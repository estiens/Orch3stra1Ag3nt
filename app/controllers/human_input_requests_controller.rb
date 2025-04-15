class HumanInputRequestsController < ApplicationController
  before_action :set_human_input_request, only: [ :show, :respond, :submit_response, :ignore ]

  def show
    # Show details of a specific human input request
  end

  def respond
    # Show form to respond to the input request
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def submit_response
    if @human_input_request.answer!(params[:response])
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
    if @human_input_request.ignore!(params[:reason])
      respond_to do |format|
        format.html { redirect_to dashboard_path, notice: "Input request ignored." }
        format.turbo_stream { flash.now[:notice] = "Input request ignored." }
      end
    else
      respond_to do |format|
        format.html { redirect_to dashboard_path, alert: "Could not ignore input request." }
        format.turbo_stream { flash.now[:alert] = "Could not ignore input request." }
      end
    end
  end

  private

  def set_human_input_request
    @human_input_request = HumanInputRequest.find(params[:id])
  end
end
