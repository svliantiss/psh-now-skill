# psh.now skill

The installable skill for [psh.now](https://psh.abslm.nl) — human approval for AI
agents. This is the **public** repo; the psh.now service itself is closed.

> One host + one key + one boolean. Your agent never stalls on a question.

An agent that needs a decision routes it here as a single **approve/deny** on its
recommended route, instead of stopping in a terminal you can't see.

## Install

```bash
npx -y skills add svliantiss/psh-now-skill --skill psh-now --copy -y -a universal
sh .agents/skills/psh-now/scripts/setup.sh
```

No npm/npx? Use the hosted installer:

```bash
curl -fsSL https://psh.abslm.nl/install.sh | sh
```

Then give your agent a host and a key (environment, or `<project>/.psh/keys.json`,
with this machine's account in `~/.psh/keys.json` as the fallback):

```bash
export PSH_BASE_URL="https://psh.abslm.nl"
export PSH_API_KEY="psh_live_..."
```

`setup.sh` writes both to `<project>/.psh/keys.json` and `<project>/.psh/host` for
you, and `psh` (installed on PATH) prints where everything is.

## What the agent does

```bash
curl -s -X POST "$PSH_BASE_URL" \
  -H "x-psh-key: $PSH_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"title":"Create src/ and PLAN.md?","message":"Recommended: create src/ and write PLAN.md. No source files yet."}'
```

Response — the only two possible bodies:

```json
{ "approved": true }
```

```json
{ "approved": false }
```

Proceed only on `true`. A timeout, a proxy error, or anything else means **do
not act**. Silence is never consent.

## Pair a device

Open the pairing link from `psh init` or the dashboard on your phone and tap
**Pair this device**. Approvals then land on your lock screen.

## Docs

- Full agent context: <https://psh.abslm.nl/llms.txt> · <https://psh.abslm.nl/llms-full.txt>
- Hosted skill: <https://psh.abslm.nl/skill.md>
- Agent manifests: <https://psh.abslm.nl/.well-known/agent.json>

## Layout

```
SKILL.md     the skill (Agent Skills format)
install.sh   the no-npm fallback installer
```

`SKILL.md` and `install.sh` are synced from the psh.now service repo. Do not
edit them here by hand.
