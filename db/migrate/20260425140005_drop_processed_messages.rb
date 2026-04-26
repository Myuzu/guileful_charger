class DropProcessedMessages < ActiveRecord::Migration[8.0]
  def change
    drop_table :processed_messages, if_exists: true
  end
end
