#!/usr/bin/env bash
#
# Writes a version to every file that stores it.

set -euo pipefail

version="${1:?usage: set-version.sh X.Y.Z}"
projects=(Cerebro.xcodeproj/project.pbxproj Example/CerebroExample.xcodeproj/project.pbxproj)

cd "$(dirname "$0")/.."

sed -i '' -E "s/^( *s\.version = ')[^']+(')$/\1$version\2/" Cerebro.podspec
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/" "${projects[@]}"

grep -q "s.version = '$version'" Cerebro.podspec
grep -q "MARKETING_VERSION = $version;" "${projects[@]}"
