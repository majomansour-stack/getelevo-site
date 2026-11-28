-- Tenant rent notices.
-- Apply on the practice project first, then on live after a backup.
-- A tenant may insert only a pending, unconfirmed payment for their own
-- unit. Confirmation stays with the landlord. Depends on public.is_admin().

CREATE OR REPLACE FUNCTION public.payments_tenant_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  landlord uuid;
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(u.landlord_id, p.landlord_id)
    INTO landlord
  FROM public.units u
  LEFT JOIN public.properties p ON p.id = u.property_id
  WHERE u.id = NEW.unit_id;

  IF TG_OP = 'INSERT' AND auth.uid() = NEW.tenant_id AND auth.uid() IS DISTINCT FROM landlord THEN
    IF NEW.unit_id IS NULL OR landlord IS NULL THEN
      RAISE EXCEPTION 'tenants may only record a payment for their own unit'
        USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = NEW.unit_id
        AND u.tenant_id = auth.uid()
    ) THEN
      RAISE EXCEPTION 'tenants may only record a payment for their own unit'
        USING ERRCODE = '42501';
    END IF;
    NEW.status := 'pending_confirmation';
    NEW.confirmed_by := NULL;
    NEW.confirmed_at := NULL;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND auth.uid() IS DISTINCT FROM landlord THEN
    RAISE EXCEPTION 'only the landlord can change a payment'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS payments_tenant_insert_guard ON public.payments;
CREATE TRIGGER payments_tenant_insert_guard
  BEFORE INSERT OR UPDATE ON public.payments
  FOR EACH ROW
  EXECUTE FUNCTION public.payments_tenant_insert_guard();

REVOKE ALL ON FUNCTION public.payments_tenant_insert_guard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payments_tenant_insert_guard() TO authenticated, service_role;

DROP POLICY IF EXISTS "Tenants can insert own payments" ON public.payments;
CREATE POLICY "Tenants can insert own payments"
  ON public.payments
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = tenant_id
    AND status IN ('pending', 'pending_confirmation')
    AND confirmed_by IS NULL
    AND confirmed_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.units u
      WHERE u.id = unit_id
        AND u.tenant_id = auth.uid()
        AND u.landlord_id IS NOT NULL
    )
  );

-- One open notice per tenant and unit. Skipped when live data already
-- has two pending rows for the same pair, so this file can still apply.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.payments
    WHERE status IN ('pending', 'pending_confirmation')
    GROUP BY tenant_id, unit_id
    HAVING count(*) > 1
  ) THEN
    RAISE NOTICE 'Skipped payments_one_pending_per_unit_tenant because duplicate pending rows exist. Remove the extras, then create the unique index.';
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS payments_one_pending_per_unit_tenant
      ON public.payments (tenant_id, unit_id)
      WHERE status IN ('pending', 'pending_confirmation');
  END IF;
END $$;
