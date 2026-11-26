#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The collector of the Conveyor dashboard (dashboard.sh). The page is what the owner reads instead of asking, so the
# data must never lie: every panel's part is cut from the same answers, a source that was not read is null with its
# reason (never a 0 or an empty list that reads as measured), a host that did not answer is said to be unreachable,
# and a sum with an unpriced step in it is unknown, never the sum of the priced part.
# This file has the parts that read the cards on both records (cards, machine, figures); dashboard.test.sh and
# dashboard-local.test.sh have the others.
set -euo pipefail
# CONVEYOR_SHELL_TEST_CASE=<part>[,<part>] runs only those parts (each part's `) & started <part>` line below), as the
# coverage map selects them (.conveyor/test-changed.sh, issue 527); an unknown name exits 2. Unset, every part runs.
PARTSEL=${CONVEYOR_SHELL_TEST_CASE:-}; PARTSEL=${PARTSEL//,/ }; unset CONVEYOR_SHELL_TEST_CASE
for p in $PARTSEL; do grep -qxF ") & started $p" "$0" || { echo "unknown part $p" >&2; exit 2; }; done
# This file's own touch -d and stat -c are GNU calls: on macOS they run Homebrew's, as Conveyor's do (portable.sh).
. "$(dirname "$0")/../../../conveyor/lib/portable.sh"; p_tools
. "$(dirname "$0")/../../../conveyor/tests/wait.sh"

SOURCE=$(git rev-parse --show-toplevel)
DASH=$SOURCE/.claude/scripts/dashboard.sh
TOP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}"/dashboard-test.XXXXXX)" && pwd -P) # physical spelling: on the Mac the temp folder is a link (/tmp to /private/tmp)
trap 'chmod -R u+w "$TOP" 2>/dev/null; rm -rf "$TOP"' EXIT
# The host file is XDG_CONFIG_HOME's when it is set, ahead of the test's HOME: an inherited one is the owner's real host.
unset XDG_CONFIG_HOME
fail() { echo "FAIL: $*" >&2; exit 1; }
# The page server runs on the Board's own virtualenv (conveyor.sh setup fills it). Every run below has the test's
# HOME, so XDG_DATA_HOME names where the real one is, for dashboard.sh and for this file's own calls.
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || fail "the Board's virtualenv $PY lacks its packages: run conveyor.sh setup"
REALPY=$(command -v python3) # the python3 a collect runs, for the stub setup writes

# The parts below run side by side ( fresh <part>; ... ) &, so the file takes its slowest part's time, not their sum.
# fresh <part> -- the part's own folder ($T, under $TOP), checkout, host file, stubs and dashboard folder, set up as
# every part begins. A part PARTSEL leaves out ends here, passed.
fresh() {
[ -z "$PARTSEL" ] || [[ " $PARTSEL " == *" $1 "* ]] || exit 0
setup "$1"
}
# A long part runs its stretches that need no state of one another side by side too: each `( setup <part>-<n>; ... ) &
# PIECES+=($!)` has a folder of its own, set up as fresh's, and the part ends with `pieces`, failed when one failed.
PIECES=()
pieces() {
  local p bad=0
  for p in "${PIECES[@]}"; do wait "$p" || bad=1; done
  [ "$bad" -eq 0 ] || fail "a piece of this part failed (its FAIL line is above)"
}
# setup <folder> -- the folder $TOP/<folder> and all in it, as above.
setup() {
T=$TOP/$1; mkdir -p "$T"
# The limit read also walks the review sessions' Codex folder; without this a collect reads the owner's real spend.
export CONVEYOR_CODEX_REVIEW_HOME=$T/codex-review
MAIN=$T/main WS=$T/ws SCR=$T/scratch OUT=$T/out BIN=$T/bin
mkdir -p "$MAIN/.claude/metrics" "$MAIN/conveyor" "$WS" "$SCR" "$BIN" "$T/userhome"
git -C "$MAIN" init -q -b main
g() { git -C "$MAIN" -c user.email=t@t -c user.name=t "$@"; }
g commit -q --allow-empty -m "feat: base commit"
# Each project's decision ledger is where the host file's record names it on this machine; sample's has no decision
# yet. The Board's own checkout holds a ledger too, whose decision must never reach the page. widgetshop's path holds a
# backslash: the Board opens the path the host file names, character for character (it once doubled it).
PPL=$T/ledgers/sample/decisions.jsonl WSL=$T/ledgers/widget\\shop/decisions.jsonl
mkdir -p "${PPL%/*}" "${WSL%/*}"; : > "$PPL"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
# The usage limit and accounts read (dashboard_limit.py, three Python starts a collect, some 40% of its CPU) fails
# at once here, so the limit part is "could not be built" and every other python3 call runs the real one. A part that
# checks the limit, the accounts or the session cost calls limit_read first, and its collects read them for real.
stub python3 'case "${1-}" in */dashboard_limit.py) exit 1 ;; esac; exec '"$(printf %q "$REALPY")"' "$@"'
limit_read() { rm -f "$BIN/python3"; }

# Conveyor's host: two records on one machine, reached over ssh. The ssh stub records its arguments and answers
# with $T/ssh-out, $T/ssh-err and the exit code in $T/ssh-rc, so no test opens a connection. The host's accounts
# read is answered with $T/ssh-accounts (nothing when there is none).
# The first record names its two lanes' folders on this machine, neither in the worktrees folder ($WS) nor named as
# that folder's lanes were (the research lane's under the home folder, written ~/); the second names no lane.
FL=$T/lanes/main-fast-lane
jq -cn --arg l "$PPL" --arg f "$FL" '{host: "devbox", ssh: "user@devbox", main: "/srv/main",
  records: [{repo: "sample", main: "/srv/main", ledger: $l, lanes: {fast: {worktree: $f}, research: {worktree: "~/lanes/main-research"}}},
    {repo: "widgetshop", main: "/srv/cd"}]}' > "$MAIN/conveyor/host.json"
stub ssh 'case "$*" in *"dashboard_limit.py accounts"*) printf "%s\n" "$*" >> "'"$T"'/ssh-accounts-calls"; cat "'"$T"'/ssh-accounts" 2>/dev/null; exit 0 ;; esac
printf "%s\n" "$*" >> "'"$T"'/ssh-calls"
cat "'"$T"'/ssh-out" 2>/dev/null
[ ! -s "'"$T"'/ssh-err" ] || cat "'"$T"'/ssh-err" >&2
exit "$(cat "'"$T"'/ssh-rc" 2>/dev/null || echo 0)"'

ago() { date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ; }
NOWISO=$(ago 0)
# The snapshots' day, taken once like NOWISO. Bug caught (issue 363): each snapshot and the check of the day it gave
# read the clock on their own, so a run that went past midnight failed "nothing landed is an empty list for today".
DAY=$(date +%F)
# snap [<overrides>] -- one record's snapshot as conveyor.sh prints it: empty and healthy unless overridden.
snap() {
  local o=${1:-}; [ -n "$o" ] || o='{}'
  jq -cn --arg day "$DAY" --arg now "$NOWISO" --argjson o "$o" '
    {time: $now, day: $day, needsYou: {waiting: [], blocked: [], before: []}, belt: [], queue: {next: []}, landed: [], landedCount: 0,
     health: {time: $now, loop: true, newest: $now, blocked: [], waiting: [], stuck: [], unpushed: [], pushError: null, pushFailingSince: null,
              gh: true, ghReached: false, diskFreeKb: 500000000, builderCap: 3, models: {claude: "claude-x", codex: "gpt-x"}},
     cost: {today: 0, week: 0, perLanded: null, landedAfter: {"1": 0, "2": 0, "3": 0, more: 0}, unpricedSteps: 0, cards: []}} * $o'
}
# answer <snapshot 1> <origin 1> <pushed epoch 1> <snapshot 2> <origin 2> <pushed epoch 2> -- what the
# host prints for the collector's one command: three lines a record, then the end marker.
answer() {
  printf '%s\n%s\n%s\n%s\n%s\n%s\n@@end\n' "$1" "$2" "$3" "$4" "$5" "$6" > "$T/ssh-out"
  echo 0 > "$T/ssh-rc"; : > "$T/ssh-err"
}
# An ssh remote, its host apart: written out, git@<host> is an email hit of conveyor/privacy/check.sh.
GH=github.com
P_URL=git@$GH:example/sample-project.git C_URL=https://github.com/example/WidgetShop
quiet() { answer "$(snap)" "$P_URL" 1794000000 "$(snap)" "$C_URL" 0; }

# A collect in the same second as the last one would be answered from that cycle's own request cache: a cache is
# reused only by a collect stamped with its `cycle`. So wait out that second, and only when a cache has one: waiting out
# every collect's end second cost some 25 s a run, most of it before the test has written any transcript.
new_cycle() {
  local c; c=$({ cat "$OUT"/cache/*-requests.json 2>/dev/null || :; } | jq -s 'map(.cycle? | numbers) | max // empty | floor')
  while [ -n "$c" ] && [ "$(date +%s)" = "$c" ]; do sleep 0.1; done
}
# One collect, bounded: a hang fails here, naming the line, instead of running into the file's budget.
run() {
  local rc=0
  new_cycle
  env -u CONVEYOR_HOOK_FIRE_LOG -u CODEX_HOME HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" \
    CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" \
    timeout 120 bash "$DASH" || rc=$?
  [ "$rc" -ne 124 ] || fail "HUNG: a collect ran past 120 s (line ${BASH_LINENO[0]})"
  [ "$rc" -eq 0 ] || fail "dashboard.sh exited $rc (line ${BASH_LINENO[0]})"
}
D=$OUT/data.js
}
json() { sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$D"; }
q() { json | jq -e "$1" >/dev/null || fail "$2 (jq: $1; data: $(json | jq -c '.panels' | cut -c1-1500))"; }
PARTS=()
started() { PARTS+=("$1:$!"); } # <part>, after its ( ... ) &

# --- cards on both records: every row names its repo and links to that repo's issue ---
# cards_fixture -- the two records' snapshots with cards on them (P, C) and each repo's issue links (PU, CU), which the
# parts from here to the host that did not answer read.
cards_fixture() {
# One read of the clock: a card id and its landing time from two reads were a day apart across midnight.
TODAY_ISO=$(date -u +%Y-%m-%d); TODAY=${TODAY_ISO//-/}
P=$(snap '{"needsYou": {"waiting": [{"card": "c1-12", "issue": 12, "title": "Button copy", "sentence": "Staff see a new button.", "since": "'"$(ago 600)"'"}],
                        "blocked": [{"card": "c2-13", "issue": 13, "title": "Broken", "reason": "tests failed twice", "since": "'"$(ago 900)"'",
                                     "track": {"records": [{"name": "tests failed", "state": "failed", "failures": {"files": [{"file": "a.test", "cases": [{"name": "adds up"}]}]}}]},
                                     "reviews": [{"round": 1, "verdict": "NO-GO", "sec": 40}], "metrics": {"tokens": 5000, "usd": 0.4, "timeline": [{"model": "claude-x"}, {"model": "gpt-x"}]}}],
                        "before": [{"issue": 14, "title": "Green Pay", "section": "The Pay page: a green button.", "since": "'"$(ago 1200)"'"}],
                        "engine": {"commit": "cccc", "reason": "its check of the pack failed: .tunables.x: not a field of the schema", "since": "'"$(ago 800)"'"},
                        "testRules": {"time": "'"$(ago 500)"'", "matched": 5, "cap": 3}, "prices": {"models": ["claude-new-9", "m"]},
                        "stopped": {"title": "The engine is stopped", "reason": "A stop signal holds the engine. Run kill -CONT 1234 1235 to resume them.", "since": "'"$(ago 300)"'", "pid": 1234, "pids": [1234, 1235]}},
  "mainTest": {"issue": 15, "cases": ["alpha", "beta"], "from": "aaaa", "to": "bbbb", "since": "'"$(ago 700)"'", "exit": 1},
  "flaky": [{"case": "b.test: flaky", "count": 3, "issue": 16}, {"case": "c.test: other", "count": 1, "issue": null}],
  "belt": [{"card": "c3-801", "issue": 801, "title": "Rebuild the dashboard", "step": "review", "review": 2, "of": 3, "stepAt": "'"$(ago 300)"'", "model": "gpt-x", "tokens": {"claude": 10, "codex": 5}, "usd": 1.25, "seats": {"failed": "the judge timed out"}}],
  "queue": {"next": [{"issue": 20, "title": "Next up", "priority": "P1", "followup": true, "retried": false}],
    "order": [{"issue": 20, "title": "Next up", "priority": "P1", "followup": true, "retried": false}], "holding": [{"issue": 30, "title": "Held one"}],
    "skipped": [{"issue": 31, "title": "Infra one", "rule": "area:infra"}],
    "waiting": [{"issue": 32, "title": "Second half", "priority": "P2", "followup": false, "retried": false, "created": "2026-11-01T00:00:00Z", "waitsFor": [20]}],
    "cards": [{"card": "c20261102T000001-sample-0", "kind": "Docs sweep"}]},
  "control": {"mode": "pause", "cap": null, "guard": 90, "held": [30], "order": [], "rules": {"P0": true, "P1": true, "P2": true, "followups": true, "never": ["area:infra"], "healsdays": 30}, "model": null, "reviewer": null, "judgeOn": true, "suiteMachine": {"kind": "ssh", "target": "dev@192.0.2.7", "dir": "~/suite"}},
  "modelSettings": {"builder": {"model": "claude-x", "effort": "medium", "modelFrom": "seed", "effortFrom": "seed", "choices": ["claude-x"], "efforts": ["low"]},
    "judge": {"model": "claude-j", "effort": "high", "modelFrom": "seed", "effortFrom": "seed", "choices": ["claude-j"], "efforts": ["high"], "default": "claude-j"}},
  "prices": {"seen": []}, "areaPrefix": "team/", "packLandAs": "pr", "packPrMerge": "idle", "packPick": {"lists": {"builder": {"claude-x": {"min": "medium", "max": "high"}}}, "efforts": {"claude": ["low", "medium", "high"]}}, "standing": ["asked-fix"], "pushCheck": false, "lintCommands": [{"run": "shellcheck {files}", "files": ["*.sh"]}], "snapshotAt": "2026-11-05T00:00:02Z",
  "health": {"state": "paused", "reason": "the loop says why", "unchecked": 2, "guard": {"at": 90, "reading": 42, "readAt": "'"$(ago 60)"'", "missing": false}, "cycles": [[40, 41]],
    "engineStopped": {"pid": 1234, "since": "2026-11-05T00:00:00Z", "pids": [1234, 1235]},
    "pressure": {"state": "Busy", "cpu": 45.5, "memory": 1.5, "wakeMs": 0.2, "freeMB": null, "why": "CPU pressure 45.5% is at or above 40%"},
    "routes": {"subscription": {"state": "expired", "at": "2026-11-05T00:00:00Z"}, "proxy": {"state": "works", "at": "2026-11-05T00:00:01Z", "baseUrl": "http://127.0.0.1:4141", "route": "fallback"}},
    "unpushed": [{"card": "c5-7", "issue": 7, "sha": "abc", "since": "2026-11-05T00:00:00Z"}],
    "landingPr": {"number": 12, "url": "https://github.com/o/r/pull/12", "cards": 2, "merge": null},
    "pushing": {"pid": 42, "since": "2026-11-05T00:00:00Z", "sha": "abc", "log": "/s/pushlogs/1.log", "sec": 9, "line": "3/9 passed", "stale": false},
    "pushLast": {"time": "2026-11-05T00:00:00Z", "by": "now", "started": true, "ok": false, "ahead": 1}},
  "forecast": {"cards": 1, "usd": 0.95, "perCard": {"usd": 0.95, "pct": 0.5}, "guard": 90, "reading": 42, "pausesAt": null},
  "fullTest": {"command": true, "why": null, "running": null, "last": {"time": "2026-11-05T01:00:00Z", "kind": "run", "push": true, "sha": "abc", "state": "failed", "exit": 1, "cases": [], "pushed": null}},
  "open": {"count": 6, "split": {"queued": 2, "you": 1, "labelOrRule": 2, "belt": 1}, "held": [{"issue": 30, "title": "Held one", "priority": "P3", "followup": false, "labels": [], "created": null, "parent": null, "reasons": [{"kind": "you"}]},
    {"issue": 33, "title": "Backlog one", "priority": "P2", "followup": false, "labels": ["backlog"], "created": null, "parent": null, "reasons": [{"kind": "label", "label": "backlog"}]}],
    "umbrellas": [{"issue": 34, "title": "Parent one", "parts": ["#35", "#36"], "done": 1, "all": 2, "inFlight": [], "closed": ["#35"]}]},
  "awaitingDeploy": [{"issue": 802, "title": "Stack split", "since": "2026-11-05T00:00:00Z"}, {"issue": 803, "title": "No time", "since": null}],
  "metrics": {"cards": [{"card": "c5-1", "issue": 1, "metrics": {"buildSec": 600, "reviewSec": 300, "fixSec": null}}, {"card": "c5-2", "issue": 2, "metrics": {"buildSec": 200, "reviewSec": 100, "fixSec": 0}},
    {"card": "c5-3", "issue": 3, "metrics": {"buildSec": 400}}], "prev": {"cards": 2, "landed": 1}, "days": [{"day": "2026-11-09", "landed": 1, "blocked": 0}],
    "slots": [{"hour": 9, "slots": 1.5, "cap": 3}],
    "steps": [{"card": "c5-9", "issue": 9, "steps": [{"step": "review", "time": "2026-11-09T09:00:00Z", "judgeWrites": {"model": "claude-haiku-5-5", "write": 40, "write1h": 0}}]}]},
  "declined": [{"id": "d0123456789ab", "time": "'"$TODAY_ISO"'T08:40:00Z", "card": "c3-801", "issue": 801, "finding": "[P1] b.txt:2 no mark here", "by": "judge", "why": "its proof needs a stub built to misbehave", "repo": "sample"}],
  "declinedRest": [{"id": "dba9876543210", "time": "'"$TODAY_ISO"'T07:10:00Z", "card": "c0-6", "issue": 6, "finding": "[P2] a.txt:1 wrong word", "by": "code", "why": "follow-up of a follow-up", "repo": "sample", "built": 90},
    {"id": "d0000000000dd", "time": "'"$TODAY_ISO"'T08:50:00Z", "card": "c3-801", "issue": 801, "finding": "[P3] d.txt:4 a word", "by": "judge", "why": "taste", "repo": "sample", "dismissed": {"time": "'"$TODAY_ISO"'T09:00:00Z", "by": "Board user owner"}}],
  "selfheals": {"entries": [{"id": "h0123456789ab", "time": "'"$TODAY_ISO"'T08:30:00Z", "card": "c3-801", "issue": 801, "repo": "sample", "area": "area:engine",
    "finding": "[P2] a.sh:3 a slow poll", "why": "the next turn picks it up", "effect": "self-heals", "from": "review", "seen": "'"$TODAY_ISO"'T08:45:00Z", "sightings": 2,
    "expired": {"time": "2026-11-02T00:00:00Z", "why": "harm", "filed": 812}}],
    "dropped": [{"id": "h0000000000dd", "time": "2026-10-01T00:00:00Z", "card": "c3-700", "issue": 700, "repo": "sample", "area": "area:engine",
      "finding": "[P2] a.sh:9 an old wait", "why": "a longer wait", "effect": "self-heals", "from": "review", "dropped": {"time": "2026-11-01T00:00:00Z", "why": "expired"}}],
    "areas": [{"area": "area:engine", "count": 1}], "sorted": {"time": "'"$TODAY_ISO"'T07:00:00Z", "ended": "'"$TODAY_ISO"'T07:01:00Z", "items": 2, "moved": 1},
    "docs": {"entries": [{"id": "d0123456789ab", "time": "'"$TODAY_ISO"'T08:40:00Z", "card": "c3-801", "issue": 801, "repo": "sample", "area": "area:board",
      "finding": "[P3] docs/board.md:9 omits the docs list", "why": "the page omits it", "effect": "docs drift", "from": "review"}], "areas": [{"area": "area:board", "count": 1}]}},
  "landedCount": 1, "landedUsd": 41.5,
  "landed": [{"card": "c'"$TODAY"'T080000-7", "issue": 7, "title": "Landed one", "step": "landed", "time": "'"$TODAY_ISO"'T08:30:00Z", "usd": 2.5, "reviews": 2, "followups": [31], "sha": "abc", "pushed": true, "start": "'"$TODAY_ISO"'T07:00:00Z", "totalSec": 2400}],
  "pushedCards": [{"card": "c0-6", "issue": 6, "time": "'"$(date -u -d yesterday +%F)"'T23:00:00Z", "day": "'"$(date +%F)"'"},
    {"card": "c0-5", "issue": 5, "time": "'"$TODAY_ISO"'T00:30:00Z", "day": "'"$(date -d yesterday +%F)"'"}],
  "cost": {"today": 3.75, "week": 10, "perLanded": 2.5, "landedAfter": {"1": 0, "2": 1, "3": 0, "more": 0}, "unpricedSteps": 0,
    "cards": [{"card": "c3-801", "issue": 801, "title": "Rebuild the dashboard", "state": "on the belt", "today": 1.25, "week": 1.25},
      {"card": "c0-6", "issue": 6, "title": "Landed days ago", "state": "landed", "today": 0, "week": 6.25},
      {"card": "c2-13", "issue": 13, "title": "Broken", "state": "blocked", "today": 2.5, "week": null}],
    "picks": [{"group": "small docs", "model": "claude-x", "effort": "medium", "cards": 2, "landed": 1, "usd": 5, "firstTry": 0, "reviews": 2, "open": 0}],
    "trials": {"dropped": [{"group": "small docs", "model": "claude-y", "effort": "medium", "cards": ["c1-5", "c1-10"]}], "flagged": [{"card": "c1-15", "issue": 15, "group": "small code", "files": ["ci/deploy.sh"]}]},
    "replay": {"model": "claude-j", "agree": 1, "findings": 2}}}')
C=$(snap '{"belt": [{"card": "c4-5", "issue": 5, "title": "Plugin thing", "step": "build", "review": null, "of": 3, "stepAt": "'"$(ago 60)"'", "model": "claude-x", "tokens": {"claude": 1, "codex": 0}, "usd": 0.25}],
  "queue": {"next": [{"issue": 9, "title": "CD next", "priority": "P3", "followup": false, "retried": true}]},
  "open": {"count": 3, "split": {"queued": 1, "you": 1, "labelOrRule": 0, "belt": 1}, "held": [{"issue": 10, "title": "CD held", "priority": "P3", "followup": false, "labels": [], "created": null, "parent": null, "reasons": [{"kind": "you"}]}]},
  "declined": [{"id": "d00000000000c", "time": "'"$TODAY_ISO"'T08:00:00Z", "card": "c4-red", "issue": 0, "name": "Main is red (0123456789ab)", "finding": "[P2] c.txt:3 a nit", "by": "owner", "why": "not worth a card", "repo": "widgetshop"}],
  "landedCount": 1,
  "landed": [{"card": "c'"$TODAY"'T090000-4", "issue": 4, "title": "CD fixed already", "step": "closed", "time": "'"$TODAY_ISO"'T09:10:00Z", "usd": 0.5, "reviews": 1, "followups": [], "sha": "", "pushed": null}],
  "health": {"loop": false, "builderCap": 2, "unpushed": [{"card": "c9-2", "issue": 2, "sha": "def", "since": "'"$(ago 3600)"'"}]},
  "cost": {"today": 0.5, "week": 4, "perLanded": 0.5, "landedAfter": {"1": 3, "2": 0, "3": 0, "more": 0}, "unpricedSteps": 1,
    "cards": [{"card": "c8-4", "issue": 4, "title": "CD fixed already", "state": "retried", "today": 0.5, "week": 0.5}],
    "picks": [{"group": "small code", "model": "claude-x", "effort": "medium", "cards": 1, "landed": 1, "usd": null, "firstTry": 1, "reviews": 1, "open": 0}]},
  "release": {"tag": "v1.0.0", "count": 2, "commits": [], "next": "1.1.0", "notes": true, "head": "abc"},
  "suites": [{"kind": "release", "version": "1.1.0", "sha": "abc", "ended": null, "state": "running", "done": 3, "failed": 1, "cases": ["x: y"]}]}')
PU=https://github.com/example/sample-project/issues CU=https://github.com/example/WidgetShop/issues
}

( fresh cards; cards_fixture
answer "$P" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
# Bug: the Release panel gets nothing of a record's main or its release run, or a record from an older engine breaks it;
# its changes link no issue, for want of the repository's address.
q '.panels.release == {error: null, data: {records: [{repo: "sample", url: "https://github.com/example/sample-project", release: null, suites: null,
    suiteMachine: {kind: "ssh", target: "dev@192.0.2.7", dir: "~/suite"}, suiteMode: null},
  {repo: "widgetshop", url: "https://github.com/example/WidgetShop", suiteMachine: null, suiteMode: null,
  release: {tag: "v1.0.0", count: 2, commits: [], next: "1.1.0", notes: true, head: "abc"},
  suites: [{kind: "release", version: "1.1.0", sha: "abc", ended: null, state: "running", done: 3, failed: 1, cases: ["x: y"]}]}]}}' \
  "the Release part is each record's release, suites and the rule's suite machine as its snapshot gives them, null from a snapshot from before them"
q '.panels.belt.data | .cap == 5 and (.cards | map([.repo, .issue, .step, .url])) == [["sample", 801, "review", "'"$PU"'/801"], ["widgetshop", 5, "build", "'"$CU"'/5"]]' "belt rows name their repo and link to that repo's issue (an ssh origin is the repo's https address)"
q '.panels.belt.data.cards[0] | .review == 2 and .of == 3 and .model == "gpt-x" and .usd == 1.25 and (.stepAt | fromdateiso8601) > 0' "a belt row keeps its step, review number, model, cost and the time the step began"
q '.panels.needs.data.cards | (.waiting | map([.repo, .issue, .sentence, .url])) == [["sample", 12, "Staff see a new button.", "'"$PU"'/12"]] and (.blocked | map([.issue, .reason])) == [[13, "tests failed twice"]]' "what waits on the owner: the visible change with the reviewer's sentence, and the blocked card with its reason"
q '.panels.needs.data.cards.before | map([.repo, .issue, .section, .url]) == [["sample", 14, "The Pay page: a green button.", "'"$PU"'/14"]]' "an issue waiting for the yes before its build names its repo, its section and its link"
# The whole test on main is no card's step, so its failure is no blocked card: without its own row the owner never sees it.
q '.panels.needs.data.tests | map([.repo, .issue, .cases, .from, .to, .url]) == [["sample", 15, ["alpha", "beta"], "aaaa", "bbbb", "'"$PU"'/15"]]' "a record whose whole test fails on main is in Needs you with its issue, cases and commits; a record with no failure adds none"
# A following record that refused a commit of the plugin's main stays on its old engine: without a row the owner never learns why.
q '.panels.needs.data.engines | map([.repo, .commit, .reason]) == [["sample", "cccc", "its check of the pack failed: .tunables.x: not a field of the schema"]]' "a commit of the plugin's main a record did not take is in Needs you with the commit and why; a record with none adds none"
# Issue 519: a run of the test rules that matched more files than one day's cap filed none; without a row the owner never learns the rules wait for them.
q '.panels.needs.data.testRules | map([.repo, .matched, .cap]) == [["sample", 5, 3]]' "a record whose test rules held a run is in Needs you with the files matched and the cap; a record with none adds none"
# Issue 1074: Conveyor no longer files an issue for a model with no price, so Needs you is where the owner learns of one.
# Issue 1106: an engine held by a stop signal was named by `foreman status` alone; Needs you lists it with the
# command that resumes it, as the snapshot gives it (needsYou.stopped, the kind "stopped" of dashboard_needs.json).
q '.panels.needs.data.entries.stopped | map([.repo, .title, .reason]) == [["sample", "The engine is stopped", "A stop signal holds the engine. Run kill -CONT 1234 1235 to resume them."]]' "a record whose engine is stopped is in Needs you with the command that resumes it; a record with none adds none"
q '.panels.needs.data.prices | map([.repo, .models]) == [["sample", ["claude-new-9", "m"]]]' "a record whose loop found models with no price is in Needs you with them; a record with none adds none"
# Issue 1461 (A-R5): Model prices listed only the models the allowed lists name, so one Needs you counts (the Codex
# model a family name resolves to) had no row to add its price on: the Rules part carries the list it counts.
q '.panels.rules.data.prices == {seen: [], missing: ["claude-new-9", "m"]}' "the Rules part's prices do not carry the models Needs you counts as having no price"
q '.panels.queue.data | (.next | map([.repo, .issue, .priority, .followup, .retried])) == [["sample", 20, "P1", true, false], ["widgetshop", 9, "P3", false, true]] and .held == 3' "the queue lists each record's next issues in its order, and counts every record's held issues (open.held: by you, a label, a rule or a wait), as the Board's Held column has them"
q '.panels.queue.data.awaitingDeploy | map([.repo, .issue, .title, .since, .url]) == [["sample", 802, "Stack split", "2026-11-05T00:00:00Z", "'"$PU"'/802"], ["sample", 803, "No time", null, "'"$PU"'/803"]]' "the issues built and waiting for a PROD deploy are listed on their own (a record without the key adds none), each with its repo, link and since when"
# An issue that waits on another is in the queue and on the Board with what it waits for; a cycle reaches health.
q '.panels.queue.data.waiting | map([.repo, .issue, .waitsFor, .url]) == [["sample", 32, [20], "'"$PU"'/32"]]' "the queue lists each record's waiting issues with what each waits for"
q '.panels.board.data.waits | map([.issue, .waitsFor]) == [[32, [20]]]' "the Board has the waiting issues with what each waits for"
q '[.panels.health.data.records[] | .cycles] == [[[40, 41]], null]' "a dependency cycle reaches the health part; a record without the key has none"
# Bug (issue 1430): Health's SIGCONT command for a card under a stopped engine named the engine's pid alone, as the part
# dropped the engine's stopped processes, and the stopped wrapper under it kept holding the card.
q '[.panels.health.data.records[] | .engineStopped] == [{pid: 1234, since: "2026-11-05T00:00:00Z", pids: [1234, 1235]}, null]' "a stopped engine with each stopped process under it reaches the health part; a record without it has null"
# Issue 261: the landed cards with a skipped lint command (Health's Lint check row) and the pack's lint commands (the
# Rules tab's Lint check list) reach the Board; dropped here, neither shows.
q '[.panels.health.data.records[] | .unchecked] == [2, null] and .panels.rules.data.lintCommands == [{run: "shellcheck {files}", files: ["*.sh"]}]' \
  "the unchecked count reaches the health part and the pack's lint commands the rules part"
# Issue 398: the host prints its kept snapshot, made before it is read. Health carries when it was made (its row says
# the age past a minute), and the Rules part's readAt is that time: dated by the read, a move the Board waits on was
# taken as read by a snapshot made before it.
q '[.panels.health.data.records[] | .snapshotAt] == ["2026-11-05T00:00:02Z", null] and .panels.rules.data.readAt == "2026-11-05T00:00:02Z"' \
  "the kept snapshot's time reaches Health and dates the Rules part's read; a snapshot that does not say has none"
# Issue 346: the machine room is removed; a snapshot of an older engine that still names the pressure (the first
# record's) does not bring it into the health part.
q '[.panels.health.data.records[] | has("pressure")] == [false, false]' "the machine's pressure no longer reaches the health part"
# The Claude routes' states (the health record's routes): without them Health cannot show an expired login or the proxy.
q '[.panels.health.data.records[] | .routes | if . == null then null else [.subscription.state, .proxy.state, .proxy.baseUrl] end] == [["expired", "works", "http://127.0.0.1:4141"], null]' "each record's Claude routes reach the health part; a record without the key has none"
# Each record's repository address: without it Health cannot link a flaky case's or a kept-off file to the file.
q '[.panels.health.data.records[] | .repoUrl] == ["https://github.com/example/sample-project", "https://github.com/example/WidgetShop"]' "each health record carries its repository's address"
# The flaky cases of each record (the snapshot's flaky): without them the Health panel has no Flaky tests line.
q '[.panels.health.data.records[] | .flaky] == [[{case: "b.test: flaky", count: 3, issue: 16, url: "'"$PU"'/16"}, {case: "c.test: other", count: 1, issue: null, url: null}], null]' "each record's flaky cases reach the health part, an issue filed with its link; a record without the key has none"
q '.panels.landed.data.cards | map([.repo, .issue, .step, .tookSec, .reviews, .usd, .pushed]) == [["widgetshop", 4, "closed", 600, 1, 0.5, null], ["sample", 7, "landed", 2400, 2, 2.5, true]]' "landed cards, newest first, each with its reviews, cost and the seconds from the first pick-up of its work to its landing (the snapshot's totalSec, else its card id's time)"
# Bug: the Declined panel lists one record's lines after another's, not the newest first, or loses who declined a finding and why;
# a built or dismissed line is in the panel's lines, or lost from the rest ("Show every line"), or loses who dismissed it.
# Issue 141: a main-red fix card's line (issue 0) keeps its name, or the panel can only call it "#0".
# Issue 403: each line keeps its repository's address, or a main-red fix card's reason (no issue url) cannot link a file:line.
q '.panels.declined.data.lines | map([.repo, .repoUrl, .id, .issue, .name, .url, .finding, .by, .why, .built, .dismissed]) == [["sample", "https://github.com/example/sample-project", "d0123456789ab", 801, null, "'"$PU"'/801", "[P1] b.txt:2 no mark here", "judge", "its proof needs a stub built to misbehave", null, null],
  ["widgetshop", "https://github.com/example/WidgetShop", "d00000000000c", 0, "Main is red (0123456789ab)", null, "[P2] c.txt:3 a nit", "owner", "not worth a card", null, null]]' \
  "the declined findings the panel shows, of every record, newest first, each with who declined it and why"
q '.panels.declined.data.rest | map([.repo, .id, .url, .built, .dismissed]) == [["sample", "d0000000000dd", "'"$PU"'/801", null, {time: "'"$TODAY_ISO"'T09:00:00Z", by: "Board user owner"}],
  ["sample", "dba9876543210", "'"$PU"'/6", 90, null]]' "the rest, newest first: the dismissed line with who dismissed it and when, and the built line with its issue"
# Issue 1559: the self-heals list of each record that has one reaches the Declined part, its entries with their
# repository and issue link, so the Board shows them and files an area's batch card on the right record.
q '.panels.declined.data.heals | map([.repo, .repoUrl, .areas, .sorted.moved, (.entries | map([.id, .url, .area, .finding, .why, .effect]))]) == [["sample", "https://github.com/example/sample-project",
  [{area: "area:engine", count: 1}], 1, [["h0123456789ab", "'"$PU"'/801", "area:engine", "[P2] a.sh:3 a slow poll", "the next turn picks it up", "self-heals"]]]]' \
  "the self-heals list of the record that has one, with its areas, its last sort and its entries"
# The Self-heals page: each entry's sighting count, last sighting and source, and the record's days an entry stays.
# Bug it catches: the part left them out, so the page could show neither "seen N×" nor the days left; nor the move up
# to harm an entry had before a review listed it again (expired), so the page's harm tile lost it.
q '.panels.declined.data.heals | map([.days, (.entries | map([.from, .seen, .sightings, .expired.why]))]) == [[30, [["review", "'"$TODAY_ISO"'T08:45:00Z", 2, "harm"]]]]' \
  "the self-heals list with the record's healsdays and each entry's source, last sighting, sightings and earlier move up to harm"
# Issue 1561: the entries that expired off the list reach the Declined part with their dates. Bug it catches: the panel's
# data left out the snapshot's selfheals.dropped, so the Board could not show what expired.
# Issue 1614: each carries left, the time it left the list, which the panel sorts and shows them by.
q '.panels.declined.data.heals | map(.dropped | map([.id, .url, .finding, .dropped.why, .dropped.time, .left, .seen])) == [[["h0000000000dd", "'"$PU"'/700", "[P2] a.sh:9 an old wait", "expired", "2026-11-01T00:00:00Z", "2026-11-01T00:00:00Z", null]]]' \
  "the entries that expired off the self-heals list, with when they left and why"
# Issue 1563: the docs list of a record reaches the Declined part beside its self-heals list, so the Board shows it
# and files an area's docs sweep card on the right record. Bug it catches: the docs list left out of the panel's data.
q '.panels.declined.data.heals | map(.docs | [.areas, (.entries | map([.id, .url, .area, .finding, .effect]))]) == [[[{area: "area:board", count: 1}],
  [["d0123456789ab", "'"$PU"'/801", "area:board", "[P3] docs/board.md:9 omits the docs list", "docs drift"]]]]' \
  "the docs list of the record that has one, with its areas and its entries"
# Metrics' tiles and charts: each record's 7 days before, its days and today's slots, as its snapshot gives them.
q '.panels.metrics.data.records | map([.repo, .prev, .days, .slots]) == [["sample", {cards: 2, landed: 1}, [{day: "2026-11-09", landed: 1, blocked: 0}], [{hour: 9, slots: 1.5, cap: 3}]], ["widgetshop", null, null, null]]' \
  "metrics carries each record's 7 days before, its days and its slots by hour; a record without them has null"
# Bug caught: the cache-write alert read only the newest cards (the snapshot's cut), so it could not name the step of
# an older card's session. The snapshot's uncut steps reach the panel, each with its repo; a record without them has none.
q '.panels.metrics.data.steps | map([.repo, .card, .issue, .steps]) == [["sample", "c5-9", 9, [{step: "review", time: "2026-11-09T09:00:00Z", judgeWrites: {model: "claude-haiku-5-5", write: 40, write1h: 0}}]]]' \
  "metrics carries each record's card steps of the last 25 h"
# Belt 3D is cut from the same answers: a lane each belt card and stuck card, a bay each of queued, waiting, held and
# landed today. Bug it catches: a held issue, an issue waiting on another, or what it waits on, missing from the floor.
q '.panels.belt3d.data | (.belt | map([.repo, .issue, .step, .landed, .url])) == [["sample", 801, "review", false, "'"$PU"'/801"], ["widgetshop", 5, "build", false, "'"$CU"'/5"]]
  and (.queue.next | map([.repo, .issue])) == [["sample", 20], ["widgetshop", 9]] and (.queue.held | map([.repo, .issue, .title])) == [["sample", 30, "Held one"]]
  and (.queue.waiting | map([.repo, .issue, .waitsFor, .url])) == [["sample", 32, [20], "'"$PU"'/32"]]
  and (.needs | map([.issue, .kind, .reason])) == [[12, "waiting", "Visible change: Staff see a new button."], [13, "blocked", "tests failed twice"]]
  and (.landed | map([.issue, .title, .usd])) == [[4, "CD fixed already", 0.5], [7, "Landed one", 2.5]]' \
  "Belt 3D has every record's belt, stuck cards, queued, held and waiting issues (with what each waits on) and landed cards"
# A stuck card's details: its review rounds with their verdicts and findings, and its cost.
q '.panels.belt3d.data.needs | map([.issue, .reviews, .usd]) == [[12, [], null], [13, [{round: 1, verdict: "NO-GO", counts: null}], 0.4]]' \
  "Belt 3D's stuck cards carry their review rounds and cost"
q '.panels.health.data.records[1] | .loop == false and (.unpushed | length) == 1 and .builderCap == 2' "a stopped loop and an unpushed landing reach the health part"
# The Board is the record on host.json's main (sample here), never another record's cards.
q '.panels.board.data | .repo == "sample" and .state == "paused" and .loop == true and .control.mode == "pause" and .cap == 3 and .guard.at == 90
  and .limit == {pct: 42, from: "loop"} and .modelSettings.builder.choices == ["claude-x"] and .issuesError == null and .reason == "the loop says why"' "the Board's bar: the loop's state and its reason, the control record, the cap, the guard with the loop's own reading, and the model settings"
q '.panels.board.data | [(.held | map([.issue, .url])), (.queue | map([.issue, .priority])), (.skipped | map([.issue, .rule]))]
  == [[[30, "'"$PU"'/30"]], [[20, "P1"]], [[31, "area:infra"]]]' "the Board's Held, Queue and skipped issues come from the record, in pick order, with their links"
q '.panels.board.data | [(.building | map(.issue)), (.review | map([.issue, .review, .of])), (.waiting | map([.issue, .sentence])), (.blocked | map([.issue, .reason])), (.landed | map([.issue, .usd, .reviews]))]
  == [[], [[801, 2, 3]], [[12, "Staff see a new button."]], [[13, "tests failed twice"]], [[7, 2.5, 2]]]' "the Board's Building, Review, Needs you and Landed today are this record's cards alone"
# Bug (#524): the snapshot's landed holds only the day's newest cards, so the Board's Today figure counted and priced
# those alone: it takes the whole day's count and cost from the snapshot (landedCount, landedUsd).
q '.panels.board.data.today == {landed: 1, usd: 41.5, estimate: false}' "the Board's Today figure is the snapshot's whole day, not its landed list"
# Bug: Control's blocked card had no track and no reviews, so it could not lead with the tests that failed or the
# NO-GO reviews (app.js failure()), as Needs you does from the same card.
q '.panels.board.data.blocked[0] | .track.records[0].failures.files[0].cases[0].name == "adds up" and (.reviews | map(.verdict)) == ["NO-GO"]' \
  "the Board's blocked card carries its track and reviews, to lead with why it failed"
# The Rules panel is the same record's rules and what they produce, with the snapshot's forecast as it is.
q '.panels.rules.data | .repo == "sample" and .repoUrl == "https://github.com/example/sample-project" and .control.rules.never == ["area:infra"] and .cap == 3 and .guard.at == 90 and .building == 1 and .issuesError == null
  and [(.held | map([.issue, .url])), (.queue | map(.issue)), (.skipped | map([.issue, .rule]))] == [[[30, "'"$PU"'/30"]], [20], [[31, "area:infra"]]]
  and .forecast == {cards: 1, usd: 0.95, perCard: {usd: 0.95, pct: 0.5}, guard: 90, reading: 42, pausesAt: null}' "the Rules part: the record's GitHub address (the setup's owner/repo title), its rules, its queue, held and skipped, the cards on the belt and the forecast"
# The landed cards not pushed and the full test suite (Push landed, Run full test suite: actions on the Control tab's
# Board, not rules), as the snapshot has them; none from a snapshot without them.
q '.panels.board.data | (.unpushed | map([.issue, .card, .url])) == [[7, "c5-7", "'"$PU"'/7"]] and .fullTest.command == true and .fullTest.last.state == "failed"
  and (.others.widgetshop.unpushed | map(.issue)) == [2] and .others.widgetshop.fullTest == null' "the Board part: the landed cards not pushed and the full test suite"
q '.panels.rules.data | has("unpushed") or has("fullTest") | not' "the Rules part carries neither: its tab has no Push landed or Run full test suite"
# Bug (#1714): the part dropped the snapshot's waiting cards with no GitHub issue, so the Rules tab could show none.
q '.panels.rules.data.cards == [{card: "c20261102T000001-sample-0", kind: "Docs sweep"}]' "the Rules part gives the snapshot's queue.cards"
# The pack's Land as (#247): without it, the Rules tab shows Main for a project whose pack lands as a pull request.
q '.panels.rules.data.packLandAs == "pr"' "the Rules part gives the pack's push.landAs"
# Merge PR (#248): the pack's rule for the Rules tab, and the open pull request for the Control tab's Merge. Without
# them the Rules tab shows Button for a pack that merges when idle, and Merge never shows.
q '.panels.rules.data.packPrMerge == "idle" and .panels.board.data.landingPr == {number: 12, url: "https://github.com/o/r/pull/12", cards: 2, merge: null}
  and .panels.board.data.others.widgetshop.landingPr == null' "the Rules part gives the pack's push.prMerge, and the Board part the open pull request"
# The push in progress and the last push (issue 1078): without them the Control tab cannot tell a slow push from a stuck one.
q '.panels.board.data | .pushing.line == "3/9 passed" and .pushLast.ahead == 1 and .others.widgetshop.pushing == null and .others.widgetshop.pushLast == null' \
  "the Board part gives the push in progress and the last push"
# Pick settings (#1047, #1067): without the pack's pick lists and each program's efforts the Rules tab's row cannot
# show or set them, and without a card's seats its page cannot show what the Judge gave it.
q '.panels.rules.data.packPick == {lists: {builder: {"claude-x": {min: "medium", max: "high"}}}, efforts: {claude: ["low", "medium", "high"]}} and (.panels.board.data.review | map(select(.issue == 801) | .seats)) == [{failed: "the judge timed out"}]' \
  "the Rules part gives the pack's pick lists, and a Board card the seats of its pick"
# The Rules tab has the loop's state (its tab's count), the models, the limit reading, the waits and every held
# issue with its labels and reasons, as the Board has them; the pack's push.check false is kept false, not dropped as
# null (a `//` would drop it, and the Test before a push row would show On).
q '.panels.rules.data | .state == "paused" and .modelSettings.builder.choices == ["claude-x"] and .areaPrefix == "team/" and .standing == ["asked-fix"] and .pushCheck == false and .limit == {pct: 42, from: "loop"} and (.waits | type) == "array"
  and (.open.held | map([.issue, .url, (.reasons | map(.label // .kind))])) == [[30, "'"$PU"'/30", ["you"]], [33, "'"$PU"'/33", ["backlog"]]]' "the Rules part: state, models, limit, waits and the held issues with why"
# Every open issue reaches the Board, each held one with its reasons and a link; a record without it gives null.
q '.panels.board.data.open | .count == 6 and .split == {queued: 2, you: 1, labelOrRule: 2, belt: 1} and (.held | map([.issue, .url, (.reasons | map(.label // .kind))])) == [[30, "'"$PU"'/30", ["you"]], [33, "'"$PU"'/33", ["backlog"]]]' "the Board has every open issue: the split and the held ones with why"
# Bug: the snapshot's open parents (open.umbrellas) did not reach the Board, so it could not show a parent's parts as one row.
q '.panels.board.data.open.umbrellas | map([.issue, .url, .done, .all, .closed]) == [[34, "'"$PU"'/34", 1, 2, ["#35"]]]' "the Board has each open parent with its parts done of all and its link"
# Every record on the host is steered from the Board and the Rules tab: both parts name every record, and each record
# not on host.json's main has its own Board and Rules under others, its own cards and links, never main's. Bug: only
# main's record reached the page, so the second project's issues, queue and rules could not be seen or steered there.
q '.panels.board.data | .repos == ["sample", "widgetshop"] and (.others | keys) == ["widgetshop"]
  and (.others.widgetshop | .repo == "widgetshop" and (.building | map([.repo, .issue, .url])) == [["widgetshop", 5, "'"$CU"'/5"]] and (.landed | map(.issue)) == [4] and .waiting == [] and .blocked == [])' \
  "the Board names every record and carries the other record's own Board"
q '.panels.rules.data | .repos == ["sample", "widgetshop"] and .others.widgetshop.repo == "widgetshop" and .others.widgetshop.onBelt == [5]
  and .onBelt == [801] and (.blocked | map([.issue, .url])) == [[13, "'"$PU"'/13"]]' "the Rules part names every record, with each record's cards on the belt and blocked"
# The waiting list says where each issue a card waits on is: the step of each card on the belt reaches the Rules part.
# Bug: it said only "waiting on another card", never on which card nor how far that one had come.
q '.panels.rules.data | .beltSteps == [{issue: 801, step: "review", landed: false}] and .others.widgetshop.beltSteps == [{issue: 5, step: "build", landed: false}]' \
  "the Rules part has the step of each card on the belt"
q '[.panels.health.data.records[] | .state] == ["paused", null]' "each record's loop state (as its control record says) reaches the health part"
# #34 the control record holds and #35 a rule skips both depend on open #20, beside unheld #32: the snapshot's
# queue.waiting lists #32 alone, #34's held entry has its waitsFor, and open.held gives both waits (issue 383). Bug:
# a held issue with a Depends on line left the Held bay and showed under "Waiting on a card", as if queued; or, out of
# waiting, sat in Held with nothing saying what it waits on, or (the rule-skipped #35) was in no bay at all.
answer "$(jq -c '.queue.holding += [{issue: 34, title: "Held and waits", waitsFor: [20]}] | .queue.skipped += [{issue: 35, title: "Skipped and waits", rule: "area:infra"}]
  | .control.held += [34]
  | .open.held += [{issue: 34, title: "Held and waits", reasons: [{kind: "you"}, {kind: "waits", waitsFor: [20]}]}, {issue: 35, title: "Skipped and waits", reasons: [{kind: "rule", rule: "area:infra"}, {kind: "waits", waitsFor: [20]}]},
    {issue: 37, title: "Landed, not pushed", reasons: [{kind: "card", step: "landed", card: "c9-37", notPushed: true}]}]' <<<"$P")" \
  "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.queue.data.waiting | map([.issue, .waitsFor]) == [[32, [20]]]' "the Queue lists under waiting the snapshot's waiting issue alone; a held or skipped one with a Depends on line is not there"
# Issue 875. Bug: with push off, #37 (its card landed, not pushed) was counted as held, so the Queue said "Holds keep
# N issues back" for an issue that is done and waits only for the push.
q '.panels.queue.data | .held == 5 and .byRepo.sample.held == 4' "the Queue's held count leaves out an open issue whose card landed and is not pushed"
q '.panels.belt3d.data.queue | (.waiting | map([.issue, .waitsFor])) == [[32, [20]]] and (.held | map([.issue, .waitsFor])) == [[30, []], [34, [20]], [35, [20]]]' \
  "Belt 3D keeps a held or rule-skipped issue with a Depends on line in Held with what it waits on, never under Waiting on a card"
q '.panels.rules.data.waits | map([.issue, .waitsFor]) == [[32, [20]], [34, [20]], [35, [20]]]' \
  "the Rules waiting list still has the held and the skipped issue that wait, which the snapshot's waiting leaves out"
) & started cards

# The collect of the cards above, which the machine's first checks read.
( fresh machine
( cards_fixture
answer "$P" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
# --- the machine's one Conveyor over both projects, each project on its own, and each Foreman ---
# Bug: two projects on one machine reached the page as two unrelated loops: nothing said the machine's cap, how many
# of its slots both hold together, or that the machine itself was paused; a project's pause could not be told from
# the machine's; and a Foreman, a group's or a project's, was nowhere in the data.
# The snapshots above are from before health named the machine: no machine cap is known, so the slots in force are
# both projects' own caps together (3 and 2), the slots in use are the cards on both belts, and the cost is both
# projects' together.
q '.panels.machine.data | .state == "running" and .cap == 5 and .used == 2 and .todayUsd == 4.25 and .repos == ["sample", "widgetshop"]' \
  "the machine: both projects' cards holding a slot, of both projects' caps, and both projects' cost today, summed"
q '.panels.machine.data.projects[0] | .repo == "sample" and .state == "paused" and .mode == "pause" and .reason == "the loop says why" and .cap == 3 and .guard == 90 and .used == 1
  and (.needs | map([.repo, .issue, .url])) == [["sample", 12, "'"$PU"'/12"], ["sample", 13, "'"$PU"'/13"], ["sample", 14, "'"$PU"'/14"]] and (.belt | map([.issue, .step])) == [[801, "review"]]
  and (.queue | map(.issue)) == [20] and (.held | map(.issue)) == [30] and (.waiting | map([.issue, .title])) == [[32, "Second half"]]
  and .order == [] and .rules.never == ["area:infra"]
  and .models == {builder: {model: "claude-x", effort: "medium"}, reviewer: null, judge: {on: true, model: "claude-j", effort: "high"}} and .landedToday == 1 and .todayUsd == 3.75' \
  "a project's section: its own state, cap, guard (the percent its paused-by-guard line names) and slots, its lists with its own links, its rules, its models and its judge"
q '.panels.machine.data.projects[1] | .repo == "widgetshop" and .state == null and .mode == null and .cap == 2 and .guard == null and .used == 1 and (.belt | map([.issue, .url])) == [[5, "'"$CU"'/5"]]
  and .queue == null and .held == null and .waiting == null and .order == null and .rules == null and .models == null and .todayUsd == 0.5' \
  "the other project is its own section: a list or record its snapshot does not give is null, never the first project's and never empty"
q '.panels.belt.data | .cap == 5 and .building == null and .byRepo == {sample: {cap: 3, building: null}, widgetshop: {cap: 2, building: null}}' "the belt carries each project's own cap beside the sum, for the page filtered to one project"
q '.panels.queue.data.byRepo == {sample: {held: 2}, widgetshop: {held: 1}}' "the queue carries each project's own held count beside the sum"
# The host file here names no Foreman group and no state folder holds a mark: each project has its own Foreman line,
# and each says no session holds the role.
q '.panels.machine.data | .foremenError == null and (.foremen | map([.projects, .group, .held, .since, .lastWakeAt, .waiting]))
  == [[["sample"], false, false, null, null, []], [["widgetshop"], false, false, null, null, []]]' "a project with no Foreman has a line that says so"
# The machine's settings, as every record's health names them: the cap, and the slots both projects hold of it. A card
# that landed and waits for its push holds no slot. One project paused by its own record leaves the other, and the
# machine, running.
MC='{"cap": 10, "paused": false}'
C3=$(jq -c '.belt += [.belt[0] + {card: "c4-6", issue: 6}, .belt[0] + {card: "c4-8", issue: 8}] | .health.state = "running" | .health.loop = true | .control = {mode: "run", order: [9]}' <<<"$C")
with_machine() { jq -c --argjson m "$1" '.health.machine = $m' <<<"$2"; } # <machine> <snapshot>
PUSHING='[{"card": "c0-98", "issue": 98, "title": "Landed, being pushed", "step": "push", "stepAt": "'"$(ago 60)"'", "landed": true, "usd": 1, "reading": true}]'
# A snapshot of an engine from before issue 346 still names the machine's load limit (20) and its cores and load.
ML=$(jq -c '.maxLoad = 20' <<<"$MC")
answer "$(with_machine "$ML" "$(jq -c --argjson l "$PUSHING" '.belt += $l | .health.machineNow = {cores: 16, load: 31.5} | .health.steer = false | .health.cores = {reserved: [14, 15], slots: 14, unavailable: null} | .tests = {files: [{file: "a.test.sh", cpu: 3, runs: [{cpu: 3, card: "c5-12"}, {cpu: 2, card: "odd"}],
    failures: [{card: "c6-13", issue: 13, verdict: "card", cases: ["one"]}],
    optimize: [{issue: 70, time: "2026-11-01T00:00:00Z", state: "landed", sha: "abc1234", fix: "sped up", into: [], before: 10, after: 4, since: 3.5, sinceRuns: 2},
      {issue: 71, state: "open"}, {issue: 72, state: "open"}]}]} | .open.issues = [{issue: 71}]
  | .testActions = {limit: 900, actions: [{id: "0123456789ab", action: "judge", file: "a.test.sh", state: "running", text: "first words"}], allowed: {claude: ["m1", "m2"]}}
  | .control.tests = {cli: "claude", model: "m1", effort: "high"} | .testMap = {state: "none", tool: "V8 coverage", build: null} | .drift = {before: {cards: 5}, after: {cards: 2}, small: ["after"]}
  | .bench = {presets: [1, 5, 20, 50], live: null}
  | .modelSettings = {judge: {clis: {claude: {models: ["m1"], efforts: ["high"]}}}}' <<<"$P")")" "$P_URL" 1794000000 "$(with_machine "$ML" "$C3")" "$C_URL" 0
run
# Issue 346: the machine room (and its Load limit) is removed, so no project's Tests part carries the machine's load
# limit, cores or load, even from a snapshot that still names them. Each project's Tests part holds its own snapshot's
# test files, never another's; each run links to its card's issue (the number that ends the card id), and a card id
# with no number links nowhere.
q '.panels.tests.data | (has("machine") | not) and (.others.widgetshop | has("machine") | not)
  and (.tests.files | map([.file, .cpu])) == [["a.test.sh", 3]] and .others.widgetshop.tests == null
  and (.tests.files[0].runs | map([.card, .issue, .url])) == [["c5-12", 12, "'"$PU"'/12"], ["odd", null, null]]' \
  "the Tests part names no machine load limit, and each project's own test files, each run with its card's link"
# Issue 347: steer (Card work yields to you) is removed, so the Rules part carries no steer, even from a snapshot of
# an engine before it that still says it is off.
q '.panels.rules.data | has("steer") | not' "the Rules part carries no steer"
# Issue 196: the Rules tab shows the cores kept for the user and the test slots left, the machine's, from whichever
# record's health names them; a Rules part without them could not show the setting at all.
q '.panels.rules.data.cores == {reserved: [14, 15], slots: 14, unavailable: null}' "the Rules part carries the machine's kept cores and slots left"
# Bug (#74): a file's Optimize issues reached the Tests page with no link. Each keeps its state and the proof's before
# and after CPU s, and gets its issue's url. And one no card took, closed on GitHub (#72 is not among the open issues:
# the Board's Close its issue as done), still showed as open.
q '.panels.tests.data.tests.files[0].optimize | map([.issue, .state, .sha, .before, .after, .url])
  == [[70, "landed", "abc1234", 10, 4, "'"$PU"'/70"], [71, "open", null, null, null, "'"$PU"'/71"], [72, "closed", null, null, null, "'"$PU"'/72"]]' \
  "the Tests part names a file's landed Optimize issue, its state, commit, before and after CPU s, with its issue's link, and a closed one as closed"
# Bug (#188): a file's failures reached the Tests page with no link, so "caught 1 card change" could not open the card.
q '.panels.tests.data.tests.files[0].failures | map([.card, .verdict, .url]) == [["c6-13", "card", "'"$PU"'/13"]]' \
  "the Tests part gives each failure of a file its issue's link"
# Bug (#521): the Tests page's actions had no action, text, Tests model, CLI or flaky case to show. Each project's own reach it.
# Bug (#594): nor the pack's models by CLI, so a CLI that lists none (Claude Code) offered no model.
q '.panels.tests.data | (.testActions.actions | map([.id, .text])) == [["0123456789ab", "first words"]] and .testActions.limit == 900
  and .testActions.allowed == {claude: ["m1", "m2"]}
  and .control.tests == {cli: "claude", model: "m1", effort: "high"} and .clis == {claude: {models: ["m1"], efforts: ["high"]}}
  and (.flaky | map(.case)) == ["b.test: flaky", "c.test: other"] and .others.widgetshop.testActions == null and .others.widgetshop.clis == null' \
  "the Tests part holds its project's test actions with their text, the host's CLIs and the flaky cases"
# Bug (#178): the Tests page had no test map to show, nor a tool to build it with. Each project's own reaches it.
q '.panels.tests.data | .testMap == {state: "none", tool: "V8 coverage", build: null} and .others.widgetshop.testMap == null' \
  "the Tests part holds its project's test map part"
# Bug (#237): the Board had no drift watch to show beside the benchmark results. Each project's own reaches the
# Benchmarks tab's part (#326: a tab of its own, so a part of its own).
q '.panels.bench.data | .repo == "sample" and .drift == {before: {cards: 5}, after: {cards: 2}, small: ["after"]} and .others.widgetshop.drift == null' \
  "the Benchmarks part holds its project's latest drift watch"
# Bug (#236): the Benchmarks tab had no SWE-bench runs to show. Each project's own reaches it, and the Tests part no
# longer carries them.
q '.panels.bench.data | .bench == {presets: [1, 5, 20, 50], live: null} and .others.widgetshop.bench == null and .repos == ["sample", "widgetshop"]' \
  "the Benchmarks part holds its project's run in progress and versions"
# Bug: Plan's guard warning kept an old history after `control guard` changed, as no run changed: the part carries the
# control record's guard, which the tab's history read stamps.
q '.panels.bench.data | .guard == 90 and (.others.widgetshop | has("guard"))' "the Benchmarks part holds its project's guard"
q '.panels.tests.data | has("bench") or has("drift") | not' "the Tests part no longer carries the Benchmarks"
q '.panels.rules.data | has("machine") | not' "the Rules part no longer carries the load limit: the Tests page has it"
q '.panels.machine.data | .state == "running" and .cap == 5 and .used == 4 and (.projects | map([.repo, .state, .mode, .used, .cap])) == [["sample", "paused", "pause", 1, 3], ["widgetshop", "running", "run", 3, 2]]' \
  "one machine head: 4 of 5, the slots of both projects (3 and 2) under the machine's 10; sample's own pause leaves widgetshop and the machine running"
q '.panels.machine.data.projects[1].order == [9]' "a project's pinned order is its own record's"
# Issue 413: the machine bar and Belt 3D's deck give one slots figure, 4 of 5: the cards holding a machine slot (the
# landed card being pushed holds none) of the slots in force. The Belt part ("On the belt" tile) counts against the card
# cap; here no card waits or lands and no machine cap is under the card cap, so it reads 4 of 5 too.
# The bug: the machine bar said 4 of 10 (the machine cap, which the projects' own 3 and 2 never reach) beside 4 of 5.
q '[(.panels.belt3d.data.deck | [.used, .cap]), (.panels.machine.data | [.used, .cap]),
    (.panels.belt.data | [([.cards[] | select(.landed != true)] | length), .cap])] == [[4, 5], [4, 5], [4, 5]]' \
  "the machine bar and Belt 3D's deck give one slots figure, and the On the belt tile agrees where no card waits or lands"
# Bug: a judge turned off read as no judge setting at all (`false // null` is null), and the project list said
# "judge not read" where the owner had said off. Off is off, whatever model the judge's settings still name.
CJ=$(jq -c '.control.judgeOn = false | .modelSettings = {judge: {model: "claude-j", effort: "high"}}' <<<"$C3")
answer "$P" "$P_URL" 1794000000 "$CJ" "$C_URL" 0
run
q '.panels.machine.data.projects[1].models.judge == {on: false}' "a project whose judge is off says off, never not read"
# The whole machine paused (the host file's mode): the machine says so; no project's own state is rewritten.
# Its cap is 4 here, under the projects' 3 and 2: the slots in force are the machine's 4 in the machine bar and Belt
# 3D's deck; the Belt part keeps the card cap, 5.
MP=$(jq -c '.paused = true | .cap = 4' <<<"$MC")
# widgetshop's 3 cards: one lands (offCap, issue 1538) and one waits on another card (health.waitingCount 1). The card cap
# leaves out the landing card, but the machine's own cap does not: the loop sends the landing card to the machine's gate
# (room(), conveyor/lib/run.sh) and leaves out the waiting one. So the machine and Belt 3D's deck count 1 + 2 slots
# in use: never 4 (the waiting card counted) and never 1 + 1 (the landing card left out, which showed a free slot on a
# full machine). widgetshop's project row counts its cards against its own cap (the waiting one in, the landing one
# out): 2 too, by another count.
answer "$(with_machine "$MP" "$P")" "$P_URL" 1794000000 "$(with_machine "$MP" "$(jq -c '.health.waitingCount = 1 | .belt[2].offCap = true' <<<"$C3")")" "$C_URL" 0
run
q '.panels.machine.data | .state == "paused" and (.projects | map(.state)) == ["paused", "running"]' "a paused machine is paused; each project's state stays its own record's"
q '[.panels.machine.data.used, (.panels.machine.data.projects | map(.used)), .panels.belt3d.data.deck.used] == [3, [1, 2], 3]' \
  "a card that only waits on another card holds no slot in the machine's and the deck's count, and a landing card (offCap) holds one; the project's row counts its cards against its own cap"
q '[.panels.machine.data.cap, .panels.belt3d.data.deck.cap] == [4, 4]' "a machine cap under the projects' own caps together is the slots in force, the same in the machine bar and Belt 3D"
# Bug: the Belt part (the On the belt tile, the Belt panel) paired the cards counted against the card cap with the machine's
# cap, "2 of 1" with a project cap of 3 and a machine cap of 1; the Machine page's project row paired the machine's count
# (a waiting card left out) with the project's own cap, "1 of 3". The cap beside the count is the card cap (the projects'
# own together; the project's own in its row), and the count is the cards counted against it, a waiting card too.
q '[.panels.belt.data.cap, .panels.belt.data.byRepo.widgetshop.cap, (.panels.machine.data.projects | map([.repo, .cap, .used]))] == [5, 2, [["sample", 3, 1], ["widgetshop", 2, 2]]]' \
  "a machine cap under the projects' own caps leaves the Belt part's cap the card cap, and a project's row counts its cards against its own cap"
answer "$(with_machine "$MP" "$P")" "$P_URL" 1794000000 "$(with_machine "$MP" "$(jq -c '.health.waitingCount = 1' <<<"$C3")")" "$C_URL" 0
run
q '[.panels.machine.data.used, (.panels.machine.data.projects | map(.used)), (.panels.machine.data.projects | map(.cap)), .panels.belt.data.cap] == [3, [1, 3], [3, 2], 5]' \
  "a waiting card holds no machine slot (used 1 + 2) but counts against its project's own cap (3 cards), and the Belt part's cap stays the card cap, not the machine's 4"
# Belt 3D's deck reads out the machine's state as the machine part has it (its LOOP readout) (issue 393): a deck that
# said LIVE on a paused machine would lie.
q '.panels.belt3d.data.deck | {host, state} == {host: "devbox", state: "paused"}' "Belt 3D's deck: the paused machine"
answer "$(with_machine '{"unread": true}' "$P")" "$P_URL" 1794000000 "$(with_machine '{"unread": true}' "$C3")" "$C_URL" 0
run
q '.panels.machine.data | .state == "not read" and .cap == 5' "a host file the host cannot read: the machine's state is not read, never running; the projects' own caps still hold"
q '.panels.belt3d.data.deck | {host, state} == {host: "devbox", state: "not read"}' "Belt 3D's deck: the state not read"
answer "$(jq -c '.health.loop = false' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.machine.data.state == "stopped"' "no project's loop running: the machine is stopped"
q '.panels.belt3d.data.deck.state == "stopped"' "Belt 3D's deck: no loop running is stopped"
# Metrics side by side: each project's 7 days, then the machine's. Its time to land is the median over both
# projects' landed cards (100, 300, 500: 300), never the mean of the two medians (200, 500: 350); a blocked card
# has none.
PM=$(jq -c '.metrics.week = {landed: 2, leadSec: {p50: 200, p90: 300}} | .metrics.cards = [{card: "c5-1", issue: 1, state: "landed", metrics: {leadSec: 100}}, {card: "c5-2", issue: 2, state: "landed", metrics: {leadSec: 300}}]' <<<"$P")
CM=$(jq -c '.metrics = {week: {landed: 1, leadSec: {p50: 500, p90: 500}}, cards: [{card: "c6-1", issue: 1, state: "landed", metrics: {leadSec: 500}}, {card: "c6-2", issue: 2, state: "blocked", metrics: {leadSec: null}}]}' <<<"$C")
answer "$PM" "$P_URL" 1794000000 "$CM" "$C_URL" 0
run
q '.panels.metrics.data.compare == {projects: [{repo: "sample", landed: 2, leadSec: 200, usd: 10, usdLeftOut: 0, usdEstimate: 0}, {repo: "widgetshop", landed: 1, leadSec: 500, usd: 4, usdLeftOut: 0, usdEstimate: 0}],
  machine: {landed: 3, leadSec: 300, usd: 14, usdLeftOut: 0, usdEstimate: 0}}' \
  "metrics: each project and the machine side by side, the machine's time to land over every landed card"
answer "$PM" "$P_URL" 1794000000 "$(jq -c '.cost.week = null' <<<"$C")" "$C_URL" 0
run
q '.panels.metrics.data.compare.machine == {landed: null, leadSec: null, usd: null, usdLeftOut: 0, usdEstimate: 0}' "a project that measured nothing, or has an unpriced week, leaves the machine's figure unknown, never the sum of the rest"
# Bug: the machine's median left out a card whose issue was already fixed (closed), which each project's own median
# counts as landed: one project with a landed card (100) and a closed one (300) said 200 for the project and 100 for
# the machine. A card closed while it was blocked landed nothing: it has no time to land, and counts in neither.
PC=$(jq -c '.metrics.week = {landed: 2, leadSec: {p50: 200, p90: 300}} | .metrics.cards = [{card: "c5-1", issue: 1, state: "landed", metrics: {leadSec: 100}}, {card: "c5-2", issue: 2, state: "closed", metrics: {leadSec: 300}},
  {card: "c5-3", issue: 3, state: "closed", metrics: {leadSec: null}}]' <<<"$P")
answer "$PC" "$P_URL" 1794000000 "$(jq -c '.metrics = {week: {landed: 0, leadSec: null}, cards: []}' <<<"$C")" "$C_URL" 0
run
q '.panels.metrics.data.compare | .projects[0].leadSec == 200 and .machine.leadSec == 200' "the machine's time to land counts an already-fixed card, as the project's own median does"
# Bug: the side-by-side cost and a project section's cost today gave the priced steps' dollars as if they were the
# whole: the steps each leaves out for having no price were dropped, so $5.00 hid an unpriced step.
answer "$(jq -c '.cost += {todayLeftOut: 2, weekLeftOut: 3}' <<<"$P")" "$P_URL" 1794000000 "$(jq -c '.cost += {todayLeftOut: 0, weekLeftOut: 1}' <<<"$C")" "$C_URL" 0
run
q '.panels.metrics.data.compare | (.projects | map(.usdLeftOut)) == [3, 1] and .machine.usdLeftOut == 4' "the side-by-side cost of each project and of the machine names the steps it leaves out"
q '.panels.machine.data.projects | map(.todayLeftOut) == [2, 0]' "a project section's cost today names the steps it leaves out"
# Bug: Cost filtered to one project had nothing but the sums of every project to show: each project's own figures
# come beside them.
q '.panels.cost.data.cards.byRepo == {sample: {todayUsd: 3.75, weekUsd: 10, perLandedUsd: 2.5, landedAfter: {"1": 0, "2": 1, "3": 0, more: 0}, unpricedSteps: 0, todayLeftOut: 2, weekLeftOut: 3, perLandedLeftOut: 0,
    todayEstimate: 0, weekEstimate: 0, perLandedEstimate: 0},
  widgetshop: {todayUsd: 0.5, weekUsd: 4, perLandedUsd: 0.5, landedAfter: {"1": 3, "2": 0, "3": 0, more: 0}, unpricedSteps: 1, todayLeftOut: 0, weekLeftOut: 1, perLandedLeftOut: 0,
    todayEstimate: 0, weekEstimate: 0, perLandedEstimate: 0}}' \
  "cost carries each project's own figures beside the sums, for the page filtered to one project"
# Bug: a project's section counted only its blocked and waiting cards as Needs you: an issue waiting for the owner's
# yes before its build was left out, so the section said "Needs you (0)" while the Needs you panel listed it.
answer "$P" "$P_URL" 1794000000 "$(jq -c '.needsYou.before = [{issue: 40, title: "New price list", section: "Customers see new prices.", since: "2026-11-12T08:00:00Z"}]' <<<"$C")" "$C_URL" 0
run
q '.panels.machine.data.projects[1].needs | map([.repo, .card, .issue, .title, .url]) == [["widgetshop", null, 40, "New price list", "'"$CU"'/40"]]' "a project's Needs you has its issues waiting for the yes before their build"
# Bug: a follow-up filed held because it changes a pipeline file was in no list the owner reads: held, and never seen.
answer "$P" "$P_URL" 1794000000 "$(jq -c '.needsYou.pipeline = [{issue: 41, title: "[P1] conveyor/conveyor.sh:9 a slow gate", cost: "not assessed", parent: 30, since: "2026-11-12T08:00:00Z"}]' <<<"$C")" "$C_URL" 0
run
q '.panels.needs.data.cards.pipeline | map([.repo, .issue, .cost, .parent, .url]) == [["widgetshop", 41, "not assessed", 30, "'"$CU"'/41"]]' "a held pipeline follow-up is in Needs you with its repo, its cost line, its parent and its link"
q '.panels.machine.data.projects[1].needs | map([.repo, .issue]) == [["widgetshop", 41]]' "a project's Needs you counts its held pipeline follow-ups"
# Bug (#617): the page and the Foreman watcher kept two lists of the kinds of Needs you. The page is sent the one list
# (dashboard_needs.json) and each kind's entries, read from the snapshot field the list names.
q '.panels.needs.data | .kinds == '"$(jq -c . "$SOURCE/.claude/scripts/dashboard_needs.json")"' and (.entries.pipeline | map([.repo, .issue, .title, .url]))
  == [["widgetshop", 41, "[P1] conveyor/conveyor.sh:9 a slow gate", "'"$CU"'/41"]] and .entries.farDeps == []' "Needs you is sent the shared list of its kinds and each kind's entries"
# Bug (issue 605): an issue waiting on another repository's issue that gh cannot read was in no list the owner reads.
answer "$P" "$P_URL" 1794000000 "$(jq -c '.needsYou.farDeps = [{issue: 42, title: "Use the new tool", ref: "other/repo#600", line: "Depends on: other/repo#600", reason: "no access"}]' <<<"$C")" "$C_URL" 0
run
q '.panels.needs.data.cards.farDeps | map([.repo, .issue, .ref, .line, .reason, .url]) == [["widgetshop", 42, "other/repo#600", "Depends on: other/repo#600", "no access", "'"$CU"'/42"]]' "a dependency that cannot be read is in Needs you with its line and why"
q '.panels.machine.data.projects[1].needs | map([.repo, .issue]) == [["widgetshop", 42]]' "a project's Needs you counts its dependencies that cannot be read"
# Bug (#1677): an issue waiting on one whose card was shut was in Needs you on the Overview, but left out of the
# project's Needs you on the Machine panel.
answer "$P" "$P_URL" 1794000000 "$(jq -c '.needsYou.shutDeps = [{issue: 43, title: "Use the new tool", dependency: 44, card: "c0-44", since: "2026-11-12T08:00:00Z", reason: "#43 waits for #44, but the owner shut its card c0-44"}]' <<<"$C")" "$C_URL" 0
run
q '.panels.machine.data.projects[1].needs | map([.repo, .issue]) == [["widgetshop", 43]]' "a project's Needs you counts its waits on a dependency whose card was shut (needsYou.shutDeps: #43 waits on #44, card c0-44 shut)"
) & PIECES+=($!)
( setup machine-2; cards_fixture
# The Foremen, read from this machine's state folders. A group of the host file's foreman.groups is one Foreman, in
# its first project's folder (the host file's stateDir for the host's own checkout): shown once with both projects,
# with when its session claimed the role, when it was last woken and the wakes still owed to it.
cp "$MAIN/conveyor/host.json" "$T/host.before"
FM=$T/fstate/foreman; mkdir -p "$FM/pending"
echo 'sess-1 2026-11-12T08:00:00Z' > "$FM/session"
printf 'Conveyor: sample: blocked: #13\n#13 is blocked since then\n' > "$FM/last-wake.txt"; touch -d '2026-11-12T09:30:00Z' "$FM/last-wake.txt"
printf 'Conveyor: widgetshop: needs the owner'"'"'s yes: #5\n#5 needs it\n' > "$FM/pending/20261112T100000Z-1-a.wake"
printf 'Limit: 91%% of the week used\n' > "$FM/pending/20261112T100100Z-1-b.wake"; : > "$FM/pending/.put.half"
# Issue 139: the plugin problems it noted (conveyor/foreman/stop.sh, one "- " line each under a heading) are counted,
# with the file, and Health has them. Bug it catches: a noted plugin problem the Board never showed.
printf '# Plugin problems\n\n- 2026-11-12T09:00:00Z · card #13 · a · evidence: -\n- 2026-11-12T09:10:00Z · card - · b · evidence: -\n' > "$FM/plugin-bugs.md"
jq --arg s "$T/fstate" '.stateDir = $s | .foreman = {groups: [["sample", "widgetshop", "gone"]]}' "$T/host.before" > "$MAIN/conveyor/host.json"
answer "$P" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.machine.data.foremen == [{projects: ["sample", "widgetshop"], group: true, held: true, since: "2026-11-12T08:00:00Z", lastWakeAt: "2026-11-12T09:30:00Z",
  waiting: ["Conveyor: widgetshop: needs the owner'"'"'s yes: #5", "Limit: 91% of the week used"], pluginBugs: 2, pluginBugsFile: "'"$FM"'/plugin-bugs.md",
  pluginBugsUrl: "plugin-bugs/sample.txt", pluginNotes: [
    {at: "2026-11-12T09:00:00Z", card: "#13", text: "a · evidence: -", line: "- 2026-11-12T09:00:00Z · card #13 · a · evidence: -"},
    {at: "2026-11-12T09:10:00Z", card: "-", text: "b · evidence: -", line: "- 2026-11-12T09:10:00Z · card - · b · evidence: -"}]}]' "a grouped Foreman is one line with both its projects (a name no record has passed over), its claim, its last wake, what waits on it and the plugin problems it noted"
# Bug it catches: the notes were under the first project alone, so picking widgetshop (the project filter keeps the
# rows whose repo it names) hid its Foreman's notes. Each project of the group has them.
q '.panels.health.data.pluginBugs | map(.repo) == ["sample", "widgetshop"] and all(.projects == ["sample", "widgetshop"] and .count == 2
  and .file == "'"$FM"'/plugin-bugs.md" and .url == "plugin-bugs/sample.txt")' "Health has the plugin problems the Foreman noted, under each of its projects, with the Board's copy"
# Issue 1042: the Plugin problems pane lists each note with its time, card and text. Bug it catches: Health had only
# the count, so the pane had no note to show or to dismiss.
q '.panels.health.data.pluginBugs[0].notes | map([.at, .card, .text]) == [["2026-11-12T09:00:00Z", "#13", "a · evidence: -"], ["2026-11-12T09:10:00Z", "-", "b · evidence: -"]]' \
  "Health has each note the Foreman noted, with its time, card and text"
# Bug it catches: the link was file://, which a browser does not open from the https Board; the copy is served beside the page.
cmp -s "$FM/plugin-bugs.md" "$OUT/plugin-bugs/sample.txt" || fail "the Board's folder has a copy of the notes, which the page links to"
# Bug it catches: outside the plugin's own repository stop.sh adds the filed line as a row and keeps the price note, so
# Health listed the note too and gave it File on GitHub again. Only the note of a model a filed line names goes; a
# note for another model, and the filed line itself, stay.
PX='- 2026-11-12T09:00:00Z · card - · No built-in price for claude-new-7: it is not priced · evidence: -'
printf '# Plugin problems\n\n%s\n- 2026-11-12T09:05:00Z · card - · No built-in price for claude-new-8: it is not priced · evidence: -\n- 2026-11-12T09:10:00Z · card - · No built-in price for claude-new-7: it is not priced, filed as #21 · evidence: -\n' "$PX" > "$FM/plugin-bugs.md"
run
q '.panels.machine.data.foremen[0] | .pluginBugs == 2 and (.pluginNotes | map(.text) == ["No built-in price for claude-new-8: it is not priced · evidence: -", "No built-in price for claude-new-7: it is not priced, filed as #21 · evidence: -"])' \
  "a price note a filed line names is listed or counted, or the note of another model or the filed line is not"
rm -f "$FM/plugin-bugs.md"
# No group: the same folder is sample's own Foreman, and widgetshop has none. A mark emptied (the role turned off)
# is no Foreman either. Groups that name a project twice are not understood: each project has its own.
jq --arg s "$T/fstate" '.stateDir = $s' "$T/host.before" > "$MAIN/conveyor/host.json"
run
q '.panels.machine.data.foremen | map([.projects, .group, .held]) == [[["sample"], false, true], [["widgetshop"], false, false]]' "each project its own Foreman: one holds the role, the other has none"
[ ! -e "$OUT/plugin-bugs" ] || fail "notes that are gone leave no copy in the Board's folder"
# Bug: the host file's own checkout was told by its main as written, while the engine follows links: a record that
# names that checkout through a link keeps its Foreman in the stateDir, and the page read the link's conveyor/state
# and said the project has no Foreman.
mkdir -p "$T/real-main"; ln -s "$T/real-main" "$T/link-main"
jq --arg s "$T/fstate" --arg m "$T/real-main" --arg l "$T/link-main" '.stateDir = $s | .main = $m | .records[0].main = $l' "$T/host.before" > "$MAIN/conveyor/host.json"
run
q '.panels.machine.data.foremen | map([.projects, .held, .since]) == [[["sample"], true, "2026-11-12T08:00:00Z"], [["widgetshop"], false, null]]' "a record that names the host file's own checkout through a link has its Foreman read from the stateDir"
: > "$FM/session"
jq --arg s "$T/fstate" '.stateDir = $s | .foreman = {groups: [["sample", "widgetshop"], ["widgetshop"]]}' "$T/host.before" > "$MAIN/conveyor/host.json"
run
q '.panels.machine.data.foremen | map([.projects, .held, .since]) == [[["sample"], false, null], [["widgetshop"], false, null]]' "a mark turned off is no Foreman; groups naming a project twice group nothing"
# Bug (issue 454): with the belt on an ssh host, a record's main is the host's path, not on this machine; the Foreman
# runs here in a checkout whose origin is that repository and marks its claim there, and the page read only under
# main and said "No Foreman". sample's checkout holds its ledger and is found by it; widgetshop's lies beside the
# Board's own checkout.
here() { git init -q -b main "$1" && git -C "$1" remote add origin "$2" && mkdir -p "$1/conveyor/state/foreman" && echo "$3" > "$1/conveyor/state/foreman/session"; }
here "$T/away/sample-here" "https://$GH/example/sample.git" 'sess-s 2026-11-12T07:00:00Z'
mkdir -p "$T/away/sample-here/.claude/metrics"; : > "$T/away/sample-here/.claude/metrics/decisions.jsonl"
here "$T/widgetshop-here" "https://$GH/example/widgetshop" 'sess-w 2026-11-12T06:00:00Z'
jq --arg s "$T/fstate" --arg l "$T/away/sample-here/.claude/metrics/decisions.jsonl" '.stateDir = $s | .records[0].ledger = $l' "$T/host.before" > "$MAIN/conveyor/host.json"
# Bug (#1115): there, the loop notes a model with no built-in price in the host's Foreman folder, and Plugin problems,
# which reads this machine's, never showed it. The host's snapshot gives the note (priceNotes), and the Board adds it
# here once; a line not of the loop's form (another card's, two lines in one) is not added.
PN='- 2026-11-12T09:00:00Z · card - · No built-in price for claude-new-9: the belt runs or offers this Claude model · evidence: -'
answer "$(snap "$(jq -cn --arg n "$PN" '{priceNotes: [$n, "- 2026-11-12T09:00:00Z · card #3 · No built-in price for claude-z: y", "\($n | sub("new-9"; "new-8"))\n- x"]}')")" \
  "$P_URL" 1794000000 "$(snap)" "$C_URL" 0
run
q '.panels.machine.data.foremen | map([.projects, .held, .since]) == [[["sample"], true, "2026-11-12T07:00:00Z"], [["widgetshop"], true, "2026-11-12T06:00:00Z"]]' "with ssh and a main not on this machine, the Foreman is read from the checkout here whose origin is that repository"
SN=$T/away/sample-here/conveyor/state/foreman/plugin-bugs.md
[ "$(grep '^- ' "$SN" 2>&1)" = "$PN" ] || fail "the host's note for a model with no built-in price is not in the Foreman's folder here, once: $(cat "$SN" 2>&1)"
q '.panels.health.data.pluginBugs | map([.repo, (.notes | map(.line))]) == [["sample", ["'"$PN"'"]]]' "Plugin problems does not show the host's note for a model with no built-in price"
# Dismissed here (the server takes the line out), the note does not come back from the host's snapshot.
grep -v '^- ' "$SN" > "$SN.new" && mv "$SN.new" "$SN"
run
[ -z "$(grep '^- ' "$SN")" ] || fail "a dismissed note for a model with no built-in price came back: $(cat "$SN")"
# Bug: each cycle after the first listed the model again in price-notes.txt, so the file grew every Board refresh.
[ "$(cat "${SN%/*}/price-notes.txt" 2>&1)" = claude-new-9 ] || fail "price-notes.txt does not list the added model once: $(cat "${SN%/*}/price-notes.txt" 2>&1)"
# Bug: once the host filed the note, its snapshots stopped giving it, but the copy added here stayed, so this Board
# offered File for a note already filed. A snapshot with no priceNotes (none read) takes nothing out; one that no
# longer gives the note takes the copy out, and leaves a line filed here and a line of another form.
FD="${PN/· evidence: -/filed as #7 · evidence: -}"
printf '%s\n%s\n- 2026-11-12T09:00:00Z · card #3 · other\n' "$PN" "$FD" >> "$SN"
quiet; run
[ "$(grep -c '^- ' "$SN")" = 3 ] || fail "a snapshot with no priceNotes took a note out of plugin-bugs.md: $(cat "$SN")"
# Bug (E2): the copy was written as a new file, so a plugin-bugs.md of mode 0600 became 0644 under umask 022.
chmod 600 "$SN"
answer "$(snap '{"priceNotes": []}')" "$P_URL" 1794000000 "$(snap '{"priceNotes": []}')" "$C_URL" 0
(umask 022; run) || exit 1
[ "$(grep '^- ' "$SN")" = "$FD"$'\n- 2026-11-12T09:00:00Z · card #3 · other' ] \
  || fail "with snapshots that give priceNotes [], the copied note was not the one line taken out: $(cat "$SN")"
[ "$(ls -l "$SN" | cut -c1-10)" = -rw------- ] || fail "taking the copied note out changed the mode of plugin-bugs.md: $(ls -l "$SN")"
# Bug (E1): the model stayed in price-notes.txt, so when a snapshot gave the unfiled note again (a group split for a
# refresh, the note read under another project's folder), it never came back here. Its model leaves the list too.
[ ! -s "${SN%/*}/price-notes.txt" ] || fail "the model of the note taken out is still in price-notes.txt: $(cat "${SN%/*}/price-notes.txt")"
grep -vxF -- "$FD" "$SN" > "$SN.new" && mv "$SN.new" "$SN"
answer "$(snap "$(jq -cn --arg n "$PN" '{priceNotes: [$n]}')")" "$P_URL" 1794000000 "$(snap)" "$C_URL" 0
run
[ "$(grep -c -xF -- "$PN" "$SN")" = 1 ] || fail "a note taken out came back in a snapshot and was not added again: $(cat "$SN")"
# The notes left here are taken out, so the ones below are counted alone.
grep -v '^- ' "$SN" > "$SN.new" && mv "$SN.new" "$SN"
# Bug: a note added here and then filed on the host (its snapshot names the model in priceFiled) stayed here, and
# Plugin problems kept offering to file it again. A note filed here stays.
PN6=${PN//new-9/new-6} PN5=${PN//new-9/new-5}
answer "$(snap "$(jq -cn --arg a "$PN6" --arg b "$PN5" '{priceNotes: [$a, $b]}')")" "$P_URL" 1794000000 "$(snap)" "$C_URL" 0
run
sed -i "s/new-5: .*/new-5: x filed as #12 · evidence: -/" "$SN"
# Bug (E1): a snapshot that only stops giving a note (the project that noted it left the group, so the host reads
# another folder, where the note is not) took the copy here out, though the note is still open on the host. A snapshot
# that gives priceFiled tells filed notes apart, so only a note it names as filed is taken out.
answer "$(snap '{"priceNotes": [], "priceFiled": []}')" "$P_URL" 1794000000 "$(snap)" "$C_URL" 0
run
grep -qxF -- "$PN6" "$SN" || fail "a snapshot that no longer gives the note for claude-new-6, and names it not filed, took it out: $(cat "$SN")"
answer "$(snap '{"priceNotes": [], "priceFiled": ["claude-new-6", "claude-new-5"]}')" "$P_URL" 1794000000 "$(snap)" "$C_URL" 0
run
[ "$(grep -c '^- ' "$SN")" = 1 ] && grep -q 'new-5: x filed as #12' "$SN" \
  || fail "with priceFiled naming both models, the unfiled note added here is not taken out, or the one filed here is: $(cat "$SN")"
q '.panels.health.data.pluginBugs | map([.repo, (.notes | length)]) == [["sample", 1]]' "Plugin problems still shows a note filed on the host"
# Bug (R10): with the Board's checkout and the build machine's at the same path, the record's main exists here too, and
# the host's note was never added: the import ran only for a main not on this machine. ssh names the host.
mkdir -p "$T/same/conveyor/state/foreman"
PN2=${PN//new-9/new-7}
jq --arg m "$T/same" '.records[0].main = $m | del(.stateDir)' "$T/host.before" > "$MAIN/conveyor/host.json"
answer "$(snap "$(jq -cn --arg n "$PN2" '{priceNotes: [$n]}')")" "$P_URL" 1794000000 "$(snap)" "$C_URL" 0
run
[ "$(grep '^- ' "$T/same/conveyor/state/foreman/plugin-bugs.md" 2>&1)" = "$PN2" ] \
  || fail "with ssh and a main that is also a path here, the host's note for a model with no built-in price is not in plugin-bugs.md: $(cat "$T/same/conveyor/state/foreman/plugin-bugs.md" 2>&1)"
# Without ssh the folder is read under main as before, even when a checkout here has the repository as its origin.
# With no ssh target Conveyor is read on this machine, where /srv/main is no checkout, so it gives no snapshot (the
# machine panel is null) and the cycle's kept Foremen part is read.
mkdir -p "$T/wmain/conveyor/state/foreman"; echo 'sess-m 2026-11-12T04:00:00Z' > "$T/wmain/conveyor/state/foreman/session"
jq --arg l "$T/away/sample-here/.claude/metrics/decisions.jsonl" --arg w "$T/wmain" 'del(.ssh) | .records[0].ledger = $l | .records[1].main = $w' "$T/host.before" > "$MAIN/conveyor/host.json"
run
jq -e '.foremen | map([.projects, .held, .since]) == [[["sample"], false, null], [["widgetshop"], true, "2026-11-12T04:00:00Z"]]' "$OUT/cache/part-foremen.json" >/dev/null \
  || fail "without ssh the Foreman is read under the record's main, never from a checkout matched by its origin ($(cat "$OUT/cache/part-foremen.json"))"
) & PIECES+=($!)
( setup machine-3; cards_fixture
# A card that landed on an earlier day and is still on the belt (its push fails) stays on the Board, in Building
# with its Push step and why; a card that landed today and is being pushed is in Landed today alone.
L='[{"card": "c0-99", "issue": 99, "title": "Landed yesterday", "step": "push", "stepAt": "'"$(ago 90000)"'", "landed": true, "usd": 1, "reading": true, "track": {"reason": "the pre-push hook failed"}},
  {"card": "c'"$TODAY"'T080000-7", "issue": 7, "title": "Landed one", "step": "push", "stepAt": "'"$(ago 60)"'", "landed": true, "usd": 2.5, "reading": true}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data | (.building | map([.issue, .step, .reason])) == [[99, "push", "the pre-push hook failed"]] and (.landed | map(.issue)) == [7]' "a card landed on an earlier day whose push fails is in Building; one landed today is in Landed today alone"
q '.panels.board.data | has("checkRuns") | not' "a record whose pack names no checks.progress sends no check run"
# Bug (issue 407): a landed card whose push failed and was tried again showed on the belt and in Landed today at once,
# while Needs you said only "Nothing needs you" beside Health's red "Failing". Needs you now lists each such card with
# the fix card building for it (a belt card whose parent it is), and the belt leaves out the one Landed today shows.
PF='{"steps": [{"name": "Build", "state": "done"}, {"name": "Review", "state": "done"}, {"name": "Fix", "state": "skipped"}, {"name": "Test", "state": "done"}, {"name": "Land", "state": "done"}, {"name": "Push", "state": "failed"}], "reason": "the pre-push hook failed"}'
L='[{"card": "c0-99", "issue": 99, "title": "Landed yesterday", "step": "push", "stepAt": "'"$(ago 90000)"'", "landed": true, "usd": 1, "reading": true, "track": '"$PF"'},
  {"card": "c'"$TODAY"'T080000-7", "issue": 7, "title": "Landed one", "step": "push", "stepAt": "'"$(ago 60)"'", "landed": true, "usd": 2.5, "reading": true, "track": '"$PF"'},
  {"card": "c0-62", "issue": 62, "title": "Fix the hook", "parent": 7, "step": "build", "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c'"$TODAY"'T090000-8", "issue": 8, "title": "Pushed, issue open", "step": "push", "stepAt": "'"$(ago 60)"'", "landed": true, "usd": 1, "reading": true, "track": '"$(jq -c '.reason = "GitHub did not close the issue: HTTP 502"' <<<"$PF")"'}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.needs.data.retrying | map([.repo, .issue, .fix]) == [["sample", 99, null], ["sample", 7, 62]]' "each landed card whose push failed is in Needs you's retrying, with the fix card building for it"
# Bug: a card whose push of main succeeded but whose issue GitHub did not close (track.jq marks its Push step failed)
# was called a push failing and being retried, and left the belt.
q '(.panels.needs.data.retrying | map(.issue) | index(8) == null) and (.panels.belt.data.cards | map(.issue) | index(8) != null)' "a card whose issue GitHub did not close is no failing push: not in retrying, still on the belt"
q '(.panels.belt.data.cards | map(.issue) | (index(7) == null and index(99) != null and index(62) != null)) and (.panels.landed.data.cards | map(.issue) | index(7) != null)' "a card that landed today and whose push failed is in Landed today and not on the belt; one landed earlier stays on the belt"
# Belt 3D's lane of a card in Test shows its test run's progress, and its details the steps' times and the turns of
# the step: the track's steps, at, since, tests and files and the live record's turns reach it.
# Issue 423: its records' names and times too (and nothing else of them), so its lane shows it went back a step.
T3='{"steps": [{"name": "Build", "state": "done", "sec": 30}], "at": 3, "since": "'"$(ago 120)"'", "label": "tests", "tests": {"done": 142, "of": 205, "failed": 0}, "files": {"run": 1, "of": 2}, "detail": [],
  "records": [{"name": "review 1 (NO-GO)", "state": "done", "sec": 60, "at": "'"$(ago 600)"'", "output": "a long review"}, {"name": "tests", "state": "now", "sec": null}]}'
answer "$(jq -c --argjson t "$T3" '.belt[0] += {step: "tests", track: $t, live: {turns: 7, lastOutputAt: null}}' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.belt3d.data.belt | .[0] | .turns == 7 and .track == ('"$T3"' | del(.label, .detail) | .records |= map({name, at: (.at // null)}))' "Belt 3D's belt card carries its track's steps, step, tests, files and records' times, and its turns"
# Bug (#320): the Board's Building card said "testing" with no progress; its track's files and tests reach it, so it
# can say "testing, 1 of 2 test files".
q '.panels.board.data.building | map(select(.issue == 801)) | .[0] | .files == {run: 1, of: 2} and .tests == {done: 142, of: 205, failed: 0}' "a card in Building carries its test run's files and tests from its track"
# Bug: a landed card's details showed six steps done with no times; its track (a skipped Fix, a push still to go) and
# the steps' times reach Belt 3D.
answer "$(jq -c --argjson t "$T3" '.landed[0] += {track: $t}' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.belt3d.data.landed | map(select(.issue == 7)) | .[0].track ==('"$T3"' | del(.label, .detail, .records))' "Belt 3D's landed card carries its track"
# Cards that landed in one batch reach the Board with their batch, so its Landed today shows them as one landing.
B='["c'"$TODAY"'T080000-7", "c'"$TODAY"'T080500-8"]'
answer "$(jq -c --argjson b "$B" '.landed |= (map(. + {batch: $b}) + [.[0] + {card: $b[1], issue: 8, title: "Batch mate", batch: $b}])' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data.landed | map([.issue, .batch]) == [[7, '"$B"'], [8, '"$B"']]' "the Board's Landed today carries each card's batch, the cards it landed with"
q '.panels.board.data.others.widgetshop.landed | map(.batch) == [null]' "a card that landed alone has no batch on the Board"
) & PIECES+=($!)
( setup machine-4; cards_fixture
# A card waiting on a same-file card is in Building with the card it waits on and where that card is, never in Review.
PICKED=$(ago 3600)
L='[{"card": "c0-56", "issue": 56, "title": "Waits", "step": "waiting", "waitsOn": {"card": "c0-55", "issue": 55, "state": "queued"}, "stepAt": "'"$(ago 60)"'", "pickedAt": "'"$PICKED"'", "landed": false, "usd": 1, "reading": true}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data | (.building | map([.issue, .step, .waitsOn.issue, .waitsOn.state])) == [[56, "waiting", 55, "queued"]] and (.review | map(.issue)) == [801]' "a waiting card is in Building with the card it waits on and that card's state"
# Time in Building is from the card's pick-up, not the start of its step: the Board sorts that column by it.
q '.panels.board.data.building[0] | .pickedAt == "'"$PICKED"'" and .stepAt != .pickedAt' "a card in Building carries its pick-up time"
# A card that gave up its land turn is in Building with the issue it gave way to, so the Board can say so.
L='[{"card": "c0-9", "issue": 9, "title": "Fits", "step": "fix", "waitsOn": null, "gaveWay": 92, "gaveWayFixing": true, "beyond": "main is red", "stepAt": "'"$(ago 60)"'", "pickedAt": "'"$PICKED"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-10", "issue": 10, "title": "Fitted", "step": "review", "review": 2, "of": 3, "waitsOn": null, "gaveWay": 92, "stepAt": "'"$(ago 60)"'", "pickedAt": "'"$PICKED"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-red", "issue": 0, "title": "Main is red", "step": "review", "review": 1, "of": 3, "waitsOn": null, "stepAt": "'"$(ago 60)"'", "pickedAt": "'"$PICKED"'", "landed": false, "usd": 1, "reading": true}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
# Bug (issue 1430): a row carried its repository only in its issue's url, so a card with no GitHub issue (a main-red
# fix, a Tests page card: url null) gave the page no repository to link its review's file paths in
# (dashboard-view.output-review.test.mjs draws that link).
q '[.panels.belt.data.cards[] | select(.issue == 0) | [.card, .url, .repoUrl]] == [["c0-red", null, "'"${PU%/issues}"'"]]' "a belt row of a card with no GitHub issue carries its record's repository address"
q '.panels.board.data | (.building | map([.issue, .step, .gaveWay])) == [[9, "fix", 92]] and (.review | map(select(.issue == 10) | .gaveWay)) == [92]' "a card that gave way is in Building or Review with the issue it gave way to"
q '.panels.board.data | (.building | map(.gaveWayFixing)) == [true] and (.review | map(select(.issue == 10) | .gaveWayFixing)) == [false]' "a card that gave way for the fix of its failed tests says so, and one that gave way for another reason does not"
# Issue 612: a main-red fix in a slot beyond the cap carries why, so the Board can say so; a card in its slot has none.
q '.panels.board.data | (.building | map(.beyond)) == ["main is red"] and (.review | map(select(.issue == 10) | .beyond)) == [null]' "a card in a slot beyond the cap carries why on the Board, and one in its slot does not"
# Bug: Stop now's label counted every card in Building and Review as requeued, while the engine's stop (halt() in
# conveyor/lib/run.sh) leaves running one filing its follow-ups (its last line starts file), one landing (starts
# land) and one that has filed them; the Board dropped the fields that say so. Each card carries stays.
F='{"name": "follow-ups filed", "state": "done", "sec": 3, "n": 1}'
L='[{"card": "c0-11", "issue": 11, "title": "Filing", "step": "tests", "done": {"step": "file"}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-12", "issue": 12, "title": "Landing", "step": "landing", "done": {"step": "land"}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-13", "issue": 13, "title": "Filed", "step": "review", "review": 1, "of": 3, "done": {"step": "test"}, "track": {"detail": ['"$F"']}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-14", "issue": 14, "title": "Testing", "step": "tests", "done": {"step": "test"}, "track": {"detail": [{"name": "follow-ups filed", "state": "todo", "sec": null}]}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-99", "issue": 99, "title": "Landed yesterday", "step": "push", "stepAt": "'"$(ago 90000)"'", "landed": true, "usd": 1, "reading": true},
  {"card": "c0-15", "issue": 15, "title": "Split filed", "step": "build", "done": {"step": null}, "split": {"result": "split", "slices": 2, "filed": [100101, 100102]}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-16", "issue": 16, "title": "Grown filed", "step": "fix", "done": {"step": "fix"}, "track": {"grown": {"before": 5, "after": 3}}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true},
  {"card": "c0-17", "issue": 17, "title": "Split kept", "step": "build", "done": {"step": "build"}, "split": {"result": "kept", "slices": 0, "filed": null}, "stepAt": "'"$(ago 60)"'", "landed": false, "usd": 1, "reading": true}]'
answer "$(jq -c --argjson l "$L" '.belt += $l' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
# Bug: halt() leaves running a card that has filed the slices of a split, at its pick (c0-15) or for its size (c0-16,
# in its fix session), yet the Board counted it as one Stop now requeues.
q '.panels.board.data | ([.building[], .review[]] | map(select(.issue | IN(11, 12, 13, 14, 15, 16, 17, 99)) | [.issue, .stays]) | sort) == [[11, true], [12, true], [13, true], [14, false], [15, true], [16, true], [17, false], [99, true]]
  and ([.building[], .review[]] | map(select(.issue | IN(11, 12, 13, 14, 15, 16, 17, 99) | not) | .stays) | all(. == false))' "a card Stop now leaves running (filing, landing, filed its follow-ups or slices, landed) is marked stays; one it ends is not"
# Bug: the split holds its umbrella before its card closes; the issue is on the belt then, out of open.held, so the
# Rules tab's Queue in Open issues saw no split and sent a release that cleared the split's hold.
q '.panels.rules.data.splitting == [15]' "the Rules part names the belt issue whose card filed a split (15), not one kept whole (17) nor one with no split"
# A long check run (the pack's checks.progress) shows on the Board as the snapshot gives it, or the Board looks idle
# while the run holds the loop paused.
CR='{"name":"nightly","sha":"0123456789ab","started":"'"$(ago 600)"'","ended":null,"result":null,"counts":{"passed":3,"failed":1,"running":2,"queued":4,"reused":0},"done":4,"all":10,"leftSec":225,
  "lanes":[{"name":"broken-0","state":"failed","started":null,"sec":120},{"name":"busy-0","state":"running","started":"'"$(ago 30)"'","sec":null},{"name":"busy-1","state":"running","started":"'"$(ago 30)"'","sec":null}]}'
answer "$(jq -c --argjson c "$CR" '.checkRun = $c' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data.checkRuns | length == 1 and (.[0] | .repo == "sample" and .name == "nightly" and .counts == {passed: 3, failed: 1, running: 2, queued: 4, reused: 0} and .done == 4 and .all == 10 and .leftSec == 225
  and ([.lanes[] | select(.state == "failed") | .name] == ["broken-0"]) and ([.lanes[] | select(.state == "running")] | length) == 2)' "the Board has the check run: its counts, its failed lane and its running lanes"
# A record the Board does not steer runs checks too: its run is on the Board, named by its repo.
answer "$P" "$P_URL" 1794000000 "$(jq -c --argjson c "$CR" '.checkRun = $c' <<<"$C")" "$C_URL" 0
run
q '.panels.board.data | .repo == "sample" and (.checkRuns | map([.repo, .name, .done])) == [["widgetshop", "nightly", 4]]' "the check run of a record the Board does not steer reaches the Board"
# No record is on host.json's main: the Board steers nothing, and the run still reaches it.
cp "$MAIN/conveyor/host.json" "$T/host.steered"
jq -c '.main = "/srv/elsewhere"' "$T/host.steered" > "$MAIN/conveyor/host.json"
run
q '.panels.board.data | .repo == null and (.checkRuns | map([.repo, .name, .done])) == [["widgetshop", "nightly", 4]]' "the check run reaches the Board when no record is steered"
mv "$T/host.steered" "$MAIN/conveyor/host.json"
answer "$(jq -c '.checkRun = {error: "check run: progress unreadable: jq: parse error"}' <<<"$P")" "$P_URL" 1794000000 "$C" "$C_URL" 0
run
q '.panels.board.data | .checkRuns == [{error: "check run: progress unreadable: jq: parse error", repo: "sample"}] and .repo == "sample" and (.review | length) == 1' "an unreadable check run is said, and the rest of the Board is still there"
q '.panels.cost.data.cards | .todayUsd == 4.25 and .weekUsd == 14 and .perLandedUsd == 1 and .landedAfter == {"1": 3, "2": 1, "3": 0, more: 0} and .unpricedSteps == 1' "cost sums both records; the average per landed card weighs each record by the cards it landed"
q '.panels.cost.data.cards.perCard | map([.repo, .issue, .state, .todayUsd, .weekUsd]) == [["sample", 801, "on the belt", 1.25, 1.25], ["sample", 6, "landed", 0, 6.25], ["sample", 13, "blocked", 2.5, null], ["widgetshop", 4, "retried", 0.5, 0.5]]' "per card, the 7 days: a card landed on an earlier day and a blocked one are rows too, and an unpriced sum stays null"
q '.panels.cost.data.cards.perCard | (.[1] | .url == "'"$PU"'/6" and .title == "Landed days ago") and (.[3].url == "'"$CU"'/4") and (.[0] | keys) == ["card", "issue", "repo", "runs", "state", "title", "todayEstimate", "todayUsd", "url", "weekEstimate", "weekUsd"]' "a per-card cost row names its repo and links to that repo's issue"
# Bug: the rule Pick settings' rows of each record did not reach the Cost panel, or lost which project they are of.
q '.panels.cost.data.cards.picks | map([.repo, .group, .usd]) == [["sample", "small docs", 5], ["widgetshop", "small code", null]]' "each record's pick rows reach the Cost panel with its repo"
# Bug: a dropped challenger or a flagged trial card did not reach the Cost panel, lost its project, or a record from
# before trials (widgetshop's) hid the other record's.
q '.panels.cost.data.cards.trials | (.dropped | map([.repo, .group, .cards])) == [["sample", "small docs", ["c1-5", "c1-10"]]] and (.flagged | map([.repo, .issue, .files])) == [["sample", 15, ["ci/deploy.sh"]]]' "each record's trials reach the Cost panel with its repo"
# Bug: a record's last judge replay, or the judge models a replay can run on, did not reach the Cost panel, or a
# record whose engine has no replay (no cost.replay in its snapshot) was offered one.
q '.panels.cost.data.cards.replays | map([.repo, .last.agree, .judge.choices]) == [["sample", 1, ["claude-j"]]]' "the last replay and the judge's models of each record that runs replays reach the Cost panel"
# The figures are the priced steps'; how many each leaves out is summed over the records, and the steps are
# listed with why. A record from before it named them leaves the list unknown, never empty.
q '.panels.cost.data.cards | .todayLeftOut == 0 and .weekLeftOut == 0 and .perLandedLeftOut == 0 and .unpriced == null' "no record gives the steps left out"
U='{"todayLeftOut": 1, "weekLeftOut": 2, "perLandedLeftOut": 1, "unpriced": [{"card": "c8-4", "issue": 4, "step": "build", "time": "2026-11-09T01:00:00Z", "why": "no model recorded"}]}'
answer "$(jq -c '.cost += {todayLeftOut: 0, weekLeftOut: 0, perLandedLeftOut: 0, unpriced: []}' <<<"$P")" "$P_URL" 1794000000 "$(jq -c --argjson u "$U" '.cost += $u' <<<"$C")" "$C_URL" 0
run
q '.panels.cost.data.cards | .todayLeftOut == 1 and .weekLeftOut == 2 and .perLandedLeftOut == 1
  and .unpriced == [{repo: "widgetshop", card: "c8-4", issue: 4, url: "'"$CU"'/4", step: "build", time: "2026-11-09T01:00:00Z", why: "no model recorded"}]' "the steps the figures leave out are counted and named, each with why and its link"
) & PIECES+=($!)
( setup machine-5; cards_fixture
# Bug (#1585): a step priced as an estimate (its usage read in part, or not at all) reached the page as exact dollars:
# the parts dropped the snapshot's estimate marks, so Today, 7 days, Per landed card, a card's row, a Review card
# and the rest showed `$x` with no `~`. Each part keeps the mark of the figure it carries.
PE=$(jq -c '.belt[0].estimate = true | .landed[0].estimate = true | .landedEstimate = 1 | .needsYou.blocked[0].metrics.estimate = true
  | .cost += {todayEstimate: 1, weekEstimate: 2, perLandedEstimate: 1} | .cost.cards[0] += {todayEstimate: 1, weekEstimate: 1} | .cost.picks[0].estimate = 1
  | .metrics.cards[0].metrics += {estimate: true, timeline: [{step: "build", usd: 1}, {step: "review", usd: 1, estimate: "the tokens it counted, at its model'"'"'s price"}]}' <<<"$P")
# widgetshop's metrics.cards is a list, or the Board shows no project's Metrics cards.
answer "$PE" "$P_URL" 1794000000 "$(jq -c '.cost += {weekEstimate: 1} | .metrics.cards = []' <<<"$C")" "$C_URL" 0
run
q '.panels.board.data | [(.review | map([.issue, .estimate])), (.landed | map([.issue, .estimate])), .today.estimate] == [[[801, true]], [[7, true]], true]' \
  "the Board's Review and Landed cards and its Today figure keep their estimate marks"
q '[(.panels.belt.data.cards | map([.issue, .estimate == true])), (.panels.belt3d.data | (.belt | map([.issue, .estimate])), (.needs | map([.issue, .estimate])), (.landed | map([.issue, .estimate])))]
  == [[[801, true], [5, false]], [[801, true], [5, false]], [[12, false], [13, true]], [[4, false], [7, true]]]' "the Belt and Belt 3D cards keep their estimate marks"
q '.panels.cost.data.cards | [.todayEstimate, .weekEstimate, .perLandedEstimate, .byRepo.sample.weekEstimate, .byRepo.widgetshop.weekEstimate,
  (.perCard | map(select(.repo == "sample") | [.issue, .todayEstimate, .weekEstimate]))] == [1, 3, 1, 2, 1, [[801, 1, 1], [6, 0, 0], [13, 0, 0]]]' \
  "Cost's three figures, each project's and each card's row carry how many of their steps are estimates"
q '[(.panels.metrics.data.compare | (.projects | map(.usdEstimate)), .machine.usdEstimate), (.panels.machine.data | .todayEstimate, (.projects | map(.todayEstimate)))]
  == [[2, 1], 3, 1, [1, 0]]' "the side-by-side cost and the machine's cost today carry their estimates"
q '.panels.landed.data.cards | map([.issue, .estimate == true]) == [[4, false], [7, true]]' "the Landed panel's cards keep their estimate marks"
q '.panels.metrics.data.cards | map(select(.repo == "sample")) | (map([.issue, .metrics.estimate == true]) == [[1, true], [2, false], [3, false]])
  and (.[0].metrics.timeline | map(.estimate)) == [null, "the tokens it counted, at its model'"'"'s price"]' "a Metrics card keeps its estimate mark, and each step how it was priced"
q '.panels.cost.data.cards.picks | map([.repo, .group, .estimate]) == [["sample", "small docs", 1], ["widgetshop", "small code", null]]' "a Pick row keeps how many of its steps are estimates"
# Bug: a Building card dropped its estimate mark. And the count of estimates for each landed card summed every
# project, also widgetshop with no reviewed landing, whose dollars the average leaves out: its estimate put ~ on
# sample's exact dollars.
answer "$P" "$P_URL" 1794000000 "$(jq -c '.belt[0].estimate = true | .cost += {landedAfter: {"1": 0, "2": 0, "3": 0, more: 0}, perLandedEstimate: 1}' <<<"$C")" "$C_URL" 0
run
q '.panels.board.data.others.widgetshop.building | map([.issue, .estimate]) == [[5, true]]' "a Building card keeps its estimate mark"
q '.panels.cost.data.cards | [.perLandedUsd, .perLandedEstimate, .byRepo.widgetshop.perLandedEstimate] == [2.5, 0, 1]' \
  "the estimates for each landed card count only the projects its average holds; the project's own figure keeps its own"
) & PIECES+=($!)
pieces
) & started machine

( fresh figures; cards_fixture
# --- a figure that was not read is null, never a smaller number ---
answer "$P" "$P_URL" 1794000000 "$(jq -c '.cost.today = null | .cost.perLanded = null' <<<"$C")" "$C_URL" 0
run
q '.panels.cost.data.cards | .todayUsd == null and .perLandedUsd == null and .weekUsd == 14' "a record with an unpriced total leaves the sum unknown, never the priced part"
# A host whose snapshot is from before it carried the per-card rows: they are unknown, never an empty list.
answer "$P" "$P_URL" 1794000000 "$(jq -c 'del(.cost.cards)' <<<"$C")" "$C_URL" 0
run
q '.panels.cost.data.cards | .perCard == null and .weekUsd == 14' "a record with no per-card cost rows leaves them unknown; the totals are still given"
answer "$P" "$P_URL" 1794000000 "$(jq -c '.queue = {next: null, held: null}' <<<"$C")" "$C_URL" 0
run
q '.panels.queue | .error == null and .data.next == null and .data.held == null and .data.awaitingDeploy == null and (.data.issuesError | test("devbox"))' "a record whose issues GitHub did not list leaves the queue unknown, never short"
# Bug: filtered to the project whose issues were listed, the page still had no queue: the part held only the unknown
# queue of all. Each record's own queue is beside it, the read one whole and the unread one unknown with its reason.
q '.panels.queue.data.byRepo | (.sample | (.next | map([.repo, .issue])) == [["sample", 20]] and .held == 2 and (.awaitingDeploy | type) == "array" and (.waiting | type) == "array" and .issuesError == null)
  and (.widgetshop | .next == null and .held == null and .awaitingDeploy == null and .waiting == null and (.issuesError | test("widgetshop on devbox")))' "one record's failed read leaves the other record's own queue readable, for the page filtered to it"
q '.panels.belt3d.data | .queue == null and (.byRepo.sample.queue | (.next | map([.repo, .issue])) == [["sample", 20]] and (.held | map(.issue)) == [30] and (.waiting | map(.issue)) == [32])
  and .byRepo.widgetshop.queue == null' "Belt 3D carries the read record's own queue too, and the unread one's as unknown"
q '.panels.belt.data.cards | length == 2' "the queue's failed read leaves the rest of the snapshot in place"
answer "$P" "" 1794000000 "$C" "https://gitlab.example/example/cd.git" 0
run
q '.panels.belt.data.cards | map(.url) == [null, null]' "a record whose origin is not a GitHub address gives no issue link"

# --- the host did not answer, or answered with something else: no card is shown, and the reason is ---
limit_read # this machine's session costs below are the limit read's
quiet; echo 255 > "$T/ssh-rc"; echo 'ssh: connect to host devbox port 22: Connection timed out' > "$T/ssh-err"; : > "$T/ssh-out"
run
q '.panels.health.data.host | .name == "devbox" and .reachable == false and (.error | test("devbox did not answer: ssh: connect to host devbox"))' "ssh that does not get through is an unreachable host, with ssh's own reason"
q '[.panels.belt, .panels.queue, .panels.landed] | all(.[]; .data == null and (.error | test("devbox did not answer")))' "with no answer the belt, the queue and the landed cards are not read, never empty"
q '.panels.needs | .error == null and .data.cards == null and (.data.cardsError | test("did not answer"))' "the cards that need the owner are unknown while the host is away"
q '.panels.health.data.records == null' "no record is read from a host that did not answer"
q '.panels.cost | .error == null and .data.cards == null and (.data.cardsError | test("did not answer")) and .data.sessions != null' "card costs are unknown; this machine's own session costs are still given"
quiet; echo 124 > "$T/ssh-rc"; : > "$T/ssh-out"
run
q '.panels.health.data.host | .reachable == false and (.error | test("no answer in [0-9]+ s"))' "an ssh that hits its time limit is an unreachable host"
quiet; echo 1 > "$T/ssh-rc"; echo 'conveyor: /srv/state/cards.jsonl line 3 is not a whole record of a known step; stopping' > "$T/ssh-err"; : > "$T/ssh-out"
run
q '.panels.health.data.host | .reachable == true and (.error | test("answered, but its Conveyor gave no snapshot: conveyor: .* line 3 is not a whole record"))' "a host that answers with Conveyor's refusal is reachable, and the refusal is shown"
q '.panels.belt.data == null' "a refused snapshot shows no card"
printf '%s\n%s\n%s\n@@end\n' "$(snap)" "$P_URL" 0 > "$T/ssh-out"; echo 0 > "$T/ssh-rc"; : > "$T/ssh-err"
run
q '.panels.belt | .data == null and (.error | test("not with the snapshot of every record"))' "an answer one record short is no answer: never a part of the records"
answer 'not json' "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.belt | .data == null and (.error | test("not with the snapshot of every record"))' "a record whose answer is not a snapshot leaves every record unread"
answer "$(snap | jq -c 'del(.belt)')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.belt.data == null and .panels.health.data.host.reachable == true' "a snapshot with a part missing is not understood, and is not shown in part"

# --- a checkout that names no host, or one it cannot find ---
mv "$MAIN/conveyor/host.json" "$T/host.json"; : > "$T/ssh-calls"
run
q '.panels.health.data.host == {name: null, local: true, reachable: null, error: "this checkout has no conveyor/host.json"} and (.panels.belt.error | test("no conveyor/host.json"))' "a checkout with no host file says so, and names no build machine"
[ ! -s "$T/ssh-calls" ] || fail "with no host file nothing is asked over ssh: $(cat "$T/ssh-calls")"
# Each error names the field that is wrong (#112), and a host file that names a build machine is said to.
echo '{"host":"dev box","ssh":"user@devbox","main":"/srv/main"}' > "$MAIN/conveyor/host.json"
run
q '.panels.belt.error == "conveyor/host.json names an ssh target, but its host is not a machine name" and .panels.health.data.host.local == false' "a host name that is not a plain name is refused, never passed to ssh"
echo '{"host":"elsewhere","ssh":"","main":"/srv/main"}' > "$MAIN/conveyor/host.json"
run
q '.panels.belt.error == "conveyor/host.json names no ssh target for elsewhere that ssh can use"' "an ssh target ssh cannot use is not guessed from test-hosts.json"
echo '{"host":"devbox","ssh":"user@devbox","records":[{"repo":"sample","main":"/srv/main"}]}' > "$MAIN/conveyor/host.json"
run
q '.panels.belt.error == "conveyor/host.json names no main: the path of the main checkout on devbox"' "a build machine with no main is refused, naming the field"
echo '{"host":"devbox","ssh":"user@devbox","main":"/srv/main","records":[{"repo":"sample","main":"relative/path"}]}' > "$MAIN/conveyor/host.json"
run
q '.panels.belt.error == "conveyor/host.json records are not understood: each needs a repo name and the path of its main checkout"' "a record whose checkout is not an absolute path is refused"
[ ! -s "$T/ssh-calls" ] || fail "a host file that is not understood asks nothing over ssh: $(cat "$T/ssh-calls")"
mv "$T/host.json" "$MAIN/conveyor/host.json"
) & started figures

( fresh behind
# --- a snapshot behind the card records: Needs you and the belt count from the records and loop.json ---
# Bug (#1101): the Board read Needs you and the belt's count from the old snapshot alone while a new one took
# minutes, so it showed nothing blocked and nothing building while cards blocked and built. sample's snapshot holds
# c1 waiting for the yes, c2 blocked, a failing push, and c5 on the belt; since it was made c2 was retried,
# c5 blocked and c6 was picked and stopped for the yes, and loop.json counts 4 building (recordsNow). widgetshop's snapshot is up to
# date, one card on its belt. Bug: c6 was listed blocked, with no Approve, as the cards waiting for the yes were the
# old snapshot's alone. Bug (#1123): c6 is on no belt of the snapshot, and it was untitled: its title is recordsNow's.
at=$(ago 120)
answer "$(snap "$(jq -cn --arg at "$at" '{snapshotAt: $at, recordsNewer: true,
    needsYou: {waiting: [{card: "c1", issue: 12, title: "Button copy", sentence: "Staff see a button.", since: $at}],
      blocked: [{card: "c2", issue: 13, title: "Broken build", reason: "tests failed", tail: "", since: $at},
        {card: "c0", issue: 11, title: "Pushed", reason: "the push failed", tail: "", since: $at, push: true}]},
    belt: [{card: "c5", issue: 15, title: "Fifteen", step: "build", stepAt: $at}],
    recordsNow: {building: 4, waitingCount: 0, blocked: [{card: "c5", issue: 15, name: null, reason: "the session made no change", since: $at}],
      waiting: [{card: "c1", issue: 12, name: null, reason: "needs a yes", since: $at, sentence: "a"},
        {card: "c6", issue: 16, name: null, title: "Sixteen", reason: "needs a yes", since: $at, sentence: "Guests see a new page."}]}}')")" "$P_URL" 1794000000 \
  "$(snap '{"belt": [{"card": "w1", "issue": 3, "title": "Three", "step": "build"}, {"card": "w2", "issue": 4, "title": "Four", "step": "landing", "offCap": true}]}')" "$C_URL" 0
run
q '.panels.needs.data | (.cards.waiting | map([.card, .repo, .title, .sentence])) == [["c1", "sample", "Button copy", "Staff see a button."], ["c6", "sample", "Sixteen", "Guests see a new page."]]
  and (.cards.blocked | map([.card, .repo, .title])) == [["c0", "sample", "Pushed"], ["c5", "sample", "Fifteen"]]
  and ([.cards.waiting[], .cards.blocked[] | .fromRecords == true] == [false, true, false, true])
  and .behind == [{repo: "sample", at: "'"$at"'"}]' "Needs you holds the cards the records hold blocked and waiting for the yes now, and names the record that is behind"
q '.panels.belt.data | .building == 5 and .byRepo.sample.building == 4 and .byRepo.widgetshop.building == null and .behind == [{repo: "sample", at: "'"$at"'"}]' \
  "the belt counts loop.json's 4 for the record that is behind, and its cards for the one that is not, a card that lands (offCap: widgetshop's w2) left out (issue 1538)"
# Bug: the Machine project row counted the old snapshot's one card for sample while the Belt panel said 4.
q '.panels.machine.data.projects | map({key: .repo, value: .used}) | from_entries == {sample: 4, widgetshop: 1}' \
  "each Machine project row counts as the Belt panel does: loop.json's 4 for the record behind, its own cards for the other"
) & started behind

( fresh behindgone
# Bug: once `conveyor.sh run` exited, recordsNow gives no building count (null), and the belt fell back to the old
# snapshot's belt: its last card, blocked since, was counted building. With no loop nothing builds: the count is 0.
at=$(ago 120)
answer "$(snap "$(jq -cn --arg at "$at" '{snapshotAt: $at, recordsNewer: true, needsYou: {waiting: [], blocked: []},
    belt: [{card: "c5", issue: 15, title: "Fifteen", step: "build", stepAt: $at}],
    recordsNow: {building: null, waitingCount: null, waiting: [], blocked: [{card: "c5", issue: 15, name: null, reason: "tests failed", since: $at}]}}')")" "$P_URL" 1794000000 "$(snap)" "$C_URL" 0
run
q '.panels.belt.data | .building == 0 and .byRepo.sample.building == 0' "a record behind its card records whose loop has exited counts none building"
) & started behindgone

# Every part ended and passed; a part that failed stopped at its FAIL line, above.
bad=()
for p in "${PARTS[@]}"; do wait "${p#*:}" || bad+=("${p%%:*}"); done
[ ${#bad[@]} -eq 0 ] || fail "these parts failed (their FAIL lines are above): ${bad[*]}"
echo "ok: dashboard-cards"
