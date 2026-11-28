-- ============================================================
-- ELEVO — stop the card-free 7-day trial for new landlords.
--
-- Not applied by the app. Run in the Supabase SQL editor after the
-- already-applied 08_trial7_property_caps.sql (which follows 06 and 07).
-- Safe to run again.
-- Does not change existing rows.
--
-- New landlord (and blank-role) rows get trial_ends_at = now(),
-- which the app treats as an ended trial, so they must choose a
-- Stripe plan. Tenants and vendors still get now() + 7 days.
-- A null trial end on an existing row is left alone.
-- ============================================================

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
  v_trial timestamptz := CASE
    WHEN v_role IN ('tenant', 'vendor') THEN now() + interval '7 days'
    ELSE now()
  END;
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
           trial_ends_at = CASE
             WHEN v_role IN ('tenant', 'vendor') THEN COALESCE(trial_ends_at, v_trial)
             ELSE trial_ends_at
           END
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

CREATE OR REPLACE FUNCTION public.protect_subscription_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  locked boolean;
  old_plan text;
  new_plan text;
  who text;
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
    who := lower(btrim(COALESCE(NEW.role, '')));
    IF who IN ('tenant', 'vendor') THEN
      IF NEW.trial_ends_at IS NULL
         OR NEW.trial_ends_at > now() + interval '8 days' THEN
        NEW.trial_ends_at := now() + interval '7 days';
      END IF;
    ELSE
      NEW.trial_ends_at := now();
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
