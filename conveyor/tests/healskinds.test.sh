#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the judge's kinds beyond harm and self-heals (issue 1563). A cleanup or an already-guarded finding goes
# to the self-heals list with its kind; an already-guarded one whose reason names no check found at a file:line of the
# code is harm; a docs drift finding goes to the docs list, which nothing expires and which release-prep files as one
# docs sweep card per area (healsdocs(), lib/heals.sh). At the last review, only a harm finding blocks the card
# (afterreview(), lib/card.sh). judging(), judgeone(), jf() and jr() are judge.test.sh's; hissue(), fubody() and heals()
# heals.test.sh's; relsetup() release.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

kdocs() { jq -rc "$1" "$ST/docsdrift.jsonl" 2>/dev/null; } # <jq filter>: of each line of the docs list
# What afterreview() decides for card c8's review (judgeone 8) as card() calls it, with the verdict judged() left,
# <pass> reviews so far and <rounds> fix rounds, its one P1 fix round given (p1fix): "<after> <stop> <last0> <p1>
# <hard>", tab-separated.
kgate() { # <pass> <rounds>
  fx_in 'wt=$T/$CASE/cards/c8 issue=$(cat "$T/$CASE/issue8") res=$(verdict "$wt.review") fin="" finrev="" finend="" earlier="" earlyend="" pass='"$1"' rounds='"$2"' \
      rebased="" tfix="" lfix="" mode="" privfix="" p1fix=1; afterreview; printf "%s\t%s\t%s\t%s\t%s\n" "$after" "$stop" "$last0" "$p1" "$hard"'
  [ "$RC" = 0 ] || fail "afterreview() failed: $(cat "$T/$CASE/run.out")"
  tail -n 1 "$T/$CASE/run.out"
}

# Bugs (issue 1563): a cleanup, already-guarded or docs drift finding of a follow-up card's review gets a fix round,
# or reaches the self-heals list with no kind (a cleanup batch card then needs a test that fails on main); an
# already-guarded finding that names no guard, or a guard that is not there, leaves the belt with its hole open; a docs
# drift finding goes to the self-heals list, whose entries expire, not to the docs list; a later ruling of a listed
# finding (cleanup, then already guarded) leaves the entry's first kind and reason, so its batch card has no guard to check.
t_kindsjudge() {
  local clean='[P3] a.txt:2 the name tmp says nothing. Proof: a.txt:2' guard='[P2] a.txt:2 no second check of the slot count. Proof: a.txt:2'
  local noguard='[P2] a.txt:2 no check of the card id. Proof: a.txt:2' farguard='[P2] a.txt:2 no check of the lock. Proof: a.txt:2'
  local drift='[P3] a.txt:2 the guide omits the docs list. Proof: a.txt:2' is
  is=$(hissue 7 "[P2] a.txt:1 a follow-up" "$(fubody '[P2] a.txt:1 a follow-up')" conveyor-followup bug P2 area:engine)
  judging "[$is]"
  printf '%s\n' "$clean" "$guard" "$noguard" "$farguard" "$drift" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: cleanup: the name changes nothing the code does. Cost to every card: none' \
    'F2 ACCEPT: already guarded: the check at a.txt:1 stops the outcome. Cost to every card: none' \
    'F3 ACCEPT: already guarded: another check stops it. Cost to every card: none' \
    'F4 ACCEPT: already-guarded: the check at a.txt:99 stops it. Cost to every card: none' \
    'F5 ACCEPT: docs drift: the guide says less than the code does. Cost to every card: none' > "$STUB/judge.1"
  JUDGEISSUE=$is judgeone 7 "$STUB/review"
  grep -qF '`F<n> ACCEPT: <harm | self-heals | cleanup | already guarded | docs drift>:' "$STUB/judge-asked" \
    && grep -qF 'The reason names that check as file:line; with none, it is harm.' "$STUB/judge-asked" \
    || fail "the judge is not asked for the new kinds, or for an already-guarded finding's guard as file:line: $(grep -F 'ACCEPT:' "$STUB/judge-asked")"
  [ "$(heals '[.card, .finding, .effect] | tojson' | jq -cs .)" = "$(jq -cn --arg a "$clean" --arg b "$guard" '[["c7", $a, "cleanup"], ["c7", $b, "already guarded"]]')" ] \
    || fail "the self-heals list does not hold the cleanup finding and the guarded one that names its guard, each with its kind, alone: $(cat "$ST/selfheals.jsonl" 2>&1)"
  [ "$(kdocs '[.card, .finding, .effect, (.id | startswith("d"))] | tojson' | jq -cs .)" = "$(jq -cn --arg a "$drift" '[["c7", $a, "docs drift", true]]')" ] \
    || fail "the docs list does not hold the docs drift finding alone: $(cat "$ST/docsdrift.jsonl" 2>&1)"
  grep -qxF "SELFHEALS: $drift (judge: docs drift: the guide says less than the code does)" <(jr 7) && grep -qxF "$noguard" <(jr 7) && grep -qxF "$farguard" <(jr 7) \
    || fail "the review does not keep the two guarded findings with no guard found as findings, or the docs drift line as off the belt: $(jr 7)"
  [ "$(jf 7 '[.judge.accepted[] | [.finding, .effect, (.reason | endswith("so it is harm)"))]] | tojson')" = "$(jq -cn --arg a "$noguard" --arg b "$farguard" '[[$a, "harm", true], [$b, "harm", true]]')" ] \
    || fail "the guarded finding that names no guard, and the one whose guard a.txt:99 is not there, are not harm saying why: $(jf 7 .judge.accepted)"
  # A later round rules the cleanup finding already guarded: its entry takes that kind and the reason that names the
  # guard, which its batch card checks, and no second entry is added.
  printf '%s\n' 'F1 ACCEPT: already guarded: the check at a.txt:1 stops it. Cost to every card: none' "$(sed -n '2,5p' "$STUB/judge.1")" > "$STUB/judge.2"
  JUDGEISSUE=$is judgeone 7 "$STUB/review"
  [ "$(heals '[.finding, .effect, .why] | tojson' | jq -cs .)" = "$(jq -cn --arg a "$clean" --arg b "$guard" '[[$a, "already guarded", "the check at a.txt:1 stops it"], [$b, "already guarded", "the check at a.txt:1 stops the outcome"]]')" ] \
    || fail "the cleanup entry did not take the later already-guarded ruling and its reason, or a second entry was added: $(cat "$ST/selfheals.jsonl" 2>&1)"
}

# Bugs (issue 1563): at the last review an in-scope P1 the judge sorts as self-heals is not let through at once (go), or
# is lost rather than listed with the card that landed it; an in-scope harm P1, or one with no kind, is not kept as the
# P1 the card files (p1); a repeated harm P1 is not known as a repeat (hard); a security P1 (a kind the project always
# accepts) the judge sorts as cleanup is not harm; a repeat ends the loop while a new P1 of the same review still has
# its fix round. Since issue 1670 a harm P1 left after its fix round lands as a follow-up, so no case here blocks.
# One card's reviews, each judged again (the last ruling of a finding stands), and afterreview() as card() calls it.
t_kindsgate() {
  local f='[P1] a.txt:2 the poll waits one turn more. Proof: a.txt:2' e='[P1][E1] a.txt:2 the poll waits one turn more. Proof: a.txt:2' is
  local sec='[P1][security] a.txt:2 the token is logged. Proof: a.txt:2' new='[P1] a.txt:2 the badge shows one turn late. Proof: a.txt:2'
  is=$(issue 8 2026-01-01 P1 area:engine)
  judging "[$is]" on security; printf '%s\n' "$is" > "$T/$CASE/issue8"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: self-heals: the next turn picks it up. Cost to every card: none' > "$STUB/judge.1"
  printf '%s\n' 'F1 ACCEPT: harm: the record line is lost. Cost to every card: none' > "$STUB/judge.2"
  printf '%s\n' 'F1 ACCEPT: it is real. Cost to every card: none' > "$STUB/judge.3"
  JUDGEISSUE=$is judgeone 8 "$STUB/review"
  [ "$(kgate 3 0)" = "$(printf 'go\tgo\t\t\t')" ] || fail "the last review's in-scope self-heals P1 did not land the card: $(kgate 3 0)"
  [ "$(heals '[.card, .issue, .finding, .effect] | tojson')" = "$(jq -cn --arg f "$f" '["c8", 8, $f, "self-heals"]')" ] \
    || fail "the landed card's self-heals P1 is not on the self-heals list with card c8: $(cat "$ST/selfheals.jsonl" 2>&1)"
  JUDGEISSUE=$is judgeone 8 "$STUB/review"
  [ "$(kgate 3 0)" = "$(printf 'last\tmax-reviews\t\t%s\t' "$f")" ] || fail "the last review's in-scope harm P1 ($f), after its P1 fix round, did not land the card to file it: $(kgate 3 0)"
  JUDGEISSUE=$is judgeone 8 "$STUB/review"
  [ "$(kgate 3 0)" = "$(printf 'last\tmax-reviews\t\t%s\t' "$f")" ] || fail "the last review's in-scope P1 with no kind ($f), after its P1 fix round, did not land the card to file it: $(kgate 3 0)"
  printf '%s\n' "$sec" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: cleanup: a log line changes nothing. Cost to every card: none' > "$STUB/judge.4"
  JUDGEISSUE=$is judgeone 8 "$STUB/review"
  [ "$(kgate 3 0)" = "$(printf 'last\tmax-reviews\t\t%s\t' "$sec")" ] || fail "the last review's in-scope security P1 the judge sorted as cleanup ($sec) was not kept as the harm P1 the card files: $(kgate 3 0)"
  # The finding back after a fix round (E1), on the second review: a repeat.
  mkdir -p "$T/$CASE/cards/c8.rounds" && jq -cn --arg f "$f" '{id: "E1", round: 1, line: $f, mkey: "x"}' > "$T/$CASE/cards/c8.rounds/findings.jsonl"
  printf '%s\n' "$e" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: self-heals: the next turn picks it up. Cost to every card: none' > "$STUB/judge.5"
  printf '%s\n' 'F1 ACCEPT: self-heals: the next turn picks it up. Cost to every card: none' 'F2 ACCEPT: harm: the badge hides a stuck card. Cost to every card: none' > "$STUB/judge.6"
  printf '%s\n' 'F1 ACCEPT: harm: the record line is lost. Cost to every card: none' > "$STUB/judge.7"
  JUDGEISSUE=$is judgeone 8 "$STUB/review"
  [ "$(kgate 1 1)" = "$(printf 'go\tgo\t\t\t')" ] || fail "a repeated in-scope self-heals P1 did not end the loop to land: $(kgate 1 1)"
  # With a new harm P1 beside the repeat, its fix round follows, as on any review before the last.
  printf '%s\n' "$e" "$new" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  JUDGEISSUE=$is judgeone 8 "$STUB/review"
  [ "$(kgate 1 1)" = "$(printf 'fix\t\t\t\t')" ] && ! grep -qF '[outside the diff]' "$STUB/judge-asked" \
    || fail "a repeat ended the loop while a new in-scope harm P1 still had its fix round, or the new P1 was outside the change: $(kgate 1 1) $(grep '^F2' "$STUB/judge-asked")"
  printf '%s\n' "$e" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  JUDGEISSUE=$is judgeone 8 "$STUB/review"
  [ "$(kgate 1 1 | cut -f1,2)" = "$(printf 'last\trepeat')" ] && [ -n "$(kgate 1 1 | cut -f5)" ] || fail "a repeated in-scope harm P1 ($e) did not end the loop as a repeat (hard) to land: $(kgate 1 1)"
}

# Bug (issue 1576): the first review of a card that is no follow-up, whose one accepted finding inside the change the
# judge sorts as <kind>, gives NO-GO and a fix round for it, though the finding harms nothing: it must give GO and put
# the finding on its list (selfheals or docsdrift, in the state folder) with its kind.
kinside() { # <kind> <the judge's reason> <the list: selfheals | docsdrift>
  local f='[P3] a.txt:2 the name tmp says nothing. Proof: a.txt:2' is l
  is=$(issue 8 2026-01-01 P1 area:engine)
  judging "[$is]"; l=$ST/$3.jsonl
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' "F1 ACCEPT: $1: $2. Cost to every card: none" > "$STUB/judge.1"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  [ "$(jf 8 .verdict)" = GO ] && [ ! -e "$T/$CASE/cards/c8.fix" ] && grep -qxF "SELFHEALS: $f (judge: $1: $2)" <(jr 8) \
    && [ "$(jq -cs 'map([.card, .finding, .effect, .from])' "$l" 2>&1)" = "$(jq -cn --arg f "$f" --arg k "$1" '[["c8", $f, $k, "review"]]')" ] \
    || fail "the first review with one accepted finding '$f' the judge answered 'F1 ACCEPT: $1: $2' did not give GO with the finding on the $3 list alone: $(jr 8) $(cat "$T/$CASE/cards/c8.fix" "$l" 2>&1)"
}
t_insideselfheals() { kinside self-heals 'the next turn picks it up' selfheals; }
t_insidecleanup() { kinside cleanup 'the name changes nothing the code does' selfheals; }
t_insideguarded() { kinside 'already guarded' 'the check at a.txt:1 stops the outcome' selfheals; }
t_insidedocs() { kinside 'docs drift' 'the guide says less than the code does' docsdrift; }

# Bugs (issue 1576): an accepted finding with no kind (an unsure judge's, which is harm), or one whose list entry
# cannot be written, beside a self-heals one, lets the review give GO, or leaves the self-heals one on its list while
# the fix round fixes it too; a list entry that cannot be written fails the whole judge (healsput() handed jq its file
# as an argument), so no finding is judged. Each gives NO-GO from a judged review, and both findings go to the fix round alone.
kblock() { # <the judge's answer for F2> [docs: the docs list cannot be written]
  local slow='[P3] a.txt:2 the poll waits one turn more. Proof: a.txt:2' other='[P3] a.txt:2 the guide omits the docs list. Proof: a.txt:2' is
  is=$(issue 8 2026-01-01 P1 area:engine)
  judging "[$is]"
  [ -z "${2:-}" ] || mkdir -p "$ST/docsdrift.jsonl"
  printf '%s\n' "$slow" "$other" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: self-heals: the next turn picks it up. Cost to every card: none' "$1" > "$STUB/judge.1"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  [ "$(jf 8 .verdict)" = NO-GO ] && [ "$(jf 8 .judge.failed)" = null ] && grep -qxF "E1 $slow" "$T/$CASE/cards/c8.fix" && grep -qxF "E2 $other" "$T/$CASE/cards/c8.fix" \
    && [ -z "$(cat "$ST/selfheals.jsonl" 2>/dev/null)" ] && [ "$(jf 8 '.judge.selfheals // [] | length')" = 0 ] \
    || fail "the review the judge answered 'F1 ACCEPT: self-heals: ...' and '$1'${2:+ (docs list not writable)} did not give NO-GO with both findings in its fix round and none on a list: $(jf 8 .judge) $(jr 8) $(cat "$T/$CASE/cards/c8.fix" "$ST/selfheals.jsonl" 2>&1)"
}
t_insidenokind() { kblock 'F2 ACCEPT: the guide is wrong. Cost to every card: none'; }
t_insidelistfail() { kblock 'F2 ACCEPT: docs drift: the guide says less than the code does. Cost to every card: none' docs; }
# An already-guarded finding whose reason names no check is harm (guardsaid()), so it blocks as one with no kind does.
t_insideunguarded() { kblock 'F2 ACCEPT: already guarded: it cannot happen twice. Cost to every card: none'; }

# Bugs (issue 1563): the sort of the queued follow-ups knows harm and self-heals alone, so a cleanup or docs drift
# card stays queued and is built; an already-guarded card that names no guard leaves the queue; a docs drift card goes
# to the self-heals list; the batch card of an already-guarded entry has a Cleanup: line, so the fix it asks for when
# the guard no longer holds is reported as a finding.
t_kindssort() {
  local ids
  judging '[]'; rm -f "$ST/healssort.jsonl"
  fx_in 'for x in "board [P3] a.txt:1 a stale comment. Proof: a.txt:1" "engine [P3] a.txt:1 the guide omits it. Proof: a.txt:1" "engine [P2] a.txt:1 no second check. Proof: a.txt:1" "engine [P2] a.txt:1 no lock check. Proof: a.txt:1"; do
      f=${x#* }; tcadd "" "$f" "$(fubody "$f")" "" "Review follow-up of #3" "[\"conveyor-followup\",\"bug\",\"area:${x%% *}\"]" 3 || exit 1; done'
  [ "$RC" = 0 ] || fail "the queued follow-up cards could not be made: $(cat "$T/$CASE/run.out")"
  mapfile -t ids < <(grep -E '^c[0-9]{8}T' "$T/$CASE/run.out")
  printf '%s\n' 'F1 CLEANUP: a comment, no behaviour.' 'F2 DOCS DRIFT: the guide says less than the code does.' 'F3 ALREADY GUARDED: another check stops it.' \
    'F4 ALREADY GUARDED: the check at a.txt:1 stops it.' > "$STUB/judge.1"
  out=$(loop heals sort 2>&1) || fail "heals sort failed: $out"
  grep -qF '`F<n> ALREADY GUARDED: <one-line reason that names the check as file:line>`' "$STUB/judge-asked" || fail "the sort's judge is not asked for the new kinds: $(cat "$STUB/judge-asked")"
  [ "$(jq -c '[.cards[].id]' "$ST/testactions/cards.json")" = "$(jq -cn '[$ARGS.positional[2]]' --args "${ids[@]}")" ] \
    || fail "the guarded card that names no guard is not the one queued alone (${ids[*]}): $(jq -c '[.cards[].id]' "$ST/testactions/cards.json")"
  [ "$(heals '[.finding, .effect] | tojson' | jq -cs .)" = '[["[P3] a.txt:1 a stale comment. Proof: a.txt:1","cleanup"],["[P2] a.txt:1 no lock check. Proof: a.txt:1","already guarded"]]' ] \
    && [ "$(kdocs '[.finding, .effect, .from] | tojson')" = '["[P3] a.txt:1 the guide omits it. Proof: a.txt:1","docs drift","sort"]' ] \
    || fail "the cleanup and guarded cards are not on the self-heals list, or the docs drift card not on the docs list, each with its kind: $(cat "$ST/selfheals.jsonl" "$ST/docsdrift.jsonl" 2>&1)"
  # Their batch cards: no test can fail on main for a cleanup or a second guard, so neither has the bug label (its
  # bug-card check would block it). The guarded one tells its builder to check that the named guard still holds, and
  # has no Cleanup: line, under which its review would report the fix of a guard that no longer holds as a change to
  # what the code does; the cleanup one has that line.
  out=$(loop heals batch area:engine 2>&1) && out=$(loop heals batch area:board 2>&1) && [ "$(wc -l < "$STUB/filed")" = 2 ] || fail "heals batch failed: $out"
  [ "$(sed -n 1p "$STUB/filed" | jq -c '.labels | map(.name)')" = '["P2","area:engine"]' ] && ! sed -n 1p "$STUB/filed" | jq -r .body | grep -q '^Cleanup: ' \
    && sed -n 1p "$STUB/filed" | jq -r .body | grep -qF -- '- Kind: already guarded. From: card c20261101T000000-main-3' \
    && sed -n 1p "$STUB/filed" | jq -r .body | grep -qF 'check first that the check its reason names still stops the outcome' \
    || fail "the batch card of a guarded entry has the bug label or a Cleanup: line, or does not name its kind and the guard check: $(sed -n 1p "$STUB/filed")"
  [ "$(sed -n 2p "$STUB/filed" | jq -c '.labels | map(.name)')" = '["P2","area:board"]' ] && sed -n 2p "$STUB/filed" | jq -r .body | grep -q '^Cleanup: ' \
    || fail "the batch card of a cleanup entry alone has the bug label or no Cleanup: line: $(sed -n 2p "$STUB/filed")"
}

# Bug (issue 1626): docs/cards.md tells a user no way to file a review finding by hand that the sort reads, so a
# finding filed without the `[Pn]` title is not sorted and nothing says why. The page's filing sentence must exist, and
# an issue filed as it says (its tag and its marker read from the page) must be read by healsitems() as one finding.
t_kindsfiling() {
  local s tag mark is
  s=$(tr '\n' ' ' < "$SRC/../docs/cards.md" | tr -s ' ' | grep -o 'To file a review finding by hand so that the sort reads it, [^.]*\.')
  tag=$(grep -o 'start the title with `\[P0\]` to `\[P3\]`' <<<"$s" | grep -o '\[P3\]') mark=$(grep -o 'include a `[A-Za-z]*:` line' <<<"$s" | grep -o '[A-Za-z]*:')
  [ -n "$tag" ] && [ -n "$mark" ] || fail "docs/cards.md has no sentence that tells a user to file a finding with a [P0] to [P3] title and a Proof: line: '$s'"
  is=$(hissue 41 "$tag a.txt:1 the poll waits one turn more" "Where: a.txt:1"$'\n'"$mark a.txt:1" area:engine)
  setup "[$is]"; fx_in "healsitems '[$is]'"
  [ "$RC" = 0 ] && [ "$(jq -sc 'map([.kind, .issue])' "$T/$CASE/run.out")" = '[["issue",41]]' ] \
    || fail "healsitems() does not read issue 41, filed as docs/cards.md says ('$s'), as one finding: rc $RC, $(cat "$T/$CASE/run.out")"
}

# Bugs (issue 1563): release-prep files no docs sweep card, so a release goes out with docs that do not match what
# users see; it files one with an area's entries mixed with another's (area:engine's entry is ready too, so a sweep
# with no area filter holds both), files one for entries a docs sweep card holds already, or files one after the
# suite; a docs entry 90 days old is dropped rather than filed. A whole release-prep, as only it shows the sweep run
# before its suite.
t_kindsrelease() {
  local b='- [P3] docs/board.md:9 does not name the docs list. Proof: docs/board.md:9' e='- [P3] docs/cards.md:3 an old word. Proof: docs/cards.md:3'
  relsetup 'cp "$ST/testactions/cards.json" "$STUB/cards-at-suite" 2>/dev/null || :'
  loop control rules followupissues=off >/dev/null || fail "control rules did not take followupissues=off"
  jq -cn '{id: "d00000000000a", time: "2026-08-01T00:00:00Z", card: "c5", issue: 5, repo: "r", area: "area:board", finding: "[P3] docs/board.md:9 does not name the docs list. Proof: docs/board.md:9", why: "the page omits it", effect: "docs drift", from: "review"},
    {id: "d00000000000b", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "r", area: "area:engine", finding: "[P3] docs/cards.md:3 an old word. Proof: docs/cards.md:3", why: "stale", effect: "docs drift", from: "review"},
    {id: "d00000000000c", time: "2026-11-21T00:00:00Z", card: "c5", issue: 5, repo: "r", area: "area:board", finding: "[P3] docs/board.md:4 a held word. Proof: docs/board.md:4", why: "stale", effect: "docs drift", from: "review", batched: 41}' > "$ST/docsdrift.jsonl"
  # The snapshot gives the Board the docs list's open entries by area (selfheals.docs), not the one a card holds.
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.selfheals.docs | [(.entries | map(.id)), .areas]' <<<"$out")" = '[["d00000000000b","d00000000000a"],[{"area":"area:board","count":1},{"area":"area:engine","count":1}]]' ] \
    || fail "the snapshot does not give the docs list's open entries and their areas: $(jq -c '.selfheals' <<<"$out")"
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep 1.1.0 failed: $out"
  [ "$(jq -c '[.cards[] | [.title, (.labels // [] | index("bug")), .label]]' "$ST/testactions/cards.json" 2>&1)" \
    = '[["Docs sweep: 1 finding of area:board",null,"Docs sweep: area:board"],["Docs sweep: 1 finding of area:engine",null,"Docs sweep: area:engine"]]' ] \
    && jq -r '.cards[0].body' "$ST/testactions/cards.json" | grep -qxF -- "$b" && ! jq -r '.cards[0].body' "$ST/testactions/cards.json" | grep -qF 'docs/cards.md' \
    && jq -r '.cards[1].body' "$ST/testactions/cards.json" | grep -qxF -- "$e" && ! jq -r '.cards[1].body' "$ST/testactions/cards.json" | grep -qF 'docs/board.md' \
    || fail "release-prep did not file one docs sweep card for each area, with no bug label, each with its own area's open entry alone: $(cat "$ST/testactions/cards.json" 2>&1) $out"
  [ "$(jq -c '[.cards[].title]' "$STUB/cards-at-suite" 2>&1)" = '["Docs sweep: 1 finding of area:board","Docs sweep: 1 finding of area:engine"]' ] \
    || fail "the docs sweep cards were not filed before the suite ran: $(cat "$STUB/cards-at-suite" 2>&1)"
  [ "$(kdocs '[.id, .batched] | tojson' | jq -cs .)" = "$(jq -c '[.cards[].id] as $c | [["d00000000000a", $c[0]], ["d00000000000b", $c[1]], ["d00000000000c", 41]]' "$ST/testactions/cards.json")" ] \
    || fail "the docs list does not mark each filed entry with its docs sweep card, or lost one: $(cat "$ST/docsdrift.jsonl")"
}

# Bugs (issue 1563): a docs sweep card shut before it lands keeps its entries, so the Board and every later docs
# sweep skip them, and its retry does not take them back; the card of an audit issue whose finding the sort moved to
# the docs list still has that finding in its scope.
t_kindsdocs() {
  local moved='[P3] docs/cards.md:2 the guide omits the docs list. Proof: docs/cards.md:2' e
  judging '[]'
  jq -cn '{id: "d00000000000a", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "r", area: "area:board", finding: "[P3] docs/board.md:9 an old word. Proof: docs/board.md:9", why: "stale", effect: "docs drift", from: "review"}' > "$ST/docsdrift.jsonl"
  out=$(loop heals docs area:board 2>&1) && [ "$(kdocs .batched)" = 100101 ] || fail "heals docs did not file the docs sweep card #100101 for the entry: $out $(cat "$ST/docsdrift.jsonl")"
  landed 100101 | jq -c '(.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  out=$(loop shut 100101 2>&1) && [ "$(kdocs '[.batched, .freed] | tojson')" = '[null,[100101]]' ] \
    || fail "the docs sweep card #100101 shut before it landed still holds its entry: $out $(cat "$ST/docsdrift.jsonl")"
  out=$(loop retry 100101 2>&1) && [ "$(kdocs .batched)" = 100101 ] || fail "retry of the shut docs sweep card #100101 did not hold its entry again: $out $(cat "$ST/docsdrift.jsonl")"
  # The brief of the card of audit issue #9 puts the finding the sort moved to the docs list out of its scope.
  fx_in 'healsadd c0-9 9 area:engine "the guide says less" "'"$moved"'" sort "docs drift"'
  e=$(tail -n 1 "$T/$CASE/run.out")
  fx_in 'healsbrief 9'
  [[ $e == d* ]] && grep -qx '# Findings of this issue that are on the self-heals list or the docs list' "$T/$CASE/run.out" && grep -qF "$moved (list entry $e)" "$T/$CASE/run.out" \
    || fail "healsbrief 9 does not put the finding moved to the docs list ($e) out of the card's scope: $(cat "$T/$CASE/run.out")"
}

# Bug (issue 1563): with no GitHub issue, a docs sweep card (or a batch card) was filed under its list's lock, and
# tcadd() took the Tests page record's lock after it; the pick holds that lock while it retries a card, which takes the
# list's (healstake()), so each waited for the other until the pick timed out. The case holds the docs list's lock and
# polls the running `heals docs` (20 s at most) until it holds the record's: the order a process takes two locks in
# shows only while it waits on the second, so no call of one function can show it.
t_kindslock() {
  local h pid rc held
  setup '[]'
  loop control rules followupissues=off >/dev/null || fail "control rules did not take followupissues=off"
  jq -cn '{id: "d00000000000a", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "r", area: "area:board", finding: "[P3] docs/board.md:9 an old word. Proof: docs/board.md:9", why: "stale", effect: "docs drift", from: "review"}' > "$ST/docsdrift.jsonl"
  mkdir -p "$ST/testactions"; exec {h}>>"$ST/docsdrift.jsonl.lock"; flock "$h"
  ( exec {h}>&-; loop heals docs area:board ) > "$T/$CASE/docs.out" 2>&1 & pid=$!
  WAIT_CEILING=20 wait_until '! flock -n "$ST/testactions/cards.json.lock" true'; held=$?
  flock -u "$h"; exec {h}>&-; wait "$pid"; rc=$?
  [ "$held" = 0 ] || fail "heals docs waited for the docs list's lock before it held the Tests page record's, so a pick that retries a card meanwhile leaves both waiting: $(cat "$T/$CASE/docs.out")"
  [ "$rc" = 0 ] && [ "$(kdocs .batched)" = "$(jq -r '.cards[0].id' "$ST/testactions/cards.json" 2>&1)" ] \
    || fail "heals docs with no GitHub issue did not file the docs sweep card for its entry once the list was free: $(cat "$T/$CASE/docs.out") $(cat "$ST/docsdrift.jsonl")"
}

# Bug (issue 1686): a branch landing (issue 0) whose NO-GO review the judge ruled, then whose review after the fix
# round is a GO with no finding line, printed "cannot take the kinds an earlier judge gave the findings ... away":
# healsnone() read the GO review's findings with leftovers(), whose grep matched no line and so failed the pipe under
# pipefail. On a follow-up branch the judge sends the first review's cleanup finding to the self-heals list and its
# docs drift finding to the docs list; after the GO, an entry whose line the fix round replaced must leave its list
# (healsnone() left both), and one whose line the fix did not touch must stay: a review of the fix alone says nothing
# of it. healsunput() read its decisions twice, so with entries on both lists the second read of the pipe was empty,
# the docs entry stayed and the line was printed.
# The first review of card c0, judged, then fix round 1 (the diff card() writes, from <fix>, a command run in the
# worktree), then a GO with no finding line, judged; prints nothing and fails the case when the GO does not stand as a
# GO or judged() prints the line.
kgoafterfix() { # <fix>
  local wt=$T/$CASE/cards/c0 old is review='USER-VISIBLE: no / VERDICT: GO'
  judging '[]'
  is=$(hissue 0 "a branch landing" "$(fubody "$KHARM" | sed 's/Follow-up depth: 1/Follow-up depth: 2/')")
  printf '%s\n' "$KHARM" "$KCLEAN" "$KDRIFT" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: harm: the first line is lost. Cost to every card: none' 'F2 ACCEPT: cleanup: the name changes nothing the code does. Cost to every card: none' \
    'F3 ACCEPT: docs drift: the guide says less than the code does. Cost to every card: none' > "$STUB/judge.1"
  JUDGEISSUE=$is judgeone 0 "$STUB/review" fix
  [ "$(jf 0 .verdict)" = NO-GO ] && [ -n "$(heals 'select(.card == "c0" and .effect == "cleanup")')" ] && [ -n "$(kdocs 'select(.card == "c0")')" ] \
    || fail "the first review of c0 (review: $KHARM / $KCLEAN / $KDRIFT; issue: Follow-up depth: 2) is not a NO-GO with its cleanup entry and its docs entry listed: $(jf 0 .) $(cat "$ST/selfheals.jsonl" "$ST/docsdrift.jsonl" 2>&1)"
  old=$(git -C "$wt" write-tree) && (cd "$wt" && eval "$1") && git -C "$wt" add -A && mkdir -p "$wt.rounds" \
    && git -C "$wt" diff "$old" "$(git -C "$wt" write-tree)" > "$wt.rounds/1.diff" || fail "fix round 1 of c0 ($1) could not be made"
  printf '%s\n' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review"
  : > "$T/$CASE/judged.err"
  JUDGEISSUE=$is JUDGEWRAP='exec 2>> "$T/$CASE/judged.err"' judgeone 0 "$STUB/review"
  [ "$(jf 0 .verdict)" = GO ] && ! grep -qF 'cannot take the kinds' "$T/$CASE/judged.err" \
    || fail "judged() on c0's GO review ($review) after fix round 1 ($1) did not stand as a GO, or printed: $(cat "$T/$CASE/judged.err")"
}
KHARM='[P0] a.txt:2 the change drops the first line. Proof: a.txt:2'
KCLEAN='[P3] a.txt:2 the name tmp says nothing. Proof: a.txt:2'
KDRIFT='[P3] a.txt:2 the guide omits the docs list. Proof: a.txt:2'
# The fix replaces a.txt:2, the line all three findings cite: neither list keeps an entry of c0.
t_kindsgoafterfix() {
  kgoafterfix "printf 'one\nthree\n' > a.txt"
  [ -z "$(heals 'select(.card == "c0")')$(kdocs 'select(.card == "c0")')" ] \
    || fail "after fix round 1 replaced a.txt:2 and the GO review, a list still holds an entry of c0's earlier round: $(cat "$ST/selfheals.jsonl" "$ST/docsdrift.jsonl" 2>&1)"
}
# The fix changes only b.txt, so the cleanup and docs drift findings at a.txt:2 still stand: both entries stay.
t_kindsgoafterotherfix() {
  kgoafterfix 'echo b > b.txt'
  [ "$(heals .finding)" = "$KCLEAN" ] && [ "$(kdocs .finding)" = "$KDRIFT" ] \
    || fail "after fix round 1 changed only b.txt and the GO review, the entries of c0's findings at a.txt:2 left their lists: $(cat "$ST/selfheals.jsonl" "$ST/docsdrift.jsonl" 2>&1)"
}
