#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what the card reviewer is told.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: the reviewer is not told what P0, P1, P2 and P3 mean (with no P3, it never reports a minor finding), so the same finding changes level between rounds; one
# mistake in several places becomes several findings; a review says only that tests were not run; the card rules'
# reply lines read as instructions to the reviewer; the lines about user-visible changes and the approved scope
# changed while the rest was rewritten; the reviewer is not told that a test that only finds text in a source file,
# where the function it is for could be run, is a finding (the change below adds one, and its review must be told).
t_reviewprompt() {
  setup "[$(issue 7 2026-01-01)]"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  # The build adds a runnable function and a test that only greps its source.
  printf '%s\n' 'printf "%s\n" "double() { echo \$((\$1 * 2)); }" > f.sh; printf "%s\n" "grep -q \"1 \\* 2\" f.sh" > f.test.sh' > "$STUB/build"
  echo "$GO" > "$STUB/review.1"; loop run >/dev/null || fail "run exited non-zero"
  [ "$(git -C "$R" show HEAD:f.test.sh 2>/dev/null)" = 'grep -q "1 \* 2" f.sh' ] || fail "the reviewed change does not hold the source-text-only test"
  local a=$STUB/asked l
  [ -s "$a" ] || fail "the reviewer was asked nothing"
  for l in '- P0: the change breaks main, loses data or opens a security hole.' \
    '- P1: the change does not do what the issue asks, or breaks behaviour the project uses today.' \
    '- P2: a real defect with a limited effect.' \
    '- P3: a real but minor defect with no wrong result that users or the next card meet (for example a misleading'; do
    grep -qxF -- "$l" "$a" || fail "the review prompt does not define the level: $l"
  done
  # The sentences wrap across lines; read the prompt as one line.
  tr '\n' ' ' < "$a" > "$a.flat"
  for l in 'One mistake is one finding: name the other places in the same finding.' \
    'Do not write that tests or builds were not run.' \
    "The card rules, under \`# Rules\` below when a card has them, are the builder's standard: hold the change to them. Their lines about how to write a reply are for the builder only." \
    'Each proof ends with `At <file:line>: ` and the text of that line in backticks: the one line of the worktree that makes the proof true.' \
    'Four checks hold on every review:'; do
    grep -qF -- "$l" "$a.flat" || fail "the review prompt lacks: $l"
  done
  # The check's bullet wraps onto indented lines: read it with runs of spaces made one.
  l='- a test that only finds text in a source file (a regex match on a file it reads, a `grep -q` on a script), where the behaviour could be run, is a finding: it passes when nothing uses that text. One whose one-line comment says no behaviour can be run (a stylesheet rule in a test with no layout) is not.'
  tr -s ' ' < "$a.flat" | grep -qF -- "$l" || fail "the review prompt lacks: $l"
  ! grep -qF 'as its own finding' "$a.flat" || fail "the review prompt still asks for each place of one mistake as its own finding"
  # The card rules the reviewer is handed come after that introduction.
  grep -qx '# Rules' "$a" || fail "the reviewer was not handed the card rules"
  # Bug (#779): the reviewer is not told that a test checks its behaviour directly, and that a proxy check with no
  # comment saying why is a P3 finding. This reads the prompt of the case's one `loop run`, not the rules file: only the
  # prompt the loop hands the reviewer shows the rule reaches the review (the file alone could be left out of it).
  sed -n '/^# Rules$/,/^# Issue #7:/p' "$a" | grep -qF 'checks the behaviour it protects directly. A test that runs other test files or the suite runner, runs the real loop, or polls a real process until a condition holds says why in a comment beside it: what a direct check cannot show. A reviewer flags one with no such comment as P3.' \
    || fail "the reviewer's card rules lack the direct-check rule"
  # The user-visible and approved-scope lines, word for word as they were (owner and product paths filled in), with
  # the ROLLOUT line between NEW CARD and them.
  cat > "$a.want" <<'EOF'
A problem outside the issue is one line `NEW CARD: what` and never holds the verdict. A step an operator must take,
in order, for the change to work once deployed (a migration before the deploy, a new environment value, a flag) is
no defect: write it as one line `ROLLOUT: <the action> | <what fails without it> | <file:line>`. It never holds the
verdict, and a defect is always a finding, never a ROLLOUT line. Write no other line: any other
line is read as a finding, except the two that end the review. Second to last line, exactly: `USER-VISIBLE: no`, or
`USER-VISIBLE: yes: <one sentence: what a customer or staff member would see or do differently>`. Answer it from
the change itself, whatever the issue says. A line in the issue starting `Visible change approved:` is the
owner's yes to such a change: the answer is still yes, and a condition in that line that the change does not meet
is a finding. A missing approval line is not a finding: report a visible change on the USER-VISIBLE line only.
Answer the same whatever the change touches: only a change to product code (src/, shared/, lambdas/, infra/, web/, ml/, tests aside)
waits for that yes, but every review gives the line.
Approve before build. A product issue may hold a section headed `## What customers or staff
will see`: the screen, message or document, what it shows today and what it will show; or the one line `Nothing
visible changes.` An issue whose section names a change and has no `Visible change approved:` line is not picked: it
waits in "Needs you" to be approved before the build. Once approved, the build is held to that section, no more and
no less: for a card that touches product code, the reviewer answers on the USER-VISIBLE line whether what the change
shows matches it. A match lands with no second ask; any difference (more, less or other, wording included) stops the
card with its patch kept, and the ask names the difference only. An issue with no section, or whose section says
nothing visible changes, stops after review for Dana's yes when its change is visible, as before.
Last line, exactly: `VERDICT: GO` or `VERDICT: NO-GO`.
EOF
  grep -qF -- "$(tr '\n' ' ' < "$a.want")" "$a.flat" || fail "the review prompt's user-visible and approved-scope lines changed: $(diff <(sed -n '/^A problem outside the issue/,/^Last line, exactly/p' "$a") "$a.want")"
  # Its pack sets no review.proof: the realistic-proof bar is off (t_reviewproof, below).
  jq -e '.review.proof == null' "$R/.conveyor/project.json" >/dev/null || fail "the test pack sets review.proof"
  proofcheck unset
}

# The realistic-proof bar is the pack's review.proof, off unless the project sets it. Bugs: a project that never
# chose the bar (unset, or any) has findings with a contrived proof sent to UNPROVEN; a project that set real is
# not told the bar, so a finding whose proof needs a hand-paused command, a stub built to fail or an input nobody
# produces holds the verdict, or a security finding loses its exemption; a pack with another value passes the check
# and the bar is silently off.
# Each value is a case of its own on a main of its own, so they run side by side: unset is t_reviewprompt's review
# (its pack sets no review.proof), any and real are reviewproofany and reviewproofreal, and the check is reviewproof.
proofrun() { # <any|real>: one card reviewed with review.proof so; its review prompt checked
  setup "[$(issue 7 2026-01-01)]"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"; tune --arg v "$1" '.review.proof = $v'
  loop run 1 >/dev/null 2>&1 && [ -s "$STUB/asked" ] || fail "review.proof $1: the run failed or the reviewer was asked nothing"
  proofcheck "$1"
}
proofcheck() { # <unset|any|real>: the review prompt in $STUB/asked holds the bar for that review.proof, in its place
  local a=$STUB/asked v=$1 l
  local bar="A finding's proof must happen with what the project really runs (its real config, commands and inputs)." \
    stub='A proof that needs a command paused by hand, a stub built to fail, or an input nobody in the project produces goes on an `UNPROVEN:` line instead.' \
    sec='A security finding (a way past a check, or to read or change data without the right to) is exempt: it stays a finding with any proof that can be reproduced.'
  tr '\n' ' ' < "$a" > "$a.flat"
  if [ "$v" = real ]; then
    for l in "$bar" "$stub" "$sec"; do grep -qF -- "$l" "$a.flat" || fail "review.proof real: the review prompt lacks: $l"; done
    grep -qF 'holds the verdict. A finding' "$a.flat" || fail "review.proof real: the bar is not in its place after the UNPROVEN line"
  else
    ! grep -qiE 'really runs|paused by hand|security finding' "$a.flat" || fail "review.proof $v: the review prompt holds the realistic-proof bar"
    grep -qF 'holds the verdict. After each finding' "$a.flat" || fail "review.proof $v: the prompt's text around the bar's place is broken"
  fi
}
t_reviewproofany() { proofrun any; }
t_reviewproofreal() { proofrun real; }
t_reviewproof() {
  local out; setup '[]'
  # Any other value is refused by check, saying which field and what it takes.
  out=$(tuned '.review.proof = "strict"' loop check 2>&1) && fail "check passed a pack whose review.proof is strict"
  grep -qF '.review.proof: "strict" is not one of ["any","real"]' <<<"$out" || fail "check did not say why it refused review.proof: $out"
  tuned '.review.proof = "real"' loop check >/dev/null 2>&1 || fail "check refused review.proof real"
}

# Bugs (#1749): a finding whose proof quotes code the reviewer did not read reaches the judge looking like any other: the
# quote of a line the staged tree does not have (other text, a line past the end, a file it lacks), or a finding with no
# quote at all, is marked as true. It calls proofline(), judgemarks() and judgefindings() alone: no card runs.
t_proofline() {
  local w=$T/$CASE/w m x
  mkdir -p "$w" && git -C "$w" init -q && printf '%s\n' 'one' '  two   words  ' 'three' > "$w/a.txt" && git -C "$w" add -A \
    && git -C "$w" -c user.name=t -c user.email=t@example.com commit -qm base && printf '%s\n' 'one' '  two   words  ' 'changed' > "$w/a.txt" \
    && git -C "$w" add -A && printf '%s\n' 'unstaged' > "$w/a.txt" || fail "the worktree could not be made"
  printf '%s\n' \
    '[P1] a.txt:3 f1 match. Proof: p. At a.txt:3: `changed`' \
    '[P1] a.txt:3 f2 differs, the text of the file on disk is not the staged tree. Proof: p. At a.txt:3: `unstaged`' \
    '[P1] a.txt:3 f3 differs, the line is the one before the change. Proof: p. At a.txt:3: `three`' \
    '[P1] a.txt:9 f4 differs, past the end. Proof: p. At a.txt:9: `changed`' \
    '[P1] gone.txt:1 f5 differs, no such file. Proof: p. At gone.txt:1: `one`' \
    '[P1] a.txt:2 f6 match, runs of spaces made one. Proof: p. At a.txt:2: `two words`' \
    "[P1] $w/a.txt:1 f7 match, the whole path of the worktree. Proof: p. At $w/a.txt:1: \`one\`" \
    '[P1] a.txt:1 f8 match, the last At part is the one read. Proof: At a.txt:3: `three`. At a.txt:1: `one`' \
    '[P1] a.txt:1 f9 none, no At part. Proof: p' \
    '[P1] a.txt:1 f10 none, no quote. Proof: p. At a.txt:1: one' \
    'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$w.review"
  # shellcheck disable=SC2034 # STE and TRYFOLD (lib/session.sh's) are read by the sourced lib/review.sh
  m=$(eval "$(grep -E '^(ROLLOUT|NOTFINDING|RX)=' "$SRC/lib/prompts.sh")"; STE='' TRYFOLD=''; . "$SRC/lib/review.sh"; . "$SRC/lib/donewhen.sh"; judgemarks "$w" '[]')
  [ "$(jq -r 'map(.proof) | join(" ")' <<<"$m")" = 'match differs differs differs differs match match match none none' ] \
    || fail "the findings' proof lines are not match, differs x4, match x3, none x2 in order: $(jq -c 'map(.proof)' <<<"$m")"
  # The mark reaches the judge's message, beside the place.
  printf '%s\n' "$m" > "$w.judge.marks"
  # shellcheck disable=SC2034 # STE and TRYFOLD (lib/session.sh's) are read by the sourced lib/review.sh
  x=$(eval "$(grep -E '^(ROLLOUT|NOTFINDING)=' "$SRC/lib/prompts.sh")"; STE='' TRYFOLD=''; . "$SRC/lib/review.sh"; judgefindings "$w")
  grep -qF 'F1 [inside the diff; proof line: match] [P1] a.txt:3 f1' <<<"$x" \
    && grep -qF 'F4 [outside the diff; proof line: differs] ' <<<"$x" && grep -qF 'F9 [outside the diff; proof line: none] ' <<<"$x" \
    || fail "the judge's message lacks the proof line marks: $(grep '^F' <<<"$x")"
}

# Bug (#1749): the review's record line counted only the findings the review still held as findings: one the judge
# declined, ruled outside or sent to the self-heals list (a DECLINED, OUTSIDE or SELFHEALS line), or listed as minor (MINOR),
# was left out, so the counts fell short and the judge's reason, which can hold backticks, was read as part of the quote.
# It calls proofline() alone, on a review as the judge leaves it.
t_proofdeclined() {
  local w=$T/$CASE/w m
  mkdir -p "$w" && git -C "$w" init -q && printf '%s\n' 'one' 'two' > "$w/a.txt" && git -C "$w" add -A || fail "the worktree could not be made"
  printf '%s\n' \
    '[P1] a.txt:1 kept. Proof: p. At a.txt:1: `one`' \
    'DECLINED: [P1] a.txt:1 declined, match. Proof: p. At a.txt:1: `one` (judge: claim wrong: `one` is there)' \
    'DECLINED: [P1] a.txt:2 declined, differs. Proof: p. At a.txt:2: `three` (judge: claim wrong)' \
    'OUTSIDE: [P2] a.txt:2 outside, none. Proof: p (judge: old code)' \
    'SELFHEALS: [P2] a.txt:2 heals, match. Proof: p. At a.txt:2: `two` (judge: harm: it fixes itself)' \
    'MINOR: [P3] a.txt:1 minor, differs. Proof: p. At a.txt:1: `two`' \
    'USER-VISIBLE: no' 'VERDICT: GO' > "$w.review"
  # NOTFINDING is read by the sourced lib/donewhen.sh, and its line of prompts.sh expands ROLLOUT, so both are loaded.
  m=$(eval "$(grep -E '^(ROLLOUT|NOTFINDING)=' "$SRC/lib/prompts.sh")"; . "$SRC/lib/donewhen.sh"; proofline "$w" | tr '\n' ' ')
  [ "$m" = 'match match differs none match differs ' ] \
    || fail "the proof lines of a kept, a declined (x2), an outside, a self-heals and a minor finding are not match match differs none match differs: $m"
}

# Bug (#1749): the review's record line leaves out how many findings quoted a true line, so the share of proofs the
# reviewer did not read cannot be measured. A whole card run, as only card() writes the line.
t_prooflines() {
  setup "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P1] a.txt:1 wrong word. Proof: p. At a.txt:1: `one`' '[P1] a.txt:1 other. Proof: p. At a.txt:1: `two`' '[P1] a.txt:1 third. Proof: p' \
    'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  # loop: the review's line is written by card(), after its sessions; no function shows what that line holds
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "review") | .proofLines | tojson' | head -n 1)" = '{"match":1,"differs":1,"none":1}' ] \
    || fail "the first review's line does not count one finding of each proof line: $(st 'select(.step == "review") | .proofLines | tojson' | head -n 1)"
}
