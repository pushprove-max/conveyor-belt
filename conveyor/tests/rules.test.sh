#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: card rules, checks and the project pack (a card's test runs and trailers: testruns.test.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a build, fix, test-fix or rebase session is not given the card rules (its flags load no CLAUDE.md and
# no .claude/rules/), gets them twice, or anywhere but between the header and the issue; the reviewer is not given the
# same rules (plan section 10); a missing or empty rules file lets the card build without them, or blocks it with a reason that does not
# name the file. The card rules are not the core rules followed by the pack's.
t_rules() {
  local f=$T/$CASE/expected p i k h d=$T/$CASE/p
  printf '%s\n\n%s\n' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")" > "$f"
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$d/w"; echo 'Mutation-verified: broke X' > "$d/w.trailers"; echo 'FAIL widget.test.ts' > "$d/w.test"
  echo "$GO" > "$STUB/review.1"; sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  # The card's prompt (cardprompt()) of the header, brief and rules card() makes for #7, then each session's as card()
  # makes it from that prompt: the build's (that prompt), the fix's (fixprompt()), the test fix's (testfixprompt()),
  # the rebuild's and the port's (rebaseprompt()); and what review() hands the reviewer (the stub codex keeps its
  # stdin), given that prompt and what the review is shown beside the diff (reviewseen()), as card() gives it.
  cat > "$d/make.sh" <<'EOS'
W=$T/$CASE/p/w
i=$(gh issue view 7 --json number,title,body,labels,milestone) && h=$(header on) && b=$(brief c0-7 "$i" "$h") && r=$(cardrules "$i") \
  && s=$(cardprompt c0-7 "$h" "$r" "$b") && v=$(reviewseen "$W" '') || exit 1
cd "$T/$CASE/p" || exit 1
printf '%s' "$s" > 1 && fixprompt "$s" 'E1 [P1] a.txt:1 wrong word' > 2 && testfixprompt "$s" "$W" 1 > 3 \
  && rebaseprompt "$s" "$W" 'CONFLICT (content): a.txt' abc > 4 && rebaseprompt "$s" "$W" 'CONFLICT (content): a.txt' abc port > 5 || exit 1
review "$W" "$s$v" "$REVIEW" > /dev/null && cp "$STUB/asked" review && head -n 1 <<<"$REVIEW" > reviewhead
EOS
  fx_in '. "$T/$CASE/p/make.sh"'
  [ "$RC" = 0 ] || fail "the prompts could not be made (exit $RC): $(cat "$T/$CASE/run.out")"
  for i in 1 2 3 4 5 review; do
    k=$(sed -n "${i/review/6}p" <<<$'build\n# Reviewer findings\n# The changed tests fail (exit 1)\n# Landing conflict\nOne review of this port alone follows\n# The commit trailers')
    [ "$i" = 1 ] || grep -q "^$k" "$d/$i" || fail "prompt $i is not the $k prompt"
    [ "$(grep -cx '# Rules' "$d/$i")" = 1 ] && [ "$(grep -cxF "$(head -n 1 "$f")" "$d/$i")" = 1 ] \
      || fail "prompt $i ($k) does not hold the rules heading and text exactly once"
    [ "$(sed -n '/^# Rules$/,/^# Issue #7:/p' "$d/$i" | sed '1,2d;$d')" = "$(cat "$f")" ] \
      || fail "prompt $i ($k): the text between # Rules and the issue is not the core rules, then the pack's"
    # The header opens each session's prompt; the reviewer's comes after its instructions (REVIEW).
    h=$(grep -n '^Conveyor card c0-7\. Make the change' "$d/$i" | head -n 1 | cut -d: -f1)
    { [ "$i" = review ] && [ "$(head -n 1 "$d/$i")" = "$(cat "$d/reviewhead")" ] || [ "$h" = 1 ]; } \
      && [ "$(grep -nx '# Rules' "$d/$i" | cut -d: -f1)" -gt "$(awk -v h="${h:-1000000}" 'NR >= h && /keeps the work\.$/ { print NR; exit }' "$d/$i")" ] \
      || fail "prompt $i ($k): the rules do not come after the header"
  done
  grep -qx 'FAIL widget.test.ts' "$d/3" && grep -qx 'Mutation-verified: broke X' "$d/review" || fail "the test fix is not given the test output, or the reviewer the trailers"
  # Bug (#779): a card session is not told that a test checks its behaviour directly, and that a proxy check (other
  # test files, the real loop, polling) says why in a comment. This reads the build's prompt, not the rules file: only
  # that prompt shows the rule reaches the session.
  grep -qxF -- '- A test the card adds or changes checks the behaviour it protects directly. A test that runs other test files or the suite runner, runs the real loop, or polls a real process until a condition holds says why in a comment beside it: what a direct check cannot show. A reviewer flags one with no such comment as P3. The test lint fails a full-loop run the change adds or changes (`loop run` or `loop serve`, `conveyor.sh run` or `conveyor.sh serve`) with no `# loop: <why>` comment on its line or the line above.' "$d/1" \
    || fail "the build session was not given the direct-check rule"
  # A missing, then an empty rules file: the rules loader fails, saying why with the file's name, the reason card()
  # blocks the card with (`brief: <why>`) before any session.
  printf ' \n\n' > "$T/$CASE/empty.md"
  for p in "$T/$CASE/none.md" "$T/$CASE/empty.md"; do
    fx_in 'RULES='"$p"'; cardrules "$(gh issue view 7 --json number,title,body,labels,milestone)"'
    [ "$RC" = 1 ] && [ "$(cat "$T/$CASE/run.out")" = "the card rules file $p is missing or empty; a card never builds without it" ] \
      || fail "rules file $p: the rules loader did not fail naming the file (exit $RC): $(cat "$T/$CASE/run.out")"
  done
}

# Bugs (plan section 10): an area rule file the pack maps to a path the issue names (a root file or top-level
# directory too) is not given to the card, or is given to a card whose issue names no such path; the card's settings
# are not the generic settings with the pack's hooks after the generic ones of each event; a generic hook is named
# relative to the project, not by its pinned path in the engine's checkout; a pack hooks.json of another shape (one
# that would set what the generic settings set) is taken, so the card builds.
t_packrules() {
  local s=$T/$CASE/settings r x
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "It breaks in web/src/a.tsx:12, package.json and tools/ too."'), $(issue 8 2026-01-02)]"
  echo 'WEB-AREA-RULE' > "$R/.conveyor/web.md"; echo 'NPM-AREA-RULE' > "$R/.conveyor/npm.md"; echo 'TOOLS-AREA-RULE' > "$R/.conveyor/tools.md"
  tune '.areas = {"infra/**": ".conveyor/none.md", "web/src/**": ".conveyor/web.md", "package.json": ".conveyor/npm.md", "tools/": ".conveyor/tools.md"}'
  # The rules of each issue, and the settings made of the pack's hooks.json (the fixture's: lib/test-hooks.json), as
  # card() asks for them.
  fx_in 'for n in 7 8; do cardrules "$(gh issue view $n --json number,title,body,labels,milestone)" > "$T/$CASE/rules.$n" || exit 1; done; cardsettings "'"$s"'"'
  [ "$RC" = 0 ] || fail "the rules or the settings could not be made (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/rules.7")" = "$(printf '%s\n\n%s\n\nWEB-AREA-RULE\n\nNPM-AREA-RULE\n\nTOOLS-AREA-RULE' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")")" ] \
    || fail "#7 names web/src/a.tsx, the root file package.json and the top-level directory tools/: its rules are not the core rules, the pack's, then web.md, npm.md and tools.md"
  [ "$(cat "$T/$CASE/rules.8")" = "$(printf '%s\n\n%s' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")")" ] || fail "#8 names no area path and was given an area rule"
  [ "$(jq -c '[.hooks.PreToolUse[] | .matcher as $m | .hooks[] | "\($m) \(.command | split("/")[-1])"]' "$s")" \
    = '["Bash git-safety.sh","Bash bash-guardrails.sh","Bash adversarial-review-gate.sh","Bash dependency-addition-guard.sh","Edit|Write|MultiEdit dependency-addition-guard.sh","Edit|Write|MultiEdit ruling-cite-gate.sh","AskUserQuestion worker-ask-guard.sh","Bash pack-bash-guard.sh","Bash pack-test-guard.sh","Edit|Write|MultiEdit pack-edit-guard.sh"]' ] \
    && [ "$(jq -cS 'del(.hooks)' "$s")" = "$(jq -cS 'del(.hooks)' "$SRC/card-settings.json")" ] \
    || fail "the card's settings are not the generic ones with the pack's hooks after them: $(jq -c . "$s")"
  # Card sessions are headless and never pause, so a 1-hour cache write (2x the input price against 1.25x) buys nothing.
  [ "$(jq -r '.env.CLAUDE_CODE_PROMPT_CACHE_TTL' "$s")" = 5m ] || fail "the card's session was not given the 5-minute prompt cache lifetime: $(jq -c .env "$s")"
  # A card session opens no Board: its settings, the pack's hooks with them, carry no SessionStart hook and no opener.
  [ "$(jq -c '[.hooks.SessionStart, ([.. | .command? // empty | select(test("board-open"))] | length)]' "$s")" = '[null,0]' ] \
    || fail "the card's settings carry a SessionStart hook or the Board opener: $(jq -c .hooks "$s")"
  # The generic hooks by their pinned path (the engine's checkout, quoted), each a file there; the pack's as written.
  r=$(cd "$SRC/.." && pwd -P)
  [ "$(jq -r '.hooks[][] | .hooks[].command' "$s" | grep -cvF -e "'$r'/.claude/hooks/" -e '"$CLAUDE_PROJECT_DIR"/.claude/hooks/')" = 0 ] \
    && [ "$(jq -r '.hooks[][] | .hooks[].command' "$s" | grep -cF "'$r'/.claude/hooks/")" = 7 ] \
    && [ "$(jq -r '.hooks[][] | .hooks[].command' "$s" | grep -F '"$CLAUDE_PROJECT_DIR"' | sed 's|.*/||' | tr '\n' ' ')" = "pack-bash-guard.sh pack-test-guard.sh pack-edit-guard.sh " ] \
    || fail "the generic hooks are not named by their pinned path, or the pack's not as written: $(jq -c '[.hooks[][] | .hooks[].command]' "$s")"
  for x in $(jq -r '.hooks[][] | .hooks[].command' "$s" | sed -n "s|^'$r'||p"); do [ -f "$r$x" ] || fail "the pinned generic hook $r$x is not a file"; done
  # A hooks.json that sets permissions too: refused, saying why, which card() blocks the card with before any session.
  jq '. + {permissions: {allow: ["Bash"]}}' "$SRC/lib/test-hooks.json" > "$R/.conveyor/hooks.json"
  fx_in 'cardsettings "$T/$CASE/other"'
  [ "$RC" != 0 ] && grep -qF "$R/.conveyor/hooks.json is not {\"hooks\": {<event>: [...]}}" "$T/$CASE/run.out" \
    || fail "a hooks.json of another shape was taken for the card settings (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Bugs: a change that fails a product check (here two of the case's own: a baseline raised, a schema added) passes,
# or the check's own lines are not in what blocks the card: a check's verbose output (more than one command argument
# can hold) comes before its failing line, and the blocked line's tail keeps the end, so that line is not lost behind
# it; a clean change fails.
t_checks() {
  local d=$T/$CASE/cards o=$T/$CASE k
  setup "[$(issue 7 2026-01-01)]"
  echo '{"hex":3}' > "$R/baseline.json"; echo 'SCHEMA_4' > "$R/schema.txt"
  git -C "$R" add -A; git -C "$R" commit -qm ratchets
  cat > "$STUB/raise-check.sh" <<'CHECK'
a=$(git show "$1:baseline.json" | jq .hex); b=$(git show "$2:baseline.json" | jq .hex)
[ "$b" -le "$a" ] || { printf 'a%.0s' {1..1000}; echo; printf '12345678\n%.0s' {1..20000}; echo "LOOSENED baseline.json hex: $a -> $b"; exit 1; }
CHECK
  cat > "$STUB/schema-check.sh" <<'CHECK'
! git diff "$1" "$2" -- schema.txt | grep -q '^+SCHEMA_5' || { echo "adds schema 5 with no old-format test"; exit 1; }
CHECK
  tune --arg a "$STUB/raise-check.sh" --arg b "$STUB/schema-check.sh" '.checks = [$a, $b]'
  rulewt raise 'echo "{\"hex\":4}" > baseline.json'; rulewt schema 'echo SCHEMA_5 >> schema.txt'; rulewt lower 'echo "{\"hex\":2}" > baseline.json'
  # The checks runner on each change (main's commit and one of the staged change on it), as card() calls it.
  fx_in 'for k in raise schema lower; do checks "$d/$k" > "$o/$k.out"; echo "$k $?"; done'
  [ "$(head -n 3 "$T/$CASE/run.out" | tr '\n' ' ')" = "raise 1 schema 1 lower 0 " ] || fail "the checks did not fail the raised baseline and the added schema alone: $(cat "$T/$CASE/run.out")"
  [ "$(head -n 1 "$o/raise.out")" = 'raise-check.sh (exit 1):' ] && [ "$(tail -n 1 "$o/raise.out")" = 'LOOSENED baseline.json hex: 3 -> 4' ] && ! grep -q schema-check "$o/raise.out" \
    || fail "the raised baseline's lines are not the first check's own: $(head -c 300 "$o/raise.out")"
  grep -qx 'schema-check.sh (exit 1):' "$o/schema.out" && grep -qx 'adds schema 5 with no old-format test' "$o/schema.out" && ! grep -q raise-check "$o/schema.out" \
    || fail "the added schema's lines are not the second check's own: $(cat "$o/schema.out")"
  [ ! -s "$o/lower.out" ] || fail "a clean change printed check lines: $(cat "$o/lower.out")"
  # Bug: a failed product check let the card go on to its tests or a fix session. A card whose change fails both
  # checks: a whole card, as where its checks stop it is card()'s own order of steps. It is blocked after its review,
  # with no test run and no session after its build, the lines of both checks at the end of its tail.
  echo 'echo "{\"hex\":4}" > baseline.json; echo SCHEMA_5 >> schema.txt' > "$STUB/build"; echo "$GO" > "$STUB/review.1"; k=$(git -C "$R" rev-parse HEAD)
  rulecard 7
  [ "$(st '.step' | tr '\n' ' ')" = "picked worktree deps brief start build start review blocked " ] && [ ! -e "$STUB/tests" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] \
    && [ "$(git -C "$R" rev-parse HEAD)" = "$k" ] || fail "a card that fails a product check landed, ran its tests or got a fix session: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "blocked") | .reason')" = "a product check failed; nothing landed." ] \
    && [ "$(st 'select(.step == "blocked") | .tail' | tail -n 3)" = $'LOOSENED baseline.json hex: 3 -> 4\nschema-check.sh (exit 1):\nadds schema 5 with no old-format test' ] \
    || fail "the blocked line is not the sentence with both checks' lines at the end of its tail: $(st 'select(.step == "blocked") | [.reason, .tail[-300:]]')"
  recok "$ST/cards.jsonl" "the block of a failed check"
}

# Bugs: a host project's long check run, which holds the loop paused, shows nowhere, so nothing seems to run; a time
# left is guessed from too few lanes; a run long over stays shown; a progress command that fails, hangs or prints
# bad JSON, or JSON missing a field, breaks the snapshot; the command runs on every snapshot, or twice when two
# snapshots ask at once; a pack without one gains a field; /units has no block to print.
# Bug: Held and Queue sorted by when an issue was opened, so one held today came before one held ten days ago when
# it was opened first. Each issue there carries since: when it came to that column, never when it was opened.
t_since() {
  setup '[]'; touch "$ST/cards.jsonl" "$ST/retried.jsonl"
  { issue 1 2026-01-01T00:00:00Z; issue 2 2026-01-02T00:00:00Z; } | jq -cs . > "$STUB/issues.json"
  on() { local t=$1; shift; CONVEYOR_NOW=$(date -u -d "$t" +%s) loop "$@"; }
  # --fresh: each snapshot is built at its own time; a kept one (a few seconds old) still holds the earlier holds.
  at() { on "$1" snapshot --fresh; }
  col() { jq -c "$1 | map([.issue, .since])"; }
  # First sight, with no times kept: both are dated by that snapshot, not by when each was opened.
  out=$(at 2026-10-01); [ "$(col .queue.order <<<"$out")" = '[[1,"2026-10-01T00:00:00Z"],[2,"2026-10-01T00:00:00Z"]]' ] || fail "first sight: $out"
  on 2026-11-01 control hold 2 >/dev/null; at 2026-11-05 >/dev/null
  on 2026-11-12 control hold 1 >/dev/null; out=$(at 2026-11-13)
  # Each is dated by its hold: #2, held on November 1, has been held longer than #1, held on November 12, though
  # #1 is the older issue.
  [ "$(col .open.held <<<"$out")" = '[[1,"2026-11-12T00:00:00Z"],[2,"2026-11-01T00:00:00Z"]]' ] \
    && [ "$(col .queue.holding <<<"$out")" = '[[1,"2026-11-12T00:00:00Z"],[2,"2026-11-01T00:00:00Z"]]' ] || fail "held since: $out"
  # Released and held again with no snapshot between: held since the second hold, not the first.
  on 2026-11-14 control release 2 >/dev/null; on 2026-11-15 control hold 2 >/dev/null
  out=$(at 2026-11-16); [ "$(col .open.held <<<"$out")" = '[[1,"2026-11-12T00:00:00Z"],[2,"2026-11-15T00:00:00Z"]]' ] || fail "held again: $out"
  # Released with no snapshot between: each is queued since its release, not since the snapshot that saw it there,
  # so #2, released first, has waited longer than the older #1.
  on 2026-11-17 control release 2 >/dev/null; on 2026-11-18 control release 1 >/dev/null
  out=$(at 2026-11-19); [ "$(col .queue.order <<<"$out")" = '[[1,"2026-11-18T00:00:00Z"],[2,"2026-11-17T00:00:00Z"]]' ] || fail "released: $out"
  # A snapshot that listed #2 in Queue, before a hold that came while it ran (the pack's progress command holds it),
  # does not write its older sight over the hold in moved.json, which each later snapshot dates Held from.
  tuned '.checks = {run: [], progress: "CONVEYOR_NOW=$(date -u -d 2026-11-21 +%s) bash '"$SRC"'/conveyor.sh control hold 2 >/dev/null"}' at 2026-11-20 >/dev/null
  [ "$(jq -c '."2" | [.col, .at]' "$ST/moved.json")" = '["held","2026-11-21T00:00:00Z"]' ] || fail "an older sight written over a hold: $(cat "$ST/moved.json")"
  # Something besides your hold keeps #2 in Held (a rule): released and held again, it never left Held.
  on 2026-11-23 control rules P3=off >/dev/null; at 2026-11-24 >/dev/null
  on 2026-11-25 control release 2 >/dev/null; on 2026-11-26 control hold 2 >/dev/null
  out=$(at 2026-11-27); [ "$(col '.open.held | map(select(.issue == 2))' <<<"$out")" = '[[2,"2026-11-21T00:00:00Z"]]' ] || fail "held by a rule all along: $out"
  on 2026-11-27 control rules P3=on >/dev/null
  # The rule turned on since that snapshot no longer keeps it: released and held again before the next snapshot, it
  # left Held, and is held since the second hold.
  on 2026-11-28 control release 2 >/dev/null; on 2026-11-29 control hold 2 >/dev/null
  out=$(at 2026-11-30); [ "$(col '.open.held | map(select(.issue == 2))' <<<"$out")" = '[[2,"2026-11-29T00:00:00Z"]]' ] || fail "held since a release the rule no longer kept: $out"
  # Held from Queue, then a rule turned off before the release: the rule keeps it in Held all along, so a hold after
  # the release does not redate it (the hold kept what the snapshot read of it).
  on 2026-12-01 control release 2 >/dev/null; at 2026-12-01 >/dev/null
  on 2026-12-02 control hold 2 >/dev/null; on 2026-12-03 control rules P3=off >/dev/null
  on 2026-12-04 control release 2 >/dev/null; on 2026-12-05 control hold 2 >/dev/null
  out=$(at 2026-12-06); [ "$(col '.open.held | map(select(.issue == 2))' <<<"$out")" = '[[2,"2026-12-02T00:00:00Z"]]' ] || fail "a hold forgot the rule that keeps it: $out"
  on 2026-12-06 control rules P3=on >/dev/null
  # Released while a snapshot lists the issues, before it copies the control record: it shows #1 in Queue since the
  # release, not since its hold, so it does not sort before #2, held all along.
  on 2026-12-07 control hold 1 >/dev/null; at 2026-12-08 >/dev/null
  echo 'CONVEYOR_NOW=$(date -u -d 2026-12-11 +%s) bash '"$SRC"'/conveyor.sh control release 1 >/dev/null' > "$STUB/list-cmd"
  out=$(at 2026-12-10); rm "$STUB/list-cmd"
  [ "$(col .queue.order <<<"$out")" = '[[1,"2026-12-11T00:00:00Z"]]' ] || fail "a release while the snapshot ran gave Queue its Held time: $out"
  # GitHub does not list the issues: no since, and the times kept are not lost.
  cp "$ST/moved.json" "$STUB/moved.was"; echo junk > "$STUB/issues.json"
  out=$(at 2026-11-22); cmp -s "$ST/moved.json" "$STUB/moved.was" || fail "moved.json changed when the issues were not listed: $(cat "$ST/moved.json")"
  ! jq -e 'has("cols")' >/dev/null <<<"$out" || fail "the snapshot carries its columns: $out"
}

# Bugs: the remote, branch, labels, owner and product paths are the host project's, whatever the pack says: a landed
# card's commit is looked for on main and pushed to origin when the pack names master and upstream; the commit subject
# does not read the pack's type label and area prefix; a visible change asks for Dana's yes when
# the owner is Quinn; the follow-up, type, priority and area labels, and the product paths, are the host project's.
t_pack() {
  local X np d
  setup "[$(issue 7 2026-01-01 defect team/billing)]"; O=$T/$CASE/up
  git -C "$R" branch -m main master; git -C "$R" remote remove origin
  git init -q --bare -b master "$O"; git -C "$R" remote add upstream "$O"
  P=$R/.conveyor/project.json
  jq '.remote = "upstream" | .defaultBranch = "master" | .owner.name = "Quinn" | .productPaths = ["app/"]
    | .labels = {built: "shipped", followup: "fu", type: "defect", priorities: ["urgent", "high", "low"], areaPrefix: "team/", nonProductAreas: ["team/tools"]}' "$P" > "$P.new" \
    && mv "$P.new" "$P" && git -C "$R" push -q upstream master
  # A card of #7, its change staged in its worktree of master: what review() hands the reviewer (the stub codex keeps
  # its stdin), the commit message card() lands it with (cardsubject()), its landing (land(), on the pack's branch), the
  # push the loop starts once a card has landed (owed() reads the pack's branch, push() its remote), and the reason of a
  # change that waits for the owner's yes (YES).
  rulewt c0-7 'echo three >> a.txt'; echo "$GO" > "$STUB/review.1"; sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  fx_in 'w=$T/$CASE/cards/c0-7; review "$w" "the brief" > /dev/null && m=$(cardsubject c0-7 "$(gh issue view 7 --json number,title,body,labels,milestone)") \
    && cd "$R" && land c0-7 7 "$w" "$m" && read -r c n _ <<<"$(owed)" && push "$c" "$n" && printf "%s\n" "$YES" > "$T/$CASE/yes"'
  [ "$RC" = 0 ] || fail "the review, landing or push failed (exit $RC): $(tail -n 5 "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "landed") | .sha')" = "$(git -C "$R" rev-parse refs/heads/master)" ] && grep -qx three <(git -C "$R" show master:a.txt) \
    && ! git -C "$R" rev-parse -q --verify refs/heads/main >/dev/null || fail "the card did not land on master: $(st .)"
  [ "$(git -C "$O" rev-parse -q --verify refs/heads/master)" = "$(git -C "$R" rev-parse master)" ] || fail "the landed commit on master was not pushed to upstream: $(tail -n 5 "$T/$CASE/run.out")"
  [ "$(git -C "$R" log -1 --format=%s master)" = 'fix(billing): title 7 (#7)' ] || fail "the commit subject does not read the type label and area prefix: $(git -C "$R" log -1 --format=%s master)"
  grep -q "stops after review for Quinn's yes when" "$STUB/asked" && grep -q '(app/, tests aside)' "$STUB/asked" && ! grep -q "Dana's yes\|src/, shared/" "$STUB/asked" \
    || fail "the review prompt does not name the pack's owner and product paths"
  [ "$(cat "$T/$CASE/yes")" = "visible to customers or staff: needs Quinn's yes: " ] || fail "a visible change does not wait for the pack's owner: $(cat "$T/$CASE/yes")"
  # Health reads a card blocked with that reason as waiting for Quinn's yes.
  { landed 8 | jq -c '.step = "picked" | .sha = "" | .title = "title 8" | del(.product)'
    landed 8 | jq -c '.step = "blocked" | .result = "blocked" | .sha = "" | .reason = "visible to customers or staff: needs Quinn'"'"'s yes: guests see a new Pay button" | del(.product)'; } >> "$ST/cards.jsonl"
  [ "$(loop health | jq -c '.waiting | map(.issue)')" = '[8]' ] || fail "health does not list the card waiting for Quinn's yes: $(loop health)"
  # A last review's NO-GO files its follow-up with the pack's follow-up, type and priority labels and area label.
  printf '%s\n' '[P0] a.txt:1 wrong word' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$T/$CASE/c0-11.review"
  fx_in 'followups c0-11 '"'$(issue 11 2026-01-03 team/billing)'"' "$T/$CASE/c0-11.review"'
  [ "$RC" = 0 ] && [ "$(jq -c '[.labels[].name]' "$STUB/filed")" = '["fu","defect","urgent","team/billing"]' ] || fail "the follow-up's labels are not the pack's (exit $RC): $(cat "$STUB/filed" "$T/$CASE/run.out")"
  # Bugs: the pack's remote changed to an empty one: the commit pushed to the old one is unpushed, and the
  # push goes to the new one.
  X=$(git -C "$R" rev-parse master); git init -q --bare -b master "$T/$CASE/up2"; git -C "$R" remote add up2 "$T/$CASE/up2"
  jq '.remote = "up2"' "$P" > "$P.new" && mv "$P.new" "$P"
  loop health | jq -e --arg x "$X" '.unpushed | any(.sha == $x)' >/dev/null || fail "health hides a commit the pack's new remote lacks: $(loop health | jq -c .unpushed)"
  fx_in 'read -r c n _ <<<"$(owed)" && push "$c" "$n"'
  [ "$(git -C "$T/$CASE/up2" rev-parse -q --verify refs/heads/master)" = "$X" ] || fail "the push did not go to the pack's new remote: $(tail -n 5 "$T/$CASE/run.out")"
  jq '.remote = "upstream"' "$P" > "$P.new" && mv "$P.new" "$P"
  # Bugs: with the pack's built label not awaiting-deploy, an awaiting-deploy issue is still skipped, or an issue with
  # the pack's built label is picked; a pack with five priorities picks an older last one before a newer fourth one; an
  # area rule must start area:.
  jq '.labels.priorities = ["critical", "high", "medium", "low", "trivial"]' "$P" > "$P.new" && mv "$P.new" "$P"
  jq -cs . <(issue 21 2026-01-01 trivial) <(issue 22 2026-01-02 low) <(issue 23 2026-01-03 awaiting-deploy) <(issue 9 2026-01-04 critical shipped) > "$STUB/issues.json"
  # The pick order (upnext()) of the open issues, as pick() and the Board's queue read it.
  fx_in 'upnext "$(<"$STUB/issues.json")" | jq -c "map(.number)"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[22,21,23]' ] || fail "the pick order is not the pack's priorities, awaiting-deploy was skipped or the built label was not (exit $RC): $(cat "$T/$CASE/run.out")"
  # Bugs: a pack with one priority: an issue with none is P3, so a P1 rule leaves it alone.
  # Bug (#220): the Foreman's watcher of a belt on another host has no pack to read foreman.waitWake from, so the
  # snapshot, made on the belt's host, gives it; without it such a watcher woke at 10 minutes whatever the pack said.
  jq '.labels.priorities = ["urgent"] | .foreman.waitWake = 5' "$P" > "$P.new" && mv "$P.new" "$P"
  echo "[$(issue 24 2026-01-01)]" > "$STUB/issues.json"; loop control rules P1=off >/dev/null
  fx_in 'upnext "$(<"$STUB/issues.json")" | jq -c "map([.number, .p])"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[[24,"P3"]]' ] || fail "an issue with no priority took a P1 rule (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$(loop snapshot --fresh | jq -c '[.areaPrefix, .waitWake]')" = '["team/",5]' ] \
    || fail "the snapshot does not give the area prefix or the pack's foreman.waitWake: $(loop snapshot --fresh | jq -c '[.areaPrefix, .waitWake]')"
  loop control rules P1=on >/dev/null
  [ "$(loop control rules team/billing=off | jq -c .rules.never)" = '["team/billing"]' ] || fail "an area rule with the pack's area prefix was refused"
  loop control rules area:billing=off 2>/dev/null; [ $? = 2 ] || fail "an area rule without the pack's area prefix was taken"
  # Bugs: a Codex reviewer and no codex on PATH: the loop's preflight (clis()) starts no card and says what is
  # missing; with the reviewer on Claude, the same PATH passes it, though the pack still lists Codex models (they
  # gate nothing).
  mv "$STUB/codex" "$STUB/codex.off"
  np=$(tr : '\n' <<<"$PATH" | while read -r d; do [ -x "$d/codex" ] || printf '%s:' "$d"; done)
  PATH=${np%:} fx_in clis
  [ "$RC" != 0 ] && grep -q "the reviewer is set to codex x, and codex is not installed on this host" "$T/$CASE/run.out" || fail "the preflight passed with codex missing (exit $RC): $(cat "$T/$CASE/run.out")"
  seatset reviewer claude-opus-5-5
  PATH=${np%:} fx_in clis
  [ "$RC" = 0 ] || fail "a pack that lists Codex models was held for codex with no seat on it: $(cat "$T/$CASE/run.out")"
}

# Bug: a card() step gives its session or the reviewer a prompt without the rules, with them twice, or out of order.
# t_rules makes each prompt; a card run shows what build, review, a NO-GO's fix, a test fix and a conflict's rebuild get.
t_rulesall() {
  local i s r e; e=$(printf '%s\n\n%s\n\nWEB-AREA-RULE' "$(cat "$SRC/rules/card-core.md")" "$(cat "$SRC/lib/test-card-rules.md")")
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "It breaks in web/a.tsx."')]"; echo 'WEB-AREA-RULE' > "$R/.conveyor/web.md"; tune '.areas = {"web/**": ".conveyor/web.md"}'
  echo "$NOGO" > "$STUB/review.1"; for i in 2 3 4 5; do echo "$GO" > "$STUB/review.$i"; done; echo 'ONE other' > "$STUB/move"
  # The first test run and its re-run fail, so a test-fix session runs; main moves on the next run, so the rebuild runs.
  s=$(<"$STUB/test-cmd"); printf '%s\n%s\n' '[ "$(cat "$STUB/tests" 2>/dev/null | wc -l)" -ge 2 ] || { echo x >> "$STUB/tests"; echo "FAIL a.test.sh"; exit 1; }' "$s" > "$STUB/test-cmd"
  echo 'n=$(wc -l < "$STUB/sessions"); cp "$STUB/brief" "$STUB/brief.$n"; if grep -q "^# Landing conflict" "$STUB/brief"; then printf "ONE\nfive\n" > a.txt; else echo "five $n" >> a.txt; fi' > "$STUB/build"
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/asked.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"; rulecard 7
  grep -q '^build' "$STUB/brief.1" && grep -q '^# Reviewer findings' "$STUB/brief.2" && grep -q '^# The changed tests fail' "$STUB/brief.3" && grep -q '^# Landing conflict' "$STUB/brief.4" && [ -s "$STUB/asked.4" ] && [ -n "$(st 'select(.step == "landed") | .sha')" ] \
    || fail "the card did not build, fix, fix its tests, rebuild, have four reviews and land: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  for i in "$STUB"/brief.* "$STUB"/asked.*; do s=$(<"$i"); r=${s#*"$e"}
    [ "$r" != "$s" ] && [[ $r != *"$e"* ]] && [ "$(grep -cxF "$(head -n 1 "$SRC/rules/card-core.md")" "$i")" = 1 ] && [ "$(grep -cxF "$(head -n 1 "$SRC/lib/test-card-rules.md")" "$i")" = 1 ] \
      && [ "$(grep -cx WEB-AREA-RULE "$i")" = 1 ] || fail "${i##*/} does not hold the core rules, the pack's, then the area rule, each once"
  done
}

# Bugs: a missing or blank rules file, or a hooks.json of another shape, lets a card build, or blocks it with no reason;
# a trailer when that is no valid ERE lets it land. Other cases call the loaders; a card run shows where card() stops.
t_packstops() {
  local n p steps why h; setup "[$(issue 7 2026-01-01), $(issue 8 2026-01-02), $(issue 9 2026-01-03), $(issue 10 2026-01-04)]"; printf ' \n\n' > "$T/$CASE/blank.md"; echo "$GO" > "$STUB/review.1"; h=$(git -C "$R" rev-parse HEAD)
  while IFS='|' read -r n p steps why; do ( eval "$p"; rulecard "$n" ) || exit 1
    [ "$(st "select(.issue == $n) | .step" | tr '\n' ' ')" = "$steps" ] && st "select(.issue == $n and .step == \"blocked\") | .reason" | grep -qF -- "$why" \
      || fail "#$n ($p) did not block as $steps with its reason: $(st "select(.issue == $n) | \"\(.step) \(.reason)\"" | tr '\n' ,)"; cp "$SRC/lib/test-hooks.json" "$R/.conveyor/hooks.json"
  done <<EOS
7|export CONVEYOR_CARD_RULES=$T/$CASE/none.md|picked worktree deps blocked |brief: the card rules file $T/$CASE/none.md is missing or empty; a card never builds without it
8|export CONVEYOR_CARD_RULES=$T/$CASE/blank.md|picked worktree deps blocked |brief: the card rules file $T/$CASE/blank.md is missing or empty
9|jq '. + {permissions: {}}' "\$SRC/lib/test-hooks.json" > "\$R/.conveyor/hooks.json"|picked worktree deps blocked |$R/.conveyor/hooks.json is not {"hooks": {<event>: [...]}}
10|tune '.commit.trailers = [{"when": "[", "token": "Mutation-verified", "ask": "Say what you broke."}]'|picked worktree deps brief start build start review blocked |the engine could not read the commit trailers that the pack requires
EOS
  [ "$(git -C "$R" rev-parse HEAD)" = "$h" ] || fail "a card with an invalid pack input landed: $(git -C "$R" log --oneline)"
}

# Bug: a card starts from main and lands to origin, whatever branch and remote the pack names. t_pack calls land() and
# push(); the real loop picks, starts and pushes the card, and its empty-queue run pushes to a remote set after that.
t_packland() {
  local x; setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"; tune '.remote = "upstream" | .defaultBranch = "master"'
  git -C "$R" branch -m main master; git -C "$R" remote remove origin; git init -q --bare -b master "$T/$CASE/up"; git -C "$R" remote add upstream "$T/$CASE/up"; git -C "$R" push -q upstream master
  loop run --only 7 > "$T/$CASE/run.out" 2>&1 || fail "the run of #7 failed: $(tail -n 5 "$T/$CASE/run.out")"; x=$(git -C "$R" rev-parse master)
  [ "$(st 'select(.step == "landed") | .sha')" = "$x" ] && [ "$(git -C "$T/$CASE/up" rev-parse master)" = "$x" ] && grep -qx two <(git -C "$R" show master:a.txt) \
    || fail "#7 did not land on master and push to upstream: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  echo '[]' > "$STUB/issues.json"; git init -q --bare -b master "$T/$CASE/up2"; git -C "$R" remote add up2 "$T/$CASE/up2"; tune '.remote = "up2"'; loop run > "$T/$CASE/run.out" 2>&1 && [ "$(git -C "$T/$CASE/up2" rev-parse -q --verify master)" = "$x" ] \
    || fail "a run with an empty queue did not push the landing to the new remote: $(tail -n 5 "$T/$CASE/run.out")"
}
