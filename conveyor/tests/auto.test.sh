#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: /conveyor-belt:auto (conveyor.sh auto), where the Foreman decides the owner's open decisions for them.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The project's ledger (the Board's open decisions) with three open decisions: one with a recommended option, one
# the pack's default auto.reserved holds back (a new feature flag), and a picker ask with no recommended option (its
# default "none", as ask-records-decision.sh writes it); and the owner's ruling log, two picker answers, the label
# kept as picked with its "(Recommended)", as ruling-log.sh writes it.
autoledger() {
  setup '[]'; export CONVEYOR_RULING_LOG=$T/$CASE/rulings.jsonl; LEDGER=$R/.claude/metrics/decisions.jsonl
  jq -cn '{id: "d-docs", askedAt: "2026-11-15T10:00:00Z", question: "Merge the docs fix now?", proposedDefault: "yes, merge it",
    source: "t", answer: null, answeredAt: null, options: ["yes, merge it", "wait"]},
    {id: "d-flag", askedAt: "2026-11-15T10:01:00Z", question: "Add a new feature flag for exports?", proposedDefault: "yes",
    source: "t", answer: null, answeredAt: null},
    {id: "d-pick", askedAt: "2026-11-15T10:02:00Z", question: "Which colour for the chart?", proposedDefault: "none",
    source: "t", answer: null, answeredAt: null, options: ["blue", "green"]}' > "$LEDGER"
  jq -cn '{id: "x-1", source: "ask", question: "Merge the docs fix now?", answer: "yes, merge it (Recommended)", pick: "recommended"},
    {id: "x-2", source: "ask", question: "Keep the old export?", answer: "no", pick: "option"}' > "$CONVEYOR_RULING_LOG"
}
answer() { jq -rs --arg id "$1" '[.[] | select(.id == $id)] | last | .answer // "open"' "$LEDGER"; } # <id>: its answer now

# Bugs: turned on, the decide step leaves a decision with a recommended option open, answers it with no log entry (or
# one without the question, the pick, why, or whether it can be reversed), or answers one the pack reserves for the
# owner, or does not list that one under "Waiting for the owner"; a second pass lists it twice.
t_auto() {
  local out log; autoledger
  out=$(cd "$R" && loop auto decide 2>&1); [ $? = 2 ] && [ "$(answer d-docs)" = open ] || fail "decide ran while auto was off: $out"
  out=$(cd "$R" && loop auto on) || fail "auto on failed: $out"
  log=$(jq -r .log "$ST/auto/mode.json"); [[ $log == "$ST"/auto/*.md ]] && [ -f "$log" ] || fail "auto on started no log in the state folder: $out"
  out=$(cd "$R" && loop auto decide) || fail "decide failed: $out"
  [ "$(answer d-docs)" = 'yes, merge it' ] || fail "the decision with a recommended option was not answered with it: $(answer d-docs)"
  [ "$(answer d-flag)" = open ] || fail "the reserved decision was answered: $(answer d-flag)"
  # The entry, under Decisions (before Waiting for the owner), with its question, pick, why and reversible lines.
  awk '/^## Decisions$/ { on = 1 } /^## Waiting for the owner$/ { on = 0 } on' "$log" > "$T/$CASE/decided"
  grep -q '^### [0-9][0-9]:[0-9][0-9] d-docs: Merge the docs fix now?$' "$T/$CASE/decided" \
    && grep -qxF -- '- **Question:** Merge the docs fix now? (options: yes, merge it; wait)' "$T/$CASE/decided" \
    && grep -qxF -- '- **Picked:** yes, merge it' "$T/$CASE/decided" \
    && grep -qxF -- '- **Why:** it is the recommended option, and the owner took the recommended option in 1 of their last 2 picker answers.' "$T/$CASE/decided" \
    && grep -q '^- \*\*Reversible:\*\* yes: ' "$T/$CASE/decided" && ! grep -q d-flag "$T/$CASE/decided" || fail "the log's decision entry: $(cat "$log")"
  awk '/^## Waiting for the owner$/ { on = 1; next } on' "$log" | grep -qxF -- '- d-flag: Add a new feature flag for exports? (reserved: feature flag)' \
    || fail "the reserved decision is not listed under Waiting for the owner: $(cat "$log")"
  # Bug: a picker ask with no recommended option was answered with its ledger default, the word "none".
  [ "$(answer d-pick)" = open ] && grep -qxF -- '- d-pick: Which colour for the chart? (no recommended option)' "$log" \
    || fail "the decision with no recommended option: $(answer d-pick) $(cat "$log")"
  out=$(cd "$R" && loop auto decide) && [ "$(grep -c -- '^- d-flag: ' "$log")" = 1 ] || fail "a second pass listed the reserved decision again: $(cat "$log")"
  [ "$(cd "$R" && loop auto band)" = "$(jq -cn --arg s "$(jq -r .since "$ST/auto/mode.json")" '{scope: "full", since: $s, count: 1}')" ] || fail "the band: $(cd "$R" && loop auto band)"
  out=$(cd "$R" && loop auto off) && [ ! -e "$ST/auto/mode.json" ] && [ "$(cd "$R" && loop auto band)" = '{"scope":"off","since":null,"count":1}' ] \
    || fail "auto off: $out $(cd "$R" && loop auto band)"
}

# Bug: an answer the ledger refused was counted as decided. With the ledger read-only, decision.sh cannot answer:
# the entry says it was not recorded, the decision waits for the owner, and the band counts no decision.
t_autounrecorded() {
  local out log; autoledger; chmod a-w "$LEDGER"
  out=$(cd "$R" && loop auto on && loop auto decide) || fail "decide failed: $out"
  log=$(jq -r .log "$ST/auto/mode.json"); chmod u+w "$LEDGER"
  [ "$(answer d-docs)" = open ] && grep -q '^- \*\*Recorded:\*\* no, so it still waits for the owner: ' "$log" \
    && grep -qxF -- '- d-docs: Merge the docs fix now? (the answer could not be recorded)' "$log" \
    && [ "$(cd "$R" && loop auto band | jq .count)" = 0 ] || fail "an unrecorded answer: $(cat "$log") $(cd "$R" && loop auto band)"
}

# Bug: narrow (the owner is here) decides more than the formalities. It answers only an open decision whose recommended
# option the owner already gave to the same question (the ruling x-1), and leaves the other for the owner. The ruling
# keeps "(Recommended)" on the answer and the ledger's default does not: compared as they are, x-1 never matched.
t_autonarrow() {
  local out log; autoledger
  jq -c '.question = "Merge the release notes?" | .id = "d-notes"' <<<"$(head -1 "$LEDGER")" >> "$LEDGER"
  out=$(cd "$R" && loop auto narrow && loop auto decide) || fail "auto narrow failed: $out"
  log=$(jq -r .log "$ST/auto/mode.json")
  [ "$(answer d-docs)" = 'yes, merge it' ] && [ "$(answer d-notes)" = open ] && [ "$(answer d-flag)" = open ] \
    || fail "narrow answered d-docs $(answer d-docs), d-notes $(answer d-notes), d-flag $(answer d-flag)"
  grep -qxF -- '- **Why:** the owner already gave this answer to the same question (ruling x-1).' "$log" \
    && grep -qF -- '- d-notes: Merge the release notes? (narrow: not a formality' "$log" || fail "the narrow log: $(cat "$log")"
}

# Bug: auto overrides the owner's latest ruling. The owner answered the docs question "yes, merge it" (x-1), then
# "wait" (x-3): the reopened d-docs recommends "yes, merge it", which the earlier ruling matched, so it was answered
# against the owner's last word. It must wait for the owner, in full mode (which never read the rulings) and narrow.
autoreruled() { # <on|narrow>
  local out log; autoledger
  jq -cn '{id: "x-3", source: "ask", question: "Merge the docs fix now?", answer: "wait", pick: "option"}' >> "$CONVEYOR_RULING_LOG"
  out=$(cd "$R" && loop auto "$1" && loop auto decide) || fail "auto $1 failed: $out"
  log=$(jq -r .log "$ST/auto/mode.json")
  [ "$(answer d-docs)" = open ] && grep -qxF -- "- d-docs: Merge the docs fix now? (against the owner's latest ruling x-3 on this question)" "$log" \
    || fail "auto $1 answered d-docs $(answer d-docs) against the ruling x-3: $(cat "$log")"
}
t_autoreruled() { autoreruled on; }
t_autoreruledn() { autoreruled narrow; }

# Bug: auto off counted every "### " entry in the log as a decision made for the owner, the ones under "Waiting for the
# owner" too, so a log with 1 decision and 3 waiting entries said "after 4 decision(s)". It says 1 decided, 3 waiting.
t_autooffcount() {
  local out log; setup '[]'
  out=$(cd "$R" && loop auto on) || fail "auto on failed: $out"
  log=$(jq -r .log "$ST/auto/mode.json")
  printf '%s\n' '# Decisions made for the owner (auto, from 2026-11-16 22:14)' '' '## Summary' '' 'Decided for the owner: 1. Waiting for the owner: 3.' '' \
    '## Decisions' '' '### 22:20 d-a: Merge it?' '- **Question:** Merge it?' '- **Picked:** yes' '' \
    '## Waiting for the owner' '' '### 22:30 d-b: Ship it?' '- **Question:** Ship it?' '' '### 22:31 d-c: Drop it?' '- **Question:** Drop it?' '' \
    '- d-d: Which colour? (no recommended option)' > "$log"
  out=$(cd "$R" && loop auto off) && [[ $out == "auto OFF after 1 decided, 3 waiting for the owner: "* ]] || fail "auto off: $out"
  [ "$(cd "$R" && loop auto band | jq .count)" = 1 ] || fail "the band after off: $(cd "$R" && loop auto band)"
}
