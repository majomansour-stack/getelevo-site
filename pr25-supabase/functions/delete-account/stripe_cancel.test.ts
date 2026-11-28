import assert from "node:assert/strict";
import { test } from "node:test";
import {
  stripeErrorIsAlreadyEnded,
  subscriptionIdsToCancel,
  subscriptionNeedsCancel,
} from "./stripe_cancel.ts";

test("an active or trialing subscription must be canceled", () => {
  assert.equal(subscriptionNeedsCancel("active"), true);
  assert.equal(subscriptionNeedsCancel("trialing"), true);
  assert.equal(subscriptionNeedsCancel("past_due"), true);
  assert.equal(subscriptionNeedsCancel("canceled"), false);
  assert.equal(subscriptionNeedsCancel("cancelled"), false);
  assert.equal(subscriptionNeedsCancel("incomplete_expired"), false);
});

test("a missing subscription is treated as already ended", () => {
  assert.equal(stripeErrorIsAlreadyEnded(404, null), true);
  assert.equal(
    stripeErrorIsAlreadyEnded(400, { error: { code: "resource_missing" } }),
    true,
  );
  assert.equal(
    stripeErrorIsAlreadyEnded(400, {
      error: { message: "You cannot cancel a subscription that is already canceled." },
    }),
    true,
  );
  assert.equal(
    stripeErrorIsAlreadyEnded(401, { error: { message: "Invalid API Key provided" } }),
    false,
  );
});

test("stored id and live customer subscriptions are canceled once", () => {
  const ids = subscriptionIdsToCancel({
    storedSubscriptionId: "sub_stored",
    storedStatus: "active",
    customerSubscriptions: [
      { id: "sub_stored", status: "active" },
      { id: "sub_trial", status: "trialing" },
      { id: "sub_old", status: "canceled" },
      { id: "sub_due", status: "past_due" },
    ],
  });
  assert.deepEqual(ids.sort(), ["sub_due", "sub_stored", "sub_trial"]);
});

test("an already canceled stored subscription is skipped", () => {
  assert.deepEqual(
    subscriptionIdsToCancel({
      storedSubscriptionId: "sub_done",
      storedStatus: "canceled",
      customerSubscriptions: [],
    }),
    [],
  );
});

test("a customer with only an ended subscription deletes without a new cancel", () => {
  assert.deepEqual(
    subscriptionIdsToCancel({
      storedSubscriptionId: null,
      customerSubscriptions: [{ id: "sub_old", status: "canceled" }],
    }),
    [],
  );
});
