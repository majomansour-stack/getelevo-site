-- Tenant unit claim lock.
-- Apply on the practice project first, then on live after a backup.
-- Replaces "units: tenant claims invite" from
-- supabase/live/06_subscriptions_push_email_rentspree.sql and tightens
-- public.units_tenant_update_guard from supabase/live/01_live_security_fixes.sql.
-- Depends on public.is_admin() and public.caller_email_confirmed().

-- A tenant may set tenant_id to themselves on an unclaimed invite.
-- Every other column stays as the landlord saved it. tenant_since is
-- forced to now() so a tenant cannot backdate the tenancy and reveal
-- the previous tenant's messages, documents, or files.
CREATE OR REPLACE FUNCTION public.units_tenant_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL
     OR auth.uid() = OLD.landlord_id
     OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF OLD.tenant_id IS NOT NULL
     OR NEW.tenant_id IS DISTINCT FROM auth.uid()
     OR OLD.invited_email IS NULL
     OR lower(btrim(OLD.invited_email))
        IS DISTINCT FROM lower(btrim(COALESCE(auth.jwt() ->> 'email', ''))) THEN
    RAISE EXCEPTION 'tenants may only claim their invited unit'
      USING ERRCODE = '42501';
  END IF;

  NEW.property_id := OLD.property_id;
  NEW.landlord_id := OLD.landlord_id;
  NEW.unit_number := OLD.unit_number;
  NEW.rent_amount := OLD.rent_amount;
  NEW.deposit_amount := OLD.deposit_amount;
  NEW.additional_deposit := OLD.additional_deposit;
  NEW.lease_start := OLD.lease_start;
  NEW.lease_end := OLD.lease_end;
  NEW.invited_email := OLD.invited_email;
  NEW.tenant_name := OLD.tenant_name;
  NEW.bedrooms := OLD.bedrooms;
  NEW.bathrooms := OLD.bathrooms;
  NEW.status := 'occupied';
  NEW.tenant_since := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS units_tenant_update_guard ON public.units;
CREATE TRIGGER units_tenant_update_guard
  BEFORE UPDATE ON public.units
  FOR EACH ROW
  EXECUTE FUNCTION public.units_tenant_update_guard();

-- The previous policy also allowed UPDATE once tenant_id was already
-- the caller. That is what let a tenant change tenant_since, tenant_name,
-- bedrooms, and bathrooms. Only the unclaimed invite remains.
DROP POLICY IF EXISTS "units: tenant claims invite" ON public.units;
CREATE POLICY "units: tenant claims invite"
  ON public.units
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id IS NULL
    AND invited_email IS NOT NULL
    AND lower(invited_email) = lower(COALESCE(auth.jwt() ->> 'email', ''))
    AND public.caller_email_confirmed()
  )
  WITH CHECK (
    tenant_id = auth.uid()
    AND status = 'occupied'
  );
