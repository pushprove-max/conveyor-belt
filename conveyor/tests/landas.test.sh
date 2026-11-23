#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the rule Land as (lib/push.sh pushone, landas, landpr; lib/control.sh `control land-as`): with pr, the
# push sends main to conveyor/landing and keeps one pull request open from it, never pushing origin's default branch;
# with main, the push goes to the default branch and opens no pull request. And the rule Merge PR (lib/push.sh
# prmerge, idlemerge; `conveyor.sh pr merge`; release in commands/release-prep.sh): who merges that pull request.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One engine function, in the loop's shell (conveyor.sh's own engine files, then the ones commands/run.sh loads).
la_eng() { la_rec la_loop "$@"; } # <command...>
la_loop() { eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"; names || exit 1; "$@"; }
# One command in the shell of conveyor.sh's own engine files alone (paths.sh, records.sh): all that writing a card's
# lines needs. The loop's other files and names() were most of each la_eng call's time.
la_rec() { # <command...>
  local a=("$@")
  # shellcheck disable=SC2034 # HERE is read by the lines of conveyor.sh (and commands/run.sh: la_loop) run by the eval
  ( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; set --
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh")"
    "${a[@]}" )
}
# `conveyor.sh <args>` as loop runs it, from a copy of the engine with no lib/fulltest.sh: a command that loads a lib it
# does not use (issue 465: pr.sh loaded lib/fulltest.sh) fails here, at the load.
la_nofull() { # <args...>
  [ -d "$T/$CASE/eng" ] || { mkdir -p "$T/$CASE/eng" && cp -R "$SRC"/. "$T/$CASE/eng" && rm -rf "$T/$CASE/eng/tests" "$T/$CASE/eng/lib/fulltest.sh"; } \
    || fail "the engine could not be copied"
  CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$T/$CASE/eng/conveyor.sh" "$@"
}
# Card <n> of issue <n> lands: a commit on main and its lines, as a card that passed its Done-when check (its reply's
# D<n> lines on the build line) and tests: a run of two cases of one file (its why names a second file, which the test
# cache kept off: the body must not list it as run), then a pass that reused that run (its line
# names no test, as card() writes it), then later runs that must not hide the cases run before: one that names both
# files and no case (the cache kept them all), one that ran one case of a third file and case one of the first again
# (the body names each case once: #1435), one that selected that file
# and no case (its times carried from the run before), and one that selected no file. With <fix rounds>, that many
# fix lines come before the tests. The lines are made as record() makes them (line()), then appended in one state
# database call, not one call a line as record() makes.
la_land() { # <n> [<fix rounds>]
  local sha fx='' i
  for ((i = 0; i < ${2:-0}; i++)); do fx+="line c$1 $1 fix ok '{}' &&"$'\n'; done
  echo "$1" > "$R/f$1.txt"; git -C "$R" add -A; git -C "$R" commit -qm "card $1"; sha=$(git -C "$R" rev-parse HEAD)
  la_rec eval "l=\$(line c$1 $1 picked ok '{\"title\":\"T$1\"}' &&
    line c$1 $1 build ok '{\"doneWhen\":{\"items\":2,\"met\":2,\"failed\":[]},\"doneLines\":[\"D1 met: t/a.test.sh case one\",\"D2 met: f$1.txt holds $1\"]}' &&
    $fx line c$1 $1 test pass '{\"ended\":\"passed\",\"tests\":{\"passed\":4,\"failed\":0},\"ran\":[\"t/a.test.sh\"],\"why\":{\"t/a.test.sh\":[\"changed\"],\"t/b.test.sh\":[\"passed before with the same inputs\"]},\"ranCases\":{\"t/a.test.sh\":[\"one\",\"two\"]}}' &&
    line c$1 $1 test pass '{\"sec\":1,\"usage\":{\"input\":0,\"write\":0,\"write1h\":0,\"read\":0,\"output\":0},\"reused\":true}' &&
    line c$1 $1 test pass '{\"ended\":\"passed\",\"tests\":{\"passed\":0,\"failed\":0},\"ran\":[\"t/a.test.sh\",\"t/c.test.sh\"],\"ranCases\":{}}' &&
    line c$1 $1 test pass '{\"ended\":\"passed\",\"tests\":{\"passed\":2,\"failed\":0},\"ran\":[\"t/a.test.sh\",\"t/c.test.sh\"],\"ranCases\":{\"t/a.test.sh\":[\"one\"],\"t/c.test.sh\":[\"three\"]}}' &&
    line c$1 $1 test pass '{\"ended\":\"passed\",\"tests\":{\"passed\":null,\"failed\":null},\"selected\":{\"files\":1,\"filesOf\":null,\"cases\":0,\"casesOf\":12,\"kept\":1},\"carried\":[\"t/c.test.sh\"],\"times\":{\"t/c.test.sh\":1}}' &&
    line c$1 $1 test pass '{\"ended\":\"nothing selected\",\"tests\":{\"passed\":0,\"failed\":0},\"selected\":{\"files\":0,\"filesOf\":12,\"cases\":null,\"casesOf\":null}}' &&
    line c$1 $1 landed ok '{\"sha\":\"$sha\",\"product\":false}') && locked append \"\$l\"" \
    || fail "card $1's lines could not be written"
}
# gh's pull requests, in front of the shared stub (its issues): each one a file $STUB/pr.<n>, numbered from 7 (one with
# .cross true is a fork's: listed by its branch name, as GitHub lists it, with isCrossRepository true); a list is
# newest first (highest number first), as gh lists them; every
# pr call is logged in $STUB/pr-calls. A merge (gh pr merge <n> --merge) makes GitHub's merge commit on origin's
# main, of it and the head branch, unless $STUB/merge-refuse holds the reason GitHub gives; $STUB/merge-then, when
# there is one, is sourced after a merge.
la_prstub() {
  mv "$STUB/gh" "$STUB/gh.issues"
  echo "$T/$CASE/origin" > "$STUB/origin"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = pr ] || exec "$STUB/gh.issues" "$@"
echo "$*" >> "$STUB/pr-calls"; c=$2; n=''; [ "$c" != edit ] && [ "$c" != merge ] || { n=$3; shift; }; shift 2
while [ $# -gt 0 ]; do case $1 in --head) h=$2 ;; --base) b=$2 ;; --title) t=$2 ;; --body) y=$2 ;; --merge) shift; continue ;; esac; shift 2; done
case $c in
  list) cat "$STUB"/pr.* 2>/dev/null | jq -cs --arg h "$h" --arg b "$b" '[.[] | select(.head == $h and .base == $b and .state == "OPEN")] | sort_by(-.number) | [.[] | {number, url: "https://github.com/o/r/pull/\(.number)", isCrossRepository: (.cross // false)}]' ;;
  merge) [ ! -e "$STUB/merge-refuse" ] || { cat "$STUB/merge-refuse" >&2; exit 1; }
    o=$(cat "$STUB/origin"); export GIT_AUTHOR_NAME=gh GIT_AUTHOR_EMAIL=gh@example.com GIT_COMMITTER_NAME=gh GIT_COMMITTER_EMAIL=gh@example.com
    hd=$(git -C "$o" rev-parse "refs/heads/$(jq -r .head "$STUB/pr.$n")") && bs=refs/heads/$(jq -r .base "$STUB/pr.$n") \
      && m=$(git -C "$o" commit-tree "$hd^{tree}" -p "$bs" -p "$hd" -m "Merge pull request #$n") && git -C "$o" update-ref "$bs" "$m" || exit 1
    jq '.state = "MERGED"' "$STUB/pr.$n" > "$STUB/pr.new" && mv "$STUB/pr.new" "$STUB/pr.$n"
    [ ! -e "$STUB/merge-then" ] || . "$STUB/merge-then" ;;
  create) n=$((7 + $(cat "$STUB"/pr.* 2>/dev/null | jq -s length)))
    jq -n --argjson n "$n" --arg h "$h" --arg b "$b" --arg t "$t" --arg y "$y" '{number: $n, head: $h, base: $b, title: $t, body: $y, state: "OPEN"}' > "$STUB/pr.$n"
    echo "https://github.com/o/r/pull/$n" ;;
  edit) jq --arg t "$t" --arg y "$y" '.title = $t | .body = $y' "$STUB/pr.$n" > "$STUB/pr.new" && mv "$STUB/pr.new" "$STUB/pr.$n" ;;
esac
EOF
  chmod +x "$STUB/gh"
}

# Issue 247 (the owner: cards land into one open pull request that collects them until it is merged).
# Bugs it catches: a pr push that still goes to origin's default branch; a second pull request opened while one is
# open; a body rewritten with only the cards of the last push (the earlier ones would not close on the merge); and a
# landing push not counted as pushed (atorigin), so the loop would push the same commit again at every turn; a body
# without each card's D<n> lines or its fix rounds (card 2 has two, card 1 none), or with the tests of its last test line (a
# reused pass names none, a later run that selected no case or no file none) in place of the run that ran them, or only the files and
# cases of its last run (a later run reruns only what changed) in place of those of all its runs; and a card pushed into the pull request shown on the Board's belt as
# waiting for its issue to close (Push failed once the wait ends), when it closes only when the owner merges.
# The pack sets pr; cards 1 and 2 land and push, then card 3. Their issues are open, as they are until the merge.
t_landpr() {
  local o sha body want
  setup "[$(issue 1 2026-01-01),$(issue 2 2026-01-01),$(issue 3 2026-01-01)]"; la_prstub
  tune '.push.landAs = "pr"'
  o=$(git -C "$T/$CASE/origin" rev-parse main)
  la_land 1; la_land 2 2; la_eng push c2 2 || fail "the push failed"
  sha=$(git -C "$R" rev-parse HEAD)
  [ "$(git -C "$T/$CASE/origin" rev-parse refs/heads/conveyor/landing 2>/dev/null)" = "$sha" ] || fail "main was not pushed to conveyor/landing: $(cat "$ST/cards.jsonl" 2>/dev/null | tail -n 3)"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$o" ] || fail "origin's default branch moved with Land as pr"
  [ "$(cat "$STUB"/pr.* | jq -sc 'map([.number, .head, .base, .state])')" = '[[7,"conveyor/landing","main","OPEN"]]' ] || fail "not one pull request from conveyor/landing: $(cat "$STUB"/pr.* 2>/dev/null)"
  body=$(jq -r .body "$STUB/pr.7")
  [ "$(grep -o '^Closes #[0-9]*' <<<"$body" | paste -sd ' ')" = 'Closes #1 Closes #2' ] || fail "the body does not close both issues, in landing order: $body"
  want=$(printf '%s\n' '## #2 T2' '' 'Closes #2' '- Card: `c2`' '- Done when: 2 of 2 met' '  - D1 met: t/a.test.sh case one' '  - D2 met: f2.txt holds 2' \
    '- Fix rounds: 2' '- Tests: passed, 2 passed, 0 failed' '  - `t/a.test.sh`: one, two' '  - `t/c.test.sh`: three')
  [ "$(awk '/^## / {p = ($0 == "## #2 T2")} p && NF' <<<"$body")" = "$(grep . <<<"$want")" ] || fail "card 2's part of the body is not its Done-when lines, its fix rounds and the tests it ran: $body"
  # Card 1 has none: with card 2's two, a count fixed at any one value fails one of these checks.
  [ "$(awk '/^## / {p = ($0 == "## #1 T1")} p && /^- Fix rounds:/' <<<"$body")" = '- Fix rounds: 0' ] || fail "card 1's part of the body does not give its zero fix rounds: $body"
  [ "$(loop snapshot --fresh | jq -c '[.belt[] | select(.issue == 1 or .issue == 2) | .issue]')" = '[]' ] || fail "a card pushed into the pull request is on the belt, waiting for its issue: $(loop snapshot --fresh | jq -c '.belt | map({issue, state})')"
  la_eng atorigin "$sha" || fail "the commit pushed to conveyor/landing does not count as pushed: the loop would push it again"
  la_land 3; la_eng push c3 3 || fail "the third push failed"
  [ "$(cat "$STUB"/pr.* | jq -s length)" = 1 ] || fail "a second pull request was opened while one was open"
  body=$(jq -r .body "$STUB/pr.7")
  [ "$(grep -o '^Closes #[0-9]*' <<<"$body" | paste -sd ' ')" = 'Closes #1 Closes #2 Closes #3' ] || fail "the updated body does not name the three cards: $body"
  [ "$(jq -r .title "$STUB/pr.7")" = 'Conveyor: 3 cards landed on main' ] || fail "the title was not rewritten: $(jq -r .title "$STUB/pr.7")"
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$o" ] || fail "origin's default branch moved at the third push"
}
# Bug it catches: the control record's main not taking over from the pack's pr (`control land-as`), so a push opens
# a pull request, or misses the default branch.
t_landmain() {
  local sha
  setup '[]'; la_prstub
  tune '.push.landAs = "pr"'
  loop control land-as main > /dev/null || fail "control land-as main was refused"
  # The Board's Rules tab shows the record's value over the pack's: the snapshot gives both.
  [ "$(loop snapshot --fresh | jq -c '[.packLandAs, .control.landAs]')" = '["pr","main"]' ] || fail "the snapshot does not give the pack's and the record's Land as: $(loop snapshot --fresh | jq -c '[.packLandAs, .control.landAs]')"
  la_land 1; la_eng push c1 1 || fail "the push failed"
  sha=$(git -C "$R" rev-parse HEAD)
  [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$sha" ] || fail "the push did not go to origin's default branch"
  [ ! -e "$STUB/pr-calls" ] && ! git -C "$T/$CASE/origin" rev-parse -q --verify refs/heads/conveyor/landing >/dev/null || fail "Land as main touched a pull request or conveyor/landing: $(cat "$STUB/pr-calls" 2>/dev/null)"
}

# The state of pull request <n> in the stub (OPEN or MERGED).
la_prst() { jq -r .state "$STUB/pr.$1" 2>/dev/null; }
# Issue 248 (the owner: the rule Merge PR, button by default, and the Board's Merge, which runs `conveyor.sh pr merge`).
# Bugs it catches: with button, the loop's idle look (idlemerge()) merged the pull request by itself; health gave the
# Board no open pull request, link or card count for its Merge; Merge did not merge with a merge commit, left main here
# behind origin's default branch, or left an issue of its cards open; and the push after the merge updated the merged
# pull request (its cards would never reach the default branch) in place of opening a new one. Issue 465: Merge
# loaded lib/fulltest.sh, which it does not use (la_nofull).
t_prbutton() {
  local out
  setup "[$(issue 1 2026-01-01),$(issue 2 2026-01-01)]"; la_prstub
  tune '.push.landAs = "pr"'
  la_land 1; la_eng push c1 1 || fail "the push failed"
  la_eng idlemerge
  [ "$(la_prst 7)" = OPEN ] && ! grep -q '^pr merge' "$STUB/pr-calls" || fail "with Merge PR button, the pull request merged by itself: $(cat "$STUB/pr-calls")"
  out=$(loop health | jq -c '.landingPr | [.number, .url, .cards]')
  [ "$out" = '[7,"https://github.com/o/r/pull/7",1]' ] || fail "health does not give the open pull request, its link and its card count: $out"
  echo OPEN > "$STUB/state.1"
  out=$(la_nofull pr merge 2>&1) || fail "pr merge failed (it runs with no lib/fulltest.sh, which it does not use): $out"
  grep -qx 'pr merge 7 --merge' "$STUB/pr-calls" && [ "$(la_prst 7)" = MERGED ] || fail "pull request 7 was not merged with a merge commit: $(cat "$STUB/pr-calls")"
  [ "$(git -C "$R" rev-parse main)" = "$(git -C "$T/$CASE/origin" rev-parse main)" ] && [ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] \
    || fail "main here is not origin's default branch after the merge: $out"
  [ "$(cat "$STUB/closed" 2>/dev/null)" = 1 ] || fail "issue 1, still open after the merge, was not closed: $(cat "$STUB/closed" 2>&1)"
  [ "$(loop health | jq -c .landingPr)" = null ] || fail "the merged pull request is still shown open: $(loop health | jq -c .landingPr)"
  la_land 2; la_eng push c2 2 || fail "the push after the merge failed"
  [ "$(la_prst 8)" = OPEN ] && [ "$(la_prst 7)" = MERGED ] || fail "the push after the merge opened no new pull request: $(cat "$STUB/pr-calls")"
  [ "$(jq -r .body "$STUB/pr.8" | grep -o '^Closes #[0-9]*' | paste -sd ' ')" = 'Closes #2' ] || fail "the new pull request does not hold only the card landed since: $(jq -r .body "$STUB/pr.8")"
}
# Issue 462. Bug it catches: a fork's pull request from its own conveyor/landing (gh pr list --head matches the branch
# name in any repository, newest first) taken for the landing pull request: the push wrote the cards into it (or opened
# none), health showed it on the Board, and Merge merged it into the default branch with Conveyor's credentials.
t_prfork() {
  local out
  setup "[$(issue 1 2026-01-01),$(issue 2 2026-01-01)]"; la_prstub
  tune '.push.landAs = "pr"'
  jq -n '{number: 7, head: "conveyor/landing", base: "main", title: "fork", body: "fork", state: "OPEN", cross: true}' > "$STUB/pr.7"
  la_land 1; la_eng push c1 1 || fail "the push failed"
  [ "$(la_prst 8)" = OPEN ] && [ "$(jq -r .body "$STUB/pr.7")" = fork ] || fail "the push did not open its own pull request beside the fork's: $(cat "$STUB/pr-calls")"
  # A fork's pull request opened after Conveyor's is listed first.
  jq -n '{number: 9, head: "conveyor/landing", base: "main", title: "fork", body: "fork", state: "OPEN", cross: true}' > "$STUB/pr.9"
  la_land 2; la_eng push c2 2 || fail "the push of card 2 failed"
  grep -qx 'Closes #2' <(jq -r .body "$STUB/pr.8") && [ "$(jq -r .body "$STUB/pr.9")" = fork ] || fail "the push did not update its own pull request: $(cat "$STUB/pr-calls")"
  rm -f "$(la_rec eval 'echo "$LANDPR"')"
  [ "$(loop health | jq -c .landingPr.number)" = 8 ] || fail "health does not show Conveyor's pull request: $(loop health | jq -c .landingPr)"
  out=$(loop pr merge 2>&1) || fail "pr merge failed: $out"
  [ "$(la_prst 8)" = MERGED ] && [ "$(la_prst 7)" = OPEN ] && [ "$(la_prst 9)" = OPEN ] || fail "Merge merged a fork's pull request: $(cat "$STUB/pr-calls")"
}
# Issue 464. Bug it catches: when a card landed on main here after the push (main and origin's default branch have
# diverged), Merge left main without origin's merge commit (prff() did not merge it in with remerge()), so the next
# push to conveyor/landing would not hold the merge, or main would lose the landed card.
t_prdiverge() {
  local out c2 o
  setup "[$(issue 1 2026-01-01)]"; la_prstub
  tune '.push.landAs = "pr"'
  la_land 1; la_eng push c1 1 || fail "the push failed"
  la_land 2; c2=$(git -C "$R" rev-parse main)
  out=$(loop pr merge 2>&1) || fail "pr merge failed with an unpushed card on main: $out"
  o=$(git -C "$T/$CASE/origin" rev-parse main)
  [ "$(git -C "$R" rev-parse main^1 main^2 2>&1 | paste -sd ' ')" = "$c2 $o" ] || fail "main here is not card 2 merged with origin's default branch after the merge: $(git -C "$R" log --format='%H %P %s' -3 main) / origin $o"
  [ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] && [ "$(cat "$R/f2.txt")" = 2 ] || fail "main's checkout does not hold the merge: $(git -C "$R" status --porcelain)"
}
# Bugs it catches: a merge GitHub refuses (checks, conflicts) taken as done: the pull request dropped from the Board,
# main here moved or its issues closed; or the refusal shown with no reason, to the owner or the Foreman (health).
# Issue 465: this error path loaded lib/fulltest.sh, which it does not use (la_nofull).
t_prrefused() {
  local out h
  setup "[$(issue 1 2026-01-01)]"; la_prstub
  tune '.push.landAs = "pr"'
  la_land 1; la_eng push c1 1 || fail "the push failed"
  echo OPEN > "$STUB/state.1"; h=$(git -C "$R" rev-parse main)
  echo 'Pull request is not mergeable: the base branch policy prohibits the merge' > "$STUB/merge-refuse"
  out=$(la_nofull pr merge 2>&1); [ $? = 1 ] && grep -qF 'the base branch policy prohibits the merge' <<<"$out" || fail "the refused merge did not fail with GitHub's reason: $out"
  [ "$(la_prst 7)" = OPEN ] && [ "$(git -C "$R" rev-parse main)" = "$h" ] && [ ! -e "$STUB/closed" ] || fail "a refused merge moved main or closed an issue"
  out=$(loop health | jq -r '.landingPr | "\(.number) \(.merge.result): \(.merge.reason)"')
  [ "$out" = '7 refused: Pull request is not mergeable: the base branch policy prohibits the merge' ] || fail "health does not show the open pull request with the refusal's reason: $out"
  # Health reads GitHub's state, not only the file the push wrote: a pull request open before that file was kept shows,
  # and one merged on GitHub, not here, is gone.
  rm -f "$(la_rec eval 'echo "$LANDPR"')"
  out=$(loop health | jq -c '.landingPr | [.number, .url]')
  [ "$out" = '[7,"https://github.com/o/r/pull/7"]' ] || fail "health does not show the pull request GitHub has open: $out"
  # The owner sets Land as to main with it open, then merges it on GitHub: health must still ask GitHub, or the Board
  # keeps showing Merge for a merged pull request.
  loop control land-as main > /dev/null || fail "control land-as main was refused"
  [ "$(loop health | jq -c '.landingPr.number')" = 7 ] || fail "the pull request still open is not shown after Land as main"
  jq '.state = "MERGED"' "$STUB/pr.7" > "$STUB/pr.new" && mv "$STUB/pr.new" "$STUB/pr.7"
  out=$(loop health | jq -c .landingPr)
  [ "$out" = null ] || fail "health still shows the pull request merged on GitHub as open (Land as main): $out"
}
# Bugs it catches: with Merge PR idle, the pull request merged while a card was on the belt, or before (or without)
# the push run passing on it: the test files linked to every card in it (here card 1's lib/m.test.js, which card 2's
# push alone would not run), each alone on its head; or it merged when the rule was set to button during that run
# (the rule and the belt were read only before it); or it never merged once the belt was empty and that run passed.
t_pridle() {
  local sha
  setup "[$(issue 1 2026-01-01),$(issue 2 2026-01-01)]"; la_prstub
  printf '%s\n' 'echo "$(git rev-parse HEAD) $1" >> "$STUB/ran"; [ ! -e "$STUB/during" ] || { bash "$STUB/during"; rm -f "$STUB/during"; }' \
    '[ ! -e "$STUB/red" ] && bash "$1"' > "$STUB/one"
  tune '.push.check = true | .push.landAs = "pr" | .test.fileCommand = "bash \"$STUB/one\""'
  # #2 is held until its card lands: an open issue that waits to be picked holds the merge (t_pridlerelease).
  loop control pr-merge idle > /dev/null && loop control hold 2 > /dev/null || fail "control pr-merge idle or control hold 2 was refused"
  mkdir -p "$R/lib" && echo good > "$R/lib/m.js" && echo 'grep -qx good lib/m.js' > "$R/lib/m.test.js" || fail "the fixture could not be made"
  la_land 1; la_eng push c1 1 || fail "the push failed"
  sha=$(git -C "$R" rev-parse main); rm -f "$STUB/ran"
  la_rec record c9 9 picked ok '{}' || fail "card 9's line could not be written"
  la_eng idlemerge
  [ "$(la_prst 7)" = OPEN ] && [ ! -e "$STUB/ran" ] || fail "the pull request merged, or its run began, with card 9 on the belt"
  la_rec record c9 9 closed ok '{}' || fail "card 9's line could not be written"
  touch "$STUB/red"; la_eng idlemerge
  [ "$(cat "$STUB/ran" 2>&1)" = "$sha lib/m.test.js" ] || fail "the push run did not run lib/m.test.js alone on the pull request's head: $(cat "$STUB/ran" 2>&1)"
  [ "$(la_prst 7)" = OPEN ] || fail "the pull request merged though its push run failed"
  rm -f "$STUB/red" "$STUB/ran"; la_land 2; la_eng push c2 2 || fail "the push of card 2 failed"
  # The owner sets the rule to button while the push run runs (it takes minutes): the run passes, and nothing merges.
  printf '%s\n' "CONVEYOR_MAIN='$R' CONVEYOR_CARDS='$T/$CASE/cards' bash '$SRC/conveyor.sh' control pr-merge button > /dev/null" > "$STUB/during"
  sha=$(git -C "$R" rev-parse main); la_eng idlemerge
  [ "$(cat "$STUB/ran" 2>&1)" = "$sha lib/m.test.js" ] || fail "the push run did not run card 1's test file on the new head: $(cat "$STUB/ran" 2>&1)"
  [ ! -e "$STUB/during" ] && [ "$(la_prst 7)" = OPEN ] || fail "the pull request merged though the rule was set to button while its push run ran"
  loop control pr-merge idle > /dev/null || fail "control pr-merge idle was refused"
  # Bug (#1076): it merged while a release run was under way, so main moved under the run's suite. A stand-in run
  # holds the release hold until the case lets it go.
  local hp
  ( exec {hp}>>"$ST/release.hold" && flock -x "$hp" && touch "$STUB/held" && while [ ! -e "$STUB/letgo" ]; do sleep 0.1; done ) & hp=$! # sleep: the stand-in run holds the hold until the case lets it go
  wait_until '[ -e "$STUB/held" ]' || fail "the stand-in run did not take the release hold"
  la_eng idlemerge; touch "$STUB/letgo"; wait "$hp"
  [ "$(la_prst 7)" = OPEN ] || fail "the pull request merged while a release run was under way"
  la_eng idlemerge
  [ "$(la_prst 7)" = MERGED ] && git -C "$T/$CASE/origin" merge-base --is-ancestor "$sha" main || fail "the pull request did not merge once the belt was empty and its run passed"
}
# Issue 1447 (R401). Bug it catches: docs/configuration.md said Merge PR idle runs the linked test files whenever Test
# before a push is on, but a pack with neither test.fileCommand nor a test.list form that gives one file runs none
# (pushtests() skips them) and idle merges. Here card 1's linked test file fails if run, and the pull request merges.
t_pridlenofile() {
  setup "[$(issue 1 2026-01-01)]"; la_prstub
  tune '.push.check = true | .push.landAs = "pr" | del(.test.fileCommand, .test.list)'
  loop control pr-merge idle > /dev/null || fail "control pr-merge idle was refused"
  mkdir -p "$R/lib" && echo bad > "$R/lib/m.js" && echo 'grep -qx good lib/m.js' > "$R/lib/m.test.js" || fail "the fixture could not be made"
  la_land 1; la_eng push c1 1 || fail "the push failed"
  la_eng idlemerge
  [ "$(la_prst 7)" = MERGED ] || fail "the pull request did not merge, with no test.fileCommand and no test.list, once the belt was empty"
}
# R106 of #1389. Bug it catches: with Merge PR idle, `control release` of a held issue while the push run ran (it takes
# minutes) left that issue waiting to be picked with no card yet, and the pull request merged, as only the rule and
# the card records were read again. #3 is held; the stubbed push run releases it: the run runs, and nothing merges.
t_pridlerelease() {
  setup "[$(issue 1 2026-01-01),$(issue 3 2026-01-01)]"; la_prstub
  printf '%s\n' 'echo "$1" >> "$STUB/ran"; [ ! -e "$STUB/during" ] || { bash "$STUB/during"; rm -f "$STUB/during"; }; bash "$1"' > "$STUB/one"
  tune '.push.check = true | .push.landAs = "pr" | .test.fileCommand = "bash \"$STUB/one\""'
  loop control pr-merge idle > /dev/null && loop control hold 3 > /dev/null || fail "control pr-merge idle or control hold 3 was refused"
  mkdir -p "$R/lib" && echo good > "$R/lib/m.js" && echo 'grep -qx good lib/m.js' > "$R/lib/m.test.js" || fail "the fixture could not be made"
  la_land 1; la_eng push c1 1 || fail "the push failed"
  rm -f "$STUB/ran"; printf '%s\n' "CONVEYOR_MAIN='$R' CONVEYOR_CARDS='$T/$CASE/cards' bash '$SRC/conveyor.sh' control release 3 > /dev/null" > "$STUB/during"
  la_eng idlemerge
  [ "$(cat "$STUB/ran" 2>&1)" = lib/m.test.js ] && [ ! -e "$STUB/during" ] || fail "the push run did not run, or #3 was not released during it: $(cat "$STUB/ran" 2>&1)"
  [ "$(la_prst 7)" = OPEN ] || fail "the pull request merged though #3 was released, and waits to be picked, while its push run ran"
}
# Bug it catches (#463): the pages said Merge PR idle always runs the linked test files before it merges, but
# pushtests() runs none with the push check off (push.check), so a reader took an untested merge for a tested one.
# A text check: the claim is in the docs, with no behaviour of its own to run (t_pridle runs the merge itself). The
# sentence itself is matched (when Test before a push is on, the linked test files run or pass first): the old claim
# with "See Test before a push." added named the setting and passed.
t_pridledocs() {
  local p s
  for p in "docs/configuration.md:^- \`idle\`:" "docs/board.md:^Idle merges it"; do
    s=$(awk -v re="${p#*:}" '$0 ~ re {on = 1} on && (/^$/ || (/^- / && $0 !~ re)) {exit} on' "$SRC/../${p%%:*}")
    [ -n "$s" ] || fail "${p%%:*}: the Merge PR idle text is not found"
    s=$(tr -s '\n ' '  ' <<< "${s//\*\*/}")
    [[ $s =~ When\ Test\ before\ a\ push\ is\ on,\ [^.]*(first\ [^.]*test\ files|test\ files[^.]*\ first) ]] \
      || fail "${p%%:*}: the Merge PR idle text does not say the linked test files run first when Test before a push is on: $s"
  done
}
# Bugs it catches: with Merge PR release, release-prep ran the suite on origin's default branch, which lacks the cards
# waiting in the pull request, in place of conveyor/landing; `release` tagged the default branch without them (it did
# not merge the pull request first), or merged it only after the tag; a release a check refused (here a tag that
# exists) had merged the pull request already; or it ran the suite again on the merge commit,
# though it holds the files release-prep's pass was on. gh posts a commit status as GitHub does: the status of a
# commit is the last one posted on it.
t_prrelease() {
  local out t m l
  la_prrelsetup
  l=$(git -C "$T/$CASE/origin" rev-parse refs/heads/conveyor/landing)
  out=$(loop release-prep 1.1.0 2>&1) && [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$l" ] || fail "release-prep did not run the suite on conveyor/landing ($l): $out"
  rm -f "$STUB/full-at"
  out=$(loop release 1.0.0 2>&1) && fail "a release of 1.0.0, whose tag exists, was not refused: $out"
  grep -qF 'the tag v1.0.0 already exists' <<<"$out" && [ "$(la_prst 7)" = OPEN ] || fail "a refused release merged the pull request: $out"
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  [ "$(la_prst 7)" = MERGED ] || fail "release did not merge the pull request: $out"
  [ ! -e "$STUB/full-at" ] || fail "release ran the suite again on the merge, though release-prep passed on the same files: $out"
  m=$(git -C "$T/$CASE/origin" log --format=%H --grep='^Merge pull request #7' main) && t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}' 2>/dev/null) \
    && [ -n "$m" ] && git -C "$T/$CASE/origin" merge-base --is-ancestor "$m" "$t" && [ "$(git -C "$T/$CASE/origin" show "$t:f1.txt")" = 1 ] \
    || fail "the tag v1.1.0 is not on the merge of the pull request, with card 1's change: $out"
}
# Bug it catches (O223): after the merge of the landing pull request, a git status that failed (core.bare=true on the
# checkout, set by the merge stub) read as a clean checkout, and the release went on to tag. It is refused by the check
# after the merge, naming the status that could not be read, with nothing tagged or released.
t_prreleasebare() {
  local out
  la_prrelsetup
  echo 'git -C "$R" config core.bare true' > "$STUB/merge-then" || fail "the fixture could not be made"
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] || fail "the release with a status that could not be read after the merge was not refused: $out"
  [ "$(la_prst 7)" = MERGED ] && grep -qF 'refused, nothing tagged or released: pull request #7 is merged, but the checkout is not at a merge holding the files checked' <<<"$out" \
    && grep -qF 'or its status could not be read' <<<"$out" || fail "the refusal is not the check after the merge: $out"
  [ -z "$(git -C "$R" tag -l v1.1.0)" ] && [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" 2>/dev/null \
    || fail "the refused release tagged or released: $(git -C "$R" tag -l) $(cat "$STUB/gh-calls" 2>&1)"
}
# The fixture of a Merge PR release: the pack sets pr and Merge PR release, main holds plugin.json (p, 1.0.0) tagged
# v1.0.0 and notes for 1.1.0, and card 1 is pushed into pull request #7. gh posts a commit status as GitHub does.
la_prrelsetup() {
  setup '[]'; la_prstub
  printf '%s\n' '#!/usr/bin/env bash' 'case $1 in release) echo "$*" >> "$STUB/gh-calls" ;; issue) echo "{\"state\":\"CLOSED\"}" ;;' \
    '  api) if [ "$2" = -X ]; then echo "$*" >> "$STUB/gh-calls"; else s=${2#*/commits/}; s=${s%%/*}' \
    '    grep -q "statuses/$s .*state=success" "$STUB/gh-calls" 2>/dev/null && echo "[{\"context\":\"conveyor/release-suite\",\"state\":\"success\"}]" || echo "[]"; fi ;; esac' > "$STUB/gh.issues"
  tune '.push.landAs = "pr" | .test.full = "git rev-parse HEAD > \"$STUB/full-at\""'
  mkdir -p "$R/.claude-plugin" "$R/docs/releases" && jq -n '{name: "p", version: "1.0.0"}' > "$R/.claude-plugin/plugin.json" \
    && jq -n '{name: "m", plugins: [{name: "p", source: {source: "url", url: "https://github.com/o/p.git", ref: "v1.0.0"}}]}' > "$R/.claude-plugin/marketplace.json" \
    && git -C "$R" add -A && git -C "$R" commit -qm 'the first release' && git -C "$R" tag -a v1.0.0 -m 'Release 1.0.0' \
    && printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$R/docs/releases/1.1.0.md" && git -C "$R" add -A && git -C "$R" commit -qm 'fix: A fix' \
    && git -C "$R" push -q origin main v1.0.0 || fail "the fixture could not be made"
  loop control pr-merge release > /dev/null || fail "control pr-merge release was refused"
  la_land 1; la_eng push c1 1 || fail "the push failed"
}
