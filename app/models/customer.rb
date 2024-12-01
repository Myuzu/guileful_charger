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
class Customer < ApplicationRecord
  has_many :subscriptions
  has_many :invoices
  has_many :payments
end
