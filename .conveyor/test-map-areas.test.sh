#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's test map (#150): its pack's test.map names .conveyor/engine-areas.json, and the engine's map reader
# (mapread(), conveyor/lib/testmap.sh), the one a user's card reads its map with, must read it as test-changed.sh
# does (--map): each engine file of an area goes to that area's case files, and the files of an area whose tests are
# "all" are shared (they run the whole suite). Bug it catches: a move onto the map that loses a case file, so a change
# to the engine file it covers would no longer run it.
set -u
cd "$(dirname "$0")/.." || exit 1
. conveyor/lib/testmap.sh || exit 1
# The pack's field, read as the engine reads it; and this project's test files, which the map names by file name.
packget() { printf -v "$2" '%s' "$(jq -r --arg f "$1" 'getpath($f | split(".")) // ""' .conveyor/project.json)"; }
testpaths() { grep -E '\.test\.'; }
m=''; packget test.map m
[ "$m" = .conveyor/engine-areas.json ] && echo "ok - the pack's test.map is the area map" || { echo "not ok - the pack's test.map is \"$m\", not .conveyor/engine-areas.json"; exit 1; }
got=$(mapread .) || { echo "not ok - the map reader could not read the area map: $got"; exit 1; }
want=$(bash .conveyor/test-changed.sh --map) || { echo "not ok - test-changed.sh --map could not read the area map"; exit 1; }
bad=$(jq -rn --argjson g "$got" --argjson w "$want" '
  ([$w.areas[] | select(.tests != "all") | .tests as $t | .files[] | {key: ., value: ($t | map("conveyor/tests/" + .) | unique)}]
    | group_by(.key) | map({key: .[0].key, value: (map(.value[]) | unique)}) | from_entries) as $ws
  | ($ws | to_entries[] | select($g.sources[.key] != .value) | "\(.key): the map reader gives \($g.sources[.key]), test-changed.sh \(.value)"),
    # An area with no files (wait) names its case file only so a change to it alone runs it, as any changed test does.
    ([$w.areas[] | select(.files != []) | .tests | arrays[] | "conveyor/tests/" + .] | unique - [$g.sources[][]] | .[] | "\(.): a case file of the area map no source runs"),
    ([$w.areas[] | select(.tests == "all") | .files[]] - $g.shared | .[] | "\(.): in an \"all\" area, but not shared")')
[ -z "$bad" ] && echo "ok - the map reader reads every area, case file and shared file as test-changed.sh does" || { echo "not ok - the map reader and test-changed.sh differ:"; echo "$bad"; exit 1; }
# Bug it catches (#1339): testhistory.test.sh runs the cases of the test rules library and of the test-settings command,
# but the map listed it under neither area, so a card changing only one of those files did not run it.
for f in conveyor/lib/testrules.sh conveyor/commands/test-settings.sh; do
  jq -e --arg f "$f" --arg t conveyor/tests/testhistory.test.sh '.sources[$f] // [] | index($t)' <<< "$got" > /dev/null \
    && echo "ok - a change to $f runs testhistory.test.sh" || { echo "not ok - a change to $f does not run testhistory.test.sh"; exit 1; }
done
# Bug it catches: mainredhold.test.sh runs settle() of the claim library and turnpick()/cardrun() of the run library,
# but the map listed it under neither area, so a card changing only one of those files did not run it.
for f in conveyor/lib/claim.sh conveyor/lib/run.sh; do
  jq -e --arg f "$f" --arg t conveyor/tests/mainredhold.test.sh '.sources[$f] // [] | index($t)' <<< "$got" > /dev/null \
    && echo "ok - a change to $f runs mainredhold.test.sh" || { echo "not ok - a change to $f does not run mainredhold.test.sh"; exit 1; }
done
# Bug it catches: runner.test.sh (t_runnermap, t_runnermapdeleted, through testsel()) and mainredverdict.test.sh
# (t_mainredcontrolchanged, t_mainchangeddeleted, through mainchanged() and maplinked()) read a test map with mapread(), but the map
# listed neither under the area of conveyor/lib/testmap.sh, so a card changing only that file did not run them.
for t in conveyor/tests/runner.test.sh conveyor/tests/mainredverdict.test.sh; do
  jq -e --arg f conveyor/lib/testmap.sh --arg t "$t" '.sources[$f] // [] | index($t)' <<< "$got" > /dev/null \
    && echo "ok - a change to conveyor/lib/testmap.sh runs $t" || { echo "not ok - a change to conveyor/lib/testmap.sh does not run $t"; exit 1; }
done
