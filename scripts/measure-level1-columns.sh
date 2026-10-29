#!/usr/bin/env bash
# Measures how many AI enemies level 1's laser columns (and its static LaserWallWave) kill, per section, per source and
# per enemy kind, by replaying each section through a real WaveManager at an 8x clock. Manually run, not part of the
# gate: it takes a few minutes. Helper: tests/helpers/level1_column_replay.gd (read its header for the output format).
#
#   scripts/measure-level1-columns.sh [section ...]     # default: deep_space planet_approach cloud_descent
set -uo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO" || exit 1
args=()
if [ "$#" -gt 0 ]; then args=(-- "$@"); fi
timeout 600 godot --headless --path "$REPO" -s tests/helpers/level1_column_replay.gd "${args[@]}" 2>&1 \
  | grep -E '^(RESULT|TOTAL|DONE|unknown section|SCRIPT ERROR|ERROR|ObjectDB|.*leaked)'
