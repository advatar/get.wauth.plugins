---
description: Run the WAUTH ceremony for a Stripe action (plan → approve → present → execute).
---

Run a Stripe action through the WAUTH Stripe doorkeeper using the `wauth_stripe` MCP tools,
following the **wauth-stripe** skill.

Action requested: $ARGUMENTS

Steps: call `plan_action`; show the user the returned tier + summary; obtain the tier-appropriate
approval (T0 none; T1 acknowledge via `request_approval_credential` → `complete_approval_credential`;
T2/T3 a **human** passkey approval — T3 also a live iProov face scan — which you cannot do for them,
so pause and poll `get_plan`); then `request_presentation` → `present_vp` → `execute_authorised_action`.
Never handle a Stripe secret key directly. Report the signed receipt.
