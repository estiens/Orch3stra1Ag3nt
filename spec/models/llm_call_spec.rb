require 'rails_helper'

RSpec.describe LlmCall, type: :model do
  describe "associations" do
    it { should belong_to(:agent_activity) }
  end

  describe "attributes" do
    it "has the necessary fields" do
      llm_call = LlmCall.new

      # Basic fields
      expect(llm_call).to respond_to(:provider)
      expect(llm_call).to respond_to(:model)
      expect(llm_call).to respond_to(:prompt)
      expect(llm_call).to respond_to(:response)

      # Token fields
      expect(llm_call).to respond_to(:tokens_used)
      expect(llm_call).to respond_to(:prompt_tokens)
      expect(llm_call).to respond_to(:completion_tokens)

      # Payload fields
      expect(llm_call).to respond_to(:request_payload)
      expect(llm_call).to respond_to(:response_payload)

      # Metrics fields
      expect(llm_call).to respond_to(:duration)
      expect(llm_call).to respond_to(:cost)
    end
  end

  describe "factory" do
    it "creates a valid LlmCall" do
      agent_activity = create(:agent_activity)
      llm_call = build(:llm_call, agent_activity: agent_activity)
      expect(llm_call).to be_valid
    end
  end
end
