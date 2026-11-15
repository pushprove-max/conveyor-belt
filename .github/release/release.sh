#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The release (docs/releases.md, Making a release): what .github/workflows/release.yml runs, in a checkout of the commit to release
# with every tag, and the repository's token for gh.
# Usage: release.sh <version X.Y.Z>, with RELEASE_ACTOR (github.actor), RELEASE_TRIGGER (github.triggering_actor: who
# started a re-run), RELEASE_OWNER (github.repository_owner), RELEASE_REF (github.ref), RELEASE_SHA (github.sha: main's
# head when the run started) and GITHUB_REPOSITORY (owner/name) set.
# It refuses, changing nothing, and names each reason, unless all of:
# - both actors are the repository owner, and the run is of main (refused first, before anything else is read);
# - the version is X.Y.Z, higher than the newest vX.Y.Z tag, and its tag does not exist;
# - the commit's newest commit status conveyor/release-suite (posted by `conveyor.sh release-prep` on the build
#   machine) is success;
# - the privacy check (conveyor/privacy/check.sh, its generic patterns: there is no terms file here) finds nothing in
#   the changes since the newest tag: each commit's message and added lines, so a hit a later commit removed is still
#   one. With no tag yet, it checks every file of the commit;
# - docs/releases/<version>.md exists on the commit and is not empty.
# Then: a commit (made only when either changes) sets plugin.json's version and the marketplace entry's ref to
# v<version>, with no sha; the annotated tag v<version> is made on it; a second commit sets the entry's sha to that
# tagged commit, since a commit cannot hold its own id. Main and the tag are pushed together (--atomic: if main moved
# since the run started, neither is), then the GitHub release is made with the notes file as its body.
set -uo pipefail
CONTEXT=conveyor/release-suite
P=.claude-plugin/plugin.json M=.claude-plugin/marketplace.json
die() { echo "release: $*" >&2; exit 1; }
v=${1:-} owner=${RELEASE_OWNER:-} actor=${RELEASE_ACTOR:-} trigger=${RELEASE_TRIGGER:-${RELEASE_ACTOR:-}} sha=${RELEASE_SHA:-}
[ -n "$owner" ] && [ "$actor" = "$owner" ] && [ "$trigger" = "$owner" ] \
  || die "refused, nothing tagged or released: only the repository owner ($owner) makes a release; this run is ${trigger:-nobody}'s"
[ "${RELEASE_REF:-}" = refs/heads/main ] || die "refused, nothing tagged or released: a release is made from main, not ${RELEASE_REF:-no ref}"
[ -n "${GITHUB_REPOSITORY:-}" ] && [ "$(git rev-parse -q --verify HEAD)" = "$sha" ] \
  || die "refused, nothing tagged or released: the checkout is not of the commit RELEASE_SHA names (${sha:-none}), or GITHUB_REPOSITORY is not set"
why=()
last=$(git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
if ! [[ $v =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then why+=("the version '$v' is not X.Y.Z")
elif git rev-parse -q --verify "refs/tags/v$v" > /dev/null; then why+=("the tag v$v already exists")
elif [ -n "$last" ] && [ "$(printf '%s\n' "${last#v}" "$v" | sort -V | tail -n 1)" != "$v" ]; then why+=("the version $v is not higher than the newest release, $last")
fi
state=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/statuses?per_page=100" | jq -r --arg c "$CONTEXT" '[.[] | select(.context == $c)][0].state // "none"') \
  || state="unreadable"
[ "$state" = success ] || why+=("the commit ${sha:0:12} has no passing whole-suite status ($CONTEXT is $state): run conveyor.sh release-prep on the build machine")
hits=()
if [ -n "$last" ]; then
  while read -r c; do
    { git log -1 --format=%B "$c"; git show --format= --no-color --no-ext-diff --text -U0 --diff-merges=first-parent "$c" | grep '^+' | grep -vE '^\+\+\+ (b/|/dev/null)'; } \
      | bash conveyor/privacy/check.sh - > /dev/null; rc=${PIPESTATUS[1]} # the check's own: grep finding no added line is no hit
    [ $rc = 0 ] || hits+=("${c:0:12}$([ $rc = 1 ] || echo ' (the check failed)')")
  done < <(git rev-list "$last..$sha")
  [ ${#hits[@]} = 0 ] || why+=("the privacy check finds something in commits since $last: ${hits[*]} (run conveyor/privacy/check.sh on each to see where)")
else
  git ls-files -z | xargs -0 bash conveyor/privacy/check.sh > /dev/null || why+=("the privacy check finds something in the files of ${sha:0:12} (there is no release tag yet)")
fi
notes=docs/releases/$v.md
[ -n "$(git show "$sha:$notes" 2>/dev/null | tr -d '[:space:]')" ] || why+=("there are no release notes: $notes is missing or empty on ${sha:0:12}")
if [ ${#why[@]} != 0 ]; then
  printf 'release: refused, nothing tagged or released: %s\n' "${why[@]}" >&2; exit 1
fi
name=$(jq -r .name "$P") && [ -n "$(jq --arg n "$name" '.plugins[] | select(.name == $n)' "$M")" ] || die "no marketplace entry for the plugin '$name'; nothing tagged or released"
ed() { jq "${@:2}" "$1" > "$1.new" && mv "$1.new" "$1"; } # <file> <jq arguments>
ed "$P" --arg v "$v" '.version = $v' && ed "$M" --arg n "$name" --arg r "v$v" '(.plugins[] | select(.name == $n) | .source) |= (.ref = $r | del(.sha))' \
  || die "plugin.json or marketplace.json could not be changed; nothing tagged or released"
{ git diff --quiet || git commit -qam "Release $v"; } && git tag -a "v$v" -m "Release $v" && t=$(git rev-parse HEAD) \
  && ed "$M" --arg n "$name" --arg s "$t" '(.plugins[] | select(.name == $n) | .source.sha) = $s' && git commit -qam "Release $v: the marketplace pins v$v at its commit" \
  || die "the release commits or the tag could not be made; nothing pushed"
git push -q --atomic origin "HEAD:refs/heads/main" "refs/tags/v$v" || die "main and v$v could not be pushed (did main move since the run started?); nothing released"
gh release create "v$v" --verify-tag --title "$v" --notes-file "$notes" || die "v$v is pushed, but its GitHub release could not be made: make it from the tag with $notes as its body"
echo "release: v$v is released at ${t:0:12}"
