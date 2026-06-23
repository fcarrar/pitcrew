#!/bin/bash
# pitcrew config wizard — interactively build ~/.claude/agent-loop/<project>/config.json
#
# Run standalone any time to (re)configure:   ./bin/configure.sh [project-name]
# install.sh calls this automatically when a project has no config yet.
#
# This configures the LOOP (which tracker, which repos, which webhooks). It never
# modifies your code repos — they are only referenced by path.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${1:-example}"
PROJECT_DIR="$HOME/.claude/agent-loop/$PROJECT"
CONFIG="$PROJECT_DIR/config.json"
EXAMPLE="$REPO_ROOT/references/config.example.json"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required. Install: brew install jq / apt-get install jq"; exit 1; }
[ -f "$EXAMPLE" ] || { echo "ERROR: $EXAMPLE not found — run from inside the pitcrew repo."; exit 1; }
mkdir -p "$PROJECT_DIR/state"

ask()     { local p="$1" d="${2:-}" a; if [ -n "$d" ]; then read -r -p "  $p [$d]: " a; printf '%s' "${a:-$d}"; else read -r -p "  $p: " a; printf '%s' "$a"; fi; }
confirm() { local a; read -r -p "  $1 [y/N]: " a; [[ "$a" =~ ^[Yy] ]]; }
setj()    { local t; t="$(mktemp)"; jq "$@" "$CONFIG" > "$t" && mv "$t" "$CONFIG"; }
expand()  { printf '%s' "${1/#\~/$HOME}"; }
detect_lang() {
  local p="$1"
  if   [ -f "$p/go.mod" ]; then echo go
  elif [ -f "$p/package.json" ]; then echo ts
  elif [ -f "$p/pyproject.toml" ] || [ -f "$p/requirements.txt" ]; then echo py
  elif [ -f "$p/Cargo.toml" ]; then echo rust
  else echo ""; fi
}

echo
echo "════════════════════════════════════════════════════════════════"
echo "  pitcrew config wizard   ·   project: $PROJECT"
echo "  Writes → $CONFIG"
echo
echo "  Configures the LOOP (tracker / repos / webhooks). It does NOT"
echo "  touch your code repos — they're only referenced by path."
echo "════════════════════════════════════════════════════════════════"

if [ -f "$CONFIG" ]; then
  confirm "config.json already exists — overwrite it?" || { echo "  Keeping existing config. Nothing changed."; exit 0; }
fi

cp "$EXAMPLE" "$CONFIG"
setj --arg p "$PROJECT" '.project_name = $p | (.manager.sources[].findings_json) |= gsub("<project>"; $p)'

# ── GitHub ──────────────────────────────────────────────────────
echo; echo "── GitHub ──"
GH_DEFAULT="$(gh api user -q .login 2>/dev/null || true)"
REVIEWER="$(ask "Your GitHub username (authors + reviews the loop's PRs)" "$GH_DEFAULT")"
ORG="$(ask "GitHub org/owner that hosts your repos" "$REVIEWER")"
setj --arg r "$REVIEWER" --arg o "$ORG" '.github.reviewer_login=$r | .github.org=$o'

# ── Linear ──────────────────────────────────────────────────────
echo; echo "── Linear (issue tracker + loop coordination) ──"
if confirm "Use Linear?"; then
  EMAIL_DEFAULT="$(git config --global user.email 2>/dev/null || true)"
  WS="$(ask "Workspace slug (the bit in linear.app/<slug>/...)" "")"
  TEAM="$(ask "Team name (e.g. Acme)" "")"
  echo "    team_id is the team's UUID — find it in Linear → team settings, or via the"
  echo "    Linear MCP list_teams. Leave blank to fill in later (skills warn until it's set)."
  TEAMID="$(ask "Team id (UUID)" "")"
  PREFIX="$(ask "Ticket prefix (e.g. ACME → ACME-123)" "")"
  EMAIL="$(ask "Your Linear account email (the loop assigns tickets here)" "$EMAIL_DEFAULT")"
  setj --arg ws "$WS" --arg t "$TEAM" --arg tid "$TEAMID" --arg px "$PREFIX" --arg em "$EMAIL" \
    '.linear.use=true | .linear.workspace_slug=$ws | .linear.team_name=$t | .linear.team_id=$tid | .linear.ticket_prefix=$px | .linear.assignee_email=$em'
else
  setj '.linear.use=false'
  echo "    Linear off — implementer/reviewer/manager/unblock sit out; qa/research still write ledgers."
fi

# ── Repos in loop scope ─────────────────────────────────────────
echo; echo "── Repos the crew may operate on ──"
echo "  Point the wizard at the folder holding your checkouts; it finds git repos and lets you pick."
REPOS='[]'
add_repo() {
  local name="$1" path="$2" branch lang
  branch="$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  lang="$(detect_lang "$path")"
  REPOS="$(jq -c --arg n "$name" --arg p "$path" --arg b "$branch" --arg l "$lang" \
    '. + [{name:$n, path:$p, default_branch:$b, lang:$l, tags:[]}]' <<<"$REPOS")"
  echo "    + $name  (lang=${lang:-?}, branch=$branch)"
}
CODE_ROOT="$(ask "Folder containing your repos (blank to add them manually)" "")"
if [ -n "$CODE_ROOT" ]; then
  CODE_ROOT="$(expand "$CODE_ROOT")"
  found=0
  for d in "$CODE_ROOT"/*/; do
    [ -d "${d}.git" ] || continue
    found=1
    name="$(basename "$d")"
    confirm "Include $name?" && add_repo "$name" "${d%/}"
  done
  [ "$found" = 0 ] && echo "    (no git repos found directly under $CODE_ROOT)"
fi
while confirm "Add a repo manually?"; do
  n="$(ask "repo name" "")"; p="$(expand "$(ask "local path" "")")"
  if [ -n "$n" ] && [ -n "$p" ]; then add_repo "$n" "$p"; else echo "    (skipped — name and path both required)"; fi
done
if [ "$REPOS" != '[]' ]; then
  setj --argjson r "$REPOS" '.repos = $r'
else
  echo "    (no repos added — keeping the example placeholders; edit repos[] in the config)"
fi

# ── Slack (optional) ────────────────────────────────────────────
echo; echo "── Slack (optional notifications) ──"
if confirm "Add Slack webhooks?"; then
  QAH="$(ask "qa/ops webhook URL" "")"
  QWH="$(ask "quick-wins/implementer webhook URL" "")"
  MEN="$(ask "your @-mention id (e.g. <@U012ABC>)" "")"
  setj --arg a "$QAH" --arg b "$QWH" --arg m "$MEN" \
    '.slack.qa_webhook_url=$a | .slack.quickwins_webhook_url=$b | .slack.user_mention=$m'
fi
TZ_GUESS="$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
TZV="$(ask "Timezone (IANA, for human-readable Slack timestamps)" "${TZ_GUESS:-Europe/Paris}")"
setj --arg t "$TZV" '.slack.timezone=$t'

echo "$PROJECT" > "$HOME/.claude/agent-loop/default.txt"

echo
echo "✓ Wrote $CONFIG"
jq -r '"  project=\(.project_name)   linear=\(.linear.use)   repos=\(.repos|length)   reviewer=\(.github.reviewer_login)"' "$CONFIG"
echo
echo "  Next:"
echo "    • Skim the config (esp. manager.sources[] + repos[].release if you use those skills)."
echo "    • Fill linear.team_id later if you left it blank."
echo "    • Smoke a skill:   /research-run $PROJECT"
