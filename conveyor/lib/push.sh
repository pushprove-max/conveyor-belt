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
# (slot_first), on the slot's core (slot_mine) and in its box (slot_box): a machine full of test runs gives the
# project's pre-push checks a test unit's share, not a sliver of what is left (the owner, 2026-11-15). A loop started
# on a slot it holds already (CONVEYOR_TEST_SLOT: a loop an engine case runs) pushes on that one, as its tests run. When
# it works the commit, the remote and the branch are written to $PUSHED; when it fails, a push line under the given card (the last one landed)
# holds the commit, the end of what git and the hook said, and why it failed (kind: check or transport; a check
# failure names the check: the word after the last "FAILED" the hook printed, else the pre-push hook). The worktree goes either way; nothing but this
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
  local wt=$CARDS/push sha out rc=0 a c n s t state round=0 before=() got=() pend=() rest=() took=$SECONDS try m want=${3:-}; local -A said=()
  for a in "$(pushed)" "refs/remotes/$REMOTE/$BRANCH"; do
    [ -z "$a" ] || ! a=$(git rev-parse -q --verify "$a^{commit}" 2>/dev/null) || before+=("$a")
  done
  for try in 1 2; do
    rm -f "$wt.trace"
    rc=0; sha=$(git rev-parse "${want:-refs/heads/$BRANCH}" 2>&1) && pushing "$sha" && out=$({
      git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt"; git worktree prune
      packget push.env e && mapfile -d '' -t e < <(jq -j 'to_entries[] | "\(.key)=\(.value)\u0000"' <<<"$e") \
        && git worktree add -q --detach "$wt" "$sha" && deps "$wt" && cd "$wt" \
        && slot_pool && slot_box && { [ -n "$SLOT_HOME" ] || { slot_first && slot_mine; }; } \
        && "${SLOT_BOX[@]}" env "${e[@]}" GIT_TRACE2_EVENT="$wt.trace" timeout --kill-after=30 "$PUSH_TIMEOUT" git push "$REMOTE" "$sha:refs/heads/$BRANCH"
    } 2>&1 < /dev/null 8>&-) && echo "$sha $REMOTE $BRANCH" > "$PUSHED" || rc=$?
    # The remote refused the push (git's "[rejected]": its main holds a commit this one lacks): main takes the
    # remote's commits in a merge commit and is pushed again, once, in this same turn. The worktree stays until they
    # are fetched: the fetch is made from it, as the push was.
    [ $rc != 0 ] && [ $try = 1 ] && grep -qF '[rejected]' <<<"$out"; a=$?
    [ $a != 0 ] || [ -z "$want" ] || { out+=$'\n'"$REMOTE/$BRANCH holds a commit ${sha:0:12} lacks: a merge with it is a commit the full test run did not test, so nothing is pushed"; a=1; }
    [ $a != 0 ] || m=$(theirs "$sha" "$wt") || { out+=$'\n'"the remote's commits were not merged into main: ${m:0:600}"; a=1; }
    git worktree remove --force "$wt" 2>/dev/null
    [ $a = 0 ] || break
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
  mapfile -t got < <(jq -rs --rawfile in <(git rev-list "$sha" --not "${before[@]}" 2>/dev/null) '($in | split("\n") | map(select(. != "")) | INDEX(.)) as $in
    | map(select(.step == "pushed") | .card) as $have | .[] | select(.step == "landed" and $in[.sha] and (.card | IN($have[]) | not)) | "\(.card) \(.issue) \(.sha)"' < <(stdb ask lines cards))
  for a in "${got[@]}"; do read -r c n s <<<"$a"; record "$c" "$n" pushed ok "{\"sha\":\"$s\",\"sec\":$took,\"head\":\"$sha\"}"; done
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
  err=$(export GIT_INDEX_FILE="$f.index"; git hook run --ignore-missing pre-commit 2>&1 && git hook run --ignore-missing commit-msg -- "$f.msg" 2>&1) || { echo "commit of the merge refused: ${err:0:600}"; return 1; }
  [ "$(GIT_INDEX_FILE="$f.index" git write-tree)" = "$t" ] || { echo "main's hooks changed what the merge would commit; it needs $OWNER"; return 1; }
  m=$(git commit-tree "$t" -p "$1" -p "$x" -F "$f.msg" 2>&1) || { echo "cannot make the merge commit: $m"; return 1; }
  git diff --quiet "$1" "$m" || err=$(git diff --binary --no-renames "$1" "$m" | git apply --index 2>&1) || { echo "the merge does not apply to main's checkout: $err"; return 1; }
  git update-ref -m "conveyor merge of $REMOTE/$BRANCH" "refs/heads/$BRANCH" "$m" "$1" || { echo "main moved during the merge; its change is left in main's checkout for $OWNER to sort out"; return 1; }
  echo "$m"
}
# The push in progress, for health to read: this push job's pid, when it began and the commit it pushes. The
# loop clears it when the job ends; one left by a loop that was killed names a pid that is gone, and health ignores it.
# The commit of the last push that worked, when it went to the pack's remote and branch: a push to another one
# says nothing of what this one holds.
pushed() { local s r b; read -r s r b 2>/dev/null < "$PUSHED" && [ "$r" = "$REMOTE" ] && [ "$b" = "$BRANCH" ] && echo "$s"; }
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
# moves (a fix lands), for the check fails the same way on the same commit.
checkheld() {
  local tip
  tip=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") || return 1
  turncards 2>/dev/null | jq -Rne --arg s "$tip" 'last(inputs | fromjson? | objects | select(.step == "push")) | .result == "fail" and .kind == "check" and .sha == $s' >/dev/null 2>&1
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
# The push that is owed, as "<card> <issue> <sha>" of the last landing: its commit is in main and not at origin.
# None while the control record's rule "Push when a card lands" is off (rules.push: land only): the landed commits
# wait for the Board's Push landed (fulltest()) or Push now (pushnow()). A record that does not read keeps the push on.
owed() {
  local o
  [ "$(ctl 2>/dev/null | jq -r '.rules.push')" != false ] || return 1
  o=$(stdb ask lines cards 2>/dev/null | jq -r 'select(.step == "landed") | "\(.card) \(.issue) \(.sha)"' 2>/dev/null); o=${o##*$'\n'}
  [ -n "$o" ] && git merge-base --is-ancestor "${o##* }" "refs/heads/$BRANCH" 2>/dev/null && ! atorigin "${o##* }" && echo "$o"
}

tidy() { git worktree remove --force "$1" 2>/dev/null; rm -f "$1".events "$1".firsttry "$1".firsttry.new "$1".patch "$1".index "$1".msg "$1".review.new "$1".carried "$1".base "$1".live "$1".live.tmp "$1".idle "$1".claim "$1".claim.new "$1".cpatch "$1".cpatch.new "$1".stack "$1".settings "$1".opencode.json "$1".donewhen "$1".unfixed "$1".covered "$1".stalled "$1".ready "$1".ready.new "$1".batch "$1".batch.new "$1".bpatch "$1".lent "$1".batchtest "$1".batchfirst "$1".first "$1".rerun "$1".rerun.new "$1".whole "$1".passed "$1".bpass "$1".times "$1".reported "$1".report "$1".slow "$1".timed "$1".cpus "$1".clocks; rm -rf "$1".rv "$1".batchtestlog; }
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
# of the speed check that blocks the card (SPEEDCHECK, lib/testrun.sh): the line's speedcheck.
block() { # <card> <issue> <worktree> <reason> [post the reason on the issue whatever the review holds]
  local k=$ST/kept/$1 f kept='' left='' stay='' hold='' patch='' reason=${4%%$'\n'*} tail='' shown body d size=null sp named=null err
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
  for f in out err review test testlog withdrawn approvals body trailers rounds rerun; do
    [ -e "$3.$f" ] || continue
    if mkdir -p "$k" 2>/dev/null && mv -f "$3.$f" "$k/" 2>/dev/null; then kept=$k; else left=1; fi
  done
  [ -z "$left" ] || { [ -n "$patch" ] || kept=''; reason="${reason:0:1200} [evidence not moved to $k: it is still at $3.out, .err, .review, .test, .testlog, .withdrawn, .body, .trailers, .rounds, .rerun]"; }
  if [ -n "$hold" ]; then git worktree remove --force "$3" 2>/dev/null; rm -f "$3".events "$3".firsttry "$3".firsttry.new "$3".index "$3".msg "$3".review.new "$3".carried "$3".live "$3".live.tmp "$3".idle "$3".claim "$3".claim.new "$3".cpatch "$3".cpatch.new "$3".stack "$3".settings "$3".opencode.json "$3".donewhen "$3".unfixed "$3".covered "$3".stalled
  elif [ -z "$stay" ]; then tidy "$3"; else rm -f "$3".events "$3".firsttry "$3".firsttry.new "$3".patch "$3".index "$3".msg "$3".review.new "$3".carried "$3".base "$3".live "$3".live.tmp "$3".idle "$3".claim "$3".claim.new "$3".cpatch "$3".cpatch.new "$3".stack "$3".settings "$3".opencode.json "$3".donewhen "$3".unfixed "$3".covered "$3".stalled; fi
  # The session or review that failed: what it spent is on this line (spent, and its tokens), so it is priced.
  sp=$(jq -ce 'objects' "$3.spent" 2>/dev/null) || sp=null; rm -f "$3.spent"
  reading fresh >/dev/null 2>&1
  # The tail comes on stdin: it can be more than one argument can hold.
  record "$1" "$2" blocked blocked "$(printf '%s' "$tail" | jq -cRs --arg r "$reason" --arg k "${kept:+kept/$1}" --argjson d "$size" --argjson e "$(ending)" --argjson sp "$sp" --argjson p "${named:-null}" --arg sc "${SPEEDCHECKED:-}" '. as $t | {reason:$r,kept:$k} + (if $t == "" then {} else {tail: $t} end)
    + (if $sc == "" then {} else {speedcheck: ($sc | tonumber)} end) + (if $d == null then {} else {diff: $d} end) + (if $p == null then {} else {paths: $p} end) + $e
    + (if $sp == null then {} else {spent: $sp, tokens: {claude: ($sp.tokens.claude // 0), codex: ($sp.tokens.codex // 0)}} end)
    + (if ($sp.stalls // 0) > 0 then {stalls: $sp.stalls} else {} end)')"
}
