require "mechanize"
require "nokogiri"

class WebScraperTool
  extend Langchain::ToolDefinition

  define_function :scrape, description: "Scrape content from web pages" do
    property :url, type: "string", description: "The URL to scrape", required: true
    property :selector, type: "string", description: "CSS selector to target specific elements (optional)", required: false
    property :extract_type, type: "string", description: "Content type to extract: 'text', 'html', or 'links'", required: false
  end

  # Add call method for compatibility with tests
  def call(url:, extract_type: "text")
    scrape(url: url, extract_type: extract_type)
  end

  def scrape(url:, selector: nil, extract_type: "text")
    # Validate URL format
    unless valid_url?(url)
      return { error: "Invalid URL format. Please provide a valid URL starting with http:// or https://" }
    end

    # Initialize and configure Mechanize agent
    agent = configure_mechanize_agent

    begin
      # Fetch the page
      page = agent.get(url)

      # Process and return results based on extraction type
      process_extraction(page, url, selector, extract_type)
    rescue Mechanize::ResponseCodeError => e
      { error: "HTTP Error: #{e.response_code} when accessing #{url}" }
    rescue Mechanize::RedirectLimitReachedError
      { error: "Too many redirects when accessing #{url}" }
    rescue Mechanize::SocketError
      { error: "Network error when accessing #{url}" }
    rescue => e
      { error: "Error scraping #{url}: #{e.message}" }
    end
  end

  private

  def valid_url?(url)
    url =~ /\A(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?(\?.*)?(\#.*)?\z/ix
  end

  def configure_mechanize_agent
    agent = Mechanize.new
    agent.user_agent_alias = "Mac Safari"
    agent.open_timeout = 10
    agent.read_timeout = 10
    agent.request_headers = {
      "Accept-Language" => "en-US,en;q=0.9",
      "Accept" => "text/html,application/xhtml+xml,application/xml",
      "Dnt" => "1"
    }
    agent
  end

  def process_extraction(page, url, selector, extract_type)
    case extract_type.to_s.downcase
    when "html"
      extract_html(page, url, selector)
    when "text"
      extract_text(page, url, selector)
    when "links"
      extract_links(page, url, selector)
    else
      { error: "Invalid extract_type. Use 'text', 'html', or 'links'." }
    end
  end

  def extract_html(page, url, selector)
    content = selector ? page.search(selector).to_html : page.body
    {
      content: content,
      url: url,
      title: page.title
    }
  end

  def extract_text(page, url, selector)
    content = selector ? page.search(selector).text.strip : page.search("body").text.strip
    {
      content: content,
      url: url,
      title: page.title
    }
  end

  def extract_links(page, url, selector)
    links = if selector
      page.search(selector).css("a").map { |link| { text: link.text.strip, href: link["href"] } }
    else
      page.links.map { |link| { text: link.text.strip, href: link.href } }
    end

    {
      links: links,
      url: url,
      title: page.title
    }
  end
end
