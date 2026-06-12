# Secure run — box the agent

Run a coding agent (Codex / Claude Code) in a hardened container so the **only reachable path to a
GitHub write is the WAUTH doorkeeper**. This is the runtime-containment layer that *composes with*
WAUTH's endpoint authority: the doorkeeper makes itself the only **sanctioned** writer (it holds the
GitHub App credential, the agent never does); the box makes it the only **reachable** one (the agent
has no ambient host credential to steal and no open egress to GitHub).

It is the answer to a simple question: *if the agent is hostile or prompt-injected, what can it
actually reach?* In the box: the repo, the model API, the doorkeeper, package registries — and
nothing else.

## Three ways to box it — pick by trust level + platform

| | What it is | Boundary | Use when |
|---|---|---|---|
| **Tier A** | macOS Seatbelt sandbox (`sandbox-exec`), **no Docker** — [`seatbelt/`](./seatbelt) | kernel sandbox profile: secrets unreadable, persistence vectors unwritable | macOS, semi-trusted agent, you want zero friction on your real toolchain |
| **Tier B** | hardened container — [`run.sh`](./run.sh) + [`Dockerfile`](./Dockerfile) | container/VM: the secret is simply **not mounted** | any OS, hostile-agent case, you want "YOLO in a sandbox" |
| **Tier C** | the **doorkeeper** itself | trust-domain split: the protected credential is **never on the box** | always — A/B layer *under* it |

Tier C is always on (it's WAUTH). Tiers A and B are the runtime-containment layer that decides how
much an on-box agent can touch. Pick A for frictionless macOS, B when you assume the agent is hostile.

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

## Tier A — macOS Seatbelt (no Docker)

The frictionless tier: the agent runs on your **real machine** with your real toolchain, inside an
Apple Seatbelt sandbox ([`seatbelt/wauth-agent.sb`](./seatbelt/wauth-agent.sb)) that makes the
host's credential stores **unreadable** and the key persistence vectors **unwritable**.

```sh
WAUTH_GITHUB_KEY="<least-privilege doorkeeper agent key>" \
OPENAI_API_KEY="<a scoped model key>" \
  ./secure-run/seatbelt/secure-run-seatbelt.sh /path/to/your/repo -- codex
# (no command after -- → an interactive shell inside the sandbox; then run `codex` / `claude`)
```

**What it enforces** (verified on macOS, `sandbox-exec`):

- **Default-deny *reads* across `$HOME`** — `~/.ssh`, the `gh` token (`~/.config/gh`), `~/.aws`,
  the **cloud-CLI credentials** (`~/.config/gcloud`, `~/.azure`), `~/.gnupg`, `~/.kube`,
  `~/Library/Keychains`, and any *unenumerated* secret under home are unreadable. Re-allowed: the
  workspace, the agent's own `~/.codex`/`~/.claude`, and non-secret dev toolchains (`~/.nvm`,
  `~/.cargo`, `~/.pyenv`, …) so the agent and its runtime still work.
- **Cloud CLIs can't run or authenticate.** Because cloud credentials live under `$HOME` — and the
  CLI binaries often do too (e.g. `~/bin/google-cloud-sdk`) — a boxed agent cannot run
  `gcloud secrets versions access …`, `aws secretsmanager get-secret-value …`, or `az keyvault …`
  to exfiltrate platform secrets: the credential is unreadable and, when the CLI lives under home,
  it won't even exec. Verified: `gcloud secrets versions access` inside the box fails with
  `Operation not permitted`.
- **Deny *writes*** to the cheapest persistence vectors — `~/.ssh` (no planting an `authorized_key`),
  `~/Library/LaunchAgents`, and the shell-init files (`~/.zshrc`, `~/.bashrc`, …).
- The workspace is fully read/write; network and the system toolchain work normally.

**Default-deny-read, scoped to `$HOME`.** This is the [neko-kai/claude-code-sandbox](https://github.com/neko-kai/claude-code-sandbox)
"noread" model (deny reads by default, allow-list what's needed) — *but scoped to the home directory
rather than `/`*, because a from-scratch `(deny default)` profile reliably breaks macOS's outbound
network plumbing (the well-known Seatbelt rabbit hole). Scoping the read-deny to `$HOME` keeps the
network/system stack working while still **failing closed**: an unknown dotfile under home is denied
until you explicitly allow it — which a deny-list of named secret paths can never guarantee. Egress
allow-listing is layered separately via `HTTPS_PROXY` (see below), after
[michaelneale/agent-seatbelt-sandbox](https://github.com/michaelneale/agent-seatbelt-sandbox).

> Trade-off, stated plainly: if a tool lives under `$HOME` in a dir the profile doesn't re-allow,
> it gets a read error — the **fail-closed** direction (a functionality gap, never a silent
> exposure). Add the dir to the re-allow block in `wauth-agent.sb`; never add a credential dir.
> `sandbox-exec(1)` is deprecated-but-functional and SBPL can shift between macOS releases — Tier A
> is the *semi-trusted* tier. For a hostile agent, use Tier B or rely on Tier C.

## Allow-list, not deny-list (Tier B)

The container doesn't *deny* `~/.ssh` — it never mounts it. Only the repo is mounted; `$HOME`,
`~/.config/gh`, cloud creds, and the SSH-agent socket are simply absent. That's strictly more robust
than enumerating sensitive paths to block (you can never enumerate them all).

## Tier B — use it (hardened container)

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

## Test the box (adversarial probes)

Don't take the containment on faith — run the probe harnesses. Each launches a battery of
"hostile agent" attempts *inside* the box and asserts every one is contained (and that normal work
still functions). Exit 0 = fully contained; non-zero = a leak/escape, with the offending probe named.

```sh
# Tier A (macOS Seatbelt) — no Docker needed, runs in seconds:
./secure-run/seatbelt/test-seatbelt-box.sh

# Tier B (container) — builds the box image on first run, then probes it:
./secure-run/test-container-box.sh
```

What they assert:
- **Reads denied** — `~/.ssh`, the `gh` token, `~/.aws`, `~/.config/gcloud`, Keychains, **and an
  unenumerated decoy secret planted in `$HOME`** (proving Tier A's default-deny-read catches secrets
  no deny-list names). A read-probe only counts when the file is genuinely readable on the host
  first, so "denied" means the box blocked a *real* secret, not an absent file.
- **Persistence-writes denied** — planting an `authorized_key` / a LaunchAgent (Tier A); read-only
  rootfs + no host mounts (Tier B). Write-probes use throwaway canary names so a hypothetical escape
  can't clobber a real dotfile.
- **Cloud-CLI exfiltration denied** — `gcloud secrets versions access …` can't run or authenticate
  in the box.
- **Containment holds without breaking work** — workspace read/write, system reads, and the node
  toolchain still function; Tier B additionally checks non-root, dropped caps, and no-egress under
  `--network none` (the proxy allow-list enforces the rest).

Run them in CI against any change to the profile/launcher/Dockerfile — a regression that opens a hole
turns the exit code red.

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
- **Tier A (Seatbelt) is the semi-trusted tier, not a hostile-agent jail.** It read-protects secrets
  and blocks the cheap persistence writes, but the agent still shares your kernel and network namespace,
  and `sandbox-exec` is a deprecated (if functional) interface whose behaviour can change between macOS
  releases. If you must assume the agent is actively hostile, use Tier B (container) or rely on Tier C
  (the credential is never on the box). Tiers compose — run A *and* C, or B *and* C.
