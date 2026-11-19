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
# other_ <name> <origin of the main> <link the command printed> [worktree]: runs filed for issue 5, linked as given,
# with one record, Folder-Name, whose main's origin is the one given, in that main or a worktree of it, with no
# CONVEYOR_MAIN (the hook finds its checkout from where it runs). Prints the hook's output; calls are noted in calls.
# Bug (#793): the main's origin was compared letter for letter with the link's name (GitHub prints its own case),
# and a record named apart from its repository was then not found: "Not held in Conveyor", the issue not held.
other_() {
  local T=$B/$1 M=$B/$1/Folder-Name W
  export XDG_CONFIG_HOME=$T/config HOME=$T/home
  W=$M; [ -z "${4:-}" ] || W=$T/wt
  { mkdir -p "$XDG_CONFIG_HOME/conveyor/filing" "$HOME" "$T/fd" && git init -q "$M" && git -C "$M" remote add origin "$2" \
    && git -C "$M" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m t \
    && { [ "$W" = "$M" ] || git -C "$M" worktree add -q "$W"; } \
    && jq -n --arg m "$M" '{records: [{repo: "Folder-Name", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"; } >&2 || return 1
  jq -cn --arg l "$3" '{session_id: "s1", tool_use_id: "x", hook_event_name: "PostToolUse", tool_input: {command: "gh issue create --title example --body example"},
      tool_response: {stdout: "\($l)\n", stderr: ""}}' \
    | (cd "$W" && CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$T/fd \
        CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_MAIN \$CONVEYOR_CMD\" >> $T/calls; echo '{\"held\":[5]}'" bash "$SRC/foreman.sh" filed) 2>&1
}
# held_ <name> [worktree]: an issue of example/other-name (linked in GitHub's case, Other-Name) is held in Folder-Name.
held_() {
  local out
  out=$(other_ "$1" https://github.com/example/other-name.git https://github.com/example/Other-Name/issues/5 ${2:-}) || { echo "FAIL [$1]: the fixture was not made: $out" >&2; exit 1; }
  grep -qx "Folder-Name $B/$1/Folder-Name control adopt 5" "$B/$1/calls" 2>/dev/null \
    || { echo "FAIL [$1]: issue 5 of example/other-name was not held in Folder-Name: $(cat "$B/$1/calls" 2>/dev/null) $out" >&2; exit 1; }
  [[ $out == *'Held in Conveyor (Folder-Name: 5)'* && $out != *'Not held'* ]] || { echo "FAIL [$1]: the hook did not say it held issue 5: $out" >&2; exit 1; }
}
# D1: a host file with no records; its one record is named for the folder, proj-a.
case_ norecords '{}' & a=$!
# D2: a record named proj-a, whose main's remote is owner/proj.
case_ named '{records: [{repo: "proj-a", main: $m}]}' & b=$!
# D3: record Folder-Name, main's origin example/other-name: an issue filed in example/other-name is held there.
held_ othermain & c=$!
# D4: the same, the hook run from a worktree of that main.
held_ otherworktree worktree & d=$!
# D5: no record has the repository: the message names it and the fix, and no record holds anything.
( out=$(other_ nomatch https://github.com/example/folder-name https://github.com/example/other-name/issues/5) || { echo "FAIL [nomatch]: the fixture was not made: $out" >&2; exit 1; }
  [ ! -s "$B/nomatch/calls" ] || ! grep -qE 'control (adopt|hold)' "$B/nomatch/calls" || { echo "FAIL [nomatch]: an issue was held in a record not of example/other-name: $(cat "$B/nomatch/calls")" >&2; exit 1; }
  r=$(jq -r '.reason // empty' <<<"$out" 2>/dev/null)
  [[ $r == *'Not held in Conveyor: 5 of other-name: no record of '*'is for other-name; it looked at Folder-Name (main '"$B/nomatch/Folder-Name"')'* \
    && $r == *'Set the "main" of its record in '*'or run conveyor.sh setup in that checkout'* ]] \
    || { echo "FAIL [nomatch]: the message does not name the repository, the records and the fix: $out" >&2; exit 1; } ) & e=$!
rc=0; for p in "$a" "$b" "$c" "$d" "$e"; do wait "$p" || rc=1; done; exit "$rc"
