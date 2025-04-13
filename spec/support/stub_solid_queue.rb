module StubSolidQueue
  class Job
    def self.enqueue(*args)
      # no-op stub for enqueue
    end

    def self.where(*args)
      []
    end

    def self.cancel_all(*args)
      true
    end

    def self.count
      0
    end
  end
end

# Define SolidQueue module with a stubbed Job for tests
module SolidQueue
  Job = StubSolidQueue::Job
end
