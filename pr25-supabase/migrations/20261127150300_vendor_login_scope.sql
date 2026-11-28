-- Apply after 20261127150200_rent_due_and_send_status.sql.
-- 20261127150100 replaced "users: landlord reads vendor accounts" with
-- vendor_login_for_landlord. That view runs as its owner and only checked
-- that the caller is a landlord, so every landlord could list every vendor
-- account's email, name and phone. The policy it replaced was limited to
-- vendors the landlord is linked to (a job, or a vendors row with the same
-- email). Keep that scope. Assigning a vendor still works because the
-- landlord's vendors row with the vendor's email satisfies
-- landlord_linked_to_vendor.

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

REVOKE ALL ON FUNCTION public.landlord_linked_to_vendor(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.landlord_linked_to_vendor(uuid) TO authenticated, service_role;

CREATE OR REPLACE VIEW public.vendor_login_for_landlord
WITH (security_invoker = false) AS
SELECT u.id, u.email, u.full_name, u.phone, u.role
FROM public.users u
WHERE u.role = 'vendor'
  AND public.current_user_role() IN ('landlord', 'admin')
  AND public.landlord_linked_to_vendor(u.id);

REVOKE ALL ON public.vendor_login_for_landlord FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.vendor_login_for_landlord TO authenticated;
GRANT ALL ON public.vendor_login_for_landlord TO service_role;
