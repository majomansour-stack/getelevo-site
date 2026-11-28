-- Vendors may see the address of a unit they are assigned to, not the
-- rent, deposit, lease, or tenant name. They may see their own directory
-- row without the landlord's notes or spend limit.
-- Apply on practice first, then live with a backup.
-- Depends on public.vendor_visible_unit_ids().

DROP POLICY IF EXISTS "units: vendor reads job units" ON public.units;

CREATE OR REPLACE VIEW public.vendor_job_units
WITH (security_invoker = false) AS
SELECT
  u.id,
  u.unit_number,
  u.property_id,
  p.name AS property_name,
  p.address,
  p.address2,
  p.city,
  p.state,
  p.zip
FROM public.units u
JOIN public.properties p ON p.id = u.property_id
WHERE u.id IN (SELECT public.vendor_visible_unit_ids());

REVOKE ALL ON public.vendor_job_units FROM PUBLIC, anon;
GRANT SELECT ON public.vendor_job_units TO authenticated, service_role;

DROP POLICY IF EXISTS "vendors: vendor reads own directory row" ON public.vendors;

CREATE OR REPLACE VIEW public.vendor_self_directory
WITH (security_invoker = false) AS
SELECT
  v.id,
  v.name,
  v.company_name,
  v.email,
  v.phone,
  v.category,
  v.is_active,
  v.rating,
  v.landlord_id
FROM public.vendors v
WHERE lower(v.email) = lower(COALESCE(auth.jwt() ->> 'email', ''));

REVOKE ALL ON public.vendor_self_directory FROM PUBLIC, anon;
GRANT SELECT ON public.vendor_self_directory TO authenticated, service_role;
