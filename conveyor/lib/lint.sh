#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The lint check (docs/configuration.md, Lint): the pack's lint.commands, each run on the files of a change it reads,
# and its result. Sourced, never run: by commands/lint.sh (conveyor.sh lint) and commands/doctor.sh (lintdoctor).
# It uses packget (lib/prompts.sh) and the test slots (lib/slots.sh), sourced before it; lintratchet also uses depdirs
# (lib/push.sh) and CARDS (lib/paths.sh).
#
# The pack is main's ($PACK); the scripts and configs a command loads are the worktree's, as it runs at the worktree's
# top. A tree is the worktree as `git add -A` would stage it, read through a copy of its index (lintindex), so the
# worktree's own index is never changed. A command's scope (lintscope) is found by git from its pathspecs: `files`
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
LINT_LIMIT=300

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
# {files}). <full> is 1 when the pack's lint field changed. Fails when git cannot list the files.
lintscope() { # <worktree> <index> <base> <command json> <full> <scratch file>
  local -a fs tr
  local full=$5
  LINT_F=() LINT_GO=''
  mapfile -d '' -t fs < <(jq -j '.files[] + "\u0000"' <<<"$4")
  mapfile -d '' -t tr < <(jq -j '(.triggers // [])[] + "\u0000"' <<<"$4")
  [ ${#fs[@]} != 0 ] || return 0
  if [ -z "$full" ] && [ ${#tr[@]} != 0 ]; then
    GIT_INDEX_FILE=$2 git -C "$1" diff --cached --no-renames -z --name-only "$3" -- "${tr[@]}" > "$6" || return 1
    [ ! -s "$6" ] || full=1
  fi
  if [[ $(jq -r .run <<<"$4") != *'{files}'* ]]; then
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

# Runs <run> at <worktree>'s top, {files} in it replaced by the files, each quoted for the shell (as test.list's
# placeholder is), on a test slot, its stdout and stderr in <output file>. Its exit is returned; LINT_OVER is 1 when
# it ran over LINT_LIMIT. <index> (empty for the worktree's own) is the GIT_INDEX_FILE the command is given.
lintcall() { # <worktree> <index> <run> <output file> [<file>...]
  local wt=$1 ix=$2 c=$3 o=$4 q='' at rc
  shift 4; LINT_OVER=''
  [ $# = 0 ] || { printf -v q '%q ' "$@"; q=${q% }; }
  c=${c//\{files\}/"$q"}
  slot_pool > "$o" 2>&1 || return 1
  [ -n "$SLOT_HOME" ] || until slot_try || slot_wait; do :; done
  at=$SECONDS
  ( [ -n "$SLOT_HOME" ] || slot_mine || exit 1
    cd "$wt" && { [ -z "$ix" ] || export GIT_INDEX_FILE=$ix; } && exec timeout --kill-after=10 "$LINT_LIMIT" bash -o pipefail -c "$c" ) < /dev/null > "$o" 2>&1 8>&-; rc=$?
  [ -n "$SLOT_HOME" ] || slot_free
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

# The pack's lint commands run on <worktree>'s tree, the change being from <base> (a commit) to that tree: one JSON
# line a command, in the pack's order: {n, run, ratchet, complexity, result, why, files, findings}. result is pass,
# findings, skipped (why: the tool), error (why: what went wrong) or `no files` (its scope is empty: not called);
# files is the count it was given (null for a command without {files}); findings its finding lines (lintfindings).
# Nothing when the pack has no lint field. Fails, saying why, when the pack or the tree cannot be read.
lintcheck() { # <worktree> <base>
  local l t full='' c n=0 rc r why run f
  packget lint l || { echo "conveyor lint: the pack's lint field could not be read" >&2; return 1; }
  [ -n "$l" ] || return 0
  t=$(mktemp -d) || return 1
  lintindex "$1" "$t/index" && GIT_INDEX_FILE=$t/index git -C "$1" ls-files -z > "$t/paths" \
    || { rm -rf "$t"; echo "conveyor lint: the tree of $1 could not be read" >&2; return 1; }
  ! lintfield "$1" "$t/index" "$2" || full=1
  while IFS= read -r c; do
    n=$((n + 1))
    lintscope "$1" "$t/index" "$2" "$c" "$full" "$t/scope" || { rm -rf "$t"; echo "conveyor lint: the files of lint command $n could not be listed" >&2; return 1; }
    if [ -z "$LINT_GO" ]; then
      jq -c --argjson n $n '{n: $n, run, ratchet: (.ratchet != false), complexity: (.complexity // []), result: "no files", why: null, files: 0, findings: []}' <<<"$c"
      continue
    fi
    run=$(jq -r .run <<<"$c"); f=null; [[ $run != *'{files}'* ]] || f=${#LINT_F[@]}
    rc=0; lintcall "$1" "$t/index" "$run" "$t/out" "${LINT_F[@]}" || rc=$?
    lintfindings "$t/out" "$t/paths" > "$t/found" || : > "$t/found"
    IFS=$'\t' read -r r why < <(lintresult "$rc" "$t/out" "$(wc -l < "$t/found" | tr -d ' ')" "$LINT_OVER")
    jq -c --argjson n $n --arg r "$r" --arg w "$why" --argjson f "$f" \
      --slurpfile fd "$t/found" '{n: $n, run, ratchet: (.ratchet != false), complexity: (.complexity // []), result: $r,
        why: (if $w == "" then null else $w end), files: $f, findings: $fd}' <<<"$c"
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
# Makes <base worktree>'s copies of the files that <pathspec>... match equal to <worktree>'s tree (<index>), the
# change being from <base>: each one the tree has is written, each one it deleted is deleted. First, each file an
# earlier call wrote or deleted (the paths in <record file>) gets base's copy again, or is deleted when base lacks it,
# so a command's base run reads no other command's triggers; the record then holds this call's paths.
lintsync() { # <worktree> <index> <base> <base worktree> <scratch file> <record file> <pathspec>...
  local w=$1 ix=$2 b=$3 bw=$4 s=$5 rec=$6 st p
  shift 6
  if [ -s "$rec" ]; then
    while IFS= read -r -d '' p; do
      rm -f "$bw/$p" || return 1
      ! git -C "$bw" ls-files --error-unmatch -- ":(literal)$p" > /dev/null 2>&1 \
        || git -C "$bw" checkout-index -f -- "$p" || return 1
    done < "$rec"
  fi
  : > "$rec" || return 1
  [ $# != 0 ] || return 0
  GIT_INDEX_FILE=$ix git -C "$w" diff --cached --no-renames -z --name-status "$b" -- "$@" > "$s" || return 1
  while IFS= read -r -d '' st && IFS= read -r -d '' p; do
    rm -f "$bw/$p" && printf '%s\0' "$p" >> "$rec" || return 1
    [ "$st" = D ] || { mkdir -p "$(dirname "$bw/$p")" && cp -pP "$w/$p" "$bw/$p"; } || return 1
  done < "$s"
}

# The ratchet: lintcheck's lines for <worktree>'s tree, the change being from <base>, each with `reported`, the
# findings that are the change's (none unless the result is findings):
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
  local out l c n=0 t bw=$CARDS/mainrun/$3.lint made='' bad='' run rc r why v
  local -a bf sp
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
    : > "$t/bfound"; bf=()
    [ "$(jq -r '.ratchet and .result == "findings"' <<<"$c")" != true ] \
      || mapfile -d '' -t bf < <(jq -j '[.findings[] | select(.kind != "card") | .base] | unique | .[] + "\u0000"' <<<"$c")
    if [ ${#bf[@]} != 0 ]; then
      r='' why=''
      mapfile -d '' -t sp < <(jq -j --argjson n $n '(.commands[$n - 1].triggers // []) + (.policy // []) | .[] + "\u0000"' <<<"$l")
      # made: 1 once the base worktree is made, 0 when it could not be (each later command's base run fails too).
      [ -n "$made" ] || { made=0; lintbasewt "$1" "$2" "$bw" && made=1; }
      if [ "$made" = 1 ] && lintsync "$1" "$t/index" "$2" "$bw" "$t/st" "$t/synced" "${sp[@]}" && lintindex "$bw" "$t/bindex" \
        && { [ ${#LINT_DEPS[@]} = 0 ] || GIT_INDEX_FILE=$t/bindex git -C "$bw" rm -rq --cached --ignore-unmatch -- "${LINT_DEPS[@]}"; } \
        && GIT_INDEX_FILE=$t/bindex git -C "$bw" ls-files -z > "$t/bpaths"; then
        run=$(jq -r .run <<<"$c"); [[ $run == *'{files}'* ]] || bf=()
        rc=0; lintcall "$bw" "$t/bindex" "$run" "$t/bout" "${bf[@]}" || rc=$?
        lintfindings "$t/bout" "$t/bpaths" > "$t/bfound" || : > "$t/bfound"
        IFS=$'\t' read -r r why < <(lintresult "$rc" "$t/bout" "$(wc -l < "$t/bfound" | tr -d ' ')" "$LINT_OVER")
        [ "$r" != skipped ] || why="missing $why"
      else why='its base worktree could not be made or given the tree'"'"'s trigger and policy files'; fi
      case $r in pass|findings) ;; *) c=$(jq -c --arg w "the base run: $why" '.result = "error" | .why = $w' <<<"$c") || { bad=1; break; } ;; esac
    fi
    jq -c --slurpfile b "$t/bfound" 'def nt($cx): if .code | IN($cx[]) then .text | gsub("[0-9]+"; "0") else .text end;
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

# doctor's probe of the pack's lint commands, one line each: a command with {files} run on one tracked file of the
# main checkout that its `files` match, a command without {files} run as it is; `ok`, `findings: <n>`,
# `missing: <tool>`, `error: <first line>` (or why, when it printed nothing or ran over the limit), or `empty` when no
# tracked file matches its `files` (it is not called).
lintdoctor() {
  local l c n=0 t run rc r why f
  local -a fs one
  packget lint l || { echo "missing: a readable lint field in the pack $PACK; fix: correct it"; return 1; }
  [ -n "$l" ] || return 0
  t=$(mktemp -d) || return 1
  git -C "$MAIN" ls-files -z > "$t/paths" || : > "$t/paths"
  while IFS= read -r c; do
    n=$((n + 1)); run=$(jq -r .run <<<"$c")
    mapfile -d '' -t fs < <(jq -j '.files[] + "\u0000"' <<<"$c")
    git -C "$MAIN" ls-files -z -- "${fs[@]}" > "$t/m" 2>/dev/null || : > "$t/m"
    mapfile -d '' -t -n 1 one < "$t/m"
    if [ ${#one[@]} = 0 ]; then echo "lint command $n ($run): empty"; continue; fi
    [[ $run == *'{files}'* ]] || one=()
    rc=0; lintcall "$MAIN" '' "$run" "$t/out" "${one[@]}" || rc=$?
    lintfindings "$t/out" "$t/paths" > "$t/found" || : > "$t/found"
    f=$(wc -l < "$t/found" | tr -d ' ')
    IFS=$'\t' read -r r why < <(lintresult "$rc" "$t/out" "$f" "$LINT_OVER")
    case $r in
      pass) echo "lint command $n ($run): ok" ;;
      findings) echo "lint command $n ($run): findings: $f" ;;
      skipped) echo "lint command $n ($run): missing: $why" ;;
      *) [ -n "$LINT_OVER" ] || { IFS= read -r l < "$t/out" && [ -n "${l%$'\r'}" ] && why=${l%$'\r'}; }
         echo "lint command $n ($run): error: $why" ;;
    esac
  done < <(jq -c '.commands // [] | .[]' <<<"$l")
  rm -rf "$t"
}
