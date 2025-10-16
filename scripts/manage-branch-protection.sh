#!/usr/bin/env bash

set -euo pipefail

# Configuration
BRANCH="main"
REQUIRED_CHECKS=(
  "lint-unit / runner / Check Metadata"
  "lint-unit / runner / Cookstyle"
  "lint-unit / runner / RSpec ubuntu-latest"
  "lint-unit / runner / markdownlint"
  "lint-unit / runner / yamllint"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Get repository from argument or auto-detect
if [ $# -eq 1 ]; then
    REPO="$1"
else
    # Try to auto-detect from git repository
    if git rev-parse --git-dir > /dev/null 2>&1; then
        REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    else
        echo -e "${RED}Error: Repository name required${NC}"
        echo "Usage: $0 <org/repo-name>"
        echo "Example: $0 sous-chefs/apache2"
        exit 1
    fi
fi

echo -e "${GREEN}Repository: ${REPO}${NC}"
echo -e "${GREEN}Branch: ${BRANCH}${NC}"
echo ""

# Function to check existing status checks
check_existing_status_checks() {
    echo -e "${YELLOW}Checking existing status checks on ${BRANCH}...${NC}"
    
    # Get branch protection rules
    PROTECTION=$(gh api "repos/${REPO}/branches/${BRANCH}/protection" 2>/dev/null || echo "{}")
    
    if [ "$PROTECTION" = "{}" ]; then
        echo -e "${YELLOW}No branch protection found on ${BRANCH}${NC}"
        return 1
    fi
    
    # Extract required status checks
    EXISTING_CHECKS=$(echo "$PROTECTION" | jq -r '.required_status_checks.contexts[]?' 2>/dev/null || echo "")
    
    if [ -z "$EXISTING_CHECKS" ]; then
        echo -e "${YELLOW}No status checks configured${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Existing status checks:${NC}"
    echo "$EXISTING_CHECKS" | while read -r check; do
        echo "  - $check"
    done
    echo ""
    
    return 0
}

# Function to remove existing status checks
remove_status_checks() {
    echo -e "${YELLOW}Removing existing status checks...${NC}"
    
    # Get current protection settings
    PROTECTION=$(gh api "repos/${REPO}/branches/${BRANCH}/protection" 2>/dev/null || echo "{}")
    
    if [ "$PROTECTION" = "{}" ]; then
        echo -e "${YELLOW}No branch protection to remove${NC}"
        return 0
    fi
    
    # Check if required_status_checks exists
    HAS_STATUS_CHECKS=$(echo "$PROTECTION" | jq -r 'has("required_status_checks")')
    
    if [ "$HAS_STATUS_CHECKS" = "false" ]; then
        echo -e "${YELLOW}No status checks to remove${NC}"
        return 0
    fi
    
    # Remove required status checks by setting empty array
    gh api \
        --method PATCH \
        "repos/${REPO}/branches/${BRANCH}/protection/required_status_checks" \
        --input - <<< '{"strict":false,"contexts":[]}' \
        > /dev/null
    
    echo -e "${GREEN}Status checks removed${NC}"
    echo ""
}

# Function to add new status checks
add_status_checks() {
    echo -e "${YELLOW}Adding new status checks...${NC}"
    
    # Build JSON array for contexts
    CONTEXTS_JSON=$(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -s .)
    
    # Check if branch protection exists
    PROTECTION=$(gh api "repos/${REPO}/branches/${BRANCH}/protection" 2>/dev/null || echo "{}")
    
    if [ "$PROTECTION" = "{}" ]; then
        echo -e "${RED}Error: Branch protection must be enabled first${NC}"
        echo "Enable it via: Settings > Branches > Branch protection rules"
        exit 1
    fi
    
    # Update required status checks
    PAYLOAD=$(jq -n --argjson contexts "$CONTEXTS_JSON" '{strict: false, contexts: $contexts}')
    gh api \
        --method PATCH \
        "repos/${REPO}/branches/${BRANCH}/protection/required_status_checks" \
        --input - <<< "$PAYLOAD" \
        > /dev/null
    
    echo -e "${GREEN}Added status checks:${NC}"
    for check in "${REQUIRED_CHECKS[@]}"; do
        echo "  - $check"
    done
    echo ""
}

# Main execution
echo "========================================="
echo "GitHub Branch Protection Manager"
echo "========================================="
echo ""

# Step 1: Check existing status checks
if check_existing_status_checks; then
    # Step 2: Remove existing status checks
    remove_status_checks
fi

# Step 3: Add new status checks
add_status_checks

# Step 4: Verify the changes
echo -e "${GREEN}Verifying changes...${NC}"
check_existing_status_checks

echo -e "${GREEN}✓ Branch protection status checks updated successfully!${NC}"
