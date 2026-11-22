#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the track of each card in the snapshot.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: the track of a card on the belt names the wrong step, hides a fix round the card did not need instead
# of showing it skipped, loses a failed test run or a rebuild after a landing conflict, or differs in shape from card
# to card; a review recorded before findings were counted shows zeros.
# Bugs: the track is 17 small chips, and a card being pushed has none of them marked; Push does not follow
# Land; a step skipped (Fix after a GO, Build of a card landed from a kept patch) reads as to come; a time is estimated
# from past cards; a card resumed from a kept patch does not count the time of the card whose work it resumes. The 17
# steps are still the detail a card opens to.
t_track() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F); local made; made=$(date -u -d "$d 1 hour ago" +%FT%TZ)
  card() { # <issue> <step[:result[:extra json]]>...: its lines a minute apart; b, r, f, t, F, l and x are the starts of build, review, fix, test, the filing of follow-ups, land and rebase, and - a minute with no line
    local n=$1 m=0 a step res x; shift; for a; do IFS=: read -r step res x <<<"$a"
      case $step in -) m=$((m + 1)); continue ;; b) step=start; x='{"of":"build"}' ;; r) step=start; x='{"of":"review"}' ;; f) step=start; x='{"of":"fix"}' ;; t) step=start; x='{"of":"test"}' ;;
        l) step=start; x='{"of":"land"}' ;; F) step=start; x='{"of":"file"}' ;; x) step=start; x='{"of":"rebase"}' ;; picked) x="{\"title\":\"T$n\",\"created\":\"$made\"}" ;; esac
      printf '%s\t%sT00:%02d:00Z\t%s\t%s\n' "$step" "$d" "$m" "${res:-ok}" "${x:-{\}}"; m=$((m + 1))
    done | jq -cR --arg c "c$n" --argjson i "$n" 'split("\t") as [$s, $t, $r, $x]
      | {card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * ($x | fromjson)' >> "$S/cards.jsonl"
  }
  K='{"counts":{"P0":0,"P1":1,"P2":2,"P3":0}}'; Z='{"counts":{"P0":0,"P1":0,"P2":0,"P3":0}}'; pre="picked worktree deps brief b build r"
  for n in 1 2 3; do card $n $pre "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abc","product":false}' pushed issue; done
  card 4 $pre "review:NO-GO:$K" f fix r "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abc","product":false}' pushed issue
  card 20 picked
  card 21 picked worktree deps
  card 22 picked worktree deps brief b
  card 23 $pre "review:NO-GO:$K" f
  card 24 $pre "review:GO:$Z" t
  card 25 $pre "review:GO:$Z" t test:fail f
  card 26 $pre "review:GO:$Z" t test:pass l x
  card 27 $pre "review:NO-GO:$K" f fix r review:NO-GO f fix r "review:NO-GO:$K" t test:pass F 'filed:ok:{"followups":[100101,100102]}' l
  card 28 $pre "review:GO:$Z" t test:pass l x rebase r
  # The follow-ups are being filed (GitHub is asked once for each): that is the step in progress, not the landing, and
  # the landing before it in the track is still to come, not skipped. After a rebuild it is the same step. Of the six
  # steps the filing is Land's, which it comes before, so the track never steps back from Push to Land.
  card 29 $pre "review:NO-GO:$K" f fix r review:NO-GO f fix r "review:NO-GO:$K" t test:pass F
  card 30 $pre "review:GO:$Z" t test:pass l x rebase r "review:NO-GO:$K" t test:pass F
  # Bug: the rebuild had no step of its own. A landing that has only begun may yet meet a conflict: the
  # rebuild is still to come there, and skipped only on a card that landed without one.
  card 31 $pre "review:GO:$Z" t test:pass l
  # Tests that fail twice, each time fixed and reviewed again: "Every step" lists each run, fix and review with its own
  # seconds, not summed into one slot.
  # A failed run keeps its reason, which the Board shows on the red bar.
  card 32 $pre "review:GO:$Z" t 'test:fail:{"reason":"exit 124: timeout"}' f fix r "review:GO:$Z" t test:fail f fix r "review:GO:$Z" t test:pass l
  # A review that failed keeps its reason too: without it the red bar repeats its name.
  card 33 $pre 'review:fail:{"reason":"review process exited 124"}' r
  # A fix keeps the reason its line names (what started it), which the Board labels it by; one with none has none.
  card 34 picked worktree deps brief b build f 'fix:ok:{"reason":"the Done-when check failed: D1 not met"}' r "review:NO-GO:$K" f fix r
  # Issue 650: a fix the Done-when check on the build's reply started is Build's, not a Fix round before the first
  # review: running (36), then done (35); a fix after a NO-GO review is still Fix (37).
  W='build:ok:{"doneWhen":{"items":1,"met":0,"failed":["D1"]}}'
  card 35 picked worktree deps brief b "$W" f 'fix:ok:{"reason":"the Done-when check failed: D1"}' r
  card 36 picked worktree deps brief b "$W" f
  card 37 $pre "review:NO-GO:$K" f fix r
  # Issue 261: a lint fix is named by the gate on the lint line before it (lint.gate): the review gate's, after the
  # build, is Build's, running (38), then done (39); the landing gate's is a Fix round, running (48).
  lintl() { printf 'lint:%s:{"lint":{"commands":[],"asInstalled":false,"gate":"%s"},"reason":"%s"}' "$@"; }
  card 38 picked worktree deps brief b build "$(lintl findings review 'lint command 1 (x): findings, 1 of this change, 2 s')" f
  card 39 picked worktree deps brief b build "$(lintl findings review '')" f 'fix:ok:{"reason":"lint: 1 finding(s) of the change"}' \
    "$(lintl pass review 'lint command 1 (x): skipped: missing shellcheck, 0 s')" r
  card 48 $pre "review:GO:$Z" "$(lintl findings land '')" f
  # The review gate's lint fix after a fix round is on Fix (49), after a rebuild on Land (50).
  card 49 $pre "review:NO-GO:$K" f fix "$(lintl findings review '')" f
  card 50 $pre "review:GO:$Z" t test:pass l x rebase "$(lintl findings review '')" f
  # Issue 1366: a lint line's commands reach the Board's step record, so it can show a row for each (51); a line with none (39) has none.
  card 51 picked worktree deps brief b build 'lint:findings:{"lint":{"commands":[{"n":1,"run":"bash x.sh {files}","result":"findings","sec":2,"findings":1,"reported":[{"file":"a.sh","line":3,"text":"bad"}]}],"asInstalled":false,"gate":"review"},"reason":"lint command 1 (bash x.sh {files}): findings, 1 of this change, 2 s"}' f
  # A fifth lands, after a fix round that took 3 minutes.
  card 5 $pre "review:NO-GO:$K" f - - fix r "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abd","product":false}'
  # Five cards land after a rebuild (two minutes each): no time of any step is estimated from them.
  for n in 6 7 8 9 10; do card $n $pre "review:GO:$Z" t test:pass l x - rebase r - - "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abe","product":false}'; done
  # Bug: a build, fix, rebuild or landing that fails takes the card off the belt, and the blocked list had no
  # track: no view showed the step that failed or how long it ran. Each blocked card carries its track, the step it
  # stopped in failed with its seconds; one waiting for the yes of the owner failed nothing.
  card 40 picked worktree deps brief b - - 'blocked:blocked:{"reason":"build: session failed (exit 124)"}'
  card 41 $pre "review:NO-GO:$K" f - 'blocked:blocked:{"reason":"fix: session failed"}'
  card 42 $pre "review:GO:$Z" t test:pass l - - - 'blocked:blocked:{"reason":"main moved during the landing; nothing was landed"}'
  card 43 $pre "review:GO:$Z" t test:pass l x - 'blocked:blocked:{"reason":"rebase: session failed"}'
  card 44 picked - "blocked:blocked:{\"reason\":\"worktree: the engine could not link the dependencies of the main checkout: no\"}"
  card 45 $pre "review:GO:$Z" "blocked:blocked:{\"reason\":\"visible to customers or staff: needs Dana's yes: a new line\"}"
  card 46 $pre - 'blocked:blocked:{"reason":"review 1: review failed (exit 124)"}'
  card 47 picked worktree deps 'blocked:blocked:{"reason":"brief: gh issue view failed"}'
  # A card resumed from the kept patch of a blocked card counts that card's time, shows its first start and gives that card's steps (earlier, #545):
  # card 60 ran 7 minutes and was blocked; card 61 took its patch up and landed 11 minutes after its own pick-up.
  card 60 picked worktree deps brief b - - 'blocked:blocked:{"reason":"build: session failed (exit 1)"}'
  card 61 picked 'worktree:ok:{"reason":"resumed from the kept patch of card c60: one session, then review"}' deps brief b build r "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abg","product":false}'
  card 62 picked worktree deps brief b build r
  # #1079: a push that went on over a pre-push hook that failed naming a test file that passed alone.
  card 63 $pre "review:GO:$Z" t test:pass l 'landed:ok:{"sha":"abh","product":false}' 'pushed:ok:{"flaky":{"files":["lib/a.test.sh"],"issues":[5]}}' issue
  # One snapshot of the cards above, and one jq a card: one after each group and one a line took the case 6 s more.
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.belt[] | select(.card == "c34") | .track.records[6:9] | map([.name, .reason])' <<<"$out")" \
    = '[["fix 1","the Done-when check failed: D1 not met"],["review 1 (NO-GO)",null],["fix 2",null]]' ] \
    || fail "a fix lost the reason that started it: $(jq -c '.belt[] | select(.card == "c34") | .track.records' <<<"$out")"
  [ "$(jq -c '.belt[] | select(.card == "c33") | .track.records[6] | [.name, .state, .why]' <<<"$out")" = '["review 1 (fail)","failed","review process exited 124"]' ] \
    || fail "a failed review lost its reason: $(jq -c '.belt[] | select(.card == "c33") | .track.records' <<<"$out")"
  [ "$(jq -c '.belt[] | select(.card == "c32") | .track.records[6:] | map([.name, .state, .sec, .why])' <<<"$out")" \
    = '[["review 1 (GO)","done",60,null],["tests failed","failed",60,"exit 124: timeout"],["fix 1","done",60,null],["review 2 (GO)","done",60,null],["tests failed","failed",60,null],["fix 2","done",60,null],["review 3 (GO)","done",60,null],["tests passed","done",60,null],["landing","now",null,null]]' ] \
    || fail "every step of a card whose tests failed twice: $(jq -c '.belt[] | select(.card == "c32") | .track.records' <<<"$out")"
  b() { jq -c --arg c "c$1" ".belt[] | select(.card == \$c) | $2" <<<"$out"; }
  marks() { b "$1" '.track | [.detailAt, .label, (.detail | map({done: "+", now: ">", skipped: "-", failed: "!", todo: "."}[.state]) | join(""))]'; }
  # The six steps Build, Review, Fix, Test, Land, Push: the step in progress, each step's mark, and the rounds of Review and Fix.
  six() { b "$1" '.track | [.at, (.steps | map({done: "+", now: ">", skipped: "-", failed: "!", todo: "."}[.state]) | join("")), .steps[1].n, .steps[2].n]'; }
  [ "$(jq -c '[.belt[].track.detail | map(.name)] | unique' <<<"$out")" = '[["queued","picked","worktree ready","dependencies linked","brief written","building","review 1","fix 1","review 2","fix 2","review 3","tests","rebuild","landing","pushed","issue closed","follow-ups filed"]]' ] \
    || fail "the track is not the same 17 steps on every card: $(jq -c '[.belt[].track.detail | map(.name)] | unique' <<<"$out")"
  while read -r n want; do [ "$(marks "$n")" = "$want" ] || fail "track of card $n: $(marks "$n"), not $want"; done <<'EOF'
20 [2,"making the worktree","++>.............."]
21 [4,"writing the brief","++++>............"]
22 [5,"building","+++++>..........."]
23 [7,"fix after review 1","+++++++>........."]
24 [11,"tests","+++++++---->....."]
25 [11,"fix after failed tests","+++++++----!....."]
26 [12,"rebuilding after a conflict","+++++++----+>...."]
27 [13,"landing","++++++++++++.>..+"]
28 [13,"review 2 after the rebuild","+++++++----++>..."]
29 [16,"filing follow-ups","++++++++++++....>"]
30 [16,"filing follow-ups","+++++++----++...>"]
31 [13,"landing","+++++++----+.>..."]
EOF
  [ "$(jq -c '[.belt[].track.steps | map(.name)] | unique' <<<"$out")" = '[["Build","Review","Fix","Test","Land","Push"]]' ] \
    || fail "the track is not the six steps in order: $(jq -c '[.belt[].track.steps | map(.name)] | unique' <<<"$out")"
  while read -r n want; do [ "$(six "$n")" = "$want" ] || fail "six steps of card $n: $(six "$n"), not $want"; done <<'EOF'
20 [0,">.....",0,0]
21 [0,">.....",0,0]
22 [0,">.....",0,0]
23 [2,"++>...",1,1]
24 [3,"++->..",1,0]
25 [2,"++>...",1,1]
26 [4,"++-+>.",1,0]
27 [4,"++++>.",3,2]
28 [1,"+>-+..",2,0]
29 [4,"++++>.",3,2]
30 [4,"++-+>.",2,0]
31 [4,"++-+>.",1,0]
34 [1,"+>+...",2,1]
35 [1,"+>....",1,0]
36 [0,">.....",0,0]
37 [1,"+>+...",2,1]
38 [0,">.....",0,0]
39 [1,"+>....",1,0]
48 [2,"++>...",1,1]
49 [2,"++>...",1,1]
50 [4,"++-+>.",1,0]
EOF
  # Bugs (#261): the review gate's lint fix was a Fix round before the first review, and the landing gate's had no
  # note, so neither the Board nor /units could say "Build · lint fix" or "Fix N: lint findings"; the review gate's
  # after a fix round or a rebuild had no note at all.
  [ "$(jq -c '[.belt[] | select(.card | IN("c38", "c39", "c48", "c49", "c50")) | [.card, .track.steps[0].lintFix, .track.steps[2].lintFix, .track.steps[4].lintFix]] | sort' <<<"$out")" \
    = '[["c38","now",null,null],["c39","done",null,null],["c48",null,"now",null],["c49",null,"now",null],["c50",null,null,"now"]]' ] \
    || fail "the lint fix on Build, Fix and Land: $(jq -c '[.belt[] | select(.card | IN("c38", "c39", "c48", "c49", "c50")) | [.card, .track.steps]]' <<<"$out")"
  # Bug (#261): a lint line showed in the card's history with none of its commands' results.
  # Bug (#1110): the lint lines did not name their gate, so the Board numbered a finished lint fix by its fix line
  # ("Fix 3: lint findings"), not as the six steps did while it ran ("Fix 1: lint findings").
  [ "$(b 39 '[.track.records[] | select(.name == "lint") | [.why, .gate]]')" = '[[null,"review"],["lint command 1 (x): skipped: missing shellcheck, 0 s","review"]]' ] \
    || fail "the lint lines' results in the history: $(b 39 .track.records)"
  # Bug (#1366): the Board got only a lint line's one-sentence reason, so it could show nothing but that sentence.
  [ "$(b 51 '[.track.records[] | select(.name == "lint") | .lint]')" = '[[{"n":1,"run":"bash x.sh {files}","result":"findings","sec":2,"findings":1,"reported":[{"file":"a.sh","line":3,"text":"bad"}]}]]' ] \
    || fail "the lint line's commands in the history: $(b 51 .track.records)"
  [ "$(b 39 '[.track.records[] | select(.name == "lint") | .lint]')" = '[null,null]' ] || fail "a lint line with no commands has a lint list: $(b 39 .track.records)"
  # The note /units and the Board draw on Build for a reply-check fix: running, done, and none without one.
  [ "$(jq -c '[.belt[] | select(.card | IN("c34", "c35", "c36", "c37")) | [.card, .track.steps[0].replyFix]] | sort' <<<"$out")" = '[["c34","done"],["c35","done"],["c36","now"],["c37",null]]' ] \
    || fail "the reply-check fix on Build: $(jq -c '[.belt[] | select(.card | IN("c34", "c35", "c36", "c37")) | [.card, .track.steps[0]]]' <<<"$out")"
  # Issue 1118: the Board names a fix in progress the reply check's only from the line before it whose check failed:
  # the build's on 36, none on 37's review findings fix.
  [ "$(jq -c '[.belt[] | select(.card | IN("c36", "c37")) | [.card, [.track.records[] | select(.checkFailed) | .name]]] | sort' <<<"$out")" = '[["c36",["building"]],["c37",[]]]' ] \
    || fail "the records do not mark the line whose Done-when check failed: $(jq -c '[.belt[] | select(.card | IN("c36", "c37")) | .track.records]' <<<"$out")"
  # Build is the set-up and the build, never the hour the issue sat queued; a failed test run is run again after its
  # fix (to come, not failed); a rebuild and the landing it follows are both Land's; the follow-ups filed are named on Push.
  [ "$(b 22 '.track.steps[0].sec')" = 180 ] && [ "$(b 25 '.track.steps[3] | [.state, .sec] | tojson')" = '"[\"todo\",60]"' ] \
    && [ "$(b 26 '.track.steps[4].sec')" = 60 ] && [ "$(b 27 '[.track.steps[5].followups, .track.steps[1].of] | tojson')" = '"[2,3]"' ] \
    || fail "the seconds of the six steps: $(b 22 .track.steps) $(b 25 .track.steps) $(b 26 .track.steps) $(b 27 .track.steps)"
  [ "$(b 27 '[.track.detail[16].n, (.reviews | map([.round, .verdict, .fixed, .counts.P2]))] | tojson')" = '"[2,[[1,\"NO-GO\",true,2],[2,\"NO-GO\",true,null],[3,\"NO-GO\",false,2]]]"' ] \
    || fail "three reviews, one of them recorded with no counts: $(b 27 .reviews)"
  [ "$(b 22 '[.reviews, .track.detail[0].sec, .track.detail[2].sec, .track.since[14:16]] | tojson')" = '"[[],3600,60,\"04\"]"' ] || fail "no review yet, the time queued, a step's seconds or when the step began: $(b 22 .)"
  [ "$(b 25 '.track.detail[11].sec')" = 60 ] || fail "the seconds of a failed test run: $(b 25 .track.detail[11])"
  # The rebuild's seconds are its session's alone; the landing that met the conflict keeps its own.
  [ "$(b 28 '.track.detail[12:14] | map([.name, .state, .sec]) | tojson')" = '"[[\"rebuild\",\"done\",60],[\"landing\",\"now\",60]]"' ] || fail "the seconds of a rebuild, apart from the landing's: $(b 28 '.track.detail[12:14]')"
  [ "$(jq -c '.landed | map(select(.card == "c1" or .card == "c5") | [.card, (.rounds | map(.verdict) | join(" ")), (.track.detail[7:11] + .track.detail[12:13] + .track.detail[14:] | map(.state[0:1]) | join(""))]) | sort | .[]' <<<"$out" | tr '\n' ' ')" \
    = '["c1","GO","sssssdds"] ["c5","NO-GO GO","ddssstts"] ' ] || fail "a landed card's reviews and the end of its track: $(jq -c '.landed | map([.card, .rounds, .track.detail])' <<<"$out")"
  # Landed: Fix skipped after a GO; Push done once the push and the close of the issue are recorded, to come before.
  [ "$(jq -c '.landed | map(select(.card == "c1" or .card == "c5") | [.card, .track.at, (.track.steps | map(.state[0:1]) | join(""))]) | sort' <<<"$out")" = '[["c1",null,"ddsddd"],["c5",null,"dddddt"]]' ] \
    || fail "the six steps of a landed card: $(jq -c '.landed | map([.card, .track.steps])' <<<"$out")"
  # The marks have their seconds too: the follow-ups took a minute to file, the push came a minute after the landing
  # and the issue closed a minute after the push.
  [ "$(b 27 '.track.detail[16] | [.sec, .n] | tojson')" = '"[60,2]"' ] || fail "the seconds of the follow-ups filed: $(b 27 .track.detail[16])"
  [ "$(jq -c '.landed[] | select(.card == "c1") | .track.detail[14:16] | map(.sec)' <<<"$out")" = '[60,60]' ] \
    || fail "the seconds of the push and of the issue closed: $(jq -c '.landed[] | select(.card == "c1") | .track.detail[14:16]' <<<"$out")"
  [ "$(jq -c '.landed[] | select(.card == "c6") | .track.detail[12:14] | map([.state, .sec])' <<<"$out")" = '[["done",120],["done",360]]' ] \
    || fail "a landed card that was rebuilt lost the rebuild's own time: $(jq -c '.landed[] | select(.card == "c6") | .track.detail[12:14]' <<<"$out")"
  # Bug: its landSec counted only the landing that landed, not the minute of the one that met the conflict.
  [ "$(jq -c '.landed[] | select(.card == "c6") | .metrics | [.landSec, .rebuildSec]' <<<"$out")" = '[120,120]' ] \
    || fail "a rebuilt card's landSec lost the landing that met the conflict: $(jq -c '.landed[] | select(.card == "c6") | .metrics' <<<"$out")"
  [ "$(jq -c '.belt | map(select(.issue >= 40 and .issue <= 47)) | length' <<<"$out")" = 0 ] || fail "a blocked card is on the belt"
  # #1079 ask 2. Bug it catches: a push that went on over a flaky hook read as a plain push, so nothing on the Board said
  # its hook failed and the files passed alone ("flaky: passed alone"), and a plain push named them.
  [ "$(jq -c '[.landed[] | select(.card == "c63" or .card == "c1") | [.card, (.track.records[] | select(.name | startswith("pushed")) | .name)]] | sort' <<<"$out")" \
    = '[["c1","pushed"],["c63","pushed (flaky: passed alone: lib/a.test.sh)"]]' ] \
    || fail "the Push step of a push over a flaky hook: $(jq -c '[.landed[] | select(.card == "c63" or .card == "c1") | {card, records: .track.records}]' <<<"$out")"
  nd() { jq -c --arg c "c$1" '.needsYou | .waiting[], .blocked[] | select(.card == $c) | [(.track.detail | map({done: "+", now: ">", skipped: "-", failed: "!", todo: "."}[.state]) | join("")), (.track.detail | map(select(.state == "failed") | [.name, .sec]))]' <<<"$out"; }
  while read -r n want; do [ "$(nd "$n")" = "$want" ] || fail "track of blocked card $n: $(nd "$n"), not $want"; done <<'EOF'
40 ["+++++!...........",[["building",180]]]
41 ["+++++++!.........",[["fix 1",120]]]
42 ["+++++++----+.!...",[["landing",240]]]
43 ["+++++++----+!....",[["rebuild",120]]]
44 ["+++!.............",[["dependencies linked",120]]]
45 ["+++++++..........",[]]
46 ["++++++!..........",[["review 1",120]]]
47 ["++++!............",[["brief written",60]]]
EOF
  nd6() { jq -c --arg c "c$1" '.needsYou | .waiting[], .blocked[] | select(.card == $c) | .track | [.at, (.steps | map({done: "+", now: ">", skipped: "-", failed: "!", todo: "."}[.state]) | join(""))]' <<<"$out"; }
  while read -r n want; do [ "$(nd6 "$n")" = "$want" ] || fail "six steps of blocked card $n: $(nd6 "$n"), not $want"; done <<'EOF'
40 [null,"!....."]
41 [null,"++!..."]
42 [null,"++-+!."]
43 [null,"++-+!."]
44 [null,"!....."]
45 [null,"++...."]
46 [null,"+!...."]
47 [null,"!....."]
EOF
  [ "$(jq -c '.needsYou.blocked[] | select(.card == "c41") | .reviews | map([.round, .verdict, .fixed])' <<<"$out")" = '[[1,"NO-GO",true]]' ] || fail "a blocked card's reviews: $(jq -c '.needsYou.blocked[] | select(.card == "c41") | .reviews' <<<"$out")"
  [ "$(jq -c '.landed[] | select(.card == "c61") | [.start[11:16], .pickedAt[11:16], .priorSec, .totalSec, (.earlier | map([.card, .sec, .reason, .track.steps[0].state]))]' <<<"$out")" = '["00:00","00:00",420,1080,[["c60",420,"build: session failed (exit 1)","failed"]]]' ] \
    && [ "$(jq -c '.belt[] | select(.card == "c62") | [.start, .pickedAt, .priorSec, .totalSec, .earlier] | [.[0] == .[1], .[2], .[3], .[4]]' <<<"$out")" = '[true,0,null,[]]' ] \
    || fail "start and overall time: $(jq -c '[.landed[], .belt[]] | map(select(.card == "c61" or .card == "c62") | {card, start, pickedAt, priorSec, totalSec, earlier})' <<<"$out")"
  # Bug (#874): a card started from a kept patch did not say so on the Board or in /units: its start line's reason is
  # the track's kept and the why of its "worktree ready" step; a card that started on main alone has neither.
  [ "$(jq -c '[.landed[], .belt[]] | map(select(.card == "c61" or .card == "c62") | [.card, .track.kept, (.track.records[] | select(.name == "worktree ready") | .why)])' <<<"$out")" \
    = '[["c61","resumed from the kept patch of card c60: one session, then review","resumed from the kept patch of card c60: one session, then review"],["c62",null,null]]' ] \
    || fail "the start line of a card resumed from a kept patch is not in its track: $(jq -c '[.landed[], .belt[]] | map(select(.card == "c61" or .card == "c62") | {card, kept: .track.kept, records: .track.records[0:3]})' <<<"$out")"
}
