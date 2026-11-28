# Landlord referral coupon

Do not run this against live until you mean to create the coupon.
The checkout function and the webhook expect this coupon id.
They do not create it.

```bash
curl https://api.stripe.com/v1/coupons \
  -u "$STRIPE_SECRET_KEY:" \
  -d id=elevo_landlord_referral_20 \
  -d percent_off=20 \
  -d duration=repeating \
  -d duration_in_months=3 \
  -d name="Landlord referral 20% for 3 months"
```

Creating it again with the same id returns the existing coupon, so the
command is safe to repeat.

Also set these Edge Function secrets before referral checkout is used:

- `STRIPE_PRICE_ESSENTIAL_MONTHLY`
- `STRIPE_PRICE_ESSENTIAL_ANNUAL`
- `STRIPE_PRICE_UNLIMITED_MONTHLY`
- `STRIPE_PRICE_UNLIMITED_ANNUAL`
- `STRIPE_REFERRAL_COUPON_ID` optional. The default is `elevo_landlord_referral_20`.

`STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` are already required.
No new webhook event is required. The existing events are enough:

- `checkout.session.completed`
- `customer.subscription.created`
- `customer.subscription.updated`

Deploy `stripe-checkout` with JWT verification left on, and redeploy
`stripe-webhook` so it can apply the referrer coupon.
