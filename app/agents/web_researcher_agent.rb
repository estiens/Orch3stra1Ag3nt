# WebResearcherAgent: Conducts web research on specific topics
# Uses search tools and browsing to gather information
class WebResearcherAgent < BaseAgent
  # Define queue
  def self.queue_name
    :web_researcher
  end

  # Limit concurrency to prevent too many web requests
  def self.concurrency_limit
    3
  end

  # Tools that the web researcher can use
  tool :search_web, "Search the web for information on a topic"
  tool :search_with_perplexity, "Search the web using Perplexity for AI-enhanced results"
  tool :browse_url, "Browse a specific URL to gather information"
  tool :scrape_webpage, "Scrape and extract content from a webpage"
  tool :semantic_memory, "Store and retrieve information using vector embeddings"
  tool :take_notes, "Record important information discovered during research"
  tool :compile_findings, "Compile research notes into structured findings"

  # Tool implementation: Search the web
  def search_web(query)
    # Use our SerpApiSearchTool for web search
    search_tool = SerpApiSearchTool.new
    search_results = search_tool.call(query: query, num_results: 5, include_snippets: true)

    # Check for errors
    if search_results[:error]
      return "Search error: #{search_results[:error]}"
    end

    # Format the results for the agent
    formatted_results = "Search results for: #{query}\n\n"

    search_results[:results].each_with_index do |result, index|
      formatted_results += "#{index + 1}. #{result[:title]}\n"
      formatted_results += "   URL: #{result[:link]}\n"
      formatted_results += "   #{result[:snippet]}\n\n" if result[:snippet]
    end

    # Add search metadata
    formatted_results += "Total results: approximately #{search_results[:total_results_count]}\n"
    formatted_results += "Search time: #{search_results[:search_time]}"

    # Record this as an event
    if agent_activity
      agent_activity.events.create!(
        event_type: "web_search_performed",
        data: {
          query: query,
          num_results: search_results[:results].count
        }
      )
    end

    formatted_results
  end

  # Tool implementation: Search with Perplexity
  def search_with_perplexity(query, focus = "web")
    # Use our PerplexitySearchTool for AI-enhanced search
    search_tool = PerplexitySearchTool.new
    search_results = search_tool.call(query: query, focus: focus)

    # Check for errors
    if search_results[:error]
      return "Perplexity search error: #{search_results[:error]}"
    end

    # Format the response
    formatted_results = "Perplexity search results for: #{query}\n\n"
    formatted_results += "#{search_results[:response]}\n\n"

    # Add citations if available
    if search_results[:citations]
      formatted_results += "Sources:\n"
      search_results[:citations].each_with_index do |citation, index|
        formatted_results += "#{index + 1}. #{citation[:title]}\n"
        formatted_results += "   URL: #{citation[:url]}\n\n"
      end
    end

    # Record this as an event
    if agent_activity
      agent_activity.events.create!(
        event_type: "perplexity_search_performed",
        data: {
          query: query,
          focus: focus
        }
      )
    end

    formatted_results
  end

  # Tool implementation: Browse a URL - now uses WebScraperTool
  def browse_url(url)
    # Use WebScraperTool to get the content
    scraper = WebScraperTool.new
    result = scraper.call(url: url, extract_type: "text")

    # Check for errors
    if result[:error]
      return "Error browsing URL: #{result[:error]}"
    end

    # Format the response
    response = "Title: #{result[:title]}\n"
    response += "URL: #{url}\n\n"

    # Truncate content if too long
    content = result[:content]
    if content.length > 5000
      response += content[0..5000] + "...\n\n[Content truncated due to length. Full length: #{content.length} characters]"
    else
      response += content
    end

    # Record this browsing activity
    if agent_activity
      agent_activity.events.create!(
        event_type: "url_browsed",
        data: {
          url: url,
          title: result[:title]
        }
      )
    end

    response
  end

  # Tool implementation: Scrape webpage - uses WebScraperTool
  def scrape_webpage(url, selector = nil, extract_type = "text")
    # Use WebScraperTool to scrape content
    scraper = WebScraperTool.new
    result = scraper.call(
      url: url,
      selector: selector,
      extract_type: extract_type
    )

    # Check for errors
    if result[:error]
      return "Error scraping webpage: #{result[:error]}"
    end

    # Format the response based on extraction type
    response = "Title: #{result[:title]}\n"
    response += "URL: #{url}\n"
    response += "Selector: #{selector || 'None'}\n"
    response += "Extract type: #{extract_type}\n\n"

    if extract_type == "links"
      response += "Links found:\n"
      result[:links].each_with_index do |link, index|
        response += "#{index + 1}. #{link[:text] || '[No text]'} - #{link[:href]}\n"
      end
    else
      # Handle text or HTML content
      content = result[:content]
      if content.length > 5000
        response += content[0..5000] + "...\n\n[Content truncated due to length. Full length: #{content.length} characters]"
      else
        response += content
      end
    end

    # Record this scraping activity
    if agent_activity
      agent_activity.events.create!(
        event_type: "webpage_scraped",
        data: {
          url: url,
          selector: selector,
          extract_type: extract_type
        }
      )
    end

    response
  end

  # Tool implementation: Take research notes
  def take_notes(note)
    return "Error: No task available to store notes" unless task

    # Add this note to the task's metadata
    current_notes = task.metadata&.dig("research_notes") || []
    updated_notes = current_notes + [ note ]

    # Update the task's metadata
    task.update!(
      metadata: (task.metadata || {}).merge({ "research_notes" => updated_notes })
    )

    # Record this note as an event
    agent_activity.events.create!(
      event_type: "research_note_added",
      data: {
        task_id: task.id,
        note: note
      }
    )

    "Research note recorded: #{note}"
  end

  # Tool implementation: Compile findings
  def compile_findings
    return "Error: No task available to compile findings" unless task

    # Get all the notes we've collected
    notes = task.metadata&.dig("research_notes") || []

    if notes.empty?
      return "No research notes found to compile. Use take_notes tool first."
    end

    # Format the notes for the prompt
    formatted_notes = notes.map.with_index { |note, i| "#{i+1}. #{note}" }.join("\n\n")

    # Create a prompt for the LLM to compile findings
    prompt = <<~PROMPT
      I've collected the following research notes on the topic: #{task.title}

      RESEARCH NOTES:
      #{formatted_notes}

      Please synthesize these notes into comprehensive research findings that:
      1. Summarize the key information discovered
      2. Organize the information in a logical structure
      3. Highlight important facts, figures, and insights
      4. Note any contradictions or uncertainties in the research
      5. Suggest any important areas that may require further research

      FORMAT YOUR RESPONSE AS:

      RESEARCH FINDINGS: #{task.title}

      SUMMARY:
      [Brief summary of findings]

      DETAILED FINDINGS:
      [Organized presentation of all key information]

      LIMITATIONS & GAPS:
      [Any limitations or gaps in the research]
    PROMPT

    # Use a thinking model for synthesis
    thinking_model = Regent::LLM.new(REGENT_MODEL_DEFAULTS[:thinking], temperature: 0.3)
    result = thinking_model.invoke(prompt)

    # Log this LLM call
    if agent_activity
      agent_activity.llm_calls.create!(
        provider: "openrouter",
        model: REGENT_MODEL_DEFAULTS[:thinking],
        prompt: prompt,
        response: result.content,
        tokens_used: (result.input_tokens || 0) + (result.output_tokens || 0)
      )
    end

    # Store the findings in the task result
    task.update!(result: result.content)

    # Create an event for task completion
    if task.may_complete?
      task.complete!

      # Publish a research completed event
      Event.publish(
        "research_subtask_completed",
        {
          subtask_id: task.id,
          result: result.content
        }
      )

      "Research findings compiled and task marked as complete"
    else
      "Research findings compiled but task could not be marked complete from its current state"
    end
  end
end
