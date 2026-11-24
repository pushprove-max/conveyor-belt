#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a held issue of the nightly whole test (needsmain(), lib/needsask.sh) released once for each asking of
# its decision answered "Release it, first in the order", reopened or asked again, and the lines of $ST/mainred-released
# an older engine wrote; and a blocked card's question keeping the backslashes of its block reasons. Their own file, to keep needsask.test.sh under the 600 lines a case file may have. The helpers
# are needsask.test.sh's (mmain, nmain, mdec, manswer, naback).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug it catches (R279): the file of released decisions named the issue alone, so mainred-7, released, then held again
# by the owner and reopened, and answered "Release it, first in the order" again, was skipped: #7 stayed held. E23: the
# file then named the decision's asking time, whole seconds, and decision.sh gives a reopen in the first asking's
# second that same time, so the reopened asking's answer was skipped all the same.
t_needsreopen() {
  setup "[$(issue 7 2026-01-01)]"; mmain 7
  nmain; naback mainred-7; manswer 7 'Release it, first in the order'; nmain
  [ "$(jq -c '.held' "$ST/control.json")" = '[]' ] || fail "the first answer did not release #7: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
  # The reopen in the first asking's second (naback sets every asking of mainred-7 to 2026-01-01T00:00:00Z).
  loop control hold 7 > /dev/null && bash "$SRC/../.claude/scripts/decision.sh" reopen mainred-7 > /dev/null && naback mainred-7 \
    || fail "#7 was not held again, or mainred-7 not reopened"
  manswer 7 'Release it, first in the order'; nmain
  [ "$(jq -c '.held' "$ST/control.json")" = '[]' ] \
    || fail "mainred-7, reopened in its first asking's second after its release and answered \"Release it, first in the order\" again, did not release #7: $(cat "$ST/control.json") $(mdec 7) $(cat "$ST/mainred-released") $(cat "$T/$CASE/run.out")"
}

# naold [<line>...]: the lines an engine before the asking number was kept wrote when it released each issue ("7" when
# none is given), as it left them: the answers of mainred-7 so far given (each time decision.sh wrote, its answer's and
# its corrections') and the file written in the past (2026-01-01, a second apart), so a case can put an answer or a
# correction in the second of the file's last write, where its time cannot tell whether the old engine read it.
naold() {
  printf '%s\n' "${@:-7}" > "$ST/mainred-released" && TZ=UTC0 touch -t 202601010000.02 "$ST/mainred-released" \
    && jq -c 'if .id == "mainred-7" and .answer != null then .answeredAt = "2026-01-01T00:00:01Z" | (.history[]?.at) = "2026-01-01T00:00:01Z" else . end' "$CONVEYOR_LEDGER" > "$T/$CASE/led.new" \
    && mv "$T/$CASE/led.new" "$CONVEYOR_LEDGER" || fail "the old engine's lines, or the times of the answers, were not written"
}

# naputback <history>: the checks of an old line "7" that fits two histories of mainred-7's two release answers, which
# need different acts (needsmain()). With auto on, two runs of the loop's job (needsjob(): needsmain, then the auto pass)
# leave #7 held and mainred-7 asked again once, open, with no recommended option and the owner's latest answer named,
# and the auto pass leaves it to the owner (its log's waiting list). Asked once is one asking row (E25: askings in one
# second share their askedAt, so a count of askedAt let two pass). The owner's answer then releases #7, once: held
# again, a run of the job leaves it held.
naputback() {
  naauto on; najob; najob
  [ "$(jq -c '.held' "$ST/control.json")" = '[7]' ] \
    && mdec 7 | jq -e '.answer == null and .proposedDefault == "none" and (.question | contains("\"Release it, first in the order\""))' > /dev/null \
    && [ "$(jq -s '[.[] | select(.id == "mainred-7" and (.source | contains("re-ask: an older engine")) and .answeredAt == null)] | length' "$CONVEYOR_LEDGER")" = 1 ] \
    && awk '/^## Waiting for the owner$/ { on = 1 } on' "$AUTOLOG" | grep -q '^- mainred-7: ' \
    || fail "with mainred-released holding an old engine's \"7\", $1, two runs of the loop's job with auto on did not leave #7 held and mainred-7 asked again once, with no recommended option, for the owner: $(cat "$ST/control.json") $(mdec 7) $(cat "$ST/mainred-released") $(cat "$AUTOLOG") $(cat "$T/$CASE/run.out")"
  manswer 7 'Release it, first in the order'; najob
  [ "$(jq -c '.held' "$ST/control.json")" = '[]' ] || fail "$1: the owner's answer to mainred-7, asked again, did not release #7: $(cat "$ST/control.json") $(cat "$ST/mainred-released") $(cat "$T/$CASE/run.out")"
  loop control hold 7 > /dev/null && najob
  [ "$(jq -c '.held' "$ST/control.json")" = '[7]' ] || fail "$1: #7, held again after the owner's answer released it, was released again: $(cat "$ST/control.json") $(cat "$ST/mainred-released") $(cat "$T/$CASE/run.out")"
}

# Bug it catches (R279 fix, upgrade, E8, E19, the owner's order of 2026-11-23): the history where the old engine took
# the last asking. mainred-7's first release answer was corrected to leave it held (in one second), then the decision
# was reopened in its first asking's second and answered to leave it held, that answer corrected to release in the
# second of the file's last write, and the old engine released #7 for it (line "7"); then #7 was held again. Taken as
# the first asking's line, the line let that answer release #7 again; read by the file's time, the correction counted
# as after it, with the same result; and reopened with its default, the decision was answered by the auto pass, with
# the same result too. E24: the case had no correction in the second of the old engine's release. E23: the two askings
# share their asking time, and counted by it they were one, so the line was taken as that one's.
t_needsoldheld() {
  local d=$SRC/../.claude/scripts/decision.sh
  setup "[$(issue 7 2026-01-01)]"; mmain 7
  nmain; naback mainred-7; manswer 7 'Release it, first in the order'
  bash "$d" answer mainred-7 'Leave it held' --correct > /dev/null && bash "$d" reopen mainred-7 > /dev/null && naback mainred-7 \
    || fail "mainred-7's answer was not corrected, or it was not reopened"
  manswer 7 'Leave it held'
  bash "$d" answer mainred-7 'Release it, first in the order' --correct > /dev/null || fail "mainred-7's second answer was not corrected"
  nmain
  [ "$(jq -c '.held' "$ST/control.json")" = '[]' ] || fail "the reopened mainred-7's release answer did not release #7: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
  naold
  # The correction (the last row's last history time) in the second of the file's last write, 2026-01-01T00:00:02Z (naold).
  jq -cs '.[-1].history[-1].at = "2026-01-01T00:00:02Z" | .[]' "$CONVEYOR_LEDGER" > "$T/$CASE/led.new" \
    && mv "$T/$CASE/led.new" "$CONVEYOR_LEDGER" && loop control hold 7 > /dev/null || fail "#7 was not held again"
  naputback "the old engine's release of the reopened asking's correction, in that second, #7 then held again"
}

# Bug it catches (R279 fix, upgrade): an engine before the asking was kept wrote the issue alone ("7") to
# mainred-released. The new check looked for "mainred-7 <asking>" alone, so #7, released by the old engine and held
# again by the owner, was released again by the old answer. Reopened and answered again, it is released.
t_needsoldreleased() {
  setup "[$(issue 7 2026-01-01)]"; mmain 7
  nmain; naback mainred-7; manswer 7 'Release it, first in the order'; nmain
  naold
  loop control hold 7 > /dev/null || fail "#7 was not held again"
  nmain
  [ "$(jq -c '.held' "$ST/control.json")" = '[7]' ] \
    || fail "with mainred-released holding \"7\" (an old engine's line), the old answer released #7 against a new hold: $(cat "$ST/control.json") $(cat "$ST/mainred-released") $(cat "$T/$CASE/run.out")"
  bash "$SRC/../.claude/scripts/decision.sh" reopen mainred-7 > /dev/null || fail "mainred-7 was not reopened"
  manswer 7 'Release it, first in the order'; nmain
  [ "$(jq -c '.held' "$ST/control.json")" = '[]' ] \
    || fail "mainred-7, reopened after an old engine's release line \"7\" and answered to release again, did not release #7: $(cat "$ST/control.json") $(cat "$ST/mainred-released") $(cat "$T/$CASE/run.out")"
}

# Bug it catches (R279 fix, upgrade, E15, the owner's order of 2026-11-23): the history where the old engine took the
# first asking. mainred-7 was released by the old engine (line "7"), #7 held again, the decision reopened (in its first
# asking's second) and answered to leave it held, then corrected to release in the second the old engine wrote its
# release of #9 (line "9"). Read by the file's time, the correction counted as before that write: the owner's new answer
# was taken as acted on, and #7 stayed held with nothing put to the owner. E23: counted by their asking time, the two
# askings were one, with the same result.
t_needsoldcorrect() {
  local d=$SRC/../.claude/scripts/decision.sh
  setup "[$(issue 7 2026-01-01)]"; mmain 7
  nmain; naback mainred-7; manswer 7 'Release it, first in the order'; nmain
  loop control hold 7 > /dev/null && bash "$d" reopen mainred-7 > /dev/null && naback mainred-7 || fail "#7 was not held again, or mainred-7 not reopened"
  manswer 7 'Leave it held'; naold 7 9
  # The correction (the last row's last history time) in the second of the file's last write, 2026-01-01T00:00:02Z (naold).
  bash "$d" answer mainred-7 'Release it, first in the order' --correct > /dev/null \
    && jq -cs '.[-1].history[-1].at = "2026-01-01T00:00:02Z" | .[]' "$CONVEYOR_LEDGER" > "$T/$CASE/led.new" && mv "$T/$CASE/led.new" "$CONVEYOR_LEDGER" \
    || fail "mainred-7's answer was not corrected in the second of the old engine's last write"
  naputback "a correction to release in the second of the old engine's release of #9"
}

# Bug it catches (follow-up of #1627): the owner answered mainred-7 "Release it, first in the order" on the Board, and
# the release was the engine's, so `released` had no date for #7 and foreman status gave no sign of the owner's act. The
# Board's answer says the owner gave it (--by owner): #7 is released, first in the order, and dated as the owner's.
t_needsownerrelease() {
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; mmain 7
  nmain; manswer 7 'Release it, first in the order' --by owner; nmain
  jq -e '.held == [] and .order == [7,8] and (.released | keys == ["7"] and (.["7"] | test("^[0-9-]{10}T[0-9:]{8}Z$")))' "$ST/control.json" > /dev/null \
    || fail "mainred-7, answered \"Release it, first in the order\" by the owner ($(mdec 7), marked $(cat "${CONVEYOR_LEDGER%.jsonl}.answeredby.jsonl" 2>&1)), did not release #7 first in the order dated as the owner's: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Bugs it catches (follow-up of #1627, E3 and E4): the owner answered mainred-8 on the Board (--by owner), the mark file
# holds a long history of the owner's Board answers (over 128 KiB, the length one argument may have on Linux), and
# `auto decide` answered mainred-7 "Release it, first in the order". With the marks given to jq as one argument, no
# decision was read and #7 stayed held; with any owner mark taken as a mark of this answer, auto's release of #7 was
# dated as the owner's. #7 is released, first in the order, with no date; #8 stays held.
t_needsmarkedother() {
  local mk
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-02-01))"; mmain 7 8
  nmain; manswer 8 'Leave it held' --by owner; mk=${CONVEYOR_LEDGER%.jsonl}.answeredby.jsonl
  jq -c 'range(800) as $i | .row.answeredAt = "2025-01-01T00:00:00Z" | .row.question += " (\($i))"' "$mk" > "$T/$CASE/pad" \
    && cat "$T/$CASE/pad" >> "$mk" && [ "$(jq -cs '[.[].row]' "$mk" | wc -c)" -gt 131072 ] \
    || fail "the owner's marks in $mk were not over 128 KiB: $(wc -c < "$mk")"
  manswer 7 'Release it, first in the order'; nmain
  jq -e '.held == [8] and .order == [7,8] and .released == {}' "$ST/control.json" > /dev/null \
    || fail "mainred-7, answered \"Release it, first in the order\" by auto ($(mdec 7)), with $(wc -l < "$mk") owner marks of other answers, did not release #7 first in the order undated, with #8 held: $(cat "$ST/control.json") $(cat "$T/$CASE/run.out")"
}

# Bug it catches (R282): when #7 closed, the pass answered mainred-7 as gone; reopened on GitHub and still held, #7 got no
# new decision, as the id was in the ledger, so it stayed held with nothing put to the owner.
t_needsmainreopen() {
  setup "[$(issue 7 2026-01-01)]"; mmain 7
  nmain; echo CLOSED > "$STUB/state.7"; nmain
  jq -e '.answer | startswith("Closed")' <<<"$(mdec 7)" > /dev/null || fail "with #7 closed, mainred-7 was not answered as gone: $(mdec 7)"
  echo OPEN > "$STUB/state.7"; nmain
  jq -e '.answeredAt == null and .answer == null and .proposedDefault == "Release it, first in the order"' <<<"$(mdec 7)" > /dev/null \
    || fail "#7, reopened on GitHub and held, has no open decision: $(mdec 7) $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#1589 review): needsask() read its rows from @tsv, which writes each backslash as two, and `read -r`
# keeps both, so a block reason quoting `\n` reached Needs you as `\\n`, in this block and in the one review-retry gave
# back. #7's first review block, given back by review-retry, and its next card's block both quote a backslash: the
# question has each once.
t_needsaskslash() {
  local d; setup "[$(issue 7 2026-01-01)]"; nainit 7
  jq -c 'select(.card == "c0-7") | if .step == "blocked" then .reason = "the fix for [P1] a.txt:1 drops the \\n escape did not hold after 3 rounds"
    | .retriedAt = "2026-11-02T00:00:00Z" | .retriedBy = "review-retry" else . end' "$ST/cards.jsonl" > "$ST/retried.jsonl" && : > "$ST/cards.jsonl" \
    || fail "c0-7 was not given back as review-retry does"
  narecard c1-7 7 '[P1] a.txt:2 splits on \t'; nask
  d=$(nadec c1-7)
  jq -e '.question | contains("splits on \\t did not hold") and contains("drops the \\n escape did not hold") and (contains("\\\\") | not)' <<<"$d" > /dev/null \
    || fail "the block reasons of c1-7 (finding '[P1] a.txt:2 splits on \\t') and of c0-7 (finding 'drops the \\n escape') are not asked with each backslash once: $d $(cat "$T/$CASE/run.out")"
}
