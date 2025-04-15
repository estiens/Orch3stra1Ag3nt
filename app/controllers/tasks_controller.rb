class TasksController < ApplicationController
  before_action :set_task, only: [:show, :edit, :update, :destroy, :activate, :pause, :resume]

  def index
    @tasks = Task.all
  end

  def show
  end

  def new
    @task = Task.new
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
    @task.update(state: 'active')
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: 'Task was activated.') }
      format.turbo_stream { 
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human"]).order(created_at: :desc).limit(10)
        render turbo_stream: turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks })
      }
    end
  end

  def pause
    @task.update(state: 'paused')
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: 'Task was paused.') }
      format.turbo_stream { 
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human"]).order(created_at: :desc).limit(10)
        render turbo_stream: turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks })
      }
    end
  end

  def resume
    @task.update(state: 'active')
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: 'Task was resumed.') }
      format.turbo_stream { 
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human"]).order(created_at: :desc).limit(10)
        render turbo_stream: turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks })
      }
    end
  end
  
  def complete
    @task.update(state: 'completed')
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: 'Task was marked as completed.') }
      format.turbo_stream { 
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human"]).order(created_at: :desc).limit(10)
        render turbo_stream: turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks })
      }
    end
  end
  
  def fail
    @task.update(state: 'failed')
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: @task, notice: 'Task was marked as failed.') }
      format.turbo_stream { 
        @tasks = Task.where(state: ["active", "pending", "waiting_on_human"]).order(created_at: :desc).limit(10)
        render turbo_stream: turbo_stream.replace("tasks-container", partial: "dashboard/tasks", locals: { tasks: @tasks })
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
