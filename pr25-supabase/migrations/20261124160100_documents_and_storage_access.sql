-- Document rows and storage reads.
-- Apply on the practice project first, then on live after a backup.
-- Depends on public.current_user_role(), public.is_admin(), and
-- public.landlord_unit_document_visible from the live security scripts.
-- Replaces public.can_read_storage_object from supabase/live/04_followup.sql.

-- The stored file_url must be the uploader's own object path
-- (`<uid>/...`) or a storage URL whose path contains that folder.
CREATE OR REPLACE FUNCTION public.document_path_owned_by(p_url text, p_uid uuid)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_url IS NOT NULL
    AND p_uid IS NOT NULL
    AND position('..' in p_url) = 0
    AND (
      btrim(p_url) LIKE p_uid::text || '/%'
      OR btrim(p_url) LIKE '%/' || p_uid::text || '/%'
    );
$$;

-- A document row unlocks a storage object only when the object path is
-- exactly that row's file and the object lives in the row owner's folder.
-- A row inserted with a file_url that merely contains someone else's path
-- does not match.
CREATE OR REPLACE FUNCTION public.document_url_matches_object(
  p_url text,
  p_object text,
  p_owner uuid
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_url IS NOT NULL
    AND p_object IS NOT NULL
    AND p_owner IS NOT NULL
    AND position('..' in p_url) = 0
    AND position('..' in p_object) = 0
    AND p_object LIKE p_owner::text || '/%'
    AND (
      btrim(p_url) = p_object
      OR btrim(p_url) LIKE '%/' || p_object
    );
$$;

-- Column names are passed in so the policy does not use an ambiguous
-- landlord_id inside a subquery on units.
CREATE OR REPLACE FUNCTION public.document_write_allowed(
  p_owner uuid,
  p_landlord uuid,
  p_tenant uuid,
  p_unit uuid,
  p_url text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_owner = auth.uid()
    AND public.document_path_owned_by(p_url, auth.uid())
    AND (
      (
        public.current_user_role() IN ('landlord', 'admin')
        AND p_landlord = auth.uid()
        AND (
          p_unit IS NULL
          OR EXISTS (
            SELECT 1
            FROM public.units u
            WHERE u.id = p_unit
              AND u.landlord_id = auth.uid()
              AND (p_tenant IS NULL OR p_tenant = u.tenant_id)
          )
        )
      )
      OR (
        public.current_user_role() = 'tenant'
        AND p_tenant = auth.uid()
        AND EXISTS (
          SELECT 1
          FROM public.units u
          WHERE u.id = p_unit
            AND u.tenant_id = auth.uid()
            AND (p_landlord IS NULL OR p_landlord = u.landlord_id)
        )
      )
    );
$$;

REVOKE ALL ON FUNCTION public.document_path_owned_by(text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.document_url_matches_object(text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.document_write_allowed(uuid, uuid, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.document_path_owned_by(text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.document_url_matches_object(text, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.document_write_allowed(uuid, uuid, uuid, uuid, text) TO authenticated, service_role;

-- "Owner manages documents" allowed any insert or read when owner_id was
-- the caller, with no check on tenant_id, landlord_id, unit_id, or file_url.
DROP POLICY IF EXISTS "Owner manages documents" ON public.documents;
DROP POLICY IF EXISTS "documents: landlords insert own" ON public.documents;
DROP POLICY IF EXISTS "documents: tenants insert own" ON public.documents;
DROP POLICY IF EXISTS "documents: landlords update own" ON public.documents;
DROP POLICY IF EXISTS "documents: landlords delete own" ON public.documents;
DROP POLICY IF EXISTS "documents: owner reads own file" ON public.documents;

CREATE POLICY "documents: owner reads own file"
  ON public.documents
  FOR SELECT
  TO authenticated
  USING (
    owner_id = auth.uid()
    AND public.document_path_owned_by(file_url, auth.uid())
  );

CREATE POLICY "documents: landlords insert own"
  ON public.documents
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.document_write_allowed(owner_id, landlord_id, tenant_id, unit_id, file_url)
    AND public.current_user_role() IN ('landlord', 'admin')
  );

CREATE POLICY "documents: landlords update own"
  ON public.documents
  FOR UPDATE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND public.current_user_role() IN ('landlord', 'admin')
  )
  WITH CHECK (
    public.document_write_allowed(owner_id, landlord_id, tenant_id, unit_id, file_url)
  );

CREATE POLICY "documents: landlords delete own"
  ON public.documents
  FOR DELETE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND public.current_user_role() IN ('landlord', 'admin')
  );

CREATE POLICY "documents: tenants insert own"
  ON public.documents
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.document_write_allowed(owner_id, landlord_id, tenant_id, unit_id, file_url)
    AND public.current_user_role() = 'tenant'
  );

CREATE OR REPLACE FUNCTION public.can_read_storage_object(bucket text, object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  parts text[];
  first_seg text;
  second_seg text;
  third_seg text;
  uid uuid := auth.uid();
  uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
BEGIN
  IF uid IS NULL OR object_name IS NULL THEN
    RETURN false;
  END IF;

  parts := storage.foldername(object_name);
  first_seg := parts[1];
  second_seg := parts[2];
  third_seg := parts[3];

  IF first_seg = uid::text THEN
    RETURN true;
  END IF;

  IF bucket = 'documents' THEN
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = second_seg::uuid
        AND (
          u.landlord_id = uid
          OR public.unit_file_visible_to_current_tenant(u.id, (
            SELECT o.created_at FROM storage.objects o
            WHERE o.bucket_id = bucket AND o.name = object_name
            LIMIT 1
          ))
          OR u.id IN (SELECT public.vendor_visible_unit_ids())
        )
    ) THEN
      RETURN true;
    END IF;

    IF second_seg = 'chat' AND third_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = third_seg::uuid
        AND (
          u.landlord_id = uid
          OR public.unit_file_visible_to_current_tenant(u.id, (
            SELECT o.created_at FROM storage.objects o
            WHERE o.bucket_id = bucket AND o.name = object_name
            LIMIT 1
          ))
          OR u.id IN (SELECT public.vendor_visible_unit_ids())
        )
    ) THEN
      RETURN true;
    END IF;

    IF second_seg = 'maintenance' AND third_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.maintenance_requests mr
      WHERE mr.id = third_seg::uuid
        AND (
          mr.landlord_id = uid
          OR (
            mr.tenant_id = uid
            AND public.unit_file_visible_to_current_tenant(
              mr.unit_id,
              COALESCE(mr.created_at, (
                SELECT o.created_at FROM storage.objects o
                WHERE o.bucket_id = bucket AND o.name = object_name
                LIMIT 1
              ))
            )
          )
          OR mr.vendor_user_id = uid
          OR mr.vendor_id::text = uid::text
          OR mr.vendor_id::text IN (
            SELECT v.id::text FROM public.vendors v
            WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
          )
        )
    ) THEN
      RETURN true;
    END IF;

    -- A document row grants this object only when the row's file_url is
    -- that object and the object sits in the row owner's folder. The reader
    -- must be that owner, that landlord, or a current tenant the unit-file
    -- rule already allows. Inserting a row that points at someone else's
    -- path does not grant the file.
    IF EXISTS (
      SELECT 1
      FROM public.documents d
      WHERE public.document_url_matches_object(d.file_url, object_name, d.owner_id)
        AND (
          d.owner_id = uid
          OR (d.landlord_id = uid AND d.owner_id = d.landlord_id)
          OR public.landlord_unit_document_visible(
            d.unit_id,
            d.tenant_id,
            d.owner_id,
            d.landlord_id,
            d.created_at,
            d.doc_type,
            d.file_type,
            d.name,
            d.file_name
          )
        )
    ) THEN
      RETURN true;
    END IF;

  ELSIF bucket = 'photo-logs' THEN
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.id = second_seg::uuid
        AND (
          u.landlord_id = uid
          OR public.unit_file_visible_to_current_tenant(u.id, (
            SELECT o.created_at FROM storage.objects o
            WHERE o.bucket_id = bucket AND o.name = object_name
            LIMIT 1
          ))
          OR public.vendor_assigned_to_unit(uid, u.id)
        )
    ) THEN
      RETURN true;
    END IF;

  ELSIF bucket = 'maintenance-photos' THEN
    IF second_seg ~ uuid_pattern AND EXISTS (
      SELECT 1 FROM public.maintenance_requests mr
      WHERE mr.id = second_seg::uuid
        AND (
          mr.landlord_id = uid
          OR (
            mr.tenant_id = uid
            AND public.unit_file_visible_to_current_tenant(
              mr.unit_id,
              COALESCE(mr.created_at, (
                SELECT o.created_at FROM storage.objects o
                WHERE o.bucket_id = bucket AND o.name = object_name
                LIMIT 1
              ))
            )
          )
          OR mr.vendor_user_id = uid
          OR mr.vendor_id::text = uid::text
          OR mr.vendor_id::text IN (
            SELECT v.id::text FROM public.vendors v
            WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
          )
        )
    ) THEN
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END;
$$;
