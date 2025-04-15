require 'rails_helper'

RSpec.describe ToolExecutionError do
  describe '#initialize' do
    it 'creates an error with a simple message' do
      error = ToolExecutionError.new('Simple error message')
      expect(error.message).to eq('Simple error message')
      expect(error.tool_name).to be_nil
      expect(error.original_exception).to be_nil
    end

    it 'creates an error with a tool name' do
      error = ToolExecutionError.new('Error message', tool_name: 'TestTool')
      expect(error.message).to eq("Error executing tool 'TestTool': Error message")
      expect(error.tool_name).to eq('TestTool')
      expect(error.original_exception).to be_nil
    end

    it 'creates an error with an original exception' do
      original = StandardError.new('Original error')
      error = ToolExecutionError.new('Error message', original_exception: original)
      expect(error.message).to eq('Error message')
      expect(error.tool_name).to be_nil
      expect(error.original_exception).to eq(original)
    end

    it 'creates an error with both tool name and original exception' do
      original = StandardError.new('Original error')
      error = ToolExecutionError.new('Error message', tool_name: 'TestTool', original_exception: original)
      expect(error.message).to eq("Error executing tool 'TestTool': Error message")
      expect(error.tool_name).to eq('TestTool')
      expect(error.original_exception).to eq(original)
    end
  end

  describe 'inheritance' do
    it 'inherits from StandardError' do
      expect(ToolExecutionError.superclass).to eq(StandardError)
    end

    it 'can be caught as a StandardError' do
      begin
        raise ToolExecutionError.new('Test error')
      rescue StandardError => e
        expect(e).to be_a(ToolExecutionError)
      end
    end
  end
end
