#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Issue 1722. CLAUDE.test.sh checks that AGENTS.md is a link to CLAUDE.md, but it reads the Git index, so its runs keep
# no input record (test-changed.sh inputsof()), and no name rule picks it for a change to AGENTS.md. Bug it catches: a
# fix that made AGENTS.md lead to another file kept the card's old pass of CLAUDE.test.sh and never ran it again.
# This checkout's .conveyor/test-links.json links AGENTS.md to CLAUDE.test.sh; a test-changed.sh listing
# (CONVEYOR_TEST_LIST, which runs no test) of that change must name it.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
# The loop's test step sets these: left set, the listing would name the card's own files as well.
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILE CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN BASH_ENV

# A scratch repo: the real script and this checkout's real links, AGENTS.md a link to CLAUDE.md, and empty stubs of
# CLAUDE.test.sh and README.test.sh (a link to a missing file is dropped). README.test.sh, which no link names for
# AGENTS.md, shows that the listing does not name every test.
R=$T/r; mkdir -p "$R/.conveyor"
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-links.json" "$R/.conveyor/"
: > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; : > "$R/.conveyor/no-records-split.sh"
echo '{"outside": "conveyor/foreman/"}' > "$R/.conveyor/engine-areas.json"
echo c > "$R/CLAUDE.md"; echo r > "$R/README.md"; ln -s CLAUDE.md "$R/AGENTS.md"
echo ':' > "$R/CLAUDE.test.sh"; echo ':' > "$R/README.test.sh"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init || { echo "not ok - the scratch repo could not be made"; exit 1; }

# The finding's change: AGENTS.md made a link to README.md.
ln -sfn README.md "$R/AGENTS.md"
(cd "$R" && CONVEYOR_TEST_LIST=$T/list bash .conveyor/test-changed.sh) > "$T/out" 2>&1 \
  || { echo "not ok - the listing of the change to AGENTS.md failed: $(cat "$T/out")"; exit 1; }
grep -qxF CLAUDE.test.sh "$T/list" 2>/dev/null \
  || { echo "not ok - a change to where AGENTS.md leads does not select CLAUDE.test.sh: list '$(tr '\n' ' ' < "$T/list" 2>&1)'"; exit 1; }
! grep -qxF README.test.sh "$T/list" \
  || { echo "not ok - a change to AGENTS.md selects README.test.sh, which no link names: the check above proves nothing"; exit 1; }
echo "ok - a change to where AGENTS.md leads selects CLAUDE.test.sh"
