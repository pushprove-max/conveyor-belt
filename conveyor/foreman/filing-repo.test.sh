#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The filing hook (foreman.sh filed) holds an issue in the record whose main checkout's GitHub repository it was
# filed in, when that record's name is not the repository's name.
# Bug (#432): filed looked for a record named as the repository in the issue's URL; a checkout folder proj-a whose
# remote is owner/proj (a host file with no records names its one record for the folder), or a record named proj-a,
# matched none, so the issue was not held and the hook said "Not held in Conveyor".
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_MAIN CONVEYOR_MACHINE_ID CLAUDE_PROJECT_DIR
# case <name> <host file's records, as jq, with $m the checkout>: runs filed for issue 5 of owner/proj there.
case_() {
  local T=$B/$1 M=$B/$1/proj-a out
  fail() { echo "FAIL [$1]: ${*:2}" >&2; exit 1; }
  export XDG_CONFIG_HOME=$T/config HOME=$T/home
  mkdir -p "$XDG_CONFIG_HOME/conveyor/filing" "$HOME" "$T/fd" && git init -q "$M" && git -C "$M" remote add origin https://github.com/owner/proj \
    && jq -n --arg m "$M" "$2" > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "$1" "the fixture was not made"
  # Each record command is noted with the record it went to; control adopt answers that issue 5 is held.
  out=$(jq -cn '{session_id: "s1", tool_use_id: "x", hook_event_name: "PostToolUse", tool_input: {command: "gh issue create --title example --body example"},
      tool_response: {stdout: "https://github.com/owner/proj/issues/5\n", stderr: ""}}' \
    | (cd "$M" && CONVEYOR_MAIN=$M CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$T/fd \
        CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_MAIN \$CONVEYOR_CMD\" >> $T/calls; echo '{\"held\":[5]}'" bash "$SRC/foreman.sh" filed) 2>&1)
  grep -qx "proj-a $M control adopt 5" "$T/calls" 2>/dev/null || fail "$1" "issue 5 of owner/proj was not held in the checkout's record: $(cat "$T/calls" 2>/dev/null) $out"
  [[ $out != *'Not held'* ]] || fail "$1" "the hook said an issue was not held: $out"
}
# D1: a host file with no records; its one record is named for the folder, proj-a.
case_ norecords '{}' & a=$!
# D2: a record named proj-a, whose main's remote is owner/proj.
case_ named '{records: [{repo: "proj-a", main: $m}]}' & b=$!
rc=0; wait "$a" || rc=1; wait "$b" || rc=1; exit "$rc"
