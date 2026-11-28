-- ============================================================
-- ELEVO — seed public.stripe_plan_map with all 10 live price ids.
--
-- Not applied by the app. Run in the Supabase SQL editor after the
-- already-applied 08_trial7_property_caps.sql (which follows 06 and 07).
-- Safe to run again. Skips a row when that price id or payment-link
-- id is already stored.
--
-- plan_key values match the webhook: essential, unlimited,
-- extra_property, done_for_you, vendor_basic, vendor_featured,
-- vendor_preferred, vendor_platinum.
-- ============================================================

INSERT INTO public.stripe_plan_map (stripe_price_id, stripe_payment_link_id, plan_key)
SELECT v.stripe_price_id, v.stripe_payment_link_id, v.plan_key
FROM (
  VALUES
    (
      'price_1Tf5LH25TBc7I7F2fBLucJX4',
      'plink_1Tg7Qw25TBc7I7F2JaZ2WuKb',
      'essential'
    ),
    (
      'price_1Uey5p25TBc7I7F2G6FY9tUz',
      'plink_1Uey6R25TBc7I7F2rM9jZAXj',
      'essential'
    ),
    (
      'price_1Uey5q25TBc7I7F2Vopoy6gf',
      'plink_1Uey6V25TBc7I7F2fwOek4ss',
      'unlimited'
    ),
    (
      'price_1Uey5u25TBc7I7F22xYVicXu',
      'plink_1Uey6V25TBc7I7F2gF83qlOs',
      'unlimited'
    ),
    (
      'price_1Tf5T325TBc7I7F2n9mltMMS',
      'plink_1Tg7Pc25TBc7I7F268oChyap',
      'extra_property'
    ),
    (
      'price_1Tf5S925TBc7I7F2zabs1UQW',
      'plink_1Tg7Q025TBc7I7F2L9YQ6qux',
      'done_for_you'
    ),
    (
      'price_1Tf5Ts25TBc7I7F2REQWNETz',
      'plink_1Tg7P725TBc7I7F2oaYAVl4k',
      'vendor_basic'
    ),
    (
      'price_1Tf5UY25TBc7I7F2goE4lBdw',
      'plink_1Tg7Oi25TBc7I7F2OLAq1pTZ',
      'vendor_featured'
    ),
    (
      'price_1Tf5VK25TBc7I7F27dkxYMGr',
      'plink_1Tg7O525TBc7I7F2wUiamQnQ',
      'vendor_preferred'
    ),
    (
      'price_1Tf5W025TBc7I7F2BXKY0zwT',
      'plink_1Tg7NZ25TBc7I7F2XUQsfbE5',
      'vendor_platinum'
    )
) AS v(stripe_price_id, stripe_payment_link_id, plan_key)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.stripe_plan_map m
  WHERE m.stripe_price_id = v.stripe_price_id
     OR m.stripe_payment_link_id = v.stripe_payment_link_id
);
