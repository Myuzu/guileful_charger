# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe ApplicationService, type: :service do
  describe ".input_schema" do
    let(:subscription) { FactoryBot.create(:subscription) }

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
