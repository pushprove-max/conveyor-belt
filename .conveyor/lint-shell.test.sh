#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The pack's shellcheck lint command (lint-shell.sh): its exit is what the engine's lint check reads (0 pass, 1
# findings, 127 with `lint: missing shellcheck` skipped, any other end an execution error), so a wrong exit makes a
# card's shellcheck warning pass, or a broken run look like a pass or a finding.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; bad=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); bad=1; echo "not ok $n - $1"; }
cd "$T" || exit 1
printf '%s\n' '#!/usr/bin/env bash' 'echo $@' > warn.sh
# No #! line: read as anything but bash, shellcheck finds SC2148 (shell unknown) on line 1.
printf '%s\n' 'echo "$1"' '[[ -n $1 ]] && echo set' > nobang.sh
run() { rc=0; out=$(bash "$HERE/lint-shell.sh" "$@" 2>&1) || rc=$?; }

# Bug: a file with no #! line (the engine's sourced files) failed on SC2148 or was read as sh.
run nobang.sh
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a file with no #! line is read as bash" || no "no #!: exit $rc: $out"

# Bug: a card's new warning passed the lint, or printed in a form the engine does not read as a finding (so the card
# got no lint fix before its review). The engine's own readers (lib/lint.sh) read the output here.
run warn.sh nobang.sh
printf '%s\n' "$out" > out; printf 'warn.sh\0nobang.sh\0' > paths
# shellcheck source=/dev/null
. "$HERE/../conveyor/lib/lint.sh"
found=$(lintfindings out paths | jq -sc 'map([.file, .line])')
[ "$rc" = 1 ] && [[ $out == *SC2068* ]] && [ "$found" = '[["warn.sh",2]]' ] && [ "$(lintresult "$rc" out 1 '')" = findings ] \
  && ok "a warning is a finding the engine reads, exit 1" || no "warning: exit $rc, engine read $found: $out"

# Bug: shellcheck that could not read a file (exit 2) gave exit 1, read as findings, or a pass when the other group
# had a finding; any such end must be 2 or more, an execution error.
run warn.sh gone.sh
[ "$rc" -ge 2 ] && [ "$rc" != 127 ] && ok "a shellcheck failure that is not a finding exits 2 or more" || no "missing file: exit $rc: $out"

# Bug: with no shellcheck, the lint failed as an execution error in place of being skipped.
mkdir bin; for t in bash head; do ln -s "$(command -v "$t")" bin/; done
rc=0; out=$(PATH=$T/bin bash "$HERE/lint-shell.sh" warn.sh 2>&1) || rc=$?
[ "$rc" = 127 ] && [ "$out" = "lint: missing shellcheck" ] && ok "no shellcheck: lint: missing shellcheck, exit 127" || no "no shellcheck: exit $rc: $out"

echo "1..$n"; exit $bad
