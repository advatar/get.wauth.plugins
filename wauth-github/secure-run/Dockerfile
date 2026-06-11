# wauth-agent-box — minimal, non-root image for running a coding agent under wauth-secure-run.
# It bakes in NO credentials; the launcher (run.sh) injects the cognition key + the WAUTH key at
# runtime and provides a writable HOME as a tmpfs. There is deliberately no SSH client config and
# no GitHub auth here — protected GitHub writes go through the WAUTH doorkeeper, not a local key.
FROM node:20-slim

# git: clone/fetch/local commits over HTTPS (no SSH key needed). ripgrep: a common agent dependency.
# ca-certificates: TLS to the doorkeeper / model API / package registries.
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ripgrep ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

# Pick the agent CLI at build time. Verify the package name matches your agent version if it changes.
#   docker build --build-arg AGENT=codex  -t wauth-agent-box .     # OpenAI Codex CLI
#   docker build --build-arg AGENT=claude -t wauth-agent-box .     # Claude Code
ARG AGENT=codex
RUN set -eux; \
  case "$AGENT" in \
    codex)  npm install -g @openai/codex ;; \
    claude) npm install -g @anthropic-ai/claude-code ;; \
    none)   echo "no agent CLI baked; install one in a child image" ;; \
    *) echo "unknown AGENT=$AGENT (use codex|claude|none)" >&2; exit 1 ;; \
  esac

# Non-root. HOME is supplied as a writable tmpfs by the launcher (so the rootfs stays --read-only).
RUN useradd -m -u 1000 -s /bin/bash coder
USER 1000:1000
WORKDIR /workspace
ENV HOME=/home/coder \
    NODE_ENV=production

# Inside the box, add the WAUTH marketplace + the github plugin once, then run the agent:
#   codex plugin marketplace add advatar/get.wauth.plugins
#   codex plugin add wauth-github@wauth      # its .mcp.json points at $WAUTH_DOORKEEPER_URL
#   codex                                    # WAUTH_GITHUB_KEY is already in the env
CMD ["bash"]
