require 'rails_helper'

RSpec.describe Langchain::LLM::OpenRouter do
  let(:api_key) { "test_api_key" }
  let(:open_router) { described_class.new(api_key: api_key) }

  describe "initialization" do
    it "sets default values" do
      expect(open_router.defaults[:temperature]).to eq(0.0)
      expect(open_router.defaults[:chat_model]).to eq("openrouter/auto")
      expect(open_router.defaults[:embedding_model]).to eq("openrouter/auto")
    end

    it "allows overriding defaults" do
      custom_router = described_class.new(
        api_key: api_key,
        default_options: {
          temperature: 0.7,
          chat_model: "openai/gpt-4"
        }
      )

      expect(custom_router.defaults[:temperature]).to eq(0.7)
      expect(custom_router.defaults[:chat_model]).to eq("openai/gpt-4")
      expect(custom_router.defaults[:embedding_model]).to eq("openrouter/auto") # Not overridden
    end
  end

  describe "#chat" do
    let(:messages) { [ { role: "user", content: "Hello" } ] }
    let(:response_body) do
      {
        "id" => "gen-123456",
        "model" => "openai/gpt-4",
        "provider" => "OpenAI",
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Hi there!"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        }
      }
    end

    before do
      # Mock HTTParty to avoid actual API calls
      allow(HTTParty).to receive(:post).and_return(
        double("HTTPartyResponse", code: 200, body: response_body.to_json)
      )
    end

    it "makes API request with correct parameters" do
      expect(HTTParty).to receive(:post).with(
        "https://openrouter.ai/api/v1/chat/completions",
        hash_including(
          headers: hash_including(
            "Content-Type" => "application/json",
            "Authorization" => "Bearer test_api_key"
          ),
          body: /"model":"openrouter\/auto".*"messages":\[.*"role":"user".*"content":"Hello"/
        )
      )

      open_router.chat(messages: messages)
    end

    it "stores the request payload" do
      open_router.chat(messages: messages)
      expect(open_router.last_request_payload).to be_present
      expect(open_router.last_request_payload[:messages]).to eq(messages)
    end

    it "enhances response with metadata" do
      response = open_router.chat(messages: messages)
      expect(response.raw_response).to include("_metadata")
      expect(response.raw_response["_metadata"]).to include("duration")
      expect(response.raw_response["_metadata"]).to include("request_time")
    end

    it "returns a properly structured response object" do
      response = open_router.chat(messages: messages)

      expect(response).to be_a(Langchain::LLM::OpenRouterResponse)
      expect(response.chat_completion).to eq("Hi there!")
      expect(response.model).to eq("openai/gpt-4")
      expect(response.provider).to eq("OpenAI")
      expect(response.prompt_tokens).to eq(10)
      expect(response.completion_tokens).to eq(5)
      expect(response.total_tokens).to eq(15)
      expect(response.id).to eq("gen-123456")
      expect(response.finish_reason).to eq("stop")
    end
  end

  describe "error handling" do
    it "raises an error for non-200 responses" do
      allow(HTTParty).to receive(:post).and_return(
        double("HTTPartyResponse", code: 400, body: { error: "Bad request" }.to_json)
      )

      expect {
        open_router.chat(messages: [ { role: "user", content: "Hello" } ])
      }.to raise_error(/OpenRouter API error/)
    end
  end
end
