#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the kept Tests page parts of the snapshot (snapkeys(), snappart(), lib/snapshot.sh): a build whose
# inputs did not change takes the kept tests and testMap parts, and a change to an input they read computes them again.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A line of the records: <card> <issue> <step> <result> <minute of 2026-11-17T10> [extra json]. Every case file is
# sourced into one shell (conveyor.test.sh), so the helpers carry the file's name.
snapparts_line() {
  jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --arg r "$4" --arg t "2026-11-17T10:$5:00Z" --argjson x "${6:-{\}}" \
    '{card: $c, issue: $i, step: $s, time: $t, tokens: {claude: 1, codex: 0}, result: $r, sha: "", reason: "", repo: "r"} * $x'
}
# A snapshot built (--fresh: one build of its own), kept in <name>.json of the case's folder.
snapparts_build() { loop snapshot --fresh > "$T/$CASE/$1.json" || fail "the snapshot $1 exited non-zero: $(cat "$T/$CASE/$1.json")"; }
# The fixture of every case: main with its stub test file a.test.sh (setup), a card picked, and a first build A,
# which computes each part and keeps it.
snapparts_setup() {
  export TZ=UTC CONVEYOR_NOW=1794918000
  setup '[]'; mkdir -p "$ST"
  snapparts_line c1 1 picked ok 00 '{"title": "one"}' > "$ST/cards.jsonl"
  snapparts_build A
  [ -s "$ST/snapparts/tests" ] && [ -s "$ST/snapparts/testmap" ] && [ -s "$ST/snapparts/owners" ] \
    || fail "the first build kept no part: $(ls "$ST/snapparts" 2>&1)"
}
# The inode of the kept part <name>: a part computed again is kept by a rename, as a new file.
snapparts_ino() { ls -i "$ST/snapparts/$1" | awk '{print $1}'; }
# The test file <file>'s row of the tests part of the build <name>, as compact JSON; empty when it has none.
snapparts_row() { jq -c --arg f "$2" '.tests.files[] | select(.file == $f)' "$T/$CASE/$1.json"; }

# Bug: each build computed the tests part, the test owners and the test map again, 7 to 16 s, though nothing they read
# had changed. A build with every input as it was takes the kept parts (the kept files are not written again) and
# gives the same tests and testMap parts as the full build A.
t_snappartssame() {
  local i t o
  snapparts_setup
  i=$(snapparts_ino tests) t=$(snapparts_ino testmap) o=$(snapparts_ino owners)
  snapparts_build B
  [ "$(snapparts_ino tests)" = "$i" ] && [ "$(snapparts_ino testmap)" = "$t" ] && [ "$(snapparts_ino owners)" = "$o" ] \
    || fail "a build with no input changed computed the Tests parts again: tests $i to $(snapparts_ino tests), testmap $t to $(snapparts_ino testmap), owners $o to $(snapparts_ino owners)"
  [ "$(jq -cS '{tests, testMap}' "$T/$CASE/B.json")" = "$(jq -cS '{tests, testMap}' "$T/$CASE/A.json")" ] \
    || fail "the kept parts differ from the full build's: $(diff <(jq -S '{tests, testMap}' "$T/$CASE/A.json") <(jq -S '{tests, testMap}' "$T/$CASE/B.json"))"
  jq -e '.tests.files | any(.file == "a.test.sh")' "$T/$CASE/B.json" > /dev/null || fail "the kept tests part does not list a.test.sh: $(jq -c .tests "$T/$CASE/B.json")"
}
# Bug: a part kept past a new commit of main hides the test files it added. Main's HEAD is in the key: a committed
# test file b.test.sh is listed at the next build.
t_snappartscommit() {
  snapparts_setup
  echo 't_two() { :; }' > "$R/b.test.sh" && git -C "$R" add b.test.sh && git -C "$R" commit -qm 'b test' || fail "b.test.sh could not be committed"
  snapparts_build B
  [ -n "$(snapparts_row B b.test.sh)" ] || fail "a new commit did not compute the tests part again: no b.test.sh in $(jq -c '[.tests.files[].file]' "$T/$CASE/B.json")"
}
# Bug: a part kept past a new test line hides the run. The card records are in the key: a.test.sh's run is listed.
t_snappartsrecord() {
  snapparts_setup
  [ "$(snapparts_row A a.test.sh | jq '.runsOnRecord')" = 0 ] || fail "a.test.sh has a run before its test line: $(snapparts_row A a.test.sh)"
  snapparts_line c1 1 test pass 01 '{"times": {"a.test.sh": 1.5}}' >> "$ST/cards.jsonl"
  snapparts_build B
  [ "$(snapparts_row B a.test.sh | jq '.runsOnRecord')" = 1 ] || fail "a new test line did not compute the tests part again: $(snapparts_row B a.test.sh)"
}
# Bug: a part keyed on the whole card records and control record was computed again whenever a card began (its start
# line) or a control setting changed, though the part reads neither. Those keep it; the control record's testsFrom,
# which the part reads, computes it again.
t_snappartsunread() {
  local i
  snapparts_setup
  i=$(snapparts_ino tests)
  # A whole start record (check.jq refuses one with no of, and the build sets a refused line aside before its key).
  snapparts_line c1 1 start ok 02 '{"of": "build"}' >> "$ST/cards.jsonl"
  [ -z "$(jq -Rrn -f "$SRC/jq/check.jq" < "$ST/cards.jsonl")" ] || fail "the start line is refused by the records' check: $(jq -Rrn -f "$SRC/jq/check.jq" < "$ST/cards.jsonl")"
  jq '.cap = 5' "$SRC/lib/control-defaults.json" > "$ST/control.json" || fail "the control record could not be written"
  snapparts_build B
  [ "$(snapparts_ino tests)" = "$i" ] || fail "a start line and a control change the part does not read computed the tests part again"
  loop test-settings history-start 2026-11-10T00:00:00Z > /dev/null || fail "the test history's start could not be set"
  snapparts_build C
  [ "$(jq -r '.tests.settings.historyStart' "$T/$CASE/C.json")" = 2026-11-10T00:00:00Z ] \
    || fail "a new test history start did not compute the tests part again: $(jq -c .tests.settings "$T/$CASE/C.json")"
}
# Bug: a part kept past a new flaky entry hides it. The flaky record is in the key: a.test.sh counts the entry.
t_snappartsflaky() {
  snapparts_setup
  jq -n '{entries: [{case: "a.test.sh: one", source: "c9", time: "2026-11-16T00:00:00Z", card: "c9", issue: 9}]}' > "$ST/flaky.json"
  snapparts_build B
  [ "$(snapparts_row B a.test.sh | jq '.flaky')" = 1 ] || fail "a new flaky entry did not compute the tests part again: $(snapparts_row B a.test.sh)"
}
# Bug: a part kept past a change to the pack shows the old settings. The pack is in the key: test.slowIssues set to
# true shows at the next build.
t_snappartspack() {
  snapparts_setup
  [ "$(jq '.tests.settings.slowIssues' "$T/$CASE/A.json")" = false ] || fail "slowIssues is on before the pack sets it: $(jq -c .tests.settings "$T/$CASE/A.json")"
  tune '.test.slowIssues = true'
  snapparts_build B
  [ "$(jq '.tests.settings.slowIssues' "$T/$CASE/B.json")" = true ] || fail "a pack change did not compute the tests part again: $(jq -c .tests.settings "$T/$CASE/B.json")"
}
# Bug: a part keyed on the whole pack, and on main's diff with a tracked pack in it, was computed again at any pack
# edit, though the parts read only its test and tests keys. With the pack committed in main, an edit of tunables.poll
# (not committed: main's diff shows it) keeps all three parts.
t_snappartspackother() {
  local i t o
  snapparts_setup
  git -C "$R" add -f .conveyor/project.json && git -C "$R" commit -qm pack || fail "the pack could not be committed"
  snapparts_build B
  i=$(snapparts_ino tests) t=$(snapparts_ino testmap) o=$(snapparts_ino owners)
  tune '.tunables.poll = 3'
  [ -n "$(git -C "$R" diff HEAD -- .conveyor/project.json)" ] || fail "the pack edit is not in main's diff"
  snapparts_build C
  [ "$(snapparts_ino tests)" = "$i" ] && [ "$(snapparts_ino testmap)" = "$t" ] && [ "$(snapparts_ino owners)" = "$o" ] \
    || fail "an edit of tunables.poll, which no part reads, computed the Tests parts again: tests $i to $(snapparts_ino tests), testmap $t to $(snapparts_ino testmap), owners $o to $(snapparts_ino owners)"
}
# Bug: a part kept past a staged deletion of a test file keeps its row: main's diff from HEAD is the same before and
# after `git add`, but the tracked files (testtracked(): git ls-files) drop it. The list of tracked files is in the key.
t_snappartsstaged() {
  snapparts_setup
  rm -f -- "$R/a.test.sh"
  snapparts_build B
  [ -n "$(snapparts_row B a.test.sh)" ] || fail "a.test.sh, deleted but still tracked, has no row: $(jq -c '[.tests.files[].file]' "$T/$CASE/B.json")"
  git -C "$R" add -u -- a.test.sh || fail "the deletion of a.test.sh could not be staged"
  snapparts_build C
  [ -z "$(snapparts_row C a.test.sh)" ] || fail "a staged deletion of a.test.sh did not compute the tests part again: $(snapparts_row C a.test.sh)"
}
# Bug: a testMap part kept past a made map says there is none. The made map is in its key.
t_snappartsmap() {
  snapparts_setup
  [ "$(jq -r '.testMap.state' "$T/$CASE/A.json")" = none ] || fail "a map before one was made: $(jq -c .testMap "$T/$CASE/A.json")"
  jq -n --arg c "$(git -C "$R" rev-parse HEAD)" '{commit: $c, command: "x", language: "node", made: "2026-11-17T09:00:00Z", seconds: 3,
    tests: ["a.test.sh"], sources: {"a.txt": ["a.test.sh"]}, notMapped: []}' > "$R/.conveyor/test-map.json"
  snapparts_build B
  [ "$(jq -r '.testMap.state, .testMap.made' "$T/$CASE/B.json" | paste -sd ' ')" = 'made 2026-11-17T09:00:00Z' ] \
    || fail "a made map did not compute the testMap part again: $(jq -c .testMap "$T/$CASE/B.json")"
}
# Bug: a testMap part kept past an edit of the project's own map (test.map names it; untracked, so main's diff does not
# show it) keeps the old counts. That file is in the key.
t_snappartsownmap() {
  snapparts_setup
  echo '{"a.txt": ["a.test.sh"], "b.txt": ["b.test.sh"]}' > "$R/mymap.json" && tune '.test.map = "mymap.json"' || fail "the map could not be set"
  snapparts_build B
  [ "$(jq -c '.testMap | [.state, .sources, .tests]' "$T/$CASE/B.json")" = '["made",2,2]' ] || fail "the project's map is not read: $(jq -c .testMap "$T/$CASE/B.json")"
  echo '{"a.txt": ["a.test.sh"]}' > "$R/mymap.json"
  snapparts_build C
  [ "$(jq -c '.testMap | [.state, .sources, .tests]' "$T/$CASE/C.json")" = '["made",1,1]' ] \
    || fail "an edit of the project's map did not compute the testMap part again: $(jq -c .testMap "$T/$CASE/C.json")"
}
# Bug: a testMap part kept past a coverage tool installed with no file the key names (a SimpleCov gem with no Gemfile)
# keeps saying it is not installed. The tool's check is in the key: a Ruby main (.rspec) whose ruby finds SimpleCov
# once the gem marker is there.
t_snappartstool() {
  local b=$T/$CASE/rb
  snapparts_setup
  mkdir -p "$b" && printf '#!/usr/bin/env bash\n[ -e %q ]\n' "$T/$CASE/gem" > "$b/ruby" && chmod +x "$b/ruby" && : > "$R/.rspec" || fail "the Ruby fixture"
  PATH=$b:$PATH snapparts_build B
  [ "$(jq -r '.testMap.toolWhy' "$T/$CASE/B.json")" = 'SimpleCov is not installed' ] || fail "SimpleCov is found before it is there: $(jq -c .testMap "$T/$CASE/B.json")"
  : > "$T/$CASE/gem"
  PATH=$b:$PATH snapparts_build C
  [ "$(jq -r '.testMap.tool' "$T/$CASE/C.json")" = SimpleCov ] || fail "SimpleCov installed did not compute the testMap part again: $(jq -c .testMap "$T/$CASE/C.json")"
}
# Bug: a testMap part kept while a run that makes the map ran says it still runs after its process ended: that end
# writes no file. While the run's progress names a pid, the part is not kept, and the next build says the run stopped.
t_snappartsmappid() {
  local p
  snapparts_setup
  sleep 60 & p=$! # sleep: a live process for the run's pid, killed below; nothing waits on it
  jq -n --argjson p "$p" '{pid: $p, started: 1794917000, done: 1, of: 3}' > "$R/.conveyor/test-map.run.json"
  snapparts_build B
  [ "$(jq -r '.testMap.state' "$T/$CASE/B.json")" = running ] || { kill "$p"; fail "a running map build is not shown running: $(jq -c .testMap "$T/$CASE/B.json")"; }
  kill "$p"; wait "$p" 2> /dev/null
  snapparts_build C
  [ "$(jq -r '.testMap.state' "$T/$CASE/C.json")" = failed ] || fail "a map build whose process ended is still shown as before: $(jq -c .testMap "$T/$CASE/C.json")"
}
# Bug: a key read after the part read its inputs keeps the part under a key newer than what it read, so a flaky entry
# written while the part is computed is never shown. What must stay true: the kept part's key is read before the part
# reads the flaky record; the other writer is flaky() (lib/flaky.sh, what `conveyor.sh flaky` and a card's test step
# call). The build runs as the snapshot command runs it, its libraries sourced, with testspart() wrapped so that the
# real writer adds an entry just after the part read the record and before snappart() keeps it: the weak point. A
# function wrap, not a program on PATH: on macOS p_path() puts Homebrew's tools ahead of any the case puts there.
t_snappartsrace() {
  snapparts_setup
  # No input changed since A, so B would take A's kept part and never read: a kept file that is not there is a miss.
  rm -f -- "$ST/snapparts/tests"
  # shellcheck source=/dev/null # the snapshot's libraries, by the list snapshot.sh names (SNAPLIBS)
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^SNAPLIBS=' "$SRC/commands/snapshot.sh")" \
      && for l in $SNAPLIBS; do . "$HERE/lib/$l.sh" || exit 9; done && names || exit 9
    eval "snapparts_read () $(declare -f testspart | tail -n +2)" || exit 9
    testspart() { snapparts_read "$@"; local r=$?; flaky c9 '[{"case": "a.test.sh: one", "card": "c9", "issue": 9}]' nofile > /dev/null || exit 8; : > "$T/$CASE/wrote"; return "$r"; }
    GITHUB=$ST/snapgh snapshot > "$T/$CASE/B.json" ) || fail "the build with the wrapped part failed (rc $?): $(head -c 300 "$T/$CASE/B.json")"
  [ -e "$T/$CASE/wrote" ] || fail "the build did not compute the tests part, so no entry was written during it"
  [ "$(snapparts_row B a.test.sh | jq '.flaky')" = 0 ] || fail "the build read the entry written after its read: $(snapparts_row B a.test.sh)"
  snapparts_build C
  [ "$(snapparts_row C a.test.sh | jq '.flaky')" = 1 ] || fail "the entry written during a build is not shown at the next: $(snapparts_row C a.test.sh)"
}
