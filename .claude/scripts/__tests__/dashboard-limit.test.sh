#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The usage limit and list-price cost (dashboard_limit.py), alone and through the collector. The owner paces their week by
# these figures, so the math must match the design's own numbers, a stale or finished week must never read as this
# one, an unpriced request must never read as $0, and the reading must be the account in use's.
set -euo pipefail
# This file's own touch -d and timeout are GNU calls: on macOS they run Homebrew's, as Conveyor's do (portable.sh).
. "$(dirname "$0")/../../../conveyor/lib/portable.sh"; p_tools
SOURCE=$(git rev-parse --show-toplevel)
DASH=$SOURCE/.claude/scripts/dashboard.sh
T=$(cd "$(mktemp -d /tmp/dashboard-limit-test.XXXXXX)" && pwd -P)
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
# The limit read also walks the review sessions' Codex folder; without this a collect reads the owner's real spend.
export CONVEYOR_CODEX_REVIEW_HOME=$T/codex-review
# The host file is XDG_CONFIG_HOME's when it is set, ahead of the test's HOME: an inherited one is the owner's real host.
unset XDG_CONFIG_HOME
fail() { echo "FAIL: $*" >&2; exit 1; }
MAIN=$T/main BIN=$T/bin OUT=$T/out
mkdir -p "$MAIN/.claude/metrics" "$BIN" "$T/home" "$T/empty"
git -C "$MAIN" init -q -b main
git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: base commit"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
# One collect, bounded: a hang fails here instead of running into the file's budget.
run() {
  local rc=0
  # A collect in the same second as the last one would be answered from that cycle's own request cache. Each part
  # below that collects has its own dashboard folder, so its own last second ($RUN_END).
  while [ "$(date +%s)" = "$(cat "$RUN_END" 2>/dev/null)" ]; do sleep 0.1; done
  env -u CONVEYOR_HOOK_FIRE_LOG -u CODEX_HOME HOME="$T/home" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" \
    CONVEYOR_WORKSPACES="$T/empty" CONVEYOR_SCRATCH="$T/empty" CONVEYOR_DASHBOARD_DIR="$OUT" "$@" timeout 120 bash "$DASH" || rc=$?
  [ "$rc" -ne 124 ] || fail "HUNG: a collect ran past 120 s (line ${BASH_LINENO[0]})"
  [ "$rc" -eq 0 ] || fail "dashboard.sh exited $rc (line ${BASH_LINENO[0]})"
  date +%s > "$RUN_END"
}
# The parts of this file, each ( ... ) & part <name>, run side by side: the file takes its slowest part's time, not
# their sum. Each writes and reads its own files; the one stub a part adds ($BIN/security, the account part's) is
# called only by a collect on a Mac, which no other part's is. A part that fails stops itself; the file fails at the
# end, once every part has ended, naming each part that failed.
PARTS=()
part() { PARTS+=("$1:$!"); }
D=$OUT/data.js
# q reads the page's health part, where the collector puts the limit reading.
q() { sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$D" | jq -e ".panels.health.data | ($1)" >/dev/null || fail "$2 (jq: $1)"; }
hist() { jq -es "$1" "$LOUT/cache/limit-history.jsonl" >/dev/null || fail "$2 (history: $(cat "$LOUT/cache/limit-history.jsonl" 2>&1))"; }

# --- the 7-day limit. The owner paces their week by the goal and the pace, so the math must match the design's own
# numbers, a stale or finished week must never read as this one, and the request count must not double
# count a request streamed over several lines or re-read on the next call ---
LIM=$SOURCE/.claude/scripts/dashboard_limit.py
price() { python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(d.price($1))"; }
(
pace() { python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(json.dumps(d.pace($1)))"; }
# 94.5 h of the 168 h week gone: the goal is 56.25%; 44% used is 12.25 points
# under, which is 12.25% of the week, 74088 s (20 h 34 m), not a rounded 12 points' 72576 s.
[ "$(pace '44, 1000000 + 73.5 * 3600, 1000000' | jq -c '[.goalPct, .underPts, .paceSec, .timeLeftSec]')" = '[56.25,12.25,74088,264600]' ] \
  || fail "goal, pace and time left must match the linear week: $(pace '44, 1000000 + 73.5 * 3600, 1000000')"
[ "$(pace '70, 1000000 + 73.5 * 3600, 1000000' | jq -c '[.underPts, .paceSec]')" = '[-13.75,-83160]' ] || fail "over pace must be negative points and time"
pace '44, 1000000, 1000000' | jq -e 'all(.[]; . == null)' >/dev/null || fail "a reading whose week already reset must not pace this week"
pace 'None, 1000000 + 3600, 1000000' | jq -e 'all(.[]; . == null)' >/dev/null || fail "no utilization must be null, never 0%"
[ "$(price '[0, "claude-fable-5-1", 0, 0, 0, 1000000, 0]')" = 0.25 ] || fail "Fable 5.1 cache reads are \$0.25/MTok, not 0.1x input"
[ "$(price '[0, "claude-sonnet-5-5", 0, 0, 0, 1000000, 0]')" = 0.1 ] || fail "Sonnet 5.5 cache reads are \$0.10/MTok (\$0.20 is the Sonnet 5 rate)"
[ "$(price '[0, "claude-haiku-5-5", 0, 0, 0, 100000, 0]')" = 0.001 ] || fail "Haiku 5.5 cache reads are \$0.01/MTok up to 100K-token prompts"
[ "$(price '[0, "claude-haiku-5-5", 100000, 0, 0, 0, 1000000]')" = 0.51 ] || fail "Haiku 5.5 is \$0.10 in and \$0.50 out per MTok up to 100K-token prompts"
[ "$(price '[0, "claude-haiku-5-5", 200000, 0, 0, 0, 1000000]')" = 2.6 ] || fail "a Haiku 5.5 prompt over 100K tokens is \$0.50 in and \$2.50 out per MTok"
[ "$(price '[0, "claude-haiku-5-5", 0, 0, 0, 200000, 0]')" = 0.01 ] || fail "a Haiku 5.5 prompt over 100K tokens reads cache at \$0.05/MTok"
rprice() { python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(round(d.price($1), 9))"; }
[ "$(rprice '[0, "claude-haiku-5-5", 50000, 0, 0, 50001, 0]')" = 0.02750005 ] || fail "the tier counts input + cache read + cache write: 100,001 tokens is a long prompt"
[ "$(price '[0, "claude-haiku-5-5", 50000, 0, 0, 50000, 0]')" = 0.0055 ] || fail "exactly 100,000 tokens is still a short prompt"
[ "$(price '[0, "claude-haiku-5-5", None, 0, 0, 0, 1000000]')" = None ] || fail "a Haiku request with no prompt size is unpriced, never guessed"
# An estimated fast mode is twice its model's rate at the prompt's own tier: doubling only the short rate
# prices a long prompt at a fifth of its estimate and calls the week complete.
[ "$(price '[0, "claude-haiku-5-5:fast", 1000000, 0, 0, 0, 0]')" = 1.0 ] || fail "an estimated fast prompt over 100K tokens is twice the long-prompt rate: $(price '[0, "claude-haiku-5-5:fast", 1000000, 0, 0, 0, 0]')"
[ "$(price '[0, "claude-haiku-5-5:fast", 100000, 0, 0, 0, 0]')" = 0.02 ] || fail "an estimated fast prompt up to 100K tokens is twice the short-prompt rate"
[ "$(price '[0, "claude-haiku-5-5:fast", None, 0, 0, 0, 1000000]')" = None ] || fail "an estimated fast request with no prompt size is unpriced, never guessed"
# Rulings 10 and 11: every model and mode this machine's logs name has a price, fast mode and Codex
# included, so the weekly dollar limit counts all of it. A fast request priced at the standard rate, or left
# out, understates the spend the owner paces against.
[ "$(price '[0, "claude-opus-5-5:fast", 1000000, 0, 0, 0, 0]')" = 8.0 ] || fail "a fast-mode request prices at the published fast rate, never the standard one"
[ "$(price '[0, "claude-opus-4-8:fast", 0, 0, 0, 1000000, 1000000]')" = 51.0 ] || fail "Opus 4.8 fast is \$50 out, and its cache read is 0.1x the \$10 fast input"
[ "$(price '[0, "gpt-6.1-sol", 100000, 0, 0, 100000, 100000]')" = 1.21 ] || fail "Codex Sol is \$2 in, \$0.10 cached and \$10 out per MTok"
[ "$(price '[0, "gpt-6.1-sol:fast", 100000, 100000, 0, 0, 100000]')" = 2.9 ] || fail "Codex Sol fast is \$4 in, \$5 cache write and \$20 out per MTok"
[ "$(price '[0, "gpt-6.1-sol", 172000, 0, 0, 100000, 0]')" = 0.354 ] || fail "exactly 272K input tokens is still Codex's short context"
[ "$(rprice '[0, "gpt-6.1-sol", 172001, 0, 0, 100000, 0]')" = 0.708004 ] || fail "over 272K input tokens Codex Sol is \$4 in and \$0.20 cached per MTok"
[ "$(price '[0, "gpt-6-astra:fast", 0, 0, 0, 0, 1000000]')" = 100.0 ] || fail "Codex Astra fast is \$100 out per MTok"
# A mode with no published price is estimated from the nearest published one (twice the model's standard
# rate, the multiple both vendors publish for fast) and flagged, so a guess is never read as a list price.
est() { python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(d.price($1), d.estimated($1))"; }
[ "$(est '[0, "claude-sonnet-5-5:fast", 1000000, 0, 0, 0, 0]')" = "4.0 True" ] || fail "an unpublished fast mode is priced by its estimate and flagged as one"
[ "$(est '[0, "claude-opus-5-5:fast", 1000000, 0, 0, 0, 0]')" = "8.0 False" ] || fail "a published fast price is not an estimate"
[ "$(est '[0, "gpt-9-nova", 1000000, 0, 0, 0, 0]')" = "None False" ] || fail "a model the table has never seen has nothing to estimate from: unpriced, never \$0"
python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
r = d.request_row(json.loads(sys.argv[1])); assert r[3:5] == [700, 0], r" \
  '{"type":"assistant","requestId":"r","timestamp":"2026-10-10T00:00:00Z","message":{"model":"m","usage":{"cache_creation_input_tokens":700}}}' \
  || fail "a usage with no TTL split prices its cache write at the 5-minute rate"
# A transcript line whose prompt size is missing, null or not a number (a string) gives a row with no input count, so
# a Haiku request (priced by its prompt's tier) is unpriced, never priced as a short prompt.
python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
for v in ('missing', None, '150000'):
    u = {'output_tokens': 1000000} if v == 'missing' else {'output_tokens': 1000000, 'input_tokens': v}
    r = d.request_row({'type': 'assistant', 'requestId': 'r', 'timestamp': '2026-10-10T12:00:00Z', 'message': {'model': 'claude-haiku-5-5', 'usage': u}})
    assert d.price(r) is None, (v, r)" || fail "a Haiku request whose prompt size is missing, null or a string is unpriced, never guessed"
# A cache written before rows kept an unknown prompt size as None holds a Haiku
# row whose missing size already became 0, which would price as a short prompt.
mkdir -p "$T/req-projects" && echo '{"offsets":{},"requests":{"r":[1791633000,"claude-haiku-5-5",0,0,0,0,1000000]}}' > "$T/req-cache.json"
python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
assert d.requests('$T/req-projects', '$T/req-cache.json', 1791630000, 1791633600) == []" \
  || fail "a request cache from before unknown prompt sizes were kept must be rebuilt, not trusted"
# A count the usage lacks is unknown for every model: priced as 0 it showed a measured cost.
[ "$(price '[0, "claude-opus-5-5", None, 0, 0, 0, 1000000]')" = None ] || fail "an Opus request with no input count is unpriced, never priced as 0 tokens"
[ "$(price '[0, "claude-opus-5-5", 1000000, 0, 0, 0, None]')" = None ] || fail "a request with no output count is unpriced"
) & part prices

(
# Transcripts that cannot be read. A file deleted between the listing
# and the read is gone, not a fault: the run goes on with the rest. One that is
# there and refuses, or a folder that cannot be listed, leaves the totals
# unknown (None), never a smaller number that reads as measured.
# The Codex reading is the newest by its own time: a resumed old session
# has the newest file and an old reading.
mkdir -p "$T/unr/p/sub" "$T/unr/cx"
python3 - "${LIM%/*}" "$T/unr" <<'PY' || fail "unreadable transcripts or the Codex reading's order (see the line above)"
import builtins, json, os, sys
sys.path.insert(0, sys.argv[1])
import dashboard_limit as d
T, now = sys.argv[2], d.epoch("2026-10-10T01:00:00Z")
row = lambda rid: json.dumps({"type": "assistant", "requestId": rid, "timestamp": "2026-10-10T00:00:00Z",
    "message": {"model": "m", "usage": {"input_tokens": 1, "output_tokens": 1}}}) + "\n"
good, bad = f"{T}/p/good.jsonl", f"{T}/p/sub/bad.jsonl"
for p, rid in ((good, "g"), (bad, "b")):
    with open(p, "w") as f:
        f.write(row(rid))
run = lambda: d.requests(f"{T}/p", f"{T}/cache.json", now - 7200, now)
real = builtins.open
def gone(path, *a, **k):
    if path == bad:
        raise FileNotFoundError(path)
    return real(path, *a, **k)
d.open = gone
got = run()
del d.open
assert got is not None and len(got) == 1, f"a transcript deleted before it was opened must not stop or blank the run: {got}"
os.remove(f"{T}/cache.json")
os.chmod(bad, 0)
assert run() is None, "a transcript that is there and cannot be opened must leave the totals unknown"
os.chmod(bad, 0o644)
os.chmod(f"{T}/p/sub", 0)
got = run()
os.chmod(f"{T}/p/sub", 0o755)
assert got is None, f"a transcript folder that cannot be listed must leave the totals unknown: {got}"
assert len(run()) == 2, "once readable again both requests are counted"

def reading(at, used):
    return json.dumps({"timestamp": at, "payload": {"rate_limits": {"primary": {
        "window_minutes": 10080, "used_percent": used, "resets_at": now + 3600}}}}) + "\n"
for name, at, used, mtime in (("resumed", "2026-10-09T00:00:00Z", 11, now), ("other", "2026-10-10T00:30:00Z", 42, now - 600)):
    with open(f"{T}/cx/{name}.jsonl", "w") as f:
        f.write(reading(at, used))
    os.utime(f"{T}/cx/{name}.jsonl", (mtime, mtime))
got = d.codex(f"{T}/cx", now)
assert got["usedPct"] == 42, f"the Codex reading must be the newest by its own time, not its file's: {got}"
os.chmod(f"{T}/cx/resumed.jsonl", 0)
got = d.codex(f"{T}/cx", now)
os.chmod(f"{T}/cx/resumed.jsonl", 0o644)
assert got["usedPct"] is None, f"a Codex session that cannot be read may hold the newest reading: unknown, not the other file's: {got}"
PY
# A session run through an API proxy logs no requestId: each request counts under its message id (streamed lines of
# one message once), and a line with no message id under its own uuid, so a proxy run never reads as zero.
mkdir -p "$T/proxy/p"
python3 - "${LIM%/*}" "$T/proxy" <<'PY' || fail "a proxy session's requests are not counted (see the line above)"
import json, sys
sys.path.insert(0, sys.argv[1])
import dashboard_limit as d
T, now = sys.argv[2], d.epoch("2026-10-10T01:00:00Z")
line = lambda **k: json.dumps({"type": "assistant", "timestamp": "2026-10-10T00:00:00Z", **k}) + "\n"
use = {"input_tokens": 1, "output_tokens": 1}
with open(f"{T}/p/s.jsonl", "w") as f:
    f.write(line(uuid="u1", message={"id": "msg_a", "model": "m", "usage": use}))
    f.write(line(uuid="u2", message={"id": "msg_a", "model": "m", "usage": use}))
    f.write(line(uuid="u3", message={"model": "m", "usage": use}))
    f.write(line(uuid="u4", message={"model": "m", "usage": use}))
got = d.requests(f"{T}/p", f"{T}/cache.json", now - 7200, now)
assert got is not None and len(got) == 3, f"one message streamed over two lines and two lines with only their own ids are three requests: {got}"
# A version-7 cache skipped the lines with neither id and holds the file's offset at its end: it is read again.
import os
p = f"{T}/p/s.jsonl"
json.dump({"version": 7, "offsets": {p: os.path.getsize(p)}, "requests": {}, "cwd": {}, "session": {}, "side": {}},
          open(f"{T}/cache7.json", "w"))
got = d.requests(f"{T}/p", f"{T}/cache7.json", now - 7200, now)
assert got is not None and len(got) == 3, f"a version-7 cache's transcript is not read again, so its uuid-only lines stay zero: {got}"
PY
# Cost today: noon UTC on 2026-10-10, host clock in UTC. A request an hour ago
# ($20 of Opus 5.5 output) counts; one before midnight does not; a day whose
# midnight precedes the week start has rows never loaded, so it has no total;
# rows today with none priced have no total either, never $0.
today() { TZ=UTC python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; o = [0, 'claude-opus-5-5', 0, 0, 0, 0, 1000000]
print(json.dumps(d.cost($1, 10, now - $2, now)['today']))"; }
[ "$(today '[[now - 3600] + o[1:], [now - 13 * 3600] + o[1:], [now - 60, "x", 0, 0, 0, 0, 5]]' 86400)" = 20.0 ] || fail "today's cost sums only rows since local midnight"
[ "$(today '[[now - 3600] + o[1:]]' 7200)" = null ] || fail "a day that began before the week start has no cost today"
[ "$(today '[[now - 60, "x", 0, 0, 0, 0, 5], [now - 13 * 3600] + o[1:]]' 86400)" = null ] || fail "today's rows with none priced have no cost, never \$0"
# A machine that pays by API paces dollars against a weekly limit the owner sets, in a week that starts
# Monday 00:00 local. Saturday noon is 5.5 of 7 days gone, so a $1,400 limit's even pace is $1,100;
# $40 spent is $1,060 under, which is 1060/1400 of the week. A wrong goal here misleads the pace alert.
api() { TZ=UTC python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; o = [0, 'claude-opus-5-5', 0, 0, 0, 0, 1000000]
print(json.dumps(d.api_week($1, $2, now)))"; }
TWO='[[now - 3600] + o[1:], [now - 90000] + o[1:], [now - 6 * 86400] + o[1:]]'
[ "$(api 1400 "$TWO" | jq -c '[.limitUsd, .spentUsd, .goalUsd, .underUsd, .paceSec, .timeLeftSec, .windowStart, .resetsAt, .requests]')" = '[1400,40.0,1100.0,1060.0,457920,129600,"2026-10-05T00:00:00Z","2026-10-12T00:00:00Z",2]' ] \
  || fail "API mode with a limit: spend since Monday against the limit's even pace: $(api 1400 "$TWO")"
[ "$(api 1400 "$TWO" | jq -c '[.history[].usd]')" = '[20.0,40.0,40.0]' ] || fail "the API graph is the running spend, held to now"
[ "$(api 30 "$TWO" | jq -c '[.underUsd, .paceSec < 0]')" = '[-16.43,true]' ] || fail "spend past the even pace is negative dollars and time"
[ "$(api None "$TWO" | jq -c '[.limitUsd, .spentUsd, .goalUsd, .underUsd, .paceSec]')" = '[null,40.0,null,null,null]' ] \
  || fail "API mode with no limit: the week's spend, and no goal or pace to alert on"
[ "$(api 1400 None | jq -c '[.spentUsd, .requests, .history]')" = '[null,null,null]' ] || fail "no transcripts is spend not measured, never \$0"
[ "$(api 1400 '[[now - 60, "x", 0, 0, 0, 0, 5]]' | jq -c '[.spentUsd, .unpricedRequests]')" = '[null,1]' ] || fail "a week of only unpriced requests has no spend, never \$0"
# Ruling 10: Claude and Codex spend sum against the one weekly limit. A Codex model with no price is named
# as not counted; its dollars are missing from the total, never added as \$0 as if it were free.
apix() { TZ=UTC python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; o = [0, 'claude-opus-5-5', 0, 0, 0, 0, 1000000]; x = [0, 'gpt-6.1-sol', 0, 0, 0, 0, 200000]
print(json.dumps(d.api_week(1400, $TWO, now, $1)))"; }
[ "$(apix '[[now - 3600] + x[1:], [now - 8 * 86400] + x[1:]]' | jq -c '[.spentUsd, .claudeUsd, .codexUsd, .underUsd, .requests, .history[-1].usd]')" = '[42.0,40.0,2.0,1058.0,3,42.0]' ] \
  || fail "API mode sums Claude and Codex spend against the limit: $(apix '[[now - 3600] + x[1:]]')"
[ "$(apix '[[now - 3600] + x[1:], [now - 60, "gpt-9-nova", 1000000, 0, 0, 0, 0]]' | jq -c '[.spentUsd, .codexUsd, .unpricedRequests, .unpricedModels]')" = '[42.0,2.0,1,["gpt-9-nova"]]' ] \
  || fail "a Codex model missing from the table is named as not counted, not added as \$0"
[ "$(apix 'None' | jq -c '[.spentUsd, .claudeUsd, .codexUsd]')" = '[40.0,40.0,null]' ] || fail "with no Codex session folder its spend is not measured, never \$0"
[ "$(apix '[[now - 3600, "gpt-6.1-sol:batch", 1000000, 0, 0, 0, 0], [now - 60, "claude-sonnet-5-5:fast", 1000000, 0, 0, 0, 0]]' | jq -c '[.spentUsd, .estimatedUsd, .unpricedModels]')" = '[44.0,4.0,["gpt-6.1-sol:batch"]]' ] \
  || fail "estimated dollars are in the total and reported as estimated"
# Each provider is counted on its own: a machine with no Claude transcripts still paces its Codex dollars,
# and a provider with requests none of which price has no dollar figure, never $0.
apin() { TZ=UTC python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; x = [0, 'gpt-6.1-sol', 0, 0, 0, 0, 200000]
print(json.dumps(d.api_week(1400, None, now, $1)))"; }
[ "$(apin '[[now - 3600] + x[1:]]' | jq -c '[.spentUsd, .claudeUsd, .codexUsd, .requests, .underUsd]')" = '[2.0,null,2.0,1,1098.0]' ] \
  || fail "with no Claude transcripts the Codex spend still counts and Claude's is not measured: $(apin '[[now - 3600] + x[1:]]')"
[ "$(apin 'None' | jq -c '[.spentUsd, .requests]')" = '[null,null]' ] || fail "with neither provider read there is no spend"
[ "$(apix '[[now - 60, "gpt-9-nova", 1000000, 0, 0, 0, 0]]' | jq -c '[.spentUsd, .claudeUsd, .codexUsd]')" = '[40.0,40.0,null]' ] \
  || fail "Codex requests none of which price have no Codex dollar figure, never \$0"
# Ruling 12: the total is trusted only when it is complete (both providers read, nothing unpriced). An
# estimate is a price, so it does not make the total incomplete. A request with every count present and 0
# costs $0 whatever its model; one with a count missing stays unpriced, so zero and missing never mix.
[ "$(apix '[[now - 3600] + x[1:], [now - 60, "claude-sonnet-5-5:fast", 1000000, 0, 0, 0, 0]]' | jq -c '[.complete, .estimatedUsd]')" = '[true,4.0]' ] \
  || fail "both providers read and every request priced, an estimate included, is a complete total"
[ "$(apix '[[now - 60, "gpt-9-nova", 1000000, 0, 0, 0, 0]]' | jq -c '.complete')" = false ] || fail "an unpriced request makes the total incomplete"
[ "$(apix 'None' | jq -c '.complete')" = false ] || fail "a provider that was not read makes the total incomplete"
[ "$(TZ=UTC python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; a = d.api_week(1, None, now, [[now - 3600, 'gpt-6.1-sol', 0, 0, 0, 0, 200000]]); print(json.dumps([a['complete'], a['underUsd'] < 0]))")" = '[false, true]' ] \
  || fail "an incomplete total still paces what was measured, so over-pace still shows"
[ "$(price '[0, "<synthetic>", 0, 0, 0, 0, 0]')" = 0.0 ] || fail "a request with every token count present and 0 costs \$0 whatever its model"
[ "$(price '[0, "<synthetic>", None, 0, 0, 0, 0]')" = None ] || fail "a request with a token count missing stays unpriced, never \$0"
[ "$(price '[0, "gpt-9-nova", 0, 0, 0, 0, 1]')" = None ] || fail "one token on a model with no price is unpriced"
# In the API week a request with a count missing is left out and makes the total incomplete, on a
# known model and inside an advisor call alike: its cost is unknown, and reading it as $0 calls the week healthy.
apim() { TZ=UTC python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; a = d.api_week(1000, $1, now, []); print(json.dumps([a['spentUsd'], a['unpricedRequests'], a['complete']]))"; }
[ "$(apim '[[now - 60, "claude-opus-5-5", None, 0, 0, 0, None]]')" = '[null, 1, false]' ] || fail "a known model with counts missing is not \$0 of complete accounting: $(apim '[[now - 60, "claude-opus-5-5", None, 0, 0, 0, None]]')"
[ "$(apim '[[now - 60, "claude-opus-5-5", 0, 0, 0, 0, 1000000, [now - 60, "claude-fable-5-1", 0, 0, 0, None, 0]]]')" = '[null, 1, false]' ] || fail "an advisor call with a count missing leaves its request out"
[ "$(apim '[[now - 60, "claude-opus-5-5", 0, 0, 0, 0, 1000000]]')" = '[20.0, 0, true]' ] || fail "a request with every count present is priced and complete"
cwp() { python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(d.cache_write_pct($1, 1000))"; }
[ "$(cwp '[[990, "claude-opus-5-5", 0, 0, 0, 100, 0, [990, "claude-fable-5-1", 0, 100, 0, 0, 0]]]')" = 50.0 ] \
  || fail "cache_write_pct_counts_advisor_calls: an advisor's cache write is part of the day's input"
) & part transcripts

(
# Codex logs one usage record per response; the model and the speed tier are logged apart from it, once
# near the head of the session. A reader that resumes at its saved offset must still know both, or every
# later response loses its price. The input count includes the cached tokens: charging both doubles them.
CXS=$T/cx-sessions/2026/10/10; mkdir -p "$CXS"
cxrec() { printf '{"timestamp":"2026-10-10T11:%s:00Z","type":"token_usage_record","payload":{"response_id":"%s","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":100,"output_tokens":50}}}\n' "$1" "$2"; }
{ echo '{"timestamp":"2026-10-10T11:00:00Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.1-sol","service_tier":"priority"}}}'
  echo '{"timestamp":"2026-10-10T11:00:01Z","type":"turn_context","payload":{"model":"gpt-6.1-sol"}}'
  cxrec 01 resp_a; cxrec 02 resp_a; } > "$CXS/rollout-a.jsonl"
{ echo '{"timestamp":"2026-10-10T11:00:01Z","type":"turn_context","payload":{"model":"gpt-6-astra"}}'; cxrec 03 resp_b; } > "$CXS/rollout-b.jsonl"
cxreq() { python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600 + ${1:-0}; print(json.dumps(sorted(r[1:] for r in d.codex_requests(['$T/cx-sessions'], '$T/cx-cache.json', now - 86400, now))))"; }
rm -f "$T/cx-cache.json"
[ "$(cxreq)" = '[["gpt-6-astra:tier-unknown", 500, 100, 0, 400, 50], ["gpt-6.1-sol:fast", 500, 100, 0, 400, 50]]' ] \
  || fail "one row per Codex response, under its session's model and tier, cached tokens taken out of the input: $(cxreq)"
cxrec 04 resp_c >> "$CXS/rollout-a.jsonl"
# A later run is a later cycle: the same stamp would be answered from the cycle's own cache.
[ "$(cxreq 60 | jq -c 'map(.[0])')" = '["gpt-6-astra:tier-unknown","gpt-6.1-sol:fast","gpt-6.1-sol:fast"]' ] || fail "a response read on a later run keeps its session's model and fast tier: $(cxreq 60)"
[ "$(python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(d.codex_requests(['$T/no-such-sessions'], '$T/cx-cache.json', 0, 1))")" = None ] \
  || fail "no Codex session folder is not measured, never an empty week"
# A codex-tui session logs no tier, so its response reads tier-unknown (priced at standard and counted as
# estimated). Fixture: rollout-b is untiered.
CX2=$T/cx-s2/2026/10/10; mkdir -p "$CX2"; cp "$CXS/rollout-b.jsonl" "$CX2/rollout-b.jsonl"
cx2() { # -> [[model, estimated, price]] for rollout-b's one response
  rm -f "$T/cx-cache2.json"
  python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; rows = d.codex_requests(['$T/cx-s2'], '$T/cx-cache2.json', now - 86400, now)
print(json.dumps([[r[1], d.estimated(r), round(d.price(r), 6)] for r in rows]))"; }
[ "$(cx2)" = '[["gpt-6-astra:tier-unknown", true, 0.00915]]' ] \
  || fail "a session with no tier reads gpt-6-astra:tier-unknown, priced at standard and estimated: $(cx2)"
# The judge's input: a version-5 cache holds that response under the old silent-standard rule, its file offset at the end of the log
# (so it would never be read again). It is dropped and the log read once more, and the cache is saved as version 6.
python3 -c "import sys, os, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
p = '$CX2/rollout-b.jsonl'; ts = d.epoch('2026-10-10T11:03:00Z')
json.dump({'version': 5, 'files': {p: [os.path.getsize(p), 'gpt-6-astra', None, None]}, 'requests': {'resp_b': [ts, 'gpt-6-astra', 500, 100, 0, 400, 50]},
           'cwd': {'resp_b': None}, 'session': {'resp_b': 'rollout-b'}, 'unread': [], 'complete': True, 'covered': [0, 1791633600]}, open('$T/cx-cache2.json', 'w'))"
[ "$(python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; rows = d.codex_requests(['$T/cx-s2'], '$T/cx-cache2.json', now - 86400, now)
print(json.dumps([[r[1], d.estimated(r)] for r in rows] + [json.load(open('$T/cx-cache2.json'))['version']]))")" = '[["gpt-6-astra:tier-unknown", true], 6]' ] \
  || fail "a version-5 cache's untiered response is re-read as estimated, and the cache is rewritten as version 6"
# The log's own tier still wins from its line on: default, then priority prices each part at its own tier.
CX3=$T/cx-s3/2026/10/10; mkdir -p "$CX3"
{ echo '{"timestamp":"2026-10-10T11:00:00Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.1-sol","service_tier":"default"}}}'
  cxrec 10 resp_m1
  echo '{"timestamp":"2026-10-10T11:11:00Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.1-sol","service_tier":"priority"}}}'
  cxrec 12 resp_m2; } > "$CX3/rollout-m.jsonl"
[ "$(python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; print(json.dumps([r[1] for r in d.codex_requests(['$T/cx-s3'], '$T/cx-cache3.json', now - 86400, now)]))")" = '["gpt-6.1-sol", "gpt-6.1-sol:fast"]' ] \
  || fail "a mid-session thread_settings_applied switch prices each part at its own tier"
[ "$(python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
r = {'timestamp': '2026-10-10T11:00:00Z', 'payload': {'response_id': 'x', 'usage': {'input_tokens': 1}}}
print([d.codex_row(r, 'gpt-6.1-sol', t)[1] for t in ('fast', 'priority', 'standard', 'default', None)])")" \
  = "['gpt-6.1-sol:fast', 'gpt-6.1-sol:fast', 'gpt-6.1-sol', 'gpt-6.1-sol', 'gpt-6.1-sol:tier-unknown']" ] \
  || fail "service_tier fast and priority read as :fast, standard and default as the standard rate, none as unknown: the one mapping in codex_row"
# A session file or folder that cannot be opened may hold spend nobody counted: the week keeps what was read
# and is not complete. A file gone between the listing and the open (a dangling link here) spent nothing unseen.
# Each call is its own cycle: the collector's second read of one cycle is answered from the first's cache.
cxweek() { echo $(( $(cat "$T/cx-tick" 2>/dev/null || echo 1000) + 60 )) > "$T/cx-tick"
  TZ=UTC python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600 + $(cat "$T/cx-tick"); m = []; rows = d.codex_requests(['$T/cx-sessions'] + ${CXEXTRA:-[]}, '$T/cx-cache.json', now - 86400, now, m)
a = d.api_week(1000, [], now, rows, bool(m)); print(json.dumps([len(rows), a['complete'], a['spentUsd'] > 0]))"; }
[ "$(cxweek)" = '[3, true, true]' ] || fail "every Codex session read is a complete week: $(cxweek)"
ln -s "$CXS/gone.jsonl" "$CXS/rollout-gone.jsonl"
[ "$(cxweek)" = '[3, true, true]' ] || fail "a session file deleted before it is opened is not a failed read: $(cxweek)"
rm "$CXS/rollout-gone.jsonl"; cxrec 05 resp_d > "$CXS/rollout-locked.jsonl"; chmod 000 "$CXS/rollout-locked.jsonl"
[ "$(cxweek)" = '[3, false, true]' ] || fail "a Codex session file that cannot be opened leaves the week incomplete with its measured dollars kept: $(cxweek)"
rm -f "$CXS/rollout-locked.jsonl"; mkdir "$T/cx-sessions/2026/10/11"; chmod 000 "$T/cx-sessions/2026/10/11"
[ "$(cxweek)" = '[3, false, true]' ] || fail "a Codex session folder that cannot be opened leaves the week incomplete: $(cxweek)"
chmod 700 "$T/cx-sessions/2026/10/11"; rmdir "$T/cx-sessions/2026/10/11"
# A second (review) folder that is absent spent nothing; one whose parent cannot be searched may hold spend.
CXEXTRA="['$T/cx-review/sessions']"
[ "$(cxweek)" = '[3, true, true]' ] || fail "an absent review folder is not a failed read: $(cxweek)"
mkdir -p "$T/cx-review/sessions"; chmod 000 "$T/cx-review"
[ "$(cxweek)" = '[3, false, true]' ] || fail "a review folder whose parent cannot be searched leaves the week incomplete: $(cxweek)"
chmod 700 "$T/cx-review"; rm -rf "$T/cx-review"; unset CXEXTRA
# A usage line the reader cannot use (no usable counts, or not even JSON) is spend of unknown size. It is kept as
# an unpriced request, and stays kept on the next run, when the reader has already moved past the line.
{ echo '{"timestamp":"2026-10-10T11:06:00Z","type":"token_usage_record","payload":{"response_id":"resp_e","usage":"lots"}}'
  echo '{"type":"token_usage_record","payload":{"respon'; } > "$CXS/rollout-bad.jsonl"
[ "$(cxweek)" = '[5, false, true]' ] || fail "a Codex usage line that cannot be used is kept as an unpriced request, never dropped: $(cxweek)"
[ "$(cxweek)" = '[5, false, true]' ] || fail "an unusable Codex usage line is still known on the next run: $(cxweek)"
# A cache saved by the reader that dropped such lines is already past them: it is rebuilt, never trusted.
[ "$(python3 -c "import sys, os, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
p = '$CXS/rollout-bad.jsonl'; json.dump({'version': 1, 'files': {p: [os.path.getsize(p), None, None]}, 'requests': {}}, open('$T/cx-old.json', 'w'))
now = 1791633600; print(sum(r[1] == 'unreadable Codex record' for r in d.codex_requests(['$T/cx-sessions'], '$T/cx-old.json', now - 86400, now)))")" = 2 ] \
  || fail "a Codex cache from the reader that dropped unusable lines is rebuilt, so those lines are found"
# A Claude transcript that cannot be opened gives no Claude reading at all. The API week then says
# Claude was not read: incomplete, with the Codex dollars it did measure kept.
mkdir -p "$T/cl-locked/p"; echo '{}' > "$T/cl-locked/p/a.jsonl"; chmod 000 "$T/cl-locked/p/a.jsonl"
[ "$(python3 -c "import sys, json, time; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = int(time.time()); rows = d.requests('$T/cl-locked', '$T/cl-locked.json', now - 86400, now)
a = d.api_week(1000, rows, now, [[now, 'gpt-6.1-sol', 0, 0, 0, 0, 200000]]); print(json.dumps([rows, a['claudeUsd'], a['codexUsd'], a['spentUsd'], a['complete']]))")" = '[null, null, 2.0, 2.0, false]' ] \
  || fail "an unreadable Claude transcript reads as Claude not read: incomplete, Codex dollars kept"
chmod 600 "$T/cl-locked/p/a.jsonl"
[ "$(cxreq 120 | jq -c 'map(.[0]) | unique')" = '["gpt-6-astra:tier-unknown","gpt-6.1-sol:fast","unreadable Codex record"]' ] || fail "an unusable usage line is named for what it is: $(cxreq 120)"
bill() { mkdir -p "$T/bill/cache"; rm -f "$T/bill/billing.json"; [ -z "$1" ] || echo "$1" > "$T/bill/billing.json"
  python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(json.dumps(d.billing('$T/bill/cache')))"; }
[ "$(bill '')" = '["subscription", null]' ] || fail "with no billing setting the panel is the subscription one"
[ "$(bill '{"billing":"api","weeklyLimitUsd":1000}')" = '["api", 1000]' ] || fail "billing.json beside the cache folder switches to API mode with its weekly limit"
[ "$(bill '{"billing":"api","weeklyLimitUsd":"lots"}')" = '["api", null]' ] || fail "a limit that is not a positive number is no limit"
[ "$(bill '{"billing":"apis","weeklyLimitUsd":5}')" = '["subscription", null]' ] || fail "an unknown billing value stays subscription"
# O66: Codex readings are kept over time like Claude's, one row per reading, so the graph can draw a Codex line.
chist() { python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
now = 1791633600; print(json.dumps(d.codex_history('$T/bill/cache', $1, now)))"; }
CXR='{"usedPct": %s, "windowStart": d.iso(now - 86400), "readAt": d.iso(now - %s)}'
rm -f "$T/bill/cache/codex-limit-history.jsonl"
[ "$(chist "$(printf "$CXR" 12 600)" | jq -c 'map(.pct)')" = '[12]' ] || fail "a Codex reading is stored as a sample"
[ "$(chist "$(printf "$CXR" 12 600)" | jq -c 'map(.pct)')" = '[12]' ] || fail "the same Codex reading is never stored twice"
[ "$(chist "$(printf "$CXR" 15 60)" | jq -c 'map(.pct)')" = '[12,15]' ] || fail "a newer Codex reading adds a sample"
[ "$(chist '{"usedPct": None, "windowStart": None, "readAt": None}')" = null ] || fail "with no live Codex reading its history is not measured, never an empty healthy line"
) & part codex

(
# fetch() names its cause on stderr; urlopen is replaced, so no call leaves the box.
fetch_run() { python3 -c "import sys, urllib.error; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
d.token = lambda folder: $1
def urlopen(req, timeout=None):
    $2
d.urllib.request.urlopen = urlopen
sys.exit(d.fetch())" 2>&1 >/dev/null | tail -n 1; }
H429='from email.message import Message
    m = Message(); m["Retry-After"] = "900"
    raise urllib.error.HTTPError("u", 429, "x", m, None)'
[ "$(fetch_run "'t'" "$H429")" = 'rate limited (429); retry after 900 s' ] || fail "429 with Retry-After must say so: $(fetch_run "'t'" "$H429")"
[ "$(fetch_run "'t'" 'raise urllib.error.HTTPError("u", 429, "x", {}, None)')" = 'rate limited (429)' ] || fail "429 alone must say rate limited (429)"
# Retry-After may be an HTTP-date; dropping it re-reads after 300 s while the server said 900.
HDATE='import email.utils, time
    from email.message import Message
    m = Message(); m["Retry-After"] = email.utils.formatdate(time.time() + 900, usegmt=True)
    raise urllib.error.HTTPError("u", 429, "x", m, None)'
# fetch() exits nonzero on a 429 by design; under pipefail that must not end the file here.
w=$(fetch_run "'t'" "$HDATE" | sed -n 's/^rate limited (429); retry after \([0-9]*\) s$/\1/p') || true
[ -n "$w" ] && [ "$w" -ge 898 ] && [ "$w" -le 900 ] || fail "a 429 with an HTTP-date Retry-After 900 s ahead must say retry after ~900 s: $(fetch_run "'t'" "$HDATE")"
[ "$(fetch_run "'t'" 'from email.message import Message
    m = Message(); m["Retry-After"] = "soon"
    raise urllib.error.HTTPError("u", 429, "x", m, None)')" = 'rate limited (429)' ] || fail "an unparseable Retry-After keeps the plain rate limited (429)"
[ "$(fetch_run "'t'" 'raise TimeoutError()')" = 'timeout' ] || fail "a timeout must say timeout"
[ "$(fetch_run "'t'" 'raise urllib.error.HTTPError("u", 500, "x", {}, None)')" = 'HTTP 500' ] || fail "an HTTP error must name its code"
[ "$(fetch_run "'t'" 'raise urllib.error.URLError(TimeoutError())')" = 'timeout' ] || fail "a connect timeout wrapped in URLError must say timeout"
[ "$(fetch_run "'t'" 'raise urllib.error.URLError("down")')" = 'network error' ] || fail "an unreachable host must say network error"
[ "$(fetch_run None 'raise AssertionError')" = 'no login token' ] || fail "no token must say no login token"
for c in "'t'|raise TimeoutError()" "None|raise AssertionError"; do
  python3 -c "import sys; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
d.token = lambda folder: ${c%%|*}
def urlopen(req, timeout=None):
    ${c#*|}
d.urllib.request.urlopen = urlopen
sys.exit(0 if d.fetch() == 1 else 7)" 2>/dev/null || fail "a failed fetch must return 1 ($c)"
done
) & part fetch

# A week's reset 3 days on: the readings of the next two parts.
reset_iso=$(date -u -d '+3 days' +%Y-%m-%dT%H:%M:%S+00:00)
(
RUN_END=$T/run-end-sec.limit
LOUT=$T/out-limit LHOME=$T/home-limit
mkdir -p "$LHOME"
run HOME="$LHOME" CONVEYOR_DASHBOARD_DIR="$LOUT"; D=$LOUT/data.js
# No Claude login and nothing cached: the panel is not measured, never a 0 week.
q '[.limit | .usedPct, .goalPct, .underPts, .paceSec, .timeLeftSec, .requests, .cost, .fiveHour] | all(. == null)' "no usage reading must leave every limit figure null"
q '.limit.reading == "not-measured" and (.limitError | startswith("the usage limit was not read: no login token"))' "a missing login must be named, not 'read failed'"
[ ! -s "$LOUT/cache/limit-history.jsonl" ] || fail "no usage reading must record no sample"
mkdir -p "$LOUT/cache" "$LHOME/.claude/projects/p/s1/subagents"
five_iso=$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%S+00:00)
printf '{"five_hour":{"utilization":15.0,"resets_at":"%s"},"seven_day":{"utilization":44.0,"resets_at":"%s"}}' "$five_iso" "$reset_iso" > "$LOUT/cache/claude-usage"
touch -d '-3 minutes' "$LOUT/cache/claude-usage"  # inside the 5-minute TTL, so the copy is reused, not re-fetched
in_week=$(date -u -d '-1 hours' +%Y-%m-%dT%H:%M:%S.000Z) old=$(date -u -d '-5 days' +%Y-%m-%dT%H:%M:%S.000Z)
ONE_OUT='{"output_tokens":1}'
line() { printf '{"type":"assistant","requestId":"%s","timestamp":"%s","message":{"model":"%s","usage":%s}}\n' "$1" "$2" "${3:-claude-opus-5-5}" "${4:-$ONE_OUT}"; }
# req_a streams twice; its last line carries the final usage, which prices at
# Opus 5.5 list ($4 in, $5 5-min write, $8 1-hour write, $0.20 read, $20 out per MTok) to $0.2388.
A_USAGE='{"input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":2000,"ephemeral_1h_input_tokens":3000},"cache_read_input_tokens":4000,"output_tokens":10000}'
# Haiku's tier needs the prompt size, so req_b reports every prompt count.
B_USAGE='{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}'
{ line req_a "$in_week"; line req_a "$in_week" claude-opus-5-5 "$A_USAGE"; line req_b "$in_week" claude-haiku-5-5 "$B_USAGE"; line req_old "$old"
  printf '{"type":"user","requestId":"req_u","timestamp":"%s","message":{"usage":{}}}\n' "$in_week"; } > "$LHOME/.claude/projects/p/s1.jsonl"
line req_sub "$in_week" claude-sonnet-5-5 '{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1000}' > "$LHOME/.claude/projects/p/s1/subagents/agent-1.jsonl"
printf '{"type":"assistant","requestId":"req_half"' >> "$LHOME/.claude/projects/p/s1/subagents/agent-1.jsonl"
lrun() { run HOME="$LHOME" CONVEYOR_DASHBOARD_DIR="$LOUT"; D=$LOUT/data.js; }
lrun
q '.limit.reading == "fresh" and .limitError == null and .limit.usedPct == 44 and .limit.fiveHour.usedPct == 15' "a fresh cached reading feeds the panel"
q '.limit.goalPct > 57.1 and .limit.goalPct < 57.2 and .limit.timeLeftSec > 259100 and .limit.timeLeftSec <= 259200' "4 of 7 days gone is a 57.1% goal with 3 days left"
q '.limit.requests == 3' "a request streamed over two lines counts once; a subagent's counts; last week's, a user line and a half-written line do not"
hist '[.[].pct] == [44]' "the first reading starts the recorded series"
# $0.2388 for req_a plus $0.01 for the subagent's 1000 Sonnet 5.5 output tokens plus
# $0.0000005 for req_b's one Haiku 5.5 output token.
q '.limit.cost | (.week - 0.2488005 | fabs) < 1e-9 and .unpricedRequests == 0 and has("today")' "the week's cost is the list price of each request's final usage"
q '.limit.cost | (.projected - 0.2488005 / 44 * 100 | fabs) < 1e-9 and (.perPoint - 0.2488005 / 44 | fabs) < 1e-9 and (.perHour - 0.2488005 / 44 * 100 / 168 | fabs) < 1e-9' "44% used for \$0.2488 projects to \$0.5655 at 100%, which over the 168 h week is \$0.0034/hr"
lrun
hist 'length == 1' "re-reading the same cached copy must not record a second sample"
q '.limit.requests == 3' "a second scan re-reads nothing it already counted"
printf ',"timestamp":"%s","message":{"usage":{}}}\n' "$in_week" >> "$LHOME/.claude/projects/p/s1/subagents/agent-1.jsonl"
touch -d '-1 minute' "$LOUT/cache/claude-usage"
lrun
q '.limit.requests == 4' "a line finished after the last scan counts once complete"
q '.limit.cost.unpricedRequests == 1 and (.limit.cost.week - 0.2488005 | fabs) < 1e-9' "a request with no model is unpriced, never priced at a guess"
hist 'length == 2' "a newer reading appends to the series"
printf '{"seven_day":{"utilization":90.0,"resets_at":"%s"}}' "$(date -u -d '-1 hours' +%Y-%m-%dT%H:%M:%S+00:00)" > "$LOUT/cache/claude-usage"
lrun
q '.limit.usedPct == null and .limit.windowStart == null and .limit.requests == null' "a reading from a week that already reset must not show as this week"
) & part limit

(
RUN_END=$T/run-end-sec.account
# --- the 7-day figure follows the Orca account in use: the config folder whose .claude.json was written last,
# among the Orca profile homes and the default (~/.claude, metadata $HOME/.claude.json). The `security` stub records the
# keychain item asked for and has no login to give, so no run reaches the network.
AOUT=$T/out-acct AHOME=$T/home-acct PROF=$T/profiles HA=$T/profiles/a/home HB=$T/profiles/b/home
mkdir -p "$HA" "$HB" "$AHOME" "$AOUT/cache"
printf '{"oauthAccount":{"emailAddress":"noreply-a@example.com"}}' > "$HA/.claude.json"
printf '{"oauthAccount":{"emailAddress":"noreply-b@example.com"}}' > "$HB/.claude.json"
touch -d '-2 hours' "$HA/.claude.json"; touch -d '-1 hours' "$HB/.claude.json"
stub security 'printf "%s\n" "$*" >> "'"$T"'/security-calls"; exit 44'
folder_hash() { python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$1"; }
arun() { run HOME="$AHOME" CONVEYOR_DASHBOARD_DIR="$AOUT" CONVEYOR_CLAUDE_PROFILES="$PROF" CONVEYOR_HOST_OS=Darwin; D=$AOUT/data.js; }
asked() { grep -qx -- "find-generic-password -s $1 -w" "$T/security-calls"; }
: > "$T/security-calls"; arun
asked "Claude Code-credentials-$(folder_hash "$HB")" || fail "limit_follows_active_profile: the fetch must ask for the newest profile's item: $(cat "$T/security-calls")"
# B's reading is cached with its retry deadline still running; A is written last. The collect drops both and fetches A's.
acct_usage() { printf '{"seven_day":{"utilization":33.0,"resets_at":"%s"},"account":{"folder":"%s","email":"%s"}}' "$reset_iso" "$1" "$2" > "$AOUT/cache/claude-usage"; touch -d '-3 minutes' "$AOUT/cache/claude-usage"; }
acct_usage "$HB" noreply-b@example.com
echo '2000000000 rate limited (429)' > "$AOUT/cache/claude-usage.retry"
touch "$HA/.claude.json"; : > "$T/security-calls"; arun
asked "Claude Code-credentials-$(folder_hash "$HA")" || fail "limit_follows_active_profile: after a switch the fetch must ask for A's item, not wait out B's retry deadline: $(cat "$T/security-calls")"
q '.limit.usedPct == null and .limit.account == null' "limit_follows_active_profile: B's cached reading must not be shown as A's"
# The same account keeps its cached reading and fetches nothing.
acct_usage "$HA" noreply-a@example.com; : > "$T/security-calls"; arun
[ ! -s "$T/security-calls" ] || fail "limit_same_account_keeps_its_reading: a fresh reading of the active account was fetched again: $(cat "$T/security-calls")"
q '.limit.usedPct == 33 and .limit.account == {folder: "'"$HA"'", email: "noreply-a@example.com"}' "limit_same_account_keeps_its_reading: the card names the account the reading was made for"
# F05: the default folder's metadata is $HOME/.claude.json (there is no ~/.claude/.claude.json); newer than every profile's, it wins,
# and its credentials are the unsuffixed item.
printf '{"oauthAccount":{"emailAddress":"noreply-d@example.com"}}' > "$AHOME/.claude.json"
rm -f "$AOUT/cache/claude-usage" "$AOUT/cache/claude-usage.retry"; : > "$T/security-calls"; arun
asked "Claude Code-credentials" || fail "limit_switch_back_to_default: the default folder's item is the unsuffixed one: $(cat "$T/security-calls")"
acct=$(HOME="$AHOME" CONVEYOR_CLAUDE_PROFILES="$PROF" python3 "$LIM" account)
[ "$(jq -c . <<<"$acct")" = "{\"folder\":\"$AHOME/.claude\",\"email\":\"noreply-d@example.com\"}" ] || fail "limit_switch_back_to_default: account says $acct"
# fetch() puts the account it read for into the reading it prints.
got=$(HOME="$AHOME" CONVEYOR_CLAUDE_PROFILES="$PROF" python3 -c "import sys, io; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
class R(io.BytesIO):
    __enter__ = lambda s: s
    __exit__ = lambda s, *a: None
d.token = lambda folder: 't'
d.urllib.request.urlopen = lambda req, timeout=None: R(b'{\"seven_day\": {\"utilization\": 1}}')
sys.exit(d.fetch())")
[ "$(jq -c '.account' <<<"$got")" = "{\"folder\":\"$AHOME/.claude\",\"email\":\"noreply-d@example.com\"}" ] || fail "fetch_names_its_account: $got"
# An account switch while the request is out must not label A's reading as B's: B's cache and history would hold A's usage.
got=$(python3 -c "import sys, io; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
class R(io.BytesIO):
    __enter__ = lambda s: s
    __exit__ = lambda s, *a: None
now = {'folder': '/a', 'email': 'noreply-a@example.com'}
d.active_folder = lambda: dict(now)
asked = []
d.token = lambda folder: asked.append(folder) or 't'
def urlopen(req, timeout=None):
    now.update(folder='/b', email='noreply-b@example.com')
    return R(b'{\"seven_day\": {\"utilization\": 33}}')
d.urllib.request.urlopen = urlopen
d.fetch()
print(asked, file=sys.stderr)" 2>"$T/fetch-asked")
[ "$(jq -c '.account' <<<"$got")" = '{"folder":"/a","email":"noreply-a@example.com"}' ] && [ "$(cat "$T/fetch-asked")" = "['/a']" ] \
  || fail "fetch_keeps_account_through_switch: the reading or the token is not A's: $got $(cat "$T/fetch-asked")"
# History keeps one account's rows apart from another's; a row from before the folder was recorded is shown for none.
HC=$T/hist-cache; mkdir -p "$HC"; hnow=$(date +%s)
hrow() { jq -nc --argjson t "$1" --argjson p "$2" --arg f "$3" '{at: ($t | todate), pct: $p} + (if $f == "" then {} else {folder: $f} end)'; }
{ hrow $((hnow - 10800)) 20 "$HB"; hrow $((hnow - 7200)) 10 "$HA"; hrow $((hnow - 3600)) 5 ""; } > "$HC/limit-history.jsonl"
hbuild() {
  printf '{"seven_day":{"utilization":%s,"resets_at":"%s"},"account":{"folder":"%s","email":"noreply-x@example.com"}}' "$2" "$reset_iso" "$1" > "$HC/usage"
  touch -d '-3 minutes' "$HC/usage"
  python3 "$LIM" build fresh "$HC/usage" "$hnow" "$HC" "$T/no-projects" | jq -c '[.history[].pct]'
}
[ "$(hbuild "$HB" 22)" = '[20,22]' ] || fail "limit_history_follows_folder: B's chart is B's rows only: $(hbuild "$HB" 22)"
[ "$(hbuild "$HA" 12)" = '[10,12]' ] || fail "limit_history_follows_folder: A's chart is A's rows only"
[ "$(jq -sc 'map(.pct) | sort' "$HC/limit-history.jsonl")" = '[5,10,12,20,22]' ] || fail "limit_history_follows_folder: another account's rows must survive a write: $(cat "$HC/limit-history.jsonl")"
rm -f "$BIN/security"
) & part account

(
# --- a machine with no Orca (tmux, a plain terminal) gets its reading with no warning. Extra profile folders
# come only from CONVEYOR_CLAUDE_PROFILES, after CLAUDE_CONFIG_DIR and ~/.claude; without it ~/.claude is read alone.
NHOME=$T/home-no-orca; mkdir -p "$NHOME/.claude"
printf '{"claudeAiOauth":{"accessToken":"tok-n"}}' > "$NHOME/.claude/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"noreply-n@example.com"}}' > "$NHOME/.claude.json"
nlim() { env -u CONVEYOR_CLAUDE_PROFILES -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$NHOME" CONVEYOR_HOST_OS=Linux "$@"; }
got=$(nlim python3 "$LIM" account 2>"$T/no-orca.err")
[ "$(jq -c . <<<"$got")" = "{\"folder\":\"$NHOME/.claude\",\"email\":\"noreply-n@example.com\"}" ] || fail "no_orca_account: $got"
[ ! -s "$T/no-orca.err" ] || fail "no_orca_account: a home with no Orca folders warned: $(cat "$T/no-orca.err")"
got=$(nlim python3 -c "import sys, io; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
class R(io.BytesIO):
    __enter__ = lambda s: s
    __exit__ = lambda s, *a: None
def u(req, timeout=None):
    assert req.headers['Authorization'] == 'Bearer tok-n', req.headers
    return R(b'{\"seven_day\": {\"utilization\": 7}}')
d.urllib.request.urlopen = u
sys.exit(d.fetch())" 2>"$T/no-orca.err") || fail "no_orca_fetch: the reading failed: $(cat "$T/no-orca.err")"
[ "$(jq -c '[.seven_day.utilization, .account.folder]' <<<"$got")" = "[7,\"$NHOME/.claude\"]" ] || fail "no_orca_fetch: $got"
[ ! -s "$T/no-orca.err" ] || fail "no_orca_fetch: a home with no Orca folders warned: $(cat "$T/no-orca.err")"
# CLAUDE_CONFIG_DIR leads the list, ~/.claude follows, each folder once.
CDIR=$T/config-dir; mkdir -p "$CDIR"
got=$(nlim CLAUDE_CONFIG_DIR="$CDIR" python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(json.dumps(d.config_folders()))")
[ "$got" = "[[\"$CDIR\", \"$CDIR/.claude.json\"], [\"$NHOME/.claude\", \"$NHOME/.claude.json\"]]" ] || fail "config_dir_first: $got"
got=$(nlim CLAUDE_CONFIG_DIR="$NHOME/.claude" python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(json.dumps(d.config_folders()))")
[ "$got" = "[[\"$NHOME/.claude\", \"$NHOME/.claude.json\"]]" ] || fail "config_dir_is_default_once: $got"
# With CONVEYOR_CLAUDE_PROFILES unset, Orca's profile folders are not read even when they exist.
# Bug caught: the default roots still globbed ~/.config/orca/claude-profiles and the Mac userData folder.
for r in "$NHOME/.config/orca/claude-profiles/p1/home" "$NHOME/Library/Application Support/orca/claude-profiles/p2/home"; do mkdir -p "$r"; done
got=$(nlim python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d; print(json.dumps(d.config_folders()))")
[ "$got" = "[[\"$NHOME/.claude\", \"$NHOME/.claude.json\"]]" ] || fail "no_orca_profile_roots: $got"
# --- every account, each with its own figures: the default login and the host file's two accounts (the second
# signed in at its own folder), never one reading for all. Bug caught: the panel showed only the folder written last.
AHOME2=$T/home-accounts; X1=$T/acct-one; X2=$T/acct-two; mkdir -p "$AHOME2/.claude" "$AHOME2/.config/conveyor" "$X1" "$X2"
for f in "$AHOME2/.claude:tok-d:noreply-d@example.com" "$X1:tok-1:noreply-1@example.com" "$X2:tok-2:noreply-2@example.com"; do
  IFS=: read -r dir tok who <<<"$f"; printf '{"claudeAiOauth":{"accessToken":"%s"}}' "$tok" > "$dir/.credentials.json"
  meta=$dir/.claude.json; [ "$dir" != "$AHOME2/.claude" ] || meta=$AHOME2/.claude.json
  jq -cn --arg e "$who" '{oauthAccount: {emailAddress: $e}}' > "$meta"
done
# The default folder, which the host file also lists (by ~/), is listed once, under the host file's name.
# Two projects: the host file's own (the first record), whose state folder is the stateDir, and another, whose state
# folder is its checkout's conveyor/state.
# A third is grouped under the second: the group's one Foreman is marked in its first-named project's folder.
PA=$T/proj-a; PB=$T/proj-b; PC=$T/proj-c; SA=$T/state-a
jq -cn --arg a "$X1" --arg b "$X2" --arg pa "$PA" --arg pb "$PB" --arg pc "$PC" --arg sa "$SA" '{stateDir: $sa,
  records: [{repo: "a", main: $pa}, {repo: "c", main: $pc}, {repo: "b", main: $pb}], foreman: {groups: [["b", "c"]]},
  accounts: [{name: "one", configDir: $a}, {name: "two", configDir: $b}, {name: "dup", configDir: "~/.claude"}]}' > "$AHOME2/.config/conveyor/host.json"
# Each project's Foreman is marked in its own state folder (conveyor/foreman/lib.sh MARK): the first project's ran on
# the first account and the other's on the default login, where their transcripts are, though the second account's
# metadata is newer. A mark anywhere else is no project's: the machine-wide folder, and the first project's
# conveyor/state, which the stateDir replaces, and the one the grouped project kept from before it was grouped; their
# session's transcript is in the second account.
mkdir -p "$SA/foreman" "$PB/conveyor/state/foreman" "$PA/conveyor/state/foreman" "$PC/conveyor/state/foreman" "$AHOME2/.local/state/conveyor/foreman" \
  "$X1/projects/-srv-main" "$X2/projects/-srv-main" "$AHOME2/.claude/projects/-srv-main"
echo "fore-1 2026-11-12T00:00:00Z" > "$SA/foreman/session"; : > "$X1/projects/-srv-main/fore-1.jsonl"
echo "fore-2 2026-11-12T00:00:00Z" > "$PB/conveyor/state/foreman/session"; : > "$AHOME2/.claude/projects/-srv-main/fore-2.jsonl"
echo "fore-x 2026-11-12T00:00:00Z" | tee "$PA/conveyor/state/foreman/session" "$PC/conveyor/state/foreman/session" > "$AHOME2/.local/state/conveyor/foreman/session"; : > "$X2/projects/-srv-main/fore-x.jsonl"
accts() { env -u CONVEYOR_CLAUDE_PROFILES -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME HOME="$AHOME2" CONVEYOR_HOST_OS=Linux python3 -c "import sys, io, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
class R(io.BytesIO):
    __enter__ = lambda s: s
    __exit__ = lambda s, *a: None
def u(req, timeout=None):
    open('$T/accounts-asked', 'a').write(req.headers['Authorization'] + '\n')
    pct = {'Bearer tok-d': 12, 'Bearer tok-1': 34, 'Bearer tok-2': 97}[req.headers['Authorization']]
    return R(json.dumps({'seven_day': {'utilization': pct, 'resets_at': '2026-11-15T00:00:00+00:00'}, 'five_hour': {'utilization': pct // 2}}).encode())
d.urllib.request.urlopen = u
sys.exit(d.main(['x', 'accounts', '$T/accounts-cache']))"; }
touch -t 203001010000 "$X2/.claude.json"
: > "$T/accounts-asked"; got=$(accts) || fail "accounts: the read failed"
[ "$(jq -c 'map([.name, .usedPct, .fiveHourPct, .email, .error])' <<<"$got")" \
  = '[["dup",12,6,"noreply-d@example.com",null],["one",34,17,"noreply-1@example.com",null],["two",97,48,"noreply-2@example.com",null]]' ] \
  || fail "accounts: each account is not listed once with its own figures: $got"
# Each row says which host file names the engine runs on its folder: the Board matches a record's account on these,
# never on the display name, which an unlisted folder may share.
[ "$(jq -c 'map(.listedAs)' <<<"$got")" = '[["dup"],["one"],["two"]]' ] || fail "accounts: a row does not carry the host file names of its folder: $got"
# The host file's second folder holds the metadata written last (touched above): it is the one in use,
# though no CLAUDE_CONFIG_DIR or profile root names it.
[ "$(jq -c 'map(.inUse)' <<<"$got")" = '[false,false,true]' ] || fail "accounts: the account in use is not marked: $got"
# A Foreman's account is the one holding its session's transcript, never the metadata written last.
# Bugs caught: the newest metadata labelled the second account this machine's Foreman; the mark was read from a
# machine-wide folder no Foreman writes, so the accounts the Foremen ran on were shown as unused; a grouped project's
# kept mark, which no Foreman reads, labelled its old session's account.
[ "$(jq -c 'map(.foreman)' <<<"$got")" = '[true,true,false]' ] || fail "accounts: a Foreman's account is not the one its transcript is in: $got"
# A relative folder in the host file is under the home folder, as the engine reads it, whatever the current folder.
# Bug caught: it was read under the Board's current folder, while the engine's sessions read it under their worktree.
AHOME3=$T/home-relative; mkdir -p "$AHOME3/.config/conveyor" "$AHOME3/profiles/rel"
echo '{"accounts": [{"name": "rel", "configDir": "profiles/rel"}]}' > "$AHOME3/.config/conveyor/host.json"
got=$(cd "$T" && env -u CONVEYOR_CLAUDE_PROFILES -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME HOME="$AHOME3" CONVEYOR_HOST_OS=Linux \
  python3 "$LIM" accounts "$T/accounts-cache-rel") || fail "accounts_relative: the read failed"
[ "$(jq -r '.[] | select(.name == "rel") | .folder' <<<"$got")" = "$AHOME3/profiles/rel" ] || fail "accounts_relative: $got"
# A Board run from a linked worktree reads its main checkout's mark: the Foreman's folder is the main checkout's.
# Bug caught: the mark was looked for under the worktree, so the Foreman's account was shown as unused there.
AHOME4=$T/home-worktree; WM=$T/wt-main; WL=$T/wt-linked
mkdir -p "$AHOME4/.config/conveyor" "$AHOME4/.claude/projects/-srv-main" "$WM/conveyor/state/foreman"
echo '{}' > "$AHOME4/.config/conveyor/host.json"; : > "$AHOME4/.claude/projects/-srv-main/fore-w.jsonl"
git -C "$WM" init -q && git -C "$WM" -c user.name=test -c user.email=noreply@example.com commit -q --allow-empty -m first \
  && git -C "$WM" worktree add -q --detach "$WL" || fail "accounts_worktree: no linked worktree"
echo "fore-w 2026-11-12T00:00:00Z" > "$WM/conveyor/state/foreman/session"
mkdir -p "$WL/.claude/scripts" && cp "$LIM" "$WL/.claude/scripts/"
got=$(env -u CONVEYOR_CLAUDE_PROFILES -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u GIT_DIR -u GIT_WORK_TREE HOME="$AHOME4" CONVEYOR_HOST_OS=Linux \
  python3 "$WL/.claude/scripts/dashboard_limit.py" accounts "$T/accounts-cache-worktree") || fail "accounts_worktree: the read failed"
[ "$(jq -c 'map(.foreman)' <<<"$got")" = '[true]' ] || fail "accounts_worktree: the main checkout's Foreman is not found: $got"
# A second read inside the TTL asks for nothing again.
: > "$T/accounts-asked"; accts > /dev/null; [ ! -s "$T/accounts-asked" ] || fail "accounts: a fresh reading was asked for again: $(cat "$T/accounts-asked")"
# fetch with a folder reads that account, never the one written last.
got=$(env -u CONVEYOR_CLAUDE_PROFILES -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$AHOME2" CONVEYOR_HOST_OS=Linux python3 -c "import sys, io, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
class R(io.BytesIO):
    __enter__ = lambda s: s
    __exit__ = lambda s, *a: None
d.urllib.request.urlopen = lambda req, timeout=None: R(json.dumps({'seven_day': {'utilization': {'Bearer tok-2': 97}.get(req.headers['Authorization'], 1)}}).encode())
sys.exit(d.main(['x', 'fetch', '$X2']))") || fail "fetch_folder: the read failed"
[ "$(jq -c '[.seven_day.utilization, .account.folder]' <<<"$got")" = "[97,\"$X2\"]" ] || fail "fetch_folder: $got"
) & part accounts

bad=()
for p in "${PARTS[@]}"; do wait "${p#*:}" || bad+=("${p%%:*}"); done
[ ${#bad[@]} -eq 0 ] || fail "these parts failed (their FAIL lines are above): ${bad[*]}"
echo "PASS: dashboard-limit"
