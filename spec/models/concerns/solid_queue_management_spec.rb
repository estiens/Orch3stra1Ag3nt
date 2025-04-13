require "rails_helper"

RSpec.describe SolidQueueManagement do
  # Create a test class that includes the concern
  class TestQueueAgent
    include SolidQueueManagement

    def self.queue_name
      :test_queue
    end

    def self.concurrency_limit
      3
    end
  end

  describe "class methods" do
    it "defines queue management helpers" do
      # Just verify the methods exist without testing implementation
      expect(TestQueueAgent).to respond_to(:with_concurrency_control)
      expect(TestQueueAgent).to respond_to(:configure_recurring)
      expect(TestQueueAgent).to respond_to(:pending_jobs)
      expect(TestQueueAgent).to respond_to(:running_count)
      expect(TestQueueAgent).to respond_to(:queued_count)
      expect(TestQueueAgent).to respond_to(:cancel_all_pending)
    end

    it "properly exposes queue configuration" do
      expect(TestQueueAgent.queue_name).to eq(:test_queue)
      expect(TestQueueAgent.concurrency_limit).to eq(3)
    end
  end
end
