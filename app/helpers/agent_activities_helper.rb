module AgentActivitiesHelper
  def event_type_badge_class(event_type)
    case event_type.to_s
    when /error|failed|failure/i
      "bg-red-500"
    when /completed|success/i
      "bg-green-500"
    when /started|created|activated/i
      "bg-blue-500"
    when /tool_execution/i
      "bg-indigo-500"
    when /human/i
      "bg-yellow-500"
    else
      "bg-gray-500"
    end
  end
end
