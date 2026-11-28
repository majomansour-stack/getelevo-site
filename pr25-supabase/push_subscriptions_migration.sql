-- ============================================================
-- ELEVO — Push Notification Tables Migration
-- Run in: Supabase Dashboard → SQL Editor → New Query → Run
--
-- Creates two tables required by PushNotificationService:
--   push_subscriptions       — stores FCM device tokens per user
--   notification_preferences — stores push permission grant status
-- ============================================================

-- ── push_subscriptions ──────────────────────────────────────
-- Stores the FCM device token for each user.
-- One row per user (upserted on every login and token refresh).

CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token       text NOT NULL,
  device_platform text NOT NULL DEFAULT 'android', -- 'ios' | 'android'
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id)
);

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Users can only upsert and read their own subscription row.
CREATE POLICY "push_subscriptions: users manage own"
  ON public.push_subscriptions
  FOR ALL
  TO authenticated
  USING  (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Service role (Edge Functions) can read all tokens to send notifications.
-- (The send-push-notification Edge Function uses the service role key.)
CREATE POLICY "push_subscriptions: service role read all"
  ON public.push_subscriptions
  FOR SELECT
  TO service_role
  USING (true);

CREATE POLICY "push_subscriptions: service role delete unregistered"
  ON public.push_subscriptions
  FOR DELETE
  TO service_role
  USING (true);


-- ── notification_preferences ────────────────────────────────
-- Stores whether the user granted push notification permission.
-- One row per user (upserted after requestPermission() call).

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  push_enabled boolean NOT NULL DEFAULT false,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id)
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Users can only upsert and read their own preference row.
CREATE POLICY "notification_preferences: users manage own"
  ON public.notification_preferences
  FOR ALL
  TO authenticated
  USING  (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── Verification ────────────────────────────────────────────
SELECT t.table_name, (SELECT count(*) FROM pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename = t.table_name) AS policy_count
FROM information_schema.tables t
WHERE t.table_schema = 'public'
  AND t.table_name IN ('push_subscriptions', 'notification_preferences');
