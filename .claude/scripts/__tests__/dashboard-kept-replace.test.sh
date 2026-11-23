#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# dashboard.sh --publish builds data.js from the parts the last cycle kept (kept_parts in dashboard_panels.sh) while the
# cycle replaces them by whole new files. Bug caught: kept_parts copied them with cp, which sees a part replaced during
# its copy, skips it and exits non-zero, so the live feed's publish failed ("cp: skipping file ..., as it was replaced
# while being copied") for a part only being refreshed, and data.js kept the last snapshot. Now each part is read through
# one open, so a part replaced during the read still gives a whole one (the old), and a part that cannot be read at all
# goes on the page as "not read yet".
set -uo pipefail
SOURCE=$(git rev-parse --show-toplevel)
DASH=$SOURCE/.claude/scripts/dashboard.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

OUT=$T/out CACHE=$T/out/cache MAIN=$T/main
mkdir -p "$CACHE" "$MAIN/conveyor" "$T/home" "$T/ws" "$T/scratch"
echo '{"host":"devbox","ssh":"max@devbox","main":"/srv/main","records":[{"repo":"sample","main":"/srv/main"}]}' > "$MAIN/conveyor/host.json"
# A fresh stream.json with no record, so the publish needs no host.
echo '{"host":"devbox","reachable":true,"error":null,"records":[],"stream":{"live":true,"heardAt":"2026-11-23T10:00:00Z","since":null,"error":null}}' > "$OUT/stream.json"
echo '{"foremen":[{"id":"old"}],"error":null}' > "$CACHE/part-foremen.json"
echo '{"foremen":[{"id":"new"}],"error":null}' > "$T/foremen.new"
echo '{"limit":{"limit":null},"error":null}' > "$CACHE/part-limit.json"
echo '{"decisions":[],"unsent":[],"error":null}' > "$CACHE/part-decisions.json"
echo '{"records":[],"error":null}' > "$CACHE/part-lanes.json"

# publish -- one dashboard.sh --publish, as the live feed runs it. The two stubs act on the foremen part only, and each
# leaves $T/replaced when it has put the new file (a whole new file, as the cycle writes) in place. cat opens the part,
# replaces it, then reads the file it opened to its end, as a real cat does (the old one). cp does not open the part: it
# replaces it and fails as macOS's cp does on a file replaced during its copy (exit 1), so a kept_parts that copies with
# cp fails here on any system.
cat() {
  if [ "${1-}" = -- ] && [ "${2##*/}" = part-foremen.json ]; then
    exec 9< "$2" && command cp "$T/foremen.new" "$2.tmp" && mv -f "$2.tmp" "$2" && : > "$T/replaced"
    command cat <&9; local rc=$?; exec 9<&-; return $rc
  fi
  command cat "$@"
}
cp() {
  if [ "${2##*/}" = foremen.json ]; then
    command cp "$T/foremen.new" "$CACHE/part-foremen.json.tmp" && mv -f "$CACHE/part-foremen.json.tmp" "$CACHE/part-foremen.json" && : > "$T/replaced"
    echo "cp: skipping file '$1', as it was replaced while being copied" >&2; return 1
  fi
  command cp "$@"
}
export -f cat cp; export T CACHE
publish() {
  rm -f "$T/replaced"
  env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/home" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$T/ws" \
    CONVEYOR_SCRATCH="$T/scratch" CONVEYOR_DASHBOARD_DIR="$OUT" timeout 30 bash "$DASH" --publish 2> "$T/err"
}
# data <filter> -- the page's data (data.js) as JSON, through the jq filter $1.
data() { sed -e 's/^window.DASH = //' -e '$ s/;$//' "$OUT/data.js" | jq -c "$1" 2>&1; }

publish || fail "--publish failed while the foremen part was replaced during its read: $(cat "$T/err")"
[ -e "$T/replaced" ] || fail "the replace never overlapped the read of the foremen part, so this run proved nothing"
v=$(data '[.. | objects | select(has("foremen")) | .foremen | arrays | .[].id] | unique')
[ "$v" = '["old"]' ] || fail "data.js has not the one whole foremen part (the old, which the read had open): '$v'"
# The new file is in place now: the next publish reads it whole.
publish || fail "--publish failed on the part the replace left: $(cat "$T/err")"
v=$(data '[.. | objects | select(has("foremen")) | .foremen | arrays | .[].id] | unique')
[ "$v" = '["new"]' ] || fail "the next publish has not the new foremen part: '$v'"

# A part no cycle kept yet, and one that cannot be read at all (a directory in its place): "not read yet", the publish goes on,
# and the two say what is true of each.
rm -f "$CACHE/part-lanes.json"; rm -f "$CACHE/part-limit.json"; mkdir "$CACHE/part-limit.json"
publish || fail "--publish failed for a part that cannot be read: $(cat "$T/err")"
v=$(data '[.. | objects | select(has("limitError")) | .limitError] | first')
case $v in *"not read yet"*) ;; *) fail "the unreadable limit part is not 'not read yet' on the page: '$v'" ;; esac
case $v in *"just started"*) fail "the unreadable limit part says the collector just started: '$v'" ;; esac
grep -q 'just started' "$OUT/data.js" || fail "the part no cycle kept (lanes) does not say the collector just started"
echo "PASS: dashboard-kept-replace"
