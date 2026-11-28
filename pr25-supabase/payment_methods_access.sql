-- ============================================================
-- ELEVO — landlord payment instructions
--
-- DO NOT run this against the live project until the owner
-- reviews it. Safe to re-run.
--
-- Elevo does not move money between tenants and landlords.
-- This table only stores the instructions a landlord wants
-- their own tenants to see (Zelle, Venmo, check, bank transfer,
-- and similar). One row per landlord.
--
-- Role checks use current_user_role(), which is SECURITY DEFINER,
-- so a policy never has to read public.users itself.
-- Tenant visibility uses my_unit_landlord_ids(), also SECURITY
-- DEFINER, so it does not loop through units row-level security.
-- ============================================================

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landlord_id uuid NOT NULL,
  zelle text,
  venmo text,
  cashapp text,
  paypal text,
  bank_name text,
  bank_routing text,
  bank_account text,
  other_method text,
  other_instructions text,
  methods jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS zelle text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS venmo text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS cashapp text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS paypal text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS bank_name text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS bank_routing text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS bank_account text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS other_method text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS other_instructions text;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS methods jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_methods TO authenticated;
GRANT ALL ON public.payment_methods TO service_role;

-- If a landlord somehow has more than one row, copy any filled-in
-- instructions onto the newest row before the extra rows are removed.
-- The handles themselves are kept. Only the duplicate shell is removed.
DO $$
DECLARE
  keeper record;
  keeper_id uuid;
  keeper_landlord uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'payment_methods'
  ) THEN
    RETURN;
  END IF;

  FOR keeper IN
    SELECT id, landlord_id
    FROM (
      SELECT id, landlord_id,
             row_number() OVER (
               PARTITION BY landlord_id
               ORDER BY created_at DESC NULLS LAST, id DESC
             ) AS rn
      FROM public.payment_methods
    ) ranked
    WHERE rn = 1
  LOOP
    keeper_id := keeper.id;
    keeper_landlord := keeper.landlord_id;
    UPDATE public.payment_methods pm
    SET
      zelle = COALESCE(NULLIF(btrim(pm.zelle), ''), src.zelle),
      venmo = COALESCE(NULLIF(btrim(pm.venmo), ''), src.venmo),
      cashapp = COALESCE(NULLIF(btrim(pm.cashapp), ''), src.cashapp),
      paypal = COALESCE(NULLIF(btrim(pm.paypal), ''), src.paypal),
      bank_name = COALESCE(NULLIF(btrim(pm.bank_name), ''), src.bank_name),
      bank_routing = COALESCE(NULLIF(btrim(pm.bank_routing), ''), src.bank_routing),
      bank_account = COALESCE(NULLIF(btrim(pm.bank_account), ''), src.bank_account),
      other_method = COALESCE(NULLIF(btrim(pm.other_method), ''), src.other_method),
      other_instructions = COALESCE(NULLIF(btrim(pm.other_instructions), ''), src.other_instructions)
    FROM (
      SELECT
        (SELECT p.zelle FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.zelle), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS zelle,
        (SELECT p.venmo FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.venmo), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS venmo,
        (SELECT p.cashapp FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.cashapp), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS cashapp,
        (SELECT p.paypal FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.paypal), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS paypal,
        (SELECT p.bank_name FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.bank_name), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS bank_name,
        (SELECT p.bank_routing FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.bank_routing), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS bank_routing,
        (SELECT p.bank_account FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.bank_account), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS bank_account,
        (SELECT p.other_method FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.other_method), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS other_method,
        (SELECT p.other_instructions FROM public.payment_methods p
          WHERE p.landlord_id = keeper_landlord
            AND NULLIF(btrim(p.other_instructions), '') IS NOT NULL
          ORDER BY p.created_at DESC NULLS LAST LIMIT 1) AS other_instructions
    ) src
    WHERE pm.id = keeper_id;
  END LOOP;

  DELETE FROM public.payment_methods pm
  USING (
    SELECT id
    FROM (
      SELECT id,
             row_number() OVER (
               PARTITION BY landlord_id
               ORDER BY created_at DESC NULLS LAST, id DESC
             ) AS rn
      FROM public.payment_methods
    ) ranked
    WHERE rn > 1
  ) extra
  WHERE pm.id = extra.id;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_attribute a
      ON a.attrelid = i.indrelid
     AND a.attnum = ANY (i.indkey)
    WHERE i.indrelid = 'public.payment_methods'::regclass
      AND i.indisunique
      AND a.attname = 'landlord_id'
      AND i.indnkeyatts = 1
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX payment_methods_one_row_per_landlord ON public.payment_methods (landlord_id)';
  END IF;
END $$;

-- Landlords of the signed-in tenant, including a unit that was invited
-- by email but not claimed yet. A vendor, a stranger, and another
-- landlord's tenant are not included. The unit's landlord is used,
-- and the property landlord only when the unit has none.
CREATE OR REPLACE FUNCTION public.my_unit_landlord_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT landlord_id
  FROM (
    SELECT COALESCE(un.landlord_id, p.landlord_id) AS landlord_id
    FROM public.units un
    LEFT JOIN public.properties p ON p.id = un.property_id
    WHERE auth.uid() IS NOT NULL
      AND COALESCE(un.landlord_id, p.landlord_id) IS NOT NULL
      AND (
        un.tenant_id = auth.uid()
        OR (
          NULLIF(btrim(un.invited_email), '') IS NOT NULL
          AND NULLIF(btrim(auth.jwt() ->> 'email'), '') IS NOT NULL
          AND lower(un.invited_email) = lower(auth.jwt() ->> 'email')
        )
      )
  ) matched;
$$;

REVOKE ALL ON FUNCTION public.my_unit_landlord_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_unit_landlord_ids() TO authenticated, service_role;

-- Drop every previous name. The live project uses "manage" / "read".
-- The practice reconstruction uses "manages" / "reads own". Leaving either
-- old rule in place would sit beside the new rules and still apply.
DROP POLICY IF EXISTS "payment_methods: landlord manage own" ON public.payment_methods;
DROP POLICY IF EXISTS "payment_methods: landlord manages own" ON public.payment_methods;
DROP POLICY IF EXISTS "payment_methods: tenant read landlord" ON public.payment_methods;
DROP POLICY IF EXISTS "payment_methods: tenant reads own landlord" ON public.payment_methods;
DROP POLICY IF EXISTS "payment_methods: landlord selects own" ON public.payment_methods;
DROP POLICY IF EXISTS "payment_methods: landlord inserts own" ON public.payment_methods;
DROP POLICY IF EXISTS "payment_methods: landlord updates own" ON public.payment_methods;
DROP POLICY IF EXISTS "payment_methods: landlord deletes own" ON public.payment_methods;
DROP POLICY IF EXISTS "payment_methods: tenant reads own landlords" ON public.payment_methods;

CREATE POLICY "payment_methods: landlord selects own"
  ON public.payment_methods
  FOR SELECT
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND lower(public.current_user_role()) IN ('landlord', 'admin')
  );

CREATE POLICY "payment_methods: landlord inserts own"
  ON public.payment_methods
  FOR INSERT
  TO authenticated
  WITH CHECK (
    landlord_id = auth.uid()
    AND lower(public.current_user_role()) IN ('landlord', 'admin')
  );

CREATE POLICY "payment_methods: landlord updates own"
  ON public.payment_methods
  FOR UPDATE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND lower(public.current_user_role()) IN ('landlord', 'admin')
  )
  WITH CHECK (
    landlord_id = auth.uid()
    AND lower(public.current_user_role()) IN ('landlord', 'admin')
  );

CREATE POLICY "payment_methods: landlord deletes own"
  ON public.payment_methods
  FOR DELETE
  TO authenticated
  USING (
    landlord_id = auth.uid()
    AND lower(public.current_user_role()) IN ('landlord', 'admin')
  );

CREATE POLICY "payment_methods: tenant reads own landlords"
  ON public.payment_methods
  FOR SELECT
  TO authenticated
  USING (landlord_id IN (SELECT public.my_unit_landlord_ids()));
