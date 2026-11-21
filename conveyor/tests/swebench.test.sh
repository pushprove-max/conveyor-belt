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
# changed): each one's `run` notes "<version> <issue title>" in $SWE_FX/log, waits while $SWE_FX/hold is there, exits 1 while
# $SWE_FX/efail is there, blocks its card with no change while $SWE_FX/eblock is there, and writes the card's records; A lands "fixed" in x.py for every task, B blocks the task proj__a-1 after two NO-GO
# reviews, each read by the judge. <folder>/py is the stub harness: the two tasks, an image fetch that waits while
# $SWE_FX/ihold is there and fails when $SWE_FX/broken names it, and a grade that resolves a patch holding "fixed" unless $SWE_FX/wrong names the task (or prints $SWE_FX/gradeout, when it is there).
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
[ ! -e "$SWE_FX/efail" ] || { echo ENGINE-FAIL-SAID; exit 1; }
# The real loop starts no card unless its queue takes the task's issue: the dry pick on the sandbox's pack, control
# record and issue, by the engine under test (a fake that skipped it missed an arm's policy keeping the issue off).
# The issue is opened by the owner, as openissues() reads it from GitHub.
q=$(mktemp) && gh issue list --json number,title,body,labels,createdAt | jq -c 'map(.authorAssociation = "OWNER")' > "$q" \
  && p=$(bash "$SWE_SRC/conveyor.sh" pick --dry --issues "$q" --state "$CONVEYOR_MAIN/conveyor/state" 2>> "$SWE_FX/pick.err"); rm -f "$q"; [ -n "${p:-}" ] || exit 0
mkdir -p "$CONVEYOR_MAIN/conveyor/state"
rec() { jq -nc --arg s "$1" --arg r "$2" --arg w "${3:-}" --argjson j "${4:-null}" --arg t "${5:-}" '{card: "c1", issue: 1, step: $s, result: $r, reason: $w, time: "2026-11-01T00:00:00Z", tokens: {claude: 100, codex: 10}}
  + (if $j == null then {} else {judge: $j} end) + (if $t == "" then {} else {tail: $t} end)' >> "$CONVEYOR_MAIN/conveyor/state/cards.jsonl"; }
rec picked ok; rec build ok
# With $SWE_FX/eblock, the card blocks with no change, as an engine whose commit the container's git refuses.
[ ! -e "$SWE_FX/eblock" ] || { rec blocked blocked "commit: git: 'hook' is not a git command"; exit 0; }
# With $SWE_FX/ewait, the card stages its fix in its worktree, which starts at main, and commits nothing (the engine
# commits only to land: card()); its test step fails only what fails on main, and it
# waits for main to change as the real engine does (its live record and idle mark, mainred.sh mainwait()): it only loops, for
# 30 s at most, and then ends with nothing landed.
if [ -e "$SWE_FX/ewait" ]; then
  git -C "$CONVEYOR_MAIN" worktree add -q --detach "$CONVEYOR_CARDS/c1" main && echo fixed > "$CONVEYOR_CARDS/c1/x.py" && git -C "$CONVEYOR_CARDS/c1" add -A || exit 1
  rec test fail 'tests/t.py fails on main too'; echo "conveyor: card c1: every case it still fails fails on main too: it waits for main to change"
  echo '{"step": "test", "action": "waiting for main to change: tests/t.py fail on main at 0123456789ab too"}' > "$CONVEYOR_CARDS/c1.live"
  i=0; while [ $i -lt 300 ]; do : > "$CONVEYOR_CARDS/c1.idle"; sleep 0.1; i=$((i + 1)); done; rm -f "$CONVEYOR_CARDS/c1.idle"; exit 0 # sleep: the idle loop the trial must end, as the real loop's sleep 30
fi
# The project name this checkout's loop takes, as the real engine names it (and its machine slot file after it).
(set -- run; HERE=$SWE_SRC; . "$SWE_SRC/lib/paths.sh" && echo "$RTAG" > "$SWE_FX/rtag")
J='{"model":"m","tokens":{"claude":5,"codex":0},"accepted":[],"declined":[]}' # a judge session on the review
if [ "$V" = B ] && [[ $t == *a-1 ]]; then rec review NO-GO '[P1] x.py:1 the fix is wrong' "$J"; rec fix ok; rec review NO-GO '[P1] x.py:1 still wrong' "$J" $'[P1] x.py:1 still wrong\n[P2] y.py:2 past the cut reason'; rec blocked blocked 'review: the last review said NO-GO'; exit 0; fi
cp "$CONVEYOR_MAIN/conveyor/state/control.json" "$SWE_FX/control.seen"; cp "$CONVEYOR_MAIN/.conveyor/project.json" "$SWE_FX/pack.seen"; (set -- run; HERE=$SWE_SRC; . "$SWE_SRC/lib/paths.sh" && . "$SWE_SRC/lib/prompts.sh" && cardrules "$(gh issue view 1)") > "$SWE_FX/rules.seen" 2>&1
cat "$HOME/.codex/auth.json" > "$SWE_FX/codex.seen" 2>/dev/null || :
# The Codex sandbox the engine under test gives a review in this container (codexsb()).
(set -- run; HERE=$SWE_SRC; . "$SWE_SRC/lib/paths.sh" && . "$SWE_SRC/lib/control.sh" && codexsb read-only && echo "${CODEX_SB[*]}") > "$SWE_FX/sandbox.seen" 2>&1
# The Python files a card's test run writes beside the fix: the arm's exclude list keeps them out of the change.
mkdir -p "$CONVEYOR_MAIN/__pycache__" && echo PYC > "$CONVEYOR_MAIN/__pycache__/x.cpython-311.pyc" && echo PYC > "$CONVEYOR_MAIN/y.pyc"
rec review GO '' null 'no findings'; rec test pass '' null 'test output'; echo fixed > "$CONVEYOR_MAIN/x.py"; git -C "$CONVEYOR_MAIN" add -A; git -C "$CONVEYOR_MAIN" commit -qm fix; rec landed ok; gh issue close 1
EOF
  # The functions and globals the stage map (bench/stagemap.sh) starts each stage from, one file a stage or two.
  printf '%s\n' 'session() { :; }' > "$e/conveyor/lib/session.sh"; printf '%s\n' 'reviewed() { :; }' > "$e/conveyor/lib/review.sh"
  printf '%s\n' 'brief() { :; }' 'cardrules() { :; }' 'REVIEWT=r' 'FIX=f' > "$e/conveyor/lib/prompts.sh"; printf '%s\n' 'tests() { :; }' > "$e/conveyor/lib/testrun.sh"
  printf '%s\n' 'land() { :; }' 'rereview() { reviewed "$@"; }' > "$e/conveyor/lib/claim.sh"; printf '%s\n' 'push() { :; }' > "$e/conveyor/lib/push.sh"
  # B, the newer engine, has the fix and testFix seats (its control record's defaults name them); A has none.
  git -C "$e" add -A && git -C "$e" commit -qm A && git -C "$e" tag v1.0.0 \
    && sed -i 's/^V=A/V=B/' "$e/conveyor/lib/fake.sh" && printf '%s\n' 'reviewed() { echo stricter; }' > "$e/conveyor/lib/review.sh" \
    && echo '{"fix": null, "testFix": null}' > "$e/conveyor/lib/control-defaults.json" && git -C "$e" add -A \
    && git -C "$e" commit -qm 'review: stricter findings' && git clone -q --bare "$e" "$F/eng.git" && rm -rf "$e" || return 1
  cat > "$F/py" <<'EOF'
#!/usr/bin/env bash
shift # the harness script's path
case $1 in
  tasks) for t in proj__a-1 proj__b-2; do jq -nc --arg t "$t" --arg u "file://$SWE_FX/task.git" --arg b "$(git -C "$SWE_FX/task.git" rev-parse main)" \
      '{id: $t, repo: "o/proj", url: $u, base: $b, issue: "Fix x.py for \($t)", image: "img-\($t)", env: "source \"$SWE_FX/activate\"", cmd: "true"}'; done > "$4" ;;
  image) while [ -e "$SWE_FX/ihold" ]; do sleep 0.1; done; [ "$(cat "$SWE_FX/broken" 2>/dev/null)" != "$2" ] || exit 3 ;;
  # grade: its container named as the harness names it, with the run's ID ($7), held while $SWE_FX/ghold is there
  # and removed when the grade ends (left when it is killed).
  grade) echo "$2 $3 $4" >> "$SWE_FX/graded"; mkdir -p "$SWE_FX/boxes/sweb.eval.$4.conveyor-$7-$4"
    while [ -e "$SWE_FX/ghold" ]; do sleep 0.1; done; rm -rf "$SWE_FX/boxes/sweb.eval.$4.conveyor-$7-$4"
    if [ -s "$SWE_FX/gradeout" ]; then cat "$SWE_FX/gradeout"
    elif grep -q fixed "$5" && [ "$(cat "$SWE_FX/wrong" 2>/dev/null)" != "$4" ]; then echo '{"resolved":true}'; else echo '{"resolved":false}'; fi ;;
esac
EOF
  chmod +x "$F/py"
  # A task's env sources this stand-in for conda's activate, which, like that script, fails when it is given arguments
  # (it takes the first as the environment to start).
  printf '%s\n' '[ $# = 0 ] || { echo "no such environment: $1" >&2; return 1; }' 'export SWE_TASKENV=testbed' > "$F/activate" || return 1
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
  ps) ls "$B" 2>/dev/null ;; # every container, whatever the filter: the caller picks its own by name
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
  EA=$(git -C "$SWE_FX/eng.git" rev-parse 'v1.0.0^{commit}'); EB=$(git -C "$SWE_FX/eng.git" rev-parse main); TL=$B/tasks.$(jq -r .revision "$SRC/bench/swe.json").$(jq -j .seed "$SRC/bench/swe.json" | sha256sum | cut -c1-12).jsonl
  # Docker is the stand-in, the arms the fixture's, and the logins made-up files: the builder's account (`control
  # account`) holds a Claude login, CODEX_HOME a Codex one.
  export PATH=$SWE_FX/bin:$PATH CONVEYOR_BENCH_ARMS=$SWE_FX/arms CODEX_HOME=$T/$CASE/codex
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/acct" "$CODEX_HOME" && echo CLAUDE-LOGIN > "$T/$CASE/acct/.credentials.json" && echo CODEX-LOGIN > "$CODEX_HOME/auth.json" \
    && jq -cn --arg a "$T/$CASE/acct" '{accounts: [{name: "bench", configDir: $a}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && jq -c '.account = "bench"' "$ST/control.json" > "$ST/c.new" && mv "$ST/c.new" "$ST/control.json" || fail "the logins were not made"
  # The conveyor arm on both engines and Claude alone passed their preflight an hour ago (a case of the preflight runs it),
  # with the logins their seats take (the conveyor arm's builder m is Claude's, its reviewer x Codex's), on the pinned first task's image, swe.json's limits and task set.
  local k a img lim set now; img=img-$(sweorder | head -n 1); now=$(($(date +%s) - 3600))
  lim=$(jq -c '{cpus: .limits.cpus, memory: .limits.memory, taskTimeout}' "$SRC/bench/swe.json"); set=$(jq -c '{dataset, revision, seed}' "$SRC/bench/swe.json")
  for k in conveyor/$EA conveyor/$EB solo/solo-m; do a=${k%/*}; mkdir -p "$B/preflight/$a"
    jq -cn --arg k "${k#*/}" --argjson e "$now" --argjson s "$(jq -cS --arg n "$a" '.name = $n' "$SWE_FX/arms/$a.json")" --arg i "$img" --argjson lim "$lim" \
      --argjson set "$set" \
      '{arm: $s.name, key: $k, ok: true, why: null, at: "2026-11-17T00:00:00Z", epoch: $e, spec: $s, logins: (if $s.kind == "conveyor" then "claude codex" else "claude" end), image: $i, limits: $lim, set: $set}' \
      > "$B/preflight/$a/${k#*/}.json" || fail "the preflight passes were not kept"
  done
}
# The tasks in the pinned order: sha256 of "<seed>:<id>", as swe.json's seed (or the seed given) gives it.
sweorder() { local s=${1:-} t; [ -n "$s" ] || s=$(jq -r .seed "$SRC/bench/swe.json"); for t in proj__a-1 proj__b-2; do printf '%s %s\n' "$(printf '%s:%s' "$s" "$t" | sha256sum | cut -c1-64)" "$t"; done | sort | cut -d ' ' -f 2; }

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
  jq -e --arg e "$EB" '.sessions == 2 and .tokens == 440 and (.minutes | type) == "number" and .engine == $e and .resolved' "$B"/results/*-"$EB/$first.json" > /dev/null \
    || fail "the task's result holds no sessions, tokens, minutes or engine: $(cat "$B"/results/*-"$EB/$first.json")"
  [ "$(tail -n 1 "$B/runs.jsonl" | jq -c --arg e "$EB" '[.n, .resolved, .engine == $e, .state]')" = '[2,1,true,"done"]' ] || fail "the run's line is not 1 of 2 resolved with its engine: $(tail -n 1 "$B/runs.jsonl")"
  grep -q "Resolved 1 of 2 with engine main ($EB)" <<<"$out" || fail "the run did not end with its resolved count and engine commit: $out"
  out=$(loop bench swe 3 2>&1) && fail "an n past the task list was taken: $out"
  out=$(loop bench swe 501 2>&1); [ $? = 2 ] || fail "n 501 was not refused as a wrong argument: $out"
  # The Board's tab reads the presets, the last run and the versions a run can pick from the snapshot (the results it
  # reads with bench swe history: t_swehistory).
  [ "$(jq -c .presets "$SRC/bench/swe.json")" = '[1,5,20,50]' ] \
    && [ "$(loop snapshot --fresh | jq -c '[.bench.presets, .bench.live.state, (.bench.versions | map(.name))]')" = '[[1,5,20,50],"done",["main","v1.0.0"]]' ] \
    || fail "the snapshot does not carry the Benchmarks tab's presets, last run and versions: $(loop snapshot --fresh | jq -c .bench)"
  # A run whose process was killed with no end written is not shown running for good, nor at a step (#643).
  jq -c '.live.state = "running" | .live.pid = 2147483646 | .live.active = {arm: "conveyor", task: "t", phase: "Building"}' "$B/board.json" > "$B/b.new" && mv "$B/b.new" "$B/board.json"
  [ "$(loop snapshot --fresh | jq -c '.bench.live | [.state, .active]')" = '["stopped",null]' ] || fail "a run whose process is gone is shown running"
}

# A release of the fixture engine: a new commit on main, tagged <tag> (an annotated tag, which ls-remote lists twice).
swerelease() { # <tag>
  local w=$T/$CASE/rel; rm -rf "$w"; git clone -q "$SWE_FX/eng.git" "$w" && git -C "$w" commit -q --allow-empty -m "release $1" \
    && git -C "$w" tag -a -m "$1" "$1" && git -C "$w" push -q origin main "$1" || fail "the release $1 was not made"
}
# Bug (#1014): the snapshot's versions were board.json's, written only by a benchmark run: before any run the
# Benchmarks tab listed none, and a release made since the last run, or a new main, never showed.
t_sweversnow() {
  swe; local o head
  o=$(loop snapshot --fresh | jq -c .bench) && [ "$o" = "$(jq -nc --arg a "$EA" --arg b "$EB" '{versions: [{name: "main", commit: $b}, {name: "v1.0.0", commit: $a}]}')" ] \
    || fail "before any run the snapshot's bench part does not list the versions: $o"
  # A board.json as the last run left it, with that run's list (main at v1.0.0 only): the list now must replace it.
  mkdir -p "$B" && jq -nc --arg a "$EA" '{presets: [1], live: {state: "done"}, versions: [{name: "main", commit: $a}, {name: "v1.0.0", commit: $a}]}' > "$B/board.json"
  swerelease v1.1.0; head=$(git -C "$SWE_FX/eng.git" rev-parse main)
  o=$(loop snapshot --fresh | jq -c '.bench') && [ "$(jq -c '[.presets, .live.state]' <<<"$o")" = '[[1],"done"]' ] && o=$(jq -c .versions <<<"$o") \
    && [ "$(jq -c 'map(.name)' <<<"$o")" = '["main","v1.1.0","v1.0.0"]' ] \
    && [ "$o" = "$(loop bench swe versions 2>&1)" ] && [ "$(jq -r '.[0:2] | map(.commit) | unique[]' <<<"$o")" = "$head" ] \
    || fail "with no run since, the snapshot does not replace the last run's list with the new release, and main at its head, as bench swe versions does, keeping the run's other parts: $o"
}
# Bug (#1014): with no source set, the versions are the engine checkout's origin's. The snapshot reads them from the
# checkout itself, with no network call (its origin here is a URL no test reaches): a release tag made there shows at
# once, and main is origin/main, not a local main ahead of it. The function is called on a clone standing in for the
# checkout (HERE).
t_sweverslocal() {
  swe; local w=$T/$CASE/eng o
  git clone -q "$SWE_FX/eng.git" "$w" && mkdir -p "$w/conveyor" && git -C "$w" tag -a -m r v1.1.0 \
    && git -C "$w" commit -q --allow-empty -m 'not pushed' && git -C "$w" remote set-url origin https://example.com/eng.git || fail "the checkout was not made"
  o=$(unset CONVEYOR_BENCH_SOURCE; export HERE=$w/conveyor RTAG=x; . "$SRC/bench/swe.sh" && swe_versionsnow) \
    && [ "$o" = "$(jq -nc --arg a "$EA" --arg b "$EB" '[{name: "main", commit: $b}, {name: "v1.1.0", commit: $b}, {name: "v1.0.0", commit: $a}]')" ] \
    || fail "the checkout's tags and origin/main were not read: $o"
}
# Bug (#1014): the snapshot never read a source named by URL. It reads it now, so the read must stay cheap: the list
# is kept for the hour and read again after it, and a source that cannot be reached leaves the last list. The URL is
# rewritten to the fixture's folder (insteadOf), so no network is used.
t_sweversurl() {
  swe; local o
  export CONVEYOR_BENCH_SOURCE=https://example.com/eng.git GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.file://$SWE_FX/eng.git.insteadOf \
    GIT_CONFIG_VALUE_0=https://example.com/eng.git CONVEYOR_NOW=1700000000
  o=$(loop snapshot --fresh | jq -c '.bench.versions | map(.name)') && [ "$o" = '["main","v1.0.0"]' ] || fail "the URL source's versions were not read: $o"
  swerelease v1.1.0
  o=$(loop snapshot --fresh | jq -c '.bench.versions | map(.name)') && [ "$o" = '["main","v1.0.0"]' ] || fail "the URL source was read again within the hour: $o"
  o=$(CONVEYOR_NOW=1700003600 loop snapshot --fresh | jq -c '.bench.versions | map(.name)') && [ "$o" = '["main","v1.1.0","v1.0.0"]' ] \
    || fail "the URL source was not read again in the next hour: $o"
  mv "$SWE_FX/eng.git" "$SWE_FX/gone.git"
  o=$(CONVEYOR_NOW=1700007200 loop snapshot --fresh | jq -c '.bench.versions | map(.name)') && [ "$o" = '["main","v1.1.0","v1.0.0"]' ] \
    || fail "a source that cannot be reached dropped the last list read: $o"
}

# Bug: the dataset's rows an earlier harness kept (raw.<revision>.jsonl, with the reference fixes and hidden tests)
# stayed in the state folder, readable by a card's sessions, when the task list of that revision was already made.
t_sweoldraw() {
  swe; local rev out; rev=$(jq -r .revision "$SRC/bench/swe.json")
  # The earlier list's tasks have no cmd (the test command run in the task's container), as an earlier harness made it.
  mkdir -p "$B" && "$SWE_FX/py" - tasks d r "$B/t" && jq -c 'del(.cmd)' "$B/t" > "$TL" && echo REFFIX > "$B/raw.$rev.jsonl" && echo REFFIX > "$B/raw.older.jsonl" \
    || fail "the earlier run's files were not made"
  out=$(loop bench swe 3 2>&1); [ $? = 2 ] || fail "an n past the task list was not refused: $out"
  [ -z "$(ls "$B"/raw.*.jsonl 2>/dev/null)" ] || fail "the dataset's rows an earlier harness kept are still in the state folder: $(ls "$B")"
  # Bug: the list kept from before was used, and every conveyor arm's card got an empty test command.
  jq -se 'length == 2 and all(.cmd == "true")' "$TL" > /dev/null || fail "a task list with no test commands was not made again: $(cat "$TL")"
  # Bug: a list kept from before with no env (the commands that start the task's environment) gave every conveyor
  # arm's card a one-file test command run outside that environment.
  jq -c 'del(.env)' "$TL" > "$B/t" && mv -f "$B/t" "$TL" || fail "the list with no env was not made"
  out=$(loop bench swe 3 2>&1); [ $? = 2 ] || fail "an n past the task list was not refused: $out"
  jq -se 'length == 2 and all(.env == "source \"$SWE_FX/activate\"")' "$TL" > /dev/null || fail "a task list with no env was not made again: $(cat "$TL")"
}

# Bug: a task whose Docker image cannot be fetched or built is counted as failed (or stops the run) instead of being
# reported as not run, with no result kept, so the next run tries it again.
t_swenotrun() {
  swe; local first second out
  { read -r first; read -r second; } < <(sweorder)
  echo "img-$first" > "$SWE_FX/broken"
  out=$(loop bench swe 2 2>&1) || fail "the run failed: $out"
  grep -q "1/2 $first: not run: its Docker image could not be fetched or built" <<<"$out" || fail "the task with no image was not reported as not run: $out"
  ! compgen -G "$B/results/*-$EB/$first.json" > /dev/null && compgen -G "$B/results/*-$EB/$second.json" > /dev/null || fail "a result was kept for the task not run, or none for the other"
  grep -q "Resolved 0 of 2 .*not run: 1\." <<<"$out" || fail "the run's total does not set the task not run apart: $out"
  [ "$(cat "$SWE_FX/log")" = "B SWE-bench $second" ] || fail "the task with no image was built: $(cat "$SWE_FX/log")"
}

# Bug: --engine builds with main's engine whatever it names, or a release is not taken by its name; results of two
# engine commits are kept apart, each with its release's name.
t_sweengine() {
  swe; local out
  out=$(loop bench swe 1 --engine v1.0.0 2>&1) || fail "the run on v1.0.0 failed: $out"
  out=$(loop bench swe 1 --engine "$EB" 2>&1) || fail "the run on a commit failed: $out"
  [ "$(cut -d ' ' -f 1 "$SWE_FX/log" | tr '\n' ' ')" = 'A B ' ] || fail "the tasks were not built with the engines named: $(cat "$SWE_FX/log")"
  [ "$(cat "$B"/results/*-"$EA"/*.json | jq -r .version)" = v1.0.0 ] || fail "the result of the release does not name it"
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
  cat "$B"/results/*-"$EB"/*.json | jq -se '[.[].steps[] | select(has("tail")) | .step + " " + .result] == ["review NO-GO"]' > /dev/null \
    || fail "a tail was kept other than the NO-GO review's: $(cat "$B"/results/*-"$EB"/*.json | jq -sc '[.[].steps[] | select(has("tail"))]')"
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
  # Docker's own confinement is taken off a conveyor arm's container only, for Codex's sandbox (swe_box).
  ! grep '^create ' "$SWE_FX/docker.log" | grep -qE -- '--security-opt|--cap-add' || fail "the solo arm's container runs with Docker's confinement off: $(grep '^create ' "$SWE_FX/docker.log")"
  local a; a=$(tail -n 1 "$STUB/sessions")
  [[ $a == *'--permission-mode dontAsk'* && $a == *'--tools Read,Grep,Glob,Edit,Write '* && $a == *"Edit(/$B/work/$first/swe-${R##*/}/**)"* \
    && $a == *'--setting-sources  --strict-mcp-config'* && $a != *bypassPermissions* ]] \
    || fail "the solo session is not held to its sandbox's files with no shell: $a"
  [ ! -s "$SWE_FX/log" ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "the solo run did not take one Claude session and no engine"
  jq -e '.arm == "solo" and .model == "m" and .sessions == 1 and .tokens == 35 and .resolved and .engine == null' "$B"/results/solo-m-*/"$first.json" > /dev/null \
    || fail "the solo result is not one session's: $(cat "$B"/results/solo-m-*/"$first.json" 2>&1)"
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
  jq -e '.fired == false and .resolved == false and (.why | startswith("its command failed"))' "$B"/results/solo-m-*/"$first.json" > /dev/null \
    && [ ! -e "$SWE_FX/graded" ] || fail "the failed trial was not kept as not fired, or its change was graded: $(cat "$B"/results/solo-m-*/"$first.json" 2>&1)"
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
  grep -q "1/1 $first: unresolved$" <<<"$out" && jq -e '.resolved == false' "$B"/results/*-"$EB/$first.json" > /dev/null \
    || fail "an unresolved grade was not kept as unresolved: $out"
  out=$(loop bench swe 1 2>&1) && grep -q "1/1 $first: unresolved (reused)" <<<"$out" || fail "the unresolved task was built again: $out"
  [ "$(sort -u "$SWE_FX/graded")" = "$(jq -r '"\(.dataset) \(.revision)"' "$SRC/bench/swe.json") $first" ] \
    || fail "the grade was not told the pinned dataset and revision to read the task's row from: $(cat "$SWE_FX/graded")"
  out=$(loop bench swe diff v1.0.0 main --json 2>&1) && [ "$(jq -c '[.tasks, (.flipped | length), .withinNoise]' <<<"$out")" = '[1,1,false]' ] \
    || fail "a complete flip of one task was called within the noise: $out"
}

# Bug (#326): the Board's Benchmarks tab had no history of the runs, no figures of each arm and no task of a run to
# open; and the snapshot carried every run and result, past its size budget. history gives every run newest first (a
# run whose process is gone shows stopped) with each arm's resolved, not run, sessions and tokens, and the arms with
# their state; show gives one run's tasks in its order, each arm's result and patch; neither is in the snapshot.
t_swehistory() {
  swe; local p o
  mkdir -p "$B/results/stub-a" "$B/results/stub-b" && jq -nc --arg i "img-$(sweorder | head -n 1)" '{id: "proj__b-2", issue: "\nSecond line first\nmore", image: $i}, {id: "proj__a-1", issue: "First task"}' > "$TL" \
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
  [ "$(jq -c 'def fp: if . then gsub("[0-9a-f]{12}"; "F") else . end; [(.arms | map(select(.name | IN("solo", "stub-a", "conveyor"))) | map([.name, .state, (.key | fp), (.keyPrefix | fp)])), (.keys | map([.key, .at]))]' <<<"$o")" \
    = '[[["conveyor","ready",null,"F-"],["solo","ready","solo-m-F",null],["stub-a","unchecked","stub-a-F",null]],[["stub-a",[0,1]],["stub-b",[1]]]]' ] \
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
    '             "patch": "REFFIX-%d" % i, "test_patch": "HIDDENTEST-%d" % i, "FAIL_TO_PASS": "[\"t1\"]", "PASS_TO_PASS": "[]"} for i in (1, 2)]' \
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
    'open("conveyor.%s.json" % a["--run_id"], "w").write(json.dumps({"resolved_ids": [a["--instance_ids"]] if ok else []}))' \
    'd = "logs/run_evaluation/%s/conveyor/%s" % (a["--run_id"], a["--instance_ids"]); os.makedirs(d)' \
    'open(d + "/report.json", "w").write(json.dumps({a["--instance_ids"]: {"tests_status": {"FAIL_TO_PASS": {"success": ["t1"] if ok else []}}}}))' > "$M/swebench/harness/run_evaluation.py"
  h() { env PYTHONPATH="$M" TMPDIR="$C/tmp" HOME="$C/home" HF_HOME="$C/home/hf" HF_DATASETS_CACHE="$C/home/hf/ds" python3 "$SRC/bench/swe_harness.py" "$@"; }
  h tasks o/ds rev1 "$C/list" || fail "tasks failed"
  [ "$(jq -r .id "$C/list" | tr '\n' ' ')" = 'o__p-1 o__p-2 ' ] || fail "the task list is not the dataset's tasks: $(cat "$C/list")"
  # Bug: the test command ran `docker run` of the task's image, which a card building inside that image cannot start.
  [ "$(head -n 1 "$C/list" | jq -r .cmd)" = 'source /opt/miniconda3/bin/activate && conda activate testbed && pytest' ] \
    || fail "the task's test command is not the one run in its own container: $(head -n 1 "$C/list")"
  # Bug: a card's one-file test command ran outside the task's environment (python3 with no pytest or task packages):
  # the task names the commands that start it, for the pack's test.fileCommand (swe_filecmd).
  [ "$(head -n 1 "$C/list" | jq -r .env)" = 'source /opt/miniconda3/bin/activate && conda activate testbed' ] \
    || fail "the task does not name the commands that start its environment: $(head -n 1 "$C/list")"
  ! grep -rlE 'REFFIX|HIDDENTEST' "$C" || fail "a reference fix or hidden test stayed on disk after the task list was made"
  echo fixed > "$C/patch"
  out=$(h grade o/ds rev1 o__p-2 "$C/patch" "$C/grade" r1) && [ "$(jq -c .resolved <<<"$out")" = true ] \
    || fail "the grade did not give the official harness the task's own row as a .jsonl file: $out"
  # Bug (#645): the harness run, and so its container (sweb.eval.<task>.<run id>), did not name the benchmark run, so
  # a Stop of that run could not find the grading container to remove it.
  [ -e "$C/grade/conveyor.conveyor-r1-o__p-2.json" ] || fail "the grade's harness run did not carry the benchmark run's ID: $(ls "$C/grade")"
  ! grep -rlE 'REFFIX|HIDDENTEST' "$C" || fail "a reference fix or hidden test stayed on disk after the grade"
  h grade o/ds rev1 o__p-9 "$C/patch" "$C/grade9" r1 > /dev/null; [ $? = 3 ] || fail "a task missing from the dataset was not reported as one the harness could not run"
  # Bug: `bench swe stop` sends SIGTERM to the grade, which then ended without removing its cache and the row in it.
  : > "$C/hold"; SWE_HOLD=$C/hold h grade o/ds rev1 o__p-1 "$C/patch" "$C/gradestop" r1 > /dev/null 2>&1 &
  wait_until "[ -s '$C/hold.pid' ]" || { rm -f "$C/hold"; fail "the stopped grade did not reach the official harness"; }
  kill -TERM "$(cat "$C/hold.pid")"; wait $!; rm -f "$C/hold"
  [ -z "$(ls -A "$C/tmp")" ] && ! grep -rlE 'REFFIX|HIDDENTEST' "$C" || fail "a grade stopped with SIGTERM left its cache, with the reference fix and hidden tests, on disk"
}
