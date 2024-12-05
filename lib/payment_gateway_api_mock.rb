class PaymentGatewayApiMock
  PaymentResponse = Struct.new(:status, :transaction_id, :message, keyword_init: true) do
    def to_h
      { status:         status,
        transaction_id: transaction_id,
        message:        message }
    end
  end

  def charge(amount:)
    case amount
    when 1..500
      PaymentResponse.new(status:         :success,
                          transaction_id: SecureRandom.uuid,
                          message:        "Payment successful")
    when 501..2000
      PaymentResponse.new(status:         :insufficient_funds,
                          transaction_id: SecureRandom.uuid,
                          message:        "Insufficient funds")
    else
      PaymentResponse.new(status:         :failed,
                          transaction_id: SecureRandom.uuid,
                          message:        "Generic gateway api error")
    end
  end
end
