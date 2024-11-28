class Invoice < ApplicationRecord
  VALID_STATUSES = %i[draft issued paid void past_due].freeze

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) },
    prefix: true

  belongs_to :customer
  belongs_to :subscription
end
