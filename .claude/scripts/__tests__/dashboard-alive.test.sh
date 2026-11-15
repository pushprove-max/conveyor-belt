#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# dashboard.sh's heartbeat (alive, every 15 s) and its page copy (copy_view, every cycle), by function: they are
# defined here from dashboard.sh itself, with no loop. Issue 566: alive read and checksummed every page file each
# 15 s, three.js too (700 KB), to stamp `view`; the checksum is now worked out when copy_view copies a file.
set -euo pipefail
SOURCE=$(git rev-parse --show-toplevel)
. "$SOURCE/conveyor/lib/portable.sh"; p_tools
T=$(cd "$(mktemp -d /tmp/dashboard-alive-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
eval "$(sed -n '/^view_files() /p; /^copy_view() {/,/^}/p; /^alive() {/,/^}/p' "$SOURCE/.claude/scripts/dashboard.sh")"
declare -F view_files copy_view alive >/dev/null || fail "dashboard.sh no longer defines view_files, copy_view and alive"
VIEW_SRC=$T/src OUT=$T/out
mkdir -p "$VIEW_SRC/panels" "$OUT"
echo 'page' > "$VIEW_SRC/index.html"; echo 'core' > "$VIEW_SRC/app.js"; echo 'panel' > "$VIEW_SRC/panels/belt.js"
view() { sed -e '1s/^window\.DASH_ALIVE = //' -e '$s/;$//' "$OUT/alive.js" | jq -c .view; }
sum() { (cd "$OUT" && view_files | xargs -d '\n' cat | cksum | cut -d' ' -f1); }

# Before copy_view has worked out a checksum, view is null, which the page does not compare (no reload).
alive
[ "$(view)" = null ] || fail "alive_without_a_checksum_says_null: $(cat "$OUT/alive.js")"
copy_view
[ "$(view_files)" = "$(cat "$OUT/.view-files")" ] && [ "$(cat "$OUT/.view")" = "$(sum)" ] \
  || fail "copy_view_stamps_the_page: .view must be the checksum of the installed page files: $(cat "$OUT/.view")"
alive
[ "$(view)" = "\"$(sum)\"" ] || fail "alive_gives_copy_views_checksum: $(cat "$OUT/alive.js")"
# Bug: alive read every page file each 15 s. An installed file changed behind copy_view's back must not change view:
# alive did not read it.
was=$(view); echo 'changed here' >> "$OUT/app.js"
alive
[ "$(view)" = "$was" ] || fail "alive_reads_no_page_file: view changed with an installed file copy_view did not copy: $(cat "$OUT/alive.js")"
# A landed page change: copy_view copies it and works the checksum out again, so a page left open reloads.
echo 'new core' > "$VIEW_SRC/app.js"
copy_view; alive
[ "$(view)" = "\"$(sum)\"" ] && [ "$(view)" != "$was" ] || fail "copy_view_restamps_a_changed_page: $(cat "$OUT/alive.js")"
# A page file gone from the checkout leaves the list: the checksum is worked out again, though no file was copied.
was=$(view); rm "$VIEW_SRC/panels/belt.js"
copy_view; alive
[ "$(view)" = "\"$(sum)\"" ] && [ "$(view)" != "$was" ] || fail "copy_view_restamps_when_a_page_file_goes: $(cat "$OUT/alive.js")"
# Nothing changed: copy_view writes nothing, not even the checksum.
before=$(stat -c '%i %Y' "$OUT/.view")
copy_view
[ "$(stat -c '%i %Y' "$OUT/.view")" = "$before" ] || fail "copy_view_unchanged_writes_nothing: .view was rewritten"
echo "PASS: dashboard-alive"
