#!/usr/bin/env bash
# Real Swift-compiler syntax validation for the whole project (Windows, no Xcode).
# Toolchain: Swift 6.3.3 installed per-user via winget (Swift.Toolchain).
# swiftc driver fails to spawn in some shells; invoke swift-frontend directly,
# with BOTH Toolchains and Runtimes on PATH (swiftCore.dll lives in Runtimes).
set -u
TOOLCHAIN="/c/Users/vibe/AppData/Local/Programs/Swift/Toolchains/6.3.3+Asserts/usr/bin"
RUNTIME="/c/Users/vibe/AppData/Local/Programs/Swift/Runtimes/6.3.3/usr/bin"
export PATH="$RUNTIME:$TOOLCHAIN:$PATH"
FE="$TOOLCHAIN/swift-frontend.exe"

cd "$(dirname "$0")"
PASS=0; FAIL=0
for f in $(find . -name "*.swift" -not -path "./preview/*" -not -path "./.build/*" | sort); do
  OUT=$("$FE" -parse "$f" 2>&1); CODE=$?
  if [ $CODE -eq 0 ] && [ -z "$OUT" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "=== FAIL($CODE): $f ==="
    echo "$OUT"
  fi
done
echo "-------------------------------------------"
echo "swift-frontend -parse: 통과 $PASS / 실패 $FAIL"
[ $FAIL -eq 0 ]
