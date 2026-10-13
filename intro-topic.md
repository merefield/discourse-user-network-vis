# Community network visualisation

|                         |                                                                                                 |
| ----------------------- | ----------------------------------------------------------------------------------------------- |
| **Summary**             | Explore relationships between forum members in an interactive 2D or 3D network.                 |
| **Repository**          | [merefield/discourse-user-network-vis](https://github.com/merefield/discourse-user-network-vis) |
| **Installation**        | Follow the [plugin installation guide](https://meta.discourse.org/t/install-a-plugin/19157).    |
| **Support development** | [Sponsor on GitHub](https://github.com/sponsors/merefield)                                      |

![3D user network with username labels and trust-level colours](https://raw.githubusercontent.com/merefield/discourse-user-network-vis/main/assets/screenshots/network-3d.png)

## Features

See how people interact across your community. Each node represents a user;
links represent likes and direct replies, with thicker links for higher
interaction scores.

- **2D and 3D views:** switch at any time. 3D is the default and has username
  labels that always face you.
- **Full-size canvas:** uses the available width and height below the header,
  adapting when the sidebar is opened.
- **Find a username:** type to centre and highlight a matching user, with no
  extra server requests or search button.
- **Trust-level filters:** choose a minimum and maximum to isolate a slice of
  the loaded network.
- **Colour modes:** choose trust levels with a legend, or relationship clusters.
  Switching colours keeps the network in place.
- **Data Explorer integration:** optional queries for the underlying graph and
  concentrated interactions involving new users.

## Using the network

Sign in and choose **User Network** in the desktop sidebar, or navigate directly
to `/usernetworkvis`. The sidebar link can be disabled in settings. On mobile,
use the direct URL.

Hover over a node to emphasise that user's connections. Click it to open their
profile summary. Drag nodes, zoom with the mouse wheel, and rotate the 3D view
to explore from different angles. 3D requires WebGL support.

![2D network with trust-level colours](https://raw.githubusercontent.com/merefield/discourse-user-network-vis/main/assets/screenshots/network-2d.png)

Search matches usernames case-insensitively, preferring an exact match, then a
prefix, then a substring. Clearing the search removes the selection. Hovering
another node temporarily changes the highlight; leaving restores your search
selection. Search operates only on users visible within the selected trust range.

![Username search highlighting alex and their connections](https://raw.githubusercontent.com/merefield/discourse-user-network-vis/main/assets/screenshots/network-search.png)

## Colours and relationship clusters

**Trust level** uses five individually configurable colours, consistently in
both views. **Clusters** uses weighted relationships and a Louvain-style method
to group strongly connected users.

![Network coloured by relationship clusters](https://raw.githubusercontent.com/merefield/discourse-user-network-vis/main/assets/screenshots/network-clusters.png)

Clusters reuse the five trust-level colours. There can be more than five
communities: smaller ones share colours with larger groups. Cluster colours do
not indicate trust levels, and neither clustering nor position proves that
accounts belong to the same person.

All screenshots show fictional users and generated interactions rendered in a
real Discourse test environment.

## Configuration

Search the admin settings for `user_network_vis`.

| Setting                                                                          | Default               | Purpose                                        |
| -------------------------------------------------------------------------------- | --------------------- | ---------------------------------------------- |
| `user_network_vis_enabled`                                                       | `true`                | Enable the plugin.                             |
| `user_network_vis_add_menu_item`                                                 | `true`                | Add the desktop sidebar entry.                 |
| `user_network_vis_default_view`                                                  | `3d`                  | Choose the initial 2D or 3D view.              |
| `user_network_vis_node_radius`                                                   | `6`                   | Adjust node sizing.                            |
| `user_network_vis_node_charge_strength`                                          | `700`                 | Adjust node repulsion.                         |
| `user_network_vis_trust_level_0_color` to `user_network_vis_trust_level_4_color` | Five distinct colours | Set each trust level's colour.                 |
| `user_network_vis_minimum_trust_level`                                           | `0`                   | Minimum trust level included in the snapshot.  |
| `user_network_vis_maximum_last_seen_years`                                       | `10`                  | Exclude users not seen within this many years. |
| `user_network_vis_reply_multiplier`                                              | `2`                   | Weight direct replies relative to likes.       |
| `user_network_vis_link_score_threshold`                                          | `0`                   | Minimum interaction score for an edge.         |

The last four settings require a new graph calculation. The on-page minimum and
maximum controls only filter the loaded snapshot; they cannot bring back users
excluded by server settings.

## Refreshing the data

The graph is calculated **hourly**. To refresh sooner, an administrator can go
to `/sidekiq/scheduler` and trigger **UserNetworkStatsCalc**. Reload the page once
the job finishes. This is also useful immediately after installation or a
snapshot-setting change.

Large communities can produce crowded graphs and expensive calculations.
Monitor the job on your own installation rather than relying on benchmarks
from a different site.

## Exploring the underlying data

Signed-in members can view the cached data at `/usernetworkvis.json`.

With Data Explorer installed, a once-off job adds two system-owned queries
without group sharing:

- **User network: graph snapshot** lists the cached edges and weighted scores
  used by the visualisation, with an optional username filter.
- **User network: concentrated new-user interactions** finds recent accounts
  whose interactions are concentrated among a small number of counterparts.
  Its adjustable defaults are accounts created within 90 days, at least 10
  interactions in the last 30 days, at most three counterparts, and at least
  80% of interactions with one counterpart.

The review query reports incoming and outgoing interactions, reciprocity and
the strongest counterpart. It excludes private messages, restricted categories,
whispers and other non-regular posts, hidden/deleted posts, self-interactions and staff candidates. Data Explorer's
existing permissions control access.

**This is an investigation aid, not a sock-puppet detector.** Concentrated
interactions can be entirely legitimate. Review post history and context; the
plugin does not establish shared identity or take moderation actions.

If Data Explorer is installed later, an administrator can run this in the Rails
console:

```ruby
Jobs.enqueue(:create_user_network_explorer_queries, force: true)
```

Existing query edits, renames and intentional deletions are preserved. See the
[README](https://github.com/merefield/discourse-user-network-vis#data-explorer)
for query semantics and maintenance details.

## Privacy considerations

The graph is available to **signed-in members**, not just staff. It exposes
usernames, trust levels and aggregate interaction scores. Making all node
colours identical does not remove trust levels from the JSON.

Private messages are excluded, but the graph's reply calculation currently does
not exclude restricted categories or invisible topics in the same way as its
likes calculation. It is a shared snapshot, not filtered for each viewer's
permissions. Review this limitation before enabling it on a site with sensitive
areas. The Data Explorer review query has stricter exclusions.

## Credits and related projects

Built with [D3](https://d3js.org/),
[3D Force Graph](https://github.com/vasturiano/3d-force-graph) and
[Three.js](https://threejs.org/).

You may also like:

- [Word cloud plugin](https://meta.discourse.org/t/word-cloud-plugin/210169)
- [Discourse tag cloud](https://meta.discourse.org/t/discourse-tag-cloud/218014)

Translations, contributions and feedback are welcome.
[GitHub sponsorship](https://github.com/sponsors/merefield) helps fund ongoing
maintenance and development.
