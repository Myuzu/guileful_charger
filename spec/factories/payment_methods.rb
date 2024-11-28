FactoryBot.define do
  factory :payment_method do
    name { "Credit Card" }
    last_used_at { "2024-11-28 20:11:16" }

    association :customer, factory: :random_customer
  end
end
