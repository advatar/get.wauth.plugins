---
name: wauth-stripe
description: Perform Stripe actions safely through the WAUTH Stripe doorkeeper — propose a plan, let WAUTH classify the risk tier, route risky actions to a human passkey/liveness approval, then execute with a credential the agent never holds. Use whenever the user wants to refund, pay out, charge, manage subscriptions/customers/products/prices/coupons, or read Stripe data via WAUTH.
---

# WAUTH Stripe doorkeeper — agent guide

You act through a **doorkeeper**: a separate trust domain that holds the real Stripe secret key.
You (the agent) **never see or handle that key**. You hold only a least-privilege **agent key**,
supplied to you as the `wauth-stripe` MCP server's bearer token. Your job is to *propose* actions;
WAUTH classifies their risk, and for risky ones a **human approves with a passkey** (plus a live
face scan for the riskiest). The doorkeeper performs the action and returns a signed receipt.

## The one rule
Never ask the user for, accept, or store a Stripe `sk_…` key, and never call the Stripe API
directly. Everything goes through the `wauth-stripe` MCP tools. If a task seems to need the raw
key, stop — the doorkeeper is the only thing that should ever hold it.

## Risk tiers (you don't decide these — `plan_action` does)
- **T0 — observe (no approval):** read balance, list/retrieve charges, subscription status, payout schedule, retrieve a customer/invoice.
- **T1 — acknowledge:** create a draft invoice, add/update metadata, create a customer or product. A lightweight acknowledgement.
- **T2 — passkey:** refund under threshold, create/cancel a subscription, update a price, issue a coupon. A human approves with a **passkey** (WebAuthn).
- **T3 — passkey + live face scan:** money to a **new** destination (payout / new bank account), bulk refunds, change payout bank details, create LIVE API keys, edit webhook endpoints, PII/card export. A human approves with a **passkey AND an iProov liveness capture**.

Thresholds, "new destination" detection, and bulk size can **escalate** a tier. Always trust the
`tier` that `plan_action` returns; never infer it yourself.

## The ceremony (which tools, in order)
1. **`plan_action`** — describe the action (`{ action, amount, currency, destination, … }`). Returns `plan_id`, `tier`, `action_hash`, and a human-readable summary. No Stripe call happens yet.
2. **Show the user** the summary + tier so they know exactly what they're authorising (what-you-see-is-what-you-sign).
3. **Get the tier-appropriate approval:**
   - **T0:** none.
   - **T1:** `request_approval_credential` → `complete_approval_credential` (submit the acknowledgement) → an action-approval credential lands in the wallet.
   - **T2 / T3:** a **human** must approve at the WAUTH approve surface with their passkey (T3 also a live iProov face scan). **You cannot approve for them.** Surface the request, then **pause** and poll `get_plan` until the action-approval credential exists.
4. **`request_presentation` → `present_vp`** — present your wallet's verifiable presentation (+ SSH proof) to exchange the approval for a single-use **capability**.
5. **`execute_authorised_action`** — the doorkeeper performs the Stripe action with its own key and returns the result + a signed **receipt**. It takes only `plan_id`; you cannot re-parameterise at execution time.
6. **Audit anytime:** `get_receipt`, `list_audit_events`, `search_receipts`, `verify_audit_chain`.

## What you can't do (by design)
- You can't `enrol_developer`, `issue_wallet_credentials`, `delegate_agent_identity`, or register passkeys — those require the **admin** key and are filtered out of your `tools/list`. That's expected; ask the operator.
- You can't downgrade a T3 to a T2 or skip the human. If `plan_action` says T3, a live human approval is mandatory.

## When something fails
- **403 / a tool is missing from the list** → you're using the agent key (correct); that operation needs an operator/admin. Ask the human.
- **412** → the principal isn't enrolled yet (no passkey/biometric). The operator must enrol first.
- **Approval still pending** → keep polling `get_plan`; do not retry `execute_authorised_action` until the capability is minted.

> Connection details and the full tool list live in the doorkeeper's `CONNECT.md` / `MCP.md`.
> The trust model is `THREAT-MODEL.md` (the doorkeeper must be a different trust domain than you).
