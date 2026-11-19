#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: release-prep validates the mod (hooks/, types/, .claude-plugin/plugin.json) on the oldest Claude Code
# version plugin.json names (relminver(), commands/release-prep.sh). The fixture is release.test.sh's cutsetup.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug (issue 772): a release that changes the mod ships it to users on the oldest Claude Code plugin.json supports
# with no check on that version: only the build machine's own, newer, claude validated it. Here: a release whose
# commits change no mod file runs no such check and its record says why; one that changes hooks/ installs the minimum
# version apart (the stub npm) and validates the packaged commit with it, and its failure stops the release before the
# suite, with validate's output; the machine's own claude is never run for it nor changed.
t_relminver() {
  local O out own before
  cutsetup 'echo run >> "$STUB/runs"'
  # The machine's own claude, a newer version, logging every other call.
  printf '%s\n' '#!/usr/bin/env bash' '[ "$1" != --version ] || { echo "9.9.9 (Claude Code)"; exit 0; }' 'printf "%s\n" "$*" >> "$STUB/own-calls"' > "$STUB/claude" \
    && chmod +x "$STUB/claude" || fail "the fixture could not be made"
  # npm install --prefix <dir> @anthropic-ai/claude-code@<v>: a claude of version <v> in <dir>, whose validate logs the
  # version and whether the folder it checks holds hooks/a.ts, and fails with OLD-API-ERROR while $STUB/old-fail is there.
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$STUB/npm-calls"; p=; v=' \
    'while [ $# -gt 0 ]; do case $1 in --prefix) p=$2; shift ;; @anthropic-ai/claude-code@*) v=${1##*@} ;; esac; shift; done' \
    '[ -n "$p" ] && [ -n "$v" ] || exit 1; mkdir -p "$p/node_modules/.bin"' \
    'printf "%s\n" "#!/usr/bin/env bash" "[ \"\$1\" != --version ] || { echo \"$v (Claude Code)\"; exit 0; }" \' \
    '  "printf \"%s %s %s\\n\" $v \"\$*\" \"\$([ -f \"\$3/hooks/a.ts\" ] && echo packaged)\" >> \"\$STUB/old-calls\"" \' \
    '  "[ ! -e \"\$STUB/old-fail\" ] || { echo \"✘ Validation failed\"; echo \"  ❯ hooks/a.ts: OLD-API-ERROR\"; exit 1; }" "echo \"✔ Validation passed\"" > "$p/node_modules/.bin/claude"' \
    'chmod +x "$p/node_modules/.bin/claude"' > "$STUB/npm" && chmod +x "$STUB/npm" || fail "the fixture could not be made"
  own=$(command -v claude); before=$(claude --version; cksum < "$own")
  # The tagged release already names the minimum, so only the later hooks/ commit can make a change to the mod.
  git -C "$R" reset -q --hard v1.0.0 && jq '.engines = {"claude-code": ">=2.1.322"}' "$R/.claude-plugin/plugin.json" > "$T/$CASE/p.json" \
    && mv "$T/$CASE/p.json" "$R/.claude-plugin/plugin.json" && git -C "$R" commit -qam 'the first release' --amend \
    && git -C "$R" tag -fa v1.0.0 -m 'Release 1.0.0' > /dev/null && git -C "$R" cherry-pick "$O" > /dev/null \
    && git -C "$R" push -qf origin main v1.0.0 || fail "the fixture could not be made"

  # The commits since v1.0.0 add the notes alone: no check, and the record says why.
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed on a release that changes no mod file: $out"
  [ ! -e "$STUB/npm-calls" ] && [ ! -e "$STUB/old-calls" ] || fail "a release that changes no mod file installed or ran Claude Code: $(cat "$STUB/npm-calls" "$STUB/old-calls" 2>&1)"
  jq -e '.minver.state == "skipped" and .minver.version == null and (.minver.why | test("change no file of the mod"))' "$T/$CASE/cards/release/run.json" > /dev/null \
    || fail "the record does not say why the mod was not validated: $(cat "$T/$CASE/cards/release/run.json")"

  # A commit changes hooks/ alone: validate runs with 2.1.322 on the packaged commit, fails, and stops the release
  # before the suite, with its output.
  mkdir -p "$R/hooks" && echo 'export {}' > "$R/hooks/a.ts" && git -C "$R" add -A && git -C "$R" commit -qm 'feat: a hook' \
    && [ "$(git -C "$R" diff --name-only v1.0.0 HEAD | sort | tr '\n' ' ')" = "docs/releases/1.1.0.md hooks/a.ts " ] \
    && git -C "$R" push -q origin main && rm -f "$STUB/runs" "$STUB/gh-calls" && touch "$STUB/old-fail" \
    || fail "the fixture could not be made: $(git -C "$R" diff --name-only v1.0.0 HEAD)"
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a failed validate on the oldest version: $out"
  grep -q 'fails claude plugin validate on Claude Code 2.1.322' <<<"$out" && grep -q 'OLD-API-ERROR' <<<"$out" \
    || fail "the stop does not name the version and give validate's output: $out"
  grep -q '@anthropic-ai/claude-code@2.1.322' "$STUB/npm-calls" && grep -qx "2.1.322 plugin validate /.* packaged" "$STUB/old-calls" \
    || fail "validate did not run with 2.1.322 on the packaged commit: $(cat "$STUB/npm-calls" "$STUB/old-calls" 2>&1)"
  [ ! -e "$STUB/runs" ] && ! grep -q statuses "$STUB/gh-calls" 2>/dev/null || fail "the suite ran or a status was posted after validate failed"
  jq -e '.minver.state == "failed" and .minver.version == "2.1.322" and any(.reasons[]; test("OLD-API-ERROR"))' "$T/$CASE/cards/release/run.json" > /dev/null \
    || fail "the record does not keep the failed check and its output: $(cat "$T/$CASE/cards/release/run.json")"

  # Fixed: it passes, with the copy installed before (npm not run again), and the suite runs.
  rm -f "$STUB/old-fail"
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed once validate passed: $out"
  [ "$(wc -l < "$STUB/npm-calls")" = 1 ] && [ -e "$STUB/runs" ] && jq -e '.minver.state == "passed"' "$T/$CASE/cards/release/run.json" > /dev/null \
    || fail "the kept copy was not reused, or the suite did not run after validate passed: $out $(cat "$STUB/npm-calls")"

  # The machine's own claude: the same file and version, never asked to validate.
  [ "$(command -v claude)" = "$own" ] && [ "$(claude --version; cksum < "$own")" = "$before" ] && [ ! -e "$STUB/own-calls" ] \
    || fail "the machine's own claude changed or ran: $(claude --version) $(cat "$STUB/own-calls" 2>&1)"
}
