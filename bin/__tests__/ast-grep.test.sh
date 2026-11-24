#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# The plugin's bin/ast-grep, called by its bare name with bin/ on PATH, as Claude Code puts it on the Bash tool's PATH.
# A stand-in that records its arguments takes the place of the binary setup installs in the Board's virtualenv.
# Bugs: with no binary, the command fails with no word of how to install it, or exits 0 as if it searched; with the
# binary there, it runs another one, or not with the arguments it was given.
set -uo pipefail
BIN=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok [bin/ast-grep]: $1"; }
bad() { echo "FAIL [bin/ast-grep]: $1" >&2; fails=$((fails + 1)); }
ON=$T/on; OFF=$T/off; V=$ON/conveyor/board-venv/bin
mkdir -p "$V" "$OFF" && printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\necho stand-in ran\n' "$T" > "$V/ast-grep" && chmod +x "$V/ast-grep" || exit 1

out=$(cd "$T" && XDG_DATA_HOME=$OFF PATH=$BIN:$PATH ast-grep run -p 'x' 2>&1); rc=$?
if [ "$rc" = 127 ] && [ "$out" = "ast-grep: not installed; run /conveyor-belt:setup, which installs it" ]; then ok "with no binary it names the setup command and fails"
else bad "ast-grep run -p x, no binary under $OFF: exit $rc, said [$out]"; fi

out=$(cd "$T" && XDG_DATA_HOME=$ON PATH=$BIN:$PATH ast-grep run -p 'f($A)' -l python 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "stand-in ran" ] && [ "$(cat "$T/args" 2>/dev/null)" = "$(printf '%s\n' run -p 'f($A)' -l python)" ]; then ok "it runs the installed binary with its arguments"
else bad "ast-grep run -p 'f(\$A)' -l python: exit $rc, said [$out], binary given [$(cat "$T/args" 2>/dev/null)]"; fi

[ "$fails" = 0 ] || { echo "FAIL [bin/ast-grep]: $fails check(s) failed" >&2; exit 1; }
