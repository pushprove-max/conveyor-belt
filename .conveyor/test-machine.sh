#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# What this repository's test suite needs on a bare Linux box: the machine a release's suite runs on when the rule in
# the control record is an ssh box or a Namespace devbox (docs/releases.md, Where the suite runs). Conveyor runs this
# script there as the box's user, which can use sudo, and runs it again only after the script changes. It works on the
# Namespace devbox image and on Ubuntu 24.04, and it is safe to run again: a tool that is there at its version stays.
# `conveyor.sh suite-machine check` reads the `# needs: <tool> [<version>]` lines below, and names each tool the
# box lacks. The tool is the command the suite runs; the version is for people.
#
# needs: node 24
# needs: npm
# needs: python3 3.14
# needs: pip
# needs: ruff 0.17.6
# needs: shellcheck 0.11.0
# needs: gh
# needs: sort (coreutils)
# needs: find (findutils)
# needs: grep
# needs: sed
# needs: gawk
# needs: diff (diffutils)
# needs: gzip
# needs: file
# needs: sqlite3 (sqlite)
# (tzdata has no command: it is installed with the packages below, and the suite's time zone cases read it.)
set -euo pipefail

SUDO=sudo
[ "$(id -u)" != 0 ] || SUDO=
# The first version number in the output of a command, empty when the command is not there.
ver() { "$@" 2> /dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1 || :; }
apt() { $SUDO env DEBIAN_FRONTEND=noninteractive apt-get "$@"; }

apt update -qq
apt install -y -qq curl ca-certificates xz-utils software-properties-common \
  coreutils findutils grep sed gawk diffutils gzip file sqlite3 tzdata gh

# node 24 and npm, from NodeSource.
case $(ver node --version) in
  24.*) ;;
  *) curl -fsSL https://deb.nodesource.com/setup_24.x | $SUDO bash - && apt install -y -qq nodejs ;;
esac

# python 3.14 with pip, from the deadsnakes PPA. Its python refuses pip outside a virtual environment, so pip and ruff
# live in one, /opt/conveyor-py, owned by the box's user, and python3, pip and ruff are links to it ahead of the
# system's in PATH: the system's own tools name /usr/bin/python3 and keep it.
if ! command -v python3.14 > /dev/null || ! python3.14 -c 'import ensurepip, venv' 2> /dev/null; then
  $SUDO add-apt-repository -y ppa:deadsnakes/ppa
  apt update -qq
  apt install -y -qq python3.14 python3.14-venv
fi
V=/opt/conveyor-py
if [ ! -x "$V/bin/pip" ]; then
  $SUDO mkdir -p "$V" && $SUDO chown "$(id -u):$(id -g)" "$V"
  python3.14 -m venv --clear "$V"
fi
# ruff 0.17.6.
[ "$(ver ruff --version)" = 0.17.6 ] || "$V/bin/pip" install -q ruff==0.17.6
for t in python3 pip ruff; do $SUDO ln -sf "$V/bin/$t" "/usr/local/bin/$t"; done

# The tool shellcheck at 0.11.0, from its GitHub release (the one in the distribution is older).
if [ "$(ver shellcheck --version)" != 0.11.0 ]; then
  d=$(mktemp -d)
  curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.$(uname -m).tar.xz" | tar -xJ -C "$d"
  $SUDO install -m 755 "$d/shellcheck-v0.11.0/shellcheck" /usr/local/bin/shellcheck
  rm -rf "$d"
fi

# git's name and address for the tests that commit, kept when the box has them.
git config --global user.name > /dev/null || git config --global user.name 'Conveyor Test'
git config --global user.email > /dev/null || git config --global user.email 'conveyor-test@example.com'

# The npm dependencies from the lock file, when the script runs in a checkout of the project (the box's run of it is
# before the checkout is made: there the pack's worktree.setup installs them in each checkout).
if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; fi
