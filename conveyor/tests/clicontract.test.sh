#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the contract between the engine and each CLI's shared stub (tests/stubs/): the engine's own reading code
# (askmodel(), a build session's session1(), openissues()) run against the stub gets the answer the case set. A change to how the engine calls or reads a CLI, or to
# what the stub answers, fails here, in the card that makes it, not in the many files whose stubs fell out of step.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# askmodel() called alone in the engine shell, as `conveyor.sh run` makes it; prints its answer, else why not.
ctask() { # <the model's seat setup, a command>
  setup "[$(issue 7 2026-01-01)]"; export CODEX_HOME=$T/$CASE/codex-home; mkdir -p "$CODEX_HOME"; mkdir -p "$T/$CASE/cards"
  eval "$1"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names \
    && d=$(mktemp -d) && askmodel "$d" 60 low "" question && cat "$d/answer" ) > "$T/$CASE/out" 2>&1
}

# A command run in the engine shell, as `conveyor.sh run` makes it; prints what it prints.
cread() { # <command>
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$T/$CASE/cards"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && eval "$1" ) > "$T/$CASE/out" 2>&1
}

# Bug: askmodel() reads a Claude seat's answer from the JSON `result`; a claude stub that answers plain text to
# --output-format json (as the stubs did before #800) left every same-file check failing far from the change.
t_contractclaude() {
  ctask 'echo "{\"ok\":1}" > "$STUB/claude-answer"' || fail "askmodel failed: $(cat "$T/$CASE/out")"
  [ "$(cat "$T/$CASE/out")" = '{"ok":1}' ] || fail "askmodel did not give the claude stub's answer: $(cat "$T/$CASE/out")"
}
# Bug: askmodel() reads a Codex seat's answer from the file its -o flag names; a codex stub that writes it elsewhere fails
# every call on a Codex seat.
t_contractcodex() {
  ctask 'echo "{\"ok\":1}" > "$STUB/codex-answer"; tune ".models.allowed[\"codex-builder\"] = [\"cx-1\"]"; seatset model cx-1' \
    || fail "askmodel failed: $(cat "$T/$CASE/out")"
  [ "$(cat "$T/$CASE/out")" = '{"ok":1}' ] || fail "askmodel did not give the codex stub's answer: $(cat "$T/$CASE/out")"
}
# Bug: askmodel() reads an OpenCode seat's answer from the text of the last step of `opencode run --format json`; a stub
# that cannot answer a run (the shared one exited 1) leaves every OpenCode seat case failing.
t_contractopencode() {
  ctask 'echo "{\"ok\":1}" > "$STUB/opencode-answer"; tune ".models.allowed.opencode = [\"opencode:p/m\"]"; seatset model opencode:p/m' \
    || fail "askmodel failed: $(cat "$T/$CASE/out")"
  [ "$(cat "$T/$CASE/out")" = '{"ok":1}' ] || fail "askmodel did not give the opencode stub's answer: $(cat "$T/$CASE/out")"
}
# A build session run alone (session1(): the seat's ready check, builder()'s call of the CLI and the usage reader the
# seat's CLI takes) on a fresh worktree of the case's main; prints the step's usage, else why not.
csession() { # <the builder seat's setup>
  setup "[$(issue 7 2026-01-01)]"; export CODEX_HOME=$T/$CASE/codex-home; mkdir -p "$CODEX_HOME" "$T/$CASE/cards"
  eval "$1"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names \
    && w=$CONVEYOR_CARDS/c7 && git -C "$R" worktree add -q --detach "$w" && echo '{}' > "$w.settings" \
    && session1 "$w" brief build | jq -c '.usage' ) > "$T/$CASE/out" 2>&1
}
# Bug: a Claude build session's usage is read from the stream builder() asks for (--output-format stream-json,
# SESSIONREAD); a builder that asks for another form, or a stub that answers in another, leaves a card's usage unread.
t_contractusageclaude() {
  csession : || fail "the session failed: $(cat "$T/$CASE/out")"
  [ "$(jq -c '{input, write, read, output}' "$T/$CASE/out" 2>&1)" = '{"input":10,"write":20,"read":999,"output":5}' ] \
    || fail "the session's usage is not the claude stub's: $(cat "$T/$CASE/out")"
}
# Bug: a Codex build session starts only past cxready() (`codex exec --help`) and its usage is read from the events
# `codex exec --json` prints (CODEXREAD); a stub or a builder out of step with either leaves a Codex card unbuilt or unread.
t_contractusagecodex() {
  csession 'tune ".models.allowed[\"codex-builder\"] = [\"cx-1\"]"; seatset model cx-1' \
    || fail "the session failed: $(cat "$T/$CASE/out")"
  [ "$(jq -c '{input, read, output}' "$T/$CASE/out" 2>&1)" = '{"input":40,"read":60,"output":7}' ] \
    || fail "the session's usage is not the codex stub's: $(cat "$T/$CASE/out")"
}
# Bug: a Codex review's usage is read from the events `codex exec --json` prints (REVIEWREAD), its verdict from the -o
# file; a codexreview() that drops --json gets the verdict but no usage, and the review fails as one that reported none.
t_contractusagecodexreview() {
  cread 'echo GO > "$STUB/review.1" && w=$CONVEYOR_CARDS/c7 && git -C "$R" worktree add -q --detach "$w" \
    && REVIEW_TIMEOUT=60 codexreview "$w" brief instructions cx-1 low | jq -c ".usage"' \
    || fail "the review failed: $(cat "$T/$CASE/out")"
  [ "$(jq -c '{input, read, output}' "$T/$CASE/out" 2>&1)" = '{"input":40,"read":60,"output":7}' ] \
    || fail "the review's usage is not the codex stub's: $(cat "$T/$CASE/out")"
}
# A Codex review run alone, as t_contractusagecodexreview runs one, with the stub's arguments kept in $STUB/codex-args.
# The worktree holds the build's change, built.txt, staged as a review is given it; the stub's review writes wrote.txt
# and stages new.txt; the worktree's files and its staged files are printed after.
cxreview() { # [NAME=value: the review's environment]
  cread 'sed -i "2a printf \"%s\\\\n\" \"\$*\" >> \"\$STUB/codex-args\"" "$STUB/codex" && echo GO > "$STUB/review.1" && echo "echo x > wrote.txt; echo y > new.txt; git add new.txt" > "$STUB/review-cmd" && w=$CONVEYOR_CARDS/c7 && git -C "$R" worktree add -q --detach "$w" \
    && echo built > "$w/built.txt" && git -C "$w" add built.txt && '"$*"' REVIEW_TIMEOUT=60 codexreview "$w" brief instructions cx-1 low > /dev/null && cat "$STUB/codex-args" && ls "$w" && git -C "$w" diff --cached --name-only | sed "s/^/staged: /"'
}
# Bug: in a benchmark's task container Codex's own sandbox cannot start a command, so a review run with -s read-only
# there read nothing and blocked the card; one run with none must not leave a write of its own in the worktree.
# Bug (R110): a new file the review staged was left in the index, as git restore and clean put back only the files,
# so the card's change took in a file its build never made; the put back must keep the build's staged built.txt, not
# go back to the last commit.
t_cxreviewbox() {
  cxreview CONVEYOR_BENCH_BOX=1 || fail "the review failed: $(cat "$T/$CASE/out")"
  grep -q -- '^exec --json --dangerously-bypass-approvals-and-sandbox ' "$T/$CASE/out" && ! grep -q -- ' -s ' "$T/$CASE/out" \
    || fail "the review in a benchmark's container kept Codex's sandbox: $(cat "$T/$CASE/out")"
  ! grep -q '^wrote.txt$' "$T/$CASE/out" || fail "the unsandboxed review's write was left in the worktree: $(cat "$T/$CASE/out")"
  ! grep -q 'new.txt$' "$T/$CASE/out" || fail "the file the unsandboxed review staged was left in the index or the worktree: $(cat "$T/$CASE/out")"
  grep -qx 'built.txt' "$T/$CASE/out" && grep -qx 'staged: built.txt' "$T/$CASE/out" \
    || fail "the build's staged built.txt was lost when the worktree was put back after the unsandboxed review: $(cat "$T/$CASE/out")"
}
# Bug: a Codex build in a benchmark's task container (the arm whose builder is Codex) ran in Codex's own sandbox
# (-s workspace-write), which cannot start a command there, so it could change no file.
t_cxbuildbox() {
  csession 'tune ".models.allowed[\"codex-builder\"] = [\"cx-1\"]"; seatset model cx-1; export CONVEYOR_BENCH_BOX=1
    sed -i "2a printf \"%s\\\\n\" \"\$*\" >> \"\$STUB/codex-args\"" "$STUB/codex"' || fail "the session failed: $(cat "$T/$CASE/out")"
  grep -q -- '^exec --json --dangerously-bypass-approvals-and-sandbox -C ' "$STUB/codex-args" && ! grep -q -- ' -s ' "$STUB/codex-args" \
    || fail "the build in a benchmark's container kept Codex's sandbox: $(cat "$STUB/codex-args" 2>&1)"
}
# Bug: a Codex judge in a benchmark's task container kept Codex's own sandbox, or left a write of its own in the worktree;
# a new file it staged was left in the index (R110, as the review's in t_cxreviewbox), or the build's staged built.txt
# was lost when it was put back.
t_cxjudgebox() {
  cread 'sed -i "2a printf \"%s\\\\n\" \"\$*\" >> \"\$STUB/codex-args\"" "$STUB/codex" && echo "F1 DECLINE: no" > "$STUB/review.1" \
    && echo "echo x > wrote.txt; echo y > new.txt; git add new.txt" > "$STUB/review-cmd" && w=$CONVEYOR_CARDS/c7 && git -C "$R" worktree add -q --detach "$w" \
    && echo built > "$w/built.txt" && git -C "$w" add built.txt && CALLSEAT="{\"agent\":\"codex\",\"model\":\"x\",\"effort\":\"low\"}" CONVEYOR_BENCH_BOX=1 REVIEW_TIMEOUT=60 judgecall "$w" instructions findings > /dev/null \
    && cat "$STUB/codex-args" && ls "$w" && git -C "$w" diff --cached --name-only | sed "s/^/staged: /" && jq -c "{judgelive: {model, effort}}" "$w.live"' || fail "the judge failed: $(cat "$T/$CASE/out")"
  grep -q -- '^exec --json --dangerously-bypass-approvals-and-sandbox ' "$T/$CASE/out" && ! grep -q -- ' -s ' "$T/$CASE/out" \
    || fail "the judge in a benchmark's container kept Codex's sandbox: $(cat "$T/$CASE/out")"
  # Issue 1085: the judge's live record names the effort it runs at, which the Board shows beside its model.
  grep -qx '{"judgelive":{"model":"x","effort":"low"}}' "$T/$CASE/out" || fail "the judge's live record lost its effort: $(cat "$T/$CASE/out")"
  ! grep -q '^wrote.txt$' "$T/$CASE/out" || fail "the unsandboxed judge's write was left in the worktree: $(cat "$T/$CASE/out")"
  ! grep -q 'new.txt$' "$T/$CASE/out" || fail "the file the unsandboxed judge staged was left in the index or the worktree: $(cat "$T/$CASE/out")"
  grep -qx 'built.txt' "$T/$CASE/out" && grep -qx 'staged: built.txt' "$T/$CASE/out" \
    || fail "the build's staged built.txt was lost when the worktree was put back after the unsandboxed judge: $(cat "$T/$CASE/out")"
}
# Bug: a review outside a benchmark's container ran without Codex's read-only sandbox.
t_cxreviewsandbox() {
  cxreview || fail "the review failed: $(cat "$T/$CASE/out")"
  grep -q -- '^exec --json -s read-only ' "$T/$CASE/out" && ! grep -q -- 'dangerously-bypass-approvals' "$T/$CASE/out" \
    || fail "the review lost Codex's read-only sandbox: $(cat "$T/$CASE/out")"
}
# Bug: an OpenCode build session starts only past ocready() (`opencode --version` is 1.x) and its usage is read from
# the events `opencode run --format json` prints (OPENCODEREAD); out of step, an OpenCode card is unbuilt or unread.
t_contractusageopencode() {
  csession 'echo ok > "$STUB/opencode-answer"; tune ".models.allowed.opencode = [\"opencode:p/m\"]"; seatset model opencode:p/m' \
    || fail "the session failed: $(cat "$T/$CASE/out")"
  [ "$(jq -c '{input, write, read, output}' "$T/$CASE/out" 2>&1)" = '{"input":100,"write":50,"read":1000,"output":20}' ] \
    || fail "the session's usage is not the opencode stub's: $(cat "$T/$CASE/out")"
}
# Bug: openissues() reads the open issues from `gh issue list --json`; a gh stub that answers in another form leaves
# the pick with no issues.
t_contractgh() {
  cread 'openissues number,title | jq -c "map(.number)"' || fail "openissues failed: $(cat "$T/$CASE/out")"
  [ "$(cat "$T/$CASE/out")" = '[7]' ] || fail "openissues did not read the gh stub's issues: $(cat "$T/$CASE/out")"
}
# The shared claude stub alone in a folder of its own ($T/$CASE), with the build $1; nothing else of a case is needed.
stubonly() { # <the build>
  mkdir -p "$T/$CASE" && cp "$SRC/tests/stubs/claude" "$T/$CASE/claude" && printf '%s\n' "$1" > "$T/$CASE/build" # stub: the shared stub itself, run alone
}
# Bug: the stub answered --output-format json and stream-json alike, so a session that asked for the wrong one was
# still read here, and failed only on a real Claude Code: json with --verbose (as a session asks) prints every event
# in one array, which the stream reader (SESSIONREAD) cannot read, and stream-json with no --verbose is refused.
t_contractformats() {
  local d=$T/$CASE j s
  stubonly : || fail "the fixture could not be made"
  j=$(cd "$d" && STUB=$d ./claude -p --output-format json --verbose <<<brief | jq -cRn --arg m m --arg e "" --argjson s 0 -f "$SRC/jq/sessionread.jq")
  [ "$(jq -r '.unread // "read"' <<<"$j")" = 'the session output holds no event' ] \
    || fail "claude -p --output-format json --verbose, read as a session's stream, was read: $j"
  (cd "$d" && STUB=$d ./claude -p --output-format stream-json <<<brief > "$d/s.out" 2>&1); s=$?
  [ "$s" = 1 ] && grep -q 'requires --verbose' "$d/s.out" \
    || fail "claude -p --output-format stream-json with no --verbose did not fail (exit $s): $(cat "$d/s.out")"
  [ "$(cd "$d" && STUB=$d ./claude -p --tools "" --output-format json <<<q | jq -r .result)" = OK ] \
    || fail "claude -p --tools '' --output-format json did not give one result object"
}
# Bug: with a claude-usage stream (as t_metrics sets one), the stub printed the stream raw for every --output-format,
# so a session that asked for json --verbose was still read by the stream reader (SESSIONREAD).
t_contractusage() {
  local d=$T/$CASE j
  stubonly : || fail "the fixture could not be made"
  printf '%s\n' '{"type":"system","subtype":"init"}' '{"type":"result","is_error":false,"usage":{"input_tokens":10,"output_tokens":5}}' > "$d/claude-usage"
  local out
  out=$(cd "$d" && STUB=$d ./claude -p --output-format json --verbose <<<brief)
  # The array must hold every fixture event: an empty or cut array would also be unread as a stream.
  [ "$(jq -c 'map([.type, .usage.output_tokens])' <<<"$out")" = '[["system",null],["result",5]]' ] \
    || fail "claude -p --output-format json --verbose with claude-usage did not give every event in one array: $out"
  j=$(jq -cRn --arg m m --arg e "" --argjson s 0 -f "$SRC/jq/sessionread.jq" <<<"$out")
  [ "$(jq -r '.unread // "read"' <<<"$j")" = 'the session output holds no event' ] \
    || fail "claude -p --output-format json --verbose with claude-usage, read as a session's stream, was read: $j"
  j=$(cd "$d" && STUB=$d ./claude -p --output-format json <<<brief | jq -c '[.type, .usage.output_tokens]')
  [ "$j" = '["result",5]' ] || fail "claude -p --output-format json with claude-usage did not give its result object alone: $j"
  j=$(cd "$d" && STUB=$d ./claude -p --output-format stream-json --verbose <<<brief | jq -cRn --arg m m --arg e "" --argjson s 0 -f "$SRC/jq/sessionread.jq")
  [ "$(jq -r '.unread // "read"' <<<"$j")" = read ] || fail "claude -p --output-format stream-json --verbose with claude-usage was not read: $j"
}
# Bug: each session wrote its prompt to the one $STUB/brief and its build read it from there, so a build run beside
# another session (two cards at once) could read the other card's prompt. Each build waits until both sessions have
# written theirs, so the later write has always happened before either reads: a poll of the other stub, as only two
# stubs run at once can show the shared file.
t_stubbrief() {
  local d=$T/$CASE i
  stubonly 'i=0; while [ "$(wc -l < "$STUB/sessions")" -lt 2 ] && [ $i -lt 400 ]; do i=$((i + 1)); sleep 0.05; done
cp "$STUB/brief" "$STUB/read.$ME"' || fail "the fixture could not be made"
  for i in 1 2; do (cd "$d" && STUB=$d ME=$i ./claude -p --output-format stream-json --verbose <<<"prompt $i" > /dev/null) & done; wait
  [ "$(cat "$d/read.1" 2>&1)" = 'prompt 1' ] && [ "$(cat "$d/read.2" 2>&1)" = 'prompt 2' ] \
    || fail "two sessions at once did not each read their own prompt: 1 read '$(cat "$d/read.1" 2>&1)', 2 read '$(cat "$d/read.2" 2>&1)'"
}
