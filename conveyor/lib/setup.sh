# SPDX-License-Identifier: Apache-2.0
# /conveyor-belt:setup (plan sections 7 and 9), run by the plugin copy in the project's checkout (MAIN), safe to run
# again: it changes only what is not there yet.
# The pack, when there is none: the owner, the product paths and the test command have no safe default and are passed
# in (none passed: it says which it needs and writes nothing); test.full, the full test suite the Board's Push landed
# runs, is the test command too (given no list, it runs whole), so a new install can push what it lands;
# test.slowIssues is false (it files nothing: the test
# rules, test.rules, replace it, and with no test.rules their switch is off and no rule is on); every other field is PACK0's, the default branch
# origin's (never the checked-out branch, which may be a feature branch: when origin's cannot be read, nothing is
# written). A pack already there is never rewritten: one that fails the check stops setup.
# The plugin, when the pack names none: the plugin's releases, followed (plugin.follow), or with --pin the commit of
# the plugin copy that runs this. A plugin already named (a pack following main too) is never changed. Then the pinned
# commit is installed (install(): a verified install is left as it is), or the followed engine is taken (take()), and each label the pack names
# that the repo lacks is created (GitHub's label names are not case-sensitive), through gh_write.
PACK0='{labels: {built: "awaiting-deploy", followup: "conveyor-followup", type: "bug", priorities: ["P0", "P1", "P2"],
    areaPrefix: "area:", nonProductAreas: []},
  linkFromMain: [], push: {env: {}}, remote: "origin",
  models: {allowed: {claude: ["claude-opus-5-5", "claude-fable-5-2", "claude-sonnet-5-5", "claude-haiku-5-5"], codex: ["gpt-6.1-sol", "gpt-6-astra"],
    "claude-reviewer": ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-2"]}},
  privacy: {mode: "public"}}'
# The question "Run a first test-speed survey now?" (conveyor/README.md, The first survey): answered by --survey yes|no,
# and asked, as the pack's answers are (exit 2, nothing written), while the pack has no saved answer
# (test.firstSurvey); a saved answer is not asked again unless --survey is given. Once the labels are there, yes files
# one survey issue (firstsurvey(), lib/survey.sh) and no files none; then the answer is saved, so a filing that failed
# leaves it unsaved and the question asked again.
# With --foreman it then sets up Foreman mode (foreman/foreman.sh setup), which `conveyor.sh foreman` starts.
# Its last line says that landed cards wait for the Board's Push landed: the control record's push rule is off by
# default (lib/control-defaults.json). A pack with no test.full (one setup did not write) has no Push landed: the line
# says to add one.
# Matt Pocock's skills, the plugin /conveyor-belt:plan reads (MPS, from the official marketplace), are a requirement:
# setup installs them for the user when Claude Code's record of installed plugins (in CLAUDE_CONFIG_DIR, default
# ~/.claude) has none, and doctor names them missing until it has.
MPS=mattpocock-skills@claude-plugins-official
mpsinstalled() { jq -e --arg p "$MPS" '.plugins[$p] | type == "array" and length > 0' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json" >/dev/null 2>&1; }
setup() { # [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--pin] [--foreman]
  local owner='' test='' prods=() need=() b p f have l n x fm='' pin='' sv='' first full
  local ask='--survey <yes or no: run a first test-speed survey now?>'
  while [ $# -gt 0 ]; do
    [ "$1" != --foreman ] || { fm=1; shift; continue; }
    [ "$1" != --pin ] || { pin=1; shift; continue; }
    case $1 in --owner) owner=${2-} ;; --product) prods+=("${2-}") ;; --test) test=${2-} ;;
      --survey) sv=${2-}; [[ $sv == yes || $sv == no ]] || { set -- x; break; } ;; *) set -- x; break ;; esac
    [ $# -ge 2 ] || { set -- x; break; }; shift 2
  done
  [ $# = 0 ] || { echo "usage: conveyor.sh setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--pin] [--foreman]" >&2; return 2; }
  if [ -e "$PACK" ]; then
    [ -n "$sv" ] || { packget test.firstSurvey first || return 1; [ -n "$first" ] || { echo "conveyor: setup needs: $ask" >&2; return 2; }; }
  else
    [ -n "$owner" ] || need+=("--owner <whose yes a visible change needs>")
    [ ${#prods[@]} -gt 0 ] || need+=("--product <a path prefix of product code> (one for each)")
    [ -n "$test" ] || need+=("--test <the command that runs a change's tests>")
    [ -n "$sv" ] || need+=("$ask")
    [ ${#need[@]} = 0 ] || { printf 'conveyor: %s has no pack; setup needs:%s\n' "$MAIN" "$(printf ' %s;' "${need[@]}")" >&2; return 2; }
    b=$(git symbolic-ref --short -q refs/remotes/origin/HEAD) && b=${b#origin/} \
      || b=$(timeout 60 git ls-remote --symref origin HEAD 2>/dev/null | awk '$1 == "ref:" && $3 == "HEAD" {sub("^refs/heads/", "", $2); print $2}')
    [ -n "$b" ] || { echo "conveyor: origin's default branch could not be read; add the remote origin (git remote add origin <url>), then run setup again" >&2; return 1; }
    mkdir -p "$(dirname "$PACK")" && jq -n --arg o "$owner" --arg t "$test" --arg b "$b" "$PACK0"' + {owner: {name: $o}, productPaths: $ARGS.positional,
        test: {command: $t, full: $t, slowIssues: false}, defaultBranch: $b}' --args "${prods[@]}" > "$PACK.new" \
      && "$HERE/lib/pack.sh" check "$PACK.new" && mv "$PACK.new" "$PACK" || { rm -f "$PACK.new"; return 1; }
    echo "conveyor: wrote the pack $PACK"
  fi
  packget plugin.commit p plugin.follow f || return 1
  if [ -z "$p$f" ] && [ -n "$pin" ]; then
    p=$(git -C "$HERE" rev-parse HEAD) && jq --arg c "$p" '.plugin = {commit: $c}' "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pin could not be written" >&2; return 1; }
    echo "conveyor: pinned Conveyor commit $p"
  elif [ -z "$p$f" ]; then
    f=releases; jq '.plugin = {follow: "releases"}' "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's plugin could not be written" >&2; return 1; }
    echo "conveyor: the project follows the plugin's releases"
  fi
  if [ -n "$f" ]; then take && enginepin p && [ -n "$p" ] || { echo "conveyor: no commit of the plugin's $f is taken on this machine; conveyor.sh doctor says why" >&2; return 1; }
  else install "$p" || return 1; fi
  mpsinstalled || { timeout 300 claude plugin install "$MPS" && mpsinstalled && echo "conveyor: installed the plugin $MPS, for /conveyor-belt:plan"; } \
    || { echo "conveyor: the plugin $MPS could not be installed (claude plugin install $MPS)" >&2; return 1; }
  # A virtualenv with no pip is what python3 -m venv leaves when ensurepip fails (no python3-venv): it is made again.
  { "$BOARD_VENV/bin/python3" -c 'import pip' 2>/dev/null || python3 -m venv --clear "$BOARD_VENV"; } \
    && "$BOARD_VENV/bin/python3" -m pip install -q --require-hashes -r "$BOARD_REQ" \
    || { echo "conveyor: the Board's virtualenv $BOARD_VENV could not be filled from $BOARD_REQ" >&2; return 1; }
  packget labels l && l=$(jq -r '[.built, .followup, .type] + .priorities + .nonProductAreas | unique[]' <<<"$l") || return 1
  have=$(timeout 60 gh label list --limit 10000 --json name --jq '.[].name') \
    || { echo "conveyor: the repo's labels could not be read (conveyor.sh doctor says why)" >&2; return 1; }
  while IFS= read -r n; do
    [ -z "$n" ] || grep -qixF -- "$n" <<<"$have" || { gh_write label create -- "$n" >/dev/null && have+=$'\n'$n && echo "conveyor: created the label $n"; } || return 1
  done <<<"$l"
  if [ -n "$sv" ]; then
    [ "$sv" = no ] || { names && firstsurvey; } || return 1
    jq --argjson a "$([ "$sv" = yes ] && echo true || echo false)" '.test.firstSurvey = $a' "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the answer to the first test-speed survey could not be saved in the pack" >&2; return 1; }
    echo "conveyor: saved the answer to the first test-speed survey ($sv) as the pack's test.firstSurvey"
  fi
  timinghint || return 1
  # The default state folder, conveyor/state in the checkout, is never committed: git's exclude file for the
  # repository (read by every worktree of it, as deps() in lib/push.sh uses it) names it, once.
  x=$(git -C "$MAIN" rev-parse --path-format=absolute --git-path info/exclude) && mkdir -p "${x%/*}" \
    && { grep -qxF /conveyor/state/ "$x" 2>/dev/null || { { [ ! -s "$x" ] || [ -z "$(tail -c 1 "$x")" ] || echo >> "$x"; } && echo /conveyor/state/ >> "$x" && echo "conveyor: wrote /conveyor/state/ in git's exclude file $x, so git leaves out the state folder"; }; } \
    || { echo "conveyor: the state folder conveyor/state/ could not be added to git's exclude file" >&2; return 1; }
  hostadd || return 1
  [ -z "$fm" ] || CONVEYOR_MAIN=$MAIN bash "$HERE/foreman/foreman.sh" setup || return 1
  packget test.full full || return 1
  echo "conveyor: landed cards wait for Push landed on the Board until push is turned on in the Rules tab$([ -n "$full" ] || echo "; Push landed needs the pack's test.full, the full test suite: add it")"
}
# A test command that runs a shell script of the project (a word of it ending in .sh that is a file, from the
# checkout's root) with no `TESTRUN sec` and no testtime.sh in it: its cards record no test times. Setup says how to
# wrap each test file's run with tools/testtime.sh (conveyor/README.md, The CPU budget of a test file), each run; it
# never changes the project's script.
timinghint() {
  local cmd w p ws=()
  packget test.command cmd || return 1
  read -ra ws <<<"$cmd"
  for w in "${ws[@]}"; do
    w=${w//[\"\']/}; w=${w%%[;&|)]*}; [[ $w == *.sh ]] || continue
    p=$w; [[ $p == /* ]] || p=$MAIN/$p
    [ -f "$p" ] && ! grep -qE 'TESTRUN sec|testtime\.sh' "$p" || continue
    echo "conveyor: the test command runs $w, which prints no \`TESTRUN sec\` lines, so cards record no test times."
    echo "  If it runs the test files one by one, copy $HERE/tools/testtime.sh into the project and wrap each file's run"
    echo "  with it, writing its line to the script's log in \$CONVEYOR_TEST_LOG before the file's \`-- ok|FAIL <file>\` line:"
    echo "    ./testtime.sh \"\$f\" -- <the file's command> > \"\$out\" 2>&1; rc=\$?; cat \"\$out\"; grep '^TESTRUN sec' \"\$out\" >> \"\$CONVEYOR_TEST_LOG/<its log>\""
    echo "  conveyor/README.md, The CPU budget of a test file, says more."
  done
}
# The project joins the machine's Conveyor: a record {repo, main} in the host file (made, as {}, when there is none),
# named for its checkout's folder, unless a record already names this checkout. A name another record has is not
# taken: setup stops and says so. Records are only added, never reordered, so no project's state folder moves.
# Under the machine's lock, read and written whole through a file of its own: two at once never lose one's record.
# With `checkout`, the project runs from its own checkout's code (the plugin's own belt: lib/machine.sh, projects):
# its record says so ("engine": "checkout"), the record already there too.
hostadd() { mlocked hostput "$@"; }
hostput() { # [checkout]
  local p n t i e=${1:-}
  p=$(cd "$MAIN" && pwd -P) || return 1
  [ -e "$HOST" ] || { mkdir -p "${HOST%/*}" && echo '{}' > "$HOST"; } || return 1
  jq -e 'type == "object" and (.records == null or (.records | type == "array"))' "$HOST" >/dev/null 2>&1 \
    || { echo "conveyor: the host file $HOST does not read as an object with a records list: this project is not added to the machine's Conveyor" >&2; return 1; }
  while IFS=$'\t' read -r i n; do
    [ "$(cd "$n" 2>/dev/null && pwd -P)" = "$p" ] || continue
    [ -n "$e" ] && ! jq -e --argjson i "$i" '.records[$i].engine == "checkout"' "$HOST" >/dev/null || return 0
    t=$(mktemp "$HOST.XXXXXX") && jq --argjson i "$i" '.records[$i].engine = "checkout"' "$HOST" > "$t" && mv "$t" "$HOST" || { rm -f "$t"; return 1; }
    echo "conveyor: $(jq -r --argjson i "$i" '.records[$i].repo' "$HOST") runs from its own checkout on the machine's Conveyor (its record of $HOST)"; return 0
  done < <(jq -r '.records // [] | to_entries[] | select(.value | objects | .main | strings) | "\(.key)\t\(.value.main)"' "$HOST")
  n=${MAIN##*/}; n=${n//[^A-Za-z0-9._-]/-}
  ! jq -e --arg n "$n" 'any(.records // [] | .[]; .repo == $n)' "$HOST" >/dev/null \
    || { echo "conveyor: another record of $HOST is named $n: add this project's record ({\"repo\": \"<name>\", \"main\": \"$MAIN\"${e:+, \"engine\": \"checkout\"}}) by hand" >&2; return 1; }
  t=$(mktemp "$HOST.XXXXXX") || return 1
  jq --arg n "$n" --arg m "$MAIN" --arg e "$e" '.records = (.records // []) + [{repo: $n, main: $m} + if $e == "" then {} else {engine: $e} end]' "$HOST" > "$t" && mv "$t" "$HOST" \
    || { rm -f "$t"; return 1; }
  echo "conveyor: added $n to the machine's Conveyor (a record of $HOST$([ -z "$e" ] || echo ", run from its own checkout"))"
}
# conveyor.sh doctor: each thing Conveyor needs on this machine for the project it is called in, one line each, "ok: ..."
# or "missing: <what>; fix: <how>", and "warning: ..." for a running loop on old code. Exit 1 when anything is missing. bash older than 5.1 stops at require_bash, above,
# which says how to get a newer one. The project's checks need jq and git; without either they are named as not checked.
doctor() {
  local bad=0 p e t c h f
  ok() { echo "ok: $1"; }; no() { echo "missing: $1; fix: $2"; bad=1; }
  ok "bash $BASH_VERSION"
  for p in jq git; do type -P "$p" >/dev/null && ok "$p" || no "$p" "install $p (macOS: brew install $p; Debian or Ubuntu: sudo apt install $p)"; done
  if ! command -v gh >/dev/null; then no "gh, the GitHub CLI" "install it: https://cli.github.com"
  elif timeout 20 gh auth status >/dev/null 2>&1; then ok "gh, signed in"; else no "gh signed in" "run gh auth login"; fi
  if mpsinstalled; then ok "the plugin $MPS, for /conveyor-belt:plan"
  else no "the plugin $MPS, for /conveyor-belt:plan" "run claude plugin install $MPS"; fi
  if [ ! -e "$HOST" ]; then no "the host file $HOST" "run /conveyor-belt:setup, which writes it"
  elif ! command -v jq >/dev/null; then echo "not checked: the host file $HOST: it is read with jq"
  elif ! jq -e 'type == "object"' "$HOST" >/dev/null 2>&1; then no "a readable host file at $HOST" "make it a JSON object"
  else ok "the host file $HOST"
    # A record of the host file whose main is this checkout (links followed): with none, the machine's Conveyor does
    # not serve it (setup adds none when another record has its folder's name).
    p=$(cd "$MAIN" 2>/dev/null && pwd -P) && e='' && while IFS= read -r t; do
      [ "$(cd "$t" 2>/dev/null && pwd -P)" != "$p" ] || { e=1; break; }
    done < <(jq -r '.records | arrays | .[] | objects | .main | strings' "$HOST")
    [ -n "$e" ] || no "a record of the host file $HOST for this checkout $MAIN (the machine's Conveyor serves only the checkouts its records name)" \
      "run /conveyor-belt:setup; when it says another record has this checkout's name, add {\"repo\": \"<name>\", \"main\": \"$MAIN\"} to the host file's records by hand"
  fi
  # One Conveyor per machine: the machine's loop (`machine`), and no loop of a project beside it that it did not start
  # (a per-project service left from before, or a `serve` started by hand). Each loop alive names its pid.
  if command -v jq >/dev/null; then
    local loops=() mains=() v=() mp='' r m s q a is='^([^ ]*/)?bash (.*/)?conveyor\.sh (serve|run( .*)?)$'; local -A up=() loop=()
    IFS=$'\t' read -r e t < <(jq -r '[.pid, .started] | @tsv' "$MACH/loop.json" 2>/dev/null) && [ -n "$e" ] && p_alive "$e" "$t" && mp=$e
    [ -z "$mp" ] || loops+=("the machine's Conveyor (pid $mp)")
    while IFS=$'\t' read -r r m _; do
      mains+=("$m")
      s=$(CONVEYOR_MAIN=$m bash "$HERE/conveyor.sh" state-dir 2>/dev/null) && [ -e "$s/cards.jsonl.run" ] || continue
      ! ( flock -n 9 ) 9>>"$s/cards.jsonl.run" 2>/dev/null || continue # no loop holds it
      IFS=$'\t' read -r e t < <(jq -r '[.pid, .started] | @tsv' "$s/loop.json" 2>/dev/null) && [ -n "$e" ] && p_alive "$e" "$t" || e='?'
      [ -n "$mp" ] && [ "$(ps -o ppid= -p "$e" 2>/dev/null | tr -d ' ')" = "$mp" ] || loops+=("a loop of $r on its own (pid $e)")
    done < <(projects 2>/dev/null)
    # Then the loops of projects that are no record of the host file (a `serve` started by hand, a service left from
    # before), found among the machine's processes, so by nothing a loop writes: one on older code is found too.
    # A loop is a bash that runs conveyor.sh with `run` or `serve` (an editor with the file open, or a script handed its
    # path, is none) on this host file (its own environment names it, by any path that reaches the same file) under no
    # other loop and not under the machine's; the folder it runs in is its checkout. One in a record's checkout was
    # looked at above.
    while read -r q e t; do
      up[$q]=$e
      [[ $t =~ $is ]] && mapfile -d '' -t v < <(p_argv "$q") || continue
      [ ${#v[@]} = 0 ] || [[ ${v[0]##*/} = bash && ${v[1]:-} =~ (^|/)conveyor\.sh$ && ${v[2]:-} =~ ^(serve|run)$ ]] || continue
      s=$(p_env "$q" XDG_CONFIG_HOME) && a=$(p_env "$q" HOME) && s=${s:-$a/.config}/conveyor/host.json || continue
      [ "$s" = "$HOST" ] || [ "$s" -ef "$HOST" ] || continue
      loop[$q]=1
    done < <(p_procs)
    for q in "${!loop[@]}"; do
      a=${up[$q]:-}; while [ -n "$a" ]; do [ "$a" != "$mp" ] && [ -z "${loop[$a]:-}" ] || continue 2; a=${up[$a]:-}; done
      s=$(p_cwd "$q") && [ -n "$s" ] || continue
      for m in "${mains[@]}"; do [ ! "$m" -ef "$s" ] || continue 2; done
      loops+=("a loop of $s, no record of the host file, on its own (pid $q)")
    done
    if [ ${#loops[@]} -gt 1 ]; then no "one Conveyor loop on this machine: ${loops[1]} runs beside ${loops[0]}" \
      "stop every loop but the machine's (a per-project service: systemctl --user disable --now conveyor-<name>.service, or launchctl bootout gui/\$(id -u)/conveyor.<name>), then run install-service once"
    elif [ ${#loops[@]} = 1 ]; then ok "one Conveyor loop on this machine: ${loops[0]}"; fi
  fi
  # A Conveyor service whose conveyor.sh is gone (an install removed under it): its loop may run now, on code it moved
  # to, but a restart or a reboot does not start it.
  while IFS=$'\t' read -r t c; do
    [ -f "$c" ] || no "the file $c that the service $t starts (a restart or a reboot does not start its loop)" \
      "run conveyor.sh install-service in the project's checkout, which writes the machine's service on an installed commit"
  done < <(services)
  # setup makes the virtualenv with python3 -m venv, which Debian and Ubuntu leave out of python3 (python3-venv); there,
  # it leaves a virtualenv with a python3 but no pip, which counts as no virtualenv.
  if ! "$BOARD_VENV/bin/python3" -c 'import pip' 2>/dev/null; then no "the Board's virtualenv $BOARD_VENV" \
    "run /conveyor-belt:setup, which makes it (on Debian or Ubuntu, first install python3-venv: sudo apt install python3-venv)"
  else for p in $BOARD_PKGS; do
    if "$BOARD_VENV/bin/python3" -c "import $p" 2>/dev/null; then ok "$p, in the Board's virtualenv $BOARD_VENV"
    else no "$p, for the Board, in its virtualenv $BOARD_VENV" "run /conveyor-belt:setup, which installs it there"; fi
  done; fi
  if ! command -v jq >/dev/null || ! type -P git >/dev/null; then
    echo "not checked: the pack, its models' programs, the pin and the terms file: they are read with jq and git"; return 1
  fi
  git -C "$CALLED" rev-parse --git-dir >/dev/null 2>&1 || { no "a git checkout of the project at $CALLED" "run conveyor.sh doctor in the project's checkout"; return 1; }
  if [ ! -e "$PACK" ]; then no "the pack $PACK" "run /conveyor-belt:setup"; return 1; fi
  e=$("$HERE/lib/pack.sh" check "$PACK" 2>&1) || { no "a valid pack" "correct what the check names: ${e//$'\n'/; }"; return 1; }
  ok "the pack $PACK"
  for p in $(progs); do
    # OpenCode's sessions start only on 1.x, the plugin API of the guard plugin (ocready()).
    if [ "$p" = opencode ] && command -v opencode >/dev/null && ! [[ $(timeout 60 opencode --version 2>/dev/null | head -n 1) =~ ^v?1\.[0-9]+ ]]; then
      no "OpenCode 1.x, for the OpenCode models (the builder's guard plugin is written for its plugin API)" "install a 1.x release (npm install -g opencode-ai@1), or take its models out of models.allowed"
    elif command -v "$p" >/dev/null; then ok "$p, for the default models the pack names for it"
    else no "$p, for the models the pack's models.allowed lists for it" "install it ($(case $p in claude) echo "npm install -g @anthropic-ai/claude-code" ;;
      codex) echo "npm install -g @openai/codex" ;; *) echo "npm install -g opencode-ai, a 1.x release, then opencode auth login for each provider its models name" ;; esac)), or take its models out of models.allowed"; fi
  done
  # The builder and the reviewer in force (the control record's, its defaults' or the seed's): one whose CLI is not
  # installed here does not start (seatready), and the loop starts no card, so doctor names that seat.
  for t in builder reviewer; do
    c=$(seat "$t" 2>/dev/null) || continue
    e=$(seatready "$t" "$c" 2>/dev/null) || no "a $t that can start (${e%%: the $t does not start;*})" \
      "install its CLI, or set the $t to a CLI and model this host has (conveyor.sh control, or Rules on the Board)"
  done
  routes || bad=1
  # A pack that follows the plugin's main or its releases: the commit it is on here, how far behind main that is (or
  # the release it is and whether a newer one is published), and a newer commit that failed its check (take()); then
  # that commit's install is checked as a pin's is.
  p=''; f=''; enginepin p f
  if [ -n "$f" ]; then
    if [ -n "$p" ] && [ "$f" = releases ]; then ok "the project follows the plugin's releases: it runs Conveyor commit $p, $(released "$p")"
    elif [ -n "$p" ]; then ok "the project follows the plugin's $f: it runs Conveyor commit $p, $(behind "$p" "$f")"; fi
    e=$(jq -r '.refused | objects | "\(.commit): \(.reason)"' "$ENGINE" 2>/dev/null) || e=''
    [ -z "$e" ] || echo "warning: Conveyor commit ${e%%: *} of the plugin's $f was not taken: ${e#*: }"
  fi
  if [ -z "$p" ] && [ -n "$f" ]; then no "a commit of the plugin's $f taken on this machine (the pack follows it)" "run /conveyor-belt:setup, which takes it"
  elif [ -z "$p" ]; then no "the pin (the pack's plugin.commit)" "run /conveyor-belt:setup"
  elif installed "$p" ro && [ -f "$VERSIONS/$p/conveyor/conveyor.sh" ]; then ok "the pinned commit $p, installed"
  # A folder there that is not the commit as cloned: install() refuses it, so setup alone cannot mend it. Only a full
  # commit id names a folder inside the versions folder, so no other pin is offered for removal.
  elif [[ $p =~ ^[0-9a-f]{40}$ ]] && { [ -e "$VERSIONS/$p" ] || [ -L "$VERSIONS/$p" ]; } && ! installed "$p"; then
    # Quoted for the shell whatever the path holds; a link (dangling or not) is removed itself, never followed. rm
    # needs read and search as well as write on each folder it empties, and chmod -R grants them before it descends.
    e=$(printf %q "$VERSIONS/$p"); [ -L "$VERSIONS/$p" ] && e="rm -f $e" || e="chmod -R u+rwx $e && rm -rf $e"
    no "the install of the pinned commit $p ($VERSIONS/$p is there and is not that commit as cloned)" \
      "remove it ($e), then run /conveyor-belt:setup, which installs it"
  else no "the install of the pinned commit $p" "run /conveyor-belt:setup, which installs it"; fi
  # A running loop on older code than its checkout's HEAD or, from an install, than the pin: a warning, as it restarts
  # on the new code by itself once its push is done.
  # The checkout is read on its own: @tsv escapes a backslash in a path, and read -r keeps that escape.
  if IFS=$'\t' read -r e t c < <(jq -r '[.pid, .started, .commit // ""] | @tsv' "$SAYS" 2>/dev/null) && [ -n "$c" ] && p_alive "$e" "$t"; then
    h=$(jq -r '.checkout // ""' "$SAYS" 2>/dev/null)
    if [ -n "$h" ]; then e=$(git -C "$h" rev-parse -q --verify HEAD) && [ "$e" != "$c" ] && echo "warning: the running loop started on Conveyor commit $c, and its checkout is at $e: it runs old code until it restarts"
    elif [ -n "$p" ] && [ "$p" != "$c" ]; then echo "warning: the running loop started on Conveyor commit $c, and the pack pins $p: it runs old code until it restarts"; fi
  fi
  # The project's last card test runs recorded no test times (UNTIMED, lib/views.sh): its test command prints no
  # `TESTRUN sec` lines. A warning: the cards still run, held to no CPU budget.
  e=$(stdb ask lines cards 2>/dev/null | jq -s "$UNTIMED"' untimed' 2>/dev/null) || e=0
  [[ ! $e =~ ^[1-9][0-9]*$ ]] || echo "warning: the last $e card test run$([ "$e" = 1 ] || echo s) recorded no test times: the test command prints no \`TESTRUN sec\` lines; conveyor/README.md, The CPU budget of a test file, says how to add them"
  if packget privacy.mode e && [ "$e" = public ]; then
    if t=$(termsfile); then ok "the terms file $t"
    elif termsnamed; then no "a readable terms file (the host file $HOST names one, or does not read, and the pack's privacy.mode is public)" "make the file it names readable, or take \"terms\" out of $HOST"
    else ok "no terms file (it is optional): the privacy check runs with no word list"; fi
  fi
  return $bad
}
