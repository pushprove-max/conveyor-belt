# SPDX-License-Identifier: Apache-2.0
# The control record, whole: the file's keys over CTL0's, so a record written before a key existed still reads.
# mode is run, pause or stop; cap and guard are a number or null; held and order are issue numbers; rules.never is
# the area labels never built, rules.push whether a card that lands is pushed (off: land only, owed()), rules.visible whether a visible change
# needs the owner's yes (yesrule()), rules.lint the rule Lint check (lintgate(), lib/lint.sh), rules.testissues, foremanissues, followupissues, releaseissues and splitissues the Rules tab's Cards with no GitHub issue: Tests page actions, the Foreman's orders, review follow-ups, release fix cards and split parts, each On while its rule is false (testissue(), cardnew(), lib/testaction.sh; followups(), lib/followups.sh; relfixes(), lib/fulltest.sh; splitcheck(), lib/slices.sh), rules.split the rule Split large issues, off, shadow or on (splitcheck(), lib/slices.sh), rules.pick the rule Pick settings, the same (modelpick(), lib/modelpick.sh), picks the owner's decision on each group's trial challenger ({"<small|medium> <docs|code>": {decision: promote, keep, drop, add or next, at, challenger and promoted: {model, effort}, when the owner's next set them}}) and on the reviewer and judge seats ({"reviewer" or "judge": {decision: promote, at, choice: {model, effort}}}, `control pick`) and pickBack null or {at, reason}, the rule's own return to shadow (pickback()); model, reviewer and judge (the review's judge, judgeseat()) are null or {cli: the
# CLI that runs the seat (claude, codex or opencode), model, effort (null: the seed's)}, cli left out of one that names
# a model of the pack's models.allowed, whose program it is (seatnow()); fix (the session that repairs review
# findings) and testFix (the one that repairs failed changed tests) are null, the card's builder, or a builder seat of
# their own, as model is (seat()); tests (the Tests seat, the test actions'
# sessions: testaction(), lib/testaction.sh) is null or {cli, model, effort}, always with its CLI; cards holds the
# per-card seats by issue number ({"<issue>": {builder, reviewer, judge}}, each left out or {model, effort (null: the
# project's)}, `control card`), which that issue's card runs on in place of the project's (seat(), SEATCARD);
# judgeOn is whether the judge reads the reviews (judged()) and judgeAlways the finding kinds it always accepts; account and
# reviewAccount are null or the name of one of the host file's accounts (ACCT, above); start is where
# new issues start, queue or held, startHeld the spans it was held ({from, to}: the newest issue number at each switch;
# to is null for the one in force, the last), startSeen the issues this setting has had its say on: held by adopt(), or released.
# depGuard is the dependency guard (true, the seed's, for a record written before it: no issue is picked while an
# issue it depends on is open) and forced the issues `control force` lets past their open dependencies while it is
# off (adopted() drops each once it lands or its issue closes). landAs is null (the pack's push.landAs) or the rule
# "Land as", main or pr (landas(), lib/push.sh). prMerge is null (the pack's push.prMerge) or the rule "Merge PR",
# button, release or idle (prmergerule(), lib/push.sh). pushCheck is null (the pack's push.check holds) or whether the run before a push runs
# (`control push-check`, over the pack's: pushcheck(), lib/pushrun.sh). signin is null, or why the loop paused itself: a session
# whose sign-in failed, with no fallback route left (signinpause()); resume clears it. A key this copy of the engine does not know, at the top
# or in rules (one a newer copy added, while a card runs on the older copy in its worktree), is passed through
# unchecked, so a control action keeps it when it writes the record. Anything else is not a record: the reason on
# stderr and exit 1.
# The file is read at every use; what this check made of it is kept, keyed on its exact text (CTL_K), so the same
# text, a copy's too (the snapshot's), is not checked again and any other is; a record that fails is never kept. A
# read in a subshell keeps nothing: ctlread sets CTL_V in the shell that calls it, and a subshell started after it
# finds what it kept. A file with a NUL byte is checked as before and not kept (a bash variable cannot hold it).
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
# picked while an issue it depends on is open; nothing is forced past it. The pack's push.check says whether the run
# before a push runs (pushCheck null). A card that lands is not pushed (rules.push
# off: land only, owed()): it waits for the Board's Push landed, or for the owner to turn the rule on. A visible change needs no yes from the owner (rules.visible off; on: a card waits for a
# `Visible change approved:` line, yesrule()). The rule Lint check is on (rules.lint: the pack's lint commands run at
# the review gate, lintgate(), lib/lint.sh). rules.testissues, foremanissues, followupissues, releaseissues and splitissues are on (each of those kinds of card files a GitHub issue; off, the Rules tab's
# Cards with no GitHub issue: that kind On, its card starts with none). The rule Split large issues is on (rules.split: the judge's
# verdict on a large issue that is too big is acted on: its slices are filed, splitcheck()). The rule Pick settings is off
# (rules.pick: no card's group and builder choice is recorded, modelpick()). No Tests seat is set: no test action starts (testaction()). The project
# is not onboarded (onboarded null; `control onboarded` sets {at, rules}: when the owner finished the Board's setup and
# the rules confirmed there), so the Board opens its setup. A release suite runs its files one by one or in parallel as suiteMode says (serial; `control suite-mode`, the mode a release-prep or release-run given no flag takes), and in parallel runs at most suiteAtOnce
# test files at once, 2 (`control atonce <n>`, or Test files at once on the Rules tab; a whole number from 1; at most the test slots of the machine it runs on: relsuite(), commands/release-prep.sh). That
# suite runs on this machine (suiteMachine {kind: "local"}; `control suite-machine`, lib/suitehost.sh; a devbox's record also keeps
# setupAt, when the box's .conveyor/test-machine.sh last ran there, as each run reads it from the box: hostsetup()). Empty when
# the file cannot be read, or there is no jq (doctor says so): then no record is read.
# testsFrom (null: every run counts) is the test history's start, a UTC time (`control tests-from`, `test-settings history-start`).
CTL0=$(jq -c . "$HERE/lib/control-defaults.json" 2>/dev/null) || CTL0=
ctl() { local CTL_V; ctlread || return 1; printf '%s\n' "$CTL_V"; }
ctlread() { # sets CTL_V to the control record, as ctl prints it
  local t a=''
  [ -n "$CTL0" ] || { echo "conveyor: the control record's defaults, $HERE/lib/control-defaults.json, cannot be read" >&2; return 1; }
  [ -s "$CONTROL" ] || { CTL_V=$CTL0; return; }
  { IFS= read -r -d '' t; a=$?; } 2>/dev/null <"$CONTROL"
  [ "$a" = 1 ] && [ "${#CTL_K[@]}" = 2 ] && [ "${CTL_K[0]}" = "$t" ] && { CTL_V=${CTL_K[1]}; return 0; }
  if [ "$a" = 1 ]; then CTL_V=$(ctlcheck <<<"$t") && CTL_K=("$t" "$CTL_V"); else CTL_V=$(ctlcheck "$CONTROL"); fi \
    || { echo "conveyor: $(notwhole)" >&2; return 1; }
}
ctlcheck() { # [<file>]: the record on the input, or in the file, whole, or exit non-zero
  jq -ce --argjson d "$CTL0" '($d * .) | .rules = ($d.rules * .rules) | select((.mode | IN("run", "pause", "stop")) and (.cap == null or (.cap | type == "number" and . >= 1 and . <= 100 and . == floor))
      and (.guard == null or (.guard | type == "number" and . >= 1 and . <= 100))
      and ([.held, .order] | all(type == "array" and all(type == "number")))
      and (.pushCheck == null or (.pushCheck | type == "boolean"))
      and (.start | IN("queue", "held")) and (.startSeen | type == "array" and all(type == "number"))
      and (.startHeld | type == "array" and all(type == "object" and keys == ["from", "to"] and (.from | type == "number") and (.to == null or (.to | type == "number"))))
      and ((.start == "held") == (.startHeld | length > 0 and (last.to == null)))
      and (.rules | (.never | type == "array" and all(type == "string")) and ([.P0, .P1, .P2, .P3, .followups, .push, .visible, .lint, .testissues, .foremanissues, .followupissues, .releaseissues, .splitissues] | all(type == "boolean"))
        and ([.split, .pick] | all(IN("off", "shadow", "on"))))
      and ([.model, .reviewer, .judge, .tests, .fix, .testFix] | all(. == null or (type == "object" and (keys - ["effort", "cli"]) == ["model"] and (.model | type == "string")
        and (.effort == null or (.effort | type == "string")) and (.cli == null or (.cli | IN("claude", "codex", "opencode"))))))
      and (.tests == null or .tests.cli != null)
      and (.cards | type == "object" and all(to_entries[]; (.key | test("^[1-9][0-9]{0,8}$")) and (.value | type == "object" and length > 0
        and (keys - ["builder", "reviewer", "judge"]) == [] and all(.[]; type == "object" and (keys - ["effort"]) == ["model"] and (.model | type == "string")
          and (.effort == null or (.effort | type == "string"))))))
      and (.judgeOn | type == "boolean") and (.judgeAlways | type == "array" and all(type == "string"))
      and (.depGuard | type == "boolean") and (.forced | type == "array" and all(type == "number"))
      and (.signin == null or (.signin | type == "string")) and (.landAs == null or (.landAs | IN("main", "pr")))
      and (.prMerge == null or (.prMerge | IN("button", "release", "idle")))
      and (.onboarded == null or (.onboarded | type == "object" and keys == ["at", "rules"] and (.at | type == "string") and (.rules | type == "array" and all(type == "string"))))
      and (.picks | type == "object" and all(to_entries[]; def choice: type == "object" and keys == ["effort", "model"] and all(.[]; type == "string");
        if .key | IN("reviewer", "judge") then .value | type == "object" and keys == ["at", "choice", "decision"] and (.at | type == "string") and .decision == "promote" and (.choice | choice)
        else (.key | test("^(small|medium) (docs|code)$")) and (.value | type == "object" and (keys - ["challenger", "promoted"]) == ["at", "decision"]
          and (.at | type == "string") and (.decision | IN("promote", "keep", "drop", "add", "next")) and all(.challenger, .promoted | select(. != null); choice)) end))
      and (.pickBack == null or (.pickBack | type == "object" and keys == ["at", "reason"] and all(.[]; type == "string")))
      and (.suiteAtOnce | type == "number" and . >= 1 and . == floor) and (.suiteMode | IN("serial", "parallel"))
      and (.testsFrom == null or (.testsFrom | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") and (try fromdate catch null) != null))
      and (.suiteMachine | type == "object" and if .kind == "local" then keys == ["kind"]
        elif .kind == "devbox" then (keys - ["setupAt", "box"]) == ["idleStop", "kind", "size", "tag"] and (.box == null or (.box | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) and (.setupAt == null or (.setupAt | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))) and (.size | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))
          and (.tag | type == "string" and test("^conveyor-suite-[A-Za-z0-9._-]+$")) and (.idleStop | type == "string" and test("^[1-9][0-9]*[smh]$"))
        else .kind == "ssh" and keys == ["dir", "kind", "target"]
        and (.target | type == "string" and test("^[A-Za-z0-9._][A-Za-z0-9._@-]*$")) and (.dir | type == "string" and test("^(~$|~/|/)") and (contains("\n") | not)) end)
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
# The control record $c with the seats it keeps for issue $n (cards; models.allowed is the input) in place of the
# project's: each named by its model alone, so it runs on the CLI the pack lists it under, at its own effort, else the
# project's seat's. One whose model the pack no longer allows the seat is passed over: the project's stands.
# cardfit: a per-card seat that took the project's effort, and whose CLI does not take that effort ($e, EFFORTS),
# runs at medium.
PERCARD='def cardset($c; $n): ($c // {} | .cards // {} | .[$n] // {});
  def percard($c; $n): cardset($c; $n) as $p | okmodels("builder") as $ob | okmodels("reviewer") as $or
    | reduce (["builder", "model", $ob], ["reviewer", "reviewer", $or], ["judge", "judge", $or]) as [$k, $f, $ok] ($c;
        if $p[$k].model != null and ([$ok[][]] | index($p[$k].model)) != null
        then .[$f] = {model: $p[$k].model, effort: ($p[$k].effort // (.[$f] // {}).effort)} else . end);
  def cardfit($c; $n; $e; $k): cardset($c; $n)[$k] as $o
    | if . == null or $o.model == null or $o.effort != null or .effort == null then .
      else .effort as $f | if ($e[.agent // ""] // [] | index($f)) == null then .effort = "medium" else . end end;'
# The seats in force, the builder's, the reviewer's and the judge's (judgeseat), worked out together in one jq run and
# kept, keyed on the exact text of the control record and of models.allowed (SEAT_K), so a step that asks for a seat
# again starts no program for it, nor does a subshell or card started after; any other text is worked out again.
# Read without a record given, the control record is read in the calling shell (ctlread), so it is kept there too.
# Within a card (SEATCARD: its issue, set by card()), the seats the record keeps for that issue (cards, `control card`)
# stand in for the project's (percard), each read when its step starts, so a step already running keeps its seat.
# A card with no judge of its own has the project's: the default judge follows the project's reviewer ($rj), not the
# card's, as the Board shows it. The fix and testFix seats (the sessions that repair review findings and failed
# changed tests) are the card's builder, unless the record sets one of its own (fix, testFix), named by a model the
# pack lists for the builder or with its CLI, as model is: then that one, for every card. fixseat($c; $k; $b) is that
# seat in jq ($k: fix or testFix, $b the builder's seat; needs SEATNOW), so the benchmark's logins name the same CLI.
FIXSEAT='def fixseat($c; $k; $b): ($c // {})[$k] as $o
  | if $o != null and ($o.cli != null or ([okmodels("builder")[][]] | index($o.model))) then [try seatnow("builder"; {model: $o})] | first else $b end;'
declare -gA SEAT_V=(); SEAT_K=''
seat() { # <builder|reviewer|judge|fix|testFix> [the control record, when the caller has read it]
  local a c=${2:-} x CTL_V n=${SEATCARD:-}; [ -n "$c" ] || { if ctlread 2>/dev/null; then c=$CTL_V; else c=null; fi; }
  # A trial card (PICKSEAT, card()'s: picktrial(), lib/modelpick.sh) builds on the rule's challenger, and a card of the
  # rule On on the judge's builder (pickjudge()), as if the record set it for the issue's builder, until the owner sets
  # one for the issue (that always wins); its other seats are the record's.
  [ -z "${PICKSEAT:-}" ] || [ -z "$n" ] || c=$(jq -c --arg n "$n" --argjson p "$PICKSEAT" '.cards[$n].builder //= $p' <<<"$c") || return 1
  # So does a card's reviewer or judge that the owner promoted from a replay result, or the judge picked (PICKSEATS:
  # pickseats(), pickjudge()).
  [ -z "${PICKSEATS:-}" ] || [ -z "$n" ] || c=$(jq -c --arg n "$n" --argjson p "$PICKSEATS" 'reduce ($p | to_entries[]) as $e (.; .cards[$n][$e.key] //= $e.value)' <<<"$c") || return 1
  # A record with no key "<issue>" keeps no seats for the card: the project's, worked out (and kept) once for all cards.
  [[ $c == *"\"$n\":"* ]] || n=''
  modelsallowed a || return 1
  if [ "$SEAT_K" != "$n"$'\037'"$c"$'\037'"$a" ]; then
    # Each seat on its own (try): one that fails to work out is none, as it was read alone.
    mapfile -d '' -t x < <(jq -j --argjson c0 "$c" --arg n "$n" --argjson e "$EFFORTS" "$SEATNOW$JUDGENOW$PERCARD$FIXSEAT"'percard($c0; $n) as $c
        | ([try seatnow("builder"; $c)] | first | cardfit($c0; $n; $e; "builder")) as $b | ([try seatnow("reviewer"; $c)] | first | cardfit($c0; $n; $e; "reviewer")) as $r
        | ([try seatnow("reviewer"; $c0)] | first) as $rj
        | ($b, $r, (if $rj == null then null else [try judgenow($c; $rj)] | first | cardfit($c0; $n; $e; "judge") end), fixseat($c0; "fix"; $b), fixseat($c0; "testFix"; $b))
        | (if . == null then "" else tojson end) + "\u0000"' <<<"$a" 2>/dev/null) \
      && [ "${#x[@]}" = 5 ] || return 1
    SEAT_V=([builder]=${x[0]} [reviewer]=${x[1]} [judge]=${x[2]} [fix]=${x[3]} [testFix]=${x[4]}); SEAT_K=$n$'\037'$c$'\037'$a
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
# The models.allowed in force, in the variable named: the pack's, as packget gives it, when it sets one (the owner's
# list), with the Codex models the host's report has (hostclis(), climodels()) added to its codex list, when it has
# one with a model in it, after the pack's own, each once: the pack's list adds models to the CLI's and does not
# replace it (a pack with no codex list, or an empty one, keeps none, so its reviewer stays on the CLI it names).
# With no pack list, the
# models this host's CLIs report: Codex's as the host's report has them, none
# when Codex is not installed, and for Claude, which reports none, the built-in MODELS0's, as are Codex's while an
# installed Codex has reported none (or the report cannot be read). Worked out in
# one jq run and kept, keyed on the pack's list and the report's text (MODELS_K), so a step that asks again starts no
# program for it. Fails when the pack does not read.
MODELS_K=()
modelsallowed() { # <variable>
  local m_ p_
  packget models.allowed p_ 2>/dev/null || return 1
  hostclis >/dev/null 2>&1 || HOST_R=''
  if [ "${#MODELS_K[@]}" = 2 ] && [ "${MODELS_K[0]}" = "$p_"$'\037'"$HOST_R" ]; then m_=${MODELS_K[1]}
  elif [ -n "$p_" ]; then
    m_=$(jq -c --argjson h "${HOST_R:-null}" '$h.codex? as $x
      | if type == "object" and ($x | type) == "array" and (.codex | type) == "array" and (.codex | length) > 0
        then .codex = reduce (.codex + $x)[] as $m ([]; if index([$m]) then . else . + [$m] end) else . end' <<<"$p_") || return 1
    MODELS_K=("$p_"$'\037'"$HOST_R" "$m_")
  else
    m_=$(jq -cn --argjson d "$MODELS0" --argjson h "${HOST_R:-null}" '$h.codex as $x
      | $d | if ($x | type) == "array" and ($x | length) > 0 then .codex = $x
        elif ($h | type) == "object" and ($h | has("codex") | not) then .codex = [] else . end') || return 1
    MODELS_K=("$p_"$'\037'"$HOST_R" "$m_")
  fi
  printf -v "$1" '%s' "$m_"
}
# A model the belt runs or offers that has no price (docs/configuration.md, Models): the Board cannot show its cost.
# The Board lists it under Rules, Model prices, and Needs you counts it: $NOPRICE keeps {missing: [model ID]}, which
# the snapshot gives as needsYou.prices. Conveyor files no issue for it in the project's repository: a missing price
# is a gap in Conveyor's own price table or a setting of the Board, no work of the project. A Claude or Codex model
# the belt runs (an ID that starts claude- or gpt-, the built-in table's reach; a seat's, a session's, the Tests
# seat's or the research lane's, not one only offered) that the built-in table does not price, whatever the pack's
# prices, is also noted as a plugin problem, in the Foreman's plugin-bugs.md (foremandir(); foreman/stop.sh's form),
# which the Overview's Plugin problems pane files to the plugin's repository on the owner's yes: once for each model
# whatever the loop's turns or restarts ($NOPRICE's noted), the projects of its group (a note in that file counts) and
# a note filed or dismissed since (that folder's noprice-noted).
# Each such note's line, or the line another project of the group noted, is kept too ($NOPRICE's notes): the snapshot
# gives them (priceNotes), so a Board on another machine than the belt adds them to the Foreman's folder it reads.
# The
# models: those of the models.allowed in force (modelsallowed(), the list the Board's "Offered with no price" takes:
# the pack's when it sets one, with the host's Codex models added to a codex list it has with a model in it), and those
# run: the builder's, the reviewer's and the judge's seats, the Tests seat, the research lane's model, and each model
# ID the card sessions of the last 30 days ran (a failed one's too). The research lane's session history does not
# count: it holds models the belt never runs. Which have no price is dashboard_limit.py's (unpriced: the built-in table
# with the pack's prices over it; an OpenCode model keeps the cost OpenCode reports, so it is never one). `serve` looks
# once a minute (run()), and asks that only when the models or the pack's prices changed since the last look that did
# all it had to (NOPRICE_K). One look at a time (a lock of its own). CONVEYOR_NOPRICE_CMD, when set, runs in place of
# dashboard_limit.py unpriced, as bash -c; one that fails changes nothing.
# First, each issue an older Conveyor filed for a missing price ($NOPRICE's filed: [{model, issue, at}]) is closed, with
# a comment that the price shows on the Board now, and taken off filed, so a later look closes nothing; one GitHub did
# not close stays on filed, tried again at the next look. No other issue is closed.
# The Foreman's folder for this project, printed, as foreman/lib.sh names it (mine, FD): for a project in a list of
# the host file's foreman.groups, the folder of that list's first project that a record names (a name no record has is
# passed over, as lib.sh and the Board pass it over), whose Foreman watches the whole group and whose plugin-bugs.md
# the Board reads; else, when the groups name a project twice (not understood: each project has its own), or when
# that project's checkout is not on this machine, this project's own.
foremandir() {
  local m
  m=$(jq -r --arg r "$REPO" '(.records | arrays | map(objects)) as $rs | (.foreman.groups | arrays) as $gs
    | select($gs | all(type == "array" and all(type == "string")) and ([.[][]] | length == (unique | length)))
    | first($gs[] | select(index([$r]))) | first(.[] as $n | $rs[] | select(.repo == $n) | .main | strings) // empty' "$HOST" 2>/dev/null)
  if [ -n "$m" ] && [ -d "$m" ] && ! [ "$m" -ef "$MAIN" ]; then
    m=$(env -u CONVEYOR_CARDS CONVEYOR_MAIN="$m" bash "$HERE/conveyor.sh" state-dir 2>/dev/null) && [ -n "$m" ] && printf '%s/foreman\n' "$m"
  else
    printf '%s/foreman\n' "${STATE%/*}"
  fi
}
NOPRICE=${STATE%/*}/noprice.json
NOPRICE_CMD=${CONVEYOR_NOPRICE_CMD:-python3 $(printf %q "$HERE/../.claude/scripts/dashboard_limit.py") unpriced}
NOPRICE_K=''
noprice() {
  local lock rc
  { exec {lock}>>"$NOPRICE.lock"; } 2>/dev/null || return 1
  flock -n "$lock" || { exec {lock}>&-; return 0; }
  noprice_; rc=$?
  exec {lock}>&-
  return $rc
}
# noprice()'s look, under its lock.
noprice_() {
  local a c p r ms rs k miss gaps m n u l out x y cli ran since st notes rc=0 noted=() lines=()
  while IFS=$'\t' read -r n m; do
    out=$(gh_write issue close "$n" --comment "Conveyor no longer files an issue for a model with no price: the price now shows on the Board. While the belt runs or offers \`$m\` with no price, the Board lists it under Rules, Model prices, and Needs you counts it until its price is added there." 2>&1 </dev/null) \
      || { echo "conveyor: #$n, the issue for the price of $m, could not be closed: ${out:0:300}" >&2; rc=1; continue; }
    jq -c --argjson n "$n" '.filed |= map(select(type != "object" or .issue != $n))' "$NOPRICE" > "$NOPRICE.new" 2>/dev/null && mv -f "$NOPRICE.new" "$NOPRICE" \
      || { rm -f "$NOPRICE.new"; echo "conveyor: #$n, the issue for the price of $m, was closed, but $NOPRICE could not be written" >&2; rc=1; continue; }
    echo "conveyor: closed #$n, Model price missing: $m (the Board shows it now)"
  done < <(jq -r '.filed | arrays | .[] | objects | select(.issue | type == "number" and . >= 1 and . == floor) | [.issue, (.model | tostring)] | @tsv' "$NOPRICE" 2>/dev/null)
  modelsallowed a || return 1
  if ctlread 2>/dev/null; then c=$CTL_V; else c=null; fi
  packget prices p lanes.research r 2>/dev/null || return 1
  # The model IDs the card sessions of the last 30 days ran, as the Board counts them under Seen (dashboard_limit.py
  # card_costs, the steps rows.jq takes): a build's, fix's or rebase's are the models its result names (stats.byModel,
  # else stats.models when it names one; <synthetic>, the name of a message no model answered, is none), else the model it was run on; a review's is its own model; a test runs none.
  # A failed session or review is the blocked line's spent, at that line's time. A seat asked for one model can run
  # another. Only the lines that name a model are parsed, and a line that does not read is skipped. No such line (grep
  # fails, a missing file too) is no model.
  since=$(jq -rn '(($ENV.CONVEYOR_NOW // "" | tonumber?) // now) - 30 * 86400 | todate') || return 1
  ran=$({ grep -hF '"model' "$STATE" "$RETRIED" 2>/dev/null || :; } | jq -nRc --arg s "$since" '[inputs | try fromjson catch null | objects
      | if .step == "blocked" then (.spent | objects) + {time} else . end
      | select((.step | IN("build", "review", "fix", "rebase")) and (.time | strings) >= $s)
      | ((if .step != "review" then .stats | objects | ((.byModel | objects | keys | map(select(. != "<synthetic>")) | select(length > 0)) // (.models | arrays | map(select(. != "<synthetic>")) | select(length == 1))) else empty end) // [.model])
      | .[] | strings | select(. != "")] | unique') || return 1
  # Each model with its CLI. A seat the record and pack leave unset (no judge, say) adds none, and fails no look.
  x=$({ for m in builder reviewer judge; do seat "$m" "$c" 2>/dev/null || :; done; } | jq -rs --argjson a "$a" --argjson c "$c" \
      --argjson r "${r:-null}" --argjson ran "$ran" '[(.[] | [.agent, .model, "r"]), ($ran[] | ["", ., "r"]), ($a | objects | to_entries[] | (if .key == "codex" or .key == "codex-builder" then "codex" else "" end) as $k
        | .value[]? | [$k, ., ""]), ($c.tests | objects | if .cli == "opencode" then ["", "opencode:" + .model, "r"] else [.cli, .model, "r"] end),
        ($r | objects | ["claude", .model, "r"])] | map(select(.[1] | strings)) | unique[] | map(. // "") | join("\u001f")') || return 1
  # A one-word name (sol, opus) is a family or an alias, no model ID: Codex runs a family's newest model (codexmodel()),
  # which is the one to price; one that resolves to none runs nothing (codexready() says so), and Claude's CLI
  # resolves its aliases itself, so neither is looked at.
  # Fields split on \037, no whitespace: IFS whitespace would drop an empty CLI field and read the model as the CLI.
  # The third field is r for a model the belt runs (a seat's, a session's, the Tests seat's, the research lane's), empty
  # for one only offered: ms holds them all, rs those run.
  y=$(while IFS=$'\037' read -r cli m u; do
      if [[ $m =~ ^[a-z]{2,}$ ]]; then [ "$cli" != codex ] || ! m=$(codexmodel "$m" 2>/dev/null) || printf '%s\037%s\n' "$u" "$m"; else printf '%s\037%s\n' "$u" "$m"; fi
    done <<<"$x" | jq -Rsc '[splits("\n") | select(length > 0) | split("\u001f")] | [(map(.[1]) | unique), (map(select(.[0] == "r") | .[1]) | unique)]') \
    && ms=$(jq -c '.[0]' <<<"$y") && rs=$(jq -c '.[1]' <<<"$y") || return 1
  k=$y$'\037'$p
  [ "$k" != "$NOPRICE_K" ] || return $rc
  # miss: the models with no price, the pack's prices put over the built-in table (what the Board lists). gaps: the
  # models run that the built-in table alone does not price: a pack's price for one leaves the table's gap.
  miss=$(jq -cn --argjson m "$ms" --argjson p "${p:-null}" '{prices: $p, models: $m}' \
      | timeout 30 bash -c "$NOPRICE_CMD" 2>/dev/null 7>&- 8>&-) && miss=$(jq -ce 'arrays | map(strings | select(. != ""))' <<<"$miss" 2>/dev/null) || return 1
  gaps=$(jq -cn --argjson m "$rs" '{prices: null, models: $m}' \
      | timeout 30 bash -c "$NOPRICE_CMD" 2>/dev/null 7>&- 8>&-) && gaps=$(jq -ce 'arrays | map(strings | select(. != ""))' <<<"$gaps" 2>/dev/null) || return 1
  st=$(jq -ce 'objects' "$NOPRICE" 2>/dev/null) || st='{}'
  # A Claude or Codex model run with no built-in price and no note yet: one plugin problem each, in stop.sh's form,
  # under the header stop.sh writes, in the Foreman's folder (foremandir()). Only an ID of the built-in table's form is
  # noted: a note is one line. The projects of a group share that file, so a model another one noted there already
  # gets no second note (it is put on noted all the same). Filing or dismissing a note on the Board takes it out of
  # that file, so each model noted is also kept in noprice-noted in the same folder, one ID a line: a model on it gets
  # no second note either, though the group's other projects have it on no noted of their own. The look and the note
  # are made under a lock of the folder, so two loops of a group never both note one model.
  notes=$(foremandir)/plugin-bugs.md || return 1
  y=$(jq -r --argjson st "$st" '.[] | select(test("^(claude|gpt)-[A-Za-z0-9._\\[\\]-]+$")) | select(. as $m | $st.noted | arrays // [] | index([$m]) | not)' <<<"$gaps") || return 1
  if [ -n "$y" ]; then
    out=$(mkdir -p "${notes%/*}" 2>/dev/null && { flock -w 30 9 || exit 1
      while IFS= read -r m; do
        l=$(grep -m 1 -F -- " · No built-in price for $m: " "$notes" 2>/dev/null) \
          || grep -qxF -- "$m" "${notes%/*}/noprice-noted" 2>/dev/null \
          || { l=$(printf -- '- %s · card - · No built-in price for %s: the belt runs or offers this %s model, and the built-in price table (dashboard_limit.py) has no price for it, so the Board cannot show what it costs · evidence: -' \
              "$(clock)" "$m" "$([[ $m == claude-* ]] && echo Claude || echo Codex)") \
            && { [ -s "$notes" ] || printf '# Plugin problems the Foreman noted (for the conveyor-belt repo)\n\n'; printf '%s\n' "$l"; } >> "$notes"; } 2>/dev/null || continue
        grep -qxF -- "$m" "${notes%/*}/noprice-noted" 2>/dev/null || { printf '%s\n' "$m" >> "${notes%/*}/noprice-noted"; } 2>/dev/null || continue
        printf '%s\t%s\n' "$m" "$l"
      done <<<"$y"; } 9>>"${notes%/*}/noprice.lock")
    # One line a model noted: the model, a tab, then its note (none for a model on noprice-noted whose note was filed
    # or dismissed: a second line, empty, would be cut off with the output's last newline).
    while IFS=$'\t' read -r m l; do [ -z "$m" ] || { noted+=("$m"); lines+=("$l"); }; done <<<"$out"
    [ "${#noted[@]}" = "$(wc -l <<<"$y")" ] || { echo "conveyor: a plugin problem for a model with no price could not be noted in $notes" >&2; rc=1; }
  fi
  l=$(printf '%s\n' "${lines[@]}" | jq -Rsc '[splits("\n") | select(. != "")]') || return 1
  jq -c --argjson m "$miss" --argjson l "$l" '.missing = $m | .noted = ((.noted | arrays // []) + $ARGS.positional | unique) | .notes = ((.notes | arrays // []) + $l)' \
      --args "${noted[@]}" <<<"$st" > "$NOPRICE.new" 2>/dev/null \
    && mv -f "$NOPRICE.new" "$NOPRICE" || { rm -f "$NOPRICE.new"; echo "conveyor: the models with no price could not be written to $NOPRICE" >&2; return 1; }
  [ "$rc" != 0 ] || NOPRICE_K=$k
  return $rc
}
# The research lane's folder, printed (nothing when there is none): the host file's lanes.research.worktree of this
# checkout's record (the record whose main is this checkout, compared as lanenote does; ~/ is the home folder).
researchwt() {
  local m w
  [ -e "$HOST" ] || return 0
  while IFS= read -r -d '' m && IFS= read -r -d '' w; do
    [ "$m" = "$MAIN" ] || { [[ $m == /* ]] && [ "$m" -ef "$MAIN" ]; } || continue
    [[ $w != \~/* ]] || w=$HOME/${w#"~/"}
    printf '%s\n' "$w"; return 0
  done < <(jq -j '.records | arrays | .[] | objects | select([.main, (try .lanes.research.worktree catch null)] | all(type == "string" and . != "" and (test("\u0000") | not)))
    | "\(.main)\u0000\(.lanes.research.worktree)\u0000"' "$HOST" 2>/dev/null)
}
# progs: the programs the models.allowed in force lists a model for, one per line (doctor's).
progs() {
  local a
  modelsallowed a && jq -r '(if (.claude // []) + (.["claude-reviewer"] // []) | any(strings) then "claude" else empty end),
      (if (.codex // []) + (.["codex-builder"] // []) | any(strings) then "codex" else empty end), (if .opencode // [] | any(strings) then "opencode" else empty end)' <<<"$a"
}
# The models a CLI has registered on this host, as a JSON array, read from the CLI itself; fails when it offers no
# list or its list cannot be read. Codex: the models its account can use, the slugs it shows a user (visibility list),
# from its models cache (models_cache.json in CODEX_HOME, which Codex fetches again as it runs), else from `codex debug
# models`, its model catalog. OpenCode: `opencode models`, one <provider>/<model> a line. Claude Code has no command
# that lists its models (its --model takes an alias or a full name): none. For Codex, the models its proxy route
# offers (codexpxmodels()) are added after its own, each once, so a model the proxy serves is listed before Codex
# reports it.
climodels() { # <cli>
  local list='[.models[]? | select((.visibility // "list") == "list") | .slug | strings] | select(length > 0)' own px
  case $1 in
    codex) own=$(jq -ce "$list" "${CODEX_HOME:-$HOME/.codex}/models_cache.json" 2>/dev/null \
      || timeout 20 codex debug models < /dev/null 2>/dev/null | jq -ce "$list" 2>/dev/null) || own=''
      px=$(codexpxmodels) || px=''
      [ -n "$own$px" ] || return 1
      jq -cn --argjson a "${own:-[]}" --argjson b "${px:-[]}" 'reduce ($a + $b)[] as $m ([]; if index([$m]) then . else . + [$m] end)' ;;
    opencode) timeout 20 opencode models < /dev/null 2>/dev/null | jq -Rsce '[splits("\n") | select(test("^[^/[:space:]]+/[^[:space:]]+$"))] | select(length > 0)' 2>/dev/null ;;
    *) return 1 ;;
  esac
}
# The models Codex's proxy route (codexProxy, kind proxy) offers, as a JSON array: the ids of its models list, GET
# <baseUrl>/models (its baseUrl ends in /v1, so /v1/models), when every role's Codex sessions always take the route
# (proxyrole codex is proxy for the builder and the reviewer): the host's report has one Codex list for every role, so
# a model only the proxy serves is not offered to a role whose sessions run on the subscription (a role on
# subscription or fallback). The OpenAI API (kind api) is not asked: its list has every model of
# the API, most of which Codex does not run. Asked as a session asks: sent its key (routekey()) as a Bearer token, or
# with none the stand-in key (NOKEY). The key goes in the call's environment, never on a command line, and is not sent
# on to a redirect. An id that is no model name (one with a space, say) is left out. Fails, so Codex's own list is used
# alone, when no such route is set, or the list does not come within 10 s or has no model.
codexpxmodels() {
  local p b PROXY_ROLE KEY_V KEY_FROM
  p=$(codexproxyset) || return 1
  [ "$(jq -r .kind <<<"$p")" != api ] || return 1
  for PROXY_ROLE in builder reviewer; do [ "$(proxyrole codex)" = proxy ] || return 1; done
  b=$(jq -r '.baseUrl | strings' <<<"$p"); [ -n "$b" ] || return 1
  routekey "$p"
  CONVEYOR_APIKEY=${KEY_V:-$NOKEY} timeout 10 python3 -I -c 'import json, os, re, sys, urllib.request
key = os.environ.pop("CONVEYOR_APIKEY")
class Stay(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a): return None
with urllib.request.build_opener(Stay).open(urllib.request.Request(sys.argv[1], headers={"Authorization": "Bearer " + key}), timeout=8) as r: d = json.load(r)
ids = [x.get("id") for x in (d.get("data") if isinstance(d, dict) else None) or [] if isinstance(x, dict)]
print(json.dumps([m for m in ids if isinstance(m, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/@-]{0,199}", m)]))' "${b%/}/models" 2>/dev/null \
    | jq -ce 'select(length > 0)' 2>/dev/null
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
  # seen: every CLI a report of this host has listed, kept when one goes (seatwait()). One CLI read that is not
  # installed is taken out of clis, not written there as installed with no list.
  if [ "$one" = fresh ]; then jq -cn --argjson r "$r" --argjson o "$old" '{at: (now | floor), clis: $r, seen: ([($o.seen | arrays | .[] | strings), ($o.clis | objects | keys[]), ($r | keys[])] | unique)}' > "$CLIS.$$"
  elif [ -n "$one" ]; then jq -c --arg c "$one" --argjson r "$r" 'if $r | has($c) then .clis[$c] = $r[$c] else del(.clis[$c]) end | .seen = ([(.seen | arrays | .[] | strings), ($r | keys[])] | unique)' <<<"$old" > "$CLIS.$$"; fi
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
# A step's check of its seat before its session starts (session1(), review(), judgecall()). A CLI that an update or a
# reinstall takes away for a moment must not block the card for good (issue 839): when seatready fails on a CLI that a
# report of this host has listed (its seen, or the clis of a report written before seen was), the host's CLIs are read
# again (a fresh report) SEAT_TRIES times, SEAT_PAUSE seconds apart, the card keeping its build slot. When the CLI is
# still missing, a card of the loop (LOOPCARD, cardrun()) waits in its step: its live record names the CLI (its cli
# and action) and <worktree>.idle stands, so it holds no build slot, until the loop takes that mark away in a turn with
# a free slot once the host's report lists the CLI again (cliwake(), lib/run.sh); the step then starts, or waits again
# when the CLI is gone again. Outside the loop (a lane's preview review), and for a CLI that no report of this host
# has listed, it fails with seatready's reason.
SEAT_TRIES=4 SEAT_PAUSE=30
seatwait() { # <role> <its seat> <worktree> <step>
  local why a i=0 at
  why=$(seatready "$1" "$2") && return 0
  a=$(jq -r '.agent | strings' <<<"$2" 2>/dev/null)
  [ -n "$a" ] && jq -e --arg a "$a" '[(.seen | arrays | .[]), (.clis | objects | keys[])] | index($a)' "$CLIS" >/dev/null 2>&1 || { printf '%s\n' "$why"; return 1; }
  at=$(date -u +%FT%TZ)
  while [ "$i" -lt "$SEAT_TRIES" ]; do
    seatlive "$1" "$3" "$4" "$a" "$at"; i=$((i + 1)); sleep "$SEAT_PAUSE"; hostclis fresh >/dev/null
    why=$(seatready "$1" "$2") && { rm -f "$3.live"; return 0; }
  done
  [ -n "${LOOPCARD:-}" ] || { rm -f "$3.live"; printf '%s\n' "$why"; return 1; }
  until [ ! -e "$3.idle" ] && why=$(seatready "$1" "$2"); do
    seatlive "$1" "$3" "$4" "$a" "$at"; : > "$3.idle"
    while [ -e "$3.idle" ]; do sleep "$LIVE"; seatlive "$1" "$3" "$4" "$a" "$at"; done
  done
  rm -f "$3.live"
}
# The live record of a step that waits for its seat's CLI (seatwait()): cli names the CLI for cliwake() (lib/run.sh).
seatlive() { # <role> <worktree> <step> <cli> <since>
  jq -cn --arg s "$3" --arg at "$5" --arg a "$4" --arg r "$1" '{step: $s, at: $at, last: (now | todate), turns: 0, cli: $a,
    action: "waiting for \($a): the \($r) is set to \($a), and \($a) is not on PATH on this host now; the \($s) starts once the host'"'"'s CLIs list \($a) again"}' \
    > "$2.live.tmp" 2>/dev/null && mv -f "$2.live.tmp" "$2.live"
}
# The preflight of plan section 6: the builder and the reviewer in force can start on this host (seatready), so the
# loop starts no card on a CLI that is gone. Prints why not and fails; prints
# nothing when both can.
clis() {
  local c r rc=0 CTL_V; if ctlread 2>/dev/null; then c=$CTL_V; else c=null; fi
  # In the calling shell, so what seat and seatready work out is kept there.
  for r in builder reviewer; do seat "$r" "$c" >/dev/null || continue; seatready "$r" "${SEAT_V[$r]}" || rc=1; done
  # A fix or testFix seat of its own (one that is not the builder's) is checked too.
  for r in fix testFix; do seat "$r" "$c" >/dev/null && [ "${SEAT_V[$r]}" != "${SEAT_V[builder]}" ] || continue; seatready "$r" "${SEAT_V[$r]}" || rc=1; done
  return $rc
}
# Models through an API proxy. Claude's: card sessions run with --setting-sources "", so a base URL in the user's
# settings.json never reaches them; the host file's claudeProxy, else the pack's models.claudeProxy, names it and the
# NAME of the variable that holds its key (never the key). Prints that object as JSON; nothing when neither names one.
# Its roles, {builder, reviewer}, set each role's route (proxyrole()): "subscription", never through it; "fallback",
# on the subscription login, and a build, fix, rebase or review runs again through the proxy when that login fails
# before any turn; "proxy" (or "api"), always through it. A role it does not name, or no roles at all, is "proxy".
# Its kind is the route's: "proxy" (the default), a proxy sent its key as a Bearer token; "api", the provider's own
# API sent its key as the API expects it (Anthropic's x-api-key); "subscription", the host file's word that the CLI runs
# on its own login only, which prints nothing, as no route is set.
claudeproxy() {
  local p; p=$(jq -ce '.claudeProxy | objects' "$HOST" 2>/dev/null) || packget models.claudeProxy p 2>/dev/null || :
  [ "$p" = null ] || [[ $p == *'"kind":"subscription"'* ]] || printf '%s' "$p"
}
# claudeproxy() runs in a subshell ($(claudeproxy), and $(proxyrole) and $(proxyroute) around it), which keeps no check
# of the pack (packok, lib/prompts.sh). Called in the shell that starts those subshells, it checks the pack's text there
# once, so each read after it takes that check and does not check the same text again. A pack that fails is left for
# the read to fail.
proxypack() { packok 2>/dev/null || :; }
# Codex's, as setup writes it in the host file: codexProxy, {kind, baseUrl, keyEnv, keyFile, roles} as claudeProxy's.
# A Codex session whose role's route takes it through the proxy, or the OpenAI API (kind api), is given it as its own
# provider settings (codexargs()).
codexproxyset() { local p; p=$(jq -ce '.codexProxy | objects | select(.kind != "subscription")' "$HOST" 2>/dev/null) && printf '%s' "$p"; }
# A route's key, read at session start from where the owner keeps it, in this order: the env of Claude Code's settings
# file (CLAUDE_SETTINGS) under the route's keyEnv; the key file its keyFile names (keyfile()); and, unless <service> is
# given, the environment Conveyor runs in (envof), which the machine's service starts bare. Sets KEY_V to the key and
# KEY_FROM to where it was found; with none, KEY_V is empty and KEY_FROM says why. The key is never printed.
CLAUDE_SETTINGS=${CONVEYOR_CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
routekey() { # <route JSON> [service]
  local k f why=''
  KEY_V='' KEY_FROM=''
  k=$(jq -r '.keyEnv | strings' <<<"$1"); f=$(jq -r '.keyFile | strings' <<<"$1")
  [[ $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || k=''
  if [ -n "$k" ] && KEY_V=$(jq -er --arg k "$k" '.env[$k] | strings | select(. != "")' "$CLAUDE_SETTINGS" 2>/dev/null); then KEY_FROM="$k in the env of $CLAUDE_SETTINGS"; return 0; fi
  KEY_V=''
  if [ -n "$f" ]; then keyfile "$f" && return 0; why=$KEY_FROM; fi
  if [ -n "$k" ] && [ -z "${2:-}" ] && KEY_V=$(envof "$k") && [ -n "$KEY_V" ]; then KEY_FROM="$k in the environment Conveyor runs in"; return 0; fi
  KEY_V=''
  KEY_FROM=${why:-no ${k:-key variable} in the env of $CLAUDE_SETTINGS$([ -n "$f" ] || echo ", and no key file named (keyFile)")}
}
# A key file's key, in KEY_V: its first line, when it is a file of this user's that no one else may read or write
# (mode 600 or tighter); else KEY_V is empty and KEY_FROM says why, and the key is not read. KEY_FROM names the file.
keyfile() { # <path>
  local m
  KEY_V='' KEY_FROM="the key file $1"
  m=$(stat -L -c '%a %u' -- "$1" 2>/dev/null) && [ -f "$1" ] || { KEY_FROM="the key file $1 is not there"; return 1; }
  [ "${m#* }" = "$(id -u)" ] || { KEY_FROM="the key file $1 is not yours"; return 1; }
  (( (8#${m%% *} & 8#077) == 0 )) || { KEY_FROM="the key file $1 has mode ${m%% *}, which lets others read or write it: run chmod 600 on it"; return 1; }
  IFS= read -r KEY_V < "$1"; KEY_V=${KEY_V%$'\r'}
  [ -n "$KEY_V" ] || { KEY_FROM="the key file $1 is empty"; return 1; }
}
# One real call to a provider's own API with a key, as a session makes it: anthropic, GET <base>/v1/models with the key
# as x-api-key; openai, GET <base>/models with it as a Bearer token. The key goes to the call in its environment, never
# on a command line, and is not sent on to a redirect. Prints "works", else "fails (<why>)", with what looks like a
# credential in the API's words left out. A progress line on stderr first, as the call can take up to 40 s.
apicheck() { # <anthropic|openai> <base URL> <key>
  echo "conveyor: checking the $([ "$1" = anthropic ] && echo Anthropic || echo OpenAI) API at $2 with one call (up to 40 s)..." >&2
  CONVEYOR_APIKEY=$3 timeout 40 python3 -I -c 'import json, os, re, sys, urllib.error, urllib.request
api, base = sys.argv[1], sys.argv[2].rstrip("/")
key = os.environ.pop("CONVEYOR_APIKEY")
def plain(w):
    w = str(w).replace(key, "[left out]") if key else str(w)
    return re.sub(r"[A-Za-z0-9_*-]{20,}", "[left out]", w).replace(";", ",")[:200]
if api == "anthropic": url, head = base + "/v1/models", {"x-api-key": key, "anthropic-version": "2023-06-01"}
else: url, head = base + "/models", {"Authorization": "Bearer " + key}
class Stay(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a): return None
try:
    with urllib.request.build_opener(Stay).open(urllib.request.Request(url, headers=head), timeout=30) as r: print("works")
except urllib.error.HTTPError as e:
    try: said = json.loads(e.read()).get("error") or {}
    except Exception: said = {}
    msg = said.get("message") if isinstance(said, dict) else None
    print("fails (HTTP %d%s)" % (e.code, ": " + plain(msg) if msg else ""))
except Exception as e: print("fails (%s)" % plain(getattr(e, "reason", e)))' "$1" "$2" 2>/dev/null || echo "fails (no answer)"
}
# The route set for the role a session started now runs as (PROXY_ROLE: builder, the default, or reviewer) on <cli>
# (claude, the default, or codex): subscription, fallback or proxy; nothing when no proxy is set for that CLI.
proxyrole() { # [claude|codex]
  local p; if [ "${1:-claude}" = codex ]; then p=$(codexproxyset); else p=$(claudeproxy); fi; [ -n "$p" ] || return 0
  jq -r --arg r "${PROXY_ROLE:-builder}" '(.roles // {})[$r] | if IN("subscription", "fallback") then . else "proxy" end' <<<"$p"
}
# The route a session started now takes: proxy, subscription (a fallback proxy not in use yet, or a role set to the
# subscription), or nothing when no proxy is set. PROXY_NOW set: this try is the one through the fallback proxy.
proxyroute() { # [claude|codex]
  local r; r=$(proxyrole "${1:-claude}"); [ -n "$r" ] || return 0
  if [ "$r" = proxy ] || { [ "$r" = fallback ] && [ -n "${PROXY_NOW:-}" ]; }; then echo proxy; else echo subscription; fi
}
# Each Claude route's state as the last session on it found it (routeset(), session.sh); health() reads it (routesnow()).
ROUTES=${STATE%/*}/routes.json
# For health: {subscription, proxy}, each {state, at} as ROUTES has it, else {state: "not checked"}; the proxy's
# {state: "not set"} when no proxy is set, else with its baseUrl, its roles (each role's route) and route: "fallback"
# when a role uses it as the fallback, else "proxy"; the subscription's {state: "not used"} when every role runs
# through the proxy. The subscription's roles: the roles whose sessions run on the subscription login now, so its usage
# limit and account are theirs alone (subroles()): a role on "subscription", or on "fallback" (each of its sessions starts
# on the login, proxyroute(), even after a login that failed before); every role when no proxy is set.
# Worked out in two jq runs (claudeproxy's and this) and kept, keyed on what they read: the host file's text, the
# pack's models.claudeProxy and ROUTES's text (ROUTES_K), so a subshell started after asks again with no program.
ROUTES_K=() # the key, then the answer
routesnow() {
  local p r h='' m='' k a=1
  [ ! -e "$HOST" ] || { IFS= read -r -d '' h; a=$?; } 2>/dev/null <"$HOST"
  packget models.claudeProxy m 2>/dev/null || m=''
  { r=$(<"$ROUTES"); } 2>/dev/null || r=null
  # A host file with a NUL byte (read stops there, exit 0) is read as before and never kept: a bash variable cannot hold it.
  k=$h$'\037'$m$'\037'$r
  [ "$a" = 1 ] && [ "${#ROUTES_K[@]}" = 2 ] && [ "${ROUTES_K[0]}" = "$k" ] && { printf '%s\n' "${ROUTES_K[1]}"; return 0; }
  p=$(claudeproxy); [ -n "$p" ] || p=null
  p=$(jq -c --argjson p "$p" 'if type == "object" then . else {} end
    | ($p | if . == null then null else [.roles // {} | (.builder, .reviewer) | if IN("subscription", "fallback") then . else "proxy" end] end) as $r
    | ["builder", "reviewer"] as $n
    | (if $r == null then $n else [range(2) | select($r[.] != "proxy") | $n[.]] end) as $on
    | {subscription: ((if $r != null and ($r | all(. == "proxy")) then {state: "not used"} else .subscription // {state: "not checked"} end) + {roles: $on}),
       proxy: (if $p == null then {state: "not set"} else (.proxy // {state: "not checked"})
         + {baseUrl: $p.baseUrl, roles: {builder: $r[0], reviewer: $r[1]}, route: (if $r | any(. == "fallback") then "fallback" else "proxy" end)} end)}' <<<"$r" 2>/dev/null) || p=null
  [ "$a" != 1 ] || ROUTES_K=("$k" "$p")
  printf '%s\n' "$p"
}
# The roles whose Claude sessions run on the subscription login now (routesnow()), one a line: the guard reads the
# usage limit of their accounts alone, as a role on an API route has no usage limit (billed per token).
subroles() { routesnow | jq -r '(.subscription.roles // ["builder", "reviewer"])[]' 2>/dev/null; }
# Run in a card session's subshell before claude starts: the route's base URL, its key (routekey()), and with a base
# URL that is not api.anthropic.com, ENABLE_TOOL_SEARCH (true unless toolSearch names otherwise). A proxy (kind proxy)
# is sent the key as a Bearer token (ANTHROPIC_AUTH_TOKEN); the Anthropic API (kind api) as its own API key
# (ANTHROPIC_API_KEY, sent as x-api-key), never as a Bearer token. Any other Anthropic key in the environment is
# dropped first, so the route is never sent a key it was not named. A session on the subscription (proxyroute
# subscription) is given none of it. With no key, a proxy (and the fallback route of either kind) is given a stand-in
# key (NOKEY): with none, Claude Code sends the machine's own login, which a proxy that needs no key does not take,
# and which on the fallback is the one that failed. The API (kind api, not the fallback) with no key is given none.
NOKEY=no-key
proxyenv() {
  local p b t v r; proxypack; r=$(proxyroute); [ "$r" = proxy ] || return 0
  p=$(claudeproxy); b=$(jq -r '.baseUrl // "https://api.anthropic.com"' <<<"$p"); t=$(jq -r '.toolSearch // "true"' <<<"$p")
  routekey "$p"; v=$KEY_V
  [ -n "$v" ] || { [ -z "${PROXY_NOW:-}" ] && [ "$(jq -r .kind <<<"$p")" = api ]; } || v=$NOKEY
  unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY
  export ANTHROPIC_BASE_URL=$b
  if [ -z "$v" ]; then :
  elif [ "$(jq -r .kind <<<"$p")" = api ]; then export ANTHROPIC_API_KEY="$v"
  else export ANTHROPIC_AUTH_TOKEN="$v"; fi
  [[ $b =~ ^https?://api\.anthropic\.com(:[0-9]+)?(/|$) ]] || export ENABLE_TOOL_SEARCH=$t
}
# A Codex session's provider settings, in the array CODEX_PX: none on the subscription; through the proxy or the OpenAI
# API (proxyroute codex), Codex's -c settings of a provider, conveyor-proxy, at codexProxy's baseUrl on the Responses
# API, its env_key the variable keyEnv names when its key is found (routekey()), exported in the session's subshell
# this is called in, so a key the service's bare environment lacks still reaches Codex. A proxy (not kind api) with no
# key found is given the stand-in key (NOKEY) in NOKEYENV, so Codex never sends it the machine's own login.
CODEXPROV=conveyor-proxy
NOKEYENV=CONVEYOR_PROXY_NOKEY
codexargs() {
  local p b k
  CODEX_PX=(); [ "$(proxyroute codex)" = proxy ] || return 0
  p=$(codexproxyset); b=$(jq -r '.baseUrl | strings' <<<"$p"); k=$(jq -r '.keyEnv | strings' <<<"$p")
  [ -n "$b" ] || return 0
  routekey "$p"
  if [[ $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -n "$KEY_V" ]; then declare -gx "$k=$KEY_V"
  elif [ -z "$KEY_V" ] && [ "$(jq -r .kind <<<"$p")" != api ]; then k=$NOKEYENV; declare -gx "$k=$NOKEY"; else k=''; fi
  codexpx "$b" "$k"
}
# The sandbox of a Codex session that runs commands (a build's, a review's, a judge's), in the array CODEX_SB: Codex's
# own (-s <mode>), except in a benchmark's task container (CONVEYOR_BENCH_BOX, which the bench sets on a conveyor arm's
# run, bench/swe_arms.sh swe_trial()): there Codex's Linux sandbox cannot start a command, and the container, with only
# the task mounted, is the sandbox, so the session runs without Codex's (a review's or judge's worktree is put back
# after it, codexreview() and judgecall()).
codexsb() { # <sandbox mode: read-only or workspace-write>
  # shellcheck disable=SC2034 # read by lib/review.sh and lib/session.sh
  if [ -n "${CONVEYOR_BENCH_BOX:-}" ]; then CODEX_SB=(--dangerously-bypass-approvals-and-sandbox); else CODEX_SB=(-s "$1"); fi
}
# Codex's -c settings of the provider conveyor-proxy at <base URL> on the Responses API, in CODEX_PX, its env_key the
# variable named when one is.
codexpx() { # <base URL> [key variable]
  # shellcheck disable=SC2034 # read by lib/pick.sh, lib/review.sh, lib/session.sh and lib/testaction.sh
  CODEX_PX=(-c "model_provider=\"$CODEXPROV\"" -c "model_providers.$CODEXPROV={name = \"$CODEXPROV\", base_url = $(jq -rn --arg b "$1" '$b | @json')$([ -z "${2:-}" ] || printf ', env_key = "%s"' "$2"), wire_api = \"responses\"}")
}
# One real call on <cli> (claude or codex), as a check session makes it: in an empty folder, under 120 s, with no
# project settings, Claude on the account folder in CALL_ACCT (acctrun(); none: the default login), and with none of
# the environment's Anthropic or OpenAI keys and base URLs, which the machine's service does not have. With a route (its JSON), through it, sent <key> as a
# session is: Claude's proxy as a Bearer token (ANTHROPIC_AUTH_TOKEN), its API (kind api) as ANTHROPIC_API_KEY;
# Codex's in the variable keyEnv names, through its provider settings (codexpx()). The key goes in the call's
# environment, never on a command line. A proxy (not kind api) with no key is sent the stand-in key (NOKEY), as a
# session is (proxyenv(), codexargs()). Prints "works", else "fails (<the first line it wrote with an authentication status, else that reads as an error and is not a retry, else its first line>)", with the key and what
# looks like a credential left out, and fails. A progress line on stderr first, as the call can take up to 120 s; for
# Claude, a "warning:" line on stderr after it when the call works and every answer of its stream reports usage 0.
routecall() { # <claude|codex> <model, or "" for the CLI's own default> [<route JSON> <key>]
  local d o rc k='' v=${4:-}
  echo "conveyor: checking $1${2:+ ($2)} $([ -z "${3:-}" ] && echo "on its own login" || jq -r '"through \(.baseUrl // "https://api.anthropic.com")"' <<<"$3") with one call (up to 120 s)..." >&2
  d=$(mktemp -d) || { echo "fails (no folder for the call)"; return 1; }
  [ -z "${3:-}" ] || { k=$(jq -r '.keyEnv | strings' <<<"$3"); [[ $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || k=''; }
  if [ -n "${3:-}" ] && [ -z "$v" ] && [ "$(jq -r .kind <<<"$3")" != api ]; then v=$NOKEY; [ "$1" = claude ] || k=$NOKEYENV; fi
  o=$(cd "$d" && unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY OPENAI_API_KEY ENABLE_TOOL_SEARCH CLAUDE_CONFIG_DIR ${k:+"$k"}
    if [ "$1" = claude ]; then acctrun "${CALL_ACCT:-}"
      if [ -n "${3:-}" ]; then export ANTHROPIC_BASE_URL; ANTHROPIC_BASE_URL=$(jq -r '.baseUrl // "https://api.anthropic.com"' <<<"$3")
        if [ -z "$v" ]; then :; elif [ "$(jq -r .kind <<<"$3")" = api ]; then export ANTHROPIC_API_KEY="$v"; else export ANTHROPIC_AUTH_TOKEN="$v"; fi
      fi
      exec timeout --kill-after=10 120 claude -p ${2:+--model "$2"} --setting-sources "" --strict-mcp-config --no-session-persistence --output-format stream-json --verbose <<<"Reply with the one word OK." 2>&1
    fi
    CODEX_PX=()
    if [ -n "${3:-}" ]; then { [ -n "$k" ] && [ -n "$v" ] && export "$k=$v"; } || k=''; codexpx "$(jq -r '.baseUrl | strings' <<<"$3")" "$k"; fi
    exec timeout --kill-after=10 120 codex exec --skip-git-repo-check -s read-only "${CODEX_PX[@]}" ${2:+-m "$2"} - <<<"Reply with the one word OK." 2>&1); rc=$?
  rm -rf "$d"
  if [ "$1" = claude ]; then
    # Claude's call streams as a session does (stream-json): a stream whose answers all report usage 0 gives a card
    # no cost while its step runs (#391), so it is named on stderr, as setup and doctor show it. The stream's other
    # lines are read as its text: a result's message, and every line that is not JSON.
    if [ $rc = 0 ] && jq -Rne '[inputs | try fromjson catch null | objects | select(.type == "assistant") | .message.usage | objects
        | [.[] | numbers] | add // 0] | length > 0 and all(. == 0)' <<<"$o" >/dev/null 2>&1; then
      echo "warning: claude$([ -z "${3:-}" ] || jq -r '" through \(.baseUrl // "https://api.anthropic.com")"' <<<"$3") reports token usage 0 in every answer of its stream: a card's cost on /units and the Board is shown only when its step ends" >&2
    fi
    o=$(jq -Rr '. as $l | (try fromjson catch null) as $e | if ($e | type) != "object" then $l elif $e.type == "result" then ($e.result // empty | tostring) else empty end' <<<"$o" 2>/dev/null) || :
  fi
  [ $rc != 0 ] || { echo works; return 0; }
  [ -z "${4:-}" ] || o=${o//"$4"/[left out]}
  # The first line that gives an authentication status, else the first other line that reads as an error and is not a
  # retry, else the first line: Codex prints its banner before it sends the call, and "ERROR: Reconnecting... 1/5"
  # (no status) before its last error, so routecheck() can read a 401.
  o=$({ grep -m 1 -iE 'unauthori|forbidden|\b40[13]\b' <<<"$o" || grep -iE 'error' <<<"$o" | grep -m 1 -viE 'reconnecting' || grep -m 1 '[^[:space:]]' <<<"$o"; } | sed -E 's/[A-Za-z0-9_-]{24,}/[left out]/g; s/;/,/g' | cut -c 1-200)
  echo "fails (${o:-exit $rc})"; return 1
}
# Codex's: the top-level model_provider of Codex's config.toml and that provider's base_url and env_key, as
# "<name>\037<base_url>\037<env_key>"; nothing when the file names no provider. A provider with no base_url is direct.
# A session the host file's codexProxy routes (proxyroute codex) is given that one instead (codexargs()).
codexproxy() {
  local f=${CODEX_HOME:-$HOME/.codex}/config.toml
  [ "$(proxyroute codex)" != proxy ] || { jq -j --arg n "$CODEXPROV" '"\($n)\u001f\(.baseUrl // "")\u001f\(.keyEnv // "")\n"' <<<"$(codexproxyset)"; return 0; }
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
    # The host file's codexProxy: its key where a session finds it (routekey()), a key file's included.
    if [[ $name$base == *[Cc]opilot* ]]; then :
    elif [ "$(proxyroute codex)" = proxy ]; then local KEY_V KEY_FROM; routekey "$(codexproxyset)"; key=$KEY_V
    elif [[ $env =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then key=$(envof "$env"); fi
    m=$(printf '%s\n%s\n' "${base%/}/models" "$key" | timeout 20 python3 -I -c "$fetch" 2>/dev/null | jq -r --arg f "$1" "[.data[]?.id, .models[]?.id] | $newest" 2>/dev/null) || m=''
  fi
  # The proxy unreachable, or listing no model of this family: Codex's models_cache.json answers.
  [ -n "$m" ] || m=$(jq -r --arg f "$1" "[.models[]? | .slug // .id] | $newest" "${CODEX_HOME:-$HOME/.codex}/models_cache.json" 2>/dev/null) || m=''
  [ -n "$m" ] || { echo "the reviewer model $1 is a family name and no gpt-<version>-$1 is in $([ -n "$base" ] && echo "the models of ${base%/}/models or ")Codex's models_cache.json: set models.allowed.codex in .conveyor/project.json (and the control record's reviewer) to the full model id"; return 1; }
  echo "$m"
}
# Doctor's answers of codexmodel() for Codex's family names, by "<role>:<family>", a failed one too: modelswarn()
# (lib/setup.sh) fills it as it resolves them, and routes() takes a role's from it, so one doctor asks for each family
# once for each route.
declare -gA CODEXMODEL_V=()
# Before a card starts: the reviewer in force, when Codex runs it, resolves to a model id (codexmodel).
codexready() {
  local s m a PROXY_ROLE=reviewer # the reviewer's route (proxyroute())
  s=$(seat reviewer) && jqget "$s" agent a model m || return 0
  [ "$a" = codex ] || return 0
  m=$(codexmodel "$m") || { echo "$m"; return 1; }
}
# For doctor, a part of a role's route line: what one real call on <cli> gives, as the machine's service makes it.
# login: on the CLI's own login (routecall()). route: through the route set for the CLI (its JSON), with its key as the
# service finds it (routekey() with no environment of the caller's): the provider's own API (kind api) called with that
# key (apicheck()), a proxy through the CLI (routecall()). A proxy the service finds no key for is called with none:
# when that call works, the proxy needs none and the line says so. When the API has no key, or a proxy refuses the call
# with no key (an authentication error, not a proxy that is stopped), a second line follows: "missing: <the key>; fix: <where to put it>". Fails when the call fails, or for
# the API when the service finds no key.
routecheck() { # <claude|codex> <model> <login|route> [<route JSON>]
  local s kind
  if [ "$3" = login ]; then s=$(routecall "$1" "$2"); printf '; its login %s' "$s"; [ "$s" = works ]; return; fi
  kind=$(jq -r .kind <<<"$4"); routekey "$4" service
  if [ -n "$KEY_V" ]; then printf '; the service reads the key from %s' "$KEY_FROM"
  elif [ "$kind" != api ] && s=$(routecall "$1" "$2" "$4" ""); then printf '; the proxy needs no key: one call through it with none %s' "$s"; return 0
  else printf '; the service finds no key: %s%s' "$KEY_FROM" "${s:+, and one call through it with none $s}"
    # A proxy that fails for another reason (stopped, unreachable) is not shown as a missing key.
    [ "$kind" = api ] || grep -qiE '401|403|unauthori|authenticat|forbidden|api key|x-api-key' <<<"$s" || return 1
    printf '\nmissing: a key the service can find for the %s route through %s; fix: put it in %s in the env of %s, or name a key file of mode 600 as keyFile of %s in %s' \
      "$1" "$(jq -r .baseUrl <<<"$4")" "$(jq -r '.keyEnv // "the variable that keyEnv names"' <<<"$4")" "$CLAUDE_SETTINGS" "$([ "$1" = claude ] && echo claudeProxy || echo codexProxy)" "$HOST"
    return 1; fi
  if [ "$kind" = api ]; then s=$(apicheck "$([ "$1" = claude ] && echo anthropic || echo openai)" "$(jq -r .baseUrl <<<"$4")" "$KEY_V"); printf ', and the API %s' "$s"
  else s=$(routecall "$1" "$2" "$4" "$KEY_V"); printf ', and one call through it %s' "$s"; fi
  [ "$s" = works ]
}
# Whether the host file sets <cli>'s route to its own login only ({kind: "subscription"}, as setup writes it).
routesub() { # <claude|codex>
  jq -e --arg n "$([ "$1" = claude ] && echo claudeProxy || echo codexProxy)" '.[$n].kind? == "subscription"' "$HOST" >/dev/null 2>&1
}
# For doctor: each role's model and its route, direct or through which proxy or API; a route the host file or the pack
# sets, its own login only included, is checked as the service runs it (routecheck()). The builder's seat runs build,
# fix and rebase. A Claude role is checked on the account its cards run on (cardaccts()): the builder's the control
# record's account, the reviewer's its reviewAccount, else that account.
routes() {
  local r s m a p name base env rc=0 PROXY_ROLE w c l k v CALL_ACCT
  proxypack; k=$(ctl 2>/dev/null) || k=null
  for r in builder reviewer; do
    PROXY_ROLE=$r
    s=$(seat "$r") || { echo "$r: the pack's models.allowed lists no $r model"; rc=1; continue; }
    jqget "$s" model m agent a || m='' a=''
    if [ "$a" = claude ]; then
      CALL_ACCT=$(acctenv "$(jq -r --arg r "$r" 'if $r == "reviewer" then .reviewAccount // .account else .account end // ""' <<<"$k")") \
        || { echo "$r: $m (claude): $CALL_ACCT"; rc=1; continue; }
      p=$(claudeproxy); w=$(proxyrole); c=''
      # A route setup set: each part the role takes checked with one real call, as the service makes it; a fallback
      # works when either of its two parts does.
      if [ -n "$p" ] && [ "$w" != subscription ]; then
        l=0; [ "$w" != fallback ] || { c=$(routecheck claude "$m" login) && l=1; }
        c+=$(routecheck claude "$m" route "$p") && l=1; [ $l = 1 ] || rc=1
        echo "$r: $m (claude) $([ "$w" != fallback ] || echo "on the subscription login, then when its login fails ")$(jq -r '"through \(if .kind == "api" then "the Anthropic API at " else "" end)\(.baseUrl), key in \(.keyEnv // "no variable")"' <<<"$p")$c"
      elif [ -n "$p" ] || routesub claude; then c=$(routecheck claude "$m" login) || rc=1; echo "$r: $m (claude) on the subscription login$c"
      # None named: a card session inherits the engine's own environment, base URL and all.
      elif [ -n "${ANTHROPIC_BASE_URL:-}" ]; then echo "$r: $m (claude) through $ANTHROPIC_BASE_URL, from the environment Conveyor runs in"
      else echo "$r: $m (claude) direct"; fi
    elif [ "$a" = opencode ]; then p=${m#opencode:}; echo "$r: $m (opencode) through its provider ${p%%/*}, as OpenCode's own config and sign-in set it"
    else
      name='' base='' env=''; IFS=$'\037' read -r name base env < <(codexproxy)
      if [ -n "${CODEXMODEL_V[$r:$m]:-}" ]; then # "<codexmodel's exit status>\037<what it printed>"
        v=${CODEXMODEL_V[$r:$m]}; m=${v#*$'\037'}; [ "${v%%$'\037'*}" = 0 ] || { echo "$r: $m"; rc=1; continue; }
      else m=$(codexmodel "$m") || { echo "$r: $m"; rc=1; continue; }; fi
      p=$(codexproxyset); w=$(proxyrole codex); c=''
      if [ "$w" = fallback ]; then
        l=0; c=$(routecheck codex "$m" login) && l=1; c+=$(routecheck codex "$m" route "$p") && l=1; [ $l = 1 ] || rc=1
        echo "$r: $m (codex) on its own login, then when its login fails through $(jq -r '"\(if .kind == "api" then "the OpenAI API at " else "" end)\(.baseUrl), key in \(.keyEnv // "no variable")"' <<<"$p")$c"
      else
        if [ -n "$p" ] && [ "$w" != subscription ]; then c=$(routecheck codex "$m" route "$p") || rc=1
        elif [ -n "$p" ] || routesub codex; then c=$(routecheck codex "$m" login) || rc=1; fi
        if [ -n "$base" ]; then echo "$r: $m (codex) through $base, Codex's model_provider $name, key in ${env:-no variable}$c"
        elif [ -n "$c" ]; then echo "$r: $m (codex) on its own login$c"
        else echo "$r: $m (codex) direct"; fi
      fi
    fi
    # A missing: line fails doctor, as every one does, a fallback's whose login works too.
    [[ ${c:-} != *$'\nmissing: '* ]] || rc=1
  done
  return $rc
}
# The models and efforts in force, as the readers name them, in one jq run: {models: {claude: the sessions', codex:
# the review's, whichever program runs it}, efforts: the same}.
inforce() { # [the control record, when the caller has read it]
  local a c=${1:-}; [ -n "$c" ] || c=$(ctl 2>/dev/null) || c=null
  modelsallowed a || a=null
  jq -c --argjson c "$c" "$SEATNOW"'(first(seatnow("builder"; $c)) // {}) as $b
    | (first(seatnow("reviewer"; $c)) // {}) as $r | {models: {claude: ($b.model // null), codex: ($r.model // null)},
      efforts: {claude: ($b.effort // null), codex: ($r.effort // null)}}' <<<"$a"
}
# The model settings of the two seats, as the Board sets them: {builder, reviewer}, each {model, effort: the
# ones in force (seat()), modelFrom, effortFrom: "control" when the control record sets it, else "seed" (the seed's,
# seed()), choices: the models the pack allows the seat (okmodels: the reviewer's Codex's, then its Claude ones),
# allowed: the same by CLI ({<cli>: its models, OpenCode's without the opencode: mark}: the list the Board offers after
# a CLI's own models, each once),
# efforts: the efforts the program of the model in force takes, agent: that program (null when no model is in
# force), clis: the CLIs installed on this host that the seat can be set to, each {models: the models it has
# registered (null: it offers no list, so the Board offers allowed's alone; either way, then a typed name), efforts: the efforts it takes in this seat}, and
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
  modelsallowed a || { echo null; return; }
  jq -c --argjson c "$c" --argjson e "$EFFORTS" --argjson h "$(hostclis)" "$SETTINGS"'settings($c; $e; $h)' <<<"$a" 2>/dev/null || echo null
}
# Why a per-card seat (`control card`) is refused, on stdout, or nothing when it is taken: its model is one the
# pack's models.allowed lists for the seat (the builder's list for the builder, the review's for the reviewer and the
# judge), and its effort, when one is given, one that model's CLI takes (an OpenCode builder takes none). Fails when
# models.allowed cannot be read.
cardok() { # <builder|reviewer|judge> <model> [effort]
  local a; modelsallowed a || { echo "conveyor: the pack's models.allowed cannot be read; nothing changed" >&2; return 1; }
  jq -r --arg s "$1" --arg m "$2" --arg f "${3:-}" --argjson e "$EFFORTS" "$OKMODELS"'okmodels(if $s == "builder" then "builder" else "reviewer" end) as $ok
    | ([$ok | to_entries[] | select(.value | index($m)) | .key] | first) as $g
    | if $g == null then "\($m) is not one of the models the pack'"'"'s models.allowed lets the \($s) run: \([$ok[][]] | if . == [] then "it lists none" else "it allows " + join(", ") end)"
      elif $f == "" then empty
      elif $s == "builder" and $g == "opencode" then "an OpenCode builder takes no effort: name the model alone"
      elif ($e[$g] | index($f)) == null then "\($g) takes no effort \($f) (it takes \($e[$g] | join(", ")))" else empty end' <<<"$a"
}
# Pick for me (`control card <issue> pick`, the Board's): one call to the project's judge (the judge seat, never the
# issue's own), with no tools and PICK_TIMEOUT at most, that chooses the builder, reviewer and judge settings for the
# issue from the models the pack allows each seat, given the issue's title and body, its size and areas (SPLITSIZE,
# lib/slices.sh), the project's seats in force and each allowed model's price (the price table the Board shows,
# dashboard_limit.py, with the pack's prices over it). Prints one JSON line, {issue, builder, reviewer, judge, model:
# the judge's}, each seat {model, effort (null: none, as an OpenCode builder takes), why}; changes nothing: the owner applies it (`control card`). An answer
# with a seat missing, a model or effort the seat does not take (cardok), or no reason, is refused with why: exit 1.
PICK_TIMEOUT=300
PICKASK='Choose the settings for the one issue below: the model and effort of its builder (the coding session that
builds and fixes the change), its reviewer (who reviews each round of the change) and its judge (who decides which
review findings count). Choose each from the models allowed for that seat, and an effort that model'"'"'s program takes
(null where it takes none).
Fit the choice to the issue: a small, clear change needs no large model or high effort; a large or risky one may.
Weigh the price of each model. Answer with one JSON object and nothing else:
{"builder": {"model": "...", "effort": "...", "why": "one line"}, "reviewer": {...}, "judge": {...}}'
cardpick() { # <issue>
  local n=$1 c s x issue out PICKANS='' PICKMODEL='' PICKUSE='' PICKWHY='' PICKPRICES=''
  c=$(ctl) || return 1
  names || return 1
  issue=$(gh issue view "$n" --json number,title,body,labels 2>/dev/null) && jq -e 'objects | .number' <<<"$issue" >/dev/null 2>&1 \
    || { echo "conveyor: issue #$n cannot be read" >&2; return 1; }
  pickcall "$issue" "$c" || { echo "conveyor: $PICKWHY" >&2; return 1; }
  out=$PICKANS
  for x in builder reviewer judge; do
    jqget "$out" "$x" s || return 1
    jq -e '(.model | type == "string") and (.effort == null or (.effort | type == "string")) and (.why | type == "string" and test("\\S")) and (.why | test("\n") | not)' <<<"$s" >/dev/null 2>&1 \
      || { echo "conveyor: the judge's answer gave the $x no model, effort and one line of reason: ${s:0:300}" >&2; return 1; }
    s=$(cardok "$x" "$(jq -r .model <<<"$s")" "$(jq -r '.effort // ""' <<<"$s")") || return 1
    [ -z "$s" ] || { echo "conveyor: the judge's choice for the $x is refused: $s" >&2; return 1; }
  done
  jq -c --argjson n "$n" --arg m "$PICKMODEL" '{issue: $n} + . + {model: $m}' <<<"$out"
}
# The judge's call of Pick for me (cardpick()) and of the rule Pick settings (pickjudge(), lib/modelpick.sh), on the
# issue <issue json> ({number, title, body, labels}). Sets the caller's PICKANS, the answer: {builder, reviewer,
# judge}, each {model (null for a blank one), effort (null for none), why} as the judge gave them (nothing else
# checked) or null; PICKMODEL, the judge's model; PICKUSE once the judge was called, the fields of the call's own card line: {model, effort, sec} and
# {tokens, usage} as a session's line on its program has them (sessionread.jq, codexread.jq, opencoderead.jq), or
# unread when its output holds no token usage; PICKPRICES, the price table the prompt names ({<model>: {input,
# output}}); and PICKWHY, why it failed: exit 1. With [<seats' models>] ({builder, reviewer, judge}, each [{model, g:
# its program, efforts}], chosen() of lib/modelpick.sh: the pick lists), the prompt lists those models and efforts
# for each seat; else each model the pack allows the seat, at every effort its program takes.
# shellcheck disable=SC2034 # PICKANS, PICKMODEL, PICKUSE, PICKPRICES and PICKWHY are the caller's, read by cardpick() and pickjudge()
pickcall() { # <issue json> <control record> [<seats' models>]
  local c=$2 issue=$1 k=${3:-null} a s x run size prices pp p d rc ans out effort model agent t0
  PICKANS='' PICKMODEL='' PICKUSE='' PICKWHY='' PICKPRICES=''
  modelsallowed a || { PICKWHY="the pack's models.allowed cannot be read"; return 1; }
  size=$(jq -c --arg area "$AREA" "$SPLITSIZE"' | .doneWhen |= length | .files |= length' <<<"$issue") || { PICKWHY="the issue's size cannot be read"; return 1; }
  packget prices pp 2>/dev/null && [ -n "$pp" ] || pp='{}'
  prices=$(jq -cn --argjson p "$pp" '{cards: [], prices: $p}' | python3 "$HERE/../.claude/scripts/dashboard_limit.py" cards 2>/dev/null \
    | jq -c --argjson p "$pp" '.table | with_entries(.value = {input: .value[0], output: .value[1]}) + ($p | with_entries(select(.value.input != null and .value.output != null) | .value |= {input, output}))' 2>/dev/null) \
    && [ -n "$prices" ] || prices='{}'
  PICKPRICES=$prices
  s=$(SEATCARD='' seat judge "$c") && jqget "$s" model model effort effort agent agent || { PICKWHY="the project has no judge to ask"; return 1; }
  PICKMODEL=$model
  [ -n "$k" ] || k=null
  p=$PICKASK$'\n\n'$(jq -r --argjson s "$size" --argjson pr "$prices" --argjson e "$EFFORTS" --argjson i "$issue" --argjson k "$k" \
      --argjson now "$(for x in builder reviewer judge; do SEATCARD='' seat "$x" "$c" || echo null; done | jq -cs '{builder: .[0], reviewer: .[1], judge: .[2]}')" "$OKMODELS"'
    def models($s): if $k == null then okmodels(if $s == "builder" then "builder" else "reviewer" end) | to_entries | map(.key as $g | .value[]
        | {model: ., g: $g, efforts: (if $s == "builder" and $g == "opencode" then [] else $e[$g] end)}) else $k[$s] // [] end;
    def list($s): models($s) | map("- \(.model) (\(.g); efforts: \(if .efforts == [] then "none" else .efforts | join(", ") end); "
      + (($pr[.model] // $pr[.model | sub("^opencode:"; "")]) as $x | if $x == null then "no price" else "$\($x.input) input, $\($x.output) output per million tokens" end) + ")") | join("\n");
    "# Models allowed for the builder\n\(list("builder"))\n\n"
    + (if models("reviewer") == models("judge") then "# Models allowed for the reviewer and the judge\n\(list("reviewer"))\n\n"
       else "# Models allowed for the reviewer\n\(list("reviewer"))\n\n# Models allowed for the judge\n\(list("judge"))\n\n" end)
    + "# The project'"'"'s settings now\n" + ($now | to_entries | map("- \(.key): \(.value.model // "none") at \(.value.effort // "no effort")") | join("\n"))
    + "\n\n# The issue'"'"'s size\n\($s.doneWhen) Done-when items, \($s.files) file paths named, \($s.areas) areas, \($s.chars) characters; labels: \([$i.labels[]?.name] | join(", "))"
    + "\n\n# The issue\n#\($i.number) \($i.title // "")\n\n\($i.body // "")"' <<<"$a") || { PICKWHY="the judge's prompt could not be made"; return 1; }
  d=$(mktemp -d) || { PICKWHY="no scratch folder for the judge's call"; return 1; }
  # The judge is the review's, as judgecall() (lib/review.sh) runs it: on the reviewer's route (proxyroute()) and on
  # the account a card's review uses (cardaccts(): its second line, the reviewAccount, only with a Claude reviewer;
  # else the builder's account, as RACCT is then unset).
  mapfile -t x < <(SEATCARD='' cardaccts "$c")
  t0=$SECONDS
  # The project's judge, as the prompt names it: never the issue's own (SEATCARD empty), whose model the line would misname.
  out=$(SEATCARD='' PROXY_ROLE=reviewer ASKSEAT=judge askmodel "$d" "$PICK_TIMEOUT" "${effort:-medium}" "$(jq -c --arg a "${x[1]-${x[0]-}}" '.account = (if $a == "" then null else $a end)' <<<"$c")" "$p"); rc=$?
  ans=$(cat "$d/answer" 2>/dev/null)
  # A Codex judge set by family name runs on the model id askmodel() resolved it to: the line names that one, which
  # the Board has a price for.
  [ ! -s "$d/model" ] || { model=$(head -n 1 "$d/model"); PICKMODEL=$model; }
  # The call's usage, as a session's line has it: a Claude judge's from its JSON output (askmodel() keeps it in raw),
  # split as sessionread.jq splits a session's; a Codex judge's from its events (err), as codexread.jq reads a
  # session's; an OpenCode judge's from its events, with OpenCode's cost, as opencoderead.jq reads them. A Codex
  # judge cut off before its turn completed (the timeout) has its running total read from the session file Codex
  # kept (rollout()), as judgecall() (lib/review.sh) reads a review judge's. The file is kept: the Board reads Codex's
  # session files for its usage reading and API spend.
  case $agent in
    codex) run=''; s=$(rollout "$d/err"); [ -z "$s" ] || run=$(grep '"token_count"' "$s" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null)
      PICKUSE=$(jq -Rcn --arg m "$model" --arg e "${effort:-medium}" --argjson s $((SECONDS - t0)) --argjson run "${run:-null}" "$CODEXREAD"' | {model, effort, sec} + (({tokens, usage} | select(.tokens != null)) // {unread})' "$d/err" 2>/dev/null) ;;
    opencode) PICKUSE=$(jq -Rcn --arg m "$model" --argjson s $((SECONDS - t0)) "$OPENCODEREAD"' | {model, sec} + (({tokens, usage} | select(.tokens != null)) // {unread})' "$d/events" 2>/dev/null) ;;
    *) PICKUSE=$(jq -Rcn --arg m "$model" --arg e "${effort:-medium}" --argjson s $((SECONDS - t0)) '{model: $m, effort: $e, sec: $s}
    + (([inputs | fromjson? | objects | select(has("result") or has("is_error"))] | last | .usage | objects
       | {i: (.input_tokens | numbers), w: (.cache_creation_input_tokens | numbers), r: (.cache_read_input_tokens | numbers), o: (.output_tokens | numbers),
          h: ((.cache_creation | objects | .ephemeral_1h_input_tokens | numbers) // 0)}
       | select(.i != null and .w != null and .r != null and .o != null)
       | {tokens: {claude: (.i + .w + .o), codex: 0}, usage: {input: .i, write: (.w - .h), write1h: .h, read: .r, output: .o}})
       // {unread: "the judge'"'"'s answer holds no token usage"})' "$d/raw" 2>/dev/null) ;;
  esac
  [ -n "$PICKUSE" ] || PICKUSE=$(jq -cn --arg m "$model" --arg e "${effort:-medium}" --argjson s $((SECONDS - t0)) '{model: $m, effort: $e, sec: $s, unread: "the judge'"'"'s answer holds no token usage"}')
  rm -rf "$d"
  [ "$rc" = 0 ] && [ -z "$out" ] || { PICKWHY="the judge ($model) did not answer: ${out:-exit $rc; 124 is the ${PICK_TIMEOUT}s timeout}"; return 1; }
  # The answer's JSON object: from its first { to its last }.
  PICKANS=$(jq -Rsc '(index("{")) as $i | (rindex("}")) as $j | if $i == null or $j == null then error("no JSON object") else .[$i:$j + 1] | fromjson end
      | {builder, reviewer, judge} | map_values(if type == "object" then {model: (.model | if type == "string" and (test("\\S") | not) then null else . end), effort: (.effort | if . == "" then null else . end), why} else null end)' <<<"$ans" 2>/dev/null) \
    || { PICKANS=''; PICKWHY="the judge's answer held no JSON object of the three seats: ${ans:0:300}"; return 1; }
}
# The cap in force: the control record's, else the seed's (CAP0); nothing when the record does not read.
capnow() { # [the control record, when the caller has read it]
  local c=${1:-}; [ -n "$c" ] || c=$(ctl 2>/dev/null) || c=null
  jq -e --argjson d "$CAP0" 'objects | .cap // $d' <<<"$c" 2>/dev/null
}
# Under the lock: one change to the control record, written whole beside it and moved into place, so a reader finds
# the old record or the new one. Prints the record as it now stands. A bad action or argument changes nothing: exit 2.
control() { # [action [arguments]]
  local c a=${1:-} f=. new x ag es bx sz top=0 p='' open=''
  c=$(ctl) || return 1
  [ $# = 0 ] || shift
  bad() { echo "usage: conveyor.sh control [pause | resume | stop | cap <1-100|off> | guard <1-100|off> | atonce <number> | suite-mode <serial|parallel> | tests-from <UTC time | clear> | suite-machine <local | ssh <target> [--dir <d>] | devbox [--size <s>] [--box <name>] [--setup-at <time>]> | hold <issue>... | release <issue>... | adopt <issue>... | order [<issue>...] | unpin <issue>... | rules <P0|P1|P2|P3|followups|push|visible|lint|testissues|foremanissues|followupissues|releaseissues|splitissues|<areaPrefix><name>>=<on|off>... | rules <split|pick>=<off|shadow|on> | pick <small|medium> <docs|code> <promote|keep|drop|add|next> | pick <reviewer|judge> <promote <model> [effort]|drop> | model <cli> <model> [effort] | model default | reviewer <cli> <model> [effort] | reviewer default | judge <cli> <model> [effort] | judge default | tests <cli> <model> [effort] | tests default | judge <on|off> | judge always [<kind>...] | account [<name>] | review-account [<name>] | start <queue|held> | start queue filed | dep-guard <on|off> | land-as <main|pr> | pr-merge <button|release|idle> | push-check <on|off> | force <issue> | depends <issue> <add|remove> <issue>... | onboarded <rule>... | card <issue> <builder|reviewer|judge> <model> [effort] | card <issue> [builder|reviewer|judge] clear | card <issue> pick]" >&2; return 2; }
  nums() { local x; for x; do [[ $x =~ ^[1-9][0-9]{0,8}$ ]] || return 1; done; }
  # A main-red fix card is of no issue (issue 0), named by its card id: there is nothing of it to hold or release.
  case $a in hold | release) for x; do [[ ! $x =~ ^(0+|c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0)$ ]] || {
    echo "conveyor: a main-red fix card, shown as \"Main is red (<commit>)\", has no issue to $a ($x). Give back a blocked one with \`conveyor.sh retry <card id>\`, or close it with \`conveyor.sh shut <card id>\`; nothing changed" >&2; return 2; }; done ;; esac
  case $a in
    '') [ $# = 0 ] || { bad; return; } ;;
    pause | resume | stop) [ $# = 0 ] || { bad; return; }; f='.mode = {pause: "pause", resume: "run", stop: "stop"}[$a] | if $a == "resume" then .signin = null else . end' ;;
    cap) [ $# = 1 ] && [[ $1 =~ ^(100|[1-9][0-9]?|off)$ ]] || { bad; return; }; f='.cap = ($v[0] | if . == "off" then null else tonumber end)' ;;
    guard) [ $# = 1 ] && [[ $1 =~ ^(100|[1-9][0-9]?|off)$ ]] || { bad; return; }; f='.guard = ($v[0] | if . == "off" then null else tonumber end)' ;;
    # atonce: the most test files a parallel release suite runs at once (suiteAtOnce; relatonce() caps it at the test slots).
    atonce) [ $# = 1 ] || { bad; return; }
      [[ $1 =~ ^[1-9][0-9]{0,2}$ ]] || { echo "conveyor: control atonce: \"$1\" is not a whole number from 1 to 999 (the most test files a parallel release suite runs at once); nothing changed" >&2; return 2; }
      f='.suiteAtOnce = ($v[0] | tonumber)' ;;
    # suite-mode: how a release's suite runs its test files when the command names no mode (suiteMode, release-prep.sh).
    suite-mode) [ $# = 1 ] || { bad; return; }
      [[ $1 =~ ^(serial|parallel)$ ]] || { echo "conveyor: control suite-mode: \"$1\" is not serial or parallel; nothing changed" >&2; return 2; }
      f='.suiteMode = $v[0]' ;;
    # tests-from: the test history's start (testsFrom, histstart() in lib/testfiles.sh): a UTC time, 2026-11-21T00:00:00Z,
    # or clear. Nothing is deleted; the readers of the test history count only what is on or after it.
    tests-from) [ $# = 1 ] || { bad; return; }
      [ "$1" = clear ] || { [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && jq -en --arg t "$1" '$t | fromdate' >/dev/null 2>&1; } \
        || { echo "conveyor: control tests-from: \"$1\" is not a UTC time like 2026-11-21T00:00:00Z, or clear; nothing changed" >&2; return 2; }
      f='.testsFrom = ($v[0] | if . == "clear" then null else . end)' ;;
    # suite-machine: where a release's whole suite runs (suiteMachine, lib/suitehost.sh): here, or a Linux box over ssh,
    # its folder there ~/conveyor-suite unless --dir names one (~, a path under ~/, or a full path). A target is
    # user@host or a host (an ssh config name too), never one that ssh would read as an option. devbox: a Namespace
    # Devbox of --size (4x8 unless given), leased under the tag conveyor-suite-<project>, and stopped when idle for 15m; with --box <name>, the
    # devbox of that name that the account already has, started and used as it is, with no devbox acquired. Saved again
    # with the same box, or with no box named and the same size, it keeps the setupAt of the box (a named box has its own size; a new box, or a new size of a tagged box, is a new box); --size <s> --setup-at <time> sets it (the Board's Undo).
    suite-machine) if [ "$*" = local ]; then f='.suiteMachine = {kind: "local"}'
      elif [ "${1:-}" = devbox ]; then
        # --setup-at <time>: the Board's Undo puts back the setupAt of the box the record had before this machine was chosen, and
        # needs the --size beside it. --box <name>: a devbox the account already has, used as it is (no devbox is acquired).
        x=4x8 es='' bx='' sz=''
        shift
        while [ $# -gt 0 ]; do
          [ $# -ge 2 ] || { bad; return; }
          case $1 in --size) x=$2 sz=1 ;; --box) bx=$2 ;; --setup-at) es=$2 ;; *) bad; return ;; esac
          shift 2
        done
        [ -z "$es" ] || [ -n "$sz" ] || { bad; return; }
        [[ $x =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "conveyor: control suite-machine: \"$x\" is not a devbox size (such as 4x8); nothing changed" >&2; return 2; }
        [[ -z $bx || $bx =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "conveyor: control suite-machine: \"$bx\" is not a devbox name; nothing changed" >&2; return 2; }
        [[ -z $es || $es =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] || { echo "conveyor: control suite-machine: \"$es\" is not a time such as 2026-11-20T15:04:00Z; nothing changed" >&2; return 2; }
        # jq reads a --size among its arguments as its own option: the values alone are given.
        set -- devbox "$x" "conveyor-suite-${REPO//[^A-Za-z0-9._-]/-}" "$es" "$bx"; f='.suiteMachine as $o | .suiteMachine = {kind: "devbox", size: $v[1], tag: $v[2], idleStop: "15m"}
          | if $v[4] != "" then .suiteMachine.box = $v[4] else . end
          | if $v[3] != "" then .suiteMachine.setupAt = $v[3]
            elif $o.kind == "devbox" and $o.tag == $v[2] and ($o.box // "") == $v[4] and ($v[4] != "" or $o.size == $v[1]) and $o.setupAt then .suiteMachine.setupAt = $o.setupAt else . end'
      elif [ "${1:-}" = ssh ] && { [ $# = 2 ] || { [ $# = 4 ] && [ "$3" = --dir ]; }; }; then
        [[ $2 =~ ^[A-Za-z0-9._][A-Za-z0-9._@-]*$ ]] || { echo "conveyor: control suite-machine: \"$2\" is not an ssh target (user@host or a host); nothing changed" >&2; return 2; }
        [ $# = 2 ] || { [[ $4 =~ ^(~$|~/|/) ]] && [[ $4 != *$'\n'* ]]; } || { echo "conveyor: control suite-machine: \"$4\" is not ~, a folder under ~/ or a full path; nothing changed" >&2; return 2; }
        # jq reads a --dir among its arguments as its own option: the folder alone is given.
        set -- ssh "$2" "${4:-}"; f='.suiteMachine = {kind: "ssh", target: $v[1], dir: (if $v[2] == "" then "~/conveyor-suite" else $v[2] end)}'
      else bad; return; fi ;;
    hold) [ $# != 0 ] && nums "$@" || { bad; return; }; f='.held = (.held + ($v | map(tonumber)) | unique)' ;;
    # adopt: the filing hooks' hold (foreman/foreman.sh filed) of the issues named: each one opened after a span of
    # startHeld began, whether or not it has ended (the owner may select Queue while a command files several), that
    # startSeen does not have yet, whatever its labels (adopted() also passes over a follow-up). One released already,
    # even a moment after it was filed, or held once, is left as it is, so a release is never undone.
    adopt) [ $# != 0 ] && nums "$@" || { bad; return; }
      f='. as $c | [$v[] | tonumber | select(. as $i | (IN($c.startSeen[]) | not) and ($c.startHeld | any($i > .from)))] as $n
         | .held = (.held + $n | unique) | .startSeen = (.startSeen + $n | unique)' ;;
    # release: one released is never held again by adopted(), whatever the setting or who opened it.
    release) [ $# != 0 ] && nums "$@" || { bad; return; }; f='.held -= ($v | map(tonumber)) | .startSeen = (.startSeen + ($v | map(tonumber)) | unique)' ;;
    order) nums "$@" || { bad; return; }; f='.order = reduce ($v[] | tonumber) as $n ([]; if index($n) then . else . + [$n] end)' ;;
    unpin) [ $# != 0 ] && nums "$@" || { bad; return; }; f='.order -= ($v | map(tonumber))' ;;
    # The dependency guard; with it off, `force` lets one issue be picked while issues it depends on are open.
    dep-guard) [ $# = 1 ] && [[ $1 =~ ^(on|off)$ ]] || { bad; return; }; f='.depGuard = ($v[0] == "on")' ;;
    # Land as: main pushes main to the pack's branch, pr to one pull request (landas(), lib/push.sh).
    land-as) [ $# = 1 ] && [[ $1 =~ ^(main|pr)$ ]] || { bad; return; }; f='.landAs = $v[0]' ;;
    # Merge PR: who merges the pull request of Land as pr (prmergerule(), lib/push.sh).
    pr-merge) [ $# = 1 ] && [[ $1 =~ ^(button|release|idle)$ ]] || { bad; return; }; f='.prMerge = $v[0]' ;;
    # The Board's setup finished: when, and the rules the owner confirmed there (each a rule's key on the Board, as
    # dep-guard); a rule the Board has that this list lacks opens the setup again, at that rule's step.
    onboarded) [ $# -ge 1 ] && [ $# -le 40 ] || { bad; return; }
      for x; do [[ $x =~ ^[a-z][A-Za-z0-9-]{0,39}$ ]] || { bad; return; }; done
      f='.onboarded = {at: (now | todate), rules: reduce $v[] as $k ([]; if index($k) then . else . + [$k] end)}' ;;
    force) [ $# = 1 ] && nums "$@" || { bad; return; }
      [ "$(jq -r .depGuard <<<"$c")" = false ] \
        || { echo "conveyor: the dependency guard is on: #$1 is not built before the issues it depends on; turn the guard off first (control dep-guard off); nothing changed" >&2; return 2; }
      f='.forced = (.forced + ($v | map(tonumber)) | unique)' ;;
    # The run before a push (pushtests(), lib/pushrun.sh), on or off over the pack's push.check.
    push-check) [ $# = 1 ] && [[ $1 =~ ^(on|off)$ ]] || { bad; return; }; f='.pushCheck = ($v[0] == "on")' ;;
    rules) [ $# != 0 ] || { bad; return; }
      # An area rule is the pack's area prefix and a name; push is whether a card that lands is pushed, visible whether
      # a change customers or staff will see needs the owner's yes, lint the rule Lint check (lintgate(), lib/lint.sh),
      # testissues, foremanissues, followupissues, releaseissues and splitissues whether a Tests page action, a Foreman order, a review follow-up, a release fix card or a split part files a GitHub issue for its card (testissue(), cardnew(), lib/testaction.sh); split (Split large issues) and pick (Pick
      # settings) are off, shadow or on, kept as that word.
      packget labels.areaPrefix p || return 1
      for x; do [[ $x =~ ^(P[0-3]|followups|push|visible|lint|testissues|foremanissues|followupissues|releaseissues|splitissues)=(on|off)$ || $x =~ ^(split|pick)=(off|shadow|on)$ ]] || { [[ $x == "$p"* ]] && [[ ${x#"$p"} =~ ^[^=[:space:]]+=(on|off)$ ]]; } || { bad; return; }; done
      f='reduce ($v[] | capture("^(?<k>.*)=(?<o>on|off|shadow)$")) as $r (.; if $r.k | IN("split", "pick") then .rules[$r.k] = $r.o elif $r.k | startswith($p) | not then .rules[$r.k] = ($r.o == "on")
           elif $r.o == "off" then .rules.never = (.rules.never + [$r.k] | unique) else .rules.never -= [$r.k] end)
         | if any($v[]; startswith("pick=")) then .pickBack = null else . end' ;;
    # The owner's decision on a group's trial challenger (modelpick(), lib/modelpick.sh), asked in Needs you after ten
    # trial cards: promote (the group builds on the challenger, 1 card in 5 on the default), keep (the trials go on,
    # and the next ten ask again) or drop (no more trials). When it was taken: the trial cards that ended before it
    # are not asked about again. add (a medium group only, once the owner decided on the small group of its kind after
    # its trial result) makes the group eligible for trials. next (a promoted group only) keeps its promoted cards on
    # that challenger and tries the next one on PICKLADDER (lib/modelpick.sh); then keep goes on with both, promote
    # takes the next one, and drop goes back to the promoted one.
    # A reviewer or judge seat joins the pick only by the owner's promote of a choice that a replay result names (a
    # line of REPLAYS for that seat, model and effort, of one review or more: replay(), lib/replay.sh); drop takes it
    # out, and the seat is the defaults again.
    pick) if [[ ${1:-} =~ ^(reviewer|judge)$ ]]; then
        if [ $# = 2 ] && [ "$2" = drop ]; then f='del(.picks[$v[0]])'
        else [ $# -ge 3 ] && [ $# -le 4 ] && [ "$2" = promote ] || { bad; return; }
          p=$(jq -rs --arg s "$1" --arg m "$3" --arg e "${4:-}" 'map(objects | select(.seat == $s and .model == $m and ($e == "" or .effort == $e) and (.reviews | numbers) > 0))
            | last | .effort // empty' "$REPLAYS" 2>/dev/null)
          # Only the judge has a replay to run (replay(), lib/replay.sh): a reviewer refusal names no command.
          [ -n "$p" ] || { if [ "$1" = judge ]; then x="run conveyor.sh pick replay judge $3${4:+ $4} first"; else x="conveyor.sh has no reviewer replay to run"; fi
            echo "conveyor: no $1 replay result on $3${4:+ at $4} effort: $x; nothing changed" >&2; return 1; }
          f='.picks[$v[0]] = {decision: "promote", at: ((($ENV.CONVEYOR_NOW // "" | tonumber?) // now) | todate), choice: {model: $v[2], effort: $p}}'
        fi
      else [ $# = 3 ] && [[ $1 =~ ^(small|medium)$ ]] && [[ $2 =~ ^(docs|code)$ ]] && [[ $3 =~ ^(promote|keep|drop|add|next)$ ]] || { bad; return; }
        x=$(jq -r --arg g "$1 $2" '.picks[$g].decision // ""' <<<"$c")
        if [ "$3" = add ]; then
          [ "$1" = medium ] && [ -z "$x" ] && jq -e --arg k "small $2" '.picks[$k].decision != null' <<<"$c" >/dev/null \
            || { echo "conveyor: add is for a medium group not yet added, after your decision on the small $2 trial result; nothing changed" >&2; return 1; }
        elif [ "$1" = medium ] && [ -z "$x" ]; then echo "conveyor: medium $2 has no trials: add it first (conveyor.sh control pick medium $2 add); nothing changed" >&2; return 1
        elif [ "$3" = next ]; then
          p=$(jq -c --argjson l "$PICKLADDER" --argjson t "$PICKTRIAL" --arg g "$1 $2" '(.picks[$g].challenger // $t) as $ch
            | ($l | index([$ch])) as $i | select($i != null and $l[$i + 1] != null) | [$ch, $l[$i + 1]]' <<<"$c")
          [ "$x" = promote ] && [ -n "$p" ] || { echo "conveyor: next is for a promoted group whose challenger has a next one; nothing changed" >&2; return 1; }
        fi
        f='.picks[$v[0] + " " + $v[1]] as $r | ((($ENV.CONVEYOR_NOW // "" | tonumber?) // now) | todate) as $t
          | .picks[$v[0] + " " + $v[1]] = (if $v[2] == "next" then ($p | fromjson) as [$o, $nx] | {decision: "next", at: $t, promoted: $o, challenger: $nx}
            elif $v[2] == "keep" then ($r // {}) + {decision: "keep", at: $t}
            elif $v[2] == "drop" and $r.promoted != null then {decision: "promote", at: $t, challenger: $r.promoted}
            else {decision: $v[2], at: $t} + ($r // {} | if .challenger != null then {challenger} else {} end) end)'
      fi ;;
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
    # One issue's own seats (cards, by issue number; percard()): its builder, reviewer or judge set to a model the
    # pack's models.allowed lists for that seat, at an effort its CLI takes (none: the project's); clear takes one seat
    # off, or all of them, so the project's stands again.
    card) [ $# -ge 2 ] && nums "$1" || { bad; return; }
      if [ "$2" = clear ]; then [ $# = 2 ] || { bad; return; }; f='del(.cards[$v[0]])'
      else [[ $2 =~ ^(builder|reviewer|judge)$ ]] && [ $# -ge 3 ] && [ $# -le 4 ] || { bad; return; }
        if [ "$3" = clear ]; then [ $# = 3 ] || { bad; return; }
          f='if .cards[$v[0]] == null then . else del(.cards[$v[0]][$v[1]]) | if .cards[$v[0]] == {} then del(.cards[$v[0]]) else . end end'
        else x=$(cardok "$2" "$3" "${4:-}") || return 1
          [ -z "$x" ] || { echo "conveyor: $x; nothing changed" >&2; return 2; }
          f='.cards[$v[0]][$v[1]] = {model: $v[2]} + (if $v[3] == null then {} else {effort: $v[3]} end)'; fi
      fi ;;
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
    # order they are opened. When the number cannot be read, nothing changes. `start queue filed` is the filing hooks'
    # Queue (foreman/foreman.sh filed, once a filing ends): it first holds every open issue opened in the span it
    # closes that startSeen does not have, a follow-up too, as adopt does with the issues named, so an issue the
    # Foreman filed is held however the command that filed it printed it (no link to it, only its number), and one
    # released already stays released. When the open issues cannot be read, nothing changes either.
    start) { [ $# = 1 ] && [[ $1 =~ ^(queue|held)$ ]]; } || [ "$*" = "queue filed" ] || { bad; return; }
      if [ "$(jq -r .start <<<"$c")" != "$1" ]; then
        top=$(timeout 60 gh issue list --state all --limit 1 --json number 2>/dev/null | jq -e '.[0].number // 0 | numbers') \
          || { echo "conveyor: cannot read the newest issue number; nothing changed" >&2; return 1; }
        [ $# = 1 ] || { names && open=$(openissues number 2>/dev/null | jq -ce 'arrays'); } \
          || { echo "conveyor: cannot read the open issues; nothing changed" >&2; return 1; }
      fi
      f='if .start == $v[0] then . elif $v[0] == "held" then .start = "held" | .startHeld += [{from: $n, to: null}]
         else .start = "queue" | .startHeld[(.startHeld | length) - 1].to = $n end' ;;
    *) bad; return ;;
  esac
  new=$(jq -c --arg a "$a" --arg p "$p" --argjson n "$top" "\$ARGS.positional as \$v | $f" --args "$@" <<<"$c") && [ -n "$new" ] || return 1
  [ -z "$open" ] || { new=$(jq -c --argjson o "$open" '.startHeld[-1] as $s | ([$o[].number | select(. > $s.from and . <= $s.to)] - .startSeen) as $h
    | .held = (.held + $h | unique) | .startSeen = (.startSeen + $h | unique)' <<<"$new") && [ -n "$new" ]; } || return 1
  ctlput "$c" "$new" || return 1
  # A release of an issue the record's held does not list changes nothing there: it is held for another reason, or not
  # held. Say so on stderr (exit 0 stays), so the one who ran it does not take the issue for released.
  if [ "$a" = release ]; then
    for x in $(jq -r '.held as $h | $ARGS.positional[] | select(tonumber | IN($h[]) | not)' --args "$@" <<<"$c"); do
      echo "conveyor: #$x is not held in this record, so nothing changed; foreman status says what holds it" >&2
    done
  fi
  # A release dates only the issues the record held; an adopt, or the filing hooks' Queue, only those it held now.
  case $a in hold) movedlocked movedhold hold "$new" "$@" ;; adopt | start) x=$(jq -r --argjson c "$c" '.held - $c.held | .[]' <<<"$new")
    [ -z "$x" ] || movedlocked movedhold hold "$new" $x ;; release) x=$(jq -r '.held as $h | $ARGS.positional[] | select(tonumber | IN($h[]))' --args "$@" <<<"$c")
    [ -z "$x" ] || movedlocked movedhold release "$new" $x ;; esac
  # A hold, a release and the filing hooks' own actions (adopt, start: foreman/foreman.sh filing and filed) wake the
  # running loop, so it picks from the new record now, not once its turn's timer ends.
  case $a in hold | release | adopt | start) wakeloop ;; esac
  # A resume puts back the cards a sign-in failure blocked, once each (signinback()).
  [ "$a" != resume ] || signinback
  printf '%s\n' "$new"
}
# The wake of the running loop: the process loop.json (SAYS) names, while it is that process, is sent URG, which ends
# its turn's wait at once (run() and turnwait(), lib/run.sh). A loop on an engine before this one ignores URG, as its
# default is. With no loop running, nothing is sent.
wakeloop() {
  local e t
  IFS=$'\t' read -r e t < <(jq -r '[.pid, .started] | @tsv' "$SAYS" 2>/dev/null) && [[ $e =~ ^[1-9][0-9]*$ ]] && p_alive "$e" "$t" \
    && kill -URG "$e" 2>/dev/null
  return 0
}
# Under the lock: a step whose session never began its work because its sign-in failed (nostart(): NOSTART_SIGNIN),
# with no fallback route left, pauses the loop as `control pause` does, so no further card meets the same failure;
# signin holds the reason, the first one while it stands. Cards already started go on. A stopped loop stays stopped.
signinpause() { # <reason>
  local c new; c=$(ctl) || return 1
  new=$(jq -c --arg r "$1" 'if .mode == "stop" then . else .mode = "pause" | .signin //= $r end' <<<"$c") && ctlput "$c" "$new"
}
# Under the lock: the rule Pick settings, On, goes back to shadow by itself (modelpick(), lib/modelpick.sh), with why
# and when in pickBack, the Needs you line; an owner's `control rules pick=...` clears it. A rule not On is left as it is.
pickback() { # <reason>
  local c new; c=$(ctl) || return 1
  new=$(jq -c --arg r "$1" --arg t "$(clock)" 'if .rules.pick != "on" then . else .rules.pick = "shadow" | .pickBack = {at: $t, reason: $r} end' <<<"$c") && ctlput "$c" "$new"
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
# its first sight or after, is never held again; and one opened before the switch keeps its place. Whatever the
# setting, an open issue opened by someone outside the project (its authorAssociation known and not INSIDE, a follow-up
# too) joins held and startSeen the same way, until the owner releases it. pick and snapshot call it with the open issues they read.
adopt() { # <open issues json>
  local c new
  c=$(ctl) && new=$(adopted "$c" "$1") && [ -n "$new" ] || return 1
  ctlput "$c" "$new"
}
# The record with adopt's holds added, saved nowhere: adopt saves it, and `pick --dry` reads it as the record. A
# forced issue (`control force`) leaves forced, and a pinned one (`control order`) leaves order, once a card of it has
# landed or it is no longer open; the card records are read only while forced or order lists one, and a line not whole
# yet (a card writing it) is skipped.
adopted() { # <control record> <open issues json>
  jq -c --argjson c "$1" --arg fu "$FOLLOWUP" --rawfile r <([[ $1 == *'"forced":[]'* && $1 == *'"order":[]'* ]] || recs 2>/dev/null) "$INSIDE"'[.[] | select((.number | IN($c.startSeen[]) | not)
      and (((.labels // [] | any(.name == $fu) | not) and (.number as $i | $c.startHeld | any($i > .from and (.to == null or $i <= .to))))
        or (.authorAssociation | type == "string") and (inside | not))) | .number] as $n
    | map(.number) as $open | [$r | splits("\n") | fromjson? | objects | select(.step == "landed") | .issue] as $landed
    | if $n == [] then $c else $c | .held = (.held + $n | unique) | .startSeen = (.startSeen + $n | unique) end
    | (.forced, .order) |= map(select(IN($open[]) and (IN($landed[]) | not)))' <<<"$2"
}
