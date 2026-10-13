# frozen_string_literal: true

module Jobs
  class CreateUserNetworkExplorerQueries < ::Jobs::Onceoff
    def execute_onceoff(args)
      return unless defined?(DiscourseDataExplorer::Query)

      DiscourseDataExplorer::Query.transaction do
        %w[snapshot new_user_interactions].each do |key|
          store_key = "explorer_query_#{key}"
          next if PluginStore.get(UserNetworkVis::PLUGIN_NAME, store_key)

          query =
            DiscourseDataExplorer::Query.create!(
              name: I18n.t("user_network_vis.queries.#{key}.name"),
              description: I18n.t("user_network_vis.queries.#{key}.description"),
              sql: File.read(File.expand_path("../../../queries/#{key}.sql", __dir__)),
              user_id: Discourse::SYSTEM_USER_ID,
            )
          PluginStore.set(UserNetworkVis::PLUGIN_NAME, store_key, query.id)
        end
      end
    end
  end
end
