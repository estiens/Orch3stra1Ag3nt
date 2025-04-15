class DashboardProjectEvent < ApplicationRecord
  belongs_to :project
  
  # Event types
  EVENT_TYPES = %w[created activated paused resumed completed].freeze
  validates :event_type, inclusion: { in: EVENT_TYPES }
  
  # Broadcast to dashboard after creation
  after_create_commit :broadcast_to_dashboard
  
  private
  
  def broadcast_to_dashboard
    # Broadcast project update to dashboard
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "projects-container",
      partial: "dashboard/projects",
      locals: { projects: Project.order(created_at: :desc).limit(10) }
    )
  end
end
