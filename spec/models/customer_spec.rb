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
require 'rails_helper'

RSpec.describe Customer, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
