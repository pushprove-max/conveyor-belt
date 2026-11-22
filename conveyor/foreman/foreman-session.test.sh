#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Foreman mode's session (foreman.sh, stop.sh, waiter.sh, lib.sh): the stop hooks, every issue the Foreman files held,
# a record command's pin and engine, the role marked by session (a claim, a fork, claims at once) and the start's line
# on an old engine. The other Foreman cases are in foreman.test.sh and foreman-projects.test.sh.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../tests/wait.sh"
. "$SRC/../lib/portable.sh"; p_tools
# Each case (t_<case>) runs side by side with the others, on a host of its own made by fixture in $B/<case> (T); a
# case that goes on from what another left (the Foreman set up, a name, a mark) makes that itself first.
B=$(mktemp -d)
# A waiter that delivers a wake leaves a waiter listening (waiter.sh handoff), which ends with the session's process:
# here a stand-in, ended with the test, and no child of it, so the wait for the cases below does not wait for it.
# unheld ends that waiter at once, where its stand-in watcher would go on putting wakes.
export CONVEYOR_FOREMAN_SESSION_PID; CONVEYOR_FOREMAN_SESSION_PID=$(sleep 600 > /dev/null 2>&1 & echo $!) # sleep: the stand-in for the session's process
trap 'kill $CONVEYOR_FOREMAN_SESSION_PID; rm -rf "$B"' EXIT
unheld() { kill "$(cut -d' ' -f1 "$FD/waiter.pid")" 2>/dev/null; flock -w 10 "$FD/waiter.lock" true; }
# Bug (issue 452): with no CONVEYOR_MAIN, the engine runs for the checkout of the folder it runs in (foreman/lib.sh,
# the git common dir). A draft of t_auto ran `foreman.sh claim a3a3a3a3-0000` in the folder the test was started
# from, a card's worktree, so the claim went to the real main checkout's conveyor/state/foreman. Every case runs
# from this temporary folder, in no checkout: an engine call that names no fixture checkout runs for none.
cd "$B" || exit 1
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
# What the Foreman's launcher exports (foreman.sh launch), and Claude Code's CLAUDE_PROJECT_DIR, name the real main
# checkout and its Foreman; the loop also runs with CONVEYOR_MAIN set (machine.sh), so its cards inherit it. A case
# that sets none of its own would run for that checkout: t_setup's launch (conveyor.sh foreman) would launch for it.
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CLAUDE_CODE_PROMPT_CACHE_TTL
# A claim opens the Board in the browser (board-open.test.sh, with a stub opener); here no claim may open a real one.
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
export CLAUDE_PLUGIN_ROOT=$SRC/../.. PLUGIN=$SRC/../..
PIN=0123456789abcdef0123456789abcdef01234567 PIN2=89abcdef0123456789abcdef0123456789abcdef
fixture() { # <case>
T=$B/$1
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate HOME=$T/home
mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME"
# Two project checkouts: alpha is the main checkout the Foreman runs in, beta another record of the same host.
for r in alpha beta; do
  git init -q "$T/$r" && mkdir -p "$T/$r/.conveyor" && jq -n --arg p "$PIN" '{plugin: {commit: $p}}' > "$T/$r/.conveyor/project.json"
done
# alpha and beta are linked (one group, foreman.groups), so they share one Foreman, whose folder (FD: its mark, state
# and wakes) is in alpha's state folder; the case projects (foreman-projects.test.sh) has a Foreman per project.
M=$T/alpha ST=$T/state FD=$T/state/foreman FH=$XDG_CONFIG_HOME/conveyor/filing/held
jq -n --arg s "$ST" --arg a "$M" --arg b "$T/beta" '{stateDir: $s, records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}],
  foreman: {groups: [["alpha", "beta"]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
# The pinned install is this checkout, so the hooks setup writes run through the real shim.
mkdir -p "$XDG_DATA_HOME/conveyor/versions" && ln -s "$(cd "$SRC/../.." && pwd -P)" "$XDG_DATA_HOME/conveyor/versions/$PIN"
}
# ready: the Foreman set up, and run as its launcher runs it (as the cases setup and launch, in foreman.test.sh, leave it).
ready() {
  CONVEYOR_MAIN=$M bash "$SRC/foreman.sh" setup > "$T/setup.out" 2>&1 || fail "setup failed: $(cat "$T/setup.out")"
  export CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_ASK="cat $T/ask/\$CONVEYOR_REPO"
}
# fileask: each record command is noted in $T/calls, and control says new issues start in the queue.
fileask() { export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO \$CONVEYOR_CMD\" >> $T/calls; [ \"\$CONVEYOR_CMD\" != control ] || echo '{\"start\":\"queue\"}'"; }

# A health record and a snapshot holding it, with the waiting and blocked issues given.
health() { # <waiting issues> <blocked issues> [<reason>]
  jq -cn --argjson w "$1" --argjson b "$2" --arg r "${3:-it changes the sign-in page}" '{time: "2026-11-11T12:00:00Z", loop: true, gh: true,
    state: "running", reason: null, stuck: [], pushError: null, pushFailingSince: null,
    waiting: [$w[] | {card: "c\(.)", issue: ., since: "2026-11-11T11:00:00Z", reason: $r}],
    blocked: [$b[] | {card: "c\(.)", issue: ., since: "2026-11-11T10:00:00Z", reason: $r}]}'
}
snap() { jq -cn --argjson h "$(health "$@")" '{health: $h, belt: [{card: "x"}], queue: {next: []}}'; }
# A hook's input for the session given: its id, how it started (startup) and its transcript.
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty'; } # the text a start's JSON output gives the session
sess() { jq -cn --arg s "$1" --arg src "${2:-startup}" --arg t "${3:-}" '{session_id: $s, source: $src, transcript_path: $t, stop_hook_active: false}'; }

t_state_stop() {
CASE=state-stop
ready
lines 6000 '- open' > "$FD/state.md"
out=$(echo '{"stop_hook_active": false}' | bash "$SRC/stop.sh" state)
jq -e '.decision == "block" and (.reason | test("6000 bytes"))' <<<"$out" >/dev/null || fail "a state over its cap did not block the stop: $out"
out=$(echo '{"stop_hook_active": true}' | bash "$SRC/stop.sh" state)
[ -z "$out" ] || fail "the second stop was blocked again: $out"
echo small > "$FD/state.md"
out=$(echo '{"stop_hook_active": false}' | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "a state under its cap blocked: $out"
out=$(echo '{"stop_hook_active": false}' | CONVEYOR_FOREMAN='' bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "another session was checked"
}

# Bug: the stop counted the '- DONE' items too, which the next start archives, so a state of open lines under the cap
# was refused for the DONE lines it carried.
t_state_stop_done() {
  local out
  ready
  { lines 4000 '- open'; lines 3000 '- DONE'; } > "$FD/state.md"
  out=$(echo '{"stop_hook_active": false}' | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "4000 open bytes and 3000 DONE bytes blocked the stop: $out"
  { lines 5100 '- open'; lines 3000 '- DONE'; } > "$FD/state.md"
  out=$(echo '{"stop_hook_active": false}' | bash "$SRC/stop.sh" state)
  jq -e '.decision == "block" and (.reason | test("5100 bytes of open lines"))' <<<"$out" >/dev/null || fail "5100 open bytes did not block with that size: $out"
  jq -e '.reason | test("begin the line of a finished item with .- DONE.")' <<<"$out" >/dev/null || fail "the block text for the input {\"stop_hook_active\": false} does not say the line must begin with - DONE: $out"
}
# Bug (issue 1218): finished items whose line ENDS with ' - DONE' were counted as open, so the cap blocked a stop for lines the
# next start archives.
t_state_stop_done_end() {
  local out
  ready
  { lines 4000 '- open'; lines 3000 '- shipped item' | sed 's/$/ - DONE/'; printf '  an indented line of it\n'; } > "$FD/state.md"
  out=$(echo '{"stop_hook_active": false}' | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "4000 open bytes and 3000 bytes of items ending ' - DONE' blocked the stop; the input was {\"stop_hook_active\": false}: $out"
}
# Bug: the stop kept its own copy of the cap, so a change of CAP in foreman.sh left the stop on the old one. The stop runs
# from a copy of the plugin with a changed CAP.
t_state_stop_cap() {
  local out
  ready
  mkdir -p "$T/copy/conveyor" && cp -R "$SRC" "$T/copy/conveyor/foreman" && cp -R "$SRC/../lib" "$T/copy/conveyor/lib"
  sed -i.bak 's/^CAP=5000 /CAP=7000 /' "$T/copy/conveyor/foreman/foreman.sh"
  grep -q '^CAP=7000 ' "$T/copy/conveyor/foreman/foreman.sh" || fail "the copy of foreman.sh has no CAP=7000"
  lines 6000 '- open' > "$FD/state.md"
  out=$(echo '{"stop_hook_active": false}' | bash "$SRC/stop.sh" state)
  jq -e '.decision == "block" and (.reason | test("5000-byte cap"))' <<<"$out" >/dev/null || fail "6000 open bytes under CAP=5000 did not block: $out"
  out=$(echo '{"stop_hook_active": false}' | bash "$T/copy/conveyor/foreman/stop.sh" state); [ -z "$out" ] || fail "6000 open bytes blocked under CAP=7000: $out"
  lines 8000 '- open' > "$FD/state.md"
  out=$(echo '{"stop_hook_active": false}' | bash "$T/copy/conveyor/foreman/stop.sh" state)
  jq -e '.decision == "block" and (.reason | test("7000-byte cap"))' <<<"$out" >/dev/null || fail "8000 open bytes under CAP=7000 did not block with that cap: $out"
}
# lines <bytes> <prefix>: that many bytes of 50-byte lines (49 characters and a newline), each starting with prefix.
lines() { local i l; for ((i = 0; i < $1 / 50; i++)); do l="$2 $i"; printf '%s%s\n' "$l" "$(head -c $((49 - ${#l})) /dev/zero | tr '\0' x)"; done; }

t_reply_stop() {
CASE=reply-stop
ready
turn() { # <uuid> <opening text> <reply>
  jq -cn --arg u "$1" --arg o "$2" --arg r "$3" '{type: "user", uuid: $u, message: {content: $o}}, {type: "assistant", message: {content: [{type: "text", text: $r}]}}' > "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t, stop_hook_active: true}' | bash "$SRC/stop.sh" reply
}
# Bug (#1292): any reply with a question mark was refused as a question to the owner, though a question mark also
# stands in a quote, a checklist or a code span. A question mark at a line's end, or in a line's middle with a space
# after it (what the old check refused), passes.
for r in 'Why is #7 red?' $'- Is #7 red?\n- Is #8 green?' 'The owner asked how do we get you to think better? Here is the answer: #7 is filed.' 'Run `grep a? file` to find #7.'; do
  out=$(turn "u1 $r" 'what now' "$r"); [ -z "$out" ] || fail "a reply with a question mark was refused (reply: $r): $out"
done
out=$(turn u2 'what now' 'Filed #9 and held it.'); [ -z "$out" ] || fail "a plain report was refused: $out"
out=$(turn u3 'what now' 'Want me to file it.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "undone work passed: $out"
out=$(turn u3b 'what now' 'I still need to file #9.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "work left undone passed: $out"
out=$(turn u3b 'what now' 'I still need to file #9.'); [ -z "$out" ] || fail "the same turn was refused twice (reply: I still need to file #9.): $out"
out=$(turn u3d 'what now' 'You still need to approve #7 because it changes the sign-in page.'); [ -z "$out" ] || fail "the owner's own decision was refused as unfinished work: $out"
# Bug (#362): an "I'll <verb>" tied to a later event or a standing rule was refused as undone work, costing a turn;
# a bare deferral is still refused.
for r in "When Conveyor sends its idle wake, I'll: pause the belt; write the 1.6.0 notes; run release-prep and the release" \
  "Until #361 lands, I'll check the health record directly for blocked cards on every wake" "When the queue empties, I'll release 1.6.0."; do
  out=$(turn "u3l $r" 'what now' "$r"); [ -z "$out" ] || fail "a future action tied to a later event was refused: $r: $out"
done
for r in "I'll file it." "I haven't filed it yet." "Released #9. I'll fix that next."; do
  out=$(turn "u3n $r" 'what now' "$r"); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "a bare deferral passed: $r: $out"
done
# A later event in one list item does not hide a bare deferral in the next item.
out=$(turn u3m 'what now' $'- When the queue empties, I\'ll release 1.6.0\n- I\'ll file it'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "a deferral in the next list item passed: $out"
# The whole final reply is checked, not only its last text block.
jq -cn '{type: "user", uuid: "u3e", message: {content: "what now"}}, {type: "assistant", message: {content: [{type: "text", text: "I still need to file #9."}, {type: "text", text: "Idle"}]}}' > "$T/t.jsonl"
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply)
jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "undone work in an earlier text block passed (replies: I still need to file #9. / Idle): $out"
# A long turn is still checked when its opening entry is over a thousand entries back.
{ jq -cn '{type: "user", uuid: "u3f", message: {content: "what now"}}'
  for _ in $(seq 1000); do echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}'; done
  jq -cn '{type: "assistant", message: {content: [{type: "text", text: "I still need to file #9."}]}}'; } > "$T/t.jsonl"
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply)
jq -e '.decision == "block"' <<<"$out" >/dev/null && [ "$(cat "$FD/reply-mark")" = u3f ] || fail "a long turn whose opening left the last thousand entries passed: $out"
printf 'Conveyor: alpha: blocked: #7\nalpha: #7 is blocked\n' > "$FD/last-wake.txt"
out=$(turn u4 'Stop hook feedback: Conveyor: alpha: blocked: #7' '#5 is still running, nothing needs you.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "play-by-play in a wake reply passed: $out"
out=$(turn u5 'Stop hook feedback: Conveyor: alpha: blocked: #7' 'Idle'); [ -z "$out" ] || fail "a one-word wake reply was refused: $out"
# Bug (#1228): the standing-yes rule needs the "Done without asking" line in the next reply, and a wake reply was
# refused for it as a report, so the Foreman kept one rule or the other. The line passes alone and beside a line that
# needs the owner; a report beside it is still refused; a line without the id is no such line.
done_line='Done without asking (review-followup): released #926 so its review could finish; logged as c20261121T1-s-1.'
out=$(turn u5a 'Stop hook feedback: Conveyor: alpha: blocked: #7' "$done_line"); [ -z "$out" ] || fail "wake reply [$done_line] was refused: $out"
owner_line='#7 needs your call: its fix changes the sign-in page.'
out=$(turn u5b 'Stop hook feedback: Conveyor: alpha: blocked: #7' "$done_line"$'\n'"$owner_line"); [ -z "$out" ] || fail "wake reply [$done_line + $owner_line] was refused: $out"
out=$(turn u5c 'Stop hook feedback: Conveyor: alpha: blocked: #7' "$done_line"$'\n''#12 landed successfully.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "wake reply [$done_line + '#12 landed successfully.'] passed: $out"
out=$(turn u5d 'Stop hook feedback: Conveyor: alpha: blocked: #7' 'Done without asking: #12 landed successfully.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "wake reply [Done without asking: #12 landed successfully.] passed: $out"
out=$(turn u6 'Stop hook feedback: Conveyor: alpha: blocked: #7' '#12 landed successfully.'); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "a report in a wake reply passed: $out"
out=$(turn u7 'Stop hook feedback: Conveyor: alpha: blocked: #7' '#7 needs your call: its fix changes the sign-in page.'); [ -z "$out" ] || fail "a wake reply naming what needs the owner was refused: $out"
# Bug (#139): a wake reply reporting a defect in Conveyor itself was refused as a status note, so the Foreman wrote
# Idle and the owner never saw it. A plugin-problem line passes, and is noted in plugin-bugs.md once.
bug='Plugin problem (for the conveyor-belt repo): setup never sets linkFromMain, so card c20261116T101500-alpha-7 has no packages; evidence ~/cards/c20261116T101500-alpha-7/test.log.'
out=$(turn u10 'Stop hook feedback: Conveyor: alpha: blocked: #7' "$bug"); [ -z "$out" ] || fail "a plugin-problem line in a wake reply was refused: $out"
[ "$(grep -c '^- ' "$FD/plugin-bugs.md" 2>/dev/null)" = 1 ] && grep -qE '^- [0-9T:-]+Z · card c20261116T101500-alpha-7 · setup never sets linkFromMain.* · evidence: ~/cards/c20261116T101500-alpha-7/test\.log$' "$FD/plugin-bugs.md" \
  || fail "the plugin problem was not noted with its time, card, finding and evidence: $(cat "$FD/plugin-bugs.md" 2>&1)"
# A status note beside it is still refused, the form named; the line said again is not noted twice.
out=$(turn u11 'Stop hook feedback: Conveyor: alpha: blocked: #7' "Released #926 so its review could finish."$'\n'"$bug")
jq -e '.decision == "block" and (.reason | contains("Plugin problem (for the conveyor-belt repo): <the command or step>, <what it did>, <what you expected>"))' <<<"$out" >/dev/null || fail "a status note beside a plugin problem passed: $out"
[ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 1 ] || fail "a plugin problem said again was noted twice: $(cat "$FD/plugin-bugs.md")"
# A finding in other words is refused, and told the form that keeps it.
out=$(turn u12 'Stop hook feedback: Conveyor: alpha: blocked: #7' 'The tests likely failed because Conveyor does not install packages in card worktrees, another plugin problem.')
jq -e '.decision == "block" and (.reason | contains("Plugin problem (for the conveyor-belt repo): <the command or step>, <what it did>, <what you expected>, card <card>, evidence <path>"))' <<<"$out" >/dev/null \
  || fail "a refused plugin finding was not told the form to use: $out"
# Only the owner can file a plugin problem, so "not filed yet" on its line is no unfinished work of the Foreman's; a
# finding that is part of one noted before is noted on its own.
out=$(turn u13 'what now' 'Plugin problem (for the conveyor-belt repo): setup never sets linkFromMain, not filed yet.'); [ -z "$out" ] || fail "a plugin problem not filed yet was refused as unfinished work: $out"
[ "$(grep -c '^- ' "$FD/plugin-bugs.md")" = 2 ] || fail "a shorter plugin problem was taken for one noted before: $(cat "$FD/plugin-bugs.md")"
# A wake delivered as a meta entry opens its own turn: its reply is checked as a wake reply, not as the owner's last message.
jq -cn '{type: "user", uuid: "u8", message: {content: "watch"}}, {type: "assistant", message: {content: [{type: "text", text: "Watching."}]}},
  {type: "user", uuid: "u8w", isMeta: true, message: {content: "Stop hook feedback: Conveyor: alpha: blocked: #7"}},
  {type: "assistant", message: {content: [{type: "text", text: "#12 landed successfully."}]}}' > "$T/t.jsonl"
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply)
jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "a report replying to a meta wake passed: $out"
# Bug (#243): the owner typed a request during a turn that began with a wake, and the report answering it was refused
# as a wake reply, so the Foreman wrote it twice. A message the owner types mid-turn (a queued_command entry of human
# origin) makes the reply an answer to the owner; a task notification queued mid-turn does not.
midturn() { # <uuid> <origin kind>
  jq -cn --arg u "$1" --arg k "$2" '{type: "user", uuid: $u, isMeta: true, message: {content: "Stop hook feedback: Conveyor: alpha: blocked: #7"}},
    {type: "assistant", message: {content: [{type: "tool_use", name: "Bash"}]}},
    {type: "attachment", attachment: {type: "queued_command", prompt: "file the bugs you found", origin: {kind: $k}}},
    {type: "user", message: {content: [{type: "tool_result", content: "ok"}]}},
    {type: "assistant", message: {content: [{type: "text", text: "Filed #31 and #32 in the conveyor-belt repo."}]}}' > "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply
}
out=$(midturn u14 human); [ -z "$out" ] || fail "the reply to the owner's mid-turn request was judged as a wake reply: $out"
out=$(midturn u15 task-notification); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "a report replying to a wake passed after a task notification: $out"
# Other meta entries still do not open a turn.
jq -cn '{type: "user", uuid: "u9", message: {content: "what now"}}, {type: "user", uuid: "u9m", isMeta: true, message: {content: "Caveat: example"}},
  {type: "assistant", message: {content: [{type: "text", text: "Should I file #9?"}]}}' > "$T/t.jsonl"
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t}' | bash "$SRC/stop.sh" reply)
jq -e '.decision == "block"' <<<"$out" >/dev/null && [ "$(cat "$FD/reply-mark")" = u9 ] || fail "a meta entry that is not a wake opened the turn: $out"
}

t_filing() {
CASE=filing
ready
# An issue the Foreman files is held from its first sight: before the command runs, every record starts new issues
# held; after it, each issue linked is held in its own record, and the records start new issues in the queue again.
: > "$T/calls"
fileask
cmd='conveyor.sh gh-write issue create --repo example/beta --title example --body example; gh issue create -R example/beta --title example --body example; gh issue create --title example --body example'
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
[ -z "$out" ] || fail "the filing command was refused: $out"
[ "$(grep -c 'control start held' "$T/calls")" = 2 ] || fail "not every record starts new issues held before the command runs: $(cat "$T/calls")"
: > "$T/calls"
# Issue 330: three issues filed in one command are all held, and each by `control adopt`, which leaves one the owner
# released before this hook ran released (startrule.test.sh t_startadopt), where `control hold` held it again.
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c},
  tool_response: {stdout: "https://github.com/example/beta/issues/12\nhttps://github.com/example/beta/issues/15\nhttps://github.com/example/alpha/issues/30\n", stderr: ""}}' \
  | bash "$SRC/foreman.sh" filed)
grep -qx 'beta control adopt 12 15' "$T/calls" && grep -qx 'alpha control adopt 30' "$T/calls" || fail "each issue filed is not held in its own record: $(cat "$T/calls")"
[ "$(grep -c 'control start queue' "$T/calls")" = 2 ] || fail "the records do not start new issues in the queue again: $(cat "$T/calls")"
[ "$(sed -n '$p' "$T/calls" | cut -d' ' -f2-)" = 'control start queue filed' ] || fail "the queue was set back before every issue was held: $(cat "$T/calls")"
jq -e '.hookSpecificOutput.additionalContext | test("#?12") and test("15") and test("30")' <<<"$out" >/dev/null || fail "the Foreman is not told what was held: $out"
# Issue 330: the Foreman is told as held only the issues the record holds after the adopt: one released already
# (#15) is named apart, not as held with a word to release it again.
in=$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c}, tool_response: {stdout: "https://github.com/example/beta/issues/12\nhttps://github.com/example/beta/issues/15\n"}}')
out=$(CONVEYOR_FOREMAN_ASK="[ \"\$CONVEYOR_CMD\" != 'control adopt 12 15' ] || echo '{\"held\":[3,12]}'" bash "$SRC/foreman.sh" filed <<<"$in")
jq -e '.hookSpecificOutput.additionalContext | test("Held in Conveyor \\(beta: 12\\)") and test("released already \\(beta: 15\\)")' <<<"$out" >/dev/null \
  || fail "a released issue was told to the Foreman as held: $out"
# Issue 330: a record whose engine has no `control adopt` (it pins an older one) refuses it as a usage error: the
# issues are held with `control hold` there, not reported as not held after GitHub filed them.
: > "$T/calls"
out=$(CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_CMD\" >> $T/calls; case \$CONVEYOR_CMD in 'control adopt'*) echo 'usage: conveyor.sh control [hold <issue>...]' >&2; exit 2 ;; 'control hold'*) echo '{\"held\":[12,15]}' ;; esac" \
  bash "$SRC/foreman.sh" filed <<<"$in")
grep -qx 'control hold 12 15' "$T/calls" && jq -e '.hookSpecificOutput.additionalContext | test("Held in Conveyor \\(beta: 12, 15\\)")' <<<"$out" >/dev/null \
  || fail "an older engine's record did not hold the issues filed: $out $(cat "$T/calls")"
# Nor does the Foreman start new issues in the queue again while the research lane's filer holds its turn: the filer,
# seeing them set held by the Foreman's filing, set nothing, and its issue is not yet held.
printf 'alpha\n' > "$FH"; : > "$T/calls"; mkdir -p "$T/state/lanes/research-filer"; mkfifo "$T/turn"
flock "$T/state/lanes/research-filer/filing.lock" sh -c "read x < '$T/turn'" & turn=$!
until flock -n "$T/state/lanes/research-filer/filing.lock" true; [ $? = 1 ]; do sleep 0.1; done
jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c}, tool_response: {stdout: "", stderr: ""}}' \
  | bash "$SRC/foreman.sh" filed > "$T/filed" 2>&1 & filed=$!
wait_until 'under "$filed" flock || ! kill -0 "$filed" 2>/dev/null' # it waits at the turn's lock, or has ended
! grep -q 'start queue' "$T/calls" || { echo go > "$T/turn"; fail "the Foreman started new issues in the queue again while the lane's filer held its turn: $(cat "$T/calls")"; }
echo go > "$T/turn"; wait "$turn"; wait "$filed"
[ "$(cat "$T/calls")" = 'alpha control start queue filed' ] && [ ! -s "$FH" ] \
  || fail "the Foreman did not start new issues in the queue again once the filer's turn was free: $(cat "$T/calls" "$T/filed")"
# A quoted subcommand files an issue just the same: it is held before and after.
cmd="gh issue 'create' --repo example/alpha --title example --body example"
: > "$T/calls"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
grep -q 'control start held' "$T/calls" || fail "a quoted filing command was not seen before it ran: $(cat "$T/calls")"
: > "$T/calls"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c}, tool_response: {stdout: "https://github.com/example/alpha/issues/31\n"}}' \
  | bash "$SRC/foreman.sh" filed)
grep -qx 'alpha control adopt 31' "$T/calls" || fail "a quoted filing command's issue was not held: $(cat "$T/calls")"
# A subcommand made by an expansion cannot be read, so it is held as filing; flags before the subcommand do not hide it.
# Another HTTP client (curl, wget, a script) files an issue on the issues list or GraphQL endpoint just as gh does, and
# whether it writes cannot be read: a script POSTs whenever it sends a body, a quoted `;` is no command break, and an
# escape (\u, \x, %) spells the endpoint or createIssue all the same. So naming either endpoint is held, and so is a
# request read from a file (a curl config, a wget input file) or made by an expansion.
bs='\'
for cmd in 'sub=create; gh issue "$sub" --title example --body example' 'gh issue ${sub} --title example' 'gh issue $(echo create) --title example' 'gh issue `echo new` --title example' \
  'sub=create; gh issue --repo example/alpha "$sub" --title example' 'gh issue -R example/alpha $sub' 'gh issue --repo=example/alpha $sub' \
  'gh issue --repo example/alpha create --title example' 'gh issue -R example/alpha new' \
  'noun=issue; sub=create; gh "$noun" "$sub" --title example --body example' 'gh -R example/alpha $noun $sub' 'conveyor.sh gh-write "$noun" create' \
  'repo=example/alpha; gh issue --repo "$repo" "$sub"' 'sub=create; gh issue -Rexample/alpha "$sub" --title example --body example' \
  'gh -Rexample/alpha issue $sub' 'gh -Rexample/alpha $noun create' 'gh api repos/example/alpha/issues -f title=example -f body=example' \
  "gh api graphql -f query='mutation { createIssue(input: {repositoryId: \"x\", title: \"example\"}) { issue { url } } }'" \
  'gh api graphql -F query=@reports/create.graphql' 'gh api graphql --input reports/create.json' 'gh api graphql -f query="$q"' \
  "curl --netrc -X POST https://api.github.com/repos/example/alpha/issues -H 'Content-Type: application/json' -d '{\"title\":\"example\"}'" \
  'wget --post-data=title=example "https://api.github.com/repos/$repo/issues"' 'curl -d @reports/create.json https://api.github.com/graphql' \
  "python3 -c 'import urllib.request as u; u.urlopen(u.Request(\"https://api.github.com/repos/example/alpha/issues\", b\"{}\", method=\"POST\"))'" \
  'curl --netrc --config reports/create.curl' 'curl --netrc -Kreports/create.curl' 'wget -i reports/urls.txt' 'curl -X POST "$url" -d @reports/create.json' \
  "curl --netrc https://api.github.com/repos/example/alpha/issues -H 'Content-Type: application/json; charset=utf-8' -d '{\"title\":\"example\"}'" \
  "python3 -c 'import urllib.request as u; u.urlopen(u.Request(\"https://api.github.com/repos/example/alpha/issues\", b\"{}\", headers={\"Authorization\":\"Bearer TOKEN\"}))'" \
  "curl --netrc https://api.github.com/graphql --json '{\"query\":\"mutation { create${bs}u0049ssue(input:{repositoryId:\\\"ID\\\",title:\\\"example\\\"}) { issue { id } } }\"}'" \
  "gh api graphql -f query='mutation { create${bs}u0049ssue(input: {repositoryId: \"x\", title: \"example\"}) { issue { url } } }'" \
  "python3 -c 'u.urlopen(\"https://api.github.com/repos/example/alpha/${bs}x69ssues\", b\"{}\")'" 'curl -d x https://api.github.com/repos/example/alpha/%69ssues' \
  'curl --netrc https://api.github.com/repos/example/alpha/issues' "curl --netrc https://api.github.com/graphql -d '{\"query\":\"{ viewer { login } }\"}'"; do
  : > "$T/calls"; : > "$FH"
  out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
  grep -q 'control start held' "$T/calls" || fail "a filing command was not seen before it ran ($cmd): $(cat "$T/calls")"
done
for cmd in 'gh issue view 7 --json "$f"' 'gh issue -R example/alpha view 7 --json "$f"' 'repo=example/alpha; gh issue --repo "$repo" view 7' \
  'gh issue -R $repo view 7' 'gh issue --repo=$repo view 7' 'gh --repo "$repo" issue view 7' 'gh issue -Rexample/alpha view 7' \
  'gh api repos/example/alpha/issues/7/comments' 'curl https://api.github.com/repos/example/alpha/issues/7' \
  'gh api graphql -f query="{ viewer { login } }"' 'cat docs/graphql.md' 'printf "%s\n" example'; do
  : > "$T/calls"; : > "$FH"
  out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
  [ ! -s "$T/calls" ] || fail "reading an issue was taken for filing ($cmd): $(cat "$T/calls")"
done
cmd="gh issue 'create' --repo example/alpha --title example --body example"
# Records that cannot be read hold nothing, so the filing command is refused, not run.
jq '.records = []' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && cp "$XDG_CONFIG_HOME/conveyor/host.json" "$T/h0" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}' | bash "$SRC/foreman.sh" filing)
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null || fail "filing ran with no record to hold its issue in: $out"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PostToolUse", tool_input: {command: $c}, tool_response: {stdout: "https://github.com/example/alpha/issues/32\n"}}' \
  | bash "$SRC/foreman.sh" filed)
jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "an issue filed with no record to hold it in was let pass: $out"
mv "$T/h0" "$XDG_CONFIG_HOME/conveyor/host.json"
# Issue 330: a filing command run in the background has its filed hook as it starts, so the records went back to the
# queue before its issues were filed, and its output linked none: none was held. It is refused, with nothing set.
: > "$T/calls"
out=$(jq -cn --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_input: {command: $c, run_in_background: true}}' | bash "$SRC/foreman.sh" filing)
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null && [ ! -s "$T/calls" ] \
  || fail "a filing command run in the background was not refused, or set records: $out $(cat "$T/calls")"
}

t_ask_pin() {
CASE=ask-pin
ready
# A record command runs the pinned install only when the pin is a full commit id: a pin that is a path (../escape)
# would run a conveyor.sh outside the versions folder.
mkdir -p "$T/gamma/.conveyor" "$XDG_DATA_HOME/conveyor/escape/conveyor" "$XDG_DATA_HOME/conveyor/versions/$PIN2/conveyor"
for d in escape "versions/$PIN2"; do printf '#!/usr/bin/env bash\necho "ran %s $*"\n' "$d" > "$XDG_DATA_HOME/conveyor/$d/conveyor/conveyor.sh"; done
jq -n --arg p "$PIN2" '{plugin: {commit: $p}}' > "$T/gamma/.conveyor/project.json"
askg() { env -u CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_DIR="$FD" bash -c '. "$1/lib.sh" && ask gamma "$2" health' _ "$SRC" "$T/gamma"; }
out=$(askg 2>&1)
[ "$out" = "ran versions/$PIN2 health" ] || fail "a full commit pin did not run its install: $out"
# Bug caught (#961): testissue run over ssh, or for another project of the group, could not see the Foreman's mark
# file, so the issue it filed was queued at once. ask adds the mark to testissue alone (the case clears the inherited
# one first): a card session would claim the role.
printf '#!/usr/bin/env bash\necho "$1 mark=${CONVEYOR_FOREMAN:-}"\n' > "$XDG_DATA_HOME/conveyor/versions/$PIN2/conveyor/conveyor.sh"
for c in testissue health; do out=$(env -u CONVEYOR_FOREMAN -u CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_DIR="$FD" bash -c '. "$1/lib.sh" && ask gamma "$2" "$3" x' _ "$SRC" "$T/gamma" "$c" 2>&1); echo "$out"; done > "$T/marks"
[ "$(cat "$T/marks")" = $'testissue mark=1\nhealth mark=' ] || fail "the Foreman's mark did not reach testissue alone: $(cat "$T/marks")"
for pin in ../escape "../escape/../versions/$PIN2" "${PIN2^^}" 7; do
  jq -n --arg p "$pin" '{plugin: {commit: $p}}' > "$T/gamma/.conveyor/project.json"
  out=$(askg 2>&1) \
    && fail "the pin $pin was accepted: $out"
  [[ $out != *ran* ]] || fail "the pin $pin ran a conveyor.sh: $out"
done
jq -n '{plugin: {commit: 7}}' > "$T/gamma/.conveyor/project.json"
askg > /dev/null 2>&1 && fail "a numeric pin was accepted"
}

t_ask_self() {
CASE=ask-self
ready
unset CONVEYOR_FOREMAN_ASK
# Bug caught (issue 40): a record whose pack has no plugin key (the plugin's own checkout, which runs the engine from
# itself) had no engine the Foreman could run, so it read as unreachable and its cards never woke the Foreman. alpha
# follows an install here; beta runs its own conveyor/conveyor.sh, with card 7 blocked.
mkdir -p "$XDG_DATA_HOME/conveyor/versions/$PIN2/conveyor" "$T/beta/conveyor"
jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" && jq -n --arg c "$PIN2" '{commit: $c}' > "$M/.git/conveyor-engine.json"
jq 'del(.plugin)' "$T/beta/.conveyor/project.json" > "$T/p" && mv "$T/p" "$T/beta/.conveyor/project.json"
belt() { jq -c --argjson i "$1" --arg t "$2" '.belt = [{card: "c\($i)", issue: $i, step: "build", title: $t}]'; }
snap '[]' '[]' | belt 5 "an alpha page" > "$T/snap-alpha"; snap '[]' '[7]' | belt 8 "a beta page" > "$T/snap-beta"
for e in "$XDG_DATA_HOME/conveyor/versions/$PIN2:alpha" "$T/beta:beta"; do
  printf '#!/usr/bin/env bash\n[ "$1" = snapshot ] && cat %q\n' "$T/snap-${e##*:}" > "${e%:*}/conveyor/conveyor.sh"
done
out=$(cd "$M" && bash "$SRC/../conveyor.sh" foreman status 2>&1)
grep -qxF "alpha: 1 on the belt" <<<"$out" && grep -qF "#5 build" <<<"$out" || fail "status did not read the record that follows an install: $out"
grep -qxF "beta: 1 on the belt" <<<"$out" && grep -qF "#8 build" <<<"$out" || fail "status did not read the record that runs its own engine: $out"
bash "$SRC/watch-conveyor.sh" --once || fail "no wake for the blocked card of the record that runs its own engine"
grep -qF "beta: #7 is blocked" "$FD"/pending/*.wake || fail "the wake does not name beta's blocked card: $(cat "$FD"/pending/*.wake)"
}

# ada: the Foreman named Ada (as launch names it), each record command noted, and no CONVEYOR_FOREMAN. The cases session,
# session_fork and session_claims start from it and run side by side.
ada() {
ready; fileask
jq '.foreman.name = "Ada"' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json"
unset CONVEYOR_FOREMAN
rm -f "$FD"/pending/*.wake
}
big() { head -c 6000 /dev/zero | tr '\0' x > "$FD/state.md"; }
t_session() {
CASE=session
# The Foreman is marked by session, not by environment: a session started with no CONVEYOR_FOREMAN (claude
# --continue, an IDE) is the Foreman when /conveyor-belt:foreman marked it, and only then. Losing the mark silently
# left a Foreman running for hours with no alert.
ada
big; out=$(sess s1 | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "an unmarked session ran the Foreman's stop hook: $out"
out=$(bash "$SRC/foreman.sh" claim s1) || fail "the claim failed: $out"
[ "$(head -n 1 <<<"$out")" = "This session is now the Foreman (Ada): its watchers start at the end of this turn." ] || fail "the claim does not say so in one line: $out"
grep -qF 'Foreman mode: you are Ada' <<<"$out" || fail "the claiming session got no Foreman rules: $out"
out=$(sess s1 | bash "$SRC/stop.sh" state); jq -e '.decision == "block"' <<<"$out" >/dev/null || fail "the marked session did not run the Foreman's stop hook: $out"
out=$(sess s2 | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "a session that is not marked ran the Foreman's stop hook: $out"
echo small > "$FD/state.md"
# Continued or resumed with the same id, it is still the Foreman: its start gives it its rules.
out=$(sess s1 resume | bash "$SRC/foreman.sh" start | ctx); grep -qF 'Foreman mode: you are Ada' <<<"$out" || fail "the resumed Foreman got no Foreman start: $out"
out=$(sess s2 startup | bash "$SRC/foreman.sh" start); [ -z "$out" ] || fail "another session got the Foreman's start: $out"
# A claim from a second session moves the mark, and the first session's waiter and its watchers exit at once.
# The waiter's output goes through cat, which ends only once nothing the waiter started holds it open.
rm -f "$FD/waiter.pid"
# The watcher is slow to stop on TERM: the claim still returns only once it is gone.
sess s1 | CONVEYOR_FOREMAN_WATCHERS="trap 'sleep 1; exit' TERM; echo \$\$ > $T/w1; while :; do sleep 1; done" bash "$SRC/waiter.sh" 2>&1 | cat > "$T/wout" & cp=$! # sleep: the 1 s the stand-in watcher takes to stop, ten of the waiter's 0.1 s checks
wait_until '[ -s "$FD/waiter.pid" ] && [ -s "$T/w1" ] || ! kill -0 "$cp" 2>/dev/null'
[ -s "$T/w1" ] || fail "the Foreman's waiter did not start its watchers"
wp=$(cut -d' ' -f1 "$FD/waiter.pid")
bash "$SRC/foreman.sh" claim s2 > /dev/null || fail "the second claim failed"
[ "$(cut -d' ' -f1 "$FD/session")" = s2 ] || fail "the second claim did not move the mark: $(cat "$FD/session")"
kill -0 "$wp" 2>/dev/null && { kill "$wp"; fail "the first session's waiter still runs after the role moved"; }
kill -0 "$(cat "$T/w1")" 2>/dev/null && fail "the first session's watcher still ran when the claim returned"
wait_until '! kill -0 "$cp" 2>/dev/null'
kill -0 "$cp" 2>/dev/null && fail "something the first session's waiter started still runs after the role moved"
[ ! -s "$T/wout" ] || fail "the first session's waiter woke its session when the role moved: $(cat "$T/wout")"
kill -0 "$(cat "$T/w1")" 2>/dev/null && fail "the first session's watcher still runs after the role moved"
rm -f "$T/w1"; out=$(sess s1 | CONVEYOR_FOREMAN_WATCHERS="echo \$\$ > $T/w1" bash "$SRC/waiter.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/w1" ] || fail "the first session's waiter started watchers at its next stop (exit $rc): $out"
out=$(sess s2 | CONVEYOR_FOREMAN_WATCHERS=". $SRC/lib.sh && echo 'Alert: moved' | pending_put" bash "$SRC/waiter.sh" 2>&1 >/dev/null); rc=$?
[ "$rc" = 2 ] && [ "$out" = 'Alert: moved' ] || fail "the new Foreman's waiter did not run its watchers (exit $rc): $out"
unheld
out=$(sess s1 resume | bash "$SRC/foreman.sh" start)
# Plain stdout at SessionStart reaches only Claude: the owner sees the line only as the systemMessage.
[ "$(wc -l <<<"$out")" = 1 ] && jq -e '.systemMessage | contains("no longer the Foreman")' <<<"$out" >/dev/null \
  || fail "the former Foreman's owner was not shown one line at its start: $out"
out=$(sess s1 resume | bash "$SRC/foreman.sh" start); [ -z "$out" ] || fail "the former Foreman was told twice: $out"
}

t_session_fork() {
CASE=session-fork
ada
bash "$SRC/foreman.sh" claim s2 > /dev/null || fail "the claim for s2 failed"
# A fork (--fork-session: source fork, a new id) keeps the role when its transcript is the Foreman's.
jq -cn '{type: "user", sessionId: "s3", forkedFrom: {sessionId: "s2", messageUuid: "u1"}, message: {content: "watch"}}' > "$T/fork.jsonl"
out=$(sess s3 fork "$T/fork.jsonl" | bash "$SRC/foreman.sh" start | ctx)
[ "$(cut -d' ' -f1 "$FD/session")" = s3 ] && grep -qF 'Foreman mode: you are Ada' <<<"$out" || fail "a fork of the Foreman lost the role: $(cat "$FD/session") $out"
jq -cn '{type: "user", sessionId: "s4", message: {content: "watch"}}' > "$T/other.jsonl"
jq -cn '{type: "user", sessionId: "s5", forkedFrom: {sessionId: "s3", messageUuid: "u2"}, message: {content: "watch"}}' > "$T/fork2.jsonl"
sess s4 resume "$T/other.jsonl" | bash "$SRC/foreman.sh" start > /dev/null
[ "$(cut -d' ' -f1 "$FD/session")" = s3 ] || fail "resuming another session took the role"
# A fork that lost the role gets it back only by a claim: resuming it, its transcript still copied from the claimant,
# tells it the role moved, or two sessions would each take the role from the other.
bash "$SRC/foreman.sh" claim s2 > /dev/null || fail "the claim back to s2 failed"
out=$(sess s3 resume "$T/fork.jsonl" | bash "$SRC/foreman.sh" start)
[ "$(cut -d' ' -f1 "$FD/session")" = s2 ] && jq -e '.systemMessage | contains("no longer the Foreman")' <<<"$out" >/dev/null \
  || fail "a displaced fork took the role back by a resume: $(cat "$FD/session") $out"
out=$(sess s3 resume "$T/fork.jsonl" | bash "$SRC/foreman.sh" start)
[ "$(cut -d' ' -f1 "$FD/session")" = s2 ] && [ -z "$out" ] || fail "a displaced fork, once told, took the role back by a resume: $(cat "$FD/session") $out"
bash "$SRC/foreman.sh" claim s3 > /dev/null || fail "the claim back to s3 failed"
# A resume that waits on the claim lock while off runs reads the mark only once it holds the lock: it never undoes off.
exec 8>>"$FD/claim.lock"; flock 8
sess s5 fork "$T/fork2.jsonl" | bash "$SRC/foreman.sh" start > /dev/null & rp=$!
wait_until 'under "$rp" flock || ! kill -0 "$rp" 2>/dev/null' # it waits at the claim lock, or has ended
: > "$FD/session"; flock -u 8; exec 8>&-
wait "$rp"
[ ! -s "$FD/session" ] || fail "a resume that waited on the lock undid off: $(cat "$FD/session")"
bash "$SRC/foreman.sh" claim s3 > /dev/null || fail "the claim back to s3 after the resume failed"
# off clears the mark, and the launcher's environment does not bring it back.
out=$(bash "$SRC/foreman.sh" off) && [ ! -s "$FD/session" ] || fail "off did not clear the mark: $out"
big
out=$(sess s3 | bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "the Foreman's hooks ran after off: $out"
out=$(sess s3 | CONVEYOR_FOREMAN=1 bash "$SRC/stop.sh" state); [ -z "$out" ] || fail "the launcher's environment overrode off: $out"
# Nor does the launcher's session start again by /clear or a compaction: only a fresh launch marks it.
for src in clear compact resume; do
  sess s3 "$src" | CONVEYOR_FOREMAN=1 bash "$SRC/foreman.sh" start > /dev/null
  [ ! -s "$FD/session" ] || fail "the launcher's session took the role back on a $src start after off: $(cat "$FD/session")"
done
# The launcher marks its own session at its start.
echo small > "$FD/state.md"
out=$(sess s5 startup | CONVEYOR_FOREMAN=1 bash "$SRC/foreman.sh" start | ctx)
[ "$(cut -d' ' -f1 "$FD/session")" = s5 ] && grep -qF 'Foreman mode: you are Ada' <<<"$out" || fail "the launcher did not mark its session: $(cat "$FD/session")"
# One Foreman per group: a claim in the checkout of another project of the group (its own state folder) moves the
# group's mark, kept in the first-named project's folder.
out=$(cd "$T/beta" && env -u CONVEYOR_FOREMAN_DIR -u CONVEYOR_MAIN bash "$SRC/foreman.sh" claim s6) || fail "the claim in beta failed: $out"
[ "$(cut -d' ' -f1 "$FD/session")" = s6 ] || fail "a claim in another checkout of the group did not move the group's mark: $(cat "$FD/session")"
[ ! -e "$T/beta/conveyor/state/foreman/session" ] || fail "a claim in beta kept a mark of its own outside the group's folder"
out=$(sess s5 | CONVEYOR_FOREMAN_WATCHERS="echo \$\$ > $T/w5" bash "$SRC/waiter.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/w5" ] || fail "a Foreman in another checkout still started its watchers (exit $rc): $out"
}

t_session_claims() {
CASE=session-claims
ada
bash "$SRC/foreman.sh" claim s6 > /dev/null || fail "the claim for s6 failed"
# Claims at once each keep their own mark and former: every one succeeds, the mark is one of them, and every other
# is told at its next start.
pids=(); for i in $(seq 7 16); do bash "$SRC/foreman.sh" claim "c$i" > "$T/claim.$i" 2>&1 & pids+=($!); done
for p in "${pids[@]}"; do wait "$p" || fail "a claim made at the same time as others failed: $(cat "$T"/claim.*)"; done
win=$(cut -d' ' -f1 "$FD/session")
[[ $win =~ ^c([7-9]|1[0-6])$ ]] || fail "claims at once left the mark wrong: $(cat "$FD/session")"
for i in $(seq 7 16); do
  [ "c$i" = "$win" ] && { grep -qxF "c$i" "$FD/former" && fail "the Foreman is listed as former"; continue; }
  grep -qxF "c$i" "$FD/former" || fail "c$i, displaced by claims at once, is not told: $(cat "$FD/former")"
done
grep -qxF s6 "$FD/former" || fail "the Foreman before the claims at once is not told: $(cat "$FD/former")"
# A session started without the launcher (no CONVEYOR_MAIN) still wakes on an awaited issue landing in its checkout.
rm -f "$FD"/pending/*.wake; echo 40 >> "$FD/await-alpha.txt"
mkdir -p "$T/ask"; snap '[12,15,16,17,18]' '[7,8]' | jq -c '.pushedCards = [{issue: 40}]' > "$T/ask/alpha"; snap '[19]' '[]' > "$T/ask/beta"
(cd "$M" && env -u CONVEYOR_MAIN -u CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK="cat $T/ask/\$CONVEYOR_REPO" bash "$SRC/watch-conveyor.sh" --once) || fail "no wake for an awaited issue landing without the launcher"
grep -qF 'alpha: #40 landed' "$FD"/pending/*.wake || fail "the awaited issue's landing was not named: $(cat "$FD"/pending/*.wake)"
}

t_stale() {
CASE=stale
# Bug caught (issue 179): a project that follows main stayed on an old engine for hours, its background take failing,
# and the Foreman's start said nothing. alpha runs PIN2; the last take read PIN and failed.
ready; fileask; unset CONVEYOR_FOREMAN
jq '.plugin = {follow: "main"}' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json"
jq -n --arg c "$PIN2" --arg h "$PIN" '{commit: $c, taken: [$c], head: {commit: $h, name: "main"}}' > "$M/.git/conveyor-engine.json"
printf '%s\n' '{"time":"2026-11-16T05:10:00Z","by":"x","exit":0,"output":""}' '{"time":"2026-11-16T06:10:00Z","by":"x","exit":1,"output":"conveyor: the plugin'"'"'s main could not be read from its remote\n"}' > "$M/.git/conveyor-engine.log"
bash "$SRC/foreman.sh" claim s1 > /dev/null || fail "the claim failed"
out=$(sess s1 resume | bash "$SRC/foreman.sh" start | ctx)
[ "$(grep -c 'old engine' <<<"$out")" = 1 ] && grep -qxF "# WARNING: Conveyor runs an old engine here: commit ${PIN2:0:7}, and the plugin's main is at ${PIN:0:7} · last take that worked: 2026-11-16T05:10:00Z · last failure: conveyor: the plugin's main could not be read from its remote · to take it, run: cd $M && bash $(cd "$SRC/.." && pwd -P)/conveyor.sh take" <<<"$out" \
  || fail "the Foreman's start does not give one line naming the old engine and why: $out"
# Once the newest commit read is the one it runs, the line goes.
jq -n --arg c "$PIN2" '{commit: $c, taken: [$c], head: {commit: $c, name: "main"}}' > "$M/.git/conveyor-engine.json"
out=$(sess s1 resume | bash "$SRC/foreman.sh" start | ctx); [[ $out != *'old engine'* ]] || fail "the Foreman's start names an old engine on the newest commit: $out"
}

# Every case at once, each in a subshell on its own fixture; each one's output is shown once all have ended, and the
# test passes only when each case ran to its end.
cases=(state_stop state_stop_done state_stop_done_end state_stop_cap reply_stop filing ask_pin ask_self session session_fork session_claims stale)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for one_case in $SEL; do case " ${cases[*]} " in *" $one_case "*) ;; *) echo "unknown case $one_case" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
# (A case's own variables, as its loops' c, are its own: the case's name is in one none of them uses.)
for one_case in "${cases[@]}"; do
  (CASE=${one_case//_/-}; fixture "$one_case"; "t_$one_case"; : > "$B/$one_case.passed") > "$B/$one_case.out" 2>&1 &
done
wait
bad=0
for one_case in "${cases[@]}"; do
  cat "$B/$one_case.out" >&2
  [ -e "$B/$one_case.passed" ] || { bad=1; [ -s "$B/$one_case.out" ] || echo "FAIL [${one_case//_/-}]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
