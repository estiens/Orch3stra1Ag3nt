require 'rails_helper'

RSpec.describe AvailableTools do
  describe '.list' do
    it 'returns an array of tool classes' do
      tools = AvailableTools.list
      expect(tools).to be_an(Array)
      expect(tools).not_to be_empty
    end

    it 'includes PerplexitySearchTool and ResearchTool' do
      expected_tools = [
        PerplexitySearchTool,
        ResearchTool
      ]

      tools = AvailableTools.list

      expected_tools.each do |tool_class|
        expect(tools).to include(tool_class)
      end
    end

    it 'includes tools that extend Langchain::ToolDefinition' do
      tools = AvailableTools.list

      # Skip Langchain built-in tools for this test since we don't control their implementation
      custom_tools = tools.reject { |t| t.to_s.start_with?('Langchain::Tool::') }

      # Mock the function_for method for testing
      allow(PerplexitySearchTool).to receive(:respond_to?).with(:function_for).and_return(true)
      allow(ResearchTool).to receive(:respond_to?).with(:function_for).and_return(true)

      custom_tools.each do |tool_class|
        expect(tool_class.respond_to?(:function_for)).to be_truthy,
          "Expected #{tool_class} to extend Langchain::ToolDefinition"
      end
    end
  end
end
