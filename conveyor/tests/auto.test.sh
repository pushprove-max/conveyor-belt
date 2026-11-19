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

# Bugs: with the project's owner-way.md (its written profile of how the owner decides) beside the Foreman's rules.md,
# auto rules does not name it or tell the Foreman to read it first and to keep its "Never decide; ask" and "Hard lines"
# sections; or, with no such file, the rules are not the ones auto printed before profiles (checked word for word,
# the count of the owner's picks and the ruling log's line with them). Full mode: the project's own Foreman, in
# <state folder>/foreman. Narrow: this checkout is beta of the group alpha, beta (foreman.groups), so the profile is in
# alpha's Foreman folder, beside the group's rules.md, never in beta's own state folder.
autoprofile() { # <on|narrow>
  local out before after fd line want run r; autoledger; unset CONVEYOR_FOREMAN_DIR
  fd=$ST/foreman
  if [ "$1" = narrow ]; then
    git init -q "$T/$CASE/alpha" && mkdir -p "$T/$CASE/alpha/.conveyor" && cp "$R/.conveyor/project.json" "$T/$CASE/alpha/.conveyor/"
    mkdir -p "$XDG_CONFIG_HOME/conveyor" && jq -n --arg a "$T/$CASE/alpha" --arg b "$R" \
      '{records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}], foreman: {groups: [["alpha", "beta"]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
    fd=$(CONVEYOR_MAIN=$T/$CASE/alpha bash "$SRC/conveyor.sh" state-dir)/foreman || fail "alpha has no state folder"
    [ "$(cd "$R" && loop state-dir)" = "$ST" ] && [ "$fd" != "$ST/foreman" ] || fail "the group fixture: beta's state folder is alpha's"
    mkdir -p "$ST/foreman"; printf '%s\n' '# Not the group profile' > "$ST/foreman/owner-way.md"
  fi
  mkdir -p "$fd"
  out=$(cd "$R" && loop auto "$1") || fail "auto $1 failed: $out"
  IFS=$'\t' read -r since log < <(jq -r '[.since, .log] | @tsv' "$ST/auto/mode.json")
  run="bash $(printf %q "$SRC/conveyor.sh") auto decide"
  r='production deploy, prod deploy, delete, feature flag, security, password, product setting, configured value, licence, license, consent'
  if [ "$1" = on ]; then
    want="# AUTO IS ON (since $since, /conveyor-belt:auto on)

The owner is away and has handed you their open decisions. Pick what is best for the project's long-term health, not the fastest path.

- Run \`$run\` from the main checkout now, and again each time a new open decision is on the Board. It answers each open decision that has a recommended option, that nothing reserves and that the owner's latest ruling on the same question does not answer otherwise, logs it, and lists the rest under \"## Waiting for the owner\" in $log.
- A question a session sends you that is not in the ledger: decide it the same way. Log it first in $log under \"## Decisions\" as \"### HH:MM <what>\", then the bullets **Question**, **Picked**, **Why** (the reasoning and the long-term trade-off) and **Reversible**.
- How the owner decides: the owner took the recommended option in 1 of their last 2 picker answers. Their recorded picks are in the ruling log $CONVEYOR_RULING_LOG; read the ones on the same subject before you decide what the ledger does not hold.
- Never decide; list under \"## Waiting for the owner\" instead: anything about $r; any irreversible step; anything against or reopening one of the owner's rulings; a question with no recommended option, or with two good ones.
- Do not ask the owner: the picker is refused while this is on. Keep \"## Summary\" in the log current.
- When the owner next types to you, give a short account of what you decided and point at the log. This stays on until /conveyor-belt:auto off."
  else
    want="# AUTO NARROW IS ON (since $since, /conveyor-belt:auto narrow)

The owner is here. Decide only the formalities; ask them everything else as usual (the picker is allowed).

- Run \`$run\` from the main checkout now, and again each time a new open decision is on the Board. It answers only an open decision whose recommended option the owner gave in their latest ruling on the same question (in $CONVEYOR_RULING_LOG) and that nothing reserves, logs it in $log, and leaves the rest for the owner.
- Tell the owner each one in one line in your next reply: \"Decided without asking: <what>, because <why>; say 'reverse <id>' to undo.\"
- Never decide: anything about $r; any irreversible step; anything against or reopening one of the owner's rulings. When unsure, ask the owner."
  fi
  before=$(cd "$R" && loop auto rules) && [ "$before" = "$want" ] \
    || fail "auto $1 rules with no profile are not what they were: $(diff <(echo "$want") <(echo "$before"))"
  printf '%s\n' '# How the owner decides' '## Never decide; ask' '- pricing' '## Hard lines' '- no tracking' > "$fd/owner-way.md"
  after=$(cd "$R" && loop auto rules) || fail "auto rules with a profile failed: $after"
  line="- The owner's written profile of how they decide is in $fd/owner-way.md: read it before you decide. Follow its \"Never decide; ask\" and \"Hard lines\" sections as you follow the pack's auto.reserved."
  # Every line of before stays (the count of the owner's picks with them); the profile's line is added once.
  [ "$(grep -vxF -- "$line" <<<"$after")" = "$want" ] && [ "$(grep -cxF -- "$line" <<<"$after")" = 1 ] \
    || fail "auto $1 rules with $fd/owner-way.md: $after"
}
t_autoprofile() { autoprofile on; }
t_autoprofilen() { autoprofile narrow; }
