---
name: wauth-link
description: Link a payment key to an agent under a WAUTH merchant lock through the WAUTH Link doorkeeper, then pay against it. The doorkeeper holds the key server-side; the agent proposes payments and never sees the key. Reading the linked instrument is free (T0); paying a known destination within threshold needs a human passkey (T2); linking a new key, paying a new destination, or any over-threshold/bulk payment needs a human passkey + iProov liveness (T3). Live-vs-sandbox is decided server-side.
---

# WAUTH-LINK — link a payment key to an agent, pay under a merchant lock

You act through the WAUTH Link doorkeeper's MCP tools. The doorkeeper holds the linked payment key
(or network token) **server-side** under a merchant lock; you propose payments and **never** see the
key.

## The ceremony
1. `plan_action({ action, account, amount, currency, destination })` → returns the risk **tier** and
   the `action_hash`. Show the user the tier + the payment summary.
2. **T0** `instrument.status` / `instrument.list`: permitted automatically — no step-up.
3. **T1** link/charge in **sandbox/test** mode: acknowledge; no human step-up.
4. **T2** `payment.charge` to an **already-known** destination within the threshold: a **human
   passkey** is required.
5. **T3** `instrument.link` of a **new key**, paying a **new destination**, or an over-threshold /
   bulk payment: a human **passkey + live iProov face scan**. You cannot satisfy it — hand off to
   the human and poll `get_plan`.
6. Once approved: `request_presentation` → `present_vp` → `execute_authorised_action`. The doorkeeper
   settles under the merchant lock and returns a payment reference only.

## Rules
- **Live-vs-sandbox is server-authoritative.** You cannot set a `livemode`/`test` flag to dodge
  tiering — the doorkeeper decides the mode from the linked instrument.
- A payment to a **new destination** always escalates to T3, regardless of amount.
- You never receive the payment key and it is never written into a receipt
  (`agent_receives_payment_key: false`).
- Every phase — plan, approval, link, payment, refusal — is a signed receipt.
- Reputation/standing is observational and never lowers a required tier.

Requires `WAUTH_LINK_KEY` (the least-privilege agent key from your WAUTH admin).
