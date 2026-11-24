#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook: enforce the 4 GB heap cap on node's test runner.
# Tool-steering rules (use Read instead of cat, Glob instead of find) were
# dropped: they cost a fork on every Bash call to restate a preference no
# incident traces to, and Codex has neither tool.
# Retire when: each rule has its own Retire-when, or the hook is split into per-rule hooks
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# A here-document's end word is one plain word (letters, digits, _ . -): bare,
# in one pair of quotes, or after one backslash. Every other `<<` is refused
# here, above every other rule and exit, so no rule in this or any other hook
# has to read an odd end word; each misread one hid the command after the note.
# A `<<<` here-string has no body and passes. Only a `<<` bash reads as an
# operator is judged: strip_quoted reports each one outside quotes, comments
# and earlier bodies. A shift inside `$(( ))` made of plain arithmetic only is
# taken out first; nothing in it can spell an odd end word.
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
# Without the helper no end word is checked and every bare node --test would pass.
type strip_quoted >/dev/null 2>&1 || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load .claude/hooks/lib/strip-quoted.sh, so it cannot screen this command. Restore it (git checkout .claude/hooks/lib/strip-quoted.sh) and retry.
Instead: git checkout .claude/hooks/lib/strip-quoted.sh, then run the command again." >&2; exit 2; }
# The one fence for the rewrite that replaces the call's text (an unbounded search): the replacement must
# run exactly what the call would. Any `$`, backtick, backslash, newline or process substitution in the RAW text,
# quoted or not, refuses it (each can run or reshape something the replacement drops). The rest is read only through
# strip_quoted, which tracks quotes left to right; callers add their own shape checks on RW_TEXT.
rewrite_safe() { # <raw command>: sets RW_TEXT to the quote-stripped text
  case "$1" in *['$`\']*|*$'\n'*|*'<('*|*'>('*) return 1 ;; esac
  RW_TEXT=$(strip_quoted "$1")
}
case "$CMD" in
  # The reader cannot follow `$'...'` (a `\'` does not end it), so with one in
  # the command every `<<` in the text is judged as written.
  *"\$'"*'<<'*|*'<<'*"\$'"*)
    ODD=$(sed -E "s/<<<//g; s/<<-?[[:blank:]]*('$_STRIP_PLAIN_W'|\"$_STRIP_PLAIN_W\"|\\\\?$_STRIP_PLAIN_W)([[:space:];|&<>()]|\$)/\2/g" <<<"$CMD" | grep -oE '<<.{0,24}' | head -1) ;;&
  *'<<'*)
  [ -n "${ODD-}" ] || ODD=$(strip_quoted "$(sed -E 's/\$\(\([A-Za-z0-9_ +*\/%()<>-]*\)\)//g' <<<"$CMD")" "" ends 2>&1 >/dev/null | head -1)
  [ -z "$ODD" ] || { echo "BLOCKED: a here-document's end word is not plain: $ODD -- use one plain word such as EOF (letters, digits, _ . -), bare or in one pair of quotes. Instead: <<'EOF' ... a line holding only EOF." >&2; exit 2; } ;;
esac

# The serena-down marker stands the symbols hint down. No session writes it by
# hand: a hand-made one ran a whole session with the gates off (2026-09-18).
case "$CMD" in *claude-serena-down*)
  echo "BLOCKED: the claude-serena-down marker is not written by hand. If serena is missing from this session, say so in your reply; do not stand the symbols hint down by hand.
Instead: say in your report that serena is missing, and leave the marker alone." >&2
  exit 2 ;;
esac

# Block node's test runner without the 4 GB heap cap (.claude/rules/tests.md,
# Heap cap). Root cause of four WSL crashes on 2026-08-24: one uncapped
# `node --test` child grew at 1.45 GB/s to 29 GB and took the workstation.
# `npm run test:*` carries the cap in the script itself, so it never matches
# here -- only a bare `node`/`npx tsx` invocation does.
#
# `--test` must be followed by whitespace or end-of-command: `--test-concurrency`
# and `--test-reporter` are companion flags, not the runner switch, and matching
# them would fire on capped commands that spell the cap correctly.
#
# The check is PER SEGMENT, not per command line. A command-wide cap search
# passed `node --max-old-space-size=4096 --test a.ts && node --test b.ts`: the
# first invocation's flag vouched for the second, uncapped one.
# Quoted text is data, not a command: `rg 'node --test src/x.ts' .claude` is a
# search, and blocking it made the hook fire on ordinary work -- including on
# the report that described it. Quoted spans and heredoc bodies come out BEFORE
# the split, in one pass over the whole command: a per-line sed left a
# multi-line commit message whole. A `;` or `&&` inside a string cannot
# manufacture a segment either. A heredoc fed to a shell (`bash <<EOF`) is
# read as data too; that is an accepted gap.
# The strip walks the command a character at a time; only a `--test` can match
# (quote and backslash characters dropped first, so `--te''st` is still seen).
# A quoted span that is one word stays the word node gets (`node "--test"`,
# a quoted heap flag); a span holding a space is prose and reads as QUOTED, so
# a cap inside a multi-word quoted NODE_OPTIONS value is not seen and blocks.
HQ=$'\x01'
HEAP_CMD=""; P=${CMD//[\'\"\\]/}; case "$P" in *--test*) HEAP_CMD=$(strip_quoted "$CMD" "$HQ" | sed -E "s/${HQ}([;&|()[:space:]]|\$)/QUOTED\1/g; s/${HQ}//g") ;; esac

# With no --test there is nothing to read: an empty segment never holds a node call (four programs a call saved).
[ -n "$HEAP_CMD" ] && while IFS= read -r SEG; do
  # An `npm` segment carries the cap inside the script it runs, and its
  # arguments may legitimately spell out a node invocation
  # (`npm run test:unit -- node --test x.ts`). Leading `VAR=value` assignments
  # and `env` are prefixes, not the command: `CI=1 npm run test:unit` is npm.
  SEG_HEAD=$(echo "$SEG" | sed -E ':a; s/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env)[[:space:]]+//; ta')
  [ "$(echo "$SEG_HEAD" | awk '{print $1}')" = "npm" ] && continue

  echo "$SEG" | grep -qE '(^|[[:space:]])(node|npx[[:space:]]+tsx)([[:space:]]+[^[:space:]]+)*[[:space:]]+--test([[:space:]]|$)' || continue

  # Allow only an explicit cap of 4096 or lower, IN THIS SEGMENT. A LARGER
  # number is still a block: the point of the cap is that a runaway dies in
  # seconds. EVERY heap flag in the segment is read, in either spelling (node
  # takes `-` and `_` alike, and `=N` or a space) and wherever it sits:
  # node honours the last one, so `--max-old-space-size=4096
  # --max_old_space_size=8192` ran at 8 GB behind a guard that read one spelling.
  HEAPS=$(echo "$SEG" | grep -oE -- '--max[-_]old[-_]space[-_]size(=|[[:space:]]+)[0-9]+' | grep -oE '[0-9]+$')
  if [ -z "$HEAPS" ] || [ -n "$(awk '$1 > 4096' <<<"$HEAPS")" ]; then
    echo "BLOCKED: bare node --test without --max-old-space-size=4096, or with a larger heap flag beside it. Use the npm script (npm run test:unit / test:guards) or add the flag and drop any larger one. .claude/rules/tests.md, Heap cap.
Instead: npm run test:unit (or npm run test:guards, or npm run test:files -- <file>)." >&2
    exit 2
  fi
done < <(printf '%s\n' "$HEAP_CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/&/\n/g' -e 's/|/\n/g' -e 's/;/\n/g')

# split_search_segments, seg_words, load_words and shq, shared with mac-test-refusal.sh. Without them no segment is read.
. "${BASH_SOURCE[0]%/*}/lib/shell-words.sh" 2>/dev/null
type load_words >/dev/null 2>&1 || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load .claude/hooks/lib/shell-words.sh, so it cannot screen this command. Restore it (git checkout .claude/hooks/lib/shell-words.sh) and retry.
Instead: git checkout .claude/hooks/lib/shell-words.sh, then run the command again." >&2; exit 2; }

# SUBST = $1 with every `$NAME` / `${NAME}` (name $2) replaced by $3.
subst_var() {
  local RE='^(.*)\$'"$2"'([^A-Za-z0-9_].*)?$'
  SUBST=${1//"\${$2}"/"$3"}
  while [[ $SUBST =~ $RE ]]; do SUBST=${BASH_REMATCH[1]}$3${BASH_REMATCH[2]}; done
}

# Resolve the literal aliases a call sets for ITSELF: `WT=/path; git -C "$WT" log`
# and `for f in /tmp/x/*.log; do rg y "$f"; done`. Only a bare literal
# assignment, a one-word for-list and $HOME resolve; nothing is executed. Any
# other `$` stays in the text, and every check below still refuses it. The
# worktree and search checks read SEG_TEXT, so an alias is judged exactly like
# the path it names.
ASSIGN_RE='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|'"'[^']*'"'|\$\(.*\)|[^[:space:]"'"'"']*)[[:space:]]*$'
FOR_RE='^[[:space:]]*for[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+in[[:space:]]+(.+)$'
# `[while] [IFS=] read [-r] VAR`: VAR takes the fed-in lines one at a time.
# search_text puts these two lines round each substitution it lifts out. A substitution runs in its own
# shell, so what it assigns and where it cds end with it: the state is kept at the first and put back at the second.
SUB_OPEN=$'\001(' SUB_CLOSE=$'\001)'
READ_RE='^[[:space:]]*(while[[:space:]]+)?(IFS=[^[:space:]]*[[:space:]]+)?read([[:space:]]+-r)?[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(<[[:space:]]*[^[:space:]]+[[:space:]]*)?$'
load_segments() { # $1 = a command text, $2 = the prefix of the four arrays to fill
  local -n L_PIPE=$2_PIPE L_TEXT=$2_TEXT L_FOR=$2_FOR L_READ=$2_READ
  local -A ALIAS=() FORLIST=() READVAR=()
  local LINE TEXT NAME VAL
  local -a KEPT=() # one entry per open substitution: a nested one puts back the outer one's state, not the call's
  L_PIPE=(); L_TEXT=(); L_FOR=(); L_READ=()
  while IFS= read -r LINE; do
    TEXT=${LINE:1}
    subst_var "$TEXT" HOME "$HOME"; TEXT=$SUBST
    for NAME in "${!ALIAS[@]}"; do
      subst_var "$TEXT" "$NAME" "${ALIAS[$NAME]}"
      [ "$SUBST" = "$TEXT" ] && continue
      TEXT=$SUBST
    done
    if [ "$TEXT" = "$SUB_OPEN" ]; then KEPT+=("$(declare -p ALIAS FORLIST READVAR)")
    elif [ "$TEXT" = "$SUB_CLOSE" ]; then [ ${#KEPT[@]} -eq 0 ] || { eval "${KEPT[-1]}"; unset 'KEPT[-1]'; }
    elif [[ ${LINE:0:1} == [23] && $TEXT =~ $ASSIGN_RE ]]; then
      # After `&&` or `||` the assignment may or may not run, so the name's value is unknown: no alias, and any
      # earlier one is dropped too, or `F=/tmp/x; true && F=.; rg foo "$F"` is judged as /tmp/x.
      unset "ALIAS[${BASH_REMATCH[1]}]" "FORLIST[${BASH_REMATCH[1]}]" "READVAR[${BASH_REMATCH[1]}]"
    elif [[ $TEXT =~ $ASSIGN_RE ]] || [[ $TEXT =~ $FOR_RE ]]; then
      NAME=${BASH_REMATCH[1]}; VAL=${BASH_REMATCH[2]}
      VAL=${VAL%"${VAL##*[![:space:]]}"}
      unset "ALIAS[$NAME]" "FORLIST[$NAME]" "READVAR[$NAME]"
      case "$VAL" in
        # A multi-word for-list of literals stays unsubstituted; the search check
        # below judges every word it can take.
        *'$'*|*'`'*) ;;
        *[[:space:]]*) [[ $TEXT =~ $FOR_RE ]] && { VAL=${VAL//\"/}; FORLIST[$NAME]=${VAL//\'/}; } ;;
        *) VAL=${VAL//\"/}; ALIAS[$NAME]=${VAL//\'/} ;;
      esac
    elif [[ $TEXT =~ $READ_RE ]]; then
      NAME=${BASH_REMATCH[4]}
      unset "ALIAS[$NAME]" "FORLIST[$NAME]"
      READVAR[$NAME]=1
    fi
    # The loop bindings in force at THIS segment, so a later reassignment of the
    # variable does not change how an earlier search is judged.
    L_FOR+=("$(for NAME in "${!FORLIST[@]}"; do printf '%s\t%s\n' "$NAME" "${FORLIST[$NAME]}"; done)")
    L_READ+=(" ${!READVAR[*]} ")
    L_PIPE+=("${LINE:0:1}"); L_TEXT+=("$TEXT")
  done < <(split_search_segments "$1")
}
SEG_PIPE=(); SEG_TEXT=(); SEG_FOR=(); SEG_READ=()
load_segments "$CMD" SEG

# Refuse an in-place source write from the shell: it skips every
# Edit/Write hook -- the content tripwires, the audits, lint-fix and the
# main-edit guard. One builder made 19 of its edits that way on 2026-09-18.
# Scratch under /tmp, ~/.claude and unit briefs stay writable: briefs are
# main's to write by heredoc. The gitignored local
# ledgers (routing log, approvals) never ship, so no Edit hook guards them.
# Scratch is /tmp and the system temp folder under both their names (macOS
# resolves /tmp to /private/tmp), and a path under a variable this command sets
# once, from mktemp: a fixture tree there may hold a folder named
# .claude or src.
# shortcut: judges the command text only: a `find .` root or a target computed
# at run time (`$(...)`, a bare variable) passes; widen when one shows up.
src_path() { # $1 = a path word, quotes allowed
  local P=${1//[\'\"]/} V
  case "$P" in '~/'*) P=$HOME/${P#\~/} ;; esac
  case "$P" in /*) P=$(realpath -m -- "$P") ;; *) [[ /$P/ == */../* ]] && P=$(realpath -m -- "$P") ;; esac
  if [[ $P =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/ ]]; then
    V="(^|[^A-Za-z0-9_])${BASH_REMATCH[1]}="
    [ "$(grep -oE "$V" <<<"$CMD" | wc -l)" -eq 1 ] && grep -qE "$V\"?\\\$\(mktemp[[:space:])]" <<<"$CMD" && return 1
  fi
  # A markdown file is prose (G3): the Edit-time hooks that a shell write skips matter for code, not for a plan or a doc.
  case "$P" in *.md) return 1 ;; esac
  case "$P" in /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*|"$HOME"/.claude/*|*/.claude/briefs/*|.claude/briefs/*) return 1 ;; esac
  case "$P" in */.claude/routing-log|.claude/routing-log|*/.claude/approvals/*|.claude/approvals/*) return 1 ;; esac
  [[ /$P =~ /(src|shared|lambdas|infra|web|scripts|ml|\.claude)/ ]]
}
write_block() {
  echo "BLOCKED: an in-place write to $1 from the shell skips every Edit/Write hook (content tripwires, audits, lint-fix, the main-edit guard). Use Edit -- parallel Edit calls in one turn for many files -- or serena replace_content / replace_symbol_body. Writes under /tmp stay allowed.${2:+ $2}
Instead: make this change with the Edit tool, not a shell write." >&2
  exit 2
}
# SCRIPT = only the python/node invocations and their heredoc bodies. Scanning
# the whole command refused `echo "open('src/x', 'w')"` beside any node call,
# and no retry could clear it.
# A heredoc body is script when the declaring segment, or a segment piped
# after it on that line, runs python/node; the rest is split as one text so a
# multi-line quote holds.
# ponytail: knows `env`, `command`, `exec`, `nice`, `time`, `timeout`, `sudo`
# wrappers only (a bare number is timeout's duration). Add one when it shows up.
script_head() {
  load_words "$1"; set -- "${WORDS[@]}"
  while [ $# -gt 0 ]; do
    [[ ${1-} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && { shift; continue; }
    case "${1-}" in
      env|command|exec|nice|time|timeout|sudo|[0-9]*) shift ;;
      -u|-g|-n|-k|-s|-a|--adjustment|--signal|--kill-after) [ $# -ge 2 ] || return 1; shift 2 ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  case "${1##*/}" in python|python3|python3.*|node) SH_ARGS=("${@:2}"); return 0 ;; esac
  return 1
}
# A runner reads its program from stdin only with no -c/-e/-m/-p and no script
# file (or `-`); `python3 -c "...stdin.read()"` reads the heredoc as data.
stdin_runner() {
  script_head "$1" || return 1
  local A SKIP=0
  for A in "${SH_ARGS[@]}"; do
    [ "$SKIP" = 1 ] && { SKIP=0; continue; }
    case "$A" in
      '>'|'>>'|'<'|[0-9]'>'|[0-9]'>>'|'&>') SKIP=1 ;;
      -) return 0 ;;
      '>'*|'<'*|[0-9]'>'*|'&>'*) ;;
      -c|-e|-m|-p|--eval|--print|-c*|-e*|-m*) return 1 ;;
      # Options whose value is the next word, not a script file.
      -W|-X|--check-hash-based-pycs|-r|--require|--import|--loader|--input-type) SKIP=1 ;;
      -*) ;;
      *) return 1 ;;
    esac
  done
}
# The delimiter of an unquoted `<<` (never `<<<`); HQ carries the open quote
# across calls, so `node -e "x('<<EOF')"` declares nothing, even over lines.
HQ=""
heredoc_delim() { # $1 = a segment
  local T=$1 I C
  for ((I=0; I<${#T}; I++)); do
    C=${T:I:1}
    if [ "$C" = '\' ] && [ "$HQ" != "'" ]; then I=$((I+1)); continue; fi
    if [ -n "$HQ" ]; then [ "$C" = "$HQ" ] && HQ=""; continue; fi
    case "$C" in
      "'"|'"') HQ=$C ;;
      '<') [ "${T:I:2}" = '<<' ] && [ "${T:I+2:1}" != '<' ] && { [ "$I" = 0 ] || [ "${T:I-1:1}" != '<' ]; } || continue
           [[ ${T:I+2} =~ ^-?[[:space:]]*[\'\"]?([^[:space:]\'\";|\&\<\>\(\)]+) ]] && { DELIM=${BASH_REMATCH[1]}; return 0; } ;;
    esac
  done
  return 1
}
SCRIPT="" SHELL_TEXT="" DELIM="" KEEP=0
while IFS= read -r LINE; do
  if [ -n "$DELIM" ]; then
    if [ "$(sed 's/^[[:space:]]*//' <<<"$LINE")" = "$DELIM" ]; then DELIM=""; else [ "$KEEP" = 1 ] && SCRIPT+=$LINE$'\n'; fi
    continue
  fi
  SHELL_TEXT+=$LINE$'\n'
  PIPED=0
  while IFS= read -r SEG; do
    if [ "$PIPED" = 1 ]; then
      [ "${SEG:0:1}" = 1 ] || PIPED=0
      [ "$PIPED" = 1 ] && stdin_runner "${SEG:1}" && KEEP=1
    fi
    heredoc_delim "${SEG:1}" || continue
    KEEP=0 PIPED=1; script_head "${SEG:1}" && KEEP=1
  done < <(split_search_segments "$LINE")
done <<<"$CMD"
RD_RE='^[0-9&]?>>?[|]?(.*)$' # a redirect's target. Shell text only: heredoc bodies, quoted or escaped `>` are data.
mapfile -d '' SH_SEGS < <(split_search_segments "$SHELL_TEXT" '\0')
for i in "${!SH_SEGS[@]}"; do
  SEG=${SH_SEGS[i]}
  script_head "${SEG:1}" && SCRIPT+=${SEG:1}$'\n'
  # One left-to-right pass, escape pairs before quotes: `\\>` keeps its redirect, `\'` opens no quote.
  # A data `>` becomes `_`, never nothing: deleting it turned `"\>"` into `"\"`, whose escaped quote swallowed a later redirect.
  # A segment with no `>` has no redirect, so perl is not started for it.
  if [[ ${SEG:1} == *'>'* ]]; then
    load_words "$(perl -0pe 's/(\\.)|(\x27[^\x27]*\x27|"(?:\\.|[^"\\])*")/defined $1 ? ($1 eq "\\>" ? "_" : $1) : ($2 =~ tr|>|_|r)/gse' <<<"${SEG:1}")"
    for ((K=0; K<${#WORDS[@]}; K++)); do
      [[ ${WORDS[K]} =~ $RD_RE ]] && T=${BASH_REMATCH[1]:-${WORDS[K+1]-}} && src_path "$T" && write_block "$T"
    done
  fi
  load_words "${SEG:1}"; set -- "${WORDS[@]}"
  while [ $# -gt 0 ] && [[ ${1-} == *=* && ${1-} != */* ]]; do shift; done
  # A copy onto a source file skips the same hooks as a redirect does: tee writes
  # every operand, the others the -t folder or else the last of two operands.
  # Not followed: dd, rsync, ln, an archive unpacked or a patch applied over the
  # tree, and a copy behind a wrapper (env, sudo).
  case "${1##*/}" in cp|mv|install|tee)
    HEAD=${1##*/} OPS=() DIR="" SKIP=0; shift
    for W in "$@"; do
      [ "$SKIP" = 1 ] && { SKIP=0; continue; }
      [ "$SKIP" = 2 ] && { SKIP=0 DIR=$W; continue; }
      case "$W" in
        '<'|'>'|'>>'|[0-9]'>'|[0-9]'>>'|'&>') SKIP=1 ;;
        '<'*|'>'*|[0-9\&]'>'*) ;;
        -t|--target-directory) SKIP=2 ;;
        --target-directory=*) DIR=${W#*=} ;;
        -m|-o|-g) [ "$HEAD" = install ] && SKIP=1 ;;
        -*) ;;
        *) OPS+=("$W") ;;
      esac
    done
    if [ "$HEAD" != tee ]; then
      if [ -n "$DIR" ]; then OPS=("$DIR"); elif [ ${#OPS[@]} -ge 2 ]; then OPS=("${OPS[-1]}"); else OPS=(); fi
    fi
    for W in "${OPS[@]}"; do
      { src_path "$W" || src_path "${W%/}/x"; } \
        && write_block "$W" "$(case "$HEAD" in cp|mv) echo 'And to rename or move a tracked file use git mv' ;; esac)"
    done
    continue ;;
  esac
  # sed's files from find's roots, or xargs' producer operands less rg/grep's patterns (each -e/-f value, else the first operand unless `--files` sits anywhere).
  TGT=(); case "${1##*/}" in
    find) shift; while [ $# -gt 0 ] && [[ $1 != [-\!\(]* ]]; do TGT+=("$1/"); shift; done; while [ $# -gt 0 ] && [[ $1 != -exec* && $1 != -ok* ]]; do shift; done; shift ;;
    xargs) shift; while [[ ${1-} == -* ]]; do [[ $1 == -[IdEnPLsa] ]] && shift; shift; done
           for ((J=i; J>0; J--)); do [ "${SH_SEGS[J]:0:1}" = 1 ] || break; mapfile -t -O ${#TGT[@]} TGT < <(seg_words "${SH_SEGS[J-1]:1}" | awk 'NR==1 { r = g = $0 ~ /(^|\/)(rg|e?grep)$/; next } s { s = 0; next } r && (match($0, /^-[A-Za-dg-z]*[ef]/) || /^--(regexp|file)(=|$)/) { g = 0; s = RLENGTH == length($0) || /^--(regexp|file)$/; next } r && /^--(files|type-list)$/ { g = 0 } /^-/ { next } { o[++n] = $0 } END { for (k = 1 + g; k <= n; k++) print o[k] "/" }'); done ;;
  esac
  case "${1##*/}" in
    sed) CODE_FLAGS=ef ;;
    perl) CODE_FLAGS=eE ;;
    *) continue ;;
  esac
  shift
  printf '%s\n' "$@" | grep -qE '^-[A-Za-z0-9]*i|^--in-place' || continue
  for W in "${TGT[@]}"; do src_path "$W" && write_block "${W%/}"; done
  # The script is text, not a target: `s|/src/|/dist/|` on a /tmp file is fine.
  HAVE_CODE=0 SKIP=0
  for W in "$@"; do
    [ "$SKIP" = 1 ] && { SKIP=0; continue; }
    case "$W" in
      --expression=*|--file=*) HAVE_CODE=1; continue ;;
      --expression|--file) HAVE_CODE=1; SKIP=1; continue ;;
      --*) continue ;;
      -?*)
        # A bundle stops at `i`, whose attached text is the backup suffix; a
        # code flag takes the rest of the word, or the next word when it ends.
        for ((J=1; J<${#W}; J++)); do
          C=${W:J:1}; [ "$C" = i ] && break
          [[ $CODE_FLAGS == *"$C"* ]] && { HAVE_CODE=1; [ $((J+1)) -lt ${#W} ] || SKIP=1; break; }
        done
        continue ;;
    esac
    [ "$HAVE_CODE" = 0 ] && { HAVE_CODE=1; continue; }
    src_path "$W" && write_block "$W"
  done
done
if [ -n "$SCRIPT" ]; then
  # A write's target is judged as written when literal; a variable by its literal
  # assignments; anything else by every quoted path the script names.
  # A move or copy (os.replace/rename, shutil.copy*/copytree/move, fs renameSync/copyFileSync) is judged on
  # its DESTINATION alone (second argument or `dst=`, wherever it stands): a quoted literal, bare or in a Path
  # wrapper, or a variable with such an assignment. Any other destination (os.path.join, an f-string, `+`, `/`,
  # a call) is refused with the plain cp/mv hint, never judged by its source (guard-python-copy-class).
  # A keyword write target (open's `file=`) is judged as written too.
  # One pass per quote kind: a span holding the other kind is the `-c "..."` wrapper around the script, not a path.
  LITERALS=$(grep -oE "'[^']*'" <<<"$SCRIPT" | grep -v '"'; grep -oE '"[^"]*"' <<<"$SCRIPT" | grep -v "'")
  # One argument, holding at most one level of nested parentheses (a Path(...) source or destination).
  PY_ARG='([^,()]|\([^()]*\))+'
  PY_MV='(os\.(replace|rename)|shutil\.(copy(2|file|tree)?|move)|\.(renameSync|copyFileSync))\('
  LIT_RE="^[rRbBuU]*('[^']*'|\"[^\"]*\")$"
  MV_HINT="For a scratch copy use plain cp or mv in the shell, or give the destination as a quoted literal ('/tmp/x' or Path('/tmp/x'))."
  # A move or copy whose two arguments cannot be read (deeper nesting, split over lines) cannot be judged at all.
  [ "$(grep -oE "$PY_MV" <<<"$SCRIPT" | wc -l)" -gt "$(grep -oE "${PY_MV}${PY_ARG},[[:space:]]*${PY_ARG}" <<<"$SCRIPT" | wc -l)" ] \
    && { echo "BLOCKED: an inline move or copy here has arguments this guard cannot read, so its destination cannot be checked against the repo. $MV_HINT
Instead: cp <source> /tmp/<name>" >&2; exit 2; }
  while IFS= read -r T; do
    [ -n "$T" ] || continue
    MV=0; [[ $T == "MV "* ]] && { MV=1; T=${T#MV }; }
    # A Path wrapper, bare or module-qualified (`pathlib.Path(`), arrives with or without its `)` (a write
    # extractor stops there) and may already have lost its `Path(`; the literal or variable inside is the target.
    T=$(sed -E 's/^(dst|file)[[:space:]]*=[[:space:]]*//; s/^([A-Za-z_][A-Za-z0-9_]*\.)*Path\([[:space:]]*//; s/^([^()]*[^()[:space:]])[[:space:]]*\)$/\1/' <<<"$T")
    # Another keyword in the target slot is the source of a call written dst-first; its dst= match judges the call.
    [[ $T =~ ^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*= ]] && continue
    if [[ $T =~ $LIT_RE ]]; then CANDS=${BASH_REMATCH[1]}
    elif [[ $T =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && CANDS=$(grep -oE "(^|[^A-Za-z0-9_.])${T}[[:space:]]*=[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*\.)*Path\()?[rRbBuU]*['\"][^'\"]*['\"]\)?[[:space:]]*(;|$)" <<<"$SCRIPT" | sed -E 's/^[^=]*=//' | grep -oE "['\"][^'\"]*['\"]"); then :
    elif [ "$MV" = 1 ]; then
      echo "BLOCKED: the destination of this inline move or copy ($T) is not a quoted path, so it cannot be checked against the repo. $MV_HINT
Instead: cp <source> /tmp/<name>" >&2
      exit 2
    else
      T=$(sed -E 's/^[fFrRbBuU]+(['"'"'"])/\1/' <<<"$T")
      case "$T" in \'*|\"*) CANDS=$T ;; *) CANDS=$LITERALS ;; esac
    fi
    while IFS= read -r C; do [ -n "$C" ] && src_path "$C" && write_block "$C"; done <<<"$CANDS"
  done < <(grep -oE "${PY_MV}([[:space:]]*${PY_ARG},)*[[:space:]]*dst[[:space:]]*=[[:space:]]*${PY_ARG}" <<<"$SCRIPT" \
    | sed -E 's/^.*dst[[:space:]]*=[[:space:]]*/MV /; s/[[:space:]]+$//'
    grep -oE "${PY_MV}${PY_ARG},[[:space:]]*${PY_ARG}" <<<"$SCRIPT" \
    | sed -E "s/^[^(]*\(${PY_ARG},[[:space:]]*/MV /; s/[[:space:]]+\$//"
    grep -oE "(Path\([^)]*\)|[A-Za-z_][A-Za-z0-9_]*)\.open\([[:space:]]*(mode[[:space:]]*=[[:space:]]*)?['\"][rbt]*[wax+]|open\([[:space:]]*[^,)]+,[[:space:]]*(mode[[:space:]]*=[[:space:]]*)?['\"][rbt]*[wax+]|(Path\([^)]*\)|[A-Za-z_][A-Za-z0-9_]*)\.write_(text|bytes)\(|(writeFileSync|writeFile|appendFileSync|appendFile|createWriteStream)\([[:space:]]*[^,)]+" <<<"$SCRIPT" \
    | sed -E 's/\.open\(.*$//; s/^open\([[:space:]]*([^,)]+),.*/\1/; s/\.write_(text|bytes)\($//; s/^[A-Za-z]+\([[:space:]]*//; s/[[:space:]]+$//')
fi

# Point a caller hunt at serena's reference lookup: one cut ran 38 rg
# searches and no find_referencing_symbols call (2026-09-18). A HINT, not a
# refusal: 73% of refusals were retried unchanged, so the block cost a
# turn and redirected nothing. The search runs, and the first hunt of a session
# carries the pointer as additionalContext; a lookup naming the symbol clears
# it. Stands down where serena cannot answer: read-tracker.sh marks an errored
# serena call.
HUNT_KEY="" HUNT_SEEN=""
HUNT_HINT=""
caller_hunt() {
  local P ID HIT=0 IDS=() MISSING=() ROOT
  case "$PATTERN" in *\'*|*\"*) return 0 ;; esac
  for P in "${PATHS[@]}"; do [[ /$P/ =~ /(src|shared|lambdas|infra|web)/ ]] && HIT=1; done
  [ "$HIT" = 1 ] || return 0
  mapfile -t IDS < <(grep -oE '[A-Za-z_][A-Za-z0-9_]*\\?\(|\\b[A-Za-z][a-z0-9]+[A-Z][A-Za-z0-9]*|[A-Za-z][a-z0-9]+[A-Z][A-Za-z0-9]*\\b' <<<"$PATTERN" \
    | sed -E 's/\\?\($//; s/\\b//g' | grep -vxE 'if|for|while|switch|catch|function|return' | sort -u)
  [ ${#IDS[@]} -gt 0 ] || return 0
  # The session's key is read here, where a hunt needs it, not on every call (one jq a call saved).
  if [ -z "$HUNT_KEY" ]; then
    HUNT_KEY=$(echo "$INPUT" | jq -r '.session_id // empty'); HUNT_KEY=${HUNT_KEY:-${CLAUDE_SESSION_ID:-$PPID}}
    HUNT_SEEN="/tmp/claude-caller-hunt-$HUNT_KEY"
  fi
  [ -e "/tmp/claude-serena-down-$HUNT_KEY" ] && return 0
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
  jq -e --arg p "${ROOT:-$PWD}" '((.projects[$p].disabledMcpServers // []) | index("serena")) != null
    or (.mcpServers.serena == null and .projects[$p].mcpServers.serena == null)' "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" >/dev/null 2>&1 && return 0
  for ID in "${IDS[@]}"; do grep -qxF "refs:$ID" "/tmp/claude-serena-tracker-$HUNT_KEY" 2>/dev/null || MISSING+=("$ID"); done
  [ ${#MISSING[@]} -gt 0 ] || return 0
  [ -e "$HUNT_SEEN" ] && return 0
  HUNT_HINT="This looks like a caller hunt for ${MISSING[*]}. serena find_referencing_symbols on the symbol answers from the language server, not from text. Said once per session; the search ran."
}

# Block a repo-wide text search (.claude/rules/agents.md, Token efficiency):
# every path an `rg`, or a `grep` with a recursive flag, names must be bounded,
# and one with no path must read a pipe. Bounded is any path, relative ones
# resolved against the command's own `cd`, that does not normalize to the
# filesystem root, a checkout root, a parent of one, or a bare wildcard; a glob
# is judged again per match (a top-level folder off an old allowlist, a
# glob and a path after a `cd` were all refused). An unresolved variable is not
# bounded. The pattern and option values are not paths, so a slash in the
# pattern proves nothing and `-g '*.ts'` is not an operand.
# Root cause: a whole-repo `rg` from main took the session down on 2026-09-10.
SEARCH_BASE=$PWD
RG_SHORT_VALUED=ABCEefgjMmrtT
GREP_SHORT_VALUED=ABCDdefm
RG_LONG_VALUED=" --glob --iglob --type --type-not --type-add --type-clear --max-count --context --after-context --before-context --max-depth --maxdepth --threads --sort --sortr --encoding --max-columns --max-filesize --replace --path-separator --pre --pre-glob --ignore-file --colors --color --context-separator --field-match-separator --field-context-separator --dfa-size-limit --regex-size-limit --engine --hyperlink-format "
GREP_LONG_VALUED=" --include --exclude --exclude-dir --exclude-from --max-count --context --after-context --before-context --devices --directories --label --binary-files --group-separator "
SEARCH_ROOTS=""
SEARCH_WARN=""

root_like() { # $1 = normalized absolute path
  local P=$1 R Q=${1%/*}
  [ "$P" = / ] && return 0
  # Home holds every checkout even when this one lives elsewhere (a Mac /tmp checkout).
  [ "$P" = "$(realpath -m -- "$HOME")" ] && return 0
  case "$Q" in *[*?[{]*) return 0 ;; esac
  # A bare wildcard is every entry of its folder: as wide as that folder.
  case "${P##*/}" in *[!*?]*) ;; *) root_like "${Q:-/}"; return ;; esac
  [ -e "$P/.git" ] && return 0
  compgen -G "$P/*/.git" >/dev/null && return 0
  [ -n "$SEARCH_ROOTS" ] || SEARCH_ROOTS="$(git rev-parse --show-toplevel 2>/dev/null) $(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  for R in $SEARCH_ROOTS; do
    case "${R%/.git}/" in "$P"/*) return 0 ;; esac
  done
  return 1
}

search_bounded() {
  local OP=$1 P M
  # The `)` that closes a subshell is not part of the path, unless a path has it.
  [[ $OP != *')' ]] || [ -e "$OP" ] || [ -e "$SEARCH_BASE/$OP" ] || OP=${OP%"${OP##*[!)]}"}
  # A HOME-ROOTED PATH IS A REAL PATH. A session's own transcripts live
  # under ~/.claude/projects/<project>/, outside every checkout, and `~/...` or
  # `$HOME/...` was refused as unbounded before it was ever resolved. Expand the
  # two home forms, then judge the result exactly like any other absolute path:
  # a bare `~` still fails, because the checkout itself lives under it.
  case "$OP" in
    '~'|'$HOME') OP=$HOME ;;
    '~/'*) OP=$HOME/${OP#'~/'} ;;
    '$HOME/'*) OP=$HOME/${OP#'$HOME/'} ;;
  esac
  # A variable is judged as a glob from its first `$` on (/tmp/conveyor/x-$n.log
  # as /tmp/conveyor/x-*), so the glob rules below bound it. A bare `$X` has no
  # fixed prefix and stays refused.
  case "$OP" in *'$'*|*'`'*)
    OP=${OP%%[\$\`]*}
    [ -n "$OP" ] || return 1
    OP="$OP*"
  esac
  case "$OP" in
    /*) P=$OP ;;
    *) [ -n "$SEARCH_BASE" ] || return 1; P=$SEARCH_BASE/$OP ;;
  esac
  P=$(realpath -m -- "$P" 2>/dev/null) || return 1
  # Scratch space is where logs live (G4): an absolute /tmp path is never an unbounded search, whatever sits in it.
  # Unless this session's own checkout lives under scratch (a /tmp checkout, a test fixture): then a glob or a parent
  # of the checkout would pass, so the root test below judges every path.
  case "$P" in /tmp|/tmp/*|/private/tmp|/private/tmp/*|/var/folders/*|/private/var/folders/*)
    M=$(git rev-parse --show-toplevel 2>/dev/null)
    case "${M:-/nonexistent}" in /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;; *) return 0 ;; esac ;;
  esac
  root_like "$P" && return 1
  case "$P" in *[*?[]*)
    while IFS= read -r M; do root_like "$(realpath -m -- "$M")" && return 1; done < <(compgen -G "$P")
  esac
  return 0
}

# The search rule reads its own text: the command with every live
# `$( )` and backtick span lifted out to a line of its own after the command
# that holds it (a `$()` stays in its place), so a search inside one is judged
# as the command it is; and with a note's text taken out, so prose that names
# a search is not. A note is a here-document cat or tee reads, alone on its
# line, with nothing after its end word; under an end word with no quote its
# substitutions still run and are judged. Any other here-document is read as
# commands, since a shell may be fed it or a later line may run the file. So a
# note whose text names a search, followed by another command in the same
# call, is still refused: write the note in its own call or with the Write tool.
# A substitution inside another is lifted the same way inside the outer one's
# own lines, so it is judged after the outer commands before it and its state
# ends where it closes.
# A seat belt against an honest mistake, not a wall. Not followed: `eval`, a
# command held in a variable, `bash -c '...'` text, process substitution, and
# nesting deeper than the self-test covers.
_st_open() { BUF+=("$OUT"); RET+=("$MODE"); DEP+=("$D"); KIND+=("$1"); HELD+=("$PEND"); OUT=""; PEND=""; D=0; MODE=code; }
_st_close() {
  case "$MODE" in sq|asq) OUT+="'" ;; dq) OUT+='"' ;; esac
  PEND=${HELD[-1]}$SUB_OPEN$NL$OUT$NL$PEND$SUB_CLOSE$NL; OUT=${BUF[-1]}'$()'; MODE=${RET[-1]}; D=${DEP[-1]}
  unset 'BUF[-1]' 'RET[-1]' 'DEP[-1]' 'KIND[-1]' 'HELD[-1]'
}
_st_sub() { # opens or closes a substitution at I; fails when none starts or ends there
  if [ "$C$N" = '$(' ]; then I=$((I+1)); _st_open p
  elif [ "$C" != '`' ]; then return 1
  elif [ ${#KIND[@]} -gt 0 ] && [ "${KIND[-1]}" = b ]; then _st_close
  else _st_open b; fi
}
NOTE_RE='(^|[;&|])[[:space:]]*(cat|tee)([[:space:]][^;&|]*)?$'
search_text() {
  # Plain arithmetic goes first, as for the end-word check: its `<<` is a shift.
  # With no `$((` the sed changes nothing; only the trailing newlines its `$( )` drops are dropped (one sed saved).
  local TEXT=$1
  case "$TEXT" in
    *'$(('*) TEXT=$(sed -E 's/\$\(\([A-Za-z0-9_ +*\/%()<>-]*\)\)/0/g' <<<"$TEXT") ;;
    *) while [[ $TEXT == *$'\n' ]]; do TEXT=${TEXT%$'\n'}; done ;;
  esac
  local OUT="" PEND="" MODE=code NL=$'\n' C N I J T R D=0 LS=0 TAG="" TQ="" DASH="" NOTE=0 BODY="" BQ="" BASE=0 BD=0
  local -a BUF=() RET=() DEP=() KIND=() HELD=()
  for ((I=0; I<${#TEXT}; I++)); do
    C=${TEXT:I:1}; N=${TEXT:I+1:1}
    if [ "$C" = "$NL" ]; then
      # A body ends where bash ends it, whatever its text left open.
      if [ -n "$BODY" ]; then
        T=${TEXT:LS:I-LS}; [ -z "$DASH" ] || T=${T#"${T%%[!	]*}"}
        if [ "$T" = "$TAG" ]; then
          while [ ${#BUF[@]} -gt "$BASE" ]; do _st_close; done
          OUT+=$BQ; BQ="" BODY="" TAG="" MODE=code D=$BD
        fi
      fi
      LS=$((I+1))
    fi
    if [ "$MODE" = comment ]; then [ "$C" = "$NL" ] || continue; MODE=code; fi
    case "$MODE" in
      sq) OUT+=$C; [ "$C" = "'" ] && MODE=code ;;
      # `$'...'`: a `\'` does not end it, so it goes on as a plain quoted span.
      asq) if [ "$C" = '\' ] && [ "$N" != "$NL" ]; then OUT+=_; I=$((I+1))
           else OUT+=$C; [ "$C" = "'" ] && MODE=code; fi ;;
      dq)
        if [ "$C" = '\' ] && [ "$N" != "$NL" ]; then OUT+=$C$N; I=$((I+1))
        elif _st_sub; then :
        else OUT+=$C; [ "$C" = '"' ] && MODE=code; fi ;;
      # A note under an end word with no quote: only what it runs is kept.
      nbody) if [ "$C" = '\' ]; then [ "$N" = "$NL" ] || I=$((I+1)); else _st_sub; fi ;;
      # Any other body is commands: BQ follows its quotes as the segment split
      # will, to close an open one at the end word. With no quote on the end
      # word bash runs every substitution in it, single quotes or not.
      sbody)
        if [ "$C" = '\' ] && [ "$N" != "$NL" ] && { [ "$BQ" != "'" ] || { [ -z "$TQ" ] && [[ $N == [\$\`\\] ]]; }; }; then OUT+=$C$N; I=$((I+1))
        elif { [ -z "$TQ" ] || [ "$BQ" != "'" ]; } && _st_sub; then :
        else
          OUT+=$C
          if [ -n "$BQ" ]; then [ "$C" = "$BQ" ] && BQ=""; else case "$C" in "'"|'"') BQ=$C ;; esac; fi
        fi ;;
      code)
        case "$C" in
          '\') I=$((I+1)); [ "$N" = "$NL" ] || OUT+=$C$N ;;
          "'") MODE=sq; OUT+=$C ;;
          '"') MODE=dq; OUT+=$C ;;
          '#') if [ "$I" -gt 0 ] && [[ ${TEXT:I-1:1} != [[:space:]\;\&\|\(] ]]; then OUT+=$C; else MODE=comment; fi ;;
          '$') if [ "$N" = "'" ]; then MODE=asq; OUT+=$N; I=$((I+1)); else _st_sub || OUT+=$C; fi ;;
          '`') _st_sub ;;
          '(') D=$((D+1)); OUT+=$C ;;
          ')') if [ "$D" -gt 0 ]; then D=$((D-1)); OUT+=$C
               elif [ ${#KIND[@]} -gt 0 ] && [ "${KIND[-1]}" = p ]; then _st_close
               else OUT+=$C; fi ;;
          '<') if [ "$N" != '<' ]; then OUT+=$C
               elif [ "${TEXT:I+2:1}" = '<' ]; then OUT+='<<<'; I=$((I+2))
               else
                 # The end word is plain here: every other one was refused above.
                 J=$((I+2)) T="" R=""
                 [ "${TEXT:J:1}" = '-' ] && { J=$((J+1)); R=1; }
                 while [[ ${TEXT:J:1} == [[:blank:]] ]]; do J=$((J+1)); done
                 TQ=""; case "${TEXT:J:1}" in "'"|'"'|'\') TQ=1 ;; esac
                 while [[ -n ${TEXT:J:1} && ${TEXT:J:1} != [[:space:]\;\&\|\(\)\<\>] ]]; do T+=${TEXT:J:1}; J=$((J+1)); done
                 T=${T//[\'\"\\]/}
                 if [ -n "$T" ]; then
                   TAG=$T DASH=$R NOTE=0
                   [ ${#BUF[@]} -eq 0 ] && [ -z "$DASH" ] && [[ ${TEXT:LS:I-LS} =~ $NOTE_RE ]] && NOTE=1
                 fi
                 OUT+='<<'; I=$((I+1))
               fi ;;
          ';'|'|'|'&'|"$NL")
            [ "$C" = "$NL" ] || NOTE=0
            # A lifted span is judged where it ran: after the command that holds it.
            if [ -n "$PEND" ] && [ "$C$N" != '&>' ] && [[ $C != '&' || $N == '&' || ${OUT: -1} != [\<\>] ]]; then OUT+=$NL$PEND; PEND=""; fi
            OUT+=$C
            if [ "$C" = "$NL" ] && [ -n "$TAG" ]; then
              R=${TEXT:I+1}; R=${R%"${R##*[![:space:]]}"}; T=${R##*"$NL"}
              if [ "$NOTE" = 1 ] && [ "$T" = "$TAG" ] && [[ $NL${R%"$T"} != *"$NL$TAG$NL"* ]]; then
                [ -z "$TQ" ] || break
                MODE=nbody TAG=""
              else BODY=1 MODE=sbody BASE=${#BUF[@]} BD=$D BQ=""; fi
            fi ;;
          *) OUT+=$C ;;
        esac ;;
    esac
  done
  while [ ${#BUF[@]} -gt 0 ]; do _st_close; done
  printf '%s\n%s' "$OUT" "$PEND"
}
# The command's search text, read once: the search, aws and card rules below all judge it, and each walk costs a
# character at a time.
SEARCH_CMD=$(search_text "$CMD")
SRCH_PIPE=(); SRCH_TEXT=(); SRCH_FOR=(); SRCH_READ=()
case "$CMD" in *rg*|*grep*) load_segments "$SEARCH_CMD" SRCH ;; esac

KEPT_BASE=()
for i in "${!SRCH_TEXT[@]}"; do
  case "${SRCH_TEXT[i]}" in
    "$SUB_OPEN") KEPT_BASE+=("$SEARCH_BASE"); continue ;;
    "$SUB_CLOSE") [ ${#KEPT_BASE[@]} -eq 0 ] || { SEARCH_BASE=${KEPT_BASE[-1]}; unset 'KEPT_BASE[-1]'; }; continue ;;
  esac
  load_words "${SRCH_TEXT[i]}"; set -- "${WORDS[@]}"
  TOOL=${1-}; [ $# -gt 0 ] && shift
  # Follow the command's own `cd`; one this cannot resolve leaves relative
  # paths unbounded. A cd into a directory that does not exist fails and
  # leaves the shell where it was, so the base stays put: `cd <root>/missing;
  # rg x .` searches the root. With `&&` the rg never runs, so judging it from
  # the old base only over-blocks.
  if [ "$TOOL" = cd ] || [ "$TOOL" = pushd ]; then
    # Stated limit: a cd that moves nothing after it is still followed -- one inside a pipeline, one
    # put in the background with `&`, one under a condition that does not run. A search after such
    # a cd is judged against the wrong directory. This guards against an accidental checkout-wide
    # search; it is not a parser of every shell form.
    NEW_BASE=""
    case "${1-}" in
      ''|'~') NEW_BASE=$HOME ;;
      '~/'*) NEW_BASE=$HOME/${1#'~/'} ;;
      -*|*'$'*|*'`'*) SEARCH_BASE=""; continue ;;
      /*) NEW_BASE=$(realpath -m -- "$1") ;;
      *) [ -n "$SEARCH_BASE" ] && NEW_BASE=$(realpath -m -- "$SEARCH_BASE/$1") ;;
    esac
    [ -n "$NEW_BASE" ] && [ -d "$NEW_BASE" ] && SEARCH_BASE=$NEW_BASE
    continue
  fi
  case "$TOOL" in
    rg) SHORT_VALUED=$RG_SHORT_VALUED; LONG_VALUED=$RG_LONG_VALUED ;;
    grep) printf '%s\n' "$@" | grep -qE '^-[a-zA-Z]*[rR]|^--(dereference-)?recursive$' || continue
          SHORT_VALUED=$GREP_SHORT_VALUED; LONG_VALUED=$GREP_LONG_VALUED ;;
    *) continue ;;
  esac
  PATTERN=""; HAVE_PATTERN=0; FILES_MODE=0; STDIN=${SRCH_PIPE[i]}; PATHS=(); OPTS_DONE=0
  while [ $# -gt 0 ]; do
    W=$1; shift
    case "$W" in
      '<'|'<<'|'<<<'|[0-9]'<') STDIN=1; shift; continue ;;
      '<'*|[0-9]'<'*) STDIN=1; continue ;;
      '>'|'>>'|[0-9]'>'|[0-9]'>>'|'&>') shift; continue ;;
      '>'*|[0-9]'>'*|'&>'*) continue ;;
    esac
    if [ "$OPTS_DONE" = 0 ]; then
      case "$W" in
        --) OPTS_DONE=1; continue ;;
        -) STDIN=1; continue ;;
        --regexp=*|--file=*) HAVE_PATTERN=1; PATTERN=${W#*=}; continue ;;
        --regexp|--file) HAVE_PATTERN=1; PATTERN=${1-}; shift; continue ;;
        --files|--type-list) HAVE_PATTERN=1; FILES_MODE=1; continue ;;
        --*=*) continue ;;
        --*) case "$LONG_VALUED" in *" $W "*) shift ;; esac; continue ;;
        -?*)
          for ((J=1; J<${#W}; J++)); do
            C=${W:J:1}
            case "$SHORT_VALUED" in *"$C"*)
              V=${W:J+1}; [ -n "$V" ] || { V=${1-}; shift; }
              case "$C" in e|f) HAVE_PATTERN=1; PATTERN=$V ;; esac
              break ;;
            esac
          done
          continue ;;
      esac
    fi
    PATHS+=("$W")
  done
  # The first operand is the pattern only when no -e/-f/--files names one, wherever that flag sits.
  [ "$HAVE_PATTERN" = 0 ] && [ ${#PATHS[@]} -gt 0 ] && PATTERN=${PATHS[0]} && PATHS=("${PATHS[@]:1}")
  BAD="" NBAD=1
  if [ ${#PATHS[@]} -eq 0 ]; then
    [ "$STDIN" = 1 ] && [ "$TOOL" = rg ] && continue
    BAD="(no path)"
  else
    NBAD=0
    for P in "${PATHS[@]}"; do
      LOOP_LIST=""
      if [[ $P =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$ ]]; then
        # A read-bound variable is one fed-in path per search: bounded.
        [[ ${SRCH_READ[i]} == *" ${BASH_REMATCH[1]} "* ]] && continue
        LOOP_LIST=$(printf '%s\n' "${SRCH_FOR[i]}" | awk -F'\t' -v n="${BASH_REMATCH[1]}" '$1 == n { print $2 }')
      fi
      if [ -n "$LOOP_LIST" ]; then
        read -ra LOOP_WORDS <<< "$LOOP_LIST"
        for V in "${LOOP_WORDS[@]}"; do search_bounded "$V" || { BAD=${BAD:-$V}; NBAD=$((NBAD + 1)); break 2; }; done
      else
        # Every operand is checked: the rewrite below replaces one, so a second unbounded one keeps the refusal.
        # An operand computed at run time ($VAR, $(...)) cannot be judged from the text: it passes with a warning (G4).
        search_bounded "$P" || case "$P" in
          '$HOME'|'$HOME/'*) BAD=${BAD:-$P}; NBAD=$((NBAD + 1)) ;;
          '$'*|'`'*) SEARCH_WARN="$TOOL over $P: the path is computed at run time, so its size is unchecked; make sure it names a directory or file, not the checkout root." ;;
          *) BAD=${BAD:-$P}; NBAD=$((NBAD + 1)) ;;
        esac
      fi
    done
    [ -z "$BAD" ] && { caller_hunt; continue; }
  fi
  # A worker's missing, `.`, root or literal-parent path is rewritten to the checkout root with the output capped at 200
  # lines (the cap bounds the 2026-09-10 flood); only when the whole call is this one simple search with one unbounded
  # operand. The rewrite single-quotes every word, so a call the shell would expand or chain (rewrite_safe, no
  # unquoted `| ; & < > ( )` or ~ * ? [ {) would search for something else: it stays refused below, as main's does.
  # pipefail keeps rg's own exit (1 no match, 2 bad pattern); the drain after head avoids SIGPIPE 141; no PIPESTATUS, the shell may be zsh.
  SIMPLE_SEARCH=0
  if rewrite_safe "$CMD"; then
    case "$RW_TEXT" in *['|;&<>()~*?[{']*) ;; *) SIMPLE_SEARCH=1 ;; esac
  fi
  # Main's lone simple search is rewritten the same way (G4); with no checkout to search it keeps the refusal below.
  if [ "$NBAD" = 1 ] && [ "$SIMPLE_SEARCH" = 1 ] && SEARCH_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$SEARCH_ROOT" ]; then
    for ((K=${#WORDS[@]}-1; K>=0; K--)); do [ "${WORDS[K]}" = "$BAD" ] && { WORDS[K]=$SEARCH_ROOT; break; }; done
    CAPPED=""; for W in "${WORDS[@]}"; do CAPPED+="$(shq "$W") "; done
    [ "$BAD" = "(no path)" ] && CAPPED+=$(shq "$SEARCH_ROOT")
    SEARCH_RUN="{ ${CAPPED% }; } 2>&1 | { head -n 200; cat >/dev/null; }" SEARCH_CUT="capped at 200 lines"
    # In a card's session (the test below, where WR_PACK is read) the whole output goes to a file under $TMPDIR and
    # through conveyor/tools/outbrief.sh, as the session's other calls do (issue #543): over 8,000 characters it prints
    # its first 60 and last 40 lines and the file's path. If the file cannot be made, the 200-line cap stays.
    SEARCH_OB=$(cd "${BASH_SOURCE[0]%/*}/../../conveyor/tools" 2>/dev/null && pwd -P)/outbrief.sh
    if [ -n "${CONVEYOR_CARD:-}" ] && [ -r "${CLAUDE_PROJECT_DIR:-.}/.conveyor/project.json" ] && [ -x "$SEARCH_OB" ]; then
      SEARCH_RUN="if __cv_o=\$(mktemp \"\${TMPDIR:-/tmp}/outbrief.XXXXXX\"); then { ${CAPPED% }; } > \"\$__cv_o\" 2>&1; $(shq "$SEARCH_OB") \"\$__cv_o\" \"\$?\"; else $SEARCH_RUN; fi"
      SEARCH_CUT="shortened by outbrief.sh"
    fi
    jq -cn --arg c "( set -o pipefail; $SEARCH_RUN )" --argjson ti "$(jq -c '.tool_input' <<<"$INPUT")" \
      --arg r "$TOOL over an unbounded path ($BAD) was rewritten to search the checkout root with the output $SEARCH_CUT" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecisionReason: $r, updatedInput: ($ti + {command: $c})}}'
    exit 0
  fi
  ROOTS="src web shared lambdas infra scripts .claude"
  if [ "$FILES_MODE" = 1 ]; then TRY="rg --files $ROOTS"
  elif [ "$TOOL" = grep ]; then TRY="grep -rn -e $(shq "$PATTERN") $ROOTS"
  else TRY="rg -n -e $(shq "$PATTERN") $ROOTS"; fi
  echo "BLOCKED: $TOOL over an unbounded path: $BAD. Name a directory relative to the checkout, an existing file, or an absolute log path such as /tmp/conveyor/<unit>-*.log -- never the checkout root, a parent of it, or an unresolved variable. A repo-wide search took main down on 2026-09-10 (.claude/rules/agents.md, Token efficiency).
Instead: the same search on one named directory, for example rg <pattern> src/." >&2
  # The rule never said how to ask the whole-repo question, which is sometimes
  # the real one: 19 of 51 blocks were followed by another block of this same
  # rule. Both sanctioned answers are named here.
  echo "Whole repo: serena find_symbol / find_referencing_symbols answer a symbol question without a filesystem walk. To search the tree anyway, name the roots: $TOOL ... src web shared lambdas infra scripts .claude" >&2
  echo "Try: $TRY" >&2
  exit 2
done

# An `env` or `VAR=value` prefix hides the real command from a check that reads
# the first word: in `tail -f x.log | env LC_ALL=C grep -q DONE` the first word
# of the consumer is `env`. Stripping repeats, because `env -i env -u LC_ALL cmd` is one prefix
# written twice, and a segment left with no command at all starts no job.
strip_prefix() { # reduces WORDS to the real command word and its arguments
  while [ ${#WORDS[@]} -gt 0 ]; do
    case "${WORDS[0]}" in
      env|*/env)
        WORDS=("${WORDS[@]:1}")
        while [ ${#WORDS[@]} -gt 0 ]; do
          case "${WORDS[0]}" in
            # `-u NAME` and `-C DIR` take the word after them; `-S` carries the
            # whole command line inside one word, so it is split back out.
            -u|-C|--unset|--chdir) WORDS=("${WORDS[@]:2}") ;;
            -S|--split-string) WORDS=(${WORDS[1]-} "${WORDS[@]:2}") ;;
            -S?*) WORDS=(${WORDS[0]#-S} "${WORDS[@]:1}") ;;
            --split-string=*) WORDS=(${WORDS[0]#*=} "${WORDS[@]:1}") ;;
            -*) WORDS=("${WORDS[@]:1}") ;;
            *) break ;;
          esac
        done ;;
      bash|sh) WORDS=("${WORDS[@]:1}") ;;
      *=*)
        case "${WORDS[0]}" in */*) break ;; esac
        WORDS=("${WORDS[@]:1}") ;;
      *) break ;;
    esac
  done
}
seg_head() { # $1 = segment index; sets WORDS to the command and its arguments
  load_words "${SEG_TEXT[$1]}"; strip_prefix
}

# Every seat: an aws call must name its profile. A call with no profile resolves to the default keys, which may be an
# account no agent may touch, so the guard refuses it early. The fence (G18, plan Data design
# "aws profile fence"): only the call's own --profile, its own `[env] AWS_PROFILE=x` prefix, or a run of literal
# assignments before it that parses in full vouches; any other text before the call leaves only the first two, not
# even the hook's own AWS_PROFILE. SEG_TEXT has the command's aliases substituted
# in, so a `P=--profile=x` that never ran would read as the call's own words: this check reads the raw segments.
# Every profile value the command text supplies passes aws_profile_name: the word reader drops quotes, so `"$X"` and a
# literal are told apart only by refusing anything but a plain profile name (pass 4: `AWS_PROFILE="$UNSET"` ran empty).
aws_profile_name() { [[ $1 =~ ^[A-Za-z0-9_.-]+$ ]]; }
AWS_LIT='("[^"$`\]*"|'"'[^']*'"'|[A-Za-z0-9_./:=@%+,-]*)'
AWS_STMT_RE='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)='"$AWS_LIT"'[[:space:]]*(;|&&|'$'\n'')'
aws_pre_parse() { # $1 = the text before the call; fills PRE_EXP/PRE_NAME/PRE_VAL, fails unless all of it parses
  local S=$1
  PRE_EXP=(); PRE_NAME=(); PRE_VAL=()
  while [[ $S =~ $AWS_STMT_RE ]]; do
    PRE_EXP+=("${BASH_REMATCH[1]:+1}"); PRE_NAME+=("${BASH_REMATCH[2]}"); PRE_VAL+=("${BASH_REMATCH[3]}")
    S=${S:${#BASH_REMATCH[0]}}
  done
  [[ $S =~ ^[[:space:]]*$ ]] && return 0
  PRE_EXP=(); PRE_NAME=(); PRE_VAL=(); return 1
}
aws_last() { # $1 = NAME; LAST_VAL (unquoted) and LAST_EXP of its last assignment there; fails when it has none
  local K
  for ((K=${#PRE_NAME[@]}-1; K>=0; K--)); do
    [ "${PRE_NAME[K]}" = "$1" ] || continue
    LAST_VAL=${PRE_VAL[K]}; LAST_EXP=${PRE_EXP[K]}
    case "$LAST_VAL" in \"*|\'*) LAST_VAL=${LAST_VAL:1:${#LAST_VAL}-2} ;; esac
    return 0
  done
  return 1
}
# search_text lifts each `$(...)` and backtick body out as segments of its own, so an aws call inside one is checked.
mapfile -t AWS_SEGS < <(split_search_segments "$SEARCH_CMD")
for AWS_SEG in "${AWS_SEGS[@]}"; do
  AWS_SEG=${AWS_SEG:1}
  load_words "$AWS_SEG"; AWS_HEAD=("${WORDS[@]}"); strip_prefix; set -- "${WORDS[@]}"
  [ "${1-}" ] && [ "${1##*/}" = aws ] || continue
  shift
  case "${1-}" in --version|help) continue ;; esac
  # The sequence is read only when this call's text occurs once in the command, so the text before it is placed.
  PRE_NAME=()
  [[ $CMD == *"$AWS_SEG"* ]] && [[ ${CMD#*"$AWS_SEG"} != *"$AWS_SEG"* ]] && aws_pre_parse "${CMD%%"$AWS_SEG"*}" && AWS_PRE_OK=1 || AWS_PRE_OK=0
  # PROF: 1 a profile name vouches; BAD: a --profile whose value is not a plain name overrides any AWS_PROFILE, so it
  # refuses outright.
  PROF=0 BAD=0
  while [ $# -gt 0 ]; do
    PV=""; P_SET=0
    case "$1" in --profile) PV=${2-}; P_SET=1; shift ;; --profile=*) PV=${1#--profile=}; P_SET=1 ;; esac
    # A `$NAME` argument vouches when NAME's last assignment in the sequence is `--profile <name>`.
    [[ $1 =~ ^\"?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\"?$ ]] && aws_last "${BASH_REMATCH[1]}" \
      && [[ $LAST_VAL =~ ^--profile(=|[[:space:]]+)(.*)$ ]] && { PV=${BASH_REMATCH[2]%% *}; P_SET=1; }
    [ "$P_SET" = 1 ] && { if aws_profile_name "$PV"; then PROF=1; else BAD=1; fi; }
    shift
  done
  [ "$BAD" = 0 ] && [ "$PROF" = 1 ] && continue
  [ "$BAD" = 1 ] && AWS_HEAD=() AWS_PRE_OK=0
  # The call's own prefix: only `env` (no option) and NAME=VALUE words before `aws`. Its AWS_PROFILE word, empty
  # or not, is the one the call runs with, so it alone decides.
  AWS_PLAIN=1 AWS_OWN_SET=0 AWS_OWN=""
  for W in "${AWS_HEAD[@]}"; do
    [ "${W##*/}" = aws ] && break
    case "$W" in
      env) ;;
      AWS_PROFILE=*) AWS_OWN_SET=1; AWS_OWN=${W#AWS_PROFILE=}; AWS_OWN=${AWS_OWN//[\"\']/} ;;
      [A-Za-z_]*=*) ;;
      *) AWS_PLAIN=0 ;;
    esac
  done
  if [ "$AWS_PLAIN" = 1 ] && [ "$AWS_OWN_SET" = 1 ]; then
    aws_profile_name "$AWS_OWN" && continue
  elif [ "$AWS_PRE_OK" = 1 ] && ! [[ $AWS_SEG =~ (-u|--unset)[=[:space:]]+AWS_PROFILE|env[[:space:]]+(-[A-Za-z]*i|--ignore-environment) ]]; then
    # The sequence's last AWS_PROFILE reaches aws when exported there or already in the session; with none, the
    # hook's own AWS_PROFILE does.
    if aws_last AWS_PROFILE; then
      aws_profile_name "$LAST_VAL" && { [ -n "$LAST_EXP" ] || [ -n "${AWS_PROFILE-}" ]; } && continue
    else
      [ -n "${AWS_PROFILE-}" ] && continue
    fi
  fi
  echo "BLOCKED: this aws command names no profile, so it would run on the default keys, which may be an account no agent may touch. Name the account you mean.
Instead: add --profile <the profile the task names>." >&2
  echo "Try: aws --profile dev sts get-caller-identity" >&2; exit 2
done

# A card's build or fix session (CONVEYOR_CARD, conveyor/lib/session.sh builder()) runs no whole test suite: the
# loop's Test step runs what the change touches before the card lands (the owner, 2026-11-14). Refused there, by the
# commands the project's pack names (<project>/.conveyor/project.json, conveyor/README.md, When a full test run is
# allowed): a command of test.wholeCommands with no case named (no word after it but options and redirections, and no
# CONVEYOR_SHELL_TEST_CASE=<cases> before it); test.changed a second time in the session (one marker per card and
# session id, in CONVEYOR_GUARD_STATE, else ~/.cache/conveyor/changed-runs); and node --test over a folder, a glob or
# nothing (node then runs every test file it finds) rather than named files. A run that names cases or files passes.
# A command or folder is read from the directory the call's cd or pushd moved to, and test.changed twice in one call
# is refused as a second run.
# Accepted gaps: a command run from a script or `bash -c` text is not seen, and a test.changed run a later hook
# refuses still counts as the session's one.
# wr_real: path $2 (from directory $1 when relative) with its folder resolved; fails when the folder does not exist.
wr_real() {
  local p=$2 d; case "$p" in '~') p=$HOME ;; '~/'*) p=$HOME/${p#\~/} ;; /*) ;; *) p=$1/$p ;; esac
  # dirname and basename as the programs give them, without starting either (two calls a segment, four programs).
  local b=$p; while [[ $b == ?*/ ]]; do b=${b%/}; done
  if [[ $b == */* ]]; then d=${b%/*}; d=${d%"${d##*[!/]}"}; d=${d:-/}; b=${b##*/}; b=${b:-/}; else d=.; fi
  d=$(cd "$d" 2>/dev/null && pwd -P) && printf '%s/%s\n' "${d%/}" "$b"
}
# wr_cmd: 0 when word $1 runs the pack's command $2: as written, ./-led, a path ending in /<command>, or the same file
# named from the directory the call's cd and pushd left it in (WR_CWD).
wr_cmd() {
  local w=${1#./} c=${2#./} a
  [ -n "$c" ] || return 1
  { [ "$w" = "$c" ] || [[ $w == */"$c" ]]; } && return 0
  a=$(wr_real "$WR_CWD" "$1") && [ "$a" = "$(wr_real "$WR_ROOT" "$c")" ]
}
# wr_args: the words of WR_W after index $1 that are not options or redirections (a bare redirection takes the next).
wr_args() {
  local i=$(($1 + 1)) w
  WR_ARGS=()
  while [ $i -lt ${#WR_W[@]} ]; do
    w=${WR_W[i]}
    case "$w" in
      '>'|'>>'|'<'|[0-9]'>'|[0-9]'>>'|'&>'|'&>>') i=$((i + 1)) ;;
      -*|[0-9]'>'*|'>'*|'<'*|'&>'*) ;;
      *) WR_ARGS+=("$w") ;;
    esac
    i=$((i + 1))
  done
}
if [ -n "${CONVEYOR_CARD:-}" ] && WR_PACK=$(cat "${CLAUDE_PROJECT_DIR:-.}/.conveyor/project.json" 2>/dev/null); then
  mapfile -t WR_WHOLE < <(jq -r '.test.wholeCommands // [] | .[] | strings' <<<"$WR_PACK" 2>/dev/null)
  WR_CHANGED=$(jq -r '.test.changed // "" | strings' <<<"$WR_PACK" 2>/dev/null)
  WR_CWD=$(echo "$INPUT" | jq -r '.cwd // empty'); [ -d "$WR_CWD" ] || WR_CWD=$PWD
  WR_ROOT=${CLAUDE_PROJECT_DIR:-.}
  WR_RUNS_CHANGED=0 WR_TESTS=0 WR_PLAIN=0
  # The engine's short-summary wrapper (below, where a test command is rewritten), beside this hook.
  WR_TB=$(cd "${BASH_SOURCE[0]%/*}/../../conveyor/tools" 2>/dev/null && pwd -P)/testbrief.sh
  # WR_PACKRUN: the pack's own test commands, also wrapped though their names are not a test runner's: test.changed,
  # and the command word of test.command (past NAME=VALUE words, options, a duration and the wrappers named below).
  WR_PACKRUN=("$WR_CHANGED")
  load_words "$(jq -r '.test.command // "" | strings' <<<"$WR_PACK" 2>/dev/null)"
  for WR_X in "${WORDS[@]}"; do
    case "$WR_X" in [A-Za-z_]*=*|-*|+*) continue ;; esac
    case "${WR_X##*/}" in env|bash|sh|timeout|nice|time|command|exec|nohup|setsid|stdbuf) continue ;; esac
    [[ $WR_X =~ ^[0-9.]+[smhd]?$ ]] || { WR_PACKRUN+=("$WR_X"); break; }
  done
  mapfile -t WR_SEGS < <(split_search_segments "$SEARCH_CMD")
  WR_KEEP=$WR_CWD
  for WR_SEG in "${WR_SEGS[@]}"; do
    # Only cd and pushd move the directory of later segments; env -C moves its own segment's alone.
    WR_CWD=$WR_KEEP
    load_words "${WR_SEG:1}"; WR_W=("${WORDS[@]}"); WR_NAMED=''
    # The command word: past NAME=VALUE words, a duration or niceness, and the wrappers env, bash/sh, timeout, nice,
    # time, command, exec, nohup, setsid, stdbuf and testbrief.sh (WR_SB: the engine's own, WR_TB) with their options;
    # an option of the wrapper before it that takes the next word (env -u NAME, bash -o pipefail) takes it, env -C moves
    # the directory, and env -S's text is read as the words it runs. CONVEYOR_SHELL_TEST_CASE names cases only while
    # set and not empty: env -i, or env -u of it, clears it. A wrapper is known by its name, so one named by its path
    # (/bin/bash, /usr/bin/env) is passed over too.
    WR_I=0; WR_WRAP=''; WR_SB=0
    while [ $WR_I -lt ${#WR_W[@]} ]; do
      WR_X=${WR_W[WR_I]}; WR_V=${WR_W[WR_I + 1]:-}
      case "$WR_WRAP:$WR_X" in
        *:CONVEYOR_SHELL_TEST_CASE=*) WR_NAMED=${WR_X#*=} ;;
        env:-i|env:--ignore-environment) WR_NAMED='' ;;
        env:-u|env:--unset) [ "$WR_V" != CONVEYOR_SHELL_TEST_CASE ] || WR_NAMED=''; WR_I=$((WR_I + 1)) ;;
        env:-uCONVEYOR_SHELL_TEST_CASE|env:--unset=CONVEYOR_SHELL_TEST_CASE) WR_NAMED='' ;;
        env:-C|env:--chdir) WR_P=$(wr_real "$WR_CWD" "$WR_V") && [ -d "$WR_P" ] && WR_CWD=$WR_P; WR_I=$((WR_I + 1)) ;;
        env:-C?*|env:--chdir=*) WR_V=${WR_X#-C}; WR_V=${WR_V#--chdir=}
          WR_P=$(wr_real "$WR_CWD" "$WR_V") && [ -d "$WR_P" ] && WR_CWD=$WR_P ;;
        env:-S|env:--split-string|env:-S?*|env:--split-string=*)
          case "$WR_X" in -S|--split-string) WR_N=2 ;; *) WR_N=1; WR_V=${WR_X#-S}; WR_V=${WR_V#--split-string=} ;; esac
          mapfile -t WR_SPLIT < <(seg_words "$WR_V")
          WR_W=("${WR_W[@]:0:WR_I}" "${WR_SPLIT[@]}" "${WR_W[@]:WR_I+WR_N}"); continue ;;
        timeout:-k|timeout:--kill-after|timeout:-s|timeout:--signal|nice:-n|nice:--adjustment|exec:-a|time:-f|time:--format|time:-o|time:--output|bash:-o|bash:-O|bash:+o|bash:+O|bash:--rcfile|bash:--init-file|sh:-o|sh:+o|stdbuf:-i|stdbuf:-o|stdbuf:-e)
          WR_I=$((WR_I + 1)) ;;
        *:[A-Za-z_]*=*|*:-*|*:+*) ;;
        *) case "${WR_X##*/}" in
             env|bash|sh|timeout|nice|time|command|exec|nohup|setsid|stdbuf) WR_WRAP=${WR_X##*/} ;;
             testbrief.sh) WR_WRAP=testbrief.sh; [ "$(wr_real "$WR_CWD" "$WR_X")" != "$WR_TB" ] || WR_SB=1 ;;
             *) [[ $WR_X =~ ^[0-9.]+[smhd]?$ ]] || break ;;
           esac ;;
      esac
      WR_I=$((WR_I + 1))
    done
    WR_HEAD=${WR_W[WR_I]:-}
    [ -n "$WR_HEAD" ] || continue
    wr_args "$WR_I"
    # cd and pushd move later segments' directory: a command or folder named after them is read from there.
    if [ "$WR_HEAD" = cd ] || [ "$WR_HEAD" = pushd ]; then
      WR_A=${WR_ARGS[0]:-$HOME}
      [ "$WR_A" = - ] || { WR_P=$(wr_real "$WR_CWD" "$WR_A") && [ -d "$WR_P" ] && WR_CWD=$WR_P; }
      WR_KEEP=$WR_CWD
      continue
    fi
    # A test command, whose time counts to the session's test budget (below): node --test, a *.test.sh, pytest,
    # vitest or jest, also as `python3 -m pytest` or `npx vitest`. WR_PLAIN: one of them, or one of the pack's own test
    # commands (WR_PACKRUN), not run through testbrief.sh.
    WR_ST=$WR_TESTS; WR_TESTS=0
    case "${WR_HEAD##*/}" in
      *.test.sh|pytest|vitest|jest) WR_TESTS=1 ;;
      node) printf '%s\n' "${WR_W[@]}" | grep -qx -- '--test' && WR_TESTS=1 ;;
      python|python3|npx|pnpx|bunx|yarn|pnpm) case "${WR_ARGS[0]:-}" in pytest|vitest|jest) WR_TESTS=1 ;; esac ;;
    esac
    # The rule Only the Test step runs tests on (CONVEYOR_TESTSTEPONLY=1, set by conveyor/lib/session.sh builder()
    # from teststeponly(), lib/prompts.sh): a card's session runs no test at all, a named case or file included. A
    # test command is one of those above, or one of the pack's own (WR_PACKRUN, test.wholeCommands).
    if [ "${CONVEYOR_TESTSTEPONLY:-}" = 1 ]; then
      WR_ONE=$WR_TESTS
      for WR_C in "${WR_PACKRUN[@]}" "${WR_WHOLE[@]}"; do [ "$WR_ONE" = 1 ] || ! wr_cmd "$WR_HEAD" "$WR_C" || WR_ONE=1; done
      [ "$WR_ONE" = 0 ] || { echo "BLOCKED: ${WR_HEAD##*/} runs tests. The rule Only the Test step runs tests is on: a card's session runs no tests, the Test step runs the tests the change touches after the session.
Instead: read the last Test step's result, the file <worktree>.test beside this worktree (none yet when no Test step has run)." >&2; exit 2; }
    fi
    [ "$WR_TESTS" = 0 ] || [ "$WR_SB" = 1 ] || WR_PLAIN=1
    for WR_C in "${WR_PACKRUN[@]}"; do wr_cmd "$WR_HEAD" "$WR_C" && [ "$WR_SB" = 0 ] && WR_PLAIN=1; done
    [ "$WR_ST" = 0 ] || WR_TESTS=1
    for WR_C in "${WR_WHOLE[@]}"; do
      wr_cmd "$WR_HEAD" "$WR_C" && [ -z "$WR_NAMED" ] && [ ${#WR_ARGS[@]} = 0 ] || continue
      echo "BLOCKED: $WR_C with no case named runs the whole suite. In a card's session run only the cases your change touches; the loop's Test step runs what the change touches before the card lands.
Instead: name the cases: $WR_C <case> [<case> ...]." >&2
      exit 2
    done
    wr_cmd "$WR_HEAD" "$WR_CHANGED" && WR_RUNS_CHANGED=$((WR_RUNS_CHANGED + 1))
    if [ "${WR_HEAD##*/}" = node ] && printf '%s\n' "${WR_W[@]}" | grep -qx -- '--test'; then
      # node's options that take the next word (the rest take none, or theirs after =).
      WR_ARGS=(); WR_I=$((WR_I + 1)); WR_BAD=''
      while [ $WR_I -lt ${#WR_W[@]} ]; do
        case "${WR_W[WR_I]}" in
          -r|--require|--import|--loader|--experimental-loader|--test-reporter|--test-reporter-destination|--test-name-pattern|--test-skip-pattern|--test-concurrency|--test-timeout|--test-shard|--env-file) WR_I=$((WR_I + 1)) ;;
          '>'|'>>'|'<'|[0-9]'>'|[0-9]'>>'|'&>'|'&>>') WR_I=$((WR_I + 1)) ;;
          -*|[0-9]'>'*|'>'*|'<'*|'&>'*) ;;
          *) WR_ARGS+=("${WR_W[WR_I]}") ;;
        esac
        WR_I=$((WR_I + 1))
      done
      [ ${#WR_ARGS[@]} != 0 ] || WR_BAD='no file'
      for WR_A in "${WR_ARGS[@]}"; do
        case "$WR_A" in /*) WR_P=$WR_A ;; *) WR_P=$WR_CWD/$WR_A ;; esac
        [[ $WR_A != *[*?[]* ]] && [ ! -d "$WR_P" ] || WR_BAD=$WR_A
      done
      [ -z "$WR_BAD" ] || { echo "BLOCKED: node --test over $WR_BAD runs every test file it finds. In a card's session run only the test files your change touches.
Instead: name the files: node --max-old-space-size=4096 --test <file> [<file> ...]." >&2; exit 2; }
    fi
  done
  [ "$WR_RUNS_CHANGED" -lt 2 ] || { echo "BLOCKED: this call runs $WR_CHANGED $WR_RUNS_CHANGED times; it runs once a session. The loop's Test step runs what the change touches before the card lands.
Instead: run it once, and after it name the cases or test files you changed since." >&2; exit 2; }
  WR_SID=$(echo "$INPUT" | jq -r '.session_id // empty' | tr -c 'A-Za-z0-9_-' '_')
  # The session test budget (conveyor/README.md, The session test budget): a test command let through is run behind an
  # EXIT trap that adds its CPU seconds to the session's ledger (one line a call, per card and session id, so a new
  # session starts at 0); a call that leaves jobs running in the background (`( ... ) &`) adds theirs once they end.
  # Once the ledger is over the pack's test.sessionBudget, the session's next test command is refused. The ledger is
  # written by the session's own shell, so it is in CONVEYOR_GUARD_STATE, else under /tmp: a Codex session's sandbox
  # lets it write in the worktree, /tmp and $TMPDIR only (conveyor/lib/session.sh builder()), not ~/.cache.
  # Accepted gaps: a command that sets its own EXIT trap replaces this one, and its time is not counted; a test run
  # from a script or `bash -c` text is not seen.
  # A call with a test command the session did not run through the short-summary wrapper (WR_TB,
  # conveyor/tools/testbrief.sh in the engine's checkout) is run through it: the call's whole text becomes the body
  # of a function that the session's own shell runs in a subshell, its output (both streams) in a file under $TMPDIR
  # that the wrapper then reads. No `export -f`: the session's shell is zsh on macOS, which exports no function to a
  # child bash (issue #873). Its whole output goes to a log file and the session
  # sees only the failures, the summary and the log's path, so a big test log stops filling every later turn (issue
  # #540). Its exit code is the command's, and its CPU seconds are still this shell's children's. If the file cannot
  # be made, the call runs as written. The text stays
  # unquoted, so a hook after this one that is given the rewritten call (conveyor/opencode/guard.sh) still reads it as
  # commands. A call that leaves a job in the background (an `&` outside quotes that is not part of `&&` or a
  # redirection) is left as it is: its output goes to its own file, and the budget's trap must see its jobs. A call
  # that runs only the pack's own test command (WR_PACKRUN) is wrapped but not timed, as before.
  # Accepted gap: a cd in a wrapped call does not move the session's directory.
  WR_RUN=$CMD
  WR_BG=$(strip_quoted "$CMD" | sed -E 's/&&|[0-9]*>&|&>|<&|\|&//g')
  if [ "$WR_PLAIN" = 1 ] && [[ $WR_BG != *'&'* ]] && [ -x "$WR_TB" ]; then
    WR_RUN="__cv_test() {"$'\n'"$CMD"$'\n'"}"$'\n'"if __cv_t=\$(mktemp \"\${TMPDIR:-/tmp}/testrun.XXXXXX\"); then"$'\n'
    WR_RUN+="( __cv_test ) > \"\$__cv_t\" 2>&1; __cv_r=\$?"$'\n'
    WR_RUN+="$(shq "$WR_TB") --from \"\$__cv_t\" --rc \"\$__cv_r\""$'\n'
    WR_RUN+="else __cv_test; fi"
  fi
  # A call with no test command is run with its output (both streams) in a file under $TMPDIR, then through
  # conveyor/tools/outbrief.sh beside the wrapper: output over 8,000 characters prints its first 60 and last 40 lines,
  # the count left out and the file's path, so a long `git diff` or log stops filling every later turn (issue #543).
  # The whole call is the body, so a pipe or redirect inside it still reads the whole output; only what reaches the
  # session is shortened. The call runs as a function in a subshell, so its `exit` or `set -e` still lets the brief print;
  # the subshell's EXIT trap keeps its last directory, and the session's shell moves there after it. Its exit code is
  # the call's. A call that names CONVEYOR_WHOLE=1 (outside quotes) prints whole, as does one that leaves a job in the
  # background (its output would reach the file after the brief). If the file cannot be made, the call runs as written.
  # Accepted gap: a call that sets its own EXIT trap does not move the session's directory.
  WR_OB=$(cd "${BASH_SOURCE[0]%/*}/../../conveyor/tools" 2>/dev/null && pwd -P)/outbrief.sh
  if [ "$WR_RUN" = "$CMD" ] && [ "$WR_TESTS" = 0 ] && [[ $WR_BG != *'&'* ]] && [ -x "$WR_OB" ] \
    && ! [[ $WR_BG =~ (^|[^[:alnum:]_])CONVEYOR_WHOLE=1([^[:alnum:]_]|$) ]]; then
    WR_RUN="__cv_out() {"$'\n'"$CMD"$'\n'"}"$'\n'"if __cv_o=\$(mktemp \"\${TMPDIR:-/tmp}/outbrief.XXXXXX\"); then"$'\n'
    WR_RUN+="( trap 'pwd -P > \"\$__cv_o.cwd\"' EXIT; __cv_out ) > \"\$__cv_o\" 2>&1; __cv_r=\$?"$'\n'
    WR_RUN+="cd \"\$(cat \"\$__cv_o.cwd\" 2>/dev/null || pwd)\" 2>/dev/null; rm -f \"\$__cv_o.cwd\"; $(shq "$WR_OB") \"\$__cv_o\" \"\$__cv_r\""$'\n'
    WR_RUN+="else __cv_out; fi"
  fi
  WR_TIMED=''
  if [ "$WR_TESTS" = 1 ]; then
    WR_BUDGET=$(jq -r '.test.sessionBudget // 3600 | numbers' <<<"$WR_PACK" 2>/dev/null); WR_BUDGET=${WR_BUDGET:-3600} # the schema's default
    WR_LDIR=${CONVEYOR_GUARD_STATE:-/tmp/conveyor-test-budget-$(id -u)}
    WR_LOG=$WR_LDIR/${CONVEYOR_CARD//\//_}-$WR_SID.testsec
    WR_USED=$(cat "$WR_LOG" 2>/dev/null | awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ { s += $1 } END { print s + 0 }')
    if awk -v u="$WR_USED" -v b="$WR_BUDGET" 'BEGIN { exit !(u > b) }'; then
      echo "BLOCKED: this session's test commands have used $WR_USED CPU s, over its test budget of $WR_BUDGET CPU s (the pack's test.sessionBudget). No more test runs in this session. Narrow to one case: read its code and the output you already have. Or stop and report what you know. The card's test step still runs the tests before the card lands.
Instead: stop running tests; report what you found and what is not verified." >&2
      exit 2
    fi
    mkdir -p "$WR_LDIR" 2>/dev/null
    # The CPU seconds of a call are its shell's children's user and system times (`times`, written to a file: in a
    # `$( )` it reads 0). Jobs still running at its end are not the shell's children it waited for, so a process left
    # behind samples their CPU seconds every second until they end, with their live descendants' and the children they
    # reaped (/proc on Linux, `ps -S` on macOS), and adds the largest sample: the CPU of their last second is not seen.
    WR_TRAP=$(cat <<'EOF'
__cv_log=@LOG@
__cv_tree() {
  if [ -r /proc/self/stat ]; then
    cat /proc/[0-9]*/stat 2>/dev/null | sed 's/ (.*) / /' | awk -v t="$(getconf CLK_TCK)" '{ print $1, $3, ($13 + $14 + $15 + $16) / t }'
  else
    ps -S -A -o pid= -o ppid= -o time= | awk '{ n = split($3, a, /[-:]/); s = 0; for (i = 1; i <= n; i++) s = s * 60 + a[i]; print $1, $2, s }'
  fi | awk -v r="$*" '{ p[NR] = $1; q[NR] = $2; c[NR] = $3 } END { split(r, a, " "); for (i in a) k[a[i]] = 1
    do { m = 0; for (i = 1; i <= NR; i++) if (!(p[i] in k) && (q[i] in k)) { k[p[i]] = 1; m = 1 } } while (m)
    for (i = 1; i <= NR; i++) if (p[i] in k) tot += c[i]; printf "%.1f\n", tot + 0 }'
}
__cv_end() {
  local j t m=0 c p
  times > "$__cv_log.$$" 2>/dev/null
  t=$(awk 'NR == 2 { for (i = 1; i <= NF; i++) { split($i, a, "m"); s += a[1] * 60 + a[2] } } END { printf "%.1f\n", s + 0 }' "$__cv_log.$$")
  rm -f "$__cv_log.$$"
  j=$(jobs -p)
  if [ -z "$j" ]; then echo "$t" >> "$__cv_log"; return; fi
  (
    while :; do
      c=$(__cv_tree $j); m=$(awk -v a="$m" -v b="$c" 'BEGIN { print (b > a ? b : a) }')
      for p in $j; do kill -0 "$p" 2>/dev/null && { sleep 1; continue 2; }; done
      break
    done
    awk -v a="$t" -v b="$m" 'BEGIN { printf "%.1f\n", a + b }' >> "$__cv_log"
  ) </dev/null >/dev/null 2>&1 &
}
trap __cv_end EXIT
EOF
)
    WR_Q=$(shq "$WR_LOG")
    WR_TIMED=${WR_TRAP//@LOG@/"$WR_Q"}$'\n'$WR_RUN
  elif [ "$WR_RUN" != "$CMD" ]; then
    WR_TIMED=$WR_RUN
  fi
  if [ "$WR_RUNS_CHANGED" = 1 ]; then
    WR_DIR=${CONVEYOR_GUARD_STATE:-$HOME/.cache/conveyor/changed-runs}
    mkdir -p "$WR_DIR" 2>/dev/null
    ( set -C; : > "$WR_DIR/${CONVEYOR_CARD//\//_}-$WR_SID" ) 2>/dev/null || { echo "BLOCKED: $WR_CHANGED already ran in this session; it runs once a session. The loop's Test step runs what the change touches before the card lands.
Instead: name the cases or test files you changed since it ran." >&2; exit 2; }
  fi
fi

# Only a call that passed every rule gets the hint, and only then is the
# session's one hunt hint spent. A timed test command (the session test budget, above) is run rewritten.
HINT_MSG=""
if [ -n "$HUNT_HINT$SEARCH_WARN" ]; then
  HOOK_FIRE_ADVISE=1
  [ -n "$HUNT_HINT" ] && : > "$HUNT_SEEN" 2>/dev/null
  HINT_MSG=$SEARCH_WARN
  [ -z "$HUNT_HINT" ] || HINT_MSG+="${HINT_MSG:+ }$HUNT_HINT"
fi
[ -z "$HINT_MSG${WR_TIMED:-}" ] || jq -cn --arg m "$HINT_MSG" --arg c "${WR_TIMED:-}" --argjson ti "$(jq -c '.tool_input' <<<"$INPUT")" \
  '{hookSpecificOutput: ({hookEventName: "PreToolUse"} + (if $m != "" then {additionalContext: $m} else {} end)
    + (if $c != "" then {updatedInput: ($ti + {command: $c})} else {} end))}'
exit 0
