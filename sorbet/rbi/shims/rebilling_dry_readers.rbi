# typed: strict

# Reviewed dry-initializer interfaces. Coerced options accept raw inputs; typed
# monetary/counter inputs require Integer or integer String to avoid implicit
# fractional truncation. Readers describe normalized values. Uncoerced fields have input
# contracts, not added runtime validation (timestamps, timezone, snapshot arrays).

class Rebilling::RetryStep
  extend T::Sig

  sig do
    params(
      percentage: Object,
      delay: Object,
      basis: Object,
      jitter: Object,
      key: Object,
      on_success: Object,
      on_failure: Object
    ).returns(Rebilling::RetryStep)
  end
  def self.new(
    percentage:,
    delay:,
    basis: T.unsafe(nil),
    jitter: T.unsafe(nil),
    key: T.unsafe(nil),
    on_success: T.unsafe(nil),
    on_failure: T.unsafe(nil)
  ); end

  sig { returns(T.any(Integer, Float)) }
  def percentage; end

  sig { returns(Integer) }
  def delay; end

  sig { returns(Symbol) }
  def basis; end

  sig { returns(T::Range[Integer]) }
  def jitter; end

  sig { returns(Symbol) }
  def key; end

  sig { returns(Symbol) }
  def on_success; end

  sig { returns(Symbol) }
  def on_failure; end
end

class Rebilling::Attempt
  extend T::Sig

  sig do
    params(
      id: Object,
      attempt_number: T.any(Integer, String),
      status: Object,
      amount_attempted_cents: T.any(Integer, String),
      failure_reason: Object,
      failure_category: Object,
      retry_step_key: Object,
      payment_method_id: Object,
      strategy_version: T.nilable(Integer),
      created_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
      completed_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
      failed_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone))
    ).returns(Rebilling::Attempt)
  end
  def self.new(
    id:,
    attempt_number:,
    status:,
    amount_attempted_cents:,
    failure_reason: T.unsafe(nil),
    failure_category: T.unsafe(nil),
    retry_step_key: T.unsafe(nil),
    payment_method_id: T.unsafe(nil),
    strategy_version: T.unsafe(nil),
    created_at: T.unsafe(nil),
    completed_at: T.unsafe(nil),
    failed_at: T.unsafe(nil)
  ); end

  sig { returns(Object) }
  def id; end

  sig { returns(Integer) }
  def attempt_number; end

  sig { returns(Symbol) }
  def status; end

  sig { returns(Integer) }
  def amount_attempted_cents; end

  sig { returns(T.nilable(Symbol)) }
  def failure_reason; end

  sig { returns(T.nilable(Symbol)) }
  def failure_category; end

  sig { returns(T.nilable(Symbol)) }
  def retry_step_key; end

  sig { returns(Object) }
  def payment_method_id; end

  sig { returns(T.nilable(Integer)) }
  def strategy_version; end

  sig { returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone))) }
  def created_at; end

  sig { returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone))) }
  def completed_at; end

  sig { returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone))) }
  def failed_at; end
end

class Rebilling::Context
  extend T::Sig

  sig do
    params(
      invoice_id: Object,
      invoice_status: Object,
      invoice_total_cents: T.any(Integer, String),
      amount_paid_cents: T.any(Integer, String),
      subscription_status: Object,
      attempts: T::Array[Rebilling::Attempt],
      payment_methods: T::Array[Rebilling::PaymentMethodSnapshot],
      customer_timezone: T.nilable(String),
      metadata: T::Hash[Object, Object]
    ).returns(Rebilling::Context)
  end
  def self.new(
    invoice_id:,
    invoice_status:,
    invoice_total_cents:,
    amount_paid_cents:,
    subscription_status:,
    attempts: T.unsafe(nil),
    payment_methods: T.unsafe(nil),
    customer_timezone: T.unsafe(nil),
    metadata: T.unsafe(nil)
  ); end

  sig { returns(Object) }
  def invoice_id; end

  sig { returns(Symbol) }
  def invoice_status; end

  sig { returns(Integer) }
  def invoice_total_cents; end

  sig { returns(Integer) }
  def amount_paid_cents; end

  sig { returns(Symbol) }
  def subscription_status; end

  sig { returns(T::Array[Rebilling::Attempt]) }
  def attempts; end

  sig { returns(T::Array[Rebilling::PaymentMethodSnapshot]) }
  def payment_methods; end

  sig { returns(T.nilable(String)) }
  def customer_timezone; end

  sig { returns(T::Hash[Object, Object]) }
  def metadata; end
end

class Rebilling::PaymentMethodSnapshot
  extend T::Sig

  sig do
    params(
      id: Object,
      status: Object,
      primary: T::Boolean,
      kind: Object,
      tokenization_kind: Object,
      last_successful_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
      last_failed_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
      failure_category: Object
    ).returns(Rebilling::PaymentMethodSnapshot)
  end
  def self.new(
    id:,
    status: T.unsafe(nil),
    primary: T.unsafe(nil),
    kind: T.unsafe(nil),
    tokenization_kind: T.unsafe(nil),
    last_successful_at: T.unsafe(nil),
    last_failed_at: T.unsafe(nil),
    failure_category: T.unsafe(nil)
  ); end

  sig { returns(Object) }
  def id; end

  sig { returns(Symbol) }
  def status; end

  sig { returns(T::Boolean) }
  def primary; end

  sig { returns(T.nilable(Symbol)) }
  def kind; end

  sig { returns(T.nilable(Symbol)) }
  def tokenization_kind; end

  sig { returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone))) }
  def last_successful_at; end

  sig { returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone))) }
  def last_failed_at; end

  sig { returns(T.nilable(Symbol)) }
  def failure_category; end
end

class Rebilling::PaymentMethodPolicy
  extend T::Sig

  sig do
    params(
      order: Object,
      exhaust_methods_per_step: T::Boolean,
      retry_same_method_after_soft_decline: T::Boolean,
      skip_hard_declined_methods: T::Boolean,
      failure_classifier: Rebilling::FailureClassifierContract
    ).returns(T.attached_class)
  end
  def self.new(
    order: T.unsafe(nil),
    exhaust_methods_per_step: T.unsafe(nil),
    retry_same_method_after_soft_decline: T.unsafe(nil),
    skip_hard_declined_methods: T.unsafe(nil),
    failure_classifier: T.unsafe(nil)
  ); end

  sig { returns(Symbol) }
  def order; end

  sig { returns(T::Boolean) }
  def exhaust_methods_per_step; end

  sig { returns(T::Boolean) }
  def retry_same_method_after_soft_decline; end

  sig { returns(T::Boolean) }
  def skip_hard_declined_methods; end

  sig { returns(Rebilling::FailureClassifierContract) }
  def failure_classifier; end
end

class Rebilling::DecisionOutcome
  extend T::Sig

  sig do
    params(status: T.any(Symbol, String), reason: T.any(Symbol, String))
      .returns(T.attached_class)
  end
  def self.new(status:, reason:); end

  sig { returns(Symbol) }
  def status; end

  sig { returns(Symbol) }
  def reason; end
end

class Rebilling::DunningStrategy
  extend T::Sig

  sig do
    params(
      steps: T::Array[Rebilling::RetryStep],
      version: T.any(Integer, String),
      max_attempts: T.any(Integer, String),
      retryable_failure_categories: T::Array[T.any(Symbol, String)],
      payment_method_policy: Rebilling::PaymentMethodPolicyContract,
      failure_classifier: Rebilling::FailureClassifierContract,
      decision_recorder: Rebilling::DecisionRecorderContract,
      scoring_policy: Object
    ).returns(T.attached_class)
  end
  def self.new(
    steps:,
    version: T.unsafe(nil),
    max_attempts: T.unsafe(nil),
    retryable_failure_categories: T.unsafe(nil),
    payment_method_policy: T.unsafe(nil),
    failure_classifier: T.unsafe(nil),
    decision_recorder: T.unsafe(nil),
    scoring_policy: T.unsafe(nil)
  ); end

  sig { returns(T::Array[Rebilling::RetryStep]) }
  def steps; end

  sig { returns(Integer) }
  def version; end

  sig { returns(Integer) }
  def max_attempts; end

  sig { returns(T::Array[Symbol]) }
  def retryable_failure_categories; end

  sig { returns(Rebilling::PaymentMethodPolicyContract) }
  def payment_method_policy; end

  sig { returns(Rebilling::FailureClassifierContract) }
  def failure_classifier; end

  sig { returns(Rebilling::DecisionRecorderContract) }
  def decision_recorder; end

  # Reserved and never consulted by the current rules-only planner.
  sig { returns(Object) }
  def scoring_policy; end
end
