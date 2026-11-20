# SPDX-License-Identifier: Apache-2.0
# The arms of `conveyor.sh bench swe` (bench/swe.sh, which sources this file). An arm is one way of building a task:
# one JSON file under bench/arms/ (CONVEYOR_BENCH_ARMS names another folder: the tests' stub arms), its name the
# file's. Its fields:
#   label      what the results call the arm
#   kind       "conveyor": the engine's loop builds the task's card (`conveyor.sh run 1`) on the project's seats with
#              the arm's seats over them; "agent": the arm's own run command builds it
#   seats      (conveyor) the control record's model, reviewer, judge, fix and testFix the arm sets, as the control
#              record holds them (fix and testFix, the repairs of review findings and of failed tests, from the
#              builder's models; left out, each is the project's, which follows the builder unless set); an engine
#              version that has no such seat refuses an arm whose card would set it (swe_pack)
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
#              issue, $SWE_MODEL the model, $SWE_EFFORT the effort (empty: the CLI's own); what it prints is the
#              trial's output
#   fired      (agent) jq over the output's JSON lines, as one array: true when the arm's method ran
#   tokens     (agent) jq over the same array: the tokens the trial took
#   sessions   (agent) the sessions a trial takes
#   model      (agent) the model given as $SWE_MODEL; "builder": the builder seat's Claude model, as Claude alone takes
#   effort     (agent) true when run passes $SWE_EFFORT to its CLI: only then may a saved arm on it choose an effort
#   exclude    paths the arm's method writes in the checkout that are not the change: kept out of the patch
#   offered    false for an arm that cannot run here, with why
# A saved arm (`bench swe arms save`, swe_armsave) is a revision the Board's form made: a name and choices only, no
# command. It runs on a host arm (its recipe: the conveyor arm, or an agent arm that takes a model) with its seats or
# model over it, and its name is its revision ID.
# Every trial runs in a container of its own (swe_box): the task's image, the same limits for every arm (the run's
# settings: cpus, memory and taskTimeout, swe_settings), the logins copied in at its start only, and the container
# removed when the trial ends.
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
#   {kind: "conveyor", seats: {model, reviewer, judge, fix, testFix}, rules, policy}   each seat given {cli, model, effort} (effort
#                                   optional); rules "engine" or "project" (optional, swe_pack); policy {judgeOn: true
#                                   or false, judgeAlways: [kind words, as `control judge always` takes them], P0 to P3:
#                                   true or false}, each optional
#   {kind: "agent", recipe: <host agent arm>, cli: <claude | codex>, model, effort}   effort optional, one of the
#                                   CLI's; the recipe must take it (its effort field), and its run gets it as $SWE_EFFORT
# A model the project does not allow that seat (or that CLI, for an agent) is refused, nothing kept: a saved arm cannot
# add a model to the project's choices (swe_pack adds a host arm's seat models to the sandbox's list, never a saved one's).
swe_armsave() { # <name> <spec json>
  local c s w id r f
  c=$(swe_choices) || { echo "conveyor: the project's models.allowed cannot be read; nothing saved" >&2; return 1; }
  s=$(jq -cSe 'objects' <<<"$2" 2>/dev/null) || { echo "conveyor: the arm's spec is not a JSON object; nothing saved" >&2; return 1; }
  w=$(jq -rn --arg n "$1" --argjson s "$s" --argjson c "$c" '
    def seaterr($k; $v): (if $k == "model" then "builder" else $k end) as $w | (if $k | IN("model", "fix", "testFix") then $c.builder else $c.reviewer end) as $p
      | if ($v | type) != "object" or (($v | keys) - ["cli", "model", "effort"]) != [] then "the \($w) seat takes cli, model and effort only"
        elif ($v.cli | type) != "string" or ($p | has($v.cli) | not) then "the \($w) seat cannot run on the CLI \($v.cli | tojson)"
        elif ($v.model | type) != "string" or ($p[$v.cli] | index([$v.model])) == null then "the project does not allow \($v.model | tojson) on \($v.cli) for the \($w) seat"
        elif $v.effort == null then empty
        elif ($k | IN("model", "fix", "testFix")) and $v.cli == "opencode" then "an OpenCode \($w) seat takes no effort"
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
          elif (($t | keys) - ["model", "reviewer", "judge", "fix", "testFix"]) != [] then "the seats are model (the builder), reviewer, judge, fix and testFix, not \(($t | keys) - ["model", "reviewer", "judge", "fix", "testFix"] | join(", "))"
          else $t | to_entries[] | seaterr(.key; .value) end
      elif $s.kind == "agent" then
        (($s | keys) - ["kind", "recipe", "cli", "model", "effort"]) as $x
        | if $x != [] then "an agent arm takes kind, recipe, cli, model and effort only, not \($x | join(", "))"
          elif ($s.recipe | type) != "string" or ($s.recipe | test("^[a-z0-9][a-z0-9-]*$") | not) then "the recipe must name an agent arm"
          elif ($c.agent | has($s.cli | tostring) | not) then "an agent arm runs on claude or codex, not \($s.cli | tojson)"
          elif ($s.model | type) != "string" or ($c.agent[$s.cli] | index([$s.model])) == null then "the project does not allow \($s.model | tojson) on \($s.cli)"
          elif ($s | has("effort")) and (($s.effort | type) != "string" or ($c.efforts[$s.cli] | index([$s.effort])) == null) then "\($s.cli) takes no effort \($s.effort | tojson)"
          else empty end
      else "kind must be conveyor or agent" end ] | first // empty')
  # An agent arm's recipe: a host arm of that kind, offered, signed in with the CLI chosen, that runs on the model given
  # and, when one is chosen, passes the effort to its CLI.
  if [ -z "$w" ] && [ "$(jq -r .kind <<<"$s")" = agent ]; then
    f=$(jq -r .recipe <<<"$s")
    if [[ $f =~ $SWE_ARMID ]] || ! r=$(swe_arm "$f") || [ "$(jq -r .kind <<<"$r")" != agent ]; then w="no agent arm $f"
    elif jq -e '.offered == false' <<<"$r" > /dev/null; then w="the arm $f is not offered: $(jq -r '.why // "no reason given"' <<<"$r")"
    elif ! jq -e '.model | type == "string"' <<<"$r" > /dev/null; then w="the arm $f takes no model"
    elif ! jq -e --arg c "$(jq -r .cli <<<"$s")" '.login == [$c]' <<<"$r" > /dev/null; then w="the arm $f does not run on $(jq -r .cli <<<"$s") alone"
    elif jq -e 'has("effort")' <<<"$s" > /dev/null && ! jq -e '.effort == true' <<<"$r" > /dev/null; then w="the arm $f takes no effort: its command does not pass one to its CLI"; fi
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
# The key an arm's preflights are kept under: the engine commit for the conveyor arm, <arm>-<commit> for another
# conveyor arm, <arm>-<model> for an arm on the builder's model (solo-<model> for Claude alone), else <arm>.
swe_armkey() { # <arm json> <engine commit, conveyor kind> <model>
  local n k; n=$(jq -r .name <<<"$1")
  if [ "$(jq -r .kind <<<"$1")" = conveyor ]; then [ "$n" = conveyor ] && k=$2 || k=$n-$2
  elif [ "$(jq -r '.model // ""' <<<"$1")" = builder ]; then k=$n-${3:-default}
  else k=$n; fi
  printf '%s\n' "${k//[^A-Za-z0-9._-]/-}"
}
# Where a conveyor arm's sandbox reads the project's files from: the run's copy of them for the arm in use (SWE_FZ,
# swe_freeze), else the project's checkout (a preflight `bench swe arms check` runs, the Board's history, Compare).
# Sets the caller's o to that folder and PACK, the pack packget reads, to the pack there: the caller makes both local.
swe_root() {
  if [ -n "${SWE_FZ:-}" ]; then o=$SWE_FZ/main; PACK=$o/.conveyor/project.json; else o=$MAIN; fi
}
# A run's copy of what a conveyor arm's sandbox reads of the project, taken once at the run's start, so every task of
# the run builds on the same seats, policy and rules, even when the project's change while it runs: the sandbox's
# control record (swe_ctl) in <folder>/control.json, and under <folder>/main the pack and, for an arm on the project's
# rules, the card rules and each area rule file the pack maps. A rule file missing or unreadable now is missing there
# too: swe_taskrules and swe_pack refuse the arm when a task's card reads it.
swe_freeze() { # <arm json> <folder>
  local SWE_FZ='' r=$2/main a g f
  rm -rf "$2" && mkdir -p "$r/.conveyor" && swe_ctl "$1" > "$2/control.json" && cp -- "$PACK" "$r/.conveyor/project.json" || return 1
  [ "$(jq -r '.rules // "engine"' <<<"$1")" = project ] || return 0
  [ ! -f "$MAIN/.conveyor/card-rules.md" ] || cp -- "$MAIN/.conveyor/card-rules.md" "$r/.conveyor/card-rules.md" 2>/dev/null || :
  packget areas a || return 1
  while IFS=$'\t' read -r g f; do
    [[ $f != /* && /$f/ != */../* ]] && [ -f "$MAIN/$f" ] && [ -r "$MAIN/$f" ] || continue
    mkdir -p "$r/$(dirname -- "$f")" && cp -- "$MAIN/$f" "$r/$f" || return 1
  done < <([ -z "$a" ] || jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$a")
}
# What a trial of an arm is given, as JSON, the same for each task of a run: the task set and the grading (dataset,
# revision, the harness's swebench version), the limits, the arm (its JSON without the words that only name it), the
# model and, for a conveyor arm, the control record and the parts of the pack its sandbox takes (swe_ctl, swe_pack)
# and its rules: the mode and, for the project's, the sha256 of the card rules and of every area rule file the pack
# maps (a task's card reads some of them). A conveyor arm's engine commit is not in it: its key holds it (swe_reskey).
# The control record leaves out what the card's build does not read: the queue, the cap, the guard and the Tests
# seat (the benchmark's `run 1` starts no `testaction`). Read from the run's copy of the arm in use (swe_root).
swe_inputs() { # <arm json> <model>
  local c=null p=null r=null a g f h o PACK=$PACK; swe_root
  if [ "$(jq -r .kind <<<"$1")" = conveyor ]; then
    c=$(swe_ctl "$1" | jq -c 'del(.mode, .held, .order, .start, .startHeld, .startSeen, .forced, .onboarded, .cards, .cap, .guard, .tests, .signin)') && [ -n "$c" ] || return 1
    p=$(jq -c '{labels, models, review, tunables, privacy}' "$PACK") || return 1
    r=$(jq -c '{mode: (.rules // "engine")}' <<<"$1")
    if [ "$(jq -r .mode <<<"$r")" = project ]; then
      packget areas a || return 1
      r=$(jq -c --arg h "$(sha256sum < "$o/.conveyor/card-rules.md" 2>/dev/null | cut -c1-64)" '. + {card: $h, areas: {}}' <<<"$r")
      while IFS=$'\t' read -r g f; do
        h=$(sha256sum < "$o/$f" 2>/dev/null | cut -c1-64)
        r=$(jq -c --arg g "$g" --arg f "$f" --arg h "$h" '.areas[$g] = {file: $f, sha: $h}' <<<"$r")
      done < <([ -z "$a" ] || jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$a")
    fi
  fi
  jq -cSn --argjson s "$SWE_SET" --argjson a "$1" --arg m "$2" --argjson c "$c" --argjson p "$p" --argjson r "$r" \
    '{set: ($s | {dataset, revision, swebench}), limits: ($s | {cpus, memory, taskTimeout}), arm: ($a | del(.name, .label, .revision, .why)),
      model: (if $m == "" then null else $m end)} + (if $a.kind == "conveyor" then {control: $c, pack: $p, rules: $r} else {} end)'
}
# The key an arm's results are kept under: its preflight key (swe_armkey) with the first 12 of the sha256 of its
# inputs (swe_inputs) in it, before the engine commit for a conveyor arm (<fp>-<commit>, <arm>-<fp>-<commit>: with no
# commit given, the part before the commit, the Board's keyPrefix), else at the end (<arm>-<fp>, <arm>-<model>-<fp>).
# A result is kept with its inputs, and reused only while they are the same (swe_reused).
swe_reskey() { # <arm json> <engine commit, conveyor kind> <model> <inputs json>
  local f k n; f=$(jq -cS . <<<"$4" | sha256sum | cut -c1-12); n=$(jq -r .name <<<"$1")
  if [ "$(jq -r .kind <<<"$1")" = conveyor ]; then [ "$n" = conveyor ] && k=$f-$2 || k=$n-$f-$2
  else k=$(swe_armkey "$1" '' "$3")-$f; fi
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
# there (the sandbox's control record, swe_ctl, as swe_pack writes it: the builder, the reviewer, the judge only when
# it is on, and the fix and testFix seats; the Tests seat serves `testaction`, which the run does not start), so a
# Conveyor arm on Claude seats needs no Codex login. The seats are worked out on the models the engine in the
# container offers, not this host's: the task's pack (swe_pack: the project's models.allowed, with a host arm's seats
# in it) when it lists some, else the built-in MODELS0, as the arm's install puts Codex in the container even where
# this host has none. Both are read from the run's copy of them for the arm in use (swe_root, swe_freeze), as the
# sandbox's are: a seat moved while a run goes changes neither.
swe_logins() { # <arm json>
  local c a x='' o PACK=$PACK
  if [ "$(jq -r .kind <<<"$1")" = conveyor ]; then
    swe_root
    c=$(swe_ctl "$1" 2>/dev/null | jq -c .) && [ -n "$c" ] || c=null
    packget models.allowed a 2>/dev/null || a=''
    x=$(jq -r --argjson c "$c" --argjson s "$(jq -c 'if has("revision") then {} else .seats // {} end' <<<"$1")" --argjson d "$MODELS0" "$SEATNOW$JUDGENOW$FIXSEAT"'
        reduce ($s[] | objects | select(.cli != null)) as $x (.; .[$x.cli] = ((.[$x.cli] // []) + [$x.model] | unique)) | (. // $d)
        | ([try seatnow("builder"; $c)] | first) as $b | ([try seatnow("reviewer"; $c)] | first) as $r
        | $b, $r, (if $c.judgeOn == true and $r != null then [try judgenow($c; $r)] | first else null end), fixseat($c; "fix"; $b), fixseat($c; "testFix"; $b)
        | .agent? // empty' <<<"${a:-null}")
  fi
  jq -r --arg x "$x" '[(.login // [])[], ($x | splits("\n")) | select(IN("claude", "codex"))] | unique | join(" ")' <<<"$1"
}
swe_logindest() { case $1 in claude) echo .claude/.credentials.json ;; codex) echo .codex/auth.json ;; esac; }
# A trial's container: the task's image; the sandbox mounted at its own path (and, for a conveyor arm, the engine's
# version folder, read-only) and nothing else of the host; the settings' CPU and memory limits; run as this user (a
# passwd line names it) with a home that is in the container only. The logins are copied into that home before the
# container starts: they are in this one container, gone when it is removed, and never in an image. The home's
# .gitconfig gives git an identity: the task's image has none, and the engine cannot commit a fix without one.
swe_box() { # <container> <image> <sb> <logins, space-separated> [<engine folder>]
  local h l f m=() rc=0
  [ -z "${5:-}" ] || m=(-v "$5:$5:ro")
  docker create --name "$1" --user "$(id -u):$(id -g)" -e "HOME=$SWE_HOME" --cpus "$(swe_set .cpus)" --memory "$(swe_set .memory)" \
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
  local t l g f o PACK=$PACK; swe_root
  [ "$(jq -r '.rules // "engine"' <<<"$1")" = project ] || return 0
  while IFS= read -r t; do
    l=$(swe_arearules "$t") || { echo "the project's pack could not be read for its area rules"; return; }
    while IFS=$'\t' read -r g f; do
      [ -f "$o/$f" ] && [ -r "$o/$f" ] \
        || { echo "the arm takes the project's rules, and the area rule file $f its pack maps to $g is missing or cannot be read"; return; }
    done < <([ -z "$l" ] || printf '%s\n' "$l")
  done
}
# The task's pack's test.fileCommand. A card runs each test file it adds or changes alone (filecmd(), lib/testrun.sh,
# which adds the file's path at the command's end). A task repository can have no test configuration that Conveyor's
# own runner reads, and then the card's Test step blocked. This command first starts the task's environment (its env in
# the task list, swe_harness.py: the Python that has the task's packages, as test.command starts it), then runs the file
# with pytest when that python3 has pytest, else with python3 alone. test.command stays the task's own. The env runs
# with no arguments: a script it sources is given the function's arguments otherwise, and conda's activate takes the
# first one as the environment to start.
swe_filecmd() { # <task json>
  local e; e=$(jq -r '.env // ""' <<<"$1")
  printf 'swe_pyfile() { local f=("$@"); set --; %sif python3 -c "import pytest" > /dev/null 2>&1; then python3 -m pytest "${f[@]}"; else python3 "${f[@]}"; fi; }; swe_pyfile\n' "${e:+$e || return 1; }"
}
# The pack and control record of a conveyor arm's sandbox: the project's, with the task's test command run in the
# container, the arm's seats (a host arm's models added to models.allowed; a saved arm's are the project's already,
# swe_armsave), its review policy (policy: judgeOn, judgeAlways, rules.P0 to P3) over the record's, and no named
# account: the container has one login of each. The project's per-issue seats (cards) are
# left out: every task is issue 1 there, and a project's own cards["1"] must not change the arm's seats. The arm's
# rules (its rules field): "engine" (the default), the engine version's core rules alone; "project", a copy of the
# project's card rules (.conveyor/card-rules.md) and of each area rule file its pack's areas map, by path glob, to a
# path the task's issue names (the sandbox's issue #1, swe_sandbox: title and body, scanned as cardrules() scans them),
# so the card there gets the rules cardrules() gives a card here (swe_arearules). An area no such path
# matches is left out of the pack, as no card there reads its rule. A rule file the card reads missing or unreadable
# refuses the arm. The project's files are read from the run's copy of them (swe_root, swe_freeze). The pack's
# test.fileCommand is swe_filecmd's.
swe_pack() { # <task json> <sb> <engine's conveyor.sh> <arm json>
  local sb=$2 d=$2/$SWE_MAIN/.conveyor m l g f a e o i=0 ar='{}' PACK=$PACK; m=$(jq -r '.rules // "engine"' <<<"$4"); swe_root
  mkdir -p "$d" "$sb/cards" && : > "$sb/rulings.jsonl" || return 1
  case $m in
    engine) ;;
    project)
      cp -- "$o/.conveyor/card-rules.md" "$d/card-rules.md" 2>/dev/null \
        || { echo "the arm takes the project's rules, and its card rules .conveyor/card-rules.md are missing or cannot be read"; return 1; }
      l=$(swe_arearules "$1") || { echo "the project's pack could not be read for its area rules"; return 1; }
      mkdir -p "$d/area-rules" || return 1
      while IFS=$'\t' read -r g f; do
        i=$((i + 1)); cp -- "$o/$f" "$d/area-rules/$i.md" 2>/dev/null \
          || { echo "the arm takes the project's rules, and the area rule file $f its pack maps to $g is missing or cannot be read"; return 1; }
        ar=$(jq -c --arg g "$g" --arg f ".conveyor/area-rules/$i.md" '.[$g] = $f' <<<"$ar")
      done < <([ -z "$l" ] || printf '%s\n' "$l") ;;
    *) echo "the arm's rules are engine or project, not $m"; return 1 ;;
  esac
  jq --arg t "$(jq -r .cmd <<<"$1")" --arg fc "$(swe_filecmd "$1")" --arg l "$sb/rulings.jsonl" --argjson s "$(jq -c 'if has("revision") then {} else .seats // {} end' <<<"$4")" --argjson ar "$ar" '{owner, labels: ((.labels // {}) + {nonProductAreas: []}), models, review, prices, privacy,
    tunables: ((.tunables // {}) + {closeWait: 0}), rulings: {log: $l}, test: {command: $t, fileCommand: $fc, survey: false}, productPaths: [".conveyor-none/"], linkFromMain: [], checks: [],
    push: {env: {}}, remote: "origin", defaultBranch: "main", landBatch: 1} | with_entries(select(.value != null))
    | if $ar != {} then .areas = $ar else . end
    | reduce ($s[] | objects | select(.cli != null)) as $x (.; .models.allowed[$x.cli] = ((.models.allowed[$x.cli] // []) + [$x.model] | unique))' \
    "$PACK" > "$d/project.json" || { echo "the project's pack could not be read to make the task's pack"; return 1; }
  # The container holds no host file, so the engine there keeps its state in the checkout's own conveyor/state.
  SWE_SST=$sb/$SWE_MAIN/conveyor/state
  mkdir -p "$SWE_SST" && swe_ctl "$4" > "$SWE_SST/control.json" || { echo "the project's control record could not be read"; return 1; }
  # A fix or testFix seat the card's record sets (the arm's, or the project's) that the engine version does not know
  # (its lib/control-defaults.json has no such key: an engine from before those seats) would be passed over there
  # unread, and the card would repair on its builder: the arm is refused.
  e=$(jq -c 'objects' "${3%/conveyor.sh}/lib/control-defaults.json" 2>/dev/null) && [ -n "$e" ] || e='{}'
  f=$(jq -r --argjson e "$e" '[("fix", "testFix") as $k | select(.[$k] != null and ($e | has($k) | not)) | $k] | join(" and ")' "$SWE_SST/control.json") \
    || { echo "the task's control record could not be read"; return 1; }
  [ -z "$f" ] || { echo "the card's $f seat is set (by the arm or the project), and the engine version it runs on has no such seat, so its card would repair on the builder: run the arm on a newer engine"; return 1; }
  # The rules P0 to P3 also keep an issue of that level off the queue (upnext.jq), and the task's issue has no
  # priority label, so the engine reads it as P3: an arm with P3 off (its P3 findings minor) never got its card
  # picked. The issue takes no label while its level's rule is on, else the pack's least urgent priority whose level's
  # rule is on (LEVEL, lib/prompts.sh); an arm whose rules leave no such level is refused.
  packget labels.priorities a && g=$(jq -c --argjson p "$a" '.rules as $r | def on($l): $r[$l] != false;
    if on("P3") then [] else [range($p | length) | select(on("P\([., 3] | min)"))] | last | if . == null then empty else [$p[.]] end end' "$SWE_SST/control.json") \
    || { echo "the project's pack could not be read for its priorities"; return 1; }
  [ -n "$g" ] || { echo "the arm's policy turns off every priority the task's issue can have, so its card would never be picked"; return 1; }
  jq -c --argjson l "$g" '.labels = ($l | map({name: .}))' "$sb/issue.json" > "$sb/issue.json.new" && mv -f "$sb/issue.json.new" "$sb/issue.json" \
    || { rm -f "$sb/issue.json.new"; echo "the task's issue could not be given its priority"; return 1; }
}
# The control record of a conveyor arm's sandbox (swe_pack): the project's, with the arm's seats and review policy over
# it, its queue and per-issue seats emptied, no named account, follow-ups and visible-change asks off, a push on; the
# run's copy of it for the arm in use (SWE_FZ, swe_freeze).
swe_ctl() { # <arm json>
  [ -z "${SWE_FZ:-}" ] || { cat "$SWE_FZ/control.json"; return; }
  ctl | jq --argjson s "$(jq -c '.seats // {}' <<<"$1")" --argjson p "$(jq -c '.policy // {}' <<<"$1")" '.mode = "run" | .held = [] | .order = [] | .startHeld = [] | .start = "queue" | .rules.followups = false | .rules.visible = false
    | .rules.push = true | .cards = {} | del(.account, .reviewAccount) + $s
    | .rules += ($p | with_entries(select(.key | test("^P[0-3]$")))) | . + ($p | with_entries(select(.key | IN("judgeOn", "judgeAlways"))))'
}
SWE_ASK='Fix this issue in the repository in the current folder. Change the code only; do not commit.'
# One trial: the arm builds the task in its container. Prints {sessions, tokens, minutes, steps, cost, fired, why}
# (a conveyor arm's steps keep each line's model and token usage, cost is swe_cost of its card's lines, its live
# records and the reviewer's record swe_watch kept); keeps
# the patch (and a conveyor arm's loop log) in <sb>.h, the trial's own folder on the host, outside the container's
# mount; fails (prints why) only when the container could not be made or the patch read, which says nothing of the
# arm. An arm that does not fire (its install, preflight or command failed, or its output shows no use of its method)
# has fired false and why: that is the arm's failure, never a task not run.
swe_trial() { # <task json> <sb> <arm json> <engine's conveyor.sh, conveyor kind>
  local sb=$2 a=$3 h=$2.h base t0 c rc='' run why='' kind eng='' to b n p=0
  base=$(jq -r .base <<<"$1"); t0=$(date +%s); kind=$(jq -r .kind <<<"$a"); to=$(swe_set .taskTimeout)
  n=conveyor-swe-${SWE_RUN:-check}-$(jq -r .name <<<"$a")-$(jq -r .id <<<"$1"); c=${n//[^A-Za-z0-9_.-]/-}
  { chmod -R u+w "$h"; rm -rf "$h"; } 2>/dev/null; mkdir -m 700 "$h" && : > "$h/out" || return 1
  { printf '%s\n\n' "$SWE_ASK"; jq -r .issue <<<"$1"; } > "$sb/prompt" && jq -r '.exclude // [] | .[]' <<<"$a" >> "$sb/$SWE_MAIN/.git/info/exclude" || return 1
  if [ "$kind" = conveyor ]; then
    swe_pack "$1" "$sb" "$4" "$a" > "$h/pack.err" || { cat "$h/pack.err"; return 1; }
    eng=${4%/conveyor/conveyor.sh}
    # CONVEYOR_BENCH_BOX: the engine runs in the task's container, which is the sandbox, so its Codex sessions run
    # without Codex's own, which cannot start a command there (codexsb(), lib/control.sh).
    run="CONVEYOR_BENCH_BOX=1 CONVEYOR_MAIN=$(printf %q "$sb/$SWE_MAIN") CONVEYOR_CARDS=$(printf %q "$sb/cards") bash $(printf %q "$4") run 1 > $(printf %q "$sb/loop.log") 2>&1"
  else run=$(jq -r .run <<<"$a"); fi
  printf '%s\n' "$c" > "$h/box"; docker rm -f "$c" > /dev/null 2>&1
  swe_ckstep 'Starting the test container'
  swe_box "$c" "$(jq -r .image <<<"$1")" "$sb" "$(swe_logins "$a")" "$eng" > "$h/box.err" 2>&1 \
    || { docker rm -f "$c" > /dev/null 2>&1; echo "its container could not be made: $(cliwords "$(cat "$h/box.err")" | tail -n 2 | paste -sd ' ' -)"; return 1; }
  swe_ckstep 'Installing the arm'
  if ! swe_in "$to" "$c" "$sb/$SWE_MAIN" "$(jq -r '.install // "true"' <<<"$a")" "SWE_SB=$sb" < /dev/null > "$h/install.log" 2>&1; then
    why="its install failed: $(cliwords "$(tail -n 20 "$h/install.log")" | tail -n 2 | paste -sd ' ' -)"
  elif swe_ckstep 'Checking its tools and logins'; ! swe_in 600 "$c" "$sb/$SWE_MAIN" "$(jq -r '.preflight // "true"' <<<"$a")" "SWE_SB=$sb" < /dev/null > "$h/install.log" 2>&1; then
    why="its preflight command failed: $(cliwords "$(tail -n 20 "$h/install.log")" | tail -n 2 | paste -sd ' ' -)"
  else
    swe_ckstep 'Running the trivial task'
    # A run's task shows the step the command is at while it runs (swe_watch, bench/swe.sh).
    swe_in "$to" "$c" "$sb/$SWE_MAIN" "$run" "SWE_SB=$sb" "SWE_PROMPT=$sb/prompt" "SWE_MODEL=${SWE_MODEL:-}" "SWE_EFFORT=$(jq -r '.effort | strings' <<<"$a")" < /dev/null > "$h/out" 2> "$h/err" &
    local j=$!; swe_watch "$j" "$c" "$kind" "$sb"; wait "$j"; rc=$?
    # A command stopped at the task's time limit is the arm's own result: its patch is graded. A conveyor arm's
    # command writes to its loop log, so its why is read from that log below.
    [ "$rc" = 0 ] || [ "$rc" = 124 ] || [ "$kind" = conveyor ] || why="its command failed (exit $rc): $(cliwords "$(tail -n 20 "$h/err" 2>/dev/null; jq -rRn "$NOSTARTSAID" "$h/out" 2>/dev/null)" | tail -n 3 | paste -sd ' ' -)"
  fi
  # What the arm left in the sandbox is read in its container, never by the host: the arm could write every file
  # there, so a host read or write could follow its symlink to a host file, and the checkout's .git/config could make
  # the host's git run the arm's code (a clean filter, an external diff).
  swe_ckstep 'Reading its change'; [ -z "${SWE_TASK:-}" ] || swe_phase 'Reading patch'
  swe_in 600 "$c" "$sb/$SWE_MAIN" 'if [ "$SWE_KIND" = conveyor ]; then git diff --binary --no-ext-diff --no-textconv "$SWE_BASE" refs/heads/main --
    else git add -A && git diff --binary --no-ext-diff --no-textconv --cached "$SWE_BASE" --; fi' "SWE_SB=$sb" "SWE_BASE=$base" "SWE_KIND=$kind" < /dev/null > "$h/patch" 2> /dev/null || p=1
  if [ "$kind" = conveyor ]; then
    swe_in 600 "$c" "$sb" 'cat "$SWE_SB/loop.log"' "SWE_SB=$sb" < /dev/null > "$h/loop.log" 2> /dev/null || rm -f "$h/loop.log"
    [ -z "$rc" ] || [ "$rc" = 0 ] || [ "$rc" = 124 ] \
      || why="its command failed (exit $rc): $(cliwords "$(tail -n 20 "$h/loop.log" 2>/dev/null)" | tail -n 3 | paste -sd ' ' -)"
    swe_in 600 "$c" "$sb" 'cat "$SWE_SST/cards.jsonl"' "SWE_SST=$SWE_SST" < /dev/null > "$h/cards.jsonl" 2> /dev/null || rm -f "$h/cards.jsonl"
    # The live records too: a session the time limit ended before its line was written is priced from them.
    swe_in 600 "$c" / "$SWE_LIVES" "SWE_CARDS=$sb/cards" < /dev/null > "$h/live" 2> /dev/null || rm -f "$h/live"
  fi
  docker rm -f "$c" > /dev/null 2>&1; rm -f "$h/box"
  [ "$p" = 0 ] || return 1
  local secs=$(( $(date +%s) - t0 ))
  if [ "$kind" = conveyor ]; then
    b=$(jq -sc --argjson m "$secs" 'map(select(.issue == 1 and (.step | IN("start", "picked", "worktree", "deps", "brief") | not))) as $s
      | {sessions: ($s | map(select(.step | IN("build", "review", "fix", "rebase"))) | length) + ($s | map(select(.judge | type == "object")) | length),
         tokens: ($s | map((.tokens.claude // 0) + (.tokens.codex // 0) + (.judge.tokens.claude // 0) + (.judge.tokens.codex // 0)) | add // 0),
         minutes: ($m / 6 | round / 10), steps: ($s | map({step, result, reason, time, tokens} + if .step == "review" and .result != "GO" and has("tail") then {tail} else {} end
           + ({model, usage, byModel: .stats.byModel?, judge: (.judge | if type == "object" then {model, usage} else null end)} | with_entries(select(.value != null)))))}' "$h/cards.jsonl" 2>/dev/null) \
      && b=$(jq -c --argjson k "$(cat "$h/cards.jsonl" "$h/live" "$h/reviewer" 2>/dev/null | swe_cost)" '. + {cost: $k}' <<<"$b") \
      || b=$(jq -nc --argjson m "$secs" '{sessions: 0, tokens: 0, minutes: ($m / 6 | round / 10), steps: [], cost: {usd: null, state: "unknown", unpriced: null, basis: {}}}')
    # An engine that built no card (its pack refused, its loop failed) did not fire.
    [ -n "$why" ] || jq -e '.steps | any(.step == "build")' <<<"$b" > /dev/null \
      || why="the engine built no card: $(cliwords "$(tail -n 3 "$h/loop.log" 2>/dev/null)" | paste -sd ' ' - | head -c 400)"
  else
    # The output file is there (empty) when its install or preflight failed: the trial then failed with that why.
    b=$(jq -Rsc --argjson m "$secs" --argjson n "$(jq '.sessions // 1' <<<"$a")" "def fired: $(jq -r '.fired // "true"' <<<"$a"); def tok: $(jq -r '.tokens // "0"' <<<"$a");
      [splits(\"\\n\") | fromjson? | objects] as \$o | {sessions: \$n, tokens: ((\$o | tok) // 0), minutes: (\$m / 6 | round / 10), steps: [], fired: ((\$o | fired) == true)}" "$h/out") \
      || { echo "the arm's fired or tokens filter is not valid jq"; return 1; }
    # An agent reports no usage by model: its cost is unknown.
    b=$(jq -c '. + {cost: {usd: null, state: "unknown", unpriced: .sessions, basis: {}}}' <<<"$b")
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
# before, by swe_setup, in both callers). Prints nothing when it passed, else what is missing. Run in a check
# (swe_check, swe_arms), which keeps its answer in the check's record.
swe_preflight() { # <arm json> <image> <engine's conveyor.sh, conveyor kind>
  local a=$1 n why='' l f t sb b
  n=$(jq -r .name <<<"$a")
  swe_ckstep 'Setting up the trivial task'
  if jq -e '.offered == false' <<<"$a" > /dev/null; then why="not offered: $(jq -r '.why // "no reason given"' <<<"$a")"
  else
    for l in $(swe_logins "$a"); do
      f=$(swe_login "$l") && [ -s "$f" ] && continue
      why="no $l login on this machine: ${f:+${f/#$HOME/\~} is missing; }sign in with $l (on macOS a Claude login kept in the Keychain has no such file)"; break
    done
  fi
  if [ -z "$why" ]; then
    sb=$SWE_DIR/check/$n
    if ! t=$(swe_checktask "$2") || ! swe_sandbox "$t" "$sb" 2> /dev/null; then why="the trivial task could not be set up"
    elif ! b=$(swe_trial "$t" "$sb" "$a" "$3"); then why=$b
    elif ! jq -e .fired <<<"$b" > /dev/null; then why="on the trivial task, $(jq -r .why <<<"$b")"
    elif [ ! -s "$sb.h/patch" ]; then why="it ran the trivial task headless but changed no file"; fi
    { chmod -R u+w "$sb" "$sb.h"; rm -rf "$sb" "$sb.h"; } 2>/dev/null
  fi
  printf '%s' "$why"
}
# A check's record, preflight/<arm>/<key>.json (key: swe_armkey), written when the check is admitted, before its
# setup (state "checking", its step written again as each step starts: swe_ckstep), and when it ends ("ready" or
# "failed", with why), a failure of its setup (Docker, the harness, the task list, the image, the engine) too. Fields:
# id (the check's ID), arm, key, state, step, ok, why, started, at and epoch (when it ended; while it runs, when it
# started), pid (the process that runs it, while it runs), spec (the arm's JSON), logins (swe_logins), image (null
# until known), limits and set (of the settings in force, swe_settings). One check of an arm runs at a time, as they
# share its sandbox: it holds the arm's lock, preflight/<arm>/lock, until it ends; another request of the arm waits for
# it and takes its answer when it was of the same request (swe_ckshared).
# A check's request, as its record is compared with: key, spec, logins, image (null when not known yet), limits and
# set (the task set: dataset, revision and seed).
swe_checkq() { # <arm json> <key> <image, empty when not known>
  jq -cn --argjson a "$1" --arg k "$2" --arg l "$(swe_logins "$1")" --arg i "$3" --argjson lim "$(swe_set '{cpus, memory, taskTimeout}')" \
    --argjson set "$(swe_set '{dataset, revision, seed}')" '{key: $k, spec: $a, logins: $l, image: (if $i == "" then null else $i end), limits: $lim, set: $set}'
}
# Whether a record is of a request but for its image (samereq: a check that runs, whose image is not known yet), whether
# it answers the request (samecheck: the same image too), and whether it is a pass the request can take (checkok: from
# the last day). The one readiness decision of Start (swe_ready), a check that waited for another (swe_ckshared),
# History and `bench swe arms` (swe_checkstate).
SWE_CHECKOK='def samereq($q): .key == $q.key and .spec == $q.spec and .logins == $q.logins and .limits == $q.limits and .set == $q.set;
  def samecheck($q): samereq($q) and .image != null and .image == $q.image;
  def checkok($q; $now): .ok == true and samecheck($q) and $now - .epoch < 86400;'
# Takes the lock of a request's arm (SWE_CKFD): returns 1 with none when another check of the arm holds it, unless
# told to wait for it.
swe_cklock() { # <request json> [wait]
  local d fd; d=$SWE_DIR/preflight/$(jq -r .spec.name <<<"$1")
  mkdir -p "$d" && exec {fd}>>"$d/lock" || return 2
  if [ -n "${2:-}" ]; then flock "$fd"; else flock -n "$fd"; fi || { exec {fd}>&-; return 1; }
  SWE_CKFD=$fd
}
# With the lock taken after a wait: prints the why of the record of the request's key (nothing for a pass) when a
# check of the same request ended since <since> (the one waited for, or one after it): the two requests shared it,
# and the caller frees the lock. Else returns 1: the lock is for the caller's own check.
swe_ckshared() { # <request json> <since: epoch seconds>
  local f; f=$SWE_DIR/preflight/$(jq -r '"\(.spec.name)/\(.key)"' <<<"$1").json
  jq -er --argjson q "$1" --argjson s "$2" "$SWE_CHECKOK"'select(.state != "checking" and .epoch >= $s and samecheck($q)) | .why // ""' "$f" 2>/dev/null
}
# Writes the record of the check that holds the lock (SWE_CKF), in state checking at <step>; SWE_CKID is its ID.
swe_ckopen() { # <request json> <step>
  local at; SWE_CKID=k$(date -u +%Y%m%dT%H%M%S)-$$-$RANDOM; at=$(swe_now)
  SWE_CKF=$SWE_DIR/preflight/$(jq -r '"\(.spec.name)/\(.key)"' <<<"$1").json
  swe_put "$SWE_CKF" "$(jq -c --arg id "$SWE_CKID" --arg s "$2" --arg at "$at" --argjson e "$(date +%s)" --argjson p "$$" \
    '{id: $id, arm: .spec.name, key, state: "checking", step: $s, ok: false, why: null, started: $at, at: $at, epoch: $e, pid: $p, spec, logins, image, limits, set}' <<<"$1")"
}
swe_ckstep() { [ -z "${SWE_CKF:-}" ] || swe_put "$SWE_CKF" "$(jq -c --arg s "$1" '.step = $s' "$SWE_CKF")"; } # <step>: of the check running (SWE_CKF), else nothing
# Ends the check (SWE_CKF): ready when <why> is empty, else failed with it, on <image> when given; frees its lock.
swe_ckend() { # <why> [<image>]
  swe_put "$SWE_CKF" "$(jq -c --arg w "$1" --arg i "${2:-}" --arg at "$(swe_now)" --argjson e "$(date +%s)" \
    '.state = (if $w == "" then "ready" else "failed" end) | .ok = ($w == "") | .why = (if $w == "" then null else $w end) | .step = null | .at = $at | .epoch = $e
     | del(.pid) | if $i == "" then . else .image = $i end' "$SWE_CKF")"
  exec {SWE_CKFD}>&-
}
# One check of an arm whose setup is done (Docker, harness, image, engine): it runs the preflight, or takes the answer
# of the check of the same request that runs now. Prints nothing when the arm passed, else why.
swe_check() { # <arm json> <key> <image> <engine's conveyor.sh, conveyor kind>
  local q s w SWE_CKF='' SWE_CKFD='' SWE_CKID=''; q=$(swe_checkq "$1" "$2" "$3") && s=$(date +%s) || return 1
  if ! swe_cklock "$q"; then
    swe_cklock "$q" wait || { printf 'its check could not be started'; return; }
    if w=$(swe_ckshared "$q" "$s"); then exec {SWE_CKFD}>&-; printf '%s' "$w"; return; fi
  fi
  swe_ckopen "$q" 'Setting up the trivial task' || { exec {SWE_CKFD}>&-; printf 'its check record could not be written'; return; }
  w=$(swe_preflight "$1" "$3" "$4"); swe_ckend "$w"; printf '%s' "$w"
}
# An arm can be picked once its preflight passed: a pass of the request (checkok) is taken, else the check runs now.
# Prints nothing when the arm is ready, else why not.
swe_ready() { # <arm json> <key> <image> <engine's conveyor.sh, conveyor kind>
  jq -e --argjson q "$(swe_checkq "$1" "$2" "$3")" --argjson now "$(date +%s)" "$SWE_CHECKOK"'checkok($q; $now)' "$SWE_DIR/preflight/$(jq -r .name <<<"$1")/$2.json" > /dev/null 2>&1 \
    || swe_check "$@"
}
# An arm's check state, as History and `bench swe arms` show it, as {state, why, step, at, id}: of the record of <key>
# (the one a run on these settings takes: main's engine for a conveyor arm), else of the arm's latest record. checking
# (with its step) while the process that runs it is there (failed once it is gone), failed, ready (a pass Start takes,
# checkok), expired (one that passed more than a day ago), changed (one of another key, arm file, logins, image,
# limits or task set), unchecked or not offered.
swe_checkstate() { # <arm json> <key, empty when not known> <image>
  local d r p alive=false; d=$SWE_DIR/preflight/$(jq -r .name <<<"$1")
  if [ -n "$2" ] && [ -s "$d/$2.json" ]; then r=$(jq -c . "$d/$2.json" 2>/dev/null)
  else r=$(cat "$d"/*.json 2>/dev/null | jq -sc 'sort_by(.epoch) | last // null'); fi
  [ -n "$r" ] || r=null
  p=$(jq -r 'select(.state == "checking") | .pid // empty' <<<"$r") && [ -n "$p" ] && kill -0 "$p" 2>/dev/null && alive=true
  jq -c --argjson r "$r" --argjson q "$(swe_checkq "$1" "$2" "$3")" --argjson now "$(date +%s)" --argjson alive "$alive" "$SWE_CHECKOK"'
    if .offered == false then {state: "not offered", why: (.why // "no reason given")}
    elif $r == null then {state: "unchecked"}
    elif $r.state == "checking" then (if $alive then {state: "checking", step: $r.step} else {state: "failed", why: "the check stopped before it ended"} end)
    elif $r.ok != true then {state: "failed", why: $r.why}
    elif $r | checkok($q; $now) then {state: "ready"}
    elif $r | checkok($q; $r.epoch) then {state: "expired"}
    else {state: "changed"} end
    | {state, why: (.why // null), step: (.step // null), at: ($r.at // null), id: ($r.id // null)}' <<<"$1"
}
# The key and the image an arm's state is read for (swe_checkstate): a run's on swe.json's settings, main's engine
# for a conveyor arm (read once, SWE_MAINC: empty when it cannot be read), and the first task's image of the settings'
# task list ("-" with no list made yet: no check matched an image of it). Two lines.
swe_mainc() { [ -n "${SWE_MAINC+x}" ] || { SWE_MAINC=''; ! swe_resolve main 2> /dev/null || SWE_MAINC=$SWE_COMMIT; }; }
swe_armnow() { # <arm json>
  local m=''
  if [ "$(jq -r .kind <<<"$1")" = conveyor ]; then
    swe_mainc
    if [ -n "$SWE_MAINC" ]; then swe_armkey "$1" "$SWE_MAINC" ''; else echo; fi
  else m=$(jq -r '.model // ""' <<<"$1"); [ "$m" != builder ] || m=$(swe_solomodel); swe_armkey "$1" '' "$m"; fi
  head -n 1 "$(swe_list "$(swe_set .revision)" "$(swe_set .seed)")" 2>/dev/null | jq -r '.image // "-"' 2>/dev/null | grep . || echo -
}
# `bench swe arms`: each arm with its preflight state (its latest preflight); `bench swe arms check <arm>...` runs
# those arms' preflights now, a conveyor arm's on main's engine (an arm is a host arm's name or a saved revision's ID),
# in containers of the --settings' limits on the image of their task set's first task (swe_settings);
# `bench swe arms save <name> <spec>` keeps a saved arm and prints its ID (swe_armsave); `bench swe arms show <id>`
# prints that revision as it was saved.
SWE_ARMSUSE='usage: conveyor.sh bench swe arms [check [--settings <json>] <arm>...] | bench swe arms save <name> <spec json> | bench swe arms show <id>'
swe_arms() { # [check [--settings <json>] <arm>... | save <name> <spec json> | show <id>]
  local n a r tf img eng k bad=0 gc='' ga=''
  case ${1:-} in
    save) [ $# = 3 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }; swe_armsave "$2" "$3"; return ;;
    show) [ $# = 2 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }
      [[ $2 =~ $SWE_ARMID ]] && jq -ce 'objects' "$SWE_DIR/arms/$2.json" 2>/dev/null || { echo "conveyor: no saved arm $2" >&2; return 1; }; return ;;
  esac
  if [ "${1:-}" = check ]; then
    shift; [ "${1:-}" != --settings ] || { [ $# -ge 2 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }; swe_settings "$2" || return; shift 2; }
    [ $# -gt 0 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }
    local names=() as=() qs=() fs=() fds=() js=() x=() since i SWE_CKF='' SWE_CKFD='' SWE_CKID='' SWE_CKPREP='' SWE_CKIMG='' SWE_CKWHY=''
    mapfile -t names < <(printf '%s\n' "$@" | awk '!s[$0]++')
    # A preflight starts a model session on the trivial task: the usage guard holds it back as it holds a run. An arm
    # or saved revision that is not there refuses the whole request, as a run's does, before any check is admitted.
    for n in "${names[@]}"; do a=$(swe_arm "$n") || { echo "conveyor: no arm $n: \`conveyor.sh bench swe arms\` lists them" >&2; return 1; }; case $(swe_guards "$a") in conveyor) gc=1 ;; agent) ga=1 ;; esac; done
    ! swe_held "$gc" "$ga" || { echo "conveyor: the usage guard is reached: no preflight starts while it stands" >&2; return 1; }
    # Each arm's check is admitted at once, its record written (checking) before any setup, and its ID printed: an arm
    # whose check runs now (another request's) waits for it. A conveyor arm checks on main's engine (its key names it;
    # "main" when main cannot be read, which its check then fails on).
    since=$(date +%s)
    for n in "${names[@]}"; do
      a=$(swe_arm "$n") || { echo "conveyor: no arm $n: \`conveyor.sh bench swe arms\` lists them" >&2; bad=1; continue; }
      [ "$(jq -r .kind <<<"$a")" != conveyor ] || swe_mainc
      mapfile -t x < <(swe_armnow "$a"); k=${x[0]:-}; [ -n "$k" ] || k=$(swe_armkey "$a" main '')
      as+=("$a"); qs+=("$(swe_checkq "$a" "$k" '')")
      if swe_cklock "${qs[-1]}"; then
        SWE_CKID=''; swe_ckopen "${qs[-1]}" 'Checking Docker and the harness' || SWE_CKF=''
        fs+=("$SWE_CKF"); fds+=("$SWE_CKFD"); js+=(''); [ -z "$SWE_CKF" ] || echo "$n: checking $SWE_CKID"
      else
        fs+=(''); fds+=('')
        # The ID of the check that runs only when it is of this request (its image is not known yet): this request
        # joins it (js: that ID); else it waits for it (js: -) and then prints its own check's ID.
        r=$(jq -r --argjson q "${qs[-1]}" "$SWE_CHECKOK"'select(.state == "checking" and samereq($q)) | .id' "$SWE_DIR/preflight/$n/$k.json" 2>/dev/null)
        js+=("${r:--}")
        if [ -n "$r" ]; then echo "$n: checking $r"; else echo "$n: waiting for the check of the arm that runs now"; fi
      fi
    done
    # The admitted checks, then each that waited: one that joined a check takes that check's answer, whatever it
    # failed on (its image too); another's answer is the check it waited for when that one was of the same request on
    # the same image, the first task's of its own task list (swe_ckprep, swe_ckshared); else it is admitted then and
    # runs its own (as is one whose joined check stopped before it ended).
    for i in "${!as[@]}"; do [ -z "${js[i]}" ] || continue; swe_armcheck "$i" || bad=1; done
    for i in "${!as[@]}"; do
      [ -n "${js[i]}" ] || continue
      n=$(jq -r .name <<<"${as[i]}")
      SWE_CKFD=''; swe_cklock "${qs[i]}" wait || { echo "$n: failed: its check could not be started"; bad=1; continue; }
      if [ "${js[i]}" != - ] && r=$(jq -er --arg id "${js[i]}" 'select(.id == $id and .state != "checking") | .why // ""' \
        "$SWE_DIR/preflight/$n/$(jq -r .key <<<"${qs[i]}").json" 2>/dev/null); then exec {SWE_CKFD}>&-
        if [ -z "$r" ]; then echo "$n: ready"; else echo "$n: failed: $r"; bad=1; fi; continue
      fi
      ! swe_ckprep || qs[i]=$(swe_checkq "${as[i]}" "$(jq -r .key <<<"${qs[i]}")" "$SWE_CKIMG")
      if r=$(swe_ckshared "${qs[i]}" "$since"); then exec {SWE_CKFD}>&-
        if [ -z "$r" ]; then echo "$n: ready"; else echo "$n: failed: $r"; bad=1; fi; continue
      fi
      SWE_CKF=''; swe_ckopen "${qs[i]}" 'Checking Docker and the harness' || SWE_CKF=''
      [ -z "$SWE_CKF" ] || echo "$n: checking $SWE_CKID"
      fs[i]=$SWE_CKF; fds[i]=$SWE_CKFD; swe_armcheck "$i" || bad=1
    done
    return "$bad"
  fi
  [ $# = 0 ] || { echo "$SWE_ARMSUSE" >&2; return 2; }
  local x
  for n in $(swe_armnames); do
    a=$(swe_arm "$n") || { echo "$n: its file is not a JSON object"; continue; }
    [ "$(jq -r .kind <<<"$a")" != conveyor ] || swe_mainc
    mapfile -t x < <(swe_armnow "$a")
    r=$(swe_checkstate "$a" "${x[0]}" "${x[1]}")
    jq -r --argjson r "$r" '. as $a | "\(.name) (\(.label // .name), \(.kind)): " + ($r | if .state == "not offered" then "not offered: \(.why)"
      elif .state == "unchecked" then "not checked: `conveyor.sh bench swe arms check \($a.name)` runs its preflight"
      elif .state == "checking" then "checking (\(.id)): \(.step)" elif .state == "ready" then "ready (checked \(.at))"
      elif .state == "expired" then "expired: its last check passed more than a day ago (\(.at))"
      elif .state == "changed" then "not checked since its file, logins, engine, image, limits or task set changed" else "failed (\(.at // "no time")): \(.why)" end)' <<<"$a"
  done
}
# One check of `bench swe arms check` that holds its arm's lock (its place i in the caller's as, qs, fs and fds):
# the setup every check of the command shares, done once (swe_ckprep), then main's engine for a conveyor arm, then
# the preflight. Ends its record and prints "<arm>: ready" or "<arm>: failed: <why>"; returns 1 when it failed.
swe_armcheck() { # <i>
  local a=${as[$1]} n r='' eng='' m; n=$(jq -r .name <<<"$a")
  SWE_CKF=${fs[$1]} SWE_CKFD=${fds[$1]}
  if [ -z "$SWE_CKF" ]; then exec {SWE_CKFD}>&-; echo "$n: failed: its check record could not be written"; return 1; fi
  swe_ckprep "${fs[@]}" || r=$SWE_CKWHY
  if [ -z "$r" ] && [ "$(jq -r .kind <<<"$a")" = conveyor ]; then
    swe_ckstep "Installing main's engine"
    if [ -z "$SWE_MAINC" ]; then r="main's engine could not be read from its repository"
    elif installed "$SWE_MAINC" || install "$SWE_MAINC" "$(swe_src)" > /dev/null; then eng=$VERSIONS/$SWE_MAINC/conveyor/conveyor.sh
    else r="main's engine could not be installed"; fi
  fi
  if [ -z "$r" ]; then
    SWE_MODEL=''; [ "$(jq -r .kind <<<"$a")" = conveyor ] || { m=$(jq -r '.model // ""' <<<"$a"); [ "$m" != builder ] || m=$(swe_solomodel); SWE_MODEL=$m; }
    r=$(swe_preflight "$a" "$SWE_CKIMG" "$eng")
  fi
  swe_ckend "$r" "$SWE_CKIMG"; fs[$1]=''; fds[$1]=''; SWE_CKF=''
  if [ -z "$r" ]; then echo "$n: ready"; else echo "$n: failed: $r"; return 1; fi
}
# The setup the checks of `bench swe arms check` share, done once (SWE_CKPREP): Docker and the harness (swe_setup),
# then the task list of the settings and its first task's image, fetched, as a run's. Sets SWE_CKIMG, the image, and
# SWE_CKWHY, empty, else what failed (said on stderr too). Each step goes in the records named (swe_ckstep).
swe_ckprep() { # <record file>...
  local f e tf
  [ -z "${SWE_CKPREP:-}" ] || { [ -z "$SWE_CKWHY" ]; return; }
  SWE_CKPREP=1 SWE_CKIMG='' SWE_CKWHY=''
  SWE_CKWHY=$(swe_setup 2>&1) || { echo "$SWE_CKWHY" >&2; SWE_CKWHY=${SWE_CKWHY#conveyor: }; return 1; }
  for f; do [ -z "$f" ] || SWE_CKF=$f swe_ckstep 'Reading the task list'; done
  e=$(mktemp) || { SWE_CKWHY='the task list could not be read'; return 1; }
  tf=$(swe_tasks 2> "$e") || { cat "$e" >&2; SWE_CKWHY=$(tail -n 1 "$e"); SWE_CKWHY=${SWE_CKWHY#conveyor: }; rm -f "$e"; return 1; }
  rm -f "$e"; SWE_CKIMG=$(head -n 1 "$tf" | jq -r .image)
  for f; do [ -z "$f" ] || SWE_CKF=$f swe_ckstep 'Fetching the test image'; done
  swe_h image "$SWE_CKIMG" > /dev/null 2>&1 || { SWE_CKWHY="the base image $SWE_CKIMG could not be fetched"; echo "conveyor: $SWE_CKWHY" >&2; return 1; }
  for f; do [ -z "$f" ] || SWE_CKF=$f swe_ckstep 'Waiting for the arms named before it'; done
}
