class OutboxMessage < ApplicationRecord
  validates :topic, presence: true
  validates :payload, presence: true

  scope :unpublished, -> { where(published_at: nil) }
  scope :claimable, ->(locked_before) {
    unpublished.where(locked_at: nil).or(unpublished.where(locked_at: ...locked_before))
  }

  def self.enqueue!(topic:, payload:, aggregate: nil, aggregate_version: nil)
    create!(topic:             topic,
            payload:           payload,
            aggregate_type:    aggregate&.class&.name,
            aggregate_id:      aggregate&.id,
            aggregate_version: aggregate_version)
  end
end
