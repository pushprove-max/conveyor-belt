#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The repository's rulesets, kept as JSON in .github/rulesets/ and applied to GitHub with this script.
# Usage: rulesets.sh apply   (run in a checkout of the repository; GH_REPO names it when its remote does not)
# - main.json: main takes no force push and is not deleted; plain pushes stay allowed (the engine lands cards on main).
# - tags-fixed.json: a v* tag is never moved or deleted, by anyone.
# - tags-create.json: a v* tag is made only by a repository admin (the owner's `conveyor.sh release` on the build
#   machine pushes it), the admin role (id 5) being its one bypass actor. The tag rules are two rulesets because a
#   bypass actor passes every rule of its ruleset: in one ruleset, an admin could move and delete tags too. Its name
#   stays the one GitHub has, so apply updates that ruleset in place rather than making a second one beside it.
# For each file, the ruleset of the same name is updated (PUT) when the repository has one, else made (POST); a second
# run changes nothing more. Prints one "<made|updated> <name> (id <id>)" line a ruleset.
# Exit 0 when all are applied, 2 on a usage or API error (the ones before it stay applied).
set -uo pipefail
die() { echo "rulesets: $*" >&2; exit 2; }
[ $# = 1 ] && [ "$1" = apply ] || { echo "usage: rulesets.sh apply" >&2; exit 2; }
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.github/rulesets" 2>/dev/null && pwd -P) || die "no .github/rulesets folder"
W=$(mktemp -d) || exit 2; trap 'rm -rf "$W"' EXIT

gh api --paginate 'repos/{owner}/{repo}/rulesets?includes_parents=false' > "$W/list" 2>"$W/err" \
  || die "the rulesets cannot be read: $(head -c 300 "$W/err")"
n=0
for f in "$dir"/*.json; do
  [ -e "$f" ] || continue
  name=$(jq -er '.name | strings' "$f") || die "$f is not a ruleset with a name"
  id=$(jq -rs --arg n "$name" '[.[][] | select(.name == $n) | .id][0] // empty' "$W/list") \
    || die "the rulesets list is not JSON"
  if [ -n "$id" ]; then
    out=$(gh api --method PUT "repos/{owner}/{repo}/rulesets/$id" --input "$f" 2>"$W/err") \
      || die "$name could not be updated: $(head -c 300 "$W/err")"
    did=updated
  else
    out=$(gh api --method POST 'repos/{owner}/{repo}/rulesets' --input "$f" 2>"$W/err") \
      || die "$name could not be made: $(head -c 300 "$W/err")"
    did=made
  fi
  echo "$did $name (id $(jq -r '.id // "unknown"' <<<"$out" 2>/dev/null || echo unknown))"
  n=$((n + 1))
done
[ $n -gt 0 ] || die "no ruleset files in $dir"
