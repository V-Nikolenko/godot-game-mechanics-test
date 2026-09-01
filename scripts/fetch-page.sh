#!/usr/bin/env bash
# Fetch a web page that WebFetch could not open.
#
# Many genuinely useful sources - game-dev forums especially - return 403 to
# automated clients while being perfectly public in a browser. Giving up on them
# throws away real research, so this tries harder before conceding:
#
#   1. curl with a normal browser User-Agent   (no third party involved)
#   2. r.jina.ai reader proxy                  (renders the page, returns markdown)
#
#   ./scripts/fetch-page.sh <url> [outfile]
#
# Prints the page text to stdout, or writes it to <outfile> if given.
#
# NOTE: step 2 sends the URL to a third-party reader service. Fine for public
# pages like documentation, blogs and forums. Do NOT use it for anything private,
# internal, authenticated, or containing credentials in the URL.
set -uo pipefail

URL="${1:-}"
OUT="${2:-}"
[ -n "$URL" ] || { echo "usage: fetch-page.sh <url> [outfile]" >&2; exit 2; }

case "$URL" in
  http://*|https://*) ;;
  *) echo "fetch-page.sh: refusing non-http(s) url" >&2; exit 2 ;;
esac

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

emit() {                       # emit <file> <how>
  if [ -n "$OUT" ]; then
    cp "$1" "$OUT"; echo "fetch-page.sh: $2 -> $OUT ($(wc -c < "$OUT") bytes)" >&2
  else
    cat "$1"
  fi
  exit 0
}

# --- 1. direct, with a browser UA -------------------------------------------
CODE="$(curl -sSL --max-time 30 -A "$UA" \
        -H "Accept: text/html,application/xhtml+xml" \
        -H "Accept-Language: en-US,en;q=0.9" \
        -o "$TMP" -w '%{http_code}' "$URL" 2>/dev/null || echo 000)"
if [ "$CODE" = "200" ] && [ "$(wc -c < "$TMP")" -gt 2000 ]; then
  # Strip tags so the caller gets readable text rather than markup.
  sed -e 's/<script[^>]*>.*<\/script>//gI' -e 's/<style[^>]*>.*<\/style>//gI' \
      -e 's/<[^>]*>//g' "$TMP" | sed -e 's/&nbsp;/ /g' -e 's/&amp;/\&/g' \
      -e 's/&quot;/"/g' -e 's/&#39;/'"'"'/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' \
    | grep -v '^[[:space:]]*$' > "${TMP}.txt"
  mv "${TMP}.txt" "$TMP"
  emit "$TMP" "direct (HTTP 200)"
fi

# --- 2. reader proxy ---------------------------------------------------------
CODE2="$(curl -sSL --max-time 45 -o "$TMP" -w '%{http_code}' "https://r.jina.ai/${URL}" 2>/dev/null || echo 000)"
if [ "$CODE2" = "200" ] && [ "$(wc -c < "$TMP")" -gt 500 ]; then
  emit "$TMP" "reader proxy (direct gave HTTP ${CODE})"
fi

echo "fetch-page.sh: could not retrieve ${URL} (direct=${CODE}, proxy=${CODE2})" >&2
exit 1
