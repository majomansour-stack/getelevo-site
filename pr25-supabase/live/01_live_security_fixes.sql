-- ============================================================
-- ELEVO — security and additive schema fixes for the LIVE database.
--
-- Run this whole file once in the Supabase SQL editor.
-- It is one transaction. If any statement fails, nothing is kept.
-- Safe to run again.
--
-- What this does:
--   * Adds columns and tables the Flutter app already writes, and
--     keeps every existing column.
--   * Closes the old permissive policies. Postgres ORs policies, so
--     leaving an old "USING (true)" policy would keep the hole open.
--   * messages.unit_id stays text. Comparisons use units.id::text.
--   * vendor_contacts stays sender_id / listing_id / message.
--   * Makes the photo-logs bucket private. Reads are limited to the
--     uploader, the landlord who owns the unit, the tenant on that
--     unit, and a vendor assigned to a job on that unit.
--   * Does not replace auto_link_tenant_on_signup or its trigger.
--     A second trigger inserts a users (and profiles) row only when
--     one is missing, and only fills blank fields.
-- ============================================================

BEGIN;

-- ── helpers (security definer so policies do not recurse through RLS) ──

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

-- ── columns and tables the app writes that live does not have yet ──

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS rentspree_disclosure_dismissed boolean NOT NULL DEFAULT false;

ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS email_enabled boolean NOT NULL DEFAULT true;
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS sms_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS events jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.calendar_events
  ADD COLUMN IF NOT EXISTS is_completed boolean NOT NULL DEFAULT false;

ALTER TABLE public.units
  ADD COLUMN IF NOT EXISTS additional_deposit numeric;

-- When the current tenant was linked. New claims set this to now().
-- Existing occupied units keep lease_start when that column is still blank.
ALTER TABLE public.units
  ADD COLUMN IF NOT EXISTS tenant_since timestamptz;

UPDATE public.units
   SET tenant_since = COALESCE(lease_start::timestamptz, created_at)
 WHERE tenant_id IS NOT NULL
   AND tenant_since IS NULL;

ALTER TABLE public.maintenance_requests
  ADD COLUMN IF NOT EXISTS vendor_user_id uuid;
ALTER TABLE public.maintenance_requests
  ADD COLUMN IF NOT EXISTS invoice_url text;
ALTER TABLE public.maintenance_requests
  ADD COLUMN IF NOT EXISTS landlord_notes text;
ALTER TABLE public.maintenance_requests
  ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.maintenance_requests
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz;
ALTER TABLE public.maintenance_requests
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS applicant_first_name text;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS applicant_last_name text;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS property_id uuid;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS property_address text;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS unit_number text;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS screening_type text;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS screening_fee numeric;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE public.tenant_screenings
  ADD COLUMN IF NOT EXISTS declined_at timestamptz;

ALTER TABLE public.vendor_applications
  ADD COLUMN IF NOT EXISTS business_name text;
ALTER TABLE public.vendor_applications
  ADD COLUMN IF NOT EXISTS owner_name text;
ALTER TABLE public.vendor_applications
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE public.vendor_applications
  ADD COLUMN IF NOT EXISTS declined_at timestamptz;

-- The join form stores phrases such as "1 to 3 years". If live stored a
-- number, keep the old values by casting them to text.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'vendor_applications'
      AND column_name = 'years_in_business'
      AND data_type IN ('smallint', 'integer', 'bigint', 'numeric')
  ) THEN
    ALTER TABLE public.vendor_applications
      ALTER COLUMN years_in_business TYPE text
      USING years_in_business::text;
  END IF;
END $$;

ALTER TABLE public.partner_listings
  ADD COLUMN IF NOT EXISTS license_number text;
ALTER TABLE public.partner_listings
  ADD COLUMN IF NOT EXISTS has_insurance boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid NOT NULL,
  property_id uuid,
  description text NOT NULL,
  amount numeric NOT NULL,
  category text NOT NULL,
  expense_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid NOT NULL,
  subject text,
  message text,
  recipient_count integer DEFAULT 0,
  recipient_scope text DEFAULT 'all',
  sent_at timestamptz DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Upsert in the app targets user_id. Skip the unique index if duplicates
-- already exist so this script still commits.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'notification_preferences'
      AND indexdef ILIKE 'CREATE UNIQUE INDEX%'
      AND indexdef ILIKE '%(user_id)%'
  ) THEN
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.notification_preferences
    GROUP BY user_id HAVING count(*) > 1
  ) THEN
    RAISE NOTICE 'notification_preferences.user_id has duplicates; unique index skipped';
    RETURN;
  END IF;
  CREATE UNIQUE INDEX notification_preferences_user_id_key
    ON public.notification_preferences (user_id);
END $$;

-- ── sign-up row, without touching auto_link_tenant_on_signup ──
-- The app updates public.users right after sign-up and expects a row.
-- This insert does not overwrite a row the other trigger already wrote.
-- Blank fields are filled. A role that is already set is left alone.

CREATE OR REPLACE FUNCTION public.ensure_app_user_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text := COALESCE(NULLIF(lower(btrim(COALESCE(NEW.email, ''))), ''), '');
  v_name text := COALESCE(NEW.raw_user_meta_data ->> 'full_name', '');
  v_phone text := COALESCE(NEW.raw_user_meta_data ->> 'phone', '');
  v_role text := CASE
    WHEN NEW.raw_user_meta_data ->> 'role' IN ('landlord', 'tenant', 'vendor')
      THEN NEW.raw_user_meta_data ->> 'role'
    ELSE 'landlord'
  END;
  v_trial timestamptz := now() + interval '7 days';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN
    INSERT INTO public.users (
      id, email, full_name, role, phone,
      subscription_plan, trial_ends_at, welcome_message_sent,
      founding_member, language_preference, created_at
    ) VALUES (
      NEW.id, v_email, v_name, v_role, v_phone,
      'trial', v_trial, false,
      false, 'en', now()
    );
  ELSE
    UPDATE public.users
       SET email = CASE
             WHEN email IS NULL OR btrim(email) = '' THEN v_email
             ELSE email
           END,
           full_name = CASE
             WHEN full_name IS NULL OR btrim(full_name) = '' THEN v_name
             ELSE full_name
           END,
           phone = CASE
             WHEN phone IS NULL OR btrim(phone) = '' THEN v_phone
             ELSE phone
           END,
           role = CASE
             WHEN role IS NULL OR btrim(role) = '' THEN v_role
             ELSE role
           END,
           subscription_plan = CASE
             WHEN subscription_plan IS NULL OR btrim(subscription_plan) = '' THEN 'trial'
             ELSE subscription_plan
           END,
           trial_ends_at = COALESCE(trial_ends_at, v_trial)
     WHERE id = NEW.id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.id) THEN
    INSERT INTO public.profiles (
      id, email, full_name, role, phone,
      subscription_plan, trial_ends_at, welcome_message_sent,
      rentspree_disclosure_dismissed, created_at
    ) VALUES (
      NEW.id, v_email, v_name, v_role, v_phone,
      'trial', v_trial, false,
      false, now()
    );
  ELSE
    UPDATE public.profiles
       SET email = CASE
             WHEN email IS NULL OR btrim(email) = '' THEN v_email
             ELSE email
           END,
           full_name = CASE
             WHEN full_name IS NULL OR btrim(full_name) = '' THEN v_name
             ELSE full_name
           END,
           phone = CASE
             WHEN phone IS NULL OR btrim(phone) = '' THEN v_phone
             ELSE phone
           END,
           role = CASE
             WHEN role IS NULL OR btrim(role) = '' THEN v_role
             ELSE role
           END
     WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_ensure_row ON auth.users;
CREATE TRIGGER on_auth_user_created_ensure_row
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_app_user_row();

-- ── a person may edit their own profile, not their role ──

CREATE OR REPLACE FUNCTION public.users_guard_role_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
      -- A role that is already set cannot be changed by that person.
      -- A blank role may be filled once, and never with admin. Sign-up
      -- does this when the link trigger created the row without a role.
      IF OLD.role IS NOT NULL AND btrim(OLD.role) <> '' THEN
        RAISE EXCEPTION 'only an admin can change an account role'
          USING ERRCODE = '42501';
      END IF;
      IF NEW.role IS NULL
         OR btrim(NEW.role) = ''
         OR NEW.role NOT IN ('landlord', 'tenant', 'vendor') THEN
        RAISE EXCEPTION 'only an admin can change an account role'
          USING ERRCODE = '42501';
      END IF;
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

-- A signed-in person with no users row must not create themselves as admin.
-- Service-role and signup (auth.uid() is null) can still set a role.
CREATE OR REPLACE FUNCTION public.users_guard_role_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF lower(btrim(COALESCE(NEW.role, ''))) = 'admin' THEN
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
      RAISE EXCEPTION 'only an admin can create an admin account'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_guard_role_insert ON public.users;
CREATE TRIGGER users_guard_role_insert
  BEFORE INSERT ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.users_guard_role_insert();

-- ── a tenant may claim an invite, not rewrite the lease ──

CREATE OR REPLACE FUNCTION public.units_tenant_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.uid() IS DISTINCT FROM OLD.landlord_id
     AND NOT public.is_admin() THEN
    IF (NEW.property_id, NEW.landlord_id, NEW.unit_number, NEW.rent_amount,
        NEW.deposit_amount, NEW.additional_deposit, NEW.lease_start,
        NEW.lease_end, NEW.invited_email)
       IS DISTINCT FROM
       (OLD.property_id, OLD.landlord_id, OLD.unit_number, OLD.rent_amount,
        OLD.deposit_amount, OLD.additional_deposit, OLD.lease_start,
        OLD.lease_end, OLD.invited_email)
       OR NEW.status IS DISTINCT FROM 'occupied' THEN
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

-- A new claim starts that person's tenancy. Clearing the tenant clears it.
CREATE OR REPLACE FUNCTION public.units_set_tenant_since()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.tenant_id IS NOT NULL AND NEW.tenant_since IS NULL THEN
      NEW.tenant_since := now();
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
    IF NEW.tenant_id IS NULL THEN
      NEW.tenant_since := NULL;
    ELSE
      NEW.tenant_since := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS units_set_tenant_since ON public.units;
CREATE TRIGGER units_set_tenant_since
  BEFORE INSERT OR UPDATE OF tenant_id ON public.units
  FOR EACH ROW
  EXECUTE FUNCTION public.units_set_tenant_since();

-- ── who is assigned to a unit, compared as text so unit_id's type is safe ──

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
    WHERE mr.unit_id::text = p_unit::text
      AND (
        mr.vendor_user_id = p_user
        OR mr.vendor_id::text = p_user::text
        OR mr.vendor_id::text IN (
          SELECT v.id::text
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
  SELECT DISTINCT u.id
  FROM public.maintenance_requests mr
  JOIN public.units u ON u.id::text = mr.unit_id::text
  WHERE mr.unit_id IS NOT NULL
    AND public.vendor_assigned_to_unit(auth.uid(), u.id);
$$;

-- messages.unit_id is text on live. Pass it through as text and match units.id::text.
CREATE OR REPLACE FUNCTION public.can_send_unit_message(
  p_unit text,
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
  v_unit uuid;
  v_landlord uuid;
  v_tenant uuid;
  sender_role text;
  receiver_role text;
BEGIN
  IF uid IS NULL OR p_unit IS NULL OR btrim(p_unit) = ''
     OR p_receiver IS NULL OR btrim(p_receiver) = '' THEN
    RETURN false;
  END IF;

  SELECT id, landlord_id, tenant_id
    INTO v_unit, v_landlord, v_tenant
  FROM public.units
  WHERE id::text = p_unit;

  IF v_landlord IS NULL OR v_unit IS NULL THEN
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
  ELSIF public.vendor_assigned_to_unit(uid, v_unit) THEN
    sender_role := 'vendor';
  ELSE
    RETURN false;
  END IF;

  IF p_receiver = v_landlord::text THEN
    receiver_role := 'landlord';
  ELSIF v_tenant IS NOT NULL AND p_receiver = v_tenant::text THEN
    receiver_role := 'tenant';
  ELSIF p_receiver ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        AND public.vendor_assigned_to_unit(p_receiver::uuid, v_unit) THEN
    receiver_role := 'vendor';
  ELSE
    RETURN false;
  END IF;

  RETURN sender_role IS DISTINCT FROM receiver_role;
END;
$$;

-- Property checks must not SELECT units under RLS. The live
-- "Landlord can insert units" policy reads properties, and a property
-- policy that reads units back would recurse.
CREATE OR REPLACE FUNCTION public.tenant_can_read_property(p_property uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_property IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.units un
    WHERE un.property_id = p_property
      AND (
        un.tenant_id = auth.uid()
        OR lower(un.invited_email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.vendor_can_read_property(p_property uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_property IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.units un
    WHERE un.property_id = p_property
      AND public.vendor_assigned_to_unit(auth.uid(), un.id)
  );
$$;

-- Current tenant sees a unit file only from when their tenancy started
-- (claim time, or lease_start when the claim time was never stored).
CREATE OR REPLACE FUNCTION public.unit_file_visible_to_current_tenant(
  p_unit uuid,
  p_created timestamptz
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_unit IS NOT NULL
    AND p_created IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = p_unit
        AND u.tenant_id = auth.uid()
        AND COALESCE(u.tenant_since, u.lease_start::timestamptz) IS NOT NULL
        AND p_created >= COALESCE(u.tenant_since, u.lease_start::timestamptz)
    );
$$;

-- Listing owner is the partner_listings email. Definer so listing RLS
-- does not hide that row from the person the message was sent to.
CREATE OR REPLACE FUNCTION public.caller_owns_listing(p_listing text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_listing IS NOT NULL AND btrim(p_listing) <> '' AND EXISTS (
    SELECT 1
    FROM public.partner_listings pl
    WHERE pl.id::text = p_listing
      AND lower(pl.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
  );
$$;

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

  IF first_seg = uid::text THEN
    RETURN true;
  END IF;

  IF bucket = 'documents' THEN
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = second_seg::uuid
        AND (
          u.landlord_id = uid
          OR public.unit_file_visible_to_current_tenant(u.id, (
            SELECT o.created_at FROM storage.objects o
            WHERE o.bucket_id = bucket AND o.name = object_name
            LIMIT 1
          ))
          OR u.id IN (SELECT public.vendor_visible_unit_ids())
        )
    ) THEN
      RETURN true;
    END IF;

    IF second_seg = 'chat' AND third_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = third_seg::uuid
        AND (
          u.landlord_id = uid
          OR public.unit_file_visible_to_current_tenant(u.id, (
            SELECT o.created_at FROM storage.objects o
            WHERE o.bucket_id = bucket AND o.name = object_name
            LIMIT 1
          ))
          OR u.id IN (SELECT public.vendor_visible_unit_ids())
        )
    ) THEN
      RETURN true;
    END IF;

    IF second_seg = 'maintenance' AND third_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.maintenance_requests mr
      WHERE mr.id = third_seg::uuid
        AND (
          mr.landlord_id = uid
          OR (
            mr.tenant_id = uid
            AND public.unit_file_visible_to_current_tenant(
              mr.unit_id,
              COALESCE(mr.created_at, (
                SELECT o.created_at FROM storage.objects o
                WHERE o.bucket_id = bucket AND o.name = object_name
                LIMIT 1
              ))
            )
          )
          OR mr.vendor_user_id = uid
          OR mr.vendor_id::text = uid::text
          OR mr.vendor_id::text IN (
            SELECT v.id::text FROM public.vendors v
            WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
          )
        )
    ) THEN
      RETURN true;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.documents d
      WHERE (d.landlord_id = uid OR d.tenant_id = uid OR d.owner_id = uid)
        AND d.file_url LIKE '%' || object_name || '%'
    ) THEN
      RETURN true;
    END IF;

    -- Landlord lease or welcome file for this tenant's unit, including
    -- one uploaded before they claimed it. A file tagged to someone else
    -- is not included.
    IF EXISTS (
      SELECT 1
      FROM public.documents d
      JOIN public.units u ON u.id = d.unit_id
      WHERE u.tenant_id = uid
        AND (d.tenant_id IS NULL OR d.tenant_id = uid)
        AND (d.owner_id = u.landlord_id OR d.landlord_id = u.landlord_id)
        AND d.file_url LIKE '%' || object_name || '%'
    ) THEN
      RETURN true;
    END IF;

  ELSIF bucket = 'photo-logs' THEN
    -- Path is {uploader}/{unit_id}/{file}. The uploader already matched
    -- above. The landlord and a vendor on a job for this unit can read
    -- it. The current tenant can read it only from their tenancy start.
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = second_seg::uuid
        AND (
          u.landlord_id = uid
          OR public.unit_file_visible_to_current_tenant(u.id, (
            SELECT o.created_at FROM storage.objects o
            WHERE o.bucket_id = bucket AND o.name = object_name
            LIMIT 1
          ))
          OR public.vendor_assigned_to_unit(uid, u.id)
        )
    ) THEN
      RETURN true;
    END IF;

  ELSIF bucket = 'maintenance-photos' THEN
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.maintenance_requests mr
      WHERE mr.id = second_seg::uuid
        AND (
          mr.landlord_id = uid
          OR (
            mr.tenant_id = uid
            AND public.unit_file_visible_to_current_tenant(
              mr.unit_id,
              COALESCE(mr.created_at, (
                SELECT o.created_at FROM storage.objects o
                WHERE o.bucket_id = bucket AND o.name = object_name
                LIMIT 1
              ))
            )
          )
          OR mr.vendor_user_id = uid
          OR mr.vendor_id::text = uid::text
          OR mr.vendor_id::text IN (
            SELECT v.id::text FROM public.vendors v
            WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
          )
        )
    ) THEN
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END;
$$;

-- ── drop the open policies by their live names ──
-- Also drop the other open policies on the same tables. A leftover
-- USING (true) is OR'd with the new policy and the hole stays open.

DROP POLICY IF EXISTS "Authenticated users read messages" ON public.messages;
DROP POLICY IF EXISTS "Authenticated users send messages" ON public.messages;
DROP POLICY IF EXISTS "Authenticated users update messages" ON public.messages;
DROP POLICY IF EXISTS "messages: participants read" ON public.messages;
DROP POLICY IF EXISTS "messages: send as self" ON public.messages;
DROP POLICY IF EXISTS "messages: receiver marks read" ON public.messages;

DROP POLICY IF EXISTS "Tenant submits maintenance" ON public.maintenance_requests;
DROP POLICY IF EXISTS "Tenants can insert own payments" ON public.payments;
DROP POLICY IF EXISTS "Vendor reads assigned maintenance" ON public.maintenance_requests;
DROP POLICY IF EXISTS "Vendor updates assigned maintenance" ON public.maintenance_requests;
DROP POLICY IF EXISTS "maintenance_requests: vendor reads assigned" ON public.maintenance_requests;
DROP POLICY IF EXISTS "maintenance_requests: vendor updates assigned" ON public.maintenance_requests;

DROP POLICY IF EXISTS "Tenants read own property" ON public.properties;
DROP POLICY IF EXISTS "properties: tenant reads own" ON public.properties;
DROP POLICY IF EXISTS "properties: vendor reads job properties" ON public.properties;

DROP POLICY IF EXISTS "Authenticated users can read vendors" ON public.vendors;
DROP POLICY IF EXISTS "vendors: vendor reads own directory row" ON public.vendors;

DROP POLICY IF EXISTS "Admin reads applications" ON public.vendor_applications;
DROP POLICY IF EXISTS "Admin updates applications" ON public.vendor_applications;
DROP POLICY IF EXISTS "Anyone submits application" ON public.vendor_applications;
DROP POLICY IF EXISTS "vendor_applications: admin reads" ON public.vendor_applications;
DROP POLICY IF EXISTS "vendor_applications: admin updates" ON public.vendor_applications;
DROP POLICY IF EXISTS "vendor_applications: submit pending" ON public.vendor_applications;

DROP POLICY IF EXISTS "Anyone reads partner listings" ON public.partner_listings;
DROP POLICY IF EXISTS "Authenticated users can insert" ON public.partner_listings;
DROP POLICY IF EXISTS "partner_listings: admin manages" ON public.partner_listings;

DROP POLICY IF EXISTS "Anyone sends contact" ON public.vendor_contacts;
DROP POLICY IF EXISTS "vendor_contacts: authenticated insert" ON public.vendor_contacts;
DROP POLICY IF EXISTS "vendor_contacts: read by listing" ON public.vendor_contacts;
DROP POLICY IF EXISTS "vendor_contacts: sender inserts" ON public.vendor_contacts;
DROP POLICY IF EXISTS "vendor_contacts: participants read" ON public.vendor_contacts;

DROP POLICY IF EXISTS "Users update own" ON public.users;
DROP POLICY IF EXISTS "users: update own" ON public.users;
DROP POLICY IF EXISTS "users: insert own" ON public.users;
DROP POLICY IF EXISTS "users: landlord reads own tenants" ON public.users;
DROP POLICY IF EXISTS "users: tenant reads own landlord" ON public.users;
DROP POLICY IF EXISTS "users: landlord reads vendor accounts" ON public.users;

DROP POLICY IF EXISTS "units: vendor reads job units" ON public.units;
DROP POLICY IF EXISTS "units: tenant claims invite" ON public.units;
DROP POLICY IF EXISTS "photo_logs: vendor reads assigned jobs" ON public.photo_logs;

DROP POLICY IF EXISTS "documents: landlords select own" ON public.documents;
DROP POLICY IF EXISTS "documents: tenants select own" ON public.documents;

DROP POLICY IF EXISTS "expenses: landlord manages own" ON public.expenses;
DROP POLICY IF EXISTS "announcements: landlord manages own" ON public.announcements;

-- Storage. The scoped upload/read policies that were already correct
-- are kept. These are the open ones, including the copies whose names
-- sound narrow but whose check is only "bucket_id = ...".
DROP POLICY IF EXISTS "Authenticated users read documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users upload documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users view maintenance photos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users upload maintenance photos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users upload avatar" ON storage.objects;
DROP POLICY IF EXISTS "Public avatar read" ON storage.objects;
DROP POLICY IF EXISTS "Tenants can read photo logs for their unit" ON public.photo_logs;
DROP POLICY IF EXISTS "photo_logs: tenant reads own tenancy" ON public.photo_logs;
DROP POLICY IF EXISTS "Tenants can read photo logs" ON storage.objects;
DROP POLICY IF EXISTS "Tenants can upload photo logs" ON storage.objects;
DROP POLICY IF EXISTS "photo-logs: read own unit photos" ON storage.objects;
DROP POLICY IF EXISTS "photo-logs: upload own unit photos" ON storage.objects;
DROP POLICY IF EXISTS "documents: landlords read properties docs" ON storage.objects;
DROP POLICY IF EXISTS "documents: tenants read own docs" ON storage.objects;
DROP POLICY IF EXISTS "maintenance-photos: landlords read all" ON storage.objects;
DROP POLICY IF EXISTS "maintenance-photos: tenants read own" ON storage.objects;
DROP POLICY IF EXISTS "documents: read if tied to the file" ON storage.objects;
DROP POLICY IF EXISTS "photo-logs: read if tied to the unit" ON storage.objects;
DROP POLICY IF EXISTS "maintenance-photos: read if tied to the job" ON storage.objects;

-- ── scoped policies ──

CREATE POLICY "messages: participants read"
  ON public.messages
  FOR SELECT
  TO authenticated
  USING (
    sender_id = auth.uid()::text
    OR receiver_id = auth.uid()::text
    OR unit_id IN (
      SELECT u.id::text
      FROM public.units u
      WHERE u.landlord_id = auth.uid()
    )
    -- Older rows have a blank receiver. The unit's landlord can read
    -- them (covered above). The current tenant can read one only when
    -- it was written during this tenancy, so a former tenant's note is
    -- not handed over. A message whose unit was deleted matches no unit,
    -- so only its sender still sees it.
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
  );

CREATE POLICY "messages: send as self"
  ON public.messages
  FOR INSERT
  TO authenticated
  WITH CHECK (public.can_send_unit_message(unit_id, sender_id, receiver_id));

CREATE POLICY "messages: receiver marks read"
  ON public.messages
  FOR UPDATE
  TO authenticated
  USING (receiver_id = auth.uid()::text)
  WITH CHECK (receiver_id = auth.uid()::text);

CREATE POLICY "maintenance_requests: vendor reads assigned"
  ON public.maintenance_requests
  FOR SELECT
  TO authenticated
  USING (
    vendor_user_id = auth.uid()
    OR vendor_id::text = auth.uid()::text
    OR vendor_id::text IN (
      SELECT v.id::text
      FROM public.vendors v
      WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
    )
  );

CREATE POLICY "maintenance_requests: vendor updates assigned"
  ON public.maintenance_requests
  FOR UPDATE
  TO authenticated
  USING (
    vendor_user_id = auth.uid()
    OR vendor_id::text = auth.uid()::text
    OR vendor_id::text IN (
      SELECT v.id::text
      FROM public.vendors v
      WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
    )
  )
  WITH CHECK (
    vendor_user_id = auth.uid()
    OR vendor_id::text = auth.uid()::text
    OR vendor_id::text IN (
      SELECT v.id::text
      FROM public.vendors v
      WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
    )
  );

CREATE POLICY "properties: tenant reads own"
  ON public.properties
  FOR SELECT
  TO authenticated
  USING (public.tenant_can_read_property(id));

CREATE POLICY "properties: vendor reads job properties"
  ON public.properties
  FOR SELECT
  TO authenticated
  USING (public.vendor_can_read_property(id));

CREATE POLICY "vendors: vendor reads own directory row"
  ON public.vendors
  FOR SELECT
  TO authenticated
  USING (lower(email) = lower(COALESCE(auth.jwt() ->> 'email', '')));

CREATE POLICY "vendor_applications: admin reads"
  ON public.vendor_applications
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

CREATE POLICY "vendor_applications: admin updates"
  ON public.vendor_applications
  FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "vendor_applications: submit pending"
  ON public.vendor_applications
  FOR INSERT
  TO authenticated
  WITH CHECK (status IS NULL OR status = 'pending');

CREATE POLICY "partner_listings: admin manages"
  ON public.partner_listings
  FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "vendor_contacts: sender inserts"
  ON public.vendor_contacts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id::text = auth.uid()::text
    AND listing_id IS NOT NULL
    AND message IS NOT NULL
    AND btrim(message) <> ''
  );

CREATE POLICY "vendor_contacts: participants read"
  ON public.vendor_contacts
  FOR SELECT
  TO authenticated
  USING (
    sender_id::text = auth.uid()::text
    OR public.is_admin()
    OR public.caller_owns_listing(listing_id::text)
  );

CREATE POLICY "Users update own"
  ON public.users
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "users: insert own"
  ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (
    id = auth.uid()
    AND lower(btrim(COALESCE(role, ''))) IS DISTINCT FROM 'admin'
  );

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

CREATE POLICY "users: landlord reads vendor accounts"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    role = 'vendor'
    AND public.current_user_role() IN ('landlord', 'admin')
  );

CREATE POLICY "units: vendor reads job units"
  ON public.units
  FOR SELECT
  TO authenticated
  USING (id IN (SELECT public.vendor_visible_unit_ids()));

CREATE POLICY "photo_logs: tenant reads own tenancy"
  ON public.photo_logs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = photo_logs.unit_id
        AND u.tenant_id = auth.uid()
        AND (
          (
            photo_logs.storage_path IS NOT NULL
            AND photo_logs.storage_path LIKE auth.uid()::text || '/%'
          )
          OR public.unit_file_visible_to_current_tenant(
            u.id, photo_logs.created_at
          )
        )
    )
  );

CREATE POLICY "photo_logs: vendor reads assigned jobs"
  ON public.photo_logs
  FOR SELECT
  TO authenticated
  USING (public.vendor_assigned_to_unit(auth.uid(), unit_id));

DROP POLICY IF EXISTS "units: invited tenant reads unclaimed" ON public.units;
CREATE POLICY "units: invited tenant reads unclaimed"
  ON public.units
  FOR SELECT
  TO authenticated
  USING (
    tenant_id IS NULL
    AND invited_email IS NOT NULL
    AND lower(invited_email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
  );

CREATE POLICY "units: tenant claims invite"
  ON public.units
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id = auth.uid()
    OR (
      tenant_id IS NULL
      AND invited_email IS NOT NULL
      AND lower(invited_email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
    )
  )
  WITH CHECK (tenant_id = auth.uid());

CREATE POLICY "documents: landlords select own"
  ON public.documents
  FOR SELECT
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND public.current_user_role() IN ('landlord', 'admin')
  );

CREATE POLICY "documents: tenants select own"
  ON public.documents
  FOR SELECT
  TO authenticated
  USING (tenant_id = auth.uid());

-- A lease or welcome packet the landlord uploaded for this unit, including
-- one saved before the tenant claimed it. A row tagged to someone else
-- (the former tenant) stays hidden.
DROP POLICY IF EXISTS "documents: tenant reads landlord unit files" ON public.documents;
CREATE POLICY "documents: tenant reads landlord unit files"
  ON public.documents
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = documents.unit_id
        AND u.tenant_id = auth.uid()
        AND (documents.tenant_id IS NULL OR documents.tenant_id = auth.uid())
        AND (
          documents.owner_id = u.landlord_id
          OR documents.landlord_id = u.landlord_id
        )
    )
  );

CREATE POLICY "Tenant submits maintenance"
  ON public.maintenance_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = maintenance_requests.tenant_id
    AND EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = maintenance_requests.unit_id
        AND (u.tenant_id = auth.uid() OR u.landlord_id = auth.uid())
    )
  );

-- payments.tenant_id must be qualified. Inside the subquery an
-- unqualified tenant_id is the unit's tenant, so the caller could
-- file the payment as someone else.
CREATE POLICY "Tenants can insert own payments"
  ON public.payments
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = payments.unit_id
        AND (
          (auth.uid() = payments.tenant_id AND u.tenant_id = auth.uid())
          OR u.landlord_id = auth.uid()
        )
    )
  );

CREATE POLICY "expenses: landlord manages own"
  ON public.expenses
  FOR ALL
  TO authenticated
  USING (landlord_id = auth.uid())
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "announcements: landlord manages own"
  ON public.announcements
  FOR ALL
  TO authenticated
  USING (landlord_id = auth.uid())
  WITH CHECK (landlord_id = auth.uid());

CREATE POLICY "documents: read if tied to the file"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.can_read_storage_object('documents', name)
  );

CREATE POLICY "photo-logs: upload own unit photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'photo-logs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "photo-logs: read if tied to the unit"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'photo-logs'
    AND public.can_read_storage_object('photo-logs', name)
  );

CREATE POLICY "maintenance-photos: read if tied to the job"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'maintenance-photos'
    AND public.can_read_storage_object('maintenance-photos', name)
  );

-- Owner decision: photo-logs is no longer a public bucket.
UPDATE storage.buckets
   SET public = false
 WHERE id = 'photo-logs';

-- ── realtime chat ──

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.messages'::regclass
      AND contype = 'p'
  ) THEN
    EXECUTE 'ALTER TABLE public.messages REPLICA IDENTITY FULL';
  END IF;

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

-- ── grants: execute only on the helpers callers and policies need ──

-- Supabase grants EXECUTE to anon on new functions. PUBLIC and anon
-- are separate grants, so both are revoked.
REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ensure_app_user_row() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.users_guard_role_change() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.users_guard_role_insert() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.units_tenant_update_guard() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.units_set_tenant_since() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.vendor_assigned_to_unit(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.vendor_visible_unit_ids() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_send_unit_message(text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.caller_owns_listing(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_read_storage_object(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.tenant_can_read_property(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.vendor_can_read_property(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unit_file_visible_to_current_tenant(uuid, timestamptz) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.users_guard_role_change() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.users_guard_role_insert() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.units_tenant_update_guard() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.units_set_tenant_since() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.vendor_assigned_to_unit(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.vendor_visible_unit_ids() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_send_unit_message(text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.caller_owns_listing(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_read_storage_object(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tenant_can_read_property(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.vendor_can_read_property(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.unit_file_visible_to_current_tenant(uuid, timestamptz) TO authenticated, service_role;

-- The auth service inserts into auth.users and must be allowed to fire
-- the new trigger. The table owner is that role on hosted Supabase.
DO $$
DECLARE
  owner_name text;
BEGIN
  SELECT pg_get_userbyid(c.relowner) INTO owner_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'auth' AND c.relname = 'users';
  IF owner_name IS NOT NULL THEN
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION public.ensure_app_user_row() TO %I',
      owner_name
    );
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    GRANT EXECUTE ON FUNCTION public.ensure_app_user_row() TO supabase_auth_admin;
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.expenses TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.announcements TO anon, authenticated, service_role;

COMMIT;
