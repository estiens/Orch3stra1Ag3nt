module DashboardHelper
  def status_badge(status)
    status_class = case status.to_s.downcase
                   when 'running', 'active'
                     'badge-success'
                   when 'completed', 'finished'
                     'badge-primary'
                   when 'failed', 'error'
                     'badge-error'
                   when 'waiting', 'pending'
                     'badge-warning'
                   when 'paused'
                     'badge-secondary'
                   else
                     'badge-info'
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
      elsif value.is_a?(Hash) || value.is_a?(Array)
        # For nested structures, just show type and size
        type = value.class.name
        size = value.is_a?(Hash) ? value.keys.size : value.size
        "#{type} with #{size} items"
      else
        value
      end
    end
    
    # Return formatted data
    filtered_data.map { |k, v| "<strong>#{k.humanize}:</strong> #{v}" }.join("<br>").html_safe
  end
  
  def time_ago_with_tooltip(datetime)
    return unless datetime
    
    content_tag(:span, 
                time_ago_in_words(datetime) + " ago", 
                class: "tooltip tooltip-bottom", 
                data: { tip: datetime.strftime("%Y-%m-%d %H:%M:%S") })
  end
  
  def truncate_with_tooltip(text, length = 50)
    return unless text
    
    if text.length > length
      content_tag(:span, 
                  truncate(text, length: length), 
                  class: "tooltip tooltip-bottom", 
                  data: { tip: text })
    else
      text
    end
  end
  
  def dashboard_section_card(title, id, view_all_path = nil, badge_count = nil)
    content_tag(:div, class: "card bg-base-100 shadow-xl h-full") do
      content_tag(:div, class: "card-body") do
        header = content_tag(:div, class: "flex justify-between items-center mb-4") do
          title_div = content_tag(:div, class: "flex items-center") do
            concat content_tag(:h2, title, class: "card-title")
            if badge_count && badge_count > 0
              concat content_tag(:span, badge_count, class: "badge badge-primary ml-2")
            end
          end
          
          concat title_div
          
          if view_all_path
            concat link_to("View All", view_all_path, class: "link link-primary text-sm")
          end
        end
        
        concat header
        concat content_tag(:div, id: id, class: "divide-y divide-gray-200 max-h-[500px] overflow-y-auto") do
          yield if block_given?
        end
      end
    end
  end
end
