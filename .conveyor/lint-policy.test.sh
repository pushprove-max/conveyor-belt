#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# This pack's lint field read by the engine's lint-policy stop (lintpolicy, conveyor/lib/lint.sh). A change that only
# removes lines from a file that the files of a `ratchet: false` command match needs no owner's yes. Bugs it catches:
# a change that only deletes lines of a linter (.conveyor/lint-funcs.sh, .conveyor/lint-shell.sh) lands without the
# owner's yes, a change that only removes lines of ruff.toml (ruff's config), .conveyor/lint-js.sh or eslint.config.js
# (ESLint's command and config) lands without it, and a change that only removes an exemption from
# .conveyor/size-exempt.txt stops for one.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
no() { echo "not ok - $*"; fails=1; }
# shellcheck source=/dev/null
. "$ROOT/conveyor/lib/lint.sh"
LINT=$(jq -c .lint "$ROOT/.conveyor/project.json") || exit 1
g() { git -C "$T" "$@"; }
g init -q && g config user.email t@example.com && g config user.name t || exit 1
mkdir -p "$T/.conveyor"
for f in .conveyor/lint-funcs.sh .conveyor/lint-shell.sh .conveyor/lint-funcs.awk .conveyor/size-exempt.txt ruff.toml \
  .conveyor/lint-js.sh eslint.config.js; do printf 'one\ntwo\n' > "$T/$f"; done
g add -A && g commit -qm base || exit 1
base=$(g rev-parse HEAD)
# policy <file>: lintpolicy's listed paths when the staged change only removes the last line of <file>.
policy() {
  g reset -q --hard "$base" && printf 'one\n' > "$T/$1" && g add -A || exit 1
  lintpolicy "$T" "$base" "$LINT" | sed 1d
}
for f in .conveyor/lint-funcs.sh .conveyor/lint-shell.sh .conveyor/lint-funcs.awk ruff.toml .conveyor/lint-js.sh eslint.config.js; do
  [ "$(policy "$f")" = "$f" ] || no "a change that only deletes lines of $f is not taken for lint policy"
done
[ -z "$(policy .conveyor/size-exempt.txt)" ] || no "a change that only removes an exemption is taken for lint policy"
[ $fails = 0 ] || exit 1
echo "ok - lint policy of this pack"
