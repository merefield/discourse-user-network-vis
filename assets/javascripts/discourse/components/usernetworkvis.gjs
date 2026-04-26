import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat } from "@ember/helper";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { service } from "@ember/service";
import { bind } from "discourse/lib/decorators";
import loadScript from "discourse/lib/load-script";
import DiscourseURL from "discourse/lib/url";
import { i18n } from "discourse-i18n";

export default class Usernetworkvis extends Component {
  @service siteSettings;

  @tracked viewMode = this.siteSettings.user_network_vis_default_view;

  graphElement = null;
  graph3D = null;
  graph3DLabelsElement = null;
  graph3DLabelFrameRequestId = null;
  resizeFrameRequestId = null;
  resizeObserver = null;
  lastGraphWidth = null;
  lastGraphHeight = null;
  graphFitPadding = 96;
  graph3DFitPadding = 4;

  get network() {
    return this.args.model?.results?.user_network_stats;
  }

  get hasItems() {
    return Boolean(this.network?.nodes?.length);
  }

  get is2D() {
    return this.viewMode === "2d";
  }

  get is3D() {
    return this.viewMode === "3d";
  }

  async ensureD3() {
    await loadScript("/plugins/discourse-user-network-vis/d3/d3.min.js");

    return window.d3;
  }

  async ensureForceGraph3D() {
    await loadScript(
      "/plugins/discourse-user-network-vis/3d-force-graph/3d-force-graph.min.js"
    );

    return window.ForceGraph3D;
  }

  graphData() {
    return {
      nodes: this.network.nodes.map((node) => ({ ...node })),
      links: this.network.links.map((link) => ({
        ...link,
        source: link.source?.id ?? link.source,
        target: link.target?.id ?? link.target,
      })),
    };
  }

  @bind
  async setup(element) {
    this.graphElement = element;
    this.setupResizeObserver();
    window.addEventListener("resize", this.scheduleRenderForResize);
    await this.renderGraph();
  }

  @bind
  teardown() {
    window.removeEventListener("resize", this.scheduleRenderForResize);

    this.resizeObserver?.disconnect();
    this.resizeObserver = null;

    if (this.resizeFrameRequestId) {
      cancelAnimationFrame(this.resizeFrameRequestId);
      this.resizeFrameRequestId = null;
    }

    this.resetGraph();
    this.graphElement = null;
  }

  @bind
  async show2D() {
    this.viewMode = "2d";
    await this.renderGraph();
  }

  @bind
  async show3D() {
    this.viewMode = "3d";
    await this.renderGraph();
  }

  async renderGraph() {
    if (!this.graphElement || !this.hasItems) {
      return;
    }

    if (this.is3D) {
      await this.render3DGraph();
    } else {
      await this.render2DGraph();
    }
  }

  resetGraph() {
    this.cancel3DLabelUpdates();

    if (this.graph3D) {
      this.graph3D._destructor?.();
      this.graph3D = null;
    }

    this.graphElement.replaceChildren();
  }

  setupResizeObserver() {
    this.resizeObserver?.disconnect();

    this.resizeObserver = new ResizeObserver(this.scheduleRenderForResize);

    this.resizeObserver.observe(this.graphElement);
  }

  @bind
  scheduleRenderForResize() {
    if (this.resizeFrameRequestId) {
      cancelAnimationFrame(this.resizeFrameRequestId);
    }

    this.resizeFrameRequestId = requestAnimationFrame(async () => {
      this.resizeFrameRequestId = null;

      if (!this.graphElement) {
        return;
      }

      const { width, height } = this.graphDimensions();

      if (
        Math.abs(width - this.lastGraphWidth) > 1 ||
        Math.abs(height - this.lastGraphHeight) > 1
      ) {
        await this.renderGraph();
      }
    });
  }

  graphDimensions() {
    const rect = this.graphElement.getBoundingClientRect();
    const width = Math.max(320, Math.floor(rect.width));
    const height = Math.max(320, Math.floor(window.innerHeight - rect.top));

    return {
      width,
      height,
    };
  }

  graphBounds(nodes, dimensions = ["x", "y"]) {
    const bounds = Object.fromEntries(
      dimensions.flatMap((dimension) => [
        [`min${dimension}`, Infinity],
        [`max${dimension}`, -Infinity],
      ])
    );

    nodes.forEach((node) => {
      dimensions.forEach((dimension) => {
        bounds[`min${dimension}`] = Math.min(
          bounds[`min${dimension}`],
          node[dimension]
        );
        bounds[`max${dimension}`] = Math.max(
          bounds[`max${dimension}`],
          node[dimension]
        );
      });
    });

    return dimensions.some(
      (dimension) => !Number.isFinite(bounds[`min${dimension}`])
    )
      ? null
      : bounds;
  }

  fit2DGraph(d3, svg, zoomBehavior, nodes, width, height) {
    const bounds = this.graphBounds(nodes);

    if (!bounds) {
      return;
    }

    const graphWidth = Math.max(1, bounds.maxx - bounds.minx);
    const graphHeight = Math.max(1, bounds.maxy - bounds.miny);
    const paddedWidth = Math.max(1, width - this.graphFitPadding * 2);
    const paddedHeight = Math.max(1, height - this.graphFitPadding * 2);
    const scale = Math.max(
      0.1,
      Math.min(10, paddedWidth / graphWidth, paddedHeight / graphHeight)
    );
    const centerX = (bounds.minx + bounds.maxx) / 2;
    const centerY = (bounds.miny + bounds.maxy) / 2;
    const transform = d3.zoomIdentity
      .translate(width / 2 - centerX * scale, height / 2 - centerY * scale)
      .scale(scale);

    svg.call(zoomBehavior.transform, transform);
  }

  cancel3DLabelUpdates() {
    if (this.graph3DLabelFrameRequestId) {
      cancelAnimationFrame(this.graph3DLabelFrameRequestId);
      this.graph3DLabelFrameRequestId = null;
    }

    this.graph3DLabelsElement = null;
  }

  async render2DGraph() {
    const d3 = await this.ensureD3();

    if (!d3) {
      return;
    }

    this.resetGraph();

    const { width, height } = this.graphDimensions();
    this.lastGraphWidth = width;
    this.lastGraphHeight = height;
    this.graphElement.style.height = `${height}px`;
    const color = d3.scaleOrdinal(
      this.siteSettings.user_network_vis_colors.split("|")
    );
    const graphData = this.graphData();

    const svg = d3
      .select(this.graphElement)
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
      .data(graphData.links)
      .enter()
      .append("line")
      .attr("stroke-width", (data) => Math.cbrt(Math.round(data.value) + 1));

    const node = graph
      .append("g")
      .attr("class", "nodes")
      .selectAll("g")
      .data(graphData.nodes)
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

    const updatePositions = () => {
      link
        .attr("x1", (data) => data.source.x)
        .attr("y1", (data) => data.source.y)
        .attr("x2", (data) => data.target.x)
        .attr("y2", (data) => data.target.y);

      node.attr("transform", (data) => `translate(${data.x},${data.y})`);
    };

    simulation.nodes(graphData.nodes).on("tick", updatePositions);

    simulation.force("link").links(graphData.links);

    simulation
      .force("link")
      .links()
      .forEach((data) => {
        linkedByIndex[`${data.source.index},${data.target.index}`] = 1;
      });

    simulation.tick(300);
    updatePositions();
    this.fit2DGraph(d3, svg, zoomBehavior, graphData.nodes, width, height);

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

  async render3DGraph() {
    const ForceGraph3D = await this.ensureForceGraph3D();

    if (!ForceGraph3D) {
      return;
    }

    this.resetGraph();

    const { width, height } = this.graphDimensions();
    this.lastGraphWidth = width;
    this.lastGraphHeight = height;
    this.graphElement.style.height = `${height}px`;
    const colors = this.siteSettings.user_network_vis_colors.split("|");
    const graphData = this.graphData();
    const nodeId = (node) => node?.id ?? node;
    let hoveredNode = null;
    let hasFitGraph = false;
    const isAttachedToHoveredNode = (link) => {
      return (
        !hoveredNode ||
        nodeId(link.source) === hoveredNode.id ||
        nodeId(link.target) === hoveredNode.id
      );
    };
    const linkColor = (link) =>
      isAttachedToHoveredNode(link)
        ? "rgba(170, 170, 170, 1)"
        : "rgba(170, 170, 170, 0.08)";

    const graph = new ForceGraph3D(this.graphElement, {
      rendererConfig: { antialias: true, alpha: true },
    })
      .width(width)
      .height(height)
      .backgroundColor("rgba(0,0,0,0)")
      .showNavInfo(false)
      .nodeLabel("id")
      .nodeVal(this.siteSettings.user_network_vis_node_radius)
      .nodeColor((node) => colors[((node.group ?? 0) + 1) % colors.length])
      .linkWidth((link) => Math.cbrt(Math.round(link.value) + 1))
      .linkColor(linkColor)
      .linkOpacity(0.2)
      .onNodeHover((node) => {
        hoveredNode = node;
        graph.linkColor(linkColor);
      })
      .onEngineStop(() => {
        if (!hasFitGraph) {
          hasFitGraph = true;
          graph.zoomToFit(400, this.graph3DFitPadding);
        }
      })
      .onNodeClick((node) => {
        if (node.id) {
          DiscourseURL.routeTo(`/u/${node.id}/summary`);
        }
      })
      .graphData(graphData);

    graph
      .d3Force("charge")
      ?.strength(-this.siteSettings.user_network_vis_node_charge_strength);

    this.graph3D = graph;
    this.create3DLabels(graph, graphData);
  }

  create3DLabels(graph, graphData) {
    const labelsElement = document.createElement("div");
    labelsElement.className = "user-network-vis__3d-labels";

    const labels = graphData.nodes.map((node) => {
      const label = document.createElement("span");
      label.className = "user-network-vis__3d-label";
      label.textContent = node.id;
      labelsElement.appendChild(label);

      return { label, node };
    });

    this.graphElement.appendChild(labelsElement);
    this.graph3DLabelsElement = labelsElement;

    const updateLabels = () => {
      if (!this.graph3DLabelsElement) {
        return;
      }

      labels.forEach(({ label, node }) => {
        if (
          [node.x, node.y, node.z].some((position) => position === undefined)
        ) {
          label.hidden = true;
          return;
        }

        const { x, y } = graph.graph2ScreenCoords(node.x, node.y, node.z);
        label.hidden = false;
        label.style.transform = `translate(${x + 10}px, ${y}px) translateY(-50%)`;
      });

      this.graph3DLabelFrameRequestId = requestAnimationFrame(updateLabels);
    };

    updateLabels();
  }

  <template>
    {{#if this.hasItems}}
      <div class="user-network-vis-container">
        <div class="user-network-vis__toolbar">
          <button
            type="button"
            class={{concat
              "user-network-vis__toggle"
              (if this.is2D " user-network-vis__toggle--active")
            }}
            aria-pressed={{this.is2D}}
            {{on "click" this.show2D}}
          >
            {{i18n "user_network_vis.view_2d"}}
          </button>

          <button
            type="button"
            class={{concat
              "user-network-vis__toggle"
              (if this.is3D " user-network-vis__toggle--active")
            }}
            aria-pressed={{this.is3D}}
            {{on "click" this.show3D}}
          >
            {{i18n "user_network_vis.view_3d"}}
          </button>
        </div>

        <div
          class="user-network-vis"
          {{didInsert this.setup}}
          {{willDestroy this.teardown}}
        ></div>
      </div>
    {{/if}}
  </template>
}
