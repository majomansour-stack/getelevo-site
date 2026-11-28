-- ============================================================
-- NOT A LIVE MIGRATION.
-- This is a reconstruction of the core tables Primio created
-- in the production project. The repo itself has no CREATE
-- TABLE for those tables. Use it only to stand up a practice
-- or local database. Do not run it against production.
-- ============================================================

-- ============================================================
-- ELEVO PRACTICE — base schema RECONSTRUCTED from the app code
-- (repo has no CREATE TABLE for the core tables; live schema was
-- built by Primio). Practice project only.
-- ============================================================
create extension if not exists pgcrypto;

-- helper: is the caller an admin? SECURITY DEFINER avoids RLS recursion
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text default '',
  role text not null default 'landlord',
  phone text,
  avatar_url text,
  subscription_plan text default 'trial',
  trial_ends_at timestamptz,
  founding_member boolean default false,
  referral_code text,
  language_preference text default 'en',
  welcome_message_sent boolean default false,
  payment_methods jsonb,
  unit_id uuid,
  created_at timestamptz not null default now()
);
alter table public.users enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.users where id = auth.uid() and role = 'admin');
$$;

-- auto-create a users row on sign-up (app comments: "users row was auto-created")
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, email, full_name, role, phone, subscription_plan, trial_ends_at)
  values (
    new.id,
    lower(new.email),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    case when new.raw_user_meta_data->>'role' in ('landlord','tenant','vendor')
         then new.raw_user_meta_data->>'role' else 'landlord' end,
    coalesce(new.raw_user_meta_data->>'phone', ''),
    'trial',
    now() + interval '7 days'
  ) on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null references auth.users(id) on delete cascade,
  name text not null default '',
  address text not null default '',
  address2 text default '',
  city text default '',
  state text default 'AZ',
  zip text default '',
  image_url text,
  rentspree_link text,
  property_type text,
  created_at timestamptz not null default now()
);

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  landlord_id uuid not null references auth.users(id) on delete cascade,
  unit_number text not null default '1',
  status text not null default 'vacant',
  rent_amount numeric not null default 0,
  deposit_amount numeric not null default 0,
  additional_deposit numeric default 0,
  bedrooms numeric,
  bathrooms numeric,
  lease_start date,
  lease_end date,
  tenant_id uuid references auth.users(id) on delete set null,
  tenant_name text,
  invited_email text,
  created_at timestamptz not null default now()
);

create table if not exists public.maintenance_requests (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id) on delete cascade,
  tenant_id uuid,
  landlord_id uuid,
  vendor_id uuid,           -- vendors.id OR a vendor auth uid (app mixes both)
  vendor_name text,
  category text,
  description text not null default '',
  priority text default 'medium',
  status text not null default 'open',
  estimated_cost numeric,
  image_url text,
  unit_address text,
  landlord_notes text,
  notes text,
  invoice_url text,
  resolved_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id) on delete cascade,
  sender_id text not null,     -- text: the app inserts sender_id = 'system'
  receiver_id text,
  content text not null default '',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid,
  unit_id uuid references public.units(id) on delete cascade,
  amount numeric not null default 0,
  status text not null default 'pending_confirmation',
  submitted_at timestamptz default now(),
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null unique,
  zelle text, venmo text, cashapp text, paypal text,
  bank_name text, bank_routing text, bank_account text,
  other_method text, other_instructions text,
  methods jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create table if not exists public.rent_history (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id) on delete cascade,
  previous_amount numeric, new_amount numeric,
  changed_by uuid, changed_at timestamptz default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null,
  subject text, message text, recipient_count int default 0,
  recipient_scope text default 'all',
  sent_at timestamptz default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null,
  title text not null default '',
  description text,
  start_date timestamptz not null default now(),
  end_date timestamptz,
  type text default 'other',
  unit_id uuid, property_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.vendors (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null,
  name text not null default '',
  company_name text, category text, phone text, email text,
  spend_limit numeric default 0,
  is_active boolean default true,
  created_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid, landlord_id uuid, tenant_id uuid,
  file_name text, doc_type text, file_url text, file_size_bytes bigint,
  created_at timestamptz not null default now()
);

create table if not exists public.vault_items (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null,
  type text, title text, content text, file_url text,
  unit_id uuid, unit_label text,
  created_at timestamptz not null default now()
);

create table if not exists public.tenant_emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  name text, phone text, relationship text,
  created_at timestamptz not null default now()
);

create table if not exists public.tenant_screenings (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null,
  applicant_name text, applicant_first_name text, applicant_last_name text,
  applicant_email text, property_id uuid, property_address text,
  unit_id uuid, unit_number text, screening_type text, screening_fee numeric,
  status text default 'invited', notes text,
  invited_at timestamptz default now(), completed_at timestamptz,
  approved_at timestamptz, declined_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.vendor_contacts (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid, contacted_by uuid, contact_type text,
  contacted_at timestamptz default now()
);

create table if not exists public.photo_logs (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id) on delete cascade,
  room text, storage_path text, public_url text,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.partner_listings (
  id uuid primary key default gen_random_uuid(),
  business_name text, owner_name text, category text, description text,
  phone text, email text, website text, service_area text,
  tier text, status text default 'active', license_number text,
  has_insurance boolean default false, logo_url text,
  rating numeric default 0, review_count int default 0,
  work_photos jsonb default '[]'::jsonb, monthly_price numeric,
  created_at timestamptz not null default now()
);

create table if not exists public.vendor_applications (
  id uuid primary key default gen_random_uuid(),
  business_name text, owner_name text, category text, years_in_business int,
  phone text, email text, website text, service_area text,
  license_number text, contractor_license text, has_insurance boolean default false,
  tier text, status text default 'pending', monthly_price numeric,
  description text,
  submitted_at timestamptz default now(), approved_at timestamptz, declined_at timestamptz
);

-- enable RLS everywhere
do $$ declare t text; begin
  foreach t in array array['properties','units','maintenance_requests','messages','payments',
    'payment_methods','rent_history','announcements','calendar_events','vendors','documents',
    'vault_items','tenant_emergency_contacts','tenant_screenings','vendor_contacts','photo_logs',
    'partner_listings','vendor_applications'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop; end $$;

-- ── reconstructed RLS for core tables (repo has none for these) ──
-- properties
create policy "properties: landlord manages own" on public.properties for all to authenticated
  using (landlord_id = auth.uid() or public.is_admin()) with check (landlord_id = auth.uid() or public.is_admin());
create policy "properties: tenant reads own" on public.properties for select to authenticated
  using (id in (select un.property_id from public.units un
                where un.tenant_id = auth.uid() or lower(un.invited_email) = lower(auth.jwt()->>'email')));
-- units
create policy "units: landlord manages own" on public.units for all to authenticated
  using (landlord_id = auth.uid() or public.is_admin()) with check (landlord_id = auth.uid() or public.is_admin());
create policy "units: tenant reads own or invited" on public.units for select to authenticated
  using (tenant_id = auth.uid() or lower(invited_email) = lower(auth.jwt()->>'email'));
create policy "units: tenant claims invite" on public.units for update to authenticated
  using (tenant_id = auth.uid() or (tenant_id is null and lower(invited_email) = lower(auth.jwt()->>'email')))
  with check (tenant_id = auth.uid());
-- maintenance
create policy "maintenance: landlord manages own" on public.maintenance_requests for all to authenticated
  using (landlord_id = auth.uid() or public.is_admin()) with check (landlord_id = auth.uid() or public.is_admin());
create policy "maintenance: tenant reads own" on public.maintenance_requests for select to authenticated
  using (tenant_id = auth.uid());
create policy "maintenance: tenant creates own" on public.maintenance_requests for insert to authenticated
  with check (tenant_id = auth.uid());
-- messages: landlord reads the whole unit (including tenant-vendor notes).
-- Everyone else reads only rows they sent or received.
-- Insert rules live in fixes_pending_owner_approval.sql (can_send_unit_message).
-- This reconstruction keeps a tighter stand-in so a practice rebuild is not wide open.
create policy "messages: participants read" on public.messages for select to authenticated
  using (sender_id = auth.uid()::text or receiver_id = auth.uid()::text
    or unit_id in (select id from public.units where landlord_id = auth.uid()));
create policy "messages: send as self" on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid()::text
    or (sender_id = 'system' and receiver_id = auth.uid()::text)
  );
create policy "messages: receiver marks read" on public.messages for update to authenticated
  using (receiver_id = auth.uid()::text) with check (receiver_id = auth.uid()::text);
-- payments
create policy "payments: tenant creates own" on public.payments for insert to authenticated
  with check (tenant_id = auth.uid() and unit_id in (select id from public.units where tenant_id = auth.uid()));
create policy "payments: tenant reads own unit" on public.payments for select to authenticated
  using (unit_id in (select id from public.units where tenant_id = auth.uid()));
create policy "payments: landlord manages own units" on public.payments for all to authenticated
  using (unit_id in (select id from public.units where landlord_id = auth.uid()))
  with check (unit_id in (select id from public.units where landlord_id = auth.uid()));
-- payment methods
-- These two policies are the practice stand-in. Replace them by running
-- supabase/payment_methods_access.sql, which limits tenants to their own
-- unit's landlord and uses current_user_role() instead of reading users.
create policy "payment_methods: landlord manages own" on public.payment_methods for all to authenticated
  using (landlord_id = auth.uid()) with check (landlord_id = auth.uid());
create policy "payment_methods: tenant reads own landlord" on public.payment_methods for select to authenticated
  using (landlord_id in (select landlord_id from public.units where tenant_id = auth.uid()));
-- rent history
create policy "rent_history: landlord manages own units" on public.rent_history for all to authenticated
  using (unit_id in (select id from public.units where landlord_id = auth.uid()))
  with check (unit_id in (select id from public.units where landlord_id = auth.uid()));
create policy "rent_history: tenant reads own unit" on public.rent_history for select to authenticated
  using (unit_id in (select id from public.units where tenant_id = auth.uid()));
-- announcements, calendar, vendors (landlord-owned)
create policy "announcements: landlord manages own" on public.announcements for all to authenticated
  using (landlord_id = auth.uid()) with check (landlord_id = auth.uid());
create policy "calendar_events: landlord manages own" on public.calendar_events for all to authenticated
  using (landlord_id = auth.uid()) with check (landlord_id = auth.uid());
create policy "vendors: landlord manages own" on public.vendors for all to authenticated
  using (landlord_id = auth.uid()) with check (landlord_id = auth.uid());
-- vault delete/insert/update come from table_rls_policies.sql; select from fixes file
-- partner marketplace
create policy "partner_listings: signed-in read active" on public.partner_listings for select to authenticated
  using (status = 'active' or public.is_admin());
create policy "partner_listings: admin manages" on public.partner_listings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "vendor_applications: anyone applies" on public.vendor_applications for insert to anon, authenticated
  with check (status = 'pending');
create policy "vendor_applications: admin manages" on public.vendor_applications for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "users: admin reads all" on public.users for select to authenticated
  using (public.is_admin());

-- realtime for chat
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin execute 'alter publication supabase_realtime add table public.messages';
    exception when duplicate_object then null; end;
  end if;
end $$;

-- storage buckets (private, per storage_rls_policies.sql header)
insert into storage.buckets (id, name, public) values
  ('documents','documents',false), ('private-vault','private-vault',false),
  ('photo-logs','photo-logs',false), ('maintenance-photos','maintenance-photos',false),
  ('avatars','avatars',false)
on conflict (id) do nothing;
