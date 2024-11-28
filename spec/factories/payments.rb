FactoryBot.define do
  factory :payment do
    status { :completed }
    amount_cents { 1200 }
    transaction_id { "3DXr8xOoobomobuENfdk8Q" }
    paid_at { DateTime.now }
    failure_reason { }

    association :customer, factory: :customer
    association :invoice,  factory: :invoice
  end

  factory :random_payment, class: Payment do
    status { :pending }
    traits_for_enum :status, Payment::VALID_STATUSES

    amount_cents { Faker::Number.between(from: 1000, to: 10_000) }
    transaction_id { SecureRandom.urlsafe_base64 }
    paid_at { DateTime.now }
    failure_reason do
      %i[failed insufficient_funds].shuffle.take(1) if status == :failed
    end

    association :customer, factory: :random_customer
    association :invoice,  factory: :random_invoice
  end
end
