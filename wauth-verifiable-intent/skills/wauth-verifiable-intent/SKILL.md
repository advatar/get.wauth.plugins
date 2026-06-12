---
name: wauth-verifiable-intent
description: Place commerce actions through the WAUTH Verifiable-Intent doorkeeper. The agent carries a signed Verifiable-Intent mandate (the human's pre-authorised merchant, amount ceiling, item and validity window); the doorkeeper verifies the order is inside that envelope and applies the merchant lock. Reads/quotes are free (T0); placing an order within the mandate needs a human passkey (T2); over-threshold, paying a new payee, or a missing/invalid mandate needs a human passkey + iProov liveness (T3). The agent never holds a payment credential.
---

# WAUTH-VERIFIABLE-INTENT — intent-bound commerce for agents

You act through the WAUTH Verifiable-Intent doorkeeper's MCP tools. The doorkeeper is the
merchant-side broker: it holds the payment credential, verifies the human's **Verifiable-Intent
mandate**, applies the merchant lock, and executes the order. You never receive a payment credential.

## The ceremony
1. `plan_action({ action, account, amount, currency, payee, item, mandate })` → returns the risk
   **tier**, the `action_hash`, and the **mandate verification** (`mandate.ok`, the matched
   envelope, or the reason it failed). Show the user the tier + mandate result.
2. **T0** `catalog.read` / `quote.get` / `order.status`: permitted automatically — no step-up.
3. **T1** `cart.create` / `order.hold` (sandbox / non-committal): acknowledge; no human step-up.
4. **T2** `order.place` / `order.charge` **within the verified mandate** (amount ≤ ceiling, merchant
   matches, known payee): a **human passkey** is required.
5. **T3** over the mandate's threshold, a **new payee/destination**, an unbounded amount, or a
   **missing or invalid mandate**: a human **passkey + live iProov face scan**. You cannot satisfy
   it — hand off to the human and poll `get_plan`.
6. Once approved: `request_presentation` → `present_vp` → `execute_authorised_action`. The doorkeeper
   places the order under the merchant lock and returns an order/charge reference only.

## The Verifiable-Intent mandate
A signed statement of the human's pre-authorised intent — `{ merchant, amount_ceiling, currency,
item, valid_until }`. The doorkeeper verifies the issuer signature **and** that the requested order
is inside the envelope before it classifies. An order outside the envelope, or with no mandate,
fails closed to T3.

## Rules
- Never relabel an order to dodge tiering — the tier is fixed server-side by the action, the amount,
  the payee, and the mandate envelope; an unknown action fails closed to T3.
- You never receive a payment credential and it is never written into a receipt
  (`agent_receives_payment_credential: false`).
- Every phase — plan, mandate verification, approval, execution, refusal — is a signed receipt.
- Reputation/standing is observational and never lowers a required tier.

Requires `WAUTH_VINTENT_KEY` (the least-privilege agent key from your WAUTH admin).
