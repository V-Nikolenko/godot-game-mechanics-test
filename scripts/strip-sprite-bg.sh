#!/usr/bin/env bash
# Erase a sprite's painted-in background by flood-filling inward from the image border.
#
# The recovery path when tests/integration/test_entity_sprite_transparency.gd fails, or when
# PixelLab hands back world art on an opaque background because a create_image_* call was made
# without `no_background: true`. Regenerating instead spends a capped monthly allowance and is
# not reversible; this is.
#
#   ./scripts/strip-sprite-bg.sh assault/assets/sprites/enemies/foo.png              # in place
#   ./scripts/strip-sprite-bg.sh in.png out.png                                      # to a copy
#   ./scripts/strip-sprite-bg.sh assault/assets/sprites/enemies/foo.png --dry-run    # numbers only
#
# The work is done by scripts/lib/strip_sprite_bg.gd - Godot is the only image library in this
# container (no python3, no ImageMagick, not even `file`). That script refuses to run unless all
# four corners are one opaque colour, and refuses to write if the fill would swallow the sprite.
#
# AFTER a successful in-place run you must re-import, or every non-editor Godot run keeps reading
# the stale .godot/imported/*.ctex:
#
#   godot --headless --path . --import
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

die() { printf 'strip-sprite-bg.sh: %s\n' "$*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: strip-sprite-bg.sh <in.png> [out.png] [--dry-run]"

dry_run=""
paths=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run="--dry-run" ;;
    --*)       die "unknown option: $arg" ;;
    *)         paths+=("$arg") ;;
  esac
done

[ "${#paths[@]}" -ge 1 ] || die "no input file given"
[ "${#paths[@]}" -le 2 ] || die "expected at most <in.png> and <out.png>, got ${#paths[@]} paths"

in_path="${paths[0]}"
out_path="${paths[1]:-${paths[0]}}"

[ -f "$in_path" ] || die "no such file: $in_path"

# Absolute, because the Godot run below is `--path "$REPO"` and would otherwise resolve a
# relative path against the repo root rather than the caller's cwd.
abs() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }

godot --headless --path "$REPO" -s res://scripts/lib/strip_sprite_bg.gd -- \
  "$(abs "$in_path")" "$(abs "$out_path")" ${dry_run:+"$dry_run"} \
  || die "strip failed - see the error above; nothing was written"

if [ -z "$dry_run" ]; then
  # Reuse pixellab.sh's magic-byte check rather than writing a second copy of it. It falls back
  # to `od` where `file` is absent, which is the case in this container.
  "$REPO/scripts/pixellab.sh" verify "$out_path"
  printf '\nNow re-import so the engine stops reading the stale .ctex:\n'
  printf '  godot --headless --path %s --import\n' "$REPO"
fi
