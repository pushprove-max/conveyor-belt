# SPDX-License-Identifier: Apache-2.0
# The arms of `conveyor.sh bench swe` (bench/swe.sh, which sources this file). An arm is one way of building a task:
# one JSON file under bench/arms/ (CONVEYOR_BENCH_ARMS names another folder: the tests' stub arms), its name the
# file's. Its fields:
#   label      what the results call the arm
#   kind       "conveyor": the engine's loop builds the task's card (`conveyor.sh run 1`) on the project's seats with
#              the arm's seats over them; "agent": the arm's own run command builds it
#   seats      (conveyor) the control record's model, reviewer and judge the arm sets, as the control record holds them
#   login      the subscription logins the arm uses: "claude" (the builder's account, `control account`), "codex"
#   install    shell run first in the task's container, as the bench user (HOME /bench, ~/.local/bin on PATH)
#   preflight  shell run in the container after install: exit 0 when the arm's tools are in place and signed in
#   run        (agent) shell that builds the task headless in the task's checkout: $SWE_PROMPT is the file of the
#              issue, $SWE_MODEL the model; what it prints is the trial's output
#   fired      (agent) jq over the output's JSON lines, as one array: true when the arm's method ran
#   tokens     (agent) jq over the same array: the tokens the trial took
#   sessions   (agent) the sessions a trial takes
#   model      (agent) the model given as $SWE_MODEL; "builder": the builder seat's Claude model, as Claude alone takes
#   exclude    paths the arm's method writes in the checkout that are not the change: kept out of the patch
#   offered    false for an arm that cannot run here, with why
# Every trial runs in a container of its own (swe_box): the task's image, the same limits for every arm (swe.json's
# limits and taskTimeout), the logins copied in at its start only, and the container removed when the trial ends.
SWE_ARMS=${CONVEYOR_BENCH_ARMS:-${BASH_SOURCE[0]%/*}/arms}
SWE_HOME=/bench
swe_arm() { # <name>: the arm's JSON, its keys sorted (a preflight's record is compared with it whole)
  local j; [[ $1 =~ ^[a-z0-9][a-z0-9-]*$ ]] && j=$(jq -cSe 'objects' "$SWE_ARMS/$1.json" 2>/dev/null) && jq -cS --arg n "$1" '.name = $n' <<<"$j"
}
swe_armnames() { local f; for f in "$SWE_ARMS"/*.json; do [ -e "$f" ] || continue; f=${f##*/}; printf '%s\n' "${f%.json}"; done; }
# The key an arm's results are kept under: the engine commit for the conveyor arm (as before arms), <arm>-<commit> for
# another conveyor arm, <arm>-<model> for an arm on the builder's model (solo-<model> for Claude alone), else <arm>.
swe_armkey() { # <arm json> <engine commit, conveyor kind> <model>
  local n k; n=$(jq -r .name <<<"$1")
  if [ "$(jq -r .kind <<<"$1")" = conveyor ]; then [ "$n" = conveyor ] && k=$2 || k=$n-$2
  elif [ "$(jq -r '.model // ""' <<<"$1")" = builder ]; then k=$n-${3:-default}
  else k=$n; fi
  printf '%s\n' "${k//[^A-Za-z0-9._-]/-}"
}
# The host's credential file of a login, the one copied into a container, and its place in the container's home.
swe_login() { # <claude | codex>
  local d
  case $1 in
    claude) ctlread 2>/dev/null && d=$(acctenv "$(ctlacct "$CTL_V")") || return 1; printf '%s\n' "${d:-$HOME/.claude}/.credentials.json" ;;
    codex) printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/auth.json" ;;
    *) return 1 ;;
  esac
}
swe_logindest() { case $1 in claude) echo .claude/.credentials.json ;; codex) echo .codex/auth.json ;; esac; }
# A trial's container: the task's image; the sandbox mounted at its own path (and, for a conveyor arm, the engine's
# version folder, read-only) and nothing else of the host; swe.json's CPU and memory limits; run as this user (a
# passwd line names it) with a home that is in the container only. The logins are copied into that home before the
# container starts: they are in this one container, gone when it is removed, and never in an image. The home's
# .gitconfig gives git an identity: the task's image has none, and the engine cannot commit a fix without one.
swe_box() { # <container> <image> <sb> <logins, space-separated> [<engine folder>]
  local h l f m=() rc=0
  [ -z "${5:-}" ] || m=(-v "$5:$5:ro")
  docker create --name "$1" --user "$(id -u):$(id -g)" -e "HOME=$SWE_HOME" --cpus "$(swe_conf .limits.cpus)" --memory "$(swe_conf .limits.memory)" \
    -v "$3:$3" "${m[@]}" --entrypoint sleep "$2" infinity > /dev/null || return 1
  h=$(mktemp -d) || return 1
  mkdir -p "$h/home/.claude" "$h/home/.codex" "$h/home/.local/bin" && chmod 700 "$h/home" \
    && printf '[user]\n\tname = Conveyor bench\n\temail = bench@example.com\n' > "$h/home/.gitconfig" || rc=1
  for l in $4; do [ "$rc" = 0 ] && f=$(swe_login "$l") && cp "$f" "$h/home/$(swe_logindest "$l")" || rc=1; done
  [ "$rc" = 0 ] && docker cp -a "$h/home/." "$1:$SWE_HOME" > /dev/null || rc=1
  rm -rf "$h"; [ "$rc" = 0 ] || return 1
  docker start "$1" > /dev/null && docker exec -u 0 "$1" sh -c "echo 'bench:x:$(id -u):$(id -g)::$SWE_HOME:/bin/bash' >> /etc/passwd"
}
# A script in a trial's container, as the bench user, in a folder, under a time limit.
swe_in() { # <seconds> <container> <folder> <script> [<NAME=value> ...]
  local t=$1 c=$2 w=$3 s=$4 e=() x; shift 4
  for x in "$@"; do e+=(-e "$x"); done
  timeout "$t" docker exec -i -w "$w" "${e[@]}" "$c" bash -c 'export PATH="$HOME/.local/bin:${SWE_SB:+$SWE_SB/bin:}$PATH"; '"$s"
}
# The pack and control record of a conveyor arm's sandbox: the project's, with the task's test command run in the
# container, the arm's seats (and their models allowed), and no named account: the container has one login of each.
swe_pack() { # <task json> <sb> <engine's conveyor.sh> <arm json>
  local sb=$2 s; s=$(jq -c '.seats // {}' <<<"$4")
  mkdir -p "$sb/$SWE_MAIN/.conveyor" "$sb/cards" && : > "$sb/rulings.jsonl" || return 1
  jq --arg t "$(jq -r .cmd <<<"$1")" --arg l "$sb/rulings.jsonl" --argjson s "$s" '{owner, labels: ((.labels // {}) + {nonProductAreas: []}), models, review, prices, privacy,
    tunables: ((.tunables // {}) + {closeWait: 0}), rulings: {log: $l}, test: {command: $t, survey: false}, productPaths: [".conveyor-none/"], linkFromMain: [], checks: [],
    push: {env: {}}, remote: "origin", defaultBranch: "main", landBatch: 1} | with_entries(select(.value != null))
    | reduce ($s[] | objects | select(.cli != null)) as $x (.; .models.allowed[$x.cli] = ((.models.allowed[$x.cli] // []) + [$x.model] | unique))' \
    "$MAIN/.conveyor/project.json" > "$sb/$SWE_MAIN/.conveyor/project.json" || { echo "the project's pack could not be read to make the task's pack"; return 1; }
  # The container holds no host file, so the engine there keeps its state in the checkout's own conveyor/state.
  SWE_SST=$sb/$SWE_MAIN/conveyor/state
  mkdir -p "$SWE_SST" && ctl | jq --argjson s "$s" '.mode = "run" | .held = [] | .order = [] | .startHeld = [] | .start = "queue" | .rules.followups = false | .rules.visible = false
    | .rules.push = true | del(.account, .reviewAccount) + $s' > "$SWE_SST/control.json" || { echo "the project's control record could not be read"; return 1; }
}
SWE_ASK='Fix this issue in the repository in the current folder. Change the code only; do not commit.'
# One trial: the arm builds the task in its container. Prints {sessions, tokens, minutes, steps, fired, why}; keeps
# the patch (and a conveyor arm's loop log) in <sb>.h, the trial's own folder on the host, outside the container's
# mount; fails (prints why) only when the container could not be made or the patch read, which says nothing of the
# arm. An arm that does not fire (its install, preflight or command failed, or its output shows no use of its method)
# has fired false and why: that is the arm's failure, never a task not run.
swe_trial() { # <task json> <sb> <arm json> <engine's conveyor.sh, conveyor kind>
  local sb=$2 a=$3 h=$2.h base t0 c rc run why='' kind eng='' to b n p=0
  base=$(jq -r .base <<<"$1"); t0=$(date +%s); kind=$(jq -r .kind <<<"$a"); to=$(swe_conf .taskTimeout)
  n=conveyor-swe-${SWE_RUN:-check}-$(jq -r .name <<<"$a")-$(jq -r .id <<<"$1"); c=${n//[^A-Za-z0-9_.-]/-}
  { chmod -R u+w "$h"; rm -rf "$h"; } 2>/dev/null; mkdir -m 700 "$h" && : > "$h/out" || return 1
  { printf '%s\n\n' "$SWE_ASK"; jq -r .issue <<<"$1"; } > "$sb/prompt" && jq -r '.exclude // [] | .[]' <<<"$a" >> "$sb/$SWE_MAIN/.git/info/exclude" || return 1
  if [ "$kind" = conveyor ]; then
    swe_pack "$1" "$sb" "$4" "$a" > "$h/pack.err" || { cat "$h/pack.err"; return 1; }
    eng=${4%/conveyor/conveyor.sh}
    run="CONVEYOR_MAIN=$(printf %q "$sb/$SWE_MAIN") CONVEYOR_CARDS=$(printf %q "$sb/cards") bash $(printf %q "$4") run 1 > $(printf %q "$sb/loop.log") 2>&1"
  else run=$(jq -r .run <<<"$a"); fi
  printf '%s\n' "$c" > "$h/box"; docker rm -f "$c" > /dev/null 2>&1
  swe_box "$c" "$(jq -r .image <<<"$1")" "$sb" "$(jq -r '.login // [] | join(" ")' <<<"$a")" "$eng" > "$h/box.err" 2>&1 \
    || { docker rm -f "$c" > /dev/null 2>&1; echo "its container could not be made: $(cliwords "$(cat "$h/box.err")" | tail -n 2 | paste -sd ' ' -)"; return 1; }
  if ! swe_in "$to" "$c" "$sb/$SWE_MAIN" "$(jq -r '.install // "true"' <<<"$a")" "SWE_SB=$sb" < /dev/null > "$h/install.log" 2>&1; then
    why="its install failed: $(cliwords "$(tail -n 20 "$h/install.log")" | tail -n 2 | paste -sd ' ' -)"
  elif ! swe_in 600 "$c" "$sb/$SWE_MAIN" "$(jq -r '.preflight // "true"' <<<"$a")" "SWE_SB=$sb" < /dev/null > "$h/install.log" 2>&1; then
    why="its preflight command failed: $(cliwords "$(tail -n 20 "$h/install.log")" | tail -n 2 | paste -sd ' ' -)"
  else
    swe_in "$to" "$c" "$sb/$SWE_MAIN" "$run" "SWE_SB=$sb" "SWE_PROMPT=$sb/prompt" "SWE_MODEL=${SWE_MODEL:-}" < /dev/null > "$h/out" 2> "$h/err"; rc=$?
    # A command stopped at the task's time limit is the arm's own result: its patch is graded.
    [ "$rc" = 0 ] || [ "$rc" = 124 ] || why="its command failed (exit $rc): $(cliwords "$(tail -n 20 "$h/err" 2>/dev/null; jq -rRn "$NOSTARTSAID" "$h/out" 2>/dev/null)" | tail -n 3 | paste -sd ' ' -)"
  fi
  # What the arm left in the sandbox is read in its container, never by the host: the arm could write every file
  # there, so a host read or write could follow its symlink to a host file, and the checkout's .git/config could make
  # the host's git run the arm's code (a clean filter, an external diff).
  swe_in 600 "$c" "$sb/$SWE_MAIN" 'if [ "$SWE_KIND" = conveyor ]; then git diff --binary --no-ext-diff --no-textconv "$SWE_BASE" refs/heads/main --
    else git add -A && git diff --binary --no-ext-diff --no-textconv --cached "$SWE_BASE" --; fi' "SWE_SB=$sb" "SWE_BASE=$base" "SWE_KIND=$kind" < /dev/null > "$h/patch" 2> /dev/null || p=1
  if [ "$kind" = conveyor ]; then
    swe_in 600 "$c" "$sb" 'cat "$SWE_SB/loop.log"' "SWE_SB=$sb" < /dev/null > "$h/loop.log" 2> /dev/null || rm -f "$h/loop.log"
    swe_in 600 "$c" "$sb" 'cat "$SWE_SST/cards.jsonl"' "SWE_SST=$SWE_SST" < /dev/null > "$h/cards.jsonl" 2> /dev/null
  fi
  docker rm -f "$c" > /dev/null 2>&1; rm -f "$h/box"
  [ "$p" = 0 ] || return 1
  local secs=$(( $(date +%s) - t0 ))
  if [ "$kind" = conveyor ]; then
    b=$(jq -sc --argjson m "$secs" 'map(select(.issue == 1 and (.step | IN("start", "picked", "worktree", "deps", "brief") | not))) as $s
      | {sessions: ($s | map(select(.step | IN("build", "review", "fix", "rebase"))) | length) + ($s | map(select(.judge | type == "object")) | length),
         tokens: ($s | map((.tokens.claude // 0) + (.tokens.codex // 0) + (.judge.tokens.claude // 0) + (.judge.tokens.codex // 0)) | add // 0),
         minutes: ($m / 6 | round / 10), steps: ($s | map({step, result, reason, time, tokens} + if .step == "review" and .result != "GO" and has("tail") then {tail} else {} end))}' "$h/cards.jsonl" 2>/dev/null) \
      || b=$(jq -nc --argjson m "$secs" '{sessions: 0, tokens: 0, minutes: ($m / 6 | round / 10), steps: []}')
    # An engine that built no card (its pack refused, its loop failed) did not fire.
    [ -n "$why" ] || jq -e '.steps | any(.step == "build")' <<<"$b" > /dev/null \
      || why="the engine built no card: $(cliwords "$(tail -n 3 "$h/loop.log" 2>/dev/null)" | paste -sd ' ' - | head -c 400)"
  else
    # The output file is there (empty) when its install or preflight failed: the trial then failed with that why.
    b=$(jq -Rsc --argjson m "$secs" --argjson n "$(jq '.sessions // 1' <<<"$a")" "def fired: $(jq -r '.fired // "true"' <<<"$a"); def tok: $(jq -r '.tokens // "0"' <<<"$a");
      [splits(\"\\n\") | fromjson? | objects] as \$o | {sessions: \$n, tokens: ((\$o | tok) // 0), minutes: (\$m / 6 | round / 10), steps: [], fired: ((\$o | fired) == true)}" "$h/out") \
      || { echo "the arm's fired or tokens filter is not valid jq"; return 1; }
    [ -n "$why" ] || jq -e .fired <<<"$b" > /dev/null || why="it did not fire: its output shows no use of its method"
  fi
  jq -c --arg w "$why" '. + {fired: ($w == ""), why: (if $w == "" then null else $w end)}' <<<"$b"
}
# The trivial task of a preflight, as a task's JSON: a repository whose hello.py prints a word misspelt, in the image
# given (the run's first task's: the same base as the tasks).
swe_checktask() { # <image>
  local g=$SWE_DIR/check/task.git w=$SWE_DIR/check/make.$$
  if [ ! -d "$g" ]; then
    rm -rf "$w" && mkdir -p "$w" && git init -q -b main "$w" && printf 'print("helo")\n' > "$w/hello.py" && git -C "$w" add -A \
      && git -C "$w" -c user.name=conveyor -c user.email=conveyor@example.com commit -qm base && git clone -q --bare "$w" "$g.$$" && mv "$g.$$" "$g"
    rm -rf "$w" "$g.$$"; [ -d "$g" ] || return 1
  fi
  jq -nc --arg u "file://$g" --arg b "$(git -C "$g" rev-parse main)" --arg i "$1" \
    '{id: "preflight", url: $u, base: $b, issue: "hello.py prints \"helo\". It should print \"hello\".", image: $i, cmd: "python3 hello.py"}'
}
# An arm's preflight: offered, Docker answering, each login it uses present on this machine, then the trivial task in
# a container: its install, its preflight command and its run, which must fire and change hello.py. Prints nothing
# when it passed, else what is missing; keeps the state in preflight/<arm>/<key>.json (swe_arms reads it).
swe_preflight() { # <arm json> <key> <image> <engine's conveyor.sh, conveyor kind>
  local a=$1 n why='' l f t sb b
  n=$(jq -r .name <<<"$a")
  if jq -e '.offered == false' <<<"$a" > /dev/null; then why="not offered: $(jq -r '.why // "no reason given"' <<<"$a")"
  elif ! docker info > /dev/null 2>&1; then why="Docker is not installed or not running (docker info failed)"
  else
    for l in $(jq -r '.login // [] | .[]' <<<"$a"); do
      f=$(swe_login "$l") && [ -s "$f" ] && continue
      why="no $l login on this machine: ${f:+${f/#$HOME/\~} is missing; }sign in with $l (on macOS a Claude login kept in the Keychain has no such file)"; break
    done
  fi
  if [ -z "$why" ]; then
    sb=$SWE_DIR/check/$n
    if ! t=$(swe_checktask "$3") || ! swe_sandbox "$t" "$sb" 2> /dev/null; then why="the trivial task could not be set up"
    elif ! b=$(swe_trial "$t" "$sb" "$a" "$4"); then why=$b
    elif ! jq -e .fired <<<"$b" > /dev/null; then why="on the trivial task, $(jq -r .why <<<"$b")"
    elif [ ! -s "$sb.h/patch" ]; then why="it ran the trivial task headless but changed no file"; fi
    { chmod -R u+w "$sb" "$sb.h"; rm -rf "$sb" "$sb.h"; } 2>/dev/null
  fi
  mkdir -p "$SWE_DIR/preflight/$n" && swe_put "$SWE_DIR/preflight/$n/$2.json" "$(jq -nc --argjson a "$a" --arg k "$2" --arg w "$why" --arg at "$(swe_now)" --argjson e "$(date +%s)" \
    '{arm: $a.name, key: $k, ok: ($w == ""), why: (if $w == "" then null else $w end), at: $at, epoch: $e, spec: $a}')"
  printf '%s' "$why"
}
# An arm can be picked once its preflight passed: a pass of the same arm file and key from the last day is taken,
# else the preflight runs now. Prints nothing when the arm is ready, else why not.
swe_ready() { # <arm json> <key> <image> <engine's conveyor.sh, conveyor kind>
  jq -e --argjson a "$1" --argjson now "$(date +%s)" '.ok and .spec == $a and $now - .epoch < 86400' "$SWE_DIR/preflight/$(jq -r .name <<<"$1")/$2.json" > /dev/null 2>&1 \
    || swe_preflight "$@"
}
# `bench swe arms`: each arm with its preflight state (its latest preflight); `bench swe arms check <arm>...` runs
# those arms' preflights now, a conveyor arm's on main's engine.
swe_arms() { # [check <arm>...]
  local n a r tf img eng k bad=0 gc='' ga=''
  if [ "${1:-}" = check ]; then
    shift; [ $# -gt 0 ] || { echo "usage: conveyor.sh bench swe arms [check <arm>...]" >&2; return 2; }
    # A preflight starts a model session on the trivial task: the usage guard holds it back as it holds a run.
    for n; do a=$(swe_arm "$n") || continue; if [ "$(jq -r .kind <<<"$a")" = conveyor ]; then gc=1; else ga=1; fi; done
    ! swe_held "$gc" "$ga" || { echo "conveyor: the usage guard is reached: no preflight starts while it stands" >&2; return 1; }
    tf=$(swe_tasks) || return 1; img=$(head -n 1 "$tf" | jq -r .image)
    swe_h image "$img" > /dev/null 2>&1 || { echo "conveyor: the base image $img could not be fetched" >&2; return 1; }
    for n in "$@"; do
      a=$(swe_arm "$n") || { echo "conveyor: no arm $n: \`conveyor.sh bench swe arms\` lists them" >&2; bad=1; continue; }
      eng=''; SWE_MODEL=''
      if [ "$(jq -r .kind <<<"$a")" = conveyor ]; then
        swe_resolve main && { installed "$SWE_COMMIT" || install "$SWE_COMMIT" "$(swe_src)" > /dev/null; } \
          || { echo "$n: failed: main's engine could not be installed"; bad=1; continue; }
        eng=$VERSIONS/$SWE_COMMIT/conveyor/conveyor.sh
      elif [ "$(jq -r '.model // ""' <<<"$a")" = builder ]; then SWE_MODEL=$(swe_solomodel)
      else SWE_MODEL=$(jq -r '.model // ""' <<<"$a"); fi
      k=$(swe_armkey "$a" "${SWE_COMMIT:-}" "$SWE_MODEL")
      r=$(swe_preflight "$a" "$k" "$img" "$eng"); if [ -z "$r" ]; then echo "$n: ready"; else echo "$n: failed: $r"; bad=1; fi
    done
    return "$bad"
  fi
  [ $# = 0 ] || { echo "usage: conveyor.sh bench swe arms [check <arm>...]" >&2; return 2; }
  for n in $(swe_armnames); do
    a=$(swe_arm "$n") || { echo "$n: its file is not a JSON object"; continue; }
    r=$(cat "$SWE_DIR/preflight/$n"/*.json 2>/dev/null | jq -sc 'sort_by(.epoch) | last // null')
    jq -r --argjson r "$r" '"\(.name) (\(.label // .name), \(.kind)): " + (if .offered == false then "not offered: \(.why // "no reason given")"
      elif $r == null then "not checked: `conveyor.sh bench swe arms check \(.name)` runs its preflight"
      elif $r.spec != . then "not checked since its file changed"
      elif $r.ok then "ready (checked \($r.at))" else "failed (\($r.at)): \($r.why)" end)' <<<"$a"
  done
}
