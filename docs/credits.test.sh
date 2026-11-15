#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Credits page, docs/credits.md, names every work Conveyor ships a copy of or installs: each licence file in the
# repository (a file whose name holds LICENSE, outside node_modules; the root LICENSE is Conveyor's own) by its path,
# and each package in package.json, .claude/scripts/requirements.txt and docs/demo/package.json by its name in
# backticks. Bug caught: a vendored copy or a new dependency lands and its author gets no credit.
# Usage: credits.test.sh (checks this repository, then two fixtures that must fail).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)

check() { # <root>: prints one line per work Credits does not name; exit 0 when none, 1 with any
  python3 -I - "$1" <<'EOF'
import json, os, re, sys

root = sys.argv[1]
def fail(why):
    print("FAIL [credits]: " + why)
    sys.exit(1)

try:
    credits = open(os.path.join(root, "docs", "credits.md"), encoding="utf-8").read()
except OSError as e:
    fail("docs/credits.md cannot be read: %s" % e)
named = {t.lower() for t in re.findall(r"`([^`\n]+)`", credits)}

missing = []
for d, dirs, files in os.walk(root):
    dirs[:] = sorted(x for x in dirs if x not in ("node_modules", ".git"))
    for f in sorted(files):
        rel = os.path.relpath(os.path.join(d, f), root)
        if "license" in f.lower() and rel != "LICENSE" and rel.lower() not in named:
            missing.append("licence file " + rel)

for rel in ("package.json", "docs/demo/package.json"):
    p = os.path.join(root, rel)
    if not os.path.exists(p):
        continue
    try:
        pkg = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError) as e:
        fail("%s cannot be read: %s" % (rel, e))
    for key in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
        for name in pkg.get(key) or {}:
            if name.lower() not in named:
                missing.append("package %s (%s)" % (name, rel))

rel = ".claude/scripts/requirements.txt"
try:
    lines = open(os.path.join(root, rel), encoding="utf-8").read().splitlines()
except OSError as e:
    fail("%s cannot be read: %s" % (rel, e))
for line in lines:
    line = line.strip()
    if not line or line.startswith(("#", "-")):
        continue
    name = re.match(r"[A-Za-z0-9._-]+", line).group(0)
    if name.lower() not in named:
        missing.append("package %s (%s)" % (name, rel))

for w in missing:
    print("FAIL [credits]: docs/credits.md does not name the " + w)
sys.exit(1 if missing else 0)
EOF
}

rc=0
out=$(check "$ROOT") || { echo "$out" >&2; rc=1; }

# Fixtures: the repository's Credits page and manifests, plus one work Credits does not name. Each must fail, naming it.
W=$(mktemp -d) || exit 1; trap 'rm -rf "$W"' EXIT
fixture() { # <dir>
  mkdir -p "$1/.claude/scripts" "$1/docs" && cp "$ROOT/package.json" "$1/" && cp "$ROOT/docs/credits.md" "$1/docs/" \
    && cp "$ROOT/.claude/scripts/requirements.txt" "$1/.claude/scripts/"
}
expect_fail() { # <dir> <text the failure must name>
  local o
  if o=$(check "$1"); then
    echo "FAIL [credits]: a fixture with $2 not in Credits passed" >&2; rc=1
  elif ! grep -qF -- "$2" <<<"$o" || [ "$(grep -c 'does not name' <<<"$o")" != 1 ]; then
    echo "FAIL [credits]: the fixture with $2 failed without naming it alone: $o" >&2; rc=1
  fi
}
fixture "$W/lic" && mkdir -p "$W/lic/vendor/left" && echo 'MIT License' > "$W/lic/vendor/left/LICENSE.txt"
expect_fail "$W/lic" "licence file vendor/left/LICENSE.txt"
fixture "$W/pkg" && mkdir -p "$W/pkg/docs/demo" && echo '{"devDependencies": {"left-pad": "1.3.0"}}' > "$W/pkg/docs/demo/package.json"
expect_fail "$W/pkg" "package left-pad (docs/demo/package.json)"

[ $rc = 0 ] && echo "ok credits"
exit $rc
