#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the host's CLIs: each seat set to a CLI installed on this host and a model, one that CLI has registered or a name typed in.
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
