# This module is now deprecated in favor of using the EventBus system
# It's kept for backward compatibility but doesn't do anything
module DashboardBroadcaster
  extend ActiveSupport::Concern
  
  # No callbacks or methods needed as we're using the event system instead
end
