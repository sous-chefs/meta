#!/usr/bin/env bash
# Script to automate updating a cookbook to use the release pipeline
# Usage: ./update-release-pipeline.sh <repo-name>

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ORG="sous-chefs"
WORKFLOW_VERSION="5.0.3"
BRANCH_NAME="release-pipeline"

# Check arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Repository name required${NC}"
    echo "Usage: $0 <repo-name>"
    echo "Example: $0 isc_kea"
    exit 1
fi

REPO_NAME="$1"
REPO_PATH="$REPO_NAME"

# Verify repo exists
if [ ! -d "$REPO_PATH" ]; then
    echo -e "${RED}Error: Repository directory not found: $REPO_PATH${NC}"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Release Pipeline Migration for ${REPO_NAME}${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Disable webhooks
echo -e "${YELLOW}[1/8] Disabling webhooks...${NC}"
./manage-webhooks.sh disable "$REPO_NAME"
echo ""

# Step 2: Create branch
echo -e "${YELLOW}[2/8] Creating feature branch...${NC}"
cd "$REPO_PATH"
git checkout main
git pull
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
echo -e "${GREEN}✓ Branch '$BRANCH_NAME' ready${NC}"
echo ""

# Step 3: Get current version from metadata.rb
echo -e "${YELLOW}[3/8] Reading cookbook version...${NC}"
if [ ! -f "metadata.rb" ]; then
    echo -e "${RED}Error: metadata.rb not found${NC}"
    exit 1
fi

VERSION=$(grep "^version" metadata.rb | sed "s/version[[:space:]]*['\"]//g" | sed "s/['\"]//g" | tr -d ' ')
echo -e "${GREEN}✓ Current version: $VERSION${NC}"
echo ""

# Step 4: Update workflow files
echo -e "${YELLOW}[4/8] Updating workflow files...${NC}"

# Update ci.yml
if [ -f ".github/workflows/ci.yml" ]; then
    echo "  Updating ci.yml..."
    sed -i '' "s/@[0-9]\+\.[0-9]\+\.[0-9]\+/@${WORKFLOW_VERSION}/g" .github/workflows/ci.yml
    sed -i '' "s/actionshub\/chef-install@[0-9]\+\.[0-9]\+\.[0-9]\+/actionshub\/chef-install@main/g" .github/workflows/ci.yml
    sed -i '' "s/actionshub\/test-kitchen@[0-9]\+\.[0-9]\+\.[0-9]\+/actionshub\/test-kitchen@main/g" .github/workflows/ci.yml
    
    # Add secrets: inherit if not present
    if ! grep -q "secrets: inherit" .github/workflows/ci.yml; then
        # Add after permissions block
        perl -i -pe 's/(permissions:.*?\n(?:.*?\n)*?)(  integration:)/\1    secrets: inherit\n\n\2/s' .github/workflows/ci.yml
    fi
fi

# Create/Update release.yml with permissions block
echo "  Creating release.yml..."
cat > .github/workflows/release.yml << 'EOF'
---
name: release

"on":
  push:
    branches:
      - main

permissions:
  contents: write
  issues: write
  pull-requests: write
  packages: write
  attestations: write
  id-token: write

jobs:
  release:
    uses: sous-chefs/.github/.github/workflows/release-cookbook.yml@5.0.3
    secrets:
      token: ${{ secrets.PORTER_GITHUB_TOKEN }}
      supermarket_user: ${{ secrets.CHEF_SUPERMARKET_USER }}
      supermarket_key: ${{ secrets.CHEF_SUPERMARKET_KEY }}
EOF

# Create conventional-commits.yml
echo "  Creating conventional-commits.yml..."
cat > .github/workflows/conventional-commits.yml << 'EOF'
---
name: conventional-commits

"on":
  pull_request:
    types:
      - opened
      - reopened
      - edited
      - synchronize

jobs:
  conventional-commits:
    uses: sous-chefs/.github/.github/workflows/conventional-commits.yml@5.0.3
EOF

# Create prevent-file-change.yml
echo "  Creating prevent-file-change.yml..."
cat > .github/workflows/prevent-file-change.yml << 'EOF'
---
name: prevent-file-change

"on":
  pull_request:
    types:
      - opened
      - reopened
      - edited
      - synchronize

jobs:
  prevent-file-change:
    uses: sous-chefs/.github/.github/workflows/prevent-file-change.yml@5.0.3
    secrets:
      token: ${{ secrets.GITHUB_TOKEN }}
EOF

# Create copilot-setup-steps.yml
echo "  Creating copilot-setup-steps.yml..."
cat > .github/workflows/copilot-setup-steps.yml << 'EOF'
---
name: 'Copilot Setup Steps'

"on":
  workflow_dispatch:
  push:
    paths:
      - .github/workflows/copilot-setup-steps.yml
  pull_request:
    paths:
      - .github/workflows/copilot-setup-steps.yml

jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Check out code
        uses: actions/checkout@v5
      - name: Install Chef
        uses: actionshub/chef-install@main
      - name: Install cookbooks
        run: berks install
EOF

# Create/Update .markdownlint-cli2.yaml
echo "  Creating .markdownlint-cli2.yaml..."
cat > .markdownlint-cli2.yaml << 'EOF'
config:
  ul-indent: false # MD007
  line-length: false # MD013
  no-duplicate-heading: false # MD024
  reference-links-images: false # MD052
  no-multiple-blanks:
    maximum: 2
ignores:
  - .github/copilot-instructions.md
EOF

echo -e "${GREEN}✓ Workflow files updated${NC}"
echo ""

# Step 5: Configure release-please config
echo -e "${YELLOW}[5/8] Configuring release-please...${NC}"

# Create release-please-config.json
cat > release-please-config.json << EOF
{
  "packages": {
    ".": {
      "package-name": "$REPO_NAME",
      "changelog-path": "CHANGELOG.md",
      "release-type": "ruby",
      "include-component-in-tag": false,
      "version-file": "metadata.rb"
    }
  },
  "\$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json"
}
EOF

# Create .release-please-manifest.json with current version
cat > .release-please-manifest.json << EOF
{
  ".": "$VERSION"
}
EOF

echo -e "${GREEN}✓ Release-please configured (version: $VERSION)${NC}"
echo ""

# Step 6: Clean up CHANGELOG
echo -e "${YELLOW}[6/8] Cleaning up CHANGELOG...${NC}"
if [ -f "CHANGELOG.md" ]; then
    # Remove Unreleased section
    sed -i '' '/^## Unreleased$/,/^## [0-9]/{ /^## Unreleased$/d; /^$/d; }' CHANGELOG.md
    
    # Convert - to *
    sed -i '' 's/^- /* /g' CHANGELOG.md
    
    # Remove tickets.opscode.com and tickets.chef.io references
    perl -i -pe 's/\*\*\[COOK-\d+\]\(https?:\/\/tickets\.(opscode\.com|chef\.io)\/browse\/COOK-\d+\)\*\*\s*-?\s*//g' CHANGELOG.md
    perl -i -pe 's/\[COOK-\d+\]\(https?:\/\/tickets\.(opscode\.com|chef\.io)\/browse\/COOK-\d+\)\s*-?\s*//g' CHANGELOG.md
    perl -i -pe 's/^\* \*/*/g' CHANGELOG.md
    perl -i -pe 's/^\*([A-Z])/* $1/g' CHANGELOG.md
    
    # Remove empty versions
    perl -i -0pe 's/^## (\d+\.\d+\.\d+.*?)\n\n(?=## )/## $1 (empty - removed)\n\n/gm; s/^## .*?\(empty - removed\)\n\n//gm' CHANGELOG.md
    
    # Remove excessive blank lines
    awk 'BEGIN{blank=0} /^$/{blank++; if(blank<=1) print; next} {blank=0; print}' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
    
    echo -e "${GREEN}✓ CHANGELOG cleaned up${NC}"
else
    echo -e "${YELLOW}⚠ No CHANGELOG.md found${NC}"
fi
echo ""

# Step 7: Run linters and auto-fix
echo -e "${YELLOW}[7/9] Running linters...${NC}"

# Run cookstyle auto-correct
if command -v cookstyle &> /dev/null; then
    echo "  Running cookstyle -A..."
    cookstyle -A || true
    echo -e "${GREEN}✓ Cookstyle auto-corrections applied${NC}"
else
    echo -e "${YELLOW}⚠ cookstyle not found, skipping${NC}"
fi

# Run markdownlint auto-fix
if command -v markdownlint-cli2 &> /dev/null; then
    echo "  Running markdownlint-cli2 --fix..."
    markdownlint-cli2 "**/*.md" "!vendor" "!.venv" --fix || true
    echo -e "${GREEN}✓ Markdownlint auto-corrections applied${NC}"
else
    echo -e "${YELLOW}⚠ markdownlint-cli2 not found, skipping${NC}"
fi
echo ""

# Step 8: Commit and push
echo -e "${YELLOW}[8/9] Committing changes...${NC}"
git add .github/workflows/ .release-please-manifest.json release-please-config.json .markdownlint-cli2.yaml CHANGELOG.md 2>/dev/null || true
# Also add any files modified by linters
git add . 2>/dev/null || true
git commit -s -m "fix(ci): Update workflows to use release pipeline"
git push -u origin "$BRANCH_NAME"
echo -e "${GREEN}✓ Changes pushed to $BRANCH_NAME${NC}"
echo ""

# Step 9: Create PR and update branch protection
echo -e "${YELLOW}[9/9] Creating pull request...${NC}"

# Try to create PR, or get existing PR URL
PR_OUTPUT=$(gh pr create \
  --title "fix(ci): Update workflows to use release pipeline" \
  --body "Updates workflows to @${WORKFLOW_VERSION}.

## Changes
- Updated ci.yml to @${WORKFLOW_VERSION} with secrets: inherit
- Created release.yml with permissions block
- Created conventional-commits.yml, prevent-file-change.yml, copilot-setup-steps.yml
- Created/updated .markdownlint-cli2.yaml
- Created/updated release-please config files (version: $VERSION)
- Cleaned up CHANGELOG.md

## Webhooks
- Webhooks disabled prior to merge" 2>&1 || true)

# Extract PR URL from output
PR_URL=$(echo "$PR_OUTPUT" | grep -o 'https://github.com/[^[:space:]]*' | head -1)

if [ -z "$PR_URL" ]; then
    # PR might already exist, try to get it
    PR_URL=$(gh pr view "$BRANCH_NAME" --json url -q .url 2>/dev/null || echo "")
    if [ -n "$PR_URL" ]; then
        echo -e "${YELLOW}⚠ PR already exists: $PR_URL${NC}"
    else
        echo -e "${RED}⚠ Could not create or find PR${NC}"
    fi
else
    echo -e "${GREEN}✓ Pull request created: $PR_URL${NC}"
fi
echo ""

echo -e "${YELLOW}Updating branch protection...${NC}"
../manage-branch-protection.sh "$ORG/$REPO_NAME"
echo ""

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ Migration Complete!${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Pull Request:${NC} $PR_URL"
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Review the PR and ensure CI checks pass"
echo "  2. Merge the PR when ready"
echo "  3. Monitor the first release to ensure it works correctly"
echo ""
