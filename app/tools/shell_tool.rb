require "open3"
require "pathname"

class ShellTool
  extend Langchain::ToolDefinition

  # Environment variable for whitelisted directories (comma-separated)
  WHITELISTED_DIRS_ENV_VAR = "SHELL_TOOL_WHITELISTED_DIRS".freeze
  # Default directory if none specified and whitelisting allows
  DEFAULT_WORKDIR = Rails.root.to_s

  define_function :execute_shell, description: "Executes a shell command with optional working directory." do
    property :command, type: "string", description: "The shell command to execute.", required: true
    property :working_directory, type: "string", description: "Directory to execute the command in (must be within whitelisted paths). Defaults to Rails root if allowed.", required: false
  end

  def execute_shell(command:, working_directory: nil)
    resolved_wd = resolve_working_directory(working_directory)
    whitelisted_paths = load_whitelisted_paths

    unless directory_is_whitelisted?(resolved_wd, whitelisted_paths)
      return { error: "Working directory '#{resolved_wd}' is not whitelisted. Whitelisted paths: #{whitelisted_paths.join(', ')}" }
    end

    execute_command(command, resolved_wd)
  rescue => e
    Rails.logger.error "[ShellTool] Error executing command '#{command}' in '#{resolved_wd}': #{e.message}\n#{e.backtrace.join("\n")}"
    { error: "Failed to execute command: #{e.message}" }
  end

  private

  def load_whitelisted_paths
    paths_str = ENV.fetch(WHITELISTED_DIRS_ENV_VAR, DEFAULT_WORKDIR)
    # Ensure split returns an array even if paths_str is empty or nil
    (paths_str || "").split(",")
             .map { |p| File.expand_path(p.strip) }
             .reject(&:empty?)
             .uniq
  end

  def resolve_working_directory(requested_wd)
    File.expand_path(requested_wd || DEFAULT_WORKDIR)
  end

  def directory_is_whitelisted?(directory, whitelisted_paths)
    abs_directory = Pathname.new(directory)
    whitelisted_paths.any? do |whitelisted_path|
      abs_whitelisted = Pathname.new(whitelisted_path)
      # Check if the directory is the whitelisted path or a subdirectory of it
      abs_directory.to_s.start_with?(abs_whitelisted.to_s) &&
        (abs_directory == abs_whitelisted || abs_directory.to_s[abs_whitelisted.to_s.length] == "/")
    end
  end

  def execute_command(command, working_directory)
    Rails.logger.info "[ShellTool] Executing command: #{command} in directory: #{working_directory}"

    stdout, stderr, status = Open3.capture3(command, chdir: working_directory)

    Rails.logger.info "[ShellTool] Command executed with status: #{status.exitstatus}"
    Rails.logger.debug "[ShellTool] Standard output: #{stdout.strip}" unless stdout.strip.empty?
    Rails.logger.debug "[ShellTool] Standard error: #{stderr.strip}" unless stderr.strip.empty?

    {
      stdout: stdout.strip,
      stderr: stderr.strip,
      status: status.exitstatus
    }
  end
end
