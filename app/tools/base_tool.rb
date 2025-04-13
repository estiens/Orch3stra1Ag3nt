# This file is not needed since we're using Regent::Tool directly
# The Regent::Tool class provides all the functionality we need
# If you need to extend functionality, create a module that can be included in tool classes

# If we need shared functionality across tools, we can implement it with a concern:

module ToolHelpers
  extend ActiveSupport::Concern

  # Add shared methods for tools here
  def format_response(data, success = true)
    if success
      { success: true, data: data }
    else
      { success: false, error: data }
    end
  end

  # Add other helper methods as needed
end

# To use this in a tool:
# class MyTool < Regent::Tool
#   include ToolHelpers
#   # ... rest of the tool implementation
# end
