# == Schema Information
#
# Table name: customers
#
#  id              :uuid             not null, primary key
#  billing_address :text             not null
#  email           :text             not null
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_customers_on_email  (email) UNIQUE
#
FactoryBot.define do
  factory :customer do
    name            { "Ivan Bolhar" }
    email           { "ivan@bolhar.me" }
    billing_address { "Non-Disclosure Ave 12/4 kv. 42" }
  end

  factory :random_customer, class: Customer do
    name            { Faker::Name.name }
    email           { Faker::Internet.email }
    billing_address { Faker::Address.full_address }
  end
end
