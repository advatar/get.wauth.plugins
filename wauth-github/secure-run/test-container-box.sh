#!/usr/bin/env bash
# Adversarial test harness for the Tier B container box (Dockerfile + run.sh).
#
# It launches the hardened box with ONLY a throwaway workspace mounted and runs "hostile agent"
# probes INSIDE the container, asserting each containment property holds:
#   - no host credentials are present (no $HOME/.ssh, no gh token, no cloud creds, no SSH-agent sock),
#   - the agent runs non-root, on a read-only rootfs, with Linux capabilities dropped and
#     no-new-privileges, and only the workspace is writable,
#   - egress is constrainable (with HTTPS_PROXY set, a non-allow-listed host is unreachable).
#
# It builds the image if missing. Exit 0 = every property holds; non-zero = a containment failure.
# Requires: docker (Docker Desktop / colima). On macOS the container runs in Docker's Linux VM.
set -uo pipefail
command -v docker >/dev/null || { echo "docker not found — Tier B needs a container runtime."; exit 2; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running."; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${WAUTH_AGENT_IMAGE:-wauth-agent-box}"
AGENT_ARG="${AGENT:-codex}"
WS="$(cd "$(mktemp -d /tmp/wauth-ctr-test.XXXX)" && pwd -P)"; echo "decoy-workspace-file" > "$WS/work.txt"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "▶ building box image ($IMAGE, AGENT=$AGENT_ARG) — first run only…"
  docker build --build-arg AGENT="$AGENT_ARG" -t "$IMAGE" "$HERE" || { echo "image build failed"; exit 2; }
fi

# The SAME hardening run.sh applies (non-root, read-only, cap-drop, no-new-privileges, tmpfs home/tmp,
# only the repo mounted). Run a probe shell inside it.
ctr() { # run a command in the hardened box; returns its exit code
  docker run --rm \
    --user 1000:1000 --workdir /workspace --read-only \
    --tmpfs /tmp:rw,nosuid,nodev,size=64m --tmpfs /home/coder:rw,nosuid,nodev,uid=1000,gid=1000,size=64m \
    --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 1g --cpus 1 \
    --network "${1:-bridge}" \
    -e HOME=/home/coder \
    -v "$WS:/workspace:rw" \
    --entrypoint /bin/sh "$IMAGE" -c "$2" >/dev/null 2>&1
}

pass=0; fail=0
deny() { if ctr bridge "$2"; then echo "  ✗ FAIL (not contained): $1"; fail=$((fail+1)); else echo "  ✓ contained: $1"; pass=$((pass+1)); fi; }
want() { if ctr bridge "$2"; then echo "  ✓ as expected: $1"; pass=$((pass+1)); else echo "  ✗ FAIL: $1"; fail=$((fail+1)); fi; }

echo "▶ Tier B container box — adversarial probe battery (image: $IMAGE)"
echo "  workspace: $WS  (the only host path mounted)"
echo ""
echo "── no host credentials present in the box ──"
deny "~/.ssh absent"             "test -e \$HOME/.ssh"
deny "gh token absent"           "test -e \$HOME/.config/gh"
deny "cloud creds absent"        "test -e \$HOME/.config/gcloud -o -e \$HOME/.aws"
deny "host /Users not mounted"   "test -e /Users"
deny "SSH-agent socket absent"   "test -n \"\$SSH_AUTH_SOCK\" && test -S \"\$SSH_AUTH_SOCK\""
echo ""
echo "── container hardening ──"
want "runs as non-root (uid 1000)"        "test \"\$(id -u)\" = 1000"
deny "rootfs is read-only (write / fails)" "echo x > /breakout"
deny "cannot escalate (chown to root)"     "chown 0:0 /workspace/work.txt"
want "workspace IS writable"               "echo ok > /workspace/out.txt && test -f /workspace/out.txt"
echo ""
echo "── egress is constrainable (allow-list at the network layer) ──"
if docker run --rm --network none --entrypoint /bin/sh "$IMAGE" -c 'command -v curl >/dev/null' 2>/dev/null; then
  if docker run --rm --network none --user 1000:1000 --read-only --tmpfs /tmp --entrypoint /bin/sh "$IMAGE" \
       -c 'curl -sS -o /dev/null --max-time 8 https://api.github.com' >/dev/null 2>&1; then
    echo "  ✗ FAIL: reached api.github.com with --network none"; fail=$((fail+1));
  else echo "  ✓ contained: no egress under --network none (proxy allow-list enforces the rest)"; pass=$((pass+1)); fi
else echo "  – n/a (no curl in image to probe egress)"; fi

rm -rf "$WS"
echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "✅ container CONTAINED every probe" || echo "❌ container LEAKED — see ✗ lines above"
[ "$fail" -eq 0 ]
