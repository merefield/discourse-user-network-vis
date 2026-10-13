import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { bind } from "discourse/lib/decorators";
import loadScript from "discourse/lib/load-script";
import DiscourseURL from "discourse/lib/url";
import DFilterInput from "discourse/ui-kit/d-filter-input";
import DNativeSelect from "discourse/ui-kit/d-native-select";
import dUniqueId from "discourse/ui-kit/helpers/d-unique-id";
import { i18n } from "discourse-i18n";

export default class Usernetworkvis extends Component {
  @service a11y;
  @service siteSettings;

  @tracked viewMode = this.siteSettings.user_network_vis_default_view;
  @tracked clusterByRelationships = false;
  @tracked searchTerm = "";
  @tracked selectedUsername = null;
  @tracked minimumTrustLevel = 0;
  @tracked maximumTrustLevel = 4;

  graphElement = null;
  currentGraphData = null;
  graph3D = null;
  graph3DLabelsElement = null;
  graph3DLabelFrameRequestId = null;
  resizeFrameRequestId = null;
  resizeObserver = null;
  lastGraphWidth = null;
  lastGraphHeight = null;
  graphFitPadding = 96;
  graph3DFitPadding = 4;
  searchListId = `network-users-${dUniqueId()}`;

  #focusNode = null;
  #highlightNode = null;
  #simulation = null;
  #updateVisibility = null;

  get visibleNodes() {
    return (this.network?.nodes ?? []).filter((node) =>
      this.#nodeInRange(node)
    );
  }

  get searchMatches() {
    const term = this.searchTerm.trim().toLowerCase();
    if (!term) {
      return [];
    }
    return this.visibleNodes
      .filter((node) => node.id.toLowerCase().includes(term))
      .sort((first, second) => {
        const rank = (node) => {
          const username = node.id.toLowerCase();
          return username === term ? 0 : username.startsWith(term) ? 1 : 2;
        };
        return rank(first) - rank(second) || first.id.localeCompare(second.id);
      });
  }

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

  get trustLevelLegendItems() {
    return [0, 1, 2, 3, 4].map((trustLevel) => {
      return {
        value: trustLevel,
        label: i18n("user_network_vis.trust_level", { trustLevel }),
        style: trustHTML(`background-color: ${this.nodeColor(trustLevel)}`),
      };
    });
  }

  @bind
  clearSearch() {
    this.searchTerm = "";
    this.selectedUsername = null;
    this.#highlightNode?.(null);
  }

  @bind
  searchUsername(event) {
    this.searchTerm = event.target.value;
    this.selectedUsername = this.searchMatches[0]?.id ?? null;
    this.#restoreSelection();
    if (this.searchTerm.trim()) {
      this.a11y.announce(
        this.selectedUsername
          ? i18n("user_network_vis.focused_user", {
              username: this.selectedUsername,
            })
          : i18n("user_network_vis.no_matching_user")
      );
    }
  }

  @bind
  changeMinimumTrustLevel(value) {
    this.minimumTrustLevel = Number(value);
    this.maximumTrustLevel = Math.max(
      this.minimumTrustLevel,
      this.maximumTrustLevel
    );
    this.#applyTrustLevelFilter();
  }

  @bind
  changeMaximumTrustLevel(value) {
    this.maximumTrustLevel = Number(value);
    this.minimumTrustLevel = Math.min(
      this.minimumTrustLevel,
      this.maximumTrustLevel
    );
    this.#applyTrustLevelFilter();
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
    const graphData = {
      nodes: this.network.nodes.map((node) => ({ ...node })),
      links: this.network.links.map((link) => ({
        ...link,
        source: link.source?.id ?? link.source,
        target: link.target?.id ?? link.target,
      })),
    };

    if (this.clusterByRelationships) {
      this.applyRelationshipClusters(graphData);
    }

    return graphData;
  }

  nodeColor(colorIndex) {
    const normalizedColorIndex = Math.max(0, Math.min(4, colorIndex ?? 0));

    return this.siteSettings[
      `user_network_vis_trust_level_${normalizedColorIndex}_color`
    ];
  }

  nodeColorIndex(node) {
    return this.clusterByRelationships ? (node.cluster ?? 0) : node.group;
  }

  applyRelationshipClusters(graphData) {
    const communities = this.detectLouvainCommunities(graphData);
    const communityWeights = new Map();
    const topCommunities = new Map();

    graphData.nodes.forEach((node) => {
      const community = communities.get(node.id) ?? node.id;
      communityWeights.set(
        community,
        (communityWeights.get(community) ?? 0) + 1
      );
    });

    [...communityWeights.entries()]
      .sort((first, second) => second[1] - first[1])
      .slice(0, 5)
      .forEach(([community], index) => topCommunities.set(community, index));

    graphData.nodes.forEach((node) => {
      const community = communities.get(node.id) ?? node.id;
      node.cluster =
        topCommunities.get(community) ??
        this.closestClusterIndex(
          node.id,
          graphData.links,
          communities,
          topCommunities
        );
    });
  }

  closestClusterIndex(nodeId, links, communities, topCommunities) {
    const weightsByCluster = new Map();

    links.forEach((link) => {
      const source = link.source?.id ?? link.source;
      const target = link.target?.id ?? link.target;

      if (source !== nodeId && target !== nodeId) {
        return;
      }

      const neighborId = source === nodeId ? target : source;
      const neighborCommunity = communities.get(neighborId) ?? neighborId;
      const clusterIndex = topCommunities.get(neighborCommunity);

      if (clusterIndex === undefined) {
        return;
      }

      weightsByCluster.set(
        clusterIndex,
        (weightsByCluster.get(clusterIndex) ?? 0) + Number(link.value || 1)
      );
    });

    return (
      [...weightsByCluster.entries()].sort(
        (first, second) => second[1] - first[1]
      )[0]?.[0] ?? 0
    );
  }

  detectLouvainCommunities(graphData) {
    const adjacency = new Map();
    const degree = new Map();
    const communities = new Map();
    const communityTotals = new Map();
    let totalWeight = 0;

    graphData.nodes.forEach((node) => {
      adjacency.set(node.id, new Map());
      degree.set(node.id, 0);
      communities.set(node.id, node.id);
      communityTotals.set(node.id, 0);
    });

    graphData.links.forEach((link) => {
      const source = link.source?.id ?? link.source;
      const target = link.target?.id ?? link.target;
      const weight = Number(link.value || 1);

      if (
        !adjacency.has(source) ||
        !adjacency.has(target) ||
        source === target
      ) {
        return;
      }

      adjacency
        .get(source)
        .set(target, (adjacency.get(source).get(target) ?? 0) + weight);
      adjacency
        .get(target)
        .set(source, (adjacency.get(target).get(source) ?? 0) + weight);
      degree.set(source, degree.get(source) + weight);
      degree.set(target, degree.get(target) + weight);
      totalWeight += weight;
    });

    degree.forEach((nodeDegree, nodeId) => {
      communityTotals.set(nodeId, nodeDegree);
    });

    if (totalWeight === 0) {
      return communities;
    }

    for (let pass = 0; pass < 20; pass++) {
      let moved = false;

      for (const node of graphData.nodes) {
        const nodeId = node.id;
        const nodeDegree = degree.get(nodeId);
        const currentCommunity = communities.get(nodeId);
        const neighborCommunityWeights = new Map();

        adjacency.get(nodeId).forEach((weight, neighborId) => {
          const community = communities.get(neighborId);
          neighborCommunityWeights.set(
            community,
            (neighborCommunityWeights.get(community) ?? 0) + weight
          );
        });

        communityTotals.set(
          currentCommunity,
          communityTotals.get(currentCommunity) - nodeDegree
        );

        let bestCommunity = currentCommunity;
        let bestGain = 0;

        for (const [
          community,
          weightToCommunity,
        ] of neighborCommunityWeights.entries()) {
          const gain =
            weightToCommunity -
            (nodeDegree * (communityTotals.get(community) ?? 0)) /
              (2 * totalWeight);

          if (gain > bestGain) {
            bestGain = gain;
            bestCommunity = community;
          }
        }

        communityTotals.set(
          bestCommunity,
          (communityTotals.get(bestCommunity) ?? 0) + nodeDegree
        );

        if (bestCommunity !== currentCommunity) {
          communities.set(nodeId, bestCommunity);
          moved = true;
        }
      }

      if (!moved) {
        break;
      }
    }

    return communities;
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

  @bind
  async setRelationshipClusters(enabled) {
    if (this.clusterByRelationships === enabled) {
      return;
    }
    this.clusterByRelationships = enabled;

    if (!this.currentGraphData) {
      await this.renderGraph();
      return;
    }

    if (this.clusterByRelationships) {
      this.applyRelationshipClusters(this.currentGraphData);
    }

    this.refreshNodeColors();
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
    this.#simulation?.stop();
    this.#simulation = null;
    this.#focusNode = null;
    this.#highlightNode = null;
    this.#updateVisibility = null;

    if (this.graph3D) {
      this.graph3D._destructor?.();
      this.graph3D = null;
    }

    this.currentGraphData = null;
    this.graphElement.replaceChildren();
  }

  refreshNodeColors() {
    if (this.is3D && this.graph3D) {
      this.graph3D.nodeColor((node) =>
        this.nodeColor(this.nodeColorIndex(node))
      );
      return;
    }

    window.d3
      ?.select(this.graphElement)
      .selectAll(".nodes circle")
      .attr("fill", (data) => this.nodeColor(this.nodeColorIndex(data)));
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
    const graphData = this.graphData();
    this.currentGraphData = graphData;

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

    this.#highlightNode = (hoveredNode) => {
      node.style("opacity", (otherNode) =>
        !hoveredNode || isConnected(hoveredNode, otherNode) ? 1 : 0.1
      );

      link.style("opacity", (otherLink) => {
        return !hoveredNode ||
          otherLink.source.id === hoveredNode.id ||
          otherLink.target.id === hoveredNode.id
          ? 1
          : 0.1;
      });
    };

    node
      .on("mouseover", (_event, hoveredNode) =>
        this.#highlightNode(hoveredNode)
      )
      .on("mouseout", () => this.#highlightNode(this.#selectedNode()));

    node
      .append("circle")
      .attr("r", this.siteSettings.user_network_vis_node_radius)
      .attr("fill", (data) => this.nodeColor(this.nodeColorIndex(data)))
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
    this.#simulation = simulation;
    updatePositions();
    this.#focusNode = (selectedNode) => {
      const scale = d3.zoomTransform(svg.node()).k;
      svg
        .interrupt()
        .transition()
        .duration(200)
        .call(
          zoomBehavior.transform,
          d3.zoomIdentity
            .translate(
              width / 2 - selectedNode.x * scale,
              height / 2 - selectedNode.y * scale
            )
            .scale(scale)
        );
    };
    this.#updateVisibility = () => {
      const visibleIds = new Set(this.visibleNodes.map((item) => item.id));
      node.style("display", (item) =>
        visibleIds.has(item.id) ? null : "none"
      );
      link.style("display", (item) =>
        visibleIds.has(item.source.id) && visibleIds.has(item.target.id)
          ? null
          : "none"
      );
      this.fit2DGraph(
        d3,
        svg,
        zoomBehavior,
        graphData.nodes.filter((item) => visibleIds.has(item.id)),
        width,
        height
      );
    };
    this.#updateVisibility();
    this.#restoreSelection();

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
    const graphData = this.graphData();
    this.currentGraphData = graphData;
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
      .nodeColor((node) => this.nodeColor(this.nodeColorIndex(node)))
      .linkWidth((link) => Math.cbrt(Math.round(link.value) + 1))
      .linkColor(linkColor)
      .linkOpacity(0.2)
      .onNodeHover((node) => {
        this.#highlightNode?.(node ?? this.#selectedNode());
      })
      .onEngineStop(() => {
        if (!hasFitGraph) {
          hasFitGraph = true;
          if (this.selectedUsername) {
            this.#restoreSelection();
          } else {
            this.#updateVisibility?.();
          }
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
    this.#highlightNode = (node) => {
      hoveredNode = node;
      graph.linkColor(linkColor);
    };
    this.#focusNode = (node) => {
      if (![node.x, node.y, node.z].every(Number.isFinite)) {
        return;
      }
      const camera = graph.cameraPosition();
      const target = graph.controls().target;
      graph.cameraPosition(
        {
          x: node.x + camera.x - target.x,
          y: node.y + camera.y - target.y,
          z: node.z + camera.z - target.z,
        },
        node,
        200
      );
    };
    this.#updateVisibility = () => {
      const visibleIds = new Set(this.visibleNodes.map((node) => node.id));
      graph.nodeVisibility((node) => visibleIds.has(node.id));
      graph.linkVisibility(
        (link) =>
          visibleIds.has(nodeId(link.source)) &&
          visibleIds.has(nodeId(link.target))
      );
      if (visibleIds.size && hasFitGraph && !this.selectedUsername) {
        graph.zoomToFit(400, this.graph3DFitPadding, (node) =>
          visibleIds.has(node.id)
        );
      }
    };
    this.#updateVisibility();
    this.#restoreSelection();
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
          !this.#nodeInRange(node) ||
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

  #selectedNode() {
    return (
      this.currentGraphData?.nodes.find(
        (node) => node.id === this.selectedUsername
      ) ?? null
    );
  }

  #nodeInRange(node) {
    return (
      node.group >= this.minimumTrustLevel &&
      node.group <= this.maximumTrustLevel
    );
  }

  #applyTrustLevelFilter() {
    this.selectedUsername = this.searchMatches[0]?.id ?? null;
    this.#updateVisibility?.();
    this.#restoreSelection();
  }

  #restoreSelection() {
    const node = this.#selectedNode();
    this.#highlightNode?.(node);
    if (node) {
      this.#focusNode?.(node);
    }
  }

  <template>
    {{#if this.hasItems}}
      <div class="user-network-vis-container">
        <div class="user-network-vis__toolbar">
          <div class="user-network-vis__search">
            <DFilterInput
              aria-label={{i18n "user_network_vis.search"}}
              list={{this.searchListId}}
              placeholder={{i18n "user_network_vis.search"}}
              type="search"
              @filterAction={{this.searchUsername}}
              @onClearInput={{this.clearSearch}}
              @value={{this.searchTerm}}
            />
            <datalist id={{this.searchListId}}>
              {{#each this.searchMatches as |node|}}
                <option value={{node.id}}></option>
              {{/each}}
            </datalist>
            {{#if this.searchTerm}}
              <span class="user-network-vis__search-result">
                {{#if this.selectedUsername}}
                  {{this.selectedUsername}}
                {{else}}
                  {{i18n "user_network_vis.no_matching_user"}}
                {{/if}}
              </span>
            {{/if}}
          </div>
          <div class="user-network-vis__trust-filters">
            <label>
              {{i18n "user_network_vis.minimum_trust_level"}}
              <DNativeSelect
                class="user-network-vis__minimum-trust-level"
                @includeNone={{false}}
                @onChange={{this.changeMinimumTrustLevel}}
                @value={{this.minimumTrustLevel}}
                as |select|
              >
                {{#each this.trustLevelLegendItems as |item|}}
                  <select.Option
                    @value={{item.value}}
                  >{{item.label}}</select.Option>
                {{/each}}
              </DNativeSelect>
            </label>
            <label>
              {{i18n "user_network_vis.maximum_trust_level"}}
              <DNativeSelect
                class="user-network-vis__maximum-trust-level"
                @includeNone={{false}}
                @onChange={{this.changeMaximumTrustLevel}}
                @value={{this.maximumTrustLevel}}
                as |select|
              >
                {{#each this.trustLevelLegendItems as |item|}}
                  <select.Option
                    @value={{item.value}}
                  >{{item.label}}</select.Option>
                {{/each}}
              </DNativeSelect>
            </label>
          </div>
          <div
            class="user-network-vis__toolbar-row user-network-vis__toolbar-row--dimensions"
          >
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
            class="user-network-vis__toolbar-row user-network-vis__toolbar-row--colours"
            role="group"
            aria-label={{i18n "user_network_vis.colours"}}
          >
            <button
              type="button"
              class={{concat
                "user-network-vis__toggle"
                (if
                  this.clusterByRelationships
                  " user-network-vis__toggle--active"
                )
              }}
              aria-pressed={{if this.clusterByRelationships "true" "false"}}
              title={{i18n "user_network_vis.cluster_colours_title"}}
              {{on "click" (fn this.setRelationshipClusters true)}}
            >
              {{i18n "user_network_vis.cluster_by_relationships"}}
            </button>
            <button
              type="button"
              class={{concat
                "user-network-vis__toggle"
                (unless
                  this.clusterByRelationships
                  " user-network-vis__toggle--active"
                )
              }}
              aria-pressed={{if this.clusterByRelationships "false" "true"}}
              title={{i18n "user_network_vis.trust_level_colours_title"}}
              {{on "click" (fn this.setRelationshipClusters false)}}
            >
              {{i18n "user_network_vis.trust_level_colours"}}
            </button>
          </div>

          {{#unless this.clusterByRelationships}}
            <div class="user-network-vis__legend">
              {{#each this.trustLevelLegendItems as |item|}}
                <div class="user-network-vis__legend-item">
                  <span
                    class="user-network-vis__legend-swatch"
                    style={{item.style}}
                  ></span>
                  <span>{{item.label}}</span>
                </div>
              {{/each}}
            </div>
          {{/unless}}
        </div>

        <div
          class="user-network-vis"
          {{didInsert this.setup}}
          {{willDestroy this.teardown}}
        ></div>
        {{#unless this.visibleNodes.length}}
          <div class="user-network-vis__empty">{{i18n
              "user_network_vis.no_users_in_range"
            }}</div>
        {{/unless}}
      </div>
    {{/if}}
  </template>
}
