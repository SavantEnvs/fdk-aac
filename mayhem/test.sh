#!/usr/bin/env bash
#
# mayhem/test.sh — RUN fdk-aac's own encode/decode self-test (built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Upstream's test/run-test.sh downloads a WAV over the network and needs ffmpeg, so it cannot run
# air-gapped. This runs the same tool (test-encode-decode: every AOT/transport/bitrate combination is
# encoded, decoded and compared against its SHA-1 digests) on deterministic WAVs generated locally,
# plus an aac-enc -> aac-dec round trip. Every expected value below is a known answer recorded from a
# clean build; a missing tool or fixture is a failure, never a skip.
B="$SRC/build-tests"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
passed=0; failed=0

check() {  # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then passed=$((passed + 1)); echo "PASS $1"
  else failed=$((failed + 1)); echo "FAIL $1: expected '$2' got '$3'"; fi
}

for tool in test-encode-decode aac-enc aac-dec; do
  [ -x "$B/$tool" ] || { echo "missing $B/$tool - mayhem/build.sh should have built it" >&2; emit_ctrf "fdk-aac-selftest" 0 1 0; exit 1; }
done

python3 "$SRC/mayhem/test/gen_wav.py" 2 "$T/stereo.wav"
python3 "$SRC/mayhem/test/gen_wav.py" 1 "$T/mono.wav"
check "stereo.wav fixture" bc12475b12d69e8264ed788977db720108d4826b "$(sha1sum < "$T/stereo.wav" | cut -d' ' -f1)"
check "mono.wav fixture" c2c786916d7f91263e4b8013d0841578e4cbbc1f "$(sha1sum < "$T/mono.wav" | cut -d' ' -f1)"

run_ted() {  # run_ted <name> <wav> <encode hash> <decode hash> <number of encode/decode configurations>
  local rc=0
  "$B/test-encode-decode" "$2" > "$T/$1.out" 2> "$T/$1.err" || rc=$?
  check "$1 exit status" 0 "$rc"
  check "$1 failures" "0 failures" "$(tail -n1 "$T/$1.err")"
  check "$1 configurations" "$5" "$(grep -c '^Testing encoding' "$T/$1.err")"
  check "$1 encode hash" "encode hash: $3" "$(grep '^encode hash' "$T/$1.out")"
  check "$1 decode hash" "decode hash: $4" "$(grep '^decode hash' "$T/$1.out")"
}
run_ted stereo "$T/stereo.wav" 7ab6c9f942229d5d6c6d53d178bf3358665f208e 4c721befc7d8aa1569541d61cb4832717222eddc 24
run_ted mono "$T/mono.wav" 52d66a2d9eb630e85b3367579fbe14f31e2a5749 e3343aa178a4d438d1ba5616093d699d5730d541 11

# aac-enc (AAC-LC, 64 kbit/s, ADTS) -> aac-dec round trip on the stereo fixture.
"$B/aac-enc" -r 64000 -t 2 "$T/stereo.wav" "$T/stereo.aac" > /dev/null 2>&1 || true
check "aac-enc ADTS size" 4850 "$(stat -c %s "$T/stereo.aac" 2>/dev/null || echo 0)"
check "aac-enc ADTS sha1" c347a2f6ad7fc2a2785e84335cd667a8a30ba05f "$(sha1sum < "$T/stereo.aac" 2>/dev/null | cut -d' ' -f1)"
"$B/aac-dec" "$T/stereo.aac" "$T/decoded.wav" > /dev/null 2>&1 || true
check "aac-dec WAV size" 91608 "$(stat -c %s "$T/decoded.wav" 2>/dev/null || echo 0)"
check "aac-dec WAV sha1" d6e4360eee2ca5d3a652f1baf9c2c48a7b6f485e "$(sha1sum < "$T/decoded.wav" 2>/dev/null | cut -d' ' -f1)"

emit_ctrf "fdk-aac-selftest" "$passed" "$failed" 0
