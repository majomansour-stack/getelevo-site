-- Practice checks for 02_job_group_chat.sql.
-- Run after 00, 01, and 02. Sample rows are rolled back.

BEGIN;

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('11111111-1111-1111-1111-111111111111', 'landlord@example.com', '{"role":"landlord","full_name":"Land Lord"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'tenant@example.com', '{"role":"tenant","full_name":"Ten Ant"}'::jsonb),
  ('33333333-3333-3333-3333-333333333333', 'vendor@example.com', '{"role":"vendor","full_name":"Ven Dor"}'::jsonb),
  ('88888888-8888-8888-8888-888888888888', 'vendor2@example.com', '{"role":"vendor","full_name":"New Vendor"}'::jsonb),
  ('44444444-4444-4444-4444-444444444444', 'stranger@example.com', '{"role":"landlord","full_name":"Stranger"}'::jsonb),
  ('99999999-9999-9999-9999-999999999999', 'nexttenant@example.com', '{"role":"tenant","full_name":"Next Tenant"}'::jsonb),
  ('55555555-5555-5555-5555-555555555555', 'admin@example.com', '{"role":"landlord","full_name":"Admin"}'::jsonb);

UPDATE public.users SET role = 'admin'
 WHERE id = '55555555-5555-5555-5555-555555555555';

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","email":"landlord@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
INSERT INTO public.properties (id, landlord_id, name, address)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111', 'Oak', '1 Oak');
INSERT INTO public.units (
  id, property_id, landlord_id, unit_number, status, rent_amount, deposit_amount, tenant_id
) VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  '1', 'occupied', 1000, 0,
  '22222222-2222-2222-2222-222222222222'
);
INSERT INTO public.maintenance_requests (
  id, unit_id, landlord_id, tenant_id, description, status
) VALUES (
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'Leak', 'open'
);
UPDATE public.maintenance_requests
   SET vendor_user_id = '33333333-3333-3333-3333-333333333333'
 WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
INSERT INTO public.messages (id, unit_id, sender_id, receiver_id, content)
VALUES (
  '12121212-1212-1212-1212-121212121212',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '1:1 hello'
);
INSERT INTO public.messages (
  id, unit_id, maintenance_request_id, sender_id, receiver_id, content
) VALUES (
  '13131313-1313-1313-1313-131313131313',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  '11111111-1111-1111-1111-111111111111',
  NULL,
  'job hello'
);
RESET ROLE;

-- Pin the first job message to the original vendor's time on the thread.
UPDATE public.messages
   SET created_at = '2026-04-01 12:00:00+00'
 WHERE id = '13131313-1313-1313-1313-131313131313';
UPDATE public.job_chat_participants
   SET joined_at = '2026-04-01 11:00:00+00'
 WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

DO $$
BEGIN
  IF (SELECT count(*) FROM public.job_chat_participants
      WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        AND left_at IS NULL) <> 3 THEN
    RAISE EXCEPTION 'job should have landlord, tenant, and vendor';
  END IF;
END $$;

-- Stranger, admin, and a later tenant cannot read the job thread.
UPDATE public.units
   SET tenant_id = '99999999-9999-9999-9999-999999999999'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

SELECT set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999999","email":"nexttenant@example.com"}', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages
   WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  IF n <> 0 THEN
    RAISE EXCEPTION 'a later tenant can read the job chat';
  END IF;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555","email":"admin@example.com"}', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages
   WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  IF n <> 0 THEN
    RAISE EXCEPTION 'an admin can read the job chat';
  END IF;
  BEGIN
    INSERT INTO public.messages (
      unit_id, maintenance_request_id, sender_id, receiver_id, content
    ) VALUES (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      '55555555-5555-5555-5555-555555555555',
      NULL,
      'admin note'
    );
    RAISE EXCEPTION 'admin was allowed to post';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","email":"stranger@example.com"}', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages
   WHERE id = '13131313-1313-1313-1313-131313131313';
  IF n <> 0 THEN
    RAISE EXCEPTION 'a stranger can read the job chat';
  END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);

-- Hand the unit to another landlord. They can see the 1:1 note, not the job.
UPDATE public.units
   SET landlord_id = '44444444-4444-4444-4444-444444444444'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages WHERE id = '12121212-1212-1212-1212-121212121212';
  IF n <> 1 THEN
    RAISE EXCEPTION 'the unit landlord should still see the 1:1 message';
  END IF;
  SELECT count(*) INTO n FROM public.messages WHERE id = '13131313-1313-1313-1313-131313131313';
  IF n <> 0 THEN
    RAISE EXCEPTION 'another landlord can read the job chat';
  END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
UPDATE public.units
   SET landlord_id = '11111111-1111-1111-1111-111111111111',
       tenant_id = '22222222-2222-2222-2222-222222222222'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

-- Replace the vendor. Old vendor keeps the April message and not the later one.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","email":"landlord@example.com"}', true);
SET ROLE authenticated;
UPDATE public.maintenance_requests
   SET vendor_user_id = '88888888-8888-8888-8888-888888888888'
 WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
RESET ROLE;

UPDATE public.job_chat_participants
   SET left_at = '2026-04-02 12:00:00+00'
 WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
   AND user_id = '33333333-3333-3333-3333-333333333333';
UPDATE public.job_chat_participants
   SET joined_at = '2026-04-02 12:00:00+00'
 WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
   AND user_id = '88888888-8888-8888-8888-888888888888'
   AND left_at IS NULL;

SELECT set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888888', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"88888888-8888-8888-8888-888888888888","email":"vendor2@example.com"}', true);
SET ROLE authenticated;
INSERT INTO public.messages (
  id, unit_id, maintenance_request_id, sender_id, receiver_id, content
) VALUES (
  '14141414-1414-1414-1414-141414141414',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  '88888888-8888-8888-8888-888888888888',
  NULL,
  'new vendor hello'
);
RESET ROLE;
UPDATE public.messages
   SET created_at = '2026-04-03 12:00:00+00'
 WHERE id = '14141414-1414-1414-1414-141414141414';

SELECT set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333","email":"vendor@example.com"}', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages WHERE id = '13131313-1313-1313-1313-131313131313';
  IF n <> 1 THEN
    RAISE EXCEPTION 'the old vendor should still read their part of the thread';
  END IF;
  SELECT count(*) INTO n FROM public.messages WHERE id = '14141414-1414-1414-1414-141414141414';
  IF n <> 0 THEN
    RAISE EXCEPTION 'the old vendor can read a message sent after they left';
  END IF;
  BEGIN
    INSERT INTO public.messages (
      unit_id, maintenance_request_id, sender_id, receiver_id, content
    ) VALUES (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      '33333333-3333-3333-3333-333333333333',
      NULL,
      'too late'
    );
    RAISE EXCEPTION 'the old vendor was allowed to post';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END $$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888888', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages WHERE id = '13131313-1313-1313-1313-131313131313';
  IF n <> 0 THEN
    RAISE EXCEPTION 'the new vendor can read messages from before they joined';
  END IF;
  SELECT count(*) INTO n FROM public.messages WHERE id = '14141414-1414-1414-1414-141414141414';
  IF n <> 1 THEN
    RAISE EXCEPTION 'the new vendor should read their own message';
  END IF;
END $$;
RESET ROLE;

-- Closing the job blocks new posts and leaves history.
UPDATE public.maintenance_requests
   SET status = 'resolved'
 WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","email":"tenant@example.com"}', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages
   WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  IF n <> 2 THEN
    RAISE EXCEPTION 'the original tenant should still read the closed thread, saw %', n;
  END IF;
  SELECT count(*) INTO n FROM public.messages WHERE id = '12121212-1212-1212-1212-121212121212';
  IF n <> 1 THEN
    RAISE EXCEPTION 'the 1:1 message should still be readable';
  END IF;
  BEGIN
    INSERT INTO public.messages (
      unit_id, maintenance_request_id, sender_id, receiver_id, content
    ) VALUES (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      '22222222-2222-2222-2222-222222222222',
      NULL,
      'after close'
    );
    RAISE EXCEPTION 'a closed job chat accepted a new message';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END $$;
RESET ROLE;

-- Moving out stops new posts but keeps messages from before the move.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
UPDATE public.maintenance_requests
   SET status = 'in_progress'
 WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
UPDATE public.units
   SET tenant_id = '99999999-9999-9999-9999-999999999999'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","email":"tenant@example.com"}', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages
   WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  IF n < 1 THEN
    RAISE EXCEPTION 'moved-out tenant should still read messages from their time';
  END IF;
  BEGIN
    INSERT INTO public.messages (
      unit_id, maintenance_request_id, sender_id, receiver_id, content
    ) VALUES (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      '22222222-2222-2222-2222-222222222222',
      NULL,
      'after move-out'
    );
    RAISE EXCEPTION 'moved-out tenant was allowed to post';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END $$;
RESET ROLE;

-- A tenant who had already moved out before 02 ran is recorded as departed
-- at install time. Same statement as the one at the end of 02.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
UPDATE public.units
   SET tenant_since = '2026-05-01 00:00:00+00'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
INSERT INTO public.maintenance_requests (
  id, unit_id, landlord_id, tenant_id, description, status
) VALUES (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'Old leak', 'in_progress'
);
UPDATE public.maintenance_requests
   SET vendor_user_id = '33333333-3333-3333-3333-333333333333'
 WHERE id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
DO $$
BEGIN
  IF (SELECT left_at FROM public.job_chat_participants
      WHERE maintenance_request_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
        AND user_id = '22222222-2222-2222-2222-222222222222')
     IS NOT NULL THEN
    RAISE EXCEPTION 'pre-install departed tenant was already closed';
  END IF;
END $$;
UPDATE public.job_chat_participants p
   SET left_at = COALESCE(
     u.tenant_since,
     u.lease_start::timestamptz,
     u.created_at,
     now()
   )
  FROM public.maintenance_requests mr
  LEFT JOIN public.units u ON u.id = mr.unit_id
 WHERE p.maintenance_request_id = mr.id
   AND p.participant_role = 'tenant'
   AND p.left_at IS NULL
   AND p.user_id IS DISTINCT FROM u.tenant_id;
UPDATE public.job_chat_participants p
   SET left_at = COALESCE(
     u.tenant_since,
     u.lease_start::timestamptz,
     u.created_at,
     now()
   )
  FROM public.maintenance_requests mr
  LEFT JOIN public.units u ON u.id = mr.unit_id
 WHERE p.maintenance_request_id = mr.id
   AND p.participant_role = 'tenant'
   AND p.left_at IS NULL
   AND p.user_id IS DISTINCT FROM u.tenant_id;
UPDATE public.job_chat_participants
   SET joined_at = '2026-03-01 00:00:00+00'
 WHERE maintenance_request_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
   AND user_id = '22222222-2222-2222-2222-222222222222';
INSERT INTO public.messages (
  id, unit_id, maintenance_request_id, sender_id, receiver_id, content, created_at
) VALUES
  ('17171717-1717-1717-1717-171717171717',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
   '11111111-1111-1111-1111-111111111111', NULL, 'before they left',
   '2026-04-01 00:00:00+00'),
  ('18181818-1818-1818-1818-181818181818',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
   '11111111-1111-1111-1111-111111111111', NULL, 'after they left',
   '2026-06-01 00:00:00+00');
DO $$
BEGIN
  IF (SELECT left_at FROM public.job_chat_participants
      WHERE maintenance_request_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
        AND user_id = '22222222-2222-2222-2222-222222222222')
     IS DISTINCT FROM '2026-05-01 00:00:00+00' THEN
    RAISE EXCEPTION 'install did not record the departed tenant at the new tenancy start';
  END IF;
END $$;
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","email":"tenant@example.com"}', true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.messages
   WHERE id = '17171717-1717-1717-1717-171717171717';
  IF n <> 1 THEN
    RAISE EXCEPTION 'departed tenant cannot read a message from before they left';
  END IF;
  SELECT count(*) INTO n FROM public.messages
   WHERE id = '18181818-1818-1818-1818-181818181818';
  IF n <> 0 THEN
    RAISE EXCEPTION 'departed tenant can read a message from after they left';
  END IF;
  BEGIN
    INSERT INTO public.messages (
      unit_id, maintenance_request_id, sender_id, receiver_id, content
    ) VALUES (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
      '22222222-2222-2222-2222-222222222222',
      NULL,
      'still here'
    );
    RAISE EXCEPTION 'a tenant who left before install was allowed to post';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END $$;
RESET ROLE;

ROLLBACK;
