#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The built-in runner of one test file (#351): the command a card gives each of its test files when the pack sets no
# test.fileCommand (ownrunner(), lib/testrun.sh). `filerun.sh [args] <file>`, in the checkout, runs <file> (a path
# from the checkout) alone with the language's own runner, from the package that holds it: the nearest folder, from
# the file's own up to the checkout, with the manifest the runner reads. In a workspace or monorepo, so, each file runs
# from its own package. [args] (the pack's test.report.args) go to the runner right after its own words (to a
# JavaScript runner, with npm's `--` before them left out).
#   .js .mjs .cjs .jsx .ts .mts .cts .tsx  under a package.json: `npx --no vitest run <absolute path>` when that
#                     package or the checkout's lists vitest, else `npx --no jest --runTestsByPath <path>` for jest,
#                     else `bun test ./<path>` with a bun.lock or bun.lockb there, else `node --test <path>`
#   .py               under pyproject.toml, setup.py, setup.cfg, pytest.ini or tox.ini: `pytest <path>`
#   *_test.go         under go.mod: `go test -count=1 ./<the file's folder>`, its package only
#   tests/<name>.rs   of a crate (Cargo.toml): `cargo test --test <name>`, that test target only
#   *_spec.rb         under a Gemfile or .rspec: `bundle exec rspec <path>` (with a Gemfile), else `rspec <path>`
# The cases the run's list (CONVEYOR_TEST_RERUN) names of the file in `fail<TAB><file><TAB><case>` lines, unless one
# such line names the file with no case, are the run's filter. A filter runs the cases each runner below matches to
# it, so a name that is no exact case name of the file runs none, unless that runner also matches part of a name:
# node --test, vitest, jest and bun: -t or --test-name-pattern `(^| )(<cases>)$`, as they match a case's name with its
# suites' names before it, and a failed case is named alone (testfails()), so it also runs a case whose name ends with
# a space and one of <cases>; pytest: the node ids <path>::<case>, each that case only; go: -run `^(<cases>)$` and
# cargo: --exact <case>..., each the whole name; rspec: -e <case> each, which runs every case whose name holds it. A
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
  local d=$f n
  while :; do
    case $d in */*) d=${d%/*} ;; *) d=. ;; esac
    for n; do [ ! -e "$d/$n" ] || { printf '%s\n' "$d"; return 0; }; done
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
    if dep "$d" vitest || dep . vitest; then b=(npx --no vitest run); t=("$PWD/$f")
    elif dep "$d" jest || dep . jest; then b=(npx --no jest); t=(--runTestsByPath "$r")
    elif [ -e "$d/bun.lock" ] || [ -e "$d/bun.lockb" ] || [ -e bun.lock ] || [ -e bun.lockb ]; then b=(bun test); t=("./$r")
    else b=(node --test); t=("$r"); fi
    # These runners match a case's whole name, its suites' names before it: a case named alone matches at its end.
    if [ ${#cs[@]} = 0 ]; then :; else x=$(whole "${cs[@]}"); x="(^| )${x#^}"
      if [ "${b[0]}" = node ]; then t=("--test-name-pattern=$x" "${t[@]}"); else t+=(-t "$x"); fi; fi ;;
  *.py)
    d=$(near pyproject.toml setup.py setup.cfg pytest.ini tox.ini) || none "no pyproject.toml, setup.py, setup.cfg, pytest.ini or tox.ini holds it"
    r=${f#"$d"/}; b=(pytest)
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
  *) none "it has no runner for a file of this kind" ;;
esac
# The pack's report args go right after the runner's own words, before the file and the filter.
a=("${b[@]}" "${extra[@]}" "${t[@]}")
if [ -n "$which" ]; then printf '%s' "$d"; printf '\t%s' "${a[@]}"; printf '\n'; exit 0; fi
cd "$d" && exec "${a[@]}"
