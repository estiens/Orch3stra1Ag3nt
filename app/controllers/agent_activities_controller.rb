class AgentActivitiesController < ApplicationController
  before_action :set_agent_activity, only: [ :show, :pause, :resume ]

  def show
    # Load related data for the agent activity
    @llm_calls = @agent_activity.llm_calls.order(created_at: :desc)
    @events = @agent_activity.events.order(created_at: :desc)

    # Check for ancestry
    if @agent_activity.ancestry.present?
      @ancestors = @agent_activity.ancestors
    end

    # Get children
    @children = @agent_activity.children
  end

  def pause
    if @agent_activity.pause!
      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path, notice: "Agent paused successfully.") }
        format.turbo_stream { flash.now[:notice] = "Agent paused successfully." }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path, alert: "Could not pause agent.") }
        format.turbo_stream { flash.now[:alert] = "Could not pause agent." }
      end
    end
  end

  def resume
    if @agent_activity.resume!
      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path, notice: "Agent resumed successfully.") }
        format.turbo_stream { flash.now[:notice] = "Agent resumed successfully." }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path, alert: "Could not resume agent.") }
        format.turbo_stream { flash.now[:alert] = "Could not resume agent." }
      end
    end
  end

  private

  def set_agent_activity
    @agent_activity = AgentActivity.find(params[:id])
  end
end
