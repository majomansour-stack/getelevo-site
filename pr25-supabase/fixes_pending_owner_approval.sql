-- ============================================================
-- ELEVO — fixes that need the owner's approval before they
-- are applied to the live Supabase project.
--
-- DO NOT run this against production until the owner reviews it.
-- Safe to re-run: new policies are dropped by name first, and
-- new columns use IF NOT EXISTS.
--
-- This file does not touch auth users, existing rows, or secrets.
--
-- Practice project note (not live): a users policy must never SELECT
-- public.users itself. That is error 42P17 and breaks every login.
-- Role checks go through current_user_role() / is_admin(), which are
-- SECURITY DEFINER and skip row-level security.
-- The other users policies in this repo only compare id = auth.uid().
-- They do not query users, so they do not recurse.
-- ============================================================

-- Fresh projects do not grant the API roles access. RLS still applies.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;

-- A signed-in person may edit their own profile, but not their role.
-- Service-role edits (no auth.uid()) and admins are the exception.
CREATE OR REPLACE FUNCTION public.users_guard_role_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
      RAISE EXCEPTION 'only an admin can change an account role'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_guard_role_change ON public.users;
CREATE TRIGGER users_guard_role_change
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.users_guard_role_change();

-- Replace the open update policy so the check is visible next to the trigger.
DROP POLICY IF EXISTS "users: update own" ON public.users;
CREATE POLICY "users: update own"
  ON public.users
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ── users: RentSpree disclosure flag (app reads users, not profiles)
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS rentspree_disclosure_dismissed boolean NOT NULL DEFAULT false;

-- Landlords need a tenant's name and email to send invites, maintenance
-- updates, and announcements. Tenants need their landlord's name and phone
-- for the emergency contact card. Vendors' account ids are needed when a
-- landlord assigns a job. These policies are additive (Postgres ORs them
-- with any existing SELECT policy).
DROP POLICY IF EXISTS "users: landlord reads own tenants" ON public.users;
CREATE POLICY "users: landlord reads own tenants"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    id IN (
      SELECT u.tenant_id
      FROM public.units u
      WHERE u.landlord_id = auth.uid()
        AND u.tenant_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS "users: tenant reads own landlord" ON public.users;
CREATE POLICY "users: tenant reads own landlord"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    id IN (
      SELECT COALESCE(un.landlord_id, p.landlord_id)
      FROM public.units un
      LEFT JOIN public.properties p ON p.id = un.property_id
      WHERE un.tenant_id = auth.uid()
    )
  );

-- Do not query public.users inside this policy. Use current_user_role().
DROP POLICY IF EXISTS "users: landlord reads vendor accounts" ON public.users;
CREATE POLICY "users: landlord reads vendor accounts"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    role = 'vendor'
    AND public.current_user_role() IN ('landlord', 'admin')
  );

-- ── documents: the existing script adds insert/update/delete but no select
DROP POLICY IF EXISTS "documents: landlords select own" ON public.documents;
CREATE POLICY "documents: landlords select own"
  ON public.documents
  FOR SELECT
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND public.current_user_role() IN ('landlord', 'admin')
  );

DROP POLICY IF EXISTS "documents: tenants select own" ON public.documents;
CREATE POLICY "documents: tenants select own"
  ON public.documents
  FOR SELECT
  TO authenticated
  USING (tenant_id = auth.uid());

-- ── vault: list the items a landlord just saved
DROP POLICY IF EXISTS "vault_items: landlords select own" ON public.vault_items;
CREATE POLICY "vault_items: landlords select own"
  ON public.vault_items
  FOR SELECT
  TO authenticated
  USING (landlord_id = auth.uid());

-- The app previously wrote a column named note. The confirmed column is content.
-- Copy any legacy note values forward when that old column exists.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'vault_items'
      AND column_name = 'note'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'vault_items'
      AND column_name = 'content'
  ) THEN
    EXECUTE $sql$
      UPDATE public.vault_items
      SET content = note
      WHERE (content IS NULL OR content = '')
        AND note IS NOT NULL
    $sql$;
  END IF;
END $$;

-- ── screenings: landlords must be able to read what they create
DROP POLICY IF EXISTS "tenant_screenings: landlords select own" ON public.tenant_screenings;
CREATE POLICY "tenant_screenings: landlords select own"
  ON public.tenant_screenings
  FOR SELECT
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND public.current_user_role() IN ('landlord', 'admin')
  );

-- ── emergency contacts: tenants add and remove their own
DROP POLICY IF EXISTS "tenant_emergency_contacts: tenants insert own" ON public.tenant_emergency_contacts;
CREATE POLICY "tenant_emergency_contacts: tenants insert own"
  ON public.tenant_emergency_contacts
  FOR INSERT
  TO authenticated
  WITH CHECK (tenant_id = auth.uid());

DROP POLICY IF EXISTS "tenant_emergency_contacts: tenants update own" ON public.tenant_emergency_contacts;
CREATE POLICY "tenant_emergency_contacts: tenants update own"
  ON public.tenant_emergency_contacts
  FOR UPDATE
  TO authenticated
  USING (tenant_id = auth.uid())
  WITH CHECK (tenant_id = auth.uid());

DROP POLICY IF EXISTS "tenant_emergency_contacts: tenants delete own" ON public.tenant_emergency_contacts;
CREATE POLICY "tenant_emergency_contacts: tenants delete own"
  ON public.tenant_emergency_contacts
  FOR DELETE
  TO authenticated
  USING (tenant_id = auth.uid());

-- ── notification preferences: store the switches the screens already show
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS email_enabled boolean NOT NULL DEFAULT true;
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS sms_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS events jsonb NOT NULL DEFAULT '{}'::jsonb;

-- ── calendar: "mark complete" has to survive a reload
ALTER TABLE public.calendar_events
  ADD COLUMN IF NOT EXISTS is_completed boolean NOT NULL DEFAULT false;

-- ── maintenance: link a directory vendor to the vendor's login
ALTER TABLE public.maintenance_requests
  ADD COLUMN IF NOT EXISTS vendor_user_id uuid;

DROP POLICY IF EXISTS "maintenance_requests: vendor reads assigned" ON public.maintenance_requests;
CREATE POLICY "maintenance_requests: vendor reads assigned"
  ON public.maintenance_requests
  FOR SELECT
  TO authenticated
  USING (
    vendor_user_id = auth.uid()
    OR vendor_id = auth.uid()
    OR vendor_id IN (
      SELECT v.id FROM public.vendors v
      WHERE lower(v.email) = lower(auth.jwt() ->> 'email')
    )
  );

DROP POLICY IF EXISTS "maintenance_requests: vendor updates assigned" ON public.maintenance_requests;
CREATE POLICY "maintenance_requests: vendor updates assigned"
  ON public.maintenance_requests
  FOR UPDATE
  TO authenticated
  USING (
    vendor_user_id = auth.uid()
    OR vendor_id = auth.uid()
    OR vendor_id IN (
      SELECT v.id FROM public.vendors v
      WHERE lower(v.email) = lower(auth.jwt() ->> 'email')
    )
  )
  WITH CHECK (
    vendor_user_id = auth.uid()
    OR vendor_id = auth.uid()
    OR vendor_id IN (
      SELECT v.id FROM public.vendors v
      WHERE lower(v.email) = lower(auth.jwt() ->> 'email')
    )
  );

DROP POLICY IF EXISTS "vendors: vendor reads own directory row" ON public.vendors;
CREATE POLICY "vendors: vendor reads own directory row"
  ON public.vendors
  FOR SELECT
  TO authenticated
  USING (lower(email) = lower(auth.jwt() ->> 'email'));

-- ── photo logs: tenants upload move-in photos for their unit
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'photo_logs'
  ) THEN
    EXECUTE 'ALTER TABLE public.photo_logs ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "photo_logs: tenant manages own unit" ON public.photo_logs';
    EXECUTE $sql$
      CREATE POLICY "photo_logs: tenant manages own unit"
        ON public.photo_logs
        FOR ALL
        TO authenticated
        USING (
          unit_id IN (SELECT id FROM public.units WHERE tenant_id = auth.uid())
        )
        WITH CHECK (
          unit_id IN (SELECT id FROM public.units WHERE tenant_id = auth.uid())
        )
    $sql$;
    EXECUTE 'DROP POLICY IF EXISTS "photo_logs: landlord reads own units" ON public.photo_logs';
    EXECUTE $sql$
      CREATE POLICY "photo_logs: landlord reads own units"
        ON public.photo_logs
        FOR SELECT
        TO authenticated
        USING (
          unit_id IN (
            SELECT id FROM public.units WHERE landlord_id = auth.uid()
          )
        )
    $sql$;
  END IF;
END $$;

-- ── expenses: the reports screen was showing made-up sample expenses
CREATE TABLE IF NOT EXISTS public.expenses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id  uuid NOT NULL,
  property_id  uuid,
  description  text NOT NULL,
  amount       numeric NOT NULL,
  category     text NOT NULL,
  expense_date date NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "expenses: landlord manages own" ON public.expenses;
CREATE POLICY "expenses: landlord manages own"
  ON public.expenses
  FOR ALL
  TO authenticated
  USING (landlord_id = auth.uid())
  WITH CHECK (landlord_id = auth.uid());

-- ── vendors can read the unit and property for an assigned job.
-- Message history is not enough. A planted message must not unlock the unit.
-- SECURITY DEFINER so units policies and message policies do not call each other.
CREATE OR REPLACE FUNCTION public.vendor_assigned_to_unit(p_user uuid, p_unit uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_user IS NOT NULL AND p_unit IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.maintenance_requests mr
    WHERE mr.unit_id = p_unit
      AND (
        mr.vendor_user_id = p_user
        OR mr.vendor_id = p_user
        OR mr.vendor_id IN (
          SELECT v.id
          FROM public.vendors v
          JOIN public.users u ON lower(u.email) = lower(v.email)
          WHERE u.id = p_user
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.vendor_visible_unit_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT mr.unit_id
  FROM public.maintenance_requests mr
  WHERE mr.unit_id IS NOT NULL
    AND public.vendor_assigned_to_unit(auth.uid(), mr.unit_id);
$$;

-- Who may post on a unit, and to whom.
-- Landlord, tenant, and a vendor assigned to a job on that unit may write
-- to each other. The tenant's automated welcome (sender "system", to themselves)
-- still works. A stranger cannot post, and a message does not create access.
CREATE OR REPLACE FUNCTION public.can_send_unit_message(
  p_unit uuid,
  p_sender text,
  p_receiver text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_landlord uuid;
  v_tenant uuid;
  sender_role text;
  receiver_role text;
BEGIN
  IF uid IS NULL OR p_unit IS NULL OR p_receiver IS NULL OR btrim(p_receiver) = '' THEN
    RETURN false;
  END IF;

  SELECT landlord_id, tenant_id INTO v_landlord, v_tenant
  FROM public.units
  WHERE id = p_unit;
  IF v_landlord IS NULL THEN
    RETURN false;
  END IF;

  IF p_sender = 'system' AND p_receiver = uid::text AND v_tenant = uid THEN
    RETURN true;
  END IF;

  IF p_sender IS DISTINCT FROM uid::text THEN
    RETURN false;
  END IF;

  IF uid = v_landlord THEN
    sender_role := 'landlord';
  ELSIF v_tenant IS NOT NULL AND uid = v_tenant THEN
    sender_role := 'tenant';
  ELSIF public.vendor_assigned_to_unit(uid, p_unit) THEN
    sender_role := 'vendor';
  ELSE
    RETURN false;
  END IF;

  IF p_receiver = v_landlord::text THEN
    receiver_role := 'landlord';
  ELSIF v_tenant IS NOT NULL AND p_receiver = v_tenant::text THEN
    receiver_role := 'tenant';
  ELSIF p_receiver ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        AND public.vendor_assigned_to_unit(p_receiver::uuid, p_unit) THEN
    receiver_role := 'vendor';
  ELSE
    RETURN false;
  END IF;

  RETURN sender_role IS DISTINCT FROM receiver_role;
END;
$$;

REVOKE ALL ON FUNCTION public.vendor_visible_unit_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.vendor_visible_unit_ids() TO authenticated, service_role;

DROP POLICY IF EXISTS "units: vendor reads job units" ON public.units;
CREATE POLICY "units: vendor reads job units"
  ON public.units
  FOR SELECT
  TO authenticated
  USING (id IN (SELECT public.vendor_visible_unit_ids()));

DROP POLICY IF EXISTS "properties: vendor reads job properties" ON public.properties;
CREATE POLICY "properties: vendor reads job properties"
  ON public.properties
  FOR SELECT
  TO authenticated
  USING (
    id IN (
      SELECT un.property_id
      FROM public.units un
      WHERE un.id IN (SELECT public.vendor_visible_unit_ids())
    )
  );

-- ── tenants may claim an invite, not rewrite rent or the lease
ALTER TABLE public.units
  ADD COLUMN IF NOT EXISTS additional_deposit numeric;

CREATE OR REPLACE FUNCTION public.units_tenant_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.uid() <> OLD.landlord_id
     AND NOT public.is_admin() THEN
    IF (NEW.property_id, NEW.landlord_id, NEW.unit_number, NEW.rent_amount,
        NEW.deposit_amount, NEW.additional_deposit, NEW.lease_start,
        NEW.lease_end, NEW.invited_email)
       IS DISTINCT FROM
       (OLD.property_id, OLD.landlord_id, OLD.unit_number, OLD.rent_amount,
        OLD.deposit_amount, OLD.additional_deposit, OLD.lease_start,
        OLD.lease_end, OLD.invited_email)
       OR NEW.status NOT IN ('occupied') THEN
      RAISE EXCEPTION 'tenants may only claim their invited unit'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS units_tenant_update_guard ON public.units;
CREATE TRIGGER units_tenant_update_guard
  BEFORE UPDATE ON public.units
  FOR EACH ROW
  EXECUTE FUNCTION public.units_tenant_update_guard();

-- ── storage: owning landlord, and the tenant or vendor tied to that unit or job
-- Replaces the old rules that let every landlord read every file, and that
-- blocked a tenant from opening a lease the landlord uploaded for their unit.
CREATE OR REPLACE FUNCTION public.can_read_storage_object(bucket text, object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  parts text[];
  first_seg text;
  second_seg text;
  third_seg text;
  uid uuid := auth.uid();
  uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
BEGIN
  IF uid IS NULL OR object_name IS NULL THEN
    RETURN false;
  END IF;

  parts := storage.foldername(object_name);
  first_seg := parts[1];
  second_seg := parts[2];
  third_seg := parts[3];

  -- The uploader can always read their own folder.
  IF first_seg = uid::text THEN
    RETURN true;
  END IF;

  IF bucket = 'documents' THEN
    -- {uploader}/{unit_id}/file
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = second_seg::uuid
        AND (
          u.landlord_id = uid
          OR u.tenant_id = uid
          OR u.id IN (SELECT public.vendor_visible_unit_ids())
        )
    ) THEN
      RETURN true;
    END IF;

    -- {uploader}/chat/{unit_id}/file
    IF second_seg = 'chat' AND third_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = third_seg::uuid
        AND (
          u.landlord_id = uid
          OR u.tenant_id = uid
          OR u.id IN (SELECT public.vendor_visible_unit_ids())
        )
    ) THEN
      RETURN true;
    END IF;

    -- {uploader}/maintenance/{request_id}/file
    IF second_seg = 'maintenance' AND third_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.maintenance_requests mr
      WHERE mr.id = third_seg::uuid
        AND (
          mr.landlord_id = uid
          OR mr.tenant_id = uid
          OR mr.vendor_user_id = uid
          OR mr.vendor_id = uid
          OR mr.vendor_id IN (
            SELECT v.id FROM public.vendors v
            WHERE lower(v.email) = lower(auth.jwt() ->> 'email')
          )
        )
    ) THEN
      RETURN true;
    END IF;

    -- A documents row explicitly shared with this person.
    IF EXISTS (
      SELECT 1 FROM public.documents d
      WHERE (d.landlord_id = uid OR d.tenant_id = uid)
        AND d.file_url LIKE '%' || object_name || '%'
    ) THEN
      RETURN true;
    END IF;

  ELSIF bucket = 'photo-logs' THEN
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = second_seg::uuid
        AND (u.landlord_id = uid OR u.tenant_id = uid)
    ) THEN
      RETURN true;
    END IF;

  ELSIF bucket = 'maintenance-photos' THEN
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.maintenance_requests mr
      WHERE mr.id = second_seg::uuid
        AND (
          mr.landlord_id = uid
          OR mr.tenant_id = uid
          OR mr.vendor_user_id = uid
          OR mr.vendor_id = uid
          OR mr.vendor_id IN (
            SELECT v.id FROM public.vendors v
            WHERE lower(v.email) = lower(auth.jwt() ->> 'email')
          )
        )
    ) THEN
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.can_read_storage_object(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_read_storage_object(text, text) TO authenticated, service_role;

DROP POLICY IF EXISTS "documents: landlords read properties docs" ON storage.objects;
DROP POLICY IF EXISTS "documents: tenants read own docs" ON storage.objects;
DROP POLICY IF EXISTS "documents: read if tied to the file" ON storage.objects;
CREATE POLICY "documents: read if tied to the file"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.can_read_storage_object('documents', name)
  );

DROP POLICY IF EXISTS "photo-logs: read own unit photos" ON storage.objects;
DROP POLICY IF EXISTS "photo-logs: read if tied to the unit" ON storage.objects;
CREATE POLICY "photo-logs: read if tied to the unit"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'photo-logs'
    AND public.can_read_storage_object('photo-logs', name)
  );

DROP POLICY IF EXISTS "maintenance-photos: landlords read all" ON storage.objects;
DROP POLICY IF EXISTS "maintenance-photos: tenants read own" ON storage.objects;
DROP POLICY IF EXISTS "maintenance-photos: read if tied to the job" ON storage.objects;
CREATE POLICY "maintenance-photos: read if tied to the job"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'maintenance-photos'
    AND public.can_read_storage_object('maintenance-photos', name)
  );

-- Messages stay on the unit. The landlord can read every message on their
-- unit, including tenant-vendor notes. Everyone else sees only rows they
-- sent or received.
DROP POLICY IF EXISTS "messages: participants read" ON public.messages;
CREATE POLICY "messages: participants read"
  ON public.messages
  FOR SELECT
  TO authenticated
  USING (
    sender_id = auth.uid()::text
    OR receiver_id = auth.uid()::text
    OR unit_id IN (
      SELECT id FROM public.units WHERE landlord_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "messages: send as self" ON public.messages;
CREATE POLICY "messages: send as self"
  ON public.messages
  FOR INSERT
  TO authenticated
  WITH CHECK (public.can_send_unit_message(unit_id, sender_id, receiver_id));

DROP POLICY IF EXISTS "messages: receiver marks read" ON public.messages;
CREATE POLICY "messages: receiver marks read"
  ON public.messages
  FOR UPDATE
  TO authenticated
  USING (receiver_id = auth.uid()::text)
  WITH CHECK (receiver_id = auth.uid()::text);

-- Repeat table grants after tables created above. Do not grant execute on
-- every function: that would hand the helpers back to anonymous callers.
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;

-- Undo the earlier blanket execute grant to anonymous callers.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;
REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.users_guard_role_change() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.vendor_assigned_to_unit(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.vendor_visible_unit_ids() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_send_unit_message(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.units_tenant_update_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_read_storage_object(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.users_guard_role_change() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.vendor_assigned_to_unit(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.vendor_visible_unit_ids() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_send_unit_message(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.units_tenant_update_guard() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_read_storage_object(text, text) TO authenticated, service_role;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'vendor_applications'
  ) THEN
    EXECUTE 'GRANT INSERT ON public.vendor_applications TO anon';
  END IF;
END $$;
