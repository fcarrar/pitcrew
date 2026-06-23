#!/bin/bash
# pitcrew Codex installer — wire pitcrew into the OpenAI Codex CLI.
#
# RUN THIS FROM INSIDE THE pitcrew CLONE. It does NOT touch your project repos.
#
# Same skill bodies as the Claude Code install — only the adapter differs:
#   1. Symlinks each skill (skills/<slug>/SKILL.md) → ~/.codex/prompts/<slug>.md
#      (Codex custom prompts → `/research-run` etc. work in the Codex TUI).
#   2. Seeds the SHARED runtime config at ~/.claude/agent-loop/<project>/ — the same
#      dir the Claude install uses, so one config drives both harnesses. (The "claude"
#      in the path is just the directory name; it's harness-neutral. Override with
#      $PITCREW_HOME if you want a different location — see docs/CODEX.md.)
#   3. Codex has no `/loop`. Schedule the skills via cron + bin/pitcrew-codex.sh
#      (this script prints a ready-to-paste crontab; full guide in docs/CODEX.md).
#
# Usage (from the repo root or its bin/ dir):
#   ./bin/install-codex.sh [project-name] [--no-wizard]

set -euo pipefail

NO_WIZARD=0
PROJECT=""
for arg in "$@"; do
  case "$arg" in
    --no-wizard) NO_WIZARD=1 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 2 ;;
    *) [ -z "$PROJECT" ] && PROJECT="$arg" ;;
  esac
done
PROJECT="${PROJECT:-example}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPTS_DIR="$HOME/.codex/prompts"
PROJECT_DIR="${PITCREW_HOME:-$HOME/.claude/agent-loop}/$PROJECT"
DEFAULT_FILE="${PITCREW_HOME:-$HOME/.claude/agent-loop}/default.txt"

SKILLS=(
  research-run qa-run implementer-run reviewer-run validator-run unblock
  investigate-run stale-sweep ops-run releaser-run manager-run coverage-run
)

echo "=== pitcrew Codex installer ==="
echo "  This wires pitcrew (this repo) into the Codex CLI. Your project repos are"
echo "  untouched — they're only referenced by path in the config."
echo
echo "  pitcrew repo:  $REPO_ROOT"
echo "  prompts dir:   $PROMPTS_DIR    (Codex custom prompts → slash commands)"
echo "  project:       $PROJECT"
echo "  runtime dir:   $PROJECT_DIR    (shared with the Claude install)"
echo

[ -d "$REPO_ROOT/skills" ] && [ -d "$REPO_ROOT/references" ] || {
  echo "ERROR: not a pitcrew checkout (missing skills/ or references/). Run from inside the repo."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found. Install: brew install jq / apt-get install jq"; exit 1; }
command -v codex >/dev/null 2>&1 || echo "  NOTE: 'codex' CLI not found on PATH — install it before scheduling loops (https://github.com/openai/codex)."
echo

# Step 1: symlink skills → Codex custom prompts
echo "[1/3] Symlinking skills into Codex prompts..."
mkdir -p "$PROMPTS_DIR"
linked=0
for slug in "${SKILLS[@]}"; do
  src="$REPO_ROOT/skills/$slug/SKILL.md"
  dst="$PROMPTS_DIR/$slug.md"
  [ -f "$src" ] || { echo "  ! skipped $slug (no SKILL.md)"; continue; }
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "  = already linked: $slug"
  else
    rm -f "$dst"; ln -s "$src" "$dst"; echo "  + $slug.md -> skills/$slug/SKILL.md"
  fi
  linked=$((linked+1))
done
echo "  linked $linked skills as Codex prompts"
echo

# Step 2: shared runtime config (reuse the harness-agnostic wizard)
echo "[2/3] Configuring project '$PROJECT' (shared runtime)..."
mkdir -p "$PROJECT_DIR/state"
if [ -f "$PROJECT_DIR/config.json" ]; then
  echo "  = config.json already exists — leaving it. Re-run: ./bin/configure.sh $PROJECT"
elif [ "$NO_WIZARD" = 1 ] || [ ! -t 0 ]; then
  cp "$REPO_ROOT/references/config.example.json" "$PROJECT_DIR/config.json"
  echo "  + copied references/config.example.json (wizard skipped). Edit: $PROJECT_DIR/config.json"
else
  "$REPO_ROOT/bin/configure.sh" "$PROJECT" || {
    echo "  (wizard exited early — copied the example to edit by hand)"
    [ -f "$PROJECT_DIR/config.json" ] || cp "$REPO_ROOT/references/config.example.json" "$PROJECT_DIR/config.json"; }
fi
for doc in TOPOLOGY LINEAR-ACCESS DIRECTED-TARGET; do
  cp -f "$REPO_ROOT/references/$doc.md" "$PROJECT_DIR/$doc.md"
done
[ -f "$PROJECT_DIR/lessons.md" ] || printf '# Agent-Loop Lessons (project: %s)\n\nPer-operator corrections the skills read each fire. Never committed.\n' "$PROJECT" > "$PROJECT_DIR/lessons.md"
echo "$PROJECT" > "$DEFAULT_FILE"
echo "  = runtime ready: $PROJECT_DIR"
echo

# Step 3: scheduling (Codex has no /loop → cron)
echo "[3/3] Scheduling — Codex has no /loop, so use cron + bin/pitcrew-codex.sh."
echo
echo "  Paste into \`crontab -e\` (adjust cadences; logs to ~/.codex/logs/):"
echo "  ----------------------------------------------------------------------"
RUNNER="$REPO_ROOT/bin/pitcrew-codex.sh"
cat <<CRON
  */30 *  * * *  $RUNNER research-run $PROJECT     >> ~/.codex/logs/research-run.log 2>&1
  0    */2 * * *  $RUNNER qa-run $PROJECT           >> ~/.codex/logs/qa-run.log 2>&1
  */15 *  * * *  $RUNNER implementer-run $PROJECT   >> ~/.codex/logs/implementer-run.log 2>&1
  */15 *  * * *  $RUNNER reviewer-run $PROJECT      >> ~/.codex/logs/reviewer-run.log 2>&1
  0    *  * * *  $RUNNER manager-run $PROJECT       >> ~/.codex/logs/manager-run.log 2>&1
CRON
echo "  ----------------------------------------------------------------------"
echo
echo "=== Install complete ==="
echo "  • research-run + qa-run need no Linear MCP (they write ledgers) — run as-is."
echo "  • Linear-coupled skills need a Linear MCP entry in ~/.codex/config.toml and a"
echo "    Codex tool-name branch in the LINEAR BINDING block — see docs/CODEX.md."
echo "  • Smoke one pass now:   ./bin/pitcrew-codex.sh research-run $PROJECT"
