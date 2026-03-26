import Component from "@glimmer/component";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { bind } from "discourse/lib/decorators";
import loadScript from "discourse/lib/load-script";
import DiscourseURL from "discourse/lib/url";

export default class Usernetworkvis extends Component {
  @service siteSettings;

  get network() {
    return this.args.model?.results?.user_network_stats;
  }

  get hasItems() {
    return Boolean(this.network?.nodes?.length);
  }

  async ensureD3() {
    await loadScript("/plugins/discourse-user-network-vis/d3/d3.min.js");

    return window.d3;
  }

  @bind
  async setup(element) {
    if (!this.hasItems) {
      return;
    }

    const d3 = await this.ensureD3();

    if (!d3) {
      return;
    }

    element.replaceChildren();

    const width = 1120;
    const height = this.siteSettings.user_network_vis_canvas_height;
    const color = d3.scaleOrdinal(
      this.siteSettings.user_network_vis_colors.split("|")
    );

    const svg = d3
      .select(element)
      .append("svg")
      .attr("width", width)
      .attr("height", height);

    const graph = svg.append("g");

    const zoomBehavior = d3
      .zoom()
      .scaleExtent([0.1, 10])
      .on("zoom", (event) => {
        graph.attr("transform", event.transform);
      });

    svg.call(zoomBehavior);

    const simulation = d3
      .forceSimulation()
      .force(
        "link",
        d3.forceLink().id((node) => node.id)
      )
      .force(
        "charge",
        d3
          .forceManyBody()
          .strength(-this.siteSettings.user_network_vis_node_charge_strength)
      )
      .force("center", d3.forceCenter(width / 2, height / 2));

    const link = graph
      .append("g")
      .attr("class", "links")
      .selectAll("line")
      .data(this.network.links)
      .enter()
      .append("line")
      .attr("stroke-width", (data) => Math.cbrt(Math.round(data.value) + 1));

    const node = graph
      .append("g")
      .attr("class", "nodes")
      .selectAll("g")
      .data(this.network.nodes)
      .enter()
      .append("g");

    const linkedByIndex = {};

    const isConnected = (firstNode, secondNode) => {
      return (
        linkedByIndex[`${firstNode.index},${secondNode.index}`] ||
        linkedByIndex[`${secondNode.index},${firstNode.index}`] ||
        firstNode.index === secondNode.index
      );
    };

    const fade = (opacity) => {
      return (_event, hoveredNode) => {
        node.style("opacity", (otherNode) =>
          isConnected(hoveredNode, otherNode) ? 1 : opacity
        );

        link.style("opacity", (otherLink) => {
          return otherLink.source.id === hoveredNode.id ||
            otherLink.target.id === hoveredNode.id
            ? 1
            : opacity;
        });
      };
    };

    node.on("mouseover", fade(0.1)).on("mouseout", fade(1));

    node
      .append("circle")
      .attr("r", this.siteSettings.user_network_vis_node_radius)
      .attr("fill", (data) => color(data.group + 1))
      .call(
        d3
          .drag()
          .on("start", dragstarted)
          .on("drag", dragged)
          .on("end", dragended)
      )
      .on("click", (_event, data) => {
        if (data.id) {
          DiscourseURL.routeTo(`/u/${data.id}/summary`);
        }
      });

    node
      .append("text")
      .text((data) => data.id)
      .attr("x", this.siteSettings.user_network_vis_node_radius + 1)
      .attr("y", this.siteSettings.user_network_vis_node_radius / 2 + 1);

    node.append("title").text((data) => data.id);

    simulation.nodes(this.network.nodes).on("tick", () => {
      link
        .attr("x1", (data) => data.source.x)
        .attr("y1", (data) => data.source.y)
        .attr("x2", (data) => data.target.x)
        .attr("y2", (data) => data.target.y);

      node.attr("transform", (data) => `translate(${data.x},${data.y})`);
    });

    simulation.force("link").links(this.network.links);

    simulation
      .force("link")
      .links()
      .forEach((data) => {
        linkedByIndex[`${data.source.index},${data.target.index}`] = 1;
      });

    function dragstarted(event, data) {
      if (!event.active) {
        simulation.alphaTarget(0.3).restart();
      }
      data.fx = data.x;
      data.fy = data.y;
    }

    function dragged(event, data) {
      data.fx = event.x;
      data.fy = event.y;
    }

    function dragended(event, data) {
      if (!event.active) {
        simulation.alphaTarget(0);
      }
      data.fx = null;
      data.fy = null;
    }
  }

  <template>
    {{#if this.hasItems}}
      <div class="user-network-vis" {{didInsert this.setup}}></div>
    {{/if}}
  </template>
}
