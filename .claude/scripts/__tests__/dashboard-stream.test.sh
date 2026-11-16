#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# The dashboard's live Conveyor feed (dashboard_stream.py): one ssh per record running `conveyor.sh watch`,
# kept in stream.json and published into data.js at once. The page is what the owner reads instead of asking, so: what the
# host streams is on the page in seconds; a stream that drops is opened again and starts from a whole snapshot; a
# stream that goes quiet is not taken for a live one; and while the host cannot be reached the page keeps the last
# board and says it is stale, with when the host was last heard from.
set -euo pipefail
# This file's own stat -c is a GNU call: on macOS it runs Homebrew's, as Conveyor's does (portable.sh).
. "$(dirname "$0")/../../../conveyor/lib/portable.sh"; p_tools
. "$(dirname "$0")/../../../conveyor/tests/wait.sh"

SOURCE=$(git rev-parse --show-toplevel)
FEED=$SOURCE/.claude/scripts/dashboard_stream.py
TOP=$(cd "$(mktemp -d /tmp/dashboard-stream-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$TOP"' EXIT
# The host file is XDG_CONFIG_HOME's when it is set, ahead of the test's HOME: an inherited one is the owner's real host.
unset XDG_CONFIG_HOME
fail() { echo "FAIL: $*" >&2; [ ! -s "$T/feed.err" ] || sed 's/^/  feed: /' "$T/feed.err" >&2; exit 1; }

# The feeds below run side by side, each in a part of its own (( fresh <part>; ... ) &): one whose stream drops and
# fails, one whose host goes quiet and comes back, one whose host file changes, one sent ten changes in a second and
# one with no change for 30 s (on a fake clock). The file takes the slowest one's
# time, not their sum.
# fresh <part> -- the part's own folder ($T), host file, ssh stub and kept parts; its feed ($PID) ends when it does, and
# the stand-in streams it holds open run under a name of its own ($HELD).
fresh() {
T=$TOP/$1 PID='' pass=0 HELD=stream-held-$$-$1
trap '[ -z "$PID" ] || kill "$PID" 2>/dev/null' EXIT
MAIN=$T/main OUT=$T/out BIN=$T/bin
mkdir -p "$MAIN/conveyor" "$OUT/cache" "$BIN" "$T/home" "$T/ws" "$T/scratch"
echo '{"host":"devbox","ssh":"max@devbox","main":"/srv/main","records":[{"repo":"sample","main":"/srv/main"}]}' > "$MAIN/conveyor/host.json"
# The ssh stub: the Nth connection runs $T/conn.N, the host's stream for it; with no such file the host cannot be
# reached (exit 255). Each connection's arguments are kept in ssh-calls.
cat > "$BIN/ssh" <<EOF
#!/usr/bin/env bash
n=\$((\$(cat "$T/conns" 2>/dev/null || echo 0) + 1)); echo \$n > "$T/conns"; printf '%s\n' "\$*" >> "$T/ssh-calls"
echo "\${EPOCHREALTIME/[.,]/}" > "$T/conn-at.\$n" # when it began, in microseconds
[ -f "$T/conn.\$n" ] || { echo 'ssh: connect to host devbox port 22: Connection refused' >&2; exit 255; }
exec bash "$T/conn.\$n"
EOF
chmod +x "$BIN/ssh"
# The slower parts, as the last 60 s cycle kept them for --publish.
echo '{"limit":null,"error":"the usage limit was not read: test"}' > "$OUT/cache/part-limit.json"
echo '{"decisions":[],"error":null,"unsent":[]}' > "$OUT/cache/part-decisions.json"
echo '{"records":[{"repo":"sample","fast":null,"research":null}]}' > "$OUT/cache/part-lanes.json"
}
# feed -- the part's feed, started; its pid is PID.
feed() {
  env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/home" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$T/ws" \
    CONVEYOR_SCRATCH="$T/scratch" CONVEYOR_DASHBOARD_DIR="$OUT" \
    CONVEYOR_STREAM_DEAD=2 CONVEYOR_STREAM_TICK=1 CONVEYOR_STREAM_BACKOFF=0.25 python3 "$FEED" "$OUT" "$MAIN" 2> "$T/feed.err" & PID=$!
}
# held <from> -- connections <from> to <from>+19 each send a whole snapshot, then stay open under the part's $HELD name.
held() {
  local i
  for i in $(seq "$1" $(($1 + 19))); do
    printf 'echo %q\nexec -a %s sleep 300\n' "$S1" "$HELD" > "$T/conn.$i" # sleep: the stand-in stream, held open under a name the test finds
  done
}
PARTS=()
started() { PARTS+=("$1:$!"); } # <part>, after its ( ... ) &

NOWISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# snap <belt json> -- one record's snapshot, as conveyor.sh prints it, with these cards on the belt.
snap() {
  jq -cn --arg day "$(date +%F)" --arg now "$NOWISO" --argjson belt "$1" '
    {time: $now, day: $day, needsYou: {waiting: [], blocked: []}, belt: $belt, queue: {next: [], held: {}, order: [], holding: [], skipped: []}, landed: [],
     control: null, health: {time: $now, loop: true, state: "running", newest: $now, blocked: [], waiting: [], stuck: [], unpushed: [], pushError: null, pushFailingSince: null,
              gh: true, diskFreeKb: 500000000, builderCap: 3, models: {claude: "claude-x", codex: "gpt-x"}, guard: {at: null, reading: null, readAt: null, missing: false}},
     cost: {today: 0, week: 0, perLanded: null, landedAfter: {"1": 0, "2": 0, "3": 0, more: 0}, unpricedSteps: 0, cards: []}}'
}
card() { jq -cn --arg c "$1" --argjson i "$2" --arg now "$NOWISO" '{card: $c, issue: $i, title: "T\($i)", step: "build", review: null, of: 3, stepAt: $now, landed: false,
  model: "claude-x", tokens: {claude: 0, codex: 0}, usd: null, reading: false, live: null, reviews: [], track: null}'; }
line() { jq -cn --arg t snapshot --argjson s "$1" '{type: $t, at: "x", why: "start", snap: $s, repoUrl: "https://github.com/o/r", lastPushAt: null}'; }
S1=$(line "$(snap "[$(card c1 11)]")")
S2=$(line "$(snap "[$(card c1 11), $(card c2 12)]")")
LIVE='{"type":"live","at":"x","cards":{"c1":{"tokens":{"claude":5000,"codex":0},"usd":1.25,"reading":true,"live":{"turns":4,"lastOutputAt":"'"$NOWISO"'","action":"Bash: npm test"},"files":null}}}'
ERR='{"type":"error","at":"x","error":"the snapshot failed: jq: error"}'
BEAT='{"type":"beat","at":"x"}' AFTER=${LIVE/Bash: npm test/after three beats}

data() { sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$OUT/data.js" 2>/dev/null; }
stream() { cat "$OUT/stream.json" 2>/dev/null; }
# until_is <what> <reader> <jq test> [<what of the reader's to show>]: waits until what the reader prints passes the test.
until_is() {
  UI_R=$2 UI_J=$3
  wait_until '"$UI_R" | jq -e "$UI_J"' || fail "$1: never (jq: $3; $2: $("$2" | jq -c "${4:-.}" 2>/dev/null | cut -c1-1200))"
}

( fresh lost
# The first stream: a snapshot, then a live line, then it ends when the test drops it.
printf 'echo %q\nsleep 0.3\necho %q\nwhile [ ! -e %q ]; do echo %q; sleep 0.3; done\n' "$S1" "$LIVE" "$T/drop" '{"type":"beat","at":"x"}' > "$T/conn.1" # sleep: the stand-in stream's pace, a line every 0.3 s
# The second: a whole snapshot again, beats (with one failed snapshot once the test says so), then silence once the
# test says so.
printf 'echo %q\nwhile [ ! -e %q ]; do [ ! -e %q ] || [ -e %q ] || { echo %q; echo %q; echo %q; echo %q; echo %q; : > %q; }; echo %q; sleep 0.3; done\nsleep 100\n' "$S2" "$T/quiet" "$T/fail" "$T/failsent" "$ERR" "$BEAT" "$BEAT" "$BEAT" "$AFTER" "$T/failsent" "$BEAT" > "$T/conn.2" # sleep: the stand-in stream, open and silent at its end
feed

# What the host streams is on the page in seconds: the belt, then the live fields laid over it.
until_is "a_snapshot_reaches_data_js" data '.panels.belt.data.cards | map(.card) == ["c1"]' .panels.belt
until_is "the_feed_is_live" stream '.stream.live == true and .records[0].steered and .records[0].repoUrl == "https://github.com/o/r"'
grep -q 'CONVEYOR_MAIN=/srv/main exec bash /srv/main/conveyor/conveyor.sh watch' "$T/ssh-calls" || fail "the ssh command: $(cat "$T/ssh-calls")"
until_is "a_live_line_reaches_data_js" data '.panels.belt.data.cards[0] | .live.action == "Bash: npm test" and .usd == 1.25 and .tokens.claude == 5000 and .reading' .panels.belt
until_is "health_says_live" data '.panels.health.data.stream | .live == true and (.heardAt | type) == "string" and .since == null'
pass=$((pass + 5))

# A stream that drops is opened again, and starts from a whole snapshot: the live line of the first is gone with it.
: > "$T/drop"
until_is "a_dropped_stream_reconnects_with_a_full_snapshot" data '.panels.belt.data.cards | map(.card) == ["c1", "c2"]' .panels.belt
[ "$(cat "$T/conns")" = 2 ] || fail "a_dropped_stream_reconnects: $(cat "$T/conns") connections"
data | jq -e '.panels.belt.data.cards[0].live == null and .panels.health.data.stream.live == true' >/dev/null || fail "the new stream's snapshot is not the whole board: $(data | jq -c .panels.belt)"
pass=$((pass + 3))

# A snapshot that fails on the host: the beats that follow do not keep the board marked live, and the page says why.
: > "$T/fail"
until_is "a_failed_snapshot_is_stale_not_live" data '.panels.health.data.stream | .live == false and (.since | type) == "string" and (.error | test("the snapshot failed"))' .panels.health
# Three beats follow the failure, then a live line: once that line is on the page the beats have been read, in order.
until_is "the_beats_after_a_failed_snapshot_are_read" data '.panels.belt.data.cards[0].live.action == "after three beats"' .panels.belt
data | jq -e '.panels.health.data.stream.live == false' >/dev/null || fail "a beat after a failed snapshot marked the board live again: $(data | jq -c .panels.health.data.stream)"
data | jq -e '.panels.belt.data.cards | map(.card) == ["c1", "c2"]' >/dev/null || fail "the board was dropped after a failed snapshot: $(data | jq -c .panels.belt)"
pass=$((pass + 3))
echo "$pass" > "$T/pass"
) & started lost

( fresh down
# A stream with both cards on its board and beats, then silence once the test says so; the host refuses every
# connection after it.
printf 'echo %q\nwhile [ ! -e %q ]; do echo %q; sleep 0.3; done\nsleep 100\n' "$S2" "$T/quiet" "$BEAT" > "$T/conn.1" # sleep: the stand-in stream, open and silent at its end
feed
until_is "the board is on the page before the stream goes quiet" data '.panels.belt.data.cards | map(.card) == ["c1", "c2"]' .panels.belt
# A stream that goes quiet is closed (no line in CONVEYOR_STREAM_DEAD s); the host can no longer be reached: the
# page keeps the last board, marked stale, with when the host was last heard from and why.
: > "$T/quiet"
until_is "the_stale_marker_shows_when_the_stream_is_down" data '.panels.health.data.stream | .live == false and (.heardAt | type) == "string" and (.since | type) == "string" and (.error | test("Connection refused"))' .panels.health
data | jq -e '.panels.belt.data.cards | map(.card) == ["c1", "c2"]' >/dev/null || fail "the board was dropped while the stream is down: $(data | jq -c .panels.belt)"
data | jq -e '.panels.health.data.host.reachable == false' >/dev/null || fail "an unreachable host is not said to be: $(data | jq -c .panels.health.data.host)"
stream | jq -e '.stream.live == false and (.records | length) == 1' >/dev/null || fail "stream.json while down: $(stream | cut -c1-600)"
[ "$(cat "$T/conns")" -ge 2 ] || fail "a quiet stream was not closed and tried again: $(cat "$T/conns") connections"
pass=$((pass + 5))

# It keeps trying, further apart each time, and stream.json is kept fresh while it does, so its age says the feed runs.
# Connection 2 is the first the host refuses. Each try begins once the one before has ended and the wait after it is
# over (CONVEYOR_STREAM_BACKOFF, 0.25 s, twice as long each time), so the times between them have a floor each; a
# busy machine makes them longer, never shorter. A wait that did not grow (0.25 s each time) stays under the last
# floor by 0.75 s of a try's own time.
at=$(stat -c %Y "$OUT/stream.json")
wait_until '[ -s "$T/conn-at.5" ]' || fail "the stream that is down is not tried again: $(cat "$T/conns") connections"
apart() { echo $(( $(cat "$T/conn-at.$2") - $(cat "$T/conn-at.$1") )); }
[ "$(apart 2 3)" -ge 250000 ] && [ "$(apart 3 4)" -ge 500000 ] && [ "$(apart 4 5)" -ge 1000000 ] \
  || fail "the retries do not come further apart: $(apart 2 3), $(apart 3 4) and $(apart 4 5) microseconds between tries 2 to 5"
wait_until '[ "$(stat -c %Y "$OUT/stream.json")" -gt "$at" ]' || fail "stream.json is not rewritten while the stream is down"
pass=$((pass + 2))

# The host is back; then the feed is stopped (the loop's exit): the stream it holds open ends with it.
held $(($(cat "$T/conns") + 1))
until_is "the_feed_comes_back_once_the_host_does" stream '.stream.live == true'
pgrep -f "$HELD" >/dev/null || fail "the test's stream is not running"
kill "$PID"; wait "$PID" 2>/dev/null || true; PID=''
wait_until '! pgrep -f "$HELD"' || :
! pgrep -f "$HELD" >/dev/null || { pkill -f "$HELD"; fail "a stream outlived the feed that opened it"; }
pass=$((pass + 2))
echo "$pass" > "$T/pass"
) & started down

( fresh hostchange; held 1
# The host file changes under a running feed: /control reads it per request, so the page does not keep showing
# the cards of the host it named before. The feed makes stream.json the new host's, with no card, builds data.js from
# it at once, and ends; dashboard.sh --loop starts it again.
# Bug caught: the feed only removed stream.json, so data.js kept the old host's cards while /control steered the new one.
rm -f "$OUT/stream.json" "$OUT/data.js"  # what the wait below reads is this feed's, never the last one's
feed
until_is "the_feed_runs_again" data '(.panels.belt.data.cards | length) > 0 and .panels.health.data.stream.live == true' .panels.belt
echo '{"host":"otherbox","ssh":"max@otherbox","main":"/srv/other","records":[{"repo":"sample","main":"/srv/other"}]}' > "$MAIN/conveyor/host.json"
wait_until '! kill -0 "$PID" 2>/dev/null' || :
! kill -0 "$PID" 2>/dev/null || fail "the feed kept running after the host file changed"
PID=''
stream | jq -e '.host == "otherbox" and .records == [] and (.stream.error | test("host.json changed"))' >/dev/null \
  || fail "stream.json is not the new host's with no card: $(stream | cut -c1-300)"
data | jq -e '.panels.belt.data.cards == [] and .panels.health.data.host.name == "otherbox"' >/dev/null \
  || fail "data.js still shows the old host's cards after the host file changed: $(data | jq -c '[.panels.belt, .panels.health.data.host]' | cut -c1-600)"
wait_until '! pgrep -f "$HELD"' || :
! pgrep -f "$HELD" >/dev/null || { pkill -f "$HELD"; fail "a stream outlived the feed whose host file changed"; }
pass=$((pass + 4))
echo "$pass" > "$T/pass"
) & started hostchange

( fresh burst
# Ten changes in one second: data.js is built at most once in that second, and the last change is on the page after
# the next build, with only beats after it. Each build (dashboard.sh --publish) is a bash and three jq over a feed of
# up to a megabyte. Bug caught: the feed built data.js once for each changed line, almost back to back.
# The bash stub logs when each build starts. It returns at once and the real build runs on behind it, so the count
# is the feed's own pace, not how long a build takes (a build that takes 2 s would pace the old feed too).
REAL_BASH=$(command -v bash)
printf '#!%s\n[ "${2-}" != --publish ] || { echo "${EPOCHREALTIME/[.,]/}" >> %q; %q "$@" </dev/null >/dev/null 2>&1 & exit 0; }\nexec %q "$@"\n' \
  "$REAL_BASH" "$T/builds" "$REAL_BASH" "$REAL_BASH" > "$BIN/bash"
chmod +x "$BIN/bash"
{ printf 'echo %q\nwhile [ ! -s %q ]; do echo %q; sleep 0.2; done\n' "$S1" "$OUT/data.js" "$BEAT"  # sleep: the stand-in stream's beat until the first build
  printf 'for _ in 1 2 3 4 5 6 7 8; do echo %q; sleep 0.3; done\n' "$BEAT"  # sleep: 2.4 s of beats, so the snapshot's build is 2 s behind
  printf 'echo "${EPOCHREALTIME/[.,]/}" > %q\n' "$T/burst-at"
  for i in $(seq 10); do printf 'echo %q; sleep 0.1\n' "${LIVE/Bash: npm test/change $i}"; done  # sleep: ten changes in one second
  printf 'while :; do echo %q; sleep 0.3; done\n' "$BEAT"  # sleep: the stand-in stream's pace
} > "$T/conn.1"
feed
until_is "the_last_of_ten_changes_reaches_data_js" data '.panels.belt.data.cards[0].live.action == "change 10"' .panels.belt
at=$(cat "$T/burst-at")
in_second=$(awk -v a="$at" '$1 >= a && $1 < a + 1000000' "$T/builds" | wc -l)
[ "$in_second" -le 1 ] || fail "ten changes in one second built data.js $in_second times in that second: $(cat "$T/builds")"
gaps=$(awk 'NR > 1 && $1 - p < 1900000 { print $1 - p } { p = $1 }' "$T/builds")
[ -z "$gaps" ] || fail "data.js was built again under 2 s after a build: $gaps microseconds apart"
pass=$((pass + 3))
echo "$pass" > "$T/pass"
) & started burst

( fresh onemachine
# Bug caught (#112): the feed followed only a host file that named a build machine, so on the host file setup writes
# (records alone) it never started and the page said the live feed was not running. On one machine it runs
# `conveyor.sh watch` of the Board's own copy of Conveyor here, never over ssh, and says it is local. A record whose
# checkout has a space in its path (setup records it unchanged) is read too, and its path is quoted in the command.
echo "{\"records\":[{\"repo\":\"sample\",\"main\":\"$MAIN\"},{\"repo\":\"spaced\",\"main\":\"/srv/my project\"}]}" > "$MAIN/conveyor/host.json"
python3 - "$FEED" "$MAIN" "$T/home" "$SOURCE" <<'PY' || fail "the feed on one machine: see above"
import importlib.util, os, sys
os.environ['XDG_CONFIG_HOME'] = sys.argv[3]  # no host file of this machine: main's
spec = importlib.util.spec_from_file_location('feed', sys.argv[1]); ds = importlib.util.module_from_spec(spec); spec.loader.exec_module(ds)
main, engine = sys.argv[2], sys.argv[4]
cfg, why = ds.config(main)
assert why is None, why
assert cfg == (ds.this_host(), main, [('sample', main), ('spaced', '/srv/my project')], None, engine), cfg
class Stop(Exception):
    pass
calls = []
def popen(argv, **kw):
    calls.append(argv)
    raise Stop
ds.subprocess.Popen = popen
f = ds.Feed('/nowhere', '/nowhere/dashboard.sh', main, *cfg)
for r in f.recs:
    try:
        f.follow(r)
    except Stop:
        pass
assert calls == [['bash', '-c', 'CONVEYOR_MAIN=%s exec bash %s/conveyor/conveyor.sh watch' % (main, engine)],
                 ['bash', '-c', "CONVEYOR_MAIN='/srv/my project' exec bash %s/conveyor/conveyor.sh watch" % engine]], calls
assert f.doc()['local'] is True
PY
echo 1 > "$T/pass"
) & started onemachine

( fresh quiet
# No line changes anything for 30 s (only beats): no build of data.js. With none for 45 s data.js is built once more,
# so the page's Live (health.js STREAM_EXPIRE_MS) does not expire on a quiet feed. The feed's clock is a fake one, so
# its 30 s take no time. Bug caught: the feed built data.js every 10 s whether or not a line changed.
python3 - "$FEED" "$OUT" "$MAIN" "$T/home" <<'PY' || fail "a quiet feed: see above"
import importlib.util, os, sys
os.environ['XDG_CONFIG_HOME'] = sys.argv[4]  # no host file of this machine: main's
os.environ.pop('CONVEYOR_STREAM_TICK', None)  # the feed's own 10 s tick
spec = importlib.util.spec_from_file_location('feed', sys.argv[1]); ds = importlib.util.module_from_spec(spec); spec.loader.exec_module(ds)

class Stop(Exception):
    pass
class Clock:  # each sleep moves it on, with a beat from the host; past `until` the ticker is stopped
    t, beat, until = 1000.0, None, float('inf')
    def monotonic(self): return self.t
    def time(self): return self.t
    def sleep(self, s):
        self.t += s
        self.beat()
        if self.t > self.until: raise Stop
clock = Clock(); ds.time = clock
builds = []
ds.subprocess.run = lambda *a, **k: builds.append(clock.t) or type('R', (), {'returncode': 0})()
cfg, why = ds.config(sys.argv[3]); assert why is None, why
f = ds.Feed(sys.argv[2], '/nowhere/dashboard.sh', sys.argv[3], *cfg)
rec = f.recs[0]
clock.beat = lambda: f.take(rec, {'type': 'beat'})
f.take(rec, {'type': 'snapshot', 'snap': {'belt': []}})
f.publish_next()
assert builds == [1000.0], builds
def ticks(n):
    clock.until = clock.t + n
    try: f.ticker()
    except Stop: pass
ticks(30)
assert not f.dirty.is_set() and builds == [1000.0], 'a build was asked for with no changed line in 30 s'
ticks(20)
assert f.dirty.is_set(), 'no build in 50 s with no change: the page would take the quiet feed for a stopped one'
PY
pass=$((pass + 2))
echo "$pass" > "$T/pass"
) & started quiet

# Both parts ran to their end (each wrote its pass count last); the file's checks are theirs added up.
pass=0 bad=()
for p in "${PARTS[@]}"; do
  if wait "${p#*:}" && [ -s "$TOP/${p%%:*}/pass" ]; then pass=$((pass + $(cat "$TOP/${p%%:*}/pass"))); else bad+=("${p%%:*}"); fi
done
[ ${#bad[@]} -eq 0 ] || fail "these parts failed (their FAIL lines are above): ${bad[*]}"
echo "PASS: dashboard-stream ($pass checks)"
