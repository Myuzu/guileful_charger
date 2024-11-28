FactoryBot.define do
  factory :invoice do
    status { :draft }
    amount_cents { 1200 }
    due_date { DateTime.now }
    issued_at { DateTime.now }

    association :customer,     factory: :customer
    association :subscription, factory: :subscription
  end

  factory :random_invoice, class: Invoice do
    status { :draft }
    traits_for_enum :status, Invoice::VALID_STATUSES

    amount_cents { Faker::Number.between(from: 1000, to: 10_000) }
    due_date { DateTime.now }
    issued_at { DateTime.now }

    association :customer,     factory: :random_customer
    association :subscription, factory: :random_active_subscription
  end
end
