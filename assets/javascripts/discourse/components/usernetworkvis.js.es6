import loadScript from "discourse/lib/load-script";
import DiscourseURL from "discourse/lib/url";

export default Ember.Component.extend({
  classNames: "user-network-vis",
  results: Ember.computed.alias("model.results"),

  ensureD3() {
    return loadScript("/plugins/discourse-user-network-vis/d3/d3.min.js");
  },

  didInsertElement() {
    if (!this.site.mobileView) {
      this.setup();
    }
  },

  setup() {
    var _this = this;

    this.ensureD3().then(() => {
      var width = 1120,
        height = Discourse.SiteSettings.user_network_vis_render_height;

      var svg = d3
        .select(".user-network-vis")
        .append("svg")
        .attr("width", width)
        .attr("height", height);

      var color = d3.scaleOrdinal(d3.schemeAccent);

      var simulation = d3
        .forceSimulation()
        .force(
          "link",
          d3.forceLink().id((d) => {
            return d.id;
          })
        )
        .force("charge", d3.forceManyBody().strength(-Discourse.SiteSettings.user_network_vis_node_charge_strength))
        .force("center", d3.forceCenter(width / 2, height / 2));

      var link = svg
        .append("g")
        .attr("class", "links")
        .selectAll("line")
        .data(_this.results.user_network_stats.links)
        .enter()
        .append("line")
        .attr("stroke-width", (d) => {
          //return 2
          return Math.sqrt(Math.round(d.value / 20) + 1);
        });

      var node = svg
        .append("g")
        .attr("class", "nodes")
        .selectAll("g")
        .data(_this.results.user_network_stats.nodes)
        .enter()
        .append("g");

      var circles = node
        .append("circle")
        .attr("r", 6)
        .attr("fill", (d) => {
          return color(d.group + 1);
        })
        .call(
          d3
            .drag()
            .on("start", dragstarted)
            .on("drag", dragged)
            .on("end", dragended)
        );

      var lables = node
        .append("text")
        .text((d) => {
          return d.id;
        })
        .attr("x", 6)
        .attr("y", 3);

      node.append("title").text((d) => {
        return d.id;
      });

      simulation
        .nodes(_this.results.user_network_stats.nodes)
        .on("tick", ticked);

      simulation.force("link").links(_this.results.user_network_stats.links);

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
