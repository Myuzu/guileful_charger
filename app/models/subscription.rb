# == Schema Information
#
# Table name: subscriptions
#
#  id                      :uuid             not null, primary key
#  amount_cents            :integer          default(0), not null
#  current_period_end      :datetime         not null
#  current_period_start    :datetime         not null
#  last_payment_at         :datetime
#  next_payment_attempt_at :datetime
#  retry_count             :integer          default(0), not null
#  status                  :enum             default(NULL), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  customer_id             :uuid             not null
#
# Indexes
#
#  index_subscriptions_on_current_period_end                  (current_period_end)
#  index_subscriptions_on_customer_id                         (customer_id)
#  index_subscriptions_on_status_and_next_payment_attempt_at  (status,next_payment_attempt_at)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#
class Subscription < ApplicationRecord
  VALID_STATUSES = %i[active cancelled past_due partially_paid].freeze

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) },
    prefix: true
  monetize :amount_cents

  belongs_to :customer
  has_many :payment_attempts

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
