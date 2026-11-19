#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the host's CLIs: each seat set to a CLI installed on this host and a model, one that CLI has registered or a name typed in;
# a step whose CLI is gone for a moment waits for it (seatwait()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The setup of a CLI case: one folder a CLI, so a case puts each on PATH or leaves it off (on <cli>...: that PATH).
# Each stub lists the models it has registered as the real CLI does: Codex its catalog as JSON (`codex debug models`,
# $STUB/codex-models; a model it hides from users among them), OpenCode one <provider>/<model> a line (`opencode
# models`, with a line that is no model), Claude Code none. Asked anything else, Codex and Claude are lib.sh's stubs,
# Codex keeping its arguments ($STUB/codex-args). No other folder of PATH holds any of the three.
clisetup() { # <issues json>
  local d np=''
  setup "$1"; CLIDIR=$T/$CASE/cli
  mkdir -p "$CLIDIR/claude" "$CLIDIR/codex" "$CLIDIR/opencode"; mv "$STUB/claude" "$CLIDIR/claude/claude"; mv "$STUB/codex" "$STUB/codex-review"; rm "$STUB/opencode"
  echo '{"models":[{"slug":"gpt-a","visibility":"list"},{"slug":"gpt-hidden","visibility":"hide"},{"slug":"gpt-b","visibility":"list"}]}' > "$STUB/codex-models"
  cat > "$CLIDIR/codex/codex" <<'EOF'
#!/usr/bin/env bash
[ "$1 ${2:-}" != "debug models" ] || { cat "$STUB/codex-models"; exit 0; }
printf '%s\n' "$*" >> "$STUB/codex-args"; exec "$STUB/codex-review" "$@"
EOF
  cat > "$CLIDIR/opencode/opencode" <<'EOF'
#!/usr/bin/env bash
[ "$1" = models ] || { touch "$STUB/opencode-ran"; exit 1; }
printf '%s\n' prov/m-1 other/vendor/m-2 'Models cached at 12:00'
EOF
  chmod +x "$CLIDIR"/*/*
  for d in ${PATH//:/ }; do [ -x "$d/claude" ] || [ -x "$d/codex" ] || [ -x "$d/opencode" ] || np+=$d:; done
  NOCLI=${np%:}
}
on() { local c p=''; for c; do p+=$CLIDIR/$c:; done; echo "$p$NOCLI"; } # <cli>...

# Bug: the Board's seat lists were the pack's models.allowed, so a CLI installed on the host was offered only when its
# models were written into the pack, and one that was not installed was offered all the same. Here the report names
# exactly the CLIs on PATH and the models each one lists (Codex's hidden one and OpenCode's line that is no model left
# out; Claude Code, which lists none, with null, so the Board takes a typed name); each seat is offered them with the
# efforts its CLI takes there (the OpenCode builder none), the judge the reviewer's CLI too; a CLI taken off PATH
# is gone from the snapshot at once, though the report read before still names it; and the snapshot runs no CLI while
# that report is younger than CLI_TTL (Codex, asked then, would list none: its catalog is gone).
# Bug: a snapshot never read the CLIs' models, so on a host where the loop had never run (no host's report) the Board's
# snapshot path, `conveyor.sh snapshot` over ssh with no `watch` feed, offered Codex and OpenCode with no models, and
# kept offering a model list CLI_TTL old. Here the first snapshot reads them and keeps the report, and one taken once
# that report is CLI_TTL old reads them again.
# Bug: Claude Code lists no models, so the Builder's model was a text box while the Judge's was a list. Each seat is
# given the pack's models.allowed by CLI (the judge's with the reviewer's Codex too), the list the Board offers then.
# One case, one setup: as two cases (clislist, clisfresh) the file used 12.6 CPU s in a card's test step, over its 8.
t_clislist() {
  clisetup "[$(issue 7 2026-01-01)]"
  export PATH; PATH=$(on claude codex opencode)
  [ ! -e "$ST/clis.json" ] || fail "the case did not start with no host's report"
  out=$(loop snapshot --fresh | jq -c --slurpfile p "$R/.conveyor/project.json" '.modelSettings | [.builder.clis, .reviewer.clis.opencode, .judge.clis],
    [.builder.allowed.claude == $p[0].models.allowed.claude, (.builder.allowed.claude | length > 0), (.judge.allowed | has("codex"))]') || fail "snapshot exited non-zero"
  [ "$(sed -n 1p <<<"$out")" = '[{"claude":{"models":null,"efforts":["low","medium","high","xhigh","max"]},"codex":{"models":["gpt-a","gpt-b"],"efforts":["minimal","low","medium","high","xhigh"]},"opencode":{"models":["prov/m-1","other/vendor/m-2"],"efforts":[]}},{"models":["prov/m-1","other/vendor/m-2"],"efforts":["minimal","low","medium","high","xhigh","max"]},{"claude":{"models":null,"efforts":["low","medium","high","xhigh","max"]},"codex":{"models":["gpt-a","gpt-b"],"efforts":["minimal","low","medium","high","xhigh"]},"opencode":{"models":["prov/m-1","other/vendor/m-2"],"efforts":["minimal","low","medium","high","xhigh","max"]}}]' ] \
    || fail "a snapshot on a host with no report does not offer each seat the installed CLIs and the models they list (the judge the reviewer's Codex too): $out"
  [ "$(sed -n 2p <<<"$out")" = '[true,true,true]' ] || fail "the seats are not given the pack's models by CLI, or the judge is not offered the reviewer's: $out"
  [ "$(jq -c .clis.codex "$ST/clis.json" 2>/dev/null)" = '["gpt-a","gpt-b"]' ] || fail "the snapshot did not keep the host's report: $(cat "$ST/clis.json" 2>&1)"
  rm "$STUB/codex-models"
  out=$(PATH=$(on claude codex) loop snapshot --fresh | jq -c '[.modelSettings.builder.clis | keys, .codex.models] + [.modelSettings.judge.clis | keys]')
  [ "$out" = '[["claude","codex"],["gpt-a","gpt-b"],["claude","codex"]]' ] \
    || fail "OpenCode, no longer on PATH, is still offered, or a snapshot with a young report ran Codex: $out"
  echo '{"models":[{"slug":"gpt-c","visibility":"list"}]}' > "$STUB/codex-models"
  jq -c '.at = 0' "$ST/clis.json" > "$ST/clis.old" && mv "$ST/clis.old" "$ST/clis.json" || fail "the host's report was not aged"
  out=$(loop snapshot --fresh | jq -c .modelSettings.reviewer.clis.codex.models) || fail "snapshot exited non-zero"
  [ "$out" = '["gpt-c"]' ] || fail "a snapshot with a report CLI_TTL old did not read Codex's models again: $out"
  echo '{"models":[{"slug":"gpt-a","visibility":"list"},{"slug":"gpt-hidden","visibility":"hide"}]}' > "$STUB/codex-models"
  [ "$(loop clis)" = '{"claude":null,"codex":["gpt-a"],"opencode":["prov/m-1","other/vendor/m-2"]}' ] \
    || fail "the host's report is not each installed CLI with the models it lists, read afresh: $(loop clis)"
  [ ! -e "$STUB/opencode-ran" ] || fail "a snapshot ran OpenCode for something other than its models"
}

# Bugs: a seat ran the CLI its model's name or the pack's list pointed to, not the one it was set to, or a model the
# pack or the CLI does not list could not be set; a seat set to a CLI that is gone ran something else, or started and
# failed in the card, instead of the loop refusing it with a message that names it; the Board is not told the seat
# cannot start, or is told so for a model its CLI does not list.
t_clisseat() {
  clisetup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-01-02))"
  export PATH; PATH=$(on claude codex opencode)
  echo "$GO" > "$STUB/review.1"
  # gpt-b is Codex's name and in none of the pack's lists: set to Claude, Claude runs it.
  [ "$(loop control model claude gpt-b high | jq -c .model)" = '{"cli":"claude","model":"gpt-b","effort":"high"}' ] \
    && [ "$(loop control reviewer codex gpt-a low | jq -c .reviewer)" = '{"cli":"codex","model":"gpt-a","effort":"low"}' ] || fail "the seats were not set to the CLI and model named"
  # A model Codex does not list (the Board's Other…) is taken and stored as typed (#441); before, it was refused.
  [ "$(loop control judge codex some-unlisted-model | jq -c .judge)" = '{"cli":"codex","model":"some-unlisted-model","effort":null}' ] \
    && [ "$(jq -c .judge "$ST/control.json")" = '{"cli":"codex","model":"some-unlisted-model","effort":null}' ] \
    || fail "a judge model Codex does not list was refused or not stored: $(jq -c .judge "$ST/control.json" 2>&1)"
  loop run --only 7 >/dev/null 2>&1 || fail "run of #7 exited non-zero: $(st 'select(.issue == 7) | [.step, .reason] | join(" ")')"
  [ "$(cut -d' ' -f1-5 "$STUB/sessions")" = '-p --model gpt-b --effort high' ] || fail "the builder did not run Claude on gpt-b at high: $(cat "$STUB/sessions")"
  grep -q -- '-m gpt-a -c model_reasoning_effort="low"' "$STUB/codex-args" && [ "$(st 'select(.issue == 7 and .step == "review") | .model')" = gpt-a ] \
    && [ -n "$(st 'select(.issue == 7 and .step == "landed") | .sha')" ] || fail "the reviewer did not run Codex on gpt-a at low, or the card did not land: $(cat "$STUB/codex-args") $(st 'select(.issue == 7) | .step' | tr '\n' ' ')"
  # OpenCode set, then gone: the loop starts no card and names the seat, its CLI and why.
  loop control reviewer opencode prov/m-1 >/dev/null || fail "the reviewer was not set to OpenCode"
  out=$(PATH=$(on claude codex) loop run --only 8 2>&1) && fail "a run with the reviewer's CLI gone exited zero"
  grep -q 'the reviewer is set to opencode prov/m-1, and opencode is not installed on this host (not on PATH): the reviewer does not start' <<<"$out" \
    && [ -z "$(st 'select(.issue == 8)')" ] && [ ! -e "$STUB/opencode-ran" ] || fail "a reviewer whose CLI is gone started, or the loop did not say why: $out"
  [ "$(PATH=$(on claude codex) loop snapshot --fresh | jq -r .modelSettings.reviewer.missing)" = 'opencode is not installed on this host (not on PATH)' ] \
    || fail "the Board is not told the reviewer's CLI is gone: $(PATH=$(on claude codex) loop snapshot --fresh | jq -c .modelSettings.reviewer)"
  # A model Codex does not list, once the report is read again: no reason the seat cannot start (#441: a typed name is
  # given to the CLI, and fails in the card when the CLI cannot run it). Bug: the Board marked it as one that cannot
  # start, and the loop started no card on it, so a model typed under Other… could never run.
  loop control model codex gpt-a medium >/dev/null && loop control reviewer claude claude-opus-5-5 >/dev/null || fail "the seats were not set"
  echo '{"models":[{"slug":"gpt-b","visibility":"list"}]}' > "$STUB/codex-models"
  jq -c '.at = 0' "$ST/clis.json" > "$ST/clis.old" && mv "$ST/clis.old" "$ST/clis.json" || fail "the host's report was not aged"
  out=$(loop snapshot --fresh | jq -c '[.modelSettings.builder.clis.codex.models, .modelSettings.builder.missing]')
  [ "$out" = '[["gpt-b"],null]' ] || fail "a builder set to a model Codex does not list is marked as one that cannot start: $out"
}

# A card's review step alone (review(), which checks its seat with seatwait() as a build, fix or test-fix session
# does), in the engine shell of `run`, on a worktree of main with a change staged, with the seat's CLI off PATH; what
# it prints, then rc=<its exit>, in $STUB/rv.out. <kind>: back, the reviewer codex and a report of this host that
# lists it, as an engine before seen wrote it (no seen) and read 100 seconds ago, well within CLI_TTL; never, the
# reviewer OpenCode, which no report of this host has listed, after `control` refused to set it. $CLIDIR/back, empty,
# is on PATH: a moment links the codex stub there, as an update of a CLI (Claude Code's) makes its link again. sleep
# is a function that, for seatwait's pauses, keeps each in $STUB/slept and runs <moment>, so no case waits one out;
# any other sleep sleeps.
clireview() { # <moment> <back | never>
  local m=$1
  clisetup "[$(issue 7 2026-01-01)]"
  export PATH; PATH=$(on claude codex opencode)
  echo "$GO" > "$STUB/review.1"; : > "$STUB/slept"
  if [ "$2" = never ]; then
    PATH=$(on claude codex)
    ! loop control reviewer opencode prov/m-1 >/dev/null 2>&1 || fail "a reviewer on OpenCode, which is not installed, was set"
    loop clis >/dev/null || fail "the host's report was not read"
    jq -c '.reviewer = {cli: "opencode", model: "prov/m-1", effort: null}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  else
    loop control reviewer codex gpt-a low >/dev/null && loop clis >/dev/null || fail "the reviewer was not set, or the host's report not read"
    mkdir -p "$CLIDIR/back"; PATH=$CLIDIR/back:$(on claude opencode)
    jq -c --argjson t $((EPOCHSECONDS - 100)) 'del(.seen) | .at = $t' "$ST/clis.json" > "$STUB/r.new" && mv "$STUB/r.new" "$ST/clis.json"
  fi
  jq -r .at "$ST/clis.json" > "$STUB/at0"
  mkdir -p "$T/$CASE/cards"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep -e '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names \
    && w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" && echo two >> "$w/a.txt" && git -C "$w" add a.txt \
    && sleep() { [ "${FUNCNAME[1]}" = seatwait ] || { command sleep "$@"; return; }; echo "$1" >> "$STUB/slept"; eval "$m"; } && # sleep: a stand-in that records seatwait's pauses and runs no wait
    { review "$w" "# Issue: body of the issue"; r=$?; [ ! -e "$w.idle" ] || echo "the wait's idle mark was left"; echo "rc=$r"; } ) > "$STUB/rv.out" 2>&1
}
# Bug (#839): a step that found its seat's CLI missing for a moment (Claude Code updating itself: its link made again)
# failed, and the card was blocked for good though the CLI was back seconds later. Here codex, the reviewer, is back
# at the second check: the review starts and passes, after one pause, and the check read the host's CLIs again (the
# report's read time moved: the cached report, which looks at PATH too, would hide a step that never read it again).
# The report is one an engine before seen wrote: its clis listing codex is enough to wait for it.
t_cliback() {
  # shellcheck disable=SC2016 # expanded in the engine shell (clireview)
  clireview 'ln -s "$CLIDIR/codex/codex" "$CLIDIR/back/codex"' back
  [ "$(tail -n 1 "$STUB/rv.out")" = rc=0 ] && [ "$(wc -l < "$STUB/reviews")" = 1 ] && [ "$(wc -l < "$STUB/slept")" = 1 ] \
    || fail "a review whose CLI was back at the second check did not start, or paused more than once: $(cat "$STUB/rv.out"); pauses: $(cat "$STUB/slept")"
  [ "$(jq -r .at "$ST/clis.json")" -gt "$(cat "$STUB/at0")" ] || fail "the second check did not read the host's CLIs again: $(cat "$ST/clis.json")"
}
# Bug (#839): the card was blocked when the CLI stayed missing, and stayed blocked until someone retried it. Here two
# cards, cap 2, build while codex (the reviewer) is on PATH; codex then goes and stays gone past the checks (four
# each, SEAT_PAUSE apart, not waited out: watchturns): each card waits in its review, not blocked, its live record
# naming codex and the snapshot (the Board, /units) showing that wait, its idle mark standing. The cap is then lowered
# to 1, so the two waits stand past it. Once codex is back, the loop's turns start the reviews in turn, on the cards'
# own worktrees, with no build again and no retry, and both land.
# A real loop, not a call of cliwake(): only run() counts the free slots and calls it in a turn. A call alone passed
# with run() never calling it, and with run()'s count, capped on idle cards, leaving no slot free once the cap fell.
t_cliwait() {
  local lp g s
  clisetup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-01-02))"
  export PATH; PATH=$(on claude codex opencode)
  echo "$GO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  tune '.tunables.live = 1 | .tunables.poll = 1'; mkdir -p "$T/$CASE/cards"
  loop control cap 2 >/dev/null && loop control reviewer codex gpt-a low >/dev/null && loop clis >/dev/null || fail "the cap or the reviewer was not set, or the host's report not read"
  mkdir -p "$CLIDIR/back" && ln -s "$CLIDIR/codex/codex" "$CLIDIR/back/codex"; PATH=$CLIDIR/back:$(on claude opencode)
  # Each build writes a file of its own (no same-file wait), then waits at the case's gate until both have built.
  echo 'echo "${PWD##*-}" > "f${PWD##*-}.txt"; echo "${PWD##*-}" >> "$STUB/built"; flock "$STUB/go.gate" true' > "$STUB/build"
  exec {g}>"$STUB/go.gate" && flock "$g" || fail "the build gate was not taken"
  watchturns
  ( exec {g}>&-; loop run > "$STUB/run.out" 2>&1 ) & lp=$!
  cwstop() { loop control stop >/dev/null; exec {g}>&-; wait "$lp" 2>/dev/null; fail "$@"; }
  wait_until '[ "$(wc -l < "$STUB/built" 2>/dev/null)" = 2 ]' 'cat "$STUB/run.out"' || cwstop "the two cards did not both build"
  rm "$CLIDIR/back/codex"; exec {g}>&-
  # shellcheck disable=SC2016 # expanded by wait_until
  wait_until '[ "$(cat "$T/$CASE/cards/"*.live 2>/dev/null | jq -s "map(select(.cli == \"codex\" and .step == \"review\")) | length")" = 2 ] && [ "$(ls "$T/$CASE/cards/"*.idle 2>/dev/null | wc -l)" -eq 2 ]' \
    'cat "$STUB/run.out"; ls "$T/$CASE/cards"' || cwstop "the two cards do not both wait for codex in their reviews, with no build slot held"
  [ "$(grep -cx seatwait "$TURNS")" = 8 ] || cwstop "the two steps did not check four times each, SEAT_PAUSE apart: $(grep -cx seatwait "$TURNS")"
  s=$(loop snapshot --fresh | jq '[.belt[] | select(.live.action // "" | startswith("waiting for codex: the reviewer is set to codex"))] | length')
  [ "$s" = 2 ] || cwstop "the snapshot does not show the two waits for codex: $s"
  [ -z "$(st 'select(.step == "blocked") | .card')" ] || cwstop "a card waiting for codex was blocked: $(st 'select(.step == "blocked") | .reason')"
  loop control cap 1 >/dev/null || cwstop "cap 1 was refused"
  turns 2 # the loop reads cap 1 before codex is back
  ln -s "$CLIDIR/codex/codex" "$CLIDIR/back/codex"
  wait_until '[ "$(st '"'"'select(.step == "landed") | .issue'"'"' | sort | tr "\n" " ")" = "7 8 " ]' 'cat "$STUB/run.out"; ls "$T/$CASE/cards"' \
    || cwstop "the two waiting cards did not both start their reviews and land once codex was back: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(wc -l < "$STUB/built")" = 2 ] && [ "$(wc -l < "$STUB/reviews")" = 2 ] && [ "$(st 'select(.step == "picked") | .issue' | sort | tr '\n' ' ')" = "7 8 " ] \
    || fail "a card built again or was picked again: built $(tr '\n' ' ' < "$STUB/built"), reviews $(wc -l < "$STUB/reviews"), picks $(st 'select(.step == "picked") | .issue' | tr '\n' ' ')"
}
# A seat set to a CLI that no report of this host has listed is refused at once, with the reason it had before #839,
# also once `control` refused to set a seat to it (it wrote that CLI into the report as installed, so the next read
# kept it as seen).
t_clinever() {
  clireview : never
  [ "$(tail -n 1 "$STUB/rv.out")" = rc=1 ] && [ ! -s "$STUB/slept" ] && [ ! -e "$STUB/reviews" ] \
    && grep -q '^the reviewer is set to opencode prov/m-1, and opencode is not installed on this host (not on PATH): the reviewer does not start' "$STUB/rv.out" \
    || fail "a reviewer set to a CLI this host never had was not refused at once with its reason: $(cat "$STUB/rv.out"); pauses: $(cat "$STUB/slept")"
}
