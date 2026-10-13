# Discourse User Network Visualisation Plugin

A plugin which generates a D3 network graph for users to analyse social connections between users

To learn more, check out: https://meta.discourse.org/t/community-network-visualisation/184189

## Username search

The graph's search uses the loaded nodes only, with no server requests. Each
keypress centres and highlights the best match (exact username, then prefix,
then substring, case-insensitively). The input offers matching usernames.
Clearing it removes the selection. Hover temporarily highlights another user;
leaving restores the search selection. Colours and dimensions preserve the
selection. Users excluded by the graph's settings cannot be searched.

Minimum and maximum trust-level dropdowns isolate an inclusive slice of the
loaded graph. Both views hide excluded nodes, labels and connecting edges
without rebuilding the simulation; search follows the visible slice. Crossing
the limits adjusts the other dropdown to keep the range valid. These controls
cannot restore users excluded from the snapshot by server settings.

## Data Explorer

When Data Explorer is installed, the once-off
`CreateUserNetworkExplorerQueries` job creates two system-owned queries without
group sharing:

- **User network: graph snapshot** reads the same cached edges and weighted scores
  as the visualisation. The optional username parameter accepts SQL patterns,
  such as `alice` or `ali%`; `%` returns all edges. It reflects the most recent
  graph calculation, not live interactions. Stored source/target directions mix
  like recipients and reply authors and must not be interpreted as a consistent
  direction of endorsement.
- **User network: concentrated new-user interactions** reads recent public likes
  and direct replies. Defaults select accounts created within 90 days with at
  least 10 interactions in the past 30 days, at most three counterparts, and at
  least 80% of interactions with one counterpart. Parameters are adjustable.
  It reports incoming likes/replies, outgoing interactions, reciprocal
  counterparts, and the strongest counterpart's account age and trust level.
  It excludes private messages, restricted categories, hidden/deleted posts,
  self-interactions and staff candidates. It does not apply the graph's minimum
  trust level or weighted edge threshold, which could hide new users.

The second query is a review aid. Concentrated interactions can be legitimate;
it does not establish shared identity, calculate an abuse probability, or take
moderation actions. Reciprocity means interactions in both directions; it need
not be reciprocal likes. Counts cover the selected time window, not lifetime
relationships or complete community isolation. Use the graph and post history
to investigate context. Data Explorer's existing permissions control access.

The installer preserves edits, renamed queries and intentional deletions on
reruns. If Data Explorer is installed later, run this in the Rails console:

```ruby
Jobs.enqueue(:create_user_network_explorer_queries, force: true)
```

This installs missing query definitions without rebuilding the graph. The SQL
sources are in `queries/`; changing those files does not overwrite installed
queries.
