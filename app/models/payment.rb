class Payment < ApplicationRecord
  VALID_STATUSES = %i[pending completed failed].freeze

  belongs_to :customer
  belongs_to :invoice
end
