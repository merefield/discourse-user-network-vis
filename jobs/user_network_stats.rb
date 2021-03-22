module Jobs
  # frozen_string_literal: true
  class UserNetworkStatsCalc < ::Jobs::Scheduled
    every 1.hours

    def execute(args={})

      user_network_list = []
      user_network_link_list = []

        build = DB.build <<-SQL

        select source_user_id, target_user_id, sum(score) as score from (
          (SELECT user_actions.user_id as source_user_id, user_actions.acting_user_id as target_user_id, count(*) as score FROM user_actions
          INNER JOIN topics ON topics.deleted_at IS NULL AND topics.id = user_actions.target_topic_id
          INNER JOIN posts ON posts.deleted_at IS NULL AND posts.id = user_actions.target_post_id
          WHERE topics.deleted_at IS NULL
          AND (topics.archetype <> 'private_message')
          AND topics.visible = TRUE
          AND (topics.category_id IS NULL OR topics.category_id IN (SELECT id FROM categories WHERE NOT read_restricted))
          AND user_actions.action_type = 2 GROUP BY user_actions.user_id, user_actions.acting_user_id ORDER BY COUNT(*) DESC)
          UNION
          (SELECT posts.user_id as source_user_id, replies.user_id as target_user_id, count(*) as score
          FROM posts INNER JOIN topics ON topics.deleted_at IS NULL AND topics.id = posts.topic_id AND (topics.archetype <> 'private_message')
          JOIN posts replies ON posts.topic_id = replies.topic_id AND posts.reply_to_post_number = replies.post_number
          WHERE posts.deleted_at IS NULL AND posts.user_id <> replies.user_id
          GROUP BY posts.user_id, replies.user_id ORDER BY COUNT(*) DESC
          )) alias
          GROUP BY source_user_id, target_user_id
          ORDER BY score DESC

        SQL

      result = build.query

      result.each do |entry|
      
        user_network_list |= [entry.source_user_id]
        user_network_list |= [entry.target_user_id]

        source_user = User.find_by(id: entry.source_user_id)
        target_user = User.find_by(id: entry.target_user_id)
        
        # already_exists = user_network_link_list.select do |item|
        #   (item[:source] == target_user.username_lower && item[:target] == source_user.username_lower)
        # end

        # unless already_exists.length > 0
          user_network_link_list << {source: source_user.username_lower, target: target_user.username_lower, value: entry.score}
        # end
      end

      user_nodes = []

      user_network_list.each do |entry|

        user = User.find_by(id: entry)
        user_nodes << {id: user.username_lower, group: user.trust_level}

      end 

      user_network_vis_list = {nodes: user_nodes, links: user_network_link_list}

      PluginStore.set(::UserNetworkVis::PLUGIN_NAME, "user_network_list", user_network_vis_list.as_json)

      Rails.logger.info ("User Network Visualisation: #{user_network_link_list.count} user link statistics updated")
    end
  end
end
