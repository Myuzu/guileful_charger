# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe ApplicationService, type: :service do
  describe "result helpers" do
    let(:subscription) { create(:subscription, :cancelled) }
    let(:payment_attempt) { create(:payment_attempt, :scheduled) }

    it "builds structured failure results" do
      service_class = Class.new(described_class) do
        def call
          failure_result(:example_error, detail: "test")
        end
      end

      result = service_class.call

      expect(result).to be_failure
      expect(result.failure).to eq([ :example_error, { detail: "test" } ])
    end

    it "builds subscription metadata" do
      service_class = Class.new(described_class) do
        param :subscription

        def call
          Success(subscription_metadata(subscription))
        end
      end

      result = service_class.call(subscription)

      expect(result).to be_success
      expect(result.value!).to eq(subscription_id: subscription.id,
                                  status:          "cancelled",
                                  state_version:   subscription.state_version)
    end

    it "builds subscription failures with extra metadata" do
      service_class = Class.new(described_class) do
        param :subscription

        def call
          subscription_failure(:already_cancelled, subscription, action: "pause")
        end
      end

      result = service_class.call(subscription)

      expect(result).to be_failure
      expect(result.failure.first).to eq(:already_cancelled)
      expect(result.failure.last).to include(subscription_id: subscription.id,
                                             status:          "cancelled",
                                             state_version:   subscription.state_version,
                                             action:          "pause")
    end

    it "keeps structured subscription metadata when extra metadata conflicts" do
      service_class = Class.new(described_class) do
        param :subscription

        def call
          subscription_failure(:already_cancelled,
                               subscription,
                               subscription_id: "wrong",
                               status:          "wrong",
                               state_version:   -1)
        end
      end

      result = service_class.call(subscription)

      expect(result.failure.last).to include(subscription_id: subscription.id,
                                             status:          "cancelled",
                                             state_version:   subscription.state_version)
    end

    it "builds payment attempt metadata without traversing to subscription" do
      service_class = Class.new(described_class) do
        param :payment_attempt

        def call
          Success(payment_attempt_metadata(payment_attempt))
        end
      end

      result = service_class.call(payment_attempt)

      expect(result).to be_success
      expect(result.value!).to eq(payment_attempt_id:     payment_attempt.id,
                                  payment_attempt_status: "scheduled",
                                  invoice_id:             payment_attempt.invoice_id)
    end

    it "builds payment attempt failures with the record and extra metadata" do
      service_class = Class.new(described_class) do
        param :payment_attempt

        def call
          payment_attempt_failure(:system_error, payment_attempt, retryable: true)
        end
      end

      result = service_class.call(payment_attempt)

      expect(result).to be_failure
      expect(result.failure.first).to eq(:system_error)
      expect(result.failure.last).to include(payment_attempt:        payment_attempt,
                                             payment_attempt_id:     payment_attempt.id,
                                             payment_attempt_status: "scheduled",
                                             invoice_id:             payment_attempt.invoice_id,
                                             retryable:              true)
    end

    it "keeps structured payment attempt metadata when extra metadata conflicts" do
      replacement_attempt = create(:payment_attempt)
      service_class = Class.new(described_class) do
        param :payment_attempt
        param :replacement_attempt

        def call
          payment_attempt_failure(:system_error,
                                  payment_attempt,
                                  payment_attempt:        replacement_attempt,
                                  payment_attempt_id:     "wrong",
                                  payment_attempt_status: "wrong",
                                  invoice_id:             "wrong")
        end
      end

      result = service_class.call(payment_attempt, replacement_attempt)

      expect(result.failure.last).to include(payment_attempt:        payment_attempt,
                                             payment_attempt_id:     payment_attempt.id,
                                             payment_attempt_status: "scheduled",
                                             invoice_id:             payment_attempt.invoice_id)
    end
  end

  describe ".input_schema" do
    let(:subscription) { create(:subscription) }

    let(:service_class) do
      Class.new(described_class) do
        option :reason, optional: true
        option :source, optional: true

        input_schema do
          optional(:reason).maybe(:string)
        end

        def call
          Success(reason: reason, source: source)
        end
      end
    end

    it "allows valid keyword input" do
      result = service_class.call(reason: "customer requested")

      expect(result).to be_success
      expect(result.value!).to eq(reason: "customer requested", source: nil)
    end

    it "preserves undeclared keyword input for Dry::Initializer options" do
      result = service_class.call(reason: "customer requested", source: "admin")

      expect(result).to be_success
      expect(result.value!).to eq(reason: "customer requested", source: "admin")
    end

    it "returns a structured invalid_input failure before service execution" do
      result = service_class.call(reason: 123)

      expect(result).to be_failure
      expect(result.failure.first).to eq(:invalid_input)
      expect(result.failure.last.fetch(:errors)).to include(:reason)
    end

    it "allows positional args with no keyword input when schema fields are optional" do
      positional_service = Class.new(described_class) do
        param :subscription

        input_schema do
          optional(:reason).maybe(:string)
        end

        def call
          Success(subscription)
        end
      end

      result = positional_service.call(subscription)

      expect(result).to be_success
      expect(result.value!).to eq(subscription)
    end
  end
end
