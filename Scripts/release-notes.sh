#!/usr/bin/env bash
#
# Prints a GitHub Release's notes for one vX.Y.Z tag: how to install that version, then its section
# of CHANGELOG.md, so the release page and the changelog always match.

set -euo pipefail

tag="${1:?usage: release-notes.sh vX.Y.Z}"
version="${tag#v}"
repository="https://github.com/0xSiddhant/Cerebro"

cd "$(dirname "$0")/.."

# The lines under the version's heading, up to the next release, one level up for the page.
changes="$(awk -v heading="## [$version]" '
    index($0, heading) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md | sed 's/^### /## /')"

if [ -z "$changes" ]; then
    echo "release-notes.sh: CHANGELOG.md has no section for $tag" >&2
    exit 1
fi

cat <<NOTES
## Install

Pick one of these three options.

### Swift Package Manager

\`\`\`swift
.package(url: "$repository.git", exact: "$version")
\`\`\`

### CocoaPods

\`\`\`ruby
pod 'Cerebro', :git => '$repository.git', :tag => '$tag'
\`\`\`

### XCFramework

Download the \`.xcframework.zip\` files below, unzip them, and add them to your app target with **Embed & Sign**.

To generate rules from \`traffic_map.json\` in a Run Script phase, also download \`cerebro-proto-gen.zip\`.
$changes
NOTES
