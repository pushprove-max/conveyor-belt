#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The plugin's bin/cb-ast, the read-only ast-grep for a review. A stand-in that records its arguments takes the place
# of the binary setup installs in the Board's virtualenv, so a refusal shows the binary never ran.
# Bugs: cb-ast lets through an option that writes files (-U, --update-all, -i, --interactive, also inside a group of
# short options such as -Ul), the --custom-languages option that writes ast-grep's trust record, or a subcommand other
# than run and scan; or it refuses a plain run -p search.
set -uo pipefail
BIN=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok [cb-ast]: $1"; }
bad() { echo "FAIL [cb-ast]: $1" >&2; fails=$((fails + 1)); }
V=$T/data/conveyor/board-venv/bin
mkdir -p "$V" && printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\necho stand-in ran\n' "$T" > "$V/ast-grep" && chmod +x "$V/ast-grep" || exit 1
cbast() { (cd "$T" && XDG_DATA_HOME=$T/data "$BIN/cb-ast" "$@" 2>&1); }

refused() { # <arg>...: cb-ast refuses them in one line with exit 2, and the binary does not run
  local out rc; rm -f "$T/args"
  out=$(cbast "$@"); rc=$?
  if [ "$rc" = 2 ] && [[ $out == cb-ast:* && $out != *$'\n'* ]] && [ ! -e "$T/args" ]; then ok "refuses: cb-ast $*"
  else bad "cb-ast $*: exit $rc, said [$out], binary $([ -e "$T/args" ] && echo ran || echo 'did not run'); want a one-line refusal, exit 2"; fi
}
refused run -p 'x = $A' -r 'y = $A' -l python -U
refused run -p 'x = $A' -r 'y = $A' -l python --update-all
refused run -p 'x = $A' -r 'y = $A' -l python -i
refused run -p 'x = $A' -r 'y = $A' -l python --interactive
refused scan -U
refused scan --update-all
refused scan -i
refused scan --interactive
refused run -p 'x = $A' -r 'y = $A' -Ul python
refused run -p 'x' -l python --custom-languages trust
refused run -p 'x' -l python --custom-languages=revoke
refused new rule
refused -U run -p x
refused

rm -f "$T/args"
out=$(cbast run -p 'print($A)' -l python lib); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "stand-in ran" ] && [ "$(cat "$T/args" 2>/dev/null)" = "$(printf '%s\n' run -p 'print($A)' -l python lib)" ]; then ok "runs a plain run -p search"
else bad "cb-ast run -p 'print(\$A)' -l python lib: exit $rc, said [$out], binary given [$(cat "$T/args" 2>/dev/null)]"; fi

[ "$fails" = 0 ] || { echo "FAIL [cb-ast]: $fails check(s) failed" >&2; exit 1; }
