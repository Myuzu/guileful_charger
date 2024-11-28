class Payment < ApplicationRecord
  VALID_STATUSES = %i[pending completed failed].freeze
  belongs_to :customer
end
