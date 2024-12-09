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
#  idx_on_subscription_id_billing_period_start_billing_97b6392bf1  (subscription_id,billing_period_start,billing_period_end) UNIQUE
#  index_invoices_on_subscription_id                               (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (subscription_id => subscriptions.id)
#
class Invoice < ApplicationRecord
  include AASM

  VALID_STATUSES = %i[draft open paid partially_paid not_paid]

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) }

  monetize :amount_total_cents
  monetize :amount_paid_cents

  has_many :payment_attempts
  belongs_to :subscription

  validates :subscription_id, uniqueness: {
    scope:   %i[billing_period_start billing_period_end],
    message: "Already has an Invoice for this billing period"
  }

  aasm timestamps:           true,
       no_direct_assignment: true,
       column:               :status,
       enum:                 true do
    state :draft, initial: true
    state :open
    state :paid
    state :partially_paid
    state :not_paid

    event :open_new do
      transitions from: :draft, to: :open do
        after { create_new_payment_attempt }
      end
    end
  end

  def create_new_payment_attempt
    payment_attempts.create!(amount_attempted: amount_remaining,
                             attempt_number:   1,
                             retry_strategy:   :initial)
  end

  def amount_remaining
    amount_total - amount_paid_cents
  end
end
