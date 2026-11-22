# SPDX-License-Identifier: Apache-2.0
# A card's failures that are not its own: what still did not pass runs again on main (verdicts()), a failure the machine
# makes holds the loop (machinehold(), the repair lane: repairlane()), and a case that fails on main goes to the fix
# card of main's commit (mainred(), redpick(), redrun()), while the cards it fails wait for main (mainwait()). Sourced
# by lib/testrun.sh.
# Before a card's failure goes to its fix session (card()), what still did not pass after the run again runs on main
# (the owner, 2026-11-14: a fix session cannot repair main or the machine): in a worktree of main's commit as it is now
# ($CARDS/mainrun/<card>), on a test slot, under the card's test time limit (testTimeout, which ends it even while it
# waits for a whole-suite turn), with test.fileCommand, each failing file run alone once, its list (CONVEYOR_TEST_RERUN)
# naming every other file of the card's runs as passed (those of its last run, and those its own list names) and, of a
# file with failing cases, those cases; a file that failed naming no case or ran out of time, as `fail\t<file>` with no
# case (the command runs it whole: on main's clean tree nothing else selects it). Each failure's
# verdict, as notpassed() names it:
# - main: the same case (or the same file failing naming no case) failed on main too, an input of its file changed
#   since its last recorded pass (the file has no pass in the test results cache with main's content: testlist.sh cachehits()),
#   and a control passed beside it, or no control could run (below). A timeout or a kill on main says nothing of the case.
#   The test command itself (testfails()'s name for a run that logged no file) gets no verdict: it names no test (a
#   card's run whose only failure it is gave no result: voidrun()).
# - machine (issue 221): it failed on main too, but its file passed before with the same inputs, or every control failed:
#   the machine's, not main's (machinehold()). The controls are the files of the pack's test.control that have a
#   recorded pass on main's content (testlist.sh cachehits()), or all of them when the cache has no pass on main's content at all
#   (a test command that logs no `TESTRUN inputs` lines records none), and are not among the failing files: main's run
#   runs them too, on the same slot (CONVEYOR_TEST_ONESLOT: a runner of the command runs its workers one at a time on
#   the run's slot, slot_take), each named `fail` in its list. With no control that could run, nothing tells the
#   machine from main, and a failure whose inputs changed is main's, as before issue 221.
# - card: it passed on main, or main's run did not run it (its worktree could not be made, the command did not
#   select it, the pack sets no test.fileCommand and its test command cannot be given one file (#1275), or its file
#   is one the card's own change adds, which main does not have: issue 323): the card's to fix, as before. A file the change edits runs on main in main's version: failing there too, it is main's. A
#   document (#367) is no test file and does not run on main: its failure is the card's, with why "no test file: a
#   selection error".
# - flaky: it failed on the first run and passed on the run again (PASSEDAGAIN; flakyrun() records it).
# Prints the test line's part: {verdicts: [{case, verdict, why (a document's alone)}]} and, when the cases ran on main, mainRun: {sha, sec (the
# seconds main's run took, its wait for a slot included), exit}, and brokeMain, the card whose landing turned main red, when the main-red
# record knows it for a case of verdict main. Each case whose verdict is main goes to the fix card of main's commit (mainred());
# each whose verdict is machine to the machine hold (machinehold()), and to no fix card.
# The card's own TEST_WAIT, TEST_RUN and TEST_FREE are kept (testrec()).
verdicts() { # <card> <worktree> <testfails() of the card's last run, or null>
  local mwt=$CARDS/mainrun/${2##*/} sha='' u um nt m=null mf=null s rc out='' fst v c f b w=$TEST_WAIT r=$TEST_RUN fr=$TEST_FREE cmd='' hits='[]' ctl='[]' cf='[]' chg lim
  packget test.command cmd test.control ctl 2>/dev/null || { cmd=''; ctl='[]'; }
  # The units that still did not pass, each {file, case}: case null for a file that failed naming no case or ran out of
  # time. The test command itself with no case (testfails()'s name for a run that logged no file) is none: it names no test.
  u=$(jq -c --arg cmd "$cmd" '[.files[] | .file as $f | if .cases == [] then {file: $f, case: null} else .cases[] | {file: $f, case: .name} end]
    + [.timeout.file // empty | {file: ., case: null}] | unique | map(select(.case != null or .file != $cmd))' <<<"$3" 2>/dev/null) || u='[]'
  # The files the card's own change (staged) adds (issue 323): main has no such file, so it cannot run there. Such a
  # unit is the card's (card) and does not run on main. When the change cannot be read, no unit runs on main: each is
  # the card's.
  chg=$(git -C "$2" diff --cached --name-only --no-renames --diff-filter=A HEAD 2>/dev/null) && chg=$(jq -cRn '[inputs | select(. != "")]' <<<"$chg") || chg=null
  # A document (.md, .txt, .rst: #367) is no test file, and was on the run by a selection error. Its failure is the
  # card's (card, its why saying so), never main's: it does not run on main and goes to no main-red entry. (A file
  # the test command names is not held to tests.patterns here: a pack whose patterns miss its test files keeps its
  # main-red record.)
  nt=$(jq -c '[.[].file | select(test("\\.(md|txt|rst)$"; "i"))] | unique' <<<"$u") || nt='[]'
  jq -r '.[]' <<<"$nt" | while IFS= read -r f; do echo "conveyor: card $1: $f is no test file: its failure is a selection error of the card's run, not main's" >&2; done
  um=$(jq -c --slurpfile c <(printf '%s' "$chg") --argjson nt "$nt" '$c[0] as $c | if $c == null then [] else map(select(.file | IN($c[], $nt[]) | not)) end' <<<"$u") || um='[]'
  if [ "$um" != '[]' ]; then
    if sha=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null) \
      && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
        && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt"; } 2>&1 < /dev/null) \
      && { hits=$(cachehits "$mwt" | jq -cRn '[inputs | select(. != "")]') || hits='[]'
        ctl=$(jq -cn --slurpfile h <(printf '%s' "$hits") --slurpfile u <(printf '%s' "$u") --slurpfile c <(printf '%s' "${ctl:-[]}") '$h[0] as $h | $u[0] as $u | $c[0] as $c | [$c | arrays[] | strings | select(($h == [] or IN($h[])) and (IN($u[].file) | not))] | unique' 2>/dev/null) || ctl='[]'; } \
      && jq -r --slurpfile u <(printf '%s' "$u") --slurpfile um <(printf '%s' "$um") --slurpfile ctl <(printf '%s' "$ctl") --rawfile k <(awk -F'\t' '$1 == "pass" || $1 == "ok" || $1 == "fail" {print $2}' "$2.rerun" 2>/dev/null) \
        '$u[0] as $u | $um[0] as $um | $ctl[0] as $ctl | ([.passed[]?, .files[]?.file, .okcases[]?.file, .passcases[]?.file, (.timeout.file // empty), ($k | split("\n")[] | select(. != ""))]
          | unique - [$u[].file] - $ctl | .[] | "pass\t\(.)"),
        ($um[] | if .case == null then "fail\t\(.file)" else "fail\t\(.file)\t\(.case)" end), ($ctl[] | "fail\t\(.)")' <<<"$3" > "$mwt.rerun"; then
      # Its limit (issue 420): the card's own (testTimeout), never none, kept by timeout itself (TEST_HARD), as a
      # runner waiting for a whole-suite turn stops the run's clock. Each failing file runs alone through
      # test.fileCommand, as the card's own run does, once however many of its cases failed. With none set, it runs
      # the way the pack's test command runs it (TEST_PACKONLY: testlist.sh nofilecmd(), #1275), never with Conveyor's
      # own runner: a file that fails only there is not main's. When the test command cannot be given one file,
      # nothing runs on main (<worktree>.stop), and each failure is the card's.
      lim=${TEST_TIMEOUT:-}; [[ $lim =~ ^[1-9][0-9]*$ ]] || { packget tunables.testTimeout lim 2>/dev/null && [[ $lim =~ ^[1-9][0-9]*$ ]]; } || lim=3600
      awk -F'\t' -v OFS='\t' '$1 != "fail" { print; next } !s[$2]++ { print "fail", $2 }' "$mwt.rerun" > "$mwt.rerun.new" && mv -f "$mwt.rerun.new" "$mwt.rerun"
      s=$SECONDS; TEST_PACKONLY=1 CONVEYOR_TEST_ONESLOT=1 TEST_HARD=$lim tests "$mwt" test.fileCommand alone; rc=$?; s=$((SECONDS - s))
      # A run that passed failed nothing (testfails() names a command that wrote no log as a file whatever its exit);
      # one that did not run (<worktree>.stop) ran nothing on main.
      if [ -s "$mwt.stop" ]; then mf=null; echo "conveyor: card $1: its failing cases did not run on main: $(head -n 1 "$mwt.stop")" >&2; elif [ $rc = 0 ]; then mf='{"files":[]}'; else mf=$(testfails "$mwt.test" "$rc") || mf=null; fi
      # The controls that did not pass: each one the run did not end ok (failed, timed out or not run).
      [ $rc = 0 ] || cf=$(jq -c --slurpfile c <(printf '%s' "$ctl") '$c[0] as $c | [.passed // []] as $p | [$c[] | select(IN($p[0][]) | not)]' <<<"${mf:-null}" 2>/dev/null) || cf=$ctl
      m=$(jq -cn --arg sha "$sha" --argjson s "$s" --argjson rc "$rc" '{sha: $sha, sec: $s, exit: $rc}')
    else
      echo "conveyor: card $1: its failing cases could not be run on main: ${out:-the commit of main could not be read}" >&2
    fi
    git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  fi
  TEST_WAIT=$w; TEST_RUN=$r; TEST_FREE=$fr
  fst=$(jq -ce objects "$2.first" 2>/dev/null) || fst=null
  v=$(jq -cn --slurpfile u <(printf '%s' "$u") --slurpfile um <(printf '%s' "$um") --slurpfile m <(printf '%s' "${mf:-null}") --slurpfile l <(printf '%s' "${3:-null}") \
    --slurpfile fst <(printf '%s' "$fst") --slurpfile h <(printf '%s' "$hits") --slurpfile ctl <(printf '%s' "${ctl:-[]}") --slurpfile cf <(printf '%s' "$cf") --argjson nt "$nt" \
    '$u[0] as $u | $um[0] as $um | $m[0] as $m | $l[0] as $l | $fst[0] as $fst | $h[0] as $h | $ctl[0] as $ctl | $cf[0] as $cf | '"$NOTPASSED$PASSEDAGAIN"'
    [($fst | select(. != null) | passedagain($l)[] | {case: ., verdict: "flaky"}),
     ($u[] | . as $x | {case: (if .case == null then .file else "\(.file): \(.case)" end), file,
       verdict: (if $m != null and ($x | IN($um[])) and any($m.files[]?; .file == $x.file and (if $x.case == null then .cases == [] else any(.cases[]; .name == $x.case) end))
         then (if ($x.file | IN($h[]) | not) and ($ctl == [] or $ctl - $cf != []) then "main" else "machine" end) else "card" end)}
       + if $x.file | IN($nt[]) then {why: "no test file: a selection error"} else {} end)]') || v='[]'
  while IFS=$'\t' read -r c f; do mainred "$1" "$c" "$f" "$sha" || :; done < <(jq -r '.[] | select(.verdict == "main") | [.case, .file] | @tsv' <<<"$v")
  # A machine verdict holds the loop (machinehold()) until the controls that failed, and the files that failed with
  # the inputs they last passed with, pass on main again (a file whose inputs changed may fail there for good).
  jq -e 'any(.[]; .verdict == "machine")' <<<"$v" >/dev/null \
    && { machinehold "$1" "$sha" "$(jq -c --slurpfile cf <(printf '%s' "$cf") --slurpfile h <(printf '%s' "$hits") '$cf[0] as $cf | $h[0] as $h | $cf + [.[] | select(.verdict == "machine") | .file | select(IN($h[]))] | unique' <<<"$v")" \
      "$(jq -c '[.[] | select(.verdict == "machine") | .case]' <<<"$v")" || :; }
  # brokeMain: the card whose landing turned main red, as the main-red record keeps it for a case of verdict main
  # (mainred(): landing), the entry of main's commit first, then the newest; none when no landing is known.
  b=$(jq -r --arg s "$sha" --slurpfile v <(printf '%s' "$v") '[$v[0][] | select(.verdict == "main") | .case] as $mc
    | (.reds // []) | [(map(select(.sha == $s)) + reverse)[] | .cases[]? | select(.case | IN($mc[])) | .landing.card? | strings] | first // empty' "$MAINRED" 2>/dev/null) || b=''
  jq -cn --slurpfile v <(printf '%s' "$v") --slurpfile m <(printf '%s' "$m") --arg b "$b" '$v[0] as $v | $m[0] as $m | {verdicts: [$v[] | {case, verdict} + if .why then {why} else {} end]} + if $m then {mainRun: $m} else {} end
    + if $b == "" then {} else {brokeMain: $b} end'
}
# The machine hold (issue 221): a case that failed on main as on the card, though its inputs did not change since it
# last passed (testlist.sh cachehits()), or while every control (verdicts()) that ran beside it on the same slot failed, is the
# machine's (verdicts(): machine), not main's. $MACHINEHOLD keeps
# {since, card, sha, controls, cases}: when the hold began, the card and main's commit that found it, the test files
# that must pass on main again (the controls that failed, and the failing files that passed before with the same
# inputs) and the cases. While it
# stands the loop picks no card (machineheld(), run()) and a card whose failures are the machine's waits for it to go
# (holdwait()), unless the repair lane passes it (repairlane()); health shows it (machineHold), which wakes the Foreman once. A hold found while one stands adds its
# files and cases to it, its since kept. One writer at a time (a lock of its own).
machinehold() { # <card> <main's commit> <the files, json> <the cases, json>
  local lock
  { exec {lock}>>"$MACHINEHOLD.lock"; } 2>/dev/null && flock "$lock" || { echo "conveyor: the machine hold could not be locked: the loop is not held" >&2; return 1; }
  jq -cn --slurpfile o <(jq -ce objects "$MACHINEHOLD" 2>/dev/null) --arg c "$1" --arg s "$2" --slurpfile f <(printf '%s' "$3") --slurpfile k <(printf '%s' "$4") \
    '$f[0] as $f | $k[0] as $k | ($o[0] // {since: (now | todate), card: $c, sha: $s, controls: [], cases: []}) | .controls = (.controls + $f | unique) | .cases = (.cases + $k | unique)' \
    > "$MACHINEHOLD.new" && mv -f "$MACHINEHOLD.new" "$MACHINEHOLD" || { exec {lock}>&-; echo "conveyor: the machine hold could not be written: the loop is not held" >&2; return 1; }
  exec {lock}>&-
}
# What the loop says while the machine hold stands, nothing when none does: the files that must pass on main again.
machineheld() {
  jq -re 'objects | "the machine fails \(.controls | join(", ")) on main, with no change to main that explains it (found by card \(.card) at \(.sha[0:12]), since \(.since): no card is picked until they pass again"' "$MACHINEHOLD" 2>/dev/null || :
}
# The loop's look at the hold (run()), at most once every POLL seconds while it stands: the hold's files run on main as it is now, in a
# worktree of its commit ($CARDS/mainrun/machine), on a test slot, each alone through test.fileCommand, its list
# naming each as `fail`. When they all pass the hold goes, unless
# files were added to it meanwhile, and the loop picks again; the cards on hold run their test step again.
machineprobe() {
  local h wt=$CARDS/mainrun/machine sha rc=1 lock
  h=$(jq -ce objects "$MACHINEHOLD" 2>/dev/null) || return 0
  if sha=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null) \
    && { git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt" "$wt".*; git worktree prune; mkdir -p "${wt%/*}" \
      && git worktree add -q --detach "$wt" "$sha" && deps "$wt"; } > /dev/null 2>&1 < /dev/null \
    && jq -r '.controls[] | "fail\t\(.)"' <<<"$h" > "$wt.rerun"; then
    tests "$wt" test.fileCommand alone; rc=$?
  fi
  git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt" "$wt".*; rmdir "${wt%/*}" 2>/dev/null
  [ $rc = 0 ] || return 1
  { exec {lock}>>"$MACHINEHOLD.lock"; } 2>/dev/null && flock "$lock" || return 1
  [ "$(jq -c .controls "$MACHINEHOLD" 2>/dev/null)" != "$(jq -c .controls <<<"$h")" ] || rm -f "$MACHINEHOLD" "$MACHINEHOLD.lane"
  exec {lock}>&-
}
# A card whose failures are the machine's (verdicts(): machine, and none the card's) waits in its test step until the
# hold goes (machineprobe()), its live record saying so and brought up to date as it waits, and <worktree>.idle
# standing, as for a red main (mainwait()). Given lane, it waits for the repair lane (repairlane()) too: it ends as
# soon as no other card holds the lane, so that the card is tested and judged again.
holdwait() { # <worktree> [lane]
  local at h; at=$(date -u +%FT%TZ)
  while [ -e "$MACHINEHOLD" ]; do
    h=''; [ -z "${2:-}" ] || { h=$(repairholder); [ -n "$h" ] || break; }
    jq -cn --arg at "$at" --arg c "$(machineheld)" --arg h "$h" '{step: "test", at: $at, last: (now | todate), turns: 0, files: {run: 0, of: null}, tests: null,
      action: (if $h == "" then "waiting for the machine: \($c)" else "waiting for the repair lane: card \($h) is judged by the controls; \($c)" end)}' > "$1.live.tmp" 2>/dev/null && mv -f "$1.live.tmp" "$1.live"
    : > "$1.idle"; sleep "$LIVE"
  done
  rm -f "$1.live" "$1.idle"
}
# The repair lane (issue 222). While the machine hold stands, a card whose failures are the machine's (verdicts():
# machine, none the card's) may be a fix of the test step itself, which its own test step, run under the running
# engine's harness, cannot pass. One card at a time takes the lane (<machine hold>.lane: {card, pid, started}, its
# card's process; the lane is free when no live process holds it) and is judged by the hold's files instead
# (repairproof()). A card that the lane passes lands; it keeps the lane until its process ends. A card that it does
# not pass gives the lane up and waits for the hold to go (holdwait()). A card that finds the lane held waits until
# it is free (holdwait() lane). Exit 0 when the card repairs the machine (REPAIRED says how), 1 when it does not
# (REPAIRED says why), 2 when another card holds the lane. Called in the card's own process, never in $(...).
repairlane() { # <card> <worktree>
  local lock h r=2 me=$BASHPID st # me: this process; $BASHPID read inside $(...) is the substitution's own
  REPAIRED=''
  { exec {lock}>>"$MACHINEHOLD.lock"; } 2>/dev/null && flock "$lock" || return 2
  if h=$(repairholder) && { [ -z "$h" ] || [ "$h" = "$1" ]; } && st=$(p_started "$me") && [ -n "$st" ]; then
    jq -cn --arg c "$1" --argjson p "$me" --arg s "$st" '{card: $c, pid: $p, started: $s}' > "$MACHINEHOLD.lane.new" \
      && mv -f "$MACHINEHOLD.lane.new" "$MACHINEHOLD.lane" && r=0
  fi
  exec {lock}>&-
  [ $r = 0 ] || return 2
  repairproof "$1" "$2" && return 0
  { exec {lock}>>"$MACHINEHOLD.lock"; } 2>/dev/null && flock "$lock" && { [ "$(repairholder)" != "$1" ] || rm -f "$MACHINEHOLD.lane"; exec {lock}>&-; }
  return 1
}
# The card that holds the repair lane; nothing when it is free (no lane, or its holder's process has ended).
repairholder() {
  local h
  h=$(jq -r 'objects | "\(.card)\t\(.pid)\t\(.started)"' "$MACHINEHOLD.lane" 2>/dev/null) && [ -n "$h" ] || return 0
  IFS=$'\t' read -r -a h <<<"$h"
  ! p_alive "${h[1]}" "${h[2]}" || printf '%s\n' "${h[0]}"
}
# The repair lane's judgement of a card (repairlane()), in the shape of bugproof.sh redproof(): the files of the machine hold run
# in a worktree of the commit the card was built on (its HEAD), $CARDS/mainrun/<card>.repair, each named `fail` in
# the run's list, each alone through the pack's test.fileCommand (else Conveyor's own runner: testlist.sh ownrunner()): first without the card's change, where they must
# fail, then with it staged, where they must pass. The run without the change must fail with a control its logs
# (testfails()) name failed or out of time: a run that fails for another reason (one that stops before any file runs)
# proves nothing. The run with the change must name every control passed and at least one case that passed (passcases):
# each file's run that exits 0 is logged ok (filecmd()), so a harness that ends each run at once with exit 0 would pass
# without running a case. Then the card's changed tests run in its own worktree (each alone, as its
# test step runs them: listcmd(), and no list of earlier passes), and must pass. Each of the three runs is a clean one
# (cleanrun()). The control runs are given none of the card's test files (CONVEYOR_TEST_FILES empty, as on main's run,
# verdicts()): a pack's test.fileCommand that runs each file that list names would fail the control's own run on a
# file the change adds, which this commit lacks, and that failure be taken for the control's. Sets REPAIRED: what the runs showed.
# shellcheck disable=SC2034 # REPAIRED is read by card() (lib/card.sh)
repairproof() { # <card> <worktree>
  local mwt=$CARDS/mainrun/$1.repair cj cs sha='' out cmd rc=1 brc=0 LISTNONE='' TEST_GIVEN='' RUNOFF='' TEST_CASES='' TEST_FILES=''
  cj=$(jq -ce 'objects | .controls | select(length > 0)' "$MACHINEHOLD" 2>/dev/null) || { REPAIRED="the machine hold names no file to run"; return 1; }
  cs=$(jq -r 'join(", ")' <<<"$cj")
  if ! packget test.fileCommand cmd 2>/dev/null; then REPAIRED="the pack's test.fileCommand could not be read"
  elif [ -z "$cmd" ] && ! cmd=$(mapfile -t fl < <(jq -r '.[]' <<<"$cj"); ownrunner "$2" "${fl[@]}"); then REPAIRED=$(narrowstop "$cmd")
  elif cmd=$(filecmd "$cmd") && sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt"; } 2>&1 < /dev/null) \
    && jq -r '.[] | "fail\t\(.)"' <<<"$cj" > "$mwt.rerun"; then
    cleanrun "$mwt" "$cmd" "$mwt.rerun" || brc=$?
    if [ "$brc" = 0 ]; then
      REPAIRED="$cs passed on main's code at ${sha:0:12} without the change in a clean harness, so the change repairs nothing there"
    elif ! testfails "$mwt.test" "$brc" | jq -e --argjson c "$cj" '[.files[]?.file, .timeout.file?] as $f | any($c[]; IN($f[]))' >/dev/null 2>&1; then
      REPAIRED="the run on main's code at ${sha:0:12} without the change failed, but its logs do not say that $cs failed in it, so it proves nothing"
    elif ! out=$(git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index 2>&1); then
      REPAIRED="the change could not be applied to main's code at ${sha:0:12}, so $cs did not run with it: ${out:0:400}"
    elif ! cleanrun "$mwt" "$cmd" "$mwt.rerun"; then
      REPAIRED="$cs still failed with the change in a clean harness"
    elif ! testfails "$mwt.test" 0 | jq -e --argjson c "$cj" '.passed as $p | all($c[]; IN($p[])) and ([.passcases[]?.cases[]?] != [])' >/dev/null 2>&1; then
      REPAIRED="the run with the change passed, but its logs do not say that $cs passed in it"
    # A change linked to no test file runs none (listcmd()), and one whose list cannot be made stops with why
    # (<worktree>.stop).
    elif ! { rm -f "$2.stop"; listcmd "$2" 2>"$2.test" &&{ [ -n "$LISTNONE" ] || cleanrun "$2" "$LISTCMD"; }; }; then
      if [ -s "$2.stop" ]; then REPAIRED="$cs failed on main's code at ${sha:0:12} without the change and passed with it, but the card's changed tests did not run: $(<"$2.stop")"
      else REPAIRED="$cs failed on main's code at ${sha:0:12} without the change and passed with it, but the card's changed tests failed in a clean harness"; fi
    else
      REPAIRED="repair lane: $cs failed on main's code at ${sha:0:12} without the change and passed with it, and the card's changed tests passed, each in a clean harness"; rc=0
    fi
  else
    REPAIRED="$cs could not be run on main's code at ${sha:-a commit that could not be read}: ${out:0:400}"
  fi
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  return $rc
}
# One run of <command> in <worktree> in a clean harness (repairproof()): a session of its own (p_setsid), no file
# descriptor above 2 of the loop's (closefds), and a minimal environment: the loop's PATH, HOME, USER, LOGNAME, LANG,
# LC_ALL, TMPDIR and XDG_CONFIG_HOME, and the variables a run is given (README.md), with the load factor
# (CONVEYOR_LOAD_FACTOR: loadfactor(), lib/loadfactor.sh) as testonce() gives it. CONVEYOR_TEST_SLOTS names the
# worktree's own conveyor/lib/slots.sh when it has one (the engine's own repository: the harness the change may
# repair), else the running engine's. It holds no test slot of the loop's: the runners take their own. Output in
# <worktree>.test, progress logs in <worktree>.testlog; exit as the command's, under the test timeout.
cleanrun() { # <worktree> <command> [<list>]
  local lib=$HERE/lib e=() v pid rs=''
  [ ! -f "$1/conveyor/lib/slots.sh" ] || lib=$1/conveyor/lib
  for v in PATH HOME USER LOGNAME LANG LC_ALL TMPDIR XDG_CONFIG_HOME; do [ -z "${!v+x}" ] || e+=("$v=${!v}"); done
  rm -rf "$1.testlog" "$1.report"; mkdir "$1.testlog" 2>"$1.test" || return 1
  # A suite runner on <list> is taken off it (testlist.sh runnersoff(), #382); a list so left with no `fail` line runs nothing.
  # The output names each, with those listcmd() took off its command's list (RUNOFF).
  [ -z "${3:-}" ] || { rs=$(runnersoff "$3"); [ -z "$rs" ] || grep -q $'^fail\t' "$3" || { runnernote "$rs" > "$1.test"; return 1; }; }
  rs=$(printf '%s\n' "${RUNOFF:-}" "$rs" | grep . | sort -u)
  (cd "$1" && closefds && p_setsid env -i "${e[@]}" CONVEYOR_LOAD_FACTOR="$(loadfactor)" CONVEYOR_TEST_SLOTS="$lib/slots.sh" CONVEYOR_TEST_LOG="$1.testlog" CONVEYOR_TEST_RERUN="${3:-}" \
    CONVEYOR_TEST_FILES="${TEST_FILES:-}" CONVEYOR_TEST_CASES="${TEST_CASES:-}" timeout --kill-after=30 "$TEST_TIMEOUT" bash -c "$2") > "$1.test" 2>&1 < /dev/null &
  pid=$!
  watch $pid "$1.test" "$1.live" test; v=$?; runnernote "$rs" >> "$1.test"; return $v
}
# One run of bugproof.sh redproof(): the cases <cases json> ([{name, file, files, case}], case "" for a file that failed naming no
# case; files, the files that define it, mainred()) alone in <worktree>, each a `fail` line of the run's list
# (CONVEYOR_TEST_RERUN), as verdicts() runs them on main. A case's result is under its file or, as a run names an
# engine case file's case under that file where an entry made before issue 214 named the runner, under one of its
# files. Prints the cases, each with its verdict: fail when the run's logs (testfails()) name it failed (or its file failed,
# for a file alone, or ran out of time); pass when they name it passed (a passed case's line under its file, as
# testfails() reads it; a file alone, when its file passed: a passing file whose named case did not run, as when the
# change renames it, is no proof of
# that case); none when they name neither. A command that writes no logs says only its exit, of every case: run
# through test.fileCommand (filecmd(), whose own log, `files`, is then the run's only one), its exit for each file,
# of every case of that file.
redrun() { # <worktree> <cases json>
  local rc t=null
  # A case its entry names under a suite runner (SUITERUNNERS, which a card's list holds no line of: #382) runs under
  # its own files.
  names > /dev/null 2>&1 || :
  jq -r --arg rn "${SUITERUNNERS:-}" '($rn | split("\n")) as $rn | .[] | [.files[]? | select(IN($rn[]; .) | not)] as $own
    | if .case == "" then "fail\t\(.file)" elif IN($rn[]; .file) and $own != [] then (.case as $c | $own[] | "fail\t\(.)\t\($c)")
      else "fail\t\(.file)\t\(.case)" end' <<<"$2" > "$1.rerun"
  # With no test.fileCommand, the way the pack's test command runs a file, as verdicts() runs it (#1275); when that
  # cannot be given one file, nothing runs (<worktree>.stop), and the run names no case: none.
  TEST_PACKONLY=1 tests "$1" test.fileCommand alone; rc=$?
  if [ -s "$1.stop" ]; then t='{}'; elif [ -n "$(testlogs "$1")" ]; then t=$(testfails "$1.test" "$rc" | jq -ce objects) || t='{}'; fi
  local own=false; ! testlogs "$1" | grep -qvxF "$1.testlog/files" || own=true # a log of the runner's own, beside filecmd()'s
  jq -c --slurpfile t <(printf '%s' "$t") --argjson rc "$rc" --argjson own "$own" '$t[0] as $t | def of($x): . == $x.file or ($x.case != "" and IN($x.files[]?; .));
    map(. as $c | . + {verdict: (if $t == null then (if $rc == 0 then "pass" else "fail" end)
    elif any($t.files[]?; (.file | of($c)) and ($c.case == "" or ($own | not) or any(.cases[]?; .name == $c.case))) or $t.timeout.file? == $c.file then "fail"
    elif (($c.case == "" or ($own | not)) and any($t.passed[]?; . == $c.file)) or any(($t.okcases // []) + ($t.passcases // []) | .[]; (.file | of($c)) and any(.cases[]?; . == $c.case)) then "pass"
    else "none" end)})' <<<"$2"
}
# A case that fails on main (verdicts()) goes to the fix card of main's commit, a card with no GitHub issue (issue 0;
# the owner, 2026-11-15: 13 issues filed in 9 hours, three by one landing): one card per broken main commit, holding
# every case that fails there. $MAINRED keeps {reds: [{sha, cases: [{case, file, by, files, last}], card}]}: by, the
# card that found the case; files, the case's files; last, the last commit that changed them ("%h %s"); card, the fix
# card, null until the loop picks it (redpick()). One writer at a time (a lock of its own). A case found failing on a
# commit that has an entry is added to it, while its card runs too (its brief and commit are made from the entry as
# they are made: redissue()); one an open fix card of an earlier commit holds (redopen()) starts nothing; else the
# commit gets an entry of its own, which the loop picks ahead of the queue. When the case's file is one file and the
# landing that broke it is known (given, as the push's run finds it: pushtests(), lib/push.sh; else brokeby()), the case's entry keeps it (landing: {sha, card, issue}), the brief names
# it, and the entry keeps the links its fix card commits (links: testlinks()). A case is the one an entry holds when
# their names are the same, or when the entry's name is of a runner of the case's file (`<runner>: <case>`, its files
# holding <its file>): an entry made when the engine's runner named its case files' cases as its own (before issue 214)
# is the case its case file names now.
MAINRED=${STATE%/*}/mainred.json
mainred() { # <card> <case> <its file> <main's commit> [<the landing that broke it: "<sha> <card> <issue>">]
  local lock rec c t k re f fs tf by s lc li cmd='' same='def same($c; $f; $k): .case == $c or ($k != "" and (.case | endswith(": " + $k)) and any(.files[]?; . == $f));'
  [ -n "$4" ] || return 1
  # The test command itself (what testfails() names a run that wrote no log) is no case: it names no test to fix.
  ! { packget test.command cmd 2>/dev/null && [ "$2" = "$cmd" ]; } \
    || { echo "conveyor: main is red: the test command itself is no case, so it goes to no fix card" >&2; return 1; }
  # Nor is a document (.md, .txt, .rst; #367): no test file (testpaths()), so no fix card could make it pass.
  [[ ! $3 =~ \.([Mm][Dd]|[Tt][Xx][Tt]|[Rr][Ss][Tt])$ ]] || { echo "conveyor: main is red: $3 is no test file, so it goes to no fix card" >&2; return 1; }
  k=${2#"$3: "}; [ "$k" != "$2" ] || k=''
  { exec {lock}>>"$MAINRED.lock"; } 2>/dev/null || { echo "conveyor: the main-is-red record could not be locked; $2 goes to no fix card" >&2; return 1; }
  flock "$lock" || { exec {lock}>&-; echo "conveyor: the main-is-red record could not be locked; $2 goes to no fix card" >&2; return 1; }
  rec=$(jq -ce '.reds | arrays' "$MAINRED" 2>/dev/null) || rec='[]'
  if ! jq -e --arg s "$4" 'any(.[]; .sha == $s)' <<<"$rec" >/dev/null; then
    while read -r c; do
      redopen "$c" || continue
      exec {lock}>&-; return 0
    done < <(jq -r --arg c "$2" --arg f "$3" --arg k "$k" "$same"'.[] | select(any(.cases[]; same($c; $f; $k))) | .card // ""' <<<"$rec")
  elif jq -e --arg s "$4" --arg c "$2" --arg f "$3" --arg k "$k" "$same"'any(.[]; .sha == $s and any(.cases[]; same($c; $f; $k)))' <<<"$rec" >/dev/null; then
    exec {lock}>&-; return 0
  fi
  # The case's file: a runner names its cases' failures as its own, so the test files at main's commit that define the
  # case (`t_<case>()`, `<case>()` or the name quoted), the named file alone when it is one of them; else the named
  # file (a failure naming no case, or one no test file defines).
  # The test files are those at that commit: its *.test.* files, by git's own glob, so a list of test files that fails
  # or is empty still searches them (#1066: the runner's case was not found in its case file), and those
  # testtracked() (lib/issues.sh) lists, the pack's tests.patterns, taken as paths, not globs.
  fs=()
  if [ -n "$k" ]; then
    re=$(sed 's/[][\\.*^$+?(){}|/]/\\&/g' <<<"$k")
    tf=(); mapfile -d '' -t tf < <(testtracked -z . "$4" 2>/dev/null)
    mapfile -t fs < <(git grep -lE -e "(^|[^[:alnum:]_])(t_)?${re}\\(\\)|['\"]${re}['\"]" "$4" -- '*.test.*' "${tf[@]/#/:(literal)}" 2>/dev/null | sed "s/^$4://")
    for f in "${fs[@]}"; do [ "$f" != "$3" ] || { fs=("$3"); break; }; done
  fi
  [ ${#fs[@]} -gt 0 ] || [ -z "$3" ] || fs=("$3")
  t=''; [ ${#fs[@]} = 0 ] || t=$(git log -1 --format='%h %s' "$4" -- "${fs[@]}" 2>/dev/null)
  by=null
  if [ -n "${5:-}" ]; then read -r s lc li <<<"$5"; by=$(landingof "$s" "$lc" "$li" "${fs[0]:-$3}" | jq -ce objects 2>/dev/null) || by=null
  elif [ ${#fs[@]} = 1 ]; then by=$(brokeby "${fs[0]}" "$4" "$3" "$k" | jq -ce objects 2>/dev/null) || by=null; fi
  jq -c --arg s "$4" --arg c "$2" --arg f "$3" --arg by "$1" --arg t "$t" --argjson b "$by" --args '({case: $c, file: $f, by: $by, files: $ARGS.positional, last: $t}
      + if $b == null then {} else {landing: ($b | {sha, card, issue}), links: $b.links} end) as $x
    | {reds: (if any(.[]; .sha == $s) then map(if .sha == $s then .cases += [$x] else . end) else . + [{sha: $s, cases: [$x], card: null}] end | .[-100:])}' \
    "${fs[@]}" <<<"$rec" > "$MAINRED.new" && mv -f "$MAINRED.new" "$MAINRED" \
    || { exec {lock}>&-; echo "conveyor: main is red: $2: the main-is-red record could not be written" >&2; return 1; }
  exec {lock}>&-
}
# The landing that broke a test file on main without its card running it (issue 598; mainred()): of main's commits
# up to <main's commit>, newest first, back to the last landing whose card's test step ran the file (its test lines
# name it in why or times, or say the whole engine suite ran, for an engine case file, or its ranCases name <case>
# under the file its run named it under: a run of only some cases of the file, issue 604) and so passed it, the first
# landing after that one. Prints {sha, card, issue, links: {<each file that landing changed>: [<test file>]}}; fails
# when no landing ran the file in the last TESTLINK_DEPTH commits (when it last passed is not known) or none is after it.
TESTLINK_DEPTH=500
brokeby() { # <test file> <main's commit> [<the file its run named the case under> <case>]
  local l s by='' ran='' card iss rn
  # The runners the test file names (a case file runs itself through its runner): a run before issue 214 named the
  # cases it ran of the engine's case files under their runner, conveyor/conveyor.test.sh.
  rn=$(git show "$2:$1" 2>/dev/null | grep -oE '[A-Za-z0-9_.-]+\.test\.[A-Za-z0-9]+' | jq -cRn '[inputs] | unique') || rn='[]'
  l=$(stdb ask lines cards 2>/dev/null | jq -rs --arg f "$1" --arg r "${3:-}" --arg c "${4:-}" --argjson rn "${rn:-[]}" '(map(select(.step == "test")) | group_by(.card)
      | map({key: .[0].card, value: any(.[]; (.why // {} | has($f)) or (.times // {} | has($f))
        or (.wholeSuite == true and ($f | startswith("conveyor/tests/")))
        or ($c != "" and any(.ranCases // {} | objects | to_entries[] | select(.key == $r or IN(.key | split("/")[-1]; $rn[])) | .value | arrays | .[]; . == $c)))}) | from_entries) as $ran
    | .[] | select(.step == "landed" and (.sha | type) == "string" and .sha != "") | "\(.sha) \(.card) \(.issue) \($ran[.card] // false)"' 2>/dev/null) || return 1
  while read -r s; do
    s=$(grep -m 1 "^$s " <<<"$l") || continue
    if [ "${s##* }" = true ]; then ran=1; break; fi
    by=$s
  done < <(git rev-list -n "$TESTLINK_DEPTH" "$2" 2>/dev/null)
  [ -n "$ran" ] && [ -n "$by" ] || return 1
  read -r s card iss _ <<<"$by"
  landingof "$s" "$card" "$iss" "$1"
}
# The landing <sha> of <card> as mainred() keeps it (brokeby(), pushtests() in lib/push.sh): {sha, card, issue,
# links: {<each file it changed but the test file>: [<test file>]}}.
landingof() { # <sha> <card> <issue> <test file>
  git diff-tree --no-commit-id --name-only --no-renames -r -z --root "$1" 2>/dev/null | tr '\0' '\n' \
    | jq -cRn --arg s "$1" --arg c "$2" --arg n "$3" --arg f "$4" '{sha: $s, card: $c, issue: ($n | tonumber? // $n),
      links: ([inputs | select(. != "" and . != $f) | {key: ., value: [$f]}] | from_entries)}'
}
# A main-red fix card (card()) stages the links its entry's cases found (mainred(): links) into
# .conveyor/test-links.json, {"<changed file>": ["<test file>", ...]}, beside the links already there, so they land
# with its fix and every later card's test selection (.conveyor/test-changed.sh) reads them.
testlinks() { # <card> <worktree>
  local new f=$2/.conveyor/test-links.json old
  new=$(jq -c --arg c "$1" 'reduce (.reds[]? | select(.card == $c) | .cases[] | .links // {} | to_entries[]) as $e ({}; .[$e.key] += $e.value)' "$MAINRED" 2>/dev/null) || return 0
  [ "$new" != '{}' ] || return 0
  old=$(jq -ce objects "$f" 2>/dev/null) || old='{}'
  mkdir -p "${f%/*}" && jq -n --argjson a "$old" --argjson b "$new" 'reduce ($b | to_entries[]) as $e ($a; .[$e.key] = ((.[$e.key] // []) + $e.value | unique))' > "$f.new" \
    && mv -f "$f.new" "$f" && git -C "$2" add -- .conveyor/test-links.json
}
# Whether the staged change of main-red fix card <card>'s worktree is only the links testlinks() stages (issue 323):
# its session made no change of its own. The links are staged again from main's copy of the file and must come out
# the same; when they do not, the staged file is put back as it was. The session wrote the worktree: a .conveyor that
# is a symlink is not taken, and the file and testlinks()'s .new are unlinked before each write, so no write follows a
# symlink or hard link the session left there to a file outside the worktree.
linksonly() { # <card> <worktree>
  local f=.conveyor/test-links.json b
  [ "$(git -C "$2" diff --cached --name-only --no-renames HEAD 2>/dev/null)" = "$f" ] && [ ! -L "$2/.conveyor" ] && [ -d "$2/.conveyor" ] \
    && b=$(git -C "$2" rev-parse -q --verify ":$f") && rm -f "$2/$f" "$2/$f.new" || return 1
  { git -C "$2" show "HEAD:$f" > "$2/$f" 2>/dev/null || rm -f "$2/$f"; } && git -C "$2" add -A -- "$f" && testlinks "$1" "$2" \
    && [ "$(git -C "$2" rev-parse -q --verify ":$f")" = "$b" ] && return 0
  rm -f "$2/$f" "$2/$f.new"; git -C "$2" cat-file blob "$b" > "$2/$f" && git -C "$2" add -- "$f"
  return 1
}
# Whether a main-red fix card is open: not picked yet ("") or given back by `retry` (no line of it in the card
# records), on the belt or blocked; not when it landed or closed. Records that cannot be read count as open.
redopen() { # <card id, or "">
  [ -n "$1" ] || return 0
  stdb ask card "$1" 2>/dev/null | jq -se 'any(.step | IN("landed", "closed")) | not' >/dev/null
}
# Under the lock (pick()), ahead of the queue: the fix card of the oldest red main commit whose card is not picked yet
# or was given back by `retry` (mainred()). Its picked line is titled "Main is red: <cases>" and names main's commit
# (mainRed), and, when it takes the slot beyond the project's cap (BEYOND, run(): redfix()), says why (beyond); the
# record names the card. Prints "<card> 0 false", `wait` when the machine holds it back, nothing when
# no commit waits for a card.
redpick() {
  local lock rec s c l card=''
  [ -s "$MAINRED" ] || return 0
  { exec {lock}>>"$MAINRED.lock"; } 2>/dev/null || { echo "conveyor: the main-is-red record could not be locked; its fix card waits" >&2; return 1; }
  flock "$lock" || { exec {lock}>&-; echo "conveyor: the main-is-red record could not be locked; its fix card waits" >&2; return 1; }
  rec=$(jq -ce '.reds | arrays' "$MAINRED" 2>/dev/null) || rec='[]'
  # A document's case (.md, .txt, .rst), which an engine before #367 took for main red, goes, with an entry it leaves
  # with no case: no fix card could make it pass, and the cards that wait on it (mainwait()) run again.
  s=$(jq -c 'map(.cases |= map(select(.file // "" | test("\\.(md|txt|rst)$"; "i") | not)) | select(.cases != []))' <<<"$rec") || s=$rec
  # The record goes to jq on its input, not as an argument: Linux refuses one over 128 KiB (issue 369).
  [ "$s" = "$rec" ] || { jq -c '{reds: .}' <<<"$s" > "$MAINRED.new" && mv -f "$MAINRED.new" "$MAINRED" && rec=$s; } \
    || { exec {lock}>&-; echo "conveyor: the main-is-red record could not be written; its fix card waits" >&2; return 1; }
  while IFS=$'\t' read -r s c; do
    if [ -n "$c" ]; then l=$(stdb ask card "$c") && [ -z "$l" ] || continue; fi
    # The machine's yes (room()), as for any card: held back, the loop asks again at its next turn.
    room 0 >/dev/null || { exec {lock}>&-; echo wait; return 0; }
    # A card id is its second, its project and its issue: a card of issue 0 picked in the same second waits for the next.
    while card="c$(date -u +%Y%m%dT%H%M%S)-$CTAG-0"; [ -n "$(stdb ask card "$card")" ] || stdb ask lines retried | grep -F "\"card\":\"$card\"" >/dev/null; do sleep 1; done
    jq -c --arg s "$s" --arg c "$card" '{reds: map(if .sha == $s then .card = $c else . end)}' <<<"$rec" > "$MAINRED.new" && mv -f "$MAINRED.new" "$MAINRED" \
      && l=$(line "$card" 0 picked ok "$(jq -c --arg s "$s" --arg b "${BEYOND:-}" '.[] | select(.sha == $s) | {title: ("Main is red: " + ([.cases[].case] | join(", ")))[0:200], mainRed: $s}
        + if $b == "" then {} else {beyond: $b} end' <<<"$rec")") \
      && append "$l" || { exec {lock}>&-; echo "conveyor: the fix card of main's commit $s could not be picked" >&2; return 1; }
    exec {lock}>&-; echo "$card 0 false"; return 0
  done < <(jq -r '.[] | [.sha, .card // ""] | @tsv' <<<"$rec")
  exec {lock}>&-
}
# What stands in for the issue of a main-red fix card (card()), from its entry as it is now (mainred()): the title
# "Main is red: <cases>", and a body naming main's commit, each case with the last commit that changed its files (and
# the landing that broke it, when known), and what to do. Labelled as the P0 issue it stands in for was (labels.type and the first priority), so it is held to the bug-card check.
redissue() { # <card>
  jq -ce --arg c "$1" --arg t "$TYPE" --argjson p "$PRIOS" '.reds[]? | select(.card == $c)
    | {number: 0, title: ("Main is red: " + ([.cases[].case] | join(", ")))[0:200], milestone: null, labels: [{name: $t}, {name: $p[0]}],
       body: ("These test cases fail on main at \(.sha[0:12]). A card'"'"'s test step failed each on its run and its run again, and it failed again when run on main, without the card'"'"'s change. A card that fails only cases that fail on main waits (no fix session, no block) until main changes, then tests again.\n\n"
         + ([.cases[] | "- `\(.case)`, found by card \(.by). The last commit that changed \(if .files == [] then "its file" else .files | join(", ") end): \(if .last == "" then "none found" else .last end)."
           + if .landing == null then "" else " The landing that broke it: \(.landing.sha[0:12]) (card \(.landing.card), #\(.landing.issue)), whose test step did not run \(.files[0]). This card links \(.files[0]) to the files that landing changed, in .conveyor/test-links.json, so later cards that change them run it: \(.links | keys | join(", "))." end] | join("\n"))
         + "\n\nMake the cases pass on main.\n\nDone when: the cases pass on main.")}' "$MAINRED" 2>/dev/null
}
# The titles of the main-red fix cards as their entries are now ({<card>: "Main is red: <cases>"}): the Board shows a
# case added while the card runs (mainred()), which its picked line's title does not name.
redtitles() {
  jq -ce '[.reds[]? | select(.card) | {key: .card, value: ("Main is red: " + ([.cases[].case] | join(", ")))[0:200]}] | from_entries' "$MAINRED" 2>/dev/null || echo '{}'
}
# Whether the main-red record (mainred()) holds main red for any of <case>...: an entry of any commit lists one, and
# its fix card is not picked yet or is still open (redopen()), as mainred() files a case (a case failing at a later
# commit goes to the open fix card of an earlier one). An entry whose fix card landed, or closed as already done
# (bugproof.sh bugproof(), nochange()), holds it no more.
redlisted() { # <case>...
  local card
  while read -r card; do redopen "$card" < /dev/null && return 0; done \
    < <(jq -r --args '.reds[]? | select(any(.cases[]?; .case | IN($ARGS.positional[]))) | .card // ""' "$@" < "$MAINRED" 2>/dev/null)
  return 1
}
# A card whose every failure is main's (verdicts()) waits in its test step until main is at another commit than
# <main's commit>, its live record saying so and brought up to date as it waits (so `health` does not call it stuck).
# It only sleeps there: <worktree>.idle stands meanwhile, so the loop does not count it against the builder cap (idle()).
# It ends too once the main-red record ($MAINRED) holds main red for none of <case>... (redlisted(); issue 358: the
# owner or the Foreman removed a wrong entry, or its fix card closed as already done), when it held one as the wait
# began; a wait on cases the record did not hold (mainred() could not write them) ends only as main moves.
mainwait() { # <worktree> <main's commit> <case>...
  local at c listed=''; at=$(date -u +%FT%TZ); c=$(jq -rn '$ARGS.positional | join(", ")' --args "${@:3}")
  ! redlisted "${@:3}" || listed=1
  while [ "$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)" = "$2" ] && { [ -z "$listed" ] || redlisted "${@:3}"; }; do
    jq -cn --arg at "$at" --arg c "$c" --arg s "${2:0:12}" '{step: "test", at: $at, last: (now | todate), turns: 0, files: {run: 0, of: null}, tests: null,
      action: "waiting for main to change: \($c) fail on main at \($s) too"}' > "$1.live.tmp" 2>/dev/null && mv -f "$1.live.tmp" "$1.live"
    : > "$1.idle"; sleep "$LIVE"
  done
  rm -f "$1.live" "$1.idle"
}
