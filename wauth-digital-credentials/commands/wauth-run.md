---
description: Present a digital credential through the WAUTH Digital-Credentials doorkeeper (plan → approve → present → execute).
---

Present a wallet credential through the WAUTH Digital-Credentials doorkeeper using the
`wauth-digital-credentials` MCP tools, following the **wauth-digital-credentials** skill.

Presentation requested: $ARGUMENTS

Steps: call `plan_action` with the action (`credential.types.read` / `attribute.present.sandbox` /
`credential.present.standard` / `identity.present.high_assurance` / `age.present` / `kyc.present` /
`government_id.present`) and the RP `scope`. Show the user the returned **tier**. Then obtain the
tier-appropriate approval (T0 read — none; T1 sandbox attribute — acknowledge; T2 standard credential
— a **human** passkey; T3 high-assurance identity / age / KYC / government-ID, or a failed holder
binding — a human passkey **plus** a live iProov face scan, which you cannot do for them, so pause
and poll `get_plan`). Then `request_presentation` → `present_vp` (the holder signs the aud/nonce-bound
vp_token) → `execute_authorised_action`. You never receive the raw credential or any wallet secret;
the doorkeeper verifies the presentation and issues only scoped authority. Report the signed receipt
chain.
