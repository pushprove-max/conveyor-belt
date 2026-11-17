#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: `conveyor.sh bench swe` (bench/swe.sh), the SWE-bench Verified benchmark. A fake dataset of 2 tiny tasks
# and a stub harness (CONVEYOR_BENCH_PYTHON) stand in for the real ones; the engine versions are two commits of a
# fixture engine (CONVEYOR_BENCH_SOURCE) whose `run` builds the sandbox's one issue as the commit says. No model call
# and no download: the test stubs answer for claude.
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
rec() { jq -nc --arg s "$1" --arg r "$2" --arg w "${3:-}" --argjson j "${4:-null}" '{card: "c1", issue: 1, step: $s, result: $r, reason: $w, time: "2026-11-01T00:00:00Z", tokens: {claude: 100, codex: 10}}
  + (if $j == null then {} else {judge: $j} end)' >> "$CONVEYOR_MAIN/conveyor/state/cards.jsonl"; }
rec picked ok; rec build ok
# The project name this checkout's loop takes, as the real engine names it (and its machine slot file after it).
(set -- run; HERE=$SWE_SRC; . "$SWE_SRC/lib/paths.sh" && echo "$RTAG" > "$SWE_FX/rtag")
J='{"model":"m","tokens":{"claude":5,"codex":0},"accepted":[],"declined":[]}' # a judge session on the review
if [ "$V" = B ] && [[ $t == *a-1 ]]; then rec review NO-GO '[P1] x.py:1 the fix is wrong' "$J"; rec fix ok; rec review NO-GO '[P1] x.py:1 still wrong' "$J"; rec blocked blocked 'review: the last review said NO-GO'; exit 0; fi
rec review GO; rec test pass; echo fixed > "$CONVEYOR_MAIN/x.py"; git -C "$CONVEYOR_MAIN" commit -qam fix; rec landed ok; gh issue close 1
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
      '{id: $t, repo: "o/proj", url: $u, base: $b, issue: "Fix x.py for \($t)", image: "img-\($t)", test: "true"}'; done | tee "$4" > "$4.jsonl" ;;
  image) [ "$(cat "$SWE_FX/broken" 2>/dev/null)" != "$2" ] || exit 3 ;;
  grade) echo "$2 $3" >> "$SWE_FX/graded"
    if grep -q fixed "$4" && [ "$(cat "$SWE_FX/wrong" 2>/dev/null)" != "$3" ]; then echo '{"resolved":true}'; else echo '{"resolved":false}'; fi ;;
esac
EOF
  chmod +x "$F/py"
}
# A case's main (setup), the fixture copied to $SWE_FX, the versions folder its own, and the bench pointed at both.
swe() {
  setup '[]'; template swe swemake || fail "the SWE-bench fixture was not made"
  export SWE_FX=$T/$CASE/fx XDG_DATA_HOME=$T/$CASE/data; cp -a "$FIXTURE.swe/." "$SWE_FX/" || fail "the fixture was not copied"
  export CONVEYOR_BENCH_PYTHON=$SWE_FX/py CONVEYOR_BENCH_SOURCE=file://$SWE_FX/eng.git B=$ST/bench/swe SWE_SRC=$SRC
  trap 'chmod -R u+w "$T/$CASE"' EXIT
  EA=$(git -C "$SWE_FX/eng.git" rev-parse 'v1.0.0^{commit}'); EB=$(git -C "$SWE_FX/eng.git" rev-parse main)
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
  # The Board's part reads the presets, the last run, the results and the versions a run can pick from the snapshot.
  [ "$(jq -c .presets "$SRC/bench/swe.json")" = '[1,5,20,50]' ] \
    && [ "$(loop snapshot | jq -c '[.bench.presets, .bench.live.state, (.bench.keys | length), (.bench.versions | map(.name))]')" = '[[1,5,20,50],"done",1,["main","v1.0.0"]]' ] \
    || fail "the snapshot does not carry the Benchmarks part with its presets and versions: $(loop snapshot | jq -c .bench)"
  # A run whose process was killed with no end written is not shown running for good.
  jq -c '.live.state = "running" | .live.pid = 2147483646' "$B/board.json" > "$B/b.new" && mv "$B/b.new" "$B/board.json"
  [ "$(loop snapshot | jq -r .bench.live.state)" = stopped ] || fail "a run whose process is gone is shown running"
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
  jq -e '.flipped[0] | .b.findings == ["[P1] x.py:1 the fix is wrong", "[P1] x.py:1 still wrong"] and .b.fixRounds == 1 and (.reading | startswith("B blocked at review"))' <<<"$out" > /dev/null \
    || fail "the flipped task's facts or the model's reading are missing: $(jq -c .flipped[0] <<<"$out")"
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
  echo 'echo fixed > x.py; command -v gh > "$STUB/solo-gh"' > "$STUB/build"
  out=$(loop bench swe 1 --solo 2>&1) || fail "the solo run failed: $out"
  # Bug: the session ran in bypass mode on the host, with a shell, the real gh, and the dataset's reference patches and
  # hidden tests in reach. The CLI's own confinement cannot run here (the claude stub): its arguments are what is checked.
  [ "$(cat "$STUB/solo-gh")" = "$B/work/$first/bin/gh" ] || fail "the solo session was not given the sandbox's gh: $(cat "$STUB/solo-gh")"
  local a; a=$(tail -n 1 "$STUB/sessions")
  [[ $a == *'--permission-mode dontAsk'* && $a == *'--tools Read,Grep,Glob,Edit,Write '* && $a == *"Edit(/$B/work/$first/swe-${R##*/}/**)"* \
    && $a == *"Read(/$B/raw.*)"* && $a == *'--setting-sources  --strict-mcp-config'* && $a != *bypassPermissions* ]] \
    || fail "the solo session is not held to its sandbox's files with no shell: $a"
  [ ! -s "$SWE_FX/log" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "the solo run did not take one Claude session and no engine"
  jq -e '.arm == "solo" and .model == "m" and .sessions == 1 and .tokens == 35 and .resolved and .engine == null' "$B/results/solo-m/$first.json" > /dev/null \
    || fail "the solo result is not one session's: $(cat "$B/results/solo-m/$first.json" 2>&1)"
  grep -q 'Fix x.py for' "$STUB/brief" || fail "the session was not given the issue"
  # Bug: the Board read the solo key board.json kept from its last run, so after the builder's model changed it
  # counted the old model's results as reused and showed no sessions for a run that builds every task.
  jq -c '.model = {cli: "claude", model: "claude-haiku-5-5"}' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json"
  [ "$(loop snapshot | jq -r .bench.soloKey)" = solo-claude-haiku-5-5 ] || fail "the snapshot's solo key is not the builder's model in force: $(loop snapshot | jq -c .bench.soloKey)"
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
}

# Bugs: a graded patch the harness found unresolved was reported as not run and kept no result, so the next run built
# it again; the grade was given the dataset's rows in a file the official harness cannot load (it reads a local dataset
# only from .json, .jsonl or .parquet); the worst case left out the judge's sessions, and the fix of a failed test
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
  [ "$(cut -d ' ' -f 1 "$SWE_FX/graded" | sort -u)" = "$B/raw.$(jq -r .revision "$SRC/bench/swe.json").jsonl" ] && [ -s "$(head -n 1 "$SWE_FX/graded" | cut -d ' ' -f 1)" ] \
    || fail "the grade was not given the dataset's rows as a .jsonl file: $(cat "$SWE_FX/graded")"
  out=$(loop bench swe diff v1.0.0 main --json 2>&1) && [ "$(jq -c '[.tasks, (.flipped | length), .withinNoise]' <<<"$out")" = '[1,1,false]' ] \
    || fail "a complete flip of one task was called within the noise: $out"
}
