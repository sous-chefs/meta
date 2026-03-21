#!/usr/bin/env bash
# Script to bulk cancel in-progress GitHub Actions workflow runs
# Usage: ./cancel-workflow-runs.sh [org-name] [optional: specific-repo]

set -euo pipefail

ORG="${1:-sous-chefs}"
REPO="${2:-}"

echo "🔍 Finding in-progress workflow runs for organization: $ORG"

if [ -n "$REPO" ]; then
  # Cancel runs for a specific repository
  REPOS=("$ORG/$REPO")
else
  # Get all repositories in the organization
  echo "📋 Fetching all repositories..."
  REPOS=($(gh repo list "$ORG" --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner'))
fi

# Process one repo: list in-progress runs and cancel them
_cancel_repo() {
  local repo=$1
  echo ""
  echo "🔎 Checking $repo..."

  local RUNS
  RUNS=$(gh run list --repo "$repo" --status in_progress \
    --json databaseId,workflowName,headBranch --limit 100 2>/dev/null || echo "[]")

  local RUN_COUNT
  RUN_COUNT=$(echo "$RUNS" | jq 'length')

  if [ "$RUN_COUNT" -gt 0 ]; then
    echo "  ⚠️  Found $RUN_COUNT in-progress run(s)"
    echo "$RUNS" | jq -r '.[] | "\(.databaseId) \(.workflowName) (\(.headBranch))"' \
      | while read -r run_id workflow_name branch; do
          echo "    ❌ Cancelling: $workflow_name - $branch (ID: $run_id)"
          gh run cancel "$run_id" --repo "$repo" 2>/dev/null \
            || echo "      ⚠️  Failed to cancel run $run_id"
        done
  else
    echo "  ✅ No in-progress runs"
  fi
}
export -f _cancel_repo

# Run up to 8 repo checks concurrently (I/O-bound — safe to parallelise)
printf '%s\n' "${REPOS[@]}" | xargs -P 8 -I {} bash -c '_cancel_repo "$@"' _ {}

echo ""
echo "✨ Done!"
