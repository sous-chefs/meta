#!/usr/bin/env fish
# Script to list all PRs containing a specific title pattern
# Usage: ./list-release-prs.fish [title-pattern]

set DEFAULT_TITLE "chore(main): release"

# Get argument or use default
set TITLE_PATTERN (test -n "$argv[1]"; and echo $argv[1]; or echo $DEFAULT_TITLE)

# Find all directories in current working directory (excluding hidden dirs)
set REPOS (find . -maxdepth 1 -type d -not -name ".*" -not -name "." | sed 's|^\./||' | sort)

echo "🔍 Searching for Pull Requests"
echo "========================================================"
echo "Title Pattern: $TITLE_PATTERN"
echo "Organization: sous-chefs"
echo "========================================================"
echo ""

set found_count 0
set pr_count 0

for repo in $REPOS
    # Fetch number and title together; filter in jq — no separate gh pr view needed
    set pr_data (gh pr list --repo sous-chefs/$repo --json number,title \
        --jq ".[] | select(.title | contains(\"$TITLE_PATTERN\")) | [(.number|tostring), .title] | @tsv" \
        2>/dev/null)

    if test -n "$pr_data"
        echo "📦 $repo"
        for entry in $pr_data
            set cols      (string split \t -- $entry)
            set pr_number $cols[1]
            set pr_title  $cols[2]
            echo "  Opening PR #$pr_number - $pr_title"
            gh pr view $pr_number --repo sous-chefs/$repo --web
            set pr_count (math $pr_count + 1)
        end
        echo ""
        set found_count (math $found_count + 1)
    end
end

echo "========================================================"
echo "✨ Search complete!"
echo "Opened $pr_count PRs from $found_count repositories"
echo "🌐 Check your browser tabs! 😄"
