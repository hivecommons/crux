#!/usr/bin/env bash
# smoke.sh — prove a crux binary serves and answers.
#
#   .github/scripts/smoke.sh [path-to-crux]
#
# Starts `crux serve` on a private unix socket with an empty runtime, drives
# it with `crux --server <sock> ps`, stops it with SIGINT and asserts the
# server exits cleanly. Used by CI on linux and macOS and after each release
# against the installed binary.
set -euo pipefail

CRUX="${1:-./crux}"
[ -x "$CRUX" ] || { echo "smoke: $CRUX is not executable" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/crux-smoke.XXXXXX")"
trap 'rm -rf "$work"' EXIT
# Unix socket paths are limited to ~104 bytes on macOS; keep it short.
sock="$work/s.sock"
log="$work/serve.log"

"$CRUX" --help >/dev/null 2>&1 || "$CRUX" --help 2>&1 | head -3 || true
if "$CRUX" --version >/dev/null 2>&1; then
  echo "smoke: $("$CRUX" --version 2>&1 | head -1)"
fi

export HIVE_WORK_DIR="$work/workdir"
mkdir -p "$HIVE_WORK_DIR"
"$CRUX" serve --socket "$sock" >"$log" 2>&1 &
pid=$!

for _ in $(seq 1 50); do
  [ -S "$sock" ] && break
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "smoke: crux serve exited early:" >&2; cat "$log" >&2; exit 1
  fi
  sleep 0.2
done
[ -S "$sock" ] || { echo "smoke: socket $sock never appeared:" >&2; cat "$log" >&2; exit 1; }
grep -q "serving" "$log" || { echo "smoke: no 'serving' banner:" >&2; cat "$log" >&2; exit 1; }

out="$("$CRUX" --server "$sock" ps 2>&1)" || { echo "smoke: ps failed:" >&2; echo "$out" >&2; cat "$log" >&2; exit 1; }
echo "smoke: ps ->"; echo "$out" | sed 's/^/  /'

kill -INT "$pid"
rc=0
for _ in $(seq 1 50); do
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 0.2
done
if kill -0 "$pid" 2>/dev/null; then
  echo "smoke: serve did not exit within 10s after SIGINT" >&2; kill -9 "$pid"; cat "$log" >&2; exit 1
fi
wait "$pid" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "smoke: serve exited $rc after SIGINT:" >&2; cat "$log" >&2; exit 1
fi
grep -q "serve stopped" "$log" || { echo "smoke: no 'serve stopped' line:" >&2; cat "$log" >&2; exit 1; }
echo "smoke: ok ($CRUX serve started, answered ps, exited 0)"
