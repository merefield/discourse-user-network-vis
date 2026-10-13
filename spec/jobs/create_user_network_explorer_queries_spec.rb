# frozen_string_literal: true

RSpec.describe Jobs::CreateUserNetworkExplorerQueries do
  describe "#execute_onceoff" do
    it "leaves installation pending when Data Explorer is unavailable" do
      stub_const(Object, :DiscourseDataExplorer, Module.new) do
        described_class.new.execute_onceoff({})
        expect(PluginStore.get(UserNetworkVis::PLUGIN_NAME, "explorer_query_snapshot")).to be_nil
        expect(
          PluginStore.get(UserNetworkVis::PLUGIN_NAME, "explorer_query_new_user_interactions"),
        ).to be_nil
      end
    end

    it "installs private queries once and preserves administrator edits and deletions" do
      described_class.new.execute_onceoff({})
      ids =
        %w[snapshot new_user_interactions].map do |key|
          PluginStore.get(UserNetworkVis::PLUGIN_NAME, "explorer_query_#{key}")
        end
      queries = DiscourseDataExplorer::Query.where(id: ids).order(:id)
      expect(queries.count).to eq(2)
      expect(queries.map(&:user_id)).to eq([Discourse::SYSTEM_USER_ID] * 2)
      expect(queries.flat_map(&:query_groups)).to be_empty

      queries.first.update!(name: "Custom network query", sql: "SELECT 42")
      queries.last.destroy!
      expect { described_class.new.execute_onceoff({}) }.not_to change(
        DiscourseDataExplorer::Query,
        :count,
      )
      expect(queries.first.reload.sql).to eq("SELECT 42")
    end
  end
end
