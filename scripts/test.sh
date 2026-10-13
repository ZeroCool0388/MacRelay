#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-tools.sh
swift test ${build_flags[@]+"${build_flags[@]}"} --disable-xctest ${testing_flags[@]+"${testing_flags[@]}"}
