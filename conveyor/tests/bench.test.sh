#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the benchmark's phase-0 scripts (bench/): the stage map, the byte check of a replayed review, the
# replay through reviewed() and the simulation of check rules. Fixture CLIs (the test stubs) stand in for the real ones.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a file two stages use (a session.sh helper of build and review, the card rules) is given to one stage only, so a
# stage check replays too few stages; a word that only looks like a call (a function name in a message, a local
# variable, a jq argument, a case pattern, a regex in a test) gives a file to a stage that never runs it, so every
# check widens to every stage; a function the engine runs through another (apitries ... claudereview) is not followed;
# a stage whose entry is gone is left out of the map without a word.
t_benchstagemap() {
  local e=$T/$CASE/engine; mkdir -p "$e/lib" "$e/rules"
  echo rules > "$e/rules/card-core.md"
  cat > "$e/lib/prompts.sh" <<'EOF'
RULES=${CONVEYOR_CARD_RULES:-$HERE/rules/card-core.md}
REVIEWT='Review the change, then push your verdict.'
FIX='# Reviewer findings'
cardrules() { cat "$RULES"; }
brief() { # <card>
  echo "# Card $1"
}
EOF
  cat > "$e/lib/session.sh" <<'EOF'
# A session: build, fix or rebase.
apitries() { # <worktree> <step> <command ...>
  local t
  t=$("${@:3}") || return 1
}
said() { echo "$1"; } # what both build and review print
session() { apitries "$1" build session1 "$@"; }
session1() {
  said "the build ended"
}
EOF
  cat > "$e/lib/review.sh" <<'EOF'
reviewed() { # <worktree> <brief>
  local land=1 push
  apitries "$1" review claudereview "$@"; echo "push failed: $land" # a word in a message: no call of push
  [[ $1 =~ ^(land|tests)$ ]] || jq -n --arg tests x '.'
  case $2 in
    push) said "a case pattern" ;;
  esac
}
claudereview() { said "$(cat "$STE80")"; }
STE80=$HERE/rules/ste80.md
EOF
  printf '%s\n' 'tests() { echo ran; }' > "$e/lib/testrun.sh"
  printf '%s\n' 'land() { said landed; }' 'rereview() { reviewed "$@"; }' > "$e/lib/claim.sh"
  printf '%s\n' 'push() { echo pushed; }' > "$e/lib/push.sh"
  local got want
  got=$("$SRC/bench/stagemap.sh" "$e") || fail "the stage map failed on the engine fixture"
  want=$(printf '%s\t%s\n' lib/claim.sh fix,land lib/prompts.sh build,review,fix lib/push.sh push lib/review.sh review,fix \
    lib/session.sh build,review,fix,land lib/testrun.sh test rules/card-core.md build,review,fix rules/ste80.md review,fix)
  [ "$got" = "$want" ] || fail "the stage map is not the fixture's: $(diff <(echo "$want") <(echo "$got"))"
  got=$("$SRC/bench/stagemap.sh" --shared "$e") || fail "the shared stage map failed"
  [ "$got" = "$(grep -Ev '^lib/(push|testrun)\.sh' <<<"$want")" ] || fail "--shared does not list exactly the files of two or more stages: $got"
  rm "$e/lib/testrun.sh"
  got=$("$SRC/bench/stagemap.sh" "$e" 2>&1) && fail "a map with no test stage passed: $got"
  [[ $got == *"the stage test names tests, which no engine file defines"* ]] || fail "a map with a stage gone does not say which: $got"
}

# Bugs: a replay whose staged change differs only in whitespace passes, as a patch id reads it; a part production had
# and the replay lacks (the trailers, a context file) passes unseen; a review read beside another writing method
# (rules/ste80.md, which the prompt names by path) compares exact; a folder with no prompt compares equal to another
# with none; the snap writes into the worktree it reads.
t_benchpromptcheck() {
  local d=$T/$CASE wt=$T/$CASE/wt p=$SRC/bench/promptcheck.sh e1=$T/$CASE/e1 e2=$T/$CASE/e2 out
  mkdir -p "$e1/rules" "$e2/rules" && echo 'Write short lines.' > "$e1/rules/ste80.md" && echo 'Write short lines!' > "$e2/rules/ste80.md"
  mkdir -p "$d" && git init -q "$wt" && printf 'a\nb\n' > "$wt/f" && echo rules > "$wt/AGENTS.md" && git -C "$wt" add -A && git -C "$wt" commit -qm base
  printf 'a\nb  c\n' > "$wt/f" && git -C "$wt" add f
  echo 'Done-when: D1 met' > "$d/prompt"; echo 'Bug-Proof: x' > "$wt.trailers"
  local before; before=$(git -C "$wt" status --porcelain=v2 && sha1sum "$wt/.git/index")
  "$p" snap "$e1" "$wt" "$d/prompt" "$d/prod" || fail "snap failed"
  [ "$(git -C "$wt" status --porcelain=v2 && sha1sum "$wt/.git/index")" = "$before" ] || fail "snap changed the worktree or its index"
  [ "$(<"$d/prod/head")" = "$(git -C "$wt" rev-parse HEAD)" ] && cmp -s "$d/prod/trailers" "$wt.trailers" && cmp -s "$d/prod/context/AGENTS.md" "$wt/AGENTS.md" \
    && cmp -s "$d/prod/context/ste80.md" "$e1/rules/ste80.md" || fail "snap did not keep HEAD, the trailers, AGENTS.md and the writing method"
  "$p" snap "$e1" "$wt" "$d/prompt" "$d/same" && out=$("$p" compare "$d/prod" "$d/same") && [ "$out" = exact ] || fail "two snaps of one review are not exact: $out"
  # The same change at another path: the prompt names <worktree>.rv/staged.diff, so it is another review.
  cp -a "$wt" "$d/wt2" && cp "$wt.trailers" "$d/wt2.trailers" && "$p" snap "$e1" "$d/wt2" "$d/prompt" "$d/moved" || fail "the snap of the moved worktree failed"
  out=$("$p" compare "$d/prod" "$d/moved") && fail "a replay at another worktree path passed: $out"
  [[ $out == "differs: worktree"* && $out != *$'\n'* ]] || fail "compare does not name the worktree path alone: $out"
  # Only the engine's writing method differs: the replay is not the review production ran.
  "$p" snap "$e2" "$wt" "$d/prompt" "$d/ste" || fail "the snap on the second engine failed"
  out=$("$p" compare "$d/prod" "$d/ste") && fail "a replay that read another writing method passed: $out"
  [[ $out == "differs: context/ste80.md"* ]] || fail "compare does not name the writing method that differs: $out"
  out=$("$p" snap "$d" "$wt" "$d/prompt" "$d/none" 2>&1) && fail "a snap with no writing method in the engine passed: $out"
  # The replay's change has one space less (the same patch id, other bytes) and its prompt one space more.
  printf 'a\nb c\n' > "$wt/f" && git -C "$wt" add f && rm "$wt.trailers"; echo 'Done-when: D1 met ' > "$d/prompt2"
  "$p" snap "$e1" "$wt" "$d/prompt2" "$d/replay" || fail "the replay's snap failed"
  [ "$(git patch-id --stable < "$d/prod/staged.diff" | cut -d' ' -f1)" = "$(git patch-id --stable < "$d/replay/staged.diff" | cut -d' ' -f1)" ] \
    || fail "the fixture's two changes do not share a patch id, so the case proves nothing about one"
  out=$("$p" compare "$d/prod" "$d/replay") && fail "a replay with other bytes and no trailers passed: $out"
  [[ $out == *"differs: staged.diff"* && $out == *"differs: prompt"* && $out == *"only in production: trailers"* ]] || fail "compare does not name the parts that differ: $out"
  rm "$d/same/prompt" "$d/replay/prompt"
  out=$("$p" compare "$d/same" "$d/replay" 2>&1); [ $? = 2 ] && [[ $out == *"has no prompt"* ]] || fail "two folders with no prompt did not fail as no snap: $out"
}

# Bugs: the replay builds its prompt by hand, not through the engine version's reviewed(), so two engine versions that
# would send other prompts compare exact; the retry of a review that ended with no verdict is not counted as a
# session; the replay's change is not the recorded bytes; it writes outside its out folder, or runs where the
# recorded cards folder already exists (beside live cards).
t_benchreplay() {
  setup '[]'
  local d=$T/$CASE in=$T/$CASE/in at=$T/$CASE/at out
  # The recorded review: card c7's change (a.txt, a trailing space) and trailers, its brief, at the paths it ran at.
  mkdir -p "$in" && git -C "$R" rev-parse HEAD > "$in/head" && printf '%s\n' "$at/engine/conveyor" > "$in/engine" && printf '%s\n' "$at/cards/c7" > "$in/worktree"
  git -C "$R" worktree add -q --detach "$d/w" && echo 'two ' >> "$d/w/a.txt" && git -C "$d/w" add a.txt && git -C "$d/w" diff --cached --binary --no-renames HEAD > "$in/staged.diff"
  printf '# Issue: body of the issue\n' > "$in/brief"; echo 'Bug-Proof: x' > "$in/trailers"
  # Each replay's reviewer first ends with no verdict, then answers GO: two sessions.
  rp() { rm -f "$STUB/reviews"; echo 'I looked at it.' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"; "$SRC/bench/replay.sh" "$1" "$R" "$in" "$d/$2"; }
  out=$(rp "$SRC" a) || fail "the replay failed: $out; $(cat "$d/a/reviewed.out" 2>/dev/null)"
  [ "$(jq -c '[.sessions, .verdict]' <<<"$out")" = '[2,"GO"]' ] || fail "the replay did not count both sessions or read the GO: $out"
  [ ! -e "$at" ] || fail "the replay left its engine or cards folder: $(ls -R "$at" | head)"
  cmp -s "$in/staged.diff" "$d/a/snap/staged.diff" && cmp -s "$in/trailers" "$d/a/snap/trailers" || fail "the replayed change or trailers are not the recorded bytes"
  [ "$(<"$d/a/snap/worktree")" = "$at/cards/c7" ] && [ "$(tail -n 1 "$d/a/prompt.1")" = '# Issue: body of the issue' ] && cmp -s "$d/a/prompt.1" "$d/a/prompt.2" \
    || fail "the replay's reviewer did not read the brief at the recorded worktree, or its retry read another prompt"
  out=$(rp "$SRC" b) && out=$("$SRC/bench/promptcheck.sh" compare "$d/a/snap" "$d/b/snap") && [ "$out" = exact ] || fail "two replays on one engine are not exact: $out"
  # The second engine version: one byte more in the review's instructions.
  mkdir -p "$d/v2" && cp -a "$SRC/." "$d/v2/" && sed -i.bak 's/^REVIEWT=\$REVIEWHEAD'"'"' /REVIEWT=$REVIEWHEAD'"'"'  /' "$d/v2/lib/prompts.sh" \
    && ! cmp -s "$SRC/lib/prompts.sh" "$d/v2/lib/prompts.sh" || fail "the second engine version could not be made"
  rp "$d/v2" c > /dev/null || fail "the replay on the second engine failed: $(cat "$d/c/reviewed.out" 2>/dev/null)"
  out=$("$SRC/bench/promptcheck.sh" compare "$d/a/snap" "$d/c/snap") && fail "two engine versions with other review prompts compared exact"
  [[ $out == "differs: prompt"* && $out != *$'\n'* ]] || fail "the replays of two engine versions differ in more than the prompt: $out"
  mkdir -p "$at/cards"; out=$(rp "$SRC" e 2>&1) && fail "a replay ran where the cards folder already exists: $out"
  [ -d "$at/cards" ] && [ ! -e "$d/e" ] || fail "a refused replay removed the cards folder it found, or wrote its out folder"
}

# Bugs: a case that passed 5 times in 5 is taken to never fail, so no rule ever confirms a false drop; the power,
# false-confirm rate or suspect count is not that of the rule (checked against the values worked out by hand for
# these rates); a retry (a call of 2 sessions) or a confirm run is left out of the sessions per check; a call with a
# field missing is read as a pass.
t_benchsimulate() {
  local f=$T/$CASE/calls.jsonl c r out
  mkdir -p "$T/$CASE"
  # 5 cases, 5 passing runs each, so each rate is 6/7; one call took 2 sessions (1.04 a call); the login's share
  # rises 0.5 a call.
  for c in a b c d e; do for r in 1 2 3 4 5; do
    printf '{"case":"%s","pass":true,"tokens":1000,"seconds":10,"sessions":%d,"login":"one","shareBefore":%d,"shareAfter":%d.5}\n' "$c" "$([ "$c$r" = a1 ] && echo 2 || echo 1)" "$r" "$r"
  done; done > "$f"
  out=$("$SRC/bench/simulate.sh" "$f" proposal:1:0:1 three:3:1:2) || fail "the simulation failed: $out"
  # By hand, q = 6/7: proposal: power 0.9 * 0.7 * 0.7 = 0.441; one case confirmed q(1-q)^2 = 0.0175, so any of 5
  # 0.0846; suspects 5q(1-q) = 0.612; runs 10 + 0.612. three: power 0.9^3 * 0.7^3 = 0.250; one case
  # q^3(1-q)^3 = 0.00184, any of 5 0.0092; suspects 5q^3(1-q) = 0.4497; runs 20 + 2 * 0.4497.
  jq -e 'def near(a; b; e): (a - b | fabs) <= e; .rules as [$p, $t]
    | near($p.power; 0.441; 0.02) and near($p.falseConfirm; 0.0846; 0.01) and near($p.suspects; 0.612; 0.03) and near($p.sessions; 10.612 * 1.04; 0.1)
      and near($t.power; 0.250; 0.02) and near($t.falseConfirm; 0.0092; 0.004) and near($t.suspects; 0.4497; 0.03) and near($t.sessions; 20.9 * 1.04; 0.1)
      and near($p.seconds; 106.1; 1) and .figures.shares == [{login: "one", calls: 25, sharePerCall: 0.5}]' <<<"$out" >/dev/null \
    || fail "the rules' figures are not those worked out by hand: $(jq -c .rules <<<"$out")"
  sed '3s/"pass":true,//' "$f" > "$f.bad"
  out=$("$SRC/bench/simulate.sh" "$f.bad" proposal:1:0:1 2>&1) && fail "a call with no pass field was read: $out"
  [[ $out == *"a call lacks case, pass"* ]] || fail "a call with no pass field was not refused as one: $out"
}

# The drift watch's fixture records: engine commit A (written first) ran 5 ended cards, a1 to a4 landed (10 minutes,
# 1200 tokens, 1 review, waited 60 s; a4's landed line has no waitSec) and a5 blocked (30 minutes, 1800 tokens, 2
# reviews, 1 fix, waited 360 s; its issue closed 200 minutes after it began, which does not end it again); engine
# commit B ran b1 and b2 landed (20 minutes, 3000 tokens, 2 reviews, 1 fix, waited 300 s) and b3, still open, which
# does not count.
DRIFTA=aaaaaaaa11111111111111111111111111111111 DRIFTB=bbbbbbbb22222222222222222222222222222222
driftrecs() {
  local c
  dc() { # <card> <engine> <first minute> <end step> <minutes> <reviews> <fixes> <claude tokens> [waitSec]
    jq -nc --arg c "$1" --arg e "$2" --argjson m "$3" --arg end "$4" --argjson d "$5" --argjson r "$6" --argjson f "$7" --argjson k "$8" --argjson w "${9:-null}" '
      def t($x): 1794787200 + ($m + $x) * 60 | todate; def l($s; $x): {card: $c, issue: 1, step: $s, time: t($x), tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""};
      l("picked"; 0), (l("worktree"; 0) + {engine: $e}), (l("build"; 1) | .tokens.claude = $k),
      (range($r) | l("review"; 2) | .tokens.codex = 100), (range($f) | l("fix"; 3) | .tokens.claude = 400),
      if $end == "" then empty else l($end; $d) + (if $end == "landed" then {sha: "0123abcd", product: true} else {} end)
        + (if $w == null then {} else {waitSec: $w} end) end'
  }
  for c in 1 2 3; do dc "a$c" "$DRIFTA" "$c" landed 10 1 0 1100 60; done
  dc a4 "$DRIFTA" 4 landed 10 1 0 1100
  dc a5 "$DRIFTA" 5 blocked 30 2 1 1200 360
  jq -nc '{card: "a5", issue: 1, step: "closed", time: (1794787200 + 205 * 60 | todate), tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}'
  dc b1 "$DRIFTB" 100 landed 20 2 1 2400 300; dc b2 "$DRIFTB" 101 landed 20 2 1 2400 300; dc b3 "$DRIFTB" 102 '' 0 1 0 5000
}
# Bugs: a card is counted on the wrong engine commit, or before it ended; a mean takes in a card it should not (reviews
# to land a blocked card's, minutes waited a card with no waitSec: A's would be 1.8, not 2.3); a group of 2 cards is
# shown as if it meant something, or the group of 5 is called too small; an engine commit with nothing before it is
# compared with nothing; a blocked card whose issue is closed later counts as closed, its minutes to the close (a5's
# would be 200); a blocked card's wait is left out (A's would be 1); an engine commit whose cards all still run (C) is skipped, so the latest
# change is compared as B against A, and `drift.sh <C>` is refused; the table needs column(1), which setup does not
# install (a stub that fails stands in for a machine without it).
t_benchdrift() {
  local f=$T/$CASE/recs.jsonl out
  mkdir -p "$T/$CASE/bin" && driftrecs > "$f"
  printf '#!/bin/sh\necho "column: command not found" >&2; exit 127\n' > "$T/$CASE/bin/column" && chmod +x "$T/$CASE/bin/column"
  out=$(PATH=$T/$CASE/bin:$PATH "$SRC/bench/drift.sh" "$f") || fail "the drift watch failed: $out"
  [ "$out" = "Figure                 before aaaaaaaa  after bbbbbbbb
Cards                  5                2
Landed                 4                2
Blocked                1                0
Tokens a card          1320             3000
Minutes a card         14               20
Reviews to land        1                2
Fix rounds a card      0.2              1
Minutes waited a card  2.3              5
The after group holds 2 cards: too small to mean anything (fewer than 5 cards)." ] || fail "the drift table is not the expected one: $out"
  [ "$("$SRC/bench/drift.sh" --json "$f" bbbbbbbb | jq -c '[.before.engine, .after.engine, .small]')" = "[\"$DRIFTA\",\"$DRIFTB\",[\"after\"]]" ] \
    || fail "the drift watch of engine commit B is not A against B: $("$SRC/bench/drift.sh" --json "$f" bbbbbbbb)"
  out=$("$SRC/bench/drift.sh" "$f" aaaaaaaa 2>&1) && fail "engine commit A, the first, was compared: $out"
  [ "$out" = "drift: no card ran on an engine commit before aaaaaaaa" ] || fail "the first engine commit was not refused as one: $out"
  # Engine commit C: its one card still runs. It is the latest change, compared with B, its group empty.
  jq -nc '{card: "c1", issue: 3, step: "worktree", time: (1794787200 + 300 * 60 | todate), tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: "", engine: "cccccccc33333333333333333333333333333333"}' >> "$f"
  for out in "$("$SRC/bench/drift.sh" --json "$f" 2>&1)" "$("$SRC/bench/drift.sh" --json "$f" cccc 2>&1)"; do
    [ "$(jq -c '[.before.engine[:8], .before.cards, .after.engine[:8], .after.cards, .small]' <<<"$out" 2>/dev/null)" = '["bbbbbbbb",2,"cccccccc",0,["before","after"]]' ] \
      || fail "engine commit C, whose card still runs, was not compared with B: $out"
  done
}
# Bugs: `conveyor.sh bench drift` does not read the retried file (a5's lines are there, as `retry` moved them); the
# snapshot does not carry the latest drift watch, or keeps a stale one once the records change.
t_benchdriftsnap() {
  setup '[]'
  local out
  driftrecs | grep -v '"card":"a5"' > "$ST/cards.jsonl"; driftrecs | grep '"card":"a5"' > "$ST/retried.jsonl"
  recok "$ST/cards.jsonl" "the drift fixture"
  out=$(loop bench drift) || fail "bench drift failed: $out"
  [ "$out" = "$("$SRC/bench/drift.sh" <(driftrecs))" ] || fail "bench drift did not compare the records and the retried file: $out"
  [ "$(loop snapshot --fresh | jq -c '.drift | [.before.cards, .after.cards, .after.engine]')" = "[5,2,\"$DRIFTB\"]" ] || fail "the snapshot has no drift watch of the records: $(loop snapshot --fresh | jq -c .drift)"
  jq -c '.card = "b4" | .issue = 2' <(grep '"card":"b1"' "$ST/cards.jsonl") >> "$ST/cards.jsonl"
  [ "$(loop snapshot --fresh | jq -c .drift.after.cards)" = 3 ] || fail "the snapshot kept the drift watch of the records before the change: $(loop snapshot --fresh | jq -c .drift)"
  # A card starts on a new engine commit (only its worktree line): the snapshot's drift is that commit against B.
  jq -c '.card = "c1" | .issue = 3 | .engine = "cccccccc33333333333333333333333333333333" | .time = "2026-11-17T00:00:00Z"' <(grep '"card":"b1","issue":1,"step":"worktree"' "$ST/cards.jsonl") >> "$ST/cards.jsonl"
  [ "$(loop snapshot --fresh | jq -c '.drift | [.before.engine[:8], .after.engine[:8], .after.cards]')" = '["bbbbbbbb","cccccccc",0]' ] \
    || fail "the snapshot kept the drift watch from before a card started on a new engine commit: $(loop snapshot --fresh | jq -c .drift)"
}
# Bugs: a blocked line had no waitSec, so the drift watch had no wait for a blocked card; block() outside card() (the
# loop blocking a card whose process ended) wrote a wait it did not know. In card(), waitsec and mainsec are its waits.
t_blockwaitsec() {
  setup "[$(issue 5 2026-01-01)]"
  local c=c20260101T000000-x-5 out
  # shellcheck disable=SC2034 # waitsec and mainsec are read by block(), as card()'s locals are
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards c; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names \
    && incard() { local waitsec=90 mainsec=30; block "$c" 5 "$CARDS/$c" "build: it failed"; } && incard \
    && block "$c-2" 5 "$CARDS/$c-2" "build: it failed" ) 2>&1) || fail "block() failed: $out"
  [ "$(st 'select(.step == "blocked") | [.card, .waitSec] | tojson' | tr '\n' ' ')" = "[\"$c\",120] [\"$c-2\",null] " ] \
    || fail "the blocked lines do not carry the card's waits, or one outside card() carries one: $(st 'select(.step == "blocked")')"
}
