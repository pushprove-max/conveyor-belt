# SPDX-License-Identifier: Apache-2.0
# The load factor of a test run, by which the engine's time limits of the run grow on a busy machine.
# The load factor of a test run (docs/configuration.md, The load factor): the 1-minute load average per core of the
# machine (p_load, nproc --all), at least 1 and at most 3, so a run on a busy machine gets more time and a slowdown of
# more than 3 times still fails. Up to two decimals, trailing zeros left out (1.5, 2). A run inside another test run
# (CONVEYOR_LOAD_FACTOR set: a test that runs Conveyor) keeps that run's factor, held between 1 and 3. The engine's
# own time limits of a run scale by it (filecmd() in lib/testrun.sh, the runner's per-case limits: tests/lib.sh), and
# each run gets it as CONVEYOR_LOAD_FACTOR (testonce(), cleanrun(), pushfile() in lib/pushrun.sh and the pre-push hook
# in lib/push.sh).
loadfactor() {
  local load=${CONVEYOR_LOAD_FACTOR:-} ncpu=1
  [[ $load =~ ^[0-9]+(\.[0-9]+)?$ ]] || { load=$(p_load); ncpu=$(nproc --all 2>/dev/null) && [ "${ncpu:-0}" -gt 0 ] 2>/dev/null || ncpu=1; }
  awk -v l="$load" -v c="$ncpu" 'BEGIN { f = (l ~ /^[0-9]+(\.[0-9]+)?$/) ? l / c : 1; if (f < 1) f = 1; if (f > 3) f = 3
    s = sprintf("%.2f", f); sub(/\.?0+$/, "", s); print s }'
}
