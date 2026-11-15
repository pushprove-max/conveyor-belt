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
    'Four checks hold on every review:'; do
    grep -qF -- "$l" "$a.flat" || fail "the review prompt lacks: $l"
  done
  # The check's bullet wraps onto indented lines: read it with runs of spaces made one.
  l='- a test that only finds text in a source file (a regex match on a file it reads, a `grep -q` on a script), where the behaviour could be run, is a finding: it passes when nothing uses that text. One whose one-line comment says no behaviour can be run (a stylesheet rule in a test with no layout) is not.'
  tr -s ' ' < "$a.flat" | grep -qF -- "$l" || fail "the review prompt lacks: $l"
  ! grep -qF 'as its own finding' "$a.flat" || fail "the review prompt still asks for each place of one mistake as its own finding"
  # The card rules the reviewer is handed come after that introduction.
  grep -qx '# Rules' "$a" || fail "the reviewer was not handed the card rules"
  # The user-visible and approved-scope lines, word for word as they were (owner and product paths filled in).
  cat > "$a.want" <<'EOF'
A problem outside the issue is one line `NEW CARD: what` and never holds the verdict. Write no other line: any other
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
