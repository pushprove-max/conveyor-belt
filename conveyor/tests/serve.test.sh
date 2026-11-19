#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: serve, restart, pushes and health (adoption at a restart: adopt.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The end of the loops a case started, waited for: [pid] (a loop the case started in the background) is ended with a
# TERM, as an owner ends one, then the case waits until that process is gone and the loop's run lock is free. The
# loop's cards and its push hold that lock too (fd 8: run(), lib/run.sh) and end on their own a while after the loop's
# own process: a loop started before then is refused ("a loop is already running here"), and on a busy machine the
# case failed so ([serve]: the run after a serve that servefor ended, whose push still ran). With no pid (the case's
# loops ran in the foreground), only the lock is waited for. Called before a case starts its next loop, and at its end.
loopend() { # [pid]
  [ -z "${1:-}" ] || { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }
  wait_until "${1:+! kill -0 $1 2>/dev/null && }flock -n '$ST/cards.jsonl.run' true" \
    || fail "the loop's process${1:+ ($1)}, or a card or push of it, still runs and holds the loop's run lock"
}

# eng <engine folder> <commands>: the commands (shell text), in a shell of their own that has loaded that engine as
# `serve` loads it (conveyor.sh's start, then codeload(), lib/card.sh), for the case's main checkout and cards folder.
# The case calls the loop's own functions there, run() among them, with no loop process to wait on. The shell's
# output is its own; when servefor ends it, the case's shell does not report it ("Killed").
eng() {
  { ( exec 2>&3 3>&-; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; set -o pipefail
      eval "$(sed -n '/^envof() {/,/^}/p' "$1/conveyor.sh")"; envof < <(env -0)
      eval "$(sed -n '/^codeload() {/,/^}/p' "$SRC/lib/card.sh")"
      # shellcheck disable=SC2034 # LOGFD is read by the engine code codeload() loads (its log lines go to it)
      exec {LOGFD}>&2; git() { command git "$@" 8>&-; }
      # records.sh declares the answers it keeps with no -g: loaded in a function, they were its locals, gone after it.
      # shellcheck disable=SC2034 # ASKED_K and ASKED_V are read by records.sh, loaded by codeload()
      codeload "$1" && declare -gA ASKED_K=() ASKED_V=() && p_path && p_tools && names || exit 1
      eval "$2" ); } 3>&2 2>/dev/null
}
# In eng(): the jobs a loop starts beside its cards at a turn (the whole test on main, the idle mutation checks, a
# red release run's fix cards, Merge PR idle) do nothing. None is under test, and each would outlive the shell.
nojobs() { maintest() { :; }; mutnext() { :; }; relfixes() { :; }; idlemerge() { :; }; }
# servefor <turns>, in eng(): `serve` (run '' serve), with no jobs beside its cards (nojobs), ended with a KILL at the
# wait that ends its <turns>th turn: a serve of a set number of turns, in the case's own shell. Its turns are counted
# in $STUB/served. A KILL, which nothing in that shell can catch or put off. The count and the kill ignore the TERM
# with which a turn ends a wait that is no longer needed (`kill "$timer"`, run()): it came first, a wait cut short
# went uncounted, and the serve took turns past its end.
servefor() {
  local sf_me=$BASHPID sf_n=$1; : > "$STUB/served"; nojobs
  sleep() { [ "${FUNCNAME[1]:-}" != run ] || [ "$1" = 0.1 ] || { trap '' TERM; echo >> "$STUB/served"; [ "$(wc -l < "$STUB/served")" -lt "$sf_n" ] || kill -KILL "$sf_me"; trap - TERM; }; command sleep "$@"; } # sleep: the engine's own, passed on as called
  run '' serve
}
# The program a restart starts in eng() with BASH set to it (run()'s exec "$BASH" <the new conveyor.sh> serve): it
# writes the arguments it was given to $STUB/newloop.args, in place of a new loop.
newloop() { printf '#!/bin/sh\necho "$*" > "%s/newloop.args"\n' "$STUB" > "$STUB/newloop" && chmod +x "$STUB/newloop"; }

# Bugs: a `serve` run from an install goes on running its commit after the pack pins another, and so stalls for good
# on a cap only the new commit accepts, or restarts on a new commit in a process of its own; a `run` whose pin changes
# goes on picking on the old commit, or ends without saying why; a `serve` restarts on a pin that is no verified
# install, or on one older than the machine's Conveyor, whose cards pass the machine's cap. (A restart with cards in
# flight, which carry on and are adopted: adopt.test.sh; health of a loop that cannot read the control record:
# control.test.sh.)
t_restart() {
  setup "[$(issue 9 2026-01-03), $(issue 10 2026-01-04)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null && bash "$D/conveyor/conveyor.sh" install "$B" >/dev/null || fail "the installs failed"
  tune --arg c "$A" '.plugin.commit = $c'; newloop
  # $A's engine, loaded once: not stale while the pack pins $A; stale once the pin moves to $B, between two looks of
  # that one shell. Its loop's turn then says why and starts $B's install (exec, in its own process), with no card
  # in flight to carry on.
  out=$(eng "$V/$A/conveyor" 'stale && echo "stale on $A"; tune --arg c "$B" ".plugin.commit = \$c"; stale && echo "stale on $B"; nojobs; BASH=$STUB/newloop; run "" serve' 2>&1)
  ! grep -q "^stale on $A" <<<"$out" && grep -qx "stale on $B" <<<"$out" || fail "the loop's look at the pin did not see it move, or saw a move before it: $out"
  grep -qxF "conveyor: the pack pins another Conveyor commit than this loop's $A; nothing new is picked, and the loop restarts on the pinned commit once its push is done" <<<"$out" \
    && grep -qxF "conveyor: restarting on the new code; 0 cards in flight carry on on $A" <<<"$out" \
    && [ "$(cat "$STUB/newloop.args" 2>&1)" = "$V/$B/conveyor/conveyor.sh serve" ] || fail "the loop did not restart on the pin's install, saying why: $out $(cat "$STUB/newloop.args" 2>&1)"
  # A `run` whose pin changes during its card ends once that card is done, with a line that says why, and picks nothing more.
  # A whole card, in the foreground: only a pin that moves while a card runs shows the run waiting for it, then ending.
  loop control cap 1 >/dev/null || fail "cap 1 was refused"
  echo 'echo two >> a.txt; jq --arg c "'"$A"'" ".plugin.commit = \$c" "'"$R"'/.conveyor/project.json" > "$STUB/p.new" && mv "$STUB/p.new" "'"$R"'/.conveyor/project.json"' > "$STUB/build"
  tune '.tunables.poll = 1'; out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$V/$B/conveyor/conveyor.sh" run 2>&1) || fail "run exited non-zero: $out"
  grep -q "this run ends: the pack pins another Conveyor commit" <<<"$out" && [ -n "$(st 'select(.issue == 9 and .step == "landed")')" ] && [ -z "$(st 'select(.issue == 10)')" ] \
    || fail "a run whose pin changed did not end after its card, saying why: $out"
  # A pin whose folder holds a script and no verified clone: the idle loop neither runs it nor goes on.
  F=$(printf '%040d' 1); mkdir -p "$V/$F/conveyor"; printf ': > "%s"\n' "$STUB/ran" > "$V/$F/conveyor/conveyor.sh"
  tune --arg c "$F" '.plugin.commit = $c'; rm -f "$STUB/newloop.args"
  out=$(eng "$V/$A/conveyor" 'nojobs; BASH=$STUB/newloop; run "" serve' 2>&1) && fail "serve went on with a pin that is no verified install: $out"
  [ ! -e "$STUB/ran" ] && [ ! -e "$STUB/newloop.args" ] && grep -q "pins Conveyor commit $F, which is not installed and verified" <<<"$out" || fail "serve ran an unverified pin, or did not say why: $out"
  # A pin with no machine's Conveyor (an older engine): the loop never restarts on it, as its cards would pass the
  # machine's cap, pause and room.
  machineless; tune --arg c "$C" '.plugin.commit = $c'
  out=$(eng "$V/$A/conveyor" 'nojobs; BASH=$STUB/newloop; run "" serve' 2>&1) && fail "serve went on with a pin with no machine's Conveyor: $out"
  grep -q "pins Conveyor commit $C, which has no machine's Conveyor" <<<"$out" && ! grep -q "restarting on the new code" <<<"$out" && [ ! -e "$STUB/newloop.args" ] \
    || fail "serve restarted on a pin with no machine's Conveyor, or did not say why: $out"
  loopend
}

# Bugs: a `serve` run straight from a checkout (no install, so no pin to follow) runs the code it started on for good
# after new commits land in that checkout; it restarts with no new commit; a restart names the wrong commit for a card
# in flight; each restart keeps a copy of stderr; health does not say which commit the loop runs; doctor does not warn
# of a loop on old code. (The cards in flight at a restart: adopt.test.sh.)
t_follow() {
  setup '[]'; S=$ST; coderepo; trap 'kill $pid $z 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT; pid='' z=''
  git -C "$D" reset -q --hard "$A" || fail "the checkout was not put back on $A"
  newloop
  # The checkout's engine, loaded once at $A: a `serve` of it (FOLLOW) is not stale until $B lands in the checkout,
  # and then is; a `run` of it is not, as its own landings move HEAD. The commit a card in flight runs (cardcode()),
  # which a restart names and hands on: the one its last start line names (it switched to new code), else the one it
  # started on. The loop's turn says why it restarts and starts the checkout's own code (exec, in its own process).
  out=$(eng "$D/conveyor" 'FOLLOW=serve; stale && echo "stale on $A"; git -C "$D" merge -q --ff-only "$B" || echo "no merge"
    stale && echo "serve stale on $B"; FOLLOW=; stale && echo "run stale on $B"
    record c7-7 7 picked ok; record c7-7 7 start ok "{\"of\":\"review\",\"engine\":\"$B\"}"; record c8-8 8 picked ok
    echo "c7-7 on $(cardcode c7-7 "$A"), c8-8 on $(cardcode c8-8 "$A")"
    nojobs; BASH=$STUB/newloop; run "" serve' 2>&1)
  ! grep -q '^stale on\|^run stale on\|^no merge' <<<"$out" && grep -qx "serve stale on $B" <<<"$out" \
    || fail "a serve from the checkout did not see its new commit alone, or a run from it did: $out"
  grep -qx "c7-7 on $B, c8-8 on $A" <<<"$out" || fail "the commit of a card in flight is not the one its last switch named, else the one it started on: $out"
  grep -qxF "conveyor: the checkout has moved on from this loop's $A; nothing new is picked, and the loop restarts on the checkout's new code once its push is done" <<<"$out" \
    && grep -qxF "conveyor: restarting on the new code; 0 cards in flight carry on on $A" <<<"$out" \
    && [ "$(cat "$STUB/newloop.args" 2>&1)" = "$D/conveyor/conveyor.sh serve" ] || fail "the loop did not restart on the checkout's new code, saying why: $out $(cat "$STUB/newloop.args" 2>&1)"
  # One real re-exec, for what only a loop's own process shows: the files it holds open (/proc, so Linux alone). Bug:
  # each restart kept its copy of stderr (LOGFD), so after some hundreds of restarts every card's test runner got fd
  # 255, bash's own, and its slot and lock cases failed. The case waits for the loop's word (loop.json, written each
  # turn) that it runs $A, then $B. copies: the fds of the loop open on its output, fewest of 5 looks (a builtin's
  # redirection holds one more for a moment).
  if [ -d /proc/self/fd ]; then
    git -C "$D" reset -q --hard "$A" || fail "the checkout was not put back on $A"
    tune '.tunables.idle = 1 | .tunables.poll = 1'; rm -f "$S/loop.json"
    mkdir -p "$ST/testactions/mutations" && git -C "$R" rev-parse HEAD > "$ST/testactions/mutations/idle" # the idle mutation check has nothing to do (mutate.test.sh)
    ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
      exec bash "$D/conveyor/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!
    on() { wait_until "[ \"\$(jq -r '\"\\(.pid) \\(.commit)\"' '$S/loop.json' 2>/dev/null)\" = '$pid $1' ]" "cat '$S/loop.json' '$STUB/serve.out'"; } # <commit>
    copies() { local f n m=''; for _ in 1 2 3 4 5; do n=0; for f in /proc/$pid/fd/*; do [ ! "$f" -ef "$STUB/serve.out" ] || n=$((n + 1)); done; [ -n "$m" ] && [ "$m" -le $n ] || m=$n; sleep 0.1; done; echo "$m"; } # sleep: samples the fd count over half a second, as a re-exec settles; nothing to wait for
    on "$A" || fail "the loop does not say it runs the commit it started on"; fds=$(copies)
    git -C "$D" merge -q --ff-only "$B" || fail "the new commit did not land in the checkout"
    on "$B" || fail "the loop did not restart on the checkout's new commit in its own process: $(cat "$STUB/serve.out")"
    [ "$(copies)" = "$fds" ] || fail "the restart kept a copy of the loop's stderr: $fds fds on its output before, $(copies) after"
    [ "$(grep -c restarting "$STUB/serve.out")" = 1 ] && [ "$(loop health | jq -r .commit)" = "$B" ] \
      || fail "the loop restarted more than once, or health does not name its new commit: $(cat "$STUB/serve.out") $(loop health | jq -c .commit)"
    loopend $pid
  fi
  # doctor warns of a running loop behind its checkout's HEAD, or, from an install, behind the pin; not of one on it.
  # It runs in main's checkout: from the case's folder, not a checkout, doctor stops before this check.
  sleep 60 & z=$!; t=$(p_started $z) # sleep: a stand-in for a running loop's process
  says() { jq -n --argjson p "$z" --arg t "$t" --arg c "$1" --arg h "$2" '{pid: $p, started: $t, state: "running", commit: $c, checkout: (if $h == "" then null else $h end)}' > "$S/loop.json"; }
  says "$A" "$D"; out=$(cd "$R" && loop doctor 2>&1)
  grep -qx "warning: the running loop started on Conveyor commit $A, and its checkout is at $B: it runs old code until it restarts" <<<"$out" \
    || fail "doctor did not warn of a loop behind its checkout: $out"
  says "$B" "$D"; out=$(cd "$R" && loop doctor 2>&1); ! grep -q '^warning: the running loop' <<<"$out" || fail "doctor warned of a loop on its checkout's HEAD: $out"
  ln -s "$D" "$T/$CASE/code\\repo"; says "$A" "$T/$CASE/code\\repo"; out=$(cd "$R" && loop doctor 2>&1)
  grep -qx "warning: the running loop started on Conveyor commit $A, and its checkout is at $B: it runs old code until it restarts" <<<"$out" \
    || fail "doctor did not warn of a loop behind a checkout whose path holds a backslash: $out"
  tune --arg c "$B" '.plugin.commit = $c'; says "$A" ''; out=$(cd "$R" && loop doctor 2>&1)
  grep -qx "warning: the running loop started on Conveyor commit $A, and the pack pins $B: it runs old code until it restarts" <<<"$out" \
    || fail "doctor did not warn of a loop behind the pin: $out"
}

# The pushes of serve and run (t_serve, t_serverun, t_servebatch), each a case of its own on a main of its own: no
# issue yet, a pushed b.txt that main's checkout then edits (a tracked file no card touches), the repo's pre-push rules.
servesetup() {
  setup '[]'; S=$ST; O=$T/$CASE/origin; for i in $(seq 10); do echo "$GO" > "$STUB/review.$i"; done
  # Bug: the push sets a variable of its own, not the pack's push.env: here the pack names another.
  tune '.push.env = {"OTHER_ALLOW_PUSH": "yes"}'; echo mine > "$R/b.txt"; git -C "$R" add -A; git -C "$R" commit -qm b; git -C "$R" push -q origin main
  # The repo's own pre-push rules: the checks read the checkout the push is made from, so it must be the pushed commit
  # with no tracked edit; a linked worktree may push only with the override the pack's push.env sets.
  cat > "$R/.git/hooks/pre-push" <<'EOF'
#!/usr/bin/env bash
read -r ref sha rest; echo "$sha" >> "$STUB/hookruns"
[ "$(git rev-parse "$sha^{tree}")" = "$(git rev-parse 'HEAD^{tree}')" ] || { echo "BLOCKED -- $ref is not the tree checked out" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "BLOCKED -- uncommitted tracked changes" >&2; exit 1; }
[ -z "${SAMPLE_ALLOW_WORKTREE_PUSH+x}" ] || { echo "BLOCKED -- a variable the pack does not name" >&2; exit 1; }
[ "${OTHER_ALLOW_PUSH:-}" = yes ] || [ "$(git rev-parse --absolute-git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
  || { echo "BLOCKED -- publishing from a linked worker checkout" >&2; exit 1; }
[ ! -e "$STUB/push-fail" ] || { echo "BLOCKED -- the fast checks are red" >&2; echo "push-checks: FAILED fast-checks" >&2; exit 1; }
echo "$sha" >> "$STUB/pushes"
EOF
  chmod +x "$R/.git/hooks/pre-push"; echo edit >> "$R/b.txt"
  add() { jq -c ". + [$(issue "$1" 2026-01-01)]" "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"; }
  mainat() { git -C "$R" rev-parse refs/heads/main; }; originat() { git -C "$O" rev-parse refs/heads/main; }
  handfix() { echo "$1" > "$R/fix.txt"; git -C "$R" add fix.txt; git -C "$R" commit -qm "$1"; } # <text>: a fix landed on main by hand: main moves
  # What is left in the cards folder (a push worktree, say), less what the per-file fixture (lib.sh filemode()) brings
  # there: the <card>.testlist each landed card leaves (tidy() does not remove it), and the mutate folder of the idle
  # mutation checks (lib/mutate.sh) that `serve` runs on its test file a.test.sh.
  left() { local f; for f in "$T/$CASE/cards"/*; do [ -e "$f" ] && [[ $f != *.testlist && $f != */mutate ]] && echo "${f##*/}"; done; }
  landed7() { st "select(.issue == $1 and .step == \"landed\") | .card"; }; fails() { st 'select(.step == "push" and .result == "fail") | .card' | wc -l; }
}
# In eng(): run()'s push variables as a new loop sets them (a retry time of 600 s), and push() a stub that adds
# "<card> <issue> <its own pid>" to $STUB/pushcalls in place of a push. turn: one turn's push decision (pushturn(),
# lib/push.sh); a push it starts has ended by the next turn, as run() sees at a turn's top.
# shellcheck disable=SC2034 # nopack, new, tried, triedat and PUSH_RETRY are read by pushturn(), from the sourced lib/push.sh
pushstub() { nopack='' new='' pusher='' tried='' triedat=0 PUSH_RETRY=600; : > "$STUB/pushcalls"; push() { echo "$* $BASHPID" >> "$STUB/pushcalls"; }; }
turn() { pushturn; [ -z "$pusher" ] || wait "$pusher"; pusher=''; }

# Bugs: `serve` ends when no issue qualifies; a second `serve` runs beside a loop; a landing is not pushed; the push
# is made from main's checkout, so the pre-push check refuses it for an edit there that the card never touched, or is
# let through by skipping the check; a failed push leaves no line, or is not tried again after the next landing; one
# that failed its check is tried again on the same main, at once or on the retry timer; one the remote refused is not
# tried again at once by a new loop, or is tried at every turn, or never on the retry timer; a push line breaks the
# record check or turns a landed card's dashboard row back into an open one. Each landing is one `run` in the
# foreground; when a push is tried again is the loop's push decision (pushturn), called at the turns of a new loop.
t_serve() {
  servesetup; tune '.tunables += {idle: 1, poll: 1}'
  # An idle serve takes its turns and does not end: the KILL of servefor ends it (137), not its own exit.
  eng "$SRC" 'servefor 2' > "$STUB/serve.out" 2>&1; rc=$?
  [ "$rc" = 137 ] && [ ! -s "$S/cards.jsonl" ] || fail "an idle serve ended ($rc), or recorded something: $(cat "$STUB/serve.out")"
  # A loop holds the run lock (fd 8): a serve beside it is refused.
  out=$( { flock -n 9 || exit 9; loop serve 9>&- 2>&1; } 9>>"$S/cards.jsonl.run") && fail "a second serve ran beside a loop"
  grep -q 'already running' <<<"$out" || fail "a second serve beside a loop was not refused as one: $out"
  add 7; loop run > "$STUB/run.out" 2>&1 || fail "the run that lands #7 failed: $(cat "$STUB/run.out")"
  [ -n "$(landed7 7)" ] && [ "$(originat)" = "$(mainat)" ] || fail "the landing was not pushed: $(cat "$S/cards.jsonl" "$STUB/run.out")"
  [ "$(cat "$STUB/pushes")" = "$(st 'select(.step == "landed") | .sha')" ] && [ "$(fails)" = 0 ] && [ "$(cat "$S/pushed")" = "$(mainat) origin main" ] \
    || fail "the push did not pass the pre-push check once, with no push line: $(cat "$S/cards.jsonl")"
  [ "$(git -C "$R" status --porcelain)" = ' M b.txt' ] || fail "main's own edit was disturbed: $(git -C "$R" status --porcelain)"
  # The push fails: a push line under the card that landed, with the commit and the reason; origin stays behind.
  : > "$STUB/push-fail"; at=$(originat); add 8
  loop run > "$STUB/run.out" 2>&1 && fail "a run whose push failed exited zero: $(cat "$STUB/run.out")"
  [ "$(fails)" = 1 ] && [ "$(st 'select(.step == "push") | [.card, .sha, (.reason | test("the fast checks are red"))] | join(" ")')" = "$(landed7 8) $(mainat) true" ] \
    && [ "$(originat)" = "$at" ] || fail "push line of a failed push: $(st 'select(.step == "push")')"
  # The next landing brings the next try; it fails too, under that card.
  add 9; loop run > "$STUB/run.out" 2>&1 && fail "a run whose push failed again exited zero: $(cat "$STUB/run.out")"
  [ "$(fails)" = 2 ] && [ "$(st 'select(.step == "push") | .card' | tail -n 1)" = "$(landed7 9)" ] && [ -n "$(landed7 9)" ] && [ -z "$(left)" ] \
    || fail "the failed push was not tried again after the next landing, under that card, or the push worktree is left: $(fails) push lines; $(left)"
  # Main stays at the commit whose push failed its check: a new loop's turn does not try it again, at once or once
  # the retry time has passed, though it is the push owed (tried).
  out=$(eng "$SRC" 'pushstub; turn; triedat=$((SECONDS - PUSH_RETRY)); turn; echo "$tried"')
  [ ! -s "$STUB/pushcalls" ] && [ "$out" = "$(landed7 9) 9 $(mainat)" ] || fail "a push that failed its check was tried again on the same main: $out; $(cat "$STUB/pushcalls")"
  # The remote refuses the next landing's push (its own hook: transport, not a check): recorded so, under that card.
  rm "$STUB/push-fail"; printf '#!/bin/sh\necho "the server is busy" >&2; exit 1\n' > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"; add 10
  loop run > "$STUB/run.out" 2>&1 && fail "a run whose push the remote refused exited zero: $(cat "$STUB/run.out")"
  [ "$(fails)" = 3 ] && [ "$(st 'select(.step == "push") | .kind' | tail -n 1)" = transport ] && [ "$(st 'select(.step == "push") | .card' | tail -n 1)" = "$(landed7 10)" ] \
    || fail "a push the remote refused is not recorded as transport under the card that landed: $(st 'select(.step == "push") | [.card, .kind]')"
  # A new loop tries it at once, not at its next turn, and again once the retry time has passed: the first two turns
  # each end with a line T, so a try at the second turn in place of the third is seen.
  eng "$SRC" 'pushstub; turn; echo T >> "$STUB/pushcalls"; turn; echo T >> "$STUB/pushcalls"; triedat=$((SECONDS - PUSH_RETRY)); turn'
  [ "$(cut -d' ' -f1,2 "$STUB/pushcalls" | paste -sd,)" = "$(landed7 10) 10,T,T,$(landed7 10) 10" ] \
    || fail "a push the remote refused was not tried at once by a new loop and then only on its retry timer: $(cat "$STUB/pushcalls")"
  rm "$O/hooks/pre-receive"; n=$(fails); loop run > "$STUB/run.out" 2>&1 || fail "the push did not go through once it could: $(cat "$STUB/run.out")"
  [ "$(originat)" = "$(mainat)" ] && [ "$(fails)" = "$n" ] && [ "$(tail -n 1 "$STUB/pushes")" = "$(mainat)" ] || fail "the push that worked left a push line, or did not pass the pre-push check"
  loopend
  loop check || fail "the record check refuses a push line"
  [ "$(loop cards | jq -c '[.landed, .open, (.cards | map("\(.step) \(.stage)") | unique)]')" = '[4,0,["landed 5"]]' ] || fail "a push line changed a landed card's dashboard row: $(loop cards)"
  CONVEYOR_MAIN=$R bash "$SRC/report.sh" | grep -Eq '^cards landed +4$' || fail "the report miscounts cards that hold a push line"
}

# Why a push failed, from git's trace2 events of it (lib/push.sh hookfailed()): its pre-push hook exited non-zero, or
# not (no hook ran: the remote could not be reached). Bug: a check that runs git push in a test of its own, under a
# hook that fails, writes its events to the same file; read as the push's own, a push whose checks passed and that the
# remote refused would be held as a failed check, never tried again.
t_pushkind() {
  local d=$T/$CASE; mkdir -p "$d"; eval "$(sed -n '/^hookfailed() {/,/^}/p' "$SRC/lib/push.sh")"
  git init -q --bare "$d/o.git"; for r in r inner; do git init -q "$d/$r"; git -C "$d/$r" commit -q --allow-empty -m a; done
  printf '#!/bin/sh\nexit 1\n' > "$d/inner/.git/hooks/pre-push"
  printf '#!/bin/sh\nenv -u GIT_DIR git -C "%s/inner" push -q "%s/o.git" HEAD:refs/heads/inner 2>/dev/null && exit 1\n[ ! -e "%s/fail" ]\n' "$d" "$d" "$d" > "$d/r/.git/hooks/pre-push"
  chmod +x "$d/inner/.git/hooks/pre-push" "$d/r/.git/hooks/pre-push"
  GIT_TRACE2_EVENT=$d/pass git -C "$d/r" push -q "$d/o.git" HEAD:refs/heads/main 2>/dev/null || fail "the push whose own hook passes failed"
  [ "$(grep -c '"hook_name":"pre-push"' "$d/pass")" = 2 ] || fail "the nested push's failing hook is not in the trace, so this case proves nothing"
  ! hookfailed "$d/pass" || fail "a push whose own hook passed is taken for a failed check, for a hook that failed in a push its check made"
  : > "$d/fail"; GIT_TRACE2_EVENT=$d/fail git -C "$d/r" push -q "$d/o.git" HEAD:refs/heads/next 2>/dev/null && fail "the push whose hook fails went through"
  hookfailed "$d/fail" || fail "a push whose own hook failed is not taken for a failed check"
  GIT_TRACE2_EVENT=$d/gone git -C "$d/r" push -q "$d/nowhere" HEAD:refs/heads/main 2>/dev/null && fail "a push to no repository went through"
  ! hookfailed "$d/gone" && ! hookfailed "$d/none" || fail "a push that never reached its hook, or one with no trace, is taken for a failed check"
}

# `run` pushes its landings too: a failed push leaves its line and a failing exit, and the next run pushes first (one
# whose check failed, once main has moved).
t_serverun() {
  servesetup; : > "$STUB/push-fail"; at=$(originat); add 10
  out=$(loop run 2>&1) && fail "a run whose push failed exited zero: $out"
  grep -q 'is not pushed' <<<"$out" && [ "$(fails)" = 1 ] && [ "$(st 'select(.step == "push") | .card' | tail -n 1)" = "$(landed7 10)" ] \
    && [ -n "$(landed7 10)" ] && [ "$(originat)" = "$at" ] || fail "a run's failed push was not recorded under its card: $out $(st 'select(.step == "push")')"
  # Bug: a push that failed its check was not told from one git or the remote failed, so it waited 10 minutes to be
  # raised. It is recorded as a check failure naming the check, and health, Needs you and the belt say so at once.
  [ "$(st 'select(.step == "push") | "\(.kind) \(.check)"')" = "check fast-checks" ] || fail "a failed check is not recorded as one: $(st 'select(.step == "push")')"
  [ "$(loop health | jq -c '.pushError | [.kind, .check, .issue]')" = '["check","fast-checks",10]' ] || fail "health does not say the push failed its check: $(loop health | jq -c .pushError)"
  s=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq -c '[(.needsYou.blocked[] | select(.push) | [.check, (.reason | startswith("push blocked: fast-checks failed after #10. A retry will fail too")), (.tail | test("FAILED fast-checks"))]),
      (.belt | map(.track.label))]' <<<"$s")" = '[["fast-checks",true,true],["push failed its check; tried again once main moves"]]' ] \
    || fail "Needs you or the belt does not show the failed check at its first failure: $(jq -c '[.needsYou.blocked, (.belt | map(.track.label))]' <<<"$s")"
  # The check would pass now, but main has not moved: the next run does not run it again, and still says main is not pushed.
  rm "$STUB/push-fail"; n=$(wc -l < "$STUB/hookruns")
  out=$(loop run 2>&1) && fail "a run that left its push owed exited zero: $out"
  [ "$(wc -l < "$STUB/hookruns")" = "$n" ] && [ "$(fails)" = 1 ] && [ "$(originat)" = "$at" ] && grep -q 'is not pushed' <<<"$out" \
    || fail "a push that failed its check was run again on the same main: $out"
  # A fix lands on main: the next run pushes as usual.
  handfix 'the fast checks pass'; loop run > /dev/null 2>&1 || fail "a run with only an owed push to make failed once main moved"
  [ "$(originat)" = "$(mainat)" ] && [ "$(tail -n 1 "$STUB/pushes")" = "$(mainat)" ] && [ "$(fails)" = 1 ] && [ -z "$(left)" ] \
    || fail "the next run did not push the owed landing through the pre-push check once main moved, or left $(left)"
  loopend
}

# One push carries three landings, and GitHub keeps the issue of the first of them open. The three are
# asked about in turn under one wait: the other two have their issue line at once, not after the first one's wait
# (asked one after the other, the last card of a long batch was dropped from the belt before its answer came).
t_servebatch() {
  servesetup; : > "$STUB/push-fail"; add 11; add 12; add 13; loop run > /dev/null 2>&1; rm "$STUB/push-fail"; handfix 'the checks pass' # main moves, so the push is made again
  [ "$(st 'select(.step == "landed" and .issue > 10) | .issue' | wc -l)" = 3 ] || fail "three cards did not land for the batch: $(st 'select(.issue > 10) | "\(.issue) \(.step)"' | tr '\n' ,)"
  open=$(st 'select(.step == "landed" and .issue > 10) | .issue' | head -n 1); echo OPEN > "$STUB/state.$open"
  tuned '.tunables.closeWait = 6' loop run > /dev/null 2>&1 || fail "the run that pushes the batch failed"
  [ "$(st 'select(.step == "pushed" and .issue > 10) | .issue' | wc -l)" = 3 ] || fail "the batch push did not mark its three cards pushed"
  [ "$(jq -cs --argjson o "$open" 'map(select(.issue > 10 and (.step | IN("pushed", "issue")))) | (map(select(.step == "pushed") | .time | fromdate) | max) as $p
      | map(select(.step == "issue")) | [(map(.result) | join(" ")), (.[2].issue == $o), (.[2].reason | test("still shows the issue open")), (.[:2] | all((.time | fromdate) - $p < 4)), ((.[2].time | fromdate) - $p >= 5)]' "$S/cards.jsonl")" \
    = '["ok ok fail",true,true,true,true]' ] || fail "the issue checks of a batch push were not made in turn under one wait: $(st 'select(.issue > 10 and (.step | IN("pushed", "issue"))) | "\(.issue) \(.step) \(.result) \(.time) \(.reason)"' | tr '\n' ,)"
  loopend
}

# Bugs: the loop waits for a push before it picks the next card; two landings during one push bring two more
# pushes, or a push is started beside one already running; health does not say a push is in progress and since when;
# a `run` with nothing left to build ends before its last push has ended. The loop's own run() (cap 1, #7 to #9
# queued), in eng(), with card() a stub that lands its issue on main at once and push() one held until #9 lands:
# run() picks, pushes and ends from its own turn order, inline in it, which no call of one function shows. The last
# push (#9's) is held until run() has begun a turn after it started (each turn's packturn() writes a line to
# $STUB/turns): a run that ends without waiting for it takes no such turn, and says "returned" before "end 9". Each
# step is a line of $STUB/order; a hold not met within 20 s says "timeout" there.
t_slowpush() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-01-02) <(issue 9 2026-01-03))"; loop control cap 1 >/dev/null
  tune '.tunables.poll = 1' # a turn a second while a push runs: the hold of the last push counts them
  eng "$SRC" 'till() { for _ in $(seq 200); do ! eval "$1" || return 0; sleep 0.1; done; echo timeout >> "$STUB/order"; }
    eval "orig_$(declare -f packturn)"; packturn() { orig_packturn; echo >> "$STUB/turns"; }; : > "$STUB/turns"
    card() { echo "$2" > "$R/f$2"; git -C "$R" add -A; git -C "$R" commit -qm "$2"
      [ "$2" != 8 ] || till "[ -e \"\$STUB/inpush\" ]"
      echo "pick $2" >> "$STUB/order"; record "$1" "$2" landed ok "$(jq -cn --arg s "$(git -C "$R" rev-parse HEAD)" "{sha: \$s, product: false}")"
      [ "$2" != 9 ] || { loop health > "$STUB/health"; loop snapshot --fresh > "$STUB/snapshot" 2>/dev/null; : > "$STUB/go"; }; }
    push() { echo "start $2" >> "$STUB/order"; [ ! -e "$STUB/inpush" ] || echo beside >> "$STUB/order"; : > "$STUB/inpush"; pushing "${owed##* }"
      till "[ -e \"\$STUB/go\" ]"; t=$(wc -l < "$STUB/turns"); [ "$2" != 9 ] || till "[ \$(wc -l < \"\$STUB/turns\") -gt $t ]"
      git -C "$R" push -q --no-verify origin "${owed##* }:refs/heads/main"; rm -f "$STUB/inpush"; echo "end $2" >> "$STUB/order"; }
    (run) > "$STUB/run.out" 2>&1; echo "returned $?" >> "$STUB/order"'
  [ "$(paste -sd, "$STUB/order")" = "pick 7,start 7,pick 8,pick 9,end 7,start 9,end 9,returned 0" ] \
    || fail "the loop did not pick during a push, join the landings made during it into one push of main's head, and wait for that push: $(paste -sd, "$STUB/order"); $(cat "$STUB/run.out")"
  first=$(st 'select(.issue == 7 and .step == "landed") | .sha')
  [ "$(jq -c '[.pushing.sha, (.pushing.since | fromdate <= now), (.unpushed | length)]' "$STUB/health")" = "[\"$first\",true,3]" ] \
    || fail "health does not report the push in progress: $(jq -c '[.pushing, .unpushed]' "$STUB/health")"
  [ "$(jq -c '[.health.pushing.sha, (.belt | map(.track.label) | unique)]' "$STUB/snapshot")" = "[\"$first\",[\"pushing\"]]" ] \
    || fail "the snapshot does not report the push in progress: $(jq -c '[.health.pushing, (.belt | map(.track.label))]' "$STUB/snapshot")"
}

# Bugs: the remote's main holds a commit the Conveyor's main lacks (landed there by hand), so every push is refused
# and no retry can work: the landings stack up unpushed, and nothing tells the owner. A refused push merges the
# remote's commits into main and pushes again; one that cannot (they conflict) and fails again on the next try is in
# Needs you, with git's error and the cards not pushed, until a push works.
t_pushmerge() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"; O=$T/$CASE/origin; H=$T/$CASE/hand; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  mainat() { git -C "$R" rev-parse refs/heads/main; }; originat() { git -C "$O" rev-parse refs/heads/main; }
  fails() { st 'select(.step == "push" and .result == "fail") | .card' | wc -l; }
  pushitem() { loop snapshot --fresh 2>/dev/null | jq -c '[.needsYou.blocked[] | select(.push)]'; }
  # Bug: the fetch of the remote's commits is made without the pack's push.env, so a remote reached only with what
  # it sets (an ssh identity) refuses it. Here the remote's side of every fetch writes down the variable it was given.
  P=$R/.conveyor/project.json; jq '.push.env = {"PUSH_AS": "pusher"}' "$P" > "$P.new" && mv "$P.new" "$P"
  printf '%s\n' '#!/usr/bin/env bash' "echo \"\${PUSH_AS:-none}\" >> '$STUB/fetches'" 'exec git-upload-pack "$@"' > "$STUB/up"; chmod +x "$STUB/up"
  git -C "$R" config remote.origin.uploadpack "$STUB/up"
  # By hand, from another clone: a commit to a file the card does not touch.
  git clone -q "$O" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main; hand=$(originat)
  out=$(loop run 2>&1) || fail "the run whose push the remote refused at first failed: $out $(st 'select(.step == "push")')"
  l7=$(st 'select(.step == "landed") | .sha')
  [ "$(originat)" = "$(mainat)" ] && git -C "$O" merge-base --is-ancestor "$hand" main && git -C "$O" merge-base --is-ancestor "$l7" main \
    || fail "the remote does not hold both the commit made by hand and the landing: $(git -C "$O" log --oneline main)"
  [ "$(st 'select(.step == "pushed") | [.issue, .sha, .head] | join(" ")')" = "7 $l7 $(mainat)" ] && [ "$(fails)" = 0 ] \
    || fail "the card is not recorded pushed by the push of the merge: $(st 'select(.step | IN("push", "pushed"))')"
  [ "$(cat "$R/c.txt")" = hand ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ "$(loop health | jq -c '[.unpushed, .pushFails]')" = '[[],0]' ] \
    || fail "main's checkout lags the merge, or health still lists the landing: $(git -C "$R" status --porcelain) $(loop health | jq -c '[.unpushed, .pushFails]')"
  grep -qx pusher "$STUB/fetches" || fail "the fetch of the remote's commits was not given the pack's push.env: $(cat "$STUB/fetches" 2>&1)"
  # By hand again, now the line the next card adds too: the two do not merge. The push fails with git's conflict;
  # one failure is the belt's "tried again", not yet the owner's.
  git -C "$H" pull -q; echo other >> "$H/a.txt"; git -C "$H" commit -qam 'by hand, the same line'; git -C "$H" push -q origin main; hand=$(originat)
  jq -c ". + [$(issue 8 2026-01-02)]" "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  out=$(loop run 2>&1) && fail "a run whose push could not be merged exited zero: $out"
  c8=$(st 'select(.step == "landed" and .issue == 8) | .card'); l8=$(st 'select(.step == "landed" and .issue == 8) | .sha')
  [ -n "$c8" ] && [ "$(fails)" = 1 ] && [ "$(mainat)" = "$l8" ] && [ "$(originat)" = "$hand" ] && [ "$(pushitem)" = '[]' ] \
    || fail "a merge that conflicts moved main or the remote, or its first failure is in Needs you already: $(st 'select(.step == "push")') $(pushitem)"
  # The next try fails the same way: the push is a blocked item of Needs you, and health lists the card not pushed.
  out=$(loop run 2>&1) && fail "the retry of a push that cannot be merged exited zero: $out"
  snap=$(loop snapshot --fresh 2>/dev/null)
  [ "$(fails)" = 2 ] && [ "$(jq -c '[.needsYou.blocked[] | select(.push) | [.card, .issue, .reason, (.tail | test("CONFLICT.*a\\.txt")), .unpushed]]' <<<"$snap")" \
    = "[[\"$c8\",8,\"the push of main keeps failing. Not pushed: #8\",true,[{\"card\":\"$c8\",\"issue\":8}]]]" ] \
    || fail "a push that failed again is not a blocked item with git's error and the card not pushed: $(jq -c '.needsYou.blocked | map({card, reason, tail})' <<<"$snap")"
  [ "$(jq -c '[(.health.unpushed | map([.card, .sha])), .health.pushFails]' <<<"$snap")" = "[[[\"$c8\",\"$l8\"]],2]" ] \
    || fail "health does not list the card not pushed: $(jq -c '.health | [.unpushed, .pushFails]' <<<"$snap")"
  # The owner merges by hand: the next push works, and the item is gone.
  git -C "$R" merge -q -s ours -m 'merge by hand' origin/main; loop run > /dev/null 2>&1 || fail "the push after the owner's merge failed: $(st 'select(.step == "push")')"
  [ "$(originat)" = "$(mainat)" ] && [ "$(pushitem)" = '[]' ] && [ "$(loop health | jq -c '[.unpushed, .pushFails]')" = '[[],0]' ] \
    || fail "a push that worked left the push in Needs you: $(pushitem)"
  # Bug: the merge is committed past main's commit hooks, which every landing answers to. Here main's commit-msg hook
  # refuses a merge's message: the remote's commit merges, but no merge commit is made, and the push line says why.
  git -C "$H" pull -q; echo hand > "$H/d.txt"; git -C "$H" add d.txt; git -C "$H" commit -qm 'by hand, a third'; git -C "$H" push -q origin main; hand=$(originat)
  printf '%s\n' '#!/usr/bin/env bash' '! grep -q "^Merge " "$1" || { echo "no merge commits here"; exit 1; }' > "$R/.git/hooks/commit-msg"; chmod +x "$R/.git/hooks/commit-msg"
  echo "$GO" > "$STUB/review.3"; jq -c ". + [$(issue 9 2026-01-03)]" "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  out=$(loop run 2>&1) && fail "a run whose merge main's commit-msg hook refuses exited zero: $out"
  l9=$(st 'select(.step == "landed" and .issue == 9) | .sha')
  [ -n "$l9" ] && [ "$(mainat)" = "$l9" ] && [ "$(originat)" = "$hand" ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    && [[ $(st 'select(.step == "push" and .result == "fail") | .reason' | tail -n 1) == *"commit of the merge refused: no merge commits here"* ]] \
    || fail "a merge main's commit-msg hook refuses was made, or the push line does not say it was refused: $(git -C "$R" log --oneline -3 main) $(st 'select(.step == "push")' | tail -n 1)"
  loopend
}

# Bugs: the remote pushes to other URLs than the one it fetches from (remote.origin.pushurl), and the commit that
# refuses the push is only at one the push goes to: the fetch after the refusal reads the fetch URL, or the first push
# URL alone, finds nothing main lacks, and the push keeps failing though the two merge cleanly. The remote's commits
# are fetched from every URL the push went to.
t_pushurl() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"; O=$T/$CASE/origin; B=$T/$CASE/first.git; C=$T/$CASE/second.git; H=$T/$CASE/hand; echo "$GO" > "$STUB/review.1"
  git clone -q --bare "$O" "$B"; git clone -q --bare "$O" "$C"; was=$(git -C "$O" rev-parse refs/heads/main)
  git -C "$R" config remote.origin.pushurl "$B"; git -C "$R" config --add remote.origin.pushurl "$C"
  # The remote names the program that serves its fetches (one of these may need its own): it notes what it served.
  printf '#!/bin/sh\necho "$1" >> "%s/served"\nexec git-upload-pack "$@"\n' "$T/$CASE" > "$T/$CASE/serve"; chmod +x "$T/$CASE/serve"
  git -C "$R" config remote.origin.uploadpack "'$T/$CASE/serve'"
  # Bug: the repository has a remote of the name the fetch is made under, so its URL (the fetch URL) is read instead.
  git -C "$R" config remote.conveyor-pushed.url "$O"; git -C "$R" config remote.conveyor-pushed.uploadpack false
  # By hand, to the second of the two only: a commit to a file the card does not touch.
  git clone -q "$C" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main
  hand=$(git -C "$C" rev-parse refs/heads/main)
  out=$(loop run 2>&1) || fail "the run whose push the second push URL refused at first failed: $out $(st 'select(.step == "push")')"
  l7=$(st 'select(.step == "landed") | .sha')
  for x in "$B" "$C"; do
    [ "$(git -C "$x" rev-parse refs/heads/main)" = "$(git -C "$R" rev-parse refs/heads/main)" ] && git -C "$x" merge-base --is-ancestor "$hand" main \
      && git -C "$x" merge-base --is-ancestor "$l7" main && [ "$(cat "$R/c.txt")" = hand ] \
      || fail "$x, where pushes go, does not hold both the commit made by hand and the landing: $(git -C "$x" log --oneline main) $(st 'select(.step == "push")')"
  done
  [ "$(st 'select(.step == "push" and .result == "fail") | .card' | wc -l)" = 0 ] && [ "$(git -C "$O" rev-parse refs/heads/main)" = "$was" ] \
    || fail "the push failed first, or went to the URL the remote fetches from: $(st 'select(.step == "push")')"
  grep -qxF "$C" "$T/$CASE/served" || fail "the push URL was not fetched with the remote's own uploadpack: $(cat "$T/$CASE/served" 2>&1)"
  loopend
}

# Bugs: the remote has two URLs and pushes to both (no pushurl, or the same list again), and the commit that refuses
# the push is at the second: the fetch after the refusal is made by the remote's name, which reads its first URL
# alone, finds nothing main lacks, and the push keeps failing though the two merge cleanly. Every URL is fetched.
t_pushurls() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"; O=$T/$CASE/origin; C=$T/$CASE/second.git; H=$T/$CASE/hand; echo "$GO" > "$STUB/review.1"
  git clone -q --bare "$O" "$C"; git -C "$R" config --add remote.origin.url "$C"
  git -C "$R" config remote.origin.pushurl "$O"; git -C "$R" config --add remote.origin.pushurl "$C"
  git clone -q "$C" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main
  hand=$(git -C "$C" rev-parse refs/heads/main)
  out=$(loop run 2>&1) || fail "the run whose push the remote's second URL refused at first failed: $out $(st 'select(.step == "push")')"
  l7=$(st 'select(.step == "landed") | .sha')
  for x in "$O" "$C"; do
    [ "$(git -C "$x" rev-parse refs/heads/main)" = "$(git -C "$R" rev-parse refs/heads/main)" ] && git -C "$x" merge-base --is-ancestor "$hand" main \
      && git -C "$x" merge-base --is-ancestor "$l7" main && [ "$(cat "$R/c.txt")" = hand ] \
      || fail "$x, where pushes go, does not hold both the commit made by hand and the landing: $(git -C "$x" log --oneline main) $(st 'select(.step == "push")')"
  done
  [ "$(st 'select(.step == "push" and .result == "fail") | .card' | wc -l)" = 0 ] || fail "the push failed first: $(st 'select(.step == "push")')"
  loopend
}

# Bugs: the push URL is set by the pack's push.env alone (git's GIT_CONFIG_* variables), and is a path relative to the
# folder the push is made from: the fetch after a refused push looks the URL up without push.env and reads the fetch
# URL, or takes the path from main's checkout and reads another folder, so a commit only where the push goes is
# never merged. The URL is looked up, and fetched, as the push is made: under push.env, from the push worktree.
t_pushurlenv() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"; O=$T/$CASE/origin; B=$T/$CASE/pushed.git; H=$T/$CASE/hand; echo "$GO" > "$STUB/review.1"
  git clone -q --bare "$O" "$B"; was=$(git -C "$O" rev-parse refs/heads/main)
  # From the push worktree ($T/$CASE/cards/push) the path is $B; from main's checkout it is no repository.
  P=$R/.conveyor/project.json; jq '.push.env = {GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "remote.origin.pushurl", GIT_CONFIG_VALUE_0: "../../pushed.git"}' "$P" > "$P.new" && mv "$P.new" "$P"
  git clone -q "$B" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main
  hand=$(git -C "$B" rev-parse refs/heads/main)
  out=$(loop run 2>&1) || fail "the run whose push the push URL of push.env refused at first failed: $out $(st 'select(.step == "push")')"
  l7=$(st 'select(.step == "landed") | .sha')
  [ "$(git -C "$B" rev-parse refs/heads/main)" = "$(git -C "$R" rev-parse refs/heads/main)" ] && git -C "$B" merge-base --is-ancestor "$hand" main \
    && git -C "$B" merge-base --is-ancestor "$l7" main && [ "$(cat "$R/c.txt")" = hand ] \
    || fail "where pushes go does not hold both the commit made by hand and the landing: $(git -C "$B" log --oneline main) $(st 'select(.step == "push")')"
  [ "$(st 'select(.step == "push" and .result == "fail") | .card' | wc -l)" = 0 ] && [ "$(git -C "$O" rev-parse refs/heads/main)" = "$was" ] \
    || fail "the push failed first, or went to the URL the remote fetches from: $(st 'select(.step == "push")')"
  loopend
}

# Bugs: the health record misses a blocked card, a card waiting on the owner's yes, an open card with no new step,
# a landed commit that is not pushed or its push error; lists a pushed commit, a fresh card or an old push error as a
# problem; says a loop runs when none does (or the other way), or that gh is signed in when it is not.
t_health() {
  setup '[]'; S=$ST; mkdir -p "$S"
  rec() { # <card> <issue> <step> <time> <result> [extra json]
    jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --arg t "$4" --arg r "$5" --argjson x "${6:-{\}}" \
      '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x' >> "$S/cards.jsonl"
  }
  h() { loop health | jq -c "$1"; }
  [ "$(h '[.loop, .newest, .blocked, .waiting, .stuck, .unpushed, .pushError, .pushFailingSince, .gh, (.diskFreeKb > 0), (.time | fromdate > 0)]')" \
    = '[false,null,[],[],[],[],null,null,true,true,true]' ] || fail "the health record of an empty belt: $(loop health)"
  pushed=$(git -C "$R" rev-parse HEAD); echo x > "$R/n.txt"; git -C "$R" add n.txt; git -C "$R" commit -qm next; ahead=$(git -C "$R" rev-parse HEAD)
  old=2026-11-01T00:00:00Z; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  rec c1-1 1 picked $old ok; rec c1-1 1 blocked 2026-11-01T00:05:00Z blocked '{"reason":"review 1: no answer","kept":""}'
  rec c2-2 2 picked $old ok; rec c2-2 2 review $old GO '{"visible":"yes: a new button"}'
  rec c2-2 2 blocked 2026-11-01T00:06:00Z blocked '{"reason":"visible to customers or staff: needs Dana'"'"'s yes: a new button","kept":""}'
  rec c3-3 3 picked $old ok; rec c3-3 3 worktree 2026-11-01T00:07:00Z ok
  rec c4-4 4 picked "$now" ok
  rec c5-5 5 picked $old ok; rec c5-5 5 landed 2026-11-01T00:01:00Z ok "{\"sha\":\"$pushed\",\"product\":false}"
  rec c5-5 5 push 2026-11-01T00:02:00Z fail "{\"sha\":\"$pushed\",\"reason\":\"an old failure\"}"
  rec c6-6 6 picked $old ok; rec c6-6 6 landed 2026-11-01T00:08:00Z ok "{\"sha\":\"$ahead\",\"product\":false}"
  [ "$(h '[.unpushed, .pushError, .pushFailingSince]')" = "[[{\"card\":\"c6-6\",\"issue\":6,\"sha\":\"$ahead\",\"since\":\"2026-11-01T00:08:00Z\"}],null,null]" ] \
    || fail "a landed commit origin lacks is not the one unpushed commit, or an older push failure counts against it: $(loop health)"
  rec c6-6 6 push 2026-11-01T00:09:00Z fail "{\"sha\":\"$ahead\",\"reason\":\"first\"}"; rec c6-6 6 push "$now" fail "{\"sha\":\"$ahead\",\"reason\":\"the fast checks are red\",\"kind\":\"check\",\"check\":\"fast-checks\"}"
  : > "$STUB/signed-out"; ( exec 8>>"$S/cards.jsonl.run"; flock 8; exec sleep 60 ) & lk=$! # sleep: a stand-in that holds the run lock until it is killed
  while kill -0 $lk 2>/dev/null && flock -n "$S/cards.jsonl.run" true; do sleep 0.05; done # until it holds the run lock
  out=$(loop health); kill $lk; wait $lk 2>/dev/null
  [ "$(jq -c '[.loop, .gh, .newest, .pushFailingSince, .pushError]' <<<"$out")" = "[true,false,\"$now\",\"2026-11-01T00:09:00Z\",{\"time\":\"$now\",\"sha\":\"$ahead\",\"reason\":\"the fast checks are red\",\"kind\":\"check\",\"check\":\"fast-checks\",\"card\":\"c6-6\",\"issue\":6}]" ] \
    || fail "loop, gh, newest line or the push error: $out"
  [ "$(jq -c '[.blocked, .waiting, .stuck]' <<<"$out")" = '[[{"card":"c1-1","issue":1,"reason":"review 1: no answer","since":"2026-11-01T00:05:00Z"}],[{"card":"c2-2","issue":2,"reason":"visible to customers or staff: needs Dana'"'"'s yes: a new button","since":"2026-11-01T00:06:00Z"}],[{"card":"c3-3","issue":3,"step":"worktree","since":"2026-11-01T00:07:00Z"}]]' ] \
    || fail "blocked, waiting and stuck cards: $out"
  [ "$(jq -c .ghReached <<<"$out")" = null ] || fail "GitHub was said reached or not though gh is signed out: $out"
  # Bug caught (#490): ghWhy keeps gh's own error text, so a wake says what gh auth token answered.
  [ "$(jq -c .ghWhy <<<"$out")" = '"gh auth token failed (exit 1): no oauth token found for github.com"' ] || fail "gh's error text is not health's ghWhy: $out"
  rm "$STUB/signed-out"; [ "$(h '[.loop, .gh, .ghReached]')" = '[false,true,true]' ] || fail "a loop that ended, or gh signed in again, is not seen"
  # Bug caught (#410): signed in was read from gh auth status, which checks the token over the network, so a slow
  # GitHub read as signed out. gh holds its token (gh auth token) while gh auth status times out: signed in, GitHub not reached.
  : > "$STUB/unreached"; [ "$(h '[.gh, .ghReached]')" = '[true,false]' ] || fail "a gh auth status that timed out is not signed in, GitHub not reached: $(loop health)"
  rm "$STUB/unreached"
  # Bug caught (#490): health said gh false with no reason, so a wake could not say why. ghWhy names a timed-out
  # gh auth token and an empty token, and is null while signed in.
  [ "$(h .ghWhy)" = null ] || fail "a signed-in gh has a reason to be signed out: $(loop health)"
  : > "$STUB/token-timeout"; [ "$(h '[.gh, .ghWhy]')" = '[false,"gh auth token timed out after 20 s"]' ] || fail "a timed-out gh auth token is not given as the reason: $(loop health)"
  rm "$STUB/token-timeout"; : > "$STUB/token-empty"
  [ "$(h '[.gh, .ghWhy]')" = '[false,"gh auth token gave an empty token"]' ] || fail "an empty token is not given as the reason: $(loop health)"
  rm "$STUB/token-empty"
  # Bug caught (#490): with watch.py's GitHub folder (CONVEYOR_GITHUB) before its first GitHub read wrote gh, health
  # read the answer not there as signed out, and the kept snapshot woke the Foreman with "gh is signed out". With no
  # answer it reads gh itself; the folder's answer of false, from `conveyor.sh github`, gives its reason.
  mkdir -p "$T/$CASE/feed"; [ "$(CONVEYOR_GITHUB=$T/$CASE/feed h .gh)" = true ] || fail "a GitHub folder with no answer yet reads as signed out"
  : > "$STUB/token-empty"; loop github "$T/$CASE/feed" > /dev/null 2>&1; rm "$STUB/token-empty"
  [ "$(CONVEYOR_GITHUB=$T/$CASE/feed h '[.gh, .ghWhy]')" = '[false,"gh auth token gave an empty token"]' ] || fail "the GitHub folder's reason is not health's: $(cat "$T/$CASE/feed/ghwhy")"
  # Bug caught (#490): the Foreman told GitHub reads apart by health's time, so a snapshot built again from one
  # folder read counted as a second read and woke it. ghRead is the same for each build from one read, new for the next.
  local r1 r2; r1=$(CONVEYOR_GITHUB=$T/$CASE/feed h .ghRead); r2=$(CONVEYOR_GITHUB=$T/$CASE/feed h .ghRead)
  [[ $r1 =~ ^\"[0-9]+\"$ ]] && [ "$r1" = "$r2" ] || fail "two builds from one GitHub read give different reads: $r1 $r2"
  : > "$STUB/token-empty"; loop github "$T/$CASE/feed" > /dev/null 2>&1; rm "$STUB/token-empty"
  [ "$(CONVEYOR_GITHUB=$T/$CASE/feed h .ghRead)" != "$r1" ] || fail "a new GitHub read gives the read before it"
  # Health asks a second on (the clock seam, CONVEYOR_NOW): #4, picked just now, is then a second old.
  [ "$(CONVEYOR_NOW=$(( $(date +%s) + 1 )) tuned '.tunables.stuck = 1' h '.stuck | map(.issue)')" = '[3,4]' ] || fail "the stuck time is not the pack's tunables.stuck"
  git -C "$R" push -q origin main; [ "$(h '[.unpushed, .pushError, .pushFailingSince]')" = '[[],null,null]' ] || fail "a pushed commit is still listed, or its push error is"
  # A line that does not check (#157): health still answers. The line is set aside in quarantined.jsonl and named,
  # and the record gives the rest. Bug: one bad line stopped health, or health read it.
  echo junk >> "$S/cards.jsonl"; mkdir -p "$T/$CASE"; out=$(loop health 2>&1 > "$T/$CASE/health") || fail "health stopped on a line that does not check: $out"
  grep -qF "line 16 is not a whole record of a known step (the check refused (not JSON))" <<<"$out" || fail "health did not name the line it set aside: $out"
  ! grep -qx junk "$S/cards.jsonl" && jq -se 'map([.line, .field, .record]) == [[16, "(not JSON)", "junk"]]' "$S/quarantined.jsonl" >/dev/null \
    || fail "the bad line was not moved out of the records to the quarantine: $(cat "$S/quarantined.jsonl" 2>&1)"
  [ "$(jq -c '[(.quarantined | map([.line, .field])), (.blocked | map(.issue)), (.waiting | map(.issue)), (.stuck | map(.issue))]' "$T/$CASE/health")" = '[[[16,"(not JSON)"]],[1],[2],[3]]' ] \
    || fail "health did not name the line set aside, or did not give the rest of the records: $(cat "$T/$CASE/health")"
}

# Bugs: a card whose process is gone (or whose pid now names another process) is not seen as stuck until
# STUCK seconds pass, or one whose process runs is; the loop's loop.json does not name its process by pid and start
# time, so the stream cannot tell whether the loop runs without a Linux-only lock table.
t_alive() {
  setup "[$(issue 7 2026-01-01)]"; S=$ST; echo "$GO" > "$STUB/review.1"
  echo 'echo two >> a.txt; cp "$ST/loop.json" "$STUB/said"; LC_ALL=C ps -o lstart= -p "$(jq -r .pid "$STUB/said")" > "$STUB/ps"
w=$(jq -c "select(.step == \"worktree\")" "$ST/cards.jsonl"); [ "$(LC_ALL=C ps -o lstart= -p "$(jq -r .pid <<<"$w")" | sed "s/^ *//; s/ *$//")" = "$(jq -r .started <<<"$w")" ] && : > "$STUB/cardalive"' > "$STUB/build"
  loop run >/dev/null 2>&1 || fail "run exited non-zero"
  [ "$(jq -r .started "$STUB/said")" = "$(sed 's/^ *//; s/ *$//' "$STUB/ps")" ] && [ -n "$(jq -r .started "$STUB/said")" ] \
    || fail "loop.json does not name the loop's start time: $(cat "$STUB/said" "$STUB/ps")"
  [ "$(st 'select(.step == "worktree") | [(.pid | type), (.started | type)]' | tr -d ' \n')" = '["number","string"]' ] \
    && [ -e "$STUB/cardalive" ] || fail "the worktree line does not name the card's running process: $(st 'select(.step == "worktree")')"
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ); sleep 30 & alive=$!; sleep 0 & ended=$!; wait $ended # sleep: stand-ins for a card's process, one alive and one ended
  started=$(. "$SRC/lib/portable.sh"; p_started $alive)
  for c in a:$alive:"$started" b:$ended:"$started" c:$alive:other; do
    jq -cn --arg c "${c%%:*}" --arg t "$now" --argjson p "$(cut -d: -f2 <<<"$c")" --arg s "$(cut -d: -f3- <<<"$c")" \
      '{card:$c,issue:9,step:"worktree",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",pid:$p,started:$s}' >> "$S/cards.jsonl"
  done
  [ "$(loop health | jq -c '.stuck | map(.card)')" = '["b","c"]' ] || fail "stuck at once: the gone and the reused pid, not the live one: $(loop health | jq -c .stuck)"
  kill $alive; wait $alive 2>/dev/null; loopend
}

# Bug: the loop that a restart starts adopts a card that has landed and not pushed yet; the card's process ends while
# the last line of the card records is still being written (a long line reaches the file in more than one write),
# the whole read of the records fails, and the loop writes `blocked` ("its process ended without a result") for the
# landed card, which then stays in Needs you after its push goes out.
t_landedrestart() {
  setup '[]'; S=$ST; O=$T/$CASE/origin; mkdir -p "$S"
  echo x > "$R/n.txt"; git -C "$R" add -A; git -C "$R" commit -qm next; sha=$(git -C "$R" rev-parse HEAD)
  rec() { # <card> <issue> <step> [extra json]
    jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --argjson x "${4:-{\}}" \
      '{card:$c,issue:$i,step:$s,time:(now | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} * $x'
  }
  { rec c1-14 14 picked; rec c1-14 14 landed "{\"sha\":\"$sha\",\"product\":false}"; } >> "$S/cards.jsonl"
  # Another card's line, half written.
  l=$(rec c2-15 15 picked); printf '%s' "${l:0:40}" >> "$S/cards.jsonl"
  # The landed card's process, adopted from the loop before the restart, has ended.
  sleep 0 & dead=$!; wait $dead # sleep: a stand-in for a card's process that has ended
  # One `run` given the adopted card (CONVEYOR_ADOPT, with the run lock on fd 8), with the push rule off: no line of
  # its own is written after the half-written one. Its first turn sees to the adopted card, and it ends: the look at
  # an adopted card is run()'s own, in its turn, so the case runs the loop, in the foreground.
  pushrule() { jq --argjson p "$1" '.rules.push = $p' "$S/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$S/control.json"; } # <true | false>
  pushrule false
  out=$(CONVEYOR_ADOPT="$dead c1-14 14 $(git -C "$SRC" rev-parse HEAD)" loop run 8>>"$S/cards.jsonl.run" 2>&1) || fail "the run that adopted the landed card failed: $out"
  ! grep -q '"step":"blocked"' "$S/cards.jsonl" || fail "the loop blocked the adopted card that had landed: $out"
  # Once the line is whole, the landed card's push is the next loop's, as for any landing.
  printf '%s\n' "${l:40}" >> "$S/cards.jsonl"; pushrule true
  out=$(loop run 2>&1) || fail "the run that pushes the landed card failed: $out"
  [ "$(git -C "$O" rev-parse main)" = "$sha" ] && [ -n "$(st 'select(.card == "c1-14" and .step == "pushed")')" ] && [ -z "$(st 'select(.step == "blocked")')" ] && loop check \
    || fail "the landed card's push did not go out, or it was blocked: $(st '"\(.card) \(.step)"' | tr '\n' ,) $out"
  loopend
}

# Bug: an installed loop whose pack does not read wrote why at every turn, twice: it asks the pack for its pin at
# every turn (stale), and that reading said the reason itself, past the loop's own once-only word. The install's
# engine, loaded while the pack reads; the pack then goes for 6 turns, each the pin's reading (stale) and the pack's
# (packturn()): the reason is said once, and nothing else is.
t_servesame() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  bash "$D/conveyor/conveyor.sh" install "$B" >/dev/null || fail "the install failed"
  tune --arg c "$B" '.plugin.commit = $c'
  eng "$V/$B/conveyor" "mv $(printf '%q %q' "$R/.conveyor/project.json" "$STUB/pack")"'; [ -n "$OWN" ] || echo "not run from the install"
    told=""; for i in 1 2 3 4 5 6; do stale; packturn; [ -n "$nopack" ] || echo "turn $i read the pack"; done' > "$STUB/turns.out" 2>&1
  [ "$(cat "$STUB/turns.out")" = "conveyor pack: $R/.conveyor/project.json: no such file" ] || fail "held for 6 turns by a pack that does not read, the installed loop said more than the reason, once: $(cat "$STUB/turns.out")"
}
