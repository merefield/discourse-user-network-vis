module ::UserNetworkVis
  class Engine < ::Rails::Engine
    engine_name 'user_network_vis'
    isolate_namespace UserNetworkVis
  end
  
  PLUGIN_NAME ||= 'user_network_vis'
end