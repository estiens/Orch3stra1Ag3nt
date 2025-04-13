require 'rails_helper'

RSpec.describe VectorEmbedding, type: :model do
  describe "validations" do
    it "requires content" do
      embedding = VectorEmbedding.new(content_type: "text", collection: "default")
      expect(embedding).not_to be_valid
      expect(embedding.errors[:content]).to include("can't be blank")
    end

    it "requires content_type" do
      embedding = VectorEmbedding.new(content: "test", collection: "default")
      expect(embedding).not_to be_valid
      expect(embedding.errors[:content_type]).to include("can't be blank")
    end

    it "requires collection" do
      embedding = VectorEmbedding.new(content: "test", content_type: "text")
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
      # Stub the embedding generation
      allow(VectorEmbedding).to receive(:generate_embedding).and_return([ 0.1, 0.2, 0.3 ])

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
      # Stub the embedding generation
      allow(VectorEmbedding).to receive(:generate_embedding).and_return([ 0.1, 0.2, 0.3 ])

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
      expect(VectorEmbedding).to receive(:generate_embedding).with("search query").and_return([ 0.1, 0.2, 0.3 ])
      expect(VectorEmbedding).to receive(:find_similar).with(
        [ 0.1, 0.2, 0.3 ],
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

    before do
      # Create some test embeddings
      allow(VectorEmbedding).to receive(:generate_embedding).and_return([ 0.1, 0.2, 0.3 ])

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
      # This test is limited without actual vector operations, but we can check filter application
      result = VectorEmbedding.find_similar([ 0.1, 0.2, 0.3 ], collection: "test_collection")
      expect(result.count).to eq(3)

      result = VectorEmbedding.find_similar([ 0.1, 0.2, 0.3 ], collection: "other_collection")
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

      result = VectorEmbedding.find_similar([ 0.1, 0.2, 0.3 ], project_id: project.id)
      expect(result.count).to eq(4) # All from first project

      result = VectorEmbedding.find_similar([ 0.1, 0.2, 0.3 ], project_id: other_project.id)
      expect(result.count).to eq(1) # Just the one from other project
    end

    it "respects the limit parameter" do
      result = VectorEmbedding.find_similar([ 0.1, 0.2, 0.3 ], limit: 2)
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
        "data" => [ { "embedding" => [ 0.1, 0.2, 0.3 ] } ]
      })

      result = VectorEmbedding.generate_embedding("Test text")
      expect(result).to eq([ 0.1, 0.2, 0.3 ])
    end

    it "truncates long text" do
      # Mock the OpenAI client
      mock_client = double("OpenAI::Client")
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)

      # Create a very long text (> 8000 chars)
      long_text = "a" * 10000
      truncated_text = "a" * 8000

      # Expect truncated text to be sent
      expect(mock_client).to receive(:embeddings).with(
        parameters: hash_including(input: truncated_text)
      ).and_return({
        "data" => [ { "embedding" => [ 0.1, 0.2, 0.3 ] } ]
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
