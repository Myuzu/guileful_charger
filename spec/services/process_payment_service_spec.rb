require 'rails_helper'
require 'payment_gateway_api_mock'

RSpec.describe ProcessPaymentService, type: :service do
  # disable transaction nesting so that isolation level can be set in implementation
  before do
    allow(ActiveRecord::Base).to receive(:transaction).and_yield
  end

  context "with PaymentAttempt be already in processing" do
    let(:payment_attempt) { FactoryBot.build(:payment_attempt, :processing) }
    let(:payment_gateway) { PaymentGatewayApiMock.new }

    it "returns Failure[:already_in_processing] result monad" do
      payment_attempt.status = :processing
      result = described_class.call(payment_attempt, payment_gateway)

      expect(result).not_to be_success
      expect(result.failure.first).to eq :already_in_processing
    end
  end

  context "with PaymentAttempt scheduled" do
    let(:payment_attempt) { FactoryBot.create(:payment_attempt, :scheduled) }
    let(:payment_gateway) { PaymentGatewayApiMock.new }

    context "with Payment Gateway returning `success`" do
      it "returns Success result monad" do
        payment_attempt.status = :scheduled
        payment_attempt.amount_attempted_cents = 500
        result = described_class.call(payment_attempt, payment_gateway)

        expect(result).to be_success
        expect(result.success.completed?).to be(true)
      end
    end

    context "with Payment Gateway returning `insufficient_funds`" do
      it "returns Failure[:insufficient_funds] result monad" do
        payment_attempt.status = :scheduled
        payment_attempt.amount_attempted_cents = 1500
        result = described_class.call(payment_attempt, payment_gateway)

        expect(result).not_to be_success
        expect(result.failure.first).to eq :insufficient_funds
        expect(result.failure.last.failed?).to be(true)
      end
    end

    context "with Payment Gateway returning `failed`" do
      it "returns Failure[:gateway_error] result monad" do
        payment_attempt.status = :scheduled
        payment_attempt.amount_attempted_cents = 35_000
        result = described_class.call(payment_attempt, payment_gateway)

        expect(result).not_to be_success
        expect(result.failure.first).to eq :gateway_error
        expect(result.failure.last.failed?).to be(true)
      end
    end
  end
end
