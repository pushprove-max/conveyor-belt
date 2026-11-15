#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: `conveyor.sh release-prep <version>`, the build machine's part of a release (docs/releases.md, Making a release).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# relsetup <full-cmd> [nonotes]: main's pack names a whole suite (test.full: $STUB/full-cmd, which notes the commit it
# ran on); origin has the release v1.0.0 and two commits after it, the last adding docs/releases/1.1.0.md (not with
# nonotes); main has one more commit origin lacks. gh records each call.
# O is origin's head, the commit release-prep must test and post on.
relsetup() {
  setup '[]'; tune '.test.full = ". \"$STUB/full-cmd\""'
  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' "$1" > "$STUB/full-cmd"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$STUB/gh-calls"\n' > "$STUB/gh"
  git -C "$R" commit -q --allow-empty -m 'fix: before the release (#1)' && git -C "$R" tag v1.0.0
  git -C "$R" commit -q --allow-empty -m 'feat(engine): A new thing (#5)' || fail "the fixture could not be made"
  [ "${2:-}" = nonotes ] || { mkdir -p "$R/docs/releases" && echo '- A fix' > "$R/docs/releases/1.1.0.md" && git -C "$R" add docs; } || fail "the fixture could not be made"
  git -C "$R" commit -q --allow-empty -m 'fix: A fix'
  git -C "$R" push -q origin main && git -C "$R" push -q origin v1.0.0 && git -C "$R" tag -d v1.0.0 > /dev/null || fail "the fixture could not be made"
  git -C "$R" commit -q --allow-empty -m 'feat: Not pushed yet'
  O=$(git -C "$T/$CASE/origin" rev-parse refs/heads/main)
}

# Bugs: a passing status is posted on a commit whose suite was not run or did not pass, or on main's local head rather
# than the remote's (the commit the workflow releases); the notes draft misses commits since the last release, holds
# ones before it, or names issue numbers.
t_relpass() {
  local O out
  relsetup true
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed on a passing suite: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on origin's head $O: $(cat "$STUB/full-at" 2>&1)"
  [ "$(grep -c statuses "$STUB/gh-calls")" = 1 ] && grep -q "statuses/$O -f state=success -f context=conveyor/release-suite " "$STUB/gh-calls" \
    || fail "no passing conveyor/release-suite status was posted on $O: $(cat "$STUB/gh-calls" 2>&1)"
  [ "$(cat "$ST/release/1.1.0.md")" = $'# 1.1.0\n\n## New\n\n- A new thing\n\n## Fixes\n\n- A fix' ] \
    || fail "the notes draft does not list the commits since v1.0.0 alone: $(cat "$ST/release/1.1.0.md" 2>&1)"
}

# Bug: the suite ran and its status was posted on a head without the notes; committing the notes then makes a new head,
# and the workflow, which checks the status of the head it releases, refuses it. The draft is still written.
t_relnonotes() {
  local O out
  relsetup true nonotes
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  [ ! -e "$STUB/full-at" ] || fail "the suite ran on a head with no notes"
  ! grep -q statuses "$STUB/gh-calls" 2>/dev/null || fail "a status was posted on a head with no notes: $(cat "$STUB/gh-calls")"
  grep -q 'has no docs/releases/1.1.0.md' <<<"$out" && grep -q 'run release-prep 1.1.0 again' <<<"$out" \
    || fail "release-prep does not say to commit the notes and run again: $out"
  [ "$(cat "$ST/release/1.1.0.md")" = $'# 1.1.0\n\n## New\n\n- A new thing\n\n## Fixes\n\n- A fix' ] \
    || fail "the notes draft was not written: $(cat "$ST/release/1.1.0.md" 2>&1)"
}

# Bug: a failing suite still posts a passing status, so the workflow would release a red commit.
t_relfail() {
  local O out
  relsetup false
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not fail on a failing suite: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on origin's head $O"
  ! grep -q 'state=success' "$STUB/gh-calls" && grep -q "statuses/$O -f state=failure -f context=conveyor/release-suite " "$STUB/gh-calls" \
    || fail "a failing suite did not post a failing status, or posted a passing one: $(cat "$STUB/gh-calls" 2>&1)"
  grep -q 'suite failed' <<<"$out" || fail "release-prep does not say the suite failed: $out"
}
