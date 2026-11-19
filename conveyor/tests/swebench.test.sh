#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: `conveyor.sh bench swe` (bench/swe.sh), the SWE-bench Verified benchmark. A fake dataset of 2 tiny tasks
# and a stub harness (CONVEYOR_BENCH_PYTHON) stand in for the real ones; the engine versions are two commits of a
# fixture engine (CONVEYOR_BENCH_SOURCE) whose `run` builds the sandbox's one issue as the commit says. The arms are
# the fixture's (CONVEYOR_BENCH_ARMS: stub arms and the real conveyor and solo arms with nothing to install), and a
# stand-in for Docker runs each container's commands on this machine. No model call and no download: the test stubs
# answer for claude.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The fixture, made once per run (template) and copied: in <folder>/task.git a task repository whose base commit
# holds x.py "bug"; in <folder>/eng.git an engine with commits A (tagged v1.0.0) and B (main, its review stage
# changed): each one's `run` notes "<version> <issue title>" in $SWE_FX/log, waits while $SWE_FX/hold is there, and
# writes the card's records; A lands "fixed" in x.py for every task, B blocks the task proj__a-1 after two NO-GO
# reviews, each read by the judge. <folder>/py is the stub harness: the two tasks, an image that fails when
# $SWE_FX/broken names it, and a grade that resolves a patch holding "fixed" unless $SWE_FX/wrong names the task.
swemake() { # <folder>
  local F=$1 e=$1/eng
  mkdir -p "$F" && git init -q -b main "$F/task" && echo bug > "$F/task/x.py" && git -C "$F/task" add -A && git -C "$F/task" commit -qm base \
    && git clone -q --bare "$F/task" "$F/task.git" && rm -rf "$F/task" || return 1
  mkdir -p "$e/conveyor/lib" && git init -q -b main "$e" || return 1
  cat > "$e/conveyor/conveyor.sh" <<'EOF'
#!/usr/bin/env bash
case $1 in state-dir) echo "$CONVEYOR_MAIN/conveyor/state" ;; run) . "$(dirname "$0")/lib/fake.sh" ;; esac
EOF
  cat > "$e/conveyor/lib/fake.sh" <<'EOF'
V=A
t=$(gh issue list --json title | jq -r '.[0].title'); echo "$V $t" >> "$SWE_FX/log"; echo $$ > "$SWE_FX/pid"
while [ -e "$SWE_FX/hold" ]; do sleep 0.1; done
mkdir -p "$CONVEYOR_MAIN/conveyor/state"
rec() { jq -nc --arg s "$1" --arg r "$2" --arg w "${3:-}" --argjson j "${4:-null}" --arg t "${5:-}" '{card: "c1", issue: 1, step: $s, result: $r, reason: $w, time: "2026-11-01T00:00:00Z", tokens: {claude: 100, codex: 10}}
  + (if $j == null then {} else {judge: $j} end) + (if $t == "" then {} else {tail: $t} end)' >> "$CONVEYOR_MAIN/conveyor/state/cards.jsonl"; }
rec picked ok; rec build ok
# The project name this checkout's loop takes, as the real engine names it (and its machine slot file after it).
(set -- run; HERE=$SWE_SRC; . "$SWE_SRC/lib/paths.sh" && echo "$RTAG" > "$SWE_FX/rtag")
J='{"model":"m","tokens":{"claude":5,"codex":0},"accepted":[],"declined":[]}' # a judge session on the review
if [ "$V" = B ] && [[ $t == *a-1 ]]; then rec review NO-GO '[P1] x.py:1 the fix is wrong' "$J"; rec fix ok; rec review NO-GO '[P1] x.py:1 still wrong' "$J" $'[P1] x.py:1 still wrong\n[P2] y.py:2 past the cut reason'; rec blocked blocked 'review: the last review said NO-GO'; exit 0; fi
cp "$CONVEYOR_MAIN/conveyor/state/control.json" "$SWE_FX/control.seen"; cp "$CONVEYOR_MAIN/.conveyor/project.json" "$SWE_FX/pack.seen"
cat "$HOME/.codex/auth.json" > "$SWE_FX/codex.seen" 2>/dev/null || :
rec review GO '' null 'no findings'; rec test pass '' null 'test output'; echo fixed > "$CONVEYOR_MAIN/x.py"; git -C "$CONVEYOR_MAIN" add -A; git -C "$CONVEYOR_MAIN" commit -qm fix; rec landed ok; gh issue close 1
EOF
  # The functions and globals the stage map (bench/stagemap.sh) starts each stage from, one file a stage or two.
  printf '%s\n' 'session() { :; }' > "$e/conveyor/lib/session.sh"; printf '%s\n' 'reviewed() { :; }' > "$e/conveyor/lib/review.sh"
  printf '%s\n' 'brief() { :; }' 'cardrules() { :; }' 'REVIEWT=r' 'FIX=f' > "$e/conveyor/lib/prompts.sh"; printf '%s\n' 'tests() { :; }' > "$e/conveyor/lib/testrun.sh"
  printf '%s\n' 'land() { :; }' 'rereview() { reviewed "$@"; }' > "$e/conveyor/lib/claim.sh"; printf '%s\n' 'push() { :; }' > "$e/conveyor/lib/push.sh"
  git -C "$e" add -A && git -C "$e" commit -qm A && git -C "$e" tag v1.0.0 \
    && sed -i 's/^V=A/V=B/' "$e/conveyor/lib/fake.sh" && printf '%s\n' 'reviewed() { echo stricter; }' > "$e/conveyor/lib/review.sh" \
    && git -C "$e" commit -qam 'review: stricter findings' && git clone -q --bare "$e" "$F/eng.git" && rm -rf "$e" || return 1
  cat > "$F/py" <<'EOF'
#!/usr/bin/env bash
shift # the harness script's path
case $1 in
  tasks) for t in proj__a-1 proj__b-2; do jq -nc --arg t "$t" --arg u "file://$SWE_FX/task.git" --arg b "$(git -C "$SWE_FX/task.git" rev-parse main)" \
      '{id: $t, repo: "o/proj", url: $u, base: $b, issue: "Fix x.py for \($t)", image: "img-\($t)", cmd: "true"}'; done > "$4" ;;
  image) [ "$(cat "$SWE_FX/broken" 2>/dev/null)" != "$2" ] || exit 3 ;;
  grade) echo "$2 $3 $4" >> "$SWE_FX/graded"
    if grep -q fixed "$5" && [ "$(cat "$SWE_FX/wrong" 2>/dev/null)" != "$4" ]; then echo '{"resolved":true}'; else echo '{"resolved":false}'; fi ;;
esac
EOF
  chmod +x "$F/py"
  # A stand-in for Docker: a container is a folder under $SWE_FX/boxes, its home the folder's home; exec runs the script
  # on this machine in that home, with none of the caller's login, Git identity or checkout variables, and git takes
  # its identity from its config only (a task's image has no usable host name to make one from). Every call is kept in
  # $SWE_FX/docker.log; with $SWE_FX/nodocker, Docker does not answer.
  mkdir -p "$F/bin" "$F/arms" && cat > "$F/bin/docker" <<'EOF'
#!/usr/bin/env bash
B=$SWE_FX/boxes; echo "$*" >> "$SWE_FX/docker.log"
case $1 in
  info) [ ! -e "$SWE_FX/nodocker" ] ;;
  create) shift; while [ "${1#-}" != "$1" ]; do [ "$1" != --name ] || n=$2; shift 2; done; mkdir -p "$B/$n/home" ;;
  cp) shift; [ "$1" != -a ] || shift; [ -d "$B/${2%%:*}" ] && cp -a "$1" "$B/${2%%:*}/home/" ;;
  start) [ -d "$B/$2" ] ;;
  exec) shift; e=(); w=.; u=''
    while [ "${1#-}" != "$1" ]; do case $1 in -i) shift ;; -u) u=$2; shift 2 ;; -w) w=$2; shift 2 ;; -e) e+=("$2"); shift 2 ;; *) exit 1 ;; esac; done
    n=$1; shift; [ -d "$B/$n" ] || exit 1; [ "$u" != 0 ] || exit 0
    cd "$w" && exec env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u CONVEYOR_MAIN -u CONVEYOR_CARDS -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u EMAIL GIT_CONFIG_PARAMETERS="'user.useconfigonly'='true'" HOME="$B/$n/home" "${e[@]}" "$@" ;;
  rm) shift; [ "$1" != -f ] || shift; [ -d "$B/$1" ] || exit 1; echo "$1" >> "$SWE_FX/removed"; rm -rf "$B/$1" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$F/bin/docker"
  # The arms: the real conveyor and solo arms with nothing to install (an install would run on this machine), and
  # stub arms. stub-a fixes x.py in every task, stub-b in proj__b-2 only; both fix the preflight's hello.py, print
  # the line their fired filter looks for, and note the Claude login their container was given. stub-quiet fires on
  # the preflight's task only: on a real task it changes x.py but prints nothing. stub-codex uses a Codex login.
  local a hello='[ ! -e hello.py ] || echo "print(\"hello\")" > hello.py'
  local hold='while [ -e "$SWE_FX/phold" ]; do sleep 0.1; done' # sleep: stub-slow's preflight runs until the case removes phold

  for a in conveyor solo; do jq '.install = "true"' "$SRC/bench/arms/$a.json" > "$F/arms/$a.json" || return 1; done
  stub() { # <name> <login> <its file in the home> <run>
    jq -n --arg n "$1" --arg l "$2" --arg f "$3" --arg r "$4" '{label: "Stub \($n)", kind: "agent", login: [$l], preflight: "[ -s \"$HOME/\($f)\" ]", run: $r,
      fired: "any(.type == \"done\")", tokens: "map(.tokens // 0) | add", sessions: 1}' > "$F/arms/stub-$1.json"
  }
  stub a claude .claude/.credentials.json "$hello"'; [ ! -e x.py ] || echo fixed > x.py; cat "$HOME/.claude/.credentials.json" >> "$SWE_FX/creds-seen"; echo "{\"type\": \"done\", \"tokens\": 7}"' \
    && stub b claude .claude/.credentials.json "$hello"'; ! grep -q b-2 "$SWE_PROMPT" || echo fixed > x.py; echo "{\"type\": \"done\", \"tokens\": 3}"' \
    && stub quiet claude .claude/.credentials.json "if [ -e hello.py ]; then $hello; echo '{\"type\": \"done\"}'; else echo fixed > x.py; fi" \
    && stub codex codex .codex/auth.json "$hello"'; echo "{\"type\": \"done\"}"' \
    && stub broken claude .claude/.credentials.json 'echo "{\"type\": \"done\"}"' && jq '.install = "echo no-such-package >&2; exit 7"' "$F/arms/stub-broken.json" > "$F/arms/b.new" \
    && mv "$F/arms/b.new" "$F/arms/stub-broken.json" \
    && stub slow claude .claude/.credentials.json "$hello"'; echo "{\"type\": \"done\"}"' && jq --arg p "$hold" '.preflight = $p' "$F/arms/stub-slow.json" > "$F/arms/s.new" \
    && mv "$F/arms/s.new" "$F/arms/stub-slow.json" || return 1
  # stub-evil fixes x.py, then sets a clean filter in its checkout's .git (it notes the HOME it runs with) and makes
  # the sandbox's patch file a link to a file outside the sandbox.
  stub evil claude .claude/.credentials.json "$hello"'; [ ! -e x.py ] || echo fixed > x.py; git config filter.mark.clean "echo \"\$HOME\" >> \"\$SWE_FX/filter-home\"; cat"
    echo "* filter=mark" > .git/info/attributes; ln -sfn "$SWE_FX/victim" "$SWE_SB/patch"; echo "{\"type\": \"done\"}"'
}
# A case's main (setup), the fixture copied to $SWE_FX, the versions folder its own, and the bench pointed at both.
swe() {
  setup '[]'; template swe swemake || fail "the SWE-bench fixture was not made"
  export SWE_FX=$T/$CASE/fx XDG_DATA_HOME=$T/$CASE/data; cp -a "$FIXTURE.swe/." "$SWE_FX/" || fail "the fixture was not copied"
  export CONVEYOR_BENCH_PYTHON=$SWE_FX/py CONVEYOR_BENCH_SOURCE=file://$SWE_FX/eng.git B=$ST/bench/swe SWE_SRC=$SRC
  trap 'chmod -R u+w "$T/$CASE"' EXIT
  EA=$(git -C "$SWE_FX/eng.git" rev-parse 'v1.0.0^{commit}'); EB=$(git -C "$SWE_FX/eng.git" rev-parse main)
  # Docker is the stand-in, the arms the fixture's, and the logins made-up files: the builder's account (`control
  # account`) holds a Claude login, CODEX_HOME a Codex one.
  export PATH=$SWE_FX/bin:$PATH CONVEYOR_BENCH_ARMS=$SWE_FX/arms CODEX_HOME=$T/$CASE/codex
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/acct" "$CODEX_HOME" && echo CLAUDE-LOGIN > "$T/$CASE/acct/.credentials.json" && echo CODEX-LOGIN > "$CODEX_HOME/auth.json" \
    && jq -cn --arg a "$T/$CASE/acct" '{accounts: [{name: "bench", configDir: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && jq -c '.account = "bench"' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" || fail "the logins were not made"
  # The conveyor arm on both engines and Claude alone passed their preflight an hour ago (a case of the preflight runs it),
  # with the logins their seats take: the conveyor arm's builder m is Claude's, its reviewer x Codex's.
  local k a
  for k in conveyor/$EA conveyor/$EB solo/solo-m; do a=${k%/*}; mkdir -p "$B/preflight/$a"
    jq -cn --arg k "${k#*/}" --argjson e "$(($(date +%s) - 3600))" --argjson s "$(jq -cS --arg n "$a" '.name = $n' "$SWE_FX/arms/$a.json")" \
      '{arm: $s.name, key: $k, ok: true, why: null, at: "2026-11-17T00:00:00Z", epoch: $e, spec: $s, logins: (if $s.kind == "conveyor" then "claude codex" else "claude" end)}' \
      > "$B/preflight/$a/${k#*/}.json" || fail "the preflight passes were not kept"
  done
}
# The tasks in the pinned order: sha256 of "<seed>:<id>", as swe.json's seed gives it.
sweorder() { local s t; s=$(jq -r .seed "$SRC/bench/swe.json"); for t in proj__a-1 proj__b-2; do printf '%s %s\n' "$(printf '%s:%s' "$s" "$t" | sha256sum | cut -c1-64)" "$t"; done | sort | cut -d ' ' -f 2; }

# Bugs: `swe n` takes other tasks than the first n of the pinned order (so `swe 5` is not the start of `swe 20`), runs a
# task again that the same engine commit already ran, takes an n past the list or none of 1 to 500, or keeps no
# per-task sessions, tokens and minutes or no per-run resolved count with its engine commit.
t_swepresets() {
  swe; local first second out
  { read -r first; read -r second; } < <(sweorder)
  out=$(loop bench swe 1 2>&1) || fail "swe 1 failed: $out"
  [ "$(cat "$SWE_FX/log")" = "B SWE-bench $first" ] || fail "swe 1 did not build the first task of the pinned order ($first) with main's engine: $(cat "$SWE_FX/log")"
  grep -q "Expected: about 2 sessions (worst case 8)" <<<"$out" || fail "the run did not say the sessions expected before it began (worst case: build, 3 reviews, 2 fixes, a test fix and its review): $out"
  # Bug: every sandbox's checkout was named main, so the benchmarks of two projects running at once took one project
  # name, main, and shared one machine slot file (lib/pick.sh), each loop leaving the other's cards out of its count.
  [ "$(cat "$SWE_FX/rtag")" = "swe-${R##*/}" ] || fail "the sandbox's loop does not take a name of this project's own: $(cat "$SWE_FX/rtag" 2>&1)"
  out=$(loop bench swe 2 2>&1) || fail "swe 2 failed: $out"
  [ "$(sed -n 2p "$SWE_FX/log")" = "B SWE-bench $second" ] && [ "$(wc -l < "$SWE_FX/log")" = 2 ] || fail "swe 2 did not reuse the first task's result and build only the second: $(cat "$SWE_FX/log")"
  grep -q "1/2 $first: resolved (reused)" <<<"$out" || fail "swe 2 did not say the first task was reused: $out"
  jq -e --arg e "$EB" '.sessions == 2 and .tokens == 440 and (.minutes | type) == "number" and .engine == $e and .resolved' "$B/results/$EB/$first.json" > /dev/null \
    || fail "the task's result holds no sessions, tokens, minutes or engine: $(cat "$B/results/$EB/$first.json")"
  [ "$(tail -n 1 "$B/runs.jsonl" | jq -c --arg e "$EB" '[.n, .resolved, .engine == $e, .state]')" = '[2,1,true,"done"]' ] || fail "the run's line is not 1 of 2 resolved with its engine: $(tail -n 1 "$B/runs.jsonl")"
  grep -q "Resolved 1 of 2 with engine main ($EB)" <<<"$out" || fail "the run did not end with its resolved count and engine commit: $out"
  out=$(loop bench swe 3 2>&1) && fail "an n past the task list was taken: $out"
  out=$(loop bench swe 501 2>&1); [ $? = 2 ] || fail "n 501 was not refused as a wrong argument: $out"
  # The Board's tab reads the presets, the last run and the versions a run can pick from the snapshot (the results it
  # reads with bench swe history: t_swehistory).
  [ "$(jq -c .presets "$SRC/bench/swe.json")" = '[1,5,20,50]' ] \
    && [ "$(loop snapshot --fresh | jq -c '[.bench.presets, .bench.live.state, (.bench.versions | map(.name))]')" = '[[1,5,20,50],"done",["main","v1.0.0"]]' ] \
    || fail "the snapshot does not carry the Benchmarks tab's presets, last run and versions: $(loop snapshot --fresh | jq -c .bench)"
  # A run whose process was killed with no end written is not shown running for good.
  jq -c '.live.state = "running" | .live.pid = 2147483646' "$B/board.json" > "$B/b.new" && mv "$B/b.new" "$B/board.json"
  [ "$(loop snapshot --fresh | jq -r .bench.live.state)" = stopped ] || fail "a run whose process is gone is shown running"
}

# Bug: the dataset's rows an earlier harness kept (raw.<revision>.jsonl, with the reference fixes and hidden tests)
# stayed in the state folder, readable by a card's sessions, when the task list of that revision was already made.
t_sweoldraw() {
  swe; local rev out; rev=$(jq -r .revision "$SRC/bench/swe.json")
  # The earlier list's tasks have no cmd (the test command run in the task's container), as an earlier harness made it.
  mkdir -p "$B" && "$SWE_FX/py" - tasks d r "$B/t" && jq -c 'del(.cmd)' "$B/t" > "$B/tasks.$rev.jsonl" && echo REFFIX > "$B/raw.$rev.jsonl" && echo REFFIX > "$B/raw.older.jsonl" \
    || fail "the earlier run's files were not made"
  out=$(loop bench swe 3 2>&1); [ $? = 2 ] || fail "an n past the task list was not refused: $out"
  [ -z "$(ls "$B"/raw.*.jsonl 2>/dev/null)" ] || fail "the dataset's rows an earlier harness kept are still in the state folder: $(ls "$B")"
  # Bug: the list kept from before was used, and every conveyor arm's card got an empty test command.
  jq -se 'length == 2 and all(.cmd == "true")' "$B/tasks.$rev.jsonl" > /dev/null || fail "a task list with no test commands was not made again: $(cat "$B/tasks.$rev.jsonl")"
}

# Bug: a task whose Docker image cannot be fetched or built is counted as failed (or stops the run) instead of being
# reported as not run, with no result kept, so the next run tries it again.
t_swenotrun() {
  swe; local first second out
  { read -r first; read -r second; } < <(sweorder)
  echo "img-$first" > "$SWE_FX/broken"
  out=$(loop bench swe 2 2>&1) || fail "the run failed: $out"
  grep -q "1/2 $first: not run: its Docker image could not be fetched or built" <<<"$out" || fail "the task with no image was not reported as not run: $out"
  [ ! -e "$B/results/$EB/$first.json" ] && [ -e "$B/results/$EB/$second.json" ] || fail "a result was kept for the task not run, or none for the other"
  grep -q "Resolved 0 of 2 .*not run: 1\." <<<"$out" || fail "the run's total does not set the task not run apart: $out"
  [ "$(cat "$SWE_FX/log")" = "B SWE-bench $second" ] || fail "the task with no image was built: $(cat "$SWE_FX/log")"
}

# Bug: Stop leaves the run, or the engine loop building in its sandbox, running, or writes no end for the run.
t_swestop() {
  swe; local p out
  : > "$SWE_FX/hold"
  loop bench swe 2 > "$T/$CASE/run.out" 2>&1 &
  wait_until "[ -s '$SWE_FX/pid' ]" || fail "the task's build did not start"
  p=$(cat "$SWE_FX/pid")
  out=$(loop bench swe stop 2>&1) || fail "stop failed: $out"
  wait_until "! kill -0 $p 2>/dev/null" || fail "the engine loop of the sandbox still runs after Stop"
  wait $! 2>/dev/null
  [ "$(tail -n 1 "$B/runs.jsonl" | jq -r .state)" = stopped ] || fail "the run's line does not say stopped: $(cat "$B/runs.jsonl" 2>&1)"
  [ ! -d "$B/work" ] && [ -z "$(ls "$B/results/$EB" 2>/dev/null)" ] || fail "the stopped task left a sandbox or a result"
  # Bug: Stop killed the docker client only; the trial's container, with the logins copied into it, was left running.
  [ -z "$(ls "$SWE_FX/boxes")" ] || fail "the stopped trial's container was not removed: $(ls "$SWE_FX/boxes")"
}

# Bug: --engine builds with main's engine whatever it names, or a release is not taken by its name; results of two
# engine commits are kept apart, each with its release's name.
t_sweengine() {
  swe; local out
  out=$(loop bench swe 1 --engine v1.0.0 2>&1) || fail "the run on v1.0.0 failed: $out"
  out=$(loop bench swe 1 --engine "$EB" 2>&1) || fail "the run on a commit failed: $out"
  [ "$(cut -d ' ' -f 1 "$SWE_FX/log" | tr '\n' ' ')" = 'A B ' ] || fail "the tasks were not built with the engines named: $(cat "$SWE_FX/log")"
  [ "$(cat "$B/results/$EA"/*.json | jq -r .version)" = v1.0.0 ] || fail "the result of the release does not name it"
  out=$(loop bench swe results 2>&1); grep -q "^v1.0.0 ${EA:0:12}: 1 of 1 resolved" <<<"$out" && grep -q "^main ${EB:0:12}: 1 of 1 resolved" <<<"$out" \
    && grep -q "with 1 task only a total break shows" <<<"$out" || fail "the two engines' results are not shown side by side with the noise line: $out"
  if out=$(loop bench swe 1 --engine v9.9.9 2>&1); then fail "a version that is not released was taken: $out"; fi
}

# Bug: diff does not find the task that flipped, the step where the two runs went apart, or the engine commits that
# changed that step; or its explanation is not the model's reading of those facts alone.
t_swediff() {
  swe; local out
  loop bench swe 2 --engine v1.0.0 > /dev/null 2>&1 && loop bench swe 2 > /dev/null 2>&1 || fail "the two runs failed"
  echo 'echo "B blocked at review after two NO-GO findings"' > "$STUB/build"
  out=$(loop bench swe diff v1.0.0 main --json 2>&1) || fail "diff failed: $out"
  [ "$(jq -c '[.flipped[].task, .flipped[0].apart, .same, .a.totals.resolved, .b.totals.resolved, .withinNoise]' <<<"$out")" = '["proj__a-1","review",["proj__b-2"],2,1,true]' ] \
    || fail "diff did not name the flipped task, the review step and the totals: $out"
  jq -e --arg c "${EB:0:7}" '.flipped[0].changes | map(.title) == ["review: stricter findings"] and (.[0].commit | startswith($c))' <<<"$out" > /dev/null \
    || fail "diff did not name the engine commit that changed the review stage: $(jq -c .flipped[0].changes <<<"$out")"
  # Bug: findings came from the reason alone, which the record cuts short, not the NO-GO review's tail (its second line here).
  jq -e '.flipped[0] | .b.findings == ["[P1] x.py:1 the fix is wrong", "[P1] x.py:1 still wrong\n[P2] y.py:2 past the cut reason"] and .b.fixRounds == 1 and (.reading | startswith("B blocked at review"))' <<<"$out" > /dev/null \
    || fail "the flipped task's facts or the model's reading are missing: $(jq -c .flipped[0] <<<"$out")"
  # Bug: every step's tail was saved, test output and GO reviews too, though Compare reads only a NO-GO review's.
  cat "$B/results/$EB"/*.json | jq -se '[.[].steps[] | select(has("tail")) | .step + " " + .result] == ["review NO-GO"]' > /dev/null \
    || fail "a tail was kept other than the NO-GO review's: $(cat "$B/results/$EB"/*.json | jq -sc '[.[].steps[] | select(has("tail"))]')"
  # Bug: the judge sessions on B's two reviews were left out of the task's sessions (build, 2 reviews, a fix: 4).
  jq -e '.flipped[0].b.sessions == 6' <<<"$out" > /dev/null || fail "the judge's sessions are not counted: $(jq -c .flipped[0].b <<<"$out")"
  grep -q '"apart":"review"' "$STUB/brief" || fail "the model was not given the facts: $(cat "$STUB/brief")"
  out=$(loop bench swe diff v1.0.0 main 2>&1) && grep -q "The model's reading (from the facts above only): B blocked" <<<"$out" || fail "the text form does not label the reading: $out"
  # Bug: the text form gave only a count of the tasks that stayed the same, not which they are.
  grep -q "The same in both: 1 task(s): proj__b-2\. Flipped: 1\." <<<"$out" || fail "the text form does not name the tasks that stayed the same: $out"
}

# Bug: --solo runs Conveyor's rounds, or is kept with an engine's results; it is one Claude session on the issue.
t_swesolo() {
  swe; local out first
  first=$(sweorder | head -n 1)
  echo 'echo fixed > x.py; command -v gh > "$STUB/solo-gh"; cat "$HOME/.claude/.credentials.json" > "$STUB/solo-acct"; echo "${CLAUDE_CONFIG_DIR:-none}" > "$STUB/solo-dir"' > "$STUB/build"
  # The builder is set to a named account (`control account`), and the caller's shell is on another login.
  export CLAUDE_CONFIG_DIR=$T/$CASE/inherited; mkdir -p "$T/$CASE/acct1" "$CLAUDE_CONFIG_DIR"
  echo FIRST-LOGIN > "$T/$CASE/acct1/.credentials.json"; echo INHERITED-LOGIN > "$CLAUDE_CONFIG_DIR/.credentials.json"
  jq -cn --arg a "$T/$CASE/acct1" '{accounts: [{name: "first", configDir: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  jq -c '.account = "first"' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(loop bench swe 1 --solo 2>&1) || fail "the solo run failed: $out"
  # Bug: the solo session ran on the login it inherited, not on the builder's account that the usage guard reads.
  # Its container is given a copy of that account's login in its own home, and no folder of the host.
  [ "$(cat "$STUB/solo-acct")" = FIRST-LOGIN ] && [ "$(cat "$STUB/solo-dir")" = none ] \
    || fail "the solo session did not run on a copy of the builder's account: $(cat "$STUB/solo-acct" "$STUB/solo-dir")"
  # Bug: the session ran on the host, where the dataset's reference patches and hidden tests are in reach. Its
  # container mounts the task's sandbox alone; the CLI's own confinement cannot run here (the claude stub): its
  # arguments are what is checked.
  [ "$(cat "$STUB/solo-gh")" = "$B/work/$first/bin/gh" ] || fail "the solo session was not given the sandbox's gh: $(cat "$STUB/solo-gh")"
  [ "$(grep '^create ' "$SWE_FX/docker.log" | grep -o -- '-v [^ ]*' | tr '\n' ' ')" = "-v $B/work/$first:$B/work/$first " ] \
    || fail "the container mounts more of the host than the task's sandbox: $(grep '^create ' "$SWE_FX/docker.log")"
  local a; a=$(tail -n 1 "$STUB/sessions")
  [[ $a == *'--permission-mode dontAsk'* && $a == *'--tools Read,Grep,Glob,Edit,Write '* && $a == *"Edit(/$B/work/$first/swe-${R##*/}/**)"* \
    && $a == *'--setting-sources  --strict-mcp-config'* && $a != *bypassPermissions* ]] \
    || fail "the solo session is not held to its sandbox's files with no shell: $a"
  [ ! -s "$SWE_FX/log" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "the solo run did not take one Claude session and no engine"
  jq -e '.arm == "solo" and .model == "m" and .sessions == 1 and .tokens == 35 and .resolved and .engine == null' "$B/results/solo-m/$first.json" > /dev/null \
    || fail "the solo result is not one session's: $(cat "$B/results/solo-m/$first.json" 2>&1)"
  grep -q 'Fix x.py for' "$STUB/brief" || fail "the session was not given the issue"
  # Bug: the Board read the solo key board.json kept from its last run, so after the builder's model changed it
  # counted the old model's results as reused and showed no sessions for a run that builds every task.
  jq -c '.model = {cli: "claude", model: "claude-haiku-5-5"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  [ "$(loop snapshot --fresh | jq -r .bench.soloKey)" = solo-claude-haiku-5-5 ] || fail "the snapshot's solo key is not the builder's model in force: $(loop snapshot --fresh | jq -c .bench.soloKey)"
}

# Bugs: an arm whose command failed in a trial was skipped as a task not run (the owner's rule: an arm that does not
# fire fails that task), or its change was graded as if the arm had worked; and the failed session's stderr kept its
# credential and address in the results and the Board's snapshot.
t_swesolofail() {
  swe; local out first
  first=$(sweorder | head -n 1)
  # A credential and an address, made here so that this file holds neither. The session changes x.py as a fix would.
  printf 'sk-ant-oat01-%s\n' "$(printf 'Ab9x%.0s' {1..10})" > "$STUB/secret"; echo "contact: ops${AT}corp-mail.test" > "$STUB/mail"
  echo 'echo fixed > x.py; { echo "Authorization: Bearer $(cat "$STUB/secret")"; cat "$STUB/mail"; } >&2
echo "{\"type\":\"result\",\"is_error\":true,\"result\":\"Invalid API key · Please run /login\"}"; exit 1' > "$STUB/build"
  out=$(loop bench swe 1 --solo 2>&1) || fail "the solo run failed: $out"
  grep -q "1/1 $first: unresolved (its command failed (exit 1): Authorization: Bearer \[left out\] \[a line left out: email\] Invalid API key · Please run /login)$" <<<"$out" \
    && grep -q "Resolved 0 of 1 with Claude alone; not run: 0\." <<<"$out" || fail "the failed session was not counted as the arm's failure, with its words and no credential: $out"
  jq -e '.fired == false and .resolved == false and (.why | startswith("its command failed"))' "$B/results/solo-m/$first.json" > /dev/null \
    && [ ! -e "$SWE_FX/graded" ] || fail "the failed trial was not kept as not fired, or its change was graded: $(cat "$B/results/solo-m/$first.json" 2>&1)"
  [ -s "$B/board.json" ] && [ -s "$B/live.json" ] || fail "the run left no Board record to check"
  ! grep -rqF -e "$(cat "$STUB/secret")" -e "corp-mail" "$B/board.json" "$B/live.json" "$B/results" || fail "the results or the Board's record hold the credential or the address"
  out=$(loop bench swe results 2>&1); grep -q "^Claude alone (m): 0 of 1 resolved (1 did not fire)" <<<"$out" || fail "the results do not count the trial that did not fire: $out"
}

# Bug: a run starts while the project's usage guard is reached.
t_sweguard() {
  swe; local out
  jq -c '.guard = 50' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(CONVEYOR_LIMIT_CMD='echo "{\"seven_day\":{\"utilization\":90}}"' loop bench swe 1 2>&1) && fail "a run started at the usage guard: $out"
  grep -q 'the usage guard is reached' <<<"$out" && [ ! -s "$SWE_FX/log" ] || fail "the refusal does not name the guard, or a task was built: $out"
  # Bug: a paused project read as "paused", not "paused by guard", so a run (here Claude alone) started past its guard.
  jq -c '.mode = "pause"' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(CONVEYOR_LIMIT_CMD='echo "{\"seven_day\":{\"utilization\":90}}"' loop bench swe 1 --solo 2>&1) && fail "a solo run started at the usage guard of a paused project: $out"
  grep -q 'the usage guard is reached' <<<"$out" && [ ! -s "$STUB/sessions" ] || fail "the refusal does not name the guard, or a session ran: $out"
  # Bug: an explicit preflight started its Claude session on the trivial task past the guard.
  out=$(CONVEYOR_LIMIT_CMD='echo "{\"seven_day\":{\"utilization\":90}}"' loop bench swe arms check solo 2>&1) && fail "a preflight ran at the usage guard: $out"
  grep -q 'the usage guard is reached' <<<"$out" && [ ! -s "$STUB/sessions" ] || fail "the refusal does not name the guard, or a session ran: $out"
}
# Bug: Claude's usage guard held back an arm with only a Codex login: its preflight and its run refused to start.
t_swecodexguard() {
  swe; local out
  jq -c '.guard = 50' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  export CONVEYOR_LIMIT_CMD='echo "{\"seven_day\":{\"utilization\":90}}"'
  out=$(loop bench swe 1 --arm stub-codex 2>&1) && grep -q "Resolved .* of 1 with " <<<"$out" && ! grep -q 'usage guard' <<<"$out" \
    || fail "a Codex-only run was held back by Claude's guard: $out"
  out=$(loop bench swe arms check stub-codex 2>&1) && grep -q '^stub-codex: ready$' <<<"$out" || fail "a Codex-only preflight was held back by Claude's guard: $out"
}
# Bug: with Codex in both seats the guard read no account, so a solo run started its Claude session on the builder's
# named account (`control account`) past that account's limit.
t_swesologuard() {
  swe; local out
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/acct1"
  jq -cn --arg a "$T/$CASE/acct1" '{accounts: [{name: "first", configDir: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  jq -c '.guard = 50 | .account = "first" | .model = {cli: "codex", model: "x", effort: null} | .reviewer = {cli: "codex", model: "x", effort: "low"}' \
    "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  # Only the named account is at its limit.
  out=$(CONVEYOR_LIMIT_CMD='u=10; [ "$CLAUDE_CONFIG_DIR" != "'"$T/$CASE/acct1"'" ] || u=90; echo "{\"seven_day\":{\"utilization\":$u}}"' loop bench swe 1 --solo 2>&1) \
    && fail "a solo run started on an account at the usage guard: $out"
  grep -q 'the usage guard is reached' <<<"$out" && [ ! -s "$STUB/sessions" ] || fail "the refusal does not name the guard, or a session ran: $out"
}

# Bugs: a graded patch the harness found unresolved was reported as not run and kept no result, so the next run built
# it again; the grade was not told which dataset and revision hold the task; the worst case left out the judge's sessions, and the fix of a failed test
# step with its review and judge; and with one task a complete
# flip was called within the noise.
t_swewrong() {
  swe; local first out
  first=$(sweorder | head -n 1)
  jq -c '.judgeOn = true' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(loop bench swe 1 --engine v1.0.0 2>&1) || fail "the run on v1.0.0 failed: $out"
  grep -q "Expected: about 2 sessions (worst case 12)" <<<"$out" || fail "the worst case leaves out a judge session for each of the 4 reviews, or the test fix and its review: $out"
  echo "$first" > "$SWE_FX/wrong"
  out=$(loop bench swe 1 2>&1) || fail "the run on main failed: $out"
  grep -q "1/1 $first: unresolved$" <<<"$out" && jq -e '.resolved == false' "$B/results/$EB/$first.json" > /dev/null \
    || fail "an unresolved grade was not kept as unresolved: $out"
  out=$(loop bench swe 1 2>&1) && grep -q "1/1 $first: unresolved (reused)" <<<"$out" || fail "the unresolved task was built again: $out"
  [ "$(sort -u "$SWE_FX/graded")" = "$(jq -r '"\(.dataset) \(.revision)"' "$SRC/bench/swe.json") $first" ] \
    || fail "the grade was not told the pinned dataset and revision to read the task's row from: $(cat "$SWE_FX/graded")"
  out=$(loop bench swe diff v1.0.0 main --json 2>&1) && [ "$(jq -c '[.tasks, (.flipped | length), .withinNoise]' <<<"$out")" = '[1,1,false]' ] \
    || fail "a complete flip of one task was called within the noise: $out"
}

# Bugs: --arm ran one arm only, or the arms on other tasks; an arm ran with no preflight; a trial shared a container
# or left one behind; the login copied into a container reached the results; the results of two arms were mixed, or
# could not be compared with diff.
t_swearms() {
  swe; local first second out
  { read -r first; read -r second; } < <(sweorder)
  out=$(loop bench swe 2 --arm stub-a --arm stub-b 2>&1) || fail "the run of two arms failed: $out"
  grep -q "^1/2 $first \[stub-a\]: " <<<"$out" && grep -q "^1/2 $first \[stub-b\]: " <<<"$out" && grep -q "^2/2 $second \[stub-b\]: " <<<"$out" \
    || fail "the two arms did not each build both tasks of the pinned order: $out"
  grep -q "^Resolved 2 of 2 with Stub a; not run: 0\.$" <<<"$out" && grep -q "^Resolved 1 of 2 with Stub b; not run: 0\.$" <<<"$out" \
    || fail "the run does not end with each arm's own resolved count: $out"
  # Bug (#326): a run's line named its arms but not their results keys, so the Board could not read each arm's figures.
  [ "$(tail -n 1 "$B/runs.jsonl" | jq -c '[(.cols | map([.arm, .key])), .set.revision == $rv]' --arg rv "$(jq -r .revision "$SRC/bench/swe.json")")" = '[[["stub-a","stub-a"],["stub-b","stub-b"]],true]' ] \
    || fail "the run's line does not name each arm's results key and the task set: $(tail -n 1 "$B/runs.jsonl")"
  [ "$(cat "$B/results/stub-a"/*.json | jq -sc 'map([.task, .resolved, .arm, .tokens]) | sort')" = "$(jq -nc --arg a proj__a-1 --arg b proj__b-2 '[[$a, true, "stub-a", 7], [$b, true, "stub-a", 7]]')" ] \
    && [ "$(cat "$B/results/stub-b"/*.json | jq -sc 'map([.task, .resolved]) | sort')" = '[["proj__a-1",false],["proj__b-2",true]]' ] \
    || fail "the results are not kept per arm: $(cat "$B"/results/stub-*/*.json)"
  # Each arm passed its preflight first; then every trial had a container of its own, removed after it.
  jq -se 'length == 2 and all(.ok)' "$B/preflight/stub-a/stub-a.json" "$B/preflight/stub-b/stub-b.json" > /dev/null || fail "an arm ran with no passed preflight"
  [ "$(grep -c '^create ' "$SWE_FX/docker.log")" = 6 ] && [ "$(sort -u "$SWE_FX/removed" | wc -l)" = 6 ] && [ -z "$(ls "$SWE_FX/boxes")" ] \
    || fail "the 2 preflights and 4 trials did not each get a container of their own, removed after: $(cat "$SWE_FX/docker.log")"
  [ "$(sort -u "$SWE_FX/creds-seen")" = CLAUDE-LOGIN ] || fail "the container was not given the builder's Claude login: $(cat "$SWE_FX/creds-seen" 2>&1)"
  ! grep -rq CLAUDE-LOGIN "$B" || fail "the login copied into the containers is in the results, the logs or the preflight records: $(grep -rl CLAUDE-LOGIN "$B")"
  out=$(loop bench swe diff stub-a stub-b --json 2>&1) && [ "$(jq -c '[.a.version, .b.version, [.flipped[].task], .flipped[0].changes, .same]' <<<"$out")" = '["stub-a","stub-b",["proj__a-1"],null,["proj__b-2"]]' ] \
    || fail "diff does not compare two arms on the tasks both ran: $out"
  out=$(loop bench swe arms 2>&1); grep -q "^stub-a (Stub a, agent): ready (checked " <<<"$out" && grep -q "^stub-quiet (Stub quiet, agent): not checked" <<<"$out" \
    || fail "the arms are not listed with their preflight state: $out"
}

# Bug (#338): an arm on the builder's model keeps each model's results under a key of its own, but the results and
# diff called both keys by the arm's label alone, so two models' runs could not be told apart. An arm of a fixed model
# (its key is its name) has the model in its label already, and was named with it twice.
t_swearmmodel() {
  swe; local m out
  for m in m1 m2; do
    mkdir -p "$B/results/stub-a-$m" && jq -nc --arg m "$m" '{task: "proj__a-1", arm: "stub-a", label: "Stub a", key: "stub-a-\($m)", engine: null, version: null,
      model: $m, resolved: true, fired: true, sessions: 1, tokens: 7, minutes: 1}' > "$B/results/stub-a-$m/proj__a-1.json" || fail "the results could not be written"
  done
  mkdir -p "$B/results/stub-f" && jq -nc '{task: "proj__a-1", arm: "stub-f", label: "Stub f (m3)", key: "stub-f", engine: null, version: null,
    model: "m3", resolved: true, fired: true, sessions: 1, tokens: 7, minutes: 1}' > "$B/results/stub-f/proj__a-1.json" || fail "the results could not be written"
  out=$(loop bench swe results 2>&1); grep -q "^Stub a (m1): 1 of 1 resolved" <<<"$out" && grep -q "^Stub a (m2): 1 of 1 resolved" <<<"$out" \
    && grep -q "^Stub f (m3): 1 of 1 resolved" <<<"$out" || fail "the results do not name each key's model once: $out"
  out=$(loop bench swe diff stub-a-m1 stub-a-m2 --json 2>&1) && [ "$(jq -c '[.a.version, .b.version]' <<<"$out")" = '["Stub a (m1)","Stub a (m2)"]' ] \
    || fail "diff does not name each key's model: $out"
}

# Bug (#326): the Board's Benchmarks tab had no history of the runs, no figures of each arm and no task of a run to
# open; and the snapshot carried every run and result, past its size budget. history gives every run newest first (a
# run whose process is gone shows stopped) with each arm's resolved, not run, sessions and tokens, and the arms with
# their state; show gives one run's tasks in its order, each arm's result and patch; neither is in the snapshot.
t_swehistory() {
  swe; local p o
  mkdir -p "$B/results/stub-a" "$B/results/stub-b" && jq -nc '{id: "proj__b-2", issue: "\nSecond line first\nmore"}, {id: "proj__a-1", issue: "First task"}' > "$B/tasks.$(jq -r .revision "$SRC/bench/swe.json").jsonl" \
    && for p in stub-a/proj__a-1/true/1/7 stub-a/proj__b-2/true/2/5 stub-b/proj__a-1/false/1/3; do IFS=/ read -r a t r s k <<<"$p"
      jq -nc --arg a "$a" --arg t "$t" --argjson r "$r" --argjson s "$s" --argjson k "$k" '{task: $t, arm: $a, key: $a, label: $a, resolved: $r, fired: true, sessions: $s, tokens: $k, minutes: 1, steps: []}' > "$B/results/$a/$t.json"; done \
    && printf '%s\n' 'diff --git a/x.py b/x.py' '--- a/x.py' '+++ b/x.py' '@@ -1 +1 @@' '-bug' '+fixed' > "$B/results/stub-a/proj__a-1.patch" \
    && jq -nc '{id: "r20261117T090000-1", arms: ["stub-a", "stub-b"], cols: [{arm: "stub-a", key: "stub-a"}, {arm: "stub-b", key: "stub-b"}], n: 4, started: "2026-11-17T09:00:00Z", state: "done",
      tasks: [{id: "proj__a-1", arm: "stub-a", result: "resolved"}, {id: "proj__a-1", arm: "stub-b", result: "unresolved"}, {id: "proj__b-2", arm: "stub-a", result: "resolved", reused: true},
        {id: "proj__b-2", arm: "stub-b", result: "not run: its Docker image could not be fetched or built"}]}' > "$B/runs.jsonl" \
    && jq -nc '{id: "r20261117T140000-2", pid: 2147483646, arms: ["stub-a"], cols: [{arm: "stub-a", key: "stub-a"}], n: 1, started: "2026-11-17T14:00:00Z", state: "running", current: "proj__b-2", tasks: []}' > "$B/live.json" \
    || fail "the runs and results could not be written"
  o=$(loop bench swe history 2>&1) || fail "history failed: $o"
  [ "$(jq -c '[(.runs | map([.id, .state, .n])), (.runs[1].cols | map([.arm, .done, .resolved, .notRun, .sessions, .tokens])), (.runs[0] | has("tasks") or has("pid"))]' <<<"$o")" \
    = '[[["r20261117T140000-2","stopped",1],["r20261117T090000-1","done",2]],[["stub-a",2,2,0,3,12],["stub-b",2,0,1,1,3]],false]' ] \
    || fail "history does not give the runs newest first with each arm's figures: $o"
  [ "$(jq -c '[(.arms | map(select(.name | IN("solo", "stub-a", "conveyor"))) | map([.name, .state, .key, .keyPrefix])), (.keys | map([.key, .at]))]' <<<"$o")" \
    = '[[["conveyor","ready",null,""],["solo","ready","solo-m",null],["stub-a","unchecked","stub-a",null]],[["stub-a",[0,1]],["stub-b",[1]]]]' ] \
    || fail "history does not give each arm's state and key, or each key's places in the pinned order: $(jq -c '[.arms, .keys]' <<<"$o")"
  o=$(loop bench swe show r20261117T090000-1 2>&1) || fail "show failed: $o"
  [ "$(jq -c '[.run.id, (.tasks | map([.id, .title, (.cells | map([.arm, .result, .resolved, .patch]))]))]' <<<"$o")" \
    = '["r20261117T090000-1",[["proj__a-1","First task",[["stub-a","resolved",true,[{"path":"x.py","added":1,"removed":1}]],["stub-b","unresolved",false,null]]],["proj__b-2","Second line first",[["stub-a","resolved",true,null],["stub-b","not run: its Docker image could not be fetched or built",null,null]]]]]' ] \
    || fail "show does not give the run's tasks in its order with each arm's result and patch: $o"
  o=$(loop bench swe show r20261117T000000-9 2>&1) && fail "show gave a run that is not there: $o"
  o=$(loop bench swe show ../../x 2>&1) && fail "show took a run id of another shape: $o"
  loop bench swe versions > /dev/null 2>&1; o=$(loop snapshot --fresh | jq -c '.bench | [has("live"), has("runs"), has("keys")]')
  [ "$o" = '[true,false,false]' ] || fail "the snapshot carries the runs or the results: $o"
}

# Bugs: an arm whose preflight fails could still be picked, or failed with no word of what is missing; an arm that
# cannot run here was offered.
t_swearmpre() {
  swe; local out
  rm "$CODEX_HOME/auth.json"
  out=$(loop bench swe 1 --arm stub-a --arm stub-codex 2>&1) && fail "an arm with no Codex login ran: $out"
  grep -q "the arm stub-codex cannot run: its preflight failed: no codex login on this machine: .*auth.json is missing" <<<"$out" || fail "the refusal does not say what is missing: $out"
  [ ! -d "$B/results" ] && [ ! -s "$SWE_FX/log" ] || fail "a task was built though an arm of the run cannot run"
  # Bug: the refusal came after the Board stopped reading the command's answer, and was recorded nowhere.
  [ "$(jq -r '.state + ": " + .why' "$B/live.json")" = "refused: $(grep -o 'the arm stub-codex cannot run: .*' <<<"$out")" ] \
    || fail "the refused run is not recorded with why: $(cat "$B/live.json")"
  out=$(loop bench swe arms 2>&1); grep -q "^stub-codex (Stub codex, agent): failed (.*): no codex login" <<<"$out" || fail "the list does not show the failed preflight: $out"
  # Bug: an arm whose install failed was reported as having a fired or tokens filter that is not valid jq.
  out=$(loop bench swe arms check stub-broken 2>&1) && fail "a preflight passed with a failed install: $out"
  grep -q "^stub-broken: failed: on the trivial task, its install failed: .*no-such-package" <<<"$out" || fail "the preflight does not say its install failed: $out"
  : > "$SWE_FX/nodocker"
  out=$(loop bench swe arms check stub-a 2>&1) && fail "a preflight passed with no Docker: $out"
  grep -qx 'conveyor: Docker did not answer on the build machine. Install or start Docker, check that `docker info` works, then check again.' <<<"$out" \
    || fail "the check does not name Docker as missing and its repair: $out"
  # Bugs (#633): a run of arms whose preflight passed started with no Docker, every task not run; its refusal removed an
  # arms check's container (chk), was on stderr only (History had no why) and named no engine (the Board said main).
  mkdir -p "$SWE_FX/boxes/chk" "$B/check/stub-a.h" && echo chk > "$B/check/stub-a.h/box"
  out=$(loop bench swe 1 --solo --arm conveyor --engine v1.5.0 2>&1) && fail "a run started with no Docker: $out"
  grep -q '^conveyor: Docker did not answer on the build machine\.' <<<"$out" || fail "the run's refusal does not name Docker: $out"
  [ ! -d "$B/results" ] && [ -d "$SWE_FX/boxes/chk" ] || fail "a task was run, or a check's container removed, with no Docker"; rm -r "$SWE_FX/nodocker" "$B/check/stub-a.h"
  out=$(loop bench swe history 2>&1); jq -e '.runs[0] | .state == "refused" and (.cols | map(.arm) == ["solo", "conveyor"]) and .cols[1].version == "v1.5.0"
    and (.why | startswith("Docker did not answer on the build machine."))' <<<"$out" > /dev/null || fail "the run history does not keep the Docker refusal: $out"
  # The engine's own arms: every file is an arm, and one that cannot run on a subscription login says why.
  out=$(CONVEYOR_BENCH_ARMS=$SRC/bench/arms loop bench swe arms 2>&1)
  [ "$(grep -c '' <<<"$out")" = "$(ls "$SRC"/bench/arms/*.json | wc -l)" ] && ! grep -q 'not a JSON object' <<<"$out" \
    && grep -q "^aider (Aider, agent): not offered: Aider runs on a model provider's API key" <<<"$out" || fail "the engine's arms are not all listed: $out"
  out=$(CONVEYOR_BENCH_ARMS=$SRC/bench/arms loop bench swe 1 --arm openhands 2>&1) && fail "an arm that is not offered ran: $out"
  grep -q "the arm openhands is not offered" <<<"$out" || fail "the refusal does not say the arm is not offered: $out"
}

# Bug: a trial whose arm did not fire (its output shows no use of its method) was graded on the change it left, or
# skipped as a task not run, when it is the arm's failure.
t_swearmquiet() {
  swe; local out
  out=$(loop bench swe 2 --arm stub-quiet 2>&1) || fail "the run failed: $out"
  [ "$(grep -c ': unresolved (it did not fire: its output shows no use of its method)$' <<<"$out")" = 2 ] && grep -q "^Resolved 0 of 2 with Stub quiet; not run: 0\.$" <<<"$out" \
    || fail "the trials that did not fire are not the arm's failures: $out"
  [ "$(cat "$B/results/stub-quiet"/*.json | jq -sc 'map([.fired, .resolved]) | unique')" = '[[false,false]]' ] && [ ! -e "$SWE_FX/graded" ] \
    || fail "a trial that did not fire was graded, or not kept as failed: $(cat "$B/results/stub-quiet"/*.json)"
}

# Bug: after an arm's container exited, the host ran git in the sandbox the arm could write (its clean filter ran on
# the host) and wrote the patch through the arm's link to a file outside the sandbox.
t_swearmhost() {
  swe; local out
  echo ORIGINAL > "$SWE_FX/victim"
  out=$(loop bench swe 1 --arm stub-evil 2>&1) || fail "the run failed: $out"
  grep -q "^Resolved 1 of 1 with Stub evil; not run: 0\.$" <<<"$out" || fail "the arm's patch was not read and graded: $out"
  [ -s "$SWE_FX/filter-home" ] && ! grep -qv "^$SWE_FX/boxes/" "$SWE_FX/filter-home" || fail "the arm's git filter ran outside its container: $(cat "$SWE_FX/filter-home" 2>&1)"
  [ "$(cat "$SWE_FX/victim")" = ORIGINAL ] || fail "the host wrote through the arm's link to a file outside the sandbox: $(cat "$SWE_FX/victim")"
}

# Bug: Stop found no run while an arm's preflight ran, as the run was recorded only after its preflights.
t_swestoppre() {
  swe; local out
  : > "$SWE_FX/phold"
  loop bench swe 1 --arm stub-slow > "$T/$CASE/run.out" 2>&1 &
  wait_until "[ -n \"\$(ls '$SWE_FX/boxes' 2>/dev/null)\" ]" || fail "the preflight's container did not start"
  out=$(loop bench swe stop 2>&1); rm -f "$SWE_FX/phold"
  [ "$out" = "conveyor: the SWE-bench run is stopped" ] || fail "Stop did not end the run in its preflight: $out"
  wait $! 2>/dev/null
  [ "$(tail -n 1 "$B/runs.jsonl" | jq -r .state)" = stopped ] && [ -z "$(ls "$SWE_FX/boxes")" ] \
    || fail "the stopped run is not recorded, or its preflight's container was left: $(cat "$B/runs.jsonl" 2>&1) $(ls "$SWE_FX/boxes")"
}

# Bug: a conveyor arm's seats were not given to the engine in its container (it built on the project's seats), or the
# container's control record named a host account it does not hold.
t_sweseats() {
  swe; local out
  jq '.seats = {model: {cli: "codex", model: "x"}, reviewer: {cli: "claude", model: "m"}} | .label = "Conveyor, Codex builds"' "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-seats.json"
  out=$(loop bench swe 1 --arm conveyor-seats 2>&1) || fail "the run failed: $out"
  grep -q "^Resolved 1 of 1 with Conveyor, Codex builds on engine main ($EB); not run: 0\.$" <<<"$out" || fail "the seats arm did not resolve the task on main's engine: $out"
  jq -e '.model == {cli: "codex", model: "x"} and .reviewer == {cli: "claude", model: "m"} and (has("account") | not)' "$SWE_FX/control.seen" > /dev/null \
    && jq -e '.models.allowed.codex | index("x")' "$SWE_FX/pack.seen" > /dev/null || fail "the engine was not given the arm's seats: $(cat "$SWE_FX/control.seen") $(jq -c .models "$SWE_FX/pack.seen")"
  # Bug: the engine in the container ran the project's own test command, not the task's (its cmd in the task list).
  jq -e '.test == {command: "true", survey: false}' "$SWE_FX/pack.seen" > /dev/null || fail "the engine's pack does not hold the task's test command: $(jq -c .test "$SWE_FX/pack.seen")"
  # Bug: the container was given the arm file's logins only, so the Codex builder seat had no Codex login there.
  [ "$(cat "$SWE_FX/codex.seen" 2>/dev/null)" = CODEX-LOGIN ] || fail "the Codex seat's container had no Codex login"
  [ -s "$B/results/conveyor-seats-$EB/$(sweorder | head -n 1).json" ] || fail "the seats arm's results are not kept apart from the conveyor arm's: $(ls "$B/results")"
}

# Bug: the conveyor arm's preflight asked for a Codex login on a project whose seats all use Claude, so the default
# arm could not run on a machine with no Codex login. A seat on Codex still needs one. The Tests seat serves
# `testaction`, which the benchmark's `run 1` does not start: a Codex Tests seat asked for a Codex login too.
t_swearmlogin() {
  swe; local out
  rm "$CODEX_HOME/auth.json"
  jq -c '.model = {cli: "claude", model: "m"} | .reviewer = {cli: "claude", model: "m"} | .judgeOn = false | .tests = {cli: "codex", model: "x"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  jq '.seats = {model: {cli: "codex", model: "x"}}' "$SWE_FX/arms/conveyor.json" > "$SWE_FX/arms/conveyor-seats.json"
  out=$(loop bench swe arms check conveyor conveyor-seats 2>&1)
  grep -q "^conveyor: ready$" <<<"$out" || fail "the conveyor arm on Claude seats asked for a Codex login: $out"
  grep -q "^conveyor-seats: failed: no codex login on this machine" <<<"$out" || fail "an arm with a Codex seat passed with no Codex login: $out"
  # Bug: a run took the passed check from before the reviewer moved to Codex, and its task's container could not be made.
  jq -c '.reviewer = {cli: "codex", model: "x"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(loop bench swe 1 2>&1) && fail "the run started with a Codex seat and no Codex login: $out"
  grep -q "the arm conveyor cannot run: its preflight failed: no codex login on this machine" <<<"$out" || fail "the run reused the check from before the seat moved to Codex: $out"
  # Bug: the judge's CLI was not counted, so a judge on Codex over Claude seats ran with no Codex login.
  jq -c '.reviewer = {cli: "claude", model: "m"} | .judgeOn = true | .judge = {cli: "codex", model: "x"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(loop bench swe arms check conveyor 2>&1)
  grep -q "^conveyor: failed: no codex login on this machine" <<<"$out" || fail "the arm with a Codex judge passed with no Codex login: $out"
}

# Bug: the seats were worked out on this host's models, so on a host with no Codex and a pack that lists no models the
# default reviewer was Claude's, while in the container, where the arm installs Codex, the same default is Codex's:
# the arm passed with no Codex login and its container had none.
t_swearmdefault() {
  swe; local out p='' d
  rm "$CODEX_HOME/auth.json" "$STUB/codex"
  for d in ${PATH//:/ }; do [ -x "$d/codex" ] || p+=$d:; done
  tune 'del(.models.allowed)'
  jq -c '.model = {cli: "claude", model: "claude-opus-5-5"} | del(.reviewer) | .judgeOn = false' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  out=$(PATH=${p%:} loop bench swe arms check conveyor 2>&1)
  grep -q "^conveyor: failed: no codex login on this machine" <<<"$out" || fail "the default reviewer, Codex's in the container, asked for no Codex login: $out"
}

# Bug: the harness kept every dataset row (each task's reference fix and hidden tests) in the state folder and in
# Hugging Face's cache, where a card's sessions, a shell as the same account, could read them while they built the
# task. The real swe_harness.py runs here on stand-in datasets and swebench modules: the stand-in load_dataset keeps
# its download in the cache it is given, as the real one does, and nothing holding a reference fix or hidden test may
# stay once tasks or grade ends; the grade still reads the one task's row, from a .jsonl file (the only local form
# the official harness loads besides .json and .parquet).
t_sweharness() {
  local C=$T/$CASE M=$T/$CASE-mods out
  mkdir -p "$C/tmp" "$C/home" "$M/datasets" "$M/swebench/harness" || fail "the case's folders were not made"
  printf '%s\n' 'import json, os' 'def load_dataset(name, split, revision):' \
    '    rows = [{"instance_id": "o__p-%d" % i, "repo": "o/p", "version": "1", "base_commit": "c%d" % i, "problem_statement": "issue %d" % i,' \
    '             "patch": "REFFIX-%d" % i, "test_patch": "HIDDENTEST-%d" % i} for i in (1, 2)]' \
    '    d = os.path.join(os.environ.get("HF_DATASETS_CACHE") or os.path.join(os.environ["HF_HOME"], "datasets"), name); os.makedirs(d, exist_ok=True)' \
    '    open(os.path.join(d, revision + ".json"), "w").write(json.dumps(rows))' \
    '    return rows' > "$M/datasets/__init__.py"
  : > "$M/swebench/__init__.py"; : > "$M/swebench/harness/__init__.py"
  echo 'MAP_REPO_VERSION_TO_SPECS = {"o/p": {"1": {"test_cmd": "pytest"}}}' > "$M/swebench/harness/constants.py"
  printf '%s\n' 'import json, os, sys, time' 'a = dict(zip(sys.argv[1::2], sys.argv[2::2]))' \
    'if os.environ.get("SWE_HOLD"):' '    open(os.environ["SWE_HOLD"] + ".pid", "w").write(str(os.getppid()))' \
    '    while os.path.exists(os.environ["SWE_HOLD"]): time.sleep(0.1)' 'rows = [json.loads(l) for l in open(a["--dataset_name"])]' \
    'pred = json.loads(open(a["--predictions_path"]).read())' \
    'ok = a["--dataset_name"].endswith(".jsonl") and [r["instance_id"] for r in rows] == [a["--instance_ids"]] and "fixed" in pred["model_patch"]' \
    'open("conveyor.%s.json" % a["--run_id"], "w").write(json.dumps({"resolved_ids": [a["--instance_ids"]] if ok else []}))' > "$M/swebench/harness/run_evaluation.py"
  h() { env PYTHONPATH="$M" TMPDIR="$C/tmp" HOME="$C/home" HF_HOME="$C/home/hf" HF_DATASETS_CACHE="$C/home/hf/ds" python3 "$SRC/bench/swe_harness.py" "$@"; }
  h tasks o/ds rev1 "$C/list" || fail "tasks failed"
  [ "$(jq -r .id "$C/list" | tr '\n' ' ')" = 'o__p-1 o__p-2 ' ] || fail "the task list is not the dataset's tasks: $(cat "$C/list")"
  # Bug: the test command ran `docker run` of the task's image, which a card building inside that image cannot start.
  [ "$(head -n 1 "$C/list" | jq -r .cmd)" = 'source /opt/miniconda3/bin/activate && conda activate testbed && pytest' ] \
    || fail "the task's test command is not the one run in its own container: $(head -n 1 "$C/list")"
  ! grep -rlE 'REFFIX|HIDDENTEST' "$C" || fail "a reference fix or hidden test stayed on disk after the task list was made"
  echo fixed > "$C/patch"
  out=$(h grade o/ds rev1 o__p-2 "$C/patch" "$C/grade") && [ "$out" = '{"resolved": true}' ] \
    || fail "the grade did not give the official harness the task's own row as a .jsonl file: $out"
  ! grep -rlE 'REFFIX|HIDDENTEST' "$C" || fail "a reference fix or hidden test stayed on disk after the grade"
  h grade o/ds rev1 o__p-9 "$C/patch" "$C/grade9" > /dev/null; [ $? = 3 ] || fail "a task missing from the dataset was not reported as one the harness could not run"
  # Bug: `bench swe stop` sends SIGTERM to the grade, which then ended without removing its cache and the row in it.
  : > "$C/hold"; SWE_HOLD=$C/hold h grade o/ds rev1 o__p-1 "$C/patch" "$C/gradestop" > /dev/null 2>&1 &
  wait_until "[ -s '$C/hold.pid' ]" || { rm -f "$C/hold"; fail "the stopped grade did not reach the official harness"; }
  kill -TERM "$(cat "$C/hold.pid")"; wait $!; rm -f "$C/hold"
  [ -z "$(ls -A "$C/tmp")" ] && ! grep -rlE 'REFFIX|HIDDENTEST' "$C" || fail "a grade stopped with SIGTERM left its cache, with the reference fix and hidden tests, on disk"
}
