class Task < ApplicationRecord
  validates :title, presence: true

  has_many :agent_activities, dependent: :destroy

  # State machine for Task
  # Requires 'aasm' gem. If not installed, add 'gem "aasm"' to your Gemfile and run bundle install.
  include AASM

  aasm column: "state" do
    state :pending, initial: true
    state :active
    state :waiting_on_human
    state :completed
    state :failed

    event :activate do
      transitions from: :pending, to: :active
    end

    event :wait_on_human do
      transitions from: :active, to: :waiting_on_human
    end

    event :complete do
      transitions from: [ :active, :waiting_on_human ], to: :completed
    end

    event :fail do
      transitions from: [ :pending, :active, :waiting_on_human ], to: :failed
    end
  end
end
