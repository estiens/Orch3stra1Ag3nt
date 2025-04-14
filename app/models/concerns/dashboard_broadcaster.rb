module DashboardBroadcaster
  extend ActiveSupport::Concern

  included do
    after_create_commit -> { broadcast_dashboard_update }
    after_update_commit -> { broadcast_dashboard_update }
  end

  private

  def broadcast_dashboard_update
    # Broadcast to the dashboard channel
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: self.class.name.underscore.pluralize + "-container",
      partial: "dashboard/#{self.class.name.underscore.pluralize}",
      locals: { self.class.name.underscore.pluralize.to_sym => self.class.order(created_at: :desc).limit(20) }
    )
  end
end
