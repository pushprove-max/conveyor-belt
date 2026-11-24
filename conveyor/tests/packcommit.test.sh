#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: `conveyor.sh setup pack-commit [yes | no]` (packcommit(), lib/setup.sh), which /conveyor-belt:setup and
# the Foreman run once the owner answers "Commit the Conveyor pack (.conveyor/project.json) on <default branch> now?".
# Bug (#187): setup and the Foreman gave the owner a git command to commit the pack by hand.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Main ($R) with its pack not committed (no longer ignored), a.txt changed and b.txt staged: the owner's other work,
# which a commit of the pack must leave as it is; the push rule off, the default (setup's seed turns it on). HEAD0 is
# main's commit before. The case then works in main's checkout, as the owner runs setup there: a case starts in a folder
# of its own that is no checkout (lib.sh), and setup refuses to run outside one (commands/setup.sh).
packsetup() {
  setup '[]'
  loop control rules push=off > /dev/null && echo 'conveyor/' > "$R/.gitignore" && git -C "$R" commit -qam 'track the pack' && git -C "$R" push -q origin main \
    && echo two >> "$R/a.txt" && echo b > "$R/b.txt" && git -C "$R" add b.txt && HEAD0=$(git -C "$R" rev-parse HEAD) && cd "$R" \
    || fail "the fixture was not made"
}
others() { [ "$(git -C "$R" status --porcelain -- a.txt b.txt)" = $' M a.txt\nA  b.txt' ]; }

# Bugs: the question is not asked or shows no change; yes commits the owner's other changes with the pack, or commits
# from a worktree in place of the main checkout, or names the wrong message; a pack changed after its commit is not
# offered again as an update; yes pushes while the push rule is off.
t_packcommityes() {
  packsetup; local out
  out=$(loop setup pack-commit) || fail "the ask exited non-zero: $out"
  [ "$(head -n 1 <<<"$out")" = 'ask: Commit the Conveyor pack (.conveyor/project.json) on main now?' ] && grep -q '^+.*"defaultBranch"' <<<"$out" \
    || fail "the question or the change was not printed: $out"
  [ "$(git -C "$R" rev-parse HEAD)" = "$HEAD0" ] || fail "the ask committed"
  # From a worktree of main, as a session in a card's worktree runs it: the commit is main's.
  git -C "$R" worktree add -q "$T/$CASE/wt" -b side || fail "the worktree was not made"
  out=$(cd "$T/$CASE/wt" && CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" setup pack-commit yes 2>&1) || fail "yes failed: $out"
  grep -q '^conveyor: committed .conveyor/project.json on main: Add the Conveyor pack' <<<"$out" && grep -q 'not pushed' <<<"$out" \
    || fail "yes did not say what it did: $out"
  [ "$(git -C "$R" log -1 --format=%s main)" = 'Add the Conveyor pack' ] && [ "$(git -C "$R" rev-parse main~1)" = "$HEAD0" ] \
    && [ "$(git -C "$R" diff-tree --no-commit-id --name-only -r main)" = .conveyor/project.json ] || fail "main's commit is not the pack alone: $(git -C "$R" log -1 --stat main)"
  others || fail "the owner's other changes were not left as they were: $(git -C "$R" status --porcelain)"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$HEAD0" ] || fail "the pack was pushed with the push rule off"
  [ "$(loop setup pack-commit)" = 'ok: the pack is committed' ] || fail "a committed pack was asked again"
  tune '.owner.name = "Lee"'
  out=$(loop setup pack-commit yes) && [ "$(git -C "$R" log -1 --format=%s)" = 'Update the Conveyor pack' ] && others \
    || fail "a changed pack was not committed as an update: $out"
}

# Bug (E1 of #1157): yes committed the pack alone, so the exempt file of its size entry, which setup writes beside the pack
# and cards read from main, stayed on this machine and cards stopped on the files that setup had exempted.
t_packcommitexempt() {
  packsetup; local out
  tune '.lint = {commands: [{files: ["*.txt"], size: {file: 3, exempt: ".conveyor/size-exempt.txt"}}]}' && echo big.txt > "$R/.conveyor/size-exempt.txt" || fail "the fixture was not made"
  out=$(loop setup pack-commit) && grep -q 'size-exempt.txt' <<<"$out" || fail "the ask did not name the exempt file: $out"
  out=$(loop setup pack-commit yes) || fail "yes failed: $out"
  [ "$(git -C "$R" diff-tree --no-commit-id --name-only -r main | paste -sd' ')" = '.conveyor/project.json .conveyor/size-exempt.txt' ] \
    && others || fail "main's commit is not the pack and its exempt file: $(git -C "$R" log -1 --stat main): $out"
  [ "$(loop setup pack-commit)" = 'ok: the pack is committed' ] || fail "the committed pack and exempt file were asked again"
  echo more >> "$R/.conveyor/size-exempt.txt"
  out=$(loop setup pack-commit) && grep -q '^ask:' <<<"$out" || fail "a changed exempt file was not asked: $out"
}

# Bug (R144 of #1450): step 3 of setup.md asked for the pack only when git status of .conveyor/project.json and the
# fixed path .conveyor/size-exempt.txt printed a line, so a change to an exempt file at another path alone was never
# put to the owner, and the Foreman's rule looked at the pack alone. Both now run pack-commit, which reads the exempt
# paths from the pack; the Foreman's step lives in procedures.md, where #1606 found the gate back. setup.md and
# procedures.md are instructions to a Claude session, so no behaviour of them can run here: the case runs pack-commit
# with a custom exempt path, and reads the texts (with foreman.sh, which names the procedures) for the call and gates.
t_packcommitcustom() {
  packsetup; local out
  tune '.lint = {commands: [{files: ["*.txt"], size: {file: 3, exempt: "docs/big-files.txt"}}]}' && mkdir -p "$R/docs" && echo big.txt > "$R/docs/big-files.txt" || fail "the fixture was not made"
  out=$(loop setup pack-commit yes) || fail "yes failed: $out"
  echo more >> "$R/docs/big-files.txt"
  out=$(loop setup pack-commit) && grep -q '^ask:' <<<"$out" && grep -q 'docs/big-files.txt' <<<"$out" || fail "a changed exempt file at a custom path was not asked: $out"
  # The bare call (closed by its backtick, or followed by its note), not the `pack-commit yes` and `no` calls of the
  # owner's answer: those are in both texts too, so a looser pattern passes with the check itself gone (E5 of #1450).
  grep -qF 'conveyor.sh" setup pack-commit`' "$SRC/../commands/setup.md" && grep -qF 'conveyor.sh setup pack-commit (' "$SRC/foreman/procedures.md" \
    || fail "setup.md or the Foreman's rules no longer run setup pack-commit with no answer, the only check that reads the exempt paths from the pack"
  ! grep -q 'status --porcelain' "$SRC/../commands/setup.md" "$SRC/foreman/foreman.sh" "$SRC/foreman/procedures.md" || fail "setup.md or the Foreman's rules gate the pack's question on a git status of fixed paths: $(grep -n 'status --porcelain' "$SRC/../commands/setup.md" "$SRC/foreman/foreman.sh" "$SRC/foreman/procedures.md" | cut -c1-200)"
}

# Bug (E2 of #1157): a size entry whose exempt file is on no disk and in no commit (the docs allow it) went to git add,
# which failed with "pathspec did not match", so the pack was never committed.
t_packcommitnoexempt() {
  packsetup; local out
  tune '.lint = {commands: [{files: ["*.txt"], size: {file: 3, exempt: ".conveyor/size-exempt.txt"}}]}' || fail "the fixture was not made"
  out=$(loop setup pack-commit yes) || fail "yes failed with the exempt file missing: $out"
  [ "$(git -C "$R" diff-tree --no-commit-id --name-only -r main)" = '.conveyor/project.json' ] \
    || fail "main's commit is not the pack alone: $(git -C "$R" log -1 --stat main): $out"
}

# Bug: no commits the pack anyway, or does not say that cards read it from main.
t_packcommitno() {
  packsetup; local out
  out=$(loop setup pack-commit no) || fail "no exited non-zero: $out"
  [ "$out" = 'conveyor: the pack is not committed: cards read the pack from main, so it stays on this machine until it is committed' ] \
    || fail "no did not say the pack is not committed: $out"
  [ "$(git -C "$R" rev-parse HEAD)" = "$HEAD0" ] && [ "$(git -C "$R" status --porcelain -- .conveyor/project.json)" = '?? .conveyor/project.json' ] && others \
    || fail "no changed the checkout: $(git -C "$R" status --porcelain)"
}

# Bug: the push rule on, the pack's commit stays on this machine.
t_packcommitpush() {
  packsetup; local out
  loop control rules push=on > /dev/null || fail "the push rule was not turned on"
  out=$(loop setup pack-commit yes) && grep -qx 'conveyor: pushed it to origin main' <<<"$out" \
    && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$(git -C "$R" rev-parse HEAD)" ] || fail "the pack's commit was not pushed: $out"
}

# The push rule on and a pre-push hook that takes 30 s (the slow step after the commit; its pid in $STUB/hook.pid),
# with an engine running: a stand-in for the loop, started as the machine's Conveyor starts one (a process group of
# its own, holding the run lock, its pid in loop.json), with a card's process under it. E is its pid.
pcslowpush() {
  packsetup; loop control rules push=on > /dev/null || fail "the push rule was not turned on"
  local h; h=$(git -C "$R" rev-parse --path-format=absolute --git-path hooks) && mkdir -p "$h" \
    && printf '#!/bin/sh\necho $$ > "%s"\nexec sleep 30\n' "$STUB/hook.pid" > "$h/pre-push" && chmod +x "$h/pre-push" || fail "the pre-push hook was not made" # sleep: the slow hook, ended by the push's limit or killed by the case
  set -m; ( cd "$R" && exec 9>>"$ST/cards.jsonl.run" && flock 9 && { sleep 600 & wait; } ) & E=$!; set +m # sleep: the card's process under the stand-in, killed by the case
  jq -cn --argjson p "$E" --arg t "$(p_started "$E")" '{pid: $p, started: $t}' > "$ST/loop.json" || fail "loop.json was not written"
}
pcended() { local s; s=$(ps -o stat= -p "$1" 2>/dev/null); [ -z "$s" ] || [[ $s == *Z* ]]; } # <pid>: ended (a zombie not yet reaped is ended too)

# Bug (#1106): pack-commit yes pushed with no time limit, so the project's pre-push hook (waiting minutes for a test
# slot the engine's cards held) kept it running past the Foreman's ask limit after its commit. Its push is now
# stopped at its own limit (CONVEYOR_PACK_PUSH, 1 s here), hook and all, and it says the commit is made, not pushed.
t_packcommitslow() {
  pcslowpush; local out rc s=$SECONDS
  out=$(CONVEYOR_PACK_PUSH=1 loop setup pack-commit yes 2>&1); rc=$?
  local took=$((SECONDS - s)) hp; hp=$(cat "$STUB/hook.pid" 2>/dev/null); kill -- "-$E"
  lim=$(loadlimit 10 30) # under the hook's 30 s
  [ "$rc" = 1 ] && [ "$took" -lt "$lim" ] || { kill "$hp" 2>/dev/null; fail "pack-commit yes did not end at its push's limit (exit $rc after ${took}s; limit $lim s: 10 s times the load factor $CASE_LOAD): $out"; }
  grep -qF "the push took more than 1s, so it was stopped; it goes with main's next push" <<<"$out" && grep -q '^conveyor: committed ' <<<"$out" \
    || fail "it did not say the commit was made and the push stopped: $out"
  [ "$(git -C "$R" log -1 --format=%s)" = 'Add the Conveyor pack' ] && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$HEAD0" ] \
    || fail "the commit was not kept, or the push went through"
  [ -n "$hp" ] && pcended "$hp" || { kill "$hp" 2>/dev/null; fail "the pre-push hook ran on after the push was stopped"; }
}

# Bug (#1106): `foreman.sh ask <project> setup pack-commit yes` hit its time limit after its commit, and the engine
# was left stopped (state T). The case runs the real ask: what a direct call of packcommit cannot show is how the ask's
# own time limit ends its command, and that it leaves no process of the engine stopped. The ask's limit (5 s) is
# shorter than the hook, so it ends pack-commit in its push. The push runs in a process group of its own (its
# limit's), which the ask's end does not reach: a push left running kept the ask's output open for the hook's 30 s
# (the ask returned late) and ran on after it. The records name no sender of the reported stop, so the case checks
# what is left after the ask: no process of the push, and no stopped one of the engine.
t_packcommitask() {
  local out rc hp s i=0
  R=$T/$CASE/main; mkdir -p "$XDG_CONFIG_HOME/conveyor" && jq -n --arg m "$R" '{records: [{repo: "main", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file was not written"
  pcslowpush
  # The record's own checkout's engine (a pack with no plugin key runs it, as lib.sh ask says): this one.
  mkdir -p "$R/conveyor" && printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$SRC/conveyor.sh" > "$R/conveyor/conveyor.sh" || fail "the record's engine was not made"
  s=$SECONDS
  out=$(cd "$T/$CASE" && unset CONVEYOR_FOREMAN_ASK CONVEYOR_PACK_PUSH && CONVEYOR_CARDS=$T/$CASE/cards CONVEYOR_MAIN=$R ASK_LIMIT=5 \
    bash "$SRC/foreman/foreman.sh" ask main setup pack-commit yes 2>&1); rc=$?
  local took=$((SECONDS - s)) st; hp=$(cat "$STUB/hook.pid" 2>/dev/null)
  # The hook is a real process that pack-commit's end tells to stop (TERM): it is given up to 3 s to end.
  while [ -n "$hp" ] && ! pcended "$hp" && [ $((i++)) -lt 30 ]; do sleep 0.1; done
  local left=; [ -n "$hp" ] && pcended "$hp" || { left=1; kill "$hp" 2>/dev/null; }
  st=$(p_stoppedtree "$E"); kill -CONT -- "-$E" 2>/dev/null; kill -- "-$E"
  lim=$(loadlimit 9 30) # under the hook's 30 s
  [ "$rc" = 124 ] && [ "$took" -lt "$lim" ] && grep -q '^conveyor: committed ' <<<"$out" || fail "the ask did not end at its limit after the commit (exit $rc after ${took}s; limit $lim s: 9 s times the load factor $CASE_LOAD): $out"
  [ -z "$left" ] || fail "the push's pre-push hook ran on after the ask ended"
  [ -z "$st" ] || fail "the ask's end left the engine's processes stopped (state T): $st"
}

# Bug: with another branch checked out, the pack is committed there, or a question is asked.
t_packcommitbranch() {
  packsetup; local out
  git -C "$R" switch -q -c feature || fail "the branch was not made"
  out=$(loop setup pack-commit 2>&1) && fail "the ask on another branch exited 0: $out"
  grep -q 'has feature checked out, not the default branch main: the pack is not committed' <<<"$out" && ! grep -q '^ask:' <<<"$out" \
    || fail "the other branch was not said, or a question was asked: $out"
  out=$(loop setup pack-commit yes 2>&1) && fail "yes on another branch exited 0: $out"
  [ "$(git -C "$R" rev-parse HEAD)" = "$HEAD0" ] && others || fail "yes on another branch committed"
}

# Bug: commands/setup.md told the session to add --foreman, --pin or --survey to every setup command, step 3's
# pack-commit too, which refuses them (exit 2), so the question was never asked. setup.md is instructions to a Claude
# session, so no behaviour of it can run here: the case runs pack-commit as it was told to, and reads the text.
t_packcommitflags() {
  packsetup; local out
  out=$(loop setup pack-commit --foreman 2>&1); [ $? -eq 2 ] || fail "pack-commit took --foreman: $out"
  ! grep -q 'every setup command' "$SRC/../commands/setup.md" || fail "setup.md adds its flags to every setup command"
  [ "$(grep -c "to each run of step 1's setup command" "$SRC/../commands/setup.md")" -eq 4 ] \
    && grep -q '^`setup pack-commit` in step 3: it takes no other argument' "$SRC/../commands/setup.md" \
    || fail "setup.md does not keep --foreman, --pin, --survey and the --size flags to step 1's setup command"
}

# Bug: a pack with a conflict is committed with its conflict marks, or a question is asked.
t_packcommitconflict() {
  packsetup; local out
  git -C "$R" reset -q --hard && git -C "$R" add .conveyor/project.json && git -C "$R" commit -qm pack \
    && git -C "$R" switch -q -c other && tune '.owner.name = "Lee"' && git -C "$R" commit -qam lee \
    && git -C "$R" switch -q main && tune '.owner.name = "Kim"' && git -C "$R" commit -qam kim || fail "the fixture was not made"
  git -C "$R" merge -q other > /dev/null 2>&1 && fail "the merge did not conflict"
  out=$(loop setup pack-commit yes 2>&1) && fail "yes on a conflict exited 0: $out"
  grep -q 'project.json has a conflict' <<<"$out" && ! grep -q '^ask:' <<<"$out" || fail "the conflict was not said: $out"
  [ "$(git -C "$R" log -1 --format=%s)" = kim ] && git -C "$R" rev-parse -q --verify MERGE_HEAD > /dev/null || fail "the conflict was committed"
}
