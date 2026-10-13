# frozen_string_literal: true

RSpec.describe UserNetworkVis do
  fab!(:new_user) { Fabricate(:user, created_at: 5.days.ago) }
  fab!(:partner) { Fabricate(:user, created_at: 1.year.ago) }

  def run_query(key, params = {})
    sql = File.read(File.expand_path("../../queries/#{key}.sql", __dir__))
    defaults =
      DiscourseDataExplorer::Query.new(sql: sql).cast_params(
        params.with_indifferent_access
      )
    DB.query(sql, defaults)
  end

  it "reads exactly the stored graph edges and supports username filtering" do
    PluginStore.set(
      UserNetworkVis::PLUGIN_NAME,
      "user_network_list",
      {
        nodes: [
          { id: new_user.username_lower, group: 0 },
          { id: partner.username_lower, group: 3 }
        ],
        links: [
          {
            source: new_user.username_lower,
            target: partner.username_lower,
            value: 17
          }
        ]
      }
    )

    rows = run_query("snapshot")
    expect(rows.map(&:weighted_score)).to eq([17])
    expect(rows.first.source_user_id).to eq(new_user.id)
    expect(rows.first.target_trust_level).to eq(3)
    expect(
      run_query("snapshot", username: new_user.username.upcase).size
    ).to eq(1)
    expect(run_query("snapshot", username: "no_such_username")).to be_empty
  end

  it "measures concentration and reciprocity without graph trust level or score filters" do
    post = Fabricate(:post, user: new_user)
    UserAction.create!(
      action_type: UserAction::WAS_LIKED,
      user_id: new_user.id,
      acting_user_id: partner.id,
      target_post_id: post.id,
      target_topic_id: post.topic_id
    )
    Fabricate(
      :post,
      topic: post.topic,
      user: partner,
      reply_to_post_number: post.post_number
    )
    partner_post = Fabricate(:post, user: partner)
    Fabricate(
      :post,
      topic: partner_post.topic,
      user: new_user,
      reply_to_post_number: partner_post.post_number
    )
    SiteSetting.user_network_vis_minimum_trust_level = 4
    SiteSetting.user_network_vis_link_score_threshold = 100

    rows = run_query("new_user_interactions", minimum_interactions: 3)
    expect(rows.map(&:user_id)).to eq([new_user.id])
    expect(rows.first.to_h).to include(
      counterpart_count: 1,
      total_interactions: 3,
      likes_received: 1,
      replies_received: 1,
      interactions_given: 1,
      reciprocal_counterparts: 1,
      top_counterpart_percent: 100,
      top_counterpart_user_id: partner.id
    )
    expect(
      run_query("new_user_interactions", minimum_interactions: 4)
    ).to be_empty

    Fabricate(
      :post,
      topic: post.topic,
      user: Fabricate(:user, created_at: 1.year.ago),
      reply_to_post_number: post.post_number
    )
    expect(
      run_query("new_user_interactions", minimum_interactions: 3)
    ).to be_empty
    broader_results =
      run_query(
        "new_user_interactions",
        minimum_interactions: 3,
        minimum_top_counterpart_percent: 75
      )
    expect(broader_results.first.to_h).to include(
      counterpart_count: 2,
      top_counterpart_percent: 75
    )
    expect(
      run_query(
        "new_user_interactions",
        minimum_interactions: 3,
        minimum_top_counterpart_percent: 75,
        maximum_counterparts: 1
      )
    ).to be_empty
  end

  it "excludes restricted, deleted, hidden, old and self interactions" do
    private_category = Fabricate(:private_category, group: Fabricate(:group))
    topics = [
      Fabricate(:topic, category: private_category),
      Fabricate(:private_message_topic, user: new_user),
      Fabricate(:topic, visible: false),
      Fabricate(:topic, deleted_at: Time.current)
    ]
    topics.each do |topic|
      original = Fabricate(:post, topic: topic, user: new_user)
      Fabricate(
        :post,
        topic: topic,
        user: partner,
        reply_to_post_number: original.post_number
      )
    end
    [{ deleted_at: Time.current }, { hidden: true }].each do |attributes|
      original = Fabricate(:post, user: new_user, **attributes)
      Fabricate(
        :post,
        topic: original.topic,
        user: partner,
        reply_to_post_number: original.post_number
      )
    end
    original = Fabricate(:post, user: new_user)
    Fabricate(
      :post,
      topic: original.topic,
      user: partner,
      reply_to_post_number: original.post_number,
      created_at: 40.days.ago
    )
    Fabricate(
      :post,
      topic: original.topic,
      user: new_user,
      reply_to_post_number: original.post_number
    )

    expect(
      run_query("new_user_interactions", minimum_interactions: 1)
    ).to be_empty
  end
end
