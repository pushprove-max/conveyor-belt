#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: `conveyor.sh release-prep <version>` and `conveyor.sh release <version>`, a release made on the build
# machine (docs/releases.md, Making a release).
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
# than the remote's (the commit `release` releases); the notes draft misses commits since the last release, holds
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
# and `release`, which checks the status of the head it releases, runs the suite again. The draft is still written.
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

# Bug: a failing suite still posts a passing status, so `release` would release a red commit without running the suite.
t_relfail() {
  local O out
  relsetup false
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not fail on a failing suite: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on origin's head $O"
  ! grep -q 'state=success' "$STUB/gh-calls" && grep -q "statuses/$O -f state=failure -f context=conveyor/release-suite " "$STUB/gh-calls" \
    || fail "a failing suite did not post a failing status, or posted a passing one: $(cat "$STUB/gh-calls" 2>&1)"
  grep -q 'suite failed' <<<"$out" || fail "release-prep does not say the suite failed: $out"
}

# cutsetup <full-cmd> [<text>]: for `release`. main's pack names a whole suite ($STUB/full-cmd, which notes the commit
# it ran on); main holds plugin.json (p, 1.0.0) and a marketplace whose entry for p is pinned at v1.0.0 (and another
# plugin's entry), and <text> in old.txt when given; v1.0.0 is tagged there, then a commit adds
# docs/releases/1.1.0.md; origin has main and the tag. gh: `api` reads print $STUB/statuses ([] when there is none);
# `api -X POST` and `release` are noted in $STUB/gh-calls, and the notes file `release` is given is kept as
# $STUB/body. O is main's head, the commit to release.
cutsetup() {
  setup '[]'; tune '.test.full = ". \"$STUB/full-cmd\""'
  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' "$1" > "$STUB/full-cmd"
  printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" = release ] || [[ " $* " == *" -X POST "* ]]; then printf "%s\n" "$*" >> "$STUB/gh-calls"' \
    'while [ $# -gt 0 ]; do [ "$1" != --notes-file ] || cp "$2" "$STUB/body"; shift; done' \
    'else cat "$STUB/statuses" 2>/dev/null || echo "[]"; fi' > "$STUB/gh"
  mkdir -p "$R/.claude-plugin" "$R/docs/releases" && jq -n '{name: "p", version: "1.0.0"}' > "$R/.claude-plugin/plugin.json" \
    && jq -n --arg s "$(printf 'a%.0s' {1..40})" '{name: "m", plugins: [{name: "p", source: {source: "github", repo: "o/p", ref: "v1.0.0", sha: $s}},
      {name: "q", source: {source: "github", repo: "o/q", ref: "v9.0.0"}}]}' > "$R/.claude-plugin/marketplace.json" \
    && { [ -z "${2:-}" ] || echo "$2" > "$R/old.txt"; } \
    && git -C "$R" add -A && git -C "$R" commit -qm 'the first release' && git -C "$R" tag -a v1.0.0 -m 'Release 1.0.0' \
    && printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$R/docs/releases/1.1.0.md" && git -C "$R" add -A && git -C "$R" commit -qm 'fix: A fix' \
    && git -C "$R" push -q origin main v1.0.0 || fail "the fixture could not be made"
  O=$(git -C "$R" rev-parse HEAD)
}
# cutrefused <version> <reason (grep -E)>: release exits 1 naming the reason, and nothing is committed, tagged, pushed
# or released. Bug each caller catches: a release cut when that check fails, or one refused that still changed something.
cutrefused() {
  local out h; h=$(git -C "$R" rev-parse HEAD)
  out=$(loop release "$1" 2>&1); [ $? = 1 ] || fail "release was not refused: $out"
  grep -qE "refused, nothing tagged or released: .*$2" <<<"$out" || fail "the refusal does not say why ($2): $out"
  [ "$(git -C "$R" rev-parse HEAD)" = "$h" ] && [ -z "$(git -C "$R" tag -l "v$1")" ] \
    || fail "a refused release committed or tagged: $(git -C "$R" log --oneline -3) $(git -C "$R" tag -l)"
  [ "$(git -C "$T/$CASE/origin" tag -l)" = v1.0.0 ] && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$O" ] \
    && ! grep -q '^release' "$STUB/gh-calls" 2>/dev/null || fail "a refused release pushed or released: $(git -C "$T/$CASE/origin" tag -l) $(cat "$STUB/gh-calls" 2>&1)"
}

# The cheap checks come before the suite, which is not run when one of them refuses.
t_cutlower() {
  local O; cutsetup true
  cutrefused 0.9.0 'the version 0.9.0 is not higher than the newest release, v1.0.0'
  [ ! -e "$STUB/full-at" ] || fail "the suite ran for a release refused before it"
}
t_cutnotes() { local O; cutsetup true; cutrefused 1.2.0 'no release notes: docs/releases/1.2.0.md is missing'; }
# The uncommitted change stays as it was.
t_cutdirty() {
  local O; cutsetup true; echo changed >> "$R/a.txt"
  cutrefused 1.1.0 'the checkout has uncommitted changes'
  [ "$(tail -n 1 "$R/a.txt")" = changed ] || fail "the refusal changed the uncommitted file"
}
# A commit the remote does not have would be released without being on GitHub's main.
t_cutahead() {
  local O; cutsetup true; git -C "$R" commit -q --allow-empty -m 'not pushed'
  cutrefused 1.1.0 'the checkout is not on main at the head of origin/main'
}
# A private text added and removed again since the last release is still found, by the commit that added it.
t_cutprivacy() {
  local O h AT=@; cutsetup true
  echo "someone${AT}gmail.com" > "$R/new.txt" && git -C "$R" add new.txt && git -C "$R" commit -qm add && h=$(git -C "$R" rev-parse HEAD) \
    && git -C "$R" rm -q new.txt && git -C "$R" commit -qm remove && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  cutrefused 1.1.0 "privacy check finds something in commits since v1.0.0: ${h:0:12}"
}
# A private text in a tracked file from before the last release, which no commit since it touches.
t_cutfiles() {
  local O AT=@; cutsetup true "someone${AT}gmail.com"
  cutrefused 1.1.0 'privacy check finds something in the tracked files.*old.txt:1: email'
}
t_cutfail() {
  local O; cutsetup false
  cutrefused 1.1.0 'the whole suite did not pass'
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on the commit to release"
}
# Bug: a commit made in the checkout while the suite ran (a card landed there) is tagged and pushed unchecked.
t_cutmoved() {
  local O out; cutsetup 'git -C "$R" commit -q --allow-empty -m "landed meanwhile"'
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] && grep -q 'refused, nothing tagged or released: the checkout moved or changed while the suite ran' <<<"$out" \
    || fail "a checkout that moved during the suite was not refused: $out"
  [ -z "$(git -C "$R" tag -l v1.1.0)" ] && [ "$(git -C "$T/$CASE/origin" tag -l)" = v1.0.0 ] && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$O" ] \
    && [ "$(git -C "$R" log -1 --format=%s)" = 'landed meanwhile' ] || fail "the refused release tagged, pushed or committed"
}
# All checks pass, with no status from release-prep: the suite runs; the tag is on a commit whose plugin.json says
# 1.1.0 and whose marketplace names v1.1.0; main's marketplace pins v1.1.0 at that commit, the other entry untouched;
# origin has both; the GitHub release is v1.1.0 with the notes as its body. The help says only the owner decides.
t_cutpass() {
  local O t out; cutsetup true
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on the commit to release"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}' 2>/dev/null) && [ "$(git -C "$T/$CASE/origin" cat-file -t v1.1.0)" = tag ] \
    || fail "origin has no annotated tag v1.1.0"
  [ "$(git -C "$R" show "$t:.claude-plugin/plugin.json" | jq -r .version)" = 1.1.0 ] || fail "plugin.json's version at the tag is not 1.1.0"
  [ "$(git -C "$R" show "$t:.claude-plugin/marketplace.json" | jq -c '.plugins[0].source | [.ref, .sha]')" = '["v1.1.0",null]' ] \
    || fail "the marketplace at the tag does not name v1.1.0, or still pins the old sha"
  [ "$(git -C "$T/$CASE/origin" show main:.claude-plugin/marketplace.json | jq -c '[.plugins[].source | [.ref, .sha]]')" = "[[\"v1.1.0\",\"$t\"],[\"v9.0.0\",null]]" ] \
    && [ "$(git -C "$T/$CASE/origin" rev-parse main^)" = "$t" ] || fail "origin's main does not pin v1.1.0 at the tagged commit $t, right after it"
  grep -q '^release create v1.1.0 --verify-tag ' "$STUB/gh-calls" && cmp -s "$STUB/body" "$R/docs/releases/1.1.0.md" \
    || fail "the GitHub release is not v1.1.0 with the notes file as its body: $(cat "$STUB/gh-calls" 2>&1)"
  loop release --help | grep -q 'Only the owner decides a release: the Foreman runs conveyor.sh release only after the owner says yes in chat' \
    || fail "the help does not say only the owner decides a release"
}
# Bug: a release-prep pass on the same commit is not taken, and the whole suite runs again.
t_cutprepped() {
  local O out; cutsetup false
  echo '[{"context":"conveyor/release-suite","state":"success"},{"context":"conveyor/release-suite","state":"failure"}]' > "$STUB/statuses"
  out=$(loop release 1.1.0 2>&1) || fail "the release with release-prep's pass was refused: $out"
  [ ! -e "$STUB/full-at" ] && [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] || fail "the suite ran again, or no tag was pushed: $out"
}
