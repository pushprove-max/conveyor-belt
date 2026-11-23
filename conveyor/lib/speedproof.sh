# SPDX-License-Identifier: Apache-2.0
# The checks of the cards the Board's Tests page files about one test file, in place of the bug-card check: a speed-up
# or Optimize card (speedproof(), optproof()), a Fix failures or Fix the waiting card (steadyproof()), a Fix the
# hollow cases card (hollowproof()) and a card that makes a test file run alone (aloneproof()). Sourced by
# lib/testrun.sh.
# The test file of a speed-up issue (card()): an issue whose title starts SPEEDUP (or the title start given: OPTIMIZE),
# as the Board's Tests page files it (`conveyor.sh testissue`). The file is the one that filing kept for the issue
# ($TAFILED), else the title's word after that start. Prints it; fails for any other issue.
# A Rewrite as a direct check issue (#778, REWRITE: "Rewrite the test file <file> as direct checks") is an Optimize
# issue with the verdict indirect (optverdict()), and a Split it issue (#768, SPLIT: "Split the test file <file>") one
# with the verdict split. A Tests page card with no issue (testcardissue(), lib/testaction.sh) has no filing kept: its
# file is its title's.
# shellcheck disable=SC2034 # OPTIMIZE, REWRITE and SPLIT are used in lib/card.sh
SPEEDUP='Speed up the test file ' OPTIMIZE='Optimize the test file ' REWRITE='Rewrite the test file ' SPLIT='Split the test file '
speedfile() { # <issue json> [title start: SPEEDUP]
  local t f p=${2:-$SPEEDUP}
  t=$(jq -r '.title // ""' <<<"$1"); [[ $t == "$p"* ]] || return 1
  f=$(jq -rRn --argjson n "$(jq -r '.number // 0' <<<"$1")" '[inputs | fromjson? | objects | select(.event == "filed" and .issue == $n) | .file | strings] | last // empty' "$TAFILED" 2>/dev/null)
  [ -n "$f" ] || { f=${t#"$p"}; f=${f%%[[:space:]]*}; }
  [ -n "$f" ] && printf '%s\n' "$f"
}
# The verdict an Optimize card is checked by (speedproof(), optproof()): the one its issue's body names on the Board's
# line "The judge's verdict (<when, seat>): <verdict>." (draftIssue(), .claude/dashboard/panels/tests.js), else on its
# last VERDICT: line (TAVERDICTS, lib/testaction.sh), in lower case; <none> ("speed up" when not given) for an issue
# that names none (a speed-up issue). A Rewrite as a direct check issue (its title starts REWRITE) is indirect, and
# a Split it issue (SPLIT) split, whatever its body says.
optverdict() { # <issue json> [<none>]
  ! speedfile "$1" "$REWRITE" > /dev/null || { echo indirect; return 0; }
  ! speedfile "$1" "$SPLIT" > /dev/null || { echo split; return 0; }
  jq -r --arg v "$TAVERDICTS" --arg n "${2:-speed up}" '[(.body // "") | split("\n")[] | sub("^[\\s*`_>-]+"; "")] as $l
    | ([$l[] | capture("^The judge.s verdict \\(.*\\):\\s*(?<v>" + $v + ")[\\s.*`_]*$"; "i").v | ascii_downcase] | last)
      // ([$l[] | capture("^VERDICT:[\\s*`_]*(?<v>" + $v + ")([^[:alpha:]].*)?$"; "i").v | ascii_downcase] | last) // $n' <<<"$1" 2>/dev/null \
    || echo "${2:-speed up}"
}
# The CPU seconds an Optimize or speed-up card's test file is held to (speedbrief(), speedproof()), printed as
# `<CPU s><TAB><what they are>`: the median of the recent runs its issue lists (the Board's line "- Last runs, newest
# first: <n> CPU s (<by>), ...", draftIssue()), else the file's median on record (the Tests page's, testspart()). A
# file whose cost grew is held to what it costs now, not to its old median. Prints nothing with neither.
recentcpu() { # <issue json> <test file>
  local r
  r=$(jq -r '[(.body // "") | split("\n")[] | select(test("^[\\s*_>-]*Last runs, newest first:")) | [scan("([0-9]+(?:\\.[0-9]+)?) CPU s") | .[0] | tonumber]]
    | last // [] | sort | if length == 0 then empty else (if length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end)
      | . * 1000 | round / 1000 end' <<<"$1" 2>/dev/null)
  if [ -n "$r" ]; then printf '%s\tthe median of its recent runs\n' "$r"; return 0; fi
  r=$(testspart "$(date +%F)" 2>/dev/null | jq -r --arg f "$2" 'first(.files[]? | select(.file == $f) | .median | numbers) // empty' 2>/dev/null)
  [ -z "$r" ] || printf '%s\tits median on record\n' "$r"
}
# The CPU seconds of the slowest of the recent runs an issue lists (recentcpu()'s line), or nothing when it lists none.
# One run of a file varies a lot while other cards run (#1140): speedproof() takes a run below it as inside the spread.
slowestrun() { # <issue json>
  jq -r '[(.body // "") | split("\n")[] | select(test("^[\\s*_>-]*Last runs, newest first:")) | [scan("([0-9]+(?:\\.[0-9]+)?) CPU s") | .[0] | tonumber]]
    | last // [] | max // empty | . * 1000 | round / 1000' <<<"$1" 2>/dev/null
}
# What a stabilise card's build must end its reply with (speedbrief(), speedproof()): one line for each flaky or
# failing case its issue names on the judge's CAUSE lines (tacauses(), lib/testaction.sh), or at least one line when
# it names none.
STABLINE='`STABILISED: <case> | <its cause: a race, a timing wait, shared state, ...> | <how the change removes it>`'
# The cases a stabilise card's build reply (<worktree>.out, its text) gives no STABILISED line, with its cause and how
# the change removes it, for: of those its issue names on CAUSE lines, one a line; "-" alone when the issue names none
# and the reply has no such line. Prints the reply's STABILISED lines, `<case> | <cause> | <how>`, on stdout of
# `stabilised <worktree>` with no issue.
stabilised() { # <worktree> [<issue json>]
  local got
  got=$(jq -Rrn '[inputs | fromjson? // empty | objects | if .type == "result" then .result elif .type == "item.completed" and .item.type? == "agent_message" then .item.text
      elif .type == "text" then .part.text? else empty end | strings | split("\n")[] | sub("^[\\s*`_>-]+"; "")
      | capture("^STABILISED:\\s*`?(?<case>[^|`]*[^|\\s`])`?\\s*\\|\\s*(?<cause>[^|]*[^|\\s])\\s*\\|\\s*(?<how>.*?[^\\s*`_])[\\s*`_]*$")] | unique[] | "\(.case) | \(.cause) | \(.how)"' "$1.out" 2>/dev/null)
  # The lines are kept in <worktree>.stabilised, so the check again after a fix round (cardreview()) still reads the
  # build's: the fix's reply replaces <worktree>.out. A case the newer reply names has its lines alone, not the kept
  # ones. They are sorted, so the same lines read the same (rechecked()). Bugs: a fix that named no cause blocked the
  # card; one that named a new cause left the old one for review; one that repeated a line had the check run again.
  got=$({ [ -z "$got" ] || printf '%s\n' "$got"; echo; cat "$1.stabilised" 2>/dev/null; } \
    | awk -F ' [|] ' '!o { if (!NF) { o = 1; next } n[$1] = 1; print; next } NF && !($1 in n) && !s[$0]++' | LC_ALL=C sort)
  [ -z "$got" ] || printf '%s\n' "$got" > "$1.stabilised"
  [ $# -gt 1 ] || { [ -z "$got" ] || printf '%s\n' "$got"; return 0; }
  jq -r '.body // ""' <<<"$2" | tatagged CAUSE "$TACAUSE" /dev/stdin 2>/dev/null | jq -r '.[] | objects | .case | gsub("^[`\"'"'"']+|[`\"'"'"']+$"; "")' 2>/dev/null \
    | awk 'NF && !s[$0]++' | jq -Rrn --arg got "$got" '[$got | split("\n")[] | select(. != "") | split(" | ")[0]] as $g | [inputs] as $c
      | if $c == [] then (if $g == [] then "-" else empty end) else $c[] | select(IN($g[]; .) | not) end'
}
# Whether a fix or rebase session since a card's last check changed what the check reads, so cardreview() runs it
# again: the worktree's tree, or, for an Optimize, Rewrite or Split card (no <pk>), the STABILISED lines of its replies
# (stabilised()). Bug: a fix that corrected a STABILISED line alone, its tree unchanged, left the old line for review.
rechecked() { # <worktree> <its tree at the last check> <pk: the Board fix issue's kind, or empty> <the STABILISED lines then>
  [ "$(git -C "$1" write-tree)" != "$2" ] || { [ -z "$3" ] && [ "$(stabilised "$1")" != "$4" ]; }
}
# The target of a speed-up or Optimize card, for its build brief (card()): the file's CPU seconds on record (its median,
# testspart()); its cases, as its runner names them in a
# run of the file alone on the commit the card is built on ($CARDS/mainrun/<card>.cases), with their count and their
# average CPU seconds (no runner reports a case's own CPU seconds to the engine); and what the check passes
# (speedproof()), with test.splitAllowance for each file's start-up. The CPU seconds are the figure the check holds the
# file to (recentcpu(): its recent runs, else its median on record), and what it passes follows the issue's verdict
# (optverdict()).
speedbrief() { # <card> <worktree> <test file> <issue json>
  local mwt=$CARDS/mainrun/$1.cases f=$3 sa before k='' sha rc bw v
  packget test.splitAllowance sa || return 1
  v=$(optverdict "$4" any); before=$(recentcpu "$4" "$f"); bw=${before#*$'\t'}; before=${before%%$'\t'*}
  if sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) && [ "$(git -C "$2" cat-file -t "$sha:$f" 2>/dev/null)" = blob ] \
    && { git worktree remove --force "$mwt"; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt"; } > /dev/null 2>&1 < /dev/null; then
    printf 'fail\t%s\n' "$f" > "$mwt.rerun"; tests "$mwt" test.fileCommand alone; rc=$?
    # The run is of the file alone: every case its runner names is the file's, under whichever file the log puts it (a
    # runner of case files, such as the engine's conveyor/conveyor.test.sh, logs them under its own name).
    k=$(testfails "$mwt.test" "$rc" 2>/dev/null | jq -r '[(.passcases + .okcases)[]?.cases[]?, .files[]?.cases[]?.name | select(. != "")] | unique | length | select(. > 0)' 2>/dev/null)
  fi
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null
  jq -rn --arg f "$f" --argjson a "$sa" --arg c "$before" --arg bw "$bw" --arg k "$k" --arg v "$v" --arg sl "$STABLINE" '
    def r: . * 100 | round / 100;
    ($c | tonumber? // null) as $c | ($k | tonumber? // null) as $k
    | "# The target of this card",
      "The test file \($f) " + (if $c == null then "has no CPU seconds on record."
        elif $bw == "its median on record" then "used \($c) CPU s on record (the median of its runs)."
        else "used \($c) CPU s in its recent runs (the median of those this issue lists)." end),
      (if $k == null then "Its runner named none of its cases in a run of it alone on main'"'"'s code, so their count is not known."
       elif $c == null then "It has \($k) cases."
       else "It has \($k) cases, about \($c / $k | r) CPU s each on average (its runner does not give the CPU seconds of each case)." end),
      "The check passes a split only when every case passes and the files'"'"' CPU seconds summed are at most the CPU seconds above plus a start-up allowance of \($a) CPU s (the pack'"'"'s test.splitAllowance, when it cannot be measured) for each file the split adds.",
      if $v == "any" then "This issue names no verdict: a change that keeps the file whole must make it cost less than the CPU seconds above."
      else "The verdict of this issue is \($v). " + {
        "speed up": "The change keeps the file, adds or removes no other test file, and must make it cost less than the CPU seconds above.",
        keep: "The change keeps the file, adds or removes no other test file, and must make it cost less than the CPU seconds above.",
        stabilise: "The change keeps the file, adds or removes no other test file, removes the cause of each of its flaky or failing cases, and must not make it cost more than the CPU seconds above. End your reply with one line \($sl) for each case the issue names on a CAUSE line (at least one when it names none): a case with no such line blocks the card. The review checks each line against the code.",
        split: "The change splits the file: it changes or removes the file and adds test files.",
        merge: "The change merges the file with another test file: it removes one of the two and changes the other, and adds no test file. When the file stays, it and the test files the change keeps must not cost more, run alone with the change, than they and the test files merged into it cost without it.",
        delete: "The change deletes the file and adds or changes no other test file.",
        indirect: "The change rewrites each proxy part the issue names on a DIRECT line as the direct check it names. It keeps the file and every case those lines name, adds or removes no other test file, and must make the file cost less than the CPU seconds above."}[$v] end'
}
NOCASE=conveyor-no-case
# The start-up allowance of each file a split adds (speedproof()): the CPU seconds of a run of <file>, the first file
# the split adds, with no case selected, printed as `<CPU s><TAB>measured: a run of <file> with no case`. A runner of
# the pack's test.command that the engine knows (testrunner()) is run here, in <worktree>, on <file> alone, with its
# own filter set to a case name no file has (NOCASE), and timed as tools/testtime.sh times a command (the user and
# system time of all it starts): node --test (--test-name-pattern), pytest (-k; its exit 5 is "no case ran"), go test
# (-run, on the package of <file>), cargo test (the test target of <file>, tests/<name>.rs, with a name filter) and
# rspec (-e). Any other command (a project's own script, such as this repository's .conveyor/test-changed.sh, or a
# runner the engine cannot filter) is run with the rerun line `fail<TAB><file><TAB>conveyor-no-case`, and that run is
# used only when the run of the split named a case found in the text of <file> and this run names none: a command
# that ignores the line runs the file whole, and its CPU seconds are not start-up. When no run can be used (a run that
# fails, names a case or gives no CPU seconds), it prints `<the pack's test.splitAllowance><TAB>the pack's
# test.splitAllowance: <why it was not measured>`.
splitstart() { # <worktree> <file> <the pack's test.command> <the pack's test.splitAllowance> <cases the split's run named, one a line>
  local r a=() p rc cpu='' why='' nc
  r=$(testrunner "$3" "$1" 2>/dev/null) || r=''
  case $r in named\ *) r=${r#named }; r=${r% *} ;; *) r=${r#* } ;; esac
  case $r in
    'node --test') a=(node --test "--test-name-pattern=^$NOCASE\$" "$2") ;;
    pytest) p=pytest; [[ $3 =~ (python[0-9.]*[[:space:]]+-m[[:space:]]+)pytest ]] && p="${BASH_REMATCH[1]}pytest"
      read -ra a <<<"$p"; a+=(-q -k "${NOCASE//-/_}" "$2") ;;
    'go test') if [[ $2 == *_test.go ]]; then p=.; [[ $2 != */* ]] || p=./${2%/*}; a=(go test -count=1 -run "^$NOCASE\$" "$p")
      else why="go test runs packages, and $2 is no *_test.go file"; fi ;;
    'cargo test') if [[ $2 =~ ^tests/([^/]+)\.rs$ ]]; then a=(cargo test --test "${BASH_REMATCH[1]}" -- --exact "$NOCASE")
      else why="cargo test runs test targets, and $2 is no tests/<name>.rs file"; fi ;;
    rspec) p=rspec; [[ $3 =~ bundle[[:space:]]+exec[[:space:]]+rspec ]] && p='bundle exec rspec'
      read -ra a <<<"$p"; a+=(-e "$NOCASE" "$2") ;;
  esac
  if [ ${#a[@]} != 0 ]; then
    (cd "$1" && exec timeout --kill-after=10 600 bash "$HERE/tools/testtime.sh" "$2" -- "${a[@]}") > "$1.nocase" 2>&1 < /dev/null; rc=$?
    cpu=$(tail -n 1 "$1.nocase" | sed -n 's/^TESTRUN sec\t[^\t]*\t[^\t]*\t\([0-9.]*\)$/\1/p')
    if [ "$rc" != 0 ] && ! { [ "$r" = pytest ] && [ "$rc" = 5 ]; }; then why="the run of $2 with no case ($r) failed (exit $rc)"; cpu=''
    elif [ -z "$cpu" ]; then why="the run of $2 with no case ($r) gave no CPU seconds"; fi
    rm -f "$1.nocase"
  elif [ -n "$why" ]; then :
  elif [ -z "$5" ] || ! grep -qF -- "$5" "$1/$2" 2>/dev/null; then
    why="the run of the split named no case of $2, so a run of it with no case cannot be told from a run of the whole file"
  else
    printf 'fail\t%s\t%s\n' "$2" "$NOCASE" > "$1.rerun"; tests "$1" test.fileCommand alone; rc=$?
    nc=$(testfails "$1.test" "$rc" 2>/dev/null | jq -r '[(.okcases + .passcases)[]?.cases[]?, .files[]?.cases[]?.name | select(. != "")] | first // empty' 2>/dev/null)
    if [ -n "$nc" ]; then why="the run of $2 with no case ran its case $nc: test.fileCommand runs the file whole"
    elif [ "$rc" != 0 ]; then why="the run of $2 with no case failed (exit $rc)"
    else cpu=$(timed "$1" 2>/dev/null | jq -r --arg f "$2" '.[$f].cpu | numbers' 2>/dev/null)
      [ -n "$cpu" ] || why="the run of $2 with no case gave no CPU seconds"; fi
  fi
  if [ -n "$cpu" ]; then printf '%s\tmeasured: a run of %s with no case\n' "$cpu" "$2"
  else printf "%s\tthe pack's test.splitAllowance: %s\n" "$4" "$why"; fi
}
# The version of this check (speedproof(), optproof()): raised by every change to what it passes. The blocked line of
# a card it fails carries it (speedcheck, card()); once it rises, the loop retries each card an older version blocked
# (speedretry(), lib/run.sh). Lines written before that carry none, and are told by their reasons: version 1's two
# ("the file is not faster: <n> CPU s on record, <n> CPU s now" and "the files of the split are not faster: ..."), and
# version 2's three ("the file is not faster: ...; its budget is ...", "the split does not fit: ..." and "the file is
# over the budget of its own that the build proposes: ..."). Version 4 holds no file to a CPU budget. Version 5
# follows the issue's verdict and holds the file to its recent runs (recentcpu()), not its old median. Version 6 lets
# a file that must be faster pass below the slowest of its recent runs (slowestrun()), inside their spread (#1140).
# Version 7 times a merge into the file: the test files it keeps, changes or removes run without the change (#1573).
# shellcheck disable=SC2034 # read by lib/card.sh and lib/run.sh
SPEEDCHECK=7
# The failures of speedproof()'s run (exit <exit>, read by testfails() from <worktree>.test) of test files other than
# <file run>...: the run also runs the test files the change selects (a Board test file's links,
# .conveyor/test-links.json), and a failure of one of them is not the run's own file's (#602). Prints them, each file
# with its failing cases and each case's first line. A file the main-red record holds red (mainred.sh redlisted(): the file, or
# `<file>: <case>`) is named as main's failure; so is one that fails the same way on the commit the card was built on
# (its HEAD): the change is taken out of the worktree again and the other files the record does not hold run alone
# there, a file being main's when each of its failing cases fails there too (a file with no case named: when it fails
# there). Prints nothing when no other file failed. Fails (1) when another file failed and none of <file run>... did.
speedothers() { # <worktree> <exit> <file run>...
  local t o cmd='' x f u=() m main=() base=() b='' brc
  packget test.command cmd 2>/dev/null || cmd=''
  t=$(testfails "$1.test" "$2" 2>/dev/null | jq -ce objects) || return 0
  # A failure under no file, or under the test command (a run that wrote no log), names no other file.
  o=$(jq -c --arg cmd "$cmd" '[.files[]?, (.timeout.file // empty | {file: ., cases: []})] | unique_by(.file)
    | map(select(.file != "" and .file != $cmd and (.file | IN($ARGS.positional[]) | not)))' --args "${@:3}" <<<"$t") || return 0
  [ "$o" != '[]' ] || return 0
  while IFS= read -r f; do
    mapfile -t u < <(jq -r --arg f "$f" '.[] | select(.file == $f) | $f, (.cases[]?.name | "\($f): \(.)")' <<<"$o")
    if redlisted "${u[@]}"; then main+=("$f"); else base+=("$f"); fi
  done < <(jq -r '.[].file' <<<"$o")
  if [ ${#base[@]} -gt 0 ] && git -C "$1" diff --cached --binary --no-renames HEAD | git -C "$1" apply -R --index > /dev/null 2>&1; then
    printf 'fail\t%s\n' "${base[@]}" > "$1.rerun"; tests "$1" test.fileCommand alone > /dev/null 2>&1; brc=$?
    [ "$brc" = 0 ] || b=$(testfails "$1.test" "$brc" 2>/dev/null | jq -ce objects) || b=''
  fi
  x=''
  while IFS= read -r f; do
    m=''
    if printf '%s\n' "${main[@]}" | grep -qxF -- "$f"; then m=" (main's failure, not the change's: the main-red record holds it)"
    elif [ -n "$b" ] && jq -e --arg f "$f" --argjson o "$o" '[.files[]? | select(.file == $f)] as $bf | [$bf[].cases[]?.name] as $bc
      | [$o[] | select(.file == $f) | .cases[]?.name] | if . == [] then $bf != [] else all(.[]; IN($bc[])) end' <<<"$b" > /dev/null 2>&1; then
      m=" (main's failure, not the change's: it fails on the commit the card was built on too)"
    fi
    x+=${x:+; }$(jq -r --arg f "$f" --arg m "$m" '.[] | select(.file == $f)
      | "\($f) fails\($m)" + (.cases | if . == [] then "" else ", " + (map("case `\(.name)`: \(.line)") | join(", ")) end)' <<<"$o")
  done < <(jq -r '.[].file' <<<"$o")
  printf '%s\n' "$x"
  jq -e '[.files[]?.file, .timeout.file?] | any(.[]; IN($ARGS.positional[]))' --args "${@:3}" <<<"$t" > /dev/null
}
# The check of a speed-up card (card(): a bug card whose issue speedfile() names a test file), in place of the bug-card
# check (bugproof.sh bugproof()): a speed-up keeps what the file tests, so its tests pass on main's code by design. The file runs
# alone, on a test slot, through the pack's test.fileCommand, in a worktree of the commit the card was built on with the whole
# staged change ($CARDS/mainrun/<card>.speed). It must pass, and its CPU seconds there (its runner's `TESTRUN sec` line,
# testlist.sh timed()) must be lower than the figure recentcpu() gives: the median of the recent runs its issue lists, else its
# median on record, or, when the issue lists recent runs, lower than the slowest of them (slowestrun(): inside their
# spread). Under the verdict stabilise (optverdict()) they must be at most that figure, and the build's reply
# must name the cause of each flaky case and how the change removes it (stabilised()), checked before the run; the
# review is shown those lines to check against the code. Under the verdict merge, a change that removes test files (merged
# into the file) runs, with the file, each test file it keeps, and they must take at most what they and those it removes took without it.
# Writes the result in
# <worktree>.unfixed, which the review is shown, its first line the reason when the check does not hold, and records a
# bugproof line (result ok or fail) with speed: {file, before: that figure, after: the CPU seconds now; each null when
# not known; fix: sped up, or split, with into: the test files the split adds}. Fails when the check does not hold: no figure, a stabilise reply that names no cause, a run that could not be made, failed or gave no
# CPU seconds, or CPU seconds not lower than the figure nor the slowest recent run (above the figure, for stabilise and merge). Given the test files a split adds (optproof()), it runs them
# too, with the file when the change keeps it: they must all pass, and their CPU
# seconds summed (after) must be at most that figure plus a start-up allowance for each file the split adds. The
# allowance (splitstart()) is measured only when the sum is over the figure. The reason names a sum over its limit
# with the allowance and where it came from: the file it was measured on, or the pack's value and why it was not
# measured.
speedproof() { # <card> <worktree> <issue json> <test file> [<test file the change adds>...]
  local mwt=$CARDS/mainrun/$1.speed f=$4 out='' rc='' sha before after='' why='' run=() l sa='' cpus='[]' over='' al='' alf='' lim='' tl='' cs='' cmd oth own v bw miss='' top='' mrg=() gone=() mi=() mb='' mbt='' ml='' who
  rm -f "$2.unfixed"
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || return 0
  v=$(optverdict "$3"); before=$(recentcpu "$3" "$f"); bw=${before#*$'\t'}; before=${before%%$'\t'*}
  # A stabilise card's reply names the cause of each flaky case and how the change removes it (stabilised()).
  [ "$v" != stabilise ] || miss=$(stabilised "$2" "$3")
  # A merge into the file (the change removes test files) is timed, not read from records (#1573): without the change the
  # file, each other test file the change changes and each it removes run alone (mrg, mergecpu()); with it, those it keeps.
  if [ "$v" = merge ] && [ $# = 4 ]; then
    mapfile -t gone < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=D HEAD 2>/dev/null | testpaths | grep -vxF -- "$f")
    mapfile -t mi < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=M HEAD 2>/dev/null | testpaths | grep -vxF -- "$f")
    [ ${#gone[@]} = 0 ] || { mrg=("$f" "${mi[@]}" "${gone[@]}"); ml=$(printf '%s, ' "${mrg[@]}"); ml=${ml%, }; before=''; bw="what $ml took run alone on main's code without the change, summed"; }
  fi
  if ! packget test.splitAllowance sa; then why="the pack could not be read for the split allowance of $f"
  elif [ -z "$before" ] && [ ${#mrg[@]} = 0 ]; then why="the file $f has no CPU seconds on record to compare with"
  elif [ "$miss" = - ]; then why="the verdict is stabilise, and the build's reply names no cause of the file's failures: it ends with a line $STABLINE for each case it fixes"
  elif [ -n "$miss" ]; then why="the verdict is stabilise, and the build's reply names no cause for the flaky $([ "$(wc -l <<<"$miss")" = 1 ] && echo case || echo cases) $(paste -sd, <<<"$miss" | sed 's/,/, /g'): it ends with a line $STABLINE for each"
  elif sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt"; } 2>&1 < /dev/null) && { [ ${#mrg[@]} = 0 ] || mb=$(mergecpu "$mwt" "${mrg[@]}") || { mb=fail; mbt=$(tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000'); }; } \
    && out=$({ git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index; } 2>&1 < /dev/null); then
    # A split whose change removes the file runs the files it adds alone; a merge into the file, the test files it keeps.
    [ $# -gt 4 ] && [ ! -e "$mwt/$f" ] || run=("$f"); run+=("${@:5}"); [ ${#mrg[@]} = 0 ] || { run+=("${mi[@]}"); [ "$mb" = fail ] || before=$mb; }
    l=$(printf '%s, ' "${run[@]}"); l=${l%, }; who="the file $f"; [ ${#run[@]} = 1 ] || who="the files $l"
    printf 'fail\t%s\n' "${run[@]}" > "$mwt.rerun"; tests "$mwt" test.fileCommand alone; rc=$?
    tl=$(tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000')
    # Each file run, with its CPU seconds.
    cpus=$(timed "$mwt" 2>/dev/null | jq -c '. as $t | [$ARGS.positional[] | {file: ., cpu: $t[.].cpu?}]' --args "${run[@]}" 2>/dev/null) || cpus='[]'
    after=$(jq -r 'map(.cpu) | if length > 0 and all(.[]; type == "number") then add | . * 1000 | round / 1000 else empty end' <<<"$cpus" 2>/dev/null)
    # A failure of another test file the run selected is named as that file's, not the run's own files' (#602).
    oth=''; own=0; [ "$rc" = 0 ] || { oth=$(speedothers "$mwt" "$rc" "${run[@]}"); own=$?; }
    if [ "$rc" != 0 ] && [ "$own" != 0 ]; then
      if [ $# = 4 ]; then why="$who does not fail with the change, but another test file the change selects does (exit $rc): $oth"
      else why="the files of the split, $l, do not fail with the change, but another test file the change selects does (exit $rc): $oth"; fi
    elif [ $# = 4 ]; then
      if [ "$rc" != 0 ]; then why="$who fails with the change (exit $rc)${oth:+; another test file the change selects fails too: $oth}"
      elif [ -z "$after" ]; then why="the run of $who with the change gave no CPU seconds"
      elif [ ${#mrg[@]} != 0 ] && [ -z "$before" ]; then why="the test files of the merge, $ml, $([ "$mb" = fail ] && echo fail || echo gave no CPU seconds) run alone on main's code at $sha without the change"
        # A failure without the change shows that run's output, not the passing run's with it.
        [ "$mb" != fail ] || tl=$mbt
      elif [ ${#mrg[@]} != 0 ]; then jq -en --argjson a "$after" --argjson b "$before" '$a <= $b' >/dev/null 2>&1 \
        || why="the merge costs more than the files apart: $l take $after CPU s with the change, over the $before CPU s that $ml took without it, run alone on main's code at $sha"
      # A stabilise or merge card may leave the file as dear as its figure; any other must make it cheaper, or cost less
      # than the slowest of the recent runs its issue lists (top, kept only then): one run varies that much (#1140).
      elif [ "$v" = stabilise ] || [ "$v" = merge ]; then jq -en --argjson a "$after" --argjson b "$before" '$a <= $b' >/dev/null 2>&1 \
        || why="the file is dearer than $bw ($before CPU s), which the verdict $v does not allow: $after CPU s now"
      elif top=$(slowestrun "$3"); jq -en --argjson a "$after" --argjson b "$before" '$a < $b' >/dev/null 2>&1; then top=''
      elif [ -z "$top" ] || ! jq -en --argjson a "$after" --argjson t "$top" '$a < $t' >/dev/null 2>&1; then
        why="the file is not faster than $bw ($before CPU s), as the verdict $v asks: $after CPU s now"; fi
    elif [ "$rc" != 0 ]; then why="the files of the split, $l, fail with the change (exit $rc)${oth:+; another test file the change selects fails too: $oth}"
    elif [ -z "$after" ]; then why="the run of the files of the split, $l, with the change gave no CPU seconds for each"
    else
      # The start-up allowance is measured only when the sum needs it (splitstart()).
      if ! jq -en --argjson a "$after" --argjson b "$before" '$a <= $b' >/dev/null 2>&1; then
        cs=$(testfails "$mwt.test" "$rc" 2>/dev/null | jq -r '(.okcases + .passcases)[]?.cases[]?, .files[]?.cases[]?.name | select(. != "")' 2>/dev/null)
        packget test.command cmd 2>/dev/null || cmd=''
        al=$(splitstart "$mwt" "$5" "$cmd" "$sa" "$cs" | tail -n 1); alf=${al#*$'\t'}; al=${al%%$'\t'*}
        lim=$(jq -n --argjson b "$before" --argjson a "$al" --argjson k "$(($# - 4))" '$b + $a * $k | . * 1000 | round / 1000')
        jq -en --argjson s "$after" --argjson m "$lim" '$s <= $m' >/dev/null 2>&1 \
          || over="the files take $after CPU s summed, $(jq -n --argjson s "$after" --argjson m "$lim" '$s - $m | . * 1000 | round / 1000') over the $lim CPU s a split of $f may take: $before CPU s $([ "$bw" = 'its median on record' ] && echo on record || echo in its recent runs) plus a start-up allowance of $al CPU s ($alf) for each of the $(($# - 4)) files it adds"
      fi
      [ -z "$over" ] || why="the split does not fit: $over"
    fi
  else why="the file $f could not be run with the change: ${out:0:300}"; fi
  { if [ -n "$why" ]; then printf '%s\n' "$why"
    elif [ $# = 4 ]; then
      printf 'This issue %s the test file %s (its verdict: %s), so no test must fail on main'"'"'s code. Run alone with the change, on a test slot, %s passed in %s CPU s, %s %s, %s CPU s%s.\n' \
        "$(case $v in stabilise) echo stabilises ;; 'speed up') echo speeds up ;; *) echo optimizes ;; esac)" "$f" "$v" "$([ ${#run[@]} = 1 ] && echo it || echo "$l")" "$after" \
        "$(if [ "$v" = stabilise ] || [ "$v" = merge ]; then echo not more than; elif [ -n "$top" ]; then echo not lower than; else echo lower than; fi)" "$bw" "$before" \
        "${top:+, but lower than the slowest of those runs, $top CPU s: inside their spread}"
    else printf 'This change splits the test file %s, so no test must fail on main'"'"'s code. Run alone with the change, on a test slot, %s passed in %s CPU s summed (%s of %s is %s CPU s): %s.\n' "$f" "$l" "$after" \
      "$([ "$bw" = 'its median on record' ] && echo the median on record || echo the median of the recent runs)" "$f" "$before" "$(jq -r 'map("\(.file) \(.cpu) CPU s") | join(", ")' <<<"$cpus")"; fi
    # The review checks each cause a stabilise card's reply names against the code.
    [ -n "$why" ] || [ "$v" != stabilise ] || { echo 'The card'"'"'s replies (its build'"'"'s, or a later fix'"'"'s that names the case again) name these causes of the file'"'"'s failures, each with how the change removes it (case | cause | how). Check each against the code: a cause the change does not remove, or a case whose cause it does not name, is a finding.'
      stabilised "$2" | sed 's/^/- /'; }
    [ -z "$rc" ] || { echo 'The end of that run'"'"'s output:'; echo '```'; printf '%s\n' "$tl"; echo '```'; }; } > "$2.unfixed"
  record "$1" "$(jq -r '.number // 0' <<<"$3")" bugproof "$(if [ -z "$why" ]; then echo ok; else echo fail; fi)" \
    "$(jq -cn --arg r "$why" --arg f "$f" --arg b "$before" --arg a "$after" '{reason: $r, speed: {file: $f, before: ($b | tonumber? // null), after: ($a | tonumber? // null),
      fix: (if $ARGS.positional == [] then "sped up" else "split" end), into: $ARGS.positional}}' --args "${@:5}")"
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  [ -z "$why" ]
}
# The check of an Optimize card (card(): a bug card whose issue speedfile() names with OPTIMIZE, REWRITE or SPLIT), in place of the
# bug-card check: the card speeds its test file up, splits it, merges it into another test file or deletes it, and
# keeps what it tests, so no test must fail on main's code. A change that keeps the file, or adds test files (a split),
# is checked as a speed-up (speedproof(), given the test files it adds). A change that removes the file and adds no
# test file (a delete, or a merge into a file main has) is not run as a speed-up: the file runs alone on the commit the card was built
# on, as it is there, and the review is told the cases its runner named (testfails()) and asked to name, for each, the
# test that still covers it, on a COVERED-BY line (the Tests page's, testspart(), for a delete). The test files a merge
# modifies (into) run alone there without the change and with it (mergecpu(), lib/testlist.sh): they must pass both
# times, and with it take at most what they took without it plus the file's figure (recentcpu()), else the check fails
# naming why. Its bugproof line has speed: {file, before: the figure (a merge's: that limit) or null, after: null (a
# merge's: into's CPU s with the change), fix: deleted (into: []) or merged, into}. First, the change must take the shape
# its issue's verdict asks (optverdict()); one that does not fails, with the reason in <worktree>.unfixed and a bugproof
# line with result fail. Returns as speedproof() does.
optproof() { # <card> <worktree> <issue json> <test file>
  local mwt=$CARDS/mainrun/$1.speed f=$4 sha='' out='' rc='' before bw cs='' add=() into=() gone=() v why='' fix mb='' ma='' lim=''
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || { rm -f "$2.unfixed"; return 0; }
  mapfile -t add < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=A HEAD 2>/dev/null | testpaths \
    | while IFS= read -r x; do [[ $x != "$f" ]] && printf '%s\n' "$x"; done)
  mapfile -t into < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=M HEAD 2>/dev/null | testpaths)
  mapfile -t gone < <(git -C "$2" diff --cached --name-only --no-renames --diff-filter=D HEAD 2>/dev/null | testpaths)
  # The change does what the issue's verdict asks (optverdict()): a split changes or removes the file and adds test
  # files; a delete removes the file and adds or changes no other test file; a merge removes the file and changes
  # another test file, or changes the file and removes another, and adds none; speed up, keep, stabilise and indirect
  # keep the file and add or remove none. An issue that names no verdict may take any of these shapes.
  v=$(optverdict "$3" any)
  case $v in
    split) if [ ${#add[@]} = 0 ]; then why="the verdict is split, and the change adds no test file"
      elif ! printf '%s\n' "${into[@]}" "${gone[@]}" | grep -qxF -- "$f"; then why="the verdict is split, and the change does not change the test file $f"; fi ;;
    delete) if [ -e "$2/$f" ]; then why="the verdict is delete, and the change keeps the test file $f"
      elif [ ${#add[@]} != 0 ]; then why="the verdict is delete, and the change adds test files: ${add[*]}"
      elif [ ${#into[@]} != 0 ]; then why="the verdict is delete, and the change also changes test files, as a merge does: ${into[*]}"; fi ;;
    merge) if [ ${#add[@]} != 0 ]; then why="the verdict is merge, and the change adds test files: ${add[*]}"
      elif [ -e "$2/$f" ]; then
        printf '%s\n' "${into[@]}" | grep -qxF -- "$f" && [ ${#gone[@]} != 0 ] \
          || why="the verdict is merge, and the change neither removes the test file $f nor merges another test file into it"
      elif [ ${#into[@]} = 0 ]; then why="the verdict is merge, and the change removes the test file $f without changing another test file"; fi ;;
    'speed up' | keep | stabilise) if [ ! -e "$2/$f" ]; then why="the verdict is $v, and the change removes the test file $f"
      elif [ ${#add[@]} != 0 ]; then why="the verdict is $v, and the change adds test files: ${add[*]}"
      elif [ ${#gone[@]} != 0 ]; then why="the verdict is $v, and the change removes test files, as a merge does: ${gone[*]}"; fi ;;
    # indirect (#778): as speed up, and the file still holds each case the issue's DIRECT lines name (directcases(),
    # casesgone()): a rewrite as direct checks loses no case that must keep passing.
    indirect) if [ ! -e "$2/$f" ]; then why="the verdict is $v, and the change removes the test file $f"
      elif [ ${#add[@]} != 0 ]; then why="the verdict is $v, and the change adds test files: ${add[*]}"
      elif [ ${#gone[@]} != 0 ]; then why="the verdict is $v, and the change removes test files, as a merge does: ${gone[*]}"
      else
        cs=$(casesgone "$2" "$f" "$(directcases "$1" "$2" "$3" "$f")")
        [ -z "$cs" ] || why="the verdict is $v, and the change drops cases of $f that the issue's DIRECT lines say must keep passing: $(paste -sd, <<<"$cs" | sed 's/,/, /g')"
      fi ;;
  esac
  if [ -n "$why" ]; then
    printf '%s\n' "$why" > "$2.unfixed"
    if [ ${#add[@]} != 0 ]; then fix='split'; elif [ -e "$2/$f" ]; then fix='sped up'; elif [ ${#into[@]} != 0 ]; then fix='merged'; else fix='deleted'; fi
    [ "$fix" = split ] || [ "$fix" = merged ] || into=(); [ "$fix" != split ] || into=("${add[@]}")
    record "$1" "$(jq -r '.number // 0' <<<"$3")" bugproof fail "$(jq -cn --arg r "$why" --arg f "$f" --arg x "$fix" '{reason: $r, speed: {file: $f, before: null, after: null,
      fix: $x, into: $ARGS.positional}}' --args "${into[@]}")"
    return 1
  fi
  if [ -e "$2/$f" ] || [ ${#add[@]} != 0 ]; then speedproof "$@" "${add[@]}"; return; fi
  rm -f "$2.unfixed"
  before=$(recentcpu "$3" "$f"); bw=${before#*$'\t'}; before=${before%%$'\t'*}
  if sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt"; } 2>&1 < /dev/null); then
    # The run is of the file alone: every case its runner names is the file's.
    printf 'fail\t%s\n' "$f" > "$mwt.rerun"; tests "$mwt" test.fileCommand alone; rc=$?
    cs=$(testfails "$mwt.test" "$rc" 2>/dev/null | jq -r '[(.passcases + .okcases)[]?.cases[]?, .files[]?.cases[]?.name | select(. != "")] | unique[]' 2>/dev/null)
    if [ ${#into[@]} != 0 ]; then # a merge
      mb=$(mergecpu "$mwt" "${into[@]}") || mb=fail
      ! git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index > /dev/null 2>&1 || ma=$(mergecpu "$mwt" "${into[@]}") || ma=fail
    fi
  fi
  # They must pass, and cost with the change at most what they cost without it plus the removed file's figure.
  if [ ${#into[@]} = 0 ]; then :
  elif [ "$ma" = fail ] || [ "$mb" = fail ]; then why="the test files $f is merged into, ${into[*]}, fail $([ "$ma" = fail ] && echo with || echo without) the change, run alone on main's code at $sha"
  elif [ -z "$before" ]; then why="the test file $f has no CPU seconds on record to compare the files it is merged into with"
  elif [ -z "$mb" ] || [ -z "$ma" ]; then why="the test files $f is merged into, ${into[*]}, gave no CPU seconds run alone on main's code without the change and with it"
  else lim=$(jq -n --argjson a "$before" --argjson b "$mb" '$a + $b | . * 1000 | round / 1000')
    jq -en --argjson a "$ma" --argjson m "$lim" '$a <= $m' >/dev/null 2>&1 \
      || why="the merge costs more than the files apart: ${into[*]} take $ma CPU s with the change, over the $lim CPU s they may take: $mb CPU s without it plus $before CPU s of $f ($bw)"
  fi
  if [ -n "$why" ]; then printf '%s\n' "$why" > "$2.unfixed"
  else { printf 'This change removes the test file %s and adds no test file: it deletes the file, or merges it into another test file. No test must fail on main'"'"'s code for it, and the file it removes was not run with the change.\n' "$f"
    if [ -n "$cs" ]; then printf 'The cases %s held, as its runner named them in a run of it alone on main'"'"'s code at %s:\n' "$f" "$sha"; sed 's/^/- /' <<<"$cs"
    elif [ -n "$rc" ]; then printf 'Its runner named no case of it in a run of it alone on main'"'"'s code at %s (exit %s): read the file there for its cases.\n' "$sha" "$rc"
    else printf 'It could not be run alone on main'"'"'s code (%s): read the file there for its cases.\n' "${out:0:300}"; fi
    [ -z "$lim" ] || printf 'The test files it is merged into, %s, run alone, take %s CPU s with the change: not more than the %s CPU s they took without it plus the %s CPU s of %s (%s).\n' \
      "${into[*]}" "$ma" "$mb" "$before" "$f" "$bw"
    echo 'Name, for each of its cases, the test that still covers it after the change, each on its own line, exactly: `COVERED-BY: <its test file>: <its case>`. A case with no test named is a finding.'; } > "$2.unfixed"; fi
  record "$1" "$(jq -r '.number // 0' <<<"$3")" bugproof "$([ -z "$why" ] && echo ok || echo fail)" "$(jq -cn --arg r "$why" --arg f "$f" --arg b "${lim:-$before}" --arg a "$ma" '{reason: $r, speed: {file: $f,
    before: ($b | tonumber? // null), after: ($a | tonumber? // null), fix: (if $ARGS.positional == [] then "deleted" else "merged" end), into: $ARGS.positional}}' --args "${into[@]}")"
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  [ -z "$why" ]
}
# The check of a Fix failures card (#188; card(): a bug card whose issue speedfile() names with FIXFAILS, as the
# Board's Fix failures files it), in place of the bug-card check: the card makes its test file pass reliably and keeps
# what it tests, so no test must fail on main's code. The file runs alone STEADYRUNS times in a row, each run on a
# test slot, on the commit the card was built on with its staged change ($CARDS/mainrun/<card>.steady). Every run must
# pass; the reason it does not names the run that failed, its exit, the cases its runner named and the end of its
# output. A change that removes the file does not hold. Writes the result in <worktree>.unfixed, which the review is
# shown, its first line the reason when the check does not hold (card() blocks the card with it). Fails when the
# check does not hold.
# Given a ratio, it is the check of a Fix the waiting card (#189; WAITFIX): the file runs WAITRUNS times in a row, and
# each run must also take at most that many seconds on the clock for each of its CPU seconds (its runner's `TESTRUN
# sec` line, testlist.sh timed()); the reason a run does not names it with its clock and CPU seconds.
# shellcheck disable=SC2034 # FIXFAILS, WAITFIX and WAITRATIO are used in lib/card.sh
FIXFAILS='Fix the failures of the test file ' STEADYRUNS=10 WAITFIX='Fix the waiting of the test file ' WAITRUNS=3 WAITRATIO=2
steadyproof() { # <card> <worktree> <test file> [<the most clock seconds a run may take for each CPU second>]
  local mwt=$CARDS/mainrun/$1.steady f=$3 lim=${4:-} n=$STEADYRUNS what='Fix failures' sha out='' rc=0 i=0 bad='' why='' cs tl='' ls t s c figs=''
  [ -z "$lim" ] || { n=$WAITRUNS; what='Fix the waiting'; }
  rm -f "$2.unfixed"
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || return 0
  if [ ! -e "$2/$f" ]; then why="the change removes the test file $f: a $what card keeps it and what it tests"
  elif sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt" \
      && git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index; } 2>&1 < /dev/null); then
    # Alone: its list names every other test file of the commit as passed, as a run of one file alone does (tests()),
    # so a command that selects the change's tests (as this project's does) runs none of them.
    ls=$(git -C "$mwt" -c core.quotePath=false ls-files 2>/dev/null | testpaths | grep -vxF -- "$f" | awk '{ print "pass\t" $0 }')
    while [ -z "$bad" ] && [ "$i" -lt "$n" ]; do
      i=$((i + 1))
      { [ -z "$ls" ] || printf '%s\n' "$ls"; printf 'fail\t%s\n' "$f"; } > "$mwt.rerun"; rm -f "$mwt.oldtimes" "$mwt.times"; tests "$mwt" test.fileCommand alone; rc=$?
      if [ "$rc" != 0 ]; then bad=$i
      elif [ -n "$lim" ]; then
        t=$(timed "$mwt" 2>/dev/null | jq -r --arg f "$f" '.[$f] // {} | "\(.sec // "")\t\(.cpu // "")"' 2>/dev/null); s=${t%%$'\t'*} c=${t#*$'\t'}
        if [ -z "$s" ] || [ -z "$c" ]; then bad=$i why="the test file $f gave no clock and CPU seconds in run $i of $n with the change, alone on a test slot: its runner prints no TESTRUN sec line for it"
        elif ! jq -en --argjson s "$s" --argjson c "$c" --argjson l "$lim" '$s <= $c * $l' >/dev/null 2>&1; then
          bad=$i why="the test file $f still waits: in run $i of $n with the change, alone on a test slot, it took $s s on the clock for $c CPU s, more than $lim times its CPU time"
        else figs+="${figs:+, }$s s for $c CPU s"; fi
      fi
    done
    if [ -n "$bad" ]; then
      tl=$(tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000')
      [ -n "$why" ] || { cs=$(testfails "$mwt.test" "$rc" 2>/dev/null | jq -r '[.files[]?.cases[]?.name | select(. != "")] | unique | join(", ")' 2>/dev/null)
        why="the test file $f failed in run $bad of $n with the change, alone on a test slot (exit $rc)${cs:+: its failing cases: $cs}"; }
    fi
  else why="the test file $f could not be run with the change: ${out:0:300}"; fi
  { if [ -n "$why" ]; then printf '%s\n' "$why"
    elif [ -n "$lim" ]; then printf 'This issue makes the test file %s wait less. Run alone with the change, on a test slot, it passed in each of %s runs in a row, each at most %s times its CPU seconds on the clock: %s.\n' "$f" "$n" "$lim" "$figs"
    else printf 'This issue makes the test file %s pass reliably. Run alone with the change, on a test slot, it passed in each of %s runs in a row.\n' "$f" "$n"; fi
    [ -z "$tl" ] || { echo 'The end of the output of the run that failed:'; echo '```'; printf '%s\n' "$tl"; echo '```'; }; } > "$2.unfixed"
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  [ -z "$why" ]
}
# The Board's other fix issues about one test file (#189), each a bug card that card() checks in place of the
# bug-card check, its file named by its title's start (speedfile()): Fix hollow cases (HOLLOWFIX, hollowproof()),
# Fix the waiting (WAITFIX, steadyproof() with WAITRATIO), Make it run (MAKERUN, its title "Make the test file <file>
# run": runproof(), and ranproof() after its test step) and Delete it (DELFILE, deleteproof()).
# shellcheck disable=SC2034 # used in lib/card.sh
HOLLOWFIX='Fix the hollow cases of the test file ' MAKERUN='Make the test file ' DELFILE='Delete the test file '
# The check of a Fix hollow cases card: each case the issue names on its HOLLOW lines (as the Board's Fix hollow cases
# writes them, tatagged() of lib/testaction.sh) now asserts the behaviour it names, or is deleted. A case is deleted
# when the change removes the file, or its name is no longer in the file. Each deleted case needs a line of the
# build's reply (<worktree>.out: its text, the session's last reply) `COVERED-BY: <test file>: <its case> | <the deleted
# case>`, naming a test file the change keeps. The lines are kept in <worktree>.covered, so a check again after a fix
# session (fixproof()) reads the build's lines with those of the fix's reply. A file the change keeps is read by the judge's hollow check
# (TAHOLLOWASK, the judge's own words): one read-only session in the card's worktree (judgecall(), lib/review.sh) on
# the seat hollowseat() names, whose answer ends with HOLLOWDONE. The card holds when it names no hollow case the issue
# names or the change added or changed; each other hollow case it names goes to the declined list (declined()). Writes
# the result in <worktree>.unfixed, the reason first when it does not hold (each case still found hollow, or each
# deleted case with no COVERED-BY line), and fails then.
HOLLOWDONE='HOLLOW-CHECK: done'
# The rows hollowproof() reads a test file by (after TESTEDIT_TABLE): the rows of the test edits' table, its case
# reader (a Go file read as JavaScript is), each with the lines that are a note and not code (note: blank or a
# comment) and the line that closes a case (close: a line that ends in a closing bracket, at most as far in as its start line, and that does not start
# inside a string, a heredoc or a comment; null for Python, whose case ends before the next line of code, not a comment
# nor in a triple-quoted string, at most as far in as its start line); row($f) is the row of file $f, or null. plain
# drops the escapes of a line (name\'s to name's), so a case title is read as it shows. ind is how far in a line is;
# tq is the triple quotes in a line. shin and jsin read an array of lines of shell or JavaScript and give, for each, true
# when it starts inside text: a quoted string or a heredoc (shell), or a template string, a block comment or a code part
# ${...} of a template (JavaScript; a ' or " string ends with its line). A regular expression is read as code. shin
# gives true also for a shell line that cannot close a case: one with a comment, one that ends inside text, and one
# whose last bracket of code closes a bracket or a $( opened on that line or inside a $( (x=$(f), a() { :; }, [ -s f ]).
HOLLOW_JQ='def cases: [table[] | any(.ext[]; . == "py") as $py
    | . + {note: (if any(.ext[]; . == "sh") or $py then "^\\s*(#|$)" else "^\\s*(//|/\\*|\\*(\\s|/|$)|$)" end),
      close: (if $py then null else "[)\\]}]\\s*;?\\s*$" end), sh: any(.ext[]; . == "sh")}];
  def row($f): (($f | capture("\\.(?<x>[^./]+)$").x | ascii_downcase) // "") as $x | first(cases[] | select(any(.ext[]; . == $x))) // null;
  def shopen: "^.*?\\(\\s*\\)\\s*[{(]|^\\s*@test\\s+(\"(\\\\.|[^\"])*\"|\\S+)\\s*\\{";
  def shstart: . as $l | (first(match(shopen)) // null) as $m | ($m.string // "" | .[-1:]) as $o | (reduce range(0; length) as $i ({q: null, e: false, d: 0, one: false, at: null};
      $l[$i:$i + 1] as $c | if .at != null then . elif .e then .e = false
          elif .q == "\u0027" then (if $c == "\u0027" then .q = null else . end)
          elif $c == "\\" then .e = true elif .q == "\"" then (if $c == "\"" then .q = null else . end)
          elif $c == "\u0027" or $c == "\"" then .q = $c
          elif $c == "#" and $i > 0 and ($l[$i - 1:$i] | test("\\s")) then .at = $i elif $m == null or $i < $m.length or .one then . elif $c == $o then .d += 1
          elif $c == ({"{": "}", "(": ")"}[$o]) then (if .d == 0 then .one = true else .d -= 1 end) else . end)) as $r
    | {text: (if $r.at == null then $l else $l[:$r.at] | sub("\\s+$"; "") end), one: $r.one};
  def plain: gsub("\\\\(?<c>.)"; .c);
  def ind: match("^\\s*").length;
  def tq: [scan("\"\"\"|\u0027\u0027\u0027")] | length;
  def shin: foreach .[] as $l ({s: [], h: null, t: false, in: false};
      if .h then .in = true | if (if .t then $l | sub("^\t+"; "") else $l end) == .h then .h = null else . end
      else .in = (.s | length > 0) | .p = null | .x = false | .d = 0 | .c = true
        | reduce ($l | [scan("\\\\.|\\$\\(|\\$\u0027|\u0027|\"|[(){}\\[\\]]|<<<|<<-?\\s*[\"\u0027]?[A-Za-z_][A-Za-z0-9_]*[\"\u0027]?|(?<!\\S)#")][]) as $k (.; .s[-1] as $top
          | if .x then .
            elif $top == "\u0027" then (if $k | endswith("\u0027") then .s |= .[:-1] else . end)
            elif $top == "$\u0027" then (if $k == "\u0027" or $k == "$\u0027" then .s |= .[:-1] else . end)
            elif $top == "\"" then (if $k == "\"" then .s |= .[:-1] elif $k == "$(" then .s += [$k] else . end)
            elif $k == "#" then .x = true
            elif $k == "\u0027" or $k == "$\u0027" or $k == "\"" or $k == "$(" then .s += [$k]
            elif $k == "(" and $top then .s += [$k]
            elif $k == ")" and $top then .s |= .[:-1] | .c = false
            elif $k | IN("(", "{", "[") then .d += 1
            elif $k | IN(")", "}", "]") then (if .d > 0 then .d -= 1 | .c = false else .c = true end)
            elif ($k | startswith("<<<")) or ($k | startswith("\\")) or .p then .
            else .p = ($k | sub("^<<-?\\s*[\"\u0027]?"; "") | sub("[\"\u0027]$"; "")) | .t = ($k | startswith("<<-")) end)
        | .h = .p end; .in or .x or (.c | not) or (.s | length > 0));
  def jsin: foreach .[] as $l ({s: [], in: false};
      .in = (.s | length > 0) | .x = false
      | reduce ($l | [scan("\\\\.|`|\u0027|\"|//|/\\*|\\*/|\\$\\{|[{}]")][]) as $k (.; .s[-1] as $top
          | if .x then .
            elif $top == "/*" then (if $k == "*/" then .s |= .[:-1] else . end)
            elif $top == "\u0027" or $top == "\"" then (if $k == $top then .s |= .[:-1] else . end)
            elif $top == "`" then (if $k == "`" then .s |= .[:-1] elif $k == "${" then .s += ["${"] else . end)
            elif $k == "//" then .x = true
            elif $k == "/*" or $k == "`" or $k == "\u0027" or $k == "\"" then .s += [$k]
            elif $top == null then .
            elif $k == "{" or $k == "${" then .s += ["{"]
            elif $k == "}" then .s |= .[:-1]
            else . end)
      | .s |= until(length == 0 or (.[-1] | . != "\u0027" and . != "\""); .[:-1]); .in);'
# The lines of a test file that start a case (hollowproof(), optproof()), by HOLLOW_JQ: "row", then each start line
# with its line number and the number of the case's last line first (<n><tab><e><tab><line>), each plain; "none" for
# a language with no row, as a line of it is not a case. A case ends at its close
# line (the row's close; for Python the line before the next line of code at most as far in as its start line), and
# at the latest on the line before the next start line, so the code between two cases (a table of values set up for
# a later case) is in no case (#606). A line of fixture text in a case (a JSON record in a heredoc, the end of a
# template string, a comment or a docstring at the left edge) does not end it, as it starts inside text (shin, jsin,
# tq); brackets are not counted across lines, as one in a regular expression or a case pattern closes nothing. In
# shell a comment or a line of code whose last bracket closes one it opened (shin) does not end it either (#612),
# and a shell case ends on its start line when the bracket that closes its opener (shopen) is on it, after a trailing
# comment is dropped (shstart: from a "#" after a blank outside quotes): t_x() { f; } # it's a note, or t_x() { f; }; t_y() { g; }.
casestarts() { # <worktree> <test file>
  jq -Rsr --arg f "$2" "$TESTEDIT_TABLE$HOLLOW_JQ"'row($f) as $t
      | if $t == null then "none" else split("\n") as $ls | [range(0; $ls | length) | select($ls[.] | test($t.case))] as $k
        | [$ls[] | if $t.sh and test($t.case) then shstart else {text: ., one: false} end] as $sl | [$sl[].text] as $lc
        | (if $t.close == null then [] elif $t.sh then [[$lc[] | if test($t.case) then sub(shopen; "") else . end] | shin] else [$ls | jsin] end) as $tx | [$ls[] | tq] as $tq
        | ["row"] + [range(0; $k | length) as $i | $k[$i] as $a | (if $i + 1 < ($k | length) then $k[$i + 1] else ($ls | length) end) as $z
          | ($ls[$a] | ind) as $in
          | (if $sl[$a].one then $a
            elif $t.close then first(range($a; $z) | select(($tx[.] | not) and ($ls[.] | ind) <= $in and ($lc[.] | test($t.close)))) // ($z - 1)
            else (first(foreach range($a + 1; $z) as $j ({q: $tq[$a]}; {p: .q, q: (.q + $tq[$j])};
                select(.p % 2 == 0 and ($ls[$j] | test($t.note) | not) and ($ls[$j] | ind) <= $in) | $j)) // $z) - 1 end) as $e
          | "\($a + 1)\t\($e + 1)\t\($ls[$a] | plain)"] | join("\n") end' "$1/$2" 2>/dev/null
}
# The cases, one a line, that an indirect issue's DIRECT lines (tadirect()) say must keep passing (optproof(), #827):
# only the names <test file> defines on the commit the card was built on (casesgone() of a copy of it), as a judge may
# name a case of another test file or put words of its check in the list. The copy is named by the file's base name
# in a new directory, so a path from the issue (../x) writes nowhere else. A DIRECT line that names no case the file
# defines, or that names no case at all, is passed over, and the card's log says so.
directcases() { # <card> <worktree> <issue json> <test file>
  local d n cs b k=''
  d=$(jq -r '.body // ""' <<<"$3" | tadirect /dev/stdin 2>/dev/null | jq -c '.direct[]?' 2>/dev/null)
  n=$(jq -r '.body // ""' <<<"$3" | grep -cE '^[[:space:]*`_>-]*DIRECT:')
  n=$((n - $(grep -c . <<<"$d")))
  [ "$n" -le 0 ] || echo "conveyor: card $1: $n DIRECT line(s) of its issue name no case, so no case of them is checked" >&2
  cs=$(jq -r '.cases[]' <<<"$d" | awk 'NF && !s[$0]++'); [ -n "$cs" ] || return 0
  b=$(mktemp -d) || return 1
  if git -C "$2" show "HEAD:$4" > "$b/x$(basename -- "$4")" 2>/dev/null; then
    k=$(grep -vxF -f <(casesgone "$b" "x$(basename -- "$4")" "$cs") <<<"$cs")
  fi
  rm -rf "$b"
  jq -r --arg c "$1" --arg f "$4" --arg k "$k" '($k | split("\n")) as $k | select(.cases - $k == .cases)
    | "conveyor: card \($c): a DIRECT line of its issue (\(.protects)) names no case \($f) defines, so no case of it is checked"' <<<"$d" >&2
  [ -z "$k" ] || printf '%s\n' "$k"
}
# The names of <cases> (one a line) that the test file in <worktree> no longer holds (hollowproof(), optproof()): a case
# is held while the name of a case that a line starts (casestarts(); any line of the file, unescaped, for a language
# with no row) holds it as a whole name: no letter or digit just before it (a prefix such as t_ may be), and no letter,
# digit or _ just after it, so t_slotwholeclock does not hold the case slotwhole. The name is the start line's head
# (t_x(), @test "x", the first argument of test( or it(), not the rest of the line, so a case of one line that calls a
# helper (t_autoreruledn() { autoreruled narrow; }) does not hold a case named as the helper. Every case is gone when
# the file is.
casesgone() { # <worktree> <test file> <cases>
  local st kept
  [ -e "$1/$2" ] || { awk 'NF' <<<"$3"; return 0; }
  st=$(casestarts "$1" "$2")
  if [ "$(head -n 1 <<<"$st")" = row ]; then
    # The name is read from the start line as the file holds it, escapes and all, and unescaped after: on the plain line
    # an escaped quote (test('the project\'s rows')) would end the name early, so the case would read as gone.
    kept=$(tail -n +2 <<<"$st" | cut -f1 | awk 'NR == FNR { n[$1]; next } FNR in n' - "$1/$2" \
      | sed -E -e 's/^[[:space:]]*(function[[:space:]]+)?((t_|test)[A-Za-z0-9_]*)[[:space:]]*\(\).*/\2/' -e t \
      -e 's/^[[:space:]]*@test[[:space:]]+("(\\.|[^"\\])*"|[^[:space:]]+).*/\1/' -e t \
      -e "s/^[[:space:]]*[xf]?(it|test)(\\.[A-Za-z]+)?[[:space:]]*\\([[:space:]]*(\"(\\\\.|[^\"\\\\])*\"|'(\\\\.|[^'\\\\])*'|\`(\\\\.|[^\`\\\\])*\`).*/\\3/" -e t -e 's/,.*//' \
      | sed 's/\\\(.\)/\1/g')
  else kept=$(sed 's/\\\(.\)/\1/g' "$1/$2" 2>/dev/null); fi
  K=$kept awk 'function held(c,   s, i, n, b, a) { n = length(c); s = ENVIRON["K"]
      while ((i = index(s, c)) > 0) { b = substr(s, i - 1, 1); a = substr(s, i + n, 1)
        if ((i == 1 || b !~ /[A-Za-z0-9]/) && a !~ /[A-Za-z0-9_]/) return 1
        s = substr(s, i + 1) }
      return 0 }
    $0 != "" && !held($0)' <<<"$3"
}
hollowproof() { # <card> <worktree> <issue json> <test file>
  local wt=$2 f=$4 c x cs starts='' gone=() uncov=() cov s j why='' found='' old='' sc d
  rm -f "$wt.unfixed"
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$wt" add -A 2>/dev/null && ! git -C "$wt" diff --cached --quiet HEAD 2>/dev/null || return 0
  cs=$(jq -r '.body // ""' <<<"$3" | tatagged HOLLOW "$TAHOLLOW" /dev/stdin 2>/dev/null | jq -r '.[] | objects | .case | gsub("^[`\"\u0027]+|[`\"\u0027]+$"; "")' 2>/dev/null | awk 'NF && !s[$0]++')
  # The lines of the file that start a case (casestarts()): a case is kept while one of them names it, so its name left
  # in a comment does not keep it, also when no case is left (casesgone()).
  [ ! -e "$wt/$f" ] || starts=$(casestarts "$wt" "$f")
  starts=$(tail -n +2 <<<"$starts")
  mapfile -t gone < <(casesgone "$wt" "$f" "$cs")
  # The COVERED-BY lines of the build's reply and of each later fix's reply, each {file, for}: a deleted case is covered by a line for it whose file the change keeps.
  cov=$(jq -Rrn '[inputs | fromjson? // empty | objects | if .type == "result" then .result elif .type == "item.completed" and .item.type? == "agent_message" then .item.text
      elif .type == "text" then .part.text? else empty end | strings | split("\n")[] | sub("^[\\s*`_>-]+"; "")
      | capture("^COVERED-BY:\\s*`?(?<file>[^\\s:`]+):\\s*.*?\\S\\s*\\|\\s*`?(?<for>.*?[^\\s*`_])[\\s*`_]*$")] | .[] | "\(.file)\t\(.for)"' "$wt.out" 2>/dev/null)
  cov=$({ cat "$wt.covered" 2>/dev/null; [ -z "$cov" ] || printf '%s\n' "$cov"; } | awk 'NF && !s[$0]++')
  if [ -n "$cov" ]; then printf '%s\n' "$cov" > "$wt.covered"; fi
  for c in "${gone[@]}"; do
    C=$c awk -F'\t' '$2 == ENVIRON["C"] { print $1 }' <<<"$cov" | while IFS= read -r x; do [ -f "$wt/$x" ] && echo y; done | grep -q y || uncov+=("$c")
  done
  [ ${#uncov[@]} = 0 ] || why="each deleted hollow case needs a COVERED-BY line in the build's or a fix session's reply naming a test file the change keeps (COVERED-BY: <test file>: <its case> | <the deleted case>), and these have none: $(printf '%s, ' "${uncov[@]}" | sed 's/, $//')"
  if [ -z "$why" ] && [ -e "$wt/$f" ]; then
    if ! s=$(hollowseat); then why="the judge's hollow check could not run: no reviewer or judge seat is set"
    elif ! j=$(CALLSEAT=$s CALLSTEP=build CALLACT='the judge checks the test file for hollow cases' judgecall "$wt" "Read the test file $f in this worktree as the staged change leaves it, and $TAHOLLOWASK Change nothing. End your answer with one line: $HOLLOWDONE" "Test file: $f"); then
      why="the judge's hollow check could not run: $(jq -r '.failed // "it gave no answer"' <<<"$j" 2>/dev/null)"
    elif [ "$(grep -v '^[[:space:]]*$' "$wt.judge" | tail -n 1 | tr -d '*`_' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" != "$HOLLOWDONE" ]; then
      why="the judge's hollow check gave no whole answer: its last line is not $HOLLOWDONE"
    else
      # The lines the change added or changed in the file, by their number in the file it leaves; a line that is a note
      # (blank or a comment) changes no case. A deletion is placed at the lines added in its place, or between the two
      # lines round it (<n>.5) when none are, so it changes only a case that holds both; one that deletes a start line
      # deletes cases, and changes none of the cases kept. A case runs from its start line to its last line (starts).
      d=$(git -C "$wt" diff --cached -U0 HEAD -- "$f" 2>/dev/null | jq -Rsr --arg f "$f" "$TESTEDIT_TABLE$HOLLOW_JQ"'row($f) as $t
          | reduce split("\n")[] as $l ([]; if ($l | test("^@@ ")) then . + [$l | capture("^@@ -[0-9,]+ \\+(?<b>[0-9]+)") | (.b | tonumber) as $b | {b: $b, i: $b, a: [], del: false, s: false}]
              elif length == 0 or $t == null then .
              elif ($l | startswith("+")) then .[-1].i as $n | .[-1].i += 1 | if ($l[1:] | test($t.note)) then . else .[-1].a += [$n] end
              elif ($l | startswith("-")) then if ($l[1:] | test($t.note)) then . elif ($l[1:] | test($t.case)) then .[-1].s = true else .[-1].del = true end
              else . end)
          | [.[] | .a[], (if .del and (.s | not) then (if .i > .b then .b else .b + 0.5 end) else empty end) | tostring] | join("\n")')
      # Each case the judge finds hollow blocks the card (held) when the issue names it or the change added or changed
      # it, or when no start line names it, so it cannot be placed. Else (old) it is an old case of the file (#584). A
      # name is read plain; one of a single word that no start line holds (TestX.test_y) is read by its last part.
      if ! sc=$(tahollow "$wt.judge" 2>/dev/null | jq -ce --arg s "$starts" --arg c "$cs" --arg d "$d" "$TESTEDIT_TABLE$HOLLOW_JQ"'
          [$s | split("\n")[] | capture("^(?<n>[0-9]+)\t(?<e>[0-9]+)\t(?<t>.*)$") | .n |= tonumber | .e |= tonumber] as $r
          | [$c | split("\n")[] | select(length > 0) | plain] as $named | [$d | split("\n")[] | select(length > 0) | tonumber] as $ch
          | def on($x): [$r[] | select(.t | contains($x))];
            def held($x): (on($x) | if . == [] and ($x | test("^[A-Za-z0-9_.:/-]+$")) then on([$x | splits("[.:/]+") | select(length > 0)] | last // $x) else . end) as $o
              | $o == [] or any($o[]; . as $k | any($named[]; . as $m | $k.t | contains($m)) or any($ch[]; . >= $k.n and . <= $k.e));
          .hollow | map(.case |= (gsub("^[`\"\\x27]+|[`\"\\x27]+$"; "") | plain)) | {held: map(select(held(.case))), old: map(select(held(.case) | not))}'); then
        why="the judge's hollow check gave an answer the engine could not read"
      else
        found=$(jq -r '.held | map("\(.case) (\(.kind)): \(.reason)") | join("; ")' <<<"$sc")
        old=$(jq -r '.old | map("\(.case) (\(.kind)): \(.reason)") | join("; ")' <<<"$sc")
        [ -z "$found" ] || why="the judge's hollow check ($(jq -r '"\(.agent) \(.model)"' <<<"$s")) still finds hollow cases in $f: $found"
        # A hollow old case does not block the card: it goes to the declined list, so the owner sees it.
        while IFS= read -r x; do
          [ -n "$x" ] || continue
          declined "$1" "$(jq -r '.number' <<<"$3")" code "the judge's hollow check found it in a case the issue did not name and the change did not touch, so it does not block the card" "Hollow case of the test file $f: $x" \
            || { why="the judge's hollow check found hollow cases the issue did not name and the change did not touch, and the engine could not write them to the declined list: $old"; break; }
        done < <(jq -r '.old[] | "\(.case) (\(.kind)): \(.reason)"' <<<"$sc")
      fi
    fi
  fi
  { if [ -n "$why" ]; then printf '%s\n' "$why"
    else printf 'This issue makes the hollow cases of the test file %s prove something. ' "$f"
      if [ -e "$wt/$f" ]; then printf 'The judge'"'"'s hollow check (%s) read the file with the change and found no hollow case' "$(jq -r '"\(.agent) \(.model)"' <<<"$s")"
        if [ -z "$old" ]; then printf '.'; else printf ' the issue named or the change added or changed. It found these other hollow cases, each now on the declined list: %s.' "$old"; fi; else printf 'The change deletes the file.'; fi
      [ ${#gone[@]} = 0 ] || printf ' The deleted cases, each with its COVERED-BY line in the card'"'"'s replies: %s.' "$(printf '%s, ' "${gone[@]}" | sed 's/, $//')"
      echo; fi
    [ -z "$cov" ] || { echo "The COVERED-BY lines of the card's replies:"; printf '%s\n' "$cov" | awk -F'\t' '{ print "- " $2 ": covered by " $1 }'; }; } > "$wt.unfixed"
  [ -z "$why" ]
}
# The seat the hollow check runs on: of the reviewer's and the review judge's seats (seat(), lib/control.sh), the
# first on another CLI than the builder's (another model family); else the reviewer's, else the judge's. Fails with
# none.
hollowseat() {
  local b s ss=()
  b=$(seat builder 2>/dev/null | jq -r '.agent // empty' 2>/dev/null)
  s=$(seat reviewer 2>/dev/null) && ss+=("$s"); s=$(seat judge 2>/dev/null) && ss+=("$s")
  for s in "${ss[@]}"; do [ "$(jq -r '.agent // empty' <<<"$s" 2>/dev/null)" = "$b" ] || { printf '%s\n' "$s"; return 0; }; done
  [ ${#ss[@]} != 0 ] && printf '%s\n' "${ss[0]}"
}
# The check of a Make it run card, before its review: a change that removes the test file does not hold (deleting it is
# Delete it). Its proof follows its test step (ranproof()). Writes what the review is told in <worktree>.unfixed, the
# reason first when it does not hold, and fails then.
runproof() { # <worktree> <test file>
  rm -f "$1.unfixed"
  git -C "$1" add -A 2>/dev/null && ! git -C "$1" diff --cached --quiet HEAD 2>/dev/null || return 0
  if [ ! -e "$1/$2" ]; then echo "the change removes the test file $2: a Make it run card keeps it and makes the test command run it" > "$1.unfixed"; return 1; fi
  printf 'This issue makes the test file %s run. After this review, the card'"'"'s test step must run it, and it must pass; else the card is blocked.\n' "$2" > "$1.unfixed"
}
# After the test step of a Make it run card passed: the step ran the file and it passed, when what the step passed
# (<worktree>.passed, testlist.sh passlist(): the file whole, or a case of it) names it. Prints why not, and fails, when it does not.
ranproof() { # <worktree> <test file>
  jq -e --arg f "$2" 'any(.units[]?; . == $f or startswith($f + "\t"))' "$1.passed" > /dev/null 2>&1 && return 0
  echo "the card's test step did not run the test file $2: the test command still does not run it, or it ran none of its cases"
  return 1
}
# The check of a Delete it card: the change removes the test file, and it is then checked as an Optimize delete
# (optproof()): the review is told the cases the file held and asked to name, for each, the test that still covers
# it on a COVERED-BY line. A change that keeps the file does not hold: <worktree>.unfixed says so, and it fails.
deleteproof() { # <card> <worktree> <issue json> <test file>
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || { rm -f "$2.unfixed"; return 0; }
  [ ! -e "$2/$4" ] || { echo "the change keeps the test file $4: a Delete it card deletes it" > "$2.unfixed"; return 1; }
  optproof "$@"
}
# The check of a Fix the waiting, Fix hollow cases, Delete it or Make it run alone card (<kind>: WAITFIX, HOLLOWFIX,
# DELFILE or ALONEFIX): card()
# runs it after the build, and again before each later review when a fix or rebase session changed the card, so the
# proof the review reads is of the change that lands. Fails when the check does not hold.
fixproof() { # <card> <worktree> <issue json> <test file> <kind>
  case $5 in
    "$WAITFIX") steadyproof "$1" "$2" "$4" "$WAITRATIO" ;;
    "$HOLLOWFIX") hollowproof "$1" "$2" "$3" "$4" ;;
    "$ALONEFIX") aloneproof "$1" "$2" "$4" ;;
    *) deleteproof "$1" "$2" "$3" "$4" ;;
  esac
}
# Make it run alone (#190): the Board's issue about a test file the pack marks wholeOnly, its title "Make the test file
# <file> run alone" (MAKERUN, then the file, then ALONEFIX). alonefile() prints its file; fixproof() checks it with
# aloneproof(), as it checks Fix the waiting.
ALONEFIX=' run alone'
alonefile() { # <issue json>
  [[ $(jq -r '.title // ""' <<<"$1") == "$MAKERUN"*"$ALONEFIX" ]] && speedfile "$1" "$MAKERUN"
}
# The check of a Make it run alone card: main's pack (.conveyor/project.json) as the change leaves it no longer marks
# the file wholeOnly, and the file runs alone, with the change, on a test slot, through the test.fileCommand of that
# same pack (with none set, the check fails naming it). The run must pass and the command must have run the file: a
# case of it that passed (testfails(): one whose name is in the file's text) or the runner's time of it names it (a time
# from Record CPU time only when the change leaves main's test.fileCommand). A change that removes the file (its runs
# moved into other test files) runs the test files the change adds or changes in its place. Writes the result in <worktree>.unfixed, the reason first when it does not
# hold, and fails then.
aloneproof() { # <card> <worktree> <test file>
  local mwt=$CARDS/mainrun/$1.alone f=$3 sha out='' rc=0 why='' x tl='' fs=() ok t tm pp=$2/.conveyor/project.json
  rm -f "$2.unfixed"
  # No change at all (an ALREADY-DONE) is not checked: it goes its own way (nochange()).
  git -C "$2" add -A 2>/dev/null && ! git -C "$2" diff --cached --quiet HEAD 2>/dev/null || return 0
  if [ -e "$2/$f" ]; then fs=("$f")
  else mapfile -t fs < <(git -C "$2" -c core.quotePath=false diff --cached --name-only --no-renames --diff-filter=AM HEAD 2>/dev/null | testpaths); fi
  # The pack the change leaves; main's own when the project does not track it (no card changes it then).
  [ -e "$pp" ] || pp=$PACK
  if jq -e --arg f "$f" '.test.files[$f].wholeOnly == true' "$pp" > /dev/null 2>&1; then
    why="the change leaves the test file $f marked whole-only (test.files.\"$f\".wholeOnly in .conveyor/project.json): a Make it run alone card takes the mark off"
  elif [ ${#fs[@]} = 0 ]; then why="the change removes the test file $f and adds or changes no test file to run what it ran"
  fi
  [ -z "$why" ] || { printf '%s\n' "$why" > "$2.unfixed"; return 1; }
  if sha=$(git -C "$2" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    && out=$({ git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; git worktree prune; mkdir -p "${mwt%/*}" \
      && git worktree add -q --detach "$mwt" "$sha" && deps "$mwt" \
      && git -C "$2" diff --cached --binary --no-renames HEAD | git -C "$mwt" apply --index; } 2>&1 < /dev/null); then
    # The run reads the pack the change leaves (pp), so a change to test.fileCommand is the command it proves.
    printf 'fail\t%s\n' "${fs[@]}" > "$mwt.rerun"; PACK=$pp tests "$mwt" test.fileCommand alone; rc=$?
    if [ -s "$mwt.stop" ]; then why=$(<"$mwt.stop")
    elif [ "$rc" != 0 ]; then
      x=$(testfails "$mwt.test" "$rc" 2>/dev/null | jq -r '[.files[]?.cases[]?.name | select(. != "")] | unique | join(", ")' 2>/dev/null)
      why="the test file ${fs[*]} failed run alone through the pack's test.fileCommand, with the change, on a test slot (exit $rc)${x:+: its failing cases: $x}"
      tl=$(tail -n 30 "$mwt.test" 2>/dev/null | tr -d '\000')
    else
      # Not the file's `-- ok` line: filecmd() writes it on any exit 0 of the command, so a command that runs nothing
      # (as `true`) has it too. A case of the file that passed (in its text), or a time of it the runner gave (a
      # `TESTRUN sec` line of its logs or its report, testlist.sh reported()). The log `cputime`, which the engine's wrapper
      # (cputwrap(), lib/testfiles.sh; the Board's Record CPU time) writes for any command it wraps, counts only when
      # the change leaves main's test.fileCommand: a card's own wrapper around a command that runs nothing writes it too.
      t=$(testfails "$mwt.test" 0 2>/dev/null) x='/cputime$'
      [ "$(jq -c '.test.fileCommand' "$pp" 2>/dev/null)" != "$(jq -c '.test.fileCommand' "$PACK" 2>/dev/null)" ] || x='^$'
      tm=$({ cat "$mwt.reported"; testlogs "$mwt" | grep -v -- "$x" | tr '\n' '\0' | xargs -0r cat; } 2>/dev/null | awk -F '\t' '$1 == "TESTRUN sec" { print $2 }')
      for x in "${fs[@]}"; do
        grep -qxF -- "$x" <<<"$tm" && continue
        ok=$(jq -r --arg f "$x" '(.passcases + .okcases)[]? | select(.file == $f) | .cases[] | select(. != "")' <<<"$t" 2>/dev/null)
        [ -n "$ok" ] && grep -qF -- "$ok" "$mwt/$x" 2>/dev/null && continue
        why="the run alone through the pack's test.fileCommand passed, but did not run the test file $x: no case of it that passed, and no time of it from the runner itself, is in the run's output, logs or report"; break
      done
    fi
  else why="the test file ${fs[*]} could not be run with the change: ${out:0:300}"; fi
  { if [ -n "$why" ]; then printf '%s\n' "$why"
    else printf 'This issue makes the test file %s run alone. The pack no longer marks it whole-only, and run alone through the pack'"'"'s test.fileCommand, with the change, on a test slot, %s passed.\n' "$f" "${fs[*]}"; fi
    [ -z "$tl" ] || { echo 'The end of the output of the run that failed:'; echo '```'; printf '%s\n' "$tl"; echo '```'; }; } > "$2.unfixed"
  git worktree remove --force "$mwt" 2>/dev/null; rm -rf "$mwt" "$mwt".*; rmdir "${mwt%/*}" 2>/dev/null # the folder, once no card's run is in it
  [ -z "$why" ]
}
