# SPDX-License-Identifier: Apache-2.0
# The test map (docs/configuration.md, The test map): which test files cover which source files, so a card's run is
# given the tests that cover what its change touches (testsel(), lib/testrun.sh). Setup makes it (setup()), with the
# project's own coverage tool; a whole run on main refreshes it from its own coverage when it is due (mapcovon(),
# maprefresh()); a card's run maps the test files it adds (mapnew()).
# The made map is the file test-map.json in the pack folder (mappath()): {commit (the commit it was made on), command
# (the pack's test.command then), language, made (when), seconds (how long the run took), tests (the test files
# mapped), sources: {<source file>: [<test file>, ...]}}.
# The pack's test.map: unset, the made map; "off", no map (a card's tests are found by name); else a path from the
# repository root of a map the project keeps itself, read in the card's worktree and never made or refreshed here
# (mapread()).
mappath() { echo "${PACK%/*}/test-map.json"; }
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
# The tracked test files (testpaths()) of <language> in <dir>, one a line: Node's are .js, .mjs, .cjs, .ts and the like,
# under __tests__/ or named *.test.*, *.spec.*; Python's test_*.py and *_test.py; Go's *_test.go; Rust's test
# binaries, tests/*.rs; Ruby's *_spec.rb. A file a test reads (a helper under test/) is no test of its own.
maptests() { # <dir> <language>
  local rx
  case $2 in
    node) rx='((^|/)__tests__/.*|[._-](test|spec))\.[cm]?[jt]sx?$' ;; python) rx='(^|/)(test_[^/]*|[^/]*_test)\.py$' ;;
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
# keeps the tracked source files). A run that fails (a test that fails, or the tool) fails it: its output's last lines
# go to stderr. The run's output is in <tmp>/log.
mapfail() { echo "$1 failed under coverage; the end of its output:" >&2; tail -n 20 "$2/log" >&2; return 1; } # <what> <tmp folder>
mapcollect() { # <dir> <language> <tmp folder> [<test file>...]
  local d=$1 lang=$2 tmp=$3 abs t n=0 cmd m ts mod rx; shift 3
  ts=("$@"); [ $# -gt 0 ] || mapfile -t ts < <(maptests "$d" "$lang")
  [ ${#ts[@]} -gt 0 ] || { echo "no $lang test files are tracked" >&2; return 1; }
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
        if [ "$lang" = node ]; then (cd "$d" && NODE_V8_COVERAGE=$tmp/c$n "${run[@]}" "$cmd") >> "$tmp/log" 2>&1 < /dev/null || { mapfail "$t" "$tmp"; return 1; }
          cat "$tmp/c$n"/*.json 2>/dev/null | jq -r --arg r "file://$abs/" --arg t "$t" '.result[]?.url | strings | select(startswith($r)) | ltrimstr($r) | "\($t)\t\(.)"'
        else (cd "$d" && CONVEYOR_MAP_COV=$tmp/c$n RUBYOPT="-r$tmp/cov.rb ${RUBYOPT:-}" "${run[@]}" "$cmd") >> "$tmp/log" 2>&1 < /dev/null || { mapfail "$t" "$tmp"; return 1; }
          jq -r --arg r "$abs/" --arg t "$t" '.[]?.coverage | objects | to_entries[]
            | select(.value | (if type == "object" then .lines else . end) | arrays | any(type == "number" and . > 0))
            | .key | select(startswith($r)) | ltrimstr($r) | "\($t)\t\(.)"' "$tmp/c$n/.resultset.json" || { mapfail "$t" "$tmp"; return 1; }
        fi
      done ;;
    python)
      # The module and arguments of the test command (python -m <module> ..., pytest ...), else pytest.
      packget test.command cmd || return 1
      if [[ $cmd =~ ^(python3?|py)[[:space:]]+-m[[:space:]]+(.+)$ ]]; then m="-m ${BASH_REMATCH[2]}"
      elif [[ $cmd =~ ^pytest([[:space:]].*)?$ ]]; then m="-m pytest${BASH_REMATCH[1]}"; else m='-m pytest'; fi
      [ $# = 0 ] || m+=" $(printf '%q ' "${ts[@]}")"
      printf '[run]\ndynamic_context = test_function\nrelative_files = True\n' > "$tmp/rc" || return 1
      (cd "$d" && COVERAGE_FILE=$tmp/py.cov "${run[@]}" "coverage run --rcfile=$(printf %q "$tmp/rc") $m") >> "$tmp/log" 2>&1 < /dev/null || { mapfail 'the suite' "$tmp"; return 1; }
      (cd "$d" && COVERAGE_FILE=$tmp/py.cov coverage json --rcfile="$tmp/rc" --show-contexts -o "$tmp/py.json") >> "$tmp/log" 2>&1 < /dev/null || { mapfail 'coverage json' "$tmp"; return 1; }
      mappy "$abs" "$tmp/py.json" "${ts[@]}" ;;
    go)
      mod=$(cd "$d" && go list -m 2>>"$tmp/log") || { mapfail 'go list -m' "$tmp"; return 1; }
      # Each package that holds a test file, once: its profile is of its test files together.
      while IFS= read -r m; do
        n=$((n + 1)); rx=$([ "$m" = . ] && echo '^[^/]+$' || printf '^%s/[^/]+$' "$m")
        (cd "$d" && "${run[@]}" "go test -count=1 -coverpkg=./... -coverprofile=$(printf %q "$tmp/go$n") ./$(printf %q "$m")") >> "$tmp/log" 2>&1 < /dev/null || { mapfail "./$m" "$tmp"; return 1; }
        awk -v m="$mod/" 'NR > 1 && $NF > 0 { f = $1; sub(/:[^:]*$/, "", f); if (index(f, m) == 1) print substr(f, length(m) + 1) }' "$tmp/go$n" | sort -u \
          | while IFS= read -r f; do printf '%s\n' "${ts[@]}" | grep -E "$rx" | while IFS= read -r t; do printf '%s\t%s\n' "$t" "$f"; done; done
      done < <(printf '%s\n' "${ts[@]}" | sed -e 's|/[^/]*$||' -e 's|^[^/]*_test\.go$|.|' | sort -u) ;;
    rust)
      for t in "${ts[@]}"; do
        n=$((n + 1)); m=${t##*/}; m=${m%.rs}
        (cd "$d" && "${run[@]}" "cargo llvm-cov --json --summary-only --test $(printf %q "$m") > $(printf %q "$tmp/rs$n.json")") >> "$tmp/log" 2>&1 < /dev/null || { mapfail "$t" "$tmp"; return 1; }
        jq -r --arg r "$abs/" --arg t "$t" '.data[]?.files[]? | select(.summary.lines.covered > 0) | .filename | select(startswith($r)) | ltrimstr($r) | "\($t)\t\(.)"' "$tmp/rs$n.json"
      done ;;
    *) echo "no coverage tool for $lang" >&2; return 1 ;;
  esac
}
# The pairs (mapcollect()'s lines) of coverage.py's report <json> (coverage json --show-contexts) of a run in <dir>: a
# context is a test function's dotted name (<module>.<class>.<function>), and its test file is the one of <tests> whose
# path, as a module name, is the longest that starts it (tests/test_a.py: tests.test_a, or test_a as pytest may import it).
mappy() { # <dir, absolute> <json> <test file>...
  local r=$1/ j=$2; shift 2
  jq -rn --arg r "$r" --slurpfile j "$j" '$ARGS.positional as $ts
    | [$ts[] | . as $t | sub("\\.py$"; "") | split("/") as $p | range($p | length) | {t: $t, m: ($p[.:] | join("."))}] as $ms
    | $j[0].files | to_entries[] | .key as $f | ($f | ltrimstr($r)) as $f
    | [.value.contexts // {} | .[][]] | unique[] | select(. != "") as $c
    | [$ms[] | select(.m as $m | $c | startswith($m + "."))] | max_by(.m | length) // empty | "\(.t)\t\($f)"' --args "$@"
}
# The pairs of V8's coverage files in <folder> (NODE_V8_COVERAGE) of a run in <dir>: a file is a Node process, and
# each test file of <tests> it ran goes with every file of <dir> it ran (node --test runs each test file in a process
# of its own; a runner that runs them all in one process maps each of its sources to all of them).
mapv8() { # <dir, absolute> <folder> <test file>...
  local r=$1/ c=$2 fs=(); shift 2
  fs=("$c"/*.json); [ -e "${fs[0]}" ] || return 0
  jq -rn --arg r "file://$r" '($ARGS.positional | INDEX(.)) as $ts
    | inputs | [.result[]?.url | strings | select(startswith($r)) | ltrimstr($r)] | unique
    | . as $fs | .[] | select($ts[.]) as $t | $fs[] | "\($t)\t\(.)"' "${fs[@]}" --args "$@"
}
# Writes the map of <dir> from <pairs> (mapcollect()'s lines): of each test, the tracked files it touched that are not
# test files are its sources. With no <tests>, a new map, of every test the run mapped, on <dir>'s HEAD; with
# <tests>, the map there (mappath()) with those tests mapped again: each taken out of every source and put back where
# the run found it, the rest of the map (its commit) kept. Written beside it and moved in, so a reader never sees half.
mapwrite() { # <dir> <pairs file> <language> <seconds> [<test file>...]
  local d=$1 p=$2 lang=$3 sec=$4 f cmd sha; shift 4
  f=$(mappath); packget test.command cmd && sha=$(git -C "$d" rev-parse HEAD) || return 1
  jq -n --rawfile p "$p" --rawfile all <(git -C "$d" -c core.quotePath=false ls-files) --rawfile ts <(git -C "$d" -c core.quotePath=false ls-files | testpaths) \
    --slurpfile old <(if [ $# -gt 0 ]; then cat "$f" 2>/dev/null; fi) --arg sha "$sha" --arg cmd "$cmd" --arg l "$lang" --argjson s "$sec" '
    def ls: split("\n") | map(select(. != ""));
    (($all | ls) - ($ts | ls) | INDEX(.)) as $src
    | [$p | ls[] | split("\t") | select(length == 2 and $src[.[1]])] as $pairs
    | ($ARGS.positional) as $only
    | (if $only == [] then {commit: $sha, command: $cmd, language: $l, made: (now | todate), seconds: $s, tests: [], sources: {}}
       else ($old[0] // {commit: $sha, command: $cmd, language: $l, made: (now | todate), seconds: $s, tests: [], sources: {}})
         | .sources |= map_values(. - $only) | .tests -= $only end)
    | .tests = (.tests + (if $only == [] then [$pairs[][0]] else $only end) | unique)
    | reduce $pairs[] as $x (.; .sources[$x[1]] = ((.sources[$x[1]] // []) + [$x[0]] | unique))
    | .sources |= with_entries(select(.value != []))' --args "$@" > "$f.new" && mv -f "$f.new" "$f" || { rm -f "$f.new"; return 1; }
}
# What the run that makes the map may cost, as setup asks before it: the time of the last whole-suite run recorded
# (its files' seconds added up: suiterec(), lib/testrun.sh), or that none is recorded.
mapcost() {
  local s
  s=$(jq -rs '[.[] | objects | select(.files | type == "object")] | last | select(.) | [.files[].sec | numbers] | add // empty | round' "${STATE%/*}/suiteruns.jsonl" 2>/dev/null)
  if [ -n "$s" ]; then echo "It takes about ${s}s or more: the last whole-suite run took ${s}s."
  else echo "Its time is not known (no whole-suite run is recorded): about as long as the whole suite, or more."; fi
}
# Makes the map of <dir> (setup's main checkout) with the whole suite under coverage
# (mapcollect()), and says how many sources and tests it mapped and how long the run took; exit 1, saying why, when
# the language has no tool, or the run fails: the map there is kept, and with none a card's tests are found by name.
mapbuild() { # <dir>
  local lang tool tmp w=$SECONDS rc=0 sec
  lang=$(maplang "$1"); tool=$(maptool "$lang" "$1") || { echo "conveyor: no test map: $tool; a card's tests are found by name" >&2; return 1; }
  tmp=$(mktemp -d) || return 1
  mapcollect "$1" "$lang" "$tmp" > "$tmp/pairs" 2> "$tmp/err" || rc=1
  [ $rc != 0 ] || [ -s "$tmp/pairs" ] || { echo 'it mapped no test file' > "$tmp/err"; rc=1; }
  sec=$((SECONDS - w))
  if [ $rc = 0 ] && mapwrite "$1" "$tmp/pairs" "$lang" "$sec"; then
    jq -r --arg tool "$tool" --arg f "$(mappath)" '"conveyor: wrote the test map \($f) with \($tool): \(.sources | length) source files, \(.tests | length) test files, in \(.seconds)s"' "$(mappath)"
  else
    echo "conveyor: no test map: the run with $tool failed after ${sec}s; a card's tests are found by name: $(cat "$tmp/err")" >&2; rc=1
  fi
  rm -rf "$tmp"; return $rc
}
# The test files of the change staged in <worktree> that the made map does not hold yet, after a card's run that
# passed (tests()): each run alone under coverage and added to the map (mapwrite()), so the next card that changes
# what it covers runs it. A run that fails adds nothing; the next run of the file tries again.
mapnew() { # <worktree>
  local m lang tmp ts=()
  packget test.map m && [ -z "$m" ] && [ -s "$(mappath)" ] || return 0
  lang=$(jq -r '.language // ""' "$(mappath)") && [ -n "$lang" ] || return 0
  mapfile -t ts < <(comm -12 <(git -C "$1" -c core.quotePath=false diff --cached --name-only --diff-filter=AM --no-renames HEAD -- 2>/dev/null | sort) <(maptests "$1" "$lang" | sort) \
    | grep -vxFf <(jq -r '.tests[]?' "$(mappath)") || :)
  [ ${#ts[@]} -gt 0 ] && tmp=$(mktemp -d) || return 0
  if mapcollect "$1" "$lang" "$tmp" "${ts[@]}" > "$tmp/pairs" 2>/dev/null && mapwrite "$1" "$tmp/pairs" "$lang" 0 "${ts[@]}"; then
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
# it would). maprefresh() makes the map from it after a pass; mapcovoff() turns it off. A Go, Rust or Ruby run cannot
# collect coverage a test file at a time so: after it passes, maprefresh() runs its tests again under the language's
# tool, as setup does (mapcollect()), and the run says so. A pack whose test.map is set (off, or a map of its own) has
# none to refresh.
mapcovon() { # <worktree>
  local m why lang c=$1.mapcov
  rm -rf "$c"; packget test.map m && [ -z "$m" ] || return 0
  why=$(mapdue "$1") || return 0
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
  echo "conveyor: test map: the whole run collects coverage to make it again, as $why"
}
mapcovoff() {
  unset NODE_V8_COVERAGE COVERAGE_PROCESS_START COVERAGE_FILE
  [ -z "${MAPCOV_PATH+x}" ] || { if [ -n "$MAPCOV_PATH" ]; then export PYTHONPATH=$MAPCOV_PATH; else unset PYTHONPATH; fi; unset MAPCOV_PATH; }
}
# After a whole run on main that passed with coverage on (mapcovon()), in its worktree: the map is made from that
# run's coverage (Go, Rust, Ruby: from a run of its tests under the language's tool, mapcollect()), saying what it
# mapped; a run whose coverage maps no test file, or that fails, keeps the map there, and says so.
maprefresh() { # <worktree>
  local c=$1.mapcov lang abs sec ts=()
  [ -s "$c/lang" ] || return 0
  lang=$(cat "$c/lang"); sec=$(( $(date +%s) - $(cat "$c/start") ))
  abs=$(cd "$1" && pwd -P) && mapfile -t ts < <(maptests "$1" "$lang")
  case $lang in
    node) mapv8 "$abs" "$c/v8" "${ts[@]}" > "$c/pairs" ;;
    python) (cd "$1" && export COVERAGE_FILE=$c/py.cov && coverage combine --rcfile="$c/rc" && coverage json --rcfile="$c/rc" --show-contexts -o "$c/py.json") > "$c/log" 2>&1 < /dev/null \
      && mappy "$abs" "$c/py.json" "${ts[@]}" > "$c/pairs" ;;
    go|rust|ruby) sec=$SECONDS; mapcollect "$1" "$lang" "$c" > "$c/pairs" 2> "$c/err" || { echo "conveyor: test map: not made again: $(cat "$c/err")"; rm -rf "$c"; return 0; }
      sec=$((SECONDS - sec)) ;;
  esac
  if [ -s "$c/pairs" ] && mapwrite "$1" "$c/pairs" "$lang" "$sec"; then
    jq -r '"conveyor: test map: made again from the whole run'\''s coverage: \(.sources | length) source files, \(.tests | length) test files"' "$(mappath)"
  else echo "conveyor: test map: not made again: the whole run's coverage mapped no test file"; fi
  rm -rf "$c"
}
# The map a card's change in <worktree> is read against (testsel()), as {by, sources: {<source>: [<test file>]}, shared:
# [<source>], age}: none (no output) with test.map off, or no made map. by is "map"; age is how many commits the made
# map is behind the worktree's HEAD (null for a map of the project's own). A source is shared when more than half the
# mapped tests touch it (a setup, config or helper file most tests read): its change runs the whole suite. A map of the
# project's own is a JSON object {"<source>": ["<test file>", ...]}, or lines of areas as .conveyor/engine-areas.json
# holds them: {"area": <name>, "file": <source>}, {"area": <name>, "test": <test file>} (a name with no / is the tracked
# test file of that name), {"area": <name>, "tests": "all"} (every source of the area is shared), {"area": <name>,
# "why": <text>} and {"outside": <path>} (a file no area needs). A map that cannot be read, a line of none of these
# kinds, or a test it names that is no tracked test file, fails it (exit 1, the reason on stdout).
mapread() { # <worktree>
  local m f out age=null sha
  packget test.map m || { echo "the pack's test.map could not be read"; return 1; }
  case $m in off) return 0 ;; '') f=$(mappath); [ -s "$f" ] || return 0 ;; *) f=$1/$m ;; esac
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
