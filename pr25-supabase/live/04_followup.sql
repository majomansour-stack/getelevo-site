-- ============================================================
-- ELEVO — document turnover after 03.
--
-- Run after 03_followup_fixes.sql. Safe to run again.
-- It only adds or tightens rules, and the backfill only fills a blank
-- tenant_id. It does not delete rows or overwrite a tenant that is set.
--
-- If 01 is applied again later, run this file again afterwards.
-- 01 recreates the wider document and storage rules this file narrows.
--
-- There is no "shared with the new tenant" flag. Lease is a document
-- category (doc_type or file_type). A welcome packet has no category,
-- so a file whose name says welcome is treated as that packet. Any other
-- untagged landlord file from before the current tenancy stays hidden.
-- A file tagged to the current tenant, and an untagged file from this
-- tenancy, stay visible.
-- ============================================================

BEGIN;

-- Invoices are stored under the repair id and were saved with no tenant.
-- Point a blank row at that repair's tenant. A row that already names
-- someone is left alone.
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

CREATE OR REPLACE FUNCTION public.landlord_unit_document_visible(
  p_unit uuid,
  p_tenant uuid,
  p_owner uuid,
  p_landlord uuid,
  p_created timestamptz,
  p_doc_type text,
  p_file_type text,
  p_name text,
  p_file_name text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.units u
    WHERE u.id = p_unit
      AND u.tenant_id = auth.uid()
      AND (p_owner = u.landlord_id OR p_landlord = u.landlord_id)
      AND (
        p_tenant = auth.uid()
        OR (
          p_tenant IS NULL
          AND (
            (
              p_created IS NOT NULL
              AND p_created >= COALESCE(
                u.tenant_since, u.lease_start::timestamptz, u.created_at
              )
            )
            OR lower(btrim(COALESCE(p_doc_type, ''))) = 'lease'
            OR lower(btrim(COALESCE(p_file_type, ''))) = 'lease'
            OR position('welcome' IN lower(COALESCE(p_name, ''))) > 0
            OR position('welcome' IN lower(COALESCE(p_file_name, ''))) > 0
          )
        )
      )
  );
$$;

DROP POLICY IF EXISTS "documents: tenant reads landlord unit files" ON public.documents;
CREATE POLICY "documents: tenant reads landlord unit files"
  ON public.documents
  FOR SELECT
  TO authenticated
  USING (
    public.landlord_unit_document_visible(
      unit_id,
      tenant_id,
      owner_id,
      landlord_id,
      created_at,
      doc_type,
      file_type,
      name,
      file_name
    )
  );

-- Same gate for the file itself. The rest of the storage rules are unchanged.
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

    IF EXISTS (
      SELECT 1 FROM public.documents d
      WHERE (d.landlord_id = uid OR d.tenant_id = uid OR d.owner_id = uid)
        AND d.file_url LIKE '%' || object_name || '%'
    ) THEN
      RETURN true;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.documents d
      WHERE public.landlord_unit_document_visible(
              d.unit_id, d.tenant_id, d.owner_id, d.landlord_id, d.created_at,
              d.doc_type, d.file_type, d.name, d.file_name
            )
        AND d.file_url LIKE '%' || object_name || '%'
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

REVOKE ALL ON FUNCTION public.landlord_unit_document_visible(uuid, uuid, uuid, uuid, timestamptz, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.landlord_unit_document_visible(uuid, uuid, uuid, uuid, timestamptz, text, text, text, text) TO authenticated, service_role;

COMMIT;
