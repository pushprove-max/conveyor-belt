#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: an issue filed by a Foreman's command starts held, through the filing hooks (foreman/foreman.sh filing
# and filed) on this engine's control record, however the command printed what it filed.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One main with #4 open, Queue, and a filer's hooks on it: the research lane's (CONVEYOR_LANE=research), so no Foreman
# claim is needed, with a host file of their own whose one record "r" is the main (the stub's links name o/r). The
# hooks reach the record through this engine (CONVEYOR_FOREMAN_ASK), with the engine's own config folder.
# hook <filing|filed> <command> [stdout]: one hook call, as Claude Code makes it for a Bash call.
filedsetup() {
  setup "[$(issue 4 2000-01-01T00:00:00Z P2)]"; C=$ST/control.json; echo : > "$STUB/build"; touch "$STUB/list-filed"
  FC=$T/$CASE/filer-config; mkdir -p "$FC/conveyor" "$T/$CASE/filer/lane"
  jq -cn --arg m "$R" '{records: [{repo: "r", main: $m}]}' > "$FC/conveyor/host.json"
  printf -v ASKE 'cd "$CONVEYOR_MAIN" && XDG_CONFIG_HOME=%q CONVEYOR_CARDS=%q bash %q $CONVEYOR_CMD' "$XDG_CONFIG_HOME" "$T/$CASE/cards" "$SRC/conveyor.sh"
  hook() {
    jq -cn --arg e "$1" --arg c "$2" --arg o "${3:-}" '{hook_event_name: (if $e == "filing" then "PreToolUse" else "PostToolUse" end), session_id: "s1",
      tool_use_id: "t1", tool_input: {command: $c}} + (if $e == "filed" then {tool_response: {stdout: $o, stderr: ""}} else {} end)' \
      | (cd "$R" && XDG_CONFIG_HOME=$FC CONVEYOR_MAIN=$R CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$T/$CASE/filer/lane CONVEYOR_FOREMAN_ASK=$ASKE \
        bash "$SRC/foreman/foreman.sh" "$1")
  }
}
# Issue 761: a command that pipes `gh issue create` to `grep -oE '[0-9]+$'` prints the new issue's number and no link.
# Bug: filed held only the issues the output links, so it held none, set new issues back to the queue, and the loop
# picked the issue before the owner's yes. The issue is a follow-up, which the loop's own hold of new issues (adopted())
# passes over, so only filed's Queue (control start queue filed) can hold it: here it is held once filed has run, and
# the loop picks #4 alone.
t_filedbare() {
  filedsetup
  cmd='n=$(gh issue create --title example --body example --label conveyor-followup | grep -oE "[0-9]+$"); echo "$n"'
  out=$(hook filing "$cmd"); [ -z "$out" ] && [ "$(jq -r .start "$C")" = held ] || fail "filing did not set new issues held: $out $(cat "$C")"
  n=$(gh issue create --title example --body example --label conveyor-followup | grep -oE '[0-9]+$') || fail "the stub filed no issue"
  out=$(hook filed "$cmd" "$n"$'\n')
  jq -e --argjson n "$n" '.start == "queue" and (.held | index($n))' "$C" >/dev/null || fail "the issue filed (#$n) is not held after filed: $(cat "$C")"
  # Bug (#1234): with no link in the output filed said nothing, so when the Queue's own hold failed (a record's older
  # engine, a stale held list), the Foreman never learned the issue was unheld and the loop built it.
  jq -e '.hookSpecificOutput.additionalContext | test("no link for each issue.*control hold")' <<<"$out" >/dev/null \
    || fail "filed did not tell the Foreman that the output links no issue (command: $cmd, output: $n): $out"
  # The real loop, not a check of the record: only a pick shows the follow-up is not built, as the pick applies its own
  # rules to the open issues it reads (adopted() and upnext.jq, which leave a follow-up eligible), not only the held list.
  loop run >/dev/null 2>&1; [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ' ')" = "4 " ] || fail "picks after the filing: $(st 'select(.step == "picked") | .issue')"
}
# Bug (#1234): one issue link in the output made filed take every issue of the command as linked, so a second
# `gh issue create` of the same command, printed as a bare number, got no warning. Here the Foreman is told.
t_filedmixed() {
  filedsetup
  cmd='gh issue create --title a --body a && gh issue create --title b --body b | grep -oE "[0-9]+$"'
  hook filing "$cmd" >/dev/null
  o=$(gh issue create --title a --body a) || fail "the stub filed no issue"
  out=$(hook filed "$cmd" "$o"$'\n'"7"$'\n')
  jq -e '.hookSpecificOutput.additionalContext | test("no link for each issue.*control hold")' <<<"$out" >/dev/null \
    || fail "filed did not warn that one of two creates shows no link (command: $cmd, output: $o and 7): $out"
  # Bug (#1405): the creates were counted on the command as written, so a quoted `gh issue 'create'` was no create and
  # got no warning, while a title that says "issue create" was one. They are counted as the filing hook reads them.
  cmd="gh issue create --title a --body a && gh issue 'create' --title b --body b | grep -oE '[0-9]+\$'"
  hook filing "$cmd" >/dev/null
  o=$(gh issue create --title a --body a) || fail "the stub filed no issue"
  out=$(hook filed "$cmd" "$o"$'\n'"8"$'\n')
  jq -e '.hookSpecificOutput.additionalContext | test("no link for each issue.*control hold")' <<<"$out" >/dev/null \
    || fail "filed did not warn that a quoted create shows no link (command: $cmd, output: $o and 8): $out"
  # Bug (#1405 review): a line continuation between gh and issue create split the create over two lines, so it was
  # not counted and one link was taken to cover both creates.
  cmd=$'gh issue create --title a --body a && gh \\\n issue create --title b --body b | grep -oE \'[0-9]+$\''
  hook filing "$cmd" >/dev/null
  o=$(gh issue create --title a --body a) || fail "the stub filed no issue"
  out=$(hook filed "$cmd" "$o"$'\n')
  jq -e '.hookSpecificOutput.additionalContext | test("no link for each issue.*control hold")' <<<"$out" >/dev/null \
    || fail "filed did not warn that a create split by a line continuation shows no link (command: $cmd, output: $o): $out"
  cmd='gh issue create --title "Count each issue create" --body a'
  hook filing "$cmd" >/dev/null
  o=$(gh issue create --title a --body a) || fail "the stub filed no issue"
  out=$(hook filed "$cmd" "$o"$'\n')
  ! jq -e '.hookSpecificOutput.additionalContext | test("no link for each issue")' <<<"$out" >/dev/null \
    || fail "filed warned of an unlinked issue for a title that says issue create (command: $cmd, output: $o): $out"
}
# Bug (#1234): when filed blocks (a linked issue it cannot hold) the block reason must still carry the unlinked-issue
# warning; without it the Foreman is told of the one failure and never that the other create shows no link.
t_filedblock() {
  filedsetup
  cmd='gh issue create --title a --body a && gh issue create --title b --body b | grep -oE "[0-9]+$"'
  hook filing "$cmd" >/dev/null
  o="https://github.com/o/other/issues/9"
  out=$(hook filed "$cmd" "$o"$'\n'"7"$'\n')
  jq -e '.decision == "block" and (.reason | test("Not held in Conveyor.*9 of other") and test("no link for each issue.*control hold"))' <<<"$out" >/dev/null \
    || fail "filed's block did not carry the unlinked-issue warning (command: $cmd, output: $o and 7): $out"
}
# With the links in the output, the issue filed is still held, and one the owner released before filed ran (the
# second, released between the command and its hook) stays released: Queue holds neither again.
t_filedlink() {
  filedsetup
  cmd='gh issue create --title a --body a; gh issue create --title b --body b'
  hook filing "$cmd" >/dev/null
  o=$(gh issue create --title a --body a; gh issue create --title b --body b) || fail "the stub filed no issues"
  a=$(sed -n '1s|.*/||p' <<<"$o"); b=$(sed -n '2s|.*/||p' <<<"$o")
  loop control release "$b" >/dev/null || fail "the release of #$b failed"
  out=$(hook filed "$cmd" "$o"$'\n')
  [ "$(jq -c '[.start, .held, .startSeen]' "$C")" = "[\"queue\",[$a],[$a,$b]]" ] || fail "after filed: $(cat "$C")"
  jq -e --arg a "$a" --arg b "$b" '.hookSpecificOutput.additionalContext | test("Held in Conveyor \\(r: " + $a + "\\)") and test("released already \\(r: " + $b + "\\)")' <<<"$out" >/dev/null \
    || fail "filed did not tell which it held: $out"
  ! jq -e '.hookSpecificOutput.additionalContext | test("no link for each issue")' <<<"$out" >/dev/null \
    || fail "filed warned of an unlinked issue though each of the two creates is linked (command: $cmd): $out"
  # filed's Queue that cannot read the open issues changes nothing: closing the span unread could leave a filed issue unheld.
  loop control start held >/dev/null; echo '[ "$4" != open ] || exit 1' > "$STUB/list-cmd"
  out=$(loop control start queue filed 2>&1); [ $? = 1 ] && [ "$(jq -r .start "$C")" = held ] || fail "Queue with the open issues unread: $out $(cat "$C")"
}
# Bug (issue 1333): the filing hooks sent the running loop nothing, so an issue filed and released already (the
# owner's yes given before filed ran, as in t_filedlink) was picked only once the loop's idle timer (here 100 s)
# ended. GitHub lists the issue only once the command has ended (the stub's list-filed), after the release, so here
# filed's wake alone can make the loop asleep on its timer pick it.
# It runs the real `serve` loop, as only its own turn shows that the wake ends the wait and that the pick follows it.
t_filedwake() {
  filedsetup; rm -f "$STUB/list-filed"; tune '.tunables.idle = 100 | .tunables.poll = 1'; watchturns
  loop control hold 4 >/dev/null || fail "hold 4 was refused"
  cmd='gh issue create --title a --body a'
  hook filing "$cmd" >/dev/null
  o=$(gh issue create --title a --body a) || fail "the stub filed no issue"; n=${o##*/}
  loop control release "$n" >/dev/null || fail "the release of #$n failed"
  loop serve > "$STUB/serve.out" 2>&1 & lp=$! # loop: only the loop's own turn shows its idle wait ending on filed
  # The loop's first timer: it has picked nothing (#4 held, #n not listed yet) and sleeps on its idle timer.
  wait_until "grep -qxF '$R' '$TURNS'" "cat '$STUB/serve.out'" || fail "the loop took no turn"
  touch "$STUB/list-filed"; out=$(hook filed "$cmd" "$o"$'\n')
  WAIT_CEILING=$(loadlimit 20 100) wait_until "[ -n \"\$(st 'select(.issue == $n and .step == \"picked\") | .card' 2>/dev/null)\" ]" "cat '$STUB/serve.out'" \
    || fail "filed (command: $cmd, output: $o) did not wake the loop asleep on its 100 s idle timer: #$n was not picked; filed said: $out"
  kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; return 0
}
