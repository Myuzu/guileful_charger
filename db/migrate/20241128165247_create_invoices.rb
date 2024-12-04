class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_enum :invoice_status, %i[issued paid partially_paid past_due not_paid]

    create_table :invoices, id: :uuid do |t|
      t.enum :status, enum_type: :invoice_status, default: :issued, null: false

      t.monetize :amount_total, currency: { present: false }, null: false
      t.monetize :amount_paid,  currency: { present: false }, null: false

      t.datetime :next_retry_at

      # AASM status timestamps
      t.datetime :issued_at
      t.datetime :paid_at
      t.datetime :partially_paid_at
      t.datetime :past_due_at
      t.datetime :not_paid_at

      t.references :subscription, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
