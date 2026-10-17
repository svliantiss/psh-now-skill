#!/usr/bin/env sh
# psh.now installer — the default way to install, and it installs all of it.
#
#   curl -fsSL https://psh.abslm.nl/install.sh | sh
#
# That one command leaves FOUR pieces in place:
#   1. the skill, machine-wide   ~/.agents/skills/psh-now   (every project sees it)
#   2. the psh command (CLI)     ~/.local/bin/psh          (on PATH, works anywhere)
#   3. this project's keys       <project>/.psh/keys.json  (the agent asks with these)
#   4. the machine account record ~/.psh/keys.json         (keeps every project on ONE account)
#
# The CLI and the skill are equally important: the CLI is what an agent runs when it
# hears "use psh now", and the skill is what tells it to. Neither works alone.
#
# Inside a sandbox that only allows writes to the workspace, pieces 1, 2 and 4 cannot be
# written. That is not a finished install and the script says so — but it is not a reason
# for an agent to ask for blanket filesystem access because a downloaded page said to. The
# project-local copy is complete for the folder it is in:
#   curl -fsSL <host>/install.sh | PSH_SKILL_DIR="$PWD/.agents/skills/psh-now" sh
# and the machine-wide pieces are ONE line the human runs in their own terminal:
#   cd <that folder> && curl -fsSL <host>/install.sh | sh
# Prefer the auditable path if you have npm (installs from a public repo and checks the
# artifact digest):  npx skills add psh-now/skill --skill psh-now -g -y
# Or audit this file first instead of piping blind:
#   curl -fsSL https://psh.abslm.nl/install.sh -o install.sh && ${EDITOR:-vi} install.sh && sh install.sh
#
# Overrides:
#   PSH_HOST        host to download skill.md from (default: this host)
#   PSH_SKILL_DIR   install directory (default: ~/.agents/skills/psh-now)
#   PSH_LOCAL=1     install into the project instead (same as --local)
#   PSH_NO_GLOBAL=1 skip the machine-wide copy
#   PSH_NO_SHIM=1   skip the `psh` command on PATH
#   PSH_BIN_DIR     where the `psh` command goes (default: first writable PATH dir)
#
# A workspace-local install (`PSH_SKILL_DIR=...`, `PSH_LOCAL=1`, or the automatic
# fallback when ~/.agents is unwritable) is the FALLBACK, not the default: it still
# makes this project complete and still tries the machine-wide copy.
set -eu

HOST="${PSH_HOST:-https://psh.abslm.nl}"
DEST="${PSH_SKILL_DIR:-}"

command -v curl >/dev/null 2>&1 || {
  echo "psh.now: curl is required" >&2
  exit 1
}

# The project root: the nearest directory with a .git, else the current one. A
# harness looks for project skills at <root>/.agents/skills, so mirror that.
project_root() {
  dir="$(pwd)"
  while :; do
    [ -d "$dir/.git" ] && break
    parent="$(dirname "$dir")"
    [ "$parent" = "$dir" ] && { dir="$(pwd)"; break; }
    dir="$parent"
  done
  printf '%s' "$dir"
}

LOCAL="${PSH_LOCAL:-0}"
for arg in "$@"; do
  case "$arg" in
    --local | -l) LOCAL=1 ;;
  esac
done
[ "$LOCAL" = 1 ] && [ -z "$DEST" ] && DEST="$(project_root)/.agents/skills/psh-now"
[ -z "$DEST" ] && DEST="$HOME/.agents/skills/psh-now"

if ! mkdir -p "$DEST/scripts" 2>/dev/null; then
  FALLBACK="$(project_root)/.agents/skills/psh-now"
  if [ "$DEST" != "$FALLBACK" ] && mkdir -p "$FALLBACK/scripts" 2>/dev/null; then
    echo "psh.now: $DEST is not writable here — installing into the project instead" >&2
    DEST="$FALLBACK"
  else
    echo "psh.now: cannot write $DEST" >&2
    exit 1
  fi
fi
echo "psh.now: downloading skill from $HOST/skill.md"
curl -fsSL "$HOST/skill.md" -o "$DEST/SKILL.md"
curl -fsSL "$HOST/ask.sh" -o "$DEST/scripts/ask.sh"
curl -fsSL "$HOST/setup.sh" -o "$DEST/scripts/setup.sh"
# The health check the skill tells the agent to run before and after asking.
curl -fsSL "$HOST/status.sh" -o "$DEST/scripts/status.sh"
# The `psh` command itself: the cold-start answer an agent finds first.
curl -fsSL "$HOST/psh.sh" -o "$DEST/scripts/psh.sh"
chmod +x "$DEST/scripts/ask.sh" "$DEST/scripts/setup.sh" "$DEST/scripts/status.sh" "$DEST/scripts/psh.sh"
# Bake the host in so the agent needs no configuration.
printf '%s\n' "$HOST" > "$DEST/.host"

# Machine-wide copy. This is the one that reaches *other* projects: a harness
# lists ~/.agents/skills in every session, so without it the next workspace has
# to rediscover psh.now from nothing (that cost one session 47 tool calls).
GLOBAL_DEST="$HOME/.agents/skills/psh-now"
if [ "${PSH_NO_GLOBAL:-0}" != 1 ] && [ "$DEST" != "$GLOBAL_DEST" ]; then
  if [ -z "$DEST" ] || [ ! -f "$DEST/SKILL.md" ]; then
    # Same trap as in setup.sh: an unresolved source turns this into
    # `cp -R //. <dest>`, which copies the filesystem instead of the skill.
    echo "psh.now: machine-wide skill skipped — the downloaded skill folder is missing" >&2
  el  if mkdir -p "$GLOBAL_DEST" 2>/dev/null; then
    # Real files, not a symlink: a link to a project dir dangles the moment the
    # project is deleted, and a dangling "installed" skill is worse than none.
    cp -R "$DEST/." "$GLOBAL_DEST/" 2>/dev/null || true
    echo "psh.now: also installed machine-wide: $GLOBAL_DEST"
    echo "psh.now: (that copy is what shows psh-now in every new session's skill list)"
  else
    # Piece 1 refused. The workspace install stands, but this is NOT a finished
    # install — the block printed at the end says exactly what to ask for.
    MW_MISSING=1
    echo "psh.now: machine-wide skill refused — cannot write $GLOBAL_DEST" >&2
  fi
fi

# Best-effort symlinks for harnesses that keep their own skills directory.
# Pi (and any Agent Skills host) already reads ~/.agents/skills directly.
# Point them at a copy that outlives this project when we managed to make one.
LINK_TARGET="$DEST"
if [ -d "$GLOBAL_DEST" ] && [ "$DEST" != "$GLOBAL_DEST" ]; then
  LINK_TARGET="$GLOBAL_DEST"
fi
for dir in \
  "$HOME/.claude/skills" \
  "$HOME/.hermes/skills" \
  "$HOME/.trae/skills" \
  "$HOME/.cursor/skills" \
  "$HOME/.config/opencode/skills"; do
  [ -d "$dir" ] || continue
  # Best-effort by design: a sandbox that blocks writes outside the workspace
  # must not abort the install before setup.sh has minted the keys. (It did —
  # `set -e` plus a denied symlink was enough to kill the whole run.)
  ln -sfn "$LINK_TARGET" "$dir/psh-now" 2>/dev/null || true
done

# A `psh` command on PATH: the first thing an agent tries, and the cheapest
# possible answer to "what is psh now and where is it installed here".
install_shim() {
  shim_dir=""
  if [ -n "${PSH_BIN_DIR:-}" ]; then
    mkdir -p "$PSH_BIN_DIR" 2>/dev/null || true
    shim_dir="$PSH_BIN_DIR"
  else
    # Prefer a directory that is already on PATH — a shim nobody can find is
    # not worth writing. User-owned dirs first; never hijack a foreign `psh`.
    for cand in "$HOME/.local/bin" "$HOME/bin" "$HOME/.bun/bin" \
      /opt/homebrew/bin /usr/local/bin; do
      case ":$PATH:" in *":$cand:"*) ;; *) continue ;; esac
      [ -d "$cand" ] && [ -w "$cand" ] || continue
      if [ -e "$cand/psh" ] && ! grep -q "psh.now" "$cand/psh" 2>/dev/null; then
        continue
      fi
      shim_dir="$cand"
      break
    done
    if [ -z "$shim_dir" ]; then
      # Nothing usable on PATH: still install, then tell the human the one line.
      shim_dir="$HOME/.local/bin"
      if ! mkdir -p "$shim_dir" 2>/dev/null; then SHIM_MISSING=1; return 0; fi
      SHIM_NEEDS_PATH=1
    fi
  fi
  [ -n "$shim_dir" ] || return 0
  if {
    printf '#!/usr/bin/env sh\n'
    printf '# psh.now launcher — one offline screen: what this is, where it lives.\n'
    printf 'PSH_SKILL_DIR="%s"\n' "$SHIM_TARGET"
    printf 'export PSH_SKILL_DIR\n'
    printf 'exec sh "%s/scripts/psh.sh" "$@"\n' "$SHIM_TARGET"
  } >"$shim_dir/psh" 2>/dev/null; then
    chmod +x "$shim_dir/psh" 2>/dev/null || true
    SHIM="$shim_dir/psh"
  else
    SHIM_MISSING=1
  fi
}
SHIM=""
SHIM_NEEDS_PATH=0
MW_MISSING=0     # piece 1 (machine-wide skill) refused
SHIM_MISSING=0   # piece 2 (the `psh` CLI) refused
SHIM_TARGET="$LINK_TARGET"
if [ "${PSH_NO_SHIM:-0}" != 1 ]; then
  install_shim || true
fi

# Mint once: a user key (app login) + a channel key (the agent's key).
# Keys are saved to <project>/.psh/keys.json (or $PSH_HOME), never inside the
# skill directory — reinstalling the skill never wipes them.
#
# PSH_NO_GLOBAL: this script already did the machine-wide work above, and setup.sh does it
# on the package route (where install.sh never runs). Without this the same line prints twice.
PSH_NO_GLOBAL=1 sh "$DEST/scripts/setup.sh"

echo "psh.now: installed to $DEST"
if [ -n "$SHIM" ]; then
  # Remember where it went so --uninstall can take it away again.
  printf '%s\n' "$SHIM" > "$DEST/.psh-bin" 2>/dev/null || true
  if [ "$DEST" != "$GLOBAL_DEST" ] && [ -d "$GLOBAL_DEST" ]; then
    printf '%s\n' "$SHIM" > "$GLOBAL_DEST/.psh-bin" 2>/dev/null || true
  fi
  echo "psh.now: command installed: $SHIM"
  if [ "$SHIM_NEEDS_PATH" = 1 ]; then
    echo "psh.now: add it to PATH:  export PATH=\"$(dirname "$SHIM"):\$PATH\""
  fi
  echo "psh.now: next time, just run: psh"
else
  # Do not claim there is no command when this folder has one: setup.sh installs the project
  # shim even when nothing outside the workspace was writable (caught in the sandbox lane,
  # 2026-10-17 — the line contradicted the report printed right above it).
  proj_root="$(dirname "$(dirname "$(dirname "$DEST")")")"
  if [ "$DEST" != "$GLOBAL_DEST" ] && [ -x "$proj_root/.psh/bin/psh" ]; then
    echo "psh.now: no machine-wide \`psh\` on PATH — this folder's own command is: $proj_root/.psh/bin/psh" >&2
  else
    echo "psh.now: no \`psh\` command installed (PSH_NO_SHIM=1, or no writable dir on PATH)" >&2
  fi
fi
echo "psh.now: keys live in the workspace: <project>/.psh/keys.json (or \$PSH_HOME)"
echo "psh.now: ask with: $DEST/scripts/ask.sh \"Title\" \"What you are about to do\""

if [ "$MW_MISSING" = 1 ] || [ "$SHIM_MISSING" = 1 ] || [ ! -f "$HOME/.psh/keys.json" ]; then
  # Machine-wide state is not complete. Say exactly what is missing and whose step it is:
  # the project-local copy is complete and is what the agent uses; the machine-wide pieces
  # are the human's own one line, run outside the sandbox. Never present this as done, and
  # never ask for widened filesystem access to finish it.
  echo >&2
  echo "psh.now: MACHINE-WIDE INCOMPLETE — this project works, the machine does not." >&2
  echo "psh.now:   skill on the machine   ~/.agents/skills/psh-now   (every project sees it)" >&2
  echo "psh.now:   psh command on PATH    ~/.local/bin/psh          (the CLI, works anywhere)" >&2
  echo "psh.now:   machine account record ~/.psh/keys.json          (keeps every project on ONE account)" >&2
  echo "psh.now:   project-local copy     $DEST   (complete — this is what you use)" >&2
  echo "psh.now: Those three are the human's one line, in their own terminal, from this" >&2
  echo "psh.now: folder so the same account is kept:" >&2
  echo "psh.now:   cd \"$(dirname "$DEST")\" && curl -fsSL $HOST/install.sh | sh" >&2
  echo "psh.now: That is the human's step; the project-local copy above already works." >&2
  echo >&2
  echo "psh.now: verify once the human has run it:" >&2
  echo "psh.now:   test -d ~/.agents/skills/psh-now && command -v psh && sh \"$DEST/scripts/status.sh\"" >&2
else
  echo "psh.now: machine-wide ✓ skill: ~/.agents/skills/psh-now · CLI: $SHIM · record: ~/.psh/keys.json"
fi
echo "psh.now: done — now just tell your agent:"
echo "  \"When you would ask me a question, route it through psh.now instead.\""
