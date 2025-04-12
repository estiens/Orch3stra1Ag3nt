require 'rails_helper'

RSpec.describe AgentActivity, type: :model do
  describe "associations" do
    it { should belong_to(:task) }
    it { should have_many(:llm_calls).dependent(:destroy) }
    it { should have_many(:events).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:agent_type) }
    it { should validate_presence_of(:status) }
  end

  describe "ancestry" do
    it "can have a parent and children using ancestry" do
      parent = create(:agent_activity)
      child = create(:agent_activity, parent: parent)
      expect(child.parent).to eq(parent)
      expect(parent.children).to include(child)
    end

    it "supports multi-level ancestry (ancestors, descendants)" do
      grandparent = create(:agent_activity)
      parent = create(:agent_activity, parent: grandparent)
      child = create(:agent_activity, parent: parent)
      expect(child.parent).to eq(parent)
      expect(parent.parent).to eq(grandparent)
      expect(child.ancestors).to eq([ grandparent, parent ])
      expect(grandparent.descendants).to include(parent, child)
    end

    it "returns the root of the ancestry chain" do
      root = create(:agent_activity)
      mid = create(:agent_activity, parent: root)
      leaf = create(:agent_activity, parent: mid)
      expect(leaf.root).to eq(root)
      expect(mid.root).to eq(root)
      expect(root.root).to eq(root)
    end

    it "returns the path from root to node" do
      root = create(:agent_activity)
      mid = create(:agent_activity, parent: root)
      leaf = create(:agent_activity, parent: mid)
      expect(leaf.path).to eq([ root, mid, leaf ])
    end

    it "returns subtree for a node" do
      root = create(:agent_activity)
      child1 = create(:agent_activity, parent: root)
      child2 = create(:agent_activity, parent: root)
      grandchild = create(:agent_activity, parent: child1)
      expect(root.subtree).to match_array([ root, child1, child2, grandchild ])
      expect(child1.subtree).to match_array([ child1, grandchild ])
    end

    it "handles orphan (root) nodes correctly" do
      root = create(:agent_activity)
      expect(root.parent).to be_nil
      expect(root.ancestors).to be_empty
      expect(root.root?).to be true
    end
  end
end
