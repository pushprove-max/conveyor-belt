#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 30
# Every source file the project writes starts with `SPDX-License-Identifier: Apache-2.0` in its language's comment
# form, on the line after the shebang or the HTML doctype where there is one (CONTRIBUTING.md, Rules). The source files
# are the tracked shell, Python, JavaScript, TypeScript, CSS and HTML files, the YAML under .github/ and any file with
# no extension that starts with a shebang; the vendored files (.claude/dashboard/vendor/) keep their own license.
# Bug it catches: a new source file, from a card or a pull request, with no license header; the failure names it.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
fail() { echo "FAIL [spdx]: $*" >&2; exit 1; }

# missing <repo>: each source file of the git repository at <repo> without the header, one a line.
missing() {
  local f b
  local -a src=()
  while IFS= read -r -d '' f; do
    b=${f##*/}
    case $f in
      .claude/dashboard/vendor/*) ;;
      *.sh | *.py | *.js | *.mjs | *.cjs | *.ts | *.tsx | *.css | *.html | .github/*.yml | .github/*.yaml) src+=("$f") ;;
      *) [[ $b != *.* ]] && [ "$(head -c 2 "$1/$f")" = '#!' ] && src+=("$f") ;;
    esac
  done < <(git -C "$1" ls-files -z) || return 2
  [ ${#src[@]} -gt 0 ] || return 0
  (cd "$1" && awk '
    BEGIN { H = "SPDX-License-Identifier: Apache-2.0" }
    function want(f) {
      if (f ~ /\.(js|mjs|cjs|ts|tsx)$/) return "// " H
      if (f ~ /\.css$/) return "/* " H " */"
      if (f ~ /\.html$/) return "<!-- " H " -->"
      return "# " H
    }
    FNR == 1 && (/^#!/ || (FILENAME ~ /\.html$/ && tolower($0) ~ /^<!doctype /)) { next }
    { if ($0 != want(FILENAME)) print FILENAME; nextfile }
  ' "${src[@]}")
}

# The repository itself.
out=$(missing "$SRC") || fail "the source files could not be read: $out"
[ -z "$out" ] || fail "these source files do not start with the SPDX-License-Identifier: Apache-2.0 line: $(echo $out)"

# A fixture: each kind of file with and without the header, and a vendored file without it.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
H='SPDX-License-Identifier: Apache-2.0'
mkdir -p "$T/.github/workflows" "$T/.claude/dashboard/vendor" "$T/bin"
printf '#!/usr/bin/env bash\n# %s\necho ok\n' "$H" > "$T/good.sh"
printf '// %s\nexport {}\n' "$H" > "$T/good.ts"
printf '<!doctype html>\n<!-- %s -->\n<html></html>\n' "$H" > "$T/good.html"
printf '/* %s */\nbody {}\n' "$H" > "$T/good.css"
printf '#!/usr/bin/env python3\nprint(1)\n' > "$T/bad.py"
printf '// a comment first\n// %s\n' "$H" > "$T/late.js"
printf '# %s\nbody {}\n' "$H" > "$T/wrongform.css"
printf 'name: x\n' > "$T/.github/workflows/bad.yml"
printf '#!/bin/sh\necho run\n' > "$T/bin/tool"
printf 'export const x = 1\n' > "$T/.claude/dashboard/vendor/lib.js"
printf '# Notes\n' > "$T/notes.md"
git -C "$T" init -q && git -C "$T" add -A || fail "the fixture repository could not be made"
out=$(missing "$T" | sort | tr '\n' ' ')
[ "$out" = '.github/workflows/bad.yml bad.py bin/tool late.js wrongform.css ' ] \
  || fail "the check named [$out], not the five fixture files without the header in their form"
echo "ok [spdx]: every source file starts with the SPDX header; a fixture file without it is named"
