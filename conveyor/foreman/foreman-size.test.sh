#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's start (foreman.sh claim, its context) stays under Claude Code's 10,000-character limit on a hook's
# output; when its files do not fit, it tells the Foreman to Read them.
# Bug it catches: a start of 23 KB (a big rules.md and state.md) went over the limit, so Claude Code kept it out of the
# context and gave the session a 2 KB preview: no rules, no standing kinds, no saved state, and the role looked not started.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CONVEYOR_MACHINE_ID
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
fail() { echo "FAIL [size-$CASE]: $*" >&2; exit 1; }
# fixture <case>: a Foreman's checkout of alpha with the test pack.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$FD" "$M/.conveyor" && git init -q "$M" \
    && jq '.plugin = {follow: "main"}' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json" \
    && git -C "$M" remote add origin https://example.com/acme/alpha.git \
    && jq -n --arg h "$M" '{records: [{repo: "alpha", main: $h}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
# text <marker> <lines>: <lines> lines of 60 characters, each starting with <marker>.
text() { local i; for ((i = 1; i <= $2; i++)); do printf '%s line %04d %s\n' "$1" "$i" "$(printf 'x%.0s' {1..40})"; done; }
start() { (cd "$M" && bash "$SRC/foreman.sh" claim sA) || fail "the claim failed"; }

# Both files over the limit together: the start is under 10,000 characters, and a line names each file left out with
# its path; the fixed text is still whole.
t_big() {
  local out f
  fixture big
  text RULESBODY 120 > "$FD/rules.md"; text STATEBODY 100 > "$FD/state.md"
  out=$(start)
  [ "${#out}" -lt 10000 ] || fail "the start is ${#out} characters, not under 10000"
  grep -qF '# Foreman mode: you are' <<<"$out" && grep -qF 'Live summary' <<<"$out" || fail "the fixed text or the live summary was cut: ${out:0:300}"
  for f in rules.md state.md; do
    grep -E "Read $FD/$f now" <<<"$out" | grep -qF "$FD/$f did not fit" || fail "no Read line names $FD/$f in the start"
  done
  ! grep -qE 'RULESBODY|STATEBODY' <<<"$out" || fail "a file's text stayed in a start that is over the limit"
  # Bug: the Read line for an oversized state.md replaced its over-the-cap warning, so the Foreman was never told to trim it.
  grep -qF "# WARNING: $FD/state.md is" <<<"$out" || fail "the over-the-cap warning for state.md is not in the start"
}
# Only rules.md is too big: it alone is left out, and the saved state, which fits once rules.md is out, stays whole.
t_rulesonly() {
  local out
  fixture rulesonly
  text RULESBODY 150 > "$FD/rules.md"; text STATEBODY 20 > "$FD/state.md"
  out=$(start)
  [ "${#out}" -lt 10000 ] || fail "the start is ${#out} characters, not under 10000"
  grep -qF "Read $FD/rules.md now" <<<"$out" || fail "no Read line for rules.md"
  ! grep -qF "Read $FD/state.md now" <<<"$out" && [ "$(grep -c STATEBODY <<<"$out")" = 20 ] || fail "the state that fits was left out or cut"
}
# Small files: their whole text is in the start, and no Read line.
t_small() {
  local out
  fixture small
  text RULESBODY 5 > "$FD/rules.md"; text STATEBODY 5 > "$FD/state.md"
  out=$(start)
  [ "$(grep -c RULESBODY <<<"$out")" = 5 ] && [ "$(grep -c STATEBODY <<<"$out")" = 5 ] || fail "a small file's text is not whole in the start"
  ! grep -qE 'did not fit|Read .* now' <<<"$out" || fail "a start that fits has a Read line: $(grep -E 'did not fit' <<<"$out")"
}

cases=(big rulesonly small)
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do cat "$B/$c.out" >&2; [ -e "$B/$c.passed" ] || bad=1; done
[ "$bad" = 0 ] || exit 1
echo "ok [size]"
