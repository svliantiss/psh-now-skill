#!/usr/bin/env sh
# psh.now command — the first thing an agent should try when a human says
# "use psh now", "ask me first", or anything else that means "check with me".
#
#   psh                        one offline screen: what psh.now is, where it
#                              lives here, and the next command to run
#   psh status                 pending requests + host health
#   psh doctor                 connectivity, credentials, stale artifacts
#   psh ask "<title>" "<msg>"  ask the human (blocks until they answer)
#   psh setup [--join <url>]   mint a workspace, or attach to a channel
#   psh help                   this text
#
# Bare `psh` deliberately makes no network call: it must answer instantly.
# `psh doctor` is the one that talks to the host.
set -eu

SKILL="${PSH_SKILL_DIR:-}"
if [ -z "$SKILL" ]; then
  # Follow symlinks without relying on `readlink -f` (absent on macOS).
  target="$0"
  while [ -L "$target" ]; do
    link="$(readlink "$target")"
    case "$link" in
      /*) target="$link" ;;
      *) target="$(dirname "$target")/$link" ;;
    esac
  done
  SKILL="$(cd "$(dirname "$target")/.." && pwd)"
fi
# A project-local copy describes this project better than the machine-wide one
# the shim points at, so prefer it when this directory has one.
proj_check="$PWD"
while :; do
  if [ -f "$proj_check/.agents/skills/psh-now/scripts/psh.sh" ]; then
    SKILL="$proj_check/.agents/skills/psh-now"
    break
  fi
  [ "$proj_check" = "/" ] && break
  [ "$proj_check" = "$HOME" ] && break
  parent="$(dirname "$proj_check")"
  [ "$parent" = "$proj_check" ] && break
  proj_check="$parent"
done
unset proj_check
SCRIPTS="$SKILL/scripts"

# Where this workspace keeps its keys: nearest .psh at or above PWD.
psh_dir() {
  if [ -n "${PSH_HOME:-}" ]; then printf '%s' "$PSH_HOME"; return; fi
  dir="$PWD"
  while :; do
    [ -d "$dir/.psh" ] && { printf '%s' "$dir/.psh"; return; }
    [ "$dir" = "/" ] && break
    parent="$(dirname "$dir")"
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done
  printf '%s' "$PWD/.psh"
}
DIR="$(psh_dir)"
KEYS="$DIR/keys.json"
GLOBAL="$HOME/.psh"

field() {
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}
mask() {
  case "$1" in
    "") printf '%s' "—" ;;
    *) printf '%s' "$(printf '%s' "$1" | cut -c1-13)…" ;;
  esac
}
# Read a field from the workspace keys, falling back to the machine-global copy.
get() {
  v=""
  [ -f "$KEYS" ] && v="$(field "$1" <"$KEYS")"
  if [ -z "$v" ] && [ -f "$GLOBAL/keys.json" ] && [ "$KEYS" != "$GLOBAL/keys.json" ]; then
    v="$(field "$1" <"$GLOBAL/keys.json")"
  fi
  printf '%s' "$v"
}

HOST="${PSH_BASE_URL:-$(get host)}"
[ -n "$HOST" ] || HOST="$(cat "$SKILL/.host" 2>/dev/null || printf 'https://psh.abslm.nl')"
HOST="${HOST:-https://psh.abslm.nl}"

warn_stale() {
  # A symlink whose target is gone is worse than nothing: it says "installed"
  # and then fails. Say so, in the one place an agent actually looks.
  for dir in \
    "$GLOBAL/skills/psh-now" \
    "$HOME/.agents/skills/psh-now" \
    "$HOME/.claude/skills/psh-now" \
    "$HOME/.hermes/skills/psh-now" \
    "$HOME/.trae/skills/psh-now" \
    "$HOME/.cursor/skills/psh-now" \
    "$HOME/.config/opencode/skills/psh-now"; do
    if [ -L "$dir" ] && [ ! -e "$dir" ]; then
      printf '  stale        dangling symlink: %s (target is gone)\n' "$dir"
    fi
  done
  # A global CLI config for a different workspace than the global keys means one
  # of them is out of date — the classic "doctor reports a deleted workspace".
  if [ -f "$GLOBAL/config.json" ] && [ -f "$GLOBAL/keys.json" ]; then
    cw="$(field workspaceId <"$GLOBAL/config.json")"
    kw="$(field workspaceId <"$GLOBAL/keys.json")"
    if [ -n "$cw" ] && [ -n "$kw" ] && [ "$cw" != "$kw" ]; then
      printf '  stale        %s/config.json names workspace %s, its keys.json names %s\n' "$GLOBAL" "$cw" "$kw"
      printf '               (re-run setup.sh in the project you want it to point at)\n'
    fi
  fi
  if [ ! -f "$KEYS" ]; then
    printf '  no keys      nothing set up in this project yet — run: psh setup\n'
  fi
}

breadcrumb() {
  ws="$(get workspaceId)"
  printf 'psh.now — ask a human before you act (approval in one tap)\n\n'
  printf '  what it is   you POST a short title + message; the human taps Approve or Deny\n'
  printf '  host         %s\n' "$HOST"
  printf '  skill        %s\n' "$SKILL"
  printf '  keys         %s%s\n' "$KEYS" "$([ -f "$KEYS" ] || printf ' (not created yet)')"
  [ -n "$ws" ] && printf '  workspace    %s\n' "$ws"
  [ -n "$ws" ] || printf '  workspace    (none yet — run: psh setup)\n'
  printf '  account key  %s   (dashboard sign-in; keep out of agent context)\n' "$(mask "$(get userKey)")"
  printf '  agent key    %s   (what the agent sends as x-psh-key)\n' "$(mask "$(get channelKey)")"
  warn_stale
  printf '\n  ask now      psh ask "Deploy?" "Push the new build to production."\n'
  printf '  full state   psh doctor\n'
  printf '  attach more  dashboard → the channel card → "Copy prompt for agent"\n'
  printf '  install      curl -fsSL %s/install.sh | sh\n' "$HOST"
  printf '\n  Never start a second account for a human who already has one. If a connect\n'
  printf '  link is dead, say so in one line and ask for a current one.\n'
}

case "${1:-}" in
  "" | status)
    [ -n "${1:-}" ] || { breadcrumb; exit 0; }
    exec sh "$SCRIPTS/status.sh" "$@"
    ;;
  doctor) exec sh "$SCRIPTS/status.sh" --doctor ;;
  ask) shift; exec sh "$SCRIPTS/ask.sh" "$@" ;;
  setup) shift; exec sh "$SCRIPTS/setup.sh" "$@" ;;
  uninstall) shift; exec sh "$SCRIPTS/setup.sh" --uninstall "$@" ;;
  help | --help | -h)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "psh.now: unknown command: $1" >&2
    echo "psh.now: try: psh          (what this is, where it lives)" >&2
    echo "psh.now:      psh status | psh doctor | psh ask \"title\" \"message\"" >&2
    exit 2
    ;;
esac
