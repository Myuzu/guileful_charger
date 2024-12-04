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
class PaymentAttempt < ApplicationRecord
  include AASM

  VALID_STATUSES = %i[pending scheduled processing completed failed].freeze

  monetize :amount_attempted_cents

  belongs_to :invoice, counter_cache: true

  aasm timestamps:           true,
       no_direct_assignment: true,
       column:               :status,
       enum:                 true do
    state :pending, initial: true
    state :scheduled
    state :processing
    state :completed
    state :failed
  end
end
