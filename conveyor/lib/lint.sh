#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The lint check (docs/configuration.md, Lint): the pack's lint.commands, each run on the files of a change it reads,
# and its result. Sourced, never run: by commands/lint.sh (conveyor.sh lint), commands/size.sh (lintsizelist),
# commands/doctor.sh (lintdoctor), commands/setup.sh (lintprobe), commands/retry.sh (lintrule) and lib/card.sh (the review and landing gates,
# lintgate; lintwait, the gate for a waiting card, is called by settle() in lib/claim.sh, in a card's shell, and
# lintbatch and lintleave, the gate for a batch, by batch() and rebatch()). It uses packget (lib/prompts.sh) and the
# test slots (lib/slots.sh), sourced before it; lintratchet also uses depdirs (lib/push.sh) and CARDS (lib/paths.sh); lintgate
# the card's steps (block, session, checked, record, giveway, cardpatch), which a card's shell has.
#
# The pack is main's ($PACK); the scripts and configs a command loads are the worktree's, as it runs at the worktree's
# top; a command whose trigger main added after the tree's commit, and the tree lacks, is skipped (lintlate). A tree
# is the worktree as `git add -A` would stage it, read through a copy of its index (lintindex), so the worktree's own
# index is never changed. A command's scope (lintscope) is found by git from its pathspecs: `files`
# (the sources it reads) and `triggers` (the scripts, configs and lock files that change its result). A command with
# `{files}` in `run` gets the changed files that `files` matches, never a deleted one (a renamed file under its new
# path); every match in the tree's index copy (an untracked file too) when one of its triggers changed or the pack's
# `lint` field did. A command without `{files}` is run as it is, when a changed file (a deleted one too) matches `files`
# or `triggers`, or the field changed, and a file of the index copy matches `files`. A command run on a tree is given
# that tree's index copy in GIT_INDEX_FILE, so a command that lists the project with `git ls-files` sees a file that is
# not tracked yet too; lintdoctor gives it the main checkout's own index, where `git ls-files` lists tracked files only.
#
# A run (lintcall) holds one test slot, as a test run does, with `bash -o pipefail -c` and a limit of LINT_LIMIT
# seconds. A finding line is `<path>:<line>[:<column>]: <text>`, <path> a file of the tree from its top: the start of
# each line is matched against the tree's paths (lintfindings), so a path with spaces or colons is read whole. The
# result (lintresult): pass (exit 0, no finding line), findings (exit 1, a finding line or more), skipped (exit 127
# with the first line `lint: missing <tool>`), or an execution error: any other end, the time limit too.
# An entry with `size` in place of `run` is the engine's own file-length check (lintsize), run with no slot.
LINT_LIMIT=300
# The jq name of a lint command in its result and the engine's lines: its run, or for a size entry (lintsize) its limit.
LINTRUN='(.run // "size, limit \(.size.file) lines")'

# A copy of <worktree>'s index in <index file>, with the worktree added as `git add -A` would add it.
lintindex() { # <worktree> <index file>
  cp -p "$(git -C "$1" rev-parse --path-format=absolute --git-path index)" "$2" 2>/dev/null || rm -f "$2"
  GIT_INDEX_FILE=$2 git -C "$1" add -A 2>/dev/null
}

# True when the pack's `lint` field in <index>'s tree differs from <base>'s (a pack in neither is no change).
lintfield() { # <worktree> <index> <base>
  local a b
  a=$(git -C "$1" show "$3:.conveyor/project.json" 2>/dev/null | jq -c '.lint' 2>/dev/null) || a=bad
  b=$(GIT_INDEX_FILE=$2 git -C "$1" show ":.conveyor/project.json" 2>/dev/null | jq -c '.lint' 2>/dev/null) || b=bad
  [ "${a:-null}" != "${b:-null}" ]
}

# The scope of one command: LINT_GO is 1 when it runs, LINT_F the files it is given (none for a command without
# {files}), LINT_TRIG 1 when the change changed one of its triggers. <full> is 1 when the pack's lint field changed.
# A size entry is scoped as a command with {files} is, and its exempt file is always one of its triggers.
# Fails when git cannot list the files.
lintscope() { # <worktree> <index> <base> <command json> <full> <scratch file>
  local -a fs tr
  local full=$5
  LINT_F=() LINT_GO='' LINT_TRIG=''
  mapfile -d '' -t fs < <(jq -j '.files[] + "\u0000"' <<<"$4")
  mapfile -d '' -t tr < <(jq -j '((.triggers // []) + [.size.exempt // empty | ":(literal)" + .])[] + "\u0000"' <<<"$4")
  [ ${#fs[@]} != 0 ] || return 0
  if [ ${#tr[@]} != 0 ]; then
    GIT_INDEX_FILE=$2 git -C "$1" diff --cached --no-renames -z --name-only "$3" -- "${tr[@]}" > "$6" || return 1
    [ ! -s "$6" ] || { full=1; LINT_TRIG=1; }
  fi
  if [[ $(jq -r 'if .size then "{files}" else .run end' <<<"$4") != *'{files}'* ]]; then
    if [ -z "$full" ]; then
      GIT_INDEX_FILE=$2 git -C "$1" diff --cached --no-renames -z --name-only "$3" -- "${fs[@]}" > "$6" || return 1
      [ ! -s "$6" ] || full=1
    fi
    [ -n "$full" ] || return 0
    # It reads the whole project: with no file of the index copy that `files` matches, it has nothing to read.
    GIT_INDEX_FILE=$2 git -C "$1" ls-files -z -- "${fs[@]}" > "$6" || return 1
    [ ! -s "$6" ] || LINT_GO=1; return 0
  fi
  if [ -n "$full" ]; then GIT_INDEX_FILE=$2 git -C "$1" ls-files -z -- "${fs[@]}" > "$6" || return 1
  else GIT_INDEX_FILE=$2 git -C "$1" diff --cached --no-renames -z --name-only --diff-filter=d "$3" -- "${fs[@]}" > "$6" || return 1; fi
  mapfile -d '' -t LINT_F < "$6"
  [ ${#LINT_F[@]} = 0 ] || LINT_GO=1
}

# LINT_LATE: the first file a trigger of <command json> matches that main (the pack's defaultBranch) added after
# <base> and <index>'s tree lacks; empty when there is none. Such a tree was made before main added the command's
# script or config, so the command cannot run on it: it runs on the change on main as it is now (the landing gate,
# after settle() fitted the card there). Fails when the pack or the files cannot be read.
lintlate() { # <worktree> <index> <base> <command json> <scratch file>
  local f
  local -a tr
  LINT_LATE=''
  mapfile -d '' -t tr < <(jq -j '(.triggers // [])[] + "\u0000"' <<<"$4")
  [ ${#tr[@]} != 0 ] || return 0
  # The pack's defaultBranch, as names() reads it into BRANCH: `conveyor.sh lint` runs no names().
  packget defaultBranch f && git -C "$1" diff --no-renames -z --name-only --diff-filter=A "$3" "refs/heads/$f" -- "${tr[@]}" > "$5" || return 1
  while IFS= read -r -d '' f; do
    [ -n "$(GIT_INDEX_FILE=$2 git -C "$1" ls-files -- ":(literal)$f")" ] || { LINT_LATE=$f; return 0; }
  done < "$5"
}

# Runs <run> at <worktree>'s top, {files} in it replaced by the files, each quoted for the shell (as test.list's
# placeholder is), on a test slot, its stdout and stderr in <output file>. Its exit is returned; LINT_OVER is 1 when
# it ran over LINT_LIMIT, LINT_SEC the seconds it ran. <index> (empty for the worktree's own) is the GIT_INDEX_FILE the command is given.
lintcall() { # <worktree> <index> <run> <output file> [<file>...]
  local wt=$1 ix=$2 c=$3 o=$4 q='' at rc
  shift 4; LINT_OVER='' LINT_SEC=0
  [ $# = 0 ] || { printf -v q '%q ' "$@"; q=${q% }; }
  c=${c//\{files\}/"$q"}
  # No slot pool: the command did not start, an execution error (exit 126) whose first line is the engine's why.
  slot_pool > "$o" 2>&1 || { q=$(grep -m 1 '^conveyor: ' "$o"); echo "${q:-conveyor: no test slot could be taken}" > "$o"; return 126; }
  [ -n "$SLOT_HOME" ] || until slot_try || slot_wait; do :; done
  at=$SECONDS
  ( [ -n "$SLOT_HOME" ] || slot_mine || exit 1
    cd "$wt" && { [ -z "$ix" ] || export GIT_INDEX_FILE=$ix; } && exec timeout --kill-after=10 "$LINT_LIMIT" bash -o pipefail -c "$c" ) < /dev/null > "$o" 2>&1 8>&-; rc=$?
  [ -n "$SLOT_HOME" ] || slot_free
  LINT_SEC=$((SECONDS - at))
  [ $((SECONDS - at)) -lt "$LINT_LIMIT" ] || { [ $rc != 124 ] && [ $rc != 137 ]; } || LINT_OVER=1
  return $rc
}

# The finding lines of <output file>, one JSON object a line: {file, line, column, text, code}, the code being the
# first word of the text. <paths file> holds the tree's paths, NUL-separated: a line is a finding when it starts with
# one of them, then `:<line>[:<column>]: `. Of two paths that fit, the shorter is the line's.
lintfindings() { # <output file> <paths file>
  jq -cn --rawfile o "$1" --rawfile p "$2" '
    (reduce ($p | split("\u0000")[] | select(. != "")) as $x ({}; .[$x] = true)) as $set
    | $o | split("\n")[] | rtrimstr("\r") | split(":") as $s
    | first(range(1; $s | length) as $k | ($s[:$k] | join(":")) as $f | select($set[$f])
      | $s[$k:] | join(":") | capture("^(?<l>[0-9]+)(:(?<c>[0-9]+))?: (?<t>.*)$")
      | {file: $f, line: (.l | tonumber), column: (.c | if . then tonumber else null end), text: .t, code: (.t | split(" ")[0])})'
}

# The result of one run: `pass`, `findings`, `skipped<TAB><tool>` or `error<TAB><why>`.
lintresult() { # <exit> <output file> <finding lines> <over the limit: 1 or empty>
  local l=''
  IFS= read -r l < "$2" || :
  l=${l%$'\r'}
  if [ -n "$4" ]; then printf 'error\tit ran over its time limit of %s seconds\n' "$LINT_LIMIT"
  elif [ "$1" = 127 ] && [[ $l =~ ^lint:\ missing\ (.+)$ ]]; then printf 'skipped\t%s\n' "${BASH_REMATCH[1]}"
  elif [ "$1" = 0 ] && [ "$3" = 0 ]; then echo pass
  elif [ "$1" = 1 ] && [ "$3" != 0 ]; then echo findings
  elif [ "$1" = 0 ]; then printf 'error\tit exited 0 and printed %s finding line(s)\n' "$3"
  elif [ "$1" = 1 ]; then printf 'error\tit exited 1 and printed no finding line%s\n' "${l:+: $l}"
  elif [ "$1" = 127 ]; then printf 'error\tit exited 127 with no `lint: missing <tool>` first line%s\n' "${l:+: $l}"
  else printf 'error\tit exited %s%s\n' "$1" "${l:+: $l}"; fi
}

# A size entry's run, in the engine with no slot, giving what a lint command gives: each of <file>... (paths from
# <worktree>'s top) that has more lines than <limit> and is not a line of the <exempt file> in <worktree>'s index
# (GIT_INDEX_FILE when it is set: the gate gives the tree's) is the finding line
# `<path>:<limit + 1>: size <n> lines, limit <limit>`, and the exit is 1; else 0. A line exempts the file whose path
# is the whole line, so a function's line (path, a tab, its name) exempts no file; an exempt file the index lacks (an
# ignored one too) or holds as a link (its blob is the target's name) exempts nothing. A link or a submodule is not
# counted, nor a file under a folder that is a link (a tracked folder made a link, to a place outside the worktree
# too). A last line with no newline is a line. When a file cannot be read, the exit is 2 after awk's why.
lintsize() { # <worktree> <limit> <exempt file> <file>...
  local w=$1 lim=$2 ex=$3 f d n out i=0 rc=0
  local -a fs=() ns
  local -A skip=()
  shift 3
  n=''; [ -z "$ex" ] || n=$(git -C "$w" ls-files -s -- ":(literal)$ex" 2>/dev/null) || n=''
  if [[ $n == '100644 '* || $n == '100755 '* ]]; then
    while IFS= read -r n || [ -n "$n" ]; do n=${n%$'\r'}; [ -z "$n" ] || skip[$n]=1; done < <(git -C "$w" cat-file blob ":$ex" 2>/dev/null)
  fi
  for f; do
    [ -f "$w/$f" ] && [ ! -L "$w/$f" ] && [ -z "${skip[$f]:-}" ] || continue
    d=$f; while [[ $d == */* ]]; do d=${d%/*}; [ ! -L "$w/$d" ] || continue 2; done
    fs+=("$f")
  done
  [ ${#fs[@]} != 0 ] || return 0
  # One awk for all the files, a count a line in their order (0 for an empty file, which has no first line); each
  # path after ./, so that awk reads no `name=value` path as a variable.
  out=$(cd "$w" && printf './%s\0' "${fs[@]}" | xargs -0 awk 'FNR == 1 { if (seen) print n; seen = 1; while (++i < ARGC && ARGV[i] != FILENAME) print 0 }
    { n = FNR } END { if (seen) print n; while (++i < ARGC) print 0 }') || return 2
  mapfile -t ns <<<"$out"
  for f in "${fs[@]}"; do
    n=${ns[i]:-}; i=$((i + 1))
    [[ $n =~ ^[0-9]+$ ]] || { echo "lint: the lines of $f could not be counted"; return 2; }
    [ "$n" -le "$lim" ] || { echo "$f:$((lim + 1)): size $n lines, limit $lim"; rc=1; }
  done
  return $rc
}

# `conveyor.sh size --list`: the paths, from <worktree>'s top, one a line, sorted, of the files that the pack's size
# entries match in <worktree>'s tree (a tracked file, or one not tracked and not ignored, as `git add -A` would stage
# it) and that have more lines than their entry's limit. The exempt file is not read: the list is what it names. Fails,
# saying why, when the pack or the tree cannot be read or a file cannot be counted.
lintsizelist() { # <worktree>
  local l c sz rc out t
  local -a fs one
  packget lint l || { echo "conveyor size: the pack's lint field could not be read" >&2; return 1; }
  t=$(mktemp -d) || return 1
  : > "$t/list"
  while IFS= read -r c; do
    sz=$(jq -r '.size.file | floor' <<<"$c")
    mapfile -d '' -t fs < <(jq -j '.files[] + "\u0000"' <<<"$c")
    git -C "$1" ls-files -z --cached --others --exclude-standard -- "${fs[@]}" > "$t/m" \
      || { rm -rf "$t"; echo "conveyor size: the files of $1 could not be listed" >&2; return 1; }
    mapfile -d '' -t one < "$t/m"
    [ ${#one[@]} != 0 ] || continue
    # No exempt file (an empty name is no file), so every file over the limit is a finding line `<path>:<line>: ...`.
    rc=0; out=$(lintsize "$1" "$sz" '' "${one[@]}" 2>&1) || rc=$?
    [ "$rc" -le 1 ] || { rm -rf "$t"; echo "conveyor size: ${out:-the lines could not be counted}" >&2; return 1; }
    [ -z "$out" ] || sed 's/:[0-9]*: size [0-9]* lines, limit [0-9]*$//' <<<"$out" >> "$t/list"
  done < <(jq -c '.commands // [] | .[] | select(.size)' <<<"${l:-null}")
  # The list's write fails the command (a full disk, a closed output): its status is sort's.
  LC_ALL=C sort -u "$t/list"; rc=$?; rm -rf "$t"; return $rc
}

# The pack's lint commands run on <worktree>'s tree, the change being from <base> (a commit) to that tree: one JSON
# line a command, in the pack's order: {n, run, ratchet, complexity, result, why, files, findings, sec, triggered}.
# result is pass, findings, skipped (why: the tool, or not called: a trigger file the tree lacks, lintlate), error
# (why: what went wrong) or `no files` (its scope is empty: not called); files is the count it was given (null for a
# command without {files}); findings its finding lines (lintfindings); sec the seconds it ran; triggered whether the
# change changed one of its triggers. A size entry
# (lintsize) is a command whose run is LINTRUN's name for it, with ratchet false (every finding is the change's, so
# there is no base run), and triggered false (no tool runs as installed).
# Nothing when the pack has no lint field. Fails, saying why, when the pack or the tree cannot be read.
lintcheck() { # <worktree> <base>
  local l t full='' c n=0 rc r why run f sz at
  packget lint l || { echo "conveyor lint: the pack's lint field could not be read" >&2; return 1; }
  [ -n "$l" ] || return 0
  t=$(mktemp -d) || return 1
  lintindex "$1" "$t/index" && GIT_INDEX_FILE=$t/index git -C "$1" ls-files -z > "$t/paths" \
    || { rm -rf "$t"; echo "conveyor lint: the tree of $1 could not be read" >&2; return 1; }
  ! lintfield "$1" "$t/index" "$2" || full=1
  while IFS= read -r c; do
    n=$((n + 1))
    LINT_LATE=''
    { lintscope "$1" "$t/index" "$2" "$c" "$full" "$t/scope" && { [ -z "$LINT_GO" ] || lintlate "$1" "$t/index" "$2" "$c" "$t/scope"; }; } \
      || { rm -rf "$t"; echo "conveyor lint: the files of lint command $n could not be listed" >&2; return 1; }
    if [ -z "$LINT_GO" ] || [ -n "$LINT_LATE" ]; then
      jq -c --argjson n $n --argjson g "$([ -n "$LINT_TRIG" ] && echo true || echo false)" --arg late "$LINT_LATE" '{n: $n, run: '"$LINTRUN"', ratchet: (.ratchet != false and .size == null),
        complexity: (.complexity // []), result: (if $late == "" then "no files" else "skipped" end),
        why: (if $late == "" then null else "\($late), which main added after the commit of this tree: it runs on the change on main as it is now" end),
        files: 0, findings: [], sec: 0, triggered: ($g and .size == null)}' <<<"$c" \
        || { rm -rf "$t"; echo "conveyor lint: the result of lint command $n could not be written" >&2; return 1; }
      continue
    fi
    run=$(jq -r .run <<<"$c"); sz=$(jq -r '.size // empty | "\(.file | floor)\t\(.exempt)"' <<<"$c"); f=null
    if [ -n "$sz" ]; then
      f=${#LINT_F[@]}; at=$SECONDS; LINT_OVER=''; rc=0
      GIT_INDEX_FILE=$t/index lintsize "$1" "${sz%%$'\t'*}" "${sz#*$'\t'}" "${LINT_F[@]}" > "$t/out" 2>&1 || rc=$?; LINT_SEC=$((SECONDS - at))
    else
      [[ $run != *'{files}'* ]] || f=${#LINT_F[@]}
      rc=0; lintcall "$1" "$t/index" "$run" "$t/out" "${LINT_F[@]}" || rc=$?
    fi
    lintfindings "$t/out" "$t/paths" > "$t/found" || : > "$t/found"
    IFS=$'\t' read -r r why < <(lintresult "$rc" "$t/out" "$(wc -l < "$t/found" | tr -d ' ')" "$LINT_OVER")
    jq -c --argjson n $n --arg r "$r" --arg w "$why" --argjson f "$f" --argjson s "$LINT_SEC" --argjson g "$([ -n "$LINT_TRIG" ] && echo true || echo false)" \
      --slurpfile fd "$t/found" '{n: $n, run: '"$LINTRUN"', ratchet: (.ratchet != false and .size == null), complexity: (.complexity // []), result: $r,
        why: (if $w == "" then null else $w end), files: $f, findings: $fd, sec: $s, triggered: ($g and .size == null)}' <<<"$c" \
      || { rm -rf "$t"; echo "conveyor lint: the result of lint command $n could not be written" >&2; return 1; }
  done < <(jq -c '.commands // [] | .[]' <<<"$l")
  rm -rf "$t"
}

# The lines of <path> that the change from <base> to <index>'s tree added or changed: `all` (a file <base> lacks),
# or `<base start> <base count> <start> <count>` a hunk, from `git diff -U0` (a count of 0: the hunk adds or deletes
# lines after that start); nothing for an unchanged file. <old path> is the base's path of a renamed file, so its
# lines are diffed against the old file's.
linthunks() { # <worktree> <index> <base> <path> [<old path>]
  local h
  if [ -z "${5:-}" ] && ! git -C "$1" cat-file -e "$3:$4" 2>/dev/null; then echo all; return 0; fi
  h=$(GIT_INDEX_FILE=$2 git -C "$1" diff --cached -U0 -M --no-color "$3" -- "${5:-$4}" "$4") || return 1
  sed -nE 's/^@@ -([0-9]+)(,([0-9]+))? \+([0-9]+)(,([0-9]+))? @@.*/\1,\3,\4,\6/p' <<<"$h" \
    | awk -F, '{ print $1, ($2 == "" ? 1 : $2), $3, ($4 == "" ? 1 : $4) }'
}

# The changed lines of each file that a finding of <lintcheck output> names and the change from <base> to <index>'s
# tree changed, as one JSON object: {<path>: {base: <its path in base, null for a file base lacks>, hunks: "all" |
# [[<base start>, <base count>, <start>, <count>]...]}} (linthunks); a renamed file's base path is its old one. A
# file the change did not touch is not in it.
linthunkmap() { # <worktree> <index> <base> <lintcheck output> <scratch file>
  local f h s
  local -a st
  local -A old=() changed=()
  GIT_INDEX_FILE=$2 git -C "$1" diff --cached -z --name-status -M "$3" > "$5" || return 1
  # name-status -z: <status> <path>, or <status> <old path> <new path> for a rename.
  mapfile -d '' -t st < "$5"
  for ((s = 0; s < ${#st[@]}; s++)); do
    case ${st[s]} in R*) old[${st[s + 2]}]=${st[s + 1]}; changed[${st[s + 2]}]=1; s=$((s + 2)) ;; D) s=$((s + 1)) ;; *) changed[${st[s + 1]}]=1; s=$((s + 1)) ;; esac
  done
  : > "$5"
  while IFS= read -r -d '' f; do
    [ -n "${changed[$f]:-}" ] || continue
    h=$(linthunks "$1" "$2" "$3" "$f" "${old[$f]:-}") || return 1
    jq -cn --arg f "$f" --arg b "${old[$f]:-$f}" --arg h "$h" '{($f): (if $h == "all" then {base: null, hunks: "all"}
      else {base: $b, hunks: [$h | split("\n")[] | select(. != "") | split(" ") | map(tonumber)]} end)}' >> "$5" || return 1
  done < <(jq -j '.findings[].file + "\u0000"' <<<"$4" | sort -zu)
  jq -cs 'add // {}' "$5"
}

# The base worktree of a card's lint run, at <base>, made anew at <base worktree> ($CARDS/mainrun/<card>.lint): a link
# to each dependency folder <worktree> has (a link from main, linkFromMain, or a folder its worktree.setup filled:
# depdirs, lib/push.sh), to the folder that one is, their paths in LINT_DEPS. worktree.setup is not run there.
lintbasewt() { # <worktree> <base> <base worktree>
  local p ps
  LINT_DEPS=()
  lintbasegone "$1" "$3"
  packget linkFromMain ps && mkdir -p "${3%/*}" && git -C "$1" worktree add -q --detach "$3" "$2" > /dev/null 2>&1 < /dev/null || return 1
  while IFS= read -r -d '' p; do
    [ -d "$1/$p" ] && [ ! -e "$3/$p" ] && [ ! -L "$3/$p" ] || continue
    mkdir -p "$(dirname "$3/$p")" && ln -s "$(cd "$1/$p" && pwd -P)" "$3/$p" && LINT_DEPS+=("$p") || return 1
  done < <(jq -j '.[] | "\(.)\u0000"' <<<"$ps"; depdirs "$1" | tr '\n' '\0')
}
# Removes the base worktree <base worktree> of <worktree>'s repository, and the mainrun folder when nothing else is in it.
lintbasegone() { # <worktree> <base worktree>
  git -C "$1" worktree remove --force "$2" > /dev/null 2>&1; rm -rf "$2"; git -C "$1" worktree prune 2>/dev/null; rmdir "${2%/*}" 2>/dev/null; return 0
}
# Makes <base worktree>'s copies of the files that any <list> matches equal to <worktree>'s tree (<index>), the change
# being from <base>: each one the tree has is written, each one it deleted is deleted. Each <list> is its count, then
# that many pathspecs, read alone, so that an :(exclude) in one does not apply to another; one record is kept for all
# of them, so that putting it back deletes and checks out in one order. First, each file an
# earlier call wrote or deleted (the paths in <record file>) gets base's copy again, or is deleted when base lacks it,
# so a command's base run reads no other command's triggers; the record then holds this call's paths. A folder of a
# path that is a link in the base worktree (a tracked link the tree made a folder) is first made a folder there, and
# noted before the path, so that nothing is written or deleted in the link's target; the next call, putting the record
# back, deletes each path last path first (that folder too), then checks base's copy of each out again (the link too).
# A path the tree made a file where base has a folder (config, for base's config/old.toml) has that folder deleted.
lintsync() { # <worktree> <index> <base> <base worktree> <scratch file> <record file> [<count> <pathspec>...]...
  local w=$1 ix=$2 b=$3 bw=$4 s=$5 rec=$6 st p d r i k
  local -a ps
  local -A want=()
  shift 6
  if [ -s "$rec" ]; then
    mapfile -d '' -t ps < "$rec"
    for ((i = ${#ps[@]} - 1; i >= 0; i--)); do lintsyncrm "$bw" "${ps[i]}" || return 1; done
    # Only a path base's index holds as an entry (a file or a link; never a folder, which a pathspec would match).
    for p in "${ps[@]}"; do
      ! git -C "$bw" cat-file -e ":0:$p" 2>/dev/null || git -C "$bw" checkout-index -f -- "$p" || return 1
    done
  fi
  : > "$rec" || return 1
  while [ $# != 0 ]; do
    k=$1; shift
    # An empty list matches nothing (a git diff given no pathspec would give every path).
    [ "$k" != 0 ] || continue
    GIT_INDEX_FILE=$ix git -C "$w" diff --cached --no-renames -z --name-only "$b" -- "${@:1:k}" > "$s" || return 1
    # Each key starts with x: a path `@` or `*` would be read as the whole array.
    while IFS= read -r -d '' p; do want[x$p]=1; done < "$s"
    shift "$k"
  done
  [ ${#want[@]} != 0 ] || return 0
  GIT_INDEX_FILE=$ix git -C "$w" diff --cached --no-renames -z --name-status "$b" > "$s" || return 1
  while IFS= read -r -d '' st && IFS= read -r -d '' p; do
    [ -n "${want[x$p]:-}" ] || continue
    d='' r=$p
    while [[ $r == */* ]]; do
      d=${d:+$d/}${r%%/*} r=${r#*/}
      [ ! -L "$bw/$d" ] || { rm -f "$bw/$d" && mkdir "$bw/$d" && printf '%s\0' "$d" >> "$rec"; } || return 1
    done
    lintsyncrm "$bw" "$p" && printf '%s\0' "$p" >> "$rec" || return 1
    [ "$st" = D ] || { mkdir -p "$(dirname "$bw/$p")" && cp -pP "$w/$p" "$bw/$p"; } || return 1
  done < "$s"
}
# <path> deleted in <base worktree>: a folder with what it holds, a file or a link alone; nothing when it is not there
# (a path under a folder an earlier path made a file).
lintsyncrm() { # <base worktree> <path>
  if [ -d "$1/$2" ] && [ ! -L "$1/$2" ]; then rm -rf "${1:?}/$2"
  elif [ -e "$1/$2" ] || [ -L "$1/$2" ]; then rm -f "$1/$2"; fi
}

# The ratchet: lintcheck's lines for <worktree>'s tree, the change being from <base>, each with `reported`, the
# findings that are the change's (none unless the result is findings), its sec counting its base run too:
# - every finding of a `ratchet: false` command;
# - a finding on a line the change added or changed (every line of a file base lacks), but a `complexity` finding on
#   such a line of a file base has, which is the change's only when base's lines its hunk replaced lack the same one;
# - a finding on another line, when base lacks the same one at the line it maps to through the diff.
# One base run of the command, in <card>'s base worktree (lintbasewt), gives base's findings: on the base path of each
# file that holds a finding of the last two kinds (a renamed file's old one; all of them for a command without
# {files}), after the base worktree's copies of the command's triggers and of the pack's lint.policy files are made
# equal to the tree's (lintsync). None is made when no file holds one. "The same" is one to one, in the same file and
# with the same code and text; in a complexity finding, every number in the text counts as equal. A base run that does
# not end in pass or findings makes the command's result an execution error. The base worktree is removed at the end.
# Fails, saying why, when the pack, the tree or the change cannot be read.
lintratchet() { # <worktree> <base> <card>
  local out l c n=0 t bw=$CARDS/mainrun/$3.lint made='' bad='' run rc r why v bs
  local -a bf sp pp
  out=$(lintcheck "$1" "$2") || return 1
  [ -n "$out" ] || return 0
  packget lint l || { echo "conveyor lint: the pack's lint field could not be read" >&2; return 1; }
  t=$(mktemp -d) || return 1
  { lintindex "$1" "$t/index" && linthunkmap "$1" "$t/index" "$2" "$out" "$t/st" > "$t/hunks"; } \
    || { rm -rf "$t"; echo "conveyor lint: the change in $1 could not be read" >&2; return 1; }
  # Each finding gets its kind: card (the change's, whatever base has), line (base's finding at line `at` would make
  # it old) or range (base's finding on a line from `from` up to, not with, `to` would), and `base`, its file's base path.
  v='.complexity as $cx | .findings |= map(. as $f | ($h[$f.file] // {base: $f.file, hunks: []}) as $x
    | if $x.hunks == "all" then . + {kind: "card"}
      else (first($x.hunks[] | select(.[2] <= $f.line and $f.line < .[2] + .[3])) // null) as $k
      | if $k == null then . + {kind: "line", base: $x.base,
          at: ($f.line + ([$x.hunks[] | select(if .[3] == 0 then .[2] < $f.line else .[2] + .[3] <= $f.line end) | .[1] - .[3]] | add // 0))}
        elif $f.code | IN($cx[]) then . + {kind: "range", base: $x.base, from: $k[0], to: ($k[0] + $k[1])}
        else . + {kind: "card"} end end)'
  while IFS= read -r c; do
    n=$((n + 1))
    c=$(jq -c --slurpfile h "$t/hunks" '$h[0] as $h | if .ratchet and .result == "findings" then '"$v"' else . end' <<<"$c") || { bad=1; break; }
    : > "$t/bfound"; bf=(); bs=0
    [ "$(jq -r '.ratchet and .result == "findings"' <<<"$c")" != true ] \
      || mapfile -d '' -t bf < <(jq -j '[.findings[] | select(.kind != "card") | .base] | unique | .[] + "\u0000"' <<<"$c")
    if [ ${#bf[@]} != 0 ]; then
      r='' why=''
      mapfile -d '' -t sp < <(jq -j --argjson n $n '(.commands[$n - 1].triggers // []) | .[] + "\u0000"' <<<"$l")
      mapfile -d '' -t pp < <(jq -j '(.policy // []) | .[] + "\u0000"' <<<"$l")
      # made: 1 once the base worktree is made, 0 when it could not be (each later command's base run fails too).
      [ -n "$made" ] || { made=0; lintbasewt "$1" "$2" "$bw" && made=1; }
      # The triggers and the policy are two pathspec lists, so that an :(exclude) in one does not apply to the other.
      if [ "$made" = 1 ] && lintsync "$1" "$t/index" "$2" "$bw" "$t/st" "$t/synced" ${#sp[@]} "${sp[@]}" ${#pp[@]} "${pp[@]}" \
        && lintindex "$bw" "$t/bindex" \
        && { [ ${#LINT_DEPS[@]} = 0 ] || GIT_INDEX_FILE=$t/bindex git -C "$bw" rm -rq --cached --ignore-unmatch -- "${LINT_DEPS[@]}"; } \
        && GIT_INDEX_FILE=$t/bindex git -C "$bw" ls-files -z > "$t/bpaths"; then
        run=$(jq -r .run <<<"$c"); [[ $run == *'{files}'* ]] || bf=()
        rc=0; lintcall "$bw" "$t/bindex" "$run" "$t/bout" "${bf[@]}" || rc=$?; bs=$LINT_SEC
        lintfindings "$t/bout" "$t/bpaths" > "$t/bfound" || : > "$t/bfound"
        IFS=$'\t' read -r r why < <(lintresult "$rc" "$t/bout" "$(wc -l < "$t/bfound" | tr -d ' ')" "$LINT_OVER")
        [ "$r" != skipped ] || why="missing $why"
      else why='its base worktree could not be made or given the tree'"'"'s trigger and policy files'; fi
      case $r in pass|findings) ;; *) c=$(jq -c --arg w "the base run: $why" '.result = "error" | .why = $w' <<<"$c") || { bad=1; break; } ;; esac
    fi
    jq -c --slurpfile b "$t/bfound" --argjson bs "$bs" '.sec += $bs | def nt($cx): if .code | IN($cx[]) then .text | gsub("[0-9]+"; "0") else .text end;
      .complexity as $cx | def strip: map(del(.kind, .base, .at, .from, .to));
      .reported = (if .result != "findings" then [] elif .ratchet | not then .findings
        else reduce .findings[] as $f ({used: {}, rep: []};
          if $f.kind == "card" then .rep += [$f]
          else . as $s | (first(range(0; $b | length) as $i | $b[$i] | select(($s.used["\($i)"] | not) and .file == $f.base and .code == $f.code
              and (if $f.kind == "line" then .line == $f.at else $f.from <= .line and .line < $f.to end) and nt($cx) == ($f | nt($cx))) | $i) // null) as $k
            | if $k == null then .rep += [$f] else .used["\($k)"] = true end end) | .rep end | strip) | .findings |= strip' <<<"$c" || { bad=1; break; }
  done <<<"$out"
  [ -z "$made" ] || lintbasegone "$1" "$bw"
  rm -rf "$t"
  [ -z "$bad" ] || { echo "conveyor lint: the findings of lint command $n could not be judged" >&2; return 1; }
}

# The read-only check of a gate (lintrun): true when <worktree> matches its index and holds no file that git neither
# tracks nor ignores (an empty folder is no file: git cannot stage it).
lintclean() { # <worktree>
  local u
  git -C "$1" diff --quiet 2>/dev/null && u=$(git -C "$1" ls-files --others --exclude-standard --directory --no-empty-directory 2>/dev/null) && [ -z "$u" ]
}
# One run of a gate on <worktree>'s staged change, from <base> (the commit it is on): the ratchet's lines
# (lintratchet) in <output file>. Before the commands, the index tree is kept and lintclean must hold; else no command
# runs and nothing is put back, so no work is lost. After them (a run over the time limit too) the index tree must be
# the kept one and lintclean must hold again; else the index is read back from the kept tree, the tracked files are
# written from it (deleted ones and modes too) and each file git neither tracks nor ignores is deleted, with the folders
# that held them; an empty folder git neither tracks nor ignores that was there before the commands is made again. Writes to
# ignored paths are not checked. 0: the card goes on (each command passed, was skipped, had no files, or found nothing
# of the change's); 1: findings of the change's (reported); 2: an execution error, LINT_WHY saying what it was.
lintrun() { # <worktree> <base> <card> <output file>
  local w=$1 o=$4 tree rc=0
  local -a ed=()
  LINT_WHY=''; : > "$o"
  tree=$(git -C "$w" write-tree 2>/dev/null) && lintclean "$w" \
    || { LINT_WHY="the worktree differs from its staged change, or holds a file git neither tracks nor ignores, so no lint command ran"; return 2; }
  # The empty folders git neither tracks nor ignores (lintclean holds, so the folders git lists hold no file), each
  # with the folders in it, which the put-back's clean would delete.
  mapfile -d '' -t ed < <(git -C "$w" ls-files -z --others --exclude-standard --directory 2>/dev/null)
  [ ${#ed[@]} = 0 ] || mapfile -d '' -t ed < <(cd "$w" && find "${ed[@]/#/./}" -type d -print0 2>/dev/null)
  lintratchet "$w" "$2" "$3" > "$o" 2> "$o.err" || rc=$?
  if [ "$(git -C "$w" write-tree 2>/dev/null)" != "$tree" ] || ! lintclean "$w"; then
    if git -C "$w" read-tree "$tree" && { git -C "$w" update-index -q --refresh > /dev/null 2>&1; git -C "$w" checkout-index -a -f; } && git -C "$w" clean -fdq \
      && { [ ${#ed[@]} = 0 ] || (cd "$w" && mkdir -p -- "${ed[@]}"); }; then
      LINT_WHY="a lint command changed the worktree or its index; the engine put both back as they were"
    else LINT_WHY="a lint command changed the worktree or its index, and the engine could not put them back"; fi
    rm -f "$o.err"; return 2
  fi
  [ $rc = 0 ] || { LINT_WHY=$(head -c 600 "$o.err"); rm -f "$o.err"; return 2; }
  rm -f "$o.err"
  LINT_WHY=$(jq -rs 'map(select(.result == "error") | "lint command \(.n) (\(.run)): \(.why)") | join("; ")' "$o") || LINT_WHY='the engine could not read the lint results'
  [ -z "$LINT_WHY" ] || return 2
  ! jq -se 'any(.[]; .reported != [])' "$o" > /dev/null || return 1
}
# A gate's lint line in the card's records, for <output file> of lintrun and its exit: result pass, findings or error;
# lint.commands each command's {n, run, result, sec, findings: the count of the change's, reported: all of them as {file, line, text}, when it has any; why: an error's}, a skipped one's result
# `skipped: missing <tool>` (or <the trigger file, lintlate>); lint.asInstalled true when a command that ran (not
# one with no files or a missing tool) has a trigger the change changed (the tools ran as installed, not as the change would install them); lint.gate the gate
# that ran it, review, land (the landing gate) or wait (the gate for a waiting card), so the Board and /units can name
# the fix session it starts (track.jq). The reason says the same (each command's text cut to fit line()'s 1500 characters), and an execution error's why.
lintline() { # <card> <issue> <output file> <lintrun's exit> <review|land|wait>
  local r=pass x
  case $4 in 1) r=findings ;; 2) r=error ;; esac
  x=$(jq -cs --arg w "$LINT_WHY" --arg g "$5" 'map({n, run, result: (if .result == "skipped" then "skipped: missing \(.why)" else .result end), sec, findings: (.reported | length)} + (if .reported == [] then {} else {reported: (.reported | map({file, line, text}))} end) + (if .result == "error" then {why} else {} end)) as $c
    | any(.[]; .triggered and (.result | IN("no files", "skipped") | not)) as $i | [$c[] | ": \(.result)\(if .result == "findings" then ", \(.findings) of this change" else "" end), \(.sec) s"] as $t | (if $i then ["tools ran as installed"] else [] end) as $x
    | ((1500 - ([range($c | length) as $k | "lint command \($c[$k].n)\($t[$k])"] + $x | join("; ") | length)) / ([$c | length, 1] | max) - 3 | floor) as $room
    | {lint: {commands: $c, asInstalled: $i, gate: $g}, reason: ([range($c | length) as $k | ($c[$k].run | tostring) as $r | "lint command \($c[$k].n)\(if $room < 2 then "" elif ($r | length) > $room then " (\($r[0:$room - 1])…)" else " (\($r))" end)\($t[$k])"] + $x + (if $w == "" then [] else [$w] end) | join("; "))}' "$3") \
    || x=$(jq -cn --arg w "$LINT_WHY" --arg g "$5" '{lint: {commands: [], asInstalled: false, gate: $g}, reason: $w}')
  record "$1" "$2" lint "$r" "$x"
}
# The rule Lint check (rules.lint of the control record the card started on, CARDCTL, else the one in force): on
# unless it is false.
lintrule() { [ "$(jq -r '.rules.lint' <<<"${CARDCTL:-$(ctl 2>/dev/null)}" 2>/dev/null)" != false ]; }

# The lint policy that <worktree>'s staged change changes from <base>: the hash of that policy diff (each file's as
# lintpolicyhunks writes it, so a kept patch on a newer main mostly hashes the same) and the width of each file's
# places, by its path, `<hash> {"<path>": <width>, ...}` (one-line JSON), then its paths, one a line: each
# file that the lint.policy pathspecs of <lint field> (main's pack's) match, and .conveyor/project.json when its lint
# field changed (lintfield). A change that only removes lines from an exempt file (one that the files of a `ratchet: false`
# command match) only tightens, so it is left out. Nothing when no path is left. Fails when the change cannot be read.
# Paths are read whole, NUL-separated, so a name with a newline is one path. Each file's places are widened to one
# width, at least that file's in <least widths> (the hash's it is checked against, so a main that left only one copy
# of an approved place's lines does not drop its context lines and change the hash), 0 for a file it does not name. A
# number is every file's: an approval kept before each file had its own width hashed every file at that one.
lintpolicy() { # <worktree> <base> <lint field> [<least widths>]
  local a f p ix t h i k w lw=${4:-}; local -a ps xs ns fs=() lws ws=()
  local -A ex=()
  mapfile -d '' -t ps < <(jq -j '(.policy // [])[] + "\u0000"' <<<"${3:-null}")
  if [ ${#ps[@]} != 0 ]; then
    t=$(mktemp) || return 1
    # Each changed path: <added>\t<deleted>\t<path>.
    git -C "$1" diff --cached --no-renames -z --numstat "$2" -- "${ps[@]}" > "$t" || { rm -f "$t"; return 1; }
    mapfile -d '' -t ns < "$t"
    # The changed paths that each ratchet: false command's own pathspecs match (each command's set alone, so that its
    # :(exclude) entries apply only to it).
    for i in $(jq -r '(.commands // []) | to_entries[] | select(.value.ratchet == false) | .key' <<<"${3:-null}"); do
      mapfile -d '' -t xs < <(jq -j --argjson i "$i" '.commands[$i].files[] + "\u0000"' <<<"$3")
      git -C "$1" diff --cached --no-renames -z --name-only "$2" -- "${xs[@]}" > "$t" || { rm -f "$t"; return 1; }
      while IFS= read -r -d '' p; do ex["$p"]=1; done < "$t"
    done
    rm -f "$t"
    for p in "${ns[@]}"; do
      a=${p%%$'\t'*} p=${p#*$'\t'} p=${p#*$'\t'}
      [ -n "$p" ] || continue
      if [ "$a" != 0 ] || [ -z "${ex["$p"]:-}" ]; then fs+=("$p"); fi
    done
  fi
  ix=$(git -C "$1" rev-parse --path-format=absolute --git-path index) || return 1
  lintfield "$1" "$ix" "$2" && f=.conveyor/project.json || f=''
  [ ${#fs[@]} != 0 ] || [ -n "$f" ] || return 0
  # Each file's width (by path: a file a retry adds must not take another's): the widest its places need to be told
  # apart in <base>, and no less than its <least width>. One width for all hashed the lines next to an edit (#1575).
  mapfile -t lws < <(jq -rn --arg lw "$lw" '($lw | try fromjson catch null) as $o | $ARGS.positional[] as $p
    | if ($o | type) == "number" then $o elif ($o | type) == "object" then ($o[$p] // 0) else 0 end' --args "${fs[@]}")
  for k in "${!fs[@]}"; do w=${lws[$k]:-0}; [[ $w =~ ^[0-9]{1,6}$ ]] || w=0
    i=$(lintpolicyhunks "$1" "$2" "${fs[$k]}" "$w") || return 1; i=${i##*$'\n'}; [ "$i" -le "$w" ] || w=$i; ws+=("$w")
  done
  h=$({ for k in "${!fs[@]}"; do lintpolicyhunks "$1" "$2" "${fs[$k]}" "${ws[$k]}" || exit 1; done
    [ -z "$f" ] || git -C "$1" show ":$f" | jq -c .lint; } | git -C "$1" hash-object --stdin) && [ -n "$h" ] || return 1
  w=$(jq -cn '$ARGS.positional | (length / 2) as $n | [range($n) as $i | {(.[$i]): (.[$i + $n] | tonumber)}] | add // {}' --args "${fs[@]}" "${ws[@]}") || return 1
  printf '%s %s\n' "$h" "$w"; printf '%s\0' "${fs[@]}" ${f:+"$f"} | sort -zu | tr '\0' '\n'
}
# <worktree>'s staged diff of <path> from <base>, written the same for the same edit on a newer main where it can be
# told apart: no context lines, no index line, and each @@ header made `@@`, so lines main adds or removes away from
# the edit leave it as it was. A hunk's place is its removed lines, or, for a hunk that only adds, the line it follows.
# Each place is widened by <width> lines each side, and by one more again and again while <base>'s file names those
# lines more than once (a line such as `done` twice); widened, its lines are written after the header, the place's own
# lines marked: the same edit at another copy, or at a copy main adds, gives another text. The last line written is
# the widest any place got. Fails when the diff or <base>'s file cannot be read.
lintpolicyhunks() { # <worktree> <base> <path> <width>
  local o d rc=1
  o=$(mktemp) || return 1
  d=$(mktemp) || { rm -f "$o"; return 1; }
  # <base>'s file is empty when <base> has none (the change adds it).
  if git -C "$1" diff --cached --no-renames --binary -U0 "$2" -- ":(literal)$3" > "$d" \
    && { ! git -C "$1" cat-file -e "$2:$3" 2>/dev/null || git -C "$1" show "$2:$3" > "$o"; }; then
    # Header `@@ -<s>[,<c>] ...`: the hunk removes lines s to s+c-1, or, with c 0, adds after line s (0: at the top).
    awk -v w0="$4" 'FILENAME == ARGV[1] { o[++n] = $0; next }
      /^index / { next }
      # w: how many lines the place is widened by each side; a to e: the lines written after the header.
      /^@@ / { split(substr($2, 2), m, ","); s = m[1] + 0; c = (2 in m) ? m[2] + 0 : 1; l = c ? c : 1; print "@@"
        if (s == 0) next
        for (w = w0 + 0; ; w++) { a = s - w < 1 ? 1 : s - w; e = s + l - 1 + w > n ? n : s + l - 1 + w; k = 0
          for (p = 1; p + e - a <= n && k < 2; p++) { for (i = 0; i <= e - a && o[p + i] == o[a + i]; i++); if (i > e - a) k++ }
          if (k == 1) break }
        if (w > wm) wm = w
        # The lines of the place itself are marked "=": lines cut short at the start or end of the file can be the same
        # for two places (after the first or the second of a last done pair), and the mark tells them apart.
        if (w || !c) for (i = a; i <= e; i++) print (i < s || i > s + l - 1 ? " " : "=") o[i]
        next }
      { print }
      END { print wm + 0 }' "$o" "$d" && rc=0
  fi
  rm -f "$o" "$d"
  return $rc
}
# Whether the owner's yes covers the policy diff hashed <hash> (lintpolicy()'s `<hash> <widths>`; the hashes alone are
# compared): the card that stopped for it kept that hash in its <kept body file> (policy), and the issue now holds more
# approval lines than that body did. A yes covers one diff: a change to a policy file after it gives another hash.
lintyes() { # <issue json> <kept body file> <hash>
  [ -n "$3" ] && jq -en --argjson now "$1" --slurpfile was "$2" --arg h "$3" "$SEE"'
    ($was[0] | objects) as $w | ($w.policy | split(" ")[0]) == ($h | split(" ")[0]) and ($now | approvals) > ($w | approvals)' >/dev/null 2>&1
}
# The brief's # Lint section, with the rule Lint check on and a pack that sets lint commands; nothing otherwise.
lintbrief() {
  local l
  lintrule || return 0
  packget lint l || return 1
  [ -n "$l" ] || return 0
  printf '# Lint\n%s\n' "The pack's lint commands, each on the files its pathspecs match. Before you finish, run \`bash $HERE/conveyor.sh lint\` in this worktree and fix each finding it lists on the lines your change made. Never change lint policy (the pack's \`lint\` field, a linter's config or a suppression) unless the issue asks for it."
  jq -r '.commands // [] | to_entries[] | "- lint command \(.key + 1): \(.value | if .size then "no file over \(.size.file) lines unless the exempt file `\(.size.exempt)` names it"
    else "`\(.run)`" end), on \(.value.files | map("`\(.)`") | join(", "))"' <<<"$l"
}
# The lint pass that stands (issue 1148: a card re-fitted onto main four times ran its lint each time, 2 to 3 minutes,
# while main changed none of its files). <worktree>.linted holds the change the landing gate's lint passed on (its
# cardpatch()), the commit it ran from and the hash of the pack's lint field it ran (lintpassed()). True (lintstands())
# for the same change and lint field on a commit where main changed none of the change's files (both sides of a
# rename), no command's triggers or size exempt file, and no file a command without {files} reads: lint gives the
# same result there, so that pass is the card's. A command with {files} (a size entry too) whose trigger the change
# changes, or any command when the change changes the pack's lint field, read every file its `files` match
# (lintscope()): for it, main must have changed none of those files either. A later run that finds the change red (lintwait, lintleave) removes
# <worktree>.linted: a linter can read a file no trigger names, so that finding, not the earlier pass, decides.
lintpassed() { printf '%s\t%s\t%s\n' "$(cardpatch "$1")" "$2" "$(git hash-object --stdin <<<"$3")" > "$1.linted"; } # <worktree> <base> <lint field>
lintstands() { # <worktree> <lint field>
  local p b k h f i n all=''
  local -a ps=() fs
  { IFS=$'\t' read -r p b k < "$1.linted"; } 2>/dev/null && [ -n "$p" ] && [ "$p" = "$(cardpatch "$1")" ] && [ "$k" = "$(git hash-object --stdin <<<"$2")" ] \
    && h=$(git -C "$1" rev-parse -q --verify HEAD) || return 1
  while IFS= read -r -d '' f; do ps+=(":(literal)$f"); done < <(git -C "$1" diff --cached --name-only --no-renames -z HEAD)
  [ ${#ps[@]} != 0 ] && git -C "$1" diff --quiet "$b" "$h" -- "${ps[@]}" 2>/dev/null && n=$(jq '.commands // [] | length' <<<"$2") || return 1
  ! lintfield "$1" "$(git -C "$1" rev-parse --path-format=absolute --git-path index)" "$h" || all=1
  # Each command's pathspecs apart, so that its :(exclude) entries apply only to it, and its files apart from its
  # triggers, so that an :(exclude) of its files (a linter's own script) hides no trigger.
  for ((i = 0; i < n; i++)); do
    mapfile -d '' -t ps < <(jq -j --argjson i "$i" '.commands[$i] | (.triggers // []) + [.size.exempt // empty | ":(literal)" + .] | .[] + "\u0000"' <<<"$2")
    [ ${#ps[@]} = 0 ] || git -C "$1" diff --quiet "$b" "$h" -- "${ps[@]}" 2>/dev/null || return 1
    mapfile -d '' -t fs < <(jq -j --argjson i "$i" '.commands[$i] | (.files // [])[] + "\u0000"' <<<"$2")
    if [ -n "$all" ] || [ "$(jq -r --argjson i "$i" '.commands[$i] | .size == null and (.run | contains("{files}") | not)' <<<"$2")" = true ] \
      || { [ ${#ps[@]} != 0 ] && ! git -C "$1" diff --cached --quiet "$h" -- "${ps[@]}" 2>/dev/null; }; then
      [ ${#fs[@]} = 0 ] || git -C "$1" diff --quiet "$b" "$h" -- "${fs[@]}" 2>/dev/null || return 1
    fi
  done
}
LINTFIX=$'# Lint findings: fix them and nothing else\nThe pack\'s lint commands found <n> finding(s) in this card\'s change. The first 50 are below, each after the command that found it. Fix the code each one names. Do not change lint policy (the pack\'s `lint` field, a linter\'s config or a suppression) to make a finding go away, unless the issue asks for it.'
# The review gate (card(), at the top of each pass of its review loop, with the change staged), with the rule Lint
# check on: the pack's lint commands on the card's staged change, from the commit its worktree is on (lintrun), and
# its lint line (lintline). An execution error blocks the card, with no fix session. Findings of the change's go to
# one fix session, told them (the first 50, and how many), its reply checked as any fix's is (donewhen.sh checked()). The change
# is staged again and the gate runs again: an execution error or a finding left then blocks the card, and nothing
# lands. 0: the card goes on, its change as it was; 1: the card ended (blocked); 2: the fix session changed it, so
# the review of this pass reads it anew: no kept review or test pass stands for it. A change that is still the one the
# landing gate's fix left (lfix, below) is not run here: the landing gate decides on it, before any test.
# The landing gate (card(), with <land> set: after the parse check and before the product checks, each time they
# run): the same run, lint line, execution-error block and rule, from the commit the card's worktree is on, which a
# merge onto main moved. Findings of the change's (a merge onto main can bring them) go to one fix session, told them
# as above, with no run after it: 2, and card() takes the card round to a review, a last review, and back to this gate.
# There a finding blocks the card while its change is the one that fix left (lfix, card()'s local: its cardpatch()),
# nothing landing; a change that another session changed since gets one new fix session.
# A pass of the landing gate stands at its next runs while lintstands() holds (a re-fit onto a main that changed none
# of the card's files): no command runs and no lint line is written, the card's last lint line being its result.
lintgate() { # <card> <issue> <worktree> <issue json> <the sessions' prompt> <branch> [land]
  local c=$1 n=$2 wt=$3 land=${7:-} l base o rc k t p=''
  lintrule || return 0
  packget lint l || { block "$c" "$n" "$wt" "lint: the engine could not read the pack's lint field, so nothing landed"; return 1; }
  [ -n "$l" ] || return 0
  [ -z "${lfix:-}" ] || p=$(cardpatch "$wt") || p=''
  [ -n "$land" ] || [ -z "$p" ] || [ "$p" != "$lfix" ] || return 0
  [ -z "$land" ] || ! lintstands "$wt" "$l" || { echo "conveyor: card $c: main changed none of its files or lint settings since its lint passed, so that pass stands and lint does not run again"; return 0; }
  base=$(git -C "$wt" rev-parse -q --verify HEAD) && o=$(mktemp) || { block "$c" "$n" "$wt" "lint: the engine could not start the lint check, so nothing landed"; return 1; }
  lintrun "$wt" "$base" "$c" "$o"; rc=$?; lintline "$c" "$n" "$o" $rc "${land:-review}"
  [ $rc != 2 ] || { rm -f "$o"; block "$c" "$n" "$wt" "lint: an execution error, so nothing landed: $LINT_WHY"; return 1; }
  [ $rc = 1 ] || { rm -f "$o"; [ -z "$land" ] || lintpassed "$wt" "$base" "$l"; return 0; }
  k=$(jq -s '[.[].reported[]] | length' "$o")
  t=$(jq -rs '[.[] | . as $c | .reported[] | "lint command \($c.n) (\($c.run)): \(.file):\(.line)\(if .column then ":\(.column)" else "" end): \(.text)"] | .[:50][]' "$o")
  if [ -n "$land" ]; then
    [ -z "$p" ] || [ "$p" != "$lfix" ] || { rm -f "$o"; block "$c" "$n" "$wt" "lint: $k findings left after its fix session; nothing landed"$'\n'"$t"; return 1; }
    rm -f "$wt.ready"; locked giveway "$c" "$wt" fixing
  else locked giveway "$c" "$wt" fix; fi
  began "$c" "$n" fix
  redbrief "$c" "$n" "$6"; t=$(session "$wt" "$5"$'\n\n'"${LINTFIX//'<n>'/$k}"$'\n'"$t" fix) || { rm -f "$o"; block "$c" "$n" "$wt" "fix: $t"; return 1; }
  # lfix is the lint fix's own change, kept before donewhen.sh checked() can run a Done-when or project-check fix session: a
  # change one of those makes is another session's, and gets a new fix at the next landing gate.
  [ -z "$land" ] || { git -C "$wt" add -A 2>/dev/null; lfix=$(cardpatch "$wt") || lfix=''; }
  checked "$c" "$n" "$wt" "$4" "$5" fix "$(jq -c --arg r "lint: $k finding(s) of the change${land:+ on main as it is now}" '. + {reason: $r}' <<<"$t")" || { rm -f "$o"; return 1; }
  # A trial card's pick names the pipeline files of what the fix left (trialflag(), lib/push.sh), so the lint line below
  # and a block line carry them, not those of the change before the fix.
  git -C "$wt" add -A 2>/dev/null; trialflag "$wt"
  [ -z "$land" ] || { rm -f "$o"; return 2; }
  lintrun "$wt" "$base" "$c" "$o"; rc=$?; lintline "$c" "$n" "$o" $rc review
  t=$(jq -rs '[.[] | . as $c | .reported[] | "lint command \($c.n): \(.file):\(.line): \(.text)"] | .[:50][]' "$o" 2>/dev/null); k=$(jq -s '[.[].reported[]] | length' "$o" 2>/dev/null)
  rm -f "$o"
  [ $rc != 2 ] || { block "$c" "$n" "$wt" "lint: an execution error after its fix session, so nothing landed: $LINT_WHY"; return 1; }
  [ $rc != 1 ] || { block "$c" "$n" "$wt" "lint: $k findings left after its fix session; nothing landed"$'\n'"$t"; return 1; }
  return 2
}

# The gate for a waiting card (settle(), lib/claim.sh): with batches on, before the product checks and changed tests a
# ready card runs while it waits. 0: they run (a pass, a missing tool, no lint command or the rule off). 1: a finding
# of the change's or an execution error, recorded on its lint line: no check, test or session runs, and its
# <worktree>.ready is removed, so no batch takes it (gather()) and this gate does not run again while it waits, and its
# <worktree>.linted, so no earlier pass of its landing gate stands (lintstands()). At its turn the landing gate
# (lintgate) gives it its fix session, or blocks it on an execution error.
lintwait() { # <card> <issue> <worktree>
  local l base o rc
  lintrule || return 0
  packget lint l || { rm -f "$3.ready"; return 1; }
  [ -n "$l" ] || return 0
  base=$(git -C "$3" rev-parse -q --verify HEAD) && o=$(mktemp) || { rm -f "$3.ready"; return 1; }
  lintrun "$3" "$base" "$1" "$o"; rc=$?; lintline "$1" "$2" "$o" $rc wait; rm -f "$o"
  [ $rc != 0 ] || return 0
  rm -f "$3.ready" "$3.linted"
  echo "conveyor: card $1: its lint found $([ $rc = 1 ] && echo findings || echo 'an execution error') while it waits: it runs no check or test, and its landing gate deals with it at its turn"
  return 1
}

# The gate for a batch's combined change (batch() and rebatch(), lib/claim.sh), before its product checks: the same
# run on <worktree>'s staged change, the change of <the run's cards> on the commit the worktree is on. 0: the run goes
# on (a pass, a missing tool, no lint command or the rule off); 1: findings of the change's or an execution error
# (it prints which), a red run for the batch's split only. It writes no lint line: a line on a card that waits in the
# batch would end that card's wait on the Board. The card alone, holding the change its own tests passed on, on the
# commit they passed on (tested()), runs nothing: its gate passed there before those tests (the landing gate, or the
# gate for a waiting card), so a batch whose other cards all leave lints the card no second time. On main moved since
# (rebatch()), it runs.
lintbatch() { # <card> <worktree> <the run's cards>
  local c=$1 wt=$2 l base o rc
  shift 2
  lintrule || return 0
  packget lint l || { echo "conveyor: card $c: the engine could not read the pack's lint field for its batch's change"; return 1; }
  [ -n "$l" ] || return 0
  base=$(git -C "$wt" rev-parse -q --verify HEAD) && o=$(mktemp) || { echo "conveyor: card $c: the engine could not start the lint check of its batch's change"; return 1; }
  [ "$*" != "$c" ] || ! testedhere "$wt" || [ "$(jq -r .head "$wt.ready" 2>/dev/null)" != "$base" ] || { rm -f "$o"; return 0; }
  lintrun "$wt" "$base" "$c" "$o"; rc=$?; rm -f "$o"
  [ $rc != 0 ] || return 0
  echo "conveyor: card $c: the lint check found $([ $rc = 1 ] && echo findings || echo "an execution error ($LINT_WHY)") on the change of $*: a red run of the batch, for its split only"
  return 1
}
# The card a batch's split finds with a lint red run (lintbatch) leaves the batch with no test failure and no test
# fix: by apart (set to lint, so card() takes it back to its landing gate even on a main that did not move) when it
# is <card>, the card that runs the batch (batch()'s local), else by unbatch. Its
# <worktree>.ready is removed, so no batch takes it again, and its <worktree>.linted, so its landing gate's earlier
# pass does not stand (lintstands()); once fitted onto main, its landing gate (lintgate) gives it its fix session
# there, or blocks it. A card that the batch took leaves <card>'s kept change (<worktree>.cpatch,
# gather()) holding its own: that file is removed, so the card is not stacked onto its own change (stackto()), and a
# card waits on <card> as on one whose change cannot be read (together()).
lintleave() { # <card> <worktree> <the card that leaves>
  # shellcheck disable=SC2034 # apart is batch()'s, read by card()
  if [ "$3" = "$1" ]; then apart=lint; rm -f "$2.ready" "$2.linted"; else rm -f "$CARDS/$3.ready" "$CARDS/$3.linted" "$2.cpatch"; unbatch "$3"; fi
  echo "conveyor: card $3: the lint check failed on its change in the batch of card $1: it leaves the batch with no test failure, and its landing gate deals with it on main"
}

# `conveyor.sh lint`: the pack's lint commands on <worktree>'s tree, the change being from <base>, with no base run:
# each command's result, then its findings on lines the change added or changed (every line of a file <base> lacks),
# and every finding of a `ratchet: false` command, which fail the check (exit 1); a finding whose code is in the
# command's `complexity` on such a line, under "the gate decides these"; and a count of the findings on other lines,
# which are not judged here. Exit 0 with no finding that fails it; 2 when a command ends in an execution error and
# none does, or the tree cannot be read.
lintreport() { # <worktree> <base>
  local out t o rc=0
  out=$(lintcheck "$1" "$2") || return 2
  [ -n "$out" ] || { echo "conveyor lint: the pack $PACK sets no lint commands"; return 0; }
  t=$(mktemp -d) || return 2
  { lintindex "$1" "$t/index" && linthunkmap "$1" "$t/index" "$2" "$out" "$t/st" > "$t/hunks"; } \
    || { rm -rf "$t"; echo "conveyor lint: the change in $1 could not be read" >&2; return 2; }
  o=$(jq -rs --slurpfile h "$t/hunks" '$h[0] as $h
    | def loc: "  \(.file):\(.line)\(if .column then ":\(.column)" else "" end): \(.text)";
      def made: . as $f | $h[.file].hunks as $x | $x == "all" or ($x | type == "array" and any(.[]; .[2] <= $f.line and $f.line < .[2] + .[3]));
    map(. as $c | .findings |= map(. + {made: made}) | . + {
      fail: [.findings[] | select($c.ratchet == false or (.made and (.code | IN($c.complexity[]) | not)))],
      gate: (if $c.ratchet == false then [] else [.findings[] | select(.made and (.code | IN($c.complexity[])))] end),
      other: (if $c.ratchet == false then 0 else [.findings[] | select(.made | not)] | length end)}) as $cs
    | ($cs[] | "lint command \(.n) (\(.run)): \(if .result == "findings" then "findings: \(.findings | length)"
        elif .result == "skipped" then "skipped: missing \(.why)" elif .result == "error" then "execution error: \(.why)" else .result end)"),
      ([$cs[].fail[]] | select(length > 0) | "Findings that fail the check (on lines this change made, and every finding of a ratchet: false command):", (.[] | loc)),
      ([$cs[].gate[]] | select(length > 0) | "The gate decides these (a size finding on a line this change made):", (.[] | loc)),
      ([$cs[].other] | add | select(. > 0) | "\(.) finding(s) on lines this change did not touch: counted, not judged here."),
      "exit \(if [$cs[].fail[]] != [] then 1 elif any($cs[]; .result == "error") then 2 else 0 end)"' <<<"$out") \
    || { rm -rf "$t"; echo "conveyor lint: the results could not be read" >&2; return 2; }
  rm -rf "$t"
  printf '%s\n' "${o%$'\n'exit *}"; rc=${o##*$'\n'exit }
  return "$rc"
}

# The probe of one lint command <command json>, as doctor and setup run it, its result on one line: a command with
# {files} run on one tracked file of the main checkout that its `files` match, a command without {files} run as it is;
# `ok`, `findings: <n>`, `missing: <tool>`, `error: <first line>` (or why, when it printed nothing or ran over the
# limit), or `empty` when no tracked file matches its `files` (it is not called). A size entry (lintsize) is run on
# every tracked file it matches. A git ls-files that fails (a pathspec git refuses) gives `error: <git's first line>`.
# <scratch folder> holds its files: `paths`, the main checkout's tracked paths, is made when it is not there.
lintprobe() { # <command json> <scratch folder>
  local c=$1 t=$2 run rc r why f sz l
  local -a fs one
  [ -e "$t/paths" ] || git -C "$MAIN" ls-files -z > "$t/paths" 2> "$t/err" \
    || { rm -f "$t/paths"; IFS= read -r l < "$t/err"; echo "error: ${l:-git ls-files failed}"; return 0; }
  run=$(jq -r "$LINTRUN" <<<"$c"); sz=$(jq -r '.size // empty | "\(.file | floor)\t\(.exempt)"' <<<"$c")
  mapfile -d '' -t fs < <(jq -j '.files[] + "\u0000"' <<<"$c")
  git -C "$MAIN" ls-files -z -- "${fs[@]}" > "$t/m" 2> "$t/err" \
    || { IFS= read -r l < "$t/err"; echo "error: ${l:-git ls-files failed}"; return 0; }
  mapfile -d '' -t -n 1 one < "$t/m"
  if [ ${#one[@]} = 0 ]; then echo empty; return 0; fi
  if [ -n "$sz" ]; then
    mapfile -d '' -t one < "$t/m"
    LINT_OVER=''; rc=0; lintsize "$MAIN" "${sz%%$'\t'*}" "${sz#*$'\t'}" "${one[@]}" > "$t/out" 2>&1 || rc=$?
  else
    [[ $run == *'{files}'* ]] || one=()
    rc=0; lintcall "$MAIN" '' "$run" "$t/out" "${one[@]}" || rc=$?
  fi
  lintfindings "$t/out" "$t/paths" > "$t/found" || : > "$t/found"
  f=$(wc -l < "$t/found" | tr -d ' ')
  IFS=$'\t' read -r r why < <(lintresult "$rc" "$t/out" "$f" "$LINT_OVER")
  case $r in
    pass) echo ok ;;
    findings) echo "findings: $f" ;;
    skipped) echo "missing: $why" ;;
    *) [ -n "$LINT_OVER" ] || { IFS= read -r l < "$t/out" && [ -n "${l%$'\r'}" ] && why=${l%$'\r'}; }
       echo "error: $why" ;;
  esac
}

# doctor's probe of the pack's lint commands (lintprobe), one line each: `lint command <n> (<run>): <result>`.
lintdoctor() {
  local l c n=0 t
  packget lint l || { echo "missing: a readable lint field in the pack $PACK; fix: correct it"; return 1; }
  [ -n "$l" ] || return 0
  t=$(mktemp -d) || return 1
  while IFS= read -r c; do
    n=$((n + 1)); echo "lint command $n ($(jq -r "$LINTRUN" <<<"$c")): $(lintprobe "$c" "$t")"
  done < <(jq -c '.commands // [] | .[]' <<<"$l")
  rm -rf "$t"
}
