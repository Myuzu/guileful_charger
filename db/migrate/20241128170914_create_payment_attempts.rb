class CreatePaymentAttempts < ActiveRecord::Migration[8.0]
  def change
    create_enum :payment_attempt_status, %i[pending scheduled processing completed failed]
    create_enum :payment_retry_strategy, %i[initial remaining_balance]

    create_table :payment_attempts, id: :uuid do |t|
      t.enum :status,         enum_type: :payment_attempt_status, default: :pending, null: false
      t.enum :retry_strategy, enum_type: :payment_retry_strategy

      t.monetize :amount_attempted, currency: { present: false }, null: false

      t.integer :attempt_number, null: false

      t.text :gateway_transaction_id
      t.text :failure_reason
      t.jsonb :gateway_response

      # AASM status timestamps
      t.datetime :pending_at
      t.datetime :processing_at
      t.datetime :scheduled_at
      t.datetime :completed_at
      t.datetime :failed_at

      t.references :invoice, null: false, foreign_key: true, type: :uuid

      t.timestamps

      t.index %i[invoice_id status], unique: true
      t.index :scheduled_at
    end
  end
end
