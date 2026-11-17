# SPDX-License-Identifier: Apache-2.0
# The machine room's reading: how hard pressed the machine is now, as one state, Steady, Busy or Strained. Sourced,
# never run (lib/pick.sh for the cards, lib/slots.sh for the test slots, lib/views.sh health shows it).
# The figures: on Linux the pressure stall information, /proc/pressure/cpu and /proc/pressure/memory "some avg10" (the
# share of the last 10 s in which some task waited for the CPU, or for memory, in percent); on every system the wake
# delay (how late a 10 ms sleep wakes, in ms: the middle of three, taken at each reading, and a loop reads at each
# turn); and, where no memory pressure is read (macOS), the free memory in MB. The state is Strained when a figure
# reaches its Strained threshold, else Busy when one reaches its Busy threshold, else Steady. The thresholds are the
# host file's "pressure" ({"busy": {...}, "strained": {...}}, each figure a number), each one it does not set the
# default below. The load average is not one of them: a machine whose tests are pinned one a core has a high load and
# still answers at once.
# The tests' seams: CONVEYOR_PSI_DIR names the folder of the cpu and memory files (/proc/pressure), CONVEYOR_WAKE_CMD
# prints the wake delay in ms, and CONVEYOR_ROOM_CMD prints "<1-minute load> <available MB>" (roomnow).

# roomnow reads the host by lib/portable.sh's p_load and p_mem: a script that sources this file, or lib/slots.sh, and
# not portable.sh (.conveyor/test-changed.sh) would read no free memory, and so no Strained on macOS, without them.
declare -F p_load p_mem >/dev/null || . "${BASH_SOURCE[0]%/*}/portable.sh" || return 1

# The machine room's older reading, "<1-minute load> <available MB>": the host file's maxLoad and minFreeMemMB.
roomnow() {
  if [ -n "${CONVEYOR_ROOM_CMD:-}" ]; then bash -c "$CONVEYOR_ROOM_CMD" 2>/dev/null 8>&- 9>&-; return; fi
  printf '%s %s\n' "$(p_load)" "$(p_mem | awk '{printf "%d", ($2 - $1) / 1024}')"
}

# The "some avg10" of /proc/pressure/<cpu | memory>; nothing where the file is not (macOS, a kernel without PSI).
p_psi() { # <cpu | memory>
  local l f=${CONVEYOR_PSI_DIR:-/proc/pressure}/$1
  [ -r "$f" ] || return 0
  while read -r l; do [[ $l =~ ^some\ .*avg10=([0-9]+(\.[0-9]+)?) ]] && { echo "${BASH_REMATCH[1]}"; return 0; }; done < "$f" 2>/dev/null
}

# The wake delay, in ms to the tenth: how late a 10 ms sleep wakes, the middle of three. The sleep is bash's own read
# with a time limit on a FIFO no one writes to, so no program is started inside the time measured. Nothing when no
# FIFO can be made.
p_wake() {
  if [ -n "${CONVEYOR_WAKE_CMD:-}" ]; then bash -c "$CONVEYOR_WAKE_CMD" 2>/dev/null 8>&- 9>&-; return; fi
  local d f='' t s=()
  d=$(mktemp -d 2>/dev/null) || return 0
  { mkfifo "$d/f" && exec {f}<>"$d/f"; } 2>/dev/null; rm -rf "$d"
  [ -n "$f" ] || return 0
  for _ in 1 2 3; do
    t=${EPOCHREALTIME/[.,]/}; read -rt 0.01 -u "$f"; t=$(( ${EPOCHREALTIME/[.,]/} - t - 10000 ))
    s+=("$(( t < 0 ? 0 : t ))")
  done
  exec {f}>&-
  t=$(printf '%s\n' "${s[@]}" | sort -n | sed -n 2p)
  printf '%d.%d\n' "$((t / 1000))" "$((t % 1000 / 100))"
}

# The reading now, one JSON object: {state: "Steady" | "Busy" | "Strained", or null when no figure could be read, cpu,
# memory (percent), wakeMs, freeMB (null where memory pressure is read, or for a figure not read), why: the figure
# that set the state, with its threshold ("CPU pressure 72.5% is at or above 60%"), null for Steady}.
pressure() { # <host file>
  local c m w f='' t
  c=$(p_psi cpu); m=$(p_psi memory); w=$(p_wake)
  [ -n "$m" ] || read -r _ f <<<"$(roomnow)"
  t=$(jq -c '.pressure | objects' "$1" 2>/dev/null); [ -n "$t" ] || t='{}'
  jq -cn --argjson p "$t" --arg c "$c" --arg m "$m" --arg w "$w" --arg f "$f" '
    def at($x; $t): [
        (if $x.cpu != null and $x.cpu >= $t.cpu then "CPU pressure \($x.cpu)% is at or above \($t.cpu)%" else empty end),
        (if $x.memory != null and $x.memory >= $t.memory then "memory pressure \($x.memory)% is at or above \($t.memory)%" else empty end),
        (if $x.wakeMs != null and $x.wakeMs >= $t.wakeMs then "the wake delay \($x.wakeMs) ms is at or above \($t.wakeMs) ms" else empty end),
        (if $x.freeMB != null and $x.freeMB < $t.freeMB then "\($x.freeMB) MB free is below \($t.freeMB) MB" else empty end)] | first;
    ($m | tonumber? // null) as $mem
    | {cpu: ($c | tonumber? // null), memory: $mem, wakeMs: ($w | tonumber? // null), freeMB: (if $mem == null then $f | tonumber? // null else null end)} as $x
    | def own($s): (($p[$s] | objects) // {}) | with_entries(select(.value | type == "number"));
      {busy: ({cpu: 40, memory: 5, wakeMs: 5, freeMB: 2048} + own("busy")),
       strained: ({cpu: 80, memory: 20, wakeMs: 20, freeMB: 512} + own("strained"))} as $t
    | $x + if [$x[]] | all(. == null) then {state: null, why: "the machine room could not be read"}
        elif at($x; $t.strained) then {state: "Strained", why: at($x; $t.strained)}
        elif at($x; $t.busy) then {state: "Busy", why: at($x; $t.busy)}
        else {state: "Steady", why: null} end'
}
