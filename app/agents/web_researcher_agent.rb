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

  # --- Tools ---
  # Consider registering external tool objects (PerplexitySearchTool, etc.) via custom_tool_objects
  # or passing them during initialization instead of creating them inside methods.

  tool :search_with_perplexity, "Search the web using Perplexity for AI-enhanced results" do |query, focus = "web"|
    # Ensure parameters are properly passed as named arguments
    search_with_perplexity(query, focus)
  end

  tool :browse_url, "Browse a specific URL to gather text content" do |url|
    browse_url(url)
  end

  tool :scrape_webpage, "Scrape and extract specific content (text, links) from a webpage" do |url, selector = nil, extract_type = "text"|
    scrape_webpage(url, selector, extract_type)
  end

  # Placeholder for Vector DB tool
  tool :semantic_memory, "Store and retrieve information using vector embeddings (Not Implemented)" do |query|
    "Vector DB search/retrieval not implemented yet."
  end

  tool :take_notes, "Record important information discovered during research" do |note|
    take_notes(note)
  end

  tool :compile_findings, "Compile research notes into structured findings" do
    compile_findings
  end
  # --- End Tools ---

  # --- Core Logic ---
  def run(input = nil) # Input should be the research topic/question
    before_run(input)
    
    # Extract a clean research topic from input or task
    research_topic = if input.present?
      # If input is provided directly, use it
      input.to_s.strip
    elsif task&.title.present?
      # If we have a task with a title, use that
      task.title.to_s.strip
    else
      # Fallback
      "Unknown topic"
    end

    unless task
      Rails.logger.warn "[WebResearcherAgent] Running without an associated task record."
    end

    result_message = "Web research run completed for: #{research_topic}"
    begin
      Rails.logger.info "[WebResearcherAgent-#{task&.id || 'no-task'}] Starting research for: #{research_topic}"

      # Step 1: Initial Search (using Perplexity first, then maybe standard web)
      search_results_text = execute_tool(:search_with_perplexity, query: research_topic)
      execute_tool(:take_notes, "Initial Perplexity Search Results:\n#{search_results_text}")

      # Check if search was successful by looking for error messages
      if search_results_text.include?("No search results found") || search_results_text.include?("Error performing Perplexity search")
        # If Perplexity search failed, try an alternative approach
        Rails.logger.warn "[WebResearcherAgent-#{task&.id || 'no-task'}] Perplexity search failed, using alternative research approach"
        
        # Record the failure
        execute_tool(:take_notes, "Perplexity search failed. Using alternative research approach.")
        
        # Try a different approach - for example, we could use a different search tool here
        # For now, we'll just continue with what we have
        alternative_research = "Based on the research topic '#{research_topic}', here's what I can determine without external search:\n\n" +
                              "This is a placeholder for alternative research methods when external search fails. " +
                              "In a production environment, this would use backup search providers or other information sources."
        
        execute_tool(:take_notes, "Alternative Research:\n#{alternative_research}")
      else
        # Parse search results to find promising URLs/Snippets
        first_url = search_results_text.match(/URL:\s*(https?\S+)/i)&.[](1)

        if first_url
          # Step 2: Browse/Scrape promising source
          Rails.logger.info "[WebResearcherAgent-#{task&.id || 'no-task'}] Browsing first URL: #{first_url}"
          browsed_content = execute_tool(:browse_url, first_url)
          execute_tool(:take_notes, "Content from #{first_url}:\n#{browsed_content.truncate(1000)}")
        else
          Rails.logger.info "[WebResearcherAgent-#{task&.id || 'no-task'}] No URL found in initial search results to browse."
          execute_tool(:take_notes, "No URLs found in search results to browse.")
        end
      end

      # Step 3: Compile findings based on notes
      Rails.logger.info "[WebResearcherAgent-#{task&.id || 'no-task'}] Compiling findings..."
      final_findings = execute_tool(:compile_findings)
      result_message = final_findings # The compiled findings are the main result

    rescue => e
      handle_run_error(e)
      raise # Re-raise after handling
    end

    @session_data[:output] = result_message
    after_run(result_message)
    result_message
  end
  # --- End Core Logic ---

  # --- Tool Implementations ---

  def search_with_perplexity(query, focus = "web")
    # Ensure query is a string
    query = query.to_s.strip
    
    # Validate query
    if query.empty?
      return "Error: Search query cannot be empty"
    end
    
    search_tool = PerplexitySearchTool.new # Consider dependency injection
    # Use call method for test compatibility
    search_results = search_tool.call(query: query, focus: focus)

    # Handle different response types
    if search_results.is_a?(String)
      # The API returned an error message as a string
      return search_results
    elsif search_results.is_a?(Hash) && search_results[:error].present?
      return "Perplexity search error: #{search_results[:error]}"
    end

    # Format the response for a successful search
    formatted_results = "Perplexity search results for: #{query}\n\n#{search_results[:response]}\n\n"
    if search_results[:citations].present?
      formatted_results += "Sources:\n"
      search_results[:citations].each_with_index do |citation, index|
        formatted_results += "#{index + 1}. #{citation[:title]} - URL: #{citation[:url]}\n"
      end
    end

    # Logging handled by AgentActivityCallbackHandler
    formatted_results
  rescue => e
    Rails.logger.error "[WebResearcherAgent] Error in search_with_perplexity: #{e.message}"
    "Error performing Perplexity search: #{e.message}"
  end

  def browse_url(url)
    scraper = WebScraperTool.new # Consider dependency injection
    # Use call method for test compatibility
    result = scraper.call(url: url, extract_type: "text")

    # Handle error response from the scraper
    if result.is_a?(Hash) && result[:error].present?
      return "Error browsing URL '#{url}': #{result[:error]}"
    end

    content = result[:content].to_s
    response = "Title: #{result[:title]}\nURL: #{url}\n\n"
    response += content.truncate(5000, omission: "... (truncated, #{content.length} chars total)")

    # Logging handled by AgentActivityCallbackHandler
    response
  rescue => e
    Rails.logger.error "[WebResearcherAgent] Error in browse_url for '#{url}': #{e.message}"
    "Error browsing URL '#{url}': #{e.message}"
  end

  def scrape_webpage(url, selector = nil, extract_type = "text")
    scraper = WebScraperTool.new # Consider dependency injection
    # Use call method for test compatibility
    result = scraper.call(url: url, selector: selector, extract_type: extract_type)

    if result[:error]
      return "Error scraping webpage '#{url}': #{result[:error]}"
    end

    response = "Title: #{result[:title]}\nURL: #{url}\nSelector: #{selector || 'None'}\nExtract type: #{extract_type}\n\n"
    if extract_type == "links"
      response += "Links found:
"
      result[:links].each_with_index { |link, i| response += "#{i + 1}. #{link[:text] || '[No text]'} - #{link[:href]}\n" }
    else
      content = result[:content].to_s
      response += content.truncate(5000, omission: "... (truncated, #{content.length} chars total)")
    end

    # Logging handled by AgentActivityCallbackHandler

    response
  rescue => e
    Rails.logger.error "[WebResearcherAgent] Error in scrape_webpage for '#{url}': #{e.message}"
    "Error scraping webpage '#{url}': #{e.message}"
  end

  def take_notes(note)
    unless task
      return "Error: Cannot take notes - Agent not associated with a task."
    end

    begin
      # Use Rails' store accessor for cleaner metadata updates if possible, otherwise merge.
      current_notes = task.metadata&.dig("research_notes") || []
      updated_notes = current_notes + [ note ]
      task.update!(metadata: (task.metadata || {}).merge({ "research_notes" => updated_notes }))

      # Logging handled by AgentActivityCallbackHandler

      "Research note recorded: #{note.truncate(100)}"
    rescue => e
      Rails.logger.error "[WebResearcherAgent] Error taking notes for task #{task.id}: #{e.message}"
      "Error recording note: #{e.message}"
    end
  end

  def compile_findings
    unless task
      return "Error: Cannot compile findings - Agent not associated with a task."
    end

    notes = task.metadata&.dig("research_notes") || []
    if notes.empty?
      return "No research notes found to compile for task #{task.id}. Use take_notes tool first."
    end

    formatted_notes = notes.map.with_index { |note, i| "Note #{i + 1}:\n#{note}" }.join("\n\n---\n\n")

    prompt_content = <<~PROMPT
      Synthesize the following research notes regarding '#{task.title}'.

      RESEARCH NOTES:
      #{formatted_notes}

      Compile these notes into comprehensive research findings.
      Summarize key information, organize logically, highlight important facts/insights, and note any contradictions or gaps.

      FORMAT:
      RESEARCH FINDINGS: #{task.title}

      SUMMARY:
      [Brief summary]

      DETAILED FINDINGS:
      [Organized points]

      LIMITATIONS & GAPS:
      [Limitations/Gaps]
    PROMPT

    begin
      # Use the agent's LLM
      response = @llm.chat(messages: [ { role: "user", content: prompt_content } ])
      compiled_result = response.chat_completion # or response.content

      # Manually log the LLM call
      log_direct_llm_call(prompt_content, response)

      # Store findings as the task result
      task.update!(result: compiled_result)
      task.complete! if task.may_complete?

      # Publish event if this is a subtask (handled in BaseAgent now? No, compile should publish)
      if task.parent_id
        Event.publish(
          "research_subtask_completed",
          { subtask_id: task.id, parent_id: task.parent_id, result: compiled_result }
        )
      end

      compiled_result
    rescue => e
      Rails.logger.error "[WebResearcherAgent] LLM Error in compile_findings for task #{task.id}: #{e.message}"
      "Error compiling findings: #{e.message}"
    end
  end
  # --- End Tool Implementations ---

  # Optional: Override after_run if specific actions needed after WebResearcher finishes
  # def after_run(result)
  #   super # Call base class hook first
  #   # ... web researcher specific actions ...
  # end
end
