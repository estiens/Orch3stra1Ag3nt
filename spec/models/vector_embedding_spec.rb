require 'rails_helper'

RSpec.describe VectorEmbedding, type: :model do
  # Helper method to generate a properly sized mock embedding vector
  def mock_embedding
    # Create an array of 384 elements (typical for modern embedding models)
    Array.new(384) { |i| i.to_f / 384 }
  end

  describe "validations" do
    it "requires content" do
      embedding = VectorEmbedding.new(content_type: "text", collection: "default")
      expect(embedding).not_to be_valid
      expect(embedding.errors[:content]).to include("can't be blank")
    end

    it "requires content_type" do
      embedding = VectorEmbedding.new(content: "test", collection: "default", content_type: nil)
      expect(embedding).not_to be_valid
      expect(embedding.errors[:content_type]).to include("can't be blank")
    end

    it "requires collection" do
      embedding = VectorEmbedding.new(content: "test", content_type: "text", collection: nil)
      expect(embedding).not_to be_valid
      expect(embedding.errors[:collection]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "belongs to task (optional)" do
      association = VectorEmbedding.reflect_on_association(:task)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be_truthy
    end

    it "belongs to project (optional)" do
      association = VectorEmbedding.reflect_on_association(:project)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be_truthy
    end
  end

  describe "scopes" do
    before do
      # Create test data for scopes
      @project1 = create(:project, name: "Test Project 1")
      @project2 = create(:project, name: "Test Project 2")
      @task1 = create(:task, project: @project1)
      
      # Create embeddings with different collections and content types
      @embedding1 = create(:vector_embedding, collection: "collection1", content_type: "text", 
                          project: @project1, task: @task1, embedding: mock_embedding)
      @embedding2 = create(:vector_embedding, collection: "collection2", content_type: "document", 
                          project: @project2, embedding: mock_embedding)
      @embedding3 = create(:vector_embedding, collection: "collection1", content_type: "code", 
                          project: @project1, embedding: mock_embedding)
    end

    it "filters by collection" do
      expect(VectorEmbedding.in_collection("collection1").count).to eq(2)
      expect(VectorEmbedding.in_collection("collection2").count).to eq(1)
    end

    it "filters by content_type" do
      expect(VectorEmbedding.by_content_type("text").count).to eq(1)
      expect(VectorEmbedding.by_content_type("document").count).to eq(1)
      expect(VectorEmbedding.by_content_type("code").count).to eq(1)
    end

    it "filters by task" do
      expect(VectorEmbedding.for_task(@task1.id).count).to eq(1)
    end

    it "filters by project" do
      expect(VectorEmbedding.for_project(@project1.id).count).to eq(2)
      expect(VectorEmbedding.for_project(@project2.id).count).to eq(1)
    end
  end

  describe ".find_similar" do
    before do
      # Mock nearest_neighbors to avoid DB vector operations
      @mock_relation = double("ActiveRecord::Relation")
      allow(@mock_relation).to receive(:in_collection).and_return(@mock_relation)
      allow(@mock_relation).to receive(:for_task).and_return(@mock_relation)
      allow(@mock_relation).to receive(:for_project).and_return(@mock_relation)
      allow(@mock_relation).to receive(:limit).and_return(@mock_relation)
      allow(@mock_relation).to receive(:count).and_return(3)
      
      allow(VectorEmbedding).to receive(:nearest_neighbors).and_return(@mock_relation)
    end

    it "calls nearest_neighbors with the query embedding" do
      query_embedding = mock_embedding
      expect(VectorEmbedding).to receive(:nearest_neighbors).with(:embedding, query_embedding, distance: "cosine")
      VectorEmbedding.find_similar(query_embedding)
    end

    it "filters by collection when specified" do
      expect(@mock_relation).to receive(:in_collection).with("test_collection")
      VectorEmbedding.find_similar(mock_embedding, collection: "test_collection")
    end

    it "filters by project_id when specified" do
      expect(@mock_relation).to receive(:for_project).with(123)
      VectorEmbedding.find_similar(mock_embedding, project_id: 123)
    end

    it "filters by task_id when specified" do
      expect(@mock_relation).to receive(:for_task).with(456)
      VectorEmbedding.find_similar(mock_embedding, task_id: 456)
    end

    it "respects the limit parameter" do
      expect(@mock_relation).to receive(:limit).with(10)
      VectorEmbedding.find_similar(mock_embedding, limit: 10)
    end

    it "uses the specified distance metric" do
      expect(VectorEmbedding).to receive(:nearest_neighbors).with(:embedding, mock_embedding, distance: "euclidean")
      VectorEmbedding.find_similar(mock_embedding, distance: "euclidean")
    end
  end

  describe ".generate_embedding", vcr: { cassette_name: "vector_embedding/generate_embedding" } do
    it "delegates to EmbeddingService" do
      embedding_service = instance_double(EmbeddingService)
      expect(EmbeddingService).to receive(:new).and_return(embedding_service)
      expect(embedding_service).to receive(:generate_embedding).with("test text").and_return(mock_embedding)
      
      result = VectorEmbedding.generate_embedding("test text")
      expect(result).to eq(mock_embedding)
    end
  end

  describe "#similarity" do
    it "calculates cosine similarity correctly" do
      embedding = VectorEmbedding.new(embedding: [1.0, 0.0, 0.0])
      
      # Same vector should have similarity 1.0
      expect(embedding.similarity([1.0, 0.0, 0.0])).to be_within(0.001).of(1.0)
      
      # Orthogonal vector should have similarity 0.0
      expect(embedding.similarity([0.0, 1.0, 0.0])).to be_within(0.001).of(0.0)
      
      # 45-degree vector should have similarity 0.707
      expect(embedding.similarity([1.0, 1.0, 0.0])).to be_within(0.001).of(0.707)
    end
  end
end
