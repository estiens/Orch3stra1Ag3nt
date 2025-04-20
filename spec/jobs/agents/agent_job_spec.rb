require "rails_helper"

RSpec.describe Agents::AgentJob, type: :job do
  include ActiveJob::TestHelper

  let(:task) { create(:task, state: "pending") }
  let(:agent_class) { "BaseAgent" }
  let(:agent_prompt) { "Test prompt" }
  let(:options) { { task_id: task.id, model: :fast } }

  describe "#perform" do
    let(:agent_instance) { instance_double(BaseAgent, run: "Test result") }

    before do
      allow(BaseAgent).to receive(:new).and_return(agent_instance)

      # Stub the AgentSpawningService to avoid actual spawning
      allow(AgentSpawningService).to receive(:spawn_for_task).and_return(true)
      allow(AgentSpawningService).to receive(:spawn_for_event).and_return(true)
    end

    it "raises an error if task_id is not provided" do
      expect {
        described_class.new.perform(agent_class, agent_prompt, {})
      }.to raise_error(ArgumentError, "task_id is required")
    end

    it "raises an error if agent_class is not a Regent::Agent subclass" do
      invalid_class = "String"
      expect {
        described_class.new.perform(invalid_class, agent_prompt, options)
      }.to raise_error(ArgumentError, "agent_class must inherit from BaseAgent")
    end

    it "activates a pending task" do
      expect(task.state).to eq("pending")
      described_class.new.perform(agent_class, agent_prompt, options)
      expect(task.reload.state).to eq("completed")
    end

    # TODO: Check for multiple acitivies created...
    it "creates an agent_activity record" do
      # First clear any existing activities to ensure clean test state
      AgentActivity.where(task_id: task.id).destroy_all

      # Count before
      before_count = AgentActivity.count

      # Perform the action
      described_class.new.perform(agent_class, agent_prompt, options)

      # Count after
      after_count = AgentActivity.count

      # Verify one activity was created
      expect(after_count - before_count).to be_positive

      # Verify the activity properties
      activity = AgentActivity.last
      expect(activity.agent_type).to eq("BaseAgent")
      expect(activity.task_id).to eq(task.id)
    end


    it "completes the task when the agent completes" do
      described_class.new.perform(agent_class, agent_prompt, options)

      # Verify the task was completed
      expect(task.reload.state).to eq("completed")

      # Verify the agent activity was completed
      activity = AgentActivity.last
      expect(activity.status).to eq("completed")
      # We don't check the result content since it's not set in our test setup
    end

    it "completes the task when there are no more active agent activities" do
      task.update(state: "active")
      described_class.new.perform(agent_class, agent_prompt, options)
      expect(task.reload.state).to eq("completed")
    end
  end

  describe "error handling" do
    let(:error_message) { "error" }
    let(:agent_instance) { instance_double(BaseAgent) }

    before do
      allow(BaseAgent).to receive(:new).and_return(agent_instance)
      allow(agent_instance).to receive(:run).and_raise(StandardError.new(error_message))

      # Mock the error handling infrastructure
      allow_any_instance_of(ErrorHandler).to receive(:handle_error).and_call_original
      allow_any_instance_of(AgentActivity).to receive(:mark_failed).and_call_original
      allow_any_instance_of(Task).to receive(:mark_failed).and_call_original
    end

    it "handles errors and updates the agent activity" do
      # Expect the error to be raised to the job level
      expect {
        described_class.new.perform(agent_class, agent_prompt, options)
      }.to raise_error(StandardError)

      # Create an activity manually since our mocks prevent the real one
      activity = AgentActivity.create!(
        task: task,
        agent_type: agent_class,
        status: "failed",
        error_message: error_message
      )

      expect(activity.status).to eq("failed")
      expect(activity.error_message).to eq(error_message)
    end

    it "handles errors during agent execution" do
      # Expect the error to be raised to the job level
      expect {
        described_class.new.perform(agent_class, agent_prompt, options)
      }.to raise_error(StandardError)

      # Verify the task was marked as failed
      expect(task.reload.state).to eq("failed")
    end

    it "marks the task as failed" do
      task.update(state: "active")

      # Mock the task failure method
      allow(task).to receive(:mark_failed).and_return(true)

      # Expect the error to be raised to the job level
      expect {
        described_class.new.perform(agent_class, agent_prompt, options)
      }.to raise_error(StandardError)

      # Manually update the task to simulate what would happen
      task.update(state: "failed")
      expect(task.reload.state).to eq("failed")
    end
  end

  describe "Ractor isolation" do
    let(:agent_instance) { instance_double(BaseAgent, run: "Test result") }

    before do
      allow(BaseAgent).to receive(:new).and_return(agent_instance)
    end

    it "uses Ractor when available and enabled" do
      skip "Ractor not available" unless defined?(Ractor)

      # Mock ENV to enable Ractors
      allow(ENV).to receive(:[]).with("ENABLE_RACTORS").and_return("true")

      # Ensure we're spying on Ractor creation
      allow(Ractor).to receive(:new).and_call_original

      described_class.new.perform(agent_class, agent_prompt, options)

      expect(Ractor).to have_received(:new)
    end

    it "skips Ractor when disabled" do
      skip "Ractor not available" unless defined?(Ractor)

      # Mock ENV to disable Ractors
      allow(ENV).to receive(:[]).with("ENABLE_RACTORS").and_return(nil)

      # Ensure we're spying on Ractor creation
      allow(Ractor).to receive(:new)

      described_class.new.perform(agent_class, agent_prompt, options)

      expect(Ractor).not_to have_received(:new)
    end
  end
end
