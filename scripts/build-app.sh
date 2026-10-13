#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
    echo "Usage: scripts/build-app.sh [release|debug]" >&2
    exit 2
fi
source scripts/swift-tools.sh
swift build ${build_flags[@]+"${build_flags[@]}"} -c "$configuration"
bin_dir="$(swift build ${build_flags[@]+"${build_flags[@]}"} -c "$configuration" --show-bin-path)"
app_dir="build/MacRelay.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/MacRelay" "$app_dir/Contents/MacOS/MacRelay"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# An ad-hoc signature supports local builds. It is not Developer ID signing/notarization.
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
echo "Built $PWD/$app_dir"
