require 'rails_helper'

RSpec.describe ShellTool do
  let(:tool) { described_class.new }

  describe '#initialize' do
    it 'can be instantiated' do
      expect(tool).to be_a(ShellTool)
    end
  end

  describe '#execute_shell' do
    it 'returns stdout for a valid safe command' do
      # Use a safe command for testing (echo)
      result = tool.execute_shell(command: "echo hello", working_directory: Dir.pwd)
      expect(result).to be_a(Hash)
      expect(result[:stdout]).to eq("hello")
      expect(result[:status]).to eq(0)
    end

    it 'returns an error for a non-whitelisted directory' do
      allow(ENV).to receive(:fetch).and_return("/not/allowed/path")
      result = tool.execute_shell(command: "echo test", working_directory: "/tmp")
      expect(result).to have_key(:error)
    end

    it 'raises error if command is missing' do
      expect { tool.execute_shell({}) }.to raise_error(ArgumentError)
    end
  end

  describe 'schema validation' do
    # Instead of testing the function_for method directly, test the actual behavior

    it 'requires command parameter' do
      expect { tool.execute_shell }.to raise_error(ArgumentError)

      # Mock the execution to avoid actually running commands
      allow(Open3).to receive(:capture3).and_return([ "", "", double(success?: true, exitstatus: 0) ])

      expect { tool.execute_shell(command: "echo test") }.not_to raise_error
    end

    it 'validates working_directory parameter' do
      allow(ENV).to receive(:fetch).with('SHELL_TOOL_WHITELISTED_DIRS', ShellTool::DEFAULT_WORKDIR).and_return("/safe/path")

      # Mock the execution to avoid actually running commands
      allow(Open3).to receive(:capture3).and_return([ "", "", double(success?: true, exitstatus: 0) ])

      result = tool.execute_shell(command: "echo test", working_directory: "/unsafe/path")
      expect(result).to have_key(:error)
    end
  end
end
