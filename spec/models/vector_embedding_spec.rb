require 'rails_helper'

RSpec.describe VectorEmbedding, type: :model do
  # Helper method to generate a properly sized mock embedding vector
  def mock_embedding
    # Create an array of 1536 elements (OpenAI's embedding size)
    Array.new(1536) { |i| i.to_f / 1536 }
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

  describe ".store" do
    let(:project) { Project.create!(name: "Test Project") }
    let(:task) { project.tasks.create!(title: "Test Task") }

    it "generates embedding and creates record" do
      # Stub the embedding generation with proper size
      allow(VectorEmbedding).to receive(:generate_embedding).and_return(mock_embedding)

      embedding = VectorEmbedding.store(
        content: "Test content",
        content_type: "text",
        project: project,
        task: task,
        metadata: { test: true }
      )

      expect(embedding).to be_persisted
      expect(embedding.content).to eq("Test content")
      expect(embedding.project).to eq(project)
      expect(embedding.task).to eq(task)
      expect(embedding.metadata["test"]).to be_truthy
    end

    it "resolves project from task if not provided" do
      # Stub the embedding generation with proper size
      allow(VectorEmbedding).to receive(:generate_embedding).and_return(mock_embedding)

      embedding = VectorEmbedding.store(
        content: "Test content",
        content_type: "text",
        task: task
      )

      expect(embedding.project).to eq(project)
    end
  end

  describe ".search" do
    it "generates embedding and calls find_similar" do
      mock_embed = mock_embedding
      expect(VectorEmbedding).to receive(:generate_embedding).with("search query").and_return(mock_embed)
      expect(VectorEmbedding).to receive(:find_similar).with(
        mock_embed,
        hash_including(limit: 5, collection: "test_collection", project_id: 123)
      )

      VectorEmbedding.search(
        text: "search query",
        limit: 5,
        collection: "test_collection",
        project_id: 123
      )
    end
  end

  describe ".find_similar" do
    let(:project) { Project.create!(name: "Test Project") }

    # Create a mock relation that can be chained and responds to count
    let(:mock_relation) do
      relation = double("ActiveRecord::Relation")
      allow(relation).to receive(:in_collection).and_return(relation)
      allow(relation).to receive(:for_task).and_return(relation)
      allow(relation).to receive(:for_project).and_return(relation)
      allow(relation).to receive(:limit).and_return(relation)

      # Mock collection filtering to return specific counts
      allow(relation).to receive(:count).and_return(4) # Default count
      relation
    end

    before do
      # Mock nearest_neighbors to avoid DB vector operations
      allow(VectorEmbedding).to receive(:nearest_neighbors).and_return(mock_relation)

      # Create some test embeddings with proper size
      allow(VectorEmbedding).to receive(:generate_embedding).and_return(mock_embedding)

      3.times do |i|
        VectorEmbedding.store(
          content: "Content #{i}",
          content_type: "text",
          collection: "test_collection",
          project: project
        )
      end

      # One in a different collection
      VectorEmbedding.store(
        content: "Other collection",
        content_type: "text",
        collection: "other_collection",
        project: project
      )
    end

    it "filters by collection when specified" do
      # Set up expectations for collection filtering
      test_collection_relation = double("CollectionRelation")
      other_collection_relation = double("OtherCollectionRelation")

      allow(mock_relation).to receive(:in_collection).with("test_collection").and_return(test_collection_relation)
      allow(mock_relation).to receive(:in_collection).with("other_collection").and_return(other_collection_relation)

      allow(test_collection_relation).to receive(:limit).and_return(test_collection_relation)
      allow(other_collection_relation).to receive(:limit).and_return(other_collection_relation)

      allow(test_collection_relation).to receive(:count).and_return(3)
      allow(other_collection_relation).to receive(:count).and_return(1)

      result = VectorEmbedding.find_similar(mock_embedding, collection: "test_collection")
      expect(result.count).to eq(3)

      result = VectorEmbedding.find_similar(mock_embedding, collection: "other_collection")
      expect(result.count).to eq(1)
    end

    it "filters by project_id when specified" do
      # Create another project with embeddings
      other_project = Project.create!(name: "Other Project")
      VectorEmbedding.store(
        content: "Other project content",
        content_type: "text",
        collection: "test_collection",
        project: other_project
      )

      # Set up expectations for project filtering
      project_relation = double("ProjectRelation")
      other_project_relation = double("OtherProjectRelation")

      allow(mock_relation).to receive(:for_project).with(project.id).and_return(project_relation)
      allow(mock_relation).to receive(:for_project).with(other_project.id).and_return(other_project_relation)

      allow(project_relation).to receive(:limit).and_return(project_relation)
      allow(other_project_relation).to receive(:limit).and_return(other_project_relation)

      allow(project_relation).to receive(:count).and_return(4)
      allow(other_project_relation).to receive(:count).and_return(1)

      result = VectorEmbedding.find_similar(mock_embedding, project_id: project.id)
      expect(result.count).to eq(4) # All from first project

      result = VectorEmbedding.find_similar(mock_embedding, project_id: other_project.id)
      expect(result.count).to eq(1) # Just the one from other project
    end

    it "respects the limit parameter" do
      # Set up expectations for limit
      limited_relation = double("LimitedRelation")
      allow(mock_relation).to receive(:limit).with(2).and_return(limited_relation)
      allow(limited_relation).to receive(:count).and_return(2)

      result = VectorEmbedding.find_similar(mock_embedding, limit: 2)
      expect(result.count).to eq(2)
    end
  end

  describe ".generate_embedding" do
    it "calls OpenAI client with correct parameters" do
      # Mock the OpenAI client
      mock_client = double("OpenAI::Client")
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)

      # Mock the response
      expect(mock_client).to receive(:embeddings).with(
        parameters: {
          model: "text-embedding-ada-002",
          input: "Test text"
        }
      ).and_return({
        "data" => [ { "embedding" => mock_embedding } ]
      })

      result = VectorEmbedding.generate_embedding("Test text")
      expect(result).to eq(mock_embedding)
    end

    it "truncates long text" do
      # Mock the OpenAI client
      mock_client = double("OpenAI::Client")
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)

      # Create a very long text (> 8000 chars)
      long_text = "a" * 10000
      truncated_text = "a" * 8001 # 8000 chars + 1 (0-indexed)

      # Expect truncated text to be sent
      expect(mock_client).to receive(:embeddings).with(
        parameters: {
          model: "text-embedding-ada-002",
          input: truncated_text
        }
      ).and_return({
        "data" => [ { "embedding" => mock_embedding } ]
      })

      VectorEmbedding.generate_embedding(long_text)
    end

    it "raises error when API returns error" do
      # Mock the OpenAI client
      mock_client = double("OpenAI::Client")
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)

      # Mock error response
      expect(mock_client).to receive(:embeddings).and_return({
        "error" => { "message" => "API error" }
      })

      expect {
        VectorEmbedding.generate_embedding("Test text")
      }.to raise_error(RuntimeError, /Failed to generate embedding/)
    end
  end
end
