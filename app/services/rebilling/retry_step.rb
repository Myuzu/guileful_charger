require "zlib"

module Rebilling
  class RetryStep
    extend Dry::Initializer

    AmountCalculation = Data.define(:base_cents, :calculated_amount_cents, :capped_amount_cents)

    option :percentage, Types::Percentage
    option :delay, Types::Seconds
    option :basis, Types::Basis, default: proc { :invoice_total }
    option :jitter, Types::JitterRange, default: proc { 0..0 }
    option :key, Types::Nil | Types::Coercible::Symbol, optional: true
    option :on_success, Types::Transition, default: proc { :repeat }
    option :on_failure, Types::Transition, default: proc { :next }

    def initialize(...)
      super
      @key = generated_key if @key.equal?(Dry::Initializer::UNDEFINED) || @key.nil? || @key.to_s.empty?

      freeze
    rescue Dry::Types::CoercionError, Dry::Types::ConstraintError => e
      raise ArgumentError, e.message
    end

    def delay_seconds
      delay
    end

    def jitter_seconds_range
      jitter
    end

    def amount_for(context)
      amount_calculation_for(context).capped_amount_cents
    end

    def amount_calculation_for(context)
      base_cents = amount_basis_for(context)
      calculated_amount_cents = ((base_cents * percentage.to_f) / 100).ceil
      capped_amount_cents = [ calculated_amount_cents, context.amount_remaining_cents ].min

      AmountCalculation.new(base_cents:              base_cents,
                            calculated_amount_cents: calculated_amount_cents,
                            capped_amount_cents:     capped_amount_cents)
    end

    def retry_window(now:, context:, attempt_number:)
      base_retry_at = now + delay_seconds.seconds
      earliest_retry_at = base_retry_at + min_jitter_seconds.seconds
      latest_retry_at = base_retry_at + max_jitter_seconds.seconds
      retry_at = base_retry_at + deterministic_jitter_seconds(context, attempt_number).seconds

      { retry_at:           retry_at,
        earliest_retry_at:  earliest_retry_at,
        latest_retry_at:    latest_retry_at }
    end

    def deterministic_jitter_seconds(context, attempt_number)
      return 0 if max_jitter_seconds.zero?

      jitter_span = max_jitter_seconds - min_jitter_seconds
      min_jitter_seconds + (Zlib.crc32("#{context.invoice_id}:#{attempt_number}:#{key}") % (jitter_span + 1))
    end

    private

    def amount_basis_for(context)
      case basis
      when :invoice_total
        context.invoice_total_cents
      when :remaining_balance
        context.amount_remaining_cents
      end
    end

    def generated_key
      :"charge_#{normalized_percentage}pct_#{basis}_after_#{delay_seconds}s"
    end

    def normalized_percentage
      percentage.to_s.tr(".", "_")
    end

    def min_jitter_seconds
      jitter_seconds_range.begin
    end

    def max_jitter_seconds
      jitter_seconds_range.end
    end
  end
end
