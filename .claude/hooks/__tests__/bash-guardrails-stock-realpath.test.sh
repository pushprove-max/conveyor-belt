#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Stock macOS realpath has no -m: it prints `illegal option -- m` and nothing on stdout. The write check read the
# empty answer as a path under no source folder, so on a Mac without GNU coreutils first on PATH an absolute source
# path passed (`sed -i s/a/b/ /abs/checkout/src/x.ts`). With such a realpath first on PATH, the verdict must be the
# one Linux gives.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/.claude/hooks/bash-guardrails.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
# The stand-in for /bin/realpath on macOS: -m is refused as BSD's is; it notes each call so the test knows it ran.
printf '%s\n' '#!/usr/bin/env bash' "echo called >> '$STUB/calls'" \
  'for a in "$@"; do [ "$a" = -m ] && { echo "realpath: illegal option -- m" >&2; exit 1; }; done' \
  'echo "realpath stub: only -m is modelled" >&2; exit 1' > "$STUB/realpath"
chmod +x "$STUB/realpath"

# The write cases name a checkout outside scratch space, never $ROOT: a checkout under /tmp is scratch to the write
# check by policy, so there $ROOT/src/x.ts passes and those cases would fail on a hook that is right. The write check
# reads only the path, so the folder need not exist.
SRC=/stock-realpath-checkout
# Links in scratch space to a checkout: GNU realpath -m follows them, so the fallback must too.
LINK=$STUB/card SRCLINK=$STUB/src-card
ln -s "$ROOT" "$LINK"
ln -s "$SRC" "$SRCLINK"
# A link to a link whose name ends in a newline: $(readlink) strips that newline, names no link, and the path
# reads as scratch.
ln -s "$SRC" "$STUB/nl"$'\n'
ln -s "$STUB/nl"$'\n' "$STUB/via-nl"
# A home folder reached by a link: a search of it is a search of every checkout under it.
ln -s "$ROOT/conveyor" "$STUB/home"

FAILED=0 RAN=()
run() { # <expected exit> <why> <command> [<HOME>]; the hook runs in the checkout root, as a session does
  local RC=0
  RAN+=("$3")
  jq -cn --arg cmd "$3" --arg cwd "$ROOT" '{session_id:"stock-realpath",cwd:$cwd,tool_input:{command:$cmd}}' \
    | (cd "$ROOT" && HOME=${4:-$HOME} PATH=$STUB:$PATH bash "$HOOK" >/dev/null 2>&1) || RC=$?
  [ "$RC" -eq "$1" ] || { echo "FAIL: $2: exit $RC, wanted $1, for: $3$(said)" >&2; FAILED=1; }
}
run 2 "an absolute source path passed the write check" "sed -i s/a/b/ $SRC/src/x.ts"
# The text resolve must fold `..`: the path starts with /tmp but names the checkout's src folder.
run 2 "an absolute source path through /tmp/.. passed the write check" "sed -i s/a/b/ /tmp/..$ROOT/src/x.ts"
# The relative arm resolves a path with `..` too: an empty answer there reads as no source folder and passes.
run 2 "a relative source path with .. passed the write check" "sed -i s/a/b/ conveyor/../src/x.ts"
run 2 "an absolute source path through /tmp/.. passed the write check" "sed -i s/a/b/ /tmp/..$SRC/src/x.ts"
run 0 "a scratch path was refused" "sed -i s/a/b/ /tmp/x.ts"
# Read as text, the link's path is under scratch space and passes; resolved, it is the checkout's src folder.
run 2 "a source path through a scratch symlink passed the write check" "sed -i s/a/b/ $SRCLINK/src/x.ts"
# The search check resolves paths too: a bounded folder must still pass, and the checkout reached by a link must not.
run 2 "a source path through a link to a newline-named link passed the write check" "sed -i s/a/b/ $STUB/via-nl/src/x.ts"
run 0 "a search of one checkout folder was refused" "grep -rn foo $ROOT/conveyor/lib | head"
run 2 "a search of the whole checkout through a scratch symlink passed" "grep -rn foo $LINK | head"
# Each search case below fails if its one call site goes back to `realpath -m`.
# root_like's home test: home is a link, so only a resolved home matches the resolved operand.
run 2 "a search of a linked home folder passed" "grep -rn foo ~ | head" "$STUB/home"
# Each glob match is resolved: an empty answer reads as / and refuses a bounded glob.
run 0 "a glob search of one checkout folder was refused" "grep -rn foo $ROOT/conveyor/lib/*.sh | head"
# A cd moves the search base only when its target resolves; otherwise `.` stays the checkout root.
run 0 "a search after cd to an absolute checkout folder was refused" "cd $ROOT/conveyor/lib && grep -rn foo . | head"
run 0 "a search after cd to a relative checkout folder was refused" "cd conveyor/lib && grep -rn foo . | head"
[ -s "$STUB/calls" ] || {
  printf 'FAIL: the hook never ran the stub realpath, so these commands did not test it:%s\n' "$(printf ' [%s]' "${RAN[@]}")" >&2
  FAILED=1
}
[ "$FAILED" = 0 ] || exit 1
echo "PASS"
