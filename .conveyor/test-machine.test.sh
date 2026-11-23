#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-machine.sh's ruff step. Bug it catches: with ruff 0.17.6 already first on PATH the step skipped the install into
# the virtual environment, then linked /usr/local/bin/ruff to the environment's ruff, which a fresh environment does
# not have, so ruff was a broken link on the box. The step is cut out of the script and run alone (the script as a
# whole installs packages with apt and sudo): its ln writes into a scratch folder, in place of /usr/local/bin.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
no() { echo "not ok - $1" >&2; fails=1; }

step=$(sed -n '/ruff==0[.]17[.]6/,/^for t in python3 pip ruff/p' "$HERE/test-machine.sh")
[ -n "$step" ] && grep -q 'ln -sf' <<<"$step" || { echo "not ok - the ruff step of test-machine.sh was not found"; exit 1; }

# A fresh environment: pip only, whose install of ruff puts the tool in the environment's bin. A ruff 0.17.6 is
# first on PATH.
V=$T/venv; mkdir -p "$V/bin" "$T/path" "$T/usrbin"
printf '%s\n' '#!/bin/sh' 'printf "#!/bin/sh\necho ruff 0.17.6\n" > "$(dirname "$0")/ruff"; chmod +x "$(dirname "$0")/ruff"' > "$V/bin/pip"
printf '%s\n' '#!/bin/sh' 'echo ruff 0.17.6' > "$T/path/ruff"
chmod +x "$V/bin/pip" "$T/path/ruff"
out=$(PATH=$T/path:$PATH V=$V SUDO='' bash -c '
  ver() { "$@" 2> /dev/null | grep -oE "[0-9]+(\.[0-9]+)+" | head -n 1 || :; }
  ln() { command ln -sf "$2" "'"$T"'/usrbin/${2##*/}"; }
  '"$step" 2>&1) || no "the ruff step failed: $out"
got=$("$T/usrbin/ruff" --version 2>&1) && [ "$got" = "ruff 0.17.6" ] \
  || no "after the step with ruff 0.17.6 first on PATH and a fresh environment, the ruff link does not run ruff 0.17.6: $got"

[ "$fails" = 0 ] && echo "ok - the ruff step leaves a working ruff link in a fresh environment" || exit 1
