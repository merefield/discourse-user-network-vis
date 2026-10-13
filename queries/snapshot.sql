-- [params]
-- text :username = %

WITH snapshot AS (
  SELECT value::jsonb AS data
  FROM plugin_store_rows
  WHERE plugin_name = 'user_network_vis' AND key = 'user_network_list'
), nodes AS (
  SELECT node.id AS username, node."group" AS trust_level
  FROM snapshot, jsonb_to_recordset(data->'nodes') AS node(id text, "group" integer)
), edges AS (
  SELECT edge.*
  FROM snapshot, jsonb_to_recordset(data->'links') AS edge(source text, target text, value numeric)
)
SELECT source_user.id AS source_user_id,
       edges.source AS source_username,
       source_node.trust_level AS source_trust_level,
       target_user.id AS target_user_id,
       edges.target AS target_username,
       target_node.trust_level AS target_trust_level,
       edges.value AS weighted_score
FROM edges
LEFT JOIN users source_user ON source_user.username_lower = edges.source
LEFT JOIN users target_user ON target_user.username_lower = edges.target
LEFT JOIN nodes source_node ON source_node.username = edges.source
LEFT JOIN nodes target_node ON target_node.username = edges.target
WHERE edges.source ILIKE :username OR edges.target ILIKE :username
ORDER BY weighted_score DESC, source_username, target_username
