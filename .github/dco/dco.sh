#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# dco.sh <base> <head> -- the DCO check of a pull request (.github/workflows/dco.yml; CONTRIBUTING.md, Sign-off): each
# commit in <base>..<head>, merge commits too (a merge can carry conflict fixes), carries a `Signed-off-by:` trailer
# with its author's name and email, exactly as `git commit -s` (or `git merge --signoff`) writes it.
# Run in a checkout that holds both commits.
# Exit 0 when each commit is signed off; 1 naming each commit that is not; 2 when the commits cannot be listed.
set -uo pipefail
[ $# = 2 ] || { echo "usage: dco.sh <base> <head>" >&2; exit 2; }
commits=$(git rev-list "$1..$2") || { echo "dco: cannot list the commits $1..$2" >&2; exit 2; }
bad=0
for c in $commits; do
  author=$(git log -1 --format='%an <%ae>' "$c") || exit 2
  if ! git log -1 --format='%(trailers:key=Signed-off-by,valueonly)' "$c" | grep -qxF -- "$author"; then
    echo "dco: commit $(git log -1 --format='%h "%s"' "$c") has no \"Signed-off-by: $author\""
    bad=1
  fi
done
if [ "$bad" = 1 ]; then
  echo "dco: sign each commit off as its author (git commit -s, git merge --signoff for a merge, or git rebase --signoff $1 for every commit) and push again."
  exit 1
fi
echo "dco: each commit is signed off by its author"
