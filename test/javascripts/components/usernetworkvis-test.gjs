import {
  click,
  fillIn,
  find,
  findAll,
  render,
  triggerEvent,
  waitUntil,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import Usernetworkvis from "discourse/plugins/discourse-user-network-vis/discourse/components/usernetworkvis";

module("Integration | Component | Usernetworkvis", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.siteSettings.user_network_vis_default_view = "2d";
    this.siteSettings.user_network_vis_node_radius = 6;
    this.siteSettings.user_network_vis_node_charge_strength = 700;
    this.model = {
      results: {
        user_network_stats: {
          nodes: ["alice", "alicia", "bob", "carol"].map((id, index) => ({
            id,
            group: index,
          })),
          links: [
            { source: "alice", target: "bob", value: 2 },
            { source: "bob", target: "carol", value: 1 },
          ],
        },
      },
    };
  });

  test("typing locally centres a match, highlights its edges, and restores selection after hover", async function (assert) {
    await render(<template><Usernetworkvis @model={{this.model}} /></template>);
    await waitUntil(() => findAll(".nodes circle").length === 4);
    const circles = findAll(".nodes circle");
    const input = ".user-network-vis__search input";
    await fillIn(input, "ALI");
    assert
      .dom(".user-network-vis__search-result")
      .hasText("alice", "prefix matching updates without submitting");
    assert
      .dom(".links line:nth-child(2)")
      .hasStyle({ opacity: "0.1" }, "disconnected edges fade");
    await waitUntil(() => {
      const point = circles[0].getBoundingClientRect();
      const canvas = find(".user-network-vis svg").getBoundingClientRect();
      return (
        Math.abs(point.x + point.width / 2 - canvas.x - canvas.width / 2) < 2
      );
    });
    assert.true(true, "matching node is centred");
    await triggerEvent(circles[3].parentElement, "mouseover");
    assert
      .dom(".links line:first-child")
      .hasStyle({ opacity: "0.1" }, "hover temporarily takes priority");
    await triggerEvent(circles[3].parentElement, "mouseout");
    assert
      .dom(".links line:first-child")
      .hasStyle({ opacity: "1" }, "leaving restores the search selection");
    await click(".user-network-vis__toolbar-row--colours button:first-child");
    assert.strictEqual(
      find(".nodes circle"),
      circles[0],
      "colour changes retain the graph nodes"
    );
    assert
      .dom(".user-network-vis__toolbar-row--colours button:first-child")
      .hasAttribute("aria-pressed", "true", "clusters are selected");
    assert
      .dom(".user-network-vis__legend")
      .doesNotExist("trust legend is hidden for clusters");
    await click(".user-network-vis__toolbar-row--colours button:first-child");
    assert
      .dom(".user-network-vis__toolbar-row--colours button:first-child")
      .hasAttribute(
        "aria-pressed",
        "true",
        "clicking the selected mode keeps it selected"
      );
    await click(".user-network-vis__toolbar-row--colours button:last-child");
    assert
      .dom(".user-network-vis__legend")
      .exists("trust colours restore the legend");
    await fillIn(input, "ALICIA");
    assert
      .dom(".user-network-vis__search-result")
      .hasText("alicia", "exact match takes precedence");
    await fillIn(input, "missing");
    assert
      .dom(".user-network-vis__search-result")
      .hasText(
        "No matching user in this graph",
        "unmatched searches show feedback"
      );
    assert
      .dom(".links line:first-child")
      .hasStyle(
        { opacity: "1" },
        "unmatched search removes the previous highlight"
      );
    await click(".filter-input-clear-btn");
    assert.dom(input).hasValue("", "clear resets search");
  });

  test("trust-level bounds hide nodes and edges locally and keep a valid range", async function (assert) {
    await render(<template><Usernetworkvis @model={{this.model}} /></template>);
    await waitUntil(() => findAll(".nodes circle").length === 4);
    const circle = find(".nodes circle");
    await fillIn(".user-network-vis__minimum-trust-level", "2");
    await triggerEvent(".user-network-vis__minimum-trust-level", "input");
    assert
      .dom(".nodes g:first-child")
      .isNotVisible("lower trust levels are hidden");
    assert
      .dom(".links line:first-child")
      .isNotVisible("edges to hidden users are hidden");
    assert
      .dom(".links line:nth-child(2)")
      .isVisible("edges within the slice remain");
    assert.strictEqual(
      find(".nodes circle"),
      circle,
      "filtering retains simulation nodes"
    );
    await fillIn(".user-network-vis__search input", "alice");
    assert
      .dom(".user-network-vis__search-result")
      .hasText(
        "No matching user in this graph",
        "search excludes hidden nodes"
      );
    await fillIn(".user-network-vis__maximum-trust-level", "0");
    await triggerEvent(".user-network-vis__maximum-trust-level", "input");
    assert
      .dom(".user-network-vis__minimum-trust-level")
      .hasValue("0", "crossing maximum adjusts minimum");
    assert.dom(".nodes g:first-child").isVisible("the selected slice is shown");
    await fillIn(".user-network-vis__minimum-trust-level", "4");
    await triggerEvent(".user-network-vis__minimum-trust-level", "input");
    assert
      .dom(".user-network-vis__maximum-trust-level")
      .hasValue("4", "crossing minimum adjusts maximum");
    assert.dom(".user-network-vis__empty").exists("empty slices have feedback");
  });
});
