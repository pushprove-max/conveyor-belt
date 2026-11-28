#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This project's full test suite (.conveyor/test-full.sh): each test file's temp files go in a folder of its own (its
# TMPDIR), removed when the file ends, passed or failed, and when the run is stopped at its time limit while the file
# runs. Bug (#1238): test runs left 2,097 tmp.* folders in /tmp, which a later run then had no space for.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
fails=0
no() { echo "not ok - $1"; fails=1; }

# No test file of this checkout makes its temp folder at a fixed /tmp path (mktemp -d /tmp/..., -p /tmp, mkdtemp in
# '/tmp'): the suite removes only the folder it gives as TMPDIR, so such a folder was left whenever its file was
# stopped (#1238 review: dashboard-alive.test.sh, dashboard-local.test.sh). A source scan, as which files do so can only
# be read from them: a run of each here would be a run of the whole suite. A line that only names such a path in a
# command a hook test hands to a hook (run_hook, json) is no folder the test makes. One line is left out by name: the
# arm of bash-guardrails-search.refute.test.sh that makes its log folder under /tmp only when the run's TMPDIR is not
# in the scratch space its hook knows (a TMPDIR under $HOME); in a TMPDIR that is, its other arm makes it there.
fixed=$(git -C "$HERE/.." ls-files -co --exclude-standard -- '*.test.sh' '*.test.mjs' '*.test.js' '*.test.ts' '*.test.py' \
  | (cd "$HERE/.." && xargs grep -nE "mktemp[^|;)]*( |-p ?|--tmpdir=)/tmp(/|[ )\"]|$)|mkdtemp(Sync)?\\(['\"]/tmp|dir=['\"]/tmp") \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#|run_hook|json |^\.claude/hooks/__tests__/bash-guardrails-search\.refute\.test\.sh:[0-9]+:[[:space:]]*\*\) LOGS=')
[ -z "$fixed" ] || no "test files make their temp folder at a fixed /tmp path, not in TMPDIR: $fixed"

# A scratch repo with the real script and three files, run one at a time in this order: a passes, b fails and c runs
# until the run is stopped. Each notes its TMPDIR and makes a temp folder there as lib.sh does (mktemp -d); a's has a
# read-only folder in it, as an install leaves, that rm cannot empty unless it is made writable first.
R=$T/r; mkdir -p "$R/.conveyor" "$R/lib" "$R/dirs"
cp "$HERE/test-full.sh" "$HERE/test-share.sh" "$R/.conveyor/"
for f in a b c; do
  printf '%s\n' "echo \"\$TMPDIR\" > \"\$(dirname \"\$0\")/../dirs/$f\"" 'd=$(mktemp -d) && : > "$d/x" || exit 1' > "$R/lib/$f.test.sh"
done
echo 'mkdir -p "$d/ro/in" && chmod a-w "$d/ro"' >> "$R/lib/a.test.sh"
echo 'exit 1' >> "$R/lib/b.test.sh"
echo ': > "$(dirname "$0")/../ready"; sleep 60' >> "$R/lib/c.test.sh"
printf '%s\n' dirs ready > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init

# The real suite runner, on its scratch repo: the folder is made and removed around each file it runs, and on a stop.
(cd "$R" && unset CONVEYOR_TEST_SLOT CONVEYOR_CARD CONVEYOR_TEST_WHOLE CONVEYOR_TEST_LOG CONVEYOR_SUITE_MODE \
  && XDG_CONFIG_HOME=$T/config exec timeout --kill-after=30 60 bash .conveyor/test-full.sh) > "$T/out" 2>&1 &
pid=$!
# The run is stopped once c runs, by SIGALRM to its timeout, as the test step's clock stops it: only a real stopped
# run shows what its exit removes, so this polls c's mark.
i=0; while [ ! -e "$R/ready" ] && [ $i -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
[ -e "$R/ready" ] || { echo "not ok - lib/c.test.sh did not start: $(cat "$T/out")"; kill "$pid"; exit 1; }
declare -A d=(); for f in a b c; do read -r "d[$f]" < "$R/dirs/$f"; done
for f in a b; do
  case ${d[$f]} in "$R"/* | '') no "lib/$f.test.sh had no temp folder of its own: '${d[$f]}'" ;; esac
  [ ! -e "${d[$f]}" ] || no "lib/$f.test.sh's temp folder ${d[$f]} is left once the file ended: $(find "${d[$f]}" | head -5); $(cat "$T/out")"
done
[ "${d[a]}" != "${d[b]}" ] && [ "${d[b]}" != "${d[c]}" ] || no "two files had one temp folder: ${d[*]}"
[ -d "${d[c]}" ] || no "lib/c.test.sh's temp folder ${d[c]} is not there while it runs"
kill -ALRM "$pid"; wait "$pid"
[ ! -e "${d[c]}" ] || no "lib/c.test.sh's temp folder ${d[c]} is left once the run was stopped at its time limit"
grep -qxF -- '-- ok lib/a.test.sh' "$T/out" && grep -qxF -- '-- FAIL lib/b.test.sh' "$T/out" \
  || no "the files did not pass and fail as written: $(cat "$T/out")"
[ "$fails" = 0 ] && echo "ok - each file's temp folder is gone once it passed, failed or was stopped"
exit $fails
