require "rails_helper"

RSpec.describe ProcessedMessage, type: :model do
  describe "deduplication" do
    it "does not allow the same consumer to process the same message twice" do
      described_class.create!(consumer_name: "Consumer", message_id: "message-1")

      expect {
        described_class.create!(consumer_name: "Consumer", message_id: "message-1")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "allows different consumers to process the same message" do
      described_class.create!(consumer_name: "ConsumerA", message_id: "message-1")

      message = described_class.new(consumer_name: "ConsumerB", message_id: "message-1")

      expect(message).to be_valid
    end
  end
end
