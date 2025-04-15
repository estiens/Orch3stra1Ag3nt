# frozen_string_literal: true

require "concurrent"

module Embedding
  # Handles text chunking for embedding generation
  class TextChunker
    attr_reader :logger
    
    def initialize
      @logger = Embedding::Logger.new("TextChunker")
    end
    
    # Efficiently chunk text using a simpler parallel approach
    def chunk_text(text, chunk_size, chunk_overlap, content_type = nil)
      # Handle nil or empty text
      return [] if text.nil? || text.empty?
      
      # For small texts, just return the whole thing or process sequentially
      return [ text.strip ] if text.length <= chunk_size

      # For medium texts, use sequential processing - parallelism overhead isn't worth it
      if text.length < 1_000_000
        begin
          @logger.debug("Text too small for parallel chunking, using sequential chunking")
        rescue => e
          # Fallback if logging fails
          puts "Using sequential chunking for medium-sized text"
        end
        return chunk_text_segment(text, chunk_size, chunk_overlap, content_type)
      end

      # Detect content type if not provided
      content_type ||= detect_content_type(text)
      begin
        @logger.debug("Detected content type: #{content_type}")
      rescue => e
        # Fallback if logging fails
        puts "Detected content type: #{content_type}"
      end
      
      # For larger texts, use a simpler and more efficient parallel approach
      processor_count = [ Concurrent.processor_count, 1 ].max
      @logger.debug("Using #{processor_count} threads for parallel chunking")

      # Divide text into segments more efficiently
      segments = split_text_into_segments(text, processor_count, chunk_size, chunk_overlap, content_type)
      @logger.debug("Split text into #{segments.size} segments for processing")

      # Use a simple thread pool for processing
      all_chunks = process_segments_with_threads(segments, chunk_size, chunk_overlap, content_type)

      # Remove duplicates that might have been created in overlap regions
      @logger.debug("Parallel chunking completed - generated #{all_chunks.size} chunks")
      all_chunks.uniq
    end

    private

    # Split text into segments for parallel processing
    def split_text_into_segments(text, processor_count, chunk_size, chunk_overlap, content_type = nil)
      # Calculate optimal segment size based on text length and processor count
      # Aim for segments that are roughly equal in size
      target_segment_count = processor_count * 2  # Create 2x segments as processors for better load balancing
      base_segment_size = text.length / target_segment_count

      # Ensure segment size is reasonable (not too small)
      segment_size = [ base_segment_size, chunk_size * 10 ].max
      segment_overlap = chunk_size  # Smaller overlap is sufficient

      segments = []
      position = 0

      while position < text.length
        end_pos = [ position + segment_size, text.length ].min

        # Find a natural breakpoint if not at the end
        if end_pos < text.length
          # Get appropriate breakpoints based on content type
          content_type ||= detect_content_type(text)
          breakpoints = get_breakpoint_patterns(content_type)
          
          # Look for appropriate breaks near the end position
          search_window = [ 500, segment_size / 10 ].min  # Smaller search window
          search_start = [ end_pos - search_window, position ].max
          search_text = text[search_start...end_pos]

          # Try each breakpoint pattern in order
          found_break = false
          breakpoints.each do |pattern, length|
            if search_text.include?(pattern)
              offset = search_text.rindex(pattern)
              if offset
                end_pos = search_start + offset + length
                found_break = true
                break
              end
            end
          end
          
          # If no suitable break found, fall back to any newline
          if !found_break && search_text.include?("\n")
            offset = search_text.rindex("\n")
            end_pos = search_start + offset + 1 if offset
          end
        end

        # Extract segment
        segment = text[position...end_pos]
        segments << segment if segment.length > 0

        # Move position with overlap
        position = [ end_pos - segment_overlap, position + 1 ].max
      end

      segments
    end

    # Process segments using a simple thread pool
    def process_segments_with_threads(segments, chunk_size, chunk_overlap, content_type = nil)
      return [] if segments.empty?

      # Use a thread pool with a reasonable size
      pool_size = [ Concurrent.processor_count, segments.size ].min

      # Create a thread pool
      pool = Concurrent::FixedThreadPool.new(pool_size)

      # Process segments in parallel
      mutex = Mutex.new
      all_chunks = []

      # Create and submit tasks
      segments.each_with_index do |segment, idx|
        pool.post do
          begin
            # Process the segment
            start_time = Time.now
            chunks = chunk_text_segment(segment, chunk_size, chunk_overlap, content_type)
            duration = Time.now - start_time

            # Thread-safe append to results
            mutex.synchronize do
              all_chunks.concat(chunks)
            end

            @logger.debug("Thread processed segment #{idx+1}/#{segments.size} in #{duration.round(2)}s - #{chunks.size} chunks")
          rescue => e
            @logger.error("Error processing segment #{idx+1}: #{e.message}")
          end
        end
      end

      # Wait for all tasks to complete
      pool.shutdown
      pool.wait_for_termination(60)  # 60 second timeout

      all_chunks
    end

    # Optimized chunking algorithm for a single text segment
    def chunk_text_segment(text, chunk_size, chunk_overlap, content_type = nil)
      # Ensure we have a content type
      content_type ||= detect_content_type(text)
      # For very small texts, just return the whole thing
      return [ text.strip ] if text.length <= chunk_size

      chunks = []
      position = 0
      text_length = text.length

      # Choose appropriate breakpoint patterns based on content type
      breakpoints = get_breakpoint_patterns(content_type)
      
      # Adjust chunk size for code to be more conservative
      # For code, we want smaller chunks to avoid breaking important structures
      effective_chunk_size = if content_type == :code
                              (chunk_size * 0.80).to_i  # Even more conservative for code
                            else
                              chunk_size
                            end
                            
      # Set a maximum chunk size to prevent API timeouts
      max_token_estimate = effective_chunk_size / 4  # Rough estimate of tokens
      if max_token_estimate > 1024  # More conservative limit (most APIs have limits around 2048 tokens)
        effective_chunk_size = 1024 * 4  # Approximately 1024 tokens
        begin
          @logger.debug("Limiting chunk size to ~1024 tokens to prevent API timeouts")
        rescue => e
          # Continue silently if logging fails
        end
      end
      
      # Ensure minimum chunk size
      if effective_chunk_size < 100
        effective_chunk_size = 100
        begin
          @logger.debug("Enforcing minimum chunk size of 100 characters")
        rescue => e
          # Continue silently if logging fails
        end
      end

      # Track the last few chunks to detect potential infinite loops
      last_positions = []
      
      # For code, try to start at logical boundaries when possible
      if content_type == :code && position == 0
        # Look for a good starting point like a class or method definition
        first_100_chars = text[0...[100, text_length].min]
        if first_100_chars.match?(/^(class|def|function|public|private|module)/)
          # We're already at a good starting point
        elsif (match = text.match(/\n(class|def|function|public|private|module)/))
          # Jump to the first class/method definition if it exists
          position = match.begin(0) + 1
        end
      end
      
      while position < text_length
        # Find end position
        end_pos = [ position + effective_chunk_size, text_length ].min

        # Find a natural breakpoint if not at the end
        if end_pos < text_length
          # Use a more efficient approach to find breakpoints
          # For code, use a larger search window to find better breakpoints
          search_window = content_type == :code ? 
            [ 300, effective_chunk_size / 3 ].min : 
            [ 200, effective_chunk_size / 5 ].min
            
          search_start = [ end_pos - search_window, position ].max
          search_text = text[search_start...end_pos]

          # Try each breakpoint pattern in order of preference
          found_breakpoint = false
          breakpoints.each do |pattern, length|
            if (pos = search_text.rindex(pattern))
              end_pos = search_start + pos + length
              found_breakpoint = true
              break
            end
          end

          # If no breakpoint found, try different fallbacks based on content type
          if !found_breakpoint
            if content_type == :code
              # For code, try to find any character that might be a reasonable break
              if (pos = search_text.rindex(/[\s\{\}\(\);]/))
                end_pos = search_start + pos + 1
              elsif (pos = search_text.rindex(" "))
                end_pos = search_start + pos + 1
              end
            else
              # For text, spaces are reasonable fallbacks
              if (pos = search_text.rindex(" "))
                end_pos = search_start + pos + 1
              end
            end
          end
        end

        # Extract chunk and add if not empty
        chunk = text[position...end_pos].strip
        chunks << chunk if chunk.length > 0

        # Move position with overlap, ensuring forward progress
        new_position = end_pos - chunk_overlap
        
        # Ensure we make progress even with large overlaps
        if new_position <= position
          # If we're not making progress, move forward by a minimum amount
          # Use a larger step for code to avoid getting stuck on long lines
          min_step = content_type == :code ? 50 : 10
          position = position + min_step
          begin
            @logger.debug("Forced position advance by #{min_step} characters to avoid stalling")
          rescue => e
            # Continue silently if logging fails
          end
        else
          position = new_position
        end
        
        # Detect potential infinite loops
        last_positions.push(position)
        if last_positions.length > 5
          last_positions.shift
          
          # If we're oscillating around the same positions, force a larger jump
          if last_positions.uniq.length <= 2
            jump_size = [chunk_size / 2, 100].max
            position += jump_size
            begin
              @logger.warn("Detected potential infinite loop, jumping forward #{jump_size} characters")
            rescue => e
              puts "Warning: Jumping forward #{jump_size} characters to avoid infinite loop"
            end
            last_positions.clear
          end
        end
      end

      # Log chunking results
      begin
        @logger.debug("Created #{chunks.size} chunks from #{text_length} characters of #{content_type} content")
      rescue => e
        # Fallback if logging fails
        puts "Created #{chunks.size} chunks from #{text_length} characters of #{content_type} content"
      end
      
      chunks
    end

    # Detect content type based on text characteristics
    # This needs to be public so it can be called from chunk_text
    def detect_content_type(text)
      # Simple heuristic to detect code vs natural language
      code_indicators = [
        # Common syntax elements
        "{", "}", ";", "=>", "->", "!=", "==", "===", "+=", "-=", "*=", "/=", "%=",
        # Language keywords
        "def ", "class ", "function ", "import ", "public ", "private ", "protected ",
        "const ", "var ", "let ", "static ", "final ", "void ", "int ", "string ",
        "return ", "if ", "else ", "for ", "while ", "switch ", "case ", 
        # Special markers
        "#!/", "#include", "package ", "module ", "namespace ", "using ", "extends ",
        "implements ", "interface ", "@Override", "async ", "await ", "yield ",
        # Method calls and declarations
        ".map(", ".filter(", ".reduce(", ".forEach(", ".then(", ".catch(",
        # Common programming patterns
        "try {", "catch (", "throw new", "new ", "this.", "self.", "super.",
        # Additional code patterns
        "import ", "export ", "require(", "module.exports", "extends ", "implements ",
        "public class", "private class", "protected class", "interface ", "enum ",
        "struct ", "typedef ", "namespace ", "template<", "#define ", "#ifdef",
        "func ", "protocol ", "extension ", "@interface", "@implementation"
      ]
      
      sample = text[0...[5000, text.length].min]
      
      # Check for code indicators - use simple count instead of regex for performance
      code_score = code_indicators.sum { |indicator| sample.scan(indicator).count }
      
      # Check for code-like line structure (many lines starting with spaces/tabs)
      lines = sample.lines
      total_lines = [1, lines.count].max
      
      # Count indented lines (common in code)
      indented_lines = lines.count { |line| line.match?(/^\s+\S/) }
      indentation_ratio = indented_lines.to_f / total_lines
      
      # Count lines with special characters common in code
      code_char_lines = lines.count { |line| line.match?(/[{}();=<>]/) }
      code_char_ratio = code_char_lines.to_f / total_lines
      
      # Check for comment patterns
      comment_lines = lines.count { |line| line.match?(/^\s*(\/\/|#|\/\*|\*|--|\*)/) }
      comment_ratio = comment_lines.to_f / total_lines
      
      # Calculate final score
      final_score = code_score + (indentation_ratio * 10) + (code_char_ratio * 15) + (comment_ratio * 10)
      
      # Log detection metrics
      begin
        @logger.debug("Content type detection: code_score=#{code_score}, indent_ratio=#{indentation_ratio.round(2)}, " +
                     "code_char_ratio=#{code_char_ratio.round(2)}, comment_ratio=#{comment_ratio.round(2)}, " +
                     "final_score=#{final_score.round(2)}")
      rescue => e
        # Fallback if logging fails
        puts "Warning: Logger error in content detection: #{e.message}"
      end
      
      # If enough indicators present, treat as code
      if final_score > 8 || indentation_ratio > 0.3 || code_char_ratio > 0.4
        :code
      else
        :text
      end
    end

    # Get appropriate breakpoint patterns based on content type
    def get_breakpoint_patterns(content_type)
      if content_type == :code
        # For code, prioritize syntax and structural boundaries
        [
          # Block and scope boundaries with comments
          ["\n}\n\n", 4],        # End of block with paragraph break
          ["\n} // ", 6],        # End of block with inline comment
          ["\n} # ", 5],         # End of block with Ruby/Python comment
          
          # Block and scope boundaries
          ["\n}\n", 3],          # End of block with newlines
          ["}\n", 2],            # End of block with newline
          [";\n\n", 3],          # Statement end with paragraph break
          [";\n", 2],            # Statement end with newline
          ["\n\n", 2],           # Paragraph break (often between functions/methods)
          
          # Class/method/function boundaries
          ["\nclass ", 7],       # Class definition
          ["\ndef ", 5],         # Method/function definition (Ruby, Python)
          ["\nfunction ", 10],   # Function definition (JavaScript)
          ["\npublic ", 8],      # Public method (Java, C#)
          ["\nprivate ", 9],     # Private method (Java, C#)
          ["\nprotected ", 11],  # Protected method (Java, C#)
          ["\nstatic ", 8],      # Static method (Java, C#)
          ["\nasync ", 7],       # Async function (JavaScript)
          
          # Documentation and comment blocks
          ["\n/**\n", 5],        # Start of JSDoc/JavaDoc comment
          ["\n/*\n", 4],         # Start of block comment
          ["\n */\n", 5],        # End of block comment
          ["\n#\n", 3],          # Ruby/Python comment line
          
          # Common code block starters
          ["\nif ", 4],          # If statement
          ["\nelse ", 6],        # Else statement
          ["\nelif ", 6],        # Elif statement (Python)
          ["\nfor ", 5],         # For loop
          ["\nwhile ", 7],       # While loop
          ["\nswitch ", 8],      # Switch statement
          ["\ncase ", 6],        # Case statement
          ["\nreturn ", 8],      # Return statement
          
          # Indentation changes (often indicate logical blocks)
          ["\n    ", 5],         # 4-space indentation
          ["\n  ", 3],           # 2-space indentation
          ["\n\t", 2],           # Tab indentation
          
          # Statement terminators
          ["; ", 2],             # Semicolon with space
          ["} ", 2],             # Closing brace with space
          [") ", 2],             # Closing parenthesis with space
          [";\n", 2],            # Semicolon with newline
          
          # Last resort - any newline
          ["\n", 1],             # Any newline
        ]
      else
        # For natural text, prioritize semantic boundaries
        [
          ["\n\n", 2],           # Paragraph break (strongest delimiter)
          [".\n\n", 3],          # End of sentence with paragraph break
          [". ", 2],             # End of sentence with space
          [".\n", 2],            # End of sentence with newline
          ["? ", 2],             # Question mark with space
          ["! ", 2],             # Exclamation mark with space
          ["?\n", 2],            # Question mark with newline
          ["!\n", 2],            # Exclamation mark with newline
          [":\n", 2],            # Colon with newline
          ["\n- ", 3],           # List item
          ["\n* ", 3],           # Bullet point
          ["\n", 1],             # Any newline
          [": ", 2],             # Colon with space
          [", ", 2],             # Comma with space
          [") ", 2],             # Closing parenthesis with space
          ["] ", 2],             # Closing bracket with space
        ]
      end
    end
    
    # Helper method for testing in console
    def self.test_chunking(file_path, chunk_size = 512, chunk_overlap = 50, content_type = nil, show_boundaries = false, max_chunks = nil)
      begin
        text = File.read(file_path)
        chunker = new
        
        # Don't try to auto-detect content type in the class method
        # Let the instance methods handle it
        if content_type.nil?
          # Try to guess based on file extension
          content_type = case File.extname(file_path).downcase
                         when '.rb', '.js', '.py', '.java', '.c', '.cpp', '.cs', '.php', '.go', '.ts', '.swift', 
                              '.h', '.hpp', '.jsx', '.tsx', '.scala', '.kt', '.rs', '.dart', '.lua', '.pl', '.sh'
                           :code
                         when '.md', '.txt', '.rst', '.adoc', '.html', '.xml', '.json', '.csv', '.yml', '.yaml'
                           :text
                         else
                           nil # Let the instance method detect it
                         end
        end
        
        puts "File size: #{text.length} characters"
        
        start_time = Time.now
        chunks = chunker.chunk_text(text, chunk_size, chunk_overlap, content_type)
        duration = Time.now - start_time
        
        # Get the content type that was actually used (might have been auto-detected)
        actual_content_type = content_type || (chunks.empty? ? :unknown : :auto_detected)
        puts "Content processed as: #{actual_content_type}"
        
        puts "Generated #{chunks.size} chunks in #{duration.round(2)}s"
        puts "Average chunk size: #{(chunks.sum { |c| c.length } / [1, chunks.size].max).round(2)} characters"
        puts "Smallest chunk: #{chunks.map(&:length).min || 0} characters"
        puts "Largest chunk: #{chunks.map(&:length).max || 0} characters"
        
        # Visualize chunk boundaries if requested
        if show_boundaries && !chunks.empty?
          puts "\nChunk boundaries visualization:"
          visualize_chunks(text, chunks)
        end
        
        # Limit chunks if requested
        if max_chunks && chunks.size > max_chunks
          puts "Limiting output to #{max_chunks} chunks (out of #{chunks.size} total)"
          chunks = chunks.first(max_chunks)
        end
        
        # Return the chunks for further inspection
        chunks
      rescue => e
        puts "Error during chunking test: #{e.message}"
        puts e.backtrace.join("\n")
        []
      end
    end
    
    # Estimate token count for a text
    def self.estimate_tokens(text)
      return 0 if text.nil? || text.empty?
      # Rough estimate: 1 token ≈ 4 characters for English text
      # This is a very rough approximation
      (text.length / 4.0).ceil
    end
    
    # Visualize where chunks start and end in the original text
    def self.visualize_chunks(text, chunks)
      # Create a map of positions where chunks start and end
      boundaries = {}
      
      chunks.each_with_index do |chunk, i|
        # Find the start position of this chunk in the original text
        chunk_to_find = chunk.strip
        start_pos = text.index(chunk_to_find)
        
        # If we can't find the exact chunk, try a fuzzy match
        unless start_pos
          # Try with first 50 chars
          if chunk_to_find.length > 50
            prefix = chunk_to_find[0...50]
            start_pos = text.index(prefix)
          end
        end
        
        next unless start_pos # Skip if we still can't find the chunk
        
        end_pos = start_pos + chunk.length
        
        # Mark the start and end in our boundaries hash
        boundaries[start_pos] = { type: :start, index: i }
        boundaries[end_pos] = { type: :end, index: i }
      end
      
      # Sort the boundaries by position
      sorted_positions = boundaries.keys.sort
      
      # Print the text with boundary markers
      last_pos = 0
      active_chunks = []
      output = ""
      
      sorted_positions.each do |pos|
        # Add the text between the last position and this one
        if pos > last_pos
          output += text[last_pos...pos].gsub(/\n/, "↵")
        end
        
        # Add the boundary marker
        boundary = boundaries[pos]
        if boundary[:type] == :start
          active_chunks << boundary[:index]
          output += "【#{boundary[:index]}→"
        else
          active_chunks.delete(boundary[:index])
          output += "←#{boundary[:index]}】"
        end
        
        last_pos = pos
      end
      
      # Add any remaining text
      if last_pos < text.length
        output += text[last_pos..-1].gsub(/\n/, "↵")
      end
      
      # Print in chunks to avoid terminal buffer issues
      output.scan(/.{1,1000}/m).each do |chunk|
        print chunk
        sleep(0.01) # Small delay to prevent buffer issues
      end
      
      # Print any remaining text
      if last_pos < text.length
        print text[last_pos..-1].gsub(/\n/, "↵")
      end
      
      puts "\n\n"
    end
    
    # Analyze chunks for potential issues
    def self.analyze_chunks(chunks)
      return if chunks.empty?
      
      # Calculate statistics
      lengths = chunks.map(&:length)
      avg_length = lengths.sum / chunks.size
      min_length = lengths.min
      max_length = lengths.max
      std_dev = Math.sqrt(lengths.map { |l| (l - avg_length) ** 2 }.sum / chunks.size)
      
      # Check for potential issues
      issues = []
      
      # Check for very small chunks
      small_chunks = chunks.select { |c| c.length < 100 }
      if small_chunks.any?
        issues << "Found #{small_chunks.size} very small chunks (< 100 chars)"
      end
      
      # Check for very large chunks
      large_chunks = chunks.select { |c| c.length > 1000 }
      if large_chunks.any?
        issues << "Found #{large_chunks.size} very large chunks (> 1000 chars)"
      end
      
      # Check for high variance in chunk sizes
      if std_dev > avg_length * 0.5
        issues << "High variance in chunk sizes (std dev: #{std_dev.round(2)})"
      end
      
      # Check for duplicate chunks
      duplicates = chunks.group_by(&:itself).select { |_, group| group.size > 1 }
      if duplicates.any?
        issues << "Found #{duplicates.size} duplicate chunks"
      end
      
      # Check for chunks that might be cut in the middle of sentences
      bad_endings = chunks.select { |c| c.end_with?(".", ",", "and", "or", "the", "a", "an") }
      if bad_endings.any?
        issues << "Found #{bad_endings.size} chunks with potentially bad break points"
      end
      
      # Print analysis
      puts "\nChunk Analysis:"
      puts "---------------"
      puts "Total chunks: #{chunks.size}"
      puts "Average length: #{avg_length} chars"
      puts "Min length: #{min_length} chars"
      puts "Max length: #{max_length} chars"
      puts "Standard deviation: #{std_dev.round(2)}"
      
      if issues.any?
        puts "\nPotential issues:"
        issues.each { |issue| puts "- #{issue}" }
      else
        puts "\nNo significant issues detected"
      end
    end
  end
end
