-- ============================================================
-- ELEVO — delete the signed-in account's personal data.
--
-- Run after 06_subscriptions_push_email_rentspree.sql. 06 is already on
-- live. This file is not applied anywhere yet.
-- Do not run this on a live project from an agent. The owner applies it.
-- It adds functions and changes three foreign keys. Applying it does not
-- delete any row.
-- Re-running replaces the functions.
--
-- The edge function supabase/functions/delete-account is the only caller.
-- It must pass the user id from a verified JWT, never from the request body.
-- EXECUTE is granted to service_role only.
--
-- Tombstone, not a cascade delete. The auth user is not removed, so a
-- foreign key ON DELETE CASCADE cannot wipe a portfolio. The edge function
-- bans that login and scrambles the auth email. This function keeps
-- public.users and public.profiles and clears the contact fields on them.
--
-- Removed for that user:
--   notification_preferences,
--   push_subscriptions (the Firebase device token from 06),
--   tenant_emergency_contacts, vault_items,
--   job_chat_reads (read receipts),
--   partner_listings and vendor_applications with the same email.
--   Storage files are removed by the edge function, not by this SQL:
--   private-vault files and other files whose first folder is this user,
--   unless a document, photo log, or repair photo still points at the file.
--
-- Kept:
--   public.users and public.profiles (contact fields cleared),
--   properties, units, and documents owned by a landlord,
--   calendar_events, expenses, and announcements (unchanged; they have
--     no changed_by column),
--   a unit the person rented: tenant_id, tenant_name, and invited_email
--     cleared and status set to vacant (the unit stays),
--   payment_methods, including bank details, so current tenants can still pay,
--   payments, with tenant_id and confirmed_by cleared when they were this user,
--   rent_history, with changed_by cleared,
--   maintenance_requests, with tenant_id and vendor_user_id cleared when
--     they were this user (vendor_id cleared only when it is this user id),
--   documents, with tenant_id cleared when it was this user (files stay),
--   photo_logs,
--   messages, with sender_id or receiver_id cleared when they were this user
--     (the text stays),
--   job_chat_participants, with left_at set (the row stays),
--   tenant_screenings kept; applicant name and email set to '' (those
--     columns are NOT NULL), and phone and notes cleared, when the
--     applicant email matches,
--   vendors directory rows kept; name, email, phone, and notes cleared when
--     the email matches.
-- Stripe is canceled by supabase/functions/delete-account before this
-- SQL runs. This SQL does not call Stripe. There is no refund.
-- Stripe audit is kept on purpose:
--   public.stripe_webhook_events (no user id; the delivery log)
--   public.stripe_applied_events (user_id is left as stored)
--   public.stripe_plan_map (shared price map, not one person's data)
-- stripe_customer_id stays on the tombstone row so a later webhook can
-- still find the account. The RentSpree link on that row is cleared.
--
-- Schema guards, so a later auth delete cannot destroy shared rows:
--   payments.tenant_id is nullable and ON DELETE SET NULL
--   rent_history.changed_by is nullable and ON DELETE SET NULL
--   payment_methods.landlord_id is ON DELETE NO ACTION (it referenced
--     profiles ON DELETE CASCADE)
--   properties.landlord_id, units.landlord_id, and documents.owner_id
--     are ON DELETE NO ACTION (they referenced auth.users ON DELETE CASCADE)
--     so a later manual delete of the auth user cannot remove the portfolio.
--     App deletes of a property, unit, or document remove that row only.
--     They do not delete auth.users, so this does not change those flows.
-- ============================================================

-- ── schema guards (idempotent) ──

DO $$
DECLARE
  r record;
  has_set_null boolean;
BEGIN
  ALTER TABLE public.payments ALTER COLUMN tenant_id DROP NOT NULL;

  has_set_null := false;
  FOR r IN
    SELECT c.oid, c.conname, pg_get_constraintdef(c.oid) AS def
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    JOIN LATERAL unnest(c.conkey) AS cols(attnum) ON true
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = cols.attnum
    WHERE n.nspname = 'public'
      AND t.relname = 'payments'
      AND c.contype = 'f'
      AND a.attname = 'tenant_id'
  LOOP
    IF r.def ILIKE '%ON DELETE SET NULL%' THEN
      has_set_null := true;
    ELSE
      EXECUTE format('ALTER TABLE public.payments DROP CONSTRAINT %I', r.conname);
    END IF;
  END LOOP;

  IF NOT has_set_null THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_tenant_id_auth_users_fkey
      FOREIGN KEY (tenant_id) REFERENCES auth.users (id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
DECLARE
  r record;
  has_set_null boolean;
BEGIN
  ALTER TABLE public.rent_history ALTER COLUMN changed_by DROP NOT NULL;

  has_set_null := false;
  FOR r IN
    SELECT c.oid, c.conname, pg_get_constraintdef(c.oid) AS def
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    JOIN LATERAL unnest(c.conkey) AS cols(attnum) ON true
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = cols.attnum
    WHERE n.nspname = 'public'
      AND t.relname = 'rent_history'
      AND c.contype = 'f'
      AND a.attname = 'changed_by'
  LOOP
    IF r.def ILIKE '%ON DELETE SET NULL%' THEN
      has_set_null := true;
    ELSE
      EXECUTE format('ALTER TABLE public.rent_history DROP CONSTRAINT %I', r.conname);
    END IF;
  END LOOP;

  IF NOT has_set_null THEN
    ALTER TABLE public.rent_history
      ADD CONSTRAINT rent_history_changed_by_auth_users_fkey
      FOREIGN KEY (changed_by) REFERENCES auth.users (id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
DECLARE
  r record;
  has_no_action boolean;
BEGIN
  has_no_action := false;
  FOR r IN
    SELECT c.conname, pg_get_constraintdef(c.oid) AS def
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    JOIN LATERAL unnest(c.conkey) AS cols(attnum) ON true
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = cols.attnum
    WHERE n.nspname = 'public'
      AND t.relname = 'payment_methods'
      AND c.contype = 'f'
      AND a.attname = 'landlord_id'
  LOOP
    -- NO ACTION is the default, so pg_get_constraintdef omits ON DELETE.
    IF r.def ILIKE '%ON DELETE%' THEN
      EXECUTE format('ALTER TABLE public.payment_methods DROP CONSTRAINT %I', r.conname);
    ELSE
      has_no_action := true;
    END IF;
  END LOOP;

  IF NOT has_no_action THEN
    ALTER TABLE public.payment_methods
      ADD CONSTRAINT payment_methods_landlord_id_profiles_fkey
      FOREIGN KEY (landlord_id) REFERENCES public.profiles (id) ON DELETE NO ACTION;
  END IF;
END $$;

-- A manual delete of auth.users must not cascade the portfolio away.
-- NO ACTION is omitted from pg_get_constraintdef, same as the default.
DO $$
DECLARE
  spec record;
  r record;
  has_no_action boolean;
BEGIN
  FOR spec IN
    SELECT *
    FROM (VALUES
      ('properties', 'landlord_id', 'properties_landlord_id_auth_users_fkey'),
      ('units', 'landlord_id', 'units_landlord_id_auth_users_fkey'),
      ('documents', 'owner_id', 'documents_owner_id_auth_users_fkey')
    ) AS v(table_name, column_name, constraint_name)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = spec.table_name
        AND column_name = spec.column_name
    ) THEN
      CONTINUE;
    END IF;

    has_no_action := false;
    FOR r IN
      SELECT c.conname, pg_get_constraintdef(c.oid) AS def
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      JOIN LATERAL unnest(c.conkey) AS cols(attnum) ON true
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = cols.attnum
      WHERE n.nspname = 'public'
        AND t.relname = spec.table_name
        AND c.contype = 'f'
        AND a.attname = spec.column_name
    LOOP
      IF r.def ILIKE '%ON DELETE%' THEN
        EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', spec.table_name, r.conname);
      ELSE
        has_no_action := true;
      END IF;
    END LOOP;

    IF NOT has_no_action THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES auth.users (id) ON DELETE NO ACTION',
        spec.table_name, spec.constraint_name, spec.column_name
      );
    END IF;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.account_repair_photo_uses(p_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RETURN false;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'maintenance_requests'
      AND column_name = 'photo_paths'
  ) THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.maintenance_requests m
    WHERE position(p_name in m.photo_paths::text) > 0
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.account_storage_to_remove(p_user uuid)
RETURNS TABLE (bucket_id text, object_name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
  IF p_user IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT o.bucket_id::text, o.name::text
  FROM storage.objects o
  WHERE o.name LIKE p_user::text || '/%'
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.file_url IS NOT NULL
        AND position(o.name in d.file_url) > 0
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.photo_logs p
      WHERE p.storage_path IS NOT NULL
        AND (
          p.storage_path = o.name
          OR position(o.name in p.storage_path) > 0
        )
    )
    AND NOT public.account_repair_photo_uses(o.name)

  UNION

  SELECT 'private-vault'::text, v.file_url
  FROM public.vault_items v
  WHERE v.landlord_id = p_user
    AND v.file_url IS NOT NULL
    AND position('://' in v.file_url) = 0
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.file_url IS NOT NULL
        AND position(v.file_url in d.file_url) > 0
    )
    AND NOT public.account_repair_photo_uses(v.file_url);
END;
$$;

CREATE OR REPLACE FUNCTION public.purge_account_data(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
  sender_is_text boolean;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'account deletion needs the signed-in user'
      USING ERRCODE = '42501';
  END IF;

  SELECT lower(email) INTO v_email
  FROM public.users
  WHERE id = p_user;

  IF v_email IS NULL THEN
    SELECT lower(email) INTO v_email
    FROM public.profiles
    WHERE id = p_user;
  END IF;

  DELETE FROM public.notification_preferences WHERE user_id = p_user;
  -- Device token for this person only. 06 stores one row per user.
  DELETE FROM public.push_subscriptions WHERE user_id = p_user;
  -- Do not delete stripe_webhook_events, stripe_applied_events, or stripe_plan_map.
  DELETE FROM public.tenant_emergency_contacts WHERE tenant_id = p_user;
  DELETE FROM public.vault_items WHERE landlord_id = p_user;

  IF to_regclass('public.job_chat_reads') IS NOT NULL THEN
    DELETE FROM public.job_chat_reads WHERE user_id = p_user;
  END IF;

  IF v_email IS NOT NULL THEN
    DELETE FROM public.partner_listings
    WHERE email IS NOT NULL AND lower(email) = v_email;

    DELETE FROM public.vendor_applications
    WHERE email IS NOT NULL AND lower(email) = v_email;

    UPDATE public.vendors
       SET email = NULL,
           phone = NULL,
           name = 'Removed vendor',
           company_name = 'Removed vendor',
           notes = NULL
     WHERE email IS NOT NULL AND lower(email) = v_email;

    UPDATE public.tenant_screenings
       SET applicant_name = '',
           applicant_email = '',
           applicant_first_name = '',
           applicant_last_name = '',
           applicant_phone = NULL,
           notes = NULL
     WHERE applicant_email IS NOT NULL
       AND applicant_email <> ''
       AND lower(applicant_email) = v_email;

    UPDATE public.units
       SET invited_email = NULL
     WHERE invited_email IS NOT NULL
       AND lower(invited_email) = v_email
       AND tenant_id IS DISTINCT FROM p_user;
  END IF;

  UPDATE public.units
     SET tenant_id = NULL,
         tenant_name = NULL,
         invited_email = NULL,
         status = 'vacant'
   WHERE tenant_id = p_user;

  SELECT data_type = 'text'
    INTO sender_is_text
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'messages'
    AND column_name = 'sender_id';

  IF sender_is_text THEN
    UPDATE public.messages
       SET sender_id = ''
     WHERE sender_id = p_user::text;
    UPDATE public.messages
       SET receiver_id = ''
     WHERE receiver_id = p_user::text;
  END IF;

  UPDATE public.maintenance_requests
     SET tenant_id = NULL
   WHERE tenant_id = p_user;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'maintenance_requests'
      AND column_name = 'vendor_user_id'
  ) THEN
    UPDATE public.maintenance_requests
       SET vendor_user_id = NULL
     WHERE vendor_user_id = p_user;
  END IF;

  UPDATE public.maintenance_requests
     SET vendor_id = NULL
   WHERE vendor_id = p_user;

  UPDATE public.payments SET tenant_id = NULL WHERE tenant_id = p_user;
  UPDATE public.payments SET confirmed_by = NULL WHERE confirmed_by = p_user;
  UPDATE public.documents SET tenant_id = NULL WHERE tenant_id = p_user;
  UPDATE public.rent_history SET changed_by = NULL WHERE changed_by = p_user;

  IF to_regclass('public.job_chat_participants') IS NOT NULL THEN
    UPDATE public.job_chat_participants
       SET left_at = COALESCE(left_at, now())
     WHERE user_id = p_user;
  END IF;

  -- Tombstone. Do not delete these rows: properties, units, documents,
  -- and payment methods point at them.
  UPDATE public.profiles
     SET email = 'deleted+' || id::text || '@getelevo.app',
         full_name = 'Deleted account',
         phone = '',
         avatar_url = NULL
   WHERE id = p_user;

  UPDATE public.users
     SET email = 'deleted+' || id::text || '@getelevo.app',
         full_name = 'Deleted account',
         phone = '',
         avatar_url = NULL,
         unit_id = NULL
   WHERE id = p_user;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'rentspree_invite_link'
  ) THEN
    UPDATE public.users
       SET rentspree_invite_link = NULL
     WHERE id = p_user;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.account_repair_photo_uses(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_storage_to_remove(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_account_data(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.account_repair_photo_uses(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.account_storage_to_remove(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.purge_account_data(uuid) TO service_role;
