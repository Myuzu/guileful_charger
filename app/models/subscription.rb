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

  VALID_STATUSES = %i[active cancelled].freeze

  enum :status, VALID_STATUSES.reduce({}) { |acc, v| acc.merge(v => v) }
  monetize :amount_cents

  belongs_to :customer
  has_many :invoices
  has_one :latest_invoice, -> {
    order(billing_period_end: :desc)
  }, class_name: "Invoice"

  # TODO: extract to QueryObject
  def self.without_invoice_for_current_period
    subscriptions = Subscription.arel_table
    invoices      = Invoice.arel_table

    period_match_condition = invoices[:subscription_id].eq(subscriptions[:id])
      .and(invoices[:billing_period_start].eq(subscriptions[:current_period_start]))
      .and(invoices[:billing_period_end].eq(subscriptions[:current_period_end]))

    invoice_exists = Invoice.unscoped
                            .where(period_match_condition)
                            .arel
                            .exists
  end

  scope :due_for_payment, ->(buffer_hours: 24) {
    active
      .where("current_period_end BETWEEN ? AND ?",
        Time.current.beginning_of_day,
        (Time.current.end_of_day + buffer_hours.hours))
      .where.not(Subscription.without_invoice_for_current_period)
  }

  scope :with_latest_invoice, ->(status) {
    joins(:latest_invoice)
      .where(invoices: { status: status })
      .distinct
  }

  aasm timestamps:           true,
       no_direct_assignment: true,
       column:               :status,
       enum:                 true do
    state :active, initial: true
    state :cancelled

    event :resume do
      transitions from: :paused, to: :active do
        after do
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

  def issue_new_invoice!
    ActiveRecord::Base.transaction(isolation: :serializable) do
      invoices.create!(draft_at:             Time.current,
                       amount_total:         amount,
                       billing_period_start: current_period_start,
                       billing_period_end:   current_period_end)
    end
  end

  def next_due_date
    current_period_end.next_weekday
  end
end
