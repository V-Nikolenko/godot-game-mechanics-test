#!/usr/bin/env bash
# Runs the GUT suite exactly as /agent/verify.sh step 3 does, and additionally fails if the
# Godot process leaked objects at exit.
#
# WHY THIS EXISTS
# ---------------
# Godot reports a leak only after the main loop is gone, as
#
#   WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
#   ERROR: 1 resources still in use at exit (run with --verbose for details).
#
# Neither line matches the gate's FATAL regex, and both are printed after GUT has already set the
# process exit code — so the gate reports GATE PASS on a suite that leaks. The usual cause is a
# test that returns while a coroutine of the code under test is still suspended: freeing the
# object strands its GDScriptFunctionState, which holds the script Resource open.
#
# /agent is mounted read-only from inside the dev container, so the agent cannot add these
# patterns to the gate itself. Run this instead, or fold it into the gate by hand — the only
# change step 3 needs is a `grep -Eq "$LEAK" "$LOG" && fail ...` after the existing checks.
#
# Exit 0 = suite green AND nothing leaked.
set -uo pipefail

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# Deliberately narrow. Godot's headless --import step emits one benign "ObjectDB instances leaked"
# of its own that predates the test suite, which is why this only ever looks at the GUT run.
LEAK='ObjectDB instances leaked|resources still in use|Resource still in use'

fail() { printf '\nLEAK CHECK FAIL: %s\n' "$1"; exit 1; }

timeout 1800 godot --headless --path "$REPO" \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | tee "$LOG"

[ "${PIPESTATUS[0]}" -ne 0 ] && fail "GUT suite red"
grep -Eq '^[[:space:]]*[1-9][0-9]* failing' "$LOG" && fail "GUT reported failing tests"

if grep -Eq "$LEAK" "$LOG"; then
  printf '\n--- offending lines ---\n'
  grep -E "$LEAK" "$LOG" | head -10
  printf '\nRe-run with --verbose after -headless to see which instances leaked.\n'
  fail "the test run leaked objects at exit"
fi

printf '\nLEAK CHECK PASS - suite green, nothing leaked\n'
exit 0
