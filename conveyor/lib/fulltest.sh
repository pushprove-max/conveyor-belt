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
# pushed) and by (who pushed anyway). $FULLTEST.running holds {since, sha, how} while the lock is held, and, once a red
# run's failed cases are run alone, counts: the whole run's suiteprog().
FULLTEST=${STATE%/*}/fulltest.jsonl
FULL_ALONE=3
# How far a whole-suite run (this one's, or a release's: commands/release-prep.sh) in <worktree> is, from the cases its
# runner named as ended (cases/ok and cases/failed of its log folder, session.sh testdone()): {done, failed, cases: the
# names of the failed ones}.
suiteprog() { # <worktree>
  local d=$1.testlog/cases
  { find "$d/ok" -maxdepth 1 -type f 2>/dev/null | sed 's|.*/|ok\t|'; find "$d/failed" -maxdepth 1 -type f 2>/dev/null | sed 's|.*/|failed\t|'; } \
    | jq -Rsc '[split("\n")[] | select(. != "") | split("\t")] | {done: length, failed: map(select(.[0] == "failed")) | length, cases: [.[] | select(.[0] == "failed") | .[1]] | sort}'
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
  local how=$1 sha=$2 wt=$CARDS/fulltest/wt rc f out cases='[]' pushed=null state=passed c n
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
  tests "$wt" test.full; rc=$?
  if [ $rc = 0 ]; then
    [ "$how" != push ] || pushed=$(fullpush "$sha" "$c" "$n")
  else
    state=failed; f=$(testfails "$wt.test" "$rc" test.full) || f='{"files":[]}'
    # Each case run alone below runs in this worktree and starts a new log folder: the suite's counts are kept first.
    jq -c --argjson p "$(suiteprog "$wt")" '. + {counts: $p}' "$FULLTEST.running" > "$FULLTEST.running.new" 2>/dev/null && mv -f "$FULLTEST.running.new" "$FULLTEST.running"
    cases=$(fulljudge "$wt" "$sha" "$3" "$f") || cases='[]'
  fi
  git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt".*
  fullline "$(jq -cn --arg s "$sha" --argjson p "$([ "$how" = push ] && echo true || echo false)" --arg st "$state" --argjson rc "$rc" --argjson c "$cases" --argjson pu "$pushed" \
    '{kind: "run", push: $p, sha: $s, state: $st, exit: $rc, cases: $c, pushed: $pu}')"
}
# One run of a unit ({file, case}) alone in <worktree>: every other file of the run (<testfails()>) listed as passed,
# and the case, when there is one, as the one to run of its file. Prints passed, failed, timeout or killed.
fullalone() { # <worktree> <testfails() of the run> <unit>
  local rc
  jq -r --argjson u "$3" '([.passed[]?, .files[]?.file, .okcases[]?.file, .passcases[]?.file, (.timeout.file // empty)] | unique - [$u.file] | .[] | "pass\t\(.)"),
    ($u | select(.case != null) | "fail\t\(.file)\t\(.case)")' <<<"$2" > "$1.rerun" || return 1
  tests "$1" test.full alone; rc=$?
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
