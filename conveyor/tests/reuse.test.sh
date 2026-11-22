#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a review reused when the card's staged change and main are those of its last review (reusable()), and
# what the review after a fix of review findings is given when it runs (donewhen.sh rereview()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A fix session that changed nothing leaves the reviewer the same change on the same main: the review is not run
# again, and its verdict and findings stand as if it had returned them. Bugs: a second review session runs (it costs a
# review and repeats the findings); the reused line lacks the verdict, findings or counts of the last review; a reused
# NO-GO is not counted as a round, so a finding back after its fix round is fixed again instead of ending the loop.
t_reusesame() {
  setup "[$(issue 7 2026-01-01)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  rv() { st "select(.issue == $1 and .step == \"review\") | $2"; }
  # The build changes a.txt; each fix session after it changes nothing.
  echo '[ "$(wc -l < "$STUB/sessions")" != 1 ] || echo two >> a.txt' > "$STUB/build"
  # #7: a P2 NO-GO: the reused review repeats it after its fix round, every finding P2, so it is the last review and
  # the card lands, filing the finding.
  printf '%s\n' '[P2] a.txt:1 a nit. Proof: line 2 reads two' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(steps 7)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,test pass,landed ok," ] \
    || fail "the reused NO-GO did not end the loop as the review's NO-GO would: $(steps 7)"
  [ "$(wc -l < "$STUB/reviews")" = 1 ] || fail "a review session ran on the same change and main: $(wc -l < "$STUB/reviews") reviews"
  [ "$(rv 7 '[.result, .reason, (.counts | tojson), .visible, .patch, .main] | join("|")' | uniq | wc -l)" = 1 ] \
    || fail "the reused review line is not the last review's verdict and findings: $(rv 7 tojson)"
  [ "$(rv 7 .reused | tail -n 1)" = "$(rv 7 .time | head -n 1)" ] && [ "$(rv 7 '.reused // "none"' | head -n 1)" = none ] \
    && [ "$(rv 7 '.tokens.codex' | tail -n 1)" = 0 ] || fail "the reused review line does not name the review it reuses, or spent tokens: $(rv 7 tojson)"
  [ "$(rv 7 .patch | head -n 1 | wc -c)" -gt 1 ] && [ "$(rv 7 .main | head -n 1)" = "$(git -C "$R" rev-parse HEAD~1)" ] \
    || fail "the review line does not hold the staged change and the main commit it read: $(rv 7 tojson)"
  [ "$(jq -r .title "$STUB/filed")" = '[P2] a.txt:1 a nit. Proof: line 2 reads two' ] || fail "the last review's finding was not filed: $(cat "$STUB/filed" 2>&1)"
  loop check >/dev/null || fail "the review lines do not pass the record check: $(loop check 2>&1)"
}

# #8: a NO-GO with a P1: the reused review repeats it after its fix round, and the card blocks as it does today. A
# case of its own on a main of its own, beside t_reusesame.
t_reuseblock() {
  setup "[$(issue 8 2026-01-02)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo '[ "$(wc -l < "$STUB/sessions")" != 1 ] || echo two >> a.txt' > "$STUB/build"; head=$(git -C "$R" rev-parse HEAD)
  echo "$NOGO" > "$STUB/review.1"
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,blocked blocked," ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    && [ "$(st 'select(.issue == 8 and .step == "blocked") | .reason')" = 'the fix for [P1] a.txt:1 wrong word did not hold after 1 round' ] \
    || fail "a carried NO-GO with a repeated P1 did not block the card: $(steps 8) $(wc -l < "$STUB/reviews") reviews $(st 'select(.issue == 8 and .step == "blocked") | .reason')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ ! -e "$STUB/filed" ] || fail "#8 landed or filed"
}

# A review is reused only when both are the same. Bugs: a fix session that changed the staged change, or a card that
# now sits on another main commit with the same change, gets the last review again instead of a new one.
# The review after a fix is also given what that fix was told, what it changed and what was declined on the card
# (donewhen.sh rereview()). Bugs: that review was given exactly the first review's prompt, so it raised its findings at the same
# places again and raised a finding just declined on the card again; it was told nothing of a new defect being still
# welcome; a first review was given the section too; an `EARLIER: E<n> holds` answer was read as a finding.
t_reusechanged() {
  setup "[$(issue 7 2026-01-01)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  # The review copies the fix diff its prompt names, so the case reads what that file held.
  echo 'f=$(sed -n "s/^The file \(.*\.diff\)$/\1/p" "$STUB/prompt.$(wc -l < "$STUB/reviews")"); [ -z "$f" ] || cp "$f" "$STUB/fixdiff"' > "$STUB/review-cmd"
  # #7: the fix session (the second) changes the change, so the review runs; a finding is declined on this card and one
  # on another card meanwhile.
  cat > "$STUB/build" <<'EOF'
k=$(wc -l < "$STUB/sessions"); echo "fix$k" >> a.txt
[ "$k" != 2 ] || printf '%s\n' "{\"id\":\"d1\",\"card\":\"${PWD##*/}\",\"issue\":7,\"finding\":\"[P2] b.txt:2 a nit\",\"by\":\"judge\",\"why\":\"its proof needs a stub built to misbehave\",\"repo\":\"r\"}" \
  '{"id":"d2","card":"c0-9","issue":9,"finding":"[P2] z.txt:9 of another card","by":"judge","why":"not about this card","repo":"r"}' >> "$ST/declined.jsonl"
EOF
  printf '%s\n' '[P1] a.txt:1 wrong word' '[P2] c.txt:3 a nit' 'UNPROVEN: maybe d.txt:4' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'EARLIER: E1 holds' 'EARLIER: E2 holds' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.2"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(steps 7)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
    || fail "a changed staged change was not reviewed again: $(steps 7) $(wc -l < "$STUB/reviews") reviews"
  [ "$(st 'select(.issue == 7 and .step == "review") | .reused // "none"' | sort -u)" = none ] \
    && [ "$(st 'select(.issue == 7 and .step == "review") | .patch' | sort -u | wc -l)" = 2 ] || fail "the second review is marked reused, or read the same patch"
  c=$(st 'select(.issue == 7 and .step == "picked") | .card')
  # Its first review holds none of the re-review section.
  ! grep -q 'follows a fix\|EARLIER\|^E[0-9] \|declined on this card\|The diff of the fix' "$STUB/prompt.1" || fail "the first review was given the re-review section: $(cat "$STUB/prompt.1")"
  # The review after the fix: the findings the fix was told, numbered, the fix diff's path, this card's declined finding with its reason.
  s=$(sed -n '/^# This review follows a fix of the last review.s findings$/,$p' "$STUB/prompt.2")
  grep -qx 'E1 \[P1\] a.txt:1 wrong word' <<<"$s" && grep -qx 'E2 \[P2\] c.txt:3 a nit' <<<"$s" && ! grep -q '^E3\|UNPROVEN' <<<"$s" \
    || fail "the review after the fix lacks the findings the fix was told: $s"
  grep -qx "The file .*/$c.rounds/1.diff" <<<"$s" && grep -qx '+fix2' "$STUB/fixdiff" && ! grep -qx '+fix1' "$STUB/fixdiff" \
    || fail "the review after the fix lacks the path of the fix's diff, or it is not that diff: $s $(cat "$STUB/fixdiff" 2>&1)"
  grep -qxF -- '- [P2] b.txt:2 a nit (declined: its proof needs a stub built to misbehave)' <<<"$s" && ! grep -q 'of another card' <<<"$s" \
    || fail "the review after the fix lacks this card's declined finding with its reason, or holds another card's: $s"
  # Its instructions: say whether each fix holds, read the fix first, a declined finding again only with a new reason,
  # a new defect at any level.
  i=$(tr '\n' ' ' <<<"$s")
  grep -qF '`EARLIER: E<n> holds`' <<<"$i" && grep -qF 'Read what that fix changed first' <<<"$i" && grep -qF 'only with a new, concrete reason' <<<"$i" \
    || fail "the re-review section lacks its instructions: $s"
  # The fix (1 line) touches no more than the default review.rereviewWhole (50%) of the change's 2 lines, so this
  # review is of the fix alone (#538). Bug: the review after a fix was asked to review the whole staged change again,
  # reading the part that passed its earlier review once more (about 63 k tokens a later review against 57 k a first).
  grep -qF 'A new defect that the fix'"'"'s lines cause, in its diff or in the code that calls what it changed, may still be raised, at any level. Do not review the rest of the change again: it passed its earlier review.' <<<"$i" \
    && ! grep -qF 'A new defect anywhere in the change' <<<"$i" || fail "the review of the fix alone is not told to raise only what the fix's lines cause: $s"
  grep -q '^Review the staged change in this worktree' "$STUB/prompt.1" && ! grep -q 'Review the staged change in this worktree' "$STUB/prompt.2" \
    && grep -q '^Review the fix of the last review.s findings, not the whole staged change' "$STUB/prompt.2" \
    || fail "the review after the fix was asked to review the whole staged change: $(head -n 3 "$STUB/prompt.2")"
  # A review of the fix alone is still a review of a change: it is told what not to raise (the declined findings).
  grep -q '^# Do not raise these' "$STUB/prompt.2" || fail "the review of the fix alone was not told what not to raise"
  # The section is part of the brief, after the issue, not of the instructions before it.
  [ "$(grep -n -m1 'body of 7' "$STUB/prompt.2" | cut -d: -f1)" -lt "$(grep -n -m1 '^# This review follows a fix' "$STUB/prompt.2" | cut -d: -f1)" ] \
    || fail "the re-review section is not in the review's brief"
  # An `EARLIER: E<n> holds` line is no finding: the GO lands the card with nothing filed.
  [ "$(st 'select(.issue == 7 and .step == "landed") | has("leftover") or has("followups")')" = false ] && [ ! -e "$STUB/filed" ] \
    || fail "an EARLIER line was read as a finding: $(st 'select(.issue == 7) | "\(.step) \(.result)"' | tr '\n' ,) $(cat "$STUB/filed" 2>&1)"
}

# A fix that touches more than review.rereviewWhole (default 50%) of the change's lines is reviewed as the whole change
# again (#538): here it adds 2 of the change's 3 lines. Bug: such a fix, most of the change, was reviewed as a fix
# alone, so the change it rewrote was never reviewed as a whole.
t_reusewhole() {
  setup "[$(issue 7 2026-01-01)]"
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  echo 'echo fix >> a.txt; [ "$(wc -l < "$STUB/sessions")" = 1 ] || echo more >> a.txt' > "$STUB/build"
  echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "the change was not reviewed after its fix: $(wc -l < "$STUB/reviews") reviews"
  i=$(tr '\n' ' ' < "$STUB/prompt.2")
  grep -q '^Review the staged change in this worktree' "$STUB/prompt.2" && ! grep -qF 'Review the fix of the last review' <<<"$i" \
    && grep -qF 'A new defect anywhere in the change, in what the fix changed or elsewhere, may still be raised, at any level.' <<<"$i" \
    && ! grep -qF 'Do not review the rest of the change again' <<<"$i" && grep -qx 'E1 \[P1\] a.txt:1 wrong word' "$STUB/prompt.2" \
    || fail "a fix over the share was not given a whole-change review with its findings: $i"
}

# #8: the fix session changes nothing in the change but puts it on a newer main commit: the review runs. A case of
# its own on a main of its own, beside t_reusechanged.
t_reusemoved() {
  setup "[$(issue 8 2026-01-02)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  cat > "$STUB/build" <<'EOF'
if [ "$(wc -l < "$STUB/sessions")" = 1 ]; then echo three >> a.txt
else echo moved > "$R/m.txt"; git -C "$R" add m.txt; git -C "$R" commit -qm moved
  git diff --cached --binary > "$STUB/p"; git reset -q --hard; git checkout -q --detach "$(git -C "$R" rev-parse HEAD)"; git apply --index "$STUB/p"; fi
EOF
  moved 1 "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
    || fail "the same change on a moved main was not reviewed again: $(steps 8) $(wc -l < "$STUB/reviews") reviews"
  [ "$(st 'select(.issue == 8 and .step == "review") | .patch' | sort -u | wc -l)" = 1 ] && [ "$(st 'select(.issue == 8 and .step == "review") | .main' | sort -u | wc -l)" = 2 ] \
    && [ "$(st 'select(.issue == 8 and .step == "review") | .reused // "none"' | sort -u)" = none ] || fail "the review on a moved main did not read the same patch on another main commit"
}

# The id both a review's reuse (reusable(), card.sh) and a test pass's reuse (testedhere()) key on is cardpatch(). Bugs: a
# fix that only re-indents Python (the same words in the same lines, so git patch-id gives one id) kept the old test
# pass and review; the change at other line numbers, on a main that moved above it, lost them. It calls the functions:
# the two reuses read nothing else of the change. The review line is stubbed to the patch, the main and the seen text
# the last review kept (stdb), its main being the HEAD asked about, so only the patch decides.
t_reusereindent() {
  eval "$(sed -n '/^cardpatch() {/p; /^tested() {/,/} # <worktree>$/p; /^testedhere() {/p' "$SRC/lib/claim.sh"; sed -n '/^reusable() {/,/^}/p' "$SRC/lib/review.sh")"
  local d=$T/reindent r; mkdir "$d" && git -C "$d" init -q && git -C "$d" config user.email t@example.com && git -C "$d" config user.name t || fail "no repo"
  printf 'for i in range(3):\n    print(i)\nprint("done")\n' > "$d/f.py"; git -C "$d" add f.py; git -C "$d" commit -qm base
  r=$d.ready; echo '{}' > "$r"
  # shellcheck disable=SC2317 # reusable() calls it
  stdb() { jq -cn --arg p "$KEPT" --arg m "$(git -C "$d" rev-parse HEAD)" '{step: "review", result: "GO", patch: $p, main: $m, seen: "s", time: "t"}'; }
  reuse() { reusable c "$(cardpatch "$d")" "$(git -C "$d" rev-parse HEAD)" s >/dev/null; } # the last review is reused
  stage() { printf '%s\n' "$1" >> "$d/f.py"; git -C "$d" add f.py; } # <the added line>
  stage '    print("inside")'; tested "$d"; KEPT=$(cardpatch "$d")
  testedhere "$d" && reuse || fail "the test pass or the review was not found on the change it passed on"
  git -C "$d" reset -q --hard; stage '        print("inside")'
  ! testedhere "$d" || fail "a change that only re-indented a line kept the old test pass (patch $(cardpatch "$d"))"
  ! reuse || fail "a change that only re-indented a line kept the old review (patch $(cardpatch "$d"))"
  git -C "$d" reset -q --hard; stage '    print("inside")'
  testedhere "$d" && reuse || fail "the same change again did not find its test pass or its review"
  git -C "$d" reset -q --hard; printf '# one\n# two\n# three\n' | cat - "$d/f.py" > "$d/g" && mv "$d/g" "$d/f.py"; git -C "$d" commit -qam above; stage '    print("inside")'
  testedhere "$d" && reuse || fail "the same change at other line numbers, on a main that moved, lost its test pass or review (patch $(cardpatch "$d"))"
}
