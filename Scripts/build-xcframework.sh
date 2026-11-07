#!/usr/bin/env bash
#
# Builds Cerebro, CerebroProto and SwiftProtobuf as XCFrameworks for device and
# simulator into build/xcframeworks, zipped for a GitHub Release.
#
# SwiftProtobuf is compiled from the checkout at the version Package.resolved
# pins, because the app's generated types must conform to the same module that
# CerebroProto was built against.

set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="$PWD/build"
ARCHIVE_DIR="$BUILD_DIR/archives"
OUTPUT_DIR="$BUILD_DIR/xcframeworks"
FRAMEWORKS=(Cerebro CerebroProto SwiftProtobuf)

rm -rf "$ARCHIVE_DIR" "$OUTPUT_DIR"
mkdir -p "$ARCHIVE_DIR" "$OUTPUT_DIR"

swift package resolve

archive() {
    local name="$1" destination="$2"

    xcodebuild archive \
        -project Cerebro.xcodeproj \
        -scheme XCFrameworks \
        -destination "$destination" \
        -archivePath "$ARCHIVE_DIR/$name.xcarchive" \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        -quiet
}

archive device "generic/platform=iOS"
archive simulator "generic/platform=iOS Simulator"

for framework in "${FRAMEWORKS[@]}"; do
    arguments=()
    for platform in device simulator; do
        archive_path="$ARCHIVE_DIR/$platform.xcarchive"
        arguments+=(
            -framework "$archive_path/Products/Library/Frameworks/$framework.framework"
            -debug-symbols "$archive_path/dSYMs/$framework.framework.dSYM"
        )
    done

    xcodebuild -create-xcframework "${arguments[@]}" -output "$OUTPUT_DIR/$framework.xcframework"
done

# An XCFramework ships only textual interfaces, and a broken one fails in the
# consumer's build rather than here, so compile a client against all three.
client="$BUILD_DIR/XCFrameworkClient.swift"
cat > "$client" <<'SWIFT'
import Cerebro
import CerebroProto
import SwiftProtobuf

let rule = ProtoRule(messageType: Google_Protobuf_Struct.self)
Cerebro.start(CerebroConfiguration().registering([rule]))
Cerebro.present()
Cerebro.stop()
SWIFT

search_paths=()
for framework in "${FRAMEWORKS[@]}"; do
    search_paths+=(-F "$OUTPUT_DIR/$framework.xcframework/ios-arm64_x86_64-simulator")
done

xcrun swiftc -typecheck \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -target arm64-apple-ios16.0-simulator \
    "${search_paths[@]}" \
    "$client"

for framework in "${FRAMEWORKS[@]}"; do
    (cd "$OUTPUT_DIR" && zip -qry "$framework.xcframework.zip" "$framework.xcframework")
done

echo "Built ${FRAMEWORKS[*]} into $OUTPUT_DIR"
