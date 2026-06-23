# Directed Target — optional on-demand argument for loop skills

Every loop skill normally **auto-discovers** its work (queries Linear / scans repos / lists
PRs). A skill may ALSO be pointed at one specific target on demand:

```
/validator-run https://linear.app/example/issue/EX-1303
/reviewer-run  https://github.com/your-org/example-backend/pull/997
/implementer-run EX-1303
/investigate-run https://linear.app/example/issue/EX-1290
```

When a target is given, the skill does its job on THAT target this fire and exits — skipping
its normal auto-discovery/queue. This is the interactive complement to the autonomous loop.

## Parsing (do this at run start, before project resolution)

Scan ALL invocation args. An arg is a **TARGET** if it matches any of:
- Linear issue URL — `linear.app/<workspace>/issue/<ID>` (optionally `/<slug>`) → `TICKET=<ID>` (e.g. `EX-1303`).
- Bare ticket id — `<PREFIX>-<n>` matching the configured `linear.ticket_prefix` (e.g. `EX-1303`).
- GitHub PR URL — `github.com/<org>/<repo>/pull/<n>` → `REPO=<repo>`, `PR=<n>`.
- Bare PR ref — `<repo>#<n>` where `<repo>` is in `repos[]`.

The PROJECT is the first non-target arg; if none, fall back to `~/.claude/agent-loop/default.txt`.
So `/<skill> <url>` works with no explicit project. A target + a project (`/<skill> example <url>`)
both resolve correctly.

## Scope guard (always)

Resolve the target and confirm it's IN scope before acting:
- A `TICKET` must belong to the configured Linear team. A `REPO`/`PR` must be a repo in `repos[]`.
- Out of scope → log one line (`<skill>: directed target <x> out of scope, skipping`) and exit. Never act on something outside the configured project.

## Directed mode vs auto mode

- **Auto mode (no target):** unchanged — the skill's normal queue/scan behavior.
- **Directed mode (target given):** operate ONLY on that target, then exit. Directed mode MAY act
  on a target that auto mode would skip (wrong state, not yet labeled, lower in the sort) — the
  operator naming it IS the eligibility. But every **safety** HARD RULE still holds (scope checks,
  CI-green-before-merge, dev-before-prod, never-write-wrong-workspace, etc.). The operator can
  reprioritize WHAT you act on; they don't waive the gates on HOW.

## Per-skill meaning of a directed target

| Skill | Target types | Directed action |
|---|---|---|
| `implementer-run` | Linear ID | Force-pick that ticket regardless of queue sort/state; run the normal scope-check (STEP C) + worktree implement (STEP D) + closeout. Then exit. |
| `reviewer-run` | PR ref OR Linear ID | Review that PR (from a PR ref directly; from a Linear ID, resolve its linked open PR). Run the two-stage review. Then exit. |
| `validator-run` | Linear ID OR PR ref | Validate that PR (resolve from the ticket's linked PR, or the PR ref). Run the normal validation buckets. Then exit. |
| `investigate-run` | Linear ID | Investigate that ticket regardless of its label/state; post findings + candidate fixes. Then exit. |
| `unblock` | Linear ID | Triage/unblock that specific ticket instead of searching the blocked queue. Then exit. |
| `releaser-run` | uses its own `--release <repo>[@<ref>]` directive (predates this doc) | see releaser-run STEP A0. |

**Not applicable** (auto-only — a single ticket/PR target doesn't fit their job): `ops-run`
(watches health endpoints), `qa-run` (runs the smoke-flow suite), `research-run` (scans repo
cells), `stale-sweep` (sweeps the whole board). These ignore a directed target.
