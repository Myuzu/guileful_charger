FactoryBot.define do
  factory :subscription do
    status { :active }
    amount_cents { 1200 }
    billing_cycle_count { 0 }
    next_billing_at { DateTime.now }

    association :customer, factory: :customer
  end

  factory :random_subscription, class: Subscription do
    status { :active }
    traits_for_enum :status, Subscription::VALID_STATUSES

    amount_cents { Faker::Number.between(from: 1000, to: 10_000) }
    billing_cycle_count { Faker::Number.between(from: 0, to: 24) }
    next_billing_at { DateTime.now }

    association :customer, factory: :random_customer
  end
end
