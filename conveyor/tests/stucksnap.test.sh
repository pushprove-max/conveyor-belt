#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the Foreman's Conveyor watcher (foreman/watch-conveyor.sh) on a kept snapshot that names a card stuck
# while the card has moved on since (#1784): the real card records, the real kept snapshot (commands/snapshot.sh) and
# the real `conveyor.sh health`, as the watcher asks them.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A line of card c<n>-<n>'s records, its step <step> (start:<of> for a start line) at <epoch seconds>.
stucksnap_line() { # <n> <step> <epoch seconds>
  jq -cn --argjson n "$1" --arg s "$2" --argjson t "$3" '($s | split(":")) as [$s, $of]
    | {card: "c\($n)-\($n)", issue: $n, step: $s, time: ($t | todate), tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}
      + if $s == "picked" then {title: "t", created: "2026-01-01T00:00:00Z"} elif $of then {of: $of} else {} end' >> "$ST/cards.jsonl"
}
# The fixture of every case: cards c7-7 and c8-8 each began their build an hour ago and wrote nothing since, past the
# pack's tunables.stuck (1200 s), and the snapshot built and kept from those records names both stuck. The kept lock is
# then held to the case's end: a snapshot read starts a rebuild when an input changed, and a rebuild finished between
# two polls would hide the stale snapshot that each case is about. The watcher reads this checkout as the record alpha.
stucksnap_setup() {
  local t lk
  export XDG_CONFIG_HOME=$T/$CASE/config
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-01)]"; mkdir -p "$ST" "$T/$CASE/cards" "$XDG_CONFIG_HOME/conveyor"
  jq -n --arg m "$R" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  t=$(($(date +%s) - 3600))
  for n in 7 8; do stucksnap_line "$n" picked "$t"; stucksnap_line "$n" start:build "$t"; done
  loop snapshot --fresh > /dev/null && jq -e '.health.stuck | map(.card) | sort == ["c7-7", "c8-8"]' "$ST/snapshot.json" > /dev/null \
    || fail "the fixture's snapshot does not name c7-7 and c8-8 stuck: $(jq -c .health.stuck "$ST/snapshot.json" 2>&1)"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
}
# Two polls of the watcher, a minute apart on its clock (a stuck card wakes only when two polls in a row list it),
# each asking the real engine, but `conveyor.sh health` fails when <health> is fail; wake gets the wake put.
stucksnap_polls() { # [fail]
  local ask="cd \"\$CONVEYOR_MAIN\" && CONVEYOR_CARDS=$T/$CASE/cards bash $SRC/conveyor.sh \$CONVEYOR_CMD" now i; now=$(date +%s)
  [ "${1:-}" != fail ] || ask="[ \"\$CONVEYOR_CMD\" != health ] || exit 1; $ask"
  for i in 0 1; do
    CONVEYOR_FOREMAN_DIR=$T/$CASE/foreman CONVEYOR_MAIN=$R CONVEYOR_FOREMAN_NOW=$((now + 60 * i)) CONVEYOR_FOREMAN_ASK=$ask \
      bash "$SRC/foreman/watch-conveyor.sh" --once > /dev/null 2>> "$T/$CASE/watch.err"
  done
  wake=$(cat "$T/$CASE"/foreman/pending/*.wake 2>/dev/null)
}
# The wakes name c8-8 stuck and never c7-7, which <why> moved on.
stucksnap_only8() { # <why>
  grep -qF '#8 is stuck' <<<"$wake" && ! grep -qF '#7 is' <<<"$wake" \
    || fail "with c7-7 $1 since the kept snapshot, the wakes are not #8 stuck alone: ${wake:-no wake} $(cat "$T/$CASE/watch.err")"
}

# Bug (#1784): c7-7 ended its build and began its test step after the snapshot was made; the watcher woke the
# Foreman with "#7 is stuck: no new step since <its build's start>" from the old snapshot. c8-8, stuck in the records
# too, still wakes: the quiet on #7 comes from the records, not from a watcher that names no stuck card.
t_stucksnapnewer() {
  stucksnap_setup; stucksnap_line 7 build "$(date +%s)"; stucksnap_line 7 start:test "$(date +%s)"
  stucksnap_polls; stucksnap_only8 "recording a newer step"
}
# The same, and `conveyor.sh health` does not read (it ran past the watcher's time limit): the stuck cards of a
# snapshot older than the records are those with no line in them since (the snapshot's recordsNow.lines). Bug: the
# snapshot's stuck list was kept as it was, so #7 woke as stuck.
t_stucksnapnohealth() {
  stucksnap_setup; stucksnap_line 7 build "$(date +%s)"; stucksnap_line 7 start:test "$(date +%s)"
  stucksnap_polls fail; stucksnap_only8 "recording a newer step, health not read,"
}
# c7-7's build prints after the snapshot was made: its live record (.live, as watch() in lib/session.sh writes it)
# has new output and the card records do not change, so the snapshot's recordsNewer stays false. Bug: only a snapshot
# older than the records was checked again, so #7 woke as stuck while its build printed.
t_stucksnaplive() {
  stucksnap_setup
  jq -cn --argjson t "$(date +%s)" '{step: "build", at: ($t - 3600 | todate), last: ($t | todate), turns: 1}' > "$T/$CASE/cards/c7-7.live"
  stucksnap_polls; stucksnap_only8 "printing live output"
}
