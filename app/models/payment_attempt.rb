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
#  gateway_response       :jsonb
#  pending_at             :datetime
#  processing_at          :datetime
#  retry_strategy         :enum
#  scheduled_at           :datetime
#  status                 :enum             default(NULL), not null
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

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) }

  monetize :amount_attempted_cents

  belongs_to :invoice, counter_cache: true

  delegate :subscription, to: :invoice

  aasm timestamps: true,
       column:     :status,
       enum:       true do
    state :pending, initial: true
    state :scheduled
    state :processing
    state :completed
    state :failed

    event :schedule do
      transitions from: :pending, to: :scheduled
    end

    event :start_processing do
      transitions from: :scheduled, to: :processing
    end

    event :succeed do
      transitions from: :processing, to: :completed do
        after do |response|
          update!(gateway_response:       response.to_h,
                  gateway_transaction_id: response.transaction_id,
                  completed_at:           Time.current)
        end
      end
    end

    event :fail do
      transitions from: :processing, to: :failed do
        after do |response, failure_reason|
          update!(gateway_response:       response.to_h,
                  gateway_transaction_id: response.transaction_id,
                  failure_reason:         failure_reason,
                  failed_at:              Time.current)
        end
      end
    end
  end
end
