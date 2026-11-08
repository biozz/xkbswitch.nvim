#!/bin/sh
set -eu
# Keep the exact upstream source revision in version control.
SOURCE_REV=97c0e4c9ce7a3f9d91a1b684da0cfad5f5978fe7
OUT=${1:-dist}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone --quiet https://github.com/vovkasm/input-source-switcher.git "$WORK/source"
git -C "$WORK/source" checkout --quiet "$SOURCE_REV"
cmake -S "$WORK/source" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release \
  '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_INSTALL_PREFIX="$WORK/package"
cmake --build "$WORK/build" --config Release --parallel
cmake --install "$WORK/build" --config Release
mkdir -p "$WORK/package/share/licenses/input-source-switcher"
cp "$WORK/source/LICENSE" "$WORK/package/share/licenses/input-source-switcher/LICENSE"
printf '%s\n' "$SOURCE_REV" > "$WORK/package/SOURCE_REVISION"
for binary in "$WORK/package/bin/issw" "$WORK/package/lib/libInputSourceSwitcher.dylib"; do
  lipo "$binary" -verify_arch arm64
  lipo "$binary" -verify_arch x86_64
  codesign --force --sign - "$binary"
  codesign --verify "$binary"
done
# Prove the CLI resolves its sibling library outside the build tree.
"$WORK/package/bin/issw" -V
tar -czf "$OUT/input-source-switcher-macos-universal.tar.gz" -C "$WORK/package" .
(cd "$OUT" && shasum -a 256 input-source-switcher-macos-universal.tar.gz > SHA256SUMS)
