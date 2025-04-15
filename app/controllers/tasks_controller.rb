class TasksController < ApplicationController
  before_action :set_task, only: [:show, :edit, :update, :destroy, :activate, :pause, :resume, :complete, :fail]

  def index
    @tasks = Task.includes(:project).order(created_at: :desc)
  end

  def show
  end

  def new
    @task = Task.new
    
    # Pre-select project if project_id is provided
    if params[:project_id].present?
      @task.project_id = params[:project_id]
    end
  end

  def edit
  end

  def create
    @task = Task.new(task_params)

    if @task.save
      redirect_to @task, notice: 'Task was successfully created.'
    else
      render :new
    end
  end

  def update
    if @task.update(task_params)
      redirect_to @task, notice: 'Task was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @task.destroy
    redirect_to tasks_url, notice: 'Task was successfully destroyed.'
  end

  def activate
    if @task.may_activate?
      @task.activate!
      notice = 'Task was activated.'
    else
      notice = 'Task could not be activated.'
    end
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: notice) }
      format.turbo_stream { 
        flash.now[:notice] = notice
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human", "paused"]).order(created_at: :desc).limit(10)
        render turbo_stream: [
          turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks }),
          turbo_stream.replace("flash", partial: "layouts/flash")
        ]
      }
    end
  end

  def pause
    if @task.may_pause?
      @task.pause!
      notice = 'Task was paused.'
    else
      notice = 'Task could not be paused.'
    end
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: notice) }
      format.turbo_stream { 
        flash.now[:notice] = notice
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human", "paused"]).order(created_at: :desc).limit(10)
        render turbo_stream: [
          turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks }),
          turbo_stream.replace("flash", partial: "layouts/flash")
        ]
      }
    end
  end

  def resume
    if @task.may_resume?
      @task.resume!
      notice = 'Task was resumed.'
    else
      notice = 'Task could not be resumed.'
    end
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: notice) }
      format.turbo_stream { 
        flash.now[:notice] = notice
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human", "paused"]).order(created_at: :desc).limit(10)
        render turbo_stream: [
          turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks }),
          turbo_stream.replace("flash", partial: "layouts/flash")
        ]
      }
    end
  end
  
  def complete
    if @task.may_complete?
      @task.complete!
      notice = 'Task was marked as completed.'
    else
      notice = 'Task could not be completed.'
    end
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: notice) }
      format.turbo_stream { 
        flash.now[:notice] = notice
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human", "paused"]).order(created_at: :desc).limit(10)
        render turbo_stream: [
          turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks }),
          turbo_stream.replace("flash", partial: "layouts/flash")
        ]
      }
    end
  end
  
  def fail
    if @task.may_fail?
      @task.fail!
      notice = 'Task was marked as failed.'
    else
      notice = 'Task could not be marked as failed.'
    end
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: notice) }
      format.turbo_stream { 
        flash.now[:notice] = notice
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human", "paused"]).order(created_at: :desc).limit(10)
        render turbo_stream: [
          turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks }),
          turbo_stream.replace("flash", partial: "layouts/flash")
        ]
      }
    end
  end

  private
    def set_task
      @task = Task.find(params[:id])
    end

    def task_params
      params.require(:task).permit(:title, :description, :state, :task_type, :priority, :project_id, :parent_id, metadata: {})
    end
end
