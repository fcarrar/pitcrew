# Agent Loop Topology — project: <PROJECT_NAME>

> Source of truth for which skill does what, how tickets route, and where each handoff happens. Every skill reads this at the top of its run (alongside `lessons.md`). Update here first when adding/removing/renaming a skill; the change propagates to all skills' shared context.
>
> Copy this file to `~/.claude/agent-loop/<PROJECT_NAME>/TOPOLOGY.md` and customize for your stack. The skill family below is the canonical starting set — adapt as needed.

## The thirteen skills

| Skill | Role (one line) | Reads | Writes |
|---|---|---|---|
| **`/research-run`** | Scans repos for drift (hygiene / hardening / doc-sync / architecture). Files **new** `Improvement` tickets the agent loop can act on. | repos[] (read-only scans) | files issue-tracker tickets in `$STATE_TODO` |
| **`/qa-run`** | Runs smoke flows from `<test_flow_repo>` against **dev environment**. Files `Bug` / drift tickets on fail. | dev backend / surfaces | files issue-tracker tickets |
| **`/implementer-run`** | Picks `agent`-labeled tickets in `$STATE_TODO`, opens PRs, addresses reviewer change-requests, merges on human "go". | issue queue, GitHub | git commits + PRs + state moves |
| **`/reviewer-run`** | Reviews open PRs you authored. Posts verdict using the keyword vocabulary (`Verdict: signed-off` / `Verdict: CHANGES_REQUESTED`). | open PRs | `gh pr review --comment` |
| **`/validator-run`** | Tests open PRs locally — `frontend-visual` / `docs` via Playwright, `mcp` / `rest` via LOCAL-LAUNCH PATH + flow replay. Gates the implementer's "Ready for your go" list. | open PRs, repos[] | GitHub PR comment, issue-tracker comment, state file only |
| **`/unblock`** | Triages tickets in `$STATE_BLOCKED`. AskUserQuestion → human-in-the-loop decision. Can split children, draft PLAN.md, file investigate-sibling, send-back-to-todo, close. | blocked queue | issue-tracker comments + state moves + new tickets + draft plans |
| **`/investigate-run`** | Picks up `investigate`-labeled tickets (filed by `/unblock`). Read-only investigation. Posts findings + ranked candidate fixes. Moves ticket to `$STATE_BLOCKED` so `/unblock` resurfaces findings. | repos[] (read-only), dev systems (curl / dry-run) | issue-tracker comment + state move only |
| **`/stale-sweep`** | Closes tickets in `$STATE_REVIEW` whose PRs got merged but state didn't propagate. Catches the lifecycle gap. | issue tracker + GitHub | state moves only |
| **`/ops-run`** *(outward)* | Watches RUNNING prod — polls `repos[].health` endpoints, anti-flap re-checks, files deduped `incident` tickets on confirmed degradation. Observe-and-file only. | prod health endpoints | files incident tickets |
| **`/releaser-run`** *(outward)* | Ships already-merged work dev→prod as versioned releases, smoke-checks each stage, auto-rolls-back on a prod break. Per-repo armed (`release.autonomy`). Agent-authored work only by default. | default branch, GitHub, deploy mechanisms | deploy triggers + release tickets |
| **`/manager-run`** *(intake)* | Turns a curated findings source (audit / qa ledger) into PACED, prioritized, routed tickets. Maintains a target queue depth; risky→`investigate`, contained→`agent`. Files tickets only. | findings sources | files (paced) tickets |
| **`/coverage-run`** *(producer)* | Finds capability×surface coverage gaps in the test-flow repo, opens grounded flow PRs (reviewer+validator gate). Proactive complement to the test-first rule. | the flow matrix + arch docs | opens test-flow PRs (paced) |
| **`/dev-verify-run`** *(producer)* | Post-deploy verifier: tests merged PRs that are LIVE on dev — plans targeted flows (diff→capability) and runs ONLY those against the live dev env. Failures → verify ledger → manager. Doesn't deploy or gate. | merged PRs + live dev | writes verify ledger |

## The state machine

```
agent-todo → agent-processing → agent-review → agent-done
                  ↓                  ↓
              agent-blocked ←────────┘
                  ↑
              (human triage via /unblock)
```

- **`agent-todo`** — eligible, untouched. `/implementer-run` picks up unless `investigate`-labeled (then `/investigate-run` does).
- **`agent-processing`** — implementer working (or investigator working).
- **`agent-review`** — PR open. Reviewer + validator evaluate. Human "go" merges.
- **`agent-blocked`** — bailed (scope / fix-exhausted / auth-sensitive / investigation-complete / etc.). `/unblock` is the ONLY skill that picks these up.
- **`agent-done`** — terminal.

## Label-based routing

The `agent` label is the eligibility gate. Additional labels route to specific skills:

| Label | Effect | Set by |
|---|---|---|
| `agent` | Eligible for the loop (mandatory on EVERY ticket the loop touches) | researcher / QA / `/unblock` / human |
| `investigate` | Routes to `/investigate-run` instead of `/implementer-run`. **Implementer STEP B drops tickets carrying this label.** | `/unblock` when filing an investigate-sibling |
| `quick-win` | Sort-hint: agent picks quick-wins first. NOT eligibility. ≤2 files of substantive change only. | researcher (with file-count gate) |
| `Bug` / `Improvement` | Category — not eligibility, not routing. | researcher / QA |

### Assignee is convention, NOT eligibility

Skills set `assignee: $ASSIGNEE_EMAIL` when filing tickets so they appear in the operator's "assigned to me" view of the issue tracker. **No skill filters list-queries by assignee for ticket pickup.** Eligibility = label only. This lets non-operator contributors file tickets (with the `agent` label) and the loop will still pick them up.

## Handoff flow (single ticket lifecycle)

```
                   ┌──────────────┐
                   │   ticket     │
                   │ landed in    │
                   │ agent-todo   │
                   └──────┬───────┘
                          │
              ┌───────────┴────────────┐
              │ has `investigate` lab? │
              └───────┬────────┬───────┘
                  no  │        │  yes
                      ▼        ▼
            /implementer-run  /investigate-run
                      │        │
        ┌─────────────┘        └────────────┐
        │                                   │
        ▼                                   ▼
    opens PR                          posts findings
   ┌──┴──┐                            moves to blocked
   │     │                                   │
   ▼     ▼                                   ▼
review  validator                      /unblock asks
  PR    tests PR                       human decides
   │     │                                   │
   └──┬──┘                                   ▼
      ▼                              draft plan / split /
   awaits "go"                       close / send back
   from human                                │
      ▼                                      │
   /implementer-run merges                   │
      ▼                                      │
   agent-done ◄──────────────────────────────┘
```

## Lifecycle insurance

- **`/stale-sweep`** catches the case where a PR is merged but issue-tracker state didn't follow. Runs every 6h.
- **`/unblock`'s cooldown** (6h per ticket) prevents pestering the human about the same blocker repeatedly.
- **`/investigate-run`'s lock + 24h cooldown** prevents redundant investigations of the same ticket.

## What NOT to confuse

- **`/research-run`** finds NEW issues (drift). It files tickets. It does NOT investigate known blockers — that's `/investigate-run`.
- **`/investigate-run`** dives into ONE known blocker. It does NOT scan broadly — that's `/research-run`.
- **`/qa-run`** runs against **dev**. **`/validator-run`** runs against **local launch + per-PR worktree**. Different environments, different purposes.
- **`/reviewer-run`** reviews CODE. **`/validator-run`** tests BEHAVIOR. Both must pass before the implementer's "Ready for your `go`" digest surfaces the PR.

## When adding a new skill

1. Pick a clear distinct verb for the name (avoid noun collisions like "research"). Conform to `/<verb>-run` for autonomous skills, `/<verb>` for human-in-the-loop.
2. Decide its routing label (if it needs one). Add to `config.json`'s `labels` + `label_ids` and to other skills' skip lists.
3. Add a row to this file's "The thirteen skills" table.
4. Cross-reference in each skill that hands off to or receives from the new one.

## Project-specific config

(Fill in for your project)

- Issue tracker: <Linear team / GitHub issues / Jira project>
- Issue-tracker project: <project name where loop tickets land>
- Repos in loop scope: see `.repos[]` in `~/.claude/agent-loop/<PROJECT_NAME>/config.json`
- Local DB for `/validator-run` rest path (if needed): <host:port>
- Ports used by `/validator-run` local-launch: <list them, ideally outside typical dev range to avoid collisions>
