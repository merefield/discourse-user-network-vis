import { withPluginApi } from 'discourse/lib/plugin-api';
import {
  getResolverOption,
} from "discourse-common/resolver";

export default {
  name: 'user-network-vis-inits',
  initialize(container) {
    const currentUser = container.lookup("current-user:main");
    const siteSettings = container.lookup("site-settings:main");
    const isMobileDevice = getResolverOption("mobileView");

    if (!siteSettings.user_network_vis_enabled || !currentUser || isMobileDevice) return;

    withPluginApi('0.8.40', api => {

      if (siteSettings.user_network_vis_add_menu_item) {
        api.addCommunitySectionLink({
          name: "users network",
          route: "usernetworkvis",
          title: I18n.t("user_network_vis.sidebar_menu_label"),
          text: I18n.t("user_network_vis.sidebar_menu_label"),
        });
      }
    });
  }
};
