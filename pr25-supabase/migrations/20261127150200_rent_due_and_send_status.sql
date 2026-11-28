-- Apply after 20261124170200_schedule_daily_emails.sql.
-- Does not schedule cron and does not touch live data by itself.

-- Rent reminders use this day of the month. Null means the 1st.
ALTER TABLE public.units
  ADD COLUMN IF NOT EXISTS rent_due_day integer;

-- The month the rent notice was for (the first of that month). Reports
-- count a confirmed payment here instead of in confirmed_at. Null rows
-- fall back to the due day and submitted_at in the app.
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS rent_period date;

-- email_send_log used to be written before the send, so a failed send
-- never retried. status = sent blocks another copy. status = failed is
-- retried on the next run. Rows already in the table were claimed as
-- sent and stay sent.
ALTER TABLE public.email_send_log
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'sent';
