-- ============================================================
-- Rolls back supabase/live/07_delete_account.sql.
-- Drops the three functions and restores the three foreign keys.
-- It does not restore a tombstoned account.
-- Safe to run more than once.
-- Do not run this on a live project from an agent.
--
-- NOT NULL is put back only when every row in that column is filled.
-- If any row is NULL, the column stays nullable and a notice says why.
--
-- payments.tenant_id returns to ON DELETE CASCADE.
-- payment_methods.landlord_id returns to ON DELETE CASCADE.
-- properties.landlord_id, units.landlord_id, and documents.owner_id
-- return to ON DELETE CASCADE.
-- rent_history.changed_by returns to a foreign key with no ON DELETE
-- clause (NO ACTION, the Postgres default). The rehearsal described that
-- column as NOT NULL and a foreign key to auth.users, and did not name
-- an ON DELETE action.
-- ============================================================

DROP FUNCTION IF EXISTS public.purge_account_data(uuid);
DROP FUNCTION IF EXISTS public.account_storage_to_remove(uuid);
DROP FUNCTION IF EXISTS public.account_repair_photo_uses(text);

DO $$
DECLARE
  r record;
  has_cascade boolean;
BEGIN
  has_cascade := false;
  FOR r IN
    SELECT c.conname, pg_get_constraintdef(c.oid) AS def
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
    IF r.def ILIKE '%ON DELETE CASCADE%' THEN
      has_cascade := true;
    ELSE
      EXECUTE format('ALTER TABLE public.payments DROP CONSTRAINT %I', r.conname);
    END IF;
  END LOOP;

  IF NOT has_cascade THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_tenant_id_auth_users_fkey
      FOREIGN KEY (tenant_id) REFERENCES auth.users (id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.payments WHERE tenant_id IS NULL) THEN
    ALTER TABLE public.payments ALTER COLUMN tenant_id SET NOT NULL;
  ELSE
    RAISE NOTICE 'payments.tenant_id left nullable: some rows are NULL, so NOT NULL was not restored';
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
      AND t.relname = 'rent_history'
      AND c.contype = 'f'
      AND a.attname = 'changed_by'
  LOOP
    IF r.def ILIKE '%ON DELETE%' THEN
      EXECUTE format('ALTER TABLE public.rent_history DROP CONSTRAINT %I', r.conname);
    ELSE
      has_no_action := true;
    END IF;
  END LOOP;

  IF NOT has_no_action THEN
    ALTER TABLE public.rent_history
      ADD CONSTRAINT rent_history_changed_by_auth_users_fkey
      FOREIGN KEY (changed_by) REFERENCES auth.users (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.rent_history WHERE changed_by IS NULL) THEN
    ALTER TABLE public.rent_history ALTER COLUMN changed_by SET NOT NULL;
  ELSE
    RAISE NOTICE 'rent_history.changed_by left nullable: some rows are NULL, so NOT NULL was not restored';
  END IF;
END $$;

DO $$
DECLARE
  r record;
  has_cascade boolean;
BEGIN
  has_cascade := false;
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
    IF r.def ILIKE '%ON DELETE CASCADE%' THEN
      has_cascade := true;
    ELSE
      EXECUTE format('ALTER TABLE public.payment_methods DROP CONSTRAINT %I', r.conname);
    END IF;
  END LOOP;

  IF NOT has_cascade THEN
    ALTER TABLE public.payment_methods
      ADD CONSTRAINT payment_methods_landlord_id_profiles_fkey
      FOREIGN KEY (landlord_id) REFERENCES public.profiles (id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
DECLARE
  spec record;
  r record;
  has_cascade boolean;
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

    has_cascade := false;
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
      IF r.def ILIKE '%ON DELETE CASCADE%' THEN
        has_cascade := true;
      ELSE
        EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', spec.table_name, r.conname);
      END IF;
    END LOOP;

    IF NOT has_cascade THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES auth.users (id) ON DELETE CASCADE',
        spec.table_name, spec.constraint_name, spec.column_name
      );
    END IF;
  END LOOP;
END $$;
