# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh release-prep <version>` and `conveyor.sh release <version>`: a release, made on the build machine
# (docs/releases.md, Making a release). Only the owner decides a release: the Foreman runs `release` only after the
# owner says yes in chat. One run of either at a time per project ($CARDS/release/lock).
# release-prep runs the pack's whole suite (test.full) on the remote's head of the default branch, in a worktree of
# that commit alone ($CARDS/release/wt), and posts the result on that commit as the commit status
# conveyor/release-suite: success when the suite passed, failure when it did not. `release` takes that status's newest
# state, success, as the suite's pass on the commit it releases. The suite runs only when that head holds
# docs/releases/<version>.md in the release notes style (tools/notes-check.sh): `release` releases the commit with the
# notes. When the head has no notes, release-prep has a model write a draft of them in that style (relnotes()), from
# the issues landed and the commits since the newest vX.Y.Z tag, to <state>/release/<version>.md, prints its path and
# stops, for the owner to read and the Foreman to commit as docs/releases/<version>.md; the run after the notes are
# pushed runs the suite. It tags and releases nothing.
# Exit 0: passed and posted; 1: the suite failed (failure posted), the head has no notes yet (draft written, nothing
# run), its notes break the style, or a step could not be done; 2: refused at the ask.
# release, in the main checkout, refuses (exit 1), changing nothing and naming each reason, unless all of:
# - the version is higher than the newest vX.Y.Z tag of the remote, and its tag does not exist;
# - the checkout is on the default branch, at the remote's head of it, with no uncommitted change to a tracked file;
# - docs/releases/<version>.md is on that commit, is not empty, and passes the notes style check (tools/notes-check.sh);
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
RELNOTES_TIMEOUT=600
# The style of the release notes, docs/releases.md (Release notes); tools/notes-check.sh checks its mechanical rules.
RELNOTES='Write the release notes of a new release of this project, from the issues that landed since the last release and
the subjects of its commits, given below. They are for the people who use the project, not for its developers.
- Begin with the line "# VERSION", then one sentence that says what this release is about.
- Then "## " sections named for what a user does or sees (for example: Cards, The Board, In Claude Code, Setup). No
  "###" headings.
- Plain-English bullets about the effect for the user, one change per bullet.
- No file, script or function names, no paths, no issue or pull request numbers, no commit hashes, no "Closes", no
  internal unit names. Names a person types or sees (a slash command, a setup question, a setting, a button) are
  allowed.
- Leave out changes that only touch tests, refactors or tooling, or put them in one plain line if they change nothing
  a user sees.
Answer with the notes alone, in Markdown, and nothing else.'
# The notes draft (<file>), written by a model (askmodel) from the issues the commits since <last tag> up to <commit>
# name ("(#N)" at a subject's end, or a "Closes #N" line: their titles and bodies, as gh reads them) and those commits'
# subjects, merges left out, each with its trailing (#N) taken off. An issue gh cannot read is left out, with a
# warning; its commit's subject is still given. Fails, with why on stdout, when the model gives no notes.
relnotes() { # <version> <last tag, or empty> <commit> <file>
  local subj ns n j iss='[]' p d rc s c
  subj=$(git log --no-merges --format=%s "${2:+$2..}$3" | sed -E 's/ \(#[0-9]+\)$//') && ns=$(git log --no-merges --format=%B "${2:+$2..}$3") || { echo "the commits could not be read"; return 1; }
  for n in $(grep -oE '(\(#[0-9]+\)$|^Closes #[0-9]+)' <<<"$ns" | grep -oE '[0-9]+' | sort -un); do
    j=$(timeout 60 gh issue view "$n" --json number,title,body < /dev/null 2>/dev/null) && iss=$(jq -c --argjson i "$j" '. + [$i]' <<<"$iss" 2>/dev/null) \
      || echo "conveyor: release-prep: issue #$n could not be read; the notes are written without it" >&2
  done
  p=${RELNOTES//VERSION/$1}$'\n\n'$(jq -r --arg s "$subj" '"# The issues that landed\n\n" + (map("## \(.title // "")\n\n\((.body // "")[0:4000])\n") | join("\n"))
    + "\n# The commit subjects\n\n" + $s' <<<"$iss") || { echo "the issues could not be read"; return 1; }
  c=$(ctl 2>/dev/null) || c=''
  d=$(mktemp -d) || { echo "no scratch folder"; return 1; }
  s=$(askmodel "$d" "$RELNOTES_TIMEOUT" medium "$c" "$p"); rc=$?
  [ -z "$s" ] || { rm -rf "$d"; echo "$s"; return 1; }
  [ "$rc" = 0 ] && [ -n "$(tr -d '[:space:]' < "$d/answer" 2>/dev/null)" ] && cp "$d/answer" "$4" \
    || { rm -rf "$d"; echo "the model gave no notes (exit $rc; 124 is the ${RELNOTES_TIMEOUT}s timeout)"; return 1; }
  rm -rf "$d"
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
  local v=$1 cmd sha last d out
  packget test.full cmd || return 1
  [ -n "$cmd" ] || { echo "conveyor: release-prep: the pack names no full test suite (test.full); nothing run" >&2; return 2; }
  rellock release-prep || return $?
  # The commit `release` releases is the remote's head of the branch, and the tags are the remote's.
  git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 'refs/tags/v*:refs/tags/v*' < /dev/null \
    && sha=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") || { echo "conveyor: release-prep: $REMOTE/$BRANCH could not be read; nothing run" >&2; return 1; }
  last=$(lasttag)
  # `release` releases the remote's head and reads the status of that commit, so the suite runs only on a head that
  # holds the notes, in the notes style: a status posted on another commit is on one the release does not use.
  if [ -n "$(git show "$sha:docs/releases/$v.md" 2>/dev/null | tr -d '[:space:]')" ]; then
    out=$(git show "$sha:docs/releases/$v.md" | "$HERE/tools/notes-check.sh" - "docs/releases/$v.md") \
      || { echo "conveyor: release-prep: docs/releases/$v.md on ${sha:0:12} breaks the release notes style, so the suite is not run and no status is posted: $(head -n 10 <<<"$out" | paste -sd ';' -)" >&2; return 1; }
    echo "conveyor: release-prep: ${sha:0:12} holds docs/releases/$v.md"
    relsuite release-prep "$sha"; return
  fi
  d=${STATE%/*}/release/$v.md
  mkdir -p "${d%/*}" && rm -f "$d" && out=$(relnotes "$v" "$last" "$sha" "$d") || { echo "conveyor: release-prep: the notes draft could not be written: $out; nothing run" >&2; return 1; }
  out=$("$HERE/tools/notes-check.sh" "$d") || out=" The draft breaks the release notes style: $(head -n 10 <<<"$out" | paste -sd ';' -)."
  echo "conveyor: release-prep: the notes draft, from the issues and commits since ${last:-the first commit}, is $d.$out ${sha:0:12} ($REMOTE/$BRANCH) has no docs/releases/$v.md, so the suite is not run and no status is posted: read the draft, edit it as needed, commit it as docs/releases/$v.md on $BRANCH, push it, and run release-prep $v again" >&2
  return 1
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
  if [ -z "$(git show "$sha:$notes" 2>/dev/null | tr -d '[:space:]')" ]; then why+=("there are no release notes: $notes is missing or empty on ${sha:0:12}")
  elif ! out=$(git show "$sha:$notes" | "$HERE/tools/notes-check.sh" - "$notes"); then
    why+=("the release notes break the release notes style: $(head -n 10 <<<"$out" | paste -sd ';' -)")
  fi
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
