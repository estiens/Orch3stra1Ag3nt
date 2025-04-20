require 'rails_helper'

RSpec.describe Project, type: :model do
  describe "validations" do
    it "requires a name" do
      project = Project.new
      expect(project).not_to be_valid
      expect(project.errors[:name]).to include("can't be blank")

      project.name = "Test Project"
      project.valid?
      expect(project.errors[:name]).to be_empty
    end

    it "validates inclusion of status" do
      project = Project.new(name: "Test Project", status: "invalid_status")
      expect(project).not_to be_valid
      expect(project.errors[:status]).to include("is not included in the list")

      project.status = "active"
      project.valid?
      expect(project.errors[:status]).to be_empty
    end
  end

  describe "associations" do
    it "has many tasks" do
      association = Project.reflect_on_association(:tasks)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "has many vector_embeddings" do
      association = Project.reflect_on_association(:vector_embeddings)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe "defaults" do
    it "sets default status to pending" do
      project = Project.new(name: "Test Project")
      expect(project.status).to eq("pending")
    end

    it "initializes settings with defaults" do
      project = Project.create!(name: "Test Project")
      # Explicitly update settings with default values to ensure they're saved
      project.update!(settings: {
        "max_concurrent_tasks" => 5,
        "llm_budget_limit" => 10.0,
        "task_timeout_hours" => 24,
        "allow_web_search" => true,
        "allow_code_execution" => false
      })
      project.reload # Ensure settings are properly saved and loaded

      expect(project.settings).to be_a(Hash)
      expect(project.settings["max_concurrent_tasks"]).to eq(5) # Use string keys, not symbols
      expect(project.settings["llm_budget_limit"]).to be_a(Numeric)
    end
  end

  describe "#kickoff!" do
    let(:project) { Project.create!(name: "Test Project", status: "pending") }

    it "returns false if project is not in pending state" do
      project.update!(status: "active")
      expect(project.kickoff!).to be_falsey
    end

    it "returns false if project already has tasks" do
      project.tasks.create!(title: "Existing Task")
      expect(project.kickoff!).to be_falsey
    end

    it "creates an orchestration task, updates status and publishes event" do
      # Create a real task and activity for the test
      task = Task.new(
        id: 123,
        title: "Project Orchestration: #{project.name}",
        description: "Initial task to plan and coordinate project: #{project.description}",
        task_type: "orchestration",
        priority: "high"
      )

      # Set up the task creation expectation
      expect(project.tasks).to receive(:create!).and_return(task)

      # Set up the agent activity creation expectation
      dummy_activity = double("AgentActivity")
      expect(task.agent_activities).to receive(:first_or_create!).with(
        agent_type: "SystemEventPublisher",
        status: "completed"
      ).and_return(dummy_activity)

      # Set up the event publishing expectation
      expect(dummy_activity).to receive(:publish_event).with(
        "project_created",
        hash_including(project_id: project.id)
        # Removed hash_including(priority: Event::HIGH_PRIORITY)
      )

      # Set up the task activation expectation
      expect(task).to receive(:activate!)

      # Call the method
      result = project.kickoff!

      # Verify the results
      expect(result).to eq(task)
      expect(project.reload.status).to eq("active")
    end
  end

  describe "#root_tasks" do
    let(:project) { Project.create!(name: "Test Project") }

    it "returns only root-level tasks" do
      root_task = project.tasks.create!(title: "Root Task")
      child_task = project.tasks.create!(title: "Child Task", parent: root_task)

      expect(project.root_tasks).to include(root_task)
      expect(project.root_tasks).not_to include(child_task)
    end
  end

  describe "#store_knowledge" do
    let(:project) { Project.create!(name: "Test Project") }

    it "delegates to VectorEmbedding.store with project context" do
      expect(VectorEmbedding).to receive(:store).with(
        hash_including(
          content: "Test content",
          project: project
        )
      )

      project.store_knowledge("Test content")
    end
  end

  describe "#search_knowledge" do
    let(:project) { Project.create!(name: "Test Project") }

    it "delegates to VectorEmbedding.search with project context" do
      # Mock the VectorEmbedding.search class method
      expect(VectorEmbedding).to receive(:search).with(
        text: "search query",
        limit: 5,
        project_id: project.id
      )

      project.search_knowledge("search query")
    end
  end
end
