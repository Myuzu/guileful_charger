# typed: strict

# Money 7 returns BigDecimal when default_infinite_precision is enabled, even
# for a whole minor-unit amount. Do not narrow these gem-wide methods to Integer.
class Money
  extend T::Sig

  sig { returns(T.any(Integer, BigDecimal)) }
  def cents; end

  sig { returns(T.any(Integer, BigDecimal)) }
  def fractional; end
end
