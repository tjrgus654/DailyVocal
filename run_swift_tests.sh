#!/usr/bin/env bash
# Real `swift test` on Windows: compiles and RUNS the pure-logic package
# (YIN detector, streak system, note math, echo design) with the installed
# Swift 6.3.3 toolchain. Same PATH setup as verify_swift_parse.sh.
set -u
TOOLCHAIN="/c/Users/vibe/AppData/Local/Programs/Swift/Toolchains/6.3.3+Asserts/usr/bin"
RUNTIME="/c/Users/vibe/AppData/Local/Programs/Swift/Runtimes/6.3.3/usr/bin"
# The Windows platform SDK carries the stdlib swiftmodules + import libs;
# without SDKROOT the manifest compile fails to load the standard library.
export SDKROOT="C:\\Users\\vibe\\AppData\\Local\\Programs\\Swift\\Platforms\\6.3.3\\Windows.platform\\Developer\\SDKs\\Windows.sdk"
export PATH="$RUNTIME:$TOOLCHAIN:$PATH"

cd "$(dirname "$0")"
exec swift test "$@"
