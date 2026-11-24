#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: Needs you says a blocked land-branch card can be shut (onMain) only while main still holds the change
# its branch was picked to land (branchon(), lib/snapshot.sh). Their own file, to keep recshut.test.sh under the 600
# lines a case file may have.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# shutonmain <card> <want> <what> [<picked epoch>]: the snapshot's onMain of the blocked land-branch card <card> of
# branch hand/r, picked at that time (picksoon when none is given) against main as later() first found it, is <want>.
# The card's title, which only its picked line has, says the snapshot read that line, and with it the branch and the
# base: a snapshot that dropped the line says no card is on main, so <want> false would hold with no check at all.
# With SHUTNOBASE set, the picked line is an older engine's: it has no base, and the blocked line names the folder of
# its kept patch as block() names it, kept/<card> in the state folder, where block() kept that commit as <card>.base.
shutonmain() {
  local snap
  [ -s "$T/$CASE/base" ] || fail "the case moved main with no later(), so no card was picked"
  [ -z "${SHUTNOBASE:-}" ] || { mkdir -p "$ST/kept/$1" && cp "$T/$CASE/base" "$ST/kept/$1/$1.base"; } || fail "the kept base was not written"
  jq -cn --arg c "$1" --arg t "$(jq -nr --argjson p "${4:-$(picksoon)}" '$p | todate')" --arg m "$(cat "$T/$CASE/base")" --arg nb "${SHUTNOBASE:-}" --arg k "kept/$1" '{card:$c,issue:0,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
    | (. + {step:"picked",title:"hand r",branch:"hand/r"} + (if $nb == "" then {base:$m} else {} end)),
      (. + {step:"blocked",result:"blocked",reason:"NO-GO: review 1."} + (if $nb == "" then {} else {kept:$k} end))' > "$ST/cards.jsonl"
  snap=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c --arg c "$1" '[.needsYou.blocked[] | select(.card == $c) | [.title, .onMain == true]]' <<<"$snap")" = "[[\"hand r\",$2]]" ] \
    || fail "Needs you has not the picked line's title \"hand r\" and onMain $2 for hand/r, $3: $(jq -c '.needsYou.blocked | map([.card, .title, .onMain])' <<<"$snap") $(git -C "$R" log --oneline --stat main)"
}
# picksoon: the epoch half an hour from now, the picked line's time unless told: after the setup's commits to main,
# before main moves by later().
picksoon() { echo $(($(date +%s) + 1800)); }
# later <git args>: git in the test checkout an hour from now, as main moves after the card is picked: its reflog line
# has that time. Its first call keeps main's commit before it, the one the card was picked against.
later() {
  [ -s "$T/$CASE/base" ] || git -C "$R" rev-parse main > "$T/$CASE/base" || return 1
  GIT_COMMITTER_DATE="$(($(date +%s) + 3600)) +0000" git -C "$R" "$@"
}

# Bug it catches (R314, E6): a branch whose tip main's history holds merges into main's own tree whatever main did since,
# and the checks that replaced it read the change from the newest main without the tip, or took a reverse patch with no
# context lines (which puts a line back that main already has back). So hand/r (its first commit takes a.txt's line
# out, its second adds s.txt), fast-forwarded into main one commit at a time after the card was picked and its first
# commit reverted there, was said to be on main, and Needs you offered to shut its card though main no longer has its
# whole change.
t_shutrevert() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && : > "$R/a.txt" && git -C "$R" commit -qam r && echo s > "$R/s.txt" && git -C "$R" add s.txt \
    && git -C "$R" commit -qm s && git -C "$R" switch -q - && later merge -q --ff-only hand/r~1 && later merge -q --ff-only hand/r \
    && later revert --no-edit hand/r~1 > /dev/null || fail "hand/r, merged into main a commit at a time and its first commit (a.txt's line taken out) reverted there"
  shutonmain c20261120T013605-x-0 false "merged into main a commit at a time and its first commit (a.txt's line taken out) reverted there"
}

# Bug it catches (R314 fix, E12): a file main took out since the change was not read (a mode change only when the
# change set the mode), so hand/r (it takes a.txt's line out, then adds s.txt), merged into main and a.txt then moved to
# b.txt with its line put back there, was said to be on main.
t_shutmoved() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && : > "$R/a.txt" && git -C "$R" commit -qam r && echo s > "$R/s.txt" && git -C "$R" add s.txt \
    && git -C "$R" commit -qm s && git -C "$R" switch -q - && later merge -q --ff-only hand/r && git -C "$R" mv a.txt b.txt \
    && git -C "$R" show 'HEAD~2:a.txt' > "$R/b.txt" && grep -q . "$R/b.txt" && later commit -qam moved \
    || fail "hand/r, merged into main, then a.txt moved to b.txt with its line put back"
  shutonmain c20261120T013613-x-0 false "merged into main, then a.txt moved to b.txt with its line put back"
}

# Bug it catches (R314 fix, rename): main's diff since the change read a moved file as one taken out, so hand/r (it
# takes a.txt's line out, then adds s.txt), merged into main and a.txt then moved to b.txt as it was, was no longer said
# to be on main though its change is all there.
t_shutmovedkept() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && : > "$R/a.txt" && git -C "$R" commit -qam r && echo s > "$R/s.txt" && git -C "$R" add s.txt \
    && git -C "$R" commit -qm s && git -C "$R" switch -q - && later merge -q --ff-only hand/r && git -C "$R" mv a.txt b.txt \
    && later commit -qm moved || fail "hand/r, merged into main, then a.txt moved to b.txt as it was"
  shutonmain c20261120T013615-x-0 true "merged into main, then a.txt moved to b.txt as it was"
}

# Bug it catches (R314 fix, E17): the branch's own change was read with no moves, so a file it only moved was a file
# taken out and one made, every line of it the branch's own. hand/r, which moves a.txt to b.txt, merged into main and
# b.txt's line then edited there, was no longer said to be on main though a.txt is still moved.
t_shutrenamed() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && git -C "$R" mv a.txt b.txt && git -C "$R" commit -qm moved && git -C "$R" switch -q - \
    && later merge -q --ff-only hand/r && echo edited > "$R/b.txt" && later commit -qam edited \
    || fail "hand/r, which moves a.txt to b.txt, merged into main and b.txt's line edited there"
  shutonmain c20261120T013617-x-0 true "which moves a.txt to b.txt, merged into main and b.txt's line edited there"
}

# Bug it catches (R314 fix, rename): with moves read as moves, a file main moved to the name of one the change took out
# was read at its old name alone, so hand/r, which takes a.txt out and makes c.txt, merged into main and c.txt then
# moved to a.txt there, was said to be on main though a.txt is back.
t_shutmovedback() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && git -C "$R" rm -q a.txt && echo c > "$R/c.txt" && git -C "$R" add c.txt && git -C "$R" commit -qm r \
    && git -C "$R" switch -q - && later merge -q --ff-only hand/r && git -C "$R" mv c.txt a.txt && later commit -qm back \
    || fail "hand/r, which takes a.txt out and makes c.txt, merged into main and c.txt moved to a.txt there"
  shutonmain c20261120T013616-x-0 false "which takes a.txt out and makes c.txt, merged into main and c.txt moved to a.txt there"
}

# Bug it catches (R314 fix, E13): the change was first read from the commit main and the branch share, then from main
# as its reflog had it before the picked second (the reflog stamps whole seconds), so hand/r, whose first commit (a.txt's
# line taken out) main had taken as a cherry-pick in the second the card was picked, before the pick, to land the rest
# (s.txt), then merged into main and that cherry-pick reverted, was not said to be on main though main has all it was
# picked to land.
t_shutpicked() {
  local p
  setup '[]'; p=$(picksoon)
  git -C "$R" switch -q -c hand/r && : > "$R/a.txt" && git -C "$R" commit -qam r && echo s > "$R/s.txt" && git -C "$R" add s.txt \
    && git -C "$R" commit -qm s && git -C "$R" switch -q - && GIT_COMMITTER_DATE="$p +0000" git -C "$R" cherry-pick -x hand/r~1 > /dev/null \
    && later merge -q --no-edit hand/r && later revert --no-edit 'HEAD^1' > /dev/null \
    || fail "hand/r, its first commit cherry-picked onto main in the picked second, then merged there and the cherry-pick reverted"
  shutonmain c20261120T013614-x-0 true "its first commit cherry-picked onto main in the picked second, then merged there and the cherry-pick reverted" "$p"
}

# Bug it catches (R314 fix, E6, E13): main as it was at the pick was read from its reflog, newest entry before the
# picked second, so hand/r, whose first commit (a.txt's line taken out) main took as a cherry-pick and reverted in the
# second the card was picked, before the pick, was read against main with the cherry-pick: its change was s.txt alone,
# and merged into main, a.txt's line then put back there, it was said to be on main.
t_shutpicksec() {
  local p
  setup '[]'; p=$(picksoon)
  git -C "$R" switch -q -c hand/r && : > "$R/a.txt" && git -C "$R" commit -qam r && echo s > "$R/s.txt" && git -C "$R" add s.txt \
    && git -C "$R" commit -qm s && git -C "$R" switch -q - && git -C "$R" cherry-pick -x hand/r~1 > /dev/null \
    && GIT_COMMITTER_DATE="$p +0000" git -C "$R" revert --no-edit HEAD > /dev/null && later merge -q --no-edit hand/r \
    && git -C "$R" show 'hand/r~2:a.txt' > "$R/a.txt" && grep -q . "$R/a.txt" && later commit -qam back \
    || fail "hand/r, its first commit cherry-picked onto main and reverted in the picked second, then merged there and a.txt's line put back"
  shutonmain c20261120T013612-x-0 false "its first commit cherry-picked onto main and reverted in the picked second, then merged there and a.txt's line put back" "$p"
}

# Bug it catches (R314 fix): the change was read from the oldest commit the branch's own reflog keeps, so hand/r, made
# with `git branch` at a commit that adds a line main has not, had no change at all, and was said to be on main once
# main took that commit and reverted it.
t_shutoldtip() {
  setup '[]'
  git -C "$R" switch -q -c side && echo r >> "$R/a.txt" && git -C "$R" commit -qam r && git -C "$R" switch -q - && git -C "$R" branch hand/r side \
    && later merge -q --ff-only hand/r && later revert --no-edit hand/r > /dev/null \
    || fail "hand/r, made at a commit of another branch, merged into main and reverted there"
  shutonmain c20261120T013607-x-0 false "made at a commit of another branch, merged into main and reverted there"
}

# Bug it catches (R314 fix, E7): only the added lines of a hunk that both took lines out and added some were checked, so
# hand/r, which puts new in place of old and obsolete, landed on main and obsolete then put back below new there, was
# said to be on main.
t_shutrestore() {
  setup '[]'
  printf 'old\nobsolete\nend\n' > "$R/r.txt" && git -C "$R" add r.txt && git -C "$R" commit -qm r \
    && git -C "$R" switch -q -c hand/r && printf 'new\nend\n' > "$R/r.txt" && git -C "$R" commit -qam new && git -C "$R" switch -q - \
    && later merge -q --ff-only hand/r && printf 'new\nobsolete\nend\n' > "$R/r.txt" && later commit -qam back \
    || fail "hand/r, which puts new in place of old and obsolete, merged into main and obsolete put back there"
  shutonmain c20261120T013609-x-0 false "which puts new in place of old and obsolete, merged into main and obsolete put back there"
}

# Bug it catches (R314 fix, E10): main changing either line beside a line the branch took out counted as putting it
# back, so hand/r, which takes obsolete out from between keep and last, landed on main and last then edited there, was
# no longer said to be on main though obsolete is still out.
t_shutbeside() {
  setup '[]'
  printf 'keep\nobsolete\nlast\n' > "$R/r.txt" && git -C "$R" add r.txt && git -C "$R" commit -qm r \
    && git -C "$R" switch -q -c hand/r && printf 'keep\nlast\n' > "$R/r.txt" && git -C "$R" commit -qam out && git -C "$R" switch -q - \
    && later merge -q --ff-only hand/r && printf 'keep\nlast changed\n' > "$R/r.txt" && later commit -qam beside \
    || fail "hand/r, which takes obsolete out, merged into main and the line after it edited there"
  shutonmain c20261120T013610-x-0 true "which takes obsolete out, merged into main and the line after it edited there"
}

# Bug it catches (R314 fix, E4): the reverse check carried context lines, so hand/r, landed on main and a line beside its
# change then edited on main, was no longer said to be on main though main still has its change.
t_shutadjacent() {
  setup '[]'
  printf '1\n2\n3\n' > "$R/n.txt" && git -C "$R" add n.txt && git -C "$R" commit -qm n \
    && git -C "$R" switch -q -c hand/r && printf '1\n2\nnew\n3\n' > "$R/n.txt" && git -C "$R" commit -qam r && git -C "$R" switch -q - \
    && later merge -q --ff-only hand/r && printf '1\n2\nnew\n3 changed\n' > "$R/n.txt" && later commit -qam beside \
    || fail "hand/r, merged into main and the line beside its change edited there"
  shutonmain c20261120T013606-x-0 true "merged into main and the line beside its change edited there"
}

# Bug it catches (R314 fix, E4): the reverse check of a file the branch made would take the whole file out, so hand/r,
# which makes n.txt, landed on main and a line then added to n.txt there, was no longer said to be on main though main
# still has its change.
t_shutnewfile() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && printf '1\n2\n3\n' > "$R/n.txt" && git -C "$R" add n.txt && git -C "$R" commit -qm n && git -C "$R" switch -q - \
    && later merge -q --ff-only hand/r && echo 4 >> "$R/n.txt" && later commit -qam more \
    || fail "hand/r, which makes n.txt, merged into main and a line added to n.txt there"
  shutonmain c20261120T013608-x-0 true "which makes n.txt, merged into main and a line added to n.txt there"
}

# Bug it catches (R314 fix, E9): a mode change has no hunk, and only a mode change of a file that was there was read,
# so hand/r, which makes n.txt executable, landed on main and its executable bit then taken off there, was said to be
# on main.
t_shutmode() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && printf '1\n' > "$R/n.txt" && chmod +x "$R/n.txt" && git -C "$R" add n.txt && git -C "$R" commit -qm n && git -C "$R" switch -q - \
    && later merge -q --ff-only hand/r && chmod -x "$R/n.txt" && later commit -qam plain \
    || fail "hand/r, which makes n.txt executable, merged into main and its executable bit taken off there"
  shutonmain c20261120T013611-x-0 false "which makes n.txt executable, merged into main and its executable bit taken off there"
}

# Bug it catches (R314 fix, E20): a card picked by an older engine has no base, and was read by the merge alone, so
# hand/r (it takes a.txt's line out), merged into main and that merge then reverted there, was said to be on main.
t_shutnobaserevert() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && : > "$R/a.txt" && git -C "$R" commit -qam r && git -C "$R" switch -q - \
    && later merge -q --no-ff -m merged hand/r && later revert --no-edit -m 1 HEAD > /dev/null \
    || fail "hand/r, merged into main and the merge then reverted there"
  SHUTNOBASE=1 shutonmain c20261120T013618-x-0 false "picked with no base, merged into main and the merge then reverted there"
}

# Bug it catches (R314 fix, E20): a card picked by an older engine has no base, and main before the merge that brought
# the tip in was taken as its base, so hand/r (it adds s.txt), squashed onto main, then merged into main and the squash
# reverted there, was read against main with s.txt already in it: its change was empty, and it was said to be on main.
t_shutnobasesquash() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && echo s > "$R/s.txt" && git -C "$R" add s.txt && git -C "$R" commit -qm s && git -C "$R" switch -q - \
    && later merge -q --squash hand/r && later commit -qm squash && later merge -q --no-ff -m merged hand/r \
    && later revert --no-edit HEAD~1 > /dev/null || fail "hand/r, squashed onto main, merged there and the squash then reverted"
  SHUTNOBASE=1 shutonmain c20261120T013621-x-0 false "picked with no base, squashed onto main, merged there and the squash then reverted"
}

# Bug it catches (R314 fix, the review after E20): a card picked by an older engine has no base, and one was looked
# for only as main before a merge that brought the tip in, so hand/r (it takes a.txt's line out), fast-forwarded into
# main with s.txt then added there, lost its close hint though main still has its change. E22: the kept base was read
# from the blocked line's kept folder as it stands, kept/<card>, from the checkout, not from the state folder, so it
# was never found and the hint was lost all the same.
t_shutnobaseff() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && : > "$R/a.txt" && git -C "$R" commit -qam r && git -C "$R" switch -q - \
    && later merge -q --ff-only hand/r && echo s > "$R/s.txt" && git -C "$R" add s.txt && later commit -qm s \
    || fail "hand/r, fast-forwarded into main and s.txt then added there"
  SHUTNOBASE=1 shutonmain c20261120T013622-x-0 true "picked with no base, fast-forwarded into main and s.txt then added there"
}

# Bug it catches (R314 fix, the earlier review): a card picked by an older engine has no base, and was not said to be
# on main at all, so hand/r (it takes a.txt's line out), merged into main with s.txt then added there, lost its close
# hint though main still has its change.
t_shutnobase() {
  setup '[]'
  git -C "$R" switch -q -c hand/r && : > "$R/a.txt" && git -C "$R" commit -qam r && git -C "$R" switch -q - \
    && later merge -q --no-ff -m merged hand/r && echo s > "$R/s.txt" && git -C "$R" add s.txt && later commit -qm s \
    || fail "hand/r, merged into main and s.txt then added there"
  SHUTNOBASE=1 shutonmain c20261120T013619-x-0 true "picked with no base, merged into main and s.txt then added there"
}

# Bug it catches (R314 fix, E21): any binary change on main to a file the change touched counted as undoing it, so
# hand/r, which only moves img.bin to pic.bin, merged into main and pic.bin's bytes then replaced there, was no longer
# said to be on main though the move is still there.
t_shutbinmove() {
  setup '[]'
  printf 'img\0one\n' > "$R/img.bin" && git -C "$R" add img.bin && git -C "$R" commit -qm img \
    && git -C "$R" switch -q -c hand/r && git -C "$R" mv img.bin pic.bin && git -C "$R" commit -qm moved && git -C "$R" switch -q - \
    && later merge -q --ff-only hand/r && printf 'img\0two\n' > "$R/pic.bin" && later commit -qam bytes \
    || fail "hand/r, which only moves img.bin to pic.bin, merged into main and pic.bin's bytes then replaced there"
  shutonmain c20261120T013620-x-0 true "which only moves img.bin to pic.bin, merged into main and pic.bin's bytes then replaced there"
}
