#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a later card of an issue whose change grows again, while a slice that an earlier card filed for its
# grown change is open (growopen(), growafter(), lib/slices.sh). What must stay true: an open grown slice is found
# whatever the owner edited in it, and an issue that only quotes one is not taken for it; the slices filed in its place
# keep what held it back (its hold, and the issues that wait on it), each only for the files it takes, also after a
# stop between the close and the filing; when that cannot be done, the new slices are withdrawn and the change is kept
# whole. The helpers (grownagain, grownwhy, GROWN) are slices.test.sh's, killatfile is splitresume.test.sh's: the
# runner sources every case file into one shell.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The body of <issue> in $STUB/filed made by the jq filter <filter> (on .body), its labels by <labels filter>.
editfiled() { # <issue> <filter> [<labels filter>]
  jq -c --argjson n "$1" "if .number == \$n then .body |= ($2) | .labels |= (${3:-.}) else . end" "$STUB/filed" > "$STUB/filed.new" \
    && mv "$STUB/filed.new" "$STUB/filed" || fail "#$1 could not be edited"
}
# gh issue list --label conveyor-followup gives only the issues with that label, as GitHub does.
listbylabel() {
  # stub: the shared gh stub's list reads $STUB/list-cmd; this one keeps the follow-up label's filter.
  printf '%s\n' 'case " $* " in *" --label conveyor-followup "*) issues() { jq -cs "(.[0] + .[1:]) | map(select(any(.labels[]?; .name == \"conveyor-followup\")))" "$STUB/issues.json" $(ls "$STUB/filed"); } ;; esac' > "$STUB/list-cmd"
}
# The answer of a judge that splits the grown change into two slices: src/s1.sh, then src/s2.sh.
GROWN2='{"verdict":"split","why":"apart","core":["src/c1.sh","src/c2.sh","src/c3.sh"],"slices":[{"title":"one","doneWhen":["a"],"files":["src/s1.sh"]},{"title":"two","doneWhen":["b"],"files":["src/s2.sh"]}]}'
# The shell a case runs before c7's growcheck: #100102 (src/x.sh) depends on #100101 (src/s1.sh), and GitHub refuses
# the edit of #100102's body.
DEPSFAIL='editfiled 100102 '\''. + "\nDepends on: #100101"'\''; eval "real_$(declare -f gh_write)"; gh_write() { [ "$1 $2 $3" != "issue edit 100102" ] || return 1; real_gh_write "$@"; }; '

# The owner edits the open slice #100101 (src/s1.sh and src/s2.sh): a heading and a note above its first line, its
# note reworded, its paths in backticks, and its follow-up label taken off (GitHub's list asked for that label then
# leaves it out). Bugs caught (review of #1684): each of these edits hid #100101, so the later card filed the same part
# again beside it, or did not see that it takes the same files. #100101 is closed and #100102 filed in its place.
t_slicesgrownedited() {
  grownagain '' 'listbylabel; editfiled 100101 '\''"## Status\nStill wanted.\n\n" + gsub("moved this part out"; "split this part out") | gsub("- src/(?<f>s[12]\\.sh)"; "- `src/\(.f)`")'\'' '\''map(select(.name != "conveyor-followup"))'\''; ' '["src/s1.sh","src/s2.sh"]'
  [ "$RC" = 2 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ "$(grownwhy)" = '["split",[100102],[100101],"the tests apart"]' ] \
    || fail "the edited open slice #100101 was not closed before #100102 was filed in its place (exit $RC): $(jq -r 'select(.number == 100101) | .body' "$STUB/filed") $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
}

# #100101 is no slice: an issue with no follow-up label that quotes a grown slice's body (src/s1.sh and src/s2.sh) in a
# code block. Bug caught (review of #1684): growopen() read the quoted lines as #100101's own, and the later card closed
# #100101. It stays open, and #100102 is filed with nothing withdrawn.
t_slicesgrownquoted() {
  grownagain '' 'editfiled 100101 '\''"A note on an old slice:\n\n```\n" + . + "\n```"'\'' '\''map(select(.name != "conveyor-followup"))'\''; ' '["src/s1.sh","src/s2.sh"]'
  [ "$RC" = 2 ] && [ ! -e "$STUB/closed" ] && [ "$(grownwhy)" = '["split",[100102],null,"the tests apart"]' ] \
    || fail "#100101, which only quotes a grown slice, was closed or taken for one (exit $RC): $(cat "$STUB/closed" 2>/dev/null) $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
}

# The owner rewrote the whole body of #100101, and its grown line (card c6's, filed after a restart would not have
# left it) names it with its files. Bug caught: a slice whose first line was edited was found by nothing, and its part
# was filed again. #100101 is closed, with the files of its grown line, and #100102 filed in its place.
t_slicesgrownrecorded() {
  grownagain '' 'editfiled 100101 '\''"Owner notes: keep this.\n\n## Done when\n- x"'\''; record c6 7 grown split "$(jq -cn '\''{grown: {mode: "on", files: 5, limit: 3, verdict: "split", why: "apart", core: ["src/c1.sh"],
    slices: [{title: "old", doneWhen: ["x"], files: ["src/s1.sh", "src/s2.sh"], dependsOn: []}], filed: [100101], after: 3}}'\'')"; ' '["src/s1.sh","src/s2.sh"]'
  [ "$RC" = 2 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ "$(grownwhy | tail -n 1)" = '["split",[100102],[100101],"the tests apart"]' ] \
    || fail "the rewritten open slice #100101, named by its grown line, was not closed before #100102 was filed (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
}

# The owner held the open slice #100101 (src/s1.sh); the open slice #100102 (src/x.sh) depends on it. The judge splits
# the change into #100103 (src/s1.sh, in #100101's place) and #100104 (src/s2.sh, a new part). Bugs caught (review of
# #1684): #100102 kept only `Depends on: #100101`, which is closed, so it could start once #7 landed, before #100103
# had; #100103 went in the queue with no hold; then both new slices were held, and #100102 waited on #100104 too,
# whose part has nothing to do with #100101. Only #100103 is held, and #100102 waits on it alone.
t_slicesgrowndeps() {
  grownagain "$GROWN2" 'locked control hold 100101 > /dev/null || exit 8; editfiled 100102 '\''. + "\nDepends on: #100101"'\''; ' '["src/s1.sh"]' '["src/x.sh"]'
  [ "$RC" = 2 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ "$(grownwhy)" = '["split",[100103,100104],[100101],"apart"]' ] \
    || fail "#100101 was not replaced by #100103 and #100104 (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  [ "$(jq -r 'select(.number == 100102) | .body | split("\n") | map(select(startswith("Depends on:"))) | join("|")' "$STUB/filed")" = 'Depends on: #7|Depends on: #100101, #100103' ] \
    || fail "#100102, which depended on the replaced #100101, does not wait on its replacement #100103 alone: $(jq -r 'select(.number == 100102) | .body' "$STUB/filed")"
  [ "$(jq -c '.held | [index(100103) != null, index(100104) != null]' "$ST/control.json")" = '[true,false]' ] \
    || fail "of the new slices, #100103 (in the held #100101's place) is not held, or #100104 (another part) is: $(jq -c .held "$ST/control.json")"
}

# GitHub refuses the edit that makes #100102, which depends on #100101, wait on its replacement #100103. Bug caught
# (review of #1684): the files went out of the change anyway, so #100102 could start before #100103 landed. #100103
# is withdrawn, and the change is kept whole with the reason.
t_slicesgrowndepsfail() {
  grownagain '' "$DEPSFAIL" '["src/s1.sh","src/s2.sh"]' '["src/x.sh"]'
  [ "$RC" = 0 ] && [ -e "$FXWT/src/s2.sh" ] && [ "$(cat "$STUB/closed" 2>/dev/null | tr '\n' ' ')" = '100101 100103 ' ] \
    || fail "with #100102's edit refused, #100103 was not withdrawn or the change not kept whole (exit $RC): $(cat "$STUB/closed" 2>/dev/null) $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "grown") | [.grown.filed, .grown.withdrawn, (.grown.why | test("the slices filed \\(#100103\\) are withdrawn, so the change is kept whole: #100102 waits on a slice withdrawn"))] | @json')" = '[null,[100101],true]' ] \
    || fail "the grown line does not say #100103 was withdrawn and why: $(cat "$ST/cards.jsonl")"
}

# The same, and GitHub refuses the close of #100103 too. Bug caught: the change was kept whole beside #100103, which
# could build its files a second time. The card is blocked (1), and its grown line says why. The refused edit says
# GitHub's error on stderr, as gh does, before `control depends` says its own. Bug caught: that reason of two lines
# reached block(), which keeps the first line only, so the blocked line did not say the close failed.
t_slicesgrownstuck() {
  grownagain '' "$DEPSFAIL"'gh_write() { [ "$1 $2 $3" != "issue edit 100102" ] || { echo "HTTP 502: Bad Gateway" >&2; return 1; }; [ "$1 $2 $3" != "issue close 100103" ] || return 1; real_gh_write "$@"; }; ' '["src/s1.sh","src/s2.sh"]' '["src/x.sh"]'
  [ "$RC" = 1 ] && [ "$(st 'select(.card == "c7") | .step' | tail -n 2 | tr '\n' ' ')" = 'grown blocked ' ] \
    || fail "with the close of #100103 refused, c7 was not blocked after its grown line (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  st 'select(.step == "blocked") | .reason' | grep -q 'GitHub did not confirm the close of the slices filed #100103; the change kept whole beside them could build their work twice' \
    || fail "c7's blocked line does not say why: $(st 'select(.step == "blocked") | .reason')"
}

# The owner holds the open slice #100101 (src/s1.sh and src/s2.sh) as c7 closes it to file #100102 in its place. Bug
# caught (review of #1684): the hold was read before the close, so #100102 went in the queue with no release from the
# owner. #100102 starts held.
t_slicesgrownheld() {
  grownagain '' 'eval "real_$(declare -f gh_write)"; gh_write() { [ "$1 $2 $3" != "issue close 100101" ] || locked control hold 100101 > /dev/null || exit 8; real_gh_write "$@"; }; ' '["src/s1.sh","src/s2.sh"]'
  [ "$RC" = 2 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ "$(jq -c '.held | index(100102) != null' "$ST/control.json")" = true ] \
    || fail "#100102, filed in place of #100101 held as it was closed, is not held (exit $RC): $(jq -c .held "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# The owner held the open slice #100101 (src/s1.sh and src/s2.sh); c7 closes it and is killed as it files its
# replacement, as a restart would stop it. Bug caught (review of #1684): c8 saw no open #100101 and queued #100102 with
# no hold. c8 reads c7's start line, and #100102 starts held.
t_slicesgrownheldstop() {
  grownagain '' 'locked control hold 100101 > /dev/null || exit 8; killatfile 1; echo "$BASHPID" > "$STUB/cardpid"; ' '["src/s1.sh","src/s2.sh"]'
  [ "$RC" = 137 ] && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] && [ "$(jq -s length "$STUB/filed")" = 1 ] \
    || fail "c7 was not killed after it closed #100101 and before it filed its replacement (exit $RC): $(cat "$T/$CASE/run.out")"
  openonly
  fx_in 'session() { echo "{}"; }; checked() { :; }; growcheck c8 7 "$FXWT" "$(big 7)" brief'
  [ "$RC" = 2 ] && [ "$(grownwhy)" = '["split",[100102],null,"the tests apart"]' ] && [ "$(jq -c '.held | index(100102) != null' "$ST/control.json")" = true ] \
    || fail "#100102, filed by c8 in place of the held #100101 that c7 closed, is not held (exit $RC): $(jq -c .held "$ST/control.json") $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
}
# GitHub's list of open issues leaves out those in $STUB/closed.
openonly() {
  # stub: the shared stub's list keeps a closed issue.
  printf '%s\n' '[ "$4" != open ] || issues() { jq -cs --rawfile cl "$STUB/closed" "(.[0] + .[1:]) | (\$cl | split(\"\n\")) as \$c | map(select(.number | tostring | IN(\$c[]) | not))" "$STUB/issues.json" $(ls "$STUB/filed"); }' > "$STUB/list-cmd"
}

# The same, and c7 is killed after it filed #100102 in place of the held #100101, before growafter(); the owner sets
# Split large issues Off. Bugs caught (review of #1684): #100102 stayed queued with no hold, as no card under Off read
# c7's filing; once given, the hold came back at each later card of #7 after the owner released #100102. c8 holds
# #100102 as it starts, its start line names #100101 as handed, and c9 leaves the released #100102 as it is.
t_slicesgrownresume() {
  grownagain '' 'locked control hold 100101 > /dev/null || exit 8; echo "$BASHPID" > "$STUB/cardpid"; growafter() { kill -9 "$(cat "$STUB/cardpid")"; sleep 5; }; ' '["src/s1.sh","src/s2.sh"]' # sleep: the subshell waits for the card's kill, so it never returns into a card that goes on
  [ "$RC" = 137 ] && [ "$(jq -sc 'map(.number)' "$STUB/filed")" = '[100101,100102]' ] && [ "$(jq -c '.held | index(100102) != null' "$ST/control.json")" = false ] \
    || fail "c7 was not killed after it filed #100102 and before it held it (exit $RC): $(jq -c .held "$ST/control.json") $(cat "$T/$CASE/run.out")"
  openonly; loop control rules split=off > /dev/null || fail "control rules split=off failed"
  fx_in 'splitcheck c8 7'
  [ "$RC" = 0 ] && [ "$(jq -c '.held | index(100102) != null' "$ST/control.json")" = true ] && [ "$(st 'select(.card == "c8") | .handed | @json')" = '[{"n":100101,"files":["src/s1.sh","src/s2.sh"]}]' ] \
    || fail "splitcheck c8 7 under Off did not hold #100102, filed in place of the held #100101 (exit $RC): $(jq -c .held "$ST/control.json") $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  recok "$ST/cards.jsonl" "a card that handed a stopped filing's holds on"
  loop control release 100102 > /dev/null || fail "control release 100102 failed"
  fx_in 'splitcheck c9 7'
  [ "$RC" = 0 ] && [ "$(jq -c '.held | index(100102) != null' "$ST/control.json")" = false ] \
    || fail "splitcheck c9 7 held #100102 again after the owner released it (exit $RC): $(jq -c .held "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# #100102 is an ordinary issue (no follow-up label) with `Depends on: #100101`, an open grown slice (src/s1.sh and
# src/s2.sh) that c7 closes to file #100103 in its place. Bug caught (review of #1684): from the close until growafter()
# #100102 waited on nothing open, so a loop turn could pick it before #100103 was filed; a refused edit then did not
# undo that pick. #100102 waits on #7 when #100101 closes, then on #100103 too.
t_slicesgrownwait() {
  grownagain '' 'editfiled 100102 '\''"Plain issue.\n\nDepends on: #100101"'\'' '\''map(select(.name != "conveyor-followup"))'\''; eval "real_$(declare -f gh_write)"
    gh_write() { [ "$1 $2 $3" != "issue close 100101" ] || jq -r '\''select(.number == 100102) | .body | split("\n") | map(select(startswith("Depends on:"))) | join("|")'\'' "$STUB/filed" > "$STUB/at-close"; real_gh_write "$@"; }; ' '["src/s1.sh","src/s2.sh"]' '["src/x.sh"]'
  [ "$RC" = 2 ] && [ "$(cat "$STUB/at-close" 2>/dev/null)" = 'Depends on: #100101, #7' ] \
    || fail "#100102 did not wait on #7 as c7 closed #100101, the slice it waits on (exit $RC): $(cat "$STUB/at-close" 2>/dev/null) $(cat "$T/$CASE/run.out")"
  [ "$(jq -r 'select(.number == 100102) | .body | split("\n") | map(select(startswith("Depends on:"))) | join("|")' "$STUB/filed")" = 'Depends on: #100101, #7, #100103' ] \
    || fail "#100102 does not wait on #100103, filed in place of #100101: $(jq -r 'select(.number == 100102) | .body' "$STUB/filed")"
}

# Run in c7 as GitHub closes #100101: #100102 comes to wait on #100101 just before the close (after growwait() read
# the open issues), then the pick's order (a dry pick: the same records and control record, and no write) is asked
# from the open list as GitHub gives it after the close (pick-at-close), and from the same list with #100102's
# `Depends on:` line left out (pick-nodep).
closepick() { # <gh_write's arguments>
  [ "$1 $2 $3" = "issue close 100101" ] || { real_gh_write "$@"; return; }
  jq -c 'if .number == 100102 then .body = "Plain issue.\n\nDepends on: #100101" | .labels = [] else . end' "$STUB/filed" > "$STUB/filed.new" && mv "$STUB/filed.new" "$STUB/filed" || exit 8
  real_gh_write "$@" || return
  jq -cs '.[0] + (.[1:] | map(select(.number != 100101) | . + {authorAssociation: "OWNER"}))' "$STUB/issues.json" "$STUB/filed" > "$STUB/open.json" || exit 8
  jq -c 'map(if .number == 100102 then .body = "Plain issue." else . end)' "$STUB/open.json" > "$STUB/nodep.json" || exit 8
  ( drypick "$STUB/open.json" "$ST" ) > "$STUB/pick-at-close"; ( drypick "$STUB/nodep.json" "$ST" ) > "$STUB/pick-nodep"
}
# #100102 (src/x.sh) comes to depend on the open grown slice #100101 (src/s1.sh and src/s2.sh) after c7's growwait()
# read the open issues, and before c7 closes #100101 to file #100103 in its place. Bug caught (review of #1684): from
# the close until growafter() #100102 waited on nothing open, so a pick there took it, and the edit after did not undo
# that. The pick at the close takes nothing, while the same list with no `Depends on:` line takes #100102: it waits on
# #7, whose filing names #100101 as replaced. growafter() then makes it wait on #100103.
t_slicesgrownwaitlate() {
  grownagain '' 'eval "real_$(declare -f gh_write)"; gh_write() { closepick "$@"; }; ' '["src/s1.sh","src/s2.sh"]' '["src/x.sh"]'
  [ "$RC" = 2 ] && [ "$(cat "$STUB/pick-nodep" 2>/dev/null)" = 100102 ] && [ -z "$(cat "$STUB/pick-at-close" 2>/dev/null)" ] \
    || fail "the pick as #100101 closed, from $(jq -c 'map({number, body})' "$STUB/open.json" 2>/dev/null), took $(cat "$STUB/pick-at-close" 2>/dev/null), not nothing (with no Depends on line: $(cat "$STUB/pick-nodep" 2>/dev/null), not 100102; exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(jq -r 'select(.number == 100102) | .body | split("\n") | map(select(startswith("Depends on:"))) | join("|")' "$STUB/filed")" = 'Depends on: #100101, #100103' ] \
    || fail "#100102 does not wait on #100103, filed in place of #100101: $(jq -r 'select(.number == 100102) | .body' "$STUB/filed")"
}

# The owner held #100101 (src/s1.sh and src/s2.sh); c7 closes it to file #100102 (src/s1.sh) and a slice for
# src/s2.sh in its place, and is killed as it files the second. c8 holds #100102 as it starts (growresume()). Bug
# caught (review of #1684): c8 marked all of #100101 as handed, though only its src/s1.sh had a slice, so c9, which
# files the slices again, filed the one for src/s2.sh (#100104) with no hold. c8 hands only src/s1.sh, and #100104
# starts held, as does #100103, filed in place of #100102.
t_slicesgrownhandedpart() {
  grownagain "$GROWN2" 'locked control hold 100101 > /dev/null || exit 8; killatfile 2; echo "$BASHPID" > "$STUB/cardpid"; ' '["src/s1.sh","src/s2.sh"]'
  [ "$RC" = 137 ] && [ "$(jq -sc 'map(.number)' "$STUB/filed")" = '[100101,100102]' ] \
    || fail "c7 was not killed after it filed #100102 and before its second slice (exit $RC): $(cat "$T/$CASE/run.out")"
  openonly
  fx_in 'splitcheck c8 7'
  [ "$RC" = 0 ] && [ "$(st 'select(.card == "c8" and .handed) | .handed | @json')" = '[{"n":100101,"files":["src/s1.sh"]}]' ] \
    || fail "splitcheck c8 7 did not hand #100101's src/s1.sh alone to #100102 (exit $RC): $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
  fx_in 'session() { echo "{}"; }; checked() { :; }; growcheck c9 7 "$FXWT" "$(big 7)" brief'
  [ "$RC" = 2 ] && [ "$(grownwhy)" = '["split",[100103,100104],[100102],"apart"]' ] && [ "$(jq -c '.held | [index(100103) != null, index(100104) != null]' "$ST/control.json")" = '[true,true]' ] \
    || fail "#100104, filed by c9 for src/s2.sh of the held #100101, or #100103, in place of the held #100102, is not held (exit $RC): $(jq -c .held "$ST/control.json") $(cat "$ST/cards.jsonl") $(cat "$T/$CASE/run.out")"
}

# The start line of c7's grown filing, which names the slices it closes, cannot be synced to disk (SYNCFAIL,
# splitresume.test.sh). Bug caught (review of #1684): it was appended with no sync, so a power cut after the close could
# lose it, and the next card filed the new slices with nothing of what held the closed one back. c7 closes nothing
# and ends (record(): a card with a worktree folder is blocked too; this one has none).
t_slicesgrownsync() {
  grownagain '' "$SYNCFAIL" '["src/s1.sh","src/s2.sh"]'
  [ "$RC" = 1 ] && [ ! -e "$STUB/closed" ] && grep -q 'conveyor: cannot record c7 start' "$T/$CASE/run.out" \
    || fail "c7, with its filing's start line not synced, closed #100101 or did not end (exit $RC): $(cat "$STUB/closed" 2>/dev/null) $(cat "$T/$CASE/run.out")"
}
