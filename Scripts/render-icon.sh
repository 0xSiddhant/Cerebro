#!/usr/bin/env bash
# Renders Cerebro's icon into docs/brand and the Example's app icon, from Sources/Cerebro/Triggers/
# CerebroIcon.swift, the same code the floating button draws with. Run it after changing that file,
# and commit what it writes.
set -euo pipefail

cd "$(dirname "$0")/.."

build_dir="build/render-icon"
mkdir -p "$build_dir"

xcrun swiftc -parse-as-library -O \
    Sources/Cerebro/Triggers/CerebroIcon.swift \
    Scripts/IconRenderer.swift \
    -o "$build_dir/render-icon"

"$build_dir/render-icon" docs/brand Example/CerebroExample/Resources/Assets.xcassets/AppIcon.appiconset
