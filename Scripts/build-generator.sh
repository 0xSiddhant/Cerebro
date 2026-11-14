#!/usr/bin/env bash
#
# Builds cerebro-proto-gen, the generator for Run Script build phases, as a
# universal macOS binary. It's compiled with swiftc directly so that a Pod's
# prepare_command doesn't have to resolve the package.
#
# Usage: Scripts/build-generator.sh [output-directory]

set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT_DIR="${1:-build/generator}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SDK="$(xcrun --sdk macosx --show-sdk-path)"
slices=()
for arch in arm64 x86_64; do
    xcrun --sdk macosx swiftc -O \
        -sdk "$SDK" \
        -target "$arch-apple-macos12" \
        -o "$WORK_DIR/$arch" \
        Sources/CerebroProtoGenerator/*.swift \
        Sources/CerebroProtoGeneratorCore/*.swift
    slices+=("$WORK_DIR/$arch")
done

mkdir -p "$OUTPUT_DIR"
lipo -create "${slices[@]}" -output "$OUTPUT_DIR/cerebro-proto-gen"
echo "Built $OUTPUT_DIR/cerebro-proto-gen"
