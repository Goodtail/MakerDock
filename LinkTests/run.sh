#!/bin/zsh
set -euo pipefail
test_directory="${0:A:h}"
test_binary="$(mktemp -t plateshelf-link-tests)"
trap 'rm -f "$test_binary"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$test_directory/../Sources/Services/MakerWorldLinkService.swift" \
  "$test_directory/Tests.swift" -o "$test_binary"
"$test_binary"
