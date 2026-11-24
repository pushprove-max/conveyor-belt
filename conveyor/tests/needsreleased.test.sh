#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a held issue of the nightly whole test (needsmain(), lib/needsask.sh) released once for each asking of
# its decision answered "Release it, first in the order", reopened or asked again, and the lines of $ST/mainred-released
# an older engine wrote. Their own file, to keep needsask.test.sh under the 600 lines a case file may have. The helpers
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
