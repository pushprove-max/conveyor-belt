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
# session's reply read from $STUB/reply.<its number>.
DW=$'## Done when\n- the first thing\n- the second thing'
dwsetup() { # <issue json>
  setup "[$1]"
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
  snap=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '.landed[] | select(.issue == 7) | .doneWhen' <<<"$snap")" = '{"items":2,"met":2,"failed":[]}' ] \
    || fail "the snapshot does not carry the landed card's Done-when check: $(jq -c '.landed | map({issue, doneWhen})' <<<"$snap")"
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
  snap=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '.needsYou.blocked[] | select(.issue == 9) | .doneWhen | [.items, .met, (.failed | length)]' <<<"$snap")" = '[2,1,1]' ] \
    || fail "the snapshot does not carry the blocked card's Done-when check: $(jq -c '.needsYou.blocked | map({issue, doneWhen})' <<<"$snap")"
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

# Bug: an issue with no `## Done when` is checked, or its reviewer is given Done-when lines.
t_dwnone() {
  # #10: no `## Done when`: no check, and a reply with no section lands.
  dwsetup "$(issue 10 2026-01-04)"
  echo "$GO" > "$STUB/review.1"; echo 'echo four >> b.txt' > "$STUB/build"
  loop run --only 10 >/dev/null || fail "run of #10 exited non-zero"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ "$(st 'select(.issue == 10) | select(has("doneWhen"))')" = '' ] && [ -n "$(st 'select(.issue == 10 and .step == "landed") | .sha')" ] \
    || fail "an issue with no Done when section was checked, or did not land: $(st 'select(.issue == 10)')"
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
    ( STATE=$ST/cards.jsonl; . "$SRC/lib/testrun.sh"; donewhen "$w" "$(issue "$1" 2026-01-01 | jq -c '.body = "## Done when\n- the thing"')" ) || echo "the check of #$1 failed to run"
  }
  k=$(marked 7 "rm t.txt; echo 'TODO later' > t2.txt"); [ "$k" = '{"items":1,"met":1,"failed":[]}' ] || fail "a TODO line moved to another file failed the reply check: $k"
  k=$(marked 8 ": > v.txt; echo '[VERIFY] the limit' > v2.txt"); [ "$k" = '{"items":1,"met":1,"failed":[]}' ] || fail "a [VERIFY] line moved to another file failed the reply check: $k"
  k=$(marked 9 "echo 'TODO again' > n.txt"); [ "$(jq -c .failed <<<"$k")" = '["TODO added in n.txt is not named in the reply"]' ] || fail "a new TODO line passed the reply check unnamed: $k"
}
