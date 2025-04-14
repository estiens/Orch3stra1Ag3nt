require 'rails_helper'

RSpec.describe AgentActivityCallbackHandler do
  let(:task) { create(:task, title: "Test task", description: "Test description") }
  let(:agent_activity) { create(:agent_activity, task: task, agent_type: "TestAgent") }
  let(:handler) { described_class.new(agent_activity: agent_activity) }

  describe "#on_llm_end" do
    it "logs complete LLM call information" do
      # Create a mock response object
      response = double(
        "LLMResponse",
        model: "openai/gpt-4",
        provider: "OpenAI",
        prompt: "Test prompt",
        chat_completion: "Test response",
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
        raw_response: {
          "id" => "gen-123456",
          "model" => "openai/gpt-4",
          "choices" => [ { "message" => { "content" => "Test response" } } ],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }
      )

      # Mock the duration calculation
      allow(Process).to receive(:clock_gettime).and_return(0, 0.5)

      # Expect a call to create with all the fields
      expect(agent_activity.llm_calls).to receive(:create!).with(
        hash_including(
          provider: "OpenAI",
          model: "openai/gpt-4",
          prompt: "Test prompt",
          response: "Test response",
          prompt_tokens: 10,
          completion_tokens: 5,
          tokens_used: 15,
          request_payload: an_instance_of(String),
          response_payload: an_instance_of(String),
          duration: 0.5,
          cost: an_instance_of(Float)
        )
      )

      # Call the method
      handler.on_llm_end(response)
    end

    it "handles minimal response data gracefully" do
      # Create a minimal response with only essential fields
      minimal_response = double("MinimalResponse", chat_completion: "Test response")

      # Expect a call to create with at least the essential fields
      expect(agent_activity.llm_calls).to receive(:create!).with(
        hash_including(
          provider: "openrouter",
          model: "unknown",
          response: "Test response"
        )
      )

      # Call the method
      handler.on_llm_end(minimal_response)
    end

    it "logs debug information" do
      # Create a simple response
      response = double(
        "LLMResponse",
        model: "openai/gpt-4",
        chat_completion: "Test response",
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15
      )

      # Allow the create! call to return a mock LlmCall
      allow(agent_activity.llm_calls).to receive(:create!).and_return(double)

      # Expect a debug log
      expect(Rails.logger).to receive(:debug).with(/LLM End Recorded/)

      # Call the method
      handler.on_llm_end(response)
    end
  end

  describe "#calculate_llm_cost" do
    it "calculates correct cost based on model and tokens" do
      # Test a few different models
      expect(handler.send(:calculate_llm_cost, "openai/gpt-4", 1000, 500)).to eq(0.06)
      expect(handler.send(:calculate_llm_cost, "openai/gpt-3.5-turbo", 1000, 500)).to eq(0.00125)
      expect(handler.send(:calculate_llm_cost, "anthropic/claude-3-opus", 1000, 500)).to eq(0.0525)
      expect(handler.send(:calculate_llm_cost, "unknown-model", 1000, 500)).to eq(0.002)
    end

    it "handles models without provider prefix" do
      expect(handler.send(:calculate_llm_cost, "gpt-4", 1000, 500)).to eq(0.06)
      expect(handler.send(:calculate_llm_cost, "claude-3-opus", 1000, 500)).to eq(0.0525)
    end
  end
end
