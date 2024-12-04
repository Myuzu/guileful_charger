# == Schema Information
#
# Table name: subscriptions
#
#  id                   :uuid             not null, primary key
#  active_at            :datetime
#  amount_cents         :integer          default(0), not null
#  cancel_reason        :text
#  cancelled_at         :datetime
#  current_period_end   :datetime         not null
#  current_period_start :datetime         not null
#  paused_at            :datetime
#  status               :enum             default(NULL), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#
# Indexes
#
#  index_subscriptions_on_customer_id                    (customer_id)
#  index_subscriptions_on_status_and_current_period_end  (status,current_period_end)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#
class Subscription < ApplicationRecord
  include AASM

  VALID_STATUSES = %i[active cancelled paused].freeze

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) },
    prefix: true
  monetize :amount_cents

  belongs_to :customer
  has_many :payment_attempts

  aasm timestamps: true, no_direct_assignment: true, column: :status, enum: true do
    state :active
    state :cancelled
    state :paused
  end

  def due_for_payment
    where(status: %i[active past_due])
      .where("next_payment_attempt_at <= ?", Time.current)
  end

  def requires_retry
    where(status: %i[past_due partially_paid])
      .where("next_payment_attempt_at <= ?", Time.current)
  end

  def calculate_payment_amount
    total_collected = subscription.payment_attempts
                                  .succeeded
                                  .sum(:amount)

      remaining_balance = subscription.payment_attempts
                                    .first
                                    .original_amount - total_collected
  end
end
