#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the retry of a blocked card, which takes up its kept work (landing conflicts and ports are in port.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
# shellcheck disable=SC2034 # the closure tool reads this line; the cases here do not use SRC
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A last review's NO-GO whose landing conflicted, and conflicted again after its port (t_portfix runs such a card):
# blocked, its follow-ups withdrawn. Retried, its kept patch does not apply to main as it is now. Bug: the card was
# built from nothing. Bug: its loop had finished (a last NO-GO, follow-ups filed) and only the landing conflict stopped
# it, yet the port went through a fresh loop of up to three reviews and two fixes. The next card ports the kept patch
# (resumeplan(): port) with the kept review's verdict (fin), so one review of the port alone follows; after a GO on
# that review, its landing files the earlier loop's findings again (afterreview(): last, earlier). Bug: its filed
# line said the loop ended on the port's GO, not on the blocked card's review 3 whose findings it files (finend,
# carried as earlyend, which the filed line takes). Its brief (carried()) holds the blocked card's last findings and
# the withdrawn follow-ups' findings: GitHub also holds follow-ups withdrawn for #8 that no .withdrawn file here names
# (#55, closed before the file existed), one this card's file names too, one of another issue (#57) and one a card
# of its own landed (#56).
t_resumeport() {
  local e='{"stop":"max-reviews","pass":3,"rounds":0}'
  resumesetup 8
  portkept 8 c1-8 'rebase onto main conflicts: CONFLICT (content): Merge conflict in a.txt' 'echo two >> a.txt' "$PORTNOGO" \
    "$(kline c1-8 8 review NO-GO "$e"; kline c1-8 8 filed ok "$e"; kline c1-8 8 rebase ok; kline c1-8 8 review GO '{"stop":"go","pass":1,"rounds":0}')"
  printf '%s\n' '#100101 [P2] a.txt:1 wrong word' '#100102 [P2] b.txt:22 no mark here' '#100103 [P2] c.txt:3 a nit' > "$K/c1-8.withdrawn"
  echo ONE > "$R/a.txt" && git -C "$R" commit -qam other || fail "main could not move"
  fu() { jq -cn --argjson n "$1" --arg p "$2" --arg f "$3" '{number:$n,title:$f,body:"Follow-up to #\($p) (Conveyor card c1-\($p)). Its last review said NO-GO.\n\nFinding: \($f)\nWhere: x\nFollow-up depth: 1"}'; }
  jq -cs . <(fu 57 80 '[P1] other.txt:1 of another issue') <(fu 56 8 '[P1] done.txt:2 landed since') <(fu 100102 8 'b.txt:22 no mark here') <(fu 55 8 '[P1] old.txt:9 an old finding') > "$STUB/closed-issues.json"
  landed 56 >> "$ST/cards.jsonl"
  loop retry 8 >/dev/null || fail "retry of #8 exited non-zero"
  # After resumeplan, as card() goes on: its brief's carried findings, and what follows a GO on the port's one review.
  resumed 8 'carried 8 "$wt" > "$T/$CASE/carried" || exit 3
    res=GO finrev=$(<"$wt.review") pass=1 rebased="" tfix="" lfix="" privfix="" p1fix="" earlier="" earlyend=""; afterreview
    jq -cn --arg a "$after" --arg s "$stop" --argjson e "${earlyend:-null}" --arg r "$earlier" "{after: \$a, stop: \$s, earlyend: \$e, earlier: (\$r | test(\"c.txt:3 a nit\"))}" > "$T/$CASE/after"
    printf "%s\n" "--- kept" "+++ ported" "@@ -1,2 +1,2 @@" "-+ONE" "++TWO" " +two" > "$wt.port" && cp "$wt.port" "$T/$CASE/port.fixture" || exit 3
    printf -v ins "%s\n\n%s\n%s" "$REVIEW" "$PORTREVIEW" "The difference is the file $wt.port."
    noshell "$wt" "the brief" "$ins" > "$T/$CASE/portreview" && cp "$wt.rv/port.diff" "$T/$CASE/port.diff" || exit 3'
  # Bug: the port's one review was not scoped to the port, or not handed the kept patch against the ported change, or
  # was handed it inline, so its prompt grew with the diff. Its prompt (noshell(), lib/review.sh) on the instructions
  # card() gives that review (REVIEW, then PORTREVIEW and the .port file's path) and a fixture .port file.
  local c=$T/$CASE/cards/c9
  grep -qx '# This review is of a port alone' "$T/$CASE/portreview" && grep -qxF "The difference is the file $c.port." "$T/$CASE/portreview" \
    && grep -qF "The difference the review of a port reads (the file $c.port) is the file $c.rv/port.diff: read it there." "$T/$CASE/portreview" \
    && cmp -s "$T/$CASE/port.fixture" "$T/$CASE/port.diff" && ! grep -qx '++TWO' "$T/$CASE/portreview" \
    || fail "the port's review is not scoped to the port, or not handed its difference from the kept patch as a file: $(tail -n 4 "$T/$CASE/portreview" 2>&1)"
  [ "$(jq -c '[.mode, .note, .fin, .finend, .staged]' <<<"$RESUMED")" = "[\"port\",\"the kept patch of card c1-8 finished its review loop and no longer applies to main: one session brings it onto main, then one review of that port alone\",\"NO-GO\",$e,[]]" ] \
    || fail "a kept patch whose finished loop no longer applies to main was not taken up as a port with one review of it alone: $RESUMED"
  [ "$(cat "$T/$CASE/after")" = "{\"after\":\"last\",\"stop\":\"go\",\"earlyend\":$e,\"earlier\":true}" ] \
    || fail "a GO on the port's review does not land with the earlier loop's last NO-GO and why that loop ended: $(cat "$T/$CASE/after")"
  grep -qx '\[P2\] c.txt:3 a nit' "$T/$CASE/carried" && grep -qx '#100102 \[P2\] b.txt:22 no mark here' "$T/$CASE/carried" && ! grep -q 'NEW CARD' "$T/$CASE/carried" \
    || fail "the port's brief lacks the last review's findings or a withdrawn follow-up's finding, or carries a NEW CARD line as a finding: $(cat "$T/$CASE/carried")"
  grep -q -- '--state closed .*--label conveyor-followup .*Follow-up to #8' "$STUB/closed-asked" && grep -qx '#55 \[P1\] old.txt:9 an old finding' "$T/$CASE/carried" \
    && [ "$(grep -c '^#100102 ' "$T/$CASE/carried")" = 1 ] && ! grep -Eq '^#(56|57) ' "$T/$CASE/carried" \
    || fail "the port's brief lacks a follow-up withdrawn before any .withdrawn file, or holds one twice, a landed one or another issue's: $(grep '^#' "$T/$CASE/carried")"
}

# A finished loop's port whose landing conflicted again (its review a GO), retried once more: its filed line still
# says why the loop whose findings it files ended. Bug: the second retry read only the NO-GO review lines of the
# card it resumed, and the first port's review was a GO, so the filed line had no stop, pass or rounds. The chain's
# lines, with no card run: card c1-8 ended its loop on review 3's max-reviews, filed and blocked on a landing
# conflict; card c2-8 ported it, its one review a GO, filed the same findings again with that loop's stop (its kept
# review is the earlier loop's last NO-GO, put back to be filed) and blocked on a second conflict.
t_resumeport2() {
  local e='{"stop":"max-reviews","pass":3,"rounds":0}' cm='rebase onto main conflicts: CONFLICT (content): Merge conflict in a.txt'
  resumesetup 8
  portkept 8 c1-8 "$cm" 'echo two >> a.txt' "$PORTNOGO" "$(kline c1-8 8 review NO-GO "$e"; kline c1-8 8 filed ok "$e")"
  echo ONE > "$R/a.txt" && git -C "$R" commit -qam other || fail "main could not move"
  portkept 8 c2-8 "$cm" 'echo two >> a.txt' "$PORTNOGO" "$(kline c2-8 8 rebase ok; kline c2-8 8 review GO '{"stop":"go","pass":1,"rounds":0}'; kline c2-8 8 filed ok "$e")"
  echo TWO > "$R/a.txt" && git -C "$R" commit -qam again || fail "main could not move"
  loop retry 8 >/dev/null || fail "retry of #8 exited non-zero"
  resumed 8
  [ "$(jq -c '[.mode, .from, .fin, .finend]' <<<"$RESUMED")" = "[\"port\",\"c2-8\",\"NO-GO\",$e]" ] \
    || fail "the port of a port that blocked again does not carry why the loop whose findings it files ended: $RESUMED"
}

# Bugs: a card blocked at the visible-change check after a last review's NO-GO lands from `retry` with its
# leftover findings filed nowhere; the card built after a retry is not told the blocked card's last findings or the
# withdrawn follow-ups' findings; a kept patch that no longer applies to main is built from nothing; a card blocked
# on a failed step is built again from nothing though its patch still applies.
# Each kind is a case of its own on a main of its own (resume, resumeport, resumestep, resumeyes), so they run side
# by side. Each starts from a blocked card as block() leaves it (portkept), with no card run.
resumesetup() { # <issue>: a fresh main with that one issue; YES, a review's visible line; steps <issue>, its lines
  setup "[$(issue "$1" 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
}
# kline <card> <issue> <step> <result> [<json added>]: a card record line as line() writes it (the records are read
# in the order of the file, not by their times).
kline() {
  jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" --arg r "$4" --argjson x "${5:-"{}"}" \
    '{card:$c,issue:$n,step:$s,time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} + $x'
}
# portkept <issue> <card> <reason> <change> [<review> [<lines>]]: card <card> of <issue> blocked with <reason> as
# block() leaves it: its picked and worktree lines, <lines> (more of its lines, kline's), and its blocked line naming
# its kept folder ($K), which holds the patch of <change> made on main as it stands (built on commit $KBASE, kept
# beside it) and <review>, its kept review.
portkept() {
  local w=$T/$CASE/kept-$2
  K=$ST/kept/$2; mkdir -p "$K" || fail "card $2's kept folder could not be made"
  git -C "$R" worktree add -q --detach "$w" && (cd "$w" && eval "$4") && git -C "$w" add -A && git -C "$w" diff --cached --binary --no-renames > "$K/$2.patch" \
    && KBASE=$(git -C "$w" rev-parse HEAD) && echo "$KBASE" > "$K/$2.base" && git -C "$R" worktree remove --force "$w" || fail "card $2's kept patch could not be made"
  [ -z "${5:-}" ] || printf '%s\n' "$5" > "$K/$2.review"
  { kline "$2" "$1" picked ok; kline "$2" "$1" worktree ok; [ -z "${6:-}" ] || printf '%s\n' "$6"
    kline "$2" "$1" blocked blocked "$(jq -cn --arg r "$3" --arg k "kept/$2" '{reason: $r, kept: $k}')"; } >> "$ST/cards.jsonl"
}
# resumed <issue> [<commands>]: how the next card of a retried <issue> takes up its kept work (resumeplan(),
# lib/card.sh), with no card run: card()'s new worktree of main ($T/$CASE/cards/c9), its issue as GitHub gives it, the rule
# "visible changes need the owner's yes" and the inherited yes as card() reads them (the moved cases' issues have
# no section naming a change, so none is held to one: heldto is empty). Its outcome, as card() acts on it, in
# $RESUMED: {rc, err, mode, note, from, fin, finend, was, pro, rounds, staged (the worktree's staged files), beside (the
# files beside the worktree, by their ending)}. <commands> run after it, in its shell (wt is that worktree).
# Used by the resume cases of kept, rerunkept, reviewback, visible and visibleinherit too (the runner loads every case
# file into one shell; .conveyor/test-links.json runs them when this file changes).
resumed() {
  # FXWT, a fix card's worktree that fx_in reads, names none here.
  FXWT=$T/$CASE/none fx_in 'cd "$R" || exit 3; n='"$1"' br="" wt=$CARDS/c9
    git worktree add -q --detach "$wt" "refs/heads/$BRANCH" || exit 3
    stdb ask issue retried "$n" >/dev/null 2>&1 || :
    issue=$(gh issue view "$n" --json number,title,body,labels,milestone) || exit 3
    vrule=on heldto="" inh=""; yesrule "" || vrule=off
    [ "$vrule" = off ] || inh=$(inherit "$issue")
    from="" fromk="" was="" mode="" note="" fin="" finend="{}" pro="[]" rounds=0 err=""
    resumeplan; rc=$?
    jq -cn --argjson rc "$rc" --arg err "$err" --arg mode "$mode" --arg note "$note" --arg from "$from" --arg fin "$fin" --argjson finend "$finend" --arg was "$was" \
      --argjson pro "$pro" --argjson rounds "$rounds" --arg staged "$(git -C "$wt" diff --cached --name-only)" --arg beside "$(cd "$CARDS" && ls -d c9.* 2>/dev/null)" \
      "{rc: \$rc, err: \$err, mode: \$mode, note: \$note, from: \$from, fin: \$fin, finend: \$finend, was: \$was, pro: \$pro, rounds: \$rounds,
        staged: (\$staged | split(\"\n\") | map(select(. != \"\"))), beside: (\$beside | split(\"\n\") | map(select(. != \"\") | ltrimstr(\"c9.\")))}" > "$T/$CASE/resumed.json" || exit 3
    '"${2:-}"
  RESUMED=$(cat "$T/$CASE/resumed.json" 2>/dev/null)
  [ "$RC" = 0 ] && [ -n "$RESUMED" ] || fail "resumeplan could not be called on #$1, or the commands after it failed: $(cat "$T/$CASE/run.out")"
}
# Three NO-GOs, the last one visible: blocked for the owner's yes, nothing filed. Approved and retried, the next
# card lands from the kept patch with no build and no review (resumeplan(): land), and the kept NO-GO is the last
# review of that landing (afterreview(): last, stop land), which files its finding as a follow-up.
t_resume() {
  resumesetup 7
  # A visible change stops only a card that touches product code: #7 and #11 change a file under web/ too.
  portkept 7 c1-7 "visible to customers or staff: needs Dana's yes: guests see a new Pay button" 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' \
    "$(printf '%s\n' '[P2] a.txt:31 wrong word' "$YES" 'VERDICT: NO-GO')"
  # The issue as the kept review read it, kept beside the patch when the card stopped for the yes (visgate()).
  issue 7 2026-01-01 | jq -c '{body}' > "$K/c1-7.body"
  issue 7 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-11"]' > "$STUB/issues.json"
  loop retry 7 | grep -q 'lands from the kept patch .*-7\.patch, with no build and no review' || fail "retry does not say the approved next card lands from the kept patch"
  # After resumeplan, what card() does on the kept review of a landing with no review (pass 0, as card() sets it).
  resumed 7 'res=$(verdict "$wt.review") finrev="" pass=0 rebased="" tfix="" lfix="" privfix="" p1fix=""; afterreview; echo "$after $stop" > "$T/$CASE/after"'
  [ "$(jq -c '[.mode, .note, .staged]' <<<"$RESUMED")" = '["land","landing from the kept patch of card c1-7: no build and no review",["a.txt","web/pay.ts"]]' ] \
    || fail "an approved kept patch was not taken up to land with no build and no review: $RESUMED"
  [ "$(cat "$T/$CASE/after")" = "last land" ] || fail "the kept NO-GO of a patch landed by retry is not a last review that files its finding: $(cat "$T/$CASE/after")"
}
# Bug (#1385): an approved kept patch whose kept review holds a P1 got its one fix round, but the card stayed in mode
# land, so the pass after the fix read the kept review again and blocked on its P1, with no review of the fix. After
# the fix a review session runs (the stub's review 1, a GO), and the card lands on it.
t_resumep1() {
  resumesetup 7
  portkept 7 c1-7 "visible to customers or staff: needs Dana's yes: guests see a new Pay button" 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' \
    "$(printf '%s\n' '[P1] a.txt:31 wrong word' "$YES" 'VERDICT: NO-GO')"
  issue 7 2026-01-01 | jq -c '{body}' > "$K/c1-7.body"
  issue 7 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-11"]' > "$STUB/issues.json"
  loop retry 7 | grep -q 'lands from the kept patch' || fail "retry does not say the approved next card lands from the kept patch"
  echo "$GO" > "$STUB/review.1"
  # loop: only a card's loop shows what the pass after the fix does: a review session, or the kept review read again.
  loop run >/dev/null
  [ "$(st 'select(.issue == 7 and (.step | IN("fix", "review", "landed", "blocked"))) | "\(.step) \(.result)"' | paste -sd , -)" = 'fix ok,review GO,landed ok' ] \
    && [ "$(wc -l < "$STUB/reviews" | tr -d ' ')" = 1 ] \
    || fail "the kept P1 ('[P1] a.txt:31 wrong word') was not fixed, reviewed in a session and landed on its GO: $(steps 7)"
}
# Bug (#1385): a retried card counted the reviews of its chain from before an automatic port (landconflict(),
# lib/cardland.sh, which starts pass and rounds again) as its rounds. Card c1-7: 3 reviews, its port (its rebase line
# marks it), 2 reviews (the port's own, then one of its fix), then a failed step. The retried card carries the 1
# review after the port's own alone, so its first NO-GO (a P1, review 2 of 3) gets a fix round; with the 5 counted,
# or the 2 after the port, it was its last review and landed the finding as a follow-up. A P1, as p1at2() makes one:
# from review 2 on, a NO-GO of new P2 findings alone ends the loop (loopstop(): new-p2) whatever the count. p1fix is
# set (the card's one P1 round spent), so a miscounted last review prints "last max-reviews", not the P1's own fix round.
t_resumeport3() {
  local r l=''
  resumesetup 7
  r=$(kline c1-7 7 review NO-GO); l=$(printf '%s\n' "$r" "$r" "$r" "$(kline c1-7 7 rebase ok '{"port": true}')" "$r" "$r")
  portkept 7 c1-7 'test: exit 1' 'echo two >> a.txt' "$(printf '%s\n' '[P1] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO')" "$l"
  loop retry 7 >/dev/null || fail "retry of #7 exited non-zero"
  resumed 7 'res=NO-GO rep="" finrev="" earlier="" pass=1 rebased="" tfix="" lfix="" privfix="" p1fix=1; afterreview; echo "$after $stop" > "$T/$CASE/after"'
  [ "$(jq -c '[.mode, .rounds]' <<<"$RESUMED")" = '["session",1]' ] || fail "the reviews before the port of c1-7, or the port's own review, were counted as the retried card's rounds: $RESUMED"
  [ "$(cat "$T/$CASE/after")" = "fix " ] || fail "the retried card's first NO-GO (a P1 on review 2: pass 1, 1 round carried) did not get a fix round: $(cat "$T/$CASE/after")"
}
# Card c1-7 of #7 after an automatic port (its rebase line marks it): the port's own review gave a NO-GO, its fix
# round 1 was kept, and the review after that fix was recorded with <result>; with <told>, that review left the rounds
# folder marked answered (told, cardreview()). Card c1-7 blocked and is retried; the retried card's refix (the round
# its first review is told, rereview()) is in $T/$CASE/refix.
portround() { # <result> [<told>]
  local r
  resumesetup 7
  r=$(kline c1-7 7 review NO-GO)
  portkept 7 c1-7 'review 2 ended without one clear verdict' 'echo two >> a.txt' "$(printf '%s\n' '[P2] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO')" \
    "$(printf '%s\n' "$r" "$(kline c1-7 7 rebase ok '{"port": true}')" "$r" "$(kline c1-7 7 review "$1")")"
  mkdir -p "$K/c1-7.rounds" && : > "$K/c1-7.rounds/1.diff" && echo '{"round":1,"id":"E1","line":"[P2] a.txt:1 wrong word"}' > "$K/c1-7.rounds/findings.jsonl" \
    && { [ -z "${2:-}" ] || : > "$K/c1-7.rounds/told"; } || fail "the kept fix round of c1-7 could not be made"
  loop retry 7 >/dev/null || fail "retry of #7 exited non-zero"
  resumed 7 'echo "${refix:-}" > "$T/$CASE/refix"'
}
# Bug it catches: after an automatic port, the port's own review (pass 1 there, landconflict()) gave a NO-GO and its
# fix round 1 was kept; the review after that fix ended with no verdict. resumeplan() counted the reviews only after
# the port's own, so it found no review the round followed, and the retried card's first review was not told the
# round's findings and diff (refix, rereview()).
t_resumeportrefix() {
  portround none
  [ "$(jq -c '[.mode, .rounds]' <<<"$RESUMED") $(cat "$T/$CASE/refix")" = '["session",1] 1' ] \
    || fail "the retried card's first review after the port's fix round 1 was not told that round (refix $(cat "$T/$CASE/refix")): $RESUMED"
}
# Bug it catches: a round a review with a verdict has answered (its rounds folder marked told, cardreview()) was told
# again to the retried card's first review, as if no review had read it: that review was asked about findings a NO-GO
# already answered.
t_resumetold() {
  portround NO-GO told
  [ -z "$(cat "$T/$CASE/refix")" ] || fail "the retried card's first review was told fix round $(cat "$T/$CASE/refix"), which a review with a verdict had answered: $RESUMED"
}
# Bug it catches: the second retry after a port. c1-7: the port, then both review attempts after it ended with no
# verdict, so reviewed() blocked with no review line. c2-7, its retry, carried 0 rounds, so its first NO-GO saved fix
# round 1, and its next review blocked again with no line. resumeplan() counted the record lines after the port's own
# review to find the round, found none, and the third card's first review was not told round 1's findings and diff.
t_resumeportrefix2() {
  local b
  resumesetup 7
  portkept 7 c1-7 'review 1: the review session failed' 'echo two >> a.txt' "$(printf '%s\n' '[P2] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO')" \
    "$(printf '%s\n' "$(kline c1-7 7 review NO-GO)" "$(kline c1-7 7 rebase ok '{"port": true}')")"
  loop retry 7 >/dev/null || fail "the first retry of #7 exited non-zero"
  b=$(printf '%s\n' "$(kline c2-7 7 worktree ok '{"reason": "resumed from the kept patch of card c1-7: one session, then review"}')" "$(kline c2-7 7 review NO-GO)")
  portkept 7 c2-7 'review 2: the review session failed' 'echo three >> a.txt' "$(printf '%s\n' '[P2] a.txt:2 other word' 'USER-VISIBLE: no' 'VERDICT: NO-GO')" "$b"
  # Its worktree line names the card it resumed (the chain resumeplan() reads): portkept's plain one goes.
  jq -c 'select(.card != "c2-7" or .step != "worktree" or .reason != "")' "$ST/cards.jsonl" > "$ST/cards.new" && mv -f "$ST/cards.new" "$ST/cards.jsonl" \
    || fail "the worktree line of c2-7 could not be made"
  mkdir -p "$K/c2-7.rounds" && : > "$K/c2-7.rounds/1.diff" && echo '{"round":1,"id":"E1","line":"[P2] a.txt:2 other word"}' > "$K/c2-7.rounds/findings.jsonl" \
    || fail "the kept fix round of c2-7 could not be made"
  loop retry 7 >/dev/null || fail "the second retry of #7 exited non-zero"
  resumed 7 'echo "${refix:-}" > "$T/$CASE/refix"'
  [ "$(jq -r .from <<<"$RESUMED") $(cat "$T/$CASE/refix")" = 'c2-7 1' ] \
    || fail "the third card's first review after c2-7's fix round 1, with no review line after the port, was not told that round (refix $(cat "$T/$CASE/refix")): $RESUMED"
}

# A failed step (here the review) with a patch that still applies: the next card starts from the patch, one session
# (resumeplan(): session).
# Bug (#585): retry gave back an issue while its blocked card's process was still ending. That process then wrote a
# second blocked line after its lines were moved out, and could not keep its change, the worktree already taken.
# Here the card's worktree line names a live process: retry refuses and names it, changing nothing; once the
# process has ended, retry gives the issue back and the next card starts from the kept patch.
# GitHub does not answer for the withdrawn follow-ups while that card starts: its brief says the list may be short
# (carried()).
t_resumestep() {
  local p t before kept
  resumesetup 9; portkept 9 c1-9 'review 1: the review exited 3' 'echo nine > n.txt'
  sleep 60 & p=$!; t=$(p_started "$p") # sleep: a stand-in for the blocked card's process, still ending
  jq -c --argjson p "$p" --arg t "$t" 'if .step == "worktree" then .pid = $p | .started = $t else . end' "$ST/cards.jsonl" > "$ST/cards.new" && mv "$ST/cards.new" "$ST/cards.jsonl"
  # The worktrees' folder, as the blocked card left it.
  mkdir -p "$T/$CASE/cards"; before=$(cat "$ST/cards.jsonl"; ls -A "$T/$CASE/cards"); kept=$(cd "$K" && ls -A && cat ./*)
  loop retry 9 >/dev/null 2>"$STUB/refused" && fail "retry gave #9 back while its card's process $p was alive"
  grep -q "still ending (pid $p)" "$STUB/refused" || fail "the refusal does not name the card's pid $p: $(cat "$STUB/refused")"
  [ "$(cat "$ST/cards.jsonl"; ls -A "$T/$CASE/cards")" = "$before" ] && [ ! -s "$ST/retried.jsonl" ] && [ "$(cd "$K" && ls -A && cat ./*)" = "$kept" ] \
    || fail "a refused retry changed the lines, the worktrees or the kept folder"
  kill "$p"; wait "$p" 2>/dev/null
  loop retry 9 | grep -q 'starts from the kept patch' || fail "retry of #9 did not go on once its card's process had ended"
  : > "$STUB/closed-fail"; resumed 9 'carried 9 "$wt" > "$T/$CASE/carried"'; rm "$STUB/closed-fail"
  [ "$(jq -c '[.mode, .note, .staged]' <<<"$RESUMED")" = '["session","resumed from the kept patch of card c1-9: one session, then review",["n.txt"]]' ] \
    || fail "a card blocked on a failed step did not resume from its kept patch with one session: $RESUMED"
  grep -q '^## The withdrawn follow-ups of this issue could not be read from GitHub$' "$T/$CASE/carried" \
    || fail "a brief made while GitHub did not list the withdrawn follow-ups does not say so: $(grep '^#' "$T/$CASE/carried" 2>&1)"
}

# Bug: the owner's yes with a condition ("only for admins") landed the kept patch with no build and no
# review, though nothing had held the change against the condition. The patch is reviewed, with no build first; the
# condition it does not meet is a finding, fixed and reviewed again. The card stopped for the yes after a GO.
t_resumeyes() {
  local old=c1-11
  resumesetup 11
  portkept 11 "$old" "visible to customers or staff: needs Dana's yes: guests see a new Pay button" 'echo eleven > e.txt; mkdir -p web; echo eleven > web/e.ts' \
    "$(printf '%s\n' "$YES" 'VERDICT: GO')"
  issue 11 2026-01-01 | jq -c '{body}' > "$K/$old.body"
  issue 11 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-12, only for admins"]' > "$STUB/issues.json"
  # Bug: retry said this card lands "with no build and no review", though the condition has it reviewed first.
  loop retry 11 | grep -q "reviews the kept patch .*-11\.patch against Dana's yes as the issue now gives it, with no build" || fail "retry does not say the conditionally approved kept patch is reviewed before it lands"
  resumed 11
  [ "$(jq -c '[.rc, .mode, .note, .staged]' <<<"$RESUMED")" = "[0,\"review\",\"reviewing the kept patch of card $old against the condition of Dana's yes: no build\",[\"e.txt\",\"web/e.ts\"]]" ] \
    || fail "a kept patch approved with a condition was not taken up to be reviewed against it, with no build: $RESUMED"
}

# Bug it catches: a card stopped for the owner's yes whose issue was then rewritten to ask for another change (its
# section of what customers or staff will see changed), and whose kept patch no longer applies to main, was ported:
# its one session was told to keep what that card changed, so the refused change came back. Its next card is built
# from nothing (resumeplan(), keptway()), as when the patch still applies (t_visiblerewritten).
t_resumeportrewritten() {
  resumesetup 8
  portkept 8 c1-8 "visible to customers or staff: needs Dana's yes: guests see a new Pay button" 'echo two >> a.txt' "$YES"
  jq -cn '{body: "Add (a).\n\n## What customers or staff will see\nGuests see a new Pay button."}' > "$K/c1-8.body"
  # The kept patch's STABILISED lines come with it (resumeplan()); a build from nothing must drop them, or its own
  # check would take the old patch's cause for the new change's.
  echo 'a.txt: the old cause' > "$K/c1-8.stabilised"
  issue 8 2026-01-01 | jq -c '[.body = "Do (b) instead.\n\n## What customers or staff will see\nNothing visible changes."]' > "$STUB/issues.json"
  echo ONE > "$R/a.txt" && git -C "$R" commit -qam other || fail "main could not move"
  loop retry 8 >/dev/null || fail "retry of #8 exited non-zero"
  resumed 8
  [ "$(jq -c '[.rc, .mode, .fin, .staged, .beside]' <<<"$RESUMED")" = '[0,"","",[],["review"]]' ] \
    && [ "$(jq -r .note <<<"$RESUMED")" = "the issue's section of what customers or staff will see changed since the review of the kept patch of card c1-8: built from nothing" ] \
    || fail "the kept patch of a rewritten issue that no longer applies was ported, not built from nothing: $RESUMED"
}

# Bug it catches: a card blocked on a landing conflict kept no issue body (landconflict(), lib/cardland.sh), so when
# its issue was then rewritten to ask for another change (its section of what customers or staff will see changed),
# keptway() could not compare and its next card ported the old change. The block keeps the body its review read, and
# the next card is built from nothing (resumeplan()), as t_resumeportrewritten's card that stopped for the yes is.
t_resumeconflictrewritten() {
  local k c out
  rebasesetup 9
  issue 9 2026-01-01 | jq -c '[.body = "Add (a).\n\n## What customers or staff will see\nGuests see a new Pay button."]' > "$STUB/issues.json"
  # ported=1: the card's one port is spent, so this conflict blocks it.
  conflicted 9 'ported=1; land1; go=end; landconflict; outcome'
  k=$(st 'select(.issue == 9 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); c=$(st 'select(.issue == 9 and .step == "blocked") | .card')
  [ "$(jq -r .body "$k/$c.body" 2>/dev/null)" = "$(jq -r '.[0].body' "$STUB/issues.json")" ] \
    || fail "a card blocked on a landing conflict (outcome $OUTCOME) did not keep the issue body its review read (kept: $k)"
  # Bug: the block comment and retry promised the kept patch, which a rewrite of the visible section voids; then the
  # comment promised a build from nothing where the patch applies again (t_keptconflictapplies: built on).
  grep -q "If the issue's section of what customers or staff will see changes first, and the patch no longer applies to main, the next card is built from nothing\.$" "$STUB/comments" \
    || fail "the landing-conflict block comment does not say a rewrite of the visible section builds from nothing only when the patch no longer applies to main: $(tail -n 3 "$STUB/comments")"
  issue 9 2026-01-01 | jq -c '[.body = "Do (b) instead.\n\n## What customers or staff will see\nNothing visible changes."]' > "$STUB/issues.json"
  out=$(loop retry 9) || fail "retry of #9 exited non-zero"
  grep -q "only if it now applies to main; if not, it is built from nothing: the issue's section" <<<"$out" \
    || fail "retry of #9 (landing conflict, visible section rewritten) promised the kept patch: $out"
  resumed 9
  [ "$(jq -c '[.rc, .mode, .fin, .staged]' <<<"$RESUMED")" = '[0,"","",[]]' ] \
    && [ "$(jq -r .note <<<"$RESUMED")" = "the issue's section of what customers or staff will see changed since the review of the kept patch of card $c: built from nothing" ] \
    || fail "the kept patch of a landing conflict whose issue was rewritten was ported, not built from nothing: $RESUMED"
  # Bug: was kept the old patch's conflict, so landconflict() (lib/cardland.sh) took this new build's own landing
  # conflict for the conflict of a port and blocked it with no port.
  [ "$(jq -r .was <<<"$RESUMED")" = "" ] || fail "a card built from nothing kept the discarded patch's block reason, which skips its own port: $RESUMED"
}
