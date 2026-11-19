#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on the fix cards of a red release run (the release record's
# fixes and restarted, which the engine's relfixes() writes, lib/fulltest.sh): one poll (--once) at a time of a
# snapshot given by CONVEYOR_FOREMAN_ASK, the clock set by CONVEYOR_FOREMAN_NOW.
# Bug (#759): when every fix card of release 1.6.0's failed suite had landed, no wake said so; the release went on
# only because the owner told the Foreman. A fix card closed with no landed card, which holds the release for the
# Foreman, woke nothing either.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0
AT=2026-11-17T08:00:00Z START=1794902400 ENDED=2026-11-17T07:00:00Z # $AT in epoch seconds; the red suite's end
mkdir -p "$T/home" "$T/config/conveyor"
check() { if "${@:2}"; then echo "ok [watch-relfix]: $1"; else echo "FAIL [watch-relfix]: $1" >&2; fails=$((fails + 1)); fi; }
nope() { ! "$@"; }
# The snapshot of record <repo>, its main $T/<repo>: <repo>.json, with the release record <run> as its one suite, a
# card queued (so no poll is idle) and <belt> on the belt. The suite's end was reported before (its own wake), so a
# wake here is the fix cards' alone.
fixture() { # <repo> <run> [<belt>]
  git init -q "$T/$1" && mkdir -p "$T/$1/.conveyor" "$T/$1.fd" && echo '{}' > "$T/$1/.conveyor/project.json" \
    && jq -r --arg r "$1" 'select(.ended != null) | "\($r)/suite:release:\(.ended)"' <<<"$2" > "$T/$1.fd/conveyor-reported.txt" \
    && jq -cn --arg at "$AT" --argjson r "$2" --argjson b "${3:-[]}" '{queue: {next: [{issue: 9}]}, belt: $b, suites: [$r],
      health: {time: $at, loop: true, gh: true, blocked: [], waiting: [], stuck: [], pushFailingSince: null, waitingOnCard: [], unpushed: []}}' > "$T/$1.json" \
    && jq -n --arg m "$T/$1" --arg r "$1" '{records: [{repo: $r, main: $m}]}' > "$T/config/conveyor/host-$1.json"
}
poll() { # <repo> [<minutes after $AT>]: one poll then; 0 with a wake put in pending, which goes to $T/<repo>.wake
  rm -f "$T/$1.fd"/pending/*.wake "$T/$1.wake"; cp "$T/config/conveyor/host-$1.json" "$T/config/conveyor/host.json"
  HOME=$T/home XDG_CONFIG_HOME=$T/config CONVEYOR_MAIN=$T/$1 CONVEYOR_FOREMAN_DIR=$T/$1.fd CONVEYOR_FOREMAN_NOW=$((START + ${2:-0} * 60)) \
    CONVEYOR_FOREMAN_ASK="cat $T/$1.json" bash "$SRC/watch-conveyor.sh" --once 2>> "$T/$1.err" && cat "$T/$1.fd"/pending/*.wake > "$T/$1.wake"
}
has() { grep -qF -- "$2" "$T/$1.wake"; } # <repo> <text>
red() { # <fixes> [<restarted>]: the record of release 1.6.0's failed release-prep
  jq -cn --arg e "$ENDED" --argjson x "$1" --arg rs "${2:-}" '{kind: "release", version: "1.6.0", step: "release-prep", since: "2026-11-17T06:00:00Z",
    ended: $e, state: "failed", sha: "0123456789abcdef", cases: ["t_a"], reasons: [], fixes: $x, restarted: (if $rs == "" then null else $rs end), by: null}'
}

# Every fix landed, and relfixes() started release-prep again: the record is that new run's, by "fixes landed".
fixture landed "$(jq -cn --arg at "$AT" '{kind: "release", version: "1.6.0", step: "release-prep", since: $at, ended: null, state: "running", sha: null, cases: [], reasons: [], by: "fixes landed"}')"
check 'a release-prep started again by its landed fixes wakes' poll landed
check 'the wake names the version and that release-prep started again' \
  has landed 'landed: every fix card of release 1.6.0'"'"'s failed suite has landed: release-prep 1.6.0 started again at 2026-11-17T08:00:00Z'
check 'the wake is one item' test "$(grep -c '1\.6\.0' "$T/landed.wake")" = 1
check 'the same run a poll later gives no second wake' nope poll landed 1

# Every fix landed, the belt empty and no push owed, but relfixes() held the run: a fix's commit is not in the commit
# the suite runs on (a landing pull request not merged).
fixture held "$(red '[{"issue": 753, "state": "landed"}, {"issue": 754, "state": "landed"}]')"
check 'landed fixes whose run is held wake' poll held
check 'the wake names the fixes and why release-prep did not start' \
  has held 'held: every fix card of release 1.6.0'"'"'s failed suite has landed (#753, #754), but release-prep 1.6.0 did not start again: the commit the suite runs on does not hold'

# The same hold with the fixes landed but not pushed: with the rule "Push when a card lands" on, the loop pushes them
# and the hold ends by itself, no wake; with it off, nothing pushes until the owner does, so it wakes.
owe() { # <repo> <push rule>: the fix's commit is owed a push, the control record's rules.push set
  jq -c --argjson on "$2" '.health.unpushed = [{card: "c53", issue: 753, sha: "fedcba9876543210", since: "2026-11-17T07:30:00Z"}]
    | .control = {rules: {push: $on}}' "$T/$1.json" > "$T/$1.new" && mv "$T/$1.new" "$T/$1.json"
}
fixture owed "$(red '[{"issue": 753, "state": "landed"}]')" && owe owed true
check 'landed fixes owed a push with the push rule on give no wake' nope poll owed
# Land as main set on the control record over a pack's pr, Merge PR button on both: a watcher that read the pack's
# Land as past the control record's would ask for a merge here.
fixture pushoff "$(red '[{"issue": 753, "state": "landed"}]')" && owe pushoff false \
  && jq -c '.control += {landAs: "main", prMerge: "button"} | .packLandAs = "pr" | .packPrMerge = "button"' "$T/pushoff.json" > "$T/pushoff.new" \
  && mv "$T/pushoff.new" "$T/pushoff.json"
check 'landed fixes owed a push with the push rule off wake' poll pushoff
check 'the wake says the owner must push' \
  has pushoff 'did not start again: the landed commits are not pushed, and the rule Push when a card lands is off: press Push landed'
check 'with Land as main the wake asks for no merge' nope has pushoff 'then Merge'

# Bug: with Land as pr and Merge PR button, Push landed sends the fixes to the landing pull request, and the suite
# runs on the branch it goes into: the wake asked only for the push, and once pushed, the merge still owed had the
# push wake's key, so nothing said it.
fixture bymerge "$(red '[{"issue": 753, "state": "landed"}]')" && owe bymerge false \
  && jq -c '.control += {landAs: null, prMerge: "button"} | .packLandAs = "pr" | .packPrMerge = "release"' "$T/bymerge.json" > "$T/bymerge.new" \
  && mv "$T/bymerge.new" "$T/bymerge.json"
check 'landed fixes owed a push under Land as pr wake' poll bymerge
check 'the wake asks for the push and then the merge' \
  has bymerge 'press Push landed on the Board'"'"'s Control tab, then Merge there, as the rule Land as is pr and the rule Merge PR is button'
jq -c '.health.unpushed = [] | .health.landingPr = {number: 41, url: null, merge: null, merged: null, closed: null, cards: 1}' "$T/bymerge.json" > "$T/bymerge.new" \
  && mv "$T/bymerge.new" "$T/bymerge.json"
check 'once pushed, the landing pull request not merged wakes again' poll bymerge 1
check 'that wake names the pull request and the Merge it needs' \
  has bymerge 'landing pull request #41 is not merged, and the rule Merge PR is button: press Merge on the Board'"'"'s Control tab'

# The same hold with a card still on the belt ends by itself when the card lands: no wake.
fixture busy "$(red '[{"issue": 753, "state": "landed"}]')" '[{"card": "c60", "issue": 60, "step": "build"}]'
check 'landed fixes held only by a card on the belt give no wake' nope poll busy

# relfixes() started release-prep again, but no run of its own began (the record is still the red one).
fixture nostart "$(red '[{"issue": 753, "state": "landed"}]' "$AT")"
check 'a restart under two polls old gives no wake yet' nope poll nostart 1
check 'a restart with no run two polls on wakes' poll nostart 2
check 'the wake says no run began and how to start it' has nostart 'release-prep was started again at 2026-11-17T08:00:00Z, but no run began: run `conveyor.sh release-run prep 1.6.0`'

# One fix closed with no landed card, one landed: the release waits on the Foreman.
fixture closed "$(red '[{"issue": 755, "state": "closed"}, {"issue": 756, "state": "landed"}]')"
check 'a fix closed with no landed card wakes' poll closed
check 'the wake names that issue' has closed 'closed: fix card #755 of release 1.6.0'"'"'s failed suite was closed with no landed card'
check 'the wake'"'"'s first line lists it by kind' has closed 'Conveyor: closed: release fix closed: #755'
check 'the landed fix is not named as closed' nope has closed '#756'
check 'the closed fix a poll later gives no second wake' nope poll closed 1

# A run started by its landed fixes that failed again, one of its own new fixes closed: the closed fix wakes, not a
# second "started again".
fixture again "$(red '[{"issue": 758, "state": "closed"}]' | jq -c '.by = "fixes landed"')"
check 'a closed fix of a run started by its fixes wakes' poll again
check 'its wake names the closed fix, not the restart' has again 'again: fix card #758 of release 1.6.0'
check 'its wake has no restart notice beside the closed fix' nope has again 'started again'

# A fix still open: nothing to report yet.
fixture open "$(red '[{"issue": 757, "state": "open"}, {"issue": 753, "state": "landed"}]')"
check 'a fix still open gives no wake' nope poll open

[ "$fails" = 0 ] || { cat "$T"/*.err >&2; exit 1; }
