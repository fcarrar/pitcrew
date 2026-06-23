# agent-loop SETUP

Bootstrap a new project's config from scratch.

> **Future automation (planned, not implemented):** turn the steps below into an interactive `/agent-loop-init <project>` skill that walks you through the fields, validates as it goes (probes Linear for label IDs, checks repo paths exist), and writes the config for you. For now, do it by hand — it's ~5 minutes the first time, and the manual flow surfaces every decision explicitly which is useful while the schema is still evolving.

## Prerequisites

- `gh` authenticated as the GitHub identity that authors PRs.
- Linear MCP server connected in Claude Code (if you want implementer/researcher).
- A Slack webhook URL ready (optional — paste empty `""` if you don't want Slack notifications).

## 1. Pick a project name

Short, lowercase, no spaces. This is the folder name under `~/.claude/agent-loop/`. Examples: `example`, `life-tracker`, `acme-freelance`.

## 2. Create the config

```bash
mkdir -p ~/.claude/agent-loop/<project>/state
cp /path/to/pitcrew/references/config.example.json ~/.claude/agent-loop/<project>/config.json
$EDITOR ~/.claude/agent-loop/<project>/config.json
```

## 3. Fill it in

### Required for everything

| Field | What it is | Example |
|---|---|---|
| `project_name` | Same as the folder name | `"example"` |
| `github.reviewer_login` | Your GitHub username (whose PRs the reviewer agent will scan, and whose review verdicts the implementer gate looks for) | `"your-username"` |
| `github.org` | The GitHub org/owner for your repos | `"your-org"` |
| `repos` | Array of every repo the agents may operate on | see below |

Each repo entry:

```json
{
  "name": "example-frontend",                                 // short logical name used everywhere
  "path": "~/Documents/example-frontend",                     // local clone path (~ expanded at runtime)
  "default_branch": "master",                          // master | main | etc.
  "lang": "ts",                                        // ts | go | py | etc. — drives which static-analysis tools researcher tries
  "tags": ["widgets", "ui"]                            // free-form labels used in routing rules
}
```

### Required for `implementer-run` and `research-run` (Linear integration)

| Field | What it is |
|---|---|
| `linear.use` | `true` |
| `linear.workspace_slug` | The slug in your Linear URL (`https://linear.app/<slug>/...`) |
| `linear.team_name` | The team your tickets live under (e.g. `"Example"`) |
| `linear.team_id` | The team's UUID — the LINEAR BINDING block in every skill confirms it's talking to the right workspace by checking this. Get it once via `mcp__linear-server__list_teams`. |
| `linear.ticket_prefix` | The ID prefix (e.g. `"EX"` → tickets are EX-123) |
| `linear.assignee_email` | Your Linear identity email — the agents assign tickets to this address so the loop can find them |
| `linear.labels` | The label *names* for `quick-win`, `Bug`, `Improvement` |
| `linear.label_ids` | (Optional) Label UUIDs. Save one MCP call per fire if filled. Get them once via `mcp__linear-server__list_issue_labels`. |
| `linear.agent_backlog_project.name` | (Optional) Name of a Linear project where agent-filed tickets land. Leave `""` to file directly to team backlog. |
| `linear.agent_backlog_project.id` | (Optional) Project UUID. |

### Required for `qa-run`

| Field | What it is |
|---|---|
| `qa.test_flow_repo` | The `repos[].name` of the repo holding `flows/**/*.md` test contracts |

The runner reads `<test_flow_repo>/.env` for env-specific URLs (`<UPPERCASE_PROJECT>_DEV_*`). Adjust the convention in the runner if your project uses a different env var prefix.

### Required for `research-run` mode `architecture`

| Field | What it is |
|---|---|
| `researcher.architecture_repo` | Logical repo name of a docs-only repo holding cross-service architecture markdown |
| `researcher.architecture_path` | Local path to it (may live outside `repos[]`) |

Omit both if you don't have a cross-service architecture doc — `architecture` mode is dropped automatically.

### Optional everywhere

- `slack.qa_webhook_url`, `slack.quickwins_webhook_url` — keep `""` to silence notifications.
- `slack.user_mention` — `<@U…>` to ping yourself when there are PRs awaiting your `go`.
- `slack.timezone` — IANA tz used for human-readable timestamps in Slack. DST-aware.
- `loop.fast_wakeup_seconds`, `loop.slow_heartbeat_seconds` — tuning for `/loop` dynamic pacing.

## 4. Set the default project (optional)

```bash
echo "<project>" > ~/.claude/agent-loop/default.txt
```

After this, running `/research-run` with no args uses this project. Pass an explicit arg to override: `/research-run other-project`.

## 5. First run + launch the loops

Smoke one skill first to confirm the config is valid:

```bash
/research-run <project>     # validates config, runs one cell, exits with a summary
```

If validation fails it prints the missing fields + the exact JSON path to fix. Then launch the
loops you want (each on its own cadence; omit any you don't use):

```
/loop 15min /implementer-run
/loop 15min /reviewer-run
/loop 30min /research-run
/loop 2hours /qa-run            # records findings to a ledger; /manager-run tickets them
/loop 15min /validator-run
/loop 6h    /stale-sweep
/loop 30min /unblock
/loop 30min /investigate-run
/loop 10min /ops-run            # needs repos[].health
/loop 15min /releaser-run       # needs repos[].release (starts at autonomy:"prepare")
/loop 1h    /manager-run        # needs manager.sources[]
/loop 12h   /coverage-run       # needs qa.test_flow_repo + an architecture repo
```

Per-skill config requirements: `repos[].health` (ops), `repos[].release` (releaser),
`manager.sources[]` (manager), `qa.test_flow_repo` (qa + coverage), `backend` (Linear-binding
resilience — defaults are fine). All optional blocks are documented in `config.example.json`.

> **After editing any skill, restart its loop** — a running `/loop` can stay pinned to the skill
> version it launched with. (Learned the hard way 2026-06-23.)

If validation fails, the skill prints the missing fields and the exact JSON path to fix, then exits without doing any work. Fix, run again.

## Switching projects mid-session

If you're working on Example and want to fire a one-off `research-run` against `life-tracker`:

```
/research-run life-tracker
```

The skill loads `life-tracker`'s config for that one fire only. `default.txt` is not touched.

## On a new machine

```bash
# Recreate the folder layout — actual configs are NEVER committed
mkdir -p ~/.claude/agent-loop
echo "example" > ~/.claude/agent-loop/default.txt

# Per project, copy the example and fill in the real values
mkdir -p ~/.claude/agent-loop/example/state
cp pitcrew/references/config.example.json ~/.claude/agent-loop/example/config.json
$EDITOR ~/.claude/agent-loop/example/config.json
# Paste webhook URLs and label IDs from your password manager / Linear UI
```

## Security

- `~/.claude/agent-loop/*/config.json` contain Slack webhook URLs and team-internal Linear identifiers. **Never commit them.** They live under `~/.claude/`, outside this repo, so they're never in version control.
- Only the placeholder `config.example.json` lives in version control.
- If a webhook leaks, regenerate it in Slack > Incoming Webhooks; no other rotation needed.
