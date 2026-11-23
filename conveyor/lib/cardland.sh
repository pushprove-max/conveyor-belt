# SPDX-License-Identifier: Apache-2.0
# card()'s steps (lib/card.sh) from a review that lets the card land: the gates before it lands (cardready()), its
# checks, tests and landing (cardlanding(), with cardtest(), cardfailed() and cardland()), and the one rebuild or port
# of a change whose landing conflicts (landconflict()). Each reads and sets card()'s locals (bash's dynamic scope) and
# says in its go what card() does next.
# These steps declare no variable of their own: each one they read or set is card()'s, or a global, which card() and
# its steps in lib/card.sh set and read too.
# shellcheck disable=SC2154,SC2034
# The gates after a review that lets the card land: the owner's yes, the trailers, the rollout actions and the commit
# message, then its ready file. go: '' (on to land) or next (a trailer session changed the change: review it again).
cardready() {
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
    pb=$fromk/$from.body; [ -n "$from" ] && [ -e "$pb" ] || pb=$CARDS/$from.body
    # The places of the diff are widened at least as far as in the hash the owner approved (lintpolicy()).
    ph=''; [ -z "$from" ] || ph=$(jq -r '.policy // "" | split(" ")[1] // ""' "$pb" 2>/dev/null) || ph=''
    { packget lint pf && pf=$(lintpolicy "$wt" "$(git -C "$wt" rev-parse HEAD)" "$pf" "$ph"); } || { block "$c" "$n" "$wt" "lint: the engine could not read the lint policy files that the change changes, so nothing landed"; return; }
    ph=${pf%%$'\n'*}; pf=$(tail -n +2 <<<"$pf" | jq -Rrs 'split("\n") | map(select(. != "")) | join(", ")')
    [ -z "$pf" ] || [ -z "$from" ] || ! lintyes "$issue" "$pb" "$ph" || { echo "conveyor: card $c: its lint policy change is the one $OWNER approved"; pf=''; }
  fi
  # The visible-change gate after the review (visgate()): a stop blocks the card, its reason in err.
  visgate || { block "$c" "$n" "$wt" "$err" post; return; }
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
    git -C "$wt" add -A && [ "$(git -C "$wt" write-tree)" = "$old" ] && [ "$(trailers "$wt")" = "$cmsg" ] || { go=next; return; }
  fi
  [ -z "$owe" ] || { block "$c" "$n" "$wt" "a commit trailer the pack requires is missing after its one fix session; nothing landed: $(jq -rs 'map("\(.token) (it adds \(.paths | join(", ")))") | join("; ")' <<<"$owe")"; return; }
  # The trailers the commit carries are these, read here where they were reviewed and checked: nothing after (the
  # tests) changes them.
  cmsg=$(trailers "$wt") || { block "$c" "$n" "$wt" "the engine could not read the commit trailers of the card, so nothing landed"; return; }
  # Its rollout actions (rollouts()): those of its newest review that decides them, its last review's file (the kept
  # review, for a card that lands from a kept patch with no review line of its own) when it names any, else its own
  # newest review line with a rollout, else the retried cards' (pro). A review that names some replaces the earlier
  # ones (R234), and so does a GO of the whole change that names none (its line's rollout is []); a NO-GO or a review
  # of the fix alone that names none keeps them. Then its Rollout trailers, each once and in the order named (ROLLOUTONCE). All go on its landed line (rollout) and, in that order, at the end of the commit message as
  # Rollout lines in place of its Rollout trailers, so the push carries each one. They are no findings: nothing here
  # holds the card, but a check that cannot be made: with the pack's privacy.mode public, a terms file the host file names that cannot be read blocks it (privwords()). With the pack's privacy.mode public, the Rollout lines have each word the privacy check flags
  # masked (privmask(), lib/issues.sh), as cardsubject() masks a body: they are reviewer text, and the push checks no
  # commit message. Bug: an address a review named in its ROLLOUT line was pushed in the commit message.
  rtr=$(rollouts <(printf '%s\n' "$cmsg") Rollout) && rrev=$(rollouts "$wt.review" ROLLOUT) \
    && ro=$(stdb ask card "$c" | jq -cs --argjson p "$pro" --argjson k "$rrev" --argjson t "$rtr" '[(($k | select(length > 0)) // ([.[] | select(.step == "review" and has("rollout")) | .rollout] | last) // $p)[], $t[]] | '"$ROLLOUTONCE") \
    && rmsg=$(jq -r '.[] | "Rollout: \(.action) | \(.fails) | \(.place)"' <<<"$ro") \
    || { block "$c" "$n" "$wt" "the engine could not read the rollout actions of the card, so nothing landed"; return; }
  { [ -z "$rmsg" ] || { packget privacy.mode t && { [ "$t" != public ] || rmsg=$(privmask "$rmsg"); }; }; } \
    || { block "$c" "$n" "$wt" "the engine could not read the pack's privacy mode, or make the privacy check of the card's rollout actions, so nothing landed"; return; }
  cmsg=$(grep -Ev "^Rollout: $ROLLOUT" <<<"$cmsg" || :); cmsg=$cmsg${cmsg:+${rmsg:+$'\n'}}$rmsg
  # A main-red fix card names its cases and main's commit, as its entry holds them now (a case added during its
  # build or a review too). A Tests page card of issue 0 (testcardissue(), lib/testaction.sh) keeps its subject
  # (cardsubject()), with its body, which closes no issue.
  [ "$n" != 0 ] || [ -n "$br" ] || testcardissue "$c" > /dev/null || msg=$(redmsg "$c" "$issue")
  # The card's commit trailers go into the message after its Closes line, before its card line, the last one: a body
  # with a line of its own that starts "Conveyor card " does not take them.
  cmsg=$(jq -rn --arg m "$msg" --arg t "$cmsg" 'if $t == "" then $m else $m | sub("\nConveyor card (?<c>[^\n]*)\\z"; "\n\($t)\nConveyor card \(.c)") end')
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
  # its tests passed, it takes the landing turn and the ready cards that share them or wait on that turn, and one run
  # judges them all (batch()); while another card has the turn, it waits for the next batch (turnq()). Tests that
  # passed while it waited on what its worktree still holds are not run again (testedhere()). A card that files a
  # last NO-GO's follow-ups, or of findings the judge found outside its change (<worktree>.outside), keeps its pass
  # there too, marked alone: no batch takes it or is taken by it, as a batch would land it with none of them filed.
  # Its extra's waitSec is what it has waited so far; settle() keeps it up to date while it waits (a batch lands it).
  rm -f "$wt.ready"; jq -cn --argjson i "$n" --arg m "$cmsg" --argjson y "${yesfrom:-null}" --argjson a "$({ [ -n "$last" ] || [ -s "$wt.outside" ]; } && echo true || echo false)" --argjson w "$((waitsec + mainsec))" --argjson ro "$ro" \
    '{issue: $i, msg: $m, extra: ({waitSec: $w} + (if $y then {yesFrom: $y} else {} end) + if $ro != [] then {rollout: $ro} else {} end)} + (if $a then {alone: true} else {} end)' > "$wt.ready"
  go=''
}
# The checks, tests and landing of a card ready to land, run again until it lands or goes back. go: next (the next
# pass of the review loop), landed or out (its landing did not land: landconflict()). Its own steps say
# again (this loop again) or '' (on).
cardlanding() {
  # Back from the landing rebuild with its change outside documentation the one that passed its tests (docpass): it
  # lands on that run, with only its product checks run again.
  [ -z "$docpass" ] || { [ "$docpass" != "$(cardpatch "$wt" ':(exclude)*.md')" ] || tested "$wt"; docpass=''; }
  away=''; jq -e '.away == true' "$wt.claim" >/dev/null 2>&1 && away=1
  trc=''
  if [ -z "$away" ]; then
    redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
    [ $rc != 1 ] || return
    [ $rc != 3 ] || { go=landed; return; } # a batch landed it
    [ $rc = 0 ] || [ $rc = 4 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; go=next; return; }
  fi
  merged=''
  while :; do
    if [ -n "$trc" ]; then
      # Its own tests failed while it waited, or it broke the tests of the batch that took it: that run's exit and
      # output are its own. No run of its own tests is on this pass (own: testlist.sh carriedrec(), slowrec()).
      rc=$trc; trc=''; own=''; rm -f "$wt.ready"
    else
      go=end; cardtest; sx=$?
      case $go in '') go=end ;; again) go=end; continue ;; end) return $sx ;; *) return ;; esac
    fi
    # Its run did not run (no test.fileCommand), or was stopped, as it would have run more than the tests of its
    # change (tests(): <worktree>.stop): no run on main and no fix session, as a session cannot change the pack.
    # The card is blocked with that reason, which names the setting that fixes it.
    [ ! -s "$wt.stop" ] || { block "$c" "$n" "$wt" "test: $(<"$wt.stop")"; return; }
    voidrun "$wt" "$rc" > /dev/null || voids=0 # a run with a result, a pass too, starts the count of runs with none again
    if [ $rc != 0 ]; then
      go=end; cardfailed; sx=$?
      case $go in '') go=end ;; again) go=end; continue ;; end) return $sx ;; *) return ;; esac
    fi
    # Not run again when they passed on what its worktree still holds (that run has its own line): this line says it
    # reused that pass.
    # A batch's run (batch(): TEST_BATCH) says in selected how many passes it kept, and no case ran when it ran none.
    # A card the repair lane passed (mainred.sh repairlane()): its line says so, with the clean run of its changed tests.
    if [ -n "$repaired" ]; then record "$c" "$n" test pass "$(jq -cn --slurpfile x <(testrec "$wt" 0 "$sec") --arg r "$repaired" '$x[0] + {reason: $r}')"
    elif [ -n "$ran" ]; then record "$c" "$n" test pass "$(jq -cn --slurpfile x <(testrec "$wt" 0 "$sec") --slurpfile r <(firstrun "$wt" pass) --argjson b "${TEST_BATCH:-null}" \
      --slurpfile s <([ -z "$own" ] && echo '{}' || slowrec "$wt") '$x[0] + $r[0] + $s[0] | if $b then .selected += $b else . end')"
    else record "$c" "$n" test pass "$(jq -cn --argjson s "$sec" '{sec:$s,usage:{input:0,write:0,write1h:0,read:0,output:0},reused:true}')"; fi
    # The test rules read the line just recorded (lib/testrules.sh): with their switch off, they file nothing.
    [ -z "$ran" ] || testrulespass > /dev/null
    # A Make it run card (#189) holds only when its test step ran its file and the file passed.
    [ -z "$mk" ] || t=$(ranproof "$wt" "$mk") || { BLOCKCLASS='proof check' block "$c" "$n" "$wt" "test: $t"; return; }
    # A card that gave way claims its files now; a card whose change is not on main as it is now (main moved while it
    # was away or during its tests) is fitted onto it, and its checks run again there, holding its files (its tests
    # too when the fitted change is not the one that passed: testedhere()).
    # A change that no longer applies there is put back as it was (caught) and meets the conflict at landing; one
    # apart from its batch (batch()), which landed, is brought onto main by one session, as a waiting card is.
    # A card queued for the next batch (cardtest(): another card had the landing turn) waits on that card at its claim
    # (turnq(), lib/claim.sh), as a waiting card does, and after the wait goes round again: a batch took it, or it has
    # the turn and makes the next batch.
    if [ -n "$away$queued" ] || [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" ]; then
      [ -n "$away" ] && [ "$away" = "$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" ] || [ -n "$apart$queued" ] || caught=1
      t=${#mates[@]}; [ -z "$queued" ] || t=queued; queued=''; unmate; old=$(git -C "$wt" rev-parse HEAD 2>/dev/null); away=''
      redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
      [ $rc != 1 ] || return
      [ $rc != 3 ] || { go=landed; return; } # a batch landed it
      [ $rc != 4 ] || continue
      [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; go=next; return; }
      [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$old" ] && [ "$t" = 0 ] || continue
    fi
    # Apart from its batch for its lint (lintleave(), lib/lint.sh): it goes back to its landing gate, also when main
    # did not move (its batch run on main as it moved, rebatch(), lands no other card), so it never lands on that finding.
    [ "$apart" != lint ] || continue
    go=end; cardland; sx=$?
    case $go in again) go=end; continue ;; end) return $sx ;; *) return ;; esac
  done
}
# Before any check or test: the parse check after a merge onto main, the landing gate, the product checks and the
# project's checks; then its changed tests, alone or in a batch. go: '' (the run ended, its exit in rc), again (the
# failed product check is its run's result) or next.
cardtest() {
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
      go=next; return
    fi
  fi
  # The landing gate (lintgate(), lib/lint.sh), before any check or test: a fix of lint findings goes round to a
  # review, a last review (lfix), and back here, where a finding left on the change that fix left blocks.
  lintgate "$c" "$n" "$wt" "$issue" "$sprompt" "$br" land; case $? in 1) return ;; 2) kept=''; docpass=''; go=next; return ;; esac
  # The product checks, on every pass that would land: a failure blocks the card, never a finding to fix. Not on
  # the pass that runs again on main as it is now what failed in a red run (tmain): there a failing check is that
  # red run failing again, as a check that fails on a batch's change is a red run (batch()), and goes to the one
  # fix round; on the passes after the fix it blocks again.
  if ! out=$(checks "$wt"); then
    [ -n "$tmain" ] || { block "$c" "$n" "$wt" "a product check failed; nothing landed."$'\n'"$out"; return; }
    norun "$wt" "a product check failed on the change of $c on main as it is now:"$'\n'"$out"; sec=0; trc=1; go=again; return
  fi
  # The changed tests, before the follow-ups are filed: a card that fails them twice files nothing.
  began "$c" "$n" test
  # The project's checks first (donewhen.sh treecheck(): kept for the tree the last session's check ran on, so not run again
  # there). When they fail, the step ends before any test file runs, its line holding one failure that names
  # the check and its output. That is not its tests failing: the one test-fix round (tfix) is kept and the card
  # is not blocked for it; one fix session is told the output, and donewhen.sh checked() runs the checks again on its change.
  # The line is marked checks: no test ran, so the card's first run of its tests is still its first (testlist.sh testedbefore()).
  out=$(treecheck "$wt"); t=$(testroute checks $?)
  [ "$t" != block ] || { block "$c" "$n" "$wt" "the engine could not run the project's checks: $out"; return; }
  if [ "$t" = checkfix ]; then
    packget test.checkCommand t || t=test.checkCommand
    record "$c" "$n" test fail "$(jq -cn --arg k "$t" --arg o "$out" '{reason: "the project'"'"'s checks failed (test.checkCommand: \($k)); no test file ran",
      checks: true, failures: {of: 0, files: [{file: $k, cases: []}], timeout: null}, tail: ($o | .[-4000:])}')"
    rm -f "$wt.ready"; locked giveway "$c" "$wt" fixing; began "$c" "$n" fix
    redbrief "$c" "$n" "$br"; t=$(session "$wt" "$sprompt"$'\n\n'"$CHECKFIX"$'\n'"$out" fix) || { block "$c" "$n" "$wt" "fix: $t"; return; }
    checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$(jq -c '. + {reason: "the project'"'"'s checks failed (test.checkCommand)"}' <<<"$t")" || return
    go=next; return
  fi
  [ -z "$away" ] || away=$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)
  sec=$SECONDS; rc=0; ran=''; own=''; apart=''; queued=''; repaired=''; TEST_BATCH=''; TEST_REFUSED=''; rm -f "$wt.stop"
  # The times its own run took go on its test line (testlist.sh slowtests()); only a test rule files an issue about a test
  # file (testrulespass(), after the test line is recorded).
  testedhere "$wt" || own=1
  # Its shared files run again once for the change it holds (<worktree>.sharedran: that change's patch-id, once
  # that run passed): on a busy main, each run again let another card land on them, and the card never landed
  # (#447). A failure of the two changes together that this lets onto main is caught there (main red).
  # That run's list holds the shared files (t; SHAREDRUN, testrun.sh listcmd()). Past that run, it has the landing turn once this step passed (turntake(), below).
  shared=''; sb=$(sed -n 's/^base\t//p' "$wt.rerun" 2>/dev/null)
  if [ -z "$own" ] && t=$(sharedtests "$wt" "$sb"); then
    if [ "$(cat "$wt.sharedran" 2>/dev/null)" = "$(cardpatch "$wt")" ]; then
      shared=2; echo "conveyor: card $c: cards landed since its shared test files ran again touch them too ($(paste -sd ' ' <<<"$t")); they ran again once, so it lands with no second run again. Cards landed since: $(landedsince "$wt" "$sb")"
    else own=1; shared=1; unshare "$wt" "$t"; echo "conveyor: card $c: cards landed since its tests ran touch its test files too, so they run again on main as it is now: $(paste -sd ' ' <<<"$t")"; fi
  fi
  [ -z "$own" ] || { ran=1; SHAREDRUN=${shared:+$t} tests "$wt"; rc=$?; [ $rc != 0 ] || slowtests "$wt" || :; }
  [ $rc != 0 ] || [ -z "$own" ] || tested "$wt"
  [ $rc != 0 ] || [ "$shared" != 1 ] || cardpatch "$wt" > "$wt.sharedran" || rm -f "$wt.sharedran"
  if [ $rc = 0 ] && [ -z "$away" ] && [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$(git rev-parse "refs/heads/$BRANCH" 2>/dev/null)" ]; then
    # Another card has the landing turn (gather() 2): it is queued, waiting on that card for the next batch (cardlanding()).
    out=$(locked gather "$c" "$wt" "$me"); t=$?; [ $t = 0 ] || out=''; [ $t != 2 ] || queued=1
    # A full run its own run refused (tests()) stays on the line its batch's run writes.
    rf=$TEST_REFUSED; [ -z "$out" ] || { t=$ran; ran=1; batch "$c" "$wt" $out; rc=$?; [ -z "$apart" ] || ran=$t; }; TEST_REFUSED=${TEST_REFUSED:-$rf}
  fi
  # Main moved during its batch's run: the batch lands on that run when it still stands there (rebatch()). A
  # product check that fails on its change there is a red run: the batch is run again there, as batch() does one.
  # That run (4: for the shared files, its passes dropped; its list holds its sharers' shared files, sharedown as SHAREDRUN, testrun.sh listcmd()) is their run again for each card that shares one and passed in it, the card failing or not (markshared(); bugs: a third run; a mate that passed went back to its own test step unmarked when the card failed; a red run's, 3, can reuse every pass).
  back=''
  if [ ${#mates[@]} != 0 ]; then
    rebatch "$c" "$wt"; t=$?
    [ $t != 2 ] || { block "$c" "$n" "$wt" "the engine fitted the batch of the card onto main, but it could not put the change of the card back in its worktree. Nothing landed. The change is in the patch $wt.bpatch"; return; }
    [ $t != 3 ] && [ $t != 4 ] || { ran=1; SHAREDRUN=$([ $t != 4 ] || printf '%s\n' "${sharedown[@]}") batch "$c" "$wt" "${mates[@]}"; rc=$?; [ $t != 4 ] || markshared "$c" "$wt" $rc; }
  fi
  sec=$((SECONDS - sec))
  # It broke its batch, or its patch did not apply on the cards before it there: the cards that passed land without it,
  # its landing turn ended (landmates(), lib/claim.sh).
  if { [ $rc != 0 ] || [ -n "$apart" ]; } && [ ${#mates[@]} != 0 ]; then
    mapfile -d '' t5 < <(fives "$c" "$n" "$wt" "$cmsg" '' skip)
    t=$(locked landmates "$c" "${t5[@]}") || { echo "conveyor: card $c: the cards of its batch that passed did not land: $t"; unmate; }
    mates=()
  fi
  # A run that failed ends its landing turn: no ready card stays queued on it (turnq()) through its fix or its wait for
  # main or the machine, where the card that fixes main would wait on it too.
  [ $rc = 0 ] || locked turnfree "$c"
  [ -z "$back" ] || { git -C "$wt" reset -q --hard "$back" 2>/dev/null && git -C "$wt" apply --index "$wt.bpatch" 2>/dev/null; } \
    || { block "$c" "$n" "$wt" "the batch of the card landed, but the engine could not put the change of the card back in its worktree. The change is in the patch $wt.bpatch"; return; }
  rm -f "$wt.lent" # its worktree holds its own change again (batch())
  # Its run again of the shared files passed (now, or before for the change it holds), and its batch's run too when a
  # batch took it: it takes the landing turn (turntake(), lib/claim.sh), so no other card lands on main before it.
  # Not before its batch's run: the cards of a batch it broke land without it (above).
  [ $rc != 0 ] || [ -n "$apart" ] || [ -z "$shared" ] || locked turntake "$c" "$me" || :
  go=''
}
# card()'s wait for the machine hold or the repair lane (mainred.sh holdwait()), its seconds added to card()'s mainsec, as
# mainwaited() (card.sh) adds a wait for main: the landed line's waitSec counts it, so the drift watch does not count it as work.
holdwaited() { # <worktree> [lane]
  local hw=$SECONDS; holdwait "$@"; mainsec=$((mainsec + SECONDS - hw)); }
# A test run that failed (rc). go: again (the test step again: no result, a wait for main or the machine, or main
# moved), next (its one fix round, or a fit onto main that went back) or landed; '' when the repair lane passed it.
cardfailed() {
  # The worktree lacks a dependency folder main has (depsmissing(), lib/push.sh): the failure is the project's
  # setup, not the change, and no run on main or fix session mends it. The card is blocked saying so, with no
  # test failures.
  t=$(depsmissing "$wt"); [ -z "$t" ] || { block "$c" "$n" "$wt" "$(depsreason "$t")"; return; }
  # A run with no result (voidrun(): killed by a signal, as by the service stopping or restarting, also under a
  # loop that adopted the card) proves nothing: nothing of it runs on main, goes to the main-red record, a wait
  # for main or a fix session. Its test line says so, and the test step runs again; the third such run in a row
  # blocks the card (a run with a result, a pass too, starts the count again: above).
  # Its own run's files kept as passed and not run, and those it ran some cases of (testlist.sh carriedrec()): the
  # step that ran them whole is an earlier one.
  cr='{}'; [ -z "$own" ] || cr=$(carriedrec "$wt")
  if t=$(voidrun "$wt" "$rc"); then
    voids=$((voids + 1))
    record "$c" "$n" test fail "$(tail -n 60 "$wt.test" 2>/dev/null | tr -d '\000' | jq -cRs --slurpfile x <(testrec "$wt" "$rc" "$sec") --slurpfile o <(printf '%s' "$cr") --arg r "no result: $t" \
      '$x[0] as $x | $o[0] as $o | sub("\n+$"; "") as $t | $x + $o + {reason: $r} + (if $t == "" then {} else {tail: $t} end)')"
    [ "$voids" -lt 3 ] || { block "$c" "$n" "$wt" "the changed tests gave no result 3 times in a row ($t); nothing landed."; return; }
    echo "conveyor: card $c: its test run gave no result ($t): the test step runs again"
    go=again; return
  fi
  out=$(testfails "$wt.test" "$rc")
  # What still did not pass runs on main first (mainred.sh verdicts()): each failure's verdict goes on the test line.
  t=$(verdicts "$c" "$wt" "${out:-null}") || t='{"verdicts":[]}'
  # Where the failed run goes (testroute()). The machine is at fault (mainred.sh verdicts(): machine, issue 221), with no
  # failure the card's: its test line is `held`, not `fail` (the card's test step is not counted as failed), and it
  # waits for the machine hold (below).
  route=$(testroute verdicts "$t")
  record "$c" "$n" test "$([ "$route" = machine ] && echo held || echo fail)" "$(failline "$wt" "$rc" "$sec" "${out:-null}" "$t" "$cr")"
  testrulespass > /dev/null
  # A failure that is the card's, or one whose verdicts could not be read (the empty list above), taken as the card's:
  # whether main moved, and the fix round, are read after the test rules ran.
  [ -n "$route" ] || route=$(testroute "$wt")
  # Main is red: every failure the run again left fails on main too. The card waits in its test step, holding no
  # files (no fix session, no block) until main changes; then it is fitted onto main and tested again, as a card
  # whose main moved during its tests is. It is not put back on its old commit (#582): caught is cleared, so a
  # change that no longer applies there is brought onto main by a session, even after the landing's rebuild.
  # The machine is at fault (mainred.sh verdicts(): machine, issue 221), with no failure the card's: no fix session, no
  # block and no wait for main. The card waits, holding no files, until the machine hold goes (mainred.sh holdwait()), then
  # is fitted onto main as it is then and tested again, as after a wait for main. Before it waits, it is judged
  # in the repair lane (mainred.sh repairlane(), issue 222): a card the lane passes goes on as a card whose tests passed;
  # one that finds the lane held by another card waits until it is free, and is then tested and judged again.
  held=''
  if [ "$route" = machine ]; then
    lane=0; repairlane "$c" "$wt" || lane=$?
    if [ $lane = 0 ]; then
      echo "conveyor: card $c: a case it still fails is the machine's, and the card repairs it: $REPAIRED"
      repaired=$REPAIRED; rc=0; tmain=''
    else
      if [ $lane = 2 ]; then echo "conveyor: card $c: a case it still fails is the machine's: it waits for the repair lane, which another card holds"
      else echo "conveyor: card $c: a case it still fails is the machine's, not main's, and the repair lane did not pass it ($REPAIRED): it waits until the machine passes its controls again"; fi
      rm -f "$wt.ready"; locked giveway "$c" "$wt"; began "$c" "$n" test
      holdwaited "$wt" "$([ $lane != 2 ] || echo lane)"; held=1
    fi
  elif [ "$route" = main ]; then
    echo "conveyor: card $c: every case it still fails fails on main too: it waits for main to change"
    rm -f "$wt.ready"; locked giveway "$c" "$wt"; began "$c" "$n" test
    mapfile -t mwon < <(jq -r '.mainRun.sha, (.verdicts[] | select(.verdict == "main") | .case)' <<<"$t")
    mainwaited "$wt" "${mwon[@]}"; held=1
  fi
  if [ -n "$held" ]; then
    unmate; away=''; caught=''
    redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
    [ $rc != 1 ] || return
    [ $rc != 3 ] || { go=landed; return; } # a batch landed it
    [ $rc != 4 ] || { go=again; return; }
    [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; go=next; return; }
    go=again; return
  fi
  # Main moved since the card's commit (#582: it may have fixed what failed there, which the card's run did not
  # hold): the change is first fitted onto main as it is now and what failed runs again there, before any fix
  # round. Once before each fix round, so a card whose own change fails does not follow a busy main for ever.
  # caught is cleared, as after a wait on a red main above: a change that no longer applies on main is brought there
  # by a session, not put back on its old commit (settle()), where what failed would only run again as it did.
  # Fitted there (settle() claims its files again), it gives way for that run, as for a fix round (fixing): a card
  # stacked on it (stackto()) is fitted onto main alone and lands, not waiting through this run (claim()).
  if [ "$route" = moved ]; then
    echo "conveyor: card $c: main moved since its commit: its change goes onto main as it is now, and what failed runs again there"
    tmain=1; rm -f "$wt.ready"; unmate; away=''; caught=''
    redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
    [ $rc != 1 ] || return
    [ $rc != 3 ] || { go=landed; return; } # a batch landed it
    [ $rc != 4 ] || { go=again; return; }
    [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; go=next; return; }
    # Away now, it claims its files again (settle()) once that run passes, before it lands, main moved or not.
    locked giveway "$c" "$wt" fixing; ! jq -e '.away == true' "$wt.claim" >/dev/null 2>&1 || away=1; go=again; return
  fi
  if [ "$route" = block ] || [ "$route" = fix ]; then
    tmain=''
    [ "$route" != block ] || { block "$c" "$n" "$wt" "the changed tests failed again after their one fix round (exit $rc); nothing landed."$'\n'"$(tail -n 60 "$wt.test" 2>/dev/null | tr -d '\000')"; return; }
    tfix=1; locked giveway "$c" "$wt" fixing; began "$c" "$n" fix
    # On the testFix seat (seat(): the builder's unless the control record sets testFix); the card's second fix session of any kind runs one effort level up.
    redbrief "$c" "$n" "$br"; t=$(session "$wt" "$(testfixprompt "$sprompt" "$wt" "$rc" "$out")" fix testFix "$([ "$fixed" = 0 ] || echo up)") \
      || { block "$c" "$n" "$wt" "fix: $t"; return; }
    fixed=$((fixed + 1))
    checked "$c" "$n" "$wt" "$issue" "$sprompt" fix "$t" || return
    go=next; return
  fi
  go=''
}
# A card of the loop (LOOPCARD, cardrun(), lib/run.sh) whose landing did not land, before it works again (its lint,
# checks, tests or a session): its land step was off the cap, so the loop may have filled the cap with new cards
# meanwhile. It sleeps, <worktree>.capheld and <worktree>.idle standing, until a turn of the loop finds room for it
# under the cap and takes both marks away (capfree()). It wakes the loop (wakeloop(), lib/control.sh), so with room
# already there that turn comes at once. Its start line marked waitFor: cap says so, and stop (halt(), lib/run.sh)
# and `shut` (shutopen(), lib/run.sh) end a card that waits here: no landing of it is under way. Its landing turn
# (turnon(), lib/claim.sh) ends first: a card that waits for that turn at its land step counts against the cap, so
# the two would wait on each other for ever. A card that no loop runs (land-branch, `lane fast land`) has no turn to
# let it go: it goes on at once. Nor does a main-red fix card (issue 0, no branch: card()'s br; redfix(), lib/run.sh)
# wait: the cards that fill the cap may wait for main (mainwait(), lib/mainred.sh), so for its fix, and the loop picks
# no other fix card while it is open. As it waits, its live record says so and is brought up to date (as in
# releasewait(), lib/push.sh), so `health` and the loop's stuck check (turnended(), lib/run.sh) see a card that waits.
caphold() { # <card> <issue> <worktree> <the step it waits to work in> [why it waits, after "card <card>"]
  local at
  [ -n "${LOOPCARD:-}" ] && { [ "$2" != 0 ] || [ -n "${br:-}" ]; } || { rm -f "$3.capheld"; return 0; }
  : > "$3.capheld" || return 0
  locked turnfree "$1"
  record "$1" "$2" start ok "$(jq -cn --arg s "$4" '{of: $s, waitFor: "cap"}')"
  echo "conveyor: card $1 ${5:-did not land}; it waits for room under the card cap before it works again"; wakeloop
  at=$(date -u +%FT%TZ)
  while [ -e "$3.capheld" ]; do
    jq -cn --arg s "$4" --arg at "$at" '{step: $s, at: $at, last: (now | todate), turns: 0, files: {run: 0, of: null}, tests: null,
      action: "waiting for room under the card cap"}' > "$3.live.tmp" 2>/dev/null && mv -f "$3.live.tmp" "$3.live"
    : > "$3.idle"; sleep "$LIVE"
  done
  rm -f "$3.live" "$3.idle"
}
# A card that slept out a wait at its claim (settle(), lib/claim.sh), before it works again: while it slept, capfree()
# left it out of its count and may have let a held card go in its slot. Then its <worktree>.capheld holds "owed", and
# it waits for room as a held card does (caphold()). Only the card itself takes that mark away, here.
capowed() { # <card> <issue> <worktree> <the step it waits to work in>
  [ -s "$3.capheld" ] || return 0
  caphold "$1" "$2" "$3" "$4" "waited on another card"
}
# In the loop's turn (turncount(), lib/run.sh): lets go of the held cards (caphold()) while the cards that work and
# count against the cap are fewer than the cap, and takes away their .idle as it does, so a card let go counts from then.
# Only a card that waits on another card at its claim (settle(), lib/claim.sh: <worktree>.idle, with its live record
# naming that card and what it waited, or <worktree>.batch the batch card that took it) is not counted here, so a card
# that waits on a held card's files does not keep it held for ever. A card that waits at its land step for the landing
# turn (landwait(), lib/claim.sh) also names a card, but it counts: it goes on with no look at the cap. Before a held
# card is let go in a turn that left such cards out, each of them gets "owed" in its <worktree>.capheld, so it waits for
# room when its wait ends (capowed()); one whose .idle is gone once the mark is written works already, so its mark goes
# and it counts. A card marked "owed" in an earlier turn that has no .idle counts, and its mark stays: its wait may have
# ended before it read the mark. Every other waiting card counts: it works again with no look at the cap (one that
# waits for its seat's CLI, cliwake(), lib/run.sh; for main or the machine hold, lib/mainred.sh).
capfree() { # <the loop's own cards in progress, "<pid> <card>" one a line> <the cap>
  local p c s n=0 held=() lent=()
  while read -r p c; do
    [ -n "$c" ] && kill -0 "$p" 2>/dev/null && ! batchlanded "$c" || continue
    if [ -s "$CARDS/$c.capheld" ]; then [ ! -e "$CARDS/$c.idle" ] || continue
    elif [ -e "$CARDS/$c.capheld" ]; then held+=("$c"); continue
    elif [ -e "$CARDS/$c.idle" ] && { [ -e "$CARDS/$c.batch" ] || jq -e '(.waits.on | type) == "string" and (.waited | type) == "object"' "$CARDS/$c.live" >/dev/null 2>&1; }; then lent+=("$c"); continue; fi
    read -r s 2>/dev/null < "$CARDS/$c.nocap" && [ "$s" = land ] && continue
    n=$((n + 1))
  done <<<"$1"
  [ ${#held[@]} != 0 ] && [ "$n" -lt "$2" ] || return 0
  for c in "${lent[@]}"; do
    [ -e "$CARDS/$c.capheld" ] || echo owed > "$CARDS/$c.capheld"
    [ ! -e "$CARDS/$c.idle" ] || continue
    [ ! -s "$CARDS/$c.capheld" ] || rm -f "$CARDS/$c.capheld"; n=$((n + 1))
  done
  for c in "${held[@]}"; do [ "$n" -lt "$2" ] || break; rm -f "$CARDS/$c.capheld" "$CARDS/$c.idle"; n=$((n + 1)); done
}
# The land step, its tests passed: files the follow-ups of a last review and lands, run again while a release run,
# an ordered or ready card or main moving holds it. go: landed, again (cardlanding() again), next or out.
cardland() {
  local capdue='' # a landing of this call did not land: the card counts against the cap again and waits for room before it works (caphold())
  while :; do
    # While a release run is under way (relhold(), lib/push.sh) it waits here, at its land step, and lands once the
    # run has ended: on main as the release left it, where it is fitted again (STALE, below).
    releasewait "$c" "$n" "$wt"
    # While another card has the landing turn (turnon(), lib/claim.sh) it waits here too, and lands after that card,
    # fitted onto main as that card left it (STALE, below). land() reads the turn under the lock (TURNHELD).
    landwait "$c" "$n" "$wt"
    # An ordered or a ready card went past this one since its claim (it holds its files only from its landing step,
    # so that is where it is passed): it claims again, waits for that card, and is fitted onto main as that card
    # left it. Gone past by an ordered card, it is reviewed again when main moved meanwhile; gone past only by ready
    # cards (claim(): fit), only when the fit changed its change, and its tests run again only where the cards that
    # landed touch its test files (sharedtests()).
    # land() reads the same mark under the lock, so a card passed after this reading does not land: it comes back here.
    # A card that tested in a batch is tested again after it.
    if jq -e '.passed == true' "$wt.claim" >/dev/null 2>&1; then
      # It is fitted again or runs its checks below: after a landing that did not land, it waits for room first.
      [ -z "$capdue" ] || caphold "$c" "$n" "$wt" land; capdue=''
      t=${#mates[@]}; unmate; old=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
      redbrief "$c" "$n" "$br"; settle "$c" "$n" "$wt" "$sprompt" land "$issue"; rc=$?
      [ $rc != 1 ] || return
      [ $rc != 3 ] || { go=landed; return; } # a batch landed it
      [ $rc != 4 ] || { go=again; return; }
      [ $rc = 0 ] || { rm -f "$wt.ready"; locked giveway "$c" "$wt"; go=next; return; }
      [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$old" ] && [ "$t" = 0 ] || { go=again; return; }
    fi
    # A last NO-GO's findings, and the findings the judge found outside the card's change (<worktree>.outside,
    # judged()) after a GO too, are filed here as follow-ups (followups()).
    if [ -n "$last" ] || [ -s "$wt.outside" ]; then
      # The earlier loop's last NO-GO is filed here, after the checks above read this card's own review: alone after a
      # GO, its findings before this review's after a NO-GO.
      [ -z "$last" ] || [ -n "$merged" ] || [ -z "$earlier" ] || { { if [ "$res" = GO ]; then printf '%s\n' "$earlier"; else grep -Ev "$NOTFINDING" <<<"$earlier"; cat "$wt.review"; fi; } > "$wt.review.new" \
        && mv -f "$wt.review.new" "$wt.review"; } || { block "$c" "$n" "$wt" "the engine could not put back the last review of the earlier loop, so it could not file the findings of that review"; return; }
      [ -z "$last" ] || merged=1
      # After a GO, the depth cap is read here: a follow-up at the cap files none of them, as after a last NO-GO.
      [ -n "$last" ] || { isfu=1; [ "$(fudepth "$issue")" -lt "$MAX_DEPTH" ] 2>/dev/null && isfu=''; }
      if [ -n "$isfu" ]; then
        dec=$(tofile "$wt.review"); left='{"leftover":true,"followups":[]}'; [ -n "$last" ] || left='{"followups":[]}'
        [ -n "$dec" ] || { block "$c" "$n" "$wt" "$(nofiling "$wt.review")"; return; }
      else
        began "$c" "$n" file
        ups=$(followups "$c" "$issue" "$wt.review") || { block "$c" "$n" "$wt" "$ups"; return; }
        # Its filed line says why the loop whose findings it files ended: after a GO on a port, the earlier loop's.
        fe=$ended; [ "$res" != GO ] || [ -z "$earlyend" ] || fe=$earlyend
        # The landed line's leftover says it landed on a NO-GO; outside: the outside findings filed, {finding, issue}.
        left="{\"leftover\":true,\"followups\":$ups}"; [ -n "$last" ] || left="{\"followups\":$ups}"
        record "$c" "$n" filed ok "$(jq -c --argjson u "$ups" --slurpfile o <(cat "$wt.outfiled" 2>/dev/null) '. + {followups: $u} + (if $o == [] then {} else {outside: $o} end)' <<<"${fe:-"{}"}")"
      fi
    fi
    # A case that joined during its last test run stages its links before it lands (redbrief()).
    began "$c" "$n" land; redbrief "$c" "$n" "$br"
    reading fresh >/dev/null 2>&1 # the after reading of the landed line, asked for outside the lock
    extra=$(landextra "$left" "$yesfrom" "$ro")
    if [ ${#mates[@]} != 0 ]; then mapfile -d '' t5 < <(fives "$c" "$n" "$wt" "$cmsg" "$extra"); else t5=("$c" "$n" "$wt" "$cmsg" "$extra"); fi
    # Landed: its declined findings are written; when they cannot be, the card ends blocked, its review kept.
    t=$(locked land "${t5[@]}") && { [ -z "$dec" ] || decline "$c" "$n" "$FUCAP" <<<"$dec" \
      || { block "$c" "$n" "$wt" "the card landed, but the engine could not write its leftover findings to the declined list. The findings are in the kept review"; return; }; go=landed; return; }
    # Not landed (main moved, a release run or a landing turn, a conflict): it lands no more now, so the loop counts it against
    # the cap again (capmark(), lib/run.sh) while it waits, rebuilds or runs its lint and checks again, until its next step begins.
    # Cards the loop started while it landed stay; before it works again (its lint, checks, tests or a session) it
    # waits for room under the cap among them (caphold()), so a landing that failed never puts more cards to work than the cap.
    rm -f "$wt.nocap"
    # A batch that did not land. Main moved again before it could: it stays a batch, and its run is found to stand
    # on main as it is now, or it is tested again there (rebatch()). Else its other cards wait on at their claims,
    # and the card is tested alone, then tries alone, in no batch (its batch's run judged it with them).
    if [ ${#mates[@]} != 0 ] && [ "$t" != "$STALE" ] && [ "$t" != "$RELHELD" ] && [ "$t" != "$TURNHELD" ]; then
      unmate
      [[ $t == "landed as "* ]] || { echo "conveyor: card $c: its batch did not land, so it is tested alone: $t"; rm -f "$wt.ready"
        # Its follow-ups are withdrawn first, as below: stop ends a card that waits for room (caphold()).
        # shellcheck disable=SC2046 # the filed follow-ups' issue numbers, one word each
        [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups"); ups=''; left=''; dec=''
        caphold "$c" "$n" "$wt" land; go=again; return; }
    fi
    [ "$t" = "$PASSED" ] || [ "$t" = "$STALE" ] || [ "$t" = "$RELHELD" ] || [ "$t" = "$TURNHELD" ] || { go=out; return; }
    # Passed, or main moved, or a release run began, or another card took the landing turn, while it went to land: its
    # follow-ups are withdrawn (filed again when it comes back to land). A release run or a landing turn: it waits for
    # its end above, a batch kept. Main moved: it is fitted
    # onto main as it is now and its checks run again there, its tests only when the fitted change is not the one that passed.
    # shellcheck disable=SC2046 # the filed follow-ups' issue numbers, one word each
    [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups"); ups=''; left=''; dec=''
    # Main moved: it is fitted again and runs its checks, so it waits for room first. Else (a card went past it, a
    # release run or another card's landing turn) it waits for room once it is found passed (above), which it may be
    # only after its wait for the run or the turn.
    [ "$t" != "$STALE" ] || { caphold "$c" "$n" "$wt" land; go=again; return; }
    capdue=1
  done
}
# A landing that did not land (its reason in t): the one rebuild of a GO card whose change no longer applies to main,
# or else the one port of a finished loop; else the card blocks. go: next (review the rebuilt or ported change).
landconflict() {
  # The one rebuild: a card that got a GO (no last NO-GO), whose reviewed change does not apply to main as it is now.
  # The follow-ups it filed for the judge's outside findings are withdrawn: filed again when it comes back to land.
  if [ -z "$rebased" ] && [ -z "${last:-}" ] && [ -z "$ported" ] && [[ $t == "rebase onto main conflicts: "* ]]; then
    # shellcheck disable=SC2046 # the filed follow-ups' issue numbers, one word each
    [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups"); ups=''; left=''; dec=''
    # Its change outside documentation (*.md) as reviewed (docs), and as tested when its tests passed on it (docpass),
    # when the clash is in documentation alone (docsonly()).
    docs=$(cardpatch "$wt" ':(exclude)*.md'); docsonly "$wt.patch" "$docs" || docs=''; docpass=''; ! testedhere "$wt" || docpass=$docs
    rebased=1; caught=1; locked giveway "$c" "$wt"; why=$t; old=$(git -C "$wt" rev-parse HEAD 2>/dev/null); printf '%s\n' "$old" > "$wt.base"
    # It waits for room before the reset, so the session starts on main as it is once the wait ends.
    caphold "$c" "$n" "$wt" rebase
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
    go=next; return
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
    # shellcheck disable=SC2046 # the filed follow-ups' issue numbers, one word each
    [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups"); ups=''; left=''; dec=''
    caphold "$c" "$n" "$wt" rebase # before the reset, as for the rebuild above
    err=$(git -C "$wt" reset -q --hard "refs/heads/$BRANCH" 2>&1) \
      || { block "$c" "$n" "$wt" "$why [the engine could not reset the worktree to main for the port:${err:0:300}]"; return; }
    began "$c" "$n" rebase
    redbrief "$c" "$n" "$br"; t=$(session "$wt" "$(rebaseprompt "$sprompt" "$wt" "$why" "$old" port)" rebase) || {
      git -C "$wt" reset -q --hard "$old" 2>/dev/null && git -C "$wt" clean -fdq 2>/dev/null && git -C "$wt" apply --index "$wt.patch" 2>/dev/null \
        || t="${t%%$'\n'*} [the engine could not put the reviewed change back in the worktree. The kept patch is what the failed port left]$([[ $t != *$'\n'* ]] || printf '\n%s' "${t#*$'\n'}")"
      block "$c" "$n" "$wt" "rebase: $t"; return; }
    # Its rebase line has port: a retry counts only the reviews after it (resumeplan(), lib/card.sh), as pass and rounds start again here.
    checked "$c" "$n" "$wt" "$issue" "$sprompt" rebase "$(jq -c --arg r "$why" '. + {reason:$r, port:true}' <<<"$t")" || return
    parsecheck=1; go=next; return
  fi
  # A landing that fails after the follow-ups were filed withdraws them, unless main did get the commit.
  # shellcheck disable=SC2046 # the filed follow-ups' issue numbers, one word each
  case $t in "landed as "*) [ -z "$dec" ] || decline "$c" "$n" "$FUCAP" <<<"$dec" ;; *) [ -z "$ups" ] || unfile "$n" "$wt.review" $(jq -r '.[]' <<<"$ups") ;; esac
  # A landing conflict keeps the issue body its review read (.body), so that the port of its kept patch is built from
  # nothing when the issue's section of what customers or staff will see changes later (resumeplan(), keptway()).
  # Bug: it kept none, and a port of the old change ran on a rewritten issue.
  [[ $t != "rebase onto main conflicts: "* ]] || [ -z "$issue" ] || jq -c '{body}' <<<"$issue" > "$wt.body" 2>/dev/null || rm -f "$wt.body"
  block "$c" "$n" "$wt" "$t"; return
}
