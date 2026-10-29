# typed: true

# Normalized outputs of dry-initializer options used by the typed rebilling core.
# Constructor inputs remain broad so dry-types can coerce and validate them.
class Rebilling::RetryStep
  extend T::Sig

  sig { params(percentage: Object, delay: Object, basis: Object, jitter: Object, key: Object, on_success: Object, on_failure: Object).returns(Rebilling::RetryStep) }
  def self.new(percentage:, delay:, basis: T.unsafe(nil), jitter: T.unsafe(nil), key: T.unsafe(nil), on_success: T.unsafe(nil), on_failure: T.unsafe(nil)); end

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

class Rebilling::Context
  extend T::Sig

  sig { returns(Object) }
  def invoice_id; end

  sig { returns(Integer) }
  def invoice_total_cents; end

  sig { returns(Integer) }
  def amount_remaining_cents; end
end

class Rebilling::Attempt
  extend T::Sig

  sig { returns(T.nilable(Symbol)) }
  def failure_category; end

  sig { returns(T.nilable(Symbol)) }
  def failure_reason; end
end

class Rebilling::DecisionOutcome
  extend T::Sig

  sig { returns(Symbol) }
  def status; end

  sig { returns(Symbol) }
  def reason; end
end
