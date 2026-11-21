# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh auto on | narrow | off | status | band | rules | decide | rulings | standing [<run> | <kind> on|off] | act <kind> <what>`:
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
# - decide: one pass over the ledger's open decisions (the Board's, .claude/scripts/decision.sh list). Each decided
#   one gets its log entry (question, pick, why, reversible), written before decision.sh answers it with its
#   recommended option; each one it leaves gets a line under "## Waiting for the owner", once. The Foreman runs it, and
#   the engine's loop runs it on a new open decision; one pass at a time (decide.lock), so each is decided once.
#   The Foreman's pass first sends the owner's rulings to the hosts (hostrulings), so the engine there reads the new ones.
# - rulings: the owner's picker answers from the ruling log of the Foreman's machine (hostrulings there), read on stdin
#   and kept as <state folder>/auto/rulings.jsonl, in place of the last ones sent: decide reads them beside this
#   machine's ruling log.
# The owner's way of deciding is read from the project's ruling log (.claude/hooks/lib/rulings.sh rulings_log: every
# picker answer the owner gave, with whether it was the recommended option), never written here.
# Test seams: CONVEYOR_LEDGER (decision.sh's), CONVEYOR_RULING_LOG (the ruling log).
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/standing.sh" || exit 1
{ [ $# = 2 ] && [[ $2 =~ ^(on|narrow|off|status|band|rules|decide|rulings|standing)$ ]]; } \
  || { [ $# = 3 ] && [ "$2" = standing ] && [[ $3 == *[![:space:]]* ]]; } \
  || { [ $# = 4 ] && [[ " ${STANDING_KINDS[*]} " == *" $3 "* ]] && { { [ "$2" = standing ] && [[ $4 =~ ^(on|off)$ ]]; } || { [ "$2" = act ] && [[ $4 == *[![:space:]]* ]]; }; }; } \
  || { echo "usage: conveyor.sh auto on | narrow | off | status | band | rules | decide | rulings | standing [<run> | <kind> on|off] | act <kind> <what> (a kind: ${STANDING_KINDS[*]})" >&2; exit 2; }
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
  f=$(CONVEYOR_MAIN=$MAIN bash -c '. "$1" > /dev/null && printf %s "$FD"' _ "$HERE/foreman/lib.sh") && [ -n "$f" ] || return 0
  f=$f/owner-way.md
  [ -s "$f" ] || return 0
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
# there), as the owner answers on this machine and the decide pass there reads their rulings; fails when not sent.
hostrulings() {
  local f out rc
  f=$(mktemp) || return 1
  [ -z "$RL" ] || [ ! -r "$RL" ] || jq -cR 'fromjson? | objects | select(.source == "ask" and .void != true) | {id, utc, source, question, answer, pick}' "$RL" > "$f"
  out=$(ASK_IN=$f CONVEYOR_MAIN=$MAIN bash "$HERE/foreman/foreman.sh" ask "$1" auto rulings 2>&1); rc=$?; rm -f "$f"
  [ "$rc" = 0 ] || echo "conveyor: auto: $1, on its host: the owner's rulings were not sent there: ${out//$'\n'/ }" >&2
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
  local repo
  while IFS= read -r repo; do
    printf '\n%s' "- The engine on the host of $repo decides that record's open decisions too, by these rules, while this session is not running. When you start, run \`CONVEYOR_MAIN=$(printf %q "$MAIN") bash $(printf %q "$HERE/foreman/foreman.sh") ask $repo auto status\`: it names the log there, and tell the owner what it decided."
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

- Run \`$run\` from the main checkout now, and again each time a new open decision is on the Board. It answers each open decision that has a recommended option, that nothing reserves and that the owner's latest ruling on the same question does not answer otherwise, logs it, and lists the rest under "## Waiting for the owner" in $log.
- A question a session sends you that is not in the ledger: decide it the same way. Log it first in $log under "## Decisions" as "### HH:MM <what>", then the bullets **Question**, **Picked**, **Why** (the reasoning and the long-term trade-off) and **Reversible**.
- How the owner decides: $(way). Their recorded picks are in the ruling log ${RL:-(none named)}; read the ones on the same subject before you decide what the ledger does not hold.$p
- Never decide; list under "## Waiting for the owner" instead: anything about $r; any irreversible step; anything against or reopening one of the owner's rulings; a question with no recommended option, or with two good ones.
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
  rulings)
    mkdir -p "$AD" && jq -cR 'fromjson? | objects | select(.source == "ask" and .void != true and (.question | type == "string"))' > "$AD/rulings.$$.new" \
      && mv "$AD/rulings.$$.new" "$AD/rulings.jsonl" || die "the rulings of the owner's machine could not be kept in $AD/rulings.jsonl"
    echo "auto: $(wc -l < "$AD/rulings.jsonl" | tr -d ' ') ruling(s) of the owner's machine kept in $AD/rulings.jsonl" ;;
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
    packget auto.reserved RES || exit 1
    L=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl}
    open='[]'
    if [ -e "$L" ]; then open=$(CONVEYOR_MAIN=$MAIN bash "$DECISION" list | jq -c '[.[] | select(.answeredAt == null)]') || die "the ledger $L could not be read"; fi
    w=$(way) d=0 k=0
    # put <text>: the text added to the log just before its "## Waiting for the owner" heading (the end of "## Decisions").
    put() { P=$1 awk '/^## Waiting for the owner$/ && !done { printf "%s\n\n", ENVIRON["P"]; done = 1 } { print }' "$log" > "$log.new" && mv "$log.new" "$log" || die "the log $log could not be written"; }
    # hold <id> <question> <why>: the decision listed for the owner, once (the section is the log's last).
    hold() { grep -qF -- "- $1: " "$log" || printf -- '- %s: %s (%s)\n' "$1" "$2" "$3" >> "$log" || die "the log $log could not be written"; k=$((k + 1)); }
    while IFS= read -r row; do
      # Split on the unit separator, not on a tab: read joins tabs in a row, so an empty field would move the rest.
      IFS=$'\x1f' read -r id q def asked opts < <(jq -r 'def one: gsub("[\r\n\u001f]+"; " "); [.id, (.question | one), (.proposedDefault | one), .askedAt,
        ((.options // []) | map(one) | join("; "))] | join("\u001f")' <<<"$row")
      # Reserved: a word or phrase of the pack's list in the question, the recommended option or an option.
      t=$(jq -r --argjson r "$RES" '([.question, .proposedDefault] + (.options // []) | join("\n") | ascii_downcase) as $t
        | first($r[] | select(. as $w | $t | contains($w | ascii_downcase))) // ""' <<<"$row")
      if [ -n "$t" ]; then hold "$id" "$q" "reserved: $t"; continue; fi
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
      if e=$(CONVEYOR_MAIN=$MAIN bash "$DECISION" answer "$id" "$def" --asked-at "$asked" 2>&1 >/dev/null); then d=$((d + 1))
      else put "- **Recorded:** no, so it still waits for the owner: ${e//$'\n'/ }"; hold "$id" "$q" "the answer could not be recorded"; fi
    done < <(jq -c '.[]' <<<"$open")
    # The summary, made again from the log: its decisions and the lines waiting for the owner.
    n=$(logged "$log") h=$(waiting "$log")
    S="Decided for the owner: $n. Waiting for the owner: $h. Last pass: $(date '+%F %H:%M')." awk '
      /^## Summary$/ { print; print ""; print ENVIRON["S"]; print ""; skip = 1; next } skip && /^## / { skip = 0 } !skip { print }' "$log" > "$log.new" && mv "$log.new" "$log" \
      || die "the log $log could not be written"
    echo "auto: decided $d, left $k for the owner. Log: $log" ;;
esac
