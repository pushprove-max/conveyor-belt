#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#270): the rule Split large issues (splitcheck(), umbrellas(), lib/slices.sh) with a stub judge
# (CONVEYOR_SPLIT_CMD: the prompt on its stdin, $STUB/answer its answer, a line in $STUB/judged per call). Each case
# calls the engine's functions as card() and the loop call them; only the shadow case runs a whole card, as only a
# card proves that a split verdict in shadow still builds and lands the issue as one card.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# An issue of three Done-when items that names src/app.sh, with the labels given; the pack's split thresholds ask the
# judge from three Done-when items (split.doneWhen 3), so this issue goes to the judge and a two-item one does not.
# Its items follow a "Done when:" line, which the split check reads and a card's own Done-when check (a heading) does
# not: the stub build ends with no D<n> lines.
big() { # <number> [<label>...]
  local n=$1; shift
  jq -cn --argjson n "$n" '{number: $n, title: "big \($n)", body: "Change src/app.sh.\n\nDone when:\n- first\n- second\n- third",
    milestone: null, createdAt: "2026-11-01", labels: ($ARGS.positional | map({name: .}))}' --args "$@"
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
  grep -q 'D1 (first): #100101' "$STUB/comments" && grep -q 'D3 (third): #100102' "$STUB/comments" || fail "the umbrella's comment does not name the slice of each Done-when item: $(cat "$STUB/comments")"
  [ "$(st '[.step, .result] | @json' | tr '\n' ' ')" = '["split","split"] ["closed","ok"] ' ] && [ "$(st 'select(.step == "split") | .split.filed | @json')" = '[100101,100102]' ] \
    || fail "the parent's card is not a split line with the slices filed, then closed: $(cat "$ST/cards.jsonl")"
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

# On, a held parent: its slices start held too. (A parent is held between its pick and its check only when the owner
# holds it then; the slices follow the parent's state.)
t_slicesheld() {
  slices on "$SPLIT2" "[$(big 7)]"
  jq -c '.held = [7]' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  fx_in 'splitcheck c1-7 7'
  [ "$RC" = 1 ] && [ "$(jq -c .held "$ST/control.json")" = '[7,100101,100102]' ] || fail "a held parent's slices were not held (exit $RC): $(jq -c .held "$ST/control.json") $(cat "$T/$CASE/run.out")"
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
