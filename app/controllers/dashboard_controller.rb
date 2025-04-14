class DashboardController < ApplicationController
  # Refresh dashboard data every 5 seconds
  def index
    @projects = Project.order(created_at: :desc).limit(10)
    @agent_activities = AgentActivity.order(created_at: :desc).limit(20)
    @events = Event.order(created_at: :desc).limit(30)
    
    # For Turbo Stream updates
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end
end
