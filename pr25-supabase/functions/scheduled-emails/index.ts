// Elevo — scheduled-emails Edge Function
// Runs daily via Supabase cron to fire rent reminders + lease expiry alerts.
//
// ── How to schedule this (Supabase Dashboard) ────────────────────────────────
// 1. Go to Database → Extensions → enable "pg_cron"
// 2. Go to SQL Editor and run:
//
//    select cron.schedule(
//      'elevo-daily-emails',
//      '0 9 * * *',   -- 9 AM UTC = 2 AM Arizona MST (no DST)
//      $$
//        select net.http_post(
//          url      := 'https://xehpakgyqraajutfcvrn.supabase.co/functions/v1/scheduled-emails',
//          headers  := '{"Authorization": "Bearer <YOUR_SERVICE_ROLE_KEY>",
//                        "Content-Type": "application/json"}'::jsonb,
//          body     := '{}'::jsonb
//        );
//      $$
//    );
//
// Required secrets (set in Supabase Dashboard → Edge Functions → Secrets):
//   RESEND_API_KEY        = <Resend API key. Rotate any key previously pasted here.>
//   SUPABASE_URL          = https://xehpakgyqraajutfcvrn.supabase.co
//   (SUPABASE_SERVICE_ROLE_KEY is injected by Supabase; no extra secret needed.)
//   The cron vault secret elevo_service_role_key must hold the project's
//   secret key (sb_secret_...) from Settings → API Keys.
// ─────────────────────────────────────────────────────────────────────────────

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const RESEND_API_KEY    = Deno.env.get('RESEND_API_KEY')       ?? '';
const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')         ?? '';
// Use the key the runtime injects (the new sb_secret_ key on current projects).
// SUPABASE_SERVICE_KEY is only a manual fallback; it is not set by default,
// which left this function unable to authenticate at all.
const SUPABASE_SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  ?? Deno.env.get('SUPABASE_SERVICE_KEY')
  ?? '';

// Server-only keys accepted from the cron caller (vault secret).
function serviceKeys(): Set<string> {
  const keys = new Set<string>();
  const add = (v: string | undefined | null) => { const t = (v ?? '').trim(); if (t) keys.add(t); };
  add(Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'));
  add(Deno.env.get('SUPABASE_SERVICE_KEY'));
  try {
    const all = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}') as Record<string, unknown>;
    for (const v of Object.values(all)) add(String(v ?? ''));
  } catch (_) { /* not set */ }
  return keys;
}
const SERVICE_KEYS = serviceKeys();
const FROM_ADDRESS      = 'hello@getelevo.app';
const FROM_NAME         = 'ELEVO Property Management';
const SEND_EMAIL_URL    = `${SUPABASE_URL}/functions/v1/send-email`;

// ── Supabase query helper ─────────────────────────────────────────────────────

async function query(path: string): Promise<unknown[]> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      'apikey':        SUPABASE_SERVICE,
      'Authorization': `Bearer ${SUPABASE_SERVICE}`,
      'Content-Type':  'application/json',
    },
  });
  if (!res.ok) {
    // A failed read used to look like "no rows", which hid a missing column
    // and silently skipped every rent reminder.
    console.error(`query ${path.split('?')[0]} failed: ${res.status} ${(await res.text()).slice(0, 200)}`);
    return [];
  }
  return res.json();
}

// ── Send via the send-email Edge Function ─────────────────────────────────────

async function sendEmail(
  to: string,
  type: string,
  data: Record<string, string>,
): Promise<boolean> {
  try {
    const res = await fetch(SEND_EMAIL_URL, {
      method: 'POST',
      headers: {
        'apikey':        SUPABASE_SERVICE,
        'Authorization': `Bearer ${SUPABASE_SERVICE}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({ to, type, data }),
    });
    if (!res.ok) {
      console.error(`send-email ${type} failed: ${res.status} ${(await res.text()).slice(0, 200)}`);
      return false;
    }
    return true;
  } catch (err) {
    console.error(`send-email ${type} threw: ${String(err)}`);
    return false;
  }
}

// ── Date helpers ──────────────────────────────────────────────────────────────

function daysBetween(a: Date, b: Date): number {
  return Math.round((b.getTime() - a.getTime()) / 86_400_000);
}

function formatDate(d: Date): string {
  return d.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

// ── Main handler ──────────────────────────────────────────────────────────────

function logKey(recipient: string, kind: string, period: string): string {
  const rec = encodeURIComponent(recipient.trim().toLowerCase());
  const k = encodeURIComponent(kind);
  const p = encodeURIComponent(period);
  return `email_send_log?recipient=eq.${rec}&kind=eq.${k}&period=eq.${p}`;
}

/// `sent` blocks another copy. `retry` is a recorded failure. `none` has no row.
/// A log written before the status column existed counts as sent.
async function logState(recipient: string, kind: string, period: string): Promise<'sent' | 'retry' | 'none'> {
  const base = logKey(recipient, kind, period);
  const rows = await query(`${base}&select=recipient`) as Array<Record<string, unknown>>;
  if (rows.length === 0) return 'none';
  const statusRows = await query(`${base}&select=status`) as Array<{ status?: string | null }>;
  if (statusRows.length === 0) return 'sent';
  const status = String(statusRows[0].status ?? 'sent').trim().toLowerCase();
  return status === 'failed' ? 'retry' : 'sent';
}

async function recordSend(
  recipient: string,
  kind: string,
  period: string,
  status: 'sent' | 'failed',
): Promise<void> {
  const rec = recipient.trim().toLowerCase();
  const headers = {
    apikey: SUPABASE_SERVICE,
    Authorization: `Bearer ${SUPABASE_SERVICE}`,
    'Content-Type': 'application/json',
    Prefer: 'return=representation',
  };
  const patched = await fetch(`${SUPABASE_URL}/rest/v1/${logKey(rec, kind, period)}`, {
    method: 'PATCH',
    headers,
    body: JSON.stringify({ status }),
  });
  if (patched.ok) {
    try {
      const body = await patched.json();
      if (Array.isArray(body) && body.length > 0) return;
    } catch (_) { /* insert below */ }
  }
  const inserted = await fetch(`${SUPABASE_URL}/rest/v1/email_send_log`, {
    method: 'POST',
    headers: { ...headers, Prefer: 'resolution=ignore-duplicates,return=minimal' },
    body: JSON.stringify({ recipient: rec, kind, period, status }),
  });
  if (!inserted.ok && status === 'sent') {
    await fetch(`${SUPABASE_URL}/rest/v1/email_send_log`, {
      method: 'POST',
      headers: { ...headers, Prefer: 'resolution=ignore-duplicates,return=minimal' },
      body: JSON.stringify({ recipient: rec, kind, period }),
    });
  }
}

function unitPlaceLabel(row: {
  unit_number?: string | null;
  properties?: { name?: string | null; address?: string | null } | Array<{ name?: string | null; address?: string | null }>;
}): string {
  const prop = Array.isArray(row.properties) ? row.properties[0] : row.properties;
  const address = (prop?.address ?? '').trim();
  const name = (prop?.name ?? '').trim();
  const number = (row.unit_number ?? '').trim();
  const place = address || name;
  if (place && number) return `${place} #${number}`;
  if (place) return place;
  if (number) return `Unit ${number}`;
  return 'your unit';
}

function dueDayOf(value: unknown): number {
  const n = typeof value === 'number' ? value : Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(n) || n < 1) return 1;
  return Math.min(31, Math.floor(n));
}

function nextDueDate(today: Date, rawDue: unknown): Date {
  const preferred = dueDayOf(rawDue);
  const year = today.getFullYear();
  const month = today.getMonth();
  const clamp = (y: number, m: number) => {
    const last = new Date(y, m + 1, 0).getDate();
    return Math.min(preferred, last);
  };
  const thisDue = new Date(year, month, clamp(year, month));
  thisDue.setHours(0, 0, 0, 0);
  if (thisDue.getTime() >= today.getTime()) return thisDue;
  const next = new Date(year, month + 1, 1);
  return new Date(next.getFullYear(), next.getMonth(), clamp(next.getFullYear(), next.getMonth()));
}

async function emailAllowed(userId: string, eventId: string): Promise<boolean> {
  const rows = await query(
    `notification_preferences?user_id=eq.${userId}&select=*`,
  ) as Array<Record<string, unknown>>;
  const row = rows[0];
  if (!row) return true;
  if (row.email_enabled === false) return false;
  const events = row.events;
  if (events && typeof events === 'object' && (events as Record<string, unknown>)[eventId] === false) {
    return false;
  }
  return true;
}

serve(async (req: Request) => {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!SUPABASE_SERVICE || !SERVICE_KEYS.has(token)) {
    return new Response(
      JSON.stringify({ error: 'Service role required' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let rentReminders   = 0;
  let leaseAlerts     = 0;

  try {
    // ── 1. Rent reminders — 5 days before the unit's rent due day ───────────
    // rent_due_day is the day of the month (1-31). A blank or missing day is
    // the 1st. A failed send is retried on later runs in that window. A
    // successful send is logged and is not sent again for the same due date.
    const tenantRows = await query(
      `users?role=eq.tenant&select=id,full_name,email,unit_id`,
    ) as Array<{
      id: string;
      full_name: string;
      email: string;
      unit_id: string | null;
    }>;

    // Tenants who joined through an invite are linked by units.tenant_id
    // only (users.unit_id stays empty), so fill unit_id from the units table.
    const linkedUnits = await query(
      `units?tenant_id=not.is.null&select=id,tenant_id`,
    ) as Array<{ id: string; tenant_id: string }>;
    const dueRows = await query(
      `units?select=id,rent_due_day`,
    ) as Array<{ id: string; rent_due_day: number | null }>;
    const placeRows = await query(
      `units?select=id,unit_number,properties(name,address)`,
    ) as Array<{
      id: string;
      unit_number?: string | null;
      properties?: { name?: string | null; address?: string | null } | Array<{ name?: string | null; address?: string | null }>;
    }>;
    const dueByUnit = new Map(dueRows.map((u) => [u.id, u.rent_due_day]));
    const labelByUnit = new Map(placeRows.map((u) => [u.id, unitPlaceLabel(u)]));
    const unitByTenant = new Map(linkedUnits.map((u) => [u.tenant_id, u.id]));
    for (const tenant of tenantRows) {
      tenant.unit_id = unitByTenant.get(tenant.id) ?? tenant.unit_id;
    }

    for (const tenant of tenantRows) {
      if (!tenant.email || !tenant.unit_id) continue;

      const nextDue = nextDueDate(today, dueByUnit.get(tenant.unit_id));
      const daysUntilDue = daysBetween(today, nextDue);
      // The first try is 5 days out. A failed send stays unlogged as sent,
      // so the next daily run (still on or before the due date) tries again.
      if (daysUntilDue < 0 || daysUntilDue > 5) continue;

      if (!(await emailAllowed(tenant.id, 'rent_reminder'))) continue;
      const period = `${nextDue.getFullYear()}-${String(nextDue.getMonth() + 1).padStart(2, '0')}-${String(nextDue.getDate()).padStart(2, '0')}`;
      if ((await logState(tenant.email, 'rent_reminder', period)) === 'sent') continue;

      const sent = await sendEmail(tenant.email, 'rent_reminder', {
        tenantName: tenant.full_name ?? 'Tenant',
        dueDate:    formatDate(nextDue),
        unitLabel:  labelByUnit.get(tenant.unit_id) ?? 'your unit',
        unitId:     tenant.unit_id,
      });
      await recordSend(tenant.email, 'rent_reminder', period, sent ? 'sent' : 'failed');
      if (!sent) continue;

      // email_send_log (status = sent) is the record of this reminder.
      rentReminders++;
    }

    // ── 2. Lease expiry alerts — 90, 60, and 30 days out ───────────────────
    // Expects units table to have: lease_end (ISO date string), landlord_id,
    // and a joined tenant via users where role='tenant' and unit_id matches.
    const unitRows = await query(
      `units?lease_end=not.is.null&select=id,unit_number,landlord_id,lease_end,property_id,tenant_id`,
    ) as Array<{
      id: string;
      unit_number: string;
      landlord_id: string;
      lease_end: string;
      property_id: string;
      tenant_id?: string;
    }>;

    const alertDays = [90, 60, 30];

    for (const unit of unitRows) {
      if (!unit.lease_end) continue;
      const leaseEnd   = new Date(unit.lease_end);
      const daysLeft   = daysBetween(today, leaseEnd);

      if (!alertDays.includes(daysLeft)) continue;

      const unitLabel  = `Unit ${unit.unit_number}`;
      const endStr     = formatDate(leaseEnd);
      const daysStr    = String(daysLeft);

      // Alert the landlord
      const landlordRows = await query(
        `users?id=eq.${unit.landlord_id}&select=full_name,email`,
      ) as Array<{ full_name: string; email: string }>;

      if (landlordRows.length > 0 && landlordRows[0].email) {
        const landlordAllowed = await emailAllowed(unit.landlord_id, `lease_${daysLeft}`);
        const landlordState = await logState(
          landlordRows[0].email,
          `lease_${daysLeft}`,
          unit.lease_end,
        );
        if (landlordAllowed && landlordState !== 'sent') {
          const sent = await sendEmail(landlordRows[0].email, 'lease_expiry', {
            recipientName: landlordRows[0].full_name ?? 'Landlord',
            daysLeft:      daysStr,
            leaseEndDate:  endStr,
            unitLabel,
            role:          'landlord',
            unitId:        unit.id,
          });
          await recordSend(
            landlordRows[0].email,
            `lease_${daysLeft}`,
            unit.lease_end,
            sent ? 'sent' : 'failed',
          );
          if (sent) leaseAlerts++;
        }
      }

      // Alert the tenant
      // Prefer the tenant on the unit row; fall back to users.unit_id.
      const tenantRows2 = (await query(
        `users?id=eq.${unit.tenant_id ?? '00000000-0000-0000-0000-000000000000'}&role=eq.tenant&select=id,full_name,email`,
      ) as Array<{ id: string; full_name: string; email: string }>).concat(
        await query(
          `users?unit_id=eq.${unit.id}&role=eq.tenant&select=id,full_name,email`,
        ) as Array<{ id: string; full_name: string; email: string }>,
      );

      if (tenantRows2.length > 0 && tenantRows2[0].email) {
        const tenantAllowed = await emailAllowed(tenantRows2[0].id, `lease_${daysLeft}`);
        const tenantState = await logState(
          tenantRows2[0].email,
          `lease_${daysLeft}`,
          unit.lease_end,
        );
        if (tenantAllowed && tenantState !== 'sent') {
          const sent = await sendEmail(tenantRows2[0].email, 'lease_expiry', {
            recipientName: tenantRows2[0].full_name ?? 'Tenant',
            daysLeft:      daysStr,
            leaseEndDate:  endStr,
            unitLabel,
            role:          'tenant',
            unitId:        unit.id,
          });
          await recordSend(
            tenantRows2[0].email,
            `lease_${daysLeft}`,
            unit.lease_end,
            sent ? 'sent' : 'failed',
          );
          if (sent) leaseAlerts++;
        }
      }
    }

  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  return new Response(
    JSON.stringify({ success: true, rentReminders, leaseAlerts }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
