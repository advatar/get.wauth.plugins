---
description: Place a commerce action through the WAUTH Verifiable-Intent doorkeeper (plan → approve → present → execute) against a signed intent mandate.
---

Run a commerce action through the WAUTH Verifiable-Intent doorkeeper using the
`wauth-verifiable-intent` MCP tools, following the **wauth-verifiable-intent** skill.

Action requested: $ARGUMENTS

Steps: call `plan_action` with the action (`catalog.read` / `quote.get` / `cart.create` /
`order.place` / `order.charge`), the merchant account, amount/currency/payee/item, and — for any
order — the human's signed **Verifiable-Intent mandate**. Show the user the returned **tier**, the
mandate verification result, and the order summary. Then obtain the tier-appropriate approval (T0
read — none; T1 cart/hold — acknowledge; T2 order within the mandate — a **human** passkey; T3
over-threshold / new payee / **missing or invalid mandate** — a human passkey **plus** a live iProov
face scan, which you cannot do for them, so pause and poll `get_plan`). Then `request_presentation`
→ `present_vp` → `execute_authorised_action`. You never receive a payment credential; the doorkeeper
places the order under the merchant lock and returns only an order/charge reference. Report the
signed receipt chain.
