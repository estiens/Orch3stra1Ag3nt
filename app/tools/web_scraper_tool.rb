require "mechanize"
require "nokogiri"

class WebScraperTool < BaseTool
  def initialize
    super("web_scraper", "Scrape content from web pages")
  end
  
  def call(args)
    url = args[:url]
    selector = args[:selector]
    extract_type = args[:extract_type] || "text"
    begin
      # Validate URL
      unless url =~ /\A(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?(\?.*)?(\#.*)?\z/ix
        return { error: "Invalid URL format. Please provide a valid URL starting with http:// or https://" }
      end

      # Initialize a Mechanize agent
      agent = Mechanize.new
      agent.user_agent_alias = "Mac Safari"
      agent.open_timeout = 10
      agent.read_timeout = 10

      # Set up request headers
      agent.request_headers = {
        "Accept-Language" => "en-US,en;q=0.9",
        "Accept" => "text/html,application/xhtml+xml,application/xml",
        "Dnt" => "1"
      }

      # Fetch the page
      page = agent.get(url)

      # Return results based on extraction type
      case extract_type.to_s.downcase
      when "html"
        if selector
          {
            content: page.search(selector).to_html,
            url: url,
            title: page.title
          }
        else
          {
            content: page.body,
            url: url,
            title: page.title
          }
        end
      when "text"
        if selector
          {
            content: page.search(selector).text.strip,
            url: url,
            title: page.title
          }
        else
          {
            content: page.search("body").text.strip,
            url: url,
            title: page.title
          }
        end
      when "links"
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
      else
        { error: "Invalid extract_type. Use 'text', 'html', or 'links'." }
      end
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

  # Helper method to extract specific elements from a page
  def extract_content(page, selector = nil, extract_type = "text")
    elements = selector ? page.search(selector) : page.search("body")

    case extract_type.to_s.downcase
    when "html"
      elements.to_html
    when "text"
      elements.text.strip
    when "links"
      elements.css("a").map { |link| { text: link.text.strip, href: link["href"] } }
    else
      elements.text.strip
    end
  end
end
