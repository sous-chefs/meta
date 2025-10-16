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

TOTAL_CANCELLED=0

for repo in "${REPOS[@]}"; do
  echo ""
  echo "🔎 Checking $repo..."
  
  # Get all in-progress runs
  RUNS=$(gh run list --repo "$repo" --status in_progress --json databaseId,workflowName,headBranch --limit 100 2>/dev/null || echo "[]")
  
  RUN_COUNT=$(echo "$RUNS" | jq '. | length')
  
  if [ "$RUN_COUNT" -gt 0 ]; then
    echo "  ⚠️  Found $RUN_COUNT in-progress run(s)"
    
    # Cancel each run
    echo "$RUNS" | jq -r '.[] | "\(.databaseId) \(.workflowName) (\(.headBranch))"' | while read -r run_id workflow_name branch; do
      echo "    ❌ Cancelling: $workflow_name - $branch (ID: $run_id)"
      gh run cancel "$run_id" --repo "$repo" 2>/dev/null || echo "      ⚠️  Failed to cancel run $run_id"
      ((TOTAL_CANCELLED++)) || true
    done
  else
    echo "  ✅ No in-progress runs"
  fi
done

echo ""
echo "✨ Done! Cancelled $TOTAL_CANCELLED workflow run(s)"
