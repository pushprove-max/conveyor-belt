# SPDX-License-Identifier: Apache-2.0
# The test files run before a push (pushtests()) and those a failed pre-push hook names, run alone (hookalone()).
# lib/push.sh sources it.
# The run before a push of main (pushone(); the owner, 2026-11-18: a card runs only its own test files, listcmd() in
# lib/testrun.sh, and the files the test map links to its change run here): the test files the test map and the
# links give each landing since the last push (testsel() narrow, of the landing's own change: the union, in order),
# each run alone, once: a commit whose run passed ($PUSHED.tested; PUSHTESTED names another such file) is not run again,
# nor a file whose pass in the test results cache holds with the commit's inputs (cachehits(), lib/testlist.sh).
# With the rule Push after a combined test run on and its pushbatchtests all, every test file of the commit in their
# place (testtracked(), less the pack's runners); that pass is kept as "<commit> all", so a pass of the linked files
# does not clear a push that the owner then asked all the files for. Never a test runner or the whole
# suite: testsel() narrow selects neither, and each file runs through a command that runs one file (mapone(),
# lib/testmap.sh: test.fileCommand, else test.command given it as test.list says); a pack with neither runs none and
# says so (PUSHNOFILE). The files run in a worktree of the commit ($CARDS/pushtest) on one test slot, or,
# with more than one to run, test.fileCommand and another slot free, side by side on the free slots (pushside()). The landing
# that broke a file that fails is found by running the file on the landings in turn, newest first (the pushed commit,
# when it is a landing, fails it; one that lacks the file passes it), up to the first that passes it: the oldest of
# the landings after that one, as a file that failed, passed, then failed again was broken by the last change, else
# none (mainred() of lib/mainred.sh looks for it then: brokeby() there). When the oldest landing fails it too, the file
# is run on the commit before that landing: when it fails there as well, it failed before these landings, and the
# reason names no landing for it. Each such file goes to the main-fix card of
# the commit (mainred(), naming that landing),
# and the push is held: a push line, result fail, kind check, its check the first file, its reason naming each file
# with the landing that broke it and the first place its stack traces say it failed, or the scaled time limit it ran
# past (pushfile()), so the loop pushes again only
# once main moves (checkheld()). It fails then, and when its worktree or the test slots cannot be had (kind
# transport, tried again later). With the push check off (pushcheck()), it runs nothing and the push goes on.
# The start of the reason of a push the run before it failed (checkheld() reads it).
PUSHRAN='the run before the push failed'
PUSHNOFILE='the test files linked to the landings did not run before the push: the test command cannot be given one test file; set test.fileCommand in .conveyor/project.json'
pushtests() { # <card> <issue> <the commit to push> [<a commit origin holds>...]
  local c=$1 n=$2 sha=$3 wt=$CARDS/pushtest lands=() fs=() bad=() l f s i tc fc lm by old what why='' all='' took=$SECONDS tested=${PUSHTESTED:-$PUSHED.tested}
  local -A fat=() hit=() # fat: why each failed file failed (pushfile()), which the reason gives after the landing that broke it; hit: cachehits()
  shift 3
  # Until #395 (the push.check rule): a state folder holding push.check.off runs no test before a push (owner's order),
  # unless the rule Push after a combined test run is on (pushbatch(), lib/push.sh): the owner asked for the run then.
  [ ! -f "$ST/push.check.off" ] || pushbatch || return 0
  pushcheck || { echo "conveyor: the push check is off (push.check, control push-check): no test file runs before the push" >&2; return 0; }
  # With the rule Push after a combined test run on and its pushbatchtests all, every test file runs, and its pass is
  # kept as "<commit> all": a pass of the linked files alone does not clear it.
  ! pushbatch || [ "$(ctl 2>/dev/null | jq -r '.rules.pushbatchtests' 2>/dev/null)" != all ] || all=' all'
  [ "$(cat "$tested" 2>/dev/null)" != "$sha$all" ] || return 0
  rm -f "$wt.log" "$wt.at.log"
  packget test.command tc test.fileCommand fc test.list lm 2>/dev/null || return 0
  # With the rule Push after a combined test run on, a push the run cannot test is not made: it fails, kind transport,
  # and is tried again later, once the pack can run one test file.
  if [ -z "$fc" ] && { [ -z "$lm" ] || [ "$lm" = runner ] || [ -n "$(listwhy "$MAIN" "$tc" "$lm")" ]; }; then
    echo "conveyor: $PUSHNOFILE" >&2
    pushbatch || return 0
    record "$c" "$n" push fail "$(jq -cn --arg s "$sha" --arg r "$PUSHNOFILE; the rule Push after a combined test run holds the push until they can run" '{sha: $s, reason: $r, sec: 0, kind: "transport"}')"
    return 1
  fi
  # The landings since the last push, oldest first: "<sha> <card> <issue>".
  mapfile -t lands < <(stdb ask lines cards 2>/dev/null | jq -rs --rawfile in <(git rev-list --reverse "$sha" --not "$@" 2>/dev/null) '
    (map(select(.step == "landed" and (.sha | type) == "string" and .sha != "")) | INDEX(.sha)) as $l
    | $in | split("\n")[] | $l[.] // empty | "\(.sha) \(.card) \(.issue)"')
  [ ${#lands[@]} != 0 ] || { echo "$sha$all" > "$tested"; return 0; }
  pushwt "$wt" "$sha" && slot_pool \
    || { pushwt "$wt"; record "$c" "$n" push fail "$(jq -cn --arg s "$sha" --argjson t $((SECONDS - took)) '{sha: $s, reason: "the worktree or the test slots of the run before the push could not be had", sec: $t, kind: "transport"}')"; return 1; }
  names > /dev/null 2>&1 || :
  # With the rule Push after a combined test run on and its pushbatchtests all, every test file of the commit
  # (testtracked()) but the pack's runners of the whole suite (SUITERUNNERS); else the files linked to the landings.
  if [ -n "$all" ]; then
    mapfile -t fs < <(testtracked "$wt" | grep -vxF -f <(printf '%s\n' "${SUITERUNNERS:-}"))
    what="of ${sha:0:12} (pushbatchtests all)"
  else
    mapfile -t fs < <(for l in "${lands[@]}"; do
        s=$(testsel "$wt" narrow "${l%% *}^" "${l%% *}" 2>/dev/null) && [[ $s == *$'\n'* ]] && printf '%s\n' "${s#*$'\n'}"
      done | awk 'NF && !seen[$0]++')
    what='linked to the landings since the last push'
  fi
  # The files whose last pass in the test results cache read the same inputs as the commit has (cachehits(),
  # lib/testlist.sh): a linked one does not run again, as that pass (a card's Test step, most often) holds on the
  # commit. With pushbatchtests all every file still runs, but such a file runs untraced: its list of inputs is fresh.
  [ ${#fs[@]} = 0 ] || while IFS= read -r f; do [ -z "$f" ] || hit[$f]=1; done < <(cachehits "$wt" 2>/dev/null)
  if [ -z "$all" ] && [ ${#hit[@]} != 0 ]; then
    l=${#fs[@]}; mapfile -t fs < <(for f in "${fs[@]}"; do [ -n "${hit[$f]:-}" ] || printf '%s\n' "$f"; done)
    echo "conveyor: before the push of ${sha:0:12}, $((l - ${#fs[@]})) test file(s) $what passed before with the same inputs and do not run again" >&2
  fi
  if [ ${#fs[@]} != 0 ]; then
    [ -n "$SLOT_HOME" ] || until slot_try || slot_wait; do :; done
    pushprog "$(printf '%s\n' "${fs[@]}")" '' ''
    # More than one file, and a slot of the pool free beside the run's own: side by side (pushside()); else one at a time.
    if [ ${#fs[@]} -gt 1 ] && [ -n "$fc" ] && [ $((SLOT_N - $(slot_used))) -gt 0 ]; then
      echo "conveyor: before the push of ${sha:0:12}, ${#fs[@]} test file(s) $what run, each alone, side by side on the free test slots (${#lands[@]} landing(s) since the last push)" >&2
      pushside "$wt" "$fc" "${fs[@]}"
    else
      echo "conveyor: before the push of ${sha:0:12}, ${#fs[@]} test file(s) $what run, each alone (${#lands[@]} landing(s) since the last push)" >&2
      i=0
      for f in "${fs[@]}"; do
        pushfile "$wt" "$f" "${hit[$f]:-}" || { bad+=("$f"); fat[$f]=$(head -n 1 "$wt.failat" 2>/dev/null); }
        i=$((i + 1)); pushprog "$(printf '%s\n' "${fs[@]}")" "$(printf '%s\n' "${fs[@]:0:i}")" "$(printf '%s\n' "${bad[@]}")"
      done
    fi
    # The passes those runs traced are kept (cachekeep()), so a later push or card takes them while their inputs hold;
    # never of a file whose run failed (a `fail` line in <worktree>.rerun), though its log has `-- ok` for it: a check
    # of the command after its tests (mapcheck, .conveyor/test-changed.sh) can fail the file alone.
    { [ ${#bad[@]} = 0 ] || printf 'fail\t%s\n' "${bad[@]}"; } > "$wt.rerun"
    cachekeep "$wt" 2>/dev/null || :
    for f in "${bad[@]}"; do
      by=''
      for ((i = ${#lands[@]} - 1; i >= 0; i--)); do
        l=${lands[i]}; s=${l%% *}
        if [ "$s" != "$sha" ]; then git cat-file -e "$s:$f" 2>/dev/null && pushwt "$wt.at" "$s" && ! pushfile "$wt.at" "$f" || break; fi
        by=$l
      done
      # The oldest landing fails it too: when the commit before that landing fails it as well, no landing broke it.
      old=''; s=${by%% *}
      if [ -n "$by" ] && [ "$by" = "${lands[0]}" ] && git cat-file -e "$s^:$f" 2>/dev/null && pushwt "$wt.at" "$s^" && ! pushfile "$wt.at" "$f"; then old=1; by=''; fi
      mainred "$c" "$f" "$f" "$sha" "$by" || :
      read -r s l _ <<<"$by"
      if [ -n "$s" ]; then why+="${why:+, }$f (broken by the landing ${s:0:12} of $l"
      elif [ -n "$old" ]; then why+="${why:+, }$f (it failed before the landings since the last push too"
      else why+="${why:+, }$f (the landing that broke it is not known"; fi
      why+="${fat[$f]:+; ${fat[$f]}})"
    done
    [ -n "$SLOT_HOME" ] || slot_free
  fi
  pushwt "$wt"; pushwt "$wt.at"
  [ ${#bad[@]} != 0 ] || { echo "$sha$all" > "$tested"; return 0; }
  record "$c" "$n" push fail "$(jq -cn --arg s "$sha" --argjson t $((SECONDS - took)) --arg f "${bad[0]}" \
    --arg r "$PUSHRAN ${#bad[@]} test file(s) $what: $why. Each goes to the main-fix card of ${sha:0:12}, and main is pushed again once it moves" \
    '{sha: $s, reason: $r, sec: $t, kind: "check", check: ($f | .[0:100])}')"
  return 1
}
# Whether the run before a push (pushtests()) runs: always while the rule Push after a combined test run is on
# (pushbatch(), lib/push.sh); else the control record's pushCheck (`control push-check on|off`) when it sets one, else
# the pack's push.check; on when neither gives a value (no record or pack read, or no push.check).
pushcheck() {
  local v
  ! pushbatch || return 0
  v=$(ctl 2>/dev/null | jq -r '.pushCheck | booleans' 2>/dev/null)
  [ -n "$v" ] || packget push.check v 2>/dev/null || v=true
  [ "$v" != false ]
}
# A worktree of the run before the push (pushtests()), with main's dependency links, made anew at <commit>; with no
# commit, removed.
pushwt() { # <worktree> [<commit>]
  git worktree remove --force "$1" 2>/dev/null; rm -rf "$1" "$1.testlog" "$1.failat" "$1.rerun"; git worktree prune 2>/dev/null
  [ -n "${2:-}" ] || return 0
  git worktree add -q --detach "$1" "$2" > /dev/null 2>&1 && deps "$1" > /dev/null && mkdir -p "$1.testlog"
}
# One test file run alone in <worktree> (pushtests(), hookalone()), on the slot it holds, its output added to
# <worktree>.log, with what a card's test run gives a test command (testonce(), lib/testrun.sh): the slots, its log
# folder, the load factor (CONVEYOR_LOAD_FACTOR: loadfactor()) and CONVEYOR_TEST_TIME, which a test.fileCommand the
# Board's Record CPU time wrapped calls (cputwrap()). When it fails, <worktree>.failat says why, a line each: `it
# failed at <place>` for each place its output's stack traces say it failed (failat(), lib/failat.sh), or, when it ran
# past its time limit, that limit with the load factor it was scaled by. With <fresh> set (the test results cache holds
# a pass of the file with the inputs it has here: pushtests()), CONVEYOR_TEST_NOTRACE=1 tells the command that its list
# of inputs is fresh, so it need not trace the file's reads (`TESTRUN inputs`).
pushfile() { # <worktree> <test file> [<fresh>]
  local cmd n=0 rc f s
  rm -f "$1.failat"; cmd=$(mapone "$1" "$2" '') || return 1
  [ ! -f "$1.log" ] || n=$(wc -l < "$1.log") || n=0
  # Its time limit is testTimeout times the load factor (LOADSCALE, lib/testrun.sh), which a timeout's line names.
  f=$(loadfactor); s=$(awk -v n="${TEST_TIMEOUT:-3600}" -v f="$f" "$LOADSCALE")
  { echo "== $2"; ( cd "$1" && { [ -n "$SLOT_HOME" ] || slot_mine; } && CONVEYOR_TEST_SLOTS=$HERE/lib/slots.sh CONVEYOR_TEST_LOG=$1.testlog \
      CONVEYOR_TEST_TIME=$HERE/tools/testtime.sh CONVEYOR_LOAD_FACTOR=$f CONVEYOR_TEST_NOTRACE=${3:+1} exec timeout --kill-after=30 "$s" bash -c "$cmd" < /dev/null 8>&- ); } >> "$1.log" 2>&1
  rc=$?
  if [ $rc = 124 ]; then
    echo "it ran past its time limit, $s s (testTimeout's ${TEST_TIMEOUT:-3600} s times the load factor $f), and was stopped there" > "$1.failat"
    echo "conveyor: $2 timed out: $(cat "$1.failat")" >> "$1.log"
  elif [ $rc != 0 ]; then tail -n "+$((n + 2))" "$1.log" 2>/dev/null | failat "$1" | sed 's/^/it failed at /' > "$1.failat"; fi
  return $rc
}
# The test files <file>... run side by side in <worktree> (pushtests(), with more than one to run and a slot of the
# pool free beside the run's own), through fileeach() side (lib/fileeach.sh): each file in its own process, on a test
# slot of its own (the slot the run holds, then slots of the pool as they come free), with the pack's <test.fileCommand>
# and what pushfile() gives one file: its time limit too, testTimeout times the load factor. Their output is added to
# <worktree>.log, in the files' order. Each file with no `-- ok` line in the run's log is added to the caller's bad, and
# why it failed (the line pushfile() puts first in <worktree>.failat) to the caller's fat; the caller's hit names the
# files whose list of inputs is fresh, each run with CONVEYOR_TEST_NOTRACE=1. While they run, and at their end, the
# push record names the files done and failed (pushprog()).
pushside() { # <worktree> <test.fileCommand> <file>...
  local w=$1 fc=$2 f s lf l=$1.testlog/files wp; shift 2
  rm -f "$w.fresh"; [ ${#hit[@]} = 0 ] || printf '%s\n' "${!hit[@]}" > "$w.fresh"
  lf=$(loadfactor); s=$(awk -v n="${TEST_TIMEOUT:-3600}" -v f="$lf" "$LOADSCALE")
  # While the files run, the push record names those whose end line the run's log has (pushprog()), each second.
  # sleep: the run's log has no event to wait on, and the watcher is ended as the run ends.
  ( while sleep 1; do pushprog "$(printf '%s\n' "$@")" "$(sed -nE 's/^-- (ok|FAIL|timeout) //p' "$l" 2>/dev/null)" \
      "$(sed -nE 's/^-- (FAIL|timeout) //p' "$l" 2>/dev/null)"; done ) 8>&- & wp=$!
  # fileeach()'s own limit of a file is the number its FILELIMIT program prints: here testTimeout, for every file.
  ( cd "$w" && { [ -n "$SLOT_HOME" ] || slot_mine; } && export CONVEYOR_TEST_SLOTS=$HERE/lib/slots.sh CONVEYOR_TEST_LOG=$w.testlog \
      CONVEYOR_TEST_TIME=$HERE/tools/testtime.sh CONVEYOR_LOAD_FACTOR=$lf CONVEYOR_TEST_NOTRACE='' CONVEYOR_TEST_FAILFAST='' \
    && fileeach side "{ ! grep -qxF -- \"\$CONVEYOR_TEST_FILE\" $(printf %q "$w.fresh") 2>/dev/null || export CONVEYOR_TEST_NOTRACE=1; }; $fc" \
      "BEGIN { print ${TEST_TIMEOUT:-3600}; exit }" "$LOADSCALE" "$l" "$@" < /dev/null 8>&- ) >> "$w.log" 2>&1
  kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
  rm -f "$w.fresh"
  for f; do
    ! grep -qxF -- "-- ok $f" "$l" 2>/dev/null || continue
    bad+=("$f")
    if grep -qxF -- "-- timeout $f" "$l" 2>/dev/null; then
      fat[$f]="it ran past its time limit, $s s (testTimeout's ${TEST_TIMEOUT:-3600} s times the load factor $lf), and was stopped there"
    else # its output: the lines after its `== <file>` line, up to the next file's
      fat[$f]=$(awk -v f="$f" 'FNR == NR { h["== " $0] = 1; next } $0 == "== " f { on = 1; next } on && ($0 in h) { exit } on' \
        <(printf '%s\n' "$@") "$w.log" | failat "$w" | sed 's/^/it failed at /' | head -n 1)
    fi
  done
  pushprog "$(printf '%s\n' "$@")" "$(printf '%s\n' "$@")" "$(printf '%s\n' "${bad[@]}")"
}
# The progress of the run before the push (pushtests()) in the push record ($PUSHING, pushing(), lib/push.sh), as
# files: {chosen: the test files it runs, done: those of them that ended, failed: those of them that failed}: chosen in
# the run's order, done and failed as they ended; so health (lib/views.sh) gives them to the Board while the push
# runs. Only the record of this shell's push (pproc, else this shell): a run with no push record of its own (the idle
# merge's) writes none.
pushprog() { # <chosen, a line each> <done, a line each> <failed, a line each>
  local t=$PUSHING.$BASHPID # this shell's own: the watcher's write never meets the run's
  [ "$(jq -r '.pid' "$PUSHING" 2>/dev/null)" = "${pproc:-$BASHPID}" ] || return 0
  jq -c --arg c "$1" --arg d "$2" --arg f "$3" 'def l: split("\n") | map(select(. != ""));
    . + {files: {chosen: ($c | l), done: ($d | l), failed: ($f | l)}}' "$PUSHING" > "$t" 2>/dev/null && mv -f "$t" "$PUSHING" || rm -f "$t"
}
# The test files a failed pre-push hook names as failing (hookalone()), one a line: each test file of <commit>
# (testtracked(), lib/issues.sh) that a line of the hook's output names, whole or after a /, on a line that says it
# failed (FAIL, failed, ✖ or "not ok"). None when the hook says a check FAILED (its words "FAILED <name>", the check a
# push line names) that is not one of those files (a pytest node id, file::case, is its file): the hook failed for
# more than these files, so running them alone cannot clear it. A name in brackets is a check too ("FAILED
# (fast-checks)"), but not a count, which holds "=", as Python's unittest ends a failed run ("FAILED (failures=1)").
hookfiles() { # <commit> <the hook's output>
  local fs
  fs=$(testtracked "$MAIN" "$1") && [ -n "$fs" ] || return 0
  printf '%s' "$2" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\000\r' | jq -rRs --arg fs "$fs" '
    def esc: gsub("(?<c>[][.+*?()|{}^$\\\\])"; "\\\(.c)");
    split("\n") as $o | [$fs | split("\n")[] | select(. != "")] as $fs
    # Each failure line takes the longest paths first, and the text of a path it names is then no other path: the
    # end of lib/a.test.sh is not the file a.test.sh too.
    | [$o[] | select(test("FAIL|failed|✖|not ok")) as $l
        | reduce ($fs | sort_by(-length) | .[]) as $f ({l: $l, hit: []};
            ("(?<a>^|[^A-Za-z0-9_.-])" + ($f | esc) + "(?<b>$|[^A-Za-z0-9_/-])") as $re
            | if .l | test($re) then .hit += [$f] | .l |= gsub($re; "\(.a)\u0000\(.b)") else . end) | .hit[]] | unique as $hit
    | [$o | join("\n") | scan("(?:^|[^A-Za-z0-9_])FAILED:?[ \t]+(\\([^()=\\n]+\\)|[^\\s(]\\S*)") | .[0] | sub("^\\((?<n>.*)\\)$"; "\(.n)") | sub("::.*$"; "") | sub("[:,.]$"; "")] as $checks
    | if $hit != [] and all($checks[]; . as $c | any($hit[]; . == $c or ($c | endswith("/" + .)))) then $hit[] else empty end'
}
# Each test file a failed pre-push hook names (hookfiles()) run again alone, once, on <commit>, as the run before the
# push runs one (pushfile(); in a worktree of the commit, $CARDS/pushhook, its output in $CARDS/pushhook.log, on one
# test slot). Prints the files, one a line, when every one passed alone. Fails when the hook names none (printing
# nothing), and when a file failed alone too or the worktree or the slots could not be had (printing why).
hookalone() { # <commit> <the hook's output>
  local wt=$CARDS/pushhook fs=() f bad=()
  mapfile -t fs < <(hookfiles "$1" "$2")
  [ ${#fs[@]} != 0 ] || return 1
  rm -f "$wt.log"
  pushwt "$wt" "$1" && slot_pool || { pushwt "$wt"; echo "the test files the pre-push hook named could not be run alone: their worktree or the test slots could not be had"; return 1; }
  echo "conveyor: the pre-push hook of ${1:0:12} failed naming ${#fs[@]} test file(s); each runs alone, once" >&2
  [ -n "$SLOT_HOME" ] || until slot_try || slot_wait; do :; done
  for f in "${fs[@]}"; do pushfile "$wt" "$f" || bad+=("$f"); done
  [ -n "$SLOT_HOME" ] || slot_free
  pushwt "$wt"
  [ ${#bad[@]} = 0 ] || { echo "the pre-push hook named $(printf '%s, ' "${bad[@]}" | sed 's/, $//'), which fails alone too (its output: $wt.log)"; return 1; }
  printf '%s\n' "${fs[@]}"
}
