// Elevo — send-email Edge Function
// Powered by Resend (resend.com)
// Deploy via: Supabase Dashboard → Edge Functions → Deploy
//
// Required secret (set in Supabase Dashboard → Edge Functions → Secrets):
//   RESEND_API_KEY = <Resend API key. Rotate any key that was previously
//                     pasted into this file. Do not commit the key.>
//
// Supported email types (pass as `type` in the request body):
//   welcome              — the signed-in person, to their own address
//   tenant_invite        — landlord invites the email saved on their unit
//   rent_reminder        — service role only, to a real tenant of that unit
//   lease_expiry         — service role only, to the landlord or tenant
//   maintenance_update   — landlord of that request, to that tenant
//   screening_invite     — landlord of that screening, to that applicant
//   screening_approved   — same
//   screening_declined   — same
//   partner_notification — the applicant or an admin, to that application
//   rent_increase        — landlord of that unit, to that tenant
//   announcement         — landlord of that unit, to that tenant
//   partner_message      — a signed-in user, to that listing's email
//
// Raw subject/html is rejected. Subject and HTML are built here.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const FROM_ADDRESS   = 'hello@getelevo.app';
const FROM_NAME      = 'Elevo';
const BRAND_COLOR    = '#1F3A5F';
const GOLD           = '#C9A227';
const APP_HOME       = 'https://getelevo.app/app/#/login';
const APP_SIGNUP     = 'https://getelevo.app/app/#/signup';
const MARKETING_URL  = 'https://getelevo.app';
const SUPABASE_URL   = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON  = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SUPABASE_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  ?? Deno.env.get('SUPABASE_SERVICE_KEY')
  ?? '';

// Every server-only key this project accepts as "the scheduler".
// The runtime now injects the new sb_secret_ key as SUPABASE_SERVICE_ROLE_KEY,
// so a caller using the legacy service_role JWT (or the reverse) no longer
// matched a single-key comparison and got 401 "Sign in is required".
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

function esc(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function clean(data: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) out[key] = esc(value);
  return out;
}

function tenantSignupUrl(email: string): string {
  const params = new URLSearchParams({ role: 'tenant', email: email.trim() });
  return `${APP_SIGNUP}?${params.toString()}`;
}

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ── Shared HTML wrapper ───────────────────────────────────────────────────────

function wrap(body: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>ELEVO</title>
</head>
<body style="margin:0;padding:0;background:#F7F4EE;font-family:'Helvetica Neue',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#F7F4EE;padding:32px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0"
               style="background:#ffffff;border-radius:12px;overflow:hidden;
                      box-shadow:0 2px 12px rgba(0,0,0,0.06);">
          <!-- Header -->
          <tr>
            <td style="background:${BRAND_COLOR};padding:28px 40px;">
              <img src="https://getelevo.app/app/icons/Icon-192.png" alt="Elevo" width="48" height="48"
                   style="display:block;border:0;border-radius:8px;margin:0 0 10px;" />
              <p style="margin:0;font-size:24px;font-weight:700;
                        color:${GOLD};letter-spacing:2px;">ELEVO</p>
              <p style="margin:4px 0 0;font-size:11px;color:#8fa5c2;
                        letter-spacing:1px;">PROPERTY MANAGEMENT, ELEVATED.</p>
            </td>
          </tr>
          <!-- Body -->
          <tr>
            <td style="padding:36px 40px 28px;color:#2B2B2B;font-size:15px;line-height:1.65;">
              ${body}
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="background:#F7F4EE;padding:20px 40px;
                       border-top:1px solid #E0DBD0;">
              <p style="margin:0;font-size:12px;color:#7B8794;line-height:1.5;">
                Elevo &nbsp;·&nbsp;
                <a href="mailto:hello@getelevo.app"
                   style="color:${GOLD};text-decoration:none;">hello@getelevo.app</a>
                &nbsp;·&nbsp;
                <a href="${MARKETING_URL}" style="color:${GOLD};text-decoration:none;">getelevo.app</a>
              </p>
              <p style="margin:6px 0 0;font-size:11px;color:#aaa;">
                You received this email because of your ELEVO account activity.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function btn(label: string, url: string): string {
  return `<p style="margin:24px 0 0;">
    <a href="${url}"
       style="display:inline-block;background:${BRAND_COLOR};color:#ffffff;
              text-decoration:none;padding:13px 28px;border-radius:8px;
              font-size:14px;font-weight:600;letter-spacing:0.3px;">
      ${label}
    </a>
  </p>`;
}

function divider(): string {
  return `<hr style="border:none;border-top:1px solid #E0DBD0;margin:24px 0;" />`;
}

// ── Email template builders ───────────────────────────────────────────────────

function buildWelcome(data: Record<string, string>): { subject: string; html: string } {
  const firstName = data.firstName ?? 'there';
  return {
    subject: 'Welcome to ELEVO — Property Management, Elevated.',
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Welcome, ${firstName}. 👋
      </h2>
      <p style="margin:0 0 16px;color:#7B8794;font-size:13px;">
        Your ELEVO account is ready.
      </p>
      <p>You're on a <strong>7-day trial</strong>. A card is collected upfront when you subscribe and is charged when the trial ends unless you cancel first.
      Here's how to get started:</p>
      <ol style="padding-left:20px;margin:16px 0;">
        <li style="margin-bottom:8px;">
          <strong>Add your first property</strong> — go to Properties and tap the + button
        </li>
        <li style="margin-bottom:8px;">
          <strong>That property is on your plan</strong> — Essential includes 1 property, and each add-on adds 1 more
        </li>
        <li style="margin-bottom:8px;">
          <strong>Invite your tenants</strong> — they get their own ELEVO app to see how to pay you,
          submit maintenance requests, and message you directly
        </li>
      </ol>
      <p>Need help? Reply to this email anytime — we're here.</p>
      ${btn('Open ELEVO', APP_HOME)}
      ${divider()}
      <p style="font-size:13px;color:#7B8794;margin:0;">
        The ELEVO Team
      </p>
    `),
  };
}

function buildTenantInvite(data: Record<string, string>): { subject: string; html: string } {
  const tenantName   = data.tenantName   ?? 'there';
  const landlordName = data.landlordName ?? 'Your landlord';
  const unitLabel    = data.unitLabel    ?? 'your property';
  const firstName    = tenantName.split(' ')[0];
  return {
    subject: `You've been invited to ELEVO by ${landlordName}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Hi ${firstName},
      </h2>
      <p>
        <strong>${landlordName}</strong> has invited you to manage your tenancy at
        <strong>${unitLabel}</strong> through <strong>ELEVO</strong> — a modern property
        management platform built for Arizona renters.
      </p>
      <p>With your ELEVO tenant account you can:</p>
      <ul style="padding-left:20px;margin:12px 0;">
        <li style="margin-bottom:6px;">Track rent and mark a payment as submitted</li>
        <li style="margin-bottom:6px;">Submit and track maintenance requests</li>
        <li style="margin-bottom:6px;">Message your landlord directly</li>
        <li style="margin-bottom:6px;">Access your lease and shared documents</li>
      </ul>
      <p>Creating your tenant account takes less than two minutes.</p>
      <p>Sign up at <a href="${data.signupUrl || APP_SIGNUP}" style="color:${GOLD};text-decoration:none;font-weight:600;">getelevo.app/app</a> to get started.</p>
      ${btn('Create your tenant account', data.signupUrl || APP_SIGNUP)}
      ${divider()}
      <p style="font-size:13px;color:#7B8794;margin:0;">
        Questions? Reply to this email or contact your landlord through the app.
      </p>
    `),
  };
}

function buildRentReminder(data: Record<string, string>): { subject: string; html: string } {
  const tenantName  = data.tenantName  ?? 'Tenant';
  const firstName   = tenantName.split(' ')[0];
  const rentAmount  = data.rentAmount  ?? '';
  const dueDate     = data.dueDate     ?? 'soon';
  const unitLabel   = data.unitLabel   ?? 'your property';
  const amountLine  = rentAmount ? `<strong>\$${rentAmount}</strong>` : 'your rent';
  return {
    subject: `Rent Reminder — Payment Due ${dueDate}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Rent is due in 5 days
      </h2>
      <p>Hi ${firstName},</p>
      <p>
        This is a friendly reminder that ${amountLine} for <strong>${unitLabel}</strong>
        is due on <strong>${dueDate}</strong>.
      </p>
      <p>
        Open ELEVO to mark your payment as submitted once you've paid —
        your landlord will be notified automatically.
      </p>
      ${btn('Open ELEVO', APP_HOME)}
      ${divider()}
      <p style="font-size:13px;color:#7B8794;margin:0;">
        If you've already made arrangements with your landlord, you can disregard this reminder.
      </p>
    `),
  };
}

function buildLeaseExpiry(data: Record<string, string>): { subject: string; html: string } {
  const recipientName = data.recipientName ?? 'there';
  const firstName     = recipientName.split(' ')[0];
  const daysLeft      = data.daysLeft   ?? '';
  const leaseEndDate  = data.leaseEndDate ?? '';
  const unitLabel     = data.unitLabel  ?? 'your property';
  const isLandlord    = data.role === 'landlord';
  const urgency       = parseInt(daysLeft) <= 30 ? '⚠️ Action Required' : '📅 Heads Up';

  return {
    subject: `${urgency} — Lease Expires in ${daysLeft} Days`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Lease expiring in ${daysLeft} days
      </h2>
      <p>Hi ${firstName},</p>
      ${isLandlord
        ? `<p>The lease for <strong>${unitLabel}</strong> expires on
           <strong>${leaseEndDate}</strong> — that's <strong>${daysLeft} days away</strong>.</p>
           <p>Now is a good time to reach out to your tenant about renewal or to begin
           planning for a new tenant if they are not renewing.</p>`
        : `<p>Your lease for <strong>${unitLabel}</strong> expires on
           <strong>${leaseEndDate}</strong> — that's <strong>${daysLeft} days away</strong>.</p>
           <p>Please contact your landlord through ELEVO to discuss your renewal options.</p>`
      }
      ${btn('Open ELEVO', APP_HOME)}
      ${divider()}
      <p style="font-size:13px;color:#7B8794;margin:0;">
        Questions? Contact us at
        <a href="mailto:hello@getelevo.app"
           style="color:${GOLD};text-decoration:none;">hello@getelevo.app</a>
      </p>
    `),
  };
}

function buildMaintenanceUpdate(data: Record<string, string>): { subject: string; html: string } {
  const tenantName   = data.tenantName   ?? 'Tenant';
  const firstName    = tenantName.split(' ')[0];
  const newStatus    = data.newStatus    ?? 'Updated';
  const description  = data.description ?? 'your maintenance request';
  const unitLabel    = data.unitLabel   ?? '';
  const vendorName   = data.vendorName  ?? '';
  const landlordNote = data.landlordNote ?? '';

  const statusColor: Record<string, string> = {
    'Submitted':   '#7B8794',
    'Assigned':    GOLD,
    'In Progress': BRAND_COLOR,
    'Resolved':    '#2D9E6E',
  };
  const color = statusColor[newStatus] ?? '#7B8794';

  return {
    subject: `Maintenance Update — ${newStatus}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Maintenance Request Updated
      </h2>
      <p>Hi ${firstName},</p>
      <p>Your maintenance request has been updated.</p>

      <table width="100%" cellpadding="0" cellspacing="0"
             style="background:#F7F4EE;border-radius:8px;margin:20px 0;overflow:hidden;">
        <tr>
          <td style="padding:20px 24px;">
            <p style="margin:0 0 4px;font-size:12px;color:#7B8794;
                      text-transform:uppercase;letter-spacing:1px;">Status</p>
            <p style="margin:0 0 12px;">
              <span style="display:inline-block;background:${color}22;color:${color};
                           padding:4px 12px;border-radius:20px;font-size:13px;
                           font-weight:600;border:1px solid ${color}44;">
                ${newStatus}
              </span>
            </p>
            <p style="margin:0 0 4px;font-size:12px;color:#7B8794;
                      text-transform:uppercase;letter-spacing:1px;">Request</p>
            <p style="margin:0 0 12px;font-weight:500;">${description}</p>
            ${unitLabel ? `
            <p style="margin:0 0 4px;font-size:12px;color:#7B8794;
                      text-transform:uppercase;letter-spacing:1px;">Property</p>
            <p style="margin:0 0 12px;">${unitLabel}</p>
            ` : ''}
            ${vendorName ? `
            <p style="margin:0 0 4px;font-size:12px;color:#7B8794;
                      text-transform:uppercase;letter-spacing:1px;">Assigned Vendor</p>
            <p style="margin:0 0 12px;">${vendorName}</p>
            ` : ''}
            ${landlordNote ? `
            <p style="margin:0 0 4px;font-size:12px;color:#7B8794;
                      text-transform:uppercase;letter-spacing:1px;">Note from Landlord</p>
            <p style="margin:0;">${landlordNote}</p>
            ` : ''}
          </td>
        </tr>
      </table>

      <p>Open ELEVO to view the full details and track progress.</p>
      ${btn('View Request', APP_HOME)}
    `),
  };
}

function buildScreeningInvite(data: Record<string, string>): { subject: string; html: string } {
  const tenantName      = data.tenantName      ?? 'Applicant';
  const firstName       = tenantName.split(' ')[0];
  const landlordName    = data.landlordName    ?? 'Your prospective landlord';
  const unitLabel       = data.unitLabel       ?? 'the property';
  const rentspreeLink   = data.rentspreeLink   ?? 'https://www.rentspree.com';
  const propertyAddress = data.propertyAddress ?? '';
  const addressLine     = propertyAddress
    ? `<p style="margin:0 0 12px;"><strong>Property:</strong> ${propertyAddress}</p>`
    : '';
  return {
    subject: `You've Been Invited to Apply — ${unitLabel}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Rental Application Invitation
      </h2>
      <p>Hi ${firstName},</p>
      <p>
        You've been invited to complete a rental application for
        <strong>${unitLabel}</strong> via RentSpree.
      </p>
      ${addressLine}
      <p>
        Click the button below to begin your application. The process takes
        approximately 5–10 minutes and requires a valid government-issued ID.
      </p>
      ${btn('Begin Your Application on RentSpree', rentspreeLink)}
      ${divider()}
      <p style="font-size:13px;color:#7B8794;margin:0;">
        This invitation was sent by <strong>${landlordName}</strong> through ELEVO.
        If you did not apply for a rental property or believe this was sent in error,
        please disregard this email.
      </p>
    `),
  };
}

function buildScreeningApproved(data: Record<string, string>): { subject: string; html: string } {
  const applicantName = data.applicantName ?? 'Applicant';
  const firstName     = applicantName.split(' ')[0];
  const unitLabel     = data.unitLabel     ?? 'the property';
  const landlordName  = data.landlordName  ?? 'Your prospective landlord';
  const landlordNote  = data.landlordNote  ?? '';
  return {
    subject: `Congratulations — Your Rental Application Has Been Approved!`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Great News, ${firstName}! 🎉
      </h2>
      <p>
        Your rental application for <strong>${unitLabel}</strong> has been
        <strong style="color:#2D9E6E;">approved</strong>.
      </p>
      <p>
        <strong>${landlordName}</strong> will be in touch shortly with next steps,
        including lease signing and move-in details.
      </p>
      ${landlordNote ? `<p><strong>Message from your landlord:</strong> ${landlordNote}</p>` : ''}
      <p>
        In the meantime, you can download the ELEVO app to stay connected,
        message your landlord directly, and manage your tenancy — all in one place.
      </p>
      ${btn('Open ELEVO', APP_HOME)}
      ${divider()}
      <p style="font-size:13px;color:#7B8794;margin:0;">
        Congratulations and welcome to your new home!<br />
        The ELEVO Team
      </p>
    `),
  };
}

function buildScreeningDeclined(data: Record<string, string>): { subject: string; html: string } {
  const applicantName = data.applicantName ?? 'Applicant';
  const firstName     = applicantName.split(' ')[0];
  const unitLabel     = data.unitLabel     ?? 'the property';
  return {
    subject: `Rental Application Update — ${unitLabel}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Application Update
      </h2>
      <p>Hi ${firstName},</p>
      <p>
        Thank you for applying for <strong>${unitLabel}</strong>. After careful
        review, we are unable to move forward with your application at this time.
      </p>

      <table width="100%" cellpadding="0" cellspacing="0"
             style="background:#F7F4EE;border-radius:8px;margin:20px 0;overflow:hidden;">
        <tr>
          <td style="padding:20px 24px;">
            <p style="margin:0 0 8px;font-size:13px;font-weight:700;
                      color:${BRAND_COLOR};text-transform:uppercase;letter-spacing:1px;">
              Adverse Action Notice — Required by Federal Law (FCRA)
            </p>
            <p style="margin:0 0 10px;font-size:13px;line-height:1.6;">
              This decision was based in whole or in part on information obtained
              from a consumer reporting agency (<strong>RentSpree, Inc.</strong>,
              www.rentspree.com, (800) 432-8555).
            </p>
            <p style="margin:0 0 10px;font-size:13px;line-height:1.6;">
              Under the Fair Credit Reporting Act (FCRA), you have the right to:
            </p>
            <ul style="padding-left:20px;margin:0 0 10px;font-size:13px;line-height:1.8;">
              <li>Obtain a <strong>free copy</strong> of your consumer report from
                  RentSpree within <strong>60 days</strong> of this notice.</li>
              <li><strong>Dispute</strong> any inaccurate or incomplete information
                  in your report directly with RentSpree.</li>
              <li>Know that RentSpree did not make this decision and cannot explain
                  the specific reason for it.</li>
            </ul>
            <p style="margin:0;font-size:13px;line-height:1.6;">
              To obtain your free report or dispute information, contact RentSpree at
              <a href="https://www.rentspree.com" style="color:${GOLD};text-decoration:none;">
                www.rentspree.com</a>.
            </p>
          </td>
        </tr>
      </table>

      <p style="font-size:13px;color:#7B8794;">
        We wish you the best in your housing search.
      </p>
      ${divider()}
      <p style="font-size:13px;color:#7B8794;margin:0;">
        Elevo — acting as platform only;<br />
        this decision was made by the property owner, not ELEVO.
      </p>
    `),
  };
}

function buildPartnerNotification(data: Record<string, string>): { subject: string; html: string } {
  const applicantName = data.applicantName ?? 'Applicant';
  const firstName     = applicantName.split(' ')[0];
  const status        = data.status ?? '';       // 'received' | 'approved' | 'declined'
  const businessName  = data.businessName ?? '';
  const category      = data.category ?? '';
  const tier          = data.tier ?? '';
  const adminNote     = data.adminNote ?? '';

  if (status === 'received') {
    return {
      subject: `Application Received — ELEVO Preferred Partner Program`,
      html: wrap(`
        <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
          Application Received
        </h2>
        <p>Hi ${firstName},</p>
        <p>
          We've received your application to join the ELEVO Preferred Partner Program.
          ${businessName ? `Your business, <strong>${businessName}</strong>,` : 'Your application'}
          has been submitted for review.
        </p>
        <p>Our team typically reviews applications within 2–3 business days.
        You'll receive an email here once a decision has been made.</p>
        <p>In the meantime, if you have any questions, reply to this email.</p>
        ${divider()}
        <p style="font-size:13px;color:#7B8794;margin:0;">
          Thank you for your interest in partnering with ELEVO.
        </p>
      `),
    };
  }

  if (status === 'approved') {
    return {
      subject: `Congratulations — You're an ELEVO Preferred Partner!`,
      html: wrap(`
        <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
          Welcome to the Network 🎉
        </h2>
        <p>Hi ${firstName},</p>
        <p>
          We're pleased to inform you that your application to the ELEVO Preferred
          Partner Program has been <strong style="color:#2D9E6E;">approved</strong>.
        </p>
        ${tier ? `<p>Your listing tier: <strong>${tier}</strong></p>` : ''}
        ${category ? `<p>Category: <strong>${category}</strong></p>` : ''}
        ${adminNote ? `<p>Note from our team: ${adminNote}</p>` : ''}
        <p>
          Your business is now visible to ELEVO landlords in the Preferred Partners
          directory. Expect inquiries directly through the platform.
        </p>
        ${btn('View Your Listing on ELEVO', APP_HOME)}
      `),
    };
  }

  // declined
  return {
    subject: `ELEVO Partner Application — Update`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">
        Application Update
      </h2>
      <p>Hi ${firstName},</p>
      <p>
        Thank you for applying to the ELEVO Preferred Partner Program.
        After careful review, we are unable to approve your application at this time.
      </p>
      ${adminNote ? `<p>Feedback: ${adminNote}</p>` : ''}
      <p>
        You are welcome to reapply in the future. If you have questions,
        please reply to this email.
      </p>
      ${divider()}
      <p style="font-size:13px;color:#7B8794;margin:0;">
        Thank you for your interest in partnering with ELEVO.
      </p>
    `),
  };
}

// ── Request dispatcher ────────────────────────────────────────────────────────

function buildRentIncrease(data: Record<string, string>): { subject: string; html: string } {
  const tenantName = data.tenantName || 'there';
  const unitLabel = data.unitLabel || 'your property';
  const previousAmount = data.previousAmount || '';
  const newAmount = data.newAmount || '';
  return {
    subject: `ELEVO — Rent update for ${unitLabel}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">Rent update</h2>
      <p>Hi ${tenantName},</p>
      <p>Your rent for ${unitLabel} is changing from ${previousAmount} to ${newAmount}. The new amount applies on your next payment date.</p>
      <p>If you have a question, reply to this email or message your landlord in Elevo.</p>
    `),
  };
}

function buildAnnouncement(data: Record<string, string>): { subject: string; html: string } {
  const tenantName = data.tenantName || 'there';
  const landlordName = data.landlordName || 'Your landlord';
  const unitLabel = data.unitLabel || 'your property';
  const subject = data.subject || 'A message from your landlord';
  const message = data.message || '';
  return {
    subject: `ELEVO — ${subject}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">${subject}</h2>
      <p>Hi ${tenantName},</p>
      <p>${landlordName} sent this announcement for ${unitLabel}:</p>
      <p>${message}</p>
    `),
  };
}

function buildPartnerMessage(data: Record<string, string>): { subject: string; html: string } {
  const businessName = data.businessName || 'there';
  const senderName = data.senderName || 'An Elevo user';
  const message = data.message || '';
  return {
    subject: `ELEVO — New message for ${businessName}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">New message</h2>
      <p>Hi ${businessName},</p>
      <p>${senderName} sent you a message through Elevo:</p>
      <p>${message}</p>
    `),
  };
}

type EmailType =
  | 'welcome'
  | 'tenant_invite'
  | 'rent_reminder'
  | 'lease_expiry'
  | 'maintenance_update'
  | 'screening_invite'
  | 'screening_approved'
  | 'screening_declined'
  | 'partner_notification'
  | 'rent_increase'
  | 'rent_paid'
  | 'announcement'
  | 'partner_message';

interface EmailRequest {
  to:       string;
  type?:    EmailType;
  data?:    Record<string, string>;
  subject?: string;
  html?:    string;
}

function buildRentPaid(data: Record<string, string>): { subject: string; html: string } {
  const tenantName = data.tenantName ?? 'Your tenant';
  const amount = data.amount ?? '';
  const monthLabel = data.monthLabel ?? 'this month';
  return {
    subject: `${tenantName} says they paid ${amount}`,
    html: wrap(`
      <h2 style="margin:0 0 8px;color:${BRAND_COLOR};font-size:22px;">Rent notice</h2>
      <p><strong>${tenantName}</strong> says they paid <strong>${amount}</strong> for <strong>${monthLabel}</strong>.</p>
      <p>Open Elevo to confirm or decline. Elevo does not collect this payment.</p>
      ${btn('Review in Elevo', APP_HOME)}
    `),
  };
}

function buildEmail(
  type: EmailType,
  data: Record<string, string>,
): { subject: string; html: string } {
  const link = (data.rentspreeLink ?? '').trim();
  const safeLink = /^https:\/\/[^\s<>"']+$/i.test(link) ? link : '';
  const safe = clean({ ...data, rentspreeLink: safeLink });
  switch (type) {
    case 'welcome':              return buildWelcome(safe);
    case 'tenant_invite':        return buildTenantInvite(safe);
    case 'rent_reminder':        return buildRentReminder(safe);
    case 'lease_expiry':         return buildLeaseExpiry(safe);
    case 'maintenance_update':   return buildMaintenanceUpdate(safe);
    case 'screening_invite':     return buildScreeningInvite(safe);
    case 'screening_approved':   return buildScreeningApproved(safe);
    case 'screening_declined':   return buildScreeningDeclined(safe);
    case 'partner_notification': return buildPartnerNotification(safe);
    case 'rent_increase':        return buildRentIncrease(safe);
    case 'rent_paid':            return buildRentPaid(safe);
    case 'announcement':         return buildAnnouncement(safe);
    case 'partner_message':      return buildPartnerMessage(safe);
    default:                     throw new Error(`Unknown email type: ${type}`);
  }
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_TYPES = new Set<EmailType>([
  'welcome', 'tenant_invite', 'rent_reminder', 'lease_expiry',
  'maintenance_update', 'screening_invite', 'screening_approved',
  'screening_declined', 'partner_notification', 'rent_increase',
  'announcement', 'partner_message', 'rent_paid',
]);

function sameEmail(a: string, b: string): boolean {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

function uuidField(data: Record<string, string>, key: string): string {
  const value = (data[key] ?? '').trim();
  if (!UUID_RE.test(value)) throw new Error(`Missing or invalid ${key}`);
  return value;
}

async function restGet(path: string): Promise<Record<string, unknown>[]> {
  if (!SUPABASE_URL || !SUPABASE_SERVICE) return [];
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      apikey: SUPABASE_SERVICE,
      Authorization: `Bearer ${SUPABASE_SERVICE}`,
      Accept: 'application/json',
    },
  });
  if (!res.ok) return [];
  const body = await res.json();
  return Array.isArray(body) ? body as Record<string, unknown>[] : [];
}

async function callerFromRequest(req: Request): Promise<
  { kind: 'service' } | { kind: 'user'; id: string; email: string; role: string }
> {
  const header = req.headers.get('Authorization') ?? '';
  const token = header.replace(/^Bearer\s+/i, '').trim();
  if (!token || !SUPABASE_SERVICE || token === SUPABASE_ANON) {
    throw new Error('Sign in is required');
  }
  if (SERVICE_KEYS.has(token)) return { kind: 'service' };
  if (!SUPABASE_URL || !SUPABASE_ANON) throw new Error('Sign in is required');
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: SUPABASE_ANON },
  });
  if (!res.ok) throw new Error('Sign in is required');
  const user = await res.json() as { id?: string; email?: string };
  if (!user.id) throw new Error('Sign in is required');
  const rows = await restGet(`users?id=eq.${user.id}&select=role,email`);
  const role = String(rows[0]?.role ?? '').toLowerCase();
  const email = String(rows[0]?.email ?? user.email ?? '');
  return { kind: 'user', id: user.id, email, role };
}

async function tenantEmailForUnit(unitId: string): Promise<string> {
  const units = await restGet(`units?id=eq.${unitId}&select=tenant_id,landlord_id`);
  const tenantId = String(units[0]?.tenant_id ?? '');
  if (!UUID_RE.test(tenantId)) throw new Error('That unit has no tenant');
  const people = await restGet(`users?id=eq.${tenantId}&select=email`);
  const email = String(people[0]?.email ?? '');
  if (!email) throw new Error('That tenant has no email');
  return email;
}

async function assertRecipient(type: EmailType, data: Record<string, string>, to: string, caller: { kind: 'service' } | { kind: 'user'; id: string; email: string; role: string }): Promise<void> {
  if (caller.kind === 'service') {
    if (type !== 'rent_reminder' && type !== 'lease_expiry') {
      throw new Error('This email type is not available to the scheduler');
    }
    const unitId = uuidField(data, 'unitId');
    const units = await restGet(`units?id=eq.${unitId}&select=tenant_id,landlord_id`);
    const unit = units[0];
    if (!unit) throw new Error('Unknown unit');
    const ids = [String(unit.tenant_id ?? ''), String(unit.landlord_id ?? '')].filter((id) => UUID_RE.test(id));
    if (ids.length === 0) throw new Error('That unit has no recipient');
    const people = await restGet(`users?id=in.(${ids.join(',')})&select=email`);
    const linked = await restGet(`users?unit_id=eq.${unitId}&select=email`);
    const allowed = [...people, ...linked];
    if (!allowed.some((row) => sameEmail(String(row.email ?? ''), to))) {
      throw new Error('Recipient is not on that unit');
    }
    return;
  }

  const user = caller;
  if (type === 'rent_reminder' || type === 'lease_expiry') {
    throw new Error('Only the scheduler can send this email');
  }
  if (type === 'welcome') {
    if (!sameEmail(to, user.email)) throw new Error('You can only welcome your own address');
    return;
  }
  if (type === 'tenant_invite') {
    const unitId = uuidField(data, 'unitId');
    const units = await restGet(`units?id=eq.${unitId}&select=landlord_id,invited_email`);
    const unit = units[0];
    if (!unit || String(unit.landlord_id ?? '') !== user.id) {
      throw new Error('You can only invite a tenant to your own unit');
    }
    const invited = String(unit.invited_email ?? '');
    if (!invited || !sameEmail(invited, to)) {
      throw new Error('Save the invitation on the unit before emailing it');
    }
    return;
  }
  if (type === 'maintenance_update') {
    const requestId = uuidField(data, 'requestId');
    const rows = await restGet(`maintenance_requests?id=eq.${requestId}&select=landlord_id,tenant_id`);
    const request = rows[0];
    if (!request || String(request.landlord_id ?? '') !== user.id) {
      throw new Error('You can only update your own repair');
    }
    const tenantId = String(request.tenant_id ?? '');
    if (!UUID_RE.test(tenantId)) throw new Error('That repair has no tenant');
    const people = await restGet(`users?id=eq.${tenantId}&select=email`);
    if (!sameEmail(String(people[0]?.email ?? ''), to)) {
      throw new Error('That is not the tenant on this repair');
    }
    return;
  }
  if (type === 'screening_invite' || type === 'screening_approved' || type === 'screening_declined') {
    const screeningId = uuidField(data, 'screeningId');
    const rows = await restGet(`tenant_screenings?id=eq.${screeningId}&select=landlord_id,applicant_email`);
    const screening = rows[0];
    if (!screening || String(screening.landlord_id ?? '') !== user.id) {
      throw new Error('You can only email your own screening');
    }
    if (!sameEmail(String(screening.applicant_email ?? ''), to)) {
      throw new Error('That is not the applicant on this screening');
    }
    return;
  }
  if (type === 'partner_notification') {
    const applicationId = uuidField(data, 'applicationId');
    const rows = await restGet(`vendor_applications?id=eq.${applicationId}&select=email,created_at`);
    const application = rows[0];
    if (!application) throw new Error('Unknown application');
    const applicationEmail = String(application.email ?? '');
    const created = Date.parse(String(application.created_at ?? ''));
    const fresh = Number.isFinite(created) && Date.now() - created < 30 * 60 * 1000;
    const ownsApplication = sameEmail(user.email, applicationEmail);
    const admin = user.role === 'admin';
    const allowedHello = to.trim().toLowerCase() === 'hello@getelevo.app'
      && (data.status ?? '') === 'received'
      && (admin || fresh);
    const allowedApplicant = sameEmail(to, applicationEmail) && (admin || ownsApplication || fresh);
    if (!allowedHello && !allowedApplicant) {
      throw new Error('That recipient is not allowed for this application');
    }
    return;
  }
  if (type === 'rent_paid') {
    const unitId = uuidField(data, 'unitId');
    const units = await restGet(`units?id=eq.${unitId}&select=tenant_id,landlord_id`);
    const unit = units[0];
    if (!unit || String(unit.tenant_id ?? '') !== user.id) {
      throw new Error('You can only report a payment for your own unit');
    }
    const landlordId = String(unit.landlord_id ?? '');
    if (!UUID_RE.test(landlordId)) throw new Error('That unit has no landlord');
    const people = await restGet(`users?id=eq.${landlordId}&select=email`);
    if (!sameEmail(String(people[0]?.email ?? ''), to)) {
      throw new Error('That is not your landlord');
    }
    return;
  }
  if (type === 'rent_increase' || type === 'announcement') {
    const unitId = uuidField(data, 'unitId');
    const units = await restGet(`units?id=eq.${unitId}&select=landlord_id`);
    if (String(units[0]?.landlord_id ?? '') !== user.id) {
      throw new Error('You can only email a tenant of your own unit');
    }
    const tenantEmail = await tenantEmailForUnit(unitId);
    if (!sameEmail(tenantEmail, to)) throw new Error('That is not the tenant of this unit');
    return;
  }
  if (type === 'partner_message') {
    const listingId = uuidField(data, 'listingId');
    const rows = await restGet(`partner_listings?id=eq.${listingId}&select=email,status`);
    const listing = rows[0];
    const status = String(listing?.status ?? '').toLowerCase();
    if (!listing || (status && status !== 'active')) throw new Error('Unknown listing');
    if (!sameEmail(String(listing.email ?? ''), to)) {
      throw new Error('That is not the listing email');
    }
    return;
  }
  throw new Error('Unknown email type');
}

// ── Main handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json() as EmailRequest;
    const { to, type, data = {} } = body;

    if (!to || !type || !EMAIL_TYPES.has(type)) {
      return new Response(
        JSON.stringify({ error: 'A signed-in caller and a known email type are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...corsHeaders } },
      );
    }

    const caller = await callerFromRequest(req);
    await assertRecipient(type, data, to, caller);
    if (type === 'tenant_invite') {
      data.signupUrl = tenantSignupUrl(to);
    }

    const built = buildEmail(type, data);
    const subject = built.subject;
    const html = built.html;

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        from:    `${FROM_NAME} <${FROM_ADDRESS}>`,
        to:      [to],
        subject,
        html,
      }),
    });

    const responseData = await res.json().catch(() => ({}));

    if (!res.ok) {
      // A provider 401 is an invalid email API key, not a sign-in failure.
      console.error(`email provider rejected the message: ${res.status}`);
      return new Response(
        JSON.stringify({
          error: 'The email provider rejected the message.',
          providerStatus: res.status,
        }),
        { status: 502, headers: { 'Content-Type': 'application/json', ...corsHeaders } },
      );
    }

    return new Response(
      JSON.stringify({ success: true, id: responseData.id }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const status = message === 'Sign in is required' ? 401 : 403;
    return new Response(
      JSON.stringify({ error: message }),
      { status, headers: { 'Content-Type': 'application/json', ...corsHeaders } },
    );
  }
});
