#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what the core card rules tell every card session.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a card session was not told what its hooks refuse, so it spent calls on commands a hook then refused (an
# unbounded search, a shell write into a code file, an uncapped node --test) and on fetching the same facts from notes.
# The core rules name each refusal on one line, each with what to do instead.
t_hookrefusals() {
  local line
  line=$(grep -F "hooks refuse" "$SRC/rules/card-core.md")
  [ "$(grep -c . <<<"$line")" = 1 ] || fail "the core card rules have no single rule naming what the hooks refuse"
  # The search hook skips a grep with no recursive flag, so the rule names only the recursive one.
  grep -qF 'An `rg`, or a recursive `grep`, with no path, or over `.`, the checkout root' <<<"$line" \
    && grep -qF 'name the directories to search' <<<"$line" \
    || fail "the hooks rule does not name the unbounded search and its alternative: $line"
  grep -qF 'A shell write into a code file' <<<"$line" && grep -qF 'use the Edit tool' <<<"$line" \
    || fail "the hooks rule does not name the shell write and its alternative: $line"
  grep -qF '`node --test` without `--max-old-space-size=4096`' <<<"$line" \
    && grep -qF "pass that flag, or use the project's own test script" <<<"$line" \
    || fail "the hooks rule does not name the uncapped node --test and its alternative: $line"
}

# Bug: the test-speed rules lived in one project's own rules, so another project's cards wrote slow tests and their
# reviews let them through. The core rules, which every project's cards and reviews are given with no setup, hold a
# "Keep tests fast" section of three rules, each with its reason, and none holds a test file to a CPU budget, which no
# file has (#349); a card's rules hold it whether or not the project adds rules of its own (cardrules(), as the build,
# fix and review prompts are given them).
t_speedrules() {
  local f=$SRC/rules/card-core.md s r p
  s=$(sed -n '/^Keep tests fast:$/,/^$/p' "$f")
  [ "$(grep -c '^- ' <<<"$s")" = 3 ] && ! grep -qi 'budget' "$f" || fail "the core card rules have no Keep tests fast section of three rules, or name a CPU budget: $s"
  for r in 'No wrapper that only runs other tests again, and no second case of one behaviour' \
    'One fixture, render or build per file where the cases allow it' 'is split into one case per fixture' \
    'Use the project'"'"'s shared fast test helpers rather than the slow real thing, unless the test is about that thing' \
    'call the function rather than run the whole program when only the function is under test'; do
    grep -qF -- "$r" <<<"$s" || fail "the Keep tests fast section does not say: $r"
  done
  # Each rule gives its reason after the rule: a colon, or ", as", inside its one line.
  ! grep '^- ' <<<"$s" | grep -vE ': [a-z]|, as ' || fail "a Keep tests fast rule gives no reason: $s"
  setup "[]"
  # A project with rules of its own (the test pack's card-rules.md), then one with none.
  for p in own none; do
    [ $p = own ] || rm "$R/.conveyor/card-rules.md"
    r=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && cardrules '{"title": "t", "body": ""}' ) ) \
      || fail "the card rules could not be made: $r"
    [[ $r == *"$s"* ]] || fail "a card's rules, in a project with $p rules of its own, do not hold the Keep tests fast section: $r"
  done
}

# Bug: a session's big tool results, test logs and whole-file reads, held half its tool output and were read again
# on every later turn (issue #540). The core rules tell it to run tests through testbrief.sh and read its log by part,
# and to search before reading and read a file of over 400 lines by line range.
t_contextrules() {
  local s
  s=$(sed -n "/^Keep the session's context small/,/^\$/p" "$SRC/rules/card-core.md")
  grep -qF '`testbrief.sh -- <command>`' <<<"$s" && grep -qF 'read the log by line range or search it' <<<"$s" \
    || fail "the core card rules do not tell a session to run tests through testbrief.sh: $s"
  grep -qF 'Search before you read, and read a file of over 400 lines by line range' <<<"$s" \
    || fail "the core card rules do not tell a session to search first and read a big file by line range: $s"
  # Issue #543: long output of other commands is shortened, and the rules say where its middle is.
  grep -qF 'When the middle matters, read the saved file by line range or search it.' <<<"$s" \
    || fail "the core card rules do not tell a session to read a long output's saved file by part: $s"
  # Issue #153: a session made one tool call per similar action (the same edit in ten files, many lookups), and each
  # result stayed in every later turn; the rules tell it to batch them into one script and read its summary.
  grep -qF 'When a step is many similar actions (the same change across files, many checks or lookups), write one script that does them all and run it once, then read its summary, not each result.' <<<"$s" \
    || fail "the core card rules do not tell a session to batch many similar actions into one script: $s"
}

# Bug: the first rule forbade "error handling the issue does not ask for", so builders left out the handling the
# reviewer then asked for, and the builder was never told the review's angles, so most first reviews were a no-go. The
# core rules let the changed code have the handling it needs and ask one read of the staged change on the review's
# three angles. The bar for how likely an input is belongs to the project's review.proof setting, which the reviewer
# applies, so the core rules name none.
t_beforefinish() {
  local f=$SRC/rules/card-core.md line
  line=$(grep -F "The smallest change that fully solves the issue." "$f")
  [ "$(grep -c . <<<"$line")" = 1 ] || fail "the core card rules have no single smallest-change rule"
  grep -qF 'No feature, abstraction or option the issue does not ask for' <<<"$line" \
    || fail "the first rule no longer forbids unrequested features, abstractions and options: $line"
  ! grep -qiE 'no [^.;]*error handling' <<<"$line" && grep -qF 'error handling the changed code needs to be correct' <<<"$line" \
    || fail "the first rule still forbids the error handling the changed code needs: $line"
  line=$(grep -F "Before you finish, read your staged change once as the reviewer will" "$f")
  [ "$(grep -c . <<<"$line")" = 1 ] || fail "the core card rules have no single before-you-finish rule"
  grep -qF 'does each changed behaviour have a test that fails without it' <<<"$line" \
    && grep -qF 'does each new test say which bug it catches' <<<"$line" \
    || fail "the before-you-finish rule does not ask for a failing test per behaviour that names its bug: $line"
  # Bug: a test that only finds text in a source file passes when nothing uses that text, and the rule did not say so.
  grep -qF 'a test that only finds text in a source file does not test behaviour, unless no behaviour can be run, such as a stylesheet rule in a test with no layout; such a test says why in a one-line comment' <<<"$line" \
    || fail "the before-you-finish rule does not rule out source-text-only tests, with the stylesheet exception and its one-line reason: $line"
  grep -qF 'can a check you added be skipped or fooled by an input it trusts' <<<"$line" \
    || fail "the before-you-finish rule does not ask whether a check can be skipped or fooled: $line"
  grep -qF 'is any comment or doc left untrue' <<<"$line" \
    || fail "the before-you-finish rule does not ask for untrue comments or docs: $line"
  grep -qF 'Fix what you find; that is part of the issue.' <<<"$line" \
    || fail "the before-you-finish rule does not say to fix what it finds: $line"
  # The reply's [likely] tag is about what the session verified, not about inputs, so it is left out of this search.
  ! sed 's/\[likely\]//g' "$f" | grep -qiE 'likely|probab|plausib|realistic|\brare\b|review\.proof' \
    || fail "the core card rules name a bar for how likely an input is: $(sed 's/\[likely\]//g' "$f" | grep -iE 'likely|probab|plausib|realistic|\brare\b|review\.proof')"
}

# Bug: a card session waited on one command for longer than its saved context lasts (five minutes of silence), so the
# next turn paid for the whole context again; and a run still going was reported as passed. The header every session
# starts with gives the four-minute rule, the background form with an output file and an exit-status file, a wait that
# ends within four minutes and runs on Linux and macOS alike, and says a run that has not ended is never passed.
t_longwait() {
  local h w b c n s seg ok='sleep timeout date stat find sed grep flock'
  setup "[$(issue 7 2026-01-01)]"
  # The build changes nothing: the card ends after the session that read the header, with no review, tests or landing.
  echo : > "$STUB/build"
  loop run 1 >/dev/null || fail "run exited non-zero"
  [ -s "$STUB/brief" ] || fail "the build session was not given a brief"
  h=$(tr '\n' ' ' < "$STUB/brief")
  grep -qF 'Never wait on one command for more than 4 minutes.' <<<"$h" || fail "the header has no four-minute rule: $h"
  b='rm -f /tmp/<name>.rc; (timeout 600 <command> > /tmp/<name>.out 2>&1; echo $? > /tmp/<name>.rc) &'
  grep -qF "\`$b\`" <<<"$h" \
    || fail "the header does not show the background run with its output file and its exit-status file: $h"
  grep -qF 'a run with no exit-status file has not ended and is reported as unfinished, never as passed' <<<"$h" \
    || fail "the header does not say an unfinished run is never reported as passed: $h"
  w=$(grep -o '`i=0; while [^`]*`' <<<"$h" | tr -d '`')
  [ -n "$w" ] || fail "the header shows no wait: $h"
  # Each command of the wait is a bash builtin or keyword, or a tool the engine has on both systems (portable.sh, p_tools).
  while IFS= read -r seg; do
    read -r c _ <<<"$seg"
    case $c in ''|while|do|done) continue ;; esac
    [[ $c == *=* ]] || [ "$(type -t "$c")" = builtin ] || [ "$(type -t "$c")" = keyword ] || [[ " $ok " == *" $c "* ]] \
      || fail "the wait runs $c, which is not in the engine's portable command set: $w"
  done < <(sed -E 's/(;|&&|\|\||\bdo\b)/\n/g' <<<"$w")
  ! grep -q 'tail\|--pid' <<<"$w" || fail "the wait uses tail --pid, which macOS does not have: $w"
  # It ends within four minutes when the run does not end, and at once when it has.
  n=$(sed -n 's/.*-lt \([0-9]*\) \].*/\1/p' <<<"$w"); s=$(sed -n 's/.*sleep \([0-9]*\);.*/\1/p' <<<"$w")
  [ -n "$n" ] && [ -n "$s" ] && [ $((n * s)) -le 240 ] || fail "the wait does not end within four minutes: $w"
  echo 0 > "$T/$CASE.rc"
  timeout 5 bash -c "${w//\/tmp\/<name>/$T/$CASE}" || fail "the wait does not end at once when the exit-status file is there: $w"
  # A status file an earlier run left is not read as this run's: started as shown over an old 0, a run still going
  # leaves no exit-status file, and the wait does not end before it does.
  b=${b//<command>/sleep 6} # sleep: a stand-in run still going while the wait is checked; the test never waits for it
  # Half a second is enough: the wait looks at once and then sleeps $s seconds, at least one, before it looks again.
  [ "$s" -ge 1 ] || fail "the wait sleeps under a second between looks: $w"
  timeout 0.5 bash -c "${b//\/tmp\/<name>/$T/$CASE} ${w//\/tmp\/<name>/$T/$CASE}" && fail "the wait read an earlier run's status: $b $w"
  [ ! -e "$T/$CASE.rc" ] || fail "an earlier run's status file is still there while the run goes on: $b"
}

# Bug (#628): a build session ran whole area files and ran failing cases again on a second checkout of HEAD, with sleep
# loops waiting on them, until it hit its time limit; the Test step does both jobs, and no rule told the session so.
# The prompt a build session and a fix session are given holds the three lines that say what to run and what not to.
t_ownruns() {
  local f l
  setup "[$(issue 7 2026-01-01)]"
  echo 'cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; echo "fix$(wc -l < "$STUB/sessions")" >> a.txt' > "$STUB/build"
  printf '%s\n' '[P1] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.2"
  loop run --only 7 >/dev/null || fail "run exited non-zero"
  [ -s "$STUB/brief.1" ] && grep -qF '# Reviewer findings: fix these findings' "$STUB/brief.2" \
    || fail "no build brief, or the second session was no fix session: $(cat "$STUB/sessions" 2>&1)"
  for f in "$STUB/brief.1" "$STUB/brief.2"; do
    for l in '- Run only the cases the change adds or changes, by name: `bash conveyor/conveyor.test.sh <case>`. Also run the existing cases that cover the changed code. For a project with no case runner, run the test file the change touches.' \
      '- Do not run a whole area file, the whole suite, or many files to look for failures. The Test step selects and runs them.' \
      '- Do not run tests on a second checkout of HEAD or main to find out whether a failure was there before. The Test step does that run on main.'; do
      grep -qxF -- "$l" "$f" || fail "the ${f##*/} prompt does not hold the line: $l"
    done
  done
}

# The benchmark's Conveyor arm on the project's rules (bench/swe_arms.sh, swe_pack), on the SWE-bench fixture of
# swebench.test.sh (swe): the host arm conveyor-rules takes the seats Codex builds and Claude reviews, the project's
# judge (on, Codex, always accepting P3) stands, the project keeps other seats for issue 1 (cards), and the pack maps
# x.py, which the task's issue names, and nomatch/* to area rule files.
swerulesarm() {
  swe
  jq -c '.judgeOn = true | .judgeAlways = ["P3"] | .judge = {cli: "codex", model: "x"} | .cards = {"1": {builder: {model: "m", effort: "low"}, reviewer: {model: "x"}}}' \
    "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" \
    && jq '.seats = {model: {cli: "codex", model: "x"}, reviewer: {cli: "claude", model: "m"}} | .rules = "project" | .label = "Conveyor, project rules"' \
      "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-rules.json" \
    && mkdir -p "$R/rules" && echo AREA-RULE-X > "$R/rules/x.md" && echo AREA-RULE-OTHER > "$R/rules/other.md" \
    && tune '.areas = {"x.py": "rules/x.md", "nomatch/*": "rules/other.md"}' || fail "the arm, the control record or the area rules were not set"
}

# Bug: the benchmark's card did not get what the arm chose. Its sandbox kept the project's per-issue seats (cards), and
# every task is issue 1 there, so a project's cards["1"] changed the arm's builder and reviewer; and its pack held no
# project card rules or area rules, so an arm could not run a card on the rules the project's own cards get. The card
# in the container sees the engine version asked for, the arm's seats, the arm's review policy over the project's, no
# per-issue seats, and the rules cardrules() gives it there: the core rules, the project's card rules and the area rule
# its issue names. Bug: a saved arm could not turn the judge off or set the finding priorities, so the host's always
# stood, and its own judgeAlways list did not replace the host's ["P3"]. The arm is a saved one (the Board's form),
# Claude builds at high effort and Codex reviews, on the project's rules, with the judge off, P3 findings off and
# "style" the judge's one always-accepted kind; P2, which it leaves out, is the project's. Bug (#703): the arm was
# refused when an area rule file was missing that no card of the run reads; the pack also maps gone/* to a file that
# is not there, a path neither the preflight task nor the task run names, so the run goes on and its pack maps no
# area to that file. Bug (#702): with P3 off the task's issue, which has no priority label and so is P3, was kept off
# the queue and no card ran (the fake engine runs the real dry pick).
t_swerules() {
  swerulesarm; local out r id
  tune '.areas["gone/*"] = "rules/gone.md"' || fail "the absent area rule was not mapped"
  id=$(loop bench swe arms save 'Project rules' '{"kind":"conveyor","seats":{"model":{"cli":"claude","model":"m","effort":"high"},"reviewer":{"cli":"codex","model":"x"}},"rules":"project","policy":{"judgeOn":false,"judgeAlways":["style"],"P3":false}}' 2>&1) \
    || fail "the arm was not saved: $id"
  out=$(loop bench swe 1 --arm "$id" --engine v1.0.0 2>&1) || fail "the run failed: $out"
  [ -s "$SWE_FX/log" ] && ! grep -v '^A ' "$SWE_FX/log" || fail "the card did not run on the engine version asked for: $(cat "$SWE_FX/log")"
  jq -e '.model == {cli: "claude", model: "m", effort: "high"} and .reviewer == {cli: "codex", model: "x"} and .cards == {}
    and .judgeOn == false and .rules.P3 == false and .rules.P2 == true and .judgeAlways == ["style"] and .judge.cli == "codex" and .judge.model == "x"' "$SWE_FX/control.seen" > /dev/null \
    || fail "the card's control record does not hold the arm's seats and its review policy over the project's, or holds the project's cards: $(cat "$SWE_FX/control.seen")"
  r=$(cat "$SWE_FX/rules.seen")
  [[ $r == "$(cat "$SRC/rules/card-core.md")"* ]] && [[ $r == *PACK-CARD-RULE* ]] && [[ $r == *AREA-RULE-X* ]] && [[ $r != *AREA-RULE-OTHER* ]] \
    || fail "the card's rules are not the core rules, the project's card rules and the area rule of x.py alone: $r"
  jq -e '.areas | keys == ["x.py"]' "$SWE_FX/pack.seen" > /dev/null || fail "the card's pack maps an area its task does not name: $(jq -c .areas "$SWE_FX/pack.seen")"
  # With P3 off, the task's issue is labelled the least urgent priority whose rule is on, P2 (#1435: a P0 passed too).
  [ "$(jq -c .labels "$SWE_FX/issue.seen" 2>&1)" = '[{"name":"P2"}]' ] || fail "the task's issue is not labelled P2, the least urgent priority still on: $(cat "$SWE_FX/issue.seen")"
}

# The benchmark's fix and testFix seats (the repairs of review findings and of failed tests). Bugs: a saved arm took a
# review model for a repair seat, which runs the builder's sessions; the card in the container got the project's
# repair seats, not the arm's; a fix seat on Codex, with every other seat on Claude, had no Codex login there; and an
# earlier engine, whose control record knows no such seat (the fixture's v1.0.0), ran the arm, its card passing the
# seats over unread and repairing on the builder, with nobody told.
t_swefixseats() {
  swe; local out id
  tune '.models.allowed["codex-builder"] = ["xb"]' || fail "the Codex builder model was not allowed"
  out=$(loop bench swe arms save 'Review model fixes' '{"kind":"conveyor","seats":{"fix":{"cli":"codex","model":"x"}}}' 2>&1) \
    && fail "a review model was saved as the fix seat: $out"
  [[ $out == *'the project does not allow "x" on codex for the fix seat'* ]] || fail "the review model was not refused for the fix seat: $out"
  id=$(loop bench swe arms save 'Codex fixes' '{"kind":"conveyor","seats":{"model":{"cli":"claude","model":"m"},"reviewer":{"cli":"claude","model":"claude-sonnet-5-5"},"fix":{"cli":"codex","model":"xb","effort":"high"},"testFix":{"cli":"claude","model":"m","effort":"low"}},"policy":{"judgeOn":false}}' 2>&1) \
    || fail "the arm was not saved: $id"
  out=$(loop bench swe 1 --arm "$id" --engine v1.0.0 2>&1) && fail "an engine with no fix or testFix seat ran the arm: $out"
  [[ $out == *"the card's fix and testFix seat is set (by the arm or the project), and the engine version it runs on has no such seat"* ]] \
    || fail "the earlier engine's refusal does not say why: $out"
  [ ! -e "$SWE_FX/log" ] || fail "a card ran on the engine with no repair seats: $(cat "$SWE_FX/log")"
  out=$(loop bench swe 1 --arm "$id" 2>&1) || fail "the run on main's engine failed: $out"
  jq -e '.fix == {cli: "codex", model: "xb", effort: "high"} and .testFix == {cli: "claude", model: "m", effort: "low"}' "$SWE_FX/control.seen" > /dev/null \
    || fail "the card's control record does not hold the arm's repair seats: $(jq -c '{fix, testFix}' "$SWE_FX/control.seen")"
  [ "$(cat "$SWE_FX/codex.seen" 2>/dev/null)" = CODEX-LOGIN ] || fail "the container of an arm whose fix seat is on Codex had no Codex login"
}

# An arm whose policy turns off every level the task's issue can have would start a loop that never picks its card;
# it is refused, and says why.
t_swepolicyoff() {
  swe; local out
  jq '.policy = {P0: false, P1: false, P2: false, P3: false}' "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-off.json" || fail "the arm was not made"
  out=$(loop bench swe 1 --arm conveyor-off 2>&1) && fail "the run started with every priority off: $out"
  grep -qF "the arm's policy turns off every priority the task's issue can have, so its card would never be picked" <<<"$out" \
    || fail "the run was not refused for its policy: $out"
  [ ! -e "$SWE_FX/log" ] || fail "a card ran with every priority off: $(cat "$SWE_FX/log")"
}

# Bug: an arm that takes the project's rules ran with one of them missing, so its cards built on fewer rules than the
# arm says. The run is refused, and says which file is missing.
t_sweruleless() {
  swerulesarm; local out
  rm "$R/rules/x.md"
  out=$(loop bench swe 1 --arm conveyor-rules 2>&1) && fail "the run started with an area rule file missing: $out"
  grep -qF "the arm conveyor-rules cannot run: its preflight failed: the arm takes the project's rules, and the area rule file rules/x.md its pack maps to x.py is missing" <<<"$out" \
    || fail "the run was not refused for the missing area rule file: $out"
  [ ! -e "$SWE_FX/log" ] || fail "a card ran with the area rule file missing: $(cat "$SWE_FX/log")"
}
