# == Schema Information
#
# Table name: payment_attempts
#
#  id              :uuid             not null, primary key
#  amount_cents    :integer          default(0), not null
#  attempt_number  :integer          not null
#  failure_reason  :text
#  paid_at         :datetime
#  processed_at    :datetime
#  scheduled_at    :datetime         not null
#  status          :enum             default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  customer_id     :uuid             not null
#  subscription_id :uuid             not null
#  transaction_id  :text
#
# Indexes
#
#  index_payment_attempts_on_customer_id                         (customer_id)
#  index_payment_attempts_on_scheduled_at                        (scheduled_at)
#  index_payment_attempts_on_status                              (status)
#  index_payment_attempts_on_subscription_id                     (subscription_id)
#  index_payment_attempts_on_subscription_id_and_attempt_number  (subscription_id,attempt_number)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
require 'rails_helper'

RSpec.describe PaymentAttempt, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
