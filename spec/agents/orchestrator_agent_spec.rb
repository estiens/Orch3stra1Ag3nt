require "rails_helper"

RSpec.describe OrchestratorAgent do
  let(:purpose) { "System orchestration" }
  let(:task) { create(:task, title: "System task", description: "Orchestrate system") }
  let(:agent_activity) { create(:agent_activity, task: task, agent_type: "OrchestratorAgent") }
  let(:agent) { described_class.new(purpose: purpose, task: task, agent_activity: agent_activity) }

  describe "initialization and configuration" do
    it "sets the correct queue name" do
      expect(described_class.queue_name).to eq(:orchestrator)
    end

    it "sets appropriate concurrency limit" do
      expect(described_class.concurrency_limit).to eq(1)
    end

    it "includes EventSubscriber" do
      expect(described_class.ancestors).to include(EventSubscriber)
    end

    it "initializes with required tools" do
      expect(agent.tools.map { |t| t[:name] if t.is_a?(Hash) }).to include(
        :analyze_system_state,
        :spawn_coordinator,
        :escalate_to_human,
        :adjust_system_priorities,
        :check_resource_usage
      )
    end
  end

  describe "event subscriptions" do
    it "subscribes to relevant system events" do
      subscriptions = described_class.event_subscriptions

      expect(subscriptions).to include(
        { event_type: "task_created", method_name: :handle_new_task },
        { event_type: "task_stuck", method_name: :handle_stuck_task },
        { event_type: "system_resources_critical", method_name: :handle_resource_critical },
        { event_type: "project_created", method_name: :handle_new_project }
      )
    end
  end

  describe "recurring schedule configuration" do
    it "configures recurring health checks" do
      expect(described_class).to receive(:configure_recurring).with(
        key: "system_health_check",
        schedule: "every 10 minutes",
        prompt: "Perform system health check and resource allocation",
        options: { purpose: "System health monitoring and resource allocation" }
      )

      described_class.configure_recurring_checks
    end

    it "allows custom interval for health checks" do
      expect(described_class).to receive(:configure_recurring).with(
        key: "system_health_check",
        schedule: "every 30 minutes",
        prompt: "Perform system health check and resource allocation",
        options: { purpose: "System health monitoring and resource allocation" }
      )

      described_class.configure_recurring_checks("every 30 minutes")
    end
  end

  describe "event handlers" do
    describe "#handle_new_task" do
      let(:event) { build(:event, event_type: "task_created", data: { task_id: task.id }) }

      it "logs the event" do
        expect(Rails.logger).to receive(:info).with(/Received handle_new_task for Task #{task.id}/)
        agent.handle_new_task(event)
      end
    end

    describe "#handle_stuck_task" do
      let(:event) { build(:event, event_type: "task_stuck", data: { task_id: task.id, stuck_duration: "30 minutes" }) }

      it "logs the event" do
        expect(Rails.logger).to receive(:info).with(/Received handle_stuck_task for Task #{task.id}/)
        agent.handle_stuck_task(event)
      end
    end

    describe "#handle_resource_critical" do
      let(:event) { build(:event, event_type: "system_resources_critical", data: { resource_type: "CPU", usage_percent: 95 }) }

      it "logs the event" do
        expect(Rails.logger).to receive(:warn).with(/Received handle_resource_critical for CPU at 95%/)
        agent.handle_resource_critical(event)
      end
    end

    describe "#handle_new_project" do
      let(:project) { create(:project, name: "Test Project") }
      let(:event) { build(:event, event_type: "project_created", data: { project_id: project.id, task_id: task.id }) }

      it "logs the event" do
        expect(Rails.logger).to receive(:info).with(/Received handle_new_project for Test Project/)
        agent.handle_new_project(event)
      end
    end
  end

  describe "tool implementations", :vcr do
    describe "#analyze_system_state" do
      let(:llm_response) do
        double(
          "LLMResponse",
          chat_completion: "SYSTEM STATE: Stable\n\nKEY AREAS OF CONCERN:\n- None\n\nRECOMMENDED ACTIONS:\n- Continue monitoring",
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150
        )
      end

      before do
        allow(Task).to receive_message_chain(:active, :count).and_return(5)
        allow(Task).to receive_message_chain(:where, :count).and_return(2)
        allow(AgentActivity).to receive_message_chain(:where, :count).and_return(3)
        allow(SolidQueue::Job).to receive_message_chain(:where, :count).and_return(10)
        allow(SolidQueue::Job).to receive_message_chain(:where, :group, :count).and_return({ "orchestrator" => 1, "coordinator" => 2 })
        allow(Event).to receive_message_chain(:where, :recent, :limit).and_return([])
        allow(agent.llm).to receive(:chat).and_return(llm_response)
      end

      it "gathers system metrics and calls LLM for analysis" do
        expect(agent.llm).to receive(:chat).with(hash_including(:messages)).and_return(llm_response)
        expect(agent).to receive(:log_direct_llm_call)

        result = agent.analyze_system_state

        expect(result).to include("SYSTEM STATE: Stable")
        expect(result).to include("KEY AREAS OF CONCERN")
        expect(result).to include("RECOMMENDED ACTIONS")
      end

      it "incorporates query when provided" do
        expect(agent.llm).to receive(:chat) do |args|
          expect(args[:messages].first[:content]).to include("SPECIFIC QUERY: Check coordinator load")
          llm_response
        end

        agent.analyze_system_state("Check coordinator load")
      end

      it "handles LLM errors" do
        expect(agent.llm).to receive(:chat).and_raise(StandardError.new("LLM API error"))

        result = agent.analyze_system_state

        expect(result).to include("Error analyzing system state: LLM API error")
      end
    end

    describe "#spawn_coordinator" do
      it "creates a coordinator agent job for a task" do
        expect(CoordinatorAgent).to receive(:enqueue).with(
          /This is a (root task|standalone task).*System task\s+Orchestrate system/m,
          hash_including(task_id: task.id, parent_activity_id: agent_activity.id)
        )

        expect(agent_activity.events).to receive(:create!).with(
          hash_including(event_type: "coordinator_spawned", data: hash_including(task_id: task.id))
        )

        result = agent.spawn_coordinator(task.id)

        expect(result).to include("Spawned CoordinatorAgent for")
        expect(result).to include("#{task.id}")
      end

      it "handles missing tasks" do
        expect(Task).to receive(:find).with(999).and_raise(ActiveRecord::RecordNotFound)

        result = agent.send(:spawn_coordinator, 999)

        expect(result).to include("Error: Task with ID 999 not found")
      end

      it "handles other errors" do
        expect(CoordinatorAgent).to receive(:enqueue).and_raise(StandardError.new("Queue error"))

        result = agent.send(:spawn_coordinator, task.id)

        expect(result).to include("Error spawning coordinator for task #{task.id}: Queue error")
      end
    end

    describe "#escalate_to_human" do
      it "creates a human intervention record" do
        intervention = build(:human_intervention, id: 123)

        expect(HumanIntervention).to receive(:create!).with(
          hash_including(
            description: "Critical issue",
            urgency: "high",
            status: "pending",
            agent_activity_id: agent_activity.id
          )
        ).and_return(intervention)

        expect(Event).to receive(:publish).with(
          "human_intervention_requested",
          hash_including(intervention_id: intervention.id, description: "Critical issue", urgency: "high"),
          hash_including(:priority)
        )

        result = agent.send(:escalate_to_human, "Critical issue", "high")

        expect(result).to include("Escalated to human operators with high urgency")
        expect(result).to include("Intervention ID: 123")
      end

      it "sets critical priority for critical urgency" do
        intervention = build(:human_intervention)
        allow(HumanIntervention).to receive(:create!).and_return(intervention)

        expect(Event).to receive(:publish).with(
          "human_intervention_requested",
          anything,
          hash_including(priority: Event::CRITICAL_PRIORITY)
        )

        agent.send(:escalate_to_human, "Critical issue", "critical")
      end

      it "handles errors" do
        expect(HumanIntervention).to receive(:create!).and_raise(StandardError.new("Database error"))

        result = agent.send(:escalate_to_human, "Critical issue")

        expect(result).to include("Error escalating issue: Database error")
      end
    end

    describe "#adjust_system_priorities" do
      let(:task1) { create(:task, id: 1, priority: "normal") }
      let(:task2) { create(:task, id: 2, priority: "low") }

      before do
        allow(Task).to receive(:find).with(1).and_return(task1)
        allow(Task).to receive(:find).with(2).and_return(task2)
      end

      it "adjusts priorities for multiple tasks" do
        expect(task1).to receive(:update!).with(priority: "high")
        expect(task1.events).to receive(:create!).with(
          hash_including(
            event_type: "priority_adjusted",
            data: hash_including(from: "normal", to: "high", adjusted_by: "OrchestratorAgent")
          )
        )

        expect(task2).to receive(:update!).with(priority: "normal")
        expect(task2.events).to receive(:create!).with(
          hash_including(event_type: "priority_adjusted", data: hash_including(from: "low", to: "normal"))
        )

        result = agent.adjust_system_priorities("1:high, 2:normal")

        expect(result).to include("Task 1: priority changed from normal to high")
        expect(result).to include("Task 2: priority changed from low to normal")
      end

      it "handles errors for individual tasks" do
        allow(Task).to receive(:find).with(1).and_return(task1)
        allow(task1).to receive(:update!).and_raise(StandardError.new("Invalid priority"))

        allow(Task).to receive(:find).with(2).and_return(task2)
        allow(task2).to receive(:update!).with(priority: "normal")
        allow(task2.events).to receive(:create!)

        result = agent.send(:adjust_system_priorities, "1:invalid, 2:normal")

        expect(result).to include("Failed to adjust task 1: Invalid priority")
        expect(result).to include("Task 2: priority changed from low to normal")
      end
    end
  end

  # describe "#check_resource_usage", :vcr do
  #   let(:llm_response) do
  #     double(
  #       "LLMResponse",
  #       chat_completion: "RESOURCE HEALTH: Good\n\nCONSTRAINTS:\n- None\n\nRECOMMENDATIONS:\n- Continue monitoring",
  #       prompt_tokens: 100,
  #       completion_tokens: 50,
  #       total_tokens: 150
  #     )
  #   end

  #   before do
  #     allow(ActiveRecord::Base.connection_pool).to receive(:stat).and_return({ connections: 5 })
  #     allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(10)
  #     allow(SolidQueue::Job).to receive_message_chain(:where, :group, :count).and_return({ "orchestrator" => 1, "coordinator" => 2 })
  #     allow(LlmCall).to receive_message_chain(:where, :count).and_return(100)
  #     allow(ENV).to receive(:[]).with("DAILY_LLM_CALL_LIMIT").and_return("1000")
  #     allow(agent.llm).to receive(:chat).and_return(llm_response)
  #   end

  #   it "gathers resource metrics and calls LLM for analysis" do
  #     # Skip platform-specific checks
  #     allow(RUBY_PLATFORM).to receive(:=~).with(/darwin/).and_return(false)
  #     allow(RUBY_PLATFORM).to receive(:=~).with(/linux/).and_return(false)

  #     # Mock ALL ENV calls that might be used, not just DAILY_LLM_CALL_LIMIT
  #     allow(ENV).to receive(:[]).and_call_original
  #     allow(ENV).to receive(:[]).with("DAILY_LLM_CALL_LIMIT").and_return("1000")
  #     allow(ENV).to receive(:[]).with("OPEN_ROUTER_API_KEY").and_return("test_key")
  #     allow(ENV).to receive(:[]).with("ENABLE_RACTORS").and_return(nil)

  #     expect(agent.llm).to receive(:chat).with(hash_including(:messages)).and_return(llm_response)
  #     expect(agent).to receive(:log_direct_llm_call)

  #     result = agent.send(:check_resource_usage)

  #     expect(result).to include("RESOURCE HEALTH: Good")
  #     expect(result).to include("CONSTRAINTS")
  #     expect(result).to include("RECOMMENDATIONS")
  #   end

  #   it "handles LLM errors" do
  #     # Skip platform-specific checks
  #     allow(RUBY_PLATFORM).to receive(:=~).with(/darwin/).and_return(false)
  #     allow(RUBY_PLATFORM).to receive(:=~).with(/linux/).and_return(false)

  #     # Mock ALL ENV calls that might be used, not just DAILY_LLM_CALL_LIMIT
  #     allow(ENV).to receive(:[]).and_call_original
  #     allow(ENV).to receive(:[]).with("DAILY_LLM_CALL_LIMIT").and_return("1000")
  #     allow(ENV).to receive(:[]).with("OPEN_ROUTER_API_KEY").and_return("test_key")
  #     allow(ENV).to receive(:[]).with("ENABLE_RACTORS").and_return(nil)

  #     expect(agent.llm).to receive(:chat).and_raise(StandardError.new("LLM API error"))

  #     result = agent.send(:check_resource_usage)

  #     expect(result).to include("Error analyzing resource usage: LLM API error")
  #   end
  # end

  describe "run method", :vcr do
    let(:system_analysis) { "SYSTEM STATE: Stable\n\nKEY AREAS OF CONCERN:\n- None" }
    let(:resource_analysis) { "RESOURCE HEALTH: Good\n\nCONSTRAINTS:\n- None" }

    before do
      allow(agent).to receive(:execute_tool).and_call_original
      allow(agent).to receive(:analyze_system_state).and_return(system_analysis)
      allow(agent).to receive(:check_resource_usage).and_return(resource_analysis)
    end

    it "analyzes system state and resource usage" do
      expect(agent).to receive(:execute_tool).with(:analyze_system_state, anything).and_return(system_analysis)
      expect(agent).to receive(:execute_tool).with(:check_resource_usage).and_return(resource_analysis)

      result = agent.run

      expect(result).to include("System/Resource analysis complete")
    end

    it "escalates issues when concerns are detected" do
      concerned_analysis = "SYSTEM STATE: Warning\n\nKEY AREAS OF CONCERN:\n- High queue depth"

      expect(agent).to receive(:execute_tool).with(:analyze_system_state, anything).and_return(concerned_analysis)
      expect(agent).to receive(:execute_tool).with(:check_resource_usage).and_return(resource_analysis)
      expect(agent).to receive(:execute_tool).with(:escalate_to_human, anything, "normal").and_return("Escalated")

      result = agent.run

      expect(result).to include("Concerns found and escalated")
    end

    it "handles errors during execution" do
      expect(agent).to receive(:execute_tool).with(:analyze_system_state, anything).and_raise(StandardError.new("Analysis error"))
      expect(agent).to receive(:handle_run_error)

      expect { agent.run }.to raise_error(StandardError, "Analysis error")
    end
  end

  describe "lifecycle hooks" do
    it "logs decisions in after_run" do
      # Adjust the expectation to match what the implementation actually logs
      # We need to allow any log messages, but specifically expect the summary log
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with("OrchestratorAgent Run Summary: Test result")
      allow(Rails.logger).to receive(:debug)

      agent.after_run("Test result")
    end
  end
end
