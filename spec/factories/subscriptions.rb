# == Schema Information
#
# Table name: subscriptions
#
#  id                   :uuid             not null, primary key
#  active_at            :datetime
#  amount_cents         :integer          default(0), not null
#  cancellation_reason  :text
#  cancelled_at         :datetime
#  current_period_end   :datetime         not null
#  current_period_start :datetime         not null
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
FactoryBot.define do
  factory :subscription do
    amount_cents { 1200 }
    current_period_start { Time.current.beginning_of_month }
    current_period_end { Time.current.end_of_month  }

    trait :active do
      after(:build) do |subscription|
        subscription[:status] = :active
      end
    end

    trait :paused do
      paused_at { Time.current }
      pause_reason { "customer requested pause" }

      after(:build) do |subscription|
        subscription[:status] = :paused
      end
    end

    trait :cancelled do
      cancelled_at { Time.current }
      cancellation_reason { "customer requested cancellation" }

      after(:build) do |subscription|
        subscription[:status] = :cancelled
      end
    end

    customer
  end

  factory :random_subscription, class: 'Subscription' do
    amount_cents { Faker::Number.between(from: 1000, to: 10_000) }
    current_period_start { Time.current.beginning_of_month }
    current_period_end { Time.current.end_of_month }

    customer
  end
end
