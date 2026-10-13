# frozen_string_literal: true

Discourse::Application.routes.append { mount ::UserNetworkVis::Engine, at: "/" }

UserNetworkVis::Engine.routes.draw { get "usernetworkvis" => "user_network_stats#data" }
