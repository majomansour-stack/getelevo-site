// Creates a Stripe Checkout Session for a landlord plan.
// A referred landlord gets the referral coupon on the session.
// The 7-day trial stays. This function does not run unless it is deployed
// and called. It does not create the coupon. Create that with the setup
// notes in supabase/scripts/referral_coupon.md before using it on live.
//
// Secrets:
//   STRIPE_SECRET_KEY
//   STRIPE_PRICE_ESSENTIAL_MONTHLY
//   STRIPE_PRICE_ESSENTIAL_ANNUAL
//   STRIPE_PRICE_UNLIMITED_MONTHLY
//   STRIPE_PRICE_UNLIMITED_ANNUAL
//   STRIPE_REFERRAL_COUPON_ID  (optional; default elevo_landlord_referral_20)
//
// Verify JWT stays on. The caller must be signed in.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const PRICE_KEYS: Record<string, string> = {
  "essential:monthly": "STRIPE_PRICE_ESSENTIAL_MONTHLY",
  "essential:annual": "STRIPE_PRICE_ESSENTIAL_ANNUAL",
  "unlimited:monthly": "STRIPE_PRICE_UNLIMITED_MONTHLY",
  "unlimited:annual": "STRIPE_PRICE_UNLIMITED_ANNUAL",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!stripeKey || !supabaseUrl || !anon) {
    return json({ error: "Checkout is not configured yet." }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ error: "Sign in is required." }, 401);
  }
  const userClient = createClient(supabaseUrl, anon, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Sign in is required." }, 401);

  let body: { plan?: string; annual?: boolean } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const plan = (body.plan ?? "").trim().toLowerCase();
  if (plan !== "essential" && plan !== "unlimited") {
    return json({ error: "Choose Essential or Unlimited." }, 400);
  }
  const priceEnv = PRICE_KEYS[`${plan}:${body.annual ? "annual" : "monthly"}`];
  const priceId = Deno.env.get(priceEnv) ?? "";
  if (!priceId) {
    return json({ error: "This plan is not ready for referral checkout yet." }, 500);
  }

  const admin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: referral } = await admin
    .from("referrals")
    .select("id, status")
    .eq("referred_id", userData.user.id)
    .maybeSingle();
  const coupon = Deno.env.get("STRIPE_REFERRAL_COUPON_ID") ?? "elevo_landlord_referral_20";
  const origin = req.headers.get("origin") ?? "https://getelevo.app";
  const returnUrl = origin.includes("localhost")
    ? `${origin}/#/choose-plan`
    : "https://getelevo.app/app/#/choose-plan";

  const fields = new URLSearchParams({
    mode: "subscription",
    "line_items[0][price]": priceId,
    "line_items[0][quantity]": "1",
    "subscription_data[trial_period_days]": "7",
    client_reference_id: userData.user.id,
    success_url: returnUrl,
    cancel_url: returnUrl,
    "metadata[user_id]": userData.user.id,
  });
  const email = userData.user.email?.trim() ?? "";
  if (email) fields.set("customer_email", email);
  if (referral?.id) {
    fields.set("discounts[0][coupon]", coupon);
    fields.set("metadata[referral_id]", referral.id as string);
  }

  const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${stripeKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: fields,
  });
  const payload = await response.json();
  if (!response.ok) {
    const message = typeof payload?.error?.message === "string"
      ? payload.error.message
      : "Could not open checkout.";
    return json({ error: message }, 502);
  }
  return json({ url: payload.url });
});
