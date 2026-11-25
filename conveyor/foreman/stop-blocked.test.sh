#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's reply stop hook (stop.sh reply) and a wake that names a card "not yet reported: blocked".
# Bug caught (#1665): a blocked card sat under Needs you for 45 minutes while the Foreman replied "Idle" to four wakes
# about it, as the hook judged a wake reply by its words alone. Now the stop is refused, at every stop, until an act
# naming the card was logged in a ruling log since it blocked, the turn asked the owner about it, or its record no
# longer holds it blocked.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
export ENG=$SRC/../conveyor.sh
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CONVEYOR_RULING_LOG
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
# The block time: before any act the case logs now, after the row t_fake writes.
SINCE=2026-01-01T00:00:00Z
# The wake: alpha's #7 and main-red card, and beta's #7, each not yet reported, with its card id (watch-conveyor.sh
# unreported).
WAKE=$'Conveyor: alpha: blocked: #7\nalpha: not yet reported: blocked #7 (card c7)\nalpha: not yet reported: blocked Main is red (d0758b25165b) (card c20261124T215417-alpha-0)\nbeta: not yet reported: blocked #7 (card b7)'
ALL=$(jq -cn --arg s "$SINCE" '{alpha: [{card: "c7", issue: 7, since: $s}, {card: "c20261124T215417-alpha-0", name: "Main is red (d0758b25165b)", since: $s}],
  beta: [{card: "b7", issue: 7, since: $s}]}')
# The engine both records pin on the build host, an engine older than this hook: every command of it is refused, as
# such an engine has none that prints the acts. It keeps the ruling log's own reader (.claude/hooks/lib/rulings.sh,
# the same rulings_log in that engine), which names the log its `auto act` writes.
PIN=b97f8d451dbb65e6fe0e6a03e9c55bf5de820db3
mkdir -p "$B/old/conveyor" && ln -s "$SRC/../../.claude" "$B/old/.claude" \
  && printf '%s\n' 'echo "usage: conveyor.sh <command>" >&2; exit 2' > "$B/old/conveyor/conveyor.sh" || exit 1
# fixture <case> <each record's blocked list, as {<repo>: [...]}>: a Foreman of its own in $B/<case> (T, its folder
# FD, whose ruling log is $FD/rulings.jsonl) watching the group of the records alpha and beta, each a git checkout
# whose pack turns fixed-block on and pins $PIN, its origin the GitHub repository example/<repo>. The host file names an ssh target, the build host: the fake ssh on
# PATH runs each command on this machine as the host would, with its own data folder (the pinned engine) and its
# Foreman folder $T/host, whose ruling log only a read on the host finds; a path under $T/away there is the one under
# $T/there here, a checkout only the host has. health (the tests' ask seam) gives the
# record's blocked list; any other ask fails. A case logs an act on the host by running the engine on the record's
# main with the host's folder, as `foreman.sh ask <repo> auto act` does there (the pinned engine writes the same row).
fixture() {
  CASE=$1 T=$B/$1
  export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate HOME=$T/home CONVEYOR_FOREMAN=1 \
    CONVEYOR_FOREMAN_DIR=$T/fd CONVEYOR_MAIN=$T/alpha PATH=$T/bin:$PATH
  FD=$CONVEYOR_FOREMAN_DIR
  local r
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$FD" "$T/bin" "$T/remote/conveyor/versions" || exit 1
  ln -s "$B/old" "$T/remote/conveyor/versions/$PIN" || exit 1
  for r in alpha beta; do
    git init -q "$T/$r" && mkdir -p "$T/$r/.conveyor" \
      && jq --arg p "$PIN" '.plugin = {commit: $p} | .auto.standing = ["fixed-block"]' "$SRC/../lib/test-pack.json" > "$T/$r/.conveyor/project.json" \
      && git -C "$T/$r" remote add origin "https://github.com/example/$r.git" \
      && jq -cn --argjson b "$2" --arg r "$r" '{blocked: ($b[$r] // [])}' > "$T/health-$r" || exit 1
  done
  jq -n --arg t "$T" '{ssh: "buildhost", foreman: {groups: [["alpha", "beta"]]},
    records: [{repo: "alpha", main: "\($t)/alpha"}, {repo: "beta", main: "\($t)/beta"}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  # ssh's last argument is the command run on the host; the host's environment is its own, not this machine's.
  printf '#!/usr/bin/env bash\nc=${!#} a=%q b=%q\nXDG_DATA_HOME=%q CONVEYOR_FOREMAN_DIR=%q exec bash -c "${c//"$a"/"$b"}"\n' "$T/away" "$T/there" "$T/remote" "$T/host" > "$T/bin/ssh" \
    && chmod +x "$T/bin/ssh" || exit 1
  export CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_CMD in health) cat $T/health-\$CONVEYOR_REPO ;; *) exit 3 ;; esac"
  printf '%s\n' "$WAKE" > "$FD/last-wake.txt"
}
# hostact <repo> <what>: an act under fixed-block, logged in the host's ruling log.
hostact() {
  local out
  out=$(cd "$T/$1" && CONVEYOR_MAIN=$T/$1 CONVEYOR_FOREMAN_DIR=$T/host bash "$ENG" auto act fixed-block "$2" 2>&1) \
    && grep -q '^Done without asking (fixed-block): ' <<<"$out" || fail "auto act fixed-block did not log $1's act [$2] on the host: $out"
}
# stop <entries after the opening, JSON lines>: the transcript is an owner's turn, then the wake's turn as Claude Code
# writes it (the waiter's wake is a meta entry), then those entries; prints what stop.sh reply gives.
stop() {
  { jq -cn '{type: "user", uuid: "u0", message: {content: "watch"}}, {type: "assistant", message: {content: [{type: "text", text: "Watching."}]}}'
    jq -cn --arg w "$WAKE" '{type: "user", uuid: "u1", isMeta: true, message: {content: ("Stop hook feedback: " + $w)}}'; printf '%s\n' "$1"; } > "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t, stop_hook_active: false}' | bash "$SRC/stop.sh" reply
}
# again <what the refused stop gave> <entries>: the same turn's next stop, as Claude Code writes it: the refusal's
# reason as a meta entry after the reply, then those entries.
again() {
  { jq -cn --arg r "$(jq -r .reason <<<"$1")" '{type: "user", isMeta: true, message: {content: ("Stop hook feedback:\n" + $r)}}'; printf '%s\n' "$2"; } >> "$T/t.jsonl"
  jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t, stop_hook_active: true}' | bash "$SRC/stop.sh" reply
}
say() { jq -cn --arg r "$1" '{type: "assistant", message: {content: [{type: "text", text: $r}]}}'; } # <reply text>
# ask <question>...: one AskUserQuestion of those questions, and the owner's answer.
ask() {
  jq -cn --arg id "q$RANDOM$RANDOM" '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "AskUserQuestion",
    input: {questions: [$ARGS.positional[] | {question: ., options: [{label: "Retry"}, {label: "Leave it"}]}]}}]}},
    {type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, content: "User has answered your questions: Retry"}]}}' --args "$@"
}
# denied <question>: one AskUserQuestion that a hook denied (hooks/auto.tsx, auto on in full), as Claude Code writes it.
denied() {
  jq -cn --arg q "$1" --arg id "d$RANDOM$RANDOM" '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "AskUserQuestion",
    input: {questions: [{question: $q, options: [{label: "Retry"}, {label: "Leave it"}]}]}}]}},
    {type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, is_error: true,
      content: "auto is on: the owner is away. Decide this yourself by the auto rules, log it with its why, and do not ask."}]}}'
}
refused() { jq -e '.decision == "block"' <<<"$1" > /dev/null 2>&1; }
# Idle, and a plan in prose, with each card still blocked: refused, at the second stop too (stop_hook_active), naming each.
t_idle() {
fixture idle "$ALL"
local r out
for r in Idle 'I will retry alpha #7 after #9 lands.'; do
  out=$(stop "$(say "$r")")
  { refused "$out" && grep -qF 'alpha: not yet reported: blocked #7' <<<"$out" && grep -qF 'blocked Main is red (d0758b25165b) (card c20261124T215417-alpha-0)' <<<"$out" \
    && grep -qF 'beta: not yet reported: blocked #7' <<<"$out"; } || fail "wake [$WAKE], reply [$r], each card blocked in health: the stop was not refused naming each: $out"
  out=$(again "$out" "$(say "$r")"); refused "$out" || fail "wake [$WAKE], reply [$r], at the second stop (stop_hook_active): the stop passed: $out"
done
}

# An act logged with `auto act` since the card blocked lets its Idle pass, though the act was taken in an earlier turn
# and this turn holds no trace of it: alpha's and beta's #7 read from the build host's ruling log, the main-red card's
# from this Foreman's own. Bugs caught: only this turn's transcript was read, so an act logged before the wake did not
# count; the host's acts were asked of the engine the record pins, so an act logged on a host whose engine has no
# command to print them never counted; and an act logged after the card blocked but before the wake was put (beta's,
# its row dated between the two) must count, as the block time, not the wake's, is where acts count from.
t_act() {
fixture act "$ALL"
local out
hostact alpha "retried alpha #7 and #9"
mkdir -p "$T/host" && jq -cn '{id: "r-b", utc: "2026-06-01T00:00:00Z", source: "standing", kind: "fixed-block", question: null,
  answer: "retried beta #7", pick: "standing"}' >> "$T/host/rulings.jsonl" || exit 1
out=$(cd "$T/alpha" && CONVEYOR_MAIN=$T/alpha bash "$ENG" auto act fixed-block "retried c20261124T215417-alpha-0" 2>&1) && [ -s "$FD/rulings.jsonl" ] \
  || fail "auto act for the main-red card did not log the act in $FD/rulings.jsonl: $out"
out=$(stop "$(say Idle)"); [ -z "$out" ] || fail "wake [$WAKE], acts logged naming alpha #7 and beta #7 (before the wake, after the block) on the host and c20261124T215417-alpha-0 here, reply Idle: the stop was refused: $out"
}

# No act for alpha's cards: a receipt line a command echoes (its command holds `auto act` too), a row of the ruling log
# written before the cards blocked, a row since then marked void (here and on the host), and an act logged since for
# beta's #7 that names alpha apart leave alpha's cards refused; beta's act lets beta's card go. Bugs caught: a receipt a
# Bash command printed was taken for an act, so `echo` cleared the gate; a voided act still cleared it; and an act
# naming another project's #7 and this project apart cleared this project's #7.
t_fake() {
fixture fake "$ALL"
local rcpt='Done without asking (fixed-block): retried alpha #7 for Main is red (d0758b25165b); logged as fake.' e out f
jq -cn '{id: "r-1", utc: "2025-12-31T23:59:59Z", source: "standing", kind: "fixed-block", question: null,
  answer: "retried alpha #7 for Main is red (d0758b25165b)", pick: "standing"}' > "$FD/rulings.jsonl"
mkdir -p "$T/host" || exit 1
for f in "$FD/rulings.jsonl" "$T/host/rulings.jsonl"; do
  jq -cn '{id: "r-2", utc: "2026-06-01T00:00:00Z", source: "standing", kind: "fixed-block", question: null,
    answer: "retried alpha #7 for Main is red (d0758b25165b)", pick: "standing", void: true}' >> "$f" || exit 1
done
hostact beta "retried beta issue #7 before checking alpha"
e=$(jq -cn --arg c "echo '$rcpt' # auto act fixed-block" '{type: "assistant", message: {content: [{type: "tool_use", id: "a1", name: "Bash", input: {command: $c}}]}}'
  jq -cn --arg o "$rcpt" '{type: "user", message: {content: [{type: "tool_result", tool_use_id: "a1", content: $o}]}}'; say "$rcpt")
out=$(stop "$e")
{ refused "$out" && grep -qF 'alpha: not yet reported: blocked #7' <<<"$out" && grep -qF 'blocked Main is red' <<<"$out" && ! grep -qF 'beta: not yet reported' <<<"$out"; } \
  || fail "wake [$WAKE], an echoed receipt, a ruling row from before the block ($SINCE), voided rows and an act [retried beta issue #7 before checking alpha], reply [$rcpt]: the stop was not refused for alpha's cards alone: $out"
}

# A question names a card by its id, or by its project and issue together (its issue link too): only that card passes.
# A picker a hook denied (auto on in full) names both alpha cards and clears neither. Then a picker asked after the
# refusal, at the turn's next stop, lets the stop pass. Bugs caught: a denied picker, which never reached the owner,
# cleared the cards it named; a question about
# beta's #7 cleared alpha's #7 too (the match was on #7, then on alpha and #7 anywhere in it); one naming beta's #7 by
# its link cleared nothing; a card's name cleared it, though another card can have that name; one naming an issue's
# card by its id cleared nothing.
t_ask() {
fixture ask "$ALL"
local q1='Should I retry https://github.com/example/beta/issues/7?' q2='Should I retry #7 before checking alpha?' \
  q3='Should I retry Main is red (d0758b25165b)?' q4='Should I retry alpha #7 and c20261124T215417-alpha-0?' out
out=$(stop "$(ask "$q1" "$q2" "$q3")"$'\n'"$(denied "$q4")"$'\n'"$(say Idle)")
{ refused "$out" && grep -qF 'alpha: not yet reported: blocked #7' <<<"$out" && grep -qF 'blocked Main is red' <<<"$out" && ! grep -qF 'beta: not yet reported' <<<"$out"; } \
  || fail "wake [$WAKE], questions [$q1], [$q2], [$q3] answered, [$q4] denied by a hook, reply Idle: the stop was not refused for alpha's cards alone: $out"
q1='Should I retry card c7?' q2='Should I retry c20261124T215417-alpha-0?'
out=$(again "$out" "$(ask "$q1" "$q2")"$'\n'"$(say Idle)")
[ -z "$out" ] || fail "wake [$WAKE], refused once, then questions [$q1], [$q2], reply Idle: the stop was refused: $out"
}

# A card's own first wake names it "<repo>: <ref> is blocked since <time>: <why>" (watch-conveyor.sh record), with no
# "not yet reported" line: Idle is refused naming each card, and a question naming each (alpha #7 by health's card c7,
# the main-red card by the id its line gives) lets it pass. Bug caught: only "not yet reported" lines were read, so an
# Idle reply to a card's first wake passed.
t_first() {
local WAKE=$'Conveyor: alpha: blocked: #7\nalpha: #7 is blocked since 2026-01-01T00:00:00Z: tests failed (as of 00:05Z)\nalpha: Main is red (d0758b25165b) (card c20261124T215417-alpha-0) is blocked since 2026-01-01T00:00:00Z: the main is red'
fixture first "$ALL"
local q1='Should I retry card c7?' q2='Should I retry c20261124T215417-alpha-0?' out
out=$(stop "$(say Idle)")
{ refused "$out" && grep -qF 'alpha: not yet reported: blocked #7' <<<"$out" && grep -qF 'blocked Main is red (d0758b25165b) (card c20261124T215417-alpha-0)' <<<"$out" \
  && ! grep -qF 'beta:' <<<"$out"; } || fail "wake [$WAKE], reply Idle, each card blocked in health: the stop was not refused naming alpha's two cards alone: $out"
out=$(again "$out" "$(ask "$q1" "$q2")"$'\n'"$(say Idle)")
[ -z "$out" ] || fail "wake [$WAKE], refused once, then questions [$q1], [$q2], reply Idle: the stop was refused: $out"
}

# Two blocked follow-ups of one issue share their name. With f1 shut since the wake, a question naming f1 by its wake
# reference, one naming the shared name alone, and an act naming the name and the parent's issue (alpha #7) leave f2
# refused. A follow-up has no issue of its own: its card is recorded, and health gives it, with issue 0. Bug caught:
# the name was counted only among the cards still blocked, so once f1 was gone the question about it, or the name
# alone, cleared f2.
t_same() {
local WAKE=$'Conveyor: alpha: blocked: Review follow-up of #7\nalpha: not yet reported: blocked Review follow-up of #7 (card f1)\nalpha: not yet reported: blocked Review follow-up of #7 (card f2)'
fixture same "$(jq -cn --arg s "$SINCE" '{alpha: [{card: "f2", issue: 0, name: "Review follow-up of #7", since: $s}]}')"
local q1='Should I retry Review follow-up of #7 (card f1)?' q2='Should I retry Review follow-up of #7?' out
hostact alpha "retried alpha #7, Review follow-up of #7"
out=$(stop "$(ask "$q1" "$q2")"$'\n'"$(say Idle)")
{ refused "$out" && grep -qF '(card f2)' <<<"$out" && ! grep -qF '(card f1)' <<<"$out"; } \
  || fail "wake [$WAKE], f1 shut, act [retried alpha #7, Review follow-up of #7], questions [$q1], [$q2], reply Idle: the stop was not refused for card f2 alone: $out"
}

# The Foreman runs in the owner's own checkout of alpha, whose origin is their fork, fork/alpha; the build host's alpha
# (its record's main, $T/away/alpha, found on the host alone) has example/alpha. A question naming the fork's issue,
# by its link or as fork/alpha#7, leaves alpha's #7 refused; one naming example/alpha's issue by its link lets it pass.
# Bugs caught: the owner of the repository was not checked, so a fork's issue cleared the card; and the repository was
# read from this machine's checkout of that name, the fork, so the fork's issue cleared it and the real one did not.
t_fork() {
local WAKE=$'Conveyor: alpha: blocked: #7\nalpha: not yet reported: blocked #7 (card c7)'
fixture fork "$(jq -cn --arg s "$SINCE" '{alpha: [{card: "c7", issue: 7, since: $s}]}')"
mkdir -p "$T/there" && cp -a "$T/alpha" "$T/there/alpha" && git -C "$T/alpha" remote set-url origin https://github.com/fork/alpha.git \
  && jq --arg m "$T/away/alpha" '.records[0].main = $m' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json" || exit 1
local q1='Should I retry https://github.com/fork/alpha/issues/7?' q2='Should I retry fork/alpha#7?' out
out=$(stop "$(ask "$q1" "$q2")"$'\n'"$(say Idle)")
refused "$out" || fail "wake [$WAKE], local origin fork/alpha, host origin example/alpha, questions [$q1], [$q2], reply Idle: the stop passed: $out"
q1='Should I retry https://github.com/example/alpha/issues/7?'
out=$(again "$out" "$(ask "$q1")"$'\n'"$(say Idle)")
[ -z "$out" ] || fail "wake [$WAKE], local origin fork/alpha, host origin example/alpha, refused once, then question [$q1], reply Idle: the stop was refused: $out"
}

# A Foreman that watches one project still needs the project with the issue. Bug caught: in such a session "#7" alone
# named the watched project's #7, so a question about another project's #7 cleared it.
t_solo() {
local WAKE=$'Conveyor: alpha: blocked: #7\nalpha: not yet reported: blocked #7 (card c7)'
fixture solo "$(jq -cn --arg s "$SINCE" '{alpha: [{card: "c7", issue: 7, since: $s}]}')"
jq 'del(.foreman)' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json" || exit 1
local q='Should I retry beta issue #7?' out
out=$(stop "$(ask "$q")"$'\n'"$(say Idle)")
refused "$out" || fail "wake [$WAKE], alpha watched alone, question [$q], reply Idle: the stop passed: $out"
}

# A prompt of the owner's that quotes the last wake, its first line too, opens no wake: its reply is not held. Bugs
# caught: the lines were read from the turn's opening, whatever it was, so wake text pasted into a prompt held the
# reply as a wake does; and then a prompt that held the wake's first line was taken for the wake.
t_paste() {
fixture paste "$ALL"
local p=$'What does "Conveyor: alpha: blocked: #7" mean? Is this one still open?\nalpha: not yet reported: blocked #7' out
{ jq -cn --arg p "$p" '{type: "user", uuid: "u2", message: {content: $p}}' && say Idle; } > "$T/t.jsonl" || exit 1
out=$(jq -cn --arg t "$T/t.jsonl" '{transcript_path: $t, stop_hook_active: false}' | bash "$SRC/stop.sh" reply)
[ -z "$out" ] || fail "last wake [$WAKE], owner prompt [$p], reply Idle, alpha's #7 blocked in health: the stop was refused: $out"
}

# A project in another Foreman's group is not this Foreman's to report: a line naming it holds nothing. Bug caught: the
# project's record was looked up among all the host file's records, so another Foreman's blocked card held this reply.
t_other() {
fixture other "$ALL"
jq '.foreman.groups = [["alpha"], ["beta"]]' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/h" && mv "$T/h" "$XDG_CONFIG_HOME/conveyor/host.json" || exit 1
local q='Should I retry alpha #7 and c20261124T215417-alpha-0?' out
out=$(stop "$(ask "$q")"$'\n'"$(say Idle)")
[ -z "$out" ] || fail "wake [$WAKE], beta in another Foreman's group and blocked in health, question [$q], reply Idle: the stop was refused: $out"
}

# actrow <answer>...: an act under fixed-block logged 2026-06-01, after the block ($SINCE) and before the wake, in this
# Foreman's ruling log, one row each.
actrow() {
  jq -cn '$ARGS.positional[] | {id: "r-\(.)", utc: "2026-06-01T00:00:00Z", source: "standing", kind: "fixed-block", question: null,
    answer: ., pick: "standing"}' --args "$@" >> "$FD/rulings.jsonl" || exit 1
}
# Records whose health does not read (the build host not reached) still hold their cards, as they may still be
# blocked: Idle is refused. alpha's block time is then the one of the snapshot the watcher kept, for the card id its
# line names, so its acts logged after the block but before the wake count. beta has no kept snapshot, so its act
# counts from the wake's time, and one logged before the wake does not. A picker naming beta's card by the id its line
# gives then lets the stop pass. Bugs caught: such a card was passed over, so with the host not reached the Foreman
# could reply Idle and take no step; a picker naming the card's id no longer counted; and beta's missing snapshot, read
# last, failed the read of every kept snapshot under pipefail, so alpha's acts no longer counted.
t_down() {
fixture down '{}'
rm -f "$T/health-alpha" "$T/health-beta" || exit 1
jq -cn --arg s "$SINCE" '{health: {blocked: [{card: "c7", issue: 7, since: $s, reason: "tests failed"},
  {card: "c20261124T215417-alpha-0", issue: 0, name: "Main is red (d0758b25165b)", since: $s, reason: "tests failed"}]}}' > "$FD/conveyor-snapshot-alpha.json" || exit 1
actrow 'retried alpha #7' 'retried c20261124T215417-alpha-0' 'retried beta #7'
local q='Should I retry b7?' out
out=$(stop "$(say Idle)")
{ refused "$out" && grep -qF 'beta: not yet reported: blocked #7 (card b7)' <<<"$out" && ! grep -qF 'alpha: not yet reported' <<<"$out"; } \
  || fail "wake [$WAKE], no health read, alpha's kept snapshot blocked since $SINCE, none kept for beta, acts [retried alpha #7], [retried c20261124T215417-alpha-0], [retried beta #7] logged 2026-06-01 before the wake, reply Idle: the stop was not refused for beta's card alone: $out"
out=$(again "$out" "$(ask "$q")"$'\n'"$(say Idle)")
[ -z "$out" ] || fail "wake [$WAKE], no health read, refused for beta's card, then question [$q], reply Idle: the stop was refused: $out"
}

# A snapshot kept before the card was retried names the card before it (c7): the card the wake names (c8) is not in
# it, so an act logged for c7 by its id, or for alpha #7 before the wake, is no step on c8, whose block time is not
# known. So is it for a line that names no card id: the kept snapshot's card of that issue is not taken for it. Bug
# caught: the kept snapshot was read by the issue alone, so the old card's retry let Idle pass for the card after it.
t_prev() {
local WAKE=$'Conveyor: alpha: blocked: #7\nalpha: not yet reported: blocked #7 (card c8)'
fixture prev '{}'
rm -f "$T/health-alpha" || exit 1
jq -cn --arg s "$SINCE" '{health: {blocked: [{card: "c7", issue: 7, since: $s, reason: "tests failed"}]}}' > "$FD/conveyor-snapshot-alpha.json" || exit 1
actrow 'retried c7' 'retried alpha #7'
local out
out=$(stop "$(say Idle)")
refused "$out" || fail "wake [$WAKE], alpha's health not read, kept snapshot naming #7 card c7, acts [retried c7], [retried alpha #7] logged 2026-06-01 before the wake, reply Idle: the stop passed: $out"
WAKE=$'Conveyor: alpha: blocked: #7\nalpha: not yet reported: blocked #7'
printf '%s\n' "$WAKE" > "$FD/last-wake.txt" || exit 1
out=$(stop "$(say Idle)")
refused "$out" || fail "wake [$WAKE], alpha's health not read, kept snapshot naming #7 card c7, acts [retried c7], [retried alpha #7] logged 2026-06-01 before the wake, reply Idle: the stop passed: $out"
}

# A card retried, shut or landed since the wake (health no longer holds it blocked) needs no step: Idle passes.
t_moved() {
fixture moved '{}'
local out
out=$(stop "$(say Idle)"); [ -z "$out" ] || fail "wake [$WAKE], reply Idle, nothing blocked in health: the stop was refused: $out"
}

# recmain finds alpha's main under the stop hook's pipefail though the records it reads after mine (which names alpha
# first) fail. Bug caught: its awk left at the first match, so with an awk that leaves at once (gawk, BSD awk) records'
# write to the closed pipe failed the lookup, and the hook then read no health, repository or host act log for the
# card. records is made to fail when recmain calls it, as that write does: mawk reads to the end of a small input
# before it leaves, so a real closed pipe cannot be had on every machine.
t_recmain() {
fixture recmain '{}'
local out
out=$(bash -c 'set -uo pipefail; . "$1/lib.sh" || exit 1; eval "real_$(declare -f records)"
  records() { real_records; [ "${FUNCNAME[1]}" = mine ]; }
  recmain alpha' _ "$SRC" 2>&1)
[ "$out" = "$T/alpha" ] || fail "recmain alpha under pipefail, records failing after mine named alpha: gave [$out], not $T/alpha"
}

cases=(idle act fake ask first fork same solo paste other down prev moved recmain)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  # A pass prints `ok <case>`, named as its FAIL line names it: the pass the main-red proof reads.
  if [ -e "$B/$c.passed" ]; then echo "ok $c"; else bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; fi
done
[ "$bad" = 0 ] || exit 1
