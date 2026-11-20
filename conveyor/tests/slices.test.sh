#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#270): the rule Split large issues (splitcheck(), umbrellas(), lib/slices.sh) with a stub judge
# (CONVEYOR_SPLIT_CMD: the prompt on its stdin, $STUB/answer its answer, a line in $STUB/judged per call). Each case
# calls the engine's functions as card() and the loop call them; only the shadow case and the three of a grown change
# run a whole card, as only a card proves that a split verdict in shadow still builds and lands the issue as one card,
# and that card() asks about a grown change before a review, once a card, and lands what the answer leaves.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# An issue of three Done-when items that names src/app.sh, with the labels given; the pack's split thresholds ask the
# judge from three Done-when items (split.doneWhen 3), so this issue goes to the judge and a two-item one does not.
# Its items follow a "Done when:" line, which the split check reads and a card's own Done-when check (a heading) does
# not: the stub build ends with no D<n> lines. The owner opened it, so the queue does not hold it (INSIDE).
big() { # <number> [<label>...]
  local n=$1; shift
  jq -cn --argjson n "$n" '{number: $n, title: "big \($n)", body: "Change src/app.sh.\n\nDone when:\n- first\n- second\n- third",
    milestone: null, createdAt: "2026-11-01", labels: ($ARGS.positional | map({name: .})), authorAssociation: "OWNER"}' --args "$@"
}
# A valid split: slice 1 covers D1 and D2, slice 2 covers D3 and depends on slice 1.
SPLIT2='{"verdict":"split","why":"two parts","slices":[{"title":"part one","doneWhen":["one done"],"covers":[1,2]},{"title":"part two","doneWhen":["two done"],"covers":[3],"dependsOn":[1]}]}'
# The case's main with src/app.sh, the rule set to <rule>, the stub judge answering <answer>.
slices() { # <rule> <answer> <issues json>
  setup "$3"; tune '.split.doneWhen = 3'
  mkdir -p "$R/src" && echo 'hello split' > "$R/src/app.sh" && git -C "$R" add src && git -C "$R" commit -qm app || fail "main's src/app.sh"
  jq -c --arg r "$1" '.rules.split = $r' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  printf '%s\n' "$2" > "$STUB/answer"
  export CONVEYOR_SPLIT_CMD='cat > "$STUB/prompt"; echo x >> "$STUB/judged"; cat "$STUB/answer"'
}
# fx_in reads its worktree's .unfixed (FXWT): these cases have no worktree.
# shellcheck disable=SC2034 # read by fx_in (lib.sh)
FXWT=$T/none
judged() { [ -f "$STUB/judged" ] && wc -l < "$STUB/judged" | tr -d ' ' || echo 0; }

# Bug caught: a small issue cost a judge call. An issue under every threshold (two Done-when items, split.doneWhen 3)
# is kept with no model call, and its split line says it was under them; the card goes on (0).
t_slicesunder() {
  slices shadow "$SPLIT2" "[$(big 7 | jq -c '.body = "Change it.\n\nDone when:\n- first\n- second"')]"
  fx_in 'splitcheck c1-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 0 ] || fail "an issue under the thresholds asked the judge ($(judged) calls) or stopped its card (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "split") | [.result, .split.verdict, .split.mode, .split.size.doneWhen] | @json')" = '["kept","under","shadow",2]' ] \
    || fail "the split line of an issue under the thresholds is not kept and under: $(st 'select(.step == "split")')"
  recok "$ST/cards.jsonl" "the split check"
}

# Shadow: the judge's split is recorded on the card's split line with its slices, and the issue is built and landed
# as one card: nothing is filed, held or commented. Bug caught: shadow mode changed what the belt builds.
t_slicesshadow() {
  slices shadow "$SPLIT2" "[$(big 7)]"; echo "$GO" > "$STUB/review.1"
  loop run 1 >/dev/null
  [ "$(judged)" = 1 ] || fail "the judge was asked $(judged) times for one picked issue"
  [ "$(st 'select(.step == "split") | [.result, .split.mode, (.split.slices | length), (.split.filed // null)] | @json')" = '["split","shadow",2,null]' ] \
    || fail "the card's split line does not record the shadow split: $(st 'select(.step == "split")')"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && [ "$(st 'select(.step == "picked") | .issue' | wc -l | tr -d ' ')" = 1 ] \
    || fail "the issue was not built and landed as one card in shadow: $(st .step | tr '\n' ' ')"
  [ ! -s "$STUB/filed" ] && [ "$(jq -c .held "$ST/control.json")" = '[]' ] || fail "shadow filed or held something: $(cat "$STUB/filed" 2>/dev/null) $(jq -c .held "$ST/control.json")"
  recok "$ST/cards.jsonl" "a shadow card"
  # The snapshot gives the card's split to the Board, which shows "Would have split into 2".
  [ "$(loop snapshot | jq -c '.landed | map(select(.issue == 7)) | .[0].split')" = '{"result":"split","slices":2,"filed":null}' ] \
    || fail "the snapshot does not give the landed card its split: $(loop snapshot | jq -c '.landed')"
}

# On, a released parent: the judge is given the issue and the file it names as main has it; the slices are filed as
# follow-ups of the parent (the follow-up label and its priority, "Follow-up of #7", each slice's Done-when items and
# the parent's it covers, the second depending on the first), queued; the parent is held, told which slice covers each
# Done-when item, and its card ends closed before any worktree (1). Bug caught: a split issue was also built whole.
t_sliceson() {
  YES='Visible change approved: yes, 2026-11-02; condition: only for admins'
  SEEN='The Save button reads Keep.'
  slices on "$SPLIT2" "[$(big 7 P1 | jq -c --arg l "$YES" --arg c "$SEEN" '.body |= sub("src/app.sh\\."; "src/app.sh and .claude/x.js.\n\n## What customers or staff will see\n" + $c + "\n\n" + $l)')]"
  mkdir -p "$R/.claude" && echo 'hidden split' > "$R/.claude/x.js" && git -C "$R" add .claude && git -C "$R" commit -qm hidden || fail "main's .claude/x.js"
  fx_in 'splitcheck c1-7 7'
  # Bug caught: a path in a hidden directory was not read as a file, so the judge never saw it.
  grep -q 'hidden split' "$STUB/prompt" || fail "the judge was not given .claude/x.js, a file in a hidden directory: $(cat "$STUB/prompt")"
  [ "$RC" = 1 ] && [ ! -e "$T/$CASE/cards/c1-7" ] || fail "a split issue's card did not end before its worktree (exit $RC): $(cat "$T/$CASE/run.out")"
  grep -q '^D3: third$' "$STUB/prompt" && grep -q 'hello split' "$STUB/prompt" || fail "the judge was not given the Done-when items and src/app.sh: $(cat "$STUB/prompt")"
  [ "$(jq -sc 'map([.number, .title, (.labels | map(.name) | sort)])' "$STUB/filed")" = '[[100101,"part one",["P1","conveyor-followup"]],[100102,"part two",["P1","conveyor-followup"]]]' ] \
    || fail "the slices were not filed as follow-ups of the parent's priority: $(cat "$STUB/filed")"
  jq -se '(.[0].body | startswith("Follow-up of #7: slice 1 of 2") and contains("- D1: first\n- D2: second") and endswith("## Done when\n- one done"))
    and (.[1].body | contains("- D3: third") and contains("Depends on: #100101"))' "$STUB/filed" >/dev/null \
    || fail "a slice's body does not name its parent, the items it covers, its own Done-when items or the slice it depends on: $(jq -r .body "$STUB/filed")"
  [ "$(jq -c .held "$ST/control.json")" = '[7]' ] || fail "the umbrella was not held, or its released parent's slices were held: $(jq -c .held "$ST/control.json")"
  # Bug caught (#648): the slices were not made sub-issues of the issue they split, so GitHub did not group them under it.
  # Bug caught (#733): the id was read as graphql's databaseId, a 32-bit Int that a real id (the stub's, over
  # 2147483647) does not fit, so no slice was attached.
  [ "$(cat "$STUB/subs" 2>/dev/null)" = $'7 100101\n7 100102' ] && grep -q 'are its sub-issues' "$STUB/comments" \
    || fail "the slices were not attached as sub-issues of #7, or its comment does not say so: $(cat "$STUB/subs" 2>/dev/null) $(cat "$STUB/comments")"
  grep -q 'D1 (first): #100101' "$STUB/comments" && grep -q 'D3 (third): #100102' "$STUB/comments" || fail "the umbrella's comment does not name the slice of each Done-when item: $(cat "$STUB/comments")"
  # The start line of file comes before the slices are filed: stop (halt()) leaves the card to finish from there.
  [ "$(st '[.step, .result, .of // empty] | @json' | tr '\n' ' ')" = '["start","ok","file"] ["split","split"] ["closed","ok"] ' ] && [ "$(st 'select(.step == "split") | .split.filed | @json')" = '[100101,100102]' ] \
    || fail "the parent's card is not a start of filing, a split line with the slices filed, then closed: $(cat "$ST/cards.jsonl")"
  recok "$ST/cards.jsonl" "a split card"
  # While it is open, the snapshot's Held names the umbrella's slices (the Board: "Umbrella of #100101, #100102").
  [ "$(loop snapshot | jq -c '.open.held | map(select(.issue == 7)) | .[0].umbrella')" = '[100101,100102]' ] \
    || fail "the snapshot's Held does not name the umbrella's slices: $(loop snapshot | jq -c '.open.held')"
  # Bug caught (#445): a slice did not inherit its parent's visible-change approval, as inherit() read only the
  # "Follow-up to #N (Conveyor card" header of a review follow-up, so its review lost the yes and its condition.
  # Bug caught (E1): the parent's card ends before any review (the issue stays open and held), so its review sentence is "not recorded"; the slice's
  # brief must carry the parent's own section, or the reviewer cannot tell what the owner approved.
  fx_in 'inherited_brief "$(inherit "$(jq -sc ".[0]" "$STUB/filed")")"'
  grep -q '^# The yes of #7$' "$T/$CASE/run.out" && grep -qxF "$YES" "$T/$CASE/run.out" && grep -q '^That yes gives a condition' "$T/$CASE/run.out" \
    || fail "a slice does not inherit its parent's approval line and its condition: $(cat "$T/$CASE/run.out")"
  grep -qxF "$SEEN" "$T/$CASE/run.out" && ! grep -q 'not recorded' "$T/$CASE/run.out" \
    || fail "a slice's brief lacks what its parent's section says customers or staff will see: $(cat "$T/$CASE/run.out")"
  # Bug caught: a run limited by --only to the parent left its slices out (the run reads its set through followups).
  fx_in "ONLY='[7]' upnext '[$(big 100101 conveyor-followup), $(big 100102 conveyor-followup), $(big 9)]' | jq -c '[.[].number]'"
  [ "$(cat "$T/$CASE/run.out")" = '[100101,100102]' ] || fail "a run limited to the split parent does not take its slices: $(cat "$T/$CASE/run.out")"
}

# On, a parent the owner released and put first in the order just before its pick: the card's control record (the
# one the loop read at the start of its turn, CARDCTL) still holds it. Its slices start queued, stand where it stood
# in the order, and the loop picks the first slice; the split line says they were not held. Bug caught (#782): the
# slices were held as the card's old record had it, so the belt went idle on the owner's approved work.
t_slicesreleased() {
  slices on "$SPLIT2" "[$(big 7), $(issue 9 2026-10-01)]"
  jq -c '.order = [8, 7, 9]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  fx_in 'CARDCTL=$(jq -c ".held = [7]" "$ST/control.json") splitcheck c1-7 7'
  [ "$RC" = 1 ] && [ "$(jq -c '[.held, .order]' "$ST/control.json")" = '[[7],[8,100101,100102,9]]' ] \
    || fail "a released parent's slices were held, or do not stand where it stood in the order (exit $RC): $(jq -c '[.held, .order]' "$ST/control.json") $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "split") | .split.held')" = false ] || fail "the split line does not say the slices started queued: $(st 'select(.step == "split")')"
  recok "$ST/cards.jsonl" "a split card of a released parent"
  # #8 is not open, so the slices stand first; #9, older and in the order after them, waits.
  touch "$STUB/list-filed"; fx_in 'locked pick "" "" "$(asked)"'
  [ "$RC" = 0 ] && [ "$(cut -d' ' -f2 "$T/$CASE/run.out")" = 100101 ] || fail "the loop did not pick the first slice #100101 (exit $RC): $(cat "$T/$CASE/run.out")"
}

# On, a held parent: its slices start held too, and the split line says so. (A parent is held between its pick and
# its check only when the owner holds it then; the slices follow the parent's state.)
t_slicesheld() {
  slices on "$SPLIT2" "[$(big 7)]"
  jq -c '.held = [7]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  fx_in 'splitcheck c1-7 7'
  [ "$RC" = 1 ] && [ "$(jq -c .held "$ST/control.json")" = '[7,100101,100102]' ] || fail "a held parent's slices were not held (exit $RC): $(jq -c .held "$ST/control.json") $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "split") | .split.held')" = true ] || fail "the split line does not say the slices started held: $(st 'select(.step == "split")')"
}

# The umbrella closes once a card of each of its slices has landed or closed it as already done, and is released from
# held; with one slice still open, or closed by hand, it stays open. Bug caught: an umbrella stayed open, held, after
# its last slice landed.
t_slicesclose() {
  setup "[$(big 7)]"
  { jq -c '.card = "c1-7" | .step = "split" | .result = "split" | .split = {mode: "on", hash: "h", verdict: "split", why: "", size: {doneWhen: 3, files: 1, areas: 0, chars: 9},
      slices: [], filed: [100101, 100102]}' <(landed 7); landed 100101; } > "$ST/cards.jsonl"
  jq -c '.held = [7]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  fx_in "umbrellas '[{\"number\":7}]'"
  [ ! -e "$STUB/closed" ] || fail "an umbrella with a slice not landed was closed: $(cat "$STUB/closed")"
  # A slice the owner closed by hand while its card was blocked (SHUT) is not done: the umbrella stays open.
  landed 100102 | jq -c --arg r 'the issue was closed by hand while the card was blocked' '.card = "c2-100102" | .step = "closed" | .reason = $r' >> "$ST/cards.jsonl"
  fx_in "umbrellas '[{\"number\":7}]'"
  [ ! -e "$STUB/closed" ] || fail "an umbrella whose slice was closed by hand was closed: $(cat "$STUB/closed")"
  # Bug caught: a last slice that main already did (ALREADY-DONE: a closed line, no landed one) left the umbrella open.
  landed 100102 | jq -c '.card = "c3-100102" | .step = "closed" | .reason = "ALREADY-DONE: src/app.sh does it"' >> "$ST/cards.jsonl"
  fx_in "umbrellas '[{\"number\":7}]'"
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 7 ] && [ "$(jq -c .held "$ST/control.json")" = '[]' ] \
    || fail "the umbrella was not closed and released once its last slice was done: $(cat "$STUB/closed" 2>/dev/null) $(jq -c .held "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Stop (halt(), lib/run.sh) leaves to finish a card whose slices are filed: one split for its size, now in its fix
# session (c1-7), and one split at its pick, before its closed line (c3-9); it stops a card whose grown change was kept
# (c2-8). Bug caught: stop in the fix session after a split for its size put the issue back in the queue with its
# slice open, so it was built whole beside the slice.
t_slicesstop() {
  local c id n s r f p1 p2 p3 a1 a2 a3
  setup "[$(big 7)]"
  { for c in 'c1-7 7 start build' 'c1-7 7 grown split [100101]' 'c1-7 7 start fix' 'c2-8 8 start build' 'c2-8 8 grown kept null' 'c2-8 8 start fix' 'c3-9 9 split split [100102]'; do
      read -r id n s r f <<<"$c"
      landed "$n" | jq -c --arg c "$id" --arg s "$s" --arg r "$r" --argjson f "${f:-null}" '.card = $c | .step = $s | .result = (if $s == "start" then "ok" else $r end)
        | if $s == "start" then .of = $r elif $s == "grown" then .grown = {verdict: (if $f then "split" else "keep" end)} + (if $f then {filed: $f} else {} end)
          else .split = {verdict: "split", filed: $f} end'
    done; } > "$ST/cards.jsonl"
  sleep 60 & p1=$!; sleep 60 & p2=$!; sleep 60 & p3=$! # sleep: stand-ins for the cards' processes, until they are killed
  fx_in "printf '%s\n' '$p1 c1-7' '$p2 c2-8' '$p3 c3-9' | halt"
  # halt() has sent its TERMs when it returns: a stand-in it ended exits 143; one it left is killed here, 137.
  kill -KILL "$p1" "$p3" 2>/dev/null; wait "$p1" 2>/dev/null; a1=$?; wait "$p2" 2>/dev/null; a2=$?; wait "$p3" 2>/dev/null; a3=$?
  [ "$(cat "$T/$CASE/run.out")" = "$p2 c2-8" ] && [ "$a1" = 137 ] && [ "$a2" = 143 ] && [ "$a3" = 137 ] \
    || fail "stop did not leave the cards with filed slices to finish and stop the other (exit: c1-7 $a1, c2-8 $a2, c3-9 $a3): $(cat "$T/$CASE/run.out")"
}

# An answer that leaves D2 uncovered breaks the rules: it is recorded (invalid, the answer kept) and the issue is kept
# whole, in On too: nothing is filed or held, and the card goes on. Bug caught: a split that dropped a Done-when item.
t_slicesbad() {
  slices on '{"verdict":"split","slices":[{"title":"a","doneWhen":["x"],"covers":[1]},{"title":"b","doneWhen":["y"],"covers":[3]}]}' "[$(big 7)]"
  fx_in 'splitcheck c1-7 7'
  [ "$RC" = 0 ] && [ ! -s "$STUB/filed" ] && [ "$(jq -c .held "$ST/control.json")" = '[]' ] || fail "an answer that leaves D2 uncovered split the issue (exit $RC): $(cat "$STUB/filed" 2>/dev/null)"
  [ "$(st 'select(.step == "split") | [.result, .split.verdict, .split.why, (.split.answer | contains("covers"))] | @json')" = '["kept","invalid","no slice covers D2",true]' ] \
    || fail "the broken answer was not recorded with the issue kept: $(st 'select(.step == "split")')"
  recok "$ST/cards.jsonl" "a kept split check"
}

# A slice with no Done-when items of its own breaks the rules: SPLIT2 with slice 1's doneWhen empty, missing, a blank
# item or a number is read as invalid. Bug caught: the check read the length of the slice, not of its doneWhen, and
# filed a slice with an empty Done-when section.
t_slicesnodone() {
  setup '[]'
  fx_in 'for d in "[]" null "[\" \"]" "[1]"; do jq -c --argjson d "$d" ".slices[0].doneWhen = \$d" <<<"$SPLIT2" | jq -Rsc --argjson n 3 "$SPLITREAD" | jq -r .why; done'
  [ "$(sort -u "$T/$CASE/run.out")" = 'a slice has no Done-when items of its own' ] && [ "$(wc -l < "$T/$CASE/run.out" | tr -d ' ')" = 4 ] \
    || fail "a slice with no Done-when items passed the split check: $(cat "$T/$CASE/run.out")"
}

# The measure health gives the Health view (SPLITM, lib/views.sh): of the checked cards, the kept ones and the "would
# split" ones built whole, each with how many had a first review, how many of those said GO and their fix rounds, and
# the issues split into slices and not built; a card the rule did not check counts in none. Bug caught: the trial had
# no figures to compare.
t_slicesmeasure() {
  setup '[]'
  rec() { jq -cn --arg c "$1" --arg s "$2" --arg r "$3" '{card: $c, issue: 1, step: $s, time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: ""}
    + if $s == "split" then {split: {mode: "shadow", hash: "h", verdict: (if $r == "split" then "split" else "keep" end), why: "", size: {doneWhen: 3, files: 0, areas: 0, chars: 9}}} else {} end'; }
  { rec k1 split kept; rec k1 worktree ok; rec k1 review GO
    rec k2 split kept; rec k2 worktree ok; rec k2 review NO-GO; rec k2 fix ok; rec k2 review GO
    rec w1 split split; rec w1 worktree ok; rec w1 review NO-GO; rec w1 fix ok; rec w1 fix ok
    rec u1 split split; rec u1 closed ok
    rec n1 worktree ok; rec n1 review GO; } >> "$ST/cards.jsonl"
  [ "$(loop health | jq -c .split)" = '{"kept":{"cards":2,"reviewed":2,"go":1,"fixes":1},"wouldSplit":{"cards":1,"reviewed":1,"go":0,"fixes":2},"split":1}' ] \
    || fail "health does not measure the checked cards: $(loop health 2>&1 | jq -c .split)"
}

# Once a text: a slice (the follow-up label) is never checked; an issue whose text has a split line is not checked
# again; once edited, it is. Bug caught: every retry of a large issue cost a judge call again.
t_slicesonce() {
  slices shadow '{"verdict":"keep","why":"one change"}' "[$(big 7), $(big 8 conveyor-followup)]"
  fx_in 'splitcheck c1-8 8; splitcheck c1-7 7; splitcheck c2-7 7'
  [ "$(judged)" = 1 ] && [ "$(st 'select(.step == "split") | .card' | tr '\n' ' ')" = 'c1-7 ' ] \
    || fail "a slice, or the same text twice, was checked again: $(judged) calls, $(st 'select(.step == "split") | .card' | tr '\n' ' ')"
  jq -c '.[0].body += "\n- fourth"' "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json"
  fx_in 'splitcheck c3-7 7'
  [ "$(judged)" = 2 ] || fail "an edited issue was not checked again: $(judged) calls"
}

# A change that grew while it was built (#448, growcheck()): issue 7 (two Done-when items, so under the split check,
# and the owner's visible-change approval GYES), the pack's split.growFiles 3, the rule <rule>, the stub judge
# answering GROWN. The five-file change FIVE edits src/s1.sh and adds src/c1.sh to c3.sh and src/s2.sh.
GROWN='{"verdict":"split","why":"the tests apart","core":["src/c1.sh","src/c2.sh","src/c3.sh"],"slices":[{"title":"the rest","doneWhen":["rest done"],"files":["src/s1.sh","src/s2.sh"]}]}'
FIVE='for f in c1 c2 c3; do echo "$f" > "src/$f.sh"; done; echo more >> src/s1.sh; echo new > src/s2.sh'
GYES='Visible change approved: yes, 2026-11-02'
grown() { # <rule>
  slices "$1" "$GROWN" "[$(big 7 | jq -c --arg l "$GYES" '.body = "Change src/app.sh.\n\nDone when:\n- first\n- second\n\n" + $l')]"; tune '.split.growFiles = 3'
}
# The whole card of issue 7, as only a card proves that card() asks before its review: main has src/s1.sh, the build
# makes FIVE (once: the fix session after a split builds nothing again), and the review is a GO.
grownrun() { # <rule>
  grown "$1"; echo 'main s1' > "$R/src/s1.sh"; git -C "$R" add src && git -C "$R" commit -qm s1 || fail "main's src/s1.sh"
  echo "[ -e src/c1.sh ] || { $FIVE; }" > "$STUB/build"; echo "$GO" > "$STUB/review.1"
  loop run 1 >/dev/null
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card of issue 7 did not land: $(st .step | tr '\n' ' ')"
}
landedfiles() { git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ' '; }

# On: the judge keeps three core files and moves two into one slice; the slice is filed under the issue, its files go
# back to main's (the edited one restored, the added one removed), one fix session is told why, and the card is
# reviewed and lands the core files alone. Bug caught: a card whose change grew to 60 files was reviewed and tested whole.
t_slicesgrown() {
  grownrun on
  [ "$(judged)" = 1 ] || fail "the judge was asked $(judged) times about a grown change"
  grep -q 'grown to 5 files' "$STUB/prompt" && grep -q 'past the 3 files' "$STUB/prompt" && grep -q '^+more$' "$STUB/prompt" \
    || fail "the judge was not given the size and the change: $(cat "$STUB/prompt")"
  [ "$(landedfiles)" = 'src/c1.sh src/c2.sh src/c3.sh ' ] || fail "the card did not land only the core files: $(landedfiles)"
  jq -se 'length == 1 and (.[0] | .title == "the rest" and (.labels | map(.name) == ["conveyor-followup"])
    and (.body | startswith("Follow-up of #7: slice 1 of 1. Conveyor card ") and contains("- src/s2.sh") and contains("Depends on: #7") and endswith("## Done when\n- rest done")))' "$STUB/filed" >/dev/null \
    || fail "the slice was not filed as a follow-up of the issue that depends on it: $(cat "$STUB/filed" 2>/dev/null)"
  grep -q '^# The change was split for its size' "$STUB/brief" && grep -qF -- '- #100101 the rest: src/s1.sh, src/s2.sh' "$STUB/brief" \
    || fail "the fix session was not told what was moved out: $(cat "$STUB/brief")"
  [ "$(st 'select(.step == "grown") | [.result, .grown.mode, .grown.files, .grown.after, .grown.filed] | @json')" = '["split","on",5,3,[100101]]' ] \
    && [ "$(st 'select(.step == "fix") | .reason')" = 'split for its size: 5 files, 3 after; its slices are #100101' ] \
    || fail "the card's lines do not record the split for its size: $(cat "$ST/cards.jsonl")"
  # Bug caught: stop (halt()) while the slices were being filed ended the card, as no line said it had begun filing.
  [[ " $(st 'select(.step == "start" or .step == "grown") | .of // .step' | tr '\n' ' ')" == *' file grown fix '* ]] \
    || fail "the card has no start of filing before its slices are filed: $(st 'select(.step == "start" or .step == "grown") | .of // .step' | tr '\n' ' ')"
  recok "$ST/cards.jsonl" "a card split for its size"
  # The track (the Board and /units) says it, with the count before and after.
  [ "$(loop snapshot | jq -c '.landed[] | select(.issue == 7) | .track | [.grown, any(.records[]; .name == "split for its size: 5 files, 3 after")]')" = '[{"before":5,"after":3},true]' ] \
    || fail "the track does not say the card was split for its size: $(loop snapshot | jq -c '.landed[] | select(.issue == 7) | .track | {grown, records}')"
  # Bug caught: the slice's opening line did not match inherit()'s slice header, so it lost its parent's approval.
  fx_in 'inherit "$(jq -sc ".[0]" "$STUB/filed")" | jq -r .from'
  [ "$(cat "$T/$CASE/run.out")" = 7 ] || fail "a slice split for size does not inherit its parent's approval: $(cat "$T/$CASE/run.out")"
  # Bug caught: a run limited by --only to the parent left out its slices, as only the grown line names them.
  jq -sc --argjson i "$(big 9)" 'map(.authorAssociation = "OWNER") + [$i]' "$STUB/filed" > "$STUB/up.json"
  fx_in 'ONLY="[7]" upnext "$(cat "$STUB/up.json")" | jq -c "[.[].number]"'
  [ "$(cat "$T/$CASE/run.out")" = '[100101]' ] || fail "a run limited to the parent does not take its size slice: $(cat "$T/$CASE/run.out")"
  # Bug caught: a parent that blocked (for the owner's yes) in place of landing left its slice in the run, waiting on
  # it, and pick answered wait on every poll (the whole list, all, is what it reads), so the run never ended.
  cp "$ST/cards.jsonl" "$STUB/cards.landed"
  jq -c 'if .step == "landed" or .step == "pushed" then .step = "blocked" else . end' "$STUB/cards.landed" > "$ST/cards.jsonl"
  fx_in 'ONLY="[7]" upnext "$(cat "$STUB/up.json")" all | jq -c "[.[].number]"'
  [ "$(cat "$T/$CASE/run.out")" = '[]' ] || fail "a run limited to a blocked parent still waits on its size slice: $(cat "$T/$CASE/run.out")"
  cp "$STUB/cards.landed" "$ST/cards.jsonl"
  # Bug caught: once `retry` gave back the parent (approved(), after the owner's yes), its grown line is in the retried
  # file, and a run limited by --only to the parent left the slice queued.
  jq -c 'select(.step == "grown")' "$ST/cards.jsonl" > "$ST/retried.jsonl"; jq -c 'select(.step != "grown")' "$ST/cards.jsonl" > "$STUB/cards.new"
  mv "$STUB/cards.new" "$ST/cards.jsonl"
  fx_in 'ONLY="[7]" upnext "$(cat "$STUB/up.json")" | jq -c "[.[].number]"'
  [ "$(cat "$T/$CASE/run.out")" = '[100101]' ] || fail "a run limited to a retried parent does not take its size slice: $(cat "$T/$CASE/run.out")"
  # Bug caught: a retried parent whose card blocked again kept the run waiting on its slice, as above.
  jq -c 'if .step == "landed" or .step == "pushed" then .step = "blocked" else . end' "$ST/cards.jsonl" > "$STUB/cards.new"
  mv "$STUB/cards.new" "$ST/cards.jsonl"
  fx_in 'ONLY="[7]" upnext "$(cat "$STUB/up.json")" all | jq -c "[.[].number]"'
  [ "$(cat "$T/$CASE/run.out")" = '[]' ] || fail "a run limited to a retried parent that blocked again still waits on its size slice: $(cat "$T/$CASE/run.out")"
}

# On, grown in a fix: the build makes one file, the first review is a NO-GO, and the fix session after it makes FIVE;
# the judge is asked before the second review, and the card lands the core files alone. Bug caught: a card asked only
# before its first review (growcheck() on pass 1 alone) let a change that grew in a fix be reviewed and land whole.
t_slicesgrownfix() {
  grown on; echo 'main s1' > "$R/src/s1.sh"; git -C "$R" add src && git -C "$R" commit -qm s1 || fail "main's src/s1.sh"
  echo "if grep -q 'wrong word' \"\$STUB/brief\" && ! grep -q '^# The change was split for its size' \"\$STUB/brief\"; then $FIVE
    elif [ ! -e src/c1.sh ]; then echo c1 > src/c1.sh; fi" > "$STUB/build"
  printf '%s\n' '[P1] src/c1.sh:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  loop run 1 >/dev/null
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card of issue 7 did not land: $(st .step | tr '\n' ' ')"
  [ "$(judged)" = 1 ] && [ "$(st 'select(.step == "review" or .step == "grown") | .step' | tr '\n' ' ')" = 'review grown review ' ] \
    || fail "a change that grew in a fix was not checked before its next review ($(judged) judge calls): $(st .step | tr '\n' ' ')"
  [ "$(landedfiles)" = 'src/c1.sh src/c2.sh src/c3.sh ' ] && [ "$(jq -sc 'map(.title)' "$STUB/filed")" = '["the rest"]' ] \
    || fail "the card grown in a fix did not land only the core files: $(landedfiles) $(cat "$STUB/filed" 2>/dev/null)"
}

# On, with a lint command (a stub finding each line with BAD in src/*.sh): the build makes FIVE, clean, and the fix
# session after the split adds BAD to src/c1.sh. Bug caught: the split's fix changed the change after the review gate,
# and the card was reviewed and landed with the finding unlinted. The gate runs again after it, a lint fix removes the
# finding, and the card lands clean. A whole card: only card() shows the gate's place after growcheck().
t_slicesgrownlint() {
  grown on; echo 'main s1' > "$R/src/s1.sh"; git -C "$R" add src && git -C "$R" commit -qm s1 || fail "main's src/s1.sh"
  printf '%s\n' 'r=0; for f; do grep -q BAD "$f" && { echo "$f:1: E1 a bad word"; r=1; }; done; exit $r' > "$STUB/lint"
  tune --arg r "bash $STUB/lint {files}" '.lint = {commands: [{files: ["src/*.sh"], run: $r}]}'
  echo "if grep -q '^# Lint findings: fix them' \"\$STUB/brief\"; then echo c1 > src/c1.sh
    elif grep -q '^# The change was split for its size' \"\$STUB/brief\"; then echo BAD >> src/c1.sh
    else $FIVE; fi" > "$STUB/build"; echo "$GO" > "$STUB/review.1"
  # loop: only card() shows the review gate running again after growcheck()'s fix session
  loop run 1 >/dev/null
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card of issue 7 did not land: $(st .step | tr '\n' ' ')"
  [ "$(st 'select(.step | IN("lint", "grown", "fix", "review")) | "\(.step):\(.result)"' | tr '\n' ' ')" = 'lint:pass grown:split fix:ok lint:findings fix:ok lint:pass review:GO ' ] \
    && ! git -C "$R" show HEAD:src/c1.sh | grep -q BAD \
    || fail "the change the split's fix left was not linted before its review: $(st 'select(.step | IN("lint", "grown", "fix", "review")) | "\(.step):\(.result)"' | tr '\n' ' ')"
}

# Shadow: the judge's answer is recorded on the grown line, and the card lands its change as it was: nothing filed,
# no fix. Bug caught: Shadow changed what the card lands.
t_slicesgrownshadow() {
  grownrun shadow
  [ "$(judged)" = 1 ] || fail "the judge was asked $(judged) times about a grown change in Shadow"
  [ "$(landedfiles)" = 'src/c1.sh src/c2.sh src/c3.sh src/s1.sh src/s2.sh ' ] && [ ! -s "$STUB/filed" ] && [ -z "$(st 'select(.step == "fix")')" ] \
    || fail "Shadow changed the change, filed a slice or ran a fix: $(landedfiles) $(cat "$STUB/filed" 2>/dev/null)"
  [ "$(st 'select(.step == "grown") | [.result, .grown.mode, .grown.files, (.grown.slices | length), .grown.filed] | @json')" = '["split","shadow",5,1,null]' ] \
    || fail "the Shadow answer was not recorded: $(cat "$ST/cards.jsonl")"
  recok "$ST/cards.jsonl" "a grown line in Shadow"
}

# Two files, and two documents (*.md, left out), are not past a size of 3: no judge call and no line. Bug caught: a
# small change, or its documentation, cost a judge call.
t_slicesgrownsmall() {
  grown on; fx_wt 'echo a > src/c1.sh; echo b > src/c2.sh; echo d > one.md; echo e > two.md' src/s1.sh 'main s1'
  fx_in 'growcheck c7 7 "$FXWT" "$(big 7)" brief'
  [ "$RC" = 0 ] && [ "$(judged)" = 0 ] && [ ! -s "$ST/cards.jsonl" ] || fail "a change of 2 files was sent to the judge (exit $RC, $(judged) calls): $(cat "$ST/cards.jsonl" 2>/dev/null)"
}
