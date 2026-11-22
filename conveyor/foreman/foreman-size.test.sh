#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's start (foreman.sh start, its context) and its rules hook (foreman.sh rules) each stay under Claude Code's
# 10,000-character limit on a hook's output; when a file does not fit, the output cuts it at a whole line and tells the
# Foreman to Read the rest.
# Bug it catches: a start of 23 KB (a big rules.md and state.md) went over the limit, so Claude Code kept it out of the
# context and gave the session a 2 KB preview: no rules, no standing kinds, no saved state, and the role looked not started.
# And a rules.md of 4.5 KB never fitted beside the fixed text, so every start sent only a line telling the Foreman to Read it.
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
# marked: makes session sA the Foreman (the claim's own output is not under test here).
marked() { (cd "$M" && bash "$SRC/foreman.sh" claim sA) > /dev/null || fail "the claim failed"; }
# ctx: the text a start's JSON output gives the session (its additionalContext); the length checks below take the whole JSON
# output, which is what Claude Code measures against its 10,000 characters.
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty'; }
# hook <start|rules> <session> [<argument>...]: the SessionStart hook's output for that session; the plugin's start
# command passes --rules-apart.
hook() { jq -cn --arg s "$2" '{session_id: $s, source: "startup", transcript_path: ""}' | (cd "$M" && bash "$SRC/foreman.sh" "$1" "${@:3}") || fail "the $1 hook failed"; }

# A rules.md of 6000 bytes and a state.md of 1000: the rules are whole in the rules output, the state whole in the start
# output, and neither has a "did not fit" line.
t_fit() {
  local st ru
  fixture fit
  text RULESBODY 98 > "$FD/rules.md"; text STATEBODY 16 > "$FD/state.md"
  marked; st=$(hook start sA --rules-apart | ctx); ru=$(hook rules sA)
  [ "$(grep -c RULESBODY <<<"$ru")" = 98 ] && ! grep -q RULESBODY <<<"$st" || fail "the rules are not whole in the rules output only"
  [ "$(grep -c STATEBODY <<<"$st")" = 16 ] && ! grep -q STATEBODY <<<"$ru" || fail "the state is not whole in the start output only"
  ! grep -qE 'did not fit|Read .* now' <<<"$st$ru" || fail "an output that fits has a Read line: $(grep -E 'did not fit' <<<"$st$ru")"
}
# A rules.md of 12000 bytes and a state.md over the limit: the rules output is under 10,000 characters, cut at a whole
# line, with a line that names the file and says to Read the rest; the start is under the limit too, with the fixed
# text whole and a Read line for the state, and no rules in it.
t_big() {
  local st ru last
  fixture big
  text RULESBODY 200 > "$FD/rules.md"; text STATEBODY 100 > "$FD/state.md"
  marked; st=$(hook start sA --rules-apart); ru=$(hook rules sA)
  [ "${#ru}" -lt 10000 ] || fail "the rules output is ${#ru} characters, not under 10000"
  last=$(grep RULESBODY <<<"$ru" | tail -1)
  [ -n "$last" ] && [ "$(grep -c RULESBODY <<<"$ru")" -lt 200 ] && [ "${#last}" = 60 ] || fail "the rules were not cut at a whole line: last line '$last'"
  grep -qF "Read the rest from $FD/rules.md" <<<"$ru" || fail "no Read line names $FD/rules.md in the rules output"
  [ "${#st}" -lt 10000 ] || fail "the start is ${#st} characters, not under 10000"
  grep -qF '# Foreman mode: you are' <<<"$st" && grep -qF 'Live summary' <<<"$st" || fail "the fixed text or the live summary was cut: ${st:0:300}"
  grep -E "Read $FD/state.md now" <<<"$st" | grep -qF "$FD/state.md did not fit" || fail "no Read line names $FD/state.md in the start"
  ! grep -qE 'RULESBODY|STATEBODY' <<<"$st" || fail "a file's text stayed in a start that is over the limit"
  # Bug: the Read line for an oversized state.md replaced its over-the-cap warning, so the Foreman was never told to trim it.
  grep -qF "# WARNING: $FD/state.md is" <<<"$st" || fail "the over-the-cap warning for state.md is not in the start"
}
# Bug: a session that is not the Foreman was given the project's rules.
t_other() {
  local ru
  fixture other
  text RULESBODY 5 > "$FD/rules.md"
  marked; ru=$(hook rules sB)
  [ -z "$ru" ] || fail "a session that is not the Foreman got a rules output: ${ru:0:200}"
}
# Bug: the rules hook runs beside start, so it read the mark before start made the session the Foreman and
# sent nothing (here auto makes a new session in the main checkout the Foreman). It must wait for start to end.
t_race() {
  local ru=$B/race.rules
  fixture race
  text RULESBODY 5 > "$FD/rules.md"
  hook rules sA > "$ru" & local rp=$!
  sleep 0.5 # sleep: the rules hook is already waiting when start runs
  hook start sA --rules-apart > /dev/null; wait "$rp"
  [ "$(grep -c RULESBODY "$ru")" = 5 ] || fail "the rules hook did not wait for start: $(cat "$ru")"
}

# Bug: a plugin from before the rules hook calls start with no --rules-apart and has no rules hook, so a start that
# always left rules.md out gave that session no project rules at all. Without the flag the rules come in the start, under
# the limit, whole when they fit and cut at a whole line with the Read line when they do not.
t_old() {
  local st
  fixture old
  # Small files that fit: without --rules-apart the fixed text and the owner rules take most of the limit, so a few
  # lines of each leave room as the fixed text grows (10 lines of rules beside 16 of state no longer fitted).
  text RULESBODY 4 > "$FD/rules.md"; text STATEBODY 4 > "$FD/state.md"
  marked; st=$(hook start sA | ctx)
  [ "$(grep -c RULESBODY <<<"$st")" = 4 ] && [ "$(grep -c STATEBODY <<<"$st")" = 4 ] || fail "a start without --rules-apart lacks the rules or the state: $(grep -E 'did not fit|cut to fit' <<<"$st")"
  text RULESBODY 200 > "$FD/rules.md"; st=$(hook start sA)
  [ "${#st}" -lt 10000 ] && grep -qF "Read the rest from $FD/rules.md" <<<"$(ctx <<<"$st")" || fail "a start without --rules-apart is ${#st} characters or has no Read line"
}

# A project with no rules.md still gets the plugin's 11 rules on working with the owner, in the rules output, and the
# start with them stays under the limit; the start's await-file line names the idle wake for a batch of cards.
# Bug it catches (#1295): the rules lived only in one project's rules.md, so another project's Foreman had none of them,
# and its await line told it to append every issue, one wake turn for each card of a batch.
t_owner() {
  local st ru i
  local -a phrase=("Scope is the owner's words" "gets an answer and nothing else" "rulings.jsonl" "real options only"
    "approved mockup is the spec" "conveyor.sh shut <issue>" "not one await line per card" "follow-up depth limit"
    "Never retry a refusal" "gives the subject only" "Never offer the owner manual work")
  fixture owner
  text STATEBODY 16 > "$FD/state.md"
  marked; st=$(hook start sA --rules-apart); ru=$(hook rules sA)
  [ ! -e "$FD/rules.md" ] || fail "the fixture has a local rules.md"
  for i in "${!phrase[@]}"; do
    grep -qF -- "$((i + 1)). " <<<"$ru" && grep -qF -- "${phrase[i]}" <<<"$ru" || fail "rule $((i + 1)) (${phrase[i]}) is not in the rules output: ${ru:0:300}"
  done
  [ "${#st}" -lt 10000 ] || fail "the start is ${#st} characters, not under 10000"
  grep -F 'await-' <<<"$(ctx <<<"$st")" | grep -qF 'idle wake ("Conveyor is idle")' || fail "the await-file line does not name the idle wake for a batch: $(grep -F 'await-' <<<"$(ctx <<<"$st")" | cut -c1-300)"
}

# Bug it catches (#1295): without --rules-apart (a plugin from before the rules hook) the start keeps a state that
# fits alone (8,500 characters in all), then the 11 rules were added after it: over 10,000, so Claude Code dropped the start.
t_owner_whole() {
  local st base n
  fixture owner_whole
  marked; base=$(hook start sA --rules-apart); base=${#base}
  n=$(((8500 - base) / 60)); [ "$n" -gt 0 ] || fail "the start without a state is already $base characters"
  text STATEBODY "$n" > "$FD/state.md"
  st=$(hook start sA)
  [ "${#st}" -lt 10000 ] || fail "a start without --rules-apart is ${#st} characters, not under 10000 ($base without a state)"
  grep -qF 'gives the subject only' <<<"$(ctx <<<"$st")" || fail "a start without --rules-apart lacks the owner rules: ${st:0:300}"
}

# Bug it catches (#1295): the fixed text and the rest (auto's rules, standing kinds, live summary) alone took 8,300
# characters, so even with the saved state swapped for a Read line the 1,783 characters of owner rules went the start
# over 10,000 and Claude Code dropped it. The owner rules then yield to a Read line.
t_owner_mid() {
  local st a b len
  fixture owner_mid
  marked
  grow() { jq -n --arg h "$M" --arg n "$(printf 'r%.0s' $(seq 1 "$1"))" '{records: [{repo: "alpha", main: $h}, {repo: $n, main: ($h + "/gone")}], foreman: {groups: [["alpha", $n]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"; }
  grow 100; a=$(hook start sA --rules-apart); a=${#a}
  grow 200; b=$(hook start sA --rules-apart); b=${#b}
  [ "$b" -gt "$a" ] || fail "a longer repo name did not lengthen the start ($a, $b)"
  len=$((100 + (8300 - a) * 100 / (b - a))); grow "$len"
  text STATEBODY 16 > "$FD/state.md"
  st=$(hook start sA)
  [ "${#st}" -lt 10000 ] || fail "a start without --rules-apart with $len-character repo name is ${#st} characters, not under 10000"
  grep -qF "$SRC/owner-rules.md did not fit" <<<"$(ctx <<<"$st")" || fail "no Read line names owner-rules.md in a start of ${#st} characters: ${st: -300}"
}

# Bug it catches (#1296): in the same start as owner_mid, with a rules.md in the project, the Read line named only
# owner-rules.md and returned before the project's rules.md was sent or named, so the Foreman never learned it existed.
t_owner_mid_rules() {
  local st a b len
  fixture owner_mid_rules
  marked
  grow() { jq -n --arg h "$M" --arg n "$(printf 'r%.0s' $(seq 1 "$1"))" '{records: [{repo: "alpha", main: $h}, {repo: $n, main: ($h + "/gone")}], foreman: {groups: [["alpha", $n]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"; }
  grow 100; a=$(hook start sA --rules-apart); a=${#a}
  grow 200; b=$(hook start sA --rules-apart); b=${#b}
  [ "$b" -gt "$a" ] || fail "a longer repo name did not lengthen the start ($a, $b)"
  len=$((100 + (8300 - a) * 100 / (b - a))); grow "$len"
  text STATEBODY 16 > "$FD/state.md"; text RULESBODY 3 > "$FD/rules.md"
  st=$(hook start sA)
  [ "${#st}" -lt 10000 ] || fail "a start without --rules-apart with $len-character repo name is ${#st} characters, not under 10000"
  grep -qF "$SRC/owner-rules.md and $FD/rules.md did not fit" <<<"$(ctx <<<"$st")" || fail "no Read line names both owner-rules.md and rules.md in a start of ${#st} characters: ${st: -300}"
}

cases=(fit big other race old owner owner_whole owner_mid owner_mid_rules)
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do cat "$B/$c.out" >&2; [ -e "$B/$c.passed" ] || bad=1; done
[ "$bad" = 0 ] || exit 1
echo "ok [size]"
