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
  [ "$(grep -c "to each run of step 1's setup command" "$SRC/../commands/setup.md")" -eq 3 ] \
    && grep -q '^`setup pack-commit` in step 3: it takes no other argument' "$SRC/../commands/setup.md" \
    || fail "setup.md does not keep --foreman, --pin and --survey to step 1's setup command"
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
