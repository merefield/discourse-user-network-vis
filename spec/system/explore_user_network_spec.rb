# frozen_string_literal: true

require_relative "page_objects/user_network"

RSpec.describe "Explore the user network" do
  include ThemeScreenshotMarker

  let(:network) { PageObjects::Pages::UserNetwork.new }

  before do
    SiteSetting.user_network_vis_enabled = true
    SiteSetting.user_network_vis_default_view = "3d"
    SiteSetting.title = "Community Lab"

    usernames = %w[
      alex
      blair
      cameron
      devon
      ellis
      frankie
      gray
      harper
      indigo
      jamie
      kai
      logan
      morgan
      nico
      oakley
      parker
      quinn
      riley
      sage
      taylor
      val
      winter
      xen
      yuri
      zara
    ]
    users =
      usernames.each_with_index.map do |username, index|
        Fabricate(:user, username: username, trust_level: index % 5, last_seen_at: Time.current)
      end
    posts = users.map { |user| Fabricate(:post, user: user) }

    users.each_with_index do |user, index|
      group_start = index / 5 * 5
      [1, 2].each do |offset|
        original = posts[group_start + (index + offset) % 5]
        Fabricate(
          :post,
          user: user,
          topic: original.topic,
          reply_to_post_number: original.post_number,
        )
      end
      next unless index % 5 == 0

      original = posts[(index + 5) % users.size]
      Fabricate(
        :post,
        user: user,
        topic: original.topic,
        reply_to_post_number: original.post_number,
      )
    end

    Jobs::UserNetworkStatsCalc.new.execute
    avatar = Fabricate(:image_upload, width: 96, height: 96, color: "#4e79a7")
    users.first.update!(uploaded_avatar_id: avatar.id)
    sign_in(users.first)
    page.driver.with_playwright_page do |browser|
      browser.set_viewport_size(width: 1440, height: 1200)
    end
  end

  it "lets a member explore both dimensions, clusters and a matching username" do
    network.open
    expect(network).to have_graph("3D")
    network.wait_for_layout
    screenshot_marker(label: "user-network-3d", only: :desktop)

    network.choose("2D")
    expect(network).to have_graph("2D")
    network.wait_for_layout
    screenshot_marker(label: "user-network-2d", only: :desktop)

    network.choose("Clusters")
    screenshot_marker(label: "user-network-clusters", only: :desktop)

    network.search("alex")
    expect(network).to have_focus("alex")
    network.wait_for_layout
    screenshot_marker(label: "user-network-search", only: :desktop)
  end
end
