# Linear Access — binding-agnostic + degraded-mode (agent-loop resilience layer)

Every loop skill coordinates through Linear. Historically each skill hardcoded the
`mcp__linear-server__*` tool family. That broke once when the OAuth
`linear-server` MCP (HTTP → `mcp.linear.app`) disconnected mid-session and the
`claude.ai Linear` connector silently took over — the skills kept calling a dead tool
prefix and would have bailed at STEP −1 as if "pointing at the wrong Linear" (learned
from a past binding-swap incident).

This file is the canonical contract. Every skill reads it (or inlines the **BINDING
BLOCK** below) at the very top of its run, before any Linear call.

---

## 1. BINDING BLOCK — detect the live Linear MCP each fire

Linear may be reachable under **different** tool families depending on the harness, and
which one is live can change between fires. Detect by **capability, not by a fixed name**:

| Harness / binding | Tool prefix (example) | How it's wired |
|---|---|---|
| Claude Code — Linear's official remote MCP | `mcp__linear-server__*` | project-scoped `type:http` → `mcp.linear.app/mcp` (OAuth) |
| Claude Code — claude.ai Linear connector | `mcp__claude_ai_Linear__*` | claude.ai-managed connector |
| Codex — `linear` MCP server | (the prefix Codex assigns) | `[mcp_servers.linear]` in `~/.codex/config.toml` |

**At run start, before any Linear operation:**

1. Look at the tools actually available to you THIS fire and pick the live Linear family
   **by capability** — the one that exposes `list_teams` / `get_issue` / `save_issue` /
   `save_comment` / `list_issue_labels` / `list_issue_statuses` / … (same operations + arg
   shapes across every family). Set `LINEAR` to its prefix:
   - Claude Code: `mcp__linear-server__*`, else `mcp__claude_ai_Linear__*`.
   - Codex: the `linear` server from `~/.codex/config.toml` (whatever prefix Codex gives it).
   - Only the **prefix** (and how prefix+op are joined) differs — so wherever a skill says
     `mcp__linear-server__<op>`, call the live family's `<op>` tool under whatever name your
     harness actually exposes it.
2. **Confirm it's the right workspace.** Call the live family's `list_teams` and verify the
   configured team is present (matching `linear.team_id` from config). If the live binding is
   authed to a *different* workspace, treat Linear as **down** (do not write into the wrong
   workspace) → degraded mode (§2).
3. Use the resolved Linear family for every Linear call for the rest of the fire. Wherever a
   skill body says `mcp__linear-server__X`, read it as the same operation `X` on that family.

> Skills are written with `mcp__linear-server__*` literals for readability. The BINDING
> BLOCK makes that prefix a **variable**, not a hardcode. If a skill says
> `mcp__linear-server__save_issue`, you call `<LINEAR>__save_issue` with the live prefix.

---

## 2. DEGRADED MODE — no live Linear binding

If **neither** Linear family is available (or the only live one is the wrong workspace):

- **Do NOT bail blind.** A silent exit looks identical to "the loop is dead".
- Refresh-read is impossible, so fall back to the **board cache** (§3): you may *read* the
  last snapshot to answer read-only questions, but you may **not** pretend a write
  succeeded.
- Log exactly one line: `<skill>: Linear unreachable (no live binding) — degraded mode, no writes this fire. Cache age: <ISO|none>.`
- For an agent whose whole job is Linear writes (implementer/reviewer/research/qa/unblock/
  investigate): exit cleanly after the log. Next fire retries — when a binding returns,
  the loop resumes with zero lost state (Linear is the SoR; nothing was written while down).
- For an agent that ALSO acts outside Linear (ops-run health polling, releaser-run
  deploys): it MAY still do its non-Linear work, but it MUST NOT take a side-effecting
  action whose safety depends on a Linear read it couldn't refresh (e.g. releaser must not
  deploy a ticket it can't confirm is merged+green). When in doubt, treat the
  Linear-dependent branch as blocked and do only the safe, read-grounded work.

**Never** invent a third Linear source or write to a wrong-workspace binding to "get
unstuck". Degraded mode is read-only-and-wait, by design.

---

## 3. Board cache — read-through snapshot (NOT a competing source of truth)

Path: `~/.claude/agent-loop/<project>/board-cache/`.

- Linear stays the **single source of truth** whenever a binding is live.
- On every **healthy** fire, after a skill has queried the issues it cares about, it MAY
  write a compact snapshot to `board-cache/<state>.json` (issue id, identifier, title,
  state, labels, updatedAt). Cheap, best-effort, overwrites the prior snapshot.
- The cache exists ONLY so degraded-mode fires can answer "what was the board roughly like"
  for read-only reporting. It is never replayed as writes, never merged back, never
  authoritative. When Linear returns, the live read wins unconditionally.
- `config.backend.cache_dir` overrides the subdirectory name; `config.backend.mode` is
  `"linear"` (default — this contract) and is the seam where a future `"local"` full
  backend would plug in (reserved; not built).

---

## 4. One-line summary for skill authors

> Prepend the BINDING BLOCK. Resolve `<LINEAR>` once. Use `<LINEAR>__*` everywhere a skill
> says `mcp__linear-server__*`. If neither family is live or it's the wrong workspace,
> log one line and degrade to read-only — never bail blind, never write to the wrong place.
