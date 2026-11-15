#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook: block dangerous git operations
# Input: JSON on stdin with tool_input.command

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# A forced worktree remove is allowed for a worktree with no uncommitted change, untracked files included, wherever it
# is (guard audit item 7). The remove is judged on its own path and the worktree as it is now, so no ordering of
# earlier calls can grant it. Anything that cannot be read blocks. A scratch worktree strictly inside ${TMPDIR:-/tmp}/conveyor/
# (the stash-free throwaway the Builder workflow makes) may be force-removed even with changes; the path is
# resolved through symlinks first and matched on the directory boundary, so `..`, a symlink out and .../conveyor2 fail.
# `--ours`/`--theirs` of paths git lists as unmerged passes in the checkout and restore arms below.
gs_conflicted() { # <path>...: every path is unmerged (mid-merge or mid-rebase), where the command runs
  # GC = the call's -C dirs, entered in order as git does (CDPATH off: git never consults it); GUNSAFE =
  # --git-dir/--work-tree, which are not resolved here, so they refuse.
  local u p d
  [ $# -gt 0 ] && [ -z "${GUNSAFE-}" ] || return 1
  u=$(CDPATH=; for d in ${GC[@]+"${GC[@]}"}; do cd -- "$d" || exit 1; done
      git diff --name-only --diff-filter=U --relative 2>/dev/null) && [ -n "$u" ] || return 1
  for p in "$@"; do printf '%s\n' "$u" | grep -qxF -- "${p#./}" || return 1; done
}
gs_removable() { # <path>: a worktree with no change at all, wherever it is (guard audit item 7: only uncommitted work blocks)
  local p=$1 phys out
  [[ $p =~ ^/[A-Za-z0-9._@%+=,:/-]+$ ]] || return 1
  case "/$p/" in */../*) return 1 ;; esac
  # Judge the worktree the path really is: a symlink is followed, and its target is what the remove deletes.
  phys=$(cd -P "$p" 2>/dev/null && pwd -P) || return 1
  # An edit hidden by assume-unchanged (lowercase tag) or skip-worktree (S) never shows in status.
  out=$(git -C "$phys" ls-files -v 2>/dev/null) || return 1
  printf '%s\n' "$out" | grep -qE '^([a-z]|S) ' && return 1
  # The flags beat any config that narrows status (status.showUntrackedFiles, diff.ignoreSubmodules; pass 8).
  out=$(git -C "$phys" status --porcelain --untracked-files=all --ignore-submodules=none 2>/dev/null) && [ -z "$out" ]
}
gs_scratch() { # <path>: a directory strictly inside ${TMPDIR:-/tmp}/conveyor/, once symlinks are followed
  local p=$1 phys tmp
  [[ $p =~ ^/[A-Za-z0-9._@%+=,:/-]+$ ]] || return 1
  case "/$p/" in */../*) return 1 ;; esac
  phys=$(cd -P "$p" 2>/dev/null && pwd -P) || return 1
  # Only the temp folder itself is resolved (/private/tmp on macOS): a conveyor folder in it that is a symlink
  # elsewhere grants nothing.
  tmp=$(cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || return 1
  case "$phys" in "$tmp"/conveyor/?*) return 0 ;; esac
  return 1
}

# The strip below walks the command a character at a time (~1 s per 10 KB);
# a command naming no git call, or none of the screened subcommands, cannot
# match, so skip it. Quote and backslash characters are dropped first, so
# `pu''sh` cannot slip past. Every subcommand a check below reads is admitted
# here; one missing from this list is never screened at all.
P=${COMMAND//[\'\"\\]/}
case "$P" in *git*) ;; *) exit 0 ;; esac
case "$P" in *push*|*reset*|*checkout*|*switch*|*restore*|*clean*|*stash*|*branch*|*worktree*|*reflog*|*gc*) ;; *) exit 0 ;; esac

# Quoted text is not a command. A commit message or an echo that merely NAMES a
# dangerous operation must not trip the force/reset checks (a commit message
# mentioning one used to block). One pass over the whole command, heredoc
# bodies included: a per-line sed left a multi-line message whole.
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
# Without the helper CMD would be empty and every force push would pass.
type strip_quoted >/dev/null 2>&1 || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load .claude/hooks/lib/strip-quoted.sh, so it cannot screen this command. Restore it (git checkout .claude/hooks/lib/strip-quoted.sh) and retry." >&2; exit 2; }
# A QUOTED ARGUMENT IS STILL AN ARGUMENT. With every quoted span removed,
# `git -C /repo 'push' --force` became `git -C /repo  --force` and matched no
# check, and `git -C "/repo" clean -fdx` became `git -C clean -fdx`, so
# -C took `clean` as its value and the discard passed. ARGV keeps a quoted span
# as its word (strip-quoted.sh, the mark form): a plain token as written, quoted
# prose as one placeholder word. Every check below reads ARGV.
#
# CONTRACT for a quoted git word and for backticks. A seat belt against an
# honest mistake, not a wall; it fails closed.
# - A git word starts a git call wherever it stands, quoted or not: bash runs
#   `"git"` as git behind an assignment, `env`, `sudo -u git` or any other
#   wrapper, and no list of wrappers is kept here. So a git word that is data,
#   followed in the same simple command by words that spell a discard or a
#   force push (`grep -c "git" stash drop`), is refused too: reword it.
# - Backticks run inside double quotes and nest, and their quotes do not say
#   which text is data. A command holding a backtick is read with the quotes
#   of every string that holds one taken out. Left: quotes nested inside a
#   backtick are paired as they come, not as the shell pairs them, so quoted prose beside one that names a discard is refused too:
#   put the message in a file (`git commit -F`).
# - Not screened: `eval`, a command held in a variable, `bash -c '...'` text
#   and any other shell given a string.
# - A command holding a backtick is judged in THREE READINGS, by every check
#   below, and any one refuses. Closed: each substitution and each quoted
#   string is one opaque word, so a backtick that is an option's value
#   (`git -C "<backtick>pwd<backtick>" ...`) splits nothing. Opened: a quoted
#   string that holds a backtick loses its quotes and the backticks become
#   separators, so a discard run inside one is read. In both, a quoted string
#   that is one plain word keeps its text: it may be the executable or its
#   subcommand ("git" "reset"). A `$(...)` inside a quoted string is data in
#   both, so the reading every other command gets is judged as a third: it
#   follows `$(...)` into double quotes, nested too, and takes a backtick as a
#   plain character. Quotes nested inside a backtick are paired as they come,
#   not as the shell pairs them.
Q=$'\x01'
case "$COMMAND" in
  *'`'*) ARGV=$(printf '%s' "$COMMAND" | perl -0e '
    my $c = <STDIN>;
    for my $open (0, 1) {
      my $r = $c;
      $r =~ s{\\(.)|\x27([^\x27]*)\x27|"((?:\\.|[^"\\])*)"}{ defined $1 ? $1 : do { my $s = defined $2 ? $2 : $3; ($open && $s =~ /`/) || $s =~ m/^[\w.\/=+:,-]*\z/ ? $s : "QUOTED" } }gse;
      $r =~ s/`[^`]*`/BT/g unless $open;
      $r =~ tr/`/;/;
      $r =~ s/["\x27\\]//g;
      print "$r\n;\n";
    }') ;;
  *) ARGV="" ;;
esac
# The reader's own reading, of every command: with a backtick it is the third
# one, and the only one that follows a `$(...)` into a quoted string.
ARGV+=$(strip_quoted "$COMMAND" "$Q" | sed -E "s/${Q}([;&|()[:space:]]|\$)/QUOTED\1/g; s/${Q}//g")

# A git invocation ANYWHERE in the command, not only at position one. The old
# `^git ` prefix test meant `cd x && git push --force`, `FOO=1 git ...` and a
# `git` call after a `;` never reached a single check below -- the guard read
# the most common shapes of the thing it exists to stop as "not a git command".
if ! printf '%s' "$ARGV" | grep -qE '(^|[;&|(/]|[[:space:]])git[[:space:]]'; then
  exit 0
fi

# OPTIONS SIT BETWEEN THE VERB AND ITS SUBCOMMAND. Widening the gate above was
# not enough: each check still demanded `git` immediately followed by `push` or
# `reset`, so `git -C <path> push --force` and `git --no-pager push --force`
# reached the checks and matched nothing. `git -C <path>` is this repo's own
# standard idiom -- orchestration.md uses it throughout and main types it in
# every worktree command -- so that was a hole in the shape we actually use.
#
# One `-opt` with an optional non-option value, repeated. `git log --oneline`
# cannot be mistaken for one of these: `log` does not begin with `-`, so the
# group cannot consume it and the subcommand never matches.
GITOPTS='([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*'

# `--force-with-lease` is the SAFE form this hook's own message recommends, and
# the old `--force` substring matched it -- so the guard blocked the push it
# told the operator to use. Neutralised before the test (grep -E is POSIX ERE
# with no lookahead) so a bare `--force` and `-f` still block.
FORCE_CMD=$(printf '%s' "$ARGV" | sed -E 's/--force-with-lease(=[^[:space:]]*)?/--lease/g; s/--force-if-includes//g')

# Try line: the refused push as a lease push, built from the words typed. A plain word is the only kind
# rebuilt; delete, mirror and :ref forms have no allowed form, so they get none.
gs_plain() { case "$1" in *[\'\"\\\`\$\(\)\<\>\*\?\[\{]*) return 1 ;; esac; }
gs_push_try() { # <one push call>: prints the lease form; fails when nothing was forced or a word cannot be rebuilt
  local w x out="" f=0
  gs_plain "$1" || return 1
  set -f
  for w in $1; do
    case "$w" in
      --force-with-lease*|--force-if-includes) ;;
      --force) f=1; continue ;;
      --de*|--m*|:*) set +f; return 1 ;;
      --*) ;;
      -*d*) set +f; return 1 ;;
      -*f*) f=1; x=${w//f/}; [ "$x" = - ] && continue; w=$x ;;
      +?*) f=1; w=${w#+} ;;
    esac
    out+="$w "
    [ "$w" = push ] && out+="--force-with-lease "
  done
  set +f
  [ "$f" = 1 ] && printf '%s\n' "${out% }"
}
gs_force_try() { # the first push call in the command that gs_push_try can rebuild
  local c t
  while IFS= read -r c; do
    t=$(gs_push_try "$c") && { printf '%s\n' "$t"; return 0; }
  done < <(printf '%s\n' "$COMMAND" | grep -oE "git${GITOPTS}[[:space:]]+push[^;&|]*")
  return 1
}

# Block force push. The flag is looked for in the push's own words, which stop
# at a command separator: `git push origin HEAD && rg -f pats src/` is no force
# push.
if printf '%s' "$FORCE_CMD" | grep -qE "git${GITOPTS}[[:space:]]+push[[:space:]][^;&|]*--force|git${GITOPTS}[[:space:]]+push[[:space:]]([^;&|]*[[:space:]])?-f([[:space:];&|)]|\$)"; then
  echo "Blocked: force push is not allowed. Use --force-with-lease if absolutely necessary." >&2
  TRY=$(gs_force_try) && echo "Try: $TRY" >&2
  exit 2
fi

# The other force and delete forms: a short-flag cluster holding f or d
# (-fu, -uf, -d), a +refspec, an empty-source :ref refspec, --delete and
# --mirror. Push arguments stop at a command separator, so a later `echo +1`
# is not read as a refspec.
PUSH_ARGS="git${GITOPTS}[[:space:]]+push([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+"
if printf '%s' "$FORCE_CMD" | grep -qE "${PUSH_ARGS}(-[[:alnum:]]*[fd][[:alnum:]]*|[+:][^;&|[:space:]]+|--de(l(e(te?)?)?)?|--m(i(r(r(or?)?)?)?)?)([[:space:];&|)]|\$)"; then
  echo "Blocked: force push, remote branch deletion and --mirror are not allowed (-f in a flag cluster, a +refspec, a :ref refspec, --delete or -d). Use --force-with-lease if a rewrite is absolutely necessary." >&2
  TRY=$(gs_force_try) && echo "Try: $TRY" >&2
  exit 2
fi

# THE FAST LANE NEVER PUSHES (conveyor.sh lane fast create). Its own config refuses every push, but a command's own
# override (-c protocol.allow=..., GIT_CONFIG_*) outranks every config file, so git itself cannot refuse that push: this refuses every push that runs in the lane, whatever is set in front of it. The lane is
# a linked worktree with protocol.allow never in its own config, or on branch fast-lane. A push may run in the
# session's folder (the hook's cwd) or in any folder a cd, pushd or popd before it in the command names, then moved by
# each of its -C folders: a cd is never taken to replace the folder, since it can be skipped (`false && cd main`), run
# in a pipe or subshell, or fail. A push where any of those is the lane is refused: `cd "$LANE" && git push` from main
# pushed from the lane. A cd whose folder cannot be told (a variable, quoted text, `cd -`, a stack index, popd, a
# relative name that CDPATH may resolve, a folder that does not exist yet, or ~ once the command names HOME) refuses
# the push after it. A cd reaches both its logical folder (a later `cd ..` leaves by the symlink it came through) and
# its physical one (cd -P, set -P). A -C of ~ once the command names HOME is a folder that cannot be told, and so is a
# -C that is not a plain path (a variable), a quoted or backtick placeholder (QUOTED, BT) or a value stuck to its -C:
# it may name any repository's lane, not only one the hook knows, so the push after it is refused. A later absolute -C
# names its folder whatever came before it, so that folder alone is checked.
gs_lane() { # <folder>: it is in the fast lane
  local g
  g=$(git -C "$1" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null) || return 1
  [ "$(sed -n 1p <<<"$g")" != "$(sed -n 2p <<<"$g")" ] || return 1
  [ "$(git -C "$1" config --worktree --get protocol.allow 2>/dev/null)" = never ] || [ "$(git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null)" = fast-lane ]
}
gs_dir() { # <folder, or empty when unknown> <word>: the folder a -C word names from it; nothing when unknown
  [[ $2 =~ ^[A-Za-z0-9._@%+=,:/~-]+$ ]] || return 0
  case "$2" in
    /*) printf '%s' "$2" ;;
    '~') printf '%s' "$GS_HOME" ;;
    '~'/*) [ -n "$GS_HOME" ] && printf '%s' "$GS_HOME/${2#'~/'}" ;;
    '~'*) ;;
    *) [ -n "$1" ] && printf '%s' "$1/$2" ;;
  esac
  return 0
}
gs_norm() { # <absolute path>: it with . and .. taken by name, as a logical cd takes them
  local c p=() o=()
  IFS=/ read -ra p <<<"$1"
  for c in ${p[@]+"${p[@]}"}; do
    case "$c" in ''|.) ;; ..) [ ${#o[@]} -gt 0 ] && unset 'o[${#o[@]}-1]' ;; *) o+=("$c") ;; esac
  done
  [ ${#o[@]} -gt 0 ] && printf '/%s' "${o[@]}" || printf /
}
gs_cd() { # <word>: add to GS_DS the folders a cd to it reaches from each folder in GS_DS; "" when it cannot be told
  local d t=() x p
  case "$1" in
    /*|'~'|'~'/*|.|..|./*|../*) ;;
    *) GS_DS+=(""); return 0 ;; # a stack index, `-`, or a name CDPATH may resolve
  esac
  for d in "${GS_DS[@]}"; do
    case "$1" in /*|'~'*) ;; *) [ -n "$d" ] || { t+=(""); continue; } ;; esac
    x=$(gs_dir "$d" "$1")
    [ -n "$x" ] || { t+=(""); continue; }
    # A folder that does not exist now may by the time the cd runs (ln -s "$LANE" x && cd x).
    p=$(CDPATH='' cd -P -- "$x" 2>/dev/null && pwd -P) || { t+=(""); continue; }
    t+=("$p" "$(gs_norm "$x")")
  done
  for x in "${t[@]}"; do [[ " ${GS_DS[*]/#/|} " == *" |$x "* ]] || GS_DS+=("$x"); done
}
gs_seg() { # SEG = one simple command's words: a cd adds to GS_DS; a git push where any is the lane or unknown exits 2
  # A redirection's descriptor is a number or a {name} (bash's named descriptor: {fd}>/dev/null cd ...).
  local i=0 n=${#SEG[@]} CALL D how w a=() keep=0 F='([0-9]*|\{[A-Za-z_][A-Za-z0-9_]*\})'
  local R='^('$F'[<>]|'$'\x1f''>)' OP='^'$F'[<>'$'\x1f'']+$'
  while [ "$i" -lt "$n" ]; do # assignments, keywords and redirections before the command word
    w=${SEG[i]}
    if [[ $w =~ $R ]]; then [[ $w =~ $OP ]] && i=$((i + 1))
    # -.*: a wrapper's own options (command -p cd, time -p cd)
    elif ! [[ $w =~ ^([A-Za-z_][A-Za-z0-9_]*=.*|-.*|[{}!]|then|do|else|elif|if|while|until|time|builtin|command)$ ]]; then break; fi
    i=$((i + 1))
  done
  case "${SEG[i]-}" in
    cd|pushd|popd)
      how=${SEG[i]}
      for ((i = i + 1; i < n; i++)); do # its words, without redirections
        w=${SEG[i]}
        if [[ $w =~ $R ]]; then [[ $w =~ $OP ]] && i=$((i + 1)); else a+=("$w"); fi
      done
      i=0
      while [ "$i" -lt "${#a[@]}" ] && [[ ${a[i]} == -?* && ${a[i]} != -[0-9]* ]]; do
        [ "${a[i]}" = -- ] && { i=$((i + 1)); break; }
        [ "$how" != cd ] && [[ ${a[i]} == *n* ]] && keep=1 # pushd -n, popd -n: no cd
        i=$((i + 1))
      done
      [ "$keep" = 1 ] && return 0
      if [ "$how" = popd ]; then GS_DS+=("")
      elif [ "$i" -ge "${#a[@]}" ]; then if [ "$how" = cd ]; then gs_cd '~'; else GS_DS+=(""); fi
      else gs_cd "${a[i]}"; fi
      return 0 ;;
  esac
  while IFS= read -r CALL; do
    CALL=${CALL#[;\&|(/]} # the separator before git
    for D in "${GS_DS[@]}"; do
      set -f; set -- $CALL; set +f; shift # the git word itself
      while [ $# -gt 0 ] && [ "$1" != push ]; do
        if [ "$1" = -C ] && [ "${2-}" != QUOTED ] && [ "${2-}" != BT ] && [ -n "$(gs_dir "$D" "${2-}")" ]; then
          D=$(gs_dir "$D" "$2")
        elif [[ $1 == -C* ]]; then D="" # a -C that cannot be followed: a variable, quoted text, a backtick, ~ or a stuck value
        fi
        # An option's value is never the subcommand: `git -C push -C "$LANE" push` pushes from the lane.
        case "$1" in -C|-c|--namespace|--config-env|--git-dir|--work-tree) shift ;; esac
        shift
      done
      if [ -z "$D" ]; then
        echo "Blocked: this push may run in a folder the hook cannot tell (a -C or cd to a variable, quoted text, a backtick, a relative name, a folder that does not exist yet, ~ when the command names HOME, cd -, a pushd stack index or a popd), so it may be the fast lane of any repository, which never pushes. Name the folder as a plain path: git -C /path/to/checkout push ..." >&2
        exit 2
      fi
      gs_lane "$D" || continue
      echo "Blocked: the fast lane ($D) never pushes, whatever a command sets for it; a push after a cd into it is refused even when that cd may not run. Land its change with conveyor.sh lane fast land; main's checkout pushes (git -C /path/to/main push ...)." >&2
      exit 2
    done
  done < <(printf '%s\n' "${SEG[*]-}" | grep -oE "(^|[;&|(/]|[[:space:]])git${GITOPTS}[[:space:]]+push([[:space:]]|\$)")
  return 0
}
GS_CWD=$(jq -r '.cwd // empty | strings' <<<"$INPUT" 2>/dev/null); GS_CWD=${GS_CWD:-$PWD}
GS_DS=("$GS_CWD"); SEG=()
# ~ and a bare cd go to HOME, unless the command may set it first (HOME=x; cd ~): then they cannot be told.
GS_HOME=$HOME; [[ $COMMAND =~ (^|[^A-Za-z0-9_])HOME([^A-Za-z0-9_]|$) ]] && GS_HOME=""
set -f
GS_NFD='^\{[A-Za-z_][A-Za-z0-9_]*\}[<>'$'\x1f'']' # a named descriptor's redirection ({fd}>x)
# The & of a redirection (>&2, &>file) and the | of >| are not separators: \x1f stands in for them.
for W in $(printf '%s\n' "$ARGV" | tr '\n' ';' | sed -E 's/([<>])&/\1'$'\x1f''/g; s/&>/'$'\x1f''>/g; s/>\|/>/g; s/([;&|()])/ \1 /g'); do
  case "$W" in
    ';'|'&'|'|'|'('|')') gs_seg; SEG=() ;;
    # A redirection written onto a word (cd>/dev/null, push>x) is its own word; an all-digit or {name} start is its fd.
    *) if ! [[ $W =~ $GS_NFD ]] &&
         [[ $W =~ ^([^<>$'\x1f']*[^0-9<>$'\x1f'][^<>$'\x1f']*)([<>$'\x1f'].*)$ ]]; then
         SEG+=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
       else SEG+=("$W"); fi ;;
  esac
done
set +f
gs_seg

# The ways to discard work: each throws away uncommitted edits,
# untracked files, a stash, an unmerged branch or the reflog that would recover
# them, exactly as reset --hard does. Every git call is read on its OWN words,
# which stop at a command separator, so a later `echo -- .` is not a checkout
# argument. Each family is narrowed to its discarding form, because its
# neighbour is ordinary work: a branch checkout, an index-only restore, a clean
# dry run, a merged-branch delete. The hook sees only the submitted command,
# so a script that runs one of these inside itself is not read here.
# CEILING: a path checkout written as ONE word without `--` (`git checkout
# file`) reads as a branch checkout and passes; nothing in the words tells the
# two apart. A commit plus a path is told apart: see the checkout rule.
case "$P" in *reset*|*checkout*|*switch*|*restore*|*clean*|*stash*|*branch*|*worktree*|*reflog*|*gc*) ;; *) exit 0 ;; esac
# The subcommand is matched as a whole word, so `git restore-mtime` is not a restore.
DISCARD="(^|[;&|(/]|[[:space:]])git${GITOPTS}[[:space:]]+(reset|checkout|switch|restore|clean|stash|branch|worktree|reflog|gc)[^;&|()[:space:]]*([[:space:]]+[^;&|()[:space:]]+)*"
arg_is() { # <ERE>: one of the call's arguments is exactly this
  local A
  for A in "${ARGS[@]}"; do [[ $A =~ ^($1)$ ]] && return 0; done
  return 1
}
# git takes any unambiguous start of a long option (`--har`, `--forc`), so a
# long option is matched by its start. A start git itself would call
# ambiguous is refused here too, which costs nothing: git refuses it as well.
opt_is() { # <--long-option>...: an argument is one of these, or the start of one
  local A O
  for A in "${ARGS[@]}"; do
    A=${A%%=*}
    [[ $A == --?* ]] || continue
    for O in "$@"; do [[ $O == "$A"* ]] && return 0; done
  done
  return 1
}
while IFS= read -r CALL; do
  set -f; set -- $CALL; set +f
  shift # the git word itself
  # GITOPTS guesses which option takes a value; git's own list decides which
  # word is the subcommand, so `git --no-pager log -- stash` stays a log.
  GC=(); GUNSAFE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) GC+=("${2-}"); shift; [ $# -gt 0 ] && shift ;;
      --git-dir|--work-tree) GUNSAFE=1; shift; [ $# -gt 0 ] && shift ;;
      --git-dir=*|--work-tree=*) GUNSAFE=1; shift ;;
      -c|--namespace|--config-env) shift; [ $# -gt 0 ] && shift ;;
      --) break ;; # git has no bare `--` option: `git grep git -- restore` names a file
      -*) shift ;;
      *) break ;;
    esac
  done
  SUB=${1-}; [ $# -gt 0 ] && shift
  # Everything after `--` is a path, never an option: a file named -n is not a
  # dry run. ARGS = the words before it, PATHS = 1 when it is there.
  ARGS=(); PATHS=0; WHY=""; PATHW=()
  for A in "$@"; do
    if [ "$PATHS" = 1 ]; then PATHW+=("$A"); continue; fi
    [ "$A" = -- ] && { PATHS=1; continue; }; ARGS+=("$A")
  done
  case "$SUB" in
    reset)
      # --hard wherever it sits: `git reset HEAD --hard`, `git reset -q --hard`.
      opt_is --hard && WHY="git reset --hard is dangerous. Use git revert for safe rollbacks." ;;
    switch)
      { opt_is --force --discard-changes || arg_is '-[a-zA-Z]*f[a-zA-Z]*'; } \
        && WHY="git switch --force (-f, --discard-changes) throws away uncommitted edits. Commit them or copy them aside first; a plain switch is not affected." ;;
    checkout)
      { opt_is --force || arg_is '-[a-zA-Z]*f[a-zA-Z]*'; } \
        && WHY="git checkout --force (-f) throws away uncommitted edits. Commit them or copy them aside first; a plain branch checkout is not affected."
      if [ -n "$WHY" ]; then
        echo "Blocked: $WHY" >&2
        # The same checkout without the force flag, when the call is a plain `git checkout` of plain words.
        if [[ $CALL =~ git[[:space:]]+checkout([[:space:]]|$) ]] && gs_plain "$*"; then
          TRY=""; for A in "$@"; do
            case "$A" in
              --f*) [[ --force == "$A"* ]] && continue ;;
              --*) ;;
              -*f*) A=${A//f/}; [ "$A" = - ] && continue ;;
            esac
            TRY+=" $A"
          done
          echo "Try: git checkout$TRY" >&2
        fi
        exit 2
      fi
      # Two positional words are a commit and a path: a branch checkout
      # takes one, unless it makes the branch from a start point. A redirection
      # and its target are not arguments.
      N=0; SKIP=0
      for A in "${ARGS[@]}"; do
        [ "$SKIP" = 0 ] || { SKIP=0; continue; }
        case "$A" in *[\<\>]) SKIP=1 ;; *[\<\>]*|-*) ;; *) N=$((N+1)) ;; esac
      done
      { [ "$PATHS" = 1 ] || arg_is '\./?' || { [ "$N" -ge 2 ] && ! arg_is '-[a-zA-Z]*[bB][a-zA-Z]*|--orphan'; }; } \
        && WHY="git checkout of paths (\`--\`, \`.\` or a commit plus a path) overwrites uncommitted edits. Commit them or copy them aside first; switching branches is not affected."
      [ -n "$WHY" ] && opt_is --ours --theirs && gs_conflicted "${PATHW[@]}" && WHY="" ;;
    restore)
      { arg_is '--staged|-[a-zA-Z]*S[a-zA-Z]*' && ! opt_is --worktree && ! arg_is '-[a-zA-Z]*W[a-zA-Z]*'; } \
        || WHY="git restore of the working tree overwrites uncommitted edits. Only the index-only \`git restore --staged\` passes."
      # Without `--` the paths are the plain words; an option's value among them is no unmerged path, so it blocks.
      [ "$PATHS" = 1 ] || { PATHW=(); for A in "${ARGS[@]}"; do [[ $A == -* ]] || PATHW+=("$A"); done; }
      [ -n "$WHY" ] && opt_is --ours --theirs && gs_conflicted "${PATHW[@]}" && WHY="" ;;
    clean)
      { opt_is --force || arg_is '-[a-zA-Z]*f[a-zA-Z]*'; } && ! arg_is '--dry-run|-[a-zA-Z]*n[a-zA-Z]*' \
        && WHY="git clean -f deletes untracked files (briefs, scratch, handoff files). Preview with \`git clean -n\` and remove what you mean to by name." ;;
    stash)
      case "${ARGS[0]-}" in drop|clear) WHY="git stash ${ARGS[0]} destroys stashed work. Apply it or leave it." ;; esac ;;
    branch)
      { arg_is '-[a-zA-Z]*D[a-zA-Z]*' || { { opt_is --delete || arg_is '-[a-zA-Z]*d[a-zA-Z]*'; } && { opt_is --force || arg_is '-[a-zA-Z]*f[a-zA-Z]*'; }; }; } \
        && WHY="git branch -D deletes a branch whatever it still holds. Use \`git branch -d\`, which refuses an unmerged branch." ;;
    worktree)
      # The path is the first word that is not an option or a redirection.
      if [ "${ARGS[0]-}" = remove ] && { opt_is --force || arg_is '-f+'; }; then
        GS_WORDS=()
        for A in "${ARGS[@]:1}"; do case "$A" in -*|*[\<\>]*) ;; *) GS_WORDS+=("$A") ;; esac; done
        GS_P=${GS_WORDS[0]-}; GS_P=${GS_P%/}
        { [ "${#GS_WORDS[@]}" = 1 ] && { gs_scratch "$GS_P" || gs_removable "$GS_P"; }; } \
          || WHY="git worktree remove --force deletes a worktree with its uncommitted changes. Remove it without --force; a forced remove passes only for a worktree with no change, untracked files included, or one strictly inside ${TMPDIR:-/tmp}/conveyor/."
      fi ;;
    reflog)
      [ "${ARGS[0]-}" = expire ] && WHY="git reflog expire drops the entries that recover lost commits." ;;
    gc)
      arg_is '--p(r(u(ne?)?)?)?=now' && WHY="git gc --prune=now deletes unreachable objects at once, the ones the reflog could still recover. Plain \`git gc\` keeps the grace period." ;;
  esac
  [ -n "$WHY" ] || continue
  echo "Blocked: $WHY" >&2
  [ "$SUB" != gc ] || echo "Try: git gc" >&2
  exit 2
done < <(printf '%s\n' "$ARGV" | grep -oE "$DISCARD")

exit 0
