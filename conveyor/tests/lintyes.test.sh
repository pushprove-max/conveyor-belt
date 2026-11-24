#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 240
# Engine cases: the stop for the owner's yes on a change of lint policy (lintpolicy() and lintyes(),
# conveyor/lib/lint.sh, and the stop in card()): what is policy, the stop, its approval line, a yes that covers one
# policy diff, one stop with a visible change, and the rule Lint check off.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The lint field of the lintpolicy() cases: .lintrc and the exempt file .size-exempt (the file the ratchet: false
# command names) are policy.
POLICY='{"commands": [{"files": ["*.txt"], "run": "true"}, {"files": [".size-exempt"], "run": "true", "ratchet": false}], "policy": [".lintrc", ".size-exempt"]}'
# What lintpolicy() prints for card c7's staged change ($FXWT, made by fx_wt), in $T/$CASE/run.out.
policyof() { fx_in "lintpolicy \"\$FXWT\" \"\$(git -C \"\$FXWT\" rev-parse HEAD)\" '$POLICY'"; [ "$RC" = 0 ] || fail "lintpolicy failed: $(cat "$T/$CASE/run.out")"; }

# Bugs: a change that only removes lines from the exempt file (it only tightens) stops for the yes; a change of a
# file that is no policy (a.txt) is taken for policy. lintpolicy() prints nothing, so the card does not stop.
t_lintpolicytighten() {
  setup '[]'
  # The lint field given lintpolicy() is one the pack check takes: an exempt file the pack cannot name proves nothing.
  jq --argjson l "$POLICY" '.lint = $l' "$R/.conveyor/project.json" > "$STUB/policy.json" \
    && bash "$SRC/lib/pack.sh" check "$STUB/policy.json" || fail "the pack check refused the cases' lint field"
  fx_wt 'printf "a.sh\n" > .size-exempt && echo two >> a.txt' .size-exempt $'a.sh\nb.sh' .lintrc old
  policyof
  [ ! -s "$T/$CASE/run.out" ] || fail "a tightening of the exempt file or a change of a.txt was taken for lint policy: $(cat "$T/$CASE/run.out")"
}
# Bugs: a policy file, an exempt file that gets a line (it loosens), or the pack's lint field is not listed, so its
# change lands without the owner's yes. Each is listed, after the hash of the diff. (Main's commit has no pack, which
# the fixture's .gitignore leaves out, so the pack the change adds changes the lint field.)
t_lintpolicylisted() {
  setup '[]'
  fx_wt 'echo c.sh >> .size-exempt && echo new > .lintrc && echo "{\"lint\": {\"commands\": []}}" > .conveyor/project.json && git add -f .conveyor/project.json' \
    .size-exempt a.sh .lintrc old
  policyof
  [ "$(sed -n '2,$p' "$T/$CASE/run.out" | paste -sd' ')" = '.conveyor/project.json .lintrc .size-exempt' ] && [[ $(head -n 1 "$T/$CASE/run.out") =~ ^[0-9a-f]{40,64}\ \{\"\.lintrc\":[0-9]+,\"\.size-exempt\":[0-9]+\}$ ]] \
    || fail "the policy files or their hash and widths (one for each of .lintrc and .size-exempt, by path) were not listed: $(cat "$T/$CASE/run.out")"
}
# Bug (R268): a policy file whose name holds a newline was read as two paths, neither of them the file, so its diff was
# hashed as empty: the hash stayed the same when the file changed, and an owner's yes to one content covered another.
# The file is listed whole, and a change to its content gives another hash.
t_lintpolicynewline() {
  local p=$'pol/a\nb' l='{"commands": [{"files": ["*.txt"], "run": "true"}], "policy": ["pol/*"]}' h1
  setup '[]'
  fx_wt 'mkdir -p pol && printf "one\n" > "pol/a
b"' keep.txt one
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'lintpolicy "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" '"'$l'"
  [ "$RC" = 0 ] && [ "$(sed -n '2,$p' "$T/$CASE/run.out")" = "$p" ] || fail "lintpolicy did not list the policy file $p whole (exit $RC): $(cat "$T/$CASE/run.out")"
  h1=$(head -n 1 "$T/$CASE/run.out")
  printf 'two\n' > "$FXWT/$p" && git -C "$FXWT" add -A || fail "the card's second change"
  # shellcheck disable=SC2016 # expanded in fx_in's shell
  fx_in 'lintpolicy "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" '"'$l'"
  [ "$RC" = 0 ] && [ "$(head -n 1 "$T/$CASE/run.out")" != "$h1" ] || fail "a change to the content of the policy file $p kept its hash $h1: $(cat "$T/$CASE/run.out")"
}
# Bug (R269): the hash kept the @@ headers' line numbers and the context lines, so a line main added directly above
# the same .lintrc edit gave another hash, and the owner's yes to that edit no longer covered it.
t_lintpolicymoved() {
  local h1
  setup '[]'
  fx_wt 'printf "a\nb\nc\nd\nE\n" > .lintrc' .lintrc "$(printf 'a\nb\nc\nd\ne')"
  policyof; h1=$(head -n 1 "$T/$CASE/run.out")
  (cd "$FXWT" && git reset -q --hard && printf 'a\nb\nc\nd\n# note\ne\n' > .lintrc && git commit -qam main \
    && printf 'a\nb\nc\nd\n# note\nE\n' > .lintrc && git add -A) || fail "main's line above the edit and the same edit"
  policyof
  [ -n "$h1" ] && [ "$(head -n 1 "$T/$CASE/run.out")" = "$h1" ] \
    || fail "the .lintrc edit e -> E hashed $h1 before main added '# note' directly above it and $(head -n 1 "$T/$CASE/run.out") after"
}
# Bug (R269): an edit after a line the file holds twice (`done`) hashed its @@ line numbers and the base blob, so a
# line main added at the top of the file gave the same .lintrc edit another hash, and the owner's yes no longer covered it.
t_lintpolicytwice() {
  local h1
  setup '[]'
  fx_wt 'printf "a\ndone\nb\ndone\n# why\nc\n" > .lintrc' .lintrc "$(printf 'a\ndone\nb\ndone\nc')"
  policyof; h1=$(head -n 1 "$T/$CASE/run.out")
  (cd "$FXWT" && git reset -q --hard && printf 'top\na\ndone\nb\ndone\nc\n' > .lintrc && git commit -qam main \
    && printf 'top\na\ndone\nb\ndone\n# why\nc\n' > .lintrc && git add -A) || fail "main's line at the top and the same edit"
  policyof
  [ -n "$h1" ] && [ "$(head -n 1 "$T/$CASE/run.out")" = "$h1" ] \
    || fail "the .lintrc edit adding '# why' after the second 'done' hashed $h1 before main added 'top' at line 1 and $(head -n 1 "$T/$CASE/run.out") after"
}
# Bug (R269): at the end of the file the widened place is cut short, so `exit 0` added after the first or after the
# last of a `done` pair (with another pair above) wrote the same lines and hashed the same: the owner's yes to one
# covered the other. Each gives its own hash.
t_lintpolicyend() {
  local h1 b='done\ndone\nx\n# end\ndone\ndone\n'
  setup '[]'
  fx_wt "printf 'done\ndone\nx\n# end\ndone\nexit 0\ndone\n' > .lintrc" .lintrc "$(printf "$b")"
  policyof; h1=$(head -n 1 "$T/$CASE/run.out")
  printf "${b}exit 0\n" > "$FXWT/.lintrc" && git -C "$FXWT" add -A || fail "the edit after the last 'done'"
  policyof
  [ -n "$h1" ] && [ "$(head -n 1 "$T/$CASE/run.out")" != "$h1" ] \
    || fail "the .lintrc edit adding 'exit 0' after line 5 and after line 6 (the last 'done' pair of '$b') both hashed $h1"
}
# Bug: with the @@ line numbers left out, the same edit at two places with the same context lines hashed the same,
# so the owner's yes to one .lintrc edit covered the other. Each place gives its own hash.
t_lintpolicyplace() {
  local h1 x='x\nx\nx\n'
  setup '[]'
  fx_wt "printf '${x}M\n${x}${x}m\n${x}' > .lintrc" .lintrc "$(printf "${x}m\n${x}${x}m\n${x}")"
  policyof; h1=$(head -n 1 "$T/$CASE/run.out")
  printf "${x}m\n${x}${x}M\n${x}" > "$FXWT/.lintrc" && git -C "$FXWT" add -A || fail "the edit at the second place"
  policyof
  [ -n "$h1" ] && [ "$(head -n 1 "$T/$CASE/run.out")" != "$h1" ] \
    || fail "the .lintrc edit m -> M at line 4 and at line 11 (3 lines of x around each) both hashed $h1"
}
# Bug: an edit after a line the file holds twice (`done`) hashed with context lines, and when main changed the other
# `done` (an inline comment) the place was unique, the context lines were dropped and the same edit at the same place
# hashed another way: the owner's yes no longer covered it. Widened at least as far as the approved hash, it hashes the same.
t_lintpolicyunique() {
  local h1
  setup '[]'
  fx_wt 'printf "a\ndone\n# why\nb\ndone\nc\n" > .lintrc' .lintrc "$(printf 'a\ndone\nb\ndone\nc')"
  policyof; h1=$(head -n 1 "$T/$CASE/run.out")
  (cd "$FXWT" && git reset -q --hard && printf 'a\ndone\nb\ndone # end\nc\n' > .lintrc && git commit -qam main \
    && printf 'a\ndone\n# why\nb\ndone # end\nc\n' > .lintrc && git add -A) || fail "main's comment on the other done and the same edit"
  fx_in "lintpolicy \"\$FXWT\" \"\$(git -C \"\$FXWT\" rev-parse HEAD)\" '$POLICY' '${h1#* }'"
  [ "$RC" = 0 ] && [ -n "$h1" ] && [ "$(head -n 1 "$T/$CASE/run.out")" = "$h1" ] \
    || fail "the .lintrc edit adding '# why' after the first 'done' hashed '$h1' before main added '# end' to the other 'done' and '$(head -n 1 "$T/$CASE/run.out")' after, given the width ${h1#* } (exit $RC)"
}
# Bug: the hash named an edit by how many copies of its lines came before it, so when main added a copy of the edited
# rule above it, an edit of that new copy hashed as the approved edit of the old one, and the owner's yes covered a
# change to another rule. With the rule now in two places, the edit of the new copy gets another hash.
t_lintpolicycopy() {
  local h1
  setup '[]'
  fx_wt 'printf "a\nrule 20\nb\n" > .lintrc' .lintrc "$(printf 'a\nrule 30\nb')"
  policyof; h1=$(head -n 1 "$T/$CASE/run.out")
  (cd "$FXWT" && git reset -q --hard && printf 'rule 30\nc\na\nrule 30\nb\n' > .lintrc && git commit -qam main \
    && printf 'rule 20\nc\na\nrule 30\nb\n' > .lintrc && git add -A) || fail "main's copy of the rule above and the edit of that copy"
  policyof
  [ -n "$h1" ] && [ "$(head -n 1 "$T/$CASE/run.out")" != "$h1" ] \
    || fail "the .lintrc edit 'rule 30' -> 'rule 20' of line 4, and of line 1 (a copy main added above it), both hashed $h1"
}
# Bug (issue 1575): every policy file was hashed at the widest width any one file needed, so a file with no repeated
# lines was hashed with the lines next to its edit, and a main edit of one of them asked for the owner's yes again.
# Each file keeps its own width, by its path: with the widths kept in order, a file a retry adds before the others
# (.alint) took .lintrc's width 1, and was hashed with its own neighbour lines again. A kept width of one number (an
# approval kept before then) is every file's, as that approval hashed every file at it.
t_lintpolicywidths() {
  local p h
  setup '[]'
  p=$(jq -c '.policy += [".alint"]' <<<"$POLICY")
  fx_wt 'printf "a\ndone\n# why\nb\ndone\nc\n" > .lintrc && printf "x\ny\nz\nv\nw\n" > .size-exempt && printf "k\nl\nm\nn\n" > .alint' \
    .lintrc "$(printf 'a\ndone\nb\ndone\nc')" .size-exempt "$(printf 'x\ny\nz\nw')" .alint "$(printf 'k\nl\nn')"
  fx_in "lintpolicy \"\$FXWT\" \"\$(git -C \"\$FXWT\" rev-parse HEAD)\" '$p' '{\".lintrc\":1,\".size-exempt\":0}'"; h=$(head -n 1 "$T/$CASE/run.out")
  [ "$RC" = 0 ] && [ "${h#* }" = '{".alint":0,".lintrc":1,".size-exempt":0}' ] \
    || fail "the kept widths {\".lintrc\":1,\".size-exempt\":0} with .alint added gave the widths '${h#* }', not .alint 0 (exit $RC)"
  fx_in "lintpolicy \"\$FXWT\" \"\$(git -C \"\$FXWT\" rev-parse HEAD)\" '$p' 1"; h=$(head -n 1 "$T/$CASE/run.out")
  [ "$RC" = 0 ] && [ "${h#* }" = '{".alint":1,".lintrc":1,".size-exempt":1}' ] \
    || fail "the kept width 1 (an approval kept before each file had its own) did not widen every file: '${h#* }' (exit $RC)"
}

# Card #7 on a main whose pack makes .lintrc lint policy, with a lint command that passes: its build runs <build>
# and notes `build` in $STUB/did; review 1 is <review> (a GO by default).
yessetup() { # <build> [<review>]
  setup "[$(issue 7 2026-01-01)]"
  tune '.lint = {commands: [{files: ["*.txt"], run: "true"}], policy: [".lintrc"]}'
  printf '%s\n' "${2:-$GO}" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  printf '%s\n' 'echo build >> "$STUB/did"' "$1" > "$STUB/build"
}
yesdid() { paste -sd' ' "$STUB/did" 2>/dev/null; }
yessteps() { st 'select(.issue == 7) | "\(.step) \(.result) \(.reason // "" | .[0:200])"' | paste -sd, -; }
# The reasons of #7's blocked lines, those `retry` moved out of the card records first.
blocks() { cat "$ST/retried.jsonl" "$ST/cards.jsonl" 2>/dev/null | jq -r 'select(.issue == 7 and .step == "blocked") | .reason'; }
approve() { issue 7 2026-01-01 | jq -c --arg a "${1:-}" '[.body += "\n\(if $a == "" then "" else $a + "\n" end)\nVisible change approved: Dana 2026-01-02 (yes)\n"]' > "$STUB/issues.json"; } # [another line of the ask]
# Named apart from lib.sh's landed(), which the runner's other case files call after sourcing this one.
yeslanded() { [ "$(st 'select(.issue == 7 and .step == "landed") | .sha')" = "$(git -C "$R" rev-parse HEAD)" ]; }

# Bugs: a change of a lint.policy file lands on its review's GO with no yes; a retry with no approval line lands it,
# or builds it again; the approval line does not land the kept patch, with no build and no review, when the rule
# "visible changes need the owner's yes" is off.
t_lintyes() {
  yessetup 'echo strict > .lintrc; echo two >> a.txt'
  # loop: the stop, the kept patch, retry, the approval line and the landing are a card's path over turns, carried in the records and the kept folder; no one engine function holds that path
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(blocks)" = "lint policy: needs Dana's yes: it changes lint policy: .lintrc" ] && ! yeslanded \
    || fail "the policy change did not stop for Dana's yes naming .lintrc: $(blocks)"
  # Bug: health lists the stop as a failed card (blocked), so the Board's Approve and Decline, which look in waiting,
  # refuse it, and the Board's Needs you shows it as failed. It is in waiting alone, in both.
  loop health | jq -e '(.waiting | any(.issue == 7)) and (.blocked | all(.issue != 7))' > /dev/null \
    || fail "health does not list the policy stop as waiting for the yes: $(loop health | jq -c '{waiting, blocked}')"
  loop snapshot --fresh | jq -e '.needsYou | (.waiting | any(.issue == 7 and .sentence == "it changes lint policy: .lintrc")) and (.blocked | all(.issue != 7))' > /dev/null \
    || fail "the snapshot does not list the policy stop as waiting for the yes: $(loop snapshot | jq -c '.needsYou | {waiting, blocked}')"
  # loop: as above, a retry with no approval line is a turn of its own
  loop retry 7 > /dev/null && loop run > /dev/null || fail "the retry with no approval line exited non-zero"
  [ "$(blocks | sort -u)" = "lint policy: needs Dana's yes: it changes lint policy: .lintrc" ] && [ "$(blocks | wc -l)" = 2 ] \
    && [ "$(yesdid)" = build ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] && ! yeslanded \
    || fail "a retry with no approval line did not stop again with no build and no review: $(yesdid); $(yessteps)"
  approve; loop control rules visible=off > /dev/null || fail "control rules visible=off was refused"
  # loop: as above, the turn that finds the approval line gives the card back by itself
  loop run > /dev/null || fail "the run after the approval line exited non-zero"
  yeslanded && [ "$(yesdid)" = build ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(git -C "$R" show HEAD:.lintrc)" = strict ] \
    || fail "the approved policy change did not land its kept patch with no build and no review: $(yesdid); $(yessteps)"
}
# Bug (issue 1575): every policy file was hashed at the one width the widest needed. .lintrc's edit after a repeated
# `done` needs width 1, so .size-exempt's added line was hashed with its neighbour `y`: when main edited `y` after the
# stop, cardready() hashed the approved change another way and asked for the yes again. The stop keeps each file's
# width by its path, and cardready() hashes each file at least at it: main also made the other `done` unique, so
# .lintrc kept its width only through the kept widths.
t_lintyeswidths() {
  # The build adds its lines in place, so the session that brings the kept patch onto main (main's edit is in the
  # patch's context lines) keeps main's edits.
  yessetup 'awk '\''NR == 2 { print; print "# why"; next } 1'\'' .lintrc > .l && mv .l .lintrc
    awk '\''NR == 3 { print; print "v"; next } 1'\'' .size-exempt > .s && mv .s .size-exempt'
  tune '.lint.policy = [".lintrc", ".size-exempt"]'
  printf 'a\ndone\nb\ndone\nc\n' > "$R/.lintrc" && printf 'x\ny\nz\nw\n' > "$R/.size-exempt" \
    && git -C "$R" add .lintrc .size-exempt && git -C "$R" commit -qm "policy files" || fail "main's policy files"
  # loop: the stop, its kept widths, main's edit, the approval line and the landing through cardready() are turns of a card's path
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(blocks)" = "lint policy: needs Dana's yes: it changes lint policy: .lintrc, .size-exempt" ] \
    && jq -e '.policy | test(" [{]\".lintrc\":1,\".size-exempt\":0[}]$")' "$ST"/kept/*/*.body > /dev/null \
    || fail "the stop did not keep the widths .lintrc 1 and .size-exempt 0: $(blocks); $(cat "$ST"/kept/*/*.body 2>&1)"
  printf 'a\ndone\nb\ndone # end\nc\n' > "$R/.lintrc" && printf 'x\ny # main\nz\nw\n' > "$R/.size-exempt" \
    && git -C "$R" commit -qam "main edits y and the other done" || fail "main's edits"
  approve
  # loop: as above, the turn that finds the approval line lands the kept patch on the newer main
  loop run > /dev/null || fail "the run after the approval line exited non-zero"
  yeslanded && [ "$(blocks | wc -l)" = 1 ] && [ "$(git -C "$R" show HEAD:.size-exempt)" = "$(printf 'x\ny # main\nz\nv\nw')" ] \
    || fail "after main edited .size-exempt's y and .lintrc's other done, the approved change did not land: $(blocks | paste -sd'|'); $(yessteps)"
}
# Bug: a yes covers more than the policy diff it was given for: a session after the yes (the issue's ask changed, so
# the kept patch gets one) edits .lintrc again, and the card lands on the old yes. It stops again.
t_lintyesagain() {
  yessetup 'echo strict >> .lintrc; echo two >> a.txt'
  # loop: the yes, the next card's session and its stop are turns of a card's path, as in t_lintyes
  loop run > /dev/null || fail "run exited non-zero"
  approve 'Keep a.txt short.'
  # loop: as above
  loop run > /dev/null || fail "the run after the approval line exited non-zero"
  [ "$(yesdid)" = 'build build' ] && [ "$(blocks | wc -l)" = 2 ] && [ "$(blocks | tail -n 1)" = "lint policy: needs Dana's yes: it changes lint policy: .lintrc" ] && ! yeslanded \
    || fail "a policy file edited after the yes did not stop the card again: $(yesdid); $(yessteps)"
}
# Bug: a card whose change is visible and changes lint policy stops twice, or one approval does not land it. It
# stops once, its reason naming the policy file, and one approval line lands its kept patch.
t_lintyesvisible() {
  yessetup 'echo strict > .lintrc; mkdir -p web; echo pay >> web/pay.ts' $'USER-VISIBLE: yes: guests see a new Pay button\nVERDICT: GO'
  # loop: the stop, the approval line and the landing are turns of a card's path, as in t_lintyes
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(blocks)" = "visible to customers or staff: needs Dana's yes: guests see a new Pay button; it also changes lint policy: .lintrc" ] \
    || fail "the visible policy change did not stop once naming both: $(blocks)"
  # Bug: the Board shows the reviewer's sentence alone, so the policy file the yes covers is hidden.
  loop snapshot --fresh | jq -e '.needsYou.waiting | any(.issue == 7 and .sentence == "guests see a new Pay button; it also changes lint policy: .lintrc")' > /dev/null \
    || fail "the snapshot does not name the policy file beside the visible change: $(loop snapshot | jq -c '.needsYou.waiting')"
  approve
  # loop: as above
  loop run > /dev/null || fail "the run after the approval line exited non-zero"
  yeslanded && [ "$(blocks | wc -l)" = 1 ] && [ "$(yesdid)" = build ] || fail "one approval did not land the visible policy change: $(yesdid); $(yessteps)"
}
# Bug: with the rule on visible changes off, a visible change that changes lint policy lands with no yes, or stops
# for its visible change in place of the policy.
t_lintyesvisibleoff() {
  yessetup 'echo strict > .lintrc; mkdir -p web; echo pay >> web/pay.ts' $'USER-VISIBLE: yes: guests see a new Pay button\nVERDICT: GO'
  loop control rules visible=off > /dev/null || fail "control rules visible=off was refused"
  # loop: the stop is card()'s, after a build and a review that says the change is visible
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(blocks)" = "lint policy: needs Dana's yes: it changes lint policy: .lintrc" ] || fail "the policy change did not stop for the policy alone: $(blocks)"
}
# Bug: for such a stop, the Board shows the reviewer's visible sentence in place of the reason, hiding the policy file
# the yes is for. Card 14 has the two records the case above writes: a review that says the change is visible, and
# the stop for the policy.
t_lintyesvisibleoffboard() { snapshotstart
  card 14 "$(date -u +%F)" picked worktree brief build 'review:GO:{"visible":"yes: guests see a new Pay button"}' \
    'blocked:blocked:{"reason":"lint policy: needs Dana'"'"'s yes: it changes lint policy: .lintrc"}'
  loop snapshot --fresh | jq -e '.needsYou.waiting | any(.issue == 14 and .sentence == "it changes lint policy: .lintrc")' > /dev/null \
    || fail "the snapshot hides the policy file: $(loop snapshot | jq -c '.needsYou.waiting')"
}
# Bug: with the rule Lint check off, a policy change still stops for the yes. It lands on its GO.
t_lintyesoff() {
  yessetup 'echo strict > .lintrc; echo two >> a.txt'
  jq '.rules.lint = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the rule off"
  # loop: only a whole card run shows that card() does not stop it between its review and its landing
  loop run > /dev/null || fail "run exited non-zero"
  yeslanded && [ -z "$(blocks)" ] || fail "a policy change stopped with the rule Lint check off: $(blocks)"
}
# Bug: once the owner turns the rule Lint check off, `retry` of a card stopped for its policy change alone says its next
# card stops again for the yes, while that card lands the kept patch. It says the card lands, and the card does, with
# no build and no review.
t_lintyesretryoff() {
  local out
  yessetup 'echo strict > .lintrc; echo two >> a.txt'
  # loop: the stop, the rule's change, retry and the landing are a card's path over turns, as in t_lintyes
  loop run > /dev/null || fail "run exited non-zero"
  loop control rules lint=off > /dev/null || fail "control rules lint=off was refused"
  out=$(loop retry 7) || fail "the retry exited non-zero: $out"
  [[ $out == *"the rule Lint check is off, so its lint policy change waits for no yes"* ]] || fail "retry did not say the card lands with Lint check off: $out"
  # loop: as above
  loop run > /dev/null || fail "the run after the retry exited non-zero"
  yeslanded && [ "$(yesdid)" = build ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] \
    || fail "the kept policy change did not land with no build and no review after Lint check was turned off: $(yesdid); $(yessteps)"
}

# Bug (R72): the yes covers one policy diff, checked only at the landing gate (cardready()). An approved retry's
# change sets .lintrc to strict while main sets the same line to main; at its landing settle() merges the two with the
# fast resolver (its judge a stub here) and no gate runs after it, so the merged policy diff, which the owner never
# saw, landed on the old yes. card()'s ph is the hash the gate let through. The card stops again for the yes, its
# kept body holding the merged diff's hash.
t_lintyesfastfit() {
  setup "[$(issue 7 2026-01-01)]"
  tune '.lint = {commands: [{files: ["*.txt"], run: "true"}], policy: [".lintrc"]}'
  fx_wt 'echo strict > .lintrc' .lintrc old
  landed 7 | jq -c '.card = "c7" | .step = "picked"' >> "$ST/cards.jsonl"
  echo main > "$R/.lintrc" && git -C "$R" commit -qam "main sets .lintrc" || fail "main's change of .lintrc"
  fx_in 'cd "$R" || exit 9; caught="" waitsec=0 behind="[]" parsecheck=""
    packget lint l && ph=$(lintpolicy "$FXWT" "$(git -C "$FXWT" rev-parse HEAD)" "$l") && ph=$(head -n 1 <<<"$ph") && [ -n "$ph" ] || exit 7
    echo "approved: $ph"
    judgeon() { echo true; }
    judgecall() { jq -cn "{\"1\": \"main\nstrict\"}" > "$1.judge"; } # judgecall: the stub judge merges both sides
    settle c7 7 "$FXWT" "Build the issue." land "$(issue 7 2026-01-01)"; echo "settle: $?"'
  local ph; ph=$(sed -n 's/^approved: //p' "$T/$CASE/run.out")
  grep -q '^conveyor: card c7: the fast resolver merged its conflicts with main' "$T/$CASE/run.out" \
    || fail "the fast resolver did not merge the card's .lintrc with main's: exit $RC: $(cat "$T/$CASE/run.out")"
  [ "$(tail -n 1 "$T/$CASE/run.out")" = 'settle: 1' ] && [ "$(st 'select(.card == "c7" and .step == "blocked") | .reason')" = "lint policy: needs Dana's yes: it changes lint policy: .lintrc" ] \
    || fail "the merged policy change did not stop for Dana's yes: $(tail -n 1 "$T/$CASE/run.out"), $(st 'select(.card == "c7") | "\(.step) \(.reason)"' | paste -sd,)"
  jq -e --arg h "$ph" '(.policy | type) == "string" and .policy != $h' "$ST/kept/c7/c7.body" > /dev/null \
    || fail "the stop's kept body does not hold the merged diff's hash, apart from the approved $ph: $(cat "$ST/kept/c7/c7.body" 2>&1)"
}
