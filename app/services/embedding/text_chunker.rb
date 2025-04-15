# frozen_string_literal: true

require "concurrent"

module Embedding
  # Handles text chunking for embedding generation
  class TextChunker
    # Efficiently chunk text using a simpler parallel approach
    def chunk_text(text, chunk_size, chunk_overlap)
      # For small texts, just return the whole thing or process sequentially
      return [ text.strip ] if text.length <= chunk_size

      # For medium texts, use sequential processing - parallelism overhead isn't worth it
      if text.length < 1_000_000
        Rails.logger.debug("EmbeddingService: Text too small for parallel chunking, using sequential chunking")
        return chunk_text_segment(text, chunk_size, chunk_overlap)
      end

      # For larger texts, use a simpler and more efficient parallel approach
      processor_count = [ Concurrent.processor_count, 1 ].max
      Rails.logger.debug("EmbeddingService: Using #{processor_count} threads for parallel chunking")

      # Divide text into segments more efficiently
      segments = split_text_into_segments(text, processor_count, chunk_size, chunk_overlap)
      Rails.logger.debug("EmbeddingService: Split text into #{segments.size} segments for processing")

      # Use a simple thread pool for processing
      all_chunks = process_segments_with_threads(segments, chunk_size, chunk_overlap)

      # Remove duplicates that might have been created in overlap regions
      Rails.logger.debug("EmbeddingService: Parallel chunking completed - generated #{all_chunks.size} chunks")
      all_chunks.uniq
    end

    private

    # Split text into segments for parallel processing
    def split_text_into_segments(text, processor_count, chunk_size, chunk_overlap)
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
          # Look for paragraph or line breaks near the end position
          search_window = [ 500, segment_size / 10 ].min  # Smaller search window
          search_start = [ end_pos - search_window, position ].max
          search_text = text[search_start...end_pos]

          # Try to find a paragraph or line break
          if search_text.include?("\n\n")
            offset = search_text.rindex("\n\n")
            end_pos = search_start + offset + 2 if offset
          elsif search_text.include?("\n")
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
    def process_segments_with_threads(segments, chunk_size, chunk_overlap)
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
            chunks = chunk_text_segment(segment, chunk_size, chunk_overlap)
            duration = Time.now - start_time

            # Thread-safe append to results
            mutex.synchronize do
              all_chunks.concat(chunks)
            end

            Rails.logger.debug("EmbeddingService: Thread processed segment #{idx+1}/#{segments.size} in #{duration.round(2)}s - #{chunks.size} chunks")
          rescue => e
            Rails.logger.error("EmbeddingService: Error processing segment #{idx+1}: #{e.message}")
          end
        end
      end

      # Wait for all tasks to complete
      pool.shutdown
      pool.wait_for_termination(60)  # 60 second timeout

      all_chunks
    end

    # Optimized chunking algorithm for a single text segment
    def chunk_text_segment(text, chunk_size, chunk_overlap)
      # For very small texts, just return the whole thing
      return [ text.strip ] if text.length <= chunk_size

      chunks = []
      position = 0
      text_length = text.length

      # Pre-calculate breakpoint patterns for faster matching
      paragraph_break = "\n\n"
      line_break = "\n"
      sentence_end = ". "

      while position < text_length
        # Find end position
        end_pos = [ position + chunk_size, text_length ].min

        # Find a natural breakpoint if not at the end
        if end_pos < text_length
          # Use a more efficient approach to find breakpoints
          # Start with a smaller search window
          search_window = [ 80, chunk_size / 10 ].min
          search_start = [ end_pos - search_window, position ].max
          search_text = text[search_start...end_pos]

          # Check for breakpoints in order of preference
          if (pos = search_text.rindex(paragraph_break))
            end_pos = search_start + pos + 2
          elsif (pos = search_text.rindex(line_break))
            end_pos = search_start + pos + 1
          elsif (pos = search_text.rindex(sentence_end))
            end_pos = search_start + pos + 2
          elsif (pos = search_text.rindex(" "))
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
  end
end
