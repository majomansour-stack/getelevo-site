-- Practice checks for 03_followup_fixes.sql and 04_followup.sql.
-- Run after 00, 01, 02, 03, and 04. Sample rows are rolled back.

BEGIN;

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('11111111-1111-1111-1111-111111111111', 'landlord@example.com', '{"role":"landlord","full_name":"Land Lord"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'tenant@example.com', '{"role":"tenant","full_name":"Ten Ant"}'::jsonb),
  ('33333333-3333-3333-3333-333333333333', 'vendor@example.com', '{"role":"vendor","full_name":"Ven Dor"}'::jsonb),
  ('34343434-3434-3434-3434-343434343434', 'directory@example.com', '{"role":"vendor","full_name":"Directory Vendor"}'::jsonb),
  ('35353535-3535-3535-3535-353535353535', 'other-vendor@example.com', '{"role":"vendor","full_name":"Other Vendor"}'::jsonb),
  ('44444444-4444-4444-4444-444444444444', 'stranger@example.com', '{"role":"landlord","full_name":"Stranger"}'::jsonb);

UPDATE public.users
   SET role = 'vendor'
 WHERE id IN (
   '33333333-3333-3333-3333-333333333333',
   '34343434-3434-3434-3434-343434343434',
   '35353535-3535-3535-3535-353535353535'
 );

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","email":"landlord@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
INSERT INTO public.properties (id, landlord_id, name, address)
VALUES (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  'Oak', '1 Oak'
);
INSERT INTO public.units (
  id, property_id, landlord_id, unit_number, status, rent_amount, deposit_amount, tenant_id, tenant_name
) VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  '1', 'occupied', 1000, 0,
  '22222222-2222-2222-2222-222222222222',
  'Ten Ant'
);
INSERT INTO public.vendors (id, landlord_id, name, email)
VALUES (
  'c1c1c1c1-c1c1-c1c1-c1c1-c1c1c1c1c1c1',
  '11111111-1111-1111-1111-111111111111',
  'Directory Vendor',
  'directory@example.com'
);
INSERT INTO public.maintenance_requests (
  id, unit_id, landlord_id, tenant_id, description, status, vendor_user_id
) VALUES (
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'Leak', 'in_progress',
  '33333333-3333-3333-3333-333333333333'
);
DO $$
BEGIN
  DELETE FROM public.units WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  RAISE EXCEPTION 'a unit with a tenant was deleted';
EXCEPTION
  WHEN insufficient_privilege THEN
    NULL;
END $$;
RESET ROLE;

-- The landlord sees the assigned vendor and the directory vendor, not a stranger.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","email":"landlord@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.users WHERE id = '33333333-3333-3333-3333-333333333333';
  IF n <> 1 THEN
    RAISE EXCEPTION 'landlord cannot read the vendor assigned to their job';
  END IF;
  SELECT count(*) INTO n FROM public.users WHERE id = '34343434-3434-3434-3434-343434343434';
  IF n <> 1 THEN
    RAISE EXCEPTION 'landlord cannot read a vendor in their directory';
  END IF;
  SELECT count(*) INTO n FROM public.users WHERE id = '35353535-3535-3535-3535-353535353535';
  IF n <> 0 THEN
    RAISE EXCEPTION 'landlord can read an unrelated vendor profile';
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
  SELECT count(*) INTO n FROM public.users
   WHERE role = 'vendor'
     AND id IN (
       '33333333-3333-3333-3333-333333333333',
       '34343434-3434-3434-3434-343434343434'
     );
  IF n <> 0 THEN
    RAISE EXCEPTION 'another landlord can read these vendor profiles';
  END IF;
END $$;
RESET ROLE;

-- An untagged lease or welcome packet from before the claim stays open.
-- An untagged invoice from before this tenancy stays closed. A blank
-- invoice tied to the repair is filled with that repair's tenant only.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
INSERT INTO storage.objects (bucket_id, name, created_at) VALUES
  ('documents', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease.pdf',
   '2026-01-02 00:00:00+00'),
  ('documents', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/welcome-packet.pdf',
   '2026-01-02 00:00:00+00'),
  ('documents', '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old-invoice.pdf',
   '2026-01-03 00:00:00+00');
INSERT INTO public.documents (
  owner_id, landlord_id, tenant_id, unit_id, name, file_name, file_type, doc_type, file_url, created_at
) VALUES
  ('11111111-1111-1111-1111-111111111111',
   '11111111-1111-1111-1111-111111111111', NULL,
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'preclaim-lease.pdf', 'preclaim-lease.pdf', 'Lease', 'Lease',
   '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease.pdf',
   '2026-01-02 00:00:00+00'),
  ('11111111-1111-1111-1111-111111111111',
   '11111111-1111-1111-1111-111111111111', NULL,
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'welcome packet.pdf', 'welcome packet.pdf', 'Other', 'Other',
   '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/welcome-packet.pdf',
   '2026-01-02 00:00:00+00'),
  ('11111111-1111-1111-1111-111111111111',
   '11111111-1111-1111-1111-111111111111', NULL,
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'old-invoice.pdf', 'old-invoice.pdf', 'Receipt', 'Receipt',
   '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old-invoice.pdf',
   '2026-01-03 00:00:00+00'),
  ('11111111-1111-1111-1111-111111111111',
   '11111111-1111-1111-1111-111111111111', NULL,
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'job-invoice.pdf', 'job-invoice.pdf', 'Receipt', 'Receipt',
   '11111111-1111-1111-1111-111111111111/maintenance/dddddddd-dddd-dddd-dddd-dddddddddddd/job-invoice.pdf',
   '2026-01-04 00:00:00+00'),
  ('11111111-1111-1111-1111-111111111111',
   '11111111-1111-1111-1111-111111111111',
   '44444444-4444-4444-4444-444444444444',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'already-tagged.pdf', 'already-tagged.pdf', 'Receipt', 'Receipt',
   '11111111-1111-1111-1111-111111111111/maintenance/dddddddd-dddd-dddd-dddd-dddddddddddd/already-tagged.pdf',
   '2026-01-04 00:00:00+00');
UPDATE public.documents d
   SET tenant_id = picked.tenant_id
  FROM (
    SELECT DISTINCT ON (doc.id)
           doc.id AS document_id,
           mr.tenant_id
      FROM public.documents doc
      JOIN public.maintenance_requests mr
        ON doc.tenant_id IS NULL
       AND mr.tenant_id IS NOT NULL
       AND doc.unit_id IS NOT DISTINCT FROM mr.unit_id
       AND doc.file_url IS NOT NULL
       AND (
         position(mr.id::text IN doc.file_url) > 0
         OR (
           NULLIF(btrim(mr.invoice_url), '') IS NOT NULL
           AND position(mr.invoice_url IN doc.file_url) > 0
         )
       )
     ORDER BY doc.id, mr.created_at DESC NULLS LAST, mr.id
  ) picked
 WHERE d.id = picked.document_id
   AND d.tenant_id IS NULL;
DO $$
BEGIN
  IF (SELECT tenant_id FROM public.documents WHERE name = 'job-invoice.pdf')
     IS DISTINCT FROM '22222222-2222-2222-2222-222222222222' THEN
    RAISE EXCEPTION 'a blank repair invoice was not tagged to that repair''s tenant';
  END IF;
  IF (SELECT tenant_id FROM public.documents WHERE name = 'already-tagged.pdf')
     IS DISTINCT FROM '44444444-4444-4444-4444-444444444444' THEN
    RAISE EXCEPTION 'the backfill overwrote a tenant that was already set';
  END IF;
  IF (SELECT tenant_id FROM public.documents WHERE name = 'old-invoice.pdf')
     IS NOT NULL THEN
    RAISE EXCEPTION 'an invoice that is not tied to a repair was tagged';
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
  SELECT count(*) INTO n FROM public.documents WHERE name = 'preclaim-lease.pdf';
  IF n <> 1 THEN
    RAISE EXCEPTION 'tenant cannot open the untagged lease from before they claimed';
  END IF;
  SELECT count(*) INTO n FROM public.documents WHERE name = 'welcome packet.pdf';
  IF n <> 1 THEN
    RAISE EXCEPTION 'tenant cannot open the untagged welcome packet from before they claimed';
  END IF;
  SELECT count(*) INTO n FROM public.documents WHERE name = 'old-invoice.pdf';
  IF n <> 0 THEN
    RAISE EXCEPTION 'tenant can see an untagged invoice from before this tenancy';
  END IF;
  SELECT count(*) INTO n FROM public.documents WHERE name = 'job-invoice.pdf';
  IF n <> 1 THEN
    RAISE EXCEPTION 'tenant cannot see the invoice tagged to them';
  END IF;
  IF NOT public.can_read_storage_object(
    'documents',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/lease.pdf'
  ) THEN
    RAISE EXCEPTION 'tenant cannot open the lease file';
  END IF;
  IF public.can_read_storage_object(
    'documents',
    '11111111-1111-1111-1111-111111111111/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/old-invoice.pdf'
  ) THEN
    RAISE EXCEPTION 'tenant can open the old invoice file';
  END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);

-- Moving the tenant out records the departure. Earlier job messages stay readable.
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '', true);
UPDATE public.job_chat_participants
   SET joined_at = '2026-01-01 00:00:00+00'
 WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
   AND user_id = '22222222-2222-2222-2222-222222222222';
INSERT INTO public.messages (
  id, unit_id, maintenance_request_id, sender_id, receiver_id, content, created_at
) VALUES (
  '17171717-1717-1717-1717-171717171717',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  '11111111-1111-1111-1111-111111111111',
  NULL,
  'before move-out',
  '2026-02-01 00:00:00+00'
);
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","email":"landlord@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
UPDATE public.units
   SET tenant_id = NULL,
       tenant_name = NULL,
       invited_email = NULL,
       status = 'vacant'
 WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
RESET ROLE;
DO $$
BEGIN
  IF (SELECT tenant_id FROM public.units WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
     IS NOT NULL THEN
    RAISE EXCEPTION 'move-out left the tenant in place';
  END IF;
  IF (SELECT tenant_since FROM public.units WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
     IS NOT NULL THEN
    RAISE EXCEPTION 'move-out left the tenancy start set';
  END IF;
  IF (SELECT lower(status) FROM public.units WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
     IS DISTINCT FROM 'vacant' THEN
    RAISE EXCEPTION 'move-out left the unit occupied';
  END IF;
  IF (SELECT left_at FROM public.job_chat_participants
      WHERE maintenance_request_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        AND user_id = '22222222-2222-2222-2222-222222222222')
     IS NULL THEN
    RAISE EXCEPTION 'move-out did not close the tenant job chat';
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
   WHERE id = '17171717-1717-1717-1717-171717171717';
  IF n <> 1 THEN
    RAISE EXCEPTION 'former tenant cannot read the job message from before they left';
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
    RAISE EXCEPTION 'former tenant was allowed to post';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END $$;
RESET ROLE;

-- After the tenant is gone, the landlord can delete the unit.
-- Remove this test's own documents first. Live keeps them through a
-- foreign key, and this check does not delete anyone else's files.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","email":"landlord@example.com","role":"authenticated"}',
  true);
SET ROLE authenticated;
DELETE FROM public.documents
 WHERE unit_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DELETE FROM public.units WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
RESET ROLE;

ROLLBACK;
