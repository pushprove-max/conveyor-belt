#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a push the remote refuses, and the merge of the remote's commits into main (from every URL it pushes to).
# Its cases call serveeng(), stubland() and loopend(), defined in serve.test.sh: the runner sources every area file.
# .conveyor/test-links.json links serve.test.sh to this file, so a change to those helpers runs these cases too.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: the remote's main holds a commit the Conveyor's main lacks (landed there by hand), so every push is refused
# and no retry can work: the landings stack up unpushed, and nothing tells the owner. A refused push merges the
# remote's commits into main and pushes again; one that cannot (they conflict) and fails again on the next try is in
# Needs you, with git's error and the cards not pushed, until a push works.
t_pushmerge() {
  setup '[]'; O=$T/$CASE/origin; H=$T/$CASE/hand
  mainat() { git -C "$R" rev-parse refs/heads/main; }; originat() { git -C "$O" rev-parse refs/heads/main; }
  fails() { st 'select(.step == "push" and .result == "fail") | .card' | wc -l; }
  pushitem() { loop snapshot --fresh 2>/dev/null | jq -c '[.needsYou.blocked[] | select(.push)]'; }
  # Bug: the fetch of the remote's commits is made without the pack's push.env, so a remote reached only with what
  # it sets (an ssh identity) refuses it. Here the remote's side of every fetch writes down the variable it was given.
  P=$R/.conveyor/project.json; jq '.push.env = {"PUSH_AS": "pusher"}' "$P" > "$P.new" && mv "$P.new" "$P"
  printf '%s\n' '#!/usr/bin/env bash' "echo \"\${PUSH_AS:-none}\" >> '$STUB/fetches'" 'exec git-upload-pack "$@"' > "$STUB/up"; chmod +x "$STUB/up"
  git -C "$R" config remote.origin.uploadpack "$STUB/up"
  # By hand, from another clone: a commit to a file the card does not touch.
  git clone -q "$O" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main; hand=$(originat)
  serveeng "$SRC" 'stubland 7' || fail "card 7 did not land"
  out=$(loop run 2>&1) || fail "the run whose push the remote refused at first failed: $out $(st 'select(.step == "push")')"
  l7=$(st 'select(.step == "landed") | .sha')
  [ "$(originat)" = "$(mainat)" ] && git -C "$O" merge-base --is-ancestor "$hand" main && git -C "$O" merge-base --is-ancestor "$l7" main \
    || fail "the remote does not hold both the commit made by hand and the landing: $(git -C "$O" log --oneline main)"
  [ "$(st 'select(.step == "pushed") | [.issue, .sha, .head] | join(" ")')" = "7 $l7 $(mainat)" ] && [ "$(fails)" = 0 ] \
    || fail "the card is not recorded pushed by the push of the merge: $(st 'select(.step | IN("push", "pushed"))')"
  [ "$(cat "$R/c.txt")" = hand ] && [ -z "$(git -C "$R" status --porcelain)" ] && [ "$(loop health | jq -c '[.unpushed, .pushFails]')" = '[[],0]' ] \
    || fail "main's checkout lags the merge, or health still lists the landing: $(git -C "$R" status --porcelain) $(loop health | jq -c '[.unpushed, .pushFails]')"
  grep -qx pusher "$STUB/fetches" || fail "the fetch of the remote's commits was not given the pack's push.env: $(cat "$STUB/fetches" 2>&1)"
  # By hand again, now the line the next card adds too: the two do not merge. The push fails with git's conflict;
  # one failure is the belt's "tried again", not yet the owner's.
  git -C "$H" pull -q; echo other >> "$H/a.txt"; git -C "$H" commit -qam 'by hand, the same line'; git -C "$H" push -q origin main; hand=$(originat)
  serveeng "$SRC" 'stubland 8 a.txt' || fail "card 8 did not land"
  out=$(loop run 2>&1) && fail "a run whose push could not be merged exited zero: $out"
  c8=$(st 'select(.step == "landed" and .issue == 8) | .card'); l8=$(st 'select(.step == "landed" and .issue == 8) | .sha')
  [ -n "$c8" ] && [ "$(fails)" = 1 ] && [ "$(mainat)" = "$l8" ] && [ "$(originat)" = "$hand" ] && [ "$(pushitem)" = '[]' ] \
    || fail "a merge that conflicts moved main or the remote, or its first failure is in Needs you already: $(st 'select(.step == "push")') $(pushitem)"
  # The next try fails the same way: the push is a blocked item of Needs you, and health lists the card not pushed.
  out=$(loop run 2>&1) && fail "the retry of a push that cannot be merged exited zero: $out"
  snap=$(loop snapshot --fresh 2>/dev/null)
  [ "$(fails)" = 2 ] && [ "$(jq -c '[.needsYou.blocked[] | select(.push) | [.card, .issue, .reason, (.tail | test("CONFLICT.*a\\.txt")), .unpushed]]' <<<"$snap")" \
    = "[[\"$c8\",8,\"the push of main keeps failing. Not pushed: #8\",true,[{\"card\":\"$c8\",\"issue\":8}]]]" ] \
    || fail "a push that failed again is not a blocked item with git's error and the card not pushed: $(jq -c '.needsYou.blocked | map({card, reason, tail})' <<<"$snap")"
  [ "$(jq -c '[(.health.unpushed | map([.card, .sha])), .health.pushFails]' <<<"$snap")" = "[[[\"$c8\",\"$l8\"]],2]" ] \
    || fail "health does not list the card not pushed: $(jq -c '.health | [.unpushed, .pushFails]' <<<"$snap")"
  # The owner merges by hand: the next push works, and the item is gone.
  git -C "$R" merge -q -s ours -m 'merge by hand' origin/main; loop run > /dev/null 2>&1 || fail "the push after the owner's merge failed: $(st 'select(.step == "push")')"
  [ "$(originat)" = "$(mainat)" ] && [ "$(pushitem)" = '[]' ] && [ "$(loop health | jq -c '[.unpushed, .pushFails]')" = '[[],0]' ] \
    || fail "a push that worked left the push in Needs you: $(pushitem)"
  # Bug: the merge is committed past main's commit hooks, which every landing answers to. Here main's commit-msg hook
  # refuses a merge's message: the remote's commit merges, but no merge commit is made, and the push line says why.
  git -C "$H" pull -q; echo hand > "$H/d.txt"; git -C "$H" add d.txt; git -C "$H" commit -qm 'by hand, a third'; git -C "$H" push -q origin main; hand=$(originat)
  printf '%s\n' '#!/usr/bin/env bash' '! grep -q "^Merge " "$1" || { echo "no merge commits here"; exit 1; }' > "$R/.git/hooks/commit-msg"; chmod +x "$R/.git/hooks/commit-msg"
  serveeng "$SRC" 'stubland 9' || fail "card 9 did not land"
  out=$(loop run 2>&1) && fail "a run whose merge main's commit-msg hook refuses exited zero: $out"
  l9=$(st 'select(.step == "landed" and .issue == 9) | .sha')
  [ -n "$l9" ] && [ "$(mainat)" = "$l9" ] && [ "$(originat)" = "$hand" ] && [ -z "$(git -C "$R" status --porcelain)" ] \
    && [[ $(st 'select(.step == "push" and .result == "fail") | .reason' | tail -n 1) == *"commit of the merge refused: no merge commits here"* ]] \
    || fail "a merge main's commit-msg hook refuses was made, or the push line does not say it was refused: $(git -C "$R" log --oneline -3 main) $(st 'select(.step == "push")' | tail -n 1)"
  loopend
}

# Bugs: the remote pushes to other URLs than the one it fetches from (remote.origin.pushurl), and the commit that
# refuses the push is only at one the push goes to: the fetch after the refusal reads the fetch URL, or the first push
# URL alone, finds nothing main lacks, and the push keeps failing though the two merge cleanly. The remote's commits
# are fetched from every URL the push went to.
t_pushurl() {
  setup '[]'; O=$T/$CASE/origin; B=$T/$CASE/first.git; C=$T/$CASE/second.git; H=$T/$CASE/hand
  git clone -q --bare "$O" "$B"; git clone -q --bare "$O" "$C"; was=$(git -C "$O" rev-parse refs/heads/main)
  git -C "$R" config remote.origin.pushurl "$B"; git -C "$R" config --add remote.origin.pushurl "$C"
  # The remote names the program that serves its fetches (one of these may need its own): it notes what it served.
  printf '#!/bin/sh\necho "$1" >> "%s/served"\nexec git-upload-pack "$@"\n' "$T/$CASE" > "$T/$CASE/serve"; chmod +x "$T/$CASE/serve"
  git -C "$R" config remote.origin.uploadpack "'$T/$CASE/serve'"
  # Bug: the repository has a remote of the name the fetch is made under, so its URL (the fetch URL) is read instead.
  git -C "$R" config remote.conveyor-pushed.url "$O"; git -C "$R" config remote.conveyor-pushed.uploadpack false
  # By hand, to the second of the two only: a commit to a file the card does not touch.
  git clone -q "$C" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main
  hand=$(git -C "$C" rev-parse refs/heads/main); serveeng "$SRC" 'stubland 7' || fail "card 7 did not land"
  out=$(loop run 2>&1) || fail "the run whose push the second push URL refused at first failed: $out $(st 'select(.step == "push")')"
  l7=$(st 'select(.step == "landed") | .sha')
  for x in "$B" "$C"; do
    [ "$(git -C "$x" rev-parse refs/heads/main)" = "$(git -C "$R" rev-parse refs/heads/main)" ] && git -C "$x" merge-base --is-ancestor "$hand" main \
      && git -C "$x" merge-base --is-ancestor "$l7" main && [ "$(cat "$R/c.txt")" = hand ] \
      || fail "$x, where pushes go, does not hold both the commit made by hand and the landing: $(git -C "$x" log --oneline main) $(st 'select(.step == "push")')"
  done
  [ "$(st 'select(.step == "push" and .result == "fail") | .card' | wc -l)" = 0 ] && [ "$(git -C "$O" rev-parse refs/heads/main)" = "$was" ] \
    || fail "the push failed first, or went to the URL the remote fetches from: $(st 'select(.step == "push")')"
  grep -qxF "$C" "$T/$CASE/served" || fail "the push URL was not fetched with the remote's own uploadpack: $(cat "$T/$CASE/served" 2>&1)"
  loopend
}

# Bugs: the remote has two URLs and pushes to both (no pushurl, or the same list again), and the commit that refuses
# the push is at the second: the fetch after the refusal is made by the remote's name, which reads its first URL
# alone, finds nothing main lacks, and the push keeps failing though the two merge cleanly. Every URL is fetched.
t_pushurls() {
  setup '[]'; O=$T/$CASE/origin; C=$T/$CASE/second.git; H=$T/$CASE/hand
  git clone -q --bare "$O" "$C"; git -C "$R" config --add remote.origin.url "$C"
  git -C "$R" config remote.origin.pushurl "$O"; git -C "$R" config --add remote.origin.pushurl "$C"
  git clone -q "$C" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main
  hand=$(git -C "$C" rev-parse refs/heads/main); serveeng "$SRC" 'stubland 7' || fail "card 7 did not land"
  out=$(loop run 2>&1) || fail "the run whose push the remote's second URL refused at first failed: $out $(st 'select(.step == "push")')"
  l7=$(st 'select(.step == "landed") | .sha')
  for x in "$O" "$C"; do
    [ "$(git -C "$x" rev-parse refs/heads/main)" = "$(git -C "$R" rev-parse refs/heads/main)" ] && git -C "$x" merge-base --is-ancestor "$hand" main \
      && git -C "$x" merge-base --is-ancestor "$l7" main && [ "$(cat "$R/c.txt")" = hand ] \
      || fail "$x, where pushes go, does not hold both the commit made by hand and the landing: $(git -C "$x" log --oneline main) $(st 'select(.step == "push")')"
  done
  [ "$(st 'select(.step == "push" and .result == "fail") | .card' | wc -l)" = 0 ] || fail "the push failed first: $(st 'select(.step == "push")')"
  loopend
}

# Bugs: the push URL is set by the pack's push.env alone (git's GIT_CONFIG_* variables), and is a path relative to the
# folder the push is made from: the fetch after a refused push looks the URL up without push.env and reads the fetch
# URL, or takes the path from main's checkout and reads another folder, so a commit only where the push goes is
# never merged. The URL is looked up, and fetched, as the push is made: under push.env, from the push worktree.
t_pushurlenv() {
  setup '[]'; O=$T/$CASE/origin; B=$T/$CASE/pushed.git; H=$T/$CASE/hand
  git clone -q --bare "$O" "$B"; was=$(git -C "$O" rev-parse refs/heads/main)
  # From the push worktree ($T/$CASE/cards/push) the path is $B; from main's checkout it is no repository.
  P=$R/.conveyor/project.json; jq '.push.env = {GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "remote.origin.pushurl", GIT_CONFIG_VALUE_0: "../../pushed.git"}' "$P" > "$P.new" && mv "$P.new" "$P"
  git clone -q "$B" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main
  hand=$(git -C "$B" rev-parse refs/heads/main); serveeng "$SRC" 'stubland 7' || fail "card 7 did not land"
  out=$(loop run 2>&1) || fail "the run whose push the push URL of push.env refused at first failed: $out $(st 'select(.step == "push")')"
  l7=$(st 'select(.step == "landed") | .sha')
  [ "$(git -C "$B" rev-parse refs/heads/main)" = "$(git -C "$R" rev-parse refs/heads/main)" ] && git -C "$B" merge-base --is-ancestor "$hand" main \
    && git -C "$B" merge-base --is-ancestor "$l7" main && [ "$(cat "$R/c.txt")" = hand ] \
    || fail "where pushes go does not hold both the commit made by hand and the landing: $(git -C "$B" log --oneline main) $(st 'select(.step == "push")')"
  [ "$(st 'select(.step == "push" and .result == "fail") | .card' | wc -l)" = 0 ] && [ "$(git -C "$O" rev-parse refs/heads/main)" = "$was" ] \
    || fail "the push failed first, or went to the URL the remote fetches from: $(st 'select(.step == "push")')"
  loopend
}
