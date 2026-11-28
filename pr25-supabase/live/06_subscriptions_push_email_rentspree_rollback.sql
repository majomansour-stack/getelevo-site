-- ============================================================
-- Rollback for 06_subscriptions_push_email_rentspree.sql.
--
-- Drops only what 06 added. Does not delete properties, units,
-- or account rows. Does not drop auth.users.email_confirmed_at
-- (that column belongs to Supabase Auth and already exists on live).
-- Restores the unit-claim policy and the signup link from 01 / 00.
-- ============================================================

BEGIN;

-- Put back only the anon and PUBLIC privileges 06 recorded. A second
-- rollback finds no backup and grants nothing.
DO $$
DECLARE
  tbl text;
  rec record;
BEGIN
  IF to_regclass('public.elevo_06_acl_backup') IS NULL THEN
    RETURN;
  END IF;

  FOR tbl IN
    SELECT DISTINCT b.table_name
    FROM public.elevo_06_acl_backup b
    WHERE b.table_schema = 'public'
      AND b.table_name IN ('job_chat_participants', 'job_chat_reads')
  LOOP
    IF to_regclass('public.' || tbl) IS NULL THEN
      CONTINUE;
    END IF;

    EXECUTE format(
      'REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon',
      tbl
    );

    FOR rec IN
      SELECT b.grantee, b.privilege_type
      FROM public.elevo_06_acl_backup b
      WHERE b.table_schema = 'public'
        AND b.table_name = tbl
        AND b.grantee IN ('anon', 'PUBLIC')
        AND b.privilege_type IN (
          'SELECT', 'INSERT', 'UPDATE', 'DELETE',
          'TRUNCATE', 'REFERENCES', 'TRIGGER'
        )
    LOOP
      IF rec.grantee = 'PUBLIC' THEN
        EXECUTE format(
          'GRANT %s ON TABLE public.%I TO PUBLIC',
          rec.privilege_type,
          tbl
        );
      ELSE
        EXECUTE format(
          'GRANT %s ON TABLE public.%I TO anon',
          rec.privilege_type,
          tbl
        );
      END IF;
    END LOOP;
  END LOOP;

  DROP TABLE public.elevo_06_acl_backup;
END $$;

DROP POLICY IF EXISTS "units: property belongs to landlord" ON public.units;

DROP FUNCTION IF EXISTS public.user_ids_matching_email(text);
DROP TABLE IF EXISTS public.stripe_applied_events;

-- FIX(run9): restore the claim policy BEFORE dropping caller_email_confirmed(),
-- which it depends on (the PR order fails with 2BP01).
DROP POLICY IF EXISTS "units: tenant claims invite" ON public.units;
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

DROP TRIGGER IF EXISTS units_require_confirmed_email ON public.units;
DROP TRIGGER IF EXISTS on_auth_user_email_confirmed ON auth.users;
DROP TRIGGER IF EXISTS enforce_landlord_plan_limits ON public.units;
DROP TRIGGER IF EXISTS enforce_landlord_plan_limits ON public.properties;
DROP TRIGGER IF EXISTS protect_subscription_columns ON public.profiles;
DROP TRIGGER IF EXISTS protect_subscription_columns ON public.users;

DROP FUNCTION IF EXISTS public.units_require_confirmed_email();
DROP FUNCTION IF EXISTS public.caller_email_confirmed();
DROP FUNCTION IF EXISTS public.caller_may_push_to(uuid);
DROP FUNCTION IF EXISTS public.enforce_landlord_plan_limits();
DROP FUNCTION IF EXISTS public.protect_subscription_columns();

-- FIX(run9): restore the exact pre-06 body and grants (live and practice
-- both had this body: no role check, LOWER(TRIM()), no search_path).
CREATE OR REPLACE FUNCTION public.auto_link_tenant_on_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  UPDATE public.units
  SET tenant_id = NEW.id,
      status = 'occupied'
  WHERE LOWER(TRIM(invited_email)) = LOWER(TRIM(NEW.email))
    AND tenant_id IS NULL;
  RETURN NEW;
END;
$function$;
ALTER FUNCTION public.auto_link_tenant_on_signup() RESET search_path;
GRANT EXECUTE ON FUNCTION public.auto_link_tenant_on_signup() TO PUBLIC, anon, authenticated, service_role;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    REVOKE EXECUTE ON FUNCTION public.auto_link_tenant_on_signup() FROM supabase_auth_admin;
  END IF;
END $$;



DROP TABLE IF EXISTS public.stripe_webhook_events;
DROP TABLE IF EXISTS public.stripe_plan_map;

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_rentspree_invite_link_https;

DROP INDEX IF EXISTS public.users_stripe_customer_id_key;

-- Drop only the index 06 created. A UNIQUE constraint of the same name
-- belongs to the original push table and must stay.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'push_subscriptions_user_id_key'
  ) THEN
    RETURN;
  END IF;
  DROP INDEX IF EXISTS public.push_subscriptions_user_id_key;
END $$;

ALTER TABLE public.users DROP COLUMN IF EXISTS rentspree_invite_link;
ALTER TABLE public.users DROP COLUMN IF EXISTS setup_purchased_at;
ALTER TABLE public.users DROP COLUMN IF EXISTS extra_property_count;
ALTER TABLE public.users DROP COLUMN IF EXISTS current_period_end;
ALTER TABLE public.users DROP COLUMN IF EXISTS stripe_subscription_id;
ALTER TABLE public.users DROP COLUMN IF EXISTS stripe_customer_id;
ALTER TABLE public.users DROP COLUMN IF EXISTS subscription_status;

ALTER TABLE public.profiles DROP COLUMN IF EXISTS setup_purchased_at;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS extra_property_count;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS current_period_end;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS stripe_subscription_id;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS stripe_customer_id;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS subscription_status;

COMMIT;
