#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: landing conflicts, ports, retries and kept work.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# A line of a build stub: the session that ports a card after its landing conflict moves main's a.txt again, so the
# card's landing conflicts once more and it blocks for the owner (a case that goes on to `retry` it).
AGAIN='if grep -q "^# Landing conflict" "$STUB/brief"; then echo TWO > "$R/a.txt"; git -C "$R" commit -qam again; fi'

# Bugs: a card that passed its review is thrown away when another change landed on its lines first; the
# rebuild starts from the card's stale tree, or without the card's patch and the conflict message; its result lands
# unreviewed, or over the other change; a card is rebuilt and ported more than once; a NO-GO on the review after the rebuild
# gets a fix round instead of landing with follow-ups; a card with no conflict runs an extra session. Each kind is a
# case of its own on a main of its own (rebase, rebasetwice, rebaseclean, rebasenogo, rebasebig, rebaseempty), so they
# run side by side.
# rebasesetup <issue>: a fresh main with that one issue, every review a GO; the build adds a line, and its rebuild
# after a landing conflict ($STUB/rebuild) keeps what it was handed.
rebasesetup() {
  setup "[$(issue "$1" 2026-01-01)]"; for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  # The build adds a line; meanwhile main changes the line beside it. The rebuild holds both.
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Landing conflict' "$STUB/brief"; then cp "$STUB/brief" "$STUB/rebrief"; cat a.txt > "$STUB/started-from"
  cp "$(sed -n 's/^The file \(.*\.patch\), made against commit [0-9a-f]*\.$/\1/p' "$STUB/brief")" "$STUB/repatch"; eval "$(cat "$STUB/rebuild")"
else echo two >> a.txt; fi
EOF
}
t_rebase() {
  rebasesetup 7
  echo 'printf "ONE\ntwo\n" > a.txt' > "$STUB/rebuild"; echo 'ONE other' > "$STUB/move"
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start test start start rebase start review start test start landed pushed issue " ] || fail "steps of a card that conflicts at landing: $(st '"\(.step) \(.reason)"' | tr '\n' ',')"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "$(wc -l < "$STUB/sessions") sessions and $(wc -l < "$STUB/reviews") reviews, not 2 and 2"
  [ "$(cat "$STUB/started-from")" = ONE ] || fail "the rebuild did not start from main as it stands: $(cat "$STUB/started-from")"
  grep -q '^rebase onto main conflicts: ' "$STUB/rebrief" && grep -qx '+two' "$STUB/repatch" && grep -q '^# Issue #7:' "$STUB/rebrief" \
    || fail "the rebuild session was not handed the issue, the conflict message and the file that holds the card's patch"
  grep -qx '+two' "$STUB/rebrief" && fail "the rebuild's prompt holds the patch itself, so it grows with the diff"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(git -C "$R" log -1 --format=%s HEAD~1)" = other ] || fail "the card did not land on top of the other commit"
  [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "the landed tree does not hold both changes, main is dirty, or the worktree is left"
  [ "$(st 'select(.step == "rebase") | [.result, .tokens.claude, (.reason | startswith("rebase onto main conflicts: "))] | tojson')" = '["ok",35,true]' ] || fail "rebase line: $(st 'select(.step == "rebase")')"
  recok "$ST/cards.jsonl" "a card rebuilt after a landing conflict (its rebase line)"
  [ "$(loop cards | jq -c '.cards[0] | [.step, .reviews, (.steps | map(.step) | join(" "))]')" = '["landed",2,"build review test rebase review test"]' ] || fail "dashboard row: $(loop cards)"
}

# Bug: after a GO on the review of a port whose earlier loop ended on a NO-GO, a test fix and the
# GO after it landed the card with nothing filed: the earlier loop's findings were lost.
t_portfix() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$NOGO3" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  echo "echo two >> a.txt; $AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q '^rebase onto main conflicts' || fail "#8 was not blocked on its landing conflict: $(steps 8)"
  echo "$GO" > "$STUB/review.5"; echo "$GO" > "$STUB/review.6"
  # The third run fails, and its run again too (tests()), so the test fix starts.
  echo 'echo x >> "$STUB/tests"; case $(wc -l < "$STUB/tests") in 3|4) echo "FAIL widget.test.ts"; exit 1 ;; esac' > "$STUB/test-cmd"
  loop retry 8 >/dev/null && loop run >/dev/null || fail "run of the retried #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test fail,fix ok,review GO,test pass,landed ok," ] \
    && [ "$(st 'select(.issue == 8 and .step == "landed") | .leftover')" = true ] \
    && [ "$(tail -n 3 "$STUB/filed" | jq -r .title | tr '\n' '|')" = '[P0] a.txt:1 wrong word|b.txt:22 no mark here|[P2] c.txt:3 a nit|' ] \
    || fail "a test fix after the port's GO lost the earlier loop's findings: $(steps 8)"
  [ "$(st 'select(.issue == 8 and .step == "filed") | .followups | length')" = 3 ] || fail "no filed line names the three follow-ups: $(steps 8)"
  recok "$ST/cards.jsonl" "a card that landed on a NO-GO (its filed line, and its landed line with leftover and followups)"
}

# Bugs: the port's landing conflicts too (its session moves main again) and something lands, or a second port runs:
# it blocks for the owner. A NO-GO on the one review of a port (a finished loop stopped only by a landing conflict)
# lands with follow-ups as if it were a last review, instead of being fixed and going round the loop as any card's.
t_port() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$NOGO3" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  echo "echo two >> a.txt; $AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,blocked blocked," ] \
    && st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' && [ "$(wc -l < "$STUB/sessions")" = 4 ] \
    && [ "$(git -C "$R" log -1 --format=%s)" = again ] || fail "a conflict after the port did not block for the owner: $(steps 8)"
  echo "$NOGO" > "$STUB/review.5"; echo "$GO" > "$STUB/review.6"; f=$(wc -l < "$STUB/filed")
  loop retry 8 >/dev/null && loop run >/dev/null || fail "run of the retried #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] \
    && [ "$(wc -l < "$STUB/filed")" = "$f" ] && [ "$(st 'select(.issue == 8 and .step == "landed") | has("leftover")')" = false ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "TWO two two " ] \
    || fail "a NO-GO on the port's review was not fixed and reviewed again before landing: $(steps 8)"
  loop check || fail "the records do not check"
}

# A last review's NO-GO whose landing conflicts, and conflicts again after its port: its three follow-ups are
# withdrawn as not planned each time, their findings kept.
t_resumeport() {
  resumesetup 8; for i in 1 2 3; do moved "${i/3/}" "$NOGO3" > "$STUB/review.$i"; done; echo "$GO" | tee "$STUB/review.4" > "$STUB/review.5"
  echo 'cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; echo two >> a.txt; '"$AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  loop run >/dev/null || fail "run of #8 exited non-zero"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts' || fail "#8 was not blocked on its landing conflict: $(steps 8)"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 100104 100105 100106 " ] && [ "$(grep -c -- '^--reason not planned --comment .*withdrawn.* #8 ' "$STUB/close-comments")" = 6 ] \
    || fail "the withdrawn follow-ups were not closed as not planned, each naming #8: $(cat "$STUB/closed" "$STUB/close-comments" 2>&1)"
  k=$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  [ "$(sed -n 2p "$k/$old.withdrawn")" = '#100102 b.txt:22 no mark here' ] && [ -s "$k/$old.patch" ] || fail "the withdrawn findings or the patch are not in the kept folder: $(ls "$k")"
  # Retried: the kept patch does not apply to main as it is now. Bug: the card was built from nothing. It is
  # still used: one session is told the patch's path and the commit it was built on, to bring the change onto main.
  # Its brief also holds the blocked card's last findings and the withdrawn follow-ups' findings.
  # GitHub also holds follow-ups withdrawn for #8 that no .withdrawn file here names (#55, closed before the file
  # existed), one this card's file names too, one of another issue (#57) and one a card of its own landed (#56).
  fu() { jq -cn --argjson n "$1" --arg p "$2" --arg f "$3" '{number:$n,title:$f,body:"Follow-up to #\($p) (Conveyor card c1-\($p)). Its last review said NO-GO.\n\nFinding: \($f)\nWhere: x\nFollow-up depth: 1"}'; }
  jq -cs . <(fu 57 80 '[P1] other.txt:1 of another issue') <(fu 56 8 '[P1] done.txt:2 landed since') <(fu 100102 8 'b.txt:22 no mark here') <(fu 55 8 '[P1] old.txt:9 an old finding') > "$STUB/closed-issues.json"
  landed 56 >> "$ST/cards.jsonl"
  # Bug: its loop had finished (a last NO-GO, follow-ups filed) and only the landing conflict stopped it, yet the
  # port went through a fresh loop of up to three reviews and two fixes. One session, one review of the port alone
  # (handed the difference between the kept patch and the ported change), the tests and the landing, which files the
  # earlier loop's findings again.
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"; echo 'cp "$PWD.port" "$STUB/port"' > "$STUB/review-cmd"
  s0=$(wc -l < "$STUB/sessions"); r0=$(wc -l < "$STUB/reviews")
  out=$(loop retry 8 && loop run) || fail "run of the retried #8 exited non-zero: $out"; n=$(wc -l < "$STUB/sessions"); rm "$STUB/review-cmd"
  [ "$n" = $((s0 + 1)) ] && [ "$(wc -l < "$STUB/reviews")" = $((r0 + 1)) ] || fail "a port of a finished loop did not get exactly one session and one review: $(steps 8)"
  grep -q '^# This review is of a port alone$' "$STUB/asked" && grep -q "^The difference is the file $T/$CASE/cards/.*-8\.port\.$" "$STUB/asked" \
    && grep -qx -- '+ TWO' "$STUB/port" && grep -qx -- ' +two' "$STUB/port" && grep -Eq '^[ +-]@@ -[0-9]' "$STUB/port" \
    || fail "the port's review was not scoped to the port, or not handed the kept patch against the ported change: $(cat "$STUB/port" 2>&1)"
  grep -q 'Change nothing else: that change finished its review loop' "$STUB/brief.$n" \
    || fail "the port session of a finished loop was not told to change nothing else"
  [ "$(st 'select(.issue == 8 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100107,100108,100109]]' ] \
    && [ "$(tail -n 3 "$STUB/filed" | jq -r .title | tr '\n' '|')" = '[P0] a.txt:1 wrong word|b.txt:22 no mark here|[P2] c.txt:3 a nit|' ] \
    || fail "a GO on the port's review did not land with the earlier loop's last NO-GO filed again: $(st 'select(.issue == 8 and .step == "landed")')"
  grep -q -- '--state closed .*--label conveyor-followup .*Follow-up to #8' "$STUB/closed-asked" && grep -qx '#55 \[P1\] old.txt:9 an old finding' "$STUB/brief.$n" \
    && [ "$(grep -c '^#100102 ' "$STUB/brief.$n")" = 1 ] && ! grep -Eq '^#(56|57) ' "$STUB/brief.$n" \
    || fail "the rebuild's brief lacks a follow-up withdrawn before any .withdrawn file, or holds one twice, a landed one or another issue's: $(grep '^#' "$STUB/brief.$n")"
  grep -q "the kept patch of card $old finished its review loop and no longer applies to main: one session brings it onto main, then one review of that port alone" <<<"$out" \
    && st 'select(.issue == 8 and .step == "worktree") | .reason' | grep -q "^the kept patch of card $old finished its review loop and no longer applies to main: one session brings it onto main" || fail "the worktree line does not say the kept patch is brought onto main: $out $(steps 8)"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test pass,landed ok," ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "TWO two " ] \
    || fail "a card whose kept patch no longer applies did not get one session, a review and a landing: $(steps 8)"
  grep -qx '\[P2\] c.txt:3 a nit' "$STUB/brief.$n" && grep -qx '#100102 b.txt:22 no mark here' "$STUB/brief.$n" \
    || fail "the rebuild's brief lacks the last review's findings or a withdrawn follow-up's finding: $(tail -n 20 "$STUB/brief.$n")"
  [ "$(cat "$k/$old.base")" != "$(git -C "$R" rev-parse HEAD)" ] && grep -q "^# This card brings the change of blocked card $old onto main$" "$STUB/brief.$n" \
    && grep -q "The patch is the file $k/$old.patch, built on commit $(cat "$k/$old.base")\. Bring that change onto main as it is now.* resolve the conflicts" "$STUB/brief.$n" \
    && ! grep -q 'from nothing\.\? *$\|Build the issue' "$STUB/brief.$n" \
    || fail "the brief of a card whose kept patch conflicts with main does not name the patch and the commit it was built on: $(tail -n 6 "$STUB/brief.$n")"
  ! grep -q 'NEW CARD: b.txt is stale' "$STUB/brief.$n" || fail "a NEW CARD line was carried into the rebuild's brief as a finding"
}

# Bug: the rebuild of a card whose diff is larger than a prompt may be fails at once with "Prompt is too
# long", and the card is blocked. The session here refuses a prompt of 1 MB; the card's diff is 3 MB.
t_rebasebig() {
  rebasesetup 11
  cat > "$STUB/build" <<'EOF'
[ "$(wc -c < "$STUB/brief")" -lt 1000000 ] || { echo "Prompt is too long" >&2; exit 1; }
yes 'a line of a large file' | head -n 140000 > big.txt
if grep -q '^# Landing conflict' "$STUB/brief"; then printf 'SEVEN\neight\n' > a.txt
  wc -c < "$(sed -n 's/^The file \(.*\.patch\), made against commit [0-9a-f]*\.$/\1/p' "$STUB/brief")" > "$STUB/patch-size"
else echo eight >> a.txt; fi
EOF
  echo 'SEVEN seventh' > "$STUB/move"
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.issue == 11 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test pass,rebase ok,review GO,test pass,landed ok," ] \
    || fail "the rebuild of a card with a 3 MB diff: $(st 'select(.issue == 11) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(cat "$STUB/patch-size")" -gt 3000000 ] && [ "$(wc -c < "$R/big.txt")" -gt 3000000 ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "SEVEN eight " ] || fail "the large card's patch file was not there for the rebuild, or its change did not land"
}

# Bug: a card whose review loop had finished (a last NO-GO, its follow-ups filed) blocked for the owner when its
# landing met a conflict, and sat there until the owner ran `retry`. It is ported in the card with no owner action:
# one session, one review of that port alone, the tests and the landing, which files the loop's findings again; the
# Board shows the port as a step, not a block. A conflict after that port blocks for the owner (t_port).
# Bug: its last NO-GO's test pass was stored nowhere (see lastsetup); here it is stored, keyed to its staged change,
# and the port, a different change, runs its tests again; it lands alone.
t_autoport() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$NOGO3" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo two >> a.txt' > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo '[ ! -e "$PWD.port" ] || { cp "$PWD.port" "$STUB/port"; cp "$PWD.ready" "$STUB/readyatport"; }' > "$STUB/review-cmd"
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,landed ok," ] \
    && [ "$(wc -l < "$STUB/sessions")" = 4 ] && [ "$(wc -l < "$STUB/reviews")" = 4 ] \
    || fail "a finished loop whose landing conflicted was not ported by one session, reviewed once, tested and landed: $(steps 8)"
  [ "$(jq -c '[.tested, .alone, (.patch | length > 0)]' "$STUB/readyatport" 2>/dev/null)" = '[true,true,true]' ] \
    || fail "the card with a last NO-GO did not store its test pass, marked alone, keyed to its staged change: $(cat "$STUB/readyatport" 2>&1)"
  [ "$(wc -l < "$STUB/tests")" = 2 ] && [ "$(st 'select(.issue == 8 and .step == "landed") | .batch')" = null ] \
    || fail "the port, a different staged change, did not run its tests, or did not land alone: $(wc -l < "$STUB/tests") runs, $(st 'select(.issue == 8 and .step == "landed")')"
  st 'select(.issue == 8 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts: ' || fail "the port's step does not name the conflict"
  grep -q '^# This review is of a port alone$' "$STUB/asked" && grep -q "^The difference is the file $T/$CASE/cards/.*-8\.port\.$" "$STUB/asked" \
    && grep -qx -- '+ ONE' "$STUB/port" && grep -qx -- ' +two' "$STUB/port" || fail "the review after the port was not of the port alone: $(cat "$STUB/port" 2>&1)"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 " ] && [ "$(st 'select(.issue == 8 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100104,100105,100106]]' ] \
    && [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] || fail "the port did not withdraw the follow-ups and file the loop's findings again at its landing: $(st 'select(.issue == 8 and .step == "landed")')"
  [ "$(loop cards | jq -c '.cards[0] | [.step, (.steps | map(.step) | join(" "))]')" = '["landed","build review fix review fix review test rebase review test"]' ] \
    && [ -z "$(st 'select(.step == "blocked")')" ] && [ ! -s "$ST/retried.jsonl" ] && loop check || fail "the port is not a step of the card's row, or it blocked or was retried: $(loop cards | jq -c '.cards[0]')"
}

# The rebuild conflicts too (main moves again during it), and so does the one port after it: blocked with the
# conflict message, nothing landed.
t_rebasetwice() {
  rebasesetup 8
  echo 'echo again > a.txt; echo "THREE$(wc -l < "$STUB/sessions")" > "$R/a.txt"; git -C "$R" commit -qam third' > "$STUB/rebuild"; echo 'TWO second' > "$STUB/move"
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.issue == 8) | .step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start test start start rebase start review start test start start rebase start review start test start blocked " ] || fail "steps of a card that conflicts three times: $(st 'select(.issue == 8) | .step' | tr '\n' ' ')"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' || fail "a conflict after the port did not block with the conflict message"
  [ "$(git -C "$R" log -1 --format=%s)" = third ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "a conflict after the port landed something, left main dirty or left the worktree"
  [ "$(wc -l < "$STUB/sessions")" = 3 ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] || fail "a card that conflicts three times was rebuilt or ported more than once"
}

# No conflict: no extra session.
t_rebaseclean() {
  rebasesetup 9; echo 'echo four >> a.txt' > "$STUB/build"
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.issue == 9) | .step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start test start landed pushed issue " ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "a card with no conflict ran an extra session: $(st 'select(.issue == 9) | .step' | tr '\n' ' ')"
}

# The review after the rebuild is a last review: its NO-GO lands the card with its finding filed, with no fix round.
t_rebasenogo() {
  rebasesetup 10; echo "$NOGO" > "$STUB/review.2"
  printf '%s\n' 'if grep -q "^# Landing conflict" "$STUB/brief"; then printf "FIVE\nsix\n" > a.txt' 'else echo six >> a.txt; fi' > "$STUB/build"; echo 'FIVE fifth' > "$STUB/move"
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.issue == 10) | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,deps ok,brief ok,start ok,build ok,start ok,review GO,start ok,test pass,start ok,start ok,rebase ok,start ok,review NO-GO,start ok,test pass,start ok,filed ok,start ok,landed ok,pushed ok,issue ok," ] || fail "a NO-GO after the rebuild: $(st 'select(.issue == 10) | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 10 and .step == "landed") | [.sha, .followups] | tojson')" = "[\"$(git -C "$R" rev-parse HEAD)\",[100101]]" ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "FIVE six " ] || fail "a NO-GO after the rebuild did not land with its follow-up: $(st 'select(.issue == 10 and .step == "landed")')"
}

# Bug: a rebuild session that ends well but leaves no change blocks the card with nothing kept: the
# reviewed change is deleted with the worktree, and retry builds from nothing.
t_rebaseempty() {
  rebasesetup 12
  printf '%s\n' 'if grep -q "^# Landing conflict" "$STUB/brief"; then :' 'else echo ten >> a.txt; fi' > "$STUB/build"; echo 'NINE ninth' > "$STUB/move"
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.issue == 12 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test pass,rebase ok,blocked blocked," ] \
    || fail "a rebuild that leaves no change: $(st 'select(.issue == 12) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  local k c; k=$(st 'select(.issue == 12 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); c=$(st 'select(.issue == 12 and .step == "blocked") | .card')
  [ -n "$k" ] && grep -qx '+ten' "$k/$c.patch" && [ "$(cat "$k/$c.base")" = "$(git -C "$R" rev-parse HEAD~1)" ] || fail "a rebuild that left no change did not keep the reviewed change as the card's patch (kept: $k)"
  tail -n 1 "$STUB/comments" | grep -q "Its work is kept as a patch: <state>/kept/${k##*/}/$c.patch (1 files, 1 KB, built on commit " || fail "the block comment does not name the reviewed patch: $(tail -n 1 "$STUB/comments")"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a rebuild that left no change left files beside the cards: $(ls "$T/$CASE/cards")"
}

# Bugs: a card blocked at the visible-change check after a last review's NO-GO lands from `retry` with its
# leftover findings filed nowhere; a follow-up withdrawn when its card did not land is closed as completed and its
# finding is lost; the card built after a retry is not told the blocked card's last findings or the withdrawn
# follow-ups' findings; a kept patch that no longer applies to main is forced in, or the fallback does not say it
# builds from nothing; a card blocked on a failed step is built again from nothing though its patch still applies.
# Each kind is a case of its own on a main of its own (resume, resumeport, resumestep, resumeunread, resumeyes), so
# they run side by side.
resumesetup() { # <issue>: a fresh main with that one issue; YES, a review's visible line; steps <issue>, its lines
  setup "[$(issue "$1" 2026-01-01)]"; YES='USER-VISIBLE: yes: guests see a new Pay button'
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
}
t_resume() {
  resumesetup 7
  # A visible change stops only a card that touches product code: #7 and #11 change a file under web/ too.
  echo 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  # Three NO-GOs, the last one visible: blocked for the owner's yes, nothing filed. Approved and retried: it lands from the
  # kept patch with no build and no review, and files the last review's finding as a follow-up at that landing.
  for i in 1 2 3; do printf '%s\n' "$(moved "${i/3/}" '[P1] a.txt:1 wrong word')" "$YES" 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  loop run >/dev/null || fail "run exited non-zero"
  st 'select(.step == "blocked") | .reason' | grep -q "needs Dana's yes" && [ ! -e "$STUB/filed" ] || fail "#7 was not blocked for Dana's yes with nothing filed: $(steps 7)"
  issue 7 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-11"]' > "$STUB/issues.json"
  loop retry 7 | grep -q 'lands from the kept patch .*-7\.patch, with no build and no review' || fail "retry does not say the approved next card lands from the kept patch"
  loop run >/dev/null || fail "run of the retried #7 exited non-zero"
  [ "$(st 'select(.issue == 7 and '"$NOMARK"') | .step' | tr '\n' ' ')" = "picked worktree brief test landed " ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    || fail "the retried card was built or reviewed again: $(steps 7)"
  [ "$(st 'select(.issue == 7 and .step == "landed") | [.sha, .leftover, .followups] | tojson')" = "[\"$(git -C "$R" rev-parse HEAD)\",true,[100101]]" ] \
    && [ "$(jq -r .title "$STUB/filed")" = '[P1] a.txt:1 wrong word' ] && jq -r .body "$STUB/filed" | grep -q '^Follow-up to #7 (Conveyor card ' \
    || fail "a card landed by retry after a last review's NO-GO did not file its leftover finding: $(steps 7) $(cat "$STUB/filed" 2>&1)"
  recok "$ST/cards.jsonl" "a card landed by retry on a NO-GO (its landed line with leftover and followups)"
}

# A failed step (here the review, tried twice) with a patch that still applies: one session that starts from the patch.
t_resumestep() {
  resumesetup 9; echo "$GO" > "$STUB/review.3"; echo 'exit 3' > "$STUB/review-cmd"
  echo 'if grep -q "^# This card resumes blocked card" "$STUB/brief"; then git diff --cached --name-only > "$STUB/resumed-with"; else echo nine > n.txt; fi' > "$STUB/build"
  loop run >/dev/null; st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q '^review 1: ' || fail "#9 was not blocked on its failed review: $(steps 9)"
  rm "$STUB/review-cmd"; loop retry 9 >/dev/null && loop run >/dev/null || fail "run of the retried #9 exited non-zero"
  [ "$(st 'select(.issue == 9 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test pass,landed ok," ] && [ "$(cat "$STUB/resumed-with" 2>&1)" = n.txt ] \
    && [ "$(cat "$R/n.txt")" = nine ] || fail "a card blocked on a failed step did not resume from its kept patch with one session: $(steps 9) $(cat "$STUB/resumed-with" 2>&1)"
  st 'select(.issue == 9 and .step == "worktree") | .reason' | grep -q '^resumed from the kept patch of card ' && loop check || fail "the worktree line does not say the card resumed, or the records do not check: $(steps 9)"
}

# Bug (#585): retry gave back an issue while its blocked card's process was still ending. That process then wrote a
# second blocked line after its lines were moved out, and could not keep its change, the worktree already taken.
# Here the card's worktree line names a live process: retry refuses and names it, changing nothing; once the
# process has ended, retry gives the issue back and the next card starts from the kept patch.
t_retryending() {
  local p t k before kept
  resumesetup 11; echo 'exit 3' > "$STUB/review-cmd"; echo 'echo eleven > e.txt' > "$STUB/build"
  loop run >/dev/null; k=$(st 'select(.issue == 11 and .step == "blocked") | "\($ENV.ST)/\(.kept)"')
  [ -s "$k/$(st 'select(.issue == 11 and .step == "blocked") | .card').patch" ] || fail "#11 was not blocked with a kept patch: $(steps 11)"
  sleep 60 & p=$!; t=$(p_started "$p") # sleep: a stand-in for the blocked card's process, still ending
  jq -c --argjson p "$p" --arg t "$t" 'if .step == "worktree" then .pid = $p | .started = $t else . end' "$ST/cards.jsonl" > "$ST/cards.new" && mv "$ST/cards.new" "$ST/cards.jsonl"
  before=$(cat "$ST/cards.jsonl"; ls -A "$T/$CASE/cards"); kept=$(cd "$k" && ls -A && cat ./*)
  loop retry 11 >/dev/null 2>"$STUB/refused" && fail "retry gave #11 back while its card's process $p was alive"
  grep -q "still ending (pid $p)" "$STUB/refused" || fail "the refusal does not name the card's pid $p: $(cat "$STUB/refused")"
  [ "$(cat "$ST/cards.jsonl"; ls -A "$T/$CASE/cards")" = "$before" ] && [ ! -s "$ST/retried.jsonl" ] && [ "$(cd "$k" && ls -A && cat ./*)" = "$kept" ] \
    || fail "a refused retry changed the lines, the worktrees or the kept folder"
  kill "$p"; wait "$p" 2>/dev/null
  rm "$STUB/review-cmd"; echo "$GO" > "$STUB/review.3"
  loop retry 11 | grep -q 'starts from the kept patch' || fail "retry of #11 did not go on once its card's process had ended"
  loop run >/dev/null || fail "run of the retried #11 exited non-zero"
  st 'select(.issue == 11 and .step == "worktree") | .reason' | grep -q '^resumed from the kept patch of card ' && [ "$(cat "$R/e.txt")" = eleven ] \
    || fail "the retried #11 did not start from its kept patch and land: $(steps 11)"
}

# GitHub does not answer for the withdrawn follow-ups: the brief says the list may be short.
t_resumeunread() {
  resumesetup 10; r=0; echo 'exit 3' > "$STUB/review-cmd"; echo 'cp "$STUB/brief" "$STUB/brief.10"; echo ten > t.txt' > "$STUB/build"
  loop run >/dev/null; rm "$STUB/review-cmd"; echo "$GO" > "$STUB/review.$((r + 3))"; : > "$STUB/closed-fail"
  loop retry 10 >/dev/null && loop run >/dev/null || fail "run of the retried #10 exited non-zero"; rm "$STUB/closed-fail"
  grep -q '^## The withdrawn follow-ups of this issue could not be read from GitHub$' "$STUB/brief.10" && [ -n "$(st 'select(.issue == 10 and .step == "landed") | .sha')" ] \
    || fail "a brief made while GitHub did not list the withdrawn follow-ups does not say so, or the card did not land: $(steps 10)"
}

# Bug: the owner's yes with a condition ("only for admins") landed the kept patch with no build and no
# review, though nothing had held the change against the condition. The patch is reviewed, with no build first; the
# condition it does not meet is a finding, fixed and reviewed again.
t_resumeyes() {
  resumesetup 11; r=0; echo 'echo eleven > e.txt; mkdir -p web; echo eleven > web/e.ts' > "$STUB/build"
  printf '%s\n' "$YES" 'VERDICT: GO' > "$STUB/review.$((r + 1))"
  loop run >/dev/null; st 'select(.issue == 11 and .step == "blocked") | .reason' | grep -q "needs Dana's yes" || fail "#11 was not blocked for Dana's yes: $(steps 11)"
  old=$(st 'select(.issue == 11 and .step == "blocked") | .card'); sessions=$(wc -l < "$STUB/sessions")
  issue 11 2026-01-01 | jq -c '[.body += "\nVisible change approved: r-12, only for admins"]' > "$STUB/issues.json"
  printf '%s\n' '[P1] e.txt:1 guests see it: the approval is only for admins' "$YES" 'VERDICT: NO-GO' > "$STUB/review.$((r + 2))"; printf '%s\n' "$YES" 'VERDICT: GO' > "$STUB/review.$((r + 3))"
  echo 'echo admins >> e.txt' > "$STUB/build"
  # Bug: retry said this card lands "with no build and no review", though the condition has it reviewed first.
  loop retry 11 | grep -q "reviews the kept patch .*-11\.patch against Dana's yes as the issue now gives it, with no build" || fail "retry does not say the conditionally approved kept patch is reviewed before it lands"
  loop run >/dev/null || fail "run of the retried #11 exited non-zero"
  [ "$(st 'select(.issue == 11 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] && [ "$(wc -l < "$STUB/sessions")" = $((sessions + 1)) ] \
    && [ "$(tr '\n' ' ' < "$R/e.txt")" = "eleven admins " ] || fail "a kept patch approved with a condition was not reviewed against it before landing: $(steps 11)"
  st 'select(.issue == 11 and .step == "worktree") | .reason' | grep -q "^reviewing the kept patch of card $old against the condition of Dana's yes" && loop check || fail "the worktree line does not say the kept patch is reviewed, or the records do not check: $(steps 11)"
}

# Bug: a card that files a last NO-GO's follow-ups had no <worktree>.ready, so its test pass was stored nowhere and it
# ran its tests again each time it came to the test step (the owner: passes are reused). Its pass is kept, keyed to
# its staged change: a different change (the port after its landing conflict) runs its tests (autoport); main
# moving on another file during the port's tests fits it onto main with the same change, which reuses the pass and
# starts no run (lastreuse). Either way it lands alone, with the earlier loop's findings filed.
lastsetup() { # [<line of the test stub>]
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$NOGO3" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  echo 'echo two >> a.txt' > "$STUB/build"; echo 'ONE other' > "$STUB/move"; echo "${1:-}" >> "$STUB/test-cmd"
  echo '[ ! -e "$PWD.port" ] || cp "$PWD.ready" "$STUB/readyatport"' > "$STUB/review-cmd"
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(jq -c '[.tested, .alone, (.patch | length > 0)]' "$STUB/readyatport" 2>/dev/null)" = '[true,true,true]' ] \
    || fail "the card with a last NO-GO did not store its test pass, marked alone, keyed to its staged change: $(cat "$STUB/readyatport" 2>&1)"
}
laststeps() { st "select(.issue == 8 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
t_lastreuse() {
  lastsetup '[ "$(wc -l < "$STUB/tests")" != 2 ] || { echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm "main adds b.txt"; }'
  [ "$(laststeps)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,test pass,landed ok," ] \
    && [ "$(st 'select(.issue == 8 and .step == "test") | .reused' | tr '\n' ,)" = "null,null,true," ] \
    && [ "$(wc -l < "$STUB/tests")" = 2 ] || fail "fitted onto main with the same staged change, the card ran its tests again: $(laststeps) $(wc -l < "$STUB/tests") runs"
  [ "$(st 'select(.issue == 8 and .step == "landed") | [.leftover, .batch] | tojson')" = '[true,null]' ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] \
    && [ "$(cat "$R/b.txt")" = b ] && [ "$(git -C "$R" log -1 --format=%P | wc -w)" = 1 ] && [ "$(git -C "$R" log -2 --format=%s | tail -n 1)" = "main adds b.txt" ] \
    || fail "#8 did not land alone on the main that moved, with its follow-ups: $(st 'select(.issue == 8 and .step == "landed")'; git -C "$R" log --oneline | head -3)"
}

# Bug: the earlier loop's review was put back in place of the port's own before the yes was
# checked, so a port whose visible change goes beyond its parent's yes landed on the earlier review's INHERITED: part.
t_portyes() {
  local P='Visible change approved: Dana, 2026-01-02; condition: only for admins' Y="visible to customers or staff: needs Dana's yes: "
  setup "$(jq -cs . <(issue 7 2026-01-01 | jq -c --arg l "$P" '.body += "\n\n" + $l') <(issue 100101 2026-01-02 conveyor-followup P1 | jq -c '.body = "Follow-up to #7 (Conveyor card c0-7). Its last review said NO-GO.\nFinding: x\nFollow-up depth: 1"'))"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  mkdir -p "$ST"
  { jq -cn '{card:"c0-7",issue:7,step:"review",time:"2026-11-01T00:00:00Z",tokens:{claude:0,codex:0},result:"GO",sha:"",reason:"",visible:"yes: admins see a Pay button"}'
    landed 7 '[100101]'; } > "$ST/cards.jsonl"
  echo "echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts; $AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  for i in 1 2 3; do printf '%s\n' "$(moved "${i/3/}" '[P1] a.txt:1 wrong word')" 'INHERITED: part' 'USER-VISIBLE: yes: admins see the Pay button in red' 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  printf '%s\n' 'INHERITED: part' 'USER-VISIBLE: yes: admins see the Pay button in red' 'VERDICT: GO' > "$STUB/review.4"
  loop run --only 100101 >/dev/null; st 'select(.issue == 100101 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts' || fail "#100101 was not blocked on its landing conflict: $(steps 100101)"
  printf '%s\n' 'INHERITED: beyond: guests see it too' 'USER-VISIBLE: yes: guests see a Pay button' 'VERDICT: GO' > "$STUB/review.5"
  head=$(git -C "$R" rev-parse HEAD)
  loop retry 100101 >/dev/null && loop run --only 100101 >/dev/null || fail "run of the retried #100101 exited non-zero"
  [ "$(st 'select(.issue == 100101 and .step == "blocked") | .reason' | tail -n 1)" = "${Y}guests see a Pay button (it goes beyond the yes of #7: guests see it too)" ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a port whose visible change goes beyond its parent's yes landed on the earlier review's: $(steps 100101)"
}

# Bugs: a blocked card whose change cannot be staged (an index lock) loses it with its worktree;
# a build that fails before any review keeps its patch and names it nowhere on the issue; a review that fails after
# a NO-GO and its fix deletes that NO-GO's findings; a retry that blocks before it takes up the kept patch makes the
# next retry forget the patch and the review; carried findings past a length are cut from the rebuild's brief. Each
# is a case of its own on a main of its own (kept, keptbuild, keptlong, keptevidence, keptleft, keptunread), so they
# run side by side.
t_kept() {
  setup "[$(issue 7 2026-01-01)]"
  echo 'echo two >> a.txt; : > "$(git rev-parse --git-path index.lock)"; exit 3' > "$STUB/build"
  loop run >/dev/null; wt=$T/$CASE/cards/$(st 'select(.step == "blocked") | .card')
  st 'select(.step == "blocked") | .reason' | grep -q "^build: .*could not be kept as a patch.*its worktree is left at $wt\]" && [ "$(tail -n 1 "$wt/a.txt" 2>&1)" = two ] \
    || fail "a change that could not be staged went with its worktree, or the reason does not say where it is: $(st 'select(.step == "blocked") | .reason') $(ls "$T/$CASE/cards")"
}
t_keptbuild() {
  setup "[$(issue 8 2026-01-01)]"; echo 'echo two >> a.txt; exit 3' > "$STUB/build"
  loop run >/dev/null; k=$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)"')
  grep -q '^8 --body Conveyor card .*-8 is blocked: build: ' "$STUB/comments" && grep -q "^Its work is kept as a patch: <state>/kept/${k##*/}/.*-8\.patch (1 files, 1 KB, built on commit $(git -C "$R" rev-parse HEAD))" "$STUB/comments" \
    || fail "a build that failed before any review did not name its kept patch and size on the issue: $(cat "$STUB/comments" 2>&1)"
}

# NO-GO with more findings than a brief may hold, its fix, then a review that fails: the NO-GO's findings are kept.
t_keptlong() {
  setup "[$(issue 9 2026-01-01)]"
  # 100 findings of 700 bytes: past the brief's 60000 in as few lines as that takes (each line costs the engine more
  # than its bytes do).
  local pad; pad=$(printf '%650s' '' | tr ' ' x)
  { for i in $(seq 1 100); do echo "[P1] a.txt:$i finding number $i of a very long review, $pad"; done; echo 'USER-VISIBLE: no'; echo 'VERDICT: NO-GO'; } > "$STUB/review.1"
  echo '[ "$(wc -l < "$STUB/reviews")" -lt 2 ] || exit 3' > "$STUB/review-cmd"
  loop run >/dev/null; k=$(st 'select(.issue == 9 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 9 and .step == "blocked") | .card')
  st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q '^review 2: ' && grep -q 'finding number 100 ' "$k/$old.review" && grep -q 'finding number 1 ' "$STUB/comments" \
    || fail "a review that failed after a NO-GO and its fix lost that NO-GO's findings: $(ls "$k" 2>&1)"
  [ -z "$(ls "$T/$CASE/cards")" ] || fail "a blocked card left files beside its worktree: $(ls "$T/$CASE/cards")"
  # Retried, and that card blocked before it took up the patch (its line keeps nothing); retried again: the card
  # resumes from the first card's patch, and its brief names the file that holds every carried finding.
  loop retry 9 >/dev/null || fail "retry of #9 refused"
  jq -cn '{card:"c20270101T000000-9",issue:9,step:"blocked",time:"2027-01-01T00:00:00Z",tokens:{claude:0,codex:0},result:"blocked",sha:"",reason:"worktree: the engine could not link the dependencies of the main checkout: x",kept:""}' >> "$ST/retried.jsonl"
  echo "$GO" > "$STUB/review.4"; rm "$STUB/review-cmd"
  echo 'cp "$STUB/brief" "$STUB/brief.build"; git diff --cached --name-only > "$STUB/resumed-with"; f=$(grep -o "/[^ ]*\.carried" "$STUB/brief" | head -n 1); cp "$f" "$STUB/carried"' > "$STUB/build"
  loop run >/dev/null || fail "run of the retried #9 exited non-zero"
  st 'select(.issue == 9 and .step == "worktree") | .reason' | grep -q "^resumed from the kept patch of card $old:" && [ "$(cat "$STUB/resumed-with" 2>&1)" = a.txt ] \
    && [ "$(st 'select(.issue == 9 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test pass,landed ok," ] \
    || fail "a retry after a card that blocked before taking up the patch forgot the earlier kept patch: $(st 'select(.issue == 9) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q 'finding number 1 ' "$STUB/brief.build" && ! grep -q 'finding number 100 ' "$STUB/brief.build" && [ "$(wc -c < "$STUB/brief.build")" -lt 100000 ] \
    && [ "$(grep -c 'finding number' "$STUB/carried" 2>&1)" = 100 ] && grep -q "All of it, .* lines, is in the file .*\.carried" "$STUB/brief.build" \
    || fail "carried findings were cut from the rebuild's brief with no file holding them all: $(tail -n 4 "$STUB/brief.build" | cut -c1-300)"
  [ -z "$(ls "$T/$CASE/cards")" ] && loop check || fail "the landed card left files behind, or the records do not check: $(ls "$T/$CASE/cards")"
}

# Bug: the patch is kept but one evidence file cannot be moved (here the session output), so
# the blocked line names no folder and the retry builds from nothing. The line names the folder that holds the patch.
t_keptevidence() {
  setup "[$(issue 10 2026-01-01)]"
  echo 'echo ten > t.txt; c=$(basename "$PWD"); mkdir -p "$ST/kept/$c/$c.out/x"; exit 3' > "$STUB/build"
  loop run >/dev/null; k=$(st 'select(.issue == 10 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 10 and .step == "blocked") | .card')
  st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q 'evidence not moved to ' && [ -s "$k/$old.patch" ] && [ -e "$T/$CASE/cards/$old.out" ] \
    || fail "a blocked line whose patch was kept names no folder when its evidence did not move: $(st 'select(.issue == 10 and .step == "blocked")') $(ls "$T/$CASE/cards")"
  echo "$GO" > "$STUB/review.1"; echo 'git diff --cached --name-only > "$STUB/resumed-with"' > "$STUB/build"
  loop retry 10 >/dev/null && loop run >/dev/null || fail "run of the retried #10 exited non-zero"
  st 'select(.issue == 10 and .step == "worktree") | .reason' | grep -q "^resumed from the kept patch of card $old:" && [ "$(cat "$STUB/resumed-with")" = t.txt ] && [ "$(cat "$R/t.txt" 2>&1)" = ten ] \
    || fail "a retry did not resume from a patch kept beside evidence that did not move: $(st 'select(.issue == 10) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# Bug: the last review could not be moved into the kept folder (here nothing can be: the folder cannot be
# written), so the blocked line names no folder, and the retry's brief left out the findings of the review that is
# still beside the worktree.
t_keptleft() {
  setup "[$(issue 11 2026-01-01)]"; r=0; echo 'echo eleven >> e.txt' > "$STUB/build"; mkdir -p "$ST/kept"
  printf '%s\n' '[P1] e.txt:1 left beside the worktree' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$((r + 1))"
  echo "[ \"\$(wc -l < \"\$STUB/reviews\")\" -lt $((r + 2)) ] || exit 3" > "$STUB/review-cmd"
  chmod a-w "$ST/kept"; loop run >/dev/null; chmod u+w "$ST/kept"; old=$(st 'select(.issue == 11 and .step == "blocked") | .card')
  [ "$(st 'select(.issue == 11 and .step == "blocked") | .kept + (.reason | sub("^review 2: .*evidence not moved.*"; "left"; "s"))')" = left ] && grep -q 'left beside' "$T/$CASE/cards/$old.review" \
    || fail "#11 was not blocked on its second review with its first review left beside the worktree: $(st 'select(.issue == 11 and .step == "blocked")') $(ls "$T/$CASE/cards")"
  rm "$STUB/review-cmd"; echo "$GO" > "$STUB/review.$((r + 4))"; echo 'cp "$STUB/brief" "$STUB/brief.11"; echo eleven >> e.txt' > "$STUB/build"
  loop retry 11 >/dev/null && loop run >/dev/null || fail "run of the retried #11 exited non-zero"
  grep -qx '\[P1\] e.txt:1 left beside the worktree' "$STUB/brief.11" && [ -n "$(st 'select(.issue == 11 and .step == "landed") | .sha')" ] \
    || fail "the brief of a retried card lacks the findings of a review left beside the blocked card's worktree: $(tail -n 8 "$STUB/brief.11" 2>&1)"
}

# A kept patch that git cannot parse is the one kind not used: that card is built from nothing and says so.
t_keptunread() {
  setup "[$(issue 12 2026-01-01)]"; echo 'echo twelve > w.txt; exit 3' > "$STUB/build"
  loop run >/dev/null; k=$(st 'select(.issue == 12 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 12 and .step == "blocked") | .card')
  [ -s "$k/$old.patch" ] || fail "#12 kept no patch: $(st 'select(.issue == 12 and .step == "blocked")')"
  echo 'not a patch' > "$k/$old.patch"; echo "$GO" > "$STUB/review.1"; echo 'cp "$STUB/brief" "$STUB/brief.12"; echo twelve > w.txt' > "$STUB/build"
  loop retry 12 >/dev/null && loop run >/dev/null || fail "run of the retried #12 exited non-zero"
  st 'select(.issue == 12 and .step == "worktree") | .reason' | grep -q "^the kept patch of card $old cannot be read: built from nothing" && grep -q "^# The kept patch of blocked card $old cannot be read$" "$STUB/brief.12" \
    && [ -n "$(st 'select(.issue == 12 and .step == "landed") | .sha')" ] || fail "a kept patch that cannot be read was not given up for a build from nothing: $(st 'select(.issue == 12) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}

# Bug (#93): after the owner turned a card's change down, the only way to have its next card build from nothing was
# to move its kept folder aside by hand, and the kept patch of an earlier retry was then taken up (mode=stale). Here
# #13 blocks twice, the second card resumed from the first's patch: `retry 13 --fresh` moves both cards' kept work to
# one dated folder and says so, and the next card starts with no change staged and no resume line.
t_keptfresh() {
  local k d out
  setup "[$(issue 13 2026-01-01)]"; echo 'echo thirteen >> w.txt; exit 3' > "$STUB/build"
  loop run >/dev/null; loop retry 13 >/dev/null && loop run >/dev/null
  k=$(st 'select(.issue == 13 and .step == "blocked") | .card'); [ -n "$k" ] && [ -s "$ST/kept/$k/$k.patch" ] || fail "#13 was not blocked again with a kept patch: $(st 'select(.issue == 13) | .step' | tr '\n' ,)"
  out=$(loop retry 13 --fresh) || fail "retry 13 --fresh exited non-zero: $out"
  d=$(ls -d "$ST"/kept-dropped/*-13 2>/dev/null)
  [ -n "$d" ] && [ "$(ls "$d" | wc -l)" = 2 ] && [ -s "$d/$k/$k.patch" ] && [ -z "$(ls -A "$ST/kept")" ] && grep -q "^conveyor: its next card builds from nothing; its kept work is in $d$" <<<"$out" \
    || fail "retry --fresh did not move both blocked cards' kept work to one dated folder: $out $(ls -R "$ST/kept" "$ST/kept-dropped" 2>&1)"
  echo "$GO" > "$STUB/review.1"; echo 'git diff --cached --name-only > "$STUB/fresh-with"; echo fresh > w.txt' > "$STUB/build"
  loop run >/dev/null || fail "run of #13 after retry --fresh exited non-zero"
  [ "$(st 'select(.issue == 13 and .step == "worktree") | .reason' | tail -n 1)" = '' ] && [ ! -s "$STUB/fresh-with" ] && [ "$(cat "$R/w.txt")" = fresh ] \
    || fail "the card after retry --fresh did not build from nothing: $(st 'select(.issue == 13 and .step == "worktree") | .reason') staged: $(cat "$STUB/fresh-with" 2>&1)"
}

# A blocked line written before kept work moved under the state folder names its folder by an absolute path,
# which the engine no longer reads. Bugs: such work, unused, lets the move land and is lost: a retry alone, another card
# of the issue landing (a retry takes up only the last kept patch), or a card that found the patch unreadable, does
# not use it; or the gate refuses for work a card took up and landed, even through blocked retries, for a folder
# already discarded, or for a state-relative one.
t_keptgate() {
  setup '[]'; local gate=$SRC/tools/kept-gate.sh old=$T/$CASE/cards-kept out c
  mkdir -p "$old/c1-7" "$old/c7-7" "$old/c2-8" "$ST/kept/c3-9"
  for c in c1-7 c7-7 c2-8; do printf 'x\n' > "$old/$c/$c.patch"; done
  rec() { jq -cn --arg c "$1" --argjson n "$2" --arg s "$3" --arg t "$4" --arg k "${5:-}" '{card:$c,issue:$n,step:$s,time:$t,tokens:{claude:0,codex:0},result:$s,sha:"",reason:""}
    + (if $s == "blocked" then {kept:$k} elif $s == "worktree" then {reason:$k} else {} end)'; }
  { rec c1-7 7 blocked 2026-11-01T00:00:00Z "$old/c1-7"; rec c7-7 7 blocked 2026-11-01T01:00:00Z "$old/c7-7"; rec c2-8 8 blocked 2026-11-01T00:00:00Z "$old/c2-8"; } > "$ST/retried.jsonl"
  { rec c3-9 9 blocked 2026-11-01T00:00:00Z kept/c3-9; rec c4-6 6 blocked 2026-11-01T00:00:00Z "$old/c4-6"; rec c5-8 8 picked 2026-11-02T00:00:00Z; } > "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1) && fail "the gate passed with unused kept work at an absolute path: $out"
  [ "$(grep -c '^kept-gate: card ' <<<"$out")" = 3 ] && grep -q "card c1-7 (#7) has unused kept work at $old/c1-7 (patch 2 bytes)" <<<"$out" \
    && grep -q "card c7-7 (#7)" <<<"$out" && grep -q "card c2-8 (#8)" <<<"$out" \
    || fail "the gate did not list exactly the three unused absolute folders with their patch sizes: $out"
  { rec c5-8 8 worktree 2026-11-02T00:00:01Z 'resumed from the kept patch of card c2-8: one session, then review'; rec c5-8 8 landed 2026-11-02T01:00:00Z
    rec c8-7 7 worktree 2026-11-02T00:00:01Z 'the kept patch of card c7-7 no longer applies to main: one session brings it onto main, then review'; rec c8-7 7 landed 2026-11-02T01:00:00Z
    rec c9-7 7 worktree 2026-11-03T00:00:01Z 'the kept patch of card c1-7 cannot be read: built from nothing'; rec c9-7 7 closed 2026-11-03T01:00:00Z
    rec c6-7 7 landed 2026-11-04T00:00:00Z; } >> "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1) && fail "a landing that took up another patch, or found this one unreadable, used c1-7's work: $out"
  grep -q 'card c1-7 ' <<<"$out" && ! grep -q 'card c7-7 ' <<<"$out" && ! grep -q 'card c2-8 ' <<<"$out" \
    || fail "the gate did not take exactly the landings that took up c7-7's and c2-8's patches as using them: $out"
  # Work carried through retries: c10 resumes c4-6 and blocks, c11 resumes c10 and blocks, c12 resumes c11 and lands.
  mkdir -p "$old/c4-6"
  { rec c10-6 6 worktree 2026-11-05T00:00:01Z 'resumed from the kept patch of card c4-6: one session, then review'; rec c10-6 6 blocked 2026-11-05T01:00:00Z kept/c10-6
    rec c11-6 6 worktree 2026-11-05T02:00:01Z 'resumed from the kept patch of card c10-6: one session, then review'; rec c11-6 6 blocked 2026-11-05T03:00:00Z kept/c11-6; } >> "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1); grep -q 'card c4-6 ' <<<"$out" || fail "retries that only blocked used c4-6's work: $out"
  { rec c12-6 6 worktree 2026-11-05T04:00:01Z 'resumed from the kept patch of card c11-6: one session, then review'; rec c12-6 6 landed 2026-11-05T05:00:00Z; } >> "$ST/cards.jsonl"
  out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1); ! grep -q 'card c4-6 ' <<<"$out" || fail "work carried through two blocked retries into a landing was reported unused: $out"
  rm -rf "$old/c1-7"; out=$(CONVEYOR_MAIN=$R bash "$gate" 2>&1) || fail "the gate refused once every absolute folder was used or discarded: $out"
  echo 'not json' >> "$ST/cards.jsonl"; CONVEYOR_MAIN=$R bash "$gate" >/dev/null 2>&1 && fail "the gate passed on records it cannot read"
  # The state folder is the host file's stateDir when it names one, for the loop and every reader that asks.
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor"; jq -n --arg d "$T/$CASE/elsewhere" '{stateDir: $d}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$T/$CASE/elsewhere" ] || fail "state-dir named $(loop state-dir), not the host file's stateDir"
  # The stateDir is the host main's: another record's checkout on the host keeps its own state folder, or a hold, a
  # pause or a card of one project would be another's (the Board steers every record by its checkout).
  mkdir -p "$T/$CASE/hostmain"; jq -n --arg d "$T/$CASE/elsewhere" --arg m "$T/$CASE/hostmain" '{stateDir: $d, main: $m}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$R/conveyor/state" ] || fail "another record's checkout shares the host main's state folder: $(loop state-dir)"
  jq -n --arg d "$T/$CASE/elsewhere" --arg m "$R/." '{stateDir: $d, main: $m}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$T/$CASE/elsewhere" ] || fail "the host main's checkout does not take the host file's stateDir: $(loop state-dir)"
  # A host file with records and no main (the Foreman's) gives the stateDir to its first record's checkout alone.
  jq -n --arg d "$T/$CASE/elsewhere" --arg a "$T/$CASE/hostmain" --arg b "$R" '{stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$R/conveyor/state" ] || fail "a second record's checkout shares the first record's state folder: $(loop state-dir)"
  jq -n --arg d "$T/$CASE/elsewhere" --arg a "$R" --arg b "$T/$CASE/hostmain" '{stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  [ "$(loop state-dir)" = "$T/$CASE/elsewhere" ] || fail "the first record's checkout does not take the host file's stateDir: $(loop state-dir)"
  # A stateDir that is another record's own conveyor/state would give both one control record: neither checkout runs.
  mkdir -p "$R/conveyor/state"
  for o in "$T/$CASE/hostmain" "$R"; do
    jq -n --arg d "$R/conveyor/state" --arg o "$T/$CASE/hostmain" --arg b "$R" '{main: $o, stateDir: $d, records: [{repo: "alpha", main: $o}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o took a state folder another record's checkout owns: $out"
  done
  # So is a stateDir another record's conveyor/state leads to by a link: both would read one control record.
  mkdir -p "$T/$CASE/shared" "$T/$CASE/beta/conveyor"; ln -s "$T/$CASE/shared" "$T/$CASE/beta/conveyor/state"
  for o in "$T/$CASE/hostmain" "$T/$CASE/beta"; do
    jq -n --arg d "$T/$CASE/shared" --arg o "$T/$CASE/hostmain" --arg b "$T/$CASE/beta" '{main: $o, stateDir: $d, records: [{repo: "alpha", main: $o}, {repo: "beta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o took a state folder a record's linked conveyor/state leads to: $out"
  done
  # Two records besides the host main whose conveyor/state lead to one folder would share its control record too.
  mkdir -p "$T/$CASE/other" "$T/$CASE/gamma/conveyor"; ln -s "$T/$CASE/other" "$T/$CASE/gamma/conveyor/state"; ln -sfn "$T/$CASE/other" "$T/$CASE/beta/conveyor/state"
  for o in "$T/$CASE/beta" "$T/$CASE/gamma" "$T/$CASE/hostmain"; do
    jq -n --arg d "$T/$CASE/elsewhere" --arg a "$T/$CASE/hostmain" --arg b "$T/$CASE/beta" --arg g "$T/$CASE/gamma" '{main: $a, stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "gamma", main: $g}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o ran while two records' conveyor/state lead to one folder: $out"
  done
  # So it is with no stateDir: the two records' one folder is still one control record.
  for o in "$T/$CASE/beta" "$T/$CASE/gamma"; do
    jq -n --arg a "$T/$CASE/hostmain" --arg b "$T/$CASE/beta" --arg g "$T/$CASE/gamma" '{main: $a, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "gamma", main: $g}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "with no stateDir, the checkout $o ran while two records' conveyor/state lead to one folder: $out"
  done
  # And with no stateDir, a record's conveyor/state that leads to the host main's own is the host main's control record.
  mkdir -p "$T/$CASE/hostmain/conveyor/state"; ln -sfn "$T/$CASE/hostmain/conveyor/state" "$T/$CASE/beta/conveyor/state"; rm "$T/$CASE/gamma/conveyor/state"
  out=$(CONVEYOR_MAIN=$T/$CASE/beta CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "with no stateDir, a record's conveyor/state that leads to the host main's was taken: $out"
  ln -sfn "$T/$CASE/other" "$T/$CASE/beta/conveyor/state"; ln -s "$T/$CASE/other" "$T/$CASE/gamma/conveyor/state"
  # Each record with its own conveyor/state still runs, on its own folder.
  rm "$T/$CASE/gamma/conveyor/state"
  out=$(CONVEYOR_MAIN=$T/$CASE/gamma CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && [ "$out" = "$T/$CASE/gamma/conveyor/state" ] || fail "a record with its own state folder did not run on it: $out"
  # A state folder not made yet is the folder its linked parents lead to: the first control command would make it there.
  mkdir -p "$T/$CASE/far" "$T/$CASE/delta" "$T/$CASE/eps" "$T/$CASE/zeta"; for c in delta eps; do ln -s "$T/$CASE/far" "$T/$CASE/$c/conveyor"; done
  for o in "$T/$CASE/delta" "$T/$CASE/eps"; do
    jq -n --arg d "$T/$CASE/elsewhere" --arg a "$T/$CASE/hostmain" --arg b "$T/$CASE/delta" --arg g "$T/$CASE/eps" '{main: $a, stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "delta", main: $b}, {repo: "eps", main: $g}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o ran while two records' linked conveyor lead to one state folder not made yet: $out"
  done
  # So is the host main's own state folder, with no stateDir, when its conveyor and a record's lead to one folder.
  ln -s "$T/$CASE/far" "$T/$CASE/zeta/conveyor"
  for o in "$T/$CASE/zeta" "$T/$CASE/delta"; do
    jq -n --arg a "$T/$CASE/zeta" --arg b "$T/$CASE/delta" '{main: $a, records: [{repo: "zeta", main: $a}, {repo: "delta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "with no stateDir, the checkout $o ran while its conveyor and the host main's lead to one folder: $out"
  done
  [ ! -e "$T/$CASE/far/state" ] || fail "a refused command made the shared state folder"
  # A stateDir that goes back up (`..`) out of a folder not made yet is the folder it ends in: here a record's linked
  # conveyor/state.
  mkdir -p "$T/$CASE/near" "$T/$CASE/theta"; ln -s "$T/$CASE/near" "$T/$CASE/theta/conveyor"
  for o in "$T/$CASE/theta" "$T/$CASE/hostmain"; do
    jq -n --arg d "$T/$CASE/near/new/../state" --arg a "$T/$CASE/hostmain" --arg b "$T/$CASE/theta" '{main: $a, stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "theta", main: $b}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "the checkout $o ran while a stateDir through a folder not made yet and .. leads to a record's state folder: $out"
  done
  [ ! -e "$T/$CASE/near/state" ] || fail "a refused command made the shared state folder"
  # A host main that is not there leaves the other records compared with each other.
  ln -sfn "$T/$CASE/other" "$T/$CASE/gamma/conveyor/state"
  for o in "$T/$CASE/beta" "$T/$CASE/gamma"; do
    jq -n --arg d "$T/$CASE/elsewhere" --arg a "$T/$CASE/missing" --arg b "$T/$CASE/beta" --arg g "$T/$CASE/gamma" '{main: $a, stateDir: $d, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "gamma", main: $g}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(CONVEYOR_MAIN=$o CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && fail "with the host main not there, the checkout $o ran while two records' conveyor/state lead to one folder: $out"
  done
  rm "$T/$CASE/gamma/conveyor/state"
  out=$(CONVEYOR_MAIN=$T/$CASE/gamma CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" state-dir 2>/dev/null) && [ "$out" = "$T/$CASE/gamma/conveyor/state" ] || fail "with the host main not there, a record with its own state folder did not run on it: $out"
  # A host file that cannot be read names no folder, and the checkout's is not taken in its place.
  for bad in '{"stateDir":"/srv/conveyor",' '' '[]'; do
    printf '%s' "$bad" > "$XDG_CONFIG_HOME/conveyor/host.json"
    out=$(loop state-dir 2>/dev/null) && fail "state-dir succeeded on the host file '$bad': $out"; [ -z "$out" ] || fail "state-dir named $out from the host file '$bad'"
  done
  jq -n '{stateDir: "/srv/conveyor"}' > "$XDG_CONFIG_HOME/conveyor/host.json"; chmod 000 "$XDG_CONFIG_HOME/conveyor/host.json"
  [ -r "$XDG_CONFIG_HOME/conveyor/host.json" ] || { loop state-dir >/dev/null 2>&1 && fail "state-dir succeeded on an unreadable host file"; }
  rm -f "$XDG_CONFIG_HOME/conveyor/host.json"; ln -s "$T/$CASE/nowhere" "$XDG_CONFIG_HOME/conveyor/host.json"
  loop state-dir >/dev/null 2>&1 && fail "state-dir succeeded on a host file that links to nothing"
  rm -f "$XDG_CONFIG_HOME/conveyor/host.json"; jq -n '{stateDir: "/srv/conveyor"}' > "$XDG_CONFIG_HOME/conveyor/host.json"; chmod 000 "$XDG_CONFIG_HOME/conveyor"
  [ -x "$XDG_CONFIG_HOME/conveyor" ] || { out=$(loop state-dir 2>/dev/null) && fail "state-dir named $out past a host folder it cannot search"; }
  chmod 755 "$XDG_CONFIG_HOME/conveyor"; mkdir -p "$T/$CASE/private"; mv "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/private/"
  ln -s "$T/$CASE/private/conveyor" "$XDG_CONFIG_HOME/conveyor"; chmod 000 "$T/$CASE/private"
  [ -x "$T/$CASE/private" ] || { out=$(loop state-dir 2>/dev/null) && fail "state-dir named $out past a linked host folder it cannot follow"; }
  chmod 755 "$T/$CASE/private"; rm -f "$XDG_CONFIG_HOME/conveyor"; ln -s "$T/$CASE/nowhere" "$XDG_CONFIG_HOME/conveyor"
  out=$(loop state-dir 2>/dev/null) && fail "state-dir named $out past a host folder link that links to nothing"
  rm -rf "$XDG_CONFIG_HOME/conveyor"
  [ "$(loop state-dir)" = "$R/conveyor/state" ] || fail "state-dir named $(loop state-dir) with no host file"
  return 0
}
