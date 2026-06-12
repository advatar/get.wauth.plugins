#!/usr/bin/env bash
# Adversarial test harness for the Tier A Seatbelt box (wauth-agent.sb + secure-run-seatbelt.sh).
#
# It runs a battery of "hostile agent" probes INSIDE the sandbox and asserts each is contained:
#   - host credential stores are UNREADABLE (including an unenumerated decoy secret),
#   - persistence-write vectors are DENIED,
#   - cloud CLIs cannot exfiltrate platform secrets,
#   - and normal work (workspace r/w, toolchain, system reads) still functions.
#
# Rigour: read-probes are only counted when the target is actually readable on the HOST first
# (so "contained" means the sandbox blocked a real, readable file — not that the file was absent).
# Write-probes use throwaway CANARY filenames under the denied dirs, so a (hypothetical) escape
# cannot clobber a real dotfile, and any leaked canary is cleaned up.
#
# Exit 0 = every probe behaved as expected; non-zero = a leak or escape (or over-blocking).
set -uo pipefail
[ "$(uname -s)" = "Darwin" ] || { echo "Tier A is macOS-only (sandbox-exec)."; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"
LAUNCH="$HERE/secure-run-seatbelt.sh"
[ -x "$LAUNCH" ] || { echo "launcher not found/executable: $LAUNCH"; exit 2; }

WS="$(cd "$(mktemp -d /tmp/wauth-box-test.XXXX)" && pwd -P)"
echo "decoy-workspace-file" > "$WS/work.txt"
DECOY="$HOME/.wauth-box-test-secret.$$"; echo "TOPSECRET-$$" > "$DECOY"   # unenumerated $HOME secret
NODE="$(command -v node || true)"; GCLOUD="$(command -v gcloud || true)"
export WAUTH_GITHUB_KEY="test-dummy-key" OPENAI_API_KEY="sk-test-dummy"

pass=0; fail=0; na=0
# run a command inside the box; returns the command's own exit code (launcher exec's it)
box() { "$LAUNCH" "$WS" -- /bin/bash -c "$1" >/dev/null 2>&1; }
first_file() { find "$1" -maxdepth 2 -type f 2>/dev/null | head -1; }

deny_read() { # label, host-path (file). PASS if readable-on-host but DENIED in box.
  local label="$1" path="$2"
  [ -n "$path" ] && [ -r "$path" ] || { echo "  – n/a (not present on host): $label"; na=$((na+1)); return; }
  if box "cat '$path'"; then echo "  ✗ LEAK: $label readable inside the box ($path)"; fail=$((fail+1));
  else echo "  ✓ denied:  $label"; pass=$((pass+1)); fi
}
deny_write() { # label, canary-path under a denied dir
  local label="$1" path="$2"
  if box "echo pwned > '$path'"; then echo "  ✗ LEAK: $label write succeeded ($path)"; fail=$((fail+1)); rm -f "$path" 2>/dev/null;
  else echo "  ✓ denied:  $label"; pass=$((pass+1)); fi
}
allow() { # label, command  — PASS if it SUCCEEDS in the box (functionality not over-blocked)
  if box "$2"; then echo "  ✓ works:   $1"; pass=$((pass+1));
  else echo "  ✗ OVER-BLOCKED: $1"; fail=$((fail+1)); fi
}

echo "▶ Tier A Seatbelt box — adversarial probe battery"
echo "  workspace: $WS"
echo ""
echo "── host credential reads must be DENIED ──"
deny_read "~/.ssh private material"      "$(first_file "$HOME/.ssh")"
deny_read "~/.aws credentials"           "$HOME/.aws/credentials"
deny_read "gh CLI token"                 "$HOME/.config/gh/hosts.yml"
deny_read "gcloud credentials"           "$(first_file "$HOME/.config/gcloud")"
deny_read "login Keychain"               "$(first_file "$HOME/Library/Keychains")"
deny_read "UNENUMERATED \$HOME secret"   "$DECOY"
echo ""
echo "── persistence writes must be DENIED ──"
deny_write "plant ~/.ssh authorized_key" "$HOME/.ssh/.wauth-box-canary.$$"
deny_write "drop a LaunchAgent"          "$HOME/Library/LaunchAgents/.wauth-box-canary.$$.plist"
echo ""
echo "── cloud-CLI secret exfiltration must be DENIED ──"
if [ -n "$GCLOUD" ]; then
  if box "'$GCLOUD' secrets versions access latest --secret=wauth-box-test 2>&1"; then
    echo "  ✗ LEAK: gcloud ran/authed inside the box"; fail=$((fail+1));
  else echo "  ✓ denied:  gcloud secrets access (can't exec/auth in the box)"; pass=$((pass+1)); fi
else echo "  – n/a (gcloud not installed)"; na=$((na+1)); fi
echo ""
echo "── normal work must still FUNCTION ──"
allow "read the workspace"               "cat '$WS/work.txt'"
allow "write the workspace"              "echo ok > '$WS/out.txt'"
allow "read system files (/etc/hosts)"   "cat /etc/hosts"
[ -n "$NODE" ] && allow "run the node toolchain" "'$NODE' -e 'process.exit(0)'" || { echo "  – n/a (node not found)"; na=$((na+1)); }

rm -f "$DECOY"; rm -rf "$WS"
echo ""
echo "RESULT: $pass passed, $fail failed, $na n/a"
[ "$fail" -eq 0 ] && echo "✅ box CONTAINED every probe" || echo "❌ box LEAKED — see ✗ lines above"
[ "$fail" -eq 0 ]
