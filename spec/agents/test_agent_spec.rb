require "rails_helper"

RSpec.describe Agents::TestAgent, type: :model do
  it "runs llm_echo tool and gets an LLM response (VCR, real OpenRouter call)" do
    VCR.use_cassette("agents/openrouter_llm_direct") do
      agent = described_class.new("Test agent for synchronous spec", model: REGENT_MODEL_DEFAULTS[:fast])
      result = agent.run("llm_echo: Hello from TestAgent!")
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  it "returns the correct queue_name" do
    expect(described_class.queue_name).to eq(:test_agent)
  end
end
