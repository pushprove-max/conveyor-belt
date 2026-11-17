# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh bench swe`: SWE-bench Verified tasks built through Conveyor and graded by the official harness.
# Sourced by commands/bench.sh after the engine files it uses (paths, records, slots, prompts, control, install).
#   bench swe <n> [--solo] [--engine <version | commit>]   runs the first n tasks of the pinned order (1 to 500)
#   bench swe stop                                         ends the run in progress
#   bench swe results [--json]                             the results of every engine run so far, side by side
#   bench swe diff <version A> <version B> [--json]        why two engine versions differ on the tasks both ran
#   bench swe versions                                     the engine versions a run can take: main and each release
# The task list: swe.json beside this file pins the dataset, its revision and a seed; the tasks are in the order of
# sha256("<seed>:<task id>"), so `swe 5` is always the first 5 of `swe 20`. The harness side (the task list, each
# task's Docker image, the grade) is swe_harness.py, run by the Python of the swebench virtualenv (SWE_VENV), else
# python3; CONVEYOR_BENCH_PYTHON names another (the tests' stub harness). Engine versions are taken from
# CONVEYOR_BENCH_SOURCE (default: this checkout's origin) and installed in the versions folder (install(),
# lib/install.sh): only the card building runs the old engine; the task setup, the grade and the results are always
# this harness's.
# Each task is built in a sandbox under the state folder's bench/swe/work: a bare origin holding the task's base
# commit (fetched from the task's repository, never pushed to), a clone of it as the main checkout with a pack made
# for it (the task's test command, no checks, no follow-ups), a gh on PATH that serves the issue text as issue #1 and
# writes nothing to GitHub, and a control record from the project's own (its seats, its cap and its guard; follow-ups
# and visible-change asks off, a push after each landing on, to the sandbox's own origin). The
# engine's loop builds that one card (`conveyor.sh run 1`) on the machine's test slots. The final patch is what
# landed on the sandbox's main; a blocked card's is empty. With --solo, one Claude session is given the issue in the
# sandbox (its gh, its files only, no shell: swe_solo()), with no review, fix or test step, and its change is the patch.
# What is kept, under the state folder's bench/swe: tasks.<revision>.jsonl (the ordered list), results/<key>/<task>.json
# (key: the engine commit, or solo-<model>; resolved, sessions, tokens, minutes, the card's records) and .patch, a
# line a run in runs.jsonl, the run in progress in live.json, and board.json, what the Board's Benchmarks part shows.
# The dataset's rows (each task's reference fix and hidden tests) are never kept: the card's sessions have a shell as
# this account, so the harness reads them into a cache of its own that it removes, for the task list and each grade.
# A result of the same key and task is reused, never run again. A task whose image cannot be fetched or built, or that
# the harness could not grade, is not run: no result is kept, and the run names it apart from the failed ones.
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
swe_conf() { jq -r "$1" "$SWE_CONF"; }
swe_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
swe_put() { printf '%s\n' "$2" > "$1.$$" && mv -f "$1.$$" "$1"; } # <file> <text>: written whole
# The pinned task list, made once a revision: the harness's list, put in the seed's order. The dataset's rows that an
# earlier harness kept beside it (raw.<revision>.jsonl, with the reference fixes and hidden tests) are removed first.
swe_tasks() {
  local rev f; rev=$(swe_conf .revision); f=$SWE_DIR/tasks.$rev.jsonl
  rm -f "$SWE_DIR"/raw.*.jsonl
  [ -s "$f" ] && { printf '%s\n' "$f"; return; }
  mkdir -p "$SWE_DIR" && swe_h tasks "$(swe_conf .dataset)" "$rev" "$SWE_DIR/raw.$rev" >&2 \
    || { echo "conveyor: the SWE-bench task list could not be read (the harness needs Python with the swebench package, in $SWE_VENV: docs/benchmarks.md)" >&2; return 1; }
  python3 -I -c 'import hashlib, json, sys
seed = sys.argv[1]
rows = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
rows.sort(key=lambda r: hashlib.sha256(("%s:%s" % (seed, r["id"])).encode()).hexdigest())
sys.stdout.write("".join(json.dumps(r) + "\n" for r in rows))' "$(swe_conf .seed)" "$SWE_DIR/raw.$rev" > "$f.$$" && [ -s "$f.$$" ] && mv -f "$f.$$" "$f" \
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
# project's mode: a paused or stopped project's guard still stands for a run of its own. A solo run's guard reads the
# one account its session runs on (swe_solo), the builder's, whatever agent and route the seats have: guardread reads
# none for a Codex or OpenCode builder or one on an API route, and the solo session is Claude on the subscription.
swe_guarded() { # [solo: any non-empty word]
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
# The sessions a task takes, usual (the mean of the arm's results so far, else build and review, or the one solo
# session) and worst case (the build, MAX_REVIEWS reviews, the fix rounds between them, the one fix of a failed test
# step and the review after it and, while the control record has the judge on, a judge session for each review), and
# its minutes.
swe_pertask() { # <arm>
  local w=$((2 * MAX_REVIEWS + 2)); ! judgeon > /dev/null || w=$((3 * MAX_REVIEWS + 3))
  cat "$SWE_DIR"/results/*/*.json 2>/dev/null | jq -sc --arg a "$1" --argjson w "$w" --argjson m "$(swe_conf ".minutes.$1")" \
    'map(select(.arm == $a)) as $r | {usual: (if $r == [] then (if $a == "solo" then 1 else 2 end) else ($r | map(.sessions) | add / length * 10 | round / 10) end),
      worst: (if $a == "solo" then 1 else $w end), minutes: (if $r == [] then $m else ($r | map(.minutes) | add / length | ceil) end)}'
}
# The model a solo run takes (the builder seat's, when it is Claude) and the key its results are kept under.
swe_solomodel() { seat builder 2>/dev/null | jq -r 'select(.agent == "claude") | .model // empty'; }
swe_solokey() { local k=solo-${1:-default}; printf '%s\n' "${k//[^A-Za-z0-9._-]/-}"; } # <model>
# board.json: the run in progress, the runs, each key's results by task with at (the places of those tasks in the
# pinned order, from 0, so the Board counts the tasks of the first n a run reuses), the key a solo run takes now
# (soloKey), the versions (the last read, SWE_VERSIONS) and the expected figures.
swe_board() {
  local vs; vs=$(jq -c '.versions // null' "$SWE_DIR/board.json" 2>/dev/null) || vs=null
  [ -z "${SWE_VERSIONS:-}" ] || vs=$SWE_VERSIONS
  mkdir -p "$SWE_DIR" || return 1
  swe_put "$SWE_DIR/board.json" "$(cat "$SWE_DIR"/results/*/*.json 2>/dev/null | jq -sc --slurpfile live <(jq -c . "$SWE_DIR/live.json" 2>/dev/null || echo null) \
    --slurpfile runs <(tail -n 50 "$SWE_DIR/runs.jsonl" 2>/dev/null | jq -sc .) --argjson vs "$vs" --argjson c "$(swe_pertask conveyor)" --argjson s "$(swe_pertask solo)" \
    --slurpfile order <(jq -c .id "$SWE_DIR/tasks.$(swe_conf .revision).jsonl" 2>/dev/null) --arg sk "$(swe_solokey "$(swe_solomodel)")" \
    --argjson presets "$(swe_conf .presets)" --argjson max "$(swe_conf .tasks)" '
    ($order | to_entries | map({key: .value, value: .key}) | from_entries) as $pos
    | {live: $live[0], runs: $runs[0], versions: $vs, presets: $presets, max: $max, perTask: {conveyor: $c, solo: $s}, soloKey: $sk,
     keys: (group_by(.key) | map({key: .[0].key, arm: .[0].arm, engine: .[0].engine, version: .[0].version, model: .[0].model,
       tasks: (map({key: .task, value: {resolved, sessions, tokens, minutes}}) | from_entries), at: (map($pos[.task] // empty) | sort)}))}')"
}
swe_live() { local l; l=$(jq -c "$@" "$SWE_DIR/live.json") && swe_put "$SWE_DIR/live.json" "$l" && swe_board; } # [jq options] <jq filter>
# The sandbox of one task: <sb>/origin, a bare repository holding the base commit as main, <sb>/swe-<project>, its clone, and
# <sb>/bin/gh, the sandbox's gh (swe_gh) serving the task's issue, for the engine's loop and the solo session alike.
swe_sandbox() { # <task json> <sb>
  local url base; url=$(jq -r .url <<<"$1"); base=$(jq -r .base <<<"$1")
  { [ ! -e "$2" ] || { chmod -R u+w "$2" && rm -rf "$2"; }; } && mkdir -p "$2/bin" && git init -q --bare -b main "$2/origin" \
    && git -C "$2/origin" fetch -q --depth 1 "$url" "$base" && git -C "$2/origin" update-ref refs/heads/main "$base" \
    && git clone -q "file://$2/origin" "$2/$SWE_MAIN" && printf '.conveyor/\nconveyor/\n' >> "$2/$SWE_MAIN/.git/info/exclude" \
    && printf '%s\n' "$base" > "$2/base" \
    && jq -c '{number: 1, title: "SWE-bench \(.id)", body: .issue, labels: [], milestone: null, createdAt: "2026-01-01T00:00:00Z", state: "OPEN"}' <<<"$1" > "$2/issue.json" \
    && swe_gh "$2"
}
# A command run as the sandbox's own Conveyor: its main checkout and cards folder, its gh, none of the card or loop
# variables of the environment this run was started in (a run inside a card would hand on that card's).
swe_env() { # <sb> <command...>
  env -u CARDCTL -u CONVEYOR_CARD_SETTINGS -u CONVEYOR_OPENCODE_GUARD -u CONVEYOR_CODEX_GUARD -u CONVEYOR_CARD_RULES -u CONVEYOR_CARD \
    -u CONVEYOR_FOREMAN -u CLAUDE_CODE_SESSION_ID -u CONVEYOR_FOREMAN_DIR -u CLAUDE_PROJECT_DIR -u CONVEYOR_ADOPT -u CONVEYOR_KIDS \
    CONVEYOR_MAIN="$1/$SWE_MAIN" CONVEYOR_CARDS="$1/cards" PATH="$1/bin:$PATH" "${@:2}"
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
# The final patch of a sandbox: what its main holds over the base commit.
swe_patch() { git -C "$1/$SWE_MAIN" diff --binary "$2" "${3:-refs/heads/main}" --; } # <sb> <base> [<what>]
# One task built by the engine in <eng> (its conveyor.sh). Prints the result's build part {sessions, tokens, minutes,
# steps}, the patch in <sb>/patch. A NO-GO review step keeps its tail (its findings): its reason is cut short.
swe_build() { # <task json> <sb> <eng>
  local sb=$2 sst t0 base; base=$(jq -r .base <<<"$1"); t0=$(date +%s)
  mkdir -p "$sb/$SWE_MAIN/.conveyor" "$sb/cards" && : > "$sb/rulings.jsonl" || return 1
  jq --arg t "$(jq -r .test <<<"$1")" --arg l "$sb/rulings.jsonl" '{owner, labels: ((.labels // {}) + {nonProductAreas: []}), models, review, prices, privacy,
    tunables: ((.tunables // {}) + {closeWait: 0}), rulings: {log: $l}, test: {command: $t, survey: false}, productPaths: [".conveyor-none/"], linkFromMain: [], checks: [],
    push: {env: {}}, remote: "origin", defaultBranch: "main", landBatch: 1} | with_entries(select(.value != null))' "$MAIN/.conveyor/project.json" > "$sb/$SWE_MAIN/.conveyor/project.json" \
    || { echo "the project's pack could not be read to make the task's pack"; return 1; }
  sst=$(swe_env "$sb" bash "$3" state-dir 2>/dev/null) && [ -n "$sst" ] || sst=$sb/$SWE_MAIN/conveyor/state
  [ "$(cd "$sst" 2>/dev/null && pwd -P)" != "$(cd "$ST" && pwd -P)" ] || { echo "the host file gives the sandbox the project's own state folder"; return 1; }
  mkdir -p "$sst" && ctl | jq '.mode = "run" | .held = [] | .order = [] | .startHeld = [] | .start = "queue" | .rules.followups = false | .rules.visible = false | .rules.push = true' > "$sst/control.json" \
    || { echo "the project's control record could not be read"; return 1; }
  swe_env "$sb" timeout "$(swe_conf .taskTimeout)" bash "$3" run 1 > "$sb/loop.log" 2>&1 < /dev/null
  swe_patch "$sb" "$base" > "$sb/patch" || return 1
  jq -sc --argjson m "$(( $(date +%s) - t0 ))" 'map(select(.issue == 1 and (.step | IN("start", "picked", "worktree", "deps", "brief") | not))) as $s
    | {sessions: ($s | map(select(.step | IN("build", "review", "fix", "rebase"))) | length) + ($s | map(select(.judge | type == "object")) | length),
       tokens: ($s | map((.tokens.claude // 0) + (.tokens.codex // 0) + (.judge.tokens.claude // 0) + (.judge.tokens.codex // 0)) | add // 0),
       minutes: ($m / 6 | round / 10), steps: ($s | map({step, result, reason, time, tokens} + if .step == "review" and .result != "GO" and has("tail") then {tail} else {} end))}' "$sst/cards.jsonl" 2>/dev/null \
    || jq -nc --argjson m "$(( $(date +%s) - t0 ))" '{sessions: 0, tokens: 0, minutes: ($m / 6 | round / 10), steps: []}'
}
# One task given to Claude alone: one session on the issue in the sandbox's main, its change the patch. The session
# has the sandbox's gh and no other way out: no shell and no web tools, its file tools only, edits only in the
# sandbox's main and, in dontAsk mode, no read outside it (the task lists and the results are denied by name as well);
# no settings file or MCP server of the host is read. It runs on the builder's account (`control account`), the one
# the usage guard reads (swe_guarded), never on an inherited login.
swe_solo() { # <task json> <sb> <model>
  local sb=$2 t0 base acct; base=$(jq -r .base <<<"$1"); t0=$(date +%s)
  ctlread 2>/dev/null || { echo "the control record could not be read"; return 1; }
  acct=$(acctenv "$(ctlacct "$CTL_V")") || { echo "$acct"; return 1; }
  { printf 'Fix this issue in the repository in the current folder. Change the code only; do not commit.\n\n'; jq -r .issue <<<"$1"; } > "$sb/prompt"
  (cd "$sb/$SWE_MAIN" && acctrun "$acct" && swe_env "$sb" timeout "$(swe_conf .taskTimeout)" claude -p --output-format json --permission-mode dontAsk ${3:+--model "$3"} \
    --setting-sources "" --strict-mcp-config --tools Read,Grep,Glob,Edit,Write --allowedTools "Edit(/$sb/$SWE_MAIN/**)" \
    --disallowedTools "Read(/$SWE_DIR/raw.*)" "Read(/$SWE_DIR/tasks.*)" "Read(/$SWE_DIR/results/**)" < "$sb/prompt" > "$sb/solo.json" 2> "$sb/solo.err")
  git -C "$sb/$SWE_MAIN" add -A && swe_patch "$sb" "$base" --cached > "$sb/patch" || return 1
  jq -sc --argjson m "$(( $(date +%s) - t0 ))" 'map(select(.type == "result")) | last // {} | .usage // {} as $u
    | {sessions: 1, tokens: (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.output_tokens // 0)), minutes: ($m / 6 | round / 10), steps: []}' "$sb/solo.json" 2>/dev/null \
    || jq -nc --argjson m "$(( $(date +%s) - t0 ))" '{sessions: 1, tokens: 0, minutes: ($m / 6 | round / 10), steps: []}'
}
# One task: fetched image, sandbox, build, grade. Writes results/<key>/<task>.json and .patch and prints "resolved",
# "unresolved", or "not run: <why>".
swe_task() { # <task json> <arm> <key> <eng or model>
  local id sb b g rc out=$SWE_DIR/results/$3; id=$(jq -r .id <<<"$1"); sb=$SWE_DIR/work/$id
  swe_h image "$(jq -r .image <<<"$1")" > /dev/null 2>&1 || { echo "not run: its Docker image could not be fetched or built"; return; }
  mkdir -p "$SWE_DIR/work" && swe_sandbox "$1" "$sb" 2> "$SWE_DIR/work/$id.err" \
    || { echo "not run: its repository could not be fetched at the base commit: $(head -c 300 "$SWE_DIR/work/$id.err")"; return; }
  if [ "$2" = solo ]; then b=$(swe_solo "$1" "$sb" "$4"); else b=$(swe_build "$1" "$sb" "$4"); fi \
    && [ -n "$b" ] && jq -e . <<<"$b" > /dev/null 2>&1 || { echo "not run: ${b:-the patch of the sandbox could not be read}"; return; }
  # An engine that built no card (its pack refused, its loop failed) says nothing of the task.
  [ "$2" = solo ] || jq -e '.steps | any(.step == "build")' <<<"$b" > /dev/null \
    || { echo "not run: the engine built no card: $(tail -n 3 "$sb/loop.log" 2>/dev/null | tr '\n' ' ' | head -c 400)"; return; }
  if [ ! -s "$sb/patch" ]; then g='{"resolved":false}'
  else g=$(swe_h grade "$(swe_conf .dataset)" "$(swe_conf .revision)" "$id" "$sb/patch" "$sb/grade" 2>/dev/null); rc=$?
    [ "$rc" = 0 ] && jq -e '.resolved | type == "boolean"' <<<"$g" > /dev/null 2>&1 || {
      if [ "$rc" = 3 ]; then echo "not run: the harness could not fetch or build its image"; else echo "not run: the harness could not grade it (exit $rc)"; fi; return; }
  fi
  mkdir -p "$out" && cp "$sb/patch" "$out/$id.patch" && { [ ! -e "$sb/loop.log" ] || cp "$sb/loop.log" "$out/$id.log"; } && swe_put "$out/$id.json" "$(jq -c --arg t "$id" --arg a "$2" --arg k "$3" --arg e "${SWE_COMMIT:-}" --arg v "${SWE_VERSION:-}" \
    --arg m "${SWE_MODEL:-}" --argjson g "$g" --arg at "$(swe_now)" '{task: $t, arm: $a, key: $k, engine: (if $e == "" then null else $e end), version: (if $v == "" then null else $v end),
    model: (if $m == "" then null else $m end), resolved: $g.resolved, at: $at} + .' <<<"$b")" || { echo "not run: its result could not be kept"; return; }
  chmod -R u+w "$sb" 2>/dev/null; rm -rf "$sb"
  if jq -e .resolved <<<"$g" > /dev/null; then echo resolved; else echo unresolved; fi
}
# The run's end: its line in runs.jsonl, live.json's state, the sandboxes gone.
swe_end() { # <state>
  [ -n "${SWE_RUN:-}" ] || return 0
  local l; l=$(jq -c --arg s "$1" --arg at "$(swe_now)" '.state = $s | .ended = $at | .current = null | del(.pid)' "$SWE_DIR/live.json") && swe_put "$SWE_DIR/live.json" "$l" \
    && printf '%s\n' "$l" >> "$SWE_DIR/runs.jsonl"
  [ ! -d "$SWE_DIR/work" ] || { chmod -R u+w "$SWE_DIR/work"; rm -rf "$SWE_DIR/work"; }
  rm -f "$SWE_DIR/stop"; swe_board; SWE_RUN=
}
swe_run() { # <n> <solo or ""> <engine>
  local n=$1 arm=conveyor key eng='' tf all i t id r reused=0 pt v
  [ -z "$2" ] || arm=solo
  mkdir -p "$SWE_DIR" && exec 7>>"$SWE_DIR/run.lock" && flock -n 7 || { echo "conveyor: a SWE-bench run is already going; \`conveyor.sh bench swe stop\` ends it" >&2; return 1; }
  ! swe_guarded "$2" || { echo "conveyor: the usage guard is reached: no SWE-bench run starts while it stands" >&2; return 1; }
  tf=$(swe_tasks) || return 1; all=$(wc -l < "$tf")
  [ "$n" -le "$all" ] || { echo "conveyor: the task list holds $all tasks: n is 1 to $all" >&2; return 2; }
  SWE_COMMIT=''; SWE_VERSION=''; SWE_MODEL=''
  if [ "$arm" = solo ]; then
    SWE_MODEL=$(swe_solomodel); key=$(swe_solokey "$SWE_MODEL")
  else
    swe_resolve "$3" || return 1; key=$SWE_COMMIT
    { installed "$SWE_COMMIT" || install "$SWE_COMMIT" "$(swe_src)" > /dev/null; } || { echo "conveyor: engine $3 ($SWE_COMMIT) could not be installed" >&2; return 1; }
    eng=$VERSIONS/$SWE_COMMIT/conveyor/conveyor.sh
  fi
  while IFS= read -r id; do [ ! -s "$SWE_DIR/results/$key/$id.json" ] || reused=$((reused + 1)); done < <(head -n "$n" "$tf" | jq -r .id)
  pt=$(swe_pertask "$arm"); v=${SWE_VERSION:-${SWE_COMMIT:0:12}}
  jq -r --argjson n "$n" --argjson r "$reused" --arg v "${v:-Claude alone${SWE_MODEL:+ on $SWE_MODEL}}" '($n - $r) as $k
    | "SWE-bench Verified: \($n) task\(if $n > 1 then "s" else "" end) with \($v); \($r) already run and reused, \($k) to run."
    , "Expected: about \($k * .usual | ceil) sessions (worst case \($k * .worst)) and \($k * .minutes) minutes."' <<<"$pt"
  SWE_RUN=r$(date -u +%Y%m%dT%H%M%S)-$$; rm -f "$SWE_DIR/stop"
  swe_put "$SWE_DIR/live.json" "$(jq -nc --arg id "$SWE_RUN" --argjson pid "$$" --arg a "$arm" --arg k "$key" --arg e "$SWE_COMMIT" --arg v "$SWE_VERSION" \
    --arg m "$SWE_MODEL" --argjson n "$n" --arg at "$(swe_now)" '{id: $id, pid: $pid, arm: $a, key: $k, engine: (if $e == "" then null else $e end),
    version: (if $v == "" then null else $v end), model: (if $m == "" then null else $m end), n: $n, done: 0, resolved: 0, current: null, started: $at, state: "running", tasks: []}')"
  swe_board
  trap 'pkill -TERM -P $$ 2>/dev/null; swe_end stopped; exit 143' TERM INT
  for ((i = 1; i <= n; i++)); do
    t=$(sed -n "${i}p" "$tf"); id=$(jq -r .id <<<"$t")
    [ ! -e "$SWE_DIR/stop" ] || { swe_end stopped; return 0; }
    if [ -s "$SWE_DIR/results/$key/$id.json" ]; then
      r=$(jq -r 'if .resolved then "resolved" else "unresolved" end' "$SWE_DIR/results/$key/$id.json"); echo "$i/$n $id: $r (reused)"
      swe_live --arg t "$id" --arg r "$r" '.tasks += [{id: $t, result: $r, reused: true}] | .done += 1 | .resolved += (if $r == "resolved" then 1 else 0 end)'
      continue
    fi
    ! swe_guarded "$2" || { echo "conveyor: the usage guard is reached: the run stops before $id"; swe_end guard; return 0; }
    swe_live --arg t "$id" '.current = $t'
    r=$(swe_task "$t" "$arm" "$key" "${eng:-$SWE_MODEL}"); echo "$i/$n $id: $r"
    swe_live --arg t "$id" --arg r "$r" '.tasks += [{id: $t, result: $r, reused: false}] | .done += 1 | .current = null | .resolved += (if $r == "resolved" then 1 else 0 end)'
  done
  jq -r '"Resolved \(.resolved) of \(.n)\(if .engine then " with engine \(.version // .engine[0:12]) (\(.engine))" else " with Claude alone" end); not run: \([.tasks[] | select(.result | startswith("not run"))] | length)."' "$SWE_DIR/live.json"
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
  local j; j=$(cat "$SWE_DIR"/results/*/*.json 2>/dev/null | jq -sc 'group_by(.key) | map({key: .[0].key, arm: .[0].arm, engine: .[0].engine, version: .[0].version, model: .[0].model,
    n: length, resolved: (map(select(.resolved)) | length), sessions: (map(.sessions) | add), tokens: (map(.tokens) | add), minutes: (map(.minutes) | add * 10 | round / 10),
    tasks: map({task, resolved, sessions, tokens, minutes})}) | sort_by(.version // "")')
  [ "${1:-}" != --json ] || { printf '%s\n' "$j"; return; }
  [ "$j" != '[]' ] || { echo "No SWE-bench results yet."; return; }
  jq -r '.[] | "\(if .arm == "solo" then "Claude alone (\(.model // "default"))" else "\(.version // "commit") \(.engine[0:12])" end): \(.resolved) of \(.n) resolved, \(.sessions) sessions, \(.tokens) tokens, \(.minutes) minutes"' <<<"$j"
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
swe_diff() { # <A> <B> [--json]
  local ca cb va vb d da db ids id fa fb st sm files=() flips='[]' ch why n e
  swe_resolve "$1" || return 1; ca=$SWE_COMMIT; va=$SWE_VERSION; swe_resolve "$2" || return 1; cb=$SWE_COMMIT; vb=$SWE_VERSION
  da=$SWE_DIR/results/$ca; db=$SWE_DIR/results/$cb
  ids=$(comm -12 <(cd "$da" 2>/dev/null && ls -- *.json 2>/dev/null | sort) <(cd "$db" 2>/dev/null && ls -- *.json 2>/dev/null | sort) | sed 's/\.json$//')
  [ -n "$ids" ] || { echo "conveyor: $1 and $2 have no task in common to compare" >&2; return 1; }
  { installed "$cb" || install "$cb" "$(swe_src)" > /dev/null; } && e=$VERSIONS/$cb || { echo "conveyor: engine $2 could not be installed to read its stages" >&2; return 1; }
  d=$SWE_DIR/diff/$ca-$cb; mkdir -p "$d"
  while IFS= read -r id; do
    fa=$(cat "$da/$id.json"); fb=$(cat "$db/$id.json")
    [ "$(jq -n --argjson a "$fa" --argjson b "$fb" '$a.resolved == $b.resolved')" = false ] || continue
    st=$(jq -rn --argjson a "$fa" --argjson b "$fb" "$SWE_STAGE"' apart($a.steps; $b.steps) // "build"')
    # The files of that stage in B's engine (stagemap.sh); null changes when its map cannot be made.
    ch=null; sm=$(bash "$HERE/bench/stagemap.sh" "$e/conveyor" 2>/dev/null) && ch='[]' \
      && mapfile -t files < <(awk -F '\t' -v s="$st" '("," $2 ",") ~ ("," s ",") { print "conveyor/" $1 }' <<<"$sm")
    [ "$ch" = null ] || [ ${#files[@]} = 0 ] || ch=$(git -C "$e" log --format='%h%x09%s' "$ca...$cb" -- "${files[@]}" 2>/dev/null | jq -Rsc 'split("\n") | map(select(. != "") | split("\t") | {commit: .[0], title: .[1]})')
    n=$(jq -nc --arg t "$id" --arg s "$st" --argjson a "$fa" --argjson b "$fb" --argjson ch "$ch" --arg va "${va:-${ca:0:12}}" --arg vb "${vb:-${cb:0:12}}" "$SWE_STAGE"'
      {task: $t, apart: $s, a: ($a | facts), b: ($b | facts), changes: $ch, versions: [$va, $vb]}')
    if [ -s "$d/$id.txt" ]; then why=$(cat "$d/$id.txt")
    else
      why=$({ printf 'Two versions of an engine that builds code changes ran one SWE-bench task; one resolved it and one did not. From these facts only, say in two or three plain sentences why the runs most likely went apart. Do not guess beyond the facts.\n\n'
        printf '%s\n' "$n"; } | timeout 300 claude -p 2>/dev/null) && [ -n "$why" ] && printf '%s\n' "$why" > "$d/$id.txt" || why=''
    fi
    flips=$(jq -c --argjson n "$n" --arg w "$why" '. + [$n + {reading: (if $w == "" then null else $w end)}]' <<<"$flips")
  done <<<"$ids"
  local j; j=$(jq -n --argjson f "$flips" --arg va "${va:-${ca:0:12}}" --arg vb "${vb:-${cb:0:12}}" --arg ca "$ca" --arg cb "$cb" --arg noise "$(swe_noise "$(wc -l <<<"$ids")")" \
    --slurpfile ra <(for id in $ids; do cat "$da/$id.json"; done) --slurpfile rb <(for id in $ids; do cat "$db/$id.json"; done) "$SWE_NOISED"'
    def tot: {resolved: (map(select(.resolved)) | length), sessions: (map(.sessions) | add), tokens: (map(.tokens) | add), minutes: (map(.minutes) | add * 10 | round / 10)};
    ($ra | length) as $n | ($ra | tot) as $ta | ($rb | tot) as $tb | noised($n) as $dd
    | {a: {version: $va, commit: $ca, totals: $ta}, b: {version: $vb, commit: $cb, totals: $tb}, tasks: $n,
       same: [$ra[] | .task] - [$f[] | .task], flipped: $f, noise: $noise, withinNoise: ((($ta.resolved - $tb.resolved) | fabs) < $dd)}')
  [ "${3:-}" != --json ] || { printf '%s\n' "$j"; return; }
  jq -r '"\(.a.version) against \(.b.version) on the \(.tasks) tasks both ran:",
    "  \(.a.version): \(.a.totals.resolved) resolved, \(.a.totals.sessions) sessions, \(.a.totals.tokens) tokens, \(.a.totals.minutes) minutes",
    "  \(.b.version): \(.b.totals.resolved) resolved, \(.b.totals.sessions) sessions, \(.b.totals.tokens) tokens, \(.b.totals.minutes) minutes",
    "  \(.noise)\(if .withinNoise then "; this difference is within the noise" else "; this difference is past the noise" end).",
    "  The same in both: \(.same | length) task(s)\(if .same == [] then "" else ": \(.same | join(", "))" end). Flipped: \(.flipped | length).",
    (.flipped[] | "", "\(.task): \(if .a.resolved then "resolved by \(.versions[0]) only" else "resolved by \(.versions[1]) only" end); the runs went apart at: \(.apart)",
      "  \(.versions[0]): sessions \(.a.sessions), tokens \(.a.tokens), minutes \(.a.minutes), fix rounds \(.a.fixRounds), test \(.a.test // "none"), blocked \(.a.blocked // "no")\(if .a.findings != [] then ", findings: \(.a.findings | join(" | "))" else "" end)",
      "  \(.versions[1]): sessions \(.b.sessions), tokens \(.b.tokens), minutes \(.b.minutes), fix rounds \(.b.fixRounds), test \(.b.test // "none"), blocked \(.b.blocked // "no")\(if .b.findings != [] then ", findings: \(.b.findings | join(" | "))" else "" end)",
      "  Engine changes to the \(.apart) stage between them: \(if .changes == null then "unknown (the stage map could not be made)" elif .changes == [] then "none" else (.changes | map("\(.commit) \(.title)") | join("; ")) end)",
      "  The model'"'"'s reading (from the facts above only): \(.reading // "none: the model call failed")")' <<<"$j"
}
swe_main() {
  local n='' solo='' eng=main named=''
  case ${1:-} in
    stop) [ $# = 1 ] && { swe_stop; return; } ;;
    results) [ $# = 1 ] || [ "$*" = 'results --json' ] && { swe_results "${2:-}"; return; } ;;
    versions) [ $# = 1 ] && { SWE_VERSIONS=$(swe_versions) && swe_board && printf '%s\n' "$SWE_VERSIONS"; return; } ;;
    diff) { [ $# = 3 ] || { [ $# = 4 ] && [ "$4" = --json ]; }; } && { swe_diff "$2" "$3" "${4:-}"; return; } ;;
  esac
  [[ ${1:-} =~ ^[1-9][0-9]{0,2}$ ]] && [ "$1" -le "$(swe_conf .tasks)" ] && n=$1 && shift || n=''
  while [ -n "$n" ] && [ $# -gt 0 ]; do case $1 in --solo) solo=1; shift ;; --engine) [ $# -ge 2 ] && eng=$2 && named=1 && shift 2 || n='' ;; *) n='' ;; esac; done
  [ -n "$n" ] && { [ -z "$solo" ] || [ -z "$named" ]; } || { echo "usage: conveyor.sh bench swe <1-$(swe_conf .tasks)> [--solo | --engine <version | commit>] | bench swe stop | bench swe results [--json] | bench swe diff <version> <version> [--json] | bench swe versions" >&2; return 2; }
  swe_run "$n" "$solo" "$eng"
}
