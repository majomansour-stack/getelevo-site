-- Daily rent reminders and lease-expiry emails.
-- Apply on practice first, then live with a backup.
-- Does not insert a cron job until pg_cron, pg_net, and the vault secrets exist.
-- See the deploy steps at the bottom of this file.

CREATE TABLE IF NOT EXISTS public.email_send_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient text NOT NULL,
  kind text NOT NULL,
  period text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (recipient, kind, period)
);

ALTER TABLE public.email_send_log ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.email_send_log FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.email_send_log TO service_role;

-- Deploy steps (do these yourself; this file does not call the live project):
-- 1. Deploy supabase/functions/scheduled-emails. It accepts only the service-role bearer.
-- 2. Deploy supabase/functions/send-email (the scheduler calls it with the service role).
-- 3. In the SQL editor, store the secrets (replace the placeholders):
--      select vault.create_secret(
--        'https://PROJECT.supabase.co/functions/v1/scheduled-emails',
--        'elevo_scheduled_emails_url'
--      );
--      select vault.create_secret(
--        'SERVICE_ROLE_KEY',
--        'elevo_service_role_key'
--      );
-- 4. Enable the extensions if they are not already on:
--      create extension if not exists pg_cron;
--      create extension if not exists pg_net;
-- 5. Schedule 14:00 UTC (7:00am Arizona, no daylight saving):
--      select cron.schedule(
--        'elevo-daily-emails',
--        '0 14 * * *',
--        $$
--        select net.http_post(
--          url := (select decrypted_secret from vault.decrypted_secrets where name = 'elevo_scheduled_emails_url'),
--          headers := jsonb_build_object(
--            'Content-Type', 'application/json',
--            'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'elevo_service_role_key')
--          ),
--          body := '{}'::jsonb
--        ) as request_id;
--        $$
--      );
-- The function records each send in email_send_log so a second run the same day does not send again.
-- It skips a person whose notification_preferences.email_enabled is false, or whose events
-- map turns off rent_reminder, lease_90, lease_60, or lease_30.
