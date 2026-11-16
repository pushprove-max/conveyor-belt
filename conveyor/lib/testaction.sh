# SPDX-License-Identifier: Apache-2.0
# Test actions (README.md, Test actions): `conveyor.sh testaction <judge|explain> <test file>` asks the Tests seat
# (the control record's tests: {cli, model, effort}) about one test file of the project, in one headless session that
# needs no code review and files no issue: judge (is the file worth its cost: keep, speed up, split, merge or delete)
# or explain (which card and what cause made it slower). With no Tests seat set it starts nothing and says why (exit 2).
# The session is given the file, its recorded times from the test lines of the card records (times, timed, slow), the
# cards that ran it and its flaky entries (testfacts()). It reads a copy of main as it is at the ask, a worktree of
# that commit whose files it cannot write ($CARDS/testactions/<id>, removed when it ends), and finds a gh that refuses
# every call first on its PATH; a Claude session has only Read, Grep and Glob, a Codex one its read-only sandbox and an
# OpenCode one the review's read-only agent (ocrun()). The ask returns once the session has started.
# Each action keeps, in $TESTACTS: <id>.json, its record: {id, action, file, project, start, end (null while it runs),
# state (running, done, stopped, failed or timed out), cli, model, effort, limit (TESTACTION_TIMEOUT, the seconds it
# may run), verdict (judge: the word its text's last line names, VERDICT: <keep | speed up | split | merge | delete>,
# else "no verdict"; explain: null), pid (the process to stop while it runs) and reason (failed: why)}; <id>.txt, the
# session's text, written as the session writes it; <id>.events and <id>.err, the CLI's output and its errors. All of
# it stays after the session ends. `conveyor.sh testaction stop <id>` ends that one session and no other.
# `conveyor.sh testaction run <test file>` is no session: it runs the file alone, now, on a test slot (tafile()).
TESTACTS=${STATE%/*}/testactions
TAVERDICTS='keep|speed up|split|merge|delete'
# The text of a session's output line: Claude's assistant text (stream-json), Codex's agent message (exec --json),
# OpenCode's text part (run --format json); each ended by a newline.
TATEXT='fromjson? // empty | objects | if .type == "assistant" then .message.content[]? | select(.type == "text") | .text | strings | . + "\n"
  elif .type == "item.completed" and .item.type == "agent_message" then .item.text | strings | . + "\n"
  elif .type == "text" then .part.text | strings | . + "\n" else empty end'
TAJUDGE="You judge one test file of this project: is it worth what it costs on every test run? Choose one: keep it, speed it up, split it, merge it with another test file (name that file), or delete it. Give the evidence for your choice: its recorded times below, what it tests, and whether another test already proves the same behaviour. Read the repository as you need. Change nothing: do not write or edit a file, do not file an issue, do not change any state. End your answer with one line: VERDICT: <keep | speed up | split | merge | delete>"
TAEXPLAIN="Explain the slowdown of one test file of this project. From its recorded times below, find when it became slower, which card's change made it slower, and what in that change is the cause. Read the repository and its history as you need. Change nothing: do not write or edit a file, do not file an issue, do not change any state."
# `conveyor.sh testissue <test file> <title> <body>`: the Board's File an issue about one test file (speed up, split,
# merge or delete; the owner read and edited the title and body), filed through the GitHub write path with the pack's
# type and its last priority. Each one filed is kept in $TAFILED, one line {time, event: filed, file, issue}, so the
# file's row has its issue (testspart(): the Board's Close its issue as done). It prints the issue's address.
TAFILED=$TESTACTS/filed.jsonl
testissue() { # <test file> <title> <body>
  local out n
  [ $# = 3 ] && [[ -n ${2//[[:space:]]/} && $2 != *$'\n'* && -n ${3//[[:space:]]/} ]] || { echo "usage: conveyor.sh testissue <test file> <title> <body>" >&2; return 2; }
  [[ -n $1 && $1 != /* && /$1/ != */../* && /$1/ != */./* && $1 != *$'\n'* ]] && [ "$(git -C "$MAIN" cat-file -t "refs/heads/$BRANCH:$1" 2>/dev/null)" = blob ] \
    || { echo "conveyor: $1 is not a file of $BRANCH; nothing filed" >&2; return 2; }
  mkdir -p "$TESTACTS" || { echo "conveyor: the test actions' folder could not be made; nothing filed" >&2; return 1; }
  out=$(gh_write issue create --title "${2:0:200}" --label "$TYPE" --label "$(jq -r '.[-1]' <<<"$PRIOS")" --body "$3" 2>&1); n=$(grep -oE '/issues/[0-9]+' <<<"$out" | tail -n 1); n=${n##*/}
  [ -n "$n" ] || { echo "conveyor: the issue about $1 could not be filed: $out" >&2; return 1; }
  jq -cn --arg t "$(clock)" --arg f "$1" --argjson n "$n" '{time: $t, event: "filed", file: $f, issue: $n}' >> "$TAFILED" \
    || echo "conveyor: #$n is filed, but its record could not be written: the row of $1 does not show it" >&2
  grep -oE '[^[:space:]]*/issues/[0-9]+' <<<"$out" | tail -n 1
}
taput() { printf '%s\n' "$2" > "$1.new" && mv -f "$1.new" "$1" || { rm -f "$1.new"; return 1; }; } # <file> <record>
testaction() { # <judge | explain | run> <test file> | stop <id>
  case ${1:-}:$# in
    stop:2) tastop "$2"; return ;;
    run:2) tafile "$2"; return ;;
    judge:2 | explain:2) ;;
    *) echo "usage: conveyor.sh testaction <judge | explain | run> <test file> | testaction stop <id>" >&2; return 2 ;;
  esac
  local how=$1 f=$2 c s cli model effort id wt facts p out i
  c=$(ctl) || return 1
  s=$(jq -ce '.tests | objects' <<<"$c") \
    || { echo "conveyor: no Tests seat is set (conveyor.sh control tests <cli> <model> [effort], or the Board's Rules tab); no session started" >&2; return 2; }
  jqget "$s" cli cli model model effort effort || return 1
  [ "$effort" != null ] || effort=medium
  out=$(seatready "Tests seat" "$(jq -c '{model, agent: .cli}' <<<"$s")") || { echo "conveyor: $out; no session started" >&2; return 2; }
  [ "$cli" != codex ] || model=$(codexmodel "$model") || { echo "conveyor: $model; no session started" >&2; return 2; }
  # A path of the repo as main has it now: no absolute path, no . or .. part, a file.
  [[ -n $f && $f != /* && /$f/ != */../* && /$f/ != */./* && $f != *$'\n'* ]] && [ "$(git -C "$MAIN" cat-file -t "refs/heads/$BRANCH:$f" 2>/dev/null)" = blob ] \
    || { echo "conveyor: $f is not a file of $BRANCH; no session started" >&2; return 2; }
  facts=$(testfacts "$f") || { echo "conveyor: the records of $f could not be read; no session started" >&2; return 1; }
  id=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n'); wt=$CARDS/testactions/$id
  mkdir -p "$TESTACTS" "$CARDS/testactions/bin" || { echo "conveyor: the test actions' folders could not be made; no session started" >&2; return 1; }
  # The gh the session finds: one that refuses, so it files no issue through gh on its PATH.
  [ -x "$CARDS/testactions/bin/gh" ] || { printf '#!/bin/sh\necho "conveyor: a test action files no issue and changes nothing on GitHub" >&2\nexit 1\n' > "$CARDS/testactions/bin/gh" \
    && chmod +x "$CARDS/testactions/bin/gh"; } || { echo "conveyor: the test actions' gh could not be made; no session started" >&2; return 1; }
  out=$(git -C "$MAIN" worktree add -q --detach "$wt" "refs/heads/$BRANCH" 2>&1 < /dev/null && chmod -R a-w "$wt" 2>&1) \
    || { tadrop "$wt"; echo "conveyor: the copy of $BRANCH the session reads could not be made: ${out:0:300}; no session started" >&2; return 1; }
  if [ "$how" = judge ]; then p=$TAJUDGE; else p=$TAEXPLAIN; fi
  p+=$'\n\n'"$(jq -r --arg f "$f" '"Test file: \($f)\n\nIts recorded times, from the test lines of the card records, oldest first (times: its CPU seconds in that run; timed: its seconds and CPU seconds in a run of a card that changed it; slow: that run found it over its CPU budget):\n"
    + (if .runs == [] then "none recorded" else .runs | map(tojson) | join("\n") end)
    + "\n\nThe cards that ran it: " + (if .cards == [] then "none recorded" else .cards | map("\(.card) (#\(.issue))") | join(", ") end)
    + "\n\nIts flaky entries (a case of it failed and then passed when run again):\n" + (if .flaky == [] then "none" else .flaky | map(tojson) | join("\n") end)' <<<"$facts")"
  # The session's runner holds no descriptor of this process's: the Board's ssh ends with this process, not with it.
  ( trap '' HUP; exec {LOGFD}>&- && exec {LOGFD}>&2
    tarun "$(jq -cn --arg id "$id" --arg a "$how" --arg f "$f" --arg p "$REPO" --arg t "$(clock)" --arg c "$cli" --arg m "$model" --arg e "$effort" --argjson l "$TESTACTION_TIMEOUT" \
      '{id: $id, action: $a, file: $f, project: $p, start: $t, end: null, state: "running", cli: $c, model: $m, effort: $e, limit: $l, verdict: null}')" "$wt" "$p" ) \
    >> "$TESTACTS/$id.err" 2>&1 < /dev/null 8>&- &
  # The record is the runner's to write, first and last: the ask returns once it is there.
  for ((i = 0; i < 100; i++)); do [ ! -s "$TESTACTS/$id.json" ] || break; sleep 0.1; done
  [ -s "$TESTACTS/$id.json" ] || { echo "conveyor: the test action $id did not start: $(tail -n 5 "$TESTACTS/$id.err" 2>/dev/null)" >&2; return 1; }
  echo "$id"
}
# What the session is given of <file>: {runs: each test line that timed it, oldest first, {card, issue, time} and its
# times, timed and slow parts for the file; cards: the cards of those lines, {card, issue}; flaky: the entries of the
# flaky-test record for it or a case of it ("<file>: <case>")}.
testfacts() { # <file>
  local fl
  fl=$(jq -c --arg f "$1" '[.entries | arrays | .[] | objects | select(.case == $f or ((.case | strings) | startswith($f + ": ")))]' "$FLAKY" 2>/dev/null) || fl='[]'
  { olds; recs; } 2>/dev/null | jq -cRn --arg f "$1" --argjson fl "$fl" '[inputs | fromjson? | objects | select(.step == "test")
      | {card, issue, time, times: ((.times | objects | .[$f]) // null), timed: ([.timed | arrays | .[] | objects | select(.file == $f)] | first),
         slow: ([.slow | arrays | .[] | objects | select(.file == $f)] | first)} | select(.times != null or .timed != null or .slow != null) | del(.[] | nulls)]
    | sort_by(.time) | {runs: ., cards: (map({card, issue}) | unique_by(.card)), flaky: $fl}'
}
# The worktree a session read, gone: made writable again, then removed.
tadrop() { chmod -R u+w "$1" 2>/dev/null; git -C "$MAIN" worktree remove --force "$1" 2>/dev/null; rm -rf "$1"; git -C "$MAIN" worktree prune 2>/dev/null; } # <worktree>
# One action's session, in the background: its record written first (running, pid this process), its CLI run under
# TESTACTION_TIMEOUT with its text going to <id>.txt as it comes, and its record written last with how it ended.
# A TERM (tastop()) ends the session: its CLI's process group is told to end, and killed 10 s later if it has not.
tarun() { # <the record> <worktree> <prompt>
  local r=$1 wt=$2 f tp='' tx txp stopped='' rc=0 t0=$EPOCHSECONDS state v=null why=null k acct cli model effort id me=$BASHPID
  trap 'stopped=1' TERM
  jqget "$r" id id cli cli model model effort effort || return 1
  f=$TESTACTS/$id
  taput "$f.json" "$(jq -c --argjson p "$me" '. + {pid: $p}' <<<"$r")" || { tadrop "$wt"; return 1; }
  : > "$f.txt"; acct=$(ctlacct "$(ctl 2>/dev/null)")
  exec {tx}> >(tee -a "$f.events" | jq --unbuffered -Rrj "$TATEXT" >> "$f.txt"); txp=$!
  ( unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; export PATH=$CARDS/testactions/bin:$PATH
    case $cli in
      claude) d=$(acctenv "$acct") || { echo "$d" >&2; exit 1; }
        cd "$wt" && proxyenv && acctrun "$d" && exec timeout --kill-after=30 "$TESTACTION_TIMEOUT" claude -p --model "$model" --effort "$effort" --permission-mode default \
          --tools Read,Grep,Glob --setting-sources "" --strict-mcp-config --no-session-persistence --output-format stream-json --verbose ;;
      codex) cd "$wt" && exec timeout --kill-after=30 "$TESTACTION_TIMEOUT" codex exec --json -s read-only -m "$model" -c "model_reasoning_effort=\"$effort\"" - ;;
      opencode) REVIEW_TIMEOUT=$TESTACTION_TIMEOUT ocrun "$wt" "$model" "$effort" ;;
    esac ) <<<"$3" >&"$tx" 2>> "$f.err" & tp=$!
  [ -n "$stopped" ] || { wait "$tp"; rc=$?; }
  if [ -n "$stopped" ]; then
    # timeout runs in a process group of its own, with its CLI and all the CLI started. A TERM sent again (tastop())
    # no longer cuts the wait short: the record says stopped only once the session has ended.
    trap '' TERM
    kill -TERM -- "-$tp" "$tp" 2>/dev/null
    ( sleep 10; kill -KILL -- "-$tp" "$tp" ) > /dev/null 2>&1 & k=$!
    wait "$tp" 2>/dev/null; kill "$k" 2>/dev/null; wait "$k" 2>/dev/null
  fi
  exec {tx}>&-; wait "$txp" 2>/dev/null
  if [ -n "$stopped" ]; then state=stopped
  elif [ $rc = 124 ] || { [ $rc = 137 ] && [ $((EPOCHSECONDS - t0)) -ge "$TESTACTION_TIMEOUT" ]; }; then state="timed out"
  elif [ $rc = 0 ]; then state=done
  else state=failed; why=$(jq -cn --arg r "exit $rc: $(tail -n 5 "$f.err" 2>/dev/null)" '$r[0:600]'); fi
  if [ "$(jq -r .action <<<"$r")" = judge ]; then
    v=$(grep -v '^[[:space:]]*$' "$f.txt" | tail -n 1 | sed -nE "s/^[[:space:]*\`_>-]*VERDICT:[[:space:]*\`_]*($TAVERDICTS)([^[:alpha:]].*)?$/\1/Ip")
    v=$(jq -cn --arg v "${v,,}" 'if $v == "" then "no verdict" else $v end')
  fi
  taput "$f.json" "$(jq -c --arg t "$(clock)" --arg s "$state" --argjson v "$v" --argjson w "$why" '. + {end: $t, state: $s, verdict: $v} + (if $w == null then {} else {reason: $w} end) | del(.pid)' <<<"$r")"
  tadrop "$wt"
}
# `testaction run <test file>` (README.md, Test actions): the file alone, run now with the pack's test.command, on main
# as it is at the ask, in a worktree of that commit ($CARDS/testactions/<id>, removed when the run ends), on one of the
# machine's test slots, waited for as a card's test step waits for one (tests()). It is no session: it needs no seat.
# The command's CONVEYOR_TEST_RERUN list names the file alone, a `fail` line with no case: on main's clean tree the
# command runs that file whole and nothing else. A path that is not a test file of main (a file whose own name has
# `.test.` or `.spec.`; a helper in a __tests__ folder is not one) is refused (exit 2), and nothing runs. Its record in $TESTACTS/<id>.json, as a session's: {id, action: "run", file, project, start,
# end, state (running, done, stopped, failed or timed out), load (the machine's 1-minute load at the ask), limit
# (TEST_TIMEOUT, the seconds the test run may run once it has its slot, as a card's test step), result (pass
# or fail; null until it ends, and when it did not run), sec (the file's clock seconds as its runner timed it, else the
# command's), cpu (the file's CPU seconds; null when its runner gave none), wait (the seconds it waited for its slot),
# pid (while it runs) and reason (failed: why)}; <id>.txt, the command's output as it writes it, kept when it ends;
# <id>.err, the runner's own errors. A run that passed is a recorded time of the file (beforetimes()). The ask returns
# the id once the run has started.
tafile() { # <test file>
  local f=$1 id i
  [[ -n $f && $f != /* && /$f/ != */../* && /$f/ != */./* && $f != *$'\n'* && ${f##*/} =~ \.(test|spec)\. ]] \
    && [ "$(git -C "$MAIN" cat-file -t "refs/heads/$BRANCH:$f" 2>/dev/null)" = blob ] \
    || { echo "conveyor: $f is not a test file of $BRANCH; nothing run" >&2; return 2; }
  id=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
  mkdir -p "$TESTACTS" "$CARDS/testactions" || { echo "conveyor: the test actions' folders could not be made; nothing run" >&2; return 1; }
  # The runner holds no descriptor of this process's: the Board's ssh ends with this process, not with it.
  ( trap '' HUP; exec {LOGFD}>&- && exec {LOGFD}>&2
    tarunfile "$(jq -cn --arg id "$id" --arg f "$f" --arg p "$REPO" --arg t "$(clock)" --arg l "$(p_load)" --arg lim "${TEST_TIMEOUT:-}" \
      '{id: $id, action: "run", file: $f, project: $p, start: $t, end: null, state: "running", load: ($l | tonumber? // null), limit: ($lim | tonumber? // null),
        result: null, sec: null, cpu: null, wait: null}')" "$CARDS/testactions/$id" ) >> "$TESTACTS/$id.err" 2>&1 < /dev/null 8>&- &
  for ((i = 0; i < 100; i++)); do [ ! -s "$TESTACTS/$id.json" ] || break; sleep 0.1; done
  [ -s "$TESTACTS/$id.json" ] || { echo "conveyor: the test action $id did not start: $(tail -n 5 "$TESTACTS/$id.err" 2>/dev/null)" >&2; return 1; }
  echo "$id"
}
# Each process <pid> started and has not ended, and <pid>: one a line, a parent before its children. Each is stopped
# (STOP) before its children are looked for, so none starts one more unseen: a child started after the look (watch()'s
# timer, every LIVE seconds) was never ended, and held the run's test slot after its record said stopped. The caller
# ends them (taend()).
tatree() { local c; kill -STOP "$1" 2>/dev/null; echo "$1"; for c in $(pgrep -P "$1" 2>/dev/null); do tatree "$c"; done; } # <pid>
# Ends <pid> and each process under it: each is told to end (TERM, to its process group too: timeout makes one for the
# command), then let go on (CONT) to do so, and killed 10 s later if it, or a process of its group, has not ended.
# Returns once they all have.
taend() { # <pid>
  local ps p x i
  ps=$(tatree "$1")
  for p in $ps; do kill -TERM -- "-$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; done
  for p in $ps; do kill -CONT -- "-$p" 2>/dev/null; kill -CONT "$p" 2>/dev/null; done
  for ((i = 0; i < 100; i++)); do
    x=''; for p in $ps; do ! kill -0 "$p" 2>/dev/null && ! kill -0 -- "-$p" 2>/dev/null || x=1; done
    [ -n "$x" ] || break
    [ "$i" != 99 ] || for p in $ps; do kill -KILL -- "-$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done
    sleep 0.1
  done
}
# The run of one file (tafile()), in the background: its record written first (running, pid this process), the file
# run in a process of its own, which holds the test slot (tests()), and its record written last with how it ended. A
# TERM (tastop()) ends the run (taend()); the record says stopped once each process it started has ended, so its slot
# is free again.
tarunfile() { # <the record> <worktree>
  local r=$1 wt=$2 t f id tp rc='' w='' s='' stopped='' state='done' res=null why=null tm x me=$BASHPID
  trap 'stopped=1' TERM
  jqget "$r" id id file t || return 1
  f=$TESTACTS/$id
  taput "$f.json" "$(jq -c --argjson p "$me" '. + {pid: $p}' <<<"$r")" || return 1
  # The command's output (tests(): <worktree>.test), read as it is written.
  ln -sfn "$wt.test" "$f.txt"
  ( x=$({ git -C "$MAIN" worktree add -q --detach "$wt" "refs/heads/$BRANCH" && deps "$wt"; } 2>&1 < /dev/null) \
      || { printf 'the copy of %s it runs in could not be made: %s\n' "$BRANCH" "${x:0:300}" > "$wt.test"; exit 1; }
    printf 'fail\t%s\n' "$t" > "$wt.rerun"
    tests "$wt" test.command alone; x=$?
    printf '%s\t%s\t%s\n' "$x" "$TEST_WAIT" "$TEST_RUN" > "$wt.res" ) & tp=$!
  [ -n "$stopped" ] || wait "$tp"
  if [ -n "$stopped" ]; then
    trap '' TERM
    taend "$tp"; wait "$tp" 2>/dev/null; state=stopped
  elif IFS=$'\t' read -r rc w s < "$wt.res" 2>/dev/null && [ -n "$s" ]; then
    if [ "$rc" = 0 ]; then res='"pass"'; else res='"fail"'; fi
    [ "$rc" != 124 ] || state="timed out"
  else
    state=failed; why=$(jq -cn --arg r "it did not run: $(tail -n 5 "$wt.test" 2>/dev/null)" '$r[0:600]')
  fi
  # The file's own times, as its runner timed it (timed()).
  tm=$(timed "$wt" 2>/dev/null | jq -c --arg t "$t" '.[$t] // {}' 2>/dev/null) || tm='{}'
  { cp -f "$wt.test" "$f.txt.new" 2>/dev/null || : > "$f.txt.new"; } && mv -f "$f.txt.new" "$f.txt"
  taput "$f.json" "$(jq -c --arg t "$(clock)" --arg s "$state" --argjson res "$res" --argjson w "$why" --argjson tm "$tm" --arg sec "$s" --arg wait "$w" \
    '. + {end: $t, state: $s, result: $res, sec: ($tm.sec // ($sec | tonumber? // null)), cpu: ($tm.cpu // null), wait: ($wait | tonumber? // null)}
      + (if $w == null then {} else {reason: $w} end) | del(.pid)' <<<"$r")"
  tadrop "$wt"; rm -rf "$wt".*
}
# `testaction stop <id>`: TERM to that action's runner (tarun(), tarunfile()), again every 2 s while its record says running, for up
# to 40 s; prints the state it ended in. One not running is refused (exit 2) and nothing is stopped.
tastop() { # <id>
  local f=$TESTACTS/$1 r p i
  [[ $1 =~ ^[0-9a-f]{12}$ ]] && r=$(jq -ce 'objects' "$f.json" 2>/dev/null) || { echo "conveyor: there is no test action $1" >&2; return 2; }
  [ "$(jq -r .state <<<"$r")" = running ] && p=$(jq -er '.pid | numbers' <<<"$r") && kill -0 "$p" 2>/dev/null \
    || { echo "conveyor: the test action $1 is not running ($(jq -r .state <<<"$r")); nothing stopped" >&2; return 2; }
  for ((i = 0; i < 400; i++)); do
    [ $((i % 20)) != 0 ] || kill -TERM "$p" 2>/dev/null
    [ "$(jq -r .state "$f.json" 2>/dev/null)" = running ] || { echo "conveyor: the test action $1 is $(jq -r .state "$f.json")"; return 0; }
    sleep 0.1
  done
  echo "conveyor: the test action $1 did not end within 40 s of its stop" >&2; return 1
}
# The actions' records, newest first, as a JSON array (the snapshot's). One whose record says running and whose
# runner is gone (the machine restarted) is failed, saying so. It lists the newest TATEXT_SHOWN, and of the older ones
# only each file's newest judge with a verdict (the Board's issue preview gives the verdict kept for a file); the
# other records stay on disk. Each listed one has text, the last TATEXT_MAX characters of its <id>.txt as it is now
# (null when there is none), and textCut, whether that left some out, so the Board shows the text as it comes and
# keeps it after the end: a result it lists always has its text for View and Copy, after a reload too.
TATEXT_SHOWN=20 TATEXT_MAX=16000
testacts() {
  local a p id t dead=() fs=() tx=()
  [ ! -d "$TESTACTS" ] || fs=("$TESTACTS"/*.json)
  [ -e "${fs[0]:-}" ] || { echo '[]'; return; }
  a=$(jq -cs 'map(objects) | sort_by(.start) | reverse' "${fs[@]}" 2>/dev/null) || { echo '[]'; return; }
  for p in $(jq -r '.[] | select(.state == "running") | .pid | numbers' <<<"$a"); do kill -0 "$p" 2>/dev/null || dead+=("$p"); done
  a=$(jq -c --argjson n "$TATEXT_SHOWN" '($ARGS.positional | map(tonumber)) as $d | map(if .state == "running" and (.pid | IN($d[])) then .state = "failed" | .reason = "its session ended with no record of how: the engine running it was ended" else . end)
    | .[:$n] + (.[$n:] | map(select(.action == "judge" and .state == "done" and (.verdict | strings) != "no verdict")) | group_by(.file) | map(first))
    | sort_by(.start) | reverse' --args "${dead[@]}" <<<"$a") || { echo '[]'; return; }
  for id in $(jq -r '.[] | .id | strings | select(test("^[0-9a-f]{12}$"))' <<<"$a"); do
    [ ! -r "$TESTACTS/$id.txt" ] || tx+=(--rawfile "t$id" "$TESTACTS/$id.txt")
  done
  # A text file gone between the look and the read (a run's, as it ends) costs the texts of this snapshot, not the list.
  for t in 1 0; do
    [ "$t" = 1 ] || tx=()
    jq -c --argjson max "$TATEXT_MAX" "${tx[@]}" '$ARGS.named as $x | map(. + (($x["t\(.id)"] | strings | {text: .[-$max:], textCut: (length > $max)}) // {text: null, textCut: false}))' <<<"$a" 2>/dev/null && return
  done
  echo "$a"
}
