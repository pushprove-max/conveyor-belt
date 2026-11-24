#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The plugin's three test rules (issue #400), in the card rules every card and review reads and in the engine tests'
# speed notes where test authors look. Bug it catches: a rule dropped or reworded in one place, or left without the
# reason and the measured cut that make a reviewer hold to it, so cards again add wrappers that run tests twice, cases
# that run fixtures one after another, and whole card runs to prove one function.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
rc=0
# Each bullet of a Markdown file as one line (its wrapped lines joined), so a check never depends on where a line wraps.
bullets() { awk '/^- /{if (b != "") print b; b=$0; next} /^  /{if (b != "") {sub(/^ +/, ""); b=b " " $0}; next} {if (b != "") print b; b=""} END{if (b != "") print b}' "$1"; }
# rule <file> <rule's words> <words of its reason or number>...: one bullet of <file> holds them all.
rule() {
  local f=$1 b p=$ROOT/$1; shift
  [[ $f != /* ]] || p=$f
  b=$(bullets "$p" | grep -F -- "$1")
  [ "$(grep -c . <<<"$b")" = 1 ] || { echo "not ok - $f: no single rule \"$1\""; rc=1; return; }
  shift
  for w; do
    grep -qF -- "$w" <<<"$b" || { echo "not ok - $f: the rule has no \"$w\": $b"; rc=1; return; }
  done
  echo "ok - $f: $b" | cut -c1-120
}
for f in .conveyor/card-rules.md conveyor/tests/speed/README.md; do
  rule "$f" 'No wrapper that only runs other tests again' 'proves nothing' '#357 removed two' '31 s of every run cut'
  rule "$f" 'A case that runs several fixtures one after another is split into one case per fixture' \
    'side by side' '`metrics`' '79% cut' '`stall`' '71%'
  rule "$f" 'A case that proves one engine function calls that function; a whole card run is kept for what only a whole card proves' \
    'pays for the loop' '`testfails`' '76% cut' '#362' '`testrec`' '89%' '#371'
done
# Issue #1009. Bug it catches: the rule dropped, or left without its files, its cost or the reviewer's finding, so a
# card again puts a fix in the suite's runner the issue did not name and the next release runs every test file.
rule .conveyor/card-rules.md 'only when its issue names that file or setting' '`.conveyor/test-full.sh`' \
  '`conveyor/conveyor.test.sh`' "pack's \`test\` settings" 'next release run every test file' 'why no other place works' 'P2 finding'
# Issue #1577. Bug it catches: the timing rule dropped from the builder's rules or from the fix prompt, so a lock, retry,
# snapshot or merge change is again tested only by a helper or a sleep that passes while the real command stays racy.
# It reads the text the engine hands a card, not the source files: cardrules() must append this project's rules, and
# fixprompt() must append FIX, or a card never sees the rule.
T=$(mktemp -d) && trap 'rm -rf "$T"' EXIT
( export CONVEYOR_MAIN=$ROOT CONVEYOR_CARDS=$T/cards; . "$ROOT/conveyor/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep '^\. "\$HERE/lib/' "$ROOT/conveyor/commands/run.sh")" \
  && cardrules '{"title": "t", "body": ""}' > "$T/rules" && fixprompt CARD 'E1 a finding' > "$T/fix" ) 2>&1 \
  || { echo 'not ok - the card rules or the fix prompt could not be made'; exit 1; }
rule "$T/rules" 'A build or fix that changes a lock, a retry, a snapshot or a merge decision' \
  'names what must stay true and the other reader or writer' 'forces that one to act at the weak point through the real caller' \
  'pause the idle merge after its last rule read, change the rule, resume, and assert no merge was asked' \
  'asserts the stored state or the outside action, never after a sleep'
# The fix prompt's rule is one sentence: each instruction of it must stay, in its order.
tr '\n' ' ' < "$T/fix" | tr -s ' ' | grep -qF 'name what must stay true and the other reader or writer, then make the test force that one to act at the weak point through the real caller, and assert the stored state or the outside action, never after a sleep' \
  || { echo 'not ok - the fix prompt fixprompt() returns has no timing rule with all its instructions'; rc=1; }
# The rule Only the Test step runs tests on (rules.teststeponly). Bug it catches: this project's own lines that tell a
# session to run its cases and test-changed.sh sit outside the paragraph cardrules() leaves out with the rule on, so a
# session is still told to run tests.
( export CONVEYOR_MAIN=$ROOT CONVEYOR_CARDS=$T/cards CARDCTL='{"rules": {"teststeponly": true}}'; . "$ROOT/conveyor/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep '^\. "\$HERE/lib/' "$ROOT/conveyor/commands/run.sh")" && cardrules '{"title": "t", "body": ""}' > "$T/rules.on" ) 2>&1 \
  || { echo 'not ok - the card rules could not be made with the rule Only the Test step runs tests on'; exit 1; }
for w in 'conveyor/conveyor.test.sh <case>' '.conveyor/test-changed.sh` at most once' 'Your own test runs'; do
  ! grep -qF -- "$w" "$T/rules.on" || { echo "not ok - with the rule Only the Test step runs tests on, this project's card rules still hold \"$w\""; rc=1; }
done
grep -qF "read the last Test step's result" "$T/rules.on" \
  || { echo "not ok - with the rule Only the Test step runs tests on, this project's card rules do not say to read the last Test step's result"; rc=1; }
exit $rc
