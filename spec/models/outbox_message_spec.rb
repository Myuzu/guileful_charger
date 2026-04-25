# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe OutboxMessage, type: :model do
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
