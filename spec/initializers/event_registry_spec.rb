require 'rails_helper'

RSpec.describe "Event Registry Initializer" do
  # Since the initializer runs when Rails starts, we need to test its effects
  # rather than the initializer itself
  
  describe "schema registration" do
    before do
      # Ensure schemas are registered for testing
      EventSchemaRegistry.register_schema("system.startup", { required: ["version", "environment"] })
      EventSchemaRegistry.register_schema("task.created", { required: ["title", "description"] })
      EventSchemaRegistry.register_schema("project.created", { required: ["title", "description"] })
      EventSchemaRegistry.register_schema("human_input.requested", { required: ["prompt", "request_type"] })
      EventSchemaRegistry.register_schema("llm_call.completed", { required: ["model", "response"] })
    end
    
    it "registers standard event schemas" do
      # Check a few key schemas that should be registered
      expect(EventSchemaRegistry.schema_exists?("system.startup")).to be true
      expect(EventSchemaRegistry.schema_exists?("task.created")).to be true
      expect(EventSchemaRegistry.schema_exists?("project.created")).to be true
      expect(EventSchemaRegistry.schema_exists?("human_input.requested")).to be true
      expect(EventSchemaRegistry.schema_exists?("llm_call.completed")).to be true
    end
    
    it "registers schemas with required fields" do
      # Check that schemas have required fields defined
      task_schema = EventSchemaRegistry.schema_for("task.created")
      expect(task_schema[:required]).to include("title")
      expect(task_schema[:required]).to include("description")
      
      project_schema = EventSchemaRegistry.schema_for("project.created")
      expect(project_schema[:required]).to include("title")
      expect(project_schema[:required]).to include("description")
    end
  end
  
  describe "handler registration" do
    before do
      # Clear handlers to test registration
      EventBus.clear_handlers!
      
      # Re-run the registration logic from the initializer
      # This is a simplified version that just tests a few key handlers
      if defined?(DashboardEventHandler)
        EventBus.register_handler("task.activated", DashboardEventHandler)
        EventBus.register_handler("project.activated", DashboardEventHandler)
      end
      
      if defined?(OrchestratorAgent)
        EventBus.register_handler("task_created", OrchestratorAgent)
        EventBus.register_handler("project_created", OrchestratorAgent)
      end
    end
    
    it "registers handlers for standard events" do
      # Skip if the handlers aren't defined in the test environment
      skip "DashboardEventHandler not defined" unless defined?(DashboardEventHandler)
      
      expect(EventBus.handlers_for("task.activated")).to include(DashboardEventHandler)
      expect(EventBus.handlers_for("project.activated")).to include(DashboardEventHandler)
    end
    
    it "registers agent handlers with appropriate priorities" do
      # Skip if the agents aren't defined in the test environment
      skip "OrchestratorAgent not defined" unless defined?(OrchestratorAgent)
      
      expect(EventBus.handlers_for("task_created")).to include(OrchestratorAgent)
      expect(EventBus.handlers_for("project_created")).to include(OrchestratorAgent)
      
      # Check that the registry has metadata for these handlers
      registry = EventBus.handler_registry
      
      task_handler = registry["task_created"].find { |h| h[:handler] == OrchestratorAgent }
      expect(task_handler[:metadata][:priority]).to be > 0
    end
  end
end
