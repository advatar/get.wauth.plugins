---
description: Run the WAUTH ceremony for a GitHub action (plan → approve → present → execute).
---

Run a GitHub action through the WAUTH GitHub doorkeeper using the `wauth-github` MCP tools,
following the **wauth-github** skill.

Action requested: $ARGUMENTS

Steps: call `plan_action`; show the user the returned tier + summary; obtain the tier-appropriate
approval (T0 none; T1 acknowledge; T2/T3 a **human** passkey approval — T3 also a live iProov face
scan — which you cannot do for them, so pause and poll `get_plan`); then `request_presentation` →
`present_vp` → `execute_authorised_action`. Never handle a GitHub token directly. Report the receipt.
