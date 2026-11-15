#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the fast lane.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || exec bash "$(dirname "$0")/../conveyor.test.sh" $(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0")
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: the fast lane is made outside the host file's lanesDir (or its default) or on another branch; a push from it,
# with --no-verify, --no-signed or a GIT_ALLOW_PROTOCOL of its own too, reaches any repository (through a rewrite, remote or push
# URL made before or after create too), or it loses main's own hooks; land or reset runs in a Foreman session (by its environment or by its marked session id), in a card's
# session or from the cards folder, or land-branch of a branch holding the lane's change under another name or tip,
# the lane's own branch renamed included, does; land does not land
# the lane's change as one card; reset moves a lane whose commits main does not hold, takes a name for --drop, or
# saves no ref of the old tip; the preview reviews something other than the lane's change, is not handed the earlier
# rounds' classes, takes a fix of whitespace alone for no new round, or goes on when a class is back after its
# whole-class round.
t_lane() {
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  setup "[$(issue 7 2026-01-01 area:billing)]"
  # A card's own session tries to land the lane: refused, whatever the lane.
  printf '%s\n' "bash $(printf %q "$SRC/conveyor.sh") lane fast land > \"\$STUB/card-land\" 2>&1; echo \"exit \$?\" >> \"\$STUB/card-land\"" 'echo two >> a.txt' > "$STUB/build"
  echo "$GO" > "$STUB/review.1"; loop run >/dev/null || fail "the card's run exited non-zero"
  grep -q 'refuses inside a card' "$STUB/card-land" && grep -qx 'exit 2' "$STUB/card-land" || fail "a card's session was not refused: $(cat "$STUB/card-land")"
  git -C "$R" push -q origin main
  # No host file: the lane would be beside the checkout.
  out=$(loop lane fast land 2>&1); [ $? = 2 ] && grep -qF "no fast lane of $R at $T/$CASE/main-fast-lane" <<<"$out" || fail "the default lane folder: $out"
}

# The lane of each case after t_lane: a main with a host file that names its lanes folder and its record, main's own
# pre-commit hook, a writable repository it could push to through a rewrite, and the lane made by create. Each part is
# a case of its own, so they run side by side; a part that goes on from a change in the lane, with main moved since
# and the lane rebased onto it, makes them itself first (lane_change).
lane_start() {
  # The Foreman's mark is the case's own: two parts side by side write and remove it.
  export XDG_CONFIG_HOME=$T/$CASE/config XDG_STATE_HOME=$T/$CASE/state; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  setup "[$(issue 7 2026-01-01 area:billing)]"
  L=$T/$CASE/lanes/main-fast-lane; HF=$XDG_CONFIG_HOME/conveyor/host.json
  jq -n --arg d "$T/$CASE/lanes" --arg m "$R" '{lanesDir: $d, records: [{repo: "other", main: "/srv/other"}, {repo: "alpha", main: $m}]}' > "$HF"
  printf '#!/bin/sh\necho ran >> "$STUB/precommit"\n' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
  # A writable repository the lane could push to, through a rewrite longer than any the lane could set.
  B=$T/$CASE/escape.git; git init -q --bare "$B" && git -C "$R" config "url.$B.pushInsteadOf" lane-target || fail "the escape repository"
  loop lane fast create >/dev/null || fail "create failed"
}
lane_change() {
  echo bee > "$L/b.txt"; git -C "$L" add b.txt; git -C "$L" commit -qm 'fix(tooling): lane change' || fail "a commit in the lane failed"
  git -C "$R" commit -q --allow-empty -m 'main moves' && git -C "$R" push -q origin main || fail "main's checkout can no longer push"
  git -C "$L" rebase -q main || fail "the lane does not rebase"
}
t_lanecreate() {
  lane_start
  [ "$(git -C "$L" symbolic-ref --short HEAD)" = fast-lane ] && [ "$(git -C "$L" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] || fail "the lane is not on fast-lane at main's head"
  # The Board reads each record's lanes from the host file: create writes the lane's folder into this checkout's
  # record, the one whose main it is, and leaves the rest of the file as it was.
  jq -e --arg l "$L" --arg d "$T/$CASE/lanes" --arg m "$R" '. == {lanesDir: $d, records: [{repo: "other", main: "/srv/other"}, {repo: "alpha", main: $m, lanes: {fast: {worktree: $l}}}]}' "$HF" >/dev/null \
    || fail "create did not write the lane's folder into its record of the host file: $(cat "$HF")"
  # A worktree at the lane's folder on another branch is no fast lane: create refuses it and changes nothing.
  git -C "$R" worktree remove --force "$L" && git -C "$R" worktree add -q -b unrelated "$L" main || fail "the unrelated worktree"
  out=$(loop lane fast create 2>&1); [ $? = 2 ] && grep -q 'nothing changed' <<<"$out" && [ "$(git -C "$L" symbolic-ref --short HEAD)" = unrelated ] \
    && [ -z "$(git -C "$L" config --worktree --get protocol.allow)" ] || fail "create took a worktree on another branch: $out"
  # A lane made by hand has no push refusal: the lane commands refuse it, and create seals it.
  git -C "$R" worktree remove --force "$L" && git -C "$R" branch -D -q unrelated && git -C "$R" worktree add -q "$L" fast-lane || fail "the lane could not be made by hand"
  out=$(loop lane fast land 2>&1); [ $? = 2 ] && grep -q 'could push' <<<"$out" || fail "an unsealed lane was used: $out"
  # A lane that is already there is written too, and a research lane its record names stays.
  jq --arg m "$R" '.records = [{repo: "other", main: "/srv/other"}, {repo: "alpha", main: $m, lanes: {research: {worktree: "~/r"}}}]' "$HF" > "$HF.t" && mv "$HF.t" "$HF"
  out=$(loop lane fast create) && grep -q 'already at' <<<"$out" || fail "a second create: $out"
  jq -e --arg l "$L" --arg m "$R" '.records == [{repo: "other", main: "/srv/other"}, {repo: "alpha", main: $m, lanes: {research: {worktree: "~/r"}, fast: {worktree: $l}}}]' "$HF" >/dev/null \
    || fail "create did not write the folder of a lane that was there into its record: $(cat "$HF")"
  # A record that spells this checkout another way (a trailing /., a link to it) is still its record: the path
  # names the same folder, and a create that compared the spellings would leave the Board without the lane.
  ln -s "$R" "$T/$CASE/alias" || fail "the link to the checkout"
  for sp in "$R/." "$T/$CASE/alias"; do
    jq --arg m "$sp" '.records = [{repo: "other", main: "/srv/other"}, {repo: "alpha", main: $m}]' "$HF" > "$HF.t" && mv "$HF.t" "$HF"
    out=$(loop lane fast create 2>&1) && ! grep -q 'no record of this checkout' <<<"$out" \
      && jq -e --arg l "$L" --arg m "$sp" '.records == [{repo: "other", main: "/srv/other"}, {repo: "alpha", main: $m, lanes: {fast: {worktree: $l}}}]' "$HF" >/dev/null \
      || fail "create did not find its record spelled $sp: $out; $(cat "$HF")"
  done
}
t_lanelock() {
  lane_start
  # Another lane's create holds the host file (its lock) and writes its own lane while this create waits: both
  # lanes stay written. Unlocked, this create would put back the file it read first, without the research lane.
  jq 'del(.records[1].lanes)' "$HF" > "$HF.t" && mv "$HF.t" "$HF"
  flock "$HF.lock" sh -c 'touch "$1.held"; until [ -e "$1.go" ]; do sleep 0.1; done' sh "$HF" & lk=$!
  until [ -e "$HF.held" ]; do sleep 0.1; done
  loop lane fast create > "$T/$CASE/create.out" 2>&1 & cr=$!
  # While the lock is held, create waits at it (its flock runs) and has neither ended nor written: a create that
  # took no lock would have done both.
  wait_until 'under "$cr" flock || ! kill -0 "$cr" 2>/dev/null'; kill -0 "$cr" 2>/dev/null && jq -e '.records[1] | has("lanes") | not' "$HF" >/dev/null \
    || { touch "$HF.go"; fail "create did not wait for the host file's lock: $(cat "$T/$CASE/create.out"; cat "$HF")"; }
  jq '.records[1].lanes.research.worktree = "~/r"' "$HF" > "$HF.t" && mv "$HF.t" "$HF"; touch "$HF.go"
  wait "$cr" || fail "a create that waited for the host file failed: $(cat "$T/$CASE/create.out")"
  wait "$lk"; rm -f "$HF.held" "$HF.go"
  jq -e --arg l "$L" '.records[1].lanes == {research: {worktree: "~/r"}, fast: {worktree: $l}}' "$HF" >/dev/null \
    || fail "a lane written while create waited was lost from the host file: $(cat "$HF")"
  # The host file cannot be written (nothing can be made in its folder): create fails and says so, it never reports
  # a lane the Board will not show.
  jq 'del(.records[1].lanes)' "$HF" > "$HF.t" && mv "$HF.t" "$HF" && cp "$HF" "$T/$CASE/host.before" && chmod a-w "$XDG_CONFIG_HOME/conveyor"
  out=$(loop lane fast create 2>&1); rc=$?; chmod u+w "$XDG_CONFIG_HOME/conveyor"
  [ "$rc" = 1 ] && grep -qF "could not be written into the host file $HF" <<<"$out" && ! grep -q 'already at' <<<"$out" && cmp -s "$HF" "$T/$CASE/host.before" \
    || fail "create with a host file that cannot be written (exit $rc): $out; $(cat "$HF")"
  # No record whose main is this checkout: nothing is written, and create says what the Board needs. A record named
  # for the checkout's folder (main) is another project's: a folder's name does not say whose checkout it is.
  jq '.records = [{repo: "other", main: "/srv/other"}, {repo: "main", main: "/srv/main"}]' "$HF" > "$HF.t" && mv "$HF.t" "$HF" && cp "$HF" "$T/$CASE/host.before"
  out=$(loop lane fast create 2>&1) && grep -q 'already at' <<<"$out" && grep -qF "no record of this checkout: the Board shows this lane once a record's lanes.fast.worktree names $L" <<<"$out" \
    && cmp -s "$HF" "$T/$CASE/host.before" || fail "create with no record of the checkout in the host file: $out; $(cat "$HF")"
}
t_lanepush() {
  lane_start
  echo bee > "$L/b.txt"; git -C "$L" add b.txt; git -C "$L" commit -qm 'fix(tooling): lane change' || fail "a commit in the lane failed"
  [ "$(cat "$STUB/precommit")" = ran ] || fail "main's own pre-commit hook did not run in the lane"
  # A remote added after create, with a push URL of its own, is refused too; so is a push that allows its own
  # transports, which outranks the lane's protocol.allow.
  git -C "$L" remote add escape "$B" && git -C "$L" remote set-url --push escape "$B" || fail "the escape remote"
  for to in 'origin fast-lane' 'lane-target HEAD:refs/heads/escape' 'escape HEAD:refs/heads/escape' "$B HEAD:refs/heads/escape"; do
    for nv in '' --no-verify '--no-verify --no-signed'; do
      for ap in '' file file:conveyor-fast-lane-refuses-push; do
        out=$(if [ -n "$ap" ]; then GIT_ALLOW_PROTOCOL=$ap git -C "$L" push $nv $to; else git -C "$L" push $nv $to; fi 2>&1) \
          && fail "a push ${nv:+$nv }${ap:+allowing $ap }to $to from the lane went through"
        grep -qE 'not allowed|invalid value for .push\.gpgsign.|remote-conveyor-fast-lane-refuses-push' <<<"$out" && ! git -C "$T/$CASE/origin" rev-parse -q --verify refs/heads/fast-lane >/dev/null \
          && ! git -C "$B" rev-parse -q --verify refs/heads/escape >/dev/null || fail "the lane's push $nv ${ap:+allowing $ap }to $to: $out"
      done
    done
  done
  git -C "$R" commit -q --allow-empty -m 'main moves' && git -C "$R" push -q origin main || fail "main's checkout can no longer push"
}
t_laneowner() {
  lane_start; lane_change
  # Owner only: refused, nothing recorded and the lane not moved, in a Foreman session, in a card's session, in the
  # cards folder; land-branch of the lane's branch too (t_laneownerbranch: of another branch that holds its change).
  # Revision syntax names no branch, so it never reaches the lane's tip.
  n=$(cat "$ST/cards.jsonl" 2>/dev/null | wc -l); tip=$(git -C "$L" rev-parse HEAD); mkdir -p "$T/$CASE/cards/c2-2"
  # The Foreman claimed by /conveyor-belt:foreman has no CONVEYOR_FOREMAN: its mark names its session, whose commands
  # Claude Code gives CLAUDE_CODE_SESSION_ID.
  mkdir -p "$XDG_STATE_HOME/conveyor/foreman" && echo "s1 2026-01-01T00:00:00Z" > "$XDG_STATE_HOME/conveyor/foreman/session"
  for r in 'fast-lane~0' 'fast-lane^{commit}' '@{-1}'; do
    out=$(CONVEYOR_FOREMAN=1 loop land-branch "$r" 2>&1); [ $? = 2 ] && grep -qF "no branch $r to land" <<<"$out" || fail "land-branch $r with a Foreman session: $out"
  done
  for c in 'lane fast land' 'lane fast reset' 'land-branch fast-lane'; do
    for v in CONVEYOR_FOREMAN=1 CLAUDE_CODE_SESSION_ID=s1 CONVEYOR_CARD=c2-2 cards; do
      out=$(if [ "$v" = cards ]; then cd "$T/$CASE/cards/c2-2" && loop $c; else export "$v"; loop $c; fi 2>&1)
      [ $? = 2 ] && grep -q "the owner's alone" <<<"$out" || fail "$c with $v was not refused: $out"
    done
  done
  rm "$XDG_STATE_HOME/conveyor/foreman/session"
  [ "$(cat "$ST/cards.jsonl" 2>/dev/null | wc -l)" = "$n" ] && [ "$(git -C "$L" rev-parse HEAD)" = "$tip" ] || fail "a refused land or reset changed something"
}
t_laneownerbranch() {
  lane_start; lane_change
  # Owner only, as t_laneowner: land-branch of another branch that holds the lane's change is refused too: one at its
  # tip, one with an empty commit on top, its change squashed onto main as one commit, and one commit on main with its
  # change and another (the lane's new file grown by a line, and a file of its own).
  n=$(cat "$ST/cards.jsonl" 2>/dev/null | wc -l); tip=$(git -C "$L" rev-parse HEAD); mkdir -p "$T/$CASE/cards/c2-2"; git -C "$R" branch -q alias fast-lane
  git -C "$R" branch -q ontop "$(git -C "$R" commit-tree 'fast-lane^{tree}' -p fast-lane -m ontop)" \
    && git -C "$R" branch -q squashed "$(git -C "$R" commit-tree 'fast-lane^{tree}' -p main -m squashed)" \
    && git -C "$R" branch -q mixed "$(printf 'bee\nmore\n' > "$T/$CASE/b" && GIT_INDEX_FILE=$T/$CASE/ix git -C "$R" read-tree main && GIT_INDEX_FILE=$T/$CASE/ix git -C "$R" update-index --add --cacheinfo "100644,$(git -C "$R" hash-object -w "$T/$CASE/b"),b.txt" --cacheinfo "100644,$(git -C "$R" hash-object -w "$T/$CASE/b"),c.txt" && git -C "$R" commit-tree "$(GIT_INDEX_FILE=$T/$CASE/ix git -C "$R" write-tree)" -p main -m mixed)" || fail "the branches that hold the lane's change"
  # The Foreman claimed by /conveyor-belt:foreman has no CONVEYOR_FOREMAN: its mark names its session, whose commands
  # Claude Code gives CLAUDE_CODE_SESSION_ID.
  mkdir -p "$XDG_STATE_HOME/conveyor/foreman" && echo "s1 2026-01-01T00:00:00Z" > "$XDG_STATE_HOME/conveyor/foreman/session"
  for c in 'land-branch alias' 'land-branch ontop' 'land-branch squashed' 'land-branch mixed'; do
    for v in CONVEYOR_FOREMAN=1 CLAUDE_CODE_SESSION_ID=s1 CONVEYOR_CARD=c2-2 cards; do
      out=$(if [ "$v" = cards ]; then cd "$T/$CASE/cards/c2-2" && loop $c; else export "$v"; loop $c; fi 2>&1)
      [ $? = 2 ] && grep -q "the owner's alone" <<<"$out" || fail "$c with $v was not refused: $out"
    done
  done
  # The lane's own branch renamed, and a branch with an empty commit on its tip: still the lane's change, found from
  # the lane's worktree.
  git -C "$L" branch -m renamed && git -C "$R" branch -q -D ontop && git -C "$R" branch -q ontop "$(git -C "$R" commit-tree 'renamed^{tree}' -p renamed -m ontop)" \
    || fail "the renamed lane"
  for c in renamed ontop; do
    out=$(CONVEYOR_FOREMAN=1 loop land-branch $c 2>&1); [ $? = 2 ] && grep -q "the owner's alone" <<<"$out" || fail "land-branch $c of the renamed lane was not refused: $out"
  done
  git -C "$L" branch -m fast-lane || fail "the lane's branch could not be named back"
  # Another session than the marked one is the owner's.
  out=$(CLAUDE_CODE_SESSION_ID=s2 loop lane fast reset 2>&1); grep -q "the owner's alone" <<<"$out" && fail "a session the mark does not name was refused: $out"
  rm "$XDG_STATE_HOME/conveyor/foreman/session"
  [ "$(cat "$ST/cards.jsonl" 2>/dev/null | wc -l)" = "$n" ] && [ "$(git -C "$L" rev-parse HEAD)" = "$tip" ] || fail "a refused land or reset changed something"
}
t_lanepreview() {
  lane_start; lane_change
  # The preview: the lane's change, reviewed by the card reviewer with the class rule; a class back once is a repeat
  # (exit 0), back after that round a stop (exit 3), a rebase onto a newer main in between included. Each round is
  # handed the earlier rounds' classes. An UNPROVEN or NEW CARD line never counts toward a repeat, however it reads.
  cat > "$STUB/codex" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" != debug ] || exit 1 # `codex debug models` (the host's report) is no review: it lists none
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
echo x >> "$STUB/reviews"; n=$(wc -l < "$STUB/reviews"); cat > "$STUB/prompt.$n"; git diff --cached --name-only > "$STUB/staged.$n"; cat "$STUB/review.$n" > "$out" || exit 1
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":7}}'
EOF
  for i in 1 2 3; do printf '%s\n' '[P1] b.txt:1 wrong word. Proof: b.txt reads bee class: Wrong word in a file.' \
    'UNPROVEN: possible P1 in foo.py:1 class: missing validation' 'NEW CARD: possible P1 in bar.py:1 class: missing check' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.$i"; done
  out=$(cd "$L" && loop lane fast review) || fail "preview 1: $out"
  grep -qF '[P1] b.txt:1 wrong word' <<<"$out" && ! grep -q CLASS <<<"$out" && [ "$(cat "$STUB/staged.1")" = b.txt ] || fail "preview 1 is not the lane's change: $out"
  grep -qF 'Review the staged change' "$STUB/prompt.1" && grep -qF 'class: <the kind of mistake' "$STUB/prompt.1" && ! grep -q 'Classes earlier' "$STUB/prompt.1" || fail "preview 1's instructions: $(cat "$STUB/prompt.1")"
  # A fix that changes only whitespace is a round of its own.
  echo ' bee' > "$L/b.txt"; git -C "$L" commit -qam 'fix(tooling): another word'
  # Bug: with the rule "visible changes need the owner's yes" off, the preview still asks about the approval line.
  grep -q 'Visible change approved:' "$STUB/prompt.1" || fail "with the rule on, preview 1 does not speak of the approval line"
  loop control rules visible=off >/dev/null || fail "control rules visible=off was refused"
  out=$(cd "$L" && loop lane fast review) && grep -q '^CLASS REPEAT' <<<"$out" && grep -qx -- '- wrong word in a file' "$STUB/prompt.2" || fail "preview 2 is not a repeat: $out"
  ! grep -q 'Visible change approved:' "$STUB/prompt.2" && grep -qF 'USER-VISIBLE: yes: <one sentence' "$STUB/prompt.2" || fail "with the rule off, preview 2 still asks about the approval line"
  loop control rules visible=on >/dev/null
  grep -qxE -- '- missing (validation|check)' "$STUB/prompt.2" && fail "an UNPROVEN or NEW CARD class was handed on: $(cat "$STUB/prompt.2")"
  echo bez > "$L/b.txt"; git -C "$L" commit -qam 'fix(tooling): a third word'
  git -C "$R" commit -q --allow-empty -m 'main moves again' && git -C "$L" rebase -q main || fail "the lane does not rebase onto the newer main"
  out=$(cd "$L" && loop lane fast review); [ $? = 3 ] && grep -q '^CLASS STOP' <<<"$out" || fail "preview 3, after a rebase, did not stop: $out"
  ! grep -q '^CLASS.*missing' <<<"$out" || fail "an UNPROVEN or NEW CARD line counted as a class: $out"
  [ "$(git -C "$R" worktree list | wc -l)" = 2 ] || fail "a preview left its worktree: $(git -C "$R" worktree list)"
  # Reset before the landing: the lane's commits are not on main, so nothing moves.
  out=$(loop lane fast reset 2>&1); [ $? = 2 ] && grep -q 'not patch-equivalent' <<<"$out" && [ "$(git -C "$L" rev-parse HEAD)" != "$(git -C "$R" rev-parse main)" ] \
    || fail "reset of an unlanded lane: $out"
  # Land: one card, one commit on main with the lane's change; the lane is not moved.
  echo "$GO" > "$STUB/review.4"; tip=$(git -C "$L" rev-parse HEAD); at=$(git -C "$R" rev-parse main)
  out=$(cd "$L" && loop lane fast land) || fail "land: $out"
  grep -q 'branch fast-lane: landed' <<<"$out" && [ "$(cat "$R/b.txt")" = bez ] && [ "$(git -C "$R" rev-parse main~1)" = "$at" ] && [ "$(git -C "$L" rev-parse HEAD)" = "$tip" ] \
    || fail "the lane did not land as one commit: $out"
  # Its three commits landed as one, which is no single one of theirs: reset wants --drop with the exact tip, as an id.
  out=$(loop lane fast reset 2>&1); [ $? = 2 ] && grep -qF -- "--drop $tip" <<<"$out" || fail "reset after a squashed landing: $out"
  out=$(loop lane fast reset --drop HEAD 2>&1); [ $? = 2 ] && [ "$(git -C "$L" rev-parse HEAD)" = "$tip" ] || fail "--drop took a name: $out"
  out=$(loop lane fast reset --drop "$tip") || fail "reset --drop: $out"
  [ "$(git -C "$L" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] && [ "$(git -C "$L" symbolic-ref --short HEAD)" = fast-lane ] \
    && [ "$(git -C "$R" for-each-ref --format='%(objectname)' refs/lane-reset/)" = "$tip" ] && grep -q 'after a fetch of origin' <<<"$out" || fail "reset --drop: $out"
  # The lane's next change starts with no classes from the landed one.
  [ ! -e "$(git -C "$L" rev-parse --absolute-git-dir)/conveyor-classes" ] || fail "reset kept the landed change's class history"
}
t_lanesingle() {
  lane_start
  # A single commit lands as itself: reset needs no --drop.
  echo sea > "$L/c.txt"; git -C "$L" add c.txt; git -C "$L" commit -qm 'fix(tooling): one commit'; echo "$GO" > "$STUB/review.1"
  out=$(cd "$L" && loop lane fast land) || fail "the land: $out"
  out=$(loop lane fast reset) && grep -q 'patch-equivalent to one on main' <<<"$out" && [ "$(git -C "$L" rev-parse HEAD)" = "$(git -C "$R" rev-parse main)" ] || fail "reset after a landing: $out"
}
