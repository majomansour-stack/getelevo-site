// stripe-billing-portal
// Opens the Stripe Customer Portal for the signed-in person.
// The app calls this from Manage Subscription. Stripe hosts the page.
//
// Secrets:
//   STRIPE_SECRET_KEY
// Optional:
//   STRIPE_PORTAL_RETURN_URL   (defaults to https://getelevo.app)
//
// The customer id is the one the webhook stored. A person with no
// Stripe payment yet gets a clear message instead of a portal link.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ error: "Sign in required." }, 401);
  }

  const secret = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  if (!secret) return json({ error: "Stripe is not configured yet." }, 500);

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Sign in required." }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: row, error: rowError } = await admin
    .from("users")
    .select("stripe_customer_id")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (rowError) return json({ error: "Could not look up the account." }, 500);

  const customerId = row?.stripe_customer_id as string | null | undefined;
  if (!customerId) {
    return json({
      error: "No Stripe billing account yet. Choose a plan first, then you can manage it here.",
    }, 409);
  }

  const returnUrl = Deno.env.get("STRIPE_PORTAL_RETURN_URL") ?? "https://getelevo.app";
  const response = await fetch("https://api.stripe.com/v1/billing_portal/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secret}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      customer: customerId,
      return_url: returnUrl,
    }),
  });
  const body = await response.json();
  if (!response.ok || typeof body?.url !== "string") {
    const message = typeof body?.error?.message === "string"
      ? body.error.message
      : "Stripe could not open the billing page.";
    return json({ error: message }, 502);
  }
  return json({ url: body.url });
});
