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
      effective_chunk_size = content_type == :code ? (chunk_size * 0.9).to_i : chunk_size

      # Track the last few chunks to detect potential infinite loops
      last_positions = []
      
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
        "try {", "catch (", "throw new", "new ", "this.", "self.", "super."
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
          
          # Common code block starters
          ["\nif ", 4],          # If statement
          ["\nfor ", 5],         # For loop
          ["\nwhile ", 7],       # While loop
          ["\nswitch ", 8],      # Switch statement
          
          # Indentation changes (often indicate logical blocks)
          ["\n    ", 5],         # 4-space indentation
          ["\n  ", 3],           # 2-space indentation
          ["\n\t", 2],           # Tab indentation
          
          # Statement terminators
          ["; ", 2],             # Semicolon with space
          ["} ", 2],             # Closing brace with space
          [") ", 2],             # Closing parenthesis with space
          
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
    def self.test_chunking(file_path, chunk_size = 512, chunk_overlap = 50, content_type = nil)
      begin
        text = File.read(file_path)
        chunker = new
        content_type ||= chunker.detect_content_type(text)
        puts "Content detected as: #{content_type}"
        puts "File size: #{text.length} characters"
        
        start_time = Time.now
        chunks = chunker.chunk_text(text, chunk_size, chunk_overlap, content_type)
        duration = Time.now - start_time
        
        puts "Generated #{chunks.size} chunks in #{duration.round(2)}s"
        puts "Average chunk size: #{(chunks.sum { |c| c.length } / [1, chunks.size].max).round(2)} characters"
        puts "Smallest chunk: #{chunks.map(&:length).min} characters"
        puts "Largest chunk: #{chunks.map(&:length).max} characters"
        
        # Return the chunks for further inspection
        chunks
      rescue => e
        puts "Error during chunking test: #{e.message}"
        puts e.backtrace.join("\n")
        []
      end
    end
  end
end
