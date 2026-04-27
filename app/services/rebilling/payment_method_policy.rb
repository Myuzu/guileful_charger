module Rebilling
  class PaymentMethodPolicy
    extend Dry::Initializer

    option :order, Types::PaymentMethodOrder, default: proc { :primary_then_recent_success }
    option :exhaust_methods_per_step, Types::Bool, default: proc { true }
    option :retry_same_method_after_soft_decline, Types::Bool, default: proc { false }
    option :skip_hard_declined_methods, Types::Bool, default: proc { true }
    option :failure_classifier, default: proc { FailureClassifier.new }

    def self.default
      new
    end

    def initialize(...)
      super
      freeze
    end

    def exhaust_methods_per_step?
      exhaust_methods_per_step
    end

    def select(context, step, preferred_payment_method_id: nil)
      candidates = ordered_candidates(context, step)

      if preferred_payment_method_id
        preferred = candidates.find { |payment_method| payment_method.id == preferred_payment_method_id }
        return preferred if preferred
      end

      candidates.first
    end

    private

    def ordered_candidates(context, step)
      candidates = context.payment_methods.select(&:active?)
      candidates = reject_hard_declined_methods(context, candidates) if skip_hard_declined_methods
      candidates = reject_failed_methods_for_step(context, step, candidates) unless retry_same_method_after_soft_decline

      sort_candidates(candidates)
    end

    def reject_hard_declined_methods(context, candidates)
      hard_declined_ids = context.attempts.filter_map do |attempt|
        attempt.payment_method_id if failure_classifier.classify_attempt(attempt).category == :hard_decline
      end.uniq

      candidates.reject do |payment_method|
        payment_method.hard_declined? || hard_declined_ids.include?(payment_method.id)
      end
    end

    def reject_failed_methods_for_step(context, step, candidates)
      failed_method_ids = context.attempts_for_step(step.key).filter_map do |attempt|
        attempt.payment_method_id if attempt.failed?
      end

      candidates.reject { |payment_method| failed_method_ids.include?(payment_method.id) }
    end

    def sort_candidates(candidates)
      candidates.sort_by do |payment_method|
        [ payment_method.primary ? 0 : 1,
         payment_method.last_successful_at ? -payment_method.last_successful_at.to_i : 0,
         payment_method.id.to_s ]
      end
    end
  end
end
