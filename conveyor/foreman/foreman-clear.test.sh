#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's start (foreman.sh start) after a /clear: Claude Code gives the session a new id (SessionStart source
# clear) in the same process. Claude Code writes the new id into that process's sessions/<pid>.json before it runs the
# hook, so the file names the new session at hook time.
# Bug (#89): start acted on startup, resume and fork only, so a /clear in the Foreman's session left it a normal
# session, with no rules, saved state or watchers, and the mark naming the old id: the owner had to run
# /conveyor-belt:foreman again by hand.
# Bug (#1184): the check wanted the file to still name the old id, which Claude Code had already replaced, so the
# mark kept the old id again.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR
# A claim opens the Board in the browser (board-open.test.sh, with a stub opener); here no claim may open a real one.
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
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
# set_file <id>: this shell's sessions/<pid>.json names that session, as Claude Code writes it at a /clear.
set_file() { jq -cn --argjson p "$$" --arg s "$1" '{pid: $p, sessionId: $s, startedAt: 1794650400000, kind: "interactive"}' > "$HOME/.claude/sessions/$$.json"; }
fail() { echo "FAIL [clear-$CASE]: $*" >&2; exit 1; }
mark() { cut -d' ' -f1 "$FD/session" 2>/dev/null; }
clear_b() { jq -cn '{session_id: "sB", source: "clear", transcript_path: "", stop_hook_active: false}' | bash "$SRC/foreman.sh" start | jq -r '.hookSpecificOutput.additionalContext // empty'; }

# D1: the Foreman's /clear, with the file naming the new session B as Claude Code writes it before the hook runs: B
# takes the mark, gets the Foreman's rules and saved state, and A is no longer marked (it is listed in former, so its
# waiter stops).
t_foreman() {
  fixture foreman
  bash "$SRC/foreman.sh" claim sA > /dev/null || fail "the claim of A failed"
  set_file sB
  out=$(clear_b) || fail "the start after /clear failed: $out"
  [ "$(mark)" = sB ] || fail "the session a /clear started in the Foreman's process is not marked: $(cat "$FD/session")"
  grep -qF '# Foreman mode: you are Foreman, the Foreman of this project' <<<"$out" && grep -qxF -- '- watch issue 12' <<<"$out" \
    && grep -qF '# Live summary' <<<"$out" || fail "the new Foreman session got no Foreman context: $out"
  grep -qxF sA "$FD/former" || fail "A, replaced by the /clear, is not listed as former: $(cat "$FD/former" 2>/dev/null)"
}
# D1b: the file still names A (the order the first fix expected): the role moves all the same.
t_oldfile() {
  fixture oldfile
  bash "$SRC/foreman.sh" claim sA > /dev/null || fail "the claim of A failed"
  out=$(clear_b)
  [ "$(mark)" = sB ] || fail "a /clear with the file naming the old session did not move the mark: $(cat "$FD/session") $out"
}
# D2b: a /clear in another Claude process, whose own sessions/<pid>.json names B, while the Foreman's process (this
# shell, recorded at the claim) is another: the mark stays. Catches a check that trusts the new id alone.
t_otherproc() {
  fixture otherproc
  bash "$SRC/foreman.sh" claim sA > /dev/null || fail "the claim of A failed"
  # The second shell stands for the other Claude process: its own file names B, and the hook runs under it.
  out=$(bash -c 'jq -cn --argjson p "$$" "{pid: \$p, sessionId: \"sB\", kind: \"interactive\"}" > "$HOME/.claude/sessions/$$.json"
    jq -cn "{session_id: \"sB\", source: \"clear\", transcript_path: \"\"}" | bash "$1/foreman.sh" start' _ "$SRC")
  [ "$(mark)" = sA ] && [ -z "$out" ] || fail "a /clear in another Claude process took the role: $(cat "$FD/session") $out"
}
# in_new_proc <source:session>...: one new shell, standing for another Claude process, runs a start hook for each
# source and session in turn, its own sessions/<pid>.json naming that session first, as Claude Code writes it; the
# file is gone when the process ends.
in_new_proc() {
  bash -c 'for a in "${@:2}"; do
      jq -cn --argjson p "$$" --arg s "${a#*:}" "{pid: \$p, sessionId: \$s, kind: \"interactive\"}" > "$HOME/.claude/sessions/$$.json"
      jq -cn --arg s "${a#*:}" --arg src "${a%%:*}" "{session_id: \$s, source: \$src, transcript_path: \"\"}" | bash "$1/foreman.sh" start
    done
    rm -f "$HOME/.claude/sessions/$$.json"' _ "$SRC" "$@"
}
# E1: the Foreman's session reopened by `claude --resume` in a new Claude process after the first one ended (its
# sessions file is gone), then a /clear there: the new process holds the Foreman now, so B takes the mark. Catches a
# record that stays with the first process.
t_resumenew() {
  fixture resumenew
  bash "$SRC/foreman.sh" claim sA > /dev/null || fail "the claim of A failed"
  rm -f "$HOME/.claude/sessions/$$.json"
  out=$(in_new_proc resume:sA clear:sB)
  [ "$(mark)" = sB ] || fail "a /clear in the reopened Foreman's new process did not move the mark: $(cat "$FD/session") $out"
}
# E3: a second Claude process reopens the Foreman's session while the Foreman's process runs on, then ends; a /clear
# in the Foreman's process still moves the role. Catches a record that the second process takes over.
t_resumesecond() {
  fixture resumesecond
  bash "$SRC/foreman.sh" claim sA > /dev/null || fail "the claim of A failed"
  in_new_proc resume:sA > /dev/null
  set_file sB
  out=$(clear_b)
  [ "$(mark)" = sB ] || fail "a /clear in the Foreman's process after a second process reopened it did not move the mark: $(cat "$FD/session") $out"
}
# E2: a /resume in the Foreman's process to an unrelated session X, then a /clear in X: X is not the Foreman, so the
# mark stays. Catches a record that still names the process after the Foreman's session left it.
t_resumeother() {
  fixture resumeother
  bash "$SRC/foreman.sh" claim sA > /dev/null || fail "the claim of A failed"
  set_file sX
  jq -cn '{session_id: "sX", source: "resume", transcript_path: ""}' | bash "$SRC/foreman.sh" start > /dev/null
  set_file sB
  out=$(clear_b)
  [ "$(mark)" = sA ] && [ -z "$out" ] || fail "a /clear in an unrelated session resumed in the Foreman's process took the role: $(cat "$FD/session") $out"
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

cases=(foreman oldfile other otherproc resumenew resumesecond resumeother off)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/casesreport.sh"
casesreport "$B" clear- "${cases[@]}" || exit 1
echo "ok [foreman-clear]"
