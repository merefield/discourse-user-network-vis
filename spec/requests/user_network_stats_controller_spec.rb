# frozen_string_literal: true

RSpec.describe UserNetworkVis::UserNetworkStatsController do
  fab!(:user)

  describe "#data" do
    before { SiteSetting.user_network_vis_enabled = true }

    it "returns the snapshot to a signed-in member" do
      snapshot = {
        "nodes" => [{ "id" => user.username_lower, "group" => user.trust_level }],
        "links" => [],
      }
      PluginStore.set(UserNetworkVis::PLUGIN_NAME, "user_network_list", snapshot)
      sign_in(user)

      get "/usernetworkvis.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["user_network_stats"]).to eq(snapshot)
    end

    it "rejects anonymous access" do
      get "/usernetworkvis.json"

      expect(response.status).to eq(403)
    end

    it "rejects signed-in access when the plugin is disabled" do
      sign_in(user)
      SiteSetting.user_network_vis_enabled = false

      get "/usernetworkvis.json"

      expect(response.status).to eq(404)
    end
  end
end
