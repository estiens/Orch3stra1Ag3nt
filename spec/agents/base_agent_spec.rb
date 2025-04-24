require "rails_helper"

RSpec.describe BaseAgent do
  let(:purpose) { "Testing agent functionality" }
  let(:task) { create(:task, title: "Test task", description: "Test description") }
  let(:agent_activity) { create(:agent_activity, task: task, agent_type: "BaseAgent") }

  describe "initialization" do
    it "initializes with required parameters" do
      agent = described_class.new(purpose: purpose)
      expect(agent.purpose).to eq(purpose)
      expect(agent.tools).to eq(described_class.registered_tools)
      expect(agent.llm).to be_a(Langchain::LLM::OpenRouter)
    end

    it "accepts optional parameters" do
      tools = [ { name: :test_tool, description: "Test tool", block: -> { } } ]
      llm = double("LLM")

      agent = described_class.new(
        purpose: purpose,
        tools: tools,
        llm: llm,
        task: task,
        agent_activity: agent_activity
      )

      expect(agent.purpose).to eq(purpose)
      expect(agent.tools).to eq(tools)
      expect(agent.llm).to eq(llm)
      expect(agent.task).to eq(task)
      expect(agent.agent_activity).to eq(agent_activity)
    end
  end

  describe "tool definition and execution" do
    let(:agent) { described_class.new(purpose: purpose, agent_activity: agent_activity) }

    before do
      # Define a test tool class
      class TestAgent < BaseAgent
        tool :add_numbers, "Add two numbers together" do |a, b|
          a + b
        end
      end
    end

    after do
      # Clean up the test class
      Object.send(:remove_const, :TestAgent) if Object.const_defined?(:TestAgent)
    end

    it "registers tools properly" do
      expect(TestAgent.registered_tools.size).to eq(1)
      expect(TestAgent.registered_tools.first[:name]).to eq(:add_numbers)
      expect(TestAgent.registered_tools.first[:description]).to eq("Add two numbers together")
      expect(TestAgent.registered_tools.first[:block]).to be_a(Proc)
    end

    it "executes tools and logs the execution" do
      test_agent = TestAgent.new(purpose: purpose, agent_activity: agent_activity)

      # Allow EventService.publish to be called (spying)
      allow(EventService).to receive(:publish).and_return(instance_double(BaseEvent))

      result = test_agent.execute_tool(:add_numbers, 2, 3)

      # Verify publish was called afterwards
      expect(EventService).to have_received(:publish).at_least(:once)

      expect(result).to eq(5)
      expect(test_agent.session_data[:tool_executions].size).to eq(1)
      expect(test_agent.session_data[:tool_executions].first[:tool]).to eq(:add_numbers)
      expect(test_agent.session_data[:tool_executions].first[:args]).to eq([ 2, 3 ])
      expect(test_agent.session_data[:tool_executions].first[:result]).to eq(5)
    end

    it "raises an error for non-existent tools" do
      expect {
        agent.execute_tool(:non_existent_tool)
      }.to raise_error(/Tool not found/)
    end

    it "handles errors in tool execution" do
      class ErrorToolAgent < BaseAgent
        tool :failing_tool, "A tool that fails" do
          raise "Tool execution failed"
        end
      end

      error_agent = ErrorToolAgent.new(purpose: purpose, agent_activity: agent_activity)

      # Expect at least one create event (for the started event)
      # Expect EventService.publish to be called (simpler check)
      expect(EventService).to receive(:publish).at_least(:once).and_return(instance_double(BaseEvent))

      expect {
        error_agent.execute_tool(:failing_tool)
      }.to raise_error(ToolExecutionError, /Tool execution failed/)

      expect(error_agent.session_data[:tool_executions].size).to eq(1)
      expect(error_agent.session_data[:tool_executions].first[:error]).to be_a(ToolExecutionError)

      Object.send(:remove_const, :ErrorToolAgent)
    end
  end

  describe "run method" do
    let(:agent) { described_class.new(purpose: purpose, agent_activity: agent_activity) }

    it "calls lifecycle hooks and returns default message" do
      expect(agent).to receive(:before_run).with("test input")
      expect(agent).to receive(:after_run)

      result = agent.run("test input")

      expect(result).to eq("No operation performed by BaseAgent.")
      expect(agent.session_data[:output]).to eq("No operation performed by BaseAgent.")
    end

    it "handles errors during run" do
      expect(agent).to receive(:before_run)
      expect(agent).to receive(:handle_run_error)

      allow(agent).to receive(:after_run).and_raise(StandardError.new("Run failed"))

      expect {
        agent.run("test input")
      }.to raise_error(StandardError, "Run failed")
    end
  end

  describe "lifecycle hooks" do
    let(:agent) { described_class.new(purpose: purpose, agent_activity: agent_activity) }

    it "updates agent activity status in before_run" do
      expect(agent_activity).to receive(:update).with(status: "running")
      agent.before_run("test input")
    end

    it "updates agent activity status in after_run" do
      expect(agent_activity).to receive(:update)
      expect(agent).to receive(:persist_tool_executions)
      agent.after_run("test result")
    end

    it "marks agent activity as failed in handle_run_error" do
      error = StandardError.new("Test error")
      expect(agent_activity).to receive(:mark_failed).with("Test error")
      expect(agent).to receive(:persist_tool_executions)
      agent.handle_run_error(error)
    end
  end

  describe "LLM interaction", :vcr do
    let(:agent) { described_class.new(purpose: purpose, agent_activity: agent_activity) }

    it "logs direct LLM calls with all fields" do
      prompt = "Hello, world!"
      llm_response = double(
        "LLMResponse",
        model: "openai/gpt-4",
        provider: "OpenAI",
        chat_completion: "Hi there!",
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
        raw_response: {
          "id" => "gen-123456",
          "model" => "openai/gpt-4",
          "choices" => [ { "message" => { "content" => "Hi there!" } } ],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }
      )

      # Mock the duration calculation
      allow(Process).to receive(:clock_gettime).and_return(0, 0.5)

      # Use allow instead of expect to be more flexible with the implementation
      expect(agent_activity.llm_calls).to receive(:create!).with(
        hash_including(
          provider: "OpenAI",
          model: "openai/gpt-4",
          prompt_id: nil, # Use prompt_id instead of prompt
          response: "Hi there!",
          prompt_tokens: 10,
          completion_tokens: 5,
          tokens_used: 15,
          cost: 0.0006, # Add expectation for cost
          duration: 0.0, # Add expectation for duration
          request_payload: "null", # Add expectation for request_payload
          response_payload: "{\"id\":\"gen-123456\",\"model\":\"openai/gpt-4\",\"choices\":[{\"message\":{\"content\":\"Hi there!\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}" # Add expectation for response_payload
        )
      )

      agent.send(:log_direct_llm_call, prompt, llm_response)
    end

    it "calculates correct cost based on model and tokens" do
      # Test a few different models
      expect(agent.send(:calculate_llm_cost, "openai/gpt-4", 1000, 500)).to eq(0.06)
      expect(agent.send(:calculate_llm_cost, "openai/gpt-3.5-turbo", 1000, 500)).to eq(0.00125)
      expect(agent.send(:calculate_llm_cost, "anthropic/claude-3-opus", 1000, 500)).to eq(0.0525)
      expect(agent.send(:calculate_llm_cost, "unknown-model", 1000, 500)).to eq(0.002)
    end

    it "handles missing or partial response data gracefully" do
      prompt = "Test prompt"
      minimal_response = instance_double("MinimalResponse", chat_completion: "Test response")

      # Expect llm_calls.create! to be called with the correct arguments (updated for new schema)
      expect(agent_activity.llm_calls).to receive(:create!).with(hash_including(
        provider: "openrouter",
        model: "unknown",
        prompt_id: nil, # Expect prompt_id instead of prompt
        response: "Test response",
        prompt_tokens: 0, # Should default to 0 if nil
        completion_tokens: 0, # Should default to 0 if nil
        tokens_used: 0, # Should default to 0 if nil
        cost: 0.0, # Should default to 0.0 if nil
        duration: anything, # Check duration exists
        request_payload: "null", # Should default to "null" if nil
        response_payload: "null" # Should default to "null" if nil
      ))

      # Simulate a response object that might be missing some methods by allowing them to return nil
      allow(minimal_response).to receive(:model).and_return(nil)
      allow(minimal_response).to receive(:provider).and_return(nil)
      allow(minimal_response).to receive(:prompt_tokens).and_return(nil)
      allow(minimal_response).to receive(:completion_tokens).and_return(nil)
      allow(minimal_response).to receive(:total_tokens).and_return(nil)
      allow(minimal_response).to receive(:raw_response).and_return(nil)

      # Use a hash for the prompt to test prompt_id assignment
      prompt_hash = { content: "Test prompt", prompt: nil } # No prompt object

      agent.send(:log_direct_llm_call, prompt_hash, minimal_response)
    end
  end

  describe "queue management" do
    it "returns the correct queue name" do
      expect(described_class.queue_name).to eq(:base_agent)
    end

    it "returns the correct default concurrency limit" do
      expect(described_class.concurrency_limit).to eq(5)
    end

    it "enqueues jobs with the correct parameters" do
      prompt = "Test prompt"
      options = { task_id: task.id }

      expect(described_class).to receive(:with_concurrency_control).and_yield
      expect(Agents::AgentJob).to receive(:set).with(queue: :base_agent).and_return(Agents::AgentJob)
      expect(Agents::AgentJob).to receive(:perform_later).with("BaseAgent", prompt, options)

      described_class.enqueue(prompt, options)
    end

    it "maps priority strings to numeric values" do
      expect(described_class.map_priority_string_to_numeric("high")).to eq(0)
      expect(described_class.map_priority_string_to_numeric("normal")).to eq(10)
      expect(described_class.map_priority_string_to_numeric("low")).to eq(20)
      expect(described_class.map_priority_string_to_numeric("invalid")).to be_nil
    end
  end
end
