# SPDX-License-Identifier: Apache-2.0
# Test actions (README.md, Test actions): `conveyor.sh testaction <judge|explain> <test file>` asks the Tests seat
# (the control record's tests: {cli, model, effort}) about one test file of the project, in one headless session that
# needs no code review and files no issue: judge (is the file worth its cost: keep, speed up, split, merge or delete;
# or stabilise, when its failures have a cause in the test; or indirect, when it checks what it protects through a proxy)
# or explain (which card and what cause made it slower). With no Tests seat set it starts nothing and says why (exit 2).
# The session is given the file, its recorded times from the test lines of the card records (times, clocks, timed) and
# from the whole-suite runs, as the Tests page shows them, the
# cards that ran it, its flaky entries, its recent failures, and its newest run of them all, named (testfacts()); explain, with
# each time as the Board that asked shows it (tawhen()), and the window of the rise in its time and the commits in it that changed
# the file or a file linked to it too (tachanges()). It reads a copy of main as it is at the ask, a worktree of
# that commit whose files it cannot write ($CARDS/testactions/<id>, removed when it ends), and finds a gh that refuses
# every call first on its PATH; a Claude session has only Read, Grep and Glob, a Codex one its read-only sandbox and an
# OpenCode one the review's read-only agent (ocrun()). The ask returns once the session has started, or is queued
# behind TAMAX running actions (taqueue()).
# Each action keeps, in $TESTACTS: <id>.json, its record: {id, action, file, project, commit (main's commit at the
# ask, the one it reads), start (the ask while it is
# queued, then its start), end (null while it runs), state (queued, running, done, stopped, failed or timed out), cli,
# model, effort, limit (TESTACTION_TIMEOUT, the seconds it
# may run), zone and hours (explain: its --time, the zone, or null for this machine's, and the clock of its facts' times), verdict (judge: the word its text's last line names, VERDICT: <keep | speed up | split | merge | delete |
# stabilise | indirect> (taverdict()), else "no verdict"; explain: null), hollow and hollowSkipped (judge: the hollow cases its HOLLOW lines name, and the
# HOLLOW lines that could not be read: tahollow()), causes (judge: the causes of its failures its CAUSE lines name,
# tacauses()), waits (judge: the waits its WAIT lines name, tawaits()), direct (judge: the proxy parts its DIRECT lines name, with the cases the file does not define in dropped, tadirectin()), pid (the process to stop while it runs) and reason (failed: why)}; <id>.txt, the
# session's text, written as the session writes it; <id>.events and <id>.err, the CLI's output and its errors. All of
# it stays after the session ends. `conveyor.sh testaction stop <id>` ends that one session and no other, or takes a
# queued one off, unstarted.
# `conveyor.sh testaction run <test file>` is no session: it runs the file alone, now, on a test slot (tafile()).
TESTACTS=${STATE%/*}/testactions
# shellcheck disable=SC2034 # used in lib/mutate.sh and lib/testfiles.sh
MUTS=$TESTACTS/mutations # the mutation checks' records (lib/mutate.sh)
TAVERDICTS='keep|speed up|split|merge|delete|stabilise|indirect'
# The text of a session's output line: Claude's assistant text (stream-json), Codex's agent message (exec --json),
# OpenCode's text part (run --format json); each ended by a newline.
TATEXT='fromjson? // empty | objects | if .type == "assistant" then .message.content[]? | select(.type == "text") | .text | strings | . + "\n"
  elif .type == "item.completed" and .item.type == "agent_message" then .item.text | strings | . + "\n"
  elif .type == "text" then .part.text | strings | . + "\n" else empty end'
# What the judge is asked of the hollow cases; the check of a Fix hollow cases card asks it too (hollowproof(),
# lib/speedproof.sh).
TAHOLLOWASK="name each hollow case of the file, a case that passes without proving anything, on a line of its own: HOLLOW: <case> | <kind> | <one-line reason>. The kind is one of: mock-echo (it only checks that a mock returned what the mock was told to return), text-only (it only checks that a file contains some text), no-assert (it has no assertion), defined-only (it only checks that a value is defined or truthy). Give no HOLLOW line when no case is hollow."
# What it is asked of the waits (#189): the Tests page marks a file Waits when its last run took more than 2 times its
# CPU time on the clock (WAITRATIO, lib/testrun.sh).
TAWAITASK="When its recent runs took more than 2 times their CPU seconds on the clock (clocks against times, or sec against cpu, above), the file waits more than it works: name each wait in it on a line of its own: WAIT: <case> | <kind> | <file:line> | <one-line reason>. The kind is one of: sleep, polling, timeout, lock, network, other. Give no WAIT line when it does not wait."
TAJUDGE="You judge one test file of this project: is it worth what it costs on every test run? Choose one: keep it, speed it up, split it, merge it with another test file (name that file), delete it, stabilise it, or rewrite it as direct checks (indirect). Give the evidence for your choice: its recorded times below, what it tests, whether another test already proves the same behaviour, and why it failed in its recent failures below. A failure with the verdict card is the test doing its job: the change of that card broke what the test checks. Choose stabilise when its failures with the verdict flaky or main have a cause in the test itself: shared state, timing, order, environment or a fixture. For stabilise, name the cause of each failing case on a line of its own: CAUSE: <case> | <kind> | <one-line reason>. The kind is one of: shared state, timing, order, environment, fixture. Say what the file protects, and whether it checks that directly or through a proxy: running other test files or the suite runner, running the real loop, or waiting on a real process with a poll such as wait_until. Choose indirect when it checks through a proxy, and name each proxy part on a line of its own: DIRECT: <what it protects> | <the direct check that would replace it> | <the cases that must keep passing, comma-separated>. A field of a DIRECT line holds no |, and its cases are the names of cases this test file defines. Read the repository as you need. Change nothing: do not write or edit a file, do not file an issue, do not change any state. Beside your verdict, $TAHOLLOWASK $TAWAITASK End your answer with one line: VERDICT: <keep | speed up | split | merge | delete | stabilise | indirect>"
# A judge's lines `<tag>: <case> | <kind> | <reason>`, from its text: each {case, kind, reason}, or false for a line
# that starts with the tag and does not read as a case, one of the kinds and a reason. A line may start with the marks
# of a list, quote or emphasis, as the VERDICT line may.
tatagged() { # <tag> <kinds, as a regex's alternatives> <text file>
  jq -Rnc --arg t "$1:" --arg k "$2" '[inputs | sub("^[\\s*`_>-]+"; "") | select(startswith($t))
      | (capture("^" + $t + "\\s*(?<case>.*?\\S)\\s*\\|\\s*(?<kind>" + $k + ")\\s*\\|\\s*(?<reason>.*?[^\\s*`_])[\\s*`_]*$") // false)]' "$3"
}
# Its HOLLOW lines: {hollow: [{case, kind, reason}], hollowSkipped: the HOLLOW lines that do not read}.
TAHOLLOW='mock-echo|text-only|no-assert|defined-only'
tahollow() { tatagged HOLLOW "$TAHOLLOW" "$1" | jq -c '{hollow: map(objects), hollowSkipped: map(select(. == false)) | length}'; } # <text file>
# Its CAUSE lines (#188): {causes: [{case, kind, reason}]}, the cause in the test of each failing case a stabilise
# verdict names; a CAUSE line that does not read is left out.
TACAUSE='shared state|timing|order|environment|fixture'
tacauses() { tatagged CAUSE "$TACAUSE" "$1" | jq -c '{causes: map(objects)}'; } # <text file>
# Its WAIT lines (#189): {waits: [{case, kind, at, reason}]}, each wait of a file that waits more than it works; at
# is the file and line of the wait. A WAIT line that does not read (no kind of TAWAIT, no file:line) is left out.
TAWAIT='sleep|polling|timeout|lock|network|other'
tawaits() { # <text file>
  jq -Rnc --arg k "$TAWAIT" '{waits: [inputs | sub("^[\\s*`_>-]+"; "") | select(startswith("WAIT:"))
    | capture("^WAIT:\\s*(?<case>.*?\\S)\\s*\\|\\s*(?<kind>" + $k + ")\\s*\\|\\s*`?(?<at>[^|\\s`]+:[0-9]+)`?\\s*\\|\\s*(?<reason>.*?[^\\s*`_])[\\s*`_]*$")]}' "$1"
}
# Its DIRECT lines (#778): {direct: [{protects, check, cases}]}, each proxy part of a file an indirect verdict names:
# what it protects, the direct check that would replace it, and the cases (comma-separated on the line) that must keep
# passing. A DIRECT line that does not read (fewer than three parts, or no case) is left out. The cases are the text
# after the line's last | and the check all between its first and last | (#827), so a | in the check stays in it.
tadirect() { # <text file>
  jq -Rnc '{direct: [inputs | sub("^[\\s*`_>-]+"; "") | select(startswith("DIRECT:"))
    | capture("^DIRECT:\\s*(?<protects>[^|]*?\\S)\\s*\\|\\s*(?<check>.*?\\S)\\s*\\|\\s*(?<cases>[^|]*?[^\\s*`_|])[\\s*`_]*$")
    | .cases |= [split(",")[] | gsub("^[\\s`\"\u0027]+|[\\s`\"\u0027]+$"; "") | select(. != "")] | select(.cases != [])]}' "$1"
}
# The DIRECT lines of <text file> (tadirect()) as the judged <test file> in <worktree> (the judge's commit) has them
# (#827): each line keeps only the cases the file defines (casesgone(), lib/speedproof.sh) and names the others in
# dropped, as a judge may name a case of another test file. A line left with no case is kept: it still names a part.
tadirectin() { # <text file> <worktree> <test file>
  local d g
  d=$(tadirect "$1") && g=$(casesgone "$2" "$3" "$(jq -r '.direct[].cases[]' <<<"$d" | awk '!s[$0]++')") || return 1
  jq -c --arg g "$g" '($g | split("\n") | map(select(. != ""))) as $g
    | .direct |= map((.cases - $g) as $k | (.cases - $k) as $x | .cases = $k | if $x == [] then . else .dropped = $x end)' <<<"$d"
}
# A judge's fields of its record (tarun()), from its text: verdict (taverdict()), hollow and hollowSkipped
# (tahollow()), causes (tacauses()), waits (tawaits()) and direct (tadirectin() of the judged <test file> in
# <worktree>).
tajudged() { # <text file> <worktree> <test file>
  local v hv
  v=$(taverdict "$1")
  hv=$(tahollow "$1" 2>/dev/null) || hv='{"hollow": [], "hollowSkipped": 0}'
  jq -c --argjson v "$v" --slurpfile c <(tacauses "$1" 2>/dev/null || echo '{"causes": []}') --slurpfile w <(tawaits "$1" 2>/dev/null || echo '{"waits": []}') \
    --slurpfile d <(tadirectin "$1" "$2" "$3" 2>/dev/null || echo '{"direct": []}') '{verdict: $v} + . + $c[0] + $w[0] + $d[0]' <<<"$hv"
}
# Its verdict: the word its last line that is not blank names (VERDICT: <one of TAVERDICTS>), in lower case; "no
# verdict" when that line names none.
taverdict() { # <text file>
  local v
  v=$(grep -v '^[[:space:]]*$' "$1" | tail -n 1 | sed -nE "s/^[[:space:]*\`_>-]*VERDICT:[[:space:]*\`_]*($TAVERDICTS)([^[:alpha:]].*)?$/\1/Ip")
  jq -cn --arg v "${v,,}" 'if $v == "" then "no verdict" else $v end'
}
TAEXPLAIN="Explain the slowdown of one test file of this project. From its recorded times below, find when it became slower, which card's change made it slower, and what in that change is the cause. The window of the rise, from its last run at its usual time to its first slower run, and every commit in that window that changed the test file, a file the test map links to it or a file the map shares with most tests, each with its card, changed files and diff, are in the facts below; you have no git. Weigh every commit in that window: do not blame a card only because its run was the first slower one. Read the repository as you need. Change nothing: do not write or edit a file, do not file an issue, do not change any state."
# `conveyor.sh testissue <test file> <title> <body>`: the Board's File an issue about one test file (an Optimize issue,
# "Optimize the test file <file>", or a Rewrite as a direct check issue, "Rewrite the test file <file> as direct
# checks", each checked by speedproof.sh optproof(), or a speed-up; the owner read and edited the title and body), filed through the GitHub write path with the pack's
# type, its last priority and the area label of the test file (filearea(), lib/areas.sh). Each one filed is kept in $TAFILED, one line {time, event: filed, file, issue}, so the
# file's row has its issue (testspart(): the Board's Close its issue as done). It prints the issue's address.
# Run for a Foreman session (the launcher's CONVEYOR_FOREMAN=1, or the session the Foreman's mark, $ST/foreman/session,
# names: Claude Code gives a session's commands its id, CLAUDE_CODE_SESSION_ID), or while the control record's new
# issues start held (or the record cannot be read), it holds the issue in the control record, as the Foreman's
# filing hooks do, which do not see an issue filed here, and says so on stderr: a Foreman's issue is not built
# before the owner's yes. Such an issue is made with the built label, which the pick skips, and has it taken off once
# the hold is in the control record, so no pick between the two takes it.
# With the control record's rules.testissues false (the Rules tab's Cards with no GitHub issue: Tests page actions On,
# #1330) it files no issue: the card starts with no GitHub issue (testcard()), and it prints that, while new issues
# start held too: the owner asked for the card on the Board. One asked for a Foreman session (foreman.sh ask
# <project> testissue) starts held, as the Foreman's issue would: it is not built before the owner's yes.
TAFILED=$TESTACTS/filed.jsonl
# ghunfiled <what> <gh_write's exit> <gh's output>: says a filing printed no link. gh stopped at gh_write()'s time limit
# (124, or 137 once killed) may have had the issue made on GitHub with its answer lost: it is looked for before it is
# filed again (askfiling(), foreman/lib.sh, is stopped later than gh, so this is what the Foreman reads).
ghunfiled() {
  case $2 in
    124 | 137) echo "conveyor: gh was stopped at its time limit before it printed a link: GitHub may have made $1 all the same: look for it in GitHub before you file it again: $3" >&2 ;;
    *) echo "conveyor: $1 could not be filed: $3" >&2 ;;
  esac
}
testissue() { # <test file> <title> <body>
  local out n s='' why='' c fm='' rc a
  [ $# = 3 ] && [[ -n ${2//[[:space:]]/} && $2 != *$'\n'* && -n ${3//[[:space:]]/} ]] || { echo "usage: conveyor.sh testissue <test file> <title> <body>" >&2; return 2; }
  [[ -n $1 && $1 != /* && /$1/ != */../* && /$1/ != */./* && $1 != *$'\n'* ]] && [ "$(git -C "$MAIN" cat-file -t "refs/heads/$BRANCH:$1" 2>/dev/null)" = blob ] \
    || { echo "conveyor: $1 is not a file of $BRANCH; nothing filed" >&2; return 2; }
  mkdir -p "$TESTACTS" || { echo "conveyor: the test actions' folder could not be made; nothing filed" >&2; return 1; }
  read -r s _ 2>/dev/null < "$ST/foreman/session"
  c=$(ctl 2>/dev/null) || c=''; a=$(filearea "" "$1") || a='' # the area label of its test file (lib/areas.sh)
  if [ "${CONVEYOR_FOREMAN:-}" = 1 ] || { [ -n "$s" ] && [ "${CLAUDE_CODE_SESSION_ID:-}" = "$s" ]; }; then why='it was filed for a Foreman session' fm=1
  else case $(jq -r '.start // empty' <<<"$c" 2>/dev/null) in queue) ;; held) why='new issues start held' ;; *) why='the control record cannot be read' ;; esac; fi
  if [ "$(jq -r '.rules.testissues' <<<"$c" 2>/dev/null)" = false ]; then testcard "$@" "${fm:+held}"; return; fi
  # An issue to be held is made with the built label, which the pick skips, until the hold is in the control record.
  out=$(gh_write issue create --title "${2:0:200}" --label "$TYPE" --label "$(jq -r '.[-1]' <<<"$PRIOS")" ${a:+--label "$a"} ${why:+--label "$BUILT"} --body "$3" 2>&1); rc=$?; n=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1); n=${n##*/}
  [ -n "$n" ] || { ghunfiled "the issue about $1" "$rc" "$out"; return 1; }
  grep -oE '[^[:space:]]*/issues/[0-9]+' <<<"$out" | tail -n 1 # at once, as cardnew() prints it
  jq -cn --arg t "$(clock)" --arg f "$1" --argjson n "$n" '{time: $t, event: "filed", file: $f, issue: $n}' >> "$TAFILED" \
    || echo "conveyor: #$n is filed, but its record could not be written: the row of $1 does not show it" >&2
  if [ -n "$why" ]; then
    if ! locked control hold "$n" > /dev/null 2>&1; then echo "conveyor: #$n is filed, but could not be held ($why): hold it (conveyor.sh control hold $n) unless the owner has said yes to it, and take the $BUILT label off it, which the belt skips" >&2
    elif gh_write issue edit "$n" --remove-label "$BUILT" > /dev/null 2>&1; then echo "conveyor: #$n is held, as $why: release it (conveyor.sh control release $n) once the owner says yes" >&2
    else echo "conveyor: #$n is held, as $why, but the $BUILT label could not be taken off it: take it off before you release it (conveyor.sh control release $n), as the belt skips an issue with it" >&2; fi
  fi
}
# A card with no GitHub issue (testissue() with rules.testissues false, #1330; a Foreman order, a review follow-up, a release
# fix card or a split part with its rule false: cardnew(), followups(), splitcards()), a card of issue 0 as a main-red fix
# card is. $TACARDS keeps {cards: [{file, label, labels, parent, title, body, time, id, card, held, was, filed, filedUrl}]}: the test file
# (null for a card of another kind, which has its label, the name the Board shows it by, its stand-in issue's labels and, for a
# review follow-up or a split part, its parent issue instead),
# the title and body the action would have filed, when it was asked, its card id (id, made here, so another card can
# wait on it before it is picked: testpick()), card, null until the loop picks it (testpick()), held (true until
# `control release <id>`: testcardact(), lib/testcardact.sh), was (the cards of it given back, oldest first) and filed and filedUrl (the
# issue File on GitHub filed from it: cardissue()). One writer at a time (a lock of its own). It keeps every card not
# picked yet, the newest 200 picked ones (card() reads a picked card's record while it builds, and the Board's Landed
# today shows a landed one's) and the older ones tcadd() keeps. Prints that the card is queued; one held also says on
# stderr how to release it.
TACARDS=$TESTACTS/cards.json
testcard() { # <test file> <title> <body> [held [<why it is held>]]
  local id
  id=$(tcadd "$1" "$2" "$3" "${4:-}") || return 1
  [ "${4:-}" != held ] || echo "conveyor: card $id is held, ${5:-as it was asked for a Foreman session}: release it (conveyor.sh control release $id) once the owner says yes" >&2
  echo "Card queued with no GitHub issue: ${2:0:200}"
}
# The record's one writer, for every kind of card with no GitHub issue: <test file> "" for a card of another kind, which
# the Board shows by <label> (a Foreman order, a review follow-up, a release fix card or a split part: cardnew(),
# followups(), splitcards()) in place of "Tests page: <file>"; <labels json> the labels its stand-in issue has
# (testcardissue()), the pack's type and last priority when none, with an area label added when they have none (that
# of <test file>, else of the file <body> names, else the map's other: filearea(), lib/areas.sh; none with no map); <parent> the issue a review follow-up or a split part
# follows up (parent in the entry: a run limited by --only to that issue takes the card, testpick()). Prints the card's id.
tcadd() { # <test file> <title> <body> <"held" or ""> [<label> [<labels json> [<parent issue>]]]
  local lock rc=0; mkdir -p "$TESTACTS" 2>/dev/null
  { exec {lock}>>"$TACARDS.lock"; } 2>/dev/null && flock "$lock" || { echo "conveyor: the record of the Tests page's cards could not be locked; no card started" >&2; return 1; }
  tcput "$@" || rc=1; exec {lock}>&-; return $rc
}
tcput() { local rec id drop; rec=$(jq -ce '.cards | arrays' "$TACARDS" 2>/dev/null) || rec='[]' # tcadd() with TACARDS.lock held by the caller (tcadd(), healsbatch())
  id=$(tcfree "$rec")
  # The picked cards the trim may drop (none with the records unread): those whose work is on main (TADONE), but one whose
  # proof deleted or merged its test file (bugproof speed.fix), the only source of its removed mark (testspart()). A card
  # blocked, open or given back (`retry`) keeps its entry, which the loop picks it again by (testpick()).
  drop=$({ stdb ask issue cards 0 || echo '"unread"'; } | jq -cn --arg shut "$SHUT" --arg own "$OWNSHUT" --arg eng "$ENGSHUT" '[inputs] | if any(.[]; . == "unread") then {}
    else [.[] | objects | select((.card | type) == "string")] | group_by(.card)
      | map(select(any(.[]; '"$TADONE"') and (any(.[]; .step == "bugproof" and (.speed.fix? | IN("deleted", "merged"))) | not)) | {key: .[0].card, value: true}) | from_entries end' 2>/dev/null) || drop='{}'
  # The record goes to jq on its input: Linux refuses an argument over 128 KiB.
  jq -c --arg f "$1" --arg t "${2:0:200}" --arg b "$3" --arg at "$(clock)" --arg id "$id" --arg held "${4:-}" --arg label "${5:-}" --arg labels "${6:-}" --arg parent "${7:-}" --argjson drop "$drop" \
    --arg area "$(filearea "" "${1:-$3}" 2>/dev/null)" --arg ap "${AREA:-}" --arg ty "${TYPE:-}" --argjson pr "${PRIOS:-[]}" \
    '. + [{file: (if $f == "" then null else $f end), title: $t, body: $b, time: $at, id: $id, card: null}
      + (if $held == "held" then {held: true} else {} end) + (if $label == "" then {} else {label: $label} end)
      + (($labels | if . == "" then null else fromjson end) as $l | if $area == "" or any(($l // [])[]; startswith($ap)) then (if $l == null then {} else {labels: $l} end)
         else {labels: (($l // [$ty, $pr[-1]]) + [$area])} end)
      + (if $parent == "" then {} else {parent: ($parent | tonumber)} end)]
    | ([to_entries[] | select(.value.card != null) | .key] | .[:-200]) as $old
    | {cards: [to_entries[] | select((.key | IN($old[])) and $drop[.value.card] == true | not) | .value]}' <<<"$rec" > "$TACARDS.new" \
    && mv -f "$TACARDS.new" "$TACARDS" || { rm -f "$TACARDS.new"; echo "conveyor: the record of the Tests page's cards could not be written; no card started" >&2; return 1; }
  echo "$id"
}
# `conveyor.sh card [--release <version>] <title> <body>`: a card the Foreman's owner ordered (the Foreman runs it as
# `foreman.sh ask <project> card ...`), or with --release the fix card of a red test file of a release's suite, whose body
# then has the line `Release fix: <version>` (relfixes(), lib/fulltest.sh). An order that files an issue (it has the pack's
# type label, as a fix issue has) is refused with no `## Cause` section, as the Foreman's filing hook refuses a fix issue.
# With the control record's rules.foremanissues (rules.releaseissues for --release) false (the Rules tab's Cards with no
# GitHub issue) it starts a card with no GitHub issue (tcadd()), held until the owner's yes, as an issue the Foreman files
# is. Otherwise it files the issue, with the pack's type and last priority and the area label of the file its body, else its title, names (cardarea(), lib/areas.sh), and holds it; the issue is made with the
# built label, which the pick skips, taken off once the hold is in the control record. Prints what it started or filed.
cardnew() { # [--release <version>] <title> <body>
  local rule=foremanissues label='Foreman order' body='' out n u nocard rc a
  [ "${1:-}" != --release ] || { [[ ${2:-} =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]] || { echo "usage: conveyor.sh card [--release <version>] <title> <body>" >&2; return 2; }
    rule=releaseissues label='Release fix'; body=$'\n\nRelease fix: '$2; shift 2; }
  [ $# = 2 ] && [[ -n ${1//[[:space:]]/} && $1 != *$'\n'* && -n ${2//[[:space:]]/} ]] || { echo "usage: conveyor.sh card [--release <version>] <title> <body>" >&2; return 2; }
  body=$2$body; a=$(cardarea "$1" "$body") || a=''
  nocard=$(ctl 2>/dev/null | jq -r --arg r "$rule" '.rules[$r] == false' 2>/dev/null)
  if [ "$nocard" != true ] && ! grep -qE '^[[:space:]]*##[[:space:]]+Cause[[:space:]]*$' <<<"$body"; then
    echo 'conveyor: an order that files an issue files a fix issue (it has the pack'"'"'s type label), and a fix issue needs a "## Cause" section: the source of the problem, a place in the code that already solves the same problem (or that none was found), and what the reader sees when the data is stale or missing. Add it and run the command again.' >&2; return 2
  fi
  if [ "$nocard" = true ]; then
    n=$(tcadd "" "$1" "$body" held "$label" ${a:+"$(jq -cn --arg t "$TYPE" --argjson p "$PRIOS" --arg a "$a" '[$t, $p[-1], $a]')"}) || return 1
    echo "conveyor: card $n is held, as it was asked for a Foreman session: release it (conveyor.sh control release $n) once the owner says yes" >&2
    echo "Card queued with no GitHub issue: ${1:0:200}"; return 0
  fi
  # Made with the built label, which the pick skips, until the hold is in the control record (as testissue() does).
  out=$(gh_write issue create --title "${1:0:200}" --label "$TYPE" --label "$(jq -r '.[-1]' <<<"$PRIOS")" ${a:+--label "$a"} --label "$BUILT" --body "$body" 2>&1); rc=$?; u=$(grep -oE '[^[:space:]]*/issues/[0-9]+' <<<"$out" | tail -n 1); n=${u##*/}
  [ -n "$n" ] || { ghunfiled "the issue" "$rc" "$out"; return 1; }
  echo "$u" # at once: an ask stopped at its limit while the hold waits still has the link (askfiling(), foreman/lib.sh)
  if ! locked control hold "$n" > /dev/null 2>&1; then echo "conveyor: #$n is filed, but could not be held: hold it (conveyor.sh control hold $n) unless the owner has said yes to it, and take the $BUILT label off it, which the belt skips" >&2
  elif gh_write issue edit "$n" --remove-label "$BUILT" > /dev/null 2>&1; then echo "conveyor: #$n is held, as it was filed for a Foreman session: release it (conveyor.sh control release $n) once the owner says yes" >&2
  else echo "conveyor: #$n is held, as it was filed for a Foreman session, but the $BUILT label could not be taken off it: take it off before you release it (conveyor.sh control release $n), as the belt skips an issue with it" >&2; fi
}
# Takes the entry of <card id> out of the record while no card has picked it (a follow-up withdrawn: unfile()). A picked
# one stays: its card is on the belt. One writer at a time, as tcadd() is.
tcdrop() { # <card id>
  local lock rec
  { exec {lock}>>"$TACARDS.lock"; } 2>/dev/null && flock "$lock" || return 1
  rec=$(jq -ce '.cards | arrays' "$TACARDS" 2>/dev/null) || { exec {lock}>&-; return 1; }
  jq -c --arg c "$1" '{cards: map(select(.id != $c or .card != null))}' <<<"$rec" > "$TACARDS.new" && mv -f "$TACARDS.new" "$TACARDS" || rm -f "$TACARDS.new"
  exec {lock}>&-
}
# A card id no card has yet: its second, its project and its issue 0, as every card of issue 0 is named. One that a
# card of the records, a retried line or an entry of the record given (its id, its card or one of its was) has waits
# for the next second.
tcfree() { # <the record's cards json>
  local card
  while card="c$(date -u +%Y%m%dT%H%M%S)-$CTAG-0"; [ -n "$(stdb ask card "$card")" ] || stdb ask lines retried | grep -F "\"card\":\"$card\"" >/dev/null \
    || jq -e --arg c "$card" 'any(.[]; . as $e | $c | IN($e.id, $e.card, ($e.was // [])[]))' <<<"$1" >/dev/null; do sleep 1; done
  printf '%s' "$card"
}
# Under the lock (pick()), after the main-red fix cards and ahead of the queue: the oldest card with no GitHub issue
# that is not picked yet, not held (testcardact()), and whose `Depends on:` lines name no card id (c<date>T<time>-<project>-<issue>,
# 0 for a card of no issue) that has not landed or ended as already done (TADONE): the card of that id, or the card now of the entry
# that id is or was, and no issue (#N) that is open and has not landed (waitsof(), as upnext() reads it), and that has none of
# its labels set to never build (rules.never). A review follow-up's body names its parent card so, so it waits for its parent to land. Any size: no split
# check reads it (card()). It is picked as its own id the first time, under a new id after that. Its picked line has
# the action's title and its test file (testFile), which the Board shows it by. Prints "<card> 0 false", `wait` when
# the machine holds it back, nothing when no card waits. A card whose lines left the card records (`retry <card id>`,
# lib/issues.sh, or a stop of the loop, lib/run.sh) is given back: its entry is picked again, the card it was added
# to was, so the new card starts from its kept work (resumeplan(), lib/card.sh). First, a card blocked the first time
# is given back so, with no one asked (TCRETRY on its blocked line); blocked again, it stays blocked, for the owner in
# Needs you. Not one stopped for the owner's yes: that waits on the owner, not on a second try. With the records of
# issue 0 unread, nothing is retried, and only a card not picked yet is picked.
TCRETRY='retried once with its kept work: a card with no GitHub issue is tried again once before it goes to the owner'
# A card record line (a jq filter, with $shut, $own and $eng the SHUT, OWNSHUT and ENGSHUT reasons) that ends a card whose work is on main: it
# landed, or it ended closed because main already did what it asks (closed(), lib/followups.sh: ALREADY-DONE), as umbrellas() reads
# an issue's slice. A card shut by hand is not one. A card that depends on it by its id, or an umbrella it is a part of, goes
# on from there (testpick(), umbrellas()).
TADONE='(.step == "landed" or (.step == "closed" and ((.reason // "") | IN($shut, $own, $eng) | not)))'
# A run limited by --only (ONLY, a json list of issues) takes only the cards that follow up one of them (parent: a review follow-up
# or a split part), as it takes their issues': an issue it names grows to its GitHub parts (an open parent's, and each open issue whose umbrella it is) and the follow-ups of its cards, as
# upnext() grows it (jq/upnext.jq), so a follow-up of a part of a named umbrella is taken; with the Follow-ups rule off (rules.followups false) no follow-up card or split part
# is taken, as no follow-up issue is (jq/upnext.jq): a card is one by its follow-up label.
testpick() { # <the open issues json>
  local lock rec i l card have h=1 old fuoff never open cards c far parts
  [ -s "$TACARDS" ] || return 0
  { exec {lock}>>"$TACARDS.lock"; } 2>/dev/null && flock "$lock" || { echo "conveyor: the record of the Tests page's cards could not be locked; its cards wait" >&2; return 1; }
  rec=$(jq -ce '.cards | arrays' "$TACARDS" 2>/dev/null) || rec='[]'
  c=$(ctl 2>/dev/null) || c=null
  fuoff=$(jq -r 'if .rules.followups == false then true else false end' <<<"$c" 2>/dev/null) || fuoff=false
  never=$(jq -c '.rules.never // []' <<<"$c" 2>/dev/null) || never='[]'
  open=$(jq -c 'map(.number)' <<<"${1:-[]}" 2>/dev/null) || open='[]'
  parts=$(jq -c '[(.[] | select((.parts // []) != []) | {k: .number, v: [.parts[] | .number | numbers]}), (.[] | select(.umbrella | numbers) | {k: .umbrella, v: [.number]})] | group_by(.k) | map({key: (.[0].k | tostring), value: (map(.v[]) | unique)}) | from_entries' <<<"${1:-[]}" 2>/dev/null) || parts='{}'
  # The unheld cards not picked yet are read as an issue is: the state of each issue of another repository their `Depends on:` lines name is asked now (farstates()).
  # A card given back (card set, its lines gone) is picked again, so it is asked as one not picked yet is; one that landed is not picked again, so it is not asked.
  have=$(stdb ask issue cards 0) || h=0
  far=$(farstates "$(printf '%s\n%s\n' "$rec" "$have" | jq -Rcn --arg shut "$SHUT" --arg own "$OWNSHUT" --arg eng "$ENGSHUT" 'input | fromjson as $r
    | ([inputs | fromjson? | objects | select('"$TADONE"') | .card | strings] | INDEX(.)) as $landed
    | $r | map(if (.held | not) and $landed[.card // ""] == null then {body} else {} end)')") \
    && rec=$(jq -c --argjson f "$far" '[., $f] | transpose | map(.[0] + (.[1] | if .far then {far} else {} end))' <<<"$rec") \
    || { exec {lock}>&-; echo "conveyor: the issues of other repositories the Tests page's cards depend on could not be read; its cards wait" >&2; return 1; }
  cards=$(recs) || { exec {lock}>&-; return 1; }
  if [ "$h" = 1 ] && [ -z "${ONLY:-}" ]; then
    while read -r old; do
      RETRYWHY=$TCRETRY retry "$old" > /dev/null 2>&1 && echo "conveyor: card $old: $TCRETRY" >&2
    done < <(printf '%s\n%s\n' "$rec" "$have" | jq -Rrn --arg yes "$YES" --arg lintyes "$LINTYES" 'input | fromjson as $r
      | ([inputs | fromjson? | objects | select(.step | IN("landed", "closed", "blocked", "pushed"))] | group_by(.card) | map({key: .[0].card, value: last}) | from_entries) as $end
      | $r[] | select(.card != null and (.was // []) == []) | $end[.card] | select(. != null and .step == "blocked" and ((.reason // "") | startswith($yes) or startswith($lintyes) | not)) | .card')
    have=$(stdb ask issue cards 0) || h=0
  fi
  # The cards of an issue that a `Depends on:` line names (a review follow-up's parent card): their lines are read too.
  while read -r old; do
    [ -z "$old" ] || have+=$'\n'$(stdb ask card "$old" 2>/dev/null)
  done < <(jq -r '.[] | (.body // "") | splits("\r?\n") | select(test("^\\s*Depends on:")) | scan("c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]*-[1-9][0-9]*(?![A-Za-z0-9_])")' <<<"$rec" | sort -u)
  while read -r i; do
    room 0 >/dev/null || { exec {lock}>&-; echo wait; return 0; }
    card=$(jq -r --argjson i "$i" '.[$i] | select(.card == null) | .id // empty' <<<"$rec")
    if [ -z "$card" ] || [ -n "$(stdb ask card "$card")" ] || stdb ask lines retried | grep -F "\"card\":\"$card\"" >/dev/null; then card=$(tcfree "$rec"); fi
    jq -c --argjson i "$i" --arg c "$card" '{cards: (.[$i] |= ((if .card == null then . else .was = (.was // []) + [.card] end) | .card = $c))}' <<<"$rec" > "$TACARDS.new" && mv -f "$TACARDS.new" "$TACARDS" \
      && l=$(line "$card" 0 picked ok "$(jq -c --argjson i "$i" '.[$i] | {title} + (if .file != null then {testFile: .file} else {noIssue: (.label // "Card")} end)' <<<"$rec")") && append "$l" \
      || { rm -f "$TACARDS.new"; exec {lock}>&-; echo "conveyor: the Tests page's card about $(jq -r --argjson i "$i" '.[$i] | .file // .title' <<<"$rec") could not be picked" >&2; return 1; }
    exec {lock}>&-; echo "$card 0 false"; return 0
  # The record and the lines go to jq on its input: Linux refuses an argument over 128 KiB.
  done < <(printf '%s\n%s\n' "$rec" "$have" | jq -Rrn --argjson h "$h" --argjson only "${ONLY:-null}" --argjson fuoff "${fuoff:-false}" --argjson never "${never:-[]}" --argjson open "${open:-[]}" --argjson parts "$parts" \
    --slurpfile cards <(printf '%s' "$cards") --arg fu "$FOLLOWUP" --arg shut "$SHUT" --arg own "$OWNSHUT" --arg eng "$ENGSHUT" \
    "$DEPS"'input | fromjson as $r | [inputs | fromjson? | objects] as $l
    | ($l | map(.card | strings) | INDEX(.)) as $have | ($l | map(select('"$TADONE"') | .card) | INDEX(.)) as $landed
    | landed($cards) as $idone | ($cards | map(select(.followups))) as $fc
    | def withparts: . as $o | . + [$o[] | $parts[tostring] // [] | .[]] | unique;
      def grow: . as $o | (ups($fc; $o) | withparts) as $n | if $n == ($o | unique) then $n else $n | grow end;
      (if $only == null then null else $only | grow end) as $only
    | def cardlanded($d): ((first($r[] | . as $e | select($d | IN($e.id, $e.card, ($e.was // [])[]))) | .card) // $d) as $k | $landed[$k] != null;
    $r | to_entries[] | select((.value.held | not) and (.value.card == null or ($h == 1 and $have[.value.card] == null))
      and ($only == null or (.value.parent | IN($only[]))) and (($fuoff | not) or ((.value.labels // []) | index($fu) == null))
      and ((.value.labels // []) | any(IN($never[])) | not)
      and (.value | [ups($fc; needs)[] | select(IN($open[]) and (IN($idone[]) | not))] == [])
      and (.value | [farneeds[] as $x | select(.far[$x].open != false) | $x] == [])
      and all(.value.body // "" | splits("\r?\n") | select(test("^\\s*Depends on:")) | scan("c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]*-[0-9]+(?![A-Za-z0-9_])"); cardlanded(.))) | .key')
  exec {lock}>&-
}
# The cards given back of a card with no GitHub issue (its entry's was, testpick()), oldest first, one a line, whose
# kept work it starts from (resumeplan(), lib/card.sh); nothing for another card.
testcardwas() { # <card>
  [ -n "$1" ] && jq -r --arg c "$1" 'first(.cards[]? | select(.card == $c)) | (.was // [])[]' "$TACARDS" 2>/dev/null
}
# The issue a card with no GitHub issue follows up (its entry's parent: a review follow-up or a split part), 0 for any other card.
# A follow-up of such a card follows up that issue too, so its body names it, and its brief reads that issue's yes (inherit()).
tcparent() { # <card>
  [ -n "$1" ] && jq -r --arg c "$1" 'first(.cards[]? | select(.card == $c)) | .parent // 0' "$TACARDS" 2>/dev/null || echo 0
}
# `conveyor.sh cardissue <card id>`: the Board's File on GitHub on a landed card with no GitHub issue (testcard()).
# It files an issue with the card's title and body through the GitHub write path, and closes it at once with a
# comment that names the commit the card landed as: its work is on main, so the belt does not build it again. The
# issue is kept on the entry (filed, filedUrl), which Landed today links; a second ask files none and prints it again.
# One ask at a time (a lock of its own). Prints the issue's address.
cardissue() { # <card id>
  local lock fl rec e sha out n u a
  [ $# = 1 ] && [[ $1 =~ ^c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0$ ]] || { echo "usage: conveyor.sh cardissue <card id>" >&2; return 2; }
  { exec {fl}>>"$TACARDS.file.lock"; } 2>/dev/null && flock "$fl" || { echo "conveyor: the File on GitHub lock could not be taken; nothing filed" >&2; return 1; }
  e=$(jq -ce --arg c "$1" 'first(.cards[]? | select(.card == $c))' "$TACARDS" 2>/dev/null) \
    || { exec {fl}>&-; echo "conveyor: card $1 is no card with no GitHub issue that the record keeps; nothing filed" >&2; return 2; }
  sha=$(stdb ask card "$1" | jq -rs 'map(select(.step == "landed") | .sha | strings) | first // empty')
  [ -n "$sha" ] || { exec {fl}>&-; echo "conveyor: card $1 has not landed; nothing filed" >&2; return 2; }
  u=$(jq -r '.filedUrl // empty' <<<"$e")
  [ -z "$u" ] || { exec {fl}>&-; echo "conveyor: card $1 was filed before, as $u" >&2; echo "$u"; return 0; }
  # With the built label from the start (the belt skips an open issue with it), and the entry's area label, else its file's.
  a=$(jq -r --arg p "${AREA:-}" 'first(select($p != "") | .labels[]? | strings | select(startswith($p))) // empty' <<<"$e"); a=$(filearea "$a" "$(jq -r '.file // .body' <<<"$e")") || a=''; out=$(gh_write issue create --title "$(jq -r .title <<<"$e")" ${a:+--label "$a"} --label "$BUILT" --body "$(jq -r .body <<<"$e")" 2>&1); u=$(grep -oE '[^[:space:]]*/issues/[0-9]+' <<<"$out" | tail -n 1); n=${u##*/}
  [ -n "$n" ] || { exec {fl}>&-; echo "conveyor: the issue of card $1 could not be filed: $out" >&2; return 1; }
  { exec {lock}>>"$TACARDS.lock"; } 2>/dev/null && flock "$lock" && rec=$(jq -ce '.cards | arrays' "$TACARDS" 2>/dev/null) \
    && jq -c --arg c "$1" --argjson n "$n" --arg u "$u" '{cards: map(if .card == $c then .filed = $n | .filedUrl = $u else . end)}' <<<"$rec" > "$TACARDS.new" && mv -f "$TACARDS.new" "$TACARDS" \
    || { rm -f "$TACARDS.new"; echo "conveyor: #$n is filed, but the record could not keep it: Landed today does not link it" >&2; }
  [ -z "$lock" ] || exec {lock}>&-
  gh_write issue close "$n" --comment "Conveyor card $1 landed this as commit $sha before the issue was filed." > /dev/null 2>&1 \
    || echo "conveyor: #$n is filed, but could not be closed: close it, as card $1 landed it as $sha, or the belt can build it again" >&2
  exec {fl}>&-
  echo "$u"
}
# What stands in for the issue of a Tests page card (card()): the title and body its action made, labelled as
# testissue() files the issue (the pack's type and its last priority), so it is held to its action's check
# (lib/speedproof.sh) as that issue's card is. Fails for any other card.
testcardissue() { # <card>
  [ -n "$1" ] && jq -ce --arg c "$1" --arg t "$TYPE" --argjson p "$PRIOS" 'first(.cards[]? | select(.card == $c))
    | {number: 0, title, body, milestone: null, labels: ((.labels // [$t, $p[-1]]) | map({name: .}))}' "$TACARDS" 2>/dev/null
}
taput() { printf '%s\n' "$2" > "$1.new" && mv -f "$1.new" "$1" || { rm -f "$1.new"; return 1; }; } # <file> <record>
# A Tests action's run (TALIMIT, its record, which tarunfile() alone writes while it runs) given the limit its run has
# once testonce() scaled it, so the Board's Running line gives that limit, not the one asked. A record it cannot read is left.
talimit() { local r; r=$(jq -ce --argjson l "$1" 'objects | .limit = $l' "$TALIMIT" 2>/dev/null) && taput "$TALIMIT" "$r"; } # <seconds>
testaction() { # <judge | explain | run> <test file> | stop <id>
  # An explain's --time: the time zone and Time setting of the Board that asked, which its facts' times are given in
  # (tawhen()); with none, this machine's zone and a 12-hour clock.
  local zone="" hours=12-hour
  if [ "${1:-}:${2:-}:$#" = explain:--time:5 ]; then
    [[ ${#3} -le 64 && $3 =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || { echo "conveyor: \"$3\" is not a time zone; no session started" >&2; return 2; }
    [[ $4 = 12-hour || $4 = 24-hour ]] || { echo "conveyor: the Time setting is 12-hour or 24-hour, not \"$4\"; no session started" >&2; return 2; }
    zone=$3 hours=$4; set -- explain "$5"
  fi
  case ${1:-}:$# in
    stop:2) tastop "$2"; return ;;
    run:2) tafile "$2"; return ;;
    judge:2 | explain:2) ;;
    *) echo "usage: conveyor.sh testaction <judge | explain [--time <zone> <12-hour | 24-hour>] | run> <test file> | testaction stop <id>" >&2; return 2 ;;
  esac
  local how=$1 f=$2 c s cli model effort id out sha
  c=$(ctl) || return 1
  s=$(jq -ce '.tests | objects' <<<"$c") \
    || { echo "conveyor: no Tests seat is set (conveyor.sh control tests <cli> <model> [effort], or the Board's Rules tab); no session started" >&2; return 2; }
  jqget "$s" cli cli model model effort effort || return 1
  [ "$effort" != null ] || effort=medium
  out=$(seatready "Tests seat" "$(jq -c '{model, agent: .cli}' <<<"$s")") || { echo "conveyor: $out; no session started" >&2; return 2; }
  [ "$cli" != codex ] || model=$(codexmodel "$model") || { echo "conveyor: $model; no session started" >&2; return 2; }
  # A path of the repo as main has it now (sha, the commit the session reads, even when it is queued): no absolute
  # path, no . or .. part, a file.
  sha=$(git -C "$MAIN" rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)
  [[ -n $sha && -n $f && $f != /* && /$f/ != */../* && /$f/ != */./* && $f != *$'\n'* ]] && [ "$(git -C "$MAIN" cat-file -t "$sha:$f" 2>/dev/null)" = blob ] \
    || { echo "conveyor: $f is not a file of $BRANCH; no session started" >&2; return 2; }
  id=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
  mkdir -p "$TESTACTS" || { echo "conveyor: the test actions' folder could not be made; no session started" >&2; return 1; }
  taput "$TESTACTS/$id.json" "$(jq -cn --arg id "$id" --arg a "$how" --arg f "$f" --arg p "$REPO" --arg t "$(clock)" --arg c "$cli" --arg m "$model" --arg e "$effort" --argjson l "$TESTACTION_TIMEOUT" \
    --argjson q "${EPOCHREALTIME/[.,]/}" --arg h "$sha" --arg z "$zone" --arg hr "$hours" '{id: $id, action: $a, file: $f, project: $p, commit: $h, start: $t, end: null, state: "queued", asked: $q, cli: $c, model: $m, effort: $e, limit: $l, verdict: null}
      + if $a == "explain" then {zone: (if $z == "" then null else $z end), hours: $hr} else {} end')" \
    || { echo "conveyor: the record of the test action could not be written; no session started" >&2; return 1; }
  taask "$id"
}
# At most TAMAX test actions run at once (sessions and runs by hand alike). Each ask is kept first as queued, in its
# record, with asked, the microseconds since the epoch of the ask (start has whole seconds: two asks in one second kept
# no order); taqueue() then starts the queued ones, oldest ask first, while fewer than TAMAX run, and each runner calls it
# again as it ends (tarun(), tarunfile()). One holder at a time ($TESTACTS/queue.lock): two ends, or an end and an ask,
# never start one action twice or more than TAMAX at once. An action counts as running while its record says so and
# its runner is there. The ask prints the id once the action has started or is queued; one that could not start is
# failed, saying why (exit 1); one whose runner wrote <id>.txt (tarun(), tarunfile()) started, even if it failed at once.
TAMAX=3
taask() { # <id>
  local r
  taqueue
  r=$(jq -ce 'objects' "$TESTACTS/$1.json" 2>/dev/null) || { echo "conveyor: the record of the test action $1 could not be read" >&2; return 1; }
  [ "$(jq -r .state <<<"$r")" != failed ] || [ -e "$TESTACTS/$1.txt" ] || { echo "conveyor: the test action $1 did not start: $(jq -r '.reason // "no reason given"' <<<"$r")" >&2; return 1; }
  echo "$1"
}
taqueue() {
  local a n p id fs
  { exec {TALOCK}>>"$TESTACTS/queue.lock"; } 2>/dev/null && flock "$TALOCK" || { echo "conveyor: the test actions' queue could not be locked; nothing started" >&2; return 1; }
  while fs=("$TESTACTS"/*.json) && [ -e "${fs[0]}" ] && a=$(jq -cs 'map(objects)' "${fs[@]}" 2>/dev/null); do
    n=0; for p in $(jq -r '.[] | select(.state == "running") | .pid | numbers' <<<"$a"); do ! kill -0 "$p" 2>/dev/null || n=$((n + 1)); done
    id=$(jq -r '[.[] | select(.state == "queued")] | sort_by(.asked) | first | .id // empty' <<<"$a")
    [ "$n" -lt "$TAMAX" ] && [ -n "$id" ] && tastart "$id" || break
  done
  exec {TALOCK}>&-
}
# A queued action <id>, started (taqueue(), which holds the lock): its runner is started with its record, now running
# from now (start), and is waited for until it has written it. One that cannot start is failed, with the reason.
tastart() { # <id>
  local f=$TESTACTS/$1 r how t sha wt=$CARDS/testactions/$1 p facts shown out i zone hours
  r=$(jq -ce 'objects | .state = "running"' "$f.json" 2>/dev/null) && jqget "$r" action how file t commit sha || return 1
  zone=$(jq -r '.zone | strings' <<<"$r") hours=$(jq -r '.hours | strings' <<<"$r")
  r=$(jq -c --arg t "$(clock)" '.start = $t' <<<"$r")
  if [ "$how" = run ]; then
    mkdir -p "$CARDS/testactions" || { tafail "$1" "the test actions' folder could not be made"; return; }
    # The runner holds no descriptor of this process's (nor the queue's lock): the Board's ssh ends with this process, not with it.
    ( trap - TERM; trap '' HUP; exec {LOGFD}>&- && exec {LOGFD}>&2; tarunfile "$r" "$wt" ) >> "$f.err" 2>&1 < /dev/null 8>&- {TALOCK}>&- &
  else
    facts=$(testfacts "$t") || { tafail "$1" "the records of $t could not be read"; return; }
    # The facts as the session reads them: an explain's with each time as the Board that asked shows it (tawhen(), in
    # its zone: TZ, read by jq's strflocaltime).
    shown=$facts
    [ "$how" = judge ] || shown=$([ -z "$zone" ] || export TZ=$zone; jq -c "$(tawhen "$hours")"' walk(if type == "object" and has("time") then .time |= when else . end)' <<<"$facts") \
      || { tafail "$1" "the records of $t could not be read"; return; }
    mkdir -p "$CARDS/testactions/bin" || { tafail "$1" "the test actions' folders could not be made"; return; }
    # The gh the session finds: one that refuses, so it files no issue through gh on its PATH.
    [ -x "$CARDS/testactions/bin/gh" ] || { printf '#!/bin/sh\necho "conveyor: a test action files no issue and changes nothing on GitHub" >&2\nexit 1\n' > "$CARDS/testactions/bin/gh" \
      && chmod +x "$CARDS/testactions/bin/gh"; } || { tafail "$1" "the test actions' gh could not be made"; return; }
    out=$(git -C "$MAIN" worktree add -q --detach "$wt" "$sha" 2>&1 < /dev/null && chmod -R a-w "$wt" 2>&1) \
      || { tadrop "$wt"; tafail "$1" "the copy of $BRANCH the session reads could not be made: ${out:0:300}"; return; }
    if [ "$how" = judge ]; then p=$TAJUDGE; else p=$TAEXPLAIN; fi
    p+=$'\n\n'"$(jq -r --arg f "$t" '"Test file: \($f)\n\nIts newest run, from the card test steps, the whole-suite runs (the release suite'"'"'s too) and its runs on its own: "
      + (if .newest == null then "none recorded" else "\(.newest.run), \(.newest.time): \(.newest.result). When you say how its newest run ended, say it of this run and name it" end)
      + ".\n\nIts recorded times, from the test lines of the card records, the whole-suite runs and the test-speed survey, oldest first (times: its CPU seconds in a card run; clocks: its seconds on the clock in that run; timed: its seconds and CPU seconds in a run of a card that changed it; carried: true, that card step kept it as passed and did not run it, its times are those of an earlier step of that card; whole: true, a whole-suite run, with its CPU seconds (cpu), seconds on the clock (sec) and result; survey: true, the time the test-speed survey saved for it, with its cpu and sec and no result):\n"
      + (if .runs == [] then "none recorded" else .runs | map(tojson) | join("\n") end)
      + "\n\nThe cards that ran it: " + (if .cards == [] then "none recorded" else .cards | map("\(.card) (#\(.issue))") | join(", ") end)
      + "\n\nIts flaky entries (a case of it failed and then passed when run again):\n" + (if .flaky == [] then "none" else .flaky | map(tojson) | join("\n") end)
      + "\n\nIts recent failures, newest first (the test steps that failed in it; verdict card: the change of that card made it fail; main: it failed on main too; flaky: it failed and then passed when run again; none on record: a step from before verdicts were kept), each with its failing cases and the end of the output of its test step:\n"
      + (if .failures == [] then "none" else .failures | map("- \(.time), card \(.card) (#\(.issue)), verdict \(.verdict // "none on record"), failing cases: \(if .cases == [] then "none named" else .cases | join(", ") end)"
          + (if .tail then "\n  The end of its output:\n" + (.tail | split("\n") | map("    " + .) | join("\n")) else "" end)) | join("\n") end)' <<<"$shown")"
    [ "$how" = judge ] || p+=$'\n\n'"$([ -z "$zone" ] || export TZ=$zone; tachanges "$t" "$facts" "$wt" "$hours")"
    # The session's runner holds no descriptor of this process's (nor the queue's lock): the Board's ssh ends with this
    # process, not with it.
    ( trap - TERM; trap '' HUP; exec {LOGFD}>&- && exec {LOGFD}>&2; tarun "$r" "$wt" "$p" ) >> "$f.err" 2>&1 < /dev/null 8>&- {TALOCK}>&- &
  fi
  # The record is the runner's to write, first and last: the action has started once it says so.
  for ((i = 0; i < 100; i++)); do [ "$(jq -r .state "$f.json" 2>/dev/null)" = queued ] || return 0; sleep 0.1; done
  tafail "$1" "$(tail -n 5 "$f.err" 2>/dev/null)"
}
tafail() { # <id> <why>: a queued action that could not start, failed
  local r
  r=$(jq -ce 'objects' "$TESTACTS/$1.json" 2>/dev/null) && taput "$TESTACTS/$1.json" "$(jq -c --arg t "$(clock)" --arg w "${2:0:600}" '. + {end: $t, state: "failed", reason: $w}' <<<"$r")"
}
# Only what is on or after the test history's start (histstart(), HISTFROM: lib/testfiles.sh) is given: no run, flaky
# entry, failure or newest run before it.
# What the session is given of <file>: {runs: each run that timed it, oldest first, the runs the Tests page shows: each
# test line of a card, {card, issue, time} and its times, clocks (its seconds on the clock), and timed parts for
# the file, and carried: true on a line that kept it as passed and did not run it, its times an earlier step's of the
# same card (testlist.sh carriedrec(); a failed step saves none, so they may be the only ones of that run), and so its
# time that of the latest earlier line of that card that did not carry the file, did not run only some cases of it
# (`partial`) and is not a reused pass, as startlines() dates it (its own time with no such line), and each whole-suite run of $SUITERUNS (testlist.sh suiterec()), {time, whole: true, how, cpu, sec, result}, and the time the test-speed
# survey saved for it (testsurvey(), lib/testfiles.sh), {time, survey: true, cpu, sec}; cards: the
# cards of the test lines, {card, issue}; flaky: the entries of the flaky-test record for it or a case of it ("<file>: <case>");
# failures: its newest TAFAILS failed test steps (those that passed on re-run too), newest first, as the Tests page has
# them (FAILURE and failedrun, lib/testfiles.sh):
# {card, issue, time, verdict, cases, caseVerdicts, tail}; newest: its newest run of every record that holds one, a card's test step
# that ran it (a file that passed on its run again while another file failed again: failed, then passed, unless the run again timed
# out, which may have ended before the file ran; a `held` step, its failures the machine's, read as a failed one and
# named held; a step that ran it, its line with no time of it as a failed step saves none, passed it when the card's
# next step carried it; a step that ran some cases of it, its line naming it partial with no time of it, testlist.sh
# partran(), when it passed or its failures were read (one with none, killed say, voidrun() of lib/testrun.sh, may have ended before those
# cases did; a time-out in another file ran it to its end, filecmd(), unless the step's failures, its last attempt's, name it stopped too, testfails(), or its first attempt's do and the last timed out too, which may have ended before the file ran again), a whole-suite run (the release suite's too) or a run of it alone (tafile(), its record in $TESTACTS), {time, run (which run it was),
# result}, null with none. Times are to the second: runs that share the newest time are all named in one, as which
# ran last is not known.}
TAFAILS=5
testfacts() { # <file>
  local fl defs refs st
  st=$(histstart)
  fl=$(jq -c --arg f "$1" --arg st "$st" "$HISTFROM"'[.entries | arrays | .[] | objects | select(.case == $f or ((.case | strings) | startswith($f + ": "))) | fromstart($st)]' "$FLAKY" 2>/dev/null) || fl='[]'
  testowners
  { olds; recs; } 2>/dev/null | jq -cRn --arg f "$1" --arg st "$st" --slurpfile fl <(printf '%s' "$fl") --argjson n "$TAFAILS" --slurpfile defs <(printf '%s' "$defs") --slurpfile refs <(printf '%s' "$refs") \
    --slurpfile su <(jq -cR 'fromjson? | objects' "$SUITERUNS" 2>/dev/null) --slurpfile sv <(testsurvey) \
    --slurpfile ta <(cat "$TESTACTS"/*.json 2>/dev/null | jq -cR --arg f "$1" 'fromjson? | objects | select(.action == "run" and .file == $f and (.result | strings) and (.end | strings))' 2>/dev/null) "$HISTFROM"'$fl[0] as $fl | ($su | map(fromstart($st))) as $su | ($ta | map(select($st == "" or (.end | strings) >= $st))) as $ta | ($sv[0] | map(fromstart($st))) as $sv | '"$OWNERS$FAILURE"'([inputs | fromjson? | objects | select(.step == "test")] | startlines($st)) as $ls
    | ([$ls[] | failedrun | select(any(failedfiles[]; . == $f)) | failure($f)] | sort_by(.time) | reverse | .[:$n]) as $fails
    | def car: any(.carried | arrays | .[]; . == $f);
      [$ls | to_entries[] | .key as $i | .value | {card, issue, time: (if car then (.card as $k | [$ls[:$i][] | select(.card == $k and .reused != true and (car | not) and (any(.partial | arrays | .[]; . == $f) | not)) | .time] | last) // .time else .time end),
         times: ((.times | objects | .[$f]) // null), clocks: ((.clocks | objects | .[$f]) // null), timed: ([.timed | arrays | .[] | objects | select(.file == $f)] | first), carried: (if car then true else null end)}
         | select(.times != null or .clocks != null or .timed != null) | del(.[] | nulls)] as $c
    | [$su[] | . as $w | .files | objects | .[$f] | objects | {time: $w.time, whole: true, how: $w.how, cpu, sec, result} | del(.[] | nulls)] as $w
    | [$sv[] | select(.file == $f) | {time, survey: true, cpu, sec} | del(.[] | nulls)] as $v
    | [[$ls | to_entries[] | select(.value.reused != true)] | group_by(.value.card)[] | . as $g
        | range(0; length - 1) | select(any($g[. + 1].value.carried | arrays | .[]; . == $f)) | $g[.].key] as $ranat
    | ([$ls | to_entries[] | .key as $i | .value | .result as $r | [if $r == "held" then .result = "fail" else . end | failedrun | select(any(failedfiles[]; . == $f))] as $x
        | select($x != [] or ((any(.carried | arrays | .[]; . == $f) | not)
            and (((.times | objects | .[$f]) // (.clocks | objects | .[$f]) // ([.timed | arrays | .[] | objects | select(.file == $f)] | first)) != null or any($ranat[]; . == $i)
              or (any(.partial | arrays | .[]; . == $f) and ($r == "pass" or (.failures | type) == "object") and (any((.failures | objects | .stopped | arrays | .[]), (select((.failures | objects | .timeout | type) == "object") | .rerun | objects | .failures | objects | .stopped | arrays | .[]); . == $f) | not)))))
        | {time, run: "the test step of card \(.card) (#\(.issue))", result: ((if $x == [] then "passed"
            elif $x[0].result == "pass" then "failed, then passed when run again"
            elif ($x[0].again | type) == "array" and (any($x[0].again[]; . == $f) | not) then
              (if ($x[0].failures.timeout | type) == "object" then "failed, and its run again timed out\($x[0].failures.timeout.file | strings | " in " + .) before it was known to pass"
               else "failed, then passed when run again" end)
            else "failed" end) + (if $r == "held" then " (the card was held: the machine was at fault)" else "" end))}]
       + [$ta[] | {time: .end, run: "its run on its own from the Tests page (test action \(.id)) on \(.commit // "" | .[:12])", result: (if .result == "pass" then "passed" else "failed" end)}]
       + [$su[] | . as $w | .files | objects | .[$f] | objects
        | {time: $w.time, run: "the \(if $w.how == "release" then "release suite" else "full test suite" end)'"'"'s run on \($w.sha // "" | .[:12])",
           result: (if .result == "ok" then "passed" elif .result == "fail" then "failed" else "no result named" end)}]
       | map(select(.time | type == "string")) | unique | (map(.time) | max) as $t | map(select(.time == $t))
       | if length < 2 then first
         else {time: $t, run: ((map(.run) | join(" and ")) + ", which ended in the same second, so which of them ran last is not known"),
           result: (if (map(.result) | unique | length) == 1 then .[0].result else map("\(.result) on \(.run)") | join("; ") end)} end) as $nw
    | {runs: ($c + $w + $v | sort_by(.time)), cards: ($c | map({card, issue}) | unique_by(.card)), flaky: $fl, failures: $fails, newest: $nw}'
}
# A jq def, when: a record's UTC time (2026-11-19T01:26:07Z) or seconds since 1970, in the time zone of TZ (an explain
# asked from the Board: the zone of its browser) on a clock of <hours> (its Time setting: 24-hour, else 12-hour), as
# the Board shows its times; a string that is no such time is kept.
tawhen() { # <hours>
  local h
  if [ "${1:-}" = 24-hour ]; then h='%H:%M:%S'; else h='%-I:%M:%S %p'; fi
  printf 'def when: if type == "number" then strflocaltime("%%Y-%%m-%%d %s %%Z") elif type == "string" then (fromdate? | when) // . else . end;' "$h"
}
# The changes an explain session is given (#767: it has no shell and no git, so it cannot read them itself), as text:
# of <facts>' runs (testfacts()) with a time of the file (times, a whole run's cpu or timed's cpu; a carried line is
# not a run of it), the one where they split best into a part before it and a higher part from it on (the least sum
# of squares of their logs about each part's mean) marks the rise. Its window is from the run before it (the last
# at its usual time) to it (the first slower one). Each commit of <worktree>'s first-parent history that changed
# <file>, a file the test map links to it or a shared file of the map (mapread() of <worktree>: for this repository,
# the engine files of its area and those of an area with tests "all", such as conveyor/tests/lib.sh, in
# .conveyor/engine-areas.json) is named when it was made in that window, and so is the commit that landed the card of
# that run when it changed one of them (its test step ran its change before it landed); not the other cards that ran
# it or landed then (#770). The commit of that card comes first and the others after it oldest first (the diff budget
# goes to its change before an older one's; a whole-suite run has no card, so all of them are oldest first), each with
# its card and issue (its last landed record, or none on record), its time, its subject, its changed files with lines
# added and removed, and its diff of those files. Times are on a clock of <hours> (tawhen()). The diffs together
# keep to TACHANGEMAX characters: the part past it is left out, and the text says which lines and files.
TACHANGEMAX=60000
tachanges() { # <file> <facts> <worktree> [<hours>]
  local ld cs fs files=() card issue sha at d keep rest k n out used=0 cut own shas=() w
  w=$(tawhen "${4:-}")
  ld=$({ olds; recs; } 2>/dev/null | jq -cRn '[inputs | fromjson? | objects | select(.step == "landed" and (.card | type) == "string" and (.sha | strings | test("^[0-9a-f]{40}$")))
    | {card, issue, sha, time}]') || ld='[]'
  # The landed records go in as a file: as one argument, a long history passes the 128 KiB Linux takes (#344).
  cs=$(jq -c --slurpfile l <(printf '%s' "$ld") '$l[0] as $l | def mean: add / length; def sse: mean as $m | map((. - $m) * (. - $m)) | add;
    [.runs[] | select(.carried != true) | {time, card, t: (.times // .cpu // .timed.cpu?)} | select(.t | numbers | . > 0)] as $r
    | [$r[].t | log] as $g
    | [range(1; $r | length) as $i | {i: $i, cost: (($g[:$i] | sse) + ($g[$i:] | sse)), rise: (($g[$i:] | mean) - ($g[:$i] | mean))}] | min_by(.cost)
    | if . == null or .rise <= 0 then {at: null} else $r[.i - 1] as $a | $r[.i] as $n
      | {at: {from: $a, to: $n}, lo: ($a.time | fromdate), hi: ($n.time | fromdate), own: ([$l[] | select(.card == $n.card)] | last | .sha)} end' <<<"$2") \
    || { echo "The commits in the window of a rise in its time: they could not be read."; return 0; }
  fs=$(mapread "$3" 2>/dev/null | jq -c --arg f "$1" '[(.sources | objects | to_entries[] | select(any(.value[]?; . == $f)) | .key), (.shared | arrays | .[] | strings)] | unique' 2>/dev/null)
  mapfile -t files < <(jq -r --arg f "$1" '[$f] + ((. // []) - [$f]) | .[]' <<<"${fs:-null}")
  if [ "$(jq '.at == null' <<<"$cs")" = true ]; then echo "The commits in the window of a rise in its time: no run of it marks a rise in its time, so no change is given."; return 0; fi
  # The card of the slower run: its test step ran its change, which landed after that run.
  own=$(jq -r '.own // empty' <<<"$cs")
  if [ -n "$own" ] && git -C "$MAIN" cat-file -e "$own^{commit}" 2>/dev/null \
    && [ -n "$(git -C "$MAIN" --literal-pathspecs show --no-color --format= --name-only --diff-merges=first-parent "$own" -- "${files[@]}" 2>/dev/null)" ]; then
    shas=("$own $(git -C "$MAIN" log -1 --format=%ct "$own")")
  fi
  mapfile -t -O "${#shas[@]}" shas < <(git -C "$3" --literal-pathspecs log --first-parent --reverse --format='%H %ct' HEAD -- "${files[@]}" 2>/dev/null \
    | awk -v lo="$(jq '.lo' <<<"$cs")" -v hi="$(jq '.hi' <<<"$cs")" -v own="$own" '$2 > lo && $2 <= hi && $1 != own')
  out=$(jq -r "$w"'"The window of the rise in its time: from its last run at its usual time (\(.at.from.t) s at \(.at.from.time | when)) to its first slower run (\(.at.to.t) s at \(.at.to.time | when)"
    + (if .at.to.card | type == "string" then ", the test step of card \(.at.to.card)). The commits made in that window that changed \($ARGS.positional | join(", ")) (the test file, the files the test map links to it and the files the map shares with most tests), and the commit that landed card \(.at.to.card) when it changed one of them, that commit first and the others" else ", a whole-suite run). The commits made in that window that changed \($ARGS.positional | join(", ")) (the test file, the files the test map links to it and the files the map shares with most tests), all of them" end)
    + " oldest first, each with its card and its diff of those files:"
    + (if $none == "1" then " none: no commit that changed one of these files was made in that window." else "" end)' \
    --arg none "$([ ${#shas[@]} -gt 0 ] || echo 1)" --args "${files[@]}" <<<"$cs")
  while IFS=$'\t' read -r sha at card issue; do
    if [ "$card" != - ]; then out+=$'\n\n'"Card $card (#$issue), landed as commit $sha at $at"; else out+=$'\n\n'"Commit $sha at $at, landed by no card on record"; fi
    out+=": $(git -C "$MAIN" log -1 --format=%s "$sha")"$'\n'"Its changed files (lines added, lines removed):"$'\n'
    out+=$(git -C "$MAIN" show --no-color --format= --numstat --diff-merges=first-parent "$sha" | awk -F'\t' '{print "  " $3 " (+" $1 ", -" $2 ")"}')
    d=$(git -C "$MAIN" --literal-pathspecs show --no-color --format= --diff-merges=first-parent "$sha" -- "${files[@]}")
    keep=$d
    if [ $((used + ${#d})) -gt "$TACHANGEMAX" ]; then
      # Cut at the last whole line within the limit.
      cut=${d:0:$((TACHANGEMAX - used))}
      if [[ $cut == *$'\n'* ]]; then keep=${cut%$'\n'*}; else keep=''; fi
    fi
    used=$((used + ${#keep}))
    out+=$'\n'"Its diff:"$'\n'"$keep"
    [ ${#keep} -lt ${#d} ] || continue
    n=$(printf '%s\n' "$d" | wc -l); k=0; [ -z "$keep" ] || k=$(printf '%s\n' "$keep" | wc -l)
    rest=$(printf '%s\n' "$d" | awk -v k="$k" '/^diff --git a\// { f = $0; sub(/^diff --git a\//, "", f); sub(/ b\/.*$/, "", f) } NR > k && f != "" && !s[f]++ { printf "%s%s", (c++ ? ", " : ""), f }')
    out+=$'\n'"[Left out: lines $((k + 1)) to $((n)) of its $((n)) lines of diff, of the files ${rest:-named above}; the diffs of these facts keep to $TACHANGEMAX characters.]"
  done < <([ ${#shas[@]} -eq 0 ] || printf '%s\n' "${shas[@]}" | jq -Rr --slurpfile l <(printf '%s' "$ld") "$w"'split(" ") as [$s, $t] | ([$l[0][] | select(.sha == $s)] | last) as $c
    | [$s, ($t | tonumber | when), ($c.card // "-"), ($c.issue // "none")] | @tsv')
  printf '%s\n' "$out"
}
# The worktree a session read, gone: made writable again, then removed.
tadrop() { chmod -R u+w "$1" 2>/dev/null; git -C "$MAIN" worktree remove --force "$1" 2>/dev/null; rm -rf "$1"; git -C "$MAIN" worktree prune 2>/dev/null; } # <worktree>
# One action's session, in the background: its record written first (running, pid this process), its CLI run under
# TESTACTION_TIMEOUT with its text going to <id>.txt as it comes, and its record written last with how it ended.
# A TERM (tastop()) ends the session: its CLI's process group is told to end, and killed 10 s later if it has not.
tarun() { # <the record> <worktree> <prompt>
  local r=$1 wt=$2 f tp='' tx txp stopped='' rc=0 t0=$EPOCHSECONDS state v=null why=null hv='{}' k acct cli model effort id me=$BASHPID px=''
  trap 'stopped=1' TERM
  jqget "$r" id id cli cli model model effort effort || return 1
  f=$TESTACTS/$id
  taput "$f.json" "$(jq -c --argjson p "$me" '. + {pid: $p}' <<<"$r")" || { tadrop "$wt"; return 1; }
  : > "$f.txt"; acct=$(ctlacct "$(ctl 2>/dev/null)")
  # A try whose login failed, with the proxy as the builder's fallback, runs again at once through the proxy
  # (loginfallback()): its output is read once it is all written, so each try has its own writer.
  while :; do
  exec {tx}> >(tee -a "$f.events" | jq --unbuffered -Rrj "$TATEXT" >> "$f.txt"); txp=$!
  ( unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; export PATH=$CARDS/testactions/bin:$PATH
    [ -z "$px" ] || export PROXY_NOW=1
    case $cli in
      claude) d=$(acctenv "$acct") || { echo "$d" >&2; exit 1; }
        cd "$wt" && proxyenv && cacheenv && acctrun "$d" && exec timeout --kill-after=30 "$TESTACTION_TIMEOUT" claude -p --model "$model" --effort "$effort" --permission-mode default \
          --tools Read,Grep,Glob --setting-sources "" --strict-mcp-config --no-session-persistence --output-format stream-json --verbose ;;
      codex) cd "$wt" && codexargs && exec timeout --kill-after=30 "$TESTACTION_TIMEOUT" codex exec --json -s read-only "${CODEX_PX[@]}" -m "$model" -c "model_reasoning_effort=\"$effort\"" - ;;
      opencode) REVIEW_TIMEOUT=$TESTACTION_TIMEOUT ocrun "$wt" "$model" "$effort" ;;
    esac ) <<<"$3" >&"$tx" 2>> "$f.err" & tp=$!
  [ -n "$stopped" ] || { wait "$tp"; rc=$?; }
  if [ -n "$stopped" ]; then
    # timeout runs in a process group of its own, with its CLI and all the CLI started. A TERM sent again (tastop())
    # no longer cuts the wait short: the record says stopped only once the session has ended.
    trap '' TERM
    kill -TERM -- "-$tp" "$tp" 2>/dev/null
    ( sleep 10; kill -KILL -- "-$tp" "$tp" ) > /dev/null 2>&1 & k=$!
    wait "$tp" 2>/dev/null; kill "$k" 2>/dev/null; wait "$k" 2>/dev/null
  fi
  exec {tx}>&-; wait "$txp" 2>/dev/null
  [ -z "$stopped" ] && [ -z "$px" ] && loginfallback "$rc" "$cli" "$f.events" "$f.err" || break
  px=1
  done
  if [ -n "$stopped" ]; then state=stopped
  elif [ $rc = 124 ] || { [ $rc = 137 ] && [ $((EPOCHSECONDS - t0)) -ge "$TESTACTION_TIMEOUT" ]; }; then state="timed out"
  elif [ $rc = 0 ]; then state=done
  else state=failed; why=$(jq -cn --arg r "exit $rc: $(tail -n 5 "$f.err" 2>/dev/null)" '$r[0:600]'); fi
  if [ "$(jq -r .action <<<"$r")" = judge ]; then
    hv=$(tajudged "$f.txt" "$wt" "$(jq -r .file <<<"$r")") || hv='{"verdict": "no verdict"}'
  fi
  taput "$f.json" "$(jq -c --arg t "$(clock)" --arg s "$state" --argjson v "$v" --argjson w "$why" --slurpfile hv <(printf '%s' "$hv") '$hv[0] as $hv | . + {end: $t, state: $s, verdict: $v} + $hv + (if $w == null then {} else {reason: $w} end) | del(.pid)' <<<"$r")"
  tadrop "$wt"
  taqueue # the next queued action, now that this one has ended
}
# `testaction run <test file>` (README.md, Test actions): the file alone, run now through the pack's test.fileCommand, on main
# as it is at the ask, in a worktree of that commit ($CARDS/testactions/<id>, removed when the run ends), on one of the
# machine's test slots, waited for as a card's test step waits for one (tests()). It is no session: it needs no seat.
# The run's CONVEYOR_TEST_RERUN list names the file alone, a `fail` line with no case: test.fileCommand runs that file
# whole and nothing else (with none set, the run fails naming it). A path that is not a test file of main (a file whose own name has
# `.test.` or `.spec.`, or one the pack's own tests.patterns match, patterntest(); a helper in a __tests__ folder is not
# one) is refused (exit 2), and nothing runs. Its record in $TESTACTS/<id>.json, as a session's: {id, action: "run", file, project, commit, start,
# end, state (queued, running, done, stopped, failed or timed out), load (the machine's 1-minute load at the ask), limit
# (TEST_TIMEOUT, the seconds the test run may run once it has its slot, as a card's test step; once it ran, that limit
# times the load factor as it started, the one it has, from its start: testonce(), lib/testrun.sh, talimit()), result (pass
# or fail; null until it ends, and when it did not run), sec (the file's clock seconds as its runner timed it, else the
# command's), cpu (the file's CPU seconds; null when its runner gave none), wait (the seconds it waited for its slot),
# pid (while it runs) and reason (failed: why)}; <id>.txt, the command's output as it writes it, kept when it ends;
# <id>.err, the runner's own errors. It is queued as
# a session is (taqueue()); the ask returns the id once the run has started or is queued.
tafile() { # <test file>
  local f=$1 id sha
  # sha: the commit of main at the ask, the one the run runs, even when it is queued.
  sha=$(git -C "$MAIN" rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)
  [[ -n $sha && -n $f && $f != /* && /$f/ != */../* && /$f/ != */./* && $f != *$'\n'* ]] && { [[ ${f##*/} =~ \.(test|spec)\. ]] || patterntest "$f"; } \
    && [ "$(git -C "$MAIN" cat-file -t "$sha:$f" 2>/dev/null)" = blob ] \
    || { echo "conveyor: $f is not a test file of $BRANCH; nothing run" >&2; return 2; }
  id=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
  mkdir -p "$TESTACTS" || { echo "conveyor: the test actions' folder could not be made; nothing run" >&2; return 1; }
  taput "$TESTACTS/$id.json" "$(jq -cn --arg id "$id" --arg f "$f" --arg p "$REPO" --arg t "$(clock)" --arg l "$(p_load)" --arg lim "${TEST_TIMEOUT:-}" --argjson q "${EPOCHREALTIME/[.,]/}" --arg h "$sha" \
    '{id: $id, action: "run", file: $f, project: $p, commit: $h, start: $t, end: null, state: "queued", asked: $q, load: ($l | tonumber? // null), limit: ($lim | tonumber? // null),
      result: null, sec: null, cpu: null, wait: null}')" || { echo "conveyor: the record of the run could not be written; nothing run" >&2; return 1; }
  taask "$id"
}
# Each process <pid> started and has not ended, and <pid>: one a line, a parent before its children. Each is stopped
# (STOP) before its children are looked for, so none starts one more unseen: a child started after the look (watch()'s
# timer, every LIVE seconds) was never ended, and held the run's test slot after its record said stopped. The caller
# ends them (taend()).
tatree() { local c; kill -STOP "$1" 2>/dev/null; echo "$1"; for c in $(pgrep -P "$1" 2>/dev/null); do tatree "$c"; done; } # <pid>
# Ends <pid> and each process under it: each is told to end (TERM, to its process group too: timeout makes one for the
# command), then let go on (CONT) to do so, and killed 10 s later if it, or a process of its group, has not ended.
# Returns once they all have.
taend() { # <pid>
  local ps p x i
  ps=$(tatree "$1")
  for p in $ps; do kill -TERM -- "-$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; done
  for p in $ps; do kill -CONT -- "-$p" 2>/dev/null; kill -CONT "$p" 2>/dev/null; done
  for ((i = 0; i < 100; i++)); do
    x=''; for p in $ps; do ! kill -0 "$p" 2>/dev/null && ! kill -0 -- "-$p" 2>/dev/null || x=1; done
    [ -n "$x" ] || break
    [ "$i" != 99 ] || for p in $ps; do kill -KILL -- "-$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done
    sleep 0.1
  done
}
# The run of one file (tafile()), in the background: its record written first (running, pid this process), the file
# run in a process of its own, which holds the test slot (tests()), and its record written last with how it ended. A
# TERM (tastop()) ends the run (taend()); the record says stopped once each process it started has ended, so its slot
# is free again.
tarunfile() { # <the record> <worktree>
  local r=$1 wt=$2 t sha f id tp rc='' w='' s='' stopped='' state='done' res=null why=null tm x me=$BASHPID
  trap 'stopped=1' TERM
  jqget "$r" id id file t commit sha || return 1
  f=$TESTACTS/$id
  taput "$f.json" "$(jq -c --argjson p "$me" '. + {pid: $p}' <<<"$r")" || return 1
  # The command's output (tests(): <worktree>.test), read as it is written.
  ln -sfn "$wt.test" "$f.txt"
  ( x=$({ git -C "$MAIN" worktree add -q --detach "$wt" "$sha" && deps "$wt"; } 2>&1 < /dev/null) \
      || { printf 'the copy of %s it runs in could not be made: %s\n' "$BRANCH" "${x:0:300}" > "$wt.test"; exit 1; }
    printf 'fail\t%s\n' "$t" > "$wt.rerun"
    TALIMIT=$f.json; tests "$wt" test.fileCommand alone; x=$? # TALIMIT: testonce() writes the scaled limit (talimit())
    printf '%s\t%s\t%s\n' "$x" "$TEST_WAIT" "$TEST_RUN" > "$wt.res" ) & tp=$!
  [ -n "$stopped" ] || wait "$tp"
  if [ -n "$stopped" ]; then
    trap '' TERM
    taend "$tp"; wait "$tp" 2>/dev/null; state=stopped
  elif IFS=$'\t' read -r rc w s < "$wt.res" 2>/dev/null && [ -n "$s" ]; then
    if [ "$rc" = 0 ]; then res='"pass"'; else res='"fail"'; fi
    [ "$rc" != 124 ] || state="timed out"
  else
    state=failed; why=$(jq -cn --arg r "it did not run: $(tail -n 5 "$wt.test" 2>/dev/null)" '$r[0:600]')
  fi
  # The file's own times, as its runner timed it (testlist.sh timed()).
  tm=$(timed "$wt" 2>/dev/null | jq -c --arg t "$t" '.[$t] // {}' 2>/dev/null) || tm='{}'
  { cp -f "$wt.test" "$f.txt.new" 2>/dev/null || : > "$f.txt.new"; } && mv -f "$f.txt.new" "$f.txt"
  # limit: the scaled one testonce() kept; the asked one when the run ended before it started (no <worktree>.limit).
  taput "$f.json" "$(jq -c --arg t "$(clock)" --arg s "$state" --argjson res "$res" --argjson w "$why" --argjson tm "$tm" --arg sec "$s" --arg wait "$w" --arg lim "$(cat "$wt.limit" 2>/dev/null)" \
    '. + {end: $t, state: $s, result: $res, sec: ($tm.sec // ($sec | tonumber? // null)), cpu: ($tm.cpu // null), wait: ($wait | tonumber? // null), limit: (($lim | tonumber?) // .limit)}
      + (if $w == null then {} else {reason: $w} end) | del(.pid)' <<<"$r")"
  tadrop "$wt"; rm -rf "$wt".*
  taqueue # the next queued action, now that this one has ended
}
# `testaction stop <id>`: TERM to that action's runner (tarun(), tarunfile()), again every 2 s while its record says running, for up
# to 40 s; prints the state it ended in. A queued one is taken off, stopped, with no session or run, under the queue's
# lock, so taqueue() cannot start it meanwhile. One neither running nor queued is refused (exit 2) and nothing is stopped.
tastop() { # <id>
  local f=$TESTACTS/$1 r p i x=1
  [[ $1 =~ ^[0-9a-f]{12}$ ]] && r=$(jq -ce 'objects' "$f.json" 2>/dev/null) || { echo "conveyor: there is no test action $1" >&2; return 2; }
  if [ "$(jq -r .state <<<"$r")" = queued ]; then
    { exec {TALOCK}>>"$TESTACTS/queue.lock"; } 2>/dev/null && flock "$TALOCK" || { echo "conveyor: the test actions' queue could not be locked; nothing stopped" >&2; return 1; }
    r=$(jq -ce 'objects' "$f.json" 2>/dev/null) && [ "$(jq -r .state <<<"$r")" = queued ] \
      && taput "$f.json" "$(jq -c --arg t "$(clock)" '. + {end: $t, state: "stopped"}' <<<"$r")" && x=0
    exec {TALOCK}>&-
    [ "$x" != 0 ] || { echo "conveyor: the test action $1 is stopped"; return 0; }
    r=$(jq -ce 'objects' "$f.json" 2>/dev/null) || { echo "conveyor: there is no test action $1" >&2; return 2; }
  fi
  [ "$(jq -r .state <<<"$r")" = running ] && p=$(jq -er '.pid | numbers' <<<"$r") && kill -0 "$p" 2>/dev/null \
    || { echo "conveyor: the test action $1 is not running ($(jq -r .state <<<"$r")); nothing stopped" >&2; return 2; }
  for ((i = 0; i < 400; i++)); do
    [ $((i % 20)) != 0 ] || kill -TERM "$p" 2>/dev/null
    [ "$(jq -r .state "$f.json" 2>/dev/null)" = running ] || { echo "conveyor: the test action $1 is $(jq -r .state "$f.json")"; return 0; }
    sleep 0.1
  done
  echo "conveyor: the test action $1 did not end within 40 s of its stop" >&2; return 1
}
# The actions' records, newest first, as a JSON array (the snapshot's). One whose record says running and whose
# runner is gone (the machine restarted) is failed, saying so. It lists the newest TATEXT_SHOWN, and of the older ones
# only each file's newest judge with a verdict (the Board's issue preview gives the verdict kept for a file); the
# other records stay on disk. Each listed one has text, the last TATEXT_MAX characters of its <id>.txt as it is now
# (null when there is none), and textCut, whether that left some out, so the Board shows the text as it comes and
# keeps it after the end: a result it lists always has its text for View and Copy, after a reload too.
TATEXT_SHOWN=20 TATEXT_MAX=16000
testacts() {
  local a p id t dead=() fs=() tx=()
  [ ! -d "$TESTACTS" ] || fs=("$TESTACTS"/*.json)
  [ -e "${fs[0]:-}" ] || { echo '[]'; return; }
  a=$(jq -cs 'map(objects) | sort_by(.start) | reverse' "${fs[@]}" 2>/dev/null) || { echo '[]'; return; }
  for p in $(jq -r '.[] | select(.state == "running") | .pid | numbers' <<<"$a"); do kill -0 "$p" 2>/dev/null || dead+=("$p"); done
  a=$(jq -c --argjson n "$TATEXT_SHOWN" '($ARGS.positional | map(tonumber)) as $d | map(if .state == "running" and (.pid | IN($d[])) then .state = "failed" | .reason = "its session ended with no record of how: the engine running it was ended" else . end)
    | .[:$n] + (.[$n:] | map(select(.action == "judge" and .state == "done" and (.verdict | strings) != "no verdict")) | group_by(.file) | map(first))
    | sort_by(.start) | reverse' --args "${dead[@]}" <<<"$a") || { echo '[]'; return; }
  for id in $(jq -r '.[] | .id | strings | select(test("^[0-9a-f]{12}$"))' <<<"$a"); do
    [ ! -r "$TESTACTS/$id.txt" ] || tx+=(--rawfile "t$id" "$TESTACTS/$id.txt")
  done
  # A text file gone between the look and the read (a run's, as it ends) costs the texts of this snapshot, not the list.
  for t in 1 0; do
    [ "$t" = 1 ] || tx=()
    jq -c --argjson max "$TATEXT_MAX" "${tx[@]}" '$ARGS.named as $x | map(. + (($x["t\(.id)"] | strings | {text: .[-$max:], textCut: (length > $max)}) // {text: null, textCut: false}))' <<<"$a" 2>/dev/null && return
  done
  echo "$a"
}
