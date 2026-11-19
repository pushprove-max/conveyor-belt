#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: card rules, test runs, trailers, checks and the project pack.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a build, fix, test-fix or rebase session is not given the card rules (its flags load no CLAUDE.md and
# no .claude/rules/), gets them twice, or anywhere but between the header and the issue; the reviewer is not given the
# same rules (plan section 10); a missing or empty rules file lets the card build without them, or blocks it with a reason that does not
# name the file. The card rules are not the core rules followed by the pack's.
t_rules() {
  local f=$T/$CASE.expected p i k
  printf '%s\n\n%s\n' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")" > "$f"
  setup "[$(issue 7 2026-01-01)]"
  # Each session's stdin is kept, as the session itself would read it. The build adds a line while main changes the
  # line beside it, so the landing conflicts; the first test run fails. So the card has a build, a fix (review 1 is a
  # NO-GO), a test fix and a rebase session. The first test run fails on its run again too (tests()), so the fix starts.
  # The fix and the test fix each change the card, so each review after them reads a new change and runs (a review of
  # an unchanged change and main is the last one again, with no session).
  sed -i 's|^cat > "$STUB/brief"; echo "$\*" >> "$STUB/sessions"|&; cp "$STUB/brief" "$STUB/prompt.$(wc -l < "$STUB/sessions")"|' "$STUB/claude"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked.$(($(cat "$STUB/reviews" 2>/dev/null \| wc -l) + 1))"; echo x|' "$STUB/codex"
  cat > "$STUB/build" <<'EOS'
if grep -q '^# Landing conflict' "$STUB/brief"; then printf 'ONE\ntwo\n' > a.txt
elif [ "$(wc -l < "$STUB/sessions")" = 1 ]; then echo two >> a.txt
else wc -l < "$STUB/sessions" > fixed.txt; fi
EOS
  echo 'echo x >> "$STUB/tests"; [ "$(wc -l < "$STUB/tests")" -gt 2 ] || { echo "FAIL widget.test.ts"; exit 1; }; [ "$(wc -l < "$STUB/tests")" != 3 ] || { echo ONE > "$R/a.txt"; git -C "$R" commit -qam other; }' > "$STUB/test-cmd"
  echo "$NOGO" > "$STUB/review.1"; for i in 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start test start fix start review start test start start rebase start review start test start landed pushed issue " ] \
    || fail "steps of a card with a build, a fix, a test fix and a rebase: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  # Bug: a stub that logged its own `-- FAIL widget.test.ts` beside filecmd()'s `-- FAIL a.test.sh` made one run two failed files.
  [ "$(st 'select(.step == "test" and .result == "fail") | .failures.files | map(.file) | join(" ")')" = a.test.sh ] \
    || fail "the failed test step does not name a.test.sh alone: $(st 'select(.step == "test" and .result == "fail") | .failures | tojson')"
  for i in 1 2 3 4; do
    k=$(sed -n "${i}p" <<<$'build\n# Reviewer findings\n# The changed tests fail\n# Landing conflict')
    [ "$i" = 1 ] || grep -q "^$k" "$STUB/prompt.$i" || fail "session $i is not the $k session"
    [ "$(grep -cx '# Rules' "$STUB/prompt.$i")" = 1 ] && [ "$(grep -cxF "$(head -n 1 "$f")" "$STUB/prompt.$i")" = 1 ] \
      || fail "session $i ($k) was not given the rules heading and text exactly once"
    [ "$(sed -n '/^# Rules$/,/^# Issue #7:/p' "$STUB/prompt.$i" | sed '1,2d;$d')" = "$(cat "$f")" ] \
      || fail "session $i ($k): the text between # Rules and the issue is not the core rules, then the pack's"
    head -n 1 "$STUB/prompt.$i" | grep -q '^Conveyor card c.*-7\. Make the change' \
      && [ "$(grep -nx '# Rules' "$STUB/prompt.$i" | cut -d: -f1)" -gt "$(grep -n 'keeps the work\.$' "$STUB/prompt.$i" | head -n 1 | cut -d: -f1)" ] \
      || fail "session $i ($k): the rules do not come after the header"
  done
  for i in 1 2 3 4; do
    [ "$(grep -cx '# Rules' "$STUB/asked.$i")" = 1 ] && [ "$(sed -n '/^# Rules$/,/^# Issue #7:/p' "$STUB/asked.$i" | sed '1,2d;$d')" = "$(cat "$f")" ] \
      || fail "review $i was not given the card rules, once, before the issue"
  done
  # A missing, then an empty rules file: the card blocks before any session, the reason naming the file.
  for p in "$T/$CASE/none.md" "$T/$CASE/empty.md"; do
    printf ' \n\n' > "$T/$CASE/empty.md"; rm -f "$STUB/sessions"; issue 8 2026-02-01 | jq -cs . > "$STUB/issues.json"
    CONVEYOR_CARD_RULES=$p loop run 1 >/dev/null || fail "run with rules file $p exited non-zero"
    st "select(.issue == 8 and .step == \"blocked\") | .reason" | tail -n 1 | grep -qF "the card rules file $p is missing or empty" \
      && [ ! -e "$STUB/sessions" ] || fail "rules file $p: the card was not blocked before its build, or the reason does not name the file: $(st 'select(.issue == 8) | "\(.step) \(.reason)"')"
    loop retry 8 >/dev/null 2>&1 || fail "retry of the blocked card failed"
  done
}

# Bugs (plan section 10): an area rule file the pack maps to a path the issue names (a root file or top-level
# directory too) is not given to the card, or is given to a card whose issue names no such path; a session is not given the card's settings, or those are not
# the generic settings with the pack's hooks after the generic ones of each event; a generic hook is named relative to
# the project, not by its pinned path in the engine's checkout;
# a pack hooks.json of another shape (one that would set what the generic settings set) lets the card build.
t_packrules() {
  local s r x
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "It breaks in web/src/a.tsx:12, package.json and tools/ too."'), $(issue 8 2026-01-02), $(issue 9 2026-01-03)]"
  for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  sed -i 's|^cat > "$STUB/brief"; echo "$\*" >> "$STUB/sessions"|&; cp "$STUB/brief" "$STUB/prompt.$(wc -l < "$STUB/sessions")"|' "$STUB/claude"
  # Each session's settings file, as it is while the session runs.
  echo 'echo two >> a.txt; a=("$@"); for i in "${!a[@]}"; do [ "${a[i]}" != --settings ] || cp "${a[i+1]}" "$STUB/settings.$(wc -l < "$STUB/sessions")"; done' > "$STUB/build"
  echo 'WEB-AREA-RULE' > "$R/.conveyor/web.md"; echo 'NPM-AREA-RULE' > "$R/.conveyor/npm.md"; echo 'TOOLS-AREA-RULE' > "$R/.conveyor/tools.md"
  tune '.areas = {"infra/**": ".conveyor/none.md", "web/src/**": ".conveyor/web.md", "package.json": ".conveyor/npm.md", "tools/": ".conveyor/tools.md"}'
  loop run --only 7 >/dev/null && loop run --only 8 >/dev/null || fail "a run exited non-zero"
  [ "$(sed -n '/^# Rules$/,/^# Issue #7:/p' "$STUB/prompt.1" | sed '1,2d;$d')" \
    = "$(printf '%s\n\n%s\n\nWEB-AREA-RULE\n\nNPM-AREA-RULE\n\nTOOLS-AREA-RULE' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")")" ] \
    || fail "#7 names web/src/a.tsx, the root file package.json and the top-level directory tools/: its rules are not the core rules, the pack's, then web.md, npm.md and tools.md"
  grep -q '^# Rules$' "$STUB/prompt.2" && ! grep -qE 'WEB-AREA-RULE|NPM-AREA-RULE|TOOLS-AREA-RULE' "$STUB/prompt.2" || fail "#8 names no area path and was given an area rule"
  [ "$(sed -n '1s/.*--settings \([^ ]*\) .*/\1/p' "$STUB/sessions")" = "$T/$CASE/cards/$(st 'select(.issue == 7) | .card' | head -n 1).settings" ] \
    && [ ! -e "$T/$CASE/cards/$(st 'select(.issue == 7) | .card' | head -n 1).settings" ] \
    || fail "the build session was not given the card's settings file, or it was left once the card landed: $(head -n 1 "$STUB/sessions")"
  s=$STUB/settings.1
  [ "$(jq -c '[.hooks.PreToolUse[] | .matcher as $m | .hooks[] | "\($m) \(.command | split("/")[-1])"]' "$s")" \
    = '["Bash git-safety.sh","Bash bash-guardrails.sh","Bash adversarial-review-gate.sh","Bash dependency-addition-guard.sh","Edit|Write|MultiEdit dependency-addition-guard.sh","Edit|Write|MultiEdit ruling-cite-gate.sh","AskUserQuestion worker-ask-guard.sh","Bash pack-bash-guard.sh","Bash pack-test-guard.sh","Edit|Write|MultiEdit pack-edit-guard.sh"]' ] \
    && [ "$(jq -cS 'del(.hooks)' "$s")" = "$(jq -cS 'del(.hooks)' "$SRC/card-settings.json")" ] \
    || fail "the card's settings are not the generic ones with the pack's hooks after them: $(jq -c . "$s")"
  # Card sessions are headless and never pause, so a 1-hour cache write (2x the input price against 1.25x) buys nothing.
  [ "$(jq -r '.env.CLAUDE_CODE_PROMPT_CACHE_TTL' "$s")" = 5m ] || fail "the card's session was not given the 5-minute prompt cache lifetime: $(jq -c .env "$s")"
  # A card session opens no Board: its settings, the pack's hooks with them, carry no SessionStart hook and no opener.
  [ "$(jq -c '[.hooks.SessionStart, ([.. | .command? // empty | select(test("board-open"))] | length)]' "$s")" = '[null,0]' ] \
    || fail "the card's settings carry a SessionStart hook or the Board opener: $(jq -c .hooks "$s")"
  # The generic hooks by their pinned path (the engine's checkout, quoted), each a file there; the pack's as written.
  r=$(cd "$SRC/.." && pwd -P)
  [ "$(jq -r '.hooks[][] | .hooks[].command' "$s" | grep -cvF -e "'$r'/.claude/hooks/" -e '"$CLAUDE_PROJECT_DIR"/.claude/hooks/')" = 0 ] \
    && [ "$(jq -r '.hooks[][] | .hooks[].command' "$s" | grep -cF "'$r'/.claude/hooks/")" = 7 ] \
    && [ "$(jq -r '.hooks[][] | .hooks[].command' "$s" | grep -F '"$CLAUDE_PROJECT_DIR"' | sed 's|.*/||' | tr '\n' ' ')" = "pack-bash-guard.sh pack-test-guard.sh pack-edit-guard.sh " ] \
    || fail "the generic hooks are not named by their pinned path, or the pack's not as written: $(jq -c '[.hooks[][] | .hooks[].command]' "$s")"
  for x in $(jq -r '.hooks[][] | .hooks[].command' "$s" | sed -n "s|^'$r'||p"); do [ -f "$r$x" ] || fail "the pinned generic hook $r$x is not a file"; done
  # A hooks.json that sets permissions too: the card blocks before any session, saying why.
  jq '. + {permissions: {allow: ["Bash"]}}' "$SRC/lib/test-hooks.json" > "$R/.conveyor/hooks.json"; rm -f "$STUB/sessions"
  loop run --only 9 >/dev/null || fail "the run of #9 exited non-zero"
  st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q "the engine could not make the card settings" && [ ! -e "$STUB/sessions" ] \
    || fail "a hooks.json of another shape did not block the card before its build: $(st 'select(.issue == 9) | "\(.step) \(.reason)"')"
}

# Bugs: a card lands a change that breaks tests, because nothing ran them: its worktree has no dependencies,
# or the loop does not run the changed tests before the landing; a dependency link is staged and lands (main's
# ignore rule has a trailing slash, which no link matches); a failing run blocks the card with no fix round, or gets
# more than one; a card whose tests fail twice lands, or files follow-ups; a card landing on the last review's NO-GO
# skips the tests, or files its follow-ups before they have passed; a test run leaves no line in the records.
t_tests() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01) <(issue 9 2026-03-01) <(issue 10 2026-04-01) <(issue 11 2026-05-01))"
  mkdir -p "$R/node_modules/dep" "$R/web/node_modules/wdep" "$R/infra" "$R/cache/deps/cdep"; echo '{}' | tee "$R/package.json" "$R/web/package.json" > "$R/infra/package.json"
  # Bug: a link whose parent folder the worktree does not have (cache/ is main's alone) failed.
  P=$R/.conveyor/project.json; jq '.linkFromMain += ["cache/deps"]' "$P" > "$P.new" && mv "$P.new" "$P"
  printf 'conveyor/\n.conveyor/\nnode_modules/\ncache/\n' > "$R/.gitignore"; git -C "$R" add -A; git -C "$R" commit -qm deps
  tl() { st "select(.issue == $1) | .step" | tr '\n' ' '; }
  count() { [ "$(wc -l < "$STUB/sessions") $(wc -l < "$STUB/reviews") $(wc -l < "$STUB/tests")" = "$1" ] || fail "sessions, reviews and test runs so far are $(wc -l < "$STUB/sessions") $(wc -l < "$STUB/reviews") $(wc -l < "$STUB/tests"), not $1"; }
  for i in 1 2 3 4 5; do echo "$GO" > "$STUB/review.$i"; done; for i in 6 7 8 9 10 11 12; do moved $i "$NOGO" > "$STUB/review.$i"; done
  # A GO card whose tests pass. The session and the test run both find main's dependencies in the worktree.
  echo '[ -d web/node_modules/wdep ] && echo two >> a.txt' > "$STUB/build"
  echo 'echo x >> "$STUB/tests"; { [ -L node_modules ] && [ -d node_modules/dep ] && [ -L web/node_modules ] && [ ! -e infra/node_modules ] && [ -L cache/deps ] && [ -d cache/deps/cdep ] && git diff --cached --name-only | tr "\n" " "; } > "$STUB/saw"' > "$STUB/test-cmd"
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ "$(tl 7)" = "picked worktree deps brief start build start review start test start landed pushed issue " ] || fail "steps of a GO card whose tests pass: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "test") | [.result, (.sec | type)] | join(" ")')" = "pass number" ] || fail "test line: $(st 'select(.step == "test")')"
  [ "$(cat "$STUB/saw")" = "a.txt " ] || fail "the test run did not find the dependency links, or a link was staged: $(cat "$STUB/saw")"
  [ "$(git -C "$R" show --name-only --format= HEAD)" = a.txt ] && [ -z "$(git -C "$R" ls-files | grep node_modules)" ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    || fail "the landed commit holds more than the change: $(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ')"
  # Bug: the brief names folders the pack does not link, rather than the pack's linkFromMain.
  grep -qF 'linked from the main checkout: node_modules, infra/node_modules, packages/sample-node/node_modules, web/node_modules, cache/deps.' "$STUB/brief" && grep -q 'the loop runs the changed tests itself' "$STUB/brief" || fail "the brief does not say the dependencies are there and the loop runs the tests"
  loop check || fail "the record check refuses a test line"; count "1 1 1"
  # Tests fail once (the second run and its run again, tests()): one fix session handed the last 200 lines of the output, one review, a second run, landed.
  # The run of a.test.sh, the file linked to a.txt, adds its own lines after the stub's (`-- FAIL a.test.sh`:
  # filecmd()), so the last 200 lines start at out line 104.
  echo 'echo two >> a.txt' > "$STUB/build"
  echo 'echo x >> "$STUB/tests"; case $(wc -l < "$STUB/tests") in 2|3) seq 300 | sed "s/^/out line /"; echo "FAIL widget.test.ts"; printf "%s\n" "== widget.test.ts" "-- FAIL widget.test.ts" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1 ;; esac' > "$STUB/test-cmd"
  loop run 1 >/dev/null || fail "second run exited non-zero"
  [ "$(tl 8)" = "picked worktree deps brief start build start review start test start fix start review start test start landed pushed issue " ] || fail "steps of a card whose tests fail once: $(tl 8)"
  [ "$(st 'select(.issue == 8 and .step == "test") | .result' | tr '\n' ' ')" = "fail pass " ] && st 'select(.issue == 8 and .step == "test" and .result == "fail") | .tail' | grep -q 'FAIL widget.test.ts' \
    || fail "test lines of a card whose tests fail once: $(st 'select(.issue == 8 and .step == "test")')"
  grep -qx 'FAIL widget.test.ts' "$STUB/brief" && grep -qx 'out line 104' "$STUB/brief" && ! grep -qx 'out line 103' "$STUB/brief" && grep -q '^# Issue #8:' "$STUB/brief" \
    || fail "the fix session was not handed the issue and the last 200 lines of the test output"
  [ "$(st 'select(.issue == 8 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ] || fail "the card did not land after its tests passed"; count "3 3 4"
  # Tests fail twice: blocked with the output, nothing landed, the output kept. The line's reason is one sentence;
  # the end of the output (its last 60 lines) is its tail, with its newlines, so the Board shows the two apart.
  # A line is kept whole, however long: a cap on its length loses what it says after the cut, and makes lines that
  # differ only there fold as identical on the Board. Lines that long, 60 of them, are more than one command argument can
  # hold: the line is written all the same, its sentence and its output.
  echo 'echo x >> "$STUB/tests"; seq 100; for i in $(seq 59); do printf "FAIL %03000d\n" 0; done; echo "FAIL gadget.test.ts: expected 2"; printf "%s\n" "== gadget.test.ts" "-- FAIL gadget.test.ts" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1' > "$STUB/test-cmd"; head=$(git -C "$R" rev-parse HEAD)
  loop run 1 >/dev/null || fail "third run exited non-zero"
  [ "$(tl 9)" = "picked worktree deps brief start build start review start test start fix start review start test blocked " ] || fail "steps of a card whose tests fail twice: $(tl 9)"
  [ "$(st 'select(.issue == 9 and .step == "blocked") | .reason')" = "the changed tests failed again after their one fix round (exit 1); nothing landed." ] \
    || fail "the blocked reason is not the one sentence: $(st 'select(.issue == 9 and .step == "blocked") | .reason')"
  # After the stub's lines come the run's own: a.test.sh's end (`-- FAIL a.test.sh`: filecmd()) and the note of the
  # linked files it ran (LINKED).
  [ "$(st 'select(.issue == 9 and .step == "blocked") | .tail | split("\n") | [length, (.[0] | length), .[-3], .[-2], (.[-1] | startswith("conveyor: the change adds or changes no test file")), (.[-5] == .[-4] and (.[-4] | startswith("FAIL 000") and length == 3005))] | join("|")')" = "60|3005|FAIL gadget.test.ts: expected 2|-- FAIL a.test.sh|true|true" ] \
    || fail "the blocked line's tail is not the last 60 lines of the test output: $(st 'select(.issue == 9 and .step == "blocked") | .tail')"
  loop check || fail "the record check refuses a blocked line with a tail"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "a card whose tests failed twice landed, left main dirty or left its worktree"
  grep -q 'FAIL gadget' "$(st 'select(.issue == 9 and .step == "blocked") | "\($ENV.ST)/\(.kept)"')"/*.test || fail "the test output was not kept"; count "5 5 8"
  # The last review says NO-GO: the tests still run, and pass, before the follow-up is filed and the card lands.
  echo 'echo x >> "$STUB/tests"; [ -e "$STUB/filed" ] || : > "$STUB/tested-first"' > "$STUB/test-cmd"
  loop run 1 >/dev/null || fail "fourth run exited non-zero"
  [ "$(tl 10)" = "picked worktree deps brief start build start review start fix start review start fix start review start test start filed start landed pushed issue " ] && [ -e "$STUB/tested-first" ] || fail "a card landing on a NO-GO did not run its tests first: $(tl 10)"
  [ "$(st 'select(.issue == 10 and .step == "landed") | [.sha, .followups] | tojson')" = "[\"$(git -C "$R" rev-parse HEAD)\",[100101]]" ] || fail "the NO-GO card did not land with its follow-up"; count "8 8 9"
  # The last review says NO-GO and the tests fail twice: blocked, with no follow-up filed.
  echo 'echo x >> "$STUB/tests"; echo "FAIL again"; printf "%s\n" "== again.test" "-- FAIL again.test" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1' > "$STUB/test-cmd"; head=$(git -C "$R" rev-parse HEAD)
  loop run --only 11 1 >/dev/null || fail "fifth run exited non-zero"
  [ "$(tl 11)" = "picked worktree deps brief start build start review start fix start review start fix start review start test start fix start review start test blocked " ] || fail "steps of a NO-GO card whose tests fail twice: $(tl 11)"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ "$(wc -l < "$STUB/filed")" = 1 ] && [ ! -e "$STUB/closed" ] || fail "a card whose tests failed twice landed or filed a follow-up"
}

# Bug: a failed test run's line held the last characters of its output as its reason: cut mid-word, a run of `ok`
# names and cleanup warnings, a note on exit 124 whatever the exit was, and the failing test named nowhere. The owner
# could not tell from the Board what failed. The line names the failing files and cases, each with its first FAIL
# line; a run that timed out says so and names the file still running; the output is the line's tail, lines whole.
# Bugs: a file that failed with no `FAIL [case]:` line (a node or TAP test, or one that died) was not listed at all;
# and a `== ` line a test printed passed for the runner's, so its cases went to a file that never ran and the count
# grew. Which files ran and failed is read from the runner's log, which no test's output reaches.
# Bug: a failing file that printed the `== ` line of a file that had passed gave it its failing case, so the Board
# named a passing file as failed. Files run in the log's order: a `== ` line that goes back is a test's own, and a
# FAIL line a passing file prints is no failure.
t_testfails() {
  local f; setup "$(jq -cs . <(issue 7 2026-01-01))"
  for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  for f in tests/a.test.sh conveyor/conveyor.test.sh tests/b.test.sh tests/c.test.sh tests/d.test.mjs tests/e.test.sh tests/slow.test.sh tests/z.test.sh; do
    mkdir -p "$R/${f%/*}" && echo x > "$R/$f"; done
  git -C "$R" add -f tests conveyor && git -C "$R" commit -qm "the test files" || fail "main's test files could not be committed" # -f: the fixture ignores conveyor/
  # Each file runs alone, as the worktree's links (the fixture ignores .conveyor/) give a.txt: the build's four, the fix's five.
  cat > "$STUB/build" <<'EOF'
echo two >> a.txt; mkdir -p .conveyor
if grep -q '^# The changed tests fail' "$STUB/brief"; then echo '{"a.txt": ["tests/a.test.sh", "tests/d.test.mjs", "tests/e.test.sh", "tests/slow.test.sh", "tests/z.test.sh"]}'
else echo '{"a.txt": ["tests/a.test.sh", "conveyor/conveyor.test.sh", "tests/b.test.sh", "tests/c.test.sh"]}'; fi > .conveyor/test-links.json
EOF
  # The first run: two of four files fail, one case each, one with a line over 200 characters and a second FAIL line,
  # after a `== ` line of its own that is no file of the run. The run after the fix: a TAP file fails (its TODO case
  # does not), a file fails naming no case, and it is still in its fourth file of five when its time (2 s) is up. Each
  # failed test line is its run again's, of the files that did not pass (of: two, then four: z.test.sh never began).
  cat > "$STUB/test-cmd" <<'EOF'
case $CONVEYOR_TEST_FILE in
  tests/a.test.sh) echo "ok alpha" ;;
  conveyor/conveyor.test.sh) echo "ok lane"; echo "== diagnostic"
    echo "FAIL [views]: the snapshot lacks $(printf 'word %.0s' $(seq 60))end"; echo "FAIL [views]: a second line"
    echo "conveyor: left 2 stubs running"; exit 1 ;;
  tests/b.test.sh) echo "== tests/a.test.sh"; echo "FAIL [beta]: expected 2, got 3"; echo "ok gamma"; exit 1 ;;
  tests/c.test.sh) echo "FAIL [own]: words a passing test prints"; echo "ok delta" ;;
  tests/d.test.mjs) echo "not ok 1 - rejects invalid input"; echo "ok 2 - fine"; echo "not ok 3 - later # TODO"; exit 1 ;;
  tests/e.test.sh) echo "e.test.sh: line 3: syntax error"; exit 1 ;;
  tests/slow.test.sh) echo "ok one"; sleep 30 ;; # sleep: a test file that hangs, cut by the run's clock at testTimeout
esac
EOF
  tuned '.tunables.testTimeout = 2' loop run 1 > /dev/null || fail "run exited non-zero"
  f() { st 'select(.step == "test" and .result == "fail") | tojson' | sed -n "$1p" | jq -r "$2"; }
  [ "$(st 'select(.step == "test") | .result' | tr '\n' ' ')" = "fail fail " ] || fail "not two failed test runs: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(f 1 '.failures | [.of, .timeout, (.files | map([.file, (.cases | map(.name) | join(","))] | join(":")) | join(" "))] | tojson')" \
    = '[2,null,"conveyor/conveyor.test.sh:views tests/b.test.sh:beta"]' ] || fail "the failing files and cases are not exactly the two that failed: $(f 1 '.failures | tojson')"
  [ "$(f 1 '.failures.files[1].cases[0].line')" = "FAIL [beta]: expected 2, got 3" ] || fail "a case's line is not its first FAIL line: $(f 1 '.failures | tojson')"
  [ "$(f 1 '.failures.files[0].cases[0].line | [(length <= 200 and length > 190), startswith("FAIL [views]: the snapshot lacks word"), endswith(" word")] | tojson')" = '[true,true,true]' ] \
    || fail "a long first line is not cut to 200 characters at a word: $(f 1 '.failures.files[0].cases[0].line')"
  f 1 '.failures | tojson' | grep -q 'ok \|alpha\|left 2 stubs\|second line\|diagnostic' && fail "a passing file, an ok line, a warning, a later FAIL line or a test's own == line is among the failures: $(f 1 '.failures | tojson')"
  # The exit is said as it was: a note on 124 beside an exit 1 reads as a timeout that never happened.
  [ "$(f 1 .reason)" = "exit 1" ] || fail "the reason of a run that exited 1: $(f 1 .reason)"
  [ "$(f 1 '.tail | split("\n") | [.[0], .[5], .[10]] | join("|")')" = "== conveyor/conveyor.test.sh|conveyor: left 2 stubs running|ok gamma" ] || fail "the tail is not the output, a line a line: $(f 1 .tail)"
  [ "$(f 2 '.failures | [.of, .timeout] | tojson')" = '[4,{"sec":2,"file":"tests/slow.test.sh"}]' ] || fail "a run that timed out does not say so and name the file still running, of the files selected: $(f 2 '.failures | tojson')"
  [ "$(f 2 '.failures.files | tojson')" = '[{"file":"tests/d.test.mjs","cases":[{"name":"rejects invalid input","line":"not ok 1 - rejects invalid input"}]},{"file":"tests/e.test.sh","cases":[]}]' ] \
    || fail "a file that failed with a TAP line, or with no case line at all, is not listed: $(f 2 '.failures.files | tojson')"
  [ "$(f 2 .reason)" = "exit 124: timed out after 2s in tests/slow.test.sh" ] || fail "the reason of a run that timed out: $(f 2 .reason)"
  loop check || fail "the record check refuses a failed test line with its failures"
  # The Board reads them from the card's steps: each failed run with its failures and its output.
  [ "$(loop snapshot --fresh | jq -c '.needsYou.blocked[0].track.records | map(select(.name == "tests failed") | [.why, (.failures.files | length), .failures.timeout.file, (.output | test("FAIL \\[beta\\]|not ok 1 "))])')" \
    = '[["exit 1",2,null,true],["exit 124: timed out after 2s in tests/slow.test.sh",2,"tests/slow.test.sh",true]]' ] \
    || fail "the card's steps lack a failed run's failures or output: $(loop snapshot --fresh | jq -c '.needsYou.blocked[0].track.records')"
}

# Bugs: a host's commit-msg hook refuses every card that needs a line only the builder can write, because the card
# cannot put one in Conveyor's message; a line not of the trailer shape, or a Co-Authored-By, reaches the commit; the
# review does not see the trailers; a pack rule's trailer is missing and the card commits anyway, or gets no session
# to write it; a pack with no commit.trailers changes the message or asks for a trailer; a trailer the fix session
# writes lands unreviewed; the tests delete the trailers after the check and the card commits without them; a path
# git quotes (café/) escapes the rule; a rule whose when is not a valid ERE silently requires nothing.
t_trailers() {
  local -x FILEMODE=1
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-01-02) <(issue 9 2026-01-03) <(issue 10 2026-01-04) <(issue 11 2026-01-05))"
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-01-02) <(issue 9 2026-01-03) <(issue 10 2026-01-04) <(issue 11 2026-01-05) <(issue 12 2026-01-06))"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  for i in 1 2 3 4 5 6 7; do echo "$GO" > "$STUB/review.$i"; done
  msgis() { # <issue> <trailer lines>: main's head message is the card's, with those lines after Closes
    local c; c=$(st "select(.issue == $1 and .step == \"landed\") | .card")
    [ -n "$c" ] && [ "$(git -C "$R" log -1 --format=%B)" = "feat(product): title $1 (#$1)"$'\n\n'"Closes #$1"$'\n'"${2:+$2$'\n'}Conveyor card $c" ]
  }
  # No pack rule: a card adding a guard test and writing no trailers lands with the message as before, one session.
  echo 'touch a-guard.test.ts' > "$STUB/build"
  loop run --only 10 >/dev/null || fail "run of #10 exited non-zero"
  msgis 10 '' && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "a pack with no commit.trailers changed the message or ran a session: $(git -C "$R" log -1 --format=%B)"
  grep -qF "$T/$CASE/cards/" "$STUB/brief" && grep -q '\.trailers, one a line' "$STUB/brief" || fail "the build prompt does not name the trailers file: $(cat "$STUB/brief")"
  # #7: the session's trailer lands after Closes; a line not of the shape and a Co-Authored-By are dropped.
  printf '%s\n' 'echo two >> a.txt' 'printf "%s\n" "Mutation-verified: broke X, test went red" "not a trailer line" "Co-Authored-By: someone" "-x: no token" > "$PWD.trailers"' > "$STUB/build"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  msgis 7 'Mutation-verified: broke X, test went red' || fail "the commit message is not the card's with its one trailer: $(git -C "$R" log -1 --format=%B)"
  grep -qx 'Mutation-verified: broke X, test went red' "$STUB/asked" && ! grep -q 'not a trailer line' "$STUB/asked" || fail "the review did not see the kept trailers: $(cat "$STUB/asked")"
  # The pack requires Mutation-verified of an added guard-class test.
  tune '.commit.trailers = [{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke and how the test went red."}]'
  # #8: no session writes it: one fix session, asked for it, then blocked with the reason; nothing lands.
  echo 'touch b-guard.test.ts' > "$STUB/build"; : > "$STUB/sessions"; head=$(git -C "$R" rev-parse HEAD)
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && grep -q 'Say what you broke and how the test went red. It adds b-guard.test.ts.' "$STUB/brief" \
    || fail "not one fix session asking for the trailer: $(cat "$STUB/brief")"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'missing after its one fix session; nothing landed: Mutation-verified (it adds b-guard.test.ts)' \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a card missing a required trailer was not blocked with the reason, or landed: $(st 'select(.issue == 8)')"
  # #9: a path git quotes; the fix session writes the trailer alone, which is reviewed again, and the card lands with it
  # though its tests delete the file.
  printf '%s\n' 'mkdir -p café; touch café/c-guard.test.ts' '[ "$(wc -l < "$STUB/sessions")" -lt 4 ] || echo "Mutation-verified: removed the check, the test went red" > "$PWD.trailers"' > "$STUB/build"
  echo 'rm -f "$PWD.trailers"' >> "$STUB/test-cmd"
  loop run --only 9 >/dev/null || fail "run of #9 exited non-zero"
  grep -q 'adds a file whose path matches the extended regular expression `(conformance|guard|parity|coverage)' "$STUB/brief" || fail "the prompt does not carry the pack's rule"
  msgis 9 'Mutation-verified: removed the check, the test went red' && [ "$(wc -l < "$STUB/sessions")" = 4 ] \
    || fail "the trailer the fix session wrote did not land: $(git -C "$R" log -1 --format=%B) $(st 'select(.issue == 9)')"
  [ "$(wc -l < "$STUB/reviews")" = 5 ] && grep -qx 'Mutation-verified: removed the check, the test went red' "$STUB/asked" \
    || fail "the trailer the fix session wrote was not reviewed: $(wc -l < "$STUB/reviews") reviews"
  # #11: a when grep cannot read blocks the card with the reason; nothing lands.
  tune '.commit.trailers = [{"when": "[", "token": "Mutation-verified", "ask": "Say what you broke."}]'
  echo 'touch d.txt' > "$STUB/build"; head=$(git -C "$R" rev-parse HEAD)
  loop run --only 11 >/dev/null || fail "run of #11 exited non-zero"
  st 'select(.issue == 11 and .step == "blocked") | .reason' | grep -q 'valid extended regular expression' && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] \
    || fail "a pack rule with an invalid when did not block the card: $(st 'select(.issue == 11)')"
}

# Bug: a path holding a newline escaped the pack's trailer rule: read a line a name, neither half matches the rule's
# when, so the card owed no trailer and committed without one. owing() (lib/testrun.sh) reads the added names whole.
t_trailerpath() {
  local W=$T/$CASE/w out rc
  mkdir -p "$W" && git -C "$W" init -q && touch "$W/$(printf 'e-guard\n.test.ts')" && git -C "$W" add -A || fail "the worktree"
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh
  out=$( (STATE=$T/$CASE/cards.jsonl; . "$SRC/lib/testrun.sh" || exit 3
    packget() { case $1 in commit.trailers) printf -v "$2" '%s' '[{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke."}]' ;;
      *) printf -v "$2" '%s' '[]' ;; esac; }
    owing "$W") 2>&1); rc=$?
  [ $rc = 0 ] && [ "$out" = '{"token":"Mutation-verified","ask":"Say what you broke.","paths":["e-guard\n.test.ts"]}' ] \
    || fail "a path holding a newline escaped the pack's rule: exit $rc, $out"
}

# Bugs: a card whose change fails a product check (here two of the case's own: a baseline raised, a schema added)
# lands, or gets a fix round in place of being blocked; the reason does not hold the check's own lines; a clean card
# does not land, or lands with no test run.
t_checks() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01) <(issue 9 2026-03-01))"
  echo '{"hex":3}' > "$R/baseline.json"; echo 'SCHEMA_4' > "$R/schema.txt"
  git -C "$R" add -A; git -C "$R" commit -qm ratchets
  # The cards change baseline.json and schema.txt: linked to the stub test file, so a card's test step runs the stub.
  linkset '{"a.txt": ["a.test.sh"], "baseline.json": ["a.test.sh"], "schema.txt": ["a.test.sh"]}'
  cat > "$STUB/raise-check.sh" <<'CHECK'
a=$(git show "$1:baseline.json" | jq .hex); b=$(git show "$2:baseline.json" | jq .hex)
[ "$b" -le "$a" ] || { printf 'a%.0s' {1..1000}; echo; printf '12345678\n%.0s' {1..20000}; echo "LOOSENED baseline.json hex: $a -> $b"; exit 1; }
CHECK
  cat > "$STUB/schema-check.sh" <<'CHECK'
! git diff "$1" "$2" -- schema.txt | grep -q '^+SCHEMA_5' || { echo "adds schema 5 with no old-format test"; exit 1; }
CHECK
  tune --arg a "$STUB/raise-check.sh" --arg b "$STUB/schema-check.sh" '.checks = [$a, $b]'
  for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  tl() { st "select(.issue == $1 and $NOMARK) | .step" | tr '\n' ' '; }
  # A baseline raised: blocked before the changed tests, with no fix round, and nothing lands. The check's verbose
  # output (more than one command argument can hold) comes before its failing line: the tail keeps the end, so the
  # failing line is not lost behind it.
  echo 'echo "{\"hex\":4}" > baseline.json' > "$STUB/build"; head=$(git -C "$R" rev-parse HEAD)
  loop run 1 >/dev/null || fail "first run exited non-zero"
  [ "$(tl 7)" = "picked worktree brief build review blocked " ] || fail "steps of a card that raises a baseline: $(tl 7)"
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "a product check failed; nothing landed." ] \
    && st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -q '^LOOSENED baseline.json hex: 3 -> 4$' \
    || fail "the blocked line is not the sentence with the check's line in its tail: $(st 'select(.issue == 7 and .step == "blocked") | [.reason, .tail]')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ ! -e "$STUB/tests" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "a card that raises a baseline landed, ran its tests or got a fix session"
  # A schema added: blocked the same way, by the second check.
  echo 'echo SCHEMA_5 >> schema.txt' > "$STUB/build"
  loop run 1 >/dev/null || fail "second run exited non-zero"
  [ "$(tl 8)" = "picked worktree brief build review blocked " ] || fail "steps of a card that adds a schema: $(tl 8)"
  st 'select(.issue == 8 and .step == "blocked") | .tail' | grep -q 'schema-check.sh (exit 1)' \
    && st 'select(.issue == 8 and .step == "blocked") | .tail' | grep -q 'adds schema 5' \
    || fail "the blocked line's tail does not hold the second check's line: $(st 'select(.issue == 8 and .step == "blocked") | .tail')"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] || fail "a card that adds a schema landed"
  # A clean card (it lowers a baseline) lands after its changed tests, which ran ($STUB/tests: the stub's one line).
  echo 'echo "{\"hex\":2}" > baseline.json' > "$STUB/build"
  loop run 1 >/dev/null || fail "third run exited non-zero"
  [ "$(cat "$STUB/tests" 2>/dev/null)" = x ] || fail "the clean card's changed tests did not run once: $(cat "$STUB/tests" 2>/dev/null)"
  [ "$(tl 9)" = "picked worktree brief build review test landed " ] && [ "$(cat "$R/baseline.json")" = '{"hex":2}' ] \
    || fail "a clean card did not land: $(st 'select(.issue == 9) | "\(.step) \(.reason)"' | tr '\n' ,)"
}

# Bugs: a host project's long check run, which holds the loop paused, shows nowhere, so nothing seems to run; a time
# left is guessed from too few lanes; a run long over stays shown; a progress command that fails, hangs or prints
# bad JSON, or JSON missing a field, breaks the snapshot; the command runs on every snapshot, or twice when two
# snapshots ask at once; a pack without one gains a field; /units has no block to print.
# Bug: Held and Queue sorted by when an issue was opened, so one held today came before one held ten days ago when
# it was opened first. Each issue there carries since: when it came to that column, never when it was opened.
t_since() {
  setup '[]'; touch "$ST/cards.jsonl" "$ST/retried.jsonl"
  { issue 1 2026-01-01T00:00:00Z; issue 2 2026-01-02T00:00:00Z; } | jq -cs . > "$STUB/issues.json"
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  # --fresh: each snapshot is built at its own time; a kept one (a few seconds old) still holds the earlier holds.
  at() { on "$1" snapshot --fresh; }
  col() { jq -c "$1 | map([.issue, .since])"; }
  # First sight, with no times kept: both are dated by that snapshot, not by when each was opened.
  out=$(at 2026-10-01); [ "$(col .queue.order <<<"$out")" = '[[1,"2026-10-01T00:00:00Z"],[2,"2026-10-01T00:00:00Z"]]' ] || fail "first sight: $out"
  on 2026-11-01 control hold 2 >/dev/null; at 2026-11-05 >/dev/null
  on 2026-11-12 control hold 1 >/dev/null; out=$(at 2026-11-13)
  # Each is dated by its hold: #2, held on November 1, has been held longer than #1, held on November 12, though
  # #1 is the older issue.
  [ "$(col .open.held <<<"$out")" = '[[1,"2026-11-12T00:00:00Z"],[2,"2026-11-01T00:00:00Z"]]' ] \
    && [ "$(col .queue.holding <<<"$out")" = '[[1,"2026-11-12T00:00:00Z"],[2,"2026-11-01T00:00:00Z"]]' ] || fail "held since: $out"
  # Released and held again with no snapshot between: held since the second hold, not the first.
  on 2026-11-14 control release 2 >/dev/null; on 2026-11-15 control hold 2 >/dev/null
  out=$(at 2026-11-16); [ "$(col .open.held <<<"$out")" = '[[1,"2026-11-12T00:00:00Z"],[2,"2026-11-15T00:00:00Z"]]' ] || fail "held again: $out"
  # Released with no snapshot between: each is queued since its release, not since the snapshot that saw it there,
  # so #2, released first, has waited longer than the older #1.
  on 2026-11-17 control release 2 >/dev/null; on 2026-11-18 control release 1 >/dev/null
  out=$(at 2026-11-19); [ "$(col .queue.order <<<"$out")" = '[[1,"2026-11-18T00:00:00Z"],[2,"2026-11-17T00:00:00Z"]]' ] || fail "released: $out"
  # A snapshot that listed #2 in Queue, before a hold that came while it ran, does not write its older sight over
  # the hold (the pack's progress command, which a snapshot runs after it copies the control record, holds it).
  tuned '.checks = {run: [], progress: "CONVEYOR_NOW=$(date -u -d 2026-11-21 +%s) bash '"$SRC"'/conveyor.sh control hold 2 >/dev/null"}' at 2026-11-20 >/dev/null
  out=$(at 2026-11-22); [ "$(col .open.held <<<"$out")" = '[[2,"2026-11-21T00:00:00Z"]]' ] || fail "an older sight written over a hold: $out"
  # Something besides your hold keeps #2 in Held (a rule): released and held again, it never left Held.
  on 2026-11-23 control rules P3=off >/dev/null; at 2026-11-24 >/dev/null
  on 2026-11-25 control release 2 >/dev/null; on 2026-11-26 control hold 2 >/dev/null
  out=$(at 2026-11-27); [ "$(col '.open.held | map(select(.issue == 2))' <<<"$out")" = '[[2,"2026-11-21T00:00:00Z"]]' ] || fail "held by a rule all along: $out"
  on 2026-11-27 control rules P3=on >/dev/null
  # The rule turned on since that snapshot no longer keeps it: released and held again before the next snapshot, it
  # left Held, and is held since the second hold.
  on 2026-11-28 control release 2 >/dev/null; on 2026-11-29 control hold 2 >/dev/null
  out=$(at 2026-11-30); [ "$(col '.open.held | map(select(.issue == 2))' <<<"$out")" = '[[2,"2026-11-29T00:00:00Z"]]' ] || fail "held since a release the rule no longer kept: $out"
  # Held from Queue, then a rule turned off before the release: the rule keeps it in Held all along, so a hold after
  # the release does not redate it (the hold kept what the snapshot read of it).
  on 2026-12-01 control release 2 >/dev/null; at 2026-12-01 >/dev/null
  on 2026-12-02 control hold 2 >/dev/null; on 2026-12-03 control rules P3=off >/dev/null
  on 2026-12-04 control release 2 >/dev/null; on 2026-12-05 control hold 2 >/dev/null
  out=$(at 2026-12-06); [ "$(col '.open.held | map(select(.issue == 2))' <<<"$out")" = '[[2,"2026-12-02T00:00:00Z"]]' ] || fail "a hold forgot the rule that keeps it: $out"
  on 2026-12-06 control rules P3=on >/dev/null
  # Released while a snapshot lists the issues, before it copies the control record: it shows #1 in Queue since the
  # release, not since its hold, so it does not sort before #2, held all along.
  on 2026-12-07 control hold 1 >/dev/null; at 2026-12-08 >/dev/null
  echo 'CONVEYOR_NOW=$(date -u -d 2026-12-11 +%s) bash '"$SRC"'/conveyor.sh control release 1 >/dev/null' > "$STUB/list-cmd"
  out=$(at 2026-12-10); rm "$STUB/list-cmd"
  [ "$(col .queue.order <<<"$out")" = '[[1,"2026-12-11T00:00:00Z"]]' ] || fail "a release while the snapshot ran gave Queue its Held time: $out"
  # GitHub does not list the issues: no since, and the times kept are not lost.
  cp "$ST/moved.json" "$STUB/moved.was"; echo junk > "$STUB/issues.json"
  out=$(at 2026-11-22); cmp -s "$ST/moved.json" "$STUB/moved.was" || fail "moved.json changed when the issues were not listed: $(cat "$ST/moved.json")"
  ! jq -e 'has("cols")' >/dev/null <<<"$out" || fail "the snapshot carries its columns: $out"
}

# Bugs: the remote, branch, labels, owner and product paths are the host project's, whatever the pack says: a card
# lands on main and pushes to origin when the pack names master and upstream; a visible change asks for Dana's yes when
# the owner is Quinn; the follow-up, type, priority and area labels, and the product paths, are the host project's.
t_pack() {
  setup "[$(issue 7 2026-01-01 defect team/billing)]"; O=$T/$CASE/up
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  git -C "$R" branch -m main master; git -C "$R" remote remove origin
  git init -q --bare -b master "$O"; git -C "$R" remote add upstream "$O"
  P=$R/.conveyor/project.json
  jq '.remote = "upstream" | .defaultBranch = "master" | .owner.name = "Quinn" | .productPaths = ["app/"]
    | .labels = {built: "shipped", followup: "fu", type: "defect", priorities: ["urgent", "high", "low"], areaPrefix: "team/", nonProductAreas: ["team/tools"]}' "$P" > "$P.new" \
    && mv "$P.new" "$P" && git -C "$R" push -q upstream master
  # #7 has the pack's type label, so it is a bug card: its build adds a test that fails without the fix (bugproof()).
  provenbug; echo 'mkdir -p app; echo pay >> app/pay.ts' >> "$STUB/build"
  echo "$GO" > "$STUB/review.1"; loop run >/dev/null || fail "run exited non-zero: $(st .)"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse refs/heads/master)" ] && [ "$(git -C "$O" rev-parse refs/heads/master)" = "$(git -C "$R" rev-parse master)" ] \
    && ! git -C "$R" rev-parse -q --verify refs/heads/main >/dev/null || fail "the card did not land on master and push it to upstream: $(st .)"
  git -C "$R" log -1 --format=%B master | grep -q '^fix(billing): title 7 (#7)$' || fail "the commit subject does not read the type label and area prefix: $(git -C "$R" log -1 --format=%s master)"
  grep -q "stops after review for Quinn's yes when" "$STUB/asked" && grep -q '(app/, tests aside)' "$STUB/asked" && ! grep -q "Dana's yes\|src/, shared/" "$STUB/asked" \
    || fail "the review prompt does not name the pack's owner and product paths"
  # A visible change under the pack's product paths: blocked for Quinn's yes; #9, labelled with the pack's built
  # label, is never picked.
  printf '%s\n' 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO' > "$STUB/review.2"
  jq -cs . <(issue 8 2026-01-01 high) <(issue 9 2026-01-02 urgent shipped) > "$STUB/issues.json"
  loop run >/dev/null || fail "second run exited non-zero"
  [ "$(st 'select(.issue == 8 and .step == "blocked") | .reason')" = "visible to customers or staff: needs Quinn's yes: guests see a new Pay button" ] \
    && [ -z "$(st 'select(.issue == 9)')" ] || fail "a visible change was not blocked for Quinn's yes, or the built label was picked: $(st .)"
  [ "$(loop health | jq -c '.waiting | map(.issue)')" = '[8]' ] || fail "health does not list the card waiting for Quinn's yes: $(loop health)"
  # A last review's NO-GO files its follow-up with the pack's follow-up, type and priority labels and area label.
  printf '%s\n' '[P0] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.3"; moved 4 "$(<"$STUB/review.3")" > "$STUB/review.4"; moved 5 "$(<"$STUB/review.3")" > "$STUB/review.5"
  echo "[$(issue 11 2026-01-03 team/billing)]" > "$STUB/issues.json"; echo 'echo three >> a.txt' > "$STUB/build"
  loop run >/dev/null || fail "third run exited non-zero: $(st 'select(.issue == 11)')"
  [ "$(jq -c '[.labels[].name]' "$STUB/filed")" = '["fu","defect","urgent","team/billing"]' ] || fail "the follow-up's labels are not the pack's: $(cat "$STUB/filed")"
  # Bugs: the pack's remote changed to an empty one: the commit pushed to the old one is unpushed, and the
  # loop pushes it to the new one.
  X=$(git -C "$R" rev-parse master); git init -q --bare -b master "$T/$CASE/up2"; git -C "$R" remote add up2 "$T/$CASE/up2"
  jq '.remote = "up2"' "$P" > "$P.new" && mv "$P.new" "$P"
  loop health | jq -e --arg x "$X" '.unpushed | any(.sha == $x)' >/dev/null || fail "health hides a commit the pack's new remote lacks: $(loop health | jq -c .unpushed)"
  echo '[]' > "$STUB/issues.json"; loop run >/dev/null; [ "$(git -C "$T/$CASE/up2" rev-parse -q --verify refs/heads/master)" = "$X" ] || fail "the loop did not push to the pack's new remote"
  jq '.remote = "upstream"' "$P" > "$P.new" && mv "$P.new" "$P"
  # Bugs: with the pack's built label not awaiting-deploy, an awaiting-deploy issue is still skipped; a pack
  # with five priorities picks an older last one before a newer fourth one; an area rule must start area:.
  jq '.labels.priorities = ["critical", "high", "medium", "low", "trivial"]' "$P" > "$P.new" && mv "$P.new" "$P"
  jq -cs . <(issue 21 2026-01-01 trivial) <(issue 22 2026-01-02 low) <(issue 23 2026-01-03 awaiting-deploy) > "$STUB/issues.json"
  [ "$(loop snapshot --fresh | jq -c '.queue.next | map(.issue)')" = '[22,21,23]' ] || fail "the pick order is not the pack's priorities, or awaiting-deploy was skipped: $(loop snapshot --fresh | jq -c .queue.next)"
  # Bugs: a pack with one priority: an issue with none is P3, so a P1 rule leaves it alone.
  # Bug (#220): the Foreman's watcher of a belt on another host has no pack to read foreman.waitWake from, so the
  # snapshot, made on the belt's host, gives it; without it such a watcher woke at 10 minutes whatever the pack said.
  jq '.labels.priorities = ["urgent"] | .foreman.waitWake = 5' "$P" > "$P.new" && mv "$P.new" "$P"
  echo "[$(issue 24 2026-01-01)]" > "$STUB/issues.json"; loop control rules P1=off >/dev/null
  [ "$(loop snapshot --fresh | jq -c '[.areaPrefix, (.queue.next | map([.issue, .priority])), .waitWake]')" = '["team/",[[24,"P3"]],5]' ] \
    || fail "an issue with no priority took a P1 rule, or the snapshot does not give the area prefix or the pack's foreman.waitWake: $(loop snapshot --fresh | jq -c '[.areaPrefix, .queue, .waitWake]')"
  loop control rules P1=on >/dev/null
  [ "$(loop control rules team/billing=off | jq -c .rules.never)" = '["team/billing"]' ] || fail "an area rule with the pack's area prefix was refused"
  loop control rules area:billing=off 2>/dev/null; [ $? = 2 ] || fail "an area rule without the pack's area prefix was taken"
  # Bugs: a Codex reviewer and no codex on PATH: the run builds no card and says what is missing; with the reviewer
  # on Claude, the same PATH builds the card, though the pack still lists Codex models (they gate nothing).
  echo "[$(issue 25 2026-01-04 urgent)]" > "$STUB/issues.json"; mv "$STUB/codex" "$STUB/codex.off"
  np=$(tr : '\n' <<<"$PATH" | while read -r d; do [ -x "$d/codex" ] || printf '%s:' "$d"; done)
  out=$(PATH=${np%:} loop run 2>&1) && fail "a run with codex missing exited zero"
  grep -q "the reviewer is set to codex x, and codex is not installed on this host" <<<"$out" && [ -z "$(st 'select(.issue == 25)')" ] || fail "a card was built with codex missing: $out $(st 'select(.issue == 25)')"
  seatset reviewer claude-opus-5-5
  PATH=${np%:} loop run >/dev/null 2>&1; [ -n "$(st 'select(.issue == 25 and .step == "picked")')" ] || fail "a pack that lists Codex models was held for codex with no seat on it"
}
