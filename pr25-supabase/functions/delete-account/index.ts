// Elevo — delete-account Edge Function
//
// Deploy with the Supabase CLI or dashboard. This file is not applied by
// itself, and it does not call a live project when it is committed.
//
// Required secrets (provided by Supabase to every function):
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY
//
// Also apply supabase/live/07_delete_account.sql before the first call.
// The function tombstones only the user in the JWT. A user id in the body
// is ignored. It does not call deleteUser, because that would cascade into
// properties and other shared rows. It bans the login instead.
// Before any row is cleared, a live Stripe subscription is canceled
// immediately with STRIPE_SECRET_KEY. A missing key, or a Stripe error
// that is not "already canceled", stops the deletion. There is no
// proration and no refund for the current period.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  stripeErrorIsAlreadyEnded,
  subscriptionIdsToCancel,
} from './stripe_cancel.ts';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const cancelFailed =
  'Could not cancel the Stripe subscription, so the account was not deleted.';

type StripeBody = {
  id?: string;
  status?: string;
  data?: { id?: string; status?: string }[];
  has_more?: boolean;
  error?: { code?: string; message?: string };
};

async function stripeCall(
  secret: string,
  method: string,
  path: string,
  params?: Record<string, string>,
): Promise<{ ok: boolean; status: number; body: StripeBody }> {
  const form = params ? new URLSearchParams(params) : null;
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${secret}`,
      ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
    },
    body: form,
  });
  let body: StripeBody = {};
  try {
    body = await response.json();
  } catch (_) {
    body = {};
  }
  return { ok: response.ok, status: response.status, body };
}

async function listCustomerSubscriptions(
  secret: string,
  customerId: string,
): Promise<{ ok: true; subs: { id: string; status: string }[] } | { ok: false; error: string }> {
  const subs: { id: string; status: string }[] = [];
  let startingAfter = '';
  for (let page = 0; page < 10; page++) {
    const query = new URLSearchParams({
      customer: customerId,
      status: 'all',
      limit: '100',
    });
    if (startingAfter) query.set('starting_after', startingAfter);
    const result = await stripeCall(secret, 'GET', `subscriptions?${query.toString()}`);
    if (!result.ok) {
      const detail = result.body.error?.message;
      return { ok: false, error: detail ? `${cancelFailed} ${detail}` : cancelFailed };
    }
    const rows = Array.isArray(result.body.data) ? result.body.data : [];
    for (const row of rows) {
      if (row.id) subs.push({ id: row.id, status: row.status ?? '' });
    }
    if (!result.body.has_more || rows.length === 0) break;
    startingAfter = rows[rows.length - 1]?.id ?? '';
    if (!startingAfter) break;
  }
  return { ok: true, subs };
}

/// Cancels live billing. Returns an error message, or null when it is
/// safe to delete the account.
async function cancelBilling(
  secret: string,
  subscriptionId: string,
  customerId: string,
): Promise<string | null> {
  let storedStatus: string | null = null;
  if (subscriptionId) {
    const current = await stripeCall(secret, 'GET', `subscriptions/${subscriptionId}`);
    if (!current.ok) {
      if (!stripeErrorIsAlreadyEnded(current.status, current.body)) {
        return current.body.error?.message
          ? `${cancelFailed} ${current.body.error.message}`
          : cancelFailed;
      }
      storedStatus = 'canceled';
    } else {
      storedStatus = current.body.status ?? '';
    }
  }

  let customerSubscriptions: { id: string; status: string }[] = [];
  if (customerId) {
    const listed = await listCustomerSubscriptions(secret, customerId);
    if (!listed.ok) return listed.error;
    customerSubscriptions = listed.subs;
  }

  const ids = subscriptionIdsToCancel({
    storedSubscriptionId: subscriptionId || null,
    storedStatus,
    customerSubscriptions,
  });

  for (const id of ids) {
    const removed = await stripeCall(secret, 'DELETE', `subscriptions/${id}`, {
      prorate: 'false',
      invoice_now: 'false',
    });
    if (!removed.ok && !stripeErrorIsAlreadyEnded(removed.status, removed.body)) {
      return removed.body.error?.message
        ? `${cancelFailed} ${removed.body.error.message}`
        : cancelFailed;
    }
  }
  return null;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'POST only' }, 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.toLowerCase().startsWith('bearer ')) {
    return json({ error: 'Sign in required' }, 401);
  }

  // Consume the body so a posted user id cannot be used. The caller is the JWT.
  try {
    await req.text();
  } catch (_) {
    // An empty body is fine.
  }

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !anon || !service) {
    return json({ error: 'Account deletion is not configured' }, 500);
  }

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: 'Sign in required' }, 401);
  }

  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const billing = await admin
    .from('users')
    .select('stripe_subscription_id, stripe_customer_id')
    .eq('id', user.id)
    .maybeSingle();
  if (billing.error) {
    return json({ error: 'Could not look up billing, so the account was not deleted.' }, 500);
  }
  const subscriptionId = String(billing.data?.stripe_subscription_id ?? '').trim();
  const customerId = String(billing.data?.stripe_customer_id ?? '').trim();
  if (subscriptionId || customerId) {
    const secret = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
    if (!secret) {
      return json({
        error: 'Stripe is not configured, so the account was not deleted.',
      }, 500);
    }
    try {
      const cancelError = await cancelBilling(secret, subscriptionId, customerId);
      if (cancelError) return json({ error: cancelError }, 502);
    } catch (_) {
      return json({ error: cancelFailed }, 502);
    }
  }

  const listed = await admin.rpc('account_storage_to_remove', { p_user: user.id });
  if (listed.error) {
    return json({ error: 'Could not delete the account' }, 500);
  }

  const paths = new Map<string, string[]>();
  const rows = Array.isArray(listed.data) ? listed.data : [];
  for (const row of rows) {
    const bucket = String(row.bucket_id ?? '');
    const name = String(row.object_name ?? '');
    if (!bucket || !name) continue;
    const list = paths.get(bucket) ?? [];
    list.push(name);
    paths.set(bucket, list);
  }

  const purged = await admin.rpc('purge_account_data', { p_user: user.id });
  if (purged.error) {
    return json({ error: 'Could not delete the account' }, 500);
  }

  for (const [bucket, names] of paths) {
    for (let i = 0; i < names.length; i += 100) {
      const chunk = names.slice(i, i + 100);
      const removed = await admin.storage.from(bucket).remove(chunk);
      if (removed.error) {
        return json({ error: 'Could not delete the account files' }, 500);
      }
    }
  }

  // Ban the login. Do not delete the auth user: properties, units,
  // documents, and other shared rows cascade from auth.users.
  const banned = await admin.auth.admin.updateUserById(user.id, {
    ban_duration: '876000h',
    email: `deleted+${user.id}@getelevo.app`,
    email_confirm: true,
    // Supabase merges user_metadata, so each signup key must be set to null
    // or the old value stays. Nulls are dropped, leaving { deleted: true }.
    user_metadata: {
      deleted: true,
      full_name: null,
      role: null,
      phone: null,
      email_verified: null,
      company_name: null,
      service_type: null,
      service_area: null,
      license_number: null,
    },
  });
  if (banned.error) {
    return json({ error: 'Could not turn off the login' }, 500);
  }

  return json({ ok: true }, 200);
});
