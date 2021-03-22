Discourse::Application.routes.append do
  mount ::UserNetworkVis::Engine, at: "/"
end

UserNetworkVis::Engine.routes.draw do
  get "usernetworkvis" => "user_network_stats#data"
end
