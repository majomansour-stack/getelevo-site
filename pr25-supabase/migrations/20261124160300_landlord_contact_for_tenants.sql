-- Tenants need a landlord's name, phone, email, and payment instructions.
-- They must not receive the landlord's plan, Stripe ids, or subscription
-- status. Apply on the practice project first, then on live after a backup.
-- Depends on public.is_admin().

CREATE OR REPLACE FUNCTION public.landlord_contact_for_tenant(p_landlord uuid)
RETURNS TABLE (
  id uuid,
  full_name text,
  phone text,
  email text,
  payment_instructions jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR p_landlord IS NULL THEN
    RETURN;
  END IF;

  IF auth.uid() IS DISTINCT FROM p_landlord
     AND NOT public.is_admin()
     AND NOT EXISTS (
       SELECT 1
       FROM public.units u
       LEFT JOIN public.properties p ON p.id = u.property_id
       WHERE u.tenant_id = auth.uid()
         AND (u.landlord_id = p_landlord OR p.landlord_id = p_landlord)
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.full_name,
    u.phone,
    u.email,
    u.payment_methods
  FROM public.users u
  WHERE u.id = p_landlord;
END;
$$;

REVOKE ALL ON FUNCTION public.landlord_contact_for_tenant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.landlord_contact_for_tenant(uuid) TO authenticated, service_role;

-- The old policy returned the landlord's entire users row.
DROP POLICY IF EXISTS "users: tenant reads own landlord" ON public.users;

-- Keep public.users and public.profiles phone and name together.
CREATE OR REPLACE FUNCTION public.sync_user_contact_to_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
     SET full_name = NEW.full_name,
         phone = NEW.phone,
         email = COALESCE(NEW.email, email)
   WHERE id = NEW.id;
  IF NOT FOUND THEN
    INSERT INTO public.profiles (id, email, full_name, phone, role)
    VALUES (NEW.id, NEW.email, NEW.full_name, NEW.phone, NEW.role)
    ON CONFLICT (id) DO UPDATE
      SET full_name = EXCLUDED.full_name,
          phone = EXCLUDED.phone,
          email = COALESCE(EXCLUDED.email, public.profiles.email);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_user_contact_to_profile ON public.users;
CREATE TRIGGER sync_user_contact_to_profile
  AFTER INSERT OR UPDATE OF full_name, phone, email ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_user_contact_to_profile();

REVOKE ALL ON FUNCTION public.sync_user_contact_to_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_user_contact_to_profile() TO authenticated, service_role;
