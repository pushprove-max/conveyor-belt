#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Issue 1775. `test-changed.sh --funcs <file>` (FUNCS) gives the sum of each function of a shell file, for the coverage
# map (coverage.sh) and the selection of a change's tests (covof). When it cannot read a file, it exits 1 and a change
# to that file runs every test of its area, or none of the hooks' tests that the map would give it.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P); ROOT=$(dirname "$HERE")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bad=0; n=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; bad=1; }
# funcs <file>: `--funcs <file>` run in this checkout, its output in $T/out and its exit status in rc.
funcs() { (cd "$ROOT" && bash .conveyor/test-changed.sh --funcs "$1") > "$T/out" 2>&1; rc=$?; }
names() { cut -f1 "$T/out" | sort | paste -sd ' ' -; }
# sum <line>...: the sum --funcs gives a function of these lines (sumsof: the cksum of its lines joined by \001).
sum() { local IFS=$'\001'; cksum <<<"$*" | cut -d' ' -f1; }

# Bug: a function whose last line is `  ...; }` (not a `}` at the left) ran on into the next function, so --funcs exited
# 1 on these engine files: claim.sh's tested(), card.sh's mainwaited() and cardland.sh's holdwaited() end so.
all=
for f in conveyor/lib/claim.sh conveyor/lib/card.sh conveyor/lib/cardland.sh; do
  funcs "$f"; want=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\) *\{' "$ROOT/$f" | sed 's/(.*//' | sort | paste -sd ' ' -)
  [ "$rc" = 0 ] && [ "$(names)" = "$want" ] && ok "--funcs $f gives each function of the file" \
    || no "--funcs $f: exit $rc, functions '$(names)', want '$want'"
  all+=" $(names)"
done
for w in tested mainwaited holdwaited; do
  [[ "$all " == *" $w "* ]] && ok "--funcs finds $w()" || no "--funcs of claim.sh, card.sh and cardland.sh: no $w() in '$all'"
done

# The same in a file of its own: the first function's body ends with `; }` on its third line, then a top-level line
# that ends with `; }` too, a comment, a second function and a last one that ends with `; }` at the end of the file
# (bug: the end of the file left that function open, and --funcs exited 1, as on wording.sh's section()). The first
# one's sum is that of its three lines alone, the top-level line no part of it.
printf '%s\n' 'one() {' '  local x=1' '  echo "$x"; }' '[ -n "${Y:-}" ] || { Y=1; }' '# two: says two' 'two() {' '  echo two' '}' \
  'three() {' '  echo 3; }' > "$T/semi.sh"
funcs "$T/semi.sh"
want=$(printf 'one\t%s\ntwo\t%s\nthree\t%s' "$(sum 'one() {' '  local x=1' '  echo "$x"; }')" "$(sum 'two() {' '  echo two' '}')" \
  "$(sum 'three() {' '  echo 3; }')")
[ "$rc" = 0 ] && [ "$(cat "$T/out")" = "$want" ] && ok "a function ends at its last line that ends with '; }', the file's last one too" \
  || no "--funcs of a function ending '  echo \"\$x\"; }' on its third line, and a last one ending '  echo 3; }': exit $rc, got '$(cat "$T/out")', want '$want'"

# Bug: a `<<word` in a comment (`<<123`, hook-fire-log.sh) or `<<-?` in a pattern (strip-quoted.sh) was read as the
# start of a heredoc that never ended, so --funcs exited 1 on both hook libraries, and the hooks' tests that the
# map gives their functions were not run on a change to them.
printf '%s\n' 'one() {' '  # a word closes a heredoc (<<123)' "  p='^<<-?[[:blank:]]'" '}' 'two() {' '  echo two' '}' > "$T/hd.sh"
funcs "$T/hd.sh"
[ "$rc" = 0 ] && [ "$(names)" = 'one two' ] && ok "a '<<word' in a comment or '<<-?' in a pattern starts no heredoc" \
  || no "--funcs of a function with '# (<<123)' and \"p='^<<-?'\": exit $rc, got '$(cat "$T/out")', want one and two"
for f in .claude/hooks/lib/hook-fire-log.sh .claude/hooks/lib/strip-quoted.sh; do
  funcs "$f"; want=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\) *\{' "$ROOT/$f" | sed 's/(.*//' | sort | paste -sd ' ' -)
  [ "$rc" = 0 ] && [ "$(names)" = "$want" ] && ok "--funcs $f gives each function of the file" \
    || no "--funcs $f: exit $rc, functions '$(names)', want '$want'"
done
echo "1..$n"
exit "$bad"
