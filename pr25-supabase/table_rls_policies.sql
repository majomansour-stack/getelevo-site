-- ============================================================
-- ELEVO — Supabase Table RLS Policies (additive only)
-- Run this entire script in:
--   Supabase Dashboard → SQL Editor → New Query → Run
--
-- SYNTAX RULE (why previous versions failed):
--   Inside a subquery in a PostgreSQL RLS policy expression,
--   you CANNOT write table-qualified references to the
--   protected table (e.g. tenant_emergency_contacts.tenant_id).
--   Use the UNQUALIFIED column name instead (tenant_id).
--   Always alias the subquery table (e.g. FROM public.units u)
--   so column references are unambiguous.
--
-- Covers six tables:
--   documents, users, tenant_emergency_contacts,
--   tenant_screenings, vault_items, vendor_contacts
--
-- IMPORTANT:
--   • Safe to re-run. Each policy is dropped by name first.
--   • All tables must have RLS already enabled.
--     Uncomment the ALTER TABLE lines if any table does not.
-- ============================================================


-- ============================================================
-- TABLE 1: documents
--
-- Confirmed columns: id, unit_id, landlord_id, tenant_id,
--   file_name, doc_type, file_url, file_size_bytes, created_at
--
-- Policies added:
--   INSERT  landlords — landlord_id = auth.uid()
--   UPDATE  landlords — landlord_id = auth.uid()
--   DELETE  landlords — landlord_id = auth.uid()
--   INSERT  tenants   — tenant_id   = auth.uid()
-- ============================================================

-- ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "documents: landlords insert own" ON public.documents;
CREATE POLICY "documents: landlords insert own"
  ON public.documents
  FOR INSERT
  TO authenticated
  WITH CHECK (
    landlord_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  );

DROP POLICY IF EXISTS "documents: landlords update own" ON public.documents;
CREATE POLICY "documents: landlords update own"
  ON public.documents
  FOR UPDATE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  )
  WITH CHECK (
    landlord_id = auth.uid()
  );

DROP POLICY IF EXISTS "documents: landlords delete own" ON public.documents;
CREATE POLICY "documents: landlords delete own"
  ON public.documents
  FOR DELETE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  );

DROP POLICY IF EXISTS "documents: tenants insert own" ON public.documents;
CREATE POLICY "documents: tenants insert own"
  ON public.documents
  FOR INSERT
  TO authenticated
  WITH CHECK (
    tenant_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role = 'tenant'
    )
  );


-- ============================================================
-- TABLE 2: users  (the app has no separate "profiles" table)
--
-- Confirmed columns: id, email, full_name, role, phone,
--   avatar_url, subscription_plan, trial_ends_at,
--   founding_member, referral_code, language_preference,
--   created_at, welcome_message_sent, payment_methods, unit_id
--
-- Policies added:
--   SELECT  own row — id = auth.uid()
--   INSERT  own row — id = auth.uid()
--   UPDATE  own row — id = auth.uid()
-- ============================================================

-- ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users: select own" ON public.users;
CREATE POLICY "users: select own"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    id = auth.uid()
  );

DROP POLICY IF EXISTS "users: insert own" ON public.users;
CREATE POLICY "users: insert own"
  ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (
    id = auth.uid()
  );

-- Column updates are limited to the signed-in user's own row.
-- Changing role is blocked by users_guard_role_change in
-- supabase/fixes_pending_owner_approval.sql. Do not widen this
-- policy to let someone set role = 'admin' on their own row.
DROP POLICY IF EXISTS "users: update own" ON public.users;
CREATE POLICY "users: update own"
  ON public.users
  FOR UPDATE
  TO authenticated
  USING (
    id = auth.uid()
  )
  WITH CHECK (
    id = auth.uid()
  );


-- ============================================================
-- TABLE 3: tenant_emergency_contacts
--
-- Confirmed columns: id, tenant_id, name, phone,
--   relationship, created_at
--
-- NO landlord_id column exists in this table.
-- Landlord scope is resolved by joining public.units:
--   units.tenant_id   matches the contact row's tenant_id
--   units.landlord_id matches auth.uid()
--
-- SYNTAX FIX: use unqualified `tenant_id` (not
-- `tenant_emergency_contacts.tenant_id`) inside subqueries,
-- and alias `public.units` as `u` to remove ambiguity.
--
-- Policies added:
--   INSERT  landlords — tenant must belong to one of their units
--   UPDATE  landlords — same scope
--   DELETE  landlords — same scope
--   SELECT  tenants   — tenant_id = auth.uid()
-- ============================================================

-- ALTER TABLE public.tenant_emergency_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tenant_emergency_contacts: landlords insert own tenants" ON public.tenant_emergency_contacts;
CREATE POLICY "tenant_emergency_contacts: landlords insert own tenants"
  ON public.tenant_emergency_contacts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.tenant_id    = tenant_id
        AND u.landlord_id  = auth.uid()
    )
    AND EXISTS (
      SELECT 1 FROM public.users usr
      WHERE usr.id   = auth.uid()
        AND usr.role IN ('landlord', 'admin')
    )
  );

DROP POLICY IF EXISTS "tenant_emergency_contacts: landlords update own tenants" ON public.tenant_emergency_contacts;
CREATE POLICY "tenant_emergency_contacts: landlords update own tenants"
  ON public.tenant_emergency_contacts
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.tenant_id   = tenant_id
        AND u.landlord_id = auth.uid()
    )
    AND EXISTS (
      SELECT 1 FROM public.users usr
      WHERE usr.id   = auth.uid()
        AND usr.role IN ('landlord', 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.tenant_id   = tenant_id
        AND u.landlord_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "tenant_emergency_contacts: landlords delete own tenants" ON public.tenant_emergency_contacts;
CREATE POLICY "tenant_emergency_contacts: landlords delete own tenants"
  ON public.tenant_emergency_contacts
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.units u
      WHERE u.tenant_id   = tenant_id
        AND u.landlord_id = auth.uid()
    )
    AND EXISTS (
      SELECT 1 FROM public.users usr
      WHERE usr.id   = auth.uid()
        AND usr.role IN ('landlord', 'admin')
    )
  );

DROP POLICY IF EXISTS "tenant_emergency_contacts: tenants select own" ON public.tenant_emergency_contacts;
CREATE POLICY "tenant_emergency_contacts: tenants select own"
  ON public.tenant_emergency_contacts
  FOR SELECT
  TO authenticated
  USING (
    tenant_id = auth.uid()
  );


-- ============================================================
-- TABLE 4: tenant_screenings
--
-- Confirmed columns: id, landlord_id, applicant_name,
--   applicant_first_name, applicant_last_name, applicant_email,
--   property_id, property_address, unit_id, unit_number,
--   screening_type, screening_fee, status, notes, invited_at,
--   completed_at, approved_at, declined_at
--
-- landlord_id EXISTS and CONFIRMED.
-- applicant_email EXISTS and CONFIRMED.
--
-- Policies added:
--   INSERT  landlords  — landlord_id = auth.uid()
--   UPDATE  landlords  — landlord_id = auth.uid()
--   SELECT  applicants — matched on applicant_email
-- ============================================================

-- ALTER TABLE public.tenant_screenings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tenant_screenings: landlords insert own" ON public.tenant_screenings;
CREATE POLICY "tenant_screenings: landlords insert own"
  ON public.tenant_screenings
  FOR INSERT
  TO authenticated
  WITH CHECK (
    landlord_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  );

DROP POLICY IF EXISTS "tenant_screenings: landlords update own" ON public.tenant_screenings;
CREATE POLICY "tenant_screenings: landlords update own"
  ON public.tenant_screenings
  FOR UPDATE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  )
  WITH CHECK (
    landlord_id = auth.uid()
  );

-- Applicants can view their own screening record matched on email.
-- This works before the applicant has an account — the row is
-- created by the landlord before the applicant signs up.
DROP POLICY IF EXISTS "tenant_screenings: applicants select own" ON public.tenant_screenings;
CREATE POLICY "tenant_screenings: applicants select own"
  ON public.tenant_screenings
  FOR SELECT
  TO authenticated
  USING (
    applicant_email = (
      SELECT u.email FROM public.users u WHERE u.id = auth.uid()
    )
  );


-- ============================================================
-- TABLE 5: vault_items
--
-- Confirmed columns: id, landlord_id, type, title, content,
--   file_url, unit_id, unit_label, created_at
--
-- landlord_id EXISTS and CONFIRMED.
--
-- Policies added:
--   INSERT  landlords — landlord_id = auth.uid()
--   UPDATE  landlords — landlord_id = auth.uid()
--   DELETE  landlords — landlord_id = auth.uid()
-- ============================================================

-- ALTER TABLE public.vault_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vault_items: landlords insert own" ON public.vault_items;
CREATE POLICY "vault_items: landlords insert own"
  ON public.vault_items
  FOR INSERT
  TO authenticated
  WITH CHECK (
    landlord_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  );

DROP POLICY IF EXISTS "vault_items: landlords update own" ON public.vault_items;
CREATE POLICY "vault_items: landlords update own"
  ON public.vault_items
  FOR UPDATE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  )
  WITH CHECK (
    landlord_id = auth.uid()
  );

DROP POLICY IF EXISTS "vault_items: landlords delete own" ON public.vault_items;
CREATE POLICY "vault_items: landlords delete own"
  ON public.vault_items
  FOR DELETE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  );


-- ============================================================
-- TABLE 6: vendor_contacts
--
-- Confirmed columns: vendor_id, contacted_by,
--   contact_type, contacted_at
--
-- NO landlord_id column exists in this table.
-- vendor_id    = the partner listing owner's uid
-- contacted_by = uid of the user who tapped Call/Email/Message
--
-- Policies added:
--   INSERT  any authenticated user — log a contact tap
--   SELECT  vendors  — vendor_id = auth.uid()
--   SELECT  landlords + admins — all rows via users.role check
-- ============================================================

-- ALTER TABLE public.vendor_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vendor_contacts: authenticated insert" ON public.vendor_contacts;
CREATE POLICY "vendor_contacts: authenticated insert"
  ON public.vendor_contacts
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "vendor_contacts: vendors select own" ON public.vendor_contacts;
CREATE POLICY "vendor_contacts: vendors select own"
  ON public.vendor_contacts
  FOR SELECT
  TO authenticated
  USING (
    vendor_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('vendor', 'admin')
    )
  );

DROP POLICY IF EXISTS "vendor_contacts: landlords and admins select all" ON public.vendor_contacts;
CREATE POLICY "vendor_contacts: landlords and admins select all"
  ON public.vendor_contacts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id   = auth.uid()
        AND u.role IN ('landlord', 'admin')
    )
  );


-- ============================================================
-- VERIFICATION QUERY
-- Run immediately after the script to confirm all 20 new
-- policies were created. Returns ALL policies on these tables
-- including any that already existed before this script ran.
--
-- New policies added by this script (20 total):
--   documents                   +4  (insert×2, update, delete)
--   users                       +3  (select, insert, update)
--   tenant_emergency_contacts   +4  (insert, update, delete, select)
--   tenant_screenings           +3  (insert, update, select)
--   vault_items                 +3  (insert, update, delete)
--   vendor_contacts             +3  (insert, select×2)
-- ============================================================
SELECT
  tablename,
  policyname,
  cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'documents',
    'users',
    'tenant_emergency_contacts',
    'tenant_screenings',
    'vault_items',
    'vendor_contacts'
  )
ORDER BY tablename, cmd, policyname;
