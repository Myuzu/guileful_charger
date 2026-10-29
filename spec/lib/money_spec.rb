# typed: false

# rubocop:disable RSpec/MultipleExpectations
require "rails_helper"

RSpec.describe Money do
  around do |example|
    original = described_class.default_infinite_precision
    example.run
  ensure
    described_class.default_infinite_precision = original
  end

  it "returns rounded Integer minor units with normal precision" do
    described_class.default_infinite_precision = false
    amount = described_class.from_cents(BigDecimal("101.5"), "UAH")

    expect(amount.cents).to eq(102)
    expect(amount.cents).to be_an(Integer)
    expect(amount.fractional).to be_an(Integer)
  end

  it "returns BigDecimal with infinite precision, including for whole minor units" do
    described_class.default_infinite_precision = true

    expect(described_class.from_cents(100, "UAH").cents).to be_a(BigDecimal)
    expect(described_class.from_cents(BigDecimal("100.5"), "UAH").fractional).to eq(BigDecimal("100.5"))
  end

  it "uses currency subunits rather than assuming every currency has 100 cents" do
    described_class.default_infinite_precision = false

    expect(described_class.from_amount(1, "UAH").fractional).to eq(100)
    expect(described_class.from_amount(1, "JPY").fractional).to eq(1)
    expect(described_class.from_amount(1, "KWD").fractional).to eq(1000)
  end

  it "keeps the integer database attribute separate from its monetized Money reader" do
    described_class.default_infinite_precision = false
    invoice = Invoice.new(amount_total_cents: 123)

    expect(invoice.amount_total_cents).to be_an(Integer)
    expect(invoice.amount_total).to be_a(described_class)
    expect(invoice.amount_total.fractional).to eq(123)
  end
end
