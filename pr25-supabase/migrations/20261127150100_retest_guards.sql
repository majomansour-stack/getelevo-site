-- Apply after 20261127150000_vendor_view_write_grants.sql.
-- Does not touch live data by itself; run it on practice before live.

-- Tenants must not insert a message with sender_id = 'system'.
-- The welcome text is inserted only by send_tenant_welcome, which checks
-- that the caller is the unit's tenant and has not already been welcomed.
CREATE OR REPLACE FUNCTION public.can_send_unit_message(
  p_unit text,
  p_sender text,
  p_receiver text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_unit uuid;
  v_landlord uuid;
  v_tenant uuid;
  sender_role text;
  receiver_role text;
BEGIN
  IF uid IS NULL OR p_unit IS NULL OR btrim(p_unit) = ''
     OR p_receiver IS NULL OR btrim(p_receiver) = '' THEN
    RETURN false;
  END IF;

  IF lower(btrim(COALESCE(p_sender, ''))) = 'system' THEN
    RETURN false;
  END IF;

  SELECT id, landlord_id, tenant_id
    INTO v_unit, v_landlord, v_tenant
  FROM public.units
  WHERE id::text = p_unit;

  IF v_landlord IS NULL OR v_unit IS NULL THEN
    RETURN false;
  END IF;

  IF p_sender IS DISTINCT FROM uid::text THEN
    RETURN false;
  END IF;

  IF uid = v_landlord THEN
    sender_role := 'landlord';
  ELSIF v_tenant IS NOT NULL AND uid = v_tenant THEN
    sender_role := 'tenant';
  ELSIF public.vendor_assigned_to_unit(uid, v_unit) THEN
    sender_role := 'vendor';
  ELSE
    RETURN false;
  END IF;

  IF p_receiver = v_landlord::text THEN
    receiver_role := 'landlord';
  ELSIF v_tenant IS NOT NULL AND p_receiver = v_tenant::text THEN
    receiver_role := 'tenant';
  ELSIF p_receiver ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        AND public.vendor_assigned_to_unit(p_receiver::uuid, v_unit) THEN
    receiver_role := 'vendor';
  ELSE
    RETURN false;
  END IF;

  RETURN sender_role IS DISTINCT FROM receiver_role;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_tenant_welcome(p_unit uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  body text :=
    'Welcome to ELEVO — we are so glad to have you here.' || E'\n\n' ||
    'You have been successfully added to ELEVO, your property management portal. ' ||
    'Here is everything you need to know to get started:' || E'\n\n' ||
    'All communication with your landlord should go through this app for the fastest response. ' ||
    'This includes maintenance requests, questions about your lease, and any general messages. ' ||
    'Messages sent through ELEVO are tracked and responded to faster than phone calls or emails.' || E'\n\n' ||
    'Here is what we recommend you do right now to get set up:' || E'\n\n' ||
    'First, go to the Documents section and review your lease agreement and any move-in paperwork ' ||
    'that has been shared with you.' || E'\n\n' ||
    'Second, upload your move-in photos. Go to the Photo Log section and upload photos of every room, ' ||
    'every wall, every appliance, and any existing damage you notice before you move in. ' ||
    'Label each photo clearly by room. These photos protect your security deposit when you move out ' ||
    'so be thorough.' || E'\n\n' ||
    'Third, make sure your notification settings are turned on so you never miss a message from ' ||
    'your landlord.' || E'\n\n' ||
    'If you have any questions your landlord is available through the Messages tab. Welcome home.';
BEGIN
  IF uid IS NULL OR p_unit IS NULL THEN
    RAISE EXCEPTION 'not allowed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.units u
    WHERE u.id = p_unit AND u.tenant_id = uid
  ) THEN
    RAISE EXCEPTION 'not allowed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.users
    WHERE id = uid AND welcome_message_sent IS TRUE
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.messages (unit_id, sender_id, receiver_id, content, is_read)
  VALUES (p_unit, 'system', uid::text, body, true);

  UPDATE public.users
  SET welcome_message_sent = true
  WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.send_tenant_welcome(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_tenant_welcome(uuid) TO authenticated, service_role;

-- Landlords looked up a vendor login by reading public.users, which also
-- returned subscription_plan and subscription_status. The directory view
-- exposes only the contact fields needed to link a job.
DROP POLICY IF EXISTS "users: landlord reads vendor accounts" ON public.users;

CREATE OR REPLACE VIEW public.vendor_login_for_landlord
WITH (security_invoker = false) AS
SELECT u.id, u.email, u.full_name, u.phone, u.role
FROM public.users u
WHERE u.role = 'vendor'
  AND public.current_user_role() IN ('landlord', 'admin');

REVOKE ALL ON public.vendor_login_for_landlord FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.vendor_login_for_landlord TO authenticated;
GRANT ALL ON public.vendor_login_for_landlord TO service_role;

-- A vendor update may change status and completion fields, not the
-- landlord's note, and may not move a job back to Submitted.
CREATE OR REPLACE FUNCTION public.guard_vendor_job_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF public.current_user_role() = 'vendor' THEN
    NEW.landlord_notes := OLD.landlord_notes;
    IF lower(btrim(COALESCE(NEW.status, ''))) IN ('open', 'submitted')
       AND lower(btrim(COALESCE(OLD.status, ''))) NOT IN ('open', 'submitted') THEN
      RAISE EXCEPTION 'A vendor cannot move a job back to Submitted';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_vendor_job_update ON public.maintenance_requests;
CREATE TRIGGER guard_vendor_job_update
  BEFORE UPDATE ON public.maintenance_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_vendor_job_update();

-- The documents bucket had no DELETE policy, so a file uploaded to the
-- wrong unit stayed in storage after the row was removed. Only the
-- landlord who owns the first folder (their own uploads) can delete it.
DROP POLICY IF EXISTS "documents: landlord deletes own file" ON storage.objects;
CREATE POLICY "documents: landlord deletes own file"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.current_user_role() IN ('landlord', 'admin')
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
