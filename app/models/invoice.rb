# == Schema Information
#
# Table name: invoices
#
#  id                     :uuid             not null, primary key
#  amount_paid_cents      :integer          default(0), not null
#  amount_total_cents     :integer          default(0), not null
#  billing_period_end     :datetime         not null
#  billing_period_start   :datetime         not null
#  draft_at               :datetime
#  next_retry_at          :datetime
#  not_paid_at            :datetime
#  open_at                :datetime
#  paid_at                :datetime
#  partially_paid_at      :datetime
#  payment_attempts_count :integer          default(0), not null
#  status                 :enum             default(NULL), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  subscription_id        :uuid             not null
#
# Indexes
#
#  index_invoices_on_subscription_id  (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (subscription_id => subscriptions.id)
#
class Invoice < ApplicationRecord
  include AASM

  VALID_STATUSES = %i[draft open paid partially_paid not_paid]

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) },
    prefix: true

  monetize :amount_total_cents
  monetize :amount_paid_cents

  has_many :payment_attempts

  aasm timestamps:           true,
       no_direct_assignment: true,
       column:               :status,
       enum:                 true do
    state :draft, initial: true
    state :open
    state :paid
    state :partially_paid
    state :not_paid
  end
end
