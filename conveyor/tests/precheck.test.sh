#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: `conveyor.sh precheck` (commands/precheck.sh), what the engine checks after a session (the project's
# checks, the commit trailers the pack requires, the form of the Done-when lines), run in the card's worktree before the
# session ends.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# One issue (7) with two Done-when items; the pack's checks fail on a file holding BAD, and its trailer rule asks for
# `Mutation-verified:` of an added test file. Card c7's worktree, $W, is made on main's commit; its change adds
# t.test.sh with <the text of a.txt> in a.txt, and the reply file $T/$CASE/reply holds <the reply>.
prewt() { # <a.txt text> <reply>
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "body"+"\n\n## Done when\n- the first thing\n- the second thing"')]"
  tune --arg c 'if grep -q BAD a.txt; then echo "a.txt holds BAD"; exit 1; fi' \
    '.test.checkCommand = $c | .commit.trailers = [{token: "Mutation-verified", when: "\\.test\\.sh$", ask: "Say what you broke to see the test fail."}]'
  git -C "$R" add -f .conveyor/project.json && { git -C "$R" commit -qm pack || :; } && W=$T/$CASE/cards/c7 && git -C "$R" worktree add -q --detach "$W" || fail "the card's worktree"
  printf '%s\n' "$1" > "$W/a.txt"; echo x > "$W/t.test.sh"; printf '%s\n' "$2" > "$T/$CASE/reply"
  git -C "$W" status --porcelain > "$T/$CASE/status.before"
}
preout() { # [<reply file as the command is given it>]
  out=$(cd "$W" && CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$SRC/conveyor.sh" precheck 7 "${1:-$T/$CASE/reply}" 2>&1); RC=$?; }

# Bug: a failing check, a missing trailer or a Done-when item without its line goes unreported in the session, so the
# engine finds it after the session and starts a fix session. All three are in this worktree: each must be named.
t_precheckfail() {
  prewt 'BAD' $'## Done when\nD1 met: t.test.sh case one'
  # Bug: reading the new files adds their objects to the repository's object folder, where a build session may not write
  # (a Codex sandbox): the folder must hold the same files after the command as before it.
  objs=$(git -C "$W" rev-parse --path-format=absolute --git-path objects); find "$objs" -type f | sort > "$T/$CASE/objs.before"
  preout
  [ "$(find "$objs" -type f | sort)" = "$(cat "$T/$CASE/objs.before")" ] || fail "precheck added objects to $objs, which a session may not write"
  [ "$RC" = 1 ] && grep -q 'a.txt holds BAD' <<<"$out" && grep -q 'Mutation-verified' <<<"$out" && grep -q 'D2: no `D2 met:' <<<"$out" \
    || fail "precheck did not report the failing check, the missing trailer and the missing D2 line (exit $RC): $out"
  [ "$(git -C "$W" status --porcelain)" = "$(cat "$T/$CASE/status.before")" ] && [ -z "$(git -C "$W" diff --cached --name-only)" ] \
    || fail "precheck staged or changed the worktree: $(git -C "$W" status --porcelain)"
}

# Bug: precheck fails a worktree that holds no failure (a trailer written, checks passing, every item answered).
t_precheckpass() {
  prewt 'fine' $'## Done when\nD1 met: t.test.sh case one\nD2 met: a.txt:1 holds the second thing'
  echo 'Mutation-verified: broke X, the test went red' > "$W.trailers"
  preout
  [ "$RC" = 0 ] && [ "$out" = 'precheck: passed' ] || fail "precheck did not pass a worktree with no failure (exit $RC): $out"
  # Bug: it keeps the checks' result beside the worktree, where a build session may not write (a Codex sandbox).
  [ ! -e "$W.checks" ] || fail "precheck wrote $W.checks, outside the worktree"
}

# Bug: an open-work marker the change adds, which the reply must name, passes the form check when only the D<n> lines
# are read, so the engine finds it after the session and starts a fix session. The marker is written in pieces here, so
# this file adds none itself.
t_precheckmarker() {
  prewt 'fine' $'## Done when\nD1 met: t.test.sh case one\nD2 met: a.txt:1 holds the second thing'
  echo 'Mutation-verified: broke X, the test went red' > "$W.trailers"; printf '# T%s later\n' ODO >> "$W/a.txt"
  preout
  [ "$RC" = 1 ] && grep -q '[T]ODO added in a.txt is not named' <<<"$out" || fail "precheck did not report the unnamed marker (exit $RC): $out"
}

# Bug: a reply file given as a relative path is read from the main checkout (the command changes folder), not from the
# worktree it was called in.
t_precheckrel() {
  prewt 'fine' $'## Done when\nD1 met: t.test.sh case one\nD2 met: a.txt:1 holds the second thing'
  echo 'Mutation-verified: broke X, the test went red' > "$W.trailers"; cp "$T/$CASE/reply" "$W/reply.md"
  preout reply.md
  [ "$RC" = 0 ] && [ "$out" = 'precheck: passed' ] || fail "precheck did not read the relative reply file reply.md from the worktree (exit $RC): $out"
}

# Bug: a worktree with no change (the card's work is already on main) holds an ALREADY-DONE one line, which is not a
# Done-when form; the engine checks none on a clean worktree, and precheck must not ask for D<n> lines there.
t_precheckdone() {
  prewt 'fine' 'ALREADY-DONE: a.txt on main holds it'
  rm -f "$W/t.test.sh"; git -C "$W" show HEAD:a.txt > "$W/a.txt" || fail "a.txt is not in the worktree's commit"
  [ -z "$(git -C "$W" status --porcelain)" ] || fail "the worktree is not clean: $(git -C "$W" status --porcelain)"
  preout
  [ "$RC" = 0 ] && [ "$out" = 'precheck: passed' ] || fail "precheck failed an ALREADY-DONE reply in a worktree with no change (exit $RC): $out"
}

# Bug: a draft reply saved in the worktree is read as part of the change, so the marker it names is reported as one
# added in the reply file itself. The marker is written in pieces here, so this file adds none itself.
t_precheckdraft() {
  prewt 'fine' "$(printf '## Done when\nD1 met: t.test.sh case one\nD2 met: a.txt:1 holds the second thing\nT%s in a.txt: left for the next card' ODO)"
  echo 'Mutation-verified: broke X, the test went red' > "$W.trailers"; printf '# T%s later\n' ODO >> "$W/a.txt"; cp "$T/$CASE/reply" "$W/reply.md"
  preout reply.md
  [ "$RC" = 0 ] && [ "$out" = 'precheck: passed' ] || fail "precheck counted the draft reply reply.md as part of the change (exit $RC): $out"
}

# R171. Bug it catches: precheck left an untracked draft reply in the worktree out of the change, but the engine staged
# it (donewhen(), git add -A), so an ALREADY-DONE card's clean worktree had a change with no D<n> lines for the issue's
# Done-when items: a fix session. The build session writes reply.md in the worktree and runs precheck on it; after the
# session (session()), donewhen() sees no change and the worktree is clean, the draft moved beside it.
# Bug it catches too: a second precheck, on reply-final.md, replaced the first draft's name, so only reply-final.md was
# moved and donewhen() staged reply.md. The session runs precheck on each draft: both are moved, in that order.
t_precheckengine() {
  prewt 'fine' 'ALREADY-DONE: a.txt on main holds it'
  rm -f "$W/t.test.sh"; git -C "$W" show HEAD:a.txt > "$W/a.txt" || fail "a.txt is not in the worktree's commit"
  local pc; pc="bash $(printf %q "$SRC/conveyor.sh") precheck 7"
  # shellcheck disable=SC2016 # expanded by the stub's shell, in the worktree
  printf '%s\n' 'echo "ALREADY-DONE: a.txt on main holds it" > reply.md' "$pc"' reply.md > "$STUB/pre.out" 2>&1' \
    'printf "Checked again.\nALREADY-DONE: a.txt on main holds it\n" > reply-final.md' "$pc"' reply-final.md >> "$STUB/pre.out" 2>&1' > "$STUB/build"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'session "$W" "Build the issue." > /dev/null; donewhen "$W" "$(gh issue view 7 --json number,title,body,labels,milestone)"; git -C "$W" status --porcelain'
  [ "$(cat "$STUB/pre.out" 2>&1 | paste -sd ' ')" = 'precheck: passed precheck: passed' ] || fail "precheck, given each untracked draft reply in a clean worktree, did not pass: $(cat "$STUB/pre.out" 2>&1)"
  [ ! -s "$T/$CASE/run.out" ] && [ "$(cat "$W.reply.kept" 2>&1)" = 'ALREADY-DONE: a.txt on main holds it' ] \
    && [ "$(head -n 1 "$W.reply.kept-2" 2>&1)" = 'Checked again.' ] \
    || fail "after the session, donewhen() checked a draft reply as a change, or the worktree is not clean: $(cat "$T/$CASE/run.out") $(ls "$W".reply.kept* 2>&1)"
}
# E13 (review). Bug it catches: a session whose reply is outside the worktree (precheck names no draft, so there is
# no <worktree>.briefs/reply) had replyout() print bash's missing-file error to the session's log after each session.
t_precheckoutside() {
  prewt 'fine' 'ALREADY-DONE: a.txt on main holds it'
  preout
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'replyout "$W"'
  [ "$RC" = 0 ] && [ ! -e "$W.briefs/reply" ] && [ ! -s "$T/$CASE/run.out" ] \
    || fail "replyout on a worktree whose precheck, given $T/$CASE/reply outside it, named no draft printed or failed (exit $RC): $(cat "$T/$CASE/run.out")"
}
# E2. Bug it catches: precheck wrote the reply's name beside the worktree, where a Codex session's sandbox may not
# write, and passed when the write failed: the engine then staged the draft reply. A briefs folder that cannot be
# written (here a file in its place) must fail the precheck, not pass it.
t_precheckmarkfail() {
  prewt 'fine' 'ALREADY-DONE: a.txt on main holds it'
  rm -f "$W/t.test.sh"; git -C "$W" show HEAD:a.txt > "$W/a.txt" || fail "a.txt is not in the worktree's commit"
  cp "$T/$CASE/reply" "$W/reply.md"; echo x > "$W.briefs"
  preout reply.md
  [ "$RC" = 2 ] && [[ $out == *'could not be named'* ]] || fail "precheck 7 reply.md, with the reply's name not writable, did not fail (exit $RC): $out"
}
