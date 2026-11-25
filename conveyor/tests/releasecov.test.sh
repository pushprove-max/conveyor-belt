#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the coverage map each release makes again and commits (issue 1593; the pack's coverageMap,
# lib/relcov.sh). Their fixture is covsetup, below, on releaseboard.test.sh's runsetup (release.test.sh's cutsetup);
# t_relcovdevbox's is suitehost.test.sh's devboxsetup.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# covcmd <command lines>...: the pack's coverageMap a command that notes the folder it runs in ($STUB/cov-at), then
# runs <command lines>, its map cov.jsonl. covsetup <command lines>...: runsetup with a passing suite, and covcmd.
covcmd() {
  tune '.coverageMap = {command: ". \"$STUB/cov-cmd\"", file: "cov.jsonl"}'
  printf '%s\n' 'echo "$PWD" >> "$STUB/cov-at"' "$@" > "$STUB/cov-cmd"
}
covsetup() { runsetup true; covcmd "$@"; }
# Bug: no release made the coverage map again, so it went stale as functions changed. release-prep's pass runs the
# command in the worktree of the commit it tested; the release after it, which runs no suite on that pass, commits the
# map in its release commit. The command fails after it wrote the map (as coverage.sh does when a unit fails): it is
# named, and its map is still committed.
t_relcovmap() {
  local O out t
  covsetup 'git rev-parse HEAD > cov.jsonl' 'echo "a unit failed"; exit 1'
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed: $out"
  grep -qF "the coverage map's command failed (exit 1)" <<<"$out" && grep -qF 'a unit failed' <<<"$out" \
    || fail "release-prep did not name the coverage command's failure and its output: $out"
  [ "$(grep -c . "$STUB/cov-at" 2>/dev/null)" = 1 ] && [ "$(cat "$STUB/cov-at")" != "$R" ] \
    || fail "the coverage command did not run once, in the suite's worktree: $(cat "$STUB/cov-at" 2>&1)"
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  [ "$(wc -l < "$STUB/runs")" = 1 ] && [ "$(grep -c . "$STUB/cov-at")" = 1 ] || fail "the release ran the suite or the coverage command again: $out"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}') || fail "origin has no tag v1.1.0: $out"
  [ "$(git -C "$R" show "$t:cov.jsonl" 2>&1)" = "$O" ] && [ "$(git -C "$R" rev-parse "$t^")" = "$O" ] \
    || fail "the release commit $t does not hold the map the command wrote on $O: $(git -C "$R" show --stat "$t" 2>&1)"
}
# Bug: release-prep made no map after a failed suite, and release --anyway runs none, so a release over a failed suite
# (releaseanyway.test.sh's anysetup) committed no fresh map. The failed run makes it, and the release commits it.
t_relcovanyway() {
  local O out t
  anysetup; covcmd 'git rev-parse HEAD > cov.jsonl'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not fail on the red suite: $out"
  grep -qF "the coverage map of ${O:0:12} is kept for its release to commit" <<<"$out" || fail "the failed suite made no coverage map: $out"
  out=$(loop release 1.1.0 --anyway --by 'the owner' 2>&1) || fail "--anyway over the red suite was refused: $out"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}') || fail "origin has no tag v1.1.0: $out"
  [ "$(git -C "$R" show "$t:cov.jsonl" 2>&1)" = "$O" ] && [ "$(grep -c . "$STUB/cov-at")" = 1 ] \
    || fail "the release over the failed suite did not commit the map made once on $O: $(git -C "$R" show --stat "$t" 2>&1)"
}
# Bug: a release whose push fails left the map it put in the checkout there, staged, so the checkout was not as the
# release found it. The command moves origin's main (as a card that lands meanwhile does), so the push fails.
t_relcovundo() {
  local O out
  covsetup 'echo map > cov.jsonl' 'git commit -q --allow-empty -m landed && git push -q origin HEAD:refs/heads/main'
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'could not be pushed' <<<"$out" || fail "the release's push did not fail: $out"
  [ ! -e "$R/cov.jsonl" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$O" ] && [ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] \
    || fail "the undone release left the map or a change in the checkout: $(git -C "$R" status --porcelain 2>&1) $(git -C "$R" log --oneline -2)"
}
# Bug: a suite run on a devbox (or a box over ssh) made no map, so this project's releases, whose suite runs on a
# devbox, never refreshed it. The command runs here, in the worktree of the tested commit, once the devbox's lease is
# given back (a traced run holds no leased box).
t_relcovdevbox() {
  local O out
  runsetup "$BOXSUITE"; devboxsetup 3; covcmd '[ ! -e "$STUB/devbox-leased" ] || echo "lease held" >> "$STUB/cov-at"' 'echo map > cov.jsonl'
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep on the devbox failed: $out"
  [ "$(cat "$STUB/full-pwd" 2>&1)" = "$BOX/wt" ] || fail "the suite did not run on the devbox: $(cat "$STUB/full-pwd" 2>&1)"
  [ "$(cat "$STUB/cov-at" 2>&1)" = "$T/$CASE/cards/release/wt" ] && grep -qF "the coverage map of ${O:0:12} is kept for its release to commit" <<<"$out" \
    || fail "the coverage command did not run once here, in the suite's worktree, after the lease was given back: $(cat "$STUB/cov-at" 2>&1): $out"
}
# Bug: a release replaced a map in the checkout that no commit holds (the Foreman's first map, made by hand), and its
# undo then deleted it. The release leaves it as it is and commits no map; its push fails (the command moves origin's
# main), so its undo runs too.
t_relcovhand() {
  local O out
  covsetup 'echo new > cov.jsonl' 'git commit -q --allow-empty -m landed && git push -q origin HEAD:refs/heads/main'
  echo hand > "$R/cov.jsonl"
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'could not be pushed' <<<"$out" || fail "the release's push did not fail: $out"
  grep -qF 'holds a cov.jsonl that' <<<"$out" && [ "$(cat "$R/cov.jsonl" 2>&1)" = hand ] && [ -z "$(git -C "$R" ls-files cov.jsonl)" ] \
    || fail "the release did not leave the hand-made map as it was, or did not say so: $(cat "$R/cov.jsonl" 2>&1): $out"
}
# Bug: the release pushed the map with no privacy check: the checks of the tracked files run before the map is put in
# the checkout. A map with a person's email is not committed, and the release goes out without it.
t_relcovprivacy() {
  local O out t AT=@
  covsetup "echo 'a case of other${AT}mail.io' > cov.jsonl"
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}') || fail "origin has no tag v1.1.0: $out"
  grep -qF 'the privacy check finds something in the coverage map' <<<"$out" && ! git -C "$R" cat-file -e "$t:cov.jsonl" 2>/dev/null && [ ! -e "$R/cov.jsonl" ] \
    || fail "the release committed a map the privacy check finds a hit in, or did not say why it left it out: $(git -C "$R" show --stat "$t" 2>&1): $out"
}
