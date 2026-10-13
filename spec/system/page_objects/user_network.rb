# frozen_string_literal: true

module PageObjects
  module Pages
    class UserNetwork < Base
      def open
        visit("/usernetworkvis")
      end

      def choose(mode)
        find(".user-network-vis__toolbar").click_button(mode, exact: true)
      end

      def search(username)
        fill_in("Find a username", with: username)
      end

      def has_focus?(username)
        has_css?(".user-network-vis__search-result", exact_text: username)
      end

      def has_graph?(dimensions)
        if dimensions == "3D"
          has_css?(".user-network-vis canvas") &&
            has_css?(".user-network-vis__3d-label", minimum: 25)
        else
          has_css?(".user-network-vis svg circle", count: 25)
        end
      end

      def wait_for_layout
        # Wait for both the force simulation and the automatic camera fit.
        page.driver.with_playwright_page do |browser|
          browser.wait_for_function(<<~JS, timeout: 60_000)
            () => {
              const nodes = [...document.querySelectorAll(
                '.user-network-vis__3d-label, .user-network-vis svg circle'
              )];
              const positions = nodes.map(node => {
                const rect = node.getBoundingClientRect();
                return [Math.round(rect.x), Math.round(rect.y)];
              });
              const value = JSON.stringify(positions);
              const state = window.networkScreenshotLayout ||= {};
              if (state.value !== value) {
                state.value = value;
                state.since = performance.now();
              }
              const canvas = document.querySelector('.user-network-vis canvas');
              const bounds = canvas?.getBoundingClientRect();
              const fitted = !bounds || positions.every(([x, y]) =>
                x >= bounds.left && x <= bounds.right &&
                y >= bounds.top && y <= bounds.bottom
              );
              return nodes.length === 25 && fitted && performance.now() - state.since > 1500;
            }
          JS
        end
      end

      def has_rendered_pixels?(dimensions)
        selector = dimensions == "3D" ? ".user-network-vis canvas" : ".user-network-vis svg"
        page.driver.with_playwright_page do |browser|
          # Screenshot the renderer alone: DOM labels must not mask a blank WebGL canvas.
          png =
            browser.locator(selector).screenshot(
              style:
                ".user-network-vis__3d-labels, .user-network-vis__toolbar { visibility: hidden !important; }",
            )
          browser.evaluate(<<~JS, arg: "data:image/png;base64,#{Base64.strict_encode64(png)}")
            async (source) => {
              const image = new Image();
              image.src = source;
              await image.decode();
              const canvas = document.createElement('canvas');
              canvas.width = image.width;
              canvas.height = image.height;
              const context = canvas.getContext('2d');
              context.drawImage(image, 0, 0);
              const pixels = context.getImageData(0, 0, image.width, image.height).data;
              const colours = new Set();
              for (let offset = 0; offset < pixels.length; offset += 4) {
                if (pixels[offset + 3] > 0) {
                  colours.add(`${pixels[offset]},${pixels[offset + 1]},${pixels[offset + 2]}`);
                }
                if (colours.size > 20) {
                  return true;
                }
              }
              return false;
            }
          JS
        end
      end
    end
  end
end
