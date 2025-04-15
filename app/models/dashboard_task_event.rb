class DashboardTaskEvent < ApplicationRecord
  belongs_to :task
  
  # Event types
  EVENT_TYPES = %w[activated paused resumed completed failed].freeze
  validates :event_type, inclusion: { in: EVENT_TYPES }
  
  # Broadcast to dashboard after creation
  after_create_commit :broadcast_to_dashboard
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  
  private
  
  def broadcast_to_dashboard
    # Broadcast task update to dashboard
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "tasks-container",
      partial: "dashboard/tasks",
      locals: { tasks: Task.where(state: ["active", "pending", "waiting_on_human", "paused"]).order(created_at: :desc).limit(10) }
    )
  end
end
