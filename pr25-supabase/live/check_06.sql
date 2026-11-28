-- Checks for 06_subscriptions_push_email_rentspree.sql.
-- Run after 00, 01, and 06, on the practice database. Not for live.
-- Sample rows are rolled back. The file is one transaction so the
-- JWT settings stay in place, same as check_security.sql.

BEGIN;

-- A signed-in landlord cannot grant themselves a paid plan, and can
-- still write the trial value signup uses.
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', 'plan-landlord@example.com',
   '{"role":"landlord","full_name":"Plan Lord"}'::jsonb);

SELECT set_config('request.jwt.claim.sub', 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1","role":"authenticated","email":"plan-landlord@example.com"}',
  true);
SET ROLE authenticated;

UPDATE public.users
   SET full_name = 'Plan Lord Saved',
       subscription_plan = 'trial'
 WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1';

UPDATE public.users
   SET subscription_plan = 'unlimited',
       subscription_status = 'active',
       stripe_customer_id = 'cus_nope',
       extra_property_count = 9
 WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1';

DO $$
BEGIN
  IF (SELECT full_name FROM public.users WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1')
     IS DISTINCT FROM 'Plan Lord Saved' THEN
    RAISE EXCEPTION 'signup-style profile update did not save the name';
  END IF;
  IF (SELECT subscription_plan FROM public.users WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1')
     IS DISTINCT FROM 'trial'
     OR (SELECT stripe_customer_id FROM public.users WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1')
        IS NOT NULL
     OR (SELECT extra_property_count FROM public.users WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1')
        IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'a signed-in user changed their own plan';
  END IF;
END $$;

INSERT INTO public.properties (id, landlord_id, name, address)
VALUES ('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6a1',
        'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', 'One', '1 Plan St');

DO $$
BEGIN
  INSERT INTO public.properties (id, landlord_id, name, address)
  VALUES ('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6a2',
          'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', 'Two', '2 Plan St');
  RAISE EXCEPTION 'second property was allowed on a trial';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE '%property limit%' THEN
      RAISE;
    END IF;
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

-- No user JWT: the SQL editor (and the webhook's service role) may set the plan.
UPDATE public.users
   SET subscription_plan = 'essential',
       subscription_status = 'active',
       extra_property_count = 1,
       stripe_customer_id = 'cus_ok'
 WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1';

SELECT set_config('request.jwt.claim.sub', 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1","role":"authenticated","email":"plan-landlord@example.com"}',
  true);
SET ROLE authenticated;

INSERT INTO public.properties (id, landlord_id, name, address)
VALUES ('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6a2',
        'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', 'Two', '2 Plan St');

DO $$
BEGIN
  INSERT INTO public.properties (id, landlord_id, name, address)
  VALUES ('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6a3',
          'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', 'Three', '3 Plan St');
  RAISE EXCEPTION 'third property was allowed with one extra';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE '%property limit%' THEN
      RAISE;
    END IF;
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

-- An unconfirmed tenant cannot claim. Confirming the email does.
INSERT INTO public.units (
  id, property_id, landlord_id, unit_number, status, invited_email
) VALUES (
  'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6b1',
  'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6a1',
  'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1',
  'A', 'vacant', 'unconfirmed@example.com'
);

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c2', 'unconfirmed@example.com',
   '{"role":"tenant","full_name":"Not Yet"}'::jsonb);

DO $$
BEGIN
  IF (SELECT tenant_id FROM public.units WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6b1')
     IS NOT NULL THEN
    RAISE EXCEPTION 'unconfirmed signup claimed a unit';
  END IF;
END $$;

SELECT set_config('request.jwt.claim.sub', 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c2', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c2","role":"authenticated","email":"unconfirmed@example.com"}',
  true);
SET ROLE authenticated;

UPDATE public.units
   SET tenant_id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c2',
       status = 'occupied'
 WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6b1';

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

DO $$
BEGIN
  IF (SELECT tenant_id FROM public.units WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6b1')
     IS NOT NULL THEN
    RAISE EXCEPTION 'unconfirmed tenant update was allowed';
  END IF;
END $$;

-- The landlord can see the unit, so the trigger (not just RLS) has to refuse.
SELECT set_config('request.jwt.claim.sub', 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1","role":"authenticated","email":"plan-landlord@example.com"}',
  true);
SET ROLE authenticated;

DO $$
BEGIN
  UPDATE public.units
     SET tenant_id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c2',
         status = 'occupied'
   WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6b1';
  RAISE EXCEPTION 'landlord assigned an unconfirmed tenant';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE '%confirm your email%' THEN
      RAISE;
    END IF;
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

UPDATE auth.users
   SET email_confirmed_at = now()
 WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c2';

DO $$
BEGIN
  IF (SELECT tenant_id FROM public.units WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6b1')
     IS DISTINCT FROM 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c2'::uuid THEN
    RAISE EXCEPTION 'confirmed email did not link the unit';
  END IF;
END $$;

-- A confirmed signup still links immediately.
INSERT INTO public.units (
  id, property_id, landlord_id, unit_number, status, invited_email
) VALUES (
  'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6b2',
  'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6a1',
  'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1',
  'B', 'vacant', 'confirmed@example.com'
);

INSERT INTO auth.users (id, email, email_confirmed_at, raw_user_meta_data) VALUES
  ('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c3', 'confirmed@example.com', now(),
   '{"role":"tenant","full_name":"Already Confirmed"}'::jsonb);

DO $$
BEGIN
  IF (SELECT tenant_id FROM public.units WHERE id = 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6b2')
     IS DISTINCT FROM 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c3'::uuid THEN
    RAISE EXCEPTION 'confirmed signup was not linked';
  END IF;
END $$;

-- Push only when the two people share the unit.
SELECT set_config('request.jwt.claim.sub', 'c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1","role":"authenticated"}',
  true);

DO $$
BEGIN
  IF NOT public.caller_may_push_to('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c3') THEN
    RAISE EXCEPTION 'landlord could not notify their tenant';
  END IF;
  IF public.caller_may_push_to('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c1') THEN
    RAISE EXCEPTION 'a person was allowed to notify themselves';
  END IF;
END $$;

-- anon cannot call the helper.
SET ROLE anon;
DO $$
BEGIN
  PERFORM public.caller_may_push_to('c6c6c6c6-c6c6-c6c6-c6c6-c6c6c6c6c6c3');
  RAISE EXCEPTION 'anon was allowed to call caller_may_push_to';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END $$;
RESET ROLE;

ROLLBACK;
