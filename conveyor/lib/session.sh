# SPDX-License-Identifier: Apache-2.0
# The brief is generated: the fixed header, the issue, the card's record, and the rulings naming the issue's areas,
# from the ruling log the pack names (rulings.log; ~/ is the user's home); a pack that names none gives no rulings.
# The brief's issue part, up to its card record (card() puts a main-red fix card's grown entry in its place).
issuepart() { # <issue json>
  jq -r '"# Issue #\(.number): \(.title)\n\n\(.body)\n\n# Card record"' <<<"$1"
}
brief() { # <card> <issue json> <header>
  local log
  packget rulings.log log || return 1
  [[ $log != "~/"* ]] || log=$HOME/${log#"~/"}
  printf 'Conveyor card %s. %s\n\n' "$1" "$3"
  issuepart "$2" || return 1
  stdb ask card "$1" || return 1
  [ -n "$log" ] || return 0
  printf '\n# Decision records for this area\n'
  jq -cR --argjson a "$(jq -c --arg p "$AREA" '[.labels[].name | select(startswith($p)) | ltrimstr($p)]' <<<"$2")" \
    'fromjson | select(.void != true) | select(((.question // "") + " " + (.answer // "")) as $t | $a | any(. as $w | $t | test("\\b" + $w + "\\b"; "i")))
     | {id, question: ((.question // "")[0:200]), answer: ((.answer // "")[0:400])}' "$log" | tail -n 20
  # The newest 20, each cut short: a common area word matched 701 rulings (2 MB) and the review refused the brief.
}

# The logs a test run wrote to the folder CONVEYOR_TEST_LOG names (tests() below): a test command may write its
# progress lines there, a file per runner, in place of its own output.
testlogs() { # <worktree>
  find "$1.testlog" -maxdepth 1 -type f 2>/dev/null | sort
}
# The cases of a test run that are running now: a runner may keep, in the folder `cases` of that folder, an empty file
# named after each case from when the case starts until it ends. Each as {name, since: when its file was written}; the
# live record of the test step holds them (cases), so `health` names a case that has run past CASE_STUCK while the
# others still print.
testcases() { # <worktree>; prints a JSON array
  local fs=() ts
  mapfile -t fs < <(find "$1.testlog/cases" -maxdepth 1 -type f 2>/dev/null | sort)
  [ ${#fs[@]} -gt 0 ] || { echo '[]'; return; }
  # A case that ended between the two readings has no line here: it is left out, by its name, and the others stay
  # (the reading fails then, and what it read is used all the same).
  ts=$(p_mtimes "${fs[@]}") || :
  jq -cRn '[inputs | capture("^(?<t>[0-9]+) .*/(?<name>[^/]+)$") | {name, since: (.t | tonumber | todate)}]' <<<"$ts" 2>/dev/null || echo '[]'
}
# The cases of a test run that have ended: a runner may name each, as it ends, by an empty file in cases/ok (it
# passed) or cases/failed of that folder.
testdone() { # <worktree>; prints {done, failed}
  local ok bad
  ok=$(find "$1.testlog/cases/ok" -maxdepth 1 -type f 2>/dev/null | wc -l); bad=$(find "$1.testlog/cases/failed" -maxdepth 1 -type f 2>/dev/null | wc -l)
  printf '{"done":%d,"failed":%d}\n' $((ok + bad)) $((bad))
}
# The files of a test run so far, as watch() counts them below: {run, of, cases}, from its output and the logs it wrote.
testprogress() { # <output file> [log...]
  local f=$1; shift
  cat "$f" "$@" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk -v own="$(wc -l < "$f" 2>/dev/null || echo 0)" -v logs="$#" '
    /^test-changed: [0-9]+ web test file\(s\) selected/ { of += $2; seen = 1; next }
    NR <= own && logs > 0 { next }
    /^-- (ok|FAIL) / || /^ (✓|❯|×|↓) [^ ]+ \([0-9]+ tests?[ |)]/ { run++ }
    /^TESTRUN files=[0-9]+/ { sub(/^TESTRUN files=/, ""); of += $1; seen = 1 }
    /^TESTRUN cases=[0-9]+/ { sub(/^TESTRUN cases=/, ""); cof += $1; cseen = 1 }
    END { printf "{\"run\":%d,\"of\":%s,\"cases\":%s}\n", run, (seen ? of + 0 : "null"), (cseen ? cof + 0 : "null") }'
}

# Waits for a running step and keeps its live record (README.md) while it runs; returns the step's exit. Only
# the whole lines the output file has gained since the last look are read, so a long session costs no more each
# time. A session's tokens are those of each answer of the model, counted once (an answer is several events with one
# id, the same usage on each); its output tokens are reported in full only when the session ends, so the reading
# runs a little low. A test run is counted whole each time, from its output and the logs it wrote (testlogs): files
# selected are the `TESTRUN files=N` lines and the web half's `N web test file(s) selected`, files run the
# `-- ok|FAIL <file>` lines and vitest's line a file. A runner that also prints its log's lines is counted once.
# Its cases (tests: {done, of, failed}) are counted only when a line `TESTRUN cases=N` says how many were selected
# (several add up), else tests is null: done and failed are the cases its runner named as ended (testdone()).
# A test run's `progress` (which health reads beside `last`, so the Foreman calls no running test step stuck while it
# moves) is when the run began, then when a case of its runner last began or ended (testcases(), testdone()); its
# `list` is the list of tests the command was given (<worktree>.testlist, tests()).
# A review's tokens are not in its stream before its turn ends: Codex writes the running total (`token_count`) to the
# session file it keeps under its home, named after the thread the stream opens with. rollout() finds that file.
rollout() { # <a review's events file>; prints the session file of that review, nothing when there is none yet
  local id
  id=$(grep -m 1 '"thread.started"' "$1" 2>/dev/null | jq -r '.thread_id // empty' 2>/dev/null) && [[ $id =~ ^[0-9A-Za-z-]+$ ]] || return 0
  find "${CODEX_HOME:-$HOME/.codex}/sessions" -type f -name "rollout-*-$id.jsonl" 2>/dev/null | head -n 1
}
# A build, fix, rebase or review that makes no progress for STUCK seconds is ended: no new output line (its live
# record's `last`), no file of its worktree changed and no new commit there (holds(), asked only once the output has
# been quiet that long, so a session's files cost nothing while it talks). Output is a whole new line, and of a Codex
# review's session file a new token count read from it: bytes with no newline (a spinner, a line cut short) move the
# file's size and are no progress. The output is read first each time, so a line
# that came since the last look counts; and the clock runs from when the files last changed, not from when that was
# seen, so a change made while the session still talked gives it no second wait. Its exit is then the ended
# process's, and <worktree>.stalled holds when its progress stopped; a step that begins with that file there is the
# one run after such a stall, and its live record says so (stalled: that time).
# A file's change time counts beside its modification time: a write that keeps the old modification time (`cp -p`,
# a restore from an archive) moves neither that nor its folder's, and the change time is the one no write can set.
holds() { # <worktree>: when it last changed, epoch seconds: the newest of its files and folders, ignored ones too, and of its HEAD
  local g
  g=$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null) || g=''
  { find "$1" ${g:+"$g/HEAD" "$g/logs/HEAD"} -printf '%T@\n%C@\n' 2>/dev/null; git -C "$1" log -1 --format=%ct 2>/dev/null; } \
    | awk -v n="$EPOCHSECONDS" '{t = int($1)} t <= n && t > m {m = t} END {print m + 0}' # a time after now is a wrong clock, not progress
}
watch() { # <pid> <output file> <live file> <step> [the model it runs on] [the program that runs it: codex for a Codex build, fix or rebase]
  local pid=$1 f=$2 out=$3 st new who rc=0 timer n have=0 size=0 now logs roll='' rsize=0 wt=${3%.live} was='' seen=$EPOCHSECONDS at lines=0 rhave=0 rn cs dn cx=false wn
  [ "${6:-}" != codex ] || cx=true
  # rm only when there is a file to remove (#532: most steps have none).
  [ "$4" = test ] || { [ ! -e "$wt.stalled" ] && [ ! -L "$wt.stalled" ]; } || { [ ! -s "$wt.stalled" ] || was=$(<"$wt.stalled"); rm -f "$wt.stalled"; }
  st=$(jq -cn --arg s "$4" --arg m "${5:-}" --arg w "$was" --slurpfile tl <([ "$4" != test ] || cat "$wt.testlist" 2>/dev/null) '{step: $s, at: (now | todate), last: null, turns: 0}
      + (if $s == "test" then {progress: (now | todate), files: {run: 0, of: null}, tests: null} + (if $tl[0] | type == "object" then {list: $tl[0]} else {} end) else {} end)
      + (if $m == "" then {} else {model: $m} end) + (if $w == "" then {} else {stalled: $w} end)') \
    && printf '%s\n' "$st" > "$out"
  while :; do
    sleep "$LIVE" > /dev/null 8>&- & timer=$!
    who=''; wait -n -p who "$pid" "$timer"; rc=$?
    kill "$timer" 2>/dev/null; wait "$timer" 2>/dev/null
    [ "$who" != "$pid" ] || break
    # A step that ended before that wait began is not among the jobs a bash before 5.3 waits for there: it would
    # name the timer every time and the card would never end. Its exit is asked for by itself.
    kill -0 "$pid" 2>/dev/null || { wait "$pid"; rc=$?; break; }
    [ -n "$who" ] || break
    # A card that gave way (giveway()): once a card took its turn, the live record names it (gaveWay: its issue).
    new=$(jq -c --argjson st "$st" 'select(.away == true and (.to | type) == "number" and .to != $st.gaveWay) | $st + {gaveWay: .to}' "${out%.live}.claim" 2>/dev/null) \
      && [ -n "$new" ] && st=$new && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"
    if [ "$4" = test ]; then
      mapfile -t logs < <(testlogs "${f%.test}")
      now=$(p_stat "$f" "${logs[@]}" | awk '{s = s "," $1; if ($2 > t) t = $2} END {if (NR) print s " " t}')
      cs=$(testcases "${f%.test}"); dn=$(testdone "${f%.test}")
      [ -n "$now" ] && [ "${now% *} $cs $dn" != "$size" ] || continue
      # A case that began or ended (its runner's cases folder) is progress, though nothing was printed.
      [ "$cs $dn" = "${size#* }" ] || st=$(jq -c '.progress = (now | todate)' <<<"$st")
      size="${now% *} $cs $dn"
      new=$(testprogress "$f" "${logs[@]}" \
        | jq -c --argjson st "$st" --argjson t "${now##* }" --argjson cs "$cs" --argjson dn "$dn" '$st + {files: {run, of},
            tests: (.cases as $n | if $n == null then null else {done: $dn.done, of: $n, failed: $dn.failed} end), last: ($t | todate), cases: $cs}' 2>/dev/null) \
        && [ -n "$new" ] && st=$new && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"
      # A run given TEST_GIVEN test files (the rule Whole suite in a card off: tests(), bugrun()) that reports far
      # more, over ten for each (the files it says it selected, or those it ran), is stopped: <worktree>.wide holds
      # that count.
      if [ -n "${TEST_GIVEN:-}" ] && [ ! -e "$wt.wide" ] && wn=$(jq -r '[.files.run, .files.of // 0] | max' <<<"$st" 2>/dev/null) \
        && [[ $wn =~ ^[0-9]+$ ]] && [ "$wn" -gt $((TEST_GIVEN * 10)) ]; then
        echo "$wn" > "$wt.wide"; kill "$pid" 2>/dev/null
      fi
      continue
    fi
    # A Codex review's, or a Codex session's: its running total, from the session file Codex keeps.
    if [ "$4" = review ] || [ $cx = true ]; then
      [ -n "$roll" ] || roll=$(rollout "$f")
      if [ -n "$roll" ] && now=$(p_stat "$roll") && [ "${now% *}" != "$rsize" ]; then
        rsize=${now% *}; rn=$(grep -c '"token_count"' "$roll")
        new=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c --argjson st "$st" --argjson t "${now#* }" '.payload.info.total_token_usage | select(type == "object")
            | {input: ((.input_tokens // 0) - (.cached_input_tokens // 0)), read: (.cached_input_tokens // 0), output: (.output_tokens // 0)} as $u
            | $st + {usage: (if $st.step == "review" then $u else {input: $u.input, write: 0, write1h: 0, read: $u.read, output: $u.output} end),
                     last: ([($t | todate), ($st.last // "")] | max)}' 2>/dev/null) \
          && [ -n "$new" ] && st=$new && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out" \
          && [ "$rn" -gt "$rhave" ] && rhave=$rn && seen=$EPOCHSECONDS
      fi
    fi
    if now=$(p_stat "$f") && [ "${now% *}" != "$size" ]; then
      size=${now% *}; n=$(wc -l < "$f"); [ "$n" -le "$lines" ] || { lines=$n; seen=$EPOCHSECONDS; }
      new=$(tail -n +$((have + 1)) "$f" | head -n $((n - have)) | jq -cRn --argjson st "$st" --argjson t "${now#* }" --argjson cx "$cx" '
        def use: (.cache_creation.ephemeral_1h_input_tokens // 0) as $h | {input: (.input_tokens // 0), write: ((.cache_creation_input_tokens // 0) - $h),
          write1h: $h, read: (.cache_read_input_tokens // 0), output: (.output_tokens // 0)};
        def plus($b): with_entries(.value += ($b[.key] // 0));
        def short: tostring | gsub("\\s+"; " ") | .[0:80];
        # What the step is doing now: the tool a session called last, with what it names, or that it writes or
        # thinks; the item a review started last (a command with its text).
        def act: [.content | arrays | .[] | objects
          | if .type == "tool_use" then (.name // "a tool" | tostring) + ((.input // {} | objects | .command // .file_path // .pattern // .description // .url // null)
              | if . == null then "" else ": " + short end)
            elif .type == "text" then "writing" elif .type == "thinking" then "thinking" else empty end] | last;
        def item: if .type == "command_execution" then "command: " + (.command // "" | short) else (.type // "working" | tostring | gsub("_"; " ")) end;
        # An OpenCode session (opencoderead.jq) or review (OCREVIEWREAD): a step_finish is one call of the model, its tokens and cost; a
        # tool_use is a call that ended, named as a Claude tool call is. A step that reports no cost leaves cost out
        # from then on (ocost false), never guessed.
        def ocuse: .tokens | {input: (.input // 0), write: (.cache.write? // 0), write1h: 0, read: (.cache.read? // 0), output: ((.output // 0) + (.reasoning // 0))};
        def ocact: (.tool // "a tool" | tostring) + ((.state.input? // {} | objects | .command // .filePath // .pattern // .description // .url // null)
          | if . == null then "" else ": " + short end);
        # A line with nothing in it is no output: a session that stalls may still be sent such lines, and stays silent.
        [inputs] as $ls | reduce $ls[] as $l ($st;
          ($l | fromjson? // null) as $e
            # An OpenCode build or review: read first, so the events of a review never reach the reading of a Codex review.
            | if (.model // "" | startswith("opencode:")) then
                if $e.type == "step_finish" and ($e.part.tokens | type) == "object" then
                  .turns += 1 | ($e.part | ocuse) as $u
                  | .usage = ((.usage // {input: 0, write: 0, write1h: 0, read: 0, output: 0}) | del(.cost) | plus($u))
                  | .ocost = (if .ocost == false or ($e.part.cost | type) != "number" then false else (.ocost // 0) + $e.part.cost end)
                  | if .ocost == false then . else .usage.cost = .ocost end
                elif $e.type == "tool_use" and ($e.part | type) == "object" then .action = ($e.part | ocact)
                elif $e.type == "text" then .action = "writing" elif $e.type == "reasoning" then .action = "thinking" else . end
            # A Claude review streams as a session does: its answers are read as a session'"'"'s.
              elif .step == "review" and $e.type != "assistant" then
                (if $e.type == "item.completed" then .turns += 1 else . end)
                | if $e.type == "item.started" and ($e.item | type) == "object" then .action = ($e.item | item) else . end
              # A Codex session (codexread.jq): each item it completed is a turn (not the notices Codex gives as
              # error items), the item it started last is the action, and a completed turn holds its usage.
              elif $cx then
                if $e.type == "item.completed" and ($e.item | type) == "object" and $e.item.type != "error" then
                  .turns += 1 | if $e.item.type == "agent_message" then .action = "writing" elif $e.item.type == "reasoning" then .action = "thinking" else . end
                elif $e.type == "item.started" and ($e.item | type) == "object" then .action = ($e.item | item)
                elif $e.type == "turn.completed" and ($e.usage | type) == "object" then
                  .usage = ($e.usage | {input: ((.input_tokens // 0) - (.cached_input_tokens // 0)), write: 0, write1h: 0, read: (.cached_input_tokens // 0), output: (.output_tokens // 0)})
                else . end
              elif $e.type == "assistant" and ($e.message | type) == "object" and ($e.message | act) != null and ($e.message.usage | type) != "object" then .action = ($e.message | act)
              elif $e.type == "assistant" and ($e.message.usage | type) == "object" and ($e.message.id | type) == "string" then
                (if .id == $e.message.id then . else (.cur // {}) as $c | .done = ((.done // {input: 0, write: 0, write1h: 0, read: 0, output: 0}) | plus($c)) | .turns += 1 end)
                | .id = $e.message.id | .cur = ($e.message.usage | use) | .cur as $c | .usage = (.done | plus($c))
                | (($e.message | act) // .action) as $a | if $a == null then . else .action = $a end
              else . end) | if any($ls[]; test("\\S")) then .last = ([($t | todate), (.last // "")] | max) else . end' 2>/dev/null) && [ -n "$new" ] && st=$new && have=$n && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"
    fi
    [ $((EPOCHSECONDS - seen)) -ge "$STUCK" ] || continue
    at=$(holds "$wt")
    if [ "$at" -gt "$seen" ]; then
      seen=$at
      new=$(jq -c --argjson t "$seen" '.progress = ($t | todate)' <<<"$st") && st=$new && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"
    fi
    [ $((EPOCHSECONDS - seen)) -ge "$STUCK" ] || continue
    jq -rn --argjson s "$seen" '$s | todate' > "$wt.stalled"; kill "$pid" 2>/dev/null; wait "$pid"; rc=$?; break
  done
  rm -f "$out" "$out.tmp"; return $rc
}

# What a session's output (stream-json, one event a line) says of it, as the fields of its line, and ok:
# whether its last result says it succeeded. Always one object: a usage that cannot be read leaves tokens and usage
# out and says why (unread), a stat that cannot be read is null, and the card goes on either way.
# A session can hold more than one result: a task notification after the first result starts a second turn, and
# each turn ends with a result of its own whose usage, num_turns and permission_denials are that turn's (card 3876's
# fix session: two results, which printed two objects where one was read, and the line could not be written). So
# usages, turns and refusals add up over the results; answers after the last result (a turn a timeout cut off) are
# added from the answers themselves, each answer once (the usage of its last event). modelUsage and duration_api_ms
# are the session's totals so far: the last result's and the largest are taken.
SESSIONREAD=$(<"$HERE/jq/sessionread.jq")
# An OpenCode session's output (`opencode run --format json`) gives the same fields (opencoderead.jq), and a Codex
# session's (`codex exec --json`) too (codexread.jq).
OPENCODEREAD=$(<"$HERE/jq/opencoderead.jq")
CODEXREAD=$(<"$HERE/jq/codexread.jq")
# What a Codex review's events say of it: its tokens and split (the turns completed, else $run, the running
# total its session file held), and its turns and tool calls by kind (the items that are not a message or
# reasoning). Nothing when no usage is there.
REVIEWREAD='[inputs | fromjson? // empty] as $all
  | ([$all[] | select(.type == "item.completed") | .item.type // "item"]) as $it
  | ($all | map(select(.type == "turn.completed") | .usage | objects)) as $t
  | (if ($t | length) > 0 then $t elif $run != null then [$run] else [] end)
  | {input: (map((.input_tokens // 0) - (.cached_input_tokens // 0)) | add), read: (map(.cached_input_tokens // 0) | add), output: (map(.output_tokens // 0) | add)}
  | select(.input != null) | {tokens: {codex: (.input + .output)}, usage: ., model: $m, effort: $e, sec: $s,
    stats: {turns: ($t | length), tools: ($it | map(select(IN("agent_message", "reasoning", "item") | not)) | group_by(.) | map({key: .[0], value: length}) | from_entries)}}'
# What an OpenCode run's events (opencode run --format json) say of it, always one object: the usage each step reports
# when it ends (step_finish: input, output, reasoning, cache read and write, each apart from the others, and cost, the
# dollars OpenCode prices them at), summed. usage is {input, write, read, output, cost}, reasoning counted as output, as
# OpenCode prices it, and cost where the Board prices an OpenCode step from (usage.cost), as an OpenCode build's is;
# tokens.codex (the review's count, whichever program runs it: inforce()) is input, cache writes and
# output, as a Claude review's leaves out the cache reads. cost is left out unless every step reports one; a usage that
# no step reports, or that a step reports only in part, is left out and unread says why. stats: its steps (turns) and
# its tool calls by tool.
OCREVIEWREAD='[inputs | fromjson? // empty | objects] as $all
  | [$all[] | select(.type == "step_finish") | .part] as $t
  | ($t | all((.tokens | type) == "object" and ([.tokens.input, .tokens.output, .tokens.reasoning, .tokens.cache.read?, .tokens.cache.write?] | all(type == "number")))) as $whole
  | {model: $m, effort: $e, sec: $s}
    + (if ($t | length) == 0 then {unread: (if ($all | length) == 0 then "the OpenCode output holds no event" else "the OpenCode output holds no token usage" end)}
       elif $whole | not then {unread: "a step of the OpenCode output reports no whole token usage"}
       else {input: ($t | map(.tokens.input) | add), write: ($t | map(.tokens.cache.write) | add), read: ($t | map(.tokens.cache.read) | add),
           output: ($t | map(.tokens.output + .tokens.reasoning) | add)} as $u
         | {tokens: {codex: ($u.input + $u.write + $u.output)},
            usage: ($u + (if all($t[]; .cost | type == "number") then {cost: ($t | map(.cost) | add)} else {} end))} end)
    + {stats: {turns: ($t | length), tools: ([$all[] | select(.type == "tool_use") | .part.tool | strings] | group_by(.) | map({key: .[0], value: length}) | from_entries)}}'
# The answer of an OpenCode run: the text it wrote in the last of its steps that wrote any (a step's text parts, in
# order), ending in one newline (verdict() reads the last line).
OPENCODEANSWER='[inputs | fromjson? // empty | objects | select(.type == "step_start" or .type == "text")]
  | reduce .[] as $e ([]; if $e.type == "step_start" or length == 0 then . + [[]] else . end
      | if $e.type == "text" then .[-1] += [$e.part.text | strings] else . end)
  | map(select(length > 0)) | last // [] | join("\n") | sub("\\s+$"; "") | select(. != "")'
# A card that `control stop` ended with a session or review running: what that one used so far is written as
# a line of its step, result stopped (its model the one the live file names, its seconds from its start line), so
# it is priced and counted when the card's lines move to the retried file. Called by the loop before the worktree
# goes; a line that cannot be written is said, and the stop goes on.
stopped() { # <card> <issue>
  local wt=$CARDS/$1 last of o f m e s x roll run='' ft=$CARDS/$1.firsttry
  last=$(stdb ask last "$1" 2>/dev/null)
  [ "$(jq -r '.step' <<<"${last:-null}" 2>/dev/null)" = start ] || return 0
  of=$(jq -r .of <<<"$last"); m=$(jq -r '.model // ""' "$wt.live" 2>/dev/null); e=''
  s=$(jq -r '(now - (.time | fromdate)) | floor' <<<"$last" 2>/dev/null) || s=0
  # Stopped in the pause before a review ran again (no live file then), or before its second attempt wrote anything:
  # the first attempt (below) is all it used, on its model. While it is still .firsttry.new, the events are the first
  # attempt's own, stopped before reviewed() dropped them: read once, from it. Never told apart by file times, which
  # can be equal.
  [ ! -s "$wt.firsttry.new" ] || ft=$wt.firsttry.new
  if [ "$of" = review ] && [ -s "$ft" ] && { [ ! -s "$wt.events" ] || [ "$ft" = "$wt.firsttry.new" ]; }; then
    [ -n "$m" ] || m=$(jq -r '.spent.model // ""' "$ft" 2>/dev/null); f=$(jq -cn --argjson s "${s:-0}" --arg m "$m" '{tokens: {}, usage: {}, model: $m, sec: $s}')
  # A Codex build, fix or rebase: its output opens as Codex's does. Its usage is its session file's running total.
  elif [ "$of" != review ] && head -n 1 "$wt.out" 2>/dev/null | grep -q '"thread.started"'; then
    roll=$(rollout "$wt.out"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); rm -f "$roll"; }
    f=$(jq -cRn --arg m "$m" --arg e "" --argjson s "${s:-0}" --argjson run "${run:-null}" "$CODEXREAD" "$wt.out" 2>/dev/null | tail -n 1 | jq -c 'del(.ok) | del(.effort)' 2>/dev/null)
  else case $of:$m in
    build:opencode:* | fix:opencode:* | rebase:opencode:*) [ -s "$wt.out" ] || return 0
      f=$(jq -cRn --arg m "$m" --argjson s "${s:-0}" "$OPENCODEREAD" "$wt.out" 2>/dev/null | tail -n 1 | jq -c 'del(.ok)' 2>/dev/null) ;;
    # A Claude review is read as a session is, from its events.
    build:* | fix:* | rebase:* | review:claude-*) o=$wt.out; [ "$of" != review ] || o=$wt.events; [ -s "$o" ] || return 0
      f=$(jq -cRn --arg m "$m" --arg e "$e" --argjson s "${s:-0}" "$SESSIONREAD" "$o" 2>/dev/null | tail -n 1 | jq -c 'del(.ok) | del(.effort)' 2>/dev/null) ;;
    review:opencode:*) [ -s "$wt.events" ] || return 0
      f=$(jq -cRn --arg m "$m" --arg e "$e" --argjson s "${s:-0}" "$OCREVIEWREAD" "$wt.events" 2>/dev/null | tail -n 1 | jq -c 'del(.effort)' 2>/dev/null) ;;
    review:*) [ -s "$wt.events" ] || return 0
      # A review stopped before its turn completed has no usage in its events: its running total is the one its
      # session file holds (as review() reads it), else the last one the live file was given from it.
      roll=$(rollout "$wt.events"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); rm -f "$roll"; }
      [ -n "$run" ] || run=$(jq -c '.usage | objects | select((.input | type) == "number" and (.output | type) == "number")
          | {input_tokens: (.input + (.read // 0)), cached_input_tokens: (.read // 0), output_tokens: .output}' "$wt.live" 2>/dev/null)
      f=$(jq -cRn --arg m "$m" --arg e "$e" --argjson s "${s:-0}" --argjson run "${run:-null}" "$REVIEWREAD" "$wt.events" 2>/dev/null | tail -n 1 | jq -c 'del(.effort)' 2>/dev/null) ;;
    *) return 0 ;;
  esac; fi
  [ -n "$f" ] || f=$(jq -cn --argjson s "${s:-0}" '{sec: $s, unread: "the output of the stopped session could not be read"}')
  [ -n "$m" ] || f=$(jq -c 'del(.model)' <<<"$f")
  # Stopped while a review ran again: the failed first attempt (reviewed()) is on the line, its tokens counted.
  [ "$of" != review ] || ! x=$(jq -ce objects "$ft" 2>/dev/null) || f=$(jq -c --argjson f "$x" "$BOTHTRIES" <<<"$f")
  f=$(line "$1" "$2" "$of" stopped "$(jq -c '. + {reason: "stopped by control stop while it ran"}' <<<"$f")") && locked append "$f" \
    || echo "conveyor: card $1 was stopped, but what its $of used could not be written to the card records" >&2
}
# One headless session with the safety hooks only and no subagents; model and effort are read at each launch
# (seat(): the control record's).
# Output goes to a file, not a pipe, so a killed session's children cannot hold the loop: the session's events, one
# JSON object a line as they come, the last of them its result. Prints the step's record fields: its fresh tokens,
# the split the dashboard prices (cache writes apart by lifetime, cache reads), and the model and effort it ran on.
# An API-side error that is not about the card (a Cloudflare 403 challenge, 429, 5xx, overloaded, connection reset)
# is no card failure: four cards blocked within three minutes of one Cloudflare outage, and the same host's sessions
# worked minutes later. APIERROR reads it from a session's output: the name of the error its last result ends with,
# nothing when that result is anything else (an overloaded or a connection-reset result is one with or without the
# words "API Error" before it); a session that ended with no result at all said it on stderr, if anywhere, so there it
# is read from what the session wrote there ($e). A Codex review says it in its stream's last error or turn.failed
# event, the status there after the word "status" when Codex names it its own way, or, when its stream names no such
# error, in the last line of what it wrote to stderr. The same session, a build's, a fix's or a review's
# (Claude's or Codex's), then runs again
# after 1, 2, 4 and 8 times API_PAUSE (the live record says so meanwhile), and only a fifth such result fails it, naming
# the error. What the refused tries used is added to the step's tokens, usage and seconds. Each such error is marked
# (APIERR: the time until which it is fresh): while it is fresh the loop picks no card (run()) and no card starts a
# session, a Codex review among them (apihold()), so one outage does not burn through the queue.
# APISAID: the words a failed session's output ends with ($codex: whether it is Codex's, a review's or a build's). A Claude session's are
# its error result. Codex's are its error event, or a line that is no JSON at all: Codex can say
# "API Error: 429" in plain words, and that is an error as an event is. Only Codex's words name a status after the
# word "status": a Claude session's result is the card's own words too, and "expected status 500, got 200" is a failed
# test, not an outage.
APISAID='([inputs | select(test("\\S")) | (fromjson? // {type: "plain", message: .}) | objects
    | select(.type | if $codex then IN("error", "turn.failed", "plain") else . == "result" end)] | last) as $r
  | if $r == null then (if $codex then empty else $e end) elif $r.type == "result" then $r | select(.is_error == true) | .result
    elif $r.type == "turn.failed" then $r.error.message else $r.message end | strings'
APIERROR=$APISAID'
  | if test("API Error\\W{1,3}403\\b") then (if test("cloudflare|attention required"; "i") then "403 Cloudflare" else empty end)
    else ((capture("(API Error" + (if $codex then "|\\bstatus" else "" end) + ")\\W{1,3}(?<c>429|5[0-9][0-9])\\b") | .c)
      // (if test("overloaded"; "i") then "overloaded" elif test("ECONNRESET|connection (reset|error)|socket hang up"; "i") then "connection reset" else empty end)) end'
APIERR=${STATE%/*}/apierror
apifresh() { [ -e "$APIERR" ] && jq -en --slurpfile u "$APIERR" '($u[0] | numbers) > now' >/dev/null 2>&1; }
# A step's fields with those of the tries the API refused before it ($p) folded in. As with a review's two attempts
# (BOTHTRIES): when a refused try's usage is unknown or only part of it, or it ran on another model, unread says so,
# so the step is unpriced, never underpriced. An OpenCode cost (usage.cost) is the sum when both report one, else left out.
APIFOLD='def add2(a; b): [a, b] | map(. // {} | to_entries[]) | reduce .[] as $e ({}; .[$e.key] += $e.value);
  .sec += $p.sec | (if .tokens != null or $p.tokens != null then .tokens = add2(.tokens; $p.tokens) else . end)
  | if $p.model != null and $p.model != .model then .unread //= "a try the model API refused ran on another model (\($p.model)): one model cannot price both"
    elif (.usage | type) == "object" and ($p.usage | type) == "object" then
      .usage.cost as $c | .usage = (add2(.usage; $p.usage) | if [$c, $p.usage.cost] | all(type == "number") then . else del(.cost) end)
      | if $p.unread then .unread //= $p.unread else . end
    else .unread //= ($p.unread // "the token usage of a try the model API refused could not be read") end'
# One session, a build's or a review's (<command ...>: it prints and fails as session1() does, its output in
# <output file>, what a failed one used in <worktree>.spent), run again while the API refuses it, as said above.
# apihold: a card picked before the error starts no session, Claude's or Codex's, while it is fresh either: it waits
# here, its live record saying so, with no output of an earlier step left for stopped() to read as this one's.
apihold() { # <worktree> <step> <output file>
  local at
  while apifresh; do
    rm -f "$3"; at=$(jq -r floor "$APIERR" 2>/dev/null) || break
    jq -cn --arg s "$2" --arg a "waiting: the model API refused a session; starting at $(p_date "@$at" +%H:%M)" \
      '{step: $s, at: (now | todate), last: null, turns: 0, action: $a}' > "$1.live.tmp" && mv -f "$1.live.tmp" "$1.live"
    sleep "$(jq -n --slurpfile u "$APIERR" '[$u[0] - now, 0.1] | max' 2>/dev/null || echo 1)"
  done
}
apitries() { # <worktree> <step> <output file> <command ...>
  local wt=$1 st=$2 o=$3 t rc api try=0 w at used=null s codex=false said; shift 3
  # Codex's words are read as Codex's (APISAID) for a Codex review and for a session on a Codex builder model alike.
  case $1 in
    codexreview) codex=true ;;
    session1) [ "$(seat builder | jq -r .agent 2>/dev/null)" != codex ] || codex=true ;;
  esac
  apihold "$wt" "$st" "$o"
  while :; do
    rm -f "$wt.spent"; t=$("$@"); rc=$?
    # What the tries the API refused before this one used is on the step's line too, or on the blocked one's spent.
    if [ "$used" != null ]; then
      if [ $rc = 0 ]; then s=$(jq -c --argjson p "$used" "$APIFOLD" <<<"$t") && t=$s
      elif s=$(jq -ce --argjson p "$used" "$APIFOLD" "$wt.spent" 2>/dev/null); then printf '%s\n' "$s" > "$wt.spent"
      else jq -c --arg s "$st" '{step: $s} + .' <<<"$used" > "$wt.spent"; fi
    fi
    # A Codex review or session whose stream names no API error may have said it on stderr alone.
    api=''; said=$o
    if [ $rc != 0 ] && [ -s "$wt.spent" ]; then
      api=$(jq -rRn --argjson codex "$codex" --rawfile e "$wt.err" "$APIERROR" "$o" 2>/dev/null)
      [ -n "$api" ] || [ $codex = false ] || { said=$wt.err; api=$(jq -rRn --argjson codex true --rawfile e "$wt.err" "$APIERROR" "$said" 2>/dev/null); }
    fi
    [ -n "$api" ] || { printf '%s\n' "$t"; return $rc; }
    # The API refused it: not a CLI that stopped before any work (nostart()), so no check session puts the card back.
    jq -c 'del(.start)' "$wt.spent" > "$wt.spent.new" 2>/dev/null && mv -f "$wt.spent.new" "$wt.spent" || rm -f "$wt.spent.new"
    s=$APIERR.$BASHPID; jq -n --argjson p "$API_PAUSE" 'now + 5 * $p' > "$s" 2>/dev/null && mv -f "$s" "$APIERR" || rm -f "$s"
    # A review that wrote its verdict and then failed (1, not 2) answered: its API error is marked as any is, so the
    # queue pauses, but it is never run again.
    [ "$st" != review ] || [ $rc = 2 ] || { printf '%s\n' "$t"; return $rc; }
    [ $try -lt 4 ] || { printf 'the model API refused (%s) at each of 5 tries, made %ss, then 2, 4 and 8 times that, apart\n%s\n' "$api" "$API_PAUSE" "$(jq -rRn --argjson codex "$codex" --rawfile e "$wt.err" "$APISAID" "$said" 2>/dev/null | tail -n 60)"; return 1; }
    read -r w at <<<"$(jq -rn --argjson p "$API_PAUSE" --argjson t "$try" '($p * pow(2; $t)) as $w | "\($w) \(now + $w | floor)"')"
    try=$((try + 1)); used=$(jq -c 'del(.step)' "$wt.spent")
    jq -cn --arg s "$st" --arg a "waiting: the model API refused ($api); trying again at $(p_date "@$at" +%H:%M)" --slurpfile u "$wt.spent" \
      '{step: $s, at: (now | todate), last: null, turns: 0, model: $u[0].model, action: $a}' > "$wt.live.tmp" && mv -f "$wt.live.tmp" "$wt.live"
    sleep "$w"
  done
}
session() { apitries "$1" "${3:-build}" "$1.out" session1 "$@"; } # <worktree> <prompt> [step: build (when none is given), fix or rebase]
# The builder program, the one seat() names for the model (its agent: the CLI the control record names, or the one the
# pack's models.allowed lists the model under): OpenCode, Codex or Claude Code. Run in the background (watch() follows it), so it
# execs the program in its own subshell, which a stall's kill ends, behind the words session1 lowers it with (STEER).
# Claude: bypass mode, as any other mode asks before a write under .claude/, and a headless session cannot answer, so
# a tooling card ended with no change; the card hooks (the settings file) still run in this mode.
# OpenCode (README.md, OpenCode builder): `opencode run` in the worktree, the prompt on stdin, its events as JSON
# lines; --auto approves what nothing denies, as bypass mode does; the config file (ocready()) loads the guard plugin,
# which runs the same settings file's hooks before each call; the project's own OpenCode config is not read, as a
# Claude session reads no project settings. It runs on no Claude account.
# Codex (README.md, Codex builder): `codex exec --json` in the worktree, the prompt on stdin, its events as JSON lines,
# on the model and effort as a Codex review is; its sandbox lets it write in the worktree, /tmp and $TMPDIR (where
# the brief's background runs and a test run's own scratch folder go) and the machine's test slots folder (slot_pool;
# the host's testSlotsDir may lie outside /tmp), which a test run takes a slot in, and nowhere else; its one
# PreToolUse hook, on every tool, is the guard hook (cxready()), which runs the same settings file's hooks before each
# call. Hooks are on, and run without Codex's trust prompt, which a headless session cannot answer;
# Codex's web search, a tool no hook is given, is off. Its commands get no terminal (unified_exec_tty off), so their input is
# closed: write_stdin, which types into a command already running and is given no hook, can only wait for output, and
# Codex refuses keys sent with it (a Codex without the feature fails to start). It runs on no Claude account.
sq() { local q="'"; printf "'%s'" "${1//$q/$q\\$q$q}"; } # <word>: it single-quoted for a shell
builder() { # <worktree> <prompt> <model> <effort> <account folder> <agent: claude, opencode or codex>
  local h a=()
  cd "$1" || exit 1
  export CONVEYOR_CARD=${1##*/}
  case $6 in
    codex) export CLAUDE_PROJECT_DIR=$1
      # The hook's command, each word single-quoted for the shell Codex runs it with, as a TOML string (JSON's escapes are TOML's).
      h=$(jq -rn --arg c "node $(sq "$CX_GUARD") $(sq "$1.settings") $(sq "$1")" \
        '"[{matcher = \"*\", hooks = [{type = \"command\", command = \($c | @json), timeout = 600}]}]"') || exit 1
      # A pool that cannot be made is left out: a test run then says why it takes no slot.
      ! slot_pool >/dev/null 2>&1 || a=(--add-dir "$SLOT_DIR")
      codexargs # its provider, when its route is the proxy
      exec "${STEER[@]}" timeout --kill-after=30 "$BUILD_TIMEOUT" codex exec --json -s workspace-write -C "$1" "${a[@]}" "${CODEX_PX[@]}" -m "$3" -c "model_reasoning_effort=\"$4\"" \
        -c 'web_search="disabled"' \
        --enable hooks --dangerously-bypass-hook-trust --disable unified_exec_tty -c "hooks.PreToolUse=$h" - <<<"$2" > "$1.out" 2> "$1.err" 8>&- ;;
    opencode) export CLAUDE_PROJECT_DIR=$1 CONVEYOR_GUARD_SETTINGS=$1.settings OPENCODE_CONFIG=$1.opencode.json OPENCODE_DISABLE_PROJECT_CONFIG=1
      exec "${STEER[@]}" timeout --kill-after=30 "$BUILD_TIMEOUT" opencode run --model "${3#opencode:}" --format json --auto <<<"$2" > "$1.out" 2> "$1.err" 8>&- ;;
    *) proxyenv && acctrun "$5" || exit 1
      exec "${STEER[@]}" timeout --kill-after=30 "$BUILD_TIMEOUT" claude -p --model "$3" --effort "$4" --permission-mode bypassPermissions --disallowedTools Agent \
        --setting-sources "" --strict-mcp-config --settings "$1.settings" --output-format stream-json --verbose <<<"$2" > "$1.out" 2> "$1.err" 8>&- ;;
  esac
}
# An OpenCode session starts only with every guard in place, else it prints why and fails: OpenCode 1.x on PATH (the
# plugin API guard.mjs is written for), the guard plugin and its runner (OC_GUARD, guard.sh and screen.mjs beside it) and the card's
# settings file. Writes the session's config file, <worktree>.opencode.json, that loads the plugin.
ocready() { # <worktree>
  local v
  command -v opencode >/dev/null || { echo "opencode is not on PATH, for the OpenCode builder model"; return 1; }
  v=$(timeout 60 opencode --version 2>/dev/null | head -n 1)
  [[ $v =~ ^v?1\.[0-9]+ ]] || { echo "OpenCode ${v:-of no version it would say} is not 1.x, whose plugin API the guard plugin is written for: an OpenCode session would run without the command guards, so it does not start"; return 1; }
  [ -f "$OC_GUARD" ] && [ -x "${OC_GUARD%/*}/guard.sh" ] \
    || { echo "the OpenCode guard plugin $OC_GUARD (or guard.sh beside it) is missing: an OpenCode session would run without the command guards, so it does not start"; return 1; }
  [ -f "${OC_GUARD%/*}/screen.mjs" ] \
    || { echo "screen.mjs, which the OpenCode guard plugin $OC_GUARD imports, is missing beside it: an OpenCode session would run without the command guards, so it does not start"; return 1; }
  [ -s "$1.settings" ] || { echo "the card's settings file $1.settings is missing: an OpenCode session would run without the command guards, so it does not start"; return 1; }
  jq -n --arg p "file://$OC_GUARD" '{"$schema": "https://opencode.ai/config.json", plugin: [$p], autoupdate: false}' > "$1.opencode.json" \
    || { echo "the OpenCode config file $1.opencode.json could not be written"; return 1; }
}
# A Codex session starts only with every guard in place, else it prints why and fails: a Codex on PATH whose exec runs
# hooks headless (--dangerously-bypass-hook-trust; the hooks of an older one wait for a trust prompt nobody answers,
# so they would not run), node for the guard hook, the guard hook and what it runs (CX_GUARD, ../opencode/screen.mjs
# and guard.sh) and the card's settings file.
cxready() { # <worktree>
  local g=${CX_GUARD%/*}/../opencode h
  command -v codex >/dev/null || { echo "codex is not on PATH, for the Codex builder model"; return 1; }
  # Read whole first: a grep that stops at the first match would end Codex's help early, and a pipe that fails so
  # reads as a Codex that cannot.
  h=$(timeout 60 codex exec --help 2>/dev/null)
  grep -q -- '--dangerously-bypass-hook-trust' <<<"$h" \
    || { echo "the Codex on PATH ($(timeout 60 codex --version 2>/dev/null | head -n 1)) cannot run hooks in a headless session (its exec has no --dangerously-bypass-hook-trust): a Codex session would run without the command guards, so it does not start"; return 1; }
  command -v node >/dev/null || { echo "node is not on PATH, for the Codex guard hook: a Codex session would run without the command guards, so it does not start"; return 1; }
  [ -f "$CX_GUARD" ] && [ -f "$g/screen.mjs" ] && [ -x "$g/guard.sh" ] \
    || { echo "the Codex guard hook $CX_GUARD (or opencode/screen.mjs or opencode/guard.sh beside it) is missing: a Codex session would run without the command guards, so it does not start"; return 1; }
  [ -s "$1.settings" ] || { echo "the card's settings file $1.settings is missing: a Codex session would run without the command guards, so it does not start"; return 1; }
}
session1() {
  local model effort agent rc s sec f dir='' x='' read=$SESSIONREAD roll run
  s=$(seat builder) && jqget "$s" model model effort effort agent agent || { echo "the pack's models.allowed lists no builder model"; return 1; }
  # The CLI the seat names, never another: one that is gone starts no session.
  f=$(seatready builder "$s") || { echo "$f"; return 1; }
  # OpenCode takes no effort here (its line names none); OpenCode and Codex run on no Claude account. A Codex model
  # named by its family is the newest of it, as for a review (codexmodel()).
  case $agent in
    opencode) effort=''; read=$OPENCODEREAD; f=$(ocready "$1") || { echo "$f"; return 1; } ;;
    codex) read=$CODEXREAD; model=$(codexmodel "$model") || { echo "$model"; return 1; }; f=$(cxready "$1") || { echo "$f"; return 1; } ;;
    *) dir=$(acctenv "$ACCT") || { echo "$dir"; return 1; } ;;
  esac
  rm -f "$1.spent" "$1.stalled"
  # Card work yields to the user (lib/slots.sh steer_words): a build, fix or rebase session at lowered priority; a
  # test-speed survey card's, which runs its test files itself, at a test run's idle one, given its normal priority
  # back while it starves (steer_watch), as a test run is (card(): STEER_KIND).
  # shellcheck disable=SC2034 # STEER_HOW and STEER_SLICE are set by steer_words and read by steer_watch (lib/slots.sh)
  local STEER STEER_HOW STEER_SLICE sw='' bp
  steer_words "${STEER_KIND:-session}"
  # A session that stalls (watch()) is ended and runs once more after REVIEW_PAUSE, as a review with no verdict does
  # (reviewed()), on what it left in the worktree; the stalled try
  # is firstTry on the step's line (BOTHTRIES), and stalls counts the stalls. A second stall fails the step.
  while :; do
    sec=$SECONDS
    builder "$1" "$2" "$model" "$effort" "$dir" "$agent" & bp=$!
    [ "${STEER_KIND:-session}" != test ] || { steer_watch $bp 8>&- & sw=$!; }
    watch $bp "$1.out" "$1.live" "${3:-build}" "$model" "$agent"; rc=$?; sec=$((SECONDS - sec))
    [ -z "$sw" ] || { kill "$sw" 2>/dev/null; wait "$sw" 2>/dev/null; sw=''; }
    # A Codex session cut off before its turn completed: its running total, from the session file Codex keeps (read
    # and removed, as a review's is).
    run=''; [ "$agent" != codex ] || { roll=$(rollout "$1.out"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); rm -f "$roll"; }; }
    # The step's fields, however it ended (SESSIONREAD, OPENCODEREAD, CODEXREAD): one JSON object, always, so the line is always written.
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" --argjson run "${run:-null}" "$read" "$1.out" 2>/dev/null | tail -n 1)
    jq -e 'objects | has("ok")' <<<"$f" >/dev/null 2>&1 \
      || f=$(jq -cn --arg m "$model" --arg e "$effort" --argjson s "$sec" '{model: $m, effort: $e, sec: $s, unread: "the session output could not be read", ok: false}
          | if $e == "" then del(.effort) else . end')
    [ -z "$x" ] && [ -e "$1.stalled" ] || break
    x=$(jq -c --arg r "stalled at ${3:-build}: no progress since $(<"$1.stalled")" '{reason: $r, spent: del(.ok)}' <<<"$f")
    echo "conveyor: card ${1##*/}: its ${3:-build} made no progress for ${STUCK}s: ended, and run once more after ${REVIEW_PAUSE}s" >&2
    sleep "$REVIEW_PAUSE"
  done
  steer_end
  [ -z "$x" ] || f=$(jq -c --argjson f "$x" --argjson n "$([ -e "$1.stalled" ] && echo 2 || echo 1)" "$BOTHTRIES"' | .stalls = $n' <<<"$f")
  [ "$agent" != claude ] || proxypack
  [ "$agent" = opencode ] || f=$(routed "$f" "$agent")
  # A session whose last result says it succeeded goes on, its usage or stats read or not (unread says why not).
  if [ $rc = 0 ] && [ "$(jq -r .ok <<<"$f")" = true ]; then [ "$agent" != claude ] || routedone 1; jq -c 'del(.ok)' <<<"$f"; return 0; fi
  # A session that failed still spent its tokens and seconds: block() records them.
  jq -c --arg st "${3:-build}" '{step: $st} + del(.ok)' <<<"$f" > "$1.spent"
  [ -z "$x" ] || [ ! -e "$1.stalled" ] || { echo "stalled twice at ${3:-build}: no progress since $(<"$1.stalled")"; return 1; }
  if nostart "$rc" "$f" "$1.out" "$1.err" "$agent" "$model" builder "$([ "$agent" != claude ] || printf '%s' "$ACCT")" "$1"; then
    jq -c --argjson s "$NOSTART_START" '. + {start: $s}' "$1.spent" > "$1.spent.new" && mv -f "$1.spent.new" "$1.spent"
    [ "$agent" != claude ] || routedone 0
    # Its subscription login failed and the proxy is its role's fallback: the same step at once through the proxy.
    if [ "$agent" != opencode ] && proxyfallback "$agent"; then
      s=$NOSTART_WHY; f=$(PROXY_NOW=1 session1 "$@") && { printf '%s\n' "$f"; return 0; }
      bothsaid "$s" "$f"; return 1
    fi
    signinstop "${3:-build}"; printf '%s\n' "$NOSTART_WHY"; return 1
  fi
  [ "$agent" != claude ] || routedone 1
  [ $rc = 0 ] || { printf 'session failed (%s)\n%s\n' "$(exitsaid "$rc" "$BUILD_TIMEOUT")" "$(tail -n 60 "$1.err")"; return 1; }
  echo "session ended with an error result, or with no result"; return 1
}
# The exit of a session or review as its reason says it: the timeout is named only when the exit is the timeout's (124).
exitsaid() { if [ "$1" = 124 ]; then echo "exit 124, the ${2}s timeout"; else echo "exit $1"; fi; } # <exit> <timeout in seconds>
# The routes of a Claude or Codex session (claudeProxy, codexProxy, proxyroute()): a step's fields with the route it
# took (subscription or proxy) when a proxy is set for its CLI; as they are when none is.
routed() { jq -c --arg r "$(proxyroute "${2:-claude}")" 'if $r == "" then . else . + {route: $r} end' <<<"$1"; } # <the step's fields> [claude|codex]
# The state of each route as the last Claude session or review on it found it, for the Board's Health (health()):
# {subscription: {state, at}, proxy: {state, at}}, state works, expired, not set (its login failed: nostart()'s
# NOSTART_LOGIN) or fails (the proxy's), in ROUTES (control.sh). Written whole beside its place and moved in.
routeset() { # <subscription|proxy> <state>
  local t=$ROUTES.$BASHPID
  { cat "$ROUTES" 2>/dev/null || echo null; } | jq -c --arg r "$1" --arg s "$2" 'if type == "object" then . else {} end | .[$r] = {state: $s, at: (now | todate)}' > "$t" 2>/dev/null \
    && mv -f "$t" "$ROUTES" || rm -f "$t"
}
# After a Claude session or review: <0> when nostart() named why it never began its work, else <1>. The route it took
# works, or it failed: through the proxy, for any cause (a proxy that is stopped refuses the connection, which is no
# login cause); on the subscription, only when its login failed (NOSTART_LOGIN), as another cause says nothing of it.
routedone() { # <0|1>
  local r; r=$(proxyroute); r=${r:-subscription}
  if [ "$1" != 0 ]; then routeset "$r" works
  elif [ "$r" = proxy ]; then routeset proxy fails
  elif [ -n "$NOSTART_LOGIN" ]; then routeset subscription "$NOSTART_LOGIN"; fi
}
# Whether a Claude or Codex session or review whose start failed (nostart()) runs again at once through the proxy: its
# login failed on the subscription, and the proxy set for its CLI is its role's fallback (proxyrole()).
proxyfallback() { # [claude|codex]
  [ -n "$NOSTART_LOGIN" ] && [ -z "${PROXY_NOW:-}" ] && [ "$(proxyrole "${1:-claude}")" = fallback ]
}
# The reason of a step that failed on its subscription login and again through the fallback proxy: both causes on its
# first line, then each one's words below it.
bothsaid() { # <the subscription try's reason> <the proxy try's reason>
  printf 'on the subscription login, %s; through the proxy, %s\n' "${1%%$'\n'*}" "${2%%$'\n'*}"
  [[ $1 != *$'\n'* ]] || printf '%s\n' "${1#*$'\n'}"
  [[ $2 != *$'\n'* ]] || printf '%s\n' "${2#*$'\n'}"
}
# A failed session's or review's own error words, whatever its CLI: its error results (Claude: the error's code, such
# as authentication_failed, and its text), its error and turn.failed events (Codex, OpenCode) and the lines that are no
# JSON, the last 5 of them.
NOSTARTSAID='[inputs | select(test("\\S")) | (fromjson? // {type: "plain", message: .}) | objects
  | if .type == "result" then select(.is_error == true) | (.error?, .result) elif .type == "turn.failed" then .error.message?
    elif .type == "error" then (.message? // .error.data.message? // .error.message? // .error.name?) elif .type == "plain" then .message else empty end
  | strings] | .[-5:][]'
# The words of a CLI whose login failed (nostart(), loginfallback()).
LOGINSAID='not logged in|log ?in|invalid api key|authenticat|unauthori[sz]ed|oauth|credentials'
# Whether a one-answer call on Claude or Codex that failed (the judge, askmodel(), a test action, a check session)
# runs again at once through the proxy: it failed (its exit not 0 and not the timeout's 124) and its words
# (NOSTARTSAID, then the last lines of its stderr) say its login failed, and the proxy set for its CLI is its role's
# fallback (proxyfallback()). Sets NOSTART_LOGIN as nostart() does.
loginfallback() { # <exit> <claude|codex|opencode> <its output file> [<its stderr file>]
  local raw
  NOSTART_LOGIN=''
  [ "$1" != 0 ] && [ "$1" != 124 ] && [ "$2" != opencode ] || return 1
  raw=$( { jq -rRn "$NOSTARTSAID" "$3" 2>/dev/null; [ -z "${4:-}" ] || tail -n 20 "$4" 2>/dev/null; } | tr -d '\000')
  grep -Eqi "$LOGINSAID" <<<"$raw" && ! grep -Eqi "(^|[^a-z])$2: (command )?not found" <<<"$raw" || return 1
  NOSTART_LOGIN='not set'; ! grep -Eqi 'expired|refresh|revoked|refused' <<<"$raw" || NOSTART_LOGIN=expired
  proxyfallback "$2"
}
# A session or review that failed (its exit not 0 and not the timeout's 124) with no turn past its first and no token
# never began its work: its CLI stopped before it (not logged in, a model this account does not have, a settings
# error). Sets NOSTART_WHY to its reason: the cause, named from the CLI's own words (a session through a proxy or the
# API: that route at its base URL, never a sign-in to it), its exit and what to do; under it
# those words (NOSTARTSAID, then the last lines of its stderr), the last 12 lines, each cut at 300 characters, with
# the user's home written ~, what looks like a credential (a value after key, token, secret, password or
# authorization and a colon or =, quoted or not, one after Bearer, a run of 24 or more letters, digits, - and _) left
# out, and every line the privacy check's patterns hit left out. Sets NOSTART_START to the seat (builder or reviewer),
# CLI, model and account it ran on: a check session on that seat as it is set then runs before the card is put back
# (startagain(), startnow()). Fails, setting neither, for any other session. NOSTART_LOGIN: the login's state when
# the cause is the login (expired: its words say expired, refresh, revoked or refused; else not set), else empty.
# NOSTART_SIGNIN, when the cause is the login: the sign-in failure (expired, was refused or is missing) and what to
# run, for the pause (signinstop()); NOSTART_START then has signin: true, so a resume puts the card back
# (signinback()). Else empty.
nostart() { # <exit> <the step's fields> <output file> <stderr file> <cli> <model> <builder|reviewer> <account, "" for the default login> <worktree>
  local raw words hits cause todo n p px c=${9##*/}
  NOSTART_LOGIN='' NOSTART_SIGNIN=''
  [ "$1" != 0 ] && [ "$1" != 124 ] && [ ! -e "$9.stalled" ] || return 1
  jq -e '([.tokens // {} | .[] | numbers] | add // 0) == 0 and (.stats.turns // 0) <= 1' <<<"$2" >/dev/null 2>&1 || return 1
  raw=$( { jq -rRn "$NOSTARTSAID" "$3" 2>/dev/null; tail -n 20 "$4" 2>/dev/null; } | tr -d '\000')
  # Cut after what is left out, so no part of a credential cut short is kept.
  words=$(jq -rRs --arg h "${HOME:-}" '[splits("\n") | select(test("\\S"))] | .[-12:][]
      | if $h != "" then split($h) | join("~") else . end
      | gsub("(?<k>(key|token|secret|password|authorization)[\"'"'"']?\\s*[:=]\\s*(bearer\\s+)?)(\"([^\"\\\\]|\\\\.)*\"?|'"'"'[^'"'"']*'"'"'?|[^\\s\"'"'"',;\\[]+)"; "\(.k)[left out]"; "i")
      | gsub("(?<k>bearer\\s+)[^\\s\"'"'"',;\\[]+"; "\(.k)[left out]"; "i")
      | gsub("[A-Za-z0-9_-]{24,}"; "[left out]") | .[0:300]' <<<"$raw" 2>/dev/null) || words=''
  if [ -n "$words" ]; then
    hits=$(printf '%s\n' "$words" | "$HERE/privacy/check.sh" -)
    if [ $? -gt 1 ]; then words='[left out: the privacy check could not be made]'
    else words=$(printf '%s\n' "$words" | H=$hits awk 'BEGIN { n = split(ENVIRON["H"], l, "\n"); for (i = 1; i <= n; i++) if (split(l[i], p, ": ") >= 2) { sub(/^-:/, "", p[1]); bad[p[1] + 0] = p[2] } }
        { if (NR in bad) print "[a line left out: " bad[NR] "]"; else print }'); fi
  fi
  # The route it took, when that is a proxy or the API: "the proxy at <base URL>" or "the API at <base URL>".
  px=''
  if [ "$5" != opencode ] && [ "$(proxyroute "$5")" = proxy ]; then
    if [ "$5" = codex ]; then p=$(codexproxyset); else p=$(claudeproxy); fi
    px=$(jq -r '"the \(if .kind == "api" then "API" else "proxy" end) at \(.baseUrl // "https://api.anthropic.com")"' <<<"$p")
  fi
  if [ "$1" = 127 ] || grep -Eqi "(^|[^a-z])$5: (command )?not found" <<<"$raw"; then
    cause="the $5 CLI is not installed"; todo="install it, or set the $7 to a CLI this host has (conveyor.sh control, or Rules on the Board)"
  elif grep -Eqi "$LOGINSAID" <<<"$raw"; then
    NOSTART_LOGIN='not set'; ! grep -Eqi 'expired|refresh|revoked|refused' <<<"$raw" || NOSTART_LOGIN=expired
    if grep -Eqi 'expired|refresh' <<<"$raw"; then cause=expired
    elif grep -Eqi 'revoked|refused|invalid|unauthori[sz]ed|denied' <<<"$raw"; then cause='was refused'; else cause='is missing'; fi
    if [ -n "$px" ]; then
      # Through a proxy or the API: their refusal, never a sign-in to the route, which has none.
      cause="$px refused the call"; todo="check ${px% at *} and the key it is sent (conveyor.sh doctor makes one call through it)"
      if [ "$5" = claude ] && grep -qi 'oauth' <<<"$raw" && grep -Eqi 'expired|refresh' <<<"$raw"; then
        cause+=": its answer says Claude Code's own sign-in expired"; todo="run claude /login${8:+ on the account $8}, or $todo"; fi
    else case $5 in
      codex) cause="the Codex sign-in $cause"; todo="run codex login (or set up the proxy route)" ;;
      opencode) cause="the OpenCode sign-in $cause"; todo="run opencode auth login" ;;
      *) cause="Claude Code's own sign-in $cause"; todo="run claude /login${8:+ on the account $8} (or set up the proxy route)" ;;
    esac; fi
    todo+=", then conveyor.sh control resume"; NOSTART_SIGNIN="$cause; $todo"
  elif grep -Eqi 'model' <<<"$raw" && grep -Eqi 'not found|not_found|not exist|unknown|invalid|not available|not supported|access' <<<"$raw"; then
    cause="the $5 CLI cannot run the model $6 on this account"; todo="set the $7 to a model the account has (conveyor.sh control, or Rules on the Board)"
  elif grep -Eqi 'setting|config' <<<"$raw"; then
    cause="the $5 CLI stopped on a settings error"; todo="fix the setting its words below name"
  elif [ -n "$px" ]; then cause="the call through $px failed"; todo="check ${px% at *}, as its words below say"
  else cause="the $5 CLI stopped before any work"; todo="fix what its words below say"; fi
  # A card's worktree is named by its card id, c<time>-<project>-<issue> (pick()); a lane's preview is not a card.
  n=${c##*-}; [[ $n =~ ^[1-9][0-9]*$ ]] || n=$c
  if ! startonce "$n"; then [[ ! $c =~ ^c[0-9]{8}T[0-9]{6}- ]] || todo+=", then retry the card (conveyor.sh retry $n, or Retry on the Board)"
  elif [ -n "$NOSTART_SIGNIN" ]; then todo+=". The card is put back once by itself on resume"
  else todo+=". The card is put back once by itself when a check session on the $7's CLI and model starts"; fi
  NOSTART_WHY="$cause ($(exitsaid "$1" 0)): $todo"$'\n'"${words:-(the $5 CLI wrote nothing)}"
  NOSTART_START=$(jq -cn --arg s "$7" --arg c "$5" --arg m "$6" --arg a "$8" --arg g "$NOSTART_SIGNIN" '{seat: $s, cli: $c, model: $m, account: $a}
    + if $g == "" then {} else {signin: true} end')
}
# After nostart(), for a step that runs nowhere else (no fallback route, or the fallback's own sign-in failed too): a
# sign-in failure pauses the loop with the step and its reason (signinpause()), as every card would meet it.
signinstop() { [ -z "$NOSTART_SIGNIN" ] || locked signinpause "$1: $NOSTART_SIGNIN" || true; } # <step>
# Whether an issue's card blocked by a session that never began its work (nostart()) is still put back by itself
# (startagain()): an issue, not a main-red fix card (issue 0), none of whose earlier cards was put back so.
startonce() { # <issue>
  [[ $1 =~ ^[1-9][0-9]*$ ]] || return 1
  ! stdb ask issue retried "$1" 2>/dev/null | jq -e 'select(.step == "blocked" and (.spent.start | type) == "object")' >/dev/null 2>&1
}
# What a check session runs on (startcheck()) for a session that never began its work (nostart()): the CLI and model
# its seat is set to now, so one the owner changed after the block is the one checked, on the account it ran on (none
# for a CLI that is not claude). Fails when the seat is set to none.
startnow() { # <{seat, cli, model, account}>
  local r s m a
  r=$(jq -r '.seat // empty' <<<"$1" 2>/dev/null); [ -n "$r" ] || return 1
  s=$(seat "$r") && jqget "$s" model m agent a || return 1
  [ "$a" != codex ] || m=$(PROXY_ROLE=$r codexmodel "$m") || return 1
  jq -c --arg c "$a" --arg m "$m" '{seat, cli: $c, model: $m, account: (if $c == "claude" then .account // "" else "" end)}' <<<"$1"
}
# A check session: the CLI, model and account startnow() gives, asked for one
# word in an empty folder, under 120 s, with no project settings, on its seat's route. Succeeds when it ends well (exit 0).
startcheck() { # <{seat, cli, model, account}>
  local cli m a d rc
  jqget "$1" cli cli model m account a || return 1
  d=$(mktemp -d) || return 1
  # On the route its seat's role takes (proxyroute()).
  local PROXY_ROLE; PROXY_ROLE=$(jq -r '.seat // "builder"' <<<"$1"); [ "$PROXY_ROLE" = reviewer ] || PROXY_ROLE=builder
  case $cli in
    claude) (cd "$d" && a=$(acctenv "$a") && proxyenv && acctrun "$a" \
      && exec timeout --kill-after=10 120 claude -p --model "$m" --setting-sources "" --strict-mcp-config --no-session-persistence <<<"Reply with the one word OK." >"$d.out" 2>&1 8>&-) ;;
    codex) (cd "$d" && codexargs && exec timeout --kill-after=10 120 codex exec --skip-git-repo-check -s read-only "${CODEX_PX[@]}" -m "$m" - <<<"Reply with the one word OK." >"$d.out" 2>&1 8>&-) ;;
    opencode) (cd "$d" && OPENCODE_DISABLE_PROJECT_CONFIG=1 exec timeout --kill-after=10 120 opencode run --model "${m#opencode:}" <<<"Reply with the one word OK." >/dev/null 2>&1 8>&-) ;;
    *) false ;;
  esac; rc=$?
  # Its login failed and the proxy is its role's fallback: checked again at once through the proxy.
  if loginfallback "$rc" "$cli" "$d.out"; then PROXY_NOW=1 startcheck "$1"; rc=$?; fi
  rm -rf "$d" "$d.out"; return $rc
}
