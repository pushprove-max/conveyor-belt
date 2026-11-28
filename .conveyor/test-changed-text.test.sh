#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-changed.sh on a change to texts alone (issue 512). Bug: card #509 reworded short texts in 9 engine files and ran
# 463 tests, most of them on logic that did not change, as a change to an engine file ran its whole area. A change to
# the messages, comments and blanks of an engine or Board file now runs only the tests that hold its texts; a change to
# quoted code, or to a #! or shellcheck line, still runs the area. (These cases are apart from test-changed.test.sh,
# so the two files run side by side.)
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
AT=@
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t${AT}example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t${AT}example.com
unset CONVEYOR_TEST_LOG CONVEYOR_SHELL_TEST_CASE CONVEYOR_TEST_FILELIST CONVEYOR_TEST_RERUN
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; }

# A scratch repo: area a is the engine file conveyor/lib/m.sh and case file a.test.sh (aone); area b is conveyor/y.sh
# and b.test.sh (bone), whose case checks m.sh's first message. y.sh echoes m.sh's second message (m.sh's again() echoes it too); the Board's app.js
# compares it, and
# its test (named after it) writes `app` to ran, as the runner stub writes the cases it was asked for (ALL for none).
# Area c (c.test.sh, cone) no change here selects: aone and bone are then not a case of every case file, which runs the
# whole engine test (a meta-runner's run, issue 584, that the pack here does not mark).
R=$T/r; mkdir -p "$R/.conveyor" "$R/conveyor/lib" "$R/conveyor/tests" "$R/.claude/dashboard/__tests__"
cp "$HERE/test-changed.sh" "$HERE/funcs.awk" "$HERE/test-share.sh" "$HERE/lint-shell.sh" "$HERE/test-lint.sh" "$HERE/no-browser-tests.sh" "$HERE/no-records-split.sh" "$R/.conveyor/"
printf '%s\n' '{"area": "a", "file": "conveyor/lib/m.sh"}' '{"area": "a", "test": "a.test.sh"}' \
  '{"area": "b", "file": "conveyor/y.sh"}' '{"area": "b", "test": "b.test.sh"}' \
  '{"area": "c", "test": "c.test.sh"}' > "$R/.conveyor/engine-areas.json"
cat > "$R/conveyor/lib/m.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC2034
PROTOS='file git ssh http'
GONE='its process was gone before the end'
# What a card says when it stops.
stop() {
  echo "the engine could not read the project pack $1" >&2
  echo "the change no longer applied"
  jq -r '.steps[] | .name' "$1"
}
again() {
  echo "the change no longer applied"
}
EOF
printf 't_aone() {\n  :\n}\n' > "$R/conveyor/tests/a.test.sh"
printf 't_bone() {\n  grep -q "could not read the project pack" out\n}\n' > "$R/conveyor/tests/b.test.sh"
printf 't_cone() {\n  :\n}\n' > "$R/conveyor/tests/c.test.sh"
echo 'echo "the change no longer applied"' > "$R/conveyor/y.sh"
echo 'echo "${CONVEYOR_SHELL_TEST_CASE:-ALL}" >> "$(dirname "$0")/../ran"' > "$R/conveyor/conveyor.test.sh"
printf "if (why === 'the change no longer applied') show('Show the reason');\n" > "$R/.claude/dashboard/app.js"
echo 'echo app >> "$(dirname "$0")/../../../ran"' > "$R/.claude/dashboard/__tests__/app.test.sh"
echo ran > "$R/.gitignore"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm init
# What one run ran (its exit in $T/rc, its output in $T/out), sorted; the list for a run again: $T/rerun when it is there.
ran() {
  rm -f "$R/ran"
  (cd "$R" && if [ -f "$T/rerun" ]; then CONVEYOR_TEST_RERUN=$T/rerun bash .conveyor/test-changed.sh; else bash .conveyor/test-changed.sh; fi) > "$T/out" 2>&1
  echo $? > "$T/rc"; cat "$R/ran" 2>/dev/null | tr ' ' '\n' | grep . | sort | tr '\n' ' ' | sed 's/ $//'
}
edit() { sed "s,$1,$2," "$R/$3" > "$T/e" && cat "$T/e" > "$R/$3"; } # <old> <new> <file>
PARTS=()
part() { # p_<name> in the background, with its own copy of the scratch repo (R), its output in $T/<name>.res
  PARTS+=("$1")
  (B=$T; T=$T/$1; mkdir "$T" && cp -a "$B/r" "$T/r" || exit 1; R=$T/r; "p_$1"; : > "$B/$1.end") > "$T/$1.res" 2>&1 &
}

# D1: a reworded echo message runs the case files that hold it (b's), not m.sh's area (a's).
p_echo() {
  edit 'could not read' 'cannot read' conveyor/lib/m.sh; got=$(ran)
  [ "$got" = bone ] && [ "$(cat "$T/rc")" = 0 ] && ok "a reworded echo message runs only the case files that hold it" \
    || no "echo reworded: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# D2: a jq program is code, though it is quoted: the change is one to its function, stop, and the test that names
# stop runs (callersof), not only the tests that hold the text (none does). Before issue 1830 the scratch repo's
# missing conveyor.sh made callersof fail here, and m.sh's area ran with no test naming stop; a real checkout got the
# tests callersof gives already.
p_jq() {
  printf 't_aone() {\n  stop pack\n}\n' > "$R/conveyor/tests/a.test.sh"; git -C "$R" commit -qam names
  edit '| .name' '| .title' conveyor/lib/m.sh; got=$(ran)
  [ "$got" = aone ] && grep -qxF 'coverage map rule: conveyor/lib/m.sh stop(): callersof' "$T/out" \
    && ok "a change to a jq filter string runs the tests that name its function, as a change to code does" || no "jq changed: ran '$got': $(cat "$T/out")"
}
# D3: a comment alone runs no case file; a #! line and a shellcheck line are code.
p_comment() {
  edit 'when it stops' 'when it ends' conveyor/lib/m.sh; got=$(ran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && ok "a comment change runs no case file" || no "comment changed: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
p_shebang() {
  edit '^#!/usr/bin/env bash' '#!/bin/bash' conveyor/lib/m.sh; got=$(ran)
  [ "$got" = aone ] && ok "a change to the #! line runs the file's whole area" || no "#! changed: ran '$got': $(cat "$T/out")"
}
p_shellcheck() {
  edit 'SC2034' 'SC2154' conveyor/lib/m.sh; got=$(ran)
  [ "$got" = aone ] && ok "a change to a shellcheck line runs the file's whole area" || no "shellcheck changed: ran '$got': $(cat "$T/out")"
}
# A list of names set to a name (a field list, protocols) is code, though its words are words: the area runs (bug: it
# was taken for a fixed reason). A fixed reason is a text: no test holds it, so none runs.
p_list() {
  edit 'ssh http' 'ssh ftp' conveyor/lib/m.sh; got=$(ran)
  [ "$got" = aone ] && ok "a change to a list of names set to a name runs the file's whole area" || no "list changed: ran '$got': $(cat "$T/out")"
}
p_reason() {
  edit 'before the end' 'before it ended' conveyor/lib/m.sh; got=$(ran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && ok "a reworded fixed reason no test holds runs no case file" || no "reason reworded: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# Its parse check still runs: a comment change in a file that does not parse fails the run, though no case file runs.
p_parse() {
  echo 'broken() { if true; then :; }' >> "$R/conveyor/lib/m.sh"; git -C "$R" commit -qam broken
  edit 'when it stops' 'when it ends' conveyor/lib/m.sh; got=$(ran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 1 ] && grep -q '^conveyor/lib/m.sh does not parse' "$T/out" \
    && ok "the parse check of a file changed in its comments alone fails the run when it does not parse" \
    || no "comment in a file that does not parse: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# D4: a reworded text that the Board's app.js compares and the engine's y.sh echoes runs their tests too: app.js's and
# y.sh's area (b's case), not the whole engine test (bug: the pick for y.sh took the runner it selected for a change to
# the runner, and ran ALL).
p_shared() {
  edit 'no longer applied' 'does not apply' conveyor/lib/m.sh; got=$(ran)
  [ "$got" = "app bone" ] && ok "a reworded text another source file holds runs that file's tests" || no "shared text reworded: ran '$got': $(cat "$T/out")"
}
# The same, when another message of m.sh keeps the text: one of its two copies reworded still loses an old text
# (bug: the texts were compared as sets, so it lost none, and no test ran). m.sh holds the old text too, so its area
# (aone) runs with app.js's test and y.sh's area.
p_sharedkept() {
  awk '!d && sub(/no longer applied/, "does not apply") { d = 1 } { print }' "$R/conveyor/lib/m.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/lib/m.sh"
  got=$(ran)
  [ "$got" = "aone app bone" ] && ok "a reworded copy of a text another message keeps runs the tests of the files that hold it" \
    || no "one copy of a shared text reworded: ran '$got': $(cat "$T/out")"
}
# Two messages that swap places are changed texts (issue 529; bug: the pieces were sorted before they were compared,
# so a swap changed none and only the parse check ran): b's case holds one, and app.js, y.sh and m.sh hold the other.
p_swap() {
  edit 'the engine could not read the project pack \$1' 'the change no longer applied $1' conveyor/lib/m.sh
  awk '!d && /^  echo "the change no longer applied"$/ { $0 = "  echo \"the engine could not read the project pack\""; d = 1 } { print }' \
    "$R/conveyor/lib/m.sh" > "$T/e" && cat "$T/e" > "$R/conveyor/lib/m.sh"
  got=$(ran)
  [ "$got" = "aone app bone" ] && ok "two messages that swap places run the tests of the files that hold them" \
    || no "two messages swapped: ran '$got': $(cat "$T/out")"
}
# A reworded Board label runs no test named after its file when no test holds the label.
p_board() {
  edit 'Show the reason' 'Show why' .claude/dashboard/app.js; got=$(ran)
  [ -z "$got" ] && [ "$(cat "$T/rc")" = 0 ] && ok "a reworded Board label no test holds runs no test" || no "Board label reworded: ran '$got', exit $(cat "$T/rc"): $(cat "$T/out")"
}
# D5: in a run again after a fix (the list's `changed` line), a reworded message runs only the case files that hold it;
# the runner passed before, so as any change m.sh would run its area (aone).
p_rerunchanged() {
  edit 'could not read' 'cannot read' conveyor/lib/m.sh
  printf 'change\tabc\npass\tconveyor/conveyor.test.sh\nchanged\tconveyor/lib/m.sh\n' > "$T/rerun"; got=$(ran)
  [ "$got" = bone ] && ok "a run again after a fix that reworded a message runs only the case files that hold it" \
    || no "run again, changed m.sh: ran '$got': $(cat "$T/out")"
}
# After main moved (the list's `main` line), what main changed in m.sh is read from the main of the last run (`from`):
# a reworded message runs b's case, which the change selects too (it changed y.sh and a.test.sh); with no `from`, as
# any change, a's.
p_rerunmain() {
  local was; was=$(git -C "$R" rev-parse HEAD)
  edit 'could not read' 'cannot read' conveyor/lib/m.sh; git -C "$R" commit -qam "main rewords"
  echo two >> "$R/conveyor/y.sh"; edit '^  :$' '  true' conveyor/tests/a.test.sh
  printf 'change\tabc\nbase\t%s\nfrom\t%s\npass\tconveyor/conveyor.test.sh\nmain\tconveyor/lib/m.sh\n' "$(git -C "$R" rev-parse HEAD)" "$was" > "$T/rerun"
  got=$(ran)
  [ "$got" = bone ] && ok "after main reworded a message, a run again runs only the case files that hold it" || no "main reworded m.sh: ran '$got': $(cat "$T/out")"
  sed -i.bak '/^from/d' "$T/rerun"; got=$(ran)
  [ "$got" = aone ] && ok "with no earlier main in the list, a file main changed runs its area" || no "no from line: ran '$got': $(cat "$T/out")"
}

for p in echo jq comment shebang shellcheck list reason parse shared sharedkept swap board rerunchanged rerunmain; do part "$p"; done
wait
for p in "${PARTS[@]}"; do
  cat "$T/$p.res"
  [ -e "$T/$p.end" ] || echo "not ok - part $p did not run to its end"
done | awk '/^(not )?ok - / { n++; sub(/ - /, " " n " - ") } { print } /^not ok / { bad = 1 } END { exit bad }'
