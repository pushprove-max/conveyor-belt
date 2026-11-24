#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# research.sh create | start | guard -- the research lane (plan docs/plans/conveyor-plugin-2026-11-10.md, section
# 11b). The lane is a worktree of the project where a Claude session researches and reports; it changes nothing
# tracked, and work it wants built becomes an issue that starts held until the owner says yes.
# create (`conveyor.sh lane research create`, re-runnable; CONVEYOR_MAIN names the main checkout, CONVEYOR_STATE_DIR
#   the state folder): first runs the lane's shell (research-bash, of the pinned install) once, and makes nothing when
#   it cannot run here (no sandbox on this host) or runs as root, saying why in one line. Then makes the worktree when
#   it is not there (detached at the pack's defaultBranch), at the host file's lanes.research.worktree (~/ is the
#   home), else <main checkout>-research beside the main checkout; makes its reports/ folder untracked (a .gitignore of *); and writes its
#   .claude/settings.local.json whole: the model and effort of the pack's lanes.research, the 1-hour prompt cache, the
#   lane's shell as CLAUDE_CODE_SHELL (so every Bash call runs where the operating system lets it write only reports/,
#   the lane's folder and the temp folder; research-bash says how), and its hooks, each run through the shim of the
#   pinned install in exec form (a command and its arguments, which Claude Code runs outside that shell): start at
#   SessionStart; guard before a Bash, Edit, Write, MultiEdit or NotebookEdit call; and the Foreman's filing (before a
#   Bash call) and filed (after it, failed or not), so an issue the lane files starts held (foreman/foreman.sh says
#   how). The lane's own folder (`lanes/research` in the state folder) holds what filing keeps between the two. Last,
#   it makes each file git tracks in the worktree, each folder holding one and the worktree read-only on disk, so the
#   Edit tools, which run outside the lane's shell, cannot write them either.
# start (SessionStart): the lane's rules: where reports go, and that work is filed by the lane's filing command
#   (research-file, the one way out of the shell's sandbox to GitHub), where it starts held, and that a message for the
#   project's Foreman goes by research-file --tell (foreman/tell.sh).
# guard (PreToolUse): refuses a git command that can change what git tracks (a commit, a push; git by any path; a
#   subcommand made by an expansion cannot be read, so it is refused too), and, so that refusal is not run round, a
#   program whose commands cannot be read: a program the session could have written (a file git does not track, run by
#   its path or given to a shell or an interpreter), any interpreter run for more than its version or help (code
#   inline, python -c, or on its input); any Bash call when the lane's shell is not the one Claude Code runs (Claude Code runs plain bash when CLAUDE_CODE_SHELL names no program); and an edit or
#   write by the Edit tools anywhere but the folders the lane's shell may write, or to a file git tracks or in a git
#   folder there (a symbolic link is followed to the file it writes).
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
HOSTF=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json

# The lane's folder, written into the host file for the Board, which reads each record's lanes from there: the
# lanes.research.worktree of this checkout's record, the record whose main is this checkout. Nothing else names a
# checkout's record: a record's repo is a name to show, and a checkout's folder may bear another project's. Paths
# are compared as the folders they name (test -ef), so a record that spells its checkout another way (a trailing /.,
# a link) is still this checkout's; each main is read whole, NUL-ended, so one with a tab or a newline in it is
# neither cut short into another path nor passed over. The file
# is read and replaced under one lock ($HOSTF.lock), so two lanes made at once both stay written. With no host
# file nothing is written; with one that has no such record, nothing is written and the line says what the Board
# needs. A file that cannot be written fails. Twin of lanenote in conveyor.sh.
lanenote() { # <main checkout> <the lane's folder>
  [ -d "$1" ] || return 1
  [ -e "$HOSTF" ] || return 0
  ( flock 9 || exit 1
    mapfile -d '' a < <(jq -j '.records | arrays | to_entries[] | select(.value | objects | .main | strings | test("\u0000") | not) | "\(.key)\u0000\(.value.main)\u0000"' "$HOSTF")
    wait $! || exit 1
    i=
    for ((n = 0; n < ${#a[@]}; n += 2)); do
      m=${a[n+1]}
      [ "$m" = "$1" ] || { [[ $m == /* ]] && [ "$m" -ef "$1" ]; } || continue
      i=${a[n]}; break
    done
    [ -n "$i" ] || exit 3
    jq --argjson i "$i" --arg w "$2" '.records[$i].lanes.research.worktree = $w' "$HOSTF" > "$HOSTF.lane.$$" && [ -s "$HOSTF.lane.$$" ] && mv "$HOSTF.lane.$$" "$HOSTF"
  ) 9>>"$HOSTF.lock"
  case $? in
    0) ;;
    3) echo "conveyor: the host file $HOSTF has no record of this checkout: the Board shows this lane once a record's lanes.research.worktree names $2" >&2 ;;
    *) rm -f "$HOSTF.lane.$$"; echo "conveyor: the lane's folder $2 could not be written into the host file $HOSTF: the Board does not show this lane" >&2; return 1 ;;
  esac
}

create() {
  local main=${CONVEYOR_MAIN:?} pack lane pin shim jail pd err w b ld f fs=(.)
  pack=$main/.conveyor/project.json
  lane=$("$HERE/../lib/pack.sh" get lanes.research "$pack") || return 1
  [ -n "$lane" ] || { echo "conveyor: the pack $pack names no lanes.research (the lane's model and effort)" >&2; return 1; }
  # The project's engine: the pin, or the current engine on this machine of a pack that follows the plugin's main.
  pin=$("$HERE/../lib/pack.sh" get plugin.commit "$pack") || return 1
  [ -z "$("$HERE/../lib/pack.sh" get plugin.follow "$pack")" ] || pin=$(jq -r '.commit // empty' "$main/.git/conveyor-engine.json" 2>/dev/null)
  [[ $pin =~ ^[0-9a-f]{40}$ ]] || { echo "conveyor: the pack of $main pins no Conveyor commit, and none of the plugin's main is taken; run /conveyor-belt:setup first" >&2; return 1; }
  shim=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions/$pin/shim.sh
  jail=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions/$pin/conveyor/lanes/research-bash
  # The lane is read-only by its shell's sandbox and by its files' modes: where those cannot hold, nothing is made.
  [ "$(id -u)" != 0 ] || { echo "conveyor: made no research lane: it runs as root, whom a file's read-only mode does not stop" >&2; return 1; }
  pd=$(mktemp -d) && git init -q "$pd/w" && mkdir "$pd/w/reports" "$pd/ld" "$pd/tmp" || return 1
  err=$(CONVEYOR_RESEARCH_REPORTS=$pd/w/reports CONVEYOR_RESEARCH_DIR=$pd/ld TMPDIR=$pd/tmp "$jail" -c true 2>&1 >/dev/null) || {
    rm -rf "$pd"
    echo "conveyor: made no research lane: its commands run in an operating-system sandbox (bubblewrap on Linux, sandbox-exec on macOS), which does not run here: ${err%%$'\n'*}" >&2; return 1; }
  rm -rf "$pd"
  b=$("$HERE/../lib/pack.sh" get defaultBranch "$pack") || return 1
  w=$(jq -r '.lanes.research.worktree // empty | strings' "$HOSTF" 2>/dev/null)
  [[ $w != "~/"* ]] || w=$HOME/${w#"~/"}
  w=${w:-$main-research}
  if [ ! -e "$w" ]; then
    git -C "$main" worktree add -q --detach "$w" "$b" || return 1
    echo "conveyor: made the research lane's worktree $w"
  elif [ "$(git -C "$w" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" != "$(git -C "$main" rev-parse --path-format=absolute --git-common-dir)" ] \
    || [ "$(git -C "$w" rev-parse --show-toplevel)" != "$(cd "$w" && pwd -P)" ] || [ "$(cd "$w" && pwd -P)" = "$(cd "$main" && pwd -P)" ]; then
    echo "conveyor: $w is there and is not a worktree of $main of its own (the main checkout, or a folder inside a worktree)" >&2; return 1
  fi
  ld=${CONVEYOR_STATE_DIR:?}/lanes/research
  chmod u+w "$w" && mkdir -p "$ld" "$w/reports" "$w/.claude" && chmod u+w "$w/.claude" || return 1
  [ -e "$w/reports/.gitignore" ] || echo '*' > "$w/reports/.gitignore" || return 1
  jq -n --argjson l "$lane" --arg ld "$ld" --arg main "$main" --arg shim "$shim" --arg jail "$jail" --arg r "$w/reports" '
    def hook($c): {type: "command", command: "/usr/bin/env",
      args: (["CONVEYOR_LANE=research", "CONVEYOR_FOREMAN_DIR=\($ld)", "CONVEYOR_MAIN=\($main)", $shim] + $c)};
    {model: $l.model, effortLevel: $l.effort,
     env: {CLAUDE_CODE_PROMPT_CACHE_TTL: "1h", CLAUDE_CODE_SHELL: $jail, CONVEYOR_RESEARCH_REPORTS: $r, CONVEYOR_RESEARCH_DIR: $ld},
     hooks: {SessionStart: [{hooks: [hook(["conveyor/lanes/research.sh", "start"])]}],
       PreToolUse: [{matcher: "Bash", hooks: [hook(["conveyor/lanes/research.sh", "guard"]), hook(["conveyor/foreman/foreman.sh", "filing"])]},
         {matcher: "Edit|Write|MultiEdit|NotebookEdit", hooks: [hook(["conveyor/lanes/research.sh", "guard"])]}],
       PostToolUse: [{matcher: "Bash", hooks: [hook(["conveyor/foreman/foreman.sh", "filed"])]}],
       PostToolUseFailure: [{matcher: "Bash", hooks: [hook(["conveyor/foreman/foreman.sh", "filed"])]}]}}' > "$w/.claude/settings.local.json.new" \
    && mv "$w/.claude/settings.local.json.new" "$w/.claude/settings.local.json" || return 1
  # The settings name the install by its path: listed in the machine's uses file, so prune() (lib/install.sh) keeps it.
  f=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/uses
  grep -qxF "$w/.claude/settings.local.json" "$f" 2>/dev/null || echo "$w/.claude/settings.local.json" >> "$f" || return 1
  # Edit and Write run in Claude Code, out of the shell's sandbox: each file git tracks (but a link, whose target could
  # be anywhere, and a submodule), each folder holding one and the worktree itself are made read-only on disk.
  while IFS= read -r -d '' f; do [[ $f == 1[26]0000* ]] || fs+=("${f#*$'\t'}"); done < <(git -C "$w" ls-files -s -z)
  while IFS= read -r -d '' f; do fs+=("$f"); done < <(git -C "$w" ls-tree -r -d -z --name-only HEAD)
  printf '%s\0' "${fs[@]}" | (cd "$w" && xargs -0 chmod a-w --) || return 1
  lanenote "$main" "$w" || return 1
  echo "conveyor: wrote the research lane's settings $w/.claude/settings.local.json; start it with: cd $(printf %q "$w") && claude"
}

start() {
  cat > /dev/null
  cat <<'EOF'
# Research lane: you research and report; you change nothing git tracks. A commit, a push and an edit to a tracked file are refused here.
# Bash runs in a sandbox: it can write only reports/, the lane's folder and the temp folder; anything else is read-only.
# Reports: write each to reports/<today, YYYY-MM-DD>/<name>.md in this worktree (untracked), then add one line for it to reports/INDEX.md: "<date> <path> <what it found, in one line>".
EOF
  # The command's path quoted for the shell, as the session runs the line it is given (a path with a space in it).
  local f; f=$(printf %q "$HERE/research-file")
  echo "# Work you want built: file it as an issue with $f <title> < <body file>; Bash has no network, so gh and curl cannot reach GitHub. It starts held, and is built only once the owner says yes."
  echo "# A message for the project's Foreman (a finding, a question, a card to file or watch): send it with $f --tell '<message>'. It reaches the Foreman in its next wake, named as the research lane's; for a long finding, write a report and send its path."
}

deny() {
  jq -cn --arg r "Refused in the research lane: $1. Write what you found as a report under reports/<date>/, and file work you want built as an issue (it starts held until the owner says yes)." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
}

# The commands that run a program they are given (a file, or what they read).
RUNNERS='bash|sh|zsh|dash|ksh|fish|source|\.|eval|exec|env|xargs|nohup|timeout|nice|command|builtin|python[0-9.]*|node|perl|ruby|php|deno|bun|lua|tclsh'
# The git subcommands that change nothing git tracks.
GITREAD='status|log|show|diff|blame|grep|ls-files|ls-tree|rev-parse|cat-file|describe|shortlog|reflog|rev-list|merge-base|for-each-ref|show-ref|fetch|remote|branch|tag|help|version'

# tracked <path> <dir>...: 0 when the path (a relative one taken from each dir), or a file under it or matching it, is
# one git tracks, or is in a git folder; a symbolic link is followed (a write goes where it points); a path or dir made
# by an expansion cannot be read, so it counts as tracked.
tracked() {
  local p=$1 b e x l n; shift
  [[ $p != *['$`']* ]] || return 0
  [[ $p != "~/"* ]] || p=$HOME/${p#"~/"}
  for b in "$@"; do
    if [[ $p == /* ]]; then e=$p; else [[ $b != *['$`']* ]] || return 0; e=$b/$p; fi
    n=0
    while [ -L "$e" ]; do
      [ $((n += 1)) -le 40 ] && l=$(readlink "$e") || return 0
      [[ $l == /* ]] || l=$(dirname "$e")/$l
      e=$l
    done
    x=$e; while [ ! -d "$x" ]; do x=$(dirname "$x"); done
    [ "$(git -C "$x" rev-parse --is-inside-git-dir 2>/dev/null)" != true ] || return 0
    [ -z "$(git -C "$x" ls-files -- "$(cd "$x" && pwd -P)${e#"$x"}" 2>/dev/null)" ] || return 0
  done
  return 1
}
# writable <path> <dir>...: 0 when the path (a relative one taken from each dir) is there and git does not track it, so
# the session could have written it; a path made by an expansion cannot be read, so it counts as writable.
writable() {
  local p=$1 b e; shift
  [[ $p != *['$`']* ]] || return 0
  [[ $p != "~/"* ]] || p=$HOME/${p#"~/"}
  for b in "$@"; do
    if [[ $p == /* ]]; then e=$p; else [[ $b != *['$`']* ]] || return 0; e=$b/$p; fi
    { [ -e "$e" ] || [ -L "$e" ]; } && ! tracked "$e" / && return 0
  done
  return 1
}
# The command with quotes kept (QUOTED): what a pair of quotes or a backslash holds stays one word (`"a b.txt"`), each
# character in it that splits words moved up by 0xE000; `back` puts them back. A $ in single quotes or after a
# backslash (rg '\$HOME') is held too: it expands nothing, so it is no expansion. An ANSI-C quote ($'\x2d') is decoded by
# the shell, not here, so its word keeps a held backquote: it is read as one made by an expansion.
QUOTED='def held: if test("[\\s;&|(){}<>=,:`]") then explode | map(. + 57344) | implode else . end;
  gsub("[0-9]*[<>]&[0-9-]*"; "") | gsub("&>"; ">")
  | reduce (explode[] | [.] | implode) as $ch ({o: "", q: null, e: false};
      if $ch == "$" and (.e or (.q != null and .q != "\"")) then .e = false | .o += ($ch | explode | map(. + 57344) | implode)
      elif .e then .e = false | .o += ($ch | held)
      elif $ch == "\\" and .q != "\u0027" then .e = true
      elif .q == null and ($ch == "\"" or $ch == "\u0027") then .q = $ch
        | if .o | endswith("$") then .o = .o[:-1] + (if $ch == "\"" then "" else "$\ue060" end) else . end
      elif .q != null and $ch == .q then .q = null
      elif .q != null then .o += ($ch | held)
      else .o += $ch end) | .o'
BACK='def back: explode | map(if . >= 57344 and . < 57472 then . - 57344 else . end) | implode;'
# writes <path> <dir>: 0 when the path (a relative one taken from dir), its symbolic links followed, is in a folder the
# lane's shell may write (the reports folder, the lane's folder or the temp folder) and is no file git tracks nor in a
# git folder. A .. past where the path is there cannot be resolved here, so such a path is in none.
writes() {
  local e=$1 l x n=0 a
  [[ $e == /* ]] || e=$2/$e
  while [ -L "$e" ]; do
    [ $((n += 1)) -le 40 ] && l=$(readlink "$e") || return 1
    [[ $l == /* ]] || l=$(dirname "$e")/$l
    e=$l
  done
  x=$e; while [ ! -d "$x" ]; do x=$(dirname "$x"); done
  [[ ${e#"$x"}/ != */../* ]] || return 1
  e=$(cd "$x" && pwd -P)${e#"$x"}
  for a in "${CONVEYOR_RESEARCH_REPORTS:-}" "${CONVEYOR_RESEARCH_DIR:-}" "${TMPDIR:-/tmp}"; do
    [ -n "$a" ] && [ -d "$a" ] && a=$(cd "$a" && pwd -P) && [[ $e == "$a"/* ]] && ! tracked "$e" / && return 0
  done
  return 1
}

guard() {
  local in d c w t cmds words dirs
  in=$(cat)
  d=$(jq -r '.cwd // empty' <<<"$in"); d=${d:-$PWD}
  if [ "$(jq -r '.tool_name // empty' <<<"$in")" = Bash ]; then
    # Claude Code runs a Bash call in plain bash, out of the sandbox, when CLAUDE_CODE_SHELL names no program.
    [ -x "${CLAUDE_CODE_SHELL:-}" ] && [ "$CLAUDE_CODE_SHELL" -ef "$HERE/research-bash" ] \
      || { deny "a Bash call, as the lane's sandboxed shell ($HERE/research-bash) is not the one Claude Code runs here; run \`conveyor.sh lane research create\` again and restart the session"; return 0; }
    # Quotes and backslashes are dropped first, so `git 'commit'` is seen.
    c=$(jq -r '.tool_input.command // "" | gsub("\\$?[\"\u0027]|\\\\"; "")' <<<"$in")
    # A git run by any path (/usr/bin/git) whose subcommand, past its options (with the values of those that take
    # one), is not one that changes nothing; one made by an expansion cannot be read, so it is refused too. So is an
    # option that can rename a subcommand or run a command (-c, with its value apart or attached, --config-env, --exec-path, git grep -O), and --output.
    jq -en --arg c "$c" --arg r "$GITREAD" '$c | test("(^|[\\s;&|(`{/])git(?>\\s+-C\\s+\\S+|\\s+--(git-dir|work-tree|namespace|super-prefix)\\s+\\S+|\\s+-(?!c|-(config-env|exec-path)\\b)\\S+)*\\s+((?!-)(?!(" + $r + ")(\\s|$))\\S+|-c|--(config-env|exec-path)\\b)|(^|[\\s;&|(`{/])git\\s[^;&|\\n]*\\s(--output|--open-files-in-pager|-O)")' >/dev/null 2>&1 \
      && { deny "a git commit, push or other git command that can change what git tracks"; return 0; }
    # What follows keeps that refusal from being run round by a program whose commands cannot be read (it could run
    # git push): code given to an interpreter and a program the session wrote.
    # The command with quotes kept, its fd redirections dropped.
    w=$(jq -r ".tool_input.command // \"\" | $QUOTED" <<<"$in")
    # A redirection to a file descriptor (2>&1, >&2) is no command, and &> writes as > does.
    c=$(sed -E 's/[0-9]*[<>]&[0-9-]*//g; s/&>/>/g' <<<"$c")
    # An interpreter's own code cannot be read: it can build a tracked path no word names (open("README"+".md")). So an
    # interpreter, run first in a part (past coproc and leading redirections) or by a shell or a command that runs one
    # (env, timeout, xargs), is refused unless it is only asked its version or help (--version, -V, -h; -v where it
    # runs nothing else) as its first word, which runs no code (one later can be an option's value: python3 -X --version): code inline (python -c, perl -e, node -e), on its input or in a program
    # file (one given to it is refused below) cannot be read. The command is split with quotes kept, so quoted text
    # is no command; a word given to a shell or a runner (bash -c "...") and a command substitution in a quoted word
    # are read as commands too.
    jq -e --arg r "$RUNNERS" "$BACK def quoted: $QUOTED;"'
      def interp: test("^(.*/)?(python[0-9.]*|node|perl|ruby|php|deno|bun|lua|tclsh)$");
      def inline($n): test("^--eval(=|$)|^-$|^<") or (($n | test("^(.*/)?python")) and test("^-[A-Za-z]*[cm]"))
        or (($n | test("^(.*/)?(perl|ruby|lua)$")) and test("^-[A-Za-z0-9]*[eE]"))
        or (($n | test("^(.*/)?(node|bun)$")) and test("^-[A-Za-z]*[ep]|^--print$"))
        or (($n | test("^(.*/)?php$")) and test("^-[A-Za-z]*[rRBE]")) or (($n | test("^(.*/)?deno$")) and . == "eval");
      def asks($n): test("^(--version|--help|-V|-h)$") or (. == "-v" and ($n | test("^(.*/)?(perl|node|php|bun)$")));
      def lead: if length > 0 and (.[0] | test("^[0-9]*[<>]"))
        then (if .[0] | test("^[0-9]*[<>]+$") then .[2:] else .[1:] end | lead) else . end;
      def bad: [quoted | splits("[;&|(){}`\\n]") | [splits("\\s+") | select(length > 0) | back
          | select(test("^[A-Za-z_][A-Za-z0-9_]*=|^(if|then|else|elif|do|while|until|!|time|coproc)$") | not)] | lead
        | select(length > 0) | . as $a
        | any(.[] | select(test("\\$\\(|`")) | sub("^.*?(\\$\\(|`)"; ""); bad)
          or ((($a[0] | interp) or ($a[0] | sub("^.*/"; "") | test("^(" + $r + "|sudo|stdbuf)$")))
            and (any($a[1:][]; bad) or ((first(range($a | length) | select($a[.] | interp)) // null) as $i | $i != null
              and ($a[$i] as $n | ($a[$i + 1:] | any(inline($n))) or (($a[$i + 1] // "") | asks($n) | not)))))] | any;
      .tool_input.command // "" | bad' <<<"$in" >/dev/null 2>&1 \
      && { deny "an interpreter run for more than its version or help: its code cannot be read"; return 0; }
    # Relative paths are taken from the session's folder and from each folder the command changes to.
    dirs=("$d")
    while read -r t; do [[ $t == /* || $t == "~/"* ]] && dirs+=("$t") || dirs+=("$d/$t"); done \
      < <(grep -oE '(^|[[:space:];&|(){}`])(cd|pushd)[[:space:]]+[^[:space:];&|(){}`]+' <<<"$c" | awk '{ print $NF }')
    # The commands are the first word of each part, past assignments and keywords; gh is named with its group, past
    # its flags (gh issue). Every word that is no option is read with quotes dropped and with quotes kept.
    cmds=$(tr ';&|(){}`' '\n' <<<"$c" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]*[<>]+$/) i++; else if ($i !~ /^[0-9]*[<>]/ && $i !~ /^[A-Za-z_][A-Za-z0-9_]*=/ && $i !~ /^(if|then|else|elif|do|while|until|!|time|coproc)$/) {
      g = $i; if (g == "gh") for (j = i + 1; j <= NF; j++) { if ($j == "-R" || $j == "--repo") j++; else if ($j !~ /^-/) { g = "gh " $j; break } }
      print g; break } }')
    words=$({ tr -s "[:space:];&|(){}<>=,:\`" '\n' <<<"$c"
      jq -rn --arg w "$w" "$BACK"'$w | splits("[\\s;&|(){}<>=,:`]+") | back'; } | grep -v '^-' | grep .)
    # A program the session could have written: a command run by its path (reports/x.sh), or any file or folder
    # there given to a shell or an interpreter (bash reports/x.sh, sh < reports/x.sh, cat reports/x.sh | sh).
    while read -r t; do
      [[ $t != */* ]] || ! writable "$t" "${dirs[@]}" || { deny "running $t, a program git does not track"; return 0; }
    done < <(echo "$cmds"; jq -rn --arg w "$w" "$BACK"'$w | splits("[;&|(){}`\\n]") | [splits("\\s+") | select(length > 0)
      | select(test("^[A-Za-z_][A-Za-z0-9_]*=|^(if|then|else|elif|do|while|until|!|time|coproc)$") | not)]
      | until(length == 0 or (.[0] | test("^[0-9]*[<>]") | not); if .[0] | test("^[0-9]*[<>]+$") then .[2:] else .[1:] end)
      | .[0] // empty | back')
    if grep -qxE "$RUNNERS" <<<"$cmds"; then
      while read -r t; do
        ! writable "$t" "${dirs[@]}" || { deny "a shell or interpreter given $t, which git does not track"; return 0; }
      done <<<"$words"
    fi
    return 0
  fi
  t=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$in")
  [ -z "$t" ] || writes "$t" "$d" || deny "an edit to $t, outside reports/, the lane's folder and the temp folder"
  return 0
}

case ${1:-} in
  create | start | guard) "$1" ;;
  *) echo "usage: research.sh create | start | guard" >&2; exit 2 ;;
esac
