# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh bench swe`: SWE-bench Verified tasks built by one or more arms and graded by the official harness.
# Sourced by commands/bench.sh after the engine files it uses (paths, records, slots, prompts, control, install, session).
#   bench swe <n> [--arm <arm>]... [--solo] [--engine <version | commit>] [--settings <json>]
#                                      runs the first n tasks of the pinned order (1 to 500) with each arm (default:
#                                      conveyor; --solo is --arm solo; --engine is the version a conveyor arm runs;
#                                      --settings the task set and limits every arm shares, swe_settings)
#   bench swe arms [check [--settings <json>] <arm>...]
#                                      the arms with their preflight state; check runs those arms' preflights
#   bench swe arms save <name> <spec>  keeps a saved arm's choices as a new revision and prints its ID (swe_armsave)
#   bench swe arms show <id>           a saved revision as it was saved
#   bench swe stop                     ends the run in progress
#   bench swe results [--json]         the results of every arm and version so far, side by side
#   bench swe history                  every run newest first with each arm's figures, and every arm's state, as JSON
#                                      (the Board's Benchmarks tab; swe_history says what it holds)
#   bench swe show <run>               one run's tasks with each arm's result, steps and patch, as JSON (swe_show)
#   bench swe diff <A> <B> [--json]    why two arms or versions differ on the tasks both ran; A and B are each a
#                                      version (the conveyor arm's), an arm, <arm>@<version> for a conveyor arm,
#                                      or a results key (bench swe results --json)
#   bench swe versions                 the engine versions a run can take: main and each release
# The task list: swe.json beside this file pins the dataset, its revision and a seed (a run's settings may name
# another revision and seed); the tasks are in the order of sha256("<seed>:<task id>"), so `swe 5` is always the
# first 5 of `swe 20`. The harness side (the task list, each
# task's Docker image, the grade) is swe_harness.py, run by the Python of the swebench virtualenv (SWE_VENV), else
# python3; CONVEYOR_BENCH_PYTHON names another (the tests' stub harness). Engine versions are taken from
# CONVEYOR_BENCH_SOURCE (default: this checkout's origin) and installed in the versions folder (install(),
# lib/install.sh): only the card building runs the old engine; the task setup, the grade and the results are always
# this harness's.
# The arms are swe_arms.sh's (one JSON file each under arms/). An arm runs only once its preflight passed
# (swe_ready). Each task is set up in a sandbox under the state folder's bench/swe/work: a bare origin holding the
# task's base commit (fetched from the task's repository, never pushed to), a clone of it as the main checkout, and a
# gh on PATH that serves the issue text as issue #1 and writes nothing to GitHub. Each arm then builds it in a Docker
# container of its own (swe_trial): a conveyor arm's engine loop builds that one card (`conveyor.sh run 1`) with a
# pack made for it (the task's test command, no checks, no follow-ups, the rules the arm takes) and a control record
# from the project's own (its seats and the arm's, its cap, none of its per-issue seats; follow-ups and visible-change
# asks off, a push after each landing on, to the sandbox's own origin), and its patch is what landed on the sandbox's main (a blocked card's is empty); another
# arm's command runs on the issue, and its change is the patch. An arm that does not fire is a failed task of it.
# What is kept, under the state folder's bench/swe: tasks.<revision>.<seed's id>.jsonl (the ordered list, swe_list),
# results/<key>/<task>.json (key: swe_reskey(), from the trial's effective inputs, swe_inputs; resolved, fired,
# sessions, tokens, minutes, a card's records, the inputs) and .patch, preflight/<arm>/<key>.json (key: swe_armkey()),
# arms/<id>.json (each saved arm revision, swe_armsave), frozen/<arm> while a run goes (its copy of what a conveyor
# arm reads of the project, swe_freeze),
# a line a run in runs.jsonl, the run in progress in live.json, and board.json, what the snapshot carries for the
# Board's Benchmarks tab (the tab reads the runs and results with history and show).
# The dataset's rows (each task's reference fix and hidden tests) are never kept: the card's sessions have a shell as
# this account, so the harness reads them into a cache of its own that it removes, for the task list and each grade.
# A result of the same key and task whose recorded inputs are the trial's now is reused, never run again: another
# model, rule, engine, task set or limit is another key. A result kept before its inputs were recorded is read, never reused. A task whose image cannot be fetched or built, whose
# container could not be made, or that the harness could not grade, is not run: no result is kept, and the run names
# it apart from the failed ones.
SWE_CONF=$HERE/bench/swe.json
SWE_DIR=$ST/bench/swe
# The folder name of a sandbox's main checkout. The engine names a project with no host record by its checkout's folder,
# and keeps the project's machine slot file (lib/pick.sh) under that name: swe-<this project>, so the benchmarks of two
# projects that run at once never share one slot file, and neither takes the name of a project called main.
SWE_MAIN=swe-$RTAG
# The harness's Python: the swebench virtualenv's (docs/benchmarks.md says how to make it), else python3.
SWE_VENV=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/swebench-venv
swe_h() {
  local py=${CONVEYOR_BENCH_PYTHON:-}
  [ -n "$py" ] || { py=$SWE_VENV/bin/python3; [ -x "$py" ] || py=python3; }
  "$py" "${BASH_SOURCE[0]%/*}/swe_harness.py" "$@"
}
# The build machine can run a benchmark: Docker answers, and the harness has the swebench swe.json pins. Run before a
# run or an arms check reads the task list, as a saved list (swe_tasks) or result never calls the harness. Says on
# stderr, as the Board shows it, what to repair.
swe_setup() {
  local b
  docker info > /dev/null 2>&1 \
    || { echo "conveyor: Docker did not answer on the build machine. Install or start Docker, check that \`docker info\` works, then check again." >&2; return 1; }
  # No Python, or a harness that cannot start, prints nothing: as no harness.
  b=$(swe_h check 2> /dev/null) \
    || { echo "conveyor: ${b:-The build machine has no SWE benchmark harness. Install it in the benchmark virtual environment, then check again.}" >&2; return 1; }
}
swe_conf() { jq -r "$1" "$SWE_CONF"; }
swe_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
swe_put() { printf '%s\n' "$2" > "$1.$$" && mv -f "$1.$$" "$1"; } # <file> <text>: written whole
# The settings every arm of a run or check shares, SWE_SET: the task set (swe.json's dataset, the dataset's revision
# and the seed of the order) and the limits of each trial's container (cpus, memory as Docker takes it, and
# taskTimeout, the seconds its install and its run may each take; its preflight command has a fixed limit of its own,
# swe_trial). swe.json's, with the --settings a run or check names over them: an object of revision (a full commit
# id), seed (1 to 80 characters), cpus, memory (<n>m or <n>g, 512m and up) and taskTimeout (60 to 86400), each
# optional. Refuses another key, a value of another shape, and more CPUs or memory than this machine has.
swe_settings() { # [<settings json>]
  local s=${1:-} w c=0 m=0
  [ -n "$s" ] || s='{}'
  s=$(jq -ce 'objects' <<<"$s" 2>/dev/null) || { echo "conveyor: the settings are not a JSON object" >&2; return 2; }
  if [ "$s" != '{}' ]; then # this machine's CPUs and memory (KiB); 0 when it does not say
    c=$(getconf _NPROCESSORS_ONLN 2>/dev/null) && [[ $c =~ ^[0-9]+$ ]] || c=0
    m=$(p_mem | awk '{ print $2 }') && [[ $m =~ ^[0-9]+$ ]] || m=0
  fi
  w=$(jq -rn --argjson s "$s" --argjson c "$c" --argjson m "$m" '
    def kib: capture("^(?<n>[1-9][0-9]{0,6})(?<u>[mg])$") | (.n | tonumber) * (if .u == "g" then 1048576 else 1024 end);
    (($s | keys) - ["revision", "seed", "cpus", "memory", "taskTimeout"]) as $x
    | [ if $x != [] then "the settings are revision, seed, cpus, memory and taskTimeout, not \($x | join(", "))" else empty end,
      if $s | has("revision") and (.revision | type != "string" or (test("^[0-9a-f]{40}$") | not)) then "the revision is the dataset revision'"'"'s full commit id" else empty end,
      if $s | has("seed") and (.seed | type != "string" or length < 1 or length > 80 or test("[[:cntrl:]]")) then "the seed is 1 to 80 characters with no control character" else empty end,
      if $s | has("cpus") | not then empty elif ($s.cpus | type) != "number" or $s.cpus <= 0 then "cpus is a number above 0"
        elif $c > 0 and $s.cpus > $c then "cpus is at most \($c), the CPUs of this machine" else empty end,
      if $s | has("memory") | not then empty elif ($s.memory | type) != "string" or ([$s.memory | kib] | length) == 0 or ($s.memory | kib) < 524288 then "memory is <n>m or <n>g, 512m or more"
        elif $m > 0 and ($s.memory | kib) > $m then "memory is at most the \($m / 1048576 | floor)g this machine holds" else empty end,
      if $s | has("taskTimeout") and (.taskTimeout | type != "number" or . != floor or . < 60 or . > 86400) then "taskTimeout is a whole number of seconds from 60 to 86400" else empty end
    ] | first // empty')
  [ -z "$w" ] || { echo "conveyor: $w" >&2; return 2; }
  SWE_SET=$(jq -c --argjson s "$s" '{dataset, revision, seed, swebench, cpus: .limits.cpus, memory: .limits.memory, taskTimeout} + $s' "$SWE_CONF")
}
swe_set() { jq -r "$1" <<<"$SWE_SET"; } # <jq filter>: of the settings in force (swe_settings)
# The ordered task list's file of a revision and seed.
swe_list() { printf '%s/tasks.%s.%s.jsonl\n' "$SWE_DIR" "$1" "$(printf '%s' "$2" | sha256sum | cut -c1-12)"; } # <revision> <seed>
# The task list of the settings' revision and seed, made once each: the harness's list, put in the seed's order. The
# dataset's rows that an earlier harness kept beside it (raw.<revision>.jsonl, with the reference fixes and hidden
# tests) are removed first. A list whose tasks have no cmd (the test command run in the task's container) is made again.
swe_tasks() {
  local rev f err; rev=$(swe_set .revision); f=$(swe_list "$rev" "$(swe_set .seed)")
  rm -f "$SWE_DIR"/raw.*.jsonl
  [ -s "$f" ] && head -n 1 "$f" | jq -e 'has("cmd")' > /dev/null 2>&1 && { printf '%s\n' "$f"; return; }
  # The harness's own conveyor: line (a swebench of the wrong version says which it has and which to install) is the
  # error; else its whole output (a failed download's traceback) goes on, and the error names its last line.
  mkdir -p "$SWE_DIR" && err=$(swe_h tasks "$(swe_set .dataset)" "$rev" "$SWE_DIR/raw.$rev" 2>&1 >&2) \
    || { local why; why=$(grep '^conveyor: ' <<<"$err" | tail -n 1)
      [ -n "$why" ] || { [ -z "$err" ] || printf '%s\n' "$err" >&2
        why="conveyor: the SWE-bench task list could not be read: $(grep -v '^[[:space:]]*$' <<<"$err" | tail -n 1) (the harness runs in $SWE_VENV: docs/benchmarks.md)"; }
      echo "$why" >&2; return 1; }
  python3 -I -c 'import hashlib, json, sys
seed = sys.argv[1]
rows = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
rows.sort(key=lambda r: hashlib.sha256(("%s:%s" % (seed, r["id"])).encode()).hexdigest())
sys.stdout.write("".join(json.dumps(r) + "\n" for r in rows))' "$(swe_set .seed)" "$SWE_DIR/raw.$rev" > "$f.$$" && [ -s "$f.$$" ] && mv -f "$f.$$" "$f" \
    || { rm -f "$f.$$"; echo "conveyor: the SWE-bench task list could not be put in order" >&2; return 1; }
  printf '%s\n' "$f"
}
swe_src() { printf '%s' "${CONVEYOR_BENCH_SOURCE:-$(git -C "$HERE" remote get-url origin 2>/dev/null)}"; }
# The released versions and main, as JSON [{name, commit}], newest release first.
swe_versions() {
  local src l; src=$(swe_src) && [ -n "$src" ] && l=$(git ls-remote "$src" refs/heads/main 'refs/tags/v*' 2>/dev/null) \
    || { echo "conveyor: the engine's versions could not be read from ${src:-its repository}" >&2; return 1; }
  awk '{ n = $2; sub(/^refs\/(tags|heads)\//, "", n); p = sub(/\^\{\}$/, "", n); print n "\t" $1 "\t" p }' <<<"$l" \
    | jq -Rsc 'split("\n") | map(select(. != "") | split("\t") | {name: .[0], commit: .[1], peeled: (.[2] == "1")})
      | map(select(.name == "main" or (.name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")))) | group_by(.name) | map(sort_by(.peeled) | last | del(.peeled))
      | (map(select(.name == "main")) + (map(select(.name != "main")) | sort_by(.name | ltrimstr("v") | split(".") | map(tonumber)) | reverse))'
}
# <main | v<x.y.z> | full commit id>: sets SWE_COMMIT and SWE_VERSION (the release's name, else "main" for main's
# commit, else "").
swe_resolve() {
  local vs; vs=$(swe_versions) || return 1; SWE_VERSIONS=$vs
  if [[ $1 =~ ^[0-9a-f]{40}$ ]]; then SWE_COMMIT=$1
    SWE_VERSION=$(jq -r --arg c "$1" 'map(select(.commit == $c)) | (map(select(.name != "main")) + .) | first.name // ""' <<<"$vs")
  else
    SWE_COMMIT=$(jq -r --arg n "$1" 'map(select(.name == $n)) | first.commit // ""' <<<"$vs"); SWE_VERSION=$1
    [ -n "$SWE_COMMIT" ] || { echo "conveyor: $1 is no released version, nor main, nor a full commit id" >&2; return 1; }
    [ "$1" != main ] || SWE_VERSION=$(jq -r --arg c "$SWE_COMMIT" 'map(select(.commit == $c and .name != "main")) | first.name // "main"' <<<"$vs")
  fi
}
# Whether the project's usage guard is reached now (the loop's own test: state(), lib/control.sh), whatever the
# project's mode: a paused or stopped project's guard still stands for a run of its own. The guard of an arm that is
# not the engine's reads the one Claude account copied into its container (swe_login), the builder's, whatever agent
# and route the seats have: guardread reads none for a Codex or OpenCode builder or one on an API route.
swe_guarded() { # [an arm that is not the engine's: any non-empty word]
  local pct; ctlread 2>/dev/null || return 1
  if [ -n "${1:-}" ]; then pct=$(ACCT=$(ctlacct "$CTL_V") reading | jq -r '.pct // empty'); else pct=$(guardread "$CTL_V" ask | jq -r '.pct // empty'); fi
  [ "$(state "$(jq -c '.mode = "run"' <<<"$CTL_V")" "$pct")" = "paused by guard" ]
}
# How many tasks a difference must reach to be told from run-to-run noise with n tasks: two standard errors of the
# difference of two resolved counts at a rate of one half, ceil(sqrt(2n)), and never more than n (with so few tasks
# that this passes n, only a total break, a difference of n, shows). noised() is that number, for swe_diff's verdict too.
SWE_NOISED='def noised($n): [(2 * $n | sqrt | ceil), $n] | min;'
swe_noise() { jq -rn --argjson n "$1" "$SWE_NOISED"'noised($n) as $d | if $d >= $n then "with \($n) task\(if $n > 1 then "s" else "" end) only a total break shows: a difference under \($n) is within the noise"
  else "with \($n) tasks a difference under \($d) tasks is within the noise" end'; }
# The sessions a task takes, usual (the mean of the arm's results so far, else build and review for a conveyor arm,
# or the arm's own sessions) and worst case (a conveyor arm's: the build, MAX_REVIEWS reviews, the fix rounds between
# them, the one fix of a failed test step and the review after it and, while the control record has the judge on, a
# judge session for each review; another arm's own sessions), its minutes (swe.json's for its kind at first) and
# session, the dollars one session costs at list prices: a benchmark session keeps no usage to price, so it is the mean
# of this project's own priced card sessions (the snapshot's $STATE.priced, dashboard_limit.py cardlines' summary: a
# header line, then a line a card, the card priced in its second tab-separated field; each step with dollars above 0;
# a test run costs none), those priced at the arm's model when it is given one; null when there is none to take the mean of.
swe_pertask() { # <arm> <conveyor | agent> <the arm's sessions> [<the arm's model>]
  local w=$((2 * MAX_REVIEWS + 2)); ! judgeon > /dev/null || w=$((3 * MAX_REVIEWS + 3))
  [ "$2" = conveyor ] || w=$3
  cat "$SWE_DIR"/results/*/*.json 2>/dev/null | jq -sc --arg a "$1" --argjson w "$w" --argjson u "$(if [ "$2" = conveyor ]; then echo 2; else echo "$3"; fi)" --argjson m "$(swe_conf ".minutes.$2")" \
    --slurpfile pr <(awk -F '\t' 'NR > 1 { print $2 }' "$STATE.priced" 2>/dev/null | jq -Rc 'fromjson? | .steps[]?| select((.usd | type) == "number" and .usd > 0) | {usd, pricedAs}' 2>/dev/null) --arg pm "${4:-}" \
    'map(select(.arm == $a)) as $r | {usual: (if $r == [] then $u else ($r | map(.sessions) | add / length * 10 | round / 10) end),
      worst: $w, minutes: (if $r == [] then $m else ($r | map(.minutes) | add / length | ceil) end),
      session: ($pr | map(select($pm == "" or .pricedAs == $pm) | .usd) | if . == [] then null else add / length * 10000 | round / 10000 end)}'
}
# The model a solo run takes (the builder seat's, when it is Claude) and its arm key (swe_armkey: its results key adds
# the fingerprint of its inputs, swe_reskey).
swe_solomodel() { seat builder 2>/dev/null | jq -r 'select(.agent == "claude") | .model // empty'; }
swe_solokey() { local k=solo-${1:-default}; printf '%s\n' "${k//[^A-Za-z0-9._-]/-}"; } # <model>
# board.json, what the snapshot carries: the run in progress, the solo arm's key now (soloKey), the versions
# (the last read, SWE_VERSIONS) and the expected figures. The runs and the results are not in it (the snapshot's size):
# the Board reads them when it shows them (swe_history, swe_show).
swe_board() {
  local vs; vs=$(jq -c '.versions // null' "$SWE_DIR/board.json" 2>/dev/null) || vs=null
  [ -z "${SWE_VERSIONS:-}" ] || vs=$SWE_VERSIONS
  mkdir -p "$SWE_DIR" || return 1
  swe_put "$SWE_DIR/board.json" "$(jq -nc --slurpfile live <(jq -c . "$SWE_DIR/live.json" 2>/dev/null || echo null) \
    --argjson vs "$vs" --argjson c "$(swe_pertask conveyor conveyor 2)" --argjson s "$(swe_pertask solo agent 1)" --arg sk "$(swe_solokey "$(swe_solomodel)")" \
    --argjson presets "$(swe_conf .presets)" --argjson max "$(swe_conf .tasks)" \
    '{live: $live[0], versions: $vs, presets: $presets, max: $max, perTask: {conveyor: $c, solo: $s}, soloKey: $sk}')"
}
# A run's line as the Board reads it ($R: each result by "<key>/<task>"): its line without its tasks and pid, n the
# tasks of each arm, and cols, each arm with the tasks it did (done), resolved and not run, and the sessions, tokens
# and minutes of its results of the tasks it ran (null when the line names no results key: a line written before
# cols). A run whose process is gone with no end written shows stopped, as the snapshot shows it.
SWE_RUNSUM='def runsum($R): . as $l | ((.arms // [.arm]) | length) as $na
  | (if .state == "running" and (.pid | type) == "number" and (.alive | not) then {state: "stopped", current: null} else {} end) as $gone
  | del(.tasks, .pid, .alive) + $gone + {n: (((.n // 0) / ([$na, 1] | max)) | floor), cols: [(.cols // ((.arms // [.arm]) | map({arm: ., key: null, label: .})))[] | . as $c
    | [$l.tasks[]? | select(.arm == $c.arm)] as $t | [$t[] | select(.result | tostring | startswith("not run") | not)] as $ran
    | [$ran[] | $R["\($c.key)/\(.id)"] // empty] as $r | def sum(f): if $c.key == null then null else $r | map(f // 0) | add // 0 end;
    $c + {done: ($t | length), resolved: ($t | map(select(.result == "resolved")) | length), notRun: (($t | length) - ($ran | length)),
      sessions: sum(.sessions), tokens: sum(.tokens), minutes: (sum(.minutes) | if . == null then null else . * 10 | round / 10 end)}]};'
# Every run's line (runs.jsonl, then the run in progress), one JSON a line, alive true on a running line whose process is there.
swe_lines() {
  local p; p=$(jq -r 'select(.state == "running") | .pid // empty' "$SWE_DIR/live.json" 2>/dev/null)
  # Neither file is there before the first run: that is no runs, not a failure (the Board's Start reads history then).
  { cat "$SWE_DIR/runs.jsonl" 2>/dev/null; jq -c 'select(.state == "running")' "$SWE_DIR/live.json" 2>/dev/null; :; } \
    | jq -Rc --argjson a "$([ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo true || echo false)" 'fromjson? | objects | select(.id | strings) | if .state == "running" then .alive = $a else . end'
}
# `bench swe history`: what the Board's Benchmarks tab reads when it is shown, as one JSON object: runs, every run
# newest first (runsum); arms, every arm with its state (ready, failed, unchecked, changed since its check, not
# offered), why, its last check (at), the guard that holds it back (swe_guards), its results key on swe.json's
# settings (swe_reskey; null for a conveyor arm, whose key ends with its engine's commit: keyPrefix and the commit)
# and its sessions, minutes and a session's dollars (swe_pertask); keys, each results key with the places of its tasks
# in the pinned order (a run reuses them); guard, whether the usage guard
# holds back a run with a conveyor arm (conveyor) or another arm on the Claude login (agent); set, the task set;
# choices, the models and efforts a saved arm may choose (swe_choices; null when the pack does not read).
swe_history() {
  local arms='[]' n a r p m k i gc=false ga=false ch
  for n in $(swe_armnames); do
    a=$(swe_arm "$n") || continue
    r=$(cat "$SWE_DIR/preflight/$n"/*.json 2>/dev/null | jq -sc 'sort_by(.epoch) | last // null')
    p=null; k=null
    if jq -e '.offered != false' <<<"$a" > /dev/null; then
      m=''; [ "$(jq -r .kind <<<"$a")" = conveyor ] || { m=$(jq -r '.model // ""' <<<"$a"); [ "$m" != builder ] || m=$(swe_solomodel); }
      i=$(swe_inputs "$a" "$m") && k=$(swe_reskey "$a" '' "$m" "$i" | jq -R .) || k=null
      p=$(swe_pertask "$n" "$(jq -r .kind <<<"$a")" "$(jq -r '.sessions // 1' <<<"$a")" "$m")
    fi
    arms=$(jq -c --argjson a "$a" --argjson r "$r" --argjson p "$p" --argjson k "$k" --arg g "$(swe_guards "$a")" '. + [{name: $a.name, label: ($a.label // $a.name), kind: $a.kind,
      state: (if $a.offered == false then "not offered" elif $r == null then "unchecked" elif $r.spec != $a then "changed" elif $r.ok then "ready" else "failed" end),
      why: (if $a.offered == false then ($a.why // null) else ($r.why // null) end), at: ($r.at // null), guard: (if $g == "" then null else $g end), perTask: $p,
      key: (if $a.kind == "conveyor" then null else $k end), keyPrefix: (if $a.kind == "conveyor" then $k else null end)}]' <<<"$arms")
  done
  ! swe_guarded || gc=true; ! swe_guarded 1 || ga=true
  ch=$(swe_choices) || ch=null
  swe_lines | jq -sc --argjson arms "$arms" --argjson gc "$gc" --argjson ga "$ga" --argjson ch "$ch" --slurpfile res <(cat "$SWE_DIR"/results/*/*.json 2>/dev/null) \
    --slurpfile order <(jq -c .id "$(swe_list "$(swe_set .revision)" "$(swe_set .seed)")" 2>/dev/null) --argjson set "$SWE_SET" "$SWE_RUNSUM"'
    ($res | map({key: "\(.key)/\(.task)", value: .}) | from_entries) as $R | ($order | to_entries | map({key: .value, value: .key}) | from_entries) as $pos
    | {set: ($set | {dataset, revision, seed}), guard: {conveyor: $gc, agent: $ga}, arms: $arms, choices: $ch,
       runs: (sort_by(.started // "") | reverse | map(runsum($R))),
       keys: ($res | group_by(.key) | map({key: .[0].key, at: (map($pos[.task] // empty) | sort)}))}'
}
# `bench swe show <run>`: one run as the Board's run page shows it: run, its line (runsum), and tasks, each task the
# run took in its order, with its title (the issue's first line) and, for each arm (cells, in cols order), what the run
# said of it (result, reused) and, where it ran that arm on the task, its kept result: resolved, fired, why, sessions, tokens, minutes, its steps (a conveyor
# arm's card records) and its patch (each file with its lines added and removed; null when none is kept).
swe_show() { # <run id>
  local l k t ks=() ts=() f o
  [[ $1 =~ ^r[0-9]{8}T[0-9]{6}-[0-9]+$ ]] && l=$(swe_lines | jq -c --arg id "$1" 'select(.id == $id)' | tail -n 1) && [ -n "$l" ] \
    || { echo "conveyor: no SWE-bench run $1" >&2; return 1; }
  mapfile -t ks < <(jq -r '.cols[]?.key // empty' <<<"$l" | grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*$')
  mapfile -t ts < <(jq -r '.tasks[]?.id' <<<"$l" | awk '!s[$0]++' | grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*$')
  o=$(mktemp) || return 1
  for k in "${ks[@]}"; do for t in "${ts[@]}"; do
    f=$SWE_DIR/results/$k/$t; [ -s "$f.json" ] || continue
    jq -c --argjson p "$(if [ -e "$f.patch" ]; then git apply --numstat "$f.patch" 2>/dev/null | jq -Rsc '[split("\n")[] | select(. != "") | split("\t")
      | {path: .[2], added: (.[0] | tonumber? // null), removed: (.[1] | tonumber? // null)}]'; else echo null; fi)" '. + {patch: $p}' "$f.json"
  done; done > "$o"
  # The run's line goes in on stdin, not as an argument: a run of 500 tasks and 6 arms is past the system's limit
  # on one argument. A cell has a kept result only where this run ran that arm on the task: the result kept under
  # its key may be another run's (a run resumed after this one stopped), never this run's to show. The titles are
  # read from the run's task list (a line with no set or seed took swe.json's).
  jq -c --slurpfile res "$o" --slurpfile tl <(jq -c '{id, title: (.issue // "" | split("\n") | map(select(test("\\S"))) | first // "" | .[0:160])}' \
    "$(swe_list "$(jq -r --arg d "$(swe_conf .revision)" '(.set.revision | strings | select(test("^[0-9a-f]{40}$"))) // $d' <<<"$l")" "$(jq -r --arg d "$(swe_conf .seed)" '(.set.seed | strings) // $d' <<<"$l")")" 2>/dev/null) "$SWE_RUNSUM"'. as $l
    | ($res | map({key: "\(.key)/\(.task)", value: .}) | from_entries) as $R | ($tl | map({key: .id, value: .title}) | from_entries) as $T | ($l | runsum($R)) as $run
    | ($l.tasks | map({key: "\(.arm)/\(.id)", value: .}) | from_entries) as $E
    | {run: $run, tasks: [$l.tasks | map(.id) | reduce .[] as $i ({s: {}, l: []}; if .s[$i] then . else .s[$i] = true | .l += [$i] end) | .l[] as $id
      | {id: $id, title: ($T[$id] // null), cells: [$run.cols[] | . as $c | $E["\($c.arm)/\($id)"] as $t
        | {arm: $c.arm, result: ($t.result // null), reused: ($t.reused // false)}
          + ((if $t == null or ($t.result | tostring | startswith("not run")) then {} else $R["\($c.key)/\($id)"] // {} end) | {resolved, fired, why, sessions, tokens, minutes, steps, patch})]}]}' <<<"$l"
  local rc=$?; rm -f "$o"; return $rc
}
swe_live() { local l; l=$(jq -c "$@" "$SWE_DIR/live.json") && swe_put "$SWE_DIR/live.json" "$l" && swe_board; } # [jq options] <jq filter>
# The sandbox of one task: <sb>/origin, a bare repository holding the base commit as main, <sb>/swe-<project>, its clone, and
# <sb>/bin/gh, the sandbox's gh (swe_gh) serving the task's issue, on PATH in every arm's container.
swe_sandbox() { # <task json> <sb>
  local url base; url=$(jq -r .url <<<"$1"); base=$(jq -r .base <<<"$1")
  { [ ! -e "$2" ] || { chmod -R u+w "$2" && rm -rf "$2"; }; } && mkdir -p "$2/bin" && git init -q --bare -b main "$2/origin" \
    && git -C "$2/origin" fetch -q --depth 1 "$url" "$base" && git -C "$2/origin" update-ref refs/heads/main "$base" \
    && git clone -q "file://$2/origin" "$2/$SWE_MAIN" && printf '.conveyor/\nconveyor/\n' >> "$2/$SWE_MAIN/.git/info/exclude" \
    && printf '%s\n' "$base" > "$2/base" \
    && jq -c '{number: 1, title: "SWE-bench \(.id)", body: .issue, labels: [], milestone: null, createdAt: "2026-01-01T00:00:00Z", state: "OPEN"}' <<<"$1" > "$2/issue.json" \
    && swe_gh "$2"
}
# The sandbox's gh: issue #1 is the task's issue, open until the card closes it or a push moves the origin's main past
# the base commit (GitHub closes an issue on a push whose commit says it closes it); a comment, label, follow-up or
# any other write is kept in <sb>/gh.log and never sent.
swe_gh() { # <sb>
  cat > "$1/bin/gh" <<EOF
#!/usr/bin/env bash
S=$(printf %q "$1")
EOF
  cat >> "$1/bin/gh" <<'EOF'
printf '%s\n' "$*" >> "$S/gh.log"
open() { [ ! -e "$S/closed" ] && [ "$(git -C "$S/origin" rev-parse -q --verify refs/heads/main)" = "$(cat "$S/base")" ]; }
case $1:${2:-} in
  issue:list) case "$*" in *' closed'*) if open; then echo '[]'; else jq -c '[.]' "$S/issue.json"; fi ;; *) if open; then jq -c '[.]' "$S/issue.json"; else echo '[]'; fi ;; esac ;;
  issue:view) [ "$3" = 1 ] || { echo "no issue $3 here" >&2; exit 1; }
    case "$*" in *'--json closed'*) if open; then echo '{"closed":false}'; else echo '{"closed":true}'; fi ;;
      *'--json state'*) if open; then echo '{"state":"OPEN","closedAt":""}'; else echo '{"state":"CLOSED","closedAt":""}'; fi ;;
      *) jq -c . "$S/issue.json" ;; esac ;;
  issue:close) [ "$3" != 1 ] || : > "$S/closed" ;;
  issue:create) echo "https://github.invalid/sandbox/issues/$((1000 + $(wc -l < "$S/gh.log")))" ;;
  auth:status) ;;
  *) ;;
esac
EOF
  chmod +x "$1/bin/gh"
}
# The engine a conveyor arm runs: SWE_COMMIT and SWE_VERSION (swe_resolve) of <version>, installed, and SWE_ENG,
# its conveyor.sh.
swe_engine() { # <version | commit>
  swe_resolve "$1" || return 1
  { installed "$SWE_COMMIT" || install "$SWE_COMMIT" "$(swe_src)" > /dev/null; } || { echo "conveyor: engine $1 ($SWE_COMMIT) could not be installed" >&2; return 1; }
  SWE_ENG=$VERSIONS/$SWE_COMMIT/conveyor/conveyor.sh
}
# An arm as a run takes it, in SWE_CTX: {arm, spec (its JSON), kind, key (its results', swe_reskey), check (its
# preflight's, swe_armkey), inputs (swe_inputs), frozen, engine, version, model, eng, label}. A conveyor arm takes the
# engine <version>; an arm on the builder's model takes the builder seat's. The inputs are taken once, here: a conveyor
# arm's project files are copied to frozen/<arm> (swe_freeze), and every task of the run builds on that copy.
swe_context() { # <arm> <version | commit>
  local a i m='' SWE_FZ=''; a=$(swe_arm "$1") || { echo "conveyor: no arm $1: \`conveyor.sh bench swe arms\` lists them" >&2; return 1; }
  ! jq -e '.offered == false' <<<"$a" > /dev/null || { echo "conveyor: the arm $1 is not offered: $(jq -r '.why // "no reason given"' <<<"$a")" >&2; return 1; }
  SWE_COMMIT=''; SWE_VERSION=''; SWE_ENG=''
  if [ "$(jq -r .kind <<<"$a")" = conveyor ]; then swe_engine "$2" || return 1
    SWE_FZ=$SWE_DIR/frozen/${1//[^A-Za-z0-9._-]/-}
    swe_freeze "$a" "$SWE_FZ" || { echo "conveyor: the project's control record, pack or rules could not be copied for the arm $1" >&2; return 1; }
  else m=$(jq -r '.model // ""' <<<"$a"); [ "$m" != builder ] || m=$(swe_solomodel); fi
  i=$(swe_inputs "$a" "$m") || { echo "conveyor: the inputs of the arm $1 could not be read" >&2; return 1; }
  SWE_CTX=$(jq -nc --argjson a "$a" --arg k "$(swe_reskey "$a" "$SWE_COMMIT" "$m" "$i")" --arg ck "$(swe_armkey "$a" "$SWE_COMMIT" "$m")" --argjson i "$i" \
    --arg e "$SWE_COMMIT" --arg v "$SWE_VERSION" --arg m "$m" --arg g "$SWE_ENG" --arg fz "$SWE_FZ" \
    '{arm: $a.name, spec: $a, kind: $a.kind, key: $k, check: $ck, inputs: $i, frozen: (if $fz == "" then null else $fz end), engine: (if $e == "" then null else $e end),
      version: (if $v == "" then null else $v end), model: (if $m == "" then null else $m end), eng: $g, label: ($a.label // $a.name)}')
}
# The arm in use: the globals the trial, its result and its preflight read, from an arm's run context.
swe_use() { # <run context>
  local x; mapfile -t x < <(jq -r '.arm, .key, (.engine // ""), (.version // ""), (.model // ""), .eng, .label, .kind, (.spec.sessions // 1), .check, (.frozen // "")' <<<"$1")
  SWE_ARM=${x[0]} SWE_KEY=${x[1]} SWE_COMMIT=${x[2]} SWE_VERSION=${x[3]} SWE_MODEL=${x[4]} SWE_ENG=${x[5]} SWE_LABEL=${x[6]} SWE_KIND=${x[7]} SWE_SESSIONS=${x[8]} SWE_CHECK=${x[9]} SWE_FZ=${x[10]}
  SWE_ARMJ=$(jq -c .spec <<<"$1"); SWE_INPUTS=$(jq -c .inputs <<<"$1")
}
# Whether the kept result of the arm in use on a task can be reused: it is there, and its recorded inputs are the
# arm's now (a result kept before inputs were recorded has none, and is run again).
swe_reused() { jq -e --argjson i "$SWE_INPUTS" '.inputs == $i' "$SWE_DIR/results/$SWE_KEY/$1.json" > /dev/null 2>&1; } # <task id>
# What a run's lines (runname) and the results (resname) call an arm, from a run context or a result. A result of
# an arm on the builder's model names its model, as each model's results are kept under a key of their own (its
# recorded arm takes the builder's model; a result kept with no inputs: its key is not its name); an arm of a fixed
# model has the model in its label already.
SWE_NAMES='def runname: if .arm == "solo" then "Claude alone" elif .arm == "conveyor" then "engine \(.version // .engine[0:12]) (\(.engine))"
    else "\(.label // .arm)\(if .engine then " on engine \(.version // .engine[0:12]) (\(.engine))" else "" end)" end;
  def resname: if .arm == "solo" then "Claude alone (\(.model // "default"))" elif .arm == "conveyor" then "\(.version // "commit") \(.engine[0:12])"
    else "\(.label // .arm)\(if .model and (if .inputs then .inputs.arm.model == "builder" else .key != .arm end) then " (\(.model))" else "" end)\(if .engine then " \(.version // "commit") \(.engine[0:12])" else "" end)" end;'
# One task with the arm in use (swe_use): fetched image, sandbox, trial, grade. Writes results/<key>/<task>.json and
# .patch and prints "resolved", "unresolved", "unresolved (<why it did not fire>)", or "not run: <why>". A trial that
# did not fire is the arm's failed task: kept, never graded, never run again. The result keeps the run's inputs
# (swe_inputs): a conveyor arm's sandbox reads the run's copy of the project's files (swe_freeze).
swe_task() { # <task json>
  local id sb b g rc out=$SWE_DIR/results/$SWE_KEY; id=$(jq -r .id <<<"$1"); sb=$SWE_DIR/work/$id
  swe_h image "$(jq -r .image <<<"$1")" > /dev/null 2>&1 || { echo "not run: its Docker image could not be fetched or built"; return; }
  mkdir -p "$SWE_DIR/work" && swe_sandbox "$1" "$sb" 2> "$SWE_DIR/work/$id.err" \
    || { echo "not run: its repository could not be fetched at the base commit: $(head -c 300 "$SWE_DIR/work/$id.err")"; return; }
  b=$(swe_trial "$1" "$sb" "$SWE_ARMJ" "$SWE_ENG") && [ -n "$b" ] && jq -e . <<<"$b" > /dev/null 2>&1 || { echo "not run: ${b:-the patch of the sandbox could not be read}"; return; }
  if ! jq -e .fired <<<"$b" > /dev/null || [ ! -s "$sb.h/patch" ]; then g='{"resolved":false}'
  else g=$(swe_h grade "$(swe_set .dataset)" "$(swe_set .revision)" "$id" "$sb.h/patch" "$sb.h/grade" 2>/dev/null); rc=$?
    [ "$rc" = 0 ] && jq -e '.resolved | type == "boolean"' <<<"$g" > /dev/null 2>&1 || {
      if [ "$rc" = 3 ]; then echo "not run: the harness could not fetch or build its image"; else echo "not run: the harness could not grade it (exit $rc)"; fi; return; }
  fi
  mkdir -p "$out" && cp "$sb.h/patch" "$out/$id.patch" && { [ ! -e "$sb.h/loop.log" ] || cp "$sb.h/loop.log" "$out/$id.log"; } && swe_put "$out/$id.json" "$(jq -c --arg t "$id" --arg a "$SWE_ARM" --arg k "$SWE_KEY" --arg e "${SWE_COMMIT:-}" --arg v "${SWE_VERSION:-}" \
    --arg m "${SWE_MODEL:-}" --arg l "$SWE_LABEL" --argjson g "$g" --arg at "$(swe_now)" --argjson i "$SWE_INPUTS" '{task: $t, arm: $a, label: $l, key: $k, engine: (if $e == "" then null else $e end), version: (if $v == "" then null else $v end),
    model: (if $m == "" then null else $m end), resolved: $g.resolved, at: $at, inputs: $i} + .' <<<"$b")" || { echo "not run: its result could not be kept"; return; }
  chmod -R u+w "$sb" "$sb.h" 2>/dev/null; rm -rf "$sb" "$sb.h"
  if jq -e .resolved <<<"$g" > /dev/null; then echo resolved; elif jq -e .fired <<<"$b" > /dev/null; then echo unresolved; else echo "unresolved ($(jq -r .why <<<"$b"))"; fi
}
# The run's end: its line in runs.jsonl, live.json's state, the containers of its trials and preflights, the
# sandboxes and the run's copies of the project's files (swe_freeze) gone.
swe_end() { # <state>
  [ -n "${SWE_RUN:-}" ] || return 0
  local l f; l=$(jq -c --arg s "$1" --arg at "$(swe_now)" '.state = $s | .ended = $at | .current = null | del(.pid)' "$SWE_DIR/live.json") && swe_put "$SWE_DIR/live.json" "$l" \
    && printf '%s\n' "$l" >> "$SWE_DIR/runs.jsonl"
  for f in "$SWE_DIR"/work/*/box "$SWE_DIR"/check/*/box; do [ ! -s "$f" ] || docker rm -f "$(cat "$f")" > /dev/null 2>&1; done
  [ ! -d "$SWE_DIR/work" ] || { chmod -R u+w "$SWE_DIR/work"; rm -rf "$SWE_DIR/work"; }
  rm -rf "$SWE_DIR/frozen"; rm -f "$SWE_DIR/stop"; swe_board; SWE_RUN=
}
# Whether the usage guard holds back a run of these kinds of arm: <conveyor> is non-empty when the run has a conveyor
# arm, <agent> when it has another arm that uses the Claude login (swe_guards).
swe_held() { { [ -n "$1" ] && swe_guarded; } || { [ -n "$2" ] && swe_guarded 1; }; } # <conveyor> <agent>
# Which guard an arm is held back by: "conveyor" (the engine's), "agent" (the Claude account an arm that is not the
# engine's uses) or nothing, for an arm with no Claude login (Codex alone): the Claude guard does not hold it.
swe_guards() { jq -r 'if .kind == "conveyor" then "conveyor" elif (.login // [] | index("claude")) then "agent" else empty end' <<<"$1"; } # <arm json>
# A run: the first n tasks, each built by every arm in turn, so a run stopped early has compared the arms on the same
# tasks. Each arm is picked only once its preflight passed (swe_ready) and, for a conveyor arm, the area rule files
# its cards of these tasks read are there (swe_taskrules).
swe_run() { # <n> <engine> <arm>...
  local n=$1 eng0=$2 tf all i t id r x a l gc='' ga='' why ctxs=() specs=() plan='[]' ra tag
  shift 2
  mkdir -p "$SWE_DIR" && exec 7>>"$SWE_DIR/run.lock" && flock -n 7 || { echo "conveyor: a SWE-bench run is already going; \`conveyor.sh bench swe stop\` ends it" >&2; return 1; }
  for x; do a=$(swe_arm "$x") || { echo "conveyor: no arm $x: \`conveyor.sh bench swe arms\` lists them" >&2; return 2; }
    specs+=("$a"); case $(swe_guards "$a") in conveyor) gc=1 ;; agent) ga=1 ;; esac; done
  ! swe_held "$gc" "$ga" || { echo "conveyor: the usage guard is reached: no SWE-bench run starts while it stands" >&2; return 1; }
  # A build machine that cannot run a task refuses the run, kept as its recorded end (state refused, with why) as a
  # failed preflight is, so the run history still says what to repair once the Board no longer waits for the answer.
  # Its conveyor arms name the engine asked for. Written here, not by swe_end: no container or sandbox is this run's,
  # and the ones swe_end removes can be an arms check's.
  why=$(swe_setup 2>&1) || { echo "$why" >&2
    l=$(printf '%s\n' "${specs[@]}" | jq -sc --arg id "r$(date -u +%Y%m%dT%H%M%S)-$$" --argjson n "$n" --arg at "$(swe_now)" --arg w "${why#conveyor: }" \
      --arg e "$eng0" --argjson set "$SWE_SET" '($e | test("^[0-9a-f]{40}$")) as $c
      | {id: $id, arm: .[0].name, arms: map(.name), label: (map(.label // .name) | join(", ")), n: ($n * length),
         cols: map({arm: .name, key: null, label: (.label // .name), kind}
           + (if .kind == "conveyor" then {engine: (if $c then $e else null end), version: (if $c then null else $e end)} else {} end)),
         set: ($set | {dataset, revision, seed}), limits: ($set | {cpus, memory, taskTimeout}), done: 0, resolved: 0, current: null, started: $at, ended: $at, state: "refused", tasks: [], why: $w}') \
      && swe_put "$SWE_DIR/live.json" "$l" && printf '%s\n' "$l" >> "$SWE_DIR/runs.jsonl"; swe_board; return 1; }
  tf=$(swe_tasks) || return 1; all=$(wc -l < "$tf")
  [ "$n" -le "$all" ] || { echo "conveyor: the task list holds $all tasks: n is 1 to $all" >&2; return 2; }
  rm -rf "$SWE_DIR/frozen"; for x; do swe_context "$x" "$eng0" || return 1; ctxs+=("$SWE_CTX"); done
  # The run is live from its preflights on, which can take minutes: Stop ends it there too, and a failed preflight is
  # the run's recorded end (state refused, with why), which the Board shows once it no longer waits for the answer.
  # cols names each arm's results key (the Board's history and run page read each arm's results by it), set the
  # task set (dataset, revision and seed: runs of one set are read side by side) and limits each trial's (swe_settings).
  SWE_RUN=r$(date -u +%Y%m%dT%H%M%S)-$$; rm -f "$SWE_DIR/stop"
  swe_put "$SWE_DIR/live.json" "$(printf '%s\n' "${ctxs[@]}" | jq -sc --arg id "$SWE_RUN" --argjson pid "$$" --argjson n "$n" --arg at "$(swe_now)" \
    --argjson set "$SWE_SET" "$SWE_NAMES"'. as $c | $c[0]
    | {id: $id, pid: $pid, arm, key, engine, version, model, arms: ($c | map(.arm)), label: ($c | map(runname) | join(", ")), n: ($n * ($c | length)),
       cols: ($c | map({arm, key, label, kind, engine, version, model})), set: ($set | {dataset, revision, seed}), limits: ($set | {cpus, memory, taskTimeout}),
       done: 0, resolved: 0, current: null, started: $at, state: "running", tasks: []}')"
  swe_board
  trap 'pkill -TERM -P $$ 2>/dev/null; swe_end stopped; exit 143' TERM INT
  for x in "${ctxs[@]}"; do
    swe_use "$x"
    why=''; [ "$SWE_KIND" != conveyor ] || why=$(head -n "$n" "$tf" | swe_taskrules "$SWE_ARMJ")
    [ -n "$why" ] || why=$(swe_ready "$SWE_ARMJ" "$SWE_CHECK" "$(head -n 1 "$tf" | jq -r .image)" "$SWE_ENG")
    [ -z "$why" ] || { why="the arm $SWE_ARM cannot run: its preflight failed: $why. \`conveyor.sh bench swe arms check $SWE_ARM\` runs it again."
      echo "conveyor: $why" >&2; swe_live --arg w "$why" '.why = $w' > /dev/null; trap - TERM INT; swe_end refused; return 1; }
    ra=0; while IFS= read -r id; do ! swe_reused "$id" || ra=$((ra + 1)); done < <(head -n "$n" "$tf" | jq -r .id)
    plan=$(jq -c --argjson c "$x" --argjson r "$ra" --argjson p "$(swe_pertask "$SWE_ARM" "$SWE_KIND" "$SWE_SESSIONS")" '. + [$p + {r: $r, c: $c}]' <<<"$plan")
  done
  jq -r --argjson n "$n" "$SWE_NAMES"'(map(.r) | add) as $r | (map($n - .r) | add) as $k
    | "SWE-bench Verified: \($n) task\(if $n > 1 then "s" else "" end) with \(map(.c | runname) | join(", ")); \($r) already run and reused, \($k) to run."
    , "Expected: about \(map(($n - .r) * .usual) | add | ceil) sessions (worst case \(map(($n - .r) * .worst) | add)) and \(map(($n - .r) * .minutes) | add) minutes."' <<<"$plan"
  for ((i = 1; i <= n; i++)); do
    t=$(sed -n "${i}p" "$tf"); id=$(jq -r .id <<<"$t")
    for x in "${ctxs[@]}"; do
      swe_use "$x"; tag=''; [ ${#ctxs[@]} = 1 ] || tag=" [$SWE_ARM]"
      [ ! -e "$SWE_DIR/stop" ] || { swe_end stopped; return 0; }
      if swe_reused "$id"; then
        r=$(jq -r 'if .resolved then "resolved" else "unresolved" end' "$SWE_DIR/results/$SWE_KEY/$id.json"); echo "$i/$n $id$tag: $r (reused)"
        swe_live --arg t "$id" --arg a "$SWE_ARM" --arg r "$r" '.tasks += [{id: $t, arm: $a, result: $r, reused: true}] | .done += 1 | .resolved += (if $r == "resolved" then 1 else 0 end)'
        continue
      fi
      case $(swe_guards "$SWE_ARMJ") in conveyor) ! swe_held 1 '' ;; agent) ! swe_held '' 1 ;; esac \
        || { echo "conveyor: the usage guard is reached: the run stops before $id"; swe_end guard; return 0; }
      swe_live --arg t "$id" '.current = $t'
      r=$(swe_task "$t"); echo "$i/$n $id$tag: $r"
      swe_live --arg t "$id" --arg a "$SWE_ARM" --arg r "$r" '.tasks += [{id: $t, arm: $a, result: $r, reused: false}] | .done += 1 | .current = null | .resolved += (if $r == "resolved" then 1 else 0 end)'
    done
  done
  jq -r --argjson n "$n" --slurpfile l "$SWE_DIR/live.json" "$SWE_NAMES"'.[].c | . as $c | [$l[0].tasks[] | select(.arm == $c.arm)] as $t
    | "Resolved \($t | map(select(.result == "resolved")) | length) of \($n) with \(runname); not run: \($t | map(select(.result | startswith("not run"))) | length)."' <<<"$plan"
  swe_end 'done'
}
swe_tree() { local k; echo "$1"; for k in $(pgrep -P "$1"); do swe_tree "$k"; done; } # <pid>: it and every process under it
swe_stop() {
  local p; p=$(jq -r 'select(.state == "running") | .pid // empty' "$SWE_DIR/live.json" 2>/dev/null)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || { echo "conveyor: no SWE-bench run is going"; return 0; }
  local ps; mapfile -t ps < <(swe_tree "$p")
  : > "$SWE_DIR/stop"; kill -TERM "${ps[@]}" 2>/dev/null
  local i=0; while kill -0 "$p" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  mapfile -t ps < <(swe_tree "$p"); ! kill -0 "$p" 2>/dev/null || kill -KILL "${ps[@]}" 2>/dev/null
  echo "conveyor: the SWE-bench run is stopped"
}
# Each key's results, side by side: one line each, then the noise line for the tasks every key ran.
swe_results() { # [--json]
  local j; j=$(cat "$SWE_DIR"/results/*/*.json 2>/dev/null | jq -sc 'group_by(.key) | map({key: .[0].key, arm: .[0].arm, label: .[0].label, engine: .[0].engine, version: .[0].version, model: .[0].model, inputs: .[0].inputs,
    n: length, resolved: (map(select(.resolved)) | length), notFired: (map(select(.fired == false)) | length), sessions: (map(.sessions) | add), tokens: (map(.tokens) | add),
    minutes: (map(.minutes) | add * 10 | round / 10), tasks: map({task, resolved, fired, sessions, tokens, minutes})}) | sort_by(.version // "")')
  [ "${1:-}" != --json ] || { printf '%s\n' "$j"; return; }
  [ "$j" != '[]' ] || { echo "No SWE-bench results yet."; return; }
  jq -r "$SWE_NAMES"'.[] | "\(resname): \(.resolved) of \(.n) resolved\(if .notFired > 0 then " (\(.notFired) did not fire)" else "" end), \(.sessions) sessions, \(.tokens) tokens, \(.minutes) minutes"' <<<"$j"
  local c; c=$(jq '[.[].tasks | map(.task)] | if length > 1 then reduce .[1:][] as $s (.[0]; . - (. - $s)) | length else .[0] | length end' <<<"$j")
  [ "$(jq length <<<"$j")" -lt 2 ] || [ "$c" = 0 ] || echo "On the tasks all of them ran ($c): $(swe_noise "$c")."
}
# Where two runs of one task went apart: the first of their steps (build, review, fix, rebase, test, landed, blocked)
# whose step or result differs, as the stage it is (stagemap.sh's names); a blocked step is the stage its reason names.
# Two runs with the same steps (both landed, one patch passing the hidden tests) went apart at build: their code differs.
SWE_STAGE='def stage: if . == "landed" then "land" elif . == "rebase" then "fix" else . end;
  def seq: map(select(.step | IN("build", "review", "fix", "rebase", "test", "landed", "blocked")));
  def apart($a; $b): ($a | seq) as $x | ($b | seq) as $y | [range([$x, $y] | map(length) | max)] | map(select($x[.] == null or $y[.] == null
    or $x[.].step != $y[.].step or $x[.].result != $y[.].result)) | first as $i
    | if $i == null then null else ($x[$i] // $y[$i]) as $s | if $s.step == "blocked" then ($s.reason // "" | capture("^(?<s>build|review|fix|test|land)") .s // "land") else ($s.step | stage) end end;
  def facts: {resolved, sessions, tokens, minutes, findings: [.steps[] | select(.step == "review" and .result != "GO") | .tail // .reason], fixRounds: ([.steps[] | select(.step == "fix")] | length),
    test: ([.steps[] | select(.step == "test") | .result] | last), blocked: ([.steps[] | select(.step == "blocked") | .reason] | last)};'
# One side of a diff: a results key, a version (the conveyor arm's), an arm, or <arm>@<version> for a conveyor arm.
# Sets SIDE_KEY, SIDE_NAME and SIDE_COMMIT (its engine commit, "" for an arm that runs no engine). A results key is
# taken first (the Board's Compare sends its columns' keys; a key kept before inputs were recorded can be an arm's name
# or an engine commit); else the key of the newest result of that arm (with that engine commit, or the builder's model
# now for an arm on it), whatever settings and inputs it ran on.
swe_side() { # <A or B>
  local arm=${1%%@*} ver='' a m=''
  [[ $1 != *@* ]] || ver=${1#*@}
  if [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [ -d "$SWE_DIR/results/$1" ]; then
    # Those results, whatever arm, engine and model.
    a=$(cat "$SWE_DIR/results/$1"/*.json 2>/dev/null | jq -sc 'first // empty') && [ -n "$a" ] || { echo "conveyor: no results under $1" >&2; return 1; }
    SIDE_KEY=$1; SIDE_COMMIT=$(jq -r '.engine // ""' <<<"$a"); SIDE_NAME=$(jq -r "$SWE_NAMES"'resname' <<<"$a"); return
  fi
  if ! a=$(swe_arm "$arm"); then
    # A version alone is the conveyor arm's.
    ver=$1; arm=''; a=$(swe_arm conveyor) || { echo "conveyor: no arm conveyor to read the version $1 with" >&2; return 1; }
  fi
  if [ "$(jq -r .kind <<<"$a")" = conveyor ]; then swe_resolve "${ver:-main}" || return 1
    SIDE_COMMIT=$SWE_COMMIT; SIDE_NAME="${arm:+$arm }${SWE_VERSION:-${SWE_COMMIT:0:12}}"
  else [ -z "$ver" ] || { echo "conveyor: the arm $arm runs no engine version" >&2; return 1; }
    SIDE_COMMIT=''; SIDE_NAME=$arm; m=$(jq -r '.model // ""' <<<"$a"); [ "$m" != builder ] || m=$(swe_solomodel)
  fi
  # A result kept before arms has no arm: it is the conveyor arm's. Its folder is its key.
  SIDE_KEY=$(jq -rn --arg a "$(jq -r .name <<<"$a")" --arg e "$SIDE_COMMIT" --arg m "$m" '[inputs | select((.arm // "conveyor") == $a and (.engine // "") == $e and ($m == "" or .model == $m))
    | {at: (.at // ""), key: (input_filename | split("/") | .[-2])}] | max_by(.at) | .key // empty' "$SWE_DIR"/results/*/*.json 2>/dev/null)
  [ -n "$SIDE_KEY" ] || { echo "conveyor: $1 has no results" >&2; return 1; }
}
# Two sides that both run an engine are told the engine changes to the stage where their runs went apart; for any
# other two, changes is null.
swe_diff() { # <A> <B> [--json]
  local ca cb va vb ka kb d da db ids id fa fb st sm files=() flips='[]' ch why n e=''
  swe_side "$1" || return 1; ca=$SIDE_COMMIT; va=$SIDE_NAME; ka=$SIDE_KEY; swe_side "$2" || return 1; cb=$SIDE_COMMIT; vb=$SIDE_NAME; kb=$SIDE_KEY
  da=$SWE_DIR/results/$ka; db=$SWE_DIR/results/$kb
  ids=$(comm -12 <(cd "$da" 2>/dev/null && ls -- *.json 2>/dev/null | sort) <(cd "$db" 2>/dev/null && ls -- *.json 2>/dev/null | sort) | sed 's/\.json$//')
  [ -n "$ids" ] || { echo "conveyor: $1 and $2 have no task in common to compare" >&2; return 1; }
  if [ -n "$ca" ] && [ -n "$cb" ]; then
    { installed "$cb" || install "$cb" "$(swe_src)" > /dev/null; } && e=$VERSIONS/$cb || { echo "conveyor: engine $2 could not be installed to read its stages" >&2; return 1; }
  fi
  d=$SWE_DIR/diff/$ka-$kb; mkdir -p "$d"
  while IFS= read -r id; do
    fa=$(cat "$da/$id.json"); fb=$(cat "$db/$id.json")
    [ "$(jq -n --argjson a "$fa" --argjson b "$fb" '$a.resolved == $b.resolved')" = false ] || continue
    st=$(jq -rn --argjson a "$fa" --argjson b "$fb" "$SWE_STAGE"' apart($a.steps; $b.steps) // "build"')
    # The files of that stage in B's engine (stagemap.sh); null changes when its map cannot be made, or a side runs no engine.
    ch=null; [ -n "$e" ] && sm=$(bash "$HERE/bench/stagemap.sh" "$e/conveyor" 2>/dev/null) && ch='[]' \
      && mapfile -t files < <(awk -F '\t' -v s="$st" '("," $2 ",") ~ ("," s ",") { print "conveyor/" $1 }' <<<"$sm")
    [ "$ch" = null ] || [ ${#files[@]} = 0 ] || ch=$(git -C "$e" log --format='%h%x09%s' "$ca...$cb" -- "${files[@]}" 2>/dev/null | jq -Rsc 'split("\n") | map(select(. != "") | split("\t") | {commit: .[0], title: .[1]})')
    n=$(jq -nc --arg t "$id" --arg s "$st" --argjson a "$fa" --argjson b "$fb" --argjson ch "$ch" --arg va "$va" --arg vb "$vb" "$SWE_STAGE"'
      {task: $t, apart: $s, a: ($a | facts), b: ($b | facts), changes: $ch, versions: [$va, $vb]}')
    if [ -s "$d/$id.txt" ]; then why=$(cat "$d/$id.txt")
    else
      why=$({ if [ -n "$e" ]; then printf 'Two versions of an engine that builds code changes'; else printf 'Two ways of building code changes (%s and %s)' "$va" "$vb"; fi
        printf ' ran one SWE-bench task; one resolved it and one did not. From these facts only, say in two or three plain sentences why the runs most likely went apart. Do not guess beyond the facts.\n\n'
        printf '%s\n' "$n"; } | timeout 300 claude -p 2>/dev/null) && [ -n "$why" ] && printf '%s\n' "$why" > "$d/$id.txt" || why=''
    fi
    flips=$(jq -c --argjson n "$n" --arg w "$why" '. + [$n + {reading: (if $w == "" then null else $w end)}]' <<<"$flips")
  done <<<"$ids"
  local j; j=$(jq -n --slurpfile fl <(printf '%s\n' "$flips") --arg va "$va" --arg vb "$vb" --arg ca "$ca" --arg cb "$cb" --arg noise "$(swe_noise "$(wc -l <<<"$ids")")" \
    --slurpfile ra <(for id in $ids; do cat "$da/$id.json"; done) --slurpfile rb <(for id in $ids; do cat "$db/$id.json"; done) "$SWE_NOISED"'
    def tot: {resolved: (map(select(.resolved)) | length), sessions: (map(.sessions) | add), tokens: (map(.tokens) | add), minutes: (map(.minutes) | add * 10 | round / 10)};
    def c: if . == "" then null else . end; $fl[0] as $f
    | ($ra | length) as $n | ($ra | tot) as $ta | ($rb | tot) as $tb | noised($n) as $dd
    | {a: {version: $va, commit: ($ca | c), totals: $ta}, b: {version: $vb, commit: ($cb | c), totals: $tb}, tasks: $n,
       same: [$ra[] | .task] - [$f[] | .task], flipped: $f, noise: $noise, withinNoise: ((($ta.resolved - $tb.resolved) | fabs) < $dd)}')
  [ "${3:-}" != --json ] || { printf '%s\n' "$j"; return; }
  jq -r --arg e "$e" '"\(.a.version) against \(.b.version) on the \(.tasks) tasks both ran:",
    "  \(.a.version): \(.a.totals.resolved) resolved, \(.a.totals.sessions) sessions, \(.a.totals.tokens) tokens, \(.a.totals.minutes) minutes",
    "  \(.b.version): \(.b.totals.resolved) resolved, \(.b.totals.sessions) sessions, \(.b.totals.tokens) tokens, \(.b.totals.minutes) minutes",
    "  \(.noise)\(if .withinNoise then "; this difference is within the noise" else "; this difference is past the noise" end).",
    "  The same in both: \(.same | length) task(s)\(if .same == [] then "" else ": \(.same | join(", "))" end). Flipped: \(.flipped | length).",
    (.flipped[] | "", "\(.task): \(if .a.resolved then "resolved by \(.versions[0]) only" else "resolved by \(.versions[1]) only" end); the runs went apart at: \(.apart)",
      "  \(.versions[0]): sessions \(.a.sessions), tokens \(.a.tokens), minutes \(.a.minutes), fix rounds \(.a.fixRounds), test \(.a.test // "none"), blocked \(.a.blocked // "no")\(if .a.findings != [] then ", findings: \(.a.findings | join(" | "))" else "" end)",
      "  \(.versions[1]): sessions \(.b.sessions), tokens \(.b.tokens), minutes \(.b.minutes), fix rounds \(.b.fixRounds), test \(.b.test // "none"), blocked \(.b.blocked // "no")\(if .b.findings != [] then ", findings: \(.b.findings | join(" | "))" else "" end)",
      "  Engine changes to the \(.apart) stage between them: \(if .changes == null and $e == "" then "none to show (they are not two versions of the engine)" elif .changes == null then "unknown (the stage map could not be made)" elif .changes == [] then "none" else (.changes | map("\(.commit) \(.title)") | join("; ")) end)",
      "  The model'"'"'s reading (from the facts above only): \(.reading // "none: the model call failed")")' <<<"$j"
}
swe_main() {
  local n='' eng=main named='' arms=() a k set=''
  swe_settings || return 1
  case ${1:-} in
    stop) [ $# = 1 ] && { swe_stop; return; } ;;
    results) [ $# = 1 ] || [ "$*" = 'results --json' ] && { swe_results "${2:-}"; return; } ;;
    history) [ $# = 1 ] && { swe_history; return; } ;;
    show) [ $# = 2 ] && { swe_show "$2"; return; } ;;
    versions) [ $# = 1 ] && { SWE_VERSIONS=$(swe_versions) && swe_board && printf '%s\n' "$SWE_VERSIONS"; return; } ;;
    diff) { [ $# = 3 ] || { [ $# = 4 ] && [ "$4" = --json ]; }; } && { swe_diff "$2" "$3" "${4:-}"; return; } ;;
    arms) shift; swe_arms "$@"; return ;;
  esac
  [[ ${1:-} =~ ^[1-9][0-9]{0,2}$ ]] && [ "$1" -le "$(swe_conf .tasks)" ] && n=$1 && shift || n=''
  while [ -n "$n" ] && [ $# -gt 0 ]; do case $1 in --solo) arms+=(solo); shift ;; --arm) [ $# -ge 2 ] && arms+=("$2") && shift 2 || n='' ;;
    --engine) [ $# -ge 2 ] && eng=$2 && named=1 && shift 2 || n='' ;;
    --settings) [ $# -ge 2 ] && [ -z "$set" ] && set=$2 && shift 2 || n='' ;; *) n='' ;; esac; done
  [ ${#arms[@]} -gt 0 ] || arms=(conveyor)
  # --engine names the version of the run's conveyor arms: a run with none takes no --engine. An arm named twice runs once.
  if [ -n "$n" ] && [ -n "$named" ]; then
    k=''; for a in "${arms[@]}"; do [ "$(swe_arm "$a" | jq -r .kind)" = agent ] || k=1; done; [ -n "$k" ] || n=''
  fi
  [ -n "$n" ] || { echo "usage: conveyor.sh bench swe <1-$(swe_conf .tasks)> [--arm <arm>]... [--solo] [--engine <version | commit>] [--settings <json>] | bench swe arms [check [--settings <json>] <arm>...] | bench swe arms save <name> <spec json> | bench swe arms show <id> | bench swe stop | bench swe results [--json] | bench swe history | bench swe show <run> | bench swe diff <A> <B> [--json] | bench swe versions" >&2; return 2; }
  swe_settings "$set" || return
  mapfile -t arms < <(printf '%s\n' "${arms[@]}" | awk '!seen[$0]++')
  swe_run "$n" "$eng" "${arms[@]}"
}
. "${BASH_SOURCE[0]%/*}/swe_arms.sh"
