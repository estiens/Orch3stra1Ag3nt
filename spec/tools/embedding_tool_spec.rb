require 'rails_helper'

RSpec.describe EmbeddingTool do
  let(:tool) { described_class.new }
  let(:sample_text) { "This is a test document for embedding." }
  
  describe "#add" do
    it "validates input parameters" do
      expect { tool.add(texts: []) }.to raise_error(ArgumentError, /must supply at least one text/)
    end
    
    it "handles single text input" do
      expect_any_instance_of(EmbeddingService).to receive(:add_text).once.and_return(build(:vector_embedding))
      result = tool.add(texts: sample_text)
      expect(result[:status]).to eq("success")
      expect(result[:total_count]).to eq(1)
    end
    
    it "handles array of texts" do
      expect_any_instance_of(EmbeddingService).to receive(:add_text).twice.and_return(build(:vector_embedding))
      result = tool.add(texts: [sample_text, "Another test document"])
      expect(result[:status]).to eq("success")
      expect(result[:total_count]).to eq(2)
    end
    
    it "uses chunking when chunk_size is provided" do
      expect_any_instance_of(EmbeddingService).to receive(:add_document).once.and_return([build(:vector_embedding)])
      result = tool.add(texts: sample_text, chunk_size: 100)
      expect(result[:status]).to eq("success")
    end
    
    it "validates chunking parameters" do
      expect { tool.add(texts: sample_text, chunk_size: 0) }.to raise_error(ArgumentError, /Chunk size must be greater than 0/)
      expect { tool.add(texts: sample_text, chunk_size: 100, chunk_overlap: -1) }.to raise_error(ArgumentError, /Chunk overlap must be greater than or equal to 0/)
      expect { tool.add(texts: sample_text, chunk_size: 100, chunk_overlap: 100) }.to raise_error(ArgumentError, /Chunk size must be greater than chunk overlap/)
    end
  end
  
  describe "#similarity_search" do
    before do
      allow_any_instance_of(EmbeddingService).to receive(:similarity_search).and_return([
        build(:vector_embedding, content: "Result 1"),
        build(:vector_embedding, content: "Result 2")
      ])
    end
    
    it "returns formatted results" do
      result = tool.similarity_search(query: "test query")
      expect(result[:status]).to eq("success")
      expect(result[:results].size).to eq(2)
      expect(result[:results].first).to have_key(:content)
    end
    
    it "passes parameters to embedding service" do
      expect_any_instance_of(EmbeddingService).to receive(:similarity_search).with(
        "test query", k: 10, distance: "cosine"
      )
      tool.similarity_search(query: "test query", limit: 10, distance: "cosine")
    end
  end
  
  describe "#ask" do
    before do
      allow(tool).to receive(:similarity_search).and_return({
        status: "success",
        results: [
          { content: "Relevant content 1", source_url: "url1", source_title: "title1" },
          { content: "Relevant content 2", source_url: "url2", source_title: "title2" }
        ]
      })
      
      allow(tool).to receive(:llm).and_return(
        double("llm", chat: double("response", chat_completion: "Answer to the question"))
      )
    end
    
    it "combines search results with LLM response" do
      result = tool.ask(question: "What is the meaning of life?")
      expect(result[:status]).to eq("success")
      expect(result[:answer]).to eq("Answer to the question")
      expect(result[:sources].size).to eq(2)
    end
    
    it "passes parameters to similarity search" do
      expect(tool).to receive(:similarity_search).with(
        query: "What is the meaning of life?", 
        limit: 3, 
        collection: "special"
      )
      tool.ask(question: "What is the meaning of life?", limit: 3, collection: "special")
    end
  end
end
