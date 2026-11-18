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
  for i in $(seq 150); do h=$(loop health 2>/dev/null | jq -c '.stuck'); [[ $h == *'"did":"ended and retried"'* ]] && break; sleep 0.2; done
  b=$(loop snapshot --fresh 2>/dev/null | jq -c '[.belt[] | [.step, .stalls]]')
  : > "$STUB/go"; wait $run || fail "run exited non-zero: $(cat "$STUB/log")"
  c=$(st 'select(.step == "picked") | .card')
  [ "$(jq -c '[.[] | [.card, .step, .did]]' <<<"$h")" = "[[\"$c\",\"build\",\"ended and retried\"]]" ] \
    && jq -e '.[0].since | fromdate > 0' <<<"$h" >/dev/null || fail "health did not list the retried build as stuck, with what the engine did: $h"
  [ "$b" = '[["build",1]]' ] || fail "the snapshot does not count the stall of the build that runs again, before its line is written: $b"
  [ $((SECONDS - s)) -lt 45 ] || fail "the stalled steps were not ended after stuck seconds: the run took $((SECONDS - s)) s"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] || fail "the build and the review did not each run once more: $(wc -l < "$STUB/sessions") sessions, $(wc -l < "$STUB/reviews") reviews"
  [ "$(st 'select(.step == "build") | [.stalls, (.firstTry.reason | test("^stalled at build: no progress since 20[0-9-]+T"))] | tostring')" = '[1,true]' ] \
    || fail "the build line does not count its stall and keep the stalled try: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "review") | [.result, .stalls, (.firstTry.reason | test("^stalled at review: no progress since 20[0-9-]+T"))] | tostring')" = '["GO",1,true]' ] \
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
  printf '%s\n' 'echo "{\"type\":\"system\"}"; echo kept >> a.txt; for i in $(seq 120); do printf x; sleep 0.5; done' > "$STUB/build" # sleep: the pause between two bytes of a spinner, ended by the engine
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
}

# Output, a changed file and a new commit each reset the clock: a session that keeps doing one of them is never ended,
# however long the others stay still (each case's session does one of them alone for twice `stuck`, and the six run
# side by side). Output that comes less often than the live record is read still counts (it is read before the clock
# is, or a line 2 s after the last was missed at 3 s), and so does a file git ignores, and a write that keeps an old
# modification time (`cp -p`), which only the change time shows.
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
for i in $(seq 12); do echo "$i" > progress.txt; sleep 0.5; done; rm progress.txt # sleep: the pause between two file changes
EOF
}
t_stallprogressignored() {
  progressing <<'EOF'
echo ignored.txt >> "$(git rev-parse --git-path info/exclude)"
for i in $(seq 12); do echo "$i" > ignored.txt; sleep 0.5; done; rm ignored.txt # sleep: the pause between two changes of an ignored file
EOF
}
t_stallprogressmtime() {
  progressing <<'EOF'
cp a.txt "$STUB/a.was"; echo old > "$STUB/old.1"; echo older > "$STUB/old.2"; touch -d 2020-01-01 "$STUB/old.1" "$STUB/old.2"
for i in $(seq 12); do cp -p "$STUB/old.$((i % 2 + 1))" a.txt; sleep 0.5; done # sleep: the pause between two writes that keep an old modification time
cat "$STUB/a.was" > a.txt
EOF
}
t_stallprogresscommit() {
  progressing <<'EOF'
for i in $(seq 12); do git commit -q --allow-empty -m "step $i"; sleep 0.5; done # sleep: the pause between two commits
EOF
}
progressing() { # stdin: the shell of the build's one kind of progress, twice `stuck` long
  local p; p=$(cat)
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables.stuck = 3'; echo "$GO" > "$STUB/review.1"
  printf '%s\n' 'h=$(git rev-parse HEAD)' "$p" 'git reset -q --soft "$h"; echo two >> a.txt' > "$STUB/build"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "a session making progress was ended: $(wc -l < "$STUB/sessions") sessions; $out"
  [ -z "$(st 'select(.stalls or .firstTry) | .step')" ] || fail "a line counts a stall: $(st 'select(.stalls or .firstTry)')"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.reason)"')"
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
# short there moved its size and reset the clock, so a review hung in the middle of a write was never ended.
t_stallrollout() {
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables.stuck = 2'; echo "$GO" > "$STUB/review.2"
  echo 'echo two >> a.txt' > "$STUB/build"
  export CODEX_HOME=$STUB/codex-home; mkdir -p "$CODEX_HOME/sessions/2026/01/01"
  cat > "$STUB/review-cmd" <<'EOF'
if [ "$(wc -l < "$STUB/reviews")" = 1 ]; then
  echo '{"type":"thread.started","thread_id":"0aa1-b2"}'
  f=$CODEX_HOME/sessions/2026/01/01/rollout-2026-01-01T00-00-00-0aa1-b2.jsonl
  echo '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"cached_input_tokens":0,"output_tokens":0}}}}' > "$f"
  for i in $(seq 120); do printf x >> "$f"; sleep 0.5; done # sleep: the pause between two bytes of a line cut short, ended by the engine
fi
EOF
  s=$SECONDS; out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ $((SECONDS - s)) -lt 45 ] || fail "a review whose session file grew by part of a line was not ended after stuck seconds: the run took $((SECONDS - s)) s"
  [ "$(st 'select(.step == "review") | [.result, .stalls, (.firstTry.reason | test("^stalled at review: no progress since 20[0-9-]+T"))] | tostring')" = '["GO",1,true]' ] \
    || fail "the review was not ended and run once more: $(st 'select(.step == "review")')"
}
