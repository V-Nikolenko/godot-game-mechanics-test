#!/usr/bin/env bash
# Runs the three gate steps exactly as /agent/verify.sh does (import, --quit boot, GUT) and
# reports how long each took, GUT's own "Time", the test count and the 15 slowest test files
# (summed testcase time from -gjunit_xml_file). Every task of the enemy-rework epic runs it
# before and after; see tests/README.md -> "Gate time" for the ceiling and the budget.
#
# Unlike /agent/verify.sh this does not fail on FATAL patterns - it measures. A red or leaking
# suite is still reported (exit 1) so a timing is never read off a broken run.
set -uo pipefail

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
XML="$TMP/gut.xml"
LEAK='ObjectDB instances leaked|resources still in use|Resource still in use'

now() { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

t0=$(now)
timeout 900 godot --headless --path "$REPO" --import >"$TMP/import.log" 2>&1
t1=$(now)
timeout 300 godot --headless --path "$REPO" --quit >"$TMP/boot.log" 2>&1
t2=$(now)
timeout 1800 godot --headless --path "$REPO" -s addons/gut/gut_cmdln.gd -gdir=res://tests \
  -ginclude_subdirs -gexit -gjunit_xml_file="$XML" >"$TMP/gut.log" 2>&1
gut_rc=$?
t3=$(now)

printf '\n=== gate time ===\n'
printf 'import  %6s s\n' "$(secs "$t0" "$t1")"
printf 'boot    %6s s\n' "$(secs "$t1" "$t2")"
printf 'GUT     %6s s wall   (GUT reports: %s)\n' "$(secs "$t2" "$t3")" \
  "$(grep -E '^[[:space:]]*Time' "$TMP/gut.log" | tail -1 | sed 's/^[[:space:]]*//')"
printf 'total   %6s s\n' "$(secs "$t0" "$t3")"
grep -E '^[[:space:]]*(Scripts|Tests|Passing Tests|Failing Tests|Risky/Pending|Asserts)[[:space:]]' "$TMP/gut.log" \
  | sed 's/^[[:space:]]*/  /'

printf '\n15 slowest files (seconds, tests):\n'
if [ -s "$XML" ]; then
  # One <testsuite name="res://..." ...> per script; its testcase times sum to the file time.
  awk '
    match($0, /<testsuite [^>]*name="[^"]*"/) {
      s = substr($0, RSTART, RLENGTH); sub(/.*name="/, "", s); sub(/"$/, "", s); file = s
    }
    /<testcase / {
      t = $0; sub(/.*time="/, "", t); sub(/".*/, "", t)
      sum[file] += t; n[file]++
    }
    END { for (f in sum) printf "%8.1f  %3d  %s\n", sum[f], n[f], f }
  ' "$XML" | sort -rn | head -15
else
  echo "  (no junit xml was written)"
fi

rc=0
if [ "$gut_rc" -ne 0 ] || grep -Eq '^[[:space:]]*[1-9][0-9]* failing' "$TMP/gut.log"; then
  printf '\nGUT RED (exit %s)\n' "$gut_rc"; grep -E 'Failing|failing|FAILED' "$TMP/gut.log" | head -20; rc=1
fi
if grep -Eq "$LEAK" "$TMP/gut.log"; then
  printf '\nGUT LEAKED at exit\n'; rc=1
fi
exit $rc
