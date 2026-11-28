-- Landlord confirms or declines a tenant rent notice.
-- Apply on practice first, then live with a backup.
-- Depends on public.is_admin() and public.payments_tenant_insert_guard().

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
      SELECT 1 FROM public.units u
      WHERE u.id = NEW.unit_id AND u.tenant_id = auth.uid()
    ) THEN
      RAISE EXCEPTION 'tenants may only record a payment for their own unit'
        USING ERRCODE = '42501';
    END IF;
    NEW.status := 'pending_confirmation';
    NEW.confirmed_by := NULL;
    NEW.confirmed_at := NULL;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF auth.uid() IS DISTINCT FROM landlord THEN
      RAISE EXCEPTION 'only the landlord can change a payment'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.status NOT IN ('confirmed', 'declined', 'pending_confirmation') THEN
      RAISE EXCEPTION 'a payment can only be confirmed or declined'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.status IN ('confirmed', 'declined') THEN
      NEW.confirmed_by := auth.uid();
      NEW.confirmed_at := now();
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP POLICY IF EXISTS "Landlords can update payment status" ON public.payments;
CREATE POLICY "Landlords can update payment status"
  ON public.payments
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.units u
      LEFT JOIN public.properties p ON p.id = u.property_id
      WHERE u.id = payments.unit_id
        AND (u.landlord_id = auth.uid() OR p.landlord_id = auth.uid())
    )
  )
  WITH CHECK (
    status IN ('confirmed', 'declined', 'pending_confirmation')
    AND EXISTS (
      SELECT 1
      FROM public.units u
      LEFT JOIN public.properties p ON p.id = u.property_id
      WHERE u.id = payments.unit_id
        AND (u.landlord_id = auth.uid() OR p.landlord_id = auth.uid())
    )
  );
