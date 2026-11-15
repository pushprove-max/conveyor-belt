#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The history rewrite, for the step that makes a repository public: takes a private name out of every commit.
# Usage: history-rewrite.sh <source repository> <new folder> <text>[=<replacement>] [<text>[=<replacement>]...]
# Makes a fresh mirror clone of the source (every branch and tag) in the new folder, then with git filter-repo
# replaces each text, wherever it stands as a whole word in any case (as history-scan.sh finds a term), with its
# replacement (default example-project) in every file of every commit and in every commit message. Authors, dates
# and the rest of each message are kept. The source is only read; the clone's remote is removed, so the result is never
# pushed by this script or by a stray `git push` in it.
# Prints the old-to-new commit-id map, one "<old> <new>" line per commit. Exit 0 when done, 2 on a usage or git error.
set -uo pipefail
usage() { echo "usage: history-rewrite.sh <source repository> <new folder> <text>[=<replacement>]..." >&2; exit 2; }
die() { echo "history-rewrite: $*" >&2; exit 2; }
[ $# -ge 3 ] || usage
src=$1 out=$2; shift 2
command -v git-filter-repo >/dev/null || die "git filter-repo is not installed"
[ ! -e "$out" ] || die "$out already exists: name a new folder"

W=$(mktemp -d) || exit 2; trap 'rm -rf "$W"' EXIT
# filter-repo's expressions file: one "regex:<expression>==><replacement>" line per text, the expression Python's,
# grep -w's word edges kept by lookarounds so the characters round the text are not replaced with it.
for a; do
  t=${a%%=*}; r=example-project; [ "$t" = "$a" ] || r=${a#*=}
  [ -n "$t" ] || die "an empty text in \"$a\""
  case $t$r in *$'\n'* | *'==>'*) die "a text or replacement holds a line break or ==>: \"$a\"" ;; esac
  rx=$(printf '%s' "$t" | sed 's/[][\.*^$+?(){}|/]/\\&/g')
  printf 'regex:(?i)(?<![0-9A-Za-z_])%s(?![0-9A-Za-z_])==>%s\n' "$rx" "$r"
done > "$W/replace"

git clone --quiet --mirror --no-local -- "$src" "$out" 2>"$W/err" || die "the mirror clone of $src failed: $(head -c 300 "$W/err")"
# (Its note that the mirror's branches were kept is not shown: they are the result.)
git -C "$out" remote remove origin 2>"$W/err" || die "the clone's remote could not be removed: $(head -c 300 "$W/err")"
# --force: the clone is fresh but local, which filter-repo's own freshness test does not accept.
git -C "$out" filter-repo --force --quiet --replace-text "$W/replace" --replace-message "$W/replace" >"$W/err" 2>&1 \
  || die "git filter-repo failed: $(head -c 300 "$W/err")"
map=$out/filter-repo/commit-map
[ -r "$map" ] || die "git filter-repo wrote no commit map"
tail -n +2 "$map"
