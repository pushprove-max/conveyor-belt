# SPDX-License-Identifier: Apache-2.0
# The main checkout's dependencies: a link for each path of the pack's linkFromMain that main has as a folder,
# its parent folders made first when the worktree has none.
# A link is not a folder, so an ignore rule with a trailing slash lets `git add -A` stage it: the exclude file (git
# keeps one for the repository, read by every worktree of it) names each path outright, from the worktree's top.
# Then the pack's worktree.setup, when it has one, runs once in the worktree (from its top, its output kept back):
# the install command of a project whose dependencies are not linked. When it fails, its last lines are the reason.
NODEPS="worktree: the engine could not link the dependencies of the main checkout" # how the blocked reason starts: block() reads it
deps() { # <worktree>; prints why when it fails
  local d p ps l s o
  local -A ex=()
  # The exclude file's lines are read once, not grepped for each path (#532); a line added here is added to them too.
  { packget linkFromMain ps worktree.setup s && d=$(git -C "$1" rev-parse --path-format=absolute --git-path info/exclude) && mkdir -p "${d%/*}" \
    && { [ ! -f "$d" ] || while IFS= read -r l || [ -n "$l" ]; do ex[x$l]=1; done < "$d"; } \
    && while IFS= read -r -d '' p; do
         { [ -n "${ex[x/$p]:-}" ] || { echo "/$p" >> "$d" && ex[x/$p]=1; }; } && { [ ! -d "$MAIN/$p" ] || { mkdir -p "$(dirname "$1/$p")" && ln -sfn "$MAIN/$p" "$1/$p"; }; } || return 1
       done < <(jq -j '.[] | "\(.)\u0000"' <<<"$ps"); } 2>&1 || return 1
  [ -z "$s" ] || o=$(cd "$1" && bash -c "$s" 2>&1 < /dev/null) || { echo "worktree.setup ($s) failed (exit $?): $(tail -n 20 <<<"$o")"; return 1; }
}
# The dependency folders of a checkout, one path a line from its top: each folder git ignores and does not track
# (none inside another ignored folder) whose name is one a package manager or build tool fills, at any depth, so the
# node_modules of each package of a workspace too. A link is no folder of the checkout: main's own links are left out.
DEPNAMES=' node_modules .venv venv vendor target .gradle Pods bower_components .bundle .dart_tool elm-stuff '
depdirs() { # <checkout>
  local p
  while IFS= read -r -d '' p; do
    p=${p%/}; [[ $DEPNAMES == *" ${p##*/} "* ]] && [ -d "$1/$p" ] && [ ! -L "$1/$p" ] && printf '%s\n' "$p"
  done < <(git -C "$1" ls-files -z --others --ignored --exclude-standard --directory 2>/dev/null)
  return 0
}
# The dependency folders of the main checkout that a worktree lacks, joined by ", ": each one whose parent folder the
# worktree has (a folder the worktree has no package for is not one its tests need). Empty: none missing.
depsmissing() { # <worktree>
  local p m=''
  while IFS= read -r p; do
    [ -n "$p" ] && [ ! -e "$1/$p" ] && { [[ $p != */* ]] || [ -d "$1/${p%/*}" ]; } && m+="${m:+, }$p"
  done < <(depdirs "$MAIN")
  [ -z "$m" ] || printf '%s\n' "$m"
}
# The blocked reason of a card whose tests failed in a worktree that lacks some of main's dependency folders.
depsreason() { # <the folders, from depsmissing>
  echo "tests: $1 $([[ $1 == *", "* ]] && echo are || echo is) missing in the card's worktree; add $([[ $1 == *", "* ]] && echo them || echo it) to linkFromMain or set worktree.setup"
}

# One push of main to origin, for the loop (the reasons are in README.md): the commit main is at, checked out
# alone in $CARDS/push, pushed from there by its name, so the hook judges exactly the bytes the push carries. The git
# push, and so the hook, holds a slot of the machine's test pool, taken ahead of every test worker that waits for one
# (slot_first), on the slot's core (slot_mine): a machine full of test runs gives the
# project's pre-push checks a test unit's share, not a sliver of what is left (the owner, 2026-11-15). A loop started
# on a slot it holds already (CONVEYOR_TEST_SLOT: a loop an engine case runs) pushes on that one, as its tests run. When
# it works the commit, the remote and the branch are written to $PUSHED; when it fails, a push line under the given card (the last one landed)
# holds the commit, the end of what git and the hook said, and why it failed (kind: check or transport; a check
# failure names the check: the word after the last "FAILED" the hook printed, else the pre-push hook). A hook that
# failed naming test files has them run alone first (hookalone()): when each passes, the same commit is pushed with no
# hook, the files go on the flaky-test record with one held issue (flakypush(), lib/flaky.sh), and each pushed line
# names them (flaky: {files, issues}). The worktree goes either way; nothing but this
# function writes in it, so a stale one (a push killed half way) is cleared before the next.
# A push the remote refuses because its main holds a commit this one lacks (landed there by hand) is made again in the
# same turn, of main merged with the remote's (remerge()); when they do not merge, the push line says so.
# A push that worked leaves its marks: under each landed card whose commit it carried (the commits it took
# to origin, past what origin held before), a `pushed` line; then, for each of those that has an issue, an `issue`
# line: ok once GitHub shows the issue closed (the commit's "Closes #N" closes it when main reaches origin, a moment
# after the push), fail when it is still open CLOSE_WAIT seconds later. The cards of one push are asked about in
# turn, round after round, under one CLOSE_WAIT counted from the push: asked one after the other, each with a wait of
# its own, the eighth card's answer came after the snapshot had stopped holding it on the belt (it holds a pushed
# card with no issue line for CLOSE_WAIT + 300 s). Every card is asked about at least once; a GitHub that answers
# nothing (each call is given 20 s) is not asked past CLOSE_WAIT + 200 s, so the last issue line of a push is
# written within CLOSE_WAIT + 220 s of its pushed lines, and a card never asked about says so in its reason.
# Given a commit (the Board's Push landed: the one its full test run tested, fulltest()), that commit is pushed, not
# main as it is then. One the remote refuses for a commit of its own is not merged and pushed again: the merge is a
# commit the run did not test, so the push fails, saying so, and main is left as it is. One push at a time, the loop's or the Board's: they share the push worktree, so each holds $PUSHED.lock throughout.
push() { # <card> <issue> [<commit>]
  local lk rc
  { exec {lk}>>"$PUSHED.lock"; } 2>/dev/null && flock "$lk" || { echo "conveyor: the push lock could not be taken; nothing pushed" >&2; return 1; }
  pushone "$@" {lk}>&-; rc=$?; exec {lk}>&-; return $rc
}
pushone() { # <card> <issue> [<commit>]
  local wt=$CARDS/push sha out rc=0 a c n s t state round=0 before=() got=() pend=() rest=() took=$SECONDS try m want=${3:-} at la to nv='' ff=() fl='' ho=''; local -A said=()
  la=$(landas) || { echo "conveyor: the rule Land as could not be read (the pack's push.landAs or the control record); nothing pushed" >&2; return 1; }
  to=$BRANCH; [ "$la" != pr ] || to=$LANDING
  for a in "$(pushed)" "refs/remotes/$REMOTE/$BRANCH"; do
    [ -z "$a" ] || ! a=$(git rev-parse -q --verify "$a^{commit}" 2>/dev/null) || before+=("$a")
  done
  # Main as it is now runs the test files linked to its landings first (pushtests()), and that commit is pushed: one
  # that lands meanwhile waits for the next push. A given commit had the full test run.
  at=${want:-refs/heads/$BRANCH}
  if [ -z "$want" ] && sha=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null); then
    pushing "$sha"; pushtests "$1" "$2" "$sha" "${before[@]}" || return 1; at=$sha
  fi
  # A pre-push hook that failed naming test files that each pass alone (hookalone()) failed under load, not in the
  # code: the same commit is pushed again with no hook (nv: --no-verify), and the files go on the flaky-test record
  # (ff, then fl: flakypush(), given the hook's output, ho). A file that fails alone too, or a hook that names none,
  # holds the push as before.
  while :; do
  for try in 1 2; do
    rm -f "$wt.trace"
    rc=0; sha=$(git rev-parse "$at" 2>&1) && pushing "$sha" && out=$({
      git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt"; git worktree prune
      packget push.env e && mapfile -d '' -t e < <(jq -j 'to_entries[] | "\(.key)=\(.value)\u0000"' <<<"$e") \
        && git worktree add -q --detach "$wt" "$sha" && deps "$wt" && cd "$wt" \
        && slot_pool && { [ -n "$SLOT_HOME" ] || { slot_first && slot_mine; }; } \
        && env "${e[@]}" GIT_TRACE2_EVENT="$wt.trace" timeout --kill-after=30 "$PUSH_TIMEOUT" git push ${nv:+"$nv"} "$REMOTE" "$sha:refs/heads/$to"
    } 2>&1 < /dev/null 8>&-) && { [ "$la" = pr ] || echo "$sha $REMOTE $BRANCH" > "$PUSHED"; } || rc=$?
    # The remote refused the push (git's "[rejected]": its main holds a commit this one lacks): main takes the
    # remote's commits in a merge commit and is pushed again, once, in this same turn. The worktree stays until they
    # are fetched: the fetch is made from it, as the push was.
    # With Land as pr, origin's default branch is not pushed to, so there is nothing of it to merge. A push with no
    # hook merges nothing either: the merge is a commit no hook judged, so the next push makes it, through the hook.
    [ $rc != 0 ] && [ $try = 1 ] && [ "$la" != pr ] && [ -z "$nv" ] && grep -qF '[rejected]' <<<"$out"; a=$?
    [ $a != 0 ] || [ -z "$want" ] || { out+=$'\n'"$REMOTE/$BRANCH holds a commit ${sha:0:12} lacks: a merge with it is a commit the full test run did not test, so nothing is pushed"; a=1; }
    [ $a != 0 ] || m=$(theirs "$sha" "$wt") || { out+=$'\n'"the remote's commits were not merged into main: ${m:0:600}"; a=1; }
    git worktree remove --force "$wt" 2>/dev/null
    [ $a = 0 ] || break
    # Main is the merge with the remote's commits now (remerge()).
    at=refs/heads/$BRANCH
  done
  [ $rc != 0 ] && [ -z "$nv" ] && [ $rc != 124 ] && [ $rc != 137 ] && hookfailed "$wt.trace" || break
  m=$(hookalone "$sha" "$out") || { [ -z "$m" ] || out+=$'\n'"conveyor: $m"; break; }
  mapfile -t ff <<<"$m"; ho=$out; nv=--no-verify; at=$sha
  done
  took=$((SECONDS - took))
  # Why it failed (docs/cards.md, Push): check, the pre-push hook exited non-zero (it fails the same way on the same
  # commit, so the loop does not push again until main moves: checkheld()), or transport, anything else (git, the
  # network, the remote, the timeout), which a later try may get past.
  [ $rc = 0 ] || { a=transport; [ $rc = 124 ] || [ $rc = 137 ] || ! hookfailed "$wt.trace" || a=check; rm -f "$wt.trace"
    record "$1" "$2" push fail "$(jq -cn --arg s "$([[ $sha =~ ^[0-9a-f]{40,64}$ ]] && echo "$sha")" --argjson t "$took" --arg k "$a" --arg o "$(tail -c 20000 <<<"$out" | tr -d '\000')" \
    --arg r "exit $rc (124 is the ${PUSH_TIMEOUT}s timeout): $(tail -c 1200 <<<"${out:-$sha}" | tr -d '\000')" '{sha:$s,reason:$r,sec:$t,kind:$k}
      + if $k == "check" then {check: ([$o | scan("(?:^|[^A-Za-z0-9_])FAILED:?[ \t]+(\\S+)")] | last[0] // "the pre-push hook" | .[0:100])} else {} end')"; return; }
  rm -f "$wt.trace"
  # Pushed over a hook that failed under load: each pushed line says so (flaky: {files, issues}).
  [ ${#ff[@]} = 0 ] || { fl=$(flakypush "$sha" "$ho" "${ff[@]}") || :; fl=",\"flaky\":${fl:-$(jq -cn '{files: $ARGS.positional, issues: []}' --args "${ff[@]}")}"; }
  mapfile -t got < <(jq -rs --rawfile in <(git rev-list "$sha" --not "${before[@]}" 2>/dev/null) '($in | split("\n") | map(select(. != "")) | INDEX(.)) as $in
    | map(select(.step == "pushed") | .card) as $have | .[] | select(.step == "landed" and $in[.sha] and (.card | IN($have[]) | not)) | "\(.card) \(.issue) \(.sha)"' < <(stdb ask lines cards))
  # With Land as pr: the pull request is opened or updated before the push counts. When it fails, the push line says
  # why and the push is owed still (the commit is not written as pushed), so the next push tries the pull request
  # again. Each card's pushed line names the pull request (pr); no issue is waited on: they close when it is merged.
  if [ "$la" = pr ]; then
    m=$(landpr "${got[@]}") || { record "$1" "$2" push fail "$(jq -cn --arg s "$sha" --argjson t "$took" --arg r "the commit is on $REMOTE/$LANDING, but $m" '{sha:$s,reason:$r,sec:$t,kind:"transport"}')"; return; }
    echo "$sha $REMOTE $LANDING" > "$PUSHED"
    for a in "${got[@]}"; do read -r c n s <<<"$a"; record "$c" "$n" pushed ok "{\"sha\":\"$s\",\"sec\":$took,\"head\":\"$sha\",\"pr\":$m$fl}"; done
    return 0
  fi
  for a in "${got[@]}"; do read -r c n s <<<"$a"; record "$c" "$n" pushed ok "{\"sha\":\"$s\",\"sec\":$took,\"head\":\"$sha\"$fl}"; done
  for a in "${got[@]}"; do read -r c n s <<<"$a"; [ "$n" = 0 ] || pend+=("$a"); done
  t=$SECONDS
  while [ ${#pend[@]} != 0 ]; do
    round=$((round + 1)); rest=()
    for a in "${pend[@]}"; do
      read -r c n s <<<"$a"
      if [ $((SECONDS - t)) -ge "$CLOSE_WAIT" ] && { [ -n "${said[$c]:-}" ] || [ "$round" -gt 1 ] || [ $((SECONDS - t)) -ge $((CLOSE_WAIT + 200)) ]; }; then rest+=("$a"); continue; fi
      state=$(timeout 20 gh issue view "$n" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null) || state=''
      [ -z "$state" ] || said[$c]=1
      if [ "$state" = CLOSED ]; then record "$c" "$n" issue ok; else rest+=("$a"); fi
    done
    pend=("${rest[@]}"); [ $((SECONDS - t)) -lt "$CLOSE_WAIT" ] || break
    [ ${#pend[@]} = 0 ] || sleep 5 8>&-
  done
  for a in "${pend[@]}"; do
    read -r c n s <<<"$a"
    record "$c" "$n" issue fail "$(jq -cn --arg r "$([ -n "${said[$c]:-}" ] && echo "GitHub still shows the issue open" || echo "GitHub gave no answer about the issue in the") $((SECONDS - t)) s after the push of $s" '{reason:$r}')"
  done
}
# The run before a push of main (pushone(); the owner, 2026-11-18: a card runs only its own test files, listcmd() in
# lib/testrun.sh, and the files the test map links to its change run here): the test files the test map and the
# links give each landing since the last push (testsel() narrow, of the landing's own change: the union, in order),
# each run alone, once: a commit whose run passed ($PUSHED.tested; PUSHTESTED names another such file) is not run again. Never a test runner or the whole
# suite: testsel() narrow selects neither, and each file runs through a command that runs one file (mapone(),
# lib/testmap.sh: test.fileCommand, else test.command given it as test.list says); a pack with neither runs none and
# says so (PUSHNOFILE). The files run in a worktree of the commit ($CARDS/pushtest) on one test slot. The landing
# that broke a file that fails is found by running the file on the landings in turn, oldest first (one that lacks the
# file passes it): the first that fails it, else the pushed commit when it is a landing, else none (mainred() looks
# for it then: brokeby()). Each such file goes to the main-fix card of the commit (mainred(), naming that landing),
# and the push is held: a push line, result fail, kind check, its check the first file, so the loop pushes again only
# once main moves (checkheld()). It fails then, and when its worktree or the test slots cannot be had (kind
# transport, tried again later). With the push check off (pushcheck()), it runs nothing and the push goes on.
# The start of the reason of a push the run before it failed (checkheld() reads it).
PUSHRAN='the run before the push failed'
PUSHNOFILE='the test files linked to the landings did not run before the push: the test command cannot be given one test file; set test.fileCommand in .conveyor/project.json'
pushtests() { # <card> <issue> <the commit to push> [<a commit origin holds>...]
  local c=$1 n=$2 sha=$3 wt=$CARDS/pushtest lands=() fs=() bad=() l f s tc fc lm by why='' took=$SECONDS tested=${PUSHTESTED:-$PUSHED.tested}
  shift 3
  # Until #395 (the push.check rule): a state folder holding push.check.off runs no test before a push (owner's order).
  [ ! -f "$ST/push.check.off" ] || return 0
  pushcheck || { echo "conveyor: the push check is off (push.check, control push-check): no test file runs before the push" >&2; return 0; }
  [ "$(cat "$tested" 2>/dev/null)" != "$sha" ] || return 0
  rm -f "$wt.log" "$wt.at.log"
  packget test.command tc test.fileCommand fc test.list lm 2>/dev/null || return 0
  if [ -z "$fc" ] && { [ -z "$lm" ] || [ "$lm" = runner ] || [ -n "$(listwhy "$MAIN" "$tc" "$lm")" ]; }; then echo "conveyor: $PUSHNOFILE" >&2; return 0; fi
  # The landings since the last push, oldest first: "<sha> <card> <issue>".
  mapfile -t lands < <(stdb ask lines cards 2>/dev/null | jq -rs --rawfile in <(git rev-list --reverse "$sha" --not "$@" 2>/dev/null) '
    (map(select(.step == "landed" and (.sha | type) == "string" and .sha != "")) | INDEX(.sha)) as $l
    | $in | split("\n")[] | $l[.] // empty | "\(.sha) \(.card) \(.issue)"')
  [ ${#lands[@]} != 0 ] || { echo "$sha" > "$tested"; return 0; }
  pushwt "$wt" "$sha" && slot_pool \
    || { pushwt "$wt"; record "$c" "$n" push fail "$(jq -cn --arg s "$sha" --argjson t $((SECONDS - took)) '{sha: $s, reason: "the worktree or the test slots of the run before the push could not be had", sec: $t, kind: "transport"}')"; return 1; }
  names > /dev/null 2>&1 || :
  mapfile -t fs < <(for l in "${lands[@]}"; do
      s=$(testsel "$wt" narrow "${l%% *}^" "${l%% *}" 2>/dev/null) && [[ $s == *$'\n'* ]] && printf '%s\n' "${s#*$'\n'}"
    done | awk 'NF && !seen[$0]++')
  if [ ${#fs[@]} != 0 ]; then
    echo "conveyor: before the push of ${sha:0:12}, ${#fs[@]} test file(s) linked to the ${#lands[@]} landing(s) since the last push run, each alone" >&2
    [ -n "$SLOT_HOME" ] || until slot_try || slot_wait; do :; done
    for f in "${fs[@]}"; do pushfile "$wt" "$f" || bad+=("$f"); done
    for f in "${bad[@]}"; do
      by=''
      for l in "${lands[@]}"; do
        s=${l%% *}
        [ "$s" != "$sha" ] || { by=$l; break; }
        git cat-file -e "$s:$f" 2>/dev/null || continue
        if pushwt "$wt.at" "$s" && ! pushfile "$wt.at" "$f"; then by=$l; break; fi
      done
      mainred "$c" "$f" "$f" "$sha" "$by" || :
      read -r s l _ <<<"$by"
      if [ -n "$s" ]; then why+="${why:+, }$f (broken by the landing ${s:0:12} of $l)"; else why+="${why:+, }$f (the landing that broke it is not known)"; fi
    done
    [ -n "$SLOT_HOME" ] || slot_free
  fi
  pushwt "$wt"; pushwt "$wt.at"
  [ ${#bad[@]} != 0 ] || { echo "$sha" > "$tested"; return 0; }
  record "$c" "$n" push fail "$(jq -cn --arg s "$sha" --argjson t $((SECONDS - took)) --arg f "${bad[0]}" \
    --arg r "$PUSHRAN ${#bad[@]} test file(s) linked to the landings since the last push: $why. Each goes to the main-fix card of ${sha:0:12}, and main is pushed again once it moves" \
    '{sha: $s, reason: $r, sec: $t, kind: "check", check: ($f | .[0:100])}')"
  return 1
}
# Whether the run before a push (pushtests()) runs: the control record's pushCheck (`control push-check on|off`) when it
# sets one, else the pack's push.check; on when neither gives a value (no record or pack read, or no push.check).
pushcheck() {
  local v
  v=$(ctl 2>/dev/null | jq -r '.pushCheck | booleans' 2>/dev/null)
  [ -n "$v" ] || packget push.check v 2>/dev/null || v=true
  [ "$v" != false ]
}
# A worktree of the run before the push (pushtests()), with main's dependency links, made anew at <commit>; with no
# commit, removed.
pushwt() { # <worktree> [<commit>]
  git worktree remove --force "$1" 2>/dev/null; rm -rf "$1" "$1.testlog"; git worktree prune 2>/dev/null
  [ -n "${2:-}" ] || return 0
  git worktree add -q --detach "$1" "$2" > /dev/null 2>&1 && deps "$1" > /dev/null && mkdir -p "$1.testlog"
}
# One test file run alone in <worktree> (pushtests(), hookalone()), on the slot it holds, its output added to
# <worktree>.log, with what a card's test run gives a test command (testonce(), lib/testrun.sh): the slots, its log
# folder and CONVEYOR_TEST_TIME, which a test.fileCommand the Board's Record CPU time wrapped calls (cputwrap()).
pushfile() { # <worktree> <test file>
  local cmd
  cmd=$(mapone "$1" "$2" '') || return 1
  { echo "== $2"; ( cd "$1" && { [ -n "$SLOT_HOME" ] || slot_mine; } && CONVEYOR_TEST_SLOTS=$HERE/lib/slots.sh CONVEYOR_TEST_LOG=$1.testlog \
      CONVEYOR_TEST_TIME=$HERE/tools/testtime.sh exec timeout --kill-after=30 "${TEST_TIMEOUT:-3600}" bash -c "$cmd" < /dev/null 8>&- ); } >> "$1.log" 2>&1
}
# The test files a failed pre-push hook names as failing (hookalone()), one a line: each test file of <commit>
# (testtracked(), lib/issues.sh) that a line of the hook's output names, whole or after a /, on a line that says it
# failed (FAIL, failed, ✖ or "not ok"). None when the hook says a check FAILED (its words "FAILED <name>", the check a
# push line names) that is not one of those files (a pytest node id, file::case, is its file): the hook failed for
# more than these files, so running them alone cannot clear it. A count after FAILED, as Python's unittest ends a
# failed run ("FAILED (failures=1)"), is no check.
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
    | [$o | join("\n") | scan("(?:^|[^A-Za-z0-9_])FAILED:?[ \t]+([^\\s(]\\S*)") | .[0] | sub("::.*$"; "") | sub("[:,.]$"; "")] as $checks
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
# The remote's commits a refused push lacks, merged into main (remerge()). They are fetched as the push was made:
# with the pack's push.env (what lets the push reach the remote lets the fetch too), from the push worktree (a
# relative URL names the same repository from there only), and from where the push went: every URL the remote pushes
# to, as git resolves them under push.env (a pushurl may be set there), each fetched and merged in turn, for the
# commit that refused the push is at any of them, not only the first, and may be at none the remote fetches from.
# Each is fetched as a remote of its own that has that one URL and every other setting of the remote (its
# uploadpack, its proxy: a URL fetched bare would lose them, and git fetches a named remote from its first URL only).
# Prints why when a fetch or a merge fails, or no URL holds a commit main lacks.
theirs() { # <the commit that was pushed> <the push worktree>
  local e u us m x kv k n=conveyor-pushed cfg c=() at=$1
  packget push.env e && mapfile -d '' -t e < <(jq -j 'to_entries[] | "\(.key)=\(.value)\u0000"' <<<"$e") || return 1
  us=$(cd "$2" && env "${e[@]}" git remote get-url --push --all "$REMOTE" 2>&1) || { echo "$us"; return 1; }
  # git config -z: a key, a newline and its value; a key alone is a setting with no value (true).
  mapfile -d '' -t cfg < <(cd "$2" && env "${e[@]}" git config -z --get-regexp '^remote\.' 2>/dev/null)
  # A name no remote has: one that is set already would keep its own URLs, first, and its other settings.
  while [[ $'\n'$(printf '%s\n' "${cfg[@]%%$'\n'*}") == *$'\n'"remote.$n."* ]]; do n+=-1; done
  for kv in "${cfg[@]}"; do
    k=${kv%%$'\n'*}; k=${k#"remote.$REMOTE."}
    [[ $k != *.* && $k != url && $k != pushurl ]] || continue
    [[ $kv == *$'\n'* ]] && c+=(-c "remote.$n.$k=${kv#*$'\n'}") || c+=(-c "remote.$n.$k")
  done
  while IFS= read -r u; do
    m=$(cd "$2" && GIT_TERMINAL_PROMPT=0 env "${e[@]}" timeout --kill-after=30 "$PUSH_TIMEOUT" git "${c[@]}" -c "remote.$n.url=$u" \
        fetch -q "$n" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 2>&1 < /dev/null 8>&-) || { echo "$m"; return 1; }
    x=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") || { echo "no $REMOTE/$BRANCH was fetched"; return 1; }
    ! git merge-base --is-ancestor "$x" "$at" || continue
    m=$(locked remerge "$at") || { echo "$m"; return 1; }
    at=$m
  done <<<"$us"
  [ "$at" != "$1" ] || { echo "main already holds $REMOTE/$BRANCH ($x)"; return 1; }
}
# One of main's commit hooks, as `git commit` runs it, on the index and repository the environment names (a landing's
# and a merge's private index): `git hook run --ignore-missing`. Git before 2.36 (Ubuntu 22.04's 2.34) has no `git
# hook` (`git hook -h` exits 129 where it is there), so the hook is run here as git runs it: from the hooks folder
# (`git rev-parse --git-path hooks`: core.hooksPath when set, else the repository's hooks), in the top of the work
# tree, with no stdin and without the loop's run lock (fd 8, as git() in conveyor.sh), only when it is a file that can
# be run. Exits as the hook does, 0 when there is none.
commithook() { # <hook name> [the hook's arguments]
  git hook -h >/dev/null 2>&1
  [ $? != 129 ] || { git hook run --ignore-missing "$1" -- "${@:2}"; return; }
  ( t=$(git rev-parse --show-toplevel) && cd "$t" && h=$(git rev-parse --git-path "hooks/$1") || exit 1
    [ -f "$h" ] && [ -x "$h" ] || exit 0
    exec "$h" "${@:2}" < /dev/null 8>&- )
}
# The merge a refused push needs, under the lock (landings move main under it too): the remote's main as just
# fetched, merged into the commit that was pushed. Only a merge git makes with no conflict (merge-tree) is taken;
# main gets it as landings get theirs: its tree is in a private index, main's commit hooks judge that index and the
# message (a merge they refuse, or change, is not made), the commit is made beside the checkout, the checkout gets its
# diff, and main moves by compare-and-swap from the commit that was pushed. Prints the merge commit, or why there is none.
remerge() { # <the commit that was pushed>
  local x t m err f=$CARDS/push.merge
  x=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") || { echo "no $REMOTE/$BRANCH was fetched"; return 1; }
  ! git merge-base --is-ancestor "$x" "$1" || { echo "main already holds $REMOTE/$BRANCH ($x)"; return 1; }
  t=$(git merge-tree --write-tree --name-only "$1" "$x" 2>&1) || { echo "$REMOTE/$BRANCH ($x) does not merge with main ($1): ${t#*$'\n'}"; return 1; }
  [ "$(git symbolic-ref -q HEAD)" = "refs/heads/$BRANCH" ] && [ "$(git rev-parse "refs/heads/$BRANCH")" = "$1" ] || { echo "main moved during the push, or its checkout is not on the $BRANCH branch"; return 1; }
  printf '%s\n' "Merge $REMOTE/$BRANCH into $BRANCH" > "$f.msg" && rm -f "$f.index" && GIT_INDEX_FILE="$f.index" git read-tree "$t" || { echo "cannot make the merge's index"; return 1; }
  err=$(export GIT_INDEX_FILE="$f.index"; commithook pre-commit 2>&1 && commithook commit-msg "$f.msg" 2>&1) || { echo "commit of the merge refused: ${err:0:600}"; return 1; }
  [ "$(GIT_INDEX_FILE="$f.index" git write-tree)" = "$t" ] || { echo "main's hooks changed what the merge would commit; it needs $OWNER"; return 1; }
  m=$(git commit-tree "$t" -p "$1" -p "$x" -F "$f.msg" 2>&1) || { echo "cannot make the merge commit: $m"; return 1; }
  git diff --quiet "$1" "$m" || err=$(git diff --binary --no-renames "$1" "$m" | git apply --index 2>&1) || { echo "the merge does not apply to main's checkout: $err"; return 1; }
  git update-ref -m "conveyor merge of $REMOTE/$BRANCH" "refs/heads/$BRANCH" "$m" "$1" || { echo "main moved during the merge; its change is left in main's checkout for $OWNER to sort out"; return 1; }
  echo "$m"
}
# The push in progress, for health to read: this push job's pid, when it began and the commit it pushes. The
# loop clears it when the job ends; one left by a loop that was killed names a pid that is gone, and health ignores it.
# The commit of the last push that worked, when it went to the pack's remote and to the branch Land as pushes to
# (pushto(): the pack's branch, or LANDING): a push to another one says nothing of what this one holds.
pushed() { local s r b; read -r s r b 2>/dev/null < "$PUSHED" && [ "$r" = "$REMOTE" ] && [ "$b" = "$(pushto)" ] && echo "$s"; }
# The rule "Land as" (docs/configuration.md): main, the push goes to the pack's branch; pr, it goes to LANDING, and one
# pull request from there into the pack's branch collects the cards (landpr()). The control record's landAs, else the
# pack's push.landAs. Fails when either cannot be read: a push to the wrong branch is not undone.
LANDING=conveyor/landing
landas() { local d x; packget push.landAs d && x=$(ctl 2>/dev/null) && x=$(jq -er --arg d "$d" '.landAs // $d' <<<"$x" 2>/dev/null) && echo "$x"; }
pushto() { local la; la=$(landas) || return 1; if [ "$la" = pr ]; then echo "$LANDING"; else echo "$BRANCH"; fi; }
# The pull requests GitHub has open from LANDING into the pack's branch, as a JSON array of {number, url}, newest
# first; or, when GitHub could not be asked, gh's error, and it fails. `gh pr list --head` matches the branch name in
# any repository, so a fork's pull request from its own conveyor/landing is listed too: it is left out (and any whose
# isCrossRepository GitHub did not give), as Conveyor would edit or merge it with its own credentials.
landingprs() { # [seconds to wait for gh, default 60]
  local out
  out=$(timeout "${1:-60}" gh pr list --head "$LANDING" --base "$BRANCH" --state open --json number,url,isCrossRepository 2>&1) \
    && jq -ce 'arrays | map(select(.isCrossRepository == false) | {number, url})' <<<"$out" 2>/dev/null || { echo "$out"; return 1; }
}
# The one pull request of Land as pr, from LANDING into the pack's branch: the open one is updated, and with none open
# (the first push, or the first after it was merged) one is opened. Its body is written whole at each push: every card
# in it, in landing order (the cards whose pushed line names it, then those this push carries), each with its
# "Closes #N" (a card of no issue has none), title, card id, Done-when check with its D<n> lines (doneLines, each with
# its state), fix rounds and the tests it ran (each file, with the cases it selected of it). Prints the
# pull request's number, or why it failed. $LANDPR then names it, with its link, for the Board's Merge (prstate()).
landpr() { # <"card issue sha" of each card this push carries>...
  local n out text url
  out=$(landingprs) && n=$(jq -er '.[0].number // 0 | numbers' <<<"$out" 2>/dev/null) \
    || { echo "the open pull request from $LANDING could not be read: ${out:0:600}"; return 1; }
  url=$(jq -r '.[0].url // "" | strings' <<<"$out" 2>/dev/null)
  text=$(stdb ask lines cards 2>/dev/null | jq -rs --argjson n "$n" --arg b "$BRANCH" '. as $all | $ARGS.positional as $new
    | (map(select(.step == "pushed" and $n != 0 and .pr == $n) | .card) + $new) as $in
    | reduce (.[] | select(.step == "landed" and (.card | IN($in[])))) as $l ([]; if any(.[]; .card == $l.card) then . else . + [$l] end)
    | "Conveyor: \(length) card\(if length == 1 then "" else "s" end) landed on \($b)",
      "Conveyor lands these cards on \($b) through this pull request, in the order they landed. Merging it closes their issues.", "",
      (.[] | . as $l | [$all[] | select(.card == $l.card)] as $c
        | ([$c[] | .title // empty | strings | select(. != "")] | first // "(no title)" | .[0:200]) as $t
        | ([$c[] | select(.doneWhen)] | last // null) as $dl | ($dl.doneWhen // null) as $d
        # The tests it ran: the outcome of its last test line that ran them (a line that reused an earlier pass names
        # none, and a later run that selected no file or no case ran none of them; a card with no run of a case shows
        # its last run), and the files and cases of all its runs: a later run runs only what changed, as the test cache
        # keeps the rest off it.
        | [$c[] | select(.step == "test" and (.reused | not))] as $r
        | (($r | map(select(.ended != "nothing selected" and .selected.files != 0 and .selected.cases != 0)) | last) // ($r | last)) as $x
        | "## \(if $l.issue != 0 then "#\($l.issue) " else "" end)\($t)", "",
          (if $l.issue != 0 then "Closes #\($l.issue)" else empty end),
          "- Card: `\($l.card)`",
          (if $d == null then "- Done when: not checked" else "- Done when: \($d.met) of \($d.items) met" end),
          ($dl.doneLines // [] | .[] | strings | "  - \(.[0:300])"),
          ($d.failed // [] | .[] | "  - not met: \(.[0:300])"),
          "- Fix rounds: \([$c[] | select(.step == "fix")] | length)",
          (if $x == null then "- Tests: none ran"
           else "- Tests: \($x.ended // $x.result)\($x.tests // {} | to_entries | map(select(.value != null) | ", \(.value) \(.key)") | join(""))",
             ([$r[] | (.ran // [] | arrays | .[] | strings), (.times, .clocks, .ranCases | objects | keys[])] | unique[]
               | . as $f | "  - `\($f)`\([$r[] | .ranCases | objects | .[$f] | arrays | .[] | strings] | unique
                 | if . == [] then "" else ": " + join(", ") end)") end), "")' --args "${@%% *}") \
    || { echo "the pull request's body could not be made from the card records"; return 1; }
  if [ "$n" = 0 ]; then
    out=$(gh_write pr create --base "$BRANCH" --head "$LANDING" --title "${text%%$'\n'*}" --body "${text#*$'\n'}" 2>&1) && url=$(tail -n 1 <<<"$out") && n=${url##*/pull/} && [[ $n =~ ^[1-9][0-9]*$ ]] \
      || { echo "the pull request could not be opened: ${out:0:600}"; return 1; }
  else
    out=$(gh_write pr edit "$n" --title "${text%%$'\n'*}" --body "${text#*$'\n'}" 2>&1) || { echo "pull request #$n could not be updated: ${out:0:600}"; return 1; }
  fi
  prstate "$n" '.url = (if $u == "" then .url else $u end)' --arg u "$url"
  echo "$n"
}
# The landing pull request as the Board and the Foreman see it (health's landingPr), in $LANDPR: {number, url (null
# when GitHub gave none), merge ({time, by, sha, result: merged or refused, reason}: the last merge asked of it, else
# null), merged (when it was merged, else null), closed (when GitHub showed it not open, merged or closed there, prsync(); else
# null)}. A pull request of another number starts the file anew.
prstate() { # <number> <jq filter, with $t the time> [jq arguments]
  local x n=$1 f=$2
  shift 2
  x=$(jq -c 'objects' "$LANDPR" 2>/dev/null) || x=null
  jq -cn --argjson x "${x:-null}" --argjson n "$n" --arg t "$(clock)" "$@" \
    '(if $x.number == $n then $x else {number: $n, url: null, merge: null, merged: null} end) | '"$f" > "$LANDPR.new" 2>/dev/null \
    && mv -f "$LANDPR.new" "$LANDPR"
}
# $LANDPR brought to GitHub's state (health() reads it, else `github` for `watch`): the pull request GitHub has open
# from LANDING is named there, with its link (one opened before $LANDPR was kept too), and with none open, the one it
# names as open is closed (merged or closed on GitHub, not here), so the Board shows no Merge for it. Skipped while a
# push or a merge holds the push lock (each writes $LANDPR itself), and when GitHub does not answer. With Land as main
# it still asks while $LANDPR names one open: a pull request left open when the rule changed is merged or closed on
# GitHub later, and the Board must not keep showing it.
prsync() {
  local lk out n u
  [ "$(landas 2>/dev/null)" = pr ] || jq -e 'objects | .merged == null and .closed == null and (.number | type) == "number"' "$LANDPR" > /dev/null 2>&1 || return 0
  { exec {lk}>>"$PUSHED.lock"; } 2>/dev/null || return 0
  if flock -n "$lk"; then
    if out=$(landingprs 20 {lk}>&-) \
      && n=$(jq -er '.[0].number // 0 | numbers' <<<"$out" 2>/dev/null); then
      if [ "$n" != 0 ]; then u=$(jq -r '.[0].url // "" | strings' <<<"$out"); prstate "$n" '.closed = null | .url = (if $u == "" then .url else $u end)' --arg u "$u"
      elif n=$(jq -er 'objects | select(.merged == null and .closed == null) | .number | numbers' "$LANDPR" 2>/dev/null); then prstate "$n" '.closed = $t'
      fi
    fi
  fi
  exec {lk}>&-
}
# The rule "Merge PR" (docs/configuration.md): who merges the pull request of Land as pr. button (the default): only the
# owner, with the Board's Merge or `conveyor.sh pr merge`; release: `release` merges it before it tags; idle: the loop
# merges it when nothing is on the belt and nothing can be picked, once the push run passes on it (idlemerge()). The
# control record's prMerge, else the pack's push.prMerge. Fails when either cannot be read.
prmergerule() { local d x; packget push.prMerge d && x=$(ctl 2>/dev/null) && x=$(jq -er --arg d "$d" '.prMerge // $d' <<<"$x" 2>/dev/null) && echo "$x"; }
# The merge of the open pull request from LANDING, by <who> (button, release or idle), under the push lock (no push
# goes to LANDING during it): GitHub's merge with --merge, a merge commit, so main here takes origin's default branch as it is
# then (prmain()). The issues of the cards in it (those whose pushed line names it) that GitHub still shows open are
# closed, each with an issue line, and $LANDPR says merged: the next push opens a new pull request (landpr()). A merge
# GitHub refuses (checks, conflicts) leaves the pull request open, and $LANDPR's merge gives GitHub's reason. Exit 2: no
# pull request is open; 1: refused, or it could not be asked; 3: merged, but main or an issue was not brought in line
# after it (said on stderr).
prmerge() { # <who>
  local lk rc
  { exec {lk}>>"$PUSHED.lock"; } 2>/dev/null && flock "$lk" || { echo "conveyor: the push lock could not be taken; nothing merged" >&2; return 1; }
  mergeone "$@" {lk}>&-; rc=$?; exec {lk}>&-; return $rc
}
mergeone() { # <who>
  local n out sha m c i st rc=0
  out=$(landingprs) && n=$(jq -er '.[0].number // 0 | numbers' <<<"$out" 2>/dev/null) \
    || { echo "conveyor: the open pull request from $LANDING could not be read: ${out:0:600}" >&2; return 1; }
  [ "$n" != 0 ] || { echo "conveyor: no pull request from $LANDING into $BRANCH is open; nothing merged" >&2; return 2; }
  sha=$(pushed) || sha=''
  if ! out=$(gh_write pr merge "$n" --merge 2>&1 < /dev/null); then
    prstate "$n" '.merge = {time: $t, by: $w, sha: $s, result: "refused", reason: $r}' --arg w "$1" --arg s "$sha" --arg r "$(tail -c 1200 <<<"${out:-gh gave no reason}")"
    echo "conveyor: GitHub refused the merge of pull request #$n, which stays open: ${out:0:600}" >&2; return 1
  fi
  prstate "$n" '.merged = $t | .merge = {time: $t, by: $w, sha: $s, result: "merged", reason: null}' --arg w "$1" --arg s "$sha"
  echo "conveyor: pull request #$n is merged into $REMOTE/$BRANCH"
  m=$(prmain) || { rc=3; echo "conveyor: $BRANCH here was not brought to $REMOTE/$BRANCH after the merge: $m" >&2; }
  while read -r c i; do
    st=$(timeout 20 gh issue view "$i" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null) || st=''
    if [ "$st" = CLOSED ] || out=$(gh_write issue close "$i" --comment "Closed by the merge of pull request #$n." 2>&1 < /dev/null); then record "$c" "$i" issue ok
    else rc=3; record "$c" "$i" issue fail "$(jq -cn --arg r "the merge of pull request #$n did not close the issue: ${out:0:600}" '{reason: $r}')"
      echo "conveyor: issue #$i was not closed after the merge: ${out:0:600}" >&2; fi
  done < <(stdb ask lines cards 2>/dev/null | jq -rs --argjson n "$n" 'map(select(.step == "pushed" and .pr == $n and .issue != 0)) | unique_by(.card) | .[] | "\(.card) \(.issue)"')
  return $rc
}
# Origin's default branch, fetched with the pack's push.env: prints its commit, or why it could not be had.
prfetch() {
  local e err
  packget push.env e && mapfile -d '' -t e < <(jq -j 'to_entries[] | "\(.key)=\(.value)\u0000"' <<<"$e") || { echo "push.env could not be read"; return 1; }
  err=$(GIT_TERMINAL_PROMPT=0 env "${e[@]}" timeout --kill-after=30 "$PUSH_TIMEOUT" git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 2>&1 < /dev/null 8>&-) \
    || { echo "the fetch of $REMOTE/$BRANCH failed: ${err:0:600}"; return 1; }
  git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}" || { echo "no $REMOTE/$BRANCH was fetched"; return 1; }
}
# Main here brought to origin's default branch after a merge (mergeone()), under the lock (landings move main under it
# too): a fast-forward when main has nothing origin lacks, the checkout given its diff and main moved by
# compare-and-swap; a merge when cards landed since the push (remerge()). Prints why it failed.
prmain() { local x; x=$(prfetch) || { echo "$x"; return 1; }; locked prff "$x"; }
prff() { # <origin's default branch, fetched>
  local at err
  at=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") || { echo "$BRANCH could not be read"; return 1; }
  ! git merge-base --is-ancestor "$1" "$at" || return 0
  if ! git merge-base --is-ancestor "$at" "$1"; then err=$(remerge "$at") || { echo "$err"; return 1; }; return 0; fi
  [ "$(git symbolic-ref -q HEAD)" = "refs/heads/$BRANCH" ] || { echo "main's checkout is not on the $BRANCH branch"; return 1; }
  git diff --quiet "$at" "$1" || err=$(git diff --binary --no-renames "$at" "$1" | git apply --index 2>&1) || { echo "$REMOTE/$BRANCH does not apply to main's checkout: $err"; return 1; }
  git update-ref -m "conveyor: $REMOTE/$BRANCH after the merge of the landing pull request" "refs/heads/$BRANCH" "$1" "$at" || { echo "$BRANCH moved meanwhile"; return 1; }
}
# Merge PR idle (prmergerule()): the loop calls it at a turn that picked nothing, with no card of its own running and no
# push under way. Under the push lock, it merges the open pull request (mergeone()) when no card in the card records is
# open, no push is owed (owed()), and the push run (pushtests()) passes on the commit LANDING holds: the test files
# linked to every landing in it (those since origin's default branch, fetched now), each alone, once a commit
# ($PUSHED.prtested). A run that fails goes to the main-fix card as a push's does and holds the merge until main moves
# (checkheld()); a merge GitHub refused is not asked again of the same commit. The rule and the belt are read again
# after that run, which takes minutes: a card the loop picked meanwhile, or the rule changed, holds the merge.
idlemerge() {
  local lk rc
  idlenow || return 0
  { exec {lk}>>"$PUSHED.lock"; } 2>/dev/null && flock "$lk" || return 1
  idleone {lk}>&-; rc=$?; exec {lk}>&-; return $rc
}
# Merge PR idle holds now: the rule is idle, Land as pr, and every card in the card records is closed (filed, landed,
# closed or blocked).
idlenow() {
  [ "$(prmergerule 2>/dev/null)" = idle ] && [ "$(landas 2>/dev/null)" = pr ] || return 1
  stdb ask lines cards 2>/dev/null | jq -se 'map(select(.step | IN("push", "pushed", "issue", "bugproof") | not)) | group_by(.card)
    | all(.[]; any(.[]; .step | IN("filed", "landed", "closed", "blocked")))' > /dev/null
}
idleone() {
  local sha c n x
  sha=$(pushed) && [ -n "$sha" ] && jq -e --arg s "$sha" '.merged == null and .closed == null and (.merge.result == "refused" and .merge.sha == $s | not)' "$LANDPR" > /dev/null 2>&1 || return 0
  ! owed > /dev/null && ! checkheld || return 0
  read -r c n < <(stdb ask lines cards 2>/dev/null | jq -rs 'map(select(.step == "landed")) | last // empty | "\(.card) \(.issue)"')
  [ -n "$c" ] || return 0
  x=$(prfetch) || { echo "conveyor: Merge PR idle: $x" >&2; return 1; }
  PUSHTESTED=$PUSHED.prtested pushtests "$c" "$n" "$sha" "$x" || return 1
  idlenow || return 0
  mergeone idle
}
pushing() { jq -cn --argjson p "$BASHPID" --arg s "$1" '{pid:$p,since:(now|todate),sha:$s}' > "$PUSHING" 2>/dev/null || :; }
# Did the push's pre-push hook exit non-zero? Read from git's trace2 events of the push (the file given): the first
# event is the push's own, and only its own children count (a check that runs git, or pushes in a test of its own,
# writes its events there too, under another session id). No file, or no such event: no.
hookfailed() { # <trace2 event file>
  jq -Rne 'first(inputs | fromjson? | objects | .sid | strings) as $s
    | reduce (inputs | fromjson? | objects | select(.sid == $s)) as $e ({hooks: [], failed: false};
        if $e.event == "child_start" and $e.child_class == "hook" and ($e.hook_name // ($e.argv[0] | tostring | split("/") | last)) == "pre-push" then .hooks += [$e.child_id]
        elif $e.event == "child_exit" and $e.code != 0 and (.hooks | index([$e.child_id])) != null then .failed = true else . end) | .failed' "$1" >/dev/null 2>&1
}
# The last push failed its check (kind check) on the commit main is at now: the loop does not push again until main
# moves (a fix lands), for the check fails the same way on the same commit. A failure of the run before the push
# (pushtests()) holds it only while the push check is on (pushcheck()): turned off, that run does not run again.
checkheld() {
  local tip on=true
  tip=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") || return 1
  pushcheck || on=false
  turncards 2>/dev/null | jq -Rne --arg s "$tip" --arg ran "$PUSHRAN " --argjson on "$on" 'last(inputs | fromjson? | objects | select(.step == "push"))
    | .result == "fail" and .kind == "check" and .sha == $s and ($on or (.reason | tostring | startswith($ran) | not))' >/dev/null 2>&1
}
# Has the pack's remote this commit? Yes when the last push that worked to its branch, or that branch as last seen
# here, holds it.
atorigin() { # <sha>
  local at
  for at in "$(pushed)" "refs/remotes/$REMOTE/$BRANCH"; do
    [ -z "$at" ] || ! git merge-base --is-ancestor "$1" "$at" 2>/dev/null || return 0
  done
  return 1
}
# The commit release-prep's suite runs on (commands/release-prep.sh), after the remote's branch and tags are fetched:
# the remote's head of the pack's branch; with Land as pr and Merge PR release (prmergerule()), the head of LANDING
# while that holds a commit the branch lacks, as `release` merges that pull request before it tags. Fails when the
# remote's branch cannot be read.
relhead() {
  local sha out
  git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 'refs/tags/v*:refs/tags/v*' < /dev/null \
    && sha=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") || return 1
  if [ "$(prmergerule 2>/dev/null)" = release ] && [ "$(landas 2>/dev/null)" = pr ] \
    && git fetch -q "$REMOTE" "+refs/heads/$LANDING:refs/remotes/$REMOTE/$LANDING" < /dev/null 2>/dev/null \
    && out=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$LANDING^{commit}") && ! git merge-base --is-ancestor "$out" "$sha"; then
    sha=$out
  fi
  echo "$sha"
}
# The push that is owed, as "<card> <issue> <sha>" of the last landing: its commit is in main and not at origin.
# None while the control record's rule "Push when a card lands" is off (rules.push: land only): the landed commits
# wait for the Board's Push landed (fulltest()) or Push now (pushnow()). A record that does not read keeps the push on.
owed() {
  local o
  [ "$(ctl 2>/dev/null | jq -r '.rules.push')" != false ] || return 1
  o=$(stdb ask lines cards 2>/dev/null | jq -r 'select(.step == "landed") | "\(.card) \(.issue) \(.sha)"' 2>/dev/null); o=${o##*$'\n'}
  [ -n "$o" ] && git merge-base --is-ancestor "${o##* }" "refs/heads/$BRANCH" 2>/dev/null && ! atorigin "${o##* }" && echo "$o"
}
# The push a turn of the loop starts (run(), lib/run.sh), in run()'s own variables: with the pack read (nopack), no
# push running (pusher) and no restart due (new), the owed push (owed) is started beside the cards as a job, its pid
# in pusher, at once when it is not the one last tried (tried), else once PUSH_RETRY seconds have passed since that
# try (triedat); never while it failed its check on main's commit (checkheld()). The turn goes on at once either way.
pushturn() {
  [ -z "$nopack" ] && [ -z "$pusher" ] && [ -z "$new" ] && owed=$(owed) && { [ "$owed" != "$tried" ] || [ $((SECONDS - triedat)) -ge "$PUSH_RETRY" ]; } || return 0
  tried=$owed; triedat=$SECONDS; read -r c n _ <<<"$owed"
  checkheld || { push "$c" "$n" & pusher=$!; }
}
# A turn's check that the push job (pusher) has ended: then no push runs, and its pushing state goes.
pushended() { [ -z "$pusher" ] || jobs -rp | grep -qx "$pusher" || { pusher=''; rm -f "$PUSHING"; }; }

tidy() { git worktree remove --force "$1" 2>/dev/null; rm -f "$1".events "$1".firsttry "$1".firsttry.new "$1".patch "$1".index "$1".msg "$1".review.new "$1".carried "$1".base "$1".live "$1".live.tmp "$1".idle "$1".claim "$1".claim.new "$1".cpatch "$1".cpatch.new "$1".stack "$1".settings "$1".opencode.json "$1".donewhen "$1".unfixed "$1".covered "$1".stalled "$1".ready "$1".ready.new "$1".batch "$1".batch.new "$1".bpatch "$1".lent "$1".batchtest "$1".batchfirst "$1".first "$1".rerun "$1".rerun.new "$1".sharedran "$1".whole "$1".passed "$1".bpass "$1".oldtimes "$1".times "$1".reported "$1".report "$1".report.[0-9]* "$1".testlist "$1".uncovered "$1".slow "$1".timed "$1".cpus "$1".clocks "$1".oldfiles "$1".before; rm -rf "$1".rv "$1".batchtestlog "$1".covfirst "$1".checks; }
# The project's own screenshots of a change that waits for the owner's yes, kept local for the Board: the images
# (PNG, JPEG, GIF, WebP) in the worktree folder the pack's review.screenshots names, which the project's own run
# writes (Conveyor takes none). Each is copied to <kept>/shots named by its content (git hash-object), the first
# SHOTS_MAX by path, none over SHOT_MAX bytes, with shots.json: {patch: the hash of the kept patch <kept>/<card>.patch,
# shots: [{file, caption: its path in the folder}]}. The Board shows them only while the card's kept patch is that one.
# An image not newer, to the nanosecond, than every file the change touches outside the folder, and every tracked file
# outside it, was made from an older patch of the card, before a later session changed it: it is left out. Tracked
# files count too, as a session that puts a file back as it was in HEAD drops it from the change but not from what the
# image shows. A file's time is the later of its mtime and its ctime, as a file moved away and back (git mv) keeps its
# mtime but not its ctime. Every folder that holds such a file counts too, as a folder moved away and back keeps the
# times of the files in it: only its own ctime and its parent's mtime change. A folder that holds the screenshot folder
# (the worktree's own among them) counts too, but an image may have its time: making the screenshot folder changed it,
# in the same clock tick as the first image. A later time there is a file added to or removed from it after the image,
# such as a file the card added and a later session removed, which no list names once it is gone; an ignored file
# made there after the image leaves the image out too. A file the change deletes is reckoned by the nearest folder that is still there, as removing it changed
# that folder's time. A folder outside the worktree (an absolute path, .., or a link
# out) gives none, and no link in it is followed. With no image, nothing is written.
SHOTS_MAX=8 SHOT_MAX=$((2 * 1024 * 1024))
keepshots() { # <worktree> <kept folder> <card>
  local dir wt s f fs=() ups=() newest=0 up=0 sz mt n=0 h ext list=() p i; local -A ds=()
  rm -rf "$2/shots"
  packget review.screenshots dir 2>/dev/null && [ -n "$dir" ] && [[ $dir != /* && /$dir/ != */../* ]] || return 0
  wt=$(cd "$1" && pwd -P) && s=$(cd "$1/$dir" 2>/dev/null && pwd -P) && [[ $s == "$wt"/* ]] || return 0
  mapfile -d '' -t fs < <(git -C "$1" diff --cached -z --name-only --no-renames -- . ":(exclude,literal)$dir"
    git -C "$1" ls-files -z -- . ":(exclude,literal)$dir")
  for i in "${!fs[@]}"; do
    p=${fs[i]}; while [ ! -e "$1/$p" ] && [ ! -L "$1/$p" ] && [ "$p" != . ]; do [[ $p == */* ]] && p=${p%/*} || p=.; done; fs[i]=$p
  done
  p=${s#"$wt"/}; while [[ $p == */* ]]; do p=${p%/*}; ds[$p]=0; done
  for p in "${fs[@]}"; do while [[ $p == */* ]]; do p=${p%/*}; [ -z "${ds[$p]-}" ] || break; ds[$p]=1; done; done
  ups=(.); for p in "${!ds[@]}"; do [ "${ds[$p]}" = 0 ] && ups+=("$p") || fs+=("$p"); done
  while read -r mt; do [ "$mt" -le "$newest" ] || newest=$mt; done < <(cd "$1" && for ((i = 0; i < ${#fs[@]}; i += 1000)); do p_mtimens "${fs[@]:i:1000}"; p_ctimens "${fs[@]:i:1000}"; done)
  while read -r mt; do [ "$mt" -le "$up" ] || up=$mt; done < <(cd "$1" && p_mtimens "${ups[@]}" && p_ctimens "${ups[@]}")
  while IFS= read -r -d '' f && [ "$n" -lt "$SHOTS_MAX" ]; do
    read -r sz _ < <(p_stat "$f") && mt=$(p_mtimens "$f") && [ "$sz" -le "$SHOT_MAX" ] && [ "$mt" -gt "$newest" ] && [ "$mt" -ge "$up" ] || continue
    ext=$(tr '[:upper:]' '[:lower:]' <<<"${f##*.}"); [ "$ext" != jpeg ] || ext=jpg
    h=$(git hash-object -- "$f") && mkdir -p "$2/shots" && cp "$f" "$2/shots/$h.$ext" || continue
    list+=("$h.$ext" "${f#"$s"/}"); n=$((n + 1))
  done < <(find "$s" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.webp' \) -print0 | LC_ALL=C sort -z)
  [ "$n" -gt 0 ] && p=$(git hash-object -- "$2/$3.patch") || return 0
  jq -cn --arg p "$p" '{patch: $p, shots: [$ARGS.positional | range(0; length; 2) as $i | {file: .[$i], caption: .[$i + 1][0:200]}]}' --args "${list[@]}" > "$2/shots/shots.json"
}
# Whether two patch files (git diff --binary --no-renames), each made on a commit of main's, are the same change: they
# change the same files, and each file the later patch gives is the earlier patch's, brought onto the later commit by a
# three-way merge (git merge-file) with main's own change to that file between the two commits. The merge moves an edit
# only as main's change moves its lines, never to another place with the same lines around it (as git apply, which
# finds a hunk by its context, can), so an edit at another place is another change. Not the same when a patch or commit
# cannot be read, a patch does not apply to its commit, or a merge has a conflict (a binary file main changed has one).
samechange() { # <earlier patch> <the commit it was made on> <later patch> <the commit it was made on>
  local d r
  [ -s "$1" ] && [ -s "$3" ] && [ -n "$2" ] && [ -n "$4" ] && git -C "$MAIN" cat-file -e "$2^{commit}" 2>/dev/null \
    && git -C "$MAIN" cat-file -e "$4^{commit}" 2>/dev/null && d=$(mktemp -d) || return 1
  ( export GIT_LITERAL_PATHSPECS=1
    g() { git -C "$MAIN" "$@"; }
    ta=$(GIT_INDEX_FILE=$d/a g read-tree "$2" && GIT_INDEX_FILE=$d/a g apply --cached -- "$1" && GIT_INDEX_FILE=$d/a g write-tree) \
      && tb=$(GIT_INDEX_FILE=$d/b g read-tree "$4" && GIT_INDEX_FILE=$d/b g apply --cached -- "$3" && GIT_INDEX_FILE=$d/b g write-tree) \
      && [ -n "$ta" ] && [ -n "$tb" ] || exit 1
    # The same files changed (diff-tree lists them in path order).
    g diff-tree -r --name-only -z "$2" "$ta" > "$d/pa" && g diff-tree -r --name-only -z "$4" "$tb" > "$d/pb" && [ -s "$d/pa" ] \
      && cmp -s "$d/pa" "$d/pb" || exit 1
    while IFS= read -r -d '' p; do
      # Each entry is "<mode> <type> <id>", or nothing for a file the patch deletes.
      ea=$(g ls-tree "$ta" -- "$p") && eb=$(g ls-tree "$tb" -- "$p") || exit 1
      ea=${ea%%$'\t'*} eb=${eb%%$'\t'*}
      [ "$ea" != "$eb" ] || continue
      [ -n "$ea" ] && [ -n "$eb" ] && [ "${ea%% *}" = "${eb%% *}" ] || exit 1
      # Main did not change the file between the two commits: the change to it differs.
      o=$(g rev-parse -q --verify "$2:$p") t=$(g rev-parse -q --verify "$4:$p")
      [ "$o" != "$t" ] || exit 1
      { [ -z "$o" ] || g cat-file blob "$o"; } > "$d/o" && { [ -z "$t" ] || g cat-file blob "$t"; } > "$d/t" \
        && g cat-file blob "${ea##* }" > "$d/x" && g merge-file -p "$d/x" "$d/o" "$d/t" > "$d/m" 2>/dev/null \
        && [ "$(g hash-object -- "$d/m")" = "${eb##* }" ] || exit 1
    done < "$d/pa" )
  r=$?; rm -rf "$d"; return "$r"
}
# The screenshots a card kept, kept again for the card that resumed its kept patch: only when they were kept for that
# patch, and the new card's patch is the same change, brought onto its newer base (samechange()): a line added at
# another place, even one with the same lines around it, is another change. Its shots.json is tied to the new card's
# own patch.
keptshots() { # <kept folder of the earlier card> <earlier card> <kept folder> <card>
  local b
  [ -r "$1/shots/shots.json" ] && [ "$(jq -r .patch "$1/shots/shots.json" 2>/dev/null)" = "$(git hash-object -- "$1/$2.patch" 2>/dev/null)" ] \
    && samechange "$1/$2.patch" "$(cat "$1/$2.base" 2>/dev/null)" "$3/$4.patch" "$(cat "$3/$4.base" 2>/dev/null)" || return 0
  rm -rf "$3/shots"
  cp -R "$1/shots" "$3/shots" && b=$(git hash-object -- "$3/$4.patch") \
    && jq -c --arg p "$b" '.patch = $p' "$1/shots/shots.json" > "$3/shots/shots.json" || rm -rf "$3/shots"
}
# <worktree>: on a trial card (lib/modelpick.sh), puts on its pick (PICK) the pipeline files (the pack's pipelineFiles,
# or files under one: onpipeline(), lib/followups.sh) its staged change touches, as pipeline, so its lines from then on
# carry them and the Board flags the card; an eligible issue names none, so each is one the issue did not name. card()
# calls it on each pass, before the review, and block() on the change it keeps: it is here, beside block(), so a
# command that blocks a card outside card() (`retry` and `shut`, through unstick(), lib/run.sh) flags it too.
trialflag() {
  local pipe f files=()
  [ -n "${PICK:-}" ] && jq -e .trial <<<"$PICK" >/dev/null 2>&1 && packget pipelineFiles pipe || return 0
  while IFS= read -r f; do [ -z "$(onpipeline "$f" <<<"$pipe")" ] || files+=("$f"); done < <(git -C "$1" diff --cached --no-renames --name-only 2>/dev/null)
  PICK=$(jq -c 'if $ARGS.positional == [] then del(.pipeline) else .pipeline = $ARGS.positional end' --args "${files[@]}" <<<"$PICK") || :
}
clean() { tidy "$1"; rm -f "$1".out "$1".err "$1".review "$1".test "$1".withdrawn "$1".approvals "$1".spent "$1".trailers; rm -rf "$1".testlog "$1".rounds; }
# The closing line for a card that does not land. Its worktree goes, once its change is kept as a patch (a
# patch that cannot be written leaves the worktree where it is, and the reason says so); its session output, error
# output, last review, last test output, the findings of its withdrawn follow-ups, the issue body its last review read, its commit trailers, its fix rounds (repeats()) and the list of what its tests passed (tests(): a retried card keeps those passes) are moved to a folder beside the cards folder, and the line names that folder. Evidence is never deleted
# here: when the folder cannot be made or a file cannot be moved, what did not move stays where it is beside the
# worktree, the line names no folder, and its reason says where the evidence is; but a line whose patch was kept
# always names the folder, whatever did not move, so the issue's next card still starts from that patch. A card that
# stopped before any session has no evidence and names no folder.
# A card that ends blocked after a review posts that review's findings as a comment on its issue first; when the
# comment cannot be posted the reason says so (the findings are still in the kept review and the review line).
# With a fifth argument the reason is posted even when the review has no findings (a GO that needs the owner's yes), and
# so it is whenever a patch is kept (a build that failed before any review): the comment names the patch.
# A card of issue 0 (a branch that names no issue) has no issue to post on: its findings are in the review line.
# A reason's first line is the sentence (what failed, what landed): the line's reason. What follows it is the end of
# the output that failed (tests, a check, a session's errors): the line's tail, its newlines kept (line() keeps the
# last 60 lines of it), so the Board shows the sentence and the output apart. SPEEDCHECKED, when set, is the version
# of the speed check that blocks the card (SPEEDCHECK, lib/testrun.sh): the line's speedcheck. Called in card(), the
# line's waitSec is the seconds the card waited on other cards and for main to change (card()'s waitsec and mainsec),
# as on its landed line, for the drift watch (bench/drift.sh); outside card() it has none.
# A card that stops for the owner's yes to a visible change keeps the project's own screenshots of it (keepshots()),
# or, retried on the same kept patch, those of the card it resumes (keptshots()).
block() { # <card> <issue> <worktree> <reason> [post the reason on the issue whatever the review holds]
  local k=$ST/kept/$1 f kept='' left='' stay='' hold='' patch='' reason=${4%%$'\n'*} tail='' shown body d size=null sp named=null err ws=null
  [ -z "${waitsec+x}" ] || ws=$((waitsec + ${mainsec:-0}))
  # Blocked by the loop, outside card() (its process gone or stuck): the blocked line carries the card's pick too.
  local PICK=${PICK:-} PICKCARD=${PICKCARD:-}; [ "$PICKCARD" = "$1" ] || heldpick "$1"
  [[ $4 != *$'\n'* ]] || tail=$(tail -n 60 <<<"${4#*$'\n'}")
  # Its claim on its files goes first: a card waiting on them goes on now, not after the comment and the evidence.
  rm -f "$3.claim" "$3.claim.new" "$3.cpatch" "$3.cpatch.new"
  # The card's work. Not after a worktree that could not be made: a branch that did not merge leaves
  # conflict marks, and the branch itself still holds that work. A worktree whose dependencies could not be linked
  # was made: a branch card's change is merged and staged in it by then, and is kept like any other. The worktree
  # goes only when its change is known to be in the patch, or known to be nothing: a change that cannot be staged
  # (an index lock) or read stays with it.
  if [[ $reason != worktree:* || $reason == "$NODEPS"* ]] && [ -d "$3" ]; then
    git -C "$3" add -A 2>/dev/null && { git -C "$3" diff --cached --quiet 2>/dev/null; d=$?; } || d=2
    [ $d = 2 ] || size=$(diffsize "$3")
    # A trial card blocked before its review flags the pipeline files of its kept change too (trialflag(), above).
    [ $d != 1 ] || trialflag "$3"
    # The files it changed, the first 200 ("Needs you" lists them on demand; a line stays small, so the
    # snapshot reads the whole list from the kept patch while there is one).
    [ $d != 1 ] || named=$(git -C "$3" diff --cached --name-only --no-renames 2>/dev/null | head -n 200 | jq -Rcs 'split("\n") | map(select(. != "") | .[0:300])' 2>/dev/null) || named=null
    if [ $d = 1 ] && mkdir -p "$k" 2>/dev/null && git -C "$3" diff --cached --binary --no-renames > "$k/$1.patch" 2>/dev/null && git -C "$3" rev-parse HEAD > "$k/$1.base" 2>/dev/null; then
      kept=$k; patch="$k/$1.patch ($(git -C "$3" diff --cached --name-only --no-renames | wc -l) files, $((($(wc -c < "$k/$1.patch") + 1023) / 1024)) KB, built on commit $(<"$k/$1.base"))"
    elif [ $d != 0 ]; then
      rm -f "$k/$1.patch" "$k/$1.base" 2>/dev/null; stay=1
      reason="${reason:0:1100} [the card's change could not be kept as a patch in $k: its worktree is left at $3]"
    elif [ -s "$3.patch" ] && [ -s "$3.base" ]; then
      # The one rebuild left the worktree with no change (its session did nothing, or took everything back): the
      # reviewed change it was rebuilding is still the card's work, in the patch file the landing made.
      if mkdir -p "$k" 2>/dev/null && cp "$3.patch" "$k/$1.patch" 2>/dev/null && cp "$3.base" "$k/$1.base" 2>/dev/null; then
        kept=$k; patch="$k/$1.patch ($(git apply --numstat "$k/$1.patch" 2>/dev/null | wc -l) files, $((($(wc -c < "$k/$1.patch") + 1023) / 1024)) KB, built on commit $(<"$k/$1.base"); the reviewed change from before the rebuild, which left no change of its own)"
      else
        rm -f "$k/$1.patch" "$k/$1.base" 2>/dev/null; hold=1
        reason="${reason:0:1100} [the reviewed change from before the rebuild could not be kept as a patch in $k: it is left at $3.patch]"
      fi
    fi
  fi
  # The screenshots go only with a patch of the staged change (d 1): they are tied to that patch.
  [[ $reason != "$YES"* ]] || [ "$d" != 1 ] || [ -z "$kept" ] || keepshots "$3" "$k" "$1"
  # A retried card (card()'s from and fromk: the card whose kept patch it applied) whose worktree has no screenshots
  # (the project's run wrote them in the old worktree, not in the patch) keeps that card's, while its change is still
  # that patch (keptshots()).
  [[ $reason != "$YES"* ]] || [ "$d" != 1 ] || [ -z "$kept" ] || [ -e "$k/shots" ] || [ -z "${from:-}" ] || [ -z "${fromk:-}" ] \
    || keptshots "$fromk" "$from" "$k" "$1"
  f=$(grep -Ev "$UNRECORDED" "$3.review" 2>/dev/null)
  # The comment is one argument, and an issue comment at most 65536 characters, beside up to 60000 of findings: it
  # shows the output's last whole lines within 4000 characters (the blocked line keeps all 60).
  shown=$tail; [ ${#shown} -le 4000 ] || { shown=${shown: -4000}; [[ $shown != *$'\n'* ]] || shown=${shown#*$'\n'}; }
  body="Conveyor card $1 is blocked: ${reason:0:600}"; [ -z "$tail" ] || body+=$'\n\n```\n'"$shown"$'\n```'
  [ -z "$f" ] || body+=$'\n\n'"Findings of its last review:"$'\n'"${f:0:60000}"
  [ -z "$patch" ] || body+=$'\n\n'"Its work is kept as a patch: $patch. \`conveyor.sh retry $2\` starts the next card from it: applied as it is while it still applies to main, brought onto main by a session when it does not."
  [ -z "$f${5:-}$patch" ] || [ "$2" = 0 ] || err=$(gh_write issue comment "$2" --body "$body" 2>&1 >/dev/null) || if [ $? = 3 ]; then
    reason="${reason:0:1100} [$([ -n "$f" ] && echo "the review's findings" || echo this) not posted on the issue: ${err:0:600}]"
  else reason="${reason:0:1100} [$([ -n "$f" ] && echo "the review's findings" || echo this) could not be posted on the issue]"; fi
  # covered: the COVERED-BY lines of its replies (hollowproof()), which a retry that lands its kept patch is checked on.
  for f in out err review test testlog withdrawn approvals body trailers rounds rerun covered; do
    [ -e "$3.$f" ] || continue
    if mkdir -p "$k" 2>/dev/null && mv -f "$3.$f" "$k/" 2>/dev/null; then kept=$k; else left=1; fi
  done
  [ -z "$left" ] || { [ -n "$patch" ] || kept=''; reason="${reason:0:1200} [evidence not moved to $k: it is still at $3.out, .err, .review, .test, .testlog, .withdrawn, .body, .trailers, .rounds, .rerun, .covered]"; }
  if [ -n "$hold" ]; then git worktree remove --force "$3" 2>/dev/null; rm -f "$3".events "$3".firsttry "$3".firsttry.new "$3".index "$3".msg "$3".review.new "$3".carried "$3".live "$3".live.tmp "$3".idle "$3".claim "$3".claim.new "$3".cpatch "$3".cpatch.new "$3".stack "$3".settings "$3".opencode.json "$3".donewhen "$3".unfixed "$3".stalled "$3".before
  elif [ -z "$stay" ]; then tidy "$3"; else rm -f "$3".events "$3".firsttry "$3".firsttry.new "$3".patch "$3".index "$3".msg "$3".review.new "$3".carried "$3".base "$3".live "$3".live.tmp "$3".idle "$3".claim "$3".claim.new "$3".cpatch "$3".cpatch.new "$3".stack "$3".settings "$3".opencode.json "$3".donewhen "$3".unfixed "$3".stalled "$3".before; fi
  # The session or review that failed: what it spent is on this line (spent, and its tokens), so it is priced.
  sp=$(jq -ce 'objects' "$3.spent" 2>/dev/null) || sp=null; rm -f "$3.spent"
  reading fresh >/dev/null 2>&1
  # The tail comes on stdin: it can be more than one argument can hold.
  record "$1" "$2" blocked blocked "$(printf '%s' "$tail" | jq -cRs --arg r "$reason" --arg k "${kept:+kept/$1}" --argjson d "$size" --argjson e "$(ending)" --argjson sp "$sp" --argjson p "${named:-null}" --arg sc "${SPEEDCHECKED:-}" --argjson ws "$ws" '. as $t | {reason:$r,kept:$k} + (if $t == "" then {} else {tail: $t} end)
    + (if $sc == "" then {} else {speedcheck: ($sc | tonumber)} end) + (if $ws == null then {} else {waitSec: $ws} end) + (if $d == null then {} else {diff: $d} end) + (if $p == null then {} else {paths: $p} end) + $e
    + (if $sp == null then {} else {spent: $sp, tokens: {claude: ($sp.tokens.claude // 0), codex: ($sp.tokens.codex // 0)}} end)
    + (if ($sp.stalls // 0) > 0 then {stalls: $sp.stalls} else {} end)')"
}
