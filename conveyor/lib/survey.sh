# SPDX-License-Identifier: Apache-2.0
# The monthly test-speed survey (README.md, The test-speed survey): every speed figure was taken on a busy machine,
# and single runs swing 2-3x, so the project's slowest lists and its survey report go stale. On the first day of each
# month, in the hour the pack names as the machine's quietest (test.surveyHour, local time, default 3: 03:00 to 03:59),
# `serve` files one issue for the project, "Test-speed survey, <month> <year>", of the pack's second priority. Its card
# runs each test file alone, records clock and CPU seconds (in the report, and in .conveyor/test-times.json for the
# slow-test check's before: beforetimes(), lib/testrun.sh), rewrites the slowest lists and the survey report, and names
# the files newly over the CPU budget (test.fileBudget). A pack with test.survey false files none. Filing in the hour
# does not make the card run in it: pick does (upnext(), lib/pick.sh), taking the issue only in test.surveyHour, of
# that day or a later one, and the card runs its measurements first, so they start in that hour.
# $SURVEY keeps {month: "<year>-<month>" of the last issue filed, issue, at}: one issue a month, whatever the loop's
# turns or restarts in that hour. A filing GitHub did not take keeps nothing, and is tried again at the next look
# within the hour. A loop not running in that hour of the 1st files none that month. One look at a time (a lock).
SURVEY=${STATE%/*}/survey.json
survey() ( # a subshell: the lock it takes ends with it, never held by the loop that calls it
  local on hour budget lock now month title n
  packget test.survey on test.surveyHour hour test.fileBudget budget || return 1
  [ "$on" != false ] || return 0
  # Now, in local time (CONVEYOR_NOW when set): "<year>-<month> <day> <hour> <Month year>".
  read -r month now n title < <(jq -rn '(($ENV.CONVEYOR_NOW // "" | tonumber?) // now) | localtime | strftime("%Y-%m %d %H %B %Y")') || return 1
  [ "$now" = 01 ] && [ "$((10#$n))" = "$hour" ] || return 0
  { exec {lock}>>"$SURVEY.lock"; } 2>/dev/null && flock -n "$lock" || return 0
  [ "$(jq -r '.month // ""' "$SURVEY" 2>/dev/null)" != "$month" ] || return 0
  title="Test-speed survey, $title"
  n=$(surveyfile "$title" "$(surveybody "$hour" "$budget")") || return 1
  jq -cn --arg m "$month" --argjson n "$n" --arg at "$(clock)" '{month: $m, issue: $n, at: $at}' > "$SURVEY.new" && mv -f "$SURVEY.new" "$SURVEY" \
    || { rm -f "$SURVEY.new"; echo "conveyor: the test-speed survey's issue #$n was filed, but $SURVEY could not be written" >&2; return 1; }
  echo "conveyor: filed #$n, $title"
)
# Files one survey issue, <title>, of the pack's type and second priority (names() sets both), and prints its number.
surveyfile() { # <title> <body>
  local prio out n
  prio=$(jq -r '.[[1, length - 1] | min]' <<<"$PRIOS")
  out=$(gh_write issue create --title "$1" --label "$TYPE" --label "$prio" --body "$2" 2>&1) \
    && n=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1) && n=${n##*/} && [ -n "$n" ] \
    || { echo "conveyor: the test-speed survey's issue could not be filed: ${out:0:300}" >&2; return 1; }
  echo "$n"
}
# The first test-speed survey, filed by setup when the owner answers yes (setup(), lib/setup.sh): one issue, titled as
# the monthly one is so that pick takes it only in test.surveyHour too, whose card also names, for the Foreman to file
# as cards, each group of files over the budget and each shared helper the measurements point to. It touches no
# survey.json: the monthly survey still runs unless test.survey is false.
firstsurvey() {
  local hour budget n
  packget test.surveyHour hour test.fileBudget budget || return 1
  n=$(surveyfile "Test-speed survey, first" "$(surveybody "$hour" "$budget" first)") || return 1
  echo "conveyor: filed #$n, Test-speed survey, first"
}
# The survey issue's body: what its card does and what its report holds; with `first`, the first survey's.
surveybody() { # <survey hour> <budget, seconds> [first]
  local when="Conveyor files this issue on the first day of each month, in the machine's quietest hour" step4 end
  step4="4. Name in the report every file newly over the budget: over it now and not in the last survey report's list of files over it. The Foreman files a speed card for each."
  end="those newly over it named apart."
  if [ "${3:-}" = first ]; then
    when="Conveyor's setup filed this issue, the project's first test-speed survey, as the owner asked. It runs in the machine's quietest hour"
    step4="4. Name in the report, for the Foreman to file as cards: each group of files over the budget (files slow for one cause), and each shared helper the measurements point to (a slow library call many files repeat, a costly fixture, a runner setting), with the files it would speed up."
    end="each group of files over it and each shared helper the measurements point to named for the Foreman."
  fi
  printf '%s\n' "$when (the pack's test.surveyHour, $(printf '%02d' "$1"):00 local time). Conveyor picks its card only in that hour, so that the tests are measured while the machine is quiet. It changes no test and no budget.

1. First, before any other work, run each of the project's test files alone, one after another, each holding one of the machine's test slots, as the project's test runner takes them. Record for each file its clock seconds (from its start to its end) and its CPU seconds (user plus system, of the run and every process it started), and write them to .conveyor/test-times.json as {\"files\": {\"<file>\": {\"sec\": <clock seconds>, \"cpu\": <CPU seconds>}}}, every file this survey measured and no other: Conveyor takes a file's time before a card's change from it.
2. Rewrite the project's slowest lists (the files its runners start first) from these times.
3. Rewrite the project's survey report: a table of every test file, slowest first, with its clock seconds and CPU seconds, and the files over the CPU budget of $2 CPU s (the pack's test.fileBudget: a file's CPU seconds, not its clock seconds, are held to it).
$step4

Done when:
- The survey report lists each test file's clock and CPU seconds, measured alone by this card, and the files over the $2 CPU s budget, $end
- The slowest lists and .conveyor/test-times.json are rewritten from the same times."
}
