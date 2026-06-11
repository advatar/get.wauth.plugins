---
name: wauth-github
description: Perform GitHub coding-agent actions safely through the WAUTH GitHub doorkeeper — propose a plan, let WAUTH classify the risk tier, route risky actions (protected-branch merges, force-push, CI bypass, branch-protection or secrets changes) to a human passkey/liveness approval, then execute with a credential the agent never holds. Use whenever the user wants to read repo state, comment, open branches, merge PRs, or perform high-risk GitHub actions via WAUTH.
---

# WAUTH GitHub doorkeeper — agent guide

You act through a **doorkeeper**: a separate trust domain that holds the real GitHub App
credential. You (the agent) **never see or handle it**. You hold only a least-privilege **agent
key**, supplied as the `wauth-github` MCP server's bearer token. You *propose* actions; WAUTH
classifies their risk, and for risky ones a **human approves with a passkey** (plus a live face scan
for the highest tier). The doorkeeper performs the action and returns a signed receipt.

## The one rule
Never ask the user for, accept, or store a GitHub token / App private key, and never call the
GitHub API directly. Everything goes through the `wauth-github` MCP tools.

## Risk tiers (you don't decide these — `plan_action` does)
- **T0 — observe (no approval):** read-only repo state (read PRs/files, CI status, list issues).
- **T1 — acknowledge:** routine writes (e.g. comment, open a branch, merge to a non-protected branch). A lightweight acknowledgement.
- **T2 — passkey:** merges to a **protected branch** (e.g. `main`). A human approves with a **passkey**.
- **T3 — passkey + live face scan:** `force_push`, `ci_bypass`, `branch_protection_change`, `secrets_access`. A human approves with a **passkey AND an iProov liveness capture**.

Always trust the `tier` that `plan_action` returns; never infer it yourself.

## The ceremony (which tools, in order)
1. **`plan_action`** — describe the action (`{ repository, action, base_branch, pull_number, head_sha, … }`). Returns `plan_id`, `tier`, `action_hash`, summary. No GitHub call yet.
2. **Show the user** the summary + tier (what-you-see-is-what-you-sign).
3. **Get the tier-appropriate approval:**
   - **T0:** none.
   - **T1:** `request_approval_credential` → `complete_approval_credential` (acknowledgement) → approval credential in the wallet.
   - **T2 / T3:** a **human** must approve at the WAUTH approve surface with their passkey (T3 also a live iProov face scan). **You cannot approve for them.** Surface the request, then **pause** and poll `get_plan` until approved.
4. **`request_presentation` → `present_vp`** — present your wallet's VP (+ SSH proof) to exchange the approval for a single-use **capability**.
5. **`execute_authorised_action`** — the doorkeeper performs the GitHub action with its own credential and returns the result + a signed **receipt**. It takes only `plan_id`; you cannot re-parameterise at execution time.
6. **Audit anytime:** `get_receipt`, `list_audit_events`, `search_receipts`, `verify_audit_chain`. Your own track record is visible via `get_reputation` (observational only — it never changes the tier).

## What you can't do (by design)
- You can't `enrol_developer`, `issue_wallet_credentials`, `delegate_agent_identity`, or register passkeys — admin-key only, filtered from your `tools/list`. Ask the operator.
- You can't downgrade a tier or skip the human. A force-push or secrets change means a live human approval, full stop.

## When something fails
- **403 / a tool is missing** → agent key (correct); that operation needs an operator/admin.
- **412** → the principal isn't enrolled yet (passkey/biometric). The operator must enrol first.
- **Approval pending** → keep polling `get_plan`; don't retry `execute_authorised_action` until the capability is minted.

## Secure run — box the agent (operator setup)
For a hostile-agent threat model, launch this agent inside the hardened container in `secure-run/`
(`secure-run/run.sh`): it mounts **only the repo** and drops `$HOME`, `~/.ssh`, the `gh` token, the
SSH-agent socket and cloud creds; runs non-root + read-only; and lets the box reach only the
doorkeeper, the model API, and package registries. Then the doorkeeper isn't just the *sanctioned*
path to a GitHub write — it's the only *reachable* one (you hold no GitHub credential and there's no
ambient host secret to steal). The container is the enforcement; this skill is only the bootstrap.
See `secure-run/README.md`.

> Connection details and the full tool list live in the doorkeeper's `CONNECT.md` / `MCP.md`.
> The trust model is `THREAT-MODEL.md` (the doorkeeper must be a different trust domain than you).
