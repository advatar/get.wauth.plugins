# get.wauth.plugins — WAUTH pilot plugins for Codex & Claude

The public marketplace for the **WAUTH doorkeeper pilots**. One command adds the marketplace, one
more installs a pilot — for either OpenAI Codex or Claude Code.

| Pilot | Plugin | What it governs |
|---|---|---|
| GitHub | `wauth-github` | Coding-agent actions (protected-branch merges → passkey; force-push / CI-bypass / branch-protection / secret changes → passkey + iProov liveness). |
| Stripe | `wauth-stripe` | Payment/account actions (high-risk → passkey + iProov liveness). |
| Salesforce | `wauth-salesforce` | CRM actions (production writes + protected objects → passkey + liveness). |

## Install

First get an **agent key** from your WAUTH admin (least-privilege: it can plan/present/execute, but
cannot enrol, issue credentials, or register passkeys). Never commit it. Export the key(s) for the
pilot(s) you install:

```bash
export WAUTH_GITHUB_KEY=...        # for wauth-github
export WAUTH_STRIPE_KEY=...        # for wauth-stripe
export WAUTH_SALESFORCE_KEY=...    # for wauth-salesforce
```

**OpenAI Codex** (reads `.codex-plugin/plugin.json`):

```bash
codex plugin marketplace add advatar/get.wauth.plugins
codex plugin add wauth-github@wauth         # or wauth-stripe@wauth · wauth-salesforce@wauth
```

**Claude Code** (reads `.claude-plugin/plugin.json`):

```bash
claude plugin marketplace add advatar/get.wauth.plugins
claude plugin install wauth-github@wauth     # or wauth-stripe@wauth · wauth-salesforce@wauth
```

**Claude Cowork** — hosted runs reach remote MCP only; the manifests already use the remote `/mcp`
HTTP endpoint, so the same bundle works unchanged.

## What these are (and are not)

WAUTH's guarantee (`THREAT-MODEL.md §1`) is that **the doorkeeper is a different trust domain than
the agent**. A plugin runs *inside the agent's context*, which is untrusted and prompt-injectable —
so each bundle is deliberately thin:

```
┌─ Plugin (Codex / Claude) — runs in the AGENT context, UNTRUSTED ──────┐
│  • SKILL.md   the WAUTH ceremony + risk tiers + "hand off to a human"  │
│  • command    /wauth-run <action>                                      │
│  • mcpServers points at the doorkeeper; carries only an AGENT key      │
└──────────────────────────────┬─────────────────────────────────────────┘
                               │ MCP (HTTP, bearer = agent key)
┌───────────────────────────────▼── Doorkeeper on Cloud Run ────────────┐
│  holds the platform creds + issuer key · runs the risk tiers ·         │
│  human approval (passkey + iProov liveness) · signs the audit chain    │
└────────────────────────────────────────────────────────────────────────┘
```

**The one rule:** a plugin must never carry a platform credential or make a tier decision. The
GitHub/Stripe/Salesforce credentials and the policy engine stay in the doorkeeper; human approval
(passkey / iProov liveness) happens at the doorkeeper's approve surface, out of the agent's reach —
the plugin can only *pause and wait* for it.

## Layout

Each pilot is one self-contained directory carrying **both** manifests (they don't collide), a
shared skill, and a command:

```
get.wauth.plugins/
├── .claude-plugin/marketplace.json    # marketplace listing — read by BOTH Claude and Codex
├── .agents/plugins/marketplace.json   # Codex's canonical marketplace path (mirror)
├── wauth-github/
│   ├── .codex-plugin/plugin.json      # Codex manifest  → mcpServers: "./.mcp.json"
│   ├── .claude-plugin/plugin.json     # Claude manifest → mcpServers: "./.mcp.json"
│   ├── .mcp.json                      # remote-MCP config (type http + bearer header)
│   ├── skills/wauth-github/SKILL.md   # the ceremony + GitHub risk tiers (shared by both)
│   └── commands/wauth-run.md          # /wauth-run <action>
├── wauth-stripe/      … same shape, Stripe action vocab …
└── wauth-salesforce/  … same shape, Salesforce action vocab …
```

Both ecosystems read the **same** `marketplace.json` and the **same** per-plugin `.mcp.json`; only
the small `.codex-plugin/` vs `.claude-plugin/` manifest differs.

## How it maps to the doorkeeper

The MCP server, tools, tiers, and human-approval flow are unchanged — see each service's `CONNECT.md`
and `MCP.md` under `services/wauth-*-doorkeeper/` in the [WAUTH repo](https://github.com/advatar/WAUTH).
The agent calls `plan_action → request_presentation → present_vp → execute_authorised_action`; T2/T3
approvals are produced by a human (passkey, plus iProov liveness for T3). These plugins make that flow
installable in one step instead of a hand-followed `CONNECT.md`.

> One MCP backend → two client formats (Codex + Claude) → three pilots (GitHub, Stripe, Salesforce).
