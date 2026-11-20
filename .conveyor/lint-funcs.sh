#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The shell function-length reader of the lint check, used only for lint (the coverage reader FUNCS in
# test-changed.sh is another reader). Its test is lint-funcs.test.sh.
# Usage: lint-funcs.sh [--max <lines>] [--exempt <file>] [--list] <file>...
# For each <file>, a path from the tree's top:
# 1. bash -n reads the whole file. A file that does not parse is one finding
#    `<path>:<line>: function-length the file does not parse, so its functions are not measured`, and none of its
#    functions is measured.
# 2. lint-funcs.awk marks each line that can start a function and each line that can end one.
# 3. For each start not inside a function already measured, bash -n reads the lines from the start line to each end
#    line in turn, through a pipe; the first text it accepts is the function, and its length is those lines.
#    "Unexpected end of file" or "unexpected EOF" (also with exit 1, an open quote in an array assignment): the next
#    end line. A syntax error on the start line itself: not shell code (an awk function in quoted text), no finding.
#    A syntax error on a later line, or no end line that parses: the function is not measured (a JavaScript function
#    in a here-document whose start line parses as shell).
# A function over --max lines (100 when not given) is the finding `<path>:<start>: function-length <name> <n> lines,
# limit <max>`, and a start that is not measured the finding `<path>:<start>: function-length <name> is not measured`,
# unless a line of the --exempt file is `<path><TAB><name>` (a missing exempt file exempts nothing). The exit is 1 when
# there is a finding, else 0.
# --list prints in place of the findings, one a line, `<path><TAB><name><TAB><start><TAB><what>`, <what> being
# `<n> lines` for a function over --max lines, `not measured` or `not shell`; the exempt file is not read. A file that
# does not parse is its finding line on stderr there, and the exit is 1.
# Any other failure (awk ending with an exit other than 0 or printing a line that is no mark, bash -n ending with an
# exit other than 0 or 2 (1 with an unexpected EOF in a quote aside), or with 2 and no syntax error, a file it
# cannot read) is an execution error: its why on stderr, and the exit is 2. AWK names the awk to run (default awk).
# Not read: a definition that does not begin its line, a second definition on one line, and a function nested in
# another (it is part of the outer one). `function name (` with a parenthesis body and no `()` is a start as any
# other, and bash -n decides what it is.
set -u
unset BASH_ENV ENV
export LC_ALL=C
AWK=${AWK:-awk}
PROG=$(dirname "$0")/lint-funcs.awk
fail() { echo "lint-funcs: $*" >&2; exit 2; }
usage() { fail "usage: lint-funcs.sh [--max <lines>] [--exempt <file>] [--list] <file>..."; }
max=100 ex='' list=''
while [ $# -gt 0 ]; do
  case $1 in
    --max) [[ ${2:-} =~ ^[0-9]+$ ]] || usage; max=$((10#$2)); shift 2 ;;
    --exempt) [ $# -ge 2 ] || usage; ex=$2; shift 2 ;;
    --list) list=1; shift ;;
    --) shift; break ;;
    -?*) usage ;;
    *) break ;;
  esac
done
[ -f "$PROG" ] && [ -r "$PROG" ] || fail "$PROG cannot be read"
declare -A skip=()
if [ -z "$list" ] && [ -n "$ex" ] && [ -e "$ex" ]; then
  [ -f "$ex" ] && [ -r "$ex" ] || fail "$ex cannot be read"
  while IFS= read -r l || [ -n "$l" ]; do l=${l%$'\r'}; [ -z "$l" ] || skip[$l]=1; done < "$ex" || fail "$ex cannot be read"
fi
RS=$'^S\t([1-9][0-9]*)\t([^\t]+)$' RE=$'^E\t([1-9][0-9]*)$'
# bash -n exits 1, not 2, when the text ends in an open quote inside an array assignment (`a=(x 'y`): true for that
# exit ($r) and its output ($out).
eofq() { [ "$r" = 1 ] && [[ $out == *'unexpected EOF while looking for matching'* ]]; }

# One result: a finding line, or with --list a list line. <what> is a length, `not measured` or `not shell`.
report() { # <path> <name> <start> <what>
  if [ -n "$list" ]; then
    case $4 in not*) printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" ;; *) [ "$4" -le "$max" ] || printf '%s\t%s\t%s\t%s lines\n' "$1" "$2" "$3" "$4" ;; esac
    return
  fi
  [ -z "${skip[$1$'\t'$2]:-}" ] || return 0
  case $4 in
    'not shell') ;;
    'not measured') echo "$1:$3: function-length $2 is not measured"; rc=1 ;;
    *) [ "$4" -le "$max" ] || { echo "$1:$3: function-length $2 $4 lines, limit $max"; rc=1; } ;;
  esac
}

rc=0
for f; do
  [ -f "$f" ] && [ -r "$f" ] || fail "$f cannot be read"
  out=$("$BASH" -n < "$f" 2>&1); r=$?
  if [ $r != 0 ]; then
    { [ $r = 2 ] || eofq; } && [[ $out =~ line\ ([0-9]+):\ (syntax\ error|unexpected\ EOF) ]] \
      || fail "bash -n exited $r on $f: $out"
    l="$f:${BASH_REMATCH[1]}: function-length the file does not parse, so its functions are not measured"
    if [ -n "$list" ]; then echo "$l" >&2; else echo "$l"; fi
    rc=1; continue
  fi
  marks=$("$AWK" -f "$PROG" < "$f") || fail "$AWK exited $? on $f"
  mapfile -t L < "$f" || fail "$f cannot be read"
  S=() N=() E=()
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    if [[ $m =~ $RS ]]; then S+=("${BASH_REMATCH[1]}"); N+=("${BASH_REMATCH[2]}")
    elif [[ $m =~ $RE ]]; then E+=("${BASH_REMATCH[1]}")
    else fail "$AWK printed a line that is no mark on $f: $m"; fi
    [ "${BASH_REMATCH[1]}" -le ${#L[@]} ] || fail "$AWK marked line ${BASH_REMATCH[1]} of $f, which has ${#L[@]} lines"
  done <<<"$marks"
  to=0 j=0
  for ((i = 0; i < ${#S[@]}; i++)); do
    s=${S[i]}
    [ "$s" -gt "$to" ] || continue
    while [ $j -lt ${#E[@]} ] && [ "${E[j]}" -lt "$s" ]; do j=$((j + 1)); done
    what='not measured'
    for ((k = j; k < ${#E[@]}; k++)); do
      e=${E[k]}
      out=$(printf '%s\n' "${L[@]:s-1:e-s+1}" | "$BASH" -n 2>&1); r=$?
      [ $r = 0 ] && { what=$((e - s + 1)); to=$e; break; }
      [ $r = 2 ] || eofq || fail "bash -n exited $r on lines $s to $e of $f: $out"
      case $out in *'unexpected end of file'*|*'unexpected EOF'*) continue ;; esac
      [[ $out =~ line\ ([0-9]+):\ syntax\ error ]] || fail "bash -n exited 2 with no syntax error on lines $s to $e of $f: $out"
      [ "${BASH_REMATCH[1]}" != 1 ] || what='not shell'
      break
    done
    report "$f" "${N[i]}" "$s" "$what"
  done
done
exit $rc
