require 'rails_helper'

RSpec.describe WebScraperTool do
  let(:tool) { described_class.new }

  describe '#initialize' do
    it 'can be instantiated' do
      expect(tool).to be_a(WebScraperTool)
    end
  end

  describe '#scrape' do
    it 'returns an error for an invalid URL' do
      result = tool.scrape(url: "not_a_url")
      expect(result).to be_a(Hash)
      expect(result[:error]).to match(/Invalid URL/)
    end

    # Network tests are flaky in CI, so stub Mechanize for a valid case
    it 'returns structured content for a valid url', :aggregate_failures do
      valid_url = "https://example.com"
      fake_page = double('page',
        title: "Example Domain",
        search: double('search', to_html: "<h1>Example Domain</h1>", text: "Example Domain"),
        body: "<h1>Example Domain</h1>",
        links: []
      )
      allow_any_instance_of(WebScraperTool).to receive(:configure_mechanize_agent).and_return(double(get: fake_page))
      result = tool.scrape(url: valid_url)
      expect(result).to be_a(Hash)
      expect(result[:content]).to include("Example Domain")
      expect(result[:url]).to eq(valid_url)
      expect(result[:title]).to eq("Example Domain")
    end

    it 'raises error if url is missing' do
      expect { tool.scrape({}) }.to raise_error(ArgumentError)
    end
  end

  describe 'schema validation' do
    # Instead of testing the function_for method directly, test the actual behavior

    it 'requires url parameter' do
      expect { tool.scrape }.to raise_error(ArgumentError)
      expect { tool.scrape({}) }.to raise_error(ArgumentError)

      # Invalid URL should return error but not raise exception
      result = tool.scrape(url: "not_a_url")
      expect(result).to be_a(Hash)
      expect(result[:error]).to match(/Invalid URL/)
    end

    it 'accepts optional parameters' do
      # Create a fake page for testing
      valid_url = "https://example.com"
      fake_page = double('page',
        title: "Example Domain",
        search: double('search', to_html: "<h1>Example Domain</h1>", text: "Example Domain"),
        body: "<h1>Example Domain</h1>",
        links: []
      )
      allow_any_instance_of(WebScraperTool).to receive(:configure_mechanize_agent).and_return(double(get: fake_page))

      # Test with optional parameters
      expect {
        tool.scrape(url: valid_url, selector: "h1", extract_type: "html")
      }.not_to raise_error
    end
  end
end
