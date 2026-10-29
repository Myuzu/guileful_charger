# typed: strict

# Reviewed contracts for Data.define members. Runtime construction remains Ruby Data;
# typed callers use keyword construction and partial keyword updates.

class Rebilling::FailureClassification
  extend T::Sig

  sig do
    params(
      category: Symbol,
      network_recommendation: T.nilable(Symbol),
      retryable: T::Boolean,
      requires_credential_refresh: T::Boolean,
      customer_action_required: T::Boolean
    ).returns(T.attached_class)
  end
  def self.new(
    category:,
    network_recommendation:,
    retryable:,
    requires_credential_refresh:,
    customer_action_required:
  ); end

  sig do
    params(
      category: Symbol,
      network_recommendation: T.nilable(Symbol),
      retryable: T::Boolean,
      requires_credential_refresh: T::Boolean,
      customer_action_required: T::Boolean
    ).returns(T.attached_class)
  end
  def self.[](
    category:,
    network_recommendation:,
    retryable:,
    requires_credential_refresh:,
    customer_action_required:
  ); end

  sig do
    params(
      category: Symbol,
      network_recommendation: T.nilable(Symbol),
      retryable: T::Boolean,
      requires_credential_refresh: T::Boolean,
      customer_action_required: T::Boolean
    ).returns(T.self_type)
  end
  def with(
    category: T.unsafe(nil),
    network_recommendation: T.unsafe(nil),
    retryable: T.unsafe(nil),
    requires_credential_refresh: T.unsafe(nil),
    customer_action_required: T.unsafe(nil)
  ); end

  sig { returns(Symbol) }
  def category; end

  sig { returns(T.nilable(Symbol)) }
  def network_recommendation; end

  sig { returns(T::Boolean) }
  def retryable; end

  sig { returns(T::Boolean) }
  def requires_credential_refresh; end

  sig { returns(T::Boolean) }
  def customer_action_required; end
end

class Rebilling::Plan
  extend T::Sig

  sig do
    params(
      step_key: Symbol,
      payment_method_id: Object,
      attempt_number: Integer,
      amount_cents: Integer,
      retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      earliest_retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      latest_retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      retry_strategy: Symbol,
      idempotency_key: String,
      strategy_version: Integer,
      source_attempt_id: Object
    ).returns(T.attached_class)
  end
  def self.new(
    step_key:,
    payment_method_id:,
    attempt_number:,
    amount_cents:,
    retry_at:,
    earliest_retry_at:,
    latest_retry_at:,
    retry_strategy:,
    idempotency_key:,
    strategy_version:,
    source_attempt_id:
  ); end

  sig do
    params(
      step_key: Symbol,
      payment_method_id: Object,
      attempt_number: Integer,
      amount_cents: Integer,
      retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      earliest_retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      latest_retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      retry_strategy: Symbol,
      idempotency_key: String,
      strategy_version: Integer,
      source_attempt_id: Object
    ).returns(T.attached_class)
  end
  def self.[](
    step_key:,
    payment_method_id:,
    attempt_number:,
    amount_cents:,
    retry_at:,
    earliest_retry_at:,
    latest_retry_at:,
    retry_strategy:,
    idempotency_key:,
    strategy_version:,
    source_attempt_id:
  ); end

  sig do
    params(
      step_key: Symbol,
      payment_method_id: Object,
      attempt_number: Integer,
      amount_cents: Integer,
      retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      earliest_retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      latest_retry_at: T.any(Time, ActiveSupport::TimeWithZone),
      retry_strategy: Symbol,
      idempotency_key: String,
      strategy_version: Integer,
      source_attempt_id: Object
    ).returns(T.self_type)
  end
  def with(
    step_key: T.unsafe(nil),
    payment_method_id: T.unsafe(nil),
    attempt_number: T.unsafe(nil),
    amount_cents: T.unsafe(nil),
    retry_at: T.unsafe(nil),
    earliest_retry_at: T.unsafe(nil),
    latest_retry_at: T.unsafe(nil),
    retry_strategy: T.unsafe(nil),
    idempotency_key: T.unsafe(nil),
    strategy_version: T.unsafe(nil),
    source_attempt_id: T.unsafe(nil)
  ); end

  sig { returns(Symbol) }
  def step_key; end

  sig { returns(Object) }
  def payment_method_id; end

  sig { returns(Integer) }
  def attempt_number; end

  sig { returns(Integer) }
  def amount_cents; end

  sig { returns(T.any(Time, ActiveSupport::TimeWithZone)) }
  def retry_at; end

  sig { returns(T.any(Time, ActiveSupport::TimeWithZone)) }
  def earliest_retry_at; end

  sig { returns(T.any(Time, ActiveSupport::TimeWithZone)) }
  def latest_retry_at; end

  sig { returns(Symbol) }
  def retry_strategy; end

  sig { returns(String) }
  def idempotency_key; end

  sig { returns(Integer) }
  def strategy_version; end

  sig { returns(Object) }
  def source_attempt_id; end
end

class Rebilling::Decision
  extend T::Sig

  sig do
    params(
      status: Symbol,
      reason: Symbol,
      plan: T.nilable(Rebilling::Plan),
      diagnostics: T::Hash[Symbol, Object],
      trace: T::Array[T::Hash[Symbol, Object]],
      notification_intent: Symbol
    ).returns(T.attached_class)
  end
  def self.new(status:, reason:, plan:, diagnostics:, trace:, notification_intent:); end

  sig do
    params(
      status: Symbol,
      reason: Symbol,
      plan: T.nilable(Rebilling::Plan),
      diagnostics: T::Hash[Symbol, Object],
      trace: T::Array[T::Hash[Symbol, Object]],
      notification_intent: Symbol
    ).returns(T.attached_class)
  end
  def self.[](status:, reason:, plan:, diagnostics:, trace:, notification_intent:); end

  sig do
    params(
      status: Symbol,
      reason: Symbol,
      plan: T.nilable(Rebilling::Plan),
      diagnostics: T::Hash[Symbol, Object],
      trace: T::Array[T::Hash[Symbol, Object]],
      notification_intent: Symbol
    ).returns(T.self_type)
  end
  def with(
    status: T.unsafe(nil),
    reason: T.unsafe(nil),
    plan: T.unsafe(nil),
    diagnostics: T.unsafe(nil),
    trace: T.unsafe(nil),
    notification_intent: T.unsafe(nil)
  ); end

  sig { returns(Symbol) }
  def status; end

  sig { returns(Symbol) }
  def reason; end

  sig { returns(T.nilable(Rebilling::Plan)) }
  def plan; end

  sig { returns(T::Hash[Symbol, Object]) }
  def diagnostics; end

  sig { returns(T::Array[T::Hash[Symbol, Object]]) }
  def trace; end

  sig { returns(Symbol) }
  def notification_intent; end
end

class Rebilling::RetryStep::AmountCalculation
  extend T::Sig

  sig do
    params(
      base_cents: Integer,
      calculated_amount_cents: Integer,
      capped_amount_cents: Integer
    ).returns(T.attached_class)
  end
  def self.new(base_cents:, calculated_amount_cents:, capped_amount_cents:); end

  sig do
    params(
      base_cents: Integer,
      calculated_amount_cents: Integer,
      capped_amount_cents: Integer
    ).returns(T.attached_class)
  end
  def self.[](base_cents:, calculated_amount_cents:, capped_amount_cents:); end

  sig do
    params(
      base_cents: Integer,
      calculated_amount_cents: Integer,
      capped_amount_cents: Integer
    ).returns(T.self_type)
  end
  def with(
    base_cents: T.unsafe(nil),
    calculated_amount_cents: T.unsafe(nil),
    capped_amount_cents: T.unsafe(nil)
  ); end

  sig { returns(Integer) }
  def base_cents; end

  sig { returns(Integer) }
  def calculated_amount_cents; end

  sig { returns(Integer) }
  def capped_amount_cents; end
end
