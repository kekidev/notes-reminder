#!/usr/bin/env bash
# Every check CI runs. Run it before each commit.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "$(git ls-files data)" ]; then
  echo "error: files under data/ are tracked; the owner's to-do list must never be committed" >&2
  exit 1
fi

/usr/bin/python3 -I scripts/merge_mcp_config.py --self-test

swiftlint --strict --quiet
swift format lint --strict -r Sources Tests App Package.swift
swift build
swift test --enable-code-coverage
bin=$(swift build --show-bin-path)
# Swift 6.4 builds one bundle per test target; Swift 6.3 (CI) builds one combined bundle.
for xctest in "$bin/GlanceCoreTests.xctest" "$bin/GlancePackageTests.xctest"; do [ -d "$xctest" ] && break; done
xcrun llvm-cov report "$xctest/Contents/MacOS/$(basename "$xctest" .xctest)" \
  -instr-profile "$bin/codecov/default.profdata" Sources/GlanceCore |
  awk '/^TOTAL/ { sub("%", "", $10); print "GlanceCore line coverage: " $10 "%"; if ($10 + 0 < 90) exit 1 }'
xcodegen generate --quiet
xcodebuild -scheme Glance -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData build test -quiet
