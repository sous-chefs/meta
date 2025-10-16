#!/usr/bin/env fish
# Script to create workflow-overhaul branches and commits for all repositories

set REPOS apt ark atom autofs bind bot-trainer bsdcpio certificate chef_auto_accumulator chef_ca chrony cinc-omnibus confluence consul control_groups

set COMMIT_MSG_TITLE "feat(ci): migrate to reusable workflows v4.1.0"
set COMMIT_MSG_BODY \
    "Update ci.yml to use lint-unit workflow v4.1.0" \
    "Add conventional-commits workflow for PR validation" \
    "Add prevent-file-change workflow for metadata protection" \
    "Add release workflow using release-cookbook v4.1.0" \
    "Add release-please configuration files" \
    "Use secrets: inherit for proper secret propagation"

echo "🚀 Creating workflow-overhaul branches and commits"
echo "================================================"
echo ""

for repo in $REPOS
    set repo_path "/Users/damacus/repos/sous-chefs/$repo"

    if not test -d $repo_path
        echo "❌ Repository not found: $repo"
        continue
    end

    echo "📦 Processing $repo..."
    cd $repo_path

    # Create branch
    echo "  🌿 Creating branch workflow-overhaul..."
    git checkout -b workflow-overhaul 2>/dev/null
    or begin
        echo "  ⚠️  Branch already exists, checking it out..."
        git checkout workflow-overhaul
    end

    # Stage files
    echo "  📝 Staging workflow files..."
    git add .github/workflows/ release-please-config.json .release-please-manifest.json .markdownlint-cli2.yaml

    # Create commit
    echo "  💾 Creating commit..."
    set commit_args -m $COMMIT_MSG_TITLE
    for msg in $COMMIT_MSG_BODY
        set commit_args $commit_args -m $msg
    end

    if git commit $commit_args
        echo "  ✅ Commit created successfully"
    else
        echo "  ⚠️  Commit failed or nothing to commit"
    end

    echo ""
end

echo "✨ Done! All repositories processed."
echo ""
echo "Next steps:"
echo "1. Review the commits in each repository"
echo "2. Run ./create-prs.fish to create pull requests"
