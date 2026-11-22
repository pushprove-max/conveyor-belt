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
