import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

export default class UsernetworkvisRoute extends DiscourseRoute {
  model() {
    return ajax("/usernetworkvis.json")
      .then((results) => ({ results }))
      .catch(popupAjaxError);
  }
}
