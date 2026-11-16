# SPDX-License-Identifier: Apache-2.0
# One card to its closing line (landed, closed or blocked). Every step checks its own exit and writes its own line when it
# ends; nothing waits between a line and the next step, which is how cards() names the step in progress.
# With a branch and its tip (land-branch) the card skips the build: that commit is merged into the worktree, staged
# and uncommitted, in place of a session's work. Issue 0 is a branch that names no issue: branchissue() stands in.
began() { rm -f "$CARDS/$1.firsttry" "$CARDS/$1.firsttry.new"; record "$1" "$2" start ok "{\"of\":\"$3\"}"; } # <card> <issue> <what begins>
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
card() { # <card> <issue> [<branch> <tip>]
  local c=$1 n=$2 br=${3:-} tip=${4:-} wt=$CARDS/$1 issue b t pass res vis unclear msg d err isfu='' dec='' why ups='' left='' rebased='' tfix='' last rc sec out merged away
  local prev from='' fromk='' was='' rev='' mode='' note='' old more base inh='' rv=$REVIEW yesfrom='' said extra
  local me cc seen=none sect='' nyes=0 heldto='' vmode='' ybase rules rhead sprompt hdr fin='' finrev earlier='' prv='' caught='' owe tsess='' cmsg ported='' kp='' mates=() t5=() trc ran apart='' back='' rf sf='' sk=''
  local vrule=on rounds=0 rep hard refix='' waitsec=0 behind='[]' cpid chead cseen own kept='' docpass='' docs parsecheck='' pfix='' # waitsec, behind: the seconds it has waited on other cards, and those cards (settle())
  local tmain='' # tmain: set once a failed test step has fitted the card onto a main that had moved (#582)
  local ins rr # ins, rr: the review's instructions, and fix when it reviews the fix alone (rereview())
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
        else fin=''; fi
      else
        mode=stale; note="the kept patch of card $from cannot be read: built from nothing"
      fi
      # Its commit trailers come with its patch (a card that lands from it has no session to write them again).
      [ "$mode" = stale ] || cp "$fromk/$from.trailers" "$wt.trailers" 2>/dev/null || cp "$CARDS/$from.trailers" "$wt.trailers" 2>/dev/null
    fi
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
    case $(keptway "$issue" "$d") in
      review) mode=session; note="resumed from the kept patch of card $from: the issue changed since its review: one session, then review" ;;
      build) git -C "$wt" reset -q --hard 2>/dev/null || { block "$c" "$n" "$wt" "worktree: the kept patch of card $from could not be taken out of the worktree"; return; }
        rm -f "$wt.rerun" "$wt.trailers"; mode=''; note="the issue's section of what customers or staff will see changed since the review of the kept patch of card $from: built from nothing" ;;
    esac
  fi
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
  # A card that takes up the kept patch of a loop that did not finish carries that loop's review rounds: the round
  # limit counts every review of the issue's retried cards, not just this card's. So does a kept patch reviewed again
  # with no build: a NO-GO there is fixed and goes round the loop. Not the port of a finished loop: its loop ended,
  # and this review checks something new.
  # Its fix rounds' findings and diffs come with them, so a finding that comes back is known as one (repeats()).
  if [ "$mode" = session ] || [ "$mode" = review ] || { [ "$mode" = port ] && [ -z "$fin" ]; }; then
    rounds=$(stdb ask issue retried "$n" 2>/dev/null | jq -s --argjson n "$n" 'map(select(.issue == $n and .step == "review")) | length' 2>/dev/null) || rounds=0
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
  # The sessions' and the reviewer's prompt (plan section 10, the reviewer gets the same text): the brief with
  # the rules after the header, before the issue.
  rhead="Conveyor card $c. $hdr"$'\n\n'
  sprompt=$rhead$'# Rules\n\n'"$rules"$'\n\n'"${b#"$rhead"}"
  d=$(jq -r '.body // ""' <<<"$issue" | sed -nE 's/^Follow-up depth: ([0-9]+)[[:space:]]*$/\1/p' | head -n 1)
  [ ${#d} -le 3 ] && d=$((10#${d:-0})) || d=''
  record "$c" "$n" brief ok "$([ -z "$d" ] && echo '{}' || echo "{\"depth\":$d}")"
  if [ -z "$br" ] && [ "$mode" != land ] && [ "$mode" != review ]; then
    more=''
    [ "$mode" != session ] || more=$'\n\n# This card resumes blocked card '"$from"$'\nThat card\'s change is already in this worktree, staged: its kept patch, applied to main as it stands. The card was blocked: '"${was:0:600}"$'\nStart from that change, not from nothing: finish what the issue asks, fix the findings carried over above, and leave alone what is already right.'
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
    began "$c" "$n" build
    redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt$more") || { block "$c" "$n" "$wt" "build: $t"; return; }
    checked "$c" "$n" "$wt" "$issue" "$sprompt" build "$t" || return
    # A bug card (the pack's type label): the tests it adds or changes must fail on main's code without the fix
    # (bugproof(); a change that selects no test of its own is proved by the test files its issue's Done-when names,
    # and goes on unchecked when it names none). When none does, or it adds none, it goes back to its build session once, told why; when the check
    # still does not hold after it, the card is blocked with that reason and no review. The review is shown the
    # check's result. A bug card that speeds up one test file (speedfile()) is checked by speedproof() instead, and one
    # that optimizes one (speedfile() with OPTIMIZE) by optproof(): when its file is not faster, or does not pass, the
    # card is blocked with that reason and no review.
    if ! jq -e --arg t "$TYPE" 'any(.labels[]?; .name == $t)' <<<"$issue" >/dev/null; then :
    elif sf=$(speedfile "$issue"); then
      speedproof "$c" "$wt" "$issue" "$sf" || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    elif sf=$(speedfile "$issue" "$OPTIMIZE"); then
      sk=$OPTREVIEW; optproof "$c" "$wt" "$issue" "$sf" || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
    else
      # A run on main that gave no result for a test file, twice (bugproof() exit 2), is blocked with that reason: a
      # build session cannot repair the runner.
      bugproof "$c" "$wt" "$issue"; trc=$?
      [ $trc != 2 ] || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
      if [ $trc != 0 ]; then
        began "$c" "$n" build
        redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt$more"$'\n\n'"$BUGBUILD"$'\n'"$(<"$wt.unfixed")") || { block "$c" "$n" "$wt" "build: $t"; return; }
        checked "$c" "$n" "$wt" "$issue" "$sprompt" build "$(jq -c --arg r "$UNFIXED" '. + {reason: $r}' <<<"$t")" || return
        bugproof "$c" "$wt" "$issue"; trc=$?
        [ $trc != 2 ] || { block "$c" "$n" "$wt" "build: $(<"$wt.unfixed")"; return; }
        [ $trc = 0 ] || { block "$c" "$n" "$wt" "build: $UNFIXED"$'\n'"$(<"$wt.unfixed")"; return; }
      fi
    fi
  fi
  msg=$(jq -r --arg c "$c" --arg t "$TYPE" --arg p "$AREA" '(.labels | map(.name)) as $l | "\(if $l | index($t) then "fix" else "feat" end)(\($l | map(select(startswith($p)) | ltrimstr($p)) | .[0] // "product")): \(.title) (#\(.number))\n\nCloses #\(.number)\nConveyor card \($c)"' <<<"$issue")
  # A branch that names no issue lands under its own first commit's subject, which names no issue to close.
  [ "$n" != 0 ] || [ -z "$br" ] || msg=$(jq -r --arg c "$c" --arg b "$br" '"\(.title)\n\nConveyor card \($c), branch \($b)"' <<<"$issue")
  prv=$'\n\n'"$PORTREVIEW"$'\n'"The difference is the file $wt.port."; kp=$fromk/$from.patch
  # A NO-GO is fixed and reviewed again; a NO-GO on a last review (review MAX_REVIEWS, counting the rounds a retried
  # card carries, or the one review after a landing conflict or after a test fix, or one that repeats a finding after
  # its fix with every finding P2 or P3) lands with follow-ups. A GO card whose landing conflicts goes round once
  # more: rebase, review. A finished loop whose landing still conflicts is ported once, as `retry` would port it.
  # Whatever the review, the changed tests pass here before anything is filed or landed.
  while pass=$((${pass:-0} + 1)); do
    redbrief "$c" "$n" "$br"
    git -C "$wt" add -A && ! git -C "$wt" diff --cached --quiet || { nochange "$c" "$n" "$wt" "$sprompt"; return; }
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
      began "$c" "$n" review
      # The review sees the card's commit trailers beside the diff, and the D<n> lines of the last checked reply.
      t="the engine could not read the commit trailers of the card"; more=$(trailerview "$wt") \
        && { [ ! -s "$wt.donewhen" ] || more+=$'\n\n'"$DONEWHENREVIEW"$'\n'"$(<"$wt.donewhen")"; } || { block "$c" "$n" "$wt" "review $pass: $t"; return; }
      [ ! -s "$wt.unfixed" ] || more+=$'\n\n'"$(if [ -n "$sk" ]; then echo "$sk"; elif [ -n "$sf" ]; then echo "$SPEEDREVIEW"; else echo "$BUGREVIEW"; fi)"$'\n'"$(<"$wt.unfixed")"
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
      record "$c" "$n" review "$res" "$(grep -Ev "$UNRECORDED" "$wt.review" | jq -cRs --arg res "$res" --argjson t "$t" --arg v "$vis" --argjson k "$(counts "$wt.review")" --arg p "$cpid" --arg m "$chead" --arg s "$cseen" 'sub("\n+$"; "") as $r | $t + {reason:$r,visible:$v,counts:$k,patch:$p,main:$m,seen:$s} + (if $res == "NO-GO" then {tail: $r} else {} end)')"
      [ "$res" != none ] || { block "$c" "$n" "$wt" "review $pass ended without one clear verdict$unclear"; return; }
    fi
    # A GO on the review of a port lands with the earlier loop's outcome: after its last NO-GO, that review's
    # findings are filed again, whatever the reviews after a test fix say. A NO-GO on it is fixed and goes round the
    # loop as any card's.
    last=''; [ "$fin" != NO-GO ] || [ "$res" != GO ] || earlier=$finrev; fin=''
    # A NO-GO that repeats a finding a fix round was told to fix (repeats()) spends no more rounds on it: when every
    # finding of the review is P2 or P3 this is the last review; when a repeated one is P0 or P1 the card blocks.
    rep=''; [ "$res" != NO-GO ] || rep=$(repeats "$wt")
    hard=$(jq -rs 'map(select(.level == "P0" or .level == "P1")) | first // empty | "\(.line[:300]) did not hold after \(.rounds) round\(if .rounds == 1 then "" else "s" end)"' <<<"$rep")
    [ -z "$hard" ] || { block "$c" "$n" "$wt" "the fix for $hard"; return; }
    if [ "$res" = GO ] && [ -z "$earlier" ]; then mode=''
    elif [ "$res" = GO ] || [ $((pass + rounds)) -ge "$MAX_REVIEWS" ] || [ -n "$rebased" ] || [ -n "$tfix" ] || [ "$mode" = land ] \
      || { [ -n "$rep" ] && [ "$(counts "$wt.review" | jq '.P0 + .P1')" = 0 ]; }; then
      # A card whose issue is itself a follow-up (the pack's follow-up label, or its body's depth line) files none:
      # its findings are declined.
      mode=''; last=1; isfu=''; ! jq -e --arg fu "$FOLLOWUP" '(.labels // [] | any(.name == $fu)) or (.body // "" | test("(^|\n)Follow-up depth: 0*[1-9][0-9]*[ \t\r]*(\n|$)"))' <<<"$issue" >/dev/null || isfu=1
    else
      began "$c" "$n" fix
      old=$(git -C "$wt" write-tree); more=''; [ -z "$rep" ] || more=$'\n\n'"$(again "$rep")"
      # The fix is told the accepted findings only: a finding the judge declined (a DECLINED line), or a P3 listed only
      # (a MINOR line, minor()), is not its to fix.
      redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt"$'\n\n'"$FIX"$'\n'"$(grep -Ev '^(DECLINED|MINOR):' "$wt.review")$more" fix) || { block "$c" "$n" "$wt" "fix: $t"; return; }
      checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$t" || return
      # This fix round's findings and the diff it made, for the review after it (repeats(), rereview()).
      mkdir -p "$wt.rounds" && git -C "$wt" add -A && git -C "$wt" diff "$old" "$(git -C "$wt" write-tree)" > "$wt.rounds/$((pass + rounds)).diff" \
        && findings "$wt.review" | jq -c --argjson r "$((pass + rounds))" '. + {round: $r}' >> "$wt.rounds/findings.jsonl" && refix=$((pass + rounds))
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
    yesfrom=''
    if [ -n "$heldto" ] && git -C "$wt" diff --cached --no-renames --name-only | productpaths; then
      case $vis in
        matches) echo "conveyor: card $c: what it shows matches the change $OWNER approved before the build" ;;
        "differs: "*) printf '%s\n' "$nyes" > "$wt.approvals"; jq -c '{body}' <<<"$issue" > "$wt.body"; block "$c" "$n" "$wt" "${YES}it differs from the change approved before the build: ${vis#differs: }" post; return ;;
        *) printf '%s\n' "$nyes" > "$wt.approvals"; jq -c '{body}' <<<"$issue" > "$wt.body"; block "$c" "$n" "$wt" "${YES}the review did not say whether it matches the change approved before the build" post; return ;;
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
      [ -n "$yesfrom" ] || { [ "$seen" != nothing ] || printf '%s\n' "$nyes" > "$wt.approvals"; jq -c '{body}' <<<"$issue" > "$wt.body"; block "$c" "$n" "$wt" "$YES${vis#yes: }$more" post; return; }
      echo "conveyor: card $c: its visible change is part of the change $OWNER approved in #$yesfrom: the yes is inherited"
    fi
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
    # only in documentation files, settle() and the rebuild marking it tested again). Accepted limit (the owner,
    # 2026-11-13): a passed test is not repeated when main moves, its change merged three-way or not, so changes that
    # passed apart can fail together on main.
    # Batches: after a GO it is ready to land once its own checks and tests pass (tested()), and a batch may take it
    # while it waits (gather()); one with follow-ups to file lands on its own. Holding its files on main as it is now,
    # its tests passed, it takes the ready cards that share them, and one run judges them all (batch()). Tests that
    # passed while it waited on what its worktree still holds are not run again (testedhere()). A card that files a
    # last NO-GO's follow-ups keeps its pass there too, marked alone: no batch takes it or is taken by it.
    rm -f "$wt.ready"; jq -cn --argjson i "$n" --arg m "$cmsg" --argjson y "${yesfrom:-null}" --argjson a "$([ -n "$last" ] && echo true || echo false)" \
      '{issue: $i, msg: $m, extra: (if $y then {yesFrom: $y} else {} end)} + (if $a then {alone: true} else {} end)' > "$wt.ready"
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
        # output are its own.
        rc=$trc; trc=''; rm -f "$wt.ready"
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
        [ -z "$away" ] || away=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)
        sec=$SECONDS; rc=0; ran=''; own=''; apart=''; TEST_BATCH=''; TEST_REFUSED=''
        # A test file its own run found over the time budget (slowtests()) is a note on its test line (slow), never a
        # finding: the card goes on with the pass. Only a test rule files an issue about it (testrulespass(), after the
        # test line is recorded).
        testedhere "$wt" || { ran=1; own=1; tests "$wt"; rc=$?; [ $rc != 0 ] || { slowtests "$wt" || rm -f "$wt.slow"; }; }
        [ $rc != 0 ] || [ -z "$own" ] || tested "$wt"
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
      if [ $rc != 0 ]; then
        out=$(testfails "$wt.test" "$rc")
        # What still did not pass runs on main first (verdicts()): each failure's verdict goes on the test line.
        t=$(verdicts "$c" "$wt" "${out:-null}") || t='{"verdicts":[]}'
        record "$c" "$n" test fail "$(tail -n 60 "$wt.test" 2>/dev/null | tr -d '\000' | jq -cRs --argjson x "$(testrec "$wt" "$rc" "$sec")" --argjson f "${out:-null}" --arg rc "$rc" --argjson r "$(firstrun "$wt")" --argjson v "$t" \
          'sub("\n+$"; "") as $t | $x + {
             reason:("exit " + $rc + (if $f.timeout then ": timed out after \($f.timeout.sec)s" + (if $f.timeout.file then " in \($f.timeout.file)" else "" end) else "" end))}
           + (if $f then {failures:($f | del(.passed, .okcases, .passcases))} else {} end) + (if $t == "" then {} else {tail:$t} end) + $r + $v')"
        testrulespass > /dev/null
        # Main is red: every failure the run again left fails on main too. The card waits in its test step, holding no
        # files (no fix session, no block) until main changes; then it is fitted onto main and tested again, as a card
        # whose main moved during its tests is. It is not put back on its old commit (#582): caught is cleared, so a
        # change that no longer applies there is brought onto main by a session, even after the landing's rebuild.
        if jq -e '[.verdicts[] | select(.verdict != "flaky")] | length > 0 and all(.verdict == "main")' <<<"$t" >/dev/null; then
          echo "conveyor: card $c: every case it still fails fails on main too: it waits for main to change"
          rm -f "$wt.ready"; locked giveway "$c" "$wt"; began "$c" "$n" test
          mainwait "$wt" "$(jq -r .mainRun.sha <<<"$t")" "$(jq -r '[.verdicts[] | select(.verdict == "main") | .case] | join(", ")' <<<"$t")"
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
        if [ -z "$tmain" ] && [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" ]; then
          echo "conveyor: card $c: main moved since its commit: its change goes onto main as it is now, and what failed runs again there"
          tmain=1; rm -f "$wt.ready"; unmate; away=''; caught=''
          redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
          [ $rc != 1 ] || return
          [ $rc != 3 ] || break 2 # a batch landed it
          [ $rc != 4 ] || continue
          [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; continue 2; }
          continue
        fi
        tmain=''
        [ -z "$tfix" ] || { block "$c" "$n" "$wt" "the changed tests failed again after their one fix round (exit $rc); nothing landed."$'\n'"$(tail -n 60 "$wt.test" 2>/dev/null | tr -d '\000')"; return; }
        tfix=1; locked giveway "$c" "$wt" fixing; began "$c" "$n" fix
        redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt"$'\n\n# The changed tests fail (exit '"$rc"$'): fix that and nothing else. The end of the test output:\n'"$(tail -n 200 "$wt.test" 2>/dev/null | tr -d '\000')" fix) \
          || { block "$c" "$n" "$wt" "fix: $t"; return; }
        checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$t" || return
        continue 2
      fi
      # Not run again when they passed on what its worktree still holds (that run has its own line): this line says it
      # reused that pass.
      # A batch that ran no case (batch(): TEST_BATCH) says so in selected: no case ran, and how many passes it kept.
      if [ -n "$ran" ]; then record "$c" "$n" test pass "$(jq -cn --argjson x "$(testrec "$wt" 0 "$sec")" --argjson r "$(firstrun "$wt" pass)" --argjson b "${TEST_BATCH:-null}" \
        --argjson s "$([ -z "$own" ] && echo '{}' || slowrec "$wt")" '$x + $r + $s | if $b then .selected += $b else . end')"
      else record "$c" "$n" test pass "$(jq -cn --argjson s "$sec" '{sec:$s,usage:{input:0,write:0,write1h:0,read:0,output:0},reused:true}')"; fi
      # The test rules read the line just recorded (lib/testrules.sh): with their switch off, they file nothing.
      [ -z "$ran" ] || testrulespass > /dev/null
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
      while :; do
        # An ordered card went past this one since its claim (it holds its files only from its landing step, so that is
        # where it is passed): it claims again, waits for that card, and is reviewed again when main moved meanwhile.
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
            left="{\"leftover\":true,\"followups\":$ups}"; record "$c" "$n" filed ok "{\"followups\":$ups}"
          fi
        fi
        # A case that joined during its last test run stages its links before it lands (redbrief()).
        began "$c" "$n" land; redbrief "$c" "$n" "$br"
        reading fresh >/dev/null 2>&1 # the after reading of the landed line, asked for outside the lock
        extra=$left; [ -z "$yesfrom" ] || extra=$(jq -c --argjson f "$yesfrom" '. + {yesFrom: $f}' <<<"${left:-"{}"}")
        if [ ${#mates[@]} != 0 ]; then mapfile -d '' t5 < <(fives "$c" "$n" "$wt" "$cmsg" "$extra"); else t5=("$c" "$n" "$wt" "$cmsg" "$extra"); fi
        # Landed: its declined findings are written; when they cannot be, the card ends blocked, its review kept.
        t=$(locked land "${t5[@]}") && { [ -z "$dec" ] || decline "$c" "$n" "follow-up of a follow-up" <<<"$dec" \
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
      redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt"$'\n\n'"$REBASE"$'\n\n## The conflict message\n'"$why"$'\n\n## The card\'s patch\nThe file '"$wt.patch"$', made against commit '"$old"$'.' rebase) || {
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
      [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups"); ups=''; left=''; dec=''
      err=$(git -C "$wt" reset -q --hard "refs/heads/$BRANCH" 2>&1) \
        || { block "$c" "$n" "$wt" "$why [the engine could not reset the worktree to main for the port:${err:0:300}]"; return; }
      began "$c" "$n" rebase
      redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt"$'\n\n'"$REBASE"$'\nOne review of this port alone follows: change nothing else.\n\n## The conflict message\n'"$why"$'\n\n## The card\'s patch\nThe file '"$wt.patch"$', made against commit '"$old"$'.' rebase) || {
        git -C "$wt" reset -q --hard "$old" 2>/dev/null && git -C "$wt" clean -fdq 2>/dev/null && git -C "$wt" apply --index "$wt.patch" 2>/dev/null \
          || t="${t%%$'\n'*} [the engine could not put the reviewed change back in the worktree. The kept patch is what the failed port left]$([[ $t != *$'\n'* ]] || printf '\n%s' "${t#*$'\n'}")"
        block "$c" "$n" "$wt" "rebase: $t"; return; }
      checked "$c" "$n" "$wt" "$issue" "$sprompt" rebase "$(jq -c --arg r "$why" '. + {reason:$r}' <<<"$t")" || return
      parsecheck=1; continue
    fi
    # A landing that fails after the follow-ups were filed withdraws them, unless main did get the commit.
    case $t in "landed as "*) [ -z "$dec" ] || decline "$c" "$n" "follow-up of a follow-up" <<<"$dec" ;; *) [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups") ;; esac
    block "$c" "$n" "$wt" "$t"; return
  done
  clean "$wt"
}
