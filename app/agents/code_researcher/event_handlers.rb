# frozen_string_literal: true

module CodeResearcher
  module EventHandlers
    # Handle code research task event
    def handle_code_research_task(event)
      task_id = event.data["task_id"]
      return if task_id.blank?

      begin
        research_task = Task.find(task_id)
        Rails.logger.info "[CodeResearcherAgentEventHandler] Received handle_code_research_task for Task #{task_id}: #{research_task.title}."
        # This could trigger a new agent run if needed
        # CodeResearcherAgent.enqueue(
        #   "Research code for: #{research_task.title}",
        #   { task_id: task_id, purpose: "Research code for task #{task_id}" }
        # )
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error "[CodeResearcherAgentEventHandler] Task #{task_id} not found for handle_code_research_task."
      end
    end

    # Handle code discovery event
    def handle_code_discovery(event)
      discovery_data = event.data["discovery"]
      task_id = event.data["task_id"]
      return if discovery_data.blank? || task_id.blank?

      begin
        research_task = Task.find(task_id)
        Rails.logger.info "[CodeResearcherAgentEventHandler] Received handle_code_discovery for Task #{task_id}."

        # Could update task metadata with discovery
        current_notes = research_task.metadata&.dig("research_notes") || []
        updated_notes = current_notes + [ "Code discovery: #{discovery_data}" ]
        research_task.update!(metadata: (research_task.metadata || {}).merge({ "research_notes" => updated_notes }))

        Rails.logger.info "[CodeResearcherAgentEventHandler] Updated task #{task_id} with code discovery note."
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error "[CodeResearcherAgentEventHandler] Task #{task_id} not found for handle_code_discovery."
      rescue => e
        Rails.logger.error "[CodeResearcherAgentEventHandler] Error handling code discovery: #{e.message}"
      end
    end

    # Handle research findings event
    def handle_research_findings(event)
      findings = event.data["findings"]
      task_id = event.data["task_id"]
      return if findings.blank? || task_id.blank?

      begin
        research_task = Task.find(task_id)
        Rails.logger.info "[CodeResearcherAgentEventHandler] Received handle_research_findings for Task #{task_id}."

        # Could update task result with findings
        research_task.update!(result: findings)
        Rails.logger.info "[CodeResearcherAgentEventHandler] Updated task #{task_id} with research findings."
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error "[CodeResearcherAgentEventHandler] Task #{task_id} not found for handle_research_findings."
      rescue => e
        Rails.logger.error "[CodeResearcherAgentEventHandler] Error handling research findings: #{e.message}"
      end
    end
  end
end
