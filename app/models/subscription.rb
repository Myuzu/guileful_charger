# == Schema Information
#
# Table name: subscriptions
#
#  id                   :uuid             not null, primary key
#  active_at            :datetime
#  amount_cents         :integer          default(0), not null
#  cancellation_reason  :text
#  cancelled_at         :datetime
#  current_period_end   :datetime         not null
#  current_period_start :datetime         not null
#  paused_at            :datetime
#  status               :enum             default(NULL), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#
# Indexes
#
#  index_subscriptions_on_customer_id                    (customer_id)
#  index_subscriptions_on_status_and_current_period_end  (status,current_period_end)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#
class Subscription < ApplicationRecord
  include AASM

  VALID_STATUSES = %i[active cancelled paused].freeze

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) },
    prefix: true
  monetize :amount_cents

  belongs_to :customer
  has_many :invoices

  aasm timestamps:           true,
       no_direct_assignment: true,
       column:               :status,
       enum:                 true do
    state :active, initial: true
    state :cancelled
    state :paused

    event :pause do
      transitions from: :active, to: :paused do
        guard do
          # TODO: add any validation logic here
          true
        end

        after do
          self.pause_reason = pause_reason
          self.paused_at = Time.current
        end
      end
    end

    event :resume do
      transitions from: :paused, to: :active do
        after do
          self.active_at = Time.current
          self.pause_reason = nil
        end
      end
    end

    event :cancel do
      transitions from: %i[active paused], to: :cancelled do
        after do
          self.cancelled_at = Time.current
          self.cancellation_reason = cancellation_reason
        end
      end
    end
  end

  def issue_new_invoice
    invoices.create(issued_at:            Time.current,
                    billing_period_start: current_period_start,
                    billing_period_end:   current_period_end,
                    past_due_at:          next_due_date)
  end

  def next_due_date
    current_period_end.next_weekday
  end
end
