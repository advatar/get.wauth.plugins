---
description: Request just-in-time SaaS access through the WAUTH SaaS JIT control plane (request → approve → provision → execute → revoke).
---

Request a time-limited SaaS access grant through the WAUTH SaaS JIT control plane using the
`wauth-saas-jit` MCP tools, following the **wauth-saas-jit** skill.

Access requested: $ARGUMENTS

Steps: call `saas_jit_request` with the target (provider/tenant/resource/action), the entitlement,
and the execution mode; show the user the returned **tier** + the time-limited grant summary. Then
obtain the tier-appropriate approval (T0 read — no grant needed; T1 sandbox — acknowledge; T2
production — a **human** passkey; T3 privileged/admin or legacy-token mode — a human passkey **plus**
a live iProov face scan — which you cannot do for them, so pause until the holder approves). Then
`saas_jit_provision` → `saas_jit_execute` → `saas_jit_revoke`. You never receive the provisioned
SaaS credential; the control plane provisions, executes under it, then revokes and reconciles. Report
the signed canonical evidence (the receipt chain) at the end.
