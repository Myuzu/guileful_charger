# typed: false

# These static RBI contracts do not load application classes into RSpec.
# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleExpectations
require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe "Reviewed rebilling and Money interfaces" do
  def typecheck(source)
    root = File.expand_path("../../..", __dir__)
    interfaces = Dir[File.join(root, "sorbet/rbi/shims/*.rbi")].sort
    # Check that the typed Money overlay wins over Tapioca's untyped reflection.
    interfaces.concat(Dir[File.join(root, "sorbet/rbi/gems/money@*.rbi")])
    implementations = %w[decision failure_classifier].map { |name| File.join(root, "app/services/rebilling/#{name}.rb") }
    Dir.mktmpdir("rebilling-types") do |directory|
      dependencies = File.join(directory, "dependencies.rbi")
      File.write(dependencies, <<~RBI)
        # typed: true
        module Rebilling; end
        module ActiveSupport
          class TimeWithZone; end
        end
      RBI
      probe = File.join(directory, "probe.rb")
      File.write(probe, "# typed: true\nextend T::Sig\n#{source}")
      Open3.capture2e(RbConfig.ruby, Gem.bin_path("sorbet", "srb"), "tc", "--no-config", *interfaces, *implementations, dependencies, probe, chdir: directory)
    end
  end

  let(:probe) do
    <<~RUBY
      sig { params(now: Time, zoned: ActiveSupport::TimeWithZone, money: Money, outcome: Rebilling::DecisionOutcome).void }
      def contracts(now, zoned, money, outcome)
        plan = Rebilling::Plan.new(step_key: :retry, payment_method_id: 42, attempt_number: 2,
          amount_cents: 300, retry_at: now, earliest_retry_at: now, latest_retry_at: zoned,
          retry_strategy: :invoice_total, idempotency_key: "retry:2", strategy_version: 1, source_attempt_id: nil)
        T.assert_type!(plan.amount_cents, Integer)
        T.assert_type!(plan.payment_method_id, Object)
        T.assert_type!(plan.retry_at, T.any(Time, ActiveSupport::TimeWithZone))
        T.assert_type!(plan.with(amount_cents: 100), Rebilling::Plan)
        classification = Rebilling::FailureClassification[category: :soft_decline, network_recommendation: nil,
          retryable: true, requires_credential_refresh: false, customer_action_required: false]
        T.assert_type!(classification.category, Symbol)
        T.assert_type!(classification.retryable, T::Boolean)
        T.assert_type!(Rebilling::FailureClassifier.new.classify_reason("insufficient_funds"), Rebilling::FailureClassification)
        decision = Rebilling::Decision.new(status: :scheduled, reason: :initial_attempt_failed,
          plan: plan, diagnostics: { count: 2, detail: nil }, trace: [{ branch: :limit }], notification_intent: :none)
        T.assert_type!(decision.plan, T.nilable(Rebilling::Plan))
        T.assert_type!(Rebilling::Decision.from_outcome(outcome, plan: plan), Rebilling::Decision)
        step = Rebilling::RetryStep.new(percentage: "12.5", delay: "60", jitter: "30".."60")
        T.assert_type!(step.percentage, T.any(Integer, Float))
        T.assert_type!(step.delay, Integer)
        T.assert_type!(step.jitter, T::Range[Integer])
        T.assert_type!(step.key, Symbol)
        attempt = Rebilling::Attempt.new(id: 42, attempt_number: "2", status: "failed", amount_attempted_cents: "300",
          created_at: now, failed_at: zoned, strategy_version: 1, failure_reason: "insufficient_funds")
        T.assert_type!(attempt.attempt_number, Integer)
        T.assert_type!(attempt.status, Symbol)
        T.assert_type!(attempt.failure_reason, T.nilable(Symbol))
        T.assert_type!(attempt.created_at, T.nilable(T.any(Time, ActiveSupport::TimeWithZone)))
        method = Rebilling::PaymentMethodSnapshot.new(id: nil, primary: true, last_successful_at: zoned)
        T.assert_type!(method.primary, T::Boolean)
        T.assert_type!(method.kind, T.nilable(Symbol))
        T.assert_type!(method.last_successful_at, T.nilable(T.any(Time, ActiveSupport::TimeWithZone)))
        context = Rebilling::Context.new(invoice_id: nil, invoice_status: "open", invoice_total_cents: "1200",
          amount_paid_cents: "0", subscription_status: "active", attempts: [attempt], payment_methods: [method],
          metadata: { "region" => "EU", count: 2 }, customer_timezone: "Europe/Kyiv")
        T.assert_type!(context.invoice_total_cents, Integer)
        T.assert_type!(context.attempts, T::Array[Rebilling::Attempt])
        T.assert_type!(context.payment_methods, T::Array[Rebilling::PaymentMethodSnapshot])
        T.assert_type!(context.metadata, T::Hash[Object, Object])
        calculation = Rebilling::RetryStep::AmountCalculation.new(base_cents: 1200,
          calculated_amount_cents: 300, capped_amount_cents: 300)
        T.assert_type!(calculation.capped_amount_cents, Integer)
        T.assert_type!(money.cents, T.any(Integer, BigDecimal))
        T.assert_type!(money.fractional, T.any(Integer, BigDecimal))
        # NEGATIVE_PROBES
      end
    RUBY
  end

  it "infers normalized readers and supports typed keyword Data construction and updates" do
    output, status = typecheck(probe)

    expect(status).to be_success, output
  end

  it "rejects invalid value updates and narrowing Money precision without a check" do
    source = probe.sub("# NEGATIVE_PROBES", <<~RUBY)
      plan.with(amount_cents: "100")
      classification.with(retryable: "yes")
      decision.with(plan: "not a plan")
      calculation.with(capped_amount_cents: 1.5)
      Rebilling::FailureClassifier.new.classify_reason(123)
      Rebilling::Decision.from_outcome("not an outcome")
      Rebilling::Attempt.new(id: 42, attempt_number: 2, status: :failed, amount_attempted_cents: 300,
        created_at: "yesterday", strategy_version: "v1")
      Rebilling::PaymentMethodSnapshot.new(id: "pm", primary: "true", last_failed_at: "yesterday")
      Rebilling::Context.new(invoice_id: "inv", invoice_status: :open, invoice_total_cents: 1200,
        amount_paid_cents: 0, subscription_status: :active, attempts: ["not an attempt"],
        payment_methods: ["not a method"], customer_timezone: 123)
      Rebilling::Context.new(invoice_id: "inv", invoice_status: :open, invoice_total_cents: money.cents,
        amount_paid_cents: 0, subscription_status: :active)
      Rebilling::Attempt.new(id: 42, attempt_number: 2, status: :failed, amount_attempted_cents: money.fractional)
      T.let(money.cents, Integer)
      T.let(money.fractional, Integer)
    RUBY
    source = source.sub("amount_cents: 300", 'amount_cents: "300"')
      .sub("retryable: true", 'retryable: "yes"')
      .sub("status: :scheduled", 'status: "scheduled"')
      .sub("base_cents: 1200", "base_cents: 1200.5")
    output, status = typecheck(source)

    expect(status).not_to be_success
    expect(output).to include("Errors: 21")
    expect(output).to include("argument `amount_cents`", "argument `retryable`", "argument `plan`", "argument `capped_amount_cents`", "argument `reason`", "argument `outcome`")
    expect(output).to include("T.let(money.cents, Integer)", "T.let(money.fractional, Integer)")
    expect(output).to include("argument `created_at`", "argument `strategy_version`", "argument `primary`", "argument `last_failed_at`",
      "argument `attempts`", "argument `payment_methods`", "argument `customer_timezone`")
    expect(output).to include("argument `invoice_total_cents`", "argument `amount_attempted_cents`")
  end

  it "types outcome construction from symbols or strings and composes it with the decision factory" do
    output, status = typecheck(<<~RUBY)
      class SpecializedOutcome < Rebilling::DecisionOutcome; end
      symbolic = Rebilling::DecisionOutcome.new(status: :scheduled, reason: :initial_attempt_failed)
      coerced = Rebilling::DecisionOutcome.new(status: "not_retryable", reason: "non_retryable_failure_reason")
      T.assert_type!(symbolic, Rebilling::DecisionOutcome)
      T.assert_type!(coerced.status, Symbol)
      T.assert_type!(coerced.reason, Symbol)
      T.assert_type!(Rebilling::Decision.from_outcome(coerced), Rebilling::Decision)
      T.assert_type!(SpecializedOutcome.new(status: :scheduled, reason: :initial_attempt_failed), SpecializedOutcome)
    RUBY

    expect(status).to be_success, output
  end

  it "rejects non-string/non-symbol outcome inputs statically" do
    output, status = typecheck(<<~RUBY)
      Rebilling::DecisionOutcome.new(status: 123, reason: true)
      Rebilling::DecisionOutcome.new(status: nil, reason: nil)
    RUBY

    expect(status).not_to be_success
    expect(output).to include("Errors: 4", "argument `status`", "argument `reason`")
  end

  it "requires both outcome keyword options statically" do
    output, status = typecheck(<<~RUBY)
      Rebilling::DecisionOutcome.new(status: :scheduled)
      Rebilling::DecisionOutcome.new(reason: :initial_attempt_failed)
    RUBY

    expect(status).not_to be_success
    expect(output).to include("Missing required keyword argument `reason`", "Missing required keyword argument `status`")
  end
end
