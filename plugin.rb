# frozen_string_literal: true

# name: discourse-user-network-vis
# about: Builds and displays a user network visualisation
# email contacts: merefield@gmail.com
# version: 1.2
# authors: Robert Barrow
# url: https://github.com/merefield/discourse-user-network-vis

enabled_site_setting :user_network_vis_enabled

register_asset "stylesheets/common.scss"

after_initialize do
  require_relative "lib/engine"
  require_relative "jobs/user_network_stats"
  require_relative "app/jobs/onceoff/create_user_network_explorer_queries"
  require_relative "app/controllers/user_network_stats"
  require_relative "config/routes"
end
