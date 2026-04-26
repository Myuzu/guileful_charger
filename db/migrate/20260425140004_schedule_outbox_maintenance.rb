class ScheduleOutboxMaintenance < ActiveRecord::Migration[8.0]
  PARTMAN_JOB = "outbox_partman_maintenance".freeze
  OUTBOX_REINDEX_ID_JOB = "outbox_unpublished_id_reindex".freeze
  OUTBOX_REINDEX_LOCKED_AT_JOB = "outbox_unpublished_locked_at_reindex".freeze

  JOB_NAMES = [
    PARTMAN_JOB,
    OUTBOX_REINDEX_ID_JOB,
    OUTBOX_REINDEX_LOCKED_AT_JOB
  ].freeze

  def up
    execute <<~SQL
      DO $$
      DECLARE
        configured_cron_database text := current_setting('cron.database_name', true);
      BEGIN
        IF configured_cron_database IS NULL OR configured_cron_database = '' THEN
          RAISE NOTICE 'Skipping message pg_cron setup because cron.database_name is not configured.';
          RETURN;
        END IF;

        IF configured_cron_database <> current_database() THEN
          RAISE NOTICE 'Skipping message pg_cron setup in %, because cron.database_name is %.', current_database(), configured_cron_database;
          RETURN;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
          RAISE NOTICE 'Skipping message pg_cron setup because pg_cron is not available.';
          RETURN;
        END IF;

        CREATE EXTENSION IF NOT EXISTS pg_cron;

        PERFORM cron.unschedule(jobid)
        FROM cron.job
        WHERE jobname IN (#{quoted_job_names});

        PERFORM cron.schedule(
          '#{PARTMAN_JOB}',
          '*/15 * * * *',
          'CALL partman.run_maintenance_proc()'
        );

        PERFORM cron.schedule(
          '#{OUTBOX_REINDEX_ID_JOB}',
          '17 3 * * *',
          'REINDEX INDEX index_outbox_messages_unpublished_on_id'
        );

        PERFORM cron.schedule(
          '#{OUTBOX_REINDEX_LOCKED_AT_JOB}',
          '27 3 * * *',
          'REINDEX INDEX index_outbox_messages_unpublished_on_locked_at'
        );
      END
      $$;
    SQL
  end

  def down
    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
          PERFORM cron.unschedule(jobid)
          FROM cron.job
          WHERE jobname IN (#{quoted_job_names});
        END IF;
      END
      $$;
    SQL
  end

  private

  def quoted_job_names
    JOB_NAMES.map { |job_name| ActiveRecord::Base.connection.quote(job_name) }.join(", ")
  end
end
