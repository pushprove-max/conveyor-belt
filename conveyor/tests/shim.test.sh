#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: commands run through shim.sh, from an install or a marketplace plugin copy (its fixture, service_start
# and coderepo: install.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a command run through shim.sh from an install takes the install's version folder, read-only and with no .git,
# as the project: git prints `fatal:` and its state folder is made inside the install, so `control` fails; or the shim
# drops the main checkout its caller names.
t_shimmain() {
  setup '[]'; local c=0123456789abcdef0123456789abcdef01234567 v o=$T/$CASE/other out
  v=$T/$CASE/data/conveyor/versions/$c; trap 'chmod -R u+w "$T/$CASE"' EXIT
  mkdir -p "$v" && cp -a "$SRC" "$v/conveyor" && cp "$SRC/../shim.sh" "$v/" && chmod -R a-w "$v" && cp -a "$R" "$o" \
    || fail "the fixture install could not be made"
  tune --arg c "$c" '.plugin.commit = $c'
  shim() { (cd "$R" && exec env -u CLAUDE_PROJECT_DIR -u CONVEYOR_CARDS -u CONVEYOR_MAIN XDG_DATA_HOME="$T/$CASE/data" "$@" bash "$v/shim.sh" conveyor/conveyor.sh control hold 1 2>&1); }
  # sd <checkout>: its state folder, as the engine finds it; held <checkout>: the issues its control record holds.
  sd() { CONVEYOR_MAIN=$1 bash "$SRC/conveyor.sh" state-dir; }
  held() { jq -c .held "$(sd "$1")/control.json"; }
  [ "$(sd "$R")" != "$(sd "$o")" ] || fail "the two checkouts share a state folder: $(sd "$R")"
  out=$(shim) && [ "$(held "$R")" = '[1]' ] || fail "the hold through the shim did not reach the project's state folder: $out"
  ! grep -q 'fatal:' <<<"$out" || fail "the shim's command ran git in the version folder: $out"
  out=$(shim CONVEYOR_MAIN="$o") && [ "$(held "$o")" = '[1]' ] \
    || fail "the shim did not keep the caller's CONVEYOR_MAIN: $out"
}

# Bugs: from a marketplace install, the engine runs from a folder in no git checkout (Claude Code's plugin copy, which
# setup runs) or from a version folder; the main checkout was looked up there for every command but a few, so git
# printed `fatal: not a git repository` and the empty answer became the folder `/` (`mkdir: cannot create directory
# '//conveyor'`): retry queued no card. Every command run from the plugin copy also printed it, reading the commit it
# runs. The fixture: the project's main checkout, a verified install of the commit it pins, and the plugin copy, with
# shim.sh at its top and no .git, apart from both.
t_shimmarket() {
  service_start; tune --arg c "$A" '.plugin.commit = $c'
  local p=$T/$CASE/plugins/cache/m/conveyor-belt/1.1.1 n=$T/$CASE/nogit x i=6 err=$T/$CASE/err out
  mkdir -p "$p" "$n" && cp -a "$SRC" "$p/conveyor" && ln -s "$SRC/../.claude" "$p/.claude" && cp "$SRC/../shim.sh" "$p/" \
    && ! git -C "$p" rev-parse --git-dir >/dev/null 2>&1 && ! git -C "$n" rev-parse --git-dir >/dev/null 2>&1 \
    || fail "the plugin copy, in no git checkout, could not be made"
  for x in 7 8 9; do
    jq -cn --argjson i "$x" '{card: "c\($i)", issue: $i, step: "blocked", time: "2026-03-01T00:02:00Z", tokens: {claude: 0, codex: 0}, result: "blocked", sha: "", reason: "build: failed"}' >> "$ST/cards.jsonl"
  done
  # run <folder> <conveyor.sh, or shim.sh and its path> <arg>...: the command as a user runs it there, its stderr in $err.
  run() { (cd "$1" && exec env -u CLAUDE_PROJECT_DIR -u CONVEYOR_CARDS -u CONVEYOR_MAIN HOME="$T/$CASE/home" bash "${@:2}" 2>"$err"); }
  # The plugin's shim, the plugin copy's conveyor.sh (as /conveyor-belt:setup runs it) and the install's (docs/setup.md).
  for x in "$p/shim.sh conveyor/conveyor.sh" "$p/conveyor/conveyor.sh" "$V/$A/conveyor/conveyor.sh"; do
    i=$((i + 1))
    # shellcheck disable=SC2086 # the shim and its path are two words
    out=$(run "$R" $x retry "$i") && jq -se --argjson i "$i" 'any(.issue == $i)' "$ST/retried.jsonl" >/dev/null \
      || fail "retry $i through $x did not queue the card: $out $(cat "$err")"
    ! grep -q 'not a git repository' "$err" || fail "retry through $x ran git outside the project's checkout: $(cat "$err")"
  done
  # Each command the plugin's setup runs from the plugin copy; their outcomes here (no virtualenv, no answers) are not
  # what is tested, only that none reads git outside a checkout.
  for x in setup doctor install-service board; do
    run "$R" "$p/conveyor/conveyor.sh" "$x" >/dev/null
    ! grep -q 'not a git repository' "$err" || fail "$x from the plugin copy ran git outside the project's checkout: $(cat "$err")"
  done
  # The plugin copy has no commit to pin and no origin to clone: each says so, naming its folder, with no git error.
  tune 'del(.plugin)'; x=$(cd "$p/conveyor" && pwd -P) # the engine's folder as it names itself, its links followed
  # The machine's routes are set already (setup asks them while none is), so setup goes on to the pin.
  local h=$XDG_CONFIG_HOME/conveyor/host.json; mkdir -p "${h%/*}" && { [ -s "$h" ] || echo '{}' > "$h"; } \
    && jq '. + {claudeProxy: {kind: "subscription"}, codexProxy: {kind: "subscription"}}' "$h" > "$h.new" && mv "$h.new" "$h" || fail "the host file"
  run "$R" "$p/conveyor/conveyor.sh" setup --fast-lane no --research-lane no --survey no --pin >/dev/null && fail "setup --pin from the plugin copy did not fail"
  [ "$(cat "$err")" = "conveyor: the pin could not be written: $x is in no git checkout, so its commit cannot be read" ] \
    || fail "setup --pin from the plugin copy did not say why it wrote no pin: $(cat "$err")"
  run "$R" "$p/conveyor/conveyor.sh" install "$B" >/dev/null && fail "install from the plugin copy did not fail"
  [ "$(cat "$err")" = "conveyor: $x is in no git checkout with an origin to clone" ] \
    || fail "install from the plugin copy did not say why it cloned nothing: $(cat "$err")"
  tune --arg c "$A" '.plugin.commit = $c'
  # Called in a folder in no git checkout, the lookup has no answer: the command stops at once and names that folder.
  run "$n" "$V/$A/conveyor/conveyor.sh" retry 7 >/dev/null && fail "retry in a folder in no git checkout did not fail"
  [ "$(cat "$err")" = "conveyor: the project's main checkout cannot be found: $(cd "$n" && pwd) is in no git checkout; run conveyor.sh in the project's checkout, or name it in CONVEYOR_MAIN" ] \
    || fail "the empty lookup did not stop with its message alone: $(cat "$err")"
}
