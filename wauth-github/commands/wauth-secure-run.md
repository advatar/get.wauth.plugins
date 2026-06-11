---
description: Show how to run this agent boxed (no ambient creds; the doorkeeper is the only reachable GitHub write path).
---

Explain and, if asked, launch the **secure-run** box for the WAUTH GitHub pilot, following the
**wauth-github** skill's "Secure run" section and `secure-run/README.md`.

Two boxes, pick by trust level + platform:

- **Tier A — macOS Seatbelt, no Docker** (`secure-run/seatbelt/secure-run-seatbelt.sh`): runs the
  agent on the real machine inside an Apple sandbox profile that makes the host credential stores
  **unreadable** (`~/.ssh`, `gh` token, `~/.aws`, `~/.gnupg`, `~/.kube`, Keychains — all of `$HOME`
  except the workspace + the agent's own toolchain dirs) and blocks writes to the key persistence
  vectors. Frictionless; the semi-trusted tier.
- **Tier B — hardened container** (`secure-run/run.sh` + `secure-run/Dockerfile`): mounts **only the
  repo** — no `$HOME`, no `~/.ssh`, no `gh` token, no SSH-agent socket, no cloud creds — non-root,
  read-only rootfs, dropped capabilities, egress constrainable to the doorkeeper + model API +
  registries. Use for the hostile-agent threat model.

Either box holds only the **cognition** credential (`OPENAI_API_KEY`/`ANTHROPIC_API_KEY`) and the
least-privilege `WAUTH_GITHUB_KEY`; the GitHub App credential is never present. Result: the
doorkeeper is the only *reachable* path to a GitHub write, not just the *sanctioned* one.

Do NOT suggest mounting `~/.ssh`, a `gh` token, or `$HOME` into the box to "make it work" — protected
writes go through the doorkeeper. For private-repo reads, prefer a short-lived scoped token over
mounting personal SSH keys.
