#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The limit is the whole file's in a card's test step (lib/fileeach.sh), and each of its 21 cases waits there for a test
# slot of its own. Their own times added up to 154 s (119 s of CPU) on a busy machine, so on a busy step the waits for
# slots took the file past 120 s (times the load factor: 126 s once) with no case failed: all 3 flaky sightings were
# that time-out (#1826).
# Engine cases: a split before the build whose card stopped after it filed slices and before its split line was
# recorded (splitplan(), splitmade(), splitend(), lib/slices.sh). What must stay true: each slice of the split is filed
# once; while the rule is On and the issue's text is the plan's, none that the earlier card filed is closed or taken out
# of the queue (the loop can have picked it already), and the next card of the issue files only the slices that are
# missing (a slice kept waits on one filed in place of a slice it depends on) and records the split; with the rule
# Shadow or Off, or the issue edited, the next card files none of the plan's slices, gives the issue back their place
# in the order, withdraws those filed, and checks the issue anew (Off: builds it whole). Slices that cannot be read, or
# one that may stay in the queue, block the card: the issue is never built whole beside them. The earlier card is
# stopped inside its own splitcheck() at the point named in each case, as a restart would stop it, and the next loop
# takes up its gone process (revive(), lib/run.sh): its `retry` moves the card's lines, the plan's too, to the retried
# records before the next card runs. The fixtures (slices, big, SPLIT2, nicards) are those of slices.test.sh and
# testcards.test.sh, editfiled and listbylabel slicesgrownedit.test.sh's: the runner sources every case file into one shell.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The next loop takes up card c6, its process gone, as run() does: revive() blocks it and gives #7 back (retry), and
# the plan c6 left is in the retried records alone. c6 has no worktree line, as card() calls splitcheck() before
# cardopen() writes one: revive() finds it by the pid on its split check's start line. Bugs caught: revive() read the
# pid from a worktree line only, so a card stopped in its split was never taken up; and a splitplan() that read the
# active records only did not see c6's plan after a real restart, so the next card filed its slices again.
restart() {
  fx_in 'revive ""'
  grep -qF 'card c6 had an open record and its process was gone' "$T/$CASE/run.out" || fail "revive did not take up card c6, its process gone (exit $RC): $(cat "$T/$CASE/run.out")"
  [ -z "$(st 'select(.card == "c6") | .step')" ] && [ "$(jq -c 'select(.card == "c6" and .step == "start" and .plan != null) | .issue' "$ST/retried.jsonl")" = 7 ] \
    || fail "c6's plan did not move to the retried records: $(cat "$ST/cards.jsonl") $(cat "$ST/retried.jsonl" 2>&1)"
}
splitline() { st 'select(.step == "split" and .card == "c7-7") | [.split.filed, .split.cards, .split.resumed] | @json'; }
# The card whose process is in $STUB/cardpid is killed once, as gh files an issue while $STUB/filed holds <n>.
killatfile() { # <n>
  # stub: the card's process and the subshells it runs gh in are killed as gh files the issue, as a restart would;
  # only the processes from gh up to the card's are killed, and none when the card's is not among them.
  printf '%s\n' '[ "$(cat "$STUB/filed" 2>/dev/null | wc -l | tr -d " ")" = '"$1"' ] && [ ! -e "$STUB/killed" ] && { touch "$STUB/killed"; c=$(cat "$STUB/cardpid"); p=$PPID; k=()
    while [ "${p:-1}" -gt 1 ] && [ "$p" != "$c" ]; do k+=("$p"); p=$(ps -o ppid= -p "$p" | tr -d " "); done; [ "$p" != "$c" ] || kill -9 "${k[@]}" "$c"; exit 1; } || :' > "$STUB/create-cmd"
}
# Card c6 splits #7 and is killed as gh files its second slice: #100101 is filed and nothing else.
stopfiling() {
  killatfile 1
  fx_in 'echo "$BASHPID" > "$STUB/cardpid"; splitcheck c6 7'
  [ -e "$STUB/killed" ] && [ "$(jq -sc 'map(.number)' "$STUB/filed")" = '[100101]' ] || fail "card c6 was not stopped after its first slice (exit $RC): $(cat "$STUB/filed" 2>/dev/null)"
  restart
}
# Card c6 splits #7 and is killed as it writes its split line, after every slice is filed and placed.
stopline() {
  fx_in 'eval "c6_$(declare -f record)"; record() { [ "$3" != split ] || kill -9 "$BASHPID"; c6_record "$@"; }; splitcheck c6 7'
  [ "$RC" = 137 ] && [ -z "$(st 'select(.step == "split") | .card')" ] || fail "card c6 was not stopped at its split line (exit $RC): $(cat "$T/$CASE/run.out")"
  restart
}

# Card c6 splits #7, pinned first in the pick order, and is killed as it files its second slice. Card c7-7 then checks
# #7. Bug caught: c6 left no split line for the hash check, so c7-7 asked the judge again and filed both slices again,
# and #7 had two open sets of them. c7-7 files only slice 2 (#100102, depending on #100101; slice 1 depends on none),
# closes nothing, puts both slices in #7's place in the order and records the split as c6's, resumed.
t_splitresume() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  loop control order 7 > /dev/null || fail "the order 7 could not be set"
  stopfiling
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ ! -e "$STUB/closed" ] && [ "$(judged)" = 1 ] || fail "splitcheck c7-7 7 asked the judge again or closed c6's slice (exit $RC, judged $(judged)): $(cat "$STUB/closed" 2>/dev/null) $(cat "$T/$CASE/run.out")"
  [ "$(jq -sc 'map([.number, (.body | test("Conveyor card c6 split #7")), (.body | test("Depends on: #100101"))])' "$STUB/filed")" = '[[100101,true,false],[100102,true,true]]' ] \
    || fail "splitcheck c7-7 7 did not file only slice 2, on c6's plan and after #100101: $(cat "$STUB/filed")"
  [ "$(splitline)" = '[[100101,100102],null,"c6"]' ] || fail "c7-7's split line does not name c6's slices and the plan it finished: $(cat "$ST/cards.jsonl")"
  [ "$(jq -c .order "$ST/control.json")" = '[100101,100102]' ] || fail "#7's place in the order did not go to its slices: $(cat "$ST/control.json")"
  recok "$ST/cards.jsonl" "a split that finished an earlier card's plan"
}

# The same with card c6 stopped after splitplace() put its slices #100101 and #100102 in #7's place in the order, before
# its split line. Bug caught: the next card withdrew them and filed new slices, and #7 was no longer in the order to give
# them its place, so the owner's order was lost. c7-7 files nothing, closes nothing and leaves the order as it is.
t_splitresumeplaced() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  loop control order 7 > /dev/null || fail "the order 7 could not be set"
  stopline
  [ "$(jq -c .order "$ST/control.json")" = '[100101,100102]' ] || fail "card c6's slices did not take #7's place: $(cat "$ST/control.json")"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ ! -e "$STUB/closed" ] && [ "$(wc -l < "$STUB/filed" | tr -d ' ')" = 2 ] && [ "$(judged)" = 1 ] \
    || fail "splitcheck c7-7 7 filed, closed or judged again (exit $RC, judged $(judged)): $(cat "$STUB/closed" 2>/dev/null) $(cat "$STUB/filed") $(cat "$T/$CASE/run.out")"
  [ "$(splitline)" = '[[100101,100102],null,"c6"]' ] || fail "c7-7's split line does not name c6's slices: $(cat "$ST/cards.jsonl")"
  [ "$(jq -c .order "$ST/control.json")" = '[100101,100102]' ] || fail "the order changed: $(cat "$ST/control.json")"
}

# The same with the slices as cards with no GitHub issue (rules.splitissues off: splitcards()). Card c6 made both and
# stopped at its split line; the loop then picked the first. Bug caught: the next card took c6's cards out of the queue
# (a picked one too) and made two more, so the parts were built twice. c7-7 makes none, keeps both in the queue,
# picked or not, and records them as the split's cards.
t_splitresumecards() {
  local old
  slices on "$SPLIT2" "[$(big 7)]"
  loop control rules splitissues=off > /dev/null || fail "control rules splitissues=off failed"
  stopline
  old=$(jq -c '[.cards[].id]' "$(nicards)")
  [ "$(jq length <<<"$old")" = 2 ] || fail "card c6 did not make two parts: $(cat "$(nicards)")"
  jq -c '.cards[0].card = "c-picked"' "$(nicards)" > "$STUB/n.new" && mv "$STUB/n.new" "$(nicards)" || fail "the first part could not be marked picked"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(jq -c '[.cards[].id]' "$(nicards)")" = "$old" ] && [ "$(judged)" = 1 ] \
    || fail "splitcheck c7-7 7 with splitissues off changed c6's parts $old in the queue or judged again (exit $RC): $(cat "$(nicards)") $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "split" and .card == "c7-7") | [.split.cards, .split.resumed] | @json')" = "[$old,\"c6\"]" ] \
    || fail "c7-7's split line does not name c6's parts $old and the plan it finished: $(cat "$ST/cards.jsonl")"
}

# Card c6 is killed after its first slice with the rule On; the owner then sets Split large issues to Shadow. Bug caught
# (review E6): c7-7 finished c6's plan as if the rule were On and filed slice 2, though Shadow builds the issue as one
# card. c7-7 files nothing, withdraws #100101, asks the judge, records a shadow split that ends c6's plan, and goes on (0).
t_splitresumeshadow() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  loop control rules split=shadow > /dev/null || fail "control rules split=shadow failed"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 0 ] && [ "$(wc -l < "$STUB/filed" | tr -d ' ')" = 1 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ "$(judged)" = 2 ] \
    || fail "splitcheck c7-7 7 under Shadow filed a slice, did not withdraw #100101 or did not check #7 anew (exit $RC, judged $(judged)): $(cat "$STUB/filed") $(cat "$STUB/closed" 2>/dev/null) $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "split" and .card == "c7-7") | [.result, .split.mode, .split.filed, .split.resumed, (.split.why | test("#100101 are withdrawn"))] | @json')" = '["split","shadow",null,"c6",true]' ] \
    || fail "c7-7's split line is not a shadow split that ends c6's plan and names #100101: $(cat "$ST/cards.jsonl")"
  recok "$ST/cards.jsonl" "a shadow split that ended an earlier card's plan"
}

# Card c6 is killed after its first slice (#100101: D1 and D2); the owner then swaps D1 and D3 of #7. Bug caught
# (review E7): c7-7 kept c6's slices and item numbers and read the new items' text, so the umbrella said slice 1
# covers "third". c7-7 withdraws #100101, asks the judge on the new text, files its slices #100102 and #100103, and the
# comment and slice bodies give each item its own text.
t_splitresumeedited() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  jq -c 'map(if .number == 7 then .body = "Change src/app.sh.\n\nDone when:\n- third\n- second\n- first" else . end)' "$STUB/issues.json" > "$STUB/i.new" \
    && mv "$STUB/i.new" "$STUB/issues.json" || fail "#7 could not be edited"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ "$(judged)" = 2 ] \
    || fail "splitcheck c7-7 7 on the edited #7 did not withdraw #100101 or did not ask the judge again (exit $RC, judged $(judged)): $(cat "$STUB/closed" 2>/dev/null) $(cat "$T/$CASE/run.out")"
  [ "$(jq -sc 'map([.number, (.body | test("Conveyor card c7-7 split #7") and test("- D1: third\n- D2: second"))]) | .[1:]' "$STUB/filed")" = '[[100102,true],[100103,false]]' ] \
    || fail "c7-7 did not file new slices for the edited items: $(cat "$STUB/filed")"
  grep -qF 'D1 (third): #100102' "$STUB/comments" && grep -qF 'D3 (first): #100103' "$STUB/comments" \
    || fail "the umbrella comment does not give the edited items to the new slices: $(cat "$STUB/comments" 2>/dev/null)"
  [ "$(splitline)" = '[[100102,100103],null,"c6"]' ] || fail "c7-7's split line does not end c6's plan with the new slices: $(cat "$ST/cards.jsonl")"
}

# Card c6 files slice 1 of #7, GitHub refuses slice 2, so c6 withdraws #100101 (closed as not planned) and is killed as
# it writes its split line. Bug caught: c7-7 took the closed #100101 for slice 1 and filed slice 2 alone, so the
# umbrella could close once slice 2 landed, with slice 1's work never built. c7-7 files both slices anew.
t_splitresumewithdrawn() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  # stub: GitHub refuses the second slice once, as c6 files it.
  printf '%s\n' '[ -e "$STUB/refused" ] || [ "$(cat "$STUB/filed" 2>/dev/null | wc -l | tr -d " ")" != 1 ] || { touch "$STUB/refused"; exit 1; }' > "$STUB/create-cmd"
  stopline
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] || fail "card c6 did not withdraw #100101 when slice 2 was refused: $(cat "$T/$CASE/run.out")"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(splitline)" = '[[100102,100103],null,"c6"]' ] \
    || fail "splitcheck c7-7 7 did not file both slices anew in place of the withdrawn #100101 (exit $RC): $(jq -sc 'map(.number)' "$STUB/filed") $(cat "$ST/cards.jsonl")"
}

# Card c6 is killed after its first slice; then GitHub's list of follow-ups fails. Bug caught: c7-7 built #7 whole,
# and its split line ended c6's plan, while #100101 stayed in the queue to build part of #7 again. c7-7 is blocked,
# files and closes nothing, and writes no split line, so the next card reads the plan again.
t_splitresumeunread() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  echo '[ "$4" != all ] || exit 1' > "$STUB/list-cmd"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(st 'select(.card == "c7-7") | .step' | tr '\n' ' ')" = 'blocked ' ] && [ ! -e "$STUB/closed" ] && [ "$(wc -l < "$STUB/filed" | tr -d ' ')" = 1 ] \
    || fail "splitcheck c7-7 7, with c6's slices unread, did not block with no split line, or filed or closed a slice (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  st 'select(.step == "blocked") | .reason' | grep -q 'card c6 planned a split of #7 and stopped before it was recorded, and the issues could not be read' \
    || fail "c7-7's blocked line does not say why: $(st 'select(.step == "blocked") | .reason')"
}

# Card c6 is killed after its first slice; then GitHub's list of open issues fails, so c7-7 cannot tell whether a grown
# slice of #7 is open and files no slice. Bug caught: its split line ended c6's plan and left #100101 in the queue
# beside the whole issue. c7-7 withdraws #100101, records why, and goes on to build #7 whole (0).
t_splitresumeopenunread() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  echo '[ "$4" != open ] || exit 1' > "$STUB/list-cmd"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 0 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ "$(wc -l < "$STUB/filed" | tr -d ' ')" = 1 ] \
    || fail "splitcheck c7-7 7, with the open issues unread, did not withdraw #100101 and build #7 whole (exit $RC): $(cat "$STUB/closed" 2>/dev/null) $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "split" and .card == "c7-7") | [.split.filed, .split.resumed, (.split.why | test("could not be read, so no slice is filed.*#100101 are withdrawn"))] | @json')" = '[null,"c6",true]' ] \
    || fail "c7-7's split line does not say #100101 was withdrawn: $(cat "$ST/cards.jsonl")"
}

# Card c6 is killed after its first slice; then 1000 newer follow-ups are filed. Bug caught: the list of follow-ups
# stopped at the newest 1000, #100101 was not among them, and c7-7 filed slice 1 a second time. c7-7 files slice 2 alone.
t_splitresumemany() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  jq -c '. + [range(200000; 201000) | {number: ., title: "other", body: "", labels: [{name: "conveyor-followup"}]}]' "$STUB/issues.json" > "$STUB/i.new" \
    && mv "$STUB/i.new" "$STUB/issues.json" || fail "the newer follow-ups could not be added"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(splitline)" = '[[100101,100102],null,"c6"]' ] \
    || fail "splitcheck c7-7 7, behind 1000 newer follow-ups, did not file slice 2 alone (exit $RC): $(jq -sc 'map(.number)' "$STUB/filed") $(cat "$T/$CASE/run.out")"
}

# Card c6 splits #7, first in the pick order, and is killed at its split line, after its slices took #7's place there;
# the owner then edits #7. As c7-7 closes #100102, a Board refresh (adopt()) reads #7 and the newer #100300 open. Bugs
# caught: c7-7 withdrew #100101 and #100102, which kept #7's place, so its new slices could not take it and the
# owner's order for #7 was lost; the place went back only after the closes, and the refresh between them dropped the
# closed slices' pins and the place with them. The new slices #100103 and #100104 stand in that place.
t_splitresumeslot() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  loop control order 7 > /dev/null || fail "the order 7 could not be set"
  stopline
  jq -c 'map(if .number == 7 then .body = "Change src/app.sh.\n\nDone when:\n- third\n- second\n- first" else . end)' "$STUB/issues.json" > "$STUB/i.new" \
    && mv "$STUB/i.new" "$STUB/issues.json" || fail "#7 could not be edited"
  fx_in 'eval "real_$(declare -f gh_write)"; gh_write() { real_gh_write "$@" || return; [ "$1 $2 $3" != "issue close 100102" ] || locked adopt '\''[{"number":7},{"number":100300}]'\''; }; splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(splitline)" = '[[100103,100104],null,"c6"]' ] && [ "$(jq -c .order "$ST/control.json")" = '[100103,100104]' ] \
    || fail "the new slices of the edited #7 did not take its place in the order (exit $RC): $(jq -c .order "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Card c6 is killed after its first slice; the owner then sets Split large issues to Off. Bug caught: Off returned
# before the plan was read, so #100101 stayed in the queue beside the whole issue. c7-7 withdraws it, writes no line,
# and goes on to build #7 whole (0).
t_splitresumeoff() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  loop control rules split=off > /dev/null || fail "control rules split=off failed"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 0 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ -z "$(st 'select(.card == "c7-7") | .step')" ] && [ "$(judged)" = 1 ] \
    || fail "splitcheck c7-7 7 under Off did not withdraw #100101, or wrote a line or asked the judge (exit $RC): $(cat "$STUB/closed" 2>/dev/null) $(cat "$T/$CASE/run.out")"
}

# The same with the slices as cards with no GitHub issue (rules.splitissues off): c6 made both and was killed at its
# split line. Bug caught: Off left both cards in the queue beside the whole issue. c7-7 takes them out.
t_splitresumeoffcards() {
  slices on "$SPLIT2" "[$(big 7)]"
  loop control rules splitissues=off > /dev/null || fail "control rules splitissues=off failed"
  stopline
  [ "$(jq '.cards | length' "$(nicards)")" = 2 ] || fail "card c6 did not make two parts: $(cat "$(nicards)")"
  loop control rules split=off > /dev/null || fail "control rules split=off failed"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 0 ] && [ "$(jq '.cards | length' "$(nicards)")" = 0 ] \
    || fail "splitcheck c7-7 7 under Off left c6's parts in the queue (exit $RC): $(cat "$(nicards)") $(cat "$T/$CASE/run.out")"
}

# The same, and the loop picked c6's first part before the owner set the rule Off. Bug caught (review of #1684): the
# picked part stayed in the queue (tcdrop() keeps a picked one) while c7-7 built #7 whole. c7-7 takes the other part
# out and is blocked (1), with no split line.
t_splitresumeoffpicked() {
  slices on "$SPLIT2" "[$(big 7)]"
  loop control rules splitissues=off > /dev/null || fail "control rules splitissues=off failed"
  stopline
  jq -c '.cards[0].card = "c-picked"' "$(nicards)" > "$STUB/n.new" && mv "$STUB/n.new" "$(nicards)" || fail "the first part could not be marked picked"
  loop control rules split=off > /dev/null || fail "control rules split=off failed"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(jq -c '[.cards[].card]' "$(nicards)")" = '["c-picked"]' ] && [ "$(st 'select(.card == "c7-7") | .step' | tr '\n' ' ')" = 'blocked ' ] \
    || fail "splitcheck c7-7 7 under Off, with c6's first part picked, did not take the other out and block (exit $RC): $(cat "$(nicards)") $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
}

# Card c6 is killed after its first slice; the owner sets the rule Off, and GitHub refuses to close #100101. Bug caught
# (review of #1684): c7-7 only said so and built #7 whole beside the open #100101. c7-7 is blocked (1), with the reason.
t_splitresumeoffrefused() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  loop control rules split=off > /dev/null || fail "control rules split=off failed"
  fx_in 'eval "real_$(declare -f gh_write)"; gh_write() { [ "$1 $2 $3" != "issue close 100101" ] || return 1; real_gh_write "$@"; }; splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ ! -e "$STUB/closed" ] && [ "$(st 'select(.card == "c7-7") | .step' | tr '\n' ' ')" = 'blocked ' ] \
    || fail "splitcheck c7-7 7 under Off, with the close of #100101 refused, did not block (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  st 'select(.step == "blocked") | .reason' | grep -q 'Conveyor could not confirm that GitHub closed #100101: they may still be open; built whole beside them, #7 could build their work twice' \
    || fail "c7-7's blocked line does not say why: $(st 'select(.step == "blocked") | .reason')"
}

# Card c6 splits #7; GitHub refuses slice 2, then the close of #100101 that withdraws slice 1. Bug caught (review of
# #1684): c6 recorded a split not filed and built #7 whole beside the open #100101. c6 is blocked (1) with no split
# line, so the next card reads its plan again.
t_splitresumestuck() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  # stub: GitHub refuses the second slice, as c6 files it.
  printf '%s\n' '[ "$(cat "$STUB/filed" 2>/dev/null | wc -l | tr -d " ")" != 1 ] || exit 1' > "$STUB/create-cmd"
  fx_in 'eval "real_$(declare -f gh_write)"; gh_write() { [ "$1 $2 $3" != "issue close 100101" ] || return 1; real_gh_write "$@"; }; splitcheck c6 7'
  [ "$RC" = 1 ] && [ "$(st 'select(.card == "c6") | .step' | tail -n 1)" = blocked ] && [ -z "$(st 'select(.step == "split") | .card')" ] \
    || fail "splitcheck c6 7, with slice 2 and the close of #100101 refused, did not block with no split line (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  st 'select(.step == "blocked") | .reason' | grep -q 'could not be filed whole: slice 2 was not filed.*(#100101): they may still be open; built whole beside them' \
    || fail "c6's blocked line does not say why: $(st 'select(.step == "blocked") | .reason')"
}

# Card c6 is killed after its first slice; the owner takes the follow-up label off #100101 and writes a heading above
# its first line. Bug caught (review of #1684): the list of follow-ups left #100101 out, or its first line no longer
# opened the body, so c7-7 filed slice 1 again. c7-7 files slice 2 alone.
t_splitresumelabel() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  listbylabel
  editfiled 100101 '"## Status\nStill wanted.\n\n" + .' 'map(select(.name != "conveyor-followup"))'
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(splitline)" = '[[100101,100102],null,"c6"]' ] && [ ! -e "$STUB/closed" ] \
    || fail "splitcheck c7-7 7, with #100101 edited, did not file slice 2 alone (exit $RC): $(jq -sc 'map(.number)' "$STUB/filed") $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
}

# Card c6 files #100101 and #100102 (which depends on #100101) and is killed at its split line; the owner closes
# #100101 as not planned. Bug caught (review of #1684): c7-7 filed #100103 in its place and kept #100102, which named
# only the closed #100101, so it could start before #100103 landed. #100102 waits on #100103 too.
t_splitresumereplaced() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopline
  echo 100101 >> "$STUB/closed"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ "$(splitline)" = '[[100103,100102],null,"c6"]' ] \
    || fail "splitcheck c7-7 7 did not file #100103 in place of the closed #100101 and keep #100102 (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  [ "$(jq -r 'select(.number == 100102) | .body | split("\n") | map(select(startswith("Depends on:"))) | join("|")' "$STUB/filed")" = 'Depends on: #100101, #100103' ] \
    || fail "#100102, kept, does not wait on #100103, filed in place of the #100101 it depends on: $(jq -r 'select(.number == 100102) | .body' "$STUB/filed")"
}

# Card c6 files #100101 and #100102 and is killed at its split line; the owner closes #100101 as not planned. c7-7
# files #100103 in its place and is killed as it makes #100102 wait on #100103 (`control depends`), as a second
# restart would stop it. Bug caught (review of #1684): c8-7 kept both #100103 and #100102 (neither filed in its own
# run), so #100102 still named only the closed #100101 and could start before #100103 landed. c8-7 files nothing and
# makes #100102 wait on #100103.
t_splitresumetwice() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopline
  echo 100101 >> "$STUB/closed"
  fx_in 'echo "$BASHPID" > "$STUB/cardpid"; depends() { kill -9 "$(cat "$STUB/cardpid")"; sleep 5; }; splitcheck c7-7 7' # sleep: the subshell waits for the card's kill, so it never returns into a card that goes on
  [ "$RC" = 137 ] && [ "$(jq -sc 'map(.number)' "$STUB/filed")" = '[100101,100102,100103]' ] \
    || fail "c7-7 was not killed after it filed #100103 and before #100102's edit (exit $RC): $(cat "$T/$CASE/run.out")"
  fx_in 'splitcheck c8-7 7'
  [ "$RC" = 1 ] && [ "$(st 'select(.step == "split" and .card == "c8-7") | .split.filed | @json')" = '[100103,100102]' ] && [ "$(jq -s length "$STUB/filed")" = 3 ] \
    || fail "splitcheck c8-7 7 did not keep #100103 and #100102 with nothing filed (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  [ "$(jq -r 'select(.number == 100102) | .body | split("\n") | map(select(startswith("Depends on:"))) | join("|")' "$STUB/filed")" = 'Depends on: #100101, #100103' ] \
    || fail "#100102, kept by c8-7, does not wait on #100103, filed in place of the #100101 it depends on: $(jq -r 'select(.number == 100102) | .body' "$STUB/filed")"
}

# Card c6 is killed after its first slice #100101, and the loop picks #100101 (a card of its own starts); the owner
# then sets the rule Off. Bug caught (review of #1684): c7-7 closed #100101, which does not stop that card, and built #7
# whole beside it. c7-7 closes nothing and is blocked (1), with the reason.
t_splitresumetaken() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  fx_in 'record c9-100101 100101 picked ok'
  [ "$RC" = 0 ] || fail "the pick of #100101 could not be recorded (exit $RC): $(cat "$T/$CASE/run.out")"
  loop control rules split=off > /dev/null || fail "control rules split=off failed"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 1 ] && [ ! -e "$STUB/closed" ] && [ "$(st 'select(.card == "c7-7") | .step' | tr '\n' ' ')" = 'blocked ' ] \
    || fail "splitcheck c7-7 7 under Off, with #100101 picked, closed it or did not block (exit $RC): $(cat "$STUB/closed" 2>/dev/null) $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  st 'select(.step == "blocked" and .card == "c7-7") | .reason' | grep -q 'a card took #100101 already, so none is withdrawn' \
    || fail "c7-7's blocked line does not say why: $(st 'select(.step == "blocked") | .reason')"
}

# Card c6 is killed after its first slice #100101; a loop turn asks for the open issues (#100101 among them), the owner
# sets the rule Off, and c7-7 withdraws #100101; then the turn picks, under the lock, from the list it asked before the
# close (turnask() and turnpick(), lib/run.sh). Bug caught (review of #1684): c7-7's last check for a card of #100101
# came before that pick, so the pick took #100101 while #7 built whole. #100101 is held before it closes, so the pick
# does not take it; once the owner releases it, the same pick would.
t_splitresumestale() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  stopfiling
  # The slices as GitHub lists them: opened by Conveyor's own account (the stub's have no author, and the pick holds
  # an issue opened from outside the project).
  jq -cs '.[0] + (.[1:] | map(. + {authorAssociation: "OWNER"}))' "$STUB/issues.json" "$STUB/filed" > "$STUB/asked.json" || fail "the open list could not be made"
  loop control rules split=off > /dev/null || fail "control rules split=off failed"
  fx_in 'splitcheck c7-7 7'
  [ "$RC" = 0 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] || fail "splitcheck c7-7 7 under Off did not withdraw #100101 (exit $RC): $(cat "$T/$CASE/run.out")"
  # The dry pick is the pick's order (upnext()) on the same card records and control record, and writes nothing.
  p=$(loop pick --dry --issues "$STUB/asked.json" --state "$ST") && [ "$p" != 100101 ] \
    || fail "the pick from the open list asked before #100101 closed ($(jq -c 'map(.number)' "$STUB/asked.json")) took the withdrawn #100101 (exit $?): $p"
  loop control release 100101 > /dev/null || fail "control release 100101 failed"
  [ "$(loop pick --dry --issues "$STUB/asked.json" --state "$ST")" = 100101 ] \
    || fail "with #100101 released, the dry pick from the open list $(jq -c 'map(.number)' "$STUB/asked.json") did not take it, so its hold is not what kept it back"
}

# The card records' append as a failing disk's: a line asked on disk (state.py append cards sync) is written and its
# sync fails (3). A power cut cannot be made here.
SYNCFAIL='eval "real_$(declare -f stdb)"; stdb() { [ "$1 $2 ${3:-}" != "append cards sync" ] || { real_stdb append cards; return 3; }; real_stdb "$@"; }; '

# Card c6 splits #7, and the start line that holds its plan cannot be synced to disk. Bug caught (review of #1684): the
# plan was appended with no sync, so a power cut after a slice was filed could lose it, and the next card filed that
# slice again. c6 files no slice and ends (record(): a card with a worktree folder is blocked too; this one has none),
# its plan line written once.
t_splitresumesync() {
  slices on "$SPLIT2" "[$(big 7)]"; : > "$STUB/list-filed"
  fx_in "$SYNCFAIL"'splitcheck c6 7'
  [ "$RC" = 1 ] && [ ! -s "$STUB/filed" ] && [ "$(st 'select(.plan != null) | .card')" = c6 ] && grep -q 'conveyor: cannot record c6 start' "$T/$CASE/run.out" \
    || fail "splitcheck c6 7, with the plan line not synced, filed a slice or did not end (exit $RC): $(cat "$STUB/filed" 2>/dev/null) $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
}
