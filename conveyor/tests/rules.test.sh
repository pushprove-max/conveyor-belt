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

# The card of the case's one picked issue, run by card() in a shell of the engine (fx_in), not by a loop run: the
# pick takes the issue, and card() runs it to its end. A case calls this only for what card() alone makes as it goes.
rulecard() { # <issue> [<commands after the card, with its card in $c>]
  fx_in 'cd "$R" && read -r c n _ <<<"$(locked pick "" "" "$(asked)")" && [ "$n" = '"$1"' ] || { echo "pick took ${n:-nothing}"; exit 3; }; card "$c" "$n"; '"${2:-}"
  [ "$RC" != 3 ] && [ -s "$ST/cards.jsonl" ] || fail "#$1 was not picked (exit $RC): $(tail -n 20 "$T/$CASE/run.out")"
}
# A worktree of main, $T/$CASE/cards/<name>, with <change> made in it and staged, as a card's change is staged.
rulewt() { # <name> <change>
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/$1" && (cd "$T/$CASE/cards/$1" && eval "$2") && git -C "$T/$CASE/cards/$1" add -A \
    || fail "the worktree $1 and its change"
}

# Bugs: a build, fix, test-fix or rebase session is not given the card rules (its flags load no CLAUDE.md and
# no .claude/rules/), gets them twice, or anywhere but between the header and the issue; the reviewer is not given the
# same rules (plan section 10); a missing or empty rules file lets the card build without them, or blocks it with a reason that does not
# name the file. The card rules are not the core rules followed by the pack's.
t_rules() {
  local f=$T/$CASE/expected p i k h d=$T/$CASE/p
  printf '%s\n\n%s\n' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")" > "$f"
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$d/w"; echo 'Mutation-verified: broke X' > "$d/w.trailers"; echo 'FAIL widget.test.ts' > "$d/w.test"
  echo "$GO" > "$STUB/review.1"; sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  # The card's prompt (cardprompt()) of the header, brief and rules card() makes for #7, then each session's as card()
  # makes it from that prompt: the build's (that prompt), the fix's (fixprompt()), the test fix's (testfixprompt()),
  # the rebuild's and the port's (rebaseprompt()); and what review() hands the reviewer (the stub codex keeps its
  # stdin), given that prompt and what the review is shown beside the diff (reviewseen()), as card() gives it.
  cat > "$d/make.sh" <<'EOS'
W=$T/$CASE/p/w
i=$(gh issue view 7 --json number,title,body,labels,milestone) && h=$(header on) && b=$(brief c0-7 "$i" "$h") && r=$(cardrules "$i") \
  && s=$(cardprompt c0-7 "$h" "$r" "$b") && v=$(reviewseen "$W" '') || exit 1
cd "$T/$CASE/p" || exit 1
printf '%s' "$s" > 1 && fixprompt "$s" 'E1 [P1] a.txt:1 wrong word' > 2 && testfixprompt "$s" "$W" 1 > 3 \
  && rebaseprompt "$s" "$W" 'CONFLICT (content): a.txt' abc > 4 && rebaseprompt "$s" "$W" 'CONFLICT (content): a.txt' abc port > 5 || exit 1
review "$W" "$s$v" "$REVIEW" > /dev/null && cp "$STUB/asked" review && head -n 1 <<<"$REVIEW" > reviewhead
EOS
  fx_in '. "$T/$CASE/p/make.sh"'
  [ "$RC" = 0 ] || fail "the prompts could not be made (exit $RC): $(cat "$T/$CASE/run.out")"
  for i in 1 2 3 4 5 review; do
    k=$(sed -n "${i/review/6}p" <<<$'build\n# Reviewer findings\n# The changed tests fail (exit 1)\n# Landing conflict\nOne review of this port alone follows\n# The commit trailers')
    [ "$i" = 1 ] || grep -q "^$k" "$d/$i" || fail "prompt $i is not the $k prompt"
    [ "$(grep -cx '# Rules' "$d/$i")" = 1 ] && [ "$(grep -cxF "$(head -n 1 "$f")" "$d/$i")" = 1 ] \
      || fail "prompt $i ($k) does not hold the rules heading and text exactly once"
    [ "$(sed -n '/^# Rules$/,/^# Issue #7:/p' "$d/$i" | sed '1,2d;$d')" = "$(cat "$f")" ] \
      || fail "prompt $i ($k): the text between # Rules and the issue is not the core rules, then the pack's"
    # The header opens each session's prompt; the reviewer's comes after its instructions (REVIEW).
    h=$(grep -n '^Conveyor card c0-7\. Make the change' "$d/$i" | head -n 1 | cut -d: -f1)
    { [ "$i" = review ] && [ "$(head -n 1 "$d/$i")" = "$(cat "$d/reviewhead")" ] || [ "$h" = 1 ]; } \
      && [ "$(grep -nx '# Rules' "$d/$i" | cut -d: -f1)" -gt "$(awk -v h="${h:-1000000}" 'NR >= h && /keeps the work\.$/ { print NR; exit }' "$d/$i")" ] \
      || fail "prompt $i ($k): the rules do not come after the header"
  done
  grep -qx 'FAIL widget.test.ts' "$d/3" && grep -qx 'Mutation-verified: broke X' "$d/review" || fail "the test fix is not given the test output, or the reviewer the trailers"
  # Bug (#779): a card session is not told that a test checks its behaviour directly, and that a proxy check (other
  # test files, the real loop, polling) says why in a comment. This reads the build's prompt, not the rules file: only
  # that prompt shows the rule reaches the session.
  grep -qxF -- '- A test the card adds or changes checks the behaviour it protects directly. A test that runs other test files or the suite runner, runs the real loop, or polls a real process until a condition holds says why in a comment beside it: what a direct check cannot show. A reviewer flags one with no such comment as P3.' "$d/1" \
    || fail "the build session was not given the direct-check rule"
  # A missing, then an empty rules file: the rules loader fails, saying why with the file's name, the reason card()
  # blocks the card with (`brief: <why>`) before any session.
  printf ' \n\n' > "$T/$CASE/empty.md"
  for p in "$T/$CASE/none.md" "$T/$CASE/empty.md"; do
    fx_in 'RULES='"$p"'; cardrules "$(gh issue view 7 --json number,title,body,labels,milestone)"'
    [ "$RC" = 1 ] && [ "$(cat "$T/$CASE/run.out")" = "the card rules file $p is missing or empty; a card never builds without it" ] \
      || fail "rules file $p: the rules loader did not fail naming the file (exit $RC): $(cat "$T/$CASE/run.out")"
  done
}

# Bugs (plan section 10): an area rule file the pack maps to a path the issue names (a root file or top-level
# directory too) is not given to the card, or is given to a card whose issue names no such path; the card's settings
# are not the generic settings with the pack's hooks after the generic ones of each event; a generic hook is named
# relative to the project, not by its pinned path in the engine's checkout; a pack hooks.json of another shape (one
# that would set what the generic settings set) is taken, so the card builds.
t_packrules() {
  local s=$T/$CASE/settings r x
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "It breaks in web/src/a.tsx:12, package.json and tools/ too."'), $(issue 8 2026-01-02)]"
  echo 'WEB-AREA-RULE' > "$R/.conveyor/web.md"; echo 'NPM-AREA-RULE' > "$R/.conveyor/npm.md"; echo 'TOOLS-AREA-RULE' > "$R/.conveyor/tools.md"
  tune '.areas = {"infra/**": ".conveyor/none.md", "web/src/**": ".conveyor/web.md", "package.json": ".conveyor/npm.md", "tools/": ".conveyor/tools.md"}'
  # The rules of each issue, and the settings made of the pack's hooks.json (the fixture's: lib/test-hooks.json), as
  # card() asks for them.
  fx_in 'for n in 7 8; do cardrules "$(gh issue view $n --json number,title,body,labels,milestone)" > "$T/$CASE/rules.$n" || exit 1; done; cardsettings "'"$s"'"'
  [ "$RC" = 0 ] || fail "the rules or the settings could not be made (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/rules.7")" = "$(printf '%s\n\n%s\n\nWEB-AREA-RULE\n\nNPM-AREA-RULE\n\nTOOLS-AREA-RULE' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")")" ] \
    || fail "#7 names web/src/a.tsx, the root file package.json and the top-level directory tools/: its rules are not the core rules, the pack's, then web.md, npm.md and tools.md"
  [ "$(cat "$T/$CASE/rules.8")" = "$(printf '%s\n\n%s' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")")" ] || fail "#8 names no area path and was given an area rule"
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
  # A hooks.json that sets permissions too: refused, saying why, which card() blocks the card with before any session.
  jq '. + {permissions: {allow: ["Bash"]}}' "$SRC/lib/test-hooks.json" > "$R/.conveyor/hooks.json"
  fx_in 'cardsettings "$T/$CASE/other"'
  [ "$RC" != 0 ] && grep -qF "$R/.conveyor/hooks.json is not {\"hooks\": {<event>: [...]}}" "$T/$CASE/run.out" \
    || fail "a hooks.json of another shape was taken for the card settings (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Bugs: a card lands a change that breaks tests, because nothing ran them: its worktree has no dependencies (a link
# whose parent folder the worktree does not have, as cache/ is main's alone, failed); a dependency link is staged and
# lands (main's ignore rule has a trailing slash, which no link matches); the brief names folders the pack does not
# link, rather than the pack's linkFromMain, or does not say the loop runs the changed tests.
t_tests() {
  local w
  setup "[$(issue 7 2026-01-01)]"; w=$T/$CASE/cards/c7
  mkdir -p "$R/node_modules/dep" "$R/web/node_modules/wdep" "$R/infra" "$R/cache/deps/cdep"; echo '{}' | tee "$R/package.json" "$R/web/package.json" > "$R/infra/package.json"
  tune '.linkFromMain += ["cache/deps"]'
  printf 'conveyor/\n.conveyor/\nnode_modules/\ncache/\n' > "$R/.gitignore"; git -C "$R" add -A; git -C "$R" commit -qm deps
  # The card's worktree as card() makes it, its links made by deps() and its brief's header by header(), as card()
  # calls them; then the card's change staged as card() stages it (git add -A).
  git -C "$R" worktree add -q --detach "$w" refs/heads/main || fail "the card's worktree"
  fx_in 'deps "'"$w"'" && header'
  [ "$RC" = 0 ] || fail "the dependencies could not be linked (exit $RC): $(cat "$T/$CASE/run.out")"
  [ -L "$w/node_modules" ] && [ -d "$w/node_modules/dep" ] && [ -L "$w/web/node_modules" ] && [ -d "$w/web/node_modules/wdep" ] && [ ! -e "$w/infra/node_modules" ] \
    && [ -L "$w/cache/deps" ] && [ -d "$w/cache/deps/cdep" ] || fail "the worktree does not have main's dependency links: $(ls -la "$w" "$w/web" "$w/cache" 2>&1 | tr '\n' ' ')"
  echo two >> "$w/a.txt"; git -C "$w" add -A
  [ "$(git -C "$w" diff --cached --name-only | tr '\n' ' ')" = "a.txt " ] || fail "a dependency link was staged: $(git -C "$w" diff --cached --name-only | tr '\n' ' ')"
  # Bug: the brief names folders the pack does not link, rather than the pack's linkFromMain.
  grep -qF 'linked from the main checkout: node_modules, infra/node_modules, packages/sample-node/node_modules, web/node_modules, cache/deps.' "$T/$CASE/run.out" \
    && grep -q 'the loop runs the changed tests itself' "$T/$CASE/run.out" || fail "the brief does not say the dependencies are there and the loop runs the tests: $(cat "$T/$CASE/run.out")"
}

# Bugs: a card whose tests pass after their one fix round does not land; a card landing on its last review's NO-GO
# skips its tests, or files the follow-ups before they have passed; a failed run names a file the test itself logged
# (`-- FAIL widget.test.ts`) beside the one the runner ran; the build session is not given the card's settings file,
# or that file is left once the card has landed.
t_testsland() {
  local p
  setup "[$(issue 7 2026-01-01)]"
  for i in 1 2 3 4; do moved "$i" "$NOGO" > "$STUB/review.$i"; done
  # The build adds a line and keeps the settings file it is given, as it is while the session runs; each later session
  # changes the card, so each review after it reads a new change. The first run fails, and its run again too (tests());
  # the run after the test fix passes, marking whether it came before any follow-up was filed.
  cat > "$STUB/build" <<'EOS'
if [ "$(wc -l < "$STUB/sessions")" = 1 ]; then echo two >> a.txt; a=("$@"); for i in "${!a[@]}"; do [ "${a[i]}" != --settings ] || cp "${a[i+1]}" "$STUB/settings"; done
else wc -l < "$STUB/sessions" > fixed.txt; fi
EOS
  echo 'echo x >> "$STUB/tests"; [ "$(wc -l < "$STUB/tests")" -gt 2 ] || { echo "FAIL widget.test.ts"; exit 1; }; [ -e "$STUB/filed" ] || : > "$STUB/tested-first"' > "$STUB/test-cmd"
  # A whole card: that its test step, after the last review's NO-GO and the test fix, goes on to file and land is
  # card()'s own order of steps, which no function of it makes alone.
  rulecard 7
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start fix start review start test start fix start review start test start filed start landed " ] \
    || fail "steps of a card landing on a last NO-GO after its test fix: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "test") | .result' | tr '\n' ' ')" = "fail pass " ] && [ -e "$STUB/tested-first" ] \
    && [ "$(st 'select(.step == "landed") | [.sha, (.followups | length)] | tojson')" = "[\"$(git -C "$R" rev-parse main)\",1]" ] \
    || fail "the card did not land with its follow-up after its tests passed, or filed it first: $(st 'select(.step == "test" or .step == "landed")')"
  [ "$(st 'select(.step == "test" and .result == "fail") | .failures.files | map(.file) | join(" ")')" = a.test.sh ] \
    || fail "the failed test step does not name a.test.sh alone: $(st 'select(.step == "test" and .result == "fail") | .failures | tojson')"
  p=$T/$CASE/cards/$(st '.card' | head -n 1).settings
  [ "$(sed -n '1s/.*--settings \([^ ]*\) .*/\1/p' "$STUB/sessions")" = "$p" ] && [ -s "$STUB/settings" ] && [ ! -e "$p" ] \
    || fail "the build session was not given the card's settings file, or it was left once the card landed: $(head -n 1 "$STUB/sessions")"
  recok "$ST/cards.jsonl" "a card that landed after its test fix"
}

# Bugs: a failing test run blocks the card with no fix round, or gets more than one; the fix session is not handed the
# issue and the last 200 lines of the test output; a card whose tests fail twice lands, files the follow-ups of its
# last review's NO-GO, leaves main dirty or leaves its worktree; its blocked line's reason is not the one sentence, or
# its tail is not the last 60 lines of the output, each line whole: a cap on a line's length loses what it says after
# the cut, and makes lines that differ only there fold as identical on the Board. Lines that long, 60 of them, are
# more than one command argument can hold: the line is written all the same, its sentence and its output.
t_testsfix() {
  local head out
  setup "[$(issue 7 2026-01-01)]"
  for i in 1 2 3 4; do moved "$i" "$NOGO" > "$STUB/review.$i"; done
  echo 'echo x >> "$STUB/tests"; seq 300 | sed "s/^/out line /"; for i in $(seq 59); do printf "FAIL %03000d\n" 0; done; echo "FAIL gadget.test.ts: expected 2"; printf "%s\n" "== gadget.test.ts" "-- FAIL gadget.test.ts" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1' > "$STUB/test-cmd"
  head=$(git -C "$R" rev-parse HEAD)
  # A whole card: the one fix round, and the block after it, are card()'s test step, which only the card's own run
  # takes after its reviews.
  rulecard 7
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start fix start review start test start fix start review start test blocked " ] \
    || fail "steps of a NO-GO card whose tests fail twice: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(wc -l < "$STUB/sessions") $(wc -l < "$STUB/reviews") $(wc -l < "$STUB/tests")" = "4 4 4" ] \
    || fail "sessions, reviews and test runs are $(wc -l < "$STUB/sessions") $(wc -l < "$STUB/reviews") $(wc -l < "$STUB/tests"), not 4 4 4"
  # The test-fix session's brief: the issue, and the end of the output (the last 200 lines hold no more than 140 of
  # the 300 `out line` lines). Bug: a cut of 100 lines kept these lines all the same; the part after the
  # heading is counted, and ends with the output's last line (the run's LINKED note).
  out=$(sed '1,/^# The changed tests fail (exit 1): fix that and nothing else\. The end of the test output:$/d' "$STUB/brief")
  grep -q '^# The changed tests fail' "$STUB/brief" && grep -qx 'FAIL gadget.test.ts: expected 2' <<<"$out" && grep -qx 'out line 300' <<<"$out" \
    && ! grep -qx 'out line 160' <<<"$out" && [ "$(grep -c '' <<<"$out")" = 200 ] && [[ "$(tail -n 1 <<<"$out")" == "conveyor: the change adds or changes no test file"* ]] \
    && grep -q '^# Issue #7:' "$STUB/brief" || fail "the fix session was not handed the issue and the last 200 lines of the test output: $(grep -c '' <<<"$out") lines, the last $(tail -n 1 <<<"$out" | cut -c1-200)"
  [ "$(st 'select(.step == "blocked") | .reason')" = "the changed tests failed again after their one fix round (exit 1); nothing landed." ] \
    || fail "the blocked reason is not the one sentence: $(st 'select(.step == "blocked") | .reason')"
  # After the stub's lines come the run's own: a.test.sh's end (`-- FAIL a.test.sh`: filecmd()) and the note of the
  # linked files it ran (LINKED).
  [ "$(st 'select(.step == "blocked") | .tail | split("\n") | [length, (.[0] | length), .[-3], .[-2], (.[-1] | startswith("conveyor: the change adds or changes no test file")), (.[-5] == .[-4] and (.[-4] | startswith("FAIL 000") and length == 3005))] | join("|")')" = "60|3005|FAIL gadget.test.ts: expected 2|-- FAIL a.test.sh|true|true" ] \
    || fail "the blocked line's tail is not the last 60 lines of the test output: $(st 'select(.step == "blocked") | .tail' | cut -c1-400)"
  recok "$ST/cards.jsonl" "a card whose tests failed twice"
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ -z "$(ls "$T/$CASE/cards")" ] && [ ! -s "$STUB/filed" ] \
    || fail "a card whose tests failed twice landed, left main dirty, left its worktree or filed a follow-up"
  grep -q 'FAIL gadget' "$(st 'select(.step == "blocked") | "\($ENV.ST)/\(.kept)"')"/*.test || fail "the test output was not kept"
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
  local w=$T/$CASE/cards/c0-7 f
  setup "$(jq -cs . <(issue 7 2026-01-01))"; mkdir -p "$w.1.testlog" "$w.2.testlog" "$ST"
  # ran <run> <file> <ok | FAIL | - (still running when the clock stopped the run)> <its lines>...: one file of the run,
  # its output and the runner's log (run.log) as filecmd() writes them: `== <file>` as it begins, `-- <end> <file>`
  # as it ends.
  ran() {
    { echo "== $2" | tee -a "$w.$1.testlog/run.log"; printf '%s\n' "${@:4}"; [ "$3" = - ] || echo "-- $3 $2" | tee -a "$w.$1.testlog/run.log"; } >> "$w.$1.test"
  }
  # Run 1, of four files: two fail, one case each, one with a line over 200 characters and a second FAIL line, after a
  # `== ` line of its own that is no file of the run; the other after the `== ` line of a file that passed, earlier.
  # A passing file prints a FAIL line of its own.
  echo 'TESTRUN files=4' > "$w.1.testlog/run.log"
  ran 1 tests/a.test.sh ok 'ok alpha'
  ran 1 conveyor/conveyor.test.sh FAIL 'ok lane' '== diagnostic' "FAIL [views]: the snapshot lacks $(printf 'word %.0s' $(seq 60))end" 'FAIL [views]: a second line' 'conveyor: left 2 stubs running'
  ran 1 tests/b.test.sh FAIL '== tests/a.test.sh' 'FAIL [beta]: expected 2, got 3' 'ok gamma'
  ran 1 tests/c.test.sh ok 'FAIL [own]: words a passing test prints' 'ok delta'
  # Run 2, of four files, out of time (2 s) in its third: a TAP file fails (its TODO case does not), a file fails
  # naming no case, and z.test.sh never began.
  echo 'TESTRUN files=4' > "$w.2.testlog/run.log"
  ran 2 tests/d.test.mjs FAIL 'not ok 1 - rejects invalid input' 'ok 2 - fine' 'not ok 3 - later # TODO'
  ran 2 tests/e.test.sh FAIL 'e.test.sh: line 3: syntax error'
  ran 2 tests/slow.test.sh - 'ok one'
  # The failure parser on each, with the run's exit and the step's timeout, as card()'s test step calls it.
  fx_in 'TEST_TIMEOUT=2; testfails "'"$w"'.1.test" 1 > "'"$w"'.1.fails" && testfails "'"$w"'.2.test" 124 > "'"$w"'.2.fails"'
  [ "$RC" = 0 ] || fail "the failure parser failed (exit $RC): $(cat "$T/$CASE/run.out")"
  f() { jq -r "$2" "$w.$1.fails"; }
  [ "$(f 1 '[.of, .timeout, (.files | map([.file, (.cases | map(.name) | join(","))] | join(":")) | join(" "))] | tojson')" \
    = '[4,null,"conveyor/conveyor.test.sh:views tests/b.test.sh:beta"]' ] || fail "the failing files and cases are not exactly the two that failed: $(f 1 'tojson')"
  [ "$(f 1 '.files[1].cases[0].line')" = "FAIL [beta]: expected 2, got 3" ] || fail "a case's line is not its first FAIL line: $(f 1 'tojson')"
  [ "$(f 1 '.files[0].cases[0].line | [(length <= 200 and length > 190), startswith("FAIL [views]: the snapshot lacks word"), endswith(" word")] | tojson')" = '[true,true,true]' ] \
    || fail "a long first line is not cut to 200 characters at a word: $(f 1 '.files[0].cases[0].line')"
  f 1 '{of, files, timeout} | tojson' | grep -q 'ok \|alpha\|left 2 stubs\|second line\|diagnostic\|own' && fail "a passing file, an ok line, a warning, a later FAIL line or a test's own == line is among the failures: $(f 1 'tojson')"
  [ "$(f 2 '[.of, .timeout] | tojson')" = '[4,{"sec":2,"file":"tests/slow.test.sh"}]' ] || fail "a run that timed out does not say so and name the file still running, of the files selected: $(f 2 'tojson')"
  [ "$(f 2 '.files | tojson')" = '[{"file":"tests/d.test.mjs","cases":[{"name":"rejects invalid input","line":"not ok 1 - rejects invalid input"}]},{"file":"tests/e.test.sh","cases":[]}]' ] \
    || fail "a file that failed with a TAP line, or with no case line at all, is not listed: $(f 2 '.files | tojson')"
  # Each failed run's line as card()'s test step makes it (failline(): no verdicts of a run on main, no carried part).
  fx_in 'failline "'"$w"'.1" 1 2 "$(<"'"$w"'.1.fails")" "{\"verdicts\":[]}" "{}" > "'"$w"'.1.line" && failline "'"$w"'.2" 124 2 "$(<"'"$w"'.2.fails")" "{\"verdicts\":[]}" "{}" > "'"$w"'.2.line"'
  [ "$RC" = 0 ] || fail "the failed test lines could not be made (exit $RC): $(cat "$T/$CASE/run.out")"
  # The exit is said as it was: a note on 124 beside an exit 1 reads as a timeout that never happened. A run that
  # timed out says so with the file still running; its failures are the parser's, with their cases; the tail is the
  # output, a line a line.
  [ "$(jq -r .reason "$w.1.line")" = "exit 1" ] || fail "the reason of a run that exited 1: $(jq -r .reason "$w.1.line")"
  # Bug: a tail of more than the output's last 60 lines makes a failed run's line, on the Board, as long as its output.
  # Run 3 printed 70 lines and no runner's log.
  seq -f 'line %g' 70 > "$w.3.test"
  fx_in 'failline "'"$w"'.3" 1 2 null "{\"verdicts\":[]}" "{}"'
  [ "$RC" = 0 ] && [ "$(jq -c '.tail | split("\n") | [length, .[0], .[-1]]' "$T/$CASE/run.out")" = '[60,"line 11","line 70"]' ] \
    || fail "the line of a run with a long output does not keep its last 60 lines alone (exit $RC): $(head -c 300 "$T/$CASE/run.out")"
  [ "$(jq -r .reason "$w.2.line")" = "exit 124: timed out after 2s in tests/slow.test.sh" ] || fail "the reason of a run that timed out: $(jq -r .reason "$w.2.line")"
  [ "$(jq -c .failures "$w.2.line")" = "$(f 2 'del(.passed, .okcases, .passcases) | tojson')" ] && [ "$(jq -c '.failures.files[0].cases' "$w.2.line")" = '[{"name":"rejects invalid input","line":"not ok 1 - rejects invalid input"}]' ] \
    || fail "the timed-out line's failures are not the parser's, with their cases: $(jq -c .failures "$w.2.line")"
  [ "$(jq -r '.tail | split("\n") | [.[0], .[1], .[-2], .[-1]] | join("|")' "$w.2.line")" = "== tests/d.test.mjs|not ok 1 - rejects invalid input|== tests/slow.test.sh|ok one" ] \
    || fail "the timed-out line's tail is not the output, a line a line: $(jq -r .tail "$w.2.line")"
  # The Board reads them from the card's steps: the two failed lines, then the blocked line.
  { landed 7 | jq -c '.step = "picked" | .sha = "" | .title = "title 7" | del(.product)'
    for i in 1 2; do
      jq -c --arg t "2026-11-01T00:0$i:00Z" '{card: "c0-7", issue: 7, step: "test", time: $t, tokens: {claude: 0, codex: 0}, result: "fail", sha: ""} + .' "$w.$i.line"
    done
    landed 7 | jq -c '.step = "blocked" | .result = "blocked" | .sha = "" | .time = "2026-11-01T00:05:00Z" | .reason = "the changed tests failed again after their one fix round (exit 124); nothing landed." | del(.product)'
  } >> "$ST/cards.jsonl"
  recok "$ST/cards.jsonl" "the failed test lines"
  [ "$(loop snapshot --fresh | jq -c '.needsYou.blocked[0].track.records | map(select(.name == "tests failed") | [.why, (.failures.files | length), .failures.timeout.file, (.output | test("FAIL \\[beta\\]|not ok 1 "))])')" \
    = '[["exit 1",2,null,true],["exit 124: timed out after 2s in tests/slow.test.sh",2,"tests/slow.test.sh",true]]' ] \
    || fail "the card's steps lack a failed run's failures or output: $(loop snapshot --fresh | jq -c '.needsYou.blocked[0].track.records')"
}

# Bugs: a host's commit-msg hook refuses every card that needs a line only the builder can write, because the card
# cannot put one in Conveyor's message; a line not of the trailer shape, or a Co-Authored-By, is kept; the review
# does not see the trailers; a pack rule's trailer is missing and the card does not owe it; a pack with no
# commit.trailers asks for a trailer; a path git quotes (café/) escapes the rule; a rule whose when is not a valid ERE
# silently requires nothing.
t_trailers() {
  local d=$T/$CASE/cards
  setup '[]'
  # The staged changes the trailers are read on: each a worktree of main, its trailers file beside it.
  rulewt 10 'touch a-guard.test.ts'
  rulewt 7 'echo two >> a.txt; printf "%s\n" "Mutation-verified: broke X, test went red" "not a trailer line" "Co-Authored-By: someone" "-x: no token" > "$PWD.trailers"'
  rulewt 8 'touch b-guard.test.ts'
  rulewt 9 'mkdir -p café; touch café/c-guard.test.ts'
  # The trailer filter, the brief's section and owing() as card() calls them: first with no pack rule, then with the
  # pack's rule for an added guard-class test, then with a rule whose when grep cannot read.
  fx_in 'owing "$d/10" > "$d/owe.10" && trailerbrief "$d/10" > "$d/brief.10" && trailers "$d/7" > "$d/kept.7" && trailerview "$d/7" > "$d/view.7" || exit 1
    tune '"'"'.commit.trailers = [{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke and how the test went red."}]'"'"'
    owing "$d/8" > "$d/owe.8" && trailerbrief "$d/8" > "$d/brief.8" && owing "$d/9" > "$d/owe.9" || exit 2
    echo "Mutation-verified: removed the check, the test went red" > "$d/9.trailers"; owing "$d/9" > "$d/owe.9.written" || exit 2
    tune '"'"'.commit.trailers = [{"when": "[", "token": "Mutation-verified", "ask": "Say what you broke."}]'"'"'
    ! owing "$d/8" || exit 3'
  [ "$RC" = 0 ] || fail "the trailers could not be read as asked (exit $RC: 1 with no rule, 2 with the rule, 3 an invalid when was taken): $(cat "$T/$CASE/run.out")"
  # No pack rule: a change adding a guard test owes nothing; the brief names the trailers file.
  [ ! -s "$d/owe.10" ] || fail "a pack with no commit.trailers asked for a trailer: $(cat "$d/owe.10")"
  grep -qF "$d/10.trailers, one a line" "$d/brief.10" || fail "the build prompt does not name the trailers file: $(cat "$d/brief.10")"
  # The kept lines: only the trailer; a line not of the shape and a Co-Authored-By are dropped, and the review sees the kept one.
  [ "$(cat "$d/kept.7")" = 'Mutation-verified: broke X, test went red' ] || fail "the kept trailers are not the one trailer: $(cat "$d/kept.7")"
  grep -qx 'Mutation-verified: broke X, test went red' "$d/view.7" && ! grep -q 'not a trailer line\|Co-Authored-By\|no token' "$d/view.7" || fail "the review is not shown the kept trailers alone: $(cat "$d/view.7")"
  # The pack's rule: an added guard test with no trailer owes it, and the prompt carries the rule.
  [ "$(cat "$d/owe.8")" = '{"token":"Mutation-verified","ask":"Say what you broke and how the test went red.","paths":["b-guard.test.ts"]}' ] \
    || fail "a change missing a required trailer does not owe it: $(cat "$d/owe.8")"
  grep -q 'adds a file whose path matches the extended regular expression `(conformance|guard|parity|coverage)' "$d/brief.8" || fail "the prompt does not carry the pack's rule: $(cat "$d/brief.8")"
  # A path git quotes owes it whole, and owes nothing once the trailer is written.
  [ "$(jq -c .paths "$d/owe.9")" = '["café/c-guard.test.ts"]' ] && [ ! -s "$d/owe.9.written" ] \
    || fail "a path git quotes escaped the rule, or its written trailer was not counted: $(cat "$d/owe.9" "$d/owe.9.written")"
  # Bugs: the trailer the one fix session writes, asked for it, is not reviewed again; or it is lost from the commit
  # when the tests delete the trailers file. A whole card: that the fix goes back to review, and that the commit takes
  # the trailers as they were reviewed and not as the tests leave them, is card()'s own order of steps.
  tune '.commit.trailers = [{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke and how the test went red."}]'
  echo "[$(issue 9 2026-01-01)]" > "$STUB/issues.json"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  printf '%s\n' 'mkdir -p café; touch café/c-guard.test.ts' '[ "$(wc -l < "$STUB/sessions")" -lt 2 ] || echo "Mutation-verified: removed the check, the test went red" > "$PWD.trailers"' > "$STUB/build"
  echo 'rm -f "$PWD.trailers"' >> "$STUB/test-cmd"
  rulecard 9
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix start review start test start landed " ] \
    && [ "$(wc -l < "$STUB/sessions") $(wc -l < "$STUB/reviews")" = "2 2" ] && grep -qx 'Mutation-verified: removed the check, the test went red' "$STUB/asked" \
    || fail "the trailer the fix session wrote was not reviewed again: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  # The whole message, so the trailer is checked in its place: after Closes, before the Conveyor card line.
  [ "$(git -C "$R" log -1 --format=%B main)" = "feat(product): title 9 (#9)"$'\n\n'"Closes #9"$'\n'"Mutation-verified: removed the check, the test went red"$'\n'"Conveyor card $(st 'select(.step == "landed") | .card')" ] \
    || fail "the trailer the fix session wrote did not land after Closes, though the tests deleted its file: $(git -C "$R" log -1 --format=%B main)"
}

# Bug: a required trailer still missing after the one fix session that asked for it does not stop the card, so it
# commits without the trailer, or it gets no such session. A whole card: that the block comes after that one fix
# session, before the tests and the commit, is card()'s own order of steps.
t_trailermissing() {
  local head
  setup "[$(issue 8 2026-01-01)]"
  tune '.commit.trailers = [{"when": "(conformance|guard|parity|coverage)[^/]*\\.test\\.(ts|tsx)$", "token": "Mutation-verified", "ask": "Say what you broke and how the test went red."}]'
  echo "$GO" > "$STUB/review.1"; echo 'touch b-guard.test.ts' > "$STUB/build"; head=$(git -C "$R" rev-parse main)
  rulecard 8
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review start fix blocked " ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && grep -q 'Say what you broke and how the test went red. It adds b-guard.test.ts.' "$STUB/brief" \
    || fail "a card missing a required trailer did not get one fix session asking for it, then stop: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  st 'select(.step == "blocked") | .reason' | grep -qF 'missing after its one fix session; nothing landed: Mutation-verified (it adds b-guard.test.ts)' \
    && [ "$(git -C "$R" rev-parse main)" = "$head" ] || fail "a card missing a required trailer was not blocked with the reason, or landed: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
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

# Bugs: a change that fails a product check (here two of the case's own: a baseline raised, a schema added) passes,
# or the check's own lines are not in what blocks the card: a check's verbose output (more than one command argument
# can hold) comes before its failing line, and the blocked line's tail keeps the end, so that line is not lost behind
# it; a clean change fails.
t_checks() {
  local d=$T/$CASE/cards o=$T/$CASE k
  setup "[$(issue 7 2026-01-01)]"
  echo '{"hex":3}' > "$R/baseline.json"; echo 'SCHEMA_4' > "$R/schema.txt"
  git -C "$R" add -A; git -C "$R" commit -qm ratchets
  cat > "$STUB/raise-check.sh" <<'CHECK'
a=$(git show "$1:baseline.json" | jq .hex); b=$(git show "$2:baseline.json" | jq .hex)
[ "$b" -le "$a" ] || { printf 'a%.0s' {1..1000}; echo; printf '12345678\n%.0s' {1..20000}; echo "LOOSENED baseline.json hex: $a -> $b"; exit 1; }
CHECK
  cat > "$STUB/schema-check.sh" <<'CHECK'
! git diff "$1" "$2" -- schema.txt | grep -q '^+SCHEMA_5' || { echo "adds schema 5 with no old-format test"; exit 1; }
CHECK
  tune --arg a "$STUB/raise-check.sh" --arg b "$STUB/schema-check.sh" '.checks = [$a, $b]'
  rulewt raise 'echo "{\"hex\":4}" > baseline.json'; rulewt schema 'echo SCHEMA_5 >> schema.txt'; rulewt lower 'echo "{\"hex\":2}" > baseline.json'
  # The checks runner on each change (main's commit and one of the staged change on it), as card() calls it.
  fx_in 'for k in raise schema lower; do checks "$d/$k" > "$o/$k.out"; echo "$k $?"; done'
  [ "$(head -n 3 "$T/$CASE/run.out" | tr '\n' ' ')" = "raise 1 schema 1 lower 0 " ] || fail "the checks did not fail the raised baseline and the added schema alone: $(cat "$T/$CASE/run.out")"
  [ "$(head -n 1 "$o/raise.out")" = 'raise-check.sh (exit 1):' ] && [ "$(tail -n 1 "$o/raise.out")" = 'LOOSENED baseline.json hex: 3 -> 4' ] && ! grep -q schema-check "$o/raise.out" \
    || fail "the raised baseline's lines are not the first check's own: $(head -c 300 "$o/raise.out")"
  grep -qx 'schema-check.sh (exit 1):' "$o/schema.out" && grep -qx 'adds schema 5 with no old-format test' "$o/schema.out" && ! grep -q raise-check "$o/schema.out" \
    || fail "the added schema's lines are not the second check's own: $(cat "$o/schema.out")"
  [ ! -s "$o/lower.out" ] || fail "a clean change printed check lines: $(cat "$o/lower.out")"
  # Bug: a failed product check let the card go on to its tests or a fix session. A card whose change fails both
  # checks: a whole card, as where its checks stop it is card()'s own order of steps. It is blocked after its review,
  # with no test run and no session after its build, the lines of both checks at the end of its tail.
  echo 'echo "{\"hex\":4}" > baseline.json; echo SCHEMA_5 >> schema.txt' > "$STUB/build"; echo "$GO" > "$STUB/review.1"; k=$(git -C "$R" rev-parse HEAD)
  rulecard 7
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review blocked " ] && [ ! -e "$STUB/tests" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$k" ] || fail "a card that fails a product check landed, ran its tests or got a fix session: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "blocked") | .reason')" = "a product check failed; nothing landed." ] \
    && [ "$(st 'select(.step == "blocked") | .tail' | tail -n 3)" = $'LOOSENED baseline.json hex: 3 -> 4\nschema-check.sh (exit 1):\nadds schema 5 with no old-format test' ] \
    || fail "the blocked line is not the sentence with both checks' lines at the end of its tail: $(st 'select(.step == "blocked") | [.reason, .tail[-300:]]')"
  recok "$ST/cards.jsonl" "the block of a failed check"
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

# Bugs: the remote, branch, labels, owner and product paths are the host project's, whatever the pack says: a landed
# card's commit is looked for on main and pushed to origin when the pack names master and upstream; the commit subject
# does not read the pack's type label and area prefix; a visible change asks for Dana's yes when
# the owner is Quinn; the follow-up, type, priority and area labels, and the product paths, are the host project's.
t_pack() {
  local X np d
  setup "[$(issue 7 2026-01-01 defect team/billing)]"; O=$T/$CASE/up
  git -C "$R" branch -m main master; git -C "$R" remote remove origin
  git init -q --bare -b master "$O"; git -C "$R" remote add upstream "$O"
  P=$R/.conveyor/project.json
  jq '.remote = "upstream" | .defaultBranch = "master" | .owner.name = "Quinn" | .productPaths = ["app/"]
    | .labels = {built: "shipped", followup: "fu", type: "defect", priorities: ["urgent", "high", "low"], areaPrefix: "team/", nonProductAreas: ["team/tools"]}' "$P" > "$P.new" \
    && mv "$P.new" "$P" && git -C "$R" push -q upstream master
  # A card of #7, its change staged in its worktree of master: what review() hands the reviewer (the stub codex keeps
  # its stdin), the commit message card() lands it with (cardsubject()), its landing (land(), on the pack's branch), the
  # push the loop starts once a card has landed (owed() reads the pack's branch, push() its remote), and the reason of a
  # change that waits for the owner's yes (YES).
  rulewt c0-7 'echo three >> a.txt'; echo "$GO" > "$STUB/review.1"; sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  fx_in 'w=$T/$CASE/cards/c0-7; review "$w" "the brief" > /dev/null && m=$(cardsubject c0-7 "$(gh issue view 7 --json number,title,body,labels,milestone)") \
    && cd "$R" && land c0-7 7 "$w" "$m" && read -r c n _ <<<"$(owed)" && push "$c" "$n" && printf "%s\n" "$YES" > "$T/$CASE/yes"'
  [ "$RC" = 0 ] || fail "the review, landing or push failed (exit $RC): $(tail -n 5 "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse refs/heads/master)" ] && grep -qx three <(git -C "$R" show master:a.txt) \
    && ! git -C "$R" rev-parse -q --verify refs/heads/main >/dev/null || fail "the card did not land on master: $(st .)"
  [ "$(git -C "$O" rev-parse -q --verify refs/heads/master)" = "$(git -C "$R" rev-parse master)" ] || fail "the landed commit on master was not pushed to upstream: $(tail -n 5 "$T/$CASE/run.out")"
  [ "$(git -C "$R" log -1 --format=%s master)" = 'fix(billing): title 7 (#7)' ] || fail "the commit subject does not read the type label and area prefix: $(git -C "$R" log -1 --format=%s master)"
  grep -q "stops after review for Quinn's yes when" "$STUB/asked" && grep -q '(app/, tests aside)' "$STUB/asked" && ! grep -q "Dana's yes\|src/, shared/" "$STUB/asked" \
    || fail "the review prompt does not name the pack's owner and product paths"
  [ "$(cat "$T/$CASE/yes")" = "visible to customers or staff: needs Quinn's yes: " ] || fail "a visible change does not wait for the pack's owner: $(cat "$T/$CASE/yes")"
  # Health reads a card blocked with that reason as waiting for Quinn's yes.
  { landed 8 | jq -c '.step = "picked" | .sha = "" | .title = "title 8" | del(.product)'
    landed 8 | jq -c '.step = "blocked" | .result = "blocked" | .sha = "" | .reason = "visible to customers or staff: needs Quinn'"'"'s yes: guests see a new Pay button" | del(.product)'; } >> "$ST/cards.jsonl"
  [ "$(loop health | jq -c '.waiting | map(.issue)')" = '[8]' ] || fail "health does not list the card waiting for Quinn's yes: $(loop health)"
  # A last review's NO-GO files its follow-up with the pack's follow-up, type and priority labels and area label.
  printf '%s\n' '[P0] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$T/$CASE/c0-11.review"
  fx_in 'followups c0-11 '"'$(issue 11 2026-01-03 team/billing)'"' "$T/$CASE/c0-11.review"'
  [ "$RC" = 0 ] && [ "$(jq -c '[.labels[].name]' "$STUB/filed")" = '["fu","defect","urgent","team/billing"]' ] || fail "the follow-up's labels are not the pack's (exit $RC): $(cat "$STUB/filed" "$T/$CASE/run.out")"
  # Bugs: the pack's remote changed to an empty one: the commit pushed to the old one is unpushed, and the
  # push goes to the new one.
  X=$(git -C "$R" rev-parse master); git init -q --bare -b master "$T/$CASE/up2"; git -C "$R" remote add up2 "$T/$CASE/up2"
  jq '.remote = "up2"' "$P" > "$P.new" && mv "$P.new" "$P"
  loop health | jq -e --arg x "$X" '.unpushed | any(.sha == $x)' >/dev/null || fail "health hides a commit the pack's new remote lacks: $(loop health | jq -c .unpushed)"
  fx_in 'read -r c n _ <<<"$(owed)" && push "$c" "$n"'
  [ "$(git -C "$T/$CASE/up2" rev-parse -q --verify refs/heads/master)" = "$X" ] || fail "the push did not go to the pack's new remote: $(tail -n 5 "$T/$CASE/run.out")"
  jq '.remote = "upstream"' "$P" > "$P.new" && mv "$P.new" "$P"
  # Bugs: with the pack's built label not awaiting-deploy, an awaiting-deploy issue is still skipped, or an issue with
  # the pack's built label is picked; a pack with five priorities picks an older last one before a newer fourth one; an
  # area rule must start area:.
  jq '.labels.priorities = ["critical", "high", "medium", "low", "trivial"]' "$P" > "$P.new" && mv "$P.new" "$P"
  jq -cs . <(issue 21 2026-01-01 trivial) <(issue 22 2026-01-02 low) <(issue 23 2026-01-03 awaiting-deploy) <(issue 9 2026-01-04 critical shipped) > "$STUB/issues.json"
  # The pick order (upnext()) of the open issues, as pick() and the Board's queue read it.
  fx_in 'upnext "$(<"$STUB/issues.json")" | jq -c "map(.number)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[22,21,23]' ] || fail "the pick order is not the pack's priorities, awaiting-deploy was skipped or the built label was not (exit $RC): $(cat "$T/$CASE/run.out")"
  # Bugs: a pack with one priority: an issue with none is P3, so a P1 rule leaves it alone.
  # Bug (#220): the Foreman's watcher of a belt on another host has no pack to read foreman.waitWake from, so the
  # snapshot, made on the belt's host, gives it; without it such a watcher woke at 10 minutes whatever the pack said.
  jq '.labels.priorities = ["urgent"] | .foreman.waitWake = 5' "$P" > "$P.new" && mv "$P.new" "$P"
  echo "[$(issue 24 2026-01-01)]" > "$STUB/issues.json"; loop control rules P1=off >/dev/null
  fx_in 'upnext "$(<"$STUB/issues.json")" | jq -c "map([.number, .p])"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[[24,"P3"]]' ] || fail "an issue with no priority took a P1 rule (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(loop snapshot --fresh | jq -c '[.areaPrefix, .waitWake]')" = '["team/",5]' ] \
    || fail "the snapshot does not give the area prefix or the pack's foreman.waitWake: $(loop snapshot --fresh | jq -c '[.areaPrefix, .waitWake]')"
  loop control rules P1=on >/dev/null
  [ "$(loop control rules team/billing=off | jq -c .rules.never)" = '["team/billing"]' ] || fail "an area rule with the pack's area prefix was refused"
  loop control rules area:billing=off 2>/dev/null; [ $? = 2 ] || fail "an area rule without the pack's area prefix was taken"
  # Bugs: a Codex reviewer and no codex on PATH: the loop's preflight (clis()) starts no card and says what is
  # missing; with the reviewer on Claude, the same PATH passes it, though the pack still lists Codex models (they
  # gate nothing).
  mv "$STUB/codex" "$STUB/codex.off"
  np=$(tr : '\n' <<<"$PATH" | while read -r d; do [ -x "$d/codex" ] || printf '%s:' "$d"; done)
  PATH=${np%:} fx_in clis
  [ "$RC" != 0 ] && grep -q "the reviewer is set to codex x, and codex is not installed on this host" "$T/$CASE/run.out" || fail "the preflight passed with codex missing (exit $RC): $(cat "$T/$CASE/run.out")"
  seatset reviewer claude-opus-5-5
  PATH=${np%:} fx_in clis
  [ "$RC" = 0 ] || fail "a pack that lists Codex models was held for codex with no seat on it: $(cat "$T/$CASE/run.out")"
}
