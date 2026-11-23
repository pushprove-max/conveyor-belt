# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh bench swe`: SWE-bench Verified tasks built by one or more arms and graded by the official harness.
# Sourced by commands/bench.sh after the engine files it uses (paths, records, slots, prompts, control, install, session).
#   bench swe <n> [--arm <arm>]... [--solo] [--engine <version | commit>] [--settings <json>] [--again] [--task <id>]
#                                      runs the first n tasks of the pinned order (1 to 500) with each arm (default:
#                                      conveyor; --solo is --arm solo; --engine is the version a conveyor arm runs;
#                                      --settings the task set and limits every arm shares, swe_settings; --again
#                                      runs each task again where a kept result could be reused, swe_reused;
#                                      --task, with n 1, runs that one task of the pinned order, not the first)
#   bench swe arms [check [--settings <json>] <arm>...]
#                                      the arms with their preflight state; check runs those arms' preflights
#   bench swe arms save <name> <spec>  keeps a saved arm's choices as a new revision and prints its ID (swe_armsave)
#   bench swe arms show <id>           a saved revision as it was saved
#   bench swe stop [<run id>]          ends the run of that ID, or with none the run in progress (swe_stop)
#   bench swe runs archive | restore | delete <run>...
#                                      archives runs, restores them, or deletes their lines, tails and the results
#                                      no other run shows (swe_runs); a run that has not ended is refused
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
# sessions, tokens, minutes, timedOut (the arm's command reached taskTimeout), its cost at list prices (swe_cost; an agent arm's
# is an estimate, swe_estimate), a card's records and, for a conveyor arm, fixRounds and findingsFixed (the findings of the
# reviews a fix round followed), the inputs; and from the grade: class,
# tests, ref and measures, as swe_harness.py's grade says, with only class kept for a patch that was not graded: none
# when the result is older than them, which each reader shows as null, not kept) and .patch, preflight/<arm>/<key>.json (key: swe_armkey(); each check's record, from its start, swe_ckopen) and its lock, preflight/<arm>/id/<id>.json (each ended check's record by its ID, for a day, swe_ckend),
# arms/<id>.json (each saved arm revision, swe_armsave), frozen/<arm> while a run goes (its copy of what a conveyor
# arm reads of the project, swe_freeze),
# a line a run in runs.jsonl (changed under runs.lock, swe_runlog), the run in progress in live.json, tails/<run>.jsonl (each run's event tail, swe_event),
# versions.json (the last versions read and the key they were read at, swe_versionsnow), and board.json, what the snapshot carries for the Board's Benchmarks tab (the tab reads the runs and results with
# history and show).
# The dataset's rows (each task's reference fix and hidden tests) are never kept (a result keeps the reference fix's size and the
# names of the hidden tests the patch failed, never their text): the card's sessions have a shell as
# this account, so the harness reads them into a cache of its own that it removes, for the task list and each grade.
# A result of the same key and task whose recorded inputs are the trial's now is reused, never run again (but by a run
# with --again, which keeps its own result apart: again/<run id>/<key>/<task>.json, .patch and .log, with again, the
# run's ID; its run shows it, the results and figures read the kept one): another model, rule, engine, task set or limit is another key. A result kept before its inputs were recorded is read, never reused. A task whose image cannot be fetched or built, whose
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
# tests) are removed first. A list whose tasks have no cmd (the test command run in the task's container) or no env
# (the shell commands that start the task's environment there) is made again.
swe_tasks() {
  local rev f err=''; rev=$(swe_set .revision); f=$(swe_list "$rev" "$(swe_set .seed)")
  rm -f "$SWE_DIR"/raw.*.jsonl
  [ -s "$f" ] && head -n 1 "$f" | jq -e 'has("cmd") and has("env")' > /dev/null 2>&1 && { printf '%s\n' "$f"; return; }
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
# The released versions and main, as JSON [{name, commit}], newest release first. Each read is kept in versions.json
# under its key (swe_vkey), for swe_versionsnow.
swe_versions() {
  local src l vs; src=$(swe_src) && [ -n "$src" ] && l=$(timeout 20 git ls-remote "$src" refs/heads/main 'refs/tags/v*' 2>/dev/null) \
    || { echo "conveyor: the engine's versions could not be read from ${src:-its repository}" >&2; return 1; }
  vs=$(swe_vlist <<<"$l") || return 1
  { mkdir -p "$SWE_DIR" && swe_put "$SWE_DIR/versions.json" "$(jq -nc --arg k "$(swe_vkey "$src")" --argjson v "$vs" '{key: $k, versions: $v}')"; } 2>/dev/null || :
  printf '%s\n' "$vs"
}
# The versions as JSON from lines of `<commit> <ref>` as ls-remote prints them (a tag's peeled commit on a line of
# its own, its ref ending ^{}). The ref <main> (refs/heads/main by default) is main's. One jq, as the snapshot reads
# the versions each time.
swe_vlist() { # [<main>]
  jq -Rsc --arg m "${1:-refs/heads/main}" 'split("\n") | map([splits("[ \t]+") | select(. != "")] | select(. != [])
      | (.[1] // "" | if . == $m then "refs/heads/main" else . end | sub("^refs/(tags|heads)/"; "")) as $n
      | {name: ($n | sub("\\^\\{\\}$"; "")), commit: .[0], peeled: ($n | endswith("^{}"))})
      | map(select(.name == "main" or (.name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")))) | group_by(.name) | map(sort_by(.peeled) | last | del(.peeled))
      | (map(select(.name == "main")) + (map(select(.name != "main")) | sort_by(.name | ltrimstr("v") | split(".") | map(tonumber)) | reverse))'
}
swe_vkey() { printf '%s %s\n' "$1" "$(jq -rn '(($ENV.CONVEYOR_NOW // "" | tonumber?) // now) | todate[0:13]')"; } # <source>: it and the hour
# The versions now, for the snapshot, which runs often: read with no network call from the git folder on this
# machine when there is one: a source that is a folder (file:// or a path) as ls-remote reads it, and the default
# source (this engine checkout's origin) from this checkout's release tags and origin/main, as it last fetched them.
# The default source's list that swe_versions read this hour (versions.json's key is the key now) is used in place of
# the checkout's; its tags read in an earlier hour are added to the checkout's, as a tag stays. A source named by URL is read again (swe_versions) only when versions.json's key is not the key now (swe_vkey:
# another source or hour); a read that fails keeps the last list of that same source (never another's) under the key now, so a source that cannot be
# reached is not asked again on each snapshot. Prints nothing when no list can be read.
swe_versionsnow() {
  local src g m l vs k pre='' own=''; src=$(swe_src) && [ -n "$src" ] || return 1; g=${src#file://} m=refs/heads/main
  [ -d "$g" ] || { [ -z "${CONVEYOR_BENCH_SOURCE:-}" ] && g=$HERE m=refs/remotes/origin/main own=1; } || g=''
  if [ -n "$g" ]; then
    # The origin's own read (`bench swe versions`) is newer than this checkout's last fetch: a tag it read and the
    # checkout has not fetched shows, in the hour of the read and after it.
    if [ -n "$own" ]; then
      vs=$(jq -c --arg k "$(swe_vkey "$src")" 'select(.key == $k) | .versions | arrays' "$SWE_DIR/versions.json" 2>/dev/null) || vs=''
      [ -z "$vs" ] || { printf '%s\n' "$vs"; return; }
      pre=$(jq -r --arg s "$src " 'select(.key | strings | startswith($s)) | .versions | arrays | .[] | select(.name != "main") | "\(.commit) refs/tags/\(.name)"' "$SWE_DIR/versions.json" 2>/dev/null) || pre=''
    fi
    l=$(git -C "$g" for-each-ref --format='%(objectname) %(refname)%(if)%(*objectname)%(then)%0a%(*objectname) %(refname)^{}%(end)' 'refs/tags/v*' "$m" 2>/dev/null) || return 1
    swe_vlist "$m" <<<"${pre:+$pre$'\n'}$l"; return
  fi
  k=$(swe_vkey "$src") || return 1
  vs=$(jq -c --arg k "$k" 'select(.key == $k) | .versions | arrays // null' "$SWE_DIR/versions.json" 2>/dev/null) || vs=''
  if [ -n "$vs" ]; then [ "$vs" != null ] && printf '%s\n' "$vs"; return; fi
  vs=$(swe_versions 2>/dev/null) && { printf '%s\n' "$vs"; return; }
  vs=$(jq -c --arg s "$src " 'select(.key | strings | startswith($s)) | .versions | arrays' "$SWE_DIR/versions.json" 2>/dev/null) || vs=''
  { mkdir -p "$SWE_DIR" && swe_put "$SWE_DIR/versions.json" "$(jq -nc --arg k "$k" --argjson v "${vs:-null}" '{key: $k, versions: $v}')"; } 2>/dev/null || :
  [ -n "$vs" ] && printf '%s\n' "$vs"
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
# The release a full commit id is, as swe_resolve names it, for a run that ends before swe_resolve reads (a refused
# one): read from the engine's source (swe_versions), so a tag this checkout has not fetched shows; from the versions
# kept on this machine (swe_versionsnow) when the source cannot be reached. Prints nothing for a commit no release has.
swe_relname() { # <commit>
  [[ $1 =~ ^[0-9a-f]{40}$ ]] || return 0
  { swe_versions 2>/dev/null || swe_versionsnow 2>/dev/null; } | jq -r --arg c "$1" 'map(select(.commit == $c and .name != "main")) | first.name // ""' 2>/dev/null || :
}
# Whether the project's usage guard is reached now (the loop's own test: state(), lib/control.sh), whatever the
# project's mode: a paused or stopped project's guard still stands for a run of its own. The guard of an arm that is
# not the engine's reads the one Claude account copied into its container (swe_login), the builder's, whatever agent
# and route the seats have: guardread reads none for a Codex or OpenCode builder or one on an API route. The guard of a
# conveyor arm reads the accounts of the seats its card runs on: the arm's seats over the project's (as swe_ctl sets
# them), so an arm whose fix or testFix runs on Claude is held back though the project's seats are all Codex.
swe_guarded() { # [an arm that is not the engine's: any non-empty word] [a conveyor arm's seats, JSON]
  local pct c s=${2:-}; [ -n "$s" ] || s='{}'; ctlread 2>/dev/null || return 1
  c=$(jq -c --argjson s "$s" '. + $s' <<<"$CTL_V") || return 1
  pct=$(swe_pct "$c" "${1:-}")
  [ "$(state "$(jq -c '.mode = "run"' <<<"$CTL_V")" "$pct")" = "paused by guard" ]
}
# With fresh, the reading is asked for whatever the age of the last asking (reading fresh); with last, the other arm's
# is the newest kept, never asked (lastread).
swe_pct() { # <control record> [an arm that is not the engine's: any non-empty word] [fresh | last]: the week's use the guard reads, "" for none
  local f=''; [ "${3:-}" != fresh ] || f=fresh
  if [ -n "${2:-}" ] && [ "${3:-}" = last ]; then ACCT=$(ctlacct "$1") lastread | jq -r '.pct // empty'
  elif [ -n "${2:-}" ]; then ACCT=$(ctlacct "$1") reading $f | jq -r '.pct // empty'; else guardread "$1" "${f:-ask}" | jq -r '.pct // empty'; fi
}
# The share of the week left at which the guard stops new trials (100 less its percent; "off" for no guard, which stops
# nothing), null when the control record does not read. The Board's Plan keeps a plan's use of the week above it.
swe_weekstop() {
  ctlread 2>/dev/null || { echo null; return; }
  jq -c 'if .guard == null then "off" else 100 - .guard end' <<<"$CTL_V"
}
# {conveyor, agent, shared}: the share of the week left that each guard a run's arms have (swe_guards) reads now (100 less
# its reading, swe_pct, to a tenth), null for one they have not, one with no reading, or a control record that does not read;
# shared, true when both guards read one account: the conveyor guard reads the highest of its accounts (guardread), so both
# read the builder's account when it is one of them and its reading is that highest, though a Claude reviewer has an
# account of its own. A drop in the week is then the use of the trials of both kinds of arm together and the Board takes it so.
# With fresh (the reading after a trial), each is asked for whatever the age of the last asking: a run that ends within
# LIMIT_TTL of its start would otherwise end on its start's reading and show no use of the week. The builder's account,
# when the conveyor guard has just asked for it, is not asked again for the other arm: two askings can differ, and
# one account has one share of the week left.
swe_weeks() { # <conveyor: non-empty when the run has a conveyor arm> <agent: non-empty when it has another arm on the Claude login> [fresh]
  local c='' a='' s=false o=false fa=${3:-}
  if ctlread 2>/dev/null; then
    [[ $'\n'$(subaccts "$CTL_V" | cut -d ' ' -f 2-)$'\n' == *$'\n'"$(ctlacct "$CTL_V")"$'\n'* ]] && o=true
    [ -z "$1" ] || { c=$(swe_pct "$CTL_V" '' "${3:-}"); [ "$o:${3:-}" != true:fresh ] || fa=last; }
    [ -z "$2" ] || a=$(swe_pct "$CTL_V" 1 "$fa")
    if [ -n "$c" ] && [ "$c" = "$a" ] && [ "$o" = true ]; then s=true; fi
  fi
  jq -nc --arg c "$c" --arg a "$a" --argjson s "$s" 'def left: if . == "" then null else (100 - tonumber) * 10 | round / 10 end;
    {conveyor: ($c | left), agent: ($a | left), shared: $s}'
}
# How many tasks a difference must reach to be told from run-to-run noise with n tasks: two standard errors of the
# difference of two resolved counts at a rate of one half, ceil(sqrt(2n)), and never more than n (with so few tasks
# that this passes n, only a total break, a difference of n, shows). noised() is that number, for swe_diff's verdict too.
SWE_NOISED='def noised($n): [(2 * $n | sqrt | ceil), $n] | min;'
swe_noise() { jq -rn --argjson n "$1" "$SWE_NOISED"'noised($n) as $d | if $d >= $n then "with \($n) task\(if $n > 1 then "s" else "" end) only a total break shows: a difference under \($n) is within the noise"
  else "with \($n) tasks a difference under \($d) tasks is within the noise" end'; }
# The sessions a task takes, usual (the mean of the arm's results so far, else build and review for a conveyor arm,
# or the arm's own sessions) and worst case (a conveyor arm's: the build, MAX_REVIEWS reviews, the fix rounds between
# them, the one fix of a failed test step and the review after it, each review run twice (one with no verdict runs
# again: lib/review.sh) and, while the control record has the judge on, a judge session for each review; another arm's
# own sessions), its minutes (swe.json's for its kind at first) and
# session, the dollars one session costs at list prices: the mean
# of this project's own priced card sessions (the snapshot's $STATE.priced, dashboard_limit.py cardlines' summary: a
# header line, then a line a card, the card priced in its second tab-separated field; each step with dollars above 0;
# a test run costs none), those priced at the arm's model when it is given one; null when there is none to take the mean of.
swe_pertask() { # <arm> <conveyor | agent> <the arm's sessions> [<the arm's model>]
  local w=$((3 * MAX_REVIEWS + 3)); ! judgeon > /dev/null || w=$((4 * MAX_REVIEWS + 4))
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
# (the last read, SWE_VERSIONS; the snapshot puts swe_versionsnow's in their place) and the expected figures. The runs and the results are not in it (the snapshot's size):
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
# A run's line as the Board reads it ($R: each result by "<key>/<task>", reskey, and a result an --again run kept
# apart by "<run id>/<key>/<task>", which resof gives that run first): its line without its tasks and pid, n the
# tasks of each arm, and cols, each arm with the tasks it did (done), the trials it ran (ran: done, less the reused tasks and those not run, but for those not run as their grade failed, ungraded; the
# Board's Plan takes the share of the week one trial used from them), resolved and not run, and the sessions, tokens
# and minutes of its results of the tasks it ran (null when the line names no results key: a line written before
# cols), classes, the count of each class of those results (null when one has none: kept before classes), and cost, the list price of the work it did in this run (costsum of each task's cost, the interrupted
# task's and the active task's so far, the active one's none before its trial's command starts; a reused task adds
# none, and a task or interrupted line kept with no cost, as one written before costs were, is unknown, as is a col kept with no arm, which no task can be matched to); the
# run's cost is that of its cols (null when one is). wall is the wall minutes of the arm's work in this run: each
# task it ran (a reused task adds none) and the interrupted one's (a line kept with no minutes adds none); the active
# task's minutes so far are the time since its active.start. A run whose process is gone with no end written shows
# stopped, as the snapshot shows it, with gone true and no ended: its end and its containers wait for a Stop
# (swe_stop), whose end keeps gone true.
# costsum: the list price of several pieces of work ({usd, state} each, as swe_cost gives it; null when none was
# kept): known when every piece is (none at all is a known $0), estimate when every piece is known or an estimate (an
# agent arm's, swe_estimate) and one is an estimate, partial when some piece is priced in whole or in part
# (usd the priced part), else unknown (usd null).
SWE_RUNSUM='def costsum: [.[] | objects | .usd | numbers] as $u | all(.[]; type == "object" and (.state | IN("known", "estimate"))) as $k | any(.[]; type == "object" and .state == "estimate") as $e
  | {usd: (if $u == [] then (if $k then 0 else null end) else $u | add * 10000 | round / 10000 end),
     state: (if $k then (if $e then "estimate" else "known" end) elif $u == [] then "unknown" else "partial" end)};
  def reskey: "\(if .again then "\(.again)/" else "" end)\(.key)/\(.task)";
  def resof($R; $run; $k; $id): $R["\($run)/\($k)/\($id)"] // $R["\($k)/\($id)"];
  def runsum($R): . as $l | ((.arms // [.arm]) | length) as $na
  | (if .state == "running" and (.pid | type) == "number" and (.alive | not) then {state: "stopped", gone: true, ended: null, current: null, active: null} else {} end) as $gone
  | del(.tasks, .pid, .alive) + $gone + {n: (((.n // 0) / ([$na, 1] | max)) | floor), cols: [(.cols // ((.arms // [.arm]) | map({arm: ., key: null, label: .})))[] | . as $c
    | [$l.tasks[]? | select(.arm == $c.arm)] as $t | [$t[] | select(.result | tostring | startswith("not run") | not)] as $ran
    | [$ran[] | resof($R; $l.id; $c.key; .id) // empty] as $r | def sum(f): if $c.key == null then null else $r | map(f // 0) | add // 0 end;
    $c + {done: ($t | length), ran: ([$ran[] | select(.reused != true)] + [$t[] | select(.ungraded == true)] | length), resolved: ($t | map(select(.result == "resolved")) | length), notRun: (($t | length) - ($ran | length)),
      sessions: sum(.sessions), tokens: sum(.tokens), classes: (if $c.key == null or any($r[]; .class == null) then null else $r | map(.class) | group_by(.) | map({key: .[0], value: length}) | from_entries end), minutes: (sum(.minutes) | if . == null then null else . * 10 | round / 10 end),
      cost: (if $c.key == null then null elif $c.arm == null then [null] | costsum else [($t[] | select(.reused != true) | .cost), ($l.interrupted | objects | select(.arm == $c.arm) | .cost), ($l.active | objects | select(.arm == $c.arm) | .cost | objects)] | costsum end),
      wall: ([($t[] | select(.reused != true) | .minutes), ($l.interrupted | objects | select(.arm == $c.arm) | .minutes) | numbers] | add // 0 | . * 10 | round / 10)}]}
  | .cost = (if any(.cols[]; .cost == null) then null else [.cols[].cost] | costsum end);'
# figures($runs; $key): what one results key's results (the input, an array) add up to, as results --json and history's
# keys give it. Every figure is null when a result it counts has not kept what it needs (a result kept before the grade's
# fields, or a measure that could not be taken), never a zero: classes (the count of each class), failToPassPassed and
# passToPassBroken (the totals of the tests' counts), clean (how many results are clean), and over the resolved results
# medians (files, codeAdded, codeRemoved, testAdded, size) and rates (the share, 0 to 1, with lintClean, size at most 2,
# strays and provesFix true), and tokensPerResolved (all the results' tokens over the resolved count). sameTwice is the
# share of the tasks the key ran twice (two runs' lines of it, archived runs left out, that ran the task, neither reused: $runs, swe_lines; a
# run with --again runs a task again on the same inputs) that got the same resolved or not both times, not rounded (1
# only when every such task agreed); null when it never ran a task twice.
SWE_FIGS='def median: sort | if length == 0 then null else (.[((length - 1) / 2) | floor] + .[(length / 2) | floor]) / 2 end;
  def kept(f): map(f) | if any(. == null) then null else . end;
  def rate(f): kept(f) | if . == null then null else (map(select(.)) | length) / length * 100 | round / 100 end;
  def figures($runs; $key): . as $r | map(select(.resolved == true)) as $ok | all($r[]; .class != null) as $g
    | {classes: (if $g then $r | map(.class) | group_by(.) | map({key: .[0], value: length}) | from_entries else null end),
       failToPassPassed: (if $g then $r | map(.tests.failToPass.passed // 0) | add else null end),
       passToPassBroken: (if $g then $r | map(.tests.passToPass.failed // 0) | add else null end),
       clean: ($r | kept(if .measures.clean != null then .measures.clean elif .class == "nopatch" then false else null end) | if . == null then null else map(select(.)) | length end),
       medians: (if $ok == [] then null else $ok | {files: (kept(.measures.files) | if . == null then null else median end), codeAdded: (kept(.measures.codeAdded) | if . == null then null else median end),
         codeRemoved: (kept(.measures.codeRemoved) | if . == null then null else median end), testAdded: (kept(.measures.testAdded) | if . == null then null else median end),
         size: (kept(.measures.size) | if . == null then null else median end)} end),
       rates: (if $ok == [] then null else $ok | {lintClean: rate(.measures.lintClean), size: rate(.measures.size | if . == null then null else . <= 2 end),
         strays: rate(.measures.strays), provesFix: rate(.measures.provesFix)} end),
       tokensPerResolved: (if $ok == [] then null else ($r | map(.tokens // 0) | add) / ($ok | length) | round end),
       sameTwice: ([$runs[] | select(.archived | type != "string") | (.cols // [] | map(select(.key == $key) | .arm)) as $a | .tasks[]? | select(.arm as $x | $a | index($x))
           | select(.reused != true and (.result | tostring | startswith("not run") | not)) | {id, r: (.result == "resolved")}]
         | group_by(.id) | map(select(length > 1)) | if length == 0 then null else (map(.[0].r as $f | select(all(.[]; .r == $f))) | length) / length end)};'
# Every run's line (runs.jsonl, then the run in progress), one JSON a line, alive true on a running line whose process is there.
swe_lines() {
  local p; p=$(jq -r 'select(.state == "running") | .pid // empty' "$SWE_DIR/live.json" 2>/dev/null)
  # Neither file is there before the first run: that is no runs, not a failure (the Board's Start reads history then).
  { cat "$SWE_DIR/runs.jsonl" 2>/dev/null; jq -c 'select(.state == "running")' "$SWE_DIR/live.json" 2>/dev/null; :; } \
    | jq -Rc --argjson a "$([ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo true || echo false)" 'fromjson? | objects | select(.id | strings) | if .state == "running" then .alive = $a else . end'
}
# `bench swe history`: what the Board's Benchmarks tab reads when it is shown, as one JSON object: runs, every run
# newest first (runsum; an archived run with archived, its time, and each run's shared: each of its results another run shows, with their IDs, swe_runs); arms, every arm with its state (swe_checkstate: checking, ready, failed, expired, changed
# since its check, unchecked, not offered), why, the step a check that runs is at, its check's ID (check) and time (at), the guard that holds it back (swe_guards), its results key on swe.json's
# settings (swe_reskey; null for a conveyor arm, whose key ends with its engine's commit: keyPrefix and the commit)
# and its sessions, minutes and a session's dollars (swe_pertask); keys, each results key with the places of its tasks
# in the pinned order (a run reuses them: at), live (the same places less the results only an archived run names: what the
# Scoreboard counts as tasks with a result) and its figures (SWE_FIGS); order, every task ID of the set in the pinned
# order of swe.json's settings (the Board's Task map; [] when the task list cannot be read); guard, whether the usage guard
# holds back a run with a conveyor arm (conveyor) or another arm on the Claude login (agent); weekLeft, the share of the
# week each of those guards has left now (swe_weeks) and stop, the share left at which the guard stops (swe_weekstop); set, the task set, and
# limits, each task container's, of swe.json (what the Board's Plan a run says each container gets);
# choices, the models and efforts a saved arm may choose (swe_choices; null when the pack does not read).
# The arms are the host arms and then each saved revision (swe_armsave; one whose recipe is gone is left out), each
# with revision ({id, name, at, recipe}; null for a host arm), spec (the choices a copy of the arm starts
# from: a saved revision's own; a host conveyor arm's seats, rules and policy; a host agent arm's recipe, CLI and
# model when it takes a model on one CLI a container signs in to; else null), sessions and effort (a host agent arm's:
# the sessions a trial takes, and whether its run passes $SWE_EFFORT, so a saved arm on it may choose one).
# defaults, the seats a sandbox runs for each seat an arm leaves out (seat() on swe_ctl's record for an arm that sets
# none: the project's, with no card's own), fix and testFix null when the project's follows the builder, judgeOwn
# whether the project's judge names its model (else it follows the reviewer), and its judgeOn and judgeAlways; null
# when the control record does not read.
swe_history() {
  local arms='[]' n a r p m k i x s gc=false ga=false ch c df wl
  for n in $(swe_armnames); do
    a=$(swe_arm "$n") || continue
    s=null; [[ ! $n =~ $SWE_ARMID ]] || s=$(jq -c '.spec' "$SWE_DIR/arms/$n.json") || continue
    [ "$(jq -r .kind <<<"$a")" != conveyor ] || swe_mainc
    mapfile -t x < <(swe_armnow "$a"); r=$(swe_checkstate "$a" "${x[0]}" "${x[1]}")
    p=null; k=null; m=''
    if jq -e '.offered != false' <<<"$a" > /dev/null; then
      [ "$(jq -r .kind <<<"$a")" = conveyor ] || { m=$(jq -r '.model // ""' <<<"$a"); [ "$m" != builder ] || m=$(swe_solomodel); }
      i=$(swe_inputs "$a" "$m") && k=$(swe_reskey "$a" '' "$m" "$i" | jq -R .) || k=null
      p=$(swe_pertask "$n" "$(jq -r .kind <<<"$a")" "$(jq -r '.sessions // 1' <<<"$a")" "$m")
    fi
    arms=$(jq -c --argjson a "$a" --argjson r "$r" --argjson p "$p" --argjson k "$k" --arg g "$(swe_guards "$a")" --argjson s "$s" --arg m "$m" '. + [{name: $a.name, label: ($a.label // $a.name), kind: $a.kind,
      state: $r.state, why: $r.why, at: $r.at, step: $r.step, check: $r.id, guard: (if $g == "" then null else $g end), perTask: $p,
      key: (if $a.kind == "conveyor" then null else $k end), keyPrefix: (if $a.kind == "conveyor" then $k else null end),
      revision: ($a.revision // null), sessions: (if $a.kind == "agent" and $a.revision == null then $a.sessions // 1 else null end),
      effort: ($a.kind == "agent" and $a.revision == null and $a.effort == true),
      spec: (if $s != null then $s elif $a.kind == "conveyor" then {kind: "conveyor"} + ($a | {seats, rules, policy} | with_entries(select(.value != null)))
        elif $a.offered != false and ($a.model | type) == "string" and $m != "" and (($a.login // []) | IN(["claude"], ["codex"])) then {kind: "agent", recipe: $a.name, cli: $a.login[0], model: $m}
        else null end)}]' <<<"$arms")
  done
  ! swe_guarded || gc=true; ! swe_guarded 1 || ga=true
  wl=$(swe_weeks 1 1 | jq -c --argjson s "$(swe_weekstop)" '. + {stop: $s}')
  ch=$(swe_choices) || ch=null
  # Each seat read on its own: one the record cannot work out is null, as seat() gives none.
  c=$(swe_ctl '{}' 2>/dev/null) && df=$(for x in builder reviewer judge fix testFix; do seat "$x" "$c" || echo null; done | jq -sc --argjson c "$c" '
    {seats: {model: .[0], reviewer: .[1], judge: .[2], fix: (if $c.fix == null then null else .[3] end), testFix: (if $c.testFix == null then null else .[4] end)},
     judgeOwn: ($c.judge.model != null), judgeOn: ($c.judgeOn == true), judgeAlways: ($c.judgeAlways // [])}') || df=null
  # Each run's shared: each result it shows that another run shows too, with those runs' IDs; a delete keeps it unless
  # it deletes them all (swe_runs).
  swe_lines | jq -sc --argjson arms "$arms" --argjson gc "$gc" --argjson ga "$ga" --argjson wl "$wl" --argjson ch "$ch" --argjson df "$df" --slurpfile res <(cat "$SWE_DIR"/results/*/*.json 2>/dev/null) --slurpfile again <(cat "$SWE_DIR"/again/*/*/*.json 2>/dev/null) \
    --slurpfile order <(jq -c .id "$(swe_list "$(swe_set .revision)" "$(swe_set .seed)")" 2>/dev/null) --argjson set "$SWE_SET" "$SWE_RUNSUM$SWE_MADE$SWE_FIGS"'
    ($res + $again | map({key: reskey, value: .}) | from_entries) as $R | ($order | to_entries | map({key: .value, value: .key}) | from_entries) as $pos
    | (map(. as $l | results[] | {p: ., id: $l.id}) | group_by(.p) | map({key: .[0].p, value: map(.id)}) | from_entries) as $S
    | {set: ($set | {dataset, revision, seed}), limits: ($set | {cpus, memory, taskTimeout}), guard: {conveyor: $gc, agent: $ga}, weekLeft: $wl, arms: $arms, choices: $ch, defaults: $df, order: $order,
       runs: (sort_by(.started // "") | reverse | map(. as $l | runsum($R) + {shared: ([$l | results[] | {key: ., value: (($S[.] // []) - [$l.id])} | select(.value | length > 0)] | from_entries)})),
       keys: (. as $L | (([$L[] | select(.archived | type == "string") | results[]] | unique) - ([$L[] | select(.archived | type != "string") | results[]] | unique)) as $gone
         | $res | group_by(.key) | map({key: .[0].key, at: (map($pos[.task] // empty) | sort), live: (map(select((reskey | IN($gone[])) | not) | $pos[.task] // empty) | sort), figures: figures($L; .[0].key)}))}'
}
# `bench swe show <run>`: one run as the Board's run page shows it: run, its line (runsum: a run going has active, the
# arm, task and phase it is at, and seq, its read revision, swe_live), tasks, each task the run took in its order and
# then each it plans and has not reached, with its title (the issue's first line) and, for each arm (cells, in cols
# order), what the run said of it (result, reused), its state (and phase, while active) and, where it ran that arm on
# the task, its kept result: resolved, fired, why, ended (why its trial ended before its command did; null when it
# did not), timedOut, sessions, tokens, minutes, cost (swe_cost; null in a result kept before it), findingsFixed and
# fixRounds (null in a result kept before them), imageBytes (the size of the task's image; null in a result kept before it), its steps (a conveyor arm's card records), its patch (each file with its lines added and removed; null when none is kept), its log (the last
# SWE_LOGN bytes of the loop's output on the task; null when none is kept) and its grade's
# class, tests, ref and measures (null in a result kept before them); and tail,
# the run's event tail (swe_event). A run with --task plans that one task, never the first of the order.
SWE_LOGN=3000
swe_show() { # <run id>
  local l k t ks=() ts=() f o
  [[ $1 =~ ^r[0-9]{8}T[0-9]{6}-[0-9]+$ ]] && l=$(swe_lines | jq -c --arg id "$1" 'select(.id == $id)' | tail -n 1) && [ -n "$l" ] \
    || { echo "conveyor: no SWE-bench run $1" >&2; return 1; }
  mapfile -t ks < <(jq -r '.cols[]?.key // empty' <<<"$l" | grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*$')
  mapfile -t ts < <(jq -r '.tasks[]?.id' <<<"$l" | awk '!s[$0]++' | grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*$')
  o=$(mktemp) || return 1
  for k in "${ks[@]}"; do for t in "${ts[@]}"; do for f in "$SWE_DIR/results/$k/$t" "$SWE_DIR/again/$1/$k/$t"; do
    [ -s "$f.json" ] || continue
    jq -c --argjson p "$(if [ -e "$f.patch" ]; then git apply --numstat "$f.patch" 2>/dev/null | jq -Rsc '[split("\n")[] | select(. != "") | split("\t")
      | {path: .[2], added: (.[0] | tonumber? // null), removed: (.[1] | tonumber? // null)}]'; else echo null; fi)" \
      --arg lg "$(tail -c "$SWE_LOGN" "$f.log" 2>/dev/null)" '. + {patch: $p, log: (if $lg == "" then null else $lg end)}' "$f.json"
  done; done; done > "$o"
  # The run's line goes in on stdin, not as an argument: a run of 500 tasks and 6 arms is past the system's limit
  # on one argument. A cell has a kept result only where this run ran that arm on the task: the result kept under
  # its key may be another run's (a run resumed after this one stopped), never this run's to show; one this run kept
  # apart (again/<run id>, a run with --again) is the one it shows. The titles are
  # read from the run's task list (a line with no set or seed took swe.json's).
  # The tasks are the ones its line names, in its order, then the rest of its plan (the first n of its task list, n
  # the run's tasks of each arm), not reached yet. Each cell's state: finished (a result is recorded), active (the arm's work in progress: its phase,
  # swe_phase), waiting (the run goes and has not reached it), interrupted (the work a Stop ended) or not reached.
  # Each cell's cost is that of this run's work on it: its task line's (a task not run after its trial ran costs what
  # the trial did), the interrupted work's, else its kept result's (a line written before costs were); null when none.
  # A cell's again is the run ID of a result this run kept apart (null for a kept result under its key, the one diff reads).
  # tail: the run's event tail (swe_event), its fields only.
  jq -c --slurpfile res "$o" --slurpfile tl <(jq -c '{id, title: (.issue // "" | split("\n") | map(select(test("\\S"))) | first // "" | .[0:160])}' \
    "$(swe_list "$(jq -r --arg d "$(swe_conf .revision)" '(.set.revision | strings | select(test("^[0-9a-f]{40}$"))) // $d' <<<"$l")" "$(jq -r --arg d "$(swe_conf .seed)" '(.set.seed | strings) // $d' <<<"$l")")" 2>/dev/null) \
    --slurpfile tail <(tail -n "$SWE_TAILN" "$SWE_DIR/tails/$1.jsonl" 2>/dev/null) "$SWE_RUNSUM"'. as $l
    | ($res | map({key: reskey, value: .}) | from_entries) as $R | ($tl | map({key: .id, value: .title}) | from_entries) as $T | ($l | runsum($R)) as $run
    | ($l.tasks | map({key: "\(.arm)/\(.id)", value: .}) | from_entries) as $E
    | (if ($l.only | type) == "string" then [$l.only] else $tl[0:((($l.n // 0) / ([($l.arms // [$l.arm]) | length, 1] | max)) | floor)] | map(.id) end) as $plan
    | def at($w; $c; $id): ($w | type) == "object" and $w.arm == $c.arm and $w.task == $id;
    {run: $run, tasks: [($l.tasks | map(.id)) + $plan | reduce .[] as $i ({s: {}, l: []}; if .s[$i] then . else .s[$i] = true | .l += [$i] end) | .l[] as $id
      | {id: $id, title: ($T[$id] // null), cells: [$run.cols[] | . as $c | $E["\($c.arm)/\($id)"] as $t
        | {arm: $c.arm, result: ($t.result // null), reused: ($t.reused // false),
           state: (if $t != null then "finished" elif at($run.active; $c; $id) then "active" elif $run.state == "running" then "waiting"
             elif at($l.interrupted; $c; $id) then "interrupted" else "not reached" end)}
          + (if $t == null and at($run.active; $c; $id) then {phase: $run.active.phase} else {} end)
          + ((if $t == null or ($t.result | tostring | startswith("not run")) then {} else resof($R; $l.id; $c.key; $id) // {} end) | {resolved, fired, why, ended, timedOut, sessions, tokens, minutes, cost, findingsFixed, fixRounds, steps, patch, log, class, tests, ref, measures, again, imageBytes})
          + {cost: (if $t != null then $t.cost // (if $t.result | tostring | startswith("not run") then null else resof($R; $l.id; $c.key; $id).cost end)
              elif at($l.interrupted; $c; $id) then $l.interrupted.cost else null end)}]}],
      tail: [$tail[] | objects | {at, arm, task, event} | select(all(.[]; . == null or type == "string"))]}' <<<"$l"
  local rc=$?; rm -f "$o"; return $rc
}
# live.json changed by a jq filter: each change adds 1 to its seq, the read revision (a step that changes and nothing
# else still changes it), and sets updated.
swe_live() { # [jq options] <jq filter>
  local l a=("$@"); local f=${a[-1]}; unset 'a[-1]'
  l=$(jq -c --arg _at "$(swe_now)" "${a[@]}" "($f) | .seq = ((.seq // 0) + 1) | .updated = \$_at" "$SWE_DIR/live.json") && swe_put "$SWE_DIR/live.json" "$l" && swe_board
}
# The run's event tail, tails/<run>.jsonl: one line an event, {at, arm, task, event} and nothing else; a file of more
# than twice SWE_TAILN lines is cut to its last SWE_TAILN, and show gives the last SWE_TAILN. Kept after the run ends (swe_end removes the run's work, not its tail), until the run is deleted (swe_runs). An event is a phase
# (swe_phase) or a result word of the run's own; never text a container wrote.
SWE_TAILN=200
swe_event() { # <event> [<arm>] [<task>]
  local f=$SWE_DIR/tails/$SWE_RUN.jsonl
  mkdir -p "$SWE_DIR/tails" && jq -nc --arg at "$(swe_now)" --arg a "${2:-}" --arg t "${3:-}" --arg e "$1" \
    '{at: $at, arm: (if $a == "" then null else $a end), task: (if $t == "" then null else $t end), event: $e}' >> "$f" || return 0
  [ "$(wc -l < "$f")" -le $((2 * SWE_TAILN)) ] || { tail -n "$SWE_TAILN" "$f" > "$f.$$" && mv -f "$f.$$" "$f"; }
}
# The work in progress of the run going (SWE_RUN): live.json's active, {arm, task, phase, since, start, cost}, of the
# arm in use and the task it is on (SWE_TASK; null while the arm's preflight runs), and an event of the phase. Nothing
# outside a run or when the phase is the one shown. start is the time the arm's work on the task began, and cost the
# trial's work so far (swe_sofar), both kept from phase to phase of one task; no cost before its trial's command starts.
# The wall minutes of the active work so far (from active.start), to a tenth; null when it has no start.
SWE_WALL='def wall: .active.start | if type == "string" then (now - fromdate) / 60 * 10 | round / 10 else null end;'
swe_phase() { # <phase>
  [ -n "${SWE_RUN:-}" ] || return 0
  ! jq -e --arg a "$SWE_ARM" --arg t "${SWE_TASK:-}" --arg p "$1" '.active | objects | .arm == $a and (.task // "") == $t and .phase == $p' "$SWE_DIR/live.json" > /dev/null 2>&1 || return 0
  swe_live --arg a "$SWE_ARM" --arg t "${SWE_TASK:-}" --arg p "$1" '(if $t == "" then null else $t end) as $t
    | ((.active | objects | select(.arm == $a and .task == $t)) // null) as $o
    | .active = ({arm: $a, task: $t, phase: $p, since: (now | todate), start: ($o.start // (now | todate))} + (($o | objects | select(.cost != null) | {cost}) // {}))' > /dev/null
  swe_event "$1" "$SWE_ARM" "${SWE_TASK:-}"
}
# The list price of a trial's work (the Board's pricing, dashboard_limit.py work, with the pack's prices over its
# table): {usd, state (known, partial or unknown), unpriced (the sessions it could not price), basis (the rates)}.
# Its input on stdin is a conveyor arm's card record lines and live records (a live record has no card), and the
# reviewer's last live record swe_watch kept ({reviewer: {of, live}}): the sessions are its card's build, review,
# fix and rebase lines, a failed one's on its blocked line (spent), and each review's judge, with each line's model
# and token usage; the live record of the session running is priced only while the card's last line is the start of
# its step, so the step's own line, once written, replaces what the live record said, and a session started with no
# live record is unpriced. While the judge runs, the review's live record is the judge's (judgecall()) and the
# review's line is not yet written: the reviewer is priced from the review's own fields (its .reviewed, SWE_LIVES,
# which hold both attempts of one that ran again), and only when there are none yet from the record swe_watch kept of
# it since that start line. A review that ran again has its first attempt's usage on its .firsttry (SWE_LIVES) until its line, which
# holds both (BOTHTRIES), is written: it is priced beside the second attempt's live record, or kept record while the
# judge runs (one kept in the pause is the first attempt's: the second's is then unpriced), and in the pause it is
# all the review used. A build, fix or rebase run again after it stalled (its live record names the stall) has its
# first try kept by nothing a container shows, so that try is unpriced. A line with no usage (an engine that records
# none) is unpriced; pricing that fails is unknown.
swe_cost() {
  # The prices of the run's copy of the pack (swe_root): a price changed while the run goes prices none of its tasks.
  local pp o PACK=${PACK-}; swe_root; packget prices pp 2>/dev/null && [ -n "$pp" ] || pp='{}'
  jq -Rsc --argjson p "$pp" '[splits("\n") | fromjson? | objects] as $r | [$r[] | select(has("card") and .issue == 1)] as $c | ($c | last) as $s
    | (if $s.step == "start" and ($s.of | IN("build", "review", "fix", "rebase")) then ([$r[] | select((has("card") | not) and .step == $s.of)] | last) // {step: $s.of} else null end) as $live
    | ($s.of == "review" and ([($live.action | strings | startswith("the judge ")) and (($live.at | strings) >= ($s.time | strings))] | any)) as $judging
    | (if $s.of == "review" then [$r[] | .reviewed | objects] | last else null end) as $rv
    | (if $s.of == "review" and $rv == null then [$r[] | select(has("firsttry") and (.firsttry | type) == "object")] | last else null end) as $ft
    | {prices: $p, live: (if ($rv != null or ($ft != null and $ft.second != true)) and ($judging | not) then null else $live end),
       steps: [($c[] | if .step == "blocked" then .spent | objects else . end | select(.step | IN("build", "review", "fix", "rebase"))
           | ({step, model, usage, unread, stats: (.stats | if type == "object" then {models, byModel} else null end)}, (.judge | objects | {step: "judge", model, usage}))),
         ($ft | objects | .firsttry.spent | if type == "object" then {step: "review", model, usage, unread} else {step: "review"} end),
         (if $rv != null then $rv | {step: "review", model, usage, unread}
          elif $judging then ([$r[] | .reviewer | objects | select(.of == $s and ($ft == null or .second == true)) | .live | objects] | last
             | {step: "review", model, usage: (if .zero == true then null else .usage end)}) // {step: "review"} else empty end),
         (if $live.stalled | type == "string" and $s.of != "review" then {step: $s.of} else empty end)]}' \
    | python3 "$HERE/../.claude/scripts/dashboard_limit.py" work 2>/dev/null \
    || echo '{"usd":null,"state":"unknown","unpriced":null,"basis":{}}'
}
# A conveyor arm's trial figures from its card's lines (<cards>, the sandbox's cards.jsonl), as swe_trial prints
# them but for cost. sessions: each build, review, fix and rebase line, less a reused review (reusable(),
# lib/review.sh: no session ran), plus a review's failed first attempt (its firstTry: the review ran twice), plus each
# judge that ran (its judge holds sec, which judgecall() writes only once a call ran; one refused its seat, or with
# findings it could not read, holds failed alone).
swe_cardsum() { # <seconds> <cards>
  jq -sc --argjson m "$1" 'map(select(.issue == 1 and (.step | IN("start", "picked", "worktree", "deps", "brief") | not))) as $s
    | {fixRounds: ($s | map(select(.step == "fix")) | length),
       findingsFixed: ([range($s | length) as $i | select($s[$i].step == "review" and $s[$i].result == "NO-GO" and ($s[$i + 1:] | any(.step == "fix")))
         | $s[$i].counts | objects | add // 0] | add // 0),
       sessions: ($s | map(select((.step | IN("build", "review", "fix", "rebase")) and .reused == null)) | length)
         + ($s | map(select(.step == "review" and .reused == null and (.firstTry | type) == "object")) | length)
         + ($s | map(select(.judge | type == "object" and has("sec"))) | length),
       tokens: ($s | map((.tokens.claude // 0) + (.tokens.codex // 0) + (.judge.tokens.claude // 0) + (.judge.tokens.codex // 0)) | add // 0),
       minutes: ($m / 6 | round / 10), steps: ($s | map({step, result, reason, time, tokens} + if .step == "review" and .result != "GO" and has("tail") then {tail} else {} end
         + ({model, usage, byModel: .stats.byModel?, judge: (.judge | if type == "object" then {model, usage} else null end)} | with_entries(select(.value != null)))))}' "$2"
}
# The active trial's cost so far (live.json's active.cost: {usd, state, unpriced}), written when it changed.
swe_sofar() { # <cost json>
  jq -e --argjson k "$1" '.active | objects | .cost != ($k | {usd, state, unpriced})' "$SWE_DIR/live.json" > /dev/null 2>&1 || return 0
  swe_live --argjson k "$1" '.active.cost = ($k | {usd, state, unpriced})' > /dev/null
}
# The step a conveyor arm's card is at, from its card records and its live records (the lines on stdin; a live record
# has no card): the step its last start line opens, by its name in SWE_STEPS; Judging while a review's judge reads the
# findings (the card's live record of the review step is the judge's, judgecall(), written since that start line); an
# engine that writes no start line (or a step not named there) shows SWE_NOSTEP. The records are the arm's to write:
# no other text of them is shown.
SWE_STEPS='{"build": "Building", "review": "Reviewing", "fix": "Fixing", "rebase": "Rebasing", "test": "Testing", "land": "Landing", "file": "Filing follow-ups"}'
SWE_NOSTEP='Running Conveyor. Step unavailable.'
# With <seen>, the start line shown last (swe_watch; null when none was), the step of each start line after it comes
# first, one a line: a step that started and ended between two reads is still shown. With no <seen>, or one no longer
# in the lines, only the last step is shown.
swe_stepof() { # [<seen>]
  jq -rRs --argjson m "$SWE_STEPS" --arg u "$SWE_NOSTEP" --slurpfile seen <(printf '%s' "${1-}") '[splits("\n") | fromjson? | objects] as $r
    | [$r[] | select(.step == "start" and (.of | type) == "string")] as $a | ($a | last) as $s
    | if $s == null then $u
      else (if $seen == [null] then -1 else [range($a | length) as $i | select($a[$i] == $seen[0]) | $i] | last // ($a | length - 1) end) as $i
        | ($a[$i + 1:-1][] | $m[.of] // $u),
          (if $s.of == "review" and any($r[]; (has("card") | not) and .step == "review" and (.action | strings | startswith("the judge "))
            and (.at | strings) >= ($s.time | strings)) then "Judging"
          else $m[$s.of] // $u end) end'
}
# While a trial's command runs (<pid>) on a task of the run: the phase it is at (swe_phase). An agent arm's is
# "Running agent"; a conveyor arm's is its card's step (swe_stepof), read in its container every 2 seconds from its
# card records and the live records in <sb>/cards, the cards folder its loop runs on (swe_trial). The same records
# give the trial's cost so far (swe_cost, swe_sofar), priced again only when they changed; the reviewer's last live
# record before the judge's replaced it is kept in <sb>.h/reviewer, with the start line it follows and whether it is a
# second attempt's (SWE_LIVES), for swe_cost and
# the trial's final figure (swe_trial). An agent arm reports no usage while it runs, so its cost is unknown.
# A card's live records, in its container, and the first attempt of a review that ran again (reviewed() keeps it in
# <card>.firsttry, .firsttry.new while that attempt's events are still there, until the review's line is written), as
# {second, firsttry}: second is true once the second attempt has written its events, so the review's live record is
# that attempt's (as stopped() tells them apart), and false in the pause, when the live record is still the first's.
# Then the review's fields once it ended, while its judge runs and until its line is written (<card>.reviewed, the
# review step's), as {reviewed}.
SWE_LIVES='for f in "$SWE_CARDS"/*.live; do [ ! -f "$f" ] || { echo; head -c 4000 "$f"; echo; }; done
  for f in "$SWE_CARDS"/*.firsttry.new "$SWE_CARDS"/*.firsttry; do
    [ -f "$f" ] || continue; w=${f%.new}; w=${w%.firsttry}; s=false
    if [ "$f" = "$w.firsttry" ]; then [ ! -f "$f.new" ] || continue; [ ! -s "$w.events" ] || s=true; fi
    printf "\n{\"second\":%s,\"firsttry\":" "$s"; tr -d "\n" < "$f"; printf "}\n"
  done
  for f in "$SWE_CARDS"/*.reviewed; do [ ! -s "$f" ] || { printf "\n{\"reviewed\":"; tr -d "\n" < "$f"; printf "}\n"; }; done; :'
# Each card of the cards folder that only waits: its <worktree>.idle mark stands (the engine stands it while the
# card sleeps out a wait for main to change, on another card, for the machine or for its seat's CLI, and never while
# a session, check or test of it runs), as {idle: <card>, action: <its live record's action>, model: <its live
# record's model>}.
SWE_IDLE='for f in "$SWE_CARDS"/*.idle; do [ -e "$f" ] || continue; w=${f%.idle}
    jq -cn --arg c "${w##*/}" --arg a "$(jq -r ".action | strings" "$w.live" 2>/dev/null)" --arg m "$(jq -r ".model | strings" "$w.live" 2>/dev/null)" \
      "{idle: \$c, action: \$a, model: \$m}"; done; :'
# Whether the trial's card only waits, from the lines on stdin (its card records, and SWE_IDLE's): the newest card of
# the task's issue has not ended, and its idle mark stands. Prints {card, why} then, why naming the wait from its live
# record's action (cut to 300 characters); nothing otherwise. A card in a session, check or test has no idle mark; a
# mark beside a live record that names a model is a session's own (a session's and the judge's record name their
# model, a wait's never does): the session can write the cards folder, and it does not end the trial.
swe_waited() {
  jq -Rsc '[splits("\n") | fromjson? | objects] as $r | ([$r[] | select(has("card") and .issue == 1)] | last) as $s
    | select($s != null and ($s.step | IN("landed", "blocked", "closed") | not))
    | [$r[] | select(.idle | strings | . == $s.card)] | last | objects | select((.model // "") == "")
    | {card: .idle, why: ("its card waited" + (.action | strings // "" | .[:300]
        | if startswith("waiting ") then " " + .[8:] elif . == "" then ", with no session or test of it running" else ": " + . end))}'
}
# A conveyor card that waits (swe_waited) waits on in a trial for its whole time limit: no other card lands and main
# never changes there. The trial's command is then stopped (each process under <pid>) and <sb>.h/waited keeps
# {card, why}: the trial grades that card's change (swe_trial).
swe_watch() { # <pid> <container> <kind> <sb>
  [ -n "${SWE_TASK:-}" ] || return 0
  [ "$3" = conveyor ] || { swe_phase 'Running agent'; swe_sofar "{\"usd\":null,\"state\":\"unknown\",\"unpriced\":${SWE_SESSIONS:-1}}"; return 0; }
  local k=0 r was='' v ps seen=null end=''
  while :; do
    # Read once more after the command ended: a step that started since the last read is still shown.
    kill -0 "$1" 2>/dev/null || end=1
    if { [ -n "$end" ] || [ $((k % 10)) = 0 ]; } && r=$(swe_in 60 "$2" / 'tail -n 200 "$SWE_SST/cards.jsonl" 2>/dev/null; '"$SWE_LIVES; $SWE_IDLE" \
        "SWE_SST=$SWE_SST" "SWE_CARDS=$4/cards" < /dev/null); then
      [ -n "$end" ] || v=$(swe_waited <<<"$r")
      if [ -z "$end" ] && [ -n "$v" ]; then
        printf '%s\n' "$v" > "$4.h/waited"; mapfile -t ps < <(swe_tree "$1"); kill -TERM "${ps[@]}" 2>/dev/null; break
      fi
      while IFS= read -r v; do swe_phase "$v"; done < <(swe_stepof "$seen" <<<"$r")
      seen=$(jq -Rsc '[splits("\n") | fromjson? | objects | select(.step == "start" and (.of | type) == "string")] | last' <<<"$r")
      if [ "$r" != "$was" ]; then
        was=$r
        v=$(jq -Rsc '[splits("\n") | fromjson? | objects] as $r | ([$r[] | select(has("card") and .issue == 1)] | last) as $s | select($s.step == "start" and $s.of == "review")
          | ([$r[] | select(has("firsttry")) | .second] | last) as $f
          | [$r[] | select((has("card") | not) and .step == "review" and (.action | strings // "" | startswith("the judge ") | not))] | last | objects
          | {reviewer: {of: $s, live: ., second: ($f == true)}}' <<<"$r")
        [ -z "$v" ] || printf '%s\n' "$v" > "$4.h/reviewer"
        swe_sofar "$({ printf '%s\n' "$r"; cat "$4.h/reviewer" 2>/dev/null; } | swe_cost)"
      fi
    fi
    [ -z "$end" ] || break
    k=$((k + 1)); sleep 0.2
  done
}
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
  # Who opened the open issues (openissues(), lib/issues.sh): the owner opened #1, so the loop's queue takes it (with no
  # answer it reads #1 as opened by someone outside the project, and holds it).
  api:graphql) case "$*" in *authorAssociation*) if open; then n='[{"number":1,"authorAssociation":"OWNER","parent":null,"subIssues":{"nodes":[]}}]'; else n='[]'; fi
    echo '{"data":{"repository":{"nameWithOwner":"sandbox/swe","issues":{"nodes":'"$n"',"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}' ;; esac ;;
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
# arm's now (a result kept before inputs were recorded has none, and is run again), and the run is not --again (one
# that runs each task again on the same inputs: it keeps its result apart, swe_task, and each run's line keeps what it got).
swe_reused() { [ -z "${SWE_AGAIN:-}" ] && jq -e --argjson i "$SWE_INPUTS" '.inputs == $i' "$SWE_DIR/results/$SWE_KEY/$1.json" > /dev/null 2>&1; } # <task id>
# The run reuses a task's kept result: under runs.lock, so a delete (swe_runs) never removes the result between the
# check and live.json's line of it. Sets r (resolved or unresolved); fails when the result is not there to reuse.
# A Stop (TERM or INT) that comes while it holds the lock waits until the lock is let go, then is raised again: its
# trap (swe_stopping) writes the run's end, and appends its line under runs.lock (swe_runlog), which it would wait on
# here until Stop killed the run with no end written.
swe_reuse() { # <task id>
  local f rc=1 t q=''; exec {f}>>"$SWE_DIR/runs.lock" || return 1
  t=$(trap -p TERM INT); trap 'q=TERM' TERM; trap 'q=INT' INT
  if flock -w 60 "$f" && swe_reused "$1"; then
    r=$(jq -r 'if .resolved then "resolved" else "unresolved" end' "$SWE_DIR/results/$SWE_KEY/$1.json") \
      && swe_live --arg t "$1" --arg a "$SWE_ARM" --arg r "$r" '.tasks += [{id: $t, arm: $a, result: $r, reused: true}] | .done += 1 | .active = null | .resolved += (if $r == "resolved" then 1 else 0 end)'
    rc=$?
  fi
  exec {f}>&-; trap - TERM INT; eval "$t"
  [ -z "$q" ] || kill -s "$q" "$BASHPID"
  return $rc
}
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
# did not fire is the arm's failed task: kept, never graded, never run again; but one whose command failed on its
# login (loginFailed, swe_trialrun) is not run, so it runs again once the owner signs in. The result keeps the run's
# inputs (swe_inputs): a conveyor arm's sandbox reads the run's copy of the project's files (swe_freeze). Once its
# trial has run, every end removes the task's sandbox and the trial's folder: the grade writes the hidden tests there.
# A grade that fails, whatever its exit (3 too: the harness's evaluation wrote no report), comes after the trial ran:
# SWE_UNGRADED (exit <n>) says so, never a fault of the image the trial ran in.
SWE_UNGRADED='not run: the harness could not grade it'
swe_rmsb() { { chmod -R u+w "$1" "$1.h"; rm -rf "$1" "$1.h"; } 2>/dev/null; } # <sb>: it and its trial's folder <sb>.h
swe_task() { # <task json>
  local id sb b g rc sz out=$SWE_DIR/results/$SWE_KEY ag=''; id=$(jq -r .id <<<"$1"); sb=$SWE_DIR/work/$id
  # A run with --again on a task with a kept result keeps its own apart, under again/<run id>: the kept one stays the
  # earlier run's, which still shows it.
  [ -z "${SWE_AGAIN:-}" ] || [ ! -e "$out/$id.json" ] || { out=$SWE_DIR/again/$SWE_RUN/$SWE_KEY; ag=$SWE_RUN; }
  swe_phase 'Preparing image'
  swe_h image "$(jq -r .image <<<"$1")" > /dev/null 2>&1 || { echo "not run: its Docker image could not be fetched or built"; return; }
  # The image's size in bytes, kept with the result; null when Docker does not say it.
  sz=$(docker image inspect --format '{{.Size}}' "$(jq -r .image <<<"$1")" 2>/dev/null | grep -E '^[0-9]+$' | head -n 1)
  swe_phase 'Setting up'
  mkdir -p "$SWE_DIR/work" && swe_sandbox "$1" "$sb" 2> "$SWE_DIR/work/$id.err" \
    || { echo "not run: its repository could not be fetched at the base commit: $(head -c 300 "$SWE_DIR/work/$id.err")"; return; }
  b=$(swe_trial "$1" "$sb" "$SWE_ARMJ" "$SWE_ENG") && [ -n "$b" ] && jq -e . <<<"$b" > /dev/null 2>&1 || { swe_rmsb "$sb"; echo "not run: ${b:-the patch of the sandbox could not be read}"; return; }
  # The trial's cost from all its records replaces what was read of them while it ran: the run counts it even when
  # the task is then not run.
  swe_sofar "$(jq -c .cost <<<"$b")"
  ! jq -e '.loginFailed == true' <<<"$b" > /dev/null || { swe_rmsb "$sb"; echo "not run: its login failed: $(jq -r .why <<<"$b")"; return; }
  if ! jq -e .fired <<<"$b" > /dev/null || [ ! -s "$sb.h/patch" ]; then g='{"resolved":false,"class":"nopatch"}'
  else swe_phase Grading; g=$(swe_h grade "$(swe_set .dataset)" "$(swe_set .revision)" "$id" "$sb.h/patch" "$sb.h/grade" "$SWE_RUN" 2>/dev/null); rc=$?
    [ "$rc" = 0 ] && jq -e '.resolved | type == "boolean"' <<<"$g" > /dev/null 2>&1 || { swe_rmsb "$sb"; echo "$SWE_UNGRADED (exit $rc)"; return; }
  fi
  mkdir -p "$out" && cp "$sb.h/patch" "$out/$id.patch" && { [ ! -e "$sb.h/loop.log" ] || cp "$sb.h/loop.log" "$out/$id.log"; } && swe_put "$out/$id.json" "$(jq -c --arg t "$id" --arg a "$SWE_ARM" --arg k "$SWE_KEY" --arg e "${SWE_COMMIT:-}" --arg v "${SWE_VERSION:-}" \
    --arg m "${SWE_MODEL:-}" --arg l "$SWE_LABEL" --argjson g "$g" --arg at "$(swe_now)" --argjson i "$SWE_INPUTS" --arg ag "$ag" --argjson z "${sz:-null}" '{task: $t, arm: $a, label: $l, key: $k, engine: (if $e == "" then null else $e end), version: (if $v == "" then null else $v end),
    model: (if $m == "" then null else $m end), resolved: $g.resolved, at: $at, inputs: $i, imageBytes: $z} + ($g | del(.resolved)) + . + (if $ag == "" then {} else {again: $ag} end)' <<<"$b")" || { swe_rmsb "$sb"; echo "not run: its result could not be kept"; return; }
  swe_rmsb "$sb"
  if jq -e .resolved <<<"$g" > /dev/null; then echo resolved; elif jq -e .fired <<<"$b" > /dev/null; then echo unresolved; else echo "unresolved ($(jq -r .why <<<"$b"))"; fi
}
# The cost so far of the active trial of a conveyor arm (live.json's active arm; its kind SWE_KIND's, or for a run
# whose process is gone its column's), from all its card's lines and live records and the reviewer's record swe_watch
# kept, read in its container as swe_trial reads them at a trial's end (swe_sofar), on the run's copy of the pack.
# Every process of the trial there is ended first (swe_boxstop): nothing it writes after the read is left out of the
# cost, as the container is removed after it. Nothing when no such trial runs, or its container is gone or does not
# answer within 10 seconds (Stop kills the run 30 seconds after its signal).
swe_endcost() {
  local t='' a='' k='' sb r c SWE_FZ
  { read -r t; read -r a; read -r k; } < <(jq -r '.active as $x | select(($x.task | type) == "string") | $x.task, $x.arm, ([.cols[]? | select(.arm == $x.arm) | .kind | strings] | first // "")' "$SWE_DIR/live.json" 2>/dev/null)
  [ -n "$t" ] && [ "${SWE_KIND:-$k}" = conveyor ] || return 0
  sb=$SWE_DIR/work/$t; c=$(swe_boxname "$(jq -nc --arg n "$a" '{name: $n}')" "$t"); SWE_FZ=$SWE_DIR/frozen/${a//[^A-Za-z0-9._-]/-}
  swe_boxstop "$c" 10
  r=$(swe_in 10 "$c" / 'cat "$SWE_SST/cards.jsonl" 2>/dev/null; '"$SWE_LIVES" \
    "SWE_SST=$sb/$SWE_MAIN/conveyor/state" "SWE_CARDS=$sb/cards" < /dev/null) || return 0
  swe_sofar "$({ printf '%s\n' "$r"; cat "$sb.h/reviewer" 2>/dev/null; } | swe_cost)"
}
# The run's end: its line in runs.jsonl, live.json's state, the containers of its trials and preflights, the
# sandboxes and the run's copies of the project's files (swe_freeze) gone. The containers removed are the run's own,
# named with its ID (swe_trial's, and the grading harness's: swe_harness.py's grade): an arms check's, which runs apart from any run, is left. A Stop that comes while the
# end is written waits for it (SIGTERM ignored until then), so a run that finished first keeps its one end, done.
swe_end() { # <state> [gone: its process had ended with no end written]
  [ -n "${SWE_RUN:-}" ] || return 0
  trap '' TERM INT
  # interrupted: the arm and task a stopped run was on, apart from the tasks it never reached, with the cost of its
  # work so far (swe_sofar; a known $0 when its trial had not started its command) and its wall minutes: the run's
  # cost and its arm's wall count them. gone: the end of a run whose process had ended (the Board says interrupted).
  # A Stop, of a run going or of one whose process is gone, reads a conveyor arm's records in its trial's container
  # once more first (swe_endcost): swe_watch priced them at most every 2 seconds, so a session's usage written after
  # its last read would be lost.
  [ "$1" != stopped ] || swe_endcost
  local l f; l=$(jq -c --arg s "$1" --arg g "${2:-}" --arg at "$(swe_now)" "$SWE_WALL"'(if $s == "stopped" and (.active.task | type) == "string" then {interrupted: (wall as $w | .active | {arm, task, cost: (.cost // {usd: 0, state: "known", unpriced: 0}), minutes: $w})} else {} end) as $i
    | .state = $s | .ended = $at | .current = null | .active = null | .seq = ((.seq // 0) + 1) | .updated = $at | del(.pid) + $i + (if $g == "" then {} else {gone: true} end)' "$SWE_DIR/live.json") && swe_put "$SWE_DIR/live.json" "$l" \
    && swe_runlog "$l"
  swe_event "Run ${1/guard/stopped by the usage guard}"
  # By name in Docker's list, never by a file: a trial's container can write its sandbox, so a file there could name
  # any container.
  docker ps -a --filter "name=$SWE_RUN-" --format '{{.Names}}' 2>/dev/null | while IFS= read -r f; do
    case $f in "sweb.eval."*".conveyor-$SWE_RUN-"?*|"conveyor-swe-$SWE_RUN-"?*) docker rm -f "$f" > /dev/null 2>&1 ;; esac
  done
  [ ! -d "$SWE_DIR/work" ] || { chmod -R u+w "$SWE_DIR/work"; rm -rf "$SWE_DIR/work"; }
  rm -rf "$SWE_DIR/frozen"; rm -f "$SWE_DIR/stop"; swe_board; SWE_RUN=; trap - TERM INT
}
# Whether the usage guard holds back a run of these kinds of arm: <conveyor> holds the seats of each conveyor arm of the
# run (swe_armseats, a line each; empty for none), <agent> is non-empty when it has another arm that uses the Claude
# login (swe_guards).
swe_held() { # <conveyor> <agent>
  local s
  while IFS= read -r s; do [ -z "$s" ] || ! swe_guarded '' "$s" || return 0; done <<<"$1"
  [ -n "$2" ] && swe_guarded 1
}
swe_armseats() { jq -c '.seats // {}' <<<"$1"; } # <arm json>: the seats it sets over the project's (swe_ctl)
# Whether the usage guard holds back one arm now (swe_guards: an arm with no Claude login is never held).
swe_armheld() { case $(swe_guards "$1") in conveyor) swe_held "$(swe_armseats "$1")" '' ;; agent) swe_held '' 1 ;; *) return 1 ;; esac; } # <arm json>
# Which guard an arm is held back by: "conveyor" (the engine's), "agent" (the Claude account an arm that is not the
# engine's uses) or nothing, for an arm with no Claude login (Codex alone): the Claude guard does not hold it.
swe_guards() { jq -r 'if .kind == "conveyor" then "conveyor" elif (.login // [] | index("claude")) then "agent" else empty end' <<<"$1"; } # <arm json>
# A run's record before its arms' contexts are taken (swe_context): its ID (SWE_RUN), arms, task count and settings,
# its conveyor arms naming the engine asked for; running (with its process: Stop finds it while its setup goes) or
# refused (ended, with why).
swe_setuprec() { # <n> <engine> <running | refused> [<why>] < the arms' JSON, one a line
  jq -sc --arg id "$SWE_RUN" --argjson pid "$$" --argjson n "$1" --arg at "$(swe_now)" --arg e "$2" --arg s "$3" --arg w "${4:-}" --arg v "${SWE_VERSION:-}" --argjson set "$SWE_SET" '($e | test("^[0-9a-f]{40}$")) as $c
    | {id: $id, arm: .[0].name, arms: map(.name), label: (map(.label // .name) | join(", ")), n: ($n * length),
       cols: map({arm: .name, key: null, label: (.label // .name), kind}
         + (if .kind == "conveyor" then {engine: (if $c then $e else null end), version: (if $c then ($v | if . == "" then null else . end) else $e end)} else {} end)),
       set: ($set | {dataset, revision, seed}), limits: ($set | {cpus, memory, taskTimeout}), done: 0, resolved: 0, current: null, started: $at, state: $s, tasks: []}
    + if $s == "running" then {pid: $pid, active: null, seq: 1, updated: $at} else {ended: $at, why: $w} end'
}
# A run that ends before it is one: live.json as it was before its start (none: no live.json), no Stop trap, no run.
swe_unstart() { # <live.json before the run's start>
  trap - TERM INT
  if [ -n "$1" ]; then swe_put "$SWE_DIR/live.json" "$1"; else rm -f "$SWE_DIR/live.json"; fi
  SWE_RUN=
}
# A run: the first n tasks, each built by every arm in turn, so a run stopped early has compared the arms on the same
# tasks. Each arm is picked only once its preflight passed (swe_ready) and, for a conveyor arm, the area rule files
# its cards of these tasks read are there (swe_taskrules).
swe_run() { # <n> <engine> <arm>...
  local n=$1 eng0=$2 tf all i t id r x a l left rid gc='' ga='' why prev ctxs=() specs=() plan='[]' ra tag ag SWE_TASK=''
  shift 2
  mkdir -p "$SWE_DIR" && swe_lock || { echo "conveyor: a SWE-bench run is already going; \`conveyor.sh bench swe stop\` ends it" >&2; return 1; }
  for x; do a=$(swe_arm "$x") || { echo "conveyor: no arm $x: \`conveyor.sh bench swe arms\` lists them" >&2; return 2; }
    # A saved revision is checked against the project's choices now, not only at its save: a pass of its check can be
    # from before a model was removed (swe_savedwhy).
    why=$(swe_savedwhy "$a"); [ -z "$why" ] || { echo "conveyor: $why" >&2; return 1; }
    specs+=("$a"); case $(swe_guards "$a") in conveyor) gc+=$(swe_armseats "$a")$'\n' ;; agent) ga=1 ;; esac; done
  # The run is live from here, before its setup (the task list, the engine's install, the copies of the project's
  # files), which can take minutes: live.json says it is running, with its process, so a Stop then finds it and ends
  # it (stopped). An early end that is no run (the guard, the task list, n or --task, an arm's context) puts live.json
  # back as it was (swe_unstart): no run is recorded.
  SWE_RUN=r$(date -u +%Y%m%dT%H%M%S)-$$; rm -f "$SWE_DIR/stop"; prev=$(cat "$SWE_DIR/live.json" 2>/dev/null)
  swe_put "$SWE_DIR/live.json" "$(printf '%s\n' "${specs[@]}" | swe_setuprec "$n" "$eng0" running)" || { SWE_RUN=; return 1; }
  trap 'swe_stopping; exit 143' TERM INT
  ! swe_held "$gc" "$ga" || { swe_unstart "$prev"; echo "conveyor: the usage guard is reached: no SWE-bench run starts while it stands" >&2; return 1; }
  # A build machine that cannot run a task refuses the run, kept as its recorded end (state refused, with why) as a
  # failed preflight is, so the run history still says what to repair once the Board no longer waits for the answer.
  # Its conveyor arms name the engine asked for. Written here, not by swe_end: no container or sandbox is this run's,
  # and the ones swe_end removes can be an arms check's.
  why=$(swe_setup 2>&1) || { echo "$why" >&2
    # An engine given as a commit is named by its version, as a run that started names it (swe_resolve). The lookup
    # can wait for the origin: a Stop then still records the time it reached the run (swe_stopping). A Stop while the
    # refused end is written waits for it, as one in swe_end does.
    SWE_VERSION=$(swe_relname "$eng0"); trap '' TERM INT
    l=$(printf '%s\n' "${specs[@]}" | swe_setuprec "$n" "$eng0" refused "${why#conveyor: }") && swe_put "$SWE_DIR/live.json" "$l" && swe_runlog "$l"; SWE_RUN=; swe_board; trap - TERM INT; return 1; }
  tf=$(swe_tasks) || { swe_unstart "$prev"; return 1; }; all=$(wc -l < "$tf")
  [ "$n" -le "$all" ] || { swe_unstart "$prev"; echo "conveyor: the task list holds $all tasks: n is 1 to $all" >&2; return 2; }
  # --task: the run's one task is that one, not the first of the order.
  [ -z "${SWE_ONLY:-}" ] || { jq -c --arg t "$SWE_ONLY" 'select(.id == $t)' "$tf" > "$SWE_DIR/only.jsonl" && [ -s "$SWE_DIR/only.jsonl" ] \
    || { swe_unstart "$prev"; echo "conveyor: the task list has no task $SWE_ONLY" >&2; return 2; }; tf=$SWE_DIR/only.jsonl; }
  rm -rf "$SWE_DIR/frozen"; for x; do swe_context "$x" "$eng0" || { swe_unstart "$prev"; return 1; }; ctxs+=("$SWE_CTX"); done
  # The run's whole record, once its arms' contexts are taken: a failed preflight is the run's recorded end (state
  # refused, with why), which the Board shows once it no longer waits for the answer.
  # cols names each arm's results key (the Board's history and run page read each arm's results by it), set the
  # task set (dataset, revision and seed: runs of one set are read side by side) and limits each trial's (swe_settings).
  # again: true for a run with --again, which reuses no kept result (the Board's Live run then counts none as reused).
  # weekStart and weekLeft: the share of the week the guards of the run's arms (swe_weeks) had left when it started and after its last trial: the Board's Live run says it and what the run needs.
  swe_put "$SWE_DIR/live.json" "$(printf '%s\n' "${ctxs[@]}" | jq -sc --arg id "$SWE_RUN" --argjson pid "$$" --argjson n "$n" --arg at "$(swe_now)" --arg ag "${SWE_AGAIN:-}" --arg only "${SWE_ONLY:-}" \
    --argjson w "$(swe_weeks "$gc" "$ga")" --argjson set "$SWE_SET" "$SWE_NAMES"'. as $c | $c[0]
    | {id: $id, pid: $pid, arm, key, engine, version, model, arms: ($c | map(.arm)), label: ($c | map(runname) | join(", ")), n: ($n * ($c | length)),
       cols: ($c | map({arm, key, label, kind, engine, version, model})), set: ($set | {dataset, revision, seed}), limits: ($set | {cpus, memory, taskTimeout}),
       weekStart: $w, weekLeft: $w, done: 0, resolved: 0, current: null, active: null, seq: 1, updated: $at, started: $at, state: "running", tasks: []} + (if $ag == "" then {} else {again: true} end) + (if $only == "" then {} else {only: $only} end)')"
  swe_board; swe_event 'Run started'
  # The run's receipt, once its record is written: the Board's Start answers it. A run that reuses the saved result
  # of each of its tasks prints none, so Start waits for its end and answers its result, whose last line names it.
  left=''; for x in "${ctxs[@]}"; do swe_use "$x"
    while IFS= read -r id; do swe_reused "$id" || { left=1; break; }; done < <(head -n "$n" "$tf" | jq -r .id); [ -z "$left" ] || break; done
  [ -z "$left" ] || echo "conveyor: run $SWE_RUN started"
  for x in "${ctxs[@]}"; do
    swe_use "$x"; swe_phase Checking
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
      swe_use "$x"; tag=''; [ ${#ctxs[@]} = 1 ] || tag=" [$SWE_ARM]"; SWE_TASK=''
      [ "$(cat "$SWE_DIR/stop" 2>/dev/null)" != "$SWE_RUN" ] || { trap - TERM INT; swe_stopping; return 0; }
      if swe_reuse "$id"; then
        echo "$i/$n $id$tag: $r (reused)"
        swe_event "Reused: ${r^}" "$SWE_ARM" "$id"
        continue
      fi
      ! swe_armheld "$SWE_ARMJ" || { echo "conveyor: the usage guard is reached: the run stops before $id"; swe_end guard; return 0; }
      swe_live --arg t "$id" '.current = $t'
      SWE_TASK=$id; r=$(swe_task "$t"); echo "$i/$n $id$tag: $r"
      # The task's cost is its trial's (swe_sofar); a task whose trial never started its command ran no session: $0.
      # Its minutes are the wall time of the arm's work on it (SWE_WALL), a task not run included. A task not run as
      # its grade failed (SWE_UNGRADED) had its trial run: ungraded, which the run's ran counts (SWE_RUNSUM).
      ag=false; [ ! -e "$SWE_DIR/again/$SWE_RUN/$SWE_KEY/$id.json" ] || ag=true
      swe_live --arg t "$id" --arg a "$SWE_ARM" --arg r "$r" --argjson ag "$ag" --arg ug "$SWE_UNGRADED" --argjson w "$(swe_weeks "$gc" "$ga" fresh)" "$SWE_WALL"'.weekLeft = $w | .tasks += [{id: $t, arm: $a, result: $r, reused: false, cost: (.active.cost // {usd: 0, state: "known", unpriced: 0}), minutes: wall} + (if $ag then {again: true} else {} end) + (if $r | startswith($ug) then {ungraded: true} else {} end)] | .done += 1 | .current = null | .active = null | .resolved += (if $r == "resolved" then 1 else 0 end)'
      # The event names the result only: the why of a task not run can hold a command's own output.
      case $r in resolved) r=Resolved ;; unresolved) r=Unresolved ;; unresolved*) r='Unresolved: did not fire' ;; *) r='Not run' ;; esac
      swe_event "$r" "$SWE_ARM" "$id"
    done
  done
  jq -r --argjson n "$n" --slurpfile l "$SWE_DIR/live.json" "$SWE_NAMES"'.[].c | . as $c | [$l[0].tasks[] | select(.arm == $c.arm)] as $t
    | "Resolved \($t | map(select(.result == "resolved")) | length) of \($n) with \(runname); not run: \($t | map(select(.result | startswith("not run"))) | length)."' <<<"$plan"
  rid=$SWE_RUN; swe_end 'done'
  # A run that reused each task's saved result printed no receipt: its last line names it once its end is recorded,
  # so the Board's Start opens its results.
  [ -n "$left" ] || echo "conveyor: run $rid ended"
}
swe_tree() { local k; echo "$1"; for k in $(pgrep -P "$1"); do swe_tree "$k"; done; } # <pid>: it and every process under it
# The run lock, run.lock on fd 7, held by a run for its life. It is taken under the stop lock (swe_stop), and a run
# that live.json still shows running gets its end first (stopped, with the task it was on; its containers and work
# removed): with the run lock free, its process has ended with no end written. So while a Stop reads and acts, no run
# starts, and a late Stop of a run that is gone finds it ended, never the run after it.
swe_lock() {
  local s id rc=0; exec {s}>>"$SWE_DIR/stop.lock" || return 1
  if flock -w 60 "$s" && exec 7>>"$SWE_DIR/run.lock" && flock -n 7; then
    id=$(jq -r 'select(.state == "running") | .id // empty' "$SWE_DIR/live.json" 2>/dev/null)
    [ -z "$id" ] || { SWE_RUN=$id; swe_end stopped gone; }
  else rc=1; fi
  exec {s}>&-; return $rc
}
# Stop's SIGTERM (or Ctrl-C) to the run going: live.json's stopping (the time Stop reached it) and its event, then
# the trial's processes ended and the run's end (swe_end), which keeps both.
swe_stopping() {
  [ -n "${SWE_RUN:-}" ] || return 0
  swe_live '.stopping = $_at' > /dev/null; swe_event Stopping; pkill -TERM -P $$ 2>/dev/null; swe_end stopped
}
# Stop: ends the run <id> (with none, the run going: `bench swe stop` as typed), and says how it ended. Under the stop
# lock (swe_lock), as is the run lock's start: the run live.json names is the one this Stop acts on, never one that
# starts while it acts. A run that is going gets SIGTERM, its process tree with it (swe_stopping records its end), and
# SIGKILL after 30 s; one whose process is gone (its run lock is free) with no end written gets its end here. A Stop
# of a run that ended (the same Stop again, or one sent before the run finished) changes nothing, and a run after it
# goes on.
swe_stop() { # [<run id>]
  local id=${1:-} s l p ps i=0 gone='' rc=0
  mkdir -p "$SWE_DIR" && exec {s}>>"$SWE_DIR/stop.lock" || return 1
  flock -w 60 "$s" || { exec {s}>&-; echo "conveyor: another Stop is going; read the run's state again" >&2; return 1; }
  [ -n "$id" ] || id=$(jq -r 'select(.state == "running") | .id // empty' "$SWE_DIR/live.json" 2>/dev/null)
  if [ -z "$id" ]; then echo "conveyor: no SWE-bench run is going"
  else
    # Its process, or "gone" for a running record with none (never 0: kill takes 0 as this Stop's own process group).
    p=$(jq -r --arg id "$id" 'select(.id == $id and .state == "running") | if (.pid | type) == "number" and .pid > 1 then .pid else "gone" end' "$SWE_DIR/live.json" 2>/dev/null)
    if [ -n "$p" ]; then
      # A free run lock: the run's process has ended (swe_lock), and its pid may now be another process's.
      exec {l}>>"$SWE_DIR/run.lock" && { ! flock -n "$l" || p=gone; exec {l}>&-; }
      if [ "$p" != gone ] && kill -0 "$p" 2>/dev/null; then
        printf '%s\n' "$id" > "$SWE_DIR/stop"; mapfile -t ps < <(swe_tree "$p"); kill -TERM "${ps[@]}" 2>/dev/null
        while kill -0 "$p" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
        mapfile -t ps < <(swe_tree "$p"); ! kill -0 "$p" 2>/dev/null || kill -KILL "${ps[@]}" 2>/dev/null
      else gone=1; fi
      # A run killed before its end was written (SIGKILL, or a process gone before Stop) gets it here.
      ! jq -e --arg id "$id" '.id == $id and .state == "running"' "$SWE_DIR/live.json" > /dev/null 2>&1 || { SWE_RUN=$id; swe_end stopped "$gone"; }
    fi
    swe_said "$id" "$gone"; rc=$?
  fi
  exec {s}>&-; return $rc
}
# What Stop says of the run <id>: how it ended, from live.json when it is that run's, else from its line in runs.jsonl.
swe_said() { # <run id> <non-empty: its process was gone when Stop came>
  local s; s=$(jq -r --arg id "$1" 'select(.id == $id) | .state' "$SWE_DIR/live.json" 2>/dev/null)
  [ -n "$s" ] || s=$(jq -r --arg id "$1" 'select(.id == $id) | .state' "$SWE_DIR/runs.jsonl" 2>/dev/null | tail -n 1)
  case $s in
    stopped) if [ -n "$2" ]; then echo "conveyor: run $1 was interrupted: its process had ended. Its end is recorded, its containers are removed, and its finished tasks are kept."
      else echo "conveyor: run $1 is stopped. Its finished tasks are kept."; fi ;;
    done) echo "conveyor: run $1 finished before Stop." ;;
    guard) echo "conveyor: run $1 had stopped at the usage guard before Stop." ;;
    refused) echo "conveyor: run $1 did not start, before Stop." ;;
    '') echo "conveyor: no SWE-bench run $1" >&2; return 1 ;;
    *) echo "conveyor: run $1 did not end: read its state again" >&2; return 1 ;;
  esac
}
# runs.jsonl changes under runs.lock: a run's end appended (swe_end, a refused run's) and the file written whole
# (swe_runs) never cross, so neither loses the other's line.
swe_runlog() { # <line>
  local f rc; exec {f}>>"$SWE_DIR/runs.lock" || return 1
  flock -w 60 "$f" && printf '%s\n' "$1" >> "$SWE_DIR/runs.jsonl"; rc=$?; exec {f}>&-; return $rc
}
# The kept results a run's line shows, each "<key>/<task>": those it made, those it reused and, for a task an --again
# run kept apart (again: true; that result is under again/<run id>, the run's own), the kept one of its key: so a run
# deleted before the --again runs of its key leaves the kept result for them. A task not run keeps none; a line with
# no results key (one written before cols) names none.
SWE_MADE='def results: . as $l | [.tasks[]? | select(.result | tostring | startswith("not run") | not)
  | . as $t | ([$l.cols[]? | select(.arm == $t.arm) | .key | strings] | first) as $k | select($k != null) | "\($k)/\($t.id)"] | unique;'
# `bench swe runs archive | restore | delete <run>...`, under runs.lock. Archive puts archived (its time) on each run's
# line and restore takes it off: the line, its tail and its results stay (the Board leaves an archived run out of its
# lists, Compare and the infographic). Delete removes each run's line, its tail and the results it shows (results/<key>/
# <task>.json, .patch and .log: those it made, and those it reused from a run deleted before; and again/<run id>, those
# it kept apart), but not a result another run shows (a later run reused it): that one stays, and its
# run still shows it. A run that has not ended (live.json's running, its process there or gone) is refused: Stop
# records its end first. Nothing changes when one run named is refused. It prints one line of what it did.
swe_runs() { # archive | restore | delete <run>...
  local v=$1 id ids s rc; shift
  for id; do [[ $id =~ ^r[0-9]{8}T[0-9]{6}-[0-9]+$ ]] || { echo "conveyor: no SWE-bench run $id" >&2; return 1; }; done
  ids=$(printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(. != "")) | unique')
  mkdir -p "$SWE_DIR" && exec {s}>>"$SWE_DIR/runs.lock" || return 1
  flock -w 60 "$s" || { exec {s}>&-; echo "conveyor: the runs are being changed: try again" >&2; return 1; }
  swe_runsdo "$v" "$ids"; rc=$?; exec {s}>&-; return $rc
}
swe_runsdo() { # archive | restore | delete <ids json>
  local v=$1 ids=$2 id l p gone=() said
  id=$(jq -r --argjson ids "$ids" 'select(.state == "running" and (.id | IN($ids[]))) | .id' "$SWE_DIR/live.json" 2>/dev/null | head -n 1)
  [ -z "$id" ] || { echo "conveyor: run $id has not ended: stop it first (\`conveyor.sh bench swe stop $id\`)" >&2; return 1; }
  id=$({ cat "$SWE_DIR/runs.jsonl" 2>/dev/null; :; } | jq -Rnr --argjson ids "$ids" '$ids - [inputs | fromjson? | objects | .id] | first // empty')
  [ -z "$id" ] || { echo "conveyor: no SWE-bench run $id" >&2; return 1; }
  # Every other line is kept as it is.
  l=$(jq -Rr --argjson ids "$ids" --arg v "$v" --arg at "$(swe_now)" '. as $raw | (fromjson? // null) as $j
    | if ($j | type) == "object" and ($j.id | IN($ids[])) then (if $v == "delete" then empty elif $v == "archive" then $j | .archived = (.archived // $at) | tojson else $j | del(.archived) | tojson end)
      else $raw end' "$SWE_DIR/runs.jsonl") || return 1
  if [ "$v" != delete ]; then swe_put "$SWE_DIR/runs.jsonl" "$l" || return 1
    echo "conveyor: $([ "$v" = archive ] && echo archived || echo restored) $(jq -r 'join(", ")' <<<"$ids")."; return
  fi
  # Every result the runs show (made or reused: a reused one whose maker was deleted first is theirs now), less those
  # another run shows: those stay for it. The other runs are runs.jsonl's and live.json's in any state: a run that has
  # written its end there and waits on runs.lock to append its line (swe_end) keeps the results it reused.
  said=$({ swe_lines; jq -c . "$SWE_DIR/live.json" 2>/dev/null; :; } | jq -sc --argjson ids "$ids" "$SWE_MADE"'(map(select(.id | IN($ids[]) | not) | results[]) | unique) as $keep
    | ([.[] | select(.id | IN($ids[])) | results[]] | unique) as $made | {gone: ($made - $keep), kept: ($made - ($made - $keep) | length)}') || return 1
  mapfile -t gone < <(jq -r '.gone[]' <<<"$said" | grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$')
  if [ -z "$l" ]; then rm -f "$SWE_DIR/runs.jsonl"; else swe_put "$SWE_DIR/runs.jsonl" "$l"; fi || return 1
  for p in "${gone[@]}"; do rm -f "$SWE_DIR/results/$p.json" "$SWE_DIR/results/$p.patch" "$SWE_DIR/results/$p.log"; rmdir "$SWE_DIR/results/${p%/*}" 2>/dev/null; done
  for id in $(jq -r '.[]' <<<"$ids"); do rm -f "$SWE_DIR/tails/$id.jsonl"; rm -rf "${SWE_DIR:?}/again/$id"; done
  # The readings Compare kept (swe_diff, diff/<key A>/<key B>) of a key whose result went: a result made again under
  # that key would be read with the old reading. A key holds no "/", so the key as A or as B is matched whole.
  for p in $(printf '%s\n' "${gone[@]}" | sed -n 's|/.*||p' | sort -u); do
    rm -rf "${SWE_DIR:?}/diff/$p" "$SWE_DIR"/diff/*/"$p"
  done
  # live.json of a deleted run that ended (the last run) goes too, so Stop and the Board no longer name it.
  ! jq -e --argjson ids "$ids" '.id | IN($ids[])' "$SWE_DIR/live.json" > /dev/null 2>&1 || { rm -f "$SWE_DIR/live.json"; swe_board; }
  jq -r --argjson ids "$ids" '"conveyor: deleted \($ids | join(", "))\(if .kept > 0 then "; \(.kept) result\(if .kept > 1 then "s" else "" end) stay\(if .kept > 1 then "" else "s" end): another run shows \(if .kept > 1 then "them" else "it" end)" else "" end)."' <<<"$said"
}
# Each key's results, side by side: one line each, then the noise line for the tasks every key ran.
swe_results() { # [--json]
  local j; j=$(cat "$SWE_DIR"/results/*/*.json 2>/dev/null | jq -sc --slurpfile runs <(swe_lines) "$SWE_FIGS"'group_by(.key) | map({key: .[0].key, arm: .[0].arm, label: .[0].label, engine: .[0].engine, version: .[0].version, model: .[0].model, inputs: .[0].inputs,
    n: length, resolved: (map(select(.resolved)) | length), notFired: (map(select(.fired == false)) | length), sessions: (map(.sessions) | add), tokens: (map(.tokens) | add),
    minutes: (map(.minutes) | add * 10 | round / 10), classes: (if all(.[]; .class != null) then (map(.class) | group_by(.) | map({key: .[0], value: length}) | from_entries) else null end),
    figures: figures($runs; .[0].key),
    tasks: map({task, resolved, fired, sessions, tokens, minutes, timedOut, findingsFixed, fixRounds, class, tests, ref, measures})}) | sort_by(.version // "")')
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
    SIDE_COMMIT=''; SIDE_NAME=$arm; m=$(jq -r '.model // ""' <<<"$a")
    # An arm on the builder's model is named with it, as resname names its results.
    [ "$m" != builder ] || { m=$(swe_solomodel); SIDE_NAME="$arm (${m:-default})"; }
  fi
  # A result kept before arms has no arm: it is the conveyor arm's. Its folder is its key.
  SIDE_KEY=$(jq -rn --arg a "$(jq -r .name <<<"$a")" --arg e "$SIDE_COMMIT" --arg m "$m" '[inputs | select((.arm // "conveyor") == $a and (.engine // "") == $e and ($m == "" or .model == $m))
    | {at: (.at // ""), key: (input_filename | split("/") | .[-2])}] | max_by(.at) | .key // empty' "$SWE_DIR"/results/*/*.json 2>/dev/null)
  [ -n "$SIDE_KEY" ] || { echo "conveyor: $1 has no results" >&2; return 1; }
}
# Two sides that both run an engine are told the engine changes to the stage where their runs went apart; for any
# other two, changes is null. Each side's totals have cost, the list price of its results on those tasks (costsum: a
# result kept before costs were has none, so it is unknown, never $0). steps: the stages whose engine files a commit
# between the two sides changed, a task flipped or not (stagemap.sh's map of B's engine, in the order of a card's
# stages); null when a side runs no engine or the map cannot be made.
swe_diff() { # <A> <B> [--json]
  local ca cb va vb ka kb d da db ids id fa fb st sm='' files=() flips='[]' ch why n e='' steps=null
  swe_side "$1" || return 1; ca=$SIDE_COMMIT; va=$SIDE_NAME; ka=$SIDE_KEY; swe_side "$2" || return 1; cb=$SIDE_COMMIT; vb=$SIDE_NAME; kb=$SIDE_KEY
  da=$SWE_DIR/results/$ka; db=$SWE_DIR/results/$kb
  ids=$(comm -12 <(cd "$da" 2>/dev/null && ls -- *.json 2>/dev/null | sort) <(cd "$db" 2>/dev/null && ls -- *.json 2>/dev/null | sort) | sed 's/\.json$//')
  [ -n "$ids" ] || { echo "conveyor: $1 and $2 have no task in common to compare" >&2; return 1; }
  if [ -n "$ca" ] && [ -n "$cb" ]; then
    { installed "$cb" || install "$cb" "$(swe_src)" > /dev/null; } && e=$VERSIONS/$cb || { echo "conveyor: engine $2 could not be installed to read its stages" >&2; return 1; }
  fi
  local mp=''
  if [ -n "$e" ] && sm=$(bash "$HERE/bench/stagemap.sh" "$e/conveyor" 2>/dev/null); then
    mp=1; local lg; lg=$(git -C "$e" log --format= --name-only "$ca...$cb" -- conveyor 2>/dev/null) \
      && steps=$(awk -F '\t' 'NR == FNR { if ($0 != "") c[$0] = 1; next } ("conveyor/" $1) in c { n = split($2, s, ","); for (i = 1; i <= n; i++) print s[i] }' \
        <(printf '%s\n' "$lg") <(printf '%s\n' "$sm") | jq -Rsc '["build", "review", "fix", "test", "land", "push"] as $o | split("\n") | map(select(. != "")) | unique
        | sort_by(. as $s | $o | index($s) // 99)') || steps=null
  else sm=''
  fi
  d=$SWE_DIR/diff/$ka/$kb; mkdir -p "$d"
  while IFS= read -r id; do
    fa=$(cat "$da/$id.json"); fb=$(cat "$db/$id.json")
    [ "$(jq -n --argjson a "$fa" --argjson b "$fb" '$a.resolved == $b.resolved')" = false ] || continue
    st=$(jq -rn --argjson a "$fa" --argjson b "$fb" "$SWE_STAGE"' apart($a.steps; $b.steps) // "build"')
    # The files of that stage in B's engine (stagemap.sh); null changes when its map cannot be made, or a side runs no engine.
    ch=null; [ -n "$mp" ] && ch='[]' \
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
  local j; j=$(jq -n --slurpfile fl <(printf '%s\n' "$flips") --arg va "$va" --arg vb "$vb" --arg ca "$ca" --arg cb "$cb" --argjson steps "$steps" --arg noise "$(swe_noise "$(wc -l <<<"$ids")")" \
    --slurpfile ra <(for id in $ids; do cat "$da/$id.json"; done) --slurpfile rb <(for id in $ids; do cat "$db/$id.json"; done) "$SWE_RUNSUM$SWE_NOISED"'
    def tot: {resolved: (map(select(.resolved)) | length), sessions: (map(.sessions) | add), tokens: (map(.tokens) | add), minutes: (map(.minutes) | add * 10 | round / 10),
      cost: (map(.cost) | costsum)};
    def c: if . == "" then null else . end; $fl[0] as $f
    | ($ra | length) as $n | ($ra | tot) as $ta | ($rb | tot) as $tb | noised($n) as $dd
    | {a: {version: $va, commit: ($ca | c), totals: $ta}, b: {version: $vb, commit: ($cb | c), totals: $tb}, tasks: $n,
       same: [$ra[] | .task] - [$f[] | .task], flipped: $f, steps: $steps, noise: $noise, withinNoise: ((($ta.resolved - $tb.resolved) | fabs) < $dd)}')
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
  SWE_AGAIN=''; SWE_ONLY=''; swe_settings || return 1
  case ${1:-} in
    stop) if [ $# = 1 ]; then swe_stop; return; elif [ $# = 2 ] && [[ $2 =~ ^r[0-9]{8}T[0-9]{6}-[0-9]+$ ]]; then swe_stop "$2"; return; fi ;;
    results) [ $# = 1 ] || [ "$*" = 'results --json' ] && { swe_results "${2:-}"; return; } ;;
    history) [ $# = 1 ] && { swe_history; return; } ;;
    show) [ $# = 2 ] && { swe_show "$2"; return; } ;;
    versions) [ $# = 1 ] && { SWE_VERSIONS=$(swe_versions) && swe_board && printf '%s\n' "$SWE_VERSIONS"; return; } ;;
    diff) { [ $# = 3 ] || { [ $# = 4 ] && [ "$4" = --json ]; }; } && { swe_diff "$2" "$3" "${4:-}"; return; } ;;
    arms) shift; swe_arms "$@"; return ;;
    runs) [ $# -ge 3 ] && [[ $2 =~ ^(archive|restore|delete)$ ]] && { shift; swe_runs "$@"; return; } ;;
  esac
  [[ ${1:-} =~ ^[1-9][0-9]{0,2}$ ]] && [ "$1" -le "$(swe_conf .tasks)" ] && n=$1 && shift || n=''
  while [ -n "$n" ] && [ $# -gt 0 ]; do case $1 in --solo) arms+=(solo); shift ;; --arm) [ $# -ge 2 ] && arms+=("$2") && shift 2 || n='' ;;
    --engine) [ $# -ge 2 ] && eng=$2 && named=1 && shift 2 || n='' ;;
    --settings) [ $# -ge 2 ] && [ -z "$set" ] && set=$2 && shift 2 || n='' ;; --again) SWE_AGAIN=1; shift ;;
    --task) [ $# -ge 2 ] && [ -z "$SWE_ONLY" ] && [[ $2 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && SWE_ONLY=$2 && shift 2 || n='' ;; *) n='' ;; esac; done
  [ -z "$SWE_ONLY" ] || [ "$n" = 1 ] || n=''
  [ ${#arms[@]} -gt 0 ] || arms=(conveyor)
  # --engine names the version of the run's conveyor arms: a run with none takes no --engine. An arm named twice runs once.
  if [ -n "$n" ] && [ -n "$named" ]; then
    k=''; for a in "${arms[@]}"; do [ "$(swe_arm "$a" | jq -r .kind)" = agent ] || k=1; done; [ -n "$k" ] || n=''
  fi
  [ -n "$n" ] || { echo "usage: conveyor.sh bench swe <1-$(swe_conf .tasks)> [--arm <arm>]... [--solo] [--engine <version | commit>] [--settings <json>] [--again] [--task <id>] | bench swe arms [check [--settings <json>] <arm>...] | bench swe arms save <name> <spec json> | bench swe arms show <id> | bench swe stop [<run id>] | bench swe runs archive|restore|delete <run>... | bench swe results [--json] | bench swe history | bench swe show <run> | bench swe diff <A> <B> [--json] | bench swe versions" >&2; return 2; }
  swe_settings "$set" || return
  mapfile -t arms < <(printf '%s\n' "${arms[@]}" | awk '!seen[$0]++')
  swe_run "$n" "$eng" "${arms[@]}"
}
. "${BASH_SOURCE[0]%/*}/swe_arms.sh"
