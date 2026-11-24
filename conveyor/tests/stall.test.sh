#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a build, fix or review that stops making progress (watch()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A stalled build or review held its slot until its hard timeout (an hour for a build), though health saw it stuck
# after `stuck` seconds. A step with no output, no file change and no commit for `stuck` seconds is ended and runs once
# more; its line counts the stall (stalls) and keeps the stalled try (firstTry); while the run after it goes on, health
# lists the card stuck with what the engine did, and the Board's card shows the count, the running step's stall too
# (it has no line yet). A review that wrote its verdict and then stalled is ended and run again like any other: it did
# not end by itself, and blocking the card on it gave the stall no second run.
t_stall() {
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables.stuck = 2'; echo "$GO" > "$STUB/review.2"
  # The first build says nothing and changes nothing; the one after it talks until $STUB/go.
  cat > "$STUB/build" <<'EOF'
if [ "$(wc -l < "$STUB/sessions")" = 1 ]; then sleep 60; fi # sleep: a build that says and changes nothing, ended by the engine
for i in $(seq 600); do [ -e "$STUB/go" ] && break; echo '{"type":"system"}'; sleep 0.1; done
echo two >> a.txt
EOF
  echo '[ "$(wc -l < "$STUB/reviews")" != 1 ] || { printf "USER-VISIBLE: no\nVERDICT: GO\n" > "$out"; sleep 60; }' > "$STUB/review-cmd" # sleep: a review that hangs after it wrote its verdict, ended by the engine
  s=$SECONDS; loop run > "$STUB/log" 2>&1 & run=$!
  # A poll of the running loop: what health lists while the retried build still runs is only there during the run.
  # Health is asked only once that build's live record says it was stalled (watch()), which health reads: each
  # `loop health` is a whole engine start, and asking it every 0.2 s from the run's start cost about a fifth of this
  # case's CPU.
  for i in $(seq 150); do
    grep -qs '"stalled"' "$T/$CASE"/cards/*.live && h=$(loop health 2>/dev/null | jq -c '.stuck') && [[ $h == *'"did":"ended and retried"'* ]] && break; sleep 0.2
  done
  b=$(loop snapshot --fresh 2>/dev/null | jq -c '[.belt[] | [.step, .stalls]]')
  : > "$STUB/go"; wait $run || fail "run exited non-zero: $(cat "$STUB/log")"
  c=$(st 'select(.step == "picked") | .card')
  [ "$(jq -c '[.[] | [.card, .step, .did]]' <<<"$h")" = "[[\"$c\",\"build\",\"ended and retried\"]]" ] \
    && jq -e '.[0].since | fromdate > 0' <<<"$h" >/dev/null || fail "health did not list the retried build as stuck, with what the engine did: $h"
  [ "$b" = '[["build",1]]' ] || fail "the snapshot does not count the stall of the build that runs again, before its line is written: $b"
  lim=$(loadlimit 45)
  [ $((SECONDS - s)) -lt "$lim" ] || fail "the stalled steps were not ended after stuck seconds: the run took $((SECONDS - s)) s (limit $lim s: 45 s times the load factor $CASE_LOAD)"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "the build and the review did not each run once more: $(wc -l < "$STUB/sessions") sessions, $(wc -l < "$STUB/reviews") reviews"
  [ "$(st 'select(.step == "build") | [.stalls, (.firstTry.reason | test("^stalled at build: no progress since 20[0-9-]+T"))] | tostring')" = '[1,true]' ] \
    || fail "the build line does not count its stall and keep the stalled try: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "review") | [.result, .stalls, (.firstTry.reason | test("^stalled at review: no progress since 20[0-9-]+T[0-9:]+Z; its events are kept in .*\\.review\\.events$"))] | tostring')" = '["GO",1,true]' ] \
    || fail "the review line does not count its stall and keep the stalled try: $(st 'select(.step == "review")')"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land after its steps ran once more: $(st '"\(.step) \(.reason)"')"
  [ "$(loop snapshot --fresh | jq -c '[.landed[] | .stalls]')" = '[2]' ] || fail "the snapshot does not carry the card's stalls: $(loop snapshot --fresh | jq -c '.landed')"
}

# A second stall at the same step blocks the card, with the reason and its kept work. The clock runs from the last
# progress itself: a file changed while the session still talked is not found `stuck` seconds later and taken for
# progress made then, which gave each try a second wait (the card blocked after four times `stuck`, not two).
# Output with no newline is no new output line: a session printing a spinner moved its output's size every second, which
# reset the clock, and it was never ended.
t_stalltwice() {
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables.stuck = 3'
  printf '%s\n' 'echo "{\"type\":\"system\",\"session_id\":\"0aa1-b2\"}"; echo kept >> a.txt; for i in $(seq 120); do printf x; sleep 0.5; done' > "$STUB/build" # sleep: the pause between two bytes of a spinner, ended by the engine
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c=$(st 'select(.step == "picked") | .card')
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ ! -e "$STUB/reviews" ] || fail "the build did not run twice, then stop: $(wc -l < "$STUB/sessions") sessions"
  st 'select(.step == "blocked") | .reason' | grep -qE '^build: stalled twice at build: no progress since 20[0-9-]+T[0-9:]+Z$' \
    || fail "the blocked reason: $(st 'select(.step == "blocked") | .reason')"
  [ "$(jq -s '(map(select(.step == "start" and .of == "build"))[0].time | fromdate) as $b
      | (map(select(.step == "blocked"))[0].time | fromdate) - $b < 11' "$ST/cards.jsonl")" = true ] \
    || fail "a try was not ended stuck seconds after its last progress, a file changed while it talked: $(st 'select(.step == "start" or .step == "blocked") | "\(.step) \(.time) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "blocked") | [.stalls, .kept, .spent.step] | tostring')" = "[2,\"kept/$c\",\"build\"]" ] \
    || fail "the blocked line does not count both stalls or name the kept work: $(st 'select(.step == "blocked")')"
  grep -qx '+kept' "$ST/kept/$c/$c.patch" || fail "the stalled build's work was not kept: $(cat "$ST/kept/$c/$c.patch" 2>/dev/null)"
  # Issue 1309. Bug it catches: the stalled build ran again from nothing, its whole brief once more, and its block was in
  # the class "session failed", as any failed session's. The stalled Claude session is resumed once by its session id
  # (claude --resume, told the resume brief), and the block of the second stall is in the class stall, with resumed 1.
  ! sed -n 1p "$STUB/sessions" | grep -q -- --resume && sed -n 2p "$STUB/sessions" | grep -q -- '--resume 0aa1-b2 ' \
    || fail "the stalled build was not resumed once by its session id: $(cat "$STUB/sessions")"
  grep -q '^Your session was cut off' "$STUB/brief" || fail "the resumed session was given the whole brief again, not the resume brief: $(head -c 300 "$STUB/brief")"
  [ "$(st 'select(.step == "blocked") | [.class, .resumed] | tostring')" = '["stall",1]' ] \
    && [ "$(loop snapshot --fresh 2>/dev/null | jq -r '.metrics.cards[] | select(.issue == 7) | .metrics.blockClass')" = stall ] \
    || fail "the twice-stalled build's block is not in the class stall with one resume: $(st '"\(.step) \(.class) \(.resumed) \(.reason)"' | tr '\n' ,)"
}

# Output, a changed file and a new commit each reset the clock: a session that keeps doing one of them is never ended,
# however long the others stay still. Each case runs a stub that does one of them alone for at least twice `stuck` (3 s): 6 s,
# or 8 s for t_stallprogressrare, under
# the engine's watch() (stallwatched(), below), and checks that watch() returns the stub's own exit and writes no
# <worktree>.stalled: a reset that is missed ends the stub at about 3 s with that file. Output that comes less often
# than the live record is read still counts (it is read before the clock is, or a line 2 s after the last was missed at
# 3 s), and so does a file git ignores, and a write that keeps an old modification time (`cp -p`), which only the
# change time shows.
t_stallprogress() {
  progressing <<'EOF'
for i in $(seq 12); do sleep 0.5; echo '{"type":"system"}'; done # sleep: the pause between two output lines
EOF
}
t_stallprogressrare() {
  progressing <<'EOF'
for i in $(seq 4); do sleep 2; echo '{"type":"system"}'; done # sleep: output that comes less often than the live record is read
EOF
}
t_stallprogressfile() {
  progressing <<'EOF'
for i in $(seq 12); do echo "$i" > a.txt; sleep 0.5; done # sleep: the pause between two changes of a tracked file
EOF
}
t_stallprogressignored() {
  progressing <<'EOF'
echo ignored.txt >> "$(git rev-parse --git-path info/exclude)"
for i in $(seq 12); do echo "$i" > ignored.txt; sleep 0.5; done # sleep: the pause between two changes of an ignored file
EOF
}
t_stallprogressmtime() {
  progressing <<'EOF'
d=$(mktemp -d); echo old > "$d/old.1"; echo older > "$d/old.2"; touch -d 2020-01-01 "$d/old.1" "$d/old.2"
for i in $(seq 12); do cp -p "$d/old.$((i % 2 + 1))" a.txt; sleep 0.5; done; rm -rf "$d" # sleep: the pause between two writes that keep an old modification time
EOF
}
t_stallprogresscommit() {
  progressing <<'EOF'
for i in $(seq 12); do git commit -q --allow-empty -m "step $i"; sleep 0.5; done # sleep: the pause between two commits
EOF
}
progressing() { # stdin: the shell of the build's one kind of progress, at least twice `stuck` long
  stallwatched build 3 'exit 7'
  [ "$RC" = 7 ] && [ ! -e "$W.stalled" ] || fail "a session making progress was ended: watch() returned $RC after $TOOK s, stalled: $(cat "$W.stalled" 2>/dev/null)"
}
# Runs stdin's shell, then <last shell>, in a fresh worktree (its git folder outside it, as a card's is) under the
# engine's watch() as step <step>, with STUCK=<stuck> and a live record every 0.2 s (setup's live), its output beside the
# worktree. Sets W (the worktree), RC (watch()'s exit) and TOOK (its seconds).
stallwatched() { # <step> <stuck> <last shell>
  local p s; p=$(cat); W=$T/$CASE/wt
  git init -q -b main --separate-git-dir "$T/$CASE/git" "$W" && echo one > "$W/a.txt" && git -C "$W" add a.txt \
    && git -C "$W" commit -qm a || fail "the case's worktree could not be made"
  printf '%s\n' "$p" "$3" > "$T/$CASE/step.sh"
  s=$SECONDS
  ( eval "$(sed -n '/^rollout() {/,/^}/p; /^holds() {/,/^}/p; /^watch() {/,/^}/p' "$SRC/lib/session.sh")"
    # shellcheck disable=SC2034 # LIVE, STUCK and SESSION_STUCK are read by watch(), defined by the eval
    LIVE=0.2 STUCK=$2 SESSION_STUCK=600; (cd "$W" && exec bash "$T/$CASE/step.sh") > "$W.out" 2>&1 < /dev/null &
    watch $! "$W.out" "$W.live" "$1" ); RC=$?; TOOK=$((SECONDS - s))
}
# Issue 1319: a step that ended before watch() started its timer. Bash 5.1 and 5.2 take a job that ended off their
# job table when the next job starts, and their `wait -n` of such a pid writes "<pid>: no such job" to the caller's
# stderr (into the verdict a main-red proof reads) and waits out the timer (LIVE); `wait <pid>` still gives its kept
# status. Bash 5.3 finds the pid itself, so the case puts a `wait` in front of the builtin that does as 5.1 and 5.2 do
# for a `wait -n` of a pid that has ended: a direct check on a 5.3 host cannot show that bash's behaviour otherwise.
# Bug it catches: that line, the wait of LIVE, or the step's exit (7) lost.
t_stallreaped() {
  local out W=$T/$CASE/wt
  mkdir -p "$W"; : > "$W.out"
  out=$( ( eval "$(sed -n '/^rollout() {/,/^}/p; /^holds() {/,/^}/p; /^watch() {/,/^}/p' "$SRC/lib/session.sh")"
    wait() { # bash 5.2's `wait -n [-p <name>] <pid>...`: a pid that has ended is no job; else the builtin
      [ "$1" = -n ] || { builtin wait "$@"; return; }
      local a=(-n) x; shift; [ "$1" != -p ] || { a+=(-p "$2"); shift 2; }
      for x; do if kill -0 "$x" 2>/dev/null; then a+=("$x"); else echo "wait: $x: no such job" >&2; fi; done
      builtin wait "${a[@]}"
    }
    # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), defined by the eval
    LIVE=5 STUCK=600; (exit 7) & p=$!
    while kill -0 "$p" 2>/dev/null; do command sleep 0.05; done # sleep: until this shell has reaped the step
    s=$SECONDS; watch "$p" "$W.out" "$W.live" build; echo "rc $? took $((SECONDS - s))" ) 2>&1 )
  [[ $out =~ ^rc\ 7\ took\ ([0-9]+)$ ]] && [ "${BASH_REMATCH[1]}" -lt 4 ] \
    || fail "watch() of a step that ended with 7 before its timer began, under bash 5.2's wait -n, did not return 7 at once with nothing on stderr: $out"
}
# #1444 (R295). Bug it catches: a build that started a test in the background under timeout (in a process group of
# its own, as the brief tells builders to) and then ended left that test running in the worktree: watch() ends only
# the session's process, and block() then took the worktree away under the test. The build session alone, as card()
# calls it, with the mark (CONVEYOR_CARDRUN) a card's process gives what it starts.
t_stallleft() {
  local bg
  setup '[]'; fx_wt : b.txt one
  echo 'timeout 60 sleep 31 > /dev/null 2>&1 & echo $! > "$STUB/bg"; echo two >> a.txt' > "$STUB/build" # sleep: a test the build leaves running
  CONVEYOR_CARDRUN=c7 fx_in 'cd "$R" && session "$FXWT" "Build the issue."; echo "rc=$?"'
  bg=$(cat "$STUB/bg" 2>/dev/null)
  [ -n "$bg" ] && grep -qx 'rc=0' "$T/$CASE/run.out" || fail "the build that starts a background test did not run and end well: $(cat "$T/$CASE/run.out")"
  wait_until "! ps -o stat= -p $bg | grep -qv Z" "ps -o pid=,stat=,args= -p $bg" \
    || { kill "$bg" 2>/dev/null; fail "the test the build left running in its worktree under timeout outlived the session"; }
}
# The runner (conveyor.test.sh) sources every area file before any case runs, so a function two files define is, in
# every run, the later file's for the cases of both. Bug it catches (#871): views.test.sh and stall.test.sh each
# defined a watched() of other arguments, and serve.test.sh an eng() of other arguments than mainred.test.sh's, which
# five other files call; whichever file came later took the name. The views watch is viewslive.test.sh's now.
t_stallownwatched() { ownfuncs stall viewslive; }
t_stallowneng() { ownfuncs mainred serve; }
# ownfuncs <area> <area>: with both area files sourced, in either order, each function of each file is the one that
# file defines when sourced alone, so its cases call their own. It compares the functions' text, not a call: a call of
# the other file's function can pass (when both take the same arguments) or fail for its own reasons.
ownfuncs() {
  local a o order names alone
  for a in "$1" "$2"; do
    o=$1; [ "$a" != "$1" ] || o=$2
    names=$(srcd "$a"; compgen -A function | grep -vx srcd)
    # shellcheck disable=SC2086 # $names and $order are function and file names, single words
    alone=$(srcd "$a"; declare -f $names)
    [ -n "$names" ] || { fail "$a.test.sh, sourced alone, defined no function"; continue; }
    for order in "$a $o" "$o $a"; do
      # shellcheck disable=SC2086
      [ "$(srcd $order; declare -f $names)" = "$alone" ] || fail "with ${order// /.test.sh and }.test.sh sourced in that order, a function of $a.test.sh is another file's"
    done
  done
}
# srcd <area>...: in this (sub)shell, no function but those the area files define, sourced in that order.
srcd() {
  local f
  # shellcheck disable=SC2046 # function names are single words
  unset -f $(compgen -A function | grep -vx srcd)
  # shellcheck disable=SC1090 # the area files the case names
  for f; do . "$SRC/tests/$f.test.sh" > /dev/null < /dev/null; done
}

# A card waiting by design (here to land, on a same-file card that lands first) is never ended, however long it waits:
# #8 waits on #7, whose tests end only 5 s (more than twice `stuck`) after #8 is seen waiting. Then #8 goes on from
# main: one session brings its change there.
t_stallwait() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; tune '.tunables.stuck = 2'; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  # Both append to a.txt; #8 builds once #7 is in review, talking meanwhile.
  cat > "$STUB/build" <<'EOF'
if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then printf 'one\nseven\neight\n' > a.txt
else case $PWD in
  *-7) echo seven >> a.txt ;;
  *) for i in $(seq 300); do [ -e "$STUB/inreview.7" ] && break; echo '{"type":"system"}'; sleep 0.1; done; echo eight >> a.txt ;;
esac; fi
EOF
  echo ': > "$STUB/inreview.${PWD##*-}"' > "$STUB/review-cmd"
  echo 'case $PWD in *-7) for i in $(seq 300); do grep -q waiting ../*-8.live 2>/dev/null && { : > "$STUB/waited"; sleep 5; break; }; sleep 0.1; done ;; esac' >> "$STUB/test-cmd" # sleep: #7's tests hold more than twice stuck while #8 waits
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ -e "$STUB/waited" ] || fail "#8 did not wait on #7: $out"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 " ] || fail "both did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(wc -l < "$STUB/sessions")" = 3 ] && [ -z "$(st 'select(.stalls or .firstTry or (.reason | test("stalled"))) | .step')" ] \
    || fail "a waiting card was ended: $(wc -l < "$STUB/sessions") sessions; $(st 'select(.stalls or .firstTry)')"
}

# A Claude review that gave its verdict and then stalled is ended and run again too, not blocked at once.
t_stallclaude() {
  setup "[$(issue 7 2026-01-01)]"; tune --slurpfile real "$SRC/lib/test-pack.json" '.tunables.stuck = 2 | .models.allowed = $real[0].models.allowed'
  loop control reviewer claude claude-opus-5-5 max >/dev/null 2>&1 || fail "the Claude reviewer was not set"
  echo "$GO" > "$STUB/review"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --tools "*) ;; *) cat > "$STUB/brief"; echo "$*" >> "$STUB/sessions"; . "$STUB/build"
  echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'; exit 0 ;; esac
cat > /dev/null; echo x >> "$STUB/reviews"
jq -cn --rawfile r "$STUB/review" '{type: "result", is_error: false, result: $r, num_turns: 2,
  usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7}}'
[ "$(wc -l < "$STUB/reviews")" != 1 ] || sleep 60 # sleep: a review that hangs after its result, ended by the engine
EOF
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "the stalled Claude review did not run once more: $(wc -l < "$STUB/reviews") reviews; $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "review") | [.result, .stalls, (.firstTry.reason | test("^stalled at review: no progress since 20[0-9-]+T"))] | tostring')" = '["GO",1,true]' ] \
    || fail "the review line does not count its stall and keep the stalled try: $(st 'select(.step == "review")')"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land after its review ran once more: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# The run after a stall waits reviewPause first, a session's as a review's: a build or fix ended for no progress began
# again at once, into the same fault (a network that is down) that stalled it.
t_stallpause() {
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables.stuck = 2 | .tunables.reviewPause = 5'; echo "$GO" > "$STUB/review.1"
  echo 'date +%s >> "$STUB/began"; [ "$(wc -l < "$STUB/sessions")" != 1 ] || sleep 60; echo two >> a.txt' > "$STUB/build" # sleep: a first build that hangs, ended by the engine
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(wc -l < "$STUB/began")" = 2 ] || fail "the stalled build did not run once more: $(wc -l < "$STUB/began") sessions; $out"
  # The first is ended 1 to 3 s after it began (stuck, in whole seconds): 6 s apart is the pause, kept.
  [ $(($(sed -n 2p "$STUB/began") - $(sed -n 1p "$STUB/began"))) -ge 6 ] || fail "the build ran again without waiting reviewPause: it began at $(tr '\n' ' ' < "$STUB/began")"
  [ "$(st 'select(.step == "build") | .stalls')" = 1 ] && [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land with its stall counted: $(st '"\(.step) \(.stalls) \(.reason)"' | tr '\n' ,)"
}

# A Codex review's session file that grows with no new token count read from it is no progress: bytes of a line cut
# short there moved its size and reset the clock, so a review hung in the middle of a write was never ended. The
# review's session file grows by a byte each 0.5 s for 15 s under watch() with STUCK=2: watch() ends it within a few
# seconds and writes <worktree>.stalled with the time its progress stopped.
t_stallrollout() {
  export CODEX_HOME=$T/$CASE/codex-home; mkdir -p "$T/$CASE/codex-home/sessions/2026/01/01"
  stallwatched review 2 'exit 0' <<'EOF'
echo '{"type":"thread.started","thread_id":"0aa1-b2"}'
f=$CODEX_HOME/sessions/2026/01/01/rollout-2026-01-01T00-00-00-0aa1-b2.jsonl
echo '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"cached_input_tokens":0,"output_tokens":0}}}}' > "$f"
for i in $(seq 30); do printf x >> "$f"; sleep 0.5; done # sleep: the pause between two bytes of a line cut short, ended by watch()
EOF
  [ "$TOOK" -lt 10 ] && [ "$RC" != 0 ] || fail "a review whose session file grew by part of a line was not ended after stuck seconds: watch() returned $RC after $TOOK s"
  jq -en --arg t "$(cat "$W.stalled" 2>/dev/null)" '$t | fromdate > 0' > /dev/null 2>&1 || fail "the ended review left no time in its .stalled file: $(cat "$W.stalled" 2>/dev/null)"
}

# Bug (#466): a card whose build line is written and whose next step never starts (here the project's checks hang
# after the build, with no live record) sat at review with no reviewer for good: the loop left it open, its slot
# taken, and `retry` refused it. Once stuck and reviewPause pass with no line and no write, the loop ends the card and
# everything under it, and blocks it naming its review step, with no review run.
t_stallnostep() {
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables.stuck = 3 | .tunables.reviewPause = 1 | .tunables.poll = 1'
  echo 'echo two >> a.txt' > "$STUB/build"
  printf '%s\n' 'echo $$ > "$STUB/hang.pid"; exec sleep 600' > "$STUB/hang" # sleep: checks that never end, ended by the loop
  tune --arg c "bash $STUB/hang" '.test.checkCommand = $c'
  s=$SECONDS; out=$(loop run --only 7 2>&1) || fail "run exited non-zero: $out"
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "review: no process of this step ran for 4s (the pack's stuck and reviewPause), so the engine stopped the card" ] \
    || fail "#7 was not blocked naming its review step: $(st 'select(.issue == 7) | [.step, .of, .reason] | map(strings) | join(" ")' | tr '\n' ,) $out"
  lim=$(loadlimit 60 600) # under the checks' 600 s hang
  [ $((SECONDS - s)) -lt "$lim" ] || fail "the stuck card was not ended soon after stuck and reviewPause: the run took $((SECONDS - s)) s (limit $lim s: 60 s times the load factor $CASE_LOAD)"
  [ ! -e "$STUB/reviews" ] && [ -z "$(st 'select(.issue == 7 and .step == "review")')" ] || fail "#7 was reviewed: $(st 'select(.issue == 7 and .step == "review")')"
  [ -s "$STUB/hang.pid" ] && ! kill -0 "$(cat "$STUB/hang.pid")" 2>/dev/null || fail "the hung checks under the card were left running"
  c=$(st 'select(.step == "picked") | .card')
  [ "$(st 'select(.step == "blocked") | .kept')" = "kept/$c" ] && [ -s "$ST/kept/$c/$c.patch" ] || fail "the card's work was not kept: $(st 'select(.step == "blocked")')"
}
