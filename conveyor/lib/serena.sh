# SPDX-License-Identifier: Apache-2.0
# Serena, a code search over MCP, for card sessions. The rule Serena (the control record's rules.serena: `control rules
# serena=<role,role,...|off>`, the Board's Rules tab) names the sessions that start with it, of build, fix, testfix,
# review and judge; it is off ([]) by default, so a machine with no Serena changes nothing. Serena is the one MCP
# server a card session may get, with its web dashboard and GUI log window off and (a Serena that has the option, 2.x)
# its agent interface tools on its command line, whatever the user's ~/.serena/serena_config.yml says (its REPL
# interface, Serena 2.1's default, gives serena_repl alone in place of find_symbol and the other search tools, and no
# session is allowed serena_repl). The engine does not change that file (Serena itself adds each project it starts in
# to the file's list of projects). Sourced by lib/control.sh.
# shellcheck disable=SC2034 # the roles the rule takes, read by control() (lib/control.sh)
SERENAROLES='build|fix|testfix|review|judge'
# The line a session's prompt gets with Serena (SERENA_SAY): which tool answers which search, and grep for the rest.
SERENATIP="Serena finds code by symbol (a function, class or variable). Use find_symbol to find a symbol by name \
(include_body=true reads its body), find_referencing_symbols to find each caller before you change, rename or remove a \
function, and get_symbols_overview before you read a whole file. Use grep for strings, comments, config and file names. \
When Serena finds nothing, check with grep before you decide the code is not there."
SERENAMISS='Serena rule on, but serena is not installed'
# Serena's tools a session may call: its search tools. Every other one writes, runs a command or changes Serena
# itself (SERENAWRITE, the ones Serena 2.1 has), which the card's hooks would not see: a review or judge, on Codex or
# Claude, is given SERENAREAD alone, and a Claude build, fix or testfix session (bypass mode, where only a refusal
# holds) is refused SERENAWRITE.
SERENAREAD=(find_symbol find_referencing_symbols get_symbols_overview)
# A Claude session gets MCP tools deferred, by name alone, until a ToolSearch call loads them: a session that is not
# told so never calls them (#1823's first cards made no Serena call). Its prompt gives the one call that loads them.
SERENALOAD="Serena's tools start deferred: before your first search of code, load them with one ToolSearch call, \
query \"select:$(printf 'mcp__serena__%s,' "${SERENAREAD[@]}" | sed 's/,$//')\"."
SERENAWRITE=(create_text_file replace_content replace_in_files delete_lines replace_lines insert_at_line replace_symbol_body
  insert_after_symbol insert_before_symbol rename_symbol safe_delete_symbol write_memory edit_memory delete_memory rename_memory
  execute_shell_command serena_repl open_dashboard activate_project remove_project onboarding jet_brains_move
  jet_brains_safe_delete jet_brains_inline_symbol jet_brains_rename jet_brains_debug)

# The serena on PATH, as one JSON object: {installed, path, version}; version is the first line `serena --version`
# prints within 10 seconds, null when it prints none. The snapshot's key serena (snapshot()) and doctor read it.
serenastatus() {
  local p v=''
  p=$(type -P serena) || p=''
  [ -z "$p" ] || v=$(timeout 10 "$p" --version 2>/dev/null < /dev/null) || :
  jq -cn --arg p "$p" --arg v "${v%%$'\n'*}" '{installed: ($p != ""), path: (if $p == "" then null else $p end), version: (if $v == "" then null else $v end)}'
}
# What serenastatus depends on, for the snapshot's kept copy (snappart()): the serena on PATH, and the size and times
# of the file it leads to (a uv upgrade writes that file again and keeps the link).
serenakey() { local p; p=$(type -P serena) || p=''; printf 'serena %s %s' "$p" "$([ -z "$p" ] || p_filekey "$(p_realpath "$p")")"; }
# The roles the rule names, comma-separated; nothing when it is off or the control record cannot be read.
serenarule() { local c; c=$(ctl 2>/dev/null) && jq -r '(.rules.serena | arrays) // [] | join(",")' <<<"$c"; }
# A build session's role for the rule (session1(), lib/session.sh): testfix on the testFix seat, build for a build,
# and fix for any other step (a fix or a rebase).
serenarole() { # <step> <seat>
  if [ "$2" = testFix ]; then echo testfix; elif [ "$1" = build ]; then echo build; else echo fix; fi
}
# Serena keeps a project's files (project.yml, memories, caches) in <project>/.serena unless its config names another
# place, and a card's staged change is the whole worktree (git add -A, emptychange() in lib/card.sh): git's exclude
# file for the repository (read by every worktree of it) names /.serena/, once, so those files never join a change. A
# file the project tracks there is not touched, as an exclude names untracked files alone.
serenaexclude() { # <worktree>
  local x; x=$(git -C "$1" rev-parse --path-format=absolute --git-path info/exclude) && mkdir -p "${x%/*}" \
    && { grep -qxF /.serena/ "$x" 2>/dev/null || { { [ ! -s "$x" ] || [ -z "$(tail -c 1 "$x")" ] || echo >> "$x"; } && echo /.serena/ >> "$x"; }; }
}
# The session's Serena, when the rule names <role> and the agent is Claude, or Codex for a review or judge (an OpenCode
# or Antigravity session gets none, nor does a Codex build, fix or testfix session, whose guard hook, codex/guard.mjs,
# refuses every MCP tool): SERENA_A, the arguments that start it, and SERENA_SAY, the line its prompt gets (SERENATIP); SERENA_NO,
# the tools a Claude build, fix or testfix session is refused (",mcp__serena__<tool>", added to its --disallowedTools);
# all empty when it gets none. A Claude session gets <worktree>.mcp.json, the one server serena, by --mcp-config, beside
# its --strict-mcp-config (a Claude review or judge also gets Serena's search tools allowed: in REVIEW_TOOLS's
# --allowedTools, reviewtools(), lib/review.sh). A Codex session gets the same command by -c settings, after the -c
# settings that turn off every other server (codexmcpoff(), lib/control.sh). When the rule names <role> and serena is
# not on PATH, the session starts without it and the card's log says so.
# shellcheck disable=SC2034 # SERENA_NO and SERENA_SAY are read by builder() (lib/session.sh) and the reviews (lib/review.sh)
serenaargs() { # <worktree> <role> <agent>
  local p a h i o='' t=()
  SERENA_A=() SERENA_SAY='' SERENA_NO=''; rm -f "$1.mcp.json"
  [ -n "$2" ] && [[ $3 != @(opencode|antigravity) ]] && { [ "$3" != codex ] || [[ $2 == @(review|judge) ]]; } && [[ ,$(serenarule), == *",$2,"* ]] || return 0
  p=$(type -P serena) || { echo "conveyor: card ${1##*/}: $SERENAMISS: its $2 session starts without it" >&2; return 0; }
  serenaexclude "$1" || { echo "conveyor: card ${1##*/}: .serena/ could not be added to git's exclude file, so Serena's project files would join the change: its $2 session starts without Serena" >&2; return 0; }
  # --agent-interface tools only for a Serena whose start-mcp-server lists it (read within 10 seconds): Serena 1.x has
  # no REPL interface and refuses the option, so it would not start.
  h=$(timeout 10 "$p" start-mcp-server --help 2>/dev/null < /dev/null) || :
  [[ $h != *--agent-interface* ]] || o=tools
  a=$(jq -cn --arg w "$1" --arg o "$o" '["start-mcp-server", "--context", "claude-code", "--project", $w] + (if $o == "" then [] else ["--agent-interface", $o] end) + ["--enable-web-dashboard", "false", "--enable-gui-log-window", "false"]')
  if [ "$3" = codex ]; then
    SERENA_A=(-c "mcp_servers.serena.command=$(jq -cn --arg p "$p" '$p')" -c "mcp_servers.serena.args=$a"
      -c "mcp_servers.serena.enabled_tools=$(jq -cn '$ARGS.positional' --args "${SERENAREAD[@]}")" -c mcp_servers.serena.enabled=true)
  else
    jq -n --arg p "$p" --argjson a "$a" '{mcpServers: {serena: {command: $p, args: $a}}}' 2>/dev/null > "$1.mcp.json" \
      || { rm -f "$1.mcp.json"; echo "conveyor: card ${1##*/}: $1.mcp.json could not be written: its $2 session starts without Serena" >&2; return 0; }
    SERENA_A=(--mcp-config "$1.mcp.json")
    if [[ $2 == @(review|judge) ]]; then
      for i in "${SERENAREAD[@]}"; do t+=("mcp__serena__$i"); done
      for i in "${!REVIEW_TOOLS[@]}"; do [ "${REVIEW_TOOLS[i]}" != --allowedTools ] || { REVIEW_TOOLS=("${REVIEW_TOOLS[@]:0:i+1}" "${t[@]}" "${REVIEW_TOOLS[@]:i+1}"); t=(); break; }; done
      [ ${#t[@]} = 0 ] || SERENA_A+=(--allowedTools "${t[@]}")
    else SERENA_NO=$(printf ',mcp__serena__%s' "${SERENAWRITE[@]}"); fi
  fi
  if [ "$3" = codex ]; then SERENA_SAY=$'\n\n'$SERENATIP; else SERENA_SAY=$'\n\n'"$SERENALOAD $SERENATIP"; fi
}
# doctor's line for Serena: where it is and its version; else whether the rule names a session that now starts without it.
serenadoctor() {
  local s r; s=$(serenastatus); r=$(serenarule)
  if jq -e .installed <<<"$s" >/dev/null; then jq -r --arg r "${r:-off}" '"ok: serena \(.version // "(its version could not be read)") at \(.path), for the card sessions the rule Serena names: \($r)"' <<<"$s"
  elif [ -n "$r" ]; then echo "warning: $SERENAMISS: the sessions it names ($r) start without it; conveyor.sh setup --serena yes installs it"
  else echo "note: serena is not installed (it is optional, and the rule Serena is off); conveyor.sh setup --serena yes installs it"; fi
}
# setup's step for Serena (`setup --serena yes|no`, commands/setup.md). With yes: when serena is not on PATH and uv is,
# `uv tool install serena-agent`; then, with serena on PATH, the rule Serena set to build, fix and testfix. With yes and
# no uv, the one command that installs it is printed and the rule is left as it is. No, or no answer, changes nothing.
# Serena's own config file is not changed here.
serenasetup() { # <yes|no|"">
  local b
  [ "$1" = yes ] || return 0
  if ! type -P serena >/dev/null; then
    type -P uv >/dev/null || { echo "conveyor: Serena is not installed, and uv is not on PATH; install it with: uv tool install serena-agent (https://docs.astral.sh/uv/ installs uv), then run setup --serena yes again. The rule Serena stays as it is"; return 0; }
    timeout 600 uv tool install serena-agent || { echo "conveyor: Serena could not be installed (uv tool install serena-agent); the rule Serena stays as it is" >&2; return 0; }
    type -P serena >/dev/null || { b=$(uv tool dir --bin 2>/dev/null) || b='the folder uv tool dir --bin names'; echo "conveyor: installed Serena, but $b is not on PATH, so card sessions cannot start it: add it (uv tool update-shell), then run setup --serena yes again. The rule Serena stays as it is"; return 0; }
    echo "conveyor: installed Serena (uv tool install serena-agent)"
  fi
  control rules serena=build,fix,testfix >/dev/null && echo "conveyor: set the rule Serena to build, fix and testfix: those card sessions start with Serena, its web dashboard off"
}
