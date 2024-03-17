import loadScript from "discourse/lib/load-script";
import DiscourseURL from "discourse/lib/url";
import { notEmpty, alias } from "@ember/object/computed";
import { observes } from 'discourse-common/utils/decorators';
import Component from "@ember/component";

export default Component.extend({
  classNames: "user-network-vis",
  results: alias("model.results"),
  hasItems: notEmpty("results"),

  ensureD3() {
    return loadScript("/plugins/discourse-user-network-vis/d3/d3.min.js");
  },

  didInsertElement() {
    if (!this.site.mobileView) {
      this.waitForData()
    }
  },

  // addZoomBehavior() {
  //   const svg = d3.select(".user-network-vis svg");
  //   const zoom = d3.zoom().on("zoom", () => {
  //     svg.attr("transform", d3.event.transform);
  //   });
  //   svg.call(zoom);
  // },

  @observes("hasItems")
  waitForData() {
    if(!this.hasItems) {
      return;
    } else {
      this.setup();
    }
  },

  setup() {
    var _this = this;

    this.ensureD3().then(() => {

      function fade(opacity) {
        return function (d) {
          // check all other nodes to see if they're connected
          // to this one. if so, keep the opacity at 1, otherwise
          // fade
          node.style("opacity", function (o) {
            return isConnected(d.currentTarget.__data__, o) ? 1 : opacity;
          });
          // also style link accordingly
          link.style("opacity", function (o) {
            return o.source.id === d.currentTarget.__data__.id || o.target.id === d.currentTarget.__data__.id ? 1 : opacity;
          });
        };
      }

      var width = 1120,
        height = _this.siteSettings.user_network_vis_canvas_height;

      var svg = d3
        .select(".user-network-vis")
        .append("svg")
        .attr("width", width)
        .attr("height", height)
        .call(d3.zoom().on("zoom", function () {
            svg.attr("transform", d3.event.transform)
         }))

      var zoomBehavior = d3.zoom()
        .scaleExtent([0.1, 10])
        .on("zoom", zoomed);

      svg.call(zoomBehavior);

      var color = d3.scaleOrdinal(
        _this.siteSettings.user_network_vis_colors.split("|")
      );

      var simulation = d3
        .forceSimulation()
        .force(
          "link",
          d3.forceLink().id((d) => {
            return d.id;
          })
        )
        .force(
          "charge",
          d3
            .forceManyBody()
            .strength(
              -_this.siteSettings.user_network_vis_node_charge_strength
            )
        )
        .force("center", d3.forceCenter(width / 2, height / 2));

      var link = svg
        .append("g")
        .attr("class", "links")
        .selectAll("line")
        .data(_this.results.user_network_stats.links)
        .enter()
        .append("line")
        .attr("stroke-width", (d) => {
          return Math.cbrt(Math.round(d.value) + 1);
        });

      var node = svg
        .append("g")
        .attr("class", "nodes")
        .selectAll("g")
        .data(_this.results.user_network_stats.nodes)
        .enter()
        .append("g")
        .on("mouseover", fade(.1))
        .on("mouseout", fade(1));

      var circles = node
        .append("circle")
        .attr("r", _this.siteSettings.user_network_vis_node_radius)
        .attr("fill", (d) => {
          return color(d.group + 1);
        })
        .call(
          d3
            .drag()
            .on("start", dragstarted)
            .on("drag", dragged)
            .on("end", dragended)
        )
        .on("click", (event, d) => {
          if (d.id) {
            DiscourseURL.routeTo(`/u/${d.id}/summary`);
          }
        })

      var labels = node
        .append("text")
        .text((d) => {
          return d.id;
        })
        .attr("x", _this.siteSettings.user_network_vis_node_radius + 1)
        .attr("y", _this.siteSettings.user_network_vis_node_radius / 2 + 1);

      node.append("title").text((d) => {
        return d.id;
      });

      simulation
        .nodes(_this.results.user_network_stats.nodes)
        .on("tick", ticked);

      simulation.force("link").links(_this.results.user_network_stats.links);

      var linkedByIndex = {};

      simulation
        .force("link")
        .links()
        .forEach(function (d) {
          linkedByIndex[d.source.index + "," + d.target.index] = 1;
        });

      function zoomed(event) {
        svg.attr("transform", `scale(${event.transform.k})`)
      }

      function isConnected(a, b) {
        return (
          linkedByIndex[a.index + "," + b.index] ||
          linkedByIndex[b.index + "," + a.index] ||
          a.index == b.index
        );
      }

      function ticked() {
        link
          .attr("x1", (d) => {
            return d.source.x;
          })
          .attr("y1", (d) => {
            return d.source.y;
          })
          .attr("x2", (d) => {
            return d.target.x;
          })
          .attr("y2", (d) => {
            return d.target.y;
          });

        node.attr("transform", (d) => {
          return "translate(" + d.x + "," + d.y + ")";
        });
      }

      function dragstarted(event, d) {
        if (!event.active) simulation.alphaTarget(0.3).restart();
        d.fx = d.x;
        d.fy = d.y;
      }

      function dragged(event, d) {
        d.fx = event.x;
        d.fy = event.y;
      }

      function dragended(event, d) {
        if (!event.active) simulation.alphaTarget(0);
        d.fx = null;
        d.fy = null;
      }
    });
  },
});
