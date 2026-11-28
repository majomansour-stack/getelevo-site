-- ============================================================
-- ELEVO PRACTICE — a copy of the LIVE database schema.
--
-- Do not run this on the live project. Load it into an empty
-- Postgres database, then run 01_live_security_fixes.sql.
--
-- The live snapshot lists table and column names, policies,
-- function names, one trigger, grants, and bucket flags.
-- It does not include column types or function bodies.
--   * messages.unit_id is text NOT NULL (reported from live).
--   * Columns compared to auth.uid() or to units.id are uuid.
--   * years_in_business is text because the app stores phrases
--     such as "1 to 3 years".
--   * auto_link_tenant_on_signup, handle_new_user, and
--     rls_auto_enable have no source in the snapshot. The
--     trigger function below only links an invited unit. It
--     does not create a users row. 01 adds that separately.
-- auth and storage objects below exist so the policies can
-- load on plain Postgres. They are not a dump of Supabase internals.
--
-- Needs roles anon, authenticated, and service_role.
-- Create them once (they are cluster-wide) before this file:
--   CREATE ROLE anon NOLOGIN;
--   CREATE ROLE authenticated NOLOGIN;
--   CREATE ROLE service_role NOLOGIN BYPASSRLS;
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    RAISE EXCEPTION
      'Create roles anon, authenticated, and service_role before this file';
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  email text,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), ''),
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    'anon'
  );
$$;

CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
$$;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id text PRIMARY KEY,
  name text NOT NULL,
  public boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text REFERENCES storage.buckets (id),
  name text,
  owner uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION storage.foldername(name text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  parts text[];
BEGIN
  IF name IS NULL OR name = '' THEN
    RETURN ARRAY[]::text[];
  END IF;
  parts := string_to_array(name, '/');
  RETURN parts[1:array_length(parts, 1) - 1];
END;
$$;

-- ── public tables (live column names) ──
CREATE TABLE IF NOT EXISTS public.calendar_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  description text,
  end_date timestamptz,
  landlord_id uuid,
  property_id uuid,
  start_date timestamptz,
  title text,
  type text,
  unit_id uuid
);
CREATE TABLE IF NOT EXISTS public.documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  doc_type text,
  file_name text,
  file_size bigint,
  file_size_bytes bigint,
  file_type text,
  file_url text,
  landlord_id uuid,
  name text,
  owner_id uuid,
  tenant_id uuid,
  unit_id uuid
);
CREATE TABLE IF NOT EXISTS public.maintenance_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text,
  created_at timestamptz NOT NULL DEFAULT now(),
  description text,
  estimated_cost numeric,
  landlord_id uuid,
  priority text,
  resolved_date timestamptz,
  status text,
  tenant_id uuid,
  unit_address text,
  unit_id uuid,
  vendor_id uuid,
  vendor_name text
);
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content text,
  created_at timestamptz NOT NULL DEFAULT now(),
  is_read boolean NOT NULL DEFAULT false,
  receiver_id text,
  sender_id text,
  unit_id text NOT NULL
);
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  push_enabled boolean,
  updated_at timestamptz,
  user_id uuid
);
CREATE TABLE IF NOT EXISTS public.partner_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_name text,
  category text,
  created_at timestamptz NOT NULL DEFAULT now(),
  description text,
  email text,
  logo_url text,
  name text,
  owner_name text,
  phone text,
  rating numeric,
  review_count integer,
  service_area text,
  status text,
  tier text,
  website text,
  work_photos jsonb
);
CREATE TABLE IF NOT EXISTS public.payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bank_account text,
  bank_name text,
  bank_routing text,
  cashapp text,
  landlord_id uuid,
  other_instructions text,
  other_method text,
  paypal text,
  updated_at timestamptz,
  venmo text,
  zelle text
);
CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  amount numeric,
  confirmed_at timestamptz,
  confirmed_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  status text,
  submitted_at timestamptz,
  tenant_id uuid,
  unit_id uuid
);
CREATE TABLE IF NOT EXISTS public.photo_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  public_url text,
  room text,
  storage_path text,
  unit_id uuid
);
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY,
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  email text,
  full_name text,
  phone text,
  referral_code text,
  rentspree_disclosure_dismissed boolean,
  role text,
  subscription_plan text,
  trial_ends_at timestamptz,
  welcome_message_sent boolean
);
CREATE TABLE IF NOT EXISTS public.properties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  address text,
  address2 text,
  city text,
  created_at timestamptz NOT NULL DEFAULT now(),
  image_url text,
  landlord_id uuid,
  name text,
  state text,
  zip text
);
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_platform text,
  fcm_token text,
  updated_at timestamptz,
  user_id uuid
);
CREATE TABLE IF NOT EXISTS public.rent_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  changed_at timestamptz,
  changed_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  new_amount numeric,
  previous_amount numeric,
  unit_id uuid
);
CREATE TABLE IF NOT EXISTS public.tenant_emergency_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  name text,
  phone text,
  relationship text,
  tenant_id uuid
);
CREATE TABLE IF NOT EXISTS public.tenant_screenings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_email text,
  applicant_name text,
  applicant_phone text,
  created_at timestamptz NOT NULL DEFAULT now(),
  landlord_id uuid,
  notes text,
  status text,
  unit_id uuid
);
CREATE TABLE IF NOT EXISTS public.units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  deposit_amount numeric,
  invited_email text,
  landlord_id uuid,
  lease_end date,
  lease_start date,
  property_id uuid,
  rent_amount numeric,
  status text,
  tenant_id uuid,
  tenant_name text,
  unit_number text
);
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY,
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  email text,
  founding_member boolean,
  full_name text,
  language_preference text,
  payment_methods jsonb,
  phone text,
  referral_code text,
  role text,
  subscription_plan text,
  trial_ends_at timestamptz,
  unit_id uuid,
  welcome_message_sent boolean
);
CREATE TABLE IF NOT EXISTS public.vault_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  file_url text,
  landlord_id uuid,
  note text,
  title text,
  type text
);
CREATE TABLE IF NOT EXISTS public.vendor_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text,
  contractor_license text,
  created_at timestamptz NOT NULL DEFAULT now(),
  description text,
  email text,
  has_insurance boolean,
  license_number text,
  monthly_price numeric,
  name text,
  phone text,
  service_area text,
  status text,
  submitted_at timestamptz,
  tier text,
  website text,
  years_in_business text
);
CREATE TABLE IF NOT EXISTS public.vendor_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  listing_id uuid,
  message text,
  sender_id uuid
);
CREATE TABLE IF NOT EXISTS public.vendors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text,
  company_name text,
  created_at timestamptz NOT NULL DEFAULT now(),
  email text,
  is_active boolean,
  landlord_id uuid,
  name text,
  notes text,
  phone text,
  rating numeric,
  spend_limit numeric
);

-- ── functions named on live ──
-- Bodies were not in the snapshot.

CREATE OR REPLACE FUNCTION public.auto_link_tenant_on_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Name-only stand-in: link a new tenant to a unit invited with their email.
  -- Does not insert public.users. 01 adds a separate trigger for that.
  IF COALESCE(NEW.raw_user_meta_data ->> 'role', '') = 'tenant'
     AND NEW.email IS NOT NULL THEN
    UPDATE public.units
       SET tenant_id = NEW.id,
           status = 'occupied'
     WHERE tenant_id IS NULL
       AND invited_email IS NOT NULL
       AND lower(invited_email) = lower(NEW.email);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Present on live and not attached to a trigger. Body was not in the snapshot.
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table', 'partitioned table')
  LOOP
    IF cmd.schema_name = 'public' THEN
      BEGIN
        EXECUTE format('ALTER TABLE IF EXISTS %s ENABLE ROW LEVEL SECURITY', cmd.object_identity);
      EXCEPTION
        WHEN OTHERS THEN
          NULL;
      END;
    END IF;
  END LOOP;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_link_tenant_on_signup();

-- ── row level security, then the live policies ──
ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.photo_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rent_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_screenings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vault_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendor_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendor_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Landlord can insert calendar events" ON public.calendar_events;
CREATE POLICY "Landlord can insert calendar events"
  ON public.calendar_events
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "Landlord manages events" ON public.calendar_events;
CREATE POLICY "Landlord manages events"
  ON public.calendar_events
  FOR ALL
  TO authenticated
  USING (auth.uid() = landlord_id)
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "Owner manages documents" ON public.documents;
CREATE POLICY "Owner manages documents"
  ON public.documents
  FOR ALL
  TO authenticated
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "Landlord manages maintenance" ON public.maintenance_requests;
CREATE POLICY "Landlord manages maintenance"
  ON public.maintenance_requests
  FOR ALL
  TO authenticated
  USING (auth.uid() = landlord_id)
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "Tenant reads own maintenance" ON public.maintenance_requests;
CREATE POLICY "Tenant reads own maintenance"
  ON public.maintenance_requests
  FOR SELECT
  TO authenticated
  USING (auth.uid() = tenant_id);

DROP POLICY IF EXISTS "Tenant submits maintenance" ON public.maintenance_requests;
CREATE POLICY "Tenant submits maintenance"
  ON public.maintenance_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = tenant_id);

DROP POLICY IF EXISTS "Vendor reads assigned maintenance" ON public.maintenance_requests;
CREATE POLICY "Vendor reads assigned maintenance"
  ON public.maintenance_requests
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Vendor updates assigned maintenance" ON public.maintenance_requests;
CREATE POLICY "Vendor updates assigned maintenance"
  ON public.maintenance_requests
  FOR UPDATE
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users read messages" ON public.messages;
CREATE POLICY "Authenticated users read messages"
  ON public.messages
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users send messages" ON public.messages;
CREATE POLICY "Authenticated users send messages"
  ON public.messages
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users update messages" ON public.messages;
CREATE POLICY "Authenticated users update messages"
  ON public.messages
  FOR UPDATE
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "notification_preferences: users manage own" ON public.notification_preferences;
CREATE POLICY "notification_preferences: users manage own"
  ON public.notification_preferences
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Anyone can view active listings" ON public.partner_listings;
CREATE POLICY "Anyone can view active listings"
  ON public.partner_listings
  FOR SELECT
  TO public
  USING (status = 'active'::text);

DROP POLICY IF EXISTS "Anyone reads partner listings" ON public.partner_listings;
CREATE POLICY "Anyone reads partner listings"
  ON public.partner_listings
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert" ON public.partner_listings;
CREATE POLICY "Authenticated users can insert"
  ON public.partner_listings
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "payment_methods: landlord manage own" ON public.payment_methods;
CREATE POLICY "payment_methods: landlord manage own"
  ON public.payment_methods
  FOR ALL
  TO authenticated
  USING (landlord_id = auth.uid())
  WITH CHECK (landlord_id = auth.uid());

DROP POLICY IF EXISTS "payment_methods: tenant read landlord" ON public.payment_methods;
CREATE POLICY "payment_methods: tenant read landlord"
  ON public.payment_methods
  FOR SELECT
  TO authenticated
  USING (EXISTS ( SELECT 1
   FROM units
  WHERE ((units.tenant_id = auth.uid()) AND (units.landlord_id = payment_methods.landlord_id))));

DROP POLICY IF EXISTS "Landlords can read unit payments" ON public.payments;
CREATE POLICY "Landlords can read unit payments"
  ON public.payments
  FOR SELECT
  TO public
  USING (EXISTS ( SELECT 1
   FROM (units u
     JOIN properties p ON ((p.id = u.property_id)))
  WHERE ((u.id = payments.unit_id) AND (p.landlord_id = auth.uid()))));

DROP POLICY IF EXISTS "Landlords can update payment status" ON public.payments;
CREATE POLICY "Landlords can update payment status"
  ON public.payments
  FOR UPDATE
  TO public
  USING (EXISTS ( SELECT 1
   FROM (units u
     JOIN properties p ON ((p.id = u.property_id)))
  WHERE ((u.id = payments.unit_id) AND (p.landlord_id = auth.uid()))));

DROP POLICY IF EXISTS "Tenants can insert own payments" ON public.payments;
CREATE POLICY "Tenants can insert own payments"
  ON public.payments
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() = tenant_id);

DROP POLICY IF EXISTS "Tenants can read own payments" ON public.payments;
CREATE POLICY "Tenants can read own payments"
  ON public.payments
  FOR SELECT
  TO public
  USING (auth.uid() = tenant_id);

DROP POLICY IF EXISTS "Landlords can insert photo logs for their units" ON public.photo_logs;
CREATE POLICY "Landlords can insert photo logs for their units"
  ON public.photo_logs
  FOR INSERT
  TO authenticated
  WITH CHECK (unit_id IN ( SELECT u.id
   FROM (units u
     JOIN properties p ON ((p.id = u.property_id)))
  WHERE (p.landlord_id = auth.uid())));

DROP POLICY IF EXISTS "Landlords can read photo logs for their units" ON public.photo_logs;
CREATE POLICY "Landlords can read photo logs for their units"
  ON public.photo_logs
  FOR SELECT
  TO authenticated
  USING (unit_id IN ( SELECT u.id
   FROM (units u
     JOIN properties p ON ((p.id = u.property_id)))
  WHERE (p.landlord_id = auth.uid())));

DROP POLICY IF EXISTS "Tenants can insert photo logs for their unit" ON public.photo_logs;
CREATE POLICY "Tenants can insert photo logs for their unit"
  ON public.photo_logs
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() IN ( SELECT units.tenant_id
   FROM units
  WHERE ((units.id = photo_logs.unit_id) AND (units.tenant_id IS NOT NULL))));

DROP POLICY IF EXISTS "Tenants can read photo logs for their unit" ON public.photo_logs;
CREATE POLICY "Tenants can read photo logs for their unit"
  ON public.photo_logs
  FOR SELECT
  TO authenticated
  USING (auth.uid() IN ( SELECT units.tenant_id
   FROM units
  WHERE ((units.id = photo_logs.unit_id) AND (units.tenant_id IS NOT NULL))));

DROP POLICY IF EXISTS "profiles: users insert own" ON public.profiles;
CREATE POLICY "profiles: users insert own"
  ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "profiles: users read own" ON public.profiles;
CREATE POLICY "profiles: users read own"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());

DROP POLICY IF EXISTS "profiles: users update own" ON public.profiles;
CREATE POLICY "profiles: users update own"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Landlord can insert properties" ON public.properties;
CREATE POLICY "Landlord can insert properties"
  ON public.properties
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "Landlord owns properties" ON public.properties;
CREATE POLICY "Landlord owns properties"
  ON public.properties
  FOR ALL
  TO authenticated
  USING (auth.uid() = landlord_id)
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "Tenants read own property" ON public.properties;
CREATE POLICY "Tenants read own property"
  ON public.properties
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "push_subscriptions: service role delete unregistered" ON public.push_subscriptions;
CREATE POLICY "push_subscriptions: service role delete unregistered"
  ON public.push_subscriptions
  FOR DELETE
  TO service_role
  USING (true);

DROP POLICY IF EXISTS "push_subscriptions: service role read all" ON public.push_subscriptions;
CREATE POLICY "push_subscriptions: service role read all"
  ON public.push_subscriptions
  FOR SELECT
  TO service_role
  USING (true);

DROP POLICY IF EXISTS "push_subscriptions: users manage own" ON public.push_subscriptions;
CREATE POLICY "push_subscriptions: users manage own"
  ON public.push_subscriptions
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Landlords can insert rent history" ON public.rent_history;
CREATE POLICY "Landlords can insert rent history"
  ON public.rent_history
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() = changed_by);

DROP POLICY IF EXISTS "Landlords can read rent history" ON public.rent_history;
CREATE POLICY "Landlords can read rent history"
  ON public.rent_history
  FOR SELECT
  TO public
  USING (EXISTS ( SELECT 1
   FROM (units u
     JOIN properties p ON ((p.id = u.property_id)))
  WHERE ((u.id = rent_history.unit_id) AND (p.landlord_id = auth.uid()))));

DROP POLICY IF EXISTS "Tenant manages own emergency contacts" ON public.tenant_emergency_contacts;
CREATE POLICY "Tenant manages own emergency contacts"
  ON public.tenant_emergency_contacts
  FOR ALL
  TO public
  USING (auth.uid() = tenant_id);

DROP POLICY IF EXISTS "emergency_contacts: insert own" ON public.tenant_emergency_contacts;
CREATE POLICY "emergency_contacts: insert own"
  ON public.tenant_emergency_contacts
  FOR INSERT
  TO authenticated
  WITH CHECK (tenant_id = auth.uid());

DROP POLICY IF EXISTS "emergency_contacts: tenant read own" ON public.tenant_emergency_contacts;
CREATE POLICY "emergency_contacts: tenant read own"
  ON public.tenant_emergency_contacts
  FOR SELECT
  TO authenticated
  USING (tenant_id = auth.uid());

DROP POLICY IF EXISTS "Landlord manages screenings" ON public.tenant_screenings;
CREATE POLICY "Landlord manages screenings"
  ON public.tenant_screenings
  FOR ALL
  TO authenticated
  USING (auth.uid() = landlord_id)
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "screenings: landlord insert" ON public.tenant_screenings;
CREATE POLICY "screenings: landlord insert"
  ON public.tenant_screenings
  FOR INSERT
  TO authenticated
  WITH CHECK (landlord_id = auth.uid());

DROP POLICY IF EXISTS "screenings: landlord read own" ON public.tenant_screenings;
CREATE POLICY "screenings: landlord read own"
  ON public.tenant_screenings
  FOR SELECT
  TO authenticated
  USING (landlord_id = auth.uid());

DROP POLICY IF EXISTS "screenings: landlord update own" ON public.tenant_screenings;
CREATE POLICY "screenings: landlord update own"
  ON public.tenant_screenings
  FOR UPDATE
  TO authenticated
  USING (landlord_id = auth.uid());

DROP POLICY IF EXISTS "Landlord can insert units" ON public.units;
CREATE POLICY "Landlord can insert units"
  ON public.units
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() = ( SELECT properties.landlord_id
   FROM properties
  WHERE (properties.id = units.property_id)));

DROP POLICY IF EXISTS "Landlord owns units" ON public.units;
CREATE POLICY "Landlord owns units"
  ON public.units
  FOR ALL
  TO authenticated
  USING (auth.uid() = landlord_id)
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "Tenant reads own unit" ON public.units;
CREATE POLICY "Tenant reads own unit"
  ON public.units
  FOR SELECT
  TO authenticated
  USING (auth.uid() = tenant_id);

DROP POLICY IF EXISTS "Users read own" ON public.users;
CREATE POLICY "Users read own"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users update own" ON public.users;
CREATE POLICY "Users update own"
  ON public.users
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "landlord_own_vault" ON public.vault_items;
CREATE POLICY "landlord_own_vault"
  ON public.vault_items
  FOR ALL
  TO public
  USING (landlord_id = auth.uid());

DROP POLICY IF EXISTS "vault: landlord delete own" ON public.vault_items;
CREATE POLICY "vault: landlord delete own"
  ON public.vault_items
  FOR DELETE
  TO authenticated
  USING (landlord_id = auth.uid());

DROP POLICY IF EXISTS "vault: landlord insert own" ON public.vault_items;
CREATE POLICY "vault: landlord insert own"
  ON public.vault_items
  FOR INSERT
  TO authenticated
  WITH CHECK (landlord_id = auth.uid());

DROP POLICY IF EXISTS "vault: landlord read own" ON public.vault_items;
CREATE POLICY "vault: landlord read own"
  ON public.vault_items
  FOR SELECT
  TO authenticated
  USING (landlord_id = auth.uid());

DROP POLICY IF EXISTS "vault: landlord update own" ON public.vault_items;
CREATE POLICY "vault: landlord update own"
  ON public.vault_items
  FOR UPDATE
  TO authenticated
  USING (landlord_id = auth.uid());

DROP POLICY IF EXISTS "Admin reads applications" ON public.vendor_applications;
CREATE POLICY "Admin reads applications"
  ON public.vendor_applications
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Admin updates applications" ON public.vendor_applications;
CREATE POLICY "Admin updates applications"
  ON public.vendor_applications
  FOR UPDATE
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Anyone submits application" ON public.vendor_applications;
CREATE POLICY "Anyone submits application"
  ON public.vendor_applications
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Anyone sends contact" ON public.vendor_contacts;
CREATE POLICY "Anyone sends contact"
  ON public.vendor_contacts
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "vendor_contacts: authenticated insert" ON public.vendor_contacts;
CREATE POLICY "vendor_contacts: authenticated insert"
  ON public.vendor_contacts
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "vendor_contacts: read by listing" ON public.vendor_contacts;
CREATE POLICY "vendor_contacts: read by listing"
  ON public.vendor_contacts
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can delete own vendors" ON public.vendors;
CREATE POLICY "Authenticated users can delete own vendors"
  ON public.vendors
  FOR DELETE
  TO public
  USING ((auth.uid())::text = (landlord_id)::text);

DROP POLICY IF EXISTS "Authenticated users can read vendors" ON public.vendors;
CREATE POLICY "Authenticated users can read vendors"
  ON public.vendors
  FOR SELECT
  TO public
  USING (auth.role() = 'authenticated'::text);

DROP POLICY IF EXISTS "Landlord can insert vendors" ON public.vendors;
CREATE POLICY "Landlord can insert vendors"
  ON public.vendors
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "Landlord manages vendors" ON public.vendors;
CREATE POLICY "Landlord manages vendors"
  ON public.vendors
  FOR ALL
  TO authenticated
  USING (auth.uid() = landlord_id)
  WITH CHECK (auth.uid() = landlord_id);

DROP POLICY IF EXISTS "Authenticated users read documents" ON storage.objects;
CREATE POLICY "Authenticated users read documents"
  ON storage.objects
  FOR SELECT
  TO public
  USING ((bucket_id = 'documents'::text) AND (auth.role() = 'authenticated'::text));

DROP POLICY IF EXISTS "Authenticated users upload avatar" ON storage.objects;
CREATE POLICY "Authenticated users upload avatar"
  ON storage.objects
  FOR INSERT
  TO public
  WITH CHECK ((bucket_id = 'avatars'::text) AND (auth.role() = 'authenticated'::text));

DROP POLICY IF EXISTS "Authenticated users upload documents" ON storage.objects;
CREATE POLICY "Authenticated users upload documents"
  ON storage.objects
  FOR INSERT
  TO public
  WITH CHECK ((bucket_id = 'documents'::text) AND (auth.role() = 'authenticated'::text));

DROP POLICY IF EXISTS "Authenticated users upload maintenance photos" ON storage.objects;
CREATE POLICY "Authenticated users upload maintenance photos"
  ON storage.objects
  FOR INSERT
  TO public
  WITH CHECK ((bucket_id = 'maintenance-photos'::text) AND (auth.role() = 'authenticated'::text));

DROP POLICY IF EXISTS "Authenticated users view maintenance photos" ON storage.objects;
CREATE POLICY "Authenticated users view maintenance photos"
  ON storage.objects
  FOR SELECT
  TO public
  USING ((bucket_id = 'maintenance-photos'::text) AND (auth.role() = 'authenticated'::text));

DROP POLICY IF EXISTS "Public avatar read" ON storage.objects;
CREATE POLICY "Public avatar read"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'avatars'::text);

DROP POLICY IF EXISTS "Public partner logo read" ON storage.objects;
CREATE POLICY "Public partner logo read"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'partner-logos'::text);

DROP POLICY IF EXISTS "Tenants can read photo logs" ON storage.objects;
CREATE POLICY "Tenants can read photo logs"
  ON storage.objects
  FOR SELECT
  TO public
  USING ((bucket_id = 'photo-logs'::text) AND (auth.role() = 'authenticated'::text));

DROP POLICY IF EXISTS "Tenants can upload photo logs" ON storage.objects;
CREATE POLICY "Tenants can upload photo logs"
  ON storage.objects
  FOR INSERT
  TO public
  WITH CHECK ((bucket_id = 'photo-logs'::text) AND (auth.role() = 'authenticated'::text));

DROP POLICY IF EXISTS "avatars: authenticated read own" ON storage.objects;
CREATE POLICY "avatars: authenticated read own"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING ((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text));

DROP POLICY IF EXISTS "avatars: authenticated upload own" ON storage.objects;
CREATE POLICY "avatars: authenticated upload own"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK ((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text));

DROP POLICY IF EXISTS "documents: authenticated users upload own path" ON storage.objects;
CREATE POLICY "documents: authenticated users upload own path"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK ((bucket_id = 'documents'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text));

DROP POLICY IF EXISTS "documents: landlords read properties docs" ON storage.objects;
CREATE POLICY "documents: landlords read properties docs"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING ((bucket_id = 'documents'::text) AND (EXISTS ( SELECT 1
   FROM users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['landlord'::text, 'admin'::text]))))));

DROP POLICY IF EXISTS "documents: tenants read own docs" ON storage.objects;
CREATE POLICY "documents: tenants read own docs"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING ((bucket_id = 'documents'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text));

DROP POLICY IF EXISTS "maintenance-photos: landlords read all" ON storage.objects;
CREATE POLICY "maintenance-photos: landlords read all"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING ((bucket_id = 'maintenance-photos'::text) AND (EXISTS ( SELECT 1
   FROM users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['landlord'::text, 'admin'::text]))))));

DROP POLICY IF EXISTS "maintenance-photos: tenants read own" ON storage.objects;
CREATE POLICY "maintenance-photos: tenants read own"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING ((bucket_id = 'maintenance-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text));

DROP POLICY IF EXISTS "maintenance-photos: tenants upload own" ON storage.objects;
CREATE POLICY "maintenance-photos: tenants upload own"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK ((bucket_id = 'maintenance-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text));

DROP POLICY IF EXISTS "photo-logs: read own unit photos" ON storage.objects;
CREATE POLICY "photo-logs: read own unit photos"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (bucket_id = 'photo-logs'::text);

DROP POLICY IF EXISTS "photo-logs: upload own unit photos" ON storage.objects;
CREATE POLICY "photo-logs: upload own unit photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'photo-logs'::text);

DROP POLICY IF EXISTS "private-vault: landlord insert own folder" ON storage.objects;
CREATE POLICY "private-vault: landlord insert own folder"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK ((bucket_id = 'private-vault'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['landlord'::text, 'admin'::text]))))));

DROP POLICY IF EXISTS "private-vault: landlord select own folder" ON storage.objects;
CREATE POLICY "private-vault: landlord select own folder"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING ((bucket_id = 'private-vault'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['landlord'::text, 'admin'::text]))))));


-- ── grants from the live snapshot (public tables, all privileges) ──

GRANT USAGE ON SCHEMA public, auth, storage TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.jwt() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION storage.foldername(text) TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.calendar_events TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.documents TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.maintenance_requests TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.messages TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.notification_preferences TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.partner_listings TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.payment_methods TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.payments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.photo_logs TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.profiles TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.properties TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.push_subscriptions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.rent_history TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tenant_emergency_contacts TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.tenant_screenings TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.units TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.users TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.vault_items TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.vendor_applications TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.vendor_contacts TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.vendors TO anon, authenticated, service_role;

GRANT ALL ON TABLE storage.buckets TO anon, authenticated, service_role;
GRANT ALL ON TABLE storage.objects TO anon, authenticated, service_role;

-- ── buckets. photo-logs is public on live. The others are private. ──

INSERT INTO storage.buckets (id, name, public) VALUES
  ('avatars', 'avatars', false),
  ('documents', 'documents', false),
  ('maintenance-photos', 'maintenance-photos', false),
  ('photo-logs', 'photo-logs', true),
  ('private-vault', 'private-vault', false)
ON CONFLICT (id) DO NOTHING;

-- Realtime publication exists on live, and messages is not in it yet.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;
