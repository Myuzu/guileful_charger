class Subscription < ApplicationRecord
  VALID_STATUSES = %i[active paused cancelled past_due].freeze

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) },
    prefix: true
  monetize :amount_cents
  belongs_to :customer_id
end
