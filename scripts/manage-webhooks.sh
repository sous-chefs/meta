#!/usr/bin/env bash
# Script to manage GitHub repository webhooks
# Usage: ./manage-webhooks.sh [check|disable] [repo1] [repo2] ...

set -euo pipefail

ORG="sous-chefs"
ACTION="${1:-check}"
shift || true

# If no repos specified, use default list
if [[ $# -eq 0 ]]; then
  REPOS=("appveyor-ci" "aptly" "atlantis" "aws" "beyondcompare")
else
  REPOS=("$@")
fi

check_webhooks() {
  local repo=$1
  echo "🔍 Checking webhooks for $ORG/$repo..."

  # Fetch once; reuse for display and count (was 2 API calls)
  local WEBHOOKS_JSON
  WEBHOOKS_JSON=$(gh api "repos/$ORG/$repo/hooks" 2>/dev/null || echo "[]")

  if [[ "$WEBHOOKS_JSON" = "[]" ]]; then
    echo "  ℹ️  No webhooks found"
    return 0
  fi

  # Parse and display webhook status
  echo "$WEBHOOKS_JSON" | jq -r '.[] | select(.active == false) | "  ✅ Webhook \(.id) (\(.name)) - DISABLED - \(.config.url)"'
  echo "$WEBHOOKS_JSON" | jq -r '.[] | select(.active == true) | "  ⚠️  Webhook \(.id) (\(.name)) - ACTIVE - \(.config.url)"'

  local ACTIVE_COUNT
  ACTIVE_COUNT=$(echo "$WEBHOOKS_JSON" | jq '[.[] | select(.active == true)] | length')

  if [[ "$ACTIVE_COUNT" -eq 0 ]]; then
    echo "  ✅ All webhooks are disabled"
  else
    echo "  ⚠️  $ACTIVE_COUNT active webhook(s) found"
  fi
}

disable_webhooks() {
  local repo=$1
  echo "🔧 Disabling webhooks for $ORG/$repo..."

  # Get all active webhooks
  WEBHOOK_IDS=$(gh api "repos/$ORG/$repo/hooks" --jq '.[] | select(.active == true) | .id' 2>/dev/null || echo "")

  if [[ -z "$WEBHOOK_IDS" ]]; then
    echo "  ✅ No active webhooks to disable"
    return 0
  fi

  # Disable each webhook
  while IFS= read -r webhook_id; do
    if [[ -n "$webhook_id" ]]; then
      echo "  🔒 Disabling webhook $webhook_id..."
      gh api -X PATCH "repos/$ORG/$repo/hooks/$webhook_id" -F active=false > /dev/null
      echo "  ✅ Webhook $webhook_id disabled"
    fi
  done <<< "$WEBHOOK_IDS"
}

# Main execution
echo "================================================"
echo "GitHub Webhook Manager"
echo "Organization: $ORG"
echo "Action: $ACTION"
echo "Repositories: ${REPOS[*]}"
echo "================================================"
echo ""

for repo in "${REPOS[@]}"; do
  case "$ACTION" in
    check)
      check_webhooks "$repo"
      ;;
    disable)
      disable_webhooks "$repo"
      echo ""
      check_webhooks "$repo"
      ;;
    *)
      echo "❌ Invalid action: $ACTION"
      echo "Usage: $0 [check|disable] [repo1] [repo2] ..."
      exit 1
      ;;
  esac
  echo ""
done

echo "✨ Done!"
