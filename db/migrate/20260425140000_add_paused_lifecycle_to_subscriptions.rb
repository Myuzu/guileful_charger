class AddPausedLifecycleToSubscriptions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    execute "ALTER TYPE subscription_status ADD VALUE IF NOT EXISTS 'paused'"

    add_column :subscriptions, :paused_at, :datetime unless column_exists?(:subscriptions, :paused_at)
    add_column :subscriptions, :pause_reason, :text unless column_exists?(:subscriptions, :pause_reason)
    add_column :subscriptions, :resumed_at, :datetime unless column_exists?(:subscriptions, :resumed_at)
    add_column :subscriptions, :resume_reason, :text unless column_exists?(:subscriptions, :resume_reason)
    add_column :subscriptions, :state_version, :integer, default: 0, null: false unless column_exists?(:subscriptions, :state_version)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
