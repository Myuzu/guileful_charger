class Customer < ApplicationRecord
  has_many :subscriptions
  has_many :invoices
  has_many :payments
end
