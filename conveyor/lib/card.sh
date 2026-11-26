# SPDX-License-Identifier: Apache-2.0
# One card to its closing line (landed, closed or blocked). Every step checks its own exit and writes its own line when it
# ends; nothing waits between a line and the next step, which is how cards() names the step in progress.
# With a branch and its tip (land-branch) the card skips the build: that commit is merged into the worktree, staged
# and uncommitted, in place of a session's work. Issue 0 is a branch that names no issue: branchissue() stands in.
# Once the worktree is made and holds no stray staged change (cardtree()), the rule Split large issues checks the card's issue (splitcheck(), lib/slices.sh): an issue it splits ends its card there, closed, its slices filed, its worktree removed.
# Then the rule Pick settings records the card's group and builder choice on each of its lines from there on, and with the rule On sets a trial card's builder (modelpick(), lib/modelpick.sh).
. "$HERE/lib/slices.sh" || exit 1
. "$HERE/lib/modelpick.sh" || exit 1
. "$HERE/lib/lint.sh" || exit 1
. "$HERE/lib/cardland.sh" || exit 1
began() { # <card> <issue> <what begins> [<more fields of the start line, a JSON object>]
  local e=''
  switchcode "$1" "$3"; rm -f "$CARDS/$1.firsttry" "$CARDS/$1.firsttry.new" "$CARDS/$1.reviewed"; capmark "$1" "$3" # capmark(): lib/run.sh
  # A card on the code of a commit it switched to: its start line names that commit, so prune() (inflight(),
  # lib/install.sh) keeps its install while the card runs; its worktree line names the commit it started on.
  [ -z "$RAN" ] || [ "$RAN" != "${CODESEEN:-}" ] || e=",\"engine\":\"$RAN\""
  e="{\"of\":\"$3\"$e}"; [ -z "${4:-}" ] || e=$(jq -c --argjson m "$4" '. + $m' <<<"$e") || return 1; record "$1" "$2" start ok "$e"
}
# The form of the files a card saves for its steps (<worktree>.review, .test, .ready, .rerun and the rest): a commit
# whose code cannot read the files that the code before it saved raises it, and a running card then keeps its old code (switchcode()).
STEPFILES=1
# A card the loop runs, at the start of each step (began()): when the loop runs a newer Conveyor commit than the card
# (loop.json; a loop that takes a commit stays the same process, as run() restarts by exec, so its pid is the card's
# $$), the card goes on with that commit's code from this step. The commit's engine files are loaded into the card's
# own process between two steps, never in a session: its worktree, claim, passed steps and their results stay as they
# are, and no passed step runs again. What the card set while it ran stays: a variable or function takes the new value
# only where the new files load another value than the old files do (codediff()). The parts of the card's prompts and
# settings that the engine made when the card started are made again by the new code: its settings file (the hooks,
# from the new install), and the card's rules, its header and the engine's review texts in each prompt a session or
# review is given from then on: switchcode() keeps each old text with its new one (SWAPOLD, SWAPNEW) and session()
# and review() put the new one in its place (newtexts()), so a copy of the prompt a function was handed before the
# switch gets them too. The rules and header are the ones card() made (its rules and hdr: began() runs only under
# card()). A function that is running (card(), the step of card() it is in, and settle() or began() under it) goes on
# in its old body to its end, as bash runs it: so the card keeps its old code, and says why once, when the new code
# changes one of them, reads another form of step files (STEPFILES), or its files do not load or do not make the card's rules, header and settings.
# shellcheck disable=SC2034 # CONVEYOR_MAIN and NAMED: read by paths.sh and names() (lib/prompts.sh)
switchcode() { # <card> <the step it begins>
  local s p d v old why='' tmp f i k o=() nv=()
  s=$(jq -r --argjson p "$$" 'select(.pid == $p) | [.commit // "", .checkout // ""] | @tsv' "$SAYS" 2>/dev/null) || return 0
  IFS=$'\t' read -r p d <<<"$s"
  [ -n "$p" ] && [ -n "$RAN" ] && [ "$p" != "$RAN" ] && [ "$p" != "${CODESEEN:-}" ] || return 0
  CODESEEN=$p; [ -n "$d" ] || d=$VERSIONS/$p/conveyor
  v=$(sed -n 's/^STEPFILES=\([0-9][0-9]*\)$/\1/p' "$d/lib/card.sh" 2>/dev/null)
  tmp=$(mktemp -d) || return 0
  # The old code's files, to compare with: an install's own folder, or the checkout's engine folder at the card's
  # commit (git archive, run in a folder of the checkout, gives that folder's files alone).
  if [ -n "$OWN" ]; then old=$HERE
  else old=$tmp/old; mkdir "$old" && git -C "$HERE" archive -o "$tmp/old.tar" "$RAN" && tar -xf "$tmp/old.tar" -C "$old" || old=''; fi
  if [ "$v" != "$STEPFILES" ]; then why="the new code cannot read the step files that the old code saved (form $STEPFILES; the new code reads form ${v:-none})"
  elif [ -z "$old" ] || ! ( CONVEYOR_MAIN=$MAIN; codediff "$old" "$d" ) > "$tmp/load" 2>/dev/null || ! ( . "$tmp/load" && NAMED='' && names ) >/dev/null 2>&1; then
    why="the new code's engine files did not load"
  else
    # The functions running now, from began() up to card(): declare -f heads each one the new code changes "<name> () ".
    for f in "${FUNCNAME[@]:1}"; do
      ! grep -qxF "$f () " "$tmp/load" || { why="the new code changes $f(), which the card is running in"; break; }
      [ "$f" != card ] || break
    done
    [ -n "$why" ] || ( . "$tmp/load" && NAMED='' && names && cardrules "$issue" > "$tmp/rules" && header "$vrule" > "$tmp/hdr" && cardsettings "$tmp/settings" ) >/dev/null 2>&1 \
      || why=${why:-"the new code could not make the card's rules, header and settings"}
  fi
  [ -n "$why" ] || mv -f "$tmp/settings" "$CARDS/$1.settings" 2>/dev/null || why="the new code's settings for the card could not be saved as $CARDS/$1.settings"
  if [ -z "$why" ]; then
    # The texts card() made its prompts of, before the switch and after it: its header and rules, and the review
    # texts its rv is made of (KINDS with the kinds judgeon names now). After the next switch, its new ones are old.
    k=$(judgeon 2>/dev/null) && [ "$k" != '[]' ] && k=$(jq -r 'join(", ")' <<<"$k") || k=''
    o=("$hdr" "$rules" "$REVIEWOFF" "$REVIEW" "$INHERIT" "$HELD" "${k:+${KINDS//'<kinds>'/"$k"}}")
    . "$tmp/load"; NAMED=''; names >/dev/null 2>&1
    nv=("$(<"$tmp/hdr")" "$(<"$tmp/rules")" "$REVIEWOFF" "$REVIEW" "$INHERIT" "$HELD" "${k:+${KINDS//'<kinds>'/"$k"}}")
    for i in "${!o[@]}"; do [ -z "${o[i]}" ] || [ "${o[i]}" = "${nv[i]}" ] || { SWAPOLD+=("${o[i]}"); SWAPNEW+=("${nv[i]}"); }; done
    hdr=${nv[0]}; rules=${nv[1]}
  fi
  rm -rf "$tmp"
  if [ -n "$why" ]; then echo "conveyor: card $1: Conveyor took commit $p; the card goes on with its old code, commit $RAN: $why"
  else echo "conveyor: card $1: Conveyor took commit $p; the card goes on with the new code from its $2 step, and no passed step runs again"; fi
}
# The engine files of an engine folder, loaded into this shell as `serve` loads them (conveyor.sh, commands/serve.sh).
# shellcheck disable=SC1090 # the engine folder is named at run time
codeload() { # <engine folder>
  local f
  HERE=$1; . "$1/lib/portable.sh" && . "$1/lib/paths.sh" serve && . "$1/lib/records.sh" serve || return 1
  for f in $(sed -n 's/^\. "\$HERE\/\(lib\/[a-z]*\.sh\)" || exit 1$/\1/p' "$1/commands/serve.sh"); do . "$1/$f" serve || return 1; done
}
# In a subshell of the card: the declarations, to load with `.`, of what the new folder's engine files load other than
# the old folder's do: the variables named in capitals (the engine's own; the rest are the shell's or a function's)
# and the functions. A top-level declare in an engine file needs -g, as this loads inside a function.
codediff() { # <old engine folder> <new engine folder>
  local n d wd=$PWD sh='BASH.*|EPOCH.*|S?RANDOM|SECONDS|LINENO|PIPESTATUS|FUNCNAME|PWD|OLDPWD|OPTIND|OPTARG|PPID|UID|EUID|GROUPS|DIRSTACK|HISTCMD|SHLVL|COLUMNS|LINES|IFS'
  local -A snap=() # snap: the old folder's declarations; not `was`, card()'s string, which shellcheck takes for this array
  # Both from the card's folder: records.sh moves into the main checkout, and paths.sh and records.sh read where they start.
  codeload "$1" >/dev/null 2>&1 && cd "$wd" || return 1
  for n in $(compgen -v | grep -xE '[A-Z][A-Z0-9_]*' | grep -vxE "$sh"); do snap[v$n]=$(declare -p "$n" 2>/dev/null); done
  for n in $(compgen -A function); do snap[f$n]=$(declare -f "$n"); done
  codeload "$2" >/dev/null 2>&1 || return 1
  for n in $(compgen -v | grep -xE '[A-Z][A-Z0-9_]*' | grep -vxE "$sh"); do
    d=$(declare -p "$n" 2>/dev/null) && [ "$d" != "${snap[v$n]-}" ] && [[ ! $d =~ ^declare\ -[a-zA-Z]*r ]] || continue
    case $d in "declare -- "*) printf '%s\n' "declare -g ${d#declare -- }" ;; *) printf '%s\n' "declare -g${d#declare -}" ;; esac
  done
  for n in $(compgen -A function); do d=$(declare -f "$n"); [ "$d" = "${snap[f$n]-}" ] || printf '%s\n' "$d"; done
}
# A main-red fix card (issue 0, no branch): a case found failing on its commit while it runs (mainred.sh mainred()) joins its
# brief. card() calls this right before each session, review, judge, settle() and land, as a case can come at any time
# (during a review too, with the fix session straight after it). Sets card()'s issue and sprompt. A case that joined
# brings its links too (issue 615), staged in card()'s worktree (mainred.sh testlinks()) to land with the fix: each call stages
# the links not staged before, so one that could not be is tried again, and one a session took out is not put back.
redbrief() { # <card> <issue> <branch>
  local red
  [ "$2" = 0 ] && [ -z "$3" ] || return 0
  testlinks "$1" "$wt" || echo "conveyor: card $1: the test links of the main-red record could not be staged in .conveyor/test-links.json" >&2
  red=$(redissue "$1") && [ "$red" != "$issue" ] || return 0
  sprompt=${sprompt/"$(issuepart "$issue")"/"$(issuepart "$red")"}; issue=$red
}
# A main-red fix card's commit message (card(), before it lands): its cases as its entry holds them now (redfix.sh redissue();
# the issue it was built from when the entry cannot be read) and main's commit it was picked for (its mainRed).
redmsg() { # <card> <issue json>
  local t; t=$(redissue "$1") || t=$2
  jq -r --arg c "$1" --arg s "$(stdb ask card "$1" | jq -rs 'map(.mainRed // empty)[0] // ""')" '"fix(product): \(.title) (main \($s[0:12]))\n\nConveyor card \($c)"' <<<"$t"
}
# card()'s wait for main to change (mainred.sh mainwait()), its seconds added to card()'s mainsec, less those of the runs on main it took (mainwait()'s mainrun): mainwait() records each on a start line of card()'s test step as its mainRun, which the Board's mainSec counts.
mainwaited() { # <worktree> <main's commit> <case>...
  local mw=$SECONDS mainrun=null; mainwait "$@"; mainsec=$((mainsec + SECONDS - mw - $(jq '.sec // 0' <<<"$mainrun" 2>/dev/null || echo 0))); }
# A card's landed line's extra (card(), as it lands): <left> (its filed follow-ups) with waitSec, the seconds it waited
# on other cards (settle()), for main to change (mainwaited()) and for the machine hold or the repair lane (holdwaited(),
# lib/cardland.sh), for the drift watch (bench/drift.sh); yesFrom; and rollout, its rollout actions, as its ready file holds them too.
landextra() { # <left json> <yesfrom json, or none> <rollout json>
  local x; x=$(jq -c --argjson w "$(waited)" '. + $w' <<<"${1:-"{}"}") || x=$1
  [ -z "$2" ] || x=$(jq -c --argjson f "$2" '. + {yesFrom: $f}' <<<"${x:-"{}"}")
  [ "$3" = '[]' ] || x=$(jq -c --argjson r "$3" '. + {rollout: $r}' <<<"${x:-"{}"}")
  printf '%s\n' "$x"
}
# The sessions' and the reviewer's prompt (plan section 10, the reviewer gets the same text): the brief with the
# rules after the header, before the issue. Each session and review is handed it with its own part after it.
cardprompt() { # <card> <header> <rules> <brief>
  local rhead="Conveyor card $1. $2"$'\n\n'
  printf '%s' "$rhead"$'# Rules\n\n'"$3"$'\n\n'"${4#"$rhead"}"
}
# The prompts of the sessions after the build, each the card's prompt (cardprompt()) with its own part after it: a fix
# of review findings, a fix of the changed tests (the failing cases, then the last 200 lines of their output), and a rebuild or a port onto main.
fixprompt() { # <card prompt> <the findings, each led by its id, and what follows them> [<repeats() lines>: FIXBACK follows FIX when there are any]
  printf '%s' "$1"$'\n\n'"$FIX$([ -z "${3:-}" ] || printf '\n%s' "$FIXBACK")"$'\n'"$2"
}
# Why a review ends the fix loop, the first that holds: go (a GO), max-reviews (it is review MAX_REVIEWS, counting the rounds a retried card carries), rebased (the one review after a landing conflict), test-fix (after a test fix),
# lint-fix (after the landing gate's lint fix), land (the kept review of a kept patch landed with no review), repeat (a NO-GO that repeats a fixed finding, each P0 or P1 of it a repeat; afterreview() ends the loop so too when a repeated harm one is P0 or P1), new-p2 (from review 2 on, counted as max-reviews is, a NO-GO with findings that repeats none, none of them P0 or P1 (a finding with no level is P1): the card lands, each harm finding filed as a follow-up and each of another kind sent to its list, issue 1578; afterreview() drops it at the follow-up depth cap). Prints nothing when a fix round follows.
loopstop() { # <verdict> <reviews so far: pass + rounds> <rebased> <tfix> <lfix> <mode> <donewhen.sh repeats() lines> <review file>
  if [ "$1" = GO ]; then echo go
  elif [ "$2" -ge "$MAX_REVIEWS" ]; then echo max-reviews
  elif [ -n "$3" ]; then echo rebased
  elif [ -n "$4" ]; then echo test-fix
  elif [ -n "$5" ]; then echo lint-fix
  elif [ "$6" = land ]; then echo land
  elif [ -n "$7" ] && [ "$(findings "$8" | jq -s --slurpfile r <(jq -c '.line' <<<"$7") 'map(select((.level == "P0" or .level == "P1") and (.line | IN($r[]) | not))) | length')" = 0 ]; then echo repeat
  elif [ -z "$7" ] && [ "$2" -ge 2 ] && [ "$(findings "$8" | jq -s 'length > 0 and all(.level != "P0" and .level != "P1")')" = true ]; then echo new-p2
  fi
}
testfixprompt() { # <card prompt> <worktree> <the test run's exit> [the failures json of testfails(), as cardfailed() read them]
  local f='' file name line n
  # Each failing case with its file and the place it failed, first. A case's line ends with ` (at <file>:<line>: <text>)`
  # when the output gave a stack; a shell case gives none, so its place is the line of its t_<name>() in its file, or, in a
  # standalone test file with no such function, the first line that names the case as `[<name>]` or in quotes (where it
  # prints its FAIL, or hands its name to the check that does). A failed file that names no case has its own at. Then the raw end of the output, under its own heading.
  while IFS=$'\037' read -r file name line; do
    [ -n "$file" ] || continue
    if [ -n "$name" ] && [[ $line != *" (at "* ]] && n=$(awk -v p="t_$name() {" -v q="[$name]" -v s="'$name'" -v d="\"$name\"" 'index($0, p) == 1 { print NR; t = 1; exit } !m && (index($0, q) || index($0, s) || index($0, d)) { m = NR } END { if (!t && m) print m }' "$2/$file" 2>/dev/null) && [ -n "$n" ]; then line+=" (at $file:$n)"; fi
    f+="- $file${line:+: $line}"$'\n'
  done < <([ -z "${4:-}" ] || jq -r '.files[]? | .file as $f | if (.cases // []) != [] then .cases[] | [$f, (.name // ""), .line] elif .at then [$f, "", .at] else [$f, "", ""] end | join("\u001f")' <<<"$4" 2>/dev/null)
  [ -z "$f" ] || f=$'\n\n# The failing cases of the changed tests, each with its file and the place it failed:\n'"$f"
  printf '%s' "$1$f"$'\n\n# The changed tests fail (exit '"$3"$'): fix that and nothing else. The end of the test output:\n'"$(tail -n 200 "$2.test" 2>/dev/null | tr -d '\000')"
}
rebaseprompt() { # <card prompt> <worktree> <the conflict message> <the commit its patch was made against> [port]
  local p=''; [ -z "${5:-}" ] || p=$'\nOne review of this port alone follows: change nothing else.'
  printf '%s' "$1"$'\n\n'"$REBASE$p"$'\n\n## The conflict message\n'"$3"$'\n\n## The card\'s patch\nThe file '"$2.patch"$', made against commit '"$4"$'.'
}
# What a review is shown after the card's prompt, beside the diff: the card's commit trailers, the D<n> lines of the
# last checked reply, and the proof of a bug or speed card's tests (<its heading>, then the lines of <worktree>.unfixed).
reviewseen() { # <worktree> <the proof's heading>
  local m
  m=$(trailerview "$1") || return 1
  [ ! -s "$1.donewhen" ] || m+=$'\n\n'"$DONEWHENREVIEW"$'\n'"$(<"$1.donewhen")"
  [ ! -s "$1.unfixed" ] || m+=$'\n\n'"$2"$'\n'"$(<"$1.unfixed")"
  printf '%s' "$m"
}
# The commit message of a card of an issue: its subject from the pack's type label (fix, else feat) and area prefix
# (its first area label, else product), then its Closes and card lines; a card with no GitHub issue's (number 0) names no issue, and carries its body (the words it came from), a closing keyword's issue named without its # or address so the push closes none. With the pack's privacy.mode public, such a message has each word the privacy check flags masked (privmask(), lib/issues.sh), as a follow-up's text is: the body can quote test output, and the push checks no commit message. Fails when the pack or the check could not be read.
cardsubject() { # <card> <issue json>
  local m pm; m=$(jq -r --arg c "$1" --arg t "$TYPE" --arg p "$AREA" '(.labels | map(.name)) as $l | (.number != 0) as $i | "\(if $l | index($t) then "fix" else "feat" end)(\($l | map(select(startswith($p)) | ltrimstr($p)) | .[0] // "product")): \(.title)\(if $i then " (#\(.number))" else "" end)\n\n\(if $i then "Closes #\(.number)\n" else .body // "" | gsub("(?i)\\b(?<k>close[sd]?|fix(?:e[sd])?|resolve[sd]?)(?<s>:?\\s+)(?:https?://\\S+/(?:issues|pull)/|(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#)(?<n>[0-9]+)"; "\(.k)\(.s)issue \(if .r then .r + " " else "" end)\(.n)") | sub("\\s+\\z"; "") | if . == "" then "" else . + "\n\n" end end)Conveyor card \($c)"' <<<"$2") && packget privacy.mode pm || return 1
  if [ "$pm" = public ] && [ "$(jq -r .number <<<"$2")" = 0 ]; then privmask "$m"; else printf '%s\n' "$m"; fi
}
# A failed (or held) test step's line, past its common fields: the run's record (testrec()), its reason (the exit, and
# the timeout with the file still running when there was one), its failures (testfails(), less host: check.jq has no
# such field), the last 60 lines of its output (its tail, each line whole), its first-run marks (firstrun()), the
# verdicts of what ran again on main (mainred.sh verdicts()) and its carried and partial part (testlist.sh carriedrec()).
failline() { # <worktree> <exit> <seconds> <failures json, or null> <verdicts json> <carried and partial json>
  tail -n 60 "$1.test" 2>/dev/null | tr -d '\000' | jq -cRs --slurpfile x <(testrec "$1" "$2" "$3") --slurpfile f <(printf '%s' "$4") --arg rc "$2" --slurpfile r <(firstrun "$1") --slurpfile v <(printf '%s' "$5") --slurpfile o <(printf '%s' "$6") \
    '$x[0] as $x | $f[0] as $f | $r[0] as $r | $v[0] as $v | $o[0] as $o | sub("\n+$"; "") as $t | $x + $o + {
       reason:("exit " + $rc + (if $f.timeout then ": timed out after \($f.timeout.sec)s" + (if $f.timeout.file then " in \($f.timeout.file)" else "" end) else "" end) + ($f.notRun // [] | if . == [] then "" else "; it stopped at its first failure, so these files did not run: " + join(", ") end))}
     + (if $f then {failures:($f | del(.passed, .okcases, .passcases, .host))} else {} end) + (if $t == "" then {} else {tail:$t} end) + $r + $v'
}
# What card() does after a review, decided from its verdict (res) and the loop's state, with nothing done: after is priv (a last
# NO-GO still holds a privacy hit of its own after PRIVFIXES fix rounds: the card is shut, its work kept, the hit on the self-heals list),
# go (land), last (a last review: land with follow-ups, whatever the level of its findings, issue 1670), nofinding (a NO-GO with no
# finding to fix: block) or fix (a fix round). It reads card()'s wt, issue, res, fin, finrev, finend, pass, rounds (the rounds a retried
# card carries), rebased, tfix, lfix, mode, privfix and p1fix, and sets card()'s after, last, earlier, earlyend, fin, rep, hard, priv, p1, stop, last0, ended, isfu and why (bash's dynamic scope).
afterreview() {
  local d
  # A GO on the review of a port lands with the earlier loop's outcome: after its last NO-GO, that review's
  # findings are filed again, whatever the reviews after a test fix say. A NO-GO on it is fixed and goes round the loop as any card's.
  last=''; [ "$fin" != NO-GO ] || [ "$res" != GO ] || { earlier=$finrev; earlyend=$finend; }; fin=''
  [ -z "${rlrev:-}" ] || [ "$mode" = land ] || earlier=$rlrev # A retry by review-land files its kept review's findings (rlrev, resumeplan()) whatever a later review says: each review after that one (mode no longer land) carries it as the earlier loop's last NO-GO. Bug: a GO after a test fix, or after the fix of a port's own finding, dropped the finding that blocked the card.
  # A NO-GO that repeats a finding a fix round was told to fix (donewhen.sh repeats()) spends no more rounds on it: when every
  # P0 or P1 finding of the review is such a repeat this is the last review (loopstop()); so is one where a repeated harm one
  # is P0 or P1 (hard: that finding), whatever else it holds. A review finding never blocks a card (issue 1670): at the last review the card lands, each
  # harm finding filed as a follow-up and each of a kind kept off the belt (harmonly(), lib/followups.sh) sent to its list. The kept review of a retry by review-land (rland) or of a Test-step block (tland), in mode land with no fix rounds carried, gives its P1 no fix round (p1, below).
  rep=''; [ "$res" != NO-GO ] || rep=$(repeats "$wt")
  hard=$(harmonly "$wt" <<<"$rep" | jq -rs 'map(select(.level == "P0" or .level == "P1")) | first // empty | .line[:300]')
  # A last NO-GO with a finding that is a privacy hit in the card's own change (privown(), lib/followups.sh) gets
  # another fix round, up to PRIVFIXES of them (privfix counts them), and lands only once a last review finds no such hit: a
  # follow-up would land the hit on main. A hit still there after them shuts the card (after priv, cardfix()). Bugs: it was filed as a follow-up the privacy check refused; after its round, a new hit landed.
  # stop: why this review ends the loop (loopstop()), empty when a fix round follows.
  # last0: the first P0 finding of a last NO-GO (one that ends the loop): the card lands at once with it filed, no P1 fix round first.
  # p1: the first P1 finding of a last NO-GO with no P0, no repeat and no privacy hit (one still there here has had its
  # PRIVFIXES rounds: bug, a new P1 beside it gave it one more). It gets one fix round, once a card (p1fix), and a fix-only
  # review; a P1 still held after that lands as a follow-up.
  priv=''; stop=''; last0=''; p1=''
  if [ -n "$hard" ]; then stop=repeat
  else
    stop=$(loopstop "$res" "$((pass + rounds))" "$rebased" "$tfix" "$lfix" "$mode" "$rep" "$wt.review")
    [ "$stop" != new-p2 ] || { d=$(fudepth "$issue") && [ "$d" -lt "$MAX_DEPTH" ]; } || stop='' # a card at the follow-up depth cap files none: it gets the fix round (bug: its P2s landed, declined)
  fi
  [ -z "$stop" ] || [ "$res" = GO ] || ! priv=$(privown "$wt") || [ -z "$priv" ] || [ "${privfix:-0}" -ge "$PRIVFIXES" ] || stop=''
  [ -z "$stop" ] || [ "$res" = GO ] || last0=$(findings "$wt.review" | harmonly "$wt" | jq -rs 'map(select(.level == "P0")) | first // empty | .line[:300]')
  [ -z "$stop" ] || [ "$res" = GO ] || [ -n "$hard$last0$priv" ] || { [ "$mode" = land ] && [ -n "${rland:-}${tland:-}" ]; } || p1=$(findings "$wt.review" | harmonly "$wt" | jq -rs 'map(select(.level == "P1")) | first // empty | .line[:300]'); [ -z "$p1" ] || [ -n "$p1fix" ] || stop=''
  # The review line, and the filed line after it, say why the loop ended: stop, with pass and rounds as they are here.
  ended=$(jq -cn --arg s "$stop" --argjson p "$pass" --argjson r "$rounds" 'if $s == "" then {} else {stop: $s, pass: $p, rounds: $r} end')
  if [ -n "$stop" ] && [ -n "$priv" ]; then after=priv
  elif [ "$res" = GO ] && [ -z "$earlier" ]; then after=go
  elif [ -n "$stop" ]; then
    # A card whose issue is a follow-up at the depth cap (fudepth(), lib/followups.sh) files none: its findings go
    # on the self-heals list as it lands (capheals(), lib/followups.sh). A depth that cannot be read counts as the cap.
    after=last; last=1; isfu=1; d=$(fudepth "$issue") && [ "$d" -lt "$MAX_DEPTH" ] && isfu=''
  # A NO-GO with no finding (an UNPROVEN line alone, say) has nothing for a fix session to fix, or to number: the
  # card blocks with the reviewer's own line (its first UNPROVEN line, else its VERDICT line), cut at 200 characters.
  elif ! grep -Evq "$NOTFINDING" "$wt.review"; then after=nofinding; why=$(grep -m1 '^UNPROVEN:' "$wt.review" || grep -m1 '^VERDICT:' "$wt.review")
  else after=fix
  fi
}
# What a bug card does after its bug-card check (bugproof.sh bugproof()), from that check's exit: close (3: every case passes on
# main without the change, so the card closes as already done), block (2: the check cannot hold, and a build session
# cannot mend it), build (another failure: one build session is told why), or nothing (0: on to the review). With
# again (the check after that build session), exit 2 still prints block, and any other failure prints unproved: the
# card blocks with the reason the check gave (BUGWHY).
bugstep() { # <the exit of bugproof.sh bugproof()> [again]
  case $1 in
    0) ;;
    2) echo block ;;
    3) [ -n "${2:-}" ] && echo unproved || echo close ;;
    *) [ -n "${2:-}" ] && echo unproved || echo build ;;
  esac
}
# Whether a card's staged change is no change (exit 0), after it stages the whole worktree (git add -A): nothing is
# staged, or the stage fails, or a main-red fix card (issue 0, no branch) stages only the links the engine staged
# (mainred.sh linksonly()). The links come with a fix, so with none they are dropped: the worktree is reset to its commit (issue
# 323). Exit 1: a change to review.
emptychange() { # <card> <issue number> <worktree> <branch, or ''>
  git -C "$3" add -A && ! git -C "$3" diff --cached --quiet || return 0
  [ "$2" = 0 ] && [ -z "$4" ] && linksonly "$1" "$3" || return 1
  git -C "$3" reset -q --hard HEAD || :
}
# card()'s steps, in turn: cardtree(), cardopen(), cardbuild(), then on each pass of the review loop cardreview() and cardfix() here, cardready(), cardlanding() and landconflict() in lib/cardland.sh. Each reads and sets card()'s locals (bash's
# dynamic scope) and says in go what follows. card() sets go=end before each: a step that returns leaving it so ends
# the card, with the step's exit as card()'s; else '' (the next step), next (the next pass of the review loop),
# landed (a batch or its own landing landed it) or out (its landing did not land: landconflict()).
# shellcheck disable=SC2034 # locals that only its steps in lib/cardland.sh, or settle() (lib/claim.sh), read
card() { # <card> <issue> [<branch> <tip>]
  local c=$1 n=$2 br=${3:-} tip=${4:-} wt=$CARDS/$1 issue b t pass res vis unclear msg d err isfu='' dec='' why ups='' left='' rebased='' tfix='' last rc sec out merged away
  local from='' fromk='' was='' mode='' note='' old more base inh='' rv=$REVIEW yesfrom='' extra
  local yfile='' # yfile: ybase is written beside the worktree, as .approvals
  local me cc seen=none sect='' nyes=0 heldto='' vmode='' ybase rules sprompt hdr fin='' finrev earlier='' prv='' caught='' owe tsess='' cmsg rtr rrev ro='[]' pro='[]' rmsg ported='' kp='' mates=() t5=() trc ran apart='' back='' rf sf='' sk='' mk='' pk='' pt='' ps=''
  local vrule=on rounds=0 rep hard refix='' waitsec=0 behind='[]' cpid chead cseen own kept='' docpass='' docs parsecheck='' pfix='' # waitsec, behind: the seconds it has waited on other cards, and those cards (settle())
  local sv an ex ids fl # sv, an, ex: a review's survived findings, its answers and the lines it cites (donewhen.sh repeats(), answers(); review.sh excerpts()); ids, fl: the fix round's numbered findings and its lines (donewhen.sh numbered(), fixlines())
  local grown='' # grown: the judge was asked about the size of its change (growcheck(), lib/slices.sh)
  local rline='' ended='{}' stop='' finend='{}' earlyend='' fe # rline, ended, stop: a review's line before it is written, and why the loop ended (loopstop()); finend, earlyend, fe: why the loop of a port's kept review ended, and the stop the filed line carries
  local lfix='' cfix='' # lfix: the change the landing gate's lint fix left, its cardpatch() (lintgate(), lib/lint.sh); cfix: the BLOCKED lines its persisted-contract fix sessions were given, one a line (contractgate(), lib/contract.sh)
  local fixtree='' rtree='' ftree='' # ftree: the tree the first review read whose judge ruled a finding (judgeruled()), kept for the card (a later ruling does not replace it, or it would hide a fix round made before that one), which the judge is given beside fixtree, to tell a finding on lines a fix round changed after a ruling (judgefindings()); fixtree: the tree before the last fix round, which holds the lines that fix deleted (excerpts()); rtree: the one the last review read, which a reused review reads again
  local after rland='' rlrev='' rlfind='' tland='' # tland: the kept review is that of a card blocked in its Test step, whose P1 has had its fix round (resumeplan(), afterreview()); after: what follows a review (afterreview()); rland: the card lands its kept patch on its kept review, a retry by review-land's (resumeplan()); rlrev: that kept review; rlfind: the finding its block names
  local priv privfix=0 p1 p1fix='' # priv: a last-review finding that is a privacy hit in the card's own change (privown()); privfix: the fix rounds given for such hits (PRIVFIXES at most); p1: the P1 finding that gets one fix round, p1fix: that round was given
  local fixed=0 # fixed: the fix sessions this card has run, review fixes and test fixes; the second and every later one runs one effort level up (session1())
  local tmain='' # tmain: set once a failed test step has fitted the card onto a main that had moved (#582)
  local voids=0 # voids: the test runs in a row that gave no result (voidrun())
  local held # held: its test step waited for main or the machine (mainred.sh mainwait(), holdwait())
  local route # route: where a failed test run goes (testroute())
  local cr # cr: a failed test line's carried and partial part (testlist.sh carriedrec())
  local mainsec=0 mwon # mwon: main's commit and the cases it waits on there (mainred.sh mainwait()); mainsec: the seconds it has waited for main to change or for the machine (mainwaited(), holdwaited()); its landed line's waitSec adds them to waitsec
  local repaired='' lane queued='' # repaired: the repair lane passed its test step (mainred.sh repairlane()), or a main-red fix card's failures are other entries' (cardland.sh redelse()), saying how; lane: its exit; queued: another card had the landing turn (gather()), so it waits for the next batch
  local ins rr # ins, rr: the review's instructions, and fix when it reviews the fix alone (donewhen.sh rereview()), reused when the last review stands (reusable())
  local ph pf pb # ph, pf: the hash and the files of the change's lint policy diff (lintpolicy()); pb: the body kept by the card it resumes
  local shared sb # shared: 1 when this test step runs its shared test files again (sharedtests()), 2 when they ran again before for the change it holds; sb: the commit its last tests ran on
  local go sx # go, sx: what the step that returned says follows (above), and its exit
  # shellcheck disable=SC2034 # SEATCARD is read by seat() in lib/control.sh
  local SEATCARD=$n # every step of this card, its split check too, runs on the seats the control record keeps for its issue (seat(), lib/control.sh)
  go=end; cardtree; sx=$?; [ "$go" != end ] || return $sx
  [ -n "$br" ] || [ "$n" = 0 ] || splitcheck "$c" "$n" || { clean "$wt"; return 0; }
  # shellcheck disable=SC2034 # PICK and PICKCARD are read by line() in lib/records.sh, PICKSEAT and PICKSEATS by seat() in lib/control.sh
  local PICK='' PICKCARD='' PICKSEAT='' PICKSEATS='' # the card's pick (modelpick(), lib/modelpick.sh), which line() puts on each of its lines, a trial's builder and the promoted reviewer and judge
  [ -n "$br" ] || [ "$n" = 0 ] || modelpick "$c" "$n"
  go=end; cardopen; sx=$?; [ "$go" != end ] || return $sx
  go=end; cardbuild; sx=$?; [ "$go" != end ] || return $sx
  msg=$(cardsubject "$c" "$issue") || { block "$c" "$n" "$wt" "the engine could not make the card's commit message, or its privacy check could not be made, so nothing landed"; return; }
  # A branch that names no issue lands under its own first commit's subject, which names no issue to close.
  [ "$n" != 0 ] || [ -z "$br" ] || msg=$(jq -r --arg c "$c" --arg b "$br" '"\(.title)\n\nConveyor card \($c), branch \($b)"' <<<"$issue")
  prv=$'\n\n'"$PORTREVIEW"$'\n'"The difference is the file $wt.port."; kp=$fromk/$from.patch
  # A NO-GO is fixed and reviewed again; a NO-GO on a last review (review MAX_REVIEWS, counting the rounds a retried
  # card carries, or the one review after a landing conflict, a test fix or the landing gate's lint fix, or one that
  # repeats a finding after its fix, or from review 2 on one whose findings are all new and all P2 or P3: loopstop() new-p2) lands with follow-ups,
  # after one fix round and a review on a P1, or after up to PRIVFIXES fix rounds on a privacy hit in its own change (afterreview()).
  # A GO card whose landing conflicts goes round once more: rebase, review. A finished loop whose landing still conflicts is ported once, as `retry` would port it.
  # Whatever the review, the changed tests pass here before anything is filed or landed.
  while pass=$((${pass:-0} + 1)); do
    go=end; cardreview; sx=$?; [ "$go" != end ] || return $sx
    go=end; cardfix; sx=$?; case $go in end) return $sx ;; next) continue ;; esac
    go=end; cardready; sx=$?; case $go in end) return $sx ;; next) continue ;; esac
    go=end; cardlanding; sx=$?; case $go in end) return $sx ;; next) continue ;; landed) break ;; esac
    go=end; landconflict; sx=$?; [ "$go" != end ] || return $sx
  done
  clean "$wt"
}
# The worktree, with a branch's tip merged in, before anything asks GitHub for the issue (splitcheck(), modelpick(), cardopen()): a stray staged change blocks the card at once, not when GitHub answers. go: ''.
cardtree() {
  err=$(git worktree add -q --detach "$wt" "refs/heads/$BRANCH" 2>&1) || { block "$c" "$n" "$wt" "worktree: $err"; return; }
  [ -z "$br" ] || err=$(git -C "$wt" merge -q --squash "$tip" 2>&1) \
    || { block "$c" "$n" "$wt" "worktree: branch $br does not merge into main as it stands; rebase it on main and land it again: ${err:0:400}"; return; }
  # A staged change in the new worktree of main (a checkout hook's), before a kept patch is applied (resumeplan()), is no work of this card: it stops.
  [ -n "$br" ] || err=$(git -C "$wt" diff --cached --name-only 2>&1) || { block "$c" "$n" "$wt" "worktree: the engine could not read the staged change of the new worktree: ${err:0:400}"; return; }
  [ -n "$br" ] || [ -z "$err" ] || { block "$c" "$n" "$wt" "worktree: the new worktree already holds a staged change that is no kept work of this issue: $(paste -sd ' ' - <<<"$err" | cut -c 1-400)"; return; }
  go=''
}
# The issue a card is built and reviewed against, as gh prints it. A card of issue 0 (no GitHub issue): its local record stands in, a branch's (branchissue()), a main-red fix card's (redissue()) or a Tests page card's
# (testcardissue(), lib/testaction.sh). None is split for its size (splitcheck() above); testpick() picks a Tests page card only once released and the cards it depends on by card id landed, and retries it once.
# A branch landed as a split's slice (slicetake(), lib/lane.sh) is held to the slice's own entry, its Done-when items, as the slice's card would be.
cardissueof() { # <card> <issue> <branch or ""> <tip>
  if [ -n "$3" ] && [ "$2" = 0 ]; then testcardissue "$1" || branchissue "$3" "$4"; elif [ "$2" = 0 ]; then redissue "$1" || testcardissue "$1"; else gh issue view "$2" --json number,title,body,labels,milestone; fi
}
# The worktree's dependencies and the brief (sprompt), with the resume of a retried card (resumeplan()). go: ''.
cardopen() {
  # Its issue's retried lines, read by prior() and carried(), kept in this shell (stdb, lib/records.sh).
  [ "$n" = 0 ] || stdb ask issue retried "$n" >/dev/null 2>&1 || :
  issue=$(cardissueof "$c" "$n" "$br" "$tip") || issue=''
  # The control record's rule "visible changes need the owner's yes" (yesrule()), as the card starts. Off, nothing below
  # waits for or asks for a `Visible change approved:` line: no condition, section or inherited yes is held to, the
  # brief and the review leave the approval out, and a visible change lands as any change does.
  yesrule "${CARDCTL:-}" || { vrule=off; rv=$REVIEWOFF; }
  # The test file of a speed-up or Optimize card (a bug card whose issue speedproof.sh speedfile() names): its build is told the
  # target (speedproof.sh speedbrief()).
  [ -z "$issue" ] || ! jq -e --arg t "$TYPE" 'any(.labels[]?; .name == $t)' <<<"$issue" >/dev/null || sf=$(speedfile "$issue") || sf=$(speedfile "$issue" "$OPTIMIZE") || sf=$(speedfile "$issue" "$REWRITE") || sf=$(speedfile "$issue" "$SPLIT") || sf=''
  # The visible-change gate before the build: seen, nyes, sect, ybase, heldto, vmode and yfile (visplan()).
  visplan
  # A follow-up whose parent (or one up its chain) has the owner's yes (inherit()); one with no GitHub issue too (its stand-in's body opens as an issue's).
  [ -z "$issue" ] || [ "$vrule" = off ] || inh=$(inherit "$issue")
  # The resume of a retried card: how it takes up the kept patch of its issue's blocked cards.
  resumeplan || { block "$c" "$n" "$wt" "$err"; return; }
  # A main-red fix card commits, with its fix, the links from the files of the landing that broke a case to its test
  # file (issue 598: mainred.sh testlinks()). After the check above that the new worktree holds no staged change.
  testlinks "$c" "$wt" || { block "$c" "$n" "$wt" "the test links of the main-red record could not be staged in .conveyor/test-links.json"; return; }
  # ybase is kept beside the worktree (yesbase() reads it for the next card) once the checks of the new worktree have
  # passed: a card that stops on one of them keeps no count.
  [ -z "$yfile" ] || printf '%s\n' "$ybase" > "$wt.approvals"
  [ -z "$note" ] || echo "conveyor: card $c: $note"
  # The worktree line is written before the linking, so the linking's seconds are those of the deps line.
  # The weekly limit as the card begins: asked for here (at most every LIMIT_TTL seconds), guard or no guard,
  # so the first card of a loop has its before reading too. The landed, closed or blocked line asks again for after.
  # The accounts the card runs on are the control record's as it starts, for the whole card: the worktree line names
  # them (account; reviewAccount when its reviewer is Claude and reviews on another; none for the default login).
  # The loop's card starts on the record its guard read (CARDCTL), which pick found unchanged in its accounts.
  cc=${CARDCTL:-}; [ -n "$cc" ] || cc=$(ctl 2>/dev/null)
  [ -z "$cc" ] || { ACCT=$(ctlacct "$cc") && RACCT=$(cardaccts "$cc" | sed -n 2p); [ "$RACCT" != "$ACCT" ] || RACCT=''; }
  reading >/dev/null 2>&1
  # The card's process (p_started: with pid, it names it), for health to tell a card whose process is gone; left out
  # when ps does not say when it started. Read here: inside $(...) BASHPID is that subshell's.
  # The engine commit the card runs on to its end (RAN), for what built what and for prune() (lib/install.sh).
  me=$BASHPID
  record "$c" "$n" worktree ok "$(jq -cn --arg r "$note" --argjson p "$me" --arg t "$(p_started "$me")" --argjson e "$(ending)" --arg a "$ACCT" --arg ra "$RACCT" --arg g "$RAN" \
    '{reason:$r} + (if $t == "" then {} else {pid:$p, started:$t} end) + (if $a == "" then {} else {account:$a} end) + (if $ra == "" then {} else {reviewAccount:$ra} end) + (if $g == "" then {} else {engine:$g} end) + $e')"
  err=$(deps "$wt") || { block "$c" "$n" "$wt" "$NODEPS: ${err:0:400}"; return; }
  record "$c" "$n" deps ok
  hdr=$(header "$vrule" 2>&1) || { block "$c" "$n" "$wt" "brief: the engine could not read the project pack $PACK: ${hdr:0:400}"; return; }
  [ -n "$issue" ] && b=$(brief "$c" "$issue" "$hdr") \
    || { block "$c" "$n" "$wt" "brief: the engine could not make the brief. There are three possible causes. gh issue view failed. Or the engine could not read the project pack. Or the rulings log of the pack is missing or has a line that does not parse"; return; }
  rules=$(cardrules "$issue") || { block "$c" "$n" "$wt" "brief: ${rules:0:400}"; return; }
  err=$(cardsettings "$wt.settings" 2>&1) || { block "$c" "$n" "$wt" "brief: the engine could not make the card settings from $CARD_SETTINGS and the hooks.json of the pack: ${err:0:400}"; return; }
  [ -z "$br" ] || b+=$'\n\n# This card skipped the build\nIts change is the change of branch '"$br"$' against main. It is already in this worktree, staged: review that change, or fix what you are told to fix in it. Do not build it again.'
  [ "$n" = 0 ] || for more in "$(carried "$n" "$wt")" "$(healsbrief "$n")"; do [ -z "$more" ] || b+=$'\n\n'"$more"; done
  # A follow-up whose parent (or an issue up its chain) has the owner's yes: the brief says so, and the reviewer
  # is asked whether this change stays inside that yes.
  [ -z "$inh" ] || { b+=$'\n\n'"$(inherited_brief "$inh")"; rv=$REVIEW$'\n\n'$INHERIT; }
  # Held to the section approved before the build: the build, fix and review briefs carry it and the approval
  # line, and the reviewer answers matches or differs.
  if [ -n "$heldto" ]; then
    b+=$'\n\n# The approved visible change\nThe owner approved, before this build, what customers or staff will see. Build that visible change, no more and no less: the review holds the change to it, and a change that shows more, less or other than it, wording included, stops for the owner again. The section, as approved:\n'"$sect"$'\nThe approval line:\n'"$(grep -m 1 '^Visible change approved:' <<<"$(jq -r '.body // ""' <<<"$issue")" | tr -d '\r')"
    ! conditional "$issue" || b+=$'\nThat yes gives a condition: build it, and hold the change to it.'
    rv+=$'\n\n'$HELD
  fi
  # The finding kinds the judge always accepts: the reviewer tags a finding of one with its kind (KINDS).
  old=$(judgeon) || old='[]'
  [ "$old" = '[]' ] || rv+=$'\n\n'${KINDS//'<kinds>'/"$(jq -r 'join(", ")' <<<"$old")"}
  more=$(trailerbrief "$wt") || { block "$c" "$n" "$wt" "brief: the engine could not read the commit trailers of the project pack"; return; }
  b+=$'\n\n'"$more"$'\n\n'"$(precheckbrief)"
  more=$(lintbrief) || { block "$c" "$n" "$wt" "brief: the engine could not read the lint field of the project pack"; return; }
  [ -z "$more" ] || b+=$'\n\n'"$more"
  sprompt=$(cardprompt "$c" "$hdr" "$rules" "$b")
  d=$(jq -r '.body // ""' <<<"$issue" | sed -nE 's/^Follow-up depth: ([0-9]+)[[:space:]]*$/\1/p' | head -n 1)
  [ ${#d} -le 3 ] && d=$((10#${d:-0})) || d=''
  record "$c" "$n" brief ok "$([ -z "$d" ] && echo '{}' || echo "{\"depth\":$d}")"
  go=''
}
# The findings the resumed session of a retried card is told came back (donewhen.sh again()), in card()'s rep: those the kept
# review repeats (donewhen.sh repeats()) when its verdict stands after the last of its fix rounds (<worktree>.rounds/answered,
# cardreview(): a reused review's too), else none. It reads card()'s wt. Bugs: it compared the last round's number with the
# reviews carried, which a port's round numbers outgrow (roundno()); then it read rounds/told, which a reused review lacks.
keptrep() {
  rep=''; [ "$(verdict "$wt.review" 2>/dev/null)" != NO-GO ] || [ ! -e "$wt.rounds/answered" ] || rep=$(repeats "$wt")
}
# Ends a main-red fix card as closed, its reason the first line of <worktree>.unfixed (bugproof.sh redgreen(), redproof()): main is no
# longer red for its cases. Its change is dropped: the worktree goes. A closed line that cannot be written (bugproof.sh redclosed(): a case joined its entry as they ran, too) blocks the card, its reason without the result's "so the card closes" clause.
greenclose() { # <card> <issue number> <worktree>
  local t out err=''
  t=$(head -n 1 "$3.unfixed") && out=$(line "$1" "$2" closed ok "$(jq -cn --arg r "$t" --argjson e "$(ending)" --argjson w "$(waited)" '{reason: $r} + $e + $w')") && err=$(locked redclosed "$1" "$out") \
    || { t=$(head -n 1 "$3.unfixed" 2>/dev/null); t=${t/, so the card closes as already done/}; block "$1" "$2" "$3" "build: ${t%.}. ${err:-The engine could not write the closed line.}"; return; }
  clean "$3"
}
# The build, then the checks a bug card's change must pass before its review (or, on a retry with no build, those of
# one of the Board's fix issues). go: '', or the card ends: blocked, or closed as already fixed on main.
# shellcheck disable=SC2034 # it declares no variable of its own: mk, as the rest, is card()'s, read in lib/cardland.sh
cardbuild() {
  if [ -z "$br" ] && [ "$mode" != land ] && [ "$mode" != review ]; then
    more=''
    [ "$mode" != session ] || more=$'\n\n# This card resumes blocked card '"$from"$'\nThe staged change in this worktree is no leftover: it is the kept work of card '"$from"$', an earlier card of this issue, applied to main as it stands. That card was blocked: '"${was:0:600}"$'\nThat change is yours now: keep, change or drop each part of it. Start from it, not from nothing: finish what the issue asks, fix the findings carried over above, and leave alone what is already right. The checks at the end (the bug-card check too) judge the whole staged change as this card\'s, that card\'s tests included.'
    if [ "$mode" = port ]; then
      base=$(git rev-parse -q --verify "$(cat "$fromk/$from.base" 2>/dev/null)^{commit}" 2>/dev/null) && base="commit $base" || base='a commit that was not recorded'
      more=$'\n\n# This card brings the change of blocked card '"$from"$' onto main\nThat card\'s change is kept as a patch, and it no longer applies to main as it stands. Do not build the change again from nothing. The patch is the file '"$fromk/$from.patch"$', built on '"$base"$'. Bring that change onto main as it is now, in this worktree, and resolve the conflicts: `git apply --3way --index` on that file applies what still fits and leaves conflict marks in the rest, and `git diff <that commit> HEAD -- <file>` shows what main changed in a file since. Read the patch in parts if it is large. Keep what main changed and what the card changed. '
      if [ -n "$fin" ]; then more+="Change nothing else: that change finished its review loop, and one review of this port alone follows. The findings carried over above are not this session's to fix: that loop fixed them or files them as follow-ups when this card lands."
      else more+='Then finish what the issue asks and fix the findings carried over above.'; fi
      more+=" The card was blocked: ${was:0:600}"
    fi
    [ "$mode" != stale ] || more=$'\n\n# The kept patch of blocked card '"$from"$' cannot be read\nBuild the issue\'s change on main as it is now. The patch is the file '"$fromk/$from.patch"$': git cannot parse it, so it was not applied; read what you can of it there for what was already worked out. The card was blocked: '"${was:0:600}"
    keptrep; [ -z "$rep" ] || more+=$'\n\n'"$(again "$rep")"
    [ -z "$sf" ] || { t=$(speedbrief "$c" "$wt" "$sf" "$issue") && more+=$'\n\n'"$t"; } \
      || { block "$c" "$n" "$wt" "brief: the engine could not read the project pack for the split allowance of $sf"; return; }
    # A main-red fix card (its entry in the main-red record names it, with no push block: redfix.sh pushred(), whose check its cases passing does not make pass)
    # whose cases all pass on main, in each of the flaky rule's runs (bugproof.sh redgreen()), closes as already done before its build session starts, as redproof() closes one after it.
    if jq -e --arg c "$c" 'any(.reds[]?; .card == $c and .push == null)' "$MAINRED" >/dev/null 2>&1 && redgreen "$c" "$wt"; then greenclose "$c" "$n" "$wt"; return; fi
    more+=$(startbrief "$wt" "$issue" 2>/dev/null) || :; began "$c" "$n" build # startbrief() gives its own blank line, or nothing
    redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt$more") || { BLOCKCLASS=$(failclass "$t") block "$c" "$n" "$wt" "build: $t"; return; }
    checked "$c" "$n" "$wt" "$issue" "$sprompt" build "$t" || return
    # A bug card (the pack's type label): the tests it adds or changes must fail on main's code without the fix
    # (bugproof.sh bugproof(); a change that selects no test of its own is proved by the test files its issue's Done-when names,
    # and goes on unchecked when it names none). When none does, or it adds none, it goes back to its build session once, told why; when the check
    # still does not hold after it, the card is blocked with that reason and no review. The review is shown the
    # check's result. A bug card that speeds up one test file (speedproof.sh speedfile()) is checked by speedproof.sh speedproof() instead, and one
    # that optimizes one (speedproof.sh speedfile() with OPTIMIZE, REWRITE: Rewrite as a direct check, #778, or SPLIT: Split it, #1330) by speedproof.sh optproof(): when the change does not do what its issue's verdict
    # asks, its file costs more than its recent runs allow, a split takes more CPU seconds than it may, or a file does not pass, the card is blocked with that reason and no review (here and, as below, before each later review: pt), its blocked line
    # carrying the check's version (SPEEDCHECK, lib/speedproof.sh). One that fixes the failures of one (speedproof.sh speedfile() with
    # FIXFAILS) is checked by speedproof.sh steadyproof(): when its file fails in one of its runs in a row, the card is blocked naming that run, with no review.
    # So are the Board's other fix issues (#189): Fix the waiting (WAITFIX), Fix hollow cases (HOLLOWFIX), Delete it (DELFILE) and Make it run alone (#190; ALONEFIX, before Make it run, whose title starts the same) by speedproof.sh fixproof() (pk), here and again before each later review on a change
    # a fix or rebase session made (pt: the tree it last held on), and Make it run (MAKERUN) by speedproof.sh runproof() now and by speedproof.sh ranproof() once its test step passed (mk).
    if ! jq -e --arg t "$TYPE" 'any(.labels[]?; .name == $t)' <<<"$issue" >/dev/null; then :
    elif sf=$(speedfile "$issue"); then
      speedproof "$c" "$wt" "$issue" "$sf" || { SPEEDCHECKED=$SPEEDCHECK BLOCKCLASS='proof check' block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    elif sf=$(speedfile "$issue" "$OPTIMIZE") || sf=$(speedfile "$issue" "$REWRITE") || sf=$(speedfile "$issue" "$SPLIT"); then
      sk=$OPTREVIEW; optproof "$c" "$wt" "$issue" "$sf" || { SPEEDCHECKED=$SPEEDCHECK BLOCKCLASS='proof check' block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }; pt=$(git -C "$wt" add -A && git -C "$wt" write-tree); ps=$(stabilised "$wt")
    elif sf=$(speedfile "$issue" "$FIXFAILS"); then
      sk=$STEADYREVIEW; steadyproof "$c" "$wt" "$sf" || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    elif { pk=$WAITFIX sk=$WAITREVIEW; sf=$(speedfile "$issue" "$pk"); } || { pk=$HOLLOWFIX sk=$HOLLOWREVIEW; sf=$(speedfile "$issue" "$pk"); } \
      || { pk=$DELFILE sk=$DELREVIEW; sf=$(speedfile "$issue" "$pk"); } || { pk=$ALONEFIX sk=$ALONEREVIEW; sf=$(alonefile "$issue"); } || { pk='' sk=''; false; }; then
      fixproof "$c" "$wt" "$issue" "$sf" "$pk" || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
      pt=$(git -C "$wt" add -A && git -C "$wt" write-tree)
    elif sf=$(speedfile "$issue" "$MAKERUN"); then
      sk=$RUNREVIEW; mk=$sf; runproof "$wt" "$sf" || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    else
      # A run on main that gave no result for a test file, twice (bugproof.sh bugproof() exit 2), is blocked with that reason: a
      # build session cannot repair the runner. A main-red fix card is proved by main's failing cases (bugproof.sh redproof()):
      # one that does not hold is blocked with that reason (exit 2), and one whose every case passes on main without
      # its change (exit 3) closes as already done, as nochange() closes a card, its change dropped.
      # bugstep() gives what each exit of the check leads to.
      bugproof "$c" "$wt" "$issue"; trc=$(bugstep $?)
      if [ "$trc" = close ]; then
        greenclose "$c" "$n" "$wt"; return
      fi
      [ "$trc" != block ] || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
      if [ "$trc" = build ]; then
        began "$c" "$n" build
        redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt$more"$'\n\n'"${BUGBUILD//'<why>'/"$BUGWHY"}"$'\n'"$(<"$wt.unfixed")") || { block "$c" "$n" "$wt" "build: $t"; return; }
        checked "$c" "$n" "$wt" "$issue" "$sprompt" build "$(jq -c --arg r "$BUGWHY" '. + {reason: $r}' <<<"$t")" || return
        bugproof "$c" "$wt" "$issue"; trc=$(bugstep $? again)
        [ "$trc" != block ] || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
        [ "$trc" != unproved ] || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "build: $BUGWHY"$'\n'"$(<"$wt.unfixed")"; return; }
      fi
    fi
  elif [ -z "$br" ] && [ -n "$sf" ] && { speedfile "$issue" "$OPTIMIZE" || speedfile "$issue" "$REWRITE" || speedfile "$issue" "$SPLIT"; } >/dev/null 2>&1; then
    # A retry with no build (land, review: its kept patch, after the owner's yes) of an Optimize, Rewrite or Split card, its file in sf from cardopen(): its kept patch passed optproof() after its build and before each review of its loop, so it is not run here (a stabilise check reads the build's reply, which a retry has not): its tree and STABILISED lines now are what a later fix round is checked against (pt, ps; cardreview()).
    # Bugs: a retry under review whose fix made the split slower went on to review unchecked; this was a branch of the one below, which cardopen()'s sf kept it out of.
    sk=$OPTREVIEW pt=$(git -C "$wt" add -A && git -C "$wt" write-tree); ps=$(stabilised "$wt")
  elif [ -z "$br" ] && [ -z "$sf" ] && jq -e --arg t "$TYPE" 'any(.labels[]?; .name == $t)' <<<"$issue" >/dev/null 2>&1; then
    # A retry with no build (land, review: its kept patch, after the owner's yes) of one of the Board's fix issues (#189) is checked as after a build: the kept change lands only on the proof of what lands (pk, pt), and a Make it run card only when its test step ran its file (mk).
    if { pk=$WAITFIX sk=$WAITREVIEW; sf=$(speedfile "$issue" "$pk"); } || { pk=$HOLLOWFIX sk=$HOLLOWREVIEW; sf=$(speedfile "$issue" "$pk"); } \
      || { pk=$DELFILE sk=$DELREVIEW; sf=$(speedfile "$issue" "$pk"); } || { pk=$ALONEFIX sk=$ALONEREVIEW; sf=$(alonefile "$issue"); } || { pk='' sk=''; false; }; then
      fixproof "$c" "$wt" "$issue" "$sf" "$pk" || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "$mode: $(<"$wt.unfixed")"; return; }
      pt=$(git -C "$wt" add -A && git -C "$wt" write-tree)
    elif sf=$(speedfile "$issue" "$MAKERUN"); then
      sk=$RUNREVIEW; mk=$sf; runproof "$wt" "$sf" || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "$mode: $(<"$wt.unfixed")"; return; }
    fi
  fi
  go=''
}
# A review's lines (<card> <issue> <result> <the review line>): the judge's line (step judge, of review: the judge's model, effort, sec, tokens, usage and stats; result failed with its reason when the judge failed; none when the line has no judge with a model: no finding, or a reused review), then the review line, which stays the newest of the pass. The review line's judge field is unchanged: replay and the snapshot read it.
reviewlines() { local j; j=$(jq -c '.judge | objects | select(.model | strings | . != "") | {of: "review"} + with_entries(select(.key | IN("model", "effort", "sec", "tokens", "usage", "stats"))) + (if .failed then {reason: (.failed | tostring)} else {} end)' <<<"$4" 2>/dev/null); [ -z "$j" ] || record "$1" "$2" judge "$(jq -r 'if .reason then "failed" else "ok" end' <<<"$j")" "$j"; record "$1" "$2" review "$3" "$4"; }
# One pass's review: the review gate and the checks before a review, then a review session and its judge, or the
# review it reuses or keeps, its verdict in res and its line, still to be written, in rline. go: ''.
# shellcheck disable=SC2034 # it declares no variable of its own: docpass, as the rest, is card()'s, read in lib/cardland.sh
cardreview() {
  redbrief "$c" "$n" "$br"
  # A staged change that is no change (emptychange(): a main-red fix card's links alone too) goes to nochange().
  ! emptychange "$c" "$n" "$wt" "$br" || { nochange "$c" "$n" "$wt" "$sprompt"; return; }
  # The review gate (lintgate(), lib/lint.sh): a fix of lint findings changed the change, so a kept review, a kept patch's review (land) and a test pass no longer stand for it, and the review of this pass reads all of it; a fix that left no change goes to nochange() as above.
  trialflag "$wt" # a trial card's pick names the pipeline files its change touches (lib/push.sh): on the gate's lines and its fix's, then on what that fix left
  lintgate "$c" "$n" "$wt" "$issue" "$sprompt" "$br"; case $? in 1) return ;; 2) ! emptychange "$c" "$n" "$wt" "$br" || { nochange "$c" "$n" "$wt" "$sprompt"; return; }; trialflag "$wt"; kept=''; docpass=''; refix=''; [ "$mode" != land ] || mode='' ;; esac
  if [ "$mode" = land ]; then
    # Landing from the kept patch: the kept review is this change's review, and it let the card land (a GO, or a
    # last review's NO-GO), so there is no review here and no review line. A review after this is this card's first.
    res=$(verdict "$wt.review"); vis=$(visible "$wt.review" any); pass=0
  elif [ -n "$kept" ]; then
    # Back from the landing rebuild with its change outside documentation (*.md) the one its last review read: that
    # review stands (kept), with no review session and no review line, and no review is counted.
    res=$(verdict "$wt.review"); vis=$(visible "$wt.review" "$vmode"); pass=$((pass - 1)); kept=''
  else
    # Same-file cards review in parallel: no claim and no wait before a review. They line up only to land (at
    # settle() below), and a card is reviewed again there only when an earlier landing changed the lines it changed,
    # or when an ordered card went past it and main moved meanwhile (then even when its patch still applies).
    # A change grown past the pack's split.growFiles (growcheck(), lib/slices.sh): asked once a card; split, its one
    # fix session dropped the slices' parts, so this review reads the whole change, not that fix alone, and the
    # review gate runs again on what that fix left; a change it left empty goes to nochange(), and a trial card's pipeline files are those it left, on the gate's lines too.
    if [ -z "$grown" ] && [ -z "$br" ]; then growcheck "$c" "$n" "$wt" "$issue" "$sprompt"; case $? in 1) return ;; 2) refix=''; git -C "$wt" add -A 2>/dev/null; trialflag "$wt"
      lintgate "$c" "$n" "$wt" "$issue" "$sprompt" "$br"; [ $? != 1 ] || return; docpass=''; ! emptychange "$c" "$n" "$wt" "$br" || { nochange "$c" "$n" "$wt" "$sprompt"; return; }; trialflag "$wt" ;; esac; fi
    # A fix or rebase session changed a Fix the waiting, Fix hollow cases, Delete it or Make it run alone card (pk), or an Optimize, Rewrite or Split one (its STABILISED lines too, ps): its check runs again on what this review reads (speedproof.sh rechecked()), and the card is blocked when it no longer holds.
    if [ -n "$pk$pt" ] && rechecked "$wt" "$pt" "$pk" "$ps"; then
      if [ -n "$pk" ]; then fixproof "$c" "$wt" "$issue" "$sf" "$pk"; else optproof "$c" "$wt" "$issue" "$sf"; fi || { SPEEDCHECKED=$([ -n "$pk" ] || echo "$SPEEDCHECK") BLOCKCLASS='proof check' block "$c" "$n" "$wt" "review $pass: $(<"$wt.unfixed")"; return; }
      pt=$(git -C "$wt" add -A && git -C "$wt" write-tree); [ -n "$pk" ] || ps=$(stabilised "$wt")
    fi
    began "$c" "$n" review
    # The review sees the card's commit trailers beside the diff, and the D<n> lines of the last checked reply.
    more=$(reviewseen "$wt" "$(if [ -n "$sk" ]; then echo "$sk"; elif [ -n "$sf" ]; then echo "$SPEEDREVIEW"; else echo "$BUGREVIEW"; fi)") \
      || { block "$c" "$n" "$wt" "review $pass: the engine could not read the commit trailers of the card"; return; }
    # What this review reads, kept on its line: the staged change, the main commit and what it is shown beside the
    # diff (seen: the trailers and D<n> lines above). A review due on the same three as the card's last review is
    # that review again (reusable()), with no review session. Not the one review of a port, which reads the port's
    # difference, not the change alone.
    cpid=$(cardpatch "$wt"); chead=$(git -C "$wt" rev-parse HEAD 2>/dev/null); cseen=$(git -C "$wt" hash-object --stdin <<<"$more")
    if [ -z "$fin" ] && t=$(reusable "$c" "$cpid" "$chead" "$cseen"); then
      echo "conveyor: card $c: its staged change, main, trailers and D<n> lines are those of its last review: that review stands, with no review session"; fixtree=$rtree rr=reused
    else
      # The one review of a port reads what the port changed: the kept patch against the staged change.
      if [ -n "$fin" ]; then
        finrev=$(<"$wt.review")
        diff -u --label kept --label ported <(sed '/^index /d' "$kp") \
          <(git -C "$wt" diff --cached --binary --no-renames | sed '/^index /d') > "$wt.port"
        [ $? -le 1 ] || { rm -f "$wt.port"; block "$c" "$n" "$wt" "review $pass: the engine could not compare the port with the kept patch"; return; }
      fi
      # The review right after a fix of review findings also sees what that fix was told and changed (donewhen.sh rereview()):
      # not part of seen, so a fix that changed nothing still reuses the last review. It reviews the fix alone, its
      # instructions opening with FIXREVIEW in place of REVIEWHEAD, unless the fix touches more than the pack's
      # review.rereviewWhole share of the change's lines (donewhen.sh fixonly()), or a retried card's (no fixtree: its session may have changed more): then the whole change.
      ins=$rv${fin:+$prv}; rr=''
      [ -z "$refix" ] || [ -z "$fixtree" ] || [[ $ins != "$REVIEWHEAD"* ]] || ! fixonly "$wt" "$refix" || { rr=fix; ins=$FIXREVIEW${ins#"$REVIEWHEAD"}; }
      redbrief "$c" "$n" "$br"; t="the engine could not write the re-review section"; { [ -z "$refix" ] || more+=$'\n\n'"$(rereview "$c" "$wt" "$refix" "$rr")"; } \
        && t=$(reviewed "$wt" "$sprompt$more" "$ins"); rc=$?; rm -f "$wt.port"
      [ $rc = 0 ] || { block "$c" "$n" "$wt" "review $pass: $t"; return; }
      # The judge (judged()): a finding it declines is no finding from here on, and a review left with none is a GO; the issue tells it whether the card is a follow-up, and its area. While it runs, <worktree>.reviewed holds the review's fields (its usage; began() drops it), as a bench reads its cost (SWE_LIVES).
      redbrief "$c" "$n" "$br"; printf '%s\n' "$t" > "$wt.reviewed"; t=$(judged "$c" "$n" "$wt" "$sprompt" "$t" "$issue" "$fixtree" "${ftree:-}"); [ -n "${ftree:-}" ] || ! judgeruled "$t" || ftree=$(git -C "$wt" write-tree)
      # The P3 findings it leaves, with the rule P3 off, are listed only (minor()).
      minor "$wt"
    fi
    refix=''
    res=$(verdict "$wt.review"); vis=$(visible "$wt.review" "$vmode"); unclear=''
    [ -n "$vis" ] || { [ "$res" = none ] || unclear=": it does not hold exactly one USER-VISIBLE line, written as asked"; res=none; }
    [ "$res" = none ] || [ ! -d "$wt.rounds" ] || { : > "$wt.rounds/answered"; [ "$rr" = reused ] || : > "$wt.rounds/told"; } # a review with a verdict answered the fix rounds before it, until the next round (donewhen.sh rounded()): told, which resumeplan() reads, not for a reused one, written before the round (bug: a retry's first review lost the round's finding ids and diff); answered, which keptrep() reads, for a reused one too, as the loop blocks on its repeats
    # A NO-GO's line names the findings that came back after a fix round told to fix them (survived: id, rounds), for the Board.
    # Every review's line keeps its answers on the findings fix rounds were told, each beside its first location
    # and proof (donewhen.sh answers()), so a review that blocks or ends the loop keeps them too.
    sv='[]'; [ "$res" != NO-GO ] || sv=$(repeats "$wt" | jq -sc 'map({id, rounds})')
    an=$(answers "$wt")
    # doneWhenHolds: the D<n> its `DONE-WHEN: D<n> holds` lines name, which the reason leaves out (UNRECORDED); the
    # Board reads them on demand (history donewhen). excerpts: the lines its findings cite, from the tree it read
    # (excerpts(), lib/review.sh), which the Board reads on demand too (history excerpts); after a fix round, also
    # from the tree before that fix (fixtree), which holds the lines the fix deleted; a reused review, from the tree the review it reuses read (rtree).
    ex=$(excerpts "$wt" "$fixtree"); rtree=$fixtree; fixtree=''
    # The line is written once the loop's end is known (stop, below); a review with no verdict blocks with it here. Its tail, the review's recorded lines (no USER-VISIBLE or VERDICT line; their last 60, TAIL in records.sh), as the reason is cut at 1500 characters: on a NO-GO, and on a GO with an OUTSIDE line, which the Board lists.
    # Its rollout: the actions its ROLLOUT lines name; on a GO of a review session of the whole change or of the fix alone (not a port's difference or a reused review), [] when it names none, as that GO says the change needs none (cardready(), lib/cardland.sh); one of the fix alone was told the actions in force (rereview()). Bug: its GO naming none kept a NO-GO's migration the fix took out.
    rline=$(grep -Ev "$UNRECORDED" "$wt.review" | jq -cRs --arg res "$res" --argjson t "$t" --arg v "$vis" --argjson k "$(counts "$wt.review")" --arg p "$cpid" --arg m "$chead" --arg s "$cseen" --argjson sv "${sv:-[]}" --argjson an "${an:-[]}" \
      --argjson ro "$(rollouts "$wt.review" ROLLOUT)" --argjson h "$(sed -n 's/^DONE-WHEN: D\([0-9][0-9]*\) holds[[:space:]]*$/\1/p' "$wt.review" | jq -sc 'unique')" --argjson ex "${ex:-[]}" --argjson pl "$(proofline "$wt" | jq -Rsc 'split("\n") | {match: map(select(. == "match")) | length, differs: map(select(. == "differs")) | length, none: map(select(. == "none")) | length}')" --argjson whole "$([ "$res" = GO ] && [ "$rr" != reused ] && [ -z "$fin" ] && echo true || echo false)" \
      'sub("\n+$"; "") as $r | $t + {reason:$r,visible:$v,counts:$k,proofLines:$pl,patch:$p,main:$m,seen:$s} + (if $res == "NO-GO" or ($r | test("(^|\n)(OUTSIDE|SELFHEALS): ")) then {tail: $r} else {} end) + (if $sv == [] then {} else {survived: $sv} end) + (if $an == [] then {} else {answers: $an} end) + (if $h == [] then {} else {doneWhenHolds: $h} end) + (if $ro != [] or $whole then {rollout: $ro} else {} end) + (if $ex == [] then {} else {excerpts: $ex} end)')
    [ -n "$rline" ] || rline='{}' # the grep finds no line in a review of only unrecorded lines: that is no failure
    [ "$res" != none ] || { reviewlines "$c" "$n" "$res" "$rline"; block "$c" "$n" "$wt" "review $pass ended without one clear verdict$unclear"; return; }
  fi
  go=''
}
# What follows the review (afterreview()): its line is written (with why the loop ended: ended), then the card is shut (privshut(), lib/cardland.sh),
# blocks on a NO-GO with no finding, goes to a fix round (go: next) or goes on to land (go: '').
cardfix() {
  # rl: this review's line, whose judge's reasons go with the fix round's findings (rounded()).
  afterreview; local rl=$rline; [ -z "$rline" ] || reviewlines "$c" "$n" "$res" "$(jq -c --argjson e "$ended" '. + $e' <<<"$rline")"; rline=''
  [ "$after" != priv ] || { privshut "$c" "$n" "$wt" "$issue" "$priv" "$pass"; return; }
  [ "$after" != nofinding ] || { block "$c" "$n" "$wt" "review $pass is NO-GO with no finding to fix: ${why:0:200}"; return; }
  if [ "$after" != fix ]; then mode=''
  else
    # A card stacked on this one (stackto()) that passed its tests goes on during this round, fitted onto main alone
    # (giveway(), claim()). A kept patch landed with no review (land) is reviewed after this fix, as after lintgate's fix.
    [ "$mode" != land ] || mode=''; [ -z "$priv" ] || { privfix=$((${privfix:-0} + 1)); echo "conveyor: card $c: a finding of its last review is a privacy hit in its own change, so it goes to fix round $privfix of $PRIVFIXES for it: ${priv:0:200}"; }
    [ -z "$p1" ] || { p1fix=1; echo "conveyor: card $c: its last review holds a P1 finding, so it goes to one fix round and a review of that fix: ${p1:0:200}"; }
    locked giveway "$c" "$wt" fix; began "$c" "$n" fix
    old=$(git -C "$wt" write-tree); more=''; [ -z "$rep" ] || more=$'\n\n'"$(again "$rep")"
    # The fix is told the accepted findings only: a finding the judge declined (a DECLINED line) or found outside the change (an OUTSIDE line, filed when the card lands), a P3 listed only
    # (a MINOR line, minor()), or a rollout action (a ROLLOUT line, no defect), is not its to fix. Each finding it is told is led by its id (donewhen.sh numbered(), fixlines()).
    # It runs on the fix seat (seat(): the builder's unless the control record sets fix).
    ids=$(numbered "$wt") && fl=$(fixlines "$wt" "$ids") || { block "$c" "$n" "$wt" "fix: the engine could not give the review's findings their ids"; return; }
    redbrief "$c" "$n" "$br"; t=$(session "$wt" "$(fixprompt "$sprompt" "$fl$more" "$rep")" fix fix "$([ "$fixed" = 0 ] || echo up)") || { block "$c" "$n" "$wt" "fix: $t"; return; }
    fixed=$((fixed + 1))
    checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$t" || return
    # This fix round's findings, with their ids, and the diff it made, for the review after it (donewhen.sh repeats(), rereview()), under a number no round in the folder has (roundno()).
    local fr; fr=$(roundno "$wt" "$((pass + rounds))"); mkdir -p "$wt.rounds" && git -C "$wt" add -A && git -C "$wt" diff "$old" "$(git -C "$wt" write-tree)" > "$wt.rounds/$fr.diff" \
      && rounded "$wt" "$fr" "$ids" "$rl" && refix=$fr && fixtree=$old
    go=next; return
  fi
  go=''
}
# The resume of a retried card (card()). A retried issue, or a card with no GitHub issue given back (testcardwas(), lib/testaction.sh; not
# a branch, nor a main-red fix card, which `retry` gives back built from nothing): the last kept review of its blocked cards comes along (its findings go in the brief,
# and stay kept if this card blocks before a review of its own), and the last kept patch is applied when it still
# applies. No build and no review only when that review is the review of that patch: both kept by the same card
# (in its kept folder, or beside its worktree when it could not be moved there). So for a retry by review-land (rland: needsland(), lib/needsask.sh, of a card blocked by its review again after review-retry gave its issue back once): it lands on that kept review (afterreview() files its findings), or, when it no longer applies, a session ports it and one review reads that port, as after a landing conflict. So for a card blocked in its Test step (testkept(), lib/issues.sh): it starts at its tests from the kept patch.
# A patch that no longer applies is still used: its session brings it onto main. Only one git cannot parse is given up, or one whose
# issue's section of what customers or staff will see changed since its review (keptway() build, below): that card is built from nothing.
# It reads card()'s n, br, wt, issue, vrule, heldto and inh, and sets its from, fromk, was, mode (land, review,
# session, port, stale, or none: built from nothing), note, fin, finend, pro, rounds and tland (a Test-step block's kept patch), and the files
# beside the worktree that come with the kept patch (review, rerun, trailers, covered, stabilised, outside, effects, rounds). It fails, with the
# reason in err, when the card must block: a kept patch it could not take out again, or retried lines it could not read (cardtree() has checked the new worktree holds no staged change).
resumeplan() {
  local prev d t rev='' kw='' crev='[]' # rev: the kept review prior() found; kw: keptway()'s answer for a kept patch; crev: the review lines of the kept-patch chain this card carries (pro and rounds are read from them)
  if [ -z "$br" ] && prev=$(prior "$n" "$([ "$n" != 0 ] || testcardwas "$c")") && [ -n "$prev" ]; then
    from=$(jq -r .card <<<"$prev"); fromk=$(jq -r .kept <<<"$prev"); was=$(jq -r .reason <<<"$prev"); rev=$(jq -r .review <<<"$prev")
    [ -z "$rev" ] || cp "$rev" "$wt.review"
    rland=''; [ "$(jq -r '.by // ""' <<<"$prev")" != review-land ] || ! { [ "$rev" = "$fromk/$from.review" ] || [ "$rev" = "$CARDS/$from.review" ]; } || [ "$(verdict "$wt.review")" = none ] || rland=1
    if [ -n "$from" ]; then
      if git -C "$wt" apply --index "$fromk/$from.patch" 2>/dev/null; then
        # What the tests of the blocked card had passed (block(); revive() for a card whose process was gone): its run
        # goes on from there, as a run again does, on main as it is now (rerunsince()).
        cp "$fromk/$from.rerun" "$wt.rerun" 2>/dev/null || :
        mode=session; note="resumed from the kept patch of card $from: one session, then review"
        if yeskept "$prev"; then mode=land; note="landing from the kept patch of card $from: no build and no review"; elif testkept "$prev"; then mode=land; tland=1; note="starting at the tests from the kept patch of card $from: no build and no review"; fi
        [ -z "$rland" ] || { mode=land; note="landing from the kept patch of card $from, blocked by its review again after review-retry: no build and no review, its review's findings filed as follow-ups"; }
      elif [ -r "$fromk/$from.patch" ] && git apply --numstat "$fromk/$from.patch" >/dev/null 2>&1; then
        mode=port; note="the kept patch of card $from no longer applies to main: one session brings it onto main, then review"
        # Its loop finished: only a landing conflict blocked it, and the kept review is the review of that
        # patch (a GO, or a last NO-GO whose follow-ups were filed); or a retry by review-land. One review of the port alone, then tests and landing.
        if { [[ $was == "rebase onto main conflicts: "* ]] || [ -n "$rland" ]; } && { [ "$rev" = "$fromk/$from.review" ] || [ "$rev" = "$CARDS/$from.review" ]; } \
          && [ -s "$wt.review" ] && fin=$(verdict "$wt.review") && [ "$fin" != none ]; then
          note="the kept patch of card $from finished its review loop and no longer applies to main: one session brings it onto main, then one review of that port alone"
          # finend: why that loop ended, for the filed line: from the blocked card's last NO-GO review that ended a loop,
          # or its filed line, which says it for a port that blocked again (its review a GO, the loop an earlier card's).
          finend=$(stdb ask issue retried "$n" 2>/dev/null | jq -cs --arg f "$from" 'map(select(.card == $f and .stop != null and (.step == "filed" or (.step == "review" and .result == "NO-GO")))) | last // {} | with_entries(select(.key == "stop" or .key == "pass" or .key == "rounds"))' 2>/dev/null) || finend='{}'
          [ -n "$finend" ] || finend='{}'
        else fin=''; fi
      else
        mode=stale; note="the kept patch of card $from cannot be read: built from nothing"
      fi
      # Its commit trailers, the COVERED-BY lines of its replies (speedproof.sh hollowproof()) and their STABILISED lines (speedproof.sh stabilised()) come with its patch (a card that
      # lands from it has no session to write them again, its deleted hollow cases are checked again on them, and a fix whose reply names no cause keeps them); so do, whatever the patch, the findings its judge found outside its change and the kinds it gave the findings (judged()), which this card files when it lands.
      [ "$mode" = stale ] || for t in trailers covered stabilised; do cp "$fromk/$from.$t" "$wt.$t" 2>/dev/null || cp "$CARDS/$from.$t" "$wt.$t" 2>/dev/null; done; for t in outside effects; do cp "$fromk/$from.$t" "$wt.$t" 2>/dev/null || cp "$CARDS/$from.$t" "$wt.$t" 2>/dev/null || :; done
    fi
  fi
  # A kept patch lands unreviewed only on the issue its review read (keptway(): the body its card kept when it stopped for the yes, on a landing conflict, or in its Test step). A body changed
  # since: the patch is built on and reviewed against the issue as it is now. A section of what customers or staff will see changed since: the issue asks for another change, built from
  # nothing, a port too (bug: it ported the refused change); the old block reason (was) goes too, so its own landing conflict gets its port (landconflict(); bug: it was skipped). Not for a retry by review-land: its card kept no body, and the owner's standing order lands it.
  if { [ "$mode" = land ] || [ "$mode" = port ]; } && [ -n "$issue" ] && [ -z "${rland:-}" ]; then
    d=$fromk/$from.body; [ -e "$d" ] || d=$CARDS/$from.body
    kw=$(keptway "$issue" "$d")
    case $mode:$kw in
      land:review) mode=session; note="resumed from the kept patch of card $from: the issue changed since its review: one session, then review" ;;
      *:build) git -C "$wt" reset -q --hard 2>/dev/null || { err="worktree: the kept patch of card $from could not be taken out of the worktree"; return 1; }
        rm -f "$wt.rerun" "$wt.trailers" "$wt.covered" "$wt.stabilised"; mode='' fin='' was=''; note="the issue's section of what customers or staff will see changed since the review of the kept patch of card $from: built from nothing" ;;
    esac
  fi
  # The owner's yes with a condition: the kept review was written before that line was, so nothing has held the change
  # against the condition. The reviewer does (an unmet condition is a finding, and its fix session builds it). Not so for a card blocked in its Test step on the issue as its review read it, approval lines word for word (tland, keptway() wait, sameyes()): that review came after the line and held the change to it.
  [ "$mode" != land ] || [ -z "$issue" ] || [ "$vrule" = off ] || { [ -n "${tland:-}" ] && [ "$kw" = wait ] && sameyes "$d" "$issue"; } || ! conditional "$issue" \
    || { mode=review; note="reviewing the kept patch of card $from against the condition of $OWNER's yes: no build"; }
  # Held to the section approved before the build (heldto): a kept review that did not say the change matches it was
  # not asked (or said it differs, and no second yes has come since), so the kept patch is reviewed against it: no build.
  [ "$mode" != land ] || [ -z "$heldto" ] || [ "$(visible "$wt.review" any)" = matches ] \
    || { mode=review; note="reviewing the kept patch of card $from against the change $OWNER approved before the build: no build"; }
  # A follow-up whose parent (or an issue up its chain) has the owner's yes (inh): a kept review that gave no INHERITED
  # answer was not asked whether the change stays inside that yes, so the kept patch is reviewed again (no build):
  # the card neither lands unasked nor blocks on the same review at every retry. So is one whose answer was
  # "beyond": that answer was given against the approval line as it was then, and the yes up the chain may since
  # have grown to cover the change; only a kept "part" lands unreviewed.
  [ "$mode" != land ] || [ -z "$inh" ] || [ "$(inheritance "$wt.review")" = part ] \
    || { mode=review; note="reviewing the kept patch of card $from: is its visible change part of the yes of #$(jq -r .from <<<"$inh")? No build"; }
  if [ -n "${rland:-}" ] && [[ $mode =~ ^(land|port|review|session)$ ]]; then rlrev=$(cat "$wt.review") || rlrev=''; rlfind=${was#the fix for }; rlfind=${rlfind% did not hold after *}; else rland=''; fi # A retry by review-land that carries its kept patch keeps the kept review (rlrev, afterreview()) and the finding its block names (rlfind, "the fix for <finding> did not hold after ...": followups() files it released); one built from nothing is no such retry.
  # pro: the rollout actions of the retried cards whose kept patch this card carries ($from, the one whose kept patch that one resumed, and so on back to one built from nothing):
  # `retry` moved their review lines out, and a new review replaces the kept one, so its landing reads them (ro, cardready()): the newest review line with a rollout, one that
  # names any or a GO of the whole change or of the fix alone ([] when it names none). Bugs: a patch `retry --fresh` discarded brought its action back; so did a NO-GO's that its card's GO replaced,
  # and a GO's that a GO after the retry replaced (R234).
  # One read gives the chain's review lines and port lines (crev): pro is the reviews' rollout actions, and rounds (below) counts the reviews.
  if [ -n "$from" ] && [ -n "$mode" ] && [ "$mode" != stale ]; then
    # shellcheck disable=SC2034 # pro: card()'s, read by cardready() (lib/cardland.sh)
    crev=$(stdb ask issue retried "$n" | jq -cs --argjson n "$n" --arg f "$from" 'map(select(.issue == $n)) as $l
      | def up: . as $c | ($l | map(select(.card == $c and .step == "worktree")) | first | .reason // ""
          | select(test("built from nothing") | not) | capture("kept patch of card (?<c>c[A-Za-z0-9-]+)").c) // null;
      [limit(100; $f | recurse(up; . != null))] as $chain
      | [$l[] | select((.step == "review" or (.step == "rebase" and .port == true)) and (.card | IN($chain[])))]') \
      && pro=$(jq -c '[.[] | select(.step == "review" and has("rollout")) | .rollout] | last // []' <<<"$crev") \
      || { err="worktree: the engine could not read the rollout actions of the retried cards of the issue"; return 1; }
  fi
  # A card that takes up the kept patch of a loop that did not finish carries that loop's review rounds: the round
  # limit counts every review of the issue's retried cards, not just this card's. So does a kept patch reviewed again
  # with no build: a NO-GO there is fixed and goes round the loop. Not the port of a finished loop: its loop ended,
  # and this review checks something new.
  # Its fix rounds' findings and diffs come with them, so a finding that comes back is known as one (donewhen.sh repeats()).
  # Only the reviews of that loop count: those of the cards whose kept patch this card carries (crev, the lines pro
  # is read from). A card's id is its own, so another project's cards are not in the chain; the lines' repo is not
  # read, as a project renamed in host.json keeps its chain. Bug (issue 1071): every review line of the issue in the
  # retried file was counted, another chain's and another project's too, so a card's first NO-GO could be its last review.
  # After an automatic port (landconflict() marks its rebase line port), only the reviews after the port's own review count: those before it ended a loop, and the port's review checked
  # the port alone. Bug (issue 1385): 3 reviews, a port and 2 reviews carried 5 rounds (then 2): a last review.
  if [ "$mode" = session ] || [ "$mode" = review ] || { [ "$mode" = port ] && [ -z "$fin" ]; }; then
    rounds=$(jq '(to_entries | map(select(.value.step == "rebase")) | last | .key) as $p | if $p == null then length else .[$p + 2:] | length end' <<<"$crev" 2>/dev/null) || rounds=0
    [[ $rounds =~ ^[0-9]+$ ]] || rounds=0
    # Rounds still beside the old worktree are the ones its block could not move (a folder of that name in the kept folder stopped it, so that one is not the history): those are copied.
    if [ -d "$CARDS/$from.rounds" ]; then cp -R "$CARDS/$from.rounds" "$wt.rounds" 2>/dev/null; else cp -R "$fromk/$from.rounds" "$wt.rounds" 2>/dev/null; fi
    # A last round no review with a verdict answered (no <worktree>.rounds/told, cardreview(): the card blocked before its review, or the review ended with none or blocked
    # unrecorded): this card's first review is told it (refix, rereview()). Bug: the record lines were counted to find it, and a review that blocked with no line, or a port, put that count off, so it was not told.
    [ -e "$wt.rounds/told" ] || { refix=$(jq -rs 'last | .round // empty' "$wt.rounds/findings.jsonl" 2>/dev/null); [[ $refix =~ ^[0-9]+$ ]] || refix=''; }
  fi
  return 0
}
# The visible-change gate before the build (card()). Approve before build (the rule at the top): an issue whose
# section names a change and that has an approval line holds the card to that section (heldto).
# An approval line is the owner's yes to what a card shows only when it was written after a card of the issue stopped
# for that yes. ybase is the count of approval lines when the last one stopped (kept beside its card, carried by
# every card after it). A section saying nothing visible changes: with no such stop, the lines there are now.
# A section naming a change: it holds the card until a card stopped for differing from it (or for not
# saying whether it matches) and an approval line has come since; however many lines it had before any such stop,
# they are all yeses to the section, not to something else a build shows.
# It reads card()'s n, issue and vrule, and sets its seen, nyes, sect, ybase, heldto, vmode and yfile.
visplan() {
  if [ -n "$issue" ] && [ "$vrule" = on ]; then
    seen=$(jq -r "$SEE"' seen' <<<"$issue" 2>/dev/null) || seen=none
    nyes=$(jq -r "$SEE"' approvals' <<<"$issue" 2>/dev/null) || nyes=0
    sect=$(jq -r "$SEE"' section // ""' <<<"$issue" 2>/dev/null) || sect=''
  fi
  ybase=$nyes
  if [ "$seen" = nothing ]; then
    ybase=$(yesbase "$n"); [[ $ybase =~ ^[0-9]{1,3}$ ]] || ybase=$nyes
    yfile=1
  elif [ "$seen" = change ] && [[ $nyes =~ ^[0-9]+$ ]] && [ "$nyes" -ge 1 ]; then
    ybase=$(yesbase "$n")
    if [[ $ybase =~ ^[0-9]{1,3}$ ]]; then yfile=1; else ybase=''; fi
    [ -n "$ybase" ] && [ "$nyes" -gt "$ybase" ] || { heldto=1; vmode=held; }
  fi
  return 0
}
# The visible-change gate after a review that would let the card land (card(); the rule is told there). A card held to
# the approved section (heldto) goes on when the review says its change matches it, and stops when it differs or the
# review did not say. One not held to a section stops for a visible change in product code with no yes of its own,
# unless its reviewer says the change is part of an inherited yes (inh): then yesfrom names the issue whose yes it lands on.
# It reads card()'s c, wt, issue, vrule, heldto, vis, nyes, seen, ybase, inh, ph and pf, and sets its yesfrom, more
# and old. It fails when the card must stop, with the reason in err and the issue body this review read written to
# .body beside the worktree (with the lint policy hash when ph is set). The approval count goes to .approvals beside it
# on a held card's stop, and on a stop of one not held only when its section said nothing visible changes (seen=nothing).
visgate() {
  local said # said: the review's answer on the inherited yes (inheritance())
  if [ -n "$heldto" ] && git -C "$wt" diff --cached --no-renames --name-only | productpaths; then
    case $vis in
      matches) echo "conveyor: card $c: what it shows matches the change $OWNER approved before the build" ;;
      "differs: "*) printf '%s\n' "$nyes" > "$wt.approvals"; jq -c --arg p "$ph" '{body} + (if $p == "" then {} else {policy: $p} end)' <<<"$issue" > "$wt.body"; err="${YES}it differs from the change approved before the build: ${vis#differs: }${pf:+; it also changes lint policy: $pf}"; return 1 ;;
      *) printf '%s\n' "$nyes" > "$wt.approvals"; jq -c --arg p "$ph" '{body} + (if $p == "" then {} else {policy: $p} end)' <<<"$issue" > "$wt.body"; err="${YES}the review did not say whether it matches the change approved before the build${pf:+; it also changes lint policy: $pf}"; return 1 ;;
    esac
  elif [ "$vrule" = on ] && [ -z "$heldto" ] && [ "$vis" != no ] && git -C "$wt" diff --cached --no-renames --name-only | productpaths \
    && { [ "$nyes" = 0 ] || { [ "$seen" = nothing ] && [ "$nyes" -le "$ybase" ]; }; }; then
    more=''
    if [ -n "$inh" ]; then
      said=$(inheritance "$wt.review"); old=$(jq -r .from <<<"$inh")
      case $said in
        part) yesfrom=$old ;;
        "beyond: "*) more=" (it goes beyond the yes of #$old: ${said#beyond: })" ;;
        *) more=" (the review did not say whether it is part of the yes of #$old)" ;;
      esac
    fi
    [ -n "$yesfrom" ] || { [ "$seen" != nothing ] || printf '%s\n' "$nyes" > "$wt.approvals"; jq -c --arg p "$ph" '{body} + (if $p == "" then {} else {policy: $p} end)' <<<"$issue" > "$wt.body"; err="$YES${vis#yes: }$more${pf:+; it also changes lint policy: $pf}"; return 1; }
    echo "conveyor: card $c: its visible change is part of the change $OWNER approved in #$yesfrom: the yes is inherited"
  fi
  return 0
}
