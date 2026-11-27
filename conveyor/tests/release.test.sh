#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: `conveyor.sh release-prep <version>` and `conveyor.sh release <version>`, a release made on the build
# machine (docs/releases.md, Making a release).
# Each case makes one fixture and runs the commands on it one after another, as an owner would: a case costs its
# fixture and the runner's start and end of it, which were most of this file's CPU when each run had a case of its own.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# relsetup <full-cmd> [nonotes|<notes text>] [notag]: main's pack names a whole suite (test.full: $STUB/full-cmd, which
# notes the commit it ran on); origin has the release v1.0.0 (its commit names issue #1 and adds a README with the
# sections Cards and The Board; with notag, that commit is not tagged) and two commits after it, the first
# naming issue #5 in its subject, the second issue #7 in a Closes line and adding docs/releases/1.1.0.md (not with
# nonotes; with <notes text>, that text); main has one more commit origin lacks. gh records each call, and `gh issue
# view <n>` prints issue n of the fixture issues (#1, #5, #7). A case that drafts notes writes the model, the stub
# claude. O is origin's head, the commit release-prep must test and post on.
relsetup() {
  setup '[{"number":1,"title":"Old","body":"BEFORE-BODY"},{"number":5,"title":"Hold a card","body":"HOLD-BODY"},{"number":7,"title":"Faster board","body":"FAST-BODY"}]'
  tune '.test.full = ". \"$STUB/full-cmd\""'
  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' "$1" > "$STUB/full-cmd"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$STUB/gh-calls"' \
    '[ "$1 $2" != "issue view" ] || jq -c --argjson n "$3" ".[] | select(.number == \$n)" "$STUB/issues.json"' > "$STUB/gh"
  printf '# Fixture\n\nREADME-INTRO\n\n## Cards\n\n- A card waits.\n\n## The Board\n\n- A page.\n' > "$R/README.md" && git -C "$R" add README.md \
    && git -C "$R" commit -q -m 'fix: before the release (#1)' && { [ "${3:-}" = notag ] || git -C "$R" tag v1.0.0; } \
    && git -C "$R" commit -q --allow-empty -m 'feat(engine): A new thing (#5)' || fail "the fixture could not be made"
  [ "${2:-}" = nonotes ] || { mkdir -p "$R/docs/releases" && printf '%s\n' "${2:-- A fix}" > "$R/docs/releases/1.1.0.md" && git -C "$R" add docs; } || fail "the fixture could not be made"
  git -C "$R" commit -q --allow-empty -m 'fix: A fix' -m 'Closes #7'
  git -C "$R" push -q origin main && { [ "${3:-}" = notag ] || { git -C "$R" push -q origin v1.0.0 && git -C "$R" tag -d v1.0.0 > /dev/null; }; } \
    || fail "the fixture could not be made"
  git -C "$R" commit -q --allow-empty -m 'feat: Not pushed yet'
  O=$(git -C "$T/$CASE/origin" rev-parse refs/heads/main)
}

# relmodel <answer>: the model (the stub claude) keeps its prompt in $STUB/notes-prompt and answers <answer>, as the
# result of Claude's JSON output. RELFMT, the end of a stub's pipe: as Claude Code does, the JSON output only with
# --output-format json, else only its result. RELCHECK, the start of a stub: it reads the prompt into p, and answers the
# check of a draft's lines against their sources (reltrace()) itself, its prompt added to $STUB/trace-prompt: with the
# numbers of the lines that hold the text in $STUB/unsupported, or none.
RELFMT='{ [[ " $* " == *" --output-format json "* ]] && cat || jq -j .result; }'
RELCHECK='p=$(cat); if grep -q "^Each numbered line below is a line of release notes" <<<"$p"; then printf "%s\n" "$p" >> "$STUB/trace-prompt"
  r=$(grep -F -- "$(cat "$STUB/unsupported" 2>/dev/null || echo NO-LINE)" <<<"$p" | sed -nE "s/^## Line ([0-9]+): .*/\\1/p")
  jq -cn --arg r "${r:-none}" '\''{type: "result", is_error: false, result: ($r + "\n"), num_turns: 1}'\'' | '"$RELFMT"'; exit; fi'
# stub: the drafter, the rewrite and the check are one model call each, answered without a real model
relmodel() { printf '#!/usr/bin/env bash\n%s\nprintf %%s "$p" > "$STUB/notes-prompt"\njq -cn --arg r %q '\''{type: "result", is_error: false, result: ($r + "\\n"), num_turns: 1}'\'' | %s\n' "$RELCHECK" "$1" "$RELFMT" > "$STUB/claude"; }
# relmodels <first answer> <second answer>: as relmodel, but call n answers its nth answer (the second from then on),
# counts the calls in $STUB/notes-calls and keeps call n's prompt in $STUB/notes-prompt.<n> (the check is not counted).
relmodels() {
  rm -f "$STUB"/notes-calls "$STUB"/notes-prompt.*
  # stub: as relmodel's, with a second answer for the rewrite
  printf '#!/usr/bin/env bash\n%s\nn=$(( $(cat "$STUB/notes-calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/notes-calls"\nprintf %%s "$p" > "$STUB/notes-prompt.$n"\na=(%q %q); r=${a[n > 1 ? 1 : 0]}\njq -cn --arg r "$r" '\''{type: "result", is_error: false, result: ($r + "\\n"), num_turns: 1}'\'' | %s\n' "$RELCHECK" "$1" "$2" "$RELFMT" > "$STUB/claude"
}

# release-prep on a head with no notes: the project's first release, then, v1.0.0 tagged, its next.
# Bugs: a project's first release (no tag) is drafted from every commit ever made, an engineering log, rather than as an
# overview of what the project does, in sections from its README (the model there copies its whole prompt into the
# draft, so a commit subject or an issue given to it would show in the draft). Then: the suite ran and its status was
# posted on a head without the notes (committing the notes then makes a new head, and `release`, which checks the
# status of the head it releases, runs the suite again); the notes draft is not the model's, or the model is not given
# the issues landed since the last release (named by "(#N)" or by a Closes line), their numbers and bodies, the commit
# subjects with their hashes and the style, or is given an issue from before it; a draft line that no issue or commit
# since the last release supports (1.8.0's draft named a doctor check no commit made, beside an issue in the range) is
# kept, or left out without release-prep naming it; a line that traces to one loses its sources, or keeps them in the
# notes; the style rewrite adds a line no source supports, or leaves the side file naming the lines it replaced; a draft that breaks the style (one naming conveyor.sh, as
# 1.7.0's did) is left for the owner to edit, not rewritten once by the model from the check's findings; one that
# still breaks it is shown as if it were ready to commit, or lacks the findings at its top; a model that gives no notes leaves an empty draft, or an earlier run's, to be taken for this run's.
t_reldraft() {
  local O out s
  relsetup true nonotes notag; relmodel $'# 1.0.0\n\nCards hold your work.\n\n## Cards\n\n- You can hold a card.'
  out=$(loop release-prep 1.0.0 2>&1); [ $? = 1 ] && grep -qF "the notes draft, an overview from the README and docs, as no release is tagged yet, is $ST/release/1.0.0.md. " <<<"$out" \
    || fail "release-prep did not draft an overview for a project with no release: $out"
  [ "$(grep '^## ' "$STUB/notes-prompt")" = $'## Cards\n## The Board' ] && grep -q README-INTRO "$STUB/notes-prompt" \
    && grep -q '^- Begin with the line "# 1.0.0"' "$STUB/notes-prompt" || fail "the first release's prompt does not hold the README's sections: $(cat "$STUB/notes-prompt" 2>&1)"
  while IFS= read -r s; do
    ! grep -qF "${s% (#*}" "$STUB/notes-prompt" || fail "the first release's prompt holds a line from the commit subject '$s': $(cat "$STUB/notes-prompt")"
  done < <(git -C "$R" log --format=%s "$O")
  ! grep -qE 'BODY|^issue ' "$STUB/notes-prompt" "$STUB/gh-calls" 2>/dev/null || fail "issues were read for a first release: $(cat "$STUB/gh-calls" 2>&1)"

  # Bug (R49, first release): the no-tag draft went to main with a heading of the model's own, as the refusal ran only
  # for a draft traced since a tag.
  notesshut # the valid draft above started a notes card: closed, the next press drafts again
  relmodel $'# 1.0.0\n\nCards can wait.\n\n## Doctor checks your Git version\n\n- You can hold a card.'
  out=$(loop release-prep 1.0.0 2>&1); [ $? = 1 ] && grep -qF 'the draft has headings that name no section of the README: Doctor checks your Git version' <<<"$out" \
    && [ ! -e "$ST/release/1.0.0.md" ] || fail "a first release's draft with a heading that names no README section was not refused: $out"

  # v1.0.0 on origin, on the commit relsetup tags without notag.
  git -C "$R" push -q origin HEAD~3:refs/tags/v1.0.0 || fail "the fixture could not be made"
  # The model's lines: two traced to issues in the range, one to a commit in it (origin's head, O); one names an issue
  # in the range that does not support it (the check, the stub's RELCHECK, says so, as 1.8.0's doctor check of git's
  # version named #1022, which made none); one names an issue from before the tag, one an issue no commit names, one a
  # commit not in the range (main's unpushed head), one nothing.
  echo 'whether git is too old' > "$STUB/unsupported" || fail "the fixture could not be made"
  relmodel "# 1.1.0"$'\n\nCards can wait. [#5]\n\n## Cards\n\n- You can hold a card. [#5, #7]\n- '"Faster. [${O:0:9}]"$'\n- The doctor check reports whether git is too old. [#7]\n- An old fix. [#1]\n- A board fix. [#99]\n'"- Not pushed. [$(git -C "$R" rev-parse --short=9 HEAD)]"$'\n- Cards are blue.'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  grep -qF 'The draft leaves out the lines no issue or commit since v1.0.0 supports: - The doctor check reports whether git is too old.; - An old fix.; - A board fix.; - Not pushed.; - Cards are blue.' <<<"$out" \
    || fail "release-prep does not name the draft lines no issue or commit in the range supports: $out"
  grep -qxF '## Line 9: - The doctor check reports whether git is too old.' "$STUB/trace-prompt" && grep -q FAST-BODY "$STUB/trace-prompt" \
    && grep -qx 'Closes #7' "$STUB/trace-prompt" && ! grep -qE 'An old fix|Cards are blue|BEFORE-BODY' "$STUB/trace-prompt" \
    || fail "the check is not given each line in the range with its sources' text, the issue's body and the commit's message: $(cat "$STUB/trace-prompt" 2>&1)"
  [ "$(jq -c . "$ST/release/1.1.0.sources.json" 2>&1)" = '[{"line":"Cards can wait.","issues":[5],"commits":[]},{"line":"- You can hold a card.","issues":[5,7],"commits":[]},{"line":"- Faster.","issues":[],"commits":["'"$O"'"]}]' ] \
    && grep -qF "are in $ST/release/1.1.0.sources.json." <<<"$out" \
    || fail "the sources of the draft's lines are not recorded beside it: $(cat "$ST/release/1.1.0.sources.json" 2>&1)"
  [ ! -e "$STUB/full-at" ] || fail "the suite ran on a head with no notes"
  ! grep -q statuses "$STUB/gh-calls" 2>/dev/null || fail "a status was posted on a head with no notes: $(cat "$STUB/gh-calls")"
  [ "$(cat "$ST/release/1.1.0.md")" = $'# 1.1.0\n\nCards can wait.\n\n## Cards\n\n- You can hold a card.\n- Faster.' ] \
    || fail "the notes draft is not the model's: $(cat "$ST/release/1.1.0.md" 2>&1)"
  grep -q HOLD-BODY "$STUB/notes-prompt" && grep -q FAST-BODY "$STUB/notes-prompt" && grep -qx "${O:0:7}[0-9a-f]* fix: A fix" "$STUB/notes-prompt" \
    && grep -qE '^[0-9a-f]{7,} feat\(engine\): A new thing$' "$STUB/notes-prompt" && grep -qx '## #5: Hold a card' "$STUB/notes-prompt" \
    && grep -q '^- Begin with the line "# 1.1.0"' "$STUB/notes-prompt" && ! grep -q BEFORE-BODY "$STUB/notes-prompt" \
    || fail "the model was not given the issues and subjects since v1.0.0 alone, and the style: $(cat "$STUB/notes-prompt" 2>&1)"
  notesshut # the draft passed the style check: its notes card (t_relnotescard) closed, the next press drafts again

  # Bug (R49): a heading is no line the trace checks, so '## Doctor checks your Git version' put a claim no source makes
  # into the notes. A draft with a heading that names no README section is refused: no draft is kept, and release-prep
  # names the heading. The fixture README's sections are Cards and The Board.
  relmodel $'# 1.1.0\n\nCards can wait. [#5]\n\n## Doctor checks your Git version\n\n- You can hold a card. [#5]'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'the notes draft could not be written: the draft has headings that name no section of the README: Doctor checks your Git version' <<<"$out" \
    && [ ! -e "$ST/release/1.1.0.md" ] || fail "a draft with a heading that names no README section was not refused: $out"

  # Bug (R49, level): only "##" headings were read, so a second "#" heading carried the same claim into the notes.
  relmodel $'# 1.1.0\n\nCards can wait. [#5]\n\n## Cards\n\n- You can hold a card. [#5]\n\n# Doctor checks your Git version\n\n- You can hold a card. [#5]'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'name no section of the README: Doctor checks your Git version' <<<"$out" \
    && [ ! -e "$ST/release/1.1.0.md" ] || fail "a draft with a second '#' heading that names no README section was not refused: $out"

  # A first answer that names the command file conveyor.sh (release 1.7.0's own draft did): the model is asked once
  # more, given the check's finding and the lines with their sources, and its rewrite is the draft, which passes the
  # check. The rewrite is traced as the draft was: the line it adds that its source does not support is left out, and
  # the side file names the rewrite's lines, not the first answer's.
  relmodels $'# 1.1.0\n\nCards can wait. [#5]\n\n## Cards\n\n- `conveyor.sh doctor` warns when the model lists differ. [#7]' \
    $'# 1.1.0\n\nCards can wait. [#5]\n\n## Cards\n\n- Conveyor\'s doctor check warns when the model lists differ. [#7]\n- Conveyor\'s doctor check reports whether git is too old. [#7]'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  [ "$(cat "$STUB/notes-calls" 2>&1)" = 2 ] || fail "the model was not asked once more to rewrite the draft: $(cat "$STUB/notes-calls" 2>&1)"
  grep -qF '1.1.0.md:7: a path or file name: - `conveyor.sh doctor`' "$STUB/notes-prompt.2" && grep -qF 'No command file' "$STUB/notes-prompt.1" \
    && grep -qxF -- '- `conveyor.sh doctor` warns when the model lists differ. [#7]' "$STUB/notes-prompt.2" \
    || fail "the rewrite was not given the check's finding and the lines' sources, or the drafter is not told to name no command file: $(cat "$STUB"/notes-prompt.* 2>&1)"
  "$SRC/tools/notes-check.sh" "$ST/release/1.1.0.md" > /dev/null && grep -qF "Conveyor's doctor check warns" "$ST/release/1.1.0.md" \
    || fail "the draft written is not the rewrite that passes the style check: $(cat "$ST/release/1.1.0.md" 2>&1)"
  ! grep -qF 'whether git is too old' "$ST/release/1.1.0.md" && grep -qF "leaves out the lines no issue or commit since v1.0.0 supports: - Conveyor's doctor check reports whether git is too old." <<<"$out" \
    && [ "$(jq -c . "$ST/release/1.1.0.sources.json" 2>&1)" = '[{"line":"Cards can wait.","issues":[5],"commits":[]},{"line":"- Conveyor'"'"'s doctor check warns when the model lists differ.","issues":[7],"commits":[]}]' ] \
    || fail "the rewrite is not traced to its sources: $out; $(cat "$ST/release/1.1.0.md" "$ST/release/1.1.0.sources.json" 2>&1)"
  ! grep -qF 'The draft breaks' <<<"$out" || fail "release-prep says a draft that passes the check breaks the style: $out"
  notesshut

  # Both answers break the style: the draft is kept, its top lists the check's findings, and release-prep names them.
  # The note (its two findings, an issue number and a Closes line, and three more lines) moves the Closes line from 3
  # to 8: the findings name line 8, its line in the draft as saved, not line 3, which holds the note's own text.
  relmodels $'# 1.1.0\n\n- Cards can wait. Closes #5 [#5]' $'# 1.1.0\n\n- Cards can wait. Closes #5 [#5]'
  local cards=$ST/testactions/cards.json run=$T/$CASE/cards/release/run.json; s=$(jq -c '.cards' "$cards")
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  grep -qF 'The draft breaks the release notes style: ' <<<"$out" && grep -qF '1.1.0.md:8: a Closes line' <<<"$out" \
    || fail "release-prep does not say the draft breaks the style, naming the rule and its line in the saved draft: $out"
  [ "$(cat "$STUB/notes-calls" 2>&1)" = 2 ] && head -n 1 "$ST/release/1.1.0.md" | grep -qF '<!--' && sed '/^-->$/q' "$ST/release/1.1.0.md" | grep -qF '1.1.0.md:8: a Closes line: - Cards can wait. Closes #5' \
    && [ "$(sed -n 8p "$ST/release/1.1.0.md")" = '- Cards can wait. Closes #5' ] \
    || fail "a draft that still breaks the style is not kept with the check's findings at its top, naming their lines in it: $(cat "$ST/release/1.1.0.md" 2>&1)"
  # #1365: such a draft starts no card (it would put notes on main that release refuses) and the run stops as refused,
  # the check's lines its reason, not waiting on a card.
  [ "$(jq -c '.cards' "$cards")" = "$s" ] && jq -e '.state == "refused" and .notes == null and (.reasons | any(contains("1.1.0.md:8: a Closes line")))' "$run" > /dev/null \
    || fail "a draft that still breaks the style started a card, or its run is not refused with the check's lines: $(cat "$cards" "$run")"

  # stub: the shared claude stub put back (relmodels replaced it), its call exiting 1 (claude-rc)
  cp "$SRC/tests/stubs/claude" "$STUB/claude" && echo 1 > "$STUB/claude-rc" || fail "the fixture could not be made"
  echo '# an earlier draft' > "$ST/release/1.1.0.md" || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && grep -q 'the notes draft could not be written: the model gave no notes (exit 1' <<<"$out" \
    || fail "release-prep does not say the model gave no notes: $out"
  [ ! -e "$ST/release/1.1.0.md" ] || fail "a draft was written when the model gave none"
}
# Bug (#1704): a model that refuses ("I cannot write ...") gave lines with no source, the trace left every one out, and
# the empty draft started a notes card. The run now ends non-zero with the model's first line, no draft, no card.
t_relrefused() {
  local out cards
  relsetup true nonotes; cards=$ST/testactions/cards.json
  relmodel $'I cannot write the 1.1.0 release notes from this input.\nThe commits give too little to go on.'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] \
    && grep -qF 'the notes draft could not be written: the model gave no notes: I cannot write the 1.1.0 release notes from this input.; nothing run' <<<"$out" \
    && [ ! -e "$ST/release/1.1.0.md" ] && [ ! -e "$ST/release/1.1.0.sources.json" ] && ! grep -qs 'docs/releases/1.1.0.md' "$cards" \
    || fail "a refusal from the model started a notes card, left a draft, or its first line is not in the reason: $out"
}
# Bug (a #1704 follow-up): a draft that breaks the style goes to the model for a rewrite (relfix()); a model that
# refused there gave lines with no source, the trace of the rewrite left every one out, and the style check passed what
# was left (the title alone), which started a notes card. The run now ends non-zero with the refusal's first line (not
# its heading), no
# draft, no card.
t_relfixrefused() {
  local out cards
  relsetup true nonotes; cards=$ST/testactions/cards.json
  relmodels $'# 1.1.0\n\n- Cards can wait. Closes #5 [#5]' $'# 1.1.0\n\nI cannot rewrite these release notes.'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && [ "$(cat "$STUB/notes-calls" 2>&1)" = 2 ] \
    && grep -qF 'the notes draft could not be written: the model gave no notes in its style rewrite: I cannot rewrite these release notes.; nothing run' <<<"$out" \
    && [ ! -e "$ST/release/1.1.0.md" ] && [ ! -e "$ST/release/1.1.0.sources.json" ] && ! grep -qs 'docs/releases/1.1.0.md' "$cards" \
    || fail "release-prep 1.1.0, the style rewrite refused, started a notes card, left a draft, or does not say the rewrite gave no notes: $out"
}
# notesshut: the notes card the release run waits on (its record's notes.card) is closed, so the next release-prep
# drafts again.
notesshut() {
  jq -cn --arg c "$(jq -r '.notes.card' "$T/$CASE/cards/release/run.json")" '{card: $c, issue: 0, step: "closed", time: "2026-11-19T12:00:00Z",
    tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}' >> "$ST/cards.jsonl" || fail "the fixture could not be made"
}

# #1365. Bug: a draft that passes the style check stopped the run as refused, for the owner to commit it on main and
# press again. One card with no issue, not held (the press was the yes), now puts the draft, word for word, on main as
# docs/releases/1.1.0.md, and the record waits on it, to start the run again (relfixes()) as it was started: prep, the
# mode and machine of the control record then. A second press while that card is open (not picked yet) starts no second
# card adding the same file and writes no new draft: a new draft would not be the text the card adds, though the run
# names it as the card's. With the card closed, the next press drafts again and starts a new card with its draft.
t_relnotescard() {
  local O out s id id2 cards run nc='[.cards[] | select(.title | contains("docs/releases/1.1.0.md"))]'
  relsetup true nonotes; cards=$ST/testactions/cards.json run=$T/$CASE/cards/release/run.json
  relmodel $'# 1.1.0\n\nCards can wait. [#5]\n\n## Cards\n\n- You can hold a card. [#5]'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  [ ! -e "$STUB/full-at" ] || fail "the suite ran on a head with no notes"
  id=$(jq -r "$nc"' | if length == 1 then .[0].id else "" end' "$cards" 2>/dev/null)
  [ -n "$id" ] && grep -qF "notes card $id started: the notes draft, from the issues and commits since v1.0.0, is $ST/release/1.1.0.md. " <<<"$out" \
    || fail "release-prep 1.1.0, its draft passing the style check, did not start one notes card and say so: $out; $(cat "$cards" 2>&1)"
  [ "$(jq -r "$nc"'[0].body' "$cards" | sed -n '/^~~~$/,/^~~~$/p' | sed '1d;$d')" = "$(cat "$ST/release/1.1.0.md")" ] \
    && jq -e "$nc"'[0] | .held == null and .label == "Release notes" and .card == null and (.body | contains("create docs/releases/1.1.0.md"))' "$cards" > /dev/null \
    || fail "notes card $id does not ask for the draft, word for word, as docs/releases/1.1.0.md, or is held: $(cat "$cards")"
  jq -e --arg c "$id" '.state == "waiting" and .notes == {card: $c, then: "prep", mode: null, machine: null} and (.reasons | any(startswith("notes card \($c) started")))' "$run" > /dev/null \
    || fail "release-prep 1.1.0's record does not wait on notes card $id: $(cat "$run")"

  s=$(cat "$ST/release/1.1.0.md" "$ST/release/1.1.0.sources.json"); relmodels $'# 1.1.0\n\nCards can wait. [#5]' $'# 1.1.0\n\nCards can wait. [#5]'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  [ "$(jq -r "$nc"' | map(.id) | join(" ")' "$cards")" = "$id" ] && grep -qF "notes card $id is still under way" <<<"$out" \
    && jq -e --arg c "$id" '.state == "waiting" and .notes.card == $c' "$run" > /dev/null \
    || fail "release-prep 1.1.0 pressed again did not keep notes card $id as the one it waits on: $out; $(cat "$cards" "$run")"
  [ ! -e "$STUB/notes-calls" ] && [ "$(cat "$ST/release/1.1.0.md" "$ST/release/1.1.0.sources.json")" = "$s" ] \
    || fail "release-prep 1.1.0 pressed again wrote a new draft while notes card $id adds the first: $(cat "$ST/release/1.1.0.md")"

  notesshut
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  id2=$(jq -r --arg c "$id" "$nc"' | map(select(.id != $c)) | if length == 1 then .[0].id else "" end' "$cards")
  [ -n "$id2" ] && grep -qF "notes card $id2 started: " <<<"$out" && jq -e --arg c "$id2" '.notes.card == $c' "$run" > /dev/null \
    && [ "$(cat "$ST/release/1.1.0.md")" = $'# 1.1.0\n\nCards can wait.' ] \
    && [ "$(jq -r --arg c "$id2" '.cards[] | select(.id == $c) | .body' "$cards" | sed -n '/^~~~$/,/^~~~$/p' | sed '1d;$d')" = "$(cat "$ST/release/1.1.0.md")" ] \
    || fail "release-prep 1.1.0 with notes card $id closed did not draft again and start a new card with that draft: $out; $(cat "$cards" "$run")"
}

# Bug (#1461 A-R50): a run waiting on its notes card to go on to the release, in parallel on this machine
# (`release-run 1.1.0 --parallel --machine local`), lost all three to a press of release-prep alone (the Board's Draft
# notes) while the card was under way: the record then said prep, no mode and no machine, so when the card landed
# relfixes() started release-prep alone, on the default mode and machine, and no release followed.
t_relnoteskeepthen() {
  local out run
  relsetup true nonotes; run=$T/$CASE/cards/release/run.json
  relmodel $'# 1.1.0\n\nCards can wait. [#5]\n\n## Cards\n\n- You can hold a card. [#5]'
  out=$(CONVEYOR_RELEASE_THEN=release CONVEYOR_RELEASE_MACHINE=local loop release-prep 1.1.0 --parallel 2>&1); [ $? = 1 ] || fail "release-prep did not stop on a head with no notes: $out"
  jq -e '.state == "waiting" and (.notes | [.then, .mode, .machine]) == ["release", "parallel", "local"]' "$run" > /dev/null \
    || fail "the first press's record does not wait to release in parallel on this machine: $(cat "$run")"
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep pressed again did not stop on a head with no notes: $out"
  grep -q 'is still under way' <<<"$out" && jq -e '.state == "waiting" and (.notes | [.then, .mode, .machine]) == ["release", "parallel", "local"]' "$run" > /dev/null \
    || fail "release-prep 1.1.0 pressed alone while the notes card is under way dropped the release, the mode or the machine the run waits to go on to: $out; $(cat "$run")"
}

# R51. Bug: release-prep found a version's notes card only from the last run's record, so release-prep 1.12.0 (card
# waiting), then 1.13.0, then 1.12.0 again read no card for 1.12.0 and started a second one adding the same file. The
# third press finds the card in the Tests page's cards and waits on it again: one card titled for 1.12.0.
# Bugs it catches too (follow-up of #1461): release-prep 1.13.0, or release-run or release of it, while 1.12.0 waited on
# its notes card replaced the one record relfixes() starts 1.12.0 again from, so its card landed and nothing ran. Another
# version is refused, the record left waiting: before the release lock and its hold (with the lock held elsewhere, the
# refusal still names the waiting run, not a run under way), and also once relfixes() has marked the run restarted and
# let the lock go, as a lock taken then would refuse the release-run it starts. `release-run stop` ends the wait: 1.13.0
# then runs. A waiting run whose fixes entry says its notes card is closed still holds other versions (bug: that
# entry is only as new as relfixes()'s last pass, and a card retried since may land); a stop ends that wait too.
t_relnotesother() {
  local out cards n run lk
  relsetup true nonotes; cards=$ST/testactions/cards.json run=$T/$CASE/cards/release/run.json
  relmodel $'# 1.12.0\n\nCards can wait. [#5]\n\n## Cards\n\n- You can hold a card. [#5]'
  out=$(loop release-prep 1.12.0 2>&1); [ $? = 1 ] || fail "release-prep 1.12.0 did not stop on a head with no notes: $out"
  exec {lk}>>"$T/$CASE/cards/release/lock" && flock -x "$lk" || fail "the release lock could not be held"
  for n in "release-prep 1.13.0" "release-run prep 1.13.0" "release 1.13.0"; do
    out=$(loop $n 2>&1); [ $? = 1 ] && grep -q 'release-prep 1.12.0 waits on notes card .*release-run stop' <<<"$out" \
      && jq -e '.version == "1.12.0" and .state == "waiting" and .restarted == null' "$run" > /dev/null \
      || fail "$n, while release-prep 1.12.0 waits on its notes card and the lock is held, was not refused for it or replaced its record: $out; $(cat "$run")"
  done
  jq -c '.restarted = "2026-01-01T00:00:00Z"' "$run" > "$run.new" && mv -f "$run.new" "$run"
  out=$(loop release-run prep 1.13.0 2>&1); [ $? = 1 ] && grep -q 'release-prep 1.12.0 starts again' <<<"$out" \
    || fail "release-run prep 1.13.0, after relfixes() marked 1.12.0 restarted, was not refused for it before the lock: $out"
  exec {lk}>&-; jq -c '.restarted = null' "$run" > "$run.new" && mv -f "$run.new" "$run"
  out=$(loop release-run stop 2>&1) || fail "release-run stop of the waiting 1.12.0 failed: $out"
  relmodel $'# 1.13.0\n\nCards can wait. [#5]\n\n## Cards\n\n- You can hold a card. [#5]'
  out=$(loop release-prep 1.13.0 2>&1); [ $? = 1 ] && ! grep -q 'release-prep 1.12.0' <<<"$out" && jq -e '.version == "1.13.0" and .state == "waiting"' "$run" > /dev/null \
    || fail "release-prep 1.13.0, after release-run stop of 1.12.0, did not run to its own notes card: $out; $(cat "$run")"
  jq -c '.fixes = [{issue: null, card: .notes.card, state: "closed"}]' "$run" > "$run.new" && mv -f "$run.new" "$run"
  out=$(loop release-prep 1.12.0 2>&1); [ $? = 1 ] && grep -q 'release-prep 1.13.0 waits on notes card' <<<"$out" && jq -e '.version == "1.13.0" and .state == "waiting"' "$run" > /dev/null \
    || fail "release-prep 1.12.0, while 1.13.0 waits on a notes card its fixes entry says is closed, was not refused for it or replaced its record: $out; $(cat "$run")"
  out=$(loop release-run stop 2>&1) || fail "release-run stop of the waiting 1.13.0, its notes card closed, failed: $out"
  out=$(loop release-prep 1.12.0 2>&1); [ $? = 1 ] || fail "release-prep 1.12.0 did not stop on a head with no notes: $out"
  [ "$(jq -r '[.cards[] | select(.title | startswith("Release notes 1.12.0"))] | length' "$cards")" = 1 ] && grep -q 'is still under way' <<<"$out" \
    || fail "release-prep 1.12.0, after 1.13.0's wait was stopped, did not keep its one notes card: $out; $(cat "$cards")"
}
# R254. Bug it catches: relnoteskept() took a notes card that had landed as done, though its commit was not pushed yet,
# so release-prep on origin's head (no notes there yet) wrote a new draft and started a second card adding the same
# file. Notes card c-1 landed on main, not on origin: relnoteskept() on origin's head waits on it again; on the landed
# commit itself (the notes there) it does not.
t_relnotesunpushed() {
  local o n
  setup '[]'; o=$(git -C "$R" rev-parse HEAD)
  mkdir -p "$ST/testactions" && echo '{"cards": [{"id": "c-1", "label": "Release notes", "title": "Release notes 1.1.0: add docs/releases/1.1.0.md"}]}' > "$ST/testactions/cards.json" \
    && mkdir -p "$R/docs/releases" && echo '# 1.1.0' > "$R/docs/releases/1.1.0.md" && git -C "$R" add docs && git -C "$R" commit -qm 'Release notes 1.1.0' \
    && n=$(git -C "$R" rev-parse HEAD) && [ "$(git -C "$T/$CASE/origin" rev-parse refs/heads/main)" = "$o" ] \
    && jq -cn --arg s "$n" '{card: "c-1", issue: 0, step: "landed", time: "2026-11-19T12:00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: $s, reason: ""}' >> "$ST/cards.jsonl" \
    || fail "the fixture could not be made"
  # relnoteswait()'s RELMODE and relrec() are commands/release-prep.sh's, which this call does not load; the record is not read here.
  fx_in "RELMODE=''; relrec() { :; }; cd '$R' && relnoteskept 1.1.0 c-1 prep $o"
  [ "$RC" = 0 ] && grep -qF 'notes card c-1 is still under way' "$T/$CASE/run.out" \
    || fail "relnoteskept on origin's head did not wait again on notes card c-1, landed but not pushed ($RC): $(cat "$T/$CASE/run.out")"
  fx_in "RELMODE=''; relrec() { :; }; cd '$R' && relnoteskept 1.1.0 c-1 prep $n"
  [ "$RC" = 1 ] || fail "relnoteskept on the commit notes card c-1 landed waits on it again ($RC): $(cat "$T/$CASE/run.out")"
}
# The release notes style check, then release-prep on a head with notes.
# Bugs: the style check passes notes that name a file, an issue or a commit, so users read an engineering log; or it
# refuses the shipped 1.0.0 notes. Each finding names its rule, so the owner knows what to change. The suite runs, and
# its pass is posted, on a head whose notes `release` refuses, so the run is wasted. With the notes fixed: a passing
# status is posted on a commit whose suite was not run or did not pass, or on main's local head rather than the
# remote's (the commit `release` releases); a model is paid to draft notes the head already holds. Then a failing suite
# still posts a passing status, so `release` would release a red commit without running the suite.
t_relpass() {
  local O out f=$T/$CASE.md rule line
  # The 1.0.0 notes are checked where the release notes are: an install of the release set ships no docs/releases/
  # folder, though it has the docs/ pages a test of the set reads (issue 769). The fixtures below run in both. A
  # checkout with docs/releases/ but no 1.0.0 notes still fails.
  if [ -d "$SRC/../docs/releases" ]; then
    out=$("$SRC/tools/notes-check.sh" "$SRC/../docs/releases/1.0.0.md") || fail "the 1.0.0 notes break the style: $out"
  else
    echo "skip [$CASE]: the 1.0.0 notes are not checked here: this install has no docs/releases/ folder" >&2
  fi
  while IFS='|' read -r rule line; do
    printf '# 9.9.9\n\nThe release.\n\n%s\n' "$line" > "$f"
    out=$("$SRC/tools/notes-check.sh" "$f" n.md); [ $? = 1 ] && grep -qF "n.md:5: $rule: $line" <<<"$out" \
      || fail "the check did not refuse \"$line\" as $rule: $out"
  done <<'EOF'
a ### heading|### Cards
an issue or pull request number|- Cards can wait (#12).
a commit hash|- Landed at 3f9a2c1d.
a path or file name|- The fix is in conveyor/lib/x.sh.
a path or file name|- The belt is drawn by belt3d.js.
a path or file name|- A new logo.svg and icon.png.
a Closes line|Closes #3
EOF

  relsetup true $'# 1.1.0\n\n### Fixes'
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] && grep -qF 'docs/releases/1.1.0.md:3: a ### heading' <<<"$out" \
    || fail "release-prep did not refuse notes that break the style, naming the rule: $out"
  [ ! -e "$STUB/full-at" ] && ! grep -q statuses "$STUB/gh-calls" 2>/dev/null || fail "the suite ran or a status was posted on notes that break the style"

  # The notes fixed and pushed, and main one commit ahead of origin again.
  echo '- A fix' > "$R/docs/releases/1.1.0.md" && git -C "$R" commit -qam 'fix: The notes' && git -C "$R" push -q origin main \
    && O=$(git -C "$R" rev-parse HEAD) && git -C "$R" commit -q --allow-empty -m 'feat: Not pushed yet' || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed on a passing suite: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on origin's head $O: $(cat "$STUB/full-at" 2>&1)"
  [ "$(grep -c statuses "$STUB/gh-calls")" = 1 ] && grep -q "statuses/$O -f state=success -f context=conveyor/release-suite " "$STUB/gh-calls" \
    || fail "no passing conveyor/release-suite status was posted on $O: $(cat "$STUB/gh-calls" 2>&1)"
  [ ! -e "$STUB/sessions" ] && [ ! -e "$ST/release/1.1.0.md" ] || fail "a notes draft was written for a head that holds the notes"

  printf 'git rev-parse HEAD > "$STUB/full-at"\nfalse\n' > "$STUB/full-cmd" && rm -f "$STUB/full-at" "$STUB/gh-calls" || fail "the fixture could not be made"
  out=$(loop release-prep 1.1.0 2>&1); [ $? = 1 ] || fail "release-prep did not fail on a failing suite: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on origin's head $O"
  ! grep -q 'state=success' "$STUB/gh-calls" && grep -q "statuses/$O -f state=failure -f context=conveyor/release-suite " "$STUB/gh-calls" \
    || fail "a failing suite did not post a failing status, or posted a passing one: $(cat "$STUB/gh-calls" 2>&1)"
  grep -q 'suite failed' <<<"$out" || fail "release-prep does not say the suite failed: $out"
}

# cutsetup <full-cmd> [<text>]: for `release`. main's pack names a whole suite ($STUB/full-cmd, which notes the commit
# it ran on); main holds plugin.json (p, 1.0.0) and a marketplace whose entry for p is pinned at v1.0.0 (and another
# plugin's entry), and <text> in old.txt when given; v1.0.0 is tagged there, then a commit adds
# docs/releases/1.1.0.md; origin has main and the tag. gh: `api` reads print $STUB/statuses ([] when there is none);
# `api -X POST` and `release` are noted in $STUB/gh-calls, and the notes file `release` is given is kept as
# $STUB/body. O is main's head, the commit to release.
cutsetup() {
  setup '[]'; tune '.test.full = ". \"$STUB/full-cmd\""'
  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' "$1" > "$STUB/full-cmd"
  printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" = release ] || [[ " $* " == *" -X POST "* ]]; then printf "%s\n" "$*" >> "$STUB/gh-calls"' \
    'while [ $# -gt 0 ]; do [ "$1" != --notes-file ] || cp "$2" "$STUB/body"; shift; done' \
    'else cat "$STUB/statuses" 2>/dev/null || echo "[]"; fi' > "$STUB/gh"
  mkdir -p "$R/.claude-plugin" "$R/docs/releases" && jq -n '{name: "p", version: "1.0.0"}' > "$R/.claude-plugin/plugin.json" \
    && jq -n --arg s "$(printf 'a%.0s' {1..40})" '{name: "m", plugins: [{name: "p", source: {source: "url", url: "https://github.com/o/p.git", ref: "v1.0.0", sha: $s}},
      {name: "q", source: {source: "github", repo: "o/q", ref: "v9.0.0"}}]}' > "$R/.claude-plugin/marketplace.json" \
    && { [ -z "${2:-}" ] || echo "$2" > "$R/old.txt"; } \
    && git -C "$R" add -A && git -C "$R" commit -qm 'the first release' && git -C "$R" tag -a v1.0.0 -m 'Release 1.0.0' \
    && printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$R/docs/releases/1.1.0.md" && git -C "$R" add -A && git -C "$R" commit -qm 'fix: A fix' \
    && git -C "$R" push -q origin main v1.0.0 || fail "the fixture could not be made"
  O=$(git -C "$R" rev-parse HEAD)
}
# cutrefused <version> <reason (grep -E)>...: release exits 1 naming each reason, and nothing is committed, tagged,
# pushed or released. Bug each caller catches: a release cut when that check fails, or one refused that still changed
# something. The checks before the suite each add their reason, so one run can name several.
cutrefused() {
  local out h r v=$1; shift; h=$(git -C "$R" rev-parse HEAD)
  out=$(loop release "$v" 2>&1); [ $? = 1 ] || fail "release was not refused: $out"
  for r; do grep -qE "refused, nothing tagged or released: .*$r" <<<"$out" || fail "the refusal does not say why ($r): $out"; done
  [ "$(git -C "$R" rev-parse HEAD)" = "$h" ] && [ -z "$(git -C "$R" tag -l "v$v")" ] \
    || fail "a refused release committed or tagged: $(git -C "$R" log --oneline -3) $(git -C "$R" tag -l)"
  [ "$(git -C "$T/$CASE/origin" tag -l)" = v1.0.0 ] && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$O" ] \
    && ! grep -q '^release' "$STUB/gh-calls" 2>/dev/null || fail "a refused release pushed or released: $(git -C "$T/$CASE/origin" tag -l) $(cat "$STUB/gh-calls" 2>&1)"
}

# release refused by the cheap checks, which come before the suite (not run when one of them refuses), then released.
# Refused: a version not higher than the newest release; no notes for it; an uncommitted change (which stays as it
# was); a commit the remote does not have, which would be released without being on GitHub's main. Bug: notes that read
# as an engineering log (an issue number here) are released as the GitHub release's text.
# Then all checks pass, with no status from release-prep: the suite runs; the tag is on a commit whose plugin.json says
# 1.1.0 and whose marketplace names v1.1.0; main's marketplace pins v1.1.0 at that commit, the other entry untouched;
# origin has both; the GitHub release is v1.1.0 with the notes as its body. The help says only the owner decides.
t_cutpass() {
  local O t out; cutsetup true
  echo changed >> "$R/a.txt" && git -C "$R" commit -q --allow-empty -m 'not pushed' || fail "the fixture could not be made"
  cutrefused 0.9.0 'the version 0.9.0 is not higher than the newest release, v1.0.0' 'no release notes: docs/releases/0.9.0.md is missing' \
    'the checkout has uncommitted changes' 'the checkout is not on main at the head of origin/main'
  [ "$(tail -n 1 "$R/a.txt")" = changed ] || fail "the refusal changed the uncommitted file"
  [ ! -e "$STUB/full-at" ] || fail "the suite ran for a release refused before it"

  git -C "$R" reset -q --hard "$O" && printf '# 1.1.0\n\n- A fix (#12)\n' > "$R/docs/releases/1.1.0.md" && git -C "$R" commit -qam 'the notes' \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  cutrefused 1.1.0 'the release notes break the release notes style: docs/releases/1.1.0.md:3: an issue or pull request number'
  [ ! -e "$STUB/full-at" ] || fail "the suite ran for a release refused before it"

  printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$R/docs/releases/1.1.0.md" && git -C "$R" commit -qam 'the notes, fixed' \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  out=$(loop release 1.1.0 2>&1) || fail "the release was refused: $out"
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on the commit to release"
  t=$(git -C "$T/$CASE/origin" rev-parse 'v1.1.0^{commit}' 2>/dev/null) && [ "$(git -C "$T/$CASE/origin" cat-file -t v1.1.0)" = tag ] \
    || fail "origin has no annotated tag v1.1.0"
  [ "$(git -C "$R" show "$t:.claude-plugin/plugin.json" | jq -r .version)" = 1.1.0 ] || fail "plugin.json's version at the tag is not 1.1.0"
  [ "$(git -C "$R" show "$t:.claude-plugin/marketplace.json" | jq -c '.plugins[0].source | [.ref, .sha]')" = '["v1.1.0",null]' ] \
    || fail "the marketplace at the tag does not name v1.1.0, or still pins the old sha"
  # The pin is written into the url source as it is: still a url source with its https:// URL, so it installs with no
  # GitHub SSH key.
  [ "$(git -C "$T/$CASE/origin" show main:.claude-plugin/marketplace.json | jq -c '[.plugins[].source | [.ref, .sha]]')" = "[[\"v1.1.0\",\"$t\"],[\"v9.0.0\",null]]" ] \
    && [ "$(git -C "$T/$CASE/origin" show main:.claude-plugin/marketplace.json | jq -c '.plugins[0].source | [.source, .url]')" = '["url","https://github.com/o/p.git"]' ] \
    && [ "$(git -C "$T/$CASE/origin" rev-parse main^)" = "$t" ] || fail "origin's main does not pin v1.1.0 at the tagged commit $t, right after it, in the same url source"
  grep -q '^release create v1.1.0 --verify-tag ' "$STUB/gh-calls" && cmp -s "$STUB/body" "$R/docs/releases/1.1.0.md" \
    || fail "the GitHub release is not v1.1.0 with the notes file as its body: $(cat "$STUB/gh-calls" 2>&1)"
  loop release --help | grep -q 'Only the owner decides a release: the Foreman runs conveyor.sh release only after the owner says yes in chat' \
    || fail "the help does not say only the owner decides a release"
}
# The privacy check, in one run: a private text in a tracked file from before the last release, which no commit since
# it touches; one added and removed again since the last release, still found by the commit that added it (h).
# Bug: a GitHub web edit's Signed-off-by trailer, which holds the commit's own author email, refused the release. A
# sign-off (A) or co-author (D) trailer with the commit's own author or committer email is not a hit; a sign-off with
# another email (B), or a body line with another email beside an own sign-off (C), still is. Bug (R173): a sign-off
# line with the author's own email that is not in the trailer block, as a prose line follows it (E), was taken out too;
# it is a hit. The hits are listed newest first, so the list is E C B h exactly: A, D and the commit that removes the
# text are no hits.
t_cutprivacy() {
  local O h b c e AT=@; local m=dev${AT}mail.io o=other${AT}mail.io; cutsetup true "someone${AT}gmail.com"
  echo "someone${AT}gmail.com" > "$R/new.txt" && git -C "$R" add new.txt && git -C "$R" commit -qm add && h=$(git -C "$R" rev-parse HEAD) \
    && git -C "$R" rm -q new.txt && git -C "$R" commit -qm remove || fail "the fixture could not be made"
  com() { GIT_COMMITTER_EMAIL=$1 git -C "$R" commit -q --allow-empty --author="dev <$m>" -m x -m "$2" && git -C "$R" rev-parse HEAD; } # <committer> <body>
  com "$m" "Signed-off-by: dev <DEV${AT}mail.io>" > /dev/null && b=$(com "$m" "Signed-off-by: other <$o>") \
    && c=$(com "$m" "$(printf 'Ask %s\n\nSigned-off-by: dev <%s>' "$o" "$m")") && com "$o" "Co-authored-by: other <$o>" > /dev/null \
    && e=$(com "$m" "$(printf 'Signed-off-by: dev <%s>\nand a line of prose after it' "$m")") \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  cutrefused 1.1.0 'privacy check finds something in the tracked files.*old.txt:1: email' \
    "privacy check finds something in commits since v1.0.0: ${e:0:12} ${c:0:12} ${b:0:12} ${h:0:12} \(run"
}
# Bug (R180): release took the pass of main's head from release-prep's commit status, its record naming another
# commit's run (here a serial run on another machine): it set the commit and cleared the counts, but kept that run's
# mode, files at once and machine, so the record said main's suite ran as that run did. Those are not known of the
# pass taken, so they are cleared.
t_cutstatusother() {
  local O out; cutsetup true
  mkdir -p "$T/$CASE/cards/release" && jq -n '{kind: "release", step: "release-prep", version: "1.1.0", since: "2026-01-01T00:00:00Z", ended: "2026-01-01T00:10:00Z", state: "passed",
    sha: "0123456789abcdef0123456789abcdef01234567", mode: "serial", atOnce: 1, machine: {kind: "ssh", name: "box.example.com"}, done: 9, failed: 0,
    cases: [], alone: [{case: "flips", verdict: "flaky"}], moved: false, reused: null}' > "$T/$CASE/cards/release/run.json" \
    && echo '[{"context":"conveyor/release-suite","state":"success"}]' > "$STUB/statuses" || fail "the fixture could not be made"
  out=$(loop release 1.1.0 2>&1) || fail "the release with the pass of main's head from its status was refused: $out"
  [ ! -e "$STUB/full-at" ] && jq -e --arg o "$O" '.sha == $o and .mode == null and .atOnce == null and .machine == null and .alone == [] and .done == 0' \
    "$T/$CASE/cards/release/run.json" > /dev/null || fail "the record of the release keeps the other commit's run: $(cat "$T/$CASE/cards/release/run.json")"
}
# --allow-commit: hits in pushed commits (a, b) the owner keeps, as only a history rewrite could remove them.
# Bugs: no way to release over them; a named commit passes over a hit in one not named (b), or one not on origin/main
# (x, a commit main does not hold) is passed over too; the release does not keep which commits it passed over, and who
# said so; --allow-commit is taken with no --by.
t_cutallow() {
  local O a b x out AT=@; cutsetup true
  a=$(git -C "$R" commit -q --allow-empty -m "fix: ask someone${AT}gmail.com" && git -C "$R" rev-parse HEAD) \
    && b=$(git -C "$R" commit -q --allow-empty -m "fix: ask other${AT}gmail.com" && git -C "$R" rev-parse HEAD) \
    && x=$(git -C "$R" commit-tree -p "$b" -m "side: someone${AT}gmail.com" "$b^{tree}") \
    && git -C "$R" push -q origin main && O=$(git -C "$R" rev-parse HEAD) || fail "the fixture could not be made"
  out=$(loop release 1.1.0 --allow-commit "${a:0:12}" 2>&1); [ $? = 2 ] && grep -q 'usage: conveyor.sh release' <<<"$out" || fail "--allow-commit with no --by was taken: $out"
  out=$(loop release 1.1.0 --allow-commit "${a:0:12}" --by 'the owner' 2>&1); [ $? = 1 ] \
    && grep -q "privacy check finds something in commits since v1.0.0: ${b:0:12} (run" <<<"$out" || fail "a hit in a commit not named was passed over, or the named one still refused: $out"
  out=$(loop release 1.1.0 --allow-commit "${a:0:12}" --allow-commit "${b:0:12}" --allow-commit "${x:0:12}" --by 'the owner' 2>&1); [ $? = 1 ] \
    && grep -q "refused, nothing tagged or released: --allow-commit ${x:0:12}: ${x:0:12} is not on origin/main" <<<"$out" || fail "a named commit not on origin/main was not refused: $out"
  [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" 2>/dev/null || fail "a refused --allow-commit was tagged or released"
  out=$(loop release 1.1.0 --allow-commit "${a:0:12}" --allow-commit "${b:0:12}" --by 'the owner' 2>&1) || fail "the release with only named, pushed hits was refused: $out"
  grep -qF "passes over its hits in $b $a, on origin/main, by the owner" <<<"$out" && [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] || fail "the release did not say what it passed over, or was not tagged: $out"
  jq -e --arg a "$a" --arg b "$b" '.state == "released" and .allowed == {by: "the owner", commits: [$b, $a]}' "$T/$CASE/cards/release/run.json" > /dev/null \
    || fail "the release's record does not keep the commits passed over and who said so: $(cat "$T/$CASE/cards/release/run.json")"
}
# #1084, E6 of its review. Bug it catches: a failing suite in `release` (which judges no case alone) said only that
# the suite did not pass, so a failure that printed no message of its own could not be read without a run again. The
# suite prints a failed TAP case and a stack frame of docs/releases/1.1.0.md, line 1: the refusal names the case with
# that place and its text.
t_cutsuiteat() {
  local O out
  cutsetup "printf '%s\n' 'not ok 1 - stub' \"    at Object.<anonymous> (\$PWD/docs/releases/1.1.0.md:1:1)\"; false"
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] || fail "release was not refused: $out"
  grep -qxF 'conveyor: release: failed: not ok 1 - stub (at docs/releases/1.1.0.md:1: # 1.1.0)' <<<"$out" \
    || fail "the refused release does not name the failed case with where it failed: $out"
}
# Bug it catches (O140): a red suite of 2,000 failed cases with names of 100 bytes made a progress object over Linux's
# 128 KiB limit of one argument, given to jq as one: jq did not start, and the record kept none of the failed cases.
t_cutmanyfailed() {
  local O; cutsetup 'd=$CONVEYOR_TEST_LOG/cases/failed; mkdir -p "$d" && for i in $(seq 2000); do : > "$d/$(printf "case%04d-%096d" "$i" 0)"; done; false'
  cutrefused 1.1.0 'the whole suite did not pass'
  local RUN=$T/$CASE/cards/release/run.json
  jq -e '.state == "failed" and (.cases | length) == 2000 and .failed == 2000 and (.cases[0] | length) == 105' "$RUN" > /dev/null \
    || fail "the record of a suite of 2000 failed cases does not end failed with them: $(jq -c '{state, failed, n: (.cases | length)}' "$RUN" 2>&1)"
  # Bug it catches (E6): release's start (relstart()) passed release-prep's failed pass of its version as one jq
  # argument, so its record was not written and the failed run --anyway goes over was lost. relstart() is called alone.
  jq '.step = "release-prep"' "$RUN" > "$RUN.prep" && mv "$RUN.prep" "$RUN" || fail "the fixture could not be made"
  CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash -c '. "$1/conveyor.sh" state-dir > /dev/null && eval "$(sed "/^shift\$/,\$d" "$1/commands/release-prep.sh")" && relstart release 1.1.0' _ "$SRC" \
    || fail "relstart failed"
  jq -e '.step == "release" and .state == "running" and (.cases | length) == 2000 and (.red.cases | length) == 2000' "$RUN" > /dev/null \
    || fail "release's start did not keep release-prep's failed pass of 2000 cases: $(jq -c '{step, state, n: (.cases | length), red: (.red.cases | length)}' "$RUN" 2>&1)"
}
# Bug it catches (O223): with git status failing (core.bare=true on the checkout), its empty output read as a clean
# checkout, and the release went on. It is refused, naming the status that could not be read, with nothing tagged:
# by the check before the suite, then (the suite making the status fail as it ends) by the check after the suite.
# The check after the merge of a landing pull request is t_prreleasebare in landas.test.sh.
t_cutbare() {
  local O; cutsetup true
  git -C "$R" config core.bare true || fail "the fixture could not be made"
  cutrefused 1.1.0 "the checkout's status could not be read"
  [ ! -e "$STUB/full-at" ] || fail "the suite ran for a release refused before it"
  git -C "$R" config core.bare false && printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' 'git -C "$R" config core.bare true' > "$STUB/full-cmd" \
    || fail "the fixture could not be made"
  cutrefused 1.1.0 'the checkout moved or changed while the suite ran, or its status could not be read'
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on the commit to release, so the check after it was not reached"
}
# The suite, the last check. Bugs: a release cut on a failing suite, or with the suite run on another commit than the one
# to release; a commit made in the checkout while the suite ran (a card landed there) tagged and pushed unchecked, or
# the run's record not saying main moved, so the Board's Release panel offers no run on the new main and shows no
# reason; a release-prep pass on the same commit not taken, and the whole suite run again.
t_cutsuite() {
  local O out; cutsetup false
  cutrefused 1.1.0 'the whole suite did not pass'
  [ "$(cat "$STUB/full-at" 2>/dev/null)" = "$O" ] || fail "the suite did not run on the commit to release"

  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' 'git -C "$R" commit -q --allow-empty -m "landed meanwhile"' > "$STUB/full-cmd" \
    || fail "the fixture could not be made"
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] && grep -q 'refused, nothing tagged or released: the checkout moved or changed while the suite ran' <<<"$out" \
    || fail "a checkout that moved during the suite was not refused: $out"
  [ -z "$(git -C "$R" tag -l v1.1.0)" ] && [ "$(git -C "$T/$CASE/origin" tag -l)" = v1.0.0 ] && [ "$(git -C "$T/$CASE/origin" rev-parse main)" = "$O" ] \
    && [ "$(git -C "$R" log -1 --format=%s)" = 'landed meanwhile' ] || fail "the refused release tagged, pushed or committed"
  jq -e --arg o "$O" '.moved == true and .state == "refused" and .sha == $o and .ended != null and any(.reasons[]; test("the checkout moved"))' "$T/$CASE/cards/release/run.json" > /dev/null \
    || fail "the run's record does not say main moved, with the moved reason: $(cat "$T/$CASE/cards/release/run.json" 2>&1)"

  git -C "$R" reset -q --hard "$O" && rm -f "$STUB/full-at" || fail "the fixture could not be made"
  echo '[{"context":"conveyor/release-suite","state":"success"},{"context":"conveyor/release-suite","state":"failure"}]' > "$STUB/statuses"
  out=$(loop release 1.1.0 2>&1) || fail "the release with release-prep's pass was refused: $out"
  [ ! -e "$STUB/full-at" ] && [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] || fail "the suite ran again, or no tag was pushed: $out"
}
