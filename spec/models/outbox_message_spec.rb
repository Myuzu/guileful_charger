# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe OutboxMessage, type: :model do
  def partition_name_for(message)
    query = <<~SQL.squish
      SELECT c.relname
      FROM outbox_messages o
      JOIN pg_class c ON c.oid = o.tableoid
      WHERE o.id = ?
    SQL
    sql = ActiveRecord::Base.sanitize_sql_array([ query, message.id ])

    ActiveRecord::Base.connection.select_value(sql)
  end

  describe ".unpublished" do
    it "returns messages that have not been published" do
      unpublished = described_class.create!(topic: "subscription.paused", payload: { event: "test" })
      described_class.create!(topic: "subscription.resumed", payload: { event: "test" }, published_at: Time.current)

      expect(described_class.unpublished).to contain_exactly(unpublished)
    end
  end

  describe ".claimable" do
    it "returns unlocked and stale locked unpublished messages" do
      unlocked = described_class.create!(topic: "subscription.paused", payload: { event: "test" })
      stale_locked = described_class.create!(topic: "subscription.resumed", payload: { event: "test" }, locked_at: 1.hour.ago)
      described_class.create!(topic: "subscription.cancelled", payload: { event: "test" }, locked_at: Time.current)

      expect(described_class.claimable(15.minutes.ago)).to contain_exactly(unlocked, stale_locked)
    end
  end

  describe "database defaults and partitioning" do
    it "configures pg_partman published retention for 7 days" do
      config = ActiveRecord::Base.connection.select_one(<<~SQL.squish)
        SELECT retention, retention_keep_table, retention_keep_index
        FROM partman.part_config
        WHERE parent_table = 'public.outbox_messages_published'
      SQL

      expect(config).to include("retention" => "7 days",
                                "retention_keep_table" => false,
                                "retention_keep_index" => false)
    end

    it "creates a default published partition as a safety net" do
      partition_names = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
        SELECT child.relname
        FROM pg_inherits
        JOIN pg_class parent ON parent.oid = pg_inherits.inhparent
        JOIN pg_class child ON child.oid = pg_inherits.inhrelid
        WHERE parent.relname = 'outbox_messages_published'
      SQL

      expect(partition_names).to include("outbox_messages_published_default")
    end

    it "uses PostgreSQL uuidv7 IDs whose timestamps can be extracted" do
      message = described_class.create!(topic: "subscription.paused", payload: { event: "test" })
      extracted_timestamp = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([ "SELECT uuid_extract_timestamp(?)", message.id ])
      )

      expect(message.id.split("-").third.first).to eq("7")
      expect(extracted_timestamp).to be_present
    end

    it "omits created_at because creation time comes from uuid_extract_timestamp(id)" do
      expect(described_class.column_names).not_to include("created_at")
    end

    it "stores unpublished rows in the unpublished partition" do
      message = described_class.create!(topic: "subscription.paused", payload: { event: "test" })

      expect(partition_name_for(message)).to eq("outbox_messages_unpublished")
    end

    it "moves rows to a published partition when published_at is set" do
      message = described_class.create!(topic: "subscription.paused", payload: { event: "test" })

      message.update!(published_at: Time.current)

      expect(partition_name_for(message)).to start_with("outbox_messages_published")
    end
  end

  describe ".enqueue!" do
    it "creates an unpublished outbox message for an aggregate" do
      subscription = FactoryBot.create(:subscription)

      message = described_class.enqueue!(topic:             "subscription.paused",
                                         payload:           subscription.lifecycle_payload(reason: "pause"),
                                         aggregate:         subscription,
                                         aggregate_version: subscription.state_version)

      expect(message).to be_persisted
      expect(message.topic).to eq("subscription.paused")
      expect(message.aggregate_type).to eq("Subscription")
      expect(message.aggregate_id).to eq(subscription.id)
      expect(message.aggregate_version).to eq(subscription.state_version)
      expect(message.published_at).to be_nil
    end
  end
end
