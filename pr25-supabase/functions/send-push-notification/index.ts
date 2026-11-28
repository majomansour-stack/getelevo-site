// send-push-notification
// Supabase Edge Function — called by PushNotificationService.sendToUser()
//
// Environment variables required (set in Supabase Dashboard → Settings → Secrets):
//   FIREBASE_SERVICE_ACCOUNT  — full JSON string of the Firebase service account key file
//                               (the contents of elevo-aa4ed-firebase-adminsdk-fbsvc-*.json)
//
// FCM HTTP v1 API endpoint:
//   https://fcm.googleapis.com/v1/projects/elevo-aa4ed/messages:send
//
// The service account JSON must be stored as a single-line JSON string.
// Format: paste the entire contents of the service account .json file as the secret value.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Every response needs these, not only the OPTIONS preflight. Without them
// the browser blocks the reply and the web app logs a CORS error.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ── JWT generation for Google OAuth2 service account ──────────────────────────

/** Base64url encode a Uint8Array */
function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

/** Encode an object as a base64url JSON string */
function b64uJSON(obj: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}

/**
 * Generate a short-lived Google OAuth2 access token using a service account key.
 * Uses the RS256 JWT flow documented at:
 * https://developers.google.com/identity/protocols/oauth2/service-account
 */
async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64uJSON({ alg: "RS256", typ: "JWT" });
  const payload = b64uJSON({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });

  const sigInput = `${header}.${payload}`;

  // Import the private key (PKCS8 PEM → CryptoKey)
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");
  const derBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    derBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sigBytes = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      cryptoKey,
      new TextEncoder().encode(sigInput),
    ),
  );

  const jwt = `${sigInput}.${base64url(sigBytes)}`;

  // Exchange the JWT for an OAuth2 access token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`OAuth2 token exchange failed: ${err}`);
  }

  const { access_token } = await tokenRes.json();
  return access_token as string;
}

// ── Types ──────────────────────────────────────────────────────────────────────

interface ServiceAccount {
  type: string;
  project_id: string;
  private_key_id: string;
  private_key: string;
  client_email: string;
  client_id: string;
  auth_uri: string;
  token_uri: string;
}

interface RequestBody {
  user_id: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

// ── Handler ────────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const { user_id, title, body, data = {} }: RequestBody = await req.json();

    if (!user_id || !title || !body) {
      return new Response(JSON.stringify({ error: "user_id, title, and body are required" }), {
        status: 400,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    // The caller must be signed in, and must share a unit or a repair
    // job with the recipient. The service role is used only after that
    // check, to read the device token.
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return new Response(JSON.stringify({ error: "sign in required" }), {
        status: 401,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: callerData, error: callerErr } = await userClient.auth.getUser();
    if (callerErr || !callerData.user) {
      return new Response(JSON.stringify({ error: "sign in required" }), {
        status: 401,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    const { data: allowed, error: allowErr } = await userClient.rpc(
      "caller_may_push_to",
      { p_target: user_id },
    );
    if (allowErr) {
      return new Response(JSON.stringify({ error: "could not check permission" }), {
        status: 500,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    if (allowed !== true) {
      return new Response(JSON.stringify({ error: "not allowed" }), {
        status: 403,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Look up the FCM token for this user
    const { data: subRow, error: subErr } = await supabase
      .from("push_subscriptions")
      .select("fcm_token")
      .eq("user_id", user_id)
      .maybeSingle();

    if (subErr || !subRow?.fcm_token) {
      // User has no push subscription — silently succeed (non-fatal)
      return new Response(JSON.stringify({ skipped: true, reason: "no_token" }), {
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const fcmToken: string = subRow.fcm_token;

    // Parse service account JSON from environment
    const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!serviceAccountJson) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT environment variable is not set");
    }
    const serviceAccount: ServiceAccount = JSON.parse(serviceAccountJson);

    // Get a fresh OAuth2 access token
    const accessToken = await getAccessToken(serviceAccount);

    // Build the FCM HTTP v1 message payload
    const projectId = serviceAccount.project_id; // elevo-aa4ed
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const message = {
      message: {
        token: fcmToken,
        notification: { title, body },
        data: {
          // Ensure all data values are strings (FCM requirement)
          ...Object.fromEntries(
            Object.entries(data).map(([k, v]) => [k, String(v)]),
          ),
        },
        android: {
          priority: "high",
          notification: {
            channel_id: "elevo_high_importance",
            priority: "high",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      },
    };

    const fcmRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    });

    if (!fcmRes.ok) {
      const errBody = await fcmRes.text();
      // If token is invalid/unregistered, clean it up
      if (fcmRes.status === 404 || errBody.includes("UNREGISTERED")) {
        await supabase
          .from("push_subscriptions")
          .delete()
          .eq("user_id", user_id);
        return new Response(JSON.stringify({ skipped: true, reason: "token_unregistered" }), {
          headers: { ...CORS, "Content-Type": "application/json" },
        });
      }
      throw new Error(`FCM send failed (${fcmRes.status}): ${errBody}`);
    }

    const result = await fcmRes.json();
    return new Response(JSON.stringify({ success: true, fcm_name: result.name }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});
