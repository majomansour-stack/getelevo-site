-- ============================================================
-- ELEVO — fill blank live data before 01_live_security_fixes.sql.
--
-- Run this on live BEFORE 01. It is one transaction and safe to run
-- again. It only fills blanks. It does not overwrite or delete rows.
-- ============================================================

BEGIN;

-- 1:1 messages were saved with an empty receiver. Point each one at the
-- other person on that unit only when it was written during the current
-- tenancy. Older blank notes stay blank so they are not handed to the
-- person who lives there now. A message whose unit is gone is left blank.
DO $$
DECLARE
  has_since boolean;
  tenancy text;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'units'
      AND column_name = 'tenant_since'
  ) INTO has_since;

  tenancy := CASE
    WHEN has_since THEN 'COALESCE(u.tenant_since, u.lease_start::timestamptz, u.created_at)'
    ELSE 'COALESCE(u.lease_start::timestamptz, u.created_at)'
  END;

  EXECUTE format($sql$
    UPDATE public.messages m
       SET receiver_id = u.tenant_id::text
      FROM public.units u
     WHERE m.unit_id = u.id::text
       AND u.tenant_id IS NOT NULL
       AND m.created_at IS NOT NULL
       AND m.created_at >= %s
       AND (m.receiver_id IS NULL OR btrim(m.receiver_id) = '')
       AND (
         m.sender_id = u.landlord_id::text
         OR lower(btrim(m.sender_id)) = 'system'
       )
  $sql$, tenancy);

  EXECUTE format($sql$
    UPDATE public.messages m
       SET receiver_id = u.landlord_id::text
      FROM public.units u
     WHERE m.unit_id = u.id::text
       AND u.landlord_id IS NOT NULL
       AND u.tenant_id IS NOT NULL
       AND m.created_at IS NOT NULL
       AND m.created_at >= %s
       AND (m.receiver_id IS NULL OR btrim(m.receiver_id) = '')
       AND m.sender_id = u.tenant_id::text
  $sql$, tenancy);
END $$;

-- One auth account has no public.users row. Infer tenant from a unit
-- they already occupy or are invited to. Never admin.
INSERT INTO public.users (
  id, email, full_name, role, phone,
  subscription_plan, founding_member, language_preference,
  welcome_message_sent, created_at
)
SELECT
  au.id,
  COALESCE(NULLIF(btrim(au.email), ''), au.id::text),
  COALESCE(NULLIF(btrim(au.raw_user_meta_data ->> 'full_name'), ''), ''),
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM public.units un
      WHERE un.tenant_id = au.id
         OR (
           un.tenant_id IS NULL
           AND NULLIF(btrim(un.invited_email), '') IS NOT NULL
           AND lower(un.invited_email) = lower(au.email)
         )
    ) THEN 'tenant'
    ELSE 'landlord'
  END,
  COALESCE(au.raw_user_meta_data ->> 'phone', ''),
  'trial',
  false,
  'en',
  false,
  COALESCE(au.created_at, now())
FROM auth.users au
WHERE NOT EXISTS (
  SELECT 1 FROM public.users u WHERE u.id = au.id
);

-- payment_methods.landlord_id references profiles. Copy each user once.
INSERT INTO public.profiles (
  id, email, full_name, role, phone, avatar_url, referral_code,
  subscription_plan, trial_ends_at, welcome_message_sent,
  rentspree_disclosure_dismissed, created_at
)
SELECT
  u.id,
  u.email,
  COALESCE(u.full_name, ''),
  COALESCE(NULLIF(btrim(u.role), ''), 'landlord'),
  u.phone,
  u.avatar_url,
  u.referral_code,
  u.subscription_plan,
  u.trial_ends_at,
  COALESCE(u.welcome_message_sent, false),
  false,
  COALESCE(u.created_at, now())
FROM public.users u
WHERE NOT EXISTS (
  SELECT 1 FROM public.profiles p WHERE p.id = u.id
);

COMMIT;
