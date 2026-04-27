module Rebilling
  class DunningStrategy
    extend Dry::Initializer

    DEFAULT_MAX_ATTEMPTS = 12
    DEFAULT_RETRYABLE_FAILURE_CATEGORIES = %i[soft_decline].freeze

    option :steps, Types::Array.of(Types.Instance(RetryStep))
    option :version, Types::Coercible::Integer, default: proc { 1 }
    option :max_attempts, Types::Coercible::Integer, default: proc { DEFAULT_MAX_ATTEMPTS }
    option :retryable_failure_categories, Types::Array, default: proc { DEFAULT_RETRYABLE_FAILURE_CATEGORIES }
    option :payment_method_policy, default: proc { PaymentMethodPolicy.default }
    option :failure_classifier, default: proc { FailureClassifier.new }
    option :decision_recorder, default: proc { DecisionRecorder.new }
    # Reserved for ML score-based step ordering. Tier 1 runs in rules-only mode
    # and does not consult this policy yet.
    option :scoring_policy, default: proc { ScoringPolicy.new }

    def self.default
      build do
        step 75, delay: 1.day
        step 50, delay: 1.day
        step 25, delay: 5.minutes, on_success: :next
        step 25, delay: 1.minute
        step 15, delay: 5.minutes
        step 10, delay: 5.minutes
        step 5, delay: 5.minutes, on_failure: :stop
      end
    end

    def self.build(**options, &block)
      builder = Builder.new
      builder.instance_eval(&block) if block
      new(**options, steps: builder.steps)
    end

    def initialize(...)
      super
      steps.freeze
      @retryable_failure_categories = retryable_failure_categories.map(&:to_sym).freeze
      @step_by_key = build_step_index

      freeze
    end

    def next_plan(context, now: Time.current, trace: false)
      trace_entries = []
      decision = compute_decision(context, now: now, trace_entries: trace ? trace_entries : nil)
      decision_recorder.record(context, decision)
      decision
    end

    private

    attr_reader :step_by_key

    def compute_decision(context, now:, trace_entries:)
      return terminal_decision(build_outcome(:invoice_paid, :invoice_already_paid), context, trace_entries) if context.paid?
      return terminal_decision(build_outcome(:not_retryable, :invoice_not_retryable), context, trace_entries) unless context.retryable_invoice?
      return terminal_decision(build_outcome(:subscription_inactive, :subscription_not_active), context, trace_entries) unless context.active_subscription?
      return terminal_decision(build_outcome(:in_flight_attempt_exists, :in_flight_attempt_exists), context, trace_entries) if context.in_flight_attempt?

      last_attempt = context.latest_terminal_attempt
      return terminal_decision(build_outcome(:not_retryable, :no_terminal_attempt), context, trace_entries) unless last_attempt
      return terminal_decision(build_outcome(:exhausted, :max_attempts_reached), context, trace_entries, last_attempt) if last_attempt.attempt_number >= max_attempts
      return terminal_decision(build_outcome(:not_retryable, :unknown_step_key), context, trace_entries, last_attempt) if unknown_retry_step?(last_attempt)

      candidate_steps = candidate_steps_for(last_attempt, trace_entries)
      if candidate_steps.empty?
        return terminal_decision(empty_candidate_decision(last_attempt), context, trace_entries, last_attempt)
      end

      selected_step, selected_payment_method = select_step_and_payment_method(context, candidate_steps, last_attempt, trace_entries)
      unless selected_step && selected_payment_method
        return terminal_decision(no_method_decision(last_attempt), context, trace_entries, last_attempt)
      end

      build_scheduled_decision(context, selected_step, selected_payment_method, last_attempt, now, trace_entries)
    end

    def candidate_steps_for(last_attempt, trace_entries)
      trace_entries&.push(branch: :candidate_steps, last_attempt_id: last_attempt.id, last_retry_step_key: last_attempt.retry_step_key)

      if last_attempt.initial?
        return [ steps.first ].compact if retryable_failure?(last_attempt)

        return []
      end

      current_step = step_by_key[last_attempt.retry_step_key]
      return [] unless current_step

      if last_attempt.completed?
        [ resolve_transition(current_step, current_step.on_success) ].compact
      elsif retryable_failure?(last_attempt)
        failure_candidate_steps(current_step)
      else
        []
      end
    end

    def failure_candidate_steps(current_step)
      candidates = []
      candidates << current_step if payment_method_policy.exhaust_methods_per_step?
      candidates << resolve_transition(current_step, current_step.on_failure)
      candidates.compact.uniq(&:key)
    end

    def select_step_and_payment_method(context, candidate_steps, last_attempt, trace_entries)
      candidate_steps.each do |candidate_step|
        preferred_payment_method_id = preferred_payment_method_id_for(last_attempt, candidate_step)
        selected_payment_method = payment_method_policy.select(context,
                                                               candidate_step,
                                                               preferred_payment_method_id: preferred_payment_method_id)

        trace_entries&.push(branch:                  :payment_method_selection,
                            candidate_step_key:      candidate_step.key,
                            preferred_payment_method_id: preferred_payment_method_id,
                            selected_payment_method_id:  selected_payment_method&.id)

        return [ candidate_step, selected_payment_method ] if selected_payment_method
      end

      [ nil, nil ]
    end

    def preferred_payment_method_id_for(last_attempt, candidate_step)
      return unless last_attempt.completed?
      return unless last_attempt.retry_step_key == candidate_step.key

      last_attempt.payment_method_id
    end

    def build_scheduled_decision(context, selected_step, selected_payment_method, last_attempt, now, trace_entries)
      amount_calculation = selected_step.amount_calculation_for(context)
      attempt_number = last_attempt.attempt_number + 1
      retry_window = selected_step.retry_window(now: now, context: context, attempt_number: attempt_number)
      plan = Plan.new(step_key:           selected_step.key,
                      payment_method_id:  selected_payment_method.id,
                      attempt_number:     attempt_number,
                      amount_cents:       amount_calculation.capped_amount_cents,
                      retry_at:           retry_window.fetch(:retry_at),
                      earliest_retry_at:  retry_window.fetch(:earliest_retry_at),
                      latest_retry_at:    retry_window.fetch(:latest_retry_at),
                      retry_strategy:     selected_step.basis,
                      idempotency_key:    idempotency_key(context, last_attempt, selected_step, selected_payment_method),
                      strategy_version:   version,
                      source_attempt_id:  last_attempt.id)

      trace_entries&.push(branch:                    :amount_calculation,
                          selected_step_key:         selected_step.key,
                          calculated_amount_cents:   amount_calculation.calculated_amount_cents,
                          capped_amount_cents:       amount_calculation.capped_amount_cents)

      Decision.from_outcome(build_outcome(:scheduled, scheduled_reason(last_attempt)),
                            plan:        plan,
                            diagnostics: diagnostics(context, last_attempt, selected_step, selected_payment_method, amount_calculation),
                            trace:       trace_entries || [])
    end

    def resolve_transition(current_step, transition)
      case transition
      when :repeat
        current_step
      when :next
        next_step_after(current_step)
      when :stop
        nil
      end
    end

    def next_step_after(current_step)
      current_index = steps.index(current_step)
      steps[current_index + 1] if current_index
    end

    def retryable_failure?(attempt)
      return false unless attempt.failed?

      classification = failure_classifier.classify_attempt(attempt)
      retryable_failure_categories.include?(classification.category) && classification.retryable
    end

    def empty_candidate_decision(attempt)
      return build_outcome(:not_retryable, :completed_initial_attempt_not_reconciled) if attempt.initial? && attempt.completed?
      return build_outcome(:not_retryable, :non_retryable_failure_reason) if attempt.initial?

      current_step = step_by_key[attempt.retry_step_key]
      return build_outcome(:exhausted, :step_chain_stopped) if attempt.completed? && current_step&.on_success == :stop
      return build_outcome(:exhausted, :no_next_step) if attempt.completed? && current_step&.on_success == :next
      return build_outcome(:exhausted, :step_chain_stopped) if attempt.failed? && current_step&.on_failure == :stop
      return build_outcome(:exhausted, :no_next_step) if attempt.failed? && current_step&.on_failure == :next && retryable_failure?(attempt)

      # Defensive fallthrough for future transitions; normal repeat/next/stop
      # control flow should resolve before this point.
      build_outcome(:not_retryable, :non_retryable_failure_reason)
    end

    def no_method_decision(attempt)
      return build_outcome(:no_eligible_payment_method, :no_eligible_payment_method) if attempt.initial?

      current_step = step_by_key[attempt.retry_step_key]
      return build_outcome(:exhausted, :step_chain_stopped) if attempt.failed? && current_step&.on_failure == :stop
      return build_outcome(:exhausted, :no_next_step) if attempt.failed? && current_step&.on_failure == :next && next_step_after(current_step).nil?

      build_outcome(:no_eligible_payment_method, :no_eligible_payment_method)
    end

    def unknown_retry_step?(attempt)
      attempt.retry_step_key.present? && !step_by_key.key?(attempt.retry_step_key)
    end

    def idempotency_key(context, last_attempt, selected_step, selected_payment_method)
      [ "rebill",
       context.invoice_id,
       last_attempt.id,
       "v#{version}",
       selected_step.key,
       selected_payment_method.id ].join(":")
    end

    def scheduled_reason(last_attempt)
      return :initial_attempt_failed if last_attempt.initial?
      return :last_step_succeeded if last_attempt.completed?

      :last_step_failed
    end

    def terminal_decision(decision_outcome, context, trace_entries, last_attempt = nil)
      trace_entries&.push(branch: :terminal_decision, status: decision_outcome.status, reason: decision_outcome.reason)

      Decision.from_outcome(decision_outcome,
                            diagnostics: diagnostics(context, last_attempt),
                            trace:       trace_entries || [])
    end

    def build_outcome(status, reason)
      DecisionOutcome.new(status: status, reason: reason)
    end

    def diagnostics(context, last_attempt = nil, selected_step = nil, selected_payment_method = nil, amount_calculation = nil)
      { invoice_id:                  context.invoice_id,
        invoice_total_cents:         context.invoice_total_cents,
        amount_paid_cents:           context.amount_paid_cents,
        amount_remaining_cents:      context.amount_remaining_cents,
        subscription_status:         context.subscription_status,
        strategy_version:            version,
        last_attempt_id:             last_attempt&.id,
        last_attempt_number:         last_attempt&.attempt_number,
        last_attempt_status:         last_attempt&.status,
        last_failure_category:       last_attempt&.failure_category,
        last_failure_reason:         last_attempt&.failure_reason,
        last_retry_step_key:         last_attempt&.retry_step_key,
        selected_step_key:           selected_step&.key,
        selected_percentage:         selected_step&.percentage,
        selected_basis:              selected_step&.basis,
        selected_payment_method_id:  selected_payment_method&.id,
        calculated_amount_cents:     amount_calculation&.calculated_amount_cents,
        capped_amount_cents:         amount_calculation&.capped_amount_cents }.compact
    end

    def build_step_index
      steps.each_with_object({}) do |step, index|
        raise ArgumentError, "duplicate retry step key: #{step.key}" if index.key?(step.key)

        index[step.key] = step
      end
    end

    class Builder
      attr_reader :steps

      def initialize
        @steps = []
      end

      def step(percentage, **options)
        steps << RetryStep.new(percentage: percentage, **options)
      end
    end
  end
end
