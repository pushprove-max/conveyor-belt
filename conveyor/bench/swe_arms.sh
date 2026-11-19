# SPDX-License-Identifier: Apache-2.0
# The arms of `conveyor.sh bench swe` (bench/swe.sh, which sources this file). An arm is one way of building a task:
# one JSON file under bench/arms/ (CONVEYOR_BENCH_ARMS names another folder: the tests' stub arms), its name the
# file's. Its fields:
#   label      what the results call the arm
#   kind       "conveyor": the engine's loop builds the task's card (`conveyor.sh run 1`) on the project's seats with
#              the arm's seats over them; "agent": the arm's own run command builds it
#   seats      (conveyor) the control record's model, reviewer and judge the arm sets, as the control record holds them
#   rules      (conveyor) "engine" (the default): the engine version's core card rules; "project": those and the
#              project's card and area rules (swe_pack)
#   policy     (conveyor) the review policy the arm sets over the control record's: judgeOn (the judge reads the
#              reviews), judgeAlways (the finding kinds it always accepts) and P0 to P3 (rules.P0 and so on), each
#              optional; what it leaves out is the control record's (swe_pack)
#   login      the subscription logins the arm uses: "claude" (the builder's account, `control account`), "codex";
#              a conveyor arm's container is given the login of each seat's CLI as well (swe_logins)
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
# A saved arm (`bench swe arms save`, swe_armsave) is a revision the Board's form made: a name and choices only, no
# command. It runs on a host arm (its recipe: the conveyor arm, or an agent arm that takes a model) with its seats or
# model over it, and its name is its revision ID.
# Every trial runs in a container of its own (swe_box): the task's image, the same limits for every arm (swe.json's
# limits and taskTimeout), the logins copied in at its start only, and the container removed when the trial ends.
SWE_ARMS=${CONVEYOR_BENCH_ARMS:-${BASH_SOURCE[0]%/*}/arms}
SWE_HOME=/bench
swe_arm() { # <name | saved revision ID>: the arm's JSON, its keys sorted (a preflight's record is compared with it whole)
  local j r
  if [[ $1 =~ $SWE_ARMID ]]; then
    # A saved revision: its recipe's JSON with the revision's seats or model over it, named by its ID.
    r=$(jq -ce 'objects' "$SWE_DIR/arms/$1.json" 2>/dev/null) && j=$(jq -r '.spec.recipe // "conveyor"' <<<"$r") && [[ ! $j =~ $SWE_ARMID ]] && j=$(swe_arm "$j") || return 1
    jq -cS --argjson r "$r" '. + ($r.spec | del(.kind, .recipe, .cli)) + {name: $r.id, label: $r.name, revision: {id: $r.id, name: $r.name, at: $r.at, recipe: .name}}' <<<"$j"
    return
  fi
  [[ $1 =~ ^[a-z0-9][a-z0-9-]*$ ]] && j=$(jq -cSe 'objects' "$SWE_ARMS/$1.json" 2>/dev/null) && jq -cS --arg n "$1" '.name = $n' <<<"$j"
}
SWE_ARMID='^arm-[0-9a-f]{12}$'
# The choices a saved arm may make, as the Board's form offers them: the models the project allows each seat pool by
# CLI (okmodels: the builder's pool for the builder, the reviewer's for the reviewer and the judge), the models an
# agent arm may run on each CLI a container can sign in to (both pools' for that CLI), and each CLI's efforts.
# source: "project" when the pack sets models.allowed, else "engine": the engine's defaults (modelsallowed()).
swe_choices() {
  local a s=project
  packget models.allowed a 2>/dev/null || return 1; [ -n "$a" ] || s=engine
  modelsallowed a || return 1
  jq -c --arg s "$s" --argjson e "$EFFORTS" "$OKMODELS"'okmodels("builder") as $b | okmodels("reviewer") as $r
    | {source: $s, builder: $b, reviewer: $r, agent: {claude: ($b.claude + ($r.claude - $b.claude)), codex: ($b.codex + ($r.codex - $b.codex))}, efforts: $e}' <<<"$a"
}
# `bench swe arms save <name> <spec>`: checks a saved arm's choices against the project's (swe_choices) and keeps it as
# a new revision, $SWE_DIR/arms/<id>.json, {id, name, at, spec}, never written again: saving under the same name makes
# another revision, so a run keeps the one it used. Prints the ID: arm-<the first 12 of sha256 of name and spec>. The
# spec holds choices only, no command:
#   {kind: "conveyor", seats: {model, reviewer, judge}, rules, policy}   each seat given {cli, model, effort} (effort
#                                   optional); rules "engine" or "project" (optional, swe_pack); policy {judgeOn: true
#                                   or false, judgeAlways: [kind words, as `control judge always` takes them], P0 to P3:
#                                   true or false}, each optional
#   {kind: "agent", recipe: <host agent arm>, cli: <claude | codex>, model}
# A model the project does not allow that seat (or that CLI, for an agent) is refused, nothing kept: a saved arm cannot
# add a model to the project's choices (swe_pack adds a host arm's seat models to the sandbox's list, never a saved one's).
swe_armsave() { # <name> <spec json>
  local c s w id r f
  c=$(swe_choices) || { echo "conveyor: the project's models.allowed cannot be read; nothing saved" >&2; return 1; }
  s=$(jq -cSe 'objects' <<<"$2" 2>/dev/null) || { echo "conveyor: the arm's spec is not a JSON object; nothing saved" >&2; return 1; }
  w=$(jq -rn --arg n "$1" --argjson s "$s" --argjson c "$c" '
    def seaterr($k; $v): (if $k == "model" then "builder" else $k end) as $w | (if $k == "model" then $c.builder else $c.reviewer end) as $p
      | if ($v | type) != "object" or (($v | keys) - ["cli", "model", "effort"]) != [] then "the \($w) seat takes cli, model and effort only"
        elif ($v.cli | type) != "string" or ($p | has($v.cli) | not) then "the \($w) seat cannot run on the CLI \($v.cli | tojson)"
        elif ($v.model | type) != "string" or ($p[$v.cli] | index([$v.model])) == null then "the project does not allow \($v.model | tojson) on \($v.cli) for the \($w) seat"
        elif $v.effort == null then empty
        elif $k == "model" and $v.cli == "opencode" then "an OpenCode builder takes no effort"
        elif ($v.effort | type) != "string" or ($c.efforts[$v.cli] | index([$v.effort])) == null then "\($v.cli) takes no effort \($v.effort | tojson)"
        else empty end;
    [ if ($n | length) < 1 or ($n | length) > 80 or ($n | test("[[:cntrl:]]")) or ($n | test("^\\s|\\s$")) then "the name must be 1 to 80 characters, with no control character and no space at either end"
      elif $s.kind == "conveyor" then
        (($s | keys) - ["kind", "seats", "rules", "policy"]) as $x | ($s.seats // {}) as $t | ($s.policy // {}) as $p
        | if $x != [] then "a Conveyor arm takes kind, seats, rules and policy only, not \($x | join(", "))"
          elif $s | has("rules") and (.rules | IN("engine", "project") | not) then "the rules are engine or project, not \($s.rules | tojson)"
          elif ($p | type) != "object" or (($p | keys) - ["judgeOn", "judgeAlways", "P0", "P1", "P2", "P3"]) != [] then "the policy takes judgeOn, judgeAlways and P0 to P3 only"
          elif [$p | del(.judgeAlways)[]] | all(type == "boolean") | not then "judgeOn and P0 to P3 are true or false"
          elif $p | has("judgeAlways") and (.judgeAlways | type != "array" or length > 20 or any(type != "string" or (test("^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$") | not)))
            then "judgeAlways is a list of at most 20 finding kinds, each a word of letters, digits, _ and -"
          elif ($t | type) != "object" then "seats must be an object"
          elif (($t | keys) - ["model", "reviewer", "judge"]) != [] then "the seats are model (the builder), reviewer and judge, not \(($t | keys) - ["model", "reviewer", "judge"] | join(", "))"
          else $t | to_entries[] | seaterr(.key; .value) end
      elif $s.kind == "agent" then
        (($s | keys) - ["kind", "recipe", "cli", "model"]) as $x
        | if $x != [] then "an agent arm takes kind, recipe, cli and model only, not \($x | join(", "))"
          elif ($s.recipe | type) != "string" or ($s.recipe | test("^[a-z0-9][a-z0-9-]*$") | not) then "the recipe must name an agent arm"
          elif ($c.agent | has($s.cli | tostring) | not) then "an agent arm runs on claude or codex, not \($s.cli | tojson)"
          elif ($s.model | type) != "string" or ($c.agent[$s.cli] | index([$s.model])) == null then "the project does not allow \($s.model | tojson) on \($s.cli)"
          else empty end
      else "kind must be conveyor or agent" end ] | first // empty')
  # An agent arm's recipe: a host arm of that kind, offered, signed in with the CLI chosen, that runs on the model given.
  if [ -z "$w" ] && [ "$(jq -r .kind <<<"$s")" = agent ]; then
    f=$(jq -r .recipe <<<"$s")
    if [[ $f =~ $SWE_ARMID ]] || ! r=$(swe_arm "$f") || [ "$(jq -r .kind <<<"$r")" != agent ]; then w="no agent arm $f"
    elif jq -e '.offered == false' <<<"$r" > /dev/null; then w="the arm $f is not offered: $(jq -r '.why // "no reason given"' <<<"$r")"
    elif ! jq -e '.model | type == "string"' <<<"$r" > /dev/null; then w="the arm $f takes no model"
    elif ! jq -e --arg c "$(jq -r .cli <<<"$s")" '.login == [$c]' <<<"$r" > /dev/null; then w="the arm $f does not run on $(jq -r .cli <<<"$s") alone"; fi
  fi
  [ -z "$w" ] || { echo "conveyor: $w; nothing saved" >&2; return 1; }
  id=arm-$(jq -cSn --arg n "$1" --argjson s "$s" '{name: $n, spec: $s}' | sha256sum | cut -c1-12)
  if [ ! -s "$SWE_DIR/arms/$id.json" ]; then
    mkdir -p "$SWE_DIR/arms" && swe_put "$SWE_DIR/arms/$id.json" "$(jq -cn --arg id "$id" --arg n "$1" --argjson s "$s" --arg at "$(swe_now)" '{id: $id, name: $n, at: $at, spec: $s}')" \
      || { echo "conveyor: the arm could not be saved" >&2; return 1; }
  fi
  printf '%s\n' "$id"
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
# The logins an arm's container is given: the arm's own, and for a conveyor arm the CLI of each seat `run 1` uses
# there (the project's control record with the arm's seats and its policy's judgeOn over it, as swe_pack writes it:
# the builder, the reviewer and the judge only when it is on; the Tests seat serves `testaction`, which the run does not start), so a Conveyor arm on Claude seats needs
# no Codex login. The seats are worked out on the models the engine in the container offers, not this host's: the
# task's pack (swe_pack: the project's models.allowed, with a host arm's seats in it) when it lists some, else the
# built-in MODELS0, as the arm's install puts Codex in the container even where this host has none.
swe_logins() { # <arm json>
  local c a s x=''
  if [ "$(jq -r .kind <<<"$1")" = conveyor ]; then
    s=$(jq -c '.seats // {}' <<<"$1")
    c=$(ctl 2>/dev/null) && c=$(jq -c --argjson s "$s" --argjson p "$(jq -c '.policy // {}' <<<"$1")" '. + $s + ($p | with_entries(select(.key == "judgeOn")))' <<<"$c") || c=null
    packget models.allowed a 2>/dev/null || a=''
    x=$(jq -r --argjson c "$c" --argjson s "$(jq -c 'if has("revision") then {} else .seats // {} end' <<<"$1")" --argjson d "$MODELS0" "$SEATNOW$JUDGENOW"'
        reduce ($s[] | objects | select(.cli != null)) as $x (.; .[$x.cli] = ((.[$x.cli] // []) + [$x.model] | unique)) | (. // $d)
        | ([try seatnow("builder"; $c)] | first) as $b | ([try seatnow("reviewer"; $c)] | first) as $r
        | $b, $r, (if $c.judgeOn == true and $r != null then [try judgenow($c; $r)] | first else null end) | .agent? // empty' <<<"${a:-null}")
  fi
  jq -r --arg x "$x" '[(.login // [])[], ($x | splits("\n")) | select(IN("claude", "codex"))] | unique | join(" ")' <<<"$1"
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
# The areas of the project's pack whose rule a task's card reads: each "<glob>\t<rule file>" the pack's areas map, by
# path glob, to a path the task's issue names (the sandbox's issue #1, swe_sandbox: its title and body), scanned as
# cardrules() scans an issue, in the pack's order. Fails when the pack cannot be read.
swe_arearules() { # <task json>
  local a g f x ps
  packget areas a || return 1
  mapfile -t ps < <(jq -r '["SWE-bench \(.id)", .issue] | map(strings) | join("\n") | scan("[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*/?")' <<<"$1")
  while IFS=$'\t' read -r g f; do
    # shellcheck disable=SC2053 # $g is the area's path glob: matched as a pattern, as cardrules() matches it
    for x in "${ps[@]}"; do [[ $x == $g ]] && { printf '%s\t%s\n' "$g" "$f"; break; }; done
  done < <([ -z "$a" ] || jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$a")
  return 0
}
# Whether an arm that takes the project's rules can run the tasks on stdin (one JSON a line): each area rule file one
# of their cards reads (swe_arearules) is a readable file, so no card builds on fewer rules than the arm says. Prints
# nothing when it can, else why not (swe_pack's words). A rule file no task's card reads is never checked.
swe_taskrules() { # <arm json> < tasks
  local t l g f
  [ "$(jq -r '.rules // "engine"' <<<"$1")" = project ] || return 0
  while IFS= read -r t; do
    l=$(swe_arearules "$t") || { echo "the project's pack could not be read for its area rules"; return; }
    while IFS=$'\t' read -r g f; do
      [ -f "$MAIN/$f" ] && [ -r "$MAIN/$f" ] \
        || { echo "the arm takes the project's rules, and the area rule file $f its pack maps to $g is missing or cannot be read"; return; }
    done < <([ -z "$l" ] || printf '%s\n' "$l")
  done
}
# The pack and control record of a conveyor arm's sandbox: the project's, with the task's test command run in the
# container, the arm's seats (a host arm's models added to models.allowed; a saved arm's are the project's already,
# swe_armsave), its review policy (policy: judgeOn, judgeAlways, rules.P0 to P3) over the record's, and no named
# account: the container has one login of each. The project's per-issue seats (cards) are
# left out: every task is issue 1 there, and a project's own cards["1"] must not change the arm's seats. The arm's
# rules (its rules field): "engine" (the default), the engine version's core rules alone; "project", a copy of the
# project's card rules (.conveyor/card-rules.md) and of each area rule file its pack's areas map, by path glob, to a
# path the task's issue names (the sandbox's issue #1, swe_sandbox: title and body, scanned as cardrules() scans them),
# taken now, so the card there gets the rules cardrules() gives a card here (swe_arearules). An area no such path
# matches is left out of the pack, as no card there reads its rule. A rule file the card reads missing or unreadable
# refuses the arm.
swe_pack() { # <task json> <sb> <engine's conveyor.sh> <arm json>
  local sb=$2 d=$2/$SWE_MAIN/.conveyor s m l g f i=0 ar='{}';s=$(jq -c '.seats // {}' <<<"$4"); m=$(jq -r '.rules // "engine"' <<<"$4")
  mkdir -p "$d" "$sb/cards" && : > "$sb/rulings.jsonl" || return 1
  case $m in
    engine) ;;
    project)
      cp -- "$MAIN/.conveyor/card-rules.md" "$d/card-rules.md" 2>/dev/null \
        || { echo "the arm takes the project's rules, and its card rules .conveyor/card-rules.md are missing or cannot be read"; return 1; }
      l=$(swe_arearules "$1") || { echo "the project's pack could not be read for its area rules"; return 1; }
      mkdir -p "$d/area-rules" || return 1
      while IFS=$'\t' read -r g f; do
        i=$((i + 1)); cp -- "$MAIN/$f" "$d/area-rules/$i.md" 2>/dev/null \
          || { echo "the arm takes the project's rules, and the area rule file $f its pack maps to $g is missing or cannot be read"; return 1; }
        ar=$(jq -c --arg g "$g" --arg f ".conveyor/area-rules/$i.md" '.[$g] = $f' <<<"$ar")
      done < <([ -z "$l" ] || printf '%s\n' "$l") ;;
    *) echo "the arm's rules are engine or project, not $m"; return 1 ;;
  esac
  jq --arg t "$(jq -r .cmd <<<"$1")" --arg l "$sb/rulings.jsonl" --argjson s "$(jq -c 'if has("revision") then {} else .seats // {} end' <<<"$4")" --argjson ar "$ar" '{owner, labels: ((.labels // {}) + {nonProductAreas: []}), models, review, prices, privacy,
    tunables: ((.tunables // {}) + {closeWait: 0}), rulings: {log: $l}, test: {command: $t, survey: false}, productPaths: [".conveyor-none/"], linkFromMain: [], checks: [],
    push: {env: {}}, remote: "origin", defaultBranch: "main", landBatch: 1} | with_entries(select(.value != null))
    | if $ar != {} then .areas = $ar else . end
    | reduce ($s[] | objects | select(.cli != null)) as $x (.; .models.allowed[$x.cli] = ((.models.allowed[$x.cli] // []) + [$x.model] | unique))' \
    "$MAIN/.conveyor/project.json" > "$d/project.json" || { echo "the project's pack could not be read to make the task's pack"; return 1; }
  # The container holds no host file, so the engine there keeps its state in the checkout's own conveyor/state.
  SWE_SST=$sb/$SWE_MAIN/conveyor/state
  mkdir -p "$SWE_SST" && ctl | jq --argjson s "$s" --argjson p "$(jq -c '.policy // {}' <<<"$4")" '.mode = "run" | .held = [] | .order = [] | .startHeld = [] | .start = "queue" | .rules.followups = false | .rules.visible = false
    | .rules.push = true | .cards = {} | del(.account, .reviewAccount) + $s
    | .rules += ($p | with_entries(select(.key | test("^P[0-3]$")))) | . + ($p | with_entries(select(.key | IN("judgeOn", "judgeAlways"))))' > "$SWE_SST/control.json" || { echo "the project's control record could not be read"; return 1; }
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
  swe_box "$c" "$(jq -r .image <<<"$1")" "$sb" "$(swe_logins "$a")" "$eng" > "$h/box.err" 2>&1 \
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
# An arm's preflight: offered, each login it uses present on this machine, then the trivial task in a container: its
# install, its preflight command and its run, which must fire and change hello.py (Docker and the harness are checked
# before, by swe_setup, in both callers). Prints nothing when it passed, else what is missing; keeps the state in
# preflight/<arm>/<key>.json (swe_arms reads it).
swe_preflight() { # <arm json> <key> <image> <engine's conveyor.sh, conveyor kind>
  local a=$1 n why='' l f t sb b
  n=$(jq -r .name <<<"$a")
  if jq -e '.offered == false' <<<"$a" > /dev/null; then why="not offered: $(jq -r '.why // "no reason given"' <<<"$a")"
  else
    for l in $(swe_logins "$a"); do
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
    --arg l "$(swe_logins "$a")" '{arm: $a.name, key: $k, ok: ($w == ""), why: (if $w == "" then null else $w end), at: $at, epoch: $e, spec: $a, logins: $l}')"
  printf '%s' "$why"
}
# An arm can be picked once its preflight passed: a pass of the same arm file and key from the last day, with the
# same logins (a seat may have moved to another CLI since), is taken, else the preflight runs now. Prints nothing
# when the arm is ready, else why not.
swe_ready() { # <arm json> <key> <image> <engine's conveyor.sh, conveyor kind>
  jq -e --argjson a "$1" --arg l "$(swe_logins "$1")" --argjson now "$(date +%s)" '.ok and .spec == $a and .logins == $l and $now - .epoch < 86400' "$SWE_DIR/preflight/$(jq -r .name <<<"$1")/$2.json" > /dev/null 2>&1 \
    || swe_preflight "$@"
}
# `bench swe arms`: each arm with its preflight state (its latest preflight); `bench swe arms check <arm>...` runs
# those arms' preflights now, a conveyor arm's on main's engine (an arm is a host arm's name or a saved revision's ID);
# `bench swe arms save <name> <spec>` keeps a saved arm and prints its ID (swe_armsave); `bench swe arms show <id>`
# prints that revision as it was saved.
SWE_ARMSUSE='usage: conveyor.sh bench swe arms [check <arm>...] | bench swe arms save <name> <spec json> | bench swe arms show <id>'
swe_arms() { # [check <arm>... | save <name> <spec json> | show <id>]
  local n a r tf img eng k bad=0 gc='' ga=''
  case ${1:-} in
    save) [ $# = 3 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }; swe_armsave "$2" "$3"; return ;;
    show) [ $# = 2 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }
      [[ $2 =~ $SWE_ARMID ]] && jq -ce 'objects' "$SWE_DIR/arms/$2.json" 2>/dev/null || { echo "conveyor: no saved arm $2" >&2; return 1; }; return ;;
  esac
  if [ "${1:-}" = check ]; then
    shift; [ $# -gt 0 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }
    # A preflight starts a model session on the trivial task: the usage guard holds it back as it holds a run.
    for n; do a=$(swe_arm "$n") || continue; case $(swe_guards "$a") in conveyor) gc=1 ;; agent) ga=1 ;; esac; done
    ! swe_held "$gc" "$ga" || { echo "conveyor: the usage guard is reached: no preflight starts while it stands" >&2; return 1; }
    swe_setup || return 1
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
  [ $# = 0 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }
  for n in $(swe_armnames); do
    a=$(swe_arm "$n") || { echo "$n: its file is not a JSON object"; continue; }
    r=$(cat "$SWE_DIR/preflight/$n"/*.json 2>/dev/null | jq -sc 'sort_by(.epoch) | last // null')
    jq -r --argjson r "$r" '"\(.name) (\(.label // .name), \(.kind)): " + (if .offered == false then "not offered: \(.why // "no reason given")"
      elif $r == null then "not checked: `conveyor.sh bench swe arms check \(.name)` runs its preflight"
      elif $r.spec != . then "not checked since its file changed"
      elif $r.ok then "ready (checked \($r.at))" else "failed (\($r.at)): \($r.why)" end)' <<<"$a"
  done
}
