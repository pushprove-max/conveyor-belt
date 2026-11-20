#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The shell function-length reader (lint-funcs.sh with lint-funcs.awk) on fixtures, under each of awk, mawk, gawk and
# original-awk (the macOS system awk's source) that is installed. Bugs it catches: a function given a wrong length
# (ended at a nested function's `}` or at a `}` in a here-document, missed when its `{` is on a later line, or not
# measured when its closing `)` or `}` touches the word or `)` before it), a 101-line function let through or an
# exempt one reported, an awk function in quoted text taken for shell, a JavaScript function in a here-document
# measured or let through, a file that does not parse given more than one finding (or, with --list, an empty list and
# exit 0), an awk that gives other marks than another, a failure of the reader read as a pass or a finding, and an open quote
# in an array assignment (bash -n's exit 1) taken for a failure of the reader.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
LF=$ROOT/.conveyor/lint-funcs.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
fails=0
no() { echo "not ok - $*"; fails=1; }
same() { [ "$2" = "$3" ] || no "$1"$'\n'"want:"$'\n'"$3"$'\n'"got:"$'\n'"$2"; }

# Each function has its true length (lines from its start to its end): a one-line function, a last line that ends
# `; }`, a nested definition at the left margin (part of the outer one), a here-document holding `}` and `done`, an
# indented definition, a blank line and a comment line before `{`, an `if` body, a `for` body, `foo+bar() {`,
# `name () {`, `function kw {`, a subshell body whose `)` touches its last word, a `}` that touches a `)`, and a `}`
# inside a quote of an array assignment (bash -n exits 1 on the text that ends there, not 2: no execution error).
cat > lengths.sh <<'EOF'
one() { echo 1; }
semi() {
  echo a; }
outer() {
inner() {
  echo in
}
  inner
}
here() {
  cat <<END
}
done
END
}
  ind() {
    echo
  }
blank()

{
  echo
}
comm()
# a comment
{
  echo
}
ifb() if true; then
  echo
fi
forb() for x in a b; do
  echo "$x"
done
foo+bar() {
  echo
}
name () {
  echo
}
function kw {
  echo
}
sub() ( echo one)
brace() { (echo)}
arr() {
  a=(x 'y
}
z')
}
EOF
LENGTHS=$(printf 'lengths.sh\t%s lines\n' 'one	1	1' 'semi	2	2' 'outer	4	6' 'here	10	6' 'ind	16	3' 'blank	19	5' \
  'comm	24	5' 'ifb	29	3' 'forb	32	3' 'foo+bar	35	3' 'name	38	3' 'kw	41	3' \
  'sub	44	1' 'brace	45	1' 'arr	46	5')

# long is 101 lines (lines 1 to 101), fits 100 (102 to 201), old 121 (202 to 322) and exempt; then an awk function in
# quoted text (324), a JavaScript function in a here-document whose start line parses as shell (330), and a function
# with no end line that parses (335, in a here-document: its `}` ends no text that bash reads).
{ echo 'long() {'; for i in $(seq 99); do echo "  echo $i"; done; echo '}'
  echo 'fits() {'; for i in $(seq 98); do echo "  echo $i"; done; echo '}'
  echo 'old() {'; for i in $(seq 119); do echo "  echo $i"; done; echo '}'
  cat <<'EOF'
awk '
function add(a, b) {
  return a + b
}
{ print add($1, $2) }
' /dev/null
cat > app.js <<'JS'
function show() {
  const a = (b) => b;
}
JS
cat <<'TXT'
tailf() {
  echo }
TXT
EOF
} > limits.sh
printf 'limits.sh\told\n' > old.txt
printf 'limits.sh\told\nlimits.sh\tshow\n' > show.txt
FOUND='limits.sh:1: function-length long 101 lines, limit 100
limits.sh:330: function-length show is not measured
limits.sh:335: function-length tailf is not measured'
LIST=$(printf 'limits.sh\t%s\n' 'long	1	101 lines' 'old	202	121 lines' 'add	324	not shell' 'show	330	not measured' \
  'tailf	335	not measured')

# A file that does not parse (b's `if` has no `fi`) is one finding, at the line bash names, though it has two functions.
printf 'a() {\n  echo a\n}\nb() {\n  if true; then\n    echo b\n}\n' > broken.sh
# A file that ends in an open quote of an array assignment (bash -n exits 1 there, not 2) is that one finding too.
printf "a=(x 'y\n" > openq.sh

# Every fixture, under the awk <awk>.
check() { # <awk>
  local got rc
  got=$(AWK=$1 bash "$LF" --max 0 --list lengths.sh 2>&1); rc=$?
  same "$1: each function's true length (exit $rc)" "$got" "$LENGTHS"
  got=$(AWK=$1 bash "$LF" --max 100 lengths.sh 2>&1); rc=$?
  same "$1: no function over the limit is no finding (exit $rc)" "$got:$rc" ":0"
  # A 101-line function is a finding, a 100-line one none, and the exempt 121-line one none; an awk function in
  # quoted text is none; the JavaScript function and the function with no end are "not measured" findings.
  got=$(AWK=$1 bash "$LF" --max 100 --exempt old.txt limits.sh 2>&1); rc=$?
  same "$1: the findings of the limit" "$got:$rc" "$FOUND:1"
  got=$(AWK=$1 bash "$LF" --max 100 --exempt show.txt limits.sh 2>&1); rc=$?
  same "$1: a \"not measured\" start the exempt file names is no finding" "$got:$rc" "$(sed '/ show /d' <<<"$FOUND"):1"
  # --list prints the functions over the limit, exempt or not, the "not measured" starts and the "not shell" ones.
  got=$(AWK=$1 bash "$LF" --max 100 --exempt old.txt --list limits.sh 2>&1); rc=$?
  same "$1: --list" "$got:$rc" "$LIST:0"
  got=$(AWK=$1 bash "$LF" --max 100 broken.sh 2>&1); rc=$?
  same "$1: a file that does not parse" "$got:$rc" \
    "broken.sh:7: function-length the file does not parse, so its functions are not measured:1"
}
declare -A seen=()
ran=''
for a in awk mawk gawk original-awk; do
  p=$(command -v "$a") || continue
  # One run an awk, though awk is a link to mawk.
  p=$(readlink -f "$p" 2>/dev/null) || p=$(command -v "$a")
  [ -z "${seen[$p]:-}" ] || continue
  seen[$p]=1; ran+=" $a"; check "$a"
done
[ -n "$ran" ] || no "no awk was found"
# --list on a file that does not parse lists nothing, says so on stderr and exits 1, so a list made from it is not
# taken for whole.
got=$(bash "$LF" --list broken.sh 2> err); rc=$?
same "--list on a file that does not parse" "$got:$rc:$(cat err)" \
  ":1:broken.sh:7: function-length the file does not parse, so its functions are not measured"
got=$(bash "$LF" openq.sh 2>&1); rc=$?
same "a file that ends in an open quote of an array" "$got:$rc" \
  "openq.sh:1: function-length the file does not parse, so its functions are not measured:1"

# An execution error exits 2, never 0 or 1: an awk that fails, an awk that prints what is no mark, and a file that
# cannot be read.
printf '#!/bin/sh\necho "awk: syntax error at source line 1" >&2\nexit 2\n' > badawk
printf '#!/bin/sh\nprintf "S\\tx\\tone\\n"\n' > oddawk
chmod +x badawk oddawk
AWK=$T/badawk bash "$LF" lengths.sh > /dev/null 2>&1; rc=$?
[ $rc = 2 ] || no "a broken awk exited $rc, not 2"
AWK=$T/oddawk bash "$LF" lengths.sh > /dev/null 2>&1; rc=$?
[ $rc = 2 ] || no "an awk that prints no mark exited $rc, not 2"
bash "$LF" missing.sh > /dev/null 2>&1; rc=$?
[ $rc = 2 ] || no "a file that cannot be read exited $rc, not 2"

[ $fails = 0 ] || exit 1
echo "ok - lint-funcs, under:$ran"
