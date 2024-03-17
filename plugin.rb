# name: discourse-user-network-vis
# about: Builds and displays a user network visualisation
# email contacts: merefield@gmail.com
# version: 1.0
# authors: Robert Barrow
# url: https://github.com/merefield/discourse-user-network-vis


enabled_site_setting :user_network_vis_enabled

register_asset 'stylesheets/common.scss'

after_initialize do
  %w(
    ../lib/engine.rb
    ../jobs/user_network_stats.rb
    ../app/controllers/user_network_stats.rb
    ../config/routes.rb
  ).each do |path|
    load File.expand_path(path, __FILE__)
  end
end
