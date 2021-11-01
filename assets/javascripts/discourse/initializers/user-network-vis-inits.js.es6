import { withPluginApi } from 'discourse/lib/plugin-api';

export default {
  name: 'user-network-vis-inits',
  initialize(container) {
    const currentUser = container.lookup("current-user:main");
    const siteSettings = container.lookup("site-settings:main");
    const isMobileDevice = container.lookup('site:main').get('isMobileDevice');

    if (!siteSettings.user_network_vis_enabled || !currentUser || isMobileDevice) return;

    withPluginApi('0.8.13', api => {

      api.decorateWidget("hamburger-menu:generalLinks", function(helper) {
        return {href: "/usernetworkvis", rawLabel: I18n.t('user_network_vis.hamburger_menu_label')}
      });

    });
  }
};
