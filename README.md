# 🏎️ pitcrew

**A pit crew for your codebase.** Twelve [Claude Code](https://claude.com/claude-code) skills that
run as long-lived, self-coordinating loops — scouting your repos for issues, opening and reviewing
PRs, testing them, shipping merged work to production, and keeping the backlog moving while you're
off doing something else.

Point it at *your* project with a single config file. No bespoke infrastructure, no hosted
service — just skills, a coordination board (Linear, optional), and your own machine.

> Like a real pit crew, every member has one job and stays in their lane. The car (your codebase)
> keeps moving because the crew handles the stops — and the dangerous moves (shipping to prod,
> deciding scope) are explicitly armed or routed to a human, never assumed.

---

## The crew

Each skill is a crew member with a single role. They coordinate through a shared board
(issue states + labels), not by talking to each other directly.

| Skill | Crew role | What it does |
|---|---|---|
| `/research-run` | **Scout** | Scans one repo for drift / dead code / doc rot / unsafe patterns. Records findings to a local ledger. |
| `/qa-run` | **Test driver** | Runs smoke flows from your test-flow repo against the **dev** environment. Records fails/drift to a ledger. |
| `/manager-run` | **Crew chief (intake)** | Turns the findings ledgers (research, qa, audits) into **paced**, prioritized, routed tickets. Never floods the board. |
| `/implementer-run` | **Mechanic** | Picks `agent`-labeled tickets, opens PRs, addresses review change-requests, merges on your "go" (low-risk docs/test PRs auto-merge on sign-off). |
| `/reviewer-run` | **Inspector (code)** | Two-stage review of open PRs you authored. Posts a verdict the implementer reads as its merge gate. |
| `/validator-run` | **Inspector (behaviour)** | Tests open PRs locally — Playwright for frontend/docs, local-launch + flow replay for services. Gates the "ready to merge" list. |
| `/unblock` | **Diagnostics (you-in-the-loop)** | Triages blocked tickets with a structured question to *you*. Splits children, drafts a plan, files an investigation, sends back, or closes. |
| `/investigate-run` | **Diagnostics (read-only)** | Dives into one blocker. Read-only investigation, posts findings + ranked candidate fixes, hands back to `/unblock`. |
| `/coverage-run` | **Track mapper** | Finds capability×surface gaps in the test-flow repo and opens grounded new-flow PRs. Proactive complement to the test-first rule. |
| `/ops-run` | **Spotter** | Watches **running prod** — polls health endpoints, anti-flap re-checks, files deduped incident tickets on confirmed degradation. Observe-and-file only. |
| `/releaser-run` | **Tire change** | Ships already-merged work dev→prod as versioned releases, smoke-checks each stage, auto-rolls-back on a confirmed break. **Per-repo armed.** |
| `/stale-sweep` | **Cleanup** | Closes tickets whose PRs merged but state didn't propagate; prunes leaked worktrees and stale deploy PRs. Catches the lifecycle gaps. |

---

## How it works

The crew coordinates through an **issue board** and a tiny **state machine**. A ticket flows:

```
   agent-todo ──▶ agent-processing ──▶ agent-review ──▶ agent-done
                       │                    │
                       └──────▶ agent-blocked ◀──────┘
                                     ▲
                          (you, via /unblock)
```

- **`agent-todo`** — eligible, untouched. The mechanic picks it up (or the investigator, if it's `investigate`-labeled).
- **`agent-processing`** — being worked.
- **`agent-review`** — PR open. Inspectors (reviewer + validator) evaluate. Your "go" merges.
- **`agent-blocked`** — bailed (scope, fix-exhausted, auth-sensitive, investigation-done). **`/unblock` is the only skill that picks these up**, and it always asks *you*.
- **`agent-done`** — terminal.

The **`agent` label is the eligibility gate** — nothing the loop touches is un-labeled. Extra labels
route: `investigate` → diagnostics instead of the mechanic; `quick-win` → sort-hint; `Bug`/`Improvement`
→ category. Assignee is convention, not eligibility, so anyone can file a ticket the loop will pick up.

Full handoff flow, routing rules, and "what NOT to confuse" live in
[`references/TOPOLOGY.md`](references/TOPOLOGY.md).

### The full pipeline

```
  Scout ─┐
         ├─▶ findings ledger ─▶ Crew chief (paced) ─▶ board ─┬─▶ Mechanic ─▶ PR ─┬─▶ Inspectors ─▶ "go" ─▶ merge ─▶ Tire change ─▶ prod
  Test ──┘                                                   │                   │                                     ▲
  driver                                                     └─▶ Diagnostics ◀───┘ (blocked)                           │
                                                                    ▲                                          Spotter watches prod
                                                                    └── you decide (/unblock)                  and files incidents
```

Every stage is one skill, fired on its own cadence by Claude Code's `/loop`. They never block each
other — the board is the only shared state.

---

## Install

Requirements: [Claude Code](https://claude.com/claude-code), `gh` (authenticated), `jq`. A Linear
MCP connection is optional (see *Configure* below).

**Clone pitcrew somewhere, then run the installer from inside the clone.** `install.sh` wires
*pitcrew itself* into Claude Code — it does **not** touch your project repos. Those stay wherever
they already are; you just point the config at them (the wizard does this for you).

```bash
git clone https://github.com/fcarrar/pitcrew.git
cd pitcrew                          # ← run install.sh from in here, not from your code folder
./bin/install.sh my-project         # default project name: "example"
```

The installer:
1. **Symlinks** each `skills/<slug>/SKILL.md` → `~/.claude/commands/<slug>.md`, so `/research-run` etc. resolve in Claude Code.
2. Creates the loop's **runtime dir** `~/.claude/agent-loop/my-project/` with `state/`.
3. **Runs the config wizard** (`bin/configure.sh`) — an interactive Q&A that sets up your GitHub identity, Linear (optional), the repos the crew may operate on, and Slack webhooks, then writes `config.json`. (Pass `--no-wizard`, or pipe a non-interactive install, to skip it and drop the example to edit by hand.)
4. Drops `TOPOLOGY.md` / `LINEAR-ACCESS.md` / `DIRECTED-TARGET.md` alongside the config.
5. Initializes a local `lessons.md` (per-operator corrections the skills read each fire) and sets the default project.

It's idempotent and won't clobber an existing `config.json` or `lessons.md`. Re-run the wizard
alone any time with `./bin/configure.sh my-project`.

> **Nothing about pitcrew lives in your code repos**, and nothing about your code lives in
> pitcrew. The only link is the `repos[].path` values in `~/.claude/agent-loop/<project>/config.json`.

---

## Configure

Everything project-specific lives in **one file**: `~/.claude/agent-loop/<project>/config.json`.
The **install wizard fills it for you** (`./bin/configure.sh <project>` to re-run); this section is
what it's setting up, and what to tweak by hand afterward. The skills are generic — they read
`repos[]`, `linear.*`, `github.*`, etc. from this file and adapt.

The wizard asks for:
- **GitHub** — your username (auto-detected from `gh` if available) and the org that hosts your repos.
- **Linear** (optional) — workspace slug, team name + `team_id`, ticket prefix, your assignee email.
- **Repos** — point it at the folder holding your checkouts; it finds the git repos and lets you pick (inferring branch + language), or add them by hand.
- **Slack** (optional) — webhook URLs for notifications, and your timezone.

The resulting file looks like:

```jsonc
{
  "project_name": "my-project",
  "github": { "reviewer_login": "your-username", "org": "your-org" },
  "linear": { "use": true, "team_name": "Example", "team_id": "<uuid>", "ticket_prefix": "EX",
              "assignee_email": "you@example.com" },
  "repos": [
    { "name": "example-frontend", "path": "~/code/frontend", "default_branch": "main", "lang": "ts" },
    { "name": "example-backend",  "path": "~/code/backend",  "default_branch": "main", "lang": "go" }
  ]
}
```

The field-by-field walkthrough — including which fields each skill needs, optional Slack
webhooks, per-repo `health` (for the spotter) and `release` (for the tire change) blocks — is in
[`references/SETUP.md`](references/SETUP.md).

**Optional integrations degrade gracefully:**
- `linear.use: false` → the mechanic/scout sit out; qa/reviewer still work. (A full machine-local board is reserved, not built.)
- Empty Slack webhooks → notifications are silently skipped; a run never fails for a missing webhook.
- No `qa` block → `/qa-run` exits cleanly. No `researcher.architecture_repo` → architecture mode is dropped.

### Run the loops

Each crew member runs on its own cadence. Launch only the ones you want:

```
/loop 15min /implementer-run
/loop 15min /reviewer-run
/loop 30min /research-run
/loop 2h    /qa-run
/loop 15min /validator-run
/loop 6h    /stale-sweep
/loop 30min /unblock
/loop 30min /investigate-run
/loop 10min /ops-run          # needs repos[].health
/loop 15min /releaser-run     # needs repos[].release (starts disarmed at autonomy:"prepare")
/loop 1h    /manager-run      # needs manager.sources[]
/loop 12h   /coverage-run     # needs qa.test_flow_repo + an architecture repo
```

You can also point any skill at one target on demand —
`/implementer-run EX-123`, `/reviewer-run example-backend#42` — see
[`references/DIRECTED-TARGET.md`](references/DIRECTED-TARGET.md).

---

## Safety & autonomy model

Autonomy is **opt-in and graduated**, never assumed. The dangerous moves are gated:

- **Per-repo release arming.** The tire change ships nothing until you arm a repo. The ladder is
  `off → prepare → dev → full`, per repo in `repos[].release.autonomy`. `full` (auto dev→prod with
  rollback) refuses to engage unless both a smoke check *and* a rollback are configured — otherwise it
  silently downgrades to `dev`. You raise the rung when you trust that repo, one repo at a time.
- **Agent-only scope (default).** The tire change auto-releases **only** work whose PR closed an
  agent-labeled, agent-done ticket — never your own in-flight or hand-merged commits. A directed
  `--release` lets you ship anything on demand, through all the same gates.
- **Paced intake.** The crew chief maintains a target queue depth and refills slowly — it will never
  dump 130 findings onto the board at once. It's the only producer allowed to flood, and it's
  designed not to.
- **Risky findings go to a human first.** Anything matching the risk regex (auth, IDOR, money,
  injection, secrets, PII…) is routed to **investigate-first**, not handed straight to the mechanic.
- **Machine gates on every ship.** Dev-before-prod, migration-before-code, red-never-ships,
  verify-the-deploy-landed — encoded as hard rules, not etiquette.
- **You-in-the-loop for ambiguity.** `/unblock` is the only skill that pauses for input, and it
  always asks a *structured* question. Nothing ambiguous gets pattern-matched into a wrong shape silently.
- **Binding resilience.** Skills detect whichever Linear MCP binding is live each fire and, if none
  is (or it's the wrong workspace), degrade to read-only-and-wait rather than writing into the wrong
  place. See [`references/LINEAR-ACCESS.md`](references/LINEAR-ACCESS.md).

---

## Repo layout

```
pitcrew/
├── README.md
├── LICENSE                       # MIT
├── CONTRIBUTING.md
├── bin/
│   ├── install.sh                # symlinks skills into Claude Code + runs the wizard
│   └── configure.sh              # interactive config wizard (re-runnable)
├── skills/
│   └── <slug>/SKILL.md           # the 12 crew members
└── references/
    ├── SETUP.md                  # config walkthrough
    ├── config.example.json       # the one file you fill in (placeholder values)
    ├── TOPOLOGY.md               # roles, routing, handoffs — source of truth
    ├── LINEAR-ACCESS.md          # binding-agnostic + degraded-mode contract
    └── DIRECTED-TARGET.md        # the on-demand "point at one ticket/PR" mode
```

Runtime config and state live under `~/.claude/agent-loop/<project>/`, **outside this repo** — they
hold your webhook URLs and team IDs and are never committed.

---

## Why another agent loop?

Autonomous "agent loops" are a small and growing genre, and pitcrew is one opinionated take. Its
distinctive pieces:

- **Paced audit + QA intake** (`/manager-run`) — a producer that turns noisy findings into a steady,
  deduped trickle the rest of the crew can actually keep up with.
- **Coverage as a first-class crew member** (`/coverage-run`) — actively maps test-coverage gaps and
  files grounded flow PRs, instead of only reacting to bugs.
- **A per-repo autonomy ladder** for releases, with **agent-only scope** by default — you grant prod
  autonomy deliberately, per repo, and the crew never ships your own work behind your back.
- **Directed-target mode** — every loop skill also works as a one-shot you can aim by hand.
- **A Linear-binding resilience layer** — the loop survives the coordination MCP swapping or dropping
  mid-session without writing to the wrong place.

---

## License

MIT — see [LICENSE](LICENSE).
