#!/usr/bin/env bash
#
# Prints the install section of a GitHub Release, for one vX.Y.Z tag.

set -euo pipefail

tag="${1:?usage: release-notes.sh vX.Y.Z}"
version="${tag#v}"
repository="https://github.com/0xSiddhant/Cerebro"

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
NOTES
