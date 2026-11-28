-- Practice checks for 05_repair_photos.sql.
-- Run after 00, 01, and 05. Sample rows are rolled back.

BEGIN;

SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('11111111-1111-1111-1111-111111111111', 'landlord@example.com', '{"role":"landlord","full_name":"Land Lord"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'tenant@example.com', '{"role":"tenant","full_name":"Ten Ant"}'::jsonb),
  ('99999999-9999-9999-9999-999999999999', 'next@example.com', '{"role":"tenant","full_name":"Next"}'::jsonb),
  ('33333333-3333-3333-3333-333333333333', 'vendor@example.com', '{"role":"vendor","full_name":"Ven Dor"}'::jsonb),
  ('44444444-4444-4444-4444-444444444444', 'stranger@example.com', '{"role":"landlord","full_name":"Stranger"}'::jsonb);

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","email":"landlord@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
INSERT INTO public.properties (id, landlord_id, name, address)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'Oak', '1 Oak');
INSERT INTO public.units (
  id, property_id, landlord_id, tenant_id, unit_number, status, rent_amount, deposit_amount
) VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '1', 'occupied', 1000, 0
);
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
UPDATE public.units
   SET tenant_since = '2026-01-01 00:00:00+00'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
INSERT INTO public.maintenance_requests (
  id, unit_id, landlord_id, tenant_id, description, status, vendor_user_id, created_at, photo_paths
) VALUES (
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'Leak', 'open',
  '33333333-3333-3333-3333-333333333333',
  '2026-02-01 00:00:00+00',
  '["dddddddd-dddd-dddd-dddd-dddddddddddd/1_leak.jpg"]'::jsonb
);
INSERT INTO storage.objects (bucket_id, name, created_at) VALUES (
  'maintenance-photos',
  'dddddddd-dddd-dddd-dddd-dddddddddddd/1_leak.jpg',
  '2026-02-01 00:00:00+00'
);

SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","email":"tenant@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects
   WHERE bucket_id = 'maintenance-photos'
     AND name = 'dddddddd-dddd-dddd-dddd-dddddddddddd/1_leak.jpg';
  IF n <> 1 THEN
    RAISE EXCEPTION 'the current tenant cannot read their repair photo';
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","email":"landlord@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects
   WHERE bucket_id = 'maintenance-photos'
     AND name = 'dddddddd-dddd-dddd-dddd-dddddddddddd/1_leak.jpg';
  IF n <> 1 THEN
    RAISE EXCEPTION 'the landlord cannot read the repair photo';
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333","email":"vendor@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects
   WHERE bucket_id = 'maintenance-photos'
     AND name = 'dddddddd-dddd-dddd-dddd-dddddddddddd/1_leak.jpg';
  IF n <> 1 THEN
    RAISE EXCEPTION 'the assigned vendor cannot read the repair photo';
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","email":"stranger@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects
   WHERE bucket_id = 'maintenance-photos'
     AND name = 'dddddddd-dddd-dddd-dddd-dddddddddddd/1_leak.jpg';
  IF n <> 0 THEN
    RAISE EXCEPTION 'a stranger can read the repair photo';
  END IF;
END $$;
RESET ROLE;

-- Move the original tenant out. They, and the next tenant, cannot read it.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
UPDATE public.units
   SET tenant_id = '99999999-9999-9999-9999-999999999999',
       status = 'occupied'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
UPDATE public.units
   SET tenant_since = '2026-06-01 00:00:00+00'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","email":"tenant@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects
   WHERE bucket_id = 'maintenance-photos'
     AND name = 'dddddddd-dddd-dddd-dddd-dddddddddddd/1_leak.jpg';
  IF n <> 0 THEN
    RAISE EXCEPTION 'a former tenant can still read the repair photo';
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999999","email":"next@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects
   WHERE bucket_id = 'maintenance-photos'
     AND name = 'dddddddd-dddd-dddd-dddd-dddddddddddd/1_leak.jpg';
  IF n <> 0 THEN
    RAISE EXCEPTION 'the next tenant can read a repair photo from before they moved in';
  END IF;
END $$;
RESET ROLE;

ROLLBACK;
