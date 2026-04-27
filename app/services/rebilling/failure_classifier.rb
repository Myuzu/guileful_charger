module Rebilling
  class FailureClassifier
    RETRYABLE_REASONS = %i[insufficient_funds].freeze
    HARD_DECLINE_REASONS = %i[stolen_card lost_card invalid_card_number fraudulent gateway_error failed].freeze
    CUSTOMER_ACTION_REASONS = %i[authentication_required expired_card incorrect_cvc].freeze
    TECHNICAL_REASONS = %i[system_error network_error processor_unavailable].freeze

    def classify_attempt(attempt)
      return classification_for_category(attempt.failure_category) if attempt.failure_category

      classify_reason(attempt.failure_reason)
    end

    def classify_reason(reason)
      normalized_reason = reason&.to_sym

      category =
        if RETRYABLE_REASONS.include?(normalized_reason)
          :soft_decline
        elsif HARD_DECLINE_REASONS.include?(normalized_reason)
          :hard_decline
        elsif CUSTOMER_ACTION_REASONS.include?(normalized_reason)
          :customer_action_required
        elsif TECHNICAL_REASONS.include?(normalized_reason)
          :technical_failure
        else
          :unknown
        end

      classification_for_category(category)
    end

    private

    def classification_for_category(category)
      normalized_category = category&.to_sym || :unknown

      FailureClassification.new(category:                    normalized_category,
                                network_recommendation:      nil,
                                retryable:                   normalized_category == :soft_decline,
                                requires_credential_refresh: false,
                                customer_action_required:    normalized_category == :customer_action_required)
    end
  end
end
