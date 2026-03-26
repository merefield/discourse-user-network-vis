import { withPluginApi } from "discourse/lib/plugin-api";
import { getResolverOption } from "discourse/resolver";
import { i18n } from "discourse-i18n";

export default {
  name: "user-network-vis-inits",

  initialize(owner) {
    const currentUser = owner.lookup("service:current-user");
    const siteSettings = owner.lookup("service:site-settings");
    const isMobileDevice = getResolverOption("mobileView");

    if (
      !siteSettings.user_network_vis_enabled ||
      !currentUser ||
      isMobileDevice
    ) {
      return;
    }

    withPluginApi((api) => {
      if (siteSettings.user_network_vis_add_menu_item) {
        api.addCommunitySectionLink({
          name: "users network",
          route: "usernetworkvis",
          title: i18n("user_network_vis.sidebar_menu_label"),
          text: i18n("user_network_vis.sidebar_menu_label"),
        });
      }
    });
  },
};
