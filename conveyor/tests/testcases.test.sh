#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the case names the Tests snapshot gives each test file (TABLECASES in lib/testfiles.sh, from the case
# starts of the file's TESTEDIT_TABLE row). The .mjs files' names, from the snapshot itself, are in testfiles.test.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug it catches (O240): the cases of a pytest, Go or bats file were not named (null), so the Board's search missed
# them. TABLECASES names each by its row's case start: def test_x( and func TestAdd( by their word, @test by its quotes.
t_tfcasenames() {
  local d=$T/$CASE got; mkdir -p "$d" && printf 'def test_x():\n    pass\nasync def test_y(self):\ndef helper():\n' > "$d/test_a.py" \
    && printf 'func TestAdd(t *testing.T) {}\nfunc helper() {}\n' > "$d/a_test.go" && printf '@test "adds one" {\n  run x\n}\n' > "$d/a.bats" || fail "the files"
  got=$(cd "$d" && bash -c '. "$1/lib/testfiles.sh" 2>/dev/null; jq -cRn "$TESTEDIT_TABLE$TABLECASES" test_a.py a_test.go a.bats' _ "$SRC")
  [ "$got" = '{"test_a.py":["test_x","test_y"],"a_test.go":["TestAdd"],"a.bats":["adds one"]}' ] || fail "TABLECASES of a pytest, a Go and a bats file: $got"
}
