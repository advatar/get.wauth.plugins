#!/usr/bin/env bash
# wauth-secure-run — launch a coding agent (Codex / Claude Code) in a hardened container so the
# ONLY reachable path to a GitHub write is the WAUTH doorkeeper.
#
# The box carries NO ambient host credentials: no $HOME, no ~/.ssh, no gh token, no SSH-agent
# socket, no cloud creds. It holds only two things — the agent's COGNITION credential (OpenAI /
# Anthropic key) and the least-privilege WAUTH doorkeeper key. The GitHub App credential is NEVER
# in the box; it lives server-side in the doorkeeper. So the doorkeeper isn't merely the
# *sanctioned* path to a protected GitHub write — it's the only *reachable* one.
#
# THIS SCRIPT IS THE ENFORCEMENT (an OS/container boundary the agent cannot reconfigure). The
# wauth-github SKILL is only the bootstrap that steers the agent through the doorkeeper. A prompt-
# injected or hostile agent inside the box still cannot read ~/.ssh (it isn't mounted) or reach
# GitHub directly (no credential, egress constrained).
#
# Usage:
#   WAUTH_GITHUB_KEY=<agent-key> OPENAI_API_KEY=<key> ./run.sh /path/to/repo [--image wauth-agent-box] [-- <agent args>]
#
# Requires: docker (Docker Desktop / colima / Linux docker). On macOS the container runs inside
# Docker's Linux VM — a strong boundary. See ./README.md for the egress-allow-list hardening.
set -euo pipefail

IMAGE="${WAUTH_AGENT_IMAGE:-wauth-agent-box}"
DOORKEEPER_URL="${WAUTH_DOORKEEPER_URL:-https://wauth-github-doorkeeper-774308232885.europe-west2.run.app/mcp}"
REPO=""
PASSTHRU=()
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --) shift; PASSTHRU=("$@"); break ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) REPO="$1"; shift ;;
  esac
done

[ -n "$REPO" ] || { echo "error: pass the repo path, e.g. ./run.sh /path/to/repo" >&2; exit 2; }
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "error: repo path does not exist" >&2; exit 2; }
[ -d "$REPO/.git" ] || echo "warning: $REPO has no .git (mounting it anyway)" >&2

# The box needs the cognition credential + the least-privilege WAUTH key — and MUST NOT get a GitHub
# token (that only ever lives in the doorkeeper).
: "${WAUTH_GITHUB_KEY:?set WAUTH_GITHUB_KEY to the least-privilege doorkeeper agent key}"
if [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "error: set OPENAI_API_KEY (Codex) or ANTHROPIC_API_KEY (Claude Code) — the agent's cognition credential" >&2
  exit 2
fi

# Defensive: never mount the home dir itself or a known credential directory as the "repo".
case "$REPO" in
  "$HOME" | "$HOME"/.ssh* | "$HOME"/.config/gh* | "$HOME"/.aws* | "$HOME"/.gnupg* | "$HOME"/.config/gcloud*)
    echo "error: refusing to mount '$REPO' — it is or contains sensitive host paths" >&2; exit 2 ;;
esac

echo "▶ boxing the agent"
echo "    repo:       $REPO  (the only host path mounted)"
echo "    doorkeeper: $DOORKEEPER_URL  (only sanctioned + only reachable GitHub write path)"
echo "    NOT mounted: \$HOME, ~/.ssh, ~/.config/gh, the SSH-agent socket, cloud creds"
[ -n "${HTTPS_PROXY:-}" ] && echo "    egress proxy: $HTTPS_PROXY (allow-list it to the doorkeeper + model + registries)"

# --read-only rootfs + tmpfs home/tmp (throwaway), non-root, all caps dropped, no privilege
# escalation, pid/mem/cpu bounded. Only the repo is writable + persisted. Credentials are passed
# BY NAME (-e VAR) so their values are inherited from this env, never placed in the container argv.
exec docker run --rm -it \
  --user 1000:1000 \
  --workdir /workspace \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,size=512m \
  --tmpfs /home/coder:rw,nosuid,nodev,uid=1000,gid=1000,size=1g \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 512 \
  --memory 4g --cpus 2 \
  --env HOME=/home/coder \
  --env WAUTH_DOORKEEPER_URL="$DOORKEEPER_URL" \
  --env WAUTH_GITHUB_KEY \
  ${OPENAI_API_KEY:+--env OPENAI_API_KEY} \
  ${ANTHROPIC_API_KEY:+--env ANTHROPIC_API_KEY} \
  ${HTTPS_PROXY:+--env HTTPS_PROXY --env HTTP_PROXY="${HTTP_PROXY:-$HTTPS_PROXY}" --env NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"} \
  -v "$REPO:/workspace:rw" \
  "$IMAGE" "${PASSTHRU[@]}"
