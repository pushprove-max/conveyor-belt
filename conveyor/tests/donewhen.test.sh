#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Done-when check of a session's reply.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The Done-when check: a card that says it is done without showing each line of the issue's `## Done when` holds
# leaves the review to find the missing item. Its cases (dw*) each run one issue's card, side by side.
# A Done-when case's main and stubs: its one issue (a JSON object), the review prompt kept in $STUB/asked, and each
# session's reply read from $STUB/reply.<its number>. No case here checks a push, so the rule "Push when a card lands"
# that setup turns on is off, as it is by default (a card still lands on main, its landed line keeping its sha): the
# push was about a tenth of the processes a landing case starts.
DW=$'## Done when\n- the first thing\n- the second thing'
dwsetup() { # <issue json>
  setup "[$1]"
  jq -c '.rules.push = false' "$ST/control.json" > "$STUB/c.new" \
    && mv "$STUB/c.new" "$ST/control.json" || fail "the control record"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB/brief"; echo "$*" >> "$STUB/sessions"; . "$STUB/build"
r=$(cat "$STUB/reply.$(wc -l < "$STUB/sessions")" 2>/dev/null)
jq -cn --arg r "$r" '{type: "result", is_error: false, result: $r, usage: {input_tokens: 10, cache_creation_input_tokens: 20, cache_read_input_tokens: 999, output_tokens: 5}}'
EOF
}

# Bugs: a reply with every item met and real evidence fails; its D<n> lines not kept on the build line; the reviewer
# is not given the D<n> lines, or its `DONE-WHEN: D<n> holds` line is read as a finding; the snapshot (the Board's card detail) lacks a landed card's check.
t_dwland() {
  dwsetup "$(issue 7 2026-01-01 | jq -c --arg b "body of 7"$'\n\n'"$DW" '.body = $b')"
  # #7: every item met, with evidence that holds (a test file the change adds, a root file and its line): one
  # session, review, landed.
  echo 'mkdir -p lib && echo x > lib/t.test.sh && echo two >> a.txt' > "$STUB/build"
  printf 'Done.\n\n## Done when\nD1 met: lib/t.test.sh case one passes\nD2 met: a.txt:2 holds the second thing\n' > "$STUB/reply.1"
  printf '%s\n' 'DONE-WHEN: D1 holds' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ "$(st 'select(.issue == 7 and .step == "build") | .doneWhen | tojson')" = '{"items":2,"met":2,"failed":[]}' ] \
    || fail "a reply with every item and real evidence did not pass the check in one session: $(st 'select(.issue == 7 and .step == "build")')"
  # The build line keeps the reply's D<n> lines with their state: the pull request of Land as pr lists them.
  [ "$(st 'select(.issue == 7 and .step == "build") | .doneLines | tojson')" = '["D1 met: lib/t.test.sh case one passes","D2 met: a.txt:2 holds the second thing"]' ] \
    || fail "the build line does not carry the reply's D<n> lines: $(st 'select(.issue == 7 and .step == "build")')"
  [ "$(st 'select(.issue == 7 and .step == "review") | .result')" = GO ] && [ -n "$(st 'select(.issue == 7 and .step == "landed") | .sha')" ] \
    || fail "a DONE-WHEN holds line was read as a finding, or #7 did not land: $(st 'select(.issue == 7 and .step == "review")')"
  grep -q "^# The card's Done-when lines$" "$STUB/asked" && grep -qx 'D1 met: lib/t.test.sh case one passes' "$STUB/asked" \
    && grep -qx 'D2 met: a.txt:2 holds the second thing' "$STUB/asked" || fail "the reviewer was not given the D<n> lines: $(cat "$STUB/asked")"
  # The Board's card detail reads the last check from the snapshot: Landed today carries it.
  snap=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.landed[] | select(.issue == 7) | .doneWhen' <<<"$snap")" = '{"items":2,"met":2,"failed":[]}' ] \
    || fail "the snapshot does not carry the landed card's Done-when check: $(jq -c '.landed | map({issue, doneWhen})' <<<"$snap")"
  # #305. Bugs: the Board's Done-when detail (each item's text, the build's D<n> line, the review's answer) is not kept,
  # or is carried in the snapshot (its size budget) instead of read on demand (history donewhen); a line keeping it is
  # refused by the record check.
  ! grep -q 'doneWhenItems\|doneWhenHolds\|case one passes' <<<"$snap" || fail "the snapshot carries the Done-when detail"
  recok "$ST/cards.jsonl" "#7's run"
  [ "$(loop history donewhen "$(st 'select(.issue == 7 and .step == "build") | .card')" | jq -c .items)" \
    = '[{"n":1,"text":"the first thing","builder":"D1 met: lib/t.test.sh case one passes","reviewer":"holds"},{"n":2,"text":"the second thing","builder":"D2 met: a.txt:2 holds the second thing","reviewer":null}]' ] \
    || fail "history donewhen does not give each item with its text, the build's line and the review's answer: $(loop history donewhen "$(st 'select(.issue == 7) | .card' | head -n 1)")"
}

# #305. Bugs: history donewhen takes the reviewer's answer from a review before the last check (an earlier round's), or
# drops a finding that names the item, or one past the reason's cut that only the tail keeps (c1's D10); a finding
# about D10 is given to D1 too. The reader is called on record lines alone.
t_dwdetail() {
  setup '[]'
  jq -c . >> "$ST/cards.jsonl" <<'EOF'
{"card":"c1","issue":5,"step":"build","doneWhenItems":[{"n":1,"text":"old","said":"D1 met: old"}]}
{"card":"c1","issue":5,"step":"review","reason":"","doneWhenHolds":[1]}
{"card":"c1","issue":5,"step":"fix","doneWhenItems":[{"n":1,"text":"one","said":"D1 met: a.test.sh case a"},{"n":2,"text":"two","said":null},{"n":10,"text":"ten","said":"D10 met: b.c:3"}]}
{"card":"c2","issue":6,"step":"review","reason":"","doneWhenHolds":[1,2,10]}
{"card":"c1","issue":5,"step":"review","reason":"[P1] D1's evidence: a.test.sh has no case a\n[P2] D10's evid","tail":"[P1] D1's evidence: a.test.sh has no case a\n[P2] D10's evidence: b.c:3 does not hold it","doneWhenHolds":[2]}
{"card":"c3","issue":7,"step":"build","doneWhenItems":[{"n":1,"text":"one","said":"D1 met: old"}]}
{"card":"c3","issue":7,"step":"review","reason":"[P1] D1 is not met","doneWhenHolds":[]}
{"card":"c3","issue":7,"step":"fix","doneWhenItems":[{"n":1,"text":"one","said":"D1 met: new"}]}
EOF
  # c3's last check has no review after it: the review of the build before it is not its answer.
  [ "$(loop history donewhen c3 | jq -c .items)" = '[{"n":1,"text":"one","builder":"D1 met: new","reviewer":null}]' ] \
    || fail "history donewhen gave the last check a review from before it: $(loop history donewhen c3)"
  [ "$(loop history donewhen c1 | jq -c .items)" = '[{"n":1,"text":"one","builder":"D1 met: a.test.sh case a","reviewer":"[P1] D1'"'"'s evidence: a.test.sh has no case a"},{"n":2,"text":"two","builder":null,"reviewer":"holds"},{"n":10,"text":"ten","builder":"D10 met: b.c:3","reviewer":"[P2] D10'"'"'s evidence: b.c:3 does not hold it"}]' ] \
    || fail "history donewhen did not pair the last check with the review after it: $(loop history donewhen c1)"
  [ "$(loop history donewhen c9)" = '{"card":"c9","items":[]}' ] || fail "a card with no check is not an empty list: $(loop history donewhen c9)"
}

# Bugs: a missing D<n> line, an empty evidence, or an added TODO the reply hides (naming another file that ends in the
# same path) passes, or fails without that item named; a named file that is not there fails its item instead of being
# a note; indented bullets are not items; a failed check blocks at once, or sends no fix session.
t_dwfix() {
  # #8 (its bullets indented, one nested under another): a missing D3, an empty evidence and an added TODO named only
  # beside another file each fail by name, and a named root test file that is not there is a note; one fix session is told them,
  # and its reply passes: review, landed.
  dwsetup "$(issue 8 2026-01-02 | jq -c '.body = "## Done when\n  - the first thing\n    - a detail of it\n  - the second thing\n  - the third thing\n\n## Notes\n- not an item"')"
  echo "echo 'TODO later' >> a.txt" > "$STUB/build"
  printf '## Done when\nD1 met: none\nD2 met: missing.test.sh case_two passes\nThe TODO in other/a.txt is old.\n' > "$STUB/reply.1"
  printf 'The TODO in a.txt is left for a later card.\n\n## Done when\nD1 met: a.txt:2 holds the line\nD2 met: `git diff --cached a.txt` shows it\nD3 not met: no test here\n' > "$STUB/reply.2"
  echo "$GO" > "$STUB/review.1"
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and .step == "build") | .doneWhen | [.items, .met, (.failed | sort | join(" | "))] | tojson')" \
    = '[3,1,"D1: met, with no evidence | D3: no `D3 met:` or `D3 not met:` line in the `## Done when` section that ends the reply | TODO added in a.txt is not named in the reply"]' ] \
    && [ "$(st 'select(.issue == 8 and .step == "build") | .doneWhen.notes | tojson')" = '["D2: names missing.test.sh, which is not in this worktree"]' ] \
    || fail "the failed items are not each named, or a missing file failed its item instead of being a note: $(st 'select(.issue == 8 and .step == "build") | .doneWhen')"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && grep -q '^# The Done-when check failed' "$STUB/brief" && grep -qx -- '- D1: met, with no evidence' "$STUB/brief" \
    && grep -qx -- '- TODO added in a.txt is not named in the reply' "$STUB/brief" || fail "no one fix session told the failed items: $(cat "$STUB/brief")"
  [ "$(st 'select(.issue == 8 and .step == "fix") | [(.reason | startswith("the Done-when check failed: ")), .doneWhen] | tojson')" = '[true,{"items":3,"met":2,"failed":[]}]' ] \
    && [ -n "$(st 'select(.issue == 8 and .step == "landed") | .sha')" ] || fail "the fix line does not carry the second check, or #8 did not land: $(st 'select(.issue == 8)')"
}

# Bugs: a second failure lands, or is reviewed; the snapshot (the Board's card detail) lacks a blocked card's check.
t_dwblock() {
  # #9: the fix session's reply fails too: blocked, with the item listed, and never reviewed.
  dwsetup "$(issue 9 2026-01-03 | jq -c --arg b "$DW" '.body = $b')"
  echo 'echo three >> a.txt' > "$STUB/build"
  printf '## Done when\nD1 met: a.txt:3\n' | tee "$STUB/reply.1" > "$STUB/reply.2"
  loop run --only 9 >/dev/null
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ ! -e "$STUB/reviews" ] \
    && st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q '^the Done-when check failed again after its one fix session: D2: no `D2 met:`' \
    || fail "a second failure did not block #9 with the item named, before any review: $(st 'select(.issue == 9)')"
  # The Board's card detail reads the last check from the snapshot: Needs you carries it.
  snap=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.needsYou.blocked[] | select(.issue == 9) | .doneWhen | [.items, .met, (.failed | length)]' <<<"$snap")" = '[2,1,1]' ] \
    || fail "the snapshot does not carry the blocked card's Done-when check: $(jq -c '.needsYou.blocked | map({issue, doneWhen})' <<<"$snap")"
}

# Bug (#466): a build that ends with a question for the owner and changes nothing is blocked with a reason that hides
# the question ("nothing to review"), or goes on to a fix session that answers it in the owner's place, or to review.
# The card is blocked at once with the question (its last paragraph, on one line) as its reason, with no fix or review.
t_dwasks() {
  dwsetup "$(issue 12 2026-01-06 | jq -c --arg b "$DW" '.body = $b')"
  echo : > "$STUB/build"
  printf 'I read the issue and changed nothing.\n\nShould the new word go in a.txt\nor in b.txt?\n' > "$STUB/reply.1"
  loop run --only 12 >/dev/null
  [ "$(st 'select(.issue == 12 and .step == "blocked") | .reason')" = "build: the session changed nothing and asks the owner: Should the new word go in a.txt or in b.txt?" ] \
    || fail "#12 was not blocked with the build's question as its reason: $(st 'select(.issue == 12) | [.step, .reason] | join(" ")')"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/reviews" ] && [ -z "$(st 'select(.issue == 12 and (.step == "review" or (.step == "start" and .of == "review")))')" ] \
    || fail "#12 had a fix session or a review after its question: $(wc -l < "$STUB/sessions") session(s), $(st 'select(.issue == 12) | .of // .step' | tr '\n' ' ')"
  # Bug (#466 review): the tree session() keeps before each session (<worktree>.before) was left in the cards folder.
  [ -z "$(find "$T/$CASE/cards" -maxdepth 1 -name '*.before' 2>/dev/null)" ] || fail "a .before file was left after the card ended: $(ls "$T/$CASE/cards")"
}

# Bug (#466): a fix session that changes nothing and only asks the owner a question is not caught: the build's change
# is still in the worktree, so it reads as a change, and the fixes inside checked() never looked. Here the Done-when
# fix asks: the card is blocked with its question, with no review.
t_dwfixasks() {
  dwsetup "$(issue 13 2026-01-07 | jq -c --arg b "$DW" '.body = $b')"
  echo '[ "$(wc -l < "$STUB/sessions")" != 1 ] || echo two >> a.txt' > "$STUB/build" # the build changes a.txt, the fix nothing
  printf 'Done.\n' > "$STUB/reply.1"
  printf 'Which file should I edit?\n' > "$STUB/reply.2"
  loop run --only 13 >/dev/null
  [ "$(st 'select(.issue == 13 and .step == "blocked") | .reason')" = "fix: the session changed nothing and asks the owner: Which file should I edit?" ] \
    && [ "$(wc -l < "$STUB/sessions")" = 2 ] && [ ! -e "$STUB/reviews" ] \
    || fail "#13's fix question did not block it before any review: $(wc -l < "$STUB/sessions") session(s), $(st 'select(.issue == 13) | [.step, .reason] | map(strings) | join(" ")' | tr '\n' ,)"
}

# Bugs (#466): asks() reads a Claude reply only, so a Codex or OpenCode builder's question goes on to review; and it
# counts a change already in the worktree before the session (a fix after a NO-GO) as the session's. asks()
# (lib/testrun.sh) is called on one worktree with each builder's stream in <worktree>.out, as checked() calls it.
t_asksreply() {
  setup '[]'
  local w=$T/$CASE/w q
  git -C "$R" worktree add -q --detach "$w" && echo earlier >> "$w/a.txt" && git -C "$w" add -A || fail "the worktree could not be made"
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh (SUITERUNS=${STATE%/*}/...)
  q=$( ( STATE=$ST/cards.jsonl; . "$SRC/lib/testrun.sh"
    treeof "$w" > "$w.before" || exit 1 # session() keeps this before each session: here, with the earlier change staged
    jq -cn '{type: "item.completed", item: {type: "agent_message", text: "I changed nothing.\n\nWhich file should I edit?"}}' > "$w.out"; asks "$w" || echo 'codex: none'
    jq -cn '{type: "step_start"}, {type: "text", part: {text: "I changed nothing.\n\nWhich file, a.txt or b.txt?"}}, {type: "step_finish"}' > "$w.out"; asks "$w" || echo 'opencode: none'
    echo more >> "$w/a.txt"; ! asks "$w" || echo 'asked after a change' ) ) || fail "asks() could not be run"
  [ "$q" = $'Which file should I edit?\nWhich file, a.txt or b.txt?' ] || fail "asks() did not read a Codex and an OpenCode question past an earlier change, or read one after a change: $q"
}

# Bug: a rebuild after a landing conflict goes to review unchecked, with the build's D<n> lines.
t_dwrebase() {
  # #11: the landing conflicts and the rebuild's reply has no D<n> line: the rebase line carries the failed check, one
  # fix session is told the items, and the review after it gets that session's D<n> lines, not the build's.
  dwsetup "$(issue 11 2026-01-05 | jq -c --arg b "$DW" '.body = $b')"
  echo "$GO" | tee "$STUB/review.1" > "$STUB/review.2"
  echo 'if grep -q "^# Landing conflict" "$STUB/brief"; then printf "ONE\nfive\n" > a.txt; else echo five >> a.txt; fi' > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  printf '## Done when\nD1 met: a.txt holds five\nD2 met: a.txt:1 is the build\n' > "$STUB/reply.1"; echo 'Rebuilt.' > "$STUB/reply.2"
  printf '## Done when\nD1 met: a.txt holds five\nD2 met: a.txt:2 after the rebuild\n' > "$STUB/reply.3"
  loop run --only 11 >/dev/null || fail "run of #11 exited non-zero"
  [ "$(st 'select(.issue == 11 and .step == "rebase") | .doneWhen | [.items, .met, (.failed | length)] | tojson')" = '[2,0,2]' ] && [ "$(wc -l < "$STUB/sessions")" = 3 ] \
    && [ "$(st 'select(.issue == 11 and .step == "fix") | .doneWhen | tojson')" = '{"items":2,"met":2,"failed":[]}' ] && [ -n "$(st 'select(.issue == 11 and .step == "landed") | .sha')" ] \
    || fail "the rebuild's reply was not checked, or #11 did not land after its one fix: $(st 'select(.issue == 11)')"
  grep -qx 'D2 met: a.txt:2 after the rebuild' "$STUB/asked" && ! grep -q 'is the build' "$STUB/asked" || fail "the review after the rebuild had stale D<n> lines: $(cat "$STUB/asked")"
}

# Bugs: a named file that is not there (a bare root name too, or two on one line) fails its item, or is not a note
# shown to the review; the record check takes notes that are not a list of strings (it sets that line aside).
t_dwnotes() {
  # #12: a pytest case after a missing path, a missing name with a one-letter extension and a :line, and one with no
  # :line and a one-letter extension (beside an e.g., which names no file), a missing path with no extension and a
  # :line, an absolute path outside the worktree, and a TODO added in a file whose name git quotes in a diff header are
  # each noted by name, not failed; the TODO fails, the fix reply names it (beside an i.e.), and the card lands.
  dwsetup "$(issue 12 2026-01-06 | jq -c '.body = "## Done when\n- one\n- two\n- three\n- four\n- five"')"
  echo "$GO" > "$STUB/review.1"
  echo "mkdir -p src && echo all: > src/Makefile && echo int > x.c && echo int > ok.h && echo 'TODO later' > café.py" > "$STUB/build"
  printf '## Done when\nD1 met: tests/missing.py::test_case passed\nD2 met: missing.c:1\nD3 met: lib/Makefile:1\nD4 met: %s:1 passes\nD5 met: y.c implements the requirement, e.g. as asked\n' "$STUB/x.py" > "$STUB/reply.1"
  printf 'The TODO in café.py stays.\n\n## Done when\nD1 met: tests/missing.py::test_case and tests/gone.py passed\nD2 met: x.c:1\nD3 met: src/Makefile:1\nD4 met: x.c:1 holds\nD5 met: x.c and ok.h implement it, i.e. as asked\n' > "$STUB/reply.2"
  loop run --only 12 >/dev/null || fail "run of #12 exited non-zero"
  [ "$(st 'select(.issue == 12 and .step == "build") | .doneWhen | [.items, .met, (.failed | sort | join(" | "))] | tojson')" \
    = '[5,5,"TODO added in café.py is not named in the reply"]' ] \
    && [ "$(st 'select(.issue == 12 and .step == "build") | .doneWhen.notes | join(" | ")')" = "D1: names tests/missing.py, which is not in this worktree | D2: names missing.c, which is not in this worktree | D3: names lib/Makefile, which is not in this worktree | D4: names $STUB/x.py, which is not in this worktree | D5: names y.c, which is not in this worktree" ] \
    || fail "a file reference was not noted, failed its item, or a quoted-name TODO slipped past the check: $(st 'select(.issue == 12 and .step == "build") | .doneWhen')"
  # The fix reply still names two missing files on one line: the card is not blocked for them, and the review is shown
  # a note for each.
  [ "$(st 'select(.issue == 12 and .step == "fix") | .doneWhen | tojson')" = '{"items":5,"met":5,"failed":[],"notes":["D1: names tests/gone.py, which is not in this worktree","D1: names tests/missing.py, which is not in this worktree"]}' ] && [ -n "$(st 'select(.issue == 12 and .step == "landed") | .sha')" ] \
    && grep -qx 'Note: D1: names tests/missing.py, which is not in this worktree' "$STUB/asked" && grep -qx 'Note: D1: names tests/gone.py, which is not in this worktree' "$STUB/asked" \
    || fail "#12's fix reply did not pass with its missing file as a note shown to the review, or #12 did not land: $(st 'select(.issue == 12)')"
  loop check || fail "a line with doneWhen is not a whole record"
  local bad; bad=$(jq -c 'select(.issue == 12 and .step == "fix") | .doneWhen.notes = false' "$ST/cards.jsonl"); echo "$bad" >> "$ST/cards.jsonl"
  # A refused line is set aside (#157), not passed: it leaves the records for the quarantine, named by its field.
  local n; n=$(wc -l < "$ST/cards.jsonl")
  loop check >/dev/null 2>&1 && jq -se --argjson n "$n" 'last | .line == $n and .field == "doneWhen"' "$ST/quarantined.jsonl" >/dev/null \
    && ! grep -qF '"notes":false' "$ST/cards.jsonl" || fail "the record check took doneWhen notes that are not a list of strings: $(cat "$ST/quarantined.jsonl" 2>&1)"
}

# Bugs: an issue with no `## Done when` is checked, or its reviewer is given Done-when lines; its build line loses the
# session's model, tokens and stats (with no Done-when file, the reply's D<n> lines read as two JSON arrays, which jq's
# --argjson refuses, and the line was written bare, the loop's log showing only jq's own error: the build and fix lines
# of the cards the engine files, which have no Done-when, were left unpriced on the Board, issue 452).
t_dwnone() {
  # #10: no `## Done when`: no check, and a reply with no section lands.
  dwsetup "$(issue 10 2026-01-04)"
  echo "$GO" > "$STUB/review.1"; echo 'echo four >> b.txt' > "$STUB/build"
  loop run --only 10 > /dev/null 2> "$STUB/run.err" || fail "run of #10 exited non-zero"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ "$(st 'select(.issue == 10) | select(has("doneWhen"))')" = '' ] && [ -n "$(st 'select(.issue == 10 and .step == "landed") | .sha')" ] \
    || fail "an issue with no Done when section was checked, or did not land: $(st 'select(.issue == 10)')"
  [ "$(st 'select(.issue == 10 and .step == "build") | .model == "m" and .usage.read == 999 and .tokens.claude > 0')" = true ] && ! grep -q 'invalid JSON text' "$STUB/run.err" \
    || fail "the build line of an issue with no Done when section lost the session's fields: $(st 'select(.issue == 10 and .step == "build")') $(cat "$STUB/run.err")"
  ! grep -q "Done-when lines" "$STUB/asked" || fail "the reviewer of #10 was given Done-when lines"
}

# The reply check counts a TODO or [VERIFY] marker as added only when the change adds more lines holding it than it
# removes. Bugs: a line holding one moved from one file to another fails a reply that does not name it (a split of a
# file then costs fix sessions); a new line holding TODO passes unnamed. The check is the engine's own donewhen()
# (lib/testrun.sh), called on a card's worktree with the build's edit in it and the session's reply in <worktree>.out,
# as checked() calls it after each build: three card runs cost the case about 13 CPU s, for that one function.
t_movedmarker() {
  setup '[]'
  printf 'TODO later\n' > "$R/t.txt"; printf '[VERIFY] the limit\n' > "$R/v.txt"; git -C "$R" add t.txt v.txt; git -C "$R" commit -qm markers
  local k
  marked() { # <issue> <the build's edit>: the check of a reply that names no file, on a worktree of main with that edit
    local w=$T/$CASE/cards/c$1
    git -C "$R" worktree add -q --detach "$w" && (cd "$w" && eval "$2") || { echo "the worktree of #$1 could not be made"; return; }
    jq -cn '{type: "result", is_error: false, result: "Done.\n\n## Done when\nD1 met: the change holds it"}' > "$w.out"
    # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh (SUITERUNS=${STATE%/*}/...)
    ( STATE=$ST/cards.jsonl; . "$SRC/lib/testrun.sh"; donewhen "$w" "$(issue "$1" 2026-01-01 | jq -c '.body = "## Done when\n- the thing"')" | jq -c 'del(.detail)' ) || echo "the check of #$1 failed to run"
  }
  k=$(marked 7 "rm t.txt; echo 'TODO later' > t2.txt"); [ "$k" = '{"items":1,"met":1,"failed":[]}' ] || fail "a TODO line moved to another file failed the reply check: $k"
  k=$(marked 8 ": > v.txt; echo '[VERIFY] the limit' > v2.txt"); [ "$k" = '{"items":1,"met":1,"failed":[]}' ] || fail "a [VERIFY] line moved to another file failed the reply check: $k"
  k=$(marked 9 "echo 'TODO again' > n.txt"); [ "$(jq -c .failed <<<"$k")" = '["TODO added in n.txt is not named in the reply"]' ] || fail "a new TODO line passed the reply check unnamed: $k"
}

# #876. Bug: a D<n> line with a bracketed tag before its colon (`D1 met [uncertain: not run]: ...`), as the card rules
# invite a session to tag what it did not verify, is not read, so the item fails as having no line and the card is
# blocked. The untagged forms are read as before. DONEWHEN (lib/testrun.sh) is run as donewhen() runs it.
t_dwtagged() {
  setup '[]'
  local out r=$'Done.\n\n## Done when\nD1 met [uncertain: not run]: evidence in a.txt\nD2 not met [likely]: why\nD3 met: plain evidence\nD4 not met: plain why\nD5 met [likely]:'
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh (SUITERUNS=${STATE%/*}/...)
  out=$( ( STATE=$ST/cards.jsonl; . "$SRC/lib/testrun.sh"
    jq -c --arg r "$r" --argjson m '[]' --arg wt "$T/$CASE" "$DONEWHEN" <<<"$(jq -cn '{body: "## Done when\n- one\n- two\n- three\n- four\n- five"}')" ) ) \
    || fail "the Done-when check failed to run"
  [ "$(jq -c '{met, failed}' <<<"$out")" = '{"met":[1,3],"failed":["D5: met, with no evidence"]}' ] \
    || fail "a tagged D<n> line was not read as its state, or an untagged one changed: $out"
  [ "$(jq -c '[.detail[].said]' <<<"$out")" = '["D1 met [uncertain: not run]: evidence in a.txt","D2 not met [likely]: why","D3 met: plain evidence","D4 not met: plain why","D5 met [likely]:"]' ] \
    || fail "the D<n> lines the review sees lost their text or tag: $out"
}

# Bug: a session's fields that cannot be put on its line (not JSON) leave the line bare with nothing in the log but
# jq's own error, which names no card and no step. dwfields() (lib/testrun.sh) is called as checked() calls it.
t_dwfields() {
  setup '[]'
  local out err
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh (SUITERUNS=${STATE%/*}/...)
  out=$( ( STATE=$ST/cards.jsonl; . "$SRC/lib/testrun.sh"; dwfields c7 "$T/$CASE/c7" build '' '.' <<<'not json' ) 2> "$T/$CASE/err") \
    || fail "dwfields failed on fields that are not JSON"
  err=$(cat "$T/$CASE/err")
  [ -z "$out" ] && grep -qF "conveyor: card c7: the build session's fields (its tokens, stats and Done-when check) could not be put on its build line; the line is written without them" <<<"$err" \
    || fail "fields that are not JSON were not left out with the card and step named: out=$out err=$err"
}
