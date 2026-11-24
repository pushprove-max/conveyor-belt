#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: test files at landing: the three-way merge of test files, a test file shared with a card landed since
# and the landing turn its run again gives (lib/claim.sh), and the parse check of merged files.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main's test file a.test.sh, one case: two changes that each add a case at its end conflict in a three-way merge.
casefile() { echo case1 > "$R/a.test.sh"; git -C "$R" add a.test.sh; git -C "$R" commit -qm "a test file"; }

# Bug (#435: 5 of 11 landing clashes in a day): two cards that both add a case at the end of one test file clashed at
# landing, and the second went to a merge session. Card c7 (fx_wt), made on main before another card landed, adds
# case8; that card's case7 lands meanwhile. At c7's landing, where its plain three-way merge conflicts, the test file
# is merged keeping both sides (unionfit(), its own lines outside the test files being unionx()'s), with no session.
# Bug (#451: a union merge, which git calls clean, can leave a test file that no longer parses): the union-merged file
# is checked to parse (parses(), here through the pack's land.parse, which records each file it checks). What a file
# that fails the check leads to is t_mergeparseclean's.
t_mergetests() {
  setup '[]'; fx_wt 'echo case8 >> a.test.sh' a.test.sh case1
  echo "{ tr '\n' ' ' < \"\$1\"; echo; } >> '$STUB/parsed'; exec bash -n \"\$1\"" > "$STUB/parse"
  tune --arg c "sh $STUB/parse" '.land.parse = {"*.test.sh": $c}'
  echo case7 >> "$R/a.test.sh"; git -C "$R" commit -qam "case7 lands"
  fx_in 'cd "$FXWT" && tf=$(git diff --cached --name-only --no-renames | testpaths) && ix=$(unionx "$FXWT" "$tf") && echo "tf=$tf" \
    && git diff --cached --binary --no-renames > "$FXWT.patch" && git reset -q --hard main && ! git apply --3way --index "$FXWT.patch" >/dev/null 2>&1 \
    && git reset -q --hard main && unionfit "$FXWT" a.test.sh "$tf" "$ix" && parses "$FXWT"'
  [ "$RC" = 0 ] && grep -qx 'tf=a.test.sh' "$T/$CASE/run.out" \
    || fail "the two cases' clash in a.test.sh was not merged keeping both, or the merge was found not to parse: $(cat "$T/$CASE/run.out")"
  [ "$(git -C "$FXWT" show :a.test.sh | tr '\n' ' ')" = "case1 case7 case8 " ] && [ "$(git -C "$FXWT" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] \
    || fail "the merged test file is not both cases staged on main: $(git -C "$FXWT" show :a.test.sh | tr '\n' ' ')"
  [ "$(cat "$STUB/parsed" 2>/dev/null)" = 'case1 case7 case8 ' ] || fail "the union-merged test file was not checked to parse: $(cat "$STUB/parsed" 2>/dev/null)"
}

# The merged test file is run before the card lands, though the card's own lines are the ones that passed: two cases
# kept side by side may not work together. #7 adds a case; during its tests main adds one too. The merged file holds
# both and its run fails: #7 goes to its fix, and lands after it with both cases.
t_mergetestsrun() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done; casefile
  echo "if grep -q '^# The changed tests fail' \"\$STUB/brief\"; then echo fixed >> a.test.sh; else echo case7 >> a.test.sh; fi" > "$STUB/build"
  # The failed run writes the runner's log naming its file: one that names only the test command is no result (voidrun()).
  cat >> "$STUB/test-cmd" <<'EOF'
[ -e "$STUB/moved" ] || { : > "$STUB/moved"; echo main-case >> "$R/a.test.sh"; git -C "$R" commit -qam "main adds a case"; }
! { grep -qx main-case a.test.sh && grep -qx case7 a.test.sh && ! grep -qx fixed a.test.sh; } || { cp a.test.sh "$STUB/merged"; echo "FAIL a.test.sh: the two cases clash"; printf "%s\n" "== a.test.sh" "-- FAIL a.test.sh" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1; }
EOF
  # loop: settle() drops the union merge's pass in its own body, and card() then runs the merged file and sends its failure to the fix: no function shows that order
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(tr '\n' ' ' < "$STUB/merged" 2>/dev/null)" = "case1 main-case case7 " ] \
    || fail "the merged test file was not run before the card landed: $(st 'select(.step == "test") | "\(.result) \(.reused)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 7 and .step == "test") | .result' | tr '\n' ' ')" = "pass fail pass " ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] \
    && grep -q '^# The changed tests fail' "$STUB/brief" && [ "$(st 'select(.step == "landed") | .issue')" = 7 ] \
    || fail "the failed run of the merged file did not send #7 to its fix, then land: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(tr '\n' ' ' < "$R/a.test.sh")" = "case1 main-case case7 fixed " ] || fail "main does not hold both cases and the fix: $(cat "$R/a.test.sh")"
}

# Bug (#334: two cards that each added a row to one panel passed their tests alone, and its test file failed on main
# once both landed): a card whose change still applied to a main that moved landed on the tests it passed before, though
# the card landed meanwhile touched a test file of its own. Card c7 (fx_wt) changes lib/rows.sh; the card landed
# meanwhile, lib/panel.sh: the test links give both lib/view.test.sh. Once main holds that landing, sharedtests() names
# lib/view.test.sh, so the card runs it again on main as it is now (card()) and does not land red; a landing that
# touches none of the card's test files (a.txt) names none, so the card lands on the run it passed.
t_mergesharedtests() {
  setup '[]'; mkdir -p "$R/lib"; linkset '{"lib/panel.sh": ["lib/view.test.sh"], "lib/rows.sh": ["lib/view.test.sh"]}'
  fx_wt 'echo eight >> lib/rows.sh' lib/panel.sh panel lib/rows.sh rows lib/view.test.sh case1
  # Each landing, then c7's change brought onto main as it is now (settle()), and what sharedtests() prints and returns.
  fx_in 'cd "$FXWT" && b=$(git rev-parse HEAD) || exit 3
    for f in a.txt lib/panel.sh; do echo landed >> "$R/$f" && git -C "$R" commit -qam "$f lands" && git diff --cached --binary --no-renames > "$FXWT.patch" \
      && git reset -q --hard main && git apply --index "$FXWT.patch" || exit 3; t=$(sharedtests "$FXWT" "$b"); echo "$f: $? $t"; done'
  [ "$RC" = 0 ] && [ "$(tr '\n' ',' < "$T/$CASE/run.out")" = "a.txt: 1 ,lib/panel.sh: 0 lib/view.test.sh," ] \
    || fail "the test file c7 shares with a card landed since was not named, or one with a landing that touches none was: $(cat "$T/$CASE/run.out")"
}

# #447: card A (#7) passes; card-b lands touching A's test file lib/view.test.sh; A runs that file again and passes;
# card-c lands touching it again (and, given "conflict", A's line of lib/panel.sh too). card-b and card-c stand for
# cards that landed: a commit on main and its landed line. Each run of A's tests logs the file, and the n-th lands the
# n-th of them. Given "turn", card B (#8, in $T/$CASE/b8) is ready to land at the same time as A (sharedturn()).
sharedonce() { # [conflict|turn]
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  mkdir -p "$R/lib"; echo panel > "$R/lib/panel.sh"; echo case1 > "$R/lib/view.test.sh"
  git -C "$R" add lib; linkset '{"lib/panel.sh": ["lib/view.test.sh"]}' # A's change runs lib/view.test.sh
  echo "if grep -q '^# Landing conflict' \"\$STUB/brief\"; then sed -i 's/^panelC\$/panelC seven/' lib/panel.sh; else sed -i 's/^panel\$/seven/' lib/panel.sh; fi" > "$STUB/build"
  if [ "${1:-}" = turn ]; then sharedturn; elif [ -n "${1:-}" ]; then : > "$STUB/conflict"; fi
  cat >> "$STUB/test-cmd" <<'EOF'
n=$(( $(cat "$STUB/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/n"
echo "== lib/view.test.sh"; printf "%s\n" "== lib/view.test.sh" "-- ok lib/view.test.sh" "TESTRUN sec	lib/view.test.sh	1	1" >> "$CONVEYOR_TEST_LOG/run.log"
c=''; case $n in 1) c=card-b ;; 2) c=card-c ;; esac
[ -z "$c" ] || { echo "$c" >> "$R/lib/view.test.sh"; [ "$c" != card-c ] || [ ! -e "$STUB/conflict" ] || sed -i 's/^panel$/panelC/' "$R/lib/panel.sh"
  git -C "$R" commit -qam "$c lands"; jq -cn --arg c "$c" --arg s "$(git -C "$R" rev-parse HEAD)" '{card: $c, issue: 90, step: "landed", result: "ok", sha: $s}' >> "$ST/cards.jsonl"; }
EOF
  # loop: only a whole card run shows card-b and card-c landing between A's test runs and A's run again before it lands
  out=$(loop run 2>&1); rc=$?; : > "$STUB/runend"; [ $rc = 0 ] || fail "run exited non-zero: $out"
  grep -q 'card .*-7: cards landed since its tests ran touch its test files too.*lib/view.test.sh' <<<"$out" \
    || fail "#7 did not run its test file again after card-b landed on it: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}
# Card B for sharedonce turn: once a card has the landing turn (land.turn), B's worktree is made on main as it is then,
# adding a line to A's shared test file, and B tries to land (land(), as card() calls it), its output and exit in
# $T/$CASE/b.out, then $STUB/btried. Main's pre-commit hook holds a landing made with the turn taken until then (30 s at most), so B tries
# while A has the turn and is landing. B gives up when the run ends first (no turn was taken).
sharedturn() {
  local h=$R/.git/hooks/pre-commit
  # Only a commit made while a card has the turn waits: card-b's and card-c's commits (test-cmd) come before it.
  printf '%s\n' '#!/usr/bin/env bash' "[ -s '$T/$CASE/cards/land.turn' ] || exit 0" "for i in \$(seq 300); do [ -e '$STUB/btried' ] && break; sleep 0.1; done" > "$h" && chmod +x "$h" || fail "main's pre-commit hook" # sleep: the landing waits for card B's try
  # This polls the loop's cards folder: only a card() run takes the turn after its run again of the shared files.
  ( for i in $(seq 1200); do [ -s "$T/$CASE/cards/land.turn" ] && break; [ ! -e "$STUB/runend" ] || exit 0; sleep 0.1; done # sleep: B waits for A's turn
    git -C "$R" worktree add -q --detach "$T/$CASE/b8" main && echo eight >> "$T/$CASE/b8/lib/view.test.sh" && git -C "$T/$CASE/b8" add -A || exit 0
    ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" || exit 9
      . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names || exit 9
      land c8-8 8 "$T/$CASE/b8" "eight (#8)"; echo "land: $?" ) > "$T/$CASE/b.out" 2>&1
    : > "$STUB/btried" ) & BPID=$!
}

# Bug (#1148): card #1134 passed its run again of its shared test files, and each time it came to land another card had
# landed first: it was fitted onto main and ran its lint and tests again, four rounds in 13 minutes. A (#7), its run
# again passed, has the landing turn: B, ready at the same time, tries to land while A lands and is refused, main
# staying as A's tests left it; A lands with no second run again of its shared file, then B lands on A's commit.
t_mergesharedturn() {
  local a
  sharedonce turn; wait "$BPID"
  [ "$(cat "$T/$CASE/b.out" 2>&1)" = $'another card has the landing turn, as its batch or its run again of the shared test files lands first; nothing was landed\nland: 1' ] \
    || fail "card B was not refused while A had the landing turn: $(cat "$T/$CASE/b.out" 2>&1)"
  a=$(st 'select(.issue == 7 and .step == "landed") | .sha')
  [ -n "$a" ] && [ "$(cat "$STUB/n")" = 2 ] && [ "$(git -C "$R" log -1 --format=%s "$a^")" = "card-c lands" ] && [ ! -e "$T/$CASE/cards/land.turn" ] \
    || fail "A did not land on main as its tests left it with no second run, or its turn stayed: runs $(cat "$STUB/n"); $(git -C "$R" log --format=%s | head -4 | paste -sd,)"
  fx_in 'W=$T/$CASE/b8; git -C "$W" diff --cached --binary > "$W.p" && git -C "$W" reset -q --hard main && git -C "$W" apply --index "$W.p" || exit 3
    land c8-8 8 "$W" "eight (#8)"; echo "land: $?"'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = 'land: 0' ] && [ "$(git -C "$R" rev-parse main^)" = "$a" ] && grep -qx eight "$R/lib/view.test.sh" \
    || fail "B did not land after A once A's turn ended: $(cat "$T/$CASE/run.out")"
}

# Bug (#1148): a card ready to land while another card has the landing turn landed, or waited saying nothing. c8-8 at
# its land step waits (landwait()) while c7-7 has the turn: its land step's start line is marked waitFor: turn, its
# live record names c7-7, the Board's step line says it waits on #7, and it is idle; once the turn ends it goes on.
t_mergeturnwait() {
  local s
  setup '[]'; mkdir -p "$T/$CASE/cards"
  for n in 7 8; do jq -cn --arg c "c$n-$n" --argjson n "$n" '{card: $c, issue: $n, step: "picked", result: "ok", time: "2026-01-01T00:00:00Z", tokens: {claude: 0, codex: 0}, sha: "", reason: ""}' >> "$ST/cards.jsonl"; done
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"]}" > "$T/$CASE/cards/c7-7.claim"; echo "{\"card\":\"c7-7\",\"pid\":$$}" > "$T/$CASE/cards/land.turn"
  # This polls a real wait: what the Board shows comes from the live record landwait() keeps while it waits.
  fx_in 'landwait c8-8 8 "$CARDS/c8-8"; echo waited' & local p=$!
  wait_until "jq -e '.waits.on == \"c7-7\" and (.action | startswith(\"waiting for card c7-7 to land first\"))' '$T/$CASE/cards/c8-8.live'" && [ -e "$T/$CASE/cards/c8-8.idle" ] \
    || { rm -f "$T/$CASE/cards/land.turn"; fail "the card does not say it waits for c7-7's landing turn: $(cat "$T/$CASE/cards/c8-8.live" 2>&1)"; }
  s=$(loop snapshot --fresh)
  [ "$(jq -c '[.belt[] | select(.issue == 8) | [.step, .waitsOn.issue]]' <<<"$s")" = '[["waiting",7]]' ] \
    || { rm -f "$T/$CASE/cards/land.turn"; fail "the Board's step line does not say the card waits on #7: $(jq -c '[.belt[] | {issue, step, waitsOn, live}]' <<<"$s")"; }
  rm -f "$T/$CASE/cards/land.turn"; wait "$p"
  grep -qx waited "$T/$CASE/run.out" && [ ! -e "$T/$CASE/cards/c8-8.live" ] && [ ! -e "$T/$CASE/cards/c8-8.idle" ] \
    && [ "$(st 'select(.card == "c8-8" and .step == "start") | .waitFor')" = turn ] || fail "the wait did not end with the turn, or left its marks: $(cat "$T/$CASE/run.out")"
  # Bug it catches: stop (halt(), lib/run.sh) left a card in that wait to land after the stop. Nothing of its landing
  # has begun there, as in a wait for a release run, so it is stopped.
  sleep 60 & p=$! # sleep: a stand-in for the card's process, until it is killed
  fx_in "echo '$p c8-8' | halt"; kill -KILL "$p" 2>/dev/null; wait "$p" 2>/dev/null
  [ "$(cat "$T/$CASE/run.out")" = "$p c8-8" ] || fail "stop left the card that waits for a landing turn: $(cat "$T/$CASE/run.out")"
  recok "$ST/cards.jsonl" "the wait for a landing turn"
}

# Bug it catches: after its shared run again passed, card-c landed on the file again and A ran it again, on and on:
# each run let another card land, and A never landed (#447). A lands with no third run, and its log names card-c only.
t_mergesharedonce() {
  sharedonce
  [ "$(cat "$STUB/n")" = 2 ] && [ "$(st 'select(.issue == 7 and .step == "test") | "\(.result) \(.reused // false)"' | tr '\n' ,)" = "pass false,pass false,pass true," ] \
    && [ "$(st 'select(.issue == 7 and .step == "landed") | .issue')" = 7 ] \
    || fail "#7 ran its shared test file again after card-c landed, or did not land: runs $(cat "$STUB/n"); $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  grep -q 'card .*-7: .*lands with no second run again\. Cards landed since: card-c$' <<<"$out" \
    || fail "#7's log does not say it lands with no second run, naming card-c alone: $(grep 'card .*-7' <<<"$out" | tail -5)"
  [ "$(tr '\n' ' ' < "$R/lib/panel.sh")" = "seven " ] || fail "main does not hold #7's change: $(cat "$R/lib/panel.sh")"
}

# Bug it catches: a card past its one shared run again (#447) landing on that pass when its change no longer applies.
# card-c changes A's line too: A is fitted onto main as before (its rebuild session), reviewed and tested again, and
# lands. The three-way merge is tried only to spare a rebuild: a change whose lines main changed too still goes to the
# rebuild session, and the rebuilt change lands, not main's line.
t_mergesharedonceconflict() {
  sharedonce conflict
  st 'select(.issue == 7 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts' \
    || fail "#7 was not fitted onto main after card-c's conflicting change: $(st 'select(.issue == 7) | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(cat "$STUB/n")" = 3 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(st 'select(.issue == 7 and .step == "landed") | .issue')" = 7 ] \
    && [ "$(tr '\n' ' ' < "$R/lib/panel.sh")" = "panelC seven " ] \
    || fail "#7's fitted change was not reviewed and tested again before it landed: runs $(cat "$STUB/n"), reviews $(wc -l < "$STUB/reviews"); $(cat "$R/lib/panel.sh")"
}

# Bug (#345): unshare() named a shared file that had passed only as failed, so the run again logged "did not pass" for
# it. Each shared file no `fail` line names gets a `shared` line beside its `fail` line; one that failed a case (c) gets
# none, as it did fail; so does each file whose passes it drops when the shared files could not be listed. Bug (R238):
# a shared file the list had no line for (e, which never ran) was named shared too, so the run again logged "main
# changed what it tests since it passed" for a file that never passed: it gets a `fail` line alone.
t_mergeunshare() {
  eval "$(sed -n '/^unshare() {/,/^}/p' "$SRC/lib/claim.sh")"
  local w=$T/$CASE/w
  mkdir -p "$T/$CASE"; printf 'change\tx\npass\ta\npass\tb\nfail\tc\tone\nok\tc\ttwo\n' > "$w.rerun"
  unshare "$w" $'a\nc\ne'
  [ "$(sort "$w.rerun" | tr '\t\n' ':|')" = "change:x|fail:a|fail:c|fail:c:one|fail:e|pass:b|shared:a|" ] \
    || fail "the shared files that passed are not each named shared, or one that failed or never ran (e) is: $(cat "$w.rerun")"
  printf 'change\tx\npass\ta\nfail\tc\tone\nok\tc\ttwo\n' > "$w.rerun"
  unshare "$w" "(the test files of the change or of main's could not be listed)"
  [ "$(sort "$w.rerun" | tr '\t\n' ':|')" = "change:x|fail:c:one|shared:a|" ] \
    || fail "with no list of shared files, the files that passed are not each named shared: $(cat "$w.rerun")"
}

# With the pack's test.changed set, unshare() leaves the list as it is: tests() adds main's change as `main` lines,
# from which the command runs the cases both changes select (#1591; t_mainmovedcases runs it through card()). Bug it
# catches: a list with no tree line, or a base (b1) that cannot be compared with HEAD, gets no `main` line from
# tests(), so left as it is the shared file would not run again at all: there it is named failed, to run whole, as with
# no test.changed. Each of the two is checked apart, so neither check of unshare() can go unnoticed.
t_mergeunsharechanged() {
  eval "$(sed -n '/^unshare() {/,/^}/p' "$SRC/lib/claim.sh")"
  local w=$T/$CASE/w l=$'change\tx\nbase\tb0\ntree\tt0\npass\ta\npass\tb\n'
  packget() { printf -v "$2" '%s' sel.sh; }; treediff() { [ "$2" = b0 ] && [ "$3" = HEAD ]; }
  mkdir -p "$T/$CASE"; printf '%s' "$l" > "$w.rerun"
  unshare "$w" a
  [ "$(cat "$w.rerun")" = "${l%$'\n'}" ] || fail "with test.changed, the shared file a lost its pass: $(cat "$w.rerun")"
  printf '%s' "$l" | grep -v '^tree' > "$w.rerun"
  unshare "$w" a
  [ "$(sort "$w.rerun" | tr '\t\n' ':|')" = "base:b0|change:x|fail:a|pass:b|shared:a|" ] \
    || fail "with test.changed and no tree line, the shared file a was not named failed to run whole: $(cat "$w.rerun")"
  printf '%s' "${l/b0/b1}" > "$w.rerun"
  unshare "$w" a
  [ "$(sort "$w.rerun" | tr '\t\n' ':|')" = "base:b1|change:x|fail:a|pass:b|shared:a|tree:t0|" ] \
    || fail "with test.changed and a base (b1) that cannot be compared with HEAD, the shared file a was not named failed to run whole: $(cat "$w.rerun")"
}

# Main moves under card c7 (#7) after its tests passed (#1591). The pack sets test.changed: its test command reads the
# list's `main` lines. The links are <links>; c7 makes <c7's change>, by default adding `eight` to lib/rows.sh. Its
# tests passed on m0, its list (c7.rerun) as a run leaves it: lib/view.test.sh passed. Card c8 lands, adding <c8's line>
# to lib/panel.sh (its commit and landed line), and c7's change is brought onto main as it is now. lib/view.test.sh
# (<its text> on main) by default fails when lib/rows.sh holds `eight` and lib/panel.sh holds `landed`: the two changes
# fail together (#334). $STUB/test-cmd stands for the project's command: it adds each file it is given to
# $STUB/given, keeps the list it got in $STUB/list, and runs the file unless the list keeps it as passed and names no
# `main` line, adding to $STUB/ran `<file> <case>` for each of the file's cases it runs: those CONVEYOR_TEST_CASES
# names of it, else all its t_ cases. Of main's change it runs only those, as the project's command runs of it only
# the cases the change's own selection holds (.conveyor/test-changed-rerun.test.sh tests that rule).
mainmoved() { # <links json> <c8's line> [<c7's change> [<lib/view.test.sh text>]]
  local v='! { grep -qx eight lib/rows.sh && grep -qx landed lib/panel.sh; }'
  setup "[$(issue 7 2026-01-01)]"; tune '.test.changed = "sel.sh"'; mkdir -p "$R/lib"; linkset "$1"
  fx_wt "${3:-echo eight >> lib/rows.sh}" lib/panel.sh panel lib/rows.sh rows lib/other.test.sh 'exit 0' lib/x.test.sh 'exit 0' \
    lib/y.test.sh 'exit 0' lib/w.test.sh 'exit 0' lib/view.test.sh "${4:-$v}"
  m0=$(git -C "$R" rev-parse main)
  printf 'change\t%s\nbase\t%s\ntree\t%s\npass\tlib/view.test.sh\n' "$(git -C "$FXWT" diff --cached --binary --no-renames HEAD | git hash-object --stdin)" \
    "$m0" "$(git -C "$FXWT" write-tree)" > "$FXWT.rerun"
  echo "$2" >> "$R/lib/panel.sh"; git -C "$R" commit -qam "title 8 (#8)" || fail "#8 could not land"
  landed 8 | jq -c --arg s "$(git -C "$R" rev-parse main)" '.card = "c8-8" | .sha = $s' >> "$ST/cards.jsonl"
  git -C "$FXWT" diff --cached --binary --no-renames > "$FXWT.patch" && git -C "$FXWT" reset -q --hard main \
    && git -C "$FXWT" apply --index "$FXWT.patch" || fail "c7's change could not be brought onto main as it is now"
  cat > "$STUB/test-cmd" <<'EOF'
f=$CONVEYOR_TEST_FILE; echo "$f" >> "$STUB/given"; cp "$CONVEYOR_TEST_RERUN" "$STUB/list"
if grep -q "^main	" "$CONVEYOR_TEST_RERUN" || ! grep -qxF "pass	$f" "$CONVEYOR_TEST_RERUN"; then
  cs=$(printf '%s\n' "${CONVEYOR_TEST_CASES:-}" | awk -F'\t' -v f="$f" '$1 == f { print $2 }'); [ -n "$cs" ] || cs=$(sed -n 's/^t_\([a-z]*\)() {.*/\1/p' "$f")
  for c in $cs; do echo "$f $c" >> "$STUB/ran"; done; bash "$f"
fi
EOF
}
# card()'s test step (cardtest()) on c7, as card() calls it, with the real sharedtests(), unshare() and tests(): the
# lint gate, checks, batches and the landing turn stubbed; c7's change is the one that passed (testedhere()). run.out
# ends with the run's exit.
mainmovedtest() {
  fx_in 'c=c7 n=7 wt=$FXWT issue="{}" sprompt="" br="" parsecheck="" tmain="" away="" apart="" me=$$ cmsg=x mates=()
    lintgate() { return 0; }; checks() { :; }; treecheck() { :; }; testedhere() { return 0; }; gather() { return 1; }; turntake() { :; }
    cardtest; echo "rc $rc"'
}

# Bug it catches (#334, kept with #1591's narrower run again): c7 and c8 each pass alone, and lib/view.test.sh, which
# both changes select, fails with both on main. With no file named failed in c7's list, its run again on main as it
# is now still gives the command that file with main's change named, so the pair fails before c7 lands.
t_mainmovedpair() {
  mainmoved '{"lib/rows.sh": ["lib/view.test.sh"], "lib/panel.sh": ["lib/view.test.sh"]}' landed; mainmovedtest
  [ "$(tail -n 1 "$T/$CASE/run.out")" != "rc 0" ] && grep -qx lib/view.test.sh "$STUB/given" \
    || fail "c7 and c8, which fail together in lib/view.test.sh, did not fail c7's run again before it landed: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#1591): a run again on a main that moved named each shared file failed with no case, so the command
# ran it whole: card #1533's selection was 14 to 20 files and its run again 135. And (#1591 review) the run again
# took the card's own cases off a shared file of its own (listcmd()), so the command ran every case of it. c7 changes
# the case t_a of lib/view.test.sh, which holds t_a, t_b and t_c: its own selection is t_a. c8's change to lib/panel.sh
# selects lib/view.test.sh, whole, and lib/other.test.sh, which c7's does not. c7's run again keeps its pass of
# lib/view.test.sh, names main's change (`main` line) and is given t_a alone of it: t_a runs, not t_b or t_c, and
# lib/other.test.sh is not given.
t_mainmovedcases() {
  mainmoved '{"lib/panel.sh": ["lib/view.test.sh", "lib/other.test.sh"]}' other \
    'printf "t_a() {\n  echo a2\n}\nt_b() {\n  echo b\n}\nt_c() {\n  echo c\n}\n" > lib/view.test.sh' $'t_a() {\n  echo a\n}\nt_b() {\n  echo b\n}\nt_c() {\n  echo c\n}'
  mainmovedtest
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "rc 0" ] && [ "$(sort -u "$STUB/given" | tr '\n' ' ')" = "lib/view.test.sh " ] \
    || fail "c7's run again was not given lib/view.test.sh alone (given: $(cat "$STUB/given" 2>&1)): $(cat "$T/$CASE/run.out")"
  [ "$(cat "$STUB/ran" 2>&1)" = 'lib/view.test.sh a' ] \
    || fail "c7's run again, its own selection t_a of lib/view.test.sh, ran other cases of it (ran: $(cat "$STUB/ran" 2>&1)): $(cat "$T/$CASE/run.out")"
  grep -qx $'pass\tlib/view.test.sh' "$STUB/list" && grep -qx $'main\tlib/panel.sh' "$STUB/list" && ! grep -q $'^fail\t' "$STUB/list" \
    || fail "c7's run again was not given its pass of lib/view.test.sh and main's change, or named a file failed to run it whole: $(cat "$STUB/list" 2>&1)"
}

# Bug it catches (#1591): the shared list grew with each move of main. c7's own passes held lib/x.test.sh, which it ran
# once only because main moved, and c8's test line names lib/y.test.sh only because main moved under c8 (its reason
# `main changed`, its time): both counted as shared, so they ran again. c8's line naming lib/w.test.sh with the reason
# `the card changed` is c8's own selection, which the links do not give: it still counts.
t_mainmovedgrow() {
  mainmoved '{"lib/rows.sh": ["lib/view.test.sh", "lib/y.test.sh", "lib/w.test.sh"], "lib/panel.sh": ["lib/view.test.sh", "lib/x.test.sh"]}' other
  jq -cn '{units: ["lib/view.test.sh", "lib/x.test.sh"], tested: true}' > "$FXWT.ready"
  jq -cn '{card: "c8-8", issue: 8, step: "test", result: "pass", times: {"lib/y.test.sh": 2},
    why: {"lib/view.test.sh": ["the card changed lib/panel.sh"], "lib/w.test.sh": ["the card changed lib/panel.sh"],
      "lib/y.test.sh": ["main changed lib/z.sh"]}}' >> "$ST/cards.jsonl"
  fx_in 't=$(sharedtests "$FXWT" "'"$m0"'"); echo "$? $t"'
  [ "$(tr '\n' ' ' < "$T/$CASE/run.out")" = "0 lib/view.test.sh lib/w.test.sh " ] \
    || fail "sharedtests() of c7 after c8 landed is not lib/view.test.sh and lib/w.test.sh alone: $(cat "$T/$CASE/run.out")"
}

# Bug (#451: #415's merge, which git called clean, left a test file with two openings and one end, and only its test
# step, minutes later, found the file no longer parsed; a broken file that no selected test loads would have landed).
# A clean three-way merge: a.test.mjs holds a test turned off in a block comment; #7 rewrites a line inside it to open a
# test of its own (still a comment: #7's file parses), and during its tests main turns the old test back on (main's
# file parses). Their lines are apart, so the three-way merge is clean with #7's lines as they were (settle()'s clean
# path, no session), and it leaves two openings and one end. The parse check finds it before any test runs on it, and
# #7's fix session is given the file and node's SyntaxError; #7 lands after it with a file that parses.
t_mergeparseclean() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
  printf '%s\n' "import test from 'node:test';" '/* off until a() is fixed' "test('one', () => {" '  a();' '  b();' '});' '*/' > "$R/a.test.mjs"
  git -C "$R" add a.test.mjs; git -C "$R" commit -qm "a test file"
  cat > "$STUB/build" <<'EOF'
if grep -q '^# A file no longer parses' "$STUB/brief"; then cp "$STUB/brief" "$STUB/parsebrief"; sed -i '2d' a.test.mjs
else sed -i "4s/.*/test('one, by the card', () => {/" a.test.mjs; fi
EOF
  cat >> "$STUB/test-cmd" <<'EOF'
[ -e "$STUB/moved" ] || { : > "$STUB/moved"; sed -i '2d;7d' "$R/a.test.mjs"; git -C "$R" commit -qam "main turns the test back on"; }
node --check a.test.mjs 2>/dev/null || cp a.test.mjs "$STUB/brokenrun"
EOF
  # loop: card() runs parses() before the test step, gives its failure to the fix session's brief and runs the tests whole after it: only a card run shows that order
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ ! -e "$STUB/brokenrun" ] || fail "a test step ran on the merged file that does not parse: $(cat "$STUB/brokenrun")"
  grep -q 'a\.test\.mjs: `node --check` failed:' "$STUB/parsebrief" 2>/dev/null && grep -q 'SyntaxError' "$STUB/parsebrief" \
    || fail "#7's fix session was not given the file that does not parse and its error: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test fix review test landed " ] \
    && st 'select(.step == "fix") | .reason' | grep -q 'no longer parses after the merge onto main: a.test.mjs' \
    || fail "#7 did not go from the parse check to its fix, then land: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  # A merge in doubt is a full run the owner allows (issue 461): the run after the parse fix is not refused.
  [ "$(st 'select(.issue == 7 and .step == "test") | .refused // "none"' | tr '\n' ' ')" = "none none " ] \
    || fail "the whole run after a merge in doubt was refused: $(st 'select(.step == "test") | .refused')"
  node --check "$R/a.test.mjs" || fail "main holds a file that does not parse: $(cat "$R/a.test.mjs")"
}

# The parse check's commands (parses()): the engine's own by file type, the pack's land.parse adding a glob (whose *
# matches a / too) and replacing one of the engine's, run on each file the change keeps; py_compile leaves no file in
# the worktree. A failure names the file and the command.
t_mergeparsepack() {
  eval "$(sed -n '/^PARSE=/p; /^parses() {/,/^}/p' "$SRC/lib/claim.sh")"
  packget() { printf -v "$2" '%s' '{"*.txt": "grep -qx ok", "*.js": "true"}'; }
  local w=$T/$CASE/w out
  mkdir -p "$w/d" && git -C "$w" init -q && echo gone > "$w/gone.sh" && git -C "$w" add -A && git -C "$w" -c user.name=t -c user.email=t@example.com commit -qm base
  echo ok > "$w/d/ok.txt"; echo 'x = (' > "$w/x.js"; echo 'print(1)' > "$w/p.py"; echo '{"a": 1}' > "$w/j.json"; rm "$w/gone.sh"; git -C "$w" add -A
  out=$(parses "$w") || fail "files that all parse were found not to: $out"
  [ -z "$(git -C "$w" ls-files -o)" ] || fail "the check left files in the worktree: $(git -C "$w" ls-files -o)"
  echo no > "$w/d/bad.txt"; echo 'if' > "$w/b.sh"; git -C "$w" add -A
  out=$(parses "$w"); [ $? = 1 ] && grep -q '^d/bad\.txt: `grep -qx ok` failed:' <<<"$out" && grep -q '^b\.sh: `bash -n` failed:' <<<"$out" \
    && [ "$(grep -c ' failed:$' <<<"$out")" = 2 ] || fail "the failing files were not each named with their command, and no other: $out"
}
