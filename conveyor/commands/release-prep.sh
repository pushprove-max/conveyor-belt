# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh release-prep <version>`: the build machine's part of a release (docs/releases.md, Making a release). It runs
# the pack's whole suite (test.full) on the remote's head of the default branch, in a worktree of that commit alone
# ($CARDS/release/wt), and posts the result on that commit as the commit status conveyor/release-suite: success when
# the suite passed, failure when it did not. The release workflow (.github/workflows/release.yml) releases a commit
# only when that status's newest state is success. Before the run it writes a draft of the release notes, the commits
# since the newest vX.Y.Z tag as bullets, to <state>/release/<version>.md, for the Foreman to edit and commit as
# docs/releases/<version>.md. The suite runs only when that head holds docs/releases/<version>.md: the workflow checks
# the status of the commit with the notes, so the first run writes the draft and stops, and the run after the notes
# are pushed runs the suite. It tags and releases nothing. One run at a time per project ($CARDS/release/lock).
# Exit 0: passed and posted; 1: the suite failed (failure posted), the head has no notes yet (draft written, nothing
# run) or a step could not be done; 2: refused at the ask.
# Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
# The notes draft (<file>): a heading, then the subjects of the commits since <last tag> up to <commit>, merges left
# out, each a bullet in New (feat), Fixes (fix) or Other changes, with its conventional-commit prefix and its
# trailing (#N) taken off: the notes name no issue or commit.
relnotes() { # <version> <last tag, or empty> <commit> <file>
  git log --no-merges --format=%s "${2:+$2..}$3" | jq -Rrs --arg v "$1" '
    [split("\n")[] | select(. != "") | (capture("^(?<k>[A-Za-z]+)(\\([^)]*\\))?!?: (?<s>.*)$") // {k: "", s: .})
      | .s |= sub(" \\(#[0-9]+\\)$"; "")] as $l
    | "# \($v)\n" + ([[["New", "feat"], ["Fixes", "fix"], ["Other changes", null]][] as [$h, $k]
      | [$l[] | select(if $k == null then .k != "feat" and .k != "fix" else .k == $k end) | "- \(.s)"]
      | select(length > 0) | "\n## \($h)\n\n" + join("\n") + "\n"] | join("")) ' > "$4"
}
releaseprep() { # <version>
  local v=$1 cmd lk sha last wt=$CARDS/release/wt d out rc state desc
  packget test.full cmd || return 1
  [ -n "$cmd" ] || { echo "conveyor: release-prep: the pack names no full test suite (test.full); nothing run" >&2; return 2; }
  mkdir -p "$CARDS/release" && { exec {lk}>>"$CARDS/release/lock"; } 2>/dev/null || { echo "conveyor: release-prep: its lock could not be made; nothing run" >&2; return 1; }
  flock -n "$lk" || { echo "conveyor: release-prep is already running; this one is not started" >&2; return 2; }
  # The commit the workflow releases is the remote's head of the branch, and the tags are the remote's.
  git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 'refs/tags/v*:refs/tags/v*' < /dev/null \
    && sha=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") || { echo "conveyor: release-prep: $REMOTE/$BRANCH could not be read; nothing run" >&2; return 1; }
  last=$(git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
  d=${STATE%/*}/release/$v.md
  mkdir -p "${d%/*}" && relnotes "$v" "$last" "$sha" "$d" || { echo "conveyor: release-prep: the notes draft could not be written; nothing run" >&2; return 1; }
  # The workflow releases the remote's head and reads the status of that commit, so the suite runs only on a head that
  # holds the notes: a status posted before the notes are committed is on a commit the release does not use.
  [ -n "$(git show "$sha:docs/releases/$v.md" 2>/dev/null | tr -d '[:space:]')" ] || {
    echo "conveyor: release-prep: the notes draft, from the commits since ${last:-the first commit}, is $d. ${sha:0:12} ($REMOTE/$BRANCH) has no docs/releases/$v.md, so the suite is not run and no status is posted: edit the draft, commit it as docs/releases/$v.md on $BRANCH, push it, and run release-prep $v again" >&2
    return 1; }
  echo "conveyor: release-prep: the notes draft, from the commits since ${last:-the first commit}, is $d; ${sha:0:12} holds docs/releases/$v.md"
  out=$({ git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt" "$wt".*; git worktree prune
    git worktree add -q --detach "$wt" "$sha" && deps "$wt"; } 2>&1 < /dev/null) || {
    git worktree remove --force "$wt" 2>/dev/null; echo "conveyor: release-prep: the worktree of ${sha:0:12} could not be made; nothing run: ${out:0:600}" >&2; return 1; }
  tests "$wt" test.full; rc=$?
  git worktree remove --force "$wt" 2>/dev/null
  if [ $rc = 0 ]; then state=success desc="The whole suite (test.full) passed on the build machine"
  else state=failure desc="The whole suite (test.full) failed on the build machine (exit $rc)"; fi
  gh_write api -X POST "repos/{owner}/{repo}/statuses/$sha" -f "state=$state" -f context=conveyor/release-suite -f "description=$desc" > /dev/null \
    || { echo "conveyor: release-prep: the status of ${sha:0:12} could not be posted (the suite $([ $rc = 0 ] && echo passed || echo failed))" >&2; return 1; }
  if [ $rc = 0 ]; then echo "conveyor: release-prep: the whole suite passed on ${sha:0:12}; its status is posted"
  else echo "conveyor: release-prep: the whole suite failed on ${sha:0:12} (exit $rc; its output is in $wt.test); a failing status is posted" >&2; return 1; fi
}
shift; [ $# = 1 ] && [[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "usage: conveyor.sh release-prep <version: X.Y.Z>" >&2; exit 2; }
releaseprep "$1"
