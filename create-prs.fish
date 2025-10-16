#!/usr/bin/env fish
# Script to create pull requests for workflow-overhaul branches

set REPOS apt ark atom autofs bind bot-trainer bsdcpio certificate chef_auto_accumulator chef_ca chrony cinc-omnibus confluence consul control_groups

echo "🚀 Creating pull requests for workflow-overhaul branches"
echo "========================================================"
echo ""

for repo in $REPOS
    set repo_path "/Users/damacus/repos/sous-chefs/$repo"
    
    if not test -d $repo_path
        echo "❌ Repository not found: $repo"
        continue
    end
    
    echo "📦 Processing $repo..."
    cd $repo_path
    
    # Check if we're on the workflow-overhaul branch
    set current_branch (git branch --show-current)
    if test "$current_branch" != "workflow-overhaul"
        echo "  ⚠️  Not on workflow-overhaul branch (currently on $current_branch)"
        echo "  🔄 Checking out workflow-overhaul..."
        git checkout workflow-overhaul
        or begin
            echo "  ❌ Failed to checkout workflow-overhaul branch"
            continue
        end
    end
    
    # Push the branch
    echo "  ⬆️  Pushing branch to origin..."
    if git push -u origin workflow-overhaul
        echo "  ✅ Branch pushed successfully"
    else
        echo "  ⚠️  Push failed or branch already pushed"
    end
    
    # Create PR
    echo "  🔀 Creating pull request..."
    if gh pr create -f
        echo "  ✅ Pull request created successfully"
    else
        echo "  ⚠️  PR creation failed (may already exist)"
    end
    
    echo ""
end

echo "✨ Done! All pull requests processed."
echo ""
echo "Review your PRs at: https://github.com/sous-chefs"
