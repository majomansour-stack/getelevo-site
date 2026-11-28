-- ============================================================
-- ELEVO — Supabase Storage RLS Policies
-- Run this entire script in:
--   Supabase Dashboard → SQL Editor → New Query → Run
--
-- Applies to five buckets:
--   documents, private-vault, photo-logs,
--   maintenance-photos, avatars
--
-- Prerequisites (run once in the Dashboard → Storage section
-- if not already done):
--   • Create each bucket with "Row Level Security" enabled
--   • Leave buckets as PRIVATE (not public)
--   • Run supabase/fixes_pending_owner_approval.sql first.
--     Document, photo-log, and maintenance-photo reads call
--     public.can_read_storage_object(), which that file creates.
--     Those reads are limited to the owning landlord and the
--     tenant or vendor tied to the unit or job.
-- ============================================================


-- ============================================================
-- BUCKET 1: documents
-- Upload convention: {uploader_uid}/{filename}
-- ============================================================

DROP POLICY IF EXISTS "documents: authenticated users upload own path"
  ON storage.objects;
DROP POLICY IF EXISTS "documents: landlords read properties docs"
  ON storage.objects;
DROP POLICY IF EXISTS "documents: tenants read own docs"
  ON storage.objects;

-- INSERT — any authenticated user may upload files where the
-- first path segment matches their own uid.
-- Covers landlord uploads AND tenant uploads (unit docs, lease, etc.)
CREATE POLICY "documents: authenticated users upload own path"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- SELECT — the uploader, the landlord who owns the unit, and the
-- tenant or vendor tied to that unit or job. Not every landlord.
-- The helper is defined in fixes_pending_owner_approval.sql.
DROP POLICY IF EXISTS "documents: read if tied to the file"
  ON storage.objects;
CREATE POLICY "documents: read if tied to the file"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.can_read_storage_object('documents', name)
  );


-- ============================================================
-- BUCKET 2: private-vault
-- Upload convention: {landlord_uid}/{timestamp}_{filename}
-- Only the owning landlord may insert or select.
-- ============================================================

DROP POLICY IF EXISTS "private-vault: landlord insert own folder"
  ON storage.objects;
DROP POLICY IF EXISTS "private-vault: landlord select own folder"
  ON storage.objects;

CREATE POLICY "private-vault: landlord insert own folder"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'private-vault'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
        AND role IN ('landlord', 'admin')
    )
  );

CREATE POLICY "private-vault: landlord select own folder"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'private-vault'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
        AND role IN ('landlord', 'admin')
    )
  );


-- ============================================================
-- BUCKET 3: photo-logs
-- Upload convention: {uploader_uid}/{unit_id}/{filename}
-- Both landlords and tenants may upload and read for their unit.
-- ============================================================

DROP POLICY IF EXISTS "photo-logs: upload own unit photos"
  ON storage.objects;
DROP POLICY IF EXISTS "photo-logs: read own unit photos"
  ON storage.objects;

-- INSERT — uploader's uid must be the first path segment.
-- Applies to both roles.
CREATE POLICY "photo-logs: upload own unit photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'photo-logs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- SELECT — uploader, or the landlord/tenant of the unit in the path.
DROP POLICY IF EXISTS "photo-logs: read if tied to the unit"
  ON storage.objects;
CREATE POLICY "photo-logs: read if tied to the unit"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'photo-logs'
    AND public.can_read_storage_object('photo-logs', name)
  );


-- ============================================================
-- BUCKET 4: maintenance-photos
-- Upload convention: {tenant_uid}/{request_id}/{filename}
-- Tenants upload; landlords (and admins) read.
-- ============================================================

DROP POLICY IF EXISTS "maintenance-photos: tenants upload own"
  ON storage.objects;
DROP POLICY IF EXISTS "maintenance-photos: landlords read all"
  ON storage.objects;
DROP POLICY IF EXISTS "maintenance-photos: tenants read own"
  ON storage.objects;

-- INSERT — only the tenant who submitted the request may upload;
-- first path segment must equal their uid.
CREATE POLICY "maintenance-photos: tenants upload own"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'maintenance-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- SELECT — the tenant who uploaded, their landlord, or the vendor on that job.
DROP POLICY IF EXISTS "maintenance-photos: read if tied to the job"
  ON storage.objects;
CREATE POLICY "maintenance-photos: read if tied to the job"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'maintenance-photos'
    AND public.can_read_storage_object('maintenance-photos', name)
  );


-- ============================================================
-- BUCKET 5: avatars
-- Upload convention: {user_uid}/{filename}  e.g. {uid}/avatar.jpg
-- Any authenticated user may upload and read their own avatar.
-- ============================================================

DROP POLICY IF EXISTS "avatars: authenticated upload own"
  ON storage.objects;
DROP POLICY IF EXISTS "avatars: authenticated read own"
  ON storage.objects;

CREATE POLICY "avatars: authenticated upload own"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Avatars are profile pictures — readable by any authenticated user
-- so they can be displayed in chat threads and partner cards.
-- If you want strictly private avatars change this to:
--   AND (storage.foldername(name))[1] = auth.uid()::text
CREATE POLICY "avatars: authenticated read own"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );


-- ============================================================
-- VERIFICATION QUERY
-- Run this after applying the policies to confirm all 13 rows
-- are present (5 buckets × 2–3 policies each).
-- ============================================================
SELECT
  policyname,
  cmd,
  roles
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename  = 'objects'
ORDER BY policyname;
