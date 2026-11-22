# SPDX-License-Identifier: Apache-2.0
# The test map (docs/configuration.md, The test map): which test files cover which source files, so a card's run is
# given the tests that cover what its change touches (testsel(), lib/testrun.sh). Setup makes it (setup()), with the
# project's own coverage tool; a whole run on main refreshes it from its own coverage when it is due (mapcovon(),
# maprefresh()); a card's run maps the test files it adds (mapnew()).
# The made map is the file test-map.json in the pack folder (mappath()): {commit (the commit it was made on), command
# (the pack's test.command then), language, made (when), seconds (how long the run took), tests (the test files
# mapped), sources: {<source file>: [<test file>, ...]}, notMapped: [{file, why}] (the test files its run could not
# map: each failed under it, or runs only under another runner, mapcollect(); none are used to pick a card's tests)}.
# The pack's test.map: unset, the made map; "off", no map (a card's tests are found by name); else a path from the
# repository root of a map the project keeps itself, read in the card's worktree and never made or refreshed here
# (mapread()).
mappath() { echo "${PACK%/*}/test-map.json"; }
# The run that makes the map, while it runs (setup's, mapbuild(); a refresh, mapcovon() to maprefresh()), says how far
# it is in test-map.run.json beside the map (mapprogpath()): {pid, started, done, of}: the engine process it runs in,
# when it started (seconds since 1970), and how many of its test files have run, of how many. A run that makes the map
# removes the file; one that fails leaves {failed: <why>} (mapend()). /units reads it (mapstate()). A card's run of the
# test files it adds (mapnew()) writes none: MAPRUN, set by the caller, turns it on in mapcollect().
mapprogpath() { echo "${PACK%/*}/test-map.run.json"; }
# The file written, whole, from jq's output with <jq arguments>; with none (or jq failing), left as it was. The file
# beside it is named by the writing process (the count of a refresh writes it too, mapcovon()).
mapput() { # <jq arguments>...
  local f t; f=$(mapprogpath); t=$f.$BASHPID
  jq -c "$@" > "$t" 2>/dev/null && mv -f "$t" "$f" || { rm -f "$t"; return 1; }
}
# A run's progress that cannot be written never fails the run. Its pid is the engine process's ($$), or MAPPID: a
# build by hand runs in a subshell of a process that has ended by then (maprunbuild()).
mapstart() { mapput -n --argjson p "${MAPPID:-$$}" --argjson of "$1" '{pid: $p, started: (now | floor), done: 0, of: $of}' || :; } # <of>
mapstep() { mapput -e --argjson d "$1" 'select(.pid) | .done = $d' "$(mapprogpath)" || :; } # <done>: only while the file is a run's
# Why a run failed, in one line: the first of its <stderr file> (mapfail()'s, without the output it introduces); exit 1
# with none.
mapwhy() { head -n 1 "$1" 2>/dev/null | sed 's/; the end of its output:$//' | grep .; }
mapend() { if [ $# = 0 ]; then rm -f "$(mapprogpath)"; else mapput -n --arg w "$1" '{failed: $w}'; fi; } # [<why it failed>]
# The test map's state, as /units shows it (`conveyor.sh testmap`, hooks/units-fetch.sh), one JSON object:
# {state: "running", done, of, started} while a run makes it (test-map.run.json, its process alive); {state: "failed",
# why} after a run that failed, or whose process ended before it said how (killed), or for a map mapread() cannot
# read; {state: "off"} with test.map off (a failed run before it is no matter); {state: "none"} with no made map; else {state: "made", sources, tests, age}:
# how many source and test files it maps, and how many commits it is behind <dir>'s HEAD (mapread(); null for a map of
# the project's own). A pack that cannot be read gives none (exit 1).
mapstate() { # <dir>
  local p pid m out
  p=$(jq -ce 'objects' "$(mapprogpath)" 2>/dev/null) && pid=$(jq -r '.pid | numbers' <<<"$p")
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then jq -c '{state: "running", done, of, started}' <<<"$p"; return 0; fi
  packget test.map m 2>/dev/null || return 1
  [ "$m" != off ] || { echo '{"state":"off"}'; return 0; }
  if [ -n "$p" ]; then
    if [ -n "${pid:-}" ]; then echo '{"state":"failed","why":"its run stopped before it ended"}'
    else jq -c '{state: "failed", why: (.failed | strings // "")}' <<<"$p"; fi
    return 0
  fi
  out=$(mapread "$1") || { jq -nc --arg w "$out" '{state: "failed", why: $w}'; return 0; }
  [ -n "$out" ] || { echo '{"state":"none"}'; return 0; }
  jq -c '{state: "made", sources: (.sources | length), tests: ([.sources[][]] | unique | length), age}' <<<"$out"
}
# The language whose coverage tool makes the map, from the files at the root of <dir>: go, rust, ruby, node or python;
# nothing for another.
maplang() { # <dir>
  if [ -e "$1/go.mod" ]; then echo go
  elif [ -e "$1/Cargo.toml" ]; then echo rust
  elif [ -e "$1/Gemfile" ] || [ -e "$1/.rspec" ]; then echo ruby
  elif [ -e "$1/package.json" ]; then echo node
  elif [ -e "$1/pyproject.toml" ] || [ -e "$1/setup.py" ] || [ -e "$1/setup.cfg" ] || [ -e "$1/pytest.ini" ] || [ -e "$1/tox.ini" ]; then echo python
  fi
}
# The coverage tool of <language>, and whether it is there: prints its name, or why there is none (exit 1). Node: V8's
# own coverage (NODE_V8_COVERAGE), a test file at a time; Python: coverage.py, with dynamic contexts (a test function
# each); Go: a coverage profile of each package's tests; Rust: cargo llvm-cov, a test binary at a time; Ruby: SimpleCov,
# a spec file at a time.
maptool() { # <language> <dir>
  case $1 in
    node) command -v node >/dev/null && echo 'V8 coverage' || { echo 'node is not installed'; return 1; } ;;
    python) command -v coverage >/dev/null && echo 'coverage.py' || { echo 'coverage.py (the coverage command) is not installed'; return 1; } ;;
    go) command -v go >/dev/null && echo 'go test -coverprofile' || { echo 'go is not installed'; return 1; } ;;
    rust) cargo llvm-cov --version >/dev/null 2>&1 && echo 'cargo llvm-cov' || { echo 'cargo-llvm-cov is not installed'; return 1; } ;;
    ruby) (cd "$2" && if [ -e Gemfile ]; then bundle exec ruby -e 'require "simplecov"'; else ruby -e 'require "simplecov"'; fi) >/dev/null 2>&1 \
      && echo SimpleCov || { echo 'SimpleCov is not installed'; return 1; } ;;
    *) echo 'its language has no coverage tool the test map knows (Node, Python, Go, Rust or Ruby)'; return 1 ;;
  esac
}
# The tracked test files (testpaths(), the pack's tests.patterns) of <language> in <dir>, one a line: Node's are all of
# those that are .js, .mjs, .cjs, .ts and the like (src/test-a.mjs, checks/one.js), as node --test runs any file it is
# given; Python's test_*.py and *_test.py; Go's *_test.go; Rust's test binaries, tests/*.rs; Ruby's *_spec.rb. Of the
# others, a file a test reads (a helper under test/) is no test of its own.
maptests() { # <dir> <language>
  local rx
  case $2 in
    node) rx='\.[cm]?[jt]sx?$' ;; python) rx='(^|/)(test_[^/]*|[^/]*_test)\.py$' ;;
    go) rx='_test\.go$' ;; rust) rx='^tests/[^/]+\.rs$' ;; ruby) rx='_spec\.rb$' ;; *) return 0 ;;
  esac
  git -C "$1" -c core.quotePath=false ls-files 2>/dev/null | testpaths | grep -E "$rx" || :
}
# The command that runs one test file (Node, Ruby), from the pack: test.fileCommand, the path added at its end and in
# CONVEYOR_TEST_FILE; else test.command with the path given as test.list says (listcmd(), lib/testrun.sh); else the
# language's own runner: node --test, or rspec (through bundle exec with a Gemfile).
mapone() { # <dir> <test file> <language>
  local fc cmd lm q
  q=$(printf %q "$2"); packget test.fileCommand fc test.command cmd test.list lm || return 1
  if [ -n "$fc" ]; then echo "export CONVEYOR_TEST_FILE=$q; $fc $q"
  elif [ "$lm" = args ] && [[ $(testrunner "$cmd" "$1") != named* ]]; then echo "$cmd $q"
  elif [ "$lm" = placeholder ] && [[ $cmd == *'{files}'* ]]; then echo "${cmd//\{files\}/"$q"}"
  elif [ "$lm" = env ]; then echo "export CONVEYOR_TEST_FILES=$q; $cmd"
  elif [ "$3" = ruby ]; then if [ -e "$1/Gemfile" ]; then echo "bundle exec rspec $q"; else echo "rspec $q"; fi
  else echo "node --test $q"; fi
}
# Runs <tests> (default: every test file of the language, maptests()) in <dir> under the language's coverage tool and
# prints what each touched, one `<test file><TAB><file>` a line (a path from the root of <dir>, any file: mapwrite()
# keeps the tracked source files). A test file (Go: a package's) whose run fails is not mapped, and the others go on:
# it is written to <tmp>/skipped, a line {file, why} each (why: the end of its output, mapskip()). So is a Node test
# file whose imports show it runs only under another runner (mapother()), before it runs. It fails (its output's last
# lines to stderr) when the tool fails, a Python suite fails, or no test file ran. The run's output is in <tmp>/log.
# With MAPRUN set, it says how far it is (mapstart(), mapstep()): a file at a time for Node, Ruby and Rust, a package's
# files at a time for Go; for Python, as the run's output names its test files (mappyran()), looked at every 2 seconds
# while the suite runs.
mapfail() { echo "$1 failed under coverage; the end of its output:" >&2; tail -n 20 "$2/log" >&2; return 1; } # <what> <tmp folder>
# <test files> not mapped, with <why> (or, with none, the end of <tmp>/out: the output of the run that failed), each a
# line of <tmp>/skipped.
mapskip() { # <tmp folder> <why or ""> <test file>...
  local tmp=$1 w=$2; shift 2
  [ -n "$w" ] || w="failed under coverage; the end of its output:"$'\n'"$(tail -n 10 "$tmp/out" 2>/dev/null | cut -c 1-300)"
  [ $# = 0 ] || printf '%s\n' "$@" | jq -Rc --arg w "$w" 'select(. != "") | {file: ., why: $w}' >> "$tmp/skipped"
}
# Why a Node <test file> in <dir> runs only under another runner, from its imports (exit 1 when it does not):
# claude-code/testing, the test API of Claude Code's mod test runner, which node --test does not have.
mapother() { # <dir> <test file>
  grep -qE "(from|import|require\\()[[:space:]]*['\"]claude-code/testing['\"]" "$1/$2" 2>/dev/null || return 1
  echo "it imports claude-code/testing, so it runs only under Claude Code's mod test runner"
}
mapcollect() { # <dir> <language> <tmp folder> [<test file>...]
  local d=$1 lang=$2 tmp=$3 abs t n=0 k=0 ok=0 rc cmd m ts mod rx w; shift 3
  ts=("$@"); [ $# -gt 0 ] || mapfile -t ts < <(maptests "$d" "$lang")
  [ ${#ts[@]} -gt 0 ] || { echo "no $lang test files are tracked" >&2; return 1; }
  : > "$tmp/skipped" || return 1
  [ -z "${MAPRUN:-}" ] || mapstart ${#ts[@]}
  abs=$(cd "$d" && pwd -P) || return 1
  local -a run=(timeout --kill-after=30 "${TEST_TIMEOUT:-3600}" bash -c)
  case $lang in
    node|ruby)
      if [ "$lang" = ruby ]; then
        printf '%s\n' 'require "simplecov"' 'SimpleCov.coverage_dir(ENV.fetch("CONVEYOR_MAP_COV"))' \
          'SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter' 'SimpleCov.start' > "$tmp/cov.rb" || return 1
      fi
      for t in "${ts[@]}"; do
        n=$((n + 1)); mkdir -p "$tmp/c$n" && cmd=$(mapone "$d" "$t" "$lang") || return 1
        if [ "$lang" = node ] && w=$(mapother "$d" "$t"); then mapskip "$tmp" "$w" "$t"
        elif [ "$lang" = node ]; then
          if (cd "$d" && NODE_V8_COVERAGE=$tmp/c$n "${run[@]}" "$cmd") > "$tmp/out" 2>&1 < /dev/null; then ok=$((ok + 1))
            cat "$tmp/c$n"/*.json 2>/dev/null | jq -r --arg r "file://$abs/" --arg t "$t" '.result[]?.url | strings | select(startswith($r)) | ltrimstr($r) | "\($t)\t\(.)"'
          else mapskip "$tmp" '' "$t"; fi
        elif (cd "$d" && CONVEYOR_MAP_COV=$tmp/c$n RUBYOPT="-r$tmp/cov.rb ${RUBYOPT:-}" "${run[@]}" "$cmd") > "$tmp/out" 2>&1 < /dev/null \
          && jq -r --arg r "$abs/" --arg t "$t" '.[]?.coverage | objects | to_entries[]
            | select(.value | (if type == "object" then .lines else . end) | arrays | any(type == "number" and . > 0))
            | .key | select(startswith($r)) | ltrimstr($r) | "\($t)\t\(.)"' "$tmp/c$n/.resultset.json" 2>> "$tmp/out"; then ok=$((ok + 1))
        else mapskip "$tmp" '' "$t"; fi
        cat "$tmp/out" >> "$tmp/log" 2>/dev/null; rm -f "$tmp/out"
        [ -z "${MAPRUN:-}" ] || mapstep $n
      done ;;
    python)
      # The module and arguments of the test command (python -m <module> ..., pytest ...), else pytest.
      packget test.command cmd || return 1
      if [[ $cmd =~ ^(python3?|py)[[:space:]]+-m[[:space:]]+(.+)$ ]]; then m="-m ${BASH_REMATCH[2]}"
      elif [[ $cmd =~ ^pytest([[:space:]].*)?$ ]]; then m="-m pytest${BASH_REMATCH[1]}"; else m='-m pytest'; fi
      # Its output names each test file (mappyran()) even where the command is quiet (pytest -q prints only dots,
      # unittest without -v too): the last verbosity given wins.
      if [ -n "${MAPRUN:-}" ]; then case $m in '-m pytest'|'-m pytest '*) m+=' --verbosity=0' ;; '-m unittest'|'-m unittest '*) m+=' -v' ;; esac; fi
      [ $# = 0 ] || m+=" $(printf '%q ' "${ts[@]}")"
      printf '[run]\ndynamic_context = test_function\nrelative_files = True\n' > "$tmp/rc" || return 1
      if [ -n "${MAPRUN:-}" ]; then
        printf '%s\n' "${ts[@]}" > "$tmp/tests" || return 1
        while :; do mapstep "$(mappyran "$tmp/tests" "$tmp/log" | wc -l)"; sleep 2; done > /dev/null 2>&1 < /dev/null 8>&- &
        k=$!
      fi
      (cd "$d" && COVERAGE_FILE=$tmp/py.cov "${run[@]}" "coverage run --rcfile=$(printf %q "$tmp/rc") $m") >> "$tmp/log" 2>&1 < /dev/null; rc=$?
      [ "$k" = 0 ] || { kill "$k" 2>/dev/null; wait "$k" 2>/dev/null; rm -f "$(mapprogpath).$k"; } # and its count's file, if killed as it wrote
      [ $rc = 0 ] || { mapfail 'the suite' "$tmp"; return 1; }
      (cd "$d" && COVERAGE_FILE=$tmp/py.cov coverage json --rcfile="$tmp/rc" --show-contexts -o "$tmp/py.json") >> "$tmp/log" 2>&1 < /dev/null || { mapfail 'coverage json' "$tmp"; return 1; }
      [ -z "${MAPRUN:-}" ] || mapstep ${#ts[@]}
      ok=1; mappy "$abs" "$tmp/py.json" "${ts[@]}" ;;
    go)
      mod=$(cd "$d" && go list -m 2>>"$tmp/log") || { mapfail 'go list -m' "$tmp"; return 1; }
      # Each package that holds a test file, once: its profile is of its test files together.
      while IFS= read -r m; do
        n=$((n + 1)); rx=$([ "$m" = . ] && echo '^[^/]+$' || printf '^%s/[^/]+$' "$m")
        if (cd "$d" && "${run[@]}" "go test -count=1 -coverpkg=./... -coverprofile=$(printf %q "$tmp/go$n") ./$(printf %q "$m")") > "$tmp/out" 2>&1 < /dev/null; then ok=$((ok + 1))
          awk -v m="$mod/" 'NR > 1 && $NF > 0 { f = $1; sub(/:[^:]*$/, "", f); if (index(f, m) == 1) print substr(f, length(m) + 1) }' "$tmp/go$n" | sort -u \
            | while IFS= read -r f; do printf '%s\n' "${ts[@]}" | grep -E "$rx" | while IFS= read -r t; do printf '%s\t%s\n' "$t" "$f"; done; done
        else mapfile -t w < <(printf '%s\n' "${ts[@]}" | grep -E "$rx"); mapskip "$tmp" '' "${w[@]}"; fi
        cat "$tmp/out" >> "$tmp/log" 2>/dev/null; rm -f "$tmp/out"
        [ -z "${MAPRUN:-}" ] || { k=$((k + $(printf '%s\n' "${ts[@]}" | grep -cE "$rx"))); mapstep $k; }
      done < <(printf '%s\n' "${ts[@]}" | sed -e 's|/[^/]*$||' -e 's|^[^/]*_test\.go$|.|' | sort -u) ;;
    rust)
      for t in "${ts[@]}"; do
        n=$((n + 1)); m=${t##*/}; m=${m%.rs}
        if (cd "$d" && "${run[@]}" "cargo llvm-cov --json --summary-only --test $(printf %q "$m") > $(printf %q "$tmp/rs$n.json")") > "$tmp/out" 2>&1 < /dev/null; then ok=$((ok + 1))
          jq -r --arg r "$abs/" --arg t "$t" '.data[]?.files[]? | select(.summary.lines.covered > 0) | .filename | select(startswith($r)) | ltrimstr($r) | "\($t)\t\(.)"' "$tmp/rs$n.json"
        else mapskip "$tmp" '' "$t"; fi
        cat "$tmp/out" >> "$tmp/log" 2>/dev/null; rm -f "$tmp/out"
        [ -z "${MAPRUN:-}" ] || mapstep $n
      done ;;
    *) echo "no coverage tool for $lang" >&2; return 1 ;;
  esac
  # No test file ran: the run fails, saying so, with the first that could not be mapped.
  [ "$ok" = 0 ] || return 0
  jq -r 'select(.file) | "no test file could be mapped (each failed under coverage or runs only under another runner); the first, \(.file): \(.why)"' "$tmp/skipped" 2>/dev/null \
    | head -n 12 | grep . >&2 || echo "no test file could be mapped" >&2
  return 1
}
# The pairs (mapcollect()'s lines) of coverage.py's report <json> (coverage json --show-contexts) of a run in <dir>: a
# context is a test function's dotted name (<module>.<class>.<function>), and its test file is the one of <tests> whose
# path, as a module name, is the longest that starts it (tests/test_a.py: tests.test_a, or test_a as pytest may import it).
mappy() { # <dir, absolute> <json> <test file>...
  local r=$1/ j=$2; shift 2
  jq -rn --arg r "$r" --slurpfile j "$j" --rawfile ts <(printf '%s\n' "$@") '[$ts | split("\n")[] | select(. != "")] as $ts
    | [$ts[] | . as $t | sub("\\.py$"; "") | split("/") as $p | range($p | length) | {t: $t, m: ($p[.:] | join("."))}] as $ms
    | $j[0].files | to_entries[] | .key as $f | ($f | ltrimstr($r)) as $f
    | [.value.contexts // {} | .[][]] | unique[] | select(. != "") as $c
    | [$ms[] | select(.m as $m | $c | startswith($m + "."))] | max_by(.m | length) // empty | "\(.t)\t\($f)"'
}
# The pairs of V8's coverage files in <folder> (NODE_V8_COVERAGE) of a run in <dir>: a file is a Node process, and
# each test file of <tests> it ran goes with every file of <dir> it ran (node --test runs each test file in a process
# of its own; a runner that runs them all in one process maps each of its sources to all of them).
mapv8() { # <dir, absolute> <folder> <test file>...
  local r=$1/ c=$2 fs=(); shift 2
  fs=("$c"/*.json); [ -e "${fs[0]}" ] || return 0
  # The coverage files and the tests go through standard input and a file, not as arguments: both grow with the project.
  printf '%s\0' "${fs[@]}" | xargs -0 cat | jq -rn --arg r "file://$r" --rawfile ts <(printf '%s\n' "$@") '([$ts | split("\n")[] | select(. != "")] | INDEX(.)) as $ts
    | inputs | [.result[]?.url | strings | select(startswith($r)) | ltrimstr($r)] | unique
    | . as $fs | .[] | select($ts[.]) as $t | $fs[] | "\($t)\t\(.)"'
}
# Writes the map of <dir> from <pairs> (mapcollect()'s lines): of each test, the tracked files it touched that are not
# test files are its sources. With no <tests>, a new map, of every test the run mapped, on <dir>'s HEAD; with
# <tests>, the map there (mappath()) with those tests mapped again: each taken out of every source and put back where
# the run found it, the rest of the map (its commit) kept. <not mapped> (mapcollect()'s <tmp>/skipped, or "" for none)
# is its notMapped: with <tests>, each of them is taken out of the map's notMapped first, and one that is in <not
# mapped> is not added to its tests (the next run of the file tries again). notMapped also names each test runner
# (TESTRUNNERS, no test file: testpaths()) with the reason RUNNERFIX. Written beside it and moved in, so a reader never
# sees half.
mapwrite() { # <dir> <pairs file> <not mapped file, or ""> <language> <seconds> [<test file>...]
  local d=$1 p=$2 nm=${3:-/dev/null} lang=$4 sec=$5 f cmd sha; shift 5
  f=$(mappath); packget test.command cmd && sha=$(git -C "$d" rev-parse HEAD) || return 1
  names || return 1
  jq -n --arg rn "$TESTRUNNERS" --arg rf "$RUNNERFIX" --rawfile p "$p" --rawfile all <(git -C "$d" -c core.quotePath=false ls-files) --rawfile ts <(git -C "$d" -c core.quotePath=false ls-files | testpaths) \
    --slurpfile old <(if [ $# -gt 0 ]; then cat "$f" 2>/dev/null; fi) --arg sha "$sha" --arg cmd "$cmd" --arg l "$lang" --argjson s "$sec" --slurpfile nm "$nm" --rawfile only <(printf '%s\n' "$@") '
    def ls: split("\n") | map(select(. != ""));
    (($all | ls) - ($ts | ls) | INDEX(.)) as $src
    | [$p | ls[] | split("\t") | select(length == 2 and $src[.[1]])] as $pairs
    | ($only | ls) as $only
    | (if $only == [] then {commit: $sha, command: $cmd, language: $l, made: (now | todate), seconds: $s, tests: [], sources: {}}
       else ($old[0] // {commit: $sha, command: $cmd, language: $l, made: (now | todate), seconds: $s, tests: [], sources: {}})
         | .sources |= map_values(. - $only) | .tests -= $only end)
    | .notMapped = ([.notMapped[]? | select(.why != $rf and (.file as $f | $only | index($f) | not))] + [$nm[] | objects]
        + [$rn | ls[] | {file: ., why: $rf}] | unique_by(.file))
    | .tests = (.tests + (if $only == [] then [$pairs[][0]] else $only - [.notMapped[].file] end) | unique)
    | reduce $pairs[] as $x (.; .sources[$x[1]] = ((.sources[$x[1]] // []) + [$x[0]] | unique))
    | .sources |= with_entries(select(.value != []))' > "$f.new" && mv -f "$f.new" "$f" || { rm -f "$f.new"; return 1; }
}
# What the run that makes the map may cost, as setup asks before it: the time of the last whole-suite run recorded
# (its files' seconds added up: suiterec(), lib/testlist.sh), or that none is recorded.
mapsuitesec() { jq -rs '[.[] | objects | select(.files | type == "object")] | last | select(.) | [.files[].sec | numbers] | add // empty | round' "${STATE%/*}/suiteruns.jsonl" 2>/dev/null; }
mapcost() {
  local s
  s=$(mapsuitesec)
  if [ -n "$s" ]; then echo "It takes about ${s}s or more: the last whole-suite run took ${s}s."
  else echo "Its time is not known (no whole-suite run is recorded): about as long as the whole suite, or more."; fi
}
# Makes the map of <dir> (setup's main checkout) with the whole suite under coverage
# (mapcollect()), and says how many sources and tests it mapped, how many test files it could not map, and how long
# the run took; exit 1, saying why, when the language has no tool, or the run fails (the tool fails, or no test file
# maps): the map there is kept, and with none a card's tests are found by name.
# The run says how far it is as it goes, and why it failed when it does, in test-map.run.json (mapprogpath()).
mapbuild() { # <dir>
  local lang tool tmp w=$SECONDS rc=0 sec MAPRUN=1
  lang=$(maplang "$1"); tool=$(maptool "$lang" "$1") || { echo "conveyor: no test map: $tool; a card's tests are found by name" >&2; return 1; }
  tmp=$(mktemp -d) || return 1
  mapcollect "$1" "$lang" "$tmp" > "$tmp/pairs" 2> "$tmp/err" || rc=1
  [ $rc != 0 ] || [ -s "$tmp/pairs" ] || { echo 'it mapped no test file' > "$tmp/err"; rc=1; }
  sec=$((SECONDS - w))
  if [ $rc = 0 ] && mapwrite "$1" "$tmp/pairs" "$tmp/skipped" "$lang" "$sec"; then
    mapend
    jq -r --arg tool "$tool" --arg f "$(mappath)" '"conveyor: wrote the test map \($f) with \($tool): \(.sources | length) source files, \(.tests | length) test files\(.notMapped | length
      | if . > 0 then ", \(.) not mapped (each with why in its notMapped)" else "" end), in \(.seconds)s"' "$(mappath)"
  else
    mapend "the run with $tool failed after ${sec}s: $(mapwhy "$tmp/err" || echo 'the map could not be written')"
    echo "conveyor: no test map: the run with $tool failed after ${sec}s; a card's tests are found by name: $(cat "$tmp/err")" >&2; rc=1
  fi
  rm -rf "$tmp"; return $rc
}
# A build by hand (`conveyor.sh testmap build`, the Board's Build the test map): mapbuild() on the main checkout, in
# the background, on one of the machine's test slots as a test run takes one (tests(), lib/testrun.sh). Its record is
# test-map.build.json beside the map (mapbuildpath()): {pid (its runner, while it runs), start, end (seconds since
# 1970; end null while it runs), state (waiting for a test slot, running, made, failed or stopped), reason (failed or
# stopped: why), tool (the coverage tool)}. One build at a time: the runner holds an flock on test-map.lock
# (maplockpath()) from the ask to its end, and a whole run on main does not collect coverage meanwhile (mapcovon()).
mapbuildpath() { echo "${PACK%/*}/test-map.build.json"; }
maplockpath() { echo "${PACK%/*}/test-map.lock"; }
mapheld() { [ -e "$(maplockpath)" ] && ! flock -n "$(maplockpath)" true 2>/dev/null; }
maprec() { jq -c "$@" > "$(mapbuildpath).new" && mv -f "$(mapbuildpath).new" "$(mapbuildpath)" || { rm -f "$(mapbuildpath).new"; return 1; }; } # <jq arguments>...
# The ask: refused (exit 2, nothing started, saying why) with test.map off (and how to turn it on), a map the project
# keeps itself, a language with no coverage tool or the tool not installed (maptool()), a build already running or a
# whole run on main making the map. Else the runner starts (maprunbuild()), and the ask returns once its record is written.
mapask() {
  local m lang tool fd i
  packget test.map m || { echo "conveyor: the pack's test.map could not be read; nothing started" >&2; return 1; }
  [ "$m" != off ] || { echo "conveyor: the test map is off (the pack's test.map is \"off\"), so a card's tests are found by name. To turn it on, remove test.map from $PACK, then run setup with --test-map yes, or run this command again; nothing started" >&2; return 2; }
  [ -z "$m" ] || { echo "conveyor: the pack's test.map names a map the project keeps itself ($m): Conveyor does not make it; nothing started" >&2; return 2; }
  lang=$(maplang "$MAIN"); tool=$(maptool "$lang" "$MAIN") || { echo "conveyor: no test map can be made: $tool; a card's tests are found by name; nothing started" >&2; return 2; }
  { exec {fd}>>"$(maplockpath)"; } 2>/dev/null || { echo "conveyor: the test map's lock $(maplockpath) could not be made; nothing started" >&2; return 1; }
  flock -n "$fd" || { exec {fd}>&-; echo "conveyor: a build of the test map is running; nothing started" >&2; return 2; }
  [ "$(mapstate "$MAIN" | jq -r .state)" != running ] || { exec {fd}>&-; echo "conveyor: a whole run on main is making the test map; nothing started" >&2; return 2; }
  rm -f "$(mapbuildpath)"
  # The runner holds the lock (its copy of fd) and no other descriptor of this process's: the Board's ssh ends with this
  # process, not with it.
  ( trap - TERM; trap '' HUP; [ -z "${LOGFD:-}" ] || exec {LOGFD}>&-; maprunbuild "$tool" ) > /dev/null 2>&1 < /dev/null 8>&- &
  exec {fd}>&-
  for ((i = 0; i < 100; i++)); do [ ! -s "$(mapbuildpath)" ] || { echo "conveyor: the test map is being built with $tool"; return 0; }; sleep 0.1; done
  echo "conveyor: the build of the test map did not start" >&2; return 1
}
# The runner of a build by hand: its record first (waiting, then running once it has a test slot), mapbuild() in a
# subshell pinned to the slot's core (slot_mine()) whose pid the run's progress names (MAPPID), and its record last,
# with how it ended. A TERM (mapquit()) ends the build with each process it started (taend(), lib/testaction.sh): its
# progress file goes, so the map there (or none) is shown as it was, and the record says stopped.
maprunbuild() { # <tool>
  local me=$BASHPID stopped='' bp rc=0 tmp st why=null
  trap 'stopped=1' TERM
  maprec -n --argjson p "$me" --arg t "$1" '{pid: $p, start: (now | floor), end: null, state: "waiting", reason: null, tool: $t}' || return 1
  if slot_pool && { [ -n "$SLOT_HOME" ] || until [ -n "$stopped" ] || slot_try || slot_wait; do :; done; } && [ -z "$stopped" ]; then
    maprec '.state = "running"' "$(mapbuildpath)"
    tmp=$(mktemp -d) || tmp=''
    ( [ -n "$SLOT_HOME" ] || slot_mine || exit 1; MAPPID=$BASHPID TMPDIR=${tmp:-${TMPDIR:-/tmp}} mapbuild "$MAIN" ) > /dev/null 2> "${tmp:-/tmp}/err.$me" & bp=$!
    [ -n "$stopped" ] || { wait "$bp"; rc=$?; }
    if [ -n "$stopped" ]; then trap '' TERM; taend "$bp"; wait "$bp" 2>/dev/null; mapend; st=stopped why='"stopped by hand"'
    elif [ "$rc" = 0 ]; then st=made
    else st=failed; why=$(jq -c '.failed | strings' "$(mapprogpath)" 2>/dev/null | grep . || jq -Rc . < <(mapwhy "${tmp:-/tmp}/err.$me" || echo 'the build failed'))
    fi
    [ -n "$SLOT_HOME" ] || slot_free
    rm -rf "${tmp:-/tmp}/err.$me" ${tmp:+"$tmp"}
  elif [ -n "$stopped" ]; then st=stopped why='"stopped by hand, before it had a test slot"'
  else st=failed why='"the machine'\''s test slots could not be read"'; fi
  maprec --arg s "$st" --argjson w "$why" '. + {end: (now | floor), state: $s, reason: $w} | del(.pid)' "$(mapbuildpath)"
}
# `testmap stop`: TERM to the running build's runner, again every 2 s while its record names it, for up to 40 s;
# prints how it ended. None running is refused (exit 2), and nothing is stopped.
mapquit() {
  local f p i
  f=$(mapbuildpath)
  p=$(jq -er '.pid | numbers' "$f" 2>/dev/null) && kill -0 "$p" 2>/dev/null || { echo "conveyor: no build of the test map is running; nothing stopped" >&2; return 2; }
  for ((i = 0; i < 400; i++)); do
    [ $((i % 20)) != 0 ] || kill -TERM "$p" 2>/dev/null
    jq -e 'has("pid")' "$f" > /dev/null 2>&1 || { echo "conveyor: the build of the test map is $(jq -r .state "$f" 2>/dev/null)"; return 0; }
    sleep 0.1
  done
  echo "conveyor: the build of the test map did not end within 40 s of its stop" >&2; return 1
}
# The Tests page's Test map part (the snapshot's testMap, lib/snapshot.sh): mapstate() of <dir>, with made and seconds
# for a made map (when it was made, and how long its run took; null for a map the project keeps itself) and notMapped
# (its test files the run could not map, [{file, why}]; [] for none or a map the project keeps itself); tool (the
# coverage tool, else null) and toolWhy (why there is none, else null) unless it is off; a map the project keeps
# itself has no tool, as a build of it is refused (mapask()), and toolWhy says so; suiteSec (the seconds of the
# last whole-suite run recorded, mapsuitesec(), else null); and build (the last build by hand's record, else null; one
# whose runner is gone, or no longer holds the lock, as after a restart, is failed, saying so). Exit 1 when the pack
# cannot be read.
mapboard() { # <dir>
  local s st m lang t='' tw='' b p
  s=$(mapstate "$1") && packget test.map m || return 1
  st=$(jq -r .state <<<"$s")
  if [ "$st" = off ]; then :
  elif [ -n "$m" ]; then tw="the pack's test.map names a map the project keeps itself ($m): Conveyor does not make it"
  else lang=$(maplang "$1"); if t=$(maptool "$lang" "$1"); then tw=''; else tw=$t; t=''; fi; fi
  b=$(jq -ce 'objects' "$(mapbuildpath)" 2>/dev/null) || b=null
  if [ "$b" != null ] && p=$(jq -er '.pid | numbers' <<<"$b") && { ! kill -0 "$p" 2>/dev/null || ! mapheld; }; then
    b=$(jq -c '. + {state: "failed", reason: "its run stopped before it ended"} | del(.pid)' <<<"$b")
  fi
  jq -c --arg t "$t" --arg tw "$tw" --arg sec "$(mapsuitesec)" --argjson b "$b" --slurpfile m <(if [ "$st" = made ] && [ -z "$m" ]; then cat "$(mappath)" 2>/dev/null; fi) '.
    + (if .state == "made" then {made: ($m[0].made // null), seconds: ($m[0].seconds // null), notMapped: [$m[0].notMapped[]? | {file, why}]} else {} end)
    + {tool: (if $t == "" then null else $t end), toolWhy: (if $tw == "" then null else $tw end), suiteSec: ($sec | tonumber? // null), build: $b}' <<<"$s"
}
# The test files of the change staged in <worktree> that the made map does not hold yet, after a card's run that
# passed (tests()): each run alone under coverage and added to the map (mapwrite()), so the next card that changes
# what it covers runs it. A file whose run fails is added to the map's notMapped alone (all failing, nothing is added);
# the next run of the file tries again.
mapnew() { # <worktree>
  local m lang tmp ts=()
  packget test.map m && [ -z "$m" ] && [ -s "$(mappath)" ] || return 0
  lang=$(jq -r '.language // ""' "$(mappath)") && [ -n "$lang" ] || return 0
  mapfile -t ts < <(comm -12 <(git -C "$1" -c core.quotePath=false diff --cached --name-only --diff-filter=AM --no-renames HEAD -- 2>/dev/null | sort) <(maptests "$1" "$lang" | sort) \
    | grep -vxFf <(jq -r '.tests[]?' "$(mappath)") || :)
  [ ${#ts[@]} -gt 0 ] && tmp=$(mktemp -d) || return 0
  if mapcollect "$1" "$lang" "$tmp" "${ts[@]}" > "$tmp/pairs" 2>/dev/null && mapwrite "$1" "$tmp/pairs" "$tmp/skipped" "$lang" 0 "${ts[@]}"; then
    echo "conveyor: test map: mapped $(printf '%s, ' "${ts[@]}" | sed 's/, $//') on its first run"
  fi
  rm -rf "$tmp"; return 0
}
# Why the made map is due to be made again at the next whole run, on stdout (exit 0), else exit 1: it was made under
# another test command, or its commit is not in <dir>'s history, or is more commits behind <dir>'s HEAD than the
# pack's test.mapAge. A project with no made map has none due (setup asks before the first).
mapdue() { # <dir>
  local f age cmd mc n
  f=$(mappath); [ -s "$f" ] || return 1
  packget test.mapAge age test.command cmd || return 1
  mc=$(jq -r '.command // ""' "$f") || return 1
  [ "$mc" = "$cmd" ] || { echo "it was made under another test command ($mc)"; return 0; }
  mc=$(jq -r '.commit // ""' "$f") && [ -n "$mc" ] && n=$(git -C "$1" rev-list --count "$mc..HEAD" 2>/dev/null) \
    || { echo "its commit is not in the history"; return 0; }
  [ "$n" -le "${age:-200}" ] || { echo "it is $n commits old (test.mapAge: ${age:-200})"; return 0; }
  return 1
}
# Before a whole run on main (the whole test on main, the release check) in <worktree>: when the made map is due
# (mapdue()), coverage is turned on for the run itself, into <worktree>.mapcov, through its environment, saying why:
# Node's V8 coverage (NODE_V8_COVERAGE), or Python's coverage.py started in each Python process with dynamic contexts
# (COVERAGE_PROCESS_START, read by a sitecustomize put first on PYTHONPATH; a Python with no coverage module runs as
# it would). maprefresh() makes the map from it after a pass; mapcovoff() turns it off. While a build by hand runs
# (mapheld()), it collects none, saying so. A Go, Rust or Ruby run cannot
# collect coverage a test file at a time so: after it passes, maprefresh() runs its tests again under the language's
# tool, as setup does (mapcollect()), and the run says so. A pack whose test.map is set (off, or a map of its own) has
# none to refresh. A Node or Python run says how far it is (mapstart(), maptick()) at once and then every 2 seconds,
# until mapcovoff().
mapcovon() { # <worktree>
  local m why lang n c=$1.mapcov
  rm -rf "$c"; packget test.map m && [ -z "$m" ] || return 0
  why=$(mapdue "$1") || return 0
  ! mapheld || { echo "conveyor: test map: due, as $why, but a build of it by hand runs (testmap build): this run collects no coverage"; return 0; }
  lang=$(jq -r '.language // ""' "$(mappath)")
  case $lang in
    node) mkdir -p "$c/v8" || return 1; export NODE_V8_COVERAGE=$c/v8 ;;
    python)
      mkdir -p "$c/site" && printf '[run]\nparallel = True\ndynamic_context = test_function\nrelative_files = True\n' > "$c/rc" \
        && printf '%s\n' 'try:' '    import coverage' 'except ImportError:' '    pass' 'else:' '    coverage.process_startup()' > "$c/site/sitecustomize.py" || return 1
      MAPCOV_PATH=${PYTHONPATH-}; export COVERAGE_PROCESS_START=$c/rc COVERAGE_FILE=$c/py.cov PYTHONPATH=$c/site${PYTHONPATH:+:$PYTHONPATH} ;;
    go|rust|ruby) mkdir -p "$c" && echo "$lang" > "$c/lang" && date +%s > "$c/start" || return 1
      echo "conveyor: test map: due, as $why: after the whole run passes, its tests run again under coverage to make it again"; return 0 ;;
    *) echo "conveyor: test map: due, as $why, but a ${lang:-such} whole run cannot collect its coverage: remove $(mappath) and run setup to make it again"; return 0 ;;
  esac
  echo "$lang" > "$c/lang" && date +%s > "$c/start" || return 1
  maptests "$1" "$lang" > "$c/tests" && n=$(wc -l < "$c/tests") && mapstart $((n))
  maptick "$1" "$lang" > /dev/null 2>&1 < /dev/null 8>&- &
  MAPTICK=$!
  echo "conveyor: test map: the whole run collects coverage to make it again, as $why"
}
# While a whole run with coverage on runs in <worktree> (mapcovon()), every 2 seconds, how many of its test files
# (<worktree>.mapcov/tests) have run: Node's, those a V8 coverage file names (node --test runs each test file in a
# process of its own, which writes its file as it ends; a file not yet whole is read again on the next look); Python's,
# those the run's output names (mappyran()); and never fewer than the test files its runner marks as ended (suiteprog(),
# lib/fulltest.sh).
maptick() { # <worktree> <language>
  local wt=$1 lang=$2 c=$1.mapcov r f k got logs=()
  local -A seen=() ran=()
  r="file://$(cd "$wt" && pwd -P)/" || return 1
  while :; do
    case $lang in
      node) for f in "$c"/v8/*.json; do
          [ -e "$f" ] && [ -z "${seen[$f]:-}" ] || continue
          got=$(jq -r --arg r "$r" '.result[]?.url | strings | select(startswith($r)) | ltrimstr($r)' "$f" 2>/dev/null) || continue
          seen[$f]=1
          while IFS= read -r k; do ran[$k]=1; done < <(grep -xF -f "$c/tests" <<<"$got")
        done ;;
      python)
        mapfile -t logs < <(find "$wt.testlog" -maxdepth 1 -type f 2>/dev/null); [ ${#logs[@]} -gt 0 ] || logs=("$wt.test")
        while IFS= read -r k; do ran[$k]=1; done < <(mappyran "$c/tests" "${logs[@]}") ;;
    esac
    k=$(suiteprog "$wt" | jq '.files.done // 0'); [ "${k:-0}" -ge ${#ran[@]} ] 2>/dev/null || k=${#ran[@]}
    mapstep "$k"; sleep 2
  done
}
# The Python test files of <tests file> (one a line) that a run's <logs> name so far, one a line, once each: pytest
# names each test file as it runs it, unittest -v each test's module (tests.test_a for tests/test_a.py).
mappyran() { # <tests file> <log>...
  local k
  sed 's/\.py$//; s|/|.|g; s/$/./' "$1" | cat "$1" - | grep -ohF -f - "${@:2}" 2>/dev/null | sort -u | while IFS= read -r k; do
    [[ $k == *.py ]] || { k=${k%.}; k=${k//.//}.py; }
    echo "$k"
  done | sort -u
}
mapcovoff() {
  [ -z "${MAPTICK:-}" ] || { kill "$MAPTICK" 2>/dev/null; wait "$MAPTICK" 2>/dev/null; unset MAPTICK; }
  unset NODE_V8_COVERAGE COVERAGE_PROCESS_START COVERAGE_FILE
  [ -z "${MAPCOV_PATH+x}" ] || { if [ -n "$MAPCOV_PATH" ]; then export PYTHONPATH=$MAPCOV_PATH; else unset PYTHONPATH; fi; unset MAPCOV_PATH; }
}
# After a whole run on main that passed with coverage on (mapcovon()), in its worktree: the map is made from that
# run's coverage (Go, Rust, Ruby: from a run of its tests under the language's tool, mapcollect()), saying what it
# mapped; a run whose coverage maps no test file, or that fails, keeps the map there, and says so.
maprefresh() { # <worktree>
  local c=$1.mapcov lang abs sec ts=() MAPRUN=1
  [ -s "$c/lang" ] || return 0
  lang=$(cat "$c/lang"); sec=$(( $(date +%s) - $(cat "$c/start") ))
  abs=$(cd "$1" && pwd -P) && mapfile -t ts < <(maptests "$1" "$lang")
  case $lang in
    node) mapv8 "$abs" "$c/v8" "${ts[@]}" > "$c/pairs" ;;
    python) (cd "$1" && export COVERAGE_FILE=$c/py.cov && coverage combine --rcfile="$c/rc" && coverage json --rcfile="$c/rc" --show-contexts -o "$c/py.json") > "$c/log" 2>&1 < /dev/null \
      && mappy "$abs" "$c/py.json" "${ts[@]}" > "$c/pairs" ;;
    go|rust|ruby) sec=$SECONDS; mapcollect "$1" "$lang" "$c" > "$c/pairs" 2> "$c/err" || { mapend "$(mapwhy "$c/err" || echo 'the coverage run failed')"; echo "conveyor: test map: not made again: $(cat "$c/err")"; rm -rf "$c"; return 0; }
      sec=$((SECONDS - sec)) ;;
  esac
  # A Node or Python whole run says nothing of the files it could not map: those the map listed, still test files
  # and still not mapped by this run, stay listed.
  case $lang in node|python) jq -c --rawfile p "$c/pairs" --rawfile ts <(printf '%s\n' "${ts[@]}") '[$p | split("\n")[] | split("\t")[0]] as $m
    | ($ts | split("\n")) as $ts | .notMapped[]? | select(.file as $f | ($ts | index($f)) and ($m | index($f) | not))' "$(mappath)" > "$c/skipped" 2>/dev/null || : ;; esac
  if [ -s "$c/pairs" ] && mapwrite "$1" "$c/pairs" "$c/skipped" "$lang" "$sec"; then
    mapend
    jq -r '"conveyor: test map: made again from the whole run'\''s coverage: \(.sources | length) source files, \(.tests | length) test files"' "$(mappath)"
  else mapend "the whole run's coverage mapped no test file"; echo "conveyor: test map: not made again: the whole run's coverage mapped no test file"; fi
  rm -rf "$c"
}
# A whole run on main that collected coverage (mapcovon()) but makes no map from it, as it failed or ran short: its
# coverage is dropped, and the map's run is said to have failed, with <why>.
mapstop() { # <worktree> <why>
  [ -e "$1.mapcov" ] || return 0
  rm -rf "$1.mapcov"; mapend "$2"
}
# The map a card's change in <worktree> is read against (testsel()), as {by, sources: {<source>: [<test file>]}, shared:
# [<source>], age}: none (no output) with test.map off, or no made map. by is "map"; age is how many commits the made
# map is behind the worktree's HEAD (null for a map of the project's own). A source is shared when more than half the
# mapped tests touch it (a setup, config or helper file most tests read): its change runs the whole suite. A map of the
# project's own is a JSON object {"<source>": ["<test file>", ...]}, or lines of areas as .conveyor/engine-areas.json
# holds them: {"area": <name>, "file": <source>}, {"area": <name>, "test": <test file>} (a name with no / is the tracked
# test file of that name), {"area": <name>, "tests": "all"} (every source of the area is shared), {"area": <name>,
# "why": <text>} and {"outside": <path>} (a file no area needs). A map that cannot be read, a line of none of these
# kinds, or a test it names that is no tracked test file, fails it (exit 1, the reason on stdout). Given <file>, a map
# of the project's own is read from it in place of the worktree's (testsel(): the map at the change's base).
mapread() { # <worktree> [<file>]
  local m f out age=null sha
  packget test.map m || { echo "the pack's test.map could not be read"; return 1; }
  case $m in off) return 0 ;; '') f=$(mappath); [ -s "$f" ] || return 0 ;; *) f=${2:-$1/$m} ;; esac
  if [ -z "$m" ]; then
    sha=$(jq -r '.commit // ""' "$f" 2>/dev/null) && [ -n "$sha" ] && age=$(git -C "$1" rev-list --count "$sha..HEAD" 2>/dev/null) || age=null
  fi
  out=$(jq -cs --rawfile ts <(git -C "$1" -c core.quotePath=false ls-files 2>/dev/null | testpaths) --argjson age "$age" --arg f "${m:-$f}" '
    ($ts | split("\n") | map(select(. != ""))) as $ts
    | def tfile: if contains("/") then . else . as $n | [$ts[] | select(split("/")[-1] == $n)]
        | if length == 1 then .[0] else error("\($f): \($n) is named, but there is no one tracked test file of that name") end end;
    (if length == 1 and (.[0] | type) == "object" and (.[0].sources | type) == "object" then {sources: .[0].sources, tests: (.[0].tests // []), all: []}
     elif length == 1 and (.[0] | type) == "object" and all(.[0][]; type == "array") then {sources: .[0], tests: ([.[0][][]] | unique), all: []}
     else reduce .[] as $l ({}; if ($l | type) == "object" and ($l | keys) == ["outside"] then .
         elif ($l | type) == "object" and ($l.area | type) == "string" and ($l | length) == 2 then
           .[$l.area] |= ((. // {files: [], tests: []}) | if ($l.file | type) == "string" then .files += [$l.file]
             elif ($l.test | type) == "string" then .tests += [$l.test | tfile] elif $l.tests == "all" then .all = true
             elif ($l.why | type) == "string" then . else error("\($f): not a line of the map: \($l | tojson)") end)
         else error("\($f): not a line of the map: \($l | tojson)") end)
       | {sources: (reduce (.[] | .tests as $t | .files[] | [., $t]) as [$s, $t] ({}; .[$s] = ((.[$s] // []) + $t | unique)) | with_entries(select(.value != []))),
          tests: ([.[].tests[]] | unique), all: [.[] | select(.all) | .files[]]} end)
    | (.tests | length) as $n
    | {by: "map", age: $age, sources: .sources, shared: (.all + [.sources | to_entries[] | select((.value | length) * 2 > $n) | .key] | unique)}' "$f" 2>&1) \
    || { out=${out#jq: error (at *): }; echo "${out:-$f: the test map cannot be read}"; return 1; }
  printf '%s\n' "$out"
}

# The files of <lines> (one a line), the first 12 joined by ", ", and how many more there are.
briefcap() { # <lines>
  awk 'NR <= 12 { printf "%s%s", (NR > 1 ? ", " : ""), $0 } NR > 12 { n++ } END { if (n) printf " and %d more", n }' <<<"$1"
}
# The files with a line of <git grep -n output> that is code: no line of a Markdown file, and none that starts with a
# comment mark (# // * /*), as a word in a comment is no caller. Reads the grep's lines on stdin.
briefcode() {
  grep -vE -e '^[^:]*\.md:' -e '^[^:]*:[0-9]+:[[:space:]]*(#|//|\*|/\*)' | cut -d: -f1 | sort -u
}
# <text> with each character that is special in an extended regular expression escaped.
briefesc() { # <text>
  sed 's/[].[\*^$+?(){}|]/\\&/g' <<<"$1"
}
# An extended regular expression for a reference to the tracked file <path> in code: its name alone (control.sh), after
# a directory path that ends its own (lib/control.sh, conveyor/lib/control.sh), after a shell variable ($DIR/control.sh)
# or after a closing paren or quote. A same-named file of another directory (commands/control.sh) is none of these.
# When another tracked file of <worktree> has the same name, the name alone (control.sh) or after a variable says
# nothing of which one it is, so only a path that ends its own counts.
briefref() { # <worktree> <path>
  local wt=$1 f=$2 b d sfx='' q="'" end='([^A-Za-z0-9_.-]|\.([^A-Za-z0-9_]|$)|$)' same
  same=$(git -C "$wt" ls-files -- 2>/dev/null | awk -F/ -v b="${f##*/}" '$NF == b { n++ } END { print n + 0 }')
  b=$(briefesc "${f##*/}"); d=${f%/*}; [ "$d" != "$f" ] || d=''
  while [ -n "$d" ]; do
    sfx+="${sfx:+|}$(briefesc "$d")/"
    [[ $d == */* ]] && d=${d#*/} || d=''
  done
  if [ "$same" -gt 1 ] && [ -n "$sfx" ]; then printf '%s' "(^|[^A-Za-z0-9_./-])($sfx)$b$end"
  else printf '%s' "(^|[^A-Za-z0-9_./-])(${sfx:-^})?$b$end|(\\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?|[)\"$q])/$b$end"; fi
}
# The files that call the function <name>, one a line: a shell command (a *.sh or *.bash file, the name at the start
# of a line, or after ; & | ( { ! then do else if while until, and followed by a space, a ; & or the end) and, in any
# other file but a Markdown page, a call written name( that is not a definition. Not a line in a comment.
briefcalls() { # <worktree> <name>
  local wt=$1 n=$2 dp dq
  dp="^[[:space:]]*(function[[:space:]]+)?${n}[[:space:]]*\\(\\)"; dq="(function|def|func|fn)[[:space:]]+${n}([^A-Za-z0-9_]|$)"
  { git -C "$wt" -c core.quotePath=false grep -nIE -e "(^|[;&|({]|(^|[[:space:]])(then|do|else|if|while|until|!))[[:space:]]*${n}([[:space:]]|;|&|$)" -- '*.sh' '*.bash' 2>/dev/null
    git -C "$wt" -c core.quotePath=false grep -nIE -e "(^|[^A-Za-z0-9_.\$])${n}[[:space:]]*\\(" -- . ':(exclude)*.md' ':(exclude)*.sh' ':(exclude)*.bash' 2>/dev/null
  } | grep -vE -e "^[^:]*:[0-9]+:${dp#^}" -e "^[^:]*:[0-9]+:.*$dq" | briefcode
}
# The build brief's starting point (card(), cardbuild()): for each tracked file (with or without a :line) and each
# function (name() or name(args)) the issue names, in backticks or bare, the files that define it, the files that call
# it (a call of a function; a file that names another by its path or name) and the test files the test map (mapread())
# ties to its file, one line each. The text says it is a starting point, never the scope: a call made by a name built at
# run time, or in another language, is not found. Nothing when the issue names no tracked file or function, or the
# search finds nothing for a name. The text starts with a blank line, as a part of the brief does.
startbrief() { # <worktree> <issue json>
  local wt=$1 toks t n defs hits tests m out='' lines='' fns=() files=() d
  mapfile -t toks < <(jq -r '[.title, .body] | map(strings) | join("\n") as $x
    | [($x | scan("`([^`\n]+)`") | .[0]), ($x | scan("(?<![A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_]*\\(\\)"))
       , ($x | scan("\\.?[A-Za-z0-9_][A-Za-z0-9_./-]*[A-Za-z0-9_](?::[0-9]+(?:-[0-9]+)?)?") | select(test("[./]")))] | unique | .[:80][]' <<<"$2")
  for t in "${toks[@]}"; do
    [[ $t =~ ^(.+):[0-9]+(-[0-9]+)?$ ]] && t=${BASH_REMATCH[1]}
    if [[ $t =~ ^([A-Za-z_][A-Za-z0-9_]*)\(.*\)$ ]]; then fns+=("${BASH_REMATCH[1]}"); else files+=("$t"); fi
  done
  m=$(mapread "$wt" 2>/dev/null) || m=''
  if [ ${#files[@]} -gt 0 ]; then
    mapfile -t files < <(git -C "$wt" ls-files -- 2>/dev/null | grep -xF -f <(printf '%s\n' "${files[@]}") | head -n 20)
    for t in "${files[@]}"; do
      hits=$(git -C "$wt" -c core.quotePath=false grep -nIE -e "$(briefref "$wt" "$t")" -- . ':(exclude)*.md' 2>/dev/null | briefcode | grep -vxF -- "$t")
      out=''; [ -z "$hits" ] || out="named in $(briefcap "$hits")"
      tests=''
      [ -z "$m" ] || tests=$(jq -r --arg f "$t" '.sources | objects | .[$f] // [] | .[]' <<<"$m")
      [ -z "$tests" ] || out+="${out:+; }mapped test files $(briefcap "$tests")"
      [ -z "$out" ] || lines+=$'\n'"- \`$t\`: $out"
    done
  fi
  while read -r n; do
    [ -n "$n" ] || continue
    # A definition: a shell `name()` at the start of a line, or `function`, `def`, `func` or `fn` before the name.
    defs=$(git -C "$wt" -c core.quotePath=false grep -lIE -e "^[[:space:]]*(function[[:space:]]+)?${n}[[:space:]]*\\(\\)" -e "(function|def|func|fn)[[:space:]]+${n}([^A-Za-z0-9_]|$)" 2>/dev/null)
    hits=$(briefcalls "$wt" "$n")
    out=''
    [ -z "$defs" ] || out="defined in $(briefcap "$defs")"
    [ -z "$hits" ] || out+="${out:+; }called in $(briefcap "$hits")"
    tests=''
    [ -z "$m" ] || [ -z "$defs" ] || tests=$(mapfile -t d <<<"$defs"; jq -r '.sources as $s | [$ARGS.positional[] as $f | ($s | objects | .[$f] // [])[]] | unique[]' --args "${d[@]}" <<<"$m")
    [ -z "$tests" ] || out+="${out:+; }mapped test files $(briefcap "$tests")"
    [ -z "$out" ] || lines+=$'\n'"- \`$n()\`: $out"
  done < <(printf '%s\n' "${fns[@]}" | sort -u | head -n 20)
  [ -z "$lines" ] || printf '\n\n# Where to start: callers and mapped tests\nThe issue names these files and functions. The list is a starting point, not the scope: it can miss a caller (a name built at run time, a call in another language) and a test. Check it against the code, and change only what the issue asks for.%s\n' "$lines"
}
