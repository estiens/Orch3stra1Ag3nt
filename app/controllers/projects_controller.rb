class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :edit, :update, :destroy, :kickoff ]

  # GET /projects
  def index
    @projects = Project.recent.all
  end

  # GET /projects/1
  def show
    @root_tasks = @project.root_tasks.order(created_at: :desc)
    @stats = {
      total_tasks: @project.tasks.count,
      pending_tasks: @project.tasks.where(state: :pending).count,
      active_tasks: @project.tasks.where(state: :active).count,
      completed_tasks: @project.tasks.where(state: :completed).count,
      waiting_on_human_tasks: @project.tasks.where(state: :waiting_on_human).count
    }
  end

  # GET /projects/new
  def new
    @project = Project.new
  end

  # GET /projects/1/edit
  def edit
  end

  # POST /projects
  def create
    @project = Project.new(project_params)

    if @project.save
      redirect_to @project, notice: 'Project was successfully created. Click "Kickoff" to start the project.'
    else
      render :new
    end
  end

  # PATCH/PUT /projects/1
  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project was successfully updated."
    else
      render :edit
    end
  end

  # DELETE /projects/1
  def destroy
    @project.destroy
    redirect_to projects_url, notice: "Project was successfully destroyed."
  end

  # POST /projects/1/kickoff
  def kickoff
    if @project.status == "pending"
      orchestration_task = @project.kickoff!
      if orchestration_task
        redirect_to @project, notice: "Project has been kicked off! The system is now planning your project."
      else
        redirect_to @project, alert: "Failed to kickoff project. Is it already active or does it already have tasks?"
      end
    else
      redirect_to @project, alert: "Project can only be kicked off when in pending status."
    end
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description, :priority, :due_date, :settings, :metadata)
  end
end
