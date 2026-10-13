-- [params]
-- int :lookback_days = 30
-- int :account_age_days = 90
-- int :minimum_interactions = 10
-- int :maximum_counterparts = 3
-- int :minimum_top_counterpart_percent = 80

WITH public_posts AS NOT MATERIALIZED (
  SELECT posts.id, posts.topic_id, posts.post_number, posts.user_id,
         posts.reply_to_post_number, posts.created_at
  FROM posts
  JOIN topics ON topics.id = posts.topic_id
  LEFT JOIN categories ON categories.id = topics.category_id
  WHERE posts.deleted_at IS NULL AND NOT posts.hidden
    AND posts.post_type = 1
    AND topics.deleted_at IS NULL AND topics.visible
    AND topics.archetype <> 'private_message'
    AND (topics.category_id IS NULL OR NOT categories.read_restricted)
), events AS (
  SELECT actions.acting_user_id AS actor_id, actions.user_id AS recipient_id,
         'like' AS kind
  FROM user_actions actions
  JOIN public_posts posts ON posts.id = actions.target_post_id
  WHERE actions.action_type = 2
    AND actions.created_at >= CURRENT_TIMESTAMP - make_interval(days => GREATEST(1, LEAST(:lookback_days, 365)))
  UNION ALL
  SELECT reply.user_id, original.user_id, 'reply'
  FROM public_posts reply
  JOIN public_posts original ON original.topic_id = reply.topic_id
    AND original.post_number = reply.reply_to_post_number
  WHERE reply.created_at >= CURRENT_TIMESTAMP - make_interval(days => GREATEST(1, LEAST(:lookback_days, 365)))
), interactions AS (
  SELECT recipient_id AS user_id, actor_id AS counterpart_id, kind, TRUE AS received
  FROM events WHERE actor_id <> recipient_id AND actor_id > 0 AND recipient_id > 0
  UNION ALL
  SELECT actor_id, recipient_id, kind, FALSE
  FROM events WHERE actor_id <> recipient_id AND actor_id > 0 AND recipient_id > 0
), pairs AS (
  SELECT user_id, counterpart_id, COUNT(*) AS interactions,
         COUNT(*) FILTER (WHERE received) AS received,
         COUNT(*) FILTER (WHERE NOT received) AS given,
         COUNT(*) FILTER (WHERE received AND kind = 'like') AS likes_received,
         COUNT(*) FILTER (WHERE received AND kind = 'reply') AS replies_received
  FROM interactions
  GROUP BY user_id, counterpart_id
), ranked AS (
  SELECT pairs.*, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY interactions DESC, counterpart_id) AS rank
  FROM pairs
), summary AS (
  SELECT user_id, COUNT(*) AS counterpart_count, SUM(interactions) AS total_interactions,
         SUM(likes_received) AS likes_received, SUM(replies_received) AS replies_received,
         SUM(given) AS interactions_given,
         COUNT(*) FILTER (WHERE received > 0 AND given > 0) AS reciprocal_counterparts,
         ROUND(100.0 * MAX(interactions) / SUM(interactions), 1) AS top_counterpart_percent,
         MAX(counterpart_id) FILTER (WHERE rank = 1) AS top_counterpart_user_id
  FROM ranked
  GROUP BY user_id
)
SELECT users.id AS user_id, users.username, users.created_at AS account_created_at,
       users.trust_level, summary.counterpart_count, summary.total_interactions,
       summary.likes_received, summary.replies_received, summary.interactions_given,
       summary.reciprocal_counterparts, summary.top_counterpart_percent,
       summary.top_counterpart_user_id, counterpart.username AS top_counterpart_username,
       counterpart.created_at AS top_counterpart_created_at,
       counterpart.trust_level AS top_counterpart_trust_level
FROM summary
JOIN users ON users.id = summary.user_id
JOIN users counterpart ON counterpart.id = summary.top_counterpart_user_id
WHERE users.created_at >= CURRENT_TIMESTAMP - make_interval(days => GREATEST(1, LEAST(:account_age_days, 3650)))
  AND NOT users.admin AND NOT users.moderator
  AND summary.total_interactions >= GREATEST(1, :minimum_interactions)
  AND summary.counterpart_count <= GREATEST(1, :maximum_counterparts)
  AND summary.top_counterpart_percent >= GREATEST(0, LEAST(:minimum_top_counterpart_percent, 100))
ORDER BY summary.top_counterpart_percent DESC, summary.total_interactions DESC, users.id
