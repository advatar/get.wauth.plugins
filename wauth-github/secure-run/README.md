# Secure run — box the agent

Run a coding agent (Codex / Claude Code) in a hardened container so the **only reachable path to a
GitHub write is the WAUTH doorkeeper**. This is the runtime-containment layer that *composes with*
WAUTH's endpoint authority: the doorkeeper makes itself the only **sanctioned** writer (it holds the
GitHub App credential, the agent never does); the box makes it the only **reachable** one (the agent
has no ambient host credential to steal and no open egress to GitHub).

It is the answer to a simple question: *if the agent is hostile or prompt-injected, what can it
actually reach?* In the box: the repo, the model API, the doorkeeper, package registries — and
nothing else.

## Why a box at all — the threat WAUTH alone doesn't cover

A local coding agent runs as **you**, with **your** filesystem. Without a box it can read
`~/.ssh/id_*`, the `gh` token (`~/.config/gh/hosts.yml`), `~/.aws`, `~/.netrc`, the SSH-agent
socket, browser cookie stores — none of which are in WAUTH's trust domain (see the repo's
`THREAT-MODEL.md` residual #8). WAUTH removes the *need* to give the agent a privileged credential,
but it cannot stop a hostile agent from exfiltrating a pre-existing personal key. The box does:
the credential simply **isn't there**.

## Two credential classes — the rule

- **Cognition credential** (`OPENAI_API_KEY` / `ANTHROPIC_API_KEY`): the agent talking to its model.
  This **must** be in the box. Use a key scoped to this use, not your everyday personal one.
- **Resource credential** (the GitHub App key): **never** in the box. It lives server-side in the
  doorkeeper. The agent's only route to a protected write is an MCP call to the doorkeeper, which
  runs the passkey/liveness step-up.

The least-privilege **WAUTH doorkeeper key** (`WAUTH_GITHUB_KEY`) is in the box too — but it only
lets the agent *propose*; it cannot bypass approval, cannot fetch the GitHub token, and is revocable
fleet-wide. So you never put a git push token (or `~/.ssh`) in the box to "make it useful" — the
doorkeeper performs the write.

## Allow-list, not deny-list

The box doesn't *deny* `~/.ssh` — it never mounts it. Only the repo is mounted; `$HOME`,
`~/.config/gh`, cloud creds, and the SSH-agent socket are simply absent. That's strictly more robust
than enumerating sensitive paths to block (you can never enumerate them all).

## Use it

```sh
# 1) Build the box image (pick your agent):
docker build --build-arg AGENT=codex -t wauth-agent-box ./secure-run

# 2) Launch — mounts ONLY the repo, drops all ambient creds:
WAUTH_GITHUB_KEY="<least-privilege doorkeeper agent key>" \
OPENAI_API_KEY="<a scoped model key>" \
  ./secure-run/run.sh /path/to/your/repo

# 3) Inside the box, wire the doorkeeper once, then work:
#    codex plugin marketplace add advatar/get.wauth.plugins
#    codex plugin add wauth-github@wauth     # MCP bearer resolves from $WAUTH_GITHUB_KEY
#    codex                                   # run fully autonomous — the walls are the container
```

Running the agent **fully unlocked inside the box** ("YOLO in a sandbox") is the point: full
autonomy on the inside, hard walls on the outside — you stop trading capability against safety.

## Egress: the stronger variant

By default the container uses Docker's bridge network (it needs to reach the model API, the
doorkeeper, and registries). To make egress an allow-list rather than open, run a filtering proxy
(host firewall, a sidecar like `tinyproxy`/`squid` with an allow-list, or your org's egress proxy)
and point the box at it:

```sh
HTTPS_PROXY="http://your-allowlist-proxy:3128" \
WAUTH_GITHUB_KEY=... OPENAI_API_KEY=... ./secure-run/run.sh /path/to/repo
```

Allow only: your doorkeeper host, `api.openai.com` (or `api.anthropic.com`), and the package
registries you need. Everything else — including a direct hop to `api.github.com` — is then blocked
at the network layer, not by the agent's goodwill.

## Hardening the launcher already applies

Non-root (`--user 1000:1000`), read-only rootfs (`--read-only`) with throwaway tmpfs `HOME`/`/tmp`,
all Linux capabilities dropped (`--cap-drop ALL`), no privilege escalation
(`--security-opt no-new-privileges`), and pid/memory/cpu limits. Credentials are passed **by name**
(`--env VAR`), so their values are inherited from your shell, never written into the container argv.

## Honest limitations

- The **cognition key is still in the box** — a compromised agent can use it to talk to its model
  (and burn quota); scope it and rotate it. It cannot reach GitHub with it.
- The `WAUTH_GITHUB_KEY` is present but **least-privilege + revocable**; if you suspect compromise,
  `revoke_agent` kills it fleet-wide immediately.
- On macOS this relies on Docker Desktop / colima providing the Linux-VM boundary; trust follows
  your container runtime.
- This is the **bootstrap + enforcement**, not the policy: the doorkeeper still decides tiers and
  demands the human step-up. The box only guarantees the doorkeeper is the *only door*.
