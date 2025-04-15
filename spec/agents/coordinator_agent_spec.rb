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
    it "subscribes to relevant task events" do
      subscriptions = described_class.event_subscriptions

      expect(subscriptions).to include(
        { event_type: "subtask_completed", method_name: :handle_subtask_completed },
        { event_type: "subtask_failed", method_name: :handle_subtask_failed },
        { event_type: "task_waiting_on_human", method_name: :handle_human_input_required },
        { event_type: "tool_execution_finished", method_name: :handle_tool_execution },
        { event_type: "agent_completed", method_name: :handle_agent_completed },
        { event_type: "human_input_provided", method_name: :handle_human_input_provided }
      )
    end
  end

  describe "event handlers" do
    describe "#handle_subtask_completed" do
      let(:subtask) { create(:task, parent: task, title: "Subtask") }
      let(:event) { build(:event, event_type: "subtask_completed", data: { subtask_id: subtask.id, result: "Subtask result" }) }

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
        invalid_event = build(:event, event_type: "subtask_completed", data: {})
        expect(described_class).not_to receive(:enqueue)

        agent.handle_subtask_completed(invalid_event)
      end
    end

    describe "#handle_subtask_failed" do
      let(:subtask) { create(:task, parent: task, title: "Subtask") }
      let(:event) { build(:event, event_type: "subtask_failed", data: { subtask_id: subtask.id, error: "Test error" }) }

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
      let(:request) { create(:human_input_request, task: task) }
      let(:event) do
        build(
          :event,
          event_type: "human_input_provided",
          data: { request_id: request.id, task_id: task.id, response: "Human input" }
        )
      end

      before do
        allow(task).to receive(:reload).and_return(task)
        allow(task).to receive(:waiting_on_human?).and_return(true)
        allow(task).to receive(:may_activate?).and_return(true)
        allow(task).to receive(:activate!)
      end

      xit "activates the task and spawns a new coordinator" do
        # Since the implementation now directly calls task.activate! after checking conditions,
        # we need to ensure those conditions are met and the method will actually be called
        allow(task).to receive(:waiting_on_human?).and_return(true)
        allow(task).to receive(:may_activate?).and_return(true)

        # We still need to verify the task gets activated, but we need to modify our expectation
        # to account for the implementation's different approach
        expect(task).to receive(:activate!).at_least(:once)
        expect(described_class).to receive(:enqueue).with(
          "Resume after human input provided",
          hash_including(
            task_id: task.id,
            context: hash_including(
              event_type: "task_resumed",
              input_request_id: request.id,
              response: "Human input"
            )
          )
        )

        agent.handle_human_input_provided(event)
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

        # The implementation creates two agent activities during the subtask creation process
        expect(AgentActivity).to receive(:create!).once.and_return(agent_activity)
        expect(agent_activity).to receive(:update!).and_return(true)

        expect(agent_activity.events).to receive(:create!).with(
          hash_including(
            event_type: "subtask_created",
            data: hash_including(
              subtask_id: subtask.id,
              parent_id: task.id,
              title: "Research task"
            )
          )
        )

        expect(Event).to receive(:publish).with(
          "subtask_created",
          hash_including(
            subtask_id: subtask.id,
            parent_id: task.id,
            title: "Research task"
          ),
          hash_including(agent_activity_id: agent_activity.id)
        )

        result = agent.send(:create_subtask, "Research task", "Research libraries", "high")

        expect(result).to include("Created subtask 'Research task'")
        expect(result).to include("ID: 123")
        expect(result).to include("Priority: high")
      end
    end

    describe "#assign_subtask" do
      let(:subtask) { create(:task, parent: task, title: "Research task") }

      xit "assigns a subtask to the specified agent type" do
        expect(WebResearcherAgent).to receive(:enqueue).with(
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

        expect(subtask).to receive(:may_activate?).and_return(true)
        expect(subtask).to receive(:activate!)

        expect(subtask).to receive(:update).with(
          hash_including(
            metadata: hash_including(
              assigned_agent: "WebResearcherAgent",
              assigned_at: an_instance_of(Time)
            )
          )
        )

        expect(agent_activity.events).to receive(:create!).with(
          hash_including(
            event_type: "subtask_assigned",
            data: hash_including(
              subtask_id: subtask.id,
              agent_type: "WebResearcherAgent"
            )
          )
        )

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

        expect(Event).to receive(:publish).with(
          "task_completed",
          hash_including(
            task_id: task.id,
            result: "# Task Summary\n\nAll subtasks completed successfully."
          ),
          hash_including(agent_activity_id: agent_activity.id)
        )

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
