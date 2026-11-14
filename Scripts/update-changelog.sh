#!/usr/bin/env bash
#
# Adds a release's section to the top of CHANGELOG.md, from the notes GitHub generates for the pull
# requests since the last tag. release-notes.sh reads that section back for the release page, so the
# two always match. Run it before tagging, with GH_TOKEN set and HEAD pushed.
#
# Usage: Scripts/update-changelog.sh vX.Y.Z

set -euo pipefail

tag="${1:?usage: update-changelog.sh vX.Y.Z}"
repository="0xSiddhant/Cerebro"

cd "$(dirname "$0")/.."

previous="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*')"
changes="$(gh api --method POST "repos/$repository/releases/generate-notes" \
    -f tag_name="$tag" -f target_commitish="$(git rev-parse HEAD)" -f previous_tag_name="$previous" \
    --jq .body)"

section="$(mktemp)"
trap 'rm -f "$section" "$section.new"' EXIT
{
    echo "## [${tag#v}](https://github.com/$repository/releases/tag/$tag) - $(date -u +%Y-%m-%d)"
    echo
    # One level down, under the version's heading.
    sed 's/^## /### /' <<< "$changes"
    echo
} > "$section"

# Above the newest release, below the introduction.
awk -v section="$section" '
    !added && /^## \[/ { while ((getline line < section) > 0) print line; added = 1 }
    { print }
    END { if (!added) { print ""; while ((getline line < section) > 0) print line } }
' CHANGELOG.md > "$section.new"
mv "$section.new" CHANGELOG.md
