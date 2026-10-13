#!/bin/bash
# Shared build flags. This file is sourced by the build/test scripts.
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
