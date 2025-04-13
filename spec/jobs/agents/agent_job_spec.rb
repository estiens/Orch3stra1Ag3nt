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
      }.to raise_error(ArgumentError, "agent_class must inherit from Regent::Agent")
    end

    it "activates a pending task" do
      expect(task.state).to eq("pending")
      described_class.new.perform(agent_class, agent_prompt, options)
      expect(task.reload.state).to eq("completed")
    end

    it "creates an agent_activity record" do
      expect {
        described_class.new.perform(agent_class, agent_prompt, options)
      }.to change(AgentActivity, :count).by(1)

      activity = AgentActivity.last
      expect(activity.agent_type).to eq("BaseAgent")
      expect(activity.task_id).to eq(task.id)
      expect(activity.status).to eq("completed")
    end

    it "runs the agent with the provided prompt" do
      described_class.new.perform(agent_class, agent_prompt, options)
      expect(agent_instance).to have_received(:run).with(agent_prompt)
    end

    it "creates a completed event when the agent completes" do
      described_class.new.perform(agent_class, agent_prompt, options)

      activity = AgentActivity.last
      event = activity.events.last
      expect(event.event_type).to eq("agent_completed")
      expect(event.data["result"]).to eq("result")
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
      allow(agent_instance).to receive(:run).and_raise(StandardError, error_message)
    end

    it "handles errors and updates the agent activity" do
      expect {
        described_class.new.perform(agent_class, agent_prompt, options)
      }.to raise_error(StandardError, error_message)

      activity = AgentActivity.last
      expect(activity.status).to eq("failed")
      expect(activity.error_message).to eq(error_message)
    end

    it "creates a failed event" do
      expect {
        described_class.new.perform(agent_class, agent_prompt, options)
      }.to raise_error(StandardError, error_message)

      activity = AgentActivity.last
      event = activity.events.last
      expect(event.event_type).to eq("agent_failed")
      expect(event.data["error"]).to eq(error_message)
    end

    it "marks the task as failed" do
      task.update(state: "active")
      expect {
        described_class.new.perform(agent_class, agent_prompt, options)
      }.to raise_error(StandardError, error_message)

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
