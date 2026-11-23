#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the start rule, where new issues start (Queue or Held), and issues from outside the project.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
# shellcheck disable=SC2154 # p is set by drypicks() in deps.test.sh
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# drypicks and readopen are deps.test.sh's: the runner loads every case file into one shell. A change to deps.test.sh's
# helpers or setup runs this file too, through its link in .conveyor/test-links.json.

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
# are not. The filing hook marks the record (`control filing on`) before the command runs, as foreman.sh filing does.
t_startadopt() {
  startsetup
  ctl start held >/dev/null; ctl filing on >/dev/null; ctl hold 9 >/dev/null; ctl release 6 9 >/dev/null
  [ "$(jq -c .filing "$C")" = 4 ] || fail "filing on did not mark the newest issue, #4: $(cat "$C")"
  add "$(issue 6 2000-01-01T00:00:00Z P2),$(issue 7 2000-01-01T00:00:00Z P2),$(issue 8 2000-01-01T00:00:00Z P2),$(issue 9 2000-01-01T00:00:00Z P2)"
  # The record saved, not only the one printed, holds all three filed and unreleased.
  [ "$(ctl adopt 4 6 7 8 9 | jq -c '[.held, .startSeen]')" = '[[7,8],[6,7,8,9]]' ] && [ "$(jq -c '[.held, .startSeen]' "$C")" = '[[7,8],[6,7,8,9]]' ] \
    || fail "adopt: $(cat "$C")"
  # Released after the hold, #7 stays released when the hook's hold is asked again.
  ctl release 7 >/dev/null; ctl adopt 7 8 >/dev/null; [ "$(jq -c .held "$C")" = '[8]' ] || fail "adopt after a release: $(cat "$C")"
  # The owner selects Queue while the command files more: #10, filed after the span ended (but after the filing
  # mark), is held too, as the hook filed it; held only up to the span's end, it was left open to be picked.
  ctl start queue >/dev/null; add "$(issue 10 2000-01-01T00:00:00Z P2)"
  [ "$(jq -c .startHeld "$C")" = '[{"from":4,"to":9}]' ] && ctl adopt 10 >/dev/null && [ "$(jq -c .held "$C")" = '[8,10]' ] \
    || fail "an issue filed after Queue was selected was not held: $(cat "$C")"
  out=$(ctl adopt 0); [ $? = 2 ] || fail "adopt 0 was not refused: $out"
}
# Bug (R247): adopt held any issue opened after a span's start, with no bound at the span's end, so a command that
# filed #11 and printed the url of #10 (opened in the queue between two Held spans) held #10 too. Only #11 is held.
t_startadoptold() {
  startsetup
  ctl start held >/dev/null; add "$(issue 5 2000-01-01T00:00:00Z P2)"; ctl start queue >/dev/null
  add "$(issue 10 2000-01-01T00:00:00Z P2)"; ctl start held >/dev/null; ctl filing on >/dev/null
  add "$(issue 11 2000-01-01T00:00:00Z P2)"
  [ "$(jq -c '[.startHeld, .filing]' "$C")" = '[[{"from":4,"to":5},{"from":10,"to":null}],10]' ] || fail "the spans and the filing mark: $(cat "$C")"
  [ "$(ctl adopt 10 11 | jq -c .held)" = '[11]' ] || fail "adopt 10 11, #10 opened in the queue between the spans, did not hold #11 alone: $(cat "$C")"
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
