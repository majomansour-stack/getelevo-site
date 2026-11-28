-- Apply after 20261124170100_vendor_column_limits.sql.
-- That migration created vendor_self_directory and vendor_job_units as
-- security-definer views and revoked PUBLIC and anon, which left the
-- default INSERT, UPDATE, and DELETE grants for authenticated in place.
-- vendor_self_directory is auto-updatable and runs as its owner, so any
-- signed-in user could insert a vendor into another landlord's directory,
-- and a vendor could change their own rating, landlord_id, or is_active.
-- vendor_job_units had the same leftover grants.

REVOKE ALL ON public.vendor_self_directory FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.vendor_job_units FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.vendor_self_directory TO authenticated;
GRANT SELECT ON public.vendor_job_units TO authenticated;
GRANT ALL ON public.vendor_self_directory TO service_role;
GRANT ALL ON public.vendor_job_units TO service_role;
