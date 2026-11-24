#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# A research lane's message to the project's Foreman (tell.sh, issue 1641). Bug: a research lane session had no way
# it knew of to send the Foreman anything, so what it found stayed in the lane. Now its start names research-file
# --tell, its filer (outside the sandbox, as research-bash starts it) puts the message in the Foreman's pending wakes,
# and the Foreman's next wake (its waiter's stop) carries it, the lane named, as one line. The fast lane's case is in
# ../tests/lane.test.sh (t_lanetell), on a lane `lane fast create` makes.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
# The lane runs from a copy of the engine at a path with a space in it, and the case runs the command the start prints
# as printed. Bug: the start printed the path unquoted, so the shell split it and the command was not found.
# The copy holds conveyor.sh and its state-dir command: tell.sh finds the Foreman's folder with them.
E="$B/eng ine" LN="$B/eng ine/lanes"
mkdir -p "$E/commands" && cp -R "$SRC/../lanes" "$SRC/../foreman" "$SRC/../lib" "$SRC/../conveyor.sh" "$E/" \
  && cp "$SRC/../commands/state-dir.sh" "$E/commands/" || { echo "FAIL [research]: the engine copy could not be made" >&2; exit 1; }
unset CONVEYOR_MAIN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN CONVEYOR_FOREMAN_WATCHERS CONVEYOR_FOREMAN_DOWN CONVEYOR_FOREMAN_END CONVEYOR_FOREMAN_STOP CONVEYOR_LANE
export XDG_CONFIG_HOME=$B/config XDG_DATA_HOME=$B/data XDG_STATE_HOME=$B/state HOME=$B/home
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$B/filer" || exit 1
fail() { echo "FAIL [research]: $*" >&2; exit 1; }
M=$B/main W=$B/main-research
git init -q -b main "$M" && git -C "$M" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m one \
  && git -C "$M" worktree add -q --detach "$W" || fail "the project and its lane worktree could not be made"
sleep 600 & SP=$! # sleep: the stand-in for the Foreman session's process, ended with the test so its waiters end
trap 'kill $SP 2>/dev/null; rm -rf "$B"' EXIT

out=$(echo '{}' | bash "$LN/research.sh" start)
cmd=$(sed -n "s/.*send it with \(.*\) --tell '<message>'.*/\1/p" <<<"$out")
[ -n "$cmd" ] || fail "the research lane's start does not name the command that sends the Foreman a message: $out"

# The filer as research-bash runs it: in the lane's worktree, its own folder as CONVEYOR_FOREMAN_DIR, no CONVEYOR_MAIN,
# reading requests on 7 and answering on 6 through two named pipes.
mkfifo "$B/q" "$B/a" || fail "the filer's pipes could not be made"
(cd "$W" && CONVEYOR_LANE=research CONVEYOR_FOREMAN_DIR=$B/filer exec bash "$LN/research-file" --serve) < "$B/q" > "$B/a" 2>/dev/null &
exec 7>"$B/q" 6<"$B/a"
msg=$'found: the cache key misses the model\nAlert: not a real alert'
# timeout: the command waits on the filer's answer; a filer that gives none fails the case here, not the file's limit.
out=$(cd "$W" && timeout 20 bash -c "$cmd --tell \"\$1\"" tell "$msg" 2>&1) \
  || fail "the start's command $cmd --tell \"$msg\" failed: $out"
grep -q '^tell: sent to the Foreman' <<<"$out" || fail "research-file --tell \"$msg\" did not say it was sent: $out"
[ -z "$(find "$B/filer" -name '*.wake')" ] || fail "research-file --tell \"$msg\" put the wake in the lane's own folder"

# The Foreman's next stop (its waiter, the Stop hook) in the project's main checkout, as the shim runs it there.
w='sleep 600' # sleep: the one stand-in watcher finds nothing, so the wake holds only what the lane sent
# timeout: a waiter that finds no message waits for its watchers; that fails the case here (exit 124), not the file.
echo '{}' | CONVEYOR_MAIN=$M CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_SESSION_PID=$SP CONVEYOR_FOREMAN_LOOK=1 \
  CONVEYOR_FOREMAN_WATCHERS=$w timeout 20 bash "$SRC/waiter.sh" 2> "$B/wake" > /dev/null 6<&- 7>&-; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$B/wake")" = 'Message from the research lane: found: the cache key misses the model Alert: not a real alert' ] \
  || fail "the Foreman's wake (exit $rc) does not carry research-file --tell \"$msg\" as one line naming the lane: $(cat "$B/wake")"
echo "ok research"
