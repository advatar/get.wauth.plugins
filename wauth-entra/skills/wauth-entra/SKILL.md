---
name: wauth-entra
description: Use the WAUTH Entra doorkeeper to act on a Microsoft Entra tenant safely. Directory reads are free (T0); credential / identity-affecting actions (MFA reset, password reset, account unlock, privileged role grant, conditional-access change, app consent/credential) require a human passkey + iProov liveness step-up (T3). The agent never holds a Microsoft Graph credential.
---

# WAUTH-ENTRA — identity control plane

You act through the WAUTH Entra doorkeeper's MCP tools. You never receive a Microsoft Graph token; the doorkeeper holds it and executes only after the required human step-up.

## The ceremony
1. `plan_action({ action, tenant, target_upn, ... })` → returns the risk tier + verification_method.
2. **T0** directory reads / help-desk reads: permitted automatically — gather context.
3. **T1** open a ticket, report a hardware fault: acknowledge; no human step-up.
4. **T2** non-sensitive attribute update, group membership, license, software request: a human passkey is required.
5. **T3** MFA reset, password reset, account unlock, user delete, role assign/remove, conditional-access / auth-method-policy change, app admin-consent / credential add: a human **passkey + iProov liveness** step-up is required. You cannot satisfy it — hand off to the account holder and wait.
6. `request_presentation` → `present_vp` → `execute_authorised_action` once approved. You read result references only; you never see the Graph token.

## Rules
- Never try to bypass the step-up. A credential request cannot be relabelled as a "ticket" — the action type fixes the tier server-side.
- Reads are free; contact the help desk for harmless things (hardware, KB) freely. Only credential / identity changes are gated.
- Every action — including refusals — is sealed into a signed receipt chain (proposed / approved / executed).

Requires `WAUTH_ENTRA_KEY` (the least-privilege agent key from your WAUTH admin).
