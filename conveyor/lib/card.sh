# SPDX-License-Identifier: Apache-2.0
# One card to its closing line (landed, closed or blocked). Every step checks its own exit and writes its own line when it
# ends; nothing waits between a line and the next step, which is how cards() names the step in progress.
# With a branch and its tip (land-branch) the card skips the build: that commit is merged into the worktree, staged
# and uncommitted, in place of a session's work. Issue 0 is a branch that names no issue: branchissue() stands in.
# Before the worktree, the rule Split large issues checks the card's issue (splitcheck(), lib/slices.sh): an issue it
# splits ends its card there, closed, its slices filed. Then the rule Pick settings records the card's group and
# builder choice on each of its lines from there on, and with the rule On sets a trial card's builder (modelpick(),
# lib/modelpick.sh).
. "$HERE/lib/slices.sh" || exit 1
. "$HERE/lib/modelpick.sh" || exit 1
. "$HERE/lib/lint.sh" || exit 1
began() { # <card> <issue> <what begins>
  local e=''
  switchcode "$1" "$3"; rm -f "$CARDS/$1.firsttry" "$CARDS/$1.firsttry.new"
  # A card on the code of a commit it switched to: its start line names that commit, so prune() (inflight(),
  # lib/install.sh) keeps its install while the card runs; its worktree line names the commit it started on.
  [ -z "$RAN" ] || [ "$RAN" != "${CODESEEN:-}" ] || e=",\"engine\":\"$RAN\""
  record "$1" "$2" start ok "{\"of\":\"$3\"$e}"
}
# The form of the files a card saves for its steps (<worktree>.review, .test, .ready, .rerun and the rest): a commit
# whose code cannot read the files that the code before it saved raises it, and a running card then keeps its old
# code (switchcode()).
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
# switch gets them too. The rules and header are the ones card() made (its rules and hdr: began() runs only in card()).
# A function that is running (card(), and settle() or began() under it) goes on in its old body to its end, as bash
# runs it: so the card keeps its old code, and says why once, when the new code changes one of them, reads another
# form of step files (STEPFILES), or its files do not load or do not make the card's rules, header and settings.
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
  if [ -z "$why" ]; then
    # The texts card() made its prompts of, before the switch and after it: its header and rules, and the review
    # texts its rv is made of (KINDS with the kinds judgeon names now). After the next switch, its new ones are old.
    k=$(judgeon 2>/dev/null) && [ "$k" != '[]' ] && k=$(jq -r 'join(", ")' <<<"$k") || k=''
    o=("$hdr" "$rules" "$REVIEWOFF" "$REVIEW" "$INHERIT" "$HELD" "${k:+${KINDS//'<kinds>'/"$k"}}")
    . "$tmp/load"; NAMED=''; names >/dev/null 2>&1
    nv=("$(<"$tmp/hdr")" "$(<"$tmp/rules")" "$REVIEWOFF" "$REVIEW" "$INHERIT" "$HELD" "${k:+${KINDS//'<kinds>'/"$k"}}")
    for i in "${!o[@]}"; do [ -z "${o[i]}" ] || [ "${o[i]}" = "${nv[i]}" ] || { SWAPOLD+=("${o[i]}"); SWAPNEW+=("${nv[i]}"); }; done
    mv -f "$tmp/settings" "$CARDS/$1.settings"
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
  local -A was=()
  # Both from the card's folder: records.sh moves into the main checkout, and paths.sh and records.sh read where they start.
  codeload "$1" >/dev/null 2>&1 && cd "$wd" || return 1
  for n in $(compgen -v | grep -xE '[A-Z][A-Z0-9_]*' | grep -vxE "$sh"); do was[v$n]=$(declare -p "$n" 2>/dev/null); done
  for n in $(compgen -A function); do was[f$n]=$(declare -f "$n"); done
  codeload "$2" >/dev/null 2>&1 || return 1
  for n in $(compgen -v | grep -xE '[A-Z][A-Z0-9_]*' | grep -vxE "$sh"); do
    d=$(declare -p "$n" 2>/dev/null) && [ "$d" != "${was[v$n]-}" ] && [[ ! $d =~ ^declare\ -[a-zA-Z]*r ]] || continue
    case $d in "declare -- "*) printf '%s\n' "declare -g ${d#declare -- }" ;; *) printf '%s\n' "declare -g${d#declare -}" ;; esac
  done
  for n in $(compgen -A function); do d=$(declare -f "$n"); [ "$d" = "${was[f$n]-}" ] || printf '%s\n' "$d"; done
}
# A main-red fix card (issue 0, no branch): a case found failing on its commit while it runs (mainred()) joins its
# brief. card() calls this right before each session, review, judge, settle() and land, as a case can come at any time
# (during a review too, with the fix session straight after it). Sets card()'s issue and sprompt. A case that joined
# brings its links too (issue 615): they are staged in card()'s worktree (testlinks()) to land with the fix, as the
# links of the cases it started with were; staged again on each call, so one that could not be is tried again.
redbrief() { # <card> <issue> <branch>
  local red
  [ "$2" = 0 ] && [ -z "$3" ] || return 0
  testlinks "$1" "$wt" || echo "conveyor: card $1: the test links of the main-red record could not be staged in .conveyor/test-links.json" >&2
  red=$(redissue "$1") && [ "$red" != "$issue" ] || return 0
  sprompt=${sprompt/"$(issuepart "$issue")"/"$(issuepart "$red")"}; issue=$red
}
# The sessions' and the reviewer's prompt (plan section 10, the reviewer gets the same text): the brief with the
# rules after the header, before the issue. Each session and review is handed it with its own part after it.
cardprompt() { # <card> <header> <rules> <brief>
  local rhead="Conveyor card $1. $2"$'\n\n'
  printf '%s' "$rhead"$'# Rules\n\n'"$3"$'\n\n'"${4#"$rhead"}"
}
# The prompts of the sessions after the build, each the card's prompt (cardprompt()) with its own part after it: a fix
# of review findings, a fix of the changed tests (the last 200 lines of their output), and a rebuild or a port onto main.
fixprompt() { # <card prompt> <the findings, each led by its id, and what follows them>
  printf '%s' "$1"$'\n\n'"$FIX"$'\n'"$2"
}
# Why a review ends the fix loop, the first that holds: go (a GO), max-reviews (it is review MAX_REVIEWS, counting the
# rounds a retried card carries), rebased (the one review after a landing conflict), test-fix (after the one test fix),
# lint-fix (after the landing gate's lint fix), land (the kept review of a kept patch landed with no review), repeat (a
# NO-GO that repeats a fixed finding, every finding P2 or P3). Prints nothing when a fix round follows.
loopstop() { # <verdict> <reviews so far: pass + rounds> <rebased> <tfix> <lfix> <mode> <repeats() lines> <review file>
  if [ "$1" = GO ]; then echo go
  elif [ "$2" -ge "$MAX_REVIEWS" ]; then echo max-reviews
  elif [ -n "$3" ]; then echo rebased
  elif [ -n "$4" ]; then echo test-fix
  elif [ -n "$5" ]; then echo lint-fix
  elif [ "$6" = land ]; then echo land
  elif [ -n "$7" ] && [ "$(counts "$8" | jq '.P0 + .P1')" = 0 ]; then echo repeat
  fi
}
testfixprompt() { # <card prompt> <worktree> <the test run's exit>
  printf '%s' "$1"$'\n\n# The changed tests fail (exit '"$3"$'): fix that and nothing else. The end of the test output:\n'"$(tail -n 200 "$2.test" 2>/dev/null | tr -d '\000')"
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
# (its first area label, else product), then its Closes and card lines.
cardsubject() { # <card> <issue json>
  jq -r --arg c "$1" --arg t "$TYPE" --arg p "$AREA" '(.labels | map(.name)) as $l | "\(if $l | index($t) then "fix" else "feat" end)(\($l | map(select(startswith($p)) | ltrimstr($p)) | .[0] // "product")): \(.title) (#\(.number))\n\nCloses #\(.number)\nConveyor card \($c)"' <<<"$2"
}
# A failed (or held) test step's line, past its common fields: the run's record (testrec()), its reason (the exit, and
# the timeout with the file still running when there was one), its failures (testfails()), the last 60 lines of its
# output (its tail, each line whole), its first-run marks (firstrun()), the verdicts of what ran again on main
# (verdicts()) and its carried part (carriedrec()).
failline() { # <worktree> <exit> <seconds> <failures json, or null> <verdicts json> <carried json>
  tail -n 60 "$1.test" 2>/dev/null | tr -d '\000' | jq -cRs --slurpfile x <(testrec "$1" "$2" "$3") --slurpfile f <(printf '%s' "$4") --arg rc "$2" --slurpfile r <(firstrun "$1") --slurpfile v <(printf '%s' "$5") --slurpfile o <(printf '%s' "$6") \
    '$x[0] as $x | $f[0] as $f | $r[0] as $r | $v[0] as $v | $o[0] as $o | sub("\n+$"; "") as $t | $x + $o + {
       reason:("exit " + $rc + (if $f.timeout then ": timed out after \($f.timeout.sec)s" + (if $f.timeout.file then " in \($f.timeout.file)" else "" end) else "" end))}
     + (if $f then {failures:($f | del(.passed, .okcases, .passcases))} else {} end) + (if $t == "" then {} else {tail:$t} end) + $r + $v'
}
card() { # <card> <issue> [<branch> <tip>]
  local c=$1 n=$2 br=${3:-} tip=${4:-} wt=$CARDS/$1 issue b t pass res vis unclear msg d err isfu='' dec='' why ups='' left='' rebased='' tfix='' last rc sec out merged away
  local prev from='' fromk='' was='' rev='' mode='' note='' old more base inh='' rv=$REVIEW yesfrom='' said extra
  local me cc seen=none sect='' nyes=0 heldto='' vmode='' ybase rules sprompt hdr fin='' finrev earlier='' prv='' caught='' owe tsess='' cmsg rtr rrev ro='[]' pro='[]' rmsg ported='' kp='' mates=() t5=() trc ran apart='' back='' rf sf='' sk='' mk='' pk='' pt=''
  local vrule=on rounds=0 rep hard refix='' waitsec=0 behind='[]' cpid chead cseen own kept='' docpass='' docs parsecheck='' pfix='' # waitsec, behind: the seconds it has waited on other cards, and those cards (settle())
  local sv an ex ids fl # sv, an, ex: a review's survived findings, its answers and the lines it cites (repeats(), answers(), excerpts()); ids, fl: the fix round's numbered findings and its lines (numbered(), fixlines())
  local crev='[]' # crev: the review lines of the kept-patch chain this card carries (pro and rounds are read from them)
  local grown='' # grown: the judge was asked about the size of its change (growcheck(), lib/slices.sh)
  local rline='' ended='{}' stop='' finend='{}' earlyend='' fe # rline, ended, stop: a review's line before it is written, and why the loop ended (loopstop()); finend, earlyend, fe: why the loop of a port's kept review ended, and the stop the filed line carries
  local lfix='' # lfix: the change the landing gate's lint fix left, its cardpatch() (lintgate(), lib/lint.sh)
  local fixtree='' # fixtree: the tree before the last fix round, which holds the lines that fix deleted (excerpts())
  local priv privfix='' # priv: a last-review finding that is a privacy hit in the card's own change (privown()); privfix: its fix round was given
  local tmain='' # tmain: set once a failed test step has fitted the card onto a main that had moved (#582)
  local voids=0 # voids: the test runs in a row that gave no result (voidrun())
  local held # held: its test step waited for main or the machine (mainwait(), holdwait())
  local cr # cr: a failed test line's carried part (carriedrec())
  local mainsec=0 mw mwon # mwon: main's commit and the cases it waits on there (mainwait()); mainsec: the seconds it has waited for main to change (mainwait()); its landed line's waitSec adds them to waitsec
  local repaired='' lane # repaired: the repair lane passed its test step (repairlane()), saying how; lane: its exit
  local ins rr # ins, rr: the review's instructions, and fix when it reviews the fix alone (rereview())
  local kw='' # kw: keptway()'s answer for a kept patch
  local ph pf pb # ph, pf: the hash and the files of the change's lint policy diff (lintpolicy()); pb: the body kept by the card it resumes
  local shared sb # shared: this test step runs its shared test files again (sharedtests()); sb: the commit its last tests ran on
  # shellcheck disable=SC2034 # SEATCARD is read by seat() in lib/control.sh
  local SEATCARD=$n # every step of this card, its split check too, runs on the seats the control record keeps for its issue (seat(), lib/control.sh)
  [ -n "$br" ] || [ "$n" = 0 ] || splitcheck "$c" "$n" || return 0
  # shellcheck disable=SC2034 # PICK and PICKCARD are read by line() in lib/records.sh, PICKSEAT and PICKSEATS by seat() in lib/control.sh
  local PICK='' PICKCARD='' PICKSEAT='' PICKSEATS='' # the card's pick (modelpick(), lib/modelpick.sh), which line() puts on each of its lines, a trial's builder and the promoted reviewer and judge
  [ -n "$br" ] || [ "$n" = 0 ] || modelpick "$c" "$n"
  err=$(git worktree add -q --detach "$wt" "refs/heads/$BRANCH" 2>&1) || { block "$c" "$n" "$wt" "worktree: $err"; return; }
  [ -z "$br" ] || err=$(git -C "$wt" merge -q --squash "$tip" 2>&1) \
    || { block "$c" "$n" "$wt" "worktree: branch $br does not merge into main as it stands; rebase it on main and land it again: ${err:0:400}"; return; }
  # A retried issue (not issue 0: a branch, or a main-red fix card, which `retry` gives back built from nothing): the last kept review of its blocked cards comes along (its findings go in the brief, and
  # stay kept if this card blocks before a review of its own), and the last kept patch is applied when it still
  # applies. No build and no review only when that review is the review of that patch: both kept by the same card
  # (in its kept folder, or beside its worktree when it could not be moved there).
  # A patch that no longer applies is still used: its session brings it onto main. Only one git cannot
  # parse is given up: that card is built from nothing.
  # Its issue's retried lines, read by prior() and carried(), kept in this shell (stdb, lib/records.sh).
  [ "$n" = 0 ] || stdb ask issue retried "$n" >/dev/null 2>&1 || :
  if [ -z "$br" ] && [ "$n" != 0 ] && prev=$(prior "$n") && [ -n "$prev" ]; then
    from=$(jq -r .card <<<"$prev"); fromk=$(jq -r .kept <<<"$prev"); was=$(jq -r .reason <<<"$prev"); rev=$(jq -r .review <<<"$prev")
    [ -z "$rev" ] || cp "$rev" "$wt.review"
    if [ -n "$from" ]; then
      if git -C "$wt" apply --index "$fromk/$from.patch" 2>/dev/null; then
        # What the tests of the blocked card had passed (block(); revive() for a card whose process was gone): its run
        # goes on from there, as a run again does, on main as it is now (rerunsince()).
        cp "$fromk/$from.rerun" "$wt.rerun" 2>/dev/null || :
        mode=session; note="resumed from the kept patch of card $from: one session, then review"
        ! yeskept "$prev" || { mode=land; note="landing from the kept patch of card $from: no build and no review"; }
      elif [ -r "$fromk/$from.patch" ] && git apply --numstat "$fromk/$from.patch" >/dev/null 2>&1; then
        mode=port; note="the kept patch of card $from no longer applies to main: one session brings it onto main, then review"
        # Its loop finished: only a landing conflict blocked it, and the kept review is the review of that
        # patch (a GO, or a last NO-GO whose follow-ups were filed). One review of the port alone, then tests and landing.
        if [[ $was == "rebase onto main conflicts: "* ]] && { [ "$rev" = "$fromk/$from.review" ] || [ "$rev" = "$CARDS/$from.review" ]; } \
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
      # Its commit trailers and the COVERED-BY lines of its replies (hollowproof()) come with its patch (a card that
      # lands from it has no session to write them again, and its deleted hollow cases are checked again on them).
      [ "$mode" = stale ] || for t in trailers covered; do cp "$fromk/$from.$t" "$wt.$t" 2>/dev/null || cp "$CARDS/$from.$t" "$wt.$t" 2>/dev/null; done
    fi
  fi
  # A card that applied no kept patch (session, land) and merged no branch starts on a clean worktree of main. A staged
  # change found there is no work of this card: its build would take it for its own, so the card stops here.
  if [ -z "$br" ] && [ "$mode" != session ] && [ "$mode" != land ]; then
    err=$(git -C "$wt" diff --cached --name-only 2>&1) || { block "$c" "$n" "$wt" "worktree: the engine could not read the staged change of the new worktree: ${err:0:400}"; return; }
    [ -z "$err" ] || { block "$c" "$n" "$wt" "worktree: the new worktree already holds a staged change that is no kept work of this issue: $(paste -sd ' ' - <<<"$err" | cut -c 1-400)"; return; }
  fi
  # A main-red fix card commits, with its fix, the links from the files of the landing that broke a case to its test
  # file (issue 598: testlinks()).
  testlinks "$c" "$wt" || { block "$c" "$n" "$wt" "the test links of the main-red record could not be staged in .conveyor/test-links.json"; return; }
  # A card of issue 0 with no branch is a main-red fix card (redpick()): its entry in the main-is-red record stands in.
  issue=$(if [ -n "$br" ] && [ "$n" = 0 ]; then branchissue "$br" "$tip"; elif [ "$n" = 0 ]; then redissue "$c"; else gh issue view "$n" --json number,title,body,labels,milestone; fi) || issue=''
  # The control record's rule "visible changes need the owner's yes" (yesrule()), as the card starts. Off, nothing below
  # waits for or asks for a `Visible change approved:` line: no condition, section or inherited yes is held to, the
  # brief and the review leave the approval out, and a visible change lands as any change does.
  yesrule "${CARDCTL:-}" || { vrule=off; rv=$REVIEWOFF; }
  # A kept patch lands unreviewed only on the issue its review read (keptway(): the body its card kept when it
  # stopped for the yes). A body changed since: the patch is built on and reviewed against the issue as it is now. A
  # section of what customers or staff will see changed since: the issue asks for another change, built from nothing.
  if [ "$mode" = land ] && [ -n "$issue" ]; then
    d=$fromk/$from.body; [ -e "$d" ] || d=$CARDS/$from.body
    kw=$(keptway "$issue" "$d")
    case $kw in
      review) mode=session; note="resumed from the kept patch of card $from: the issue changed since its review: one session, then review" ;;
      build) git -C "$wt" reset -q --hard 2>/dev/null || { block "$c" "$n" "$wt" "worktree: the kept patch of card $from could not be taken out of the worktree"; return; }
        rm -f "$wt.rerun" "$wt.trailers" "$wt.covered"; mode=''; note="the issue's section of what customers or staff will see changed since the review of the kept patch of card $from: built from nothing" ;;
    esac
  fi
  # The test file of a speed-up or Optimize card (a bug card whose issue speedfile() names): its build is told the
  # target (speedbrief()).
  [ -z "$issue" ] || ! jq -e --arg t "$TYPE" 'any(.labels[]?; .name == $t)' <<<"$issue" >/dev/null || sf=$(speedfile "$issue") || sf=$(speedfile "$issue" "$OPTIMIZE") || sf=$(speedfile "$issue" "$REWRITE") || sf=''
  # The owner's yes with a condition: the kept review was written before that line was, so nothing has held the change
  # against the condition. The reviewer does (an unmet condition is a finding, and its fix session builds it).
  [ "$mode" != land ] || [ -z "$issue" ] || [ "$vrule" = off ] || ! conditional "$issue" \
    || { mode=review; note="reviewing the kept patch of card $from against the condition of $OWNER's yes: no build"; }
  # Approve before build (the rule at the top): an issue whose section names a change and that has an approval
  # line holds the card to that section (heldto). A kept review that did not say the change matches it was not asked
  # (or said it differs, and no second yes has come since), so the kept patch is reviewed against it: no build.
  if [ -n "$issue" ] && [ "$vrule" = on ]; then
    seen=$(jq -r "$SEE"' seen' <<<"$issue" 2>/dev/null) || seen=none
    nyes=$(jq -r "$SEE"' approvals' <<<"$issue" 2>/dev/null) || nyes=0
    sect=$(jq -r "$SEE"' section // ""' <<<"$issue" 2>/dev/null) || sect=''
  fi
  # An approval line is the owner's yes to what a card shows only when it was written after a card of the issue stopped
  # for that yes. ybase is the count of approval lines when the last one stopped (kept beside its card, carried by
  # every card after it). A section saying nothing visible changes: with no such stop, the lines there are now.
  # A section naming a change: it holds the card until a card stopped for differing from it (or for not
  # saying whether it matches) and an approval line has come since; however many lines it had before any such stop,
  # they are all yeses to the section, not to something else a build shows.
  ybase=$nyes
  if [ "$seen" = nothing ]; then
    ybase=$(yesbase "$n"); [[ $ybase =~ ^[0-9]{1,3}$ ]] || ybase=$nyes
    printf '%s\n' "$ybase" > "$wt.approvals"
  elif [ "$seen" = change ] && [[ $nyes =~ ^[0-9]+$ ]] && [ "$nyes" -ge 1 ]; then
    ybase=$(yesbase "$n")
    if [[ $ybase =~ ^[0-9]{1,3}$ ]]; then printf '%s\n' "$ybase" > "$wt.approvals"; else ybase=''; fi
    [ -n "$ybase" ] && [ "$nyes" -gt "$ybase" ] || { heldto=1; vmode=held; }
  fi
  [ "$mode" != land ] || [ -z "$heldto" ] || [ "$(visible "$wt.review" any)" = matches ] \
    || { mode=review; note="reviewing the kept patch of card $from against the change $OWNER approved before the build: no build"; }
  # A follow-up whose parent (or an issue up its chain) has the owner's yes: a kept review that gave no INHERITED
  # answer was not asked whether the change stays inside that yes, so the kept patch is reviewed again (no build):
  # the card neither lands unasked nor blocks on the same review at every retry. So is one whose answer was
  # "beyond": that answer was given against the approval line as it was then, and the yes up the chain may since
  # have grown to cover the change; only a kept "part" lands unreviewed.
  [ "$n" = 0 ] || [ -z "$issue" ] || [ "$vrule" = off ] || inh=$(inherit "$issue")
  [ "$mode" != land ] || [ -z "$inh" ] || [ "$(inheritance "$wt.review")" = part ] \
    || { mode=review; note="reviewing the kept patch of card $from: is its visible change part of the yes of #$(jq -r .from <<<"$inh")? No build"; }
  # pro: the rollout actions the reviews of the retried cards whose kept patch this card carries named, in order: the
  # card it resumes ($from), the card whose kept patch that one resumed (its worktree line names it), and so on back
  # to one built from nothing. `retry` moved those review lines out of its card records, and a new review replaces the
  # kept one, so its landing reads them here (ro, below). Bug: every retried card of the issue was read, so a patch
  # `retry --fresh` discarded brought its rollout action back into the commit.
  # One read gives the chain's review lines (crev): pro is their rollout actions, and rounds (below) counts them.
  if [ -n "$from" ] && [ -n "$mode" ] && [ "$mode" != stale ]; then
    crev=$(stdb ask issue retried "$n" | jq -cs --argjson n "$n" --arg f "$from" 'map(select(.issue == $n)) as $l
      | def up: . as $c | ($l | map(select(.card == $c and .step == "worktree")) | first | .reason // ""
          | select(test("built from nothing") | not) | capture("kept patch of card (?<c>c[A-Za-z0-9-]+)").c) // null;
      [limit(100; $f | recurse(up; . != null))] as $chain
      | [$l[] | select(.step == "review" and (.card | IN($chain[])))]') \
      && pro=$(jq -c '[.[] | .rollout // [] | .[]]' <<<"$crev") \
      || { block "$c" "$n" "$wt" "worktree: the engine could not read the rollout actions of the retried cards of the issue"; return; }
  fi
  # A card that takes up the kept patch of a loop that did not finish carries that loop's review rounds: the round
  # limit counts every review of the issue's retried cards, not just this card's. So does a kept patch reviewed again
  # with no build: a NO-GO there is fixed and goes round the loop. Not the port of a finished loop: its loop ended,
  # and this review checks something new.
  # Its fix rounds' findings and diffs come with them, so a finding that comes back is known as one (repeats()).
  # Only the reviews of that loop count: those of the cards whose kept patch this card carries (crev, the lines pro
  # is read from). A card's id is its own, so another project's cards are not in the chain; the lines' repo is not
  # read, as a project renamed in host.json keeps its chain. Bug (issue 1071): every review line of the issue in the
  # retried file was counted, another chain's and another project's too, so a card's first NO-GO could be its last review.
  if [ "$mode" = session ] || [ "$mode" = review ] || { [ "$mode" = port ] && [ -z "$fin" ]; }; then
    rounds=$(jq 'length' <<<"$crev" 2>/dev/null) || rounds=0
    [[ $rounds =~ ^[0-9]+$ ]] || rounds=0
    # Rounds still beside the old worktree are the ones its block could not move (a folder of that name in the kept
    # folder stopped it, so that one is not the history): those are copied.
    if [ -d "$CARDS/$from.rounds" ]; then cp -R "$CARDS/$from.rounds" "$wt.rounds" 2>/dev/null; else cp -R "$fromk/$from.rounds" "$wt.rounds" 2>/dev/null; fi
  fi
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
  [ "$n" = 0 ] || { more=$(carried "$n" "$wt"); [ -z "$more" ] || b+=$'\n\n'"$more"; }
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
  b+=$'\n\n'"$more"
  more=$(lintbrief) || { block "$c" "$n" "$wt" "brief: the engine could not read the lint field of the project pack"; return; }
  [ -z "$more" ] || b+=$'\n\n'"$more"
  sprompt=$(cardprompt "$c" "$hdr" "$rules" "$b")
  d=$(jq -r '.body // ""' <<<"$issue" | sed -nE 's/^Follow-up depth: ([0-9]+)[[:space:]]*$/\1/p' | head -n 1)
  [ ${#d} -le 3 ] && d=$((10#${d:-0})) || d=''
  record "$c" "$n" brief ok "$([ -z "$d" ] && echo '{}' || echo "{\"depth\":$d}")"
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
    # The kept review came after the last of its fix rounds (it is the issue's last review, and that round followed an
    # earlier one) and repeats a finding that round was told to fix: the session is told so, with that round's diff.
    rep=''; [ "$(verdict "$wt.review" 2>/dev/null)" != NO-GO ] || ! jq -se --argjson r "$rounds" 'map(.round) | max < $r' "$wt.rounds/findings.jsonl" >/dev/null 2>&1 \
      || rep=$(repeats "$wt")
    [ -z "$rep" ] || more+=$'\n\n'"$(again "$rep")"
    [ -z "$sf" ] || { t=$(speedbrief "$c" "$wt" "$sf" "$issue") && more+=$'\n\n'"$t"; } \
      || { block "$c" "$n" "$wt" "brief: the engine could not read the project pack for the split allowance of $sf"; return; }
    began "$c" "$n" build
    redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt$more") || { block "$c" "$n" "$wt" "build: $t"; return; }
    checked "$c" "$n" "$wt" "$issue" "$sprompt" build "$t" || return
    # A bug card (the pack's type label): the tests it adds or changes must fail on main's code without the fix
    # (bugproof(); a change that selects no test of its own is proved by the test files its issue's Done-when names,
    # and goes on unchecked when it names none). When none does, or it adds none, it goes back to its build session once, told why; when the check
    # still does not hold after it, the card is blocked with that reason and no review. The review is shown the
    # check's result. A bug card that speeds up one test file (speedfile()) is checked by speedproof() instead, and one
    # that optimizes one (speedfile() with OPTIMIZE, or REWRITE: Rewrite as a direct check, #778) by optproof(): when the change does not do what its issue's verdict
    # asks, its file costs more than its recent runs allow, a split takes more
    # CPU seconds than it may, or a file does not pass, the card is blocked with that reason and no review, its blocked line
    # carrying the check's version (SPEEDCHECK, lib/testrun.sh). One that fixes the failures of one (speedfile() with
    # FIXFAILS) is checked by steadyproof(): when its file fails in one of its runs in a row, the card is blocked
    # naming that run, with no review. So are the Board's other fix issues (#189): Fix the waiting (WAITFIX), Fix hollow
    # cases (HOLLOWFIX), Delete it (DELFILE) and Make it run alone (#190; ALONEFIX, before Make it run, whose title
    # starts the same) by fixproof() (pk), here and again before each later review on a change
    # a fix or rebase session made (pt: the tree it last held on), and Make it run (MAKERUN) by runproof() now and by
    # ranproof() once its test step passed (mk).
    if ! jq -e --arg t "$TYPE" 'any(.labels[]?; .name == $t)' <<<"$issue" >/dev/null; then :
    elif sf=$(speedfile "$issue"); then
      speedproof "$c" "$wt" "$issue" "$sf" || { SPEEDCHECKED=$SPEEDCHECK block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    elif sf=$(speedfile "$issue" "$OPTIMIZE") || sf=$(speedfile "$issue" "$REWRITE"); then
      sk=$OPTREVIEW; optproof "$c" "$wt" "$issue" "$sf" || { SPEEDCHECKED=$SPEEDCHECK block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    elif sf=$(speedfile "$issue" "$FIXFAILS"); then
      sk=$STEADYREVIEW; steadyproof "$c" "$wt" "$sf" || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    elif { pk=$WAITFIX sk=$WAITREVIEW; sf=$(speedfile "$issue" "$pk"); } || { pk=$HOLLOWFIX sk=$HOLLOWREVIEW; sf=$(speedfile "$issue" "$pk"); } \
      || { pk=$DELFILE sk=$DELREVIEW; sf=$(speedfile "$issue" "$pk"); } || { pk=$ALONEFIX sk=$ALONEREVIEW; sf=$(alonefile "$issue"); } || { pk='' sk=''; false; }; then
      fixproof "$c" "$wt" "$issue" "$sf" "$pk" || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
      pt=$(git -C "$wt" add -A && git -C "$wt" write-tree)
    elif sf=$(speedfile "$issue" "$MAKERUN"); then
      sk=$RUNREVIEW; mk=$sf; runproof "$wt" "$sf" || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    else
      # A run on main that gave no result for a test file, twice (bugproof() exit 2), is blocked with that reason: a
      # build session cannot repair the runner. A main-red fix card is proved by main's failing cases (redproof()):
      # one that does not hold is blocked with that reason (exit 2), and one whose every case passes on main without
      # its change (exit 3) closes as already done, as nochange() closes a card, its change dropped.
      bugproof "$c" "$wt" "$issue"; trc=$?
      if [ $trc = 3 ]; then
        t=$(head -n 1 "$wt.unfixed") && out=$(line "$c" "$n" closed ok "$(jq -cn --arg r "$t" --argjson e "$(ending)" --argjson w "$(waited)" '{reason: $r} + $e + $w')") && locked append "$out" \
          || { block "$c" "$n" "$wt" "build: $(head -n 1 "$wt.unfixed" 2>/dev/null) The engine could not write the closed line"; return; }
        clean "$wt"; return
      fi
      [ $trc != 2 ] || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
      if [ $trc != 0 ]; then
        began "$c" "$n" build
        redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt$more"$'\n\n'"${BUGBUILD//'<why>'/"$BUGWHY"}"$'\n'"$(<"$wt.unfixed")") || { block "$c" "$n" "$wt" "build: $t"; return; }
        checked "$c" "$n" "$wt" "$issue" "$sprompt" build "$(jq -c --arg r "$BUGWHY" '. + {reason: $r}' <<<"$t")" || return
        bugproof "$c" "$wt" "$issue"; trc=$?
        [ $trc != 2 ] || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
        [ $trc = 0 ] || { block "$c" "$n" "$wt" "build: $BUGWHY"$'\n'"$(<"$wt.unfixed")"; return; }
      fi
    fi
  elif [ -z "$br" ] && [ -z "$sf" ] && jq -e --arg t "$TYPE" 'any(.labels[]?; .name == $t)' <<<"$issue" >/dev/null 2>&1; then
    # A retry with no build (land, review: its kept patch, after the owner's yes) of one of the Board's fix issues
    # (#189) is checked as after a build: the kept change lands only on the proof of what lands (pk, pt), and a Make
    # it run card only when its test step ran its file (mk).
    if { pk=$WAITFIX sk=$WAITREVIEW; sf=$(speedfile "$issue" "$pk"); } || { pk=$HOLLOWFIX sk=$HOLLOWREVIEW; sf=$(speedfile "$issue" "$pk"); } \
      || { pk=$DELFILE sk=$DELREVIEW; sf=$(speedfile "$issue" "$pk"); } || { pk=$ALONEFIX sk=$ALONEREVIEW; sf=$(alonefile "$issue"); } || { pk='' sk=''; false; }; then
      fixproof "$c" "$wt" "$issue" "$sf" "$pk" || { block "$c" "$n" "$wt" "$mode: $(<"$wt.unfixed")"; return; }
      pt=$(git -C "$wt" add -A && git -C "$wt" write-tree)
    elif sf=$(speedfile "$issue" "$MAKERUN"); then
      sk=$RUNREVIEW; mk=$sf; runproof "$wt" "$sf" || { block "$c" "$n" "$wt" "$mode: $(<"$wt.unfixed")"; return; }
    fi
  fi
  msg=$(cardsubject "$c" "$issue")
  # A branch that names no issue lands under its own first commit's subject, which names no issue to close.
  [ "$n" != 0 ] || [ -z "$br" ] || msg=$(jq -r --arg c "$c" --arg b "$br" '"\(.title)\n\nConveyor card \($c), branch \($b)"' <<<"$issue")
  prv=$'\n\n'"$PORTREVIEW"$'\n'"The difference is the file $wt.port."; kp=$fromk/$from.patch
  # A NO-GO is fixed and reviewed again; a NO-GO on a last review (review MAX_REVIEWS, counting the rounds a retried
  # card carries, or the one review after a landing conflict, a test fix or the landing gate's lint fix, or one that
  # repeats a finding after its fix with every finding P2 or P3) lands with follow-ups. A GO card whose landing
  # conflicts goes round once more: rebase, review. A finished loop whose landing still conflicts is ported once, as `retry` would port it.
  # Whatever the review, the changed tests pass here before anything is filed or landed.
  while pass=$((${pass:-0} + 1)); do
    redbrief "$c" "$n" "$br"
    # A main-red fix card whose staged change is only the links the engine staged (linksonly()) made no change: the
    # links come with a fix, so with none they are dropped (issue 323).
    git -C "$wt" add -A && ! git -C "$wt" diff --cached --quiet \
      && ! { [ "$n" = 0 ] && [ -z "$br" ] && linksonly "$c" "$wt" && { git -C "$wt" reset -q --hard HEAD || :; }; } || {
      nochange "$c" "$n" "$wt" "$sprompt"; return; }
    trialflag "$wt" # a trial card's pick names the pipeline files its change touches (lib/push.sh)
    # The review gate (lintgate(), lib/lint.sh): a fix of lint findings changed the change, so a kept review, a kept
    # patch's review (land) and a test pass no longer stand for it, and the review of this pass reads all of it.
    lintgate "$c" "$n" "$wt" "$issue" "$sprompt" "$br"; case $? in 1) return ;; 2) kept=''; docpass=''; refix=''; [ "$mode" != land ] || mode='' ;; esac
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
      # review gate runs again on what that fix left.
      if [ -z "$grown" ] && [ -z "$br" ]; then growcheck "$c" "$n" "$wt" "$issue" "$sprompt"; case $? in 1) return ;; 2) refix=''; git -C "$wt" add -A 2>/dev/null
        lintgate "$c" "$n" "$wt" "$issue" "$sprompt" "$br"; [ $? != 1 ] || return; docpass='' ;; esac; fi
      # A fix or rebase session changed a Fix the waiting, Fix hollow cases, Delete it or Make it run alone card: its check runs again on
      # what this review reads, and the card is blocked when it no longer holds.
      if [ -n "$pk" ] && [ "$(git -C "$wt" write-tree)" != "$pt" ]; then
        fixproof "$c" "$wt" "$issue" "$sf" "$pk" || { block "$c" "$n" "$wt" "review $pass: $(<"$wt.unfixed")"; return; }
        pt=$(git -C "$wt" add -A && git -C "$wt" write-tree)
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
        echo "conveyor: card $c: its staged change, main, trailers and D<n> lines are those of its last review: that review stands, with no review session"
      else
        # The one review of a port reads what the port changed: the kept patch against the staged change.
        if [ -n "$fin" ]; then
          finrev=$(<"$wt.review")
          diff -u --label kept --label ported <(sed '/^index /d' "$kp") \
            <(git -C "$wt" diff --cached --binary --no-renames | sed '/^index /d') > "$wt.port"
          [ $? -le 1 ] || { rm -f "$wt.port"; block "$c" "$n" "$wt" "review $pass: the engine could not compare the port with the kept patch"; return; }
        fi
        # The review right after a fix of review findings also sees what that fix was told and changed (rereview()):
        # not part of seen, so a fix that changed nothing still reuses the last review. It reviews the fix alone, its
        # instructions opening with FIXREVIEW in place of REVIEWHEAD, unless the fix touches more than the pack's
        # review.rereviewWhole share of the change's lines (fixonly()): then it reviews the whole change.
        ins=$rv${fin:+$prv}; rr=''
        [ -z "$refix" ] || [[ $ins != "$REVIEWHEAD"* ]] || ! fixonly "$wt" "$refix" || { rr=fix; ins=$FIXREVIEW${ins#"$REVIEWHEAD"}; }
        redbrief "$c" "$n" "$br"; t="the engine could not write the re-review section"; { [ -z "$refix" ] || more+=$'\n\n'"$(rereview "$c" "$wt" "$refix" "$rr")"; } \
          && t=$(reviewed "$wt" "$sprompt$more" "$ins"); rc=$?; rm -f "$wt.port"
        [ $rc = 0 ] || { block "$c" "$n" "$wt" "review $pass: $t"; return; }
        # The judge (judged()): a finding it declines is no finding from here on, and a review left with none is a GO.
        redbrief "$c" "$n" "$br"; t=$(judged "$c" "$n" "$wt" "$sprompt" "$t")
        # The P3 findings it leaves, with the rule P3 off, are listed only (minor()).
        minor "$wt"
      fi
      refix=''
      res=$(verdict "$wt.review"); vis=$(visible "$wt.review" "$vmode"); unclear=''
      [ -n "$vis" ] || { [ "$res" = none ] || unclear=": it does not hold exactly one USER-VISIBLE line, written as asked"; res=none; }
      # A NO-GO's line names the findings that came back after a fix round told to fix them (survived: id, rounds), for the Board.
      # Every review's line keeps its answers on the findings fix rounds were told, each beside its first location
      # and proof (answers()), so a review that blocks or ends the loop keeps them too.
      sv='[]'; [ "$res" != NO-GO ] || sv=$(repeats "$wt" | jq -sc 'map({id, rounds})')
      an=$(answers "$wt")
      # doneWhenHolds: the D<n> its `DONE-WHEN: D<n> holds` lines name, which the reason leaves out (UNRECORDED); the
      # Board reads them on demand (history donewhen). excerpts: the lines its findings cite, from the tree it read
      # (excerpts(), lib/review.sh), which the Board reads on demand too (history excerpts); after a fix round, also
      # from the tree before that fix (fixtree), which holds the lines the fix deleted.
      ex=$(excerpts "$wt" "$fixtree"); fixtree=''
      # The line is written once the loop's end is known (stop, below); a review with no verdict blocks with it here.
      rline=$(grep -Ev "$UNRECORDED" "$wt.review" | jq -cRs --arg res "$res" --argjson t "$t" --arg v "$vis" --argjson k "$(counts "$wt.review")" --arg p "$cpid" --arg m "$chead" --arg s "$cseen" --argjson sv "${sv:-[]}" --argjson an "${an:-[]}" \
        --argjson ro "$(rollouts "$wt.review" ROLLOUT)" --argjson h "$(sed -n 's/^DONE-WHEN: D\([0-9][0-9]*\) holds[[:space:]]*$/\1/p' "$wt.review" | jq -sc 'unique')" --argjson ex "${ex:-[]}" \
        'sub("\n+$"; "") as $r | $t + {reason:$r,visible:$v,counts:$k,patch:$p,main:$m,seen:$s} + (if $res == "NO-GO" then {tail: $r} else {} end) + (if $sv == [] then {} else {survived: $sv} end) + (if $an == [] then {} else {answers: $an} end) + (if $h == [] then {} else {doneWhenHolds: $h} end) + (if $ro != [] then {rollout: $ro} else {} end) + (if $ex == [] then {} else {excerpts: $ex} end)')
      [ -n "$rline" ] || rline='{}' # the grep finds no line in a review of only unrecorded lines: that is no failure
      [ "$res" != none ] || { record "$c" "$n" review "$res" "$rline"; block "$c" "$n" "$wt" "review $pass ended without one clear verdict$unclear"; return; }
    fi
    # A GO on the review of a port lands with the earlier loop's outcome: after its last NO-GO, that review's
    # findings are filed again, whatever the reviews after a test fix say. A NO-GO on it is fixed and goes round the
    # loop as any card's.
    last=''; [ "$fin" != NO-GO ] || [ "$res" != GO ] || { earlier=$finrev; earlyend=$finend; }; fin=''
    # A NO-GO that repeats a finding a fix round was told to fix (repeats()) spends no more rounds on it: when every
    # finding of the review is P2 or P3 this is the last review; when a repeated one is P0 or P1 the card blocks.
    rep=''; [ "$res" != NO-GO ] || rep=$(repeats "$wt")
    hard=$(jq -rs 'map(select(.level == "P0" or .level == "P1")) | first // empty | "\(.line[:300]) did not hold after \(.rounds) round\(if .rounds == 1 then "" else "s" end)"' <<<"$rep")
    # A last NO-GO with a finding that is a privacy hit in the card's own change (privown(), lib/followups.sh) gets
    # one more fix round, once a card: a follow-up would land the hit on main. Bug: such a finding was filed as a
    # follow-up that the privacy check refused, and the card was blocked.
    # stop: why this review ends the loop (loopstop()), empty when a fix round follows (or the card blocks).
    priv=''; stop=''
    if [ -z "$hard" ]; then
      stop=$(loopstop "$res" "$((pass + rounds))" "$rebased" "$tfix" "$lfix" "$mode" "$rep" "$wt.review")
      [ -z "$stop" ] || [ "$res" = GO ] || [ -n "$privfix" ] || ! priv=$(privown "$wt") || [ -z "$priv" ] || stop=''
    fi
    # The review line, and the filed line after it, say why the loop ended: stop, with pass and rounds as they are here.
    ended=$(jq -cn --arg s "$stop" --argjson p "$pass" --argjson r "$rounds" 'if $s == "" then {} else {stop: $s, pass: $p, rounds: $r} end')
    [ -z "$rline" ] || record "$c" "$n" review "$res" "$(jq -c --argjson e "$ended" '. + $e' <<<"$rline")"; rline=''
    [ -z "$hard" ] || { block "$c" "$n" "$wt" "the fix for $hard"; return; }
    if [ "$res" = GO ] && [ -z "$earlier" ]; then mode=''
    elif [ -n "$stop" ]; then
      # A card whose issue is a follow-up at the depth cap (fudepth(), lib/followups.sh) files none: its findings are
      # declined. A depth that cannot be read counts as the cap.
      mode=''; last=1; isfu=1; d=$(fudepth "$issue") && [ "$d" -lt "$MAX_DEPTH" ] && isfu=''
    else
      # A NO-GO with no finding (an UNPROVEN line alone, say) has nothing for a fix session to fix, or to number: the
      # card blocks with the reviewer's own line (its first UNPROVEN line, else its VERDICT line), cut at 200 characters.
      grep -Evq "$NOTFINDING" "$wt.review" || { why=$(grep -m1 '^UNPROVEN:' "$wt.review" || grep -m1 '^VERDICT:' "$wt.review")
        block "$c" "$n" "$wt" "review $pass is NO-GO with no finding to fix: ${why:0:200}"; return; }
      # A card stacked on this one (stackto()) that passed its tests goes on during this round, fitted onto main alone
      # (giveway(), claim()).
      [ -z "$priv" ] || { privfix=1; echo "conveyor: card $c: a finding of its last review is a privacy hit in its own change, so it goes to one more fix round: ${priv:0:200}"; }
      locked giveway "$c" "$wt" fix; began "$c" "$n" fix
      old=$(git -C "$wt" write-tree); more=''; [ -z "$rep" ] || more=$'\n\n'"$(again "$rep")"
      # The fix is told the accepted findings only: a finding the judge declined (a DECLINED line), a P3 listed only
      # (a MINOR line, minor()), or a rollout action (a ROLLOUT line, no defect), is not its to fix. Each finding it is told is led by its id (numbered(), fixlines()).
      # It runs on the fix seat (seat(): the builder's unless the control record sets fix).
      ids=$(numbered "$wt") && fl=$(fixlines "$wt" "$ids") || { block "$c" "$n" "$wt" "fix: the engine could not give the review's findings their ids"; return; }
      redbrief "$c" "$n" "$br"; t=$(session "$wt" "$(fixprompt "$sprompt" "$fl$more")" fix fix) || { block "$c" "$n" "$wt" "fix: $t"; return; }
      checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$t" || return
      # This fix round's findings, with their ids, and the diff it made, for the review after it (repeats(), rereview()).
      mkdir -p "$wt.rounds" && git -C "$wt" add -A && git -C "$wt" diff "$old" "$(git -C "$wt" write-tree)" > "$wt.rounds/$((pass + rounds)).diff" \
        && rounded "$wt" "$((pass + rounds))" "$ids" && refix=$((pass + rounds)) && fixtree=$old
      continue
    fi
    # This review would let the card land. A change customers or staff would see needs the owner's yes first, when
    # the card touches product code: its staged change, both sides of a rename, names a path PRODUCT counts.
    # A follow-up with no line of its own lands on its parent's yes when its reviewer says its visible change is part
    # of that approved change; one that goes beyond it stops, and the reason names what goes beyond.
    # A card held to the section the owner approved before the build lands on a review that says its change matches
    # that section, with no second ask; one that differs stops, and the ask names the difference only. A section
    # saying nothing visible changes is no yes: a visible change stops as it would with no section. With the rule
    # "visible changes need the owner's yes" off, none of this holds a card.
    # A card that stops here keeps the issue body this review read (.body; keptway(): its retry lands only on it).
    # A change of lint policy (lintpolicy(), lib/lint.sh) needs the owner's yes too, with the rule Lint check on,
    # whatever the rule on visible changes says. The card that stops for it keeps the hash of its policy diff in its
    # .body (policy), and the yes covers that diff only (lintyes()): an approval line after that stop. A card that
    # stops for a visible change as well stops once, its reason naming the policy files (pf) too.
    yesfrom='' ph='' pf=''
    if lintrule; then
      { packget lint pf && pf=$(lintpolicy "$wt" "$(git -C "$wt" rev-parse HEAD)" "$pf"); } || { block "$c" "$n" "$wt" "lint: the engine could not read the lint policy files that the change changes, so nothing landed"; return; }
      ph=${pf%%$'\n'*}; pf=$(tail -n +2 <<<"$pf" | jq -Rrs 'split("\n") | map(select(. != "")) | join(", ")')
      pb=$fromk/$from.body; [ -n "$from" ] && [ -e "$pb" ] || pb=$CARDS/$from.body
      [ -z "$pf" ] || [ -z "$from" ] || ! lintyes "$issue" "$pb" "$ph" || { echo "conveyor: card $c: its lint policy change is the one $OWNER approved"; pf=''; }
    fi
    if [ -n "$heldto" ] && git -C "$wt" diff --cached --no-renames --name-only | productpaths; then
      case $vis in
        matches) echo "conveyor: card $c: what it shows matches the change $OWNER approved before the build" ;;
        "differs: "*) printf '%s\n' "$nyes" > "$wt.approvals"; jq -c --arg p "$ph" '{body} + (if $p == "" then {} else {policy: $p} end)' <<<"$issue" > "$wt.body"; block "$c" "$n" "$wt" "${YES}it differs from the change approved before the build: ${vis#differs: }${pf:+; it also changes lint policy: $pf}" post; return ;;
        *) printf '%s\n' "$nyes" > "$wt.approvals"; jq -c --arg p "$ph" '{body} + (if $p == "" then {} else {policy: $p} end)' <<<"$issue" > "$wt.body"; block "$c" "$n" "$wt" "${YES}the review did not say whether it matches the change approved before the build${pf:+; it also changes lint policy: $pf}" post; return ;;
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
      [ -n "$yesfrom" ] || { [ "$seen" != nothing ] || printf '%s\n' "$nyes" > "$wt.approvals"; jq -c --arg p "$ph" '{body} + (if $p == "" then {} else {policy: $p} end)' <<<"$issue" > "$wt.body"; block "$c" "$n" "$wt" "$YES${vis#yes: }$more${pf:+; it also changes lint policy: $pf}" post; return; }
      echo "conveyor: card $c: its visible change is part of the change $OWNER approved in #$yesfrom: the yes is inherited"
    fi
    [ -z "$pf" ] || { jq -c --arg p "$ph" '{body, policy: $p}' <<<"$issue" > "$wt.body"; block "$c" "$n" "$wt" "${LINTYES}it changes lint policy: $pf" post; return; }
    # The trailers the pack requires of the files this change adds (commit.trailers): one session per card writes
    # those the card has not; still missing, the card blocks, never committing without them. A session that changed
    # the change or its trailers goes round to be reviewed again.
    owe=$(owing "$wt") || { block "$c" "$n" "$wt" "the engine could not read the commit trailers that the pack requires. Each when value must be a valid extended regular expression. Nothing landed"; return; }
    if [ -n "$owe" ] && [ -z "$tsess" ]; then
      tsess=1; old=$(git -C "$wt" write-tree); cmsg=$(trailers "$wt") || { block "$c" "$n" "$wt" "the engine could not read the commit trailers of the card, so nothing landed"; return; }
      began "$c" "$n" fix
      redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt"$'\n\n# A commit trailer is missing: write it and change nothing else\nThis change adds files that need a line in '"$wt.trailers"$', and that file has none for them:'"$(jq -r '"\n- `\(.token): <text>`: \(.ask) It adds \(.paths | join(", "))."' <<<"$owe")" fix) \
        || { block "$c" "$n" "$wt" "fix: $t"; return; }
      checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$(jq -c --arg r "missing commit trailers: $(jq -r .token <<<"$owe" | paste -sd ' ' -)" '. + {reason: $r}' <<<"$t")" || return
      git -C "$wt" add -A && [ "$(git -C "$wt" write-tree)" = "$old" ] && [ "$(trailers "$wt")" = "$cmsg" ] || continue
    fi
    [ -z "$owe" ] || { block "$c" "$n" "$wt" "a commit trailer the pack requires is missing after its one fix session; nothing landed: $(jq -rs 'map("\(.token) (it adds \(.paths | join(", ")))") | join("; ")' <<<"$owe")"; return; }
    # The trailers the commit carries are these, read here where they were reviewed and checked: nothing after (the
    # tests) changes them.
    cmsg=$(trailers "$wt") || { block "$c" "$n" "$wt" "the engine could not read the commit trailers of the card, so nothing landed"; return; }
    # Its rollout actions (rollouts()): those its reviews named (its retried cards' review lines' (pro), its own lines', then its kept review's, as a card
    # that lands from a kept patch has no review line of its own), then its Rollout trailers, each once and in the order
    # named (ROLLOUTONCE). All go on its landed line (rollout) and, in that order, at the end of the commit message as
    # Rollout lines in place of its Rollout trailers, so the push carries each one. They are no findings: nothing here
    # holds the card.
    rtr=$(rollouts <(printf '%s\n' "$cmsg") Rollout) && rrev=$(rollouts "$wt.review" ROLLOUT) \
      && ro=$(stdb ask card "$c" | jq -cs --argjson p "$pro" --argjson k "$rrev" --argjson t "$rtr" '[$p[], (.[] | select(.step == "review") | .rollout // [] | .[]), $k[], $t[]] | '"$ROLLOUTONCE") \
      && rmsg=$(jq -r '.[] | "Rollout: \(.action) | \(.fails) | \(.place)"' <<<"$ro") \
      || { block "$c" "$n" "$wt" "the engine could not read the rollout actions of the card, so nothing landed"; return; }
    cmsg=$(grep -Ev "^Rollout: $ROLLOUT" <<<"$cmsg" || :); cmsg=$cmsg${cmsg:+${rmsg:+$'\n'}}$rmsg
    # A main-red fix card names its cases and main's commit, as its entry holds them now (a case added during its
    # build or a review too).
    [ "$n" != 0 ] || [ -n "$br" ] || msg=$(t=$(redissue "$c") || t=$issue; jq -r --arg c "$c" --arg s "$(stdb ask card "$c" | jq -rs 'map(.mainRed // empty)[0] // ""')" \
      '"fix(product): \(.title) (main \($s[0:12]))\n\nConveyor card \($c)"' <<<"$t")
    # The card's commit trailers go into the message after its Closes line (before the card line).
    cmsg=$(jq -rn --arg m "$msg" --arg t "$cmsg" 'if $t == "" then $m else $m | sub("\nConveyor card "; "\n\($t)\nConveyor card ") end')
    # Same-file cards (at settle()): it holds its files from its landing step through its tests and landing, unless
    # it waits here on a card that holds one of them or goes before it. Its patch still applying to main, it goes on
    # with no second review (unless an ordered card went past it and main moved: then it is reviewed again on main);
    # a change a session had to bring onto main since is reviewed again, giving way meanwhile (giveway()), unless the
    # session left its change outside documentation (*.md) as it was (settle(), and the rebuild below). A card that
    # gave way runs its checks and tests first, holding nothing, and claims only once they passed (ready): its change
    # applying to main then. Any card lands only on main as its worktree holds it: when main moved since its checks and
    # tests ran (while it was away, during its tests or before its landing), its change is fitted onto main as it is now,
    # holding its files, and its product checks run again there, until main stays where they ran; land() checks that
    # under the lock. Its tests run again only when the fitted change is not the one that passed (testedhere(): a
    # session changed it, or brought it onto main when it no longer applied, or its test files were merged keeping
    # both sides; a clean three-way merge onto main is the change that passed, settle(), and so is one a session changed
    # only in documentation files, settle() and the rebuild marking it tested again), and when the cards landed since
    # its last run touch a test file its change touches too (sharedtests(): two changes that passed apart can fail
    # together, #334), once for the change it holds: after that run passed it lands on it (#447). That run keeps the passes of the run before but those of the shared
    # files, which it runs whole (unshare()), its list naming what main changed (rerunsince()); a failure there goes to
    # the card's fix, as main alone passes it.
    # Batches: after a GO it is ready to land once its own checks and tests pass (tested()), and a batch may take it
    # while it waits (gather()); one with follow-ups to file lands on its own. Holding its files on main as it is now,
    # its tests passed, it takes the ready cards that share them, and one run judges them all (batch()). Tests that
    # passed while it waited on what its worktree still holds are not run again (testedhere()). A card that files a
    # last NO-GO's follow-ups keeps its pass there too, marked alone: no batch takes it or is taken by it.
    # Its extra's waitSec is what it has waited so far; settle() keeps it up to date while it waits (a batch lands it).
    rm -f "$wt.ready"; jq -cn --argjson i "$n" --arg m "$cmsg" --argjson y "${yesfrom:-null}" --argjson a "$([ -n "$last" ] && echo true || echo false)" --argjson w "$((waitsec + mainsec))" --argjson ro "$ro" \
      '{issue: $i, msg: $m, extra: ({waitSec: $w} + (if $y then {yesFrom: $y} else {} end) + if $ro != [] then {rollout: $ro} else {} end)} + (if $a then {alone: true} else {} end)' > "$wt.ready"
    # Back from the landing rebuild with its change outside documentation the one that passed its tests (docpass): it
    # lands on that run, with only its product checks run again.
    [ -z "$docpass" ] || { [ "$docpass" != "$(cardpatch "$wt" ':(exclude)*.md')" ] || tested "$wt"; docpass=''; }
    away=''; jq -e '.away == true' "$wt.claim" >/dev/null 2>&1 && away=1
    trc=''
    if [ -z "$away" ]; then
      redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
      [ $rc != 1 ] || return
      [ $rc != 3 ] || break # a batch landed it
      [ $rc = 0 ] || [ $rc = 4 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; continue; }
    fi
    merged=''
    while :; do
      if [ -n "$trc" ]; then
        # Its own tests failed while it waited, or it broke the tests of the batch that took it: that run's exit and
        # output are its own. No run of its own tests is on this pass (own: carriedrec(), slowrec()).
        rc=$trc; trc=''; own=''; rm -f "$wt.ready"
      else
        # After a merge onto main (settle(), the rebuild, the port), before any check or test runs: every file it
        # changed still parses (parses()). One that does not goes to one fix session, given each such file and its
        # error; still failing after it, the card blocks. Nothing lands meanwhile. Its tests then run whole, a merge in
        # doubt (<worktree>.whole, tests()): no pass of the change before the merge is kept (rerunsince()).
        if [ -n "$parsecheck" ]; then
          out=$(parses "$wt"); t=$?
          if [ $t = 0 ]; then parsecheck=''
          else
            [ $t = 1 ] || { block "$c" "$n" "$wt" "the engine could not check that the files of the merge onto main parse, so nothing landed: $out"; return; }
            [ -z "$pfix" ] || { block "$c" "$n" "$wt" "a file the card's merge onto main changed still does not parse after its one fix session; nothing landed."$'\n'"$out"; return; }
            pfix=1; rm -f "$wt.ready" "$wt.rerun"; echo 'merge in doubt: a file of the merge onto main did not parse' > "$wt.whole"; locked giveway "$c" "$wt" fixing; began "$c" "$n" fix
            redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt"$'\n\n# A file no longer parses after the card\'s change was merged onto main: fix that and nothing else\nA merge can keep lines of both sides that do not go together. Each file that fails, the check run on it and its output:\n'"$out" fix) \
              || { block "$c" "$n" "$wt" "fix: $t"; return; }
            checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$(jq -c --arg r "a file no longer parses after the merge onto main: $(sed -n 's/: `.*` failed:$//p' <<<"$out" | paste -sd ' ' -)" '. + {reason: $r}' <<<"$t")" || return
            continue 2
          fi
        fi
        # The landing gate (lintgate(), lib/lint.sh), before any check or test: a fix of lint findings goes round to a
        # review, a last review (lfix), and back here, where a finding left on the change that fix left blocks.
        lintgate "$c" "$n" "$wt" "$issue" "$sprompt" "$br" land; case $? in 1) return ;; 2) kept=''; docpass=''; continue 2 ;; esac
        # The product checks, on every pass that would land: a failure blocks the card, never a finding to fix. Not on
        # the pass that runs again on main as it is now what failed in a red run (tmain): there a failing check is that
        # red run failing again, as a check that fails on a batch's change is a red run (batch()), and goes to the one
        # fix round; on the passes after the fix it blocks again.
        if ! out=$(checks "$wt"); then
          [ -n "$tmain" ] || { block "$c" "$n" "$wt" "a product check failed; nothing landed."$'\n'"$out"; return; }
          norun "$wt" "a product check failed on the change of $c on main as it is now:"$'\n'"$out"; sec=0; trc=1; continue
        fi
        # The changed tests, before the follow-ups are filed: a card that fails them twice files nothing.
        began "$c" "$n" test
        # The project's checks first (treecheck(): kept for the tree the last session's check ran on, so not run again
        # there). When they fail, the step ends before any test file runs, its line holding one failure that names
        # the check and its output. That is not its tests failing: the one test-fix round (tfix) is kept and the card
        # is not blocked for it; one fix session is told the output, and checked() runs the checks again on its change.
        # The line is marked checks: no test ran, so the card's first run of its tests is still its first (testedbefore()).
        out=$(treecheck "$wt"); t=$?
        [ $t != 2 ] || { block "$c" "$n" "$wt" "the engine could not run the project's checks: $out"; return; }
        if [ $t = 1 ]; then
          packget test.checkCommand t || t=test.checkCommand
          record "$c" "$n" test fail "$(jq -cn --arg k "$t" --arg o "$out" '{reason: "the project'"'"'s checks failed (test.checkCommand: \($k)); no test file ran",
            checks: true, failures: {of: 0, files: [{file: $k, cases: []}], timeout: null}, tail: ($o | .[-4000:])}')"
          rm -f "$wt.ready"; locked giveway "$c" "$wt" fixing; began "$c" "$n" fix
          redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt"$'\n\n'"$CHECKFIX"$'\n'"$out" fix) || { block "$c" "$n" "$wt" "fix: $t"; return; }
          checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$(jq -c '. + {reason: "the project'"'"'s checks failed (test.checkCommand)"}' <<<"$t")" || return
          continue 2
        fi
        [ -z "$away" ] || away=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)
        sec=$SECONDS; rc=0; ran=''; own=''; apart=''; repaired=''; TEST_BATCH=''; TEST_REFUSED=''; rm -f "$wt.stop"
        # The times its own run took go on its test line (slowtests()); only a test rule files an issue about a test
        # file (testrulespass(), after the test line is recorded).
        testedhere "$wt" || own=1
        # Its shared files run again once for the change it holds (<worktree>.sharedran: that change's patch-id, once
        # that run passed): on a busy main, each run again let another card land on them, and the card never landed
        # (#447). A failure of the two changes together that this lets onto main is caught there (main red).
        shared=''; sb=$(sed -n 's/^base\t//p' "$wt.rerun" 2>/dev/null)
        if [ -z "$own" ] && t=$(sharedtests "$wt" "$sb"); then
          if [ "$(cat "$wt.sharedran" 2>/dev/null)" = "$(cardpatch "$wt")" ]; then
            echo "conveyor: card $c: cards landed since its shared test files ran again touch them too ($(paste -sd ' ' <<<"$t")); they ran again once, so it lands with no second run again. Cards landed since: $(landedsince "$wt" "$sb")"
          else own=1; shared=1; unshare "$wt" "$t"; echo "conveyor: card $c: cards landed since its tests ran touch its test files too, so they run again on main as it is now: $(paste -sd ' ' <<<"$t")"; fi
        fi
        [ -z "$own" ] || { ran=1; tests "$wt"; rc=$?; [ $rc != 0 ] || slowtests "$wt" || :; }
        [ $rc != 0 ] || [ -z "$own" ] || tested "$wt"
        [ $rc != 0 ] || [ -z "$shared" ] || cardpatch "$wt" > "$wt.sharedran" || rm -f "$wt.sharedran"
        if [ $rc = 0 ] && [ -z "$away" ] && [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" ]; then
          out=$(locked gather "$c" "$wt" "$me") || out=''
          # A full run its own run refused (tests()) stays on the line its batch's run writes.
          rf=$TEST_REFUSED; [ -z "$out" ] || { t=$ran; ran=1; batch "$c" "$wt" $out; rc=$?; [ -z "$apart" ] || ran=$t; }; TEST_REFUSED=${TEST_REFUSED:-$rf}
        fi
        # Main moved during its batch's run: the batch lands on that run when it still stands there (rebatch()). A
        # product check that fails on its change there is a red run: the batch is run again there, as batch() does one.
        back=''
        if [ ${#mates[@]} != 0 ]; then
          rebatch "$c" "$wt"; t=$?
          [ $t != 2 ] || { block "$c" "$n" "$wt" "the engine fitted the batch of the card onto main, but it could not put the change of the card back in its worktree. Nothing landed. The change is in the patch $wt.bpatch"; return; }
          [ $t != 3 ] || { ran=1; batch "$c" "$wt" "${mates[@]}"; rc=$?; }
        fi
        sec=$((SECONDS - sec))
        # It broke its batch, or its patch did not apply on the cards before it there: the cards that passed land without it.
        if { [ $rc != 0 ] || [ -n "$apart" ]; } && [ ${#mates[@]} != 0 ]; then
          mapfile -d '' t5 < <(fives "$c" "$n" "$wt" "$cmsg" '' skip)
          t=$(locked land "${t5[@]}") || { echo "conveyor: card $c: the cards of its batch that passed did not land: $t"; unmate; }
          mates=()
        fi
        [ -z "$back" ] || { git -C "$wt" reset -q --hard "$back" 2>/dev/null && git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null; } \
          || { block "$c" "$n" "$wt" "the batch of the card landed, but the engine could not put the change of the card back in its worktree. The change is in the patch $wt.bpatch"; return; }
        rm -f "$wt.lent" # its worktree holds its own change again (batch())
      fi
      # Its run did not run (no test.fileCommand), or was stopped, as it would have run more than the tests of its
      # change (tests(): <worktree>.stop): no run on main and no fix session, as a session cannot change the pack.
      # The card is blocked with that reason, which names the setting that fixes it.
      [ ! -s "$wt.stop" ] || { block "$c" "$n" "$wt" "test: $(<"$wt.stop")"; return; }
      voidrun "$wt" "$rc" > /dev/null || voids=0 # a run with a result, a pass too, starts the count of runs with none again
      if [ $rc != 0 ]; then
        # The worktree lacks a dependency folder main has (depsmissing(), lib/push.sh): the failure is the project's
        # setup, not the change, and no run on main or fix session mends it. The card is blocked saying so, with no
        # test failures.
        t=$(depsmissing "$wt"); [ -z "$t" ] || { block "$c" "$n" "$wt" "$(depsreason "$t")"; return; }
        # A run with no result (voidrun(): killed by a signal, as by the service stopping or restarting, also under a
        # loop that adopted the card) proves nothing: nothing of it runs on main, goes to the main-red record, a wait
        # for main or a fix session. Its test line says so, and the test step runs again; the third such run in a row
        # blocks the card (a run with a result, a pass too, starts the count again: above).
        # Its own run's files kept as passed and not run (carriedrec()): the step that ran them is an earlier one.
        cr='{}'; [ -z "$own" ] || cr=$(carriedrec "$wt")
        if t=$(voidrun "$wt" "$rc"); then
          voids=$((voids + 1))
          record "$c" "$n" test fail "$(tail -n 60 "$wt.test" 2>/dev/null | tr -d '\000' | jq -cRs --slurpfile x <(testrec "$wt" "$rc" "$sec") --slurpfile o <(printf '%s' "$cr") --arg r "no result: $t" \
            '$x[0] as $x | $o[0] as $o | sub("\n+$"; "") as $t | $x + $o + {reason: $r} + (if $t == "" then {} else {tail: $t} end)')"
          [ "$voids" -lt 3 ] || { block "$c" "$n" "$wt" "the changed tests gave no result 3 times in a row ($t); nothing landed."; return; }
          echo "conveyor: card $c: its test run gave no result ($t): the test step runs again"
          continue
        fi
        out=$(testfails "$wt.test" "$rc")
        # What still did not pass runs on main first (verdicts()): each failure's verdict goes on the test line.
        t=$(verdicts "$c" "$wt" "${out:-null}") || t='{"verdicts":[]}'
        # The machine is at fault (verdicts(): machine, issue 221), with no failure the card's: its test line is `held`,
        # not `fail` (the card's test step is not counted as failed), and it waits for the machine hold (below).
        held=''; jq -e '[.verdicts[] | select(.verdict != "flaky")] | length > 0 and all(.verdict | IN("main", "machine")) and any(.verdict == "machine")' <<<"$t" >/dev/null && held=machine
        record "$c" "$n" test "$([ -n "$held" ] && echo held || echo fail)" "$(failline "$wt" "$rc" "$sec" "${out:-null}" "$t" "$cr")"
        testrulespass > /dev/null
        # Main is red: every failure the run again left fails on main too. The card waits in its test step, holding no
        # files (no fix session, no block) until main changes; then it is fitted onto main and tested again, as a card
        # whose main moved during its tests is. It is not put back on its old commit (#582): caught is cleared, so a
        # change that no longer applies there is brought onto main by a session, even after the landing's rebuild.
        # The machine is at fault (verdicts(): machine, issue 221), with no failure the card's: no fix session, no
        # block and no wait for main. The card waits, holding no files, until the machine hold goes (holdwait()), then
        # is fitted onto main as it is then and tested again, as after a wait for main. Before it waits, it is judged
        # in the repair lane (repairlane(), issue 222): a card the lane passes goes on as a card whose tests passed;
        # one that finds the lane held by another card waits until it is free, and is then tested and judged again.
        if [ "$held" = machine ]; then
          lane=0; repairlane "$c" "$wt" || lane=$?
          if [ $lane = 0 ]; then
            echo "conveyor: card $c: a case it still fails is the machine's, and the card repairs it: $REPAIRED"
            repaired=$REPAIRED; held=''; rc=0; tmain=''
          else
            if [ $lane = 2 ]; then echo "conveyor: card $c: a case it still fails is the machine's: it waits for the repair lane, which another card holds"
            else echo "conveyor: card $c: a case it still fails is the machine's, not main's, and the repair lane did not pass it ($REPAIRED): it waits until the machine passes its controls again"; fi
            rm -f "$wt.ready"; locked giveway "$c" "$wt"; began "$c" "$n" test
            holdwait "$wt" "$([ $lane != 2 ] || echo lane)"; held=1
          fi
        elif jq -e '[.verdicts[] | select(.verdict != "flaky")] | length > 0 and all(.verdict == "main")' <<<"$t" >/dev/null; then
          echo "conveyor: card $c: every case it still fails fails on main too: it waits for main to change"
          rm -f "$wt.ready"; locked giveway "$c" "$wt"; began "$c" "$n" test
          mapfile -t mwon < <(jq -r '.mainRun.sha, (.verdicts[] | select(.verdict == "main") | .case)' <<<"$t")
          mw=$SECONDS; mainwait "$wt" "${mwon[@]}"; held=1
          mainsec=$((mainsec + SECONDS - mw))
        fi
        if [ -n "$held" ]; then
          unmate; away=''; caught=''
          redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
          [ $rc != 1 ] || return
          [ $rc != 3 ] || break 2 # a batch landed it
          [ $rc != 4 ] || continue
          [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; continue 2; }
          continue
        fi
        # Main moved since the card's commit (#582: it may have fixed what failed there, which the card's run did not
        # hold): the change is first fitted onto main as it is now and what failed runs again there, before any fix
        # round. Once before each fix round, so a card whose own change fails does not follow a busy main for ever.
        # caught is cleared, as after a wait on a red main above: a change that no longer applies on main is brought there
        # by a session, not put back on its old commit (settle()), where what failed would only run again as it did.
        # Fitted there (settle() claims its files again), it gives way for that run, as for a fix round (fixing): a card
        # stacked on it (stackto()) is fitted onto main alone and lands, not waiting through this run (claim()).
        if [ -z "$repaired" ] && [ -z "$tmain" ] && [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" ]; then
          echo "conveyor: card $c: main moved since its commit: its change goes onto main as it is now, and what failed runs again there"
          tmain=1; rm -f "$wt.ready"; unmate; away=''; caught=''
          redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
          [ $rc != 1 ] || return
          [ $rc != 3 ] || break 2 # a batch landed it
          [ $rc != 4 ] || continue
          [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; continue 2; }
          # Away now, it claims its files again (settle()) once that run passes, before it lands, main moved or not.
          locked giveway "$c" "$wt" fixing; ! jq -e '.away == true' "$wt.claim" >/dev/null 2>&1 || away=1; continue
        fi
        if [ -z "$repaired" ]; then
          tmain=''
          [ -z "$tfix" ] || { block "$c" "$n" "$wt" "the changed tests failed again after their one fix round (exit $rc); nothing landed."$'\n'"$(tail -n 60 "$wt.test" 2>/dev/null | tr -d '\000')"; return; }
          tfix=1; locked giveway "$c" "$wt" fixing; began "$c" "$n" fix
          # On the testFix seat (seat(): the builder's unless the control record sets testFix).
          redbrief "$c" "$n" "$br"; t=$(session "$wt" "$(testfixprompt "$sprompt" "$wt" "$rc")" fix testFix) \
            || { block "$c" "$n" "$wt" "fix: $t"; return; }
          checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$t" || return
          continue 2
        fi
      fi
      # Not run again when they passed on what its worktree still holds (that run has its own line): this line says it
      # reused that pass.
      # A batch's run (batch(): TEST_BATCH) says in selected how many passes it kept, and no case ran when it ran none.
      # A card the repair lane passed (repairlane()): its line says so, with the clean run of its changed tests.
      if [ -n "$repaired" ]; then record "$c" "$n" test pass "$(jq -cn --slurpfile x <(testrec "$wt" 0 "$sec") --arg r "$repaired" '$x[0] + {reason: $r}')"
      elif [ -n "$ran" ]; then record "$c" "$n" test pass "$(jq -cn --slurpfile x <(testrec "$wt" 0 "$sec") --slurpfile r <(firstrun "$wt" pass) --argjson b "${TEST_BATCH:-null}" \
        --slurpfile s <([ -z "$own" ] && echo '{}' || slowrec "$wt") '$x[0] + $r[0] + $s[0] | if $b then .selected += $b else . end')"
      else record "$c" "$n" test pass "$(jq -cn --argjson s "$sec" '{sec:$s,usage:{input:0,write:0,write1h:0,read:0,output:0},reused:true}')"; fi
      # The test rules read the line just recorded (lib/testrules.sh): with their switch off, they file nothing.
      [ -z "$ran" ] || testrulespass > /dev/null
      # A Make it run card (#189) holds only when its test step ran its file and the file passed.
      [ -z "$mk" ] || t=$(ranproof "$wt" "$mk") || { block "$c" "$n" "$wt" "test: $t"; return; }
      # A card that gave way claims its files now; a card whose change is not on main as it is now (main moved while it
      # was away or during its tests) is fitted onto it, and its checks run again there, holding its files (its tests
      # too when the fitted change is not the one that passed: testedhere()).
      # A change that no longer applies there is put back as it was (caught) and meets the conflict at landing; one
      # apart from its batch (batch()), which landed, is brought onto main by one session, as a waiting card is.
      if [ -n "$away" ] || [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" ]; then
        [ -n "$away" ] && [ "$away" = "$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" ] || [ -n "$apart" ] || caught=1
        t=${#mates[@]}; unmate; old=$(git -C "$wt" rev-parse HEAD 2>/dev/null); away=''
        redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
        [ $rc != 1 ] || return
        [ $rc != 3 ] || break 2 # a batch landed it
        [ $rc != 4 ] || continue
        [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; continue 2; }
        [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$old" ] && [ "$t" = 0 ] || continue
      fi
      # Apart from its batch for its lint (lintleave(), lib/lint.sh): it goes back to its landing gate, also when main
      # did not move (its batch run on main as it moved, rebatch(), lands no other card), so it never lands on that finding.
      [ "$apart" != lint ] || continue
      while :; do
        # An ordered or a ready card went past this one since its claim (it holds its files only from its landing step,
        # so that is where it is passed): it claims again, waits for that card, and is fitted onto main as that card
        # left it. Gone past by an ordered card, it is reviewed again when main moved meanwhile; gone past only by ready
        # cards (claim(): fit), only when the fit changed its change, and its tests run again only where the cards that
        # landed touch its test files (sharedtests()).
        # land() reads the same mark under the lock, so a card passed after this reading does not land: it comes back here.
        # A card that tested in a batch is tested again after it.
        if jq -e '.passed == true' "$wt.claim" >/dev/null 2>&1; then
          t=${#mates[@]}; unmate; old=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
          redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
          [ $rc != 1 ] || return
          [ $rc != 3 ] || break 3 # a batch landed it
          [ $rc != 4 ] || continue 2
          [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; continue 3; }
          [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$old" ] && [ "$t" = 0 ] || continue 2
        fi
        if [ -n "$last" ]; then
          # The earlier loop's last NO-GO is filed here, after the checks above read this card's own review: alone after a
          # GO, its findings before this review's after a NO-GO.
          [ -n "$merged" ] || [ -z "$earlier" ] || { { if [ "$res" = GO ]; then printf '%s\n' "$earlier"; else grep -Ev "$NOTFINDING" <<<"$earlier"; cat "$wt.review"; fi; } > "$wt.review.new" \
            && mv -f "$wt.review.new" "$wt.review"; } || { block "$c" "$n" "$wt" "the engine could not put back the last review of the earlier loop, so it could not file the findings of that review"; return; }
          merged=1
          if [ -n "$isfu" ]; then
            dec=$(leftovers "$wt.review"); left='{"leftover":true,"followups":[]}'
            [ -n "$dec" ] || { block "$c" "$n" "$wt" "the last review said NO-GO and named no finding to file"; return; }
          else
            began "$c" "$n" file
            ups=$(followups "$c" "$issue" "$wt.review") || { block "$c" "$n" "$wt" "$ups"; return; }
            # Its filed line says why the loop whose findings it files ended: after a GO on a port, the earlier loop's.
            fe=$ended; [ "$res" != GO ] || [ -z "$earlyend" ] || fe=$earlyend
            left="{\"leftover\":true,\"followups\":$ups}"; record "$c" "$n" filed ok "$(jq -c --argjson u "$ups" '. + {followups: $u}' <<<"${fe:-"{}"}")"
          fi
        fi
        # A case that joined during its last test run stages its links before it lands (redbrief()).
        began "$c" "$n" land; redbrief "$c" "$n" "$br"
        reading fresh >/dev/null 2>&1 # the after reading of the landed line, asked for outside the lock
        # waitSec: the seconds it waited on other cards (settle()) and for main to change (mainwait()), for the drift
        # watch (bench/drift.sh).
        extra=$(jq -c --argjson w "$((waitsec + mainsec))" '. + {waitSec: $w}' <<<"${left:-"{}"}") || extra=$left
        [ -z "$yesfrom" ] || extra=$(jq -c --argjson f "$yesfrom" '. + {yesFrom: $f}' <<<"${extra:-"{}"}")
        # rollout: its rollout actions, as its ready file holds them too (above).
        [ "$ro" = '[]' ] || extra=$(jq -c --argjson r "$ro" '. + {rollout: $r}' <<<"${extra:-"{}"}")
        if [ ${#mates[@]} != 0 ]; then mapfile -d '' t5 < <(fives "$c" "$n" "$wt" "$cmsg" "$extra"); else t5=("$c" "$n" "$wt" "$cmsg" "$extra"); fi
        # Landed: its declined findings are written; when they cannot be, the card ends blocked, its review kept.
        t=$(locked land "${t5[@]}") && { [ -z "$dec" ] || decline "$c" "$n" "$FUCAP" <<<"$dec" \
          || { block "$c" "$n" "$wt" "the card landed, but the engine could not write its leftover findings to the declined list. The findings are in the kept review"; return; }; break 3; }
        # A batch that did not land. Main moved again before it could: it stays a batch, and its run is found to stand
        # on main as it is now, or it is tested again there (rebatch()). Else its other cards wait on at their claims,
        # and the card is tested alone, then tries alone, in no batch (its batch's run judged it with them).
        if [ ${#mates[@]} != 0 ] && [ "$t" != "$STALE" ]; then
          unmate
          [[ $t == "landed as "* ]] || { echo "conveyor: card $c: its batch did not land, so it is tested alone: $t"; rm -f "$wt.ready"; continue 2; }
        fi
        [ "$t" = "$PASSED" ] || [ "$t" = "$STALE" ] || break 2
        # Passed, or main moved, while it went to land: its follow-ups are withdrawn (filed again when it comes back to
        # land). Main moved: it is fitted onto main as it is now and its checks run again there, its tests only when the
        # fitted change is not the one that passed.
        [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups"); ups=''; left=''; dec=''
        [ "$t" != "$STALE" ] || continue 2
      done
    done
    # The one rebuild: a card that got a GO, whose reviewed change does not apply to main as it is now.
    if [ -z "$rebased" ] && [ -z "$ups" ] && [ -z "$dec" ] && [ -z "$ported" ] && [[ $t == "rebase onto main conflicts: "* ]]; then
      # Its change outside documentation (*.md) as reviewed (docs), and as tested when its tests passed on it (docpass),
      # when the clash is in documentation alone (docsonly()).
      docs=$(cardpatch "$wt" ':(exclude)*.md'); docsonly "$wt.patch" "$docs" || docs=''; docpass=''; ! testedhere "$wt" || docpass=$docs
      rebased=1; caught=1; locked giveway "$c" "$wt"; why=$t; old=$(git -C "$wt" rev-parse HEAD 2>/dev/null); printf '%s\n' "$old" > "$wt.base"
      err=$(git -C "$wt" reset -q --hard "refs/heads/$BRANCH" 2>&1) \
        || { block "$c" "$n" "$wt" "$why [the engine could not reset the worktree to main for the rebuild:${err:0:300}]"; return; }
      began "$c" "$n" rebase
      redbrief "$c" "$n" "$br"; t=$(session "$wt" "$(rebaseprompt "$sprompt" "$wt" "$why" "$old")" rebase) || {
        # The reviewed change goes back into the worktree, in place of the half-made rebuild, so block keeps it.
        git -C "$wt" reset -q --hard "$old" 2>/dev/null && git -C "$wt" clean -fdq 2>/dev/null && git -C "$wt" apply --index "$wt.patch" 2>/dev/null \
          || t="${t%%$'\n'*} [the engine could not put the reviewed change back in the worktree. The kept patch is what the failed rebuild left]$([[ $t != *$'\n'* ]] || printf '\n%s' "${t#*$'\n'}")"
        block "$c" "$n" "$wt" "rebase: $t"; return; }
      checked "$c" "$n" "$wt" "$issue" "$sprompt" rebase "$(jq -c --arg r "$why" '. + {reason:$r}' <<<"$t")" || return
      # A clash in documentation alone (a README) and a rebuild that changed nothing outside it: the review and the test
      # pass stand (kept, docpass), and only the product checks run before it lands. A merge session: its files are
      # checked to parse before any test runs (parsecheck).
      parsecheck=1; git -C "$wt" add -A 2>/dev/null; if [ -n "$docs" ] && [ "$(cardpatch "$wt" ':(exclude)*.md')" = "$docs" ]; then kept=1; else docpass=''; fi
      continue
    fi
    # The port `retry` would start, with no owner action: a card whose review loop finished (its one rebuild done, or a
    # last review's follow-ups filed) and whose landing still conflicts. Its follow-ups are withdrawn; one session
    # brings the reviewed change (the patch land() wrote) onto main, a rebase step; one review of that port alone
    # follows, its own loop as on a retried card, then the tests and the landing, which files the loop's last NO-GO
    # again after a GO. Once a card, and never on a card that is itself the port of an earlier card's conflict: a
    # conflict after the port blocks for the owner.
    if [ -z "$ported" ] && [[ $t == "rebase onto main conflicts: "* ]] && [[ $was != "rebase onto main conflicts: "* ]] && [ -s "$wt.patch" ]; then
      ported=1; caught=1; pass=0; rounds=0; rm -rf "$wt.rounds"; rebased=''; tfix=''; locked giveway "$c" "$wt"; why=$t; fin=$res; kp=$wt.patch; old=$(git -C "$wt" rev-parse HEAD 2>/dev/null); printf '%s\n' "$old" > "$wt.base"
      finend=$ended
      [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups"); ups=''; left=''; dec=''
      err=$(git -C "$wt" reset -q --hard "refs/heads/$BRANCH" 2>&1) \
        || { block "$c" "$n" "$wt" "$why [the engine could not reset the worktree to main for the port:${err:0:300}]"; return; }
      began "$c" "$n" rebase
      redbrief "$c" "$n" "$br"; t=$(session "$wt" "$(rebaseprompt "$sprompt" "$wt" "$why" "$old" port)" rebase) || {
        git -C "$wt" reset -q --hard "$old" 2>/dev/null && git -C "$wt" clean -fdq 2>/dev/null && git -C "$wt" apply --index "$wt.patch" 2>/dev/null \
          || t="${t%%$'\n'*} [the engine could not put the reviewed change back in the worktree. The kept patch is what the failed port left]$([[ $t != *$'\n'* ]] || printf '\n%s' "${t#*$'\n'}")"
        block "$c" "$n" "$wt" "rebase: $t"; return; }
      checked "$c" "$n" "$wt" "$issue" "$sprompt" rebase "$(jq -c --arg r "$why" '. + {reason:$r}' <<<"$t")" || return
      parsecheck=1; continue
    fi
    # A landing that fails after the follow-ups were filed withdraws them, unless main did get the commit.
    # shellcheck disable=SC2046 # the filed follow-ups' issue numbers, one word each
    case $t in "landed as "*) [ -z "$dec" ] || decline "$c" "$n" "$FUCAP" <<<"$dec" ;; *) [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups") ;; esac
    block "$c" "$n" "$wt" "$t"; return
  done
  clean "$wt"
}
