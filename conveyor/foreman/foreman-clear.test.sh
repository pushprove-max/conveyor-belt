#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's start (foreman.sh start) after a /clear: Claude Code gives the session a new id (SessionStart source
# clear) in the same process, whose sessions/<pid>.json names the session it replaces.
# Bug (#89): start acted on startup, resume and fork only, so a /clear in the Foreman's session left it a normal
# session, with no rules, saved state or watchers, and the mark naming the old id: the owner had to run
# /conveyor-belt:foreman again by hand.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR
# Records cannot be asked here: the live summary says so, which the start's context prints all the same.
export CONVEYOR_FOREMAN_ASK='exit 3'
# fixture <case>: a project alpha, its Foreman's folder with a saved state, and this test's own shell (an ancestor of
# every hook it runs, as Claude Code's process is of its hooks) holding session A in Claude Code's sessions/<pid>.json.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$HOME/.claude/sessions" "$XDG_CONFIG_HOME/conveyor" "$FD" && git init -q "$M" && mkdir -p "$M/.conveyor" \
    && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && printf '# Foreman: saved state\n- watch issue 12\n' > "$FD/state.md" \
    && jq -cn --argjson p "$$" '{pid: $p, sessionId: "sA", startedAt: 1794650400000, kind: "interactive"}' > "$HOME/.claude/sessions/$$.json" \
    || fail "the fixture was not made"
}
fail() { echo "FAIL [clear-$CASE]: $*" >&2; exit 1; }
mark() { cut -d' ' -f1 "$FD/session" 2>/dev/null; }
clear_b() { jq -cn '{session_id: "sB", source: "clear", transcript_path: "", stop_hook_active: false}' | bash "$SRC/foreman.sh" start; }

# D1: the Foreman's /clear: the new session B takes the mark, gets the Foreman's rules and saved state, and A is no
# longer marked (it is listed in former, so its waiter stops).
t_foreman() {
  fixture foreman
  bash "$SRC/foreman.sh" claim sA > /dev/null || fail "the claim of A failed"
  out=$(clear_b) || fail "the start after /clear failed: $out"
  [ "$(mark)" = sB ] || fail "the session a /clear started in the Foreman's process is not marked: $(cat "$FD/session")"
  grep -qF '# Foreman mode: you are Foreman, the Foreman of this project' <<<"$out" && grep -qxF -- '- watch issue 12' <<<"$out" \
    && grep -qF '# Live summary' <<<"$out" || fail "the new Foreman session got no Foreman context: $out"
  grep -qxF sA "$FD/former" || fail "A, replaced by the /clear, is not listed as former: $(cat "$FD/former" 2>/dev/null)"
}
# D2: a /clear in a session that is not the Foreman: the Foreman is another session (C), and B takes nothing.
t_other() {
  fixture other
  bash "$SRC/foreman.sh" claim sC > /dev/null || fail "the claim of C failed"
  out=$(clear_b)
  [ "$(mark)" = sC ] && [ -z "$out" ] || fail "a /clear in a session that was not the Foreman took the role: $(cat "$FD/session") $out"
}
# D3: a /clear after off in the Foreman's session: off stays off.
t_off() {
  fixture off
  bash "$SRC/foreman.sh" claim sA > /dev/null && bash "$SRC/foreman.sh" off > /dev/null || fail "the claim and off failed"
  out=$(clear_b)
  [ -z "$(mark)" ] && [ -z "$out" ] || fail "a /clear after off took the role back: $(cat "$FD/session") $out"
}

cases=(foreman other off)
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do cat "$B/$c.out" >&2; [ -e "$B/$c.passed" ] || bad=1; done
[ "$bad" = 0 ] || exit 1
echo "ok [foreman-clear]"
