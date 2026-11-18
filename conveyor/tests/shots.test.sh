#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the project's own screenshots of a visible change waiting for the owner's yes (#308): block() keeps
# them beside the card's kept patch (keepshots(), lib/push.sh) and the snapshot gives them with that patch's hash, for
# Needs you on the Board. fx_in and fx_wt are in lib.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Card c7 of #7 changes web/pay.ts; its project's run wrote shots/ (ignored by git): pay.png after the change, old.png
# before it (from an older patch of the card), and link.png, a link to a file outside the worktree. Main also holds
# gone.ts, which a case deletes later.
shotswt() {
  setup "[$(issue 7 2026-01-01)]"; FXWT=
  fx_wt 'mkdir -p web && echo pay > web/pay.ts' .gitignore 'shots/' gone.ts gone
  echo secret > "$T/$CASE/secret.png"
  mkdir -p "$FXWT/shots/pay" && echo new > "$FXWT/shots/pay/button.png" && echo old > "$FXWT/shots/old.png" \
    && touch -d "@$(($(date +%s) - 600))" "$FXWT/shots/old.png" && ln -s "$T/$CASE/secret.png" "$FXWT/shots/link.png" || fail "the screenshots"
}
blockyes() { fx_in 'block c7 7 "$FXWT" "${YES}guests see a Pay button" post'; [ "$RC" = 0 ] || fail "block: $(cat "$T/$CASE/run.out")"; }

# Bugs: the owner approved a visible change from text alone, though the project's run had made screenshots of it;
# a screenshot made before a later session changed the card was kept as the change's; a link out of the worktree was
# followed; the snapshot gave no hash to tie the screenshots to the patch they show; the worktree's own folder, whose
# time making shots/ set in the clock tick of the image (#454), left the image out.
t_shotskept() {
  shotswt; tune '.review.screenshots = "shots"'; blockyes
  k=$ST/kept/c7 h=$(echo new | git hash-object --stdin)
  [ "$(jq -c '.shots' "$k/shots/shots.json")" = "[{\"file\":\"$h.png\",\"caption\":\"pay/button.png\"}]" ] && [ "$(cat "$k/shots/$h.png")" = new ] \
    || fail "block did not keep only the screenshot made since the change: $(cat "$k/shots/shots.json" 2>&1; ls "$k/shots" 2>&1)"
  p=$(git hash-object "$k/c7.patch")
  [ "$(jq -r .patch "$k/shots/shots.json")" = "$p" ] || fail "the screenshots are not tied to the kept patch $p: $(cat "$k/shots/shots.json")"
  snap=$(loop snapshot) || fail "snapshot exited non-zero"
  [ "$(jq -c '.needsYou.waiting[] | select(.card == "c7") | [.patch, .shots.patch, (.shots.shots | map(.file))]' <<<"$snap")" = "[\"$p\",\"$p\",[\"$h.png\"]]" ] \
    || fail "the snapshot does not give the card's screenshots with its patch: $(jq -c '.needsYou.waiting' <<<"$snap")"
}

# Bug: Conveyor kept screenshots for a project whose pack names no folder for them, or for a folder outside the
# worktree (the screenshots are the project's own, in its checkout). Neither keeps any.
t_shotsnone() {
  shotswt; blockyes
  [ ! -e "$ST/kept/c7/shots" ] || fail "a pack with no review.screenshots kept screenshots: $(ls "$ST/kept/c7/shots")"
}
# Bugs: a screenshot made before a later session deleted a file of the change, or edited one later in the same second,
# was kept as the change's: a deleted file was not reckoned, and times were compared to the second.
t_shotsdeleted() {
  shotswt; tune '.review.screenshots = "shots"'; git -C "$FXWT" rm -q gone.ts; blockyes
  [ ! -e "$ST/kept/c7/shots" ] || fail "a screenshot from before a deletion was kept: $(cat "$ST/kept/c7/shots/shots.json" 2>&1)"
}
t_shotssamesec() {
  shotswt; tune '.review.screenshots = "shots"'; s=$(date +%s)
  touch -d "@$s.25" "$FXWT/shots/pay/button.png" && echo later >> "$FXWT/web/pay.ts" && touch -d "@$s.75" "$FXWT/web/pay.ts" \
    && git -C "$FXWT" add web/pay.ts || fail "the later edit"
  blockyes
  [ ! -e "$ST/kept/c7/shots" ] || fail "a screenshot from before an edit in the same second was kept: $(cat "$ST/kept/c7/shots/shots.json" 2>&1)"
}
# Bug (#454): a screenshot made before a later session put a changed file back as it is in HEAD was kept as the
# change's: the restored file dropped out of the diff, so its time was not reckoned.
t_shotsrestored() {
  shotswt; tune '.review.screenshots = "shots"'
  # Every file of the change is older than the screenshot (set in the future), so only the restored file's time, set
  # later still, can leave it out.
  s=$(date +%s); touch -d "@$((s + 5))" "$FXWT/shots/pay/button.png" || fail "the screenshot"
  echo gone > "$FXWT/gone.ts" && touch -d "@$((s + 10))" "$FXWT/gone.ts" && git -C "$FXWT" diff --quiet HEAD -- gone.ts \
    || fail "the restored file"
  blockyes
  [ ! -e "$ST/kept/c7/shots" ] || fail "a screenshot from before a file was restored was kept: $(cat "$ST/kept/c7/shots/shots.json" 2>&1)"
}
# Bug (#454): a screenshot made between a session's move of a file away and a later session's move of it back to its
# own path (git mv) was kept: the move back drops the file from the diff and keeps its mtime; only its ctime changes.
t_shotsmoved() {
  shotswt; tune '.review.screenshots = "shots"'
  git -C "$FXWT" mv gone.ts old.ts || fail "the move away"
  sleep 0.05 # sleep: a ctime is the clock's at the change and no program sets it, so only time passing parts the two
  touch "$FXWT/shots/pay/button.png" || fail "the screenshot"
  sleep 0.05 # sleep: as above, so the move back's ctime is later than the screenshot's mtime
  git -C "$FXWT" mv old.ts gone.ts && git -C "$FXWT" diff --cached --quiet HEAD -- gone.ts old.ts || fail "the move back"
  blockyes
  [ ! -e "$ST/kept/c7/shots" ] || fail "a screenshot from before a file was moved back was kept: $(cat "$ST/kept/c7/shots/shots.json" 2>&1)"
}
# Bug (#454): a screenshot made between a session's move of a folder away and a later session's move of it back was
# kept: the files in the folder keep their mtime and ctime; only the folder's own ctime and its parent's mtime change.
# The folder is nested, as in a Board's own folders.
t_shotsmovedfolder() {
  shotswt; tune '.review.screenshots = "shots"'
  mkdir "$FXWT/ui" && mv "$FXWT/web" "$FXWT/ui/web" && mv "$FXWT/ui/web" "$FXWT/ui/old" || fail "the move away"
  sleep 0.05 # sleep: a ctime is the clock's at the change and no program sets it, so only time passing parts the two
  touch "$FXWT/shots/pay/button.png" || fail "the screenshot"
  sleep 0.05 # sleep: as above, so the move back's times are later than the screenshot's mtime
  mv "$FXWT/ui/old" "$FXWT/ui/web" || fail "the move back"
  blockyes
  [ ! -e "$ST/kept/c7/shots" ] || fail "a screenshot from before a folder was moved back was kept: $(cat "$ST/kept/c7/shots/shots.json" 2>&1)"
}
t_shotsout() {
  shotswt; tune --arg d "$T/$CASE" '.review.screenshots = $d'; blockyes
  [ -s "$ST/kept/c7/c7.patch" ] && [ ! -e "$ST/kept/c7/shots" ] || fail "a folder outside the worktree gave screenshots: $(ls "$ST/kept/c7" 2>&1)"
}
