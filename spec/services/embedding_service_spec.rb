require 'rails_helper'

RSpec.describe EmbeddingService do
  let(:service) { described_class.new(collection: "test_collection") }
  let(:sample_text) { "This is a test document for embedding generation." }
  
  describe "#initialize" do
    it "sets default collection when none provided" do
      service = described_class.new
      expect(service.collection).to eq("default")
    end
    
    it "uses provided collection" do
      service = described_class.new(collection: "custom_collection")
      expect(service.collection).to eq("custom_collection")
    end
    
    it "sets project from task if available" do
      project = create(:project)
      task = create(:task, project: project)
      service = described_class.new(task: task)
      expect(service.project).to eq(project)
    end
  end
  
  describe "#add_text" do
    before do
      # Mock the embedding generation to avoid API calls
      allow(service).to receive(:generate_embedding).and_return(Array.new(384) { rand })
    end
    
    it "returns nil for blank text" do
      expect(service.add_text("")).to be_nil
    end
    
    it "skips adding if embedding already exists" do
      allow(service).to receive(:embedding_exists?).and_return(true)
      expect(service).not_to receive(:store)
      expect(service.add_text(sample_text)).to be_nil
    end
    
    it "stores text when force is true even if it exists" do
      allow(service).to receive(:embedding_exists?).and_return(true)
      expect(service).to receive(:store).once.and_return(build(:vector_embedding))
      service.add_text(sample_text, force: true)
    end
    
    it "creates a vector embedding" do
      allow(service).to receive(:embedding_exists?).and_return(false)
      expect(service).to receive(:store).once.and_return(build(:vector_embedding))
      service.add_text(sample_text)
    end
  end
  
  describe "#generate_embedding", vcr: { cassette_name: "embedding_service/generate_embedding" } do
    it "raises error when API key is missing" do
      allow(ENV).to receive(:[]).with("HUGGINGFACE_API_TOKEN").and_return(nil)
      expect { service.generate_embedding(sample_text) }.to raise_error(/HUGGINGFACE_API_TOKEN/)
    end
    
    context "with valid API key" do
      before do
        # Skip this test if no API key is available
        skip "HUGGINGFACE_API_TOKEN not set" unless ENV["HUGGINGFACE_API_TOKEN"]
      end
      
      it "returns an array of floats" do
        embedding = service.generate_embedding(sample_text)
        expect(embedding).to be_an(Array)
        expect(embedding.first).to be_a(Float)
      end
    end
  end
  
  describe "#similarity_search" do
    let(:query) { "test query" }
    let(:embedding) { Array.new(384) { rand } }
    
    before do
      allow(service).to receive(:generate_embedding).with(query).and_return(embedding)
      allow(service).to receive(:similarity_search_by_vector).and_return([build(:vector_embedding)])
    end
    
    it "generates embedding for the query" do
      expect(service).to receive(:generate_embedding).with(query)
      service.similarity_search(query)
    end
    
    it "calls similarity_search_by_vector with the generated embedding" do
      expect(service).to receive(:similarity_search_by_vector).with(embedding, k: 5, distance: "cosine")
      service.similarity_search(query)
    end
    
    it "passes custom parameters to similarity_search_by_vector" do
      expect(service).to receive(:similarity_search_by_vector).with(embedding, k: 10, distance: "euclidean")
      service.similarity_search(query, k: 10, distance: "euclidean")
    end
  end
  
  describe "#chunk_text" do
    let(:long_text) { "This is a very long text. " * 50 }
    
    it "returns the original text if shorter than chunk size" do
      chunks = service.send(:chunk_text, "Short text", 500, 0)
      expect(chunks).to eq(["Short text"])
    end
    
    it "splits text into chunks of appropriate size" do
      chunks = service.send(:chunk_text, long_text, 100, 0)
      expect(chunks.size).to be > 1
      expect(chunks.first.length).to be <= 100
    end
    
    it "respects chunk overlap" do
      chunks = service.send(:chunk_text, long_text, 100, 20)
      # With overlap, we should have more chunks than without
      no_overlap_chunks = service.send(:chunk_text, long_text, 100, 0)
      expect(chunks.size).to be >= no_overlap_chunks.size
    end
  end
end
