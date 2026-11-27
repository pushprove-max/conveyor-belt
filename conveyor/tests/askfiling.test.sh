#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Foreman's filing ask (`foreman.sh ask <project> card` or `testissue`: ask() and askfiling(),
# foreman/lib.sh) on the real engine's cardnew() and testissue() (lib/testaction.sh). Its fixture is
# testaction.test.sh's tasetup.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs these catch (#1637): the filing ask filed the issue, then was stopped at the ask limit (or lost its ssh
# connection) before it gave the link back: it ended 124 with no link, and the Foreman filed the issue again. Each runs
# the real ask on the real engine.
# taask <ask limit> <GHWAIT, - for foreman/lib.sh's own> <lock|-> <ask arguments>: with lock, another process (as a pick
# or a snapshot would) holds the record's lock from before the ask until it ends, so the hold after the filing always
# takes longer than the limit. Sets out and rc; the ask's stderr is in $STUB/ask.err.
taask() {
  local lim=$1 wait=$2 lock=$3; shift 3
  mkdir -p "$R/conveyor" && printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$SRC/conveyor.sh" > "$R/conveyor/conveyor.sh" \
    || fail "the checkout's engine could not be made"
  if [ "$lock" = lock ]; then
    fx_in 'locked bash -c "touch \"\$STUB/locked\"; until [ -e \"\$STUB/free\" ]; do sleep 0.1; done" &'
    wait_until '[ -e "$STUB/locked" ]' || { touch "$STUB/free"; fail "the record's lock was not taken: $(cat "$T/$CASE/run.out")"; }
  fi
  out=$( ( export CONVEYOR_CARDS=$T/$CASE/cards; unset CONVEYOR_FOREMAN_ASK; . "$SRC/foreman/lib.sh" \
    && { [ "$wait" = - ] || export GHWAIT=$wait; } && ASK_LIMIT=$lim ask alpha "$R" "$@" ) 2> "$STUB/ask.err"); rc=$?
  touch "$STUB/free"
}
# tafiled <ask arguments>: the ask that filed the issue ended 0 with its link, and filed it once.
tafiled() {
  [ "$rc" = 0 ] && grep -qE '/issues/100101$' <<<"$out" \
    || fail "ask alpha $*, with the issue filed, did not end 0 with the issue's link (exit $rc): $out $(cat "$STUB/ask.err")"
  [ "$(jq -s length "$STUB/filed")" = 1 ] || fail "ask alpha $* did not file exactly one issue: $(cat "$STUB/filed")"
}
# tassh <after|before>, before tasetup (setup reads the host file for the state folder): the host file names an ssh
# host, and ssh runs the ask here and then (after), or at once (before), ends 255 as a lost connection does. The stub
# goes in the case's stub folder, which setup fills and does not empty.
tassh() {
  local s=$T/$CASE/stub
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$s" && echo '{"ssh": "box.example.com"}' > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file could not be written"
  if [ "$1" = after ]; then printf '#!/usr/bin/env bash\nbash -c "${!#}"\nexit 255\n' > "$s/ssh"; else printf '#!/usr/bin/env bash\nexit 255\n' > "$s/ssh"; fi
  chmod +x "$s/ssh"
}
# The hold waits on the lock past the limit (10 s, the engine reaches the filing well inside it): the link is printed,
# and the ask says the issue was filed.
t_cardaskslow() {
  local a=(card "Add a Rules row" "$(printf "Make it so.\n## Cause\nNo row exists.")")
  tasetup
  taask 10 0 lock "${a[@]}"; tafiled "${a[@]}"
  grep -qF 'after it filed' "$STUB/ask.err" && grep -qF 'do not file it again' "$STUB/ask.err" \
    || fail "ask alpha card 'Add a Rules row' does not say the issue was filed and must not be filed again: $(cat "$STUB/ask.err")"
}
# The same for testissue: its link was printed only after the hold.
t_taissueaskslow() {
  local a=(testissue tests/x.test.sh "Speed up tests/x.test.sh" "Measured: 12 CPU s.")
  tasetup
  taask 10 0 lock "${a[@]}"; tafiled "${a[@]}"
  grep -qF 'after it filed' "$STUB/ask.err" \
    || fail "ask alpha testissue tests/x.test.sh does not say the issue was filed: $(cat "$STUB/ask.err")"
}
# GitHub answers gh's create after the ask limit (2 s; gh takes 4 s): the filing ask waits GHWAIT more for gh's answer
# (gh_write() stops gh at its own limit), so the link comes and the hold is in. GHWAIT is foreman/lib.sh's own, so a
# default that is lost or too short fails here too. Bug this also catches: a GHWAIT of 10 passed the 4-second gh, yet
# in use it stops the ask while gh still has 50 of its seconds to wait on GitHub. A `timeout` first on PATH writes down
# the ask's limit and the limit gh_write() gives gh's create, then runs the real one, so the case checks the ask leaves
# gh its whole limit past the ask limit (2 s) with no wait of gh's own length.
t_cardaskgh() {
  local a=(card "Add a Rules row" "$(printf "Make it so.\n## Cause\nNo row exists.")") real ask gh
  tasetup; real=$(command -v timeout)
  printf '%s\n' '#!/usr/bin/env bash' '[ "$1 $2 $4" != "-k 2 bash" ] || echo "ask $3" >> "$STUB/limits"' \
    '[ "$2 $3 $4" != "gh issue create" ] || echo "gh $1" >> "$STUB/limits"' "exec '$real' \"\$@\"" > "$STUB/timeout" \
    && chmod +x "$STUB/timeout" || fail "the timeout stub could not be written"
  echo 'sleep 4' > "$STUB/create-cmd" # sleep: a slow GitHub answer is gh's time itself, past the ask limit, which no condition stands for
  taask 2 - - "${a[@]}"; tafiled "${a[@]}"
  [ "$(loop control | jq -c .held)" = '[100101]' ] || fail "ask alpha card 'Add a Rules row' with a slow gh did not hold its issue: $(loop control)"
  ask=$(sed -n 's/^ask //p' "$STUB/limits" | head -n 1); gh=$(sed -n 's/^gh //p' "$STUB/limits" | head -n 1)
  [[ $ask =~ ^[0-9]+$ && $gh =~ ^[0-9]+$ ]] && [ "$ask" -ge $((2 + gh)) ] \
    || fail "ask alpha card 'Add a Rules row' at ask limit 2 got a limit of '$ask' s, short of 2 s and gh_write()'s '$gh' s on gh: $(cat "$STUB/limits" 2>&1)"
}
# Bug this catches: the ask stopped at its limit (1 s, GHWAIT 0) while gh still waits on GitHub (4 s) gave the Foreman
# no link and no word that GitHub may have made the issue, so it filed it again.
t_cardasknolink() {
  tasetup
  echo 'sleep 4' > "$STUB/create-cmd" # sleep: a slow GitHub answer is gh's time itself, past the ask limit, which no condition stands for
  taask 1 0 - card "Add a Rules row" "$(printf "Make it so.\n## Cause\nNo row exists.")"
  [[ $rc = 124 || $rc = 137 ]] && ! grep -q '/issues/' <<<"$out" \
    && grep -qF 'before it printed an issue link: look for the issue in alpha before you file it again' "$STUB/ask.err" \
    || fail "ask alpha card 'Add a Rules row', stopped before gh answered, did not end 124 with the warning to look for the issue (exit $rc): $out $(cat "$STUB/ask.err")"
}
# Bug this catches (an ssh record): the connection lost after the engine printed the link ended the ask 255, and the
# Foreman, with a failed ask, filed the issue again.
t_cardasksshafter() {
  local a=(card "Add a Rules row" "$(printf "Make it so.\n## Cause\nNo row exists.")")
  tassh after; tasetup
  taask 10 0 - "${a[@]}"; tafiled "${a[@]}"
  grep -qF 'lost its connection to the host after it filed' "$STUB/ask.err" \
    || fail "ask alpha card 'Add a Rules row' over a lost ssh connection does not say the issue was filed: $(cat "$STUB/ask.err")"
}
# Bug this catches (an ssh record): with Foreman orders set to make cards with no GitHub issue, the engine prints the
# card's title; a title that ended in a parent issue's link, with the connection then lost, was taken for a filed issue,
# and the Foreman was told to hold that parent issue. Also: the engine had said the card was queued, yet the ask ended
# 255 and told the Foreman to look for an issue that does not exist, so a retry queued a second card.
t_cardasksshtitle() {
  local a=(card "Fix the row of https://github.com/o/alpha/issues/77" "Make it so.")
  tassh after; tasetup
  loop control rules foremanissues=off > /dev/null || fail "control rules foremanissues=off was refused"
  taask 10 0 - "${a[@]}"
  [ "$rc" = 0 ] && ! grep -qF 'after it filed' "$STUB/ask.err" && ! grep -qF 'control hold 77' "$STUB/ask.err" \
    || fail "ask alpha ${a[*]:0:2} with no GitHub issue, over a lost ssh connection, did not end 0 or took the title's link for a filed issue (exit $rc): $out $(cat "$STUB/ask.err")"
  grep -qF 'after it queued its card with no GitHub issue' "$STUB/ask.err" && grep -qF 'do not order it again' "$STUB/ask.err" \
    && ! grep -qF 'look for the issue' "$STUB/ask.err" \
    || fail "ask alpha ${a[*]:0:2} with no GitHub issue, over a lost ssh connection, does not say the card is queued and must not be ordered again: $(cat "$STUB/ask.err")"
  [ "$(jq '.cards | length' "$ST/testactions/cards.json")" = 1 ] || fail "ask alpha ${a[*]:0:2} with no GitHub issue did not queue exactly one card: $(cat "$ST/testactions/cards.json")"
}
# Bug this catches (an ssh record): the connection lost before a link came ended the ask 255 with no word that GitHub
# may have made the issue.
t_cardasksshbefore() {
  tassh before; tasetup
  taask 10 0 - card "Add a Rules row" "$(printf "Make it so.\n## Cause\nNo row exists.")"
  [ "$rc" = 255 ] && grep -qF 'lost its connection to the host before it printed an issue link: look for the issue in alpha' "$STUB/ask.err" \
    || fail "ask alpha card 'Add a Rules row' over an ssh connection lost at once did not end 255 with the warning to look for the issue (exit $rc): $out $(cat "$STUB/ask.err")"
}
