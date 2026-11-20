#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Issue 1087: a subscription account's weekly limit was not read for days. Its usage endpoint answered 429, and while
# the Board waited out the Retry-After, the Foreman's watcher (and the engine's guard, acctpaths.test.sh) asked the same
# account every 5 minutes with no regard for it, so the endpoint kept refusing it and limit.json (what /units shows)
# held no limit. Here the watcher's read is refused, its next poll inside the wait must not ask, and the reading
# reaches limit.json at the first Board collect the wait allows, not earlier and not later: the Board, which got no
# 429 itself, waits the 30 s left of the watcher's wait, not its own 300 s TTL. Whole collects (dashboard.sh):
# limit.json is written by the collect's publish, so only a collect shows the reading reaching it.
set -euo pipefail
# date -d is GNU's: on macOS it runs Homebrew's, as Conveyor's does (portable.sh).
. "$(dirname "$0")/../../../conveyor/lib/portable.sh"; p_tools
SOURCE=$(git rev-parse --show-toplevel)
LIM=$SOURCE/.claude/scripts/dashboard_limit.py
T=$(cd "$(mktemp -d /tmp/dashboard-limit-wait-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
# The host file and the account reads' folder are XDG's when set, ahead of the test's HOME: inherited, they are the owner's.
unset XDG_CONFIG_HOME XDG_CACHE_HOME CLAUDE_CONFIG_DIR CONVEYOR_CLAUDE_PROFILES
H=$T/home MAIN=$T/main OUT=$T/out
mkdir -p "$H/.claude" "$MAIN" "$T/empty" "$T/fm" "$T/direct"
git -C "$MAIN" init -q -b main
git -C "$MAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m "feat: base commit"
printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$H/.claude/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"noreply-d@example.com"}}' > "$H/.claude.json"
export USAGE_STUB_LOG=$T/asked USAGE_STUB_ANSWER=$T/answer PYTHONPATH=$SOURCE/.claude/scripts/__tests__/usage-stub
: > "$T/asked"
asks() { wc -l < "$T/asked" | tr -d ' '; }
# Every reader runs as on Linux, so each reads the fixture's credentials file: on a Mac a reader would ask the keychain,
# get no token and ask the endpoint nothing, and a check that it asks nothing would pass whatever it did.
collect() {
  env -u CONVEYOR_HOOK_FIRE_LOG -u CODEX_HOME HOME="$H" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$T/empty" \
    CONVEYOR_SCRATCH="$T/empty" CONVEYOR_DASHBOARD_DIR="$OUT" CONVEYOR_CODEX_REVIEW_HOME="$T/codex-review" \
    timeout 100 bash "$SOURCE/.claude/scripts/dashboard.sh" || fail "dashboard.sh failed (line ${BASH_LINENO[0]})"
}
watch() {
  HOME=$H CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN=$MAIN CONVEYOR_FOREMAN_DIR=$T/fm \
    timeout 60 bash "$SOURCE/conveyor/foreman/watch-limit.sh" --once 2>/dev/null || :
}
NAME=account-$(python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$H/.claude").json
ACCT=$H/.cache/conveyor/accounts/$NAME
# dashboard.sh's clock is `date +%s`, which a test cannot move: the wait passing is the account's kept deadline, and
# the Board's own when it has one, moved back by the same seconds.
pass() { # <seconds>
  local at why
  if [ -s "$OUT/cache/claude-usage.retry" ]; then
    read -r at why < "$OUT/cache/claude-usage.retry"
    printf '%s %s\n' $((at - $1)) "$why" > "$OUT/cache/claude-usage.retry"
  fi
  jq -c --argjson s "$1" '.next -= $s' "$ACCT" > "$ACCT.new" && mv "$ACCT.new" "$ACCT"
}

# The Foreman's watcher is refused; the deadline is kept in the machine's one folder of account reads.
echo '429 600' > "$T/answer"
watch
[ "$(asks)" = 1 ] && [ -s "$ACCT" ] && jq -e '.error == "rate limited (429); retry after 600 s"' "$ACCT" >/dev/null \
  || fail "the watcher's 429 was not asked once and kept in the machine's account folder: asked $(asks), $(cat "$ACCT" 2>&1)"
# Its next poll, inside the wait, asks nothing.
watch
[ "$(asks)" = 1 ] || fail "the Foreman's watcher asked the account inside the wait its 429 named: asked $(asks)"
# The endpoint has a reading again; 30 s of the wait are left: the Board's collect asks nothing yet.
reset=$(date -u -d '+3 days' +%Y-%m-%dT%H:%M:%SZ)
echo "45 $reset" > "$T/answer"
pass 570
collect
[ "$(asks)" = 1 ] && jq -e '.limit.usedPct == null' "$OUT/limit.json" >/dev/null \
  || fail "a collect asked the account with 30 s of its 429's wait left: asked $(asks), $(cat "$OUT/limit.json")"
# The wait is over: the next collect asks, and limit.json holds the reading.
pass 31
collect
[ "$(asks)" = 2 ] && jq -e --arg r "$reset" '.limit == {usedPct: 45, resetsAt: $r}' "$OUT/limit.json" >/dev/null \
  || fail "the first collect after the 429's wait did not write the reading to limit.json: asked $(asks), $(cat "$OUT/limit.json")"

# A kept failure other than a 429 (here a network error, 300 s from its `next`) says nothing of the endpoint's wait:
# the guard's fresh read after a card lands, which passes the same folder, asks at once.
jq -n --argjson n $(($(date +%s) + 300)) '{at: 0, next: $n, body: null, bodyAt: null, error: "network error"}' > "$T/direct/$NAME"
HOME=$H CONVEYOR_HOST_OS=Linux python3 "$LIM" fetch "$H/.claude" "$T/direct" > "$T/fresh.json" 2>"$T/fresh.err" \
  && [ "$(asks)" = 3 ] && jq -e '.seven_day.utilization == 45' "$T/fresh.json" >/dev/null \
  || fail "a kept network error held a fetch back: asked $(asks), $(cat "$T/fresh.err")"

# Two readers ask at once: another one's 429 is saved while this read is out, and this read's answer must not write
# its deadline over. note() is called directly: two real requests cannot be made to land in that order.
python3 - "$SOURCE/.claude/scripts" "$T/direct/$NAME" <<'EOF' || fail "a read that landed after another reader's 429 lost that 429's deadline"
import json, sys, time
sys.path.insert(0, sys.argv[1])
import dashboard_limit as d
now = time.time()
with open(sys.argv[2], "w") as f:
    json.dump({"at": now, "next": now + 3600, "body": None, "bodyAt": None, "error": "rate limited (429); retry after 3600 s"}, f)
d.note(sys.argv[2], {}, now, {"seven_day": {"utilization": 45.0}}, None)
with open(sys.argv[2]) as f:
    k = json.load(f)
assert k["next"] == now + 3600 and k["error"] == "rate limited (429); retry after 3600 s", k
assert k["body"] == {"seven_day": {"utilization": 45.0}} and k["bodyAt"] == now, k
EOF
echo "PASS: dashboard-limit-wait"
