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
  # Bug caught: the start text said the whole state.md stays under the cap, while stop.sh counts its open lines only, so
  # a Foreman cut finished items it could have marked done. The docs page is checked as text, as no behaviour reads it.
  grep -qF 'keep it current, its open lines under 5000 bytes' <<<"$st" || fail "the start text does not say the cap counts open lines only: $st"
  grep -qF 'The cap on the saved state counts only its open lines, not the `- DONE` items.' "$SRC/../../docs/foreman.md" || fail "docs/foreman.md does not say the cap counts open lines only"
  # Bug caught: with rules.testissues false, testissue makes a held card with no issue, and the start text gave only
  # `control release <issue>`, so the Foreman had no number to release it by.
  grep -qF 'so the issue starts held there too (rules.testissues false: a held card, released by its card ID)' <<<"$st" \
    || fail "the start text does not say how to release testissue's held card when test issues are off: $st"
}
# allkinds: every standing kind on, as in this repository's pack. The ask seam runs only `auto standing`, as
# foreman-standing.test.sh does.
allkinds() {
  local k='["asked-fix", "review-followup", "release-check", "fixed-block", "review-retry"]'
  jq --argjson k "$k" '.auto.standing = $k' "$M/.conveyor/project.json" > "$T/pack.json" && mv "$T/pack.json" "$M/.conveyor/project.json" \
    || fail "the pack with every standing kind was not made"
  export ENG=$SRC/../conveyor.sh CONVEYOR_FOREMAN_ASK='[[ $CONVEYOR_CMD == "auto standing "?* ]] || exit 3; cd "$CONVEYOR_MAIN" && bash "$ENG" auto standing "${CONVEYOR_CMD#auto standing }"'
}
# The fixed text of a start (every line up to and with the live summary's heading, the warnings left out) takes at most
# 52% of the 10,000 characters (5,200; it is 4,923 now), with every standing kind on and the folder in its paths 19
# characters long: the rest of the room is for the live summary, the owner's rules and the state (t_old and t_own hold that room).
# Bug it catches: the fixed text grew with each line added to it until 10 lines of rules beside 16 of state no longer
# fitted a start without --rules-apart, and a live start said the state "did not fit"; only t_old noticed, and its sample
# was cut to hide it. A start with every kind on is the largest the fixed text makes, so a line added to the standing
# rules counts here too.
t_fixed() {
  local st n
  fixture fixed; allkinds
  marked; st=$(hook start sA --rules-apart | ctx)
  grep -q '^# STANDING YES' <<<"$st" && grep -q -- '^- review-retry: ' <<<"$st" || fail "the start has no standing rules (a fixed text so long that they were saved to $FD/start-rest.md, a file that $([ -s "$FD/start-rest.md" ] && echo exists || echo does not exist), leaves them no room): ${st:0:200}"
  grep -q '^# Foreman mode: you are' <<<"$st" && grep -q '^# Live summary' <<<"$st" || fail "the start has no fixed text or no live summary: ${st:0:200}"
  # The fixture's folder ($B, under the runner's TMPDIR) is in every path of the text: it is swapped for a path of a set
  # length, so the count is the same under any TMPDIR, and counts the paths (the text names them many times).
  st=${st//"$B"//tmp/tmp.XXXXXXXXXX}
  n=$(awk '!/^# WARNING/ { print } /^# Live summary/ { exit }' <<<"$st" | wc -c)
  [ "$n" -le 5200 ] || fail "the fixed text of a start with every standing kind on is $n characters, over 52% of the 10,000 a start may have"
}
# A rules.md of 12000 bytes and a state.md over the limit: the rules output is under 10,000 characters, cut at a whole
# line, with a line that names the file and says to Read the rest; the start is under the limit too, with the fixed
# text whole and a Read line for the state, and no rules in it.
t_big() {
  local st ru last
  fixture big
  # Every standing kind is on: the fixed text is trimmed, so a state of 6,100 bytes (over the cap's 5,000) fits a start of
  # the test pack on its own, and the state has no room only beside the standing kinds of this repository's pack.
  allkinds
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
# The sample is 10 lines of rules and 16 of state with every standing kind on: the room the fixed text must leave, which
# a sample of 4 lines each (or kinds off) hid when the fixed text grew.
# 15 open decisions fill the live summary to its cap, as a busy project's does, and auto is on. Bug it catches: the live
# summary took its room first, or auto's rules and the standing kinds kept theirs, so the start swapped the 16 lines of
# state for a Read line and cut rules.md.
t_old() {
  local st out
  oldsample old
  marked; out=$(hook start sA); st=$(ctx <<<"$out")
  [ "$(grep -c RULESBODY <<<"$st")" = 10 ] && [ "$(grep -c STATEBODY <<<"$st")" = 16 ] || fail "a start without --rules-apart lacks the rules or the state: $(grep -E 'did not fit|cut to fit' <<<"$st")"
  autoread "$st"
  grep -qF 'gives the subject only' <<<"$st" && grep -q '^# Live summary' <<<"$st" && [ "${#out}" -lt 10000 ] \
    || fail "a start without --rules-apart, with a full live summary, lacks the owner rules or the live summary, or is ${#out} characters: $(grep -E 'did not fit|cut at' <<<"$st")"
  text RULESBODY 200 > "$FD/rules.md"; st=$(hook start sA)
  [ "${#st}" -lt 10000 ] && grep -qF "Read the rest from $FD/rules.md" <<<"$(ctx <<<"$st")" || fail "a start without --rules-apart is ${#st} characters or has no Read line"
}
# Bug it catches: the live summary took its room (up to LIVE_CAP) before the saved state was measured, so with 15 open
# decisions a start without --rules-apart swapped the 16 lines of state for a Read line, and once the state fit, the
# live summary left rules.md under rules_text's 300-byte margin, so none of its 10 lines came. The live summary now yields.
t_old_live() {
  local st c i
  fixture old_live; allkinds
  text RULESBODY 10 > "$FD/rules.md"; text STATEBODY 16 > "$FD/state.md"
  mkdir -p "$M/.claude/metrics" || fail "the ledger folder was not made"
  for ((i = 1; i <= 15; i++)); do
    jq -cn --arg i "$i" '{id: "d\($i)", question: ("Approve the change \($i) " + ("q" * 150)), askedAt: "2026-11-22T10:00:00Z", answeredAt: null}'
  done > "$M/.claude/metrics/decisions.jsonl"
  marked; st=$(hook start sA); c=$(ctx <<<"$st")
  [ "${#st}" -lt 10000 ] || fail "a start without --rules-apart, with 15 open decisions, is ${#st} characters, not under 10000"
  grep -qF 'open decisions (15' <<<"$c" || fail "the live summary has no open decisions, so the fixture does not fill it: $(grep -A3 'Live summary' <<<"$c" | cut -c1-200)"
  [ "$(grep -c STATEBODY <<<"$c")" = 16 ] && ! grep -qF "Read $FD/state.md now" <<<"$c" \
    || fail "a start without --rules-apart, with 15 open decisions in the live summary, lacks the 16 state lines: $(grep -E 'did not fit|cut at' <<<"$c" | cut -c1-200)"
  [ "$(grep -c RULESBODY <<<"$c")" = 10 ] \
    || fail "a start without --rules-apart, with 15 open decisions in the live summary, has $(grep -c RULESBODY <<<"$c") of the 10 rules.md lines: $(grep -E 'did not fit|cut to fit' <<<"$c" | cut -c1-200)"
}
# t_old's sample with auto off, so the standing text stays in the start, and rules.md grown until the state and the whole
# rules leave the live summary 20 bytes: the start keeps the 16 lines of state and every line of rules.md, under 10,000
# characters (the standing text moves to start-rest.md, which leaves the live summary its room). The first start's cut
# line gives the room the live summary had; the line added to rules.md takes all but 20 bytes of it.
# Bug it catches: the live summary got the 20 bytes but printed its cut line (about 31 bytes) anyway, so the start went
# over its limit and rules_text cut rules.md.
t_old_gap() {
  local out c n
  oldsample old_gap
  (cd "$M" && bash "$SRC/../conveyor.sh" auto off) > /dev/null || fail "auto was not turned off"
  marked; c=$(hook start sA | ctx)
  n=$(sed -n 's/^\[live summary cut at \([0-9]*\) bytes\]$/\1/p' <<<"$c")
  [ -n "$n" ] && [ "$n" -gt 35 ] && [ "$n" -lt 1500 ] && grep -q -- '^- review-retry: ' <<<"$c" \
    || fail "the first start has the standing text in start-rest.md, or its live summary is not cut under LIVE_CAP with over 35 bytes (the added line's 15 and 20 left), so the gap cannot be set: '$n'"
  printf 'RULESBODY gap %s\n' "$(printf 'g%.0s' $(seq 1 $((n - 20 - 15))))" >> "$FD/rules.md"
  out=$(hook start sA); c=$(ctx <<<"$out")
  [ "$(grep -c RULESBODY <<<"$c")" = 11 ] && [ "$(grep -c STATEBODY <<<"$c")" = 16 ] && [ "${#out}" -lt 10000 ] \
    || fail "a start without --rules-apart that leaves the live summary 20 bytes (rules.md grown by $((n - 20)) bytes) has $(grep -c RULESBODY <<<"$c") of 11 rules lines, $(grep -c STATEBODY <<<"$c") of 16 state lines, or is ${#out} characters: $(grep -E 'did not fit|cut to fit|cut at' <<<"$c" | cut -c1-200)"
}

# The sample of t_old (10 lines of rules, 16 of state) fits this repository's own start without --rules-apart: its pack
# (every standing kind on, its auto.reserved), its record's name, the plugin-home text, the state folder in the checkout
# and the live summary of a quiet belt. The start is the real one, with no --rules-apart, so the owner rules and rules.md
# come from context() itself. Its folder, in every path of the text, has its length in a card's test slot (40
# characters, as in foreman-launcher.test.sh) and stays under the runner's TMPDIR (the share of temp space it counts): a
# shorter one is padded to it, so a shorter TMPDIR does not make the start fit when it does not fit in the slot; a longer
# one (a hand run of test-changed.sh from /tmp gives each file a TMPDIR of 27 characters, and mktemp's folder in it is
# 42) is swapped for a folder of a 3-character name in the same TMPDIR, padded the same way, so the start does not fail
# for room the slot has.
# Bug it catches (follow-up of #1536): t_old's sample fitted only a start smaller than this repository's own; here the
# standing text and the owner rules left rules.md 4 of its 10 lines.
t_own() {
  local st own n B=$B
  CASE=own
  if [ "${#B}" -gt 39 ]; then
    # The case runs in a subshell of its own: its exit removes this folder (OWN_TMP is global, so the trap still finds it
    # after t_own returns, when $B is the file's own folder again).
    OWN_TMP=$(mktemp -d "${B%/*}/XXX") || fail "the folder in ${B%/*} was not made"
    trap 'rm -rf "$OWN_TMP"' EXIT
    B=$OWN_TMP
    [ "${#B}" -le 39 ] || fail "TMPDIR ${B%/*} is too long for a folder of a card's test slot's length (40 characters)"
  fi
  [ "${#B}" -ge 39 ] || B+=/$(printf '%*s' $((39 - ${#B})) '' | tr ' ' p)
  fixture own; allkinds
  own=$(jq -r '.repository | if type == "object" then .url else . end' "$SRC/../../.claude-plugin/plugin.json")
  git -C "$M" remote set-url origin "git@github.com:${own#https://github.com/}.git" \
    && jq '.plugin = {follow: "main"}' "$SRC/../../.conveyor/project.json" > "$M/.conveyor/project.json" \
    && jq -n --arg h "$M" --arg r "${own##*/}" '{records: [{repo: $r, main: $h}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture of this repository's own start was not made"
  # The state folder's own place: the checkout's conveyor/state (lib/paths.sh state-dir), not the fixture's shorter one.
  FD=$M/conveyor/state/foreman; export CONVEYOR_FOREMAN_DIR=$FD; mkdir -p "$FD" || fail "the state folder was not made"
  # The snapshot of a quiet belt: no card in flight, blocked or waiting, the loop running.
  export CONVEYOR_FOREMAN_ASK='case $CONVEYOR_CMD in snapshot) echo "{\"snapshotAt\": \"2026-11-23T10:00:00Z\", \"belt\": [], \"health\": {\"loop\": true, \"state\": \"running\", \"reason\": null, \"blocked\": [], \"waiting\": []}}" ;; "auto standing "?*) cd "$CONVEYOR_MAIN" && bash "$ENG" auto standing "${CONVEYOR_CMD#auto standing }" ;; *) exit 3 ;; esac'
  text RULESBODY 10 > "$FD/rules.md"; text STATEBODY 16 > "$FD/state.md"
  marked; st=$(hook start sA | ctx)
  grep -q '^Conveyor [^ ]* (snapshot as of 2026-11-23T10:00:00Z): loop running' <<<"$st" && grep -qF "this project is the plugin's own repository" <<<"$st" \
    && grep -q -- '^- review-retry: ' <<<"$st" || fail "the start is not this repository's own (no live summary, plugin-home text or standing kinds): ${st:0:200}"
  n=$(printf '%s\n' "$st" | wc -c)
  ! grep -qE 'did not fit|Read the rest' <<<"$st" && [ "$(grep -c STATEBODY <<<"$st")" = 16 ] && [ "$(grep -c RULESBODY <<<"$st")" = 10 ] \
    && grep -qF "$(head -n 1 "$SRC/owner-rules.md")" <<<"$st" && [ "$n" -le 9000 ] \
    || fail "this repository's own start without --rules-apart ($n bytes) does not hold the owner rules, 10 lines of rules and 16 of state: $(grep -E 'did not fit|Read the rest' <<<"$st" | cut -c1-200)"
}
# oldsample <case>: t_old's sample in a new fixture: every kind on, as this repository's pack has them (the largest start
# a project makes), auto on, 15 open decisions, 10 lines of rules and 16 of state.
oldsample() {
  local i
  fixture "$1"; allkinds
  (cd "$M" && bash "$SRC/../conveyor.sh" auto on) > /dev/null || fail "auto was not turned on"
  mkdir -p "$M/.claude/metrics" || fail "the ledger folder was not made"
  for ((i = 1; i <= 15; i++)); do
    jq -cn --arg i "$i" '{id: "d\($i)", question: ("Approve the change \($i) " + ("q" * 150)), askedAt: "2026-11-22T10:00:00Z", answeredAt: null}'
  done > "$M/.claude/metrics/decisions.jsonl"
  text RULESBODY 10 > "$FD/rules.md"; text STATEBODY 16 > "$FD/state.md"
}
# autoread <start text>: auto's rules are in the start, or in start-rest.md that its Read line names, so the sample has
# auto's rules to place.
autoread() {
  grep -q '^# AUTO IS ON' <<<"$1" || { grep -qF "# $FD/start-rest.md (auto's rules" <<<"$1" && grep -q '^# AUTO IS ON' "$FD/start-rest.md"; } \
    || fail "the start has auto's rules neither in it nor in start-rest.md by a Read line: $(grep -n 'AUTO\|start-rest' <<<"$1" | cut -c1-200)"
}
# A claim made by the owner's words (the words hook, which has no --rules-apart and a smaller limit than a start) keeps
# the saved state, the owner rules and the ten project rules whole with t_old's sample, and its output stays under 10,000 characters. The
# session runs with a 5-minute cache, so the claim has its longest lines (the cache-time line names the checkout).
# Bug it catches: the live summary took the room first, the words hook kept a guessed 1,500 bytes (then 1,000) for what
# it adds, and it said the cache-time line twice, so the claim swapped the state, and the rules, for Read lines.
t_words_old() {
  local out c in
  oldsample words_old
  marked
  in=$(jq -cn --arg c "$M" '{session_id: "sB", prompt: "start your role", cwd: $c}')
  out=$( (cd "$M" && CLAUDE_CODE_PROMPT_CACHE_TTL=5m bash "$SRC/foreman.sh" words) <<<"$in") || fail "the words hook failed for $in"
  c=$(ctx <<<"$out")
  [ "$(grep -c STATEBODY <<<"$c")" = 16 ] && [ "$(grep -c RULESBODY <<<"$c")" = 10 ] && grep -qF 'gives the subject only' <<<"$c" && [ "${#out}" -lt 10000 ] \
    || fail "the words hook's claim for $in lacks the state, the project rules or the owner rules, or is ${#out} characters: $(grep -E 'did not fit|cut' <<<"$c" | cut -c1-200)"
  autoread "$c"
  [ "$(grep -c '^The Foreman runs with the prompt cache time 5m' <<<"$c")" = 1 ] \
    || fail "the words hook's claim for $in does not say the cache-time line once: $(grep -n 'prompt cache time' <<<"$c" | cut -c1-120)"
  # A state of 60 lines (under its cap) has no room beside the owner rules even with auto's rules moved out: it yields,
  # and the live summary leaves the owner rules their room (bug: it took that room, so both came as Read lines).
  text STATEBODY 60 > "$FD/state.md"
  in=$(jq -cn --arg c "$M" '{session_id: "sC", prompt: "start your role", cwd: $c}')
  out=$( (cd "$M" && CLAUDE_CODE_PROMPT_CACHE_TTL=5m bash "$SRC/foreman.sh" words) <<<"$in") || fail "the words hook failed for $in"
  c=$(ctx <<<"$out")
  grep -qF 'gives the subject only' <<<"$c" && grep -qF "Read $FD/state.md now" <<<"$c" && [ "${#out}" -lt 10000 ] \
    || fail "the words hook's claim for $in, with 60 lines of state, lacks the owner rules or the state's Read line, or is ${#out} characters: $(grep -E 'did not fit|cut' <<<"$c" | cut -c1-200)"
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

# Bug it catches (#1461 O148): the owner's words that claim the role (the words hook) wrap the claim's start in text
# and JSON the start's limit did not count, and the Read line for owner-rules.md and rules.md came last: once the
# fixed text and the rest (which have no cap) grew, the output went over 10,000 characters, Claude Code showed a
# preview of its start, and the Read line was lost. In the start of owner_mid_rules, the words hook's output is under
# 10,000 characters, and the Read line naming both files is in its first 2,000.
t_words_rules() {
  local out c a b len
  fixture words_rules
  marked
  grow() { jq -n --arg h "$M" --arg n "$(printf 'r%.0s' $(seq 1 "$1"))" '{records: [{repo: "alpha", main: $h}, {repo: $n, main: ($h + "/gone")}], foreman: {groups: [["alpha", $n]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"; }
  grow 100; a=$(hook start sA --rules-apart); a=${#a}
  grow 200; b=$(hook start sA --rules-apart); b=${#b}
  [ "$b" -gt "$a" ] || fail "a longer repo name did not lengthen the start ($a, $b)"
  len=$((100 + (8300 - a) * 100 / (b - a))); grow "$len"
  text STATEBODY 16 > "$FD/state.md"; text RULESBODY 3 > "$FD/rules.md"
  out=$(jq -cn --arg c "$M" '{session_id: "sB", prompt: "you are the foreman", cwd: $c}' | (cd "$M" && bash "$SRC/foreman.sh" words)) || fail "the words hook failed"
  c=$(ctx <<<"$out")
  [ -n "$c" ] || fail "the words hook gave no claim: $out"
  [ "${#out}" -lt 10000 ] || fail "the words hook's output, with a $len-character repo name, is ${#out} characters, not under 10000"
  grep -qF "$SRC/owner-rules.md and $FD/rules.md did not fit" <<<"${c:0:2000}" \
    || fail "no Read line naming owner-rules.md and rules.md in the first 2000 characters of the claim's ${#c}: ${c:0:400}"
}

# Bug it catches (review of #1461): in the plugin's own repository the start lists each unfiled plugin problem of
# plugin-bugs.md with its filed line, and the list had no cap: with 30 notes the start's output was 22,000 characters.
# It is under 10,000, with the WARNING line, the first note whole with its filed line, and a line that says to Read
# plugin-bugs.md for the rest. (The words hook leaves the test pack no room for a note: words_notes_full has its case.)
t_notes() {
  local out c i own
  fixture notes
  own=$(jq -r '.repository | if type == "object" then .url else . end' "$SRC/../../.claude-plugin/plugin.json")
  git -C "$M" remote set-url origin "git@github.com:${own#https://github.com/}.git" || fail "the origin was not set"
  for ((i = 1; i <= 30; i++)); do
    printf -- '- 2026-11-22T10:%02d:00Z · card c20261122T100000-alpha-%d · the price of a model is not in models.json, it should be there to count the cost, card c20261122T100000-alpha-%d, evidence ~/cards/c20261122T100000-alpha-%d.err · evidence: ~/cards/c20261122T100000-alpha-%d.err\n' "$i" "$i" "$i" "$i" "$i"
  done > "$FD/plugin-bugs.md"
  marked
  out=$(hook start sA --rules-apart); c=$(ctx <<<"$out")
  [ "${#out}" -lt 10000 ] || fail "the start's output, with 30 unfiled plugin problems in plugin-bugs.md, is ${#out} characters, not under 10000"
  grep -q '^# WARNING: plugin problems noted' <<<"$c" && grep -qxF '  Plugin problem (for the conveyor-belt repo): the price of a model is not in models.json, it should be there to count the cost, card c20261122T100000-alpha-1, evidence ~/cards/c20261122T100000-alpha-1.err, filed as #<n>' <<<"$c" \
    || fail "the start, with 30 unfiled plugin problems, does not list the first one with its filed line: ${c:0:400}"
  grep -qE "^# [0-9]+ more such notes did not fit in this start .*Read $FD/plugin-bugs.md now" <<<"$c" \
    || fail "the start, with 30 unfiled plugin problems, has no line that says to Read $FD/plugin-bugs.md for the rest"
}

# Bug it catches (review of the fix above): in the plugin's own checkout the pack's standing kinds and a full live
# summary leave the notes no room, yet the two notice lines were added all the same, and the live summary had no cap
# but its own, so the words hook's output was over 10,000 characters even with no note at all. With this repository's
# own pack, its standing kinds read, 15 open decisions and 30 notes, the output is under 10,000, and one short line that
# says to Read plugin-bugs.md stands for all the notes. And as those leave no room for a note, auto's rules and the
# standing kinds are saved to start-rest.md, which a Read line names (bug: the output was over 10,000 with no note).
# And (E3 of that review): the line that may stand for the saved state was made before the start's archive ran, so a
# state.md of only DONE items over its cap, which the archive empties, still got "over its cap: trim it" and a Read line,
# here where the start is full and the owner rules do not fit.
t_words_notes_full() {
  local out c i own
  fixture words_notes_full
  own=$(jq -r '.repository | if type == "object" then .url else . end' "$SRC/../../.claude-plugin/plugin.json")
  git -C "$M" remote set-url origin "git@github.com:${own#https://github.com/}.git" || fail "the origin was not set"
  jq '.plugin = {follow: "main"}' "$SRC/../../.conveyor/project.json" > "$M/.conveyor/project.json" || fail "the pack was not copied"
  # A second project with a long name: the start's fixed text is trimmed, so the pack's standing kinds alone no longer
  # leave a live summary and the notes no room, which is what this case needs (the name is in the start several times).
  jq -n --arg h "$M" --arg n "$(printf 'r%.0s' {1..1500})" '{records: [{repo: "alpha", main: $h}, {repo: $n, main: ($h + "/gone")}], foreman: {groups: [["alpha", $n]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file with a long project name was not made"
  for ((i = 1; i <= 30; i++)); do
    printf -- '- 2026-11-22T10:%02d:00Z · card c20261122T100000-alpha-%d · the price of a model is not in models.json, card c20261122T100000-alpha-%d, evidence ~/cards/c20261122T100000-alpha-%d.err · evidence: ~/cards/c20261122T100000-alpha-%d.err\n' "$i" "$i" "$i" "$i" "$i"
  done > "$FD/plugin-bugs.md"
  mkdir -p "$M/.claude/metrics" || fail "the ledger folder was not made"
  for ((i = 1; i <= 15; i++)); do
    jq -cn --arg i "$i" '{id: "d\($i)", question: ("Approve the change \($i) " + ("q" * 150)), askedAt: "2026-11-22T10:00:00Z", answeredAt: null}'
  done > "$M/.claude/metrics/decisions.jsonl"
  # The standing kinds are read from this checkout's engine, as the real record's are; the snapshot cannot be read.
  export CONVEYOR_FOREMAN_ASK='case $CONVEYOR_CMD in "auto standing "*) cd "$CONVEYOR_MAIN" && bash "$ENGINE" auto standing "${CONVEYOR_CMD#auto standing }" ;; *) exit 3 ;; esac'
  export ENGINE=$SRC/../conveyor.sh
  marked
  # After the claim of sA, whose start would archive it first.
  for ((i = 1; i <= 80; i++)); do printf -- '- DONE 2026-11-22 10:%02d ET: card %d landed, its issue closed and its await line removed\n' "$((i % 60))" "$i"; done > "$FD/state.md"
  [ "$(wc -c < "$FD/state.md")" -gt 5000 ] || fail "the fixture's state.md is not over its 5000-byte cap"
  out=$(jq -cn --arg c "$M" '{session_id: "sB", prompt: "you are the foreman", cwd: $c}' | (cd "$M" && bash "$SRC/foreman.sh" words)) || fail "the words hook failed"
  c=$(ctx <<<"$out")
  grep -qF '# STANDING YES' "$FD/start-rest.md" || fail "start-rest.md has no standing kinds, so the fixture does not test the real pack: $(head -c 400 "$FD/start-rest.md" 2>&1)"
  grep -qxF "# $FD/start-rest.md (auto's rules and the standing kinds of routine yes) did not fit in this start (Claude Code cuts a start over 10,000 characters): Read it now, before you act." <<<"$c" \
    || fail "the words hook's claim, with no room for the standing kinds, has no line that says to Read $FD/start-rest.md: $(grep -n 'STANDING\|start-rest' <<<"$c" | cut -c1-200)"
  [ ! -s "$FD/state.md" ] || fail "the start did not archive the DONE items of state.md: $(head -c 200 "$FD/state.md")"
  ! grep -E "state\.md is [0-9]+ bytes, over its|Read $FD/state\.md now" <<<"$c" \
    || fail "the words hook's claim, for a state.md of DONE items only that the start archived, still says to trim or Read it"
  [ "${#out}" -lt 10000 ] || fail "the words hook's output, with the plugin's own pack, a full live summary and 30 unfiled plugin problems, is ${#out} characters, not under 10000"
  grep -qxF "# WARNING: 30 plugin problems noted in $FD/plugin-bugs.md have no issue number yet, and did not fit in this start: Read it now, and for each one search this repository's issues for one that reports it, file it only when none does, then say its line in the form above with that issue's number." <<<"$c" \
    || fail "the words hook's claim, with no room for a note, has no one line that says to Read $FD/plugin-bugs.md: $(grep -n 'plugin-bugs' <<<"$c" | cut -c1-200)"
}

cases=(fit fixed big other race old old_live own old_gap words_old owner owner_whole owner_mid owner_mid_rules words_rules notes words_notes_full)
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/tests/casesreport-helper.sh"
casesreport "$B" size- "${cases[@]}" || exit 1
echo "ok [size]"
