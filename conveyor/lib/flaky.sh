# SPDX-License-Identifier: Apache-2.0
# The flaky-test record (README.md, Flaky tests): each time a test case failed and then passed when run again with
# nothing changed, or failed in a card and passed on main (flakycard()). A card's test run that passed on re-run (tests(): <worktree>.first) adds one entry for each case
# that had not passed (flakyrun()); `conveyor.sh flaky add <case> <source> <note>` adds one from outside a card (the
# nightly whole test: a case that failed in the full run and passed alone); `flaky off` adds one the same way and files
# no issue (the Board's Keep a case off, an action that files none). A case it names is kept off card test steps
# (flakyoff()) until its flaky issue closes: the full suite and the whole test on main still run it. It adds no run,
# wait or retry to a card. A push whose pre-push hook failed naming test files that pass alone adds one entry for
# each whole file (flakypush()); a whole file is kept off card test steps only while an issue filed for that file is
# open, and when the push reopens the closed issue last filed for a case of that file (`<file>: <case>`), flakyoff()
# keeps that case off again while it is open.
# $FLAKY keeps {entries: [{case, source, time} + {card, issue} (a card's; with a note: it passed on main, flakycard()) or {note} (flaky add or off)], filed: [{case,
# issue} + {time} (a push's)], the issue last filed for each case}. An entry older than FLAKY_KEEP days is dropped at the next write.
# A case with entries from FLAKY_SOURCES different sources within FLAKY_DAYS days, and no open issue filed for it,
# gets one issue (flakyfile()). One writer at a time: a lock of its own, held through the filing, so two cards that
# add the third entry at once file one issue.
FLAKY=${STATE%/*}/flaky.json
FLAKY_KEEP=30 FLAKY_DAYS=7 FLAKY_SOURCES=3
FLAKY_LABEL=flaky-test
flakyput() { printf '%s\n' "$1" > "$FLAKY.new" && mv -f "$FLAKY.new" "$FLAKY" || { rm -f "$FLAKY.new"; return 1; }; } # <the record>
flaky() { # <source> <entries, a JSON array of {case} and any of {card, issue, note}> [nofile: file no issue]
  local lock rec now c rc=0
  { exec {lock}>>"$FLAKY.lock"; } 2>/dev/null || { echo "conveyor: the flaky-test record could not be locked; nothing added" >&2; return 1; }
  flock "$lock" || { exec {lock}>&-; echo "conveyor: the flaky-test record could not be locked; nothing added" >&2; return 1; }
  now=$(clock)
  rec=$(jq -ce 'objects' "$FLAKY" 2>/dev/null) || rec='{}'
  rec=$(jq -c --arg s "$1" --arg now "$now" --slurpfile add <(printf '%s' "$2") --argjson keep "$FLAKY_KEEP" '$add[0] as $add | ($now | fromdate) as $t
    | .entries = [(.entries | arrays | .[] | objects | select(((.time | fromdate?) // 0) > $t - $keep * 86400)),
        ($add[] | . + {source: $s, time: $now})]
    | .filed = [.filed | arrays | .[] | objects]' <<<"$rec") && flakyput "$rec" \
    || { exec {lock}>&-; echo "conveyor: the flaky-test record could not be written; nothing added" >&2; return 1; }
  [ "${3:-}" = nofile ] || while IFS= read -r c; do flakyfile "$c" "$now" || rc=1; done < <(jq -r '.[].case' <<<"$2" | sort -u)
  exec {lock}>&-; return $rc
}
# `conveyor.sh flaky` drops, as it reads the record and before it adds, each case `<file>: <case>` gone from main's
# checkout ($MAIN), with all its entries and filed issues. Its files: the tracked file at that path or ending in /<file>
# (a runner may name a path from a subfolder), and each test file that names the file (a runner's case files: the
# engine's conveyor.test.sh). Gone: none of them holds the case's name as a word, or there is no such file. Each
# dropped case is said on stderr with its count of entries and its reason; its last filed issue, when open, is closed
# with a comment that names the reason. A case whose issue could not be closed, or whose state was unread, is kept
# for the next read; so is the whole record when main's tracked files cannot be read.
flakyprune() {
  local lock rec tracked c f k w n s why m out gone='[]' files own tests=()
  [ -s "$FLAKY" ] || return 0
  tracked=$(git -C "$MAIN" -c core.quotePath=false ls-files 2>/dev/null) && [ -n "$tracked" ] || return 0
  # Main's test files (testtracked(), lib/issues.sh), as paths, not globs.
  mapfile -d '' -t tests < <(testtracked -z 2>/dev/null); wait $! || return 0
  { exec {lock}>>"$FLAKY.lock"; } 2>/dev/null && flock "$lock" || { echo "conveyor: the flaky-test record could not be locked; nothing dropped" >&2; return 1; }
  rec=$(jq -ce 'objects' "$FLAKY" 2>/dev/null) || { exec {lock}>&-; return 0; }
  while IFS= read -r c; do
    f=${c%%: *} k=${c#*: }
    mapfile -t own < <(F=$f awk '$0 == ENVIRON["F"] || substr($0, length($0) - length(ENVIRON["F"])) == "/" ENVIRON["F"]' <<<"$tracked")
    files=(); [ ${#tests[@]} = 0 ] || mapfile -t files < <(git -C "$MAIN" -c core.quotePath=false --literal-pathspecs grep -lwF -e "${f##*/}" -- "${tests[@]}" 2>/dev/null)
    files+=("${own[@]}")
    # A word: no letter or digit on either side (an engine case is defined as t_<case>, so _ is no part of one). A quote
    # may have a backslash before it, as in a quoted name in the source ('it\'s').
    w=$(sed -e 's/[][\.*^$+?(){}|]/\\&/g' -e 's/['\''"`]/\\\\?&/g' <<<"$k")
    [ ${#files[@]} = 0 ] || ! git -C "$MAIN" grep -qE -e "(^|[^A-Za-z0-9])$w([^A-Za-z0-9]|\$)" -- "${files[@]/#/:(literal)}" 2>/dev/null || continue
    if [ ${#own[@]} = 0 ] && [ "${#files[@]}" = 0 ]; then why="its file $f is not in main's checkout"
    elif [ ${#own[@]} = 0 ]; then why="its file $f is not in main's checkout, and no test file that runs through it holds the case \"$k\""
    else why="the case \"$k\" is no longer in $f or in a test file that runs it"; fi
    n=$(jq -r --arg c "$c" '[.filed[]? | select(.case == $c) | .issue][-1] // empty' <<<"$rec")
    if [ -n "$n" ]; then
      s=$(timeout 20 gh issue view "$n" --json state 2>/dev/null </dev/null | jq -r '.state // ""' 2>/dev/null) || s=''
      if [ "$s" = OPEN ]; then
        out=$(gh_write issue close "$n" --comment "Conveyor: the flaky-test record dropped the case \`$c\`: $why. Nothing is kept off card test steps for it now." 2>&1 </dev/null) \
          || { echo "conveyor: flaky test $c: $why, but #$n could not be closed; kept: $out" >&2; continue; }
      elif [ "$s" != CLOSED ]; then echo "conveyor: flaky test $c: $why, but the state of #$n could not be read; kept" >&2; continue; fi
    fi
    m=$(jq --arg c "$c" '[.entries[]? | select(.case == $c)] | length' <<<"$rec")
    echo "conveyor: flaky test $c: dropped from the flaky-test record with its $m entries${n:+ and #$n}: $why" >&2
    gone=$(jq -c --arg c "$c" '. + [$c]' <<<"$gone")
  done < <(jq -r '[(.entries[]?.case), (.filed[]?.case) | strings | select(test("^.+?: .+$"))] | unique[]' <<<"$rec")
  [ "$gone" = '[]' ] || flakyput "$(jq -c --argjson g "$gone" '.entries = [.entries[]? | select(IN(.case; $g[]) | not)]
    | .filed = [.filed[]? | select(IN(.case; $g[]) | not)]' <<<"$rec")" \
    || { exec {lock}>&-; echo "conveyor: the flaky-test record could not be written; nothing dropped" >&2; return 1; }
  exec {lock}>&-
}
# One issue for a case whose entries come from FLAKY_SOURCES different sources within FLAKY_DAYS days, unless the one
# filed for it last is open; its state unread files none (it may be open), and the next entry asks again. When that
# issue is closed, only the entries made after it closed count, and only they are listed (when GitHub says when). An issue
# GitHub did not take is not kept, so the next entry files it. Its labels: flakylabels() of the case.
flakyfile() { # <case> <now>, under flaky()'s lock
  local rec n state at='' title body labels out
  # The entries that count: the case's, made within FLAKY_DAYS days of now and after $at (when the last filed issue closed).
  local counted='($now | fromdate) as $t | (($at | fromdate?) // 0) as $a
    | def counted: .entries[] | select(.case == $c and (((.time | fromdate?) // 0) as $e | $e > $t - $d * 86400 and $e > $a));'
  rec=$(jq -ce 'objects' "$FLAKY") || return 1
  jq -e --arg c "$1" --arg now "$2" --arg at '' --argjson d "$FLAKY_DAYS" --argjson k "$FLAKY_SOURCES" "$counted"'[counted | .source] | unique | length >= $k' <<<"$rec" >/dev/null || return 0
  n=$(jq -r --arg c "$1" '[.filed[] | select(.case == $c) | .issue][-1] // empty' <<<"$rec")
  if [ -n "$n" ]; then
    state=$(timeout 20 gh issue view "$n" --json state,closedAt 2>/dev/null | jq -r '"\(.state // "")\t\(.closedAt // "")"' 2>/dev/null) || state=''
    at=${state#*$'\t'} state=${state%%$'\t'*}
    [ "$state" = CLOSED ] || { [ "$state" = OPEN ] || echo "conveyor: flaky test $1: the state of #$n could not be read; nothing filed" >&2; return 0; }
    jq -e --arg c "$1" --arg now "$2" --arg at "$at" --argjson d "$FLAKY_DAYS" --argjson k "$FLAKY_SOURCES" "$counted"'[counted | .source] | unique | length >= $k' <<<"$rec" >/dev/null || return 0
  fi
  title="Flaky test: $1 fails at random"; title=${title:0:200}
  body=$(jq -r --arg c "$1" --arg now "$2" --arg at "$at" --argjson d "$FLAKY_DAYS" --argjson k "$FLAKY_SOURCES" "$counted"'
    "The test case `\($c)` failed and then passed (when run again with nothing changed, or on the code of main, in a file the card did not change), from \($k) or more different sources within \($d) days. Until this issue is closed, card test steps are told to keep the case off: it runs only in the full test suite and the whole test on main.\n\nIts entries in the flaky-test record of Conveyor:\n"
    + ([counted
        | "- \(.time) \(.source)" + (if .issue != null then ", issue #\(.issue)" else "" end) + (if (.note // "") != "" then ": \(.note)" else "" end)] | join("\n"))
    + "\n\nMake the test reliable, or remove it.\n\nDone when: the case passes alone and in the whole test."' <<<"$rec") || return 1
  mapfile -t labels < <(flakylabels "$1")
  out=$(gh_write issue create --title "$title" "${labels[@]}" --body "$body" 2>&1); n=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1); n=${n##*/}
  [ -n "$n" ] || { echo "conveyor: flaky test $1: its issue could not be filed: $out" >&2; return 1; }
  flakyput "$(jq -c --arg c "$1" --argjson n "$n" '.filed = [.filed[] | select(.case != $c)] + [{case: $c, issue: $n}]' <<<"$rec")"
}
# The test file a case counts for, for the area label of its issue (filearea(), lib/areas.sh; flakylabels(); fullfix(),
# lib/fulltest.sh): of a case named alone (the full test names one as `apicodex`, as its runner reports it), or of
# `<file>: <case>` whose <file> does not define the case (a runner, as `conveyor/conveyor.test.sh: slotcaseterm`, runs
# cases another file defines), the file of main's test files that defines it (testowners(), lib/testfiles.sh): one
# <file> names, else the first; else <file>, else the name itself (a whole file, or a case no file defines). defs and
# refs go to jq on its input: on a large project they are over the limit of one argument (128 KiB on Linux).
casefile() { # <case>
  local defs refs f='' file='' c=$1
  [[ $1 != *': '* ]] || { file=${1%%: *}; c=${1#*: }; }
  if [[ $c =~ ^[A-Za-z0-9_]+$ ]]; then
    testowners
    f=$(printf '%s\n%s\n' "$defs" "$refs" | jq -rn --arg f "$file" --arg c "$c" '[inputs] as [$d, $r] | ($d[$c] // []) as $o
      | if any($o[]; . == $f) then $f else first($o[] | select(. as $o1 | any($r[$f][]?; . == ($o1 | split("/")[-1])))) // $o[0] // empty end' 2>/dev/null) || f=''
  fi
  printf '%s\n' "${f:-${file:-$1}}"
}
# The labels of a flaky issue, as gh's arguments, one a line: the pack's type, its last priority, the area label of
# <case>'s test file (casefile(): the file that defines the case, else the file <case> names, else <case>) from
# the pack's path-to-area map (filearea(), lib/areas.sh), or with no map <areaPrefix>engine when
# the pack's nonProductAreas names it, and flaky-test (made here when the repo lacks it).
flakylabels() { # <case>
  local a
  printf '%s\n' --label "$TYPE" --label "$(jq -r '.[-1]' <<<"$PRIOS")"
  a=$(filearea "" "$(casefile "$1")") || a=''
  if [ -n "$a" ]; then printf '%s\n' --label "$a"
  elif jq -e --arg a "${AREA}engine" 'index($a)' <<<"$NONPRODUCT" >/dev/null; then printf '%s\n' --label "${AREA}engine"; fi
  printf '%s\n' --label "$FLAKY_LABEL"
  gh_write label create -- "$FLAKY_LABEL" >/dev/null 2>&1 # it fails when the label is there already
}
# A test file flaky again (the owner, 2026-11-20: "A file that fails twice in a week gets reopened, not marked fixed
# again"): again($f; <now, seconds>; <days>) is the issue last filed for the file or a case of it (`<file>: <case>`,
# a runner's name for the case too: caseowners, OWNERS in lib/testfiles.sh, read before it with its defs and refs)
# when the record has entries of them from two or more different sources within <days> days of now (the full test
# writes each case of one run on its own, in different seconds, but under one source: so a source counts once, as in
# flakyfile()), the newest made after that issue was
# filed (a filed line with no time: before every entry); else null. The Tests page names it (testspart(),
# lib/testfiles.sh) and a push's flaky issue reopens it (flakypush()).
FLAKYAGAIN='def mine($f): (.case | strings) | any(caseowners[]; . == $f);
  def again($f; $t; $d): ([.entries | arrays | .[] | objects | select(mine($f) and ((.time | fromdate?) // 0) > $t - $d * 86400)] | sort_by(.time)) as $e
    | ([.filed | arrays | .[] | objects | select(mine($f) and (.issue | type) == "number")] | last) as $i
    | if ([$e[] | .source] | unique | length) >= 2 and $i != null and (($i.time // "") | tostring) < $e[-1].time then $i.issue else null end;'
# A push whose pre-push hook failed naming test files, each of which passed when run alone (pushone(), lib/push.sh):
# one entry of the flaky-test record for each file, its source "push <commit>", and one issue for the files, filed
# held (`control hold`, as a follow-up that changes a pipeline file is), not one each. A file the issue last filed for
# it (or for a case of it) still holds is not filed again: that issue, when open, gets a comment; when closed and the
# file is flaky again (FLAKYAGAIN), it is reopened with a comment that says "flaky again since its fix #<issue>", and
# held. A file whose issue is closed and that is not flaky again goes in the new issue; one whose issue's state is
# unread goes in none (it may be open), and is said. The record's filed list keeps {case: the file, issue, time: when
# it was filed} for each file of a new issue; a reopened issue keeps its own, so the file stays flaky again. Prints {files, issues: the issues that now hold them}; fails when some could not be
# filed, commented, reopened or held.
flakypush() { # <the commit pushed> <the hook's output> <test file>...
  local sha=$1 log=$2 lock rec now f n s out rc=0 put='' q new=() hold=() iss=() labels=() lines defs refs; local -A seen=()
  shift 2
  testowners
  flaky "push ${sha:0:12}" "$(jq -cn '[$ARGS.positional[] | {case: ., note: "failed in the pre-push hook, passed alone"}]' --args "$@")" nofile || rc=1
  { exec {lock}>>"$FLAKY.lock"; } 2>/dev/null && flock "$lock" \
    || { echo "conveyor: the flaky-test record could not be locked; no flaky issue filed" >&2; jq -cn '{files: $ARGS.positional, issues: []}' --args "$@"; return 1; }
  now=$(clock); rec=$(jq -ce 'objects | .filed |= [arrays | .[] | objects]' "$FLAKY" 2>/dev/null) || rec='{"filed": []}'
  # The lines of the hook's output that name the files, for the issue and its comments.
  lines=$(printf '%s\n' "$log" | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\000\r' | grep -F "${@/#/-e}" | head -n 20 | cut -c1-300)
  for f; do
    n=$(jq -r --arg f "$f" --slurpfile defs <(printf '%s' "$defs") --slurpfile refs <(printf '%s' "$refs") "$OWNERS$FLAKYAGAIN"'[.filed[]| select(mine($f)) | .issue | numbers][-1] // empty' <<<"$rec")
    [ -n "$n" ] || { new+=("$f"); continue; }
    s=${seen[$n]:-}
    [ -n "$s" ] || s=$(timeout 20 gh issue view "$n" --json state 2>/dev/null </dev/null | jq -r '.state // ""' 2>/dev/null) || s=''
    # seen: an issue a file before this one found open, or reopened (open now): one comment a push.
    if [ "$s" = OPEN ]; then
      [ -n "${seen[$n]:-}" ] || out=$(gh_write issue comment "$n" --body "The pre-push hook failed again at ${sha:0:12} naming \`$f\`, which passed when run alone, so the push went on." 2>&1 </dev/null) \
        || { echo "conveyor: flaky test $f: #$n could not be given a comment: $out" >&2; rc=1; }
      seen[$n]=$s; iss+=("$n")
    elif [ "$s" = CLOSED ] && jq -e --arg f "$f" --arg now "$now" --argjson d "$FLAKY_DAYS" --slurpfile defs <(printf '%s' "$defs") --slurpfile refs <(printf '%s' "$refs") \
      "$OWNERS$FLAKYAGAIN"'again($f; $now | fromdate; $d) != null' <<<"$rec" >/dev/null; then
      q=''; [ -z "$lines" ] || q=$'\n\nThe lines of the hook that name it:\n```\n'"$(grep -F -e "$f" <<<"$lines")"$'\n```'
      out=$(gh_write issue reopen "$n" --comment "Flaky again since its fix #$n: the pre-push hook failed at ${sha:0:12} naming \`$f\`, which passed when run alone, so the push went on. It was recorded flaky twice within $FLAKY_DAYS days, so this issue is reopened, not filed again.$q" 2>&1 </dev/null) || { echo "conveyor: flaky test $f: #$n could not be reopened: $out" >&2; rc=1; continue; }
      seen[$n]=OPEN; hold+=("$n"); iss+=("$n")
    elif [ "$s" = CLOSED ]; then new+=("$f")
    else echo "conveyor: flaky test $f: the state of #$n could not be read; no flaky issue filed for it" >&2; rc=1; fi
  done
  if [ ${#new[@]} != 0 ]; then
    names >/dev/null 2>&1 || :
    mapfile -t labels < <(flakylabels "${new[0]}") # the area of its first file
    q=''; [ -z "$lines" ] || q=$'\nThe lines of the hook that name them:\n```\n'"$lines"$'\n```\n'
    out=$(gh_write issue create --title "$(printf 'Flaky test: %s failed in the pre-push hook and passed alone' "$(printf '%s, ' "${new[@]}" | sed 's/, $//')" | cut -c1-200)" "${labels[@]}" \
      --body "The pre-push hook failed at ${sha:0:12} naming the test files below. Each passed when run alone, once, on the same commit, so the push went on without the hook.

$(printf -- '- `%s`\n' "${new[@]}")
$q
Make each file pass in the pre-push hook on a busy machine, or remove it.

Done when: each file passes in the pre-push hook and alone." 2>&1 </dev/null); n=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1); n=${n##*/}
    if [ -n "$n" ]; then
      hold+=("$n"); iss+=("$n"); put=1
      rec=$(jq -c --argjson n "$n" --arg t "$now" '.filed = [.filed[] | select(IN(.case; $ARGS.positional[]) | not)] + [$ARGS.positional[] | {case: ., issue: $n, time: $t}]' --args "${new[@]}" <<<"$rec")
    else echo "conveyor: the flaky test files ${new[*]}: their issue could not be filed: $out" >&2; rc=1; fi
  fi
  [ -z "$put" ] || flakyput "$rec" || { echo "conveyor: the flaky-test record could not be written; the issues filed are not kept in it" >&2; rc=1; }
  exec {lock}>&-
  for n in "${hold[@]}"; do out=$(locked control hold "$n" 2>&1 >/dev/null) || { echo "conveyor: flaky issue #$n could not be held: ${out:0:300}" >&2; rc=1; }; done
  jq -cn --argjson i "$(printf '%s\n' "${iss[@]}" | jq -cs 'unique')" '{files: $ARGS.positional, issues: $i}' --args "$@"
  return $rc
}
# A card's test run that passed on re-run (<worktree>.first), recorded by tests() as it ends: one entry for each case
# that had not passed, the card its source (the worktree's name; its issue the number that ends it, none for 0:
# lib/pick.sh). A run again that failed, given its failures (testfails()), adds only the cases that passed in it (PASSEDAGAIN): their
# file passed, or the case printed ok; a case it did not run, or that failed again, is no entry. A batch's run in the
# card's worktree is the card's. A failure here is said and leaves the card as it is.
flakyrun() { # <worktree> [testfails() of the run again, when it failed]
  local e c=${1##*/} n
  n=${c##*-}; [[ $n =~ ^[1-9][0-9]*$ ]] || n=null # a main-red fix card or a land-branch card ends in -0: no issue
  if [ $# -ge 2 ]; then
    # The run's result goes in by file, not as an argument: one argument over 128 KiB fails to start jq on Linux.
    e=$(jq -ce --arg c "$c" --argjson n "$n" --slurpfile l <(printf '%s' "${2:-null}") "$NOTPASSED$PASSEDAGAIN"'$l[0] as $l | [passedagain($l)[] | {case: ., card: $c, issue: $n}] | select(length > 0)' "$1.first" 2>/dev/null) || return 0
  else
    e=$(jq -ce --arg c "$c" --argjson n "$n" "$NOTPASSED"'[notpassed[] | {case: ., card: $c, issue: $n}] | select(length > 0)' "$1.first" 2>/dev/null) || return 0
  fi
  flaky "$c" "$e" || echo "conveyor: card $c: its flaky-test entries were not all recorded" >&2
}
# Issue 1829: a case that failed every run of a card (as on a busy machine) and passed on main got the verdict card
# (mainred.sh verdicts()) and was never a flaky entry, however many cards it failed in. Each such case adds one entry,
# the card its source: its verdict card, and main's run at <main's commit> names it passed (mainprobe() mp: its file
# passed, for a unit naming no case; the case printed ok, for a case), so a case main's run did not run (not started
# for want of room: testfails() host; a case its file does not hold) adds none; a file the card's change (staged in
# <worktree>) adds, edits, renames or deletes is the card's own, and adds none, as does every case when the change
# cannot be read. A second fix round of the card that fails the case again adds no entry (one card is one source:
# flakyfile()). Such an entry (a card's, with a note) keeps the case off card test steps only once its issue is filed
# (flakyoff()). The verdicts stay as they are when the record cannot be written: the card's log gets one line.
flakycard() { # <card> <worktree> <verdicts: [{case, file, verdict}]> <the units main's run names passed: [{file, case}]> <main's commit>
  local chg e err n=${1##*-} w=()
  [ -n "$5" ] && [ "$4" != '[]' ] || return 0
  [[ $n =~ ^[1-9][0-9]*$ ]] || n=null
  chg=$(git -C "$2" -c core.quotePath=false diff --cached --name-only --no-renames HEAD 2>/dev/null) || return 0
  chg=$(jq -cRn '[inputs | select(. != "")]' <<<"$chg") || return 0
  mapfile -t w < <(jq -r --slurpfile p <(printf '%s' "$4") --argjson chg "$chg" '[$p[0][] | if .case == null then .file else "\(.file): \(.case)" end] as $ok
    | .[] | select(.verdict == "card" and (.file | strings) and (.file | IN($chg[]) | not) and (.case | IN($ok[]))) | .case' <<<"$3" 2>/dev/null)
  [ ${#w[@]} != 0 ] || return 0
  # A case the record already has from this card (an earlier fix round) is left out: it is no new sighting.
  e=$(jq -cn --arg k "$1" --argjson n "$n" --arg s "${5:0:12}" --slurpfile r <(jq -ce objects "$FLAKY" 2>/dev/null || echo '{}') '[$r[0].entries[]? | select(.source == $k) | .case] as $had
    | [$ARGS.positional[] | select(IN($had[]) | not)
    | {case: ., card: $k, issue: $n, note: "failed in the card, passed on main at \($s); the card does not change its file"}]' --args "${w[@]}") || e=''
  [ "$e" != '[]' ] || return 0
  # flaky()'s own line for a record it could not lock or write ("; nothing added") is replaced by the card's one line;
  # what it says of an issue it could not file, after the entries were written, is kept as it is.
  if [ -z "$e" ]; then err="conveyor: card $1: the flaky-test record could not be written"
  elif ! err=$(flaky "$1" "$e" 2>&1 >/dev/null) && [[ $err == *'; nothing added'* ]]; then err="conveyor: card $1: the flaky-test record could not be written"; fi
  [ -z "$err" ] || printf '%s\n' "$err" >&2
}
# Of a first run's record ({exit, failures}, tests()), the units that did not pass in it ($l: testfails() of the run
# again) passed in the run again: its file passed, or (a case) the case printed ok. Each as notpassed() names it: a
# file the run's time limit only stopped beside the one that ran out of time is not one; a file its own limit stopped
# (ownLimit) is.
PASSEDAGAIN='def passedagain($l): if ($l | type) != "object" then [] else
  [.failures.files[] | .file as $f | if .cases == [] then [$f, null] else .cases[] | [$f, .name] end] + [(.failures.ownLimit // [])[], (.failures.timeout.file // empty) | [., null]]
  | unique | map(select(. as [$f, $c] | IN($l.passed[]?; $f) or ($c != null and any(($l.okcases + $l.passcases)[]?; .file == $f and IN(.cases[]; $c)))))
  | map(if .[1] == null then .[0] else "\(.[0]): \(.[1])" end) end;'
# The cases the flaky-test record keeps off card test steps (the owner, 2026-11-14): each case it names as
# `<file>: <case>`, and each whole file with an issue filed for it (the owner, 2026-11-25: a file whose command
# cannot run part of it, as #1690's; a whole file with no issue filed, or a case with no file, is never kept off),
# while no issue filed for it has closed since its last entry: none filed yet, the last one open or its state unread, or closed before a newer entry.
# An entry of a case that passed on main (flakycard(): a card's, with a note) is no such entry: one card whose change
# broke a test in another file would else keep it off every later card, and no later card could add its sighting. A case
# whose entries have aged out of the record (FLAKY_KEEP) is still named by its filed issue, so it stays off while that
# issue is open. They run in the full suite and the whole test on main, which are given no such list. tests() adds an
# `ok` line to the card's list (<worktree>.rerun, CONVEYOR_TEST_RERUN) for each, unless the list already names the case
# or its file passed: the command keeps it as passed and does not run it (a command that cannot run part of a file runs
# the file whole). It adds an `off` line for each too, unless a `fail` line names the case: an `ok` line alone is also a
# case that passed in a run killed part-way, which a change that selects it runs again; an `off` case does not run even
# then. A whole file is kept off only while its last filed issue is open or its state unread (a closed one ends it, even
# with a newer entry), and gets a `pass` and an `off` line instead (as cacheoff() keeps a file off), unless a `fail`
# line names the file.
flakyoff() { # <worktree>
  local rec c n f k s add=''
  rec=$(jq -ce 'objects' "$FLAKY" 2>/dev/null) || return 0
  while IFS=$'\t' read -r c n f k; do
    if [ "$n" != - ]; then
      s=$(timeout 20 gh issue view "$n" --json state,closedAt 2>/dev/null | jq -r '"\(.state // "")\t\(.closedAt // "")"' 2>/dev/null) || s=''
      # A whole file: kept off only while its issue is open, so an entry newer than its closing does not keep it off.
      [ "$k" != - ] || [ "${s%%$'\t'*}" != CLOSED ] || continue
      # Closed: kept off only by an entry newer than its closing (when GitHub says when).
      [ "${s%%$'\t'*}" != CLOSED ] || jq -e --arg c "$c" --arg at "${s#*$'\t'}" '$at != "" and any(.entries[]; .case == $c and .time > $at and (.card == null or .note == null))' <<<"$rec" >/dev/null || continue
    fi
    if [ "$k" = - ]; then # a whole file
      ! grep -qxF "fail"$'\t'"$f" "$1.rerun" 2>/dev/null || continue
      grep -qxF "pass"$'\t'"$f" "$1.rerun" 2>/dev/null || add+="pass"$'\t'"$f"$'\n'
      grep -qxF "off"$'\t'"$f" "$1.rerun" 2>/dev/null || add+="off"$'\t'"$f"$'\n'
      continue
    fi
    ! grep -qxF "fail"$'\t'"$f"$'\t'"$k" "$1.rerun" 2>/dev/null || continue
    grep -qxF -e "pass"$'\t'"$f" -e "ok"$'\t'"$f"$'\t'"$k" "$1.rerun" 2>/dev/null || add+="ok"$'\t'"$f"$'\t'"$k"$'\n'
    grep -qxF "off"$'\t'"$f"$'\t'"$k" "$1.rerun" 2>/dev/null || add+="off"$'\t'"$f"$'\t'"$k"$'\n'
  done < <(jq -r '. as $r | [(.entries[]? | select(.card == null or .note == null) | .case), (.filed[]?.case) | strings
      | (capture("^(?<f>.+?): (?<k>.+)$") // (select(. as $c | any($r.filed[]?; .case == $c and .issue != null)) | {f: ., k: "-"}))] | unique[] as $x
    | (if $x.k == "-" then $x.f else "\($x.f): \($x.k)" end) as $c
    | ([$r.filed[]? | select(.case == $c) | .issue][-1] // "-") as $n | [$c, $n, $x.f, $x.k] | @tsv' <<<"$rec") # "-": no issue filed, or no case: a whole file (a tab IFS would join an empty field)
  [ -z "$add" ] || printf '%s' "$add" >> "$1.rerun"
}
