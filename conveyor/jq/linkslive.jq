# linkslive() in lib/testlist.sh: the test links (the input, .conveyor/test-links.json) less each link the last passes
# rule out, as that function says. $t: the test files that have a pass on record ($TESTCACHE), one a line. A project's
# own selector of the changed tests reads its links through this file too, so it and the engine follow the same links.
def eng: test("^conveyor/tests/[^/]+\\.test\\.sh$");
def src: eng or test("^conveyor/lib/[^/]+\\.sh$");
($t | split("\n") | map(select(. != "") | {key: ., value: true}) | from_entries) as $p
| objects | with_entries(.key as $k | if ($k | startswith("main:")) or (.value | type) != "array" then .
    else .value |= map(strings | select(($p[.] | not) or (eng and ($k | src)))) end)
