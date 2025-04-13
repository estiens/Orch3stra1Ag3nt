require "rails_helper"

RSpec.describe "TestAgent (async via AgentJob)", type: :job do
  include ActiveJob::TestHelper

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
