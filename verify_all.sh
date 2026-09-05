#!/usr/bin/env bash
# One-shot local verification: everything Windows can run, in one command.
#   bash verify_all.sh
# Gates:
#   1. Swift parse (all app+test sources)
#   2. swift test (pure-logic unit tests, real execution)
#   3. Static cross-verification (data contracts, ghost APIs)
#   4. Echo parity gate (web prototype <-> Swift, 8 axes)
#   5. Streak parity gate (web prototype <-> Swift, 5 axes)
#   6. live.html JS syntax (vm.Script)
# CI (.github/workflows/typecheck.yml) additionally typechecks the app and
# widget against the iphonesimulator SDK and re-runs swift test on macOS.
set -u
cd "$(dirname "$0")"

PASS=0; FAIL=0
step() {
  echo ""
  echo "=============================================="
  echo "[$1] $2"
  echo "=============================================="
}
record() {
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo ">>> PASS: $2";
  else FAIL=$((FAIL+1)); echo ">>> FAIL: $2"; fi
}

step 1 "Swift 구문 검사 (swift-frontend -parse)"
bash verify_swift_parse.sh > /tmp/va_parse.log 2>&1
record $? "parse (tail: $(tail -1 /tmp/va_parse.log))"

step 2 "순수 로직 유닛테스트 (swift test, 실실행)"
bash run_swift_tests.sh > /tmp/va_test.log 2>&1
grep -q "with 0 failures" /tmp/va_test.log && grep -q "Executed" /tmp/va_test.log
record $? "swift test ($(grep -o 'Executed [0-9]* tests, with [0-9]* failures' /tmp/va_test.log | tail -1))"

step 3 "정적 교차검증 (데이터 정합·유령 API)"
python evidence/20260903-rebuild/verify_static.py > /tmp/va_static.log 2>&1
record $? "static ($(tail -1 /tmp/va_static.log))"

step 4 "에코 플로우 파리티 (웹 ↔ Swift, 8축)"
python evidence/20260903-rebuild/verify_echo_parity.py > /tmp/va_echo.log 2>&1
record $? "echo parity ($(tail -1 /tmp/va_echo.log))"

step 5 "스트릭/쉬는 날 파리티 (웹 ↔ Swift, 5축)"
python evidence/20260903-rebuild/verify_streak_parity.py > /tmp/va_streak.log 2>&1
record $? "streak parity ($(tail -1 /tmp/va_streak.log))"

step 6 "프로토타입 JS 구문 (vm.Script)"
node -e "
const fs=require('fs'), vm=require('vm');
[...fs.readFileSync('preview/live.html','utf8').matchAll(/<script>([\s\S]*?)<\/script>/g)].forEach(m=>new vm.Script(m[1]));
console.log('JS OK');" > /tmp/va_js.log 2>&1
record $? "live.html JS ($(tail -1 /tmp/va_js.log))"

step 7 "비브라토 파리티 (웹 ↔ Swift, 상수+공식+15실행축)"
python evidence/20260903-rebuild/verify_vibrato_parity.py > /tmp/va_vib.log 2>&1
record $? "vibrato parity ($(tail -1 /tmp/va_vib.log))"

step 8 "다이내믹스 파리티 (웹 ↔ Swift, 상수+공식+16실행축)"
python evidence/20260903-rebuild/verify_dynamics_parity.py > /tmp/va_dyn.log 2>&1
record $? "dynamics parity ($(tail -1 /tmp/va_dyn.log))"

step 9 "최장지속(MPT) 파리티 (웹 ↔ Swift, 상수+9실행축)"
python evidence/20260903-rebuild/verify_sustain_parity.py > /tmp/va_sus.log 2>&1
record $? "sustain parity ($(tail -1 /tmp/va_sus.log))"

echo ""
echo "=============================================="
echo "RESULT: $PASS 통과 / $FAIL 실패 (9 게이트)"
[ "$FAIL" -eq 0 ] && echo "ALL GREEN" || { echo "FAILURES PRESENT"; exit 1; }
