module RebillingHelpers
  DEFAULT_INVOICE_TOTAL_CENTS = 1200
  DEFAULT_AMOUNT_ATTEMPTED_CENTS = 300
  DEFAULT_PAYMENT_METHOD_ID = "pm_primary".freeze

  def build_payment_method(id = DEFAULT_PAYMENT_METHOD_ID, **attributes)
    Rebilling::PaymentMethodSnapshot.new(id: id, **attributes)
  end

  def build_attempt(**attributes)
    defaults = { id:                     SecureRandom.uuid,
                 attempt_number:         1,
                 status:                 :failed,
                 amount_attempted_cents: DEFAULT_AMOUNT_ATTEMPTED_CENTS,
                 payment_method_id:      DEFAULT_PAYMENT_METHOD_ID }

    Rebilling::Attempt.new(**defaults.merge(attributes))
  end

  def build_context(**attributes)
    amount_paid = attributes[:amount_paid_cents] || 0
    derived_status = amount_paid.positive? ? :partially_paid : :open
    defaults = { invoice_id:           SecureRandom.uuid,
                 invoice_status:       attributes[:invoice_status] || derived_status,
                 invoice_total_cents:  DEFAULT_INVOICE_TOTAL_CENTS,
                 amount_paid_cents:    amount_paid,
                 subscription_status:  :active,
                 attempts:             [],
                 payment_methods:      [] }

    Rebilling::Context.new(**defaults.merge(attributes))
  end
end
