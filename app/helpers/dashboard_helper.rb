module DashboardHelper
  def status_badge(status)
    status_class = case status.to_s.downcase
                   when 'running', 'active'
                     'badge-success'
                   when 'completed', 'finished'
                     'badge-primary'
                   when 'failed', 'error'
                     'badge-danger'
                   when 'waiting', 'pending'
                     'badge-warning'
                   else
                     'badge-secondary'
                   end
    
    content_tag(:span, status.to_s.humanize, class: "badge #{status_class}")
  end
  
  def format_event_data(data)
    return "No data" unless data.present? && data.is_a?(Hash)
    
    # Filter out sensitive or overly verbose data
    filtered_data = data.except('prompt', 'response', 'full_text')
    
    # Truncate long values
    filtered_data.transform_values do |value|
      if value.is_a?(String) && value.length > 100
        value[0..100] + "..."
      else
        value
      end
    end
    
    # Return formatted data
    filtered_data.map { |k, v| "<strong>#{k.humanize}:</strong> #{v}" }.join("<br>").html_safe
  end
end
