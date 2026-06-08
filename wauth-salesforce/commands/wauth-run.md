---
description: Run the WAUTH ceremony for a Salesforce action (plan → approve → present → execute).
---

Run a Salesforce action through the WAUTH Salesforce doorkeeper using the `wauth_salesforce` MCP
tools, following the **wauth-salesforce** skill.

Action requested: $ARGUMENTS

Steps: call `plan_action`; show the user the returned tier + summary (remember production writes and
protected objects escalate to T3, server-authoritative); obtain the tier-appropriate approval (T0
none; T1 acknowledge; T2/T3 a **human** passkey approval — T3 also a live iProov face scan — which
you cannot do for them, so pause and poll `get_plan`); then `request_presentation` → `present_vp` →
`execute_authorised_action`. Never handle Salesforce credentials directly. Report the signed receipt.
