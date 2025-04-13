require "rails_helper"

RSpec.describe "TestAgent with VCR", type: :agent, vcr: true do
  # Create a simple test agent class with tools for testing
  class WeatherTestAgent < BaseAgent
    tool :get_weather, "Get the weather for a location" do |location|
      "It is currently 72°F and sunny in #{location}."
    end
    
    tool :get_forecast, "Get a future forecast for a location" do |location, days_ahead = 3|
      "The forecast for #{location} in #{days_ahead} days is 75°F with scattered clouds."
    end
    
    # Direct methods for testing
    def get_weather(location)
      execute_tool(:get_weather, location)
    end
    
    def get_forecast(location, days_ahead = 3)
      execute_tool(:get_forecast, location, days_ahead)
    end
  end

  let(:task) { create(:task, title: "Test Weather Task") }
  let(:agent_activity) { create(:agent_activity, task: task, agent_type: "WeatherTestAgent") }

  describe "agent with tools", vcr: { cassette_name: "weather_test_agent/basic_tools" } do
    it "can use tools to answer weather questions" do
      agent = WeatherTestAgent.new(
        "You are a helpful weather assistant",
        task: task,
        agent_activity: agent_activity
      )

      result = agent.run("What's the weather like in San Francisco?")

      # Check that the agent used the tool
      expect(agent.session.spans.map(&:type)).to include("tool_execution")

      # Expect the result to mention San Francisco weather
      expect(result).to include("San Francisco")
      expect(result).to include("sunny")

      # TODO: Uncomment when the agent_activity is updated with LLM calls

      # Verify the agent_activity has been updated with LLM calls
      # expect(agent_activity.reload.llm_calls).not_to be_empty

      # Verify we have tool execution events
      # tool_events = agent_activity.events.where(event_type: "tool_execution")
      # expect(tool_events).not_to be_empty
    end
  end

  describe "agent with multiple tool calls", vcr: { cassette_name: "weather_test_agent/multiple_tools" } do
    it "can use multiple tools in sequence" do
      agent = WeatherTestAgent.new(
        "You are a helpful weather assistant",
        task: task,
        agent_activity: agent_activity
      )

      result = agent.run("What's the weather like in Tokyo today and what's the forecast for Tokyo in 3 days?")

      # Check that the agent made multiple tool calls
      tool_executions = agent.session.spans.select { |span| span.type == "tool_execution" }
      expect(tool_executions.count).to be > 1

      # Expect the result to include both current weather and forecast
      expect(result).to include("Tokyo")
      expect(result).to include("forecast")

      # Verify the agent_activity has been updated with the expected number of LLM calls
      # TODO: this is not updating correctly
      # expect(agent_activity.reload.llm_calls.count).to be >= 2
    end
  end

  describe "error handling", vcr: { cassette_name: "weather_test_agent/error_handling" } do
    class ErrorTestAgent < BaseAgent
      tool :failing_tool, "A tool that always fails"

      def failing_tool(input)
        raise "This tool deliberately failed"
      end
    end

    # TODO: fix this rescue

    # it "handles tool errors gracefully" do
    #   error_agent = ErrorTestAgent.new(
    #     "You are a test agent",
    #     task: task,
    #     agent_activity: agent_activity
    #   )

    #   # The agent should recover and try a different approach or return an error message
    #   result = error_agent.run("Please use the failing tool with input 'test'")

    #   # Expect the result to mention the failure (one of these should be true)
    #   expect(result).to satisfy { |msg| msg.include?("error") || msg.include?("unable") || msg.include?("fail") }

    #   # The agent activity should record the error in some way
    #   events = agent_activity.reload.events
    #   expect(events.any? { |e| e.data.to_s.include?("fail") }).to be true
    # end
  end
end
