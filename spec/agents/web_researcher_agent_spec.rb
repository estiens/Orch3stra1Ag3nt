require "rails_helper"

RSpec.describe WebResearcherAgent do
  let(:purpose) { "Web research" }
  let(:task) { create(:task, title: "Research task", description: "Research about AI") }
  let(:agent_activity) { create(:agent_activity, task: task, agent_type: "WebResearcherAgent") }
  let(:agent) { described_class.new(purpose: purpose, task: task, agent_activity: agent_activity) }

  describe "initialization and configuration" do
    it "sets the correct queue name" do
      expect(described_class.queue_name).to eq(:web_researcher)
    end

    it "sets appropriate concurrency limit" do
      expect(described_class.concurrency_limit).to eq(3)
    end

    it "initializes with required tools" do
      # The custom tools are provided by PerplexitySearchTool and WebScraperTool
      # The agent has its own defined tools: semantic_memory, take_notes, compile_findings
      expect(agent.tools.map { |t| t[:name] if t.is_a?(Hash) }).to include(
        :semantic_memory,
        :take_notes,
        :compile_findings
      )
    end
  end

  describe "tool implementations", :vcr do
    let(:perplexity_tool) { instance_double(PerplexitySearchTool) }
    let(:scraper) { instance_double(WebScraperTool) }

    before do
      allow(PerplexitySearchTool).to receive(:new).and_return(perplexity_tool)
      allow(WebScraperTool).to receive(:new).and_return(scraper)
    end


    describe "#search_with_perplexity" do
      let(:perplexity_results) do
        {
          response: "This is the AI-enhanced search response",
          citations: [
            { title: "Source 1", url: "https://example.com/1" },
            { title: "Source 2", url: "https://example.com/2" }
          ]
        }
      end

      it "calls PerplexitySearchTool and formats results" do
        expect(perplexity_tool).to receive(:call).with(query: "test query", focus: "web").and_return(perplexity_results)

        result = agent.send(:search_with_perplexity, "test query")

        expect(result).to include("This is the AI-enhanced search response")
        expect(result).to include("Source 1")
        expect(result).to include("Source 2")
        expect(result).to include("https://example.com/1")
      end

      it "handles errors" do
        expect(perplexity_tool).to receive(:call).and_raise(StandardError.new("API error"))

        result = agent.send(:search_with_perplexity, "test query")

        expect(result).to include("Error performing Perplexity search: API error")
      end

      it "handles error responses from the search tool" do
        expect(perplexity_tool).to receive(:call).and_return({ error: "Rate limit exceeded" })

        result = agent.send(:search_with_perplexity, "test query")

        expect(result).to include("Perplexity search error: Rate limit exceeded")
      end
    end

    describe "#browse_url" do
      let(:browse_results) do
        {
          title: "Test Page",
          content: "This is the page content",
          error: nil
        }
      end

      it "calls WebScraperTool and formats results" do
        expect(scraper).to receive(:call).with(url: "https://example.com", extract_type: "text").and_return(browse_results)

        result = agent.send(:browse_url, "https://example.com")

        expect(result).to include("Title: Test Page")
        expect(result).to include("This is the page content")
      end

      it "handles errors" do
        expect(scraper).to receive(:call).and_raise(StandardError.new("Network error"))

        result = agent.send(:browse_url, "https://example.com")

        expect(result).to include("Error browsing URL 'https://example.com': Network error")
      end

      it "handles error responses from the scraper tool" do
        expect(scraper).to receive(:call).and_return({ error: "404 Not Found" })

        result = agent.send(:browse_url, "https://example.com")

        expect(result).to include("Error browsing URL 'https://example.com': 404 Not Found")
      end
    end

    describe "#take_notes" do
      it "adds notes to task metadata" do
        task.update(metadata: {})

        result = agent.send(:take_notes, "This is an important finding")

        expect(task.reload.metadata["research_notes"]).to eq([ "This is an important finding" ])
        expect(result).to include("Research note recorded")
      end

      it "appends to existing notes" do
        task.update(metadata: { "research_notes" => [ "Existing note" ] })

        result = agent.send(:take_notes, "This is another finding")

        expect(task.reload.metadata["research_notes"]).to eq([ "Existing note", "This is another finding" ])
      end

      it "handles errors" do
        allow(task).to receive(:update!).and_raise(StandardError.new("Database error"))

        result = agent.send(:take_notes, "This is an important finding")

        expect(result).to include("Error recording note: Database error")
      end

      it "returns an error if not associated with a task" do
        agent_without_task = described_class.new(purpose: purpose)

        result = agent_without_task.send(:take_notes, "This is an important finding")

        expect(result).to include("Error: Cannot take notes - Agent not associated with a task")
      end
    end

    describe "#compile_findings", :vcr do
      let(:llm_response) do
        double(
          "LLMResponse",
          chat_completion: "# Research Findings\n\nHere is a summary of the research...",
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150
        )
      end

      before do
        task.update(metadata: { "research_notes" => [ "Note 1", "Note 2" ] })
        allow(agent.llm).to receive(:chat).and_return(llm_response)
      end

      it "uses LLM to compile notes into findings" do
        expect(agent.llm).to receive(:chat).with(hash_including(:messages)).and_return(llm_response)
        expect(agent).to receive(:log_direct_llm_call)

        result = agent.send(:compile_findings)

        expect(result).to eq("# Research Findings\n\nHere is a summary of the research...")
        expect(task.reload.result).to eq("# Research Findings\n\nHere is a summary of the research...")
      end

      it "marks the task as complete" do
        allow(task).to receive(:may_complete?).and_return(true)
        expect(task).to receive(:complete!)

        agent.send(:compile_findings)
      end

      it "publishes an event for subtasks" do
        parent_task = create(:task)
        task.update(parent_id: parent_task.id)

        expect(Event).to receive(:publish).with(
          "research_subtask_completed",
          hash_including(subtask_id: task.id, parent_id: parent_task.id)
        )

        agent.send(:compile_findings)
      end

      it "returns an error if no notes exist" do
        task.update(metadata: {})

        result = agent.send(:compile_findings)

        expect(result).to include("No research notes found to compile")
      end

      it "handles LLM errors" do
        expect(agent.llm).to receive(:chat).and_raise(StandardError.new("LLM API error"))

        result = agent.send(:compile_findings)

        expect(result).to include("Error compiling findings: LLM API error")
      end
    end
  end

  describe "run method", :vcr do
    before do
      # Mock the tool execution methods to avoid actual API calls
      allow(agent).to receive(:execute_tool).and_call_original

      # Mock specific tool methods
      allow(agent).to receive(:search_with_perplexity).and_return("Perplexity search results\nURL: https://example.com")
      allow(agent).to receive(:browse_url).and_return("Content from example.com")
      allow(agent).to receive(:take_notes).and_return("Note recorded")
      allow(agent).to receive(:compile_findings).and_return("Compiled research findings")
    end

    it "executes the research workflow" do
      expect(agent).to receive(:execute_tool).with(:search_with_perplexity, query: "Research task").and_return("Perplexity search results\nURL: https://example.com")
      expect(agent).to receive(:execute_tool).with(:take_notes, "Initial Perplexity Search Results:\nPerplexity search results\nURL: https://example.com")
      expect(agent).to receive(:execute_tool).with(:browse_url, "https://example.com").and_return("Content from example.com")
      expect(agent).to receive(:execute_tool).with(:take_notes, "Content from https://example.com:\nContent from example.com")
      expect(agent).to receive(:execute_tool).with(:compile_findings).and_return("Compiled research findings")

      result = agent.run

      expect(result).to eq("Compiled research findings")
    end

    it "handles missing URLs in search results" do
      allow(agent).to receive(:search_with_perplexity).and_return("Perplexity search results without URLs")

      expect(agent).to receive(:execute_tool).with(:search_with_perplexity, query: "Research task")
      expect(agent).to receive(:execute_tool).with(:take_notes, "Initial Perplexity Search Results:\nPerplexity search results without URLs")
      expect(agent).to receive(:execute_tool).with(:take_notes, "No URLs found in search results to browse.")
      expect(agent).to receive(:execute_tool).with(:compile_findings)

      agent.run
    end

    it "handles errors during execution" do
      expect(agent).to receive(:execute_tool).with(:search_with_perplexity, query: "Research task").and_raise(StandardError.new("API error"))
      expect(agent).to receive(:handle_run_error)

      expect { agent.run }.to raise_error(StandardError, "API error")
    end
  end
end
