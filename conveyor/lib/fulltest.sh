# SPDX-License-Identifier: Apache-2.0
# The full test suite (README.md, The full test suite): the pack's test.full, run on main when the Board asks, never by
# the loop or a card. `conveyor.sh full-test` (the Board's "Run full test suite") runs it and pushes nothing;
# `full-test push` ("Push landed") runs it and, green, pushes the commit it tested; `full-test anyway <run id>
# [--by <who>]` ("Push anyway", beside a red result, after a confirm that names its failed cases) pushes the commit that
# red run tested with no new run, logged as the owner's push over a red suite. The id is that of the red run the confirm
# named: when the last line of the record is not that run (a later run ended since the Board showed it), nothing is
# pushed, so a push over a red suite is never one over cases the owner was not shown. A pack with no test.full has none
# of them (exit 2).
# One at a time per project: $FULLTEST.lock is held from the ask to the end of the run and its push; an ask while it is
# held is refused (exit 2) and says what runs and since when. The ask returns once the run has started: the run goes on
# in the background (its output in $FULLTEST.log), so the Board is not kept waiting for a whole suite.
# The run is of main as it is at the ask, in a worktree of that commit alone ($CARDS/fulltest/wt), on one of the
# machine's test slots, as the whole test on main is (tests()). Cards go on landing meanwhile; the push sends the commit
# the run tested, never a later one (push() given that commit: its checks and marks, under the card of the newest
# landing that commit holds and origin lacks). A push with no landed commit to send is refused at the ask.
# The run reuses the whole-suite results of $SUITES (suitereuse(), issue 44) as release-prep does: with a pass of every
# file on the commit itself (a release-prep's, or an earlier run's), no test runs and the run passes; with results on
# an ancestor, only the files that failed there, those the commits since change and those the changed-tests command
# selects for them run (the command is told the list by the file CONVEYOR_SUITE_FILES names), and the other files keep
# that run's ok; else the whole suite runs. Its results go to $SUITES (suitekeep()), for the next run of any of them.
# A red run pushes nothing. Each case that failed (testfails(): "<file>: <case>", the file alone for a file that failed
# naming no case or ran out of time) is run alone FULL_ALONE times on the same commit: the command is told, in its
# CONVEYOR_TEST_RERUN list (README.md, The test step), that every other file of the run passed and, of the case's
# file, to run that case alone. It is then judged as the nightly whole test judges a case:
# - it passed every run alone: flaky, an entry of the flaky-test record (flaky()), its source "full test <commit>".
# - it failed alone, and every run of it that failed timed out, was killed, or failed with words of the machine or the
#   network (FULL_OUTSIDE): outside the code, a line of the declined list (declined(), by code) with that reason.
# - else it is in the code: a fix card, an issue of the pack's second priority (P1) that names the case, its failure
#   line, its runs alone and the cause. When the commit tested holds landed commits origin lacks, the case is run alone
#   once more at the commit origin has ($CARDS/fulltest/base): failing there too, it was already failing before them;
#   passing there, the landed commit that plausibly caused it is the newest of them that changed the case's file, else
#   the newest of them. With none, it was already failing before them. The issue filed last for the same case, while
#   it is open, is reused (the same text as a comment), never a second; one GitHub says nothing of files nothing.
# A run that cannot start (its worktree, its test slots) tested nothing: its line says why (state error).
# $FULLTEST (fulltest.jsonl) keeps a line for each run as it ends and for each push anyway: time, id (12 hex digits of
# its own), kind (run or anyway),
# push (asked to push), sha (the commit run or pushed), state (passed, failed or error, with reason), exit, cases (a red
# run's: each {case, line, runs: each run alone, passed, failed, timeout or killed, verdict: flaky, fix or declined, why,
# issue, reused}; an anyway line's: those of the red run it pushed over), pushed ({ok, reason}; null: nothing was to be
# pushed), by (who pushed anyway) and reused (a run's: null for a whole suite, else {sha, time, ran, kept}: the run
# reused, the files rerun, none when nothing ran, and the passes kept). $FULLTEST.running holds {since, sha, how} while the lock is held, and, once a red
# run's failed cases are run alone, counts: the whole run's suiteprog(). Each run's files, with their results and
# times, also go to $SUITERUNS (suiterec(), lib/testrun.sh) for the Tests page.
FULLTEST=${STATE%/*}/fulltest.jsonl
FULL_ALONE=3
# How far a whole-suite run (this one's, or a release's: commands/release-prep.sh) in <worktree> is, from the cases its
# runner named as ended (cases/ok and cases/failed of its log folder, session.sh testdone()): {done, failed, cases: the
# names of the failed ones, of: the cases it selected, the sum of its `TESTRUN cases=N` lines, null with none; files:
# {done, of, failed}: the files its runner named as ended (`-- ok <file>`, `-- FAIL <file>`), the sum of its
# `TESTRUN files=N` lines (null with none) and the names of those that failed}. The
# lines are read from the logs it wrote (session.sh testlogs()), or from its output when it wrote none, so a runner
# that also prints its log's lines is counted once.
suiteprog() { # <worktree>
  local d=$1.testlog/cases ls logs=()
  mapfile -t logs < <(find "$1.testlog" -maxdepth 1 -type f 2>/dev/null)
  [ ${#logs[@]} -gt 0 ] || logs=("$1.test")
  ls=$(cat "${logs[@]}" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/^TESTRUN cases=[0-9]+/ { sub(/^TESTRUN cases=/, ""); n += $1; seen = 1 }
    /^TESTRUN files=[0-9]+/ { sub(/^TESTRUN files=/, ""); fn += $1; fseen = 1 }
    /^-- ok / { print "ok\t" substr($0, 7) } /^-- FAIL / { print "failed\t" substr($0, 9) }
    END { print "of\t" (seen ? n + 0 : "null"); print "fof\t" (fseen ? fn + 0 : "null") }')
  { find "$d/ok" -maxdepth 1 -type f 2>/dev/null | sed 's|.*/|ok\t|'; find "$d/failed" -maxdepth 1 -type f 2>/dev/null | sed 's|.*/|failed\t|'; } \
    | jq -Rsc --arg ls "$ls" '($ls | [split("\n")[] | select(. != "") | split("\t")]) as $l | ($l | map(select(.[0] == "of" or .[0] == "fof") | {(.[0]): (.[1] | fromjson)}) | add) as $n
      | [split("\n")[] | select(. != "") | split("\t")] | {done: length, of: $n.of, failed: map(select(.[0] == "failed")) | length, cases: [.[] | select(.[0] == "failed") | .[1]] | sort,
        files: ($l | map(select(.[0] == "ok" or .[0] == "failed")) | {done: (map(.[1]) | unique | length), of: $n.fof, failed: [.[] | select(.[0] == "failed") | .[1]] | unique})}'
}
# The whole-suite results of each commit (issues 43 and 44), shared by every whole-suite run: Run full test suite and
# Push landed (fullrun()), release-prep and release (relsuite(), commands/release-prep.sh). One line a commit, the
# newest last: {sha, time, by (the run that made it: full test, push landed, release-prep or release), files: {<file>:
# ok or fail}}, each test file of <sha> by its result, as of the run's `-- ok|FAIL <file>` lines; a run that reused one
# has that run's results of the files it did not run. Only a run that named a result for every file it selected (its
# `TESTRUN files=N` lines) is kept. The newest SUITES_KEEP commits are kept.
SUITES=${STATE%/*}/suites.jsonl
SUITES_KEEP=50
# The line of $SUITES on <commit>, else on its nearest ancestor (the fewest commits between), the newest of a tie: a
# later run on an older commit does not hide the result on <commit> or on a nearer one. Fails with none.
suitebase() { # <commit>
  local l s d best='' bd=''
  while IFS= read -r l; do
    s=$(jq -r .sha <<<"$l")
    git merge-base --is-ancestor "$s" "$1" 2>/dev/null && d=$(git rev-list --count "$s..$1" 2>/dev/null) || continue
    [ -n "$bd" ] && [ "$d" -ge "$bd" ] || { best=$l; bd=$d; }
  done < <(jq -cR 'fromjson? | objects | select((.sha | type) == "string" and (.files | type) == "object")' "$SUITES" 2>/dev/null | jq -cs 'reverse[]')
  [ -n "$best" ] && printf '%s\n' "$best"
}
# Whether the suite on <commit> reruns some files only (suitebase()'s line is on an ancestor of <commit>, or on it), and
# the commits since change neither the pack's test settings (test.*) nor a file the pack's test commands name (a word
# of test.full, test.command, test.changed or test.wholeCommands in the pack: .conveyor/test-full.sh, the engine's
# runner). Then <worktree> (a worktree of <commit>) gets <worktree>.files, the files to run: those that did not pass in
# that line, those the commits change or add, and those the changed-tests command (test.command, as a card's test step
# runs it) selects for those changes, which it lists to the file CONVEYOR_TEST_LIST names, in <worktree> with its HEAD
# at the line's commit. Prints the line. 1: the whole suite runs (no line, a test setting or command changed, or the
# command wrote no list); 2: <worktree> could not be put back on <commit>; 3: the line is a pass of every file on
# <commit> itself: nothing runs, and the pass counts.
suitereuse() { # <worktree> <commit>
  local wt=$1 sha=$2 l b pk=${PACK#"$MAIN"/} cmd ch=() f w=()
  l=$(suitebase "$sha") || return 1
  b=$(jq -r .sha <<<"$l")
  [ "$b" != "$sha" ] || ! jq -e '.files | length > 0 and all(.[]; . == "ok")' <<<"$l" > /dev/null || { printf '%s\n' "$l"; return 3; }
  [ "$(git show "$b:$pk" 2>/dev/null | jq -c .test 2>/dev/null)" = "$(git show "$sha:$pk" 2>/dev/null | jq -c .test 2>/dev/null)" ] || return 1
  mapfile -t ch < <(git diff --name-only --no-renames "$b" "$sha") || return 1
  while read -ra w; do
    for f in "${w[@]}"; do printf '%s\n' "${ch[@]}" | grep -qxF -- "${f#./}" && return 1; done
  done < <(jq -r '.test | [.full, .command, .changed, (.wholeCommands // [])[]] | .[] | strings' "$PACK" 2>/dev/null)
  packget test.command cmd && [ -n "$cmd" ] || return 1
  rm -f "$wt.sel"
  git -C "$wt" reset -q "$b" 2>/dev/null && (cd "$wt" && CONVEYOR_TEST_LIST=$wt.sel timeout 300 bash -c "$cmd" > "$wt.sel.out" 2>&1 < /dev/null 8>&-)
  git -C "$wt" reset -q "$sha" 2>/dev/null && [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ] || return 2
  [ -f "$wt.sel" ] || return 1
  { jq -r '.files | to_entries[] | select(.value != "ok") | .key' <<<"$l"; printf '%s\n' "${ch[@]}"; cat "$wt.sel"; } | grep . | sort -u > "$wt.files" || return 1
  printf '%s\n' "$l"
}
# The line of the suite run in <worktree> on <commit>, made by <by>, added to $SUITES in place of that commit's line,
# with the files of the line it reused (<reused line>, suitereuse()) that it did not run, and only the files <commit>
# holds. Prints, for the run's record, null for a whole suite, else {sha, time, ran, kept}: the reused line's commit and
# time, the files rerun and the passes kept. A run that named no result for a file it selected, or that failed (<exit>
# not 0) with no file failed, adds no line and fails.
suitekeep() { # <worktree> <commit> <exit> <by> [reused line]
  local logs=() r of f
  mapfile -t logs < <(testlogs "$1")
  r=$(cat "${logs[@]}" "$1.test" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | jq -cRn 'reduce (inputs | capture("^-- (?<r>ok|FAIL) (?<f>.+)$")) as $x ({};
    .[$x.f] |= (if . == "fail" or $x.r == "FAIL" then "fail" else "ok" end))') || return 1
  of=$(suiteprog "$1"); of=$(jq -r '.files.of // null' <<<"$of" 2>/dev/null) || return 1
  [ "$of" != null ] && [ "$(jq length <<<"$r")" -ge "$of" ] || return 1
  [ "$3" = 0 ] || jq -e 'any(.[]; . == "fail")' <<<"$r" > /dev/null || return 1
  jq -cn --arg s "$2" --arg t "$(clock)" --arg by "$4" --argjson r "$r" --argjson o "${5:-null}" --rawfile tr <(git ls-tree -r --name-only "$2") '
    ($tr | split("\n") | map({(.): true}) | add) as $has
    | (if $o == null then {} else $o.files | with_entries(select(.value == "ok" and $has[.key] and ($r[.key] | not))) end) as $k
    | {sha: $s, time: $t, by: $by, files: ($k + $r | with_entries(select($has[.key])))},
      (if $o == null then null else {sha: $o.sha, time: $o.time, ran: ($r | keys), kept: ($k | length)} end)' \
    | { IFS= read -r f && suiteadd "$f" && IFS= read -r f && printf '%s\n' "$f"; }
}
# <line> added to $SUITES in place of its commit's line, under $SUITES.lock: two runs may end at once.
suiteadd() { # <line>
  ( flock 9 && { jq -cR --arg s "$(jq -r .sha <<<"$1")" 'fromjson? | objects | select(.sha != $s)' "$SUITES" 2>/dev/null; printf '%s\n' "$1"; } \
      | tail -n "$SUITES_KEEP" > "$SUITES.new" && mv -f "$SUITES.new" "$SUITES" ) 9>>"$SUITES.lock"
}
FULL_OUTSIDE='ECONNREFUSED|ECONNRESET|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|Could not resolve host|Network is unreachable|Temporary failure in name resolution|Connection (refused|reset|timed out)|No space left on device|Disk quota exceeded|Cannot allocate memory|out of memory'
fulltest() { # [push | anyway <run id> [--by <who>]]
  local how=${1:-run} by=owner cmd lk sha o='' last=null id=${2:-}
  case $#:${1:-} in
    0: | 1:push | 2:anyway) ;;
    4:anyway) [ "$3" = --by ] && [[ $4 == *[![:space:]]* && $4 != *$'\n'* ]] || how=bad; by=$4 ;;
    *) how=bad ;;
  esac
  [ "$how" != anyway ] || [[ $id =~ ^[0-9a-f]{12}$ ]] || how=bad
  [ "$how" != bad ] || { echo "usage: conveyor.sh full-test [push | anyway <run id> [--by <who>]]" >&2; return 2; }
  packget test.full cmd || return 1
  [ -n "$cmd" ] || { echo "conveyor: the pack names no full test suite (test.full); nothing run" >&2; return 2; }
  mkdir -p "$CARDS/fulltest" && { exec {lk}>>"$FULLTEST.lock"; } 2>/dev/null || { echo "conveyor: the full test's lock could not be made; nothing run" >&2; return 1; }
  flock -n "$lk" || { echo "conveyor: a full test run is already running$(jq -r '" (\(.how), since \(.since), on \(.sha[0:12]))"' "$FULLTEST.running" 2>/dev/null); this one is not started" >&2; return 2; }
  if [ "$how" = anyway ]; then
    last=$(tail -n 1 "$FULLTEST" 2>/dev/null | jq -ce 'select(.kind == "run" and .state == "failed")' 2>/dev/null) \
      || { echo "conveyor: the last full test run is not a red one: there is nothing to push over; nothing pushed" >&2; return 2; }
    [ "$(jq -r '.id // ""' <<<"$last")" = "$id" ] \
      || { echo "conveyor: the red run $id is not the last full test run: a later one ended since; nothing pushed" >&2; return 2; }
    sha=$(jq -r .sha <<<"$last")
  else
    sha=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") || { echo "conveyor: main could not be read; nothing run" >&2; return 1; }
  fi
  [ "$how" = run ] || o=$(fullowed "$sha") || { echo "conveyor: no landed commit of ${sha:0:12} is unpushed; nothing pushed" >&2; return 2; }
  jq -cn --arg s "$sha" --arg h "$how" --arg t "$(clock)" '{since: $t, sha: $s, how: $h}' > "$FULLTEST.running" || return 1
  # The run holds the lock (lk) to its end. It is given no other descriptor of this process's: the Board's ssh ends
  # with this process, not with the run.
  ( trap '' HUP; exec {LOGFD}>&- && exec {LOGFD}>&2
    fullrun "$how" "$sha" "$cmd" "$o" "$by" "$last"; rm -f "$FULLTEST.running" ) > "$FULLTEST.log" 2>&1 < /dev/null 8>&- &
  exec {lk}>&-
  case $how in
    run) echo "conveyor: the full test suite is running on ${sha:0:12}; it pushes nothing" ;;
    push) echo "conveyor: the full test suite is running on ${sha:0:12}; green, that commit is pushed" ;;
    anyway) echo "conveyor: ${sha:0:12} is being pushed over its red suite, by $by" ;;
  esac
}
# `conveyor.sh push-now` (the Board's "Push now"): what landed and is not pushed, pushed as the loop pushes it while the
# rule "Push when a card lands" is on, with no full test run: push() of main through the project's pre-push hook, under
# the card of the newest landing origin lacks, a failure recorded as that card's push line (kind check or transport).
# Refused (exit 2), with the reason and nothing changed, when main holds no landed commit origin lacks, or while a full
# test run holds its lock (Run full test suite, Push landed or Push anyway). The ask returns once the push has started:
# it goes on in the background (its output in $PUSHNOW_LOG), so the Board is not kept waiting for the pre-push hook.
PUSHNOW_LOG=${STATE%/*}/pushnow.log
pushnow() {
  local lk sha o c n
  [ $# = 0 ] || { echo "usage: conveyor.sh push-now" >&2; return 2; }
  mkdir -p "$CARDS/fulltest" && { exec {lk}>>"$FULLTEST.lock"; } 2>/dev/null || { echo "conveyor: the full test's lock could not be made; nothing pushed" >&2; return 1; }
  flock -n "$lk" || { exec {lk}>&-; echo "conveyor: a full test run is under way$(jq -r '" (\(.how), since \(.since), on \(.sha[0:12]))"' "$FULLTEST.running" 2>/dev/null); nothing pushed" >&2; return 2; }
  exec {lk}>&-
  sha=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") || { echo "conveyor: main could not be read; nothing pushed" >&2; return 1; }
  o=$(fullowed "$sha") || { echo "conveyor: no landed commit of main (${sha:0:12}) is unpushed; nothing pushed" >&2; return 2; }
  read -r c n <<<"$o"
  # The push file names this job while it pushes (pushing()); it is cleared at the end only while it still does.
  ( trap '' HUP; exec {LOGFD}>&- && exec {LOGFD}>&2
    push "$c" "$n"; [ "$(jq -r '.pid' "$PUSHING" 2>/dev/null)" != "$BASHPID" ] || rm -f "$PUSHING" ) > "$PUSHNOW_LOG" 2>&1 < /dev/null 8>&- &
  echo "conveyor: main (${sha:0:12}) is being pushed through the pre-push hook, with no full test run"
}
# "<card> <issue>" of the newest landing in <commit> that origin lacks; fails when there is none.
fullowed() { # <commit>
  local c n s
  ! atorigin "$1" || return 1
  while read -r c n s; do
    git merge-base --is-ancestor "$s" "$1" 2>/dev/null && ! atorigin "$s" && { echo "$c $n"; return 0; }
  done < <(stdb ask lines cards 2>/dev/null | jq -rs 'map(select(.step == "landed")) | reverse[] | "\(.card) \(.issue) \(.sha)"' 2>/dev/null)
  return 1
}
fullline() { jq -c --arg t "$(clock)" --arg i "$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')" '{time: $t, id: $i} + .' <<<"$1" >> "$FULLTEST"; } # <the line, without its time and id>
# The push of <commit> (push()), as {ok, reason}: ok once origin holds it; else the reason of the card's last push line.
fullpush() { # <commit> <card> <issue>
  push "$2" "$3" "$1" > /dev/null 2>&1
  if atorigin "$1"; then echo '{"ok":true,"reason":null}'
  else stdb ask card "$2" | jq -cs --arg c "$2" '{ok: false, reason: (map(select(.step == "push" and .card == $c and .result == "fail")) | last | .reason // "the push did not reach origin")}'; fi
}
fullrun() { # <run | push | anyway> <commit> <command> <"card issue" to push under> <who> <the red run's line (anyway)>
  local how=$1 sha=$2 wt=$CARDS/fulltest/wt rc f out cases='[]' pushed=null state=passed c n l reused=null
  read -r c n <<<"$4"
  if [ "$how" = anyway ]; then
    pushed=$(fullpush "$sha" "$c" "$n")
    fullline "$(jq -cn --arg s "$sha" --argjson p "$pushed" --arg by "$5" --argjson r "$6" \
      '{kind: "anyway", push: true, sha: $s, state: $r.state, exit: $r.exit, cases: $r.cases, pushed: $p, by: $by}')"
    return
  fi
  out=$({ git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt" "$wt".*; git worktree prune
    git worktree add -q --detach "$wt" "$sha" && deps "$wt"; } 2>&1 < /dev/null) && out=$(slot_pool 2>&1) || {
    git worktree remove --force "$wt" 2>/dev/null
    fullline "$(jq -cn --arg s "$sha" --argjson p "$([ "$how" = push ] && echo true || echo false)" --arg r "nothing was tested: ${out:0:600}" \
      '{kind: "run", push: $p, sha: $s, state: "error", reason: $r, exit: null, cases: [], pushed: null}')"
    return
  }
  l=$(suitereuse "$wt" "$sha"); rc=$?
  if [ $rc = 2 ]; then
    git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt".*
    fullline "$(jq -cn --arg s "$sha" --argjson p "$([ "$how" = push ] && echo true || echo false)" --arg r "nothing was tested: the worktree of ${sha:0:12} could not be put back on it after the changed-tests selection" \
      '{kind: "run", push: $p, sha: $s, state: "error", reason: $r, exit: null, cases: [], pushed: null}')"
    return
  elif [ $rc = 3 ]; then
    # A pass of every file on this very commit (a release-prep's, or an earlier run's): nothing runs.
    rc=0; reused=$(jq -c '{sha, time, ran: [], kept: (.files | length)}' <<<"$l")
    echo "conveyor: full-test: reuses the green run of $(jq -r .time <<<"$l") on ${sha:0:12}; no test runs"
  else
    if [ $rc = 0 ]; then
      echo "conveyor: full-test: reruns the files that failed or changed since the suite run on $(jq -r '.sha[0:12]' <<<"$l") ($(wc -l < "$wt.files") listed) and reuses its other passes"
      CONVEYOR_SUITE_FILES=$wt.files tests "$wt" test.full; rc=$?
    else l=''; tests "$wt" test.full; rc=$?; fi
    suiterec "$wt" full "$sha"
    reused=$(suitekeep "$wt" "$sha" "$rc" "$([ "$how" = push ] && echo 'push landed' || echo 'full test')" "$l") && [ -n "$reused" ] || reused=null
    # A run of some files only whose results could not be kept proves nothing of the others: it is no pass.
    [ -z "$l" ] || [ "$reused" != null ] || [ $rc != 0 ] || { rc=1; echo "conveyor: full-test: the rerun's results could not be read, so the passes of $(jq -r '.sha[0:12]' <<<"$l") are not reused"; }
  fi
  if [ $rc = 0 ]; then
    [ "$how" != push ] || pushed=$(fullpush "$sha" "$c" "$n")
  else
    state=failed; f=$(testfails "$wt.test" "$rc" test.full) || f='{"files":[]}'
    # A file kept from the reused run passed: each case run alone is told so, as of a file that passed in this run.
    [ -z "$l" ] || f=$(jq -c --argjson l "$l" --rawfile run "$wt.files" '.passed = ((.passed // []) + ([$l.files | to_entries[] | select(.value == "ok") | .key] - ($run | split("\n"))))' <<<"$f")
    # Each case run alone below runs in this worktree and starts a new log folder: the suite's counts are kept first.
    jq -c --argjson p "$(suiteprog "$wt")" '. + {counts: $p}' "$FULLTEST.running" > "$FULLTEST.running.new" 2>/dev/null && mv -f "$FULLTEST.running.new" "$FULLTEST.running"
    cases=$(fulljudge "$wt" "$sha" "$3" "$f") || cases='[]'
  fi
  git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt".*
  fullline "$(jq -cn --arg s "$sha" --argjson p "$([ "$how" = push ] && echo true || echo false)" --arg st "$state" --argjson rc "$rc" --argjson c "$cases" --argjson pu "$pushed" --argjson u "$reused" \
    '{kind: "run", push: $p, sha: $s, state: $st, exit: $rc, cases: $c, pushed: $pu, reused: $u}')"
}
# One run of a unit ({file, case}) alone in <worktree>: every other file of the run (<testfails()>) listed as passed,
# and the case as the one to run of its file (a `fail` line; a unit with no case, its file whole), so a command that
# reads the list runs that alone. Prints passed, failed, timeout or killed. The command is the pack's test.full, or
# <field> (the whole test on main's: test.main).
fullalone() { # <worktree> <testfails() of the run> <unit> [field]
  local rc
  jq -r --argjson u "$3" '([.passed[]?, .files[]?.file, .okcases[]?.file, .passcases[]?.file, (.timeout.file // empty)] | unique - [$u.file] | .[] | "pass\t\(.)"),
    ($u | if .case != null then "fail\t\(.file)\t\(.case)" elif .file != null then "fail\t\(.file)" else empty end)' <<<"$2" > "$1.rerun" || return 1
  tests "$1" "${4:-test.full}" alone; rc=$?
  case $rc in 0) echo passed ;; 124) echo timeout ;; *) if [ "$rc" -gt 128 ]; then echo killed; else echo failed; fi ;; esac
}
# Each failed case of a red run, judged (above): prints them as a JSON array.
fulljudge() { # <worktree> <commit> <command> <testfails() of the run>
  local wt=$1 sha=$2 u name r runs outside code why cause body x v issue reused out=()
  while IFS= read -r u; do
    name=$(jq -r .name <<<"$u"); runs=(); outside=(); code=''
    for ((x = 0; x < FULL_ALONE; x++)); do
      r=$(fullalone "$wt" "$4" "$u") || r=failed; runs+=("$r")
      case $r in
        timeout) outside+=("it timed out alone, under load") ;;
        killed) outside+=("it was killed") ;;
        failed) if v=$(grep -Eio "$FULL_OUTSIDE" "$wt.test" 2>/dev/null | head -n 1) && [ -n "$v" ]; then outside+=("the machine or the network: $v"); else code=1; fi ;;
      esac
    done
    why=''; issue=null; reused=false
    if [ ${#outside[@]} = 0 ] && [ -z "$code" ]; then
      v=flaky; why="failed in the full test suite, passed alone $FULL_ALONE of $FULL_ALONE"
      flaky "full test ${sha:0:12}" "$(jq -cn --arg c "$name" --arg n "$why" '[{case: $c, note: $n}]')" >/dev/null 2>&1 || why+="; the flaky-test record could not be written"
    elif [ -z "$code" ]; then
      v=declined; why="outside the code: $(printf '%s\n' "${outside[@]}" | sort -u | paste -sd';' - | sed 's/;/; /g')"
      declined "full-test-${sha:0:12}" 0 code "$why" "$name: $(jq -r '.line // "failed"' <<<"$u")" 2>/dev/null || why+="; the declined list could not be written"
    else
      v=fix; cause=$(fullcause "$sha" "$4" "$u")
      body="The full test suite (the pack's test.full) failed at ${sha:0:12}, and this case fails alone too: the failure is in the code.

Case: $name
Failure: $(jq -r '.line // "the file failed naming no case"' <<<"$u")
Runs alone at ${sha:0:12}: $(printf '%s\n' "${runs[@]}" | paste -sd, - | sed 's/,/, /g')
Cause: $cause

Done when: the case passes alone and in the full test suite."
      x=$(fullfix "$name" "$body"); issue=$(jq -c '.issue' <<<"$x"); reused=$(jq -c '.reused' <<<"$x"); why=$(jq -r '.why // ""' <<<"$x")
    fi
    out+=("$(jq -c --arg v "$v" --arg why "$why" --argjson i "${issue:-null}" --argjson re "${reused:-false}" \
      '{case: .name, line, runs: $ARGS.positional, verdict: $v, why: (if $why == "" then null else $why end), issue: $i, reused: $re}' --args "${runs[@]}" <<<"$u")")
  done < <(jq -c --arg cmd "$3" '(.files | map(.file)) as $fs
    | [(.files[] | .file as $f | if .cases == [] then {file: $f, case: null, line: null} else .cases[] | {file: $f, case: .name, line} end),
       (.timeout.file // empty | select(IN($fs[]) | not) | {file: ., case: null, line: "it ran out of time"})]
    | unique_by([.file, .case])[] | . + {name: (if .case == null then .file elif .file == $cmd or .file == "" then .case else "\(.file): \(.case)" end)}' <<<"$4")
  printf '%s\n' "${out[@]}" | jq -cs '.'
}
# Why a case that fails alone in the code fails (fulljudge()): a landed commit origin lacks that plausibly caused it, or
# that it was already failing before them.
fullcause() { # <commit> <testfails() of the run> <unit>
  local a x c n base before=() landed=() bwt=$CARDS/fulltest/base out r t f
  for a in "refs/remotes/$REMOTE/$BRANCH" "$(pushed)"; do
    [ -z "$a" ] || ! x=$(git rev-parse -q --verify "$a^{commit}" 2>/dev/null) || before+=("$x")
  done
  mapfile -t landed < <(jq -rs --rawfile in <(git rev-list "$1" --not "${before[@]}" 2>/dev/null) '($in | split("\n") | map(select(. != ""))) as $in
    | (map(select(.step == "landed")) | INDEX(.sha)) as $l | $in[] | select($l[.]) | "\(.) \($l[.].card) \($l[.].issue)"' < <(stdb ask lines cards) 2>/dev/null)
  [ ${#landed[@]} != 0 ] && [ ${#before[@]} != 0 ] && base=$(git merge-base "$1" "${before[0]}" 2>/dev/null) \
    || { echo "it was already failing before the landed commits: the commit tested holds none that origin lacks"; return; }
  out=$({ git worktree remove --force "$bwt" 2>/dev/null; rm -rf "$bwt" "$bwt".*; git worktree prune
    git worktree add -q --detach "$bwt" "$base" && deps "$bwt"; } 2>&1 < /dev/null) \
    || { echo "not known: the case could not be run alone at origin's ${base:0:12}, before the landed commits: ${out:0:300}"; return; }
  r=$(fullalone "$bwt" "$2" "$3"); git worktree remove --force "$bwt" 2>/dev/null; rm -rf "$bwt".*
  [ "$r" = passed ] || { echo "it was already failing before the landed commits: it fails alone at origin's ${base:0:12} too"; return; }
  f=$(jq -r '.file' <<<"$3"); t=''
  [ -z "$f" ] || t=$(git log --format=%H "$base..$1" -- "$f" 2>/dev/null | while read -r x; do printf '%s\n' "${landed[@]}" | grep -m 1 "^$x " && break; done)
  if [ -n "$t" ]; then x="the newest of them that changed $f"; else t=${landed[0]}; x="the newest of them; none changed ${f:-its file}"; fi
  read -r a c n <<<"$t"
  echo "a landed commit plausibly caused it (it passes alone at origin's ${base:0:12}, before them): $(git log -1 --format='%h %s' "$a" 2>/dev/null) (card $c, #$n), $x"
}
# The fix card of a case: the issue filed last for it while it is open (a comment of <body>), else a new one. Prints
# {issue, reused, why}.
fullfix() { # <case> <body>
  local n state out prio
  n=$(jq -rs --arg c "$1" '[.[] | .cases[]? | select(.case == $c and (.issue | type) == "number") | .issue] | last // empty' "$FULLTEST" 2>/dev/null)
  if [ -n "$n" ]; then
    state=$(timeout 20 gh issue view "$n" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null) || state=''
    case $state in
      OPEN) if gh_write issue comment "$n" --body "It fails again.

$2" >/dev/null 2>&1; then jq -cn --argjson n "$n" '{issue: $n, reused: true}'
          else jq -cn --argjson n "$n" '{issue: $n, reused: true, why: "the comment could not be added to it"}'; fi
        return ;;
      CLOSED) ;;
      *) jq -cn --argjson n "$n" '{issue: $n, reused: true, why: "GitHub did not say whether it is still open, so no second issue was filed"}'; return ;;
    esac
  fi
  prio=$(jq -r '.[[1, length - 1] | min]' <<<"$PRIOS")
  out=$(gh_write issue create --title "$(jq -rn --arg c "$1" '"Full test suite fails: " + $c | .[0:200]')" --label "$TYPE" --label "$prio" --body "$2" 2>&1) \
    && n=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && n=${n##*/} && [ -n "$n" ] \
    || { jq -cn --arg r "${out:0:300}" '{issue: null, reused: false, why: ("its issue could not be filed: " + $r)}'; return; }
  jq -cn --argjson n "$n" '{issue: $n, reused: false}'
}
