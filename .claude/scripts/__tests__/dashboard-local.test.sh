#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The collector of the Conveyor dashboard (dashboard.sh). The page is what the owner reads instead of asking, so the
# data must never lie: every panel's part is cut from the same answers, a source that was not read is null with its
# reason (never a 0 or an empty list that reads as measured), a host that did not answer is said to be unreachable,
# and a sum with an unpriced step in it is unknown, never the sum of the priced part.
# This file has the parts that read this machine (decisions, lanes, update, install, queuewait); dashboard.test.sh
# and dashboard-cards.test.sh have the others.
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
DECIDE=$SOURCE/.claude/scripts/decision.sh
VIEW=$SOURCE/.claude/dashboard
TOP=$(cd "$(mktemp -d /tmp/dashboard-test.XXXXXX)" && pwd -P) # physical spelling: on the Mac /tmp is /private/tmp
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
FL=$T/lanes/main-fast-lane RSL=$T/userhome/lanes/main-research
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
    "$@" timeout 120 bash "$DASH" || rc=$?
  [ "$rc" -ne 124 ] || fail "HUNG: a collect ran past 120 s (line ${BASH_LINENO[0]})"
  [ "$rc" -eq 0 ] || fail "dashboard.sh exited $rc (line ${BASH_LINENO[0]})"
}
D=$OUT/data.js
}
json() { sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$D"; }
q() { json | jq -e "$1" >/dev/null || fail "$2 (jq: $1; data: $(json | jq -c '.panels' | cut -c1-1500))"; }
PARTS=()
started() { PARTS+=("$1:$!"); } # <part>, after its ( ... ) &

( fresh decisions
# --- the open decisions: each project's ledger, where the host file's record names it on this machine ---
# Bug caught: the Board read the ledger of its own checkout, a plugin clone that holds none, and Needs you said
# "Decisions were not read: no ledger at <the clone>" while the project's decisions waited in the project's checkout.
dec() { local l=$1; shift; env HOME="$T/userhome" CONVEYOR_MAIN="$MAIN" CONVEYOR_LEDGER="$l" CONVEYOR_RULING_LOG="$T/userhome/.claude/rulings/conveyor.jsonl" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" bash "$DECIDE" "$@"; }
dec "$MAIN/.claude/metrics/decisions.jsonl" add q-own "The Board's own checkout?" 'no' main >/dev/null 2>&1 || fail "decision add to the Board's own ledger failed"
quiet
run
q '.panels.needs.data | .decisions == [] and .decisionsError == null' "a named ledger with no open decision is a measured empty list; a record that names no ledger has none and no warning; the Board's own ledger is not read"
mv "$PPL" "$T/ppl.kept"
run
q '.panels.needs.data | .decisions == null and (.decisionsError | test("^no ledger for sample at .*/ledgers/sample/decisions.jsonl$")) and .cards != null' "a named ledger that does not exist is a warning naming its project, and the cards still show"
mv "$T/ppl.kept" "$PPL"
dec "$PPL" add q-ship 'Ship "it" <b>now</b>?' 'Yes' main --options '["Yes","No"]' >/dev/null 2>&1 || fail "decision add failed"
dec "$PPL" add q-old 'Already settled?' 'no' main >/dev/null 2>&1 && dec "$PPL" answer q-old 'no' >/dev/null 2>&1 || fail "decision answer failed"
dec "$WSL" add w-pay 'Take card payments from Monday?' 'No' main >/dev/null 2>&1 || fail "decision add to the second ledger failed"
cp "$MAIN/conveyor/host.json" "$T/host.one-ledger"
jq -c --arg l "$WSL" '.records[1].ledger = $l' "$T/host.one-ledger" > "$MAIN/conveyor/host.json"
run
q '.panels.needs.data | .decisionsError == null and (.decisions | map([.repo, .id])) == [["sample", "q-ship"], ["widgetshop", "w-pay"]]
   and (.decisions[0] | .question == "Ship \"it\" <b>now</b>?" and .options == ["Yes", "No"] and .proposedDefault == "Yes" and .source == "main" and (.askedAt | test("Z$")))' \
  "two records with ledgers show both projects' open decisions, each named, with what the owner needs to answer it"
# Bug: a project's section left its open decisions out of its Needs you, so it counted fewer than wait on the owner.
q '[.panels.machine.data.projects[] | [.needs[] | select(.decision != null) | [.repo, .decision, .title]]] == [[["sample", "q-ship", "Ship \"it\" <b>now</b>?"]], [["widgetshop", "w-pay", "Take card payments from Monday?"]]]' \
  "each project's section has its own open decisions in its Needs you, never another project's"
grep -qx '# sample' "$OUT/digest.txt" && grep -qx '# widgetshop' "$OUT/digest.txt" \
  || fail "a collect that read the ledgers writes the owner's daily page beside data.js, a page a project: $(cat "$OUT/digest.txt" 2>/dev/null)"
# Bug caught: the decisions read so far went to the next ledger's jq as one argument, so a long question passed the
# argument limit and every project after it was dropped. And the whole ruling log's picker answers, which name no
# project, were printed under every project's heading.
cp "$PPL" "$T/ppl.short"
jq -cn '{id: "q-long", askedAt: "2026-11-12T10:00:00Z", question: ("x" * 140000), proposedDefault: "no", source: "main", answeredAt: null, answer: null}' >> "$PPL"
RL=$T/userhome/.claude/rulings/conveyor.jsonl; mkdir -p "${RL%/*}"; [ ! -e "$RL" ] || fail "no ruling log is expected here yet"
jq -cn --arg t "$(ago 0)" '{id: "r-pick", source: "ask", utc: $t, question: "Ship project A?", answer: "yes"}' > "$RL"
run
q '.panels.needs.data | .decisionsError == null and (.decisions | map([.repo, .id])) == [["sample", "q-ship"], ["sample", "q-long"], ["widgetshop", "w-pay"]]' \
  "a question past the argument limit drops no project's decisions"
[ "$(grep -c 'Ship project A?' "$OUT/digest.txt")" = 1 ] \
  && [ "$(awk '/^# /{h=$0} /Ship project A\?/{print h}' "$OUT/digest.txt")" = '# Picker answers no project ledger holds' ] \
  || fail "a picker answer is on the daily page once, under no project's heading: $(cat "$OUT/digest.txt")"
mv "$T/ppl.short" "$PPL"; rm -f "$RL"
jq -c '.records[1].ledger = "/nowhere/decisions.jsonl"' "$T/host.one-ledger" > "$MAIN/conveyor/host.json"
run
q '.panels.needs.data | (.decisions | map(.id)) == ["q-ship"] and .decisionsError == "no ledger for widgetshop at /nowhere/decisions.jsonl"' \
  "a ledger that does not exist is a warning naming that project, beside the decisions of the ledgers that read"
grep -qx '# widgetshop' "$OUT/digest.txt" \
  || fail "a collect in which a named ledger did not read keeps the last good daily page: $(cat "$OUT/digest.txt" 2>/dev/null)"
# Bug caught: a run that read no ledger kept the last page, so removing the last named ledger left its decisions on
# the owner's daily page for good.
jq -c '.records |= map(del(.ledger))' "$T/host.one-ledger" > "$MAIN/conveyor/host.json"
grep -q 'q-ship\|Ship "it"' "$OUT/digest.txt" || fail "the daily page holds the open decision before its ledger is removed: $(cat "$OUT/digest.txt")"
run
q '.panels.needs.data | .decisions == [] and .decisionsError == null' "with no ledger named there are no decisions and no warning"
[ -e "$OUT/digest.txt" ] && ! grep -q 'q-ship\|Ship "it"\|^# ' "$OUT/digest.txt" \
  || fail "with no ledger named the daily page holds no project's decisions: $(cat "$OUT/digest.txt" 2>/dev/null)"
mv "$T/host.one-ledger" "$MAIN/conveyor/host.json"
# There is no main session any more; an answer that is recorded is done, and nothing is listed as unsent.
UD=$T/userhome/.claude/rulings/dashboard-unsent; mkdir -p "$UD"
printf '{"id":"u1","askedAt":"2026-10-18T12:00:00Z","answer":"go","ruling":"ruling-1"}' > "$UD/u1.json"
run
q '.panels.needs.data | has("unsent") or has("unsentError") | not' "an answer kept from before is not listed as waiting on main"
rm -rf "$UD"
cp "$PPL" "$T/ledger.ok"; printf '{"id":"broken"\n' >> "$PPL"
run
q '.panels.needs | .error == null and .data.decisions == null and (.data.decisionsError | startswith("sample: ")) and .data.cards != null' "a corrupt ledger is not read, never an empty list; the cards still show"
echo 255 > "$T/ssh-rc"; : > "$T/ssh-out"
run
q '.panels.needs | .data == null and (.error | test("Cards: .*did not answer.* Decisions: "))' "with neither the cards nor the decisions read, the part itself failed to load"
cp "$T/ledger.ok" "$PPL"

# The host file's `main` is the Conveyor host's checkout, on another machine when the Board runs on the Mac. A
# Board in a git checkout, with CONVEYOR_MAIN unset, reads its own checkout and sends only the host's path over ssh.
# Bug caught: the host file's main was taken as this machine's checkout: the collect ran `cd /srv/linux-only` here
# and failed, and `decision.sh list` found no ledger there.
HF=$T/hostfile; mkdir -p "$HF/conveyor" "$MAIN/.claude/scripts"
jq -cn --arg l "$PPL" '{host: "devbox", ssh: "user@devbox", main: "/srv/linux-only",
  records: [{repo: "sample", main: "/srv/linux-only", ledger: $l}, {repo: "widgetshop", main: "/srv/cd"}]}' > "$HF/conveyor/host.json"
cp "$SOURCE"/.claude/scripts/{dashboard*.sh,dashboard_limit*.py,dashboard_alerts.jq,dashboard_needs.json,decision.sh,hostfile.sh} "$MAIN/.claude/scripts/"
quiet; : > "$T/ssh-calls"
new_cycle
env -u CONVEYOR_MAIN -u CONVEYOR_HOOK_FIRE_LOG -u CODEX_HOME HOME="$T/userhome" XDG_CONFIG_HOME="$HF" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux \
  CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" timeout 120 bash "$MAIN/.claude/scripts/dashboard.sh" 2>"$T/hf.err" \
  || fail "a Board whose host file names a checkout on another machine must still collect: $(cat "$T/hf.err")"
q '.panels.needs.data | .decisionsError == null and (.decisions | map(.id)) == ["q-ship"]' "the decisions come from the ledger the host file names, not the host file's main nor the Board's own checkout"
grep -qF "bash '/srv/linux-only/conveyor/conveyor.sh' snapshot" "$T/ssh-calls" || fail "the host file's main is the host's checkout, sent over ssh: $(cat "$T/ssh-calls")"
env -u CONVEYOR_MAIN HOME="$T/userhome" XDG_CONFIG_HOME="$HF" bash "$MAIN/.claude/scripts/decision.sh" list > "$T/hf.list" 2>&1 \
  && jq -e 'map(.id) | index("q-own") != null' "$T/hf.list" >/dev/null \
  || fail "decision.sh must read this machine's ledger, not the host file's main: $(cat "$T/hf.list")"
rm -rf "$MAIN/.claude/scripts"

# With CONVEYOR_DASHBOARD_DIR unset, the Board's folder is dashboard/ in the state folder: the host file's stateDir,
# else the checkout's conveyor/state, as `conveyor.sh state-dir` names it. Bug caught: the Board wrote to a fixed
# folder in the owner's home, outside the state folder, whatever the host file said.
SDH=$T/sd-host SD=$T/sd-state; mkdir -p "$SDH/conveyor"
jq -c --arg s "$SD" --arg m "$MAIN" '. + {main: $m, stateDir: $s}' "$MAIN/conveyor/host.json" > "$SDH/conveyor/host.json"
quiet; run CONVEYOR_DASHBOARD_DIR= XDG_CONFIG_HOME="$SDH"
[ -s "$SD/dashboard/data.js" ] || fail "the Board writes data.js to dashboard/ in the host file's stateDir"
quiet; run CONVEYOR_DASHBOARD_DIR= XDG_CONFIG_HOME="$T/sd-none"
[ -s "$MAIN/conveyor/state/dashboard/data.js" ] || fail "with no host file the Board writes data.js to the checkout's conveyor/state/dashboard"
echo '{' > "$SDH/conveyor/host.json"
env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" \
  XDG_CONFIG_HOME="$SDH" timeout 120 bash "$DASH" 2>/dev/null && fail "a host file that cannot be read must stop the Board, never fall back to the checkout's folder"
rm -rf "$SDH" "$SD" "$MAIN/conveyor/state"
) & started decisions

( fresh lanes
gw() { git -C "$FL" -c user.email=t@t -c user.name=t "$@"; }
# fast_lane <branch> -- the Fast lane as the piece before leaves it, on <branch>: two commits, f.txt added.
fast_lane() {
  g worktree add -q -b "$1" "$FL" main
  gw commit -q --allow-empty -m "First lane commit"; gw commit -q --allow-empty -m "Second lane commit"
  echo x > "$FL/f.txt"; gw add f.txt
}
( # --- the lanes: each record's Fast lane and Research worktrees on this machine, at the folders the host file names ---
quiet
run
q '.panels.lanes == {error: null, data: {records: [{repo: "sample", fast: {present: false}, research: {present: false}},
  {repo: "widgetshop", fast: null, research: null}], cardsError: null}}' "a named lane folder that is not there is said, not guessed; a record that names no lane has none, and that is no error"
g worktree add -q -b fix-123-fast "$FL" main
run
q '.panels.lanes.data.records[0].fast | .present and .branch == "fix-123-fast" and .ahead == 0 and .dirty == 0 and .subject == null and .landing == {state: "none"}' "a lane level with main has no open change"
# A saved new file is work not committed: the tile counts it, never Idle.
echo x > "$FL/new.txt"
run
q '.panels.lanes.data.records[0].fast | .ahead == 0 and .dirty == 1' "a new file not yet added is an uncommitted change"
rm "$FL/new.txt"
# New files in a new folder are each a file changed, not the folder once.
mkdir "$FL/new"; echo a > "$FL/new/a.txt"; echo b > "$FL/new/b.txt"
run
q '.panels.lanes.data.records[0].fast | .ahead == 0 and .dirty == 2' "each new file in a new folder is counted, not the folder once"
rm -r "$FL/new"
gw commit -q --allow-empty -m "First lane commit"; gw commit -q --allow-empty -m "Second lane commit"
echo x > "$FL/f.txt"; gw add f.txt
run
q '.panels.lanes.data.records[0].fast | .ahead == 2 and .subject == "Second lane commit" and .first == "First lane commit" and .dirty == 1 and .landing == {state: "none"}' "the open change: commits ahead of main, the newest and the oldest, and uncommitted files; no card lands it yet"
) & PIECES+=($!)
( setup lanes-2; fast_lane c20260101T000000-sample-123
lane_card() { jq -c --argjson c "$1" "$2" <<<"$(snap)"; }
BELT_CARD='{"card": "c5-123", "issue": 123, "title": "Fast thing", "step": "tests", "review": null, "of": 3, "stepAt": "'"$(ago 30)"'", "model": null, "tokens": {"claude": 0, "codex": 0}, "usd": 0}'
answer "$(lane_card "$BELT_CARD" '.belt = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing | .state == "belt" and .card == "c5-123" and .step == "tests"' "the card of the issue the branch names is the lane's landing, with its step"
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "reason": "worktree: branch does not merge", "since": "'"$(ago 30)"'"}' '.needsYou.blocked = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing | .state == "blocked" and .reason == "worktree: branch does not merge"' "a blocked landing carries its reason"
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "sentence": "Customers see a new page.", "since": "'"$(ago 30)"'"}' '.needsYou.waiting = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing | .state == "waiting" and .reason == "Customers see a new page."' "a landing that waits for the owner's yes says what they would be approving"
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "step": "landed", "time": "'"$(ago 30)"'", "usd": 1, "reviews": 1, "followups": [], "sha": "abc", "pushed": true}' '.landed = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing | .state == "landed" and .reviews == 1' "a landed lane change says so until the lane is reset"
# The landed list is today's alone; after midnight the card is in branches, however long ago it landed.
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "step": "landed", "time": "2026-01-01T00:00:00Z"}' '.branches = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "landed", card: "c5-123", since: null, reviews: null}' "a lane change landed long ago still says landed, with no time"
# A snapshot from before it carried branches: the card is among the 7 days' cost rows.
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "state": "landed", "today": 0, "week": 1}' '.cost.cards = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "landed", card: "c5-123", since: null, reviews: null}' "a lane change landed on an earlier day still says landed, with no time"
answer "$(lane_card '{"card": "c5-123", "issue": 123, "title": "Fast thing", "state": "retried", "today": 0, "week": 1}' '.cost.cards = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "none"}' "a retried card of an earlier day is not a landing"
answer "$(snap)" "$P_URL" 0 "$(lane_card "$BELT_CARD" '.belt = [$c]')" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "none"}' "another record's card of the same issue number is not this record's lane's landing"
# Issue 601: a number at the end of a hand fix's name is no issue (land-branch lands it as issue 0): issue 123's card
# is not the landing of a lane on fix-123.
gw branch -q -m fix-123
answer "$(lane_card "$BELT_CARD" '.belt = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "none"}' "a number at the end of the branch name is not the lane's issue"
# A branch that names no issue lands as a card of issue 0, titled with the first commit of the branch.
gw branch -q -m lane-work
NO_ISSUE='{"card": "c6-0", "issue": 0, "title": "First lane commit", "step": "review", "review": 1, "of": 3, "stepAt": "'"$(ago 30)"'", "model": "gpt-x", "tokens": {"claude": 0, "codex": 0}, "usd": 0}'
answer "$(lane_card "$NO_ISSUE" '.belt = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast | .branch == "lane-work" and .landing.state == "belt" and .landing.review == 1' "a branch that names no issue is matched by the title Conveyor gave its card"
q '.panels.belt.data.cards[0].url == null' "a card of no issue has no issue link"
answer "$(lane_card "$(jq -c '.title = "Some other branch"' <<<"$NO_ISSUE")" '.belt = [$c]')" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.lanes.data.records[0].fast.landing == {state: "none"}' "another branch's card of no issue is not this lane's landing"
echo 255 > "$T/ssh-rc"; : > "$T/ssh-out"
run
q '.panels.lanes | .error == null and .data.records[0].fast.ahead == 2 and .data.records[0].fast.landing == null and (.data.cardsError | test("did not answer"))' "with the cards unread the lane still shows its change, and its landing is unknown, never \"not landing\""
) & PIECES+=($!)
( setup lanes-3; fast_lane lane-work
quiet
g worktree add -q -b research-notes "$RSL" main
# The owner's Board said "no worktrees folder is set (CONVEYOR_WORKSPACES)": its lanes were in no folder it could
# find. The host file names each record's lanes, so both show with no environment variable naming a folder.
run CONVEYOR_WORKSPACES=
q '.panels.lanes | .error == null and (.data.records | map([.repo, .fast.present, .fast.branch, .research.present, .research.branch]))
  == [["sample", true, "lane-work", true, "research-notes"], ["widgetshop", null, null, null, null]]' \
  "with the host file naming a record's fast and research lane folders and no environment variable, both lanes show; the record that names none has none"
# A lanes entry that is no folder name is said, never read as no lanes.
cp "$MAIN/conveyor/host.json" "$T/host.lanes"
jq -c '.records[1].lanes = {fast: {worktree: 7}}' "$T/host.lanes" > "$MAIN/conveyor/host.json"
run
q '.panels.lanes == {error: "conveyor/host.json records are not understood", data: null}' "a lane folder that is not a path is not understood, and the panel says so"
mv "$T/host.lanes" "$MAIN/conveyor/host.json"
run
q '.panels.lanes.data.records[0].research == {present: true, branch: "research-notes", ahead: 0, subject: null, first: null, dirty: 0, run: null}' "a Research worktree with no session has no run"
RLOG=$T/userhome/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$RSL"); mkdir -p "$RLOG"
{ echo '{"type":"summary","summary":"x"}'
  echo '{"type":"user","timestamp":"2026-11-09T10:00:00Z","message":{"role":"user","content":"Compare   OCR vendors\nfor passports"}}'
  echo '{"type":"assistant","timestamp":"2026-11-09T10:00:05Z","message":{"content":[{"type":"text","text":"On it."}]}}'; } > "$RLOG/s1.jsonl"
run
q '.panels.lanes.data.records[0].research.run | .startedAt == "2026-11-09T10:00:00Z" and .active == true and .topic == "Compare OCR vendors for passports" and (.lastAt | fromdateiso8601) > 0' "the Research lane's run: when it began, that its record just moved, and how its first prompt opens"
touch -d '-7 minutes' "$RLOG/s1.jsonl"
run
q '.panels.lanes.data.records[0].research.run.active == true' "a session quiet for a few minutes (a long test run) is still working"
touch -d '-11 minutes' "$RLOG/s1.jsonl"
run
q '.panels.lanes.data.records[0].research.run.active == false' "a session whose record has not moved for over 10 minutes is not working"
# A session begun in the main checkout (or a folder of the lane) is filed under that folder; its records' cwd says
# it works in the lane now. The Board read the lane's own folder alone, and showed such a lane as idle.
MLOG=$T/userhome/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$MAIN"); mkdir -p "$MLOG"
{ echo '{"type":"user","timestamp":"2026-11-11T09:00:00Z","cwd":"'"$MAIN"'","message":{"role":"user","content":"Fix the login copy"}}'
  echo '{"type":"assistant","timestamp":"2026-11-11T09:00:05Z","cwd":"'"$FL/web"'","message":{"content":[{"type":"text","text":"Editing."}]}}'
  echo '{"type":"last-prompt","sessionId":"m1"}'; } > "$MLOG/m1.jsonl"
run
q '.panels.lanes.data.records[0].fast.run | .active == true and .topic == "Fix the login copy" and .startedAt == "2026-11-11T09:00:00Z"' "a session working in the Fast lane is its run, wherever it was begun"
q '.panels.lanes.data.records[0].research.run.topic == "Compare OCR vendors for passports"' "a session working in another lane is not this lane's run"
# A session whose latest cwd left the lane, or is a folder whose name only begins like it, is not the lane's run.
{ echo '{"type":"user","timestamp":"2026-11-11T09:00:00Z","cwd":"'"$FL"'","message":{"role":"user","content":"Fix the login copy"}}'
  echo '{"type":"assistant","timestamp":"2026-11-11T09:00:05Z","cwd":"'"$FL-old"'","message":{"content":[{"type":"text","text":"Elsewhere."}]}}'; } > "$MLOG/m1.jsonl"
run
q '.panels.lanes.data.records[0].fast.run == null' "a session that moved out of the lane is not its run"
# A record with one message longer than any tail read still shows the folder it works in.
{ printf '{"type":"user","timestamp":"2026-11-11T09:00:00Z","cwd":"%s","message":{"role":"user","content":"Fix the login copy %s"}}\n' \
    "$FL" "$(head -c 500000 /dev/zero | tr '\0' x)"; } > "$MLOG/m1.jsonl"
run
q '.panels.lanes.data.records[0].fast.run | .active == true and (.topic | startswith("Fix the login copy x")) and .startedAt == "2026-11-11T09:00:00Z"' "a session working in the lane is its run with its prompt, however long that message"
rm -rf "$MLOG"
# A session filed under the lane whose latest cwd has left it is not the lane's run, however fresh.
FLOG=$T/userhome/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$FL"); mkdir -p "$FLOG"
{ echo '{"type":"user","timestamp":"2026-11-11T09:00:00Z","cwd":"'"$FL"'","message":{"role":"user","content":"Fix the login copy"}}'
  echo '{"type":"assistant","timestamp":"2026-11-11T09:00:05Z","cwd":"/elsewhere","message":{"content":[{"type":"text","text":"Elsewhere."}]}}'; } > "$FLOG/s1.jsonl"
run
q '.panels.lanes.data.records[0].fast.run == null' "a session begun in the lane that has left it is not its run"
rm -rf "$FLOG"

# --- what the Foreman's watchers read from the same file ---
q '(.panels.needs.data.decisions | type) == "array" and (.panels.health.data | has("limit") and has("limitError"))' "the decision and limit watchers find their fields"
) & PIECES+=($!)
pieces
) & started lanes

( fresh update
# --- --update brings a checkout behind origin/main forward, a fast-forward only, and restarts on new code ---
ORIG=$T/origin.git UP=$T/up PUSHER=$T/pusher
git init -q --bare -b main "$ORIG"
git clone -q "$ORIG" "$PUSHER" 2>/dev/null
pg() { git -C "$PUSHER" -c user.email=t@t -c user.name=t "$@"; }
pg symbolic-ref HEAD refs/heads/main
mkdir -p "$PUSHER/.claude/scripts"
echo v1 > "$PUSHER/.claude/scripts/dashboard_server.py"; echo v1 > "$PUSHER/README"
pg add -A; pg commit -q -m base; pg push -q origin main
git clone -q "$ORIG" "$UP"
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"'
# upd runs with no fetch stamp, so each run fetches; updkeep keeps the stamp the last run wrote.
upd() { rm -f "$OUT/cache/update-fetched"; updkeep; }
updkeep() {
  : > "$T/systemctl-calls"
  env -u CONVEYOR_HOOK_FIRE_LOG HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$UP" CONVEYOR_WORKSPACES="$WS" \
    CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" timeout 60 bash "$DASH" --update 2>> "$T/update.log"
}
uq() { jq -e "$1" "$OUT/update.json" >/dev/null || fail "$2 (jq: $1; update.json: $(cat "$OUT/update.json"))"; }
# Behind by one commit that changes the page server; an untracked file and a changed file the commit does not touch
# do not hold it.
echo v2 > "$PUSHER/.claude/scripts/dashboard_server.py"; pg commit -q -am "server change"; pg push -q origin main
echo local > "$UP/README"; echo scratch > "$UP/notes.txt"
upd || fail "--update exited non-zero on a checkout it can bring forward: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$(pg rev-parse HEAD)" ] || fail "one --update must fast-forward a checkout behind origin/main"
[ "$(cat "$UP/README")" = local ] && [ -e "$UP/notes.txt" ] || fail "the fast-forward must keep the changed and untracked files it does not touch"
grep -qxF -- '--user --no-block restart dashboard.service' "$T/systemctl-calls" || fail "a move that changes a file the loop runs must restart the service: $(cat "$T/systemctl-calls")"
uq '.error == null and .moved.restart == true and .moved.to == .head and (.moved.at | fromdateiso8601) > 0' "update.json says the checkout moved and the dashboard restarted on it"
run
q '.panels.health.data.update | .error == null and .moved.restart == true' "the Health part carries the update's last word"
# A move that changes no file the loop runs: brought forward, no restart.
echo doc > "$PUSHER/doc.txt"; pg add doc.txt; pg commit -q -m "doc only"; pg push -q origin main
upd || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$(pg rev-parse HEAD)" ] && [ ! -s "$T/systemctl-calls" ] || fail "a move that changes no file the loop runs must not restart: $(cat "$T/systemctl-calls")"
uq '.error == null and .moved.restart == false' "update.json says the checkout moved with no restart"
# A move that changes only what the live feed reads once, at its start (its records' host): a restart.
mkdir -p "$PUSHER/conveyor"; echo '{}' > "$PUSHER/conveyor/host.json"; pg add conveyor; pg commit -q -m "host"; pg push -q origin main
upd || fail "--update exited non-zero: $(cat "$T/update.log")"
grep -qxF -- '--user --no-block restart dashboard.service' "$T/systemctl-calls" || fail "a move that changes conveyor/host.json must restart the service: $(cat "$T/systemctl-calls")"
uq '.error == null and .moved.restart == true' "update.json says the move to a new host.json restarted"
# A restart that fails is reported and retried by the next run, and stays owed through a later move that alone would
# need none.
echo v3 > "$PUSHER/.claude/scripts/dashboard_server.py"; pg commit -q -am "server change 2"; pg push -q origin main
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"; exit 1'
upd && fail "--update must exit non-zero when the restart fails"
uq '(.error | test("restart failed")) and .moved.restartFailed == true' "a failed restart is reported and kept"
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"'
echo doc2 > "$PUSHER/doc.txt"; pg commit -q -am "doc only 2"; pg push -q origin main
upd || fail "--update exited non-zero on the restart retry: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$(pg rev-parse HEAD)" ] || fail "the retry run must still bring a later move forward"
grep -qxF -- '--user --no-block restart dashboard.service' "$T/systemctl-calls" || fail "the next run must retry a failed restart: $(cat "$T/systemctl-calls")"
uq '.error == null and .moved.restart == true and (.moved | has("restartFailed") | not)' "a retried restart clears the failure"
# origin main is fetched at most every 5 minutes, by a stamp (issue 513): each 60 s cycle fetching put a network call
# in every cycle. A stub git counts the fetches and runs git for the rest. Two runs a minute apart fetch once, the
# second using what the first got; a run after the stamp is 5 minutes old fetches again.
stub git 'case " $* " in *" fetch "*) echo fetch >> "'"$T"'/fetches" ;; esac; exec "'"$(command -v git)"'" "$@"'
rm -f "$OUT/cache/update-fetched"; : > "$T/fetches"
echo doc3 > "$PUSHER/doc.txt"; pg commit -q -am "doc only 3"; pg push -q origin main
updkeep || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(wc -l < "$T/fetches")" -eq 1 ] && [ "$(git -C "$UP" rev-parse HEAD)" = "$(pg rev-parse HEAD)" ] || fail "a run with no stamp must fetch and move: $(wc -l < "$T/fetches") fetch(es)"
# The first run wrote the stamp; the test only ages that stamp, so a run that writes none fails here.
stamped() { at=$(cat "$OUT/cache/update-fetched" 2>/dev/null) && [[ $at =~ ^[0-9]+$ ]] && [ $(($(date +%s) - at)) -lt 30 ]; }
stamped || fail "a run that fetches must write the fetch stamp: '$(cat "$OUT/cache/update-fetched" 2>&1)'"
echo $((at - 60)) > "$OUT/cache/update-fetched"
here=$(git -C "$UP" rev-parse HEAD)
echo doc4 > "$PUSHER/doc.txt"; pg commit -q -am "doc only 4"; pg push -q origin main
updkeep || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(wc -l < "$T/fetches")" -eq 1 ] && [ "$(git -C "$UP" rev-parse HEAD)" = "$here" ] || fail "a run a minute after the last fetch must not fetch, and stays where that fetch got it: $(wc -l < "$T/fetches") fetch(es)"
uq '.error == null' "a run with no fetch is not an error"
at=$(cat "$OUT/cache/update-fetched"); echo $((at - 240)) > "$OUT/cache/update-fetched"
updkeep || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(wc -l < "$T/fetches")" -eq 2 ] && [ "$(git -C "$UP" rev-parse HEAD)" = "$(pg rev-parse HEAD)" ] || fail "a run after the stamp is 5 minutes old must fetch again and move: $(wc -l < "$T/fetches") fetch(es)"
stamped || fail "a run that fetches again must write a new stamp"
rm -f "$BIN/git"
# A fast-forward that would overwrite a changed file: git refuses, and the reason is reported, autostash set or not.
git -C "$UP" config merge.autoStash true
echo v3 > "$PUSHER/README"; pg commit -q -am "readme"; pg push -q origin main
here=$(git -C "$UP" rev-parse HEAD)
upd || fail "a refused fast-forward is reported, not a failed run: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$here" ] && [ "$(cat "$UP/README")" = local ] && [ ! -s "$T/systemctl-calls" ] || fail "a fast-forward that would overwrite a changed file must leave the checkout as it is"
uq '(.error | test("refused the fast-forward")) and .moved.to == .head' "the refusal is reported, and the last move is kept"
# A local commit: the checkout is left alone and the reason reported.
git -C "$UP" -c user.email=t@t -c user.name=t commit -q -am "local work"
here=$(git -C "$UP" rev-parse HEAD)
upd || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$here" ] && [ ! -s "$T/systemctl-calls" ] || fail "a checkout with a local commit must be left alone"
uq '.error == "main has 1 commit(s) that origin/main does not; it is left as it is"' "a local commit is reported with its reason"
run
q '.panels.health.data.update.error | test("main has 1 commit")' "the page reads why the checkout was not brought forward"
# Another branch: left alone.
git -C "$UP" switch -q -c side
upd || fail "--update exited non-zero: $(cat "$T/update.log")"
[ "$(git -C "$UP" rev-parse HEAD)" = "$here" ] || fail "a checkout on another branch must be left alone"
uq '.error == "the checkout is on side, not main; it is left as it is"' "another branch is reported with its reason"
# A fetch that fails says git's fatal line, not its last: that is "and the repository exists.", the end of a hint,
# which Health showed as the reason (issue 415).
git -C "$UP" switch -q main
git -C "$UP" remote set-url origin "$T/no-such.git"
upd || fail "--update exited non-zero on a failed fetch: $(cat "$T/update.log")"
uq '(.error | startswith("origin/main could not be fetched: fatal:")) and (.error | test("repository exists") | not)' "a failed fetch is reported by git's fatal line"
git -C "$UP" remote set-url origin "$ORIG"
rm -f "$BIN/systemctl" "$OUT/update.json"

# --- only what the script was asked for ---
rc=0; env HOME="$T/userhome" CONVEYOR_MAIN="$MAIN" CONVEYOR_DASHBOARD_DIR="$OUT" bash "$DASH" --follow > "$T/usage.out" 2>&1 || rc=$?
[ "$rc" = 2 ] && grep -qF 'usage: dashboard.sh [--install|--uninstall|--restart|--loop|--publish|--update|--history|--work|--older <repo> <test file>|--donewhen <repo> <card id>|--shot <repo> <card> <file>|--excerpts <repo> <card id>|--bench <repo> [<run>]|--check]' "$T/usage.out" || fail "an argument the collector does not have is refused with its usage: rc=$rc $(cat "$T/usage.out")"

# --- the strip-down holds: the retired workflow is named nowhere in the collector, the page or their tests ---
# Comments count as well as the page's text: a panel's comment (bench.js, on an arm checked on the default run
# settings) that named the retired word for a check that succeeded failed this case on main (#753).
# "seat" is not on the list: it now names a card's builder, reviewer and judge (docs/board.md), not the retired workflow.
# The collector's own tests are three files: this one, dashboard.test.sh and dashboard-cards.test.sh.
RETIRED='\b([u]nits?|[p]ass(es)?|[m]erge queue|[c]hain)\b'
found=$(grep -n -i -E "$RETIRED" "${DASH%.sh}"*.sh "$VIEW"/*.* "$VIEW"/panels/*.js "$SOURCE"/.claude/scripts/__tests__/dashboard.test.sh \
  "$SOURCE"/.claude/scripts/__tests__/dashboard-cards.test.sh "$SOURCE"/.claude/scripts/__tests__/dashboard-local.test.sh \
  "$SOURCE"/.claude/scripts/__tests__/dashboard-view.*.mjs | grep -v -E ':[0-9]+:\[[U]nit\]$' \
  | grep -v -E '/dashboard-view\.bench[^/]*\.mjs:[0-9]+:' || true)
# Exempt: the Benchmarks tab's tests (dashboard-view.bench*.mjs). They check the tab's texts, which use SWE-bench's
# own names for a test's result ("fail-to-[p]ass"), not the retired workflow; the tab's parts/ are not scanned either.
# Exempt: the service file's section header, a line that is only that header. Any other line still fails: the
# header's text anywhere in a line used to exempt it, so this check's own line could hide a retired word beside it.
[ -z "$found" ] || fail "the retired workflow is still named (the service file's own section header aside): $found"
) & started update

( fresh install
# The page's folder as a collect leaves it, data.js and all, which an install copies the page beside.
quiet; run
# --- install refuses missing files and copies the page beside data.js ---
# bootout returns before launchd has removed the job, and a bootstrap in that window fails with "Input/output
# error"; the stub keeps the old job listed for two prints after bootout, so install must wait for it to go.
stub launchctl 'echo "$*" >> "'"$T"'/launchctl-calls"; L="'"$T"'/launchctl-left"
case "$1" in
  bootout) echo 2 > "$L" ;;
  print) n=$(cat "$L" 2>/dev/null || echo 0); [ "$n" -gt 0 ] || exit 1; echo $((n-1)) > "$L"; exit 0 ;;
  bootstrap) [ "$(cat "$L" 2>/dev/null || echo 0)" -eq 0 ] || exit 5 ;;
esac
[ -z "${LAUNCHCTL_FAIL:-}" ] || [ "$1" != bootstrap ] || exit 1'
inst() {
  env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Darwin CONVEYOR_MAIN="$MAIN" \
    CONVEYOR_DASHBOARD_DIR="$OUT" "$@" bash "$DASH" --install
}
PL=$T/userhome
PL=$PL/Library/LaunchAgents/com.conveyor.dashboard.plist
mkdir -p "${PL%/*}" "$MAIN/.claude/scripts"
echo 'previous job' > "$PL"
cp -R "$VIEW" "$MAIN/.claude/dashboard"
cp "$SOURCE"/.claude/scripts/dashboard*.sh "$SOURCE"/.claude/scripts/dashboard_server*.py "$MAIN/.claude/scripts/"
view_list() { (cd "$MAIN/.claude/dashboard" && find . -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.svg' \) | sed 's|^\./||' | LC_ALL=C sort); }
for f in scripts/dashboard.sh dashboard/index.html dashboard/app.css dashboard/app.js; do
  mv "$MAIN/.claude/$f" "$T/held"
  rm -f "$T/launchctl-calls"
  ! inst > "$T/inst.log" 2>&1 || fail "--install must fail without $f"
  grep -qF "$MAIN/.claude/$f" "$T/inst.log" || fail "--install must name the missing $f"
  grep -qx 'previous job' "$PL" || fail "a refused install must not replace the existing job"
  [ ! -e "$T/launchctl-calls" ] || fail "a refused install must not touch launchd"
  mv "$T/held" "$MAIN/.claude/$f"
done
chmod a-w "$OUT"
! inst > "$T/inst.log" 2>&1 || fail "--install must fail when the page cannot be copied"
grep -qx 'previous job' "$PL" || fail "a failed copy must not replace the existing job"
chmod u+w "$OUT"
# A restart that would serve a login nobody can get through (No login on this device off, and no admin with a
# password) refuses before launchd is touched, so the old server keeps serving. The store checked is the one the
# restarted job serves: an override set at install time is forwarded to it.
AUTHD=$T/userhome/.claude/rulings/dashboard-auth.json VALID=$T/valid-auth.json OFF=$T/off-auth.json NONE=$T/none-auth.json
mkdir -p "${AUTHD%/*}"; echo '{"noLoginHere": false}' | tee "$OFF" > "$AUTHD"; echo '{}' > "$NONE"; rm -f "$T/launchctl-calls"
python3 -c 'import hashlib, json; s = b"0" * 16; print(json.dumps(dict(epoch=1, noLoginHere=False, users=dict(max=dict(role="admin", salt=s.hex(), n=2, r=1, p=1, epoch=1,
  hash=hashlib.scrypt(b"password1", salt=s, n=2, r=1, p=1, dklen=32).hex())))))' > "$VALID"
! inst > "$T/inst.log" 2>&1 || fail "--install must refuse when No login on this device is off and the auth store holds no password"
grep -qF "$AUTHD" "$T/inst.log" || fail "the refusal must name the store it read: $(cat "$T/inst.log")"
[ ! -e "$T/launchctl-calls" ] || fail "a refused install must not boot the running job out: $(cat "$T/launchctl-calls")"
grep -qx 'previous job' "$PL" || fail "a refused install must not replace the existing job"
# A hash with no salt, user or scrypt parameters fails every login, so it is no password either.
echo '{"hash":"h","noLoginHere":false}' > "$AUTHD"
! inst > "$T/inst.log" 2>&1 || fail "--install accepted a store with a hash but no salt, user or scrypt parameters"
[ ! -e "$T/launchctl-calls" ] && grep -qx 'previous job' "$PL" || fail "a store no login can use still touched the running job"
rm -f "$AUTHD"
inst CONVEYOR_DASHBOARD_AUTH="$VALID" > "$T/inst.log" 2>&1 || fail "an override store that holds a hash was refused: $(cat "$T/inst.log")"
grep -qF "<key>CONVEYOR_DASHBOARD_AUTH</key><string>$VALID</string>" "$PL" \
  || fail "the job does not carry the auth store the preflight read, so it would serve the empty default: $(cat "$PL")"
cp "$VALID" "$AUTHD"; echo 'previous job' > "$PL"; rm -f "$T/launchctl-calls"
! inst CONVEYOR_DASHBOARD_AUTH="$OFF" > "$T/inst.log" 2>&1 || fail "an override store with no password was accepted because the default store has a hash"
[ ! -e "$T/launchctl-calls" ] && grep -qx 'previous job' "$PL" || fail "an override store with no password still touched the running job"
# Bug caught (#108): the first install needed a typed admin password, so an agent could not start the Board. With no
# user at all and No login on this device at its default (on), this machine gets in, so the install goes ahead.
inst CONVEYOR_DASHBOARD_AUTH="$NONE" < /dev/null > "$T/inst.log" 2>&1 || fail "a store with no user, with No login on this device on, was refused: $(cat "$T/inst.log")"
grep -q 'bootstrap' "$T/launchctl-calls" || fail "the install with no user did not start the job: $(cat "$T/launchctl-calls" 2>&1)"
! inst LAUNCHCTL_FAIL=1 >/dev/null 2>&1 || fail "--install must fail when launchd refuses the job"
inst > /dev/null || fail "--install failed"
[ "$(view_list | wc -l)" -ge 11 ] || fail "the page is its core files and one file for each panel: $(view_list | tr '\n' ' ')"
while IFS= read -r f; do cmp -s "$MAIN/.claude/dashboard/$f" "$OUT/$f" || fail "install must copy $f beside data.js"; done < <(view_list)
grep -qF "<string>--loop</string>" "$PL" || fail "the job must run the collect loop"
grep -qF "$MAIN/.claude/scripts/dashboard.sh" "$PL" || fail "the job must run the primary checkout's script"
grep -q 'bootstrap' "$T/launchctl-calls" || fail "install must bootstrap the job"
# The page is served over HTTPS only, so an install makes the self-signed certificate once and a second install keeps it.
CERT_DIR=$T/userhome/.claude/rulings/dashboard-tls
[ -s "$CERT_DIR/cert.pem" ] && [ -s "$CERT_DIR/key.pem" ] || fail "install_makes_the_certificate: no certificate in $CERT_DIR"
CERT_SUM=$(cksum < "$CERT_DIR/cert.pem")
inst > /dev/null || fail "--install failed the second time"
[ "$(cksum < "$CERT_DIR/cert.pem")" = "$CERT_SUM" ] || fail "install_keeps_the_certificate: a second install replaced the certificate"
env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Darwin CONVEYOR_MAIN="$MAIN" \
  bash "$DASH" --uninstall >/dev/null || fail "--uninstall failed"
[ ! -e "$PL" ] || fail "uninstall must remove the plist"
grep -q 'bootout' "$T/launchctl-calls" || fail "uninstall must boot the job out"
# The Linux service: each word of the command is quoted, so a path with a space is one word, and a
# service that is already running is restarted.
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"'
linst() { env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_DASHBOARD_DIR="$OUT" "$@" bash "$DASH" --install; }
SVCF=$T/userhome/.config/systemd/user/dashboard.service
cp "$OFF" "$AUTHD"; rm -f "$T/systemctl-calls"
! linst > "$T/inst.log" 2>&1 || fail "a Linux --install must refuse when No login on this device is off and the auth store holds no password"
[ ! -e "$T/systemctl-calls" ] || fail "a refused Linux install restarted the service: $(cat "$T/systemctl-calls")"
linst CONVEYOR_DASHBOARD_AUTH="$VALID" > "$T/inst.log" 2>&1 || fail "a Linux override store that holds a hash was refused: $(cat "$T/inst.log")"
grep -qxF "Environment=\"CONVEYOR_DASHBOARD_AUTH=$VALID\"" "$SVCF" || fail "the service does not carry the auth store the preflight read: $(cat "$SVCF")"
cp "$VALID" "$AUTHD"; rm -f "$T/systemctl-calls"
! linst CONVEYOR_DASHBOARD_AUTH="$OFF" > "$T/inst.log" 2>&1 || fail "a Linux override store with no password was accepted because the default store has a hash"
[ ! -e "$T/systemctl-calls" ] || fail "a Linux override store with no password still restarted the service"
linst >/dev/null || fail "--install failed on Linux"
grep -qE '^ExecStart="[^"]+" "[^"]+/dashboard\.sh" --loop$' "$SVCF" || fail "the service's command is not quoted: $(grep ExecStart "$SVCF")"
grep -q -- '--user restart dashboard.service' "$T/systemctl-calls" || fail "a Linux install did not restart the running service: $(cat "$T/systemctl-calls")"
# A release installed as a git clone (plan section 7), for a project that carries no Board of its own, installs
# its own files, not the project's.
# Bug caught: a Board in any git checkout took CONVEYOR_MAIN's files and refused the project's missing dashboard.sh.
REL=$T/release PROJ=$T/project
mkdir -p "$REL/.claude/scripts" "$PROJ"
cp -R "$VIEW" "$REL/.claude/dashboard"
cp "$SOURCE"/.claude/scripts/dashboard*.sh "$SOURCE"/.claude/scripts/dashboard_server*.py "$REL/.claude/scripts/"
git -C "$REL" init -q -b main
env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$PROJ" CONVEYOR_DASHBOARD_DIR="$OUT" \
  bash "$REL/.claude/scripts/dashboard.sh" --install > "$T/inst.log" 2>&1 \
  && grep -qxF "ExecStart=\"$BASH\" \"$REL/.claude/scripts/dashboard.sh\" --loop" "$SVCF" \
  || fail "a git-clone release must install its own Board: $(cat "$T/inst.log") $(grep ExecStart "$SVCF")"
rm -f "$BIN/systemctl"

# --- the loop serves the page to other machines on the LAN, and its server ends with it (a leftover would hold
# the port against the next job) ---
# The port is free when picked and the server binds it later. A port the kernel handed out (bind to 0) is in the
# ephemeral range, where any outgoing connection, or another test's bind to 0, can take it in that gap and the server
# fails to start; a free port below that range is only taken by a bind that names it.
port=$(python3 -c '
import random, socket
try: low = int(open("/proc/sys/net/ipv4/ip_local_port_range").read().split()[0])
except OSError: low = 49152
while True:
    p = random.randrange(10000, low)
    with socket.socket() as s:
        try: s.bind(("", p))
        except OSError: continue
    print(p); break')
lan=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$lan" ] || fail "no LAN address to test the page from"
rm -f "$OUT/data.js"  # a fresh install: the page is up before the first collect lands
# A page fix landed in the primary checkout reaches the running loop on its next cycle, with no reinstall;
# a page file that did not change is not rewritten.
printf '/* landed page fix */\n' >> "$MAIN/.claude/dashboard/app.css"
printf '// landed panel fix\n' >> "$MAIN/.claude/dashboard/panels/belt.js"
touch -d '-1 hour' "$OUT/index.html"
idx_stat=$(stat -c '%i %Y' "$OUT/index.html")
# The loop's server is HTTPS behind a login. The certificate names localhost, so the LAN address is reached
# with --resolve; the password is set through the server's own command, in a store of this test's.
AUTHL=$T/auth; SRVPY=${DASH%/*}/dashboard_server.py; DPW='a long enough password'
CONVEYOR_DASHBOARD_AUTH=$AUTHL/dashboard-auth.json "$PY" "$SRVPY" make-cert >/dev/null || fail "the loop's HTTPS certificate could not be made"
printf '%s\n%s\n' "$DPW" "$DPW" | CONVEYOR_DASHBOARD_AUTH=$AUTHL/dashboard-auth.json "$PY" "$SRVPY" set-password max >/dev/null || fail "the loop's password could not be set"
# The loop starts on an empty certificate, which the server cannot load. Bug caught (#200): the server failed on
# every start and the Board stayed down; the loop must make it again, say so once in its log, and serve.
: > "$AUTHL/dashboard-tls/cert.pem"
DU=https://localhost:$port
dcurl() { curl --cacert "$AUTHL/dashboard-tls/cert.pem" --resolve "localhost:$port:$lan" -b "$AUTHL/jar" "$@"; }
# The loop itself brings the checkout forward each cycle, with no --update typed. Its origin is one commit
# ahead with a file the loop runs, so the cycle must fast-forward and restart the service.
MORIG=$T/main-origin.git MPUSH=$T/main-pusher
git init -q --bare -b main "$MORIG"; g remote add origin "$MORIG"; g push -q origin main
git clone -q "$MORIG" "$MPUSH" 2>/dev/null
mkdir -p "$MPUSH/.claude/scripts"; echo v2 > "$MPUSH/.claude/scripts/dashboard_stream.py"
git -C "$MPUSH" add -A; git -C "$MPUSH" -c user.email=t@t -c user.name=t commit -q -m "stream change"; git -C "$MPUSH" push -q origin main
stub systemctl 'echo "$*" >> "'"$T"'/systemctl-calls"'; : > "$T/systemctl-calls"
quiet
# A feed that ended mid-write left its temp files; each new feed names its own, so the loop must remove these.
echo '{"partial":' > "$OUT/.stream.json.123"; echo '{"partial":' > "$OUT/.stream.json.456"
env HOME="$T/userhome" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" CONVEYOR_DASHBOARD_AUTH="$AUTHL/dashboard-auth.json" \
  CONVEYOR_WORKSPACES="$WS" CONVEYOR_SCRATCH="$SCR" CONVEYOR_DASHBOARD_DIR="$OUT" \
  CONVEYOR_DASHBOARD_PORT="$port" bash "$DASH" --loop > "$T/loop.log" 2>&1 &
loop=$!
stop() { kill "$loop" 2>/dev/null || true; fail "$1"; }
wait_until 'dcurl -sf -m 1 -o /dev/null "$DU/login" || ! kill -0 "$loop" 2>/dev/null' || :
dcurl -sf -m 1 -o /dev/null "$DU/login" || stop "the page is not served over https on $lan:$port: $(cat "$T/loop.log")"
[ "$(grep -c "dashboard: certificate $AUTHL/dashboard-tls/cert.pem is empty: making a new one$" "$T/loop.log")" = 1 ] \
  || stop "loop_makes_an_empty_certificate_again: the log must say once that the empty certificate was made again: $(cat "$T/loop.log")"
[ "$(dcurl -s -m 2 -o /dev/null -w '%{http_code}' "$DU/index.html")" = 302 ] || stop "loop_serves_https_behind_login: the page opened without a login"
[ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://$lan:$port/index.html")" = 000 ] || stop "loop_serves_https_behind_login: plain http got an answer"
dcurl -sf -m 5 -c "$AUTHL/jar" -o /dev/null -X POST -H "Origin: $DU" -H 'Content-Type: application/json' \
  --data-binary "{\"user\":\"max\",\"password\":\"$DPW\",\"trust\":false,\"label\":\"\"}" "$DU/login" || stop "the loop's login was refused"
dcurl -sf -m 5 "$DU/index.html" > "$T/served.html" || stop "the page is not served after the login"
cmp -s "$OUT/index.html" "$T/served.html" || stop "the served page must be the installed one"
dcurl -sf -m 5 "$DU/panels/belt.js" > "$T/served-belt.js" || stop "a panel's file is not served from its folder"
# The header's mark is the Conveyor logo (the C path and the card rectangle), and the tab icon is served as SVG.
grep -qF '<svg class="brand-mark" aria-hidden="true"' "$T/served.html" \
  && grep -qF '<path d="M42.5 20.5A16 16 0 1 0 42.5 43.5"' "$T/served.html" \
  && grep -qF '<rect x="35" y="26.5" width="16" height="11" rx="3"' "$T/served.html" \
  || stop "page_shows_the_logo: the header must hold the Conveyor mark's SVG"
grep -qF '<link rel="icon" type="image/svg+xml" href="icon.svg">' "$T/served.html" || stop "page_names_its_tab_icon: no SVG icon link"
dcurl -sf -m 5 -D "$T/icon.head" -o "$T/served-icon.svg" "$DU/icon.svg" || stop "page_names_its_tab_icon: icon.svg is not served"
grep -qi '^content-type: image/svg+xml' "$T/icon.head" && cmp -s "$MAIN/.claude/dashboard/icon.svg" "$T/served-icon.svg" \
  || stop "page_names_its_tab_icon: icon.svg must be served as image/svg+xml: $(cat "$T/icon.head")"
# The server starts before the first collect publishes data.js, so wait for that too, while the loop lives.
wait_until '[ -s "$OUT/data.js" ] || ! kill -0 "$loop" 2>/dev/null' || :
[ -s "$OUT/data.js" ] || stop "data.js must be served beside the page: the loop ended, or hung, before its first collect: $(cat "$T/loop.log")"
[ -z "$(find "$OUT" -maxdepth 1 -name '.stream.json.*' | head -n 1)" ] || stop "loop_clears_stream_temps: the temp files an ended feed left are kept: $(ls -A "$OUT")"
dcurl -sf -m 5 "$DU/data.js" > "$T/served.js" || stop "data.js must be served beside the page"
head -c 14 "$T/served.js" | grep -qF 'window.DASH = ' || stop "the served data.js must assign window.DASH"
# alive.js is the loop's heartbeat: the page tells a slow cycle (heartbeat fresh, data.js old) from a stopped
# collector (no heartbeat) by it. The first cycle's end stamps its length.
# One copy is waited on and checked: a heartbeat that read the cycle before it was timed can replace alive.js after.
wait_until 'cp "$OUT/alive.js" "$T/alive.js" 2>/dev/null && grep -qE "\"lastCycleSec\":[0-9]+" "$T/alive.js" || ! kill -0 "$loop" 2>/dev/null' || :
grep -qE '"lastCycleSec":[0-9]+' "$T/alive.js" 2>/dev/null || stop "the loop must write alive.js with the cycle it timed: $(cat "$T/alive.js" 2>&1)"
sed -e '1s/^window\.DASH_ALIVE = //' -e '$s/;$//' "$T/alive.js" \
  | jq -e '(.at | fromdateiso8601) > 0 and (.cycleStartedAt | fromdateiso8601) > 0 and (.lastCycleSec | type) == "number"' >/dev/null \
  || stop "alive.js must assign window.DASH_ALIVE = {at, cycleStartedAt, lastCycleSec}: $(cat "$T/alive.js")"
wait_until 'grep -qxF -- "--user --no-block restart dashboard.service" "$T/systemctl-calls" || ! kill -0 "$loop" 2>/dev/null' || :
grep -qxF -- '--user --no-block restart dashboard.service' "$T/systemctl-calls" \
  || stop "loop_runs_the_update: the cycle must restart the service on new code: $(cat "$OUT/update.json" "$T/loop.log" 2>&1)"
[ "$(git -C "$MAIN" rev-parse HEAD)" = "$(git -C "$MPUSH" rev-parse HEAD)" ] && jq -e '.error == null and .moved.restart == true' "$OUT/update.json" >/dev/null \
  || stop "loop_runs_the_update: the cycle must fast-forward the checkout and say so in update.json: $(cat "$OUT/update.json" 2>&1)"
cmp -s "$MAIN/.claude/dashboard/app.css" "$OUT/app.css" && cmp -s "$MAIN/.claude/dashboard/panels/belt.js" "$OUT/panels/belt.js" \
  || stop "loop_refreshes_the_page: a changed page file, a panel's included, must be served after the next cycle"
[ "$(stat -c '%i %Y' "$OUT/index.html")" = "$idx_stat" ] || stop "loop_refreshes_the_page: an unchanged page file must not be rewritten"
# The heartbeat carries a stamp of the installed page files, so a page left open sees an update and reloads.
[ "$(sed -e '1s/^window\.DASH_ALIVE = //' -e '$s/;$//' "$OUT/alive.js" | jq -r .view)" = "$(view_list | (cd "$OUT" && xargs -d '\n' cat) | cksum | cut -d' ' -f1)" ] \
  || stop "heartbeat_stamps_the_page: alive.js must carry the checksum of every installed page file: $(cat "$OUT/alive.js")"
# The page keeps its layout in the browser: the loop's server takes no layout and writes none.
[ "$(dcurl -s -m 2 -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' -H "Origin: $DU" --data-binary '{"order":["belt"]}' "$DU/layout")" = 501 ] \
  && [ ! -e "$OUT/layout.js" ] || stop "loop_keeps_no_layout: the server took a layout, or a layout file was written: $(ls "$OUT")"
# On the main checkout the live dashboard service is another `dashboard.sh --loop` of this very script, hours old.
# A stand-in plays it: only the loop this test started, and its children, must be gone.
( exec -a "bash $DASH --loop" sleep 30 ) & standin=$! # sleep: the stand-in, alive under the live service's name
kids=$(pgrep -P "$loop" -f -- "$DASH --loop" | tr '\n' ' ')  # the heartbeat subshell, not the cycle's own sleep
[ -n "$kids" ] || { kill "$loop" "$standin"; fail "the loop has a heartbeat child to watch"; }
kill "$loop"; wait "$loop" 2>/dev/null || true
wait_until '! curl -s -m 1 -o /dev/null --cacert "$AUTHL/dashboard-tls/cert.pem" "https://127.0.0.1:$port/login"' \
  || { kill "$standin"; fail "the page server must stop with the loop"; }
# A heartbeat that outlives its loop reads alive forever. A deadline, not a poll count: a slow process list must
# not wait out the heartbeat's own 15 s sleep.
alive_kids() { local p; for p in $kids; do ! kill -0 "$p" 2>/dev/null || ps -o pid=,command= -p "$p"; done; }
end=$((SECONDS + 3)); while [ -n "$(alive_kids)" ]; do
  [ $SECONDS -lt $end ] || { kill "$standin"; fail "loop_check_ignores_another_loop: the heartbeat must stop with the loop: $(alive_kids)"; }; sleep 0.1
done
kill -0 "$standin" 2>/dev/null || fail "loop_check_ignores_another_loop: the stand-in for the live service must still be running"
kill "$standin"; wait "$standin" 2>/dev/null || true
) & started install

( fresh queuewait
# Bug (issue 19): an issue waiting on another (sample's #16 on #7) with nothing else queued must still reach the Queue
# part, on the whole Board and, when the other record's issues were not listed, in byRepo for its own project.
W16='{"queue": {"next": [], "waiting": [{"issue": 16, "title": "Second half", "waitsFor": [7], "forced": false}]}}'
answer "$(snap "$W16")" "$P_URL" 0 "$(snap)" "$C_URL" 0
run
q '.panels.queue.data | .next == [] and (.waiting | map([.repo, .issue, .waitsFor])) == [["sample", 16, [7]]]' \
  "every project: the Queue part's waiting has the issue that waits on another, with next empty"
answer "$(snap "$W16")" "$P_URL" 0 "$(snap '{"queue": {"next": null}}')" "$C_URL" 0
run
q '.panels.queue.data | .waiting == null and (.byRepo.sample.waiting | map([.repo, .issue, .waitsFor])) == [["sample", 16, [7]]]
  and .byRepo.sample.next == [] and .byRepo.widgetshop.waiting == null' \
  "byRepo: its own project's part has the waiting issue when another project's issues were not listed"
) & started queuewait

# Every part ended and passed; a part that failed stopped at its FAIL line, above.
bad=()
for p in "${PARTS[@]}"; do wait "${p#*:}" || bad+=("${p%%:*}"); done
[ ${#bad[@]} -eq 0 ] || fail "these parts failed (their FAIL lines are above): ${bad[*]}"
echo "ok: dashboard-local"
