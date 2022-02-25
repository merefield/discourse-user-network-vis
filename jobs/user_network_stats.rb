module Jobs
  # frozen_string_literal: true
  class UserNetworkStatsCalc < ::Jobs::Scheduled
    every 1.hours

    def execute(args={})

      user_network_list = []
      user_network_link_list = []

      min_tl = SiteSetting.user_network_vis_minimum_trust_level

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
          (SELECT posts.user_id as source_user_id, replies.user_id as target_user_id, count(*) * #{SiteSetting.user_network_vis_reply_multiplier} as score
          FROM posts INNER JOIN topics ON topics.deleted_at IS NULL AND topics.id = posts.topic_id AND (topics.archetype <> 'private_message')
          JOIN posts replies ON posts.topic_id = replies.topic_id AND posts.reply_to_post_number = replies.post_number
          WHERE posts.deleted_at IS NULL AND posts.user_id <> replies.user_id
          GROUP BY posts.user_id, replies.user_id ORDER BY COUNT(*) DESC
          )) alias
          GROUP BY source_user_id, target_user_id
          ORDER BY score DESC

        SQL

      result = build.query

      time_threshold = Time.now - (SiteSetting.user_network_vis_maximum_last_seen_years).year

      result.each do |entry|

        user_network_list |= [entry.source_user_id]
        user_network_list |= [entry.target_user_id]

        source_user = User.find_by(id: entry.source_user_id)
        target_user = User.find_by(id: entry.target_user_id)

        source_user_in_scope = source_user.trust_level >= min_tl && source_user.last_seen_at && source_user.last_seen_at > time_threshold
        target_user_in_scope = target_user.trust_level >= min_tl && target_user.last_seen_at && target_user.last_seen_at > time_threshold

        if source_user_in_scope && target_user_in_scope && entry.score >= SiteSetting.user_network_vis_link_score_threshold
          user_network_link_list << {source: source_user.username_lower, target: target_user.username_lower, value: entry.score}
        end
      end

      user_nodes = []

      user_network_list.each do |entry|

        user = User.find_by(id: entry)

        if user.trust_level >= min_tl && user.last_seen_at && user.last_seen_at > time_threshold
          user_nodes << {id: user.username_lower, group: user.trust_level}
        end
      end 

      user_network_vis_list = {nodes: user_nodes, links: user_network_link_list}

      PluginStore.set(::UserNetworkVis::PLUGIN_NAME, "user_network_list", user_network_vis_list.as_json)

      Rails.logger.info ("User Network Visualisation: #{user_network_link_list.count} user link statistics updated")
    end
  end
end
