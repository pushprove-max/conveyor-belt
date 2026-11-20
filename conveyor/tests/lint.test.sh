#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the lint check's core (conveyor/lib/lint.sh): the pack's lint.commands, the scope each is given, its
# run and its four results; `conveyor.sh lint` in a card's worktree; doctor's probe (lintdoctor); the ratchet's judgment
# of a card's findings against its base run (lintratchet).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The case's main ($R, setup) with the stub linter $STUB/lint: it notes each run in $STUB/lint-args, one line `run`
# and its arguments, each after a space, and prints a finding for each line holding BAD (E1) or BIG (C901, with a
# column), in each file it is given or, given none, each tracked file; exit 1 with a finding, else 0. For the ratchet's
# cases: a line holding @size gives `C901 size <the file's line count>`, one holding @num `E3 line count <the same>`,
# one holding @use `E2 not defined` when no line of its file holds @def, and one holding the word in the top's
# .lintwords file (its config) `W1 <the word>`.
lintsetup() {
  setup '[]'
  printf '%s\n' '{ printf run; [ $# = 0 ] || printf " %s" "$@"; echo; } >> "$STUB/lint-args"' \
    'if [ $# = 0 ]; then mapfile -t a < <(git ls-files); set -- "${a[@]}"; fi' 'r=0; w=$(cat .lintwords 2>/dev/null)' \
    'for f; do [ -f "$f" ] || continue; c=$(($(wc -l < "$f"))); d=$(grep -c @def "$f"); n=0; while IFS= read -r l; do n=$((n + 1))' \
    '  case $l in *BAD*) echo "$f:$n: E1 a bad word"; r=1 ;; *BIG*) echo "$f:$n:1: C901 too big"; r=1 ;;' \
    '    *@size*) echo "$f:$n: C901 size $c"; r=1 ;; *@num*) echo "$f:$n: E3 line count $c"; r=1 ;;' \
    '    *@use*) [ "$d" != 0 ] || { echo "$f:$n: E2 not defined"; r=1; } ;; *) [ -z "$w" ] || [[ $l != *"$w"* ]] || { echo "$f:$n: W1 $w"; r=1; } ;; esac' \
    'done < "$f"; done; exit $r' > "$STUB/lint" || fail "the stub linter"
}
# The pack's lint.commands set to <commands json>, where $L in a run is the stub linter's command.
lintcmds() { tune --arg l "bash $STUB/lint" --argjson c "$1" '.lint = {commands: ($c | map(if .run then .run |= gsub("\\$L"; $l) else . end))}'; }
# Main commits the <file> <content> pairs; card c7's worktree, $W, is made on that commit, with no change yet.
lintwt() {
  while [ $# -gt 1 ]; do mkdir -p "$(dirname "$R/$1")" && printf '%s\n' "$2" > "$R/$1" && git -C "$R" add -f "$1" || fail "main's $1"; shift 2; done
  W=$T/$CASE/cards/c7
  git -C "$R" commit -qm files && git -C "$R" worktree add -q --detach "$W" || fail "the card's worktree"
}
# <commands> run in a shell of the engine as conveyor.sh lint loads it, main being $R: output in $T/$CASE/out, exit in RC.
lintin() {
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && . "$SRC/lib/slots.sh" && . "$SRC/lib/prompts.sh" && . "$SRC/lib/push.sh" && . "$SRC/lib/lint.sh" || exit 9
    eval "$1" ) > "$T/$CASE/out" 2>&1; RC=$?
  [ "$RC" != 9 ] || fail "the engine could not be loaded: $(cat "$T/$CASE/out")"
}
# The runs of the stub linter, in order, as $STUB/lint-args notes them.
lintargs() { cat "$STUB/lint-args" 2>/dev/null | paste -sd'|' -; }

# Bugs: a missing tool counts as a pass or as an error; a failed run counts as a pass or as findings (a bare 127, an
# exit 2, an exit 1 with nothing to show, an exit 0 that printed findings, a command that hangs, a pipe whose first
# command failed). Each command runs through lintcall and is judged by lintresult, its lines read by lintfindings.
t_lintresults() {
  local over='exec sleep 30' # sleep: the command the 1-second limit ends; nothing waits for it
  lintsetup
  # shellcheck disable=SC2016 # expanded by the engine's shell, in lintin
  lintin 'git -C "$MAIN" ls-files -z > "$T/$CASE/paths"; LINT_LIMIT=1
    one() { local rc=0; lintcall "$MAIN" "" "$1" "$T/$CASE/o" || rc=$?; lintfindings "$T/$CASE/o" "$T/$CASE/paths" > "$T/$CASE/f"
      printf "%s=" "$2"; lintresult $rc "$T/$CASE/o" "$(wc -l < "$T/$CASE/f" | tr -d " ")" "$LINT_OVER" | cut -f1; }
    one "echo clean" pass; one "echo a.txt:1: E1 x; exit 1" findings; one "echo lint: missing shellcheck; exit 127" missing
    one "exit 127" bare127; one "echo a.txt:1: E1 x; exit 2" exit2; one "echo nothing here; exit 1" one0; one "echo a.txt:1: E1 x" zero1
    one "false | cat" pipe; one "'"$over"'" over
    lintresult 127 <(echo "lint: missing shell check") 0 "" | tr "\t" /'
  [ "$(paste -sd' ' "$T/$CASE/out")" = "pass=pass findings=findings missing=skipped bare127=error exit2=error one0=error zero1=error pipe=error over=error skipped/shell check" ] \
    || fail "the results are not pass, findings, skipped and seven execution errors, the tool named: $(cat "$T/$CASE/out")"
}

# Bug: a finding of a file whose name holds a space and a colon is cut at its first colon, so it is a finding of no
# file, or of the wrong one. The path is matched whole against the tree's paths; a line naming no file of the tree is
# no finding.
t_lintpaths() {
  lintsetup
  printf '%s\0' 'a b:c.txt' 'a b' > "$T/$CASE/paths"
  printf '%s\n' 'a b:c.txt:3:2: E1 x: y' 'gone.txt:1: E1 x' 'a b:c.txt: no line' > "$T/$CASE/lines"
  # shellcheck disable=SC2016 # expanded in lintin
  lintin 'lintfindings "$T/$CASE/lines" "$T/$CASE/paths"'
  [ "$(cat "$T/$CASE/out")" = '{"file":"a b:c.txt","line":3,"column":2,"text":"E1 x: y","code":"E1"}' ] \
    || fail "the finding was not read as one of 'a b:c.txt', line 3, column 2, code E1: $(cat "$T/$CASE/out")"
}

# Bugs: a per-file command is given a deleted file, is given every file for a deletion or a rename, is given the
# renamed file under its old path, or gets an excluded file; a command with nothing to read is called anyway.
t_lintscope() {
  lintsetup
  lintcmds '[{"files": ["*.c", ":(exclude)x/*"], "run": "$L {files}"}, {"files": ["*.py"], "run": "$L {files}"}]'
  lintwt d.c one r.c two m.c three u.c four
  (cd "$W" && git rm -q d.c && git mv r.c r2.c &&echo BAD >> m.c && mkdir x && echo BAD > x/skip.c) || fail "the card's change"
  lintin 'lintcheck "$W" "$(git -C "$W" rev-parse HEAD)"'
  [ "$(lintargs)" = 'run m.c r2.c' ] || fail "the per-file command was not given m.c and r2.c alone: $(lintargs)"
  jq -e -s 'length == 2 and .[0].result == "findings" and .[0].files == 2 and .[0].findings == [{file: "m.c", line: 2, column: null, text: "E1 a bad word", code: "E1"}]
    and .[1].result == "no files" and .[1].files == 0' "$T/$CASE/out" > /dev/null \
    || fail "the results are not the m.c finding and no files: $(cat "$T/$CASE/out")"
}

# Bug: a changed trigger (the linter's config) leaves its command on the changed files alone, so an old file the new
# config fails is never read. It is given every file of the tree its files match (a file not tracked yet too); a
# command without {files} runs too, but not one whose files match no file of the tree (*.md here): its result is
# `no files`.
t_linttrigger() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "triggers": [".lintrc"], "run": "$L {files}"}, {"files": ["*.md"], "triggers": [".lintrc"], "run": "$L"},
    {"files": ["*.c"], "triggers": [".lintrc"], "run": "$L"}]'
  lintwt a.c one b.c two .lintrc old
  echo new > "$W/.lintrc"
  lintin 'lintcheck "$W" "$(git -C "$W" rev-parse HEAD)"'
  [ "$(lintargs)" = 'run a.c b.c|run' ] || fail "the trigger did not run the *.c commands alone, the per-file one on every *.c: $(lintargs)"
  jq -e -s '[.[].result] == ["pass", "no files", "pass"]' "$T/$CASE/out" > /dev/null || fail "the *.md command's result is not no files: $(cat "$T/$CASE/out")"
}

# Bug: a change to the pack's lint field (a new command, a rule turned on) is checked on the changed files alone. Every
# command runs on every file of the tree it matches, though the change touches none of them.
t_lintfield() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "run": "$L {files}"}, {"files": ["*.txt"], "run": "$L {files}"}]'
  git -C "$R" add -f .conveyor/project.json || fail "main's pack"
  lintwt a.c one
  jq '.lint.commands[0].ratchet = false' "$W/.conveyor/project.json" > "$W/p" && mv "$W/p" "$W/.conveyor/project.json" || fail "the card's pack"
  lintin 'lintcheck "$W" "$(git -C "$W" rev-parse HEAD)"'
  [ "$(lintargs)" = 'run a.c|run a.txt' ] || fail "the changed lint field did not run every command on every match in the tree: $(lintargs)"
}

# Bugs: `conveyor.sh lint` in a card's worktree misses an edit that is not staged or a file that is not tracked, stages
# them, makes a state folder or a base worktree, or exits 0 with findings on the lines the change made. A finding on
# a line it did not touch is counted, not listed. The second command, without {files}, lists the project itself with
# `git ls-files`: it must see the file that is not tracked, as the per-file one does.
t_lintcmd() {
  local before after idx
  lintsetup
  lintcmds '[{"files": ["*.c"], "run": "$L {files}"}, {"files": ["*.c"], "run": "$L"}]'
  lintwt a.c "$(printf 'BAD old\none')"
  rm -rf "$ST"
  echo 'BAD edit' >> "$W/a.c"; echo 'BAD new' > "$W/n.c"
  # status first: it refreshes the index's stat data, which is no change of the lint's.
  before=$(git -C "$W" status --porcelain); git -C "$R" worktree list --porcelain > "$T/$CASE/wt.before"
  idx=$(git -C "$W" rev-parse --git-path index); idx=$(cd "$W" && cksum < "$idx")
  out=$(cd "$W" && CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" lint 2>&1); RC=$?
  [ "$idx" = "$(cd "$W" && cksum < "$(git -C "$W" rev-parse --git-path index)")" ] || fail "conveyor.sh lint changed the worktree's index"
  after=$(git -C "$W" status --porcelain)
  [ "$RC" = 1 ] && [ "$(grep -cxF '  a.c:3: E1 a bad word' <<<"$out")" = 2 ] && [ "$(grep -cxF '  n.c:1: E1 a bad word' <<<"$out")" = 2 ] \
    && grep -qxF '2 finding(s) on lines this change did not touch: counted, not judged here.' <<<"$out" \
    || fail "conveyor.sh lint did not fail on the edit's and the new file's findings of both commands, the old ones counted (exit $RC): $out"
  [ "$before" = "$after" ] || fail "the worktree changed: '$before' then '$after'"
  [ ! -e "$ST" ] && [ ! -e "$T/$CASE/cards/mainrun" ] && git -C "$R" worktree list --porcelain | cmp -s - "$T/$CASE/wt.before" \
    || fail "conveyor.sh lint made a state folder or a base worktree: $(ls "$ST" "$T/$CASE/cards" 2>&1)"
}

# Bug: a size finding (a code the command lists in complexity) on a line the change made fails `conveyor.sh lint`,
# though the gate, with the base's findings, decides it. It is listed apart, and the exit is 0.
t_lintgate() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "complexity": ["C901"], "run": "$L {files}"}]'
  lintwt a.c one
  echo 'BIG' >> "$W/a.c"
  out=$(cd "$W" && CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" lint 2>&1); RC=$?
  [ "$RC" = 0 ] && [ "$out" = "$(printf '%s\n' 'lint command 1 (bash '"$STUB"'/lint {files}): findings: 1' \
    'The gate decides these (a size finding on a line this change made):' '  a.c:2:1: C901 too big')" ] \
    || fail "the size finding was not listed under the gate's, with exit 0 (exit $RC): $out"
}

# lintratchet on card c7's worktree $W, the change being from its commit: its lines in $T/$CASE/out, exit in RC; then
# each command's reported findings, `<file>:<line>: <text>` joined by `|` and the commands by `;`, in REP.
lintrat() {
  # shellcheck disable=SC2016 # expanded in lintin
  lintin "${1:-}"'lintratchet "$W" "$(git -C "$W" rev-parse HEAD)" c7'
  REP=$(jq -r '[.reported[] | "\(.file):\(.line): \(.text)"] | join("|")' "$T/$CASE/out" 2>/dev/null | paste -sd';' -)
}
# The base worktree is gone, and git lists no worktree of it.
lintgone() { [ ! -e "$T/$CASE/cards/mainrun" ] && ! git -C "$R" worktree list --porcelain | grep -q 'c7\.lint' || fail "the base worktree is left: $(git -C "$R" worktree list)"; }

# Bugs: a new finding on a line the change did not touch is let through (a definition deleted elsewhere in the file), an
# old one there is reported, a line after a deleted line is compared with the wrong base line, a renamed file's
# findings are all new, and two identical findings in a hunk that replaced a line with one are both matched to it.
t_lintratchet() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "complexity": ["C901"], "run": "$L {files}"}]'
  lintwt a.c "$(printf '@def\nBAD old\n@use\none')" r.c "$(printf 'BAD x\nl2\nl3\nl4\nl5')" b.c 'BIG a'
  (cd "$W" && printf 'BAD old\n@use\nBAD edit\n' > a.c && git mv r.c s.c && printf 'BAD x\nl2\nl3\nl4\nl5b\n' > s.c && printf 'BIG b\nBIG c\n' > b.c) || fail "the card's change"
  lintrat
  [ "$RC" = 0 ] && [ "$REP" = 'a.c:2: E2 not defined|a.c:3: E1 a bad word|b.c:2: C901 too big' ] \
    || fail "the change's findings are not the lost definition, the edit and one of the two size findings (exit $RC): $REP $(cat "$T/$CASE/out")"
  [ "$(lintargs)" = 'run a.c b.c s.c|run a.c b.c r.c' ] || fail "the base run was not one run on the base paths: $(lintargs)"
  lintgone
}

# Bugs: a size finding on a changed line that base has too is the change's, or is new because its number grew; a
# correctness finding whose number differs from base's is old.
t_lintsize() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "complexity": ["C901"], "run": "$L {files}"}]'
  lintwt a.c "$(printf 'f() @size\n@num\nend')" b.c 'f() @size'
  printf 'g() @size\n@num\nend\nmore\n' > "$W/a.c"; echo 'g() @size' > "$W/b.c"
  lintrat
  [ "$RC" = 0 ] && [ "$REP" = 'a.c:2: E3 line count 4' ] || fail "the reported findings are not the E3 alone (exit $RC): $REP $(cat "$T/$CASE/out")"
}

# Bugs: a card that tightens a rule in a trigger file is given every old line the new rule fails, as the base run reads
# base's own copy of the file. It reads the tree's. A later command that does not name the file as a trigger reads
# base's copy in its base run, not the copy the first command's run left, so its new finding on a.c is reported.
t_linttighten() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "triggers": [".lintwords"], "run": "$L {files}"}, {"files": ["*.c"], "run": "$L {files}"}]'
  lintwt .lintwords xyz a.c "$(printf 'foo\nbar')" b.c foo
  echo foo > "$W/.lintwords"; echo baz >> "$W/a.c"
  lintrat
  [ "$RC" = 0 ] && [ "$REP" = ';a.c:1: W1 foo' ] && [ "$(jq -r .result "$T/$CASE/out" | paste -sd' ' -)" = 'findings findings' ] \
    && [ "$(lintargs)" = 'run a.c b.c|run a.c|run a.c b.c|run a.c' ] \
    || fail "old lines the tightened rule fails were reported, a later command's base run read the tightened file, or no base run was made (exit $RC): $REP $(lintargs) $(cat "$T/$CASE/out")"
}

# Bug: a card that deletes a trigger config gets a base run that still reads it. Each run notes whether it sees one.
t_lintdeltrigger() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "triggers": [".lintwords"], "run": "{ [ -e .lintwords ] && echo has || echo none; } >> '"$STUB"'/seen; $L {files}"}]'
  lintwt .lintwords foo a.c "$(printf 'foo\nBAD old')"
  git -C "$W" rm -q .lintwords || fail "the card's change"
  lintrat
  [ "$RC" = 0 ] && [ "$REP" = '' ] && [ "$(paste -sd' ' "$STUB/seen")" = 'none none' ] \
    || fail "the base run read the deleted config (exit $RC): $(paste -sd' ' "$STUB/seen") $REP $(cat "$T/$CASE/out")"
}

# Bug: a base run that breaks is read as no base finding, so every old finding is reported. It is an execution error.
t_lintbasefail() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "run": "[ -e new.c ] || { echo the base broke; exit 3; }; $L {files}"}]'
  lintwt a.c "$(printf 'BAD old\none')"
  printf 'BAD old\ntwo\n' > "$W/a.c"; echo fine > "$W/new.c"
  lintrat
  [ "$RC" = 0 ] && [ "$(jq -c '[.result, .why, .reported]' "$T/$CASE/out")" = '["error","the base run: it exited 3: the base broke",[]]' ] \
    || fail "the failed base run is not an execution error (exit $RC): $(cat "$T/$CASE/out")"
  lintgone
}

# Bug: a `ratchet: false` command's old findings are judged against a base run. Each is reported, and none is made.
t_lintratchetoff() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "ratchet": false, "run": "$L {files}"}]'
  lintwt a.c "$(printf 'BAD old\none')"
  printf 'BAD old\nBAD new\n' > "$W/a.c"
  lintrat
  [ "$RC" = 0 ] && [ "$REP" = 'a.c:1: E1 a bad word|a.c:2: E1 a bad word' ] && [ "$(lintargs)" = 'run a.c' ] \
    || fail "not every finding was reported, or a base run was made (exit $RC): $REP $(lintargs)"
  lintgone
}

# Bugs: the base run lacks the head's dependency folders (main's link, and a folder worktree.setup filled), runs
# worktree.setup, holds no test slot or more than one, or its worktree is left. Each run notes its folders, the slots
# held in a pool of two that the case makes its own, and where it ran; worktree.setup would leave a file.
t_lintbasedeps() {
  local p=$T/$CASE/pool d
  lintsetup
  lintcmds '[{"files": ["*.c"], "run": "bash '"$STUB"'/deps.sh; $L {files}"}]'
  tune --arg s "touch $STUB/setup-ran" '.linkFromMain = ["node_modules"] | .worktree.setup = $s'
  printf '%s\n' "h=0; for k in 1 2; do flock -n '$p/'\$k true 2>/dev/null || h=\$((h + 1)); done" \
    'echo "$(cd node_modules && pwd -P) $(cd vendor && pwd -P) slots=$h $(pwd -P)" >> "'"$STUB"'/deps"' > "$STUB/deps.sh" || fail "the dependency probe"
  mkdir -p "$R/node_modules" || fail "main's node_modules"
  lintwt .gitignore "$(printf 'node_modules\nvendor')" a.c "$(printf 'BAD old\none')"
  ln -s "$R/node_modules" "$W/node_modules" && mkdir "$W/vendor" && echo two >> "$W/a.c" || fail "the card's worktree"
  lintrat 'unset CONVEYOR_TEST_SLOT; export CONVEYOR_TEST_POOL=2:'"$p"'; '
  d="$(cd "$R/node_modules" && pwd -P) $(cd "$W/vendor" && pwd -P) slots=1"
  [ "$RC" = 0 ] && [ "$REP" = '' ] && [ "$(cat "$STUB/deps")" = "$d $(cd "$W" && pwd -P)"$'\n'"$d $(cd "$T/$CASE" && pwd -P)/cards/mainrun/c7.lint" ] \
    || fail "the base run did not use the head's folders on one slot of its own (exit $RC): $(cat "$STUB/deps") $(cat "$T/$CASE/out")"
  [ ! -e "$STUB/setup-ran" ] || fail "worktree.setup was run"
  lintgone
}

# Bug: a `ratchet: false` command's finding on a line the change did not touch is only counted, so `conveyor.sh lint`
# passes a rule the project wants kept on every line. Each of its findings is listed, a size one too, and fails, under a
# heading that does not call them findings on lines this change made.
t_lintnoratchet() {
  lintsetup
  lintcmds '[{"files": ["*.c"], "ratchet": false, "complexity": ["C901"], "run": "$L {files}"}]'
  lintwt a.c "$(printf 'BAD old\nBIG old')"
  echo two >> "$W/a.c"
  out=$(cd "$W" && CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" lint 2>&1); RC=$?
  [ "$RC" = 1 ] && [ "$(grep -c '^  a\.c:' <<<"$out")" = 2 ] && grep -qxF '  a.c:1: E1 a bad word' <<<"$out" && grep -qxF '  a.c:2:1: C901 too big' <<<"$out" \
    && grep -qxF 'Findings that fail the check (on lines this change made, and every finding of a ratchet: false command):' <<<"$out" \
    && ! grep -q 'gate decides\|not judged' <<<"$out" || fail "the ratchet: false command's old findings did not fail the lint, each listed (exit $RC): $out"
}

# The pack's one lint command: the size entry, on *.c, a limit of 3 lines, the exempt file .size-exempt.
lintsizecmd() { tune '.lint = {commands: [{files: ["*.c"], size: {file: 3, exempt: ".size-exempt"}}]}'; }
# The gate's run (lintrun) on card c7's change, staged, after the optional code <first>: its exit in RC, its lines in
# $T/$CASE/res, the reported findings in REP, as lintrat gives them.
lintsizegate() {
  git -C "$W" add -A || fail "the card's change could not be staged"
  # shellcheck disable=SC2016 # expanded in lintin
  lintin "${1:-}"'lintrun "$W" "$(git -C "$W" rev-parse HEAD)" c7 "$T/$CASE/res"'
  REP=$(jq -r '[.reported[] | "\(.file):\(.line): \(.text)"] | join("|")' "$T/$CASE/res" 2>/dev/null)
}

# Bugs: at the gate, a new file of limit + 1 lines (its last line with no newline) or a file grown from limit - 1 to
# limit + 1 lines is let through; an exempt file that grows is a finding; an exempt file renamed keeps its exemption
# under its new path; a function's line in the exempt file (path, a tab, its name) exempts its file.
t_lintsizegate() {
  lintsetup; lintsizecmd
  lintwt grow.c "$(printf 'l1\nl2')" old.c "$(printf 'l1\nl2\nl3\nl4\nl5')" mv.c "$(printf 'l1\nl2\nl3\nl4\nl5')" .size-exempt "$(printf 'old.c\nmv.c\nnew.c\tf')"
  (cd "$W" && printf 'l3\nl4\n' >> grow.c && printf 'l1\nl2\nl3\nl4' > new.c && echo l6 >> old.c && git mv mv.c moved.c) || fail "the card's change"
  # lintbasewt notes each call in basewt: the gate removes the base worktree before it returns, so what is left cannot show one was made.
  # shellcheck disable=SC2016 # expanded in lintin
  lintsizegate 'lintbasewt() { touch "$T/$CASE/basewt"; return 1; }; '
  [ "$RC" = 1 ] && [ "$REP" = 'grow.c:4: size 4 lines, limit 3|moved.c:4: size 5 lines, limit 3|new.c:4: size 4 lines, limit 3' ] \
    || fail "the findings are not the grown, the renamed and the new file (exit $RC): $REP $(cat "$T/$CASE/out" "$T/$CASE/res")"
  [ ! -e "$STUB/lint-args" ] && [ ! -e "$T/$CASE/basewt" ] || fail "the size entry ran a command or made a base worktree: $(lintargs)"
}

# Bugs: a card that removes a file's line from the exempt file, and does not change that file, gets no finding for it
# though it is over the limit; the changed exempt file marks the entry triggered, so the gate's lint line says tools
# ran as installed; the brief names a size entry's run as null.
t_lintsizeexempt() {
  lintsetup; lintsizecmd
  lintwt big.c "$(printf 'l1\nl2\nl3\nl4\nl5')" keep.c "$(printf 'l1\nl2\nl3\nl4\nl5')" small.c l1 .size-exempt "$(printf 'big.c\nkeep.c')"
  echo keep.c > "$W/.size-exempt"
  lintsizegate
  [ "$RC" = 1 ] && [ "$REP" = 'big.c:4: size 5 lines, limit 3' ] && [ "$(jq -r '"\(.files) \(.triggered)"' "$T/$CASE/res")" = '3 false' ] \
    || fail "the file no longer exempt is not the one finding, of every *.c file, untriggered (exit $RC): $REP $(cat "$T/$CASE/out" "$T/$CASE/res")"
  lintin 'CARDCTL={} lintbrief'
  grep -qxF -e '- lint command 1: no file over 3 lines unless the exempt file `.size-exempt` names it, on `*.c`' "$T/$CASE/out" \
    || fail "the brief does not name the size entry: $(cat "$T/$CASE/out")"
}

# Bug: doctor says nothing of a lint command that cannot run, or runs one with no file to read. Each of five stub
# commands gives its line: ok, findings, missing, error, empty; a size entry, run in the engine, its findings on the
# fixture's two-line .gitignore. lintdoctor is called alone: doctor's other checks
# need a whole setup, and doctor() only prints what it prints.
t_lintdoctor() {
  lintsetup
  lintcmds '[{"files": ["*.txt"], "run": "$L {files}"}, {"files": ["*.txt"], "run": "echo a.txt:1: E1 x; echo a.txt:2: E2 y; exit 1"},
    {"files": ["*.txt"], "run": "echo lint: missing ruff; exit 127"}, {"files": ["*.txt"], "run": "echo the config is bad; echo more; exit 2"},
    {"files": ["*.py"], "run": "$L {files}"}, {"files": [".gitignore"], "size": {"file": 1, "exempt": "none"}}]'
  lintin 'lintdoctor'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/out")" = "$(printf '%s\n' "lint command 1 (bash $STUB/lint {files}): ok" \
    'lint command 2 (echo a.txt:1: E1 x; echo a.txt:2: E2 y; exit 1): findings: 2' 'lint command 3 (echo lint: missing ruff; exit 127): missing: ruff' \
    'lint command 4 (echo the config is bad; echo more; exit 2): error: the config is bad' "lint command 5 (bash $STUB/lint {files}): empty" \
    'lint command 6 (size, limit 1 lines): findings: 1')" ] \
    || fail "doctor's lint lines are not ok, findings, missing, error, empty and the size entry's findings: $(cat "$T/$CASE/out")"
  [ "$(lintargs)" = 'run a.txt' ] || fail "the per-file command was not run on one tracked file alone, or the empty one was run: $(lintargs)"
}

# Bug: a pack with no lint field gets lint lines from doctor or a lint run, or fails. There is nothing to say.
t_lintnone() {
  lintsetup
  lintwt a.c BAD
  echo BAD >> "$W/a.c"
  lintin 'lintdoctor && lintcheck "$W" "$(git -C "$W" rev-parse HEAD)"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/out" ] && [ ! -e "$STUB/lint-args" ] || fail "a pack with no lint field gave lint results (exit $RC): $(cat "$T/$CASE/out")"
  out=$(cd "$W" && CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" lint 2>&1) && [ "$out" = "conveyor lint: the pack $R/.conveyor/project.json sets no lint commands" ] \
    || fail "conveyor.sh lint with no lint field: $out"
}
