class UpdatePostgresqlExtensions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER EXTENSION pg_partman UPDATE;

      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
          ALTER EXTENSION pg_cron UPDATE;
        END IF;
      END
      $$;

      UPDATE partman.part_config
      SET infinite_time_partitions = true
      WHERE parent_table = 'public.outbox_messages_published';
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "PostgreSQL extensions cannot be safely downgraded"
  end
end
