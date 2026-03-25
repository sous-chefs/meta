#!/usr/bin/env fish
# Clear GitHub notifications for CI results and merged PRs
# Usage: ./clear-notifications.fish [--dry-run]

set -l DRY_RUN false
if contains -- --dry-run $argv
    set DRY_RUN true
end

echo "Fetching unread notifications..."
set -l raw (gh api /notifications --paginate 2>/dev/null | jq -s 'add // []')
set -l total (echo $raw | jq 'length')
echo "Found $total unread notification(s)"
echo ""

# --- CI (reason: ci_activity) ---
set -l ci_ids (echo $raw | jq -r '.[] | select(.reason == "ci_activity") | .id')

# --- Merged PRs (reason: state_change on PullRequest, confirmed merged) ---
set -l pr_candidates (echo $raw | jq -r '.[] | select(.reason == "state_change" and .subject.type == "PullRequest") | "\(.id)|\(.subject.url)"')

set -l merged_ids
for entry in $pr_candidates
    set -l parts (string split '|' $entry)
    set -l id $parts[1]
    set -l url $parts[2]
    set -l info (gh api $url --jq '{merged_at: .merged_at, title: .title}' 2>/dev/null)
    set -l merged_at (echo $info | jq -r '.merged_at')
    if test "$merged_at" != "null" -a -n "$merged_at"
        set -l title (echo $info | jq -r '.title')
        echo "  Merged PR: $title"
        set -a merged_ids $id
    end
end

set -l all_ids $ci_ids $merged_ids
set -l clear_count (count $all_ids)

echo ""
echo "CI notifications: "(count $ci_ids)
echo "Merged PRs:       "(count $merged_ids)
echo "Total to clear:   $clear_count"

if test $clear_count -eq 0
    echo ""
    echo "Nothing to clear."
    exit 0
end

if test $DRY_RUN = true
    echo ""
    echo "[DRY RUN] No changes made."
    exit 0
end

echo ""
echo "Clearing..."
set -l cleared 0
set -l failed 0

for id in $all_ids
    gh api --method PATCH /notifications/threads/$id > /dev/null 2>&1
    if test $status -eq 0
        set cleared (math $cleared + 1)
    else
        set failed (math $failed + 1)
    end
end

echo "Cleared: $cleared"
if test $failed -gt 0
    echo "Failed:  $failed"
end
