#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app_dir="build/MacRelay.app"
if [[ ! -d "$app_dir" ]]; then
    echo "Build the app first with ./scripts/build-app.sh" >&2
    exit 1
fi
codesign --verify --strict "$app_dir"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "The app version must contain three numbers." >&2
    exit 1
fi
output_dir="${1:-build}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
stage_dir="$(mktemp -d build/package.XXXXXX)"
trap 'rm -rf "$stage_dir"' EXIT

# One unchanged app, with both roles. Install the same archive on both Macs.
ditto "$app_dir" "$stage_dir/MacRelay.app"
cp docs/INSTALL.md "$stage_dir/START-HERE.md"
cp LICENSE "$stage_dir/LICENSE.txt"
archive="MacRelay-$version-macOS.zip"
ditto -c -k "$stage_dir" "$output_dir/$archive"
(cd "$output_dir" && shasum -a 256 "$archive" > "$archive.sha256")
echo "Packaged $output_dir/$archive"
