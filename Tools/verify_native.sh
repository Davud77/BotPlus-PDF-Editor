#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/botplus-checks.XXXXXX")"
cleanup() {
  local result=$?
  trap - EXIT
  if [[ -n "$CHECK_DIRECTORY" && -d "$CHECK_DIRECTORY" ]]; then rm -rf -- "$CHECK_DIRECTORY"; fi
  exit "$result"
}
trap cleanup EXIT
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  printf 'Native checks require an Apple Silicon Mac.\n' >&2
  exit 1
}
sed '/^@main$/d' "$PROJECT_ROOT/ContentView.swift" > "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/Tests/NativeChecksMain.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
mkdir -p "$CHECK_DIRECTORY/Modules" "$CHECK_DIRECTORY/ClangModules"
SWIFT_MODULE_CACHE_PATH="$CHECK_DIRECTORY/Modules" \
CLANG_MODULE_CACHE_PATH="$CHECK_DIRECTORY/ClangModules" \
swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos14.0 \
  -module-cache-path "$CHECK_DIRECTORY/Modules" \
  "$CHECK_DIRECTORY/NativeChecks.swift" -o "$CHECK_DIRECTORY/NativeChecks"
"$CHECK_DIRECTORY/NativeChecks" "$CHECK_DIRECTORY"
