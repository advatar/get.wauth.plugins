---
description: Link a payment key and pay against it through the WAUTH Link doorkeeper (plan → approve → present → execute) under a merchant lock.
---

Link a payment instrument or make a payment through the WAUTH Link doorkeeper using the
`wauth-link` MCP tools, following the **wauth-link** skill.

Action requested: $ARGUMENTS

Steps: call `plan_action` with the action (`instrument.status` / `instrument.link` /
`payment.charge`), the merchant account, and amount/currency/destination for a payment. Show the
user the returned **tier** and payment summary. Then obtain the tier-appropriate approval (T0
status/list — none; T1 sandbox link/charge — acknowledge; T2 payment to a **known** destination
within threshold — a **human** passkey; T3 linking a **new key**, paying a **new destination**, or
an over-threshold/bulk payment — a human passkey **plus** a live iProov face scan, which you cannot
do for them, so pause and poll `get_plan`). Then `request_presentation` → `present_vp` →
`execute_authorised_action`. You never receive the payment key; the doorkeeper holds it server-side,
settles under the merchant lock, and returns only a payment reference. Live-vs-sandbox is decided by
the doorkeeper, not by you. Report the signed receipt chain.
