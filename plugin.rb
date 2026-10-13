# frozen_string_literal: true

# name: discourse-user-network-vis
# about: Builds and displays a user network visualisation
# email contacts: merefield@gmail.com
# version: 1.2
# authors: Robert Barrow
# url: https://github.com/merefield/discourse-user-network-vis

enabled_site_setting :user_network_vis_enabled

register_asset "stylesheets/common.scss"

module ::UserNetworkVis
  PLUGIN_NAME = "user_network_vis"
end

require_relative "lib/user_network_vis/engine"
