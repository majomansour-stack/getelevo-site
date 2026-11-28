// Which Stripe subscriptions to cancel before an account is deleted.
// No Deno or network imports, so a Node test can run this file.

export const alreadyEndedStatuses = new Set([
  "canceled",
  "cancelled",
  "incomplete_expired",
]);

export function subscriptionNeedsCancel(status: string | null | undefined): boolean {
  const state = (status ?? "").trim().toLowerCase();
  if (!state) return true;
  return !alreadyEndedStatuses.has(state);
}

export function stripeErrorIsAlreadyEnded(
  httpStatus: number,
  body: { error?: { code?: string; message?: string } } | null,
): boolean {
  if (httpStatus === 404) return true;
  const code = (body?.error?.code ?? "").toLowerCase();
  const message = (body?.error?.message ?? "").toLowerCase();
  if (code === "resource_missing") return true;
  if (message.includes("already canceled") || message.includes("already cancelled")) {
    return true;
  }
  if (message.includes("no such subscription")) return true;
  return false;
}

/// Stored subscription id is canceled unless Stripe already ended it.
/// Customer subscriptions that are still active or trialing are included
/// even when the users row has no subscription id. Other still-billable
/// statuses on the customer (past_due, unpaid, paused, incomplete) are
/// included too, so a deleted account is not invoiced again.
export function subscriptionIdsToCancel(input: {
  storedSubscriptionId?: string | null;
  storedStatus?: string | null;
  customerSubscriptions?: { id?: string | null; status?: string | null }[];
}): string[] {
  const ids = new Set<string>();
  const stored = (input.storedSubscriptionId ?? "").trim();
  if (stored && subscriptionNeedsCancel(input.storedStatus)) {
    ids.add(stored);
  }
  for (const sub of input.customerSubscriptions ?? []) {
    const id = (sub.id ?? "").trim();
    if (!id) continue;
    if (subscriptionNeedsCancel(sub.status)) ids.add(id);
  }
  return [...ids];
}
