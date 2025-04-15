# frozen_string_literal: true

module Embedding
  # Helper methods for testing embedding functionality
  class TestHelper
    # Generate a test document with random content
    def self.generate_test_document(size: 10000)
      paragraphs = []
      current_size = 0

      while current_size < size
        paragraph_size = rand(100..500)
        paragraph = generate_random_paragraph(paragraph_size)
        paragraphs << paragraph
        current_size += paragraph.length
      end

      paragraphs.join("\n\n")
    end

    # Test the chunking functionality
    def self.test_chunking(text: nil, chunk_size: 512, chunk_overlap: 25)
      text ||= generate_test_document

      chunker = Embedding::TextChunker.new
      start_time = Time.now
      chunks = chunker.chunk_text(text, chunk_size, chunk_overlap)
      duration = Time.now - start_time

      {
        original_size: text.length,
        chunk_count: chunks.size,
        average_chunk_size: chunks.sum { |c| c.length } / chunks.size.to_f,
        duration: duration,
        chunks: chunks
      }
    end

    private

    # Generate a random paragraph
    def self.generate_random_paragraph(size)
      words = %w[the quick brown fox jumps over lazy dog computer science artificial intelligence
                machine learning natural language processing vector embeddings semantic search
                transformer models attention mechanism neural networks deep learning]

      result = []
      current_size = 0

      while current_size < size
        sentence_length = rand(5..15)
        sentence = words.sample(sentence_length).join(" ") + "."
        result << sentence
        current_size += sentence.length + 1  # +1 for space
      end

      result.join(" ")
    end
  end
end
