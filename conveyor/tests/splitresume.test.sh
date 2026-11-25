#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a split before the build whose card stopped after it filed slices and before its split line was
# recorded (splitplan(), splitmade(), splitend(), lib/slices.sh). What must stay true: each slice of the split is filed
# once; while the rule is On and the issue's text is the plan's, none that the earlier card filed is closed or taken out
# of the queue (the loop can have picked it already), and the next card of the issue files only the slices that are
# missing and records the split; with the rule Shadow, or the issue edited, the next card files none of the plan's
# slices, withdraws those filed, and checks the issue anew. The earlier card is stopped inside its own splitcheck() at
# the point named in each case, as a restart would stop it.
# The fixtures (slices, big, SPLIT2, nicards) are those of slices.test.sh and testcards.test.sh: the runner sources
# every case file into one shell.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

splitline() { st 'select(.step == "split" and .card == "c7-7") | [.split.filed, .split.cards, .split.resumed] | @json'; }
# Card c6 splits #7 and is killed as gh files its second slice: #100101 is filed and nothing else.
stopfiling() {
  # stub: the card's process and the subshells it runs gh in are killed as gh files the second slice, as a restart would;
  # only the processes from gh up to the card's are killed, and none when the card's is not among them.
  printf '%s\n' '[ "$(cat "$STUB/filed" 2>/dev/null | wc -l | tr -d " ")" = 1 ] && [ ! -e "$STUB/killed" ] && { touch "$STUB/killed"; c=$(cat "$STUB/cardpid"); p=$PPID; k=()
    while [ "${p:-1}" -gt 1 ] && [ "$p" != "$c" ]; do k+=("$p"); p=$(ps -o ppid= -p "$p" | tr -d " "); done; [ "$p" != "$c" ] || kill -9 "${k[@]}" "$c"; exit 1; } || :' > "$STUB/create-cmd"
  fx_in 'echo "$BASHPID" > "$STUB/cardpid"; splitcheck c6 7'
  [ -e "$STUB/killed" ] && [ "$(jq -sc 'map(.number)' "$STUB/filed")" = '[100101]' ] || fail "card c6 was not stopped after its first slice (exit $RC): $(cat "$STUB/filed" 2>/dev/null)"
}
# Card c6 splits #7 and is killed as it writes its split line, after every slice is filed and placed.
stopline() {
  fx_in 'eval "c6_$(declare -f record)"; record() { [ "$3" != split ] || kill -9 "$BASHPID"; c6_record "$@"; }; splitcheck c6 7'
  [ "$RC" = 137 ] && [ -z "$(st 'select(.step == "split") | .card')" ] || fail "card c6 was not stopped at its split line (exit $RC): $(cat "$T/$CASE/run.out")"
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
