# SPDX-License-Identifier: Apache-2.0
# The flaky-test record (README.md, Flaky tests): each time a test case failed and then passed when run again with
# nothing changed. A card's test run that passed on re-run (tests(): <worktree>.first) adds one entry for each case
# that had not passed (flakyrun()); `conveyor.sh flaky add <case> <source> <note>` adds one from outside a card (the
# nightly whole test: a case that failed in the full run and passed alone); `flaky off` adds one the same way and files
# no issue (the Board's Keep a case off, an action that files none). A case it names is kept off card test steps
# (flakyoff()) until its flaky issue closes: the full suite and the whole test on main still run it. It adds no run,
# wait or retry to a card.
# $FLAKY keeps {entries: [{case, source, time} + {card, issue} (a card's) or {note} (flaky add or off)], filed: [{case,
# issue}], the issue last filed for each case}. An entry older than FLAKY_KEEP days is dropped at the next write.
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
  rec=$(jq -c --arg s "$1" --arg now "$now" --argjson add "$2" --argjson keep "$FLAKY_KEEP" '($now | fromdate) as $t
    | .entries = [(.entries | arrays | .[] | objects | select(((.time | fromdate?) // 0) > $t - $keep * 86400)),
        ($add[] | . + {source: $s, time: $now})]
    | .filed = [.filed | arrays | .[] | objects]' <<<"$rec") && flakyput "$rec" \
    || { exec {lock}>&-; echo "conveyor: the flaky-test record could not be written; nothing added" >&2; return 1; }
  [ "${3:-}" = nofile ] || while IFS= read -r c; do flakyfile "$c" "$now" || rc=1; done < <(jq -r '.[].case' <<<"$2" | sort -u)
  exec {lock}>&-; return $rc
}
# One issue for a case whose entries come from FLAKY_SOURCES different sources within FLAKY_DAYS days, unless the one
# filed for it last is open; its state unread files none (it may be open), and the next entry asks again. An issue
# GitHub did not take is not kept, so the next entry files it. Its labels: the pack's type, its last priority, the
# area label <areaPrefix>engine when the pack's nonProductAreas names it, and flaky-test (made when the repo lacks it).
flakyfile() { # <case> <now>, under flaky()'s lock
  local rec n state title body labels out
  rec=$(jq -ce 'objects' "$FLAKY") || return 1
  jq -e --arg c "$1" --arg now "$2" --argjson d "$FLAKY_DAYS" --argjson k "$FLAKY_SOURCES" '($now | fromdate) as $t
    | [.entries[] | select(.case == $c and ((.time | fromdate?) // 0) > $t - $d * 86400) | .source] | unique | length >= $k' <<<"$rec" >/dev/null || return 0
  n=$(jq -r --arg c "$1" '[.filed[] | select(.case == $c) | .issue][-1] // empty' <<<"$rec")
  if [ -n "$n" ]; then
    state=$(timeout 20 gh issue view "$n" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null) || state=''
    [ "$state" = CLOSED ] || { [ "$state" = OPEN ] || echo "conveyor: flaky test $1: the state of #$n could not be read; nothing filed" >&2; return 0; }
  fi
  title="Flaky test: $1 fails at random"; title=${title:0:200}
  body=$(jq -r --arg c "$1" --arg now "$2" --argjson d "$FLAKY_DAYS" --argjson k "$FLAKY_SOURCES" '($now | fromdate) as $t
    | "The test case `\($c)` failed and then passed when run again, with nothing changed, from \($k) or more different sources within \($d) days. Until this issue is closed, card test steps are told to keep the case off: it runs only in the full test suite and the whole test on main.\n\nIts entries in the flaky-test record of Conveyor:\n"
    + ([.entries[] | select(.case == $c and ((.time | fromdate?) // 0) > $t - $d * 86400)
        | "- \(.time) \(.source)" + (if .issue != null then ", issue #\(.issue)" else "" end) + (if (.note // "") != "" then ": \(.note)" else "" end)] | join("\n"))
    + "\n\nMake the test reliable, or remove it.\n\nDone when: the case passes alone and in the whole test."' <<<"$rec") || return 1
  labels=(--label "$TYPE" --label "$(jq -r '.[-1]' <<<"$PRIOS")")
  ! jq -e --arg a "${AREA}engine" 'index($a)' <<<"$NONPRODUCT" >/dev/null || labels+=(--label "${AREA}engine")
  labels+=(--label "$FLAKY_LABEL")
  gh_write label create -- "$FLAKY_LABEL" >/dev/null 2>&1 # it fails when the label is there already
  out=$(gh_write issue create --title "$title" "${labels[@]}" --body "$body" 2>&1); n=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1); n=${n##*/}
  [ -n "$n" ] || { echo "conveyor: flaky test $1: its issue could not be filed: $out" >&2; return 1; }
  flakyput "$(jq -c --arg c "$1" --argjson n "$n" '.filed = [.filed[] | select(.case != $c)] + [{case: $c, issue: $n}]' <<<"$rec")"
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
    e=$(jq -ce --arg c "$c" --argjson n "$n" --argjson l "${2:-null}" "$NOTPASSED$PASSEDAGAIN"'[passedagain($l)[] | {case: ., card: $c, issue: $n}] | select(length > 0)' "$1.first" 2>/dev/null) || return 0
  else
    e=$(jq -ce --arg c "$c" --argjson n "$n" "$NOTPASSED"'[notpassed[] | {case: ., card: $c, issue: $n}] | select(length > 0)' "$1.first" 2>/dev/null) || return 0
  fi
  flaky "$c" "$e" || echo "conveyor: card $c: its flaky-test entries were not all recorded" >&2
}
# Of a first run's record ({exit, failures}, tests()), the units that did not pass in it ($l: testfails() of the run
# again) passed in the run again: its file passed, or (a case) the case printed ok. Each as notpassed() names it.
PASSEDAGAIN='def passedagain($l): if ($l | type) != "object" then [] else
  [.failures.files[] | .file as $f | if .cases == [] then [$f, null] else .cases[] | [$f, .name] end] + [.failures.timeout.file // empty | [., null]]
  | unique | map(select(. as [$f, $c] | IN($l.passed[]?; $f) or ($c != null and any(($l.okcases + $l.passcases)[]?; .file == $f and IN(.cases[]; $c)))))
  | map(if .[1] == null then .[0] else "\(.[0]): \(.[1])" end) end;'
# The cases the flaky-test record keeps off card test steps (the owner, 2026-11-14): each case it names as
# `<file>: <case>` (a whole file, or a case with no file, is never kept off), while no issue filed for it has closed
# since its last entry: none filed yet, the last one open or its state unread, or closed before a newer entry. A case
# whose entries have aged out of the record (FLAKY_KEEP) is still named by its filed issue, so it stays off while that
# issue is open. They run in the full suite and the whole test on main, which are given no such list. tests() adds an
# `ok` line to the card's list (<worktree>.rerun, CONVEYOR_TEST_RERUN) for each, unless the list already names the case
# or its file passed: the command keeps it as passed and does not run it (a command that cannot run part of a file runs
# the file whole). It adds an `off` line for each too, unless a `fail` line names the case: an `ok` line alone is also a
# case that passed in a run killed part-way, which a change that selects it runs again; an `off` case does not run even
# then.
flakyoff() { # <worktree>
  local rec c n f k s add=''
  rec=$(jq -ce 'objects' "$FLAKY" 2>/dev/null) || return 0
  while IFS=$'\t' read -r c n f k; do
    if [ "$n" != - ]; then
      s=$(timeout 20 gh issue view "$n" --json state,closedAt 2>/dev/null | jq -r '"\(.state // "")\t\(.closedAt // "")"' 2>/dev/null) || s=''
      # Closed: kept off only by an entry newer than its closing (when GitHub says when).
      [ "${s%%$'\t'*}" != CLOSED ] || jq -e --arg c "$c" --arg at "${s#*$'\t'}" '$at != "" and any(.entries[]; .case == $c and .time > $at)' <<<"$rec" >/dev/null || continue
    fi
    ! grep -qxF "fail"$'\t'"$f"$'\t'"$k" "$1.rerun" 2>/dev/null || continue
    grep -qxF -e "pass"$'\t'"$f" -e "ok"$'\t'"$f"$'\t'"$k" "$1.rerun" 2>/dev/null || add+="ok"$'\t'"$f"$'\t'"$k"$'\n'
    grep -qxF "off"$'\t'"$f"$'\t'"$k" "$1.rerun" 2>/dev/null || add+="off"$'\t'"$f"$'\t'"$k"$'\n'
  done < <(jq -r '. as $r | [(.entries[]?.case), (.filed[]?.case) | strings | capture("^(?<f>.+?): (?<k>.+)$")] | unique[] as $x
    | ([$r.filed[]? | select(.case == "\($x.f): \($x.k)") | .issue][-1] // "-") as $n | ["\($x.f): \($x.k)", $n, $x.f, $x.k] | @tsv' <<<"$rec") # "-": no issue filed (a tab IFS would join an empty field)
  [ -z "$add" ] || printf '%s' "$add" >> "$1.rerun"
}
