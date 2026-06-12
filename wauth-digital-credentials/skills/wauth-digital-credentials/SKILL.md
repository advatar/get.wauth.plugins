---
name: wauth-digital-credentials
description: Present a digital wallet credential (Apple Wallet / Digital Credentials API / mdoc / EUDI) through the WAUTH Digital-Credentials doorkeeper, bound via HAPP. The doorkeeper verifies the presentation (issuer-signed, holder-bound, aud/nonce-bound, unexpired) and issues scoped authority. Reading accepted types is free (T0); a standard credential needs a human passkey (T2); a high-assurance identity / age / KYC / government-ID presentation — or a failed holder binding — needs a human passkey + iProov liveness (T3). The agent never holds the raw credential.
---

# WAUTH-DIGITAL-CREDENTIALS — wallet-credential presentment for agents

You act through the WAUTH Digital-Credentials doorkeeper's MCP tools. The doorkeeper verifies a
presented wallet credential and issues **scoped authority**; it never hands you the raw credential
or any wallet secret.

## The ceremony
1. `plan_action({ action, scope })` → returns the risk **tier** and the `action_hash`. Show the
   user the tier.
2. **T0** `credential.types.read` / `presentation.request.read` / `credential.status.read`:
   permitted automatically — no step-up.
3. **T1** `attribute.present.sandbox` (low-assurance, sandbox): acknowledge; no human step-up.
4. **T2** `credential.present.standard` / `.membership` / `.email`: a **human passkey** is required.
5. **T3** `identity.present.high_assurance` / `age.present` / `kyc.present` / `government_id.present`,
   or **any presentation whose holder binding fails**: a human **passkey + live iProov face scan**.
   You cannot satisfy it — hand off to the human and poll `get_plan`.
6. Once approved: `request_presentation` → `present_vp` (the holder signs the aud/nonce-bound
   vp_token) → `execute_authorised_action`.

## What the doorkeeper verifies (fail closed)
The presented credential must be **issuer-signed**, **holder-bound** (proof-of-possession by the
holder), **aud/nonce-bound to this request**, and **unexpired**. Any failure fails closed — a failed
holder binding escalates to T3 rather than proceeding.

## Rules
- Never relabel a high-assurance presentation as a standard or sandbox one — the tier is fixed
  server-side by the credential class and the action; an unknown action fails closed to T3.
- You never receive the raw credential and it is never written into a receipt
  (`agent_receives_wallet_credential: false`).
- Every phase — plan, presentation, verification, approval, execution, refusal — is a signed receipt.
- Reputation/standing is observational and never lowers a required tier.

Requires `WAUTH_DCRED_KEY` (the least-privilege agent key from your WAUTH admin).
