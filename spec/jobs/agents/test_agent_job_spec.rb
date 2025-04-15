require "rails_helper"

RSpec.describe "TestAgent (async via AgentJob)", type: :job do
  include ActiveJob::TestHelper

  before do
    # Stub the AgentSpawningService to avoid actual spawning
    allow(AgentSpawningService).to receive(:spawn_for_task).and_return(true)
    allow(AgentSpawningService).to receive(:spawn_for_event).and_return(true)
    
    # Stub the enqueue_for_processing method to avoid spawning agents in tests
    allow_any_instance_of(Task).to receive(:enqueue_for_processing).and_return(true)
  end

  it "performs an OpenRouter LLM completion via Regent (end-to-end with VCR)" do
    VCR.use_cassette("agents/openrouter_llm") do
      begin
        perform_enqueued_jobs do
          task = Task.create!(title: "Test task for agent job", state: "pending")
          Agents::AgentJob.set(queue: Agents::TestAgent.queue_name).perform_later(
            "Agents::TestAgent",
            "llm_echo: Hello from TestAgent!",
            { model: :fast, task_id: task.id }
          )
        end
      rescue => e
        puts "\n--- Exception Raised in TestAgentJob: ---"
        puts "#{e.class}: #{e.message}"
        puts e.backtrace.join("\n")
        raise
      end
    end
  end
end
