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
#  pause_reason         :text
#  paused_at            :datetime
#  resume_reason        :text
#  resumed_at           :datetime
#  state_version        :integer          default(0), not null
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

  VALID_STATUSES = %i[active paused cancelled].freeze

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
    state :paused
    state :cancelled

    event :pause, before: :record_pause_metadata do
      transitions from: :active, to: :paused
    end

    event :resume, before: :record_resume_metadata do
      transitions from: :paused, to: :active
    end

    event :cancel, before: :record_cancellation_metadata do
      transitions from: %i[active paused], to: :cancelled
    end
  end

  def billable?
    active?
  end

  def service_accessible?
    active?
  end

  def terminal?
    cancelled?
  end

  def due_for_payment_now?(buffer_hours: 24)
    active? && current_period_end.between?(Time.current.beginning_of_day,
                                           Time.current.end_of_day + buffer_hours.hours)
  end

  def invoice_for_current_period?
    invoices.exists?(billing_period_start: current_period_start,
                     billing_period_end:   current_period_end)
  end

  def issue_new_invoice!
    ActiveRecord::Base.transaction(isolation: :serializable) do
      invoices.create!(draft_at:             Time.current,
                       amount_total:         amount,
                       billing_period_start: current_period_start,
                       billing_period_end:   current_period_end)
    end
  end

  def issue_new_invoice_if_due!(buffer_hours: 24)
    invoice = nil

    self.class.transaction(isolation: :serializable) do
      lock!

      if due_for_payment_now?(buffer_hours: buffer_hours) && !invoice_for_current_period?
        invoice = invoices.create!(draft_at:             Time.current,
                                   amount_total:         amount,
                                   billing_period_start: current_period_start,
                                   billing_period_end:   current_period_end)
        enqueue_invoice_created(invoice)
      end
    end

    invoice
  end

  def next_due_date
    current_period_end.next_weekday
  end

  def lifecycle_payload(reason: nil)
    { subscription_id: id,
      customer_id:     customer_id,
      status:          status,
      reason:          reason,
      state_version:   state_version }
  end

  private

  def record_pause_metadata(reason = nil)
    self.pause_reason = reason
    increment_state_version
  end

  def record_resume_metadata(reason = nil)
    resumed_time = Time.current
    pause_duration = resumed_time - paused_at if paused_at.present?

    self.resume_reason = reason
    self.resumed_at = resumed_time
    self.current_period_end += pause_duration if pause_duration.present?
    increment_state_version
  end

  def record_cancellation_metadata(reason = nil)
    self.cancellation_reason = reason
    increment_state_version
  end

  def enqueue_invoice_created(invoice)
    OutboxMessage.enqueue!(topic:             "invoice.created",
                           payload:           invoice_created_payload(invoice),
                           aggregate:         self,
                           aggregate_version: state_version)
  end

  def invoice_created_payload(invoice)
    { invoice_id:                  invoice.id,
      subscription_id:             id,
      subscription_state_version:  state_version }
  end

  def increment_state_version
    self.state_version += 1
  end
end
