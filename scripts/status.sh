#!/usr/bin/env sh
# psh.now — is the install healthy, reachable, and authenticated?
#
#   ./scripts/status.sh            pending requests + plan/usage
#   ./scripts/status.sh --doctor   the above, plus where everything lives and
#                                  anything stale (dangling links, dead configs)
#   ./scripts/status.sh --help
#
# Exit codes:
#   0  ok (host reachable + key accepted)
#   1  not set up (no keys yet — run ./scripts/setup.sh)
#   2  host unreachable
#   3  auth rejected (the stored key is dead or revoked)
#
# Prints progress on stderr and a machine-readable block `psh_status.*` on the
# last lines so agents can parse the same way they parse `psh_result.*`.
set -eu

DOCTOR=0
for arg in "$@"; do
  case "$arg" in
    --doctor) DOCTOR=1 ;;
    --help | -h)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Same lookup chain as ask.sh: $PSH_HOME, then nearest ./.psh walking up, then
# the legacy machine-global ~/.psh. Never climbs past $HOME.
resolve_psh_dir() {
  if [ -n "${PSH_HOME:-}" ]; then printf '%s' "$PSH_HOME"; return; fi
  dir="$PWD"
  while :; do
    [ -d "$dir/.psh" ] && { printf '%s' "$dir/.psh"; return; }
    [ "$dir" = "/" ] && break
    [ "$dir" = "$HOME" ] && break
    dir="$(dirname "$dir")"
  done
  [ -d "$HOME/.psh" ] && { printf '%s' "$HOME/.psh"; return; }
  printf '%s' "$PWD/.psh"
}
PSH_DIR="$(resolve_psh_dir)"
KEYS="$PSH_DIR/keys.json"
HOST="${PSH_BASE_URL:-$(cat "$PSH_DIR/host" 2>/dev/null || cat "$SKILL_DIR/host" 2>/dev/null || cat "$SKILL_DIR/.host" 2>/dev/null || true)}"
HOST="${HOST:-https://psh.abslm.nl}"

field() {
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

mask() {
  case "$1" in
    ""|"—") printf '%s' "$1" ;;
    *)      printf '%s…%s' "$(printf '%s' "$1" | cut -c1-11)" "$(printf '%s' "$1" | rev | cut -c1-4 | rev)" ;;
  esac
}

# Everything an agent (or a human) needs to understand this install, plus any
# artifact that lies about it. Cheap, local, no network.
diagnose() {
  echo "psh.diag.skill=$SKILL_DIR"
  echo "psh.diag.keys=$KEYS"
  echo "psh.diag.cwd=$PWD"
  [ -f "$KEYS" ] || echo "psh.diag.keys_state=missing"
  ws="$(field workspaceId <"$KEYS" 2>/dev/null || true)"
  [ -n "$ws" ] || ws="$(field workspaceId <"$HOME/.psh/keys.json" 2>/dev/null || true)"
  if [ -n "$ws" ]; then
    echo "psh.diag.workspace=$ws"
    if [ -f "$HOME/.psh/config.json" ]; then
      cw="$(field workspaceId <"$HOME/.psh/config.json")"
      if [ -n "$cw" ] && [ "$cw" != "$ws" ]; then
        echo "psh.diag.stale=~/.psh/config.json points at workspace $cw, not $ws"
      fi
    fi
  fi
  for dir in \
    "$HOME/.agents/skills/psh-now" \
    "$HOME/.claude/skills/psh-now" \
    "$HOME/.hermes/skills/psh-now" \
    "$HOME/.trae/skills/psh-now" \
    "$HOME/.cursor/skills/psh-now" \
    "$HOME/.config/opencode/skills/psh-now"; do
    if [ -L "$dir" ] && [ ! -e "$dir" ]; then
      echo "psh.diag.stale=dangling symlink $dir"
    elif [ -e "$dir" ]; then
      echo "psh.diag.installed=$dir"
    fi
  done
  shim="$(command -v psh 2>/dev/null || true)"
  if [ -n "$shim" ] && ! grep -q "psh.now" "$shim" 2>/dev/null; then shim=""; fi
  if [ -z "$shim" ]; then
    for cand in "$HOME/.local/bin/psh" "$HOME/bin/psh" "$HOME/.bun/bin/psh" \
      /opt/homebrew/bin/psh /usr/local/bin/psh; do
      if [ -f "$cand" ] && grep -q "psh.now" "$cand" 2>/dev/null; then shim="$cand"; break; fi
    done
  fi
  if [ -n "$shim" ]; then
    echo "psh.diag.shim=$shim"
  else
    echo "psh.diag.shim=none (no 'psh' command on PATH — install again to add one)"
  fi
}

# In doctor mode, always print the map — even on the failure paths below.
finish() {
  if [ "$DOCTOR" = 1 ]; then diagnose; fi
}

echo "psh.now: host $HOST" >&2

# 1) Reachability (no auth needed).
if ! curl -fsS -m 5 "$HOST/api/v1/health" >/dev/null 2>&1; then
  echo "psh.now: UNREACHABLE — $HOST did not answer /api/v1/health" >&2
  echo "psh_status.host=$HOST"
  echo "psh_status.auth=unreachable"
  finish
  exit 2
fi
echo "psh.now: reachable ✓" >&2

# 2) Key presence.
KEY="${PSH_API_KEY:-$(field channelKey <"$KEYS" 2>/dev/null || true)}"
[ -n "$KEY" ] || KEY="$(field apiKey <"$SKILL_DIR/.keys.json" 2>/dev/null || true)"
if [ -z "$KEY" ]; then
  echo "psh.now: NOT SET UP — no channel key in \$PSH_API_KEY or $KEYS" >&2
  echo "psh.now: run: sh \"$SKILL_DIR/scripts/setup.sh\"  (or setup.sh --join <link>)" >&2
  echo "psh_status.host=$HOST"
  echo "psh_status.auth=none"
  finish
  exit 1
fi
# Never echo the key itself: with PSH_API_KEY set this printed "(from envpsh_agent_…)" — the
# raw key in a log, and an unreadable sentence (found 2026-10-17).
if [ -n "${PSH_API_KEY:-}" ]; then key_src="env (PSH_API_KEY)"; else key_src="$KEYS"; fi
echo "psh.now: key $(mask "$KEY") (from $key_src)" >&2

# 3) Auth + plan/usage. `me` is unauthenticated-misuse-safe to print; the key
#    itself never is.
usage="$(curl -sS -m 5 -H "x-psh-key: $KEY" "$HOST/api/v1/me" 2>&1)" || usage=""
if [ -z "$usage" ]; then
  echo "psh.now: AUTH REJECTED — the stored key is dead or revoked. Re-run setup.sh." >&2
  echo "psh_status.host=$HOST"
  echo "psh_status.auth=rejected"
  finish
  exit 3
fi
# A 401/403 body still prints JSON but not the expected workspace fields.
if ! printf '%s' "$usage" | grep -q '"workspace"'; then
  echo "psh.now: AUTH REJECTED — the stored key is dead or revoked. Re-run setup.sh." >&2
  [ -n "$usage" ] && printf '%s\n' "$usage" >&2
  echo "psh_status.host=$HOST"
  echo "psh_status.auth=rejected"
  finish
  exit 3
fi

EMAIL="$(printf '%s' "$usage" | field email)"
PLAN="$(printf '%s' "$usage" | field plan)"
CLAIMED="$(printf '%s' "$usage" | field claimed)"
# Integer fields need a numeric parse; `field` only matches quoted strings.
num() { printf '%s' "$usage" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n 1; }
ONLINE="$(num onlineDevices)"
PENDING="$(num pendingPrompts)"
TODAY="$(num requestsToday)"
LIMIT="$(num limit)"

echo "psh.now: auth ✓" >&2
echo "psh.now: account ${EMAIL:-anonymous}${CLAIMED:+ (claimed)}" >&2
echo "psh.now: plan $PLAN, ${TODAY:-0}/${LIMIT:-?} requests today, $ONLINE online devices, $PENDING pending" >&2
echo "psh_status.host=$HOST"
echo "psh_status.auth=ok"
echo "psh_status.plan=$PLAN"
echo "psh_status.usage=$TODAY/$LIMIT"
echo "psh_status.online_devices=$ONLINE"
echo "psh_status.pending=$PENDING"
finish
exit 0
