#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: landing conflicts, ports and retries (kept work is in kept.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# A line of a build stub: the session that ports a card after its landing conflict moves main's a.txt again, so the
# card's landing conflicts once more and it blocks for the owner (a case that goes on to `retry` it).
AGAIN='if grep -q "^# Landing conflict" "$STUB/brief"; then echo TWO > "$R/a.txt"; git -C "$R" commit -qam again; fi'
# NOGO3 with each finding a P2 (its P0, and the line with no level, which counts as a P1): a last NO-GO that lands with its follow-ups filed (one with a P0 or a P1 does not land).
PORTNOGO=${NOGO3/\[P0\]/[P2]}; PORTNOGO=${PORTNOGO/$'\n'b.txt:22/$'\n'[P2] b.txt:22}
# NOGO with its P1 made a P2, for the same reason.
export PORTNOGO2=${NOGO/\[P1\]/[P2]}

# Bugs: a card that passed its review is thrown away when another change landed on its lines first; the
# rebuild starts from the card's stale tree; its result lands unreviewed, or over the other change; a card is rebuilt
# and ported more than once; a card with no conflict runs an extra session. Each kind is a case of its own on a main of
# its own (rebase, rebasetwice, rebaseempty), so they run side by side; a card with no conflict is keptunread's card
# built from nothing. What the rebuild is handed, and the review after it, are rebasebig's, with no card run; so are
# rebasetwice's and rebaseempty's, which call landconflict() (lib/cardland.sh) on a conflict made by hand (conflicted).
# rebasesetup <issue>: a fresh main with that one issue, every review a GO; the build adds a line, and its rebuild
# after a landing conflict ($STUB/rebuild) keeps what it was handed.
rebasesetup() {
  setup "[$(issue "$1" 2026-01-01)]"; for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  # The build adds a line; meanwhile main changes the line beside it. The rebuild holds both.
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Landing conflict' "$STUB/brief"; then cat a.txt > "$STUB/started-from"; eval "$(cat "$STUB/rebuild")"
else echo two >> a.txt; fi
EOF
}
# conflicted <issue> <commands>: card c7 of <issue> as card() holds it when land() (lib/claim.sh) says its change no
# longer applies to main, with no card run: its worktree ($FXWT, fx_wt) on main's earlier commit with the build's line
# two staged in a.txt, main's a.txt then changed to ONE, and card()'s locals after a GO that let it land. <commands>
# run in that shell: land1 is land()'s answer (it writes <worktree>.patch from the staged change, t the conflict), and
# outcome adds what card() acts on after landconflict() (go, and the rebased, ported, parsecheck, kept and pass it
# sets) to $OUTCOME, one JSON line a call.
conflicted() {
  fx_wt 'echo two >> a.txt' b.txt b
  echo ONE > "$R/a.txt"; git -C "$R" commit -qam other || fail "main could not be moved"
  fx_in 'cd "$R" || exit 3; n='"$1"' c=c7 br="" wt=$CARDS/c7
    issue=$(gh issue view "$n" --json number,title,body,labels,milestone) || exit 3
    sprompt="the card prompt"
    was="" res=GO ended="{}" rebased="" ported="" ups="" dec="" left="" tfix="" caught="" pass=1 rounds=0 docs="" docpass="" kept="" parsecheck="" fin="" finend="{}" kp="" why="" old="" err=""
    land1() { git -C "$wt" add -A && git -C "$wt" diff --cached --binary --no-renames > "$wt.patch"; t="rebase onto main conflicts: CONFLICT (content): Merge conflict in a.txt"; }
    outcome() { jq -cn --arg go "$go" --arg r "$rebased" --arg p "$ported" --arg pc "$parsecheck" --arg k "$kept" --argjson pass "$pass" \
      "{go: \$go, rebased: \$r, ported: \$p, parsecheck: \$pc, kept: \$k, pass: \$pass}" >> "$T/$CASE/outcome"; }
    '"$2"
  OUTCOME=$(cat "$T/$CASE/outcome" 2>/dev/null)
  [ "$RC" = 0 ] || fail "landconflict could not be called on #$1, or the commands after it failed (exit $RC): $(cat "$T/$CASE/run.out")"
}
t_rebase() {
  rebasesetup 7
  echo 'printf "ONE\ntwo\n" > a.txt' > "$STUB/rebuild"; echo 'ONE other' > "$STUB/move"
  # loop: only a whole card run shows the landing conflict, the rebuild, its review and the landing on the other commit
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start test start start rebase start review start test start landed pushed issue " ] || fail "steps of a card that conflicts at landing: $(st '"\(.step) \(.reason)"' | tr '\n' ',')"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "$(wc -l < "$STUB/sessions") sessions and $(wc -l < "$STUB/reviews") reviews, not 2 and 2"
  [ "$(cat "$STUB/started-from")" = ONE ] || fail "the rebuild did not start from main as it stands: $(cat "$STUB/started-from")"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(git -C "$R" log -1 --format=%s HEAD~1)" = other ] || fail "the card did not land on top of the other commit"
  [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "the landed tree does not hold both changes, main is dirty, or the worktree is left"
  [ "$(st 'select(.step == "rebase") | [.result, .tokens.claude, (.reason | startswith("rebase onto main conflicts: "))] | tojson')" = '["ok",35,true]' ] || fail "rebase line: $(st 'select(.step == "rebase")')"
  recok "$ST/cards.jsonl" "a card rebuilt after a landing conflict (its rebase line)"
  [ "$(loop cards | jq -c '.cards[0] | [.step, .reviews, (.steps | map(.step) | join(" "))]')" = '["landed",2,"build review test rebase review test"]' ] || fail "dashboard row: $(loop cards)"
}

# Bug: after a GO on the review of a port whose earlier loop ended on a NO-GO, a test fix and the
# GO after it landed the card with nothing filed: the earlier loop's findings were lost.
# Bugs of the card blocked here, a last review's NO-GO whose landing conflicts, and conflicts again after its port: its
# three follow-ups were not withdrawn as not planned each time, their findings kept. Of the retried card, whose kept
# patch no longer applies to main (resumeport takes it up with no card run): its port session was not told the
# patch's file and the commit it was built on, or to change nothing else (its one review's prompt is resumeport's,
# with no card run).
t_portfix() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  echo 'cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; echo two >> a.txt; '"$AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  # loop: only a whole card run shows a last review's NO-GO, a landing conflict and the retry that ports it
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q '^rebase onto main conflicts' || fail "#8 was not blocked on its landing conflict: $(steps 8)"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 100104 100105 100106 " ] && [ "$(grep -c -- '^--reason not planned --comment .*withdrawn.* #8 ' "$STUB/close-comments")" = 6 ] \
    || fail "the withdrawn follow-ups were not closed as not planned, each naming #8: $(cat "$STUB/closed" "$STUB/close-comments" 2>&1)"
  local k old s
  k=$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  [ "$(sed -n 2p "$k/$old.withdrawn")" = '#100102 [P2] b.txt:22 no mark here' ] && [ -s "$k/$old.patch" ] || fail "the withdrawn findings or the patch are not in the kept folder: $(ls "$k")"
  echo "$GO" > "$STUB/review.5"; echo "$GO" > "$STUB/review.6"
  # The third run fails, and its run again too (tests()), so the test fix starts.
  echo 'echo x >> "$STUB/tests"; case $(wc -l < "$STUB/tests") in 3|4) echo "FAIL widget.test.ts"; printf "%s\n" "== widget.test.ts" "-- FAIL widget.test.ts" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1 ;; esac' > "$STUB/test-cmd"
  s=$(($(wc -l < "$STUB/sessions") + 1))
  # The bug is after the resume, in the port's test fix, its second GO and the landing that files the earlier loop's findings.
  # loop: only the card's own steps show the port's brief, its review, test fix, second GO and landing
  loop retry 8 >/dev/null && loop run >/dev/null || fail "run of the retried #8 exited non-zero"
  [ "$(cat "$k/$old.base")" != "$(git -C "$R" rev-parse HEAD)" ] && grep -q "^# This card brings the change of blocked card $old onto main$" "$STUB/brief.$s" \
    && grep -q "The patch is the file $k/$old.patch, built on commit $(cat "$k/$old.base")\. Bring that change onto main as it is now.* resolve the conflicts" "$STUB/brief.$s" \
    && grep -q 'Change nothing else: that change finished its review loop' "$STUB/brief.$s" && ! grep -q 'from nothing\.\? *$\|Build the issue' "$STUB/brief.$s" \
    || fail "the port session of a finished loop was not told the patch and the commit it was built on, or to change nothing else: $(tail -n 6 "$STUB/brief.$s")"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test fail,fix ok,review GO,test pass,landed ok," ] \
    && [ "$(st 'select(.issue == 8 and .step == "landed") | .leftover')" = true ] \
    && [ "$(tail -n 3 "$STUB/filed" | jq -r .title | tr '\n' '|')" = '[P2] a.txt:1 wrong word|[P2] b.txt:22 no mark here|[P2] c.txt:3 a nit|' ] \
    || fail "a test fix after the port's GO lost the earlier loop's findings: $(steps 8)"
  [ "$(st 'select(.issue == 8 and .step == "filed") | .followups | length')" = 3 ] || fail "no filed line names the three follow-ups: $(steps 8)"
  recok "$ST/cards.jsonl" "a card that landed on a NO-GO (its filed line, and its landed line with leftover and followups)"
}

# Bugs: the port's landing conflicts too (its session moves main again) and something lands, or a second port runs:
# it blocks for the owner. A NO-GO on the one review of a port (a finished loop stopped only by a landing conflict)
# lands with follow-ups as if it were a last review, instead of being fixed and going round the loop as any card's.
t_port() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  echo "echo two >> a.txt; $AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  # loop: only a whole card run shows a finished loop stopped by a landing conflict, then the port's own review
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,blocked blocked," ] \
    && st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' && [ "$(wc -l < "$STUB/sessions")" = 4 ] \
    && [ "$(git -C "$R" log -1 --format=%s)" = again ] || fail "a conflict after the port did not block for the owner: $(steps 8)"
  echo "$NOGO" > "$STUB/review.5"; echo "$GO" > "$STUB/review.6"; f=$(wc -l < "$STUB/filed")
  # resumeplan only gives the port its finished loop's GO (fin); what is proved is card()'s handling of a NO-GO on that
  # one review (fixed and reviewed again, nothing filed).
  # loop: only the card's review loop shows a NO-GO on the port's one review fixed and reviewed again
  loop retry 8 >/dev/null && loop run >/dev/null || fail "run of the retried #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] \
    && [ "$(wc -l < "$STUB/filed")" = "$f" ] && [ "$(st 'select(.issue == 8 and .step == "landed") | has("leftover")')" = false ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "TWO two two " ] \
    || fail "a NO-GO on the port's review was not fixed and reviewed again before landing: $(steps 8)"
  loop check || fail "the records do not check"
}

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

# Bugs: the rebuild of a card whose diff is larger than a prompt may be fails at once with "Prompt is too long",
# and the card is blocked; or it is not handed the issue, the conflict message and the file that holds the card's
# patch. The prompt of the rebuild, and of a port (rebaseprompt(), lib/card.sh, on the card's prompt as card() makes
# it), names the patch file and the commit it was made against, and holds none of the card's diff of 3 MB.
# Bug: a NO-GO on the review after the rebuild got a fix round. That review is a last review (afterreview(),
# lib/card.sh): its NO-GO lands the card with its finding filed, where the same NO-GO with no rebuild is fixed.
t_rebasebig() {
  local cm='rebase onto main conflicts: CONFLICT (content): Merge conflict in a.txt'
  setup "[$(issue 11 2026-01-01)]"
  fx_in 'wt=$CARDS/c1-11; mkdir -p "$CARDS" && { printf "%s\n" "diff --git a/big.txt b/big.txt" "--- /dev/null" "+++ b/big.txt"; awk "BEGIN { while (i++ < 140000) print \"+a line of a large file\" }"; } > "$wt.patch" || exit 3
    issue=$(gh issue view 11 --json number,title,body,labels,milestone) && hdr=$(header on) && b=$(brief c1-11 "$issue" "$hdr") || exit 3
    p=$(cardprompt c1-11 "$hdr" "the card rules" "$b")
    rebaseprompt "$p" "$wt" "$cm" 0123abc > "$T/$CASE/rebuild" && rebaseprompt "$p" "$wt" "$cm" 0123abc port > "$T/$CASE/port" || exit 3
    printf "%s\n" "$PORTNOGO2" > "$wt.review"; res=NO-GO fin="" finrev="" finend="{}" pass=2 rounds=0 tfix="" lfix="" mode="" privfix="" p1fix=""
    for rebased in 1 ""; do afterreview; echo "$after $stop"; done > "$T/$CASE/after"'
  [ "$RC" = 0 ] || fail "the rebuild's prompt or the decision after its review could not be made (exit $RC): $(cat "$T/$CASE/run.out")"
  local f; for f in rebuild port; do
    [ "$(wc -c < "$T/$CASE/cards/c1-11.patch")" -gt 3000000 ] && [ "$(wc -c < "$T/$CASE/$f")" -lt 100000 ] && ! grep -q 'a line of a large file' "$T/$CASE/$f" \
      || fail "the $f prompt of a card with a 3 MB diff holds the patch itself, so it grows with the diff: $(wc -c < "$T/$CASE/$f") bytes"
    grep -q '^# Issue #11: title 11$' "$T/$CASE/$f" && grep -q '^# Landing conflict' "$T/$CASE/$f" \
      && [ "$(grep -A1 -x '## The conflict message' "$T/$CASE/$f" | tail -n 1)" = "$cm" ] && grep -qxF "The file $T/$CASE/cards/c1-11.patch, made against commit 0123abc." "$T/$CASE/$f" \
      || fail "the $f session is not handed the issue, the conflict message and the file that holds the card's patch with its commit: $(tail -n 8 "$T/$CASE/$f")"
  done
  grep -qx 'One review of this port alone follows: change nothing else.' "$T/$CASE/port" && ! grep -q 'One review of this port' "$T/$CASE/rebuild" \
    || fail "only the port's session is told that one review of the port alone follows: $(tail -n 8 "$T/$CASE/port")"
  [ "$(tr '\n' , < "$T/$CASE/after")" = "last rebased,fix ," ] || fail "a NO-GO on the review after the rebuild is not a last review that lands with its finding filed: $(tr '\n' , < "$T/$CASE/after")"
  # A last review's NO-GO, its three follow-ups filed, whose landing conflicts: landconflict() ports it (no rebuild)
  # and withdraws them; the port's own last NO-GO files three more, its landing conflicts again, and the card blocks
  # with those withdrawn too.
  conflicted 11 'printf "%s\n" "$PORTNOGO2" > "$wt.review"; res=NO-GO
    for u in "[100101,100102,100103]" "[100104,100105,100106]"; do ups=$u; land1; go=end; landconflict; outcome; done'
  [ "$OUTCOME" = '{"go":"next","rebased":"","ported":"1","parsecheck":"1","kept":"","pass":0}
{"go":"end","rebased":"","ported":"1","parsecheck":"1","kept":"","pass":0}' ] \
    || fail "a finished loop whose landing conflicted was not ported, then blocked when the port conflicted: $OUTCOME"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 100104 100105 100106 " ] && st 'select(.issue == 11 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' \
    || fail "the follow-ups of a conflicting landing were not withdrawn at the port and at the block after it: $(cat "$STUB/closed" 2>&1) $(st 'select(.issue == 11 and .step == "blocked")')"
}

# Bug: a card whose review loop had finished (a last NO-GO, its follow-ups filed) blocked for the owner when its
# landing met a conflict, and sat there until the owner ran `retry`. It is ported in the card with no owner action:
# one session, one review of that port alone, the tests and the landing, which files the loop's findings again; the
# Board shows the port as a step, not a block. A conflict after that port blocks for the owner (t_port).
# Bug: a card that files a last NO-GO's follow-ups had no <worktree>.ready, so its test pass was stored nowhere and it
# ran its tests again each time it came to the test step (the owner: passes are reused). Its pass is kept, keyed to
# its staged change: the port, a different change, runs its tests again; main moving on another file during the
# port's tests then fits it onto main with the same change, which reuses the port's pass and starts no run. It lands
# alone, with the earlier loop's findings filed.
t_autoport() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo two >> a.txt' > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  echo '[ "$(wc -l < "$STUB/tests")" != 2 ] || { echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm "main adds b.txt"; }' >> "$STUB/test-cmd"
  echo '[ ! -e "$PWD.port" ] || { cp "$PWD.port" "$STUB/port"; cp "$PWD.ready" "$STUB/readyatport"; echo "$PWD" > "$STUB/portwt"; }' > "$STUB/review-cmd"
  # Each review's prompt is kept, as $STUB/prompt.<n>.
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  # loop: only a whole card run shows the port's tests, the move on main and the auto-port that reuses its pass
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,test pass,landed ok," ] \
    && [ "$(wc -l < "$STUB/sessions")" = 4 ] && [ "$(wc -l < "$STUB/reviews")" = 4 ] \
    || fail "a finished loop whose landing conflicted was not ported by one session, reviewed once, tested and landed: $(steps 8)"
  [ "$(jq -c '[.tested, .alone, (.patch | length > 0)]' "$STUB/readyatport" 2>/dev/null)" = '[true,true,true]' ] \
    || fail "the card with a last NO-GO did not store its test pass, marked alone, keyed to its staged change: $(cat "$STUB/readyatport" 2>&1)"
  [ "$(wc -l < "$STUB/tests")" = 2 ] && [ "$(st 'select(.issue == 8 and .step == "test") | .reused' | tr '\n' ,)" = "null,null,true," ] \
    && [ "$(st 'select(.issue == 8 and .step == "landed") | .batch')" = null ] \
    || fail "the port, a different staged change, did not run its tests, its fit onto the moved main with the same change ran them again, or it did not land alone: $(wc -l < "$STUB/tests") runs, $(steps 8) $(st 'select(.issue == 8 and .step == "landed")')"
  [ "$(cat "$R/b.txt")" = b ] && [ "$(git -C "$R" log -1 --format=%P | wc -w)" = 1 ] && [ "$(git -C "$R" log -2 --format=%s | tail -n 1)" = "main adds b.txt" ] \
    || fail "#8 did not land alone on the main that moved: $(git -C "$R" log --oneline | head -3)"
  st 'select(.issue == 8 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts: ' || fail "the port's step does not name the conflict"
  # Bug (#1385): nothing marked the port, so a retry counted the reviews before it as its rounds (t_resumeport3).
  [ "$(st 'select(.issue == 8 and .step == "rebase") | .port')" = true ] && recok "$ST/cards.jsonl" "an automatic port" \
    || fail "the port's rebase line does not mark it as the port: $(st 'select(.issue == 8 and .step == "rebase")')"
  # The .port file and the instructions of the port's review are made inside card() (no function makes them), so only
  # this run shows that review is told it reviews a port alone and handed the kept patch against the ported change.
  # Bug: the port's review was given the instructions of any other review (no PORTREVIEW, no .port file named).
  # Bug: a prompt that names another file (such as <worktree>.patch.port) in place of <worktree>.port, the file the
  # engine writes, sends the review to a file that is not there: the line must name that exact path.
  grep -qx -- '+ ONE' "$STUB/port" && grep -qx -- ' +two' "$STUB/port" || fail "the review after the port was not handed the kept patch against the port: $(cat "$STUB/port" 2>&1)"
  grep -qx '# This review is of a port alone' "$STUB/prompt.4" && grep -qxF "The difference is the file $(cat "$STUB/portwt" 2>&1).port." "$STUB/prompt.4" \
    && ! grep -q '^# This review is of a port alone' "$STUB/prompt.3" \
    || fail "the port's review, and it alone, was not told it reviews the port and handed the .port file: $(grep -n 'port' "$STUB/prompt.4" 2>&1 | tail -n 4)"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 " ] && [ "$(st 'select(.issue == 8 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100104,100105,100106]]' ] \
    && [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] || fail "the port did not withdraw the follow-ups and file the loop's findings again at its landing: $(st 'select(.issue == 8 and .step == "landed")')"
  # Bug: the filed line after the port's GO said the loop ended on that GO, not on review 3's max-reviews whose
  # findings it files.
  [ "$(st 'select(.issue == 8 and .step == "filed") | [.stop, .pass, .rounds] | tojson' | tr '\n' ' ')" = '["max-reviews",3,0] ["max-reviews",3,0] ' ] \
    || fail "a filed line does not say why the loop whose findings it files ended: $(st 'select(.issue == 8 and .step == "filed") | tojson')"
  [ "$(loop cards | jq -c '.cards[0] | [.step, (.steps | map(.step) | join(" "))]')" = '["landed","build review fix review fix review test rebase review test test"]' ] \
    && [ -z "$(st 'select(.step == "blocked")')" ] && [ ! -s "$ST/retried.jsonl" ] && loop check || fail "the port is not a step of the card's row, or it blocked or was retried: $(loop cards | jq -c '.cards[0]')"
}

# The rebuild conflicts too (main moves again during it), and so does the one port after it: blocked with the
# conflict message, nothing landed: landconflict() on each of the three conflicts, as card() calls it after each land().
t_rebasetwice() {
  rebasesetup 8
  echo 'echo again > a.txt; echo "THREE$(wc -l < "$STUB/sessions")" > "$R/a.txt"; git -C "$R" commit -qam third' > "$STUB/rebuild"
  conflicted 8 'for i in 1 2 3; do land1; go=end; landconflict; outcome; done'
  [ "$OUTCOME" = '{"go":"next","rebased":"1","ported":"","parsecheck":"1","kept":"","pass":1}
{"go":"next","rebased":"","ported":"1","parsecheck":"1","kept":"","pass":0}
{"go":"end","rebased":"","ported":"1","parsecheck":"1","kept":"","pass":0}' ] \
    || fail "a card that conflicts three times was not rebuilt, then ported, then blocked: $OUTCOME"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "rebase ok,rebase ok,blocked blocked," ] \
    && st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' || fail "a conflict after the port did not block with the conflict message: $(st 'select(.issue == 8)')"
  [ "$(git -C "$R" log -1 --format=%s)" = third ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "a conflict after the port landed something, left main dirty or left the worktree"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] || fail "a card that conflicts three times was rebuilt or ported more than once: $(wc -l < "$STUB/sessions") sessions"
}

# Bug: a rebuild session that ends well but leaves no change blocks the card with nothing kept: the
# reviewed change is deleted with the worktree, and retry builds from nothing. landconflict() rebuilds, and the next
# pass of the review loop finds no change (emptychange(), then nochange(), as cardreview() calls them).
t_rebaseempty() {
  rebasesetup 12
  echo ':' > "$STUB/rebuild"
  conflicted 12 'land1; go=end; landconflict; outcome; ! emptychange "$c" "$n" "$wt" "$br" || nochange "$c" "$n" "$wt" "$sprompt"'
  [ "$OUTCOME" = '{"go":"next","rebased":"1","ported":"","parsecheck":"1","kept":"","pass":1}' ] || fail "a card whose landing conflicted after a GO was not rebuilt: $OUTCOME"
  [ "$(st 'select(.issue == 12 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "rebase ok,blocked blocked," ] \
    || fail "a rebuild that leaves no change: $(st 'select(.issue == 12) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  local k c; k=$(st 'select(.issue == 12 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); c=$(st 'select(.issue == 12 and .step == "blocked") | .card')
  [ -n "$k" ] && grep -qx '+two' "$k/$c.patch" && [ "$(cat "$k/$c.base")" = "$(git -C "$R" rev-parse HEAD~1)" ] || fail "a rebuild that left no change did not keep the reviewed change as the card's patch (kept: $k)"
  tail -n 1 "$STUB/comments" | grep -q "Its work is kept as a patch: <state>/kept/${k##*/}/$c.patch (1 files, 1 KB, built on commit " || fail "the block comment does not name the reviewed patch: $(tail -n 1 "$STUB/comments")"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a rebuild that left no change left files beside the cards: $(ls "$T/$CASE/cards")"
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
# $RESUMED: {rc, err, mode, note, from, fin, finend, pro, rounds, staged (the worktree's staged files), beside (the
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
    jq -cn --argjson rc "$rc" --arg err "$err" --arg mode "$mode" --arg note "$note" --arg from "$from" --arg fin "$fin" --argjson finend "$finend" \
      --argjson pro "$pro" --argjson rounds "$rounds" --arg staged "$(git -C "$wt" diff --cached --name-only)" --arg beside "$(cd "$CARDS" && ls -d c9.* 2>/dev/null)" \
      "{rc: \$rc, err: \$err, mode: \$mode, note: \$note, from: \$from, fin: \$fin, finend: \$finend, pro: \$pro, rounds: \$rounds,
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
# review after the port's own alone, so its first NO-GO (a P2, review 2 of 3) gets a fix round; with the 5 counted,
# or the 2 after the port, it was its last review and landed the finding as a follow-up.
t_resumeport3() {
  local r l=''
  resumesetup 7
  r=$(kline c1-7 7 review NO-GO); l=$(printf '%s\n' "$r" "$r" "$r" "$(kline c1-7 7 rebase ok '{"port": true}')" "$r" "$r")
  portkept 7 c1-7 'test: exit 1' 'echo two >> a.txt' "$(printf '%s\n' '[P2] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO')" "$l"
  loop retry 7 >/dev/null || fail "retry of #7 exited non-zero"
  resumed 7 'res=NO-GO rep="" finrev="" earlier="" pass=1 rebased="" tfix="" lfix="" privfix="" p1fix=""; afterreview; echo "$after $stop" > "$T/$CASE/after"'
  [ "$(jq -c '[.mode, .rounds]' <<<"$RESUMED")" = '["session",1]' ] || fail "the reviews before the port of c1-7, or the port's own review, were counted as the retried card's rounds: $RESUMED"
  [ "$(cat "$T/$CASE/after")" = "fix " ] || fail "the retried card's first NO-GO (review 1, 1 round carried) did not get a fix round: $(cat "$T/$CASE/after")"
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

# Bug: the earlier loop's review was put back in place of the port's own before the yes was
# checked, so a port whose visible change goes beyond its parent's yes landed on the earlier review's INHERITED: part.
# The yes check (visgate(), lib/card.sh) of follow-up #100101, whose parent #7 has the owner's yes (inherit()), on
# the port's product change: the port's own review, which says the change goes beyond that yes, stops the card for
# the owner; the earlier loop's review, which says it is part of the yes, would land it on that yes.
t_portyes() {
  local P='Visible change approved: Dana, 2026-01-02; condition: only for admins' Y="visible to customers or staff: needs Dana's yes: "
  setup "$(jq -cs . <(issue 7 2026-01-01 | jq -c --arg l "$P" '.body += "\n\n" + $l') <(issue 100101 2026-01-02 conveyor-followup P1 | jq -c '.body = "Follow-up to #7 (Conveyor card c0-7). Its last review said NO-GO.\nFinding: x\nFollow-up depth: 1"'))"
  { kline c0-7 7 review GO '{"visible":"yes: admins see a Pay button"}'; landed 7 '[100101]'; } > "$ST/cards.jsonl"
  printf '%s\n' 'INHERITED: beyond: guests see it too' 'USER-VISIBLE: yes: guests see a Pay button' 'VERDICT: GO' > "$STUB/review.port"
  printf '%s\n' '[P1] a.txt:1 wrong word' 'INHERITED: part' 'USER-VISIBLE: yes: admins see the Pay button in red' 'VERDICT: NO-GO' > "$STUB/review.earlier"
  fx_in 'cd "$R" || exit 3; n=100101 c=c9 wt=$CARDS/c9 ph="" pf=""
    git worktree add -q --detach "$wt" "refs/heads/$BRANCH" && (cd "$wt" && echo two >> a.txt && mkdir -p web && echo pay >> web/pay.ts && git add -A) || exit 3
    issue=$(gh issue view "$n" --json number,title,body,labels,milestone) || exit 3
    vrule=on seen=none nyes=0 sect="" ybase="" heldto="" vmode="" yfile=""; visplan; inh=$(inherit "$issue"); [ -n "$inh" ] || exit 3
    for r in port earlier; do
      cp "$STUB/review.$r" "$wt.review" && vis=$(visible "$wt.review" "$vmode") && yesfrom="" err="" || exit 3
      visgate >/dev/null; jq -cn --arg r "$r" --arg rc $? --arg e "$err" --arg y "$yesfrom" "{review: \$r, rc: \$rc, err: \$e, yesfrom: \$y}"
    done > "$T/$CASE/gate"'
  [ "$RC" = 0 ] || fail "the yes check could not be called on #100101's port (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(jq -sc '.[0]' "$T/$CASE/gate")" = "$(jq -cn --arg e "${Y}guests see a Pay button (it goes beyond the yes of #7: guests see it too)" '{review: "port", rc: "1", err: $e, yesfrom: ""}')" ] \
    || fail "a port whose visible change goes beyond its parent's yes does not stop for the owner: $(cat "$T/$CASE/gate")"
  [ "$(jq -sc '.[1]' "$T/$CASE/gate")" = '{"review":"earlier","rc":"0","err":"","yesfrom":"7"}' ] \
    || fail "the earlier loop's review, the one that must not stand for the port's, does not land on the yes of #7: $(cat "$T/$CASE/gate")"
}
