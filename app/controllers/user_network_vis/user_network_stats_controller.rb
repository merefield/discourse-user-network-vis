# frozen_string_literal: true

class ::UserNetworkVis::UserNetworkStatsController < ::ApplicationController
  requires_plugin "discourse-user-network-vis"

  def data
    raise Discourse::InvalidAccess.new unless current_user

    result = PluginStore.get(::UserNetworkVis::PLUGIN_NAME, "user_network_list")

    render_json_dump user_network_stats: result
  end
end
