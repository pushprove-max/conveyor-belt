#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Issue 1821. `bash .conveyor/where.sh <function>` tells a build or fix session where an engine function is defined,
# which functions call it, which tests run it and which cases the coverage map says ran it, so the session need not
# read whole files to find them. Each check runs where.sh on a small fixture checkout of its own.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bad=0; n=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; bad=1; }
# sum <line>...: the coverage map's sum of a function of these lines (sumsof of test-changed.sh: the cksum of its
# lines joined by \001).
sum() { local IFS=$'\001'; cksum <<<"$*" | cut -d' ' -f1; }
# The fixture: target() in a.sh, called by usesit() in b.sh (a comment in other() names it too, and calls nothing);
# b.test.sh runs usesit, c.test.sh and d.test.tsx name target in a comment only (# in one, // in the other); the
# coverage map says case bcase ran target.
B=$T/base
mkdir -p "$B/.conveyor" "$B/conveyor/lib" "$B/conveyor/tests"
cp "$HERE/where.sh" "$HERE/funcs.awk" "$B/.conveyor/"
printf 'target() {\n  echo hi\n}\nother() {\n  # target is not called here\n  :\n}\n' > "$B/conveyor/lib/a.sh"
printf '#!/usr/bin/env bash\nusesit() {\n  local x=1\n  target "$x"\n}\n' > "$B/conveyor/lib/b.sh"
printf 't_b() {\n  usesit\n}\n' > "$B/conveyor/tests/b.test.sh"
printf '# target\nt_c() {\n  :\n}\n' > "$B/conveyor/tests/c.test.sh"
printf 'it("d", () => {\n  // target\n  /* target\n   * target */\n});\n' > "$B/conveyor/tests/d.test.tsx"
printf '%s\n' '{"area": "a", "file": "conveyor/lib/a.sh"}' '{"area": "a", "file": "conveyor/lib/b.sh"}' \
  '{"area": "a", "test": "b.test.sh"}' '{"area": "a", "test": "c.test.sh"}' > "$B/.conveyor/engine-areas.json"
printf '%s\n' '{"testfile": 1, "path": "conveyor/conveyor.test.sh"}' '{"unit": 1, "testfile": 1, "case": "bcase"}' \
  "{\"file\": \"conveyor/lib/a.sh\", \"fn\": \"target\", \"sum\": \"$(sum 'target() {' '  echo hi' '}')\", \"units\": [1]}" \
  > "$B/.conveyor/coverage.jsonl"
git -C "$B" init -q || { echo "not ok - the fixture checkout could not be made"; exit 1; }
# fixture <name>: a copy of the base fixture in $T/<name>, in F.
fixture() { F=$T/$1; cp -a "$B" "$F"; }
# where <function>: where.sh run in F on it, its output in out and its exit status in rc.
where() { out=$(bash "$F/.conveyor/where.sh" "$1" 2>&1); rc=$?; }

# Bug it catches: a session told of no caller in another sourced file, no test that runs the function through a
# caller, or no case the map holds, so it greps and reads whole files again; or told of a test file that names the
# function only in a comment (a shell #, a TypeScript // or /* */), so it reads a test that does not run it.
fixture all; where target
want=$'def conveyor/lib/a.sh:1\ncaller conveyor/lib/b.sh:4 usesit\ntest conveyor/tests/b.test.sh\ncovered conveyor/conveyor.test.sh bcase'
[ "$rc" = 0 ] && [ "$out" = "$want" ] \
  && ok "where.sh target gives its definition, its caller in b.sh, the test that names the caller and the case the map holds" \
  || no "where.sh target: exit $rc, output '$out', want '$want'"

# Bug it catches: a row traced before the function changed read as current, so the session trusts cases that may no
# longer run the function.
fixture stale; printf 'target() {\n  echo bye\n}\n' > "$F/conveyor/lib/a.sh"; where target
want=$'def conveyor/lib/a.sh:1\ncaller conveyor/lib/b.sh:4 usesit\ntest conveyor/tests/b.test.sh\ncoverage row older than the function\ncovered conveyor/conveyor.test.sh bcase'
[ "$rc" = 0 ] && [ "$out" = "$want" ] \
  && ok "where.sh target, changed since the map was traced, says the coverage row is older before its cases" \
  || no "where.sh target with a.sh's target() changed after the trace: exit $rc, output '$out', want '$want'"

# Bug it catches: a helper that many functions call fills the session's context with every caller.
fixture many
for i in $(seq 1 26); do printf 'c%d() {\n  target\n}\n' "$i"; done > "$F/conveyor/lib/many.sh"
echo '{"area": "a", "file": "conveyor/lib/many.sh"}' >> "$F/.conveyor/engine-areas.json"
where target
[ "$rc" = 0 ] && [ "$(grep -c '^caller ' <<<"$out")" = 25 ] \
  && [ "$(grep -A1 '^caller conveyor/lib/many.sh:71 c24$' <<<"$out" | tail -n 1)" = 'and 2 more' ] \
  && ok "where.sh target with 27 callers lists 25 of them, then and 2 more" \
  || no "where.sh target with 27 callers (usesit and c1 to c26 of many.sh): exit $rc, output '$out'"

# Bug it catches: a unit that ran target in two files it is defined in (two rows of the map) was listed twice, a line
# that tells the session nothing and takes the place of another case under the limit.
fixture twodefs; printf 'target() {\n  echo hi\n}\n' > "$F/conveyor/lib/d.sh"
echo '{"area": "a", "file": "conveyor/lib/d.sh"}' >> "$F/.conveyor/engine-areas.json"
sed -n 's/conveyor\/lib\/a[.]sh/conveyor\/lib\/d.sh/p' "$F/.conveyor/coverage.jsonl" >> "$F/.conveyor/coverage.jsonl"
where target
[ "$rc" = 0 ] && [ "$(grep -c '^def ' <<<"$out")" = 2 ] \
  && [ "$(grep '^covered ' <<<"$out")" = 'covered conveyor/conveyor.test.sh bcase' ] \
  && ok "where.sh target, defined in a.sh and d.sh with unit 1 in both rows, lists that unit once" \
  || no "where.sh target defined in a.sh and d.sh, both map rows with unit 1 (bcase): exit $rc, output '$out'"

# Bug it catches: a function that many test files name, or many cases ran, fills the session's context with each.
fixture limits
for i in $(seq 1 20); do printf 't_x() {\n  usesit\n}\n' > "$F/conveyor/tests/x$i.test.sh"; done
sed -i.bak "s/\"units\": \[1\]/\"units\": [$(seq -s, 1 21)]/" "$F/.conveyor/coverage.jsonl"
for i in $(seq 2 21); do echo "{\"unit\": $i, \"testfile\": 1, \"case\": \"c$i\"}"; done >> "$F/.conveyor/coverage.jsonl"
where target
[ "$rc" = 0 ] && [ "$(grep -c '^test ' <<<"$out")" = 20 ] && [ "$(grep -c '^covered ' <<<"$out")" = 20 ] \
  && [ "$(grep -A1 '^test ' <<<"$out" | tail -n 1)" = 'and 1 more' ] \
  && [ "$(grep -A1 '^covered ' <<<"$out" | tail -n 1)" = 'and 1 more' ] \
  && ok "where.sh target with 21 test files and 21 covered units lists 20 of each, each then and 1 more" \
  || no "where.sh target with 21 test files naming usesit (b and x1 to x20) and units 1 to 21 in its row: exit $rc, output '$out'"

# Bug it catches: a name no engine file defines read as found, with an empty answer the session cannot tell from one
# with no callers.
fixture unknown; where nope
[ "$rc" = 1 ] && [ "$out" = "no function nope" ] && ok "where.sh nope, a name no engine file defines, exits 1 with no function nope" \
  || no "where.sh nope: exit $rc, output '$out', want exit 1 and 'no function nope'"
echo "1..$n"
exit "$bad"
