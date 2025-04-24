class DashboardController < ApplicationController
  # Refresh dashboard data every 5 seconds
  def index
    @projects = Project.order(created_at: :desc).limit(10)
    @agent_activities = AgentActivity.order(created_at: :desc).limit(20)
    @llm_calls = LlmCall.order(created_at: :desc).limit(15)
    @tasks = Task.where(state: [ "active", "pending", "waiting_on_human" ]).order(created_at: :desc).limit(10)
    # Fetch active interventions specifically
    @human_interactions = HumanInteraction.interventions.active_interventions.order(urgency: :desc, created_at: :desc).limit(5)
    # Fetch pending input requests
    @human_input_requests = HumanInteraction.input_requests.pending.order(created_at: :desc).limit(5)
    # Removed fallback logic for old HumanInputRequest model

    # For Turbo Stream updates
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end
end
