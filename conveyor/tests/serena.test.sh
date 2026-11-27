#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: Serena for card sessions (lib/serena.sh): the rule Serena (`control rules serena=...`), a build session
# and a Codex review started with it or without it, its web dashboard off, its project files kept out of the change,
# the Claude review and judge each by its own role, the warning when serena is missing, the snapshot's detection, and
# setup --serena yes with doctor's line after it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
# shellcheck disable=SC2034 # the closure tool reads this line; the cases here do not use SRC
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Serena's command, after its path, as a session must start a Serena 2.x: the worktree its project, its agent
# interface tools (Serena 2.1's default REPL interface gives serena_repl alone, which no session is allowed, in place
# of find_symbol), its web dashboard and GUI log window off, whatever ~/.serena/serena_config.yml says.
serenaargsof() { jq -cn --arg w "$1" '["start-mcp-server", "--context", "claude-code", "--project", $w, "--agent-interface", "tools", "--enable-web-dashboard", "false", "--enable-gui-log-window", "false"]'; }
# One issue, #7, the rule Serena set to <roles> (a JSON array) in the control record, and, with serena, a stub serena
# on PATH that prints its version and, as Serena 2.x does, lists --agent-interface in its start-mcp-server --help
# (serena1: as Serena 1.x does, with no such option).
serenacase() { # <roles> [serena|serena1]
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$T/$CASE/bin" && export PATH=$T/$CASE/bin:$PATH
  jq -c --argjson r "$1" '.rules.serena = $r' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  [[ ${2:-} == serena?(1) ]] || return 0
  local o="'  --agent-interface [tools|repl]'"; [ "$2" = serena ] || o=''
  printf '%s\n' '#!/usr/bin/env bash' '[ "${1:-}" != --version ] || echo "Serena 9.9.9"' \
    "[ \"\$*\" != 'start-mcp-server --help' ] || printf '%s\n' '  --project TEXT' $o '  --enable-web-dashboard BOOLEAN'" > "$T/$CASE/bin/serena"
  chmod +x "$T/$CASE/bin/serena"
}
# The card's worktree, c7-7, made from main in the engine's folder of cards. A case that needs this machine's own serena
# or uv missing runs with PATH=$(without serena uv) (doctor.test.sh's helper: every other program on PATH).
SERENAWT='w=$CARDS/c7-7 && git -C "$MAIN" worktree add -q --detach "$w"'

# Bug (#1823): a card session had no symbol search, as each Claude session starts with --strict-mcp-config and no
# --mcp-config. With the rule naming build, the build session starts with <worktree>.mcp.json, whose one server is
# serena with its web dashboard and GUI log window off, beside --strict-mcp-config and --setting-sources "", its prompt
# names Serena's search tools, and Serena's tools that write or run a command are refused (the card's hooks see none).
# Bug (#1823): Serena writes its project files in <worktree>/.serena (its default place), and the card's change is
# the whole worktree: git's exclude file must name /.serena/, so the card's stage (emptychange()) leaves them out.
t_serenabuild() {
  serenacase '["build"]' serena
  fx_in "$SERENAWT"' && session "$w" brief && mkdir -p "$w/.serena" && echo name: x > "$w/.serena/project.yml" && { emptychange c7-7 7 "$w" ""; echo "staged: $(git -C "$w" diff --cached --name-only | paste -sd " " -)"; }'
  local w=$T/$CASE/cards/c7-7 a; a=$(cat "$STUB/sessions" 2>/dev/null)
  [[ $a == *" --setting-sources  --strict-mcp-config --mcp-config $w.mcp.json --settings $w.settings "* ]] \
    || fail "session <worktree> brief, with the rule Serena on build and serena installed, did not start claude with --strict-mcp-config --mcp-config $w.mcp.json: $a $(cat "$T/$CASE/run.out")"
  jq -e --arg p "$T/$CASE/bin/serena" --argjson a "$(serenaargsof "$w")" '.mcpServers | keys == ["serena"] and .serena == {command: $p, args: $a}' "$w.mcp.json" >/dev/null 2>&1 \
    || fail "session <worktree> brief, with the rule Serena on build: $w.mcp.json is not serena alone with its web dashboard off: $(cat "$w.mcp.json" 2>&1)"
  grep -qF "Use Serena's find_symbol and find_referencing_symbols" "$STUB/brief" \
    || fail "session <worktree> brief, with the rule Serena on build: its prompt does not name Serena's search tools: $(cat "$STUB/brief")"
  [[ $a == *"--disallowedTools Agent,"*",mcp__serena__replace_symbol_body,"*",mcp__serena__execute_shell_command,"* && $a != *mcp__serena__find_symbol* ]] \
    || fail "session <worktree> brief, with the rule Serena on build: Serena's write and shell tools are not refused, or a search tool is: $a"
  [ "$(tail -n 1 "$T/$CASE/run.out")" = 'staged: a.txt' ] \
    || fail "emptychange c7-7 7 <worktree>, after a build session with the rule Serena on build and a .serena/project.yml in the worktree, did not stage the build's a.txt alone: $(cat "$T/$CASE/run.out")"
}
# Bug (#1823): a machine without the rule (the default, off) must start each session as before: no --mcp-config, no
# <worktree>.mcp.json and no Serena line in its prompt, though serena is installed.
t_serenaoff() {
  serenacase '[]' serena
  fx_in "$SERENAWT"' && session "$w" brief'
  local w=$T/$CASE/cards/c7-7 a; a=$(cat "$STUB/sessions" 2>/dev/null)
  [[ -n $a && $a != *--mcp-config* && $a != *mcp__serena* ]] && [ ! -e "$w.mcp.json" ] && ! grep -q Serena "$STUB/brief" \
    || fail "session <worktree> brief, with the rule Serena off and serena installed, started with Serena: $a $(cat "$w.mcp.json" 2>&1) $(cat "$T/$CASE/run.out")"
}
# Bug (#1823): Serena 1.x has no --agent-interface (it has no REPL interface), and its start-mcp-server refuses the
# option, so a session given it would start with no Serena. With a serena whose start-mcp-server --help does not list
# the option, the command leaves it out and still turns the web dashboard and GUI log window off.
t_serenaold() {
  serenacase '["build"]' serena1
  fx_in "$SERENAWT"' && serenaargs "$w" build claude'
  local w=$T/$CASE/cards/c7-7
  jq -e --arg w "$w" '.mcpServers.serena.args == ["start-mcp-server", "--context", "claude-code", "--project", $w, "--enable-web-dashboard", "false", "--enable-gui-log-window", "false"]' "$w.mcp.json" >/dev/null 2>&1 \
    || fail "serenaargs <worktree> build claude, with a Serena 1.x stub whose start-mcp-server --help has no --agent-interface, did not start it without that option and with its web dashboard off: $(cat "$w.mcp.json" 2>&1) $(cat "$T/$CASE/run.out")"
}
# Bug (#1823): with the rule on and no serena on PATH, the session must start without it, and the card's log must say
# why (a silent rule that does nothing).
t_serenamissing() {
  serenacase '["build","fix"]'
  fx_in 'PATH=$(without serena) && '"$SERENAWT"' && session "$w" brief'
  local a; a=$(cat "$STUB/sessions" 2>/dev/null)
  [[ -n $a && $a != *--mcp-config* ]] || fail "session <worktree> brief, with the rule Serena on build and no serena, did not start, or started with --mcp-config: $a $(cat "$T/$CASE/run.out")"
  grep -qxF "conveyor: card c7-7: Serena rule on, but serena is not installed: its build session starts without it" "$T/$CASE/run.out" \
    || fail "session <worktree> brief, with the rule Serena on build and no serena, did not log the warning: $(cat "$T/$CASE/run.out")"
}
# Bug (#1823, after #1824): a Codex review with the rule on must keep every other server of the user's Codex config
# off and turn serena on alone, after its off setting: its command, the same arguments (web dashboard off) and only
# Serena's search tools (a review changes nothing).
t_serenareview() {
  serenacase '["review"]' serena
  export CODEX_HOME=$T/$CASE/codex-home; mkdir -p "$CODEX_HOME"
  printf '%s\n' 'model = "x"' '[mcp_servers.serena]' 'command = "serena"' '[mcp_servers.node_repl]' 'command = "/opt/node_repl"' '[mcp_servers.web]' 'url = "https://example.com/mcp"' > "$CODEX_HOME/config.toml"
  # stub: the shared stub reads and drops its arguments; this one keeps them for the case
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$@" > "$STUB/mcp-args"' 'exec "$STUB/codex" "$@"' > "$T/$CASE/bin/codex"; chmod +x "$T/$CASE/bin/codex"
  fx_in "$SERENAWT"' && codexreview "$w" brief instructions m low'
  local w=$T/$CASE/cards/c7-7 want
  want=$(printf '%s\n' mcp_servers.node_repl.enabled=false mcp_servers.serena.enabled=false mcp_servers.web.enabled=false \
    "mcp_servers.serena.command=\"$T/$CASE/bin/serena\"" "mcp_servers.serena.args=$(serenaargsof "$w")" \
    'mcp_servers.serena.enabled_tools=["find_symbol","find_referencing_symbols","get_symbols_overview"]' mcp_servers.serena.enabled=true)
  [ "$(grep '^mcp_servers' "$STUB/mcp-args" 2>/dev/null)" = "$want" ] \
    || fail "codexreview <worktree> brief instructions m low, with the rule Serena on review and a Codex config of serena, node_repl and web, did not start codex with the others off and serena on alone: $(tr '\n' ' ' < "$STUB/mcp-args" 2>&1) $(cat "$T/$CASE/run.out")"
}
# Bug (#1823): a Codex build session's guard hook (codex/guard.mjs) refuses every MCP tool, and an OpenCode session is
# not to change: neither may get Serena (or its prompt line) from the rule, while a Codex review of the same rule does.
t_serenaagents() {
  serenacase '["build","review"]' serena
  fx_in "$SERENAWT"' && for a in "build codex" "build opencode" "review codex"; do serenaargs "$w" $a; echo "$a: ${#SERENA_A[@]} ${SERENA_SAY:+said}"; done'
  [ "$(cat "$T/$CASE/run.out")" = $'build codex: 0 \nbuild opencode: 0 \nreview codex: 8 said' ] \
    || fail "serenaargs <worktree> <role> <agent>, with the rule Serena on build and review, for a Codex build, an OpenCode build and a Codex review (want none, none, Serena): $(cat "$T/$CASE/run.out")"
}
# Bug (#1823): a Claude review or judge runs in permission mode default, so Serena's tools must be allowed, its search
# tools alone (a review changes nothing), and inside the one --allowedTools its shell already has (a second flag could
# take the place of the first), or in one of its own when it has none.
t_serenaclaudereview() {
  serenacase '["review","judge"]' serena
  fx_in "$SERENAWT"' && for t in "--allowedTools Bash(cb-ast:*)" ""; do REVIEW_TOOLS=(--permission-mode default --tools Read,Grep,Glob $t --setting-sources "" --strict-mcp-config)
    serenaargs "$w" review claude; echo "${REVIEW_TOOLS[*]} ${SERENA_A[*]}"; done'
  local s='mcp__serena__find_symbol mcp__serena__find_referencing_symbols mcp__serena__get_symbols_overview' m="--mcp-config $T/$CASE/cards/c7-7.mcp.json"
  [ "$(cat "$T/$CASE/run.out")" = "--permission-mode default --tools Read,Grep,Glob --allowedTools $s Bash(cb-ast:*) --setting-sources  --strict-mcp-config $m
--permission-mode default --tools Read,Grep,Glob --setting-sources  --strict-mcp-config $m --allowedTools $s" ] \
    || fail "serenaargs <worktree> review claude, after a review's tools with and without --allowedTools Bash(cb-ast:*), did not allow Serena's search tools alone in one --allowedTools: $(cat "$T/$CASE/run.out")"
}
# Bug (#1823): a Claude review (claudereview()) and a card's Claude judge (judgecall()) must each ask for Serena by
# their own role: with the rule on judge alone, the judge starts with Serena and the review without it; with the rule
# on review alone, the other way round. A caller that drops Serena, or asks by the other's role, fails one of the four.
t_serenaclaudecallers() {
  serenacase '[]' serena
  fx_in "$SERENAWT"' && for r in judge review; do control rules serena=$r > /dev/null || exit 1
    claudereview "$w" brief instructions m medium > /dev/null; CALLSEAT='"'"'{"agent":"claude","model":"m","effort":"low"}'"'"' judgecall "$w" judge "F1 a finding" > /dev/null; done'
  local w=$T/$CASE/cards/c7-7 l i=0 want=(no yes yes no) call=("claudereview, rule judge" "judgecall, rule judge" "claudereview, rule review" "judgecall, rule review") got
  [ "$(wc -l < "$STUB/sessions" 2>/dev/null)" = 4 ] || fail "claudereview and judgecall, with the rule Serena on judge and then on review, did not start four claude sessions: $(cat "$STUB/sessions" 2>&1) $(cat "$T/$CASE/run.out")"
  while IFS= read -r l; do
    # Given in part (the server's file, or its tools allowed, without the other) is neither yes nor no, so it fails.
    got=no; [[ $l == *--mcp-config* || $l == *mcp__serena__* ]] && got=part
    [[ $l == *" --mcp-config $w.mcp.json "* && $l == *mcp__serena__find_symbol* ]] && got=yes
    [ "$got" = "${want[i]}" ] || fail "${call[i]}: Serena given is $got, want ${want[i]}: $l"
    i=$((i + 1))
  done < "$STUB/sessions"
}
# Bug (#1823): the rule is set by `control rules serena=<roles>|off`: kept sorted, off as [], and a role the engine does
# not know is refused with the record unchanged.
t_serenarule() {
  serenacase '[]'
  fx_in 'control rules serena=review,build > /dev/null && jq -c .rules.serena "$CONTROL" && control rules serena=off > /dev/null && jq -c .rules.serena "$CONTROL"'
  [ "$RC" = 0 ] && [ "$(tail -n 2 "$T/$CASE/run.out")" = $'["build","review"]\n[]' ] \
    || fail "control rules serena=review,build then serena=off did not keep [\"build\",\"review\"] then []: $(cat "$T/$CASE/run.out")"
  fx_in 'control rules serena=build,deploy'
  [ "$RC" = 2 ] && [ "$(jq -c .rules.serena "$ST/control.json")" = '[]' ] \
    || fail "control rules serena=build,deploy was not refused (exit $RC), or changed the rule: $(jq -c .rules.serena "$ST/control.json") $(cat "$T/$CASE/run.out")"
}
# Bug (#1823): nothing found Serena. The snapshot's key serena, which the Board's Rules tab reads, gives its path and
# version.
t_serenastatus() {
  serenacase '["fix"]' serena
  local s; s=$(loop snapshot --fresh | jq -c .serena)
  [ "$s" = "{\"installed\":true,\"path\":\"$T/$CASE/bin/serena\",\"version\":\"Serena 9.9.9\"}" ] \
    || fail "loop snapshot --fresh, with a stub serena of version Serena 9.9.9 on PATH, did not give its key serena: $s"
}
# Bug (#1823): a machine with the plugin and no Serena had no way to add it. setup --serena yes, with no serena and uv
# on PATH, runs `uv tool install serena-agent` and then sets the rule to build, fix and testfix; doctor then names
# the serena installed and the sessions the rule names. A whole setup and doctor run (the sample, doctordone's
# arguments): only they show that setup reads --serena and doctor prints Serena's line.
t_serenasetup() {
  local X out p; sample; X=$D/conveyor/conveyor.sh; mkdir -p "$T/$CASE/uvbin" "$T/$CASE/bin"
  # stub: uv keeps its arguments, and its tool install of serena-agent puts a serena of version 9.9.9 on PATH
  printf '%s\n' '#!/usr/bin/env bash' "printf '%s\n' \"\$*\" >> '$T/$CASE/uv-calls'" \
    "[ \"\$*\" != 'tool install serena-agent' ] || { printf '%s\n' '#!/usr/bin/env bash' 'echo 9.9.9' > '$T/$CASE/uvbin/serena'; chmod +x '$T/$CASE/uvbin/serena'; }" > "$T/$CASE/bin/uv"
  chmod +x "$T/$CASE/bin/uv"; p=$(without serena uv):$T/$CASE/bin:$T/$CASE/uvbin
  out=$(cd "$S" && PATH=$p bash "$X" setup --fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no --pin --serena yes 2>&1) \
    || fail "setup --serena yes, with no serena and a stub uv, exited non-zero: $out"
  [ "$(cat "$T/$CASE/uv-calls" 2>/dev/null)" = 'tool install serena-agent' ] && grep -qF 'installed Serena' <<<"$out" \
    || fail "setup --serena yes, with no serena and a stub uv, did not run uv tool install serena-agent: uv got '$(cat "$T/$CASE/uv-calls" 2>&1)': $out"
  out=$(cd "$S" && PATH=$p bash "$X" doctor 2>&1)
  grep -qxF "ok: serena 9.9.9 at $T/$CASE/uvbin/serena, for the card sessions the rule Serena names: build,fix,testfix" <<<"$out" \
    || fail "doctor, after setup --serena yes installed serena, did not name it and the rule on build, fix and testfix: $(grep -i serena <<<"$out")"
}
# Bug (#1823): with no uv, setup --serena yes must print the one command that installs Serena and leave the rule off
# (a rule on for a serena that is not there does nothing).
t_serenasetupnouv() {
  serenacase '[]'
  fx_in 'PATH=$(without serena uv) && serenasetup yes'
  [ "$RC" = 0 ] && grep -qF 'install it with: uv tool install serena-agent' "$T/$CASE/run.out" && [ "$(jq -c .rules.serena "$ST/control.json")" = '[]' ] \
    || fail "serenasetup yes, with no serena and no uv, did not print the install command, or set the rule (exit $RC): $(jq -c .rules.serena "$ST/control.json") $(cat "$T/$CASE/run.out")"
}
