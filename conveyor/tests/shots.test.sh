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

# Card c7 of #7 adds web/pay.ts, a line to function a of web/list.ts (whose functions a and b have the same body) and a
# line to the first of web/nums.ts's two same blocks, whose lines give no function name;
# its project's run wrote shots/ (ignored by git): pay.png after the change, old.png before it (from an older patch of
# the card), and link.png, a link to a file outside the worktree. Main also holds gone.ts, which a case deletes later.
shotswt() {
  setup "[$(issue 7 2026-01-01)]"; FXWT=
  mkdir -p "$R/web"
  fx_wt 'echo pay > web/pay.ts && printf "a {\n1\n2\n3\nx\n4\n5\n6\n}\nb {\n1\n2\n3\n4\n5\n6\n}\n" > web/list.ts \
    && printf "0\n1\n2\n3\nx\n4\n5\n6\n1\n2\n3\n4\n5\n6\n" > web/nums.ts' .gitignore 'shots/' gone.ts gone \
    web/list.ts $'a {\n1\n2\n3\n4\n5\n6\n}\nb {\n1\n2\n3\n4\n5\n6\n}' web/nums.ts $'0\n1\n2\n3\n4\n5\n6\n1\n2\n3\n4\n5\n6'
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
# Bug: a card added index.html beside the screenshot folder, its run made a screenshot, and a later session removed
# the file: no list names it once it is gone, and the folders above the screenshot folder were not reckoned at all, so
# the old screenshot was kept as the final change's. At the worktree root (shotsgoneroot) and in a folder that holds
# the screenshot folder (shotsgoneup).
shotsgone() { # <folder that holds the screenshot folder: . or a folder>
  shotswt; tune --arg d "$1" '.review.screenshots = (if $d == "." then "shots" else "\($d)/shots" end)'
  mkdir -p "$FXWT/$1/shots" && echo page > "$FXWT/$1/index.html" && echo shot > "$FXWT/$1/shots/page.png" || fail "the screenshot"
  sleep 0.05 # sleep: the folder's time is the clock's at the removal, so only time passing makes it later than the image
  rm "$FXWT/$1/index.html" || fail "the removal"
  blockyes
  [ ! -e "$ST/kept/c7/shots" ] || fail "a screenshot from before a removal in $1 was kept: $(cat "$ST/kept/c7/shots/shots.json" 2>&1)"
}
t_shotsgoneroot() { shotsgone .; }
t_shotsgoneup() { shotsgone ui; }
t_shotsout() {
  shotswt; tune --arg d "$T/$CASE" '.review.screenshots = $d'; blockyes
  [ -s "$ST/kept/c7/c7.patch" ] && [ ! -e "$ST/kept/c7/shots" ] || fail "a folder outside the worktree gave screenshots: $(ls "$ST/kept/c7" 2>&1)"
}
# Bug: `conveyor.sh retry` of a card stopped for the yes, with no approval line since, stops again on the same kept
# patch, applied in a new worktree with no screenshots (the project's run wrote them in the old one): the new card
# kept none, and the Board showed the change from text alone. It keeps the earlier card's, tied to its own patch: the
# retry is built on a newer main (a line above web/list.ts's change and one above web/nums.ts's), so its patch differs
# byte for byte, and a shots.json copied as it was would tie them to c7's patch. A card whose change is no longer that
# patch keeps none of them, even when it differs only in whitespace (`.a .b` to `.a.b` in CSS), which git patch-id
# --stable does not read (c9), or adds the same line, between the same lines, in another function (c10: b, not a),
# which git patch-id does not read either, or (#563) adds the same line at another place with the same lines around it
# and no function name (web/nums.ts's second block), so its patch differs from c7's only in its hunks' line numbers and
# its index lines' blob ids: moved by hand (c11), or by git apply itself on a main that changed a line around the first
# block (c12).
t_shotsretry() {
  shotswt; tune '.review.screenshots = "shots"'; blockyes
  local w=$T/$CASE/cards/c8 x=$T/$CASE/cards/c9 y=$T/$CASE/cards/c10 z=$T/$CASE/cards/c11 v=$T/$CASE/cards/c12 h c
  printf '0\na {\n1\n2\n3\n4\n5\n6\n}\nb {\n1\n2\n3\n4\n5\n6\n}\n' > "$R/web/list.ts" \
    && printf '9\n0\n1\n2\n3\n4\n5\n6\n1\n2\n3\n4\n5\n6\n' > "$R/web/nums.ts" && git -C "$R" commit -qam 'main moves on' \
    && git -C "$R" worktree add -q --detach "$w" && git -C "$w" apply --index "$ST/kept/c7/c7.patch" \
    && git -C "$R" worktree add -q --detach "$x" && git -C "$x" apply --index "$ST/kept/c7/c7.patch" && echo 'pa y' > "$x/web/pay.ts" && git -C "$x" add -A \
    && git -C "$R" worktree add -q --detach "$y" && git -C "$y" apply --index "$ST/kept/c7/c7.patch" && printf '0\na {\n1\n2\n3\n4\n5\n6\n}\nb {\n1\n2\n3\nx\n4\n5\n6\n}\n' > "$y/web/list.ts" && git -C "$y" add -A \
    && git -C "$R" worktree add -q --detach "$z" && git -C "$z" apply --index "$ST/kept/c7/c7.patch" && printf '9\n0\n1\n2\n3\n4\n5\n6\n1\n2\n3\nx\n4\n5\n6\n' > "$z/web/nums.ts" && git -C "$z" add -A \
    && printf '9\n0\n1b\n2\n3\n4\n5\n6\n1\n2\n3\n4\n5\n6\n' > "$R/web/nums.ts" && git -C "$R" commit -qam 'main changes the first block' \
    && git -C "$R" worktree add -q --detach "$v" && git -C "$v" apply --index "$ST/kept/c7/c7.patch" \
    || fail "the retried worktrees"
  [ "$(sed -n 12p "$v/web/nums.ts")" = x ] || fail "git apply did not move c12's line to the second block: the case proves nothing"
  fx_in 'from=c7 fromk=$ST/kept/c7; block c8 7 "'"$w"'" "${YES}guests see a Pay button" post && block c9 7 "'"$x"'" "${YES}guests see a Pay button" post && block c10 7 "'"$y"'" "${YES}guests see a Pay button" post && block c11 7 "'"$z"'" "${YES}guests see a Pay button" post && block c12 7 "'"$v"'" "${YES}guests see a Pay button" post'
  [ "$RC" = 0 ] || fail "block: $(cat "$T/$CASE/run.out")"
  h=$(echo new | git hash-object --stdin)
  ! cmp -s "$ST/kept/c7/c7.patch" "$ST/kept/c8/c8.patch" || fail "the retried card's patch is c7's byte for byte: the case proves nothing"
  [ "$(jq -c '[.patch, .shots]' "$ST/kept/c8/shots/shots.json" 2>&1)" = "[\"$(git hash-object "$ST/kept/c8/c8.patch")\",[{\"file\":\"$h.png\",\"caption\":\"pay/button.png\"}]]" ] \
    && [ "$(cat "$ST/kept/c8/shots/$h.png")" = new ] || fail "the retried card did not keep the screenshots of the same patch: $(ls "$ST/kept/c8" 2>&1)"
  [ ! -e "$ST/kept/c9/shots" ] || fail "a retried card whose change differs from the kept patch kept its screenshots: $(cat "$ST/kept/c9/shots/shots.json")"
  [ "$(git patch-id --verbatim < "$ST/kept/c7/c7.patch" | cut -d' ' -f1)" = "$(git patch-id --verbatim < "$ST/kept/c10/c10.patch" | cut -d' ' -f1)" ] \
    || fail "c10's change has its own git patch-id: the case proves nothing"
  [ ! -e "$ST/kept/c10/shots" ] || fail "a retried card that adds the same line in another place kept its screenshots: $(cat "$ST/kept/c10/shots/shots.json")"
  for c in c11 c12; do
    [ "$(sed -E '/^index /d; s/^@@ [^@]*@@//' "$ST/kept/c7/c7.patch")" = "$(sed -E '/^index /d; s/^@@ [^@]*@@//' "$ST/kept/$c/$c.patch")" ] \
      || fail "$c's patch differs from c7's in more than its hunks' line numbers and its index lines' blob ids: the case proves nothing"
    [ ! -e "$ST/kept/$c/shots" ] || fail "$c, a retried card that adds the same line at another place with the same context, kept its screenshots: $(cat "$ST/kept/$c/shots/shots.json")"
  done
}
# Bug (#563): a retry whose change is the same as the kept patch's lost its screenshots when main changed a line around
# another copy of the lines around its edit, before it: here a.patch's line goes in web/nums.ts's second block, and main
# changes the first block's 1, so the edit's place among the same lines changes, but not the edit.
t_shotssame() {
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$R/web" && cd "$R" || fail "main"
  local a=$T/$CASE/kept/a b=$T/$CASE/kept/b
  mkdir -p "$a/shots" "$b" && echo new > "$a/shots/pay.png" \
    && printf '0\n1\n2\n3\n4\n5\n6\n1\n2\n3\n4\n5\n6\n' > web/nums.ts && git add web/nums.ts && git commit -qm base && git rev-parse HEAD > "$a/a.base" \
    && printf '0\n1\n2\n3\n4\n5\n6\n1\n2\n3\nx\n4\n5\n6\n' > web/nums.ts && git diff --binary --no-renames > "$a/a.patch" \
    && jq -cn --arg p "$(git hash-object "$a/a.patch")" '{patch: $p, shots: [{file: "pay.png", caption: "pay.png"}]}' > "$a/shots/shots.json" \
    && printf '0\n1b\n2\n3\n4\n5\n6\n1\n2\n3\n4\n5\n6\n' > web/nums.ts && git commit -qam 'main changes the first block' && git rev-parse HEAD > "$b/b.base" \
    && git apply --index "$a/a.patch" && git diff --cached --binary --no-renames > "$b/b.patch" \
    && [ "$(sed -n 11p web/nums.ts)" = x ] || fail "the two patches"
  fx_in "keptshots '$a' a '$b' b"
  [ "$RC" = 0 ] && [ "$(jq -r .patch "$b/shots/shots.json" 2>&1)" = "$(git hash-object "$b/b.patch")" ] && [ "$(cat "$b/shots/pay.png")" = new ] \
    || fail "the same change, on a main that changed the first block, did not keep its screenshots: $(cat "$T/$CASE/run.out"; ls "$b")"
}
