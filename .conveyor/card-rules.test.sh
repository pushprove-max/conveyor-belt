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
  local f=$1 b; shift
  b=$(bullets "$ROOT/$f" | grep -F -- "$1")
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
exit $rc
