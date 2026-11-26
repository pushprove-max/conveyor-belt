# SPDX-License-Identifier: Apache-2.0
# The shared setup of test-changed.test.sh and test-changed-map.test.sh (each sources this file, with HERE and ROOT
# set): the scratch repository, this checkout's map (HMAP), and the functions the parts use. Each of the two files
# starts only its own parts, so a map change runs them side by side, each in its own process.
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
# The loop's test step sets CONVEYOR_TEST_FILELIST (the file of the card's changed test files) and CONVEYOR_TEST_RERUN: left set,
# every scratch run below would select the card's files as well as its own.
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN
# The checks are in parts (p_<name>) that run side by side, each in a scratch folder of its own (T, part below): each
# says ok or not ok, and the lines are numbered once every part has ended, in the order the parts started.
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; }

# A scratch repo: the real script, a map of two areas and a core, case files a and b, and a runner stub that
# records which cases it was asked for (ALL when none was named). Each part starts from its own copy of it, as
# committed ($T/r, its map also in $T/map, read as one object: test-changed.sh --map).
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/tests"
# The test lint and the browser check, which every run starts, are empty here: no part checks them, and each run of
# the real ones is time paid ~100 times a file run (test-lint.test.sh checks that a run runs the lint).
cp "$HERE/test-changed.sh" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$R/.conveyor/"; : > "$R/.conveyor/test-lint.sh"; : > "$R/.conveyor/no-browser-tests.sh"; : > "$R/.conveyor/no-records-split.sh"
cat > "$R/.conveyor/engine-areas.json" <<'EOF'
{"outside": "conveyor/README.md"}
{"area": "core", "file": "conveyor/core.sh"}
{"area": "core", "tests": "all"}
{"area": "a", "file": "conveyor/x.sh"}
{"area": "a", "test": "a.test.sh"}
{"area": "b", "file": "conveyor/y.jq"}
{"area": "b", "test": "b.test.sh"}
EOF
# A map read as one object (test-changed.sh --map), written back one fact a line.
lines() {
  jq -c '(.outside[] | {outside: .}), (.areas | to_entries[] | .key as $a | .value | (.files[] | {area: $a, file: .}),
    (.tests | if . == "all" then {area: $a, tests: "all"} else (. // [])[] | {area: $a, test: .} end), (.why // empty | {area: $a, why: .}))'
}
(cd "$R" && bash .conveyor/test-changed.sh --map) > "$T/scratch.json" || { echo "not ok - the scratch map could not be read"; exit 1; }
printf 't_aone() {\n  :\n}\nt_atwo() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
printf 't_bone() {\n  :\n}\n' > "$R/conveyor/tests/b.test.sh"
echo 'echo "${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "${0%/*}/../ran"' > "$R/conveyor/conveyor.test.sh"
echo one > "$R/conveyor/core.sh"; echo one > "$R/conveyor/x.sh"; echo one > "$R/conveyor/y.jq"; echo doc > "$R/conveyor/README.md"
# The runner stub's run of every case file is a meta-runner's (issue 584): a card mode in the pack lets it run whole
# here, so the parts below see which runs are whole.
echo '{"test": {"files": {"conveyor/conveyor.test.sh": {"cardMode": "CONVEYOR_RUNNER_STUB=1"}}}}' > "$R/.conveyor/project.json"
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# This checkout's own map, read as one object, and the number of its case files (the parts that read it: the map
# file's, and mapnames in test-changed.test.sh).
HMAP=$T/here.json; (cd "$ROOT" && bash .conveyor/test-changed.sh --map) > "$HMAP" || echo "not ok - this checkout's map could not be read"
# shellcheck disable=SC2034 # read by the files that source this one
cases=$(ls "$ROOT"/conveyor/tests/*.test.sh | wc -l)
# ran: the cases the runner stub was asked for, its runs' lines sorted and joined (each engine case file runs on its
# own, side by side, so a selection of two files is two runs, in either order).
ranlines() { LC_ALL=C sort "$1" 2>/dev/null | awk '{ gsub(/ +/, " "); sub(/ $/, ""); printf "%s%s", (NR > 1 ? " " : ""), $0 } END { print "" }'; }
ran() { rm -f "$R/ran"; (cd "$R" && bash .conveyor/test-changed.sh "$@") > "$T/out" 2>&1; echo $? > "$T/rc"; ranlines "$R/ran"; }
mran2() { ran "$@" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//'; }
sorted() { tr ' ' '\n' | grep . | sort | tr '\n' ' '; }
# part <name> [m]: p_<name> in the background, in $T/<name> with its own copy of the scratch repo (R), and with m of
# this checkout's map copy below (M); its output in $T/<name>.res, and $T/<name>.end once it ran to its end.
PARTS=()
part() {
  PARTS+=("$1")
  (B=$T; T=$T/$1; mkdir "$T" && cp -a "$B/r" "$T/r" && cp "$B/scratch.json" "$T/map" || exit 1; R=$T/r
    # shellcheck disable=SC2034 # M is read by the parts of test-changed-map.test.sh
    [ -z "${2:-}" ] || { cp -a "$B/m" "$T/m" && M=$T/m; } || exit 1
    # A name with no p_ function (a typo in the list) fails, rather than skipping its cases with no result.
    declare -F "p_$1" > /dev/null || { echo "not ok - no part p_$1"; exit 1; }
    "p_$1"; : > "$B/$1.end") > "$T/$1.res" 2>&1 &
}
# results: waits for every part, then prints each part's lines in the order the parts started, numbered.
results() {
  wait
  for p in "${PARTS[@]}"; do
    cat "$T/$p.res"
    [ -e "$T/$p.end" ] || echo "not ok - part $p did not run to its end"
  done | awk '/^(not )?ok - / { n++; sub(/ - /, " " n " - ") } { print } /^not ok / { bad = 1 } END { exit bad }'
}
