# == Schema Information
#
# Table name: invoices
#
#  id                 :uuid             not null, primary key
#  amount_paid_cents  :integer          default(0), not null
#  amount_total_cents :integer          default(0), not null
#  issued_at          :datetime
#  next_retry_at      :datetime
#  not_paid_at        :datetime
#  paid_at            :datetime
#  partially_paid_at  :datetime
#  past_due_at        :datetime
#  status             :enum             default("issued"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  subscription_id    :uuid             not null
#
# Indexes
#
#  index_invoices_on_subscription_id  (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (subscription_id => subscriptions.id)
#
require 'rails_helper'

RSpec.describe Invoice, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
