# Documentation screenshots

These PNGs are unedited browser screenshots of the real `/usernetworkvis` page
in a local Discourse **test** environment, using the Foundation theme in light
mode at 1440 x 1200. They include the actual header, sidebar and plugin controls.
No production data or mocked frontend is used.

The browser spec creates 25 fictional users spanning trust levels 0-4 and
generates direct replies within five groups, with links between the groups.
It runs the real `Jobs::UserNetworkStatsCalc` calculation before opening the
page as a signed-in member. The test database cleanup removes the fixtures.
Force-directed layouts can vary between captures.

The system suite also exercises both renderers at a 390 x 844 mobile viewport.
Desktop and mobile tests inspect pixels from screenshots of the renderer itself
(excluding the separate 3D label overlay), so an empty WebGL canvas fails even
when username labels are present. The committed gallery remains desktop-only.

| File                   | View                                             |
| ---------------------- | ------------------------------------------------ |
| `network-3d.png`       | 3D, trust-level colours and legend.              |
| `network-2d.png`       | 2D, trust-level colours and legend.              |
| `network-clusters.png` | 2D, relationship-cluster colours.                |
| `network-search.png`   | 2D, cluster colours, username search for `alex`. |

## Reproduce

Use a working Discourse development checkout with this plugin installed under
`plugins/discourse-user-network-vis`, the test database prepared and the browser
test dependencies installed. From the Discourse root:

```sh
TAKE_SCREENSHOTS=1 LOAD_PLUGINS=1 \
  SCREENSHOTS_SUBSET=user-network \
  SCREENSHOTS_THEMES=foundation \
  SCREENSHOTS_MODES=light \
  SCREENSHOTS_DEVICES=desktop \
  SCREENSHOTS_DIR=/tmp/user-network-screenshots \
  bin/rspec spec/system/theme_screenshots_spec.rb
```

The capture scenario is
[`explore_user_network_spec.rb`](../../spec/system/explore_user_network_spec.rb).
Waits check that the layout has settled and the 3D nodes are in the canvas before
capturing. Review both the image files and the test summary: the matrix wrapper
can return success even if an inner example fails.

Open `/tmp/user-network-screenshots/compare.html` to review the results. Copy
`raw/desktop-foundation-light-user-network-{3d,2d,clusters,search}.png` into this
folder as `network-{3d,2d,clusters,search}.png`. Preserve the original browser
images, and confirm that labels, the canvas and controls are visible.

To run just the workflow without capturing:

```sh
LOAD_PLUGINS=1 bin/rspec plugins/discourse-user-network-vis/spec/system/explore_user_network_spec.rb
```

## Publishing the intro topic

The repository README uses relative image links. `intro-topic.md` uses raw GitHub
URLs on `main` so its images work when pasted into a Discourse topic. Merge the
assets to `main` before publishing the topic, or upload the PNGs to the target
forum and replace those URLs with the resulting upload links.
