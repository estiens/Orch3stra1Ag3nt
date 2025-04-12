require 'rails_helper'

RSpec.describe Task, type: :model do
  describe "associations" do
    it { should have_many(:agent_activities).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:title) }
  end

  describe "state machine" do
    let(:task) { build(:task) }

    it "has initial state pending" do
      expect(task.aasm.current_state).to eq(:pending)
    end

    it "transitions from pending to active" do
      task.save!
      expect { task.activate! }.to change { task.aasm.current_state }.from(:pending).to(:active)
    end

    it "transitions from active to waiting_on_human" do
      task.save!
      task.activate!
      expect { task.wait_on_human! }.to change { task.aasm.current_state }.from(:active).to(:waiting_on_human)
    end

    it "transitions to completed from active or waiting_on_human" do
      task.save!
      task.activate!
      expect { task.complete! }.to change { task.aasm.current_state }.from(:active).to(:completed)

      task = create(:task, state: :waiting_on_human)
      expect { task.complete! }.to change { task.aasm.current_state }.from(:waiting_on_human).to(:completed)
    end

    it "transitions to failed from any state" do
      task.save!
      expect { task.fail! }.to change { task.aasm.current_state }.from(:pending).to(:failed)

      task = create(:task, state: :active)
      expect { task.fail! }.to change { task.aasm.current_state }.from(:active).to(:failed)
    end
  end
end
