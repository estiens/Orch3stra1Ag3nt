require "serpapi"

class SerpApiSearchTool < Regent::Tool
  # Implement the call method that will be invoked when the tool is used
  def call(query, num_results: 5, include_snippets: true)
    begin
      # Validate the API key
      api_key = ENV["SERPAPI_API_KEY"]
      unless api_key
        return { error: "SERPAPI_API_KEY environment variable is not set" }
      end

      # Validate the query
      if query.to_s.strip.empty?
        return { error: "Search query cannot be empty" }
      end

      # Limit number of results to reasonable range
      num_results = [ [ 1, num_results.to_i ].max, 10 ].min

      # Build parameters for the search
      params = {
        q: query,
        api_key: api_key,
        engine: "google",
        num: num_results,
        gl: "us",  # Country code for search
        hl: "en"   # Language code
      }

      # Execute the search
      results = SerpApi::Client.search(params)

      # Extract and format the organic results
      if results["organic_results"]
        formatted_results = results["organic_results"].first(num_results).map do |result|
          {
            title: result["title"],
            link: result["link"],
            snippet: include_snippets ? result["snippet"] : nil,
            position: result["position"]
          }.compact
        end

        {
          query: query,
          results: formatted_results,
          total_results_count: results["search_information"]["total_results"].to_i,
          search_time: results["search_information"]["time_taken_displayed"]
        }
      else
        {
          error: "No results found or unexpected response format",
          raw_results: results
        }
      end
    rescue => e
      { error: "Error executing search: #{e.message}" }
    end
  end
end
