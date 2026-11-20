#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: how many programs one snapshot (lib/snapshot.sh) starts.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The Board reads a snapshot again and again, and each program the snapshot starts is a fork and an exec. Before
# issue 2, one snapshot of this fixture started SNAPEXEC_WAS programs: a basename for each file name, an uname at each
# system check, a `true` for each test slot counted, a jq for each read of the same control record, and more, where
# the shell's own expansions, one kept answer or a lock tried on the shell's own descriptor do the same. Issue 993:
# the Claude routes, the models allowed and the host's report worked out again by jq in each of the snapshot's
# subshells (health, each seat, the guard's accounts), and a jq for each list of test files, took it to 283. A shim of
# every program on PATH notes its name, then runs the program. Bug it catches: the snapshot starting programs again
# where bash needs none.
SNAPEXEC_WAS=269
t_snapexec() {
  local root=$T/$CASE/brew log=$T/$CASE/execs d f n out; local shim=$root/bin; local -A seen=()
  export XDG_CONFIG_HOME=$T/$CASE/config
  # Its own slot pool: the shared one's slots are held by other cases now and then.
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 4, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup "[$(issue 1 2026-01-01),$(issue 2 2026-01-02),$(issue 3 2026-01-03)]"; mkdir -p "$ST"
  # Two cards landed, one at its review.
  jq -cn 'range(1; 4) as $i | ["picked", "worktree", "brief", "build", "review", "test", "landed"][: if $i == 3 then 5 else 7 end] | to_entries[]
    | {card: "c\($i)", issue: $i, step: .value, time: (1767225600 + $i * 100 + .key | todate), tokens: {claude: 0, codex: 0}, result: "ok", sha: "", reason: ""}
      + {picked: {title: "card \($i)", branch: "b\($i)"}, review: {result: "GO"}, test: {result: "pass", sec: 60}, landed: {sha: "abc\($i)", product: false}}[.value] // {}' > "$ST/cards.jsonl"
  # The first snapshot makes the kept summaries; the one counted is a Board's next.
  loop snapshot --fresh > /dev/null || fail "the first snapshot exited non-zero"
  mkdir -p "$shim"; local IFS=:
  for d in $PATH; do
    for f in "$d"/*; do
      n=${f##*/}; [[ -z ${seen[$n]:-} && -x $f && ! -d $f && $n =~ ^[A-Za-z0-9._+-]+$ ]] || continue
      seen[$n]=1; printf '#!/bin/sh\necho %s >> %q\nexec %q "$@"\n' "$n" "$log" "$f" > "$shim/$n"
    done
  done
  unset IFS
  # On macOS the engine takes Homebrew's prefix from the gtimeout on PATH (p_brewprefix), here the shim's, and wants
  # its gnubin and openssl@3 folders under it (p_tools, p_path): the shim's root has each, with a shim of each program.
  if p_darwin; then
    local pre; pre=$(p_brewprefix)
    for d in opt/coreutils/libexec/gnubin opt/findutils/libexec/gnubin opt/gnu-sed/libexec/gnubin opt/grep/libexec/gnubin opt/openssl@3/bin; do
      [ -d "$pre/$d" ] || continue; mkdir -p "$root/$d"
      for f in "$pre/$d"/*; do
        n=${f##*/}; [[ -x $f && ! -d $f && $n =~ ^[A-Za-z0-9._+-]+$ ]] || continue
        printf '#!/bin/sh\necho %s >> %q\nexec %q "$@"\n' "$n" "$log" "$f" > "$root/$d/$n"
      done
    done
  fi
  find "$root" -type f -exec chmod +x {} +
  out=$(PATH=$shim loop snapshot --fresh) || fail "the snapshot under the shim exited non-zero"
  [ "$(jq -c '[.belt[].card]' <<<"$out")" = '["c3"]' ] || fail "the snapshot under the shim is not the fixture's: $(jq -c .belt <<<"$out")"
  n=$(wc -l < "$log")
  [ "$n" -lt "$SNAPEXEC_WAS" ] || fail "one snapshot started $n programs, not fewer than the $SNAPEXEC_WAS before issue 2: $(sort "$log" | uniq -c | sort -rn | head -n 12 | tr -s ' \n' ' ')"
}
