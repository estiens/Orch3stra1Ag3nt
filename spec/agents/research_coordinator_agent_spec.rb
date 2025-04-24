# require "rails_helper"

# RSpec.describe ResearchCoordinatorAgent, type: :agent do
#   let(:task) { instance_double("Task", id: 1, title: "Test Research", description: "Describe something", subtasks: [], may_complete?: true) }
#   let(:agent) { described_class.new(purpose: "Test research coordination", task: task) }
#   let(:input) { "What is the best way to test research workflows?" }

#   before do
#     allow(agent).to receive(:task).and_return(task)
#     allow(agent).to receive(:before_run)
#     allow(agent).to receive(:after_run)
#     allow(agent).to receive(:execute_tool).and_return("Analysis complete", "Subtask created with ID 2", "Findings consolidated")
#     allow(agent).to receive(:parse_research_subtasks).and_return([ { title: "Subtask 1", description: "Do research", methods: [ "reading" ] } ])
#     allow(task).to receive(:reload).and_return(task)
#     allow(task).to receive(:subtasks).and_return([])
#     allow(task).to receive(:complete!)
#   end

#   describe "#run" do
#     context "when there are no subtasks" do
#       it "analyzes the research question and creates subtasks" do
#         result = agent.run(input)
#         expect(result).to include("Analyzed research question, created and assigned")
#       end
#     end

#     context "when all subtasks are completed" do
#       before do
#         allow(task).to receive(:subtasks).and_return([
#           instance_double("Subtask", state: "completed"),
#           instance_double("Subtask", state: "completed")
#         ])
#       end

#       it "consolidates findings and marks the task complete" do
#         result = agent.run(input)
#         expect(result).to include("Consolidated findings")
#         expect(task).to have_received(:complete!)
#       end
#     end

#     context "when a subtask fails" do
#       let(:context) { { event_type: "research_subtask_failed", subtask_id: 2, error: "Timeout" } }

#       it "handles the failure and suggests human guidance" do
#         result = agent.run(context: context)
#         expect(result).to include("failed: Timeout")
#       end
#     end

#     context "when no task is associated" do
#       before { allow(agent).to receive(:task).and_return(nil) }

#       it "returns an error message" do
#         result = agent.run(input)
#         expect(result).to include("Error: Agent not associated with a task")
#       end
#     end
#   end
# end
