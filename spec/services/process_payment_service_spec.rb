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

    before do
      payment_attempt.status = :processing
    end

    it "returns a Failure result monad" do
      result = described_class.call(payment_attempt, payment_gateway)
      expect(result).not_to be_success
    end

    it "returns :already_in_processing as the failure reason" do
      result = described_class.call(payment_attempt, payment_gateway)
      expect(result.failure.first).to eq :already_in_processing
    end
  end

  context "with PaymentAttempt scheduled" do
    let(:payment_attempt) { FactoryBot.create(:payment_attempt, :scheduled) }
    let(:payment_gateway) { PaymentGatewayApiMock.new }

    context "with Payment Gateway returning `success`" do
      before do
        payment_attempt.status = :scheduled
        payment_attempt.amount_attempted_cents = 500
      end

      it "returns Success result monad" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result).to be_success
      end

      it "marks the payment attempt as completed" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.success.completed?).to be(true)
      end

      it "sets the payment attempt status to completed" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.value!.status).to eq("completed")
      end
    end

    context "with Payment Gateway returning `insufficient_funds`" do
      before do
        payment_attempt.status = :scheduled
        payment_attempt.amount_attempted_cents = 1500
      end

      it "returns Failure[:insufficient_funds] result monad" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result).not_to be_success
      end

      it "returns :insufficient_funds as the failure reason" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.first).to eq :insufficient_funds
      end

      it "marks the payment attempt as failed" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.last.failed?).to be(true)
      end

      it "sets the payment attempt status to failed" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.last.status).to eq("failed")
      end
    end

    context "with Payment Gateway returning `system_error`" do
      before do
        payment_attempt.status = :scheduled
        payment_attempt.amount_attempted_cents = 0
      end

      it "return Failure[:system_error] result monad" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result).not_to be_success
      end

      it "returns :system_error as the failure reason" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.first).to eq :system_error
      end

      it "marks the payment attempt as failed" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.last.failed?).to be(true)
      end

      it "sets the payment attempt status to failed" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.last.status).to eq("failed")
      end
    end

    context "with Payment Gateway returning `failed`" do
      before do
        payment_attempt.status = :scheduled
        payment_attempt.amount_attempted_cents = 35_000
      end

      it "returns Failure[:gateway_error] result monad" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result).not_to be_success
      end

      it "returns :gateway_error as the failure reason" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.first).to eq :gateway_error
      end

      it "marks the payment attempt as failed" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.last.failed?).to be(true)
      end

      it "sets the payment attempt status to failed" do
        result = described_class.call(payment_attempt, payment_gateway)
        expect(result.failure.last.status).to eq("failed")
      end
    end
  end
end
