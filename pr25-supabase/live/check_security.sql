-- Practice checks for 01_live_security_fixes.sql.
-- Run with psql after 00 and 01, against the practice database.
-- All sample rows are rolled back.

BEGIN;

-- Structural: open policies are gone, realtime and buckets are right.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname IN (
      'Authenticated users read messages',
      'Authenticated users send messages',
      'Authenticated users update messages',
      'Vendor reads assigned maintenance',
      'Vendor updates assigned maintenance',
      'Tenants read own property',
      'Authenticated users can read vendors',
      'Admin reads applications',
      'Admin updates applications',
      'Anyone sends contact',
      'vendor_contacts: authenticated insert',
      'vendor_contacts: read by listing',
      'Authenticated users read documents',
      'Authenticated users view maintenance photos',
      'Tenants can read photo logs',
      'Public avatar read',
      'photo-logs: read own unit photos',
      'documents: landlords read properties docs',
      'maintenance-photos: landlords read all'
    )
  ) THEN
    RAISE EXCEPTION 'an open live policy is still installed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    RAISE EXCEPTION 'messages is not in supabase_realtime';
  END IF;

  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'unit_id')
     IS DISTINCT FROM 'text' THEN
    RAISE EXCEPTION 'messages.unit_id should stay text';
  END IF;

  IF (SELECT public FROM storage.buckets WHERE id = 'photo-logs') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'photo-logs bucket must be private';
  END IF;
  IF (SELECT public FROM storage.buckets WHERE id = 'documents') IS DISTINCT FROM false
     OR (SELECT public FROM storage.buckets WHERE id = 'avatars') IS DISTINCT FROM false
     OR (SELECT public FROM storage.buckets WHERE id = 'private-vault') IS DISTINCT FROM false
     OR (SELECT public FROM storage.buckets WHERE id = 'maintenance-photos') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'a private bucket flag changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'auth' AND c.relname = 'users'
      AND t.tgname = 'on_auth_user_created' AND NOT t.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'auth' AND c.relname = 'users'
      AND t.tgname = 'on_auth_user_created_ensure_row' AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'signup triggers are missing';
  END IF;
END $$;

-- Anonymous callers cannot execute the helpers.
SET ROLE anon;
DO $$
BEGIN
  PERFORM public.is_admin();
  RAISE EXCEPTION 'anon was allowed to call is_admin';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END $$;
RESET ROLE;

-- Accounts. The ensure trigger fills users/profiles. auto_link links the tenant.
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('11111111-1111-1111-1111-111111111111', 'landlord@example.com',
   '{"role":"landlord","full_name":"Land Lord","phone":"555"}'::jsonb);

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","email":"landlord@example.com"}',
  true);
SET ROLE authenticated;
INSERT INTO public.properties (id, landlord_id, name, address)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111', 'Oak', '1 Oak St');
INSERT INTO public.units (
  id, property_id, landlord_id, unit_number, status, rent_amount, deposit_amount, invited_email
) VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  '1', 'vacant', 1200, 500, 'tenant@example.com'
);
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('22222222-2222-2222-2222-222222222222', 'tenant@example.com',
   '{"role":"tenant","full_name":"Ten Ant"}'::jsonb),
  ('33333333-3333-3333-3333-333333333333', 'vendor@example.com',
   '{"role":"vendor","full_name":"Ven Dor"}'::jsonb),
  ('44444444-4444-4444-4444-444444444444', 'stranger@example.com',
   '{"role":"landlord","full_name":"Stranger"}'::jsonb),
  ('55555555-5555-5555-5555-555555555555', 'admin@example.com',
   '{"role":"landlord","full_name":"Admin"}'::jsonb);

UPDATE public.users
   SET role = 'admin'
 WHERE id = '55555555-5555-5555-5555-555555555555';

DO $$
BEGIN
  IF (SELECT role FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222')
     IS DISTINCT FROM 'tenant' THEN
    RAISE EXCEPTION 'tenant users row was not created with role tenant';
  END IF;
  IF (SELECT full_name FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222')
     IS DISTINCT FROM 'Ten Ant' THEN
    RAISE EXCEPTION 'tenant name was not copied from signup';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = '22222222-2222-2222-2222-222222222222'
  ) THEN
    RAISE EXCEPTION 'profiles row was not created';
  END IF;
  -- 06 waits for email_confirmed_at. Confirming the address runs the
  -- same link. Before 06 the column is absent and signup already linked.
  IF (SELECT tenant_id FROM public.units WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
     IS NULL
     AND EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'auth'
         AND table_name = 'users'
         AND column_name = 'email_confirmed_at'
     ) THEN
    UPDATE auth.users
       SET email_confirmed_at = now()
     WHERE id = '22222222-2222-2222-2222-222222222222'
       AND email_confirmed_at IS NULL;
  END IF;
  IF (SELECT tenant_id FROM public.units WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
     IS DISTINCT FROM '22222222-2222-2222-2222-222222222222'::uuid
     OR (SELECT status FROM public.units WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
        IS DISTINCT FROM 'occupied' THEN
    RAISE EXCEPTION 'auto_link_tenant_on_signup did not link the invited unit';
  END IF;
END $$;

-- Role change is blocked. A normal profile edit is not.
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","email":"tenant@example.com"}',
  true);
SET ROLE authenticated;
DO $$
BEGIN
  UPDATE public.users
     SET role = 'admin'
   WHERE id = '22222222-2222-2222-2222-222222222222';
  RAISE EXCEPTION 'self role change was allowed';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE '%only an admin can change an account role%' THEN
      RAISE;
    END IF;
END $$;
UPDATE public.users
   SET full_name = 'Ten Ant Updated'
 WHERE id = '22222222-2222-2222-2222-222222222222';
DO $$
BEGIN
  UPDATE public.units
     SET rent_amount = 1
   WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  RAISE EXCEPTION 'tenant was allowed to change rent';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE '%tenants may only claim%' THEN
      RAISE;
    END IF;
END $$;
RESET ROLE;

-- Landlord assigns a job and writes directory + listing rows.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","email":"landlord@example.com"}',
  true);
SET ROLE authenticated;
INSERT INTO public.vendors (id, landlord_id, name, email)
VALUES ('99999999-9999-9999-9999-999999999999',
        '11111111-1111-1111-1111-111111111111',
        'Ace', 'vendor@example.com');
INSERT INTO public.maintenance_requests (
  id, unit_id, landlord_id, tenant_id, vendor_id, vendor_user_id, description, status
) VALUES (
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '99999999-9999-9999-9999-999999999999',
  '33333333-3333-3333-3333-333333333333',
  'Leak', 'open'
);
INSERT INTO public.messages (unit_id, sender_id, receiver_id, content)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        'Hello tenant');
RESET ROLE;

-- Stranger cannot read or send that thread. text unit_id must not error.
SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","email":"stranger@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages;
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read messages (% rows)', n;
  END IF;
  BEGIN
    INSERT INTO public.messages (unit_id, sender_id, receiver_id, content)
    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            '44444444-4444-4444-4444-444444444444',
            '22222222-2222-2222-2222-222222222222',
            'nope');
    RAISE EXCEPTION 'stranger message was allowed';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE '%row-level security%' THEN
        RAISE;
      END IF;
  END;
  SELECT count(*) INTO n FROM public.maintenance_requests;
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read maintenance';
  END IF;
  SELECT count(*) INTO n FROM public.properties;
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read properties';
  END IF;
END $$;
RESET ROLE;

-- Tenant sees the message and can post the system welcome. Vendor note is visible to the landlord only.
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","email":"tenant@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages;
  IF n <> 1 THEN
    RAISE EXCEPTION 'tenant should see 1 message, saw %', n;
  END IF;
END $$;
INSERT INTO public.messages (unit_id, sender_id, receiver_id, content)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'system',
        '22222222-2222-2222-2222-222222222222',
        'welcome');
INSERT INTO public.messages (unit_id, sender_id, receiver_id, content)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333',
        'vendor note');
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","email":"vendor@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.maintenance_requests;
  IF n <> 1 THEN
    RAISE EXCEPTION 'vendor should see the assigned job, saw %', n;
  END IF;
  SELECT count(*) INTO n FROM public.units;
  IF n <> 1 THEN
    RAISE EXCEPTION 'vendor should see the job unit, saw %', n;
  END IF;
  SELECT count(*) INTO n
  FROM public.messages
  WHERE content = 'vendor note';
  IF n <> 1 THEN
    RAISE EXCEPTION 'vendor should see their own note, saw %', n;
  END IF;
  SELECT count(*) INTO n
  FROM public.messages
  WHERE content = 'Hello tenant';
  IF n <> 0 THEN
    RAISE EXCEPTION 'vendor can see the landlord-tenant thread';
  END IF;
END $$;
UPDATE public.maintenance_requests
   SET status = 'resolved',
       notes = 'done',
       resolved_date = now(),
       resolved_at = now(),
       completed_at = now()
 WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","email":"landlord@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages;
  IF n <> 3 THEN
    RAISE EXCEPTION 'landlord should see the whole unit thread, saw %', n;
  END IF;
END $$;
RESET ROLE;

-- Documents and storage are limited to people tied to the unit.
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","email":"tenant@example.com"}',
  true);
SET ROLE authenticated;
INSERT INTO storage.objects (bucket_id, name)
VALUES ('documents', '22222222-2222-2222-2222-222222222222/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease.pdf');
INSERT INTO public.documents (
  owner_id, landlord_id, tenant_id, unit_id, name, file_name, file_type, doc_type, file_url, file_size, file_size_bytes
) VALUES (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'lease.pdf', 'lease.pdf', 'Lease', 'Lease',
  'https://example.test/object/public/documents/22222222-2222-2222-2222-222222222222/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease.pdf',
  12, 12
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","email":"landlord@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'documents';
  IF n <> 1 THEN
    RAISE EXCEPTION 'landlord should read the unit file, saw %', n;
  END IF;
  SELECT count(*) INTO n FROM public.documents;
  IF n <> 1 THEN
    RAISE EXCEPTION 'landlord should read the document row, saw %', n;
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","email":"stranger@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'documents';
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read documents storage';
  END IF;
  SELECT count(*) INTO n FROM public.documents;
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read document rows';
  END IF;
  BEGIN
    INSERT INTO storage.objects (bucket_id, name)
    VALUES ('documents', '22222222-2222-2222-2222-222222222222/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/evil.pdf');
    RAISE EXCEPTION 'stranger uploaded into someone else''s folder';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END $$;
RESET ROLE;

-- Partner message uses sender_id, listing_id, and message.
SELECT set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","email":"admin@example.com"}',
  true);
SET ROLE authenticated;
INSERT INTO public.partner_listings (id, name, business_name, email, status)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Ace', 'Ace', 'vendor@example.com', 'active');
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","email":"tenant@example.com"}',
  true);
SET ROLE authenticated;
INSERT INTO public.vendor_contacts (sender_id, listing_id, message)
VALUES ('22222222-2222-2222-2222-222222222222',
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'Can you come Tuesday?');
INSERT INTO public.vendor_applications (name, business_name, email, status)
VALUES ('Other Co', 'Other Co', 'other@example.com', 'pending');
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","email":"vendor@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.vendor_contacts;
  IF n <> 1 THEN
    RAISE EXCEPTION 'listing owner should read the contact, saw %', n;
  END IF;
  SELECT count(*) INTO n FROM public.vendor_applications;
  IF n <> 0 THEN
    RAISE EXCEPTION 'vendor can read applications';
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","email":"admin@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.vendor_applications;
  IF n <> 1 THEN
    RAISE EXCEPTION 'admin should read applications, saw %', n;
  END IF;
END $$;
RESET ROLE;

-- Expenses are landlord-only.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","email":"landlord@example.com"}',
  true);
SET ROLE authenticated;
INSERT INTO public.expenses (landlord_id, description, amount, category, expense_date)
VALUES ('11111111-1111-1111-1111-111111111111', 'Filter', 20, 'hvac', CURRENT_DATE);
INSERT INTO public.announcements (landlord_id, subject, message, recipient_count)
VALUES ('11111111-1111-1111-1111-111111111111', 'Hi', 'All', 1);
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","email":"stranger@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.expenses;
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read expenses';
  END IF;
  SELECT count(*) INTO n FROM public.announcements;
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read announcements';
  END IF;
END $$;
RESET ROLE;

-- Photo logs are private. Landlord, tenant, and the assigned vendor can read.
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","email":"tenant@example.com"}',
  true);
SET ROLE authenticated;
INSERT INTO storage.objects (bucket_id, name)
VALUES (
  'photo-logs',
  '22222222-2222-2222-2222-222222222222/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/kitchen.jpg'
);
INSERT INTO public.photo_logs (unit_id, room, storage_path, public_url)
VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'Kitchen',
  '22222222-2222-2222-2222-222222222222/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/kitchen.jpg',
  'https://example.test/storage/v1/object/public/photo-logs/22222222-2222-2222-2222-222222222222/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/kitchen.jpg'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","email":"vendor@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'photo-logs';
  IF n <> 1 THEN
    RAISE EXCEPTION 'vendor should read the job photo, saw %', n;
  END IF;
  SELECT count(*) INTO n FROM public.photo_logs;
  IF n <> 1 THEN
    RAISE EXCEPTION 'vendor should read the photo log row, saw %', n;
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","email":"stranger@example.com"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'photo-logs';
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read photo logs';
  END IF;
  SELECT count(*) INTO n FROM public.photo_logs;
  IF n <> 0 THEN
    RAISE EXCEPTION 'stranger can read photo log rows';
  END IF;
END $$;
RESET ROLE;

-- An invited person can see the unclaimed unit and claim it.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
INSERT INTO public.units (
  id, property_id, landlord_id, unit_number, status, rent_amount, deposit_amount, invited_email
) VALUES (
  'bcbcbcbc-bcbc-bcbc-bcbc-bcbcbcbcbcbc',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  '2', 'vacant', 900, 0, 'stranger@example.com'
);
SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","email":"stranger@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.units WHERE id = 'bcbcbcbc-bcbc-bcbc-bcbc-bcbcbcbcbcbc';
  IF n <> 1 THEN
    RAISE EXCEPTION 'invited tenant cannot see the unclaimed unit';
  END IF;
END $$;
UPDATE public.units
   SET tenant_id = '44444444-4444-4444-4444-444444444444',
       status = 'occupied'
 WHERE id = 'bcbcbcbc-bcbc-bcbc-bcbc-bcbcbcbcbcbc';
RESET ROLE;

-- A signed-in account must not insert its own users row as admin.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES ('abababab-abab-abab-abab-abababababab', 'gap@example.com', '{}'::jsonb);
DELETE FROM public.profiles WHERE id = 'abababab-abab-abab-abab-abababababab';
DELETE FROM public.users WHERE id = 'abababab-abab-abab-abab-abababababab';
SELECT set_config('request.jwt.claim.sub', 'abababab-abab-abab-abab-abababababab', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"abababab-abab-abab-abab-abababababab","email":"gap@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
BEGIN
  INSERT INTO public.users (id, email, full_name, role)
  VALUES ('abababab-abab-abab-abab-abababababab', 'gap@example.com', 'Gap', 'admin');
  RAISE EXCEPTION 'self insert as admin was allowed';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END $$;
RESET ROLE;

-- Blank receivers from before this tenancy stay blank. Later ones are filled.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
UPDATE public.units
   SET tenant_since = '2026-06-01 00:00:00+00'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
INSERT INTO public.messages (id, unit_id, sender_id, receiver_id, content, created_at)
VALUES
  ('15151515-1515-1515-1515-151515151515',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '11111111-1111-1111-1111-111111111111', '', 'old blank',
   '2026-01-01 00:00:00+00'),
  ('16161616-1616-1616-1616-161616161616',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '11111111-1111-1111-1111-111111111111', '', 'new blank',
   '2026-07-01 00:00:00+00');
UPDATE public.messages m
   SET receiver_id = u.tenant_id::text
  FROM public.units u
 WHERE m.unit_id = u.id::text
   AND u.tenant_id IS NOT NULL
   AND m.created_at IS NOT NULL
   AND m.created_at >= COALESCE(u.tenant_since, u.lease_start::timestamptz, u.created_at)
   AND (m.receiver_id IS NULL OR btrim(m.receiver_id) = '')
   AND (
     m.sender_id = u.landlord_id::text
     OR lower(btrim(m.sender_id)) = 'system'
   );
DO $$
BEGIN
  IF (SELECT btrim(receiver_id) FROM public.messages
      WHERE id = '15151515-1515-1515-1515-151515151515') <> '' THEN
    RAISE EXCEPTION 'a blank message from before the tenancy was reassigned';
  END IF;
  IF (SELECT receiver_id FROM public.messages
      WHERE id = '16161616-1616-1616-1616-161616161616')
     IS DISTINCT FROM '22222222-2222-2222-2222-222222222222' THEN
    RAISE EXCEPTION 'a blank message from this tenancy was not filled';
  END IF;
END $$;
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","email":"tenant@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages
   WHERE id = '15151515-1515-1515-1515-151515151515';
  IF n <> 0 THEN
    RAISE EXCEPTION 'current tenant can read a blank message from before their tenancy';
  END IF;
  INSERT INTO public.payments (tenant_id, unit_id, amount, status)
  VALUES (
    '11111111-1111-1111-1111-111111111111',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    10, 'pending_confirmation'
  );
  RAISE EXCEPTION 'tenant filed a payment as someone else';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END $$;
INSERT INTO public.payments (tenant_id, unit_id, amount, status)
VALUES (
  '22222222-2222-2222-2222-222222222222',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  10, 'pending_confirmation'
);
RESET ROLE;

-- An untagged landlord lease from before the claim stays open.
-- A file the landlord uploaded for the former tenant stays closed,
-- even when the path starts with the landlord. Photo logs from before
-- this tenancy stay closed too.
INSERT INTO storage.objects (bucket_id, name, created_at) VALUES
  ('documents', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease.pdf',
   '2026-01-02 00:00:00+00'),
  ('documents', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/welcome-packet.pdf',
   '2026-01-02 00:00:00+00'),
  ('documents', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease_old.pdf',
   '2026-01-03 00:00:00+00'),
  ('documents', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/t2_lease2.pdf',
   '2026-01-03 00:00:00+00'),
  ('documents', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/l2.pdf',
   '2026-01-03 00:00:00+00'),
  ('documents', '44444444-4444-4444-4444-444444444444/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old.pdf',
   '2026-01-03 00:00:00+00'),
  ('photo-logs', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/welcome.jpg',
   '2026-01-04 00:00:00+00'),
  ('photo-logs', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old_moveout.jpg',
   '2026-01-04 00:00:00+00'),
  ('photo-logs', '44444444-4444-4444-4444-444444444444/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old.jpg',
   '2026-01-05 00:00:00+00');
INSERT INTO public.documents (
  owner_id, landlord_id, tenant_id, unit_id, name, file_name, file_type, doc_type, file_url, created_at
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111',
  NULL,
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'landlord-lease.pdf',
  'landlord-lease.pdf',
  'Lease',
  'Lease',
  'https://example.test/11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease.pdf',
  '2026-01-02 00:00:00+00'
);
INSERT INTO public.documents (
  owner_id, landlord_id, tenant_id, unit_id, name, file_url, created_at
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'welcome-packet.pdf',
  'https://example.test/11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/welcome-packet.pdf',
  '2026-01-02 00:00:00+00'
), (
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111',
  '44444444-4444-4444-4444-444444444444',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'lease_old.pdf',
  'https://example.test/11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease_old.pdf',
  '2026-01-03 00:00:00+00'
), (
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111',
  '44444444-4444-4444-4444-444444444444',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  't2_lease2.pdf',
  'https://example.test/11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/t2_lease2.pdf',
  '2026-01-03 00:00:00+00'
), (
  '11111111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111',
  '44444444-4444-4444-4444-444444444444',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'l2.pdf',
  'https://example.test/11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/l2.pdf',
  '2026-01-03 00:00:00+00'
), (
  '44444444-4444-4444-4444-444444444444',
  '11111111-1111-1111-1111-111111111111',
  '44444444-4444-4444-4444-444444444444',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'old.pdf',
  'https://example.test/44444444-4444-4444-4444-444444444444/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old.pdf',
  '2026-01-03 00:00:00+00'
);
INSERT INTO public.photo_logs (unit_id, room, storage_path, created_at) VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'Welcome',
   '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/welcome.jpg',
   '2026-01-04 00:00:00+00'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'Moveout OLD',
   '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old_moveout.jpg',
   '2026-01-04 00:00:00+00'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'Old kitchen',
   '44444444-4444-4444-4444-444444444444/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old.jpg',
   '2026-01-05 00:00:00+00');
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","email":"tenant@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.documents WHERE name = 'landlord-lease.pdf';
  IF n <> 1 THEN
    RAISE EXCEPTION 'tenant cannot see the untagged landlord lease uploaded before they claimed';
  END IF;
  SELECT count(*) INTO n FROM public.documents WHERE name = 'welcome-packet.pdf';
  IF n <> 1 THEN
    RAISE EXCEPTION 'tenant cannot see a landlord file tagged to them';
  END IF;
  SELECT count(*) INTO n FROM public.documents
   WHERE name IN ('old.pdf', 'lease_old.pdf', 't2_lease2.pdf', 'l2.pdf');
  IF n <> 0 THEN
    RAISE EXCEPTION 'tenant can see a document tagged to the former tenant';
  END IF;
  IF NOT public.can_read_storage_object(
    'documents',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease.pdf'
  ) THEN
    RAISE EXCEPTION 'tenant cannot open the untagged landlord lease file';
  END IF;
  IF NOT public.can_read_storage_object(
    'documents',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/welcome-packet.pdf'
  ) THEN
    RAISE EXCEPTION 'tenant cannot open a landlord file tagged to them';
  END IF;
  IF public.can_read_storage_object(
    'documents',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease_old.pdf'
  ) OR public.can_read_storage_object(
    'documents',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/t2_lease2.pdf'
  ) OR public.can_read_storage_object(
    'documents',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/l2.pdf'
  ) OR public.can_read_storage_object(
    'documents',
    '44444444-4444-4444-4444-444444444444/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old.pdf'
  ) THEN
    RAISE EXCEPTION 'tenant can open a file tagged to the former tenant';
  END IF;
  SELECT count(*) INTO n FROM public.photo_logs WHERE room = 'Moveout OLD';
  IF n <> 0 THEN
    RAISE EXCEPTION 'tenant can see the Moveout OLD photo log';
  END IF;
  SELECT count(*) INTO n FROM public.photo_logs
   WHERE storage_path LIKE '11111111-1111-1111-1111-111111111111/%'
      OR storage_path LIKE '44444444-4444-4444-4444-444444444444/%';
  IF n <> 0 THEN
    RAISE EXCEPTION 'tenant can see a photo log from before their tenancy';
  END IF;
  IF public.can_read_storage_object(
    'photo-logs',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old_moveout.jpg'
  ) OR public.can_read_storage_object(
    'photo-logs',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/welcome.jpg'
  ) OR public.can_read_storage_object(
    'photo-logs',
    '44444444-4444-4444-4444-444444444444/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old.jpg'
  ) THEN
    RAISE EXCEPTION 'tenant can open a photo log file from before their tenancy';
  END IF;
END $$;
RESET ROLE;

ROLLBACK;
