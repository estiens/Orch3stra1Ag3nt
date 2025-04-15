# frozen_string_literal: true

# AgentSpawningService provides centralized logic for spawning agents
# This ensures consistent agent creation across the application
class AgentSpawningService
  include Singleton

  # Class methods - delegates to instance
  class << self
    delegate :spawn_for_task, :spawn_for_project, :spawn_for_event, to: :instance
  end

  attr_reader :logger

  def initialize
    @logger = Rails.logger
  end

  # Spawn an appropriate agent for a task based on its type
  # @param task [Task] the task to spawn an agent for
  # @param options [Hash] additional options for the agent
  # @return [AgentActivity] the created agent activity
  def spawn_for_task(task, options = {})
    logger.info("Spawning agent for task: #{task.title} [#{task.id}]")
    
    # Determine the appropriate agent class based on task type
    agent_class = agent_class_for_task(task)
    
    if agent_class.nil?
      logger.error("No agent class found for task type: #{task.task_type}")
      return nil
    end
    
    # Prepare agent options
    agent_options = {
      task_id: task.id,
      purpose: "Process task: #{task.title}",
      context: { task_id: task.id, project_id: task.project_id }
    }.merge(options)
    
    # Enqueue the agent job
    result = agent_class.enqueue(
      "Process task: #{task.title}",
      agent_options
    )
    
    # The result could be an AgentActivity or an AgentJob depending on the environment
    if result.is_a?(AgentActivity)
      agent_activity = result
      logger.info("Spawned #{agent_class.name} for task: #{task.id}, agent activity: #{agent_activity.id}")
    else
      logger.info("Enqueued #{agent_class.name} for task: #{task.id}")
    end
    
    result
  end
  
  # Spawn an appropriate agent for a project
  # @param project [Project] the project to spawn an agent for
  # @param options [Hash] additional options for the agent
  # @return [AgentActivity] the created agent activity
  def spawn_for_project(project, options = {})
    logger.info("Spawning agent for project: #{project.title} [#{project.id}]")
    
    # For projects, we typically use the OrchestratorAgent
    agent_class = OrchestratorAgent
    
    # Prepare agent options
    agent_options = {
      project_id: project.id,
      purpose: "Orchestrate project: #{project.title}",
      context: { project_id: project.id }
    }.merge(options)
    
    # Enqueue the agent job
    result = agent_class.enqueue(
      "Orchestrate project: #{project.title}",
      agent_options
    )
    
    # The result could be an AgentActivity or an AgentJob depending on the environment
    if result.is_a?(AgentActivity)
      agent_activity = result
      logger.info("Spawned #{agent_class.name} for project: #{project.id}, agent activity: #{agent_activity.id}")
    else
      logger.info("Enqueued #{agent_class.name} for project: #{project.id}")
    end
    
    result
  end
  
  # Spawn an agent in response to an event
  # @param event [Event] the event to spawn an agent for
  # @param agent_class [Class] the agent class to use
  # @param options [Hash] additional options for the agent
  # @return [AgentActivity] the created agent activity
  def spawn_for_event(event, agent_class, options = {})
    logger.info("Spawning agent for event: #{event.event_type} [#{event.id}]")
    
    # Prepare agent options
    agent_options = {
      event_id: event.id,
      event_data: event.data,
      purpose: options[:purpose] || "Process event: #{event.event_type}",
      context: event.context || {}
    }.merge(options)
    
    # Enqueue the agent job
    result = agent_class.enqueue(
      "Process event: #{event.event_type}",
      agent_options
    )
    
    # The result could be an AgentActivity or an AgentJob depending on the environment
    if result.is_a?(AgentActivity)
      agent_activity = result
      logger.info("Spawned #{agent_class.name} for event: #{event.id}, agent activity: #{agent_activity.id}")
    else
      logger.info("Enqueued #{agent_class.name} for event: #{event.id}")
    end
    
    result
  end
  
  private
  
  # Determine the appropriate agent class based on task type
  # @param task [Task] the task to determine the agent class for
  # @return [Class] the agent class to use
  def agent_class_for_task(task)
    case task.task_type.to_s
    when "research"
      ResearchCoordinatorAgent
    when "code"
      CodeResearcherAgent
    when "analysis", "search"
      WebResearcherAgent
    when "review"
      SummarizerAgent
    when "orchestration"
      OrchestratorAgent
    else
      # Default to CoordinatorAgent for unknown task types
      CoordinatorAgent
    end
  end
end
