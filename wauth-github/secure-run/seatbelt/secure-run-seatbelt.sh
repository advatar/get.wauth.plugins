#!/usr/bin/env bash
# secure-run-seatbelt — WAUTH secure-run Tier A (macOS, no Docker).
#
# Run a coding agent (Codex / Claude Code) directly on macOS inside an Apple Seatbelt sandbox that
# makes the host's personal credential stores UNREADABLE: ~/.ssh, the gh token (~/.config/gh),
# ~/.aws, ~/.gnupg, ~/.kube, cloud creds, Keychain files — everything under $HOME except the
# workspace and the agent's own dirs. A prompt-injected or hostile agent therefore cannot exfiltrate
# the ambient keys that would let it bypass the WAUTH doorkeeper.
#
# This is the frictionless tier — no container runtime, the agent runs on your real machine with
# your real toolchain. The walls are a kernel sandbox profile (wauth-agent.sb), not a VM.
#   Tier A (this): Seatbelt, macOS only, semi-trusted agent. Read-protects secrets, blocks key-planting.
#   Tier B (../run.sh): hardened container, any OS, hostile-agent case. Secret simply isn't mounted.
#   Tier C (the doorkeeper): the protected credential is never on the box at all.
# The doorkeeper still decides tiers and demands the human passkey/liveness step-up; Tier A just
# removes the agent's ability to read ambient keys and go around it.
#
# The cognition credential (OPENAI_API_KEY / ANTHROPIC_API_KEY) and the least-privilege
# WAUTH_GITHUB_KEY pass through by environment. The GitHub App credential is NEVER here — it lives
# server-side in the doorkeeper.
#
# Upstream credit: default-deny-read model after neko-kai/claude-code-sandbox; egress-proxy model
# after michaelneale/agent-seatbelt-sandbox.
#
# Usage:
#   WAUTH_GITHUB_KEY=<agent-key> OPENAI_API_KEY=<key> \
#     ./secure-run-seatbelt.sh /path/to/repo -- codex
#   (no command after -- → an interactive shell inside the sandbox)
#
# Requires: macOS (sandbox-exec). On non-macOS, use Tier B (../run.sh).
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || { echo "error: Tier A is macOS-only (sandbox-exec). Use Tier B: ../run.sh" >&2; exit 2; }
command -v sandbox-exec >/dev/null || { echo "error: sandbox-exec not found" >&2; exit 2; }

PROFILE="$(cd "$(dirname "$0")" && pwd)/wauth-agent.sb"
DOORKEEPER_URL="${WAUTH_DOORKEEPER_URL:-https://wauth-github-doorkeeper-774308232885.europe-west2.run.app/mcp}"
REPO=""
CMD=()
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; CMD=("$@"); break ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) REPO="$1"; shift ;;
  esac
done

[ -n "$REPO" ] || { echo "error: pass the repo/workspace path, e.g. ./secure-run-seatbelt.sh /path/to/repo -- codex" >&2; exit 2; }
# Seatbelt 'subpath' matches RESOLVED paths — resolve symlinks (e.g. /tmp -> /private/tmp) up front.
WORKSPACE="$(cd "$REPO" 2>/dev/null && pwd -P)" || { echo "error: workspace path does not exist" >&2; exit 2; }

# Never let the "workspace" be the home dir itself or a credential dir (would re-allow reads of it).
case "$WORKSPACE" in
  "$HOME" | "$HOME"/.ssh* | "$HOME"/.config/gh* | "$HOME"/.aws* | "$HOME"/.gnupg* | "$HOME"/.config/gcloud* | "$HOME"/.kube* | "$HOME"/Library/Keychains*)
    echo "error: refusing to use '$WORKSPACE' as the workspace — it is or contains sensitive host paths" >&2; exit 2 ;;
esac

# The box needs the cognition credential + the least-privilege WAUTH key — never a GitHub token.
: "${WAUTH_GITHUB_KEY:?set WAUTH_GITHUB_KEY to the least-privilege doorkeeper agent key}"
if [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "error: set OPENAI_API_KEY (Codex) or ANTHROPIC_API_KEY (Claude Code) — the agent's cognition credential" >&2
  exit 2
fi

# Default command: an interactive shell inside the sandbox.
[ "${#CMD[@]}" -gt 0 ] || CMD=("${SHELL:-/bin/bash}" -i)

echo "▶ boxing the agent (Tier A — macOS Seatbelt, no Docker)"
echo "    workspace:  $WORKSPACE  (the only home-dir path the agent can read/write freely)"
echo "    doorkeeper: $DOORKEEPER_URL  (only sanctioned + only reachable GitHub write path)"
echo "    UNREADABLE: ~/.ssh, ~/.config/gh, ~/.aws, ~/.gnupg, ~/.kube, Keychains — all of \$HOME except the workspace + the agent's own dirs"
[ -n "${HTTPS_PROXY:-}" ] && echo "    egress proxy: $HTTPS_PROXY (allow-list it to the doorkeeper + model + registries)"

export WAUTH_DOORKEEPER_URL="$DOORKEEPER_URL"
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"

# Run with cwd = the workspace (node and friends need a readable cwd). Credentials stay in the
# environment (sandbox-exec inherits it) — never placed on the command line.
cd "$WORKSPACE"
exec sandbox-exec \
  -D HOME="$HOME" \
  -D WORKSPACE="$WORKSPACE" \
  -f "$PROFILE" \
  "${CMD[@]}"
