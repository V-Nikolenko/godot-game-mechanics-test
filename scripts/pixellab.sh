#!/usr/bin/env bash
# Safe binary handling for PixelLab MCP output.
#
# The MCP server is remote: it returns base64 or URLs, it cannot write files here.
# NEVER save image data with the Write tool - Write is UTF-8 text only and silently
# corrupts PNG bytes into null-filled files that look valid until Godot imports them.
# Every path below verifies the result with `file` before returning success.
#
#   ./scripts/pixellab.sh save-b64 "<base64>" path/out.png
#   ./scripts/pixellab.sh download "<url>"    path/out.png
#   ./scripts/pixellab.sh verify   path/out.png
set -euo pipefail

die() { printf 'pixellab.sh: %s\n' "$*" >&2; exit 1; }

verify() {
  local f="$1"
  [ -s "$f" ] || die "FAILED: $f is missing or zero bytes"
  local t; t="$(file -b "$f")"
  case "$t" in
    PNG*|JPEG*|"RIFF"*|Web*) printf 'OK  %s  (%s, %s bytes)\n' "$f" "${t%%,*}" "$(stat -c %s "$f")" ;;
    *) die "FAILED: $f is not an image (file says: $t). Did you use the Write tool?" ;;
  esac
}

cmd="${1:-}"; shift || true
case "$cmd" in
  save-b64)
    [ $# -eq 2 ] || die "usage: save-b64 <base64> <outfile>"
    data="$1"; out="$2"
    mkdir -p "$(dirname "$out")"
    # Strip a data: URI prefix and any whitespace/newlines the MCP response may carry.
    printf '%s' "$data" | sed -e 's|^data:[^,]*,||' | tr -d '[:space:]' | base64 -d > "$out" \
      || die "base64 decode failed for $out"
    verify "$out"
    ;;
  download)
    [ $# -eq 2 ] || die "usage: download <url> <outfile>"
    url="$1"; out="$2"
    mkdir -p "$(dirname "$out")"
    # -L is required: the API answers with a 302 and without it you get a 0-byte file.
    curl -sSL --fail -o "$out" "$url" || die "download failed: $url"
    verify "$out"
    ;;
  verify)
    [ $# -eq 1 ] || die "usage: verify <file>"
    verify "$1"
    ;;
  *)
    die "usage: $(basename "$0") {save-b64|download|verify} ..."
    ;;
esac
