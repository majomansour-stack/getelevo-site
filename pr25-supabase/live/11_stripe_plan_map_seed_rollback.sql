-- Rolls back 11_stripe_plan_map_seed.sql. Not applied by the app.
-- Deletes the 10 price ids that script inserts:
-- two essential, two unlimited, extra_property, done_for_you,
-- and the four vendor tiers. Other plan-map rows are left in place.

DELETE FROM public.stripe_plan_map
WHERE stripe_price_id IN (
  'price_1Tf5LH25TBc7I7F2fBLucJX4',
  'price_1Uey5p25TBc7I7F2G6FY9tUz',
  'price_1Uey5q25TBc7I7F2Vopoy6gf',
  'price_1Uey5u25TBc7I7F22xYVicXu',
  'price_1Tf5T325TBc7I7F2n9mltMMS',
  'price_1Tf5S925TBc7I7F2zabs1UQW',
  'price_1Tf5Ts25TBc7I7F2REQWNETz',
  'price_1Tf5UY25TBc7I7F2goE4lBdw',
  'price_1Tf5VK25TBc7I7F27dkxYMGr',
  'price_1Tf5W025TBc7I7F2BXKY0zwT'
);
