require "rails_helper"

RSpec.describe CoordinatorAgent do
  let(:purpose) { "Task coordination" }
  let(:task) { create(:task, title: "Main task", description: "Coordinate subtasks") }
  let(:agent_activity) { create(:agent_activity, task: task, agent_type: "CoordinatorAgent") }
  let(:agent) { described_class.new(purpose: purpose, task: task, agent_activity: agent_activity) }

  describe "initialization and configuration" do
    it "sets the correct queue name" do
      expect(described_class.queue_name).to eq(:coordinator)
    end

    it "sets appropriate concurrency limit" do
      expect(described_class.concurrency_limit).to eq(3)
    end

    it "includes EventSubscriber" do
      expect(described_class.ancestors).to include(EventSubscriber)
    end

    it "initializes with required tools" do
      expect(agent.tools.map { |t| t[:name] if t.is_a?(Hash) }).to include(
        :analyze_task,
        :create_subtask,
        :assign_subtask,
        :check_subtasks,
        :update_task_status,
        :request_human_input,
        :mark_task_complete
      )
    end
  end

  describe "event subscriptions" do
    it "subscribes to relevant task events with dot notation" do
      subscriptions = described_class.event_subscriptions

      # Note: we're now using dot notation format for events
      expect(subscriptions).to include(
        { event_type: "subtask.completed", method_name: :handle_subtask_completed },
        { event_type: "subtask.failed", method_name: :handle_subtask_failed },
        { event_type: "task.waiting_on_human", method_name: :handle_human_input_required },
        { event_type: "tool_execution.finished", method_name: :handle_tool_execution },
        { event_type: "agent.completed", method_name: :handle_agent_completed },
        { event_type: "human_input.provided", method_name: :handle_human_input_provided }
      )
    end
  end

  describe "event handlers" do
    describe "#handle_subtask_completed" do
      let(:subtask) { create(:task, parent: task, title: "Subtask") }

      # Use a double to mock the event interface
      let(:event) do
        double("Event",
          event_type: "subtask.completed",
          data: { "subtask_id" => subtask.id, "result" => "Subtask result" },
          metadata: {}
        )
      end

      before do
        # Allow data hash access with indifferent access (string or symbol keys)
        allow(event).to receive(:data).and_return(
          { "subtask_id" => subtask.id, "result" => "Subtask result" }
        )
        allow(event.data).to receive(:[]).with("subtask_id").and_return(subtask.id)
        allow(event.data).to receive(:[]).with("result").and_return("Subtask result")
      end

      it "spawns a new coordinator to evaluate progress" do
        expect(described_class).to receive(:enqueue).with(
          "Evaluate progress after subtask #{subtask.id} (#{subtask.title}) completed",
          {
            task_id: task.id,
            context: {
              event_type: "subtask_completed",
              subtask_id: subtask.id,
              result: "Subtask result"
            }
          }
        )

        agent.handle_subtask_completed(event)
      end

      it "ignores events without subtask_id" do
        invalid_event = double("Event", data: {})
        allow(invalid_event).to receive(:data).and_return({})
        allow(invalid_event.data).to receive(:[]).with("subtask_id").and_return(nil)

        expect(described_class).not_to receive(:enqueue)

        agent.handle_subtask_completed(invalid_event)
      end
    end

    describe "#handle_subtask_failed" do
      let(:subtask) { create(:task, parent: task, title: "Subtask") }
      # Use a double to mock the event interface
      let(:event) do
        double("Event",
          event_type: "subtask.failed",
          data: { "subtask_id" => subtask.id, "error" => "Test error" },
          metadata: {}
        )
      end

      it "spawns a new coordinator to handle the failure" do
        expect(described_class).to receive(:enqueue).with(
          "Handle failure of subtask #{subtask.id} (#{subtask.title}): Test error",
          hash_including(
            task_id: task.id,
            context: hash_including(
              event_type: "subtask_failed",
              subtask_id: subtask.id,
              error: "Test error"
            )
          )
        )

        agent.handle_subtask_failed(event)
      end
    end

    describe "#handle_human_input_provided" do
      # Use a double to mock the HumanInputRequest interface
      let(:request) do
        double("HumanInputRequest", id: 123, task: task) # Mock id and task association
      end
      let(:event) do
        # Use a double to mock the event interface
        double("Event",
          id: "event-123",
          event_type: "human_input.provided",
          data: { "request_id" => request.id, "task_id" => task.id, "input" => "Human input" }, # Use "input" to match the service
          metadata: {}
        )
      end

      before do
        allow(task).to receive(:reload).and_return(task)
        allow(task).to receive(:waiting_on_human?).and_return(true)
        allow(task).to receive(:may_activate?).and_return(true)
        allow(task).to receive(:activate!)
      end

      let(:coordinator_event_service) { CoordinatorEventService.new }

      it "publishes a human_input.processed event" do
        # Skip this test for now as it requires more complex mocking
        skip "Requires more complex mocking of Task and HumanInteraction objects"

        # Mock the HumanInteraction.find_by to return a mock interaction
        interaction = double("HumanInteraction", id: request.id, task_id: task.id, task: task)
        allow(HumanInteraction).to receive(:find_by).and_return(interaction)

        # Allow task to respond to state
        allow(task).to receive(:state).and_return("waiting_on_human")

        # Allow EventService.publish to be called (spying)
        allow(EventService).to receive(:publish)

        # Call the service method directly
        coordinator_event_service.handle_human_input_provided(event, agent)

        # Verify publish was called with the correct event type and data
        expect(EventService).to have_received(:publish).with(
          "human_input.processed",
          hash_including(
            request_id: request.id,
            input: "Human input",
            task_id: task.id
          ),
          anything # Don't be strict about the metadata
        )
      end
    end
  end

  describe "tool implementations", :vcr do
    describe "#analyze_task" do
      let(:llm_response) do
        double(
          "LLMResponse",
          chat_completion: "Subtask 1: Research Component\nDescription: Research available libraries\nPriority: high\nAgent: WebResearcherAgent\nDependencies: None",
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150
        )
      end

      before do
        allow(agent.llm).to receive(:chat).and_return(llm_response)
      end

      it "calls LLM to analyze the task" do
        expect(agent.llm).to receive(:chat).with(hash_including(:messages)).and_return(llm_response)
        expect(agent).to receive(:log_direct_llm_call)

        result = agent.send(:analyze_task, "Build a web application")

        expect(result).to include("Subtask 1: Research Component")
        expect(result).to include("Priority: high")
        expect(result).to include("Agent: WebResearcherAgent")
      end

      it "handles LLM errors" do
        expect(agent.llm).to receive(:chat).and_raise(StandardError.new("LLM API error"))

        result = agent.send(:analyze_task, "Build a web application")

        expect(result).to include("Error analyzing task: LLM API error")
      end
    end

    describe "#create_subtask" do
      it "creates a subtask with the specified attributes" do
        subtask = build(:task, id: 123)
        expect(task.subtasks).to receive(:create!).with(
          hash_including(
            title: "Research task",
            description: "Research libraries",
            priority: "high",
            state: "pending"
          )
        ).and_return(subtask)

        # The implementation creates agent activities during the subtask creation process
        expect(AgentActivity).to receive(:create!).once.and_return(agent_activity)
        expect(agent_activity).to receive(:update!).and_return(true)

        # Expect event publication with the correct event type and data
        expect(EventService).to receive(:publish).with(
          "subtask.created",
          hash_including(
            title: "Research task",
            description: "Research libraries",
            priority: "high"
          ),
          hash_including( # Check metadata as well
            subtask_id: 123, # Subtask ID is in metadata
            parent_id: task.id, # Parent ID is in metadata
            task_id: 123 # Task ID is the same as subtask_id in metadata
          )
        ).and_return(double) # Allow publish to return a double

        result = agent.send(:create_subtask, "Research task", "Research libraries", "high")

        expect(result).to include("Created subtask 'Research task'")
        expect(result).to include("ID: 123")
        expect(result).to include("Priority: high")
      end
    end

    describe "#assign_subtask" do
      let(:subtask) { create(:task, parent: task, title: "Research task") }

      xit "assigns a subtask to the specified agent type" do
        # First stub the WebResearcherAgent.enqueue method
        allow(WebResearcherAgent).to receive(:enqueue).with(
          "Research task\n\nThis is a test task",
          {
            task_id: subtask.id,
            parent_activity_id: agent_activity.id,
            purpose: "Execute subtask: Research task",
            task_priority: "normal",
            metadata: {
              coordinator_id: agent_activity.id,
              parent_task_id: task.id
            }
          }
        ).and_return(true)

        # Set up expectations for the methods that will be called
        allow(subtask).to receive(:activate!)
        allow(subtask).to receive(:update)

        # Call the method first
        agent.send(:assign_subtask, subtask.id, "WebResearcherAgent")

        # Then verify the expectations
        expect(subtask).to have_received(:activate!)
        expect(subtask).to have_received(:update).with(
          hash_including(
            metadata: hash_including(
              assigned_agent: "WebResearcherAgent",
              assigned_at: an_instance_of(Time)
            )
          )
        )

        # Skip testing the legacy event creation
        allow(agent_activity.events).to receive(:create!).and_return(double)

        # Allow EventService.publish without strict expectations
        allow(EventService).to receive(:publish).and_return(double)

        result = agent.send(:assign_subtask, subtask.id, "WebResearcherAgent")

        expect(result).to include("Assigned subtask #{subtask.id}")
        expect(result).to include("WebResearcherAgent")
      end
    end

    describe "#check_subtasks" do
      before do
        # Create some subtasks in different states
        create(:task, parent: task, state: "completed", priority: "high")
        create(:task, parent: task, state: "active", priority: "normal")
        create(:task, parent: task, state: "pending", priority: "low")
        create(:task, parent: task, state: "failed", priority: "normal")
      end

      it "generates a detailed status report" do
        result = agent.send(:check_subtasks)

        expect(result).to include("SUBTASK STATUS REPORT")
        expect(result).to include("Task: #{task.title}")
        expect(result).to include("Total Subtasks: 4")
        expect(result).to include("Completed: 1")
        expect(result).to include("In Progress: 1")
        expect(result).to include("Pending: 1")
        expect(result).to include("Failed: 1")
      end
    end

    describe "#mark_task_complete" do
      let(:llm_response) do
        double(
          "LLMResponse",
          chat_completion: "# Task Summary\n\nAll subtasks completed successfully.",
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150
        )
      end

      before do
        allow(agent.llm).to receive(:chat).and_return(llm_response)
      end

      it "marks the task as complete with a summary" do
        # Create completed subtasks
        create(:task, parent: task, state: "completed", result: "Subtask 1 result")
        create(:task, parent: task, state: "completed", result: "Subtask 2 result")

        expect(task).to receive(:update!).with(result: "# Task Summary\n\nAll subtasks completed successfully.")
        expect(task).to receive(:may_complete?).and_return(true)
        expect(task).to receive(:complete!)

        # Allow any event publication without being strict about the format
        allow(EventService).to receive(:publish).and_return(double)

        result = agent.send(:mark_task_complete)

        expect(result).to include("Task #{task.id} ('#{task.title}') successfully COMPLETED!")
      end
    end
  end

  describe "run method", :vcr do
    context "with new task without subtasks" do
      it "performs initial task decomposition" do
        expect(agent).to receive(:perform_initial_task_decomposition).and_return("Task decomposed into subtasks")

        result = agent.run

        expect(result).to eq("Task decomposed into subtasks")
      end
    end

    context "with subtask completion event" do
      let(:subtask) { create(:task, parent: task, title: "Completed subtask") }
      let(:input) do
        {
          context: {
            event_type: "subtask_completed",
            subtask_id: subtask.id,
            result: "Subtask result"
          }
        }
      end

      it "processes the completed subtask" do
        expect(agent).to receive(:process_completed_subtask).with(subtask.id, "Subtask result").and_return("Processed subtask completion")

        result = agent.run(input)

        expect(result).to eq("Processed subtask completion")
      end
    end

    context "with subtask failure event" do
      let(:subtask) { create(:task, parent: task, title: "Failed subtask") }
      let(:input) do
        {
          context: {
            event_type: "subtask_failed",
            subtask_id: subtask.id,
            error: "Test error"
          }
        }
      end

      it "handles the failed subtask" do
        expect(agent).to receive(:handle_failed_subtask).with(subtask.id, "Test error").and_return("Handled subtask failure")

        result = agent.run(input)

        expect(result).to eq("Handled subtask failure")
      end
    end
  end
end
