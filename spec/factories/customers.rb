FactoryBot.define do
  factory :customer do
    name            { "Ivan Bolhar" }
    email           { "ivan@bolhar.me" }
    billing_address { "Non-Disclosure Ave 12/4 kv. 42" }
  end

  factory :random_customer, class: Customer do
    name            { Faker::Name.name }
    email           { Faker::Internet.email }
    billing_address { Faker::Address.full_address}
  end
end
