#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This pack's ESLint lint command (.conveyor/project.json, lint; .conveyor/lint-js.sh; eslint.config.js) run by the
# engine's own gate (lintrun and lintcheck, conveyor/lib/lint.sh) on a card's change in a fixture repository that
# holds this checkout's script, config and panels/landed.js. Bugs it catches: an undefined name a card adds to a panel
# file lands unread; a rule set to `warn` lets its finding through, or makes the run an execution error; a bare use of
# a Board global the files share (DASH_APP) is a finding; a file under .claude/dashboard/vendor/ is given to ESLint; a
# broken eslint.config.js reads as a pass; a gate run fixes a JavaScript file; with no ESLint installed, the command is
# an execution error in place of `skipped: missing eslint`. The cases that need ESLint are skipped when this
# checkout's node_modules lacks it (npm ci installs it); the case of a missing ESLint always runs.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d); trap 'git -C "$T/main" worktree prune 2>/dev/null; rm -rf "$T"' EXIT
n=0; bad=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); bad=1; echo "not ok $n - $1"; }
R=$T/main W=$T/cards/c7 P=.claude/dashboard/panels/landed.js V=.claude/dashboard/vendor/v.js
g() { git -C "$R" "$@"; }

# Main: the test pack with this pack's ESLint command and lint policy, the script and config, panels/landed.js (which
# has old complexity findings, so the gate makes a base run), and a vendor file.
mkdir -p "$R/.conveyor" "$R/.claude/dashboard/panels" "$R/.claude/dashboard/vendor" "$T/cards" && g init -q -b main \
  && g config user.email t@example.com && g config user.name t || exit 1
jq --slurpfile p "$ROOT/.conveyor/project.json" '.lint = ($p[0].lint | .commands |= map(select(.run // "" | test("lint-js"))))' \
  "$ROOT/conveyor/lib/test-pack.json" > "$R/.conveyor/project.json" || exit 1
[ "$(jq '.lint.commands | length' "$R/.conveyor/project.json")" = 1 ] || { echo "not ok - the pack has no one ESLint command"; exit 1; }
cp "$ROOT/.conveyor/lint-js.sh" "$R/.conveyor/" && cp "$ROOT/eslint.config.js" "$R/" && cp "$ROOT/$P" "$R/$P" || exit 1
echo node_modules > "$R/.gitignore" && echo 'export const v = 1;' > "$R/$V" || exit 1
g add -A && g commit -qm base && g worktree add -q --detach "$W" || exit 1
base=$(g rev-parse HEAD)

# engine <commands>: <commands> in a shell of the engine as conveyor.sh lint loads it, main being $R; output in
# $T/out.
engine() {
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/cards
    . "$ROOT/conveyor/conveyor.sh" state-dir > /dev/null && . "$ROOT/conveyor/lib/slots.sh" && . "$ROOT/conveyor/lib/prompts.sh" \
      && . "$ROOT/conveyor/lib/push.sh" && . "$ROOT/conveyor/lib/lint.sh" || exit 9
    eval "$1" ) > "$T/out" 2>&1
}
# gate: the gate's run on the card's change; its exit, then its lines, in $T/out; `rep` its reported findings
# (`<file>:<line> <code>`), `found` every finding the command printed.
gate() {
  # shellcheck disable=SC2016 # expanded by the engine's shell
  engine 'lintrun "$W" '"$base"' c7 "$T/run"; echo "exit $?"; cat "$T/run"'
  rep=$(sed 1d "$T/out" | jq -r '.reported[] | "\(.file):\(.line) \(.code)"' 2>/dev/null | paste -sd' ' -)
  found=$(sed 1d "$T/out" | jq -r '.findings[] | "\(.file):\(.line) \(.code)"' 2>/dev/null | paste -sd' ' -)
}

# The card's change: at the end of landed.js, an undefined name, a bare use of DASH_APP, and a double negation that
# ESLint's --fix would rewrite; an undefined name in the vendor file.
cp "$R/$P" "$W/$P" && printf 'notDefinedAnywhere();\nDASH_APP.panel;\nif (!!window.DASH) window.DASH_ALIVE = 1;\n' >> "$W/$P" \
  && echo 'vendorUndefined();' > "$W/$V" && git -C "$W" add -A || exit 1
L=$(($(wc -l < "$R/$P") + 1))

if [ -x "$ROOT/node_modules/.bin/eslint" ]; then
  ln -s "$ROOT/node_modules" "$W/node_modules" || exit 1
  sums() { (cd "$W" && git ls-files -z '*.js' | xargs -0 cksum); }
  before=$(sums)
  gate
  head -1 "$T/out" | grep -qx 'exit 1' || no "the gate did not end in findings: $(cat "$T/out")"
  [[ " $rep " == *" $P:$L no-undef "* ]] && ok "an undefined name added to a panel file is a finding at the gate" \
    || no "no no-undef at $P:$L: $rep"
  [[ " $found " != *" $P:$((L + 1)) "* ]] && ok "a use of a shared Board global is no finding" || no "DASH_APP is a finding: $found"
  # A command that changes a file makes lintrun put it back and exit 2, so the files alone cannot show it: the exit 1
  # does.
  [ "$(sums)" = "$before" ] && head -1 "$T/out" | grep -qx 'exit 1' && ok "a gate run leaves every JavaScript file unchanged" \
    || no "a JavaScript file changed: $(cat "$T/out")"

  # The config sets no-undef to warn and turns off the rules of landed.js's other findings, so ESLint reports only
  # warnings: without --max-warnings 0 it would exit 0 with a finding line, an execution error. A changed trigger
  # gives the command every file its pathspecs match.
  printf "module.exports.push({ rules: { 'no-undef': 'warn', 'no-extra-boolean-cast': 'off', complexity: 'off', 'max-lines-per-function': 'off' } });\n" \
    >> "$W/eslint.config.js" && git -C "$W" add -A || exit 1
  gate
  [[ " $rep " == *" $P:$L no-undef "* ]] && head -1 "$T/out" | grep -qx 'exit 1' && ok "a rule set to warn gives a finding" \
    || no "a warn rule: $(cat "$T/out")"
  [ "$(sed 1d "$T/out" | jq -r .files 2>/dev/null)" = 1 ] && [[ " $found " != *" $V:"* ]] \
    && ok "a file under .claude/dashboard/vendor/ is not passed to ESLint" || no "the vendor file: $(cat "$T/out")"

  echo 'module.exports = [' > "$W/eslint.config.js" && git -C "$W" add -A || exit 1
  # shellcheck disable=SC2016 # expanded by the engine's shell
  engine 'lintcheck "$W" '"$base"
  [ "$(jq -r .result "$T/out" 2>/dev/null)" = error ] && ok "a broken eslint.config.js gives an execution error" \
    || no "broken eslint.config.js: $(cat "$T/out")"
  cp "$R/eslint.config.js" "$W/" && rm "$W/node_modules" && git -C "$W" add -A || exit 1
else
  for c in "an undefined name is a finding" "a shared Board global is no finding" "a gate run leaves the JavaScript files unchanged" \
    "a rule set to warn gives a finding" "a vendor file is not passed to ESLint" "a broken eslint.config.js is an execution error"; do
    n=$((n + 1)); echo "ok $n - # SKIP $c: node_modules has no ESLint"
  done
fi

# No ESLint: the worktree has no node_modules. The gate's run, then the lint line it records (lintline; record prints
# the line's fields here).
# shellcheck disable=SC2016 # expanded by the engine's shell
engine 'lintrun "$W" '"$base"' c7 "$T/run"; r=$?; echo "exit $r"; record() { jq -r ".lint.commands[0].result" <<<"$5"; }
  lintline c7 1 "$T/run" $r review'
[ "$(cat "$T/out")" = "$(printf 'exit 0\nskipped: missing eslint')" ] && ok "with ESLint absent, the command gives skipped: missing eslint" \
  || no "no ESLint: $(cat "$T/out")"

echo "1..$n"; exit $bad
