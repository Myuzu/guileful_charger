class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_enum :invoice_status, %i[draft open paid partially_paid not_paid]

    create_table :invoices, id: :uuid do |t|
      t.enum :status, enum_type: :invoice_status, default: :draft, null: false

      t.monetize :amount_total, currency: { present: false }, null: false
      t.monetize :amount_paid,  currency: { present: false }, null: false

      t.datetime :billing_period_start, null: false
      t.datetime :billing_period_end,   null: false

      t.datetime :next_retry_at

      t.integer :payment_attempts_count, default: 0, null: false

      # AASM status timestamps
      t.datetime :draft_at
      t.datetime :open_at
      t.datetime :paid_at
      t.datetime :partially_paid_at
      t.datetime :not_paid_at

      t.references :subscription, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
