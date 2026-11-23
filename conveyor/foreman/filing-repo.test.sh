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
  [[ $r == *'Not held in Conveyor: 5 of example/other-name: no record of '*'is for example/other-name; it looked at Folder-Name (main '"$B/nomatch/Folder-Name"')'* \
    && $r == *'Set the "main" of its record in '*'or run conveyor.sh setup in that checkout'* ]] \
    || { echo "FAIL [nomatch]: the message does not name the repository, the records and the fix: $out" >&2; exit 1; } ) & e=$!
# D6: two records whose mains' repositories share a name under two owners, example/other-name first. Bug caught: the
# owner was dropped from the link and the remotes, so an issue of another-owner/other-name was held in the first.
( T=$B/owners; export XDG_CONFIG_HOME=$T/config HOME=$T/home
  { mkdir -p "$XDG_CONFIG_HOME/conveyor/filing" "$HOME" "$T/fd" && git init -q "$T/first" && git -C "$T/first" remote add origin https://github.com/example/other-name \
    && git init -q "$T/second" && git -C "$T/second" remote add origin git@github.com:another-owner/other-name.git \
    && jq -n --arg a "$T/first" --arg b "$T/second" '{records: [{repo: "first", main: $a}, {repo: "second", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"; } >&2 \
    || { echo "FAIL [owners]: the fixture was not made" >&2; exit 1; }
  l=https://github.com/another-owner/other-name/issues/5
  out=$(jq -cn --arg l "$l" '{session_id: "s1", tool_use_id: "x", hook_event_name: "PostToolUse", tool_input: {command: "gh issue create --title example --body example"},
      tool_response: {stdout: "\($l)\n", stderr: ""}}' \
    | (cd "$T/first" && CONVEYOR_MAIN=$T/first CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$T/fd \
        CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_MAIN \$CONVEYOR_CMD\" >> $T/calls; echo '{\"held\":[5]}'" bash "$SRC/foreman.sh" filed) 2>&1)
  [ "$(cat "$T/calls" 2>/dev/null)" = "second $T/second control adopt 5" ] \
    || { echo "FAIL [owners]: for the output $l, the record calls were not one adopt of 5 in second: $(cat "$T/calls" 2>/dev/null) $out" >&2; exit 1; } ) & f=$!
# The same two repositories with both mains on the host file's ssh host, the record of example/other-name named
# other-name; the first main's path is no folder on this machine, the second's an empty folder. Bugs caught: a main not
# on this machine was passed over, and then a main whose path was a folder here with no checkout in it, so the record
# named other-name was taken by its name and the issue of another-owner/other-name was held there, or none held it.
( T=$B/sshowners; export XDG_CONFIG_HOME=$T/config HOME=$T/home
  { mkdir -p "$XDG_CONFIG_HOME/conveyor/filing" "$HOME" "$T/fd" "$T/bin" "$T/host/second" && git init -q "$T/real/first" && git -C "$T/real/first" remote add origin https://github.com/example/other-name \
    && git init -q "$T/real/second" && git -C "$T/real/second" remote add origin git@github.com:another-owner/other-name.git \
    && jq -n --arg a "$T/host/first" --arg b "$T/host/second" '{ssh: "example-host", records: [{repo: "other-name", main: $a}, {repo: "second", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && printf '#!/usr/bin/env bash\nh=%q r=%q c=${*: -1}; exec bash -c "${c//"$h"/"$r"}"\n' "$T/host" "$T/real" > "$T/bin/ssh" && chmod +x "$T/bin/ssh"; } >&2 \
    || { echo "FAIL [sshowners]: the fixture was not made" >&2; exit 1; } # ssh: the host, its command run here with the host's paths read from real
  l=https://github.com/another-owner/other-name/issues/5
  out=$(jq -cn --arg l "$l" '{session_id: "s1", tool_use_id: "x", hook_event_name: "PostToolUse", tool_input: {command: "gh issue create --title example --body example"},
      tool_response: {stdout: "\($l)\n", stderr: ""}}' \
    | (cd "$T/real/first" && PATH=$T/bin:$PATH CONVEYOR_MAIN=$T/real/first CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$T/fd \
        CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_MAIN \$CONVEYOR_CMD\" >> $T/calls; echo '{\"held\":[5]}'" bash "$SRC/foreman.sh" filed) 2>&1)
  [ "$(cat "$T/calls" 2>/dev/null)" = "second $T/host/second control adopt 5" ] \
    || { echo "FAIL [sshowners]: for the output $l, with both mains on the ssh host (the second's path an empty folder here), the record calls were not one adopt of 5 in second: $(cat "$T/calls" 2>/dev/null) $out" >&2; exit 1; } ) & g=$!
# A record named other-name whose main's remote is example/first-project, and no record of another-owner/other-name.
# Bug caught: the record was taken by its name, as only a remote of that name under another owner was passed over, so
# an issue of another-owner/other-name was held in example/first-project's record.
( T=$B/othername; export XDG_CONFIG_HOME=$T/config HOME=$T/home
  { mkdir -p "$XDG_CONFIG_HOME/conveyor/filing" "$HOME" "$T/fd" && git init -q "$T/first" && git -C "$T/first" remote add origin https://github.com/example/first-project \
    && jq -n --arg a "$T/first" '{records: [{repo: "other-name", main: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"; } >&2 \
    || { echo "FAIL [othername]: the fixture was not made" >&2; exit 1; }
  l=https://github.com/another-owner/other-name/issues/5
  out=$(jq -cn --arg l "$l" '{session_id: "s1", tool_use_id: "x", hook_event_name: "PostToolUse", tool_input: {command: "gh issue create --title example --body example"},
      tool_response: {stdout: "\($l)\n", stderr: ""}}' \
    | (cd "$T/first" && CONVEYOR_MAIN=$T/first CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$T/fd \
        CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_MAIN \$CONVEYOR_CMD\" >> $T/calls; echo '{\"held\":[5]}'" bash "$SRC/foreman.sh" filed) 2>&1)
  ! grep -qE 'control (adopt|hold)' "$T/calls" 2>/dev/null \
    || { echo "FAIL [othername]: for the output $l, an issue was held in the record of example/first-project: $(cat "$T/calls") $out" >&2; exit 1; }
  [[ $out == *'Not held in Conveyor: 5 of another-owner/other-name'* ]] \
    || { echo "FAIL [othername]: for the output $l, the hook did not say issue 5 is not held: $out" >&2; exit 1; } ) & h=$!
# Each case that passed prints `ok <case>`, named as its FAIL line names it: the pass the main-red proof reads.
rc=0
for p in "$a norecords" "$b named" "$c othermain" "$d otherworktree" "$e nomatch" "$f owners" "$g sshowners" "$h othername"; do
  if wait "${p%% *}"; then echo "ok ${p#* }"; else rc=1; fi
done
exit "$rc"
