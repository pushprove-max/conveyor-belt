#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the monthly test-speed survey's issue (lib/survey.sh), filed on the 1st in the pack's quiet hour.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# <command> [<argument>...] in one shell of the engine for main $R, made as conveyor.sh makes one for its commands
# (conveyor.sh sourced, with its state-dir command, then names()). An engine started for each look or pick took about
# 0.16 s to the look's 0.01 s, and the file's 19 took it to 5.4 s, over its 4 s budget (#417): a case here starts one
# for each main it looks from, and notes in a file what it checks between two looks. The command may call
# this file's functions and lib.sh's (tune), but not lib.sh's setup (the engine's setup replaces it).
# The runner sources every case file into one shell, so each name here at file level is this file's own (sv_): an
# `engine` here replaced followmain.test.sh's.
sv_engine() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/survey.sh")" && names && "$@" ); }
sv_now() { jq -en --arg t "$1" '$t | fromdate'; } # <UTC time>: the engine's clock then (CONVEYOR_NOW)

# Every speed figure was taken on a busy machine and the slowest lists go stale as tests are added: each project gets
# one survey card a month, filed in the machine's quiet hour, and never a second that month.
# Local time is UTC here, so the hours below are the pack's.
survey_start() {
  export TZ=UTC; setup "[]"; tune 'del(.test.survey)' # the pack's default: on (the test pack turns it off)
  filed() { jq -cs "map($1)" "$STUB/filed" 2>/dev/null || echo '[]'; }   # <jq filter> of each issue filed
  kept() { jq -c '[.month, .issue, .at]' "${1:-$ST}/survey.json" 2>&1; } # [state folder]: the survey it keeps, and when it filed it
}
# The survey's look (survey(), as `conveyor.sh survey` makes it) at each <UTC time>, one after another, in one engine
# shell; fails at the first look that fails.
sv() { sv_engine sv_looks "$@"; }
sv_looks() { local t n; for t; do n=$(sv_now "$t") && CONVEYOR_NOW=$n survey || return 1; done; }
t_survey() {
  survey_start
  # Another day of the month, or the 1st outside the quiet hour (default 03:00 to 03:59): none. Then the 1st, in the
  # hour: one issue, of the pack's second priority, whose card reports each file's clock and CPU seconds. One filed outside the hour on the 1st would be kept with its
  # time (kept, noted in $T/$CASE/dec before the later looks), and the one in the hour would not be filed.
  # Then not again that month: later in the hour, or on a later day. The next month's 1st: its own.
  months() {
    sv_looks 2026-11-30T03:10:00Z 2026-12-01T02:59:59Z 2026-12-01T04:00:00Z 2026-12-01T03:10:00Z && kept > "$T/$CASE/dec" \
      && sv_looks 2026-12-01T03:59:00Z 2026-12-15T03:10:00Z 2027-01-01T03:00:00Z
  }
  sv_engine months || fail "a look failed"
  [ "$(cat "$T/$CASE/dec")" = '["2026-12",100101,"2026-12-01T03:10:00Z"]' ] \
    || fail "the 1st's quiet hour, and not a look outside it, did not file the month's survey issue: $(cat "$T/$CASE/dec")"
  [ "$(filed '[.title, (.labels | map(.name))]')" = '[["Test-speed survey, December 2026",["bug","P1"]],["Test-speed survey, January 2027",["bug","P1"]]]' ] \
    && [ "$(kept)" = '["2027-01",100102,"2027-01-01T03:00:00Z"]' ] \
    || fail "a second survey issue was filed in one month, or the next month filed none, or not of the pack's second priority: $(filed '[.title, .labels]') $(kept)"
  jq -se '.[0].body | contains("each of the project'"'"'s test files alone") and contains("test slots") and contains("clock seconds")
      and contains("CPU seconds") and (contains("budget") | not)
      and contains("slowest lists") and contains("03:00 local time") and contains("write them to .conveyor/test-times.json")' "$STUB/filed" > /dev/null \
    || fail "the survey issue does not ask for each file's clock and CPU seconds, written to .conveyor/test-times.json, or it still names a CPU budget no file has: $(jq -sr '.[0].body' "$STUB/filed")"
}
# Filing in the quiet hour does not make the card run in it: a survey issue filed at 03:59 and picked at 04:00 would be
# measured on a busy machine. So pick takes it only in the pack's test.surveyHour, of any day; other issues any time.
t_surveypick() {
  local d=$T/$CASE/frozen want got
  export TZ=UTC; setup "$(jq -cs '.[0].title = "Test-speed survey, December 2026" | .' <(issue 7 2026-01-01 P1) <(issue 6 2026-02-01 P1))"
  tune 'del(.test.survey)'; mkdir -p "$d"; cp "$ST/control.json" "$d/"
  # <UTC time>...: `<time> <issue>`, a line each, of what `conveyor.sh pick --dry` takes then ('-' for none).
  picks() { local t n p; for t; do n=$(sv_now "$t") && p=$(CONVEYOR_NOW=$n drypick "$STUB/issues.json" "$d") || return 1; echo "$t ${p:--}"; done; }
  # Past its hour, #6; in it, #7, the oldest P1: on the 1st, and on a later day. Then with test.surveyHour 22: #6 at
  # 03:10, #7 at 22:00 (the engine reads the pack again at each look).
  both() { picks 2026-12-01T04:00:00Z 2026-12-01T03:10:00Z 2026-12-02T03:59:59Z && tune '.test.surveyHour = 22' && echo hour 22 \
    && picks 2026-12-01T03:10:00Z 2026-12-01T22:00:00Z; }
  want='2026-12-01T04:00:00Z 6
2026-12-01T03:10:00Z 7
2026-12-02T03:59:59Z 7
hour 22
2026-12-01T03:10:00Z 6
2026-12-01T22:00:00Z 7'
  got=$(sv_engine both)
  [ "$got" = "$want" ] || fail "the survey issue was picked outside the pack's test.surveyHour, or not in it: $got"
}
# One for each project: each keeps its own in its state folder, so a second project on the machine files its own.
t_surveyprojects() {
  survey_start; local two=$T/$CASE/two
  cp -a "$R" "$two" || fail "the second project could not be made"
  # The second's look is the command itself (`conveyor.sh survey`), which no other case runs.
  sv 2026-12-01T03:10:00Z 2026-12-01T03:20:00Z && CONVEYOR_NOW=$(sv_now 2026-12-01T03:30:00Z) R=$two loop survey || fail "a look failed"
  [ "$(filed .title)" = '["Test-speed survey, December 2026","Test-speed survey, December 2026"]' ] \
    || fail "two projects did not file one survey issue each: $(filed .title)"
  [ "$(kept),$(kept "$two/conveyor/state")" = '["2026-12",100101,"2026-12-01T03:10:00Z"],["2026-12",100102,"2026-12-01T03:30:00Z"]' ] \
    || fail "each project does not keep its own survey: $(kept) $(kept "$two/conveyor/state")"
}
# The pack's settings: test.survey false files none (the way to turn it off); test.surveyHour moves the hour; a
# test.fileBudget left in the pack is ignored: no file has a CPU budget, so the issue names none (#349). First, with the pack's default (on), the running loop files it.
# Bug: `serve` does not look for the survey by itself (run.sh's once-a-minute call dropped), so no survey is ever
# filed: the other looks call `loop survey` straight. Here only the running loop can file it. (Here, not in a case of
# its own: a fifth case waited for a test slot and made the file slower.)
t_surveyoff() {
  survey_start
  tune '.tunables.idle = 1 | .tunables.poll = 1'
  CONVEYOR_NOW=$(jq -n '"2026-12-01T03:10:00Z" | fromdate') loop serve > "$STUB/serve.out" 2>&1 & pid=$!
  trap 'kill $pid 2>/dev/null' EXIT
  # survey.json, the look's last write: survey() is a subshell that outlives the loop's kill, so waiting only for the
  # filed issue let it write survey.json (03:10) after the rm below, and the 03:10 look later in this case filed none.
  wait_until '[ -s "$ST/survey.json" ]' 'cat "$STUB/serve.out"' || fail "serve did not file the survey issue in the 1st's quiet hour"
  [ "$(filed .title)" = '["Test-speed survey, December 2026"]' ] || fail "serve did not file one survey issue: $(filed .title)"
  kill $pid; wait $pid 2>/dev/null; trap - EXIT; rm -f "$STUB/filed" "$ST/survey.json"
  # Off, then on with hour 22, in one engine shell (it reads the pack again at each look). An issue filed at either
  # 03:10 would be the one kept, with that time, and none would be filed at 22:30.
  offthen22() {
    tune '.test.survey = false' && sv_looks 2026-12-01T03:10:00Z \
      && tune 'del(.test.survey) | .test.surveyHour = 22 | .test.fileBudget = 7' && sv_looks 2026-12-01T03:10:00Z 2026-12-01T22:30:00Z
  }
  sv_engine offthen22 || fail "a look failed with the survey off, or with test.surveyHour 22"
  [ "$(filed .title)" = '["Test-speed survey, December 2026"]' ] && [ "$(kept)" = '["2026-12",100101,"2026-12-01T22:30:00Z"]' ] \
    && jq -e '.body | (contains("budget") | not) and contains("22:00 local time")' "$STUB/filed" > /dev/null \
    || fail "test.survey false filed a survey issue, or test.surveyHour 22 filed at 03:10 or not at 22:30, or the issue names the pack's ignored test.fileBudget: $(kept) $(filed '[.title, .body]')"
}
