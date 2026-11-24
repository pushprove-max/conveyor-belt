#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The plugin's SessionStart hook for ast-grep, hooks/ast-grep.sh, run as the command hooks/hooks.json registers. A
# stand-in for the ast-grep binary setup installs in the Board's virtualenv makes ast-grep installed.
# Bugs: the hook adds its line in a project with no file ast-grep parses, or with ast-grep not installed (or fails
# there, which Claude Code shows the user), or adds none in a project with bash, Python or TypeScript files, or leaves
# out a language ast-grep parses, such as Markdown, JSON or YAML.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok [ast-grep hook]: $1"; }
bad() { echo "FAIL [ast-grep hook]: $1" >&2; fails=$((fails + 1)); }

# ast-grep installed: its binary where setup puts it ($XDG_DATA_HOME/conveyor/board-venv); not installed: none there.
ON=$T/on; OFF=$T/off
mkdir -p "$ON/conveyor/board-venv/bin" "$OFF" && printf '#!/bin/sh\necho ast-grep 0.0.0\n' > "$ON/conveyor/board-venv/bin/ast-grep" \
  && chmod +x "$ON/conveyor/board-venv/bin/ast-grep" || exit 1
# repo <dir> <file>...: a git checkout whose tracked files are these.
repo() {
  local d=$1; shift; git init -q "$d" && (cd "$d" && for f in "$@"; do mkdir -p "$(dirname "$f")" && : > "$f"; done && git add -A) || exit 1
}
repo "$T/code" tools/run.sh lib/app.py web/main.ts README.md data.json config.yaml
repo "$T/plain" notes.txt .env LICENSE build.sh.in
CMD=$(jq -r '.hooks.SessionStart[].hooks[].command | select(contains("ast-grep"))' "$ROOT/hooks/hooks.json")
[ -n "$CMD" ] || bad "hooks/hooks.json registers no ast-grep hook at SessionStart"
hook() { # <project> <XDG_DATA_HOME>: the registered command, run in the project as Claude Code runs it
  (cd "$1" && CLAUDE_PLUGIN_ROOT=$ROOT CLAUDE_PROJECT_DIR=$1 XDG_DATA_HOME=$2 bash -c "$CMD" 2> "$T/err" < /dev/null)
}

out=$(hook "$T/code" "$ON"); rc=$?
want="ast-grep is installed: a code search that matches syntax, not text. Call it as ast-grep run -p '<pattern>' -l <lang> [<path>...]. Languages in this project: bash, json, markdown, python, typescript, yaml."
if [ "$rc" = 0 ] && [ "$out" = "$want" ] && [ ! -s "$T/err" ]; then ok "a project with bash, Python, TS, Markdown, JSON and YAML files gets the line, with each language"
else bad "hook in a project of tools/run.sh lib/app.py web/main.ts README.md data.json config.yaml, ast-grep installed: exit $rc, said [$out], stderr [$(cat "$T/err")], want [$want]"; fi

out=$(hook "$T/plain" "$ON"); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ] && [ ! -s "$T/err" ]; then ok "a project with no file ast-grep parses gets no line"
else bad "hook in a project of notes.txt .env LICENSE build.sh.in, ast-grep installed: exit $rc, said [$out], stderr [$(cat "$T/err")], want nothing"; fi

out=$(hook "$T/code" "$OFF"); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ] && [ ! -s "$T/err" ]; then ok "with ast-grep not installed the hook adds no line and does not fail"
else bad "hook in the code project, no ast-grep under $OFF: exit $rc, said [$out], stderr [$(cat "$T/err")], want nothing"; fi

[ "$fails" = 0 ] || { echo "FAIL [ast-grep hook]: $fails check(s) failed" >&2; exit 1; }
