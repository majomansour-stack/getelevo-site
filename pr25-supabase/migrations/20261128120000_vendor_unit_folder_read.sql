-- Apply after 20261127150300_vendor_login_scope.sql.
-- An assigned vendor could list and download a unit folder in the documents
-- bucket, including the lease and landlord-tenant chat files, because
-- can_read_storage_object treated every file on a visible unit as readable.
-- Vendors keep the maintenance folder, which is where job photos and new
-- job-chat attachments live. This does not move existing objects.

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
