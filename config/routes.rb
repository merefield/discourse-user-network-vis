# frozen_string_literal: true

UserNetworkVis::Engine.routes.draw { get "usernetworkvis" => "user_network_stats#data" }

Discourse::Application.routes.draw { mount ::UserNetworkVis::Engine, at: "/" }
