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
  lanes: {research: {model: "claude-fable-5-2", effort: "medium"}},
  privacy: {mode: "public"}}'
# The question "Run a first test-speed survey now?" (conveyor/README.md, The first survey): answered by --survey yes|no,
# and asked, as the pack's answers are (exit 2, nothing written), while the pack has no saved answer
# (test.firstSurvey); a saved answer is not asked again unless --survey is given. Once the labels are there, yes files
# one survey issue (firstsurvey(), lib/survey.sh) and no files none; then the answer is saved, so a filing that failed
# leaves it unsaved and the question asked again.
# The questions "Make a fast lane?" and "Make a research lane?" (docs/lanes.md): answered by --fast-lane yes|no and
# --research-lane yes|no, and asked (exit 2, nothing written) on every run; yes makes the lane (setuplane()) once the
# project is in the host file, where its create writes the lane's folder. PACK0's lanes.research is the research
# lane's model and effort, which its create needs; yes writes it into a pack that has none.
# The question "Set the pack's tests.patterns?": answered by --test-patterns yes|no, and asked (exit 2, nothing written)
# while the pack sets no tests.patterns and the default misses tracked files that read as tests (testoffer()), naming
# the globs and how many tracked files they match; yes writes them as the pack's tests.patterns.
# The question "Set the pack's test.list?": answered by --test-list yes|no, and asked (exit 2, nothing written) while
# the pack sets no test.list and the test command runs a runner listguess() knows, naming it; yes writes what
# listguess() offers (args, or runner for go test and cargo test, which take packages and test targets, not files) as
# the pack's test.list.
# The question "Make the test map?": answered by --test-map yes|no, and asked (exit 2, nothing written) while the pack
# sets no test.map, there is no made map and the project's language has a coverage tool the map knows (lib/testmap.sh
# maptool()), naming the tool and what the run may cost (mapcost()); yes runs the whole suite under coverage and
# writes the map (mapbuild()), no writes test.map off. With no such tool, setup says so: a card's tests are found by
# name.
# Before the host file names the project, the control record is written when there is none, with new issues and every
# open issue held (heldstart()).
# With --foreman it then sets up Foreman mode (foreman/foreman.sh setup), which `conveyor.sh foreman` starts.
# Then it says which of the project's instruction files, CLAUDE.md and AGENTS.md, are there (agentfiles()).
# Its last line says that landed cards wait for the Board's Push landed: the control record's push rule is off by
# default (lib/control-defaults.json). A pack with no test.full (one setup did not write) has no Push landed: the line
# says to add one.
# Matt Pocock's skills, the plugin /conveyor-belt:plan reads (MPS, from the official marketplace), are a requirement:
# setup installs them for the user when Claude Code's record of installed plugins (in CLAUDE_CONFIG_DIR, default
# ~/.claude) has none, and doctor names them missing until it has.
# The questions "Which route does the builder use?" and "Which route does the reviewer use?" (docs/setup.md): asked
# (exit 2, nothing written) on every run while the role's CLI has no route set in the host file and has a second
# route: a local API proxy (findproxy()) or the provider's own API with a key (routeask()); before them, where that
# key is kept (--claude-key, --codex-key), while none is found. Each route is checked with one real call first, and
# one that fails is named with why and not offered. --builder-route and --reviewer-route are each fallback (the CLI's
# own login, and the second route when that login fails), proxy or api (always that route) or subscription (the CLI's
# own login only). Once the project is in the host file, each such CLI's route is written there (routewrite()):
# Claude's as claudeProxy, Codex's as codexProxy, which a Codex session is given as its own provider settings.
MPS=mattpocock-skills@claude-plugins-official
mpsinstalled() { jq -e --arg p "$MPS" '.plugins[$p] | type == "array" and length > 0' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json" >/dev/null 2>&1; }
# The question "Link the dependency folders?" (docs/setup.md): asked (exit 2, nothing written) on every run while the
# main checkout has dependency folders (depdirs(), lib/push.sh) and the pack has neither a linkFromMain nor a
# worktree.setup, naming the folders and the project's tracked lockfiles. --link yes writes the folders as
# linkFromMain; --worktree-setup <command> writes worktree.setup, the install run in each card worktree, which a
# project whose cards may change a lockfile needs in place of links to main's folders. Once the pack has either, the
# question is not asked and a rerun changes neither.
LOCKFILES=(package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml bun.lockb poetry.lock uv.lock Pipfile.lock Gemfile.lock Cargo.lock composer.lock Podfile.lock)
SETUP_USAGE='setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--test-patterns yes|no] [--test-list yes|no] [--test-map yes|no] --fast-lane yes|no --research-lane yes|no [--link yes|no] [--worktree-setup <command>] [--builder-route subscription|fallback|proxy|api] [--reviewer-route subscription|fallback|proxy|api] [--fallback-route proxy|api] [--claude-key none|settings|<key file>] [--codex-key none|settings|<key file>] [--claude-proxy <base URL>] [--codex-proxy <base URL>] [--claude-proxy-key settings|<key file>] [--codex-proxy-key settings|<key file>] [--pin] [--foreman]'
setup() { # as SETUP_USAGE
  local owner='' test='' prods=() need=() b p f have l n x fm='' pin='' sv='' fl='' rl='' br='' rr='' fr='' w first full c lk='' ws='' lf='' wsx='' dds=() lks tp='' tpa='' tn tl='' tla='' tma='' tmt='' tmw=''
  local -A keyarg=() pxarg=() pkarg=() rcli=() lg=() pxu=() ak=() akf=() pk=() pkf=() as=() kd=(); local clis=()
  local ask='--survey <yes or no: run a first test-speed survey now?>'
  while [ $# -gt 0 ]; do
    [ "$1" != --foreman ] || { fm=1; shift; continue; }
    [ "$1" != --pin ] || { pin=1; shift; continue; }
    case $1 in --owner) owner=${2-} ;; --product) prods+=("${2-}") ;; --test) test=${2-} ;;
      --survey) sv=${2-}; [[ $sv == yes || $sv == no ]] || { set -- x; break; } ;;
      --test-patterns) tpa=${2-}; [[ $tpa == yes || $tpa == no ]] || { set -- x; break; } ;;
      --test-list) tla=${2-}; [[ $tla == yes || $tla == no ]] || { set -- x; break; } ;;
      --test-map) tma=${2-}; [[ $tma == yes || $tma == no ]] || { set -- x; break; } ;;
      --fast-lane) fl=${2-}; [[ $fl == yes || $fl == no ]] || { set -- x; break; } ;;
      --research-lane) rl=${2-}; [[ $rl == yes || $rl == no ]] || { set -- x; break; } ;;
      --link) lk=${2-}; [[ $lk == yes || $lk == no ]] || { set -- x; break; } ;;
      --worktree-setup) ws=${2-}; [ -n "$ws" ] || { set -- x; break; } ;;
      --builder-route) br=${2-}; [[ $br =~ ^(subscription|fallback|proxy|api)$ ]] || { set -- x; break; } ;;
      --reviewer-route) rr=${2-}; [[ $rr =~ ^(subscription|fallback|proxy|api)$ ]] || { set -- x; break; } ;;
      --fallback-route) fr=${2-}; [[ $fr == proxy || $fr == api ]] || { set -- x; break; } ;;
      --claude-key) keyarg[claude]=${2-}; [ -n "${keyarg[claude]}" ] || { set -- x; break; } ;;
      --codex-key) keyarg[codex]=${2-}; [ -n "${keyarg[codex]}" ] || { set -- x; break; } ;;
      --claude-proxy) pxarg[claude]=${2-}; [ -n "${pxarg[claude]}" ] || { set -- x; break; } ;;
      --codex-proxy) pxarg[codex]=${2-}; [ -n "${pxarg[codex]}" ] || { set -- x; break; } ;;
      --claude-proxy-key) pkarg[claude]=${2-}; [ -n "${pkarg[claude]}" ] || { set -- x; break; } ;;
      --codex-proxy-key) pkarg[codex]=${2-}; [ -n "${pkarg[codex]}" ] || { set -- x; break; } ;; *) set -- x; break ;; esac
    [ $# -ge 2 ] || { set -- x; break; }; shift 2
  done
  [ $# = 0 ] || { echo "usage: conveyor.sh $SETUP_USAGE" >&2; return 2; }
  # The two lanes are asked on every run, before anything is changed: there is no saved answer.
  [ -n "$fl" ] || need+=("--fast-lane <yes or no: make a fast lane, your own worktree for changes made by hand?>")
  [ -n "$rl" ] || need+=("--research-lane <yes or no: make a research lane, a read-only sandboxed worktree?>")
  # So are the two roles' routes, while a CLI with none set has a second route.
  routeask || return
  # The dependency folders, while the pack neither links nor installs them.
  [ ! -e "$PACK" ] || packget linkFromMain lf worktree.setup wsx || return 1
  if [ -z "$wsx" ] && [ "$(jq 'length' <<<"${lf:-[]}")" = 0 ]; then
    mapfile -t dds < <(depdirs "$MAIN")
    if [ ${#dds[@]} -gt 0 ] && [ -z "$lk$ws" ]; then
      lks=$(git -C "$MAIN" ls-files -z | tr '\0' '\n' | grep -xE "(.*/)?($(IFS='|'; echo "${LOCKFILES[*]//./\\.}"))" | head -n 5 | paste -sd, - | sed 's/,/, /g')
      w="link the dependency folders of the main checkout ($(printf '%s, ' "${dds[@]}" | sed 's/, $//')) into each card's worktree (the pack's linkFromMain)?"
      w+=" Linking is not safe when a card may change $([ -n "$lks" ] && echo "a lockfile ($lks)" || echo "what they hold"): its tests would run on main's packages."
      w+=" Then pass --worktree-setup with the command that installs them in each card's worktree, such as npm ci, in place of --link"
      need+=("--link <yes or no: $w>")
    fi
  fi
  # The project's test files, when the pack sets no tests.patterns and the default misses files that read as tests
  # (testoffer()): asked, as the lanes are, naming the globs and how many tracked files they match; yes writes them.
  if [ "$tpa" != no ] && ! jq -e '.tests.patterns' "$PACK" >/dev/null 2>&1; then
    x=$test; [ ! -e "$PACK" ] || packget test.command x 2>/dev/null || x=''
    [ -z "$x" ] || tp=$(testoffer "$x") || tp=''
    if [ -n "$tp" ] && [ -z "$tpa" ]; then
      tn=$(testcount "$tp") && n=$(testcount "$(jq -c '.properties.tests.properties.patterns.default' "$SCHEMA")") || return 1
      need+=("--test-patterns <yes or no: the default test-file patterns miss $((tn - n)) tracked files that read as tests; set the pack's tests.patterns to $(jq -r 'join(", ")' <<<"$tp"), which match $tn tracked files?>")
    fi
  fi
  # How the test command takes the list of a card's tests, while the pack sets no test.list and the command runs a
  # runner listguess() knows: asked, naming the runner; yes writes what it offers.
  if [ "$tla" != no ] && ! jq -e '.test.list' "$PACK" >/dev/null 2>&1; then
    x=$test; [ ! -e "$PACK" ] || packget test.command x 2>/dev/null || x=''
    [ -z "$x" ] || tl=$(listguess "$x") || tl=''
    if [ -n "$tl" ] && [ -z "$tla" ]; then
      if [ "${tl%% *}" = args ]; then
        need+=("--test-list <yes or no: the test command runs ${tl#* }, which takes test files as arguments; set the pack's test.list to args, so a card's test run is given only the tests its change touches?>")
      else
        need+=("--test-list <yes or no: the test command runs ${tl#* }, which takes packages or test targets, not test files; set the pack's test.list to runner, so a card's test run is given only the packages or test targets of the tests its change touches?>")
      fi
    fi
  fi
  # The test map, while the pack sets no test.map and there is none (lib/testmap.sh): asked, naming the coverage tool
  # and what the run may cost (mapcost()); a project whose language has no tool the map knows is told so.
  if [ "$tma" != no ] && ! jq -e '.test.map' "$PACK" >/dev/null 2>&1 && [ ! -s "$(mappath)" ]; then
    if tmt=$(maptool "$(maplang "$MAIN")" "$MAIN"); then
      [ -n "$tma" ] || need+=("--test-map <yes or no: run the whole suite once with $tmt to make the test map (which test files cover which source files), so a card runs only the tests that cover its change? $(mapcost)>")
    else tmw=$tmt; tmt=''; fi
  fi
  if [ -e "$PACK" ]; then
    [ -n "$sv" ] || { packget test.firstSurvey first || return 1; [ -n "$first" ] || need+=("$ask"); }
    [ ${#need[@]} = 0 ] || { printf 'conveyor: setup needs:%s\n' "$(printf ' %s;' "${need[@]}")" >&2; return 2; }
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
  # dds is read only while the pack has neither: what the owner wrote in either is kept.
  if [ "$lk" = yes ] && [ ${#dds[@]} -gt 0 ]; then
    jq '.linkFromMain = $ARGS.positional' "$PACK" --args "${dds[@]}" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the dependency folders could not be written as the pack's linkFromMain" >&2; return 1; }
    echo "conveyor: wrote the pack's linkFromMain: $(printf '%s, ' "${dds[@]}" | sed 's/, $//'), linked from the main checkout into each card's worktree"
  fi
  if [ -n "$ws" ] && [ -z "$wsx" ]; then
    jq --arg s "$ws" '.worktree.setup = $s' "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: worktree.setup could not be written in the pack" >&2; return 1; }
    echo "conveyor: wrote the pack's worktree.setup: $ws, run in each card's worktree before its build and tests"
  fi
  if [ "$tpa" = yes ] && [ -n "$tp" ]; then
    jq --argjson p "$tp" '.tests.patterns = $p' "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's tests.patterns could not be written" >&2; return 1; }
    echo "conveyor: wrote the pack's tests.patterns: $(jq -r 'join(", ")' <<<"$tp") ($(testcount "$tp") tracked files)"
  fi
  if [ "$tla" = yes ] && [ -n "$tl" ]; then
    jq --arg l "${tl%% *}" '.test.list = $l' "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's test.list could not be written" >&2; return 1; }
    echo "conveyor: wrote the pack's test.list: ${tl%% *} (the test command runs ${tl#* })"
  fi
  # Yes runs the whole suite under coverage now and writes the map, saying what it mapped and how long it took; a run
  # that fails says so, and the cards' tests are found by name. No writes test.map off, so it is not asked again.
  [ -z "$tmw" ] || echo "conveyor: no test map: $tmw; a card's tests are found by name"
  if [ "$tma" = yes ] && [ -n "$tmt" ]; then mapbuild "$MAIN" || :
  elif [ "$tma" = no ] && ! jq -e '.test.map' "$PACK" >/dev/null 2>&1; then
    jq '.test.map = "off"' "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's test.map could not be written" >&2; return 1; }
    echo "conveyor: wrote the pack's test.map: off; a card's tests are found by name"
  fi
  # How Conveyor reads the test times from the runner's own report (test.report, reportguess()), while the pack names
  # no format: written again each run, so a report option added to the test command since is found.
  if ! jq -e '.test.report.format' "$PACK" >/dev/null 2>&1 && packget test.command x && x=$(reportguess "$x") && [ -n "$x" ] \
    && ! jq -e --argjson r "$x" '.test.report == $r' "$PACK" >/dev/null 2>&1; then
    jq --argjson r "$x" '.test.report = $r' "$PACK" > "$PACK.new" && "$HERE/lib/pack.sh" check "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's test.report could not be written" >&2; return 1; }
    jq -r '"conveyor: wrote the pack'"'"'s test.report: the test command runs \(.runner), "
      + if .format then "and Conveyor reads each test file'"'"'s clock seconds from its report (\(.format), \(if .env or .args then "which Conveyor asks it for at each run" else .path // "its output" end))"
        else "whose output gives no test times Conveyor can read; its option \(.option) would" end' <<<"$x"
  fi
  packget plugin.commit p plugin.follow f || return 1
  if [ -z "$p$f" ] && [ -n "$pin" ]; then
    p=$(git -C "$HERE" rev-parse HEAD 2>/dev/null) || { echo "conveyor: the pin could not be written: $HERE is in no git checkout, so its commit cannot be read" >&2; return 1; }
    jq --arg c "$p" '.plugin = {commit: $c}' "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
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
  # Before hostadd: once the host file names the project, a machine's service already running serves it.
  heldstart || return 1
  hostadd || return 1
  for c in "${clis[@]}"; do mlocked routewrite "$c" || return 1; done
  [ "$fl" = no ] || setuplane fast || return 1
  if [ "$rl" = yes ]; then
    # A pack an earlier setup wrote has no lanes.research, which the lane's create needs: PACK0's is written in.
    packget lanes.research x || return 1
    [ -n "$x" ] || { jq ".lanes.research = ($PACK0).lanes.research" "$PACK" > "$PACK.new" && mv "$PACK.new" "$PACK" \
      && echo "conveyor: wrote the research lane's model and effort as the pack's lanes.research"; } \
      || { rm -f "$PACK.new"; echo "conveyor: the research lane's model and effort could not be written in the pack" >&2; return 1; }
    setuplane research || return 1
  fi
  [ -z "$fm" ] || CONVEYOR_MAIN=$MAIN bash "$HERE/foreman/foreman.sh" setup || return 1
  # A Board left on older Conveyor would keep running it (it may not read the host file just written): started again.
  boardrenew
  agentfiles
  packget test.full full || return 1
  echo "conveyor: landed cards wait for Push landed on the Board until push is turned on in the Rules tab$([ -n "$full" ] || echo "; Push landed needs the pack's test.full, the full test suite: add it")"
}
# The control record, when the project has none (no file, or an empty one, which reads as the defaults): new issues
# start held (as `control start held` sets it, from the newest issue's number) and every issue open now is held, so
# no loop builds an issue the owner did not release. With no record the loop reads the defaults, where new issues
# start in the Queue, and it would queue the whole backlog. The newest number is read before the open issues, so an
# issue opened between the two reads is in the span (adopt() holds it) or in the list. setup writes it before the
# host file names the project (hostadd), and doctor names a project with no record as missing, so the service is not
# offered before it is there. A record already there, with the owner's later `start queue` and releases, is never
# changed. No lock: no loop serves the project yet, and the record is written whole beside its place and moved in.
heldstart() {
  local top open new
  [ ! -s "$CONTROL" ] || return 0
  top=$(timeout 60 gh issue list --state all --limit 1 --json number 2>/dev/null | jq -e '.[0].number // 0 | numbers') \
    && open=$(timeout 60 gh issue list --state open --limit 100000 --json number 2>/dev/null | jq -ce 'map(.number | numbers) | unique') \
    && new=$(jq -c --argjson top "$top" --argjson open "$open" '.start = "held" | .startHeld = [{from: $top, to: null}] | .held = $open' <<<"$CTL0") \
    && [ -n "$new" ] && mkdir -p "${CONTROL%/*}" && printf '%s\n' "$new" > "$CONTROL.new" && mv -f "$CONTROL.new" "$CONTROL" \
    || { rm -f "$CONTROL.new"; echo "conveyor: the control record $CONTROL could not be written with the open issues held (gh issue list, or the folder); run setup again" >&2; return 1; }
  echo "conveyor: wrote the control record $CONTROL: new issues start held; $(heldline "$(jq length <<<"$open")")"
}
# What setup and doctor say of the open issues the control record holds.
heldline() { echo "$1 open issue$([ "$1" = 1 ] || echo s) held; release one with \`conveyor.sh control release <issue>\` or on the Board"; }
# The project's instruction files that Conveyor's sessions read, at the root of the main checkout: CLAUDE.md (the
# builder, the fixer, the Foreman and the lanes) and AGENTS.md (the Codex reviewer). One `ok:` or `missing:` line for
# each, printed by setup and by doctor. Only read: /conveyor-belt:setup asks the user whether to write a missing one,
# and an existing one is never changed. A missing one is not counted as a fault: sessions run without it, with no
# project context beyond the card rules.
agentfiles() {
  local f w
  for f in CLAUDE.md AGENTS.md; do
    [ "$f" = CLAUDE.md ] && w="Conveyor's Claude sessions (builder, fixer, Foreman, lanes)" || w="the Codex reviewer"
    if [ -f "$MAIN/$f" ]; then echo "ok: $f, the project's instructions for $w"
    else echo "missing: $f at the root of $MAIN, the project's instructions for $w; fix: run /conveyor-belt:setup and answer yes when it asks to write it, or write it yourself"; fi
  done
}
# setuplane fast|research: the lane made by its own create (`conveyor.sh lane <lane> create`, re-runnable: a lane
# already there is left as it is), its output passed on, with its `made the` line, there only when the lane is new,
# said as one `created:` line.
setuplane() {
  local out rc
  out=$(cd "$MAIN" && bash "$HERE/conveyor.sh" lane "$1" create); rc=$?
  [ -z "$out" ] || sed 's/^conveyor: made the /conveyor: created: the /' <<<"$out"
  [ $rc = 0 ] || { echo "conveyor: the $1 lane could not be made (conveyor.sh lane $1 create)" >&2; return 1; }
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
# The pack's test.report for a test command (setup()), as JSON: {runner, format, path} when the command already has
# its runner write a report tools/testreport.py reads (path: the report's file, from the checkout's root; none for
# the command's own output), {runner, format, env} or {runner, format, args} when Conveyor asks the runner for one
# at each run (below), else {runner, option}: the runner's option that would. Nothing for a runner it does not
# know. A command that runs a package.json script (npm, yarn, pnpm or bun) is read as that script, as testrunner() reads it.
reportguess() { # <test command>
  local s=$1 r='' f='' p='' o='' e='' pm='' i w v ws=() rs=()
  if [[ $1 =~ ^(npm|yarn|pnpm|bun)[[:space:]]+(run[[:space:]]+)?([A-Za-z0-9:_-]+)[[:space:]]*$ ]]; then
    pm=${BASH_REMATCH[1]}; s=$(jq -r --arg n "${BASH_REMATCH[3]}" '.scripts[$n] | strings' "$MAIN/package.json" 2>/dev/null) || return 0
  fi
  if [[ $s =~ (^|[;&|[:space:]])(node([[:space:]]+-[^[:space:]]+)*[[:space:]]+--test|vitest|jest|mocha|pytest|rspec|go[[:space:]]+test|cargo[[:space:]]+test)([[:space:]]|$) ]]; then
    r=${BASH_REMATCH[2]}; [[ $r != node* ]] || r='node --test'; [[ $r != go* ]] || r='go test'; [[ $r != cargo* ]] || r='cargo test'
    # node's options may come before --test: its words are kept.
    w=${s#*"${BASH_REMATCH[0]}"}; [ "$r" = 'node --test' ] && s="${BASH_REMATCH[0]} $w" || s=$w
  else return 0; fi
  # The runner's words to the end of its command, quotes taken off; an --option=<value> as the option and its value.
  read -ra ws <<<"${s%%[;&|)]*}"
  declare -A a=()
  for ((i = 0; i < ${#ws[@]}; i++)); do
    w=${ws[i]//[\"\']/}; v=${ws[i + 1]:-}; v=${v//[\"\']/}
    if [[ $w == -*=* ]]; then a[${w%%=*}]+=" ${w#*=}"; elif [[ $w == -* && $v != -* ]]; then a[$w]+=" $v"; else a[$w]+=' '; fi
  done
  case $r in
    # Each --test-reporter writes to the --test-reporter-destination in the same place.
    'node --test') read -ra ws <<<"${a[--test-reporter]:-}"; read -ra rs <<<"${a[--test-reporter-destination]:-}"
      for i in "${!ws[@]}"; do [ "${ws[i]}" != junit ] || [[ ${rs[i]:-stdout} =~ ^std(out|err)$ ]] || { p=${rs[i]}; f=junit; }; done
      o='--test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=<file>' ;;
    vitest) if [[ " ${a[--reporter]:-} " == *' json '* ]]; then p=${a[--outputFile.json]:-${a[--outputFile]:-}}; f=jest-json
      elif [[ " ${a[--reporter]:-} " == *' junit '* ]]; then p=${a[--outputFile.junit]:-${a[--outputFile]:-}}; f=junit; fi
      o='--reporter=default --reporter=json --outputFile.json=<file>' ;;
    jest) [ -n "${a[--json]+x}" ] && p=${a[--outputFile]:-} && f=jest-json; o='--json --outputFile=<file>' ;;
    mocha) [[ " ${a[--reporter]:-}${a[-R]:-} " == *' xunit '* ]] && p=${a[--reporter-option]:-${a[--reporter-options]:-}} && [[ $p == *output=* ]] && p=${p##*output=} && f=junit
      o='--reporter xunit --reporter-option output=<file>' ;;
    pytest) p=${a[--junitxml]:-${a[--junit-xml]:-}}
      if [ -n "$p" ]; then f=junit; elif [ "${a[--durations]:-}" = ' 0' ]; then f=pytest-durations; fi
      o='--junitxml=<file>' ;;
    'go test') if [ -n "${a[-json]+x}" ]; then f=go-json; elif [ -n "${a[-v]+x}" ]; then f=go-text; fi ;;
    # cargo's own output names each test target and gives its seconds, with libtest's JSON format or without.
    'cargo test') f=cargo ;;
    rspec) [[ " ${a[--format]:-}${a[-f]:-} " == *' json '* ]] && p=${a[--out]:-${a[-o]:-}} && f=rspec-json
      o='--format progress --format json --out <file>' ;;
  esac
  p=${p# }; p=${p##* }; p=${p#./}
  # A report named by a variable or a pattern, or one a report file is needed for and none is named, is not read.
  [[ $p != *[\$*?\{]* ]] || f=''; [ -n "$p" ] || [[ $f =~ ^(go-json|go-text|cargo|pytest-durations)$ ]] || f=''
  # A runner whose report the command does not ask for: Conveyor asks for it at each card run and full test suite run (testrun.sh reportask()),
  # so the test command stays as it is: by environment variables (env: {variable: its words}), or, for vitest and
  # jest when their words end the command, by their options added at its end (args; after `--` for an npm script).
  # <file> is the report file Conveyor names. A command that names a report or reporter of its own is not given
  # another: its own option would win over Conveyor's, or (node) pair with Conveyor's destinations. Go is asked for
  # -v (GOFLAGS), whose output still gives the failures, not -json, which would take its place; mocha is given
  # Conveyor's timer (tools/mochatimes.cjs), which leaves its reporter as it is.
  if [ -z "$f" ]; then
    case $r in
      'node --test') [ -n "${a[--test-reporter]+x}" ] || { f=junit; e=$(jq -cn --arg o "$o" '{NODE_OPTIONS: $o}'); } ;;
      pytest) [ -n "${a[--junitxml]+x}${a[--junit-xml]+x}" ] || { f=junit; e=$(jq -cn --arg o "$o" '{PYTEST_ADDOPTS: $o}'); } ;;
      rspec) [ -n "${a[--out]+x}${a[-o]+x}" ] || { f=rspec-json; e=$(jq -cn --arg o "$o" '{SPEC_OPTS: $o}'); } ;;
      'go test') f=go-text; e='{"GOFLAGS":"-v"}' ;;
      mocha) f=mocha-times; e='{"NODE_OPTIONS":"--require <mochatimes>","CONVEYOR_MOCHA_REPORT":"<file>"}' ;;
      vitest|jest) [ "${s%%[;&|)]*}" != "$s" ] || [ -n "${a[--json]+x}${a[--reporter]+x}${a[--outputFile]+x}${a[--outputFile.json]+x}" ] \
        || { f=jest-json; [ "$pm" != npm ] || o="-- $o"; } ;;
    esac
    if [ -n "$f" ]; then
      jq -cn --arg r "$r" --arg f "$f" --argjson e "${e:-null}" --arg o "$o" '{runner: $r, format: $f} + if $e == null then {args: $o} else {env: $e} end'
      return
    fi
  fi
  if [ -n "$f" ]; then jq -cn --arg r "$r" --arg f "$f" --arg p "$p" '{runner: $r, format: $f} + if $p == "" then {} else {path: $p} end'
  else jq -cn --arg r "$r" --arg o "$o" '{runner: $r, option: $o}'; fi
}
# The tracked files the test command names (docs/configuration.md, How test files are found): each word of it with a
# * or ? in it (quotes taken off; of an --option=<value>, the value) read as a glob of paths from the checkout's root,
# as git reads one. One a line.
cmdtests() { # <test command>
  local w ws=()
  read -ra ws <<<"$1"
  for w in "${ws[@]}"; do
    w=${w//[\"\']/}; w=${w%%[;&|)]*}; [[ $w != -*=* ]] || w=${w#*=}; w=${w#./}
    [[ $w == *[*?]* && $w != -* && $w != *'$'* && $w != /* ]] || continue
    git -C "$MAIN" -c core.quotePath=false ls-files -- ":(glob)$w" 2>/dev/null
  done | LC_ALL=C sort -u
}
# The tracked files the test-file globs <patterns> (a JSON list, as tests.patterns) match, counted.
testcount() { # <patterns>
  local rx
  rx=$(jq -r "$GLOBRX"'globsrx' <<<"$1") || return 1
  git -C "$MAIN" -c core.quotePath=false ls-files | { grep -cE -- "$rx" || :; }
}
# Setup's guess at the test files <patterns> (a JSON list) miss: of the tracked files that are not documents or data,
# those the test command names (cmdtests()) and those whose own name reads as a test's (it starts with test or spec and
# a - or _, or ends so, or with Test, Tests or Spec, before its extension), each made a glob: its test word kept, the
# rest a *, in any folder; a file the command names whose name has no test word, its folder's files of its extension.
# Prints the globs that match a file <patterns> misses, one a line.
testguess() { # <test command> <patterns>
  local rx
  rx=$(jq -r "$GLOBRX"'globsrx' <<<"$2") || return 1
  git -C "$MAIN" -c core.quotePath=false ls-files | jq -rRn --arg rx "$rx" --rawfile cf <(cmdtests "$1") '
    ($cf | split("\n") | map(select(. != ""))) as $cf
    | [inputs | select(test($rx) | not) | select(test("\\.(md|txt|json|ya?ml|snap|lock|csv|html|css|svg|png|jpe?g|gif)$"; "i") | not)
      | . as $p | split("/")[-1] as $b | ($b | capture("(?<x>\\.[^.]+)$").x // "") as $e
      | if $b | test("^(?i:test|spec)s?[-_]") then ($b | capture("^(?<w>(?i:test|spec)s?[-_])").w) + "*" + $e
        elif $b | test("[-_.](?i:test|spec)s?\\.[^.]+$") then "*" + ($b | capture("(?<w>[-_.](?i:test|spec)s?)\\.[^.]+$").w) + $e
        elif $b | test("(Test|Tests|Spec)\\.[^.]+$") then "*" + ($b | capture("(?<w>Test|Tests|Spec)\\.[^.]+$").w) + $e
        elif IN($cf[]; $p) and ($p | contains("/")) then "/" + ($p | split("/")[:-1] | join("/")) + "/*" + $e
        else empty end] | unique[]'
}
# What setup offers for a pack with no tests.patterns of its own (setup()): the default and testguess()'s globs, as
# the setting (a JSON list); nothing when the default misses no file that reads as a test.
testoffer() { # <test command>
  local d g=()
  d=$(jq -c '.properties.tests.properties.patterns.default' "$SCHEMA") && mapfile -t g < <(testguess "$1" "$d") || return 1
  [ ${#g[@]} = 0 ] || jq -cn --argjson d "$d" '$d + $ARGS.positional' --args "${g[@]}"
}
# The test.list setup offers for a test command (setup()), and the runner it runs, as one line `<mode> <runner>`
# (testrunner(), in main): nothing for a runner it does not know, or for a command that already names the test files
# its runner runs, which paths added at its end would not narrow.
listguess() { # <test command>
  local g
  g=$(testrunner "$1" "$MAIN") || return 0
  [[ $g == named* ]] || printf '%s\n' "$g"
}
# What doctor says of the pack's tests.patterns: a `missing:` line when they match no tracked file, or miss a file the
# test command names (cmdtests()); else an `ok:` line with the count. Fails with a `missing:` line.
testcheck() {
  local p c n m=()
  packget tests.patterns p test.command c || return 1
  n=$(testcount "$p") || return 1
  mapfile -t m < <(cmdtests "$c" | testpaths -v)
  if [ "$n" = 0 ]; then
    echo "missing: test files the pack's tests.patterns match (they match no tracked file: $(jq -r 'join(", ")' <<<"$p")); fix: set tests.patterns in .conveyor/project.json to globs of the project's test files (docs/configuration.md, How test files are found)"; return 1
  elif [ ${#m[@]} != 0 ]; then
    echo "missing: tests.patterns that match the ${#m[@]} file$([ ${#m[@]} = 1 ] || echo s) the test command names, such as ${m[0]}; fix: add a glob of them to tests.patterns in .conveyor/project.json (docs/configuration.md, How test files are found)"; return 1
  fi
  echo "ok: the pack's tests.patterns match $n tracked file$([ "$n" = 1 ] || echo s)"
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
# A local API proxy: one listening on this machine on a port of PROXY_PORTS (CONVEYOR_PROXY_PORTS when set, else the
# ports such proxies take by default) that answers <api>, an empty request posted to it. messages, Claude's: the
# Anthropic Messages API, /v1/messages gives a Messages API body back (type error or message); its base URL is
# http://127.0.0.1:<port>. responses, Codex's: the OpenAI Responses API, /v1/responses gives a response object or an
# OpenAI error ({error: {...}}, with no type of its own, as an Anthropic error has) back; its base URL ends in /v1, as
# Codex's base_url does. Prints each one's base URL, one a line; nothing for none. An answer is only how a proxy is
# found: routeask() checks each one found with one real call through it before it is offered.
PROXY_PORTS=${CONVEYOR_PROXY_PORTS-4141 3456 4000 8082}
findproxy() { # <messages|responses>
  local ps; read -ra ps <<<"$PROXY_PORTS"; [ ${#ps[@]} -gt 0 ] || return 0
  timeout 60 python3 -I -c 'import json, sys, urllib.error, urllib.request
api = sys.argv[1]
for port in sys.argv[2:]:
    if not port.isdigit(): continue
    base = "http://127.0.0.1:" + port
    head = {"content-type": "application/json"}
    if api == "messages": head["anthropic-version"] = "2023-06-01"
    req = urllib.request.Request(base + "/v1/" + api, data=b"{}", headers=head)
    try:
        with urllib.request.urlopen(req, timeout=3) as r: body = r.read()
    except urllib.error.HTTPError as e: body = e.read()
    except Exception: continue
    try: said = json.loads(body)
    except ValueError: continue
    if not isinstance(said, dict): continue
    if api == "messages" and said.get("type") in ("error", "message"):
        print(base)
    if api == "responses" and (said.get("object") == "response" or (isinstance(said.get("error"), dict) and "type" not in said)):
        print(base + "/v1")' "$1" "${ps[@]}" 2>/dev/null
}
# The provider's own API, as setup checks it and writes its base URL (CONVEYOR_ANTHROPIC_API and CONVEYOR_OPENAI_API
# when set, else the providers' own), and the variable each one's key is named by.
ANTHROPIC_API=${CONVEYOR_ANTHROPIC_API:-https://api.anthropic.com}
OPENAI_API=${CONVEYOR_OPENAI_API:-https://api.openai.com/v1}
declare -A APIKEY=([claude]=ANTHROPIC_API_KEY [codex]=OPENAI_API_KEY) APINAME=([claude]=Anthropic [codex]=OpenAI) PROXYKEY=([claude]=CLAUDE_PROXY_KEY [codex]=CODEX_PROXY_KEY)
# setup()'s route questions, in its own variables (its locals, read and set here). Each role's CLI now, in rcli: the
# pack's seat, or with no pack yet the seat PACK0's models give. Each of those CLIs, Claude or Codex, with no route set
# (Claude: no claudeProxy in the host file or the pack; Codex: installed, no codexProxy in the host file) is checked:
# first where its provider's API key is kept (ak, the key; akf, where: settings, a key file's path or none, as
# --claude-key or --codex-key answers it, empty while a key is found and not answered). With no key found and no
# answer, that question is asked and no route is checked yet. Then each route it can take, each with one real call:
# its own login (routecall()), in lg; each local API proxy found (findproxy()), through the CLI with the key of its
# proxy variable, the ones that work in pxok; the provider's own API with the key (apicheck()), in as. Each check, a
# failing one with why, is printed, and named in the CLI's text (desc). Each role is offered the routes of its own CLI that work
# (off); its route is asked when that is more than the CLI's own login, and an answer naming a route not offered is
# refused (exit 2). Adds to need each question still unanswered: the roles' routes; --fallback-route, when a role takes
# the fallback and its CLI has both a proxy and the API; --claude-proxy or --codex-proxy, when more than one proxy
# works for the CLI a role goes through; --claude-key or --codex-key, where the key of a CLI going to its API is kept;
# --claude-proxy-key or --codex-proxy-key, where the key of a CLI going to its proxy is kept, while it is only in the
# shell setup runs in, which the service does not have.
# Sets clis, the CLIs with a route that works, whose route setup writes (routewrite()), and kd, each one's second route
# (proxy, api, or empty for its own login only), with its proxy in pxu. A key file that is not there, not the user's
# own or readable by others, or an answer of settings with no key there, stops setup (exit 1), for an API key or a
# proxy's.
routeask() {
  local c a r o t u k s cs=() asked=''
  local -A off=() pxok=() desc=()
  for r in builder reviewer; do
    if [ -e "$PACK" ]; then s=$(seat "$r" 2>/dev/null) || s=''
    else s=$(jq -cn "$PACK0 | .models.allowed" | jq -c --arg r "$r" --argjson c null "$SEATNOW"'[try seatnow($r; $c)] | first // empty' 2>/dev/null) || s=''; fi
    rcli[$r]=$(jq -r '.agent // empty' <<<"$s" 2>/dev/null)
  done
  for c in claude codex; do
    [ "${rcli[builder]}" = $c ] || [ "${rcli[reviewer]}" = $c ] || continue
    if [ $c = claude ]; then ! jq -e '.claudeProxy | objects' "$HOST" >/dev/null 2>&1 && [ -z "$(claudeproxy)" ] || continue
    else command -v codex >/dev/null && ! jq -e '.codexProxy | objects' "$HOST" >/dev/null 2>&1 || continue; fi
    k=${APIKEY[$c]}; a=${keyarg[$c]:-}
    if [ -z "$a" ]; then routekey "{\"keyEnv\": \"$k\"}"; akf[$c]=''
      [ -n "$KEY_V" ] || { asked=1; need+=("--$c-key <none, settings or the path of a key file that only you can read (mode 600): where your ${APINAME[$c]} API key is kept, for a route through the ${APINAME[$c]} API (none: you use no API key; settings: the $k in the env of $CLAUDE_SETTINGS); now $KEY_FROM, and none is in this shell>"); continue; }
    elif [ "$a" = none ]; then KEY_V=''; akf[$c]=none
    elif [ "$a" = settings ]; then routekey "{\"keyEnv\": \"$k\"}" service
      [ -n "$KEY_V" ] || { echo "conveyor: --$c-key settings: $KEY_FROM; add it there, or answer the path of a key file" >&2; return 1; }
      akf[$c]=settings
    else a=$(cd "$(dirname -- "$a")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename -- "$a")") || a=${keyarg[$c]}
      keyfile "$a" || { echo "conveyor: --$c-key: $KEY_FROM" >&2; return 1; }
      akf[$c]=$a
    fi
    ak[$c]=$KEY_V; cs+=("$c")
  done
  # A key question unanswered: the routes are checked once it is.
  [ -z "$asked" ] || return 0
  for c in "${cs[@]}"; do
    t=$([ $c = claude ] && echo Claude || echo Codex)
    lg[$c]=$(routecall $c ""); s="$t: its own login ${lg[$c]}"; pxok[$c]=''
    # The proxies' key (pk), where --claude-proxy-key or --codex-proxy-key answers it is kept, else in the settings
    # file, else in this shell. pkf: settings, the key file's path, or empty while the key is only in this shell.
    k=${PROXYKEY[$c]}; a=${pkarg[$c]:-}
    if [ -z "$a" ]; then routekey "{\"keyEnv\": \"$k\"}" service; pkf[$c]=${KEY_V:+settings}; [ -n "$KEY_V" ] || routekey "{\"keyEnv\": \"$k\"}"
    elif [ "$a" = settings ]; then routekey "{\"keyEnv\": \"$k\"}" service
      [ -n "$KEY_V" ] || { echo "conveyor: --$c-proxy-key settings: $KEY_FROM; add it there, or answer the path of a key file" >&2; return 1; }
      pkf[$c]=settings
    else a=$(cd "$(dirname -- "$a")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename -- "$a")") || a=${pkarg[$c]}
      keyfile "$a" || { echo "conveyor: --$c-proxy-key: $KEY_FROM" >&2; return 1; }
      pkf[$c]=$a
    fi
    pk[$c]=$KEY_V
    while IFS= read -r u; do
      [ -n "$u" ] || continue
      o=$(routecall $c "" "$(jq -cn --arg b "$u" --arg k "$k" '{kind: "proxy", baseUrl: $b, keyEnv: $k}')" "${pk[$c]}")
      s+=", a local API proxy at $u $o"; [ "$o" != works ] || pxok[$c]+="$u "
    done < <(findproxy "$([ $c = claude ] && echo messages || echo responses)")
    as[$c]=''
    [ -z "${ak[$c]}" ] || { as[$c]=$(apicheck "$([ $c = claude ] && echo anthropic || echo openai)" "$([ $c = claude ] && echo "$ANTHROPIC_API" || echo "$OPENAI_API")" "${ak[$c]}")
      s+=", the ${APINAME[$c]} API with the key in ${APIKEY[$c]} ${as[$c]}"; }
    echo "conveyor: the routes checked for $s." >&2
    desc[$c]="$s. fallback: $t's own login, and its second route (the proxy or the API) when that login fails. proxy: always through the local proxy. api: always through the ${APINAME[$c]} API with your key. subscription: $t's own login only"
    # The answers offered, once each, in this order.
    o=''; [ "${lg[$c]}" = works ] && { [ -n "${pxok[$c]}" ] || [ "${as[$c]}" = works ]; } && o+=', fallback'
    [ -z "${pxok[$c]}" ] || o+=', proxy'; [ "${as[$c]}" != works ] || o+=', api'; [ "${lg[$c]}" != works ] || o+=', subscription'
    off[$c]=${o#, }
    if [ -n "${off[$c]}" ]; then clis+=("$c")
    else echo "conveyor: no route $t can take works now, so none is written and setup asks again on its next run: $s" >&2; fi
  done
  for r in builder reviewer; do
    c=${rcli[$r]}; [ -n "$c" ] && [[ -v off[$c] ]] && [ -n "${off[$c]}" ] || continue
    u=$([ $r = builder ] && echo "$br" || echo "$rr")
    # The CLI's own login is its only route: nothing to ask.
    [ -n "$u" ] || [ "${off[$c]}" != subscription ] || { u=subscription; if [ $r = builder ]; then br=$u; else rr=$u; fi; }
    if [ -z "$u" ]; then asked=1; need+=("--$r-route <${off[$c]}, for $([ $r = builder ] && echo "builds, fixes and rebases" || echo reviews), which run on $c: ${desc[$c]}>")
    elif [[ ", ${off[$c]}, " != *", $u, "* ]]; then echo "conveyor: --$r-route $u is not offered for the $r, which runs on $c (the routes offered: ${off[$c]}): ${desc[$c]}" >&2; return 2; fi
  done
  [ -z "$asked" ] || return 0
  for c in "${clis[@]}"; do
    # The second routes this CLI can take, those its roles name, and whether one of them takes the fallback.
    u=''; [ -z "${pxok[$c]}" ] || u+=' proxy'; [ "${as[$c]}" != works ] || u+=' api'
    a='' o=''
    for r in builder reviewer; do
      [ "${rcli[$r]}" = $c ] || continue; k=$([ $r = builder ] && echo "$br" || echo "$rr")
      [ "$k" != fallback ] || o=1
      if [[ $k == proxy || $k == api ]] && [[ "$a " != *" $k "* ]]; then a+=" $k"; fi
    done
    if [ "$a" = " proxy api" ] || [ "$a" = " api proxy" ]; then
      echo "conveyor: each CLI takes one second route: the builder and the reviewer cannot take the proxy and the API both on $c; answer the same of the two" >&2; return 2
    elif [ -n "$a" ]; then kd[$c]=${a# }
    elif [ -n "$o" ]; then
      if [ "$u" = ' proxy api' ]; then
        [ -n "$fr" ] && kd[$c]=$fr || need+=("--fallback-route <proxy or api: the second route a role that takes the fallback goes to when its login fails, for $c: ${desc[$c]}>")
      else kd[$c]=${u# }; fi
    else kd[$c]=''; fi
    # Which proxy, when more than one works.
    if [ "${kd[$c]:-}" = proxy ]; then
      read -ra s <<<"${pxok[$c]}"
      if [ ${#s[@]} = 1 ]; then pxu[$c]=${s[0]}
      elif [ -z "${pxarg[$c]:-}" ]; then need+=("--$c-proxy <$(printf '%s or ' "${s[@]}" | sed 's/ or $//'): the local API proxy $c goes through: ${desc[$c]}>")
      elif [[ " ${pxok[$c]}" == *" ${pxarg[$c]} "* ]]; then pxu[$c]=${pxarg[$c]}
      else echo "conveyor: --$c-proxy ${pxarg[$c]} is not a local API proxy that works for $c (those that do: ${pxok[$c]% })" >&2; return 2; fi
    fi
    [ "${kd[$c]:-}" != api ] || [ -n "${akf[$c]}" ] \
      || need+=("--$c-key <settings, the ${APIKEY[$c]} in the env of $CLAUDE_SETTINGS ($( [ -n "$(jq -r --arg k "${APIKEY[$c]}" '.env[$k] // empty' "$CLAUDE_SETTINGS" 2>/dev/null)" ] && echo "it is there" || echo "it is not there now")), or the path of a key file that only you can read (mode 600): where the ${APINAME[$c]} API key is kept, so the service's sessions can read it>")
    [ "${kd[$c]:-}" != proxy ] || [ -n "${pkf[$c]}" ] || [ -z "${pk[$c]}" ] \
      || need+=("--$c-proxy-key <settings, the ${PROXYKEY[$c]} in the env of $CLAUDE_SETTINGS, or the path of a key file that only you can read (mode 600): where the local API proxy's key is kept, so the service's sessions can read it; now it is only in this shell>")
  done
  return 0
}
# A CLI's route in the host file, claudeProxy or codexProxy (under the machine's lock, mlocked, as hostput writes the
# host file), from setup()'s answers (routeask()): {kind: "subscription"} when the CLI takes no second route or both
# roles answered subscription; else its kind (proxy or api), base URL, the NAME of the variable its key is read by
# (never the key), the key file's path when the key, the API's or the proxy's, is kept in one, and each role's route.
# A role that names a route this CLI cannot take runs on its own login.
routewrite() { # <claude|codex>
  local n t k r b o
  n=$([ "$1" = claude ] && echo claudeProxy || echo codexProxy); k=${kd[$1]:-}
  r=$(jq -cn --arg k "$k" --arg b "$br" --arg r "$rr" '[$b, $r] | map(if . == "subscription" or $k == "" then "subscription" elif . == "fallback" or . == $k then . else "subscription" end) | {builder: .[0], reviewer: .[1]}')
  if [ -z "$k" ] || [ "$r" = '{"builder":"subscription","reviewer":"subscription"}' ]; then o='{"kind":"subscription"}'
  else
    if [ "$k" = proxy ]; then b=${pxu[$1]}; else b=$([ "$1" = claude ] && echo "$ANTHROPIC_API" || echo "$OPENAI_API"); fi
    o=$(jq -cn --arg k "$k" --arg b "$b" --arg e "$([ "$k" = proxy ] && echo "${PROXYKEY[$1]}" || echo "${APIKEY[$1]}")" --arg f "$(if [ "$k" = api ]; then f=${akf[$1]}; else f=${pkf[$1]}; fi; [ "$f" = settings ] || echo "$f")" --argjson r "$r" \
      '{kind: $k, baseUrl: $b, keyEnv: $e} + (if $f == "" then {} else {keyFile: $f} end) + {roles: $r}')
  fi
  t=$(mktemp "$HOST.XXXXXX") || return 1
  jq --arg n "$n" --argjson o "$o" '.[$n] = $o' "$HOST" > "$t" && mv "$t" "$HOST" \
    || { rm -f "$t"; echo "conveyor: $n could not be written in the host file $HOST" >&2; return 1; }
  if [[ $o == '{"kind":"subscription"}' ]]; then echo "conveyor: wrote $n in the host file $HOST: $1 runs on its own login only"
  else jq -r --arg n "$n" --arg h "$HOST" --arg s "$CLAUDE_SETTINGS" '"conveyor: wrote \($n) in the host file \($h): through \(if .kind == "api" then "the API at " else "the proxy at " end)\(.baseUrl), the builder'"'"'s route \(.roles.builder) and the reviewer'"'"'s \(.roles.reviewer); its key is read from \(.keyEnv) in the env of \($s)\(if .keyFile then ", else from the key file \(.keyFile)" else "" end)"' <<<"$o"; fi
}
# doctor's line on a dependency folder of the main checkout that a new card worktree lacks (depsmissing(),
# lib/push.sh): a test worktree at main's HEAD, linked as a card's is (deps()), then removed. Returns 1 when one is
# missing. With worktree.setup its install fills them, which doctor does not run; with no readable pack, nothing.
doctordeps() {
  local s t c
  packget worktree.setup s 2>/dev/null || return 0
  if [ -n "$s" ]; then echo "ok: the dependencies of each card's worktree: worktree.setup ($s) installs them"
  elif t=$(mktemp -d) && git -C "$MAIN" worktree add -q --detach "$t/w" HEAD >/dev/null 2>&1; then
    deps "$t/w" >/dev/null 2>&1; c=$(depsmissing "$t/w")
    rm -rf "$t"; git -C "$MAIN" worktree prune 2>/dev/null
    [ -n "$c" ] || { echo "ok: a new card worktree has the dependency folders of the main checkout"; return 0; }
    echo "missing: $c in a new card worktree (the main checkout has it, ignored by git, and the tests may need it); fix: add $c to the pack's linkFromMain, or set the pack's worktree.setup to the command that installs it, such as npm ci (/conveyor-belt:setup asks which)"
    return 1
  else [ -z "$t" ] || rm -rf "$t"; echo "not checked: the dependencies of a card's worktree: a test worktree of $MAIN could not be made"; fi
}
# conveyor.sh doctor: each thing Conveyor needs on this machine for the project it is called in, one line each, "ok: ..."
# or "missing: <what>; fix: <how>", and "warning: ..." for a running loop on old code or a Board not running. Exit 1 when anything is missing,
# but for the project's instruction files (agentfiles(), which sessions run without). bash older than 5.1 stops at require_bash, above,
# which says how to get a newer one. The project's checks need jq and git; without either they are named as not checked.
doctor() {
  local bad=0 p e t c h f
  ok() { echo "ok: $1"; }; no() { echo "missing: $1; fix: $2"; bad=1; }
  # Each requirement at its minimum version, as the engine runs it: the version found, and where (lib/requires.sh).
  req_report || bad=1
  if ! command -v gh >/dev/null; then : # named by req_report
  elif timeout 20 gh auth status >/dev/null 2>&1; then ok "gh, signed in"; else no "gh signed in" "run /conveyor-belt:setup, which starts gh auth login"; fi
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
    # With a build machine named (hostfile.sh, the Board's reader: an ssh target and a host that is not this machine),
    # Conveyor runs there, and the project's record names its checkout there under the name setup gives it (hostput):
    # that record serves this checkout, and a record of this checkout would start a second engine on the repository.
    # setup (commands/setup.md) offers no service on this machine when doctor prints this ok line.
    t=${MAIN##*/}; t=${t//[^A-Za-z0-9._-]/-}; c=${HERE%/*}/.claude/scripts/hostfile.sh; h=''
    [ -n "$e" ] || [ ! -f "$c" ] || ! jq -e --arg n "$t" 'any(.records | arrays | .[] | objects; .repo == $n)' "$HOST" >/dev/null \
      || h=$(bash "$c" "$MAIN" 2>/dev/null | jq -r 'select(.local == false) | .host | strings')
    if [ -n "$h" ]; then ok "the project $t is served on the build machine $h (its record of the host file $HOST): Conveyor for it runs there, not on this machine"
    elif [ -z "$e" ]; then no "a record of the host file $HOST for this checkout $MAIN (the machine's Conveyor serves only the checkouts its records name)" \
      "run /conveyor-belt:setup; when it says another record has this checkout's name, add {\"repo\": \"<name>\", \"main\": \"$MAIN\"} to the host file's records by hand"; fi
    # The Board reads the project as the host file says, by its own reader (dashboard.sh --check): on this machine, or
    # over ssh on a build machine the host file names. When it cannot, every Board panel says so: this names why.
    f=${HERE%/*}/.claude/scripts/dashboard.sh
    if [ ! -f "$f" ]; then echo "not checked: the Board reading the project: this copy of Conveyor has no $f"
    elif t=$(CONVEYOR_MAIN=$MAIN bash "$f" --check 2>&1); then ok "the Board reads the project ${t##*$'\n'}"
    else no "the Board reading the project (${t//$'\n'/; })" \
      "correct the host file $HOST as that says; on one machine it needs no host, main or ssh, only its records"; fi
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
  # The Board is optional, so one not running is a warning with its fix (bad stays 0), named by its address. One that
  # runs older Conveyor than the project's (boardold) is missing: it may not read what this one writes, such as the
  # host file setup writes, and shows no card.
  e=$(boardold | head -n 1)
  if [ -n "$e" ]; then IFS=$'\t' read -r _ t c <<<"$e"
    no "the Board runs engine $t but the project has $c" "run /conveyor-belt:setup, which starts it again on $c, or conveyor.sh board in the project's checkout"
  elif ! command -v curl >/dev/null; then echo "not checked: the Board: it is checked with curl"
  elif boardup; then ok "the Board, running at $(boardurl)"
  elif boardcert; then echo "warning: something answers on $(boardurl) but fails the check of the Board's certificate (curl exit $BOARD_CURL); fix: run conveyor.sh board in the project's checkout, which replaces a certificate that does not name its curve and restarts the Board"
  else echo "warning: the Board is not running (nothing serves $(boardurl)); fix: run /conveyor-belt:setup and answer yes to \"Start the Board now?\", or conveyor.sh board in the project's checkout"; fi
  agentfiles
  if ! command -v jq >/dev/null || ! type -P git >/dev/null; then
    echo "not checked: the pack, its models' programs, the pin and the terms file: they are read with jq and git"; return 1
  fi
  git -C "$CALLED" rev-parse --git-dir >/dev/null 2>&1 || { no "a git checkout of the project at $CALLED" "run conveyor.sh doctor in the project's checkout"; return 1; }
  if [ ! -e "$PACK" ]; then no "the pack $PACK" "run /conveyor-belt:setup"; return 1; fi
  e=$("$HERE/lib/pack.sh" check "$PACK" 2>&1) || { no "a valid pack" "correct what the check names: ${e//$'\n'/; }"; return 1; }
  ok "the pack $PACK"
  # The pack's test-file globs: they must find the project's tests (testcheck()).
  testcheck || bad=1
  # The control record setup writes (heldstart()): with none, the loop would queue every open issue. With one, the
  # open issues it holds.
  if [ ! -s "$CONTROL" ]; then no "the control record $CONTROL (with none, the loop queues every open issue)" "run /conveyor-belt:setup, which writes it with every open issue held"
  elif c=$(ctl 2>/dev/null) && e=$(timeout 60 gh issue list --state open --limit 100000 --json number 2>/dev/null | jq -e --argjson c "$c" '[.[].number | select(IN($c.held[]))] | length'); then
    ok "$(heldline "$e")"
  fi
  # Card records an older engine left in another state folder (strays()): the belt, retry and health do not read them.
  while IFS= read -r f; do
    e=$(jq -Rnr '[inputs | fromjson? | objects] | group_by(.card)[] | select(map(select(.step | IN("landed", "closed", "blocked", "pushed"))) | last | .step == "blocked")
      | "#\(.[0].issue)"' "$f/cards.jsonl" 2>/dev/null | sort -u | paste -sd' ' -)
    no "card records only in the state folder $ST: $f holds others, written by an older engine (blocked there: ${e:-none})" \
      "this belt never reads them; for each blocked issue you want built, run \`conveyor.sh control release <issue>\` if it is held, then move $f away"
  done < <(strays)
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
  # `TESTRUN sec` lines and Conveyor read no report of its runner. A warning: the cards still run, held to no CPU
  # budget. When setup found a runner whose report Conveyor cannot read now (test.report with no format), it names the
  # runner and its option that would give them.
  e=$(stdb ask lines cards 2>/dev/null | jq -s "$UNTIMED"' untimed' 2>/dev/null) || e=0
  t=$(jq -r '.test.report | objects | select(.format == null and .option) | "; the test command runs \(.runner), whose report option \(.option) would give them"' "$PACK" 2>/dev/null) || t=''
  [[ ! $e =~ ^[1-9][0-9]*$ ]] || echo "warning: the last $e card test run$([ "$e" = 1 ] || echo s) recorded no test times: the test command prints no \`TESTRUN sec\` lines; conveyor/README.md, The CPU budget of a test file, says how to add them$t"
  if packget privacy.mode e && [ "$e" = public ]; then
    if t=$(termsfile); then ok "the terms file $t"
    elif termsnamed; then no "a readable terms file (the host file $HOST names one, or does not read, and the pack's privacy.mode is public)" "make the file it names readable, or take \"terms\" out of $HOST"
    else ok "no terms file (it is optional): the privacy check runs with no word list"; fi
  fi
  ! command -v jq >/dev/null || doctordeps || bad=1
  return $bad
}
