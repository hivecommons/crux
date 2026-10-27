#!/usr/bin/env bash
# Exercises coverage-floors.sh with a hermetic `go` test double: no real Go
# toolchain, build or test run is used. `go list ./...` is answered by a fake
# `go` on PATH with a fixed package list, and each case feeds the gate a
# synthetic `go test -cover` log, then asserts the exit status and the verdict
# it prints.
#
# The gate's job is to fail closed. In CI it only ever sees green logs, so
# every failure branch (below floor, FAIL, no test files, Go >= 1.20 zero-
# coverage form, NOT MEASURED, ok-without-figure, worst-of-duplicates) would
# otherwise run for the first time on the day it matters. This test runs them
# on every change to the script.
#
# Usage: bash .github/scripts/test-coverage-floors.sh   (from the module root)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/.github/scripts/coverage-floors.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/coverage-floors-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf '  ok: %s\n' "$*"; }
bad() {
  printf '  FAIL: %s\n' "$*"
  failures=$((failures + 1))
}
# Here-strings, not pipes, so a grep that stops reading early cannot turn
# pipefail into a false FAIL.
assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then pass "$msg"; else bad "$msg (missing: $needle)"; fi
}
assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then bad "$msg (unexpected: $needle)"; else pass "$msg"; fi
}
assert_exit() {
  local want="$1" got="$2" msg="$3"
  if [ "$want" = "$got" ]; then pass "$msg (exit $got)"; else bad "$msg (want exit $want, got $got)"; fi
}

# Fake `go`: only `go list ./...` is ever called by the gate. The package set
# covers every floor_key() branch: module root ("crux"), crux/<pkg>, a nested
# crux/<pkg>/<sub>, and cmd/<name> (which must never key as crux/*).
BIN="$TMP/bin"
mkdir -p "$BIN"
cat >"$BIN/go" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ]; then
  if [ -n "${FAKE_GO_LIST_EMPTY:-}" ]; then exit 0; fi
  printf '%s\n' \
    github.com/hivecommons/crux \
    github.com/hivecommons/crux/agent \
    github.com/hivecommons/crux/agent/tmux \
    github.com/hivecommons/crux/cmd/crux \
    github.com/hivecommons/crux/pushbroker
fi
exit 0
SH
chmod +x "$BIN/go"

MODULE="$TMP/module"
mkdir -p "$MODULE"

# ok_line PKG PCT -> one `go test -cover` success line, exactly as go prints it
# (two spaces after "ok", tab-separated fields, elapsed time before coverage).
ok_line() { printf 'ok  \t%s\t0.1s\tcoverage: %s%% of statements\n' "$1" "$2"; }

# A log in which every package clears its floor, with crux/agent (floor 89)
# and crux/pushbroker (floor 99) sitting just above theirs, as they do on
# main, so one edit below is enough to cross a floor.
green_log() {
  ok_line github.com/hivecommons/crux 98.6
  ok_line github.com/hivecommons/crux/agent 89.3
  ok_line github.com/hivecommons/crux/agent/tmux 100.0
  ok_line github.com/hivecommons/crux/cmd/crux 80.0
  ok_line github.com/hivecommons/crux/pushbroker 99.2
}
# green_log minus one package, so a case can append its own line for it.
green_without() { green_log | grep -v "$(printf '\t%s\t' "$1")"; }

# run_gate CASE [env VAR=VALUE ...] -- LOG...
# Runs the gate from a scratch module dir with the fake go first on PATH.
# Leaves stdout+stderr in $TMP/<case>.out and the exit status in RC.
run_gate() {
  local name="$1"; shift
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  (
    cd "$MODULE" && env -u GITHUB_STEP_SUMMARY "${envs[@]}" PATH="$BIN:$PATH" bash "$SCRIPT" "$@"
  ) >"$TMP/$name.out" 2>&1
  RC=$?
  OUT="$(cat "$TMP/$name.out")"
}

echo "case: all packages at or above their floors"
green_log >"$TMP/green.log"
run_gate green -- "$TMP/green.log"
assert_exit 0 "$RC" "green log passes"
assert_contains "$OUT" "All packages meet their coverage floor" "prints the pass verdict"
assert_contains "$OUT" "crux/agent: 89.3% (floor 89%)" "crux/agent scored against its 89 override"
assert_contains "$OUT" "crux/pushbroker: 99.2% (floor 99%)" "crux/pushbroker scored against its 99 override"
assert_contains "$OUT" "cmd/crux: 80.0% (floor 75%)" "cmd/crux keys as cmd/<name>, not crux/cmd/crux"
assert_contains "$OUT" "crux/agent/tmux: 100.0% (floor 90%)" "nested package uses the 90 default"
assert_contains "$OUT" "crux: 98.6% (floor 90%)" "module root keys as crux"
assert_not_contains "$OUT" "COVERAGE GATE FAILED" "no failure banner on a green log"
if [ -z "$(ls -A "$MODULE")" ]; then pass "scratch files removed on exit"; else bad "scratch files left behind: $(ls -A "$MODULE")"; fi

echo "case: a package just below its override floor"
{ green_without github.com/hivecommons/crux/agent; ok_line github.com/hivecommons/crux/agent 88.9; } >"$TMP/below.log"
run_gate below -- "$TMP/below.log"
assert_exit 1 "$RC" "88.9% against floor 89 fails"
assert_contains "$OUT" "COVERAGE GATE FAILED" "prints the failure banner"
assert_contains "$OUT" "crux/agent: 88.9% (floor 89%)" "names the package, figure and floor"

echo "case: the integer part is compared, not a rounded figure"
{ green_without github.com/hivecommons/crux/agent; ok_line github.com/hivecommons/crux/agent 89.0; } >"$TMP/exact.log"
run_gate exact -- "$TMP/exact.log"
assert_exit 0 "$RC" "89.0% meets floor 89"
{ green_without github.com/hivecommons/crux/pushbroker; ok_line github.com/hivecommons/crux/pushbroker 98.9; } >"$TMP/round.log"
run_gate round -- "$TMP/round.log"
assert_exit 1 "$RC" "98.9% does not round up to floor 99"

echo "case: a package whose tests fail"
{ green_without github.com/hivecommons/crux/agent; printf 'FAIL\tgithub.com/hivecommons/crux/agent\t5.0s\n'; } >"$TMP/fail.log"
run_gate fail -- "$TMP/fail.log"
assert_exit 1 "$RC" "FAIL line is a hard failure"
assert_contains "$OUT" "crux/agent: TESTS FAILING" "reports TESTS FAILING"

echo "case: a package with no test files (classic form)"
{ green_without github.com/hivecommons/crux/pushbroker; printf '?   \tgithub.com/hivecommons/crux/pushbroker\t[no test files]\n'; } >"$TMP/notests.log"
run_gate notests -- "$TMP/notests.log"
assert_exit 1 "$RC" "no test files is a hard failure (UNTESTED_CMD_MAINS is empty)"
assert_contains "$OUT" "crux/pushbroker: NO TEST FILES" "reports NO TEST FILES"

echo "case: a package with no test files (Go >= 1.20 coverage: 0.0% form)"
{ green_without github.com/hivecommons/crux/pushbroker; printf '\tgithub.com/hivecommons/crux/pushbroker\t\tcoverage: 0.0%% of statements\n'; } >"$TMP/go120.log"
run_gate go120 -- "$TMP/go120.log"
assert_exit 1 "$RC" "tab-led 0.0% line is treated as no test files"
assert_contains "$OUT" "crux/pushbroker: NO TEST FILES" "reports NO TEST FILES for the 0.0% form"

echo "case: a listed package that no log mentions"
green_without github.com/hivecommons/crux/pushbroker >"$TMP/missing.log"
run_gate missing -- "$TMP/missing.log"
assert_exit 1 "$RC" "a lost shard fails closed"
assert_contains "$OUT" "crux/pushbroker: NOT MEASURED (no test result in any log)" "reports NOT MEASURED"

echo "case: ok line without a coverage figure"
{ green_without github.com/hivecommons/crux/agent; printf 'ok  \tgithub.com/hivecommons/crux/agent\t5.0s\n'; } >"$TMP/nocover.log"
run_gate nocover -- "$TMP/nocover.log"
assert_exit 1 "$RC" "ok without -cover output fails"
assert_contains "$OUT" "crux/agent: ok but no coverage figure (was -cover passed?)" "says -cover was probably dropped"

echo "case: a package reported in two logs takes the lowest percentage"
{ green_without github.com/hivecommons/crux/agent; ok_line github.com/hivecommons/crux/agent 95.0; } >"$TMP/dup-a.log"
{ green_without github.com/hivecommons/crux/agent; ok_line github.com/hivecommons/crux/agent 88.0; } >"$TMP/dup-b.log"
run_gate dup-low -- "$TMP/dup-a.log" "$TMP/dup-b.log"
assert_exit 1 "$RC" "lowest of 95.0 and 88.0 is scored"
assert_contains "$OUT" "crux/agent: 88.0% (floor 89%)" "reports the lower figure"
run_gate dup-low-reversed -- "$TMP/dup-b.log" "$TMP/dup-a.log"
assert_exit 1 "$RC" "log order does not change the verdict"

echo "case: a package reported ok in one log and FAIL in another takes FAIL"
printf 'FAIL\tgithub.com/hivecommons/crux/agent\t5.0s\n' >"$TMP/failonly.log"
run_gate dup-fail -- "$TMP/green.log" "$TMP/failonly.log"
assert_exit 1 "$RC" "FAIL wins over ok"
assert_contains "$OUT" "crux/agent: TESTS FAILING" "reports TESTS FAILING, not the ok figure"

echo "case: packages outside go list are ignored"
{ green_log; ok_line github.com/other/module 1.0; printf 'FAIL\tgithub.com/other/module/sub\t1.0s\n'; } >"$TMP/foreign.log"
run_gate foreign -- "$TMP/foreign.log"
assert_exit 0 "$RC" "foreign ok/FAIL lines do not affect the verdict"
assert_not_contains "$OUT" "other/module" "foreign packages are not reported"

echo "case: argument and input validation"
run_gate noargs --
assert_exit 2 "$RC" "no arguments is a usage error"
assert_contains "$OUT" "usage:" "prints usage"
: >"$TMP/empty.log"
run_gate empty -- "$TMP/empty.log"
assert_exit 1 "$RC" "an empty log fails"
assert_contains "$OUT" "::error::" "empty log is reported as a workflow error"
run_gate absent -- "$TMP/does-not-exist.log"
assert_exit 1 "$RC" "a missing log fails"
printf 'some unrelated output\n' >"$TMP/noise.log"
run_gate noise -- "$TMP/noise.log"
assert_exit 1 "$RC" "a log with no package results fails"
assert_contains "$OUT" "no package pass/fail states parsed" "says nothing was parsed"

echo "case: go list returns nothing"
run_gate golist FAKE_GO_LIST_EMPTY=1 -- "$TMP/green.log"
assert_exit 1 "$RC" "empty go list fails rather than passing vacuously"
assert_contains "$OUT" "go list produced no packages" "names the cause"

echo "case: GITHUB_STEP_SUMMARY receives the report"
SUMMARY="$TMP/summary.md"
: >"$SUMMARY"
(cd "$MODULE" && env GITHUB_STEP_SUMMARY="$SUMMARY" PATH="$BIN:$PATH" bash "$SCRIPT" "$TMP/below.log") >/dev/null 2>&1
assert_contains "$(cat "$SUMMARY")" "## Per-package coverage" "report heading written to the step summary"
assert_contains "$(cat "$SUMMARY")" "### Packages below their floor" "failure section written to the step summary"
assert_contains "$(cat "$SUMMARY")" "crux/agent: 88.9% (floor 89%)" "failing package named in the step summary"

echo
if [ "$failures" -eq 0 ]; then
  echo "coverage-floors tests: all passed"
  exit 0
fi
echo "coverage-floors tests: $failures failure(s)"
exit 1
