class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :edit, :update, :destroy, :kickoff, :pause, :resume ]

  # GET /projects
  def index
    @projects = Project.recent.all
  end

  # GET /projects/1
  def show
    @tasks = @project.tasks.order(created_at: :desc)
    @stats = @project.task_status_counts
    @llm_stats = @project.llm_call_stats
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
  
  # POST /projects/1/pause
  def pause
    if @project.status == "active"
      if @project.pause!
        notice = "Project paused successfully."
      else
        notice = "Could not pause project."
      end
      
      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path, notice: notice) }
        format.turbo_stream { 
          flash.now[:notice] = notice
          render turbo_stream: [
            turbo_stream.replace("projects-container", 
              partial: "dashboard/projects", 
              locals: { projects: Project.order(created_at: :desc).limit(10) }),
            turbo_stream.replace("flash", 
              partial: "layouts/flash")
          ]
        }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path, alert: "Could not pause project.") }
        format.turbo_stream { 
          flash.now[:alert] = "Could not pause project."
          render turbo_stream: turbo_stream.replace("flash", partial: "layouts/flash")
        }
      end
    end
  end
  
  # POST /projects/1/resume
  def resume
    if @project.status == "paused"
      if @project.resume!
        notice = "Project resumed successfully."
      else
        notice = "Could not resume project."
      end
      
      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path, notice: notice) }
        format.turbo_stream { 
          flash.now[:notice] = notice
          render turbo_stream: [
            turbo_stream.replace("projects-container", 
              partial: "dashboard/projects", 
              locals: { projects: Project.order(created_at: :desc).limit(10) }),
            turbo_stream.replace("flash", 
              partial: "layouts/flash")
          ]
        }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path, alert: "Could not resume project.") }
        format.turbo_stream { 
          flash.now[:alert] = "Could not resume project."
          render turbo_stream: turbo_stream.replace("flash", partial: "layouts/flash")
        }
      end
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
