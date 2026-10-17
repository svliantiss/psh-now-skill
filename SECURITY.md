# Security — the psh.now skill

_config: internal artifact + `security.md` for the public repo (checklist 3.7)._

## What this skill does

psh.now routes a question the agent was already going to ask into one human
decision: the agent POSTs `{"title","message"}`, the user taps **Approve** or
**Deny** from anywhere, and the agent gets one boolean back (`true`/`false`).
It exists so agents stop stalling in a terminal nobody is watching.

## What runs on the machine

Three POSIX `sh` scripts that come with the skill. They are plain shell —
**no `eval`, no `sudo`, no service daemon** — and they touch only:

| Location | Why |
|---|---|
| `<project>/.psh/keys.json` · `host` | the channel key + baked-in host (mode `0600`) |
| `<project>/.psh/config.json` · `README.md` | the `psh` CLI's config + a plain-text breadcrumb |
| `~/.psh/keys.json` · `host` | this machine's account, written by the first install (never overwritten while it is still valid) |
| `~/.psh/config.json` · `README.md` | only created when absent or when they already point at that workspace |
| `~/.agents/skills/psh-now/` | the machine-wide skill copy (real files, not a symlink) |
| one PATH directory | the `psh` command (`~/.local/bin`, `~/.bun/bin`, …), recorded in `.psh-bin` for `--uninstall` |
| `<skill dir>/.keys.json` | read-only legacy fallback; never written |
| `stdout` / `stderr` | result (`psh_result.*`) and progress |

Everything else the scripts do is an HTTPS call to the configured host.

## What is sent

One UTF-8 JSON body per ask:

```json
{"title":"…", "message":"…", "agent":"…", "cwd":"…", "wait":true}
```

- **`title` + `message`** — what the agent writes for the human to read.
  There is **no file content, no code, no key material, no command output**
  unless the agent itself chooses to quote it in `message`. The human reads it
  before deciding.
- **`agent`** (optional) — display name of the calling harness
  (`claude-code`, `cursor`, …). Present so a human can tell which agent asked.
- **`cwd`** (optional, off by default) — path of the working directory.
- **The channel key** goes in the `x-psh-key` header. It is **ask-only**: it
  can create approval requests and read their result, and nothing else. The
  *account* (`userKey`) key is the one that signs in to the app.

## What comes back

`{"approved": true}` or `{"approved": false}` — plus `decision` (which option
on a batched ask) and `pollUrl`. Nothing else. The agent does not get codes,
emails, or device lists from an ask.

## Honest limits (please read)

- The skill **guides the model; it does not enforce**. An agent can skip
  asking. Enforcement belongs to the harness, the OS, or your own
  policy — psh.now deliberately stays harness-agnostic (no SDK, no MCP).
- Approvals are granted per decision, not per session. Silence is never
  consent; a timed-out ask resolves to `false`.
- The message is written by the asking agent. The human and the network
  should treat it as untrusted text, not as proof of what will actually run.

## How to audit the install without trusting the installer

Pick whichever you actually control:

1. **Preferred — npm:** `npx skills add psh-now/skill --skill psh-now -g -y`
   installs from a GitHub repo every file of which is readable before it runs.
2. **Well-known tarball:** the host publishes
   `.well-known/skills/index.json` with a `sha256:` digest of the artifact:

   ```bash
   dig=$(curl -fsSL https://psh.abslm.nl/.well-known/agent-skills/index.json | …read digest)
   curl -fsSL https://psh.abslm.nl/psh-now.tar.gz | shasum -a 256 -c -   # compare
   ```

   The `skills` CLI performs the same digest check on install.
3. **The `curl | sh` fallback** exists only for machines without npm. If
   you would rather not pipe blind:

   ```bash
   curl -fsSL https://psh.abslm.nl/install.sh -o install.sh
   ${EDITOR:-vi} install.sh          # read it; it is ~50 lines of POSIX sh
   sh install.sh
   ```

## Reporting

Contact the operator: **[absolum.nl](https://absolum.nl)** — or, once the
public repo is live (checklist 4.1), open a security issue there. The skill's
own scripts are the audit surface; the service itself is closed-source and
should be treated as a black box **on your own domain** if you self-host it.
