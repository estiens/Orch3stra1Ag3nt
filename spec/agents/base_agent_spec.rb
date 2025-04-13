require "rails_helper"

RSpec.describe BaseAgent, type: :agent do
  describe "#initialize" do
    it "initializes with a purpose" do
      agent = BaseAgent.new("Test purpose")
      expect(agent.context).to eq("Test purpose")
    end

    it "accepts a model parameter as string" do
      agent = BaseAgent.new("Test purpose", model: "deepseek/deepseek-chat-v3-0324")
      expect(agent.model).to be_a(Regent::LLM)
      expect(agent.model.model).to eq("deepseek/deepseek-chat-v3-0324")
    end

    it "accepts a model parameter as symbol" do
      agent = BaseAgent.new("Test purpose", model: :fast)
      expect(agent.model).to be_a(Regent::LLM)
      expect(agent.model.model).to eq(BaseAgent.new("Test purpose").fast_model.model)
    end

    it "accepts a model parameter as Regent::LLM instance" do
      llm = Regent::LLM.new("deepseek/deepseek-chat-v3-0324")
      agent = BaseAgent.new("Test purpose", model: llm)
      expect(agent.model).to eq(llm)
    end

    it "stores task and agent_activity if provided" do
      task = double("Task")
      activity = double("AgentActivity")
      agent = BaseAgent.new("Test purpose", task: task, agent_activity: activity)
      expect(agent.task).to eq(task)
      expect(agent.agent_activity).to eq(activity)
    end
  end

  describe ".queue_name" do
    it "returns the demodulized underscored class name as symbol" do
      expect(BaseAgent.queue_name).to eq(:base_agent)
    end
  end

  describe ".concurrency_limit" do
    it "returns the default concurrency limit" do
      expect(BaseAgent.concurrency_limit).to eq(5)
    end
  end

  describe "#session_trace" do
    let(:agent) { BaseAgent.new("Test purpose") }
    let(:session) { instance_double(Regent::Session, spans: []) }

    before do
      allow(agent).to receive(:session).and_return(session)
    end

    it "returns nil if no session exists" do
      allow(agent).to receive(:session).and_return(nil)
      expect(agent.session_trace).to be_nil
    end

    it "returns a hash with llm_calls, tool_executions, and result" do
      allow(session).to receive(:result).and_return("test result")
      allow(agent).to receive(:extract_llm_calls).and_return([])
      allow(agent).to receive(:extract_tool_executions).and_return([])

      expect(agent.session_trace).to eq(
        llm_calls: [],
        tool_executions: [],
        result: "test result"
      )
    end
  end

  describe "#extract_llm_calls", :private do
    let(:agent) { BaseAgent.new("Test purpose") }
    let(:session) { instance_double(Regent::Session) }

    it "extracts LLM calls from session spans" do
      # Create a real Span double that exposes meta as a method
      span = double("Regent::Span",
        type: Regent::Span::Type::LLM_CALL,
        arguments: { model: "test-model", message: "test message" },
        output: "test output",
        meta: { input_tokens: 10, output_tokens: 5 }
      )

      allow(session).to receive(:spans).and_return([ span ])
      allow(agent).to receive(:session).and_return(session)

      result = agent.send(:extract_llm_calls)
      expect(result).to eq([ {
        provider: "openrouter",
        model: "test-model",
        input: "test message",
        output: "test output",
        tokens: 15
      } ])
    end
  end

  describe "#extract_tool_executions", :private do
    let(:agent) { BaseAgent.new("Test purpose") }
    let(:session) { instance_double(Regent::Session) }
    let(:span) do
      instance_double(Regent::Span,
        type: Regent::Span::Type::TOOL_EXECUTION,
        arguments: { name: "test_tool", arguments: [ "arg1", "arg2" ] },
        output: "tool result"
      )
    end

    before do
      allow(agent).to receive(:session).and_return(session)
      allow(session).to receive(:spans).and_return([ span ])
    end

    it "extracts tool executions from session spans" do
      result = agent.send(:extract_tool_executions)
      expect(result).to eq([ {
        tool: "test_tool",
        args: [ "arg1", "arg2" ],
        result: "tool result"
      } ])
    end
  end
end
