# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# The input a guard hook test last gave its hook, for the FAIL lines of the checks after it (#1084): a failure log
# names the command the hook was given, so it can be read with no run again. Sourced by the guard hook tests under
# .claude/hooks/__tests__/ that name their input (said.test.sh checks it there); each FAIL line they print ends with $(said).
#   bash ...         a call of bash on a script file, wherever it is (`bash "$HOOK"`, `bash "$copy/git-safety.sh"
#                    --hash-range a b`: a first word that is a file) notes the call's words after the script and its
#                    stdin, then runs it with that stdin; any other call of bash (`bash -c ...`) runs as it would. A
#                    test that runs the hook itself ("$HOOK" <<<"$x") notes the input with said_in.
#   said_in <input>  notes the input, and no words (a call often runs in a $(...) subshell, so the note is a file,
#                    removed on exit). It stands until the next input is noted: several checks of one hook call's
#                    output each name it.
#   said_tee         in a pipe into the hook: notes its stdin as said_in does and passes it on unchanged
#   said             for a FAIL line: ` [the hook's last command "<it>"]` (an input whose tool_input.command is a
#                    string), else ` [the hook's last input <it, as JSON>]`; a call with words after the script names
#                    them first: ` [the hook's last call "<words>", command "<it>"]`, or the words alone when it had
#                    no input. Cut to 600 characters; nothing when nothing is noted yet.
SAID_FILE=$(mktemp "${TMPDIR:-/tmp}/hook-said.XXXXXX") || SAID_FILE=/dev/null
# The note is removed when the shell that sourced this ends (said_exit), before the EXIT trap the test sets
# (SAID_OLDTRAP), whenever the test sets it: one set before this file is read back from trap -p's
# `trap -- '<it>' EXIT`, and a later `trap <it> EXIT` goes through the trap function below, which keeps it there. A
# subshell's EXIT trap runs its own and leaves the note.
SAID_PID=$BASHPID SAID_OLDTRAP=''
said_exit() { [ "$BASHPID" != "$SAID_PID" ] || rm -f "$SAID_FILE" "$SAID_FILE.args"; eval "$SAID_OLDTRAP"; }
_said_w=(); eval "_said_w=($(builtin trap -p EXIT))"; SAID_OLDTRAP=${_said_w[2]:-}; unset _said_w
builtin trap said_exit EXIT
trap() {
  if [ $# = 2 ] && [ "$2" = EXIT ]; then
    if [ "$1" = - ]; then SAID_OLDTRAP=''; else SAID_OLDTRAP=$1; fi
    builtin trap said_exit EXIT
  elif [ "${1:-}" = -p ]; then shift; builtin trap -p "$@"
  else builtin trap -- "$@"; fi
}
said_in() { printf '%s' "$1" > "$SAID_FILE"; rm -f "$SAID_FILE.args"; }
said_tee() { local s=''; IFS= read -r -d '' s || :; said_in "$s"; printf '%s' "$s"; } # read: 1 at the end of stdin
# The words after the script go to $SAID_FILE.args, shell-quoted (printf %q), when there are any. The script gets the
# payload back on a here-string of its own (one newline after it), or /dev/null when it was empty. A stdin that is a
# terminal (a hook call with no input, in a test run by hand) is left to the script unread, and noted as no input.
bash() {
  case ${1:-} in -*|'') command bash "$@"; return ;; esac
  [ -f "$1" ] || { command bash "$@"; return; }
  local s='' w=''
  if [ -t 0 ]; then said_in ''; else IFS= read -r -d '' s || :; said_in "$s"; fi # read: 1 at the end of stdin
  [ $# -lt 2 ] || { printf -v w ' %q' "${@:2}"; printf '%s' "${w# }" > "$SAID_FILE.args"; }
  if [ -t 0 ]; then command bash "$@"
  elif [ -n "$s" ]; then command bash "$@" <<<"$s"; else command bash "$@" < /dev/null; fi
}
said() {
  local s='' w=''
  [ ! -s "$SAID_FILE" ] || IFS= read -r -d '' s < "$SAID_FILE" || : # read: 1 at the file's end, which has no NUL
  [ ! -s "$SAID_FILE.args" ] || IFS= read -r -d '' w < "$SAID_FILE.args" || :
  [ -n "$s$w" ] || return 0
  [ -z "$s" ] || s=$(printf '%s' "$s" | jq -rRs '(try fromjson catch null) as $j
    | if ($j | type) == "object" and ($j.tool_input.command | type) == "string" then "command \($j.tool_input.command | tojson)"
      elif $j != null then "input \($j | tojson)" else "input \(tojson)" end' 2>/dev/null) || s="input $s"
  [ -z "$w" ] || { w=$(jq -rn --arg w "$w" '$w | tojson'); s="call $w${s:+, $s}"; }
  [ ${#s} -le 600 ] || s="${s:0:599}…"
  printf ' [the hook'\''s last %s]' "$s"
}
