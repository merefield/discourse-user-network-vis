# frozen_string_literal: true

module ::UserNetworkVis
  class Engine < ::Rails::Engine
    engine_name "user_network_vis"
    isolate_namespace UserNetworkVis
    config.autoload_paths << File.join(config.root, "lib")
    scheduled_job_dir = "#{config.root}/app/jobs/scheduled"
    config.to_prepare { Rails.autoloaders.main.eager_load_dir(scheduled_job_dir) }
  end
end
