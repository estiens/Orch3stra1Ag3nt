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
      # For small texts, just return the whole thing or process sequentially
      return [ text.strip ] if text.length <= chunk_size

      # For medium texts, use sequential processing - parallelism overhead isn't worth it
      if text.length < 1_000_000
        @logger.debug("Text too small for parallel chunking, using sequential chunking")
        return chunk_text_segment(text, chunk_size, chunk_overlap)
      end

      # Detect content type if not provided
      content_type ||= detect_content_type(text)
      @logger.debug("Detected content type: #{content_type}")
      
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
    def chunk_text_segment(text, chunk_size, chunk_overlap, content_type = detect_content_type(text))
      # For very small texts, just return the whole thing
      return [ text.strip ] if text.length <= chunk_size

      chunks = []
      position = 0
      text_length = text.length

      # Choose appropriate breakpoint patterns based on content type
      breakpoints = get_breakpoint_patterns(content_type)

      while position < text_length
        # Find end position
        end_pos = [ position + chunk_size, text_length ].min

        # Find a natural breakpoint if not at the end
        if end_pos < text_length
          # Use a more efficient approach to find breakpoints
          # Start with a smaller search window
          search_window = [ 200, chunk_size / 5 ].min
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

          # If no breakpoint found, fall back to space
          if !found_breakpoint && (pos = search_text.rindex(" "))
            end_pos = search_start + pos + 1
          end
        end

        # Extract chunk and add if not empty
        chunk = text[position...end_pos].strip
        chunks << chunk if chunk.length > 0

        # Move position with overlap, ensuring forward progress
        new_position = end_pos - chunk_overlap
        # Ensure we make progress even with large overlaps
        position = new_position > position ? new_position : position + 1
      end

      chunks
    end

    # Detect content type based on text characteristics
    def detect_content_type(text)
      # Simple heuristic to detect code vs natural language
      code_indicators = [
        "{", "}", ";", "def ", "class ", "function ", "import ", "public ", "private ",
        "const ", "var ", "let ", "=>", "->", "#!/", "#include", "package ", "module "
      ]
      
      sample = text[0...[5000, text.length].min]
      
      # Check for code indicators
      code_score = code_indicators.sum { |indicator| sample.scan(indicator).count }
      
      # Check for code-like line structure (many lines starting with spaces/tabs)
      indented_lines = sample.lines.count { |line| line.match?(/^\s+\S/) }
      total_lines = [1, sample.lines.count].max
      indentation_ratio = indented_lines.to_f / total_lines
      
      # If enough code indicators or high indentation ratio, treat as code
      if code_score > 5 || indentation_ratio > 0.3
        :code
      else
        :text
      end
    end

    # Get appropriate breakpoint patterns based on content type
    def get_breakpoint_patterns(content_type)
      if content_type == :code
        # For code, prioritize syntax boundaries
        [
          ["\n\n", 2],           # Paragraph break
          [";\n", 2],            # End of statement with newline
          ["}\n", 2],            # Closing brace with newline
          ["{\n", 2],            # Opening brace with newline
          ["\n    ", 5],         # Indentation change
          ["\n  ", 3],           # Indentation change
          ["\n\t", 2],           # Tab indentation
          ["\n", 1],             # Any newline
          ["; ", 2],             # Semicolon with space
          ["} ", 2],             # Closing brace with space
          [") ", 2],             # Closing parenthesis with space
        ]
      else
        # For natural text, prioritize semantic boundaries
        [
          ["\n\n", 2],           # Paragraph break
          [". ", 2],             # End of sentence
          [".\n", 2],            # End of sentence with newline
          ["\n", 1],             # Line break
          [": ", 2],             # Colon with space
          [", ", 2],             # Comma with space
          [") ", 2],             # Closing parenthesis with space
          ["] ", 2],             # Closing bracket with space
        ]
      end
    end
  end
end
