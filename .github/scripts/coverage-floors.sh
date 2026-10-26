#!/usr/bin/env bash
# coverage-floors.sh — per-package coverage gate for the published Crux module.
#
# Mirrors the "Check per-package coverage" step hive applies to this same code
# in .github/workflows/v2-tests.yml and coverage-hourly.yml (hivecommons/hive,
# branch v5). Same inputs (`go test -cover` output), same classification, same
# floors, same default of 90%, so a change that would fail hive's gate fails
# here too once hive consumes the module from this repository.
#
#   ok    <pkg>  coverage: NN.N% of statements  -> scored against its floor
#   FAIL  <pkg>                                 -> TESTS FAILING (hard fail)
#   ?     <pkg>  [no test files]                -> NO TEST FILES (hard fail)
#   <pkg>\t\tcoverage: 0.0% of statements       -> NO TEST FILES (Go >= 1.20 form)
#
# Any package `go list ./...` knows about that produced no result at all is
# reported NOT MEASURED and fails the gate (fail closed: a lost shard log must
# not read as "all green").
#
# Lives under .github/ because the crux-publish sync replaces every other path.
#
# Usage: .github/scripts/coverage-floors.sh <go-test-log>...
#   Run from the module root. Each log is the combined stdout+stderr of a
#   `go test -cover ...` invocation (the agent job and the rest job each
#   produce one). Writes a report to $GITHUB_STEP_SUMMARY when set.
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: $0 <go-test-log>..." >&2; exit 2; }
for f in "$@"; do
  [ -s "$f" ] || { echo "::error::$f is missing or empty" >&2; exit 1; }
done

THRESHOLD=90

# Scratch files in the working directory (the module root in CI); removed on
# exit so a local run leaves the tree clean.
trap 'rm -f existing-pkgs.txt cover-run.log pkg-states.txt' EXIT

# KEEP IN SYNC with the crux/* and cmd/crux entries of PKG_THRESHOLD in hive's
# .github/workflows/v2-tests.yml and coverage-hourly.yml. Keys are hive's
# floor_key() output, which is identical for both import paths
# (github.com/hivecommons/hive/crux/agent and github.com/hivecommons/crux/agent
# both key as crux/agent). Values are hive's; a package that measures above its
# floor here is NOT a reason to raise it here — raise it in hive.
declare -A PKG_THRESHOLD=(
  [crux/agent]=89      # pre-existing shortfall inherited from hive #2350; see hive #2355
  [crux/proxy]=89
  [crux/sandbox]=98
  [crux/pushbroker]=99
  [crux/kubejob]=90    # hive #6311
  [cmd/crux]=75        # main() is the one uncovered statement; run() is tested in-process (hive #13536, #14138)
  [crux/cli]=92        # residue is Main() and write-error branches (hive #13536)
)

# Thin mains exempt from the NO TEST FILES failure. Empty, as in hive.
UNTESTED_CMD_MAINS=''

# hive's floor_key(), verbatim. */cmd/* is tested first so cmd/crux never
# resolves to a crux/* key; the module root package keys as "crux".
floor_key() {
  case "$1" in
    */cmd/*)  echo "cmd/${1##*/}" ;;
    */pkg/*)  echo "${1##*/pkg/}" ;;
    */crux/*) echo "crux/${1##*/crux/}" ;;
    */crux)   echo "crux" ;;
    *)        echo "${1##*/}" ;;
  esac
}

go list ./... | LC_ALL=C sort -u > existing-pkgs.txt
if [ ! -s existing-pkgs.txt ]; then
  echo "::error::go list produced no packages" >&2
  exit 1
fi

cat "$@" > cover-run.log

# One state per package. A package that appears in more than one log (the
# agent job and the rest job both run ./agent/tmux, for instance) takes the
# worst state and the lowest percentage, so a flaky split can only make the
# verdict stricter.
awk '
  NR == FNR { exists[$1] = 1; next }
  $1 == "ok" || $1 == "FAIL" || $1 == "?" {
    if (!exists[$2]) next
    seen[$2] = 1
    if ($1 == "ok") {
      ok[$2] = 1
      for (i = 3; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+%$/) {
        p = $i; sub(/%$/, "", p)
        if (!(($2) in pct) || p + 0 < pct[$2] + 0) pct[$2] = p
      }
    } else if ($1 == "FAIL") fail[$2] = 1
    else no_tests[$2] = 1
    next
  }
  /^\t.*\t\tcoverage: 0\.0% of statements$/ {
    if (exists[$1]) { seen[$1] = 1; no_tests[$1] = 1 }
  }
  END {
    for (pkg in seen) {
      if (fail[pkg]) print "FAIL", pkg, "-"
      else if (no_tests[pkg]) print "?", pkg, "-"
      else if (ok[pkg]) print "ok", pkg, (pkg in pct ? pct[pkg] : "-")
    }
  }
' existing-pkgs.txt cover-run.log | LC_ALL=C sort -u > pkg-states.txt

if [ ! -s pkg-states.txt ]; then
  echo "COVERAGE GATE FAILED: no package pass/fail states parsed from the test logs."
  exit 1
fi

FAILED=""
BROKEN=""
REPORT=""

while read -r state pkgpath pct; do
  pkg=$(floor_key "$pkgpath")
  case "$state" in
    ok)
      if [ "$pct" = "-" ]; then
        BROKEN="${BROKEN}${pkg}: ok but no coverage figure (was -cover passed?)\n"
        REPORT="${REPORT}${pkg}: ok, unscored\n"
        continue
      fi
      int_pct=${pct%.*}
      pkg_threshold=${PKG_THRESHOLD[$pkg]:-$THRESHOLD}
      if [ "$int_pct" -lt "$pkg_threshold" ]; then
        FAILED="${FAILED}${pkg}: ${pct}% (floor ${pkg_threshold}%)\n"
      fi
      REPORT="${REPORT}${pkg}: ${pct}% (floor ${pkg_threshold}%)\n"
      ;;
    FAIL)
      BROKEN="${BROKEN}${pkg}: TESTS FAILING\n"
      REPORT="${REPORT}${pkg}: FAIL\n"
      ;;
    \?)
      case " $UNTESTED_CMD_MAINS " in
        *" $pkg "*)
          REPORT="${REPORT}${pkg}: no tests (exempt thin main)\n"
          ;;
        *)
          BROKEN="${BROKEN}${pkg}: NO TEST FILES\n"
          REPORT="${REPORT}${pkg}: no tests\n"
          ;;
      esac
      ;;
  esac
done < pkg-states.txt

# Fail closed on anything go list knows about that no log reported.
while read -r p; do
  [ -n "$p" ] || continue
  if ! awk -v p="$p" '$2 == p { f = 1 } END { exit !f }' pkg-states.txt; then
    pkg=$(floor_key "$p")
    BROKEN="${BROKEN}${pkg}: NOT MEASURED (no test result in any log)\n"
    REPORT="${REPORT}${pkg}: not measured\n"
  fi
done < existing-pkgs.txt

{
  echo "## Per-package coverage"
  echo ""
  echo -e "${REPORT}"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -n "$BROKEN" ] || [ -n "$FAILED" ]; then
  {
    [ -n "$BROKEN" ] && echo -e "### Packages that cannot be scored\n${BROKEN}"
    [ -n "$FAILED" ] && echo -e "### Packages below their floor\n${FAILED}"
  } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
  echo ""
  echo "COVERAGE GATE FAILED:"
  [ -n "$BROKEN" ] && echo -e "${BROKEN}"
  [ -n "$FAILED" ] && echo -e "${FAILED}"
  exit 1
fi
echo "All packages meet their coverage floor" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
