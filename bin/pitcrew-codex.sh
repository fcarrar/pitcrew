#!/bin/bash
# pitcrew-codex.sh — run ONE pitcrew skill as a single headless Codex pass.
#
# Codex has no `/loop`, so this is what cron fires on a cadence (the Claude Code
# install uses `/loop` instead). See docs/CODEX.md for the crontab.
#
# Usage:  pitcrew-codex.sh <skill> [project]
#
# Env overrides:
#   CODEX_BIN      path to the codex CLI            (default: codex on PATH)
#   PITCREW_HOME   shared runtime root              (default: ~/.claude/agent-loop)
#   CODEX_SANDBOX  read-only|workspace-write|danger-full-access (default: workspace-write)
#
# Sandbox note: workspace-write lets the agent write the configured repos + the runtime
# dir, with network OFF. Skills that need network (e.g. `gh`/curl against an API) want a
# Codex profile that re-enables it, or CODEX_SANDBOX=danger-full-access. research-run /
# qa-run do their core work locally and run fine sandboxed.

set -uo pipefail

SKILL="${1:?usage: pitcrew-codex.sh <skill> [project]}"
HOME_DIR="${PITCREW_HOME:-$HOME/.claude/agent-loop}"
PROJECT="${2:-$(cat "$HOME_DIR/default.txt" 2>/dev/null || echo example)}"
CODEX_BIN="${CODEX_BIN:-codex}"
SANDBOX="${CODEX_SANDBOX:-workspace-write}"
PROMPT_FILE="$HOME/.codex/prompts/$SKILL.md"
PROJECT_DIR="$HOME_DIR/$PROJECT"

command -v "$CODEX_BIN" >/dev/null 2>&1 || { echo "pitcrew-codex: codex CLI not found ('$CODEX_BIN'). Set CODEX_BIN to the binary path."; exit 1; }
[ -f "$PROMPT_FILE" ] || { echo "pitcrew-codex: no prompt at $PROMPT_FILE — run ./bin/install-codex.sh first."; exit 1; }
[ -f "$PROJECT_DIR/config.json" ] || { echo "pitcrew-codex: no config at $PROJECT_DIR/config.json — run ./bin/configure.sh $PROJECT."; exit 1; }

# Make every configured repo path (plus the runtime dir) a writable root for the sandbox.
ADD_DIRS=(--add-dir "$PROJECT_DIR")
while IFS= read -r p; do
  p="${p/#\~/$HOME}"
  [ -n "$p" ] && [ -d "$p" ] && ADD_DIRS+=(--add-dir "$p")
done < <(jq -r '.repos[].path // empty' "$PROJECT_DIR/config.json" 2>/dev/null)

PROMPT="$(cat "$PROMPT_FILE")

---
Run ONE non-interactive pass for project: $PROJECT.
Resolve config from $PROJECT_DIR/config.json, do the work, then stop. Never ask for input."

# Feed the prompt on stdin (the skill body starts with a `---` frontmatter fence, which
# `codex exec` would otherwise parse as a flag). `-` tells codex to read from stdin.
printf '%s' "$PROMPT" | "$CODEX_BIN" exec \
  --sandbox "$SANDBOX" \
  --cd "$PROJECT_DIR" \
  "${ADD_DIRS[@]}" \
  --skip-git-repo-check \
  -
