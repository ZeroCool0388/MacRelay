#!/bin/bash
# Shared build flags. This file is sourced by the build/test scripts.
swift_version="$(swift --version)"
if [[ "$swift_version" =~ Swift\ version\ ([0-9]+) ]]; then
    if (( ${BASH_REMATCH[1]} < 6 )); then
        echo "MacRelay needs Swift 6 or later. Select Xcode 16+ or newer Command Line Tools, then try again." >&2
        exit 2
    fi
else
    echo "Could not read the Swift version. Check Apple's developer tools." >&2
    exit 2
fi
build_flags=()
testing_flags=()
swift_help="$(swift build --help)"
# Swift 6.4's new default runner misses macro discovery in some CLT builds.
# Prefer the supported classic runner when the new one is the default.
if [[ "$swift_help" == *"default: swiftbuild"* && "$swift_help" == *"native"* ]]; then
    build_flags+=(--build-system native)
fi
developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
if [[ -d "$testing_frameworks/Testing.framework" ]]; then
    testing_flags+=(-Xswiftc -F -Xswiftc "$testing_frameworks")
    testing_flags+=(-Xlinker -rpath -Xlinker "$testing_frameworks")
fi
testing_plugins="$developer_dir/usr/lib/swift/host/plugins/testing"
plugin_server="$developer_dir/usr/bin/swift-plugin-server"
if [[ -f "$testing_plugins/libTestingMacros.dylib" && -x "$plugin_server" ]]; then
    testing_flags+=(-Xswiftc -external-plugin-path -Xswiftc "$testing_plugins#$plugin_server")
fi
