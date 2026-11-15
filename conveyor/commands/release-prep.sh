# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh release-prep <version>` and `conveyor.sh release <version>`: a release, made on the build machine
# (docs/releases.md, Making a release). Only the owner decides a release: the Foreman runs `release` only after the
# owner says yes in chat. One run of either at a time per project ($CARDS/release/lock).
# release-prep runs the pack's whole suite (test.full) on the remote's head of the default branch, in a worktree of
# that commit alone ($CARDS/release/wt), and posts the result on that commit as the commit status
# conveyor/release-suite: success when the suite passed, failure when it did not. `release` takes that status's newest
# state, success, as the suite's pass on the commit it releases. Before the run release-prep writes a draft of the
# release notes, the commits since the newest vX.Y.Z tag as bullets, to <state>/release/<version>.md, for the Foreman
# to edit and commit as docs/releases/<version>.md. The suite runs only when that head holds docs/releases/<version>.md:
# `release` releases the commit with the notes, so the first run writes the draft and stops, and the run after the
# notes are pushed runs the suite. It tags and releases nothing.
# Exit 0: passed and posted; 1: the suite failed (failure posted), the head has no notes yet (draft written, nothing
# run) or a step could not be done; 2: refused at the ask.
# release, in the main checkout, refuses (exit 1), changing nothing and naming each reason, unless all of:
# - the version is higher than the newest vX.Y.Z tag of the remote, and its tag does not exist;
# - the checkout is on the default branch, at the remote's head of it, with no uncommitted change to a tracked file;
# - docs/releases/<version>.md is on that commit and is not empty;
# - the privacy check (privacy/check.sh, with the host file's terms file, as gh_write() runs it) finds nothing in the
#   tracked files, nor in the changes since the newest tag: each commit's message and added lines, so a hit a later
#   commit removed is still one;
# - the whole suite passed on that commit: the newest conveyor/release-suite status is success (release-prep's
#   pass), else this command runs the suite, as release-prep does, once every other check has passed.
# Then: a commit (made only when either changes) sets plugin.json's version and the marketplace entry's ref to
# v<version>, with no sha; the annotated tag v<version> is made on it; a second commit sets the entry's sha to that
# tagged commit, since a commit cannot hold its own id. The branch and the tag are pushed together (--atomic: if the
# remote's branch moved, neither is, and the commits and the tag are undone here), then the GitHub release is made
# with the notes file as its body (gh release create). Exit 0: released; 1: refused, or a step could not be done.
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
RELHELP="Only the owner decides a release: the Foreman runs conveyor.sh release only after the owner says yes in chat."
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
# The release lock, held until the command ends. 1: it could not be made; 2: another run holds it.
rellock() { # <command name>
  local lk
  mkdir -p "$CARDS/release" && { exec {lk}>>"$CARDS/release/lock"; } 2>/dev/null || { echo "conveyor: $1: its lock could not be made; nothing run" >&2; return 1; }
  flock -n "$lk" || { echo "conveyor: $1: release-prep or release is already running; this one is not started" >&2; return 2; }
}
# The newest vX.Y.Z tag, after the remote's branch and tags are fetched.
lasttag() { git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1; }
# The whole suite (test.full) on <commit>, in a worktree of it alone, its result posted on it as conveyor/release-suite.
# 0: passed and posted; 1: failed (failure posted), or a step could not be done; 2: the pack names no test.full.
relsuite() { # <command name> <commit>
  local n=$1 sha=$2 cmd wt=$CARDS/release/wt out rc state desc
  packget test.full cmd || return 1
  [ -n "$cmd" ] || { echo "conveyor: $n: the pack names no full test suite (test.full); nothing run" >&2; return 2; }
  out=$({ git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt" "$wt".*; git worktree prune
    git worktree add -q --detach "$wt" "$sha" && deps "$wt"; } 2>&1 < /dev/null) || {
    git worktree remove --force "$wt" 2>/dev/null; echo "conveyor: $n: the worktree of ${sha:0:12} could not be made; nothing run: ${out:0:600}" >&2; return 1; }
  tests "$wt" test.full; rc=$?
  git worktree remove --force "$wt" 2>/dev/null
  if [ $rc = 0 ]; then state=success desc="The whole suite (test.full) passed on the build machine"
  else state=failure desc="The whole suite (test.full) failed on the build machine (exit $rc)"; fi
  gh_write api -X POST "repos/{owner}/{repo}/statuses/$sha" -f "state=$state" -f context=conveyor/release-suite -f "description=$desc" > /dev/null \
    || { echo "conveyor: $n: the status of ${sha:0:12} could not be posted (the suite $([ $rc = 0 ] && echo passed || echo failed))" >&2; return 1; }
  if [ $rc = 0 ]; then echo "conveyor: $n: the whole suite passed on ${sha:0:12}; its status is posted"
  else echo "conveyor: $n: the whole suite failed on ${sha:0:12} (exit $rc; its output is in $wt.test); a failing status is posted" >&2; return 1; fi
}
releaseprep() { # <version>
  local v=$1 cmd sha last d
  packget test.full cmd || return 1
  [ -n "$cmd" ] || { echo "conveyor: release-prep: the pack names no full test suite (test.full); nothing run" >&2; return 2; }
  rellock release-prep || return $?
  # The commit `release` releases is the remote's head of the branch, and the tags are the remote's.
  git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 'refs/tags/v*:refs/tags/v*' < /dev/null \
    && sha=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") || { echo "conveyor: release-prep: $REMOTE/$BRANCH could not be read; nothing run" >&2; return 1; }
  last=$(lasttag)
  d=${STATE%/*}/release/$v.md
  mkdir -p "${d%/*}" && relnotes "$v" "$last" "$sha" "$d" || { echo "conveyor: release-prep: the notes draft could not be written; nothing run" >&2; return 1; }
  # `release` releases the remote's head and reads the status of that commit, so the suite runs only on a head that
  # holds the notes: a status posted before the notes are committed is on a commit the release does not use.
  [ -n "$(git show "$sha:docs/releases/$v.md" 2>/dev/null | tr -d '[:space:]')" ] || {
    echo "conveyor: release-prep: the notes draft, from the commits since ${last:-the first commit}, is $d. ${sha:0:12} ($REMOTE/$BRANCH) has no docs/releases/$v.md, so the suite is not run and no status is posted: edit the draft, commit it as docs/releases/$v.md on $BRANCH, push it, and run release-prep $v again" >&2
    return 1; }
  echo "conveyor: release-prep: the notes draft, from the commits since ${last:-the first commit}, is $d; ${sha:0:12} holds docs/releases/$v.md"
  relsuite release-prep "$sha"
}
release() { # <version>
  local v=$1 sha last c rc out terms name t state notes=docs/releases/$1.md why=() hits=()
  local P=.claude-plugin/plugin.json M=.claude-plugin/marketplace.json
  rellock release || return 1
  git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 'refs/tags/v*:refs/tags/v*' < /dev/null \
    && sha=$(git rev-parse -q --verify 'HEAD^{commit}') \
    || { echo "conveyor: release: refused, nothing tagged or released: $REMOTE/$BRANCH or the checkout's HEAD could not be read" >&2; return 1; }
  [ "$(git symbolic-ref -q HEAD)" = "refs/heads/$BRANCH" ] && [ "$sha" = "$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}")" ] \
    || why+=("the checkout is not on $BRANCH at the head of $REMOTE/$BRANCH")
  [ -z "$(git status --porcelain --untracked-files=no)" ] || why+=("the checkout has uncommitted changes")
  last=$(lasttag)
  if git rev-parse -q --verify "refs/tags/v$v" > /dev/null; then why+=("the tag v$v already exists")
  elif [ -n "$last" ] && [ "$(printf '%s\n' "${last#v}" "$v" | sort -V | tail -n 1)" != "$v" ]; then why+=("the version $v is not higher than the newest release, $last")
  fi
  [ -n "$(git show "$sha:$notes" 2>/dev/null | tr -d '[:space:]')" ] || why+=("there are no release notes: $notes is missing or empty on ${sha:0:12}")
  terms=$(termsfile)
  if [ -z "$terms" ] && termsnamed; then why+=("the host file's terms file cannot be read, so the privacy check cannot be made")
  else
    out=$(git ls-files -z | xargs -0 "$HERE/privacy/check.sh" ${terms:+--terms "$terms"} 2>&1) \
      || why+=("the privacy check finds something in the tracked files, or cannot read one: $(head -n 5 <<<"$out" | paste -sd ';' -)")
    if [ -n "$last" ]; then
      while read -r c; do
        { git log -1 --format=%B "$c"; git show --format= --no-color --no-ext-diff --text -U0 --diff-merges=first-parent "$c" | grep '^+' | grep -vE '^\+\+\+ (b/|/dev/null)'; } \
          | "$HERE/privacy/check.sh" ${terms:+--terms "$terms"} - > /dev/null; rc=${PIPESTATUS[1]} # the check's own: grep finding no added line is no hit
        [ "$rc" = 0 ] || hits+=("${c:0:12}$([ "$rc" = 1 ] || echo ' (the check failed)')")
      done < <(git rev-list "$last..$sha")
      [ ${#hits[@]} = 0 ] || why+=("the privacy check finds something in commits since $last: ${hits[*]} (run conveyor/privacy/check.sh on each to see where)")
    fi
  fi
  name=$(jq -r .name "$P" 2>/dev/null) && [ -n "$(jq --arg n "$name" '.plugins[] | select(.name == $n)' "$M" 2>/dev/null)" ] \
    || why+=("$M has no entry for the plugin $P names")
  if [ ${#why[@]} != 0 ]; then printf 'conveyor: release: refused, nothing tagged or released: %s\n' "${why[@]}" >&2; return 1; fi
  # The suite last: it takes the longest, and a refusal above needs none of it.
  state=$(timeout 60 gh api "repos/{owner}/{repo}/commits/$sha/statuses?per_page=100" < /dev/null 2>/dev/null \
    | jq -r '[.[] | select(.context == "conveyor/release-suite")][0].state // "none"' 2>/dev/null)
  if [ "$state" = success ]; then echo "conveyor: release: the whole suite passed on ${sha:0:12} (release-prep's status); it is not run again"
  else relsuite release "$sha" || { echo "conveyor: release: refused, nothing tagged or released: the whole suite did not pass on ${sha:0:12}" >&2; return 1; }; fi
  # The suite takes long: a checkout that moved meanwhile would tag commits no check above read.
  [ "$(git rev-parse -q --verify HEAD)" = "$sha" ] && [ -z "$(git status --porcelain --untracked-files=no)" ] \
    || { echo "conveyor: release: refused, nothing tagged or released: the checkout moved or changed while the suite ran" >&2; return 1; }
  # A step that fails undoes what was made here: the tag, the commits, and the two files' changes, nothing else.
  relundo() { git tag -d "v$v" > /dev/null 2>&1; git reset -q "$sha" && git checkout -q "$sha" -- "$P" "$M"; }
  relset() { jq "${@:2}" "$1" > "$1.new" && mv "$1.new" "$1"; } # <file> <jq arguments>
  relset "$P" --arg v "$v" '.version = $v' && relset "$M" --arg n "$name" --arg r "v$v" '(.plugins[] | select(.name == $n) | .source) |= (.ref = $r | del(.sha))' \
    && { git diff --quiet -- "$P" "$M" || git commit -q -m "Release $v" -- "$P" "$M"; } && git tag -a "v$v" -m "Release $v" && t=$(git rev-parse HEAD) \
    && relset "$M" --arg n "$name" --arg s "$t" '(.plugins[] | select(.name == $n) | .source.sha) = $s' \
    && git commit -q -m "Release $v: the marketplace pins v$v at its commit" -- "$M" \
    || { relundo; echo "conveyor: release: the release commits or the tag could not be made; they are undone, nothing pushed" >&2; return 1; }
  git push -q --atomic "$REMOTE" "HEAD:refs/heads/$BRANCH" "refs/tags/v$v" < /dev/null \
    || { relundo; echo "conveyor: release: $BRANCH and v$v could not be pushed (did $REMOTE/$BRANCH move?); the release commits and the tag are undone, nothing released" >&2; return 1; }
  gh_write release create "v$v" --verify-tag --title "$v" --notes-file "$notes" < /dev/null \
    || { echo "conveyor: release: v$v is pushed, but its GitHub release could not be made: make it from the tag with $notes as its body" >&2; return 1; }
  echo "conveyor: release: v$v is released at ${t:0:12}"
}
shift
if [ "$CMD_ARG" = release ]; then
  [ "${1:-}" != --help ] || { echo "usage: conveyor.sh release <version: X.Y.Z>"; echo "$RELHELP"; exit 0; }
  [ $# = 1 ] && [[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { printf 'usage: conveyor.sh release <version: X.Y.Z>\n%s\n' "$RELHELP" >&2; exit 2; }
  release "$1"
else
  [ $# = 1 ] && [[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "usage: conveyor.sh release-prep <version: X.Y.Z>" >&2; exit 2; }
  releaseprep "$1"
fi
