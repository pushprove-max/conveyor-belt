#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: dependencies and the start rule.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Dependencies. Bugs: an issue picked while an issue it depends on is open, or not picked once it closes; two
# independent issues not built side by side while a third waits on them; the snapshot not saying what a waiting
# issue waits on; a dependency cycle not reported by health; a run over a list of four with a limit of two leaving
# one unbuilt, building more than two at once, or not saying that a listed issue waits on one outside the list.
# GitHub closes an issue when the commit that names it reaches origin: here, origin's post-receive hook does.
deps_setup() { # <issues json>
  setup "$1"
  printf '%s\n' '#!/usr/bin/env bash' 'while read -r old new ref; do' \
    '  for n in $(git log --format=%s "$old..$new" | grep -oE "\(#[0-9]+\)" | tr -d "(#)"); do' \
    '    jq -c --argjson n "$n" "map(select(.number != \$n))" "$ISSUES" > "$ISSUES.new" && mv "$ISSUES.new" "$ISSUES"' \
    '  done' 'done' > "$T/$CASE/origin/hooks/post-receive"
  sed -i "2i ISSUES=$STUB/issues.json" "$T/$CASE/origin/hooks/post-receive"; chmod +x "$T/$CASE/origin/hooks/post-receive"
  for i in $(seq 1 20); do echo "$GO" > "$STUB/review.$i"; done
  # Each card adds a file of its own, so cards built side by side do not conflict.
  echo 'echo x > "f${PWD##*-}.txt"' > "$STUB/build"
}
# Sets p to the issues the loop would pick one after another, in that order, a space after each: `pick --dry`
# (drypick(), the loop's upnext() on the same records, pick.test.sh), each answer then given a landed line, until it
# answers none (ten at most). For a case that checks which issues are picked, not what a card does: no card is built.
# Run in the case's own shell, not in $(...), so a dry pick that fails fails the case and is not read as no pick.
drypicks() {
  local n i=0
  p=''; mkdir -p "$ST"
  while [ $i -lt 10 ]; do
    n=$(loop pick --dry --issues "$STUB/issues.json" --state "$ST") || fail "pick --dry failed (exit $?) after: $p"
    [ -n "$n" ] || break
    p+="$n "; landed "$n" >> "$ST/cards.jsonl"; i=$((i + 1))
  done
}
# The open issues read as the loop's pick and the snapshot read them: adopt() under the records' lock, which saves the
# holds the start rule and the forced list give them in the control record, with no snapshot built.
readopen() {
  fx_in 'locked adopt "$(cat "$STUB/issues.json")"'; [ "$RC" = 0 ] || fail "adopt() failed (exit $RC): $(cat "$T/$CASE/run.out")"
}
# Where new issues start. Bugs: a new issue picked while the setting is Held, or not shown as held; a released
# one held again, also one released before it was first seen; a follow-up, or an issue open before the switch (even
# opened in its same second), held; switching back to Queue releasing the held ones, or letting through one opened
# while it was Held (even in the second of the switch back), or holding one opened after it in that same second; a
# switch made when the newest issue number cannot be read; a hold that could not be saved shown as queued; the setting
# refused, or not named by health and snapshot.
# The start of each start-rule case (t_start, t_startheld, t_startqueue), which run side by side: #4 open. These cases
# check which issues are picked, not what lands: each card's build changes nothing, so the card ends after its build
# (blocked: no change to review), with no review, tests or landing. t_start and t_startheld run the loop; the others
# ask the dry pick (drypicks()), as the loop's pick reads the same record.
startsetup() {
  setup "[$(issue 4 2000-01-01T00:00:00Z P2)]"; C=$ST/control.json; echo : > "$STUB/build"
  ctl() { loop control "$@" 2>&1; }
  picks() { st 'select(.step == "picked") | .issue' | sort -n | tr '\n' ' '; }
  add() { jq -c ". + [$1]" "$STUB/issues.json" > "$STUB/i" && mv "$STUB/i" "$STUB/issues.json"; }
}
t_start() {
  startsetup
  # Queue, the default: a new issue is picked.
  [ "$(ctl | jq -c '[.start, .startHeld, .startSeen]')" = '["queue",[],[]]' ] && [ "$(loop health | jq -r .start)" = queue ] || fail "the default is not Queue: $(ctl)"
  loop run >/dev/null 2>&1; [ "$(picks)" = "4 " ] || fail "a new issue under Queue was not picked: $(picks)"
  for bad in 'start' 'start maybe' 'start held now'; do
    # shellcheck disable=SC2086
    out=$(ctl $bad); [ $? = 2 ] && [ "$(ctl | jq -r .start)" = queue ] || fail "control $bad was not refused with nothing changed: $out"
  done
  echo 'exit 1' > "$STUB/list-cmd"; out=$(ctl start held); [ $? = 1 ] && [ "$(ctl | jq -r .start)" = queue ] || fail "a switch with no issue number: $out"; rm "$STUB/list-cmd"
}
# The middle of t_start, from where its first part ends: Queue, #4 done (a landed line, not its card built again).
t_startheld() {
  startsetup
  landed 4 > "$ST/cards.jsonl"
  # Held: #5 (opened before the switch, in its same second) stays queued; #6 (opened after) is held and never picked;
  # #7 (a follow-up) and #10 (released before it was first seen) are picked.
  t=$(date -u +%FT%TZ); add "$(issue 5 "$t" P2)"
  [ "$(ctl start held | jq -c '[.start, .startHeld]')" = '["held",[{"from":5,"to":null}]]' ] && [ "$(loop health | jq -r .start)" = held ] || fail "start held: $(cat "$C")"
  ctl release 10 >/dev/null
  add "$(issue 6 "$t" P0),$(issue 7 "$t" P2 conveyor-followup),$(issue 10 "$t" P2)"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.control.start, .control.held, (.queue.holding | map(.issue)), (.queue.order | map(.issue) | sort), (.open.held | map(select(.issue != 4)) | map([.issue, (.reasons | map(.kind) | join(","))]))]' <<<"$out")" \
    = '["held",[6],[6],[5,7,10],[[6,"you"]]]' ] || fail "a new issue under Held is not shown held: $(jq -c '[.control, .queue, .open.held]' <<<"$out")"
  loop run >/dev/null 2>&1; [ "$(picks)" = "5 7 10 " ] || fail "picks under Held: $(picks)"
}
# The last part of t_start, from where t_startheld ends: Held since #5, #6 held when first seen, #10 released, and
# #4, #5, #7 and #10 done (landed lines, not their cards built again).
t_startqueue() {
  startsetup
  for n in 4 5 7 10; do landed "$n"; done > "$ST/cards.jsonl"
  t=$(date -u +%FT%TZ); add "$(issue 5 "$t" P2)"; ctl start held >/dev/null; ctl release 10 >/dev/null
  add "$(issue 6 "$t" P0),$(issue 7 "$t" P2 conveyor-followup),$(issue 10 "$t" P2)"
  readopen; [ "$(jq -c '[.start, .held, .startHeld]' "$C")" = '["held",[6],[{"from":5,"to":null}]]' ] || fail "the record under Held: $(cat "$C")"
  # Back to Queue, all in one second: #6 stays held; #12 (opened while it was Held, first seen after the switch) is
  # held; #13 (opened after) is picked.
  t=$(date -u +%FT%TZ); add "$(issue 12 "$t" P0)"
  [ "$(ctl start queue | jq -c '[.start, .held, .startHeld]')" = '["queue",[6],[{"from":5,"to":12}]]' ] || fail "start queue: $(cat "$C")"
  add "$(issue 13 "$t" P2)"
  readopen; drypicks
  [ "$p" = "13 " ] && [ "$(jq -c '[.held, .startSeen]' "$C")" = '[[6,12],[6,10,12]]' ] || fail "after Queue again: $p $(cat "$C")"
  # Released, #6 is picked, and is not held again however often the open issues are read.
  ctl release 6 >/dev/null; readopen; drypicks; readopen
  [ "$p" = "6 " ] && [ "$(jq -c .held "$C")" = '[12]' ] || fail "a released issue: $p $(cat "$C")"
  # A hold that cannot be saved: #14 is not shown in the queue.
  ctl start held >/dev/null; add "$(issue 14 "$t" P2)"; mkdir "$C.new"
  out=$(loop snapshot --fresh 2>/dev/null); rmdir "$C.new"
  [ "$(jq -c '[.queue.order // [] | .[].issue | select(. == 14)]' <<<"$out")" = '[]' ] || fail "an unsaved hold shown queued: $(jq -c .queue <<<"$out")"
}
# Issue 330: the filing hook's hold (`control adopt`, foreman.sh filed) comes after the command that filed the issues.
# A release given in between stays: `control hold` held #6 again, a few seconds after the owner said yes. The other
# issues filed in the same command (#7, #8) are held; #4, opened before the filing, and #9, held and released before,
# are not.
t_startadopt() {
  startsetup
  ctl start held >/dev/null; ctl hold 9 >/dev/null; ctl release 6 9 >/dev/null
  add "$(issue 6 2000-01-01T00:00:00Z P2),$(issue 7 2000-01-01T00:00:00Z P2),$(issue 8 2000-01-01T00:00:00Z P2),$(issue 9 2000-01-01T00:00:00Z P2)"
  # The record saved, not only the one printed, holds all three filed and unreleased.
  [ "$(ctl adopt 4 6 7 8 9 | jq -c '[.held, .startSeen]')" = '[[7,8],[6,7,8,9]]' ] && [ "$(jq -c '[.held, .startSeen]' "$C")" = '[[7,8],[6,7,8,9]]' ] \
    || fail "adopt: $(cat "$C")"
  # Released after the hold, #7 stays released when the hook's hold is asked again.
  ctl release 7 >/dev/null; ctl adopt 7 8 >/dev/null; [ "$(jq -c .held "$C")" = '[8]' ] || fail "adopt after a release: $(cat "$C")"
  # The owner selects Queue while the command files more: #10, filed after the span ended, is held too, as the hook
  # filed it; held only up to the span's end, it was left open to be picked.
  ctl start queue >/dev/null; add "$(issue 10 2000-01-01T00:00:00Z P2)"
  [ "$(jq -c .startHeld "$C")" = '[{"from":4,"to":9}]' ] && ctl adopt 10 >/dev/null && [ "$(jq -c .held "$C")" = '[8,10]' ] \
    || fail "an issue filed after Queue was selected was not held: $(cat "$C")"
  out=$(ctl adopt 0); [ $? = 2 ] || fail "adopt 0 was not refused: $out"
}
# Issue 453: under Queue, every new issue was picked, whoever opened it, so text from anyone with a GitHub account
# reached a card session with write tools. Bug: an issue whose author is NONE or CONTRIBUTOR (someone outside the
# project) is picked, or not shown held for that reason; one whose author is the owner, a member or a collaborator
# is held.
out() { jq -c --arg a "$2" '.authorAssociation = $a' <<<"$1"; } # <issue json> <authorAssociation>
t_startoutside() {
  startsetup
  add "$(out "$(issue 5 2000-01-01T00:00:00Z P2)" NONE),$(out "$(issue 6 2000-01-01T00:00:00Z P2)" CONTRIBUTOR),$(out "$(issue 7 2000-01-01T00:00:00Z P2)" MEMBER),$(out "$(issue 8 2000-01-01T00:00:00Z P2)" COLLABORATOR)"
  s=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.control.start, .control.held, (.queue.order | map(.issue) | sort), (.open.held | map([.issue, .reasons]))]' <<<"$s")" \
    = '["queue",[5,6],[4,7,8],[[5,[{"kind":"you","outside":true}]],[6,[{"kind":"you","outside":true}]]]]' ] \
    || fail "an issue from outside the project is queued, or not held as such: $(jq -c '[.control, .queue.order, .open.held]' <<<"$s")"
  drypicks; [ "$p" = "4 7 8 " ] || fail "picks under Queue with issues from outside the project: $p"
}
# Bug: the owner's release of an issue from outside the project does not queue it, or it is held again at the next read.
t_startoutrel() {
  startsetup
  landed 4 > "$ST/cards.jsonl"; add "$(out "$(issue 5 2000-01-01T00:00:00Z P2)" NONE)"
  loop snapshot >/dev/null; [ "$(jq -c .held "$C")" = '[5]' ] || fail "an issue from outside the project was not held: $(cat "$C")"
  ctl release 5 >/dev/null; s=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.control.held, (.queue.order | map(.issue))]' <<<"$s")" = '[[],[5]]' ] || fail "released, it is not in the queue: $(jq -c '[.control, .queue]' <<<"$s")"
  drypicks; [ "$p" = "5 " ] || fail "released, it was not picked: $p"
}
dep() { jq -c --arg b "$2" '.body = "body\n" + $b' <<<"$1"; } # <issue json> <Depends on: lines>
order() { st 'select(.step == "picked" or .step == "landed") | "\(.step):\(.issue)"' | tr '\n' ' '; }
t_depends() {
  # #7 is held: the snapshot still says what it waits on, on its held entry. The control record holds #2 and #7; their
  # backlog labels hold nothing. Bug it catches (issue 383): held #7, with its Depends on line, was in queue.waiting, so
  # the Board and /units showed it as waiting on a card, as if queued, though the loop would not pick it.
  deps_setup "$(jq -cs . <(dep "$(issue 1 2026-01-01 P1)" 'Depends on: #2') <(issue 2 2026-01-01 backlog) <(dep "$(issue 7 2026-01-01 backlog)" 'Depends on: #2'))"
  loop control hold 2 7 >/dev/null
  drypicks; [ -z "$p" ] || fail "an issue whose dependency is open was picked: $p"
  out=$(loop snapshot --fresh)
  [ "$(jq -c '[(.queue.waiting | map([.issue, .waitsFor])), (.queue.holding | map([.issue, .waitsFor])), .queue.order, .queue.next, .health.cycles]' <<<"$out")" \
    = '[[[1,[2]]],[[2,[]],[7,[2]]],[],[],[]]' ] \
    || fail "queue.waiting is not the unheld waiting issue alone, or a held entry does not say what it waits on: $(jq -c '[.queue, .health.cycles]' <<<"$out")"
  # #1 waits only on #2: it is not queued but held, its reason the wait; the four counts add up.
  [ "$(jq -c '.open | [.count, .split, (.held | map([.issue, (.reasons | map(.label // .kind) | join(","))]))]' <<<"$out")" \
    = '[3,{"queued":0,"you":1,"labelOrRule":2,"landed":0,"belt":0},[[1,"waits"],[2,"you"],[7,"you,waits"]]]' ] \
    || fail "an issue held only by a dependency is not in Held, or is counted as queued: $(jq -c .open <<<"$out")"
  # #2 closed (as not planned too: closed is closed): #1 is picked.
  echo "[$(dep "$(issue 1 2026-01-01 P1)" 'Depends on: #2')]" > "$STUB/issues.json"
  loop run >/dev/null && [ "$(order)" = "picked:1 landed:1 " ] || fail "the issue was not picked once its dependency closed: $(order)"
}
t_dependsside() {
  # The third waits for both: #12, P0 and so first if it did not wait, is picked only once the last of #10 and #11 has
  # landed. Each of the two is landed first in turn, so a #12 that waits for only one of them is picked first, ahead of
  # the open P2 issue, in the run where that one has landed. That two independent issues build side by side is t_only's run.
  setup "$(jq -cs . <(issue 10 2026-01-01 P2) <(issue 11 2026-01-02 P2) <(dep "$(issue 12 2026-01-03 P0)" 'Depends on: #10, #11'))"
  mkdir -p "$ST"; landed 10 > "$ST/cards.jsonl"
  drypicks; [ "$p" = "11 12 " ] || fail "with #10 landed, #12 was picked before #11 landed: $p"
  landed 11 > "$ST/cards.jsonl"
  drypicks; [ "$p" = "10 12 " ] || fail "with #11 landed, #12 was picked before #10 landed: $p"
}
t_dependscycle() {
  # A cycle: health names its issues, and an issue waiting on it is never picked.
  deps_setup "$(jq -cs . <(dep "$(issue 3 2026-01-01)" 'Depends on: #4') <(dep "$(issue 4 2026-01-01)" 'Depends on: #3') <(dep "$(issue 5 2026-01-01)" 'Depends on: #4') \
    <(dep "$(issue 6 2026-01-01)" 'Depends on: #6'))"
  [ "$(loop health | jq -c .cycles)" = '[[3,4],[6]]' ] || fail "health does not report the cycles: $(loop health | jq -c .cycles)"
  loop run | grep -q 'no issue qualifies' || fail "an issue in a cycle, or waiting on one, was picked: $(order)"
}
# The dependency guard. Bugs: a record written before the guard (no depGuard, no forced) not read as a whole record,
# or read with the guard off; with the guard on, an issue whose dependency is open picked once released from a hold and
# pinned first, or `control force` taken, or refused without naming the guard; with it off, a forced issue not picked
# while its dependency is open, an issue not forced picked, or the snapshot not saying which is forced, or its queued
# row (order, next) dropping what it waits on, so the Board draws it "ready" with no tag; a forced entry
# left in the record once its card has landed (its issue still open) or its issue has closed (never built).
# The Board's "Depends on…" (`control depends`): the issue's body on GitHub, the line pick reads. Bugs: an add not
# written as the `Depends on:` line pick reads (the snapshot then shows no wait), a second dependency on a line of its
# own instead of the same one, a remove that changes other bytes of the body (its trailing newline among them) or leaves
# an empty line; and a self-dependency, a closed or unknown issue, a cycle, a dependency added to an issue whose card
# runs, or a remove of a number the body does not name, written all the same, or refused with no reason.
# gh issue edit <n> --body-file <file>, as gh_write calls it: the issue's body becomes the file's bytes.
ghedits() {
  mv "$STUB/gh" "$STUB/gh0"
  printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1 $2 $4" = "issue edit --body-file" ]; then echo "$3" >> "$STUB/edits"' \
    '  jq -c --argjson n "$3" --rawfile b "$5" "map(if .number == \$n then .body = \$b else . end)" "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"; exit; fi' \
    'exec "$STUB/gh0" "$@"' > "$STUB/gh"; chmod +x "$STUB/gh"
}
# A dependency in another repository: `Depends on: other/repo#600` names that repository's #600, asked of GitHub with
# gh issue view --repo. Bug it catches (issue 605): the line was read as this repository's #600, closed here, so the
# issue was picked at once, before the other repository's issue landed. The case's build changes nothing: a picked
# card ends after its build.
t_fardeps() {
  setup "[$(dep "$(issue 1 2026-01-01 P1)" 'Depends on: other/repo#600 landing')]"; echo : > "$STUB/build"
  echo OPEN > "$STUB/repo.other_repo.600"
  # The far state is read with the open issues (asked()), so the snapshot's pick order, not `pick --dry` on the
  # file, shows what the loop would take: nothing (this repository has no open #600).
  [ "$(loop snapshot --fresh | jq -c '[(.queue.order | map(.issue)), (.queue.waiting | map([.issue, .waitsFor])), (.open.issues | map(.dependsOn))]')" = '[[],[[1,["other/repo#600"]]],[["other/repo#600"]]]' ] \
    || fail "#1 is queued while other/repo#600 is open, or the snapshot does not say it waits on it: $(loop snapshot --fresh | jq -c '[.queue, .open.issues]')"
  echo CLOSED > "$STUB/repo.other_repo.600"
  loop run >/dev/null 2>&1; [ "$(st 'select(.step == "picked") | .issue')" = 1 ] || fail "#1 was not picked once other/repo#600 closed: $(st .step)"
}
# Both repositories at once: `Depends on: #5, other/repo#7` waits on both. Bug it catches: one of the two read and the
# other dropped, so the issue is queued while one of them is still open.
t_fardepsboth() {
  setup "$(jq -cs . <(dep "$(issue 1 2026-01-01 P1)" 'Depends on: #5, other/repo#7') <(issue 5 2026-01-01 backlog))"
  loop control hold 5 >/dev/null; echo OPEN > "$STUB/repo.other_repo.7"
  waits() { loop snapshot --fresh | jq -c '[(.queue.waiting | map([.issue, .waitsFor])), (.queue.order | map(.issue))]'; }
  [ "$(waits)" = '[[[1,[5,"other/repo#7"]]],[]]' ] || fail "#1 does not wait on both #5 and other/repo#7: $(waits)"
  jq -c 'map(select(.number != 5))' "$STUB/issues.json" > "$STUB/i" && mv "$STUB/i" "$STUB/issues.json"
  [ "$(waits)" = '[[[1,["other/repo#7"]]],[]]' ] || fail "#5 closed: #1 does not still wait on other/repo#7: $(waits)"
  echo CLOSED > "$STUB/repo.other_repo.7"
  [ "$(waits)" = '[[],[1]]' ] || fail "both closed: #1 is not queued: $(waits)"
}
# A repository gh cannot read (no access, not found) counts as open: the issue waits, and Needs you names the issue,
# the line and what gh said. Bug it catches: a failed read taken as closed, so the issue is picked at once, or a wait
# nobody is told of, as the other repository's issue may be closed long ago.
t_fardepsfail() {
  setup "[$(dep "$(issue 1 2026-01-01 P1)" 'Depends on: other/repo#600')]"
  touch "$STUB/repo-fail.other_repo"
  out=$(loop snapshot --fresh) # its pick order is what the loop would take (t_fardeps)
  [ "$(jq -c '[(.queue.order | map(.issue)), (.queue.waiting | map([.issue, .waitsFor]))]' <<<"$out")" = '[[],[[1,["other/repo#600"]]]]' ] \
    || fail "#1 is queued though other/repo cannot be read, or does not wait on other/repo#600: $(jq -c .queue <<<"$out")"
  jq -e '.needsYou.farDeps == [{issue: 1, title: "title 1", ref: "other/repo#600", line: "Depends on: other/repo#600",
      reason: "GraphQL: Could not resolve to a Repository with the name '"'other/repo'"'. (repository)"}]' <<<"$out" >/dev/null \
    || fail "Needs you does not name the dependency that cannot be read: $(jq -c .needsYou.farDeps <<<"$out")"
}
t_dependsedit() {
  local orig=$'Fix the thing.\n\nIt says more.\n' b
  setup "$(jq -cs --arg b "$orig" '.[0].body = $b' <(issue 12 2026-01-01) <(issue 7 2026-01-01) <(issue 9 2026-01-01) <(dep "$(issue 5 2026-01-01)" 'Depends on: #12') <(issue 3 2026-01-01))"
  echo '[{"number":40}]' > "$STUB/closed-issues.json"
  ghedits
  body() { jq -j --argjson n "$1" '.[] | select(.number == $n) | .body' "$STUB/issues.json"; echo .; }
  is() { b=$(body 12); [ "${b%.}" = "$1" ] || fail "$2: the body of #12 is $(jq -c '.[] | select(.number == 12) | .body' "$STUB/issues.json")"; }
  out=$(loop control depends 12 add 7 2>&1) && grep -q '#12 now waits on #7' <<<"$out" || fail "depends 12 add 7: $out"
  is "${orig}Depends on: #7"$'\n' "add 7 did not append the line"
  loop snapshot --fresh | jq -e '.queue.waiting | any(.issue == 12 and .waitsFor == [7])' >/dev/null || fail "the line added is not the one pick reads: #12 does not wait on #7"
  loop control depends 12 add 9 >/dev/null 2>&1; is "${orig}Depends on: #7, #9"$'\n' "a second dependency did not extend the same line"
  loop control depends 12 remove 7 >/dev/null 2>&1; is "${orig}Depends on: #9"$'\n' "remove 7 left the line wrong"
  out=$(loop control depends 12 remove 9 2>&1) && grep -q '#12 no longer depends on #9' <<<"$out" || fail "depends 12 remove 9: $out"
  is "$orig" "removing the last dependency did not give the body back byte for byte"
  # Refused, each with its reason, and nothing written.
  printf '%s\n' '{"card":"c1-3","issue":3,"step":"picked","time":"2026-11-01T00:00:00Z","tokens":{"claude":0,"codex":0},"result":"","sha":"","reason":""}' >> "$ST/cards.jsonl"
  cp "$STUB/issues.json" "$STUB/before.json"; : > "$STUB/edits"
  for c in '12 add 12|#12 cannot depend on itself' '12 add 40|#40 is not an open issue of this project' '12 add 99|#99 is not an open issue of this project' \
      '12 add 5|would make a dependency cycle (#5, #12)' '3 add 7|#3: its card is already running; the dependency would not stop it' \
      '12 remove 7|#12 has no Depends on: line naming #7' '40 remove 7|#40 is not an open issue of this project' '12 add|usage:' '12 drop 7|usage:'; do
    # shellcheck disable=SC2086
    out=$(loop control depends ${c%%|*} 2>&1); [ $? = 2 ] && grep -qF "${c#*|}" <<<"$out" || fail "depends ${c%%|*} was not refused with \"${c#*|}\": $out"
  done
  cmp -s "$STUB/issues.json" "$STUB/before.json" && [ ! -s "$STUB/edits" ] || fail "a refused change was written: $(cat "$STUB/edits")"
  # A card of the issue that ended (here, blocked) is not running: the dependency is added.
  printf '%s\n' '{"card":"c1-3","issue":3,"step":"blocked","time":"2026-11-01T00:01:00Z","tokens":{"claude":0,"codex":0},"result":"blocked","sha":"","reason":"x"}' >> "$ST/cards.jsonl"
  loop control depends 3 add 7 >/dev/null 2>&1 && [ "$(body 3)" = $'body of 3\nDepends on: #7.' ] || fail "an issue whose card ended was refused: $(body 3)"
  # Removing #7 leaves another repository's o/r#7 on the line (bug, issue 605: it was cut to "o/r").
  jq -c 'map(if .number == 3 then .body += ", o/r#7" else . end)' "$STUB/issues.json" > "$STUB/i" && mv "$STUB/i" "$STUB/issues.json"
  loop control depends 3 remove 7 >/dev/null 2>&1 && [ "$(body 3)" = $'body of 3\nDepends on: o/r#7.' ] || fail "removing #7 changed o/r#7: $(body 3)"
}
t_depguard() {
  setup "$(jq -cs . <(issue 2 2026-01-01 P2) <(dep "$(issue 3 2026-01-02 P1)" 'Depends on: #2') \
    <(dep "$(issue 4 2026-01-03 P1)" 'Depends on: #2') <(dep "$(issue 5 2026-01-04 P1)" 'Depends on: #2'))"
  C=$ST/control.json; ctl() { loop control "$@" 2>&1; }
  [ "$(jq 'has("depGuard") or has("forced")' "$C")" = false ] || fail "the case's record is not one written before the guard: $(cat "$C")"
  [ "$(ctl | jq -c '[.depGuard, .forced]')" = '[true,[]]' ] && [ "$(loop health | jq -r .state)" = running ] \
    || fail "a record without the guard does not read whole with the guard on: $(ctl) $(loop health | jq -r .state)"
  for bad in 'dep-guard' 'dep-guard maybe' 'dep-guard on off' 'force' 'force x' 'force 3 4'; do
    # shellcheck disable=SC2086
    out=$(ctl $bad); [ $? = 2 ] && [ "$(jq 'has("depGuard")' "$C")" = false ] || fail "control $bad was not refused with nothing changed: $out"
  done
  # On: #3, released from a hold and pinned first, waits for #2 (held); force is refused, naming the guard.
  ctl hold 2 3 >/dev/null; ctl release 3 >/dev/null; ctl order 3 >/dev/null
  out=$(ctl force 3); [ $? = 2 ] && grep -q 'dependency guard is on' <<<"$out" && [ "$(ctl | jq -c .forced)" = '[]' ] || fail "control force with the guard on: $out"
  drypicks; [ -z "$p" ] || fail "with the guard on, an issue whose dependency is open was picked: $p"
  # Off: #3 forced is picked; #4 and #5, not forced, still wait.
  [ "$(ctl dep-guard off | jq .depGuard)" = false ] && [ "$(ctl force 3 | jq -c .forced)" = '[3]' ] || fail "the guard off and #3 forced: $(cat "$C")"
  out=$(loop snapshot --fresh)
  [ "$(jq -c '[(.queue.order | map(.issue)), (.queue.waiting | map([.issue, .forced]))]' <<<"$out")" = '[[3],[[3,true],[4,false],[5,false]]]' ] \
    || fail "the snapshot does not queue the forced issue, or does not say it is forced: $(jq -c .queue <<<"$out")"
  # Queued, the forced issue keeps what it waits on (Next up and Control tag it by them), in order and in next alike.
  [ "$(jq -c '[.queue.order, .queue.next] | map(map([.issue, .forced, .waitsFor]))' <<<"$out")" = '[[[3,true,[2]]],[[3,true,[2]]]]' ] \
    || fail "the queued forced issue lost what it waits on: $(jq -c .queue <<<"$out")"
  drypicks; [ "$p" = "3 " ] || fail "with the guard off, the forced issue was not picked, or one not forced was: $p"
  # #3's card landed (drypicks' landed line) and its issue closed; #4's card landed with its issue still open; #5
  # closed without a card: each leaves forced at the next read of the open issues (adopt(), as the snapshot reads them).
  ctl force 4 >/dev/null; ctl force 5 >/dev/null; landed 4 >> "$ST/cards.jsonl"
  jq -c 'map(select(.number != 3 and .number != 5))' "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  # shellcheck disable=SC2333 # the read of the open issues between the two reads of the control record rewrites it
  [ "$(jq -c .forced "$C")" = '[3,4,5]' ] && readopen && [ "$(jq -c .forced "$C")" = '[]' ] \
    || fail "a forced issue that landed, or whose issue closed, is still forced: $(cat "$C")"
}
# Bugs: an issue that depends on #50 is picked while a follow-up filed from #50, or one filed from that
# follow-up, is open (held here: one kept off the belt is still waited for), or not picked once each is closed (a
# withdrawn one too); the snapshot does not name the open follow-ups in waitsFor; an issue with no Depends on line
# waits for any of it. The case checks what is picked, not what lands: it asks the dry pick (drypicks()).
depfu() { issue "$1" 2026-01-01 conveyor-followup P1 | jq -c --arg p "$2" '.body = "Follow-up to #\($p) (Conveyor card c0-\($p)): a finding\nFollow-up depth: 1"'; } # <number> <issue it follows>
t_followdeps() {
  setup "$(jq -cs . <(dep "$(issue 60 2026-01-01 P0)" 'Depends on: #50') <(depfu 100101 50) <(depfu 100102 50) <(issue 70 2026-01-02 P2))"
  mkdir -p "$ST"; landed 50 '[100101,100102]' > "$ST/cards.jsonl"
  loop control hold 100101 100102 >/dev/null
  out=$(loop snapshot --fresh)
  [ "$(jq -c '.queue.waiting | map([.issue, .waitsFor])' <<<"$out")" = '[[60,[100101,100102]]]' ] \
    || fail "waitsFor does not name the open follow-ups of the dependency: $(jq -c .queue <<<"$out")"
  # The Board's × (control depends remove) takes what the issue's own line names (open.issues dependsOn), #50, which
  # waitsFor leaves out; a × built from waitsFor sends removals the host refuses.
  [ "$(jq -c '.open.issues | map(select(.issue == 60 or .issue == 70) | [.issue, .dependsOn])' <<<"$out")" = '[[60,[50]],[70,[]]]' ] \
    || fail "open.issues does not carry the numbers each issue's Depends on: line names: $(jq -c .open.issues <<<"$out")"
  drypicks; [ "$p" = "70 " ] || fail "#60 picked while #50's follow-ups are open, or #70 not picked: $p"
  # #100101 closes: #100102 still holds #60. #100102 has landed with a follow-up of its own, #100103: it holds #60 too.
  jq -cs . <(dep "$(issue 60 2026-01-01 P0)" 'Depends on: #50') <(depfu 100102 50) <(depfu 100103 100102) > "$STUB/issues.json"
  drypicks; [ -z "$p" ] || fail "#60 picked while #100102 is open: $p"
  jq -c '.card = "c1-100102"' <(landed 100102 '[100103]') >> "$ST/cards.jsonl"; loop control hold 100103 >/dev/null
  jq -c 'map(select(.number != 100102))' "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  [ "$(loop snapshot --fresh | jq -c '.queue.waiting | map([.issue, .waitsFor])')" = '[[60,[100103]]]' ] \
    || fail "waitsFor does not name the follow-up of a follow-up: $(loop snapshot --fresh | jq -c .queue)"
  drypicks; [ -z "$p" ] || fail "#60 picked while #100102's follow-up #100103 is open: $p"
  # #100103 is withdrawn (closed as not planned): nothing holds #60 now, and it is picked.
  echo "[$(dep "$(issue 60 2026-01-01 P0)" 'Depends on: #50')]" > "$STUB/issues.json"
  drypicks; [ "$p" = "60 " ] || fail "#60 not picked once every follow-up closed: $p"
}
# A dependency whose card landed and was not pushed (push off: its issue stays open until the push). Bug (issue 356):
# its issue being open held every issue that depends on it, though its change is on the main they are built from, so
# the queue showed "Waits for #N" and the belt sat empty until the push. One case a fixture: #80 open, #81 depends on it.
landdeps() { # <#80's card lines after its picked line, as jq -c objects>
  deps_setup "$(jq -cs . <(issue 80 2026-01-01 P2) <(dep "$(issue 81 2026-01-02 P2)" 'Depends on: #80'))"
  mkdir -p "$ST"; jq -cn --arg c c0-80 '{card: $c, issue: 80, step: "picked", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}' > "$ST/cards.jsonl"
  printf '%s\n' "$@" >> "$ST/cards.jsonl"
  pick=$(loop pick --dry --issues "$STUB/issues.json" --state "$ST" 2>&1); snap=$(loop snapshot --fresh); waits=$(jq -c '[.queue.order, .queue.waiting] | map(map([.issue, (.waitsFor // [])]))' <<<"$snap")
}
t_depslanded() {
  # #80's card has its landed line and no pushed line: #81 is picked, and the queue shows it next, waiting on nothing.
  landdeps "$(landed 80)"
  [ "$pick" = 81 ] || fail "#81 is not picked while #80's card has landed, not pushed, and #80 is open: $pick"
  [ "$waits" = '[[[81,[]]],[]]' ] || fail "the snapshot has #81 waiting on #80, which has landed: $waits"
}
t_depsblocked() {
  # #80's card is blocked (it never landed), #80 open: #81 still waits on it.
  landdeps "$(landed 80 | jq -c '.step = "blocked" | .reason = "tests failed"')"
  [ -z "$pick" ] || fail "#81 was picked while #80's card is blocked and #80 is open: $pick"
  [ "$waits" = '[[],[[81,[80]]]]' ] || fail "the snapshot does not have #81 waiting on #80, whose card is blocked: $waits"
  # Bug (issue 439): the wait named #80 only, not why #80 does not move.
  local on; on=$(jq -c '.queue.waiting[0].waitsOn' <<<"$snap")
  [ "$on" = '[{"issue":80,"state":"blocked"}]' ] || fail "the snapshot does not say #80, which #81 waits on, is blocked: $on"
}
# What a waiting issue waits on, with no card of it (issue 439). Bug: the snapshot named #80 only, so a queue of
# waiting issues did not say whether #80 is held or only queued. One case a fixture: #80 open, #81 depends on it.
depstate() { # <control args, or none>
  deps_setup "$(jq -cs . <(issue 80 2026-01-01 P2) <(dep "$(issue 81 2026-01-02 P2)" 'Depends on: #80'))"; mkdir -p "$ST"
  [ $# = 0 ] || loop control "$@" >/dev/null
  loop snapshot | jq -c '.queue.waiting | map([.issue, .waitsOn])'
}
t_depsheld() {
  local s; s=$(depstate hold 80)
  [ "$s" = '[[81,[{"issue":80,"state":"held"}]]]' ] || fail "the snapshot does not say #80, which #81 waits on, is held: $s"
}
t_depsqueued() {
  local s; s=$(depstate)
  [ "$s" = '[[81,[{"issue":80,"state":"queued"}]]]' ] || fail "the snapshot does not say #80, which #81 waits on, is queued (not picked, not held): $s"
}
t_depsrepushed() {
  # #80's first card landed, a second card for #80 blocked, then a push-now wrote the first card's pushed line. Bug: that
  # later line made the old card newest again, so #81 was picked though #80's newest card is blocked.
  local c1='{card: "c1-80", issue: 80, time: "2026-11-02T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}'
  landdeps "$(landed 80)" "$(jq -cn "$c1 + {step: \"picked\"}")" "$(jq -cn "$c1 + {step: \"blocked\", reason: \"tests failed\"}")" \
    "$(landed 80 | jq -c '.step = "pushed"')"
  [ -z "$pick" ] || fail "#81 was picked while #80's newest card is blocked (an older card's pushed line came after it): $pick"
  [ "$waits" = '[[],[[81,[80]]]]' ] || fail "the snapshot does not have #81 waiting on #80, whose newest card is blocked: $waits"
}
t_followdepscycle() {
  # A cycle through a follow-up: #60 depends on #50, whose follow-up #100101 depends on #60. Health names it, and a run
  # limited to #60 says so at its start and ends instead of polling for it forever.
  deps_setup "$(jq -cs . <(dep "$(issue 60 2026-01-01 P0)" 'Depends on: #50') <(depfu 100101 50 | jq -c '.body += "\nDepends on: #60"'))"
  mkdir -p "$ST"; landed 50 '[100101]' > "$ST/cards.jsonl"
  [ "$(loop health | jq -c .cycles)" = '[[60,100101]]' ] || fail "health does not report a cycle through a follow-up: $(loop health | jq -c .cycles)"
  # The run is waited for until it ends: one that polls forever ends at its own time limit (exit 124) instead.
  tune '.tunables.poll = 1'; CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 60 bash "$SRC/conveyor.sh" run --only 60 1 > "$STUB/cyc.out" 2>&1
  [ $? != 124 ] || fail "a run limited to an issue in a cycle through a follow-up polls forever: $(cat "$STUB/cyc.out")"
  grep -q '#60 is in a dependency cycle' "$STUB/cyc.out" || fail "a run limited to an issue in a cycle through a follow-up does not say so: $(cat "$STUB/cyc.out")"
  [ "$(order)" = "landed:50 " ] || fail "an issue in a cycle through a follow-up was picked: $(order)"
}
# "File as issue" on a declined finding (declinedbuild(), followups.sh). Bugs: the issue filed for a finding whose source
# issue is open (its card not landed) has no `Depends on` line, so it is picked at once, built on main without the
# code the finding is about, and blocked with no change; a finding whose source is closed waits on it all the same;
# a source whose state cannot be read is not waited on.
t_declineddeps() {
  local id body
  setup "[$(issue 7 2026-01-01 P2)]"
  echo OPEN > "$STUB/state.7"; : > "$STUB/state.9" # #7 open; #9's state reads empty: unknown. #8 reads CLOSED.
  for n in 7 8 9; do loop declined add "c1-$n" "$n" judge 'no proof' "[P2] f$n.txt:1 a nit" || fail "the finding of #$n was not declined"; done
  for n in 7 8 9; do
    id=$(jq -r --argjson n "$n" 'select(.issue == $n) | .id' "$ST/declined.jsonl")
    loop declined build "$id" >/dev/null || fail "build this of #$n's finding failed"
  done
  body() { jq -r --arg t "[P2] f$1.txt:1 a nit" 'select(.title == $t) | .body' "$STUB/filed"; }
  [[ $(body 7) == *$'\n\nDepends on: #7' ]] || fail "the finding of the open #7 was filed with no Depends on line at its end: $(body 7)"
  ! grep -q 'Depends on' <<<"$(body 8)" || fail "the finding of the closed #8 was filed waiting on it: $(body 8)"
  [[ $(body 9) == *$'\n\nDepends on: #9' ]] || fail "the finding of #9, whose state could not be read, was filed with no Depends on line: $(body 9)"
  # Pick does not take the new issue (#100101) while #7 is open (held here, so the pick has nothing else to take).
  loop control hold 7 >/dev/null; jq -c 'select(.number == 100101)' "$STUB/filed" | jq -cs '$i + .' --argjson i "$(cat "$STUB/issues.json")" > "$STUB/issues.new" \
    && mv "$STUB/issues.new" "$STUB/issues.json"
  drypicks; [ -z "$p" ] || fail "the issue filed from the open #7's finding was picked: $p"
  [ "$(loop snapshot --fresh | jq -c '.queue.waiting | map([.issue, .waitsFor])')" = '[[100101,[7]]]' ] || fail "the filed issue is not shown waiting on #7: $(loop snapshot --fresh | jq -c .queue)"
}
t_only() {
  deps_setup "$(jq -cs . <(issue 21 2026-01-01 P2) <(issue 22 2026-01-02 P2) <(issue 23 2026-01-03 P2) <(dep "$(issue 26 2026-01-06 P0)" 'Depends on: #21'))"
  # Three issues free to build and a limit of two, so a loop that builds past the limit builds three at once, and one
  # that does not build independent issues side by side builds one. #21 to
  # #23 each wait for two to have come before counting (or for the stub folder to go: the test's end), so a loaded
  # machine that starts or runs cards slowly still shows two side by side: a here.<n> mark is never removed, so one that
  # is paused while the other finishes still sees both; a loop that builds one at a time never reaches two. The first
  # to count does so before either has removed its in.<n> mark, so it counts both. Only #21, which #26 waits on, has to
  # land: the other builds change nothing, so those cards end after their build (blocked: no change to review).
  echo 'n=${PWD##*-}; mkdir "$STUB/in.$n" "$STUB/here.$n"; while [ -d "$STUB" ]; do [ "$n" -gt 23 ] || [ "$(ls -d "$STUB"/here.* | wc -l)" -ge 2 ] && break; sleep 0.1; done
    ls -d "$STUB"/in.* | wc -l >> "$STUB/conc"; rmdir "$STUB/in.$n"; [ "$n" != 21 ] || echo x > "f$n.txt"' > "$STUB/build"
  out=$(tune '.tunables.poll = 1'; loop run --only 21,22,23,26 2) || fail "run exited non-zero: $out"
  [ "$(st 'select(.step == "landed" or .step == "blocked") | "\(.issue):\(.step)"' | sort -n | tr '\n' ' ')" = "21:landed 22:blocked 23:blocked 26:blocked " ] \
    || fail "the run did not build all four: $(order) $out"
  [ "$(sort -n "$STUB/conc" | tail -1)" = 2 ] || fail "not two at once, or more: $(cat "$STUB/conc")"
  [ "$(order | grep -oE '(landed:21|picked:26)' | tr '\n' ' ')" = "landed:21 picked:26 " ] || fail "#26 was picked before #21 landed: $(order)"
}
t_onlyheld() {
  # A listed issue that depends on an issue outside the list is reported at the start, not silently skipped. A held
  # listed issue is neither landed, closed nor blocked: the run waits for its release, then builds it. Each build
  # changes nothing, so its card ends after it (blocked: no change to review): the case reads what is built, not
  # what lands.
  deps_setup "$(jq -cs . <(issue 30 2026-01-01 backlog) <(dep "$(issue 31 2026-01-01)" 'Depends on: #30') <(issue 33 2026-01-01))"
  loop control hold 33 >/dev/null; echo : > "$STUB/build"
  tune '.tunables.poll = 1'; watchturns; loop run --only 31,32,33 4 > "$STUB/only.out" 2>&1 & pid=$!
  said() { grep -q '#31 depends on #30, outside this run' "$STUB/only.out" && grep -q '#33 is held: the run waits until it is released' "$STUB/only.out" && grep -q '#32 is not open' "$STUB/only.out"; }
  until said || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done # its three lines, or the run's end
  ! kill -0 $pid 2>/dev/null || turns 2 # then a whole turn of the loop with nothing built
  out=$(cat "$STUB/only.out")
  grep -q '#31 depends on #30, outside this run' <<<"$out" && grep -q '#33 is held: the run waits until it is released' <<<"$out" && grep -q '#32 is not open' <<<"$out" \
    || fail "the start of the run does not report the listed issues it will not build: $out"
  kill -0 $pid 2>/dev/null && [ ! -s "$ST/cards.jsonl" ] || fail "the run ended, or built, with #33 held and #31 waiting: $out $(order)"
  loop control release 33 >/dev/null
  until [ -n "$(st 'select(.issue == 33 and .step == "blocked")')" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  kill -0 $pid 2>/dev/null || fail "the run ended once the held #33 was built, with #31 still waiting on #30: $(cat "$STUB/only.out")"
  jq -c 'map(select(.number != 30))' "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  wait $pid || fail "the run exited non-zero: $(cat "$STUB/only.out")"
  [ "$(st 'select(.step == "build") | .issue' | sort -n | tr '\n' ' ')" = "31 33 " ] || fail "the run did not build the released and the cleared issue: $(order)"
}
# The same-file check before a pick (overlap(), pick.sh). #1's card is on the belt (picked, not ended) and changes
# upnext() in conveyor/lib/pick.sh; #2 (P0) names the same function in the same file, #3 only the folder, #4 only
# README.md. The judgement is CONVEYOR_OVERLAP_CMD (<command>): it is given the prompt on stdin. Each build changes
# nothing, so its card ends after it (blocked: no change to review): the cases read what is picked.
overlapsetup() { # <the judgement's command>
  setup "$(jq -cs . <(issue 1 2026-01-01 P2 | jq -c '.body = "Change upnext() in conveyor/lib/pick.sh"') \
    <(issue 2 2026-01-02 P0 | jq -c '.body = "Make upnext() in conveyor/lib/pick.sh skip a held issue"') \
    <(issue 3 2026-01-03 P1 | jq -c '.body = "Add a new file under conveyor/lib/"') <(issue 4 2026-01-04 P2 | jq -c '.body = "Fix a typo in README.md"'))"
  echo '{"card":"c1-1","issue":1,"step":"picked","time":"2026-11-01T00:00:00Z","tokens":{"claude":0,"codex":0},"result":"ok","sha":"","reason":""}' > "$ST/cards.jsonl"
  echo : > "$STUB/build"; ghedits; export CONVEYOR_OVERLAP_CMD=$1
  picks() { st 'select(.step == "picked" and .issue != 1) | .issue' | sort -n | tr '\n' ' '; }
}
# Bugs: #2 picked beside #1's card (the two clash when the second lands), or held with no Depends on line pick reads,
# or no comment naming the file and the card; #3 or #4 held back; the judgement not shown the queued issue and the
# belt card's own text, or asked about the same issue again at every turn.
t_overlap() {
  # A stand-in for the model: DEPENDS when the queued issue names upnext(), as #1's card does; else NONE.
  overlapsetup '. "$STUB/judge"'
  printf '%s\n' 'p=$(cat); n=$(sed -n "/^# The queued issue$/{n;p;q}" <<<"$p" | grep -oE "^#[0-9]+"); echo "$n" >> "$STUB/judged"; printf "%s\n" "$p" > "$STUB/prompt.${n#\#}"' \
    'if sed -n "/^# The queued issue$/,/^# The cards on the belt$/p" <<<"$p" | grep -q "upnext()"; then echo "DEPENDS #1: conveyor/lib/pick.sh"; else echo NONE; fi' > "$STUB/judge"
  loop run >/dev/null 2>&1
  [ "$(picks)" = "3 4 " ] || fail "the issue changing the same function was picked, or one sharing only a folder or README.md was not: $(picks)"
  [ "$(jq -r '.[] | select(.number == 2) | .body' "$STUB/issues.json")" = $'Make upnext() in conveyor/lib/pick.sh skip a held issue\nDepends on: #1' ] \
    || fail "#2 did not get the Depends on line pick reads: $(jq -c '.[] | select(.number == 2)' "$STUB/issues.json")"
  grep -q '^2 --body Conveyor: this issue now waits on #1, .*conveyor/lib/pick.sh' "$STUB/comments" || fail "no comment on #2 naming the file and the card: $(cat "$STUB/comments" 2>/dev/null)"
  grep -q 'Change upnext() in conveyor/lib/pick.sh' "$STUB/prompt.2" && grep -q 'README.md is not enough' "$STUB/prompt.2" \
    || fail "the judgement was not given the belt card's text and the rule: $(cat "$STUB/prompt.2")"
  [ "$(sort "$STUB/judged" | tr '\n' ' ')" = "#2 #3 #4 " ] || fail "each queued issue was not judged exactly once: $(cat "$STUB/judged")"
}
# Bug: a judgement that fails holds the issue back, or adds a dependency all the same. overlap() itself, as the loop
# calls it before a pick (t_overlap runs the loop): the open issues it gives back are the pick's, so unchanged ones
# leave every issue to be picked as it is.
t_overlapfail() {
  overlapsetup ': > "$STUB/judged"; cat > /dev/null; exit 1'
  fx_in 'overlap "$(cat "$STUB/issues.json")" "" "$(ctl)"; printf "%s\n" "$OVL" > "$STUB/ovl"'
  [ "$RC" = 0 ] && [ -e "$STUB/judged" ] || fail "overlap() failed (exit $RC), or did not ask the judgement: $(cat "$T/$CASE/run.out")"
  [ "$(jq -c . "$STUB/ovl")" = "$(jq -c . "$STUB/issues.json")" ] && [ ! -s "$STUB/edits" ] \
    || fail "with the judgement failing, an issue was changed or got a dependency: $(cat "$STUB/ovl") $(cat "$STUB/edits" 2>/dev/null)"
}
# The same-file check asked of the builder's Claude seat itself (askmodel(), no CONVEYOR_OVERLAP_CMD), whose stub
# answers as Claude Code does with --output-format json: a result record. Bug (issue 881's lead): a stub, or an
# askmodel(), out of step with that form fails every check, and each card is picked without it.
t_overlapseat() {
  setup "[$(issue 1 2026-01-01), $(issue 2 2026-01-02)]"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$STUB/asked"; echo "$*" > "$STUB/args"' \
    'j=$(jq -cn '"'"'{type: "result", is_error: false, subtype: "success", result: "DEPENDS #1: conveyor/lib/pick.sh", num_turns: 1}'"'"')' \
    '[[ " $* " == *" --output-format json "* ]] && echo "$j" || jq -r .result <<<"$j"' > "$STUB/claude"
  fx_in 'unset CONVEYOR_OVERLAP_CMD; overlapcall 2 "[1]" "$(cat "$STUB/issues.json")" ""'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = $'1\tconveyor/lib/pick.sh' ] \
    || fail "the same-file check on the Claude seat gave no answer (exit $RC): $(cat "$T/$CASE/run.out") (asked with: $(cat "$STUB/args" 2>/dev/null))"
  grep -q '^# The queued issue$' "$STUB/asked" || fail "the seat was not asked the same-file question: $(head -c 300 "$STUB/asked")"
}
