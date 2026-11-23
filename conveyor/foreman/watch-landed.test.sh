#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on awaited issues that land: one poll (--once) at a time of a
# snapshot given by CONVEYOR_FOREMAN_ASK; each case has a record of its own.
# Bug (#1263): the watcher woke the Foreman once for each awaited issue that landed, so a batch of nine cards gave nine
# wakes, each a whole turn of the Foreman's session, most of them needing nothing. A landing now waits while another
# awaited issue of its record is on the belt, and the landings of the batch wake in one.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0
mkdir -p "$T/home" "$T/config/conveyor"
check() { if "${@:2}"; then echo "ok [watch-landed]: $1"; else echo "FAIL [watch-landed]: $1" >&2; fails=$((fails + 1)); fi; }
nope() { ! "$@"; }
# The record <repo>, its main $T/<repo>, awaiting the issues given; its snapshot is $T/<repo>.json (see snap).
fixture() { # <repo> <issue>...
  git init -q "$T/$1" && mkdir -p "$T/$1/.conveyor" "$T/$1.fd" && echo '{}' > "$T/$1/.conveyor/project.json" \
    && jq -n --arg m "$T/$1" --arg r "$1" '{records: [{repo: $r, main: $m}]}' > "$T/config/conveyor/host-$1.json" \
    && printf '%s\n' "${@:2}" > "$T/$1.fd/await-$1.txt"
}
# The snapshot: the issues on the belt (building), the issues pushed (each with a landed commit, its number as 12 hex digits)
# and the issues blocked; a jq filter after them changes it.
snap() { # <repo> <belt issues> <pushed issues> <blocked issues> [<jq filter>]
  jq -n --argjson belt "[${2:-}]" --argjson pushed "[${3:-}]" --argjson blocked "[${4:-}]" '{queue: {next: [{issue: 99}]}, open: {held: []}, suites: [],
    belt: [$belt[] | {card: "c\(.)", issue: ., step: "build"}], pushedCards: [$pushed[] | {card: "c\(.)", issue: ., sha: "\(. + 100000000000 | tostring)abcdef"}],
    landed: [$pushed[] | {card: "c\(.)", issue: ., sha: "\(. + 100000000000 | tostring)abcdef"}],
    health: {time: "2026-11-17T08:00:00Z", loop: true, gh: true, stuck: [], waiting: [], pushFailingSince: null,
      blocked: [$blocked[] | {card: "c\(.)", issue: ., since: "2026-11-17T07:00:00Z", reason: "the review found a flaw"}]}} | '"${5:-.}" > "$T/$1.json"
}
poll() { # <repo>: one poll; 0 with a wake put in pending, which goes to $T/<repo>.wake. While $T/<repo>.nohist is there, the history does not read.
  rm -f "$T/$1.fd"/pending/*.wake "$T/$1.wake"; cp "$T/config/conveyor/host-$1.json" "$T/config/conveyor/host.json"
  HOME=$T/home XDG_CONFIG_HOME=$T/config CONVEYOR_MAIN=$T/$1 CONVEYOR_FOREMAN_DIR=$T/$1.fd CONVEYOR_FOREMAN_NOW=1794902400 \
    CONVEYOR_FOREMAN_ASK="[ \"\$CONVEYOR_CMD\" != history ] || [ ! -e $T/$1.nohist ] || exit 1; cat $T/$1.json" bash "$SRC/watch-conveyor.sh" --once 2>> "$T/$1.err" && cat "$T/$1.fd"/pending/*.wake > "$T/$1.wake"
}
has() { grep -qxF -- "$2" "$T/$1.wake"; } # <repo> <whole line>

# Three awaited issues in flight. Bug it catches: a wake for #1 and another for #2, before #3 had landed.
fixture batch 1 2 3
snap batch '1, 2, 3'
check 'nothing landed: no wake' nope poll batch
snap batch '2, 3' 1
check 'the first of three landed: no wake' nope poll batch
snap batch 3 '1, 2'
check 'the second of three landed: no wake' nope poll batch
snap batch '' '1, 2, 3'
check 'the third landed: one wake' poll batch
check 'the wake names the three landings and their commits' test "$(cat "$T/batch.wake")" = "Conveyor: batch: landed: #1 #2 #3
batch: #1 landed as 100000000001: your step is due
batch: #2 landed as 100000000002: your step is due
batch: #3 landed as 100000000003: your step is due"
check 'the three landings are not named again' nope poll batch

# Bug it catches: a held landing that waited for a quiet belt while a follow-up needing the Foreman went unsaid.
fixture follow 1 2
snap follow 2 1
check 'one landing held, the other still building: no wake' nope poll follow
snap follow 2 1 '' '.needsYou = {waiting: [], blocked: [], before: [], pipeline: [{issue: 615, title: "the fix skips a step", parent: 597, since: "2026-11-17T07:00:00Z"}]}'
check 'a held pipeline change wakes at once, with a landing held' poll follow
check 'the wake names the pipeline change' has follow 'follow: pipeline change held: #615 (follow-up of #597): the fix skips a step'
check 'the wake also names the held landing, so it is not woken for again' has follow 'follow: #1 landed as 100000000001: your step is due'
check 'the landing is not named again' nope poll follow

# Bug it catches: a landing held for a card that is blocked, which wakes itself and will not land soon.
fixture blocked 1 2
snap blocked '' 1 2
check 'a landing while the other awaited card is blocked wakes at once' poll blocked
check 'the wake names the landing and the block' test "$(grep -c '^blocked: #[12] ' "$T/blocked.wake")" = 2

# Bug it catches: a landing held for an awaited issue that is not on the belt (it has not begun), or for a card of no
# interest to the Foreman on the belt, so the wake never came.
fixture alone 1 2
snap alone 50 1
check 'an awaited issue landed while no other awaited issue is in flight: wake at once' poll alone
check 'the wake names it and its commit' has alone 'alone: #1 landed as 100000000001: your step is due'

# Bug it catches: held landings lost when the waiter restarts, so the Foreman never hears of them. The waiter's pid is
# the first field of waiter.pid; a new waiter has another.
fixture restart 1 2
snap restart 2 1
echo '4001 - 77 sid' > "$T/restart.fd/waiter.pid"
check 'a landing held under the first waiter: no wake' nope poll restart
check 'the same waiter a poll later: still no wake' nope poll restart
echo '4002 - 77 sid' > "$T/restart.fd/waiter.pid"
check 'a restarted waiter sends the held landing at once' poll restart
check 'the wake names it and its commit' has restart 'restart: #1 landed as 100000000001: your step is due'

# Bug it catches: a held landing that lost its commit when the batch ended on a later day, as the snapshot lists a day's
# landings only, and one that was held again after a restart when the first snapshot after it did not read.
fixture later 1 2
snap later 2 1
check 'a landing held on its day: no wake' nope poll later
# #1's push names no commit either, so only the commit saved while it was held can name it.
snap later '' '1, 2' '' 'del(.landed[] | select(.issue == 1)) | del(.pushedCards[] | select(.issue == 1) | .sha)'
check 'the batch ends on a later day: one wake' poll later
check 'it still names the commit of the landing of the day before' has later 'later: #1 landed as 100000000001: your step is due'
check 'and the commit of the last landing' has later 'later: #2 landed as 100000000002: your step is due'

fixture failed 1 2
snap failed 2 1
echo '4001 - 77 sid' > "$T/failed.fd/waiter.pid"
check 'a landing held under the first waiter: no wake' nope poll failed
echo '4002 - 77 sid' > "$T/failed.fd/waiter.pid"
rm -f "$T/failed.json"
check 'the first snapshot after the restart does not read: no wake' nope poll failed
snap failed 2 1
check 'the next snapshot reads: the landing held before the restart wakes at once' poll failed
check 'the wake names it and its commit' has failed 'failed: #1 landed as 100000000001: your step is due'

# Bug it catches (#1277): a held landing left behind for good once it aged out of the snapshot and its history (they
# list the 7 days to today), as a read with no row for it kept it as a record that did not read does; and one sent
# while the history, which can still list it, did not read.
fixture aged 1 2
snap aged 2 1
echo '4001 - 77 sid' > "$T/aged.fd/waiter.pid"
check 'a landing held under the first waiter: no wake' nope poll aged
echo '4002 - 77 sid' > "$T/aged.fd/waiter.pid"
snap aged 2 ''
touch "$T/aged.nohist"
check 'restarted, the landing aged out and the history does not read: no wake' nope poll aged
rm "$T/aged.nohist"
check 'restarted, the landing aged out of the snapshot and its history: it wakes' poll aged
check 'the wake names it and its saved commit' has aged 'aged: #1 landed as 100000000001: your step is due'

# Bug it catches (#1277): the same waiter, a held landing aged out while the other awaited issue is still building: it
# woke alone, or was never sent when the batch ended.
fixture agedheld 1 2
snap agedheld 2 1
check 'a landing held on its day: no wake' nope poll agedheld
snap agedheld 2 ''
check 'the landing aged out, the other still building: no wake' nope poll agedheld
snap agedheld '' 2
check 'the batch ends: one wake' poll agedheld
check 'it names the aged-out landing and its saved commit' has agedheld 'agedheld: #1 landed as 100000000001: your step is due'
check 'and the last landing' has agedheld 'agedheld: #2 landed as 100000000002: your step is due'

# Bug it catches: the saved commit of a held landing erased before its wake was in pending, when the Foreman session's
# process had ended during the poll: the next waiter then named no commit for it. A dead pid stands for that session.
fixture gone 1 2
snap gone 2 1
check 'a landing held on its day: no wake' nope poll gone
snap gone '' '1, 2' '' 'del(.landed[] | select(.issue == 1)) | del(.pushedCards[] | select(.issue == 1) | .sha)'
true & dead=$!; wait "$dead"
CONVEYOR_FOREMAN_SESSION_PID=$dead poll gone 2>/dev/null
check 'the batch ends on a later day while the session has ended: no wake put' nope compgen -G "$T/gone.fd/pending/*.wake"
check 'the next waiter sends one wake' poll gone
check 'it still names the commit of the landing of the day before' has gone 'gone: #1 landed as 100000000001: your step is due'
check 'and the commit of the last landing' has gone 'gone: #2 landed as 100000000002: your step is due'

# Bug it catches: #1 landed the day before with push off and was pushed today, with #2, which landed today: today's
# snapshot lists #1 pushed but not among its landings (today's only, in the history too), so the batch's wake named no
# commit for #1. Its pushedCards entry holds the commit.
fixture pushlater 1 2
snap pushlater '' '1, 2' '' 'del(.landed[] | select(.issue == 1))'
check 'both pushed: one wake' poll pushlater
check 'it names the commit of the landing of the day before, from pushedCards' has pushlater 'pushlater: #1 landed as 100000000001: your step is due'

# Bug it catches: the same push, read while metrics.cards already showed #1 pushed (landed, not in health's unpushed)
# and the engine had not yet written its pushed line: #1 was in neither landed nor pushedCards, here or in the history,
# so the wake named no commit for it. Its metrics.cards row holds the commit.
fixture pushnoline 1 2
snap pushnoline '' '1, 2' '' 'del(.landed[] | select(.issue == 1)) | del(.pushedCards[] | select(.issue == 1))
  | .metrics.cards = [{card: "c1", issue: 1, state: "landed", sha: "100000000001abcdef"}]'
check 'both pushed, #1 by metrics.cards alone: one wake' poll pushnoline
check 'it names the commit of the landing of the day before, from metrics.cards' has pushnoline 'pushnoline: #1 landed as 100000000001: your step is due'

[ "$fails" = 0 ] || { cat "$T"/*.err >&2; exit 1; }
