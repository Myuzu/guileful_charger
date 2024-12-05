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
    email           { Faker::Internet.email }
    billing_address { Faker::Address.full_address }
  end
end
