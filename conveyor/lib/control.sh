# SPDX-License-Identifier: Apache-2.0
# The control record, whole: the file's keys over CTL0's, so a record written before a key existed still reads.
# mode is run, pause or stop; cap and guard are a number or null; held and order are issue numbers; rules.never is
# the area labels never built, rules.push whether a card that lands is pushed (off: land only, owed()), rules.visible whether a visible change
# needs the owner's yes (yesrule()); model, reviewer and judge (the review's judge, judgeseat()) are null or {cli: the
# CLI that runs the seat (claude, codex or opencode), model, effort (null: the seed's)}, cli left out of one that names
# a model of the pack's models.allowed, whose program it is (seatnow()); tests (the Tests seat, the test actions'
# sessions: testaction(), lib/testaction.sh) is null or {cli, model, effort}, always with its CLI;
# judgeOn is whether the judge reads the reviews (judged()) and judgeAlways the finding kinds it always accepts; account and
# reviewAccount are null or the name of one of the host file's accounts (ACCT, above); start is where
# new issues start, queue or held, startHeld the spans it was held ({from, to}: the newest issue number at each switch;
# to is null for the one in force, the last), startSeen the issues this setting has had its say on: held by adopt(), or released while there is a span.
# depGuard is the dependency guard (true, the seed's, for a record written before it: no issue is picked while an
# issue it depends on is open) and forced the issues `control force` lets past their open dependencies while it is
# off (adopted() drops each once it lands or its issue closes). A key this copy of the engine does not know, at the top
# or in rules (one a newer copy added, while a card runs on the older copy in its worktree), is passed through
# unchecked, so a control action keeps it when it writes the record. Anything else is not a record: the reason on
# stderr and exit 1.
# The file is read at every use; what this check made of it is kept, keyed on the file and its exact text (CTL_K), so
# the same text is not checked again and any other is; a record that fails is never kept. A read in a subshell keeps
# nothing: ctlread sets CTL_V in the shell that calls it, and a subshell started after it finds what it kept. A file
# with a NUL byte is checked as before and not kept (a bash variable cannot hold it).
CTL_K=()
# The record when there is no file, and each key's default where a record leaves the key out: control-defaults.json
# beside this file, one key a line, read here into CTL0 (compact). A new key is a new line there; ctlcheck gives it to
# every record that leaves it out. The defaults are the settings the plugin's own project runs on: nothing paused,
# held, ordered or excluded; new issues start in the Queue; six cards at once; no new card starts at 98% of the
# account's usage (guard); the builder and the judge on claude-opus-5-5 and the reviewer on gpt-6.1-sol, each at
# medium effort and named by its model alone, so it runs on the CLI the pack's models.allowed lists it under (one the
# pack does not list is the seed's, below; one whose CLI is not installed does not start, and doctor names it); the
# judge reads the reviews (judgeOn) and always accepts no kind. A cap, seat or effort the record sets null is the
# seed's: six cards at once (CAP0), and for a seat the first model the pack's models.allowed lists for it (seed()) at
# medium effort (an OpenCode builder at none: it is given no effort, seatnow). The dependency guard is on: no issue is
# picked while an issue it depends on is open; nothing is forced past it. A card that lands is pushed (rules.push;
# off: land only, owed()). A visible change needs no yes from the owner (rules.visible off; on: a card waits for a
# `Visible change approved:` line, yesrule()). No Tests seat is set: no test action starts (testaction()). Empty when
# the file cannot be read, or there is no jq (doctor says so): then no record is read.
CTL0=$(jq -c . "$HERE/lib/control-defaults.json" 2>/dev/null) || CTL0=
ctl() { local CTL_V; ctlread || return 1; printf '%s\n' "$CTL_V"; }
ctlread() { # sets CTL_V to the control record, as ctl prints it
  local t a=''
  [ -n "$CTL0" ] || { echo "conveyor: the control record's defaults, $HERE/lib/control-defaults.json, cannot be read" >&2; return 1; }
  [ -s "$CONTROL" ] || { CTL_V=$CTL0; return; }
  { IFS= read -r -d '' t; a=$?; } 2>/dev/null <"$CONTROL"
  [ "$a" = 1 ] && [ "${#CTL_K[@]}" = 3 ] && [ "${CTL_K[0]}" = "$CONTROL" ] && [ "${CTL_K[1]}" = "$t" ] && { CTL_V=${CTL_K[2]}; return 0; }
  if [ "$a" = 1 ]; then CTL_V=$(ctlcheck <<<"$t") && CTL_K=("$CONTROL" "$t" "$CTL_V"); else CTL_V=$(ctlcheck "$CONTROL"); fi \
    || { echo "conveyor: $(notwhole)" >&2; return 1; }
}
ctlcheck() { # [<file>]: the record on the input, or in the file, whole, or exit non-zero
  jq -ce --argjson d "$CTL0" '($d * .) | .rules = ($d.rules * .rules) | select((.mode | IN("run", "pause", "stop")) and (.cap == null or (.cap | type == "number" and . >= 1 and . <= 100 and . == floor))
      and (.guard == null or (.guard | type == "number" and . >= 1 and . <= 100))
      and ([.held, .order] | all(type == "array" and all(type == "number")))
      and (.start | IN("queue", "held")) and (.startSeen | type == "array" and all(type == "number"))
      and (.startHeld | type == "array" and all(type == "object" and keys == ["from", "to"] and (.from | type == "number") and (.to == null or (.to | type == "number"))))
      and ((.start == "held") == (.startHeld | length > 0 and (last.to == null)))
      and (.rules | (.never | type == "array" and all(type == "string")) and ([.P0, .P1, .P2, .P3, .followups, .push, .visible] | all(type == "boolean")))
      and ([.model, .reviewer, .judge, .tests] | all(. == null or (type == "object" and (keys - ["effort", "cli"]) == ["model"] and (.model | type == "string")
        and (.effort == null or (.effort | type == "string")) and (.cli == null or (.cli | IN("claude", "codex", "opencode"))))))
      and (.tests == null or .tests.cli != null)
      and (.judgeOn | type == "boolean") and (.judgeAlways | type == "array" and all(type == "string"))
      and (.depGuard | type == "boolean") and (.forced | type == "array" and all(type == "number"))
      and ([.account, .reviewAccount] | all(. == null or (type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")))))' \
    "$@" 2>/dev/null
}
notwhole() { echo "$CONTROL is not a whole control record; nothing is picked while it stands"; }
# The newest Claude weekly limit reading, as {time, pct}, or nothing when there is none younger than LIMIT_OLD.
# It first asks for a new one when the last asking is LIMIT_TTL old; one asker at a time, and never under the card
# records' lock (the question goes over the network). A question that fails leaves no line. With fresh (the after
# reading of a closing line) it asks whatever the age of the last asking, waiting for an asker already at it,
# unless that asker began after this call did: a card that ends within LIMIT_TTL of its before reading would
# otherwise end on that same reading and show no use of the limit. A snapshot of `watch` (GITHUB set) never asks.
# The reading is the account's in use (ACCT): each account is asked for on its own, and its line names it.
reading() { # [fresh]
  local t0 asked=$LIMIT.asked${ACCT:+.$ACCT}; t0=$(date +%s)
  [ -n "$GITHUB" ] || ( if [ "${1:-}" = fresh ]; then flock -w 40 7 || exit 0; [ "$(cat "$asked" 2>/dev/null || echo 0)" -le "$t0" ] || exit 0
    else flock -n 7 || exit 0; [ $(($(date +%s) - $(cat "$asked" 2>/dev/null || echo 0))) -ge "$LIMIT_TTL" ] || exit 0; fi
    date +%s > "$asked"
    # An account the host file no longer lists has no folder to read: no reading. The default login is ~/.claude, the
    # folder a session started with no account uses (acctrun), never the one whose metadata was written last nor a
    # CLAUDE_CONFIG_DIR the engine inherited: the Board marks ~/.claude as the default.
    if [ -n "$ACCT" ]; then CLAUDE_CONFIG_DIR=$(acctdir "$ACCT") || exit 0; else CLAUDE_CONFIG_DIR=$HOME/.claude; fi
    export CLAUDE_CONFIG_DIR
    pct=$(timeout 30 bash -c "$LIMIT_CMD" 2>/dev/null 7>&- 8>&- < /dev/null | jq -e '.seven_day.utilization | numbers' 2>/dev/null) || exit 0
    jq -cn --argjson p "$pct" --arg a "$ACCT" '{time: (now | todate), pct: $p} + (if $a == "" then {} else {account: $a} end)' | stdb append limit
    stdb keep limit 4000 2000
  ) 7>>"$LIMIT.lock"
  lastread
}
# What a pick does now, from the control record ("" when it does not read) and the reading's percent ("" for none):
# running, paused, stopped, "paused by guard", or "control record unreadable". The loop, health and the snapshot all
# ask here.
state() { # <control record> <percent>
  jq -rn --argjson c "${1:-null}" --arg p "${2:-}" 'if $c == null then "control record unreadable" elif $c.mode == "pause" then "paused"
    elif $c.mode == "stop" then "stopped" elif $c.guard != null and $p != "" and ($p | tonumber) >= $c.guard then "paused by guard" else "running" end'
}
# The model and effort a seat runs on now, as {model, effort, agent}: the control record's over the seed's. agent is
# the CLI that runs the model: the one the record names with it (cli), whatever the pack lists; for a record that
# names a model alone, the program the pack's models.allowed lists it under (okmodels). A record that does not read,
# or names no CLI and a model the pack does not list for the seat, sets nothing: the seed's. effort is null for an
# OpenCode builder, which is given none. Nothing when neither the record nor the pack names a model for the seat.
# Whether the seat's CLI and model are on this host is seatready()'s. An OpenCode model is named opencode:<provider>/<model>
# (ocmark), as the pack names one: the live record, a stopped step and the Board's prices know an OpenCode step by
# that mark, and the record holds it as OpenCode lists it. seatnow($s; $c) is that answer in jq, from
# models.allowed (its input) and the control record $c, so a step that needs both seats asks one jq run (inforce,
# modelsettings, homes).
SEATNOW="$OKMODELS"'def ocmark: if .agent == "opencode" and (.model | startswith("opencode:") | not) then .model = "opencode:" + .model else . end;
  def seatnow($s; $c): okmodels($s) as $ok | seed($s) as $d
    | ($c // {} | .[{builder: "model", reviewer: "reviewer"}[$s]] // {}) as $o
    | (if $o.model != null and ($o.cli != null or ([$ok[][]] | index($o.model))) then $o else {} end) as $o
    | ($o.model // $d.model) as $m
    | {model: $m, effort: ($o.effort // $d.effort), agent: ($o.cli // ([$ok | to_entries[] | select(.value | index($m)) | .key] | first))} | ocmark
    | ($s == "builder" and .agent == "opencode") as $none | if $none then .effort = null else . end
    | select((.model | type == "string") and ($none or (.effort | type == "string")) and .agent != null);'
# Several values of one JSON object, as `jq -r .<key>` prints each, read in one jq run (each ended by a NUL), so a step
# that needs a seat's model, effort and agent starts one program, not three. Fails when the object does not read.
jqget() { # <json> <key> <variable> [<key> <variable>]...
  local j_=$1 k_=() v_=() x_=() i_; shift
  while [ $# -ge 2 ]; do k_+=("$1"); v_+=("$2"); shift 2; done
  mapfile -d '' -t x_ < <(jq -j '. as $o | $ARGS.positional[] | $o[.] | (if type == "string" then . else tojson end) + "\u0000"' \
      --args "${k_[@]}" <<<"$j_" 2>/dev/null) && [ "${#x_[@]}" = "${#k_[@]}" ] || return 1
  for i_ in "${!v_[@]}"; do printf -v "${v_[i_]}" '%s' "${x_[i_]}"; done
}
# The seats in force, the builder's, the reviewer's and the judge's (judgeseat), worked out together in one jq run and
# kept, keyed on the exact text of the control record and of models.allowed (SEAT_K), so a step that asks for a seat
# again starts no program for it, nor does a subshell or card started after; any other text is worked out again.
# Read without a record given, the control record is read in the calling shell (ctlread), so it is kept there too.
declare -gA SEAT_V=(); SEAT_K=''
seat() { # <builder|reviewer|judge> [the control record, when the caller has read it]
  local a c=${2:-} x CTL_V; [ -n "$c" ] || { if ctlread 2>/dev/null; then c=$CTL_V; else c=null; fi; }
  packget models.allowed a 2>/dev/null || return 1
  if [ "$SEAT_K" != "$c"$'\037'"$a" ]; then
    # Each seat on its own (try): one that fails to work out is none, as it was read alone.
    mapfile -d '' -t x < <(jq -j --argjson c "$c" "$SEATNOW$JUDGENOW"'([try seatnow("builder"; $c)] | first) as $b | ([try seatnow("reviewer"; $c)] | first) as $r
        | ($b, $r, (if $r == null then null else [try judgenow($c; $r)] | first end)) | (if . == null then "" else tojson end) + "\u0000"' <<<"$a" 2>/dev/null) \
      && [ "${#x[@]}" = 3 ] || return 1
    SEAT_V=([builder]=${x[0]} [reviewer]=${x[1]} [judge]=${x[2]}); SEAT_K=$c$'\037'$a
  fi
  [ -n "${SEAT_V[$1]:-}" ] && printf '%s\n' "${SEAT_V[$1]}"
}
# The model and effort the review's judge (judged()) runs on now, as {model, effort, agent}. The control record's
# judge is the one when it names a model, on its CLI (cli, or for one named by its model alone the program the pack
# lists it under for the review), the reviewer's CLI too; else the first of the models the pack allows the review
# that another program than the reviewer's runs (Claude's or OpenCode's for a Codex reviewer, and so on), at medium
# effort. Nothing when there is none.
# judgenow($c; $r) is that answer in jq, from models.allowed (its input), the control record $c and the reviewer's
# seat $r, so the Board's settings (SETTINGS) name the same model.
JUDGENOW='def judgenow($c; $r): okmodels("reviewer") as $all | ($all | del(.[$r.agent])) as $ok
    | def of($x; $m): [$x | to_entries[] | select(.value | index($m)) | .key] | first;
    ($c // {} | .judge // {}) as $o
    | (if $o.model == null then null else $o.cli // of($all; $o.model) end) as $a
    | if $a != null then {model: $o.model, effort: ($o.effort // "medium"), agent: $a} | ocmark
      else ([$ok[][]] | first) as $m | select($m != null) | {model: $m, effort: "medium", agent: of($ok; $m)} end;'
judgeseat() { seat judge; }
# The finding kinds always accepted (a JSON array), when the control record's judge is on (`control judge on`).
# Nothing, and a failure, when it is off or the record does not read.
judgeon() { local c; c=$(ctl 2>/dev/null) && jq -ce 'select(.judgeOn) | .judgeAlways' <<<"$c"; }
# progs: the programs the pack's models.allowed lists a model for, one per line (doctor's).
progs() {
  local a
  packget models.allowed a && jq -r '(if (.claude // []) + (.["claude-reviewer"] // []) | any(strings) then "claude" else empty end),
      (if (.codex // []) + (.["codex-builder"] // []) | any(strings) then "codex" else empty end), (if .opencode // [] | any(strings) then "opencode" else empty end)' <<<"$a"
}
# The models a CLI has registered on this host, as a JSON array, read from the CLI itself; fails when it offers no
# list or its list cannot be read. Codex: `codex debug models`, its model catalog, the slugs it shows a user
# (visibility list). OpenCode: `opencode models`, one <provider>/<model> a line. Claude Code has no command that lists
# its models (its --model takes an alias or a full name): none.
climodels() { # <cli>
  case $1 in
    codex) timeout 20 codex debug models < /dev/null 2>/dev/null \
      | jq -ce '[.models[]? | select((.visibility // "list") == "list") | .slug | strings] | select(length > 0)' 2>/dev/null ;;
    opencode) timeout 20 opencode models < /dev/null 2>/dev/null | jq -Rsce '[splits("\n") | select(test("^[^/[:space:]]+/[^[:space:]]+$"))] | select(length > 0)' 2>/dev/null ;;
    *) return 1 ;;
  esac
}
# The host's report: each CLI of CLINAMES installed here (on PATH) and the models it has registered, as {<cli>: its
# models (climodels), or null when it offers no list or it has not been read}. Read from CLIS; with fresh every CLI is
# read again, with due only when CLIS is CLI_TTL old, and with a CLI's name that one alone; what was read is written
# back to CLIS. A CLI that is not installed now is left out, whatever CLIS says.
# The report as CLIS holds it, for the CLIs installed now, is worked out in one jq run and kept, keyed on CLIS's exact
# text and those CLIs (HOST_K), so a step that asks again before it is due starts no program for it, nor does a
# subshell or card started after.
# What it printed is in HOST_R too ("" when it failed), for a caller that keeps it in its own shell (seatready).
HOST_K=() # the key, then CLIS read as an object, when it was read (.at, whole seconds) and the report
hostclis() { # [fresh | due | <cli>]
  local c old r found=() one=${1:-} t='' a=1 k='' x
  HOST_R=''
  for c in $CLINAMES; do command -v "$c" >/dev/null && k+=" $c"; done
  [ ! -e "$CLIS" ] || { a=''; { IFS= read -r -d '' t; a=$?; } 2>/dev/null <"$CLIS"; }
  # A file with a NUL byte is read as before and never kept (a bash variable cannot hold it).
  [ "$a" = 1 ] && [ "${#HOST_K[@]}" = 4 ] && [ "${HOST_K[0]}" = "$k"$'\037'"$t" ] || {
    mapfile -d '' -t x < <(jq -Rsj '(try fromjson catch null | objects) // {} | . as $o
        | tojson, ((.at | numbers | floor) // 0 | tostring), ([$ARGS.positional[] | {key: ., value: ($o.clis[.] // null)}] | from_entries | tojson)
        | . + "\u0000"' --args $k < <(if [ "$a" = 1 ]; then printf '%s' "$t"; else cat "$CLIS"; fi) 2>/dev/null) && [ "${#x[@]}" = 3 ] || return 1
    HOST_K=('' "${x[@]}"); [ "$a" != 1 ] || HOST_K[0]=$k$'\037'$t
  }
  old=${HOST_K[1]}
  [ "$one" != due ] || { one=''; [ $((HOST_K[2] + CLI_TTL)) -gt "$EPOCHSECONDS" ] || one=fresh; }
  [ -n "$one" ] || { HOST_R=${HOST_K[3]}; printf '%s\n' "$HOST_R"; return 0; }
  # Each installed CLI and its models: read now, or "*" for those CLIS has (null when it has none).
  for c in $CLINAMES; do
    command -v "$c" >/dev/null || continue
    if [ "$one" = fresh ] || [ "$one" = "$c" ]; then found+=("$c" "$(climodels "$c" || echo null)"); else found+=("$c" '"*"'); fi
  done
  r=$(jq -cn --argjson o "$old" '$ARGS.positional as $p | [range(0; $p | length; 2) | {key: $p[.], value: ($p[. + 1] | fromjson)}
      | if .value == "*" then .value = ($o.clis[.key] // null) else . end] | from_entries' --args "${found[@]}") || return 1
  if [ "$one" = fresh ]; then jq -cn --argjson r "$r" '{at: (now | floor), clis: $r}' > "$CLIS.$$"
  elif [ -n "$one" ]; then jq -c --arg c "$one" --argjson r "$r" '.clis[$c] = $r[$c]' <<<"$old" > "$CLIS.$$"; fi
  [ ! -e "$CLIS.$$" ] || mv -f "$CLIS.$$" "$CLIS" || rm -f "$CLIS.$$"
  HOST_R=$r; printf '%s\n' "$r"
}
# Whether a seat ({model, effort, agent}) can start on this host: its CLI is installed (MISSING; a model the CLI
# does not list is tried, and fails in the card when the CLI cannot run it). Prints why not, naming the seat, its CLI
# and model, and fails. The report is read again once it is CLI_TTL old (hostclis due), so `run` and `serve`, with no
# `watch` beside them to read it, never start a CLI removed longer ago than that. Why a seat cannot start is kept for each
# seat while the host's report is the one it was worked out on (READY_H), so a step that asks again starts no program.
declare -gA READY_V=(); READY_H=''
seatready() { # <builder|reviewer|judge> <its seat>
  local why h; hostclis due >/dev/null; h=$HOST_R
  [ "$h" = "$READY_H" ] || { READY_V=(); READY_H=$h; }
  if [ -n "${READY_V[$2]+1}" ]; then why=${READY_V[$2]}
  else why=$(jq -r --argjson h "$h" "$MISSING"'missing($h) // empty' <<<"$2" 2>/dev/null) || why=''; [ -z "$h" ] || READY_V[$2]=$why; fi
  [ -z "$why" ] || { echo "the $1 is set to $(jq -r "$MISSING"'"\(.agent) \(bare)"' <<<"$2"), and $why: the $1 does not start; set it to a CLI and model this host has (conveyor.sh control, or Rules on the Board)"; return 1; }
}
# The preflight of plan section 6: the builder and the reviewer in force can start on this host (seatready), so the
# loop starts no card on a CLI that is gone. Prints why not and fails; prints
# nothing when both can.
clis() {
  local c r rc=0 CTL_V; if ctlread 2>/dev/null; then c=$CTL_V; else c=null; fi
  # In the calling shell, so what seat and seatready work out is kept there.
  for r in builder reviewer; do seat "$r" "$c" >/dev/null || continue; seatready "$r" "${SEAT_V[$r]}" || rc=1; done
  return $rc
}
# Models through an API proxy. Claude's: card sessions run with --setting-sources "", so a base URL in the user's
# settings.json never reaches them; the host file's claudeProxy, else the pack's models.claudeProxy, names it and the
# NAME of the variable that holds its key (never the key). Prints that object as JSON; nothing when neither names one.
claudeproxy() {
  local p; p=$(jq -ce '.claudeProxy | objects' "$HOST" 2>/dev/null) || packget models.claudeProxy p 2>/dev/null || :
  [ "$p" = null ] || printf '%s' "$p"
}
# Run in a card session's subshell before claude starts: the proxy's base URL, its key from the variable it names,
# and with a base URL that is not api.anthropic.com, ENABLE_TOOL_SEARCH (true unless toolSearch names otherwise).
# Any other Anthropic key in the environment is dropped first, so the proxy is never sent a key it was not named.
proxyenv() {
  local p b k t v=''; p=$(claudeproxy); [ -n "$p" ] || return 0
  b=$(jq -r .baseUrl <<<"$p"); k=$(jq -r '.keyEnv // ""' <<<"$p"); t=$(jq -r '.toolSearch // "true"' <<<"$p")
  [[ ! $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || v=$(envof "$k")
  unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY
  export ANTHROPIC_BASE_URL=$b
  [ -z "$v" ] || export ANTHROPIC_AUTH_TOKEN="$v"
  [[ $b =~ ^https?://api\.anthropic\.com(:[0-9]+)?(/|$) ]] || export ENABLE_TOOL_SEARCH=$t
}
# Codex's: the top-level model_provider of Codex's config.toml and that provider's base_url and env_key, as
# "<name>\037<base_url>\037<env_key>"; nothing when the file names no provider. A provider with no base_url is direct.
codexproxy() {
  local f=${CODEX_HOME:-$HOME/.codex}/config.toml
  [ -r "$f" ] || return 0
  # Each line as tokens: a quoted string (s), a bare word (b) or one of {}[]=,. ; a key is dotted and quoted or not, a
  # value an inline table (read into its keys, at any depth), an array (skipped) or a scalar.
  # A multiline string ("""...""" or '''...''') is read as one statement with the lines up to its close. A basic
  # (double-quoted) string's escapes are decoded, \u and \U to UTF-8 (awk in the C locale, so %c writes one byte).
  LC_ALL=C awk 'function utf8(c) {
      if (c < 128) return sprintf("%c", c)
      if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
      if (c < 65536) return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
      return sprintf("%c%c%c%c", 240 + int(c / 262144), 128 + int(c / 4096) % 64, 128 + int(c / 64) % 64, 128 + c % 64) }
    function unesc(w, ml,   r, i, c, n, k, h, cp) { r = ""; i = 1
      while (i <= length(w)) { c = substr(w, i, 1)
        if (c != "\\") { r = r c; i++; continue }
        c = substr(w, i + 1, 1)
        if (ml && match(substr(w, i + 1), /^[ \t\r]*\n[ \t\r\n]*/)) { i += 1 + RLENGTH; continue }
        n = c == "u" ? 4 : c == "U" ? 8 : c == "x" ? 2 : 0
        if (n) { cp = 0; for (k = 1; k <= n; k++) { h = index("0123456789abcdef", tolower(substr(w, i + 1 + k, 1))); cp = cp * 16 + h - 1 }
          r = r utf8(cp); i += 2 + n; continue }
        k = index("btnfre\"\\", c); r = r (k ? substr("\b\t\n\f\r\033\"\\", k, 1) : c); i += 2 }
      return r }
    function lex(s,   i, j, c, w) { N = 0; P = 1; i = 1; split("", Y)
      while (i <= length(s)) { c = substr(s, i, 1)
        if (c == " " || c == "\t" || c == "\r" || c == "\n") { i++; continue }
        if (c == "#") break
        if ((c == "\"" || c == "\047") && substr(s, i, 3) == c c c) { j = i + 3
          while (j <= length(s) && substr(s, j, 3) != c c c) j += c == "\"" && substr(s, j, 1) == "\\" ? 2 : 1
          if (j > length(s)) return 0
          w = substr(s, i + 3, j - i - 3); sub(/^\r?\n/, "", w); if (c == "\"") w = unesc(w, 1)
          T[++N] = w; Y[N] = "s"; i = j + 3; continue }
        if (c == "\"" || c == "\047") { j = i + 1
          while (j <= length(s) && substr(s, j, 1) != c) j += c == "\"" && substr(s, j, 1) == "\\" ? 2 : 1
          w = substr(s, i + 1, j - i - 1); if (c == "\"") w = unesc(w, 0)
          T[++N] = w; Y[N] = "s"; i = j + 1; continue }
        if (index("{}[]=,.", c)) { T[++N] = c; Y[N] = c; i++; continue }
        j = i; while (j <= length(s) && !index(" \t\r\n{}[]=,.#\"\047", substr(s, j, 1))) j++
        T[++N] = substr(s, i, j - i); Y[N] = "b"; i = j }
      return 1 }
    function keypath(   k) { k = T[P++]; while (Y[P] == "." && P < N) { P++; k = k "." T[P++] } return k }
    function value(pre,   k, d) {
      if (Y[P] == "{") { P++
        while (P <= N && Y[P] != "}") { k = keypath(); if (Y[P] != "=") return; P++; value(pre "." k); if (Y[P] == ",") P++ }
        P++; return }
      if (Y[P] == "[") { d = 0; do { if (Y[P] == "[") d++; else if (Y[P] == "]") d--; P++ } while (d > 0 && P <= N); return }
      v[pre] = T[P++]; while (P <= N && Y[P] != "," && Y[P] != "}" && Y[P] != "]") P++ }
    { L = L $0; if (!lex(L)) { L = L "\n"; next } L = "" }
    N && Y[1] == "[" { P = 1; while (Y[P] == "[") P++; t = keypath(); next }
    N && (Y[1] == "s" || Y[1] == "b") { P = 1; k = keypath(); if (Y[P] == "=") { P++; value((t == "" ? "" : t ".") k) } }
    END { p = v["model_provider"]
      if (p != "") printf "%s\037%s\037%s\n", p, v["model_providers." p ".base_url"], v["model_providers." p ".env_key"] }' "$f"
}
# The model id Codex runs a reviewer model as. One named in full is used as written. A family name (a word of two or
# more letters, such as sol; real Codex model ids hold a digit or a dash) is the newest gpt-<version>-<family> in the proxy's own GET <base>/models list (a GitHub Copilot API
# proxy is asked with no key), else in Codex's models_cache.json. Fails, printing the setting to set, when none matches.
codexmodel() { # <model>
  [[ $1 =~ ^[a-z]{2,}$ ]] || { echo "$1"; return 0; }
  local name='' base='' env='' key='' m=''
  # GET of the URL on stdin's first line, with the bearer key on its second when there is one: the key never on argv.
  # A redirect to another origin is followed without the key. A local, so a variable the user holds as FETCH (a
  # provider's env_key, say) reaches Codex as it was.
  local fetch='import sys, urllib.parse, urllib.request
url, key = sys.stdin.readline().strip(), sys.stdin.readline().strip()
origin = lambda u: urllib.parse.urlsplit(u)[:2]
class SameOrigin(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and origin(new.full_url) != origin(req.full_url): new.remove_header("Authorization")
        return new
req = urllib.request.Request(url, headers={"Authorization": "Bearer " + key} if key else {})
sys.stdout.write(urllib.request.build_opener(SameOrigin).open(req, timeout=10).read().decode())'
  local newest='map(strings | select(test("^gpt-[0-9]+(\\.[0-9]+)*-" + $f + "$")))
    | max_by(sub("^gpt-"; "") | split("-")[0] | split(".") | map(tonumber)) // empty'
  IFS=$'\037' read -r name base env < <(codexproxy)
  if [ -n "$base" ]; then
    [[ $name$base == *[Cc]opilot* ]] || [[ ! $env =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || key=$(envof "$env")
    m=$(printf '%s\n%s\n' "${base%/}/models" "$key" | timeout 20 python3 -I -c "$fetch" 2>/dev/null | jq -r --arg f "$1" "[.data[]?.id, .models[]?.id] | $newest" 2>/dev/null) || m=''
  fi
  # The proxy unreachable, or listing no model of this family: Codex's models_cache.json answers.
  [ -n "$m" ] || m=$(jq -r --arg f "$1" "[.models[]? | .slug // .id] | $newest" "${CODEX_HOME:-$HOME/.codex}/models_cache.json" 2>/dev/null) || m=''
  [ -n "$m" ] || { echo "the reviewer model $1 is a family name and no gpt-<version>-$1 is in $([ -n "$base" ] && echo "the models of ${base%/}/models or ")Codex's models_cache.json: set models.allowed.codex in .conveyor/project.json (and the control record's reviewer) to the full model id"; return 1; }
  echo "$m"
}
# Before a card starts: the reviewer in force, when Codex runs it, resolves to a model id (codexmodel).
codexready() {
  local s m a; s=$(seat reviewer) && jqget "$s" agent a model m || return 0
  [ "$a" = codex ] || return 0
  m=$(codexmodel "$m") || { echo "$m"; return 1; }
}
# For doctor: each role's model and its route, direct or through which proxy. The builder's seat runs build, fix and rebase.
routes() {
  local r s m a p name base env rc=0
  for r in builder reviewer; do
    s=$(seat "$r") || { echo "$r: the pack's models.allowed lists no $r model"; rc=1; continue; }
    jqget "$s" model m agent a || m='' a=''
    if [ "$a" = claude ]; then
      p=$(claudeproxy)
      if [ -n "$p" ]; then echo "$r: $m (claude) through $(jq -r '"\(.baseUrl), key in \(.keyEnv // "no variable")"' <<<"$p")"
      # None named: a card session inherits the engine's own environment, base URL and all.
      elif [ -n "${ANTHROPIC_BASE_URL:-}" ]; then echo "$r: $m (claude) through $ANTHROPIC_BASE_URL, from the environment Conveyor runs in"
      else echo "$r: $m (claude) direct"; fi
    elif [ "$a" = opencode ]; then p=${m#opencode:}; echo "$r: $m (opencode) through its provider ${p%%/*}, as OpenCode's own config and sign-in set it"
    else
      name='' base='' env=''; IFS=$'\037' read -r name base env < <(codexproxy)
      m=$(codexmodel "$m") || { echo "$r: $m"; rc=1; continue; }
      if [ -n "$base" ]; then echo "$r: $m (codex) through $base, Codex's model_provider $name, key in ${env:-no variable}"
      else echo "$r: $m (codex) direct"; fi
    fi
  done
  return $rc
}
# The models in force, as the readers name them: {claude: the sessions', codex: the review's, whichever program runs
# it}; efforts likewise.
inforce() { # [efforts] [the control record, when the caller has read it]
  local a c=${2:-}; [ -n "$c" ] || c=$(ctl 2>/dev/null) || c=null
  packget models.allowed a 2>/dev/null || a=null
  jq -c --argjson c "$c" --arg k "$([ -z "${1:-}" ] && echo model || echo effort)" "$SEATNOW"'(first(seatnow("builder"; $c)) // {}) as $b
    | (first(seatnow("reviewer"; $c)) // {}) as $r | {claude: ($b[$k] // null), codex: ($r[$k] // null)}' <<<"$a"
}
# The model settings of the two seats, as the Board sets them: {builder, reviewer}, each {model, effort: the
# ones in force (seat()), modelFrom, effortFrom: "control" when the control record sets it, else "seed" (the seed's,
# seed()), choices: the models the pack allows the seat (okmodels: the reviewer's Codex's, then its Claude ones),
# allowed: the same by CLI ({<cli>: its models, OpenCode's without the opencode: mark}: the list the Board offers for a
# CLI that lists no models of its own),
# efforts: the efforts the program of the model in force takes, agent: that program (null when no model is in
# force), clis: the CLIs installed on this host that the seat can be set to, each {models: the models it has
# registered (null: it offers no list, so the Board offers allowed's; either way, then a typed name), efforts: the efforts it takes in this seat}, and
# missing: why the seat in force cannot start on this host (MISSING; null when it can)}, and judge, the review's judge
# (judgeseat()): the same fields, its choices (and allowed) the models the pack allows the review and its clis every
# installed one, the reviewer's too, and default: the model it runs on when the record names none (its model is null
# when no model of another family is named; judge is null when the reviewer has no model). null when the pack does not read.
# settings($c; $e; $h) is that answer in jq, from models.allowed (its input), the control record $c, EFFORTS ($e) and
# the host's report $h (hostclis()).
SETTINGS="$SEATNOW$JUDGENOW$MISSING"'def settings($c; $e; $h): . as $a | (first(seatnow("builder"; $c)) // null) as $b | (first(seatnow("reviewer"; $c)) // null) as $r
    | def offer($s; $x): $x | with_entries(.value = {models: .value, efforts: (if $s == "builder" and .key == "opencode" then [] else $e[.key] end)});
      def gone($now): if $now == null then null else $now | missing($h) end;
      def bycli($m): $m | with_entries(.value |= map(sub("^opencode:"; "")));
      def one($s; $k; $now): ($a | [okmodels($s)[][]]) as $ok | ($c // {} | .[$k] // {}) as $o
        | (($o.model != null) and ($o.cli != null or ($ok | index($o.model) != null))) as $set
        | {model: ($now.model // null), effort: ($now.effort // null), modelFrom: (if $set then "control" else "seed" end),
           effortFrom: (if $set and $o.effort != null then "control" else "seed" end), choices: $ok, allowed: bycli($a | okmodels($s)),
           efforts: (if $s == "builder" and $now.agent == "opencode" then [] else $e[$now.agent // {builder: "claude", reviewer: "codex"}[$s]] end), agent: ($now.agent // null),
           clis: offer($s; $h), missing: gone($now)};
    {builder: one("builder"; "model"; $b), reviewer: one("reviewer"; "reviewer"; $r),
     judge: (if $r == null then null else ($a | [okmodels("reviewer") | del(.[$r.agent]) | .[][]]) as $ok | ($a | first(judgenow($c; $r)) // null) as $j
       | ($c // {} | .judge // {}) as $o | ($j != null and $o.model != null and ($o.cli == null or $o.cli == $j.agent) and ({model: $o.model, agent: $j.agent} | ocmark | .model) == $j.model) as $set
       | ($j // {model: null, effort: null, agent: null}) + {modelFrom: (if $set then "control" else "seed" end), effortFrom: (if $set and $o.effort != null then "control" else "seed" end),
           choices: ($a | [okmodels("reviewer")[][]]), allowed: bycli($a | okmodels("reviewer")), efforts: (if $j == null then [] else $e[$j.agent] end), default: $ok[0], clis: offer("judge"; $h), missing: gone($j)} end)};'
modelsettings() { # [the control record, when the caller has read it]
  local a c=${1:-}; [ -n "$c" ] || c=$(ctl 2>/dev/null) || c=null
  packget models.allowed a 2>/dev/null || { echo null; return; }
  jq -c --argjson c "$c" --argjson e "$EFFORTS" --argjson h "$(hostclis)" "$SETTINGS"'settings($c; $e; $h)' <<<"$a" 2>/dev/null || echo null
}
# The cap in force: the control record's, else the seed's (CAP0); nothing when the record does not read.
capnow() { # [the control record, when the caller has read it]
  local c=${1:-}; [ -n "$c" ] || c=$(ctl 2>/dev/null) || c=null
  jq -e --argjson d "$CAP0" 'objects | .cap // $d' <<<"$c" 2>/dev/null
}
# Under the lock: one change to the control record, written whole beside it and moved into place, so a reader finds
# the old record or the new one. Prints the record as it now stands. A bad action or argument changes nothing: exit 2.
control() { # [action [arguments]]
  local c a=${1:-} f=. new x ag es top=0 p=''
  c=$(ctl) || return 1
  [ $# = 0 ] || shift
  bad() { echo "usage: conveyor.sh control [pause | resume | stop | cap <1-100|off> | guard <1-100|off> | hold <issue>... | release <issue>... | order [<issue>...] | unpin <issue>... | rules <P0|P1|P2|P3|followups|push|visible|<areaPrefix><name>>=<on|off>... | model <cli> <model> [effort] | model default | reviewer <cli> <model> [effort] | reviewer default | judge <cli> <model> [effort] | judge default | tests <cli> <model> [effort] | tests default | judge <on|off> | judge always [<kind>...] | account [<name>] | review-account [<name>] | start <queue|held> | dep-guard <on|off> | force <issue> | depends <issue> <add|remove> <issue>...]" >&2; return 2; }
  nums() { local x; for x; do [[ $x =~ ^[1-9][0-9]{0,8}$ ]] || return 1; done; }
  case $a in
    '') [ $# = 0 ] || { bad; return; } ;;
    pause | resume | stop) [ $# = 0 ] || { bad; return; }; f='.mode = {pause: "pause", resume: "run", stop: "stop"}[$a]' ;;
    cap) [ $# = 1 ] && [[ $1 =~ ^(100|[1-9][0-9]?|off)$ ]] || { bad; return; }; f='.cap = ($v[0] | if . == "off" then null else tonumber end)' ;;
    guard) [ $# = 1 ] && [[ $1 =~ ^(100|[1-9][0-9]?|off)$ ]] || { bad; return; }; f='.guard = ($v[0] | if . == "off" then null else tonumber end)' ;;
    hold) [ $# != 0 ] && nums "$@" || { bad; return; }; f='.held = (.held + ($v | map(tonumber)) | unique)' ;;
    release) [ $# != 0 ] && nums "$@" || { bad; return; }; f='.held -= ($v | map(tonumber)) | if .startHeld == [] then . else .startSeen = (.startSeen + ($v | map(tonumber)) | unique) end' ;;
    order) nums "$@" || { bad; return; }; f='.order = reduce ($v[] | tonumber) as $n ([]; if index($n) then . else . + [$n] end)' ;;
    unpin) [ $# != 0 ] && nums "$@" || { bad; return; }; f='.order -= ($v | map(tonumber))' ;;
    # The dependency guard; with it off, `force` lets one issue be picked while issues it depends on are open.
    dep-guard) [ $# = 1 ] && [[ $1 =~ ^(on|off)$ ]] || { bad; return; }; f='.depGuard = ($v[0] == "on")' ;;
    force) [ $# = 1 ] && nums "$@" || { bad; return; }
      [ "$(jq -r .depGuard <<<"$c")" = false ] \
        || { echo "conveyor: the dependency guard is on: #$1 is not built before the issues it depends on; turn the guard off first (control dep-guard off); nothing changed" >&2; return 2; }
      f='.forced = (.forced + ($v | map(tonumber)) | unique)' ;;
    rules) [ $# != 0 ] || { bad; return; }
      # An area rule is the pack's area prefix and a name; push is whether a card that lands is pushed, visible whether
      # a change customers or staff will see needs the owner's yes.
      packget labels.areaPrefix p || return 1
      for x; do [[ $x =~ ^(P[0-3]|followups|push|visible)=(on|off)$ ]] || { [[ $x == "$p"* ]] && [[ ${x#"$p"} =~ ^[^=[:space:]]+=(on|off)$ ]]; } || { bad; return; }; done
      f='reduce ($v[] | capture("^(?<k>.*)=(?<o>on|off)$")) as $r (.; if $r.k | startswith($p) | not then .rules[$r.k] = ($r.o == "on")
           elif $r.o == "off" then .rules.never = (.rules.never + [$r.k] | unique) else .rules.never -= [$r.k] end)' ;;
    # The judge's on or off and the finding kinds it always accepts (no kind clears them) are the record's too. The
    # Tests seat is set as the others are; default is none, and no test action starts.
    model | reviewer | judge | tests)
      if [ "$a" = judge ] && [[ ${1:-} =~ ^(on|off)$ ]]; then [ $# = 1 ] || { bad; return; }; f='.judgeOn = ($v[0] == "on")'
      elif [ "$a" = judge ] && [ "${1:-}" = always ]; then
        for x in "${@:2}"; do [[ $x =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$ ]] || { bad; return; }; done
        f='.judgeAlways = reduce $v[1:][] as $k ([]; if index($k) then . else . + [$k] end)'
      else [ $# -ge 1 ] && [ $# -le 3 ] || { bad; return; }
      if [ "$1" = default ]; then [ $# = 1 ] || { bad; return; }; f='.[$a] = null'; else
      # A CLI installed on this host (hostclis(), which conveyor.sh read afresh for that CLI before the lock) and any
      # model, listed by the CLI or not (the Board's Other…); the pack's models.allowed limits nothing. A model is one
      # word that starts with a letter or a digit, so no CLI reads it as an option. Its effort is one that CLI takes.
      ag=$1; x='^[A-Za-z0-9][]A-Za-z0-9._:/@[-]{0,191}$'
      [ $# -ge 2 ] && [[ " $CLINAMES " == *" $ag "* ]] && [[ $2 =~ $x ]] || { bad; return; }
      x=$(hostclis) && x=$(jq -rn --argjson h "$x" --arg c "$ag" --arg m "$2" "$MISSING"'{model: $m, agent: $c} | missing($h) // empty') || return 1
      [ -z "$x" ] || { echo "conveyor: $x; nothing changed" >&2; return 2; }
      # The OpenCode builder takes no effort (seatnow()).
      es=$(jq -c --arg a "$ag" --arg s "$a" 'if $s == "model" and $a == "opencode" then [] else .[$a] end' <<<"$EFFORTS")
      [ $# = 2 ] || jq -en --argjson e "$es" --arg x "$3" '$e | index($x)' >/dev/null \
        || { echo "conveyor: $ag takes no effort $3 (it takes $(jq -r 'if length == 0 then "none: name the model alone" else join(", ") end' <<<"$es")); nothing changed" >&2; return 2; }
      f='.[$a] = {cli: $v[0], model: $v[1], effort: ($v[2] // null)}'; fi; fi ;;
    # An account the host file lists, by name; with no name, none: the host's default login (for a review, the
    # builder's account). No word stands for none, so every name the host file lists can be chosen, default too.
    account | review-account) [ $# -le 1 ] || { bad; return; }
      x=$([ "$a" = account ] && echo account || echo reviewAccount)
      [ $# = 0 ] || { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] && acctdir "$1" >/dev/null; } \
        || { echo "conveyor: $1 is not one of the accounts the host file $HOST lists; nothing changed" >&2; return 2; }
      f='.'$x' = ($v[0] // null)' ;;
    # Held opens a span and Queue closes it: adopt() holds every issue opened in any span, whenever it first sees it.
    # Each end is the newest issue's number at the switch, not a time: createdAt is in whole seconds, so a time cannot
    # tell an issue opened in the switch's second before it from one opened after it, and GitHub numbers issues in the
    # order they are opened. When the number cannot be read, nothing changes.
    start) [ $# = 1 ] && [[ $1 =~ ^(queue|held)$ ]] || { bad; return; }
      if [ "$(jq -r .start <<<"$c")" != "$1" ]; then
        top=$(timeout 60 gh issue list --state all --limit 1 --json number 2>/dev/null | jq -e '.[0].number // 0 | numbers') \
          || { echo "conveyor: cannot read the newest issue number; nothing changed" >&2; return 1; }
      fi
      f='if .start == $v[0] then . elif $v[0] == "held" then .start = "held" | .startHeld += [{from: $n, to: null}]
         else .start = "queue" | .startHeld[(.startHeld | length) - 1].to = $n end' ;;
    *) bad; return ;;
  esac
  new=$(jq -c --arg a "$a" --arg p "$p" --argjson n "$top" "\$ARGS.positional as \$v | $f" --args "$@" <<<"$c") && [ -n "$new" ] || return 1
  ctlput "$c" "$new" || return 1
  # A release dates only the issues the record held.
  case $a in hold) movedlocked movedhold hold "$new" "$@" ;; release) x=$(jq -r '.held as $h | $ARGS.positional[] | select(tonumber | IN($h[]))' --args "$@" <<<"$c")
    [ -z "$x" ] || movedlocked movedhold release "$new" $x ;; esac
  printf '%s\n' "$new"
}
# `control depends <issue> add|remove <issue>...` (the Board's "Depends on…"): the issue's `Depends on: #N` lines, the
# ones pick reads (DEPS, prompts.sh), changed on GitHub through gh_write; the control record is not touched, and the
# records' lock is not taken (it asks GitHub). add puts the numbers it does not depend on yet at the end of the body's
# last such line, or writes one at the end of the body; remove takes the numbers off every such line (never another
# repository's owner/repo#N), and drops a line left with none. The rest of the body stays byte for byte, so an add and then its remove give the body back. Refused,
# each with its reason and the body unchanged (exit 2): an issue that depends on itself, an issue or a dependency not
# open in the project, a dependency that would make a cycle (cycles(), DEPS), an add to an issue whose card is running
# (the dependency would not stop it), and a remove of a number the issue's lines do not name. Runs in the main
# checkout, so gh reads and writes that project's issues.
depends() ( # <issue> <add|remove> <issue>...
  local n=${1:-} how=${2:-} x open body new d cyc
  [ $# -ge 3 ] && [ $# -le 22 ] && [[ $how =~ ^(add|remove)$ ]] || { echo "usage: conveyor.sh control depends <issue> <add|remove> <issue>..." >&2; exit 2; }
  for x in "$n" "${@:3}"; do [[ $x =~ ^[1-9][0-9]{0,8}$ ]] || { echo "usage: conveyor.sh control depends <issue> <add|remove> <issue>..." >&2; exit 2; }; done
  shift 2
  if [ "$how" = add ]; then for x; do [ "$x" != "$n" ] || { echo "conveyor: #$n cannot depend on itself; nothing changed" >&2; exit 2; }; done; fi
  cd "$MAIN" || exit 1
  open=$(openissues number,body) || { echo "conveyor: the open issues could not be read; nothing changed" >&2; exit 1; }
  body=$(jq -ec --argjson n "$n" '.[] | select(.number == $n) | .body // ""' <<<"$open") \
    || { echo "conveyor: #$n is not an open issue of this project; nothing changed" >&2; exit 2; }
  if [ "$how" = add ]; then
    for x; do jq -e --argjson x "$x" 'any(.[]; .number == $x)' <<<"$open" >/dev/null \
      || { echo "conveyor: #$x is not an open issue of this project; #$n cannot depend on it; nothing changed" >&2; exit 2; }; done
    # A card of the issue with no closing line is running: it was picked already, and pick is the only reader.
    ! stdb ask issue cards "$n" 2>/dev/null | jq -es --argjson n "$n" 'map(select(.issue == $n)) | group_by(.card) | any(all(.step | IN("landed", "closed", "blocked", "pushed") | not))' >/dev/null 2>&1 \
      || { echo "conveyor: #$n: its card is already running; the dependency would not stop it; nothing changed" >&2; exit 2; }
  else
    x=$(jq -nr --argjson b "$body" "$DEPS"'({body: $b} | needs) as $h | [$ARGS.positional[] | select(tonumber | IN($h[]) | not) | "#\(.)"] | join(", ")' --args "$@") || exit 1
    [ -z "$x" ] || { echo "conveyor: #$n has no Depends on: line naming $x; nothing changed" >&2; exit 2; }
  fi
  # The body's line ending is its own (\r\n when it has one); a line is the text between two \n, its \r kept. Both
  # bodies stay JSON strings until the write: a command substitution would drop a trailing newline.
  new=$(jq -nc --argjson b "$body" --arg how "$how" "$DEPS"'def dep: test("^\\s*Depends on:");
      ($ARGS.positional | map(tonumber) | unique) as $v | ($b | split("\n")) as $l
      | if $how == "add" then ({body: $b} | needs) as $h | ([$v[] | select(IN($h[]) | not) | "#\(.)"] | join(", ")) as $t
        | ([range($l | length) | select($l[.] | dep)] | last) as $i | (if $b | test("\r\n") then "\r\n" else "\n" end) as $e
        | if $t == "" then $b
          elif $i != null then $l | .[$i] |= sub("(?<e>\r?)$"; ", \($t)\(.e)") | join("\n")
          elif $b == "" then "Depends on: \($t)"
          elif $b | endswith("\n") then $b + "Depends on: \($t)" + $e
          else $b + $e + "Depends on: \($t)" end
      else [$l[] | if dep then (reduce $v[] as $k (.; gsub(",\\s*(?<![A-Za-z0-9_./-])#\($k)(?![0-9])"; "") | gsub("(?<![A-Za-z0-9_./-])#\($k)(?![0-9])\\s*,?\\s*"; ""))) as $d
          | if $d == . then . elif $d | test("#[0-9]") then $d else empty end else . end] | join("\n") end' --args "$@") || exit 1
  [ "$new" != "$body" ] || { echo "conveyor: #$n already depends on $(printf '#%s, ' "$@" | sed 's/, $//'); nothing changed"; exit 0; }
  if [ "$how" = add ]; then
    # A cycle this change makes: one that holds the issue and was not there before it.
    cyc=$(jq -r --argjson n "$n" --argjson b "$new" --slurpfile cards <(recs 2>/dev/null) "$DEPS"'(cycles($cards)) as $was
        | [map(if .number == $n then .body = $b else . end) | cycles($cards)[] | select(index($n)) | select(. as $c | $was | index([$c]) | not)]
        | first // empty | map("#\(.)") | join(", ")' <<<"$open") || exit 1
    [ -z "$cyc" ] || { echo "conveyor: #$n depending on $(printf '#%s, ' "$@" | sed 's/, $//') would make a dependency cycle ($cyc): none of them would ever be picked; nothing changed" >&2; exit 2; }
  fi
  jq -j . <<<"$new" | gh_write issue edit "$n" --body-file - >/dev/null || { echo "conveyor: the body of #$n could not be written; nothing changed" >&2; exit 1; }
  if [ "$how" = add ]; then echo "conveyor: #$n now waits on $(printf '#%s, ' "$@" | sed 's/, $//')"
  else echo "conveyor: #$n no longer depends on $(printf '#%s, ' "$@" | sed 's/, $//')"; fi
)
ctlput() { # <the record as read> <the new record>: written only when it changed
  [ "$2" = "$1" ] || { printf '%s\n' "$2" > "$CONTROL.new" && mv -f "$CONTROL.new" "$CONTROL"; } \
    || { echo "conveyor: cannot write $CONTROL; the control record is unchanged" >&2; return 1; }
}
# Now, as the health record has it (CONVEYOR_NOW when set).
clock() { jq -rn '(($ENV.CONVEYOR_NOW // "" | tonumber?) // now) | todate'; }
movedread() { jq -ce 'objects' "$MOVED" 2>/dev/null || echo '{}'; }
movedwrite() { printf '%s\n' "$1" > "$MOVED.$$" && mv -f "$MOVED.$$" "$MOVED" || { rm -f "$MOVED.$$"; return 1; }; }
# moved.json has a lock of its own, so a snapshot dating its sight never waits on the records' lock: the loop's
# cards hold that one most of the time on a busy host, and each wait cost a snapshot seconds. `control` takes it
# inside the records' lock, a snapshot alone; nothing takes the records' lock while it holds this one.
movedlocked() { ( flock 3 && "$@" ) 3>>"$MOVED.lock"; }
# Under moved.json's lock: moved.json with the columns a snapshot saw ({"<issue>": {col, other, by}}) when it listed the issues
# (<saw>); prints the times of this sight. An issue in the column it was in keeps its time; one released from Held (left) and seen in Queue
# came there when it was released; one in another column, seen for the first time, or released and seen back in
# Held, is dated <saw> (when it came there before the first snapshot is not known; when it was opened is not it).
# What was known at <saw> or later (a later snapshot's, a hold's or a release's) is kept as it is, so a snapshot that
# ends after a newer one never writes its older sight over it; an issue no longer open is dropped. What it prints is
# its own sight, not what was kept: a hold or release that came while it ran dates the column it moved the issue to,
# not the one this snapshot shows.
movedsaw() { # <cols json> <saw>
  local m sight; m=$(movedread)
  sight=$(jq -c --argjson o "$1" --arg t "$2" '. as $m | $o | with_entries(.key as $k | .value as $s
      | .value = ($m[$k] | {col: $s.col, other: $s.other, by: $s.by, seen: $t, at: (if .col == $s.col and .left == null then .at
          elif .col == "held" and .left != null and $s.col == "queue" then .left else $t end)}))' <<<"$m") \
    && movedwrite "$(jq -c --argjson s "$sight" --arg t "$2" '$s + with_entries(select(.value.seen >= $t))' <<<"$m")" && printf '%s\n' "$sight"
}
# Under moved.json's lock: `control hold` dates each issue in Held from now, unless it was there already and not released
# since; `control release` marks when it left, unless the last snapshot saw something besides your hold and the rules
# keep it in Held, or a rule of the record as it now stands excludes it (a rule turned on since that snapshot no longer
# keeps it), so a hold before the next snapshot dates it anew only when it had left. A hold keeps what the snapshot
# read of the issue (by, other), so a rule turned off before its release still keeps it in Held.
movedhold() { # <hold|release> <the control record as it now stands> <issue>...
  local m new a=$1 c=$2; shift 2; m=$(movedread)
  new=$(jq -c --arg a "$a" --argjson c "$c" --arg t "$(clock)" 'def ruled: .by != null and ((.by.labels | any(IN($c.rules.never[])))
      or (if .by.fu then $c.rules.followups | not else $c.rules[.by.p] == false end));
    reduce $ARGS.positional[] as $k (.; .[$k] |= if $a == "release" then (if . == null or .other or ruled then . else . + {left: $t, seen: $t} end)
      elif .col == "held" and .left == null then .seen = $t else . + {col: "held", at: $t, seen: $t} | del(.left) end) | with_entries(select(.value != null))' --args "$@" <<<"$m") \
    && movedwrite "$new" || echo "conveyor: cannot write $MOVED; Held's time for $* is dated by the next snapshot" >&2
}
# Under the lock (where new issues start is a setting, Queue by default): every open issue
# opened in a span of startHeld joins held, unless it is a follow-up (it builds as before: it inherits its parent's
# yes) or startSeen already has it (held once, or released), which it then joins. So an issue opened while the
# setting is Held is held from its first sight, even when the setting is Queue again by then; one released, before
# its first sight or after, is never held again; and one opened before the switch keeps its place. pick and snapshot call it with the open issues they read.
adopt() { # <open issues json>
  local c new
  c=$(ctl) && new=$(adopted "$c" "$1") && [ -n "$new" ] || return 1
  ctlput "$c" "$new"
}
# The record with adopt's holds added, saved nowhere: adopt saves it, and `pick --dry` reads it as the record. A
# forced issue (`control force`) leaves forced once a card of it has landed or it is no longer open; the card records
# are read only while forced lists one, and a line not whole yet (a card writing it) is skipped.
adopted() { # <control record> <open issues json>
  jq -c --argjson c "$1" --arg fu "$FOLLOWUP" --rawfile r <([[ $1 == *'"forced":[]'* ]] || recs 2>/dev/null) '[.[] | select((.number | IN($c.startSeen[]) | not) and (.labels // [] | any(.name == $fu) | not)
      and (.number as $i | $c.startHeld | any($i > .from and (.to == null or $i <= .to)))) | .number] as $n
    | map(.number) as $open | [$r | splits("\n") | fromjson? | objects | select(.step == "landed") | .issue] as $landed
    | if $n == [] then $c else $c | .held = (.held + $n | unique) | .startSeen = (.startSeen + $n | unique) end
    | if .forced == [] then . else .forced |= map(select(IN($open[]) and (IN($landed[]) | not))) end' <<<"$2"
}
