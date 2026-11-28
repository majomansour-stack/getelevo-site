-- Apply after 20261128120000_vendor_unit_folder_read.sql.
-- Landlord referral codes. Does not create a Stripe coupon.
-- A landlord can read only their own code. Referral rows are written and
-- read through security-definer functions so nobody can list every code.

CREATE TABLE IF NOT EXISTS public.referral_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES public.users (id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT referral_codes_format
    CHECK (code ~ '^ELEVO-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$')
);

CREATE TABLE IF NOT EXISTS public.referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  referred_id uuid NOT NULL UNIQUE REFERENCES public.users (id) ON DELETE CASCADE,
  code text NOT NULL,
  status text NOT NULL DEFAULT 'linked',
  referred_coupon_applied boolean NOT NULL DEFAULT false,
  referrer_coupon_applied boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT referrals_not_self CHECK (referrer_id <> referred_id),
  CONSTRAINT referrals_status CHECK (status IN ('linked', 'reward_pending', 'rewarded'))
);

ALTER TABLE public.referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "referral_codes: landlord reads own" ON public.referral_codes;
CREATE POLICY "referral_codes: landlord reads own"
  ON public.referral_codes
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    AND public.current_user_role() IN ('landlord', 'admin')
  );

REVOKE ALL ON public.referral_codes FROM PUBLIC, anon;
REVOKE ALL ON public.referrals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.referral_codes TO authenticated;
GRANT ALL ON public.referral_codes TO service_role;
GRANT ALL ON public.referrals TO service_role;

CREATE OR REPLACE FUNCTION public.generate_referral_code()
RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
  attempt int;
  n int;
BEGIN
  FOR attempt IN 1..30 LOOP
    candidate := 'ELEVO-';
    FOR n IN 1..4 LOOP
      candidate := candidate || substr(
        alphabet,
        1 + floor(random() * length(alphabet))::int,
        1
      );
    END LOOP;
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.referral_codes WHERE code = candidate
    );
  END LOOP;
  RETURN candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_landlord_referral_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  existing text;
  role text;
  created text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Sign in is required';
  END IF;
  SELECT u.role INTO role FROM public.users u WHERE u.id = uid;
  IF role IS DISTINCT FROM 'landlord' AND role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Only a landlord has a referral code';
  END IF;
  SELECT code INTO existing FROM public.referral_codes WHERE user_id = uid;
  IF existing IS NOT NULL THEN
    RETURN existing;
  END IF;
  created := public.generate_referral_code();
  INSERT INTO public.referral_codes (user_id, code) VALUES (uid, created);
  RETURN created;
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_landlord_referral_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IN ('landlord', 'admin') THEN
    INSERT INTO public.referral_codes (user_id, code)
    VALUES (NEW.id, public.generate_referral_code())
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_landlord_referral_code ON public.users;
CREATE TRIGGER assign_landlord_referral_code
  AFTER INSERT ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_landlord_referral_code();

INSERT INTO public.referral_codes (user_id, code)
SELECT u.id, public.generate_referral_code()
FROM public.users u
WHERE u.role IN ('landlord', 'admin')
  AND NOT EXISTS (
    SELECT 1 FROM public.referral_codes c WHERE c.user_id = u.id
  );

CREATE OR REPLACE FUNCTION public.claim_referral_code(p_code text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  normalized text := upper(btrim(COALESCE(p_code, '')));
  owner uuid;
  role text;
  sub_id text;
  status text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Sign in is required';
  END IF;
  SELECT u.role, u.stripe_subscription_id, u.subscription_status
    INTO role, sub_id, status
  FROM public.users u
  WHERE u.id = uid;
  IF role IS DISTINCT FROM 'landlord' AND role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Only a landlord can use a referral code';
  END IF;
  IF normalized !~ '^ELEVO-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$' THEN
    RAISE EXCEPTION 'That code is not valid';
  END IF;
  SELECT user_id INTO owner FROM public.referral_codes WHERE code = normalized;
  IF owner IS NULL THEN
    RAISE EXCEPTION 'That code is not valid';
  END IF;
  IF owner = uid THEN
    RAISE EXCEPTION 'You cannot use your own code';
  END IF;
  IF EXISTS (SELECT 1 FROM public.referrals WHERE referred_id = uid) THEN
    RAISE EXCEPTION 'This account already used a referral code';
  END IF;
  IF NULLIF(btrim(COALESCE(sub_id, '')), '') IS NOT NULL
     OR lower(COALESCE(status, '')) IN ('active', 'trialing') THEN
    RAISE EXCEPTION 'Referral codes are only for a new landlord account';
  END IF;
  INSERT INTO public.referrals (referrer_id, referred_id, code, status)
  VALUES (owner, uid, normalized, 'linked');
  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION public.my_referral_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  role text;
  own_code text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Sign in is required';
  END IF;
  SELECT u.role INTO role FROM public.users u WHERE u.id = uid;
  IF role IS DISTINCT FROM 'landlord' AND role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Only a landlord has a referral code';
  END IF;
  SELECT code INTO own_code FROM public.referral_codes WHERE user_id = uid;
  RETURN jsonb_build_object(
    'code', own_code,
    'count', (
      SELECT count(*) FROM public.referrals r WHERE r.referrer_id = uid
    ),
    'used_code', (
      SELECT r.code FROM public.referrals r WHERE r.referred_id = uid
    ),
    'referrals', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'first_name', split_part(COALESCE(u.full_name, ''), ' ', 1),
        'status', r.status
      ) ORDER BY r.created_at DESC)
      FROM public.referrals r
      JOIN public.users u ON u.id = r.referred_id
      WHERE r.referrer_id = uid
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.generate_referral_code() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ensure_landlord_referral_code() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_landlord_referral_code() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_referral_code(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.my_referral_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_referral_code() TO service_role;
GRANT EXECUTE ON FUNCTION public.ensure_landlord_referral_code() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_referral_code(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.my_referral_dashboard() TO authenticated, service_role;
