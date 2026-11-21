#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The Board's long-lived processes run its scripts' parts too: dashboard.sh --loop sources dashboard_*.sh, and the
# page server runs dashboard_server_*.py. --update restarts the service when main brings a change to one of them, as
# it does for the scripts themselves (RESTART_FILES). Bug caught: a change to a part alone left the loop and the page
# server on the old code. And dashboard.sh without its parts stops at once (exit 1), not run on without them.
set -uo pipefail
SOURCE=$(git rev-parse --show-toplevel)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -C "$1" -c user.name=test -c user.email=noreply@example.com "${@:2}"; }
# Every part the loop sources and the page server runs, as the checkout holds them: one added later is checked too.
parts=()
for f in "$SOURCE"/.claude/scripts/dashboard_*.sh "$SOURCE"/.claude/scripts/dashboard_server_*.py; do [ ! -f "$f" ] || parts+=("${f##*/}"); done
[ ${#parts[@]} -ge 2 ] || fail "no parts of dashboard.sh or dashboard_server.py found"
O=$T/origin M=$T/main
mkdir -p "$O/.claude/scripts" && git init -q -b main "$O" || fail "no origin repository"
for p in "${parts[@]}"; do echo one > "$O/.claude/scripts/$p"; done
g "$O" add -A && g "$O" commit -qm one && git clone -q "file://$O" "$M" || fail "no main checkout"
for p in "${parts[@]}"; do
  echo two >> "$O/.claude/scripts/$p" && g "$O" commit -qam "$p" || fail "no commit of $p"
  : > "$T/restarts"
  # --update's function as dashboard.sh runs it, with the values dashboard.sh gives it, its restart only noted. Each
  # run fetches (FETCH_EVERY 0): the stamp of the last fetch would hold off the next one for 300 s.
  OUT=$T/out CACHE=$T/out/cache PP_MAIN=$M NOTE=$T/restarts bash -c '. "$1" || exit 1
    iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
    restart() { echo restarted >> "$NOTE"; }
    FETCH_EVERY=0; mkdir -p "$CACHE" && update' _ "$SOURCE/.claude/scripts/dashboard_service.sh" 2>/dev/null
  [ "$(git -C "$M" rev-parse HEAD)" = "$(git -C "$O" rev-parse HEAD)" ] || fail "update did not bring main forward to the change to $p"
  [ -s "$T/restarts" ] || fail "a change to $p alone did not restart the service"
done
# A copy of dashboard.sh with no parts beside it: --restart would else run on to "restart: command not found".
mkdir -p "$T/alone/.claude/scripts" && cp "$SOURCE/.claude/scripts/dashboard.sh" "$T/alone/.claude/scripts/" || fail "no copy"
CONVEYOR_MAIN=$T/alone CONVEYOR_DASHBOARD_DIR=$T/alone/out bash "$T/alone/.claude/scripts/dashboard.sh" --restart > "$T/alone.out" 2>&1
rc=$?
[ "$rc" = 1 ] && grep -q 'dashboard_panels.sh' "$T/alone.out" || fail "dashboard.sh without its parts exited $rc: $(cat "$T/alone.out")"
echo "PASS: dashboard-parts"
