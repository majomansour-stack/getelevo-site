-- ============================================================
-- ELEVO — photos on a repair request.
--
-- Run after 04_followup.sql. Safe to run again.
-- It only adds a column, a private bucket if it is missing, and rules.
-- It does not delete or overwrite repair rows.
--
-- Photo paths look like {request id}/{time}_{file}. The first folder is
-- the repair, not the person who uploaded it, so a former tenant is not
-- treated as the file owner.
--
-- Who can read a photo: the landlord of that repair, the vendor assigned
-- to it, and the tenant who filed it only while they still live in the
-- unit and the repair was opened during their tenancy.
-- ============================================================

BEGIN;

ALTER TABLE public.maintenance_requests
  ADD COLUMN IF NOT EXISTS photo_paths jsonb NOT NULL DEFAULT '[]'::jsonb;

INSERT INTO storage.buckets (id, name, public)
VALUES ('maintenance-photos', 'maintenance-photos', false)
ON CONFLICT (id) DO NOTHING;

UPDATE storage.buckets
   SET public = false
 WHERE id = 'maintenance-photos'
   AND public IS DISTINCT FROM false;

-- A tenant may add photo paths to their own open repair, and nothing else.
CREATE OR REPLACE FUNCTION public.tenant_repair_photo_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.uid() = OLD.tenant_id
     AND auth.uid() IS DISTINCT FROM OLD.landlord_id
     AND NOT public.is_admin() THEN
    IF (to_jsonb(NEW) - 'photo_paths') IS DISTINCT FROM (to_jsonb(OLD) - 'photo_paths') THEN
      RAISE EXCEPTION 'tenants may only add photos to their repair' USING ERRCODE = '42501';
    END IF;
    IF NEW.photo_paths IS DISTINCT FROM OLD.photo_paths AND (
         jsonb_typeof(NEW.photo_paths) IS DISTINCT FROM 'array'
         OR jsonb_array_length(NEW.photo_paths) > 5
         OR EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.photo_paths) e
                    WHERE jsonb_typeof(e) <> 'string'
                       OR left(e #>> '{}', length(OLD.id::text) + 1) <> OLD.id::text || '/'))
    THEN
      RAISE EXCEPTION 'repair photos must be up to 5 files in this repair''s folder' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS maintenance_requests_tenant_photo_update ON public.maintenance_requests;
CREATE TRIGGER maintenance_requests_tenant_photo_update
  BEFORE UPDATE ON public.maintenance_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.tenant_repair_photo_update();

DROP POLICY IF EXISTS "maintenance_requests: tenant adds repair photos" ON public.maintenance_requests;
CREATE POLICY "maintenance_requests: tenant adds repair photos"
  ON public.maintenance_requests
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = maintenance_requests.unit_id
        AND u.tenant_id = auth.uid()
    )
  )
  WITH CHECK (
    tenant_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = maintenance_requests.unit_id
        AND u.tenant_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "maintenance-photos: tenant uploads repair photos" ON storage.objects;
CREATE POLICY "maintenance-photos: tenant uploads repair photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'maintenance-photos'
    AND (storage.foldername(name))[1] ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    AND EXISTS (
      SELECT 1
      FROM public.maintenance_requests mr
      JOIN public.units u ON u.id = mr.unit_id
      WHERE mr.id = (storage.foldername(name))[1]::uuid
        AND mr.tenant_id = auth.uid()
        AND u.tenant_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "maintenance-photos: repair participants read" ON storage.objects;
CREATE POLICY "maintenance-photos: repair participants read"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'maintenance-photos'
    AND (storage.foldername(name))[1] ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    AND EXISTS (
      SELECT 1
      FROM public.maintenance_requests mr
      WHERE mr.id = (storage.foldername(name))[1]::uuid
        AND (
          mr.landlord_id = auth.uid()
          OR mr.vendor_user_id = auth.uid()
          OR mr.vendor_id = auth.uid()
          OR mr.vendor_id::text IN (
            SELECT v.id::text
            FROM public.vendors v
            WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
          )
          OR (
            mr.tenant_id = auth.uid()
            AND public.unit_file_visible_to_current_tenant(mr.unit_id, mr.created_at)
          )
        )
    )
  );

REVOKE ALL ON FUNCTION public.tenant_repair_photo_update() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tenant_repair_photo_update() TO authenticated, service_role;

COMMIT;
