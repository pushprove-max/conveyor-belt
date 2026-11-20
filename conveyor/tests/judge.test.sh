#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the review's judge (judged()), which decides which findings of a review count.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The setup of a judge case: main holds b.txt beside a.txt (a card's build changes a.txt alone, so b.txt is outside
# its diff), and the stubs keep what they were asked. The stub reviewer is Codex's (x), so the judge is Claude's: a
# Claude call with the review's read-only tools is the judge, its prompt kept in $STUB/judge-asked, its answer
# $STUB/judge.<its number>; any other Claude call is a session, as in lib.sh.
judging() { # <issues json> [on | off: the control record's judge, on when not given] [a kind it always accepts]...
  setup "$1"; cksum < "$R/.conveyor/project.json" > "$STUB/pack.sum"
  loop control judge "${2:-on}" >/dev/null && loop control judge always "${@:3}" >/dev/null || fail "control judge did not take the judge's settings"
  echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm b; git -C "$R" push -q origin main
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"--tools Read,Grep,Glob"*)
  cat > "$STUB/judge-asked"; echo "$*" >> "$STUB/judges"; [ ! -f "$STUB/judge-cmd" ] || . "$STUB/judge-cmd"
  jq -cn --rawfile r "$STUB/judge.$(wc -l < "$STUB/judges")" '{type: "result", is_error: false, result: $r, usage: {input_tokens: 3, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 2}}'
  exit ;;
esac
cat > "$STUB/brief"; echo "$*" >> "$STUB/sessions"; . "$STUB/build"
echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'
EOF
}
rev() { st "select(.issue == $1 and .step == \"review\") | $2"; } # <issue> <jq filter>: of each of its review lines
# One review judged as a card's is (judged()), with no card run, for a case that proves what the judge does with a
# review: a card run pays for the loop, its sessions and waits around the one function.
# The card c<issue>'s worktree holds main with the stub build's change staged (a.txt gains a line 2), the review
# beside it is <review file> (with -, the stub reviewer's next review.<n>, written by review() as a card's review is,
# its prompt in $STUB/asked), and the engine shell is made as `conveyor.sh run` makes one. What judged() prints is in
# <worktree>.fields, with the verdict and counts the card's review line takes from the review after minor(), as
# card() does; the review it leaves is <worktree>.review, and with fix, for a NO-GO, what its fix round is told, as
# card() gives it (numbered(), fixlines()), is <worktree>.fix. The cases that need a whole card (its fix round and
# second review, its landing, the reviewer's brief card() builds, the snapshot) still run one.
judgeone() { # <issue> <review file | -> [fix]
  local wt=$T/$CASE/cards/c$1
  mkdir -p "$T/$CASE/cards" && git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && . "$STUB/build") && git -C "$wt" add -A \
    && { [ "$2" = - ] || cp "$2" "$wt.review"; } || fail "the worktree of c$1 could not be made"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && { [ "$2" != - ] || review "$wt" "body of $1" > /dev/null; } \
    && f=$(judged "c$1" "$1" "$wt" "body of $1" '{}') && minor "$wt" \
    && jq -c --arg v "$(verdict "$wt.review")" --argjson k "$(counts "$wt.review")" '. + {verdict: $v, counts: $k}' <<<"$f" > "$wt.fields" \
    && { [ "${3:-}" != fix ] || [ "$(verdict "$wt.review")" != NO-GO ] || { ids=$(numbered "$wt") && fixlines "$wt" "$ids" > "$wt.fix"; }; } ) \
    || fail "review() or judged() on c$1 failed"
}
jf() { jq -r "$2" "$T/$CASE/cards/c$1.fields"; } # <issue> <jq filter>: of what judged() printed for c<issue> (judgeone)
jr() { cat "$T/$CASE/cards/c$1.review"; }        # <issue>: the review judged() left for c<issue> (judgeone)

# Bugs: a finding about a file the card did not change is dropped before the judge sees it, or reaches the judge not
# marked as outside the card's diff; declined, it still leaves the review a NO-GO (a fix session); accepted (the
# change breaks that file), it leaves the review, so the card lands without its fix.
t_judgeoutside() {
  local f='[P1] b.txt:1 still reads the old first line of a.txt. Proof: b.txt:1'
  judging "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo "F1 DECLINE: not about this card's change" > "$STUB/judge.1"
  echo 'F1 ACCEPT: the change breaks the reader in b.txt. Cost to every card: none' > "$STUB/judge.2"
  judgeone 7 "$STUB/review"
  grep -qxF "F1 [outside the diff] $f" "$STUB/judge-asked" || fail "the finding outside the card's diff did not reach the judge marked as outside it: $(grep '^F1' "$STUB/judge-asked")"
  [ "$(jr 7 | tr '\n' '|')" = "DECLINED: $f (judge: not about this card's change)|USER-VISIBLE: no|VERDICT: GO|" ] && [ "$(jf 7 '.judge.declined[0].place')" = outside ] \
    || fail "a declined finding outside the diff did not leave the review a GO, or is not recorded as outside the diff: $(jr 7) $(jf 7 .judge)"
  judgeone 8 "$STUB/review"
  cmp -s "$STUB/review" "$T/$CASE/cards/c8.review" && [ "$(jf 8 '.judge.accepted[0] | [.place, .cost] | join(" ")')" = "outside none" ] \
    || fail "an accepted finding outside the diff did not leave the review a NO-GO holding it, or is not recorded as outside the diff with its cost: $(jr 8) $(jf 8 .judge)"
}

# Bugs: a review whose only finding the judge declines still says NO-GO and costs a fix round; the declined finding or
# the judge's reason is lost from the card's record, or never reaches the declined list; the judge runs on the reviewer's own model family.
t_judgedecline() {
  local f='[P1] a.txt:2 wrong word. Proof: a stub that returns garbage'
  judging "[$(issue 7 2026-01-01)]"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  echo 'F1 DECLINE: the proof needs a stub built to misbehave' > "$STUB/judge.1"
  judgeone 7 -
  [ "$(jf 7 .verdict)" = GO ] || fail "a review whose only finding was declined is not a GO: $(jr 7)"
  [ "$(jf 7 '.judge.declined | tojson')" = "$(jq -cn --arg f "$f" '[{n: 1, finding: $f, place: "inside", reason: "the proof needs a stub built to misbehave"}]')" ] \
    || fail "the review's fields do not hold the declined finding and the judge's reason: $(jf 7 '.judge | tojson')"
  # The declined list holds it once, with who declined it and why.
  [ "$(jq -c '[.card, .issue, .finding, .by, .why, (.time | fromdate | type)]' "$ST/declined.jsonl")" = "$(jq -cn --arg f "$f" '["c7", 7, $f, "judge", "the proof needs a stub built to misbehave", "number"]')" ] \
    || fail "the declined finding did not go to the declined list, once, with who declined it and why: $(cat "$ST/declined.jsonl" 2>&1)"
  jr 7 | grep -qxF "DECLINED: $f (judge: the proof needs a stub built to misbehave)" && [ "$(jf 7 '.counts | add')" = 0 ] \
    || fail "the review's text does not show the declined finding with its reason, or it is counted as a finding: $(jr 7)"
  grep -qxF "F1 [inside the diff] $f" "$STUB/judge-asked" && grep -q '^body of 7$' "$STUB/judge-asked" || fail "the judge was not given the finding marked as inside the diff, or the issue"
  # Bug (#534): the findings and the judge's reasons the Board shows were asked for by the old ASD-STE100 rule list,
  # not by the pinned STE80 Humanizer. Each prompt names the engine's own rules/ste80.md, a file that is there and the
  # same as this checkout's, asks for both passes, and holds none of the old rules.
  local a s
  for a in "$STUB/asked" "$STUB/judge-asked"; do
    s=$(grep -o 'by the method in the file [^ ]*/rules/ste80\.md (STE80 Humanizer)' "$a") && s=${s#by the method in the file } && s=${s% (STE80 Humanizer)} \
      && cmp -s "$s" "$SRC/rules/ste80.md" && grep -qF 'Apply both' "$a" && ! grep -qF 'Use common, simple words that have one meaning each' "$a" \
      && ! grep -qF 'Write a sentence that tells the reader to do something in 20 words or fewer' "$a" \
      || fail "${a##*/}: the prompt does not name the engine's rules/ste80.md and its two passes, or still holds the old STE rules: $(grep -c 'ste80\|Use common, simple words' "$a")"
  done
  # The reviewer is Codex's x: the judge is the first Claude model the pack lists for the review.
  [ "$(jf 7 .judge.model)" = claude-opus-5-5 ] && grep -q -- '--model claude-opus-5-5 ' "$STUB/judges" && [ "$(jf 7 .judge.tokens.claude)" = 5 ] \
    || fail "the judge did not run on a model of another family than the reviewer's, or what it used is not recorded: $(jf 7 '.judge | tojson')"
}

# Bugs (#539): the judge is not told the higher bar for a P2, so a rare-case or style P2 starts a fix round (a fix
# session and another review); a P2 it declines as `rare case` leaves the review a NO-GO, or is lost from the declined list.
t_judgerare() {
  local f='[P2] a.txt:2 breaks when two cards land in the same second. Proof: start two cards at once on a slow disk' l
  judging "[$(issue 7 2026-01-01)]"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 DECLINE: rare case: the proof needs an unusual timing' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  for l in 'A P2 finding has a higher bar. Accept a P2 only when it is inside the diff, its proof uses what the project really' \
    'runs, and it would cause a wrong result that users or the next card meet. Decline with the reason `rare case` a P2' \
    'whose proof needs an unusual input, timing or setup. Decline with the reason `style` a P2 about wording, naming or' \
    'form that causes no wrong result.'; do
    grep -qxF -- "$l" "$STUB/judge-asked" || fail "the judge's prompt does not hold the P2 bar: no line '$l'"
  done
  [ "$(jr 7 | tr '\n' '|')" = "DECLINED: $f (judge: rare case: the proof needs an unusual timing)|USER-VISIBLE: no|VERDICT: GO|" ] \
    || fail "a P2 the judge declined as a rare case did not leave the review a GO: $(jr 7)"
  [ "$(jq -c '[.finding, .by, .why]' "$ST/declined.jsonl")" = "$(jq -cn --arg f "$f" '[$f, "judge", "rare case: the proof needs an unusual timing"]')" ] \
    || fail "the rare-case P2 is not on the declined list, once, with the judge's reason: $(cat "$ST/declined.jsonl" 2>&1)"
}

# Bugs (#534): the writing method the reviewer and the judge read is missing, changed from the pinned upstream text,
# or kept without its licence; either file does not name the commit it was copied from. The hashes are the Git blob
# ids of SKILL.md and LICENSE at that commit upstream, so an edit to the copied text fails here.
t_ste80pin() {
  local c=0d6f7994a581205aba615e0663a4c509d8a35c7d m=$SRC/rules/ste80.md l=$SRC/rules/ste80-LICENSE
  [ -s "$m" ] && [ -s "$l" ] || fail "rules/ste80.md or rules/ste80-LICENSE is missing"
  head -n 3 "$m" | grep -qF "$c" && [ "$(tail -n +4 "$m" | git hash-object --stdin)" = b909e8836f8583827457953e7db39e127b2799ab ] \
    || fail "rules/ste80.md does not name commit $c in its note, or is not SKILL.md of that commit below the note"
  head -n 3 "$l" | grep -qF "$c" && [ "$(sed -n '5,25p' "$l" | git hash-object --stdin)" = 58050cd3a39ad49548d10eb7b80d7de6933c3b7e ] \
    && grep -qF 'is adapted from blader/humanizer' "$l" \
    || fail "rules/ste80-LICENSE does not name commit $c, or does not hold LICENSE of that commit and the notice for the part it adapts"
}

# Bugs: an accepted finding causes no fix; the fix session is told the findings the judge declined too; a finding
# declined earlier on the issue is not given to the next judge.
t_judgeaccept() {
  judging "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P1] a.txt:1 wrong word' '[P2] a.txt:2 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P1] a.txt:12 another word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  printf '%s\n' 'F1 ACCEPT: the word is wrong for every reader. Cost to every card: one more test run' 'F2 DECLINE: a matter of taste' > "$STUB/judge.1"
  echo 'F1 DECLINE: no such line' > "$STUB/judge.2"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(rev 7 .result | tr '\n' ' ')" = "NO-GO GO " ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] || fail "an accepted finding did not send the card to one fix: $(rev 7 .result | tr '\n' ' ')"
  grep -qxF 'E1 [P1] a.txt:1 wrong word' "$STUB/brief" && ! grep -q 'a nit' "$STUB/brief" || fail "the fix prompt does not hold the accepted finding alone: $(grep 'a.txt:' "$STUB/brief")"
  [ "$(rev 7 '.judge.accepted[0] | [.reason, .cost] | join(" | ")' | head -n 1)" = "the word is wrong for every reader | one more test run" ] && [ "$(rev 7 '.counts | tojson' | head -n 1)" = '{"P0":0,"P1":1,"P2":0,"P3":0}' ] \
    || fail "the accepted finding's reason and cost are not recorded, or the declined one is counted: $(rev 7 '.judge | tojson' | head -n 1)"
  grep -qxF -- '- [P2] a.txt:2 a nit (declined: a matter of taste)' "$STUB/judge-asked" || fail "the second judge was not given the finding declined before on this issue"
  [ "$(jq -r '"\(.by): \(.finding)"' "$ST/declined.jsonl" | tr '\n' ,)" = 'judge: [P2] a.txt:2 a nit,judge: [P1] a.txt:12 another word,' ] \
    || fail "the declined list does not hold the declined findings alone, each once: $(cat "$ST/declined.jsonl" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ ! -e "$STUB/filed" ] || fail "the card did not land, or a declined finding was filed as a follow-up"
}

# Bugs: a line the reviewer itself starts with `DECLINED:` is taken as a finding the judge declined: it counts for
# nothing and the review is a GO, with the judge off (no judge ever ran) or on (the judge is never asked about it),
# and a finding of an always-accepted kind slips past that way.
t_judgeforged() {
  local f='[P1][security] a.txt:2 exposed token'
  judging "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" off
  printf '%s\n' "DECLINED: $f" 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"; cp "$STUB/review.1" "$STUB/review.2"
  judgeone 7 -
  [ "$(jf 7 .verdict)" = NO-GO ] && [ "$(jf 7 .counts.P1)" = 1 ] && jr 7 | grep -qxF "$f" && [ ! -e "$STUB/judges" ] \
    || fail "with the judge off, a DECLINED line the reviewer wrote did not count as the finding it is: $(jr 7) $(jf 7 .)"
  loop control judge on >/dev/null && loop control judge always security >/dev/null || fail "control judge did not take the judge's settings"
  echo 'F1 DECLINE: cannot happen. Cost to every card: none' > "$STUB/judge.1"
  judgeone 8 -
  grep -qxF "F1 [inside the diff; always accepted: security] $f" "$STUB/judge-asked" || fail "a DECLINED line the reviewer wrote did not reach the judge as a finding of its kind: $(grep '^F[0-9]' "$STUB/judge-asked" 2>&1)"
  [ "$(jf 8 .verdict)" = NO-GO ] && jr 8 | grep -qxF "$f" && [ "$(jf 8 '.judge.accepted[0].finding')" = "$f" ] && [ ! -s "$ST/declined.jsonl" ] \
    || fail "a DECLINED line the reviewer wrote was not judged as a finding of its kind, or it is in the declined list: $(jr 8) $(jf 8 .judge)"
}

# Bugs: a finding that names its file by the worktree's whole path is marked outside the card's diff, so the judge is
# told to decline what the card changed; the name of an always-accepted kind anywhere in a finding (here in its
# proof) makes it one of that kind, so it is accepted whatever the judge says.
t_judgemarks() {
  local f='[P2] a.txt:2 typo. Proof: section heading [security]'
  judging "[$(issue 7 2026-01-01)]" on security
  # The first finding names a.txt by the path of the card's worktree (judgeone's), as a reviewer run there may.
  printf '%s\n' "[P1] $T/$CASE/cards/c7/a.txt:2 wrong word" "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 DECLINE: no' 'F2 DECLINE: a matter of taste' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  grep -qxF "F1 [inside the diff] [P1] $T/$CASE/cards/c7/a.txt:2 wrong word" "$STUB/judge-asked" || fail "a finding that names its file by the worktree's whole path was not marked as inside the diff: $(grep '^F1' "$STUB/judge-asked" 2>&1)"
  grep -qxF "F2 [inside the diff] $f" "$STUB/judge-asked" || fail "a finding whose proof holds a kind's name in brackets was marked as of that kind: $(grep '^F2' "$STUB/judge-asked" 2>&1)"
  [ "$(jr 7 | tail -n 1)" = 'VERDICT: GO' ] && [ "$(jf 7 '.judge.declined | length')" = 2 ] || fail "the two declined findings did not leave the review a GO: $(jr 7) $(jf 7 .judge)"
}

# Bug: a finding that came back carries its id mark ([E2], REREVIEW) beside its kind mark, and the judge no longer
# read its kind, so an always-accepted finding could be declined. It calls judgemarks() alone: no card runs.
t_judgeidmark() {
  local w=$T/$CASE/w m; mkdir -p "$w" && git -C "$w" init -q || fail "the worktree could not be made"
  printf '%s\n' '[P1] [E2][security] a.txt:2 exposed token' '[P1][security] [E3] a.txt:3 exposed key' '[P1] a.txt:4 plain' > "$w.review"
  # shellcheck disable=SC2034 # STE is read by the sourced lib/review.sh
  m=$(eval "$(grep -E '^(ROLLOUT|NOTFINDING|RX)=' "$SRC/lib/prompts.sh")"; STE=''; . "$SRC/lib/review.sh"; judgemarks "$w" '["security"]')
  [ "$(jq -c 'map(.kind)' <<<"$m")" = '["security","security",null]' ] || fail "a finding with an id mark lost its always-accepted kind: $m"
}

# Bug: a judge call that fails blocks the card or drops its findings, instead of leaving every finding accepted. An
# answer that cannot be read is t_judgeunread's.
t_judgefail() {
  judging "[$(issue 7 2026-01-01)]"
  echo "$NOGO" > "$STUB/review"
  echo 'exit 1' > "$STUB/judge-cmd"
  judgeone 7 "$STUB/review"
  [ -e "$STUB/judges" ] && cmp -s "$STUB/review" "$T/$CASE/cards/c7.review" && [ "$(jf 7 .verdict)" = NO-GO ] \
    || fail "a failing judge call did not leave the finding accepted, the review as the reviewer wrote it: $(jr 7)"
  [ -n "$(jf 7 '.judge.failed // empty')" ] || fail "the review's fields do not say the judge failed: $(jf 7 '.judge | tojson')"
}

# Bug: with the judge off, a review is judged all the same (a judge call, a finding declined, the reviewer
# asked to tag kinds), instead of every finding counting as before.
t_judgeoff() {
  judging "[$(issue 7 2026-01-01)]" off security
  echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"; echo 'F1 DECLINE: no' > "$STUB/judge.1"
  loop run >/dev/null || fail "run exited non-zero"
  [ ! -e "$STUB/judges" ] && [ "$(rev 7 'has("judge")' | tr '\n' ' ')" = "false false " ] || fail "a judge was asked, or a review line holds one, with the judge off"
  [ "$(rev 7 .result | tr '\n' ' ')" = "NO-GO GO " ] && [ "$(wc -l < "$STUB/sessions")" = 2 ] && grep -qxF 'E1 [P1] a.txt:1 wrong word' "$STUB/brief" \
    || fail "with the judge off, a NO-GO did not go to its fix and a second review as before: $(rev 7 .result | tr '\n' ' ')"
  ! grep -q 'always accepts' "$STUB/asked" && [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "the reviewer was asked to tag kinds with the judge off, or the card did not land"
  [ "$(loop snapshot --fresh | jq -c '.landed[0].rounds | map(.judge)')" = '[{"ran":false,"why":"the judge is off"},{"ran":false,"why":"the review had no finding"}]' ] \
    || fail "the snapshot does not say the judge did not run on the reviews, with why (it is off; no finding)"
}

# Bugs: the judge is switched on or off only by a commit to the pack, so the owner cannot switch it from the Board;
# `control judge on` or `off` reaches a later card only, not the next review.
t_judgeswitch() {
  judging "[$(issue 8 2026-01-02),$(issue 9 2026-01-03)]" off
  printf '%s\n' '[P1] a.txt:2 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 DECLINE: a matter of taste' > "$STUB/judge.1"
  # Off: no judge is asked (a card's review with the judge off is t_judgeoff's).
  [ "$(loop control | jq -c .judgeOn)" = false ] || fail "the control record does not say the judge is off: $(loop control)"
  [ "$(loop control judge on | jq -c .judgeOn)" = true ] || fail "control judge on did not switch the judge on in the control record"
  judgeone 8 "$STUB/review"
  [ "$(jf 8 '[.verdict, (.judge.declined | length)] | join(" ")')" = "GO 1" ] && [ "$(wc -l < "$STUB/judges")" = 1 ] \
    || fail "control judge on did not have the next review judged: $(jf 8 .)"
  [ "$(loop control judge off | jq -c .judgeOn)" = false ] || fail "control judge off did not switch the judge off in the control record"
  judgeone 9 "$STUB/review"
  [ "$(jf 9 '[.verdict, has("judge")] | join(" ")')" = "NO-GO false" ] && [ "$(wc -l < "$STUB/judges")" = 1 ] && cmp -s "$STUB/review" "$T/$CASE/cards/c9.review" \
    || fail "control judge off did not leave the next review unjudged: $(jf 9 .)"
  [ "$(cksum < "$R/.conveyor/project.json")" = "$(<"$STUB/pack.sum")" ] || fail "switching the judge changed the pack"
  loop control judge on off >/dev/null 2>&1; [ $? = 2 ] || fail "control judge on took a second word"
}

# Bugs: the always-accepted kinds are the pack's, so naming one takes a commit; `control judge always` with no kind
# leaves the old kinds in force; a kind that is not one word (it would close the tag the reviewer writes) is taken.
t_judgekinds() {
  local i
  judging "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"
  [ "$(loop control judge always security data security | jq -c .judgeAlways)" = '["security","data"]' ] || fail "control judge always did not write the kinds, each once, to the control record"
  for i in 1 3; do printf '%s\n' '[P1][security] a.txt:2 the token is logged' '[P1][data] a.txt:2 the rows are dropped' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  echo "$GO" > "$STUB/review.2"
  printf '%s\n' 'F1 DECLINE: cannot happen. Cost to every card: none' 'F2 DECLINE: cannot happen. Cost to every card: none' > "$STUB/judge.1"
  printf '%s\n' 'F1 DECLINE: cannot happen' 'F2 DECLINE: cannot happen' > "$STUB/judge.2"
  # A whole card: card() itself adds the kinds to the reviewer's brief, and its fix brief is what the fix is told.
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  grep -q 'always accepts a finding of one of these kinds: security, data\.' "$STUB/asked" || fail "the reviewer was not told the kinds the control record names"
  [ "$(rev 7 .result | tr '\n' ' ')" = "NO-GO GO " ] && [ "$(rev 7 '.judge // empty | [(.accepted | length), (.declined | length)] | join(" ")')" = "2 0" ] \
    && grep -qxF 'E1 [P1][security] a.txt:2 the token is logged' "$STUB/brief" && grep -qxF 'E2 [P1][data] a.txt:2 the rows are dropped' "$STUB/brief" \
    || fail "a finding of a kind control judge always names was not accepted against the judge's decline: $(rev 7 '[.result, .judge] | tojson' | tr '\n' ' ')"
  # No kind clears them: the same findings are the judge's to decline, and the reviewer is asked for no tag. A whole
  # card again: card() builds the reviewer's brief inline from what judgeon() gives, so only its run shows that an
  # empty list adds no tag text while the judge stays on.
  [ "$(loop control judge always | jq -c .judgeAlways)" = '[]' ] || fail "control judge always with no kind did not clear the kinds"
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(rev 8 '[.result, (.judge.declined | length)] | join(" ")')" = "GO 2" ] && ! grep -q 'always accepts' "$STUB/asked" \
    || fail "with the kinds cleared, a finding once of one was still accepted whatever the judge said, or the reviewer was asked to tag: $(rev 8 '[.result, .judge] | tojson' | tr '\n' ' ')"
  loop control judge always 'a]b' >/dev/null 2>&1; [ $? = 2 ] && [ "$(loop control | jq -c .judgeAlways)" = '[]' ] || fail "control judge always took a kind that is not one word"
  [ "$(cksum < "$R/.conveyor/project.json")" = "$(<"$STUB/pack.sum")" ] || fail "naming the kinds changed the pack"
}

# Bugs: a finding of a kind the project always accepts is declined because the judge said so, inside the card's diff or
# outside it, or is accepted with no cost to every card; an unchanged line beside the card's changed line (a.txt:1, in
# the hunk's context) is marked inside its diff. That the reviewer is told to tag the kinds, and the fix is told the
# accepted findings, is t_judgekinds'.
t_judgealways() {
  judging "[$(issue 7 2026-01-01)]" on security
  printf '%s\n' '[P1][security] a.txt:2 the token is logged' '[P1][security] b.txt:1 a secret is kept here' '[P2] a.txt:1 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 DECLINE: cannot happen. Cost to every card: none' "F2 DECLINE: not about this card's change. Cost to every card: one more scan" 'F3 DECLINE: a matter of taste' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  grep -qxF 'F1 [inside the diff; always accepted: security] [P1][security] a.txt:2 the token is logged' "$STUB/judge-asked" \
    && grep -qxF 'F2 [outside the diff; always accepted: security] [P1][security] b.txt:1 a secret is kept here' "$STUB/judge-asked" \
    || fail "the judge was not told which findings are always accepted: $(grep '^F[0-9]' "$STUB/judge-asked")"
  grep -qxF 'F3 [outside the diff] [P2] a.txt:1 a nit' "$STUB/judge-asked" || fail "a finding on an unchanged line beside the changed one was not marked as outside the diff: $(grep '^F3' "$STUB/judge-asked")"
  [ "$(jf 7 '.judge // empty | [(.accepted | map(.place) | join(",")), (.declined | map(.finding) | join(","))] | join(" / ")')" = "inside,outside / [P2] a.txt:1 a nit" ] \
    || fail "a finding of an always-accepted kind was not accepted against the judge's decline, inside the diff and outside it: $(jf 7 '.judge | tojson')"
  [ "$(jf 7 '.judge // empty | .accepted | map(.cost) | join(" / ")')" = "none / one more scan" ] && jf 7 '.judge // empty | .accepted[0].reason' | grep -qxF 'always accepted: a security finding (the judge declined it: cannot happen)' \
    || fail "an always-accepted finding the judge declined is recorded without its cost to every card: $(jf 7 '.judge | tojson')"
  [ "$(jr 7 | tr '\n' '|')" = '[P1][security] a.txt:2 the token is logged|[P1][security] b.txt:1 a secret is kept here|DECLINED: [P2] a.txt:1 a nit (judge: a matter of taste)|USER-VISIBLE: no|VERDICT: NO-GO|' ] \
    || fail "the review does not keep the always-accepted findings, alone, as findings of a NO-GO: $(jr 7)"
}

# Bugs: an answer that cannot be read is taken in part: one with a decision for a finding the review does not hold
# makes the review a GO; an ACCEPT with no cost to every card, or a decline of an always-accepted finding with none,
# is recorded as an accepted finding with no cost; one with no line for a finding is taken for the findings it has a
# line for. Each leaves every finding accepted (the review as the reviewer wrote it) and says the judge failed.
t_judgeunread() {
  local i
  judging "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03),$(issue 10 2026-01-04)]" on security
  printf '%s\n' '[P1] a.txt:2 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.7"; cp "$STUB/review.7" "$STUB/review.8"
  printf '%s\n' '[P1][security] a.txt:2 the token is logged' '[P2] a.txt:2 a nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.9"
  echo "$NOGO3" > "$STUB/review.10"
  printf '%s\n' 'F1 DECLINE: unrelated' 'F2 ACCEPT: broken. Cost to every card: none' > "$STUB/judge.1"
  echo 'F1 ACCEPT: the change breaks its caller' > "$STUB/judge.2"
  printf '%s\n' 'F1 DECLINE: cannot happen' 'F2 DECLINE: a matter of taste' > "$STUB/judge.3"
  printf '%s\n' 'F1 DECLINE: no' 'F3 DECLINE: no' > "$STUB/judge.4"
  for i in 7 8 9 10; do
    judgeone $i "$STUB/review.$i"
    cmp -s "$STUB/review.$i" "$T/$CASE/cards/c$i.review" && [ -n "$(jf $i '.judge.failed // empty')" ] && [ "$(jf $i '.judge // empty | has("accepted") or has("declined")')" = false ] \
      || fail "#$i: a judge's answer that cannot be read (7: a decision too many; 8: an ACCEPT with no cost; 9: an always-accepted finding with no cost; 10: no line for a finding) was taken: $(jr $i) $(jf $i .judge)"
  done
  [ "$(wc -l < "$STUB/judges")" = 4 ] && [ ! -s "$ST/declined.jsonl" ] || fail "a judge was not asked each review, or a finding of an answer not read went to the declined list: $(cat "$ST/declined.jsonl" 2>&1)"
}

# Bugs: the owner cannot name the judge's CLI and model, or only a model the pack lists; a judge set to the
# reviewer's own CLI is skipped for the default (#441: the owner may pick it), so the reviews are not read by it.
t_judgemodel() {
  judging "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"
  printf '%s\n' '[P1] a.txt:2 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 DECLINE: no' > "$STUB/judge.1"
  # j is in none of the pack's lists: Claude Code lists no models, so any name it is given is its own.
  [ "$(loop control judge claude j high | jq -c .judge)" = '{"cli":"claude","model":"j","effort":"high"}' ] || fail "control judge did not set the judge's CLI, model and effort"
  loop control judge j >/dev/null 2>&1 && fail "control judge took a model with no CLI"
  # What the Board is given: the judge's model and effort, the model it runs on at default (the first of another
  # family than the reviewer's), and for its choices every model the pack allows the review, the reviewer's too.
  [ "$(loop snapshot --fresh | jq -c '.modelSettings.judge | [.model, .effort, .modelFrom, .effortFrom, .default, .agent, (.choices | index("x") != null), .choices[-1]]')" \
    = '["j","high","control","control","claude-opus-5-5","claude",true,"claude-fable-5-2"]' ] \
    || fail "the snapshot does not give the Board the judge's settings, its default and every model of the review: $(loop snapshot --fresh | jq -c .modelSettings.judge)"
  judgeone 7 "$STUB/review"
  grep -q -- '--model j --effort high ' "$STUB/judges" && [ "$(jf 7 .judge.model)" = j ] || fail "the judge did not run on the model the control record names: $(cat "$STUB/judges")"
  # Codex runs the reviewer too, and a Codex judge is the judge: no review ran on Codex here, so its call is Codex's
  # first, its answer is review.1, and it is asked the finding.
  echo 'F1 DECLINE: no' > "$STUB/review.1"
  loop control judge codex x >/dev/null || fail "control judge refused a Codex model"
  [ "$(loop snapshot --fresh | jq -c '.modelSettings.judge | [.model, .effort, .modelFrom, .agent]')" = '["x","medium","control","codex"]' ] \
    || fail "the snapshot does not show the judge on the reviewer's CLI as the one in force: $(loop snapshot --fresh | jq -c .modelSettings.judge)"
  judgeone 8 "$STUB/review"
  [ "$(jf 8 '[.verdict, .judge.model] | join(" ")')" = "GO x" ] && [ "$(wc -l < "$STUB/judges")" = 1 ] && grep -qx 'F1 \[[a-z ]*\] \[P1\] a.txt:2 wrong word' "$STUB/asked" \
    || fail "the judge on the reviewer's CLI did not read the review, or another judge ran: $(jf 8 '.judge | tojson') $(wc -l < "$STUB/judges")"
  [ "$(loop control judge default | jq -c .judge)" = null ] || fail "control judge default did not clear the setting"
}

# Bugs: the judge set to an OpenCode model runs on Claude, or OpenCode outside the worktree or with tools that write
# (or as the host's default agent, whose own permissions could allow them);
# its answer is not read as a Claude judge's is (the finding it declined still costs a fix round); what it used and
# cost is not on the review's line.
t_judgeopencode() {
  local f='[P1] a.txt:2 wrong word. Proof: a stub that returns garbage'
  judging "[$(issue 7 2026-01-01)]"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  cat > "$STUB/opencode" <<'EOF'
#!/usr/bin/env bash
[ "$1" != models ] || { echo prov/m-2; exit 0; }
cat > "$STUB/oc-asked"; printf '%s\n' "$*" >> "$STUB/oc-runs"; printf '%s\n' "$PWD" "$OPENCODE_CONFIG_CONTENT" > "$STUB/oc-env"
echo '{"type":"step_start","timestamp":1,"sessionID":"s","part":{"type":"step-start"}}'
echo '{"type":"text","timestamp":1,"sessionID":"s","part":{"type":"text","text":"F1 DECLINE: the proof needs a stub built to misbehave"}}'
echo '{"type":"step_finish","timestamp":1,"sessionID":"s","part":{"type":"step-finish","reason":"stop","cost":0.5,"tokens":{"input":30,"output":4,"reasoning":1,"cache":{"read":9,"write":2}}}}'
EOF
  chmod +x "$STUB/opencode"
  [ "$(loop control judge opencode prov/m-2 | jq -c .judge)" = '{"cli":"opencode","model":"prov/m-2","effort":null}' ] || fail "control judge did not take an OpenCode model"
  judgeone 7 "$STUB/review"
  [ ! -e "$STUB/judges" ] && [ "$(cat "$STUB/oc-runs")" = 'run --pure --format json --agent conveyor-readonly -m prov/m-2 --variant medium' ] \
    && [ "$(sed -n 1p "$STUB/oc-env")" = "$T/$CASE/cards/c7" ] && sed -n 2p "$STUB/oc-env" | jq -e '.permission["*"] == "deny" and .agent["conveyor-readonly"].permission == .permission' >/dev/null \
    || fail "the OpenCode judge did not run on OpenCode, read-only in the worktree: $(cat "$STUB/judges" "$STUB/oc-runs" "$STUB/oc-env" 2>&1)"
  grep -qxF "F1 [inside the diff] $f" "$STUB/oc-asked" && grep -q '^body of 7$' "$STUB/oc-asked" || fail "the OpenCode judge was not given the finding and the issue"
  [ "$(jf 7 .verdict)" = GO ] && [ "$(jf 7 '.judge.declined[0].reason')" = 'the proof needs a stub built to misbehave' ] \
    || fail "the OpenCode judge's decline was not read as a Claude judge's is: $(jr 7) $(jf 7 .judge)"
  # Its cost is in its usage (usage.cost), where an OpenCode step's is priced from, as a build's and a review's are.
  [ "$(jf 7 '.judge | [.model, .effort, .tokens, .usage, .cost] | tojson')" = '["opencode:prov/m-2","medium",{"codex":37},{"input":30,"write":2,"read":9,"output":5,"cost":0.5},null]' ] \
    || fail "what the OpenCode judge used and cost is not in the usage on the review's fields: $(jf 7 '.judge | tojson')"
}

# Bugs: the snapshot says nothing of the judge on a card's reviews, so the Board cannot show what the judge accepted
# and declined; a GO the judge made (it declined every finding) reads as the reviewer's own; a review whose judge call
# failed, or that held no finding to judge, reads as judged.
# The judge names a finding of the review it reads by its number (F1, F2 ...) in its reasons. Bugs: the snapshot's
# declined line does not give the review it was declined in, or numbers that review's findings otherwise than the judge
# did (a line that is no finding, as an UNPROVEN one, counted; a declined finding left out or put last); a line whose
# review is not in the card's records gets findings of another; the judge is not asked to quote the file and line of
# a finding it names, so its reason does not read on its own. The numbering is read from the review's text, which the
# record cuts at 1,500 characters, so a long review loses every reference; a retried card's records (moved to the
# retried file) are not read, so its references are lost too.
t_judgeref() {
  local out want bug="[P1] a.txt:3 a real bug. Proof: it breaks$(printf ', again%.0s' {1..250})"
  judging "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P1] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' 'UNPROVEN: a.txt:9 may be slow' '[P2] a.txt:2 a nit. Proof: it reads oddly' "$bug" '[P2] a.txt:2 the same nit. Proof: it reads oddly' \
    'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo "$GO" > "$STUB/review.3"
  echo 'F1 ACCEPT: the word is wrong. Cost to every card: none' > "$STUB/judge.1"
  printf '%s\n' 'F1 DECLINE: a matter of taste' 'F2 ACCEPT: it breaks. Cost to every card: none' 'F3 DECLINE: this is F1 (a.txt:2) again with nothing new' > "$STUB/judge.2"
  loop run >/dev/null || fail "run exited non-zero"
  grep -qF "quotes that finding's file and line beside it" "$STUB/judge-asked" || fail "the judge is not asked to quote the file and line of a finding it names by its number"
  loop declined add c9-9 9 judge 'this is F1 again' '[P2] z.txt:1 of no review' || fail "a declined line was not taken"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(rev 7 'select(.judge.declined | length > 0) | .reason | length')" -le 1500 ] && ! rev 7 'select(.judge.declined | length > 0) | .reason' | grep -qF 'the same nit' \
    || fail "the review's text in the record was not cut short before its last finding, so the case does not show a long review"
  want=$(jq -cn --arg b "$bug" '[2, [{n: 1, finding: "[P2] a.txt:2 a nit. Proof: it reads oddly"}, {n: 2, finding: $b}, {n: 3, finding: "[P2] a.txt:2 the same nit. Proof: it reads oddly"}]]')
  [ "$(jq -c '.declined[] | select(.finding | startswith("[P2] a.txt:2 the same nit")) | [.round, .findings]' <<<"$out")" = "$want" ] \
    || fail "the declined line does not give its review round and that review's findings as the judge numbered them: $(jq -c '.declined' <<<"$out")"
  [ "$(jq -c '.declined[] | select(.card == "c9-9") | [.round, .findings]' <<<"$out")" = '[null,null]' ] \
    || fail "a declined line with no review in the card's records was given one: $(jq -c '.declined' <<<"$out")"
  # The card's lines moved to the retried file, as `retry` moves a blocked card's: its findings are still found.
  jq -c 'select(.issue == 7)' "$ST/cards.jsonl" >> "$ST/retried.jsonl" && jq -c 'select(.issue != 7)' "$ST/cards.jsonl" > "$ST/cards.new" && mv -f "$ST/cards.new" "$ST/cards.jsonl"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero after the retry"
  [ "$(jq -c '.declined[] | select(.finding | startswith("[P2] a.txt:2 the same nit")) | [.round, .findings]' <<<"$out")" = "$want" ] \
    || fail "a retried card's declined line lost its review round and findings: $(jq -c '.declined' <<<"$out")"
}

t_judgesnapshot() {
  local out
  judging "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"
  printf '%s\n' '[P1] a.txt:1 wrong word' '[P2] a.txt:2 a nit' '[P2] a.txt:3 another nit' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  printf '%s\n' '[P1] a.txt:12 another word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo "$NOGO" > "$STUB/review.3"; echo "$GO" > "$STUB/review.4"
  printf '%s\n' 'F1 ACCEPT: the word is wrong for every reader. Cost to every card: none' 'F2 DECLINE: a matter of taste' 'F3 DECLINE: a matter of taste too' > "$STUB/judge.1"
  echo 'F1 DECLINE: no such line' > "$STUB/judge.2"
  # Whole cards, because the snapshot is read from the records card() writes: the review lines with their judge
  # fields over two rounds and a fix, a failed judge call's line, and the track's review steps; records written here
  # by hand would show only that the snapshot reads what the test wrote. One run, a card at a time (max-cards 1), #7
  # first: its two reviews are the judge's first two calls, so the third, #8's first, is the one that fails.
  echo '[ "$(wc -l < "$STUB/judges")" -lt 3 ] || exit 1' > "$STUB/judge-cmd"
  loop run --only 7,8 1 >/dev/null || fail "run of #7 and #8 exited non-zero"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.landed[] | select(.issue == 7) | .rounds | map(.judge)' <<<"$out")" = '[{"ran":true,"accepted":1,"declined":2,"go":false},{"ran":true,"accepted":0,"declined":1,"go":true}]' ] \
    || fail "#7's reviews do not give one accepted and two declined, then a GO the judge made: $(jq -c '.landed[] | select(.issue == 7) | .rounds' <<<"$out")"
  [ "$(jq -c '.landed[] | select(.issue == 8) | .rounds | map(.judge | [.ran, (.why | test("^the judge call failed")), .why])' <<<"$out")" = '[[false,true,"'"$(rev 8 '.judge.failed // empty')"'"],[false,false,"the review had no finding"]]' ] \
    || fail "#8's reviews do not say the judge did not run, with why (its call failed; no finding to judge): $(jq -c '.landed[] | select(.issue == 8) | .rounds | map(.judge)' <<<"$out")"
  # Each review step of the card's track says the same as its review.
  [ "$(jq -c '.landed[] | [.rounds | map(.judge)] == [.track.records | map(select(.name | startswith("review")) | .judge)]' <<<"$out" | sort -u)" = true ] \
    || fail "a review step of a card's track does not hold its review's judge: $(jq -c '.landed[] | .track.records | map(select(.name | startswith("review")))' <<<"$out")"
  # A landed card's fixes are its fix rounds: #7 and #8 each had a NO-GO, then a fix (a fix before any review is
  # t_judgesnapfixes').
  [ "$(jq -c '[.landed[] | select(.issue | IN(7, 8)) | [.issue, .fixes]] | sort' <<<"$out")" = '[[7,1],[8,1]]' ] \
    || fail "a landed card's fixes are not its fix rounds: $(jq -c '[.landed[] | [.issue, .fixes, (.rounds | map(.fixed))]]' <<<"$out")"
}

# Bug: a landed card's fixes are counted from its reviews followed by a fix, so a fix before any review (its build
# failed the Done-when check) is not counted. #9's records are written as a card writes them, with no card run: it
# was built, fixed, then reviewed GO, so it had one fix round though no review was followed by a fix.
t_judgesnapfixes() {
  local out now s; now=$(date -u +%FT%TZ)
  setup '[]'
  for s in picked build fix review:GO landed; do
    jq -cn --arg s "${s%%:*}" --arg r "$([ "$s" = review:GO ] && echo GO || echo ok)" --arg t "$now" \
      '{card: "c9", issue: 9, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: (if $s == "landed" then "abc" else "" end), reason: "", title: "T9", product: false}' >> "$ST/cards.jsonl"
  done
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.landed[] | [.issue, .fixes]]' <<<"$out")" = '[[9,1]]' ] \
    || fail "a fix before any review is not counted as a fix round of the landed card: $(jq -c '[.landed[] | [.issue, .fixes, (.rounds | map(.fixed))]]' <<<"$out")"
}

# P3 findings (the control record's rule P3). The issues are P1: an issue with no priority counts as P3, and the rule
# P3 off would leave it unpicked.
MINOR3='[P3] a.txt:1 the name says count but holds a sum. Proof: a.txt:1'
# Bugs: an accepted P3 with the rule P3 on is listed only (as with the rule off) and causes no fix round, or the fix
# is not told it, or is told a P3 the judge declined; the record does not count it as a P3. A NO-GO's fix round and
# landing after it are t_judgeaccept's whole card: here the review is judged alone (judgeone).
t_minoron() {
  judging "[$(issue 7 2026-01-01 P1)]"
  printf '%s\n' "$MINOR3" '[P3] a.txt:2 odd spacing. Proof: a.txt:2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: the name misleads the next reader. Cost to every card: none' 'F2 DECLINE: rare case' > "$STUB/judge.1"
  judgeone 7 "$STUB/review" fix
  [ "$(jf 7 .verdict)" = NO-GO ] && grep -qxF "E1 $MINOR3" "$T/$CASE/cards/c7.fix" && ! grep -q 'odd spacing' "$T/$CASE/cards/c7.fix" \
    || fail "an accepted P3 with the rule P3 on did not make a NO-GO whose fix is told it alone: $(jf 7 .verdict), $(cat "$T/$CASE/cards/c7.fix")"
  [ "$(jf 7 '.counts | tojson')" = '{"P0":0,"P1":0,"P2":0,"P3":1}' ] || fail "the review's counts do not count the accepted P3 alone: $(jf 7 '.counts | tojson')"
}

# Bugs: the judge is not told to judge a P3 as a P2, or is left to decline every P3 for causing no wrong result; a P3
# finding the judge declines still costs a fix round, or never reaches the declined list with its reason.
t_minordecline() {
  local l
  judging "[$(issue 7 2026-01-01 P1)]"
  printf '%s\n' "$MINOR3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 DECLINE: rare case' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  for l in 'Judge a P3 finding as a P2: accept it only when it is inside the diff, its proof uses what the project really runs,' \
    'case`. A P3 is minor by its level: do not decline it because it causes no wrong result, or as `style` when it is a'; do
    grep -qxF -- "$l" "$STUB/judge-asked" || fail "the judge's prompt does not hold the P3 bar: no line '$l'"
  done
  [ "$(jr 7 | tr '\n' '|')" = "DECLINED: $MINOR3 (judge: rare case)|USER-VISIBLE: no|VERDICT: GO|" ] || fail "a declined P3 did not leave the review a GO: $(jr 7)"
  [ "$(jq -r '"\(.by): \(.why): \(.finding)"' "$ST/declined.jsonl")" = "judge: rare case: $MINOR3" ] || fail "the declined P3 is not in the declined list with its reason: $(cat "$ST/declined.jsonl" 2>&1)"
}

# Bugs: with the rule P3 off, an accepted P3 alone makes a NO-GO and costs a fix round, is filed as a follow-up, or
# is lost from the card's record (its review line lists and counts it).
t_minoroff() {
  judging "[$(issue 7 2026-01-01 P1)]"
  loop control rules P3=off >/dev/null || fail "control rules P3=off was refused"
  printf '%s\n' "$MINOR3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 ACCEPT: the name misleads the next reader. Cost to every card: none' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  # A GO is no fix round, and a review that holds no finding files no follow-up.
  [ "$(jf 7 .verdict)" = GO ] || fail "an accepted P3 with the rule P3 off made a NO-GO: $(jr 7)"
  jr 7 | grep -qxF "MINOR: $MINOR3" && [ "$(jf 7 '.counts.P3')" = 1 ] && [ "$(jf 7 '.judge.accepted[0].finding')" = "$MINOR3" ] \
    || fail "the review does not list and count the accepted P3: $(jr 7) $(jf 7 .)"
}

# Bug: card() runs the judge, minor() and the verdict in the wrong order or skips one, so an accepted P3 on a P3-off
# card costs a fix round, a follow-up, or is missing from the landed card's review line. A whole card run, because
# t_minoroff calls those functions in its own order: only card() shows the order they run in on a card.
t_minoroffrun() {
  judging "[$(issue 7 2026-01-01 P1)]"
  loop control rules P3=off >/dev/null || fail "control rules P3=off was refused"
  printf '%s\n' "$MINOR3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  echo 'F1 ACCEPT: the name misleads the next reader. Cost to every card: none' > "$STUB/judge.1"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(rev 7 .result | tr '\n' ' ')" = "GO " ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ ! -e "$STUB/filed" ] \
    || fail "an accepted P3 with the rule P3 off made a NO-GO, a fix round or a follow-up: $(rev 7 .result | tr '\n' ' '), $(wc -l < "$STUB/sessions") sessions"
  rev 7 .reason | grep -qxF "MINOR: $MINOR3" && [ "$(rev 7 '.counts.P3')" = 1 ] && [ "$(rev 7 '.judge.accepted[0].finding')" = "$MINOR3" ] \
    || fail "the landed card's review line does not list and count the accepted P3: $(rev 7 '[.reason, .counts] | tojson')"
}

# Bug: a line the reviewer itself starts with `MINOR:` is taken as a P3 listed only, so a P1 written so counts for
# nothing and the review is a GO.
t_minorforged() {
  local f='[P1] a.txt:2 exposed token'
  judging "[$(issue 7 2026-01-01 P1)]" off
  loop control rules P3=off >/dev/null || fail "control rules P3=off was refused"
  printf '%s\n' "MINOR: $f" 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"
  judgeone 7 -
  [ "$(jf 7 .verdict)" = NO-GO ] && [ "$(jf 7 '.counts.P1')" = 1 ] && jr 7 | grep -qxF "$f" \
    || fail "a MINOR line the reviewer wrote did not count as the finding it is: $(jr 7) $(jf 7 .)"
}

# Bug: an accepted P3 still open after the last review round lands with no follow-up, or one filed above P3: with the
# test pack's three priorities (P0 to P2, as this project's pack) it was labelled P2. An issue with none of the pack's
# priorities is P3 (LEVEL), so the follow-up has none. The second review repeats it after its fix, and every finding
# is P3, so it is the last review (repeats()).
t_minorleft() {
  judging "[$(issue 7 2026-01-01 P1)]" off
  printf '%s\n' "$MINOR3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' | tee "$STUB/review.1" > "$STUB/review.2"
  loop run --only 7 >/dev/null || fail "run exited non-zero"
  [ "$(rev 7 .result | tr '\n' ' ')" = "NO-GO NO-GO " ] && [ "$(st 'select(.step == "landed") | .followups | tojson')" = '[100101]' ] \
    || fail "the P3 left after the last review did not land with its follow-up: $(st 'select(.step | IN("review", "landed", "blocked")) | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(jq -r '[.title, (.labels | map(.name) | join(" "))] | join(" | ")' "$STUB/filed")" = "$MINOR3 | conveyor-followup bug" ] \
    || fail "the follow-up is not the P3 finding with no priority label (P3): $(cat "$STUB/filed")"
}
