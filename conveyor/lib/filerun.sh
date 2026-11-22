#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The built-in runner of one test file (#351): the command a card gives each of its test files when the pack sets no
# test.fileCommand (ownrunner(), lib/testlist.sh). `filerun.sh [args] <file>`, in the checkout, runs <file> (a path
# from the checkout) alone with the language's own runner, from the package that holds it: the nearest folder, from
# the file's own up to the checkout, with the manifest the runner reads. In a workspace or monorepo, so, each file runs
# from its own package. [args] (the pack's test.report.args) go to the runner right after its own words (to a
# JavaScript runner, with npm's `--` before them left out).
#   .js .mjs .cjs .jsx .ts .mts .cts .tsx  under a package.json: `npx --no vitest run <absolute path> --exclude
#                     **/<file name>?*` (not a file whose name goes on past it) when that
#                     package or the checkout's lists vitest, else `npx --no jest --runTestsByPath <path>` for jest,
#                     else `bun test ./<path>` with a bun.lock or bun.lockb there, else `node --test <path>`
#   .py               under pyproject.toml, setup.py, setup.cfg, pytest.ini or tox.ini: `pytest --tb=native <path>`
#   *_test.go         under go.mod: `go test -count=1 ./<the file's folder>`, its package only
#   tests/<name>.rs   of a crate (Cargo.toml): `cargo test --test <name>`, that test target only
#   *_spec.rb         under a Gemfile or .rspec: `bundle exec rspec <path>` (with a Gemfile), else `rspec <path>`
#   src/<set>/java, kotlin or groovy/<package path>/<class>.java .kt .groovy  under build.gradle or build.gradle.kts:
#                     `gradle test --tests <package>.<class>`, else under pom.xml: `mvn test -Dtest=<package>.<class>`,
#                     each through its wrapper (gradlew, mvnw) when the nearest folder up holds one
#   .cs               under a .csproj: `dotnet test --filter FullyQualifiedName~<namespace>.<class>.`, the class the
#                     file's name, in the first namespace it names; it also runs a class whose full name ends with it
#   Tests/<target>/.../<class>.swift  under Package.swift: `swift test --filter ^(<target>\.<class>)/`
#   *Test.php         under phpunit.xml, phpunit.xml.dist or composer.json: `phpunit <path>` (vendor/bin/phpunit when
#                     the project has it)
#   *_test.exs        under mix.exs (in an umbrella, the app's own): `mix test <path>`
#   .c .cc .cpp .cxx  under a folder whose build/ holds CTestTestfile.cmake (a CMake build): `ctest --no-tests=error
#                     -R ^(<the file's name, its extension left out>)$` in that build folder
#   *_test.dart       under pubspec.yaml: `flutter test <path>` when it names the flutter sdk, else `dart test <path>`
# The cases the run's list (CONVEYOR_TEST_RERUN) names of the file in `fail<TAB><file><TAB><case>` lines, unless one
# such line names the file with no case, are the run's filter. A filter runs the cases each runner below matches to
# it, so a name that is no exact case name of the file runs none, unless that runner also matches part of a name:
# node --test, vitest, jest and bun: -t or --test-name-pattern `(^| )(<cases>)$`, as they match a case's name with its
# suites' names before it, and a failed case is named alone (testfails()), so it also runs a case whose name ends with
# a space and one of <cases>; pytest: the node ids <path>::<case>, each that case only; go: -run `^(<cases>)$` and
# cargo: --exact <case>..., each the whole name; rspec: -e <case> each, which runs every case whose name holds it;
# gradle: --tests <class>.<case> each and mvn: -Dtest=<class>#<case>+..., each that method; dotnet:
# FullyQualifiedName=<class>.<case>|..., each the whole name (a real dotnet test may still exit 0 when it matches
# none); swift: --filter ^(<target>\.<class>)/(<cases>)$; phpunit: --filter /::(<cases>)( with data set .*)?$/, each a
# case of the file's class, with any data set; mix: --only "test:test <case>" each, the whole name; ctest: -R
# ^(<cases>)$, each a test of the build named whole (--no-tests=error: one that matches none fails); dart: --name
# `(^| )(<cases>)$`, as for the JavaScript runners, its groups' names before a case's. A
# path that is no file, and a file with no runner here, run nothing and fail (exit 2), the reason on stderr.
# `filerun.sh --which <file>` runs nothing: it prints the command, as `<folder><TAB><word>...`, or the reason there is
# none (exit 1).
set -u
which=
[ "${1:-}" != --which ] || { which=1; shift; }
[ $# != 0 ] || { echo "filerun: no test file given" >&2; exit 2; }
f=${!#}; f=${f#./}; extra=("${@:1:$#-1}")
# No runner for <file>: <why>.
none() {
  if [ -n "$which" ]; then printf '%s\n' "$1"; exit 1; fi
  echo "filerun: $f: $1" >&2; exit 2
}
[ -n "$f" ] && [ -f "$f" ] || none "no such test file"
# The nearest folder, from the file's own up to the checkout's (`.`), that holds one of <name>...
near() { # <name>...
  local d=$f n x
  while :; do
    case $d in */*) d=${d%/*} ;; *) d=. ;; esac
    # A <name> may be a pattern (*.csproj): unquoted, it gives the files it matches, or itself, which then is no file.
    for n; do for x in "$d"/$n; do [ ! -e "$x" ] || { printf '%s\n' "$d"; return 0; }; done; done
    [ "$d" != . ] || return 1
  done
}
# Whether package.json in <folder> lists the package <name> as a dependency.
dep() { # <folder> <name>
  jq -e --arg n "$2" '[.dependencies, .devDependencies] | any(objects | has($n))' "$1/package.json" >/dev/null 2>&1
}
# <cases> as one regular expression that matches each of them whole, its special characters escaped.
whole() { # <case>...
  local c s='' x
  for c; do x=$(printf '%s' "$c" | sed 's/[][\\.*^$+?(){}|]/\\&/g'); s+=${s:+|}$x; done
  printf '^(%s)$' "$s"
}
# The path of <name>, a runner's wrapper script, as the nearest folder that holds it gives it, from any folder.
wrapper() { # <name>
  local w
  w=$(near "$1") || return 1
  if [ "$w" = . ]; then printf '%s/%s\n' "$PWD" "$1"; else printf '%s/%s/%s\n' "$PWD" "$w" "$1"; fi
}
cs=()
if [ -s "${CONVEYOR_TEST_RERUN:-}" ] && ! awk -F'\t' -v f="$f" '$1 == "fail" && $2 == f && $3 == "" { e = 1 } END { exit !e }' "$CONVEYOR_TEST_RERUN"; then
  mapfile -t cs < <(awk -F'\t' -v f="$f" '$1 == "fail" && $2 == f && $3 != "" && !s[$3]++ { print $3 }' "$CONVEYOR_TEST_RERUN")
fi
b=() t=()
case $f in
  *.js|*.mjs|*.cjs|*.jsx|*.ts|*.mts|*.cts|*.tsx)
    d=$(near package.json) || none "no package.json holds it"
    r=${f#"$d"/}
    # The pack's report args are written for its test command, after npm's `--` when that runs an npm script
    # (reportguess(), lib/setup.sh). The runner here runs with no npm, so that `--` is left out: jest would take the
    # words after it as no options, and vitest would get no file to run.
    [ "${extra[0]:-}" != -- ] || extra=("${extra[@]:1}")
    if dep "$d" vitest || dep . vitest; then
      # vitest reads the path as a filter on the paths of its files: b.test.ts would also run b.test.tsx. So the files
      # whose name goes on past this one's are left out (--exclude, the name's glob characters escaped).
      x=$(printf '%s' "${f##*/}" | sed 's/[][\\*?(){}!+@|]/\\&/g')
      b=(npx --no vitest run); t=("$PWD/$f" --exclude "**/$x?*")
    elif dep "$d" jest || dep . jest; then b=(npx --no jest); t=(--runTestsByPath "$r")
    elif [ -e "$d/bun.lock" ] || [ -e "$d/bun.lockb" ] || [ -e bun.lock ] || [ -e bun.lockb ]; then b=(bun test); t=("./$r")
    else b=(node --test); t=("$r"); fi
    # These runners match a case's whole name, its suites' names before it: a case named alone matches at its end.
    if [ ${#cs[@]} = 0 ]; then :; else x=$(whole "${cs[@]}"); x="(^| )${x#^}"
      if [ "${b[0]}" = node ]; then t=("--test-name-pattern=$x" "${t[@]}"); else t+=(-t "$x"); fi; fi ;;
  *.py)
    d=$(near pyproject.toml setup.py setup.cfg pytest.ini tox.ini) || none "no pyproject.toml, setup.py, setup.cfg, pytest.ini or tox.ini holds it"
    # --tb=native: Python's own traceback (`File "<absolute path>", line <n>`), the frames testfails() reads a
    # failure's place from (lib/failat.sh PYFRAMERX); pytest's default form names it only from the package's folder.
    r=${f#"$d"/}; b=(pytest --tb=native)
    if [ ${#cs[@]} = 0 ]; then t=("$r"); else for c in "${cs[@]}"; do t+=("$r::$c"); done; fi ;;
  *_test.go)
    d=$(near go.mod) || none "no go.mod holds it"
    p=.; case $f in */*) p=${f%/*} ;; esac
    if [ "$p" = "$d" ]; then p=.; elif [ "$d" != . ]; then p=./${p#"$d"/}; else p=./$p; fi
    b=(go test -count=1); [ ${#cs[@]} = 0 ] || t=(-run "$(whole "${cs[@]}")"); t+=("$p") ;;
  *.rs)
    d=$(near Cargo.toml) || none "no Cargo.toml holds it"
    r=${f#"$d"/}
    [[ $r =~ ^tests/([^/]+)\.rs$ ]] || none "cargo test runs test targets, and it is no tests/<name>.rs file of its crate"
    b=(cargo test); t=(--test "${BASH_REMATCH[1]}"); [ ${#cs[@]} = 0 ] || t+=(-- --exact "${cs[@]}") ;;
  *_spec.rb)
    d=$(near Gemfile .rspec) || none "no Gemfile or .rspec holds it"
    r=${f#"$d"/}; b=(rspec); [ ! -e "$d/Gemfile" ] || b=(bundle exec rspec)
    for c in "${cs[@]}"; do t+=(-e "$c"); done; t+=("$r") ;;
  *.java|*.kt|*.groovy)
    d=$(near build.gradle build.gradle.kts pom.xml) || none "no build.gradle, build.gradle.kts or pom.xml holds it"
    r=${f#"$d"/}
    [[ $r =~ ^src/[^/]+/(java|kotlin|groovy)/(.+)\.(java|kt|groovy)$ ]] \
      || none "Gradle and Maven run test classes, and it is no src/<set>/java, kotlin or groovy/<package path>/<class> file of its project"
    k=${BASH_REMATCH[2]//\//.}
    if [ -e "$d/build.gradle" ] || [ -e "$d/build.gradle.kts" ]; then
      b=(gradle); x=$(wrapper gradlew) && b=("$x"); b+=(test)
      if [ ${#cs[@]} = 0 ]; then t=(--tests "$k"); else for c in "${cs[@]}"; do t+=(--tests "$k.$c"); done; fi
    else
      b=(mvn); x=$(wrapper mvnw) && b=("$x"); b+=(test)
      if [ ${#cs[@]} = 0 ]; then t=("-Dtest=$k"); else t=("-Dtest=$k#$(IFS=+; printf '%s' "${cs[*]}")"); fi
    fi ;;
  *.cs)
    d=$(near '*.csproj') || none "no .csproj file holds it"
    # The test class: the file's name, in the namespace the file names first (as `namespace <name>` or `<name>;`).
    k=${f##*/}; k=${k%.cs}; x=$(sed -nE 's/^[[:space:]]*namespace[[:space:]]+([A-Za-z0-9_.]+).*/\1/p' "$f" | head -n 1)
    k=${x:+$x.}$k; b=(dotnet test)
    # The filter's special characters, each escaped with a backslash.
    esc() { printf '%s' "$1" | sed 's/[\\()&|=!~]/\\&/g'; }
    if [ ${#cs[@]} = 0 ]; then x="FullyQualifiedName~$(esc "$k.")"
    else x=; for c in "${cs[@]}"; do x+=${x:+|}FullyQualifiedName=$(esc "$k.$c"); done; fi
    t=(--filter "$x") ;;
  *.swift)
    d=$(near Package.swift) || none "no Package.swift holds it"
    r=${f#"$d"/}
    [[ $r =~ ^Tests/([^/]+)/(.+/)?([^/]+)\.swift$ ]] || none "swift test runs test targets, and it is no Tests/<target>/ file of its package"
    # swift test matches its filter to `<target>.<class>/<case>`; the class is the file's name.
    x=$(whole "${BASH_REMATCH[1]}.${BASH_REMATCH[3]}"); x="${x%)\$})/"
    if [ ${#cs[@]} = 0 ]; then t=(--filter "$x"); else c=$(whole "${cs[@]}"); t=(--filter "$x${c#^}"); fi
    b=(swift test) ;;
  *Test.php)
    d=$(near phpunit.xml phpunit.xml.dist composer.json) || none "no phpunit.xml, phpunit.xml.dist or composer.json holds it"
    r=${f#"$d"/}; b=(phpunit); [ ! -x "$d/vendor/bin/phpunit" ] || b=(vendor/bin/phpunit)
    # phpunit matches its filter to `<class>::<case>`, with ` with data set <name>` after it for a case of a data provider.
    if [ ${#cs[@]} != 0 ]; then x=$(whole "${cs[@]}"); x=${x#^}; x=${x%\$}; t=(--filter "/::${x//\//\\/}( with data set .*)?\$/"); fi
    t+=("$r") ;;
  *_test.exs)
    d=$(near mix.exs) || none "no mix.exs holds it"
    r=${f#"$d"/}; b=(mix test)
    for c in "${cs[@]}"; do t+=(--only "test:test $c"); done; t+=("$r") ;;
  *.c|*.cc|*.cpp|*.cxx)
    d=$(near build/CTestTestfile.cmake) || none "no CMake build folder (build/CTestTestfile.cmake) holds it, so ctest has no tests to run"
    if [ "$d" = . ]; then d=build; else d=$d/build; fi
    x=${f##*/}; x=${x%.*}; b=(ctest --no-tests=error)
    if [ ${#cs[@]} = 0 ]; then t=(-R "$(whole "$x")"); else t=(-R "$(whole "${cs[@]}")"); fi ;;
  *_test.dart)
    d=$(near pubspec.yaml) || none "no pubspec.yaml holds it"
    r=${f#"$d"/}; b=(dart test); ! grep -Eq '^[[:space:]]+sdk:[[:space:]]*flutter' "$d/pubspec.yaml" || b=(flutter test)
    if [ ${#cs[@]} != 0 ]; then x=$(whole "${cs[@]}"); t=(--name "(^| )${x#^}"); fi
    t+=("$r") ;;
  *) none "it has no runner for a file of this kind" ;;
esac
# The pack's report args go right after the runner's own words, before the file and the filter.
a=("${b[@]}" "${extra[@]}" "${t[@]}")
if [ -n "$which" ]; then printf '%s' "$d"; printf '\t%s' "${a[@]}"; printf '\n'; exit 0; fi
# node --test exits 0 when its filter matches no case of the file: its summary counts no test, or it names the file
# itself as the one test that ran. In a loop's run (CONVEYOR_TEST_LOG), that writes the record {file} with no record
# of a case in results/ of the log folder, so the loop reads the file as one whose filter ran no case (testrun.sh
# nocases()), not as a pass.
if [ "${b[0]}" = node ] && [ ${#cs[@]} != 0 ] && [ -d "${CONVEYOR_TEST_LOG:-}" ]; then
  o=$(mktemp) || exit 2
  (cd "$d" && exec "${a[@]}") 2>&1 | tee "$o"; x=${PIPESTATUS[0]}
  [ "$x" != 0 ] || ! awk -v r="$r" '$0 == "# tests 0" || $0 == "ℹ tests 0" || $0 == "ok 1 - " r || index($0, "✔ " r " (") == 1 { z = 1 } END { exit !z }' "$o" \
    || { mkdir -p "$CONVEYOR_TEST_LOG/results" && jq -cn --arg f "${CONVEYOR_TEST_FILE:-$f}" '{file: $f}' > "$CONVEYOR_TEST_LOG/results/filerun.$$"; }
  rm -f "$o"; exit "$x"
fi
cd "$d" && exec "${a[@]}"
