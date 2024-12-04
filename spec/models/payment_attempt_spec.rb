# == Schema Information
#
# Table name: payment_attempts
#
#  id                     :uuid             not null, primary key
#  amount_attempted_cents :integer          default(0), not null
#  attempt_number         :integer          not null
#  completed_at           :datetime
#  failed_at              :datetime
#  failure_reason         :text
#  gateway_response       :text
#  pending_at             :datetime
#  processing_at          :datetime
#  retry_strategy         :enum
#  scheduled_at           :datetime
#  status                 :enum             default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  gateway_transaction_id :text
#  invoice_id             :uuid             not null
#
# Indexes
#
#  index_payment_attempts_on_invoice_id             (invoice_id)
#  index_payment_attempts_on_invoice_id_and_status  (invoice_id,status)
#  index_payment_attempts_on_scheduled_at           (scheduled_at)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#
require 'rails_helper'

RSpec.describe PaymentAttempt, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
