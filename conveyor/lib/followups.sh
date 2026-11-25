# SPDX-License-Identifier: Apache-2.0
# The last review said NO-GO: each of its finding lines becomes its own issue, filed before the card lands; a line
# the review repeats word for word is filed once. So does each finding the judge found real but not caused by the
# card's change (an OUTSIDE answer, judged(): <worktree>.outside), after the review's, whatever the last verdict; its
# body says so and gives the judge's reason, and each goes to <worktree>.outfiled as {finding, issue} (issue: the
# number, or the card id of a follow-up card) for the filed line. Prints the new issue numbers as a JSON array.
# A finding its judge last sorted as self-heals, cleanup, already guarded or docs drift (HARMRULE, lib/review.sh) is
# never filed: it goes to the self-heals list or the docs list (healsadd()), and a review whose findings all went there
# files nothing and prints []. Each follow-up's body names the finding's kind and the judge's reason ("Kind:"); a
# finding with no kind is harm.
# With the control record's rules.followupissues false (the Rules tab's Cards with no GitHub issue: Review follow-ups On)
# each finding becomes a card with no GitHub issue instead (tcadd(), lib/testaction.sh), its body the issue's, naming its
# parent, and a `Depends on:` line with the parent card's id, so it is picked only once the parent has landed. A card on a finding that names a pipeline file is held as the issue is (`control release <card id>`). None is
# an issue, so the array is empty; each card's id and finding go to <worktree>.fucards, one a line, so unfile() can
# take them back out of the record. When a filing fails
# it prints the reason instead, and withdraws (closes) the ones it had already filed: the card will not land, and an
# open follow-up would be built against a main that never got its parent's change.
# A withdrawn follow-up is closed as "not planned", never "completed": nothing fixed its finding. The finding
# goes to <worktree>.withdrawn, in the order filed (the review's finding lines, as followups() reads them), and from
# the kept folder into the brief of the issue's next card; the comment names that issue.
# Each follow-up's body holds its depth, "Follow-up depth: N": its parent's depth (fudepth()) plus 1. A card whose
# issue is at the cap, MAX_DEPTH (lib/paths.sh), files none, so no chain goes deeper: its last review's findings go on
# the self-heals list when it lands, with FUCAP as the reason (capheals(); issue 1670); when they cannot be written there the
# card ends blocked, landed, its review kept.
# A finding that names one of the pack's pipelineFiles (how the engine builds, reviews, fixes, tests, lands or
# pushes), or a file under one (onpipeline()), is filed held: the control record holds its issue, as `control hold` does, before the card lands,
# so it is never built until the owner releases it. Its body holds one more line, "Cost to every card:", which reads
# "not assessed": nothing here assesses it. The snapshot lists it in Needs you (pipeline) while it is held.
# With the pack's standing kind review-followup on (auto.standing, lib/standing.sh), such a finding that names only
# files of the card's own change (ownonly()) is not held: it only finishes or corrects the change the owner approved.
# Its release is logged in the ruling log, source "standing", kind review-followup; one that cannot be logged is held.
# Nor is the finding whose fix did not hold on a card the engine lands by the owner's standing order (rlfind, a retry
# by review-land: lib/needsask.sh needsland()), which logs that landing itself, unless the whole finding holds a word
# of auto.reserved or an item of the owner's profile: that one is held.
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
  # The body goes to gh in a file, cut to stay under GitHub's limit (65536 characters). Bug: given as an argument, the body of a
  # few hundred failing cases passed the system's limit on one argument, so gh could not start and nothing was filed.
  [ ${#body} -le 65000 ] || body="${body:0:64900}"$'\n\n'"(The rest is cut: GitHub takes no longer text.)"
  if [ "$state" = OPEN ]; then
    printf '%s' "$body" | gh_write issue comment "$n" --body-file - >/dev/null 2>&1 || { told=false; echo "conveyor: the whole test on main failed again; no comment could be added to #$n" >&2; }
  elif [ -z "$n" ] || [ "$state" = CLOSED ]; then
    prio=$(jq -r '.[[1, length - 1] | min]' <<<"$PRIOS")
    title=$(jq -r --arg s "${sha:0:12}" --arg short "$short" 'if $short != "" then "The whole test on main " + $short + " at " + $s else
      "The whole test fails on main" + (if . == [] then " at " + $s
      else ": " + (.[:3] | join(", ")) + (if length > 3 then " and \(length - 3) more" else "" end) end) end | .[0:200]' <<<"$cases")
    n=$(printf '%s' "$body" | gh_write issue create --title "$title" --label "$TYPE" --label "$prio" --body-file - 2>&1 | grep -oE '/issues/[0-9]+' | tail -n 1); n=${n##*/}
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
FUCAP="its issue is a follow-up at the depth cap of $MAX_DEPTH, so no deeper follow-up is filed" # the reason of a finding put on the self-heals list at the cap (capheals())
leftovers() { grep -Ev "$NOTFINDING" "$1" 2>/dev/null | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk '!seen[$0]++'; } # <review file>: its finding lines, each once
# <review file>: the findings followups() files, in its order: the review's finding lines (leftovers()), then the
# findings of <worktree>.outside that are not among them, each once; none the judge last sorted as a kind kept off the
# belt (healsleft()), which go to their list instead.
tofile() { { leftovers "$1"; jq -r '.finding' "${1%.review}.outside" 2>/dev/null; } | awk 'NF && !seen[$0]++' | grep -vxF -f <(healsleft "$1"); }
# <review file>: the findings the judge of a card that is no follow-up accepted and last sorted as a kind kept off the
# belt (LISTKINDS; <worktree>.effects, judged()), each once: its fix rounds fixed none of them when the review holds one still.
healsleft() { jq -r --argjson k "$LISTKINDS" 'select(.effect | IN($k[])) | .finding' "${1%.review}.effects" 2>/dev/null; }
# The findings on stdin, JSON lines with line (donewhen.sh findings(), repeats()), that are harm: all but those the judge
# of <worktree>'s review last sorted as a kind kept off the belt (<worktree>.effects, healsleft()). A finding with no kind
# is harm. Only a harm finding ends the fix loop as a repeat and becomes a follow-up (afterreview(), loopstop(), lib/card.sh): the others go to their list (followups()).
harmonly() { # <worktree>
  jq -c --slurpfile e <(jq -c 'objects' "$1.effects" 2>/dev/null || :) --argjson k "$LISTKINDS" '. as $f | select(any($e[]; .finding == $f.line and (.effect | IN($k[]))) | not)'
}
# <review file>: why a last NO-GO with no finding line files nothing, with the reviewer's own line (its first UNPROVEN
# line, else its VERDICT line, as afterreview() quotes one), cut at 200 characters.
nofiling() { local w; w=$(grep -m1 '^UNPROVEN:' "$1" || grep -m1 '^VERDICT:' "$1"); echo "the last review said NO-GO and named no finding to file${w:+: ${w:0:200}}"; }
# The findings on stdin, one a line, of a card at the follow-up depth cap: each on the self-heals list (healsadd()) with FUCAP as its
# reason, under the first area label of <issue json>. Issue 1670: they went to the declined list, where nothing builds them.
capheals() { # <card> <issue number> <issue json>
  local f a; a=$(jq -r --arg p "$AREA" '.labels // [] | map(.name | select(startswith($p))) | .[0] // empty' <<<"$3" 2>/dev/null) || a=''
  while IFS= read -r f; do
    [ -z "$f" ] || healsadd "$1" "$2" "$a" "$FUCAP" "$f" review >/dev/null \
      || { echo "conveyor: card $1: its findings at the follow-up depth cap could not be written to $SELFHEALS" >&2; return 1; }
  done
}
# <finding>, the pack's pipelineFiles on stdin: prints 1 when the finding names one of them, or a file under one. Each
# path is read as git would: "." parts and doubled slashes dropped, ".." taking the part before it, so another
# spelling of a listed file is that file, and a longer name that starts with one (a.sh.bak) is not. A name may hold
# spaces: every run of words between the finding's other separators is a candidate. A "*" is a separator too, so a
# name in Markdown emphasis (**conveyor/lib/**) is that name. The sentence marks a candidate ends in (".", "?", "!") are dropped.
# A candidate with its leading and closing "_" dropped is a candidate too, so a name in emphasis of underscores
# (__conveyor/lib/__) is that name, and a name that starts or ends in "_" is still read whole.
onpipeline() {
  jq -r --arg f "$1" 'def norm: reduce (split("/")[] | select(. != "" and . != ".")) as $s ([]; if $s == ".." and length > 0 and .[-1] != ".." then .[:-1] else . + [$s] end) | join("/");
    map(norm) as $e | [$f | scan("[^\\]\\[:,;()\u0027\"`<>*]+") | [splits("\\s+") | select(. != "")] as $w
      | range(0; $w | length) as $i | range($i + 1; ($w | length) + 1) as $j | $w[$i:$j] | join(" ") | sub("[.?!]+$"; "") | (., (sub("^_+"; "") | sub("_+$"; ""))) | norm]
    | if any(. as $p | $e | any(. as $x | $x == "" or $p == $x or ($p | startswith($x + "/")))) then "1" else "" end'
}
# <finding> <worktree>: prints 1 when the finding names a file, and each file it names is one of the worktree's staged
# change (the card's change, as its review read it); a name with no folder counts as the changed file of that name. A
# file it names: a word with a "/" that ends in an extension or a "/", is a tracked path, or starts with a tracked
# top folder (a new file: conveyor/lib/newguard, or in a new folder: conveyor/lib/guards/newguard); or a word that is a tracked file's name or a changed file. A word is a run of
# letters, digits and _.@+/- (so a ":<line>" is not part of it), its leading "./" and closing "." dropped; a word that
# names no file as written is read again with its leading and closing "_" dropped (Markdown emphasis:
# __conveyor/lib/newguard__). Bug it stops: a follow-up that changes another pipeline file let through with no
# one asked.
ownonly() {
  jq -rn --arg f "$1" --rawfile ch <(git -C "$2" diff --cached --no-renames --name-only 2>/dev/null) --rawfile tr <(git -C "$2" ls-files 2>/dev/null) '
    def lines: split("\n") | map(select(. != ""));
    ($ch | lines) as $c | ($tr | lines) as $t | ($t | map(split("/")[-1])) as $tn | ($c | map(split("/")[-1])) as $cn
    | ([$t[] | select(contains("/")) | {key: split("/")[0], value: true}] | from_entries) as $d
    | def named: . != "" and ((contains("/") and (test("\\.[A-Za-z0-9]+$") or endswith("/") or IN($t[]) or $d[split("/")[0]])) or IN($tn[]) or IN($c[]));
    [$f | scan("[A-Za-z0-9_.@+/-]+") | sub("^(\\./)+"; "") | sub("\\.+$"; "")
       | [., (sub("^_+"; "") | sub("_+$"; "") | sub("^(\\./)+"; "") | sub("\\.+$"; ""))] | map(select(named)) | .[0] // empty]
    | if length > 0 and all(IN($c[]) or ((contains("/") | not) and IN($cn[]))) then "1" else "" end'
}
# <worktree>: prints the first finding of its review (<worktree>.review) that quotes a word the privacy check flags
# (privwords(), lib/issues.sh) that names a hit the check finds in the lines the card's staged change adds: the finding's
# word, with its leading and closing marks (quotes, brackets, a closing . or :) aside, as written or with its string
# escapes decoded (\/<home>\/x is /<home>/x; <home> here is the home folder), is at a place in a flagged added word
# (as written or decoded) where every text the check passes to its left (from the added word) and every text it passes
# to its right, with the finding's word between them, is flagged, and no letter, digit, _ or - (or a . or @ before one)
# goes on after it. So $C/<home>/hf (a folder under a variable) is no hit for /<home>/hf, nor is /<home>/hf2, and in
# PATH=/<home>/y/bin:/<home>/x/bin /<home>/x/bin is a hit though /<home>/y/bin is one too. Such a finding is a privacy hit in the card's own change: a follow-up
# would land the hit on main, so the card fixes it (card.sh). A terms file the host file names that cannot be read does not
# stop the check: the built-in patterns are still checked (bug: the gate was off for a home path). Prints nothing when
# the check could not be made.
privown() {
  local f w x t l terms added hits
  added=$(git -C "$1" diff --cached --no-renames -U0 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+ ') || return 0
  hits=$(privwords "$added" 2>/dev/null || privwords "$added" builtin 2>/dev/null) && [ -n "$hits" ] || return 0
  # occ: each place {a, s, e} a flagged added word $a holds the finding's word $w; cuts: each text checked for it: its
  # left and right contexts, and the two with the place between them.
  local occ="def unesc: $UNESCAPE;"'def forms: [., unesc] | map(gsub("[\\n\\r]"; " ")) | unique;
    def occ: ($w | forms | map(select(. != ""))) as $f | [$h | split("\n")[] | select(. != "") | split("\t")[1:] | join("\t") | forms[]] | unique[] as $a
      | $f[] as $x | ($x | length) as $n | range(0; ($a | length) - $n + 1) as $s | select($a[$s:$s + $n] == $x)
      | select($a[$s + $n:] | test("^([A-Za-z0-9_-]|[.@][A-Za-z0-9])") | not) | {a: $a, s: $s, e: ($s + $n)};
    def cuts: occ | . as $o | range(0; $o.s + 1) as $k | range($o.e; ($o.a | length) + 1) as $m | $o.a[$k:$o.s], $o.a[$o.e:$m], $o.a[$k:$m];'
  terms=$(termsfile); t=$(mktemp) || return 0
  while IFS= read -r f; do
    while IFS=$'\t' read -r x w; do
      w=$(sed -E 's/^[^[:alnum:]/~\\]+//; s/[^[:alnum:]]+$//' <<<"$w")
      [ -n "$w" ] || continue
      # Bug: the finding's word as a substring of a flagged added word (PATH=$C/<home>/hf:/<home>/hf2 is flagged for
      # /<home>/hf2, and a finding quoting /<home>/hf matched it), and that word taken out while another hit stayed
      # (/<home>/x/bin in PATH=/<home>/x/bin:/<home>/y/bin, missed).
      jq -rn --arg w "$w" --rawfile h <(printf '%s' "$hits") "$occ"'[cuts] | unique[]' > "$t" || continue
      [ -s "$t" ] || continue
      # A terms file that cannot be read is retried with the built-in patterns, so its error is not printed.
      l=$("$HERE/privacy/check.sh" ${terms:+--terms "$terms"} "$t" 2>/dev/null); [ $? -le 1 ] || l=$("$HERE/privacy/check.sh" "$t"); [ $? -le 1 ] || break 2
      jq -en --arg w "$w" --rawfile h <(printf '%s' "$hits") --arg l "$l" --arg p "$t:" "$occ"'([cuts] | unique) as $c
        | ([$l | split("\n")[] | select(startswith($p)) | ltrimstr($p) | split(":")[0] | {key: $c[tonumber - 1], value: true}] | from_entries) as $hit
        | any(occ; . as $o | all(range(0; $o.s + 1) as $k | select($hit[$o.a[$k:$o.s]] | not)
          | range($o.e; ($o.a | length) + 1) as $m | select($hit[$o.a[$o.e:$m]] | not) | $o.a[$k:$m]; $hit[.] // false))' >/dev/null \
        && { printf '%s\n' "$f"; rm -f "$t"; return 0; }
    done < <(privwords "$f" 2>/dev/null || privwords "$f" builtin 2>/dev/null)
  done < <(leftovers "$1.review")
  rm -f "$t"; return 0
}
# <text>: a follow-up's title, the text cut at 200 characters; a word the cut falls in is dropped, unless it is the
# title's only word. Bug: an example.com address cut at its 200th character read as another address (example.com with its last letter cut),
# which the privacy check flags, so the follow-up was not filed and nothing landed.
futitle() {
  local t=${1:0:200}
  [ ${#1} -le 200 ] || [[ ${1:200:1} == [[:space:]] ]] || [[ $t != *[[:space:]]* ]] || t=${t%[[:space:]]*}
  printf '%s' "$t"
}
unfile() { # <parent issue> <review file> <follow-up issue>...
  local n=$1 r=$2 i j=0 found=(); shift 2
  mapfile -t found < <(tofile "$r")
  for i; do
    gh_write issue close "$i" --reason "not planned" --comment "Conveyor: the card this follows up did not land; withdrawn. The next build of #$n carries this finding in its brief." >/dev/null 2>&1
    printf '#%s %s\n' "$i" "${found[j]:-}" >> "${r%.review}.withdrawn"; j=$((j + 1))
  done
  # The follow-ups that are cards with no GitHub issue (followups() noted each, with its finding, in <review>.fucards) are
  # taken out of the record while no card has picked them, and their findings go to the brief as an issue's do.
  [ ! -s "${r%.review}.fucards" ] || while IFS=$'\t' read -r i j; do
    tcdrop "$i"; printf '%s %s\n' "$i" "$j" >> "${r%.review}.withdrawn"
  done < "${r%.review}.fucards"
  rm -f "${r%.review}.fucards"
}
# rlpick <finding> <cost> <held>: what followups() does with the finding whose fix did not hold on a card the owner's
# standing order lands (rlfind, its block reason's part: resumeplan(), lib/card.sh; landable(), commands/retry.sh), on a
# pipeline file (<cost> not empty). "rl" when the whole finding holds nothing of <held> (heldlist(), lib/standing.sh):
# its follow-up is filed released, and its issue released too, as a filing mark (`control filing on`) would hold it at
# its first sight (adopted(), lib/control.sh). "hold" when it holds something: held, even when review-followup would
# free it. Nothing for another finding. Bugs: the block reason keeps only the finding's first 300 characters, so a
# reserved word after them was released; and free reads auto.reserved alone, so a profile item was released through it.
rlpick() {
  [ -n "$2" ] && [ -n "${rlfind:-}" ] && [[ $1 == "$rlfind"* ]] || return 0
  if [ "$(jq --arg f "$1" 'any(.[]; . as $w | $f | ascii_downcase | contains($w | ascii_downcase))' <<<"$3" 2>/dev/null)" = false ]; then echo rl; else echo hold; fi
}
followups() { # <card> <issue json> <review file>
  local f mark where out num n pn nums=() more=() found=() pipe cost own='' free rl held='' res pm g masked depth kind clean body area nocard='' fc=${3%.review}.fucards
  local why ofc=${3%.review}.outfiled ek healed=0; [ -z "${rlfind:-}" ] || heldlist held || held='' # what waits for the owner, read for the finding of a retry by review-land (rl, below); none read holds it
  depth=$(fudepth "$2") && [[ $depth =~ ^[0-9]+$ ]] || { echo "cannot read the parent issue's follow-up depth"; return 1; }
  packget pipelineFiles pipe || { echo "cannot read the pack's pipeline files"; return 1; }
  packget privacy.mode pm || { echo "cannot read the pack's privacy mode"; return 1; }
  ! standingon review-followup || { packget auto.reserved res || { echo "cannot read the pack's auto.reserved"; return 1; }; own=1; }
  area=$(jq -r --arg p "$AREA" '.labels | map(.name | select(startswith($p))) | .[0] // empty' <<<"$2") || { echo "cannot read the parent issue's labels"; return 1; }
  n=$(jq -r .number <<<"$2") && mapfile -t more < <(jq -r --arg p "$AREA" '(.labels | map(.name | select(startswith($p))) | .[0] // empty | "--label", .),
    (.milestone.title // empty | "--milestone", .)' <<<"$2") || { echo "cannot read the parent issue's labels and milestone"; return 1; }
  # Issue 0's parent is the issue its card follows up, if any (--only takes its follow-ups). pn names it in a follow-up card: #<issue>, else the branch,
  # else the card id (bug: "Review follow-up of #"); a follow-up issue keeps "Follow-up to #<n>", the only form jq/upnext.jq and snapshot.sh read.
  [ "$n" != 0 ] || n=$(tcparent "$1"); [[ $n =~ ^[1-9][0-9]*$ ]] && pn="#$n" || pn=$(stdb ask card "$1" 2>/dev/null | jq -rn 'first(inputs | objects | select(.step == "picked") | .branch | strings) // empty' 2>/dev/null); pn=${pn:-$1}
  mapfile -t found < <(tofile "$3")
  rm -f "$fc" "$ofc"; [ "$(ctl 2>/dev/null | jq -r '.rules.followupissues' 2>/dev/null)" != false ] || nocard=1; [ -n "$nocard" ] || pn="#$n"
  # A finding of the last review the judge sorted as a kind kept off the belt goes to its list (healsadd()), not to a
  # follow-up: the card's own issue, its area, and the card that lands it. At the last review it no longer blocks the
  # card, whatever its level (afterreview(), lib/card.sh). One that cannot be written there lands nothing, so it is not lost.
  while IFS=$'\t' read -r ek why f; do
    healsadd "$1" "$(jq -r .number <<<"$2")" "$area" "$why" "$f" review "$ek" >/dev/null \
      || { echo "a $ek finding could not be written to its list, so nothing landed (finding: ${f:0:200})"; return 1; }
    healed=$((healed + 1))
  done < <(leftovers "$3" | jq -rR --slurpfile e <(jq -c --argjson k "$LISTKINDS" 'select(.effect | IN($k[]))' "${3%.review}.effects" 2>/dev/null) \
    '. as $f | first($e[] | select(.finding == $f)) | [.effect, .reason, .finding] | map(gsub("[[:space:]]+"; " ")) | join("\t")')
  [ ${#found[@]} != 0 ] || { [ "$healed" = 0 ] || { echo '[]'; return 0; }; nofiling "$3"; return 1; }
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
    rl=$(rlpick "$f" "$cost" "$held"); [ "$rl" != hold ] || free=''; [ "$rl" = rl ] || rl='' # the finding of a retry by review-land, released or held
    cost=${cost:+$'\nCost to every card: not assessed'}
    # A finding the reviewer marks [cleanup] (REVIEWT: its fix changes no behaviour, as a comment, dead code or a
    # redundant check) is filed without the pack's type label, so its card skips the bug-card check (card.sh): no test
    # can fail on main for it. Its body says so, and its review judges that the change keeps behaviour. A finding with
    # no such mark is a bug, as before. Bug: such a follow-up was built as a bug and blocked for having no failing test.
    kind=$TYPE clean=''
    if grep -qiE '^(\[[^]]*\][[:space:]]*)*\[cleanup\]' <<<"$f"; then
      kind='' clean=$'\nCleanup: the finding changes no behaviour, so no test has to fail on main for it. The change must keep what the code does: the review judges that it does.'
    fi
    # An outside finding (<worktree>.outside) that the review does not hold as a finding: the judge's reason is its why.
    why=''; leftovers "$3" | grep -Fxq -- "$f" || why=$(jq -r --arg f "$f" 'select(.finding == $f) | .reason' "${3%.review}.outside" 2>/dev/null | head -n 1)
    # Its kind (judged(): the last ruling kept in <worktree>.effects or .outside) and the judge's reason; with none, harm.
    ek=$({ cat "${3%.review}.effects" "${3%.review}.outside" 2>/dev/null || :; } | jq -rn --arg f "$f" \
      '[inputs | objects | select(.finding == $f and (.effect | type) == "string")] | first // empty | "\(.effect): \(.reason)"' 2>/dev/null) || ek=''
    [ -n "$ek" ] || ek='harm (the judge gave it no kind, so it is filed as harm)'
    [ -z "$why" ] || [ "$pm" != public ] || why=$(privmask "$why") \
      || { unfile "$n" "$3" "${nums[@]}"; echo "follow-up not filed, so nothing landed: the privacy check could not be made (finding: ${f:0:200})"; return 1; }
    [ "$pm" != public ] || ek=$(privmask "$ek") \
      || { unfile "$n" "$3" "${nums[@]}"; echo "follow-up not filed, so nothing landed: the privacy check could not be made (finding: ${f:0:200})"; return 1; }
    if [ -n "$why" ]; then
      body="Follow-up to $pn (Conveyor card $1). The judge of that card's review found the finding below real, but not caused by that card's change: $why
The card landed without a fix for it. Fix it in this issue."
    else
      body="Follow-up to $pn (Conveyor card $1). The last review of that card said NO-GO. The card landed without a fix for the finding below. Fix it in this issue."
    fi
    body+="

Finding: $g
Where: ${where:-the finding names no file:line}
Kind: $ek$clean$cost$masked
Follow-up depth: $((depth + 1))"
    if [ -n "$nocard" ]; then
      # The standing yes is logged before the card exists (it has no id yet); one that cannot be logged is held, as an issue is.
      [ -z "$free" ] || standinglog review-followup "a follow-up card of $pn (card $1) was not held: its finding names only files of that card's change: ${f:0:200}" >/dev/null 2>&1 || free=''
      # Its parent's card is filed before it lands: the card waits on that id, as an issue waits on its parent's landed line (jq/upnext.jq).
      # It keeps its parent's area label, as the follow-up issue does (more), so an area set to Never build holds it too.
      num=$(tcadd "" "$(futitle "$g")" "$body"$'\n'"Depends on: $1" "$([ -z "$cost" ] || [ -n "$free$rl" ] || echo held)" "Review follow-up of $pn" "$(jq -cn '$ARGS.positional' --args "$FOLLOWUP" ${kind:+"$kind"} ${mark:+"$mark"} ${area:+"$area"})" "$n") \
        && printf '%s\t%s\n' "$num" "$f" >> "$fc" && { [ -z "$why" ] || jq -cn --arg f "$f" --arg i "$num" '{finding: $f, issue: $i}' >> "$ofc"; } || { unfile "$n" "$3" "${nums[@]}"; echo "follow-up not filed, so nothing landed (finding: ${f:0:200}): its card could not be started"; return 1; }
      continue
    fi
    out=$(gh_write issue create --title "$(futitle "$g")" --label "$FOLLOWUP" ${kind:+--label "$kind"} ${mark:+--label "$mark"} "${more[@]}" --body "$body" 2>&1) && num=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && num=${num##*/} && [ -n "$num" ] \
      || { unfile "$n" "$3" "${nums[@]}"; echo "follow-up not filed, so nothing landed (finding: ${f:0:200}): ${out:0:400}"; return 1; }
    nums+=("$num")
    [ -z "$why" ] || jq -cn --arg f "$f" --argjson i "$num" '{finding: $f, issue: $i}' >> "$ofc" \
      || { unfile "$n" "$3" "${nums[@]}"; echo "follow-up #$num filed, but the engine could not note it as an outside finding's, so nothing landed (finding: ${f:0:200})"; return 1; }
    [ -z "$free" ] || standinglog review-followup "#$num, a follow-up of $pn (card $1), was not held: its finding names only files of that card's change: ${f:0:200}" >/dev/null 2>&1 || free=''
    [ -z "$cost" ] || [ -n "$free$rl" ] || out=$(locked control hold "$num" 2>&1 >/dev/null) \
      || { unfile "$n" "$3" "${nums[@]}"; echo "a follow-up that changes a pipeline file could not be held, so nothing landed (finding: ${f:0:200}): ${out:0:400}"; return 1; }
    [ -z "$rl" ] || out=$(CONVEYOR_RELEASEBY=follow-up locked control release "$num" 2>&1 >/dev/null) \
      || { unfile "$n" "$3" "${nums[@]}"; echo "the follow-up of the finding that blocked the card could not be released, so nothing landed (finding: ${f:0:200}): ${out:0:400}"; return 1; }
  done
  jq -cn '$ARGS.positional | map(tonumber)' --args "${nums[@]}"
}

# A finding whose Proof says it was seen in real logs or records (jq test(), case aside): harm whatever its judge
# says (HARMRULE, lib/review.sh).
# shellcheck disable=SC2034 # read by judged() (lib/review.sh) and healsjudge() (lib/heals.sh)
SEENRX='proof:.*\b(seen|observed)\b[^.]*\b(logs?|records?)\b'
# jq: the one line a finding or a reason is kept as on the self-heals list, which healsunput() (lib/review.sh) matches.
HEALSONE='def one: gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");'
# The judge's kinds that keep a finding off the belt (HARMRULE, lib/review.sh), as a JSON list: self-heals, cleanup and
# already guarded go to the self-heals list, docs drift to the docs list (healsfile()). Any other kind, or none, is harm.
LISTKINDS='["self-heals", "cleanup", "already guarded", "docs drift"]'
healsfile() { if [ "$1" = 'docs drift' ]; then printf '%s\n' "$DOCSDRIFT"; else printf '%s\n' "$SELFHEALS"; fi; } # <kind>: its list
# Whether <reason> names, as file:line, a line of <worktree> that holds text: the check an already-guarded finding names
# as the one that stops its outcome. A path that leaves the worktree (a leading / or a .. part) names none. An
# already-guarded ruling whose reason names no such line is harm (guardless()).
guardat() { # <worktree> <reason>
  local w f l
  while IFS= read -r w; do
    f=${w%:*} l=$((10#${w##*:})) f=${f#./}
    [[ $f != /* && /$f/ != */../* && $l -ge 1 ]] && [ -f "$1/$f" ] && sed -n "${l}p" "$1/$f" 2>/dev/null | grep -q '[^[:space:]]' && return 0
  done < <(grep -oE '[A-Za-z0-9_./-]+:[0-9]{1,9}' <<<"$2")
  return 1
}
# The rulings read from stdin, "<n>\t<reason>" a line, of already-guarded findings: prints the JSON list of the n whose
# reason names no guard found in <worktree> (guardat()). judged() (lib/review.sh) and healsjudge() (lib/heals.sh) rule them harm.
guardless() { # <worktree>
  local n r
  while IFS=$'\t' read -r n r; do guardat "$1" "$r" || printf '%s\n' "$n"; done | jq -cs 'map(tonumber? // empty)'
}
# The reason a guardless already-guarded ruling gets added, as it becomes harm.
# shellcheck disable=SC2034 # read by guardsaid() (lib/review.sh) and healsjudge() (lib/heals.sh)
GUARDLESS=' (it names no check found at a file:line of the code that stops the outcome, so it is harm)'
# A finding sorted as self-heals, cleanup or already guarded goes to the self-heals list (SELFHEALS, lib/paths.sh), and
# one sorted as docs drift to the docs list (DOCSDRIFT), in place of a follow-up or a fix round, once: its id names the
# card and the finding (h for the self-heals list, d for the docs list), and the same one written again adds no line:
# an entry no batch card holds yet takes its kind and reason (a later ruling, as cleanup then already guarded, stands),
# and one a batch card holds stays as it is. On the self-heals list the same finding of a later card is that entry too,
# and one found again after it expired takes its line back from HEALSDROPPED; either way the entry is seen now, and
# the id printed is the entry's own. The finding and the reason are each one line; effect is its kind (self-heals when not given). Prints the
# entry's id. Callers: judged() (lib/review.sh, from: review), followups() (a finding left at a first card's last
# review) and healssort() (lib/heals.sh, from: sort).
healsadd() { # <card> <issue> <area | ""> <why> <finding> <review | sort> [<kind>]
  local l id e=${7:-self-heals} f
  [[ $# -le 7 && $2 =~ ^[0-9]+$ && $1 == *[![:space:]]* && $4 == *[![:space:]]* && $5 == *[![:space:]]* && $6 =~ ^(review|sort)$ ]] \
    && jq -e --arg e "$e" 'index($e) != null' <<<"$LISTKINDS" >/dev/null || return 2
  f=$(healsfile "$e")
  l=$(jq -cn --arg c "$1" --argjson n "$2" --arg a "$3" --arg why "$4" --arg f "$5" --arg from "$6" --arg repo "$REPO" --arg e "$e" \
    "$HEALSONE"'
    {card: $c, issue: $n, repo: $repo, area: (if $a == "" then null else $a end), finding: ($f | one), why: ($why | one), effect: $e, from: $from}') \
    && id=$([ "$f" = "$DOCSDRIFT" ] && echo d || echo h)$(jq -j '.card, "\n", .finding' <<<"$l" | git hash-object --stdin | cut -c1-12) && [ ${#id} = 13 ] || return 1
  ( flock 9 || exit 1
    t=$(clock) || exit 1
    rid=$(healsagain "$f" "$id" "$l" "$t" 1); case $? in
      0) ;;
      3) rid=$id; jq -c --arg id "$id" --arg t "$t" '{id: $id, time: $t} + .' <<<"$l" >> "$f" || exit 1 ;;
      *) exit 1 ;;
    esac
    printf '%s\n' "$rid" ) 9>>"$f.lock" || return 1
}
. "$HERE/lib/healslist.sh" || exit 1 # how a sighting finds its entry (HEALSSAME, healsagain(), healsseen()); after HEALSONE, which it reads as it is sourced
# The ids the batch card <card> of <issue> may be known by on the self-heals list (batched: its issue number, or for a
# card with no GitHub issue its Tests page id, healsbatch(), lib/heals.sh), as a JSON list. <card> may be empty.
healsids() { # <card> <issue>
  local tc=''
  [ -z "$1" ] || tc=$(jq -r --arg c "$1" 'first(.cards[]? | select(.card == $c or .id == $c or ((.was // []) | index($c)))) | .id // empty' "$TACARDS" 2>/dev/null) || tc=''
  jq -cn --arg c "$1" --arg tc "$tc" --argjson n "$2" '[(if $n != 0 then $n else empty end), ($c, $tc | select(. != ""))]'
}
# The entries of the self-heals list and the docs list that the batch card or docs sweep card <card> of <issue> holds
# (healsids()), given back to their list: shut() calls it when it closes that card before it lands, so the next card
# of their area holds them. Each keeps the cards it was given back by (freed), which healstake() reads, and counts its days
# to expire (healsexpire(), lib/heals.sh) from now (seen). Fails when a
# list cannot be written.
healsfree() { # <card> <issue>
  local ids f
  for f in "$SELFHEALS" "$DOCSDRIFT"; do
    grep -qF '"batched":' "$f" 2>/dev/null || continue
    ids=$(healsids "$1" "$2") || return 1
    ( flock 9 || exit 1
      jq -c --argjson ids "$ids" --arg t "$(clock)" 'if type == "object" and .batched != null and (.batched | IN($ids[])) then .freed = ((.freed // []) + [.batched] | unique) | del(.batched) | .seen = $t else . end' \
        "$f" > "$f.new" && mv -f "$f.new" "$f" || { rm -f "$f.new"; exit 1; } ) 9>>"$f.lock" || return 1
  done
}
# `retry` of a batch card or docs sweep card that shut() gave its entries back for (healsfree()): the card builds its
# scope again, so it holds those entries again (batched). When another card holds one of them now, the retry is
# refused (exit 3, nothing changed): both cards would fix the same findings. A card holds the entries of one list
# only. An entry of the self-heals list that expired (healsexpire(), lib/heals.sh) since the card gave it back comes back from
# HEALSDROPPED first, so the card holds it and no review lists it again for a second batch card. retry() calls it before it gives the
# card back. Fails when a list cannot be read or written.
healstake() { # <card> <issue>
  local ids f d
  for f in "$SELFHEALS" "$DOCSDRIFT"; do
    d=$HEALSDROPPED; [ "$f" = "$SELFHEALS" ] || d=/dev/null
    grep -qF '"freed":' "$f" "$d" 2>/dev/null || continue
    ids=$(healsids "$1" "$2") || return 1
    ( flock 9 || exit 1
      other=$(jq -rs --argjson ids "$ids" '[.[] | objects | select(any(.freed[]?; IN($ids[])) and .batched != null and (.batched | IN($ids[]) | not)) | .batched | tostring] | unique | join(", ")' "$f") || exit 1
      [ -z "$other" ] || { echo "conveyor: the findings of this card are held by the batch card $other now; nothing changed" >&2; exit 3; }
      if grep -qF '"freed":' "$d" 2>/dev/null; then
        jq -c --argjson ids "$ids" 'select(type == "object" and any(.freed[]?; IN($ids[]))) | .expired = .dropped | del(.dropped)' "$d" >> "$f" \
          && jq -c --argjson ids "$ids" 'select(type != "object" or (any(.freed[]?; IN($ids[])) | not))' "$d" > "$d.new" && mv -f "$d.new" "$d" || { rm -f "$d.new"; exit 1; }
      fi
      jq -c --argjson ids "$ids" 'if type == "object" and .batched == null and any(.freed[]?; IN($ids[])) then .batched = first(.freed[] | select(IN($ids[]))) else . end' \
        "$f" > "$f.new" && mv -f "$f.new" "$f" || { rm -f "$f.new"; exit 1; } ) 9>>"$f.lock" || return
  done
}
# A finding that is not built goes to the declined list (DECLINED), once: declined again for the same card (the
# reviewer raised it again in a later round), it is the line it has (id names the card and the finding). Declined again
# with another kind (or none after one), that line takes the later kind, its reason and who declined it, and keeps the rest (time,
# built, dismissed), so donotraise() reads the later kind and the Board has one row, and one "File as issue", for the
# finding. The line keeps when the later ruling was made (ruled) and the rulings it replaced (was: [{time, by, why,
# kind}], oldest first), so a replay (replaycases(), lib/replay.sh) gives a judge only the ruling made before it ran.
# Bug: the line kept only the first time, so a replay gave an earlier judge a later kind and reason. Bug: each kind
# was a line of its own, so the finding could be filed twice, and filing one row left the other on the do-not-raise
# list. The review's judge (judged()) and `conveyor.sh declined add` are its callers. The finding
# and the reason are each one line; kind, when given, is the kind of the reason (JUDGE in review.sh), which donotraise()
# reads. Bug: a declined finding left no trace, and the next review raised it again.
declined() { # <card> <issue> <code | judge | owner> <why> <finding> [<kind>]
  local id l
  [[ $# =~ ^[56]$ && $2 =~ ^[0-9]+$ && $3 =~ ^(code|judge|owner)$ && $1 == *[![:space:]]* && $4 == *[![:space:]]* && $5 == *[![:space:]]* ]] \
    && [[ $# = 5 || $6 =~ ^(claim wrong|cannot happen|fixed|rare case|not this change|other)$ ]] \
    || { echo "usage: conveyor.sh declined add <card> <issue> <code | judge | owner> <why> <finding> [claim wrong | cannot happen | fixed | rare case | not this change | other]" >&2; return 2; }
  l=$(jq -cn --arg c "$1" --argjson n "$2" --arg by "$3" --arg why "$4" --arg f "$5" --arg kind "${6:-}" --arg repo "$REPO" \
    'def one: gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; ""); {card: $c, issue: $n, finding: ($f | one), by: $by, why: ($why | one)}
      + (if $kind == "" then {} else {kind: $kind} end) + {repo: $repo}') \
    && id=d$(jq -j '.card, "\n", .finding' <<<"$l" | git hash-object --stdin | cut -c1-12) && [ ${#id} = 13 ] || return 1
  # The time is read once the lock is held, so a ruling is never dated before a writer that held the lock (a
  # `declined build` on its GitHub calls) let it be saved. Bug: dated before the wait, a replay gave a judge that read
  # the list during the wait the ruling it had not seen.
  ( flock 9 || exit 1
    l=$(jq -c --arg t "$(clock)" '{time: $t} + .' <<<"$l") || exit 1
    old=$(stdb ask lines declined 2>/dev/null | jq -c --arg id "$id" 'objects | select(.id == $id)' 2>/dev/null | head -n 1)
    [ -n "$old" ] || { jq -c --arg id "$id" '{id: $id} + .' <<<"$l" | stdb append declined; exit; }
    [ "$(jq -r '.kind // ""' <<<"$old")" != "${6:-}" ] || exit 0
    stdb ask lines declined | jq -c --arg id "$id" --argjson l "$l" 'if .id == $id then ((.was // []) + [{time: (.ruled // .time), by, why} + if .kind then {kind} else {} end]) as $w
      | del(.kind) + ($l | {by, why} + if .kind then {kind} else {} end) + {ruled: $l.time, was: $w} else . end' > "$DECLINED.new" \
      && stdb rewrite declined < "$DECLINED.new" && rm -f "$DECLINED.new" || { rm -f "$DECLINED.new"; exit 1; } ) 9>>"$DECLINED.lock"
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
# the reviewer is still told not to raise it when its kind is one donotraise() lists, and the panel's "Show every
# line" shows it. A line dismissed
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
# characters) and the last 20 declined findings the owner has not asked to be built, each with its reason. Only a line
# whose kind (declined(), the kind the judge wrote, JUDGE in review.sh) is `claim wrong`, `cannot happen` or `fixed` is
# listed: a line of another kind or with no kind (every decline from before kinds were kept, and one by the code or
# the owner) is not, so a finding raised again is judged again. Nothing when the project has neither.
donotraise() {
  local lim dec
  lim=$(awk '/^##? / { on = ($0 ~ /^## +Accepted limits[[:space:]]*$/); next } on' "$MAIN/README.md" 2>/dev/null | sed '/[^[:space:]]/,$!d' | head -c 4000)
  dec=$(stdb ask lines declined 2>/dev/null | jq -r 'select(.built == null and (.kind | IN("claim wrong", "cannot happen", "fixed"))) | "- \(.why) (the finding: \(.finding[0:300]))"' 2>/dev/null | tail -n 20)
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
# Markdown line break): those two alone, as [[:blank:]] takes in other blanks too in a UTF-8 locale (an em space).
# Prints "GO", "NO-GO" or "none".
verdict() { # <review file>
  [ "$(grep '^VERDICT:' "$1" | sed $'s/[ \t]*$//' | sort -u | wc -l)" -eq 1 ] || { echo none; return; }
  case $(tail -n 1 "$1" | sed $'s/[ \t]*$//') in
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
  grep -E "^USER-VISIBLE: ($f)[ "$'\t'"]*\$" "$1" | sed $'s/^USER-VISIBLE: //; s/[ \t]*$//'
}

# The last reply of a session's stream (a Claude result, a Codex agent_message or the text an OpenCode step wrote: its
# text parts, in order, one a line, as OPENCODEANSWER joins them) that holds more than white space, on one line, cut
# to 1000 characters; nothing when it has none. With whole, the reply as it is.
lastreply() { # <session output> [whole]
  jq -Rrjn --arg w "${2:-}" 'reduce (inputs | fromjson? // empty | objects) as $e ({r: [], step: false};
      if $e.type == "step_start" then .step = false
      elif $e.type == "text" and ($e.part.text? | type) == "string" then (if .step then .r[-1] += "\n" + $e.part.text else .r += [$e.part.text] | .step = true end)
      elif $e.type == "result" then .r += [$e.result] | .step = false
      elif $e.type == "item.completed" and $e.item.type? == "agent_message" then .r += [$e.item.text] | .step = false else . end)
    | [.r[] | strings | select(test("\\S"))] | last // "" | if $w != "" then . else [splits("\\s+")] | map(select(. != "")) | join(" ") | .[0:1000] end' "$1" 2>/dev/null
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
# closes as not needed, its closed line saying so; so too when the pack's test command cannot run them alone (no
# test.fileCommand: #1275), as then nothing shows main red the pack's way. Else it is blocked, saying why, whatever its reply says: only that
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
    t="Not needed: the session made no change, and its cases were checked again on main. $(head -n 1 "$wt.unfixed")"
    # Written only while its entry holds no case that did not run (bugproof.sh redclosed()): a case that joined it then keeps it open.
    err=''; res=$(line "$c" "$n" closed ok "$(jq -cn --arg r "$t" --argjson e "$(ending)" --argjson w "$(waited)" '{reason: $r} + $e + $w')") && err=$(locked redclosed "$c" "$res") \
      || { t=${t/, so the card closes as already done/}; ncblock "$c" "$n" "$wt" "${t%.}. ${err:-The engine could not write the closed line.}" "$why"; return; }
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
