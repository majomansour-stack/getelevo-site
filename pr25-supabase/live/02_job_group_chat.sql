-- ============================================================
-- ELEVO — group chat for each repair job.
--
-- Run this on live AFTER supabase/live/01_live_security_fixes.sql.
-- One transaction. Safe to run again. Adds columns and tables only.
--
-- A job thread is a messages row with maintenance_request_id set and
-- receiver_id null. unit_id stays text, matching live.
--
-- Who is in the thread is snapshotted in job_chat_participants when a
-- vendor login (vendor_user_id) is saved on the request:
--   the request's landlord, the request's tenant, and that vendor.
-- A later tenant of the unit is not added. Admins are not added.
--
-- Reassigning the vendor sets left_at on the old vendor. They can still
-- read messages from while they were in the thread (the same idea as a
-- 1:1 message you already sent or received). They cannot read or post
-- anything sent after they left. The new vendor sees messages from when
-- they joined, not the previous vendor's part of the thread.
--
-- resolved, closed, and completed make the thread read-only.
--
-- 1:1 policies from 01 are replaced so a job row is not treated as a
-- unit-wide landlord message, and a 1:1 insert cannot set a job id.
-- Job rows use their own policies. The two WITH CHECK expressions are
-- OR'd, so each one only has to accept its own rows.
-- ============================================================

BEGIN;

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS maintenance_request_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'messages_maintenance_request_id_fkey'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_maintenance_request_id_fkey
      FOREIGN KEY (maintenance_request_id)
      REFERENCES public.maintenance_requests (id)
      ON DELETE CASCADE;
  END IF;
END $$;

-- Live requires receiver_id. Job rows are the only messages with no receiver.
ALTER TABLE public.messages ALTER COLUMN receiver_id DROP NOT NULL;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_receiver_id_job_or_person;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_receiver_id_job_or_person
  CHECK (
    receiver_id IS NOT NULL
    OR maintenance_request_id IS NOT NULL
  );

CREATE TABLE IF NOT EXISTS public.job_chat_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  maintenance_request_id uuid NOT NULL REFERENCES public.maintenance_requests (id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  participant_role text NOT NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.job_chat_reads (
  message_id uuid NOT NULL REFERENCES public.messages (id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS job_chat_participants_one_active
  ON public.job_chat_participants (maintenance_request_id, user_id)
  WHERE left_at IS NULL;

ALTER TABLE public.job_chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_chat_reads ENABLE ROW LEVEL SECURITY;

-- ── helpers ──

CREATE OR REPLACE FUNCTION public.job_chat_is_closed(p_request uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT lower(btrim(status)) IN ('resolved', 'closed', 'completed')
    FROM public.maintenance_requests
    WHERE id = p_request
  ), false);
$$;

CREATE OR REPLACE FUNCTION public.job_chat_can_read(p_request uuid, p_at timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND p_request IS NOT NULL
    AND p_at IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.job_chat_participants p
      WHERE p.maintenance_request_id = p_request
        AND p.user_id = auth.uid()
        AND p.joined_at <= p_at
        AND (p.left_at IS NULL OR p_at < p.left_at)
    );
$$;

CREATE OR REPLACE FUNCTION public.job_chat_can_post(p_request uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND p_request IS NOT NULL
    AND NOT public.job_chat_is_closed(p_request)
    AND EXISTS (
      SELECT 1
      FROM public.job_chat_participants p
      WHERE p.maintenance_request_id = p_request
        AND p.user_id = auth.uid()
        AND p.left_at IS NULL
    );
$$;

-- True when the signed-in person has ever been in this job thread.
-- Security definer so a participants policy can call it without
-- reading job_chat_participants under its own row policy.
CREATE OR REPLACE FUNCTION public.job_chat_viewer_is_member(p_request uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND p_request IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.job_chat_participants p
      WHERE p.maintenance_request_id = p_request
        AND p.user_id = auth.uid()
    );
$$;

-- Names for the header. Only someone still in the thread can call it.
-- This does not widen the users table policies.
CREATE OR REPLACE FUNCTION public.job_chat_directory(p_request uuid)
RETURNS TABLE (
  user_id uuid,
  full_name text,
  participant_role text,
  active boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.user_id,
         COALESCE(u.full_name, ''),
         p.participant_role,
         p.left_at IS NULL
  FROM public.job_chat_participants p
  LEFT JOIN public.users u ON u.id = p.user_id
  WHERE p.maintenance_request_id = p_request
    AND p.left_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.job_chat_participants me
      WHERE me.maintenance_request_id = p_request
        AND me.user_id = auth.uid()
        AND me.left_at IS NULL
    )
  ORDER BY p.joined_at;
$$;

CREATE OR REPLACE FUNCTION public.sync_job_chat_participants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.vendor_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.landlord_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants
    WHERE maintenance_request_id = NEW.id
      AND user_id = NEW.landlord_id
      AND left_at IS NULL
  ) AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants
    WHERE maintenance_request_id = NEW.id
      AND participant_role = 'landlord'
  ) THEN
    INSERT INTO public.job_chat_participants (
      maintenance_request_id, user_id, participant_role
    ) VALUES (NEW.id, NEW.landlord_id, 'landlord');
  END IF;

  IF NEW.tenant_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants
    WHERE maintenance_request_id = NEW.id
      AND participant_role = 'tenant'
  ) AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants
    WHERE maintenance_request_id = NEW.id
      AND user_id = NEW.tenant_id
      AND left_at IS NULL
  ) THEN
    INSERT INTO public.job_chat_participants (
      maintenance_request_id, user_id, participant_role
    ) VALUES (NEW.id, NEW.tenant_id, 'tenant');
  END IF;

  UPDATE public.job_chat_participants
     SET left_at = now()
   WHERE maintenance_request_id = NEW.id
     AND participant_role = 'vendor'
     AND left_at IS NULL
     AND user_id IS DISTINCT FROM NEW.vendor_user_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants
    WHERE maintenance_request_id = NEW.id
      AND user_id = NEW.vendor_user_id
      AND left_at IS NULL
  ) THEN
    INSERT INTO public.job_chat_participants (
      maintenance_request_id, user_id, participant_role
    ) VALUES (NEW.id, NEW.vendor_user_id, 'vendor');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS maintenance_requests_sync_job_chat ON public.maintenance_requests;
CREATE TRIGGER maintenance_requests_sync_job_chat
  AFTER INSERT OR UPDATE OF vendor_user_id, landlord_id, tenant_id
  ON public.maintenance_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_job_chat_participants();

-- Moving out ends posting in open job chats on that unit. Messages from
-- before the move stay readable, the same as a replaced vendor.
CREATE OR REPLACE FUNCTION public.job_chat_tenant_moved_out()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.tenant_id IS NOT NULL
     AND OLD.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
    UPDATE public.job_chat_participants p
       SET left_at = now()
      FROM public.maintenance_requests mr
     WHERE p.maintenance_request_id = mr.id
       AND mr.unit_id = NEW.id
       AND p.user_id = OLD.tenant_id
       AND p.participant_role = 'tenant'
       AND p.left_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS units_job_chat_tenant_moved_out ON public.units;
CREATE TRIGGER units_job_chat_tenant_moved_out
  AFTER UPDATE OF tenant_id ON public.units
  FOR EACH ROW
  EXECUTE FUNCTION public.job_chat_tenant_moved_out();

-- Jobs that already have a vendor login, from before this script.
INSERT INTO public.job_chat_participants (maintenance_request_id, user_id, participant_role)
SELECT mr.id, mr.landlord_id, 'landlord'
FROM public.maintenance_requests mr
WHERE mr.vendor_user_id IS NOT NULL
  AND mr.landlord_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants p
    WHERE p.maintenance_request_id = mr.id AND p.participant_role = 'landlord'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants p
    WHERE p.maintenance_request_id = mr.id
      AND p.user_id = mr.landlord_id AND p.left_at IS NULL
  );

INSERT INTO public.job_chat_participants (maintenance_request_id, user_id, participant_role)
SELECT mr.id, mr.tenant_id, 'tenant'
FROM public.maintenance_requests mr
WHERE mr.vendor_user_id IS NOT NULL
  AND mr.tenant_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants p
    WHERE p.maintenance_request_id = mr.id AND p.participant_role = 'tenant'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants p
    WHERE p.maintenance_request_id = mr.id
      AND p.user_id = mr.tenant_id AND p.left_at IS NULL
  );

INSERT INTO public.job_chat_participants (maintenance_request_id, user_id, participant_role)
SELECT mr.id, mr.vendor_user_id, 'vendor'
FROM public.maintenance_requests mr
WHERE mr.vendor_user_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.job_chat_participants p
    WHERE p.maintenance_request_id = mr.id
      AND p.user_id = mr.vendor_user_id
      AND p.left_at IS NULL
  );

-- A tenant who moved out before this script ran is no longer the unit's
-- tenant. Record that departure once. They keep messages from before
-- they left and can no longer post. A later run does not move left_at.
UPDATE public.job_chat_participants p
   SET left_at = COALESCE(
     u.tenant_since,
     u.lease_start::timestamptz,
     u.created_at,
     now()
   )
  FROM public.maintenance_requests mr
  LEFT JOIN public.units u ON u.id = mr.unit_id
 WHERE p.maintenance_request_id = mr.id
   AND p.participant_role = 'tenant'
   AND p.left_at IS NULL
   AND p.user_id IS DISTINCT FROM u.tenant_id;

-- ── messages: keep 1:1 rows and job rows on separate rules ──
-- The landlord-of-the-unit read from 01 must not cover job rows, or a
-- later landlord of the same unit could read the repair thread.
-- can_send_unit_message rejects a null receiver, so the 1:1 insert rule
-- does not accept a job row. The job insert rule does not accept a 1:1 row.

DROP POLICY IF EXISTS "messages: participants read" ON public.messages;
CREATE POLICY "messages: participants read"
  ON public.messages
  FOR SELECT
  TO authenticated
  USING (
    (
      maintenance_request_id IS NULL
      AND (
        sender_id = auth.uid()::text
        OR receiver_id = auth.uid()::text
        OR unit_id IN (
          SELECT u.id::text
          FROM public.units u
          WHERE u.landlord_id = auth.uid()
        )
        OR (
          (messages.receiver_id IS NULL OR btrim(messages.receiver_id) = '')
          AND EXISTS (
            SELECT 1
            FROM public.units u
            WHERE u.id::text = messages.unit_id
              AND u.tenant_id = auth.uid()
              AND messages.created_at IS NOT NULL
              AND messages.created_at >= COALESCE(
                u.tenant_since, u.lease_start::timestamptz, u.created_at
              )
          )
        )
      )
    )
    OR (
      messages.maintenance_request_id IS NOT NULL
      AND public.job_chat_can_read(
        messages.maintenance_request_id, messages.created_at
      )
    )
  );

DROP POLICY IF EXISTS "messages: send as self" ON public.messages;
CREATE POLICY "messages: send as self"
  ON public.messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    maintenance_request_id IS NULL
    AND public.can_send_unit_message(unit_id, sender_id, receiver_id)
  );

DROP POLICY IF EXISTS "messages: send job chat" ON public.messages;
CREATE POLICY "messages: send job chat"
  ON public.messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    maintenance_request_id IS NOT NULL
    AND receiver_id IS NULL
    AND sender_id = auth.uid()::text
    AND public.job_chat_can_post(maintenance_request_id)
    AND unit_id = (
      SELECT mr.unit_id::text
      FROM public.maintenance_requests mr
      WHERE mr.id = maintenance_request_id
    )
  );

DROP POLICY IF EXISTS "messages: receiver marks read" ON public.messages;
CREATE POLICY "messages: receiver marks read"
  ON public.messages
  FOR UPDATE
  TO authenticated
  USING (
    maintenance_request_id IS NULL
    AND receiver_id = auth.uid()::text
  )
  WITH CHECK (
    maintenance_request_id IS NULL
    AND receiver_id = auth.uid()::text
  );

-- Read receipts are per person. Job message rows themselves are not updated.
DROP POLICY IF EXISTS "job_chat_reads: own" ON public.job_chat_reads;
CREATE POLICY "job_chat_reads: own"
  ON public.job_chat_reads
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.messages m
      WHERE m.id = message_id
        AND m.maintenance_request_id IS NOT NULL
        AND public.job_chat_can_read(m.maintenance_request_id, m.created_at)
    )
  );

DROP POLICY IF EXISTS "job_chat_reads: mark own" ON public.job_chat_reads;
CREATE POLICY "job_chat_reads: mark own"
  ON public.job_chat_reads
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.messages m
      WHERE m.id = message_id
        AND m.maintenance_request_id IS NOT NULL
        AND public.job_chat_can_read(m.maintenance_request_id, m.created_at)
    )
  );

DROP POLICY IF EXISTS "job_chat_reads: refresh own" ON public.job_chat_reads;
CREATE POLICY "job_chat_reads: refresh own"
  ON public.job_chat_reads
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.messages m
      WHERE m.id = message_id
        AND m.maintenance_request_id IS NOT NULL
        AND public.job_chat_can_read(m.maintenance_request_id, m.created_at)
    )
  );

DROP POLICY IF EXISTS "job_chat_participants: member reads" ON public.job_chat_participants;
CREATE POLICY "job_chat_participants: member reads"
  ON public.job_chat_participants
  FOR SELECT
  TO authenticated
  USING (public.job_chat_viewer_is_member(maintenance_request_id));

-- Realtime already includes messages. Add it only if a fresh database
-- has the publication and is missing the table.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'messages'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.job_chat_is_closed(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.job_chat_can_read(uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.job_chat_can_post(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.job_chat_directory(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.job_chat_viewer_is_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_job_chat_participants() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.job_chat_tenant_moved_out() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.job_chat_is_closed(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.job_chat_can_read(uuid, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.job_chat_can_post(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.job_chat_directory(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.job_chat_viewer_is_member(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sync_job_chat_participants() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.job_chat_tenant_moved_out() TO authenticated, service_role;

GRANT SELECT ON public.job_chat_participants TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON public.job_chat_reads TO authenticated, service_role;
GRANT ALL ON public.job_chat_participants TO service_role;
GRANT ALL ON public.job_chat_reads TO service_role;

COMMIT;
