#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook (Bash): a test suite or type check is run ONCE per state of
# the tree. Agent-neutral (fires for Codex through codex-dispatch.sh).
#
# ALSO the PostToolUse half: `--record-complete` on the same Bash payload is
# what marks a run as having actually happened. The PreToolUse pass records the
# attempt as PENDING and only a COMPLETED record blocks the next run, so a
# command that a later hook refused, or that the operator interrupted, does not
# leave a "you already ran this" behind for a run that never started.
#
# Measured on the walkthrough-remediation PR (2026-09-03): 22 of 116 suite and
# tsc runs across seven workers were the SAME command on an UNCHANGED tree,
# minutes apart, 27 minutes of runner time -- an agent piping a suite through
# `tail`/`grep`, losing the line it wanted, and running the whole suite again
# to read it differently. With the machine-wide suite lock every such rerun
# also holds up the worktrees queued behind it.
#
# Rule: the same suite/tsc command in the same directory, with the working
# tree in the same state, within 30 minutes, is blocked. Save the output the
# first time (`> "$SCRATCH/unit.log"`) and read the file. A genuine flake
# check is an explicit `RERUN=1` prefix on the command.
#
# Also blocks bare `npm test` outside infra/: it is guards + unit + the infra
# jest suite (~11 min under load, and `-- <filter>` reaches only the infra
# leg). Run the leg you need.
#
# "Tree state" is HEAD plus tracked worktree/index state and untracked path plus
# content identity, hashed BEFORE the run. A golden-file rewrite by the run
# itself, or any meaningful input edit, unlocks the next run.
#
# The state is keyed on the EFFECTIVE directory, not the payload's cwd:
# `cd infra && npm test` runs a different suite over a different tree than the
# same words at the repo root, and keying both to the root made them one run.
MODE=""
case "${1:-}" in --record-complete) MODE=complete ;; esac

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -d "$CWD" ] || CWD=$PWD
# Physical path, as seg_cd resolves a `cd`: on the Mac /var is a symlink, so a
# logical cwd and the same directory reached by `cd` would key two runs.
CWD=$(cd "$CWD" && pwd -P)

# Words are split as the shell would, with shlex: a quoted filename stays a file filter, a
# quoted word holding spaces is prose (a commit message may name a suite) and
# is dropped unless it holds a `$(...)` that runs, and so is every redirection
# with its target. A line whose quote is still open is split together with the
# lines that close it: split alone, a quoted string spanning lines lost its
# quotes and its prose ran as a command.
# chain_split prints the segments twice with a \x1d line between: the second
# time every word is kept, re-quoted, whitespace folded: the run key needs them,
# since `-t "one case"` picks the tests and is not the two words `-t one case`.
# -I: the caller's directory is on sys.path under -c, and a shlex.py or re.py
# planted there would run inside this hook; -I drops it (and PYTHON* vars).
chain_segments() {
  CMD=$1 python3 -I -S -c '
import os, re, shlex
def emit(toks, keep):
    seg, skip = [], False
    for t in toks:
        if skip:
            skip = False
        elif t and set(t) <= set(";&|"):
            print(" ".join(seg)); seg = []
        elif t and set(t) <= set("<>&|"):
            skip = True
        elif keep:
            # Verbatim: a filter is a regex, so its spacing selects. A newline is
            # spelled $'\n' so it stays off the segment line and unlike a typed \n.
            seg.append(shlex.quote(t).replace("\n", "'$'\\n''"))
        elif "$(" in t or not any(c.isspace() for c in t):
            seg.append(t)
    print(" ".join(seg))
# The fd number of `2>x` belongs to the redirection, but shlex splits it off as
# a word of its own. Quoted and escaped text is left as it is.
FD = re.compile(r"""\\.|\x27[^\x27]*\x27|"(?:\\.|[^"\\])*"|(?<![^\s;&|()])\d+(?=[<>])""")
def lex(text):
    text = FD.sub(lambda m: "" if m.group(0)[0].isdigit() else m.group(0), text)
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|<>")
    lex.whitespace_split = True
    return list(lex)
# Only a `#` that starts a word starts a comment; shlex ends a word at any `#`,
# which hid the commands after `a#b`. Escaped, a mid-word `#` stays a letter;
# one the command already escapes (an odd backslash run) is left as it is.
def midword_hash(m):
    run, at, text = m.group(1), m.start(), m.string
    if len(run) % 2 or (not run and (at == 0 or text[at - 1] in " \t;&|()<>")):
        return m.group(0)
    return run + "\\#"
lines = [re.sub(r"(\\*)#", midword_hash, l) for l in os.environ["CMD"].replace("\\\n", "").splitlines()]
# FAIL CLOSED on a heredoc (a ruling of main): a body apostrophe could
# open a quote that hides the commands after the body, and parsing delimiters
# missed a form every round. Any `<<` outside a comment (a `#` that starts a
# word with no quote before it) means one line at a time, body included: a
# suite named in a body blocks, one after it is never hidden.
groups = []
COMMENT = re.compile(r"^([^\x27\x22#]*?)(?:^|(?<=\s))#.*")
if any("<<" in COMMENT.sub(r"\1", l) for l in lines):
    for line in lines:
        try:
            toks = lex(line)
        except ValueError:
            toks = line.split()
        groups.append(toks)
    lines = []  # every line is read: the joining loop below has none left
i = 0
while i < len(lines):
    for j in range(i, len(lines)):
        try:
            toks = lex("\n".join(lines[i:j + 1]))
            break
        except ValueError:
            pass
    else:
        # A quote that never closes costs only its own line.
        j, toks = i, lines[i].split()
    groups.append(toks)
    i = j + 1
for keep in ("", "1"):
    for toks in groups:
        emit(toks, keep)
    if not keep:
        print("\x1d")
'
}
# One python call per command, not per use: this hook runs on every suite call.
# Sets CS_PLAIN and CS_KEPT; callers read them, a $( ) would lose the cache.
chain_split() {
  [ "${CS_TEXT+x}" = x ] && [ "$CS_TEXT" = "$1" ] && return
  local ALL
  ALL=$(chain_segments "$1")
  CS_TEXT=$1 CS_PLAIN=${ALL%%$'\x1d'*} CS_KEPT=${ALL#*$'\x1d'}
  # the \x1d line leaves one newline on each side
  CS_PLAIN=${CS_PLAIN%$'\n'} CS_KEPT=${CS_KEPT#$'\n'}
}

# A `cd <dir>` segment moves every segment after it. Prints the directory the
# segment leaves the shell in.
# ponytail: a `(cd x && ...)` subshell is not unwound at its `)`; the directory
# carries on to later segments.
seg_cd() {
  local w target
  read -r -a w <<< "$2"
  case "${w[0]:-}" in cd|'(cd') target=${w[1]:-} ;; *) printf '%s' "$1"; return ;; esac
  case "$target" in /*) ;; *) target="$1/$target" ;; esac
  if [ -d "$target" ]; then (cd "$target" && pwd -P); else printf '%s' "$1"; fi
}

# A test file only narrows the run as a POSITIONAL word: the value of an option
# (`--outputFile x.test.json`, `--exclude src/a.test.tsx`) does not. The flags
# below and every `--no-*` leave the next word positional; any other option
# takes it, so an unknown flag right before a file blocks rather than lets a
# full run through. The list is exact and case-sensitive: every option name
# for which Vitest 4.1.11's own parseCLI keeps `vitest run --<name> x` as a
# filter. Regenerate it when web/ moves to a new Vitest.
VITEST_FLAGS=" w watch ui open api.strictPort api.allowExec api.allowWrite hideSkippedTests coverage coverage.enabled coverage.clean coverage.cleanOnRerun coverage.reportOnFailure coverage.allowExternal coverage.skipFull coverage.thresholds.100 coverage.thresholds.perFile coverage.excludeAfterRemap isolate globals dom browser.enabled browser.headless browser.api.strictPort browser.api.allowExec browser.api.allowWrite browser.isolate browser.ui browser.fileParallelism browser.trackUnhandledErrors browser.locators.exact fileParallelism passWithNoTests logHeapUsage detectAsyncLeaks allowOnly dangerouslyIgnoreUnhandledErrors sequence.shuffle sequence.shuffle.files sequence.shuffle.tests sequence.concurrent diff.expand diff.includeChangeCounts diff.omitAnnotationLines diff.printBasicPrototype expandSnapshotDiff disableConsoleIntercept typecheck typecheck.enabled typecheck.only typecheck.allowJs typecheck.ignoreSourceErrors cache expect.requireAssertions printConsoleTrace includeTaskLocation run color clearScreen standalone clearCache strictTags experimental.fsModuleCache experimental.importDurations experimental.importDurations.failOnDanger experimental.importDurations.thresholds experimental.viteModuleRunner experimental.nodeLoader experimental.preParse "
takes_value() {
  local f=${1#-}
  f=${f#-}
  case "$f" in ''|*=*|no-*) return 1 ;; esac
  [[ $VITEST_FLAGS != *" $f "* ]]
}
names_test_file() {
  local w prev="" words
  read -r -a words <<< "$1"
  for w in "${words[@]}"; do
    case "$w" in
      -*) ;;
      # A plain variable names one file; `$@`, `$*`, `$(...)` do not (Accepted failure mode 1: it may be empty at run time).
      '$'[A-Za-z_]*|'"$'[A-Za-z_]*'"'|'${'[A-Za-z_]*'}'|'"${'[A-Za-z_]*'}"')
        case "$w" in *[!A-Za-z0-9_\$\{\}\"]*) ;; *)
          case "$prev" in -*) takes_value "$prev" || return 0 ;; *) return 0 ;; esac ;;
        esac ;;
      *.test.*|*.spec.*|*__tests__*)
        case "$prev" in -*) takes_value "$prev" || return 0 ;; *) return 0 ;; esac ;;
    esac
    prev=$w
  done
  return 1
}

SUITE_RE='(^|[[:space:];&|(`])(npm[[:space:]]+(run[[:space:]]+)?(test|typecheck)(:[a-z:-]+)?|npx[[:space:]]+tsc|tsc[[:space:]]|npx[[:space:]]+vitest|vitest[[:space:]])'

# --- builders leave the merge chain's checks to the chain -------------
# Two dev-4-room builders spent ~29 minutes in whole-project checks the chain
# runs anyway. A linked worktree seat only; main and the chain never block.
# Blocks `test:guards` and the coverage gate in any form (the gate runs the
# whole backend and web suites; main runs it once per plan before the merge),
# root `npm run test:unit` always (npm appends
# `-- <file>` AFTER the script's own full file list, so naming a file still runs
# every test), web `test:unit` always (its integrity wrapper ignores file
# arguments), and web `test:unit:raw` or `vitest run` with no test file named.
# A script file a segment runs gets the same checks, one level deep, and so does
# the whole-suite file list (`scripts/test-unit-files.sh`) under `node --test`,
# typed or scripted: a builder once ran the coverage gate twice from a /tmp
# script this hook never saw.
# ponytail: a script behind a wrapper (`timeout 900 bash x.sh`), a script run by
# a script, and `bash -c '...'` prose are not seen; widen seg_script if used.
#
# The same walk resolves the directory the suite runs in: the rerun state below
# is keyed on it, not on the payload's cwd.
RULE3=".claude/briefs/_implementer-tools.md rule 3"
# npm's own options may sit between `run` and the script name
# (`npm run --silent test:guards`), each with an optional value.
NPM_RUN='(^|[[:space:](])npm([[:space:]]+[^[:space:]]+)*[[:space:]]+run(-script)?([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+'
ONE_WEB_FILE='npm --prefix web run test:unit:raw -- src/x.test.tsx'
DEFER=" Do not ask main: if you still need that check, record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on."
COVERAGE_BLOCK="BLOCKED: the coverage gate runs the whole backend and web suites; main runs it once per plan before the merge, not a builder ($RULE3). Run instead: npm run test:changed.$DEFER"
printf '%s' "$CMD" | grep -qE "$SUITE_RE|test:(guards|unit|coverage)|test-coverage\.sh|test-unit-files\.sh|vitest|(^|[[:space:];&|(])((bash|sh|zsh|source|\.)[[:space:]]|\.?/)" || exit 0

in_worktree() {
  [ "$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null)" \
    != "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ]
}

# Prints the script file segment $2 runs from directory $1: `bash|sh|zsh
# <file>`, `source|. <file>`, or a `./` or absolute executable. Tracked files
# are left out: the repo's own scripts are reached by their npm names, checked
# here, and scripts/test-changed.sh reads the whole-suite list legitimately.
seg_script() {
  local w f="" i=0
  read -r -a w <<< "$2"
  while [[ ${w[i]:-} == [A-Za-z_]*=* ]]; do i=$((i+1)); done
  case "${w[i]:-}" in
    bash|sh|zsh) for f in "${w[@]:i+1}"; do [[ $f == -* ]] || break; done
      [[ $f == -* ]] && f="" ;;
    source|.) f=${w[i+1]:-} ;;
    ./*|/*) f=${w[i]} ;;
  esac
  [ -n "$f" ] || return 1
  case "$f" in /*) ;; *) f="$1/$f" ;; esac
  [ -f "$f" ] && grep -Iq . "$f" || return 1
  case "${w[i]}" in ./*|/*) [ -x "$f" ] || return 1 ;; esac
  git -C "$(dirname "$f")" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 && return 1
  printf '%s' "$f"
}

# Walks the segments of text $1 from $D; $2 is set inside a script. A builder
# seat is its payload cwd too: a script is often run from /tmp and cds itself.
builder_checks() {
  local SEG F SAVED SEGS
  chain_split "$1"; SEGS=$CS_PLAIN
  if [ -z "$MODE" ] && printf '%s' "$SEGS" | grep -q 'test-unit-files\.sh' \
    && printf '%s' "$SEGS" | grep -qE -- '--test([[:space:]]|$)' \
    && { in_worktree "$D" || in_worktree "$CWD"; }; then
    echo "$COVERAGE_BLOCK" >&2
    exit 2
  fi
  while IFS= read -r SEG; do
    D=$(seg_cd "$D" "$SEG")
    [ -z "$RUN_CWD" ] && [ -z "${2:-}" ] && printf '%s' "$SEG" | grep -qE "$SUITE_RE" && RUN_CWD=$D
    if [ -z "$MODE" ] && [ -z "${2:-}" ] && F=$(seg_script "$D" "$SEG"); then
      SAVED=$D
      builder_checks "$(cat "$F")" script
      D=$SAVED
    fi
    [ -z "$MODE" ] && printf '%s' "$SEG" | grep -qE 'test:(guards|unit|coverage)|test-coverage\.sh|vitest' \
      && in_worktree "$D" || continue
    if printf '%s' "$SEG" | grep -qE "${NPM_RUN}test:guards(:[^[:space:]]*)?([[:space:])]|$)"; then
      echo "BLOCKED: test:guards is the merge chain's check, not a builder's ($RULE3). Run instead: npm run test:changed.$DEFER" >&2
      exit 2
    fi
    if printf '%s' "$SEG" | grep -qE "${NPM_RUN}test:coverage(:gate)?([[:space:])]|$)|test-coverage\.sh[[:space:]]+(gate|backend|web)"; then
      echo "$COVERAGE_BLOCK" >&2
      exit 2
    fi
    if printf '%s' "$SEG" | grep -qE "${NPM_RUN}test:unit(:[^[:space:]]*)?([[:space:])]|$)"; then
      if printf '%s' "$SEG" | grep -qE -- '--prefix[[:space:]=]+([^[:space:]]*/)?web/?([[:space:]]|$)' || [ "$(basename "$D")" = web ]; then
        if printf '%s' "$SEG" | grep -qE "${NPM_RUN}test:unit([[:space:])]|$)"; then
          echo "BLOCKED: web test:unit runs the whole suite even with files named; its integrity wrapper ignores them ($RULE3). Run instead: npm run test:changed, or one file: $ONE_WEB_FILE.$DEFER" >&2
          exit 2
        fi
        names_test_file "$SEG" && continue
        echo "BLOCKED: a full web test:unit run is the merge chain's job ($RULE3). Run instead: npm run test:changed, or name the test files ($ONE_WEB_FILE).$DEFER" >&2
        exit 2
      fi
      [ "$(basename "$D")" = infra ] && continue
      echo "BLOCKED: root npm run test:unit runs every test file, even with -- <file> named ($RULE3). Run instead: npm run test:changed, or one file: node --max-old-space-size=4096 --test --require ts-node/register <file>.$DEFER" >&2
      exit 2
    fi
    if printf '%s' "$SEG" | grep -qE '(^|[[:space:](/])vitest[[:space:]]+run([[:space:]]|$)' \
      && ! names_test_file "$SEG"; then
      echo "BLOCKED: a full vitest run is the merge chain's job ($RULE3). Run instead: npm run test:changed, or name the test files (npx vitest run src/x.test.tsx).$DEFER" >&2
      exit 2
    fi
  done <<< "$SEGS"
}
D=$CWD
RUN_CWD=""
builder_checks "$CMD"
CWD=${RUN_CWD:-$D}
# Match the words that run, not quoted prose: a message body naming `npm test`
# is not a suite run.
chain_split "$CMD"; SEGS=$CS_PLAIN

printf '%s' "$SEGS" | grep -qE "$SUITE_RE" || exit 0

# --- bare `npm test` ---------------------------------------------------------
if [ -z "$MODE" ] && printf '%s' "$SEGS" | grep -qE '(^|[[:space:];&|(])npm[[:space:]]+test([[:space:]]|$)' \
  && ! printf '%s' "$SEGS" | grep -q 'infra' && [ "$(basename "$CWD")" != infra ]; then
  echo "BLOCKED: bare 'npm test' is guards + unit + the infra jest suite (~11 min); a '-- <filter>' reaches only the infra leg. Run the one you need: npm run test:changed, npm run test:unit, npm run test:guards, or (cd infra && npm test -- <name>). .claude/rules/tests.md, Rerun guard." >&2
  echo "Try: npm run test:changed" >&2
  exit 2
fi

# --- same run, same tree, within 30 minutes -----------------------------------
printf '%s' "$SEGS" | grep -qE '(^|[[:space:];&|(])RERUN=1([[:space:]]|$)' && exit 0

# The key is every suite segment, in order, with cd steps, pipe stages and
# redirections dropped: `npm run test:unit 2>&1 | tail -40` and
# `npm run test:unit | grep FAIL` are the same run, but a suite after the pipe
# is a new one.
KEY=$(printf '%s\n' "$CS_KEPT" | grep -E "$SUITE_RE" | paste -sd ';' -)

TREE=$( {
  git -C "$CWD" rev-parse HEAD 2>/dev/null
  printf 'WORKTREE\0'
  git -C "$CWD" diff 2>/dev/null
  printf 'INDEX\0'
  git -C "$CWD" diff --cached 2>/dev/null
  printf 'UNTRACKED\0'
  while IFS= read -r -d '' file; do
    printf '%s\0' "$file"
    git -C "$CWD" hash-object -- "$file" 2>/dev/null || printf 'missing\n'
  done < <(git -C "$CWD" ls-files --others --exclude-standard -z 2>/dev/null)
} | sha1sum | cut -c1-40)
[ -n "$TREE" ] || exit 0

DIR="${CONVEYOR_SUITE_RUNS_DIR:-$HOME/.cache/conveyor/suite-runs}"
mkdir -p "$DIR" 2>/dev/null || exit 0
STATE="$DIR/$(printf '%s|%s' "$CWD" "$KEY" | sha1sum | cut -c1-40)"
NOW=$(date +%s)

# --- PostToolUse: the run finished, so it counts ------------------------------
if [ "$MODE" = complete ]; then
  # An interrupted call produced no result to read, so it must not stand in
  # for one.
  if [ "$(printf '%s' "$INPUT" | jq -r '.tool_response.interrupted // false' 2>/dev/null)" = true ]; then
    rm -f "$STATE"
    exit 0
  fi
  [ -f "$STATE" ] || exit 0
  read -r THEN LAST_TREE _ < "$STATE"
  printf '%s %s complete\n' "${THEN:-$NOW}" "$LAST_TREE" > "$STATE"
  exit 0
fi

if [ -f "$STATE" ]; then
  read -r THEN LAST_TREE STATUS < "$STATE"
  AGE=$(( (NOW - ${THEN:-0}) / 60 ))
  # Only a run that FINISHED is a result you saw. A pending record is an
  # attempt another hook refused, or one that was interrupted before it
  # started, and blocking on it strands the tree until the 30 minutes lapse.
  if [ "${STATUS:-}" = complete ] && [ "$LAST_TREE" = "$TREE" ] && [ "$AGE" -lt 30 ]; then
    echo "BLOCKED: '$KEY' already ran $AGE min ago in $CWD with NO edit since -- the result is what you saw. Save the output next time (... > \"\$SCRATCH/run.log\") and read the file. Checking a flake? Prefix the command with RERUN=1. .claude/rules/tests.md, Rerun guard." >&2
    # A flake check on purpose: the same one-line command behind the override.
    case "$CMD" in *$'\n'*) ;; *) echo "Try: RERUN=1 $CMD" >&2 ;; esac
    exit 2
  fi
fi

# --- a worker sees its diff once, before its first suite run -----------
# Advice only, never a block: a run spent on files the brief does not name is the loss it prevents. One marker per
# session, made with noclobber (O_EXCL), so of two calls released together exactly one creates it and prints. A marker
# that cannot be made prints nothing (the next run may print it again). No session_id (a Codex pane) gets nothing.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' | tr -c 'A-Za-z0-9_-' '_')
if [ -n "$SID" ] && [ "${CONVEYOR_REVIEWER:-}" != 1 ] && in_worktree "$CWD" && ( set -C; : > "$DIR/diffstat-$SID" ) 2>/dev/null; then
  BASE=$(git -C "$CWD" merge-base main HEAD 2>/dev/null)
  if [ -n "$BASE" ]; then
    UNT=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null)
    NUNT=$(printf '%s' "$UNT" | grep -c '')
    jq -n --arg stat "$(git -C "$CWD" diff --stat "$BASE" 2>/dev/null)" --arg unt "$(printf '%s\n' "$UNT" | head -20)" --argjson n "$NUNT" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext:
        ("Your diff against main, before this first test run (compare with the files your brief names):\n" + $stat
         + (if $n > 0 then "\nUntracked:\n" + $unt + (if $n > 20 then "\n... and \($n - 20) more" else "" end) else "" end))}}'
  fi
fi
printf '%s %s pending\n' "$NOW" "$TREE" > "$STATE"
exit 0
