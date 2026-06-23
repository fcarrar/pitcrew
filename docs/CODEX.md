# Running pitcrew on OpenAI Codex

pitcrew's skills are **harness-agnostic** — the body of each `skills/<slug>/SKILL.md` is
natural-language workflow + `bash`/`gh`/`git`/`jq` + a config-driven `STEP −1` block, none of
which is Claude-specific. The **same skill files** drive both Claude Code and Codex; only the
*adapter* differs, and that adapter is built in:

| | Claude Code | Codex |
|---|---|---|
| Install skills | `bin/install.sh` → `~/.claude/commands/` | `bin/install-codex.sh` → `~/.codex/prompts/` |
| Invoke | `/research-run` (skill) | `/research-run` (Codex custom prompt) or headless `codex exec` |
| Schedule the loop | `/loop 30min /research-run` | cron → `bin/pitcrew-codex.sh` |
| Find the Linear tools | binding block detects `mcp__linear-server__*` / `mcp__claude_ai_Linear__*` | **same binding block** detects the `linear` MCP server from `~/.codex/config.toml` (by capability — see below) |
| Ask a human (`unblock`) | `AskUserQuestion` tool | **built-in fallback**: the same question as plain text (see `unblock` STEP 6) |
| Runtime config + state | `~/.claude/agent-loop/<project>/` | **same dir** (shared) |

## Install

```bash
cd pitcrew
./bin/install-codex.sh my-project          # symlinks 12 prompts + seeds shared config
```

Runs the same config wizard as the Claude install and writes the **shared** runtime dir
`~/.claude/agent-loop/<project>/` (override with `PITCREW_HOME`). If you already ran
`./bin/install.sh`, the config is reused — one config, both harnesses.

## Linear & MCP (`config.toml`)

`research-run` and `qa-run` write local ledgers and need **no** tracker — they run on Codex as-is.
The other ten coordinate through Linear. Wire it once:

1. Add the Linear MCP server to `~/.codex/config.toml` (see
   [`references/codex-config.example.toml`](../references/codex-config.example.toml)):
   ```toml
   [mcp_servers.linear]
   command = "npx"
   args = ["-y", "mcp-remote", "https://mcp.linear.app/mcp"]
   ```
2. That's it — **no skill edit needed.** The `LINEAR BINDING` block in every skill now resolves
   `<LINEAR>` **by capability**: it picks whichever available tool family exposes
   `list_teams`/`get_issue`/`save_issue`/… , so it finds the Codex `linear` server the same way it
   finds Claude's. (See `references/LINEAR-ACCESS.md` §1.)

## Schedule the loops (cron, since Codex has no `/loop`)

`bin/pitcrew-codex.sh <skill> [project]` runs one headless pass. Point cron at it:

```cron
# ledger producers — no network needed, default sandbox is fine
*/30 *  * * *  /path/to/pitcrew/bin/pitcrew-codex.sh research-run my-project   >> ~/.codex/logs/research-run.log 2>&1
0    */2 * * *  /path/to/pitcrew/bin/pitcrew-codex.sh qa-run my-project         >> ~/.codex/logs/qa-run.log 2>&1

# Linear-coupled skills — need network (gh/curl + the Linear MCP), so widen the sandbox
*/15 *  * * *  CODEX_SANDBOX=danger-full-access /path/to/pitcrew/bin/pitcrew-codex.sh implementer-run my-project >> ~/.codex/logs/implementer-run.log 2>&1
*/15 *  * * *  CODEX_SANDBOX=danger-full-access /path/to/pitcrew/bin/pitcrew-codex.sh reviewer-run my-project    >> ~/.codex/logs/reviewer-run.log 2>&1
0    *  * * *  CODEX_SANDBOX=danger-full-access /path/to/pitcrew/bin/pitcrew-codex.sh manager-run my-project     >> ~/.codex/logs/manager-run.log 2>&1
```

`pitcrew-codex.sh` invokes `codex exec` with the skill body on **stdin** (the skill's `---`
frontmatter would otherwise be parsed as a CLI flag), and an `--add-dir` for every `repos[].path`
plus the runtime dir so file ops are allowed.

Env overrides: `CODEX_BIN` (path to the codex CLI — e.g. the app-bundled
`/Applications/Codex.app/Contents/Resources/codex` if it's not on `PATH`), `PITCREW_HOME`,
`CODEX_SANDBOX` (`read-only` | `workspace-write` | `danger-full-access`).

## Sandbox & network

`workspace-write` (the runner default) lets the agent write the configured repos + the runtime
dir but **disables network**. That's correct for the ledger producers. The Linear-coupled skills
also reach the network (`gh`, curl, the Linear MCP), so run those with
`CODEX_SANDBOX=danger-full-access`, or keep the write-sandbox and enable network for it via a Codex
profile (see `references/codex-config.example.toml` and your Codex version's sandbox docs).

## What's built in vs. what's yours to set

- **Built in:** harness-agnostic Linear detection (all 10 Linear-coupled skills + LINEAR-ACCESS.md);
  the `unblock` plain-text question fallback; the Codex installer, headless runner, and cron template.
- **Yours to set, once:** the `~/.codex/config.toml` Linear MCP entry, the cron lines, and the
  sandbox/network choice above. The shared runtime dir keeps the `claude` name unless you set
  `PITCREW_HOME`.

## Spike status (validated 2026-06-23)

On `codex-cli 0.140`: the **unmodified** `research-run/SKILL.md` symlinks into `~/.codex/prompts/`
and `codex exec` ingested the full skill body (via stdin) + the project directive and began the
pass — confirming the thesis end to end. (The validation run was cut short only by a Codex account
usage limit, not by anything in pitcrew.) Re-run `./bin/pitcrew-codex.sh research-run <project>`
once quota is available to see the ledger written.
