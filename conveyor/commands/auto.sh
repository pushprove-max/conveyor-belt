# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh auto on | narrow | off | status | band | rules | decide | rulings | send | standing [<run> | <kind> on|off] | act <kind> <what> | reserved`:
# /conveyor-belt:auto, for the project it is called in. While it is on, the Foreman decides the owner's open decisions for them, by the owner's recorded way of
# deciding, and logs each with its reasons; what the pack reserves (auto.reserved) is never decided and waits for the
# owner. Sourced by conveyor.sh.
# - on: the owner is away: decide every open decision that has a recommended option and that nothing reserves, unless
#   the owner's latest ruling on the same question gave another answer.
#   narrow: the owner is here: decide only the formalities, an open decision whose recommended option the owner
#   gave in their latest ruling on the same question (in the ruling log). Each starts a log,
#   <state folder>/auto/<date>-<time>.md: "## Summary", "## Decisions", "## Waiting for the owner". off ends it.
#   Each of the three is also set on the host of each record of this checkout's Foreman whose main is on another
#   machine (tohosts), with its own log there: the engine on the machine that has the record runs decide itself
#   (lib/needsask.sh needsauto), so auto goes on while the owner's machine is off or the Foreman session is not running.
# - status: one line for the owner. band: {scope: full|narrow|off, since, count} for the plugin's band (hooks/auto.tsx).
#   rules: what the Foreman is told while it is on; nothing while it is off. When the project keeps owner-way.md, its
#   written profile of how the owner decides, in the Foreman's folder (beside rules.md), the rules name it.
# - standing: the standing kinds of routine yes this checkout's pack turns on (lib/standing.sh), which hold whether
#   auto is on or off; nothing when no kind is on. The Foreman's start asks each of its records for them (foreman.sh),
#   on the host that has the record, as the Board turns them on or off there. <run>: how the rules name the engine to
#   run their commands with (default: this engine); the Foreman's start gives `foreman.sh ask <repo>`, which reaches
#   the record from the Foreman's machine.
#   standing <kind> on|off: the Board's Rules tab turns one standing kind on or off in the pack (auto.standing).
#   act <kind> <what>: the Foreman logs one act under a kind that is on (the ruling log, source "standing") and gets the
#   line it tells the owner; a kind that is off is refused, so the step goes to the owner.
#   reserved: what waits for the owner, as one JSON list (lib/standing.sh heldlist): the pack's auto.reserved and the
#   owner's profile items. The Foreman's watcher asks it, on the record's host, before it retries a review block.
# - decide: one pass over the ledger's open decisions (the Board's, .claude/scripts/decision.sh list). Each decided
#   one gets its log entry (question, pick, why, reversible), written before decision.sh answers it with its
#   recommended option; each one it leaves gets a line under "## Waiting for the owner", once. The Foreman runs it, and
#   the engine's loop runs it on a new open decision; one pass at a time (decide.lock), so each is decided once.
#   The whole text of a question the engine cut (<state folder>/auto/asked/<id>.txt) is checked for reserved items too;
#   a blocked-card or nightly question that may be cut and has no such file waits for the owner.
#   A blocked-card decision whose issue was already retried (answered with its recommended option) for the same block
#   reason is left for the owner, not retried again. The owner's own "Retry keeping the work" counts; their "Fresh retry" does not.
#   The Foreman's pass first sends the owner's rulings to the hosts (hostrulings), so the engine there reads the new ones.
# - rulings: the owner's picker answers from the ruling log of the Foreman's machine (hostrulings there), read on stdin
#   and kept as <state folder>/auto/rulings.jsonl, in place of the last ones sent: decide reads them beside this
#   machine's ruling log. The row of the owner's profile items sent with them ({source: "profile", held}) is kept in
#   the same file, and decide holds those items as it holds the profile's (lib/standing.sh profileheld).
# - send: the owner's rulings and profile items sent again to each host whose last send (hostrulings) carried other
#   profile items, so an item the owner adds to the profile holds there before the Foreman's next `auto decide`, and
#   an item they take out stops holding there, whether auto is on or off: the watcher's review-retry asks the host's
#   `auto reserved` in both. The Foreman's Stop hook runs it (foreman/stop.sh state) at the end of each turn.
#   Fails, each host not reached named on stderr (hostrulings), when the items were not sent to a host or the profile
#   cannot be read; a host not reached is sent them again at the next run, as its last send still carries the old items.
# The owner's way of deciding is read from the project's ruling log (.claude/hooks/lib/rulings.sh rulings_log: every
# picker answer the owner gave, with whether it was the recommended option), never written here.
# Test seams: CONVEYOR_LEDGER (decision.sh's), CONVEYOR_RULING_LOG (the ruling log).
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/standing.sh" || exit 1
{ [ $# = 2 ] && [[ $2 =~ ^(on|narrow|off|status|band|rules|decide|rulings|send|standing|reserved)$ ]]; } \
  || { [ $# = 3 ] && [ "$2" = standing ] && [[ $3 == *[![:space:]]* ]]; } \
  || { [ $# = 4 ] && [[ " ${STANDING_KINDS[*]} " == *" $3 "* ]] && { { [ "$2" = standing ] && [[ $4 =~ ^(on|off)$ ]]; } || { [ "$2" = act ] && [[ $4 == *[![:space:]]* ]]; }; }; } \
  || { echo "usage: conveyor.sh auto on | narrow | off | status | band | rules | decide | rulings | send | standing [<run> | <kind> on|off] | act <kind> <what> | reserved (a kind: ${STANDING_KINDS[*]})" >&2; exit 2; }
AD=$ST/auto MODE=$ST/auto/mode.json LAST=$ST/auto/last.json DECISION=$HERE/../.claude/scripts/decision.sh
die() { echo "conveyor: auto: $*" >&2; exit 1; }
# The mode while on, as JSON: {scope, since, log}; fails while off.
mode() { jq -ce 'select(type == "object" and (.scope == "full" or .scope == "narrow") and (.since | type == "string") and (.log | type == "string"))' "$MODE" 2>/dev/null; }
# <log>: its decisions, the entries under "## Decisions", an entry whose answer could not be recorded left out.
logged() { awk '/^## / { on = ($0 == "## Decisions") } on && /^### / { n++ } on && /^- \*\*Recorded:\*\* no/ { n-- } END { print n + 0 }' "$1" 2>/dev/null || echo 0; }
# <log>: the entries under "## Waiting for the owner": a "- <id>: " line, or a "### " entry with its "- **...**" lines.
waiting() { awk '/^## / { on = ($0 == "## Waiting for the owner") } on && (/^### / || (/^- / && !/^- \*\*/)) { n++ } END { print n + 0 }' "$1" 2>/dev/null || echo 0; }
m=$(mode) || m=''
if [ -n "$m" ]; then IFS=$'\t' read -r scope since log < <(jq -r '[.scope, .since, .log] | @tsv' <<<"$m"); fi
RL=$(rulingslog) || RL=''
# The owner's rulings: this machine's ruling log and those the Foreman's machine sent (rulings), each that can be read.
RLS=(); [ -z "$RL" ] || [ ! -r "$RL" ] || RLS+=("$RL"); [ ! -r "$AD/rulings.jsonl" ] || RLS+=("$AD/rulings.jsonl")
# The owner's way of deciding, from their last 100 picker answers in those rulings (one sent from the owner's machine
# and also in this machine's log is counted once).
way() {
  [ "${#RLS[@]}" != 0 ] || { echo "the ruling log ${RL:-(none named)} cannot be read, so the owner's picks are not known"; return; }
  jq -nRr '[inputs | fromjson? | objects | select(.source == "ask" and .void != true)]
    | unique_by([.id, .utc, .question, .answer] | tostring) | sort_by(.utc // "" | tostring) | .[-100:] | length as $n
    | ([.[] | select(.pick == "recommended")] | length) as $k
    | if $n == 0 then "the ruling log holds no picker answer of the owner yet"
      else "the owner took the recommended option in \($k) of their last \($n) picker answers" end' "${RLS[@]}"
}
reserved() { packget auto.reserved RES && jq -r 'join(", ")' <<<"$RES"; }
# The project's written profile of how the owner decides, beside the Foreman's rules.md (the plugin ships none): when
# it is there, a newline and the rules' line that names it, else nothing. The folder is the one the Foreman's own
# reading (foreman/lib.sh FD) names: the launcher's, else for a group the first-named project's, never this checkout's.
profile() {
  local f
  f=$(profilefile) || return 0
  printf '\n%s' "- The owner's written profile of how they decide is in $f: read it before you decide. Follow its \"Never decide; ask\" and \"Hard lines\" sections as you follow the pack's auto.reserved."
}
# The records of this checkout's Foreman (foreman/lib.sh mine) whose main checkout is not on this machine, one name a
# line: the belt runs on another host, whose engine decides that record's open decisions (lib/needsask.sh needsauto) by
# its own auto mode and log.
remote() {
  local repo main
  while IFS=$'\t' read -r repo main; do [ -n "$repo" ] && [ ! -d "$main" ] && printf '%s\n' "$repo"; done \
    < <(CONVEYOR_MAIN=$MAIN bash -c '. "$1" > /dev/null && mine' _ "$HERE/foreman/lib.sh" 2>/dev/null)
  return 0
}
# hostrulings <repo>: the owner's picker answers of this machine's ruling log sent to the record's host (`auto rulings`
# there), as the owner answers on this machine and the decide pass there reads their rulings; and with them one row
# {source: "profile", held}, the items of the owner's profile (profileheld), as the profile is in the Foreman's folder
# on this machine, not there, and the decide pass there must hold them too. Fails when not sent, or when the profile
# cannot be read (then nothing is sent). The items sent are kept in $AD/sent/<repo>.json, which send reads.
hostrulings() {
  local f out rc h
  h=$(profileheld) || { echo "conveyor: auto: $1, on its host: the owner's profile could not be read, so the owner's rulings were not sent there" >&2; return 1; }
  f=$(mktemp) || return 1
  [ -z "$RL" ] || [ ! -r "$RL" ] || jq -cR 'fromjson? | objects | select(.source == "ask" and .void != true) | {id, utc, source, question, answer, pick}' "$RL" > "$f"
  jq -cn --argjson h "$h" '{source: "profile", held: $h}' >> "$f" || { rm -f "$f"; return 1; }
  out=$(ASK_IN=$f CONVEYOR_MAIN=$MAIN bash "$HERE/foreman/foreman.sh" ask "$1" auto rulings 2>&1); rc=$?; rm -f "$f"
  if [ "$rc" = 0 ]; then mkdir -p "$AD/sent" && printf '%s\n' "$h" > "$AD/sent/${1//\//_}.json" || :
  else echo "conveyor: auto: $1, on its host: the owner's rulings were not sent there: ${out//$'\n'/ }" >&2; fi
  return "$rc"
}
# tohosts <on|narrow|off>: the same mode set on the host of each such record (foreman.sh ask), so the engine there
# decides while this machine is off or the Foreman session is not running; one line for each host. On or narrow is
# set only once the owner's rulings are sent there (hostrulings): without them, the engine there could decide against one.
tohosts() {
  local repo out
  while IFS= read -r repo; do
    if [ "$1" != off ] && ! hostrulings "$repo"; then echo "conveyor: auto: $repo, on its host: auto $1 was not set there, so the engine there keeps its own mode" >&2
    elif out=$(CONVEYOR_MAIN=$MAIN bash "$HERE/foreman/foreman.sh" ask "$repo" auto "$1" 2>&1); then echo "$repo, on its host: ${out##*$'\n'}"
    else echo "conveyor: auto: $repo, on its host: auto $1 was not set there, so the engine there keeps its own mode: ${out//$'\n'/ }" >&2; fi
  done < <(remote)
}
# The rules' lines for those records: where the engine's own decisions are logged. Each starts with a newline.
hostsrules() {
  local repo l=''
  while IFS= read -r repo; do
    # The command's file is made by the Foreman's start; a session that began before this engine has not run that start, so make it here.
    [ -n "$l" ] || l=$(CONVEYOR_MAIN=$MAIN bash -c '. "$1" > /dev/null && launcher && printf %s "$LAUNCHER"' _ "$HERE/foreman/lib.sh") || die "the Foreman's foreman.sh command could not be made"
    printf '\n%s' "- The engine on the host of $repo decides that record's open decisions too, by these rules, while this session is not running. When you start, run \`CONVEYOR_MAIN=$(printf %q "$MAIN") $(printf %q "$l") ask $repo auto status\`: it names the log there, and tell the owner what it decided."
  done < <(remote)
}

case $2 in
  on|narrow)
    want=$([ "$2" = on ] && echo full || echo narrow)
    if [ -n "$m" ]; then
      [ "$scope" = "$want" ] && { echo "auto $2 is already on (since $since). Log: $log"; tohosts "$2"; exit 0; }
      echo "conveyor: auto is on in $scope mode (since $since): run /conveyor-belt:auto off first, then /conveyor-belt:auto $2" >&2; exit 2
    fi
    r=$(reserved) || exit 1
    mkdir -p "$AD" || die "the folder $AD could not be made"
    since=$(date '+%F %H:%M'); log=$AD/$(date +%F-%H%M%S) i=1
    # A log started in the same second as an earlier one is a new file beside it, never written over it.
    [ ! -e "$log.md" ] || { while [ -e "$log-$i.md" ]; do i=$((i + 1)); done; log=$log-$i; }; log=$log.md
    { printf '# Decisions made for the owner (auto%s, from %s)\n\n' "$([ "$want" = full ] || echo ' narrow')" "$since"
      if [ "$want" = full ]; then echo 'The owner handed over their open decisions with /conveyor-belt:auto on.'
      else echo 'The owner turned on /conveyor-belt:auto narrow: only formalities (an answer they already gave to the same question) are decided without asking.'; fi
      printf 'Each entry gives the question, the pick, why, and whether it can be reversed.\nNever decided for the owner: %s.\n\n' "$r"
      printf '## Summary\n\n(nothing yet)\n\n## Decisions\n\n## Waiting for the owner\n'
    } > "$log" && jq -n --arg s "$want" --arg t "$since" --arg l "$log" '{scope: $s, since: $t, log: $l}' > "$MODE.new" && mv "$MODE.new" "$MODE" \
      || die "the log $log or the mode $MODE could not be written"
    echo "auto $([ "$want" = full ] && echo ON || echo 'NARROW on'): $([ "$want" = full ] && echo 'open decisions are decided for the owner' || echo 'formalities are decided; everything else still goes to the owner') until /conveyor-belt:auto off. Log: $log"
    tohosts "$2" ;;
  off)
    [ -n "$m" ] || { echo "auto is already off."; tohosts off; exit 0; }
    n=$(logged "$log") h=$(waiting "$log")
    printf '\n---\nauto turned off at %s.\n' "$(date '+%F %H:%M')" >> "$log"
    jq -n --argjson n "$n" '{count: $n}' > "$LAST" && rm -f "$MODE" || die "the mode $MODE could not be ended"
    echo "auto OFF after $n decided, $h waiting for the owner: decisions go back to the owner. Log: $log"
    tohosts off ;;
  status)
    if [ -n "$m" ]; then echo "auto is $([ "$scope" = full ] && echo ON || echo NARROW) since $since: $(logged "$log") decision(s). Log: $log"
    else echo "auto is OFF. Use /conveyor-belt:auto on, /conveyor-belt:auto narrow or /conveyor-belt:auto off."; fi ;;
  band)
    if [ -n "$m" ]; then jq -cn --arg s "$scope" --arg t "$since" --argjson n "$(logged "$log")" '{scope: $s, since: $t, count: $n}'
    else jq -cn --argjson n "$(jq -r '.count // 0 | numbers' "$LAST" 2>/dev/null || echo 0)" '{scope: "off", since: null, count: $n}'; fi ;;
  rules)
    [ -n "$m" ] || exit 0
    r=$(reserved) || exit 1
    run="bash $(printf %q "$HERE/conveyor.sh") auto decide" p=$(profile)$(hostsrules)
    if [ "$scope" = full ]; then
      cat <<EOF
# AUTO IS ON (since $since, /conveyor-belt:auto on)

The owner is away and has handed you their open decisions. Pick what is best for the project's long-term health, not the fastest path.

- Run \`$run\` from the main checkout now, and again each time a new open decision is on the Board. It answers each open decision that has a recommended option, that nothing reserves, that the owner's latest ruling on the same question does not answer otherwise and that is not a blocked card whose issue was already retried with its recommended step for the same block reason, logs it, and lists the rest under "## Waiting for the owner" in $log.
- A question a session sends you that is not in the ledger: decide it the same way. Log it first in $log under "## Decisions" as "### HH:MM <what>", then the bullets **Question**, **Picked**, **Why** (the reasoning and the long-term trade-off) and **Reversible**.
- How the owner decides: $(way). Their recorded picks are in the ruling log ${RL:-(none named)}; read the ones on the same subject before you decide what the ledger does not hold.$p
- Never decide; list under "## Waiting for the owner" instead: anything about $r; any irreversible step; anything against or reopening one of the owner's rulings; a blocked card whose issue was already retried with its recommended step for the same block reason; a question with no recommended option, or with two good ones.
- Do not ask the owner: the picker is refused while this is on. Keep "## Summary" in the log current.
- When the owner next types to you, give a short account of what you decided and point at the log. This stays on until /conveyor-belt:auto off.
EOF
    else
      cat <<EOF
# AUTO NARROW IS ON (since $since, /conveyor-belt:auto narrow)

The owner is here. Decide only the formalities; ask them everything else as usual (the picker is allowed).

- Run \`$run\` from the main checkout now, and again each time a new open decision is on the Board. It answers only an open decision whose recommended option the owner gave in their latest ruling on the same question (in ${RL:-the ruling log}) and that nothing reserves, logs it in $log, and leaves the rest for the owner.
- Tell the owner each one in one line in your next reply: "Decided without asking: <what>, because <why>; say 'reverse <id>' to undo."
- Never decide: anything about $r; any irreversible step; anything against or reopening one of the owner's rulings. When unsure, ask the owner.$p
EOF
    fi ;;
  standing)
    if [ $# != 4 ]; then r=$(reserved) || exit 1; standingrules "${3:-bash $(printf %q "$HERE/conveyor.sh")}" "$r"; exit; fi
    # The pack's list as it was, with the kind added or taken out; each kind once, in STANDING_KINDS' order.
    packset --arg k "$3" --argjson on "$([ "$4" = on ] && echo true || echo false)" --argjson all "$(jq -cn '$ARGS.positional' --args "${STANDING_KINDS[@]}")" \
      '.auto.standing = ((.auto.standing // []) - [$k] + (if $on then [$k] else [] end) | . as $s | $all | map(select(IN($s[]))))' || exit 1
    echo "auto: the standing kind $3 is $4. $([ "$4" = on ] && echo 'The Foreman takes it without asking, and logs each act.' || echo 'Each such step goes to the owner again.')" ;;
  act)
    standingon "$3" || { echo "conveyor: auto: the standing kind $3 is not on in the pack (auto.standing), so this step goes to the owner: ask them" >&2; exit 1; }
    id=$(standinglog "$3" "${4//$'\n'/ }") || exit 1
    echo "Done without asking ($3): ${4//$'\n'/ }; logged as $id." ;;
  reserved) heldlist r || die "the pack's auto.reserved or the owner's profile could not be read"; echo "$r" ;;
  rulings)
    # One file, so one rename keeps the rulings and the profile items sent with them together.
    mkdir -p "$AD" && jq -cR 'fromjson? | objects | select((.source == "ask" and .void != true and (.question | type == "string"))
      or (.source == "profile" and (.held | type == "array"))) | if .source == "profile" then {source, held: [.held[] | strings]} else . end' > "$AD/rulings.$$.new" \
      && mv "$AD/rulings.$$.new" "$AD/rulings.jsonl" || { rm -f "$AD/rulings.$$.new"; die "the rulings of the owner's machine could not be kept in $AD/rulings.jsonl"; }
    echo "auto: $(jq -nR '[inputs | fromjson | select(.source == "ask")] | length' "$AD/rulings.jsonl") ruling(s) and $(jq -nR '[inputs | fromjson | select(.source == "profile") | .held[]] | unique | length' "$AD/rulings.jsonl") item(s) of the owner's profile from the owner's machine kept in $AD/rulings.jsonl" ;;
  send)
    # Not only while auto is on: the host's watcher holds review blocks by the items it last got (`auto reserved`,
    # foreman/lib.sh retryable()) whatever the mode, so an item the owner takes out must stop holding there too.
    h=$(profileheld) || die "the owner's profile could not be read, so it was not sent to the hosts"
    # A host not reached keeps deciding by the items it last got, so the caller (the Stop hook) is told: it fails.
    rc=0
    while IFS= read -r rep; do [ "$(cat "$AD/sent/${rep//\//_}.json" 2>/dev/null)" = "$h" ] || hostrulings "$rep" || rc=1; done < <(remote)
    exit "$rc" ;;
  decide)
    [ -n "$m" ] || { echo "conveyor: auto is off; /conveyor-belt:auto on or narrow turns it on" >&2; exit 2; }
    # The rulings the owner gave since they were last sent go to the hosts first, so the engine there decides by them.
    while IFS= read -r rep; do hostrulings "$rep" || :; done < <(remote)
    # One pass at a time: the engine's pass (lib/needsask.sh needsauto) and the Foreman's both start on a new decision,
    # and two passes that read it open at once would each decide it. The mode is read again once the lock is held.
    { exec {lk}>>"$AD/decide.lock"; } 2>/dev/null && flock -w 120 "$lk" || die "another auto pass held $AD/decide.lock for 120 s"
    m=$(mode) || die "auto went off while this pass waited"
    IFS=$'\t' read -r scope since log < <(jq -r '[.scope, .since, .log] | @tsv' <<<"$m")
    [ -f "$log" ] || die "the log $log is gone"
    # The pack's auto.reserved and the owner's profile (owner-way.md): its "Never decide; ask" and "Hard lines" items.
    heldlist RES || die "the pack's auto.reserved or the owner's profile could not be read"
    L=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl}
    open='[]' seen='' cnt='{}'
    # A blocked-card decision's key: its issue and the first 200 characters of its block reason, digits as N (the card id and the
    # timings in a reason differ on each block of one issue, and the engine cut the reason at 300 characters before the digits
    # changed its length, so its end differs). seen: the keys of the blocked-card decisions already answered with the recommended
    # retry (the ledger's answered rows, then each one this pass answers).
    bkey='def bkey: (.question // "") | (capture("\\(#(?<n>[0-9]+)\\) is blocked with its work kept: (?<r>.*)\\. What should the engine do with it\\?\\z")? // empty)
      | "\(.n) \(.r | gsub("[0-9]+(\\.[0-9]+)?"; "N") | .[:200])";'
    if [ -e "$L" ]; then
      # Each decision's count of ledger rows (hold()), read before the rows: a row added between the two reads then
      # gives a count lower than the row's, never one a later asking will have.
      cnt=$(jq -cs 'group_by(.id) | map({key: .[0].id, value: length}) | from_entries' "$L") || die "the ledger $L could not be read"
      all=$(CONVEYOR_MAIN=$MAIN bash "$DECISION" list) || die "the ledger $L could not be read"
      open=$(jq -c '[.[] | select(.answeredAt == null)]' <<<"$all") || die "the ledger $L could not be read"
      seen=$(jq -r "$bkey"'.[] | select(.answeredAt != null and (.id | startswith("blocked-")) and .answer == .proposedDefault) | bkey' <<<"$all") || die "the ledger $L could not be read"
    fi
    w=$(way) d=0 k=0
    # put <text>: the text added to the log just before its "## Waiting for the owner" heading (the end of "## Decisions").
    put() { P=$1 awk '/^## Waiting for the owner$/ && !done { printf "%s\n\n", ENVIRON["P"]; done = 1 } { print }' "$log" > "$log.new" && mv "$log.new" "$log" || die "the log $log could not be written"; }
    # hold <id> <question> <why>: the decision listed for the owner, once (the section is the log's last): a decision asked
    # again under its id gets its line written again in place, so the log shows the question the owner has now. Its id and
    # its count of ledger rows ("<id> <count>") go to <log>.seen, a line each, once: a decision asked again or reopened
    # keeps its id, and in the same second its whole row too (decision.sh stamps whole seconds), but the ledger only
    # grows, a row for each ask, answer and reopen. The engine's needsauto() (lib/needsask.sh) runs a pass for an open
    # decision whose line no pass wrote.
    hold() { local s
      P="- $1: " L=$(printf -- '- %s: %s (%s)' "$1" "$2" "$3") awk '/^## / { on = ($0 == "## Waiting for the owner") }
        on && index($0, ENVIRON["P"]) == 1 { if (!done) print ENVIRON["L"]; done = 1; next } { print } END { if (!done) print ENVIRON["L"] }' \
        "$log" > "$log.new" && mv "$log.new" "$log" || die "the log $log could not be written"; k=$((k + 1))
      s=$(jq -r --argjson c "$cnt" '"\(.id | gsub("[\r\n]+"; " ")) \($c[.id] // 0)"' <<<"$row") \
        && { grep -qxF -- "$s" "$log.seen" 2>/dev/null || printf '%s\n' "$s" >> "$log.seen"; } || die "the file $log.seen could not be written"; }
    # unhold <id>: the decision's line taken out of "## Waiting for the owner" once this pass answered it: a decision held,
    # then asked again under its id and answered here, no longer waits, and the summary counts that section's lines.
    unhold() { P="- $1: " awk '/^## / { on = ($0 == "## Waiting for the owner") } on && index($0, ENVIRON["P"]) == 1 { next } { print }' \
      "$log" > "$log.new" && mv "$log.new" "$log" || die "the log $log could not be written"; }
    while IFS= read -r row; do
      # Split on the unit separator, not on a tab: read joins tabs in a row, so an empty field would move the rest.
      IFS=$'\x1f' read -r id q def asked opts < <(jq -r 'def one: gsub("[\r\n\u001f]+"; " "); [.id, (.question | one), (.proposedDefault | one), .askedAt,
        ((.options // []) | map(one) | join("; "))] | join("\u001f")' <<<"$row")
      # Reserved: a word or phrase of the pack's list, or an item of the owner's profile, in the question, the
      # recommended option or an option. A question the engine cut (lib/needsask.sh askcut) names only the items held when
      # it was put, so its whole text, kept in $AD/asked/<id>.txt, is read too: an item held since then is past the cut.
      # An engine before that file put such a question with no kept text, and the loop keeps it there only on its next
      # pass (needsask, needsmain askkeep): until then a question of 300 characters or more there may be cut, so it waits.
      # The engine keeps the text of each one of 300 or more, so a question of exactly 300 waits only until that pass.
      # An empty file is taken as none: askkeep renames a whole file into place and never writes an empty one.
      wt=''
      if [[ $id =~ ^(blocked|mainred)-[A-Za-z0-9._-]+$ ]]; then
        if [ -s "$AD/asked/$id.txt" ]; then
          wt=$(cat "$AD/asked/$id.txt") || { hold "$id" "$q" "the whole text of its cut question could not be read"; continue; }
        elif jq -e '.question | (capture("^Card \\S+ \\(#[0-9]+\\) is blocked with its work kept: (?<r>.*)\\. What should the engine do with it\\?$"; "s")
            // capture("^Issue #[0-9]+ was filed by the nightly whole test for a test that fails on main \\((?<r>.*)\\), and the engine holds it\\. What should the engine do with it\\?$"; "s")
            // {r: .}) | .r | length >= 300' <<<"$row" >/dev/null; then
          hold "$id" "$q" "its question may be cut, and its whole text is not kept yet"; continue
        fi
      fi
      t=$(jq -r --argjson r "$RES" --arg w "$wt" '([.question, .proposedDefault, $w] + (.options // []) | join("\n") | ascii_downcase) as $t
        | first($r[] | select(. as $w | $t | contains($w | ascii_downcase))) // ""' <<<"$row")
      if [ -n "$t" ]; then hold "$id" "$q" "reserved: $t"; continue; fi
      # A card blocked again for a reason its issue was already retried for goes to the owner (rules.md "Cards": a repeated
      # block is the owner's), not to a third try that meets the same check.
      bk=$(jq -r "$bkey"'bkey' <<<"$row")
      if [ -n "$bk" ] && grep -qxF -- "$bk" <<<"$seen"; then hold "$id" "$q" "this issue was already retried with its recommended step for the same block reason"; continue; fi
      # A picker ask with no "(Recommended)" option is in the ledger with the default "none" (ask-records-decision.sh).
      [ -n "${def//[[:space:]]/}" ] && [ "$def" != none ] || { hold "$id" "$q" "no recommended option"; continue; }
      # The owner's latest ruling on the same question: its id and whether it gave the recommended option ("true" or
      # "false"; empty when there is none). Only the latest counts: an earlier answer the owner later changed is not theirs.
      # The ruling log keeps the label as picked, "(Recommended)" and all; the ledger's default has it cut off.
      # The rulings are this machine's ruling log and those the Foreman's machine sent (rulings); the latest by its time.
      rid='' same=''
      if [ "${#RLS[@]}" != 0 ]; then
        IFS=$'\x1f' read -r rid same <<<"$(jq -nRr --arg q "$q" --arg d "$def" 'def flat: ascii_downcase | [scan("[a-z0-9]+")] | join(" ");
          [inputs | fromjson? | objects | select(.source == "ask" and .void != true and ((.question // "") | flat) == ($q | flat))]
          | sort_by(.utc // "" | tostring) | last
          | select(. != null) | [(.id // "" | tostring), (((.answer // "") | sub("\\s*\\(Recommended\\)\\s*$"; "") | flat) == ($d | flat) | tostring)]
          | join("\u001f")' "${RLS[@]}")"
      fi
      if [ "$same" = false ]; then hold "$id" "$q" "against the owner's latest ruling${rid:+ $rid} on this question"; continue; fi
      why="it is the recommended option, and $w"
      if [ "$scope" = narrow ]; then
        [ "$same" = true ] || { hold "$id" "$q" "narrow: not a formality, as the owner never gave this answer to this question"; continue; }
        why="the owner already gave this answer to the same question (ruling $rid)"
      fi
      put "$(printf '### %s %s: %s\n- **Question:** %s%s\n- **Picked:** %s\n- **Why:** %s.\n- **Reversible:** yes: the owner replaces the answer on the Board, or with `decision.sh answer %s <answer> --correct`.\n' \
        "$(date +%H:%M)" "$id" "${q:0:100}" "$q" "${opts:+ (options: $opts)}" "$def" "$why" "$id")"
      if e=$(CONVEYOR_MAIN=$MAIN bash "$DECISION" answer "$id" "$def" --asked-at "$asked" 2>&1 >/dev/null); then d=$((d + 1)); unhold "$id"; [ -z "$bk" ] || seen+=$'\n'$bk
      else put "- **Recorded:** no, so it still waits for the owner: ${e//$'\n'/ }"; hold "$id" "$q" "the answer could not be recorded"; fi
    done < <(jq -c '.[]' <<<"$open")
    # The summary, made again from the log: its decisions and the lines waiting for the owner.
    n=$(logged "$log") h=$(waiting "$log")
    S="Decided for the owner: $n. Waiting for the owner: $h. Last pass: $(date '+%F %H:%M')." awk '
      /^## Summary$/ { print; print ""; print ENVIRON["S"]; print ""; skip = 1; next } skip && /^## / { skip = 0 } !skip { print }' "$log" > "$log.new" && mv "$log.new" "$log" \
      || die "the log $log could not be written"
    echo "auto: decided $d, left $k for the owner. Log: $log" ;;
esac
