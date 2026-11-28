-- ============================================================
-- ELEVO — property type, unit size, and additional deposit
--
-- DO NOT run this against the live project until the owner
-- reviews it. Safe to re-run. Adds columns only.
--
-- It does not drop columns, rewrite existing values, or change
-- policies. The same statements apply on the live database and
-- on a practice database, whether or not the column is already
-- there.
--
-- units.additional_deposit is also added by another change.
-- IF NOT EXISTS means either script can run first.
-- ============================================================

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS property_type text;

ALTER TABLE public.units
  ADD COLUMN IF NOT EXISTS bedrooms numeric;

ALTER TABLE public.units
  ADD COLUMN IF NOT EXISTS bathrooms numeric;

ALTER TABLE public.units
  ADD COLUMN IF NOT EXISTS additional_deposit numeric;
