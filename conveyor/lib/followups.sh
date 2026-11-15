# SPDX-License-Identifier: Apache-2.0
# The last review said NO-GO: each of its finding lines becomes its own issue, filed before the card lands; a line
# the review repeats word for word is filed once. Prints the new issue numbers as a JSON array. When a filing fails
# it prints the reason instead, and withdraws (closes) the ones it had already filed: the card will not land, and an
# open follow-up would be built against a main that never got its parent's change.
# A withdrawn follow-up is closed as "not planned", never "completed": nothing fixed its finding. The finding
# goes to <worktree>.withdrawn, in the order filed (the review's finding lines, as followups() reads them), and from
# the kept folder into the brief of the issue's next card; the comment names that issue.
# A card whose issue is itself a follow-up (it has the pack's follow-up label, or its body holds a depth line) files
# none, so no follow-up has one of its own: its last review's findings go to the declined list when it lands, declined
# by code as "follow-up of a follow-up"; when they cannot be written there the card ends blocked, landed, its review kept.
# A finding that names one of the pack's pipelineFiles (how the engine builds, reviews, fixes, tests, lands or
# pushes), or a file under one (onpipeline()), is filed held: the control record holds its issue, as `control hold` does, before the card lands,
# so it is never built until the owner releases it. Its body holds one more line, "Cost to every card:", which reads
# "not assessed": nothing here assesses it. The snapshot lists it in Needs you (pipeline) while it is held.
# The whole test on main (the pack's test.main; a pack that names none has none): a card's test step runs only the
# tests of what the card touched, so the whole test is run here instead, by `serve` beside its cards and never by a
# card: no card waits on it. A run is due when main is at another commit than the last run's and the last try began
# MAIN_TEST_EVERY seconds ago or more; one runs at a time (a lock: a loop that restarts on new code leaves the run of
# the loop before it going). It runs as a card's test step does (tests(): one of the machine's test slots, the
# timeout, its output and logs), in a worktree of that commit alone, $CARDS/maintest/wt.
# $MAINTEST keeps {sha: the commit of the last run that ended, at: when the last try began, pass: the last commit that
# passed, fail: null, or {issue, cases, from: the last pass, to: the commit that failed, since, exit} of the failure
# that stands, filed: [{issue, cases}], the issue last filed for each set of failing cases}; the snapshot gives fail
# to the Board's Needs you (mainTest) until a run passes. The commit is kept only once its run has ended and, when it
# failed, its issue was filed or added to: a try whose worktree or test slots could not be made, or that was killed,
# tested nothing, and a failure GitHub did not take reached no one, so the same commit is tried again an hour on.
# A failure files one issue of the pack's second priority (its last, when it has one) that names the failing cases
# (testfails(); "<file>: <case>", or the case alone when the run's logs name no file: a case of the same name in
# another file is another case, with its own issue) and the commits since the last pass. A failure
# of the same cases while the issue filed for them is open adds a comment to it, with the commits up to the new one,
# and files none, whatever failed in the runs between; one whose issue GitHub says nothing of writes nothing, and
# keeps the issue (and, as any failure not written, is tried again).
MAIN_TEST_EVERY=3600
mainput() { printf '%s\n' "$1" > "$MAINTEST.new" && mv -f "$MAINTEST.new" "$MAINTEST" || { rm -f "$MAINTEST.new"; return 1; }; } # <the record>
maintest() {
  local cmd sha was at wt=$CARDS/maintest/wt lock rc out f cases pass n state='' prio title body told=true
  packget test.main cmd && [ -n "$cmd" ] || return 0
  mkdir -p "${wt%/*}" && { exec {lock}>>"$MAINTEST.lock"; } 2>/dev/null && flock -n "$lock" || return 0
  sha=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") && at=$(clock) || return 0
  was=$(jq -ce 'objects' "$MAINTEST" 2>/dev/null) || was='{}'
  jq -e --arg s "$sha" --arg at "$at" --argjson e "$MAIN_TEST_EVERY" \
    '.sha != $s and ((.at | type) != "string" or ($at | fromdate) - (.at | fromdate) >= $e)' <<<"$was" >/dev/null || return 0
  was=$(jq -c --arg at "$at" '. + {at: $at}' <<<"$was") && mainput "$was" || return 1
  out=$({ git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt" "$wt.test" "$wt.testlog"; git worktree prune
    git worktree add -q --detach "$wt" "$sha" && deps "$wt"; } 2>&1 < /dev/null) \
    || { echo "conveyor: the whole test on main did not run: its worktree could not be made: $out" >&2; return 1; }
  out=$(slot_pool 2>&1) || { echo "conveyor: the whole test on main did not run: $out" >&2; return 1; }
  tests "$wt" test.main; rc=$?
  if [ $rc = 0 ]; then
    git worktree remove --force "$wt" 2>/dev/null
    mainput "$(jq -c --arg s "$sha" '. + {sha: $s, pass: $s, fail: null}' <<<"$was")"; return
  fi
  f=$(testfails "$wt.test" "$rc" test.main) || f='{"files":[]}'
  git worktree remove --force "$wt" 2>/dev/null
  cases=$(jq -c --arg cmd "$cmd" '[.files[] | .file as $f | .cases[] | if $f == $cmd or $f == "" then .name else "\($f): \(.name)" end] | unique' <<<"$f") || cases='[]'
  pass=$(jq -r '.pass // ""' <<<"$was"); git rev-parse -q --verify "$pass^{commit}" >/dev/null 2>&1 || pass=''
  n=$(jq -r --argjson c "$cases" '[.filed | arrays | .[] | select(.cases == $c) | .issue][-1] // empty' <<<"$was")
  [ -z "$n" ] || state=$(timeout 20 gh issue view "$n" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null) || state=''
  body="The whole test on main (the pack's test.main) failed$([ "$state" != OPEN ] || echo " again, with the same cases,") at ${sha:0:12} (exit $rc; 124 is the ${TEST_TIMEOUT}s timeout).

Failing cases:
$(jq -r 'if . == [] then "the run named none" else .[] | "- " + . end' <<<"$cases")

$(if [ -n "$pass" ]; then echo "Commits since the last pass (${pass:0:12}..${sha:0:12}):"; git log --format='- %h %s' "$pass..$sha" | head -n 50
  else echo "No pass of it is recorded here yet: main is at ${sha:0:12}."; fi)"
  if [ "$state" = OPEN ]; then
    gh_write issue comment "$n" --body "$body" >/dev/null 2>&1 || { told=false; echo "conveyor: the whole test on main failed again; no comment could be added to #$n" >&2; }
  elif [ -z "$n" ] || [ "$state" = CLOSED ]; then
    prio=$(jq -r '.[[1, length - 1] | min]' <<<"$PRIOS")
    title=$(jq -r --arg s "${sha:0:12}" '"The whole test fails on main" + (if . == [] then " at " + $s
      else ": " + (.[:3] | join(", ")) + (if length > 3 then " and \(length - 3) more" else "" end) end) | .[0:200]' <<<"$cases")
    n=$(gh_write issue create --title "$title" --label "$TYPE" --label "$prio" --body "$body" 2>&1 | grep -oE '/issues/[0-9]+' | tail -n 1); n=${n##*/}
    [ -n "$n" ] || { told=false; echo "conveyor: the whole test on main failed; its issue could not be filed" >&2; }
  else
    told=false; echo "conveyor: the whole test on main failed again; the state of #$n could not be read" >&2
  fi
  mainput "$(jq -c --argjson c "$cases" --argjson n "${n:-null}" --arg p "$pass" --arg s "$sha" --arg at "$at" --argjson rc "$rc" --argjson told "$told" \
    '([.fail | objects | select(.cases == $c) | .since][0]) as $since
     | . + (if $told then {sha: $s} else {} end) + {fail: {issue: $n, cases: $c, from: (if $p == "" then null else $p end), to: $s, since: ($since // $at), exit: $rc}}
     | if $n == null then . else .filed = [.filed | arrays | .[] | select(.cases != $c)] + [{issue: $n, cases: $c}] end' <<<"$was")"
}

leftovers() { grep -Ev "$NOTFINDING" "$1" 2>/dev/null | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk '!seen[$0]++'; } # <review file>: its finding lines, each once
decline() { # <card> <issue> <why>, the findings on stdin, one a line: each to the declined list (declined()), by code
  local f
  while IFS= read -r f; do
    [ -z "$f" ] || declined "$1" "$2" code "$3" "$f" \
      || { echo "conveyor: card $1: its declined findings could not be written to $DECLINED" >&2; return 1; }
  done
}
# <finding>, the pack's pipelineFiles on stdin: prints 1 when the finding names one of them, or a file under one. Each
# path is read as git would: "." parts and doubled slashes dropped, ".." taking the part before it, so another
# spelling of a listed file is that file, and a longer name that starts with one (a.sh.bak) is not. A name may hold
# spaces: every run of words between the finding's other separators is a candidate.
onpipeline() {
  jq -r --arg f "$1" 'def norm: reduce (split("/")[] | select(. != "" and . != ".")) as $s ([]; if $s == ".." and length > 0 and .[-1] != ".." then .[:-1] else . + [$s] end) | join("/");
    map(norm) as $e | [$f | scan("[^\\]\\[:,;()\u0027\"`<>]+") | [splits("\\s+") | select(. != "")] as $w
      | range(0; $w | length) as $i | range($i + 1; ($w | length) + 1) as $j | $w[$i:$j] | join(" ") | sub("\\.+$"; "") | norm]
    | if any(. as $p | $e | any(. as $x | $x == "" or $p == $x or ($p | startswith($x + "/")))) then "1" else "" end'
}
unfile() { # <parent issue> <review file> <follow-up issue>...
  local n=$1 r=$2 i j=0 found=(); shift 2
  mapfile -t found < <(leftovers "$r")
  for i; do
    gh_write issue close "$i" --reason "not planned" --comment "Conveyor: the card this follows up did not land; withdrawn. The next build of #$n carries this finding in its brief." >/dev/null 2>&1
    printf '#%s %s\n' "$i" "${found[j]:-}" >> "${r%.review}.withdrawn"; j=$((j + 1))
  done
}
followups() { # <card> <issue json> <review file>
  local f mark where out num n nums=() more=() found=() pipe cost
  packget pipelineFiles pipe || { echo "cannot read the pack's pipeline files"; return 1; }
  n=$(jq -r .number <<<"$2") && mapfile -t more < <(jq -r --arg p "$AREA" '(.labels | map(.name | select(startswith($p))) | .[0] // empty | "--label", .),
    (.milestone.title // empty | "--milestone", .)' <<<"$2") || { echo "cannot read the parent issue's labels and milestone"; return 1; }
  mapfile -t found < <(leftovers "$3")
  [ ${#found[@]} != 0 ] || { echo "the last review said NO-GO and named no finding to file"; return 1; }
  for f in "${found[@]}"; do
    # The finding's level, P0 to P3 (P1 when it names none), is the pack's priority at that place, or its last one.
    # A P3 finding in a pack of fewer than four priorities gets none of them: the engine reads an issue with none as P3
    # (LEVEL), and the pack's last one would file it at a higher level. Bug: P3 follow-ups were filed as P2.
    mark=$(grep -oE '\[P[0-3]\]' <<<"$f" | head -n 1 | tr -d '[]P'); where=$(grep -oE '[^[:space:]]+:[0-9]+' <<<"$f" | head -n 1)
    mark=$(jq -r --argjson i "${mark:-1}" 'if $i == 3 and length < 4 then "" else .[[$i, length - 1] | min] end' <<<"$PRIOS")
    cost=$(onpipeline "$f" <<<"$pipe") || { unfile "$n" "$3" "${nums[@]}"; echo "cannot tell whether a finding names a pipeline file, so nothing landed (finding: ${f:0:200})"; return 1; }
    cost=${cost:+$'\nCost to every card: not assessed'}
    out=$(gh_write issue create --title "${f:0:200}" --label "$FOLLOWUP" --label "$TYPE" ${mark:+--label "$mark"} "${more[@]}" \
      --body "Follow-up to #$n (Conveyor card $1). The last review of that card said NO-GO. The card landed without a fix for the finding below. Fix it in this issue.

Finding: $f
Where: ${where:-the finding names no file:line}$cost
Follow-up depth: 1" 2>&1) && num=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && num=${num##*/} && [ -n "$num" ] \
      || { unfile "$n" "$3" "${nums[@]}"; echo "follow-up not filed, so nothing landed (finding: ${f:0:200}): ${out:0:400}"; return 1; }
    nums+=("$num")
    [ -z "$cost" ] || out=$(locked control hold "$num" 2>&1 >/dev/null) \
      || { unfile "$n" "$3" "${nums[@]}"; echo "a follow-up that changes a pipeline file could not be held, so nothing landed (finding: ${f:0:200}): ${out:0:400}"; return 1; }
  done
  jq -cn '$ARGS.positional | map(tonumber)' --args "${nums[@]}"
}

# A finding that is not built goes to the declined list (DECLINED), once: declined again for the same card (the
# reviewer raised it again in a later round), it is the line it has (id names the card and the finding). The
# review's judge (judged()) and `conveyor.sh declined add` are its callers. The finding and the reason are each one line. Bug: a declined finding left no trace, and the next review raised it again.
declined() { # <card> <issue> <code | judge | owner> <why> <finding>
  local id l
  [ $# = 5 ] && [[ $2 =~ ^[0-9]+$ && $3 =~ ^(code|judge|owner)$ && $1 == *[![:space:]]* && $4 == *[![:space:]]* && $5 == *[![:space:]]* ]] \
    || { echo "usage: conveyor.sh declined add <card> <issue> <code | judge | owner> <why> <finding>" >&2; return 2; }
  l=$(jq -cn --arg t "$(clock)" --arg c "$1" --argjson n "$2" --arg by "$3" --arg why "$4" --arg f "$5" --arg repo "$REPO" \
    'def one: gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; ""); {time: $t, card: $c, issue: $n, finding: ($f | one), by: $by, why: ($why | one), repo: $repo}') \
    && id=d$(jq -j '.card, "\n", .finding' <<<"$l" | git hash-object --stdin | cut -c1-12) && [ ${#id} = 13 ] || return 1
  ( flock 9 || exit 1
    ! stdb ask lines declined 2>/dev/null | grep -F "{\"id\":\"$id\"," >/dev/null || exit 0
    jq -c --arg id "$id" '{id: $id} + .' <<<"$l" | stdb append declined ) 9>>"$DECLINED.lock"
}
# "File as issue" on the Board's Declined panel: the owner wants a declined finding built after all. It is filed as an
# ordinary issue that names the finding (no follow-up label: it is picked as any new issue is), and its line keeps the
# issue's number (built), so a second ask files nothing and the reviewer is no longer told not to raise it
# (donotraise()). The list's lock is held from the reading of the line to its mark: two asks at once file one issue.
# While the finding's source issue is open (its card has not landed, so the code the finding is about is only in that
# card's change), the body ends with `Depends on: #<source>` (DEPS, prompts.sh): the new issue waits until the source
# lands. Bug: built on main at once, its card found nothing to change and was blocked. A source whose state cannot be
# read is waited on too (waiting on a closed issue costs nothing; building too early costs a blocked card); only a
# closed one gets no such line.
declinedbuild() { # <id>
  ( flock 9 || exit 1
    l=$(stdb ask lines declined 2>/dev/null | jq -c --arg id "$1" 'select(.id == $id)' 2>/dev/null | head -n 1)
    [ -n "$l" ] || { echo "conveyor: the declined list has no line $1; nothing filed" >&2; exit 2; }
    num=$(jq -r '.built // empty' <<<"$l"); [ -z "$num" ] || { echo "conveyor: this finding is already filed as #$num; nothing filed"; exit 0; }
    src=$(jq -r '.issue' <<<"$l")
    state=$(timeout 20 gh issue view "$src" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null) || state=''
    out=$(gh_write issue create --title "$(jq -r '.finding[0:200]' <<<"$l")" --body "$(jq -r --arg dep "$([ "$state" = CLOSED ] || echo "Depends on: #$src")" \
      '"Conveyor declined this review finding. Then the owner asked on the Board to build it.\n\nFinding: \(.finding)\nFrom: Conveyor card \(.card), issue #\(.issue)\nWho declined it: \(.by)\nThe reason to decline it: \(.why)" + if $dep == "" then "" else "\n\n" + $dep end' <<<"$l")" 2>&1) \
      && num=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && num=${num##*/} && [ -n "$num" ] || { echo "conveyor: the issue was not filed: ${out:0:400}" >&2; exit 1; }
    stdb ask lines declined | jq -c --arg id "$1" --argjson n "$num" 'if .id == $id then .built = $n else . end' > "$DECLINED.new" \
      && stdb rewrite declined < "$DECLINED.new" && rm -f "$DECLINED.new" \
      || { rm -f "$DECLINED.new"; echo "conveyor: the finding is filed as #$num, but its line in the declined list could not be marked" >&2; exit 1; }
    echo "conveyor: the finding is filed as #$num" ) 9>>"$DECLINED.lock"
}
# "Dismiss" and "Dismiss all shown" on the Board's Declined panel: each line named is marked dismissed, {time, by: who
# dismissed it, "the host" unless --by names them}, and leaves the panel (snapshot: declined). It stays in the list:
# the reviewer is still told not to raise it (donotraise()) and the panel's "Show every line" shows it. A line dismissed
# already keeps its first dismissal. An id the list does not have changes nothing (exit 2).
declineddismiss() { # [--by <who>] <id>...
  local by="the host"
  [ "${1:-}" != --by ] || { by=${2:-}; shift 2 || set --; }
  [ $# -ge 1 ] && [[ $by == *[![:space:]]* && $by != *$'\n'* ]] \
    || { echo "usage: conveyor.sh declined dismiss [--by <who>] <id>..." >&2; return 2; }
  ( flock 9 || exit 1
    miss=$(stdb ask lines declined 2>/dev/null | jq -rn '[inputs | objects | .id] as $have | $ARGS.positional - $have | join(" ")' --args "$@" 2>/dev/null) || miss="$*"
    [ -z "$miss" ] || { echo "conveyor: the declined list has no line $miss; nothing dismissed" >&2; exit 2; }
    stdb ask lines declined | jq -c --arg t "$(clock)" --arg by "$by" 'if type == "object" and (.id | IN($ARGS.positional[])) and .dismissed == null then .dismissed = {time: $t, by: $by} else . end' \
      --args "$@" > "$DECLINED.new" && stdb rewrite declined < "$DECLINED.new" && rm -f "$DECLINED.new" \
      || { rm -f "$DECLINED.new"; echo "conveyor: the declined list could not be written; nothing dismissed" >&2; exit 1; }
    echo "conveyor: dismissed $# line(s) of the declined list" ) 9>>"$DECLINED.lock"
}
# What a review of a change is told not to raise, after its instructions: the project's stated limits (the section of
# the checkout's README.md headed `## Accepted limits`, to the next heading of level one or two; its first 4000
# characters) and the last 20 declined findings the owner has not asked to be built, each with its reason. Nothing
# when the project has neither.
donotraise() {
  local lim dec
  lim=$(awk '/^##? / { on = ($0 ~ /^## +Accepted limits[[:space:]]*$/); next } on' "$MAIN/README.md" 2>/dev/null | sed '/[^[:space:]]/,$!d' | head -c 4000)
  dec=$(stdb ask lines declined 2>/dev/null | jq -r 'select(.built == null) | "- \(.why) (the finding: \(.finding[0:300]))"' 2>/dev/null | tail -n 20)
  [ -n "$lim$dec" ] || return 0
  printf '\n\n# Do not raise these\nA problem named here is no finding and is not written on any line of the review.'
  [ -z "$lim" ] || printf "\nThe project's stated limits (its README's accepted limits):\n%s" "$lim"
  [ -z "$dec" ] || printf '\nFindings of earlier reviews that were declined, each as its reason, then the finding. Raise no finding one of these reasons declines:\n%s' "$dec"
}

# No follow-up issue (the pack's labels.followup) marked with one of its first two priorities is waiting: exit 0.
# Otherwise exit 1 and list them. Waiting is open on
# GitHub with no landed line here: a landed follow-up stays open on GitHub until its commit is pushed. An answer
# that cannot be had (gh, or a record that does not check) is exit 1 too.
pushable() {
  local issues waiting
  check && issues=$(openissues number,title,labels --label "$FOLLOWUP") || return 1
  waiting=$(jq -r --slurpfile cards <(recs) --arg fu "$FOLLOWUP" --argjson prio "$PRIOS" '($cards | map(select(.step == "landed") | .issue)) as $landed
    | sort_by(.number)[] | (.labels | map(.name)) as $l | ([$prio[:2][] | select(IN($l[]))] | first) as $p
    | select(($l | index($fu)) and $p and (.number | IN($landed[]) | not)) | "#\(.number) \($p) \(.title)"' <<<"$issues") || return 1
  [ -z "$waiting" ] || { echo "conveyor: not pushable; these follow-ups are waiting to be built:"; echo "$waiting"; return 1; }
}

# One clear answer or none: every verdict line says the same (a review may repeat its verdict), and the last line is
# that verdict; a GO beside an open finding is a NO-GO. Prints "GO", "NO-GO" or "none".
verdict() { # <review file>
  [ "$(grep '^VERDICT:' "$1" | sort -u | wc -l)" -eq 1 ] || { echo none; return; }
  case $(tail -n 1 "$1") in
    'VERDICT: GO') if grep -Evq "$NOTFINDING" "$1"; then echo NO-GO; else echo GO; fi ;;
    'VERDICT: NO-GO') echo NO-GO ;;
    *) echo none ;;
  esac
}

# The review's answer to "would a customer or staff member see or do anything differently": prints "no" or
# "yes: <the reviewer's sentence>", or nothing when the review does not hold exactly one such line, written as asked.
# A review held to a section approved before the build answers "matches" or "differs: <how>" instead: with
# held, only those two are an answer; with any, all four are (a kept review, whichever it was).
visible() { # <review file> [held | any]
  local f='no|yes: .*[^[:space:]].*'
  [ "${2:-}" != held ] || f='matches|differs: .*[^[:space:]].*'
  [ "${2:-}" != any ] || f="$f|matches|differs: .*[^[:space:]].*"
  [ "$(grep -c '^USER-VISIBLE:' "$1")" = 1 ] || return 0
  grep -E "^USER-VISIBLE: ($f)\$" "$1" | sed 's/^USER-VISIBLE: //'
}

# The session left no change. If its reply ends with an ALREADY-DONE line and the worktree is untouched, one review
# confirms that main already does what the issue asks, and on its GO the issue is closed with that line and the
# card's closing line is `closed`. Anything else blocks the card with the reason; there is no fix round.
# The untouched worktree is first moved to main as it stands, so the reviewer reads today's main, not the one the
# session started from; closed() then refuses a main that has moved on from the commit the reviewer read.
nochange() { # <card> <issue> <worktree> <brief>
  local c=$1 n=$2 wt=$3 said t res err
  said=$(jq -r 'select(.type == "result") | .result // "" | tostring' "$wt.out" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n 1)
  [[ $said == "ALREADY-DONE: "*[![:space:]]* ]] && [ -z "$(git -C "$wt" status --porcelain 2>&1)" ] \
    || { block "$c" "$n" "$wt" "the session made no change, so there is nothing to review"; return; }
  said=${said:0:1000}
  err=$(git -C "$wt" checkout -q --detach "refs/heads/$BRANCH" 2>&1) \
    || { block "$c" "$n" "$wt" "the session said that main already fixes the issue, but the engine could not move the worktree to main for the review:${err:0:400}. $said"; return; }
  began "$c" "$n" review
  t=$(reviewed "$wt" "$4"$'\n\n# The session changed nothing and ended its reply with this line\n'"$said" "$CONFIRM") \
    || { block "$c" "$n" "$wt" "review of the session's ALREADY-DONE line: $t"; return; }
  res=$(verdict "$wt.review")
  record "$c" "$n" review "$res" "$(grep -Ev "$UNRECORDED" "$wt.review" | jq -cRs --arg res "$res" --argjson t "$t" --argjson k "$(counts "$wt.review")" 'sub("\n+$"; "") as $r | $t + {reason:$r,counts:$k} + (if $res == "NO-GO" then {tail: $r} else {} end)')"
  case $res in
    GO) ;;
    NO-GO) block "$c" "$n" "$wt" "the session made no change and said that main already fixes the issue. The reviewer says that main does not do what the issue asks. $said"; return ;;
    *) block "$c" "$n" "$wt" "the session made no change and said that main already fixes the issue. The review of that claim ended without one clear verdict. $said"; return ;;
  esac
  reading fresh >/dev/null 2>&1 # the after reading of the closed line, asked for outside the lock
  err=$(locked closed "$c" "$n" "$wt" "$said") || { block "$c" "$n" "$wt" "$err. $said"; return; }
  clean "$wt"
}

# Under the lock, as one step, so no Conveyor landing comes between the check and the close: the issue is closed
# only if main is still the commit the reviewer read, then the closed line is written. Prints the reason when it fails.
closed() { # <card> <issue> <worktree> <ALREADY-DONE line>
  local err l
  [ "$(git rev-parse "refs/heads/$BRANCH")" = "$(git -C "$3" rev-parse HEAD)" ] \
    || { echo "the reviewer confirmed that main already fixes the issue, but main changed during that review. The fix is possibly not on main now, so the engine did not close the issue"; return 1; }
  l=$(line "$1" "$2" closed ok "$(jq -cn --arg r "$4" --argjson e "$(ending)" '{reason:$r} + $e')") || { echo "the engine cannot make the closed line, so it did not close the issue"; return 1; }
  # A card of issue 0 (a main-red fix card) has no issue to close.
  [ "$2" = 0 ] || err=$(gh_write issue close "$2" --comment "Conveyor card $1 changed nothing: main already does what this issue asks, and the reviewer confirmed it."$'\n\n'"$4" 2>&1 >/dev/null) \
    || { echo "main already does what the issue asks, and the reviewer confirmed it. The engine could not close the issue:${err:0:400}"; return 1; }
  append "$l" || { echo "the engine closed the issue, but it could not write the closed line"; return 1; }
}
