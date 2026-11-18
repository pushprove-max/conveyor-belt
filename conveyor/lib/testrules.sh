# SPDX-License-Identifier: Apache-2.0
# The test rules (README.md, Test rules): rules the owner sets in the pack (test.rules) that file an issue about a test
# file, behind one switch (test.rules.on, off by default) and guards. They replace the "Slow test" filing of
# test.slowIssues, which files nothing now.
# A rule: name, on, measure, limit, runs (the runs in a row), minRuns (the least count of runs on record), and days
# (flaky and failed) or minClock (clock). Its measures, of one test file, from the card test lines (times, clocks,
# failures) and the flaky-test record ($FLAKY):
#   usual  CPU seconds over limit times its usual (the median of its runs before those runs), in each of its last runs
#           runs ("slower than its usual");
#   clock   clock seconds over limit times its CPU seconds, with at least minClock clock seconds, in each of its last
#           runs runs;
#   flaky   at least limit entries of the flaky-test record (a case kept off as flaky) in the last days days;
#   failed  at least limit test steps that failed in it in the last days days.
# A rule with the measure budget, which the schema still takes, matches nothing: no file has a CPU budget.
# usual is the CPU rule: a file the pack marks slow on purpose is never filed by it.
# The guards, each a pack setting with a default: perDay (the most issues filed in one day; the rest wait for the next
# day), maxOpen (the most issues of the rules open at one time), one issue a file (no second issue for a file while
# the one last filed for it is open, whichever rule matched; an issue whose state cannot be read counts as open),
# quietDays (no issue for a file in the days after its last one closed), and burst (when one pass matches more files
# than perDay, the pass files nothing and the snapshot puts one line in "Needs you").
# TESTRULES holds the list of the last pass (the snapshot's tests.rules.last): {time, on, matches: [each match, with
# result (filed, would file, stopped or not filed), issue or guard and why], burst: {matched, cap} or null}.
# TESTRULESLOG holds one line for each issue filed and each match a guard stopped: {time, event: filed or stopped,
# rule, measure, file, values, cards} and issue (filed) or guard and why (stopped).
TESTRULES=${STATE%/*}/testrules.json
TESTRULESLOG=${STATE%/*}/testrules.jsonl
# shellcheck disable=SC2034 # read by testspart() in lib/testfiles.sh
TESTRULES_SHOWN=50  # the lines of the log the snapshot holds (testspart(), lib/testfiles.sh), for the Board's Tests page
TESTRULES_CPU='["usual"]'
# A match's measured values in words, for the preview and the issue.
TESTRULES_SAID='def n: if . == floor then tostring else (. * 100 | round / 100 | tostring) end;
  def said: if .measure == "usual" then "\(.values.cpu | length) card test runs in a row at \(.values.cpu | map(n) | join(", ")) CPU s, each over \(.limit | n) times its usual of \(.values.usual | n) CPU s"
    elif .measure == "clock" then "\(.values.sec | length) card test runs in a row at \([.values.sec, .values.cpu] | transpose | map("\(.[0] | n) s clock for \(.[1] | n) CPU s") | join(", ")), each clock time over \(.limit | n) times its CPU seconds"
    elif .measure == "flaky" then "kept off as flaky \(.values.count) times in \(.values.days) days (the limit is \(.limit | n))"
    else "failed in \(.values.count) test steps in \(.values.days) days (the limit is \(.limit | n))" end;'

# The switch, the guards and the rules, as the pack holds them with the schema's defaults: {on, perDay, maxOpen,
# quietDays, burst, list}.
testrulesettings() {
  local on pd mo qd bu ls
  packget test.rules.on on test.rules.perDay pd test.rules.maxOpen mo test.rules.quietDays qd test.rules.burst bu test.rules.list ls || return 1
  jq -cn --arg on "$on" --argjson pd "$pd" --argjson mo "$mo" --argjson qd "$qd" --arg bu "$bu" --argjson ls "$ls" \
    '{on: ($on == "true"), perDay: $pd, maxOpen: $mo, quietDays: $qd, burst: ($bu != "false"), list: $ls}'
}

# What the rules that are on match now (<now>, epoch seconds), in the order of the rules and then of the files:
# [{rule, measure, limit, file, values, cards}]. A file counts its runs from the card test lines that timed it.
testrulesmatches() { # <now> <settings: testrulesettings()>
  local fl defs refs
  jq -e 'any(.list[]; .on == true)' <<<"$2" > /dev/null || { echo '[]'; return 0; }
  fl=$(jq -ce 'objects' "$FLAKY" 2>/dev/null) || fl='{}'
  testowners
  { olds; recs; } 2>/dev/null | { grep -F '"step":"test"' || :; } | jq -cRn --argjson now "$1" --argjson s "$2" \
    --argjson fl "$fl" --argjson defs "$defs" --argjson refs "$refs" "$OWNERS"'
    def median: sort | if length == 0 then null else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 end;
    [inputs | fromjson? | objects | select(.step == "test")] | sort_by(.time) as $ls
    | [$ls[] | select(.result == "fail") | {at: ((.time | fromdate?) // 0), card, files: failedfiles}] as $fails
    | [$fl.entries | arrays | .[] | objects | select(.case | type == "string") | {at: ((.time | fromdate?) // 0), card: (.card // .source), files: (.case | caseowners)}] as $flk
    | (reduce ($ls[] | . as $l | .times | objects | to_entries[] | select(.value | type == "number") | .key as $f
        | {f: $f, r: {cpu: .value, sec: (($l.clocks | objects | .[$f] | numbers) // null), card: $l.card}}) as $x ({}; .[$x.f] += [$x.r])) as $runs
    | ([$runs | keys[]] + [$fails[].files[], $flk[].files[]] | unique) as $all
    | [$s.list[] | select(.on == true and .measure != "budget") | . as $u | ($u.days // 7) as $days
      | $all[] as $f | ($runs[$f] // []) as $r | select(($r | length) >= $u.minRuns) | $r[-$u.runs:] as $last
      | if $u.measure == "usual" then select(($r | length) > $u.runs) | ($r[:-$u.runs] | map(.cpu) | median) as $m
          | select($m > 0 and all($last[]; .cpu > $u.limit * $m))
          | {values: {cpu: [$last[].cpu], usual: ($m * 1000 | round / 1000)}, cards: [$last[].card]}
        elif $u.measure == "clock" then
          select(($last | length) == $u.runs and all($last[]; .sec != null and .cpu > 0 and .sec >= ($u.minClock // 0) and .sec > $u.limit * .cpu))
          | {values: {sec: [$last[].sec], cpu: [$last[].cpu]}, cards: [$last[].card]}
        else [(if $u.measure == "flaky" then $flk else $fails end)[] | select(.at > $now - $days * 86400 and any(.files[]; . == $f))] as $e
          | select(($e | length) > 0 and ($e | length) >= $u.limit)
          | {values: {count: ($e | length), days: $days}, cards: ([$e[].card | strings] | unique)} end
      | {rule: $u.name, measure: $u.measure, limit: $u.limit, file: $f} + .]'
}

# One pass of the rules: what they match, and for each match the guard that stops it, else "would file". After a
# card's test step (card(), settle()), with the switch on, each "would file" is filed, each filing and each stopped
# match logged ($TESTRULESLOG), and the list kept ($TESTRULES); with it off, the list is kept and nothing filed or
# logged. preview (`conveyor.sh testrules preview`) prints the list and writes and files nothing, the switch on or off.
# The state of the issue last filed for each file is asked of GitHub (only when something matches and the switch is
# on): state and closedAt; one not read, or closed with no closedAt, counts as open.
testrulespass() { # [preview]
  local s t m log st='{}' n x r lock='' fs out e
  s=$(testrulesettings) && packget test.files fs || { echo "conveyor: test rules: the pack could not be read; nothing filed" >&2; return 1; }
  if [ "${1:-}" != preview ]; then
    { exec {lock}>>"$TESTRULESLOG.lock"; } 2>/dev/null && flock "$lock" || { echo "conveyor: test rules: the log could not be locked; nothing filed" >&2; return 1; }
  fi
  t=$(clock)
  m=$(testrulesmatches "$(jq -rn --arg t "$t" '$t | fromdate')" "$s") || { [ -z "$lock" ] || exec {lock}>&-; echo "conveyor: test rules: the records could not be read; nothing filed" >&2; return 1; }
  log=$(jq -cRn '[inputs | fromjson? | objects]' "$TESTRULESLOG" 2>/dev/null) || log='[]'
  # With the switch off every match stops at it: no state is asked.
  if [ "$m" != '[]' ] && jq -e '.on' <<<"$s" > /dev/null; then
    while IFS= read -r n; do
      x=$(timeout 20 gh issue view "$n" --json state,closedAt 2>/dev/null | jq -c '{state: (.state // ""), closedAt: (.closedAt // "")}' 2>/dev/null) || x=''
      st=$(jq -c --arg n "$n" --argjson x "${x:-null}" '.[$n] = ($x // {state: "", closedAt: ""})' <<<"$st")
    done < <(jq -r '[.[] | select(.event == "filed" and (.file | type) == "string" and (.issue | type) == "number")] | group_by(.file) | .[] | last.issue' <<<"$log")
  fi
  r=$(jq -c --argjson s "$s" --argjson m "$m" --argjson log "$log" --argjson st "$st" --arg t "$t" --argjson cpu "$TESTRULES_CPU" --argjson fs "$fs" -n '
    def closed: .state == "CLOSED" and ((.closedAt | fromdate?) // null) != null;
    ($t | fromdate) as $now | ($now | strflocaltime("%Y-%m-%d")) as $today
    | [$log[] | select(.event == "filed" and (.file | type) == "string" and (.issue | type) == "number")] as $filed
    | ($filed | group_by(.file) | map({key: .[0].file, value: last.issue}) | from_entries) as $last
    | ([$last[] | $st[tostring] // {state: ""} | select(closed | not)] | length) as $open
    | ([$filed[] | select(((.time | fromdate? | strflocaltime("%Y-%m-%d")) // "") == $today)] | length) as $day
    | def stop($g; $why): . + {result: "stopped", guard: $g, why: $why};
    # The guards of one file: the switch, slow on purpose, one issue a file, and the issue last filed for it.
    (reduce $m[] as $x ({seen: {}, out: []}; $last[$x.file] as $n | ($st[$n | tostring] // {state: "", closedAt: ""}) as $i
      | (if ($s.on | not) then $x | stop("off"; "the switch is off")
         elif IN($x.measure; $cpu[]) and $fs[$x.file].slowOnPurpose != null then $x | stop("slowOnPurpose"; "the file is marked slow on purpose")
         elif .seen[$x.file] != null then $x | stop("oneAFile"; "rule \(.seen[$x.file]) matched the file first in this pass")
         elif $n == null then $x
         elif $i.state == "OPEN" then $x | stop("open"; "#\($n), filed for the file, is open")
         elif ($i | closed | not) then $x | stop("open"; "the state of #\($n), filed for the file, could not be read")
         elif ($i.closedAt | fromdate) > $now - $s.quietDays * 86400 then $x | stop("quietDays"; "#\($n), filed for the file, closed less than \($s.quietDays) days ago")
         else $x end) as $y
      | .out += [$y] | if $y.result == null then .seen[$x.file] = $x.rule else . end) | .out) as $o
    | [$o[] | select(.result == null)] as $c
    | ($s.burst and ($c | length) > $s.perDay) as $burst
    # The guards of the pass: the burst guard, then the day cap and the cap of open issues, in the order of the matches.
    | reduce $o[] as $x ({day: $day, open: $open, out: []};
        if $x.result != null then .out += [$x]
        elif $burst then .out += [$x | stop("burst"; "\($c | length) files matched in one pass, more than the \($s.perDay) a day")]
        elif .day >= $s.perDay then .out += [$x | stop("perDay"; "\(.day) issues filed today, the most in one day is \($s.perDay)")]
        elif .open >= $s.maxOpen then .out += [$x | stop("maxOpen"; "\(.open) issues of the rules are open, the most is \($s.maxOpen)")]
        else .day += 1 | .open += 1 | .out += [$x + {result: "would file"}] end)
    | {time: $t, on: $s.on, matches: .out, burst: (if $burst then {matched: ($c | length), cap: $s.perDay} else null end)}') \
    || { [ -z "$lock" ] || exec {lock}>&-; echo "conveyor: test rules: the guards could not be read; nothing filed" >&2; return 1; }
  if [ "${1:-}" = preview ]; then
    jq -r "$TESTRULES_SAID"'if .matches == [] then "The test rules match no file now." else .matches[]
      | "\(.rule): \(.file): \(said): \(if .result == "would file" then "would file" else "stopped by \(.guard): \(.why)" end)" end' <<<"$r"
    return 0
  fi
  if jq -e '.on' <<<"$r" > /dev/null; then
    names || { exec {lock}>&-; return 1; }
    out='[]'
    while IFS= read -r e; do
      jq -e '.result == "would file"' <<<"$e" > /dev/null && n=$(testrulefile "$e") && e=$(jq -c --argjson n "$n" '.result = "filed" | .issue = $n' <<<"$e") \
        || { jq -e '.result == "would file"' <<<"$e" > /dev/null && e=$(jq -c '.result = "not filed"' <<<"$e"); }
      out=$(jq -c --argjson e "$e" '. + [$e]' <<<"$out")
      jq -c --arg t "$t" 'select(.result == "filed" or .result == "stopped") | {time: $t, event: .result, rule, measure, file, values, cards}
        + if .result == "filed" then {issue} else {guard, why} end' <<<"$e" >> "$TESTRULESLOG"
    done < <(jq -c '.matches[]' <<<"$r")
    r=$(jq -c --argjson o "$out" '.matches = $o' <<<"$r")
  fi
  printf '%s\n' "$r" > "$TESTRULES.new" && mv -f "$TESTRULES.new" "$TESTRULES" || rm -f "$TESTRULES.new"
  exec {lock}>&-
}
# One issue for a match (testrulespass()): it names the rule, the measured values and the cards; its labels are the
# pack's type and last priority. Prints the issue's number; one GitHub did not take is said and not kept.
testrulefile() { # <match>
  local out n
  out=$(gh_write issue create --title "$(jq -r '"Test rule \(.rule): \(.file)"[:200]' <<<"$1")" --label "$TYPE" --label "$(jq -r '.[-1]' <<<"$PRIOS")" \
    --body "$(jq -r "$TESTRULES_SAID"'"The test rule `\(.rule)` (\(.measure)) matched the test file `\(.file)`: \(said).\n\nThe cards of those figures: \(if .cards == [] then "none on record" else .cards | join(", ") end).\n\nConveyor'"'"'s test rules filed this issue. Find why the file matches, and change the file or the rule."' <<<"$1")" 2>&1)
  n=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1); n=${n##*/}
  [ -n "$n" ] || { echo "conveyor: test rule $(jq -r '"\(.rule): \(.file)"' <<<"$1"): its issue could not be filed: $out" >&2; return 1; }
  echo "conveyor: test rule $(jq -r '"\(.rule) matched \(.file)"' <<<"$1"): filed #$n" >&2
  echo "$n"
}

# conveyor.sh testrules: the preview, the switch, the guards and the rules, saved in the pack (packset()). Each refuses
# a bad value, says why and changes nothing:
#   preview                                   what the rules match now and what each match would do; files nothing
#   on | off                                  test.rules.on
#   guard <perDay | maxOpen | quietDays | burst> <value>
#                                             perDay and maxOpen a whole number of at least 1, quietDays of at least 0,
#                                             burst true or false
#   add <name> <measure> <limit> <runs> <minRuns> [<days | minClock>]
#                                             a rule, added off: days for flaky and failed, minClock for clock
#   set <name> <on | measure | limit | runs | minRuns | days | minClock> <value>
#   remove <name>
TESTRULES_USAGE='usage: conveyor.sh testrules preview | on | off | guard <perDay | maxOpen | quietDays | burst> <value> | add <name> <measure> <limit> <runs> <minRuns> [<days | minClock>] | set <name> <on | measure | limit | runs | minRuns | days | minClock> <value> | remove <name>'
testrules() { # <what> [<argument>...]
  local why='' ls k v r='{"on": false}'
  case ${1:-}:$# in
    preview:1) testrulespass preview; return ;;
    on:1 | off:1) packset --argjson v "$([ "$1" = on ] && echo true || echo false)" '.test.rules.on = $v'; return ;;
    guard:3 | add:6 | add:7 | set:4 | remove:2) ;;
    *) echo "$TESTRULES_USAGE" >&2; return 2 ;;
  esac
  packget test.rules.list ls || return 1
  case $1 in
    guard) [[ $2 =~ ^(perDay|maxOpen|quietDays|burst)$ ]] && testrulevalue "$2" "$3" || why=${why:-"the guard is perDay, maxOpen, quietDays or burst, not \"$2\""}
      [ -n "$why" ] || { packset --arg k "$2" --argjson v "$v" '.test.rules[$k] = $v'; return; } ;;
    add) [[ -n ${2//[[:space:]]/} && $2 != *[$'\n\r']* ]] || why="the name is one line that is not blank"
      [ -n "$why" ] || ! jq -e --arg n "$2" 'any(.[]; .name == $n)' <<<"$ls" > /dev/null || why="a rule named \"$2\" is there already"
      for k in measure:3 limit:4 runs:5 minRuns:6; do
        [ -n "$why" ] || testrulevalue "${k%:*}" "${@:${k#*:}:1}"; [ -n "$why" ] || r=$(jq -c --arg k "${k%:*}" --argjson v "$v" '.[$k] = $v' <<<"$r")
      done
      if [ -z "$why" ] && [ $# = 7 ]; then
        case $3 in flaky | failed) k=days ;; clock) k=minClock ;; *) why="a rule of $3 takes no seventh value" ;; esac
        [ -n "$why" ] || testrulevalue "$k" "$7"; [ -n "$why" ] || r=$(jq -c --arg k "$k" --argjson v "$v" '.[$k] = $v' <<<"$r")
      fi
      [ -n "$why" ] || { packset --arg n "$2" --argjson r "$r" '.test.rules.list = (.test.rules.list // []) + [{name: $n} + $r]'; return; } ;;
    set | remove) jq -e --arg n "$2" 'any(.[]; .name == $n)' <<<"$ls" > /dev/null || why="no rule is named \"$2\""
      if [ "$1" = remove ]; then [ -n "$why" ] || { packset --arg n "$2" '.test.rules.list |= map(select(.name != $n))'; return; }
      else
        [ -n "$why" ] || testrulevalue "$3" "$4"
        [ -n "$why" ] || { packset --arg n "$2" --arg k "$3" --argjson v "$v" '.test.rules.list |= map(if .name == $n then .[$k] = $v else . end)'; return; }
      fi ;;
  esac
  echo "conveyor: testrules $1: $why; nothing changed" >&2; return 1
}
# A value of a rule or a guard (testrules()) as JSON, in the caller's v, or why it is not one, in the caller's why.
testrulevalue() { # <key> <value>
  case $1 in
    on | burst) [[ $2 =~ ^(true|false)$ ]] && v=$2 || why="$1 is true or false, not \"$2\"" ;;
    measure) [[ $2 =~ ^(usual|clock|flaky|failed)$ ]] && v="\"$2\"" || why="the measure is usual, clock, flaky or failed, not \"$2\"" ;;
    limit | minClock) [[ $2 =~ ^[0-9]{1,6}(\.[0-9]{1,3})?$ ]] && v=$2 || why="$1 is a number of at least 0 (such as 1 or 1.5), not \"$2\"" ;;
    runs | perDay | maxOpen | days) [[ $2 =~ ^[1-9][0-9]{0,5}$ ]] && v=$2 || why="$1 is a whole number of at least 1, not \"$2\"" ;;
    minRuns | quietDays) [[ $2 =~ ^[0-9]{1,6}$ ]] && v=$2 || why="$1 is a whole number of at least 0, not \"$2\"" ;;
    *) why="\"$1\" is not a setting of a rule" ;;
  esac
}
