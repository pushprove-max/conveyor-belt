#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Issue 1640. The Foreman's start text is made by conveyor/lib/standing.sh (the standing-yes text), conveyor/foreman/foreman.sh
# and conveyor/foreman/procedures.md, and the Foreman tests that read it (foreman-size, foreman-standing, foreman-launcher,
# foreman.test.sh) are under conveyor/foreman/, which the engine area map keeps outside. Bug it catches: a card that
# grew the standing text ran none of them, landed, and main went red on foreman-size.test.sh later. This checkout's
# .conveyor/test-links.json links each of the three files to those tests; a test-changed.sh listing
# (CONVEYOR_TEST_LIST, which runs no test) of a change to each one must name them. It links foreman/lib.sh to
# conveyor/tests/askfiling.test.sh too (the filing ask's cases, below).
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
# The loop's test step sets these: left set, the listing would name the card's own files as well.
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN BASH_ENV
fails=0
no() { echo "not ok - $1"; fails=1; }

# A scratch repo: the real script and this checkout's real links, the three start-text files as they are, an area map
# that holds standing.sh as the real one does, and empty stubs of the Foreman test files (a link to a missing file is
# dropped). waiter.test.sh, linked to none of the three, shows that the listing does not name every Foreman test.
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests" "$R/conveyor/lib" "$R/conveyor/foreman"
cp "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-links.json" "$R/.conveyor/"
: > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; : > "$R/.conveyor/no-records-split.sh"
printf '%s\n' '{"outside": "conveyor/foreman/"}' '{"outside": "conveyor/commands/foreman.sh"}' '{"area": "cmd-auto", "file": "conveyor/lib/standing.sh"}' \
  '{"area": "cmd-auto", "test": "standing.test.sh"}' > "$R/.conveyor/engine-areas.json"
cp "$ROOT/conveyor/lib/standing.sh" "$R/conveyor/lib/"
cp "$ROOT/conveyor/foreman/foreman.sh" "$ROOT/conveyor/foreman/procedures.md" "$ROOT/conveyor/foreman/lib.sh" "$R/conveyor/foreman/"
mkdir -p "$R/conveyor/commands" && cp "$ROOT/conveyor/commands/foreman.sh" "$R/conveyor/commands/"
printf 't_one() {\n  :\n}\n' > "$R/conveyor/tests/standing.test.sh"
printf 't_cardaskslow() {\n  :\n}\n' > "$R/conveyor/tests/askfiling.test.sh"
# The test files the links give foreman/lib.sh (more than a card's cap), each there: the cap check below reads them all.
mapfile -t LIBLINKED < <(jq -r '.["conveyor/foreman/lib.sh"][]' "$HERE/test-links.json")
for t in "${LIBLINKED[@]}"; do [ -f "$R/$t" ] || { mkdir -p "$R/${t%/*}" && echo ':' > "$R/$t"; }; done
FOREMAN=(conveyor/foreman/foreman-launcher.test.sh conveyor/foreman/foreman-size.test.sh conveyor/foreman/foreman-standing.test.sh
  conveyor/foreman/foreman.test.sh)
# The Foreman session cases, split in two files (foreman-session and foreman-claims): a change that runs one runs both.
SESSION=(conveyor/foreman/foreman-session.test.sh conveyor/foreman/foreman-claims.test.sh)
for t in "${FOREMAN[@]}" "${SESSION[@]}" conveyor/foreman/waiter.test.sh; do echo ':' > "$R/$t"; done
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init

# listed <file> <sed script>: the listing of the change the sed script makes to <file>; the change is undone after.
listed() {
  rm -f "$T/list"
  sed "$2" "$R/$1" > "$T/e" && cat "$T/e" > "$R/$1"
  git -C "$R" diff --quiet -- "$1" && { no "$1: the sed script '$2' changed nothing"; return; }
  (cd "$R" && CONVEYOR_TEST_LIST=$T/list bash .conveyor/test-changed.sh) > "$T/out" 2>&1 || no "$1: the listing failed: $(cat "$T/out")"
  git -C "$R" checkout -q -- .
}
# names <file>: each Foreman test is in the list made for a change to <file>, and waiter.test.sh is not.
names() {
  local t
  for t in "${FOREMAN[@]}"; do grep -qxF "$t" "$T/list" 2>/dev/null || no "a change to $1 does not select $t: list '$(tr '\n' ' ' < "$T/list" 2>&1)'"; done
  ! grep -qxF conveyor/foreman/waiter.test.sh "$T/list" || no "a change to $1 selects waiter.test.sh, which no link names: the check above proves nothing"
}
# sessions <file>: both Foreman session test files are in the list made for a change to <file>.
sessions() {
  local t
  for t in "${SESSION[@]}"; do grep -qxF "$t" "$T/list" 2>/dev/null || no "a change to $1 does not select $t: list '$(tr '\n' ' ' < "$T/list" 2>&1)'"; done
}

# The issue's case: a change to the standing-yes text alone (the text-only rule picks only tests that hold the text).
listed conveyor/lib/standing.sh 's/When unsure, ask\./When unsure, ask the owner./'; names conveyor/lib/standing.sh
listed conveyor/foreman/foreman.sh '$a\
: two'; names conveyor/foreman/foreman.sh; sessions conveyor/foreman/foreman.sh
# Bug: the claims cases left foreman-session.test.sh for foreman-claims.test.sh, and a change to the engine's foreman
# command ran only the old file (its tests are listed by hand in test-changed.sh TESTS_OF).
listed conveyor/commands/foreman.sh '$a\
: two'; sessions conveyor/commands/foreman.sh
listed conveyor/foreman/procedures.md '$a\
One more line.'; names conveyor/foreman/procedures.md
# Bug: askfiling() (foreman/lib.sh, outside the map) is tested only by conveyor/tests/askfiling.test.sh, whose area,
# testaction, holds none of the Foreman's files: a change to the filing ask alone ran none of its cases. It was linked
# then, but sorted last of the files linked to lib.sh, and the card's cap of them kept the first by name. The engine's
# own cap (lib/testlist.sh selfirst(), which asks this script, then lib/testrun.sh testcap(), as listcmd() calls them),
# with no failure on record, must keep it.
sed '/^askfiling() {/,/^}/s/^\( *\)return 0$/\1return 1/' "$R/conveyor/foreman/lib.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/foreman/lib.sh"
if git -C "$R" diff --quiet -- conveyor/foreman/lib.sh; then no "the sed script changed no 'return 0' line of askfiling()"
else
  # The cap's libraries alone, CARDLINKED as lib/prompts.sh sets it, and the pack's test settings as packget gives them.
  kept=$(cd "$R" && set +u && eval "$(grep '^CARDLINKED=' "$ROOT/conveyor/lib/prompts.sh")" && . "$ROOT/conveyor/lib/testfiles.sh" \
    && . "$ROOT/conveyor/lib/testlist.sh" && . "$ROOT/conveyor/lib/testrun.sh" && [ -n "$CARDLINKED" ] || exit 1
    packget() { case $1 in test.changed) printf -v "$2" %s .conveyor/test-changed.sh ;; test.command) printf -v "$2" %s 'bash .conveyor/test-changed.sh' ;; *) return 1 ;; esac; }
    testowners() { defs='{}' refs='{}'; : "$defs$refs"; } # testcap() reads defs and refs: no case names on record; olds() { :; }; recs() { :; }
    fs=("${LIBLINKED[@]}"); selfirst "$R" "$CARDLINKED"; CAPMAX=$CARDLINKED CAPFIRST=$SELN testcap "${fs[@]}"
    echo "$CARDLINKED of ${#LIBLINKED[@]}:"; printf '%s\n' "${CAPFILES[@]}") 2>&1
  [ "${#LIBLINKED[@]}" -gt "$(sed -n 's/^\([0-9]*\) of .*/\1/p' <<<"$kept")" ] \
    || no "the links give foreman/lib.sh no more files than a card's cap keeps, so the check below proves nothing: $kept"
  grep -qxF conveyor/tests/askfiling.test.sh <<<"$kept" \
    || no "a change to askfiling()'s 'return 0' in conveyor/foreman/lib.sh: the card's cap of its linked files left out conveyor/tests/askfiling.test.sh: kept $(tr '\n' ' ' <<<"$kept")"
fi
git -C "$R" checkout -q -- .

[ "$fails" = 0 ] && echo "ok - a change to each Foreman start-text file selects the Foreman size and text tests, and one to foreman/lib.sh the filing ask's cases"
exit "$fails"
