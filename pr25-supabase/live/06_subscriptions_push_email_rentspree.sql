-- ============================================================
-- ELEVO — subscriptions, push authorization, email confirmation,
-- and the landlord RentSpree link.
--
-- Run after 04_followup.sql (and after 05 if that file is already
-- on the database). Safe to run again. Adds columns, tables,
-- triggers, and one tighter policy. It does not delete rows,
-- overwrite existing values, or widen a policy.
--
-- Stripe plan mapping
-- -------------------
-- The app never sends a price id. After a payment, stripe-webhook
-- looks up public.stripe_plan_map by the Stripe price id and, if
-- that misses, by the payment link id (plink_..., from the Payment
-- Link page in Stripe — not the buy.stripe.com URL).
--
-- An admin fills the table later from the Supabase SQL editor
-- (that session has no user JWT, so it is allowed to write).
-- Example, once the ids are copied from Stripe:
--
--   insert into public.stripe_plan_map
--     (stripe_price_id, stripe_payment_link_id, plan_key)
--   values
--     ('price_...', 'plink_...', 'essential');
--
-- plan_key must be one of:
--   essential, unlimited, extra_property, done_for_you,
--   vendor_basic, vendor_featured, vendor_preferred, vendor_platinum
--
-- essential / unlimited / vendor_* become users.subscription_plan.
-- extra_property sets extra_property_count from that subscription
-- item's quantity (one subscription, quantity = how many extras).
-- done_for_you sets setup_purchased_at and does not change the plan.
-- A price that is not in this table is stored on the event row and
-- does not change the account.
--
-- Plan rules the trigger enforces (same as lib/core/billing_rules.dart):
--   * trial / free / blank, with trial_ends_at null or in the future,
--     uses Essential limits. A null trial end stays open so older
--     rows are not locked. A past trial end with no paying plan
--     blocks new properties. A unit insert counts as one property.
--     Reads are unchanged.
--   * Essential: 1 property, plus each purchased extra property.
--     A new property row counts as one. A new unit row also counts
--     as one property against that same limit.
--   * Unlimited with status active, trialing, or blank: no cap.
--   * past_due, canceled, unpaid, incomplete, incomplete_expired:
--     block new creates. Stripe keeps status active until the period
--     ends, so cancel-at-period-end still allows creates.
--   * Tenants are not gated. Vendor tiers have no per-vendor usage
--     cap in the app, so this trigger does not limit vendors.
--   * Admin accounts are not plan-gated. founding_member is not a plan.
--   * Done for You does not change limits.
--
-- Who may write plan fields
-- --------------------------
-- A signed-in person cannot change subscription_plan to anything
-- except trial, and only while the stored plan is blank or already
-- trial. That is the signup update. They cannot extend trial_ends_at
-- or set status, Stripe ids, period end, extra properties, or
-- setup_purchased_at. The service role (the webhook) and any session
-- with no user id (the signup trigger, the SQL editor) can write them.
-- The trigger puts forbidden values back instead of failing the whole
-- update, so signup can still save the name and phone in the same row.
-- ============================================================

BEGIN;

-- Practice databases created from 00 do not have this Auth column.
-- Live already has it. Rollback does not drop it.
-- FIX(run9): auth.users is owned by supabase_auth_admin, so even
-- ADD COLUMN IF NOT EXISTS fails with "must be owner". Only try when missing.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'auth' AND table_name = 'users'
      AND column_name = 'email_confirmed_at'
  ) THEN
    ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz;
  END IF;
END $$;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS subscription_status text NOT NULL DEFAULT 'trial';
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS stripe_customer_id text;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS current_period_end timestamptz;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS extra_property_count integer NOT NULL DEFAULT 0;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS setup_purchased_at timestamptz;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS rentspree_invite_link text;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS subscription_status text NOT NULL DEFAULT 'trial';
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stripe_customer_id text;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS current_period_end timestamptz;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS extra_property_count integer NOT NULL DEFAULT 0;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS setup_purchased_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS users_stripe_customer_id_key
  ON public.users (stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'users_rentspree_invite_link_https'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_rentspree_invite_link_https
      CHECK (
        rentspree_invite_link IS NULL
        OR rentspree_invite_link ~* '^https://([a-z0-9-]+\.)*rentspree\.com([/?#][^[:space:]]*)?$'
      );
  END IF;
END $$;

-- ── plan map and webhook idempotency (service role only) ──

CREATE TABLE IF NOT EXISTS public.stripe_plan_map (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stripe_price_id text,
  stripe_payment_link_id text,
  plan_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT stripe_plan_map_key_present CHECK (
    stripe_price_id IS NOT NULL OR stripe_payment_link_id IS NOT NULL
  ),
  CONSTRAINT stripe_plan_map_plan_key_known CHECK (
    plan_key IN (
      'essential',
      'unlimited',
      'extra_property',
      'done_for_you',
      'vendor_basic',
      'vendor_featured',
      'vendor_preferred',
      'vendor_platinum'
    )
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS stripe_plan_map_price_id_key
  ON public.stripe_plan_map (stripe_price_id)
  WHERE stripe_price_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stripe_plan_map_payment_link_id_key
  ON public.stripe_plan_map (stripe_payment_link_id)
  WHERE stripe_payment_link_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.stripe_webhook_events (
  event_id text PRIMARY KEY,
  event_type text NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),
  note text
);

ALTER TABLE public.stripe_plan_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_webhook_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.stripe_plan_map FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.stripe_webhook_events FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stripe_plan_map TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stripe_webhook_events TO service_role;

-- One token row per person, so login upserts instead of inserting duplicates.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'push_subscriptions_user_id_key'
  ) THEN
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.push_subscriptions
    GROUP BY user_id HAVING count(*) > 1
  ) THEN
    RAISE NOTICE 'push_subscriptions.user_id has duplicates; unique index skipped';
    RETURN;
  END IF;
  CREATE UNIQUE INDEX push_subscriptions_user_id_key
    ON public.push_subscriptions (user_id);
END $$;

-- ── signed-in people cannot grant themselves a plan ──
-- SECURITY INVOKER so current_user is the caller. A definer here would
-- look like postgres and the lock would never apply.

-- FIX(run9): see fix2_trial_null.sql
CREATE OR REPLACE FUNCTION public.protect_subscription_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  locked boolean;
  old_plan text;
  new_plan text;
BEGIN
  locked := auth.uid() IS NOT NULL
    AND COALESCE(auth.role(), '') IS DISTINCT FROM 'service_role';

  IF NOT locked THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.subscription_plan := 'trial';
    NEW.subscription_status := 'trial';
    NEW.stripe_customer_id := NULL;
    NEW.stripe_subscription_id := NULL;
    NEW.current_period_end := NULL;
    NEW.extra_property_count := 0;
    NEW.setup_purchased_at := NULL;
    IF NEW.trial_ends_at IS NULL
       OR NEW.trial_ends_at > now() + interval '8 days' THEN
      NEW.trial_ends_at := now() + interval '7 days';
    END IF;
    RETURN NEW;
  END IF;

  old_plan := lower(btrim(COALESCE(OLD.subscription_plan, '')));
  new_plan := lower(btrim(COALESCE(NEW.subscription_plan, '')));
  IF NOT (
    new_plan = old_plan
    OR ((old_plan = '' OR old_plan = 'trial' OR old_plan = 'free') AND new_plan = 'trial')
  ) THEN
    NEW.subscription_plan := OLD.subscription_plan;
  END IF;

  IF OLD.trial_ends_at IS NULL THEN
    IF NEW.trial_ends_at IS NOT NULL
       AND NEW.trial_ends_at > now() + interval '8 days' THEN
      NEW.trial_ends_at := now() + interval '7 days';
    END IF;
  ELSIF NEW.trial_ends_at IS DISTINCT FROM OLD.trial_ends_at THEN
    IF NEW.trial_ends_at IS NULL OR NEW.trial_ends_at > OLD.trial_ends_at THEN
      NEW.trial_ends_at := OLD.trial_ends_at;
    END IF;
  END IF;

  NEW.subscription_status := OLD.subscription_status;
  NEW.stripe_customer_id := OLD.stripe_customer_id;
  NEW.stripe_subscription_id := OLD.stripe_subscription_id;
  NEW.current_period_end := OLD.current_period_end;
  NEW.extra_property_count := OLD.extra_property_count;
  NEW.setup_purchased_at := OLD.setup_purchased_at;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_subscription_columns ON public.users;
CREATE TRIGGER protect_subscription_columns
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_subscription_columns();

DROP TRIGGER IF EXISTS protect_subscription_columns ON public.profiles;
CREATE TRIGGER protect_subscription_columns
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_subscription_columns();

-- ── Essential property limit on new properties and unit rows ──

CREATE OR REPLACE FUNCTION public.enforce_landlord_plan_limits()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid;
  v_role text;
  v_plan text;
  v_status text;
  v_trial timestamptz;
  v_extra integer;
  v_properties integer;
  v_units integer;
  v_slots integer;
BEGIN
  -- SQL editor and the signup path have no user id. The webhook uses
  -- the service role. Admins are not plan-gated.
  IF auth.uid() IS NULL
     OR COALESCE(auth.role(), '') = 'service_role'
     OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  v_owner := NEW.landlord_id;
  IF v_owner IS NULL AND TG_TABLE_NAME = 'units' THEN
    SELECT p.landlord_id INTO v_owner
    FROM public.properties p
    WHERE p.id = NEW.property_id;
  END IF;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'subscription required to add properties or units'
      USING ERRCODE = '42501';
  END IF;

  SELECT role, subscription_plan, subscription_status, trial_ends_at, extra_property_count
    INTO v_role, v_plan, v_status, v_trial, v_extra
  FROM public.users
  WHERE id = v_owner;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription required to add properties or units'
      USING ERRCODE = '42501';
  END IF;

  -- Tenants never use this path for their own home. A vendor has no
  -- property product. Only landlord (and a blank role, which the app
  -- treats as landlord) are measured against the plan.
  IF lower(btrim(COALESCE(v_role, ''))) = 'admin' THEN
    RETURN NEW;
  END IF;
  IF lower(btrim(COALESCE(v_role, ''))) IN ('tenant', 'vendor') THEN
    RAISE EXCEPTION 'subscription required to add properties or units'
      USING ERRCODE = '42501';
  END IF;

  v_plan := lower(btrim(COALESCE(v_plan, 'trial')));
  v_status := lower(btrim(COALESCE(v_status, 'trial')));
  v_extra := COALESCE(v_extra, 0);
  IF v_extra < 0 THEN
    v_extra := 0;
  END IF;

  IF v_plan = 'unlimited'
     AND v_status IN ('active', 'trialing', '') THEN
    RETURN NEW;
  END IF;

  IF NOT (
    (v_plan = 'essential' AND v_status IN ('active', 'trialing', ''))
    OR (
      v_plan IN ('trial', 'free', '')
      AND (v_trial IS NULL OR v_trial > now())
    )
  ) THEN
    RAISE EXCEPTION 'subscription required to add properties or units'
      USING ERRCODE = '42501';
  END IF;

  v_slots := 1 + v_extra;

  IF TG_TABLE_NAME = 'properties' THEN
    SELECT count(*) INTO v_properties
    FROM public.properties
    WHERE landlord_id = v_owner;
    IF v_properties >= v_slots THEN
      RAISE EXCEPTION 'essential plan property limit reached'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_units
  FROM public.units un
  LEFT JOIN public.properties pr ON pr.id = un.property_id
  WHERE un.landlord_id = v_owner
     OR pr.landlord_id = v_owner;

  IF v_units >= v_slots THEN
    RAISE EXCEPTION 'essential plan property limit reached'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_landlord_plan_limits ON public.properties;
CREATE TRIGGER enforce_landlord_plan_limits
  BEFORE INSERT ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_landlord_plan_limits();

DROP TRIGGER IF EXISTS enforce_landlord_plan_limits ON public.units;
CREATE TRIGGER enforce_landlord_plan_limits
  BEFORE INSERT ON public.units
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_landlord_plan_limits();

-- ── push: only someone who shares a unit or a repair job ──

-- FIX(run9): see fix3_push_scope.sql
CREATE OR REPLACE FUNCTION public.caller_may_push_to(p_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (SELECT auth.uid() AS id)
  SELECT (SELECT id FROM me) IS NOT NULL
    AND p_target IS NOT NULL
    AND (SELECT id FROM me) IS DISTINCT FROM p_target
    AND (
      EXISTS (
        SELECT 1
        FROM public.units u
        LEFT JOIN public.properties p ON p.id = u.property_id
        WHERE (
          COALESCE(u.landlord_id, p.landlord_id) = (SELECT id FROM me)
          AND u.tenant_id = p_target
        ) OR (
          COALESCE(u.landlord_id, p.landlord_id) = p_target
          AND u.tenant_id = (SELECT id FROM me)
        )
      )
      OR EXISTS (
        SELECT 1
        FROM public.maintenance_requests mr
        JOIN public.units u ON u.id::text = mr.unit_id::text
        LEFT JOIN public.properties p ON p.id = u.property_id
        CROSS JOIN LATERAL (VALUES ((SELECT id FROM me)), (p_target)) AS who(x)
        GROUP BY mr.id
        -- COALESCE: a NULL column must count as "not a party"; bool_and skips NULLs.
        HAVING bool_and(COALESCE(
          who.x = mr.landlord_id
          OR who.x = COALESCE(u.landlord_id, p.landlord_id)
          OR who.x = mr.vendor_user_id
          OR mr.vendor_id::text = who.x::text
          OR mr.vendor_id::text IN (
            SELECT v.id::text FROM public.vendors v
            JOIN public.users uu ON lower(uu.email) = lower(v.email)
            WHERE uu.id = who.x
          )
          OR (who.x = mr.tenant_id AND who.x = u.tenant_id)
        , false))
      )
    );
$$;

-- ── a unit claim needs a confirmed email ──
-- The insert trigger from 00 still calls this function. It now does
-- nothing until email_confirmed_at is set. A second trigger runs the
-- same link when confirmation lands. Confirmed accounts still link.

CREATE OR REPLACE FUNCTION public.auto_link_tenant_on_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.raw_user_meta_data ->> 'role', '') = 'tenant'
     AND NEW.email IS NOT NULL
     AND NEW.email_confirmed_at IS NOT NULL THEN
    UPDATE public.units
       SET tenant_id = NEW.id,
           status = 'occupied'
     WHERE tenant_id IS NULL
       AND invited_email IS NOT NULL
       AND lower(invited_email) = lower(NEW.email);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_email_confirmed ON auth.users;
CREATE TRIGGER on_auth_user_email_confirmed
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW
  WHEN (OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL)
  EXECUTE FUNCTION public.auto_link_tenant_on_signup();

CREATE OR REPLACE FUNCTION public.caller_email_confirmed()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = auth.uid()
      AND email_confirmed_at IS NOT NULL
  );
$$;

-- Blocks a new claim. An update that keeps the same tenant is left alone,
-- so someone already on the unit is not disturbed.
CREATE OR REPLACE FUNCTION public.units_require_confirmed_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.tenant_id IS NOT DISTINCT FROM OLD.tenant_id THEN
    RETURN NEW;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = NEW.tenant_id
      AND email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'confirm your email before claiming a unit'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS units_require_confirmed_email ON public.units;
CREATE TRIGGER units_require_confirmed_email
  BEFORE INSERT OR UPDATE OF tenant_id ON public.units
  FOR EACH ROW
  EXECUTE FUNCTION public.units_require_confirmed_email();

-- Same claim policy as 01, plus the confirmed-email check on a new claim.
-- The branch for the person who already lives there is unchanged.
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
      AND public.caller_email_confirmed()
    )
  )
  WITH CHECK (tenant_id = auth.uid());

-- ── grants ──

REVOKE ALL ON FUNCTION public.protect_subscription_columns() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.enforce_landlord_plan_limits() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.caller_may_push_to(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.caller_email_confirmed() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.units_require_confirmed_email() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.auto_link_tenant_on_signup() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.protect_subscription_columns() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enforce_landlord_plan_limits() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.caller_may_push_to(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.caller_email_confirmed() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.units_require_confirmed_email() TO authenticated, service_role;

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
      'GRANT EXECUTE ON FUNCTION public.auto_link_tenant_on_signup() TO %I',
      owner_name
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION public.units_require_confirmed_email() TO %I',
      owner_name
    );
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    GRANT EXECUTE ON FUNCTION public.auto_link_tenant_on_signup() TO supabase_auth_admin;
    GRANT EXECUTE ON FUNCTION public.units_require_confirmed_email() TO supabase_auth_admin;
  END IF;
END $$;

-- A unit insert must name a property that belongs to the same landlord.
-- RESTRICTIVE so it applies on top of the existing insert policies.
DROP POLICY IF EXISTS "units: property belongs to landlord" ON public.units;
CREATE POLICY "units: property belongs to landlord"
  ON public.units
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = units.property_id
        AND p.landlord_id = units.landlord_id
    )
  );

-- Record anon and PUBLIC privileges on the job-chat tables, then revoke
-- them. A second run keeps the first snapshot, so it does not record the
-- already-revoked state. Tables from 02 may be absent; those are skipped.
CREATE TABLE IF NOT EXISTS public.elevo_06_acl_backup (
  table_schema name NOT NULL,
  table_name name NOT NULL,
  grantee text NOT NULL,
  privilege_type text NOT NULL,
  PRIMARY KEY (table_schema, table_name, grantee, privilege_type)
);

ALTER TABLE public.elevo_06_acl_backup ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.elevo_06_acl_backup FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['job_chat_participants', 'job_chat_reads']
  LOOP
    IF to_regclass('public.' || tbl) IS NULL THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.elevo_06_acl_backup
      WHERE table_schema = 'public'
        AND table_name = tbl
    ) THEN
      INSERT INTO public.elevo_06_acl_backup
        (table_schema, table_name, grantee, privilege_type)
      VALUES ('public', tbl, 'snapshot', '');

      INSERT INTO public.elevo_06_acl_backup
        (table_schema, table_name, grantee, privilege_type)
      SELECT DISTINCT
             'public',
             tbl,
             CASE WHEN acl.grantee = 0 THEN 'PUBLIC'
                  ELSE pg_get_userbyid(acl.grantee)
             END,
             acl.privilege_type
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL aclexplode(c.relacl) AS acl
      WHERE n.nspname = 'public'
        AND c.relname = tbl
        AND c.relacl IS NOT NULL
        AND (
          acl.grantee = 0
          OR pg_get_userbyid(acl.grantee) = 'anon'
        )
        AND acl.privilege_type IN (
          'SELECT', 'INSERT', 'UPDATE', 'DELETE',
          'TRUNCATE', 'REFERENCES', 'TRIGGER'
        );
    END IF;

    EXECUTE format(
      'REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon',
      tbl
    );
  END LOOP;
END $$;

-- Last Stripe event time applied to each subscription, so an older
-- webhook delivery cannot overwrite a newer one.
CREATE TABLE IF NOT EXISTS public.stripe_applied_events (
  scope_key text PRIMARY KEY,
  user_id uuid,
  last_event_at timestamptz NOT NULL
);

ALTER TABLE public.stripe_applied_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.stripe_applied_events FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stripe_applied_events TO service_role;

-- Exact case-insensitive email match. ilike would treat _ and % as wildcards.
CREATE OR REPLACE FUNCTION public.user_ids_matching_email(p_email text)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id
  FROM public.users
  WHERE p_email IS NOT NULL
    AND btrim(p_email) <> ''
    AND lower(email) = lower(btrim(p_email));
$$;

REVOKE ALL ON FUNCTION public.user_ids_matching_email(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.user_ids_matching_email(text) TO service_role;

COMMIT;
