class CreateOutboxMessages < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE SCHEMA IF NOT EXISTS partman;
      CREATE EXTENSION IF NOT EXISTS pg_partman WITH SCHEMA partman;

      CREATE TABLE outbox_messages (
        id uuid NOT NULL DEFAULT uuidv7(),
        topic varchar NOT NULL,
        payload jsonb DEFAULT '{}'::jsonb NOT NULL,
        aggregate_type varchar,
        aggregate_id uuid,
        aggregate_version integer,
        published_at timestamptz,
        attempts integer DEFAULT 0 NOT NULL,
        last_error text,
        locked_at timestamptz,
        updated_at timestamptz NOT NULL
      ) PARTITION BY LIST (published_at);

      CREATE TABLE outbox_messages_unpublished
        PARTITION OF outbox_messages
        FOR VALUES IN (NULL);

      CREATE TABLE outbox_messages_published
        PARTITION OF outbox_messages
        DEFAULT
        PARTITION BY RANGE (published_at);

      ALTER TABLE outbox_messages_published
        ALTER COLUMN published_at SET NOT NULL;

      CREATE INDEX index_outbox_messages_unpublished_on_id
        ON outbox_messages_unpublished (id);

      CREATE INDEX index_outbox_messages_unpublished_on_locked_at
        ON outbox_messages_unpublished (locked_at);

      CREATE INDEX index_outbox_messages_unpublished_on_aggregate
        ON outbox_messages_unpublished (aggregate_type, aggregate_id);

      SELECT partman.create_parent(
        p_parent_table := 'public.outbox_messages_published',
        p_control := 'published_at',
        p_interval := '1 day',
        p_premake := 7,
        p_default_table := true
      );

      UPDATE partman.part_config
      SET retention = '7 days',
          retention_keep_table = false,
          retention_keep_index = false
      WHERE parent_table = 'public.outbox_messages_published';
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS outbox_messages CASCADE;
      DROP EXTENSION IF EXISTS pg_partman CASCADE;
      DROP SCHEMA IF EXISTS partman CASCADE;
    SQL
  end
end
