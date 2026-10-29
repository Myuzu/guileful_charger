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
    interfaces.concat(Dir[File.join(root, "sorbet/rbi/gems/dry-initializer@*.rbi")])
    implementations = %w[
      attempt context decision decision_recorder decision_recorder_contract dunning_strategy
      failure_classifier failure_classifier_contract payment_method_policy
      payment_method_policy_contract payment_method_snapshot scoring_policy
    ].map { |name| File.join(root, "app/services/rebilling/#{name}.rb") }
    Dir.mktmpdir("rebilling-types") do |directory|
      dependencies = File.join(directory, "dependencies.rbi")
      File.write(dependencies, <<~RBI)
        # typed: strict
        module Rebilling; end
        module Rebilling::Types
          extend T::Sig
          sig { params(type: T::Module[T.anything]).returns(T.untyped) }
          def self.Instance(type); end
          PaymentMethodOrder = T.let(T.unsafe(nil), Object)
          Bool = T.let(T.unsafe(nil), Object)
          NonNegativeInteger = T.let(T.unsafe(nil), Object)
          Array = T.let(T.unsafe(nil), T.untyped)
          Hash = T.let(T.unsafe(nil), Object)
          Nil = T.let(T.unsafe(nil), T.untyped)
          module Coercible
            Integer = T.let(T.unsafe(nil), T.untyped)
            Symbol = T.let(T.unsafe(nil), T.untyped)
          end
        end
        class Integer
          extend T::Sig
          sig { returns(Object) }
          def day; end
          sig { returns(Object) }
          def minute; end
          sig { returns(Object) }
          def minutes; end
        end
        class Time
          extend T::Sig
          sig { returns(Time) }
          def self.current; end
        end
        class Object
          extend T::Sig
          sig { returns(T::Boolean) }
          def present?; end
        end
        class Rebilling::RetryStep
          extend T::Sig
          sig { params(context: Rebilling::Context).returns(Rebilling::RetryStep::AmountCalculation) }
          def amount_calculation_for(context); end
          sig do
            params(now: T.any(Time, ActiveSupport::TimeWithZone), context: Rebilling::Context, attempt_number: Integer)
              .returns(T::Hash[Symbol, T.any(Time, ActiveSupport::TimeWithZone)])
          end
          def retry_window(now:, context:, attempt_number:); end
        end
        module ActiveSupport
          class TimeWithZone
            extend T::Sig
            sig { returns(Integer) }
            def to_i; end
          end
        end
      RBI
      probe = File.join(directory, "probe.rb")
      File.write(probe, "# typed: strict\nextend T::Sig\n#{source}")
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

  it "types payment policy construction, defaults, readers, and optional selection" do
    output, status = typecheck(<<~RUBY)
      class SpecializedPaymentPolicy < Rebilling::PaymentMethodPolicy; end
      sig { params(context: Rebilling::Context, step: Rebilling::RetryStep).void }
      def choose(context, step)
        policy = Rebilling::PaymentMethodPolicy.new(order: "primary_then_recent_success", exhaust_methods_per_step: false)
        T.assert_type!(policy.order, Symbol)
        T.assert_type!(policy.exhaust_methods_per_step?, T::Boolean)
        T.assert_type!(policy.select(context, step, preferred_payment_method_id: 42), T.nilable(Rebilling::PaymentMethodSnapshot))
        T.assert_type!(SpecializedPaymentPolicy.default, SpecializedPaymentPolicy)
      end
    RUBY

    expect(status).to be_success, output
  end

  it "rejects incorrect payment policy flags and selection inputs" do
    output, status = typecheck(<<~RUBY)
      Rebilling::PaymentMethodPolicy.new(skip_hard_declined_methods: "true")
      Rebilling::PaymentMethodPolicy.default.select("not a context", "not a step")
    RUBY

    expect(status).not_to be_success
    expect(output).to include("argument `skip_hard_declined_methods`", "argument `context`", "argument `step`")
  end

  it "accepts an alternative classifier implementing the classifier contract" do
    output, status = typecheck(<<~RUBY)
      class CustomClassifier
        extend T::Sig
        include Rebilling::FailureClassifierContract
        sig { override.params(attempt: Rebilling::Attempt).returns(Rebilling::FailureClassification) }
        def classify_attempt(attempt)
          Rebilling::FailureClassification.new(category: :unknown, network_recommendation: nil,
            retryable: false, requires_credential_refresh: false, customer_action_required: false)
        end
      end
      policy = Rebilling::PaymentMethodPolicy.new(failure_classifier: CustomClassifier.new)
      T.assert_type!(policy.failure_classifier, Rebilling::FailureClassifierContract)
    RUBY

    expect(status).to be_success, output
  end

  it "rejects classifiers that do not meet the injected contract" do
    output, status = typecheck(<<~RUBY)
      class IncompleteClassifier
        include Rebilling::FailureClassifierContract
      end
      Rebilling::PaymentMethodPolicy.new(failure_classifier: Object.new)
    RUBY

    expect(status).not_to be_success
    expect(output).to include("Missing definition for abstract method", "argument `failure_classifier`")
  end

  it "types the strategy builder receiver, step results, readers, and decisions" do
    output, status = typecheck(<<~RUBY)
      class SpecializedStrategy < Rebilling::DunningStrategy; end
      configured = Rebilling::DunningStrategy.build(version: "7") do |builder|
        T.assert_type!(self, Rebilling::DunningStrategy::Builder)
        T.assert_type!(builder, Rebilling::DunningStrategy::Builder)
        T.assert_type!(step("12.5", delay: "60"), T::Array[Rebilling::RetryStep])
      end
      T.assert_type!(configured.version, Integer)
      T.assert_type!(configured.steps, T::Array[Rebilling::RetryStep])
      T.assert_type!(SpecializedStrategy.default, SpecializedStrategy)
      sig { params(strategy: Rebilling::DunningStrategy, context: Rebilling::Context).void }
      def plan(strategy, context)
        T.assert_type!(strategy.next_plan(context, now: Time.now, trace: true), Rebilling::Decision)
      end
    RUBY

    expect(status).to be_success, output
  end

  it "rejects invalid strategy steps, planning inputs, and builder calls" do
    output, status = typecheck(<<~RUBY)
      Rebilling::DunningStrategy.new(steps: ["not a step"])
      Rebilling::DunningStrategy.default.next_plan("not a context", now: "tomorrow", trace: "yes")
      Rebilling::DunningStrategy.build { unknown_builder_method }
    RUBY

    expect(status).not_to be_success
    expect(output).to include("argument `steps`", "argument `context`", "argument `now`", "argument `trace`", "unknown_builder_method")
  end

  it "types recorder hooks without narrowing ignored inputs" do
    output, status = typecheck(<<~RUBY)
      recorder = Rebilling::DecisionRecorder.new
      T.assert_type!(recorder.record(:context, :decision), NilClass)
      T.assert_type!(recorder.record_shadows(:context, :primary, [:shadow]), NilClass)
    RUBY

    expect(status).to be_success, output
  end

  it "accepts typed planner collaborators and ignores the recorder result" do
    output, status = typecheck(<<~RUBY)
      class CustomSelector
        extend T::Sig
        include Rebilling::PaymentMethodPolicyContract
        sig { override.returns(T::Boolean) }
        def exhaust_methods_per_step?; false; end
        sig do
          override(allow_incompatible: true)
            .params(context: Rebilling::Context, step: Rebilling::RetryStep, preferred_payment_method_id: Object)
            .returns(T.nilable(Rebilling::PaymentMethodSnapshot))
        end
        def select(context, step, preferred_payment_method_id: nil); nil; end
      end
      class CustomRecorder
        extend T::Sig
        include Rebilling::DecisionRecorderContract
        sig { override.params(context: Rebilling::Context, decision: Rebilling::Decision).returns(Symbol) }
        def record(context, decision); :recorded; end
      end
      strategy = Rebilling::DunningStrategy.new(steps: [], payment_method_policy: CustomSelector.new,
        failure_classifier: Rebilling::FailureClassifier.new, decision_recorder: CustomRecorder.new,
        scoring_policy: Object.new)
      T.assert_type!(strategy.payment_method_policy, Rebilling::PaymentMethodPolicyContract)
      T.assert_type!(strategy.decision_recorder, Rebilling::DecisionRecorderContract)
    RUBY

    expect(status).to be_success, output
  end

  it "rejects planner collaborators without their required interfaces" do
    output, status = typecheck(<<~RUBY)
      Rebilling::DunningStrategy.new(steps: [], payment_method_policy: Object.new,
        failure_classifier: Object.new, decision_recorder: Object.new)
    RUBY

    expect(status).not_to be_success
    expect(output).to include("Errors: 3", "argument `payment_method_policy`", "argument `failure_classifier`", "argument `decision_recorder`")
  end

  it "preserves subclass types through snapshot constructors and Data factories and updates" do
    output, status = typecheck(<<~RUBY)
      class SpecializedAttempt < Rebilling::Attempt; end
      class SpecializedContext < Rebilling::Context; end
      class SpecializedSnapshot < Rebilling::PaymentMethodSnapshot; end
      class SpecializedStep < Rebilling::RetryStep; end
      class SpecializedPlan < Rebilling::Plan; end
      class SpecializedClassification < Rebilling::FailureClassification; end
      class SpecializedDecision < Rebilling::Decision; end
      class SpecializedCalculation < Rebilling::RetryStep::AmountCalculation; end

      T.assert_type!(SpecializedAttempt.new(id: nil, attempt_number: "2", status: "failed",
        amount_attempted_cents: "300"), SpecializedAttempt)
      T.assert_type!(SpecializedContext.new(invoice_id: 42, invoice_status: "open", invoice_total_cents: "1200",
        amount_paid_cents: "0", subscription_status: "active"), SpecializedContext)
      T.assert_type!(SpecializedSnapshot.new(id: nil), SpecializedSnapshot)
      T.assert_type!(SpecializedStep.new(percentage: "12.5", delay: "60"), SpecializedStep)

      plan = SpecializedPlan.new(step_key: :retry, payment_method_id: 42, attempt_number: 2,
        amount_cents: 300, retry_at: Time.now, earliest_retry_at: Time.now, latest_retry_at: Time.now,
        retry_strategy: :invoice_total, idempotency_key: "retry:2", strategy_version: 1, source_attempt_id: nil)
      T.assert_type!(plan, SpecializedPlan)
      T.assert_type!(plan.with(amount_cents: 100), SpecializedPlan)
      classification = SpecializedClassification[category: :soft_decline, network_recommendation: nil,
        retryable: true, requires_credential_refresh: false, customer_action_required: false]
      T.assert_type!(classification, SpecializedClassification)
      T.assert_type!(classification.with(retryable: false), SpecializedClassification)
      outcome = Rebilling::DecisionOutcome.new(status: :scheduled, reason: :initial_attempt_failed)
      decision = SpecializedDecision.from_outcome(outcome, plan: plan)
      T.assert_type!(decision, SpecializedDecision)
      T.assert_type!(decision.with(notification_intent: :notify), SpecializedDecision)
      calculation = SpecializedCalculation.new(base_cents: 1200, calculated_amount_cents: 300, capped_amount_cents: 300)
      T.assert_type!(calculation, SpecializedCalculation)
      T.assert_type!(calculation.with(capped_amount_cents: 100), SpecializedCalculation)
    RUBY

    expect(status).to be_success, output
  end

  it "types placeholder scores as a symbol-to-nil map with an opaque context" do
    output, status = typecheck(<<~RUBY)
      policy = Rebilling::ScoringPolicy.new
      step = Rebilling::RetryStep.new(percentage: "25", delay: "60")
      T.assert_type!(policy.score(:context, [step]), T::Hash[Symbol, NilClass])
      T.assert_type!(policy.score(BasicObject.new, []), T::Hash[Symbol, NilClass])
    RUBY

    expect(status).to be_success, output
  end

  it "rejects invalid scoring candidates and treating placeholder results as numeric" do
    output, status = typecheck(<<~RUBY)
      sig { params(scores: T::Hash[Symbol, Float]).void }
      def numeric_scores(scores); end

      policy = Rebilling::ScoringPolicy.new
      policy.score(nil, ["not a RetryStep"])
      numeric_scores(policy.score(nil, []))
    RUBY

    expect(status).not_to be_success
    expect(output).to include("Errors: 2", "argument `candidate_steps`", "argument `scores`")
  end
end
