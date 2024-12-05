# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2024_11_28_170914) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "uuid-ossp"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "invoice_status", ["draft", "open", "paid", "partially_paid", "not_paid"]
  create_enum "payment_attempt_status", ["pending", "scheduled", "processing", "completed", "failed"]
  create_enum "payment_retry_strategy", ["initial", "remaining_balance"]
  create_enum "subscription_status", ["active", "cancelled"]

  create_table "customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "email", null: false
    t.text "billing_address", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
  end

  create_table "invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.enum "status", default: "draft", null: false, enum_type: "invoice_status"
    t.integer "amount_total_cents", default: 0, null: false
    t.integer "amount_paid_cents", default: 0, null: false
    t.datetime "billing_period_start", null: false
    t.datetime "billing_period_end", null: false
    t.datetime "next_retry_at"
    t.integer "payment_attempts_count", default: 0, null: false
    t.datetime "draft_at"
    t.datetime "open_at"
    t.datetime "paid_at"
    t.datetime "partially_paid_at"
    t.datetime "not_paid_at"
    t.uuid "subscription_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscription_id", "billing_period_start", "billing_period_end"], name: "idx_on_subscription_id_billing_period_start_billing_97b6392bf1", unique: true
    t.index ["subscription_id"], name: "index_invoices_on_subscription_id"
  end

  create_table "payment_attempts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.enum "status", default: "pending", null: false, enum_type: "payment_attempt_status"
    t.enum "retry_strategy", enum_type: "payment_retry_strategy"
    t.integer "amount_attempted_cents", default: 0, null: false
    t.integer "attempt_number", null: false
    t.text "gateway_transaction_id"
    t.text "failure_reason"
    t.jsonb "gateway_response"
    t.datetime "pending_at"
    t.datetime "processing_at"
    t.datetime "scheduled_at"
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.uuid "invoice_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "status"], name: "index_payment_attempts_on_invoice_id_and_status"
    t.index ["invoice_id"], name: "index_payment_attempts_on_invoice_id"
    t.index ["scheduled_at"], name: "index_payment_attempts_on_scheduled_at"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.enum "status", default: "active", null: false, enum_type: "subscription_status"
    t.integer "amount_cents", default: 0, null: false
    t.datetime "current_period_start", null: false
    t.datetime "current_period_end", null: false
    t.datetime "active_at"
    t.datetime "cancelled_at"
    t.text "cancellation_reason"
    t.uuid "customer_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_subscriptions_on_customer_id"
    t.index ["status", "current_period_end"], name: "index_subscriptions_on_status_and_current_period_end"
  end

  add_foreign_key "invoices", "subscriptions"
  add_foreign_key "payment_attempts", "invoices"
  add_foreign_key "subscriptions", "customers"
end
