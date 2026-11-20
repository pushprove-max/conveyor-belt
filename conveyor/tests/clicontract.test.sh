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
