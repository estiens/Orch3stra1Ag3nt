class HumanInteractionsController < ApplicationController # Renamed class
  before_action :set_human_interaction, only: [ :show, :respond, :submit_response, :ignore ] # Renamed filter

  def show
    # Show details of a specific human interaction (input request or intervention)
    # TODO: View might need adjustment based on interaction_type
  end

  def respond
    # Show form to respond to the input request
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def submit_response
    # Assuming this action is only for input_requests
    if @human_interaction.input_request? && @human_interaction.answer!(params[:response])
      respond_to do |format|
        format.html { redirect_to dashboard_path, notice: "Response submitted successfully." }
        format.turbo_stream { flash.now[:notice] = "Response submitted successfully." }
      end
    else
      respond_to do |format|
        format.html { render :respond, status: :unprocessable_entity }
        format.turbo_stream { flash.now[:alert] = "Could not submit response." }
      end
    end
  end

  def ignore
    # Assuming this action is only for optional input_requests
    if @human_interaction.input_request? && !@human_interaction.required? && @human_interaction.ignore!(params[:reason])
      respond_to do |format|
        format.html { redirect_to dashboard_path, notice: "Input request ignored." }
        format.turbo_stream { flash.now[:notice] = "Input request ignored." }
      end
    else
      respond_to do |format|
        alert_message = "Could not ignore input request."
        alert_message = "Cannot ignore required input requests." if @human_interaction.required?
        alert_message = "Cannot ignore interventions." unless @human_interaction.input_request?
        format.html { redirect_to dashboard_path, alert: alert_message }
        format.turbo_stream { flash.now[:alert] = alert_message }
      end
    end
  end

  private

  def set_human_interaction # Renamed method
    # Find any type of interaction for show, but check type in actions
    @human_interaction = HumanInteraction.find(params[:id])
  end
end
