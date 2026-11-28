// stripe-webhook
// Stripe calls this. It does not send a Supabase JWT.
// Deploy with "Verify JWT" turned OFF (see supabase/config.toml).
//
// Secrets (Supabase Dashboard → Edge Functions → Secrets):
//   STRIPE_SECRET_KEY
//   STRIPE_WEBHOOK_SECRET
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
//
// Handled events:
//   checkout.session.completed
//   customer.subscription.created
//   customer.subscription.updated
//   customer.subscription.deleted
//   invoice.payment_failed
//
// The purchase is matched to a plan through public.stripe_plan_map
// (price id, then payment link id). See 06_subscriptions_push_email_rentspree.sql
// for the plan keys and how an admin fills that table.
// The same Stripe event id is stored once and is not applied again.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const encoder = new TextEncoder();

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function idOf(value: unknown): string | null {
  if (typeof value === "string" && value.length > 0) return value;
  if (value && typeof value === "object" && "id" in value) {
    const id = (value as { id?: unknown }).id;
    if (typeof id === "string" && id.length > 0) return id;
  }
  return null;
}

function timingSafeEqual(a: string, b: string): boolean {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  const length = Math.max(left.length, right.length);
  let diff = left.length === right.length ? 0 : 1;
  for (let i = 0; i < length; i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}

async function verifyStripeSignature(
  payload: string,
  header: string,
  secret: string,
): Promise<boolean> {
  let timestamp = "";
  const signatures: string[] = [];
  for (const piece of header.split(",")) {
    const [key, value] = piece.split("=");
    if (key === "t") timestamp = value ?? "";
    if (key === "v1" && value) signatures.push(value);
  }
  if (!timestamp || signatures.length === 0) return false;
  const ts = Number(timestamp);
  if (!Number.isFinite(ts)) return false;
  if (Math.abs(Date.now() / 1000 - ts) > 300) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${timestamp}.${payload}`),
  );
  const expected = [...new Uint8Array(mac)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return signatures.some((signature) => timingSafeEqual(signature, expected));
}

async function stripeGet(path: string, secret: string): Promise<Record<string, unknown>> {
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    headers: { Authorization: `Bearer ${secret}` },
  });
  const body = await response.json();
  if (!response.ok) {
    const message = typeof body?.error?.message === "string"
      ? body.error.message
      : `Stripe request failed (${response.status})`;
    throw new Error(message);
  }
  return body as Record<string, unknown>;
}

type PlanKey =
  | "essential"
  | "unlimited"
  | "extra_property"
  | "done_for_you"
  | "vendor_basic"
  | "vendor_featured"
  | "vendor_preferred"
  | "vendor_platinum";

type Mapped = {
  plan: string | null;
  extraQuantity: number | null;
  setup: boolean;
  unmatched: string[];
};

const BASE_PLANS = new Set([
  "essential",
  "unlimited",
  "vendor_basic",
  "vendor_featured",
  "vendor_preferred",
  "vendor_platinum",
]);

async function lookupPlan(
  admin: SupabaseClient,
  priceId: string | null,
  paymentLinkId: string | null,
): Promise<PlanKey | null> {
  if (priceId) {
    const { data } = await admin
      .from("stripe_plan_map")
      .select("plan_key")
      .eq("stripe_price_id", priceId)
      .maybeSingle();
    if (data?.plan_key) return data.plan_key as PlanKey;
  }
  if (paymentLinkId) {
    const { data } = await admin
      .from("stripe_plan_map")
      .select("plan_key")
      .eq("stripe_payment_link_id", paymentLinkId)
      .maybeSingle();
    if (data?.plan_key) return data.plan_key as PlanKey;
  }
  return null;
}

async function mapItems(
  admin: SupabaseClient,
  items: { priceId: string; quantity: number }[],
  paymentLinkId: string | null,
): Promise<Mapped> {
  let plan: string | null = null;
  let extraQuantity: number | null = null;
  let setup = false;
  const unmatched: string[] = [];

  for (const item of items) {
    const key = await lookupPlan(admin, item.priceId, null);
    if (!key) {
      unmatched.push(item.priceId);
      continue;
    }
    if (key === "extra_property") {
      extraQuantity = (extraQuantity ?? 0) + Math.max(item.quantity, 1);
    } else if (key === "done_for_you") {
      setup = true;
    } else if (BASE_PLANS.has(key)) {
      plan = key;
    }
  }

  if (plan == null && extraQuantity == null && !setup && paymentLinkId) {
    const key = await lookupPlan(admin, null, paymentLinkId);
    if (key === "extra_property") extraQuantity = 1;
    else if (key === "done_for_you") setup = true;
    else if (key && BASE_PLANS.has(key)) plan = key;
    else if (!key) unmatched.push(paymentLinkId);
  }

  return { plan, extraQuantity, setup, unmatched };
}

function itemsFromList(list: unknown): { priceId: string; quantity: number }[] {
  const data = (list as { data?: unknown[] } | undefined)?.data ?? [];
  const items: { priceId: string; quantity: number }[] = [];
  for (const raw of data) {
    const row = raw as { price?: unknown; plan?: unknown; quantity?: number };
    const priceId = idOf(row.price) ?? idOf(row.plan);
    if (!priceId) continue;
    const quantity = typeof row.quantity === "number" && row.quantity > 0
      ? row.quantity
      : 1;
    items.push({ priceId, quantity });
  }
  return items;
}

function periodEndIso(subscription: Record<string, unknown>): string | null {
  const top = subscription.current_period_end;
  const fromItem = (
    (subscription.items as { data?: { current_period_end?: number }[] } | undefined)
      ?.data?.[0]?.current_period_end
  );
  const unix = typeof top === "number" ? top : fromItem;
  if (typeof unix !== "number") return null;
  return new Date(unix * 1000).toISOString();
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

function metadataUserId(metadata: unknown): string | null {
  if (!metadata || typeof metadata !== "object") return null;
  const bag = metadata as Record<string, unknown>;
  for (const key of ["user_id", "elevo_user_id"]) {
    const value = bag[key];
    if (typeof value === "string" && isUuid(value.trim())) return value.trim();
  }
  return null;
}

function eventTimeIso(created: unknown): string | null {
  if (typeof created !== "number" || !Number.isFinite(created)) return null;
  return new Date(created * 1000).toISOString();
}

function unixToIso(value: unknown): string | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return new Date(value * 1000).toISOString();
}

async function userExists(admin: SupabaseClient, userId: string): Promise<boolean> {
  const { data } = await admin.from("users").select("id").eq("id", userId).maybeSingle();
  return Boolean(data?.id);
}

async function exactEmailUserId(admin: SupabaseClient, email: string): Promise<string | null> {
  const { data, error } = await admin.rpc("user_ids_matching_email", { p_email: email });
  if (error || !Array.isArray(data) || data.length !== 1) return null;
  const id = data[0];
  return typeof id === "string" ? id : null;
}

/// Subscription id, then customer id, then metadata, then client_reference_id,
/// then an exact case-insensitive email. A reference never moves a subscription
/// or customer that is already stored on an account.
async function resolveUserId(
  admin: SupabaseClient,
  input: {
    subscriptionId?: string | null;
    customerId?: string | null;
    metadata?: unknown;
    clientReferenceId?: string | null;
    email?: string | null;
  },
): Promise<string | null> {
  if (input.subscriptionId) {
    const { data } = await admin
      .from("users")
      .select("id")
      .eq("stripe_subscription_id", input.subscriptionId)
      .maybeSingle();
    if (data?.id) return data.id as string;
  }
  if (input.customerId) {
    const { data } = await admin
      .from("users")
      .select("id")
      .eq("stripe_customer_id", input.customerId)
      .maybeSingle();
    if (data?.id) return data.id as string;
  }
  const fromMetadata = metadataUserId(input.metadata);
  if (fromMetadata && await userExists(admin, fromMetadata)) return fromMetadata;
  const reference = input.clientReferenceId?.trim() ?? "";
  if (isUuid(reference) && await userExists(admin, reference)) return reference;
  const email = input.email?.trim() ?? "";
  if (email) return await exactEmailUserId(admin, email);
  return null;
}

async function eventIsOlder(
  admin: SupabaseClient,
  scopeKey: string,
  eventAt: string | null,
): Promise<boolean> {
  if (!scopeKey || !eventAt) return false;
  const { data } = await admin
    .from("stripe_applied_events")
    .select("last_event_at")
    .eq("scope_key", scopeKey)
    .maybeSingle();
  if (!data?.last_event_at) return false;
  return new Date(eventAt).getTime() < new Date(data.last_event_at as string).getTime();
}

async function rememberEvent(
  admin: SupabaseClient,
  scopeKey: string,
  userId: string,
  eventAt: string | null,
): Promise<void> {
  if (!scopeKey || !eventAt) return;
  await admin.from("stripe_applied_events").upsert({
    scope_key: scopeKey,
    user_id: userId,
    last_event_at: eventAt,
  }, { onConflict: "scope_key" });
}

async function applyAccount(
  admin: SupabaseClient,
  userId: string,
  patch: Record<string, unknown>,
  markSetup: boolean,
): Promise<void> {
  if (Object.keys(patch).length > 0) {
    const { error } = await admin.from("users").update(patch).eq("id", userId);
    if (error) throw new Error(error.message);
    await admin.from("profiles").update(patch).eq("id", userId);
  }
  if (markSetup) {
    const stamp = new Date().toISOString();
    await admin
      .from("users")
      .update({ setup_purchased_at: stamp })
      .eq("id", userId)
      .is("setup_purchased_at", null);
    await admin
      .from("profiles")
      .update({ setup_purchased_at: stamp })
      .eq("id", userId)
      .is("setup_purchased_at", null);
  }
}

serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const secret = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  if (!secret || !webhookSecret) {
    return json({ error: "Stripe secrets are not set" }, 500);
  }

  const payload = await req.text();
  const signature = req.headers.get("stripe-signature") ?? "";
  const valid = await verifyStripeSignature(payload, signature, webhookSecret);
  if (!valid) return json({ error: "invalid signature" }, 400);

  let event: {
    id?: string;
    type?: string;
    created?: number;
    data?: { object?: Record<string, unknown> };
  };
  try {
    event = JSON.parse(payload);
  } catch {
    return json({ error: "invalid payload" }, 400);
  }
  if (!event.id || !event.type || !event.data?.object) {
    return json({ error: "invalid event" }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { error: insertError } = await admin.from("stripe_webhook_events").insert({
    event_id: event.id,
    event_type: event.type,
  });
  if (insertError) {
    if (insertError.code === "23505") return json({ received: true, duplicate: true });
    return json({ error: insertError.message }, 500);
  }

  try {
    const object = event.data.object;
    const eventAt = eventTimeIso(event.created);
    let note = "ignored";

    if (
      event.type === "customer.subscription.created" ||
      event.type === "customer.subscription.updated"
    ) {
      note = await applySubscription(admin, object, false, eventAt, {}, secret);
    } else if (event.type === "customer.subscription.deleted") {
      note = await applySubscription(admin, object, true, eventAt, {}, secret);
    } else if (event.type === "checkout.session.completed") {
      note = await applyCheckout(admin, object, secret, eventAt);
    } else if (event.type === "invoice.payment_failed") {
      note = await applyPaymentFailed(admin, object, secret, eventAt);
    }

    await admin.from("stripe_webhook_events").update({ note }).eq("event_id", event.id);
    return json({ received: true });
  } catch (error) {
    await admin.from("stripe_webhook_events").delete().eq("event_id", event.id);
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: message }, 500);
  }
});

type Hints = {
  clientReferenceId?: string | null;
  email?: string | null;
  metadata?: unknown;
};

const REFERRAL_COUPON = () =>
  Deno.env.get("STRIPE_REFERRAL_COUPON_ID") ?? "elevo_landlord_referral_20";

function referralQualifies(status: string): boolean {
  return status === "trialing" || status === "trial" || status === "active";
}

async function stripeForm(
  path: string,
  secret: string,
  fields: Record<string, string>,
): Promise<void> {
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secret}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(fields),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    const message = typeof body?.error?.message === "string"
      ? body.error.message
      : `Stripe request failed (${response.status})`;
    throw new Error(message);
  }
}

async function addReferralCoupon(
  secret: string,
  subscriptionId: string,
): Promise<void> {
  try {
    await stripeForm(`subscriptions/${subscriptionId}`, secret, {
      "discounts[0][coupon]": REFERRAL_COUPON(),
    });
  } catch (error) {
    const message = String(error).toLowerCase();
    if (!message.includes("already")) throw error;
  }
}

/// The referred landlord's trial or active plan unlocks both discounts.
/// If the referrer has no subscription yet, the reward stays pending.
async function applyReferralRewards(
  admin: SupabaseClient,
  userId: string,
  subscriptionId: string | null,
  stripeStatus: string,
  plan: string | null,
  secret: string,
): Promise<void> {
  if (!secret || !subscriptionId) return;
  if (plan !== "essential" && plan !== "unlimited") return;
  if (!referralQualifies(stripeStatus)) return;

  const { data: asReferred } = await admin
    .from("referrals")
    .select("id, referrer_id, referred_coupon_applied, referrer_coupon_applied")
    .eq("referred_id", userId)
    .maybeSingle();
  if (asReferred && !asReferred.referred_coupon_applied) {
    await addReferralCoupon(secret, subscriptionId);
    await admin.from("referrals").update({
      referred_coupon_applied: true,
    }).eq("id", asReferred.id);
  }
  if (asReferred && !asReferred.referrer_coupon_applied) {
    const { data: referrer } = await admin
      .from("users")
      .select("stripe_subscription_id")
      .eq("id", asReferred.referrer_id)
      .maybeSingle();
    const referrerSub = typeof referrer?.stripe_subscription_id === "string"
      ? referrer.stripe_subscription_id
      : "";
    if (referrerSub) {
      await addReferralCoupon(secret, referrerSub);
      await admin.from("referrals").update({
        referrer_coupon_applied: true,
        status: "rewarded",
      }).eq("id", asReferred.id);
    } else {
      await admin.from("referrals").update({
        status: "reward_pending",
      }).eq("id", asReferred.id);
    }
  }

  const { data: waiting } = await admin
    .from("referrals")
    .select("id")
    .eq("referrer_id", userId)
    .eq("referrer_coupon_applied", false)
    .eq("status", "reward_pending");
  for (const row of waiting ?? []) {
    await addReferralCoupon(secret, subscriptionId);
    await admin.from("referrals").update({
      referrer_coupon_applied: true,
      status: "rewarded",
    }).eq("id", (row as { id: string }).id);
  }
}

async function applySubscription(
  admin: SupabaseClient,
  subscription: Record<string, unknown>,
  deleted: boolean,
  eventAt: string | null,
  hints: Hints = {},
  secret = "",
): Promise<string> {
  const customerId = idOf(subscription.customer);
  const subscriptionId = idOf(subscription.id);
  if (subscriptionId && await eventIsOlder(admin, subscriptionId, eventAt)) {
    return "skipped older event";
  }
  const mapped = await mapItems(admin, itemsFromList(subscription.items), null);
  const userId = await resolveUserId(admin, {
    subscriptionId,
    customerId,
    metadata: hints.metadata ?? subscription.metadata,
    clientReferenceId: hints.clientReferenceId,
    email: hints.email,
  });
  if (!userId) return mapped.unmatched.length ? `unmatched user; prices ${mapped.unmatched.join(",")}` : "unmatched user";

  if (deleted) {
    const patch: Record<string, unknown> = {};
    if (mapped.plan) patch.subscription_status = "canceled";
    if (mapped.extraQuantity != null) patch.extra_property_count = 0;
    if (!mapped.plan && mapped.extraQuantity == null) patch.subscription_status = "canceled";
    await applyAccount(admin, userId, patch, false);
    if (subscriptionId) await rememberEvent(admin, subscriptionId, userId, eventAt);
    return "subscription deleted";
  }

  const patch: Record<string, unknown> = {};
  if (customerId) patch.stripe_customer_id = customerId;
  const stripeStatus = typeof subscription.status === "string" ? subscription.status : "active";
  if (mapped.plan) {
    patch.subscription_plan = mapped.plan;
    if (stripeStatus === "trialing") {
      patch.subscription_status = "trial";
      const trialEnd = unixToIso(subscription.trial_end);
      if (trialEnd) patch.trial_ends_at = trialEnd;
    } else {
      patch.subscription_status = stripeStatus;
    }
    if (subscriptionId) patch.stripe_subscription_id = subscriptionId;
    const periodEnd = periodEndIso(subscription);
    if (periodEnd) patch.current_period_end = periodEnd;
  }
  if (mapped.extraQuantity != null) patch.extra_property_count = mapped.extraQuantity;
  await applyAccount(admin, userId, patch, mapped.setup);
  if (subscriptionId) await rememberEvent(admin, subscriptionId, userId, eventAt);
  await applyReferralRewards(
    admin,
    userId,
    subscriptionId,
    stripeStatus,
    mapped.plan,
    secret,
  );
  if (mapped.unmatched.length > 0) return `applied; unmapped ${mapped.unmatched.join(",")}`;
  if (!mapped.plan && mapped.extraQuantity == null && !mapped.setup) return "no mapped price";
  return "applied";
}

async function applyCheckout(
  admin: SupabaseClient,
  session: Record<string, unknown>,
  secret: string,
  eventAt: string | null,
): Promise<string> {
  const sessionId = typeof session.id === "string" ? session.id : "";
  const full = sessionId
    ? await stripeGet(
      `checkout/sessions/${sessionId}?${new URLSearchParams({ "expand[]": "line_items" })}`,
      secret,
    )
    : session;
  const mode = typeof full.mode === "string" ? full.mode : "";
  const subscriptionId = idOf(full.subscription);
  if (mode === "subscription" && subscriptionId) {
    const subscription = await stripeGet(`subscriptions/${subscriptionId}`, secret);
    const customerId = idOf(full.customer) ?? idOf(subscription.customer);
    const email = (typeof full.customer_email === "string" && full.customer_email)
      || (typeof (full.customer_details as { email?: string } | undefined)?.email === "string"
        ? (full.customer_details as { email?: string }).email
        : null);
    const reference = typeof full.client_reference_id === "string" ? full.client_reference_id : null;
    return await applySubscription(admin, subscription, false, eventAt, {
      clientReferenceId: reference,
      email: email ?? null,
      metadata: full.metadata ?? subscription.metadata,
    }, secret);
  }

  const mapped = await mapItems(
    admin,
    itemsFromList(full.line_items),
    idOf(full.payment_link),
  );
  const email = (typeof full.customer_email === "string" && full.customer_email)
    || (typeof (full.customer_details as { email?: string } | undefined)?.email === "string"
      ? (full.customer_details as { email?: string }).email
      : null);
  const scopeKey = sessionId ? `checkout:${sessionId}` : "";
  if (scopeKey && await eventIsOlder(admin, scopeKey, eventAt)) return "skipped older event";
  const userId = await resolveUserId(admin, {
    customerId: idOf(full.customer),
    metadata: full.metadata,
    clientReferenceId: typeof full.client_reference_id === "string" ? full.client_reference_id : null,
    email: email ?? null,
  });
  if (!userId) return "unmatched user";
  const patch: Record<string, unknown> = {};
  const customerId = idOf(full.customer);
  if (customerId) patch.stripe_customer_id = customerId;
  if (mapped.plan) {
    patch.subscription_plan = mapped.plan;
    patch.subscription_status = "active";
  }
  if (mapped.extraQuantity != null) patch.extra_property_count = mapped.extraQuantity;
  await applyAccount(admin, userId, patch, mapped.setup);
  if (scopeKey) await rememberEvent(admin, scopeKey, userId, eventAt);
  if (mapped.unmatched.length > 0) return `applied; unmapped ${mapped.unmatched.join(",")}`;
  return "applied";
}

async function applyPaymentFailed(
  admin: SupabaseClient,
  invoice: Record<string, unknown>,
  secret: string,
  eventAt: string | null,
): Promise<string> {
  const customerId = idOf(invoice.customer);
  const subscriptionId = idOf(invoice.subscription);
  const scopeKey = subscriptionId || (customerId ? `customer:${customerId}` : "");
  if (scopeKey && await eventIsOlder(admin, scopeKey, eventAt)) return "skipped older event";
  const email = typeof invoice.customer_email === "string" ? invoice.customer_email : null;
  const userId = await resolveUserId(admin, {
    subscriptionId,
    customerId,
    metadata: invoice.metadata,
    email,
  });
  if (!userId) return "unmatched user";

  const { data: account } = await admin
    .from("users")
    .select("subscription_status, stripe_subscription_id")
    .eq("id", userId)
    .maybeSingle();
  const status = typeof account?.subscription_status === "string"
    ? account.subscription_status
    : "";
  const mainId = typeof account?.stripe_subscription_id === "string"
    ? account.stripe_subscription_id
    : "";
  const mainStillActive = status === "active" || status === "trial" || status === "trialing";
  const targetsMain = !subscriptionId || !mainId || subscriptionId === mainId;
  let addonOnly = false;
  if (subscriptionId && subscriptionId !== mainId) {
    try {
      const subscription = await stripeGet(`subscriptions/${subscriptionId}`, secret);
      const mapped = await mapItems(admin, itemsFromList(subscription.items), null);
      addonOnly = mapped.extraQuantity != null && mapped.plan == null;
    } catch {
      addonOnly = true;
    }
  }
  if (mainStillActive && !targetsMain && addonOnly) {
    if (scopeKey) await rememberEvent(admin, scopeKey, userId, eventAt);
    return "addon invoice failed; main subscription left active";
  }

  const patch: Record<string, unknown> = { subscription_status: "past_due" };
  if (customerId) patch.stripe_customer_id = customerId;
  await applyAccount(admin, userId, patch, false);
  if (scopeKey) await rememberEvent(admin, scopeKey, userId, eventAt);
  return "marked past_due";
}
