#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook (Bash + Edit|Write): block adding a NEW npm dependency
# without the owner's explicit approval. Rule 2: prefer the
# stdlib, an existing helper (shared/, src/utils/), or a few lines of code
# over a new package. A new dependency is the highest-signal mechanical
# proxy for over-engineering -- and a supply-chain surface.
#
# Approval flow: hooks NEVER see inline env prefixes (they are separate
# harness-spawned processes), so approval rides IN the command text, and it
# must be the DOCUMENTED PREFIX form -- anchored at the start so a compound
# command, commit message, or echo that merely mentions the token cannot
# leak approval to anything else in the same command:
#   CONVEYOR_DEP_APPROVED=1 npm install <pkg>
# A package.json edit has no command string to carry that prefix, and in a
# linked worktree node_modules is a symlink to the main checkout's copy, so the
# install form is not always available. There the approval is an EXACT name in
# the environment, the same shape flag-addition-guard uses:
#   CONVEYOR_DEP_APPROVED=<pkg>[,<pkg>]   (.claude/settings.local.json env)
# No prefixes, no wildcards, so approving one package cannot approve its
# neighbour, and an unapproved name in the same edit still blocks.
#
# Deliberately allowed: bare `npm install` / `npm ci` (lockfile-driven),
# version bumps of EXISTING deps in package.json.
# Accepted over-match class: substring matching of command text can block
# prose that looks like an install command -- loud and cheap, reword it.
#
# THREAT MODEL (charter): this is a TRIPWIRE against sloppiness -- forgetting
# to ask before reaching for a package -- not a security boundary against a
# deliberately evasive operator (who could trivially bypass any text-matching
# hook). Evasion-class review findings are out of scope by design. The `i`
# alias stays out of the loose tier (there it made ordinary compounds
# false-block); `npm --prefix <dir> i <pkg>` is caught by dropping npm's valued
# flags before the tight tier reads the command.

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

block() {
  echo "BLOCKED: adding a new dependency ($1) requires the owner's explicit approval first." >&2
  echo "Rule 2: check the stdlib, an already-installed package, or an existing helper in shared/ or src/utils/ before reaching for a new package." >&2
  echo "If the owner has approved this exact package, install it with the token as the COMMAND PREFIX: CONVEYOR_DEP_APPROVED=1 npm install <pkg> (one command per approval; package.json direct edits stay blocked -- the install writes it)." >&2
  echo "Or: the owner answers Yes today to a picker headed exactly \"Dep <pkg>\" in the main checkout, for each package it adds." >&2
  echo "If you need this package, record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on without it; do not ask main." >&2
  exit 2
}

# owner_approved <pkg>: the owner's latest answer today to a picker headed exactly "Dep <pkg>" is Yes, read from the
# decision log by approval.sh. The name is compared whole, so "Dep @types/node" approves no other package.
owner_approved() {
  bash "${BASH_SOURCE[0]%/*}/../scripts/approval.sh" "Dep $1" 2>/dev/null
}

# cmd_approved <command text>: every word after a package manager's install, i or add in it, flags aside, is a
# package the owner approved by picker today. The manager may be any word before the install, so a wrapper (env npm
# install, sudo pip install) still names its packages, while a command with no manager word (git add package.json)
# names none. Git's own options and their folders are not manager words (git -C pnpm add x, git -C./pnpm add x,
# git --git-dir=pnpm/.git add x, env git -C pnpm add x name none), but the rest of a git command is read, so an alias that runs an install (git -c alias.d='!npm install x' d) still names its packages. A manager word
# that is only another command's argument is read as an install: a false block, never a missed one.
# False when it names none, so a form it cannot read still blocks. In an npm command a
# valued flag's value is not a package (pnpm's -w is a switch). A version is not part of the name: lodash@4,
# @types/node@20 and requests>=2 are lodash, @types/node and requests.
# Its limit, accepted: it recognises plain install commands of the package managers. An unusual argument shape (for
# example a directory argument named like a package manager) may be read wrongly, and is out of scope.
cmd_approved() {
  local pkgs p
  pkgs=$(printf '%s\n' "$1" | sed -E 's/(&&|\|\||[;|&()])/\n/g' \
    | awk '{ f = 0; npm = 0; mgr = 0; skip = 0; git = 0
        for (i = 1; i <= NF; i++) {
          if (skip) { skip = 0; continue }
          if (git && !mgr && $i ~ /^-/) { skip = ($i ~ /^(-C|--git-dir|--work-tree|--namespace)$/); continue }
          if (npm && $i ~ /^(--prefix|--workspace|-w|-C|--registry|--loglevel|--cache|--userconfig)$/) { skip = 1; continue }
          if (f) { if ($i !~ /^-/) { n = substr($i, 2); sub(/@.*/, "", n); n = substr($i, 1, 1) n
                     sub(/[][=<>!~;].*/, "", n); print n } }
          else if ($i ~ /(^|\/)git$/) git = 1
          else if ($i ~ /(^|[\/!])npm$/) npm = mgr = 1
          else if ($i ~ /(^|[\/!])(yarn|pnpm|pip3?|uv)$/) mgr = 1
          else if (mgr && ($i == "install" || $i == "i" || $i == "add")) f = 1 } }')
  [ -n "$pkgs" ] || return 1
  for p in $pkgs; do owner_approved "$p" || return 1; done
}

# ran <command> -- the text bash runs, for the matchers below. A quoted
# span is skipped only on a line where EVERY command is a sender, below: there
# it is a message body, a commit message, an issue body. Any other line is
# read whole (whole, below), so a form nobody listed is judged as an install:
# the worst case is a false block, never a missed install. Past a false block:
# put the text in a file (--body-file, -F).
# A line is a senders' line when each command on it, between `;`, `&&`, `||`,
# `|`, `&`, brackets and line ends, starts with a sender's bare name, no
# backtick and no `$(` runs in it, and every here-document on it has a quoted end word
# (bash expands nothing in those; their bodies are dropped). strip_quoted reads
# the spans (the reader git-safety.sh uses): a one-word
# span stays the word it is, a span of several words becomes $QUOTED.
# Commands that only carry text; none runs a quoted word given to it.
SENDERS='gh|git[[:space:]]+(commit|tag|notes|status|log|diff|show|add)|echo|printf|cat|rg|grep|(bash[[:space:]]+)?[^[:space:]]*decision\.sh'
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null || true
ran() {
  local M=$'\x01' CODE SEG
  # Whether anything can run a word is asked of the reader's own output, never
  # of the raw text: it alone knows which `<<` opens a here-document, so one
  # named in a comment or a quoted string hides no line after it. What
  # it prints holds every backtick and `$(` that runs, and each quoted end word
  # as a mark after its `<<`; a here-document with any other end word expands
  # its body, which the reader drops, so the whole command is read instead.
  # An end word is plain here: bash-guardrails.sh refuses every other one.
  if declare -F strip_quoted >/dev/null && CODE=$(strip_quoted "$1" "$M") && [[ $CODE != *'`'* && $CODE != *'$('* ]] \
    && ! grep -qE "<<-?[[:space:]]*[^[:space:]$M<-]" <<<"${CODE//<<</ }"; then
    CODE=$(sed -E "s/$M([^[:space:]$M])/\1/g; s/$M/ \$QUOTED /g" <<<"$CODE")
    while IFS= read -r SEG; do
      [[ $SEG =~ ^[[:space:]]*$ || $SEG =~ ^[[:space:]]*($SENDERS)([[:space:]]|$) ]] || { whole "$1"; return; }
    done < <(sed -E 's/[0-9]*[<>]&[0-9-]*//g; s/&&|\|\||[;|&()]/\n/g' <<<"$CODE")
    printf '%s' "$CODE"
  else
    whole "$1"
  fi
}
# The whole line as code: a quote mark is a word break, so `bash -c 'npm ci'`
# reads as npm ci. A quoted folder with a space becomes $QUOTED, which blocks
# as a folder the guard cannot read, instead of its first word.
whole() {
  printf '%s' "$1" | sed -E "s/(cd|pushd|--prefix|-C)([[:space:]=]+)\\\\?(\"[^\"']*[[:space:]][^\"']*\"|'[^\"']*[[:space:]][^\"']*')/\1\2\$QUOTED /g" \
    | tr "\"'\`" '   ' | sed 's/<<</ /g'
}

if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  [ -z "$CMD" ] && exit 0
  # Normalize backslash-newline continuations so a split command matches the
  # same as its single-line form.
  CMD=$(printf '%s' "$CMD" | sed -z 's/\\\n/ /g')
  RAN=$(ran "$CMD")
  # npm ci replaces node_modules. In a worker worktree that is a symlink to the
  # main checkout's shared copy, and npm ci there wiped it for every worktree.
  # Checked before the approval shortcut: no approval covers it. The guard does
  # not follow the shell's folder moves: which `cd` took effect depends on `&&`,
  # `||`, `;`, subshells and exit codes. EVERY npm ci on the line is
  # judged in every folder the line could be in by then -- the payload's cwd and
  # each `cd`/`pushd` target that exists -- or, with `--prefix <dir>`, in that
  # folder under each of them, and passes only when none holds a link. A folder
  # may be quoted. One this cannot read (`$VAR`, a command substitution,
  # `cd -`, `popd`, a pattern, an option) blocks: it could be the linked one.
  # Ceiling: CDPATH is not read, so a relative `cd` it sends elsewhere is missed.
  # It reads the text bash runs (ran, above).
  NPM_CI='(^|[;&|([:space:]])(\S*/)?npm([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+ci([[:space:];&|)]|$)'
  if grep -qE "$NPM_CI" <<<"$RAN"; then
    NPM_CWD=$(echo "$INPUT" | jq -r '.cwd // empty'); NPM_CWD=${NPM_CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}
    WORD="\"[^\"]*\"|'[^']*'|[^[:space:]]+"
    WAY_OUT="Run it from the folder itself, or name the folder: npm --prefix <folder> ci"
    NPM_DIRS=("$NPM_CWD"); UNREAD=""
    folders() { # <dir as written> -- every folder it could name, one per line; fails when it cannot be read
      local d=$1 b
      d=${d#[\"\']}; d=${d%[\"\']}
      case "$d" in "~"|"~/"*) d=$HOME${d#\~} ;; esac
      case "$d" in
        # Not a folder name it can look up: a variable, a substitution, another user's home, a
        # pattern, an option, or `-`/`+N`, which go where an earlier command left the shell.
        ""|*'$'*|*'`'*|"~"*|-*|+*|*[*?[{]*) return 1 ;;
        /*) printf '%s\n' "$d" ;;
        *) for b in "${NPM_DIRS[@]}"; do printf '%s\n' "$b/$d"; done ;;
      esac
    }
    while IFS= read -r SEG || [ -n "$SEG" ]; do
      if [[ $SEG =~ (^|[[:space:]])(cd|pushd)[[:space:]]+($WORD) ]]; then
        if TO=$(folders "${BASH_REMATCH[3]}"); then
          while IFS= read -r D; do [ ! -d "$D" ] || NPM_DIRS+=("$D"); done <<<"$TO"
        else
          UNREAD=${BASH_REMATCH[3]}
        fi
      elif [[ $SEG =~ (^|[[:space:]])cd[[:space:]]*$ ]]; then
        NPM_DIRS+=("$HOME")
      elif [[ $SEG =~ (^|[[:space:]])popd([[:space:]]|$) ]]; then
        UNREAD=popd
      fi
      grep -qE "$NPM_CI" <<<"$SEG" || continue
      [ -z "$UNREAD" ] || { echo "BLOCKED: npm ci after a move to $UNREAD, a folder this guard cannot read, so it cannot tell whether node_modules there is the shared copy. $WAY_OUT" >&2; exit 2; }
      CI_DIRS=$(printf '%s\n' "${NPM_DIRS[@]}")
      if [[ $SEG =~ (--prefix|-C)[=[:space:]]+($WORD) ]]; then
        CI_DIRS=$(folders "${BASH_REMATCH[2]}") \
          || { echo "BLOCKED: npm ci into ${BASH_REMATCH[2]}, a folder this guard cannot read, so it cannot tell whether node_modules there is the shared copy. Name the folder in full." >&2; exit 2; }
      fi
      while IFS= read -r CI_DIR; do
        [ -L "$CI_DIR/node_modules" ] || continue
        echo "BLOCKED: npm ci in $CI_DIR would replace node_modules, a symlink to the shared copy at $(readlink "$CI_DIR/node_modules"); every worktree using it would lose its modules." >&2
        echo "A worker never reinstalls the shared copy. If package-lock.json changed, main installs in the main checkout; local-checks reuses a link whose lockhash matches." >&2
        [ "$CI_DIR" = "$NPM_CWD" ] || [ "${#NPM_DIRS[@]}" = 1 ] \
          || echo "This line could run it in more than one folder ($(printf '%s, ' "${NPM_DIRS[@]}" | sed 's/, $//')), and the guard does not follow which move took effect." >&2
        echo "For an install meant for another folder: $WAY_OUT" >&2
        exit 2
      done <<<"$CI_DIRS"
    # A redirection's `&` (2>&1, &>) is not a separator.
    done < <(printf '%s' "$RAN" | tr '\n' ';' | sed -E 's/[0-9]*[<>]&[0-9-]*//g; s/&>/>/g; s/(&&|\|\||[;|&()])/\n\1\n/g')
  fi
  # Anchored: approval must be the documented prefix of THE command, exactly
  # =1 -- `=10`, a token quoted mid-command, or a second command chained after
  # an approved one must NOT inherit approval. Approval covers ONE simple
  # command: with separators present, the approved first segment is stripped
  # and the REMAINDER re-enters matching, so `APPROVED=1 npm install ok &&
  # npm install sneaky` still blocks on sneaky.
  if echo "$CMD" | grep -qE '^[[:space:]]*CONVEYOR_DEP_APPROVED=1[[:space:]]'; then
    CMD=$(printf '%s' "$CMD" | tr '\n' ';')
    case "$CMD" in
      *';'*|*'&'*|*'|'*)
        CMD=$(printf '%s' "$CMD" | sed -E 's/^[[:space:]]*CONVEYOR_DEP_APPROVED=1[[:space:]][^;&|]*//')
        ;;
      *) exit 0 ;;
    esac
  fi
  # Two matcher tiers, both fail-closed:
  # TIGHT: manager + optional flags + subcommand (incl. `i`) + flags + pkg.
  # LOOSE: manager + ANY tokens (catches valued flags like --prefix web /
  #        --cwd web / workspace X) + install/add + flags (incl. bare --) + pkg.
  #        `i` is excluded from LOOSE -- too short to survive arbitrary tokens.
  # A redirection is not a package, and neither is what follows a separator:
  # the package position stops at `;`, `&`, `|` and `)`.
  CMD=$(ran "$CMD")
  CMD=$(sed -E 's/[[:space:]]*[0-9]*(>>?|<)&?[[:space:]]*[^;&|<>[:space:]]+//g' <<<"$CMD")
  # npm's flags that take a value: dropped with the value, so `npm install
  # --prefix web` is a bare install and `npm --prefix web i lodash` is not
  # one. Read for npm only: `-w` is a switch in pnpm.
  NPM_CMD=$(sed -E 's/[[:space:]](--prefix|--workspace|-w|-C|--registry|--loglevel|--cache|--userconfig)([[:space:]]+|=)[^;&|[:space:]]+//g' <<<"$CMD")
  TRAIL='([[:space:]]+-{1,2}\S*)*'
  TIGHT_FLAGS='([[:space:]]+-{1,2}[^-[:space:]]\S*)*'
  PKG='[[:space:]]+[^-;&|)[:space:]]'
  NPM_TIGHT='(\S*/)?npm'"$TIGHT_FLAGS"'[[:space:]]+(install|i|add)'"$TRAIL$PKG"
  # LOOSE token runs must NOT cross command separators: with plain \S+ they
  # consumed `&&` and whole commands, so `npm ci && git add .` false-blocked
  # (the `add` belongs to git) -- round-4 regression, one class per tier.
  NPM_LOOSE='(\S*/)?npm([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+(install|add)'"$TRAIL$PKG"
  YARN_LOOSE='(\S*/)?yarn([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+add'"$TRAIL$PKG"
  PNPM_LOOSE='(\S*/)?pnpm([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+add'"$TRAIL$PKG"
  NPMPKG='(\S*/)?npm[[:space:]]+pkg[[:space:]]+set[[:space:]]+\S*[Dd]ependencies'
  # An install the owner approved by picker passes when every package it names is approved; `npm pkg set` names no
  # package and always blocks.
  if grep -qE "(^|[;&|([:space:]])($NPM_TIGHT|$NPM_LOOSE)" <<<"$NPM_CMD" \
    || grep -qE "(^|[;&|([:space:]])($YARN_LOOSE|$PNPM_LOOSE)" <<<"$CMD"; then
    cmd_approved "$CMD" || block "via package-manager command"
  fi
  if grep -qE "(^|[;&|([:space:]])$NPMPKG" <<<"$CMD"; then
    block "via package-manager command"
  fi
  # Python installers. `-r <file>` installs what a requirements file
  # already pins, pip's lockfile-driven form, so it is dropped before matching;
  # a package named beside it still blocks.
  PY_CMD=$(sed -E 's/[[:space:]](-r|--requirement)([[:space:]]+|=)[^;&|[:space:]]+//g' <<<"$CMD")
  PY_ADD='(\S*/)?(pip3?([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+install|uv([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+add)'"$TRAIL"'[[:space:]]+[^-;&|[:space:]]'
  if grep -qE "(^|[;&|[:space:]])$PY_ADD" <<<"$PY_CMD"; then
    cmd_approved "$PY_CMD" || block "via package-manager command"
  fi
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
PY_MANIFEST=0
case "${FILE_PATH##*/}" in
  package.json) ;;
  requirements*.txt|pyproject.toml) PY_MANIFEST=1 ;;
  *) exit 0 ;;
esac

block_manifest() {
  owner_approved "$1" && return 0
  echo "BLOCKED: adding a new dependency ('$1' in $FILE_PATH) requires the owner's explicit approval first." >&2
  echo "Rule 2: check the stdlib, an already-installed package, or an existing helper in shared/ or src/utils/ before reaching for a new package." >&2
  echo "Once the owner has approved THIS package: CONVEYOR_DEP_APPROVED=$1 (exact, comma-separated for several) in .claude/settings.local.json env, or install it with CONVEYOR_DEP_APPROVED=1 npm install <pkg> as the command prefix." >&2
  echo "Or: the owner answers Yes today to a picker headed exactly \"Dep $1\" in the main checkout." >&2
  echo "If you need this package, record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on without it; do not ask main." >&2
  exit 2
}

unreadable_manifest() {
  echo "BLOCKED: $1" >&2
  exit 2
}

# MultiEdit carries an edits[] array; every new_string is concatenated so a
# dependency added through any hunk is still seen. One definition of that
# across every content-screening hook: lib/edit-payload.sh.
#
# SOURCED HERE, BELOW THE BASH BRANCH, deliberately. This hook is registered on
# Bash as well as on the file tools. A load failure must block the write it
# cannot screen -- but blocking every Bash command too would leave no way to run
# the `git checkout` that restores the helper. The Bash branch has already
# returned by this point, so it never depends on the helper.
source "$(dirname "${BASH_SOURCE[0]}")/lib/edit-payload.sh" 2>/dev/null
hook_payload_loaded 2>/dev/null || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load .claude/hooks/lib/edit-payload.sh, so it cannot screen this write. Restore it (git checkout .claude/hooks/lib/edit-payload.sh) and retry." >&2; exit 2; }
CONTENT=$(hook_new_text "$INPUT")
[ -z "$CONTENT" ] && exit 0
APPROVED=",${CONVEYOR_DEP_APPROVED:-},"
# Both readers below place an edit at the first match of its old text. A Codex
# hunk lands where its `@@` anchor says, which this hook never sees, so old text
# that is in the file more than once is refused (readers exit 3), not guessed.
ambiguous() {
  echo "BLOCKED: this edit's old text is in $FILE_PATH more than once, so where it lands cannot be told and it cannot be screened for a new dependency. Give the edit enough of its surrounding lines to match once." >&2
  exit 2
}

# Python manifests: the edit is applied to the file on disk and the
# names the result declares are compared with the names it declares now; a
# name only the result has is new. Names are PEP 503-normalised, so a case or
# separator change is not new. A new name is approved in its normalised form or
# as any line of the result spells it, so a Yes to "Dep My_Pkg" lets in
# My_Pkg==1.0 even with my.pkg written above it. An
# option line (`-e`, `--index-url`) counts whole, so a new one blocks too. A
# manifest this cannot read blocks.
if [ "$PY_MANIFEST" = 1 ]; then
  NEW=$(printf '%s' "$INPUT" | python3 -I -c '
import json, os, re, sys
payload = json.load(sys.stdin)
ti = payload.get("tool_input") or {}
path = sys.argv[1]
before = open(path).read() if os.path.exists(path) else ""
if payload.get("tool_name") == "Write":
    after = ti.get("content") or ""
else:
    after = before
    for e in (ti.get("edits") or [ti]):
        old, new = e.get("old_string"), e.get("new_string")
        if old is None or new is None:
            continue
        if old and old not in after:
            raise SystemExit(1)
        if old and not e.get("replace_all") and after.count(old) > 1:
            raise SystemExit(3)
        after = after.replace(old, new, -1 if e.get("replace_all") else 1) if old else after + new
def names(text):
    if path.endswith(".toml"):
        import tomllib
        doc = tomllib.loads(text)
        project = doc.get("project", {})
        specs = list(project.get("dependencies", [])) + list(doc.get("build-system", {}).get("requires", []))
        for group in (project.get("optional-dependencies", {}), doc.get("dependency-groups", {})):
            for v in group.values():
                specs += [s for s in v if isinstance(s, str)]
    else:
        specs = [l for l in text.splitlines() if not l.lstrip().startswith("#")]
    out = {}
    for s in specs:
        # A bare URL names its package only in the URL, so it counts whole, as
        # an option line does: read as a name, every one of them was `https`.
        if s.lstrip().startswith("-") or re.match(r"\s*[A-Za-z][A-Za-z0-9+.-]*://", s):
            out.setdefault(s.strip(), set()).add(s.strip())
            continue
        m = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._-]*)", s)
        if m:
            out.setdefault(re.sub(r"[-_.]+", "-", m.group(1)).lower(), set()).add(m.group(1))
    return out
# One JSON array per new name, so an option line with a tab or newline in it
# stays one spelling. A NUL would split it again where the shell reads it.
if "\0" in after:
    raise SystemExit(1)
spelt = names(after)
for n in sorted(spelt.keys() - names(before).keys()):
    print(json.dumps([n] + sorted(spelt[n])))
' "$FILE_PATH" 2>/dev/null) || {
    [ $? != 3 ] || ambiguous
    echo "BLOCKED: could not read the dependencies $FILE_PATH would declare after this edit, so it cannot be screened for a new one." >&2
    exit 2
  }
  while IFS= read -r RECORD; do
    [ -n "$RECORD" ] || continue
    mapfile -d '' -t SPELLINGS < <(jq -j '.[] | ., "\u0000"' <<<"$RECORD")
    for SPELT in "${SPELLINGS[@]}"; do
      case "$APPROVED" in *",$SPELT,"*) continue 2 ;; esac
      owner_approved "$SPELT" && continue 2
    done
    block_manifest "${SPELLINGS[1]}"
  done <<<"$NEW"
  exit 0
fi

# What the manifest will SAY once this edit lands is the question, so the edit
# is applied to the file on disk and the result's dependency maps are read.
# Guessing at a fragment's line shapes answered a different one: a "version"-
# shaped metadata key, a script name, or a URL in an unrelated section all read
# as packages, and a real addition written in a shape the regex did not know
# read as nothing.
PY_OK=1
CANDIDATES=$(printf '%s' "$INPUT" | python3 -I -c '
import json, os, sys
payload = json.load(sys.stdin)
ti = payload.get("tool_input") or {}
path = sys.argv[1]
# Exit 4: the file on disk is not JSON; exit 5: the result would not be. Either
# way the dependency maps cannot be read, and guessing from line shapes named
# the wrong package.
if os.path.exists(path):
    try:
        json.loads(open(path).read())
    except ValueError:
        raise SystemExit(4)
if payload.get("tool_name") == "Write":
    text = ti.get("content") or ""
else:
    text = open(path).read()
    for e in (ti.get("edits") or [ti]):
        old, new = e.get("old_string"), e.get("new_string")
        if old is None or new is None:
            continue
        if old and old not in text:
            raise SystemExit(1)
        if old and not e.get("replace_all") and text.count(old) > 1:
            raise SystemExit(3)
        text = text.replace(old, new, -1 if e.get("replace_all") else 1) if old else text + new
try:
    m = json.loads(text)
except ValueError:
    raise SystemExit(5)
keys = set()
for k in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
    v = m.get(k) if isinstance(m, dict) else None
    if isinstance(v, dict):
        keys.update(v)
print("\n".join(sorted(keys)))
' "$FILE_PATH" 2>/dev/null) || {
  RC=$?
  [ "$RC" != 3 ] || ambiguous
  [ "$RC" != 4 ] || unreadable_manifest "$FILE_PATH is not valid JSON as it stands, so an edit to it cannot be screened for a new dependency. Restore the last committed copy with a Bash command (git show HEAD:<repo-relative path> > $FILE_PATH), then redo the edit."
  [ "$RC" != 5 ] || unreadable_manifest "this edit would leave $FILE_PATH as invalid JSON, so it cannot be screened for a new dependency. Redo the edit so the result is valid JSON."
  PY_OK=0
}

if [ "$PY_OK" = 0 ]; then
  # The edit could not be applied to the file on disk (its old_string is gone,
  # or the result is not JSON), so fall back to line-shape matching rather than
  # letting an unreadable manifest change through.
  # Spec shapes: semver/ranges (incl. >= <=), dist-tags as a single word,
  # *, and workspace/file/npm/link/github/git/URL forms. "version" is the
  # only same-shaped top-level key -- excluded by name. A false block on a
  # metadata fragment is fail-closed and loud; rewriting the full file via
  # Write takes the structural path above.
  CANDIDATES=$(echo "$CONTENT" \
    | grep -oE '"[@a-zA-Z0-9][@a-zA-Z0-9._/-]*"[[:space:]]*:[[:space:]]*"(workspace:|file:|npm:|link:|github:|git\+|https?:|\*|(>=|<=|[~^><])?[0-9]|[A-Za-z][A-Za-z0-9._-]*")[^"]*"?' \
    | sed -E 's/^"([^"]+)".*/\1/' \
    | grep -vxE 'version')
fi

# A brand-new package.json is a new dependency surface in itself: every
# candidate counts as new.
if [ ! -f "$FILE_PATH" ]; then
  for NAME in $CANDIDATES; do
    case "$APPROVED" in *",$NAME,"*) continue ;; esac
    owner_approved "$NAME" && continue
    block "'$NAME' in NEW file $FILE_PATH"
  done
  exit 0
fi

# "Existing" means present in a DEPENDENCY MAP of the on-disk manifest --
# a whole-file grep counted a script or metadata key with the same name
# (e.g. "build") as an existing dependency.
for NAME in $CANDIDATES; do
  case "$APPROVED" in *",$NAME,"*) continue ;; esac
  if ! jq -e --arg n "$NAME" '
       ((.dependencies // {}) + (.devDependencies // {}) +
        (.optionalDependencies // {}) + (.peerDependencies // {})) | has($n)' \
       "$FILE_PATH" >/dev/null 2>&1; then
    block_manifest "$NAME"
  fi
done

exit 0
