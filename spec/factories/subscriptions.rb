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
FactoryBot.define do
  factory :subscription do
    status { :active }
    amount_cents { 1200 }
    current_period_start { Time.current.beginning_of_month }
    current_period_end { Time.current.end_of_month  }
    last_payment_at { DateTime.now }
    next_payment_attempt_at { DateTime.now }

    association :customer
  end

  # factory :random_subscription, class: Subscription do
  #   status { :active }
  #   traits_for_enum :status, Subscription::VALID_STATUSES

  #   amount_cents { Faker::Number.between(from: 1000, to: 10_000) }
  #   billing_cycle_count { Faker::Number.between(from: 0, to: 24) }
  #   next_billing_at { DateTime.now }

  #   association :customer, factory: :random_customer
  # end
end
