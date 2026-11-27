#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: land-branch.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a branch landed by land-branch runs a build session, skips the review, the visible-change check or the
# changed tests, or lands on a NO-GO without its fix session; its lines are not a card's (no card id, no branch on the
# picked line, the wrong issue); the branch itself is moved; a refusal (no branch, no change, a conflict with main, an
# issue whose card is open) leaves a card behind; a card of no issue posts on issue 0.
# One case for each part (t_branch, t_branchfix, t_branchtests, t_branchvisible, t_branchrefused, t_branchnolink), so
# they run side by side, each on a main of its own (branchsetup). count is of the part's own sessions, reviews and
# test runs. t_branchfix and t_branchrefused are in branchfix.test.sh, t_branchtests in branchtests.test.sh and
# t_branchvisible in branchvisible.test.sh, using this file's branchsetup (the runner sources every case file): the
# six cost about 17 CPU s together, over a file's CPU budget (test.fileBudget).
branchsetup() {
  setup "[$(issue 7 2026-01-01 area:billing)]"
  lane() { # <branch> <file> <text> [commit message] [start point]: a branch with one commit, made in a worktree of its own
    git -C "$R" worktree add -q -b "$1" "$T/$CASE/lane-$1" "${5:-main}" && mkdir -p "$(dirname "$T/$CASE/lane-$1/$2")" && echo "$3" > "$T/$CASE/lane-$1/$2" && git -C "$T/$CASE/lane-$1" add "$2" \
      && git -C "$T/$CASE/lane-$1" commit -qm "${4:-fix(tooling): $1 change}"
  }
  steps() { st "select(.card == \"$1\") | .step" | tr '\n' ' '; }
  newest() { st 'select(.step == "picked") | .card' | tail -n 1; }
  count() { [ "$(cat "$STUB/sessions" 2>/dev/null | wc -l) $(cat "$STUB/reviews" 2>/dev/null | wc -l) $(cat "$STUB/tests" 2>/dev/null | wc -l)" = "$1" ] || fail "sessions, reviews and test runs so far are $(cat "$STUB/sessions" 2>/dev/null | wc -l) $(cat "$STUB/reviews" 2>/dev/null | wc -l) $(cat "$STUB/tests" 2>/dev/null | wc -l), not $1"; }
  init=$(git -C "$R" rev-parse HEAD)
}
t_branch() {
  branchsetup; linkset '{"a.txt": ["a.test.sh"], "b.txt": ["a.test.sh"]}'; init=$(git -C "$R" rev-parse HEAD) # b.txt's change runs the stub test file
  # A good change on a branch that names no issue: one review, the changed tests, landed. No build session.
  lane fast-lane b.txt bee; tip=$(git -C "$R" rev-parse fast-lane); echo "$GO" > "$STUB/review.1"
  out=$(loop land-branch fast-lane) || fail "a good branch did not land: $out"
  c=$(newest); count "0 1 1"
  [ "$(steps "$c")" = "picked worktree deps brief start test start review start test start landed " ] || fail "steps of a good branch: $(steps "$c")"
  [ "$(st 'select(.step == "picked") | [.issue, .branch, .title] | join("|")')" = "0|fast-lane|fix(tooling): fast-lane change" ] || fail "picked line: $(st 'select(.step == "picked")')"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse main)" ] && [ "$(cat "$R/b.txt")" = bee ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    && [ "$(git -C "$R" rev-parse main~1)" = "$init" ] || fail "main is not its old head plus one commit holding the branch's change"
  [ "$(git -C "$R" log -1 --format=%B main)" = "fix(tooling): fast-lane change"$'\n\n'"Conveyor card $c, branch fast-lane" ] || fail "commit message: $(git -C "$R" log -1 --format=%B main)"
  [ "$(git -C "$R" rev-parse fast-lane)" = "$tip" ] && grep -q "card $c, branch fast-lane: landed" <<<"$out" && [ -z "$(ls "$T/$CASE/cards")" ] || fail "the branch moved, the landing was not reported, or the worktree or its files are left: $out $(ls "$T/$CASE/cards")"
  recok "$ST/cards.jsonl" "a land-branch card (its picked line with branch)"
  [ "$(loop cards | jq -c '[.landed, (.cards | map("\(.issue) \(.step) \(.reviews)"))]')" = '[1,["0 landed 1"]]' ] || fail "dashboard row of a branch card: $(loop cards)"
  # A branch card that has its brief line is in review 1, not in a build.
  jq -c 'select(.step | IN("picked", "worktree", "brief")) | .card = "c1-0"' "$ST/cards.jsonl" > "$STUB/open" && cat "$STUB/open" >> "$ST/cards.jsonl"
  [ "$(loop cards | jq -c '.cards | map(select(.card == "c1-0") | [.step, .stage])')" = '[["review",2]]' ] || fail "a branch card after its brief is not shown in review 1: $(loop cards)"
  grep -v '"c1-0"' "$ST/cards.jsonl" > "$STUB/open"; cat "$STUB/open" > "$ST/cards.jsonl"
  # Landed already: the same branch holds no change against main now, and no card is made for it.
  out=$(loop land-branch fast-lane) && grep -q 'nothing to land' <<<"$out" && [ "$(newest)" = "$c" ] || fail "a branch main already holds made a card or failed: $out"
}
t_branchnolink() {
  branchsetup
  # Bug: a branch merged into the card's worktree, then the dependencies could not be linked
  # (here a folder the branch tracks is where the link goes), and the block threw the staged change away. It is
  # kept as a patch.
  P=$R/.conveyor/project.json; jq '.linkFromMain += ["sub/node_modules"]' "$P" > "$P.new" && mv "$P.new" "$P"
  lane nolink g.txt gee; mkdir -p "$T/$CASE/lane-nolink/sub/node_modules/node_modules" "$R/sub/node_modules"
  echo '{}' > "$T/$CASE/lane-nolink/sub/package.json"; echo x > "$T/$CASE/lane-nolink/sub/node_modules/node_modules/x"
  git -C "$T/$CASE/lane-nolink" add -f sub; git -C "$T/$CASE/lane-nolink" commit -qm 'fix(tooling): nolink, its package'
  out=$(loop land-branch nolink 2>&1) && fail "a branch card whose dependencies could not be linked exited zero: $out"
  c=$(newest); k=$(st "select(.card == \"$c\" and .step == \"blocked\") | \"\\(\$ENV.ST)/\\(.kept)\"")
  st "select(.card == \"$c\" and .step == \"blocked\") | .reason" | grep -q "^worktree: the engine could not link the dependencies of the main checkout" \
    && [ "$(steps "$c")" = "picked worktree blocked " ] && [ "$(git -C "$R" apply --numstat "$k/$c.patch" 2>&1 | cut -f3 | tr '\n' ' ')" = "g.txt sub/node_modules/node_modules/x sub/package.json " ] && [ "$(cat "$k/$c.base" 2>&1)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "a branch card whose dependencies could not be linked did not keep its merged change as a patch: $(st "select(.card == \"$c\")") $(ls "$k" 2>&1)"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "that blocked card left files beside its worktree: $(ls "$T/$CASE/cards")"
  rm -rf "$R/sub"; loop check || fail "the record check fails after the card whose dependencies could not be linked"
}

# Bug (#1457): a land-branch card started its processes with no card's mark (CONVEYOR_CARDRUN), which only a card of
# the loop had (cardrun()). So a review it started, left running once the card's shell was gone, was no process of the
# card's to retry or shut (leftin(), lib/run.sh), and they took its worktree from under it. A process the card starts
# (card() a stand-in that runs one) carries the card's id.
t_branchmark() {
  local c
  branchsetup; lane seven s.txt ess
  fx_in 'card() { printenv CONVEYOR_CARDRUN > "$STUB/mark"; }; landbranch seven'
  c=$(newest)
  [ -n "$c" ] && [ "$(cat "$STUB/mark" 2>/dev/null)" = "$c" ] \
    || fail "land-branch seven: a process its card ${c:-(none picked)} started carried the mark '$(cat "$STUB/mark" 2>/dev/null)', not the card's id: $(cat "$T/$CASE/run.out")"
}

# Bug (#1674): #7 split into two slices that are cards with no GitHub issue; slice a blocked and the owner shut it, and
# its change landed by hand with `land-branch <a's card id>`. That card was a new card of issue 0 that no slice knew, so
# umbrellas() never counted a as done: #7 stayed open and held. And the snapshot gave #7 no slices, so `foreman status`
# called the split's hold the owner's. Now the snapshot names the slices (a shut, b landed); land-branch refuses the
# branch while a's card is open, and once a is shut lands it as slice a, so #7 is closed and released.
t_branchslice() {
  local a b c sd
  branchsetup
  fx_in 'splitcards c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" '"'"'[{"title":"First part","doneWhen":["a"],"covers":[1],"dependsOn":[]},{"title":"Second part","doneWhen":["b"],"covers":[2],"dependsOn":[1]}]'"'"' 1'
  a=$(jq -r '.cards[0].id' "$(nicards)"); b=$(jq -r '.cards[1].id' "$(nicards)")
  [ "$(nipick)" = "$a 0 false" ] || fail "the pick did not take the first slice $a: $(cat "$T/$CASE/run.out")"
  loop control hold 7 > /dev/null || fail "control hold 7 failed"
  lane "$a" s.txt ess
  fx_in 'card() { append "$(line "$1" "$2" landed ok "{\"sha\":\"abe\",\"product\":false}")"; }; landbranch '"$a"
  [ "$RC" != 0 ] && grep -qF "slice $a has its card $a still open" "$T/$CASE/run.out" && [ "$(newest)" = "$a" ] \
    || fail "land-branch $a was taken while the slice's own card $a was open (exit $RC): $(cat "$T/$CASE/run.out") $(st 'select(.step == "picked") | .card')"
  # b landed as a commit main does not hold yet (a side branch's), as after the pack's defaultBranch changed.
  lane side t.txt tee; sd=$(git -C "$R" rev-parse side)
  fx_in 'append "$(line c1-7 7 split split "{\"split\":{\"mode\":\"on\",\"hash\":\"h\",\"size\":{\"areas\":1,\"chars\":10,\"doneWhen\":3,\"files\":1},\"verdict\":\"split\",\"why\":\"w\",\"cards\":[\"'"$a"'\",\"'"$b"'\"],\"filed\":[]}}")"
    append "$(line c1-7 7 closed ok "{\"reason\":\"split\"}")"
    append "$(line '"$a"' 0 blocked fail "{\"reason\":\"the review found a fault\"}")"
    append "$(line '"$a"' 0 closed ok "$(jq -cn --arg r "$OWNSHUT" "{reason: \$r}")")"
    append "$(line '"$b"' 0 landed ok "{\"sha\":\"'"$sd"'\",\"product\":false}")"; umbrellas "$(asked)"'
  [ ! -e "$STUB/closed" ] || fail "the umbrella #7 closed with its slice $a shut and not landed: $(cat "$STUB/closed")"
  # Bugs: the snapshot counted b landed though main does not hold its commit (umbrellas() does not count it), and gave
  # #7's own hold no mark of the split's, so the Board grouped it under Held by you. (Each slice entry may also carry
  # its card's name, which the snapshot adds to every object that names a card; only card and state are in question.)
  [ "$(loop snapshot --fresh | jq -c '.open.held[] | select(.issue == 7) | [.reasons[0], (.sliceCards | map({card, state}))]')" = "[{\"kind\":\"you\",\"split\":true},[{\"card\":\"$a\",\"state\":\"shut\"},{\"card\":\"$b\",\"state\":\"waiting\"}]]" ] \
    || fail "the snapshot does not give #7 the split's hold and its slice cards, $a shut and $b waiting (its commit off main): $(loop snapshot --fresh | jq -c '.open.held')"
  git -C "$R" merge -q --ff-only side || fail "main could not take the side branch"
  # The land-branch of slice a, with two bugs forced. A competing writer of the record of the cards with no GitHub
  # issue (tcadd()) acts at once after the card's id is picked, before the slice's entry keeps it, with the clock held
  # so it would pick the same id: it waits for the record's lock when pickbranch() holds it, else it runs then. And
  # the card stand-in keeps the issue the card is reviewed against (cardissueof()), which was the branch's commit
  # messages in place of the slice's own Done-when items.
  fx_in 'date() { if [ "${2:-}" = +%Y%m%dT%H%M%S ]; then k=$(( $(cat "$STUB/dates" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$STUB/dates"; printf "20990101T0000%02d\n" "$(( k < 3 ? 0 : k ))"; else command date "$@"; fi; }
    eval "real$(declare -f slicetake)"
    slicetake() { if ( [ -z "${lock:-}" ] || exec {lock}>&-; flock -n "$TACARDS.lock" true ); then tcadd "" Other "other body" > "$STUB/tcid"
      else ( exec {lock}>&-; tcadd "" Other "other body" > "$STUB/tcid" ) & fi; realslicetake "$@"; }
    card() { cardissueof "$1" "$2" "$3" "$4" > "$STUB/issue"; append "$(line "$1" "$2" landed ok "{\"sha\":\"abe\",\"product\":false}")"; }; landbranch '"$a"'; umbrellas "$(asked)"'
  c=$(newest)
  [ "$c" != "$a" ] && [ "$(jq -c --arg a "$a" '.cards[] | select(.id == $a) | [.card, .was]' "$(nicards)")" = "[\"$c\",[\"$a\"]]" ] \
    || fail "land-branch $a did not land as slice $a (its entry's card the new card ${c:-none}, $a in its was): $(cat "$T/$CASE/run.out") $(cat "$(nicards)")"
  [ -s "$STUB/tcid" ] && [ "$(cat "$STUB/tcid")" != "$c" ] && [ "$(jq -c --arg t "$(cat "$STUB/tcid")" '[.cards[] | select(.id == $t) | .title]' "$(nicards)")" = '["Other"]' ] \
    || fail "tcadd() at the handoff of land-branch $a took the slice card's id $c (it got '$(cat "$STUB/tcid" 2>&1)'): $(cat "$(nicards)")"
  [ "$(jq -c '[.title, .body]' "$STUB/issue")" = "$(jq -c --arg a "$a" '.cards[] | select(.id == $a) | [.title, .body]' "$(nicards)")" ] \
    || fail "land-branch $a was reviewed against $(cat "$STUB/issue" 2>&1), not slice $a's own issue: $(cat "$(nicards)")"
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 7 ] && [ "$(loop control | jq -c '.held | index(7)')" = null ] \
    || fail "the umbrella #7 was not closed and released once slice $a landed by land-branch and $b landed: $(cat "$STUB/closed" 2>&1) $(loop control | jq -c .held) $(cat "$T/$CASE/run.out")"
  # Bug: a second land-branch of a's branch, with one more commit, made a new card the slice's: a card that may block,
  # which a card that depends on slice a would wait on again. Slice a is done: it is refused.
  echo more > "$T/$CASE/lane-$a/s.txt" && git -C "$T/$CASE/lane-$a" commit -qam 'fix(tooling): more' || fail "branch $a could not take a commit"
  fx_in 'card() { append "$(line "$1" "$2" landed ok "{\"sha\":\"abf\",\"product\":false}")"; }; landbranch '"$a"
  [ "$RC" != 0 ] && grep -qF "slice $a is done already, as card $c" "$T/$CASE/run.out" && [ "$(jq -r --arg a "$a" '.cards[] | select(.id == $a) | .card' "$(nicards)")" = "$c" ] \
    || fail "a second land-branch $a, after slice $a landed as $c, was not refused, or took the slice (exit $RC): $(cat "$T/$CASE/run.out") $(cat "$(nicards)")"
}

# Bug it catches: with privacy.mode public, a branch landed as a slice of no GitHub issue took its commit message from
# the slice's title (card() put it in place of cardsubject()'s masked message), so a private term in the title landed
# and the push sent it with no privacy check. cardsubject() now makes the branch's message and masks it.
t_branchprivmsg() {
  H=/home; export XDG_CONFIG_HOME=$T/$CASE/config # the home path is put together here, so this file holds none itself
  setup '[]'; mkdir -p "$XDG_CONFIG_HOME/conveyor"; echo 'case:Zed' > "$STUB/terms"
  jq -n --arg t "$STUB/terms" '{terms: $t}' > "$XDG_CONFIG_HOME/conveyor/host.json"; tune '.privacy.mode = "public"'
  local issue; issue=$(jq -cn --arg h "$H/x" '{number: 0, title: "Slice for Zed in \($h)", body: "the slice", labels: []}')
  fx_in "cardsubject c0-0 '$issue' slice-b"
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = $'Slice for <private term> in <home path>\n\nConveyor card c0-0, branch slice-b' ] \
    || fail "cardsubject c0-0 '$issue' slice-b with privacy.mode public did not mask the slice's title in the branch's message (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Push off: slice cOff landed a commit of the branch side, which main does not hold (as after the pack's defaultBranch
# was set to a branch from before the slice landed), and slice cOn landed main's own commit. Bug caught: slicetake()
# counted any landed line done (TADONE), so land-branch of cOff was refused as done already, though umbrellas() and
# the snapshot count it as waiting. cOn, on main, is still refused. Slice cWas landed main's commit as cWas, then
# again off main as cWasB (its card now, cWas in its was). Bug caught: slicetake() read only its card's lines, so it
# took cWas again, though umbrellas() and the Board count it landed by cWas.
t_branchoffmain() {
  local h sd
  setup "[]"
  h=$(git -C "$R" rev-parse HEAD) && git -C "$R" switch -qc side && git -C "$R" commit -q --allow-empty -m 'slice' \
    && sd=$(git -C "$R" rev-parse HEAD) && git -C "$R" switch -q main || fail "the side branch's commit could not be made"
  mkdir -p "$ST/testactions" && jq -cn '{cards: [{id: "cOff", card: "cOff", title: "off", body: "Do off."}, {id: "cOn", card: "cOn", title: "on", body: "Do on."}, {id: "cWas", card: "cWasB", was: ["cWas"], title: "was", body: "Do was."}]}' > "$(nicards)"
  fx_in 'append "$(line cOff 0 picked ok "{}")"; append "$(line cOff 0 landed ok "{\"sha\":\"'"$sd"'\"}")"
    append "$(line cOn 0 picked ok "{}")"; append "$(line cOn 0 landed ok "{\"sha\":\"'"$h"'\"}")"
    append "$(line cWas 0 picked ok "{}")"; append "$(line cWas 0 landed ok "{\"sha\":\"'"$h"'\"}")"
    append "$(line cWasB 0 picked ok "{}")"; append "$(line cWasB 0 landed ok "{\"sha\":\"'"$sd"'\"}")"
    slicetake cOn cNewOn; echo "on $?"; slicetake cOff cNewOff; echo "off $?"; slicetake cWas cNewWas; echo "was $?"'
  grep -qx 'on 1' "$T/$CASE/run.out" && grep -qF 'slice cOn is done already, as card cOn' "$T/$CASE/run.out" \
    || fail "slicetake cOn cNewOn did not refuse slice cOn, whose landed commit $h main holds: $(cat "$T/$CASE/run.out")"
  grep -qx 'was 1' "$T/$CASE/run.out" && grep -qF 'slice cWas is done already, as card cWas' "$T/$CASE/run.out" \
    || fail "slicetake cWas cNewWas did not refuse slice cWas, whose earlier card cWas landed $h, which main holds: $(cat "$T/$CASE/run.out")"
  grep -qx 'off 0' "$T/$CASE/run.out" && [ "$(jq -c '[.cards[] | [.id, .card, .was]]' "$(nicards)")" = '[["cOff","cNewOff",["cOff"]],["cOn","cOn",null],["cWas","cWasB",["cWas"]]]' ] \
    || fail "slicetake cOff cNewOff refused slice cOff, whose landed commit $sd main does not hold, or did not give it the new card: $(cat "$T/$CASE/run.out") $(cat "$(nicards)")"
}
