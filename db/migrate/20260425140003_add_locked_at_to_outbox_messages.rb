class AddLockedAtToOutboxMessages < ActiveRecord::Migration[8.0]
  def change
    # Guard for databases that applied the original create_outbox_messages migration
    # before locked_at was added there. Fresh installs always hit this guard.
    return if column_exists?(:outbox_messages, :locked_at)

    add_column :outbox_messages, :locked_at, :datetime
    add_index :outbox_messages, :locked_at
  end
end
