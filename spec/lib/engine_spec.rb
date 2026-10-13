# frozen_string_literal: true

RSpec.describe UserNetworkVis::Engine do
  it "registers Ruby paths with Zeitwerk and eagerly loads the hourly job" do
    loader = Rails.autoloaders.main
    expected_constants = {
      "app/controllers/user_network_vis/user_network_stats_controller.rb" =>
        "UserNetworkVis::UserNetworkStatsController",
      "app/jobs/onceoff/create_user_network_explorer_queries.rb" =>
        "Jobs::CreateUserNetworkExplorerQueries",
      "app/jobs/scheduled/user_network_stats_calc.rb" => "Jobs::UserNetworkStatsCalc",
      "lib/user_network_vis/engine.rb" => "UserNetworkVis::Engine",
    }

    expected_constants.each do |path, constant|
      expect(loader.cpath_expected_at(described_class.root.join(path))).to eq(constant)
    end

    expect(Jobs.autoload?(:UserNetworkStatsCalc)).to be_nil
    expect(Jobs::UserNetworkStatsCalc.every).to eq(1.hour)

    %w[app/controllers app/jobs lib].each do |path|
      expect { loader.eager_load_dir(described_class.root.join(path)) }.not_to raise_error
    end
  end
end
