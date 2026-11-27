#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a review reused when the card's staged change and main are those of its last review (reusable()), and
# what the review after a fix of review findings is given when it runs (donewhen.sh rereview()), and the first review
# that ends the loop with new P2 or P3 findings alone (loopstop(): new-p2), and the run of the card's changed tests
# before its first review (cardland.sh pretest()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A page of the repository says <text> (lines joined, spaces folded). Each case file that calls it defines its own, named after the file: the bug check puts only the card's test files on main's code, where a helper in lib.sh is missing, and the runner sources the case files into one shell, where one name cannot be defined twice.
pagesays_reuse() { tr '\n' ' ' < "$SRC/../$1" | tr -s ' ' | grep -qF -- "$2" || fail "$1 does not say \"$2\": $3"; } # <page> <text> <what the run showed>
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
  # #7: a P1 NO-GO (a P2 alone ends the loop at once: loopstop() new-p2): the reused review repeats it after its fix
  # round, so it is the last review and the card lands, filing the finding.
  printf '%s\n' '[P1] a.txt:1 a nit. Proof: line 2 reads two' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  # loop: only card()'s review loop shows a fix round that changed nothing reusing the review, then the test and landing
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  # The tests run once before the first review (pretest()), and no test line comes before the reused review.
  [ "$(steps 7)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review NO-GO,test pass,landed ok," ] \
    || fail "the reused NO-GO did not end the loop as the review's NO-GO would, or tests ran before the reused review: $(steps 7)"
  [ "$(wc -l < "$STUB/reviews")" = 1 ] || fail "a review session ran on the same change and main: $(wc -l < "$STUB/reviews") reviews"
  [ "$(rv 7 '[.result, .reason, (.counts | tojson), .visible, .patch, .main] | join("|")' | uniq | wc -l)" = 1 ] \
    || fail "the reused review line is not the last review's verdict and findings: $(rv 7 tojson)"
  [ "$(rv 7 .reused | tail -n 1)" = "$(rv 7 .time | head -n 1)" ] && [ "$(rv 7 '.reused // "none"' | head -n 1)" = none ] \
    && [ "$(rv 7 '.tokens.codex' | tail -n 1)" = 0 ] || fail "the reused review line does not name the review it reuses, or spent tokens: $(rv 7 tojson)"
  [ "$(rv 7 .patch | head -n 1 | wc -c)" -gt 1 ] && [ "$(rv 7 .main | head -n 1)" = "$(git -C "$R" rev-parse HEAD~1)" ] \
    || fail "the review line does not hold the staged change and the main commit it read: $(rv 7 tojson)"
  [ "$(jq -r .title "$STUB/filed")" = '[P1] a.txt:1 a nit. Proof: line 2 reads two' ] || fail "the last review's finding was not filed: $(cat "$STUB/filed" 2>&1)"
  loop check >/dev/null || fail "the review lines do not pass the record check: $(loop check 2>&1)"
}

# #1444 (R231). Bug it catches: the review after a fix round keeps the lines that fix deleted (excerpts(), from the
# tree before the fix); a second fix round that changed nothing then made the tree before it, which no longer has
# those lines, the one its reused review read them from, so that review lost them. The build adds `two` and `three`,
# the first fix deletes `two`, the review after it cites a.txt:2 (two, as that fix deleted it), the second fix changes
# nothing; the review it reuses kept `two`, and so must it.
t_reuseexcerpts() {
  local r
  setup "[$(issue 7 2026-01-01)]"
  echo 'case $(wc -l < "$STUB/sessions") in 1) printf "%s\n" two three >> a.txt ;; 2) sed -i "/^two$/d" a.txt ;; esac' > "$STUB/build"
  # P1s: a review of new P2s alone ends the loop (loopstop(): new-p2), with no fix round to reuse it.
  printf '%s\n' '[P1] a.txt:1 a nit. Proof: line 1 reads one' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P1] a.txt:2 the deleted two was needed. Proof: line 2 read two before the fix' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  # loop: only card()'s review loop shows a fix round, the review after it and a reused review after a second fix
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  r=$(st 'select(.issue == 7 and .step == "review") | [(.reused // "none" | . != "none"), [.excerpts[]? | select(.at == "a.txt:2") | [.side, .lines]]] | tojson' | tail -n 2)
  [ "$r" = '[false,[["new",["three"]],["fix",["two"]]]]'$'\n''[true,[["new",["three"]],["fix",["two"]]]]' ] \
    || fail "the review reused after a fix that changed nothing lost the line the fix before it deleted: $r ($(st 'select(.issue == 7) | "\(.step) \(.result)"' | tr '\n' ,))"
}

# #8: a NO-GO with a P1: the reused review repeats it after its fix round, which ends the loop: the card lands with the
# P1 filed as a follow-up (issue 1670; it blocked). A case of its own on a main of its own, beside t_reusesame.
t_reuseblock() {
  setup "[$(issue 8 2026-01-02)]"; steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo '[ "$(wc -l < "$STUB/sessions")" != 1 ] || echo two >> a.txt' > "$STUB/build"
  echo "$NOGO" > "$STUB/review.1"
  # loop: only card()'s review loop shows a reused NO-GO counted as a round, then the card's test step and landing
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review NO-GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    || fail "a carried NO-GO with a repeated P1 ([P1] a.txt:1 wrong word) did not land: $(steps 8) $(wc -l < "$STUB/reviews") reviews $(st 'select(.issue == 8 and .step == "blocked") | .reason')"
  [ "$(jq -r .title "$STUB/filed" 2>&1)" = '[P1] a.txt:1 wrong word' ] && [ "$(st 'select(.issue == 8 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] \
    || fail "#8 (review: [P1] a.txt:1 wrong word, repeated) did not land on main with the P1 filed: $(cat "$STUB/filed" 2>&1)"
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
  # on another card meanwhile. This card's is of a kind donotraise() lists (`cannot happen`); a line with no kind is
  # left out of the "Do not raise these" section.
  cat > "$STUB/build" <<'EOF'
k=$(wc -l < "$STUB/sessions"); echo "fix$k" >> a.txt
[ "$k" != 2 ] || printf '%s\n' "{\"id\":\"d1\",\"card\":\"${PWD##*/}\",\"issue\":7,\"finding\":\"[P2] b.txt:2 a nit\",\"by\":\"judge\",\"why\":\"its proof needs a stub built to misbehave\",\"kind\":\"cannot happen\",\"repo\":\"r\"}" \
  '{"id":"d2","card":"c0-9","issue":9,"finding":"[P2] z.txt:9 of another card","by":"judge","why":"not about this card","repo":"r"}' >> "$ST/declined.jsonl"
EOF
  printf '%s\n' '[P1] a.txt:1 wrong word' '[P2] c.txt:3 a nit' 'UNPROVEN: maybe d.txt:4' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'EARLIER: E1 holds' 'EARLIER: E2 holds' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.2"
  # loop: only card()'s review loop shows the fix session's changed change reviewed again, with the prompt rereview() gave it
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(steps 7)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
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
  grep -q '^# Do not raise these' "$STUB/prompt.2" && grep -qxF -- '- its proof needs a stub built to misbehave (the finding: [P2] b.txt:2 a nit)' "$STUB/prompt.2" \
    || fail "the review of the fix alone was not told what not to raise"
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
  # loop: only card()'s review loop shows a fix over the rereviewWhole share given a whole-change review
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
  # loop: only card()'s review loop shows a fix that only moved main reviewed again, then the test and landing
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
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
  eval "$(sed -n '/^cardpatch() {/p; /^tested() {/,/} # <worktree>$/p; /^readyput() {/,/^}/p; /^testedhere() {/p' "$SRC/lib/claim.sh"; sed -n '/^reusable() {/,/^}/p' "$SRC/lib/review.sh")"
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

# Issue 1302: a P1 first found in the last review (the third) gets one fix round and a review of that fix alone before
# the card can land; if the P1 still holds the card blocks. Bug: the loop's end decided, so the card landed with the P1
# filed as a follow-up. p1last runs card #7 through two fix rounds and a third review that finds the P1, then gives the
# fourth review (<review 4>) and reads the steps (steps), the prompts of the reviews (prompt.N) and the follow-ups (filed).
p1last() { # <review 4>
  setup "[$(issue 7 2026-01-01)]"; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  echo 'echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"
  # P1s: a review of new P2s alone ends the loop (loopstop(): new-p2), with no third review to find the P1.
  printf '%s\n' '[P1] a.txt:1 first nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P1] a.txt:2 second nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' '[P1] a.txt:3 drops what the issue asks' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.3"
  printf '%s\n' "$1" > "$STUB/review.4"
  # loop: only a whole card shows that the fix round and its review come before any landing.
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
}
p1fixround() { # the fix round and its fix-only review came before any landing or block
  [[ "$(steps)" == "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,fix ok,review $1"* ]] \
    && [ "$(wc -l < "$STUB/reviews")" = 4 ] && grep -q '^Review the fix of the last review.s findings, not the whole staged change' "$STUB/prompt.4" \
    || fail "the P1 of the last review did not get one fix round and a review of that fix alone before the end: $(steps) $(wc -l < "$STUB/reviews") reviews"
}

# Done when: the fix clears the P1, so the card lands and files no follow-up for it.
t_p1lastfixed() {
  p1last $'USER-VISIBLE: no\nVERDICT: GO'
  p1fixround GO
  [ "$(steps)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] && [ ! -e "$STUB/filed" ] \
    || fail "a P1 cleared by its fix round did not land with nothing filed: $(steps) $(cat "$STUB/filed" 2>&1)"
  # Bug (#1436): the guide said a card has at most three reviews, but the run above had four: the last review's P1 got one
  # fix round and one more review.
  local n; n=$(wc -l < "$STUB/reviews")
  pagesays_reuse docs/cards.md 'once more after the fix of a P1 on a last review' "the card had $n reviews"
  pagesays_reuse docs/cards.md 'and one more the fix of a P1 on a last review' "the card had $n reviews"
}

# Done when (issue 1670): the P1 still holds after that fix, so the card lands and the P1 is filed as a follow-up.
# Bug: the card blocked for the owner and filed nothing.
t_p1laststill() {
  p1last $'[P1] a.txt:3 drops what the issue asks\nUSER-VISIBLE: no\nVERDICT: NO-GO'
  p1fixround NO-GO
  [ "$(steps)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,landed ok," ] \
    && [ -z "$(st 'select(.issue == 7 and .step == "blocked")')" ] && [ "$(jq -r .title "$STUB/filed" 2>&1)" = '[P1] a.txt:3 drops what the issue asks' ] \
    || fail "a P1 that holds after its fix round (review 4: [P1] a.txt:3 drops what the issue asks) did not land with it filed: $(steps) $(cat "$STUB/filed" 2>&1)"
}

# Issue 1736: a first review that is a NO-GO with only new P2 or P3 findings ends the loop (loopstop(): new-p2): the
# card runs no fix session, goes to its tests and lands, each finding filed as a follow-up at depth 1. Bugs: such a
# review got a fix round (new-p2 held from review 2 on only), so the card paid a fix session and a second review for
# findings that land as follow-ups anyway; the stop on its review line is not new-p2; a finding is not filed.
t_newp2first() {
  local p2='[P2] a.txt:1 the count is one short. Proof: line 2 reads two' p3='[P3] a.txt:2 a style nit'
  setup "[$(issue 7 2026-01-01)]"; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  printf '%s\n' "$p2" "$p3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  # loop: only a whole card shows that no fix session runs and the card goes on to its tests and lands with the follow-ups
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(steps)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] \
    && [ "$(st 'select(.issue == 7 and .step == "review") | .stop')" = new-p2 ] \
    || fail "review 1 ($p2; $p3) did not end the loop as new-p2 with no fix session: $(steps) $(wc -l < "$STUB/sessions") sessions"
  [ "$(jq -r .title "$STUB/filed" | tr '\n' '|')" = "$p2|$p3|" ] && [ "$(jq -rs 'map(.body | test("(^|\n)Follow-up depth: 1(\n|$)")) | all' "$STUB/filed")" = true ] \
    || fail "review 1's findings ($p2; $p3) were not each filed as a follow-up at depth 1: $(cat "$STUB/filed" 2>&1)"
  pagesays_reuse docs/cards.md '`new-p2`: from the first review on, a `NO-GO` whose findings are all new and all P2 or P3' "review 1 ended the loop as $(st 'select(.issue == 7 and .step == "review") | .stop')"
}

# Issue 1736: a first review with a P1 beside a P2 gets a fix round (new-p2 needs no P0 or P1). Bug: the card lands it.
t_newp2firstp1() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' b.txt base
  printf '%s\n' '[P1] a.txt:2 drops the count' '[P2] b.txt:1 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  afterrun "$(issue 7 2026-01-01)"
  [ "$(jq -c '[.after, .stop]' <<<"$AFTER")" = '["fix",""]' ] || fail "review 1 with [P1] a.txt:2 drops the count and [P2] b.txt:1 a nit did not go to a fix round: $AFTER"
}

# Issue 1736: a card whose issue is a follow-up at the depth cap (Follow-up depth: 2) files no follow-up, so a first
# review of P2s alone gets a fix round there (afterreview() drops new-p2). Bug: the card lands and the P2 is fixed nowhere.
t_newp2firstcap() {
  setup "[$(issue 7 2026-01-01)]"; fx_wt 'echo two >> a.txt' b.txt base
  printf '%s\n' '[P2] a.txt:2 the count is one short' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  afterrun "$(issue 7 2026-01-01 | jq -c '.body += "\nFollow-up depth: 2"')"
  [ "$(jq -c '[.after, .stop]' <<<"$AFTER")" = '["fix",""]' ] || fail "review 1 with [P2] a.txt:2 the count is one short, on a follow-up at depth 2, did not go to a fix round: $AFTER"
}

# The tests before the first review (pretest(), cardland.sh). #7's changed test a.test.sh fails its first run and the
# run again (runs 1 and 2), then passes. Bugs it catches: the card paid for a review before its tests failed (a review
# line before the first fix); the fail and pass lines before the review lack before: "review"; the test fix before the
# review made the first review a last one (loopstop() test-fix: its P1 NO-GO landed filed, with no fix round); the pass
# of that test fix was counted as a review (the GO review's line says pass 3).
t_pretestfail() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  # The build (session 1) and the fix of the review's finding (session 3) change a.txt; the test fix (session 2) does not.
  echo 'case $(wc -l < "$STUB/sessions") in 1) echo two >> a.txt ;; 3) echo three >> a.txt ;; esac' > "$STUB/build"
  echo 'echo x >> "$STUB/tests"; [ "$(wc -l < "$STUB/tests")" -gt 2 ] || { echo "a.test.sh: one failed"; exit 1; }' > "$STUB/test-cmd"
  printf '%s\n' '[P1] a.txt:2 drops the count. Proof: line 2 reads two' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.2"
  # loop: only card()'s loop shows the test fix before any review, then the review loop after it, and the Test step
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(steps)" = "picked ok,worktree ok,brief ok,build ok,test fail,fix ok,test pass,review NO-GO,fix ok,review GO,test pass,landed ok," ] \
    || fail "a card whose changed test fails before its review did not go to a test fix, then review, fix and land: $(steps)"
  [ "$(st 'select(.issue == 7 and .step == "test") | "\(.result) \(.before // "none")"' | paste -sd , -)" = "fail review,pass review,pass none" ] \
    || fail "the test lines before the review do not say before review, or the Test step's does: $(st 'select(.issue == 7 and .step == "test") | tojson')"
  [ "$(st 'select(.issue == 7 and .step == "review" and .result == "GO") | "\(.stop) \(.pass)"')" = "go 2" ] \
    || fail "the GO after one fix round is not review 2: $(st 'select(.issue == 7 and .step == "review") | tojson')"
  recok "$ST/cards.jsonl" "the card with a test fix before its review"
}

# The tests before the first review never pass: the card gets the Test step's limit of test-fix rounds (TESTFIXES, 3)
# and blocks, with no review. Bugs it catches: pretest() started each test fix with a count of its own (tfix reset),
# so the card went round test fixes with no end; or it went on to a review after its last test fix.
t_pretestlimit() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"
  echo 'echo x >> "$STUB/tests"; echo "a.test.sh: one failed"; exit 1' > "$STUB/test-cmd"
  # loop: only card()'s loop shows the test-fix rounds before any review end at their limit, as a whole card goes round them
  loop run --only 7 >/dev/null 2>&1
  [ "$(st 'select(.issue == 7 and (.step | IN("test", "fix", "review", "blocked"))) | .step' | paste -sd ' ' -)" = "test fix test fix test fix test blocked" ] \
    || fail "a card whose changed test always fails before its review did not block after 3 test fixes with no review: $(st 'select(.issue == 7) | "\(.step) \(.result)"' | paste -sd , -)"
}

# pretest() called as cardreview() calls it, on c7's change to a.txt (linked to a.test.sh). A pass writes one test line
# with before: "review"; a second call writes nothing (once a card).
# Bugs it catches: no test line, or one without before; the tests ran twice.
t_pretestpass() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  fx_in 'cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" pretested="" tbefore="" pretfix="" fin="" trc="" voids=0 pass=1 tfix="" fixed=0
    pretest; echo "1: go=$go"; pretest; echo "2: go=$go"'
  [ "$(grep '^[12]:' "$T/$CASE/run.out" | paste -sd , -)" = "1: go=,2: go=" ] || fail "pretest() did not go on to the review: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "test") | "\(.result) \(.before)"')" = "pass review" ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    || fail "pretest() run twice did not write one pass line with before review, its tests run once: $(st 'select(.step == "test") | tojson') $(cat "$STUB/tests" 2>&1)"
  recok "$ST/cards.jsonl" "pretest()"
}

# The project's checks (test.checkCommand) fail on #7's change, and its linked test a.test.sh would fail with them (a
# test.fileCommand may run them too): pretest() runs no test and goes on to the review, with no test line, as the Test
# step stops on such checks before any test runs and gives them to their own fix (cardtest()). Bug it catches: the
# failed check went to cardfailed() as a failed test, so the card got a test-fix round in place of the check's fix.
t_pretestcheck() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  echo 'echo x >> "$STUB/tests"; echo "a.test.sh: one failed"; exit 1' > "$STUB/test-cmd"
  tune '.test.checkCommand = "echo type error; exit 1"'
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" sprompt="" pretested="" tbefore="" pretfix="" fin="" trc="" voids=0 pass=1 tfix="" fixed=0 tmain=""
    cardfailed() { echo "cardfailed"; go=next; }; pretest; echo "go=$go tfix=$tfix"'
  [ "$(grep -E '^(cardfailed|go=)' "$T/$CASE/run.out" | paste -sd , -)" = "go= tfix=" ] && [ ! -e "$STUB/tests" ] && [ -z "$(st 'select(.step == "test")')" ] \
    || fail "pretest() ran the tests, or sent the failed project checks to a test fix, in place of going on to the review: $(cat "$T/$CASE/run.out") $(st 'select(.step == "test") | tojson')"
}

# pretest() passes a.test.sh run whole, timed (1 CPU second), and the Test step's run after it (tests(), as cardtest()
# calls it, then slowtests()) keeps that pass. Bug it catches: the Test step carried the pass's time from
# <worktree>.oldtimes onto its own line, so the Tests page (testruns(), testrulesmatches()) counted that one run twice.
t_pretesttimes() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  echo 'echo x >> "$STUB/tests"; printf "TESTRUN sec\t%s\t2\t1\n" a.test.sh >> "$CONVEYOR_TEST_LOG/t"' > "$STUB/test-cmd"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" pretested="" tbefore="" pretfix="" fin="" trc="" voids=0 pass=1 tfix="" fixed=0; testrulespass() { :; }
    pretest; echo "go=$go"; tests "$wt"; echo "rc=$?"; slowtests "$wt"; echo "times=$(cat "$wt.cpus")"'
  [ "$(grep -E '^(go|rc|times)=' "$T/$CASE/run.out" | paste -sd , -)" = "go=,rc=0,times={}" ] && [ "$(wc -l < "$STUB/tests")" = 1 ] \
    && [ "$(st 'select(.step == "test") | .times | tojson')" = '{"a.test.sh":1}' ] \
    || fail "the Test step that kept the pass before the review carried that pass's time, or ran a.test.sh again: $(cat "$T/$CASE/run.out") runs $(wc -l < "$STUB/tests") $(st 'select(.step == "test") | tojson')"
}

# The tests before the review fail, and main moved during them (b.txt, no conflict): cardfailed() fits #7 onto the moved
# main and runs them again there, and they pass. Bug it catches: the review line kept the main commit read before
# pretest() (the old one), though the review read the card on the moved main, so a later review could be reused wrongly.
t_pretestmoved() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; echo "$GO" > "$STUB/review.1"
  # Runs 1 and 2 (the run and tests()'s run again of its failed case at once) fail, and run 1 moves main: a run that
  # failed only once passed on its run again, and cardfailed() never fitted the card onto main.
  echo 'echo x >> "$STUB/tests"; r=$(wc -l < "$STUB/tests"); [ "$r" -gt 2 ] || { [ "$r" != 1 ] || { echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qnm "main moves"; }; echo "a.test.sh: one failed"; exit 1; }' > "$STUB/test-cmd"
  # loop: the review line, with its main commit, is written by card()'s review loop after pretest() and cardfailed()'s fit onto main
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  local moved; moved=$(git -C "$R" log --format=%H -1 --grep='^main moves$')
  [ -n "$moved" ] && [ "$(st 'select(.issue == 7 and .step == "review") | .main')" = "$moved" ] \
    || fail "the review after tests fitted onto the moved main ($moved) does not name that main: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.main // "") \(.reason)"' | tr '\n' ,)"
}

# The tests before the review fail, and their first run moves main (b.txt): the real cardfailed() routes the failure
# to a fit onto main (testroute(): moved, which sets tmain), and the run there passes. settle() is stubbed: the fit's
# worktree work is not what this checks. Then main moves again, and the Test step's testroute() is asked about a failure
# there. Bug it catches: pretest() left tmain set, so that failure went to a fix round (fix), not to a fit onto the new
# main (moved).
t_pretesttmain() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  # Runs 1 and 2 (the run and tests()'s run again of its failed case at once) fail, and run 1 moves main.
  echo 'echo x >> "$STUB/tests"; r=$(wc -l < "$STUB/tests"); [ "$r" -gt 2 ] || { [ "$r" != 1 ] || { echo b > "$R/b.txt"; git -C "$R" commit -qnam "main moves"; }; echo "a.test.sh: one failed"; exit 1; }' > "$STUB/test-cmd"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" sprompt="" pretested="" tbefore="" pretfix="" fin="" trc="" voids=0 pass=1 tfix="" fixed=0 tmain=""
    verdicts() { echo "{\"verdicts\":[{\"case\":\"a.test.sh: one\",\"verdict\":\"card\"}]}"; }; failline() { echo "{}"; }; testrulespass() { :; }
    redbrief() { :; }; unmate() { :; }; locked() { :; }; settle() { echo "settle"; return 0; }
    pretest; echo "go=$go tmain=$tmain"; echo c > b.txt; git commit -qnam "main moves again"; echo "route=$(testroute "$wt")"'
  [ "$(grep -E '^(settle|go=|route=)' "$T/$CASE/run.out" | paste -sd , -)" = "settle,go= tmain=,route=moved" ] \
    || fail "after the tests before the review were fitted onto a moved main and passed, a failure in the Test step after main moved again was not fitted onto main (route moved), or pretest() did not go on to the review: $(cat "$T/$CASE/run.out")"
}

# As t_pretesttmain, but the fit onto the moved main is a merge (settle() sets parsecheck, as its clean three-way
# merge does) whose file no longer parses. Bug it catches: pretest() ran the tests on that merged tree with no parse
# check, so a test file a merge broke ran before the review, where cardtest() would have sent it to its parse fix.
t_pretestparse() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  echo 'echo x >> "$STUB/tests"; r=$(wc -l < "$STUB/tests"); [ "$r" -gt 2 ] || { [ "$r" != 1 ] || { echo b > "$R/b.txt"; git -C "$R" commit -qnam "main moves"; }; echo "a.test.sh: one failed"; exit 1; }' > "$STUB/test-cmd"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" sprompt="" pretested="" tbefore="" pretfix="" fin="" voids=0 pass=1 tfix="" fixed=0 tmain="" parsecheck="" pfix=""
    verdicts() { echo "{\"verdicts\":[{\"case\":\"a.test.sh: one\",\"verdict\":\"card\"}]}"; }; failline() { echo "{}"; }; testrulespass() { :; }
    redbrief() { :; }; unmate() { :; }; locked() { :; }; settle() { parsecheck=1; return 0; }; checked() { :; }
    parses() { printf "%s\n" "a.test.mjs: \`node --check\` failed:" "SyntaxError"; return 1; }; session() { printf "%s\n" "$2" > "$STUB/parsefix"; echo "{}"; }
    pretest; echo "go=$go pass=$pass pretested=$pretested runs=$(wc -l < "$STUB/tests")"'
  [ "$(grep '^go=' "$T/$CASE/run.out")" = "go=next pass=0 pretested= runs=2" ] && grep -q 'no longer parses' "$STUB/parsefix" 2>/dev/null \
    || fail "after a fit onto main whose merge does not parse, pretest() ran the tests there, or did not go to the parse fix as a fix round with no review: $(cat "$T/$CASE/run.out") $(cat "$STUB/parsefix" 2>&1)"
  [ "$(cat "$FXWT.whole" 2>&1)" = 'merge in doubt: a file of the merge onto main did not parse' ] || fail "the parse fix did not mark the merge in doubt: $(cat "$FXWT.whole" 2>&1)"
}

# As t_pretesttmain, but the fit onto the moved main needs a conflict fix (settle() gives 2): the card goes to a fix
# round (next) with tmain set. Another card then marks main red (cnew), so the next pretest() runs no test and goes on
# to the review; then main moves again, and the Test step's testroute() is asked about a failure there. Bug it catches:
# pretest()'s skip on a red main left tmain set, so that failure went to a fix round (fix), not to a fit onto main (moved).
t_pretesttmainred() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  # Runs 1 and 2 (the run and tests()'s run again of its failed case at once) fail, and run 1 moves main.
  echo 'echo x >> "$STUB/tests"; r=$(wc -l < "$STUB/tests"); [ "$r" -gt 2 ] || { [ "$r" != 1 ] || { echo b > "$R/b.txt"; git -C "$R" commit -qnam "main moves"; }; echo "a.test.sh: one failed"; exit 1; }' > "$STUB/test-cmd"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" sprompt="" pretested="" tbefore="" pretfix="" fin="" trc="" voids=0 pass=1 tfix="" fixed=0 tmain=""
    verdicts() { echo "{\"verdicts\":[{\"case\":\"a.test.sh: one\",\"verdict\":\"card\"}]}"; }; failline() { echo "{}"; }; testrulespass() { :; }
    redbrief() { :; }; unmate() { :; }; locked() { :; }; settle() { echo "settle"; return 2; }; unset LOOPFIX ONLY
    pretest; echo "go=$go tmain=$tmain"
    jq -cn --arg s "$(git rev-parse HEAD)" '"'"'{reds: [{sha: $s, cases: [{case: "z.test.sh: other"}], card: "cnew"}]}'"'"' > "$MAINRED"
    pretest; echo "red: go=$go tmain=$tmain runs=$(wc -l < "$STUB/tests")"; rm -f "$MAINRED"
    echo c > b.txt; git commit -qnam "main moves again"; echo "route=$(testroute "$wt")"'
  [ "$(grep -E '^(settle|go=|red:|route=)' "$T/$CASE/run.out" | paste -sd , -)" = "settle,go=next tmain=1,red: go= tmain= runs=2,route=moved" ] \
    || fail "after a fit onto a moved main that needed a conflict fix, pretest() on a main marked red did not go on to the review with tmain cleared, so a failure in the Test step after main moved again was not fitted onto main (route moved): $(cat "$T/$CASE/run.out")"
}

# pretest() runs no test and writes no test line, going on to the review, for: a port's one review of a kept review
# (fin); a card that started from a kept review (cardreview()'s land, after which pretest() is not due); main red at
# main's commit, in a run with no LOOPFIX (`run --only` or a loop with a limit on its picks: red) and for the main-red
# fix card itself (redfix); no test.fileCommand. The review file is there only for land, so each other step skips for
# its own reason. Bugs it catches: each of them ran the tests before its review (a test line, a run of the stub);
# red, redfix: redhere() answers only for a card that waits on main, so the tests ran on a red main.
t_pretestskips() {
  local out
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  local v='cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" sprompt="" pretested="" tbefore="" pretfix="" fin="" trc="" voids=0 pass=1 tfix="" fixed=0 kept="" mode="" grown=1; unset LOOPFIX ONLY'
  # Each step prints its go and the test runs so far ($STUB/tests, a line a run of the stub).
  fx_in "$v"'; ran() { echo "$1: go=$go runs=$(cat "$STUB/tests" 2>/dev/null | wc -l)"; }; fin=GO; pretest; ran fin; fin=""; pretested=""
    printf "%s\n" "USER-VISIBLE: no" "VERDICT: GO" > "$wt.review"
    redbrief() { :; }; trialflag() { :; }; lintgate() { return 0; }; mode=land; cardreview; pretest; ran land; pretested=""; mode=""; rm -f "$wt.review"
    mkred() { jq -cn --arg s "$(git rev-parse "refs/heads/$BRANCH")" --arg c "$1" '"'"'{reds: [{sha: $s, cases: [{case: "a.test.sh: one"}], card: $c}]}'"'"' > "$MAINRED"; }
    mkred cnew; pretest; ran red; pretested=""
    mkred c7; LOOPFIX=1 pretest; ran redfix; rm -f "$MAINRED"'
  out=$(cat "$T/$CASE/run.out")
  tune 'del(.test.fileCommand)'; fx_in "$v"'; pretest; echo "nofilecmd: go=$go runs=$(cat "$STUB/tests" 2>/dev/null | wc -l)"'; out+=$'\n'$(cat "$T/$CASE/run.out")
  [ "$(grep -E '^(fin|land|red|redfix|nofilecmd):' <<<"$out" | paste -sd , -)" = "fin: go= runs=0,land: go= runs=0,red: go= runs=0,redfix: go= runs=0,nofilecmd: go= runs=0" ] \
    || fail "pretest() ran tests, or did not go on to the review, for a port's review (fin), a kept review (land), a red main in a run with no LOOPFIX (red) or for its fix card (redfix), or no test.fileCommand (nofilecmd): $out"
  [ -z "$(st 'select(.step == "test")')" ] && [ ! -e "$STUB/tests" ] \
    || fail "pretest() ran the tests for a port's review, a kept review, a red main or a pack with no test.fileCommand: $(st 'select(.step == "test") | tojson') $out"
}

# A card that carries an earlier card's review only for its findings (resumeplan(): its review file beside the
# worktree) runs its tests before its first review; a card blocked in those tests is not taken up at its tests with
# that review (issues.sh testkept()), while one blocked in its Test step is. Bugs they catch: pretest() skipped the
# tests for any review file there, so a card built from nothing went to its review untested; and once it ran them,
# a block there kept the carried review as the card's own, and a retry landed the change unreviewed.
t_pretestcarried() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" pretested="" tbefore="" pretfix="" fin="" trc="" voids=0 pass=1 tfix="" fixed=0
    printf "%s\n" "USER-VISIBLE: no" "VERDICT: NO-GO" > "$CARDS/c7.review"
    pretest; echo "carried: go=$go runs=$(cat "$STUB/tests" 2>/dev/null | wc -l)"
    p=$(jq -cn --arg r "$CARDS/c7.review" '"'"'{card: "c7", kept: "", reason: "the changed tests failed again after their 3 fix rounds (exit 1)", review: $r}'"'"')
    d=${STATE%/*}; jq -c '"'"'select(.card == "c7")'"'"' "$d/cards.jsonl" > "$d/retried.jsonl" # a retry finds a blocked card'"'"'s lines among the retried lines (prior())
    if testkept "$p" 7; then echo "before review: kept"; else echo "before review: not kept"; fi
    l=$(jq -c '"'"'select(.step == "test") | del(.before)'"'"' "$d/retried.jsonl"); printf "%s\n" "$l" >> "$d/retried.jsonl" # its last test line now one of its Test step
    if testkept "$p" 7; then echo "test step: kept"; else echo "test step: not kept"; fi'
  [ "$(grep -E '^(carried|before review|test step):' "$T/$CASE/run.out" | paste -sd , -)" = "carried: go= runs=1,before review: not kept,test step: kept" ] \
    || fail "a card with a carried review did not run its tests before the review, or testkept() took up a block before the review (or refused one in the Test step): $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "test" and .before == "review") | .result')" = pass ] || fail "the run with a carried review wrote no pass line before review: $(st 'select(.step == "test") | tojson')"
}

# The tests before the review fail, and their first run moves main and marks the new main red (an entry of another
# card, cnew): cardfailed() fits #7 onto that main (again), where pretest() runs no test and the card goes to its
# review. The stub's later runs pass and clear the mark, so the Test step and the landing go on. Bug it catches: the
# run again after the fit never asked whether main is red now, and ran the tests on a main marked red.
t_pretestredagain() {
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; echo "$GO" > "$STUB/review.1"; steps() { st "select(.issue == 7 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo x >> "$STUB/tests"; r=$(wc -l < "$STUB/tests"); [ "$r" -le 2 ] || { rm -f "$ST/mainred.json"; exit 0; }
    [ "$r" != 1 ] || { echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qnm "main moves"
      jq -cn --arg s "$(git -C "$R" rev-parse HEAD)" "{reds: [{sha: \$s, cases: [{case: \"z.test.sh: other\"}], card: \"cnew\"}]}" > "$ST/mainred.json"; }
    echo "a.test.sh: one failed"; exit 1' > "$STUB/test-cmd"
  # loop: only card()'s loop fits the card onto the moved main in cardfailed() (settle()) and comes back to pretest() with again
  loop run --only 7 >/dev/null 2>&1
  [[ $(steps) == "picked ok,worktree ok,brief ok,build ok,test fail,review GO,"* ]] \
    || fail "the tests before the review ran again on a main marked red after the fit onto it, or the card did not go on to its review: $(steps)"
}

# The tests before the review wait for a test slot (a pool of one slot, which another run holds), and while they wait
# another card marks main red (cnew), then that run gives the slot back. pretest() goes on to the review with no test
# run and no test line, and the merge in doubt (c7.whole) stays for the Test step. Bugs it catches: tests() ran the
# tests once it had the slot, as pretest() asked whether main is red only before the wait; the run that ran nothing
# lost <worktree>.whole, so the Test step kept passes of a merge in doubt.
t_pretestslotred() {
  local f
  setup "[$(issue 7 2026-01-01)]"; : > "$STUB/pretests"; fx_wt 'echo seven >> a.txt' b.txt base
  echo 'merge in doubt: a test' > "$FXWT.whole"
  mkdir -p "$T/$CASE/slots"; exec {f}>>"$T/$CASE/slots/1"; flock -n "$f" || fail "slot 1 could not be taken"
  # The other run polls the card's live record: only a wait inside the real tests() shows main going red after
  # pretest() asked and before the command starts; a call of the check alone cannot show where tests() asks it.
  ( wait_until "grep -qs 'waiting for a test slot' '$T/$CASE/cards/c7.live'"
    jq -cn --arg s "$(git -C "$R" rev-parse HEAD)" '{reds: [{sha: $s, cases: [{case: "z.test.sh: other"}], card: "cnew"}]}' > "$ST/mainred.json"
    flock -u "$f" ) &
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'cd "$R"; c=c7 n=7 wt=$FXWT issue="{}" br="" pretested="" tbefore="" pretfix="" fin="" trc="" voids=0 pass=1 tfix="" fixed=0
    unset CONVEYOR_TEST_SLOT CONVEYOR_CARD; export CONVEYOR_TEST_POOL=1:$T/$CASE/slots; pretest; echo "go=$go runs=$(cat "$STUB/tests" 2>/dev/null | wc -l)"'
  wait $!; exec {f}>&-
  [ "$(grep '^go=' "$T/$CASE/run.out")" = "go= runs=0" ] && [ -z "$(st 'select(.step == "test")')" ] \
    || fail "pretest() ran the tests on a main marked red while it waited for its slot, or did not go on to the review: $(cat "$T/$CASE/run.out") $(st 'select(.step == "test") | tojson')"
  [ "$(cat "$FXWT.whole" 2>&1)" = 'merge in doubt: a test' ] || fail "the run that ran nothing lost c7.whole: $(cat "$FXWT.whole" 2>&1)"
}

# A wait for main or the machine in the tests before the first review (cardfailed() with tbefore set by pretest()),
# and each run on main in the wait for main (mainwait()), have start lines marked before "review"; in the Test step
# (no tbefore) they have none. cardfailed() runs its main and machine routes with each step around the wait stubbed.
# Bug it catches: those start lines had no before, so the Board drew the wait as the Test step and the reviews still
# to come as skipped (track.jq). The fit onto main after that wait (settle()) waits to begin test, not land, in the
# tests before the review, and began() and caphold() mark that step's start lines (the real ones, record() stubbed).
# Bug it catches: settle() wrote its start lines with of: "land", so the Board drew a card with no review as landing.
t_pretestwaitmark() {
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none
  setup '[]'
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'cd "$R"; c=c7 n=7 wt=$T/$CASE/c7 rc=1 own="" sec=1 mainsec=0 br="" sprompt="" issue="" tfix="" fixed=0 REPAIRED=""
    echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true}" > "$wt.claim"
    ( record() { echo "mark $3 $5"; }; locked() { :; }; wakeloop() { :; }; sleep() { rm -f "$wt.capheld"; }
      for tbefore in review ""; do began "$c" "$n" test; LOOPCARD=1 caphold "$c" "$n" "$wt" test; began "$c" "$n" land; done )
    depsmissing() { :; }; voidrun() { return 1; }; testfails() { :; }; repairlane() { return 1; }; holdwaited() { :; }; mainwaited() { :; }
    verdicts() { echo "{\"mainRun\":{\"sha\":\"abc\"},\"verdicts\":[{\"case\":\"a.test: one\",\"verdict\":\"main\"}]}"; }
    record() { [ "$3" != start ] || echo "waitstart $5"; }; failline() { :; }; testrulespass() { :; }; unmate() { :; }; redbrief() { :; }; settle() { echo "settle $5"; return 1; }
    for WAITROUTE in main machine; do testroute() { echo "$WAITROUTE"; }; for tbefore in review ""; do cardfailed || :; done; done
    redlisted() { return 1; }; mainprobe() { m="{\"sha\":\"s1\",\"sec\":1}"; r=1; sha=""; }; probelet() { :; }; record() { echo "record $3 $5"; }
    for tbefore in review ""; do mainwait "$wt" 0000 "a.test: one"; done'
  [ "$(grep '^settle' "$T/$CASE/run.out" | paste -sd , -)" = 'settle test,settle land,settle test,settle land' ] \
    || fail "cardfailed()'s fit onto main after its wait (main, then machine; tbefore review, then none) did not wait to begin test only in the tests before the review: $(cat "$T/$CASE/run.out")"
  [ "$(grep '^mark start' "$T/$CASE/run.out" | paste -sd , -)" = 'mark start {"of":"test","before":"review"},mark start {"of":"test","waitFor":"cap","before":"review"},mark start {"of":"land"},mark start {"of":"test"},mark start {"of":"test","waitFor":"cap"},mark start {"of":"land"}' ] \
    || fail "began() and caphold() (test, a cap hold in test, then land; tbefore review, then none) did not mark the test step's start lines before review only in the tests before the review: $(cat "$T/$CASE/run.out")"
  [ "$(grep '^waitstart' "$T/$CASE/run.out" | paste -sd , -)" = 'waitstart {"of":"test","before":"review"},waitstart {"of":"test"},waitstart {"of":"test","before":"review"},waitstart {"of":"test"}' ] \
    || fail "cardfailed()'s wait for main or the machine (main, then machine; tbefore review, then none) did not mark its start line before review only in the tests before the review: $(cat "$T/$CASE/run.out")"
  [ "$(grep '^record' "$T/$CASE/run.out" | paste -sd , -)" = 'record start {"of":"test","mainRun":{"sha":"s1","sec":1},"before":"review"},record start {"of":"test","mainRun":{"sha":"s1","sec":1}}' ] \
    || fail "mainwait()'s line of a run on main (tbefore review, then none) did not mark it before review only in the tests before the review: $(cat "$T/$CASE/run.out")"
}
