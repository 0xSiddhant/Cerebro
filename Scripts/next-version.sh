#!/usr/bin/env bash
#
# Prints the next version from the commits since the last tag, or nothing when
# none of them is releasable.
#
#   Release-As: X.Y.Z footer   exactly that version
#   ! or BREAKING CHANGE:      major, or minor while the major version is 0
#   feat                       minor
#   fix                        patch

set -euo pipefail

last_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*')"
messages="$(git log "$last_tag..HEAD" --format='%B')"

IFS=. read -r major minor patch <<< "${last_tag#v}"

forced="$(awk '/^Release-As: *[0-9]+\.[0-9]+\.[0-9]+ *$/ { print $2; exit }' <<< "$messages")"

if [ -n "$forced" ]; then
    echo "$forced"
elif grep -qE '^[a-z]+(\(.+\))?!:|^BREAKING CHANGE:' <<< "$messages"; then
    # 1.0.0 is a deliberate step, so nothing reaches it by accident.
    if [ "$major" -eq 0 ]; then
        echo "0.$((minor + 1)).0"
    else
        echo "$((major + 1)).0.0"
    fi
elif grep -qE '^feat(\(.+\))?:' <<< "$messages"; then
    echo "$major.$((minor + 1)).0"
elif grep -qE '^fix(\(.+\))?:' <<< "$messages"; then
    echo "$major.$minor.$((patch + 1))"
fi
