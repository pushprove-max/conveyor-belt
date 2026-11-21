#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the start-up allowance of each file a split adds (splitstart()), measured for each runner the engine
# can run a file of with no case selected, or the pack's test.splitAllowance with the reason it was not measured.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug these catch (#191): the allowance fell back to the pack's 1 CPU s guess instead of being measured, so an honest
# split was refused. Each case gives splitstart() a fixture runner whose file costs a known start-up, and wants an
# allowance within 20% of it.
# A fixture runner on PATH, <name>, in $T/$CASE/bin: its start-up takes <start> CPU s; given any arguments but
# <the arguments of a run with no case>, it also runs its case, one, for 1 CPU s more and says so. It exits <exit>.
ssrunner() { # <name> <start> <the arguments of a run with no case> [exit]
  mkdir -p "$T/$CASE/bin" "$T/$CASE/wt"
  # shellcheck disable=SC2016 # the runner's own script, expanded when it runs
  printf '%s\n' '#!/usr/bin/env bash' \
    'burn() { python3 -c '"'"'import sys, time' 's = time.process_time()' 'while time.process_time() - s < float(sys.argv[1]): pass'"'"' "$1"; }' \
    "burn $2" "[ \"\$*\" = $(printf %q "$3") ] || { burn 1; echo 'ok one'; }" "exit ${4:-0}" > "$T/$CASE/bin/$1"
  chmod +x "$T/$CASE/bin/$1"
}
# splitstart() on <file> of $T/$CASE/wt with <test command> and a test.splitAllowance of 1, its fixture runner first on
# PATH; its line in $SS.
ssrun() { # <file> <test command>
  # shellcheck disable=SC2034 # HERE is read by splitstart(), for tools/testtime.sh
  SS=$(eval "$(sed -n '/^NOCASE=/p; /^splitstart() {/,/^}/p' "$SRC/lib/speedproof.sh"; sed -n '/^testrunner() {/,/^}/p' "$SRC/lib/issues.sh")"
    HERE=$SRC; PATH=$T/$CASE/bin:$PATH; splitstart "$T/$CASE/wt" "$1" "$2" 1 'one')
}
# ssnear <want CPU s> <file>: $SS is the allowance measured on <file>, within 20% of <want>.
ssnear() {
  if [ "${SS#*$'\t'}" != "measured: a run of $2 with no case" ] || ! awk -v c="${SS%%$'\t'*}" -v w="$1" 'BEGIN { exit !(c >= w * 0.8 && c <= w * 1.2) }'; then
    fail "the allowance on $2 is not measured within 20% of its start-up of $1 CPU s: $SS"
  fi
}

# node --test, the real runner: the file's start-up (its top level) takes 1 CPU s and node's own about 0.1; its case 2.
t_ssnode() {
  mkdir -p "$T/$CASE/wt"
  cat > "$T/$CASE/wt/a.test.mjs" <<'EOF'
import { test } from 'node:test';
const burn = (s) => { const t = process.cpuUsage(); for (;;) { const u = process.cpuUsage(t); if ((u.user + u.system) / 1e6 >= s) break; } };
burn(1);
test('one', () => burn(2));
EOF
  ssrun a.test.mjs 'node --test'
  ssnear 1.1 a.test.mjs
}

# pytest, -k with no case; pytest's exit 5 (no case ran) is the run with no case's own.
t_sspytest() {
  ssrunner pytest 0.5 '-q -k conveyor_no_case tests/test_a.py' 5
  ssrun tests/test_a.py 'pytest -q'
  ssnear 0.5 tests/test_a.py
}

# go test, on the file's package, -run with no case.
t_ssgo() {
  ssrunner go 0.5 'test -count=1 -run ^conveyor-no-case$ ./pkg'
  ssrun pkg/a_test.go 'go test ./...'
  ssnear 0.5 pkg/a_test.go
}

# cargo test, on the file's test target, with a name filter no case has.
t_sscargo() {
  ssrunner cargo 0.5 'test --test a -- --exact conveyor-no-case'
  ssrun tests/a.rs 'cargo test'
  ssnear 0.5 tests/a.rs
}

# rspec, -e with no case, as the command starts it (bundle exec).
t_ssrspec() {
  ssrunner bundle 0.5 'exec rspec -e conveyor-no-case spec/a_spec.rb'
  ssrun spec/a_spec.rb 'bundle exec rspec'
  ssnear 0.5 spec/a_spec.rb
}

# Bug it catches: a run that cannot be measured is taken at the pack's value with no word of why. A file cargo test
# cannot run alone, and a run with no case that fails, each say why in the reason.
t_ssnotmeasured() {
  ssrun src/a.rs 'cargo test'
  [ "$SS" = "1"$'\t'"the pack's test.splitAllowance: cargo test runs test targets, and src/a.rs is no tests/<name>.rs file" ] \
    || fail "a file cargo test cannot run alone did not give the pack's value with why: $SS"
  ssrunner rspec 0.1 '-e conveyor-no-case spec/a_spec.rb' 2
  ssrun spec/a_spec.rb 'rspec'
  [ "$SS" = "1"$'\t'"the pack's test.splitAllowance: the run of spec/a_spec.rb with no case (rspec) failed (exit 2)" ] \
    || fail "a run with no case that failed did not give the pack's value with why: $SS"
}
