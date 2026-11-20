#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 240
# Engine cases: the lint check's review gate (lintgate(), conveyor/lib/lint.sh): its read-only check and put-back
# (lintrun), its fix session, its blocks and its lint line in a card's run, and the rule Lint check.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The case's main ($R, setup with <issues json>) with the stub linter $STUB/lint as the pack's one lint command, on
# *.txt and *.md files (each given to it): it notes each run in $STUB/lint-args and prints `<file>:<n>: E1 a bad word`
# for each line holding BAD; exit 1 with a finding, else 0. <run> (default `$L {files}`) is the command, $L in it the
# stub linter.
gatesetup() { # <issues json> [<run>]
  setup "$1"
  printf '%s\n' 'echo "run $*" >> "$STUB/lint-args"; r=0' \
    'for f; do n=0; while IFS= read -r l; do n=$((n + 1)); [[ $l != *BAD* ]] || { echo "$f:$n: E1 a bad word"; r=1; }; done < "$f"; done; exit $r' \
    > "$STUB/lint" || fail "the stub linter"
  tune --arg l "bash $STUB/lint" --arg r "${2:-\$L {files\}}" '.lint = {commands: [{files: ["*.txt", "*.md"], run: ($r | gsub("\\$L"; $l))}]}'
}
# Every session of card #7 is $STUB/build: a lint fix session (its brief holds the heading of LINTFIX) runs <lint fix>,
# a review fix session (FIX's heading) <review fix>, a rebuild (a landing conflict) <rebuild>, and the build <build>.
# Each notes its kind in $STUB/did.
gatesessions() { # <build> <lint fix> [<review fix>] [<rebuild>]
  printf '%s\n' "if grep -q '^# Lint findings: fix them' \"\$STUB/brief\"; then echo lintfix >> \"\$STUB/did\"; $2" \
    "elif grep -q '^# Reviewer findings' \"\$STUB/brief\"; then echo fix >> \"\$STUB/did\"; ${3:-:}" \
    "elif grep -q '^# \(Landing conflict\|Main moved\)' \"\$STUB/brief\"; then echo rebuild >> \"\$STUB/did\"; ${4:-:}" \
    "else echo build >> \"\$STUB/did\"; $1; fi" > "$STUB/build"
}
did() { paste -sd' ' "$STUB/did" 2>/dev/null; }
# The engine as the loop loads it, in a shell of main, <commands> run there: output in run.out, exit in RC (fx_in).
# Card c7's worktree, $FXWT, is made by fx_wt.

# Bug: the read-only check refuses a staged change (a modified, an added and a deleted file) though the linter writes
# nothing, as a check of the worktree against HEAD would. It passes, and the linter read the changed files.
# Bug: the lint line of a run whose change changed a command's trigger (its config) does not say the tools ran as
# installed, so a pass reads as the change's own config passing.
t_lintgatestaged() {
  gatesetup '[]'
  tune '.lint.commands[0].triggers = [".lintrc"]'
  # The empty folder: git cannot stage it, so it is no file that fails the check.
  fx_wt 'echo two >> a.txt && echo new > n.txt && git rm -q d.txt && echo new > .lintrc && mkdir empty' d.txt gone .lintrc old
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'lintrun "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" c7 "$T/$CASE/o"; rc=$?; echo "rc=$rc"; lintline c7 7 "$T/$CASE/o" $rc'
  grep -qx 'rc=0' "$T/$CASE/run.out" && [ "$(cat "$STUB/lint-args")" = 'run a.txt n.txt' ] \
    || fail "the staged change did not pass the read-only check, or the linter did not read it: $(cat "$T/$CASE/run.out") $(cat "$STUB/lint-args" 2>&1)"
  [ "$(st 'select(.step == "lint") | [.result, .lint.asInstalled, (.reason | endswith("; tools ran as installed"))] | tojson')" = '["pass",true,true]' ] \
    || fail "the lint line does not say the tools ran as installed: $(st 'select(.step == "lint")')"
  recok "$ST/cards.jsonl" "lintline"
}
# Bug: a command whose tool is missing (skipped) and whose trigger the change changed makes the lint line say the
# tools ran as installed, though no tool ran.
t_lintgateskiptrigger() {
  gatesetup '[]' 'echo "lint: missing shellcheck"; exit 127'
  tune '.lint.commands[0].triggers = [".lintrc"]'
  fx_wt 'echo two >> a.txt && echo new > .lintrc' .lintrc old
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'lintrun "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" c7 "$T/$CASE/o"; rc=$?; echo "rc=$rc"; lintline c7 7 "$T/$CASE/o" $rc'
  grep -qx 'rc=0' "$T/$CASE/run.out" || fail "the skipped command did not let the gate go on: $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "lint") | [.lint.commands[0].result, .lint.asInstalled, (.reason | contains("tools ran as installed"))] | tojson')" = '["skipped: missing shellcheck",false,false]' ] \
    || fail "the lint line of a skipped command says the tools ran as installed: $(st 'select(.step == "lint")')"
}

# Bugs: a lint command that writes a tracked file, adds a file git neither tracks nor ignores, or changes the index
# passes the gate, or leaves what it did in the card's change. Each is an execution error, and the worktree and index
# are put back as they were (the staged change, its deleted file still deleted, its added file still added).
t_lintgatewrites() {
  local cmd before
  gatesetup '[]'
  fx_wt 'echo two >> a.txt && echo new > n.txt && git rm -q d.txt' d.txt gone
  before=$(git -C "$FXWT" write-tree)
  # The index commands unset GIT_INDEX_FILE (the gate's copy of the index) to reach the worktree's own.
  for cmd in 'echo spoiled >> a.txt' 'chmod +x a.txt' 'echo x > stray.txt; mkdir -p dir && echo y > dir/f.txt' 'rm n.txt' \
    'env -u GIT_INDEX_FILE git rm -q --cached a.txt' 'echo z > added.txt; env -u GIT_INDEX_FILE git add added.txt'; do
    tune --arg r "$cmd; bash $STUB/lint {files}" '.lint.commands[0].run = $r'
    # shellcheck disable=SC2016 # expanded in fx_in's shell
    fx_in 'lintrun "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" c7 "$T/$CASE/o"; echo "rc=$?"; echo "why=$LINT_WHY"'
    grep -qx 'rc=2' "$T/$CASE/run.out" && grep -qx 'why=a lint command changed the worktree or its index; the engine put both back as they were' "$T/$CASE/run.out" \
      || fail "'$cmd' was no execution error put back: $(cat "$T/$CASE/run.out")"
    [ "$(git -C "$FXWT" write-tree)" = "$before" ] && git -C "$FXWT" diff --quiet && [ -z "$(git -C "$FXWT" ls-files -o --exclude-standard)" ] \
      && [ "$(cat "$FXWT/a.txt")" = "$(printf 'one\ntwo')" ] && [ ! -x "$FXWT/a.txt" ] && [ -f "$FXWT/n.txt" ] && [ ! -e "$FXWT/d.txt" ] \
      || fail "after '$cmd' the worktree or index is not as before: $(git -C "$FXWT" status --porcelain)"
  done
}

# Bug: a lint command that runs past its time limit is ended and counted, but what it wrote before it was ended stays
# in the card's change. It is an execution error, and the worktree is put back as it was.
t_lintgateover() {
  local before
  gatesetup '[]' 'echo spoiled >> a.txt; exec sleep 30' # sleep: ended by the 1-second limit; nothing waits for it
  fx_wt 'echo two >> a.txt' b.txt base
  before=$(git -C "$FXWT" write-tree)
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'LINT_LIMIT=1; at=$SECONDS; lintrun "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" c7 "$T/$CASE/o"; echo "rc=$?"; echo "sec=$((SECONDS - at))"'
  grep -qx 'rc=2' "$T/$CASE/run.out" && [ "$(git -C "$FXWT" write-tree)" = "$before" ] && git -C "$FXWT" diff --quiet \
    && [ "$(cat "$FXWT/a.txt")" = "$(printf 'one\ntwo')" ] || fail "the run over its limit was no execution error put back: $(cat "$T/$CASE/run.out"; git -C "$FXWT" diff)"
  # Bug: the gate waits for the command to end on its own (sleep 30 ends with exit 0, and the write alone makes rc 2).
  # The command is ended at its limit, and its result says so.
  [ "$(jq -r .why "$T/$CASE/o")" = 'it ran over its time limit of 1 seconds' ] && [ "$(sed -n 's/^sec=//p' "$T/$CASE/run.out")" -lt 20 ] \
    || fail "the command was not ended at its time limit: $(cat "$T/$CASE/o" "$T/$CASE/run.out")"
}

# Bug: a lint command that cannot start, as its test slots cannot be made, leaves no result (its seconds unset, so the
# record is dropped) and the gate passes. It is an execution error that names the command and why.
t_lintgatenoslot() {
  local host=$XDG_CONFIG_HOME/conveyor/host.json
  gatesetup '[]'
  fx_wt 'echo two >> a.txt' b.txt base
  mkdir -p "${host%/*}" && echo '{"testSlotsDir": "/dev/null/slots"}' > "$host" || fail "the host file"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'lintrun "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" c7 "$T/$CASE/o"; echo "rc=$?"; echo "why=$LINT_WHY"'
  rm -f "$host"
  grep -qx 'rc=2' "$T/$CASE/run.out" && grep -q '^why=lint command 1 (.*): it exited 126: conveyor: the test slots folder /dev/null/slots cannot be made' "$T/$CASE/run.out" \
    && [ ! -e "$STUB/lint-args" ] || fail "a command that could not start was no execution error: $(cat "$T/$CASE/run.out")"
}

# Bug: a worktree with an edit that is not staged goes to the linter, and the put-back after it deletes the edit. It is
# an execution error before any command runs, and the edit is still there.
t_lintgateunstaged() {
  gatesetup '[]'
  fx_wt 'echo two >> a.txt' b.txt base
  echo three >> "$FXWT/a.txt"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'lintrun "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" c7 "$T/$CASE/o"; echo "rc=$?"; echo "why=$LINT_WHY"'
  grep -qx 'rc=2' "$T/$CASE/run.out" && grep -q '^why=the worktree differs from its staged change' "$T/$CASE/run.out" && [ ! -e "$STUB/lint-args" ] \
    && [ "$(cat "$FXWT/a.txt")" = "$(printf 'one\ntwo\nthree')" ] || fail "the unstaged edit was linted or lost: $(cat "$T/$CASE/run.out"; cat "$FXWT/a.txt")"
}

# The cases below run card #7 whole (loop run): what they check is where the gate sits in card()'s review loop, which
# sessions and reviews follow it and what lands, which no call of lintgate() alone shows.

# Bugs: a finding at the review gate goes to the review as it is; its fix session spends a review (the card ends its
# loop a review early); a review fix that adds a finding in pass 2 blocks the card, or lands the finding. Each finding
# gets one fix session, then that pass's review session: three NO-GO reviews, and the last one lands with follow-ups.
t_lintgatefix() {
  gatesetup "[$(issue 7 2026-01-01)]"
  for i in 1 2 3; do moved $i "$NOGO" > "$STUB/review.$i"; done
  gatesessions 'echo BAD >> a.txt' "sed -i '/BAD/d' a.txt; echo good >> a.txt" 'echo "BAD again" >> a.txt'
  # loop: only card()'s review loop shows a lint fix before each pass's review and the count of reviews kept at three
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(did)" = 'build lintfix fix lintfix fix lintfix' ] && [ "$(wc -l < "$STUB/reviews")" = 3 ] \
    || fail "not one lint fix before each of the three reviews, and three reviews: $(did), $(wc -l < "$STUB/reviews") reviews"
  [ "$(st 'select(.step | IN("lint", "fix", "review")) | "\(.step):\(.result)"' | tr '\n' ' ')" \
    = "$(for i in 1 2 3; do printf 'lint:findings fix:ok lint:pass review:NO-GO '; [ $i = 3 ] || printf 'fix:ok '; done)" ] \
    || fail "the steps are not lint, its fix, lint again and the review in each pass: $(st 'select(.step | IN("lint", "fix", "review")) | "\(.step):\(.result)"' | tr '\n' ' ')"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && ! grep -q BAD "$R/a.txt" || fail "the card did not land without the findings: $(cat "$R/a.txt")"
  st 'select(.step == "fix") | .reason' | grep -qx 'lint: 1 finding(s) of the change' || fail "the lint fix's line does not say why it ran: $(st 'select(.step == "fix") | .reason')"
  # The sessions' brief has the # Lint section: the command and the engine's own conveyor.sh lint.
  grep -qx '# Lint' "$STUB/brief" && grep -qF "run \`bash $SRC/conveyor.sh lint\` in this worktree" "$STUB/brief" && grep -qF -e "- lint command 1: \`bash $STUB/lint {files}\`" "$STUB/brief" \
    || fail "the brief has no # Lint section naming the command and conveyor.sh lint: $(grep -A3 '^# Lint$' "$STUB/brief")"
  recok "$ST/cards.jsonl" "the card with lint lines"
}

# Bug: a retry that lands an approved kept patch (no build, no review) lands a finding the gate finds in it. The
# finding gets one fix session, then a fresh review session reads the fixed change, and that review lets it land.
t_lintgateland() {
  local i
  i=$(issue 7 2026-01-01)
  gatesetup "[$i]"
  # The first card runs with the rule off, so its kept patch, approved, holds the finding.
  jq '.rules.lint = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the rule off"
  gatesessions 'mkdir -p web; echo pay >> web/pay.ts; echo BAD >> a.txt' "sed -i '/BAD/d' a.txt"
  for i in 1 2; do printf '%s\n' 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO' > "$STUB/review.$i"; done
  # loop: the kept, approved patch the retry lands from is made only by a whole first card run
  loop run > /dev/null || fail "first run exited non-zero"
  st 'select(.step == "blocked") | .reason' | grep -q "^visible to customers or staff: needs .*'s yes" || fail "the card did not stop for the yes: $(st 'select(.step | IN("blocked", "landed"))')"
  jq '.rules.lint = true' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the rule on"
  jq -c '[.[0] | .body += "\nVisible change approved: r-11\n"]' "$STUB/issues.json" > "$STUB/i.new" && mv "$STUB/i.new" "$STUB/issues.json" || fail "the yes"
  # loop: only the retried card run shows the gate's fix and fresh review on the mode=land path
  loop retry 7 > /dev/null && loop run > /dev/null || fail "the retry exited non-zero"
  st 'select(.step == "worktree") | .reason' | grep -q '^landing from the kept patch of card' || fail "the retry did not land from the kept patch: $(st 'select(.step == "worktree") | .reason')"
  [ "$(did)" = 'build lintfix' ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ -n "$(st 'select(.step == "landed") | .sha')" ] && ! grep -q BAD "$R/a.txt" \
    || fail "the kept patch's finding did not get a fix and a fresh review before it landed: $(did), $(wc -l < "$STUB/reviews") reviews, a.txt: $(cat "$R/a.txt")"
}

# Bug: a kept review (a rebuild after a landing conflict that changed documentation alone) stands for a change whose
# rebuild added a finding in README.md. The finding gets one fix session, then a review session reads the fixed change.
t_lintgatekept() {
  gatesetup "[$(issue 7 2026-01-01)]"
  for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  echo title > "$R/README.md" && git -C "$R" add README.md && git -C "$R" commit -qm "a README" || fail "main's README"
  gatesessions 'echo seven >> a.txt; echo seven > README.md' "sed -i '/BAD/d' README.md" : 'echo seven >> a.txt; printf "%s\n" main seven BAD > README.md'
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; echo main > "$R/README.md"; git -C "$R" commit -qam "main moves"; }' >> "$STUB/test-cmd"
  # loop: the landing conflict, rebuild and kept review that the gate must not trust come only from a whole card run
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(did)" = 'build rebuild lintfix' ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] \
    || fail "the rebuild's finding did not get a lint fix and a new review: $(did), $(wc -l < "$STUB/reviews") reviews"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ "$(tr '\n' ' ' < "$R/README.md")" = 'main seven ' ] \
    || fail "the card did not land the fixed README: $(cat "$R/README.md")"
}

# Bug: a finding left after the gate's fix session goes to the review, or lands. The card blocks, and nothing lands.
t_lintgateleft() {
  local head
  gatesetup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; head=$(git -C "$R" rev-parse HEAD)
  gatesessions 'echo BAD >> a.txt' 'echo "still BAD" >> a.txt'
  # loop: only a whole card run shows that card() blocks and lands nothing when a finding is left after the fix
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "blocked") | .reason' | head -n 1)" = 'lint: 2 findings left after its fix session; nothing landed' ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$head" ] && [ -z "$(st 'select(.step == "landed")')" ] && [ ! -e "$STUB/reviews" ] \
    || fail "the finding left did not block the card before any review: $(st 'select(.step | IN("blocked", "landed", "review")) | .reason')"
}

# Bug: a lint command that fails to run (exit 2) at the gate is taken as findings and sent to a fix session, or as a
# pass. It blocks the card, naming the command, with no fix session, and nothing lands.
t_lintgateerror() {
  gatesetup "[$(issue 7 2026-01-01)]" 'echo "lint: config broken"; exit 2'
  echo "$GO" > "$STUB/review.1"; gatesessions 'echo two >> a.txt' :
  # loop: only a whole card run shows that an execution error blocks the card with no fix session and nothing lands
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(did)" = build ] && [ -z "$(st 'select(.step == "landed")')" ] \
    && st 'select(.step == "blocked") | .reason' | grep -qF 'lint: an execution error, so nothing landed: lint command 1 (echo "lint: config broken"; exit 2): it exited 2: lint: config broken' \
    || fail "the execution error did not block the card with no fix session: $(did); $(st 'select(.step | IN("blocked", "landed")) | .reason')"
}

# Bug: a lint tool that is not installed blocks the card or is left out of its record. The card lands, its lint line
# saying the command was skipped and why.
t_lintgateskip() {
  gatesetup "[$(issue 7 2026-01-01)]" 'echo "lint: missing shellcheck"; exit 127'
  echo "$GO" > "$STUB/review.1"
  # loop: only a whole card run shows that a missing tool lets the card land with a skipped lint line in its record
  loop run > /dev/null || fail "run exited non-zero"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ "$(st 'select(.step == "lint") | .lint.commands[0].result')" = 'skipped: missing shellcheck' ] \
    && st 'select(.step == "lint") | .reason' | grep -qF 'lint command 1 (echo "lint: missing shellcheck"; exit 127): skipped: missing shellcheck' \
    || fail "the card with a missing tool did not land with its skipped lint line: $(st 'select(.step | IN("lint", "blocked")) | .reason')"
}

# Bug: with the rule Lint check off, the gate still runs the pack's lint commands. None runs, the brief has no # Lint
# section, and the card lands with no lint line.
t_lintgateoff() {
  gatesetup "[$(issue 7 2026-01-01)]"
  echo "$GO" > "$STUB/review.1"; gatesessions 'echo BAD >> a.txt' :
  jq '.rules.lint = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the rule off"
  # loop: only a whole card run shows that no gate, brief section or record line of card() runs a lint command
  loop run > /dev/null || fail "run exited non-zero"
  [ ! -e "$STUB/lint-args" ] && [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ -z "$(st 'select(.step == "lint")')" ] && ! grep -q '^# Lint$' "$STUB/brief" \
    || fail "a lint command ran with the rule off: $(cat "$STUB/lint-args" 2>&1)"
}
