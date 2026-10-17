# AGENTS.md

Instructions for coding agents working in **this** repo (the public psh.now
skill). For the skill's own instructions to agents, see `SKILL.md`.

## What this repo is

The publishable skill package for psh.now. It is **not** the service. The
service (server, database, dashboard) is closed source and lives elsewhere.

## Rules

- Keep `SKILL.md` focused, in the here.now style: docs-first, one clear
  behavioural rule, one tool, one boolean. Do not add select/input, polling
  transports, or policy engines.
- The skill **is** the mechanism. It must make this unmissable: *if you are about
  to ask the user a question, do not end your turn with it — turn it into a
  yes/no on your recommended route and route it through psh.now.* Destructive
  actions are examples, not the definition.
- Store credentials in `<project>/.psh/keys.json` (outside the skill dir, so
  reinstalling the skill cannot wipe them), with the machine's account in
  `~/.psh/keys.json` as the fallback, like here.now's `~/.herenow/credentials`.
- `SKILL.md` and `install.sh` are **synced** from the service repo. Prefer
  changing them there and re-syncing, rather than editing here.
- The only valid approval answers are `{"approved": true}` and
  `{"approved": false}` — `approved` stays a boolean. A batched `route` adds an
  optional `decision` string naming the chosen option id; it never replaces the
  boolean. Keep the "no fabricated approvals / no codes" rule.
- Keep the install shape identical to the ecosystem norm:
  `npx skills add <org>/skill --skill <name> -g`, with a `curl …/install.sh | sh`
  fallback.

## Sync

From the service repo:

```bash
scripts/sync-skill-repo.sh
```

which copies `skills/psh-now/SKILL.md` and `install.sh` into this directory.
