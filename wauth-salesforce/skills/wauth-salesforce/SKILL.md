---
name: wauth-salesforce
description: Perform Salesforce actions safely through the WAUTH Salesforce doorkeeper — propose a plan, let WAUTH classify the risk tier (production writes and protected objects escalate), route risky actions to a human passkey/liveness approval, then execute with credentials the agent never holds. Use whenever the user wants to query (SOQL), create/update/delete records, describe objects, or export data/reports via WAUTH.
---

# WAUTH Salesforce doorkeeper — agent guide

You act through a **doorkeeper**: a separate trust domain that holds the real Salesforce
credentials. You (the agent) **never see or handle them**. You hold only a least-privilege
**agent key**, supplied as the `wauth-salesforce` MCP server's bearer token. Your job is to
*propose* actions; WAUTH classifies their risk, and for risky ones a **human approves with a
passkey** (plus a live face scan for the riskiest). The doorkeeper performs the action and
returns a signed receipt.

## The one rule
Never ask the user for, accept, or store Salesforce credentials (session token, connected-app
secret, named credential), and never call the Salesforce REST/SOQL API directly. Everything goes
through the `wauth-salesforce` MCP tools.

## Risk tiers (you don't decide these — `plan_action` does)
- **T0 — observe (no approval):** `soql.query`, `sobject.describe`, `org.info`, `record.retrieve`.
- **T1 — acknowledge:** `record.create`; also **anything in a sandbox/scratch org** (the sandbox floor — for safe experimentation).
- **T2 — passkey:** `record.update`, `record.delete` within the row threshold on a non-protected object. A human approves with a **passkey**.
- **T3 — passkey + live face scan:** `data.export`, `report.export`, **bulk DML** (count over the threshold), DML on a **protected object** (User / Profile / PermissionSet / NamedCredential / …), and **any write in PRODUCTION**. A human approves with a **passkey AND an iProov liveness capture**.

**`production` is server-authoritative** — the doorkeeper reads the bound org's `isSandbox`, never
your supplied value. A production write escalates to T3 no matter what you pass. Always trust the
`tier` that `plan_action` returns.

## The ceremony (which tools, in order)
1. **`plan_action`** — describe the action (`{ action, org, sobject, record_id, soql, count }`). Returns `plan_id`, `tier`, `action_hash`, and a human-readable summary. No Salesforce call yet.
2. **Show the user** the summary + tier (what-you-see-is-what-you-sign).
3. **Get the tier-appropriate approval:**
   - **T0:** none.
   - **T1:** `request_approval_credential` → `complete_approval_credential` (acknowledgement) → approval credential in the wallet.
   - **T2 / T3:** a **human** must approve with their passkey (T3 also a live iProov face scan). **You cannot approve for them.** Surface the request, then **pause** and poll `get_plan` until approved.
4. **`request_presentation` → `present_vp`** — present your wallet's VP (+ SSH proof) to exchange the approval for a single-use **capability**.
5. **`execute_authorised_action`** — the doorkeeper performs the Salesforce action with its own credentials and returns the result + a signed **receipt**. It takes only `plan_id`; you cannot re-parameterise at execution time.
6. **Audit anytime:** `get_receipt`, `list_audit_events`, `search_receipts`, `verify_audit_chain`.

## What you can't do (by design)
- You can't `enrol_developer`, `issue_wallet_credentials`, `delegate_agent_identity`, or register passkeys — admin-key only, filtered out of your `tools/list`. Ask the operator.
- You can't downgrade a tier or skip the human. A production write or a protected object means a live human approval, full stop.

## When something fails
- **403 / a tool is missing** → agent key (correct); that operation needs an operator/admin.
- **412** → the principal isn't enrolled yet. The operator must enrol first.
- **Approval pending** → keep polling `get_plan`; don't retry `execute_authorised_action` until the capability is minted.

> Connection details and the full tool list live in the doorkeeper's `CONNECT.md` / `MCP.md`.
> The trust model is `THREAT-MODEL.md` (the doorkeeper must be a different trust domain than you).
