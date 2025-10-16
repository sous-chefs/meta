#!/usr/bin/env fish
# Script to force merge pull requests matching a specific title pattern
# Usage: ./force-merge-prs.fish [title-pattern]

set DEFAULT_TITLE "chore(main): release"

# Get argument or use default
set TITLE_PATTERN (test -n "$argv[1]"; and echo $argv[1]; or echo $DEFAULT_TITLE)

# Find all directories in current working directory (excluding hidden dirs and this script's dir)
set REPOS (find . -maxdepth 1 -type d -not -name ".*" -not -name "." | sed 's|^\./||' | sort)

echo "🚀 Force Merging Pull Requests"
echo "========================================================"
echo "Title Pattern: $TITLE_PATTERN"
echo "Organization: sous-chefs"
echo "========================================================"
echo ""

# Confirmation prompt
echo "⚠️  WARNING: This will force merge PRs even if checks fail!"
echo "Press ENTER to continue or Ctrl+C to cancel..."
read -P ""

for repo in $REPOS
    set repo_path "/Users/damacus/repos/sous-chefs/$repo"

    if not test -d $repo_path
        echo "❌ Repository not found: $repo"
        continue
    end

    echo "📦 Processing sous-chefs/$repo..."

    # Find PR matching the title pattern
    echo "  🔍 Searching for PR with title '$TITLE_PATTERN'..."
    set pr_number (gh pr list --repo sous-chefs/$repo --json number,title --jq ".[] | select(.title | contains(\"$TITLE_PATTERN\")) | .number" 2>/dev/null)

    if test -z "$pr_number"
        echo "  ℹ️  No matching PR found"
        echo ""
        continue
    end

    echo "  ✅ Found PR #$pr_number"

    # Get PR details
    set pr_title (gh pr view $pr_number --repo sous-chefs/$repo --json title --jq .title)
    set pr_state (gh pr view $pr_number --repo sous-chefs/$repo --json state --jq .state)

    echo "  📋 Title: $pr_title"
    echo "  📊 State: $pr_state"

    if test "$pr_state" != "OPEN"
        echo "  ⚠️  PR is not open, skipping..."
        echo ""
        continue
    end

    # Force merge the PR
    echo "  🔀 Force merging PR #$pr_number..."
    if gh pr merge $pr_number --repo sous-chefs/$repo --admin --squash --delete-branch
        echo "  ✅ PR #$pr_number merged successfully"
    else
        echo "  ❌ Failed to merge PR #$pr_number"
    end

    echo ""
end

echo "✨ Done! All matching PRs processed."
echo ""
echo "Summary:"
echo "- Title Pattern: $TITLE_PATTERN"
echo "- Repositories checked: "(count $REPOS)
