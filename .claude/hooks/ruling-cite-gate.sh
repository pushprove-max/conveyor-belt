#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook (Edit|Write|MultiEdit): a memory or rule line that cites a ruling, ruling:<id>, must cite an id the
# decision log holds (ruling-log.sh writes it; lib/rulings.sh names it). A made-up id, or one whose row is void (known
# not to be the owner's words), is refused, so a note can never pass off an invented ruling or time as the owner's.
#
# Scope: memory files and .claude/rules/. Only ADDED lines are checked: the edit is applied to the file in memory and
# every resulting line not already on disk is screened, so an edit that changes only the id inside an old line pays
# too, even when its old and new text hold no `ruling:`. Unchanged old lines are grandfathered. Silent when it passes.
# Its limit, accepted: it protects memory and the rules folder by their plain paths, and follows a symlink only as far
# as real_path below does. A path reached through a symlink alias it does not resolve, or a rules folder that is itself
# a symlink, is out of scope: it checks agents' own writes and is not a security boundary.
#
# ruling-cite-gate.sh --id <id> runs the same log check on one id, exit 0 or 1.
# Self-test: bash .claude/hooks/__tests__/ruling-cite-gate.test.sh
. "${BASH_SOURCE[0]%/*}/lib/rulings.sh"
# ruling_id_ok <id>: a row with this id is in the log and is not void. jq, not a string match: a row voided by hand may
# be written with spaces.
ruling_id_ok() {
  [ -n "$LOG" ] && grep -F -- "$1" "$LOG" 2>/dev/null | jq -e --arg id "$1" 'select(.id == $id and (.void | not))' >/dev/null 2>&1
}
# real_path <absolute path>: where the path lands on disk, so a symlinked folder or file cannot carry a rules write out
# of scope. Walked one segment at a time as the kernel does: a symlink is followed before a `..` after it applies, so
# `link/../x` lands beside the link's target, not beside the link. A missing segment is kept as named. Plain bash:
# macOS has no `realpath -m`. Split on / alone and read to the end, never to a newline: a name may hold one.
real_path() {
  local cur= s t n=0; local -a q tq
  IFS=/ read -rd '' -a q < <(printf '%s' "$1")
  while [ ${#q[@]} -gt 0 ]; do
    s=${q[0]}; q=("${q[@]:1}")
    case "$s" in ''|.) continue ;; ..) cur=${cur%/*}; continue ;; esac
    if [ -L "$cur/$s" ] && [ $n -lt 40 ] && t=$(readlink -- "$cur/$s" && echo .); then
      t=${t%.}; t=${t%$'\n'}; n=$((n+1)); IFS=/ read -rd '' -a tq < <(printf '%s' "$t");q=(${tq[@]+"${tq[@]}"} ${q[@]+"${q[@]}"})
      case "$t" in /*) cur= ;; esac
    else
      cur=$cur/$s
    fi
  done
  printf '%s' "${cur:-/}"
}
INPUT=
[ "${1:-}" = --id ] || INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# The log's path costs about twenty programs (the Foreman's folder, through git, jq and the engine), so it is named
# only once a line cites a ruling: an edit that adds none never needs it.
LOG=
if [ "${1:-}" = --id ]; then
  LOG=$(rulings_log) || LOG=
  [ -n "${2:-}" ] && ruling_id_ok "$2" && exit 0; exit 1
fi
source "${BASH_SOURCE[0]%/*}/lib/edit-payload.sh" 2>/dev/null
hook_payload_loaded 2>/dev/null || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load .claude/hooks/lib/edit-payload.sh, so it cannot screen this write." >&2; exit 2; }
[ -n "$(hook_edit_triples "$INPUT")" ] || exit 0
# Every path the call writes: the top-level one and any an edit names for itself (a per-edit path wins over the
# top-level one, as in lib/edit-payload.sh). Each is screened with the text that is its own.
ADDED=
while IFS= read -rd '' RAW; do
  [ -n "$RAW" ] || continue
  # The path as it names the file: relative to the project, with no ./ or ../ segment, so `.claude/./rules/x.md` is
  # in scope; and also where it lands (real_path of the path as given, before any `..` is collapsed), so a symlink into
  # memory or rules is in scope too. The text already there is read from where it lands.
  FILE_PATH=$RAW
  case "$FILE_PATH" in /*) ;; *) FILE_PATH=${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // "."' 2>/dev/null)}/$FILE_PATH ;; esac
  # A sentinel keeps a trailing newline in the name: $(...) alone strips it, and the text read would be another file's.
  REAL=$(real_path "$FILE_PATH"; echo .); REAL=${REAL%.}
  IFS=/ read -rd '' -a SEGS < <(printf '%s' "$FILE_PATH"); NORM=()
  for s in ${SEGS[@]+"${SEGS[@]}"}; do
    case "$s" in ''|.) ;; ..) [ ${#NORM[@]} -eq 0 ] || unset 'NORM[-1]' ;; *) NORM+=("$s") ;; esac
  done
  printf -v FILE_PATH '/%s' ${NORM[@]+"${NORM[@]}"}
  for P in "$FILE_PATH" "$REAL"; do
    case "$P" in */.claude/projects/*/memory/*|*/.claude/rules/*) break ;; esac
    P=
  done
  [ -n "$P" ] || continue
  CUR=/dev/null; [ -f "$REAL" ] && CUR="$REAL"
  # The file as it will be after this call. split/join keeps the replacement literal; the first-only form mirrors
  # Edit without replace_all. An old_string the file does not hold still has its new text screened, appended: the
  # gate must never pass text it did not look at.
  RESULT=$(printf '%s' "$INPUT" | jq -r --rawfile cur "$CUR" --arg raw "$RAW" '
    def rep($o; $n; $all):
      split($o) as $p
      | if $o == "" or ($p | length) < 2 then . + "\n" + $n
        elif $all then $p | join($n)
        else $p[0] + $n + ($p[1:] | join($o)) end;
    .tool_input as $t
    | if $t.content != null and $t.file_path == $raw then $t.content
      else reduce (
          (if $t.old_string != null and $t.file_path == $raw then [$t] else [] end)
          + [($t.edits // [])[] | select((.file_path // $t.file_path) == $raw)] | .[]
        ) as $e ($cur; rep($e.old_string // ""; $e.new_string // ""; $e.replace_all // false))
      end' 2>/dev/null)
  # Added = resulting lines beyond each line's count on disk, so a second copy of an old line is added while a moved
  # line is not.
  ADDED+=$(printf '%s\n' "$RESULT" | awk 'FILENAME == ARGV[1] { n[$0]++; next }
    n[$0] > 0 { n[$0]--; next } { print }' "$CUR" - | grep -F 'ruling:')$'\n'
done < <(printf '%s' "$INPUT" | jq -j '[.tool_input.file_path, (.tool_input.edits // [])[].file_path]
  | map(select(type == "string")) | unique[] | . + "\u0000"' 2>/dev/null)
ADDED=$(grep -v '^$' <<<"$ADDED")
[ -n "$ADDED" ] || exit 0
LOG=$(rulings_log) || LOG=

BAD=""
while IFS= read -r line; do
  # Every cited token, of any shape: one the log does not hold is refused whatever it looks like.
  while IFS= read -r id; do
    ruling_id_ok "$id" || BAD="$BAD  ${id:-(empty)}: ${line:0:160}\n"
  done < <(printf '%s' "$line" | grep -oE 'ruling:[A-Za-z0-9._-]*' | cut -d: -f2 | sed -E 's/[._-]+$//')
done <<< "$ADDED"
[ -z "$BAD" ] && exit 0
cat >&2 <<EOF
BLOCKED: line(s) cite a ruling id the decision log does not hold (or holds as void):

$(printf '%b' "$BAD")
Each cited id must be in ${LOG:-the decision log (the state folder could not be named)}.
Get the id from the "ruling logged: ..." line printed after AskUserQuestion, or for words the owner typed in chat
run: bash .claude/scripts/ruling-id.sh "<verbatim phrase>". Use the time that lookup prints, never one from memory.
EOF
exit 2
