#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's session name: its start (foreman.sh start) and, for a session that took the role by claim, the words hook
# (foreman.sh words) give Claude Code hookSpecificOutput.sessionTitle "<project> - foreman", and no other session gets one.
# Bug it catches: the Foreman's conversation kept the name Claude Code gave it, so several open sessions could not be told
# apart from the Foreman's; a claim runs a Bash command, whose output cannot name a session, so its next prompt does.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
export CONVEYOR_FOREMAN_ASK='exit 3' # the records cannot be asked here: the live summary says so, which the start prints all the same
fail() { echo "FAIL [title-$CASE]: $*" >&2; exit 1; }
# fixture <case>: a project alpha (the Foreman's checkout) and this shell as the Claude Code process of session sA.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$HOME/.claude/sessions" "$XDG_CONFIG_HOME/conveyor" "$FD" && git init -q "$M" && mkdir -p "$M/.conveyor" \
    && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && jq -cn --argjson p "$$" '{pid: $p, sessionId: "sA", startedAt: 1794650400000, kind: "interactive"}' > "$HOME/.claude/sessions/$$.json" \
    || fail "the fixture was not made"
}
claim() { (cd "$M" && bash "$SRC/foreman.sh" claim "$1") > /dev/null || fail "the claim of $1 failed"; }
# start <session> <source>: the SessionStart hook's output for that session in the Foreman's checkout.
start() { jq -cn --arg s "$1" --arg src "$2" '{session_id: $s, source: $src, transcript_path: ""}' | (cd "$M" && bash "$SRC/foreman.sh" start); }
# prompt <session> <text>: the UserPromptSubmit hook's output for that prompt.
prompt() { jq -cn --arg s "$1" --arg p "$2" --arg c "$M" '{session_id: $s, prompt: $p, cwd: $c}' | bash "$SRC/foreman.sh" words; }
# titled <output> <start text>: the output names the session "alpha - foreman", and its additionalContext holds the text.
titled() {
  [ "$(jq -r '.hookSpecificOutput.sessionTitle // empty' <<<"$1")" = 'alpha - foreman' ] \
    && jq -e --arg t "$2" '.hookSpecificOutput.additionalContext | contains($t)' <<<"$1" > /dev/null || fail "$3: no sessionTitle 'alpha - foreman', or the start text '$2' is missing: $1"
}

# A marked Foreman session's start, as Claude Code runs it at a startup, a resume of the same session and a /clear.
t_startup() {
  fixture startup; claim sA
  titled "$(start sA startup)" '# Foreman mode: you are Foreman' 'startup of the marked session'
}
t_resume() {
  fixture resume; claim sA
  titled "$(start sA resume)" '# Foreman mode: you are Foreman' 'resume of the marked session'
}
t_clear() {
  fixture clear; claim sA
  # Claude Code has written the new id to the process's file before the /clear hook runs.
  jq -cn --argjson p "$$" '{pid: $p, sessionId: "sB", startedAt: 1794650400000, kind: "interactive"}' > "$HOME/.claude/sessions/$$.json"
  titled "$(start sB clear)" '# Foreman mode: you are Foreman' 'the session a /clear made in the Foreman process'
}
# A new session in the main checkout with no live Foreman takes the role at its start (auto) and is named in that output.
t_auto() {
  fixture auto
  titled "$(start sA startup)" 'This session is now the Foreman: no live session held the role' 'the auto claim'
}
# A group's Foreman is named for its first project, not the checkout it runs in.
t_group() {
  fixture group
  jq -n --arg a "$M" --arg b "$T/beta" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}], foreman: {groups: [["beta", "alpha"]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  claim sA
  [ "$(start sA startup | jq -r '.hookSpecificOutput.sessionTitle // empty')" = 'beta - foreman' ] || fail "a group's Foreman is not named for its first project"
}
# A session that is not the Foreman gets no title: a resume of it prints nothing, a new session told to ask the owner gets
# the question and no title, and its prompts give none.
t_other() {
  local out
  fixture other; claim sA
  out=$(start sB resume); [ -z "$out" ] || fail "a resume of a session that is not the Foreman printed: $out"
  out=$(start sB startup)
  jq -e '.hookSpecificOutput.additionalContext | contains("Take over")' <<<"$out" > /dev/null \
    && jq -e '.hookSpecificOutput | has("sessionTitle") | not' <<<"$out" > /dev/null || fail "a session told to ask whether to take over has a sessionTitle, or no question: $out"
  out=$(prompt sB 'what is the state of the belt?'); [ -z "$out" ] || fail "a prompt of a session that is not the Foreman gave: $out"
}
# A session that took the role by claim is named by its next prompt, once. The claim (a Bash command) names nothing.
t_words() {
  local out
  fixture words
  claim sA
  out=$(prompt sA 'what is the state of the belt?')
  [ "$(jq -r '.hookSpecificOutput | "\(.hookEventName) \(.sessionTitle)"' <<<"$out")" = 'UserPromptSubmit alpha - foreman' ] || fail "the first prompt after a claim did not name the session: $out"
  out=$(prompt sA 'and the next one?'); [ -z "$out" ] || fail "a later prompt named the session again: $out"
  # A Foreman that start named has nothing left to name: a prompt after it gives no title.
  claim sB; start sB resume > /dev/null
  out=$(prompt sB 'hello'); [ -z "$out" ] || fail "a prompt after the start named the session again: $out"
}
# The owner's words claim and name the session in the one output.
t_words_claim() {
  local out
  fixture words_claim
  out=$(prompt sA 'Start your role'); jq -e '.hookSpecificOutput | .sessionTitle == "alpha - foreman" and (.additionalContext | contains("now the Foreman"))' <<<"$out" > /dev/null \
    || fail "the words that claim the role did not name the session: $out"
  out=$(prompt sA 'hello'); [ -z "$out" ] || fail "a prompt after the words named the session again: $out"
}
# Bug it catches: the words hook named a session whose claim failed (a project in two groups has two Foremen, so the claim
# is refused), and noted it as named. If the session became the Foreman later by another route, a prompt would then find
# it noted as named and never give it its title.
t_words_claim_fails() {
  local out
  fixture words_claim_fails
  jq -n --arg a "$M" --arg b "$T/beta" '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}], foreman: {groups: [["alpha", "beta"], ["beta", "alpha"]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  out=$(prompt sA 'Start your role')
  jq -e '.hookSpecificOutput | (.additionalContext | contains("the claim failed")) and (has("sessionTitle") | not)' <<<"$out" > /dev/null     || fail "the words whose claim failed gave a sessionTitle, or did not say the claim failed: $out"
  [ ! -e "$FD/titled" ] || fail "a failed claim noted the session as named: $(cat "$FD/titled")"
}
# cc_pid (lib.sh), run two processes below the case's own, finds this shell, the Claude Code process of the fixture, with
# one ps. Bug it catches: one ps for each ancestor, each a read of every process, made a claim or start slow on a busy
# machine, and foreman-size.test.sh ran past its time limit under the test step's strace.
t_ccpid() {
  local real out n cmd
  fixture ccpid
  real=$(command -v ps) && mkdir -p "$T/bin" || fail "no ps on PATH, or no stub folder"
  # stub: ps counts its calls in $T/ps.calls, then runs the real ps, so the walk is the real one.
  printf '#!/usr/bin/env bash\necho x >> %q\nexec %q "$@"\n' "$T/ps.calls" "$real" > "$T/bin/ps" && chmod +x "$T/bin/ps" || fail "the ps stub was not made"
  # The outer bash runs a command after the inner one, so it stays a process of its own between them and this case.
  cmd='bash -c ". \"\$1\" && PATH=\$2:\$PATH cc_pid" _ "$1" "$2"; :'
  out=$(bash -c "$cmd" _ "$SRC/lib.sh" "$T/bin")
  n=$(grep -c '' "$T/ps.calls" 2>/dev/null)
  [ "$out" = "$$" ] && [ "$n" = 1 ] \
    || fail "bash -c '$cmd' (cc_pid, with $HOME/.claude/sessions/$$.json) printed '$out' after $n ps calls, not $$ after 1"
}

cases=(startup resume clear auto group other words words_claim words_claim_fails ccpid)
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/tests/casesreport-helper.sh"
casesreport "$B" title- "${cases[@]}" || exit 1
echo "ok [title]"
