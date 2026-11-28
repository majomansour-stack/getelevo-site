-- Rolls back 10_landlord_card_trial.sql. Not applied by the app.
-- Does not update existing rows, and does not undo 08_trial7_property_caps.sql.
--
-- What it puts back:
--   * ensure_app_user_row again sets trial_ends_at to now() + 7 days for
--     every new account, including landlords. If a users row already
--     exists with a null trial end, that null is filled with the same date.
--   * protect_subscription_columns, on a signed-in INSERT, again sets the
--     plan and status to trial and, for every role, fills a missing or
--     too-far trial end with now() + 7 days.

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
