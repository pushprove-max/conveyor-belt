#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Benchmark phase 0, gate 2: replays one recorded review through reviewed() (lib/review.sh) of one engine version, with
# a throwaway state, and keeps what that replay's reviewer read as a snap (promptcheck.sh) to compare with the
# recorded one. Run it once for each engine version, then `promptcheck.sh compare <recorded snap> <out>/snap`.
# Every reviewer runs in the worktree, and a Claude or OpenCode review's prompt names the worktree's path and the
# engine folder's, so the replay puts the worktree and the engine at the recorded paths (the snap's parts worktree
# and engine). Those places, the cards folder above the worktree and the
# engine folder, must not exist: the replay makes them and removes them when it ends, so it runs in a container (or
# under a scratch folder), never beside live cards. Everything else it writes is under <out>: a clone of <main> (with
# <main>'s .conveyor/ pack copied over it), the state, the config, TMPDIR and the CLI shims.
# Each launch of a reviewer CLI (claude, codex, opencode; not --version, debug or models) goes through a shim in
# <out>/bin that adds a line to <out>/launches and keeps the prompt it read on stdin as <out>/prompt.<n>, then runs
# the CLI found on PATH before the replay began: a fixture CLI in tests, the real one in the container. Every retry,
# reviewed()'s second attempt and each apitries() try alike, is a launch, so the count is the replay's sessions.
# Usage: replay.sh <engine folder> <main checkout> <recorded snap> <out folder>
# Prints one JSON line, also kept as <out>/result.json: {sessions, seconds (the wall time, the API waits and
# REVIEW_PAUSE included), rc (reviewed()'s exit), verdict}. Exits 2 on a wrong argument, 1 when no reviewer CLI ran.
set -euo pipefail
[ $# = 4 ] || { echo "usage: replay.sh <engine folder> <main checkout> <recorded snap> <out folder>" >&2; exit 2; }
SRC=$(cd "$1" && pwd -P) MAIN=$2 IN=$3 OUT=$4
BENCH=$(cd "$(dirname "$0")" && pwd -P)
for p in brief head staged.diff engine worktree; do [ -f "$IN/$p" ] || { echo "replay: $IN has no $p" >&2; exit 2; }; done
[ -f "$SRC/conveyor.sh" ] && [ -f "$SRC/commands/run.sh" ] || { echo "replay: $SRC is no engine folder" >&2; exit 2; }
[ -d "$MAIN/.conveyor" ] || { echo "replay: $MAIN has no .conveyor pack" >&2; exit 2; }
AT=$(<"$IN/engine") WT=$(<"$IN/worktree"); CARDS=$(dirname "$WT")
for p in "$AT" "$CARDS" "$OUT"; do
  [[ $p == /* ]] || { echo "replay: $p is no absolute path" >&2; exit 2; }
  [ ! -e "$p" ] && [ ! -L "$p" ] || { echo "replay: $p already exists: the replay makes it and removes it, so it runs only where it is not" >&2; exit 2; }
done
[[ $AT/ != "$CARDS"/* && $CARDS/ != "$AT"/* ]] || { echo "replay: the engine folder and the cards folder overlap" >&2; exit 2; }
mkdir -p "$OUT/bin" "$OUT/state" "$OUT/config" "$OUT/tmp"; : > "$OUT/launches"
# From here, the two places made outside <out> go however the replay ends, each from the first folder of its path the
# replay made.
made() { local p=$1; while [ ! -e "$(dirname "$p")" ]; do p=$(dirname "$p"); done; printf '%s' "$p"; } # <path>
MADE=("$(made "$AT")" "$(made "$CARDS")")
trap 'rm -rf "${MADE[@]}"' EXIT
mkdir -p "$AT" "$CARDS" && cp -a "$SRC/." "$AT/"
git clone -q "$MAIN" "$OUT/main" && git -C "$OUT/main" checkout -q --detach "$(<"$IN/head")" && cp -a "$MAIN/.conveyor/." "$OUT/main/.conveyor/"
git -C "$OUT/main" worktree add -q --detach "$WT" HEAD
[ ! -s "$IN/staged.diff" ] || git -C "$WT" apply --index --binary --whitespace=nowarn "$(cd "$IN" && pwd -P)/staged.diff"
[ ! -f "$IN/trailers" ] || cp "$IN/trailers" "$WT.trailers"
[ ! -f "$IN/context/port.diff" ] || cp "$IN/context/port.diff" "$WT.port"
[ ! -d "$IN/context/rounds" ] || cp -R "$IN/context/rounds" "$WT.rounds"
for c in claude codex opencode; do
  r=$(command -v "$c" 2>/dev/null) || continue
  printf '#!/usr/bin/env bash\ncase "${1:-}" in --version|debug|models) exec %q "$@" ;; esac\nn=$(( $(wc -l < %q) + 1 ))\necho %q >> %q\nexec %q "$@" < <(tee %q.$n)\n' \
    "$r" "$OUT/launches" "$c" "$OUT/launches" "$r" "$OUT/prompt" > "$OUT/bin/$c"
  chmod +x "$OUT/bin/$c"
done
s=$SECONDS rc=0
# shellcheck disable=SC1091 # the engine version under replay, loaded as conveyor.sh <command> loads it
( export CONVEYOR_MAIN=$OUT/main CONVEYOR_CARDS=$CARDS XDG_STATE_HOME=$OUT/state XDG_CONFIG_HOME=$OUT/config TMPDIR=$OUT/tmp PATH=$OUT/bin:$PATH
  set +eu; . "$AT/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$AT/commands/run.sh")" && names \
    && reviewed "$WT" "$(cat "$IN/brief")" ) > "$OUT/reviewed.out" 2>&1 || rc=$?
s=$((SECONDS - s)) n=$(wc -l < "$OUT/launches")
v=$( (grep -o 'VERDICT: [A-Z-]*' "$WT.review" 2>/dev/null || echo 'VERDICT: none') | tail -n 1 | cut -d' ' -f2)
[ ! -f "$WT.review" ] || cp "$WT.review" "$OUT/review"
[ "$n" -gt 0 ] && [ -f "$OUT/prompt.1" ] || { echo "replay: no reviewer CLI ran; see $OUT/reviewed.out" >&2; exit 1; }
"$BENCH/promptcheck.sh" snap "$AT" "$WT" "$OUT/prompt.1" "$OUT/snap" "$IN/brief"
jq -cn --argjson n "$n" --argjson s "$s" --argjson rc "$rc" --arg v "$v" '{sessions: $n, seconds: $s, rc: $rc, verdict: $v}' | tee "$OUT/result.json"
