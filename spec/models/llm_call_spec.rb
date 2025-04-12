require 'rails_helper'

RSpec.describe LlmCall, type: :model do
  describe "associations" do
    it { should belong_to(:agent_activity) }
  end
end
