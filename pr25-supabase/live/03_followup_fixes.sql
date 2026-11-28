-- ============================================================
-- ELEVO — follow-up rules after 01 and 02.
--
-- Run this after 01_live_security_fixes.sql and 02_job_group_chat.sql.
-- One transaction. Safe to run again. It only adds or tightens rules.
-- It does not delete or overwrite rows.
--
-- If 01 is applied again later, run this file again afterwards.
-- 01 recreates the wider vendor-profile rule that this file narrows.
-- ============================================================

BEGIN;

-- A landlord may read a vendor login only when that vendor is in the
-- landlord's own directory (matched by email) or assigned to one of
-- the landlord's repair jobs. Admins can still read every vendor profile.
CREATE OR REPLACE FUNCTION public.landlord_linked_to_vendor(p_vendor uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_vendor IS NOT NULL
    AND public.current_user_role() IN ('landlord', 'admin')
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.maintenance_requests mr
        WHERE mr.landlord_id = auth.uid()
          AND (
            mr.vendor_user_id = p_vendor
            OR mr.vendor_id = p_vendor
          )
      )
      OR EXISTS (
        SELECT 1
        FROM public.vendors v
        JOIN public.users u ON u.id = p_vendor
        WHERE v.landlord_id = auth.uid()
          AND NULLIF(btrim(v.email), '') IS NOT NULL
          AND NULLIF(btrim(u.email), '') IS NOT NULL
          AND lower(btrim(v.email)) = lower(btrim(u.email))
      )
    );
$$;

DROP POLICY IF EXISTS "users: landlord reads vendor accounts" ON public.users;
CREATE POLICY "users: landlord reads vendor accounts"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    role = 'vendor'
    AND public.landlord_linked_to_vendor(id)
  );

-- Same block the app already shows: a unit with a tenant, or one still
-- marked occupied, cannot be deleted. Moving the tenant out first clears
-- both, and the existing tenancy and job-chat triggers record the departure.
CREATE OR REPLACE FUNCTION public.units_block_delete_with_tenant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.tenant_id IS NOT NULL
     OR lower(btrim(COALESCE(OLD.status, ''))) = 'occupied' THEN
    RAISE EXCEPTION 'This unit still has a tenant, so it cannot be deleted. Move the tenant out first.'
      USING ERRCODE = '42501';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS units_block_delete_with_tenant ON public.units;
CREATE TRIGGER units_block_delete_with_tenant
  BEFORE DELETE ON public.units
  FOR EACH ROW
  EXECUTE FUNCTION public.units_block_delete_with_tenant();

REVOKE ALL ON FUNCTION public.landlord_linked_to_vendor(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.units_block_delete_with_tenant() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.landlord_linked_to_vendor(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.units_block_delete_with_tenant() TO authenticated, service_role;

COMMIT;
