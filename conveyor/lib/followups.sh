# SPDX-License-Identifier: Apache-2.0
# The last review said NO-GO: each of its finding lines becomes its own issue, filed before the card lands; a line
# the review repeats word for word is filed once. Prints the new issue numbers as a JSON array. When a filing fails
# it prints the reason instead, and withdraws (closes) the ones it had already filed: the card will not land, and an
# open follow-up would be built against a main that never got its parent's change.
# A withdrawn follow-up is closed as "not planned", never "completed": nothing fixed its finding. The finding
# goes to <worktree>.withdrawn, in the order filed (the review's finding lines, as followups() reads them), and from
# the kept folder into the brief of the issue's next card; the comment names that issue.
# Each follow-up's body holds its depth, "Follow-up depth: N": its parent's depth (fudepth()) plus 1. A card whose
# issue is at the cap, MAX_DEPTH (lib/paths.sh), files none, so no chain goes deeper: its last review's findings go to
# the declined list when it lands, declined by code with FUCAP as the reason; when they cannot be written there the
# card ends blocked, landed, its review kept.
# A finding that names one of the pack's pipelineFiles (how the engine builds, reviews, fixes, tests, lands or
# pushes), or a file under one (onpipeline()), is filed held: the control record holds its issue, as `control hold` does, before the card lands,
# so it is never built until the owner releases it. Its body holds one more line, "Cost to every card:", which reads
# "not assessed": nothing here assesses it. The snapshot lists it in Needs you (pipeline) while it is held.
# With the pack's standing kind review-followup on (auto.standing, lib/standing.sh), such a finding that names only
# files of the card's own change (ownonly()) is not held: it only finishes or corrects the change the owner approved.
# Its release is logged in the ruling log, source "standing", kind review-followup; one that cannot be logged is held.
# The whole test on main (the pack's test.main; a pack that names none has none): a card's test step runs only the
# tests of what the card touched, so the whole test is run here instead, by `serve` beside its cards and never by a
# card: no card waits on it. A run is due when main is at another commit than the last run's and the last try began
# MAIN_TEST_EVERY seconds ago or more. With the pack's test.mainAt (HH:MM, the host's local time) it is due once a
# day instead: when main is at another commit than the last run's, it is that time of the day or later, and the last
# try began before that time of the same day. One runs at a time (a lock: a loop that restarts on new code leaves the
# run of the loop before it going). It runs as a card's test step does (tests(): one of the machine's test slots, the
# timeout, its output and logs), in a worktree of that commit alone, $CARDS/maintest/wt.
# $MAINTEST keeps {sha: the commit of the last run that ended, at: when the last try began, pass: the last commit that
# passed, fail: null, or {issue, cases, from: the last pass, to: the commit that failed, since, exit} of the failure
# that stands, filed: [{issue, cases}], the issue last filed for each set of failing cases, full: the count of `ok <case>`
# lines of the output of the last run that passed}. A run that exits 0 with under 90% of full such lines is a short
# run, not a pass (a run that skipped half the suite would else be the last pass later failures are measured from): it
# keeps pass and full, and fails as below with the one case "a short run: ...", its issue saying "ran N of about M
# cases" with the end of its output. The snapshot gives fail
# to the Board's Needs you (mainTest) until a run passes. The commit is kept only once its run has ended and, when it
# failed, its issue was filed or added to: a try whose worktree or test slots could not be made, or that was killed,
# tested nothing, and a failure GitHub did not take reached no one, so the same commit is tried again when the next run
# is due (an hour on; with test.mainAt, the next day).
# Each failed case of a red run (testfails(); "<file>: <case>", or the case alone when the run's logs name no file: a
# case of the same name in another file is another case, with its own issue) is run alone MAIN_ALONE times on the
# same commit (fullalone(), lib/fulltest.sh). A case that passes every time alone is flaky: an entry of the flaky-test
# record (flaky()), its source "main test <commit>", and it files nothing. A red run whose failed cases were all
# flaky, with no file that failed naming no case and no timeout, counts as a pass. The cases that failed alone file
# one issue of the pack's second priority (its last, when it has one) that names them, their failure lines and the
# commits since the last pass. A failure
# of the same cases while the issue filed for them is open adds a comment to it, with the commits up to the new one,
# and files none, whatever failed in the runs between; one whose issue GitHub says nothing of writes nothing, and
# keeps the issue (and, as any failure not written, is tried again).
. "$HERE/lib/standing.sh" || exit 1
MAIN_TEST_EVERY=3600 MAIN_ALONE=3
mainput() { printf '%s\n' "$1" > "$MAINTEST.new" && mv -f "$MAINTEST.new" "$MAINTEST" || { rm -f "$MAINTEST.new"; return 1; }; } # <the record>
maintest() {
  local cmd daily due=null sha was at wt=$CARDS/maintest/wt lock rc out f cases='[]' lines='[]' u r x ok pass n state='' prio title body told=true ran full short='' tail
  packget test.main cmd test.mainAt daily && [ -n "$cmd" ] || return 0
  mkdir -p "${wt%/*}" && { exec {lock}>>"$MAINTEST.lock"; } 2>/dev/null && flock -n "$lock" || return 0
  sha=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") && at=$(clock) || return 0
  if [ -n "$daily" ]; then
    [[ $daily =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] \
      || { echo "conveyor: the whole test on main did not run: the pack's test.mainAt, \"$daily\", is not a time of day as HH:MM" >&2; return 1; }
    x=$(jq -rn --arg at "$at" '$at | fromdate') && due=$(p_date "$(p_date "@$x" +%F) $daily" +%s) || return 1
  fi
  was=$(jq -ce 'objects' "$MAINTEST" 2>/dev/null) || was='{}'
  jq -e --arg s "$sha" --arg at "$at" --argjson e "$MAIN_TEST_EVERY" --argjson due "$due" \
    '.sha != $s and if $due == null then (.at | type) != "string" or ($at | fromdate) - (.at | fromdate) >= $e
      else ($at | fromdate) >= $due and ((.at | type) != "string" or (.at | fromdate) < $due) end' <<<"$was" >/dev/null || return 0
  was=$(jq -c --arg at "$at" '. + {at: $at}' <<<"$was") && mainput "$was" || return 1
  out=$({ git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt" "$wt".*; git worktree prune
    git worktree add -q --detach "$wt" "$sha" && deps "$wt"; } 2>&1 < /dev/null) \
    || { echo "conveyor: the whole test on main did not run: its worktree could not be made: $out" >&2; return 1; }
  out=$(slot_pool 2>&1) || { echo "conveyor: the whole test on main did not run: $out" >&2; return 1; }
  # A test map that is due is made again from this run's coverage (lib/testmap.sh mapcovon(), maprefresh()).
  mapcovon "$wt" || :; tests "$wt" test.main; rc=$?; mapcovoff
  ran=$(sed 's/\x1b\[[0-9;]*m//g' "$wt.test" 2>/dev/null | grep -c '^ok ') || ran=0
  full=$(jq -r '.full | numbers' <<<"$was")
  if [ $rc = 0 ] && [ -n "$full" ] && [ $((ran * 10)) -lt $((full * 9)) ]; then
    short="ran $ran of about $full cases"
    mapstop "$wt" "the whole test on main $short"
    tail=$(sed 's/\x1b\[[0-9;]*m//g' "$wt.test" 2>/dev/null | tail -n 20); cases='["a short run: under 90% of the cases of its last full run"]'
  elif [ $rc = 0 ]; then
    maprefresh "$wt" || :
    git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt".*
    mainput "$(jq -c --arg s "$sha" --argjson r "$ran" '. + {sha: $s, pass: $s, fail: null, full: $r}' <<<"$was")"; return
  else
    mapstop "$wt" "the whole test on main failed"
    f=$(testfails "$wt.test" "$rc" test.main) || f='{"files":[]}'
    # Each named case alone, MAIN_ALONE times: one that passes every time is flaky; the others are the failure.
    while IFS= read -r u; do
      ok=0; for ((x = 0; x < MAIN_ALONE; x++)); do r=$(fullalone "$wt" "$f" "$u" test.main) && [ "$r" = passed ] && ok=$((ok + 1)); done
      if [ "$ok" = "$MAIN_ALONE" ]; then
        flaky "main test ${sha:0:12}" "$(jq -c --arg n "failed in the whole test on main, passed alone $MAIN_ALONE of $MAIN_ALONE" '[{case: .name, note: $n}]' <<<"$u")" >/dev/null \
          || echo "conveyor: the whole test on main: $(jq -r .name <<<"$u") passed alone; the flaky-test record could not be written" >&2
      else
        cases=$(jq -c --argjson u "$u" '. + [$u.name]' <<<"$cases")
        lines=$(jq -c --argjson u "$u" --arg r "passed alone $ok of $MAIN_ALONE" '. + ["\($u.name): \($u.line // "failed") (\($r))"]' <<<"$lines")
      fi
    done < <(jq -c --arg cmd "$cmd" '[.files[] | .file as $f | .cases[] | {file: $f, case: .name, line,
      name: (if $f == $cmd or $f == "" then .name else "\($f): \(.name)" end)}] | unique_by(.name)[]' <<<"$f")
    # Every failure named a case, and each passed alone every time: a pass.
    if [ "$cases" = '[]' ] && jq -e '(.files | length) > 0 and all(.files[]; .cases != []) and .timeout == null' <<<"$f" >/dev/null; then
      git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt".*
      mainput "$(jq -c --arg s "$sha" '. + {sha: $s, pass: $s, fail: null}' <<<"$was")"; return
    fi
  fi
  git worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt".*
  pass=$(jq -r '.pass // ""' <<<"$was"); git rev-parse -q --verify "$pass^{commit}" >/dev/null 2>&1 || pass=''
  n=$(jq -r --slurpfile c <(printf '%s' "$cases") '$c[0] as $c | [.filed | arrays | .[] | select(.cases == $c) | .issue][-1] // empty' <<<"$was")
  [ -z "$n" ] || state=$(timeout 20 gh issue view "$n" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null) || state=''
  if [ -n "$short" ]; then
    body="The whole test on main (the pack's test.main) $short at ${sha:0:12}. It named no failing case, but it ran under 90% of the cases of its last full run, so it is not a pass.

The end of its output:
\`\`\`
$tail
\`\`\`
"
  else
    body="The whole test on main (the pack's test.main) failed$([ "$state" != OPEN ] || echo " again, with the same cases,") at ${sha:0:12} (exit $rc; 124 is the ${TEST_TIMEOUT}s timeout).

Failing cases:
$(jq -r 'if . == [] then "the run named none" else .[] | "- " + . end' <<<"$cases")
$([ "$lines" = '[]' ] || jq -r '"\nTheir failure lines, each case run alone '"$MAIN_ALONE"' times:", (.[] | "- " + .)' <<<"$lines")
"
  fi
  body="$body

$(if [ -n "$pass" ]; then echo "Commits since the last pass (${pass:0:12}..${sha:0:12}):"; git log --format='- %h %s' "$pass..$sha" | head -n 50
  else echo "No pass of it is recorded here yet: main is at ${sha:0:12}."; fi)"
  if [ "$state" = OPEN ]; then
    gh_write issue comment "$n" --body "$body" >/dev/null 2>&1 || { told=false; echo "conveyor: the whole test on main failed again; no comment could be added to #$n" >&2; }
  elif [ -z "$n" ] || [ "$state" = CLOSED ]; then
    prio=$(jq -r '.[[1, length - 1] | min]' <<<"$PRIOS")
    title=$(jq -r --arg s "${sha:0:12}" --arg short "$short" 'if $short != "" then "The whole test on main " + $short + " at " + $s else
      "The whole test fails on main" + (if . == [] then " at " + $s
      else ": " + (.[:3] | join(", ")) + (if length > 3 then " and \(length - 3) more" else "" end) end) end | .[0:200]' <<<"$cases")
    n=$(gh_write issue create --title "$title" --label "$TYPE" --label "$prio" --body "$body" 2>&1 | grep -oE '/issues/[0-9]+' | tail -n 1); n=${n##*/}
    [ -n "$n" ] || { told=false; echo "conveyor: the whole test on main failed; its issue could not be filed" >&2; }
  else
    told=false; echo "conveyor: the whole test on main failed again; the state of #$n could not be read" >&2
  fi
  mainput "$(jq -c --slurpfile c <(printf '%s' "$cases") --argjson n "${n:-null}" --arg p "$pass" --arg s "$sha" --arg at "$at" --argjson rc "$rc" --argjson told "$told" \
    '$c[0] as $c | ([.fail | objects | select(.cases == $c) | .since][0]) as $since
     | . + (if $told then {sha: $s} else {} end) + {fail: {issue: $n, cases: $c, from: (if $p == "" then null else $p end), to: $s, since: ($since // $at), exit: $rc}}
     | if $n == null then . else .filed = [.filed | arrays | .[] | select(.cases != $c)] + [{issue: $n, cases: $c}] end' <<<"$was")"
}

# <issue json>: prints its follow-up depth: its body's "Follow-up depth: N" line; at least 1 with the pack's follow-up
# label (a slice of a split has the label and no depth line); else 0.
fudepth() {
  jq -r --arg fu "$FOLLOWUP" '[([.body // "" | match("(?:^|\n)Follow-up depth: ([0-9]{1,3})[ \t\r]*(?=\n|$)") | .captures[0].string | tonumber][0] // 0),
    (if (.labels // []) | any(.name == $fu) then 1 else 0 end)] | max' <<<"$1"
}
# shellcheck disable=SC2034 # read by card() (lib/card.sh)
FUCAP="its issue is a follow-up at the depth cap of $MAX_DEPTH, so no deeper follow-up is filed" # the reason of a finding declined at the cap
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
# spaces: every run of words between the finding's other separators is a candidate. A "*" is a separator too, so a
# name in Markdown emphasis (**conveyor/lib/**) is that name.
onpipeline() {
  jq -r --arg f "$1" 'def norm: reduce (split("/")[] | select(. != "" and . != ".")) as $s ([]; if $s == ".." and length > 0 and .[-1] != ".." then .[:-1] else . + [$s] end) | join("/");
    map(norm) as $e | [$f | scan("[^\\]\\[:,;()\u0027\"`<>*]+") | [splits("\\s+") | select(. != "")] as $w
      | range(0; $w | length) as $i | range($i + 1; ($w | length) + 1) as $j | $w[$i:$j] | join(" ") | sub("\\.+$"; "") | norm]
    | if any(. as $p | $e | any(. as $x | $x == "" or $p == $x or ($p | startswith($x + "/")))) then "1" else "" end'
}
# <finding> <worktree>: prints 1 when the finding names a file, and each file it names is one of the worktree's staged
# change (the card's change, as its review read it); a name with no folder counts as the changed file of that name. A
# file it names: a word with a "/" that ends in an extension or a "/", or is a tracked path; or a word that is a tracked
# file's name or a changed file. A word is a run of letters, digits and _.@+/- (so a ":<line>" is not part of it), its
# leading "./" and closing "." dropped. Bug it stops: a follow-up that changes another pipeline file let through with no
# one asked.
ownonly() {
  jq -rn --arg f "$1" --rawfile ch <(git -C "$2" diff --cached --no-renames --name-only 2>/dev/null) --rawfile tr <(git -C "$2" ls-files 2>/dev/null) '
    def lines: split("\n") | map(select(. != ""));
    ($ch | lines) as $c | ($tr | lines) as $t | ($t | map(split("/")[-1])) as $tn | ($c | map(split("/")[-1])) as $cn
    | [$f | scan("[A-Za-z0-9_.@+/-]+") | sub("^(\\./)+"; "") | sub("\\.+$"; "")
       | select(. != "" and ((contains("/") and (test("\\.[A-Za-z0-9]+$") or endswith("/") or IN($t[]))) or IN($tn[]) or IN($c[])))]
    | if length > 0 and all(IN($c[]) or ((contains("/") | not) and IN($cn[]))) then "1" else "" end'
}
# <worktree>: prints the first finding of its review (<worktree>.review) that quotes a word the privacy check flags
# (privwords(), lib/issues.sh) which a line the card's staged change adds holds, the word's leading and closing marks
# (quotes, brackets, a closing . or :) aside. Such a finding is a privacy hit in the card's own change: a follow-up
# would land the hit on main, so the card fixes it (card.sh). Prints nothing when the check could not be made.
privown() {
  local f w x added
  added=$(git -C "$1" diff --cached --no-renames -U0 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+ ') || return 0
  while IFS= read -r f; do
    while IFS=$'\t' read -r x w; do
      w=$(sed -E 's/^[^[:alnum:]/~\\]+//; s/[^[:alnum:]]+$//' <<<"$w")
      [ -z "$w" ] || [[ $added != *"$w"* ]] || { printf '%s\n' "$f"; return 0; }
    done < <(privwords "$f" 2>/dev/null)
  done < <(leftovers "$1.review")
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
  local f mark where out num n nums=() more=() found=() pipe cost own='' free res pm g masked depth kind clean
  depth=$(fudepth "$2") && [[ $depth =~ ^[0-9]+$ ]] || { echo "cannot read the parent issue's follow-up depth"; return 1; }
  packget pipelineFiles pipe || { echo "cannot read the pack's pipeline files"; return 1; }
  packget privacy.mode pm || { echo "cannot read the pack's privacy mode"; return 1; }
  ! standingon review-followup || { packget auto.reserved res || { echo "cannot read the pack's auto.reserved"; return 1; }; own=1; }
  n=$(jq -r .number <<<"$2") && mapfile -t more < <(jq -r --arg p "$AREA" '(.labels | map(.name | select(startswith($p))) | .[0] // empty | "--label", .),
    (.milestone.title // empty | "--milestone", .)' <<<"$2") || { echo "cannot read the parent issue's labels and milestone"; return 1; }
  mapfile -t found < <(leftovers "$3")
  [ ${#found[@]} != 0 ] || { echo "the last review said NO-GO and named no finding to file"; return 1; }
  for f in "${found[@]}"; do
    # The finding's level, P0 to P3 (P1 when it names none), is the pack's priority at that place, or its last one.
    # A P3 finding in a pack of fewer than four priorities gets none of them: the engine reads an issue with none as P3
    # (LEVEL), and the pack's last one would file it at a higher level. Bug: P3 follow-ups were filed as P2.
    # With the pack's privacy.mode public, the issue's text holds the finding with each word the privacy check flags
    # masked (privmask(), lib/issues.sh), and says so: gh_write would post none of it. Bug: a finding that quoted a
    # home path could not be filed, so its card was blocked.
    g=$f masked=''
    if [ "$pm" = public ]; then
      g=$(privmask "$f") || { unfile "$n" "$3" "${nums[@]}"; echo "follow-up not filed, so nothing landed: the privacy check could not be made (finding: ${f:0:200})"; return 1; }
      masked=${f//"$CARDS"/<cards>}; [ "$g" = "${masked//"${STATE%/*}"/<state>}" ] && masked='' \
        || masked=$'\n\nConveyor masked the parts of the finding that the privacy check flags.'
    fi
    mark=$(grep -oE '\[P[0-3]\]' <<<"$f" | head -n 1 | tr -d '[]P'); where=$(grep -oE '[^[:space:]]+:[0-9]+' <<<"$g" | head -n 1)
    mark=$(jq -r --argjson i "${mark:-1}" 'if $i == 3 and length < 4 then "" else .[[$i, length - 1] | min] end' <<<"$PRIOS")
    cost=$(onpipeline "$f" <<<"$pipe") || { unfile "$n" "$3" "${nums[@]}"; echo "cannot tell whether a finding names a pipeline file, so nothing landed (finding: ${f:0:200})"; return 1; }
    # A finding that holds a word or phrase of auto.reserved (in any case, as auto decide reads it) is never let
    # through: it waits for the owner. Bug: a follow-up on the card's own file about security went unheld.
    free=''; [ -z "$cost" ] || [ -z "$own" ] \
      || [ "$(jq --arg f "$f" 'any(.[]; . as $w | $f | ascii_downcase | contains($w | ascii_downcase))' <<<"$res" 2>/dev/null)" != false ] \
      || free=$(ownonly "$f" "${3%.review}")
    cost=${cost:+$'\nCost to every card: not assessed'}
    # A finding the reviewer marks [cleanup] (REVIEWT: its fix changes no behaviour, as a comment, dead code or a
    # redundant check) is filed without the pack's type label, so its card skips the bug-card check (card.sh): no test
    # can fail on main for it. Its body says so, and its review judges that the change keeps behaviour. A finding with
    # no such mark is a bug, as before. Bug: such a follow-up was built as a bug and blocked for having no failing test.
    kind=$TYPE clean=''
    if grep -qiE '^(\[[^]]*\][[:space:]]*)*\[cleanup\]' <<<"$f"; then
      kind='' clean=$'\nCleanup: the finding changes no behaviour, so no test has to fail on main for it. The change must keep what the code does: the review judges that it does.'
    fi
    out=$(gh_write issue create --title "${g:0:200}" --label "$FOLLOWUP" ${kind:+--label "$kind"} ${mark:+--label "$mark"} "${more[@]}" \
      --body "Follow-up to #$n (Conveyor card $1). The last review of that card said NO-GO. The card landed without a fix for the finding below. Fix it in this issue.

Finding: $g
Where: ${where:-the finding names no file:line}$clean$cost$masked
Follow-up depth: $((depth + 1))" 2>&1) && num=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && num=${num##*/} && [ -n "$num" ] \
      || { unfile "$n" "$3" "${nums[@]}"; echo "follow-up not filed, so nothing landed (finding: ${f:0:200}): ${out:0:400}"; return 1; }
    nums+=("$num")
    [ -z "$free" ] || standinglog review-followup "#$num, a follow-up of #$n (card $1), was not held: its finding names only files of that card's change: ${f:0:200}" >/dev/null 2>&1 || free=''
    [ -z "$cost" ] || [ -n "$free" ] || out=$(locked control hold "$num" 2>&1 >/dev/null) \
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
    l=$(stdb ask lines declined 2>/dev/null | jq -c --arg id "$1" 'objects | select(.id == $id)' 2>/dev/null) \
      || { echo "conveyor: the declined list could not be read; nothing filed" >&2; exit 1; }
    l=$(head -n 1 <<<"$l")
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
    miss=$(stdb ask lines declined 2>/dev/null | jq -rn '[inputs | objects | .id] as $have | $ARGS.positional - $have | join(" ")' --args "$@" 2>/dev/null) \
      || { echo "conveyor: the declined list could not be read; nothing dismissed" >&2; exit 1; }
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
# that verdict; a GO beside an open finding is a NO-GO. Spaces and tabs at a verdict line's end are left out (a
# Markdown line break). Prints "GO", "NO-GO" or "none".
verdict() { # <review file>
  [ "$(grep '^VERDICT:' "$1" | sed 's/[[:blank:]]*$//' | sort -u | wc -l)" -eq 1 ] || { echo none; return; }
  case $(tail -n 1 "$1" | sed 's/[[:blank:]]*$//') in
    'VERDICT: GO') if grep -Evq "$NOTFINDING" "$1"; then echo NO-GO; else echo GO; fi ;;
    'VERDICT: NO-GO') echo NO-GO ;;
    *) echo none ;;
  esac
}

# The review's answer to "would a customer or staff member see or do anything differently": prints "no" or
# "yes: <the reviewer's sentence>", or nothing when the review does not hold exactly one such line, written as asked.
# Spaces and tabs at the line's end are left out (a Markdown line break); any other added text is not an answer.
# A review held to a section approved before the build answers "matches" or "differs: <how>" instead: with
# held, only those two are an answer; with any, all four are (a kept review, whichever it was).
visible() { # <review file> [held | any]
  local f='no|yes: .*[^[:space:]].*'
  [ "${2:-}" != held ] || f='matches|differs: .*[^[:space:]].*'
  [ "${2:-}" != any ] || f="$f|matches|differs: .*[^[:space:]].*"
  [ "$(grep -c '^USER-VISIBLE:' "$1")" = 1 ] || return 0
  grep -E "^USER-VISIBLE: ($f)[[:blank:]]*\$" "$1" | sed 's/^USER-VISIBLE: //; s/[[:blank:]]*$//'
}

# The last reply of a session's stream (a Claude result, a Codex agent_message or an OpenCode text part) that holds
# more than white space, on one line, cut to 1000 characters; nothing when it has none. With whole, the reply as it is.
lastreply() { # <session output> [whole]
  jq -Rrjn --arg w "${2:-}" '[inputs | fromjson? // empty | objects | if .type == "result" then .result
      elif .type == "item.completed" and .item.type? == "agent_message" then .item.text elif .type == "text" then .part.text? else empty end
      | strings | select(test("\\S"))] | last // "" | if $w != "" then . else [splits("\\s+")] | map(select(. != "")) | join(" ") | .[0:1000] end' "$1" 2>/dev/null
}

# block(), with the given words added at the end of the reason's first line, before the output a reason may carry.
# The reason is posted on the issue whatever the review holds: it says where the session's logs are kept.
ncblock() { # <card> <issue> <worktree> <reason> <words>
  local l=${4%%$'\n'*}
  block "$1" "$2" "$3" "$l$5${4#"$l"}" post
}

# The session left no change. If its reply ends with an ALREADY-DONE line and the worktree is untouched, one review
# confirms that main already does what the issue asks, and on its GO the issue is closed with that line and the
# card's closing line is `closed`. A DONE-OUTSIDE line (the issue asks for no change to a tracked file, and the session
# did its work outside the repository: records in the state folder, issues filed) goes to one review the same way
# (OUTSIDE): it checks the issue's Done-when lines against the evidence the line names, and on its GO
# doneoutside() closes the issue with the session's report; a NO-GO's reason holds the reviewer's findings.
# Anything else blocks the card with the reason; there is no fix round.
# The untouched worktree is first moved to main as it stands, so the reviewer reads today's main, not the one the
# session started from; closed() then refuses a main that has moved on from the commit the reviewer read, unless
# every file the ALREADY-DONE line names is the same on the new main (issue 552: on a busy belt main moves during
# nearly every review, and a new review only meets the same move again).
# A main-red fix card (issue 0, its entry in the main-red record) that made no change first runs its cases again on
# main as it is now (bugproof.sh redproof(), issue 323): when every case passes there, main is no longer red for them, and the card
# closes as not needed, its closed line saying so. Else it is blocked, saying why, whatever its reply says: only that
# run, not a review of an ALREADY-DONE line, shows main is no longer red.
# Every reason it blocks with names the card's kept folder, where block() moves the session's output and errors, so
# the owner finds why the session stopped (issue 495), and is posted on the issue. A review of an ALREADY-DONE line
# writes its own error output in place of the session's, and a reason after it says so.A reason of a main-red card, or of a card with no ALREADY-DONE
# line, also quotes the session's last reply (lastreply()); with none it says so, and the end of the session's error
# output is the line's tail. A card reaches here only after its session ended well: session() fails on any other exit.
nochange() { # <card> <issue> <worktree> <brief>
  local c=$1 n=$2 wt=$3 said t res err kept why r k ins claim ev=''
  kept=" Its session's output and errors are kept in kept/$c/."; why=$kept
  if r=$(lastreply "$wt.out") && [ -n "$r" ]; then why+=" Its last reply: $r"
  elif [ -e "$wt.out" ]; then why+=" The session ended well (exit 0) but left no reply."$'\n'"$(tail -n 20 "$wt.err" 2>/dev/null)"; fi
  if [ "$n" = 0 ] && jq -e --arg c "$c" 'any(.reds[]?; .card == $c)' "$MAINRED" >/dev/null 2>&1; then
    t="the session made no change, so there is nothing to review"
    [ -z "$(git -C "$wt" status --porcelain 2>&1)" ] && err=$(git -C "$wt" checkout -q --detach "refs/heads/$BRANCH" 2>&1) \
      || { ncblock "$c" "$n" "$wt" "$t. The engine could not run its cases again on main: the worktree is not clean or could not be moved to main. ${err:0:400}" "$why"; return; }
    redproof "$c" "$wt"
    [ $? = 3 ] || { ncblock "$c" "$n" "$wt" "$t. Its cases on main as it is now: $(head -n 1 "$wt.unfixed")" "$why"; return; }
    t="Not needed: the session made no change, and the cases ran again on main. $(head -n 1 "$wt.unfixed")"
    res=$(line "$c" "$n" closed ok "$(jq -cn --arg r "$t" --argjson e "$(ending)" --argjson w "$(waited)" '{reason: $r} + $e + $w')") && locked append "$res" \
      || { ncblock "$c" "$n" "$wt" "$t The engine could not write the closed line." "$why"; return; }
    clean "$wt"; return
  fi
  r=$(lastreply "$wt.out" whole)
  said=$(grep -v '^[[:space:]]*$' <<<"$r" | tail -n 1)
  case $said in "ALREADY-DONE: "*[![:space:]]*) k=fixed ;; "DONE-OUTSIDE: "*[![:space:]]*) k=outside ;; *) k='' ;; esac
  [ -n "$k" ] && [ -z "$(git -C "$wt" status --porcelain 2>&1)" ] \
    || { ncblock "$c" "$n" "$wt" "the session made no change, so there is nothing to review." "$why"; return; }
  said=${said:0:1000}
  if [ $k = fixed ]; then
    ins=$CONFIRM claim="said that main already fixes the issue"
    err=$(git -C "$wt" checkout -q --detach "refs/heads/$BRANCH" 2>&1) \
      || { ncblock "$c" "$n" "$wt" "the session said that main already fixes the issue, but the engine could not move the worktree to main for the review:${err:0:400}." "$kept $said"; return; }
  else ins=$OUTSIDE claim="said that it did the issue's work outside the repository" ev=$(outsidefacts "$said" "$n" "$(p_stat "$wt.before" | cut -d' ' -f2)"); fi
  began "$c" "$n" review
  kept=" Its session's output and the last error output (of its review, when the review started) are kept in kept/$c/."
  t=$(reviewed "$wt" "$4$ev"$'\n\n# The session changed nothing and ended its reply with this line\n'"$said" "$ins") \
    || { ncblock "$c" "$n" "$wt" "review of the session's ${said%%:*} line: $t" "$kept"; return; }
  res=$(verdict "$wt.review")
  record "$c" "$n" review "$res" "$(grep -Ev "$UNRECORDED" "$wt.review" | jq -cRs --arg res "$res" --argjson t "$t" --argjson k "$(counts "$wt.review")" 'sub("\n+$"; "") as $r | $t + {reason:$r,counts:$k} + (if $res == "NO-GO" then {tail: $r} else {} end)')"
  case $res in
    GO) ;;
    NO-GO) t="main does not do what the issue asks"
      # The reviewer's findings, on the reason's first line: what the evidence of work outside the repository lacks.
      [ $k = fixed ] || t="the evidence does not show the issue's work done: $(grep -Ev "$NOTFINDING" "$wt.review" | tr '\n' ' ' | head -c 600)"
      ncblock "$c" "$n" "$wt" "the session made no change and $claim. The reviewer says that ${t% }." "$kept $said"; return ;;
    *) ncblock "$c" "$n" "$wt" "the session made no change and $claim. The review of that claim ended without one clear verdict." "$kept $said"; return ;;
  esac
  reading fresh >/dev/null 2>&1 # the after reading of the closed line, asked for outside the lock
  if [ $k = fixed ]; then err=$(locked closed "$c" "$n" "$wt" "$said")
  else err=$(locked doneoutside "$c" "$n" "$said" "$r"); fi || { ncblock "$c" "$n" "$wt" "$err." "$kept $said"; return; }
  clean "$wt"
}

# The evidence a DONE-OUTSIDE line names, as its reviewer is given it: a Claude or OpenCode reviewer has no shell or
# web, and reads no folder outside the worktree. Each issue it names (#<n>, of the first 50 distinct numbers, the
# card's own then left out) as GitHub gives it, its body cut to 2000 characters; a range (#<a> to #<b>, through, - or
# .., of at most 50) is each issue in it. Each path under conveyor/state/ it names (a file, or a folder's files), read from the state folder,
# 4000 characters a file and 40000 in all: the files it names first, in the order it names them, so a big folder named
# before a file does not leave the file out, then the folders. In a folder, the files the session changed (at or after
# its start, the time of the <worktree>.before that session() writes as it begins) first, the smallest first, so the
# records it wrote come before older files and session logs; the files the limit leaves out are counted. What cannot
# be read says so.
outsidefacts() { # <DONE-OUTSIDE line> <the card's issue> [<the session's start, epoch seconds>]
  local w i j f p s m o='' left=40000 more
  for i in $(grep -oE '#[0-9]+( *(to|through|-|–|\.\.) *#?[0-9]+)?' <<<"$1" | awk '{ a = substr($0, 2) + 0; match($0, /[0-9]+$/)
      b = substr($0, RSTART) + 0; if (b > a && b - a <= 50) for (; a <= b; a++) print a; else { print a; print b } }' \
    | awk '!s[$0]++' | head -n 50); do
    [ "$i" != "$2" ] || continue
    j=$(timeout 20 gh issue view "$i" --json number,title,state,body 2>/dev/null </dev/null \
      | jq -er 'objects | select(.number) | "\(.title) (\(.state))\n\(.body // "" | .[0:2000])"' 2>/dev/null) || j="GitHub did not give this issue."
    o+=$'\n\n## Issue #'"$i"$'\n'"$j"
  done
  while IFS= read -r w; do
    p=$ST/${w#conveyor/state/}; p=${p%/}
    [[ $w != *..* ]] && [ -e "$p" ] || { o+=$'\n\n## '"$w"$'\nThe state folder has no such file.'; continue; }
    more=0
    while read -r s m f; do
      [ "$left" -gt 0 ] || { more=$((more + 1)); continue; }
      j=$(head -c 4000 "$f" 2>/dev/null) || j="It cannot be read."; j=${j:0:$left}; left=$((left - ${#j}))
      o+=$'\n\n## conveyor/state/'"${f#"$ST"/}"$'\n'"$j"
    done < <(find "$p" -type f 2>/dev/null | while IFS= read -r f; do s=$(p_stat "$f") && echo "$s $f"; done \
      | awk -v t="${3:-0}" '{ print ($2 >= t ? 0 : 1), $0 }' | LC_ALL=C sort -k1,1n -k2,2n -k4 | cut -d' ' -f2-)
    [ "$more" = 0 ] || o+=$'\n\n'"The limit of 40000 characters left out $more more files of $w."
  done < <(grep -oE 'conveyor/state/[^[:space:]`"'"'"',;:)]*' <<<"$1" | awk '!s[$0]++' | head -n 20 \
    | while IFS= read -r w; do p=$ST/${w#conveyor/state/}; s=1; [[ $w == *..* ]] || [ ! -f "${p%/}" ] || s=0; echo "$s $w"; done \
    | LC_ALL=C sort -s -k1,1n | cut -d' ' -f2-)
  [ -z "$o" ] || printf '\n\n# The evidence the line names, read by the engine: the issues from GitHub, the files from the state folder%s' "$o"
}

# A card whose session did the issue's work outside the repository, and whose reviewer confirmed it: the issue is
# closed with the session's report as its comment, then the closed line, its reason saying the work was done
# outside the repository, is written. Prints the reason when it fails.
doneoutside() { # <card> <issue> <DONE-OUTSIDE line> <the session's report>
  local err l
  l=$(line "$1" "$2" closed ok "$(jq -cn --arg r "Done outside the repository: $3" --argjson e "$(ending)" --argjson w "$(waited)" '{reason:$r} + $e + $w')") \
    || { echo "the engine cannot make the closed line, so it did not close the issue"; return 1; }
  err=$(gh_write issue close "$2" --comment "Conveyor card $1 changed no tracked file: it did this issue's work outside the repository, and the reviewer confirmed it."$'\n\n'"${4:0:60000}" 2>&1 >/dev/null) \
    || { echo "the reviewer confirmed that the work was done outside the repository. The engine could not close the issue:${err:0:400}"; return 1; }
  append "$l" || { echo "the engine closed the issue, but it could not write the closed line"; return 1; }
}

# Under the lock, as one step, so no Conveyor landing comes between the check and the close: the issue is closed
# only if main is still the commit the reviewer read, or main moved but no file the ALREADY-DONE line names (a word
# of it, its `:<line>` and quotes taken off, that is a file or folder in the commit read) changed since; a line that
# names none is refused as before. Then the closed line is written. Prints the reason when it fails.
closed() { # <card> <issue> <worktree> <ALREADY-DONE line>
  local err l h m w p ps=() ws
  h=$(git -C "$3" rev-parse HEAD) m=$(git rev-parse "refs/heads/$BRANCH")
  if [ "$m" != "$h" ]; then
    read -ra ws <<<"${4#ALREADY-DONE:}"
    for w in "${ws[@]}"; do
      [[ $w =~ ^[^[:alnum:]._/-]*([[:alnum:]._/-]+) ]] || continue
      p=${BASH_REMATCH[1]}; while [[ $p == *. ]]; do p=${p%.}; done
      [ -n "$p" ] && git cat-file -e "$h:$p" 2>/dev/null && ps+=("$p")
    done
  fi
  [ "$m" = "$h" ] || { [ ${#ps[@]} -gt 0 ] && git diff --quiet "$h" "$m" -- "${ps[@]}"; } \
    || { echo "the reviewer confirmed that main already fixes the issue, but main changed during that review. The fix is possibly not on main now, so the engine did not close the issue"; return 1; }
  l=$(line "$1" "$2" closed ok "$(jq -cn --arg r "$4" --argjson e "$(ending)" --argjson w "$(waited)" '{reason:$r} + $e + $w')") || { echo "the engine cannot make the closed line, so it did not close the issue"; return 1; }
  # A card of issue 0 (a main-red fix card) has no issue to close.
  [ "$2" = 0 ] || err=$(gh_write issue close "$2" --comment "Conveyor card $1 changed nothing: main already does what this issue asks, and the reviewer confirmed it."$'\n\n'"$4" 2>&1 >/dev/null) \
    || { echo "main already does what the issue asks, and the reviewer confirmed it. The engine could not close the issue:${err:0:400}"; return 1; }
  append "$l" || { echo "the engine closed the issue, but it could not write the closed line"; return 1; }
}
