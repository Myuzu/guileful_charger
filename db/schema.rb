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
  create_enum "payment_attempt_status", ["pending", "in_progress", "completed", "failed"]
  create_enum "subscription_status", ["active", "cancelled", "past_due", "partially_paid"]

  create_table "customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "email", null: false
    t.text "billing_address", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
  end

  create_table "payment_attempts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.enum "status", default: "pending", null: false, enum_type: "payment_attempt_status"
    t.integer "amount_cents", default: 0, null: false
    t.integer "attempt_number", null: false
    t.text "transaction_id"
    t.text "failure_reason"
    t.datetime "paid_at"
    t.datetime "scheduled_at", null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "customer_id", null: false
    t.uuid "subscription_id", null: false
    t.index ["customer_id"], name: "index_payment_attempts_on_customer_id"
    t.index ["scheduled_at"], name: "index_payment_attempts_on_scheduled_at"
    t.index ["subscription_id", "status"], name: "index_payment_attempts_on_subscription_id_and_status"
    t.index ["subscription_id"], name: "index_payment_attempts_on_subscription_id"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.enum "status", default: "active", null: false, enum_type: "subscription_status"
    t.integer "amount_cents", default: 0, null: false
    t.datetime "current_period_start", null: false
    t.datetime "current_period_end", null: false
    t.datetime "next_payment_attempt_at"
    t.datetime "last_payment_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "customer_id", null: false
    t.index ["current_period_end"], name: "index_subscriptions_on_current_period_end"
    t.index ["customer_id"], name: "index_subscriptions_on_customer_id"
    t.index ["status", "next_payment_attempt_at"], name: "index_subscriptions_on_status_and_next_payment_attempt_at"
  end

  add_foreign_key "payment_attempts", "customers"
  add_foreign_key "payment_attempts", "subscriptions"
  add_foreign_key "subscriptions", "customers"
end
