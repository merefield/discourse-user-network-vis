import DiscourseRoute from "discourse/routes/discourse";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { ajax } from "discourse/lib/ajax";
import EmberObject from "@ember/object";

export default DiscourseRoute.extend({
  model(data, transition) {
    return ajax("/usernetworkvis.json")
      .then((results) => {
        return EmberObject.create({
          results: results
        });
      })
      .catch(popupAjaxError);
  },

  // renderTemplate() {
  //   this.render("usernetworkvis");
  // },
});
