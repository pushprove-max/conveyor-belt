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
# The cases of a test run that have ended: a runner may name each, as it ends, by an empty file in cases/ok (it passed) or cases/failed of that folder.
testdone() { # <worktree>; prints {done, failed}
  local ok bad
  ok=$(find "$1.testlog/cases/ok" -maxdepth 1 -type f 2>/dev/null | wc -l); bad=$(find "$1.testlog/cases/failed" -maxdepth 1 -type f 2>/dev/null | wc -l)
  printf '{"done":%d,"failed":%d}\n' $((ok + bad)) $((bad))
}
# Ends <pid> and every process under it at once (SIGKILL): each is stopped first, so none starts another or leaves
# its parent unseen while they are found, then its process group (a test run's timeout leads one) and each found.
endall() { # <pid>
  local ps=("$1") i=0 k
  while [ $i -lt ${#ps[@]} ]; do
    kill -STOP "${ps[i]}" 2>/dev/null; for k in $(pgrep -P "${ps[i]}" 2>/dev/null); do ps+=("$k"); done; i=$((i + 1))
  done
  kill -KILL -- "-$1" 2>/dev/null; kill -KILL "${ps[@]}" 2>/dev/null; :
}
# The files of a test run so far, as watch() counts them below: {run, of, cases}, from its output and the logs it wrote
# (cases null when its `TESTRUN cases=` lines add up to 0), and now, the file that runs now: the last a `== <file>` line
# began that no `-- ok|FAIL <file>` line has ended since (left out when none);
# run is never above of: a run that ran more test files than it selected has over too, how many more.
# Each test file counts once, by its name (a file run again, or named in two logs, is one). A runner that prints both
# a `-- ok|FAIL <file>` line and vitest's line for each file names it in two ways (web/src/a.test.ts and
# src/a.test.ts, #360): of a file whose `-- ok|FAIL` lines name its test files, the vitest lines are left out.
testprogress() { # <output file> [log...]
  local f=$1 x; shift
  # Each file is read after a line of one \036, so the awk tells the output (n 1) and each log (n 2, ...) apart.
  for x in "$f" "$@"; do printf '\n\036\n'; sed 's/\x1b\[[0-9;]*m//g' "$x" 2>/dev/null; done | awk -v logs="$#" '
    $0 == "\036" { n++; next }
    /^test-changed: [0-9]+ web test file\(s\) selected/ { of += $2; seen = 1; next }
    n == 1 && logs > 0 { next }
    /^-- (ok|FAIL) / { # the name without the padding and the times a runner may put around it (`-- ok   a.test.ts 0s`)
      k = $0; sub(/^-- (ok|FAIL) +/, "", k); sub(/[ \r]+$/, "", k); while (sub(/ +[0-9][0-9.]*m?s$/, "", k)) ;
      if (k != "") { named[n, k] = 1; names[n] = 1; delete open[k] } }
    /^== / { k = $0; sub(/^== +/, "", k); sub(/[ \r]+$/, "", k); if (k != "") open[k] = ++began }
    /^ (✓|❯|×|↓) [^ ]+ \([0-9]+ tests?[ |)]/ { vitest[n, $2] = 1 }
    /^TESTRUN files=[0-9]+/ { sub(/^TESTRUN files=/, ""); of += $1; seen = 1 }
    /^TESTRUN cases=[0-9]+/ { sub(/^TESTRUN cases=/, ""); cof += $1 }
    END {
      for (i in named) { split(i, p, SUBSEP); if (!(p[2] in ran)) { ran[p[2]] = 1; run++ } }
      for (i in vitest) { split(i, p, SUBSEP); if (!(p[1] in names) && !(p[2] in ran)) { ran[p[2]] = 1; run++ } }
      over = seen && run > of ? run - of : 0
      # now: the file begun last that has not ended (the backslash doubled by "&&", as each awk reads it alike).
      last = 0; for (k in open) if (open[k] > last) { last = open[k]; cur = k }
      if (last) { gsub(/\\/, "&&", cur); gsub(/"/, "\\\"", cur); cur = ",\"now\":\"" cur "\"" }
      printf "{\"run\":%d,\"of\":%s,\"cases\":%s%s%s}\n", (over ? of : run), (seen ? of + 0 : "null"), (cof > 0 ? cof + 0 : "null"), (over ? ",\"over\":" over : ""), cur }'
}

# Waits for a running step and keeps its live record (README.md) while it runs; returns the step's exit. Only
# the whole lines the output file has gained since the last look are read, so a long session costs no more each
# time. A session's tokens are those of each answer of the model, counted once (an answer is several events with one
# id, the same usage on each); its output tokens are reported in full only when the session ends, so the reading
# runs a little low. A test run is counted whole each time, from its output and the logs it wrote (testlogs): files
# selected are the `TESTRUN files=N` lines and the web half's `N web test file(s) selected`, files run the distinct
# files the `-- ok|FAIL <file>` lines and vitest's line a file name, never more than those selected (over: how many
# more ran; testprogress()). A runner that also prints its log's lines is counted once. A run that names no files
# selected has of from the size of the card's test list (list.files) when that has one (#385).
# Its cases (tests: {done, of, failed}) are counted only when `TESTRUN cases=N` lines say how many were selected
# (several add up) and that is above 0, else tests is null (#385: a run of whole files prints cases=0): done and
# failed are the cases its runner named as ended (testdone()).
# files.now ({file, at}) names the file that runs now (testprogress() now) and when this watch first saw it begin, so a slow file and a hung run can be told apart (#433); left out while no file runs.
# A test run's `progress` (which health reads beside `last`, so the Foreman calls no running test step stuck while it
# moves) is when the run began, then when a case of its runner last began or ended (testcases(), testdone()); its
# `list` is the list of tests the command was given (<worktree>.testlist, tests()); its `before` is the seconds of the
# run before it in the same Test step (TEST_BEFORE: tests() runs the failed cases again at once), left out on a first.
# A review's tokens are not in its stream before its turn ends: Codex writes the running total (`token_count`) to the session file it keeps under its home, named after the thread the stream opens with. rollout() finds that file.
rollout() { # <a review's events file>; prints the session file of that review, nothing when there is none yet
  local id
  id=$(grep -m 1 '"thread.started"' "$1" 2>/dev/null) && id=$(jq -r '.thread_id // empty' <<<"$id" 2>/dev/null) && [[ $id =~ ^[0-9A-Za-z-]+$ ]] || return 0
  find "${CODEX_HOME:-$HOME/.codex}/sessions" -type f -name "rollout-*-$id.jsonl" 2>/dev/null | head -n 1
}
liveusage() { { if [ $# = 0 ]; then printf '%s' "${WATCHED:-}"; else cat "$1"; fi; } 2>/dev/null | jq -c '.usage | objects | select((.input | type) == "number" and (.output | type) == "number") | {input_tokens: (.input + (.read // 0)), cached_input_tokens: (.read // 0), output_tokens: .output}' 2>/dev/null; } # [live file]: the running total watch() last gave a Codex review's live record from its session file (that live file's, else WATCHED: the last record of the live file watch() just removed), as that file writes it: what a review that ended before its turn did spent, when its session file then holds none; nothing when the record holds no usage
# A build, fix, rebase or review that makes no progress for STUCK seconds is ended: no new output line (its live
# record's `last`), no file of its worktree changed and no new commit there (holds(), asked only once the output has
# been quiet that long, so a session's files cost nothing while it talks). Output is a whole new line, and of a Codex
# review's session file a new token count read from it: bytes with no newline (a spinner, a line cut short) move the
# file's size and are no progress. The output is read first each time, so a line that came since the last look counts; and the clock runs from when the files last changed, not from when that was
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
watch() { # <pid> <output file> <live file> <step> [the model it runs on] [the program that runs it: codex for a Codex build, fix or rebase] [the effort it runs at]
  local pid=$1 f=$2 out=$3 st='' new who rc=0 timer n have=0 size=0 now logs roll='' rsize=0 wt=${3%.live} was='' seen=$EPOCHSECONDS at lines=0 rhave=0 rn cs dn cx=false wn wb wk=0 gk='' cpu=0 cpt=0
  [ "${6:-}" != codex ] || cx=true
  # rm only when there is a file to remove (#532: most steps have none).
  [ "$4" = test ] || { [ ! -e "$wt.stalled" ] && [ ! -L "$wt.stalled" ]; } || { [ ! -s "$wt.stalled" ] || was=$(<"$wt.stalled"); rm -f "$wt.stalled"; }
  while :; do
    [ -n "$st" ] || { st=$(jq -cn --arg s "$4" --argjson p "$pid" --arg m "${5:-}" --arg e "${7:-}" --arg w "$was" --slurpfile tl <([ "$4" != test ] || cat "$wt.testlist" 2>/dev/null) --arg b "${TEST_BEFORE:-}" '{step: $s, at: (now | todate), last: null, turns: 0, pid: $p}
      + (if $s == "test" then {progress: (now | todate), files: {run: 0, of: null}, tests: null} + (if $tl[0] | type == "object" then {list: $tl[0]} else {} end)
          + (if $b == "" then {} else {before: ($b | tonumber)} end) else {} end)
      + (if $m == "" then {} else {model: $m} end) + (if $e == "" then {} else {effort: $e} end) + (if $w == "" then {} else {stalled: $w} end)') \
      && [ -n "$st" ] && printf '%s\n' "$st" > "$out"; } || st='' # the live record, made at the first look and at each look until it is: a first jq that failed left the state empty, each later look failed on it, and the session had no live record (issue 1524); pid: the process watched (health: a session whose record names none runs no session now)
    sleep "$LIVE" > /dev/null 8>&- & timer=$!
    # A bash before 5.3 takes a step that ended off its job table as a job starts (the timer): `wait -n` says "no such
    # job" and waits out the timer (#1319). A step that ended is asked for by itself, below, for its kept status.
    who=''; kill -0 "$pid" 2>/dev/null && wait -n -p who "$pid" "$timer" 2>/dev/null; rc=$?
    kill "$timer" 2>/dev/null; wait "$timer" 2>/dev/null
    [ "$who" != "$pid" ] || break
    kill -0 "$pid" 2>/dev/null || { wait "$pid"; rc=$?; break; }
    [ -n "$who" ] || break
    # A card that gave way (giveway()): once a card took its turn, the live record names it (gaveWay: its issue); no jq while it has no claim (#1542).
    [ -s "${out%.live}.claim" ] && new=$(jq -c --argjson st "$st" 'select(.away == true and (.to | type) == "number" and .to != $st.gaveWay) | $st + {gaveWay: .to}' "${out%.live}.claim" 2>/dev/null) \
      && [ -n "$new" ] && st=$new && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"
    # A guard that failed twice (guardrun.sh) ends the session, as OpenCode and Codex ignore "continue": false: at the look after the one that saw it (gk), as guardrun.sh records the failure before it gives the session the refusal, which the session reads in between.
    [ "$4" = test ] || [ ! -s "$wt.guardfail" ] || ! awk -F'\t' '++n[$1] == 2 { f = 1 } END { exit !f }' "$wt.guardfail" || { [ -z "$gk" ] && gk=1 || { kill "$pid" 2>/dev/null; wait "$pid"; rc=$?; break; }; }
    if [ "$4" = test ]; then
      mapfile -t logs < <(testlogs "${f%.test}")
      now=$(p_stat "$f" "${logs[@]}" | awk '{s = s "," $1; if ($2 > t) t = $2} END {if (NR) print s " " t}')
      cs=$(testcases "${f%.test}"); dn=$(testdone "${f%.test}")
      [ -n "$now" ] && [ "${now% *} $cs $dn" != "$size" ] || continue
      # A case that began or ended (its runner's cases folder) is progress, though nothing was printed.
      [ "$cs $dn" = "${size#* }" ] || st=$(jq -c '.progress = (now | todate)' <<<"$st")
      size="${now% *} $cs $dn"
      new=$(testprogress "$f" "${logs[@]}" \
        | jq -c --argjson st "$st" --argjson t "${now##* }" --argjson cs "$cs" --argjson dn "$dn" '$st + {files: ({run, of: (.of // $st.list.files)} + (if .over then {over} else {} end)
              + (.now as $f | if $f == null then {} elif $st.files.now.file == $f then {now: $st.files.now} else {now: {file: $f, at: (now | todate)}} end)),
            tests: (.cases as $n | if $n == null then null else {done: $dn.done, of: $n, failed: $dn.failed} end), last: ($t | todate), cases: $cs}' 2>/dev/null) \
        && [ -n "$new" ] && st=$new && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"
      # A run given TEST_GIVEN test files (a card's run and the bug-card check, tests(), testlist.sh bugrun(); never the full test
      # suite) that reports more (the files it says it selected, or those it ran) than those is ended at once, every
      # process under it (#350: a card never runs the whole suite): <worktree>.wide holds that count. Run file by file (filecmd(), lib/testrun.sh: a `== <file>` line in its log `files` as each begins), a run that reports more files than it began is ended too (an invocation given the first of two that runs both); the begun ones are read last, so one begun meanwhile is no false stop. So is one whose files before the k-th reported more than k - 1 (wideeach(): one that ran both and ended, and the next began, between two looks).
      if [ -n "${TEST_GIVEN:-}" ] && [ ! -e "$wt.wide" ] && wn=$(jq -r '[.files.run + (.files.over // 0), .files.of // 0] | "\(.[0]) \(max)"' <<<"$st" 2>/dev/null) && [[ $wn =~ ^[0-9]+\ [0-9]+$ ]]; then
        wb=$(sed -n 's/^== //p' "$wt.testlog/files" 2>/dev/null | sort -u | wc -l); if [ "${wn#* }" -gt "$TEST_GIVEN" ] || { [ "$wb" -gt 0 ] && [ "${wn% *}" -gt "$wb" ]; }; then echo "${wn#* }" > "$wt.wide"; endall "$pid"; elif wn=$(wideeach "$wt" "$wk"); then endall "$pid"; else wk=$wn; fi; fi
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
      size=${now% *}; n=$(wc -l < "$f"); [ "$n" -le "$lines" ] || { lines=$n; seen=$EPOCHSECONDS; } # the new whole lines, read by one awk that stops at line n: a `tail | head` failed each look that found more after them (a line written since, or one half written), as the loop runs with SIGPIPE ignored (systemd's IgnoreSIGPIPE, kept by machineloop()): tail got EPIPE, pipefail failed the look and its lines were never read
      new=$(awk -v a="$have" -v b="$n" 'NR > b {exit} NR > a' "$f" | jq -cRn --argjson st "$st" --argjson t "${now#* }" --argjson cx "$cx" --arg wt "$wt" '
        def use: (.cache_creation.ephemeral_1h_input_tokens // 0) as $h | {input: (.input_tokens // 0), write: ((.cache_creation_input_tokens // 0) - $h),
          write1h: $h, read: (.cache_read_input_tokens // 0), output: (.output_tokens // 0)};
        def plus($b): with_entries(.value += ($b[.key] // 0)); def minus($b): with_entries(.value = ([.value - ($b[.key] // 0), 0] | max)); def u0: {input: 0, write: 0, write1h: 0, read: 0, output: 0};
        def sofar: (.cur // {}) as $c | (.done // u0) | plus($c); def bym: (.cur // {}) as $c | (.bmd // {}) as $d | $d + (if .cm == null then {} else {(.cm): (($d[.cm] // u0) | plus($c))} end); # the answers so far; each model'"'"'s
        # The card'"'"'s worktree path reads worktree before the cut, so a long path does not push the end of a command
        # out of its 80 characters (a path that only starts with it, the card'"'"'s <worktree>.wide, is kept).
        def tree: if $wt == "" or . == "" then . else split($wt) as $p | reduce $p[1:][] as $x ($p[0];
          . + (if $x | test("^($|[/\\s;&|)\"'"'"'])") then "worktree" else $wt end) + $x) end;
        def short: tostring | gsub("\\s+"; " ") | tree | .[0:80];
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
        # A line with nothing in it is no output: a session that stalls may still be sent such lines, and stays silent. A line this cannot read (JSON that is no event object, or an event of a shape it does not know) is passed over, still output (last): its error failed each later look, which read it again, so the live record stopped there for the rest of the session (issue 1524).
        [inputs] as $ls | reduce $ls[] as $l ($st; . as $kept | try (
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
            # A Claude turn'"'"'s result: its whole usage (rdone, the sum of the results so far), with the answers after the last result added (rbase: the answers'"'"' sum at it), is the reading when its
            # answers report less (a route whose stream gives every answer usage 0, #391). The last result'"'"'s modelUsage (mu), its usage readable or not, with each model'"'"'s answers after it (rbm), is the split by model the Board prices (stats.byModel, as sessionread.jq gives it).
              elif $e.type == "result" then (if ($e.usage | type) == "object" then .rdone = ((.rdone // u0) | plus($e.usage | use)) | .rbase = sofar else . end) | .rbm = bym | .mu =($e.modelUsage | if type == "object" then with_entries(.value |= {input: ((.inputTokens? | numbers) // 0), write: ((.cacheCreationInputTokens? | numbers) // 0), read: ((.cacheReadInputTokens? | numbers) // 0), output: ((.outputTokens? | numbers) // 0)}) else null end)
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
                (if .id == $e.message.id then . else (.cur // {}) as $c | .done = ((.done // u0) | plus($c)) | .bmd = bym | .turns += 1 end)
                | .id = $e.message.id | .cm = ($e.message.model | if type == "string" and . != "" then . else $st.model // "" end) | .cur = ($e.message.usage | use) | .cur as $c | .usage = (.done | plus($c))
                | (($e.message | act) // .action) as $a | if $a == null then . else .action = $a end
              else . end) catch $kept)
          | if (.rdone | type) == "object" then (.rbase // u0) as $b | (sofar | minus($b)) as $a | (.rdone | plus($a)) as $r | (if (.usage // {} | del(.cost) | [.[]] | add // 0) < ($r | [.[]] | add) then .usage = $r else . end) else . end
          | bym as $now | (.rbm // {}) as $was | if (.mu | type) != "object" then . else .stats.byModel = (reduce ($now | keys[]) as $k (.mu; ($now[$k] | minus($was[$k] // u0)) as $d | if $was[$k] != null and ($d | add) == 0 then . else .[$k] = ((.[$k] // {input: 0, write: 0, read: 0, output: 0}) | .input += $d.input | .write += $d.write + $d.write1h | .read += $d.read | .output += $d.output) end) | with_entries(.key as $k | .value += (if $now[$k] == null then {} else {write1h: $now[$k].write1h} end)) | del(.["<synthetic>"])) end
          # zero: a Claude session whose answers so far all report usage 0, and no result yet: its cost is read when its step ends (sofar in snapshot.sh), not "no reading yet".
          | .zero = (.id != null and (.usage // {} | [.[] | numbers] | add // 0) == 0)
          | if any($ls[]; test("\\S")) then .last = ([($t | todate), (.last // "")] | max) else . end' 2>/dev/null) && [ -n "$new" ] && st=$new && have=$n && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"
    fi; [ "$4" = review ] || [ $((EPOCHSECONDS - cpt)) -lt $((SESSION_STUCK / 10)) ] || { cpt=$EPOCHSECONDS; cpu=$(p_cpurose "$pid" "$cpu") && new=$(jq -c --argjson t "$cpt" '.cpuAt = ($t | todate)' <<<"$st") && [ -n "$new" ] && st=$new && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"; } # a session's CPU use, a sign of life beside its output (health): read from the first look on, each tenth of SESSION_STUCK, its last use is cpuAt, the look that read it (p_cpurose())
    [ $((EPOCHSECONDS - seen)) -ge "$STUCK" ] || continue
    at=$(holds "$wt")
    if [ "$at" -gt "$seen" ]; then
      seen=$at
      new=$(jq -c --argjson t "$seen" '.progress = ($t | todate)' <<<"$st") && st=$new && printf '%s\n' "$st" > "$out.tmp" && mv -f "$out.tmp" "$out"
    fi
    [ $((EPOCHSECONDS - seen)) -ge "$STUCK" ] || continue
    jq -rn --argjson s "$seen" '$s | todate' > "$wt.stalled"; kill "$pid" 2>/dev/null; wait "$pid"; rc=$?; break
  done
  # A run given TEST_GIVEN files that ended between two looks (a fast runner that ran more and exited) is counted once more, whole, and file by file (wideeach()): over the count, it is a wide run all the same.
  [ "$4" != test ] || [ -z "${TEST_GIVEN:-}" ] || [ -e "$wt.wide" ] || wideeach "$wt" "$wk" > /dev/null || { mapfile -t logs < <(testlogs "$wt"); wn=$(testprogress "$f" "${logs[@]}" | jq -r --argjson st "$st" '[.run + (.over // 0), .of // $st.list.files // 0] | max' 2>/dev/null); ! [[ $wn =~ ^[0-9]+$ ]] || [ "$wn" -le "$TEST_GIVEN" ] || echo "$wn" > "$wt.wide"; }
  WATCHED=$st; rm -f "$out" "$out.tmp"; return $rc # WATCHED: the last record of the live file, which goes now, for liveusage() in the caller's shell (codexreview()); empty when none was written
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
SESSIONREAD=$(<"$HERE/jq/sessionread.jq") SESSID='first(inputs | fromjson? | objects | .session_id | strings | select(test("^[0-9A-Za-z-]+$")))' # SESSID: the session id a Claude output's events name
# A Claude session's fields when its output holds no token usage: Claude Code's own transcript of that session is
# read with SESSIONREAD (each answer once: the usage of its last event), and its tokens, usage, cacheFirst and the models
# that ran take the place of unread, so the step is priced. The transcript is <account folder, ~/.claude for the default
# login>/projects/<the worktree's real path, each character but a letter or digit made ->/<session id>.jsonl, the id the
# output's events name. Fields that hold a usage, an output that names no session, and a transcript that is missing or
# holds no whole usage leave the fields as they are (unread says why).
transcribed() { # <the step's fields> <output file> <worktree> <account folder, "" for the default login>
  local id p t u
  if jq -e '(.usage | type) != "object"' <<<"$1" >/dev/null 2>&1 \
    && id=$(jq -rRn "$SESSID" "$2" 2>/dev/null) && [ -n "$id" ] \
    && p=$(cd "$3" 2>/dev/null && pwd -P) && t=${4:-$HOME/.claude}/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$p")/$id.jsonl && [ -s "$t" ] \
    && u=$(jq -cRn --arg m "$(jq -r '.model // ""' <<<"$1")" --arg e "" --argjson s 0 "$SESSIONREAD" "$t" 2>/dev/null | tail -n 1 \
      | jq -ce 'select((.usage | type) == "object" and .unread == null) | {tokens, usage, cacheFirst, stats: (.stats // {} | {models, byModel, cacheHit})}' 2>/dev/null); then
    jq -c --argjson u "$u" 'del(.unread) + {tokens: $u.tokens, usage: $u.usage} + (if $u.cacheFirst == null then {} else {cacheFirst: $u.cacheFirst} end) | .stats = ((.stats // {}) + $u.stats)' <<<"$1"
  else printf '%s\n' "$1"; fi
}
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
# goes; a line that cannot be written is said, and the stop goes on. A build, fix or rebase whose output holds no usage yet is read from its transcript (transcribed()), on the account its worktree line names (the loop's own ACCT is the default), and one still with no price keeps its output (outkeep()), as a session's line does; a review still with no price keeps its events and err (reviewkeep()). A line with no usage read still names the model, so the Board can price it at that model's median (estimate_rest()).
stopped() { # <card> <issue>
  local wt=$CARDS/$1 last of o f m e s x roll run='' kn='' ft=$CARDS/$1.firsttry
  last=$(stdb ask last "$1" 2>/dev/null)
  [ "$(jq -r '.step' <<<"${last:-null}" 2>/dev/null)" = start ] || return 0
  # shellcheck disable=SC2034 # PICK and PICKCARD are read by line() in lib/records.sh
  local PICK='' PICKCARD=''; heldpick "$1" # the stopped line carries the card's pick (heldpick(), lib/records.sh)
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
    f=$(jq -cRn --arg m "$m" --arg e "" --argjson s "${s:-0}" --argjson run "${run:-null}" "$CODEXREAD" "$wt.out" 2>/dev/null | tail -n 1 | jq -c 'del(.ok) | del(.effort)' 2>/dev/null); elif [ "$of" != review ] && [ ! -s "$wt.out" ] && unpricedleft "$wt"; then f=$(jq -ce --argjson s "${s:-0}" 'objects | del(.step, .ok, .effort, .start) | .sec = $s' "$wt.spent" 2>/dev/null) || f='' # stopped in a later try's wait, that try with no output (refused on stderr alone), and a try before it with no price left its output (unpricedleft(), lib/records.sh): the line is what apitries() folded of the tries ($wt.spent), its seconds from the step's start as the waits count too, and outkeep() keeps that output before clean() removes it
  else case $of:$m in
    build:opencode:* | fix:opencode:* | rebase:opencode:*) [ -s "$wt.out" ] || return 0
      f=$(jq -cRn --arg m "$m" --argjson s "${s:-0}" "$OPENCODEREAD" "$wt.out" 2>/dev/null | tail -n 1 | jq -c 'del(.ok)' 2>/dev/null) ;;
    # A Claude review is read as a session is, from its events.
    build:* | fix:* | rebase:* | review:claude-*) o=$wt.out; [ "$of" != review ] || o=$wt.events; [ -s "$o" ] || return 0
      f=$(jq -cRn --arg m "$m" --arg e "$e" --argjson s "${s:-0}" "$SESSIONREAD" "$o" 2>/dev/null | tail -n 1 | jq -c 'del(.ok) | del(.effort)' 2>/dev/null); [ "$of" = review ] || { x=$(stdb ask card "$1" 2>/dev/null | jq -rs 'map(select(.step == "worktree")) | last | .account // ""' 2>/dev/null) && x=$(acctenv "$x" 2>/dev/null) || x=''; f=$(transcribed "$f" "$o" "$wt" "$x"); } ;;
    review:opencode:*) [ -s "$wt.events" ] || return 0
      f=$(jq -cRn --arg m "$m" --arg e "$e" --argjson s "${s:-0}" "$OCREVIEWREAD" "$wt.events" 2>/dev/null | tail -n 1 | jq -c 'del(.effort)' 2>/dev/null) ;;
    review:*) [ -s "$wt.events" ] || return 0
      # A review stopped before its turn completed: its running total from its session file (as review() reads it), else its live file's.
      roll=$(rollout "$wt.events"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); rm -f "$roll"; }
      [ -n "$run" ] || run=$(liveusage "$wt.live")
      f=$(jq -cRn --arg m "$m" --arg e "$e" --argjson s "${s:-0}" --argjson run "${run:-null}" "$REVIEWREAD" "$wt.events" 2>/dev/null | tail -n 1 | jq -c 'del(.effort)' 2>/dev/null) ;;
    *) return 0 ;;
  esac; fi
  [ -n "$f" ] || f=$(jq -cn --argjson s "${s:-0}" --arg m "$m" '{model: $m, sec: $s, unread: "the output of the stopped session could not be read"}')
  [ -n "$m" ] || f=$(jq -c 'del(.model)' <<<"$f")
  # Stopped while a review ran again: the failed first attempt (reviewed()) is on the line, its tokens counted. A review still with no price then keeps its events and err, which clean() removes next (reviewkeep(); outkeep() keeps no review's): its reason names them.
  [ "$of" != review ] || { { ! x=$(jq -ce objects "$ft" 2>/dev/null) || f=$(jq -c --argjson f "$x" "$BOTHTRIES" <<<"$f"); }; [ ! -e "$wt.events" ] || ! jq -e '(.usage | type) != "object" or (.unread | type) == "string"' <<<"$f" >/dev/null 2>&1 || kn=$(reviewkeep "$wt" ""); }
  f=$(line "$1" "$2" "$of" stopped "$(jq -c --arg k "$kn" '. + {reason: ("stopped by control stop while it ran" + $k)}' <<<"$f")") && locked append "$f" && { outkeep "$1" "$of" "$f" || :; } \
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
TRYFOLD=$(<"$HERE/jq/tryfold.jq") # the jq defs the two folds of a step's tries share: APIFOLD, below, and BOTHTRIES (lib/review.sh, sourced after this file)
# A step's fields with those of the tries the API refused before it ($p) folded in. As with a review's two attempts
# (BOTHTRIES): when a refused try's usage is unknown or only part of it, or it ran on another model, unread says so,
# so the step is priced as an estimate, never as exact; the usage counted is kept (one try's alone when the other's is unknown, with its split; a try's on another model in alsoUsed, with its split: TRYFOLD). An OpenCode cost (usage.cost) is the sum when both report one, else left out. A resumed try (session1()) leaves it resumed.
APIFOLD="$TRYFOLD"'
  .sec += $p.sec | keepfirst($p) | (if .tokens != null or $p.tokens != null then .tokens = add2(.tokens; $p.tokens) else . end) | (if $p.resumed then .resumed = $p.resumed else . end) | .alsoUsed = ((.alsoUsed // []) + ($p.alsoUsed // []))
  | if $p.model != null and $p.model != .model then .unread //= otherwhy($p; "a try the model API refused") | if ($p.usage | type) == "object" then .alsoUsed += [also($p)] else . end
    elif (.usage | type) == "object" and ($p.usage | type) == "object" then fold($p)
      | if $p.unread then .unread //= $p.unread else . end
    elif ($p.usage | type) == "object" then took($p) | .unread //= ($p.unread // "the token usage of the try after the one the model API refused could not be read")
    else .unread //= ($p.unread // "the token usage of a try the model API refused could not be read") end | if .alsoUsed == [] then del(.alsoUsed) else . end'
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
  local wt=$1 st=$2 o=$3 t rc api try=0 w at used=null s codex=false said APIRESUME='' APIRESUMED=''; shift 3
  # Codex's words are read as Codex's (APISAID) for a Codex review and for a session on a Codex builder model alike.
  case $1 in
    codexreview) codex=true ;;
    session1) [ "$(seat "${5:-builder}" | jq -r .agent 2>/dev/null)" != codex ] || codex=true ;; # its seat (session1's 4th argument)
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
    # The API refused it: not a CLI that stopped before any work (nostart()), so no check session puts the card back. A try that failed on the subscription login and then through the proxy (bothsaid()) keeps the login's cause on the reason of the fifth. The reason of a Codex review holds none of Codex's words (a URL in them can hold a credential, and a reason goes to a GitHub comment): it names the events file kept for its last try (keptnote(), reviewkeep(), lib/review.sh).
    jq -c 'del(.start)' "$wt.spent" > "$wt.spent.new" 2>/dev/null && mv -f "$wt.spent.new" "$wt.spent" || rm -f "$wt.spent.new"
    s=$APIERR.$BASHPID; jq -n --argjson p "$API_PAUSE" 'now + 5 * $p' > "$s" 2>/dev/null && mv -f "$s" "$APIERR" || rm -f "$s"
    # A review that wrote its verdict and then failed (1, not 2) answered: its API error is marked as any is, so the
    # queue pauses, but it is never run again.
    [ "$st" != review ] || [ $rc = 2 ] || { printf '%s\n' "$t"; return $rc; }
    [ $try -lt 4 ] || { s=''; [[ $t != 'on the subscription login, '* ]] || { s=${t%%$'\n'*}; s=", through the proxy; ${s%%; through the proxy, *}"; [[ $t != *$'\n'* ]] || s+=$'\n'${t#*$'\n'}; }
      printf 'the model API refused (%s) at each of 5 tries, made %ss, then 2, 4 and 8 times that, apart%s\n%s\n' "$api" "$API_PAUSE" "$s$(keptnote "$t")" "$([ "$1" = codexreview ] || jq -rRn --argjson codex "$codex" --rawfile e "$wt.err" "$APISAID" "$said" 2>/dev/null | tail -n 60)"; return 1; }
    read -r w at <<<"$(jq -rn --argjson p "$API_PAUSE" --argjson t "$try" '($p * pow(2; $t)) as $w | "\($w) \(now + $w | floor)"')"
    try=$((try + 1)); used=$(jq -c 'del(.step)' "$wt.spent"); APIRESUME=1; APIRESUMED=''; jq -e '.resumed' <<<"$used" >/dev/null 2>&1 && APIRESUMED=1 # each retry of a Claude build resumes the refused session by the id its output names (session1(); other agents and steps run again from nothing), so a try refused before it named one leaves the resume to the next; a resumed try is the step's one resume, so no later try resumes (APIRESUMED)
    jq -cn --arg s "$st" --arg a "waiting: the model API refused ($api); trying again at $(p_date "@$at" +%H:%M)" --slurpfile u "$wt.spent" \
      '{step: $s, at: (now | todate), last: null, turns: 0, model: $u[0].model, action: $a} + (if ($u[0].effort | type) == "string" and $u[0].effort != "" then {effort: $u[0].effort} else {} end)' > "$wt.live.tmp" && mv -f "$wt.live.tmp" "$wt.live"
    sleep "$w"; [ "$o" != "$wt.out" ] || [ ! -e "$wt.out.unpriced" ] || outfirst "$wt" # the refused try's output, when its own fields (session1(), not $wt.spent, which holds the tries before it too) have no price to read, before the next try writes over it: after the wait, as a stop in it (stopped()) keeps <worktree>.out itself, and a copy made before would be kept twice (outkeep(), lib/records.sh)
  done
}
# The worktree's tree before the session is kept in <worktree>.before (treeof(), lib/donewhen.sh), so donewhen.sh asks() can tell a
# session that changed nothing from one that found a change already there.
# The session runs on the seat named (seat(): fix, the repair of review findings, or testFix, the repair of failed
# changed tests), else the builder's. With up as its 5th argument it runs one effort level above the seat's (session1()). It does not start when its card or its issue is at a dollar limit: it prints why and fails (usdstop(), lib/records.sh).
session() { # <worktree> <prompt> [step: build (when none is given), fix or rebase] [seat: builder (the default), fix or testFix] [up]
  local p=$2; newtexts p; usdstop "$1" || return 1
  treeof "$1" > "$1.before" 2>/dev/null || rm -f "$1.before"; rm -f "$1.out.first" "$1.out.first-"* "$1.out.unpriced"
  apitries "$1" "${3:-build}" "$1.out" session1 "$1" "$p" "${@:3}"; local rc=$?; rm -f "$1.out.unpriced"; replyout "$1"; return $rc # replyout: the draft reply precheck left out, out of the change (lib/donewhen.sh). <worktree>.out.unpriced marks one try for apitries() and session1() alone: removed here, as a blocked card keeps the worktree's other files and clean() (lib/push.sh) does not run for it
}
# The texts of a card's prompts that its old code made, each with the one the new code makes in its place, in the
# order of its switches (switchcode(), lib/card.sh); newtexts() puts the new ones in a prompt, in that order.
SWAPOLD=() SWAPNEW=()
newtexts() { # <the name of a variable that holds a prompt>
  local -n fr=$1; local i
  for i in "${!SWAPOLD[@]}"; do fr=${fr//"${SWAPOLD[i]}"/"${SWAPNEW[i]}"}; done
}
# The builder program, the one seat() names for the model (its agent: the CLI the control record names, or the one the
# pack's models.allowed lists the model under): OpenCode, Codex or Claude Code. Run in the background (watch() follows it), so it
# execs the program in its own subshell, which a stall's kill ends, behind the words session1 puts it on the cores left for card work with (KEEP).
# Claude: bypass mode, as any other mode asks before a write under .claude/, and a headless session cannot answer, so
# a tooling card ended with no change; the card hooks (the settings file) still run in this mode. It has none of the
# tools that schedule, message or start other agents (BUILDNOTOOLS): a headless run with a wakeup pending waits for
# it, even past its time limit. WebFetch and WebSearch stay open.
# OpenCode (README.md, OpenCode builder): `opencode run` in the worktree, the prompt on stdin, its events as JSON
# lines; --auto approves what nothing denies, as bypass mode does; the config file (ocready()) loads the guard plugin,
# which runs the same settings file's hooks before each call; the project's own OpenCode config is not read, as a
# Claude session reads no project settings. It runs on no Claude account.
# Codex (README.md, Codex builder): `codex exec --json` in the worktree, the prompt on stdin, its events as JSON lines,
# on the model and effort as a Codex review is; its sandbox lets it write in the worktree, /tmp and $TMPDIR (where the
# brief's background runs and a test run's own scratch folder go) and the machine's test slots folder (slot_pool; the
# host's testSlotsDir may lie outside /tmp), which a test run takes a slot in, and the card's briefs folder, and nowhere
# else (in a benchmark's task container it has no Codex sandbox, the container being the sandbox: codexsb()); its one
# PreToolUse hook, on every tool, is the guard hook (cxready()), which runs the same settings file's hooks before each
# call. Hooks are on, and run without Codex's trust prompt, which a headless session cannot answer; Codex's web search,
# a tool no hook is given, is off. Its commands get no terminal (unified_exec_tty off), so their input is closed:
# write_stdin, which types into a command already running and is given no hook, can only wait for output, and Codex
# refuses keys sent with it (a Codex without the feature fails to start). It runs on no Claude account.
RESUMEBRIEF='Your session was cut off (it made no progress for a while, or the model API refused it) and is now resumed. The worktree holds what you did so far: go on with the task from where you stopped, and end as the brief asks.' # what a resumed build session is told (session1())
BUILDNOTOOLS=Agent,ScheduleWakeup,CronCreate,CronDelete,CronList,Monitor,RemoteTrigger,PushNotification,SendMessage,ListAgents,Workflow
sq() { local q="'"; printf "'%s'" "${1//$q/$q\\$q$q}"; } # <word>: it single-quoted for a shell
builder() { # <worktree> <prompt> <model> <effort> <account folder> <agent: claude, opencode or codex> [Claude session id to resume]
  local h a=()
  cd "$1" && mkdir -p "$1.briefs" || exit 1; ! "${HERE%/*}/bin/ast-grep" --version >/dev/null 2>&1 || export PATH="${HERE%/*}/bin:$PATH" # PATH: the plugin's bin/ when ast-grep is installed (bin/ast-grep runs), for each CLI, so the session runs `ast-grep` by name: a card session loads no plugin, so its CLI puts no bin/ there
  export CONVEYOR_CARD=${1##*/} CONVEYOR_BRIEFS=$1.briefs CONVEYOR_TESTSTEPONLY=0; ! teststeponly || CONVEYOR_TESTSTEPONLY=1 # BRIEFS: kept long outputs (tools/outbrief.sh), gone with the card. TESTSTEPONLY: the rule Only the Test step runs tests (teststeponly(), lib/prompts.sh), 1 on, 0 off whatever the loop inherited, for the card's command guard (.claude/hooks/bash-guardrails.sh), which refuses the session's test commands while it is on.
  case $6 in
    codex) export CLAUDE_PROJECT_DIR=$1
      # The hook's command, each word single-quoted for the shell Codex runs it with, as a TOML string (JSON's escapes are TOML's).
      h=$(jq -rn --arg c "node $(sq "$CX_GUARD") $(sq "$1.settings") $(sq "$1")" \
        '"[{matcher = \"*\", hooks = [{type = \"command\", command = \($c | @json), timeout = 600}]}]"') || exit 1
      # A pool that cannot be made is left out: a test run then says why it takes no slot.
      ! slot_pool >/dev/null 2>&1 || a=(--add-dir "$SLOT_DIR"); a+=(--add-dir "$CONVEYOR_BRIEFS")
      codexargs # its provider, when its route is the proxy
      codexsb workspace-write
      exec "${KEEP[@]}" timeout --kill-after=30 "$BUILD_TIMEOUT" codex exec --json "${CODEX_SB[@]}" -C "$1" "${a[@]}" "${CODEX_PX[@]}" -m "$3" -c "model_reasoning_effort=\"$4\"" \
        -c 'web_search="disabled"' \
        --enable hooks --dangerously-bypass-hook-trust --disable unified_exec_tty -c "hooks.PreToolUse=$h" - <<<"$2" > "$1.out" 2> "$1.err" 8>&- ;;
    opencode) export CLAUDE_PROJECT_DIR=$1 CONVEYOR_GUARD_SETTINGS=$1.settings OPENCODE_CONFIG=$1.opencode.json OPENCODE_DISABLE_PROJECT_CONFIG=1
      exec "${KEEP[@]}" timeout --kill-after=30 "$BUILD_TIMEOUT" opencode run --model "${3#opencode:}" --format json --auto <<<"$2" > "$1.out" 2> "$1.err" 8>&- ;;
    *) proxyenv && acctrun "$5" || exit 1; [ -z "${7:-}" ] || a=(--resume "$7") # the session it resumes (session1())
      exec "${KEEP[@]}" timeout --kill-after=30 "$BUILD_TIMEOUT" claude -p "${a[@]}" --model "$3" --effort "$4" --permission-mode bypassPermissions --disallowedTools "$BUILDNOTOOLS" \
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
  local model effort agent rc s sec f dir='' x='' read=$SESSIONREAD roll run role=${4:-builder}
  s=$(seat "$role") && jqget "$s" model model effort effort agent agent || { echo "the pack's models.allowed lists no builder model"; return 1; }
  # The CLI the seat names, never another: one that is gone starts no session; one gone for a moment is waited for (seatwait()).
  # A second fix round (5th argument up) runs one effort level above the seat's, inside the pack's range (effortup()).
  f=$(seatwait "$role" "$s" "$1" "${3:-build}") || { echo "$f"; return 1; }; [ "${5:-}" != up ] || [ -z "$effort" ] || effort=$(effortup "$agent" "$model" "$effort")
  # OpenCode takes no effort here; OpenCode and Codex run on no Claude account. A Codex model named by its family is the newest of it (codexmodel()).
  case $agent in
    opencode) effort=''; read=$OPENCODEREAD; f=$(ocready "$1") || { echo "$f"; return 1; } ;;
    codex) read=$CODEXREAD; model=$(codexmodel "$model") || { echo "$model"; return 1; }; f=$(cxready "$1") || { echo "$f"; return 1; } ;;
    *) dir=$(acctenv "$ACCT") || { echo "$dir"; return 1; } ;;
  esac
  rm -f "$1.spent" "$1.stalled"
  # The session runs on the cores left for card work (lib/slots.sh slot_keepwords).
  local KEEP bp p rid rd='' k; slot_keepwords
  # A session that stalls (watch()) is ended and runs once more after REVIEW_PAUSE, as a review with no verdict does
  # (reviewed()), on what it left in the worktree; the stalled try is firstTry on the step's line (BOTHTRIES), its output kept (outfirst(), lib/records.sh) when it has no price to read, for outkeep() (apitries() does the same for each try the API refused), and stalls counts the stalls. A second stall fails the step. Each try starts with no guard failure (<worktree>.guardfail): one of the stalled try does not count against the next.
  # A Claude build session cut off by a stall, or by the model API (APIRESUME: apitries()'s retries), is resumed once by the session id its output names (claude --resume, told RESUMEBRIEF), not run again from nothing: its line has resumed 1.
  # What a try left running in the card's folders as it ends (a test it started under timeout, in a process group of its own) is ended then (leftin(), lib/run.sh), before the next try reads the worktree or block() takes it away.
  while :; do
    sec=$SECONDS; p=$2 rid=''; rm -f "$1.guardfail"; [ -z "$rd" ] && [ -z "${APIRESUMED:-}" ] && [ "$agent" = claude ] && [ "${3:-build}" = build ] && [ -n "${APIRESUME:-}$x" ] && rid=$(jq -rRn "$SESSID" "$1.out" 2>/dev/null) && [ -n "$rid" ] && p=$RESUMEBRIEF rd=1
    builder "$1" "$p" "$model" "$effort" "$dir" "$agent" "$rid" & bp=$!
    watch $bp "$1.out" "$1.live" "${3:-build}" "$model" "$agent" "$effort"; rc=$?; sec=$((SECONDS - sec))
    ! declare -F leftin >/dev/null || { k=$(for p in $(leftin "${1##*/}"); do freeze "$p"; done); [ -z "$k" ] || kill -KILL $k 2>/dev/null; }
    # A Codex session cut off before its turn completed: its running total, from the session file Codex keeps (read
    # and removed, as a review's is).
    run=''; [ "$agent" != codex ] || { roll=$(rollout "$1.out"); [ -z "$roll" ] || { run=$(grep '"token_count"' "$roll" | tail -n 1 | jq -c '.payload.info.total_token_usage | objects' 2>/dev/null); rm -f "$roll"; }; }
    # The step's fields, however it ended (SESSIONREAD, OPENCODEREAD, CODEXREAD): one JSON object, always, so the line is always written.
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s "$sec" --argjson run "${run:-null}" "$read" "$1.out" 2>/dev/null | tail -n 1)
    jq -e 'objects | has("ok")' <<<"$f" >/dev/null 2>&1 \
      || f=$(jq -cn --arg m "$model" --arg e "$effort" --argjson s "$sec" '{model: $m, effort: $e, sec: $s, unread: "the session output could not be read", ok: false}
          | if $e == "" then del(.effort) else . end')
    [ "$agent" != claude ] || [ -n "$rid" ] || f=$(transcribed "$f" "$1.out" "$1" "$dir"); rm -f "$1.out.unpriced"; ! jq -e "$UNPRICED" <<<"$f" >/dev/null 2>&1 || : > "$1.out.unpriced" # transcribed not for a resumed try (rid): its transcript holds the earlier try, which BOTHTRIES or APIFOLD adds; a fresh try after it has its own. <worktree>.out.unpriced: this try's own price, before BOTHTRIES or APIFOLD adds an earlier try's, is not to read, so its output is kept for that (outfirst(), lib/records.sh), and not one an earlier try lacked usage for
    [ -z "$x" ] && [ -e "$1.stalled" ] || break
    x=$(jq -c --arg r "stalled at ${3:-build}: no progress since $(<"$1.stalled")" '{reason: $r, spent: del(.ok)}' <<<"$f")
    echo "conveyor: card ${1##*/}: its ${3:-build} made no progress for ${STUCK}s: ended, and run once more after ${REVIEW_PAUSE}s" >&2
    sleep "$REVIEW_PAUSE"; [ ! -e "$1.out.unpriced" ] || outfirst "$1" # after the pause, as apitries() does: a stop in it keeps <worktree>.out once
  done
  [ -z "$x" ] || f=$(jq -c --argjson f "$x" --argjson n "$([ -e "$1.stalled" ] && echo 2 || echo 1)" "$BOTHTRIES"' | .stalls = $n' <<<"$f"); [ -z "$rd" ] || f=$(jq -c '.resumed = 1' <<<"$f")
  [ "$agent" != claude ] || proxypack
  [ "$agent" = opencode ] || f=$(routed "$f" "$agent")
  s=$(awk -F'\t' '++n[$1] == 2 { print "guard " $1 " is failing: " $2; exit }' "$1.guardfail" 2>/dev/null); rm -f "$1.guardfail" # guardrun.sh: blocks the card
  [ -z "$s" ] || { [ "$agent" != claude ] || routedone 1; jq -c --arg st "${3:-build}" '{step: $st} + del(.ok)' <<<"$f" > "$1.spent"; printf '%s\n' "$s"; return 1; }
  # A session whose last result says it succeeded goes on, its usage or stats read or not (unread says why not).
  if [ $rc = 0 ] && [ "$(jq -r .ok <<<"$f")" = true ]; then [ "$agent" != claude ] || routedone 1; jq -c 'del(.ok)' <<<"$f"; return 0; fi
  # A session that failed still spent its tokens and seconds: block() records them.
  jq -c --arg st "${3:-build}" '{step: $st} + del(.ok)' <<<"$f" > "$1.spent"
  [ -z "$x" ] || [ ! -e "$1.stalled" ] || { echo "stalled twice at ${3:-build}: no progress since $(<"$1.stalled")"; return 1; }
  if nostart "$rc" "$f" "$1.out" "$1.err" "$agent" "$model" "$role" "$([ "$agent" != claude ] || printf '%s' "$ACCT")" "$1"; then
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
# The words of a CLI that failed, fit to keep in a record or to show: the last 12 lines of <text> that are not blank,
# each cut at 300 characters, with the user's home written ~, what looks like a credential (a value after key, token,
# secret, password or authorization and a colon or =, quoted or not, one after Bearer, a run of 24 or more letters,
# digits, - and _) left out, and every line the privacy check's patterns hit left out (nostart(), bench/swe.sh).
cliwords() { # <text>
  local words hits
  # Cut after what is left out, so no part of a credential cut short is kept.
  words=$(jq -rRs --arg h "${HOME:-}" '[splits("\n") | select(test("\\S"))] | .[-12:][]
      | if $h != "" then split($h) | join("~") else . end
      | gsub("(?<k>(key|token|secret|password|authorization)[\"'"'"']?\\s*[:=]\\s*(bearer\\s+)?)(\"([^\"\\\\]|\\\\.)*\"?|'"'"'[^'"'"']*'"'"'?|[^\\s\"'"'"',;\\[]+)"; "\(.k)[left out]"; "i")
      | gsub("(?<k>bearer\\s+)[^\\s\"'"'"',;\\[]+"; "\(.k)[left out]"; "i")
      | gsub("[A-Za-z0-9_-]{24,}"; "[left out]") | .[0:300]' <<<"$1" 2>/dev/null) || words=''
  [ -n "$words" ] || return 0
  hits=$(printf '%s\n' "$words" | "$HERE/privacy/check.sh" -)
  if [ $? -gt 1 ]; then echo '[left out: the privacy check could not be made]'
  else printf '%s\n' "$words" | H=$hits awk 'BEGIN { n = split(ENVIRON["H"], l, "\n"); for (i = 1; i <= n; i++) if (split(l[i], p, ": ") >= 2) { sub(/^-:/, "", p[1]); bad[p[1] + 0] = p[2] } }
    { if (NR in bad) print "[a line left out: " bad[NR] "]"; else print }'; fi
}
# A session or review that failed (its exit not 0 and not the timeout's 124) with no turn past its first and no token
# never began its work: its CLI stopped before it (not logged in, a model this account does not have, a settings
# error, a kill). Sets NOSTART_WHY to its reason: the cause, named from its exit (137 or 143: a signal ended it, on any
# route) or else from the CLI's own words (a session through a proxy or the
# API: that route at its base URL, never a sign-in to it), its exit and what to do; under it those words (NOSTARTSAID,
# then the last lines of its stderr) as cliwords() keeps them. Sets NOSTART_START to the seat (builder or reviewer),
# CLI, model and account it ran on: a check session on that seat as it is set then runs before the card is put back
# (startagain(), startnow()). Fails, setting neither, for any other session. NOSTART_LOGIN: the login's state when
# the cause is the login (expired: its words say expired, refresh, revoked or refused; else not set), else empty.
# NOSTART_SIGNIN, when the cause is the login: the sign-in failure (expired, was refused or is missing) and what to
# run, for the pause (signinstop()); NOSTART_START then has signin: true, so a resume puts the card back
# (signinback(), which alone puts back a card of issue 0: no check session does). Else empty.
nostart() { # <exit> <the step's fields> <output file> <stderr file> <cli> <model> <builder|reviewer|fix|testFix> <account, "" for the default login> <worktree>
  local raw words cause todo n p px c=${9##*/}
  NOSTART_LOGIN='' NOSTART_SIGNIN=''
  [ "$1" != 0 ] && [ "$1" != 124 ] && [ ! -e "$9.stalled" ] || return 1
  jq -e '([.tokens // {} | .[] | numbers] | add // 0) == 0 and (.stats.turns // 0) <= 1' <<<"$2" >/dev/null 2>&1 || return 1
  raw=$( { jq -rRn "$NOSTARTSAID" "$3" 2>/dev/null; tail -n 20 "$4" 2>/dev/null; } | tr -d '\000')
  words=$(cliwords "$raw")
  # The route it took, when that is a proxy or the API: "the proxy at <base URL>" or "the API at <base URL>".
  px=''
  if [ "$5" != opencode ] && [ "$(proxyroute "$5")" = proxy ]; then
    if [ "$5" = codex ]; then p=$(codexproxyset); else p=$(claudeproxy); fi
    px=$(jq -r '"the \(if .kind == "api" then "API" else "proxy" end) at \(.baseUrl // "https://api.anthropic.com")"' <<<"$p")
  fi
  # Exit 137 or 143: a signal (9 or 15) ended the CLI, on any route; its proxy or the API did not.
  if [ "$1" = 137 ] || [ "$1" = 143 ]; then
    if [ "$1" = 137 ]; then cause="the $5 CLI was killed (signal 9)"; else cause="the $5 CLI ended (signal 15)"; fi
    cause+=", not by the proxy or the API"; todo="check for an out-of-memory kill or a stop"
  elif [ "$1" = 127 ] || grep -Eqi "(^|[^a-z])$5: (command )?not found" <<<"$raw"; then
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
  if ! startonce "$n" || { [ -z "$NOSTART_SIGNIN" ] && [ "$n" = "$c" ]; }; then [[ ! $c =~ ^c[0-9]{8}T[0-9]{6}- ]] || todo+=", then retry the card (conveyor.sh retry $n, or Retry on the Board)"
  elif [ -n "$NOSTART_SIGNIN" ]; then todo+=". The card is put back once by itself on resume"
  else todo+=". The card is put back once by itself when a check session on the $7's CLI and model starts"; fi
  NOSTART_WHY="$cause ($(exitsaid "$1" 0)): $todo"$'\n'"${words:-(the $5 CLI wrote nothing)}"
  NOSTART_START=$(jq -cn --arg s "$7" --arg c "$5" --arg m "$6" --arg a "$8" --arg g "$NOSTART_SIGNIN" '{seat: $s, cli: $c, model: $m, account: $a}
    + if $g == "" then {} else {signin: true} end')
}
# After nostart(), for a step that runs nowhere else (no fallback route, or the fallback's own sign-in failed too): a
# sign-in failure pauses the loop with the step and its reason (signinpause()), as every card would meet it.
signinstop() { [ -z "$NOSTART_SIGNIN" ] || locked signinpause "$1: $NOSTART_SIGNIN" || true; } # <step>
# Whether a card blocked by a session that never began its work (nostart()) is still put back by itself (startagain(), signinback()): an issue none of whose cards was put back so,
# or a main-red fix card (issue 0, by its id) none of whose cards for the same main commit (mainRed: redpick() gives each its own id) was put back so, nor the card itself; never another card of issue 0 (a Tests page card, whose retry testpick() limits).
startonce() { # <issue, or the card id of a main-red fix card>
  local n=$1 s=''; [[ $1 =~ ^[1-9][0-9]*$ ]] || { [[ $1 =~ ^c[0-9]{8}T[0-9]{6}-.*-0$ ]] && n=0 && s=$(stdb ask card "$1" 2>/dev/null | jq -rs 'map(.mainRed? | strings) | first // empty' 2>/dev/null) && [ -n "$s" ]; } || return 1
  ! stdb ask issue retried "$n" 2>/dev/null | jq -se --arg c "$1" --arg s "$s" 'group_by(.card)[] | select(.[0].issue != 0 or .[0].card == $c or any(.[]; .mainRed? == $s)) | .[] | select(.step == "blocked" and (.spent.start | type) == "object")' >/dev/null 2>&1
}
# What a check session runs on (startcheck()) for a session that never began its work (nostart()): the CLI and model
# its seat is set to now, so one the owner changed after the block is the one checked, on the account it ran on (none
# for a CLI that is not claude). Fails when the seat is set to none.
startnow() { # <{seat, cli, model, account}>
  local r s m a
  r=$(jq -r '.seat // empty' <<<"$1" 2>/dev/null); [ -n "$r" ] || return 1
  s=$(seat "$r") && jqget "$s" model m agent a || return 1
  # A fix or testFix seat takes the builder's route, as its session does.
  local p=$r; case $r in fix | testFix) p=builder ;; esac
  [ "$a" != codex ] || m=$(PROXY_ROLE=$p codexmodel "$m") || return 1
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
    claude) (cd "$d" && a=$(acctenv "$a") && proxyenv && cacheenv && acctrun "$a" \
      && exec timeout --kill-after=10 120 claude -p --model "$m" --setting-sources "" --strict-mcp-config --no-session-persistence <<<"Reply with the one word OK." >"$d.out" 2>&1 8>&-) ;;
    codex) (cd "$d" && codexargs && exec timeout --kill-after=10 120 codex exec --skip-git-repo-check -s read-only "${CODEX_PX[@]}" -m "$m" - <<<"Reply with the one word OK." >"$d.out" 2>&1 8>&-) ;;
    opencode) (cd "$d" && OPENCODE_DISABLE_PROJECT_CONFIG=1 exec timeout --kill-after=10 120 opencode run --model "${m#opencode:}" <<<"Reply with the one word OK." >/dev/null 2>&1 8>&-) ;;
    *) false ;;
  esac; rc=$?
  # Its login failed and the proxy is its role's fallback: checked again at once through the proxy.
  if loginfallback "$rc" "$cli" "$d.out"; then PROXY_NOW=1 startcheck "$1"; rc=$?; fi
  rm -rf "$d" "$d.out"; return $rc
}
