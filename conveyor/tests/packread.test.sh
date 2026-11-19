#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the project pack, read at every use while one engine process runs on.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The engine keeps the check of the pack it last passed, so it need not check the same text again. Bugs: the same text
# is checked at every read, which made the engine test minutes slower; a run that read the pack at its start reads a
# field with the value it had then, after a card changed it; a pack too long to pass as one argument is not read; a
# pack a card broke, even only past a NUL byte, or a schema that changed under a running engine so the pack no longer
# meets it, still passes at the next read.
# Each card's build changes the pack or the schema after the run has read and checked both (names()); the card's
# test command or its commit trailers, read after the build, are the next read. Each kind of change is a case of its
# own, on an engine copy of its own (packread_start), so they run side by side.
packread_start() { # <issue>: a main with that one issue, the engine copied to $E (eng), the good pack kept
  local -x WHOLESUITE=true # The old fixture: the per-file one runs a.test.sh through test.fileCommand, so an edit to test.command is never run.
  setup "[$(issue "$1" 2026-01-01)]"
  E=$T/$CASE/eng; mkdir -p "$E"; cp -r "$SRC"/* "$E/"; rm -rf "$E/state"; ln -s "$SRC/../.claude" "$T/$CASE/.claude"
  eng() { CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards bash "$E/conveyor.sh" "$@"; }
  P=$R/.conveyor/project.json; S=$E/schema/pack.schema.json; cp "$P" "$STUB/pack.good"
  for i in 1 2; do echo "$GO" > "$STUB/review.$i"; done
}
t_packread() {
  packread_start 7
  # jq, counting the pack's checks and its reads (each runs jq on a program only it has). A read of a checked text
  # starts no program (packall read every field with the check), so the reads counted are those runs alone.
  printf '#!/usr/bin/env bash\ncase "$*" in *"JSON documents, not one"*) echo >> "$STUB/checks" ;; *"not a field of the schema"*) echo >> "$STUB/reads" ;; esac\nexec %q "$@"\n' \
    "$(command -v jq)" > "$STUB/jq" && chmod +x "$STUB/jq"
  # An edited pack, longer than one argument may be: its new test command runs. The text is checked once per
  # process that reads it, not at every read.
  echo 'echo two >> a.txt; { printf "%131072s" ""; jq ".test.command = \"echo edited > \\\"\$STUB/edited\\\"\"" "$STUB/pack.good"; } > "$STUB/p.new" && mv "$STUB/p.new" "'"$P"'"' > "$STUB/build"
  eng run 1 >/dev/null 2>&1 || fail "run exited non-zero: $(st .)"
  [ -e "$STUB/edited" ] && [ ! -e "$STUB/tests" ] || fail "the pack a card edited was not seen at the next read: the old test command ran"
  [ -n "$(st 'select(.issue == 7 and .step == "landed")')" ] || fail "the card with the edited pack did not land: $(st 'select(.issue == 7)')"
  c=$(wc -l < "$STUB/checks") r=$(wc -l < "$STUB/reads"); rm "$STUB/jq"
  # This run reads the pack 39 times (main before #379, which ran jq at every read, counted them): checked at each,
  # that is 39 checks; once per process that reads a text, 11 (names() twice, and once each in the subshells of the
  # card's steps: the build session's read of models.claudeProxy, two tree checks, two trailer reads, the review's
  # models, owing, checks and tests). Each check is followed by one run reading every field.
  [ "$c" -ge 1 ] && [ "$c" -le 11 ] && [ "$r" = "$c" ] || fail "the same pack text was checked again at its reads, or a read ran jq of its own: $c checks, $r reads by jq"
}
# A broken pack: refused at the next read, so the card is blocked, saying why, and its test command never runs.
t_packbroken() {
  packread_start 8
  echo 'echo three >> a.txt; jq ".tunables.poll = 0" "$STUB/pack.good" > "$STUB/p.new" && mv "$STUB/p.new" "'"$P"'"' > "$STUB/build"
  eng run 1 >/dev/null 2>&1
  [ ! -e "$STUB/tests" ] && [ -z "$(st 'select(.issue == 8 and .step == "landed")')" ] || fail "the pack a card broke was read: its test command ran, or the card landed"
  st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q 'conveyor pack: .*\.tunables\.poll: 0 is below 1' \
    || fail "the card was not blocked by the broken pack, saying why: $(st 'select(.issue == 8) | .reason')"
}
# A changed schema: the pack, unchanged, is checked again and refused, as it lacks a field the schema now requires.
t_packschema() {
  packread_start 9
  echo 'echo four >> a.txt; jq ".required += [\"foreman\"]" "'"$S"'" > "$STUB/s.new" && mv "$STUB/s.new" "'"$S"'"' > "$STUB/build"
  eng run 1 >/dev/null 2>&1
  [ ! -e "$STUB/tests" ] && [ -z "$(st 'select(.issue == 9 and .step == "landed")')" ] || fail "the pack was not checked again under the changed schema: its test command ran, or the card landed"
  st 'select(.issue == 9 and .step == "blocked") | .reason' | grep -q 'conveyor pack: .*\.foreman: missing (required)' \
    || fail "the card was not blocked by the pack the changed schema refuses, saying why: $(st 'select(.issue == 9) | .reason')"
}
# A pack broken only past a NUL byte, which a shell variable cannot hold: refused, not read as the good text before it.
t_packnul() {
  packread_start 10
  echo 'echo five >> a.txt; printf "\0{" >> "'"$P"'"' > "$STUB/build"
  eng run 1 >/dev/null 2>&1
  [ ! -e "$STUB/tests" ] && [ -z "$(st 'select(.issue == 10 and .step == "landed")')" ] || fail "the pack broken past a NUL byte was read: its test command ran, or the card landed"
  st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q 'conveyor pack: .*NUL byte' \
    || fail "the card was not blocked by the pack holding a NUL byte, saying why: $(st 'select(.issue == 10) | .reason')"
}
# The pack's names (names(): remote, branch, labels, owner, tunables) are kept while the pack's text is the one they
# were read from, and every field of the schema is read in one jq run per text (packall). Bugs: the loop reads the
# names again at every turn though the pack has not changed; a field is read by a jq run of its own at each use (about
# 30 in one card's run); or the names are kept after a card changed the pack, so it picks by the old labels.
t_packnames() {
  setup "[$(issue 5 2026-01-01), $(issue 6 2026-01-02 shipped)]"
  P=$R/.conveyor/project.json; cp "$P" "$STUB/pack.good"; echo "$GO" > "$STUB/review.1"; loop control cap 1 >/dev/null
  # jq, counting names()'s own runs (the one program that makes PRODUCT: map(rx)), the reads of a field by a run of
  # its own (packget's: $ARGS.positional[] as $f) and the loop's turns (the cap in force, read once a turn: run()).
  printf '#!/usr/bin/env bash\ncase "$*" in *"map(rx)"*) echo >> "$STUB/names" ;; *"positional[] as \\$f"*) echo >> "$STUB/fields" ;; *".cap // \\$d end"*) echo >> "$STUB/turns" ;; esac\nexec %q "$@"\n' \
    "$(command -v jq)" > "$STUB/jq" && chmod +x "$STUB/jq"
  : > "$STUB/names"; : > "$STUB/fields"; : > "$STUB/turns"
  # #5's build makes "shipped" the label of a built issue: #6 carries it, so the turn after it is not picked.
  echo 'echo two >> a.txt; jq ".labels.built = \"shipped\"" "$STUB/pack.good" > "$STUB/p.new" && mv "$STUB/p.new" "'"$P"'"' > "$STUB/build"
  loop run >/dev/null 2>&1 || fail "run exited non-zero: $(st .)"
  n=$(wc -l < "$STUB/names") f=$(wc -l < "$STUB/fields") t=$(wc -l < "$STUB/turns"); rm "$STUB/jq"
  [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ' ')" = "5 " ] || fail "an issue with the label the changed pack names for built was picked: $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
  # Three reads: the loop's first, and two of the pack #5's build changed: the card's test step (listcmd(), in the
  # card's own process, per file as setup has it) and the loop's next turn. A read on each unchanged turn makes more.
  [ "$t" -ge 4 ] && [ "$n" -le 3 ] || fail "the pack's names were read again on an unchanged pack: $n reads in $t turns"
  [ "$f" = 0 ] || fail "a field of the schema was read by a jq run of its own, not from the run that read them all: $f runs"
}

# The review judge's settings moved from the pack to the control record. Bug: a pack that still holds a `judge`
# object passes the check, so its owner believes the judge is on while the engine, which reads it no more, runs none;
# or it fails with no word of where the setting lives now.
t_packjudge() {
  local out
  setup '[]'
  loop check >/dev/null 2>&1 || fail "a pack with no judge object did not pass the check"
  tune '.judge = {mode: "on", always: ["security"]}'
  out=$(loop check 2>&1) && fail "a pack holding a judge object passed conveyor.sh check"
  grep -q 'conveyor pack: .*\.judge: .*conveyor\.sh control judge <on|off>' <<<"$out" && grep -qF 'conveyor.sh control judge always' <<<"$out" \
    || fail "the check of a pack holding a judge object does not name the control command that sets it now: $out"
}
