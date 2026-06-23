# Running pitcrew on OpenAI Codex

pitcrew's skills are **harness-agnostic** — the body of each `skills/<slug>/SKILL.md` is
natural-language workflow + `bash`/`gh`/`git`/`jq` + a config-driven `STEP −1` block, none of
which is Claude-specific. So the **same skill files** drive both Claude Code and Codex; only the
*adapter* differs:

| | Claude Code | Codex |
|---|---|---|
| Install skills | `bin/install.sh` → symlinks into `~/.claude/commands/` | `bin/install-codex.sh` → symlinks into `~/.codex/prompts/` |
| Invoke | `/research-run` (skill) | `/research-run` (Codex custom prompt) or headless `codex exec` |
| Schedule the loop | `/loop 30min /research-run` | cron → `bin/pitcrew-codex.sh` |
| Ask a human (`unblock`) | `AskUserQuestion` tool | plain-text question (see caveats) |
| Tracker (Linear) | Linear MCP, auto-detected by the binding block | Linear MCP in `~/.codex/config.toml` (see below) |
| Runtime config + state | `~/.claude/agent-loop/<project>/` | **same dir** (shared) |

## Install

```bash
cd pitcrew
./bin/install-codex.sh my-project          # symlinks 12 prompts + seeds shared config
```

This runs the same config wizard as the Claude install and writes to the **shared** runtime dir
`~/.claude/agent-loop/<project>/` (override with `PITCREW_HOME`). If you already ran `./bin/install.sh`,
the config is reused — one config, both harnesses.

## Schedule the loops (cron, since Codex has no `/loop`)

`bin/pitcrew-codex.sh <skill> [project]` runs one headless pass. Point cron at it:

```cron
*/30 *  * * *  /path/to/pitcrew/bin/pitcrew-codex.sh research-run my-project   >> ~/.codex/logs/research-run.log 2>&1
0    */2 * * *  /path/to/pitcrew/bin/pitcrew-codex.sh qa-run my-project         >> ~/.codex/logs/qa-run.log 2>&1
*/15 *  * * *  /path/to/pitcrew/bin/pitcrew-codex.sh implementer-run my-project >> ~/.codex/logs/implementer-run.log 2>&1
```

`pitcrew-codex.sh` invokes `codex exec` with the skill body on **stdin** (the skill's `---`
frontmatter would otherwise be parsed as a CLI flag), `--sandbox workspace-write`, and an
`--add-dir` for every `repos[].path` plus the runtime dir so file ops are allowed.

Env overrides: `CODEX_BIN` (path to the codex CLI — e.g. the app-bundled
`/Applications/Codex.app/Contents/Resources/codex` if it's not on `PATH`), `PITCREW_HOME`,
`CODEX_SANDBOX` (`read-only` | `workspace-write` | `danger-full-access`).

## Linear-coupled skills

`research-run` and `qa-run` write local ledgers and need **no** tracker — they run on Codex as-is.
The rest coordinate through Linear. To run them on Codex:

1. Add a Linear MCP server to `~/.codex/config.toml`:
   ```toml
   [mcp_servers.linear]
   command = "npx"
   args = ["-y", "mcp-remote", "https://mcp.linear.app/mcp"]
   ```
2. The skills' **LINEAR BINDING block** already treats the tool prefix as a variable `<LINEAR>`.
   It currently resolves `mcp__linear-server__*` / `mcp__claude_ai_Linear__*` (Claude's names);
   add a branch that resolves `<LINEAR>` to Codex's MCP tool names for the `linear` server. That's
   the one edit needed to make the Linear-coupled skills portable.

## Caveats / remaining adapter work

- **Sandbox + network.** `workspace-write` disables network. Skills that call `gh`/curl against a
  remote (implementer, reviewer, ops, releaser) need a Codex profile that re-enables network, or
  `CODEX_SANDBOX=danger-full-access`. The ledger producers don't.
- **`AskUserQuestion`** (only `unblock` and `investigate-run`) has no Codex equivalent — those two
  need a plain-text question variant. The other ten are unaffected.
- **Shared runtime dir** is `~/.claude/agent-loop/` regardless of harness. Cosmetic only; rename via
  `PITCREW_HOME` if the `claude` in the path bothers a Codex-only setup.

## Spike status (research-run, validated 2026-06-23)

A one-skill spike confirmed the thesis end-to-end on `codex-cli 0.140.0`:

- ✅ The **unmodified** `research-run/SKILL.md` symlinks into `~/.codex/prompts/` and resolves as a prompt.
- ✅ `install-codex.sh` wires all 12 prompts + the shared config; `pitcrew-codex.sh` builds a correct `codex exec` invocation.
- ✅ `codex exec` ingested the full skill body (via stdin) + the project directive and began the pass.
- ⏸️ The full agentic completion was cut short only by a **Codex account usage limit**, not by anything in pitcrew — re-run `./bin/pitcrew-codex.sh research-run <project>` once quota is available to see the ledger written.

**Effort to finish the port:** producers (research/qa) already work; the Linear-coupled skills need
the one binding-block branch + a `config.toml` MCP entry (~half a day); `unblock`/`investigate-run`
need a text-question fallback (~couple hours). No skill rewrite — it's an adapter, as predicted.
