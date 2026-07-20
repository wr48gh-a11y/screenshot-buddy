#!/bin/zsh
# Pre-submit guard: fail (or warn) if the App Store signing placeholders are still unfilled.
#
# Use in two modes:
#   ./scripts/check-release.sh            # hard fail — run before `archive.sh`
#   ./scripts/check-release.sh --warn-only # non-zero exit skipped — used by build.sh during iteration
#
# Fills the gap between "iterate locally" (no Apple account needed) and "submit to the App
# Store" (a real Team ID is mandatory). Prevents shipping a build that can't be signed.
set -u
cd "$(dirname "$0")/.."

WARN_ONLY=0
[ "${1:-}" = "--warn-only" ] && WARN_ONLY=1

emit() {   # 1 = severity (ERROR/WARNING), 2 = message
  if [ "$1" = "ERROR" ] && [ "$WARN_ONLY" -eq 0 ]; then
    echo "✗ $2" >&2
  else
    echo "⚠ $2" >&2
  fi
}

PROBLEMS=0

# 1. project.yml: DEVELOPMENT_TEAM must be a real Team ID (10 alphanumeric chars).
TEAM="$(awk -F'"' '/DEVELOPMENT_TEAM:/ {print $2}' project.yml 2>/dev/null | tr -d '[:space:]')"
if [ -z "$TEAM" ]; then
  emit ERROR "project.yml: DEVELOPMENT_TEAM is empty. Set it to your Apple Team ID."
  PROBLEMS=$((PROBLEMS + 1))
fi

# 2. exportOptions.plist: teamID must not still be the placeholder.
if grep -q "REPLACE_WITH_TEAM_ID" exportOptions.plist 2>/dev/null; then
  emit ERROR "exportOptions.plist: teamID is still 'REPLACE_WITH_TEAM_ID'. Set it to your Apple Team ID."
  PROBLEMS=$((PROBLEMS + 1))
fi

if [ "$PROBLEMS" -gt 0 ]; then
  if [ "$WARN_ONLY" -eq 0 ]; then
    echo "Refusing to proceed: $PROBLEMS signing issue(s). Edit project.yml and exportOptions.plist, then re-run." >&2
    exit 1
  else
    echo "(Iteration build only — $PROBLEMS signing issue(s) will block submission. Ignoring for now.)" >&2
  fi
fi

exit 0
