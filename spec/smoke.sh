# Headless end-to-end check against live feeds.
#
# Starts KOReader (SDL "dummy" video driver, no window) with the plugin
# installed into a throwaway data directory, fetches the feeds, opens the
# newest article in the reader and saves screenshots.  Driven over KOReader's
# built-in HTTP inspector plugin.
#
#   nix run .#smoke                         # defaults below
#   SMOKE_OPML=my.opml nix run .#smoke      # your own feed list
#   KO_HOME=/tmp/ko nix run .#smoke         # keep the data directory
#
# Requires: koreader, curl, python3 on PATH (the dev shell has them).

QUICKRSS_SRC="${QUICKRSS_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/quickrss.koplugin}"
KO_HOME="${KO_HOME:-$(mktemp -d -t quickrss-smoke.XXXXXX)}"
PORT="${SMOKE_PORT:-8181}"
API="http://localhost:${PORT}/koreader"
export KO_HOME

mkdir -p "$KO_HOME/plugins" "$KO_HOME/quickrss"
rm -rf "$KO_HOME/plugins/quickrss.koplugin"
cp -r "$QUICKRSS_SRC" "$KO_HOME/plugins/quickrss.koplugin"

cat > "$KO_HOME/settings.reader.lua" <<SETTINGS
return {
    ["httpinspector"] = { ["autostart"] = true, ["port"] = ${PORT} },
    ["quickstart_shown_version"] = 999999999,
    ["lastdir"] = "${KO_HOME}",
}
SETTINGS

if [ -n "${SMOKE_OPML:-}" ]; then
    cp "$SMOKE_OPML" "$KO_HOME/quickrss/feeds.opml"
else
    cat > "$KO_HOME/quickrss/feeds.opml" <<'OPML'
<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <head><title>QuickRSS Feeds</title></head>
  <body>
    <outline text="Ars Technica" type="rss" xmlUrl="https://feeds.arstechnica.com/arstechnica/index"/>
    <outline text="Newsletters">
      <outline text="Astral Codex Ten" type="rss" xmlUrl="https://astralcodexten.substack.com/feed"/>
    </outline>
  </body>
</opml>
OPML
fi

cat > "$KO_HOME/quickrss/settings.lua" <<SETTINGS
return {
    ["article_settings"] = {
        ["items_per_feed"] = ${SMOKE_ITEMS:-3},
        ["articles_dir"] = "${KO_HOME}/quickrss/articles",
    },
}
SETTINGS

log="$KO_HOME/smoke.log"
echo "KO_HOME=$KO_HOME"
SDL_VIDEODRIVER=dummy EMULATE_READER_W="${EMULATE_READER_W:-600}" EMULATE_READER_H="${EMULATE_READER_H:-800}" \
    koreader -d "$KO_HOME" > "$log" 2>&1 &
ko_pid=$!
trap 'kill "$ko_pid" 2>/dev/null || true' EXIT

wait_for() { # wait_for <seconds> <command...>: poll until the command succeeds
    local deadline=$(( $(date +%s) + $1 )); shift
    until "$@"; do
        if [ "$(date +%s)" -ge "$deadline" ]; then return 1; fi
        if ! kill -0 "$ko_pid" 2>/dev/null; then echo "KOReader exited early; see $log"; return 1; fi
        sleep 0.5
    done
}
inspector_up() { curl -sf --max-time 2 "$API/" > /dev/null; }
fetch_done()   { grep -q "QuickRSS: fetch finished" "$log"; }
shot()         { curl -s --max-time 10 "$API/device/screen/bb" -o "$1"; echo "screenshot: $1"; }

wait_for 60 inspector_up || { echo "HTTP inspector did not come up"; exit 1; }
echo "KOReader up, fetching…"
start=$(date +%s)
curl -sf --max-time 5 "$API/ui/quickrss/fetch/" > /dev/null
wait_for "${SMOKE_FETCH_TIMEOUT:-600}" fetch_done || { echo "fetch did not finish"; shot "$KO_HOME/smoke-stuck.png"; exit 1; }
sleep 1
echo "fetch finished in $(( $(date +%s) - start ))s"
shot "$KO_HOME/smoke-result.png"

articles_dir="$KO_HOME/quickrss/articles"
echo "articles written:"
(cd "$articles_dir" && find . -name '*.html' | sort | sed 's/^/  /')
[ "$(find "$articles_dir" -name '*.html' | wc -l)" -gt 0 ] || { echo "no articles written"; exit 1; }

newest=$(find "$articles_dir" -name '*.html' -printf '%T@\t%p\n' | sort -rn | head -1 | cut -f2)
echo "opening: $newest"
curl -sf --max-time 5 "$API/event/Close" > /dev/null # dismiss the fetch summary
sleep 1
quoted=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(chr(34) + sys.argv[1] + chr(34), safe=""))' "$newest")
open_start=$(date +%s.%N)
curl -s --max-time 10 "$API/ui/openFile/$quoted" > /dev/null
opened() { [ "$(curl -s --max-time 2 "$API/ui/document/file")" = "$newest" ]; }
wait_for 60 opened || { echo "article did not open"; shot "$KO_HOME/smoke-noopen.png"; exit 1; }
printf 'opened in %.1fs (includes polling granularity)\n' "$(echo "$(date +%s.%N) - $open_start" | bc 2>/dev/null || python3 -c "import time,sys; print(time.time()-float(sys.argv[1]))" "$open_start")"
sleep 2
echo "document props: $(curl -s --max-time 5 "$API/ui/doc_props")"
shot "$KO_HOME/smoke-article.png"
curl -sf --max-time 5 "$API/event/GotoViewRel/1" > /dev/null; sleep 1
shot "$KO_HOME/smoke-article-p2.png"

echo "log warnings/errors (if any):"
grep -aiE "quickrss|traceback|error" "$log" | grep -viE "QuickRSS (fetching|fetch OK|parsed feed|full-text fetch)" | sed 's/^/  /' | tail -30 || true

kill "$ko_pid" 2>/dev/null || true
wait "$ko_pid" 2>/dev/null || true
trap - EXIT
echo "done"
