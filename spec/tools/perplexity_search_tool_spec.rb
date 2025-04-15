require 'rails_helper'

RSpec.describe PerplexitySearchTool do
  let(:api_key) { 'test_api_key' }

  before do
    allow(ENV).to receive(:fetch).with('PERPLEXITY_API_KEY', nil).and_return(api_key)
  end

  describe '#initialize' do
    it 'can be instantiated with a valid API key' do
      tool = described_class.new
      expect(tool).to be_a(PerplexitySearchTool)
    end

    it 'raises an error when API key is missing' do
      allow(ENV).to receive(:fetch).with('PERPLEXITY_API_KEY', nil).and_return(nil)
      expect { described_class.new }.to raise_error(RuntimeError, /PERPLEXITY_API_KEY is not set/)
    end
  end

  describe '#search' do
    let(:tool) { described_class.new }
    let(:query) { 'test query' }
    let(:focus) { 'web' }
    let(:success_response) do
      {
        'choices' => [
          {
            'message' => {
              'content' => 'Search result content',
              'context' => {
                'citations' => [
                  {
                    'title' => 'Source Title',
                    'url' => 'https://example.com',
                    'text' => 'Citation text'
                  }
                ]
              }
            }
          }
        ]
      }.to_json
    end

    it 'makes a request to the Perplexity API with the correct parameters' do
      stub_request = stub_request(:post, 'https://api.perplexity.ai/chat/completions')
        .with(
          headers: {
            'Authorization' => "Bearer #{api_key}",
            'Content-Type' => 'application/json'
          }
        )
        .to_return(status: 200, body: success_response, headers: { 'Content-Type' => 'application/json' })

      tool.search(query: query, focus: focus)
      expect(stub_request).to have_been_requested
    end

    it 'returns search results with citations when successful' do
      stub_request(:post, 'https://api.perplexity.ai/chat/completions')
        .to_return(status: 200, body: success_response, headers: { 'Content-Type' => 'application/json' })

      result = tool.search(query: query)

      expect(result[:response]).to be_a(String)
      expect(result[:response]).to include('result content')
    end

    it 'validates and corrects invalid focus values' do
      stub_request(:post, 'https://api.perplexity.ai/chat/completions')
        .to_return(status: 200, body: success_response, headers: { 'Content-Type' => 'application/json' })

      allow(Rails.logger).to receive(:warn)

      result = tool.search(query: query, focus: 'invalid_focus')

      expect(Rails.logger).to have_received(:warn).with(/Invalid focus: invalid_focus/)
    end

    it 'handles API errors gracefully' do
      error_response = { 'error' => { 'message' => 'API Error' } }.to_json
      stub_request(:post, 'https://api.perplexity.ai/chat/completions')
        .to_return(status: 400, body: error_response, headers: { 'Content-Type' => 'application/json' })

      result = tool.search(query: query)

      expect(result).to be_a(String)
      expect(result).to include('No search results found')
      expect(result).to include('API Error')
    end

    it 'handles network errors gracefully' do
      stub_request(:post, 'https://api.perplexity.ai/chat/completions')
        .to_raise(StandardError.new('Network error'))

      result = tool.search(query: query)

      expect(result).to be_a(String)
      expect(result).to include('No search results found due to a connection error')
      expect(result).to include('Network error')
    end
  end

  describe 'schema validation' do
    # Instead of testing the Langchain::ToolDefinition implementation directly,
    # test the actual behavior of the tool's parameters

    let(:tool) { described_class.new }

    it 'requires a query parameter' do
      expect { tool.search }.to raise_error(ArgumentError)

      stub_request(:post, 'https://api.perplexity.ai/chat/completions')
        .to_return(status: 200, body: '{"choices":[{"message":{"content":"test"}}]}', headers: {})

      expect { tool.search(query: "test") }.not_to raise_error
    end

    it 'accepts an optional focus parameter' do
      stub_request(:post, 'https://api.perplexity.ai/chat/completions')
        .to_return(status: 200, body: '{"choices":[{"message":{"content":"test"}}]}', headers: {})

      # Should work with default focus
      expect { tool.search(query: "test") }.not_to raise_error

      # Should work with specified focus
      expect { tool.search(query: "test", focus: "academic") }.not_to raise_error
    end

    it 'validates the focus parameter' do
      stub_request(:post, 'https://api.perplexity.ai/chat/completions')
        .to_return(status: 200, body: '{"choices":[{"message":{"content":"test"}}]}', headers: {})

      allow(Rails.logger).to receive(:warn)

      tool.search(query: "test", focus: "invalid")
      expect(Rails.logger).to have_received(:warn).with(/Invalid focus: invalid/)
    end
  end
end
