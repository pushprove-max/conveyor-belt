#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a project that follows the plugin's main (plugin.follow) and keeps itself up to date (take(),
# lib/install.sh): the pack's check, the loop's move to a new commit, a commit refused, the shim, the record of the
# engine a card ran on, a pinned pack left alone, and old installs pruned.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# After setup and coderepo (tests/install.test.sh): the plugin's pushed main ($D.git) put on <commit>.
mainat() { git -C "$D.git" update-ref refs/heads/main "$1" || fail "the plugin's main was not moved to $1"; }
# A new commit of the plugin's code repo, pushed to its main, made by <shell command> run in the repo; its id in $NEW.
pushed() { # <shell command>
  (cd "$D" && eval "$1") && git -C "$D" add -A && git -C "$D" commit -qm "$1" && git -C "$D" push -q origin HEAD:main \
    && NEW=$(git -C "$D" rev-parse HEAD) || fail "the commit ($1) was not pushed"
}
# The project's take, run by the install of <commit> as the loop on that commit runs it.
takeby() { CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$V/$1/conveyor/conveyor.sh" take; } # <commit>
engine() { jq -cr "$1" "$R/.git/conveyor-engine.json"; } # <jq filter> of the project's engine record

# Bug: a pack names both a pin and main to follow, or neither, and the engine guesses which it runs; the message does
# not say what to set.
t_followpack() {
  setup '[]'; P=$R/.conveyor/project.json
  tune '.plugin = {follow: "main"}'
  out=$(bash "$SRC/lib/pack.sh" check "$P" 2>&1) || fail "a pack that follows main and names no commit was refused: $out"
  out=$(loop check 2>&1) || fail "check refused a pack that follows main: $out"
  tune --arg c "$(printf '%040d' 0)" '.plugin = {follow: "main", commit: $c}'
  out=$(bash "$SRC/lib/pack.sh" check "$P" 2>&1) && fail "a pack naming both a commit and main to follow passed"
  grep -q 'plugin: both commit and follow are set: set one, commit (a full commit id: the project runs that commit) or follow: "releases"' <<<"$out" \
    || fail "a pack naming both was refused without saying which to set: $out"
  tune '.plugin = {}'
  out=$(bash "$SRC/lib/pack.sh" check "$P" 2>&1) && fail "a pack naming neither a commit nor main to follow passed"
  grep -q 'plugin: neither commit nor follow is set: set one, commit (a full commit id: the project runs that commit) or follow: "releases"' <<<"$out" \
    || fail "a pack naming neither was refused without saying which to set: $out"
  tune '.plugin = {follow: "dev"}'
  ! bash "$SRC/lib/pack.sh" check "$P" >/dev/null 2>&1 || fail "a pack following a branch other than main passed"
}

# Bugs: the plugin's main moves and a following project's loop goes on on the old engine for good, or it kills or
# moves a card in flight onto the new one; a card's record does not say which engine built it; health does not name
# the commit the loop runs.
t_followtake() {
  setup "[$(issue 7 2026-01-01), $(issue 8 2026-01-02)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  coderepo; trap 'kill $pid 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'; mainat "$A"
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null && takeby "$A" >/dev/null || fail "the first commit was not taken"
  [ "$(engine .commit)" = "$A" ] || fail "the project's engine is not the commit taken: $(cat "$R/.git/conveyor-engine.json")"
  loop control cap 1 >/dev/null || fail "cap 1 was refused"
  # Each build changes nothing: the card ends after it (blocked: no change to review), with no review, tests or
  # landing, which say nothing of the engine it ran on.
  echo ': > "$STUB/building"; while [ -d "$STUB" ]; do [ -e "$STUB/go" ] && break; sleep 0.1; done' > "$STUB/build"
  tune '.tunables.idle = 1 | .tunables.poll = 1'
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec bash "$V/$A/conveyor/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!
  till() { until eval "$1"; do kill -0 $pid 2>/dev/null || return 1; sleep 0.1; done; } # <condition>: until it holds; 1 if the loop ended first
  till '[ -e "$STUB/building" ]' || fail "serve did not start #7: $(cat "$STUB/serve.out")"
  [ "$(st 'select(.issue == 7 and .step == "worktree") | .engine')" = "$A" ] || fail "#7's record does not name the engine it runs on: $(st 'select(.issue == 7)')"
  # The plugin's main moves to $B while #7 is in flight: the loop takes it with nobody asked, and restarts on it at
  # its next pick; #7 ends on $A.
  mainat "$B"
  till 'grep -q "took Conveyor commit $B of the plugin.s main" "$STUB/serve.out"' || fail "the loop did not take the new commit of main: $(cat "$STUB/serve.out")"
  till 'grep -q "restarting on the new code; 1 cards in flight carry on on $A" "$STUB/serve.out"' || fail "the loop did not restart on the commit taken: $(cat "$STUB/serve.out")"
  [ "$(engine .commit)" = "$B" ] && [ -z "$(st 'select(.issue == 7 and .step == "landed")')" ] \
    || fail "the engine did not move, or the loop waited for #7 before it moved: $(cat "$R/.git/conveyor-engine.json")"
  # Health names the commit the loop says it runs (its loop.json): waited for there, then asked of health once, as a
  # health a turn costs the loop's own core about a second.
  till '[ "$(jq -r ".commit // empty" "$ST/loop.json" 2>/dev/null)" = "$B" ]' && [ "$(loop health | jq -r .commit)" = "$B" ] \
    || fail "health does not name the commit the loop runs: $(loop health | jq -c .commit)"
  loop control cap 2 >/dev/null || fail "cap 2 was refused"
  till '[ -n "$(st '"'"'select(.issue == 8 and .step == "worktree")'"'"')" ]' || fail "the restarted loop did not pick #8: $(cat "$STUB/serve.out")"
  [ "$(st 'select(.issue == 8 and .step == "worktree") | .engine')" = "$B" ] || fail "#8 was not picked on the new commit: $(st 'select(.issue == 8 and .step == "worktree")')"
  : > "$STUB/go"
  till '[ -n "$(st '"'"'select(.issue == 8 and .step == "blocked")'"'"')" ] && [ -n "$(st '"'"'select(.issue == 7 and .step == "blocked")'"'"')" ]' \
    || fail "#7 and #8 did not both end: $(cat "$STUB/serve.out")"
  # #7's build ran to its end, on the engine it started on: it was neither killed nor moved by the restart.
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "the session made no change, so there is nothing to review" ] \
    && [ "$(st 'select(.issue == 7 and .step == "worktree") | .engine')" = "$A" ] && kill -0 $pid 2>/dev/null \
    || fail "#7 did not end on the engine it started on, or the loop ended: $(st 'select(.issue == 7)')"
}

# Bugs: a commit of main whose check fails, or that lacks a hook the project runs, becomes the project's engine and
# stops its loop and its sessions' hooks; or it is refused and nothing says so; or the entry stays after a later
# commit is taken; doctor does not say which engine a following project is on, or how far behind main.
t_followrefuse() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'; mainat "$A"
  mkdir -p "$R/.claude" && jq -n '{hooks: {Stop: [{hooks: [{type: "command", command: "\"${CLAUDE_PLUGIN_ROOT}\"/shim.sh conveyor/foreman/stop.sh state"}]}]}}' > "$R/.claude/settings.json"
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null && takeby "$A" >/dev/null || fail "the first commit was not taken"
  # A commit whose schema no longer takes the project's pack.
  pushed "jq '.required += [\"zzz\"]' conveyor/schema/pack.schema.json > s.new && mv s.new conveyor/schema/pack.schema.json"; E=$NEW
  out=$(takeby "$A" 2>&1)
  [ "$(engine .commit)" = "$A" ] && [ "$(engine .refused.commit)" = "$E" ] || fail "a commit that fails its check was taken, or not recorded: $out $(cat "$R/.git/conveyor-engine.json")"
  grep -q "did not take Conveyor commit $E of the plugin's main, as its check of the pack failed" <<<"$out" || fail "the refusal was not said: $out"
  # Bug: a refused commit, installed to be checked and never taken, stays installed for good.
  [ ! -e "$V/$E" ] && [ -d "$V/$A" ] || fail "the refused commit's install was kept, or the project's own removed: $(ls "$V")"
  s=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  jq -e --arg e "$E" '.needsYou.engine | .commit == $e and (.reason | test("its check of the pack failed: .*zzz: missing"))' <<<"$s" >/dev/null \
    || fail "Needs you does not name the refused commit and why: $(jq -c .needsYou.engine <<<"$s")"
  # doctor says which engine the project is on, how far behind the plugin's main ($B, then $E) that is, and why $E was not taken.
  out=$(cd "$R" && CONVEYOR_MAIN=$R bash "$V/$A/conveyor/conveyor.sh" doctor 2>&1)
  grep -qx "ok: the project follows the plugin's main: it runs Conveyor commit $A, 2 commits behind the plugin's main ($E)" <<<"$out" \
    && grep -q "^warning: Conveyor commit $E of the plugin's main was not taken: its check of the pack failed" <<<"$out" \
    || fail "doctor did not say which engine the project is on, how far behind main, and the commit refused: $out"
  # A commit that passes the check but lacks a hook .claude/settings.json runs through shim.sh.
  pushed "git checkout -q $A -- conveyor/schema/pack.schema.json && rm conveyor/foreman/stop.sh"; F=$NEW
  out=$(takeby "$A" 2>&1)
  [ "$(engine .commit)" = "$A" ] && [ "$(engine .refused.commit)" = "$F" ] || fail "a commit lacking a hook was taken: $out $(cat "$R/.git/conveyor-engine.json")"
  [ "$(loop snapshot --fresh | jq -c --arg f "$F" '.needsYou.engine | [.commit == $f, .reason]')" = '[true,"it lacks hooks .claude/settings.json runs through shim.sh: conveyor/foreman/stop.sh"]' ] \
    || fail "Needs you does not name the commit lacking a hook and the hook: $(loop snapshot --fresh | jq -c .needsYou.engine)"
  [ ! -e "$V/$F" ] || fail "the install of a commit refused for a missing hook was kept"
  # A refused commit is not tried again: it would be installed and checked once a minute for nothing.
  out=$(takeby "$A" 2>&1); [ -z "$out" ] || fail "a refused commit was tried again: $out"
  # A later commit that passes is taken, and the entry goes.
  pushed "git checkout -q $A -- conveyor/foreman/stop.sh"; G=$NEW
  takeby "$A" >/dev/null || fail "a commit that passes was not taken"
  [ "$(engine .commit)" = "$G" ] && [ "$(engine .refused)" = null ] || fail "the passing commit was not taken, or the refusal stays: $(cat "$R/.git/conveyor-engine.json")"
  [ "$(loop snapshot --fresh | jq -c .needsYou.engine)" = null ] || fail "Needs you still names a refused commit after a later one was taken"
}

# Bugs: shim.sh runs a following project's hooks from the commit it took first for good, or from the plugin copy, even
# on a machine with no loop to take main;
# a machine that has taken no commit cannot run a hook; the take's own output reaches the hook's stdout, which
# Claude Code reads, or the take reads the hook's input from stdin.
t_followshim() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'
  # The plugin copy is the code repo's checkout, with the shim at its top and a hook that says which commit it is and
  # what it read on stdin.
  pushed "cp '$SRC/../shim.sh' shim.sh && printf '#!/bin/sh\nread l; echo one \$l\n' > probe.sh && chmod +x probe.sh"; X1=$NEW
  hook() { echo input | CLAUDE_PROJECT_DIR=$R bash "$D/shim.sh" probe.sh 2>"$STUB/shim.err"; }
  out=$(hook) || fail "the shim did not run the hook on a machine with no commit taken: $(cat "$STUB/shim.err")"
  [ "$out" = 'one input' ] && [ "$(engine .commit)" = "$X1" ] \
    || fail "the first use did not take main and run its hook with its input, or the take wrote to the hook's stdout: $out $(cat "$STUB/shim.err")"
  pushed "printf '#!/bin/sh\nread l; echo two \$l\n' > probe.sh"; X2=$NEW
  # Within a minute of its last look, a hook starts no take: one per hook would read the remote at every tool call.
  [ "$(hook)" = 'one input' ] && [ "$(engine .commit)" = "$X1" ] || fail "the shim left the engine before it was taken, or took again within a minute"
  # Bug: a machine that runs hooks but no loop (`serve`) stays on its first commit for good. Its last look a minute
  # gone, a hook runs on the engine it has and starts a take beside it, with nobody asked; a later hook runs the new one.
  touch -t 200001010000 "$R/.git/conveyor-engine.look"
  [ "$(hook)" = 'one input' ] || fail "the shim left the engine before it was taken: $(cat "$STUB/shim.err")"
  wait_until '[ "$(engine .commit)" = "$X2" ]' 'cat "$R/.git/conveyor-engine.json"' || fail "the shim did not take the plugin's new main on a machine with no loop"
  [ "$(hook)" = 'two input' ] || fail "the shim did not run the hook from the new engine: $(cat "$STUB/shim.err")"
}

# Bug (#179): a hook's background take threw its output and exit code away, so a project that follows main could stay
# on an old engine for hours and nothing said why. Run as Claude Code runs a hook (CONVEYOR_HOOK=1), the shim ends at
# once; the take it started then moves the project to main's new commit and keeps its run in the log.
t_followhook() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'
  pushed "cp '$SRC/../shim.sh' shim.sh && printf '#!/bin/sh\necho ran\n' > probe.sh && chmod +x probe.sh"; X1=$NEW
  bash "$D/conveyor/conveyor.sh" install "$X1" >/dev/null && takeby "$X1" >/dev/null || fail "the first commit was not taken"
  pushed "echo two > two.txt"; X2=$NEW
  # The shim's last look a minute gone: its next call starts a take.
  touch -t 200001010000 "$R/.git/conveyor-engine.look"
  out=$(echo '{}' | CONVEYOR_HOOK=1 CLAUDE_PROJECT_DIR=$R bash "$D/shim.sh" probe.sh 2>&1) && [ "$out" = ran ] \
    || fail "the hook did not run, or the take wrote to its streams: $out"
  wait_until '[ "$(engine .commit)" = "$X2" ] && [ -s "$R/.git/conveyor-engine.log" ]' 'cat "$R/.git/conveyor-engine.json" "$R/.git/conveyor-engine.log"' \
    || fail "the hook's background take did not move the project to main's new commit, or kept no log"
  jq -se --arg c "$X1" 'length == 1 and .[0].by == $c and .[0].exit == 0 and (.[0].time | fromdate) > 0' "$R/.git/conveyor-engine.log" >/dev/null \
    || fail "the log does not keep the take's run by the engine that ran it: $(cat "$R/.git/conveyor-engine.log")"
}

# Bug (#186): the install of the project's taken commit was removed (another project's prune), and every hook then ran
# with the guards off ("the project's Conveyor commit ... is not installed") until a take by hand. The next hook takes
# again in the foreground, which installs that commit again (main has not moved), runs on it and says so.
# Bug (#352): the repair's take, started while another take held ENGINE's lock, ended at once as a background take
# does, and the hook then ran with the guards off. Here another take holds the lock for 2 s: the repair waits for it.
t_followrepair() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'
  pushed "cp '$SRC/../shim.sh' shim.sh && printf '#!/bin/sh\necho ran\n' > probe.sh && chmod +x probe.sh"; X1=$NEW
  bash "$D/conveyor/conveyor.sh" install "$X1" >/dev/null && takeby "$X1" >/dev/null || fail "the first commit was not taken"
  chmod -R u+w "$V/$X1" && rm -rf "${V:?}/$X1" || fail "the install was not removed"
  ( flock 9 && touch "$STUB/held" && sleep 2 ) 9>>"$R/.git/conveyor-engine.json.lock" & # sleep: the other take holds the lock 2 s, for the repair to wait on
  wait_until '[ -e "$STUB/held" ]' : || fail "the other take's lock was not held"
  out=$(echo '{"session_id": "s1"}' | CONVEYOR_HOOK=1 CLAUDE_PROJECT_DIR=$R bash "$D/shim.sh" probe.sh 2>"$STUB/shim.err")
  [ "$out" = ran ] && [ "$(engine .commit)" = "$X1" ] && [ -f "$V/$X1/probe.sh" ] \
    || fail "the hook did not install the project's commit again and run on it: $out $(cat "$STUB/shim.err")"
  [ "$(cat "$STUB/shim.err")" = "conveyor: the project's Conveyor commit $X1 was not installed; the plugin's main was taken again, and this runs on $X1" ] \
    || fail "the hook did not say once that it repaired the install: $(cat "$STUB/shim.err")"
}

# Bugs (#179): an engine whose own take is broken never leaves itself; a take that fails says nothing, so doctor, the
# Foreman and /units do not name an old engine or why it stays.
t_followhookfail() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'
  hook() { echo '{}' | CONVEYOR_HOOK=1 CLAUDE_PROJECT_DIR=$R bash "$D/shim.sh" probe.sh >/dev/null 2>&1; touch -t 200001010000 "$R/.git/conveyor-engine.look"; }
  logged() { wait_until "[ \"\$(wc -l < '$R/.git/conveyor-engine.log' 2>/dev/null)\" -ge $1 ]" 'cat "$R/.git/conveyor-engine.log"' || fail "the log does not hold $1 takes"; }
  # X1's own take fails at once; the project runs it.
  pushed "cp '$SRC/../shim.sh' shim.sh && printf '#!/bin/sh\necho ran\n' > probe.sh && chmod +x probe.sh && sed -i '4i echo \"conveyor: a fault in this take\" >&2; exit 3' conveyor/commands/take.sh"; X1=$NEW
  bash "$D/conveyor/conveyor.sh" install "$X1" >/dev/null && jq -n --arg c "$X1" '{commit: $c, taken: [$c]}' > "$R/.git/conveyor-engine.json" || fail "the broken commit was not made the project's engine"
  pushed "git checkout -q HEAD~ -- conveyor/commands/take.sh"; X2=$NEW
  # The plugin copy (at X2) takes in its place, and the log says so.
  hook; logged 2
  [ "$(engine .commit)" = "$X2" ] || fail "an engine whose take fails was not left: $(cat "$R/.git/conveyor-engine.json" "$R/.git/conveyor-engine.log")"
  jq -se --arg c "$X1" '.[0].by == $c and .[0].exit == 3 and (.[0].output | test("a fault in this take"))
      and .[1].by == "plugin copy" and .[1].exit == 0 and .[1].note == "the take by \($c) failed, so the plugin copy'"'"'s take ran"' "$R/.git/conveyor-engine.log" >/dev/null \
    || fail "the log does not keep the failed take with its reason and the plugin copy's take after it: $(cat "$R/.git/conveyor-engine.log")"
  # main moves on, and no take can install it: the reason is kept, and doctor names the old engine, the newest
  # commit, when a take last worked, the reason and the command that takes it.
  pushed "echo three > three.txt"; X3=$NEW
  ok=$(jq -sr '.[1].time' "$R/.git/conveyor-engine.log")
  # Bug: ten failed takes after the last that worked pushed it out of the log, and the line lost its time.
  for i in 1 2 3 4 5 6 7 8 9 10; do jq -cn '{time: "2026-11-16T06:10:00Z", by: "x", exit: 1, output: "an older failure"}'; done >> "$R/.git/conveyor-engine.log"
  chmod a-w "$V"; hook
  wait_until '[ "$(tail -n 1 "$R/.git/conveyor-engine.log" | jq -r .by)" = "plugin copy" ]' 'cat "$R/.git/conveyor-engine.log"' || fail "the log does not hold the hook's takes"
  chmod u+w "$V"
  [ "$(engine .commit)" = "$X2" ] || fail "a commit that could not be installed was taken"
  [ "$(wc -l < "$R/.git/conveyor-engine.log")" -eq 11 ] || fail "the log does not keep the last 10 takes and the last that worked: $(cat "$R/.git/conveyor-engine.log")"
  out=$(cd "$R" && CONVEYOR_MAIN=$R bash "$V/$X2/conveyor/conveyor.sh" doctor 2>&1)
  line=$(grep '^warning: Conveyor runs an old engine here' <<<"$out")
  [ "$line" = "warning: Conveyor runs an old engine here: commit ${X2:0:7}, and the plugin's main is at ${X3:0:7} · last take that worked: $ok · last failure: conveyor: Conveyor commit $X3 of the plugin's main could not be installed: conveyor: commit $X3 could not be fetched from $D.git, checked out and verified · to take it, run: cd $R && bash $V/$X2/conveyor/conveyor.sh take" ] \
    || fail "doctor does not name the old engine, the newest commit, the last take that worked, the failure and the fix: $out"
  # The Foreman's start and /units print the same line, with no remote read.
  [ "warning: $(CONVEYOR_MAIN=$R bash "$V/$X2/conveyor/conveyor.sh" take stale)" = "$line" ] || fail "take stale does not print doctor's line"
}

# Bug (#192): the old-engine line read the last take that worked only from the hooks' log, so a take that worked by
# setup, the loop or `conveyor.sh take` (none of which writes that log) was shown as "none in the log" or an older time.
t_followtakeok() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'; mainat "$A"
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null || fail "the first commit was not installed"
  before=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  takeby "$A" >/dev/null || fail "the first commit was not taken"
  [ ! -e "$R/.git/conveyor-engine.log" ] || fail "a take run by hand wrote the hooks' log, so this case proves nothing"
  # A newer commit the last take read, not taken yet: the project runs an old engine.
  t=$(jq --arg h "$B" '.head = {commit: $h, name: "main"}' "$R/.git/conveyor-engine.json") && printf '%s\n' "$t" > "$R/.git/conveyor-engine.json" \
    || fail "the record's head was not moved"
  # Bug (#193): reading the line (/units, the Foreman's start) made the state folder, its record files and the cards folder.
  rm -rf "$ST" "$(dirname "$R")/conveyor-cards" || fail "the state folder was not removed"
  line=$(CONVEYOR_MAIN=$R bash "$V/$A/conveyor/conveyor.sh" take stale)
  [ ! -e "$ST" ] && [ ! -e "$(dirname "$R")/conveyor-cards" ] \
    || fail "take stale made local engine state: $(ls -d "$ST" "$(dirname "$R")/conveyor-cards" 2>/dev/null)"
  ok=$(sed -n 's/.* · last take that worked: \([^ ]*\) · .*/\1/p' <<<"$line")
  [[ $ok =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] && [[ ! $ok < $before ]] \
    || fail "the line does not name the time of the take run by hand (after $before): $line"
}

# Bug: a project that pins a commit has engines installed and switched when the plugin's main moves.
t_followpin() {
  setup '[]'; coderepo; trap 'kill $pid 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT; pid=''
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null || fail "the install failed"
  tune --arg c "$A" '.plugin.commit = $c'; tune '.tunables.idle = 1 | .tunables.poll = 1'; mainat "$B"
  watchturns
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec bash "$V/$A/conveyor/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!
  # serve looks at the plugin's main at its first turn (run(): its last look is long past), so one whole turn after
  # that look began is enough; the take after it is that same look, made here, and waited for.
  turns 2
  takeby "$A" > "$STUB/take.out" 2>&1 || fail "take of a pinned pack failed: $(cat "$STUB/take.out")"
  kill $pid; wait $pid 2>/dev/null
  [ ! -e "$V/$B" ] && [ ! -e "$R/.git/conveyor-engine.json" ] && [ ! -s "$STUB/take.out" ] && ! grep -q 'took\|restarting' "$STUB/serve.out" \
    || fail "a pinned project took the plugin's main: $(ls "$V") $(cat "$STUB/take.out" "$STUB/serve.out")"
}

# Bugs: every commit taken stays installed for good; or an install a card in flight runs on is removed under it.
t_followprune() {
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'; mainat "$A"
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null && takeby "$A" >/dev/null || fail "the first commit was not taken"
  # A card of this project in flight on $A.
  mkdir -p "$ST" && jq -cn --arg a "$A" '{card: "c1-5", issue: 5, step: "picked"}, {card: "c1-5", issue: 5, step: "worktree", engine: $a}' > "$ST/cards.jsonl"
  mainat "$B"; takeby "$A" >/dev/null || fail "$B was not taken"
  pushed 'echo 1 > n.txt'; C1=$NEW; takeby "$B" >/dev/null || fail "$C1 was not taken"
  pushed 'echo 2 > n.txt'; C2=$NEW; takeby "$C1" >/dev/null || fail "$C2 was not taken"
  [ ! -e "$V/$B" ] && [ -d "$V/$C1" ] && [ -d "$V/$C2" ] || fail "an install older than the newest two with no card on it was kept, or a newer one removed: $(ls "$V")"
  [ -d "$V/$A" ] || fail "the install a card in flight runs on was removed"
  [ "$(engine .taken)" = "$(jq -cn --arg a "$A" --arg c "$C1" --arg d "$C2" '[$a, $c, $d]')" ] || fail "the taken list: $(engine .taken)"
  # Once the card has ended, its install goes too.
  jq -cn '{card: "c1-5", issue: 5, step: "landed"}' >> "$ST/cards.jsonl"
  takeby "$C2" >/dev/null || fail "take failed"
  [ ! -e "$V/$A" ] && [ -d "$V/$C1" ] && [ -d "$V/$C2" ] || fail "the install of a card that ended was kept: $(ls "$V")"
}

# Bugs: each take of a new commit clones the plugin's whole repository again (minutes for one with large media), and
# every other take queues behind it, so the install stays behind and the old-engine line never clears.
t_followfetch() {
  prunesetup; trap 'touch "$STUB/go"; kill $tp 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT; tp=''
  # A new commit whose pack check waits for $STUB/go: its take runs until then.
  pushed "sed -i '2i until [ -e $STUB/go ]; do sleep 0.1; done' conveyor/lib/pack.sh" # sleep: the pause of the pack check's own wait for $STUB/go
  GIT_TRACE=$STUB/trace takeby "$A" > "$STUB/take.out" 2>&1 & tp=$!
  for _ in $(seq 300); do [ -d "$V/$NEW" ] && break; sleep 0.1; done
  [ -d "$V/$NEW" ] || fail "the first take did not install $NEW: $(cat "$STUB/take.out")"
  # A take started during the first ends at once, and the old-engine line says a take runs.
  s=$SECONDS; out=$(CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards timeout 30 bash "$V/$A/conveyor/conveyor.sh" take 2>&1) || fail "the second take failed: $out"
  [ $((SECONDS - s)) -lt 10 ] && grep -qx "conveyor: another take of the plugin's Conveyor runs now: this one ends" <<<"$out" \
    || fail "the second take waited for the first, $((SECONDS - s)) s: $out"
  out=$(CONVEYOR_MAIN=$R bash "$V/$A/conveyor/conveyor.sh" take stale 2>&1)
  [ "$out" = "Conveyor takes the plugin's main now: commit ${NEW:0:7}; the project runs commit ${A:0:7} until the take ends" ] \
    || fail "the old-engine line during a take: $out"
  touch "$STUB/go"; wait $tp || fail "the first take failed: $(cat "$STUB/take.out")"
  [ "$(engine .commit)" = "$NEW" ] || fail "$NEW was not taken: $(cat "$STUB/take.out")"
  # The new commit came by one fetch of the remote into the mirror, with no clone of the remote, of only the objects
  # main gained since $A (B's and the new commit's: commits, trees, changed files; under fetch.unpackLimit, so kept loose).
  ! grep -q "built-in: git clone .*$D.git" "$STUB/trace" && [ "$(grep -c "built-in: git fetch .*$D.git" "$STUB/trace")" = 1 ] \
    || fail "the take did not fetch the remote once, with no clone: $(grep 'built-in' "$STUB/trace")"
  # Bug: a depth-one install had no history, so olderthan took $A for newer than $NEW and a service would be started
  # again on the older commit. The install keeps the history, and the plugin's repository as its origin.
  # shellcheck disable=SC2034 # HERE, OWN and VERSIONS are read by the sourced lib/install.sh
  (HERE=$V/$NEW/conveyor OWN='' VERSIONS=$V; . "$SRC/lib/install.sh"; ! olderthan "$NEW" "$A" && olderthan "$A" "$NEW") \
    && [ "$(git -C "$V/$NEW" remote get-url origin)" = "$D.git" ] \
    || fail "the install of $NEW has no history to tell it is newer than $A, or not the plugin's origin: $(git -C "$V/$NEW" log --oneline | head -3)"
  n=$(git -C "$D" rev-list --objects "$A..$NEW" | wc -l)
  [ "$(git -C "$V/mirror.git" count-objects | cut -d' ' -f1)" = $((n)) ] && [ "$n" -lt 20 ] \
    || fail "the mirror did not fetch only the $n new objects: $(git -C "$V/mirror.git" count-objects -v)"
}
# The start of each other prune case (t_followprunelane, t_followpruneother, t_followpruneself, t_followprunelist), which run side by
# side: a following project that has taken $A, with no card. The host file is the case's own, as two of them write one.
prunesetup() {
  export XDG_CONFIG_HOME=$T/$CASE/config
  setup '[]'; coderepo; trap 'chmod -R u+w "$T/$CASE"' EXIT
  tune '.plugin = {follow: "main"}'; mainat "$A"
  bash "$D/conveyor/conveyor.sh" install "$A" >/dev/null && takeby "$A" >/dev/null || fail "the first commit was not taken"
}
t_followprunelane() {
  prunesetup
  pushed 'echo 1 > n.txt'; C1=$NEW; takeby "$A" >/dev/null || fail "$C1 was not taken"
  pushed 'echo 2 > n.txt'; C2=$NEW; takeby "$C1" >/dev/null || fail "$C2 was not taken"
  # Bug: a research lane's settings (or the machine's service) name an install by its path, and it is removed under
  # them. Listed in the uses file, it is kept while a listed file names it, and goes once none does.
  mkdir -p "$T/$CASE/lane" && jq -n --arg s "$V/$C1/shim.sh" --arg j "$V/$C1/conveyor/lanes/research-bash" \
    '{env: {CLAUDE_CODE_SHELL: $j}, hooks: {SessionStart: [{hooks: [{command: "/usr/bin/env", args: [$s]}]}]}}' > "$T/$CASE/lane/settings.local.json" \
    && echo "$T/$CASE/lane/settings.local.json" >> "$XDG_DATA_HOME/conveyor/uses" || fail "the lane's settings were not written"
  pushed 'echo 3 > n.txt'; C3=$NEW; takeby "$C2" >/dev/null || fail "$C3 was not taken"
  [ -d "$V/$C1" ] || fail "the install a research lane's settings name was removed under it"
  jq --arg c "$C1" --arg n "$C3" 'walk(if type == "string" then sub($c; $n) else . end)' "$T/$CASE/lane/settings.local.json" > "$T/$CASE/lane/new" \
    && mv "$T/$CASE/lane/new" "$T/$CASE/lane/settings.local.json" || fail "the lane's settings were not rewritten"
  pushed 'echo 4 > n.txt'; C4=$NEW; takeby "$C3" >/dev/null || fail "$C4 was not taken"
  [ ! -e "$V/$C1" ] && [ ! -e "$V/$C2" ] && [ -d "$V/$C3" ] || fail "an install no listed file names any more was kept: $(ls "$V")"
}
# Bug caught (#573): a per-project service of before starts the install of $A by its path, in no uses file; the loop
# moved on to newer commits, prune removed $A, and a restart or a reboot of the service would not start the loop.
t_followpruneunit() {
  prunesetup
  mkdir -p "$XDG_CONFIG_HOME/systemd/user" && printf '[Service]\nEnvironment="CONVEYOR_MAIN=%s"\nExecStart="/bin/bash" "%s" serve\n' "$R" "$V/$A/conveyor/conveyor.sh" \
    > "$XDG_CONFIG_HOME/systemd/user/conveyor-proj-1.service" || fail "the unit was not written"
  pushed 'echo 1 > n.txt'; C1=$NEW; takeby "$A" >/dev/null || fail "$C1 was not taken"
  pushed 'echo 2 > n.txt'; C2=$NEW; takeby "$C1" >/dev/null || fail "$C2 was not taken"
  [ -f "$V/$A/conveyor/conveyor.sh" ] && engine '.taken[]' | grep -qxF "$A" || fail "the install a service unit starts was removed: $(ls "$V")"
}
t_followpruneother() {
  prunesetup
  pushed 'echo 4 > n.txt'; C4=$NEW; takeby "$A" >/dev/null || fail "$C4 was not taken"
  # Bug: another project of the host file, pinned, starts a card on $C4 and is repinned to $A while it runs; this
  # project's prune reads only that project's new pin and removes $C4 under its card. Its card in flight keeps $C4,
  # until the card ends.
  local O=$T/$CASE/other; mkdir -p "$O/.conveyor" "$O/conveyor/state" "$XDG_CONFIG_HOME/conveyor" \
    && jq -n --arg c "$A" '{plugin: {commit: $c}}' > "$O/.conveyor/project.json" \
    && jq -cn --arg c "$C4" '{card: "c2-6", issue: 6, step: "picked"}, {card: "c2-6", issue: 6, step: "worktree", engine: $c}' > "$O/conveyor/state/cards.jsonl" \
    && jq -n --arg r "$R" --arg o "$O" '{records: [{repo: "proj", main: $r}, {repo: "other", main: $o}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the other project was not written"
  pushed 'echo 5 > n.txt'; C5=$NEW; takeby "$C4" >/dev/null || fail "$C5 was not taken"
  pushed 'echo 6 > n.txt'; C6=$NEW; takeby "$C5" >/dev/null || fail "$C6 was not taken"
  [ -d "$V/$C4" ] || fail "the install another project's card in flight runs on was removed: $(ls "$V")"
  jq -cn '{card: "c2-6", issue: 6, step: "landed"}' >> "$O/conveyor/state/cards.jsonl"
  pushed 'echo 7 > n.txt'; C7=$NEW; takeby "$C6" >/dev/null || fail "$C7 was not taken"
  [ ! -e "$V/$C4" ] || fail "the install of another project's card that ended was kept: $(ls "$V")"
}
# Bug (#36): the Foreman's waiter and its watchers ran from versions/$A, and an update removed $A under them: every
# watcher read files that were gone, and the landings the Foreman awaited never woke it. A live waiter, of this project
# or of another of the host file (a group's Foreman folder is in its first project's state folder), keeps the commit
# its waiter.pid names; once that pid has ended, the next update removes it.
t_followprunewaiter() {
  prunesetup
  local O=$T/$CASE/other; mkdir -p "$O/.conveyor" "$O/conveyor/state/foreman" "$ST/foreman" "$XDG_CONFIG_HOME/conveyor" \
    && jq -n '{plugin: {follow: "main"}}' > "$O/.conveyor/project.json" \
    && jq -n --arg r "$R" --arg o "$O" '{records: [{repo: "proj", main: $r}, {repo: "other", main: $o}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the other project was not written"
  sleep 60 & w1=$!; sleep 60 & w2=$!; trap 'kill $w1 $w2 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT # sleep: stand-in waiters
  echo "$w1 $A s1" > "$ST/foreman/waiter.pid"
  pushed 'echo 1 > n.txt'; C1=$NEW; takeby "$A" >/dev/null || fail "$C1 was not taken"
  pushed 'echo 2 > n.txt'; C2=$NEW; takeby "$C1" >/dev/null || fail "$C2 was not taken"
  [ -d "$V/$A" ] && engine '.taken[]' | grep -qxF "$A" || fail "the install this project's live Foreman waiter runs from was removed: $(ls "$V")"
  kill $w1; wait $w1 2>/dev/null
  echo "$w2 $C1 s2" > "$O/conveyor/state/foreman/waiter.pid"
  pushed 'echo 3 > n.txt'; C3=$NEW; takeby "$C2" >/dev/null || fail "$C3 was not taken"
  [ ! -e "$V/$A" ] || fail "the install of a Foreman waiter that ended was kept: $(ls "$V")"
  [ -d "$V/$C1" ] || fail "the install another project's live Foreman waiter runs from was removed: $(ls "$V")"
}
# Bug (#198): the live Foreman waiter of another project, which no host file or followers list of this one names (or
# whose Foreman folder is not in the state folder guessed for it), ran from $A, and this project's prune removed $A
# under it: its watcher died and its blocked cards woke nothing. The waiter lists its Foreman folder in the machine's
# foremen file (foreman/waiter.sh; foreman/gone.test.sh checks that it does), and every prune keeps what it names.
t_followprunefar() {
  prunesetup
  local F=$T/$CASE/elsewhere/foreman; mkdir -p "$F" && echo "$F" >> "${V%/*}/foremen" || fail "the foremen file was not written"
  sleep 60 & w=$!; trap 'kill $w 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT # sleep: a stand-in waiter
  echo "$w $A s1" > "$F/waiter.pid"
  pushed 'echo 1 > n.txt'; C1=$NEW; takeby "$A" >/dev/null || fail "$C1 was not taken"
  pushed 'echo 2 > n.txt'; C2=$NEW; takeby "$C1" >/dev/null || fail "$C2 was not taken"
  [ -d "$V/$A" ] || fail "the install a live Foreman waiter the foremen file lists runs from was removed: $(ls "$V")"
}
# Bug (#186): two projects on one machine follow main, each with its own host file, so neither is in the other's
# records. The other's take lists it (FOLLOWERS), and this project's prune keeps the commit the other runs. A Board of
# either (a process running from an install, named by its path) keeps its commit too.
t_followpruneself() {
  prunesetup
  local O=$T/$CASE/other
  cp -a "$R" "$O" && rm -rf "$O/conveyor/state" && CONVEYOR_MAIN=$O CONVEYOR_CARDS=$T/$CASE/ocards bash "$V/$A/conveyor/conveyor.sh" take >/dev/null \
    && [ "$(jq -r .commit "$O/.git/conveyor-engine.json")" = "$A" ] || fail "the other project did not take $A"
  pushed 'echo 1 > n.txt'; C1=$NEW; takeby "$A" >/dev/null || fail "$C1 was not taken"
  bash -c 'sleep 60; :' "$V/$C1/.claude/scripts/dashboard.sh" & b=$!; trap 'kill $b 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT # sleep: a stand-in Board the test never waits for
  pushed 'echo 2 > n.txt'; C2=$NEW; takeby "$C1" >/dev/null || fail "$C2 was not taken"
  pushed 'echo 3 > n.txt'; C3=$NEW; takeby "$C2" >/dev/null || fail "$C3 was not taken"
  [ -d "$V/$A" ] || fail "the commit another following project runs was removed: $(ls "$V")"
  [ -d "$V/$C1" ] || fail "the commit a running Board runs was removed: $(ls "$V")"
}
t_followprunelist() {
  prunesetup
  pushed 'echo 6 > n.txt'; C6=$NEW; takeby "$A" >/dev/null || fail "$C6 was not taken"
  pushed 'echo 7 > n.txt'; C7=$NEW; takeby "$C6" >/dev/null || fail "$C7 was not taken"
  # Bug: two following projects each keep an old commit in their own taken list because the other's list names it,
  # and neither ever removes it. Named only in another's taken list, it leaves this list; its folder stays for that
  # project's own prune.
  local O=$T/$CASE/other; mkdir -p "$O/.conveyor" "$O/.git" "$XDG_CONFIG_HOME/conveyor" \
    && jq -n '{plugin: {follow: "main"}}' > "$O/.conveyor/project.json" \
    && jq -n --arg c "$C6" '{commit: $c, taken: [$c]}' > "$O/.git/conveyor-engine.json" \
    && jq -n --arg r "$R" --arg o "$O" '{records: [{repo: "proj", main: $r}, {repo: "other", main: $o}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the other project was not written"
  engine '.taken[]' | grep -qxF "$C6" || fail "this project's taken list does not name $C6 before the take: $(engine .taken)"
  pushed 'echo 8 > n.txt'; takeby "$C7" >/dev/null || fail "$NEW was not taken"
  [ -d "$V/$C6" ] && ! engine '.taken[]' | grep -qxF "$C6" \
    || fail "an old commit another project's taken list names stayed in this project's list, or its install was removed: $(engine .taken) $(ls "$V")"
}
