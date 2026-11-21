#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This pack's ruff lint command (.conveyor/project.json, lint; ruff.toml) run by the engine's own gate (lintrun and
# lintcheck, conveyor/lib/lint.sh) on a card's change in a fixture repository that holds this checkout's ruff.toml and
# dashboard_server.py. Bugs it catches: a card's unused import or a function it makes too complex lands unread; a card
# that only edits the signature of a function that was already too complex is given that old finding; a broken
# ruff.toml reads as a pass; a gate run fixes a Python file; with no ruff, the command is an execution error in
# place of `skipped: missing ruff`. The cases that need ruff are skipped when ruff is not on PATH (the Foreman puts
# it there); the case of a missing ruff always runs.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d); trap 'git -C "$T/main" worktree prune 2>/dev/null; rm -rf "$T"' EXIT
n=0; bad=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); bad=1; echo "not ok $n - $1"; }
R=$T/main W=$T/cards/c7
g() { git -C "$R" "$@"; }
# A function of <n> if statements: its complexity is n + 1. <sig> is its def line.
fn() { local i; echo "$1"; for ((i = 1; i <= $2; i++)); do printf '    if a == %s:\n        return %s\n' "$i" "$i"; done; echo '    return 0'; }

# Main: the test pack with this pack's ruff command and lint policy, ruff.toml, dashboard_server.py, and c.py with f
# under the complexity limit of 10 (complexity 9) and g over it (13).
mkdir -p "$R/.conveyor" "$R/.claude/scripts" "$T/cards" && g init -q -b main && g config user.email t@example.com && g config user.name t || exit 1
jq --slurpfile p "$ROOT/.conveyor/project.json" '.lint = ($p[0].lint | .commands |= map(select(.run // "" | test("ruff check"))))' \
  "$ROOT/conveyor/lib/test-pack.json" > "$R/.conveyor/project.json" || exit 1
[ "$(jq '.lint.commands | length' "$R/.conveyor/project.json")" = 1 ] || { echo "not ok - the pack has no one ruff command"; exit 1; }
cp "$ROOT/ruff.toml" "$R/" && cp "$ROOT/.claude/scripts/dashboard_server.py" "$R/.claude/scripts/" || exit 1
{ fn 'def f(a):' 8; echo; echo; fn 'def g(a):' 12; } > "$R/c.py"
g add -A && g commit -qm base && g worktree add -q --detach "$W" || exit 1
base=$(g rev-parse HEAD)

# engine <commands>: <commands> in a shell of the engine as conveyor.sh lint loads it, main being $R; output in
# $T/out.
engine() {
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/cards
    . "$ROOT/conveyor/conveyor.sh" state-dir > /dev/null && . "$ROOT/conveyor/lib/slots.sh" && . "$ROOT/conveyor/lib/prompts.sh" \
      && . "$ROOT/conveyor/lib/push.sh" && . "$ROOT/conveyor/lib/lint.sh" || exit 9
    eval "$1" ) > "$T/out" 2>&1
}

# The card's change: an unused import at the top of dashboard_server.py, 3 more ifs in f's body (complexity 12), and
# a new parameter on g's def line, g's body unchanged.
awk '!d && /^import / { print "import colorsys"; d = 1 } 1' "$R/.claude/scripts/dashboard_server.py" > "$W/.claude/scripts/dashboard_server.py" || exit 1
{ fn 'def f(a):' 11; echo; echo; fn 'def g(a, b=0):' 12; } > "$W/c.py"
git -C "$W" add -A || exit 1

if command -v ruff > /dev/null; then
  sums() { (cd "$W" && git ls-files -z '*.py' | xargs -0 cksum); }
  before=$(sums)
  # shellcheck disable=SC2016 # expanded by the engine's shell
  engine 'lintrun "$W" '"$base"' c7 "$T/run"; echo "exit $?"; cat "$T/run"'
  rep=$(sed 1d "$T/out" | jq -r '.reported[] | "\(.file):\(.line) \(.code)"' 2>/dev/null | paste -sd' ' -)
  head -1 "$T/out" | grep -qx 'exit 1' || no "the gate did not end in findings: $(cat "$T/out")"
  [[ " $rep " == *" .claude/scripts/dashboard_server.py:"*" F401 "* ]] \
    && ok "an unused import added to dashboard_server.py is a finding at the gate" || no "no F401 of dashboard_server.py: $rep"
  [[ " $rep " == *" c.py:1 C901 "* ]] && ok "a body edit that takes a function over the complexity limit is a finding" \
    || no "f over the limit is not reported: $rep"
  gl=$(grep -n '^def g' "$W/c.py" | cut -d: -f1)
  [[ " $rep " != *" c.py:$gl C901 "* ]] && ok "a signature edit of a function already over the limit is no finding" \
    || no "g's old C901 is reported: $rep"
  [ "$(sums)" = "$before" ] && ! grep -q 'changed the worktree' "$T/out" && ok "a gate run leaves every Python file unchanged" \
    || no "a Python file changed: $(cat "$T/out")"

  echo 'this is = = not toml' > "$W/ruff.toml" && git -C "$W" add -A || exit 1
  # shellcheck disable=SC2016 # expanded by the engine's shell
  engine 'lintcheck "$W" '"$base"
  [ "$(jq -r .result "$T/out" 2>/dev/null)" = error ] && ok "a broken ruff.toml gives an execution error" || no "broken ruff.toml: $(cat "$T/out")"
  cp "$R/ruff.toml" "$W/ruff.toml" && git -C "$W" add -A || exit 1
else
  for c in "an unused import is a finding" "a body edit over the limit is a finding" "a signature edit is no finding" \
    "a gate run leaves the Python files unchanged" "a broken ruff.toml is an execution error"; do
    n=$((n + 1)); echo "ok $n - # SKIP $c: ruff is not on PATH"
  done
fi

# No ruff: each PATH folder that holds one is replaced by a folder of links to its other programs.
p=''
IFS=: read -ra dirs <<<"$PATH"
for d in "${dirs[@]}"; do
  if [ -e "$d/ruff" ]; then s=$T/path$n.${#p}; mkdir "$s" && ln -s "$d"/* "$s"/ && rm "$s/ruff" || exit 1; d=$s; fi
  p+=${p:+:}$d
done
# The gate's run, then the lint line it records (lintline; record prints the line's fields here).
# shellcheck disable=SC2016 # expanded by the engine's shell
PATH=$p engine 'lintrun "$W" '"$base"' c7 "$T/run"; r=$?; echo "exit $r"; record() { jq -r ".lint.commands[0].result" <<<"$5"; }
  lintline c7 1 "$T/run" $r review'
[ "$(cat "$T/out")" = "$(printf 'exit 0\nskipped: missing ruff')" ] && ok "with ruff absent, the command gives skipped: missing ruff" \
  || no "no ruff: $(cat "$T/out")"

echo "1..$n"; exit $bad
