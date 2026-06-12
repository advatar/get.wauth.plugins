---
name: wauth-saas-jit
description: Use the WAUTH SaaS JIT control plane (AFPS) to obtain just-in-time, time-limited SaaS access for an agent. Reads are free (T0); a production grant needs a human passkey (T2); a privileged/admin grant — or the legacy contained-user-token mode — needs a human passkey + iProov liveness (T3). The grant is short-lived, auto-revoked and reconciled, and the agent never holds the provisioned SaaS credential.
---

# WAUTH-SAAS-JIT — just-in-time SaaS access for agents

You act through the WAUTH SaaS JIT control plane's MCP tools. You never receive a standing SaaS
credential; the control plane provisions a **time-limited** grant, executes the approved action under
it, then **revokes and reconciles** it — leaving a signed canonical-evidence chain.

## The lifecycle
1. `saas_jit_request({ provider, tenant, resource, action, entitlement, execution_mode, ttl_seconds })`
   → returns the risk **tier**, the `action_hash`, and a time-limited request. Show the user the tier.
2. **T0** read / list / describe a resource: permitted automatically — no grant, no step-up.
3. **T1** sandbox / non-production tenant: acknowledge; no human step-up.
4. **T2** production grant, standard privilege: a **human passkey** is required.
5. **T3** privileged / admin entitlement, or the `legacy_user_token_contained` mode: a human
   **passkey + live iProov face scan** is required. You cannot satisfy it — hand off to the human
   and wait.
6. Once approved: `saas_jit_provision` (mint the time-limited grant) → `saas_jit_execute` (act under
   it) → `saas_jit_revoke` (revoke + reconcile). `saas_jit_get` returns the session + signed evidence.

## Execution modes
- `agent_identity` (preferred): the agent acts as its own scoped app/service principal.
- `doorkeeper_proxy`: the control plane holds the credential; the agent never sees it.
- `legacy_user_token_contained` (fallback): a user token stays contained in the broker, bound to the
  action hash and revoked after use — this mode is always T3.

## Rules
- Never try to skip the step-up or relabel a production/admin grant as a sandbox one — the tier is
  fixed server-side by the target + entitlement, and an unknown classification fails closed to T3.
- The provisioned credential is **never** exposed to the agent and never written into a receipt
  (`token_exposed_to_agent: false`).
- Every phase — request, approval, grant, execution, revocation, reconciliation — is a signed receipt;
  the final `saas_jit_get` returns the canonical evidence with the full receipt chain.
- Reputation/standing is observational and never lowers a required tier.

Requires `WAUTH_SAAS_JIT_KEY` (the least-privilege agent key from your WAUTH admin).
