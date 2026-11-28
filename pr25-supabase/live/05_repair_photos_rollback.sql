-- ============================================================
-- ELEVO — undo 05_repair_photos.sql.
--
-- Drops only what 05 added. It does not remove the maintenance-photos
-- bucket, because that bucket already existed, and it does not delete
-- repair rows. photo_paths is removed, so the path list goes with it.
-- Run this only if 05 should be taken back.
-- ============================================================

BEGIN;

DROP POLICY IF EXISTS "maintenance-photos: repair participants read" ON storage.objects;
DROP POLICY IF EXISTS "maintenance-photos: tenant uploads repair photos" ON storage.objects;
DROP POLICY IF EXISTS "maintenance_requests: tenant adds repair photos" ON public.maintenance_requests;

DROP TRIGGER IF EXISTS maintenance_requests_tenant_photo_update ON public.maintenance_requests;
DROP FUNCTION IF EXISTS public.tenant_repair_photo_update();

ALTER TABLE public.maintenance_requests
  DROP COLUMN IF EXISTS photo_paths;

COMMIT;
