#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases (#376, #377, #351 scenarios 11 and 12): Conveyor's own per-file runner (lib/filerun.sh), which a card's run
# gives each test file when the pack sets no test.fileCommand. Each case calls filerun.sh on a fixture project whose
# runner is a stub on PATH that records the folder it ran in and its arguments: no real toolchain is needed. Each
# fixture's package is in a folder of its own, as in a workspace or monorepo, so each case also shows the file run from
# its package. A filter of the run's list that names no case of the file (`conveyor-no-case`) reaches the runner as
# a filter of that name, never as a run of the whole file or suite: it runs only the cases the runner matches to it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The fixture project $T/$CASE/p (FRP, its real path) with the files <path>=<text>..., and a stub of each runner in
# $T/$CASE/bin: each adds `<runner> <the folder it ran in, from the project: /...>|<its arguments>` to $T/$CASE/got.
# A file whose <text> is `stub` is such a stub too, named as its path in the project (a project's own wrapper, as
# gradlew or vendor/bin/phpunit), so a run of the runner on PATH in its place is told apart from it.
frsetup() { # <path>=<text>...
  local r x
  mkdir -p "$T/$CASE/p" "$T/$CASE/bin" && FRP=$(cd "$T/$CASE/p" && pwd -P) || fail "the fixture could not be made"
  for r in npx bun node pytest go cargo rspec bundle gradle mvn dotnet swift phpunit mix ctest dart flutter; do frstub "$T/$CASE/bin/$r"; done
  for x; do
    mkdir -p "$FRP/$(dirname "${x%%=*}")" || fail "the folder of ${x%%=*} could not be made"
    if [ "${x#*=}" = stub ]; then frstub "$FRP/${x%%=*}" "${x%%=*}"; else printf '%s\n' "${x#*=}" > "$FRP/${x%%=*}" || fail "the fixture file ${x%%=*} could not be made"; fi
  done
}
frstub() { # <path> [name, by default the file's]
  local r=${2:-${1##*/}}
  printf '%s\n' '#!/usr/bin/env bash' "d=\$(pwd -P); d=\${d#$(printf %q "$FRP")}; echo \"$r \${d:-/}|\$*\" >> $(printf %q "$T/$CASE/got")" > "$1" \
    && chmod +x "$1" || fail "the stub $r could not be made"
}
# filerun.sh on <file> in the fixture project, with the run's list holding <lines> (CONVEYOR_TEST_RERUN; none when
# empty) and the pack's report <args> before the file: what the stubs recorded in FRGOT, its exit in FRRC, its output
# in $T/$CASE/out.
fr() { # <file> [list lines] [args...]
  local l=''
  rm -f "$T/$CASE/got"; [ -z "${2:-}" ] || { printf '%s\n' "$2" > "$T/$CASE/rerun" && l=$T/$CASE/rerun; }
  (cd "$FRP" && PATH="$T/$CASE/bin:$PATH" CONVEYOR_TEST_RERUN=$l exec bash "$SRC/lib/filerun.sh" "${@:3}" "$1") > "$T/$CASE/out" 2>&1; FRRC=$?
  FRGOT=$(cat "$T/$CASE/got" 2>/dev/null)
}
# The run of <file> alone gives <whole>, and with a filter that names no case of it, <none>, each the line its stub
# recorded: one run, of that file (or package) only, from its package.
frcheck() { # <file> <whole> <none>
  fr "$1"; [ "$FRRC" = 0 ] && [ "$FRGOT" = "$2" ] || fail "$1 did not run alone from its package (exit $FRRC): got [$FRGOT], want [$2]: $(cat "$T/$CASE/out")"
  fr "$1" "$(printf 'fail\t%s\tconveyor-no-case' "$1")"
  [ "$FRRC" = 0 ] && [ "$FRGOT" = "$3" ] || fail "$1 with a filter that names no case did not give the runner a filter of that case (exit $FRRC): got [$FRGOT], want [$3]"
}

# Bug it catches: with no test.fileCommand, a Node test file in a workspace ran from the checkout (where its package's
# own setup is not read), ran with other files, or a filter that names nothing ran the whole file. A path that is no
# file runs nothing and fails, so a list that names a gone file never widens to a run of everything.
t_filerunnode() {
  frsetup 'package.json={"private": true, "workspaces": ["packages/*"]}' 'packages/web/package.json={"name": "web"}' 'packages/web/a.test.js=x' 'packages/web/ab.test.js=x'
  frcheck packages/web/a.test.js 'node /packages/web|--test a.test.js' 'node /packages/web|--test --test-name-pattern=(^| )(conveyor-no-case)$ a.test.js'
  # A failed case, as the run names it (its own name, with no suite): its pattern matches it whole, at the end of the
  # name the runner matches (its suites' names first), its special characters taken as text. Bug it catches: a case
  # under a suite matched nothing, so the run again of a failed case ran none and passed.
  fr packages/web/a.test.js "$(printf 'fail\tpackages/web/a.test.js\tadds (1+1)')"
  [ "$FRGOT" = 'node /packages/web|--test --test-name-pattern=(^| )(adds \(1\+1\))$ a.test.js' ] || fail "a failed case's filter is not its name whole, at the end: [$FRGOT]"
  fr packages/web/gone.test.js
  [ "$FRRC" = 2 ] && [ -z "$FRGOT" ] && grep -qxF 'filerun: packages/web/gone.test.js: no such test file' "$T/$CASE/out" \
    || fail "a path that is no file ran, or did not fail naming it (exit $FRRC): [$FRGOT] $(cat "$T/$CASE/out")"
}

# Bug it catches: a vitest package ran its file under node --test, or by a name vitest reads as part of a path (which
# runs every file whose path holds it). vitest is given the file's whole path.
t_filerunvitest() {
  frsetup 'packages/ui/package.json={"devDependencies": {"vitest": "1"}}' 'packages/ui/src/b.test.ts=x'
  frcheck packages/ui/src/b.test.ts "npx /packages/ui|--no vitest run $FRP/packages/ui/src/b.test.ts" \
    "npx /packages/ui|--no vitest run $FRP/packages/ui/src/b.test.ts -t (^| )(conveyor-no-case)\$"
}

# Bug it catches: a jest file of a workspace whose jest is listed at the checkout's root ran under node --test, or by a
# pattern jest matches against other paths too: --runTestsByPath runs that path only.
t_filerunjest() {
  frsetup 'package.json={"devDependencies": {"jest": "29"}}' 'packages/api/package.json={"name": "api"}' 'packages/api/c.test.js=x'
  frcheck packages/api/c.test.js 'npx /packages/api|--no jest --runTestsByPath c.test.js' \
    'npx /packages/api|--no jest --runTestsByPath c.test.js -t (^| )(conveyor-no-case)$'
  # The report args setup gives jest under an npm script (reportguess()) start with npm's `--`. Bug it catches (E1 of
  # #376's review): that `--` reached jest, which then read --runTestsByPath and -t as no options, so the run's filter
  # and its exact path were lost.
  fr packages/api/c.test.js '' -- --json --outputFile=r.json
  [ "$FRGOT" = 'npx /packages/api|--no jest --json --outputFile=r.json --runTestsByPath c.test.js' ] \
    || fail "npm's -- before the report args reached jest, or the args were lost (exit $FRRC): [$FRGOT]"
}

# Bug it catches: a bun project's file ran under node, or by a name bun reads as a filter (any path holding it): ./
# makes it a path.
t_filerunbun() {
  frsetup 'packages/b/package.json={"name": "b"}' 'packages/b/bun.lock=x' 'packages/b/d.test.ts=x'
  frcheck packages/b/d.test.ts 'bun /packages/b|test ./d.test.ts' 'bun /packages/b|test ./d.test.ts -t (^| )(conveyor-no-case)$'
}

# Bug it catches: a Python file ran from the checkout, outside its project, or a filter ran its whole file: the
# node id <file>::<case> names one case, and pytest runs nothing when there is no such case.
t_filerunpytest() {
  frsetup 'svc/pyproject.toml=x' 'svc/tests/test_x.py=x'
  frcheck svc/tests/test_x.py 'pytest /svc|tests/test_x.py' 'pytest /svc|tests/test_x.py::conveyor-no-case'
}

# Bug it catches: go test ran the whole module (./...) or from outside it: it runs the file's package only, from the
# module (go.mod), and a file at the module's top runs its package `.`.
t_filerungo() {
  frsetup 'mod/go.mod=module example.com/m' 'mod/pkg/x_test.go=x' 'mod/y_test.go=x'
  frcheck mod/pkg/x_test.go 'go /mod|test -count=1 ./pkg' 'go /mod|test -count=1 -run ^(conveyor-no-case)$ ./pkg'
  fr mod/y_test.go; [ "$FRGOT" = 'go /mod|test -count=1 .' ] || fail "a test file at the module's top did not run its package . (exit $FRRC): [$FRGOT]"
}

# Bug it catches: cargo test ran every test target, or from outside the crate of a workspace: it runs the file's test
# target only, from its crate; a .rs file that is no test target runs nothing and fails, saying why.
t_fileruncargo() {
  frsetup 'Cargo.toml=[workspace]' 'crates/c/Cargo.toml=[package]' 'crates/c/tests/e2e.rs=x' 'crates/c/src/lib.rs=x'
  frcheck crates/c/tests/e2e.rs 'cargo /crates/c|test --test e2e' 'cargo /crates/c|test --test e2e -- --exact conveyor-no-case'
  fr crates/c/src/lib.rs
  [ "$FRRC" = 2 ] && [ -z "$FRGOT" ] && grep -qxF 'filerun: crates/c/src/lib.rs: cargo test runs test targets, and it is no tests/<name>.rs file of its crate' "$T/$CASE/out" \
    || fail "a .rs file that is no test target ran, or did not fail saying why (exit $FRRC): [$FRGOT] $(cat "$T/$CASE/out")"
}

# Bug it catches: an RSpec file ran without its bundle, or from outside its app: with a Gemfile it runs through bundle
# exec from the app's folder.
t_filerunrspec() {
  frsetup 'app/Gemfile=x' 'app/spec/m_spec.rb=x'
  frcheck app/spec/m_spec.rb 'bundle /app|exec rspec spec/m_spec.rb' 'bundle /app|exec rspec -e conveyor-no-case spec/m_spec.rb'
}

# Bug it catches (#377): a Gradle test file had no runner (the card stopped), ran every test of the build, or ran
# with the gradle on PATH in place of the project's own wrapper: it runs its class only, through gradlew, from its
# project.
t_filerungradle() {
  frsetup 'settings.gradle=x' 'gradlew=stub' 'lib/build.gradle.kts=x' 'lib/src/test/java/com/example/FooTest.java=x'
  frcheck lib/src/test/java/com/example/FooTest.java 'gradlew /lib|test --tests com.example.FooTest' \
    'gradlew /lib|test --tests com.example.FooTest.conveyor-no-case'
}

# Bug it catches (#377): a Maven test file had no runner, or ran every test of the build: it runs its class only.
t_filerunmaven() {
  frsetup 'pom.xml=x' 'app/pom.xml=x' 'app/src/test/kotlin/com/example/BarTest.kt=x'
  frcheck app/src/test/kotlin/com/example/BarTest.kt 'mvn /app|test -Dtest=com.example.BarTest' \
    'mvn /app|test -Dtest=com.example.BarTest#conveyor-no-case'
}

# Bug it catches (#377): a C# test file had no runner, or ran every test of its project. A real dotnet test whose
# filter matches nothing can exit 0, so this checks the filter it is given, never the exit status: the whole name of
# the case, in the class the file is, in its file-scoped namespace.
t_filerundotnet() {
  frsetup 'tests/Api.Tests/Api.Tests.csproj=x' 'tests/Api.Tests/Unit/CalcTests.cs=namespace Api.Tests.Unit;'
  frcheck tests/Api.Tests/Unit/CalcTests.cs 'dotnet /tests/Api.Tests|test --filter FullyQualifiedName~Api.Tests.Unit.CalcTests.' \
    'dotnet /tests/Api.Tests|test --filter FullyQualifiedName=Api.Tests.Unit.CalcTests.conveyor-no-case'
}

# Bug it catches (#377): a Swift test file had no runner, or ran every test of its package: the filter names its
# target and class, the dot taken as text.
t_filerunswift() {
  frsetup 'pkg/Package.swift=x' 'pkg/Tests/CoreTests/MathTests.swift=x'
  frcheck pkg/Tests/CoreTests/MathTests.swift 'swift /pkg|test --filter ^(CoreTests\.MathTests)/' \
    'swift /pkg|test --filter ^(CoreTests\.MathTests)/(conveyor-no-case)$'
}

# Bug it catches (#377): a PHPUnit file had no runner, or ran with a phpunit other than the project's own
# (vendor/bin), or from outside its project.
t_filerunphpunit() {
  frsetup 'web/composer.json={}' 'web/vendor/bin/phpunit=stub' 'web/tests/UserTest.php=x'
  frcheck web/tests/UserTest.php 'web/vendor/bin/phpunit /web|tests/UserTest.php' \
    'web/vendor/bin/phpunit /web|--filter /::(conveyor-no-case)( with data set .*)?$/ tests/UserTest.php'
}

# Bug it catches (#377): an Elixir test file had no runner, or ran from the umbrella's top in place of its app.
t_filerunmix() {
  frsetup 'mix.exs=x' 'apps/core/mix.exs=x' 'apps/core/test/core_test.exs=x'
  frcheck apps/core/test/core_test.exs 'mix /apps/core|test test/core_test.exs' \
    'mix /apps/core|test --only test:test conveyor-no-case test/core_test.exs'
}

# Bug it catches (#377): a C++ test file had no runner, or ran every test of the build; ctest's own run of a filter
# that matches nothing passes, so --no-tests=error makes it fail. With no build folder it runs nothing and fails,
# saying why.
t_filerunctest() {
  frsetup 'CMakeLists.txt=x' 'build/CTestTestfile.cmake=x' 'tests/parse_test.cpp=x'
  frcheck tests/parse_test.cpp 'ctest /build|--no-tests=error -R ^(parse_test)$' 'ctest /build|--no-tests=error -R ^(conveyor-no-case)$'
  rm "$FRP/build/CTestTestfile.cmake" && fr tests/parse_test.cpp
  [ "$FRRC" = 2 ] && [ -z "$FRGOT" ] && grep -qF 'filerun: tests/parse_test.cpp: no CMake build folder' "$T/$CASE/out" \
    || fail "a C++ file with no build ran, or did not fail saying why (exit $FRRC): [$FRGOT] $(cat "$T/$CASE/out")"
}

# Bug it catches (#377): a Flutter package's test ran under dart test (which cannot load flutter), or a plain Dart
# package's under flutter test.
t_filerundart() {
  frsetup "app/pubspec.yaml=$(printf 'dependencies:\n  flutter:\n    sdk: flutter')" 'app/test/widget_test.dart=x' \
    'core/pubspec.yaml=name: core' 'core/test/a_test.dart=x'
  frcheck app/test/widget_test.dart 'flutter /app|test test/widget_test.dart' \
    'flutter /app|test --name (^| )(conveyor-no-case)$ test/widget_test.dart'
  fr core/test/a_test.dart; [ "$FRGOT" = 'dart /core|test test/a_test.dart' ] || fail "a Dart package's test did not run under dart test (exit $FRRC): [$FRGOT]"
}

# Bug it catches: the header of filerun.sh said a filter that names no case of the file runs none, while rspec -e
# (and the JavaScript runners' end match) also runs a case whose name only holds that name, so a reader trusted a
# narrower rerun than the one made. A text check, as a comment has no behaviour to run.
t_filerundoc() {
  local h
  h=$(sed -n '/^set -u$/q; s/^# \{0,1\}//p' "$SRC/lib/filerun.sh" | tr '\n' ' ') || fail "the header of filerun.sh could not be read"
  case $h in *"a filter that names no case of the file runs none"*) fail "the header still says a filter that names no case runs none" ;; esac
  case $h in *"unless that runner also matches part of a name"*) ;; *) fail "the header does not say that a runner that matches part of a name runs more" ;; esac
}
