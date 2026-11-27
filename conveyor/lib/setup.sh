# SPDX-License-Identifier: Apache-2.0
# /conveyor-belt:setup (plan sections 7 and 9), run by the plugin copy in the project's checkout (MAIN), safe to run
# again: it changes only what is not there yet.
# The pack, when there is none: the owner, the product paths and the test command have no safe default and are passed
# in (none passed: it says which it needs and writes nothing); test.full, the full test suite the Board's Push landed
# runs, is the test command too (given no list, it runs whole), so a new install can push what it lands;
# test.slowIssues is false (it files nothing: the test
# rules, test.rules, replace it, and with no test.rules their switch is off and no rule is on); models.allowed is
# not written, so the project follows the models the CLIs report (modelsallowed()); every other field is PACK0's, the default branch
# origin's (never the checked-out branch, which may be a feature branch: when origin's cannot be read, nothing is
# written). A pack already there is never rewritten: one that fails the check stops setup.
# The plugin, when the pack names none: the plugin's releases, followed (plugin.follow), or with --pin the commit of
# the plugin copy that runs this. A plugin already named (a pack following main too) is never changed. Then the pinned
# commit is installed (install(): a verified install is left as it is), or the followed engine is taken (take()), and each label the pack names
# that the repo lacks is created (GitHub's label names are not case-sensitive), through gh_write.
PACK0='{labels: {built: "awaiting-deploy", followup: "conveyor-followup", type: "bug", priorities: ["P0", "P1", "P2"],
    areaPrefix: "area:", nonProductAreas: []},
  linkFromMain: [], push: {env: {}}, remote: "origin", models: {},
  lanes: {research: {model: "claude-fable-5-2", effort: "medium"}},
  privacy: {mode: "public"}, auto: {standing: []}}'
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
# while the pack sets no tests.patterns and the test command's runner config names test files, or the default misses
# tracked files that read as tests (testoffer()), naming each glob, how many tracked files it matches and where it was
# read; yes writes them as the pack's tests.patterns.
# The question "Set the pack's test.fileCommand?": answered by --file-command yes|no, and asked (exit 2, nothing
# written) while the pack sets no test.fileCommand and the test command runs a runner listguess() knows that takes test
# files as arguments (args), naming it; yes writes the test command as the pack's test.fileCommand, which a card runs
# each of its test files alone with, the file's path at its end (filecmd(), lib/testrun.sh).
# The question "Make the test map?": answered by --test-map yes|no, and asked (exit 2, nothing written) while the pack
# sets no test.map, there is no made map and the project's language has a coverage tool the map knows (lib/testmap.sh
# maptool()), naming the tool and what the run may cost (mapcost()); yes runs the whole suite under coverage and
# writes the map (mapbuild()), no writes test.map off. With no such tool, setup says so: a card's tests are found by
# name.
# The question "Which command lints the project?" (docs/setup.md): asked by /conveyor-belt:setup while the pack has no
# lint field, answered by --lint <command> with --lint-files <pathspec> (one for each). The command is probed as doctor
# probes it (setuplint()) and written in the pack's lint.commands only when the probe says ok or findings.
# While the pack has no lint field, setup also offers a ready entry for shellcheck, ruff and ESLint, each only when
# the project tracks that tool's config (lintready()), answered by --lint-ready; a pyproject.toml that holds ruff's
# config is asked of apart, --lint-shared, as lint policy (setupready()). A project with files of a language that has
# no ready entry and no lint command of the pack on them is told what checks them (lintother()): only their length
# when a size entry covers them, else nothing.
# The question "Limit the length of files?" (docs/setup.md) is asked by /conveyor-belt:setup, answered by --size <lines>
# or --size no, with --size-files <pathspec> (one for each) and --size-skip <folder> (one for each, left out). On a
# limit, setupsize() writes a size entry in the pack's lint.commands, the exempt file .conveyor/size-exempt.txt naming
# each file the entry reads that is over the limit now, and that file in lint.policy; at its end each run, setup names the
# pack and that file there too when the entry reads them and they are over the limit by then (sizeself()). The entry is
# written last, after every other file setup writes, and only on the run that finds the pack with none.
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
SETUP_USAGE='setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--test-patterns yes|no] [--file-command yes|no] [--test-machine yes|no] [--test-map yes|no] --fast-lane yes|no --research-lane yes|no [--link yes|no] [--worktree-setup <command>] [--lint <command> --lint-files <pathspec>...] [--lint-ready yes|no] [--lint-shared yes|no] [--size <lines>|no] [--size-files <pathspec>]... [--size-skip <folder>]... [--builder-route subscription|fallback|proxy|api] [--reviewer-route subscription|fallback|proxy|api] [--fallback-route proxy|api] [--claude-key none|settings|<key file>] [--codex-key none|settings|<key file>] [--claude-proxy <base URL>] [--codex-proxy <base URL>] [--claude-proxy-key settings|<key file>] [--codex-proxy-key settings|<key file>] [--pin] [--foreman]'
setup() { # as SETUP_USAGE
  local owner='' test='' prods=() need=() b p f have l n x fm='' pin='' sv='' fl='' rl='' br='' rr='' fr='' w first full c lk='' ws='' lf='' wsx='' dds=() lks tp='' tpa='' tn tl='' tla='' tmc='' tma='' tmt='' tmw='' lc='' lfs=() lra='' lsa='' lro='' sz='' szf=() szs=()
  local -A keyarg=() pxarg=() pkarg=() rcli=() lg=() pxu=() ak=() akf=() pk=() pkf=() as=() kd=(); local clis=()
  local ask='--survey <yes or no: run a first test-speed survey now?>'
  while [ $# -gt 0 ]; do
    [ "$1" != --foreman ] || { fm=1; shift; continue; }
    [ "$1" != --pin ] || { pin=1; shift; continue; }
    case $1 in --owner) owner=${2-} ;; --product) prods+=("${2-}") ;; --test) test=${2-} ;;
      --survey) sv=${2-}; [[ $sv == yes || $sv == no ]] || { set -- x; break; } ;;
      --test-patterns) tpa=${2-}; [[ $tpa == yes || $tpa == no ]] || { set -- x; break; } ;;
      --file-command) tla=${2-}; [[ $tla == yes || $tla == no ]] || { set -- x; break; } ;;
      --test-machine) tmc=${2-}; [[ $tmc == yes || $tmc == no ]] || { set -- x; break; } ;;
      --test-map) tma=${2-}; [[ $tma == yes || $tma == no ]] || { set -- x; break; } ;;
      --fast-lane) fl=${2-}; [[ $fl == yes || $fl == no ]] || { set -- x; break; } ;;
      --research-lane) rl=${2-}; [[ $rl == yes || $rl == no ]] || { set -- x; break; } ;;
      --link) lk=${2-}; [[ $lk == yes || $lk == no ]] || { set -- x; break; } ;;
      --worktree-setup) ws=${2-}; [ -n "$ws" ] || { set -- x; break; } ;;
      --lint) lc=${2-}; [ -n "$lc" ] || { set -- x; break; } ;;
      --lint-files) lfs+=("${2-}"); [ -n "${2-}" ] || { set -- x; break; } ;;
      --size) sz=${2-}; [[ $sz =~ ^([1-9][0-9]*|no)$ ]] || { set -- x; break; } ;;
      --size-files) szf+=("${2-}"); [ -n "${2-}" ] || { set -- x; break; } ;;
      --size-skip) szs+=("${2-}"); [[ -n ${2-} && ${2-} != /* && ${2-} != *\** ]] || { set -- x; break; } ;;
      --lint-ready) lra=${2-}; [[ $lra == yes || $lra == no ]] || { set -- x; break; } ;;
      --lint-shared) lsa=${2-}; [[ $lsa == yes || $lsa == no ]] || { set -- x; break; } ;;
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
  # --lint-files names the files of --lint's command only: given alone, it is a wrong call.
  [ -n "$lc" ] || [ ${#lfs[@]} = 0 ] || set -- x
  # --size-files and --size-skip belong to --size <lines>: given with no limit, or with no, they are a wrong call.
  { [ -n "$sz" ] && [ "$sz" != no ]; } || [ $((${#szf[@]} + ${#szs[@]})) = 0 ] || set -- x
  [ $# = 0 ] || { echo "usage: conveyor.sh $SETUP_USAGE" >&2; return 2; }
  [ -z "$lc" ] || [ ${#lfs[@]} -gt 0 ] || need+=("--lint-files <a git pathspec of the files the lint command reads> (one for each)")
  [ -z "$sz" ] || [ "$sz" = no ] || [ ${#szf[@]} -gt 0 ] || need+=("--size-files <a git pathspec of the files that the size limit reads> (one for each)")
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
  # The project's test files, when the pack sets no tests.patterns and the runner's config names them or the default
  # misses files that read as tests (testoffer()): asked, as the lanes are, naming each glob, how many tracked files
  # it matches and where it was read; yes writes them.
  if [ "$tpa" != no ] && ! jq -e '.tests.patterns' "$PACK" >/dev/null 2>&1; then
    x=$test; [ ! -e "$PACK" ] || packget test.command x 2>/dev/null || x=''
    [ -z "$x" ] || tp=$(testoffer "$x") || tp=''
    if [ -n "$tp" ] && [ -z "$tpa" ]; then
      tn=$(testcount "$(jq -c 'map(.p)' <<<"$tp")") || return 1
      if jq -e 'any(.[]; .from == "default")' <<<"$tp" >/dev/null; then
        n=$(testcount "$(jq -c '.properties.tests.properties.patterns.default' "$SCHEMA")") || return 1
        w="the default test-file patterns miss $((tn - n)) tracked files that read as tests"
      else w="the test command and its runner's config name the project's test files"; fi
      w+="; set the pack's tests.patterns to $(jq -r 'map(.p + " (\(.n) tracked file" + (if .n == 1 then "" else "s" end)
        + (if .from == "default" then "" elif .from == "names" then ", by the names of tracked files" else ", from \(.from)" end) + ")") | join(", ")' <<<"$tp")"
      need+=("--test-patterns <yes or no: $w, which match $tn tracked files?>")
    fi
  fi
  # The command a card runs each of its test files alone with, while the pack sets no test.fileCommand and the test
  # command runs a runner listguess() knows that takes test files as arguments: asked, naming the runner; yes writes
  # the test command as it. A runner of packages or test targets (go test, cargo test) runs no one file so: not asked.
  if [ "$tla" != no ] && ! jq -e '.test.fileCommand | strings | select(. != "")' "$PACK" >/dev/null 2>&1; then
    x=$test; [ ! -e "$PACK" ] || packget test.command x 2>/dev/null || x=''
    [ -z "$x" ] || tl=$(listguess "$x") || tl=''
    [ "${tl%% *}" = args ] || tl=''
    if [ -n "$tl" ] && [ -z "$tla" ]; then
      need+=("--file-command <yes or no: the test command runs ${tl#* }, which takes test files as arguments; set the pack's test.fileCommand to the test command, so a card runs each of its test files alone through it?>")
    fi
  fi
  # The test map, while the pack sets no test.map and there is none (lib/testmap.sh): asked, naming the coverage tool
  # and what the run may cost (mapcost()); a project whose language has no tool the map knows is told so.
  if [ "$tma" != no ] && ! jq -e '.test.map' "$PACK" >/dev/null 2>&1 && [ ! -s "$(mappath)" ]; then
    if tmt=$(maptool "$(maplang "$MAIN")" "$MAIN"); then
      [ -n "$tma" ] || need+=("--test-map <yes or no: run the whole suite once with $tmt to make the test map (which test files cover which source files), so a card runs only the tests that cover its change? $(mapcost)>")
    else tmw=$tmt; tmt=''; fi
  fi
  # The ready lint entries, while the pack has no lint field: asked once for all that are offered, naming each tool
  # and its config; the pyproject.toml that holds ruff's config is asked of apart, for lint.policy. lro is the offer,
  # [] when no tool's config is there; empty when the pack has a lint field, and nothing is asked.
  if ! jq -e '.lint' "$PACK" >/dev/null 2>&1; then
    lro=$(lintready "$MAIN") || return 1
    if [ "$lro" != '[]' ] && [ "$lra" != no ]; then
      [ -n "$lra" ] || need+=("--lint-ready <yes or no: write the ready lint entries, $(jq -r 'map("\(.tool) (for \(.entry.triggers | join(", ")))") | join(", ")' <<<"$lro"), in the pack's lint.commands? Each reads the files only, adds no rule, and is skipped while its tool is not installed>")
      [ -n "$lsa" ] || ! jq -e 'any(.[]; .shared != [])' <<<"$lro" >/dev/null \
        || need+=("--lint-shared <yes or no: pyproject.toml holds ruff's config: put it in the pack's lint.policy, so that a card that changes it stops for your yes?>")
    fi
  fi
  # Before anything outside the checkout is changed (the survey issue, the labels): a pathspec git refuses stops the run here,
  # so a run the owner corrects files nothing twice. A pack that has a size entry already gets none (setupsize()).
  if [ -n "$sz" ] && [ "$sz" != no ]; then
    for x in "${szs[@]}"; do szf+=(":(exclude)${x%/}/*"); done
    jq -e 'any(.lint.commands[]?; .size)' "$PACK" >/dev/null 2>&1 || git -C "$MAIN" ls-files -z --cached --others --exclude-standard -- "${szf[@]}" > /dev/null \
      || { echo "conveyor: the files of $MAIN could not be listed for the size limit: check the --size-files and --size-skip pathspecs" >&2; return 1; }
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
  if [ -n "$f" ]; then take wait && enginepin p && [ -n "$p" ] || { echo "conveyor: no commit of the plugin's $f is taken on this machine; conveyor.sh doctor says why" >&2; return 1; }
  else install "$p" || return 1; fi
  # Before hostadd: once the host file names the project, a machine's service already running serves it.
  heldstart || return 1
  hostadd || return 1
  # Before any other pack field is written: a machine's service on older Conveyor than the project's commit refuses
  # a field its schema does not name, so it is started again on that commit first (servicerenew()).
  servicerenew || return 1
  # dds is read only while the pack has neither: what the owner wrote in either is kept.
  if [ "$lk" = yes ] && [ ${#dds[@]} -gt 0 ]; then
    jq '.linkFromMain = $ARGS.positional' "$PACK" --args "${dds[@]}" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the dependency folders could not be written as the pack's linkFromMain" >&2; return 1; }
    echo "conveyor: wrote the pack's linkFromMain: $(printf '%s, ' "${dds[@]}" | sed 's/, $//'), linked from the main checkout into each card's worktree"
  fi
  if [ -n "$ws" ] && [ -z "$wsx" ]; then
    jq --arg s "$ws" '.worktree.setup = $s' "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: worktree.setup could not be written in the pack" >&2; return 1; }
    echo "conveyor: wrote the pack's worktree.setup: $ws, run in each card's worktree before its build and tests"
  fi
  if [ "$lra" = yes ] && [ -n "$lro" ] && [ "$lro" != '[]' ]; then setupready "$p" "$lro" "$lsa" || return 1; fi
  [ -z "$lc" ] || setuplint "$p" "$lc" "${lfs[@]}" || return 1
  if [ "$tpa" = yes ] && [ -n "$tp" ]; then
    tp=$(jq -c 'map(.p)' <<<"$tp") || return 1
    jq --argjson p "$tp" '.tests.patterns = $p' "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's tests.patterns could not be written" >&2; return 1; }
    echo "conveyor: wrote the pack's tests.patterns: $(jq -r 'join(", ")' <<<"$tp") ($(testcount "$tp") tracked files)"
  fi
  if [ "$tla" = yes ] && [ -n "$tl" ]; then
    jq '.test.fileCommand = .test.command' "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's test.fileCommand could not be written" >&2; return 1; }
    echo "conveyor: wrote the pack's test.fileCommand: $(jq -r '.test.command' "$PACK") (the test command runs ${tl#* }), which a card runs each of its test files alone with"
  fi
  # Yes runs the whole suite under coverage now and writes the map, saying what it mapped and how long it took; a run
  # that fails says so, and the cards' tests are found by name. No writes test.map off, so it is not asked again.
  [ -z "$tmw" ] || echo "conveyor: no test map: $tmw; a card's tests are found by name"
  filehint
  machineoffer "$tmc" || return 1
  if [ "$tma" = yes ] && [ -n "$tmt" ]; then mapbuild "$MAIN" || :
  elif [ "$tma" = no ] && ! jq -e '.test.map' "$PACK" >/dev/null 2>&1; then
    jq '.test.map = "off"' "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's test.map could not be written" >&2; return 1; }
    echo "conveyor: wrote the pack's test.map: off; a card's tests are found by name"
  fi
  # How Conveyor reads the test times from the runner's own report (test.report, reportguess()), while the pack names
  # no format: written again each run, so a report option added to the test command since is found.
  if ! jq -e '.test.report.format' "$PACK" >/dev/null 2>&1 && packget test.command x && x=$(reportguess "$x") && [ -n "$x" ] \
    && ! jq -e --argjson r "$x" '.test.report == $r' "$PACK" >/dev/null 2>&1; then
    jq --argjson r "$x" '.test.report = $r' "$PACK" > "$PACK.new" && "$HERE/lib/pack.sh" check "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the pack's test.report could not be written" >&2; return 1; }
    jq -r '"conveyor: wrote the pack'"'"'s test.report: the test command runs \(.runner), "
      + if .format then "and Conveyor reads each test file'"'"'s clock seconds from its report (\(.format), \(if .env or .args then "which Conveyor asks it for at each run" else .path // "its output" end))"
        else "whose output gives no test times Conveyor can read; its option \(.option) would" end' <<<"$x"
  fi
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
    jq --argjson a "$([ "$sv" = yes ] && echo true || echo false)" '.test.firstSurvey = $a' "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
      || { rm -f "$PACK.new"; echo "conveyor: the answer to the first test-speed survey could not be saved in the pack" >&2; return 1; }
    echo "conveyor: saved the answer to the first test-speed survey ($sv) as the pack's test.firstSurvey"
  fi
  timinghint || return 1
  # The default state folder, conveyor/state in the checkout, is never committed: git's exclude file for the
  # repository (read by every worktree of it, as deps() in lib/push.sh uses it) names it, once.
  x=$(git -C "$MAIN" rev-parse --path-format=absolute --git-path info/exclude) && mkdir -p "${x%/*}" \
    && { grep -qxF /conveyor/state/ "$x" 2>/dev/null || { { [ ! -s "$x" ] || [ -z "$(tail -c 1 "$x")" ] || echo >> "$x"; } && echo /conveyor/state/ >> "$x" && echo "conveyor: wrote /conveyor/state/ in git's exclude file $x, so git leaves out the state folder"; }; } \
    || { echo "conveyor: the state folder conveyor/state/ could not be added to git's exclude file" >&2; return 1; }
  for c in "${clis[@]}"; do mlocked routewrite "$c" || return 1; done
  [ "$fl" = no ] || setuplane fast || return 1
  if [ "$rl" = yes ]; then
    # A pack an earlier setup wrote has no lanes.research, which the lane's create needs: PACK0's is written in.
    packget lanes.research x || return 1
    [ -n "$x" ] || { jq ".lanes.research = ($PACK0).lanes.research" "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
      && echo "conveyor: wrote the research lane's model and effort as the pack's lanes.research"; } \
      || { rm -f "$PACK.new"; echo "conveyor: the research lane's model and effort could not be written in the pack" >&2; return 1; }
    setuplane research || return 1
  fi
  [ -z "$fm" ] || CONVEYOR_MAIN=$MAIN bash "$HERE/foreman/foreman.sh" setup || return 1
  # A Board left on older Conveyor would keep running it (it may not read the host file just written): started again.
  boardrenew
  agentfiles
  # Last of the writes, so the first count sees the files setup wrote (.conveyor/test-machine.sh, say)
  # and no stop after the entry leaves it without its exemptions (sizeself(), run by setupsize()). Each run says the
  # languages the entry covers (lintother()), one the pack has already too.
  [ "${#szf[@]}" = 0 ] || setupsize "$p" "$sz" "${szf[@]}" || return 1
  lintother "$MAIN" || return 1
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
# `conveyor.sh setup desktop`: /units for Claude Desktop's Chat tab, as the bundle conveyor-units.mcpb in the state
# folder's desktop/: a zip of manifest.json (written here) and the plugin's desktop/units-mcp/server.py and view.html.
# The manifest runs server.py with the python3 found here (3.11 or newer, as server.py needs) and this PATH, as Desktop
# starts it with neither, and with its one user config value, the checkout, set to this project's main checkout, where
# the server runs the fetch. On macOS it opens the bundle, so Claude Desktop asks to install it; elsewhere it prints
# the path.
desktopbundle() {
  local src=$HERE/../desktop/units-mcp d=$ST/desktop py v t rc
  [ $# = 0 ] || { echo "usage: conveyor.sh setup desktop" >&2; return 2; }
  [ -f "$src/server.py" ] && [ -f "$src/view.html" ] || { echo "conveyor: $src has no server.py or view.html: the Desktop bundle is not built" >&2; return 1; }
  py=$(command -v python3) && "$py" -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
    || { echo "conveyor: the Desktop bundle needs python3 3.11 or newer on PATH: the bundle is not built" >&2; return 1; }
  v=$(jq -er '.version | strings' "$HERE/../.claude-plugin/plugin.json") || { echo "conveyor: the plugin's version cannot be read: the Desktop bundle is not built" >&2; return 1; }
  mkdir -p "$d" && t=$(mktemp -d "$d/build.XXXXXX") || return 1
  jq -n --arg v "$v" --arg py "$py" --arg path "$PATH" --arg main "$MAIN" '{manifest_version: "0.3", name: "conveyor-units",
    display_name: "Conveyor /units", version: $v, description: "Conveyor'"'"'s board in the Chat tab: what needs you, the belt, the queue and today'"'"'s dollars. It only reads.",
    author: {name: "Conveyor"}, license: "Apache-2.0",
    server: {type: "python", entry_point: "server.py",
      mcp_config: {command: $py, args: ["${__dirname}/server.py", "${user_config.checkout}"], env: {PATH: $path}}},
    user_config: {checkout: {type: "directory", title: "Project checkout",
      description: "The main checkout of a project that Conveyor runs, where /units reads the board.", required: true, default: $main}},
    compatibility: {platforms: ["darwin", "win32", "linux"], runtimes: {python: ">=3.11"}}}' > "$t/manifest.json" \
    && (cd "$t" && "$py" -m zipfile -c bundle.mcpb manifest.json "$src/server.py" "$src/view.html") && mv -f "$t/bundle.mcpb" "$d/conveyor-units.mcpb"; rc=$?
  rm -rf "$t"
  [ "$rc" = 0 ] || { echo "conveyor: the Desktop bundle could not be written in $d" >&2; return 1; }
  if p_darwin; then
    open "$d/conveyor-units.mcpb" || { echo "conveyor: $d/conveyor-units.mcpb could not be opened: open it in Claude Desktop" >&2; return 1; }
    echo "opened $d/conveyor-units.mcpb: Claude Desktop asks to install it"
  else
    echo "$d/conveyor-units.mcpb: open it in Claude Desktop to install it"
  fi
}
# `conveyor.sh setup pack-commit [yes | no]`: the pack (.conveyor/project.json) committed on the default branch, in the
# main checkout, when it is not committed or differs from its commit; /conveyor-belt:setup and the Foreman ask the owner
# first, so the owner never types a git command. With no answer it commits nothing: it prints `ask: <the question>` and
# the change, or `ok: the pack is committed` when there is nothing to commit. yes commits only the pack and the exempt
# files of its size entries that are on disk or in the commit (lint.commands[].size.exempt; setupsize() writes one); other changes in the checkout,
# staged or not, are left as they are. The commit is "Add the Conveyor pack" when the default branch has no
# pack yet, else "Update the Conveyor pack"; it is pushed to the pack's remote when the control record's rule "Push
# when a card lands" (rules.push) is on; no commits nothing and says the pack stays on this machine. With the default
# branch not checked out, or a conflict in the pack, it says so, asks nothing and commits nothing (exit 1). A push
# that takes more than PACK_PUSH seconds is stopped: the commit stays, and it says so (exit 1).
# CONVEYOR_PACK_PUSH, when set, is used in place of the 30 s limit (the tests' seam).
PACK_PUSH=${CONVEYOR_PACK_PUSH:-30}
packcommit() {
  local f=.conveyor/project.json st on msg out rc o p x
  local -a fs
  [ $# -le 1 ] && [[ ${1-ask} =~ ^(ask|yes|no)$ ]] || { echo "usage: conveyor.sh setup pack-commit [yes | no]" >&2; return 2; }
  # The pack's size entries' exempt files go with it: a card reads them from main (lintsize()), so a pack committed
  # without its exempt file would stop the cards on the files that setup named in it.
  fs=("$f")
  # An exempt file that is not on disk and not in the commit is left out: git add fails on a path it does not know.
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    if [ -e "$MAIN/$x" ] || git -C "$MAIN" cat-file -e "HEAD:$x" 2>/dev/null; then fs+=("$x"); fi
  done < <(jq -r '.lint.commands[]? | .size.exempt // empty' "$MAIN/$f" 2>/dev/null)
  st=$(git -C "$MAIN" status --porcelain -- "${fs[@]}") || return 1
  [ -n "$st" ] || { echo "ok: the pack is committed"; return 0; }
  # Before the pack is read (names): a pack with conflict marks in it fails its check.
  [[ $(git -C "$MAIN" status --porcelain -- "$f" | cut -c1-2) =~ ^(DD|AU|UD|UA|DU|AA|UU)$ ]] \
    && { echo "conveyor: $MAIN/$f has a conflict; resolve it, then run /conveyor-belt:setup again: the pack is not committed" >&2; return 1; }
  names || return 1
  on=$(git -C "$MAIN" symbolic-ref -q --short HEAD)
  [ "$on" = "$BRANCH" ] || { echo "conveyor: $MAIN has ${on:-a detached HEAD} checked out, not the default branch $BRANCH: the pack is not committed" >&2; return 1; }
  case ${1-ask} in
    ask)
      echo "ask: Commit the Conveyor pack ($f) on $BRANCH now?"
      if git -C "$MAIN" cat-file -e "HEAD:$f" 2>/dev/null; then git -C "$MAIN" --no-pager diff HEAD -- "$f"
      else git -C "$MAIN" --no-pager diff --no-index -- /dev/null "$f"; fi
      [ ${#fs[@]} = 1 ] || echo "and the exempt files of its size entries: ${fs[*]:1}"
      return 0 ;;
    no)
      echo "conveyor: the pack is not committed: cards read the pack from $BRANCH, so it stays on this machine until it is committed"
      return 0 ;;
  esac
  git -C "$MAIN" cat-file -e "HEAD:$f" 2>/dev/null && msg='Update the Conveyor pack' || msg='Add the Conveyor pack'
  # A commit with a path commits that path alone (git commit --only): the index's other entries stay staged.
  out=$(git -C "$MAIN" add -- "${fs[@]}" 2>&1 && git -C "$MAIN" commit -q -m "$msg" -- "${fs[@]}" 2>&1) \
    || { echo "conveyor: the pack was not committed: $out" >&2; return 1; }
  echo "conveyor: committed ${fs[*]} on $BRANCH: $msg ($(git -C "$MAIN" rev-parse --short HEAD))"
  if [ "$(ctl 2>/dev/null | jq -r '.rules.push')" = true ]; then
    # The push runs under PACK_PUSH seconds, in a process group of its own (timeout's) that is ended whole at the limit,
    # with no terminal prompt and no stdin. The project's pre-push hook can wait minutes for a test slot that the
    # cards of a running engine hold, and git can wait for a password. foreman.sh ask ends its command at ASK_LIMIT
    # (45 s), so with no limit here the ask ended pack-commit after its commit, in the middle of the push (#1106).
    # The ask's limit ends only its own process group, which the push's is not: pack-commit ended by a signal (TERM,
    # INT or HUP) first ends the push, as timeout ends its group on TERM. The push writes to a file, holding no copy
    # of the caller's output (the $( ) of the ask, or LOGFD, the engine's stderr), so none is held open after that.
    o=$(mktemp) || { echo "conveyor: the pack's commit was not pushed: no temporary file for the push's output" >&2; return 1; }
    GIT_TERMINAL_PROMPT=0 timeout -k 2 "$PACK_PUSH" git -C "$MAIN" push -q "$REMOTE" "$BRANCH" > "$o" 2>&1 < /dev/null 8>&- {LOGFD}>&- &
    p=$!
    trap 'kill -TERM "$p" 2>/dev/null; rm -f "$o"; exit 143' TERM INT HUP # run in wait, below: p and o are in scope
    wait "$p"; rc=$?
    trap - TERM INT HUP
    out=$(cat "$o"); rm -f "$o"
    case $rc in
      0) ;;
      124 | 137) echo "conveyor: the pack's commit was not pushed to $REMOTE $BRANCH: the push took more than ${PACK_PUSH}s, so it was stopped; it goes with main's next push" >&2; return 1 ;;
      *) echo "conveyor: the pack's commit was not pushed to $REMOTE $BRANCH: $out" >&2; return 1 ;;
    esac
    echo "conveyor: pushed it to $REMOTE $BRANCH"
  else
    echo "conveyor: not pushed, as the rule \"Push when a card lands\" is off: it goes with main's next push"
  fi
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
# pinreads <commit> <new pack>: exit 0 when the project's commit (its install's pack.sh) reads the new pack. A field
# this setup writes may not be in the schema of an older commit the project runs, whose engine would then refuse the
# whole pack, so the field is not written: what its check says, and what to do, on stderr.
pinreads() {
  local o
  o=$(bash "$VERSIONS/$1/conveyor/lib/pack.sh" check "$2" 2>&1) && return 0
  echo "conveyor: Conveyor commit $1, which the project runs, cannot read the pack with this field (${o//$'\n'/; }); move the project to a newer commit of the plugin (the pack's plugin), or leave the field out, then run setup again" >&2
  return 1
}
# setuplint <commit> <command> <pathspec>...: the project's own lint command (--lint, its files --lint-files), probed
# as doctor probes it (lintprobe(), lib/lint.sh). The probe says ok or findings: the command is added at the end of
# the pack's lint.commands. It says missing, error or empty: nothing is written, and setup says why and goes on. A
# command the pack's lint.commands already runs is not probed or written again.
setuplint() {
  local p=$1 r=$2 c t o; shift 2
  jq -e --arg r "$r" 'any(.lint.commands[]?; .run == $r)' "$PACK" >/dev/null && { echo "conveyor: the pack's lint.commands already has the lint command $r"; return 0; }
  c=$(jq -cn --arg r "$r" '{files: $ARGS.positional, run: $r}' --args "$@") && t=$(mktemp -d) || return 1
  o=$(lintprobe "$c" "$t"); rm -rf "$t"
  case $o in
    ok|findings:*)
      jq --argjson c "$c" '.lint.commands = (.lint.commands // []) + [$c]' "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
        || { rm -f "$PACK.new"; echo "conveyor: the lint command $r could not be written in the pack's lint.commands" >&2; return 1; }
      echo "conveyor: wrote the lint command $r in the pack's lint.commands (the probe says $o)" ;;
    missing:*) echo "conveyor: the lint command $r was not written: the probe says $o; install it, then run setup again" ;;
    error:*) echo "conveyor: the lint command $r was not written: the probe says $o; it needs a wrapper script that ends 0 with no finding, 1 with finding lines (<path>:<line>: <text>) or 127 with the first line \`lint: missing <tool>\`: give that script to setup as --lint" ;;
    empty) echo "conveyor: the lint command $r was not written: the probe says empty: no tracked file matches --lint-files $*" ;;
    *) echo "conveyor: the lint command $r could not be probed${o:+: $o}" >&2; return 1 ;;
  esac
}
# The ready lint entries' commands: each reads the files only (no --fix; ESLint lets no warning through, and says
# nothing of a file its config ignores), adds no rule flag, and is skipped (`lint: missing <tool>`, exit 127) while
# its tool is not installed. ESLint has no built-in format of one line a finding, so its JSON is put in that form.
READY_SHELLCHECK='command -v shellcheck >/dev/null || { echo '\''lint: missing shellcheck'\''; exit 127; }; shellcheck -S warning -f gcc {files}'
READY_RUFF='command -v ruff >/dev/null || { echo '\''lint: missing ruff'\''; exit 127; }; ruff check --no-fix --force-exclude --output-format=concise {files}'
READY_ESLINT='[ -x node_modules/.bin/eslint ] || { echo '\''lint: missing eslint'\''; exit 127; }; node_modules/.bin/eslint --max-warnings 0 --no-warn-ignored --format json {files} | jq -r --arg top "$(pwd -P)/" '\''.[] | (.filePath | ltrimstr($top)) as $f | .messages[] | "\($f):\(.line // 1):\(.column // 1): \(.ruleId // "eslint") \(.message | gsub("[\r\n]+"; " "))"'\'''
# lintready <dir>: the ready lint entries setup offers, a JSON list of {tool, policy, shared, entry}: one for each
# tool (shellcheck, ruff, ESLint) whose config <dir> tracks at its top. policy is the tool's own config files there,
# shared the pyproject.toml that holds ruff's config ([tool.ruff]); the entry's triggers are both. The configs are
# found by name only: no rule in them is read.
lintready() {
  local d=$1 fs py=''
  fs=$(git -C "$d" ls-files -z -- .shellcheckrc shellcheckrc ruff.toml .ruff.toml eslint.config.js eslint.config.mjs eslint.config.cjs \
    eslint.config.ts eslint.config.mts eslint.config.cts | jq -Rsc 'split("\u0000") | map(select(. != ""))') || return 1
  [ -z "$(git -C "$d" ls-files -- pyproject.toml)" ] || ! grep -qE '^\[tool\.ruff(\]|\.)' "$d/pyproject.toml" 2>/dev/null || py=pyproject.toml
  jq -nc --argjson fs "$fs" --arg py "$py" --arg sc "$READY_SHELLCHECK" --arg rf "$READY_RUFF" --arg es "$READY_ESLINT" '
    [{tool: "shellcheck", configs: [".shellcheckrc", "shellcheckrc"], shared: [], entry: {files: ["*.sh"], run: $sc}},
     {tool: "ruff", configs: ["ruff.toml", ".ruff.toml"], shared: [$py | select(. != "")],
      entry: {files: ["*.py"], run: $rf, complexity: ["C901", "PLR0915"]}},
     {tool: "ESLint", configs: ["eslint.config.js", "eslint.config.mjs", "eslint.config.cjs", "eslint.config.ts", "eslint.config.mts", "eslint.config.cts"],
      shared: [], entry: {files: ["*.js", "*.mjs", "*.cjs"], run: $es, complexity: ["complexity", "max-lines-per-function", "max-depth"]}}]
    | map(.policy = [.configs[] | select(IN($fs[]))] | select(.policy + .shared != []) | .entry.triggers = .policy + .shared | del(.configs))'
}
# setupready <commit> <offer> <shared answer>: the entries of <offer> (lintready()) added to the pack's lint.commands,
# and their tools' own config files to lint.policy, with the shared file only on a yes. No linter's config is
# changed, and nothing goes in pipelineFiles. Then one line names the complexity rules of the tools written, which
# their entry does not turn on.
setupready() {
  local p=$1 o=$2 s=$3 pol
  pol=$(jq -c --arg s "$s" '[.[] | .policy[], (if $s == "yes" then .shared[] else empty end)]' <<<"$o") || return 1
  jq --argjson o "$o" --argjson pol "$pol" '.lint.commands = (.lint.commands // []) + [$o[].entry]
    | if $pol == [] then . else .lint.policy = (.lint.policy // []) + $pol end' "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
    || { rm -f "$PACK.new"; echo "conveyor: the ready lint entries could not be written in the pack's lint.commands" >&2; return 1; }
  jq -r '.[] | "conveyor: wrote the ready lint entry for \(.tool) in the pack'"'"'s lint.commands, on \(.entry.files | join(", "))"' <<<"$o"
  [ "$pol" = '[]' ] || echo "conveyor: wrote the pack's lint.policy: $(jq -r 'join(", ")' <<<"$pol"); a card that changes one stops for your yes"
  jq -r 'map(select(.entry.complexity) | "\(.tool) \(.entry.complexity | join(", "))") | select(. != [])
    | "conveyor: the rules that measure complexity, which the ready entries do not turn on: \(join("; ")); turn them on in the linter'"'"'s own config"' <<<"$o"
}
# The size limit's exempt file, and its place in lint.policy.
SIZE_EXEMPT=.conveyor/size-exempt.txt
# exemptadd <path>: <path> as a line of the main checkout's SIZE_EXEMPT, unless it is there; a last line with no newline gets one first.
exemptadd() {
  local x=$MAIN/$SIZE_EXEMPT
  grep -qxF -- "$1" "$x" && return 0
  { [ ! -s "$x" ] || [ -z "$(tail -c1 "$x")" ] || echo >> "$x"; } && printf '%s\n' "$1" >> "$x"
}
# setupsize <commit> <limit> <pathspec>...: a size entry (the files, the limit and SIZE_EXEMPT) added to the pack's
# lint.commands, SIZE_EXEMPT added to lint.policy, and SIZE_EXEMPT in the main checkout naming each file the entry
# reads (a tracked file, or one not tracked and not ignored) that already has more lines than the limit, so the limit
# stops only what grows past it. A file under a folder that a pathspec excludes is not read, so it is not named. A line
# already in SIZE_EXEMPT stays. The pack and SIZE_EXEMPT are counted last, once the entry is written (sizeself(), which
# setupsize() runs). A pathspec git refuses writes nothing. A pack that already has a size entry is left as it is, and
# so is its exempt file: a later run never names a file the owner's edits made grow.
setupsize() {
  local p=$1 lim=$2 out rc f t new=''; shift 2
  local -a fs
  jq -e 'any(.lint.commands[]?; .size)' "$PACK" >/dev/null && { echo "conveyor: the pack's lint.commands already has a size entry"; return 0; }
  [ -e "$MAIN/$SIZE_EXEMPT" ] || new=1
  mkdir -p "$MAIN/.conveyor" && touch "$MAIN/$SIZE_EXEMPT" || { echo "conveyor: $SIZE_EXEMPT could not be written" >&2; return 1; }
  # Listed into a file: the status of a process substitution is never read, so a pathspec git refuses would list nothing and pass.
  t=$(mktemp) && git -C "$MAIN" ls-files -z --cached --others --exclude-standard -- "$@" > "$t" && mapfile -d '' -t fs < "$t" \
    || { rm -f "$t"; [ -z "$new" ] || rm -f "$MAIN/$SIZE_EXEMPT"; echo "conveyor: the files of $MAIN could not be listed for the size limit" >&2; return 1; }
  rm -f "$t"
  rc=0; out=$([ ${#fs[@]} = 0 ] || lintsize "$MAIN" "$lim" '' "${fs[@]}" 2>&1) || rc=$?
  [ "$rc" -le 1 ] || { echo "conveyor: the size limit was not written: ${out:-the lines could not be counted}" >&2; return 1; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    exemptadd "$f" || { echo "conveyor: $SIZE_EXEMPT could not be written" >&2; return 1; }
  done < <(sed 's/:[0-9]*: size [0-9]* lines, limit [0-9]*$//' <<<"$out")
  jq --argjson l "$lim" --arg e "$SIZE_EXEMPT" --argjson fs "$(jq -nc '$ARGS.positional' --args "$@")" '.lint.commands = (.lint.commands // []) + [{files: $fs, size: {file: $l, exempt: $e}}]
    | .lint.policy = (.lint.policy // [] | if index($e) then . else . + [$e] end)' "$PACK" > "$PACK.new" && pinreads "$p" "$PACK.new" && mv "$PACK.new" "$PACK" \
    || { rm -f "$PACK.new"; echo "conveyor: the size entry could not be written in the pack's lint.commands" >&2; return 1; }
  echo "conveyor: wrote a size entry in the pack's lint.commands: no file over $lim lines on $(printf '%s, ' "$@" | sed 's/, $//'); $SIZE_EXEMPT names the files that are over it now (the pack's commit takes it too), and is in the pack's lint.policy, so a card that changes it stops for your yes"
  sizeself
}
# sizeself: right after setupsize() wrote the entry, the pack and SIZE_EXEMPT named in SIZE_EXEMPT when a size entry of the
# pack that has SIZE_EXEMPT as its exempt file reads them and they are over its limit then (lintsizelist(): the size
# check's own count). The pack's own line is added first, since it makes SIZE_EXEMPT longer. A file at the limit is not
# named. Only setupsize() calls it, on the run that writes the entry, with nothing that can stop the run between: a
# later run would name growth the owner made, which the size check must report.
sizeself() {
  local f l
  jq -e --arg e "$SIZE_EXEMPT" 'any(.lint.commands[]?; .size.exempt == $e)' "$PACK" >/dev/null || return 0
  for f in "${PACK#"$MAIN"/}" "$SIZE_EXEMPT"; do
    l=$(lintsizelist "$MAIN") || return 1
    grep -qxF -- "$f" <<<"$l" || continue
    exemptadd "$f" || { echo "conveyor: $SIZE_EXEMPT could not be written" >&2; return 1; }
  done
}
# lintlangs: the languages with no ready lint entry of the paths on stdin, one a line, as one list "Go, Rust".
lintlangs() {
  sed -n 's/.*\.\([a-z]*\)$/\1/p' | LC_ALL=C sort -u | awk 'BEGIN { split("go Go rs Rust rb Ruby java Java kt Kotlin swift Swift c C h C cpp C++ cc C++ cs C# php PHP ts TypeScript tsx TypeScript", a, " ")
      for (i = 1; i in a; i += 2) n[a[i]] = a[i + 1] } ($1 in n) && !s[n[$1]]++ { print n[$1] }' | paste -sd, - | sed 's/,/, /g'
}
# lintother <dir>: the languages with no ready lint entry of <dir>'s tracked files that no lint command with a run in
# the pack covers (its files pathspecs). Those a size entry covers are named in one line: only their length is
# measured. The others are named in one line: nothing checks them.
lintother() {
  local d=$1 c k ps t l
  t=$(mktemp -d) || return 1
  : > "$t/run"; : > "$t/size"
  while IFS= read -r c; do
    mapfile -d '' -t ps < <(jq -j '.files[] + "\u0000"' <<<"$c")
    k=$(jq -r 'if .size then "size" else "run" end' <<<"$c")
    git -C "$d" -c core.quotepath=off ls-files -- "${ps[@]}" >> "$t/$k" || { rm -rf "$t"; return 1; }
  done < <(jq -c '.lint.commands // [] | .[]' "$PACK")
  git -C "$d" -c core.quotepath=off ls-files | LC_ALL=C sort -u > "$t/all" || { rm -rf "$t"; return 1; }
  LC_ALL=C sort -u -o "$t/run" "$t/run"; LC_ALL=C sort -u -o "$t/size" "$t/size"
  LC_ALL=C comm -23 "$t/all" "$t/run" > "$t/left"
  l=$(LC_ALL=C comm -12 "$t/left" "$t/size" | lintlangs)
  [ -z "$l" ] || echo "conveyor: Conveyor has no ready lint entry for $l: for those files, only file length is measured, unless you give setup your own lint command as --lint"
  l=$(LC_ALL=C comm -23 "$t/left" "$t/size" | lintlangs)
  [ -z "$l" ] || echo "conveyor: Conveyor has no ready lint entry for $l, and no lint command in the pack checks those files, not even their length: give setup your own lint command as --lint, or add a size entry to the pack's lint.commands"
  rm -rf "$t"
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
# wrap each test file's run with tools/testtime.sh (conveyor/README.md, Test file times), each run; it
# never changes the project's script.
timinghint() {
  local w ws
  ws=$(timingscripts) || return 1
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    echo "conveyor: the test command runs $w, which prints no \`TESTRUN sec\` lines, so cards record no test times."
    echo "  If it runs the test files one by one, copy $HERE/tools/testtime.sh into the project and wrap each file's run"
    echo "  with it, writing its line to the script's log in \$CONVEYOR_TEST_LOG before the file's \`-- ok|FAIL <file>\` line:"
    echo "    ./testtime.sh \"\$f\" -- <the file's command> > \"\$out\" 2>&1; rc=\$?; cat \"\$out\"; grep '^TESTRUN sec' \"\$out\" >> \"\$CONVEYOR_TEST_LOG/<its log>\""
    echo "  conveyor/README.md, Test file times, says more."
  done <<<"$ws"
}
# The scripts timinghint() speaks of, one a line, as the test command writes each.
timingscripts() {
  local cmd w p ws=()
  packget test.command cmd || return 1
  read -ra ws <<<"$cmd"
  for w in "${ws[@]}"; do
    w=${w//[\"\']/}; w=${w%%[;&|)]*}; [[ $w == *.sh ]] || continue
    p=$w; [[ $p == /* ]] || p=$MAIN/$p
    [ -f "$p" ] && ! grep -qE 'TESTRUN sec|testtime\.sh' "$p" || continue
    echo "$w"
  done
}
# Record test times: what the Tests page's action does when the last card test runs recorded no test times, as JSON,
# for the first of these that applies, or null with none:
#   {kind: "report", report}  the pack's test.report is set to the report setup knows for the test command
#                             (reportguess(): a runner whose report Conveyor reads; none when the pack names a format)
#   {kind: "wrap", file, was, command[, fileCommand]}  the test command runs one test file: it is wrapped with
#                             tools/testtime.sh, as cpuplan() gives it
#   {kind: "card", file, title, body}  the test command runs a script of the project that prints no test times: a held
#                             card for the owner, whose body is timinghint()'s wrap steps (the script is the owner's)
timesplan() {
  local cmd fmt r p f
  packget test.command cmd test.report.format fmt || return 1
  if [ -z "$fmt" ] && r=$(reportguess "$cmd") && jq -e '.format' <<<"$r" >/dev/null 2>&1; then
    jq -cn --argjson r "$r" '{kind: "report", report: $r}'; return 0
  fi
  # cpuplan() writes {file: ...} (a plan) or {why: ...} (none): the plan's text starts with its file.
  if p=$(cpuplan 2>/dev/null) && [[ $p == '{"file":'* ]]; then jq -c '{kind: "wrap"} + .' <<<"$p"; return 0; fi
  f=$(timingscripts) || return 1; f=${f%%$'\n'*}
  if [ -n "$f" ]; then
    jq -cn --arg f "$f" --arg b "$(timinghint)" '{kind: "card", file: $f, title: "Record test times: wrap each test file'"'"'s run in \($f)", body: $b}'; return 0
  fi
  echo null
}
# The health record <json> with the plan of Record test times (timesplan()) as timesPlan while the last card test runs
# recorded no test times (its untimed is above 0), else null: the snapshot's Health part, for the Tests page's action.
timesadd() { # <health json>
  local p=null
  [ "$(jq -r '.untimed // 0' <<<"$1")" = 0 ] || p=$(timesplan 2>/dev/null) || p=null
  jq -c --argjson p "$p" '.timesPlan = $p' <<<"$1"
}
# conveyor.sh test-settings record-times: the plan of timesplan() run, as an admin's pack change the Board's Tests page
# makes: a report or a wrapped command saved in the pack (packset()), or the held card filed (testcard(): no GitHub
# issue; held until `control release`). With no plan, or a card of that title already waiting, it says so and changes
# nothing.
recordtimes() {
  local p k t
  [ $# = 0 ] || { echo "usage: conveyor.sh test-settings record-times" >&2; return 2; }
  p=$(timesplan) || { echo "conveyor: test-settings record-times: the pack cannot be read; nothing changed" >&2; return 1; }
  k=$(jq -r '.kind // empty' <<<"$p")
  case $k in
    report) packset --argjson r "$(jq -c .report <<<"$p")" '.test.report = $r' ;;
    wrap) testsettings cpu-time "$(jq -r .file <<<"$p")" ;;
    card) t=$(jq -r .title <<<"$p")
      if jq -e --arg t "$t" 'any(.cards[]?; .title == $t and .card == null)' "$TACARDS" >/dev/null 2>&1; then
        echo "conveyor: test-settings record-times: the held card \"$t\" is waiting already; nothing changed" >&2; return 1
      fi
      mkdir -p "$TESTACTS" || { echo "conveyor: test-settings record-times: the test actions' folder could not be made; no card filed" >&2; return 1; }
      testcard "$(jq -r .file <<<"$p")" "$t" "$(jq -r .body <<<"$p")" held "as it asks the owner to change a script of the project" ;;
    *) echo "conveyor: test-settings record-times: no plan applies to this test command; nothing changed" >&2; return 1 ;;
  esac
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
# The globs, in the form of tests.patterns, of the test files the test command runs, from what the project says
# (docs/setup.md): each word of the command with a * or ? in it (quotes taken off; of an --option=<value>, the value),
# as a path from the checkout's root, and so of the package.json script the command runs (npm, yarn, pnpm or bun:
# `npm test`, `npm run <name>`); Jest's testMatch (package.json, jest.config.*); Vitest's include (vitest.config.*,
# vite.config.*; its coverage block left out); pytest's python_files under each of its testpaths (pytest.ini,
# pyproject.toml's [tool.pytest.ini_options]; with no python_files, pytest's own: test_*.py and *_test.py); and
# *_test.go when the checkout tracks a Go test file. A config is read as text from main's checkout, in its root.
# {a,b} makes one glob of each; a glob of a form tests.patterns cannot say ([...], ?(...), !...) is left out.
# One `<glob>\t<where it was read>` a line, each glob once.
runnerglobs() { # <test command>
  local s=$1 n=test.command w ws=() f k
  if [[ $1 =~ ^(npm|yarn|pnpm|bun)[[:space:]]+(run[[:space:]]+)?([A-Za-z0-9:_-]+)[[:space:]]*$ ]]; then
    n="package.json scripts.${BASH_REMATCH[3]}"
    s=$(jq -r --arg n "${BASH_REMATCH[3]}" '.scripts[$n] | strings' "$MAIN/package.json" 2>/dev/null) || s=''
  fi
  {
    read -ra ws <<<"$s"
    for w in "${ws[@]}"; do
      w=${w//[\"\']/}; w=${w%%[;&|)]*}; [[ $w != -*=* ]] || w=${w#*=}; w=${w#./}
      [[ $w == *[*?]* && $w != -* && $w != *'$'* && $w != /* ]] || continue
      printf '/%s\t%s\n' "$w" "$n"
    done
    for f in package.json jest.config.{js,ts,mjs,cjs,json} vitest.config.{js,ts,mjs,mts,cjs,cts} vite.config.{js,ts,mjs,mts,cjs,cts}; do
      [ -f "$MAIN/$f" ] || continue
      if [[ $f == vite* ]]; then k='Vitest include'; else k='Jest testMatch'; fi
      # The list of key <k> as a JavaScript or JSON text writes it (testMatch: [...], "testMatch": [...]), with each
      # `coverage: {...}` block, whose include names product files, taken out first; a glob from the root unless it
      # starts with **/.
      jq -rRs --arg k "${k#* }" --arg from "$k in $f" '
        def unblock: (first(match("\\bcoverage[\"'"'"']?\\s*:\\s*\\{")) // null) as $m
          | if $m == null then . else (.[$m.offset + $m.length:] | explode) as $c
            | (first(foreach range(0; $c | length) as $i (1; if $c[$i] == 123 then . + 1 elif $c[$i] == 125 then . - 1 else . end;
                select(. == 0) | $i)) // ($c | length)) as $e
            | .[:$m.offset] + .[$m.offset + $m.length + $e + 1:] | unblock end;
        unblock | scan("\\b" + $k + "[\"'"'"']?\\s*:\\s*\\[((?:[^\\]\"'"'"'`]|\"[^\"]*\"|'"'"'[^'"'"']*'"'"'|`[^`]*`)*)\\]")[0]
        | scan("[\"'"'"'`]([^\"'"'"'`]+)[\"'"'"'`]")[0] | ltrimstr("<rootDir>/") | ltrimstr("./")
        | (if startswith("**/") then . else "/" + . end) + "\t" + $from' "$MAIN/$f" 2>/dev/null
    done
    for f in pytest.ini pyproject.toml; do
      [ -f "$MAIN/$f" ] || continue
      [ $f = pytest.ini ] && k=pytest || k=tool.pytest.ini_options
      # The keys of section [<sec>], an INI's (a value goes on in the indented lines below it) or a TOML's (a list
      # goes on to its closing ]).
      jq -rRs --arg sec "$k" --arg from "pytest's testpaths and python_files in $f" '
        def words: if test("^\\s*\\[") then [scan("[\"'"'"']([^\"'"'"']+)[\"'"'"']")[0]] else sub("\\s[#;].*$"; "") | [splits("\\s+") | select(. != "")] end;
        (split("\n") | reduce .[] as $l ({s: null, k: null, v: {}};
          if .k != null and (.v[.k] | test("^\\s*\\[") and (test("\\]") | not)) then .v[.k] += " " + $l
          elif $l | test("^\\s*\\[[^\\]]*\\]\\s*$") then .s = ($l | capture("\\[(?<n>[^\\]]*)\\]").n) | .k = null
          elif .s != $sec then .
          elif $l | test("^[A-Za-z_]+\\s*=") then ($l | capture("^(?<k>[A-Za-z_]+)\\s*=\\s*(?<r>.*)$")) as $c | .k = $c.k | .v[$c.k] = $c.r
          elif .k != null and ($l | test("^\\s+\\S")) then .v[.k] += " " + $l
          else .k = null end) | .v) as $v
        | ($v.python_files // "test_*.py *_test.py" | words) as $f
        | if $v.testpaths then ($v.testpaths | words | .[] | ltrimstr("./") | rtrimstr("/")) as $d
            | if $d == "." or $d == "" then $f[] elif $d | endswith(".py") then "/" + $d else "/" + $d + "/**/" + $f[] end
          else $v.python_files // empty | words | .[] end
        | . + "\t" + $from' "$MAIN/$f" 2>/dev/null
    done
    [ -z "$(git -C "$MAIN" ls-files -- '*_test.go' 2>/dev/null)" ] || printf '*_test.go\tGo test files\n'
  } | jq -rRn 'def braces: if test("\\{[^{}]*\\}") then capture("^(?<a>[^{]*)\\{(?<b>[^{}]*)\\}(?<c>.*)$") as $m
      | $m.b | split(",")[] | $m.a + . + $m.c | braces else . end;
    reduce (inputs | split("\t") | select(length == 2) | .[1] as $f | .[0] | braces
      | select(test("[\\[\\]()!{}$]|^/?$") | not) | [., $f]) as $x ([]; if any(.[]; .[0] == $x[0]) then . else . + [$x] end)
    | .[] | join("\t")'
}
# The tracked files the test command runs (runnerglobs()), one a line.
cmdtests() { # <test command>
  local g=()
  mapfile -t g < <(runnerglobs "$1" | cut -f1)
  [ ${#g[@]} != 0 ] || return 0
  git -C "$MAIN" -c core.quotePath=false ls-files 2>/dev/null | grep -E -- "$(jq -rn "$GLOBRX"'$ARGS.positional | globsrx' --args "${g[@]}")" || :
}
# The tracked files the test-file globs <patterns> (a JSON list, as tests.patterns) match, counted.
testcount() { # <patterns>
  local rx
  rx=$(jq -r "$GLOBRX"'globsrx' <<<"$1") || return 1
  git -C "$MAIN" -c core.quotePath=false ls-files | { grep -cE -- "$rx" || :; }
}
# Setup's guess at the test files <patterns> (a JSON list) miss: of the tracked files that are not documents or data,
# those whose own name reads as a test's (it starts with test or spec and a - or _, or ends so, or with Test, Tests or
# Spec, before its extension), each made a glob: its test word kept, the rest a *, in any folder. Prints the globs
# that match a file <patterns> misses, one a line.
testguess() { # <patterns>
  local rx
  rx=$(jq -r "$GLOBRX"'globsrx' <<<"$1") || return 1
  git -C "$MAIN" -c core.quotePath=false ls-files | jq -rRn --arg rx "$rx" '
    [inputs | select(test($rx) | not) | select(test("\\.(md|txt|json|ya?ml|snap|lock|csv|html|css|svg|png|jpe?g|gif)$"; "i") | not)
      | split("/")[-1] as $b | ($b | capture("(?<x>\\.[^.]+)$").x // "") as $e
      | if $b | test("^(?i:test|spec)s?[-_]") then ($b | capture("^(?<w>(?i:test|spec)s?[-_])").w) + "*" + $e
        elif $b | test("[-_.](?i:test|spec)s?\\.[^.]+$") then "*" + ($b | capture("(?<w>[-_.](?i:test|spec)s?)\\.[^.]+$").w) + $e
        elif $b | test("(Test|Tests|Spec)\\.[^.]+$") then "*" + ($b | capture("(?<w>Test|Tests|Spec)\\.[^.]+$").w) + $e
        else empty end] | unique[]'
}
# What setup offers for a pack with no tests.patterns of its own (setup()): the globs the test command runs
# (runnerglobs()) that match a tracked file or, with none, the default; then testguess()'s globs of the files those
# miss. A JSON list of {p: <glob>, from: <where it was read>, n: <the tracked files it matches>}, from "default" for
# the default's and "names" for testguess()'s; nothing when no runner glob matches a file and testguess() finds none.
testoffer() { # <test command>
  local d r o g=() cnt
  # cnt: each glob of the list given its count of the tracked files (the program's input lines) it matches.
  cnt="$GLOBRX"'[inputs] as $fs | def cnt: map(.n = ((.p | globrx) as $x | [$fs[] | select(test($x))] | length));'
  d=$(jq -c '.properties.tests.properties.patterns.default' "$SCHEMA") \
    && r=$(runnerglobs "$1" | jq -cRn '[inputs | split("\t") | {p: .[0], from: .[1]}]') \
    && o=$(git -C "$MAIN" -c core.quotePath=false ls-files | jq -cRn --argjson r "$r" --argjson d "$d" "$cnt"'$r | cnt | map(select(.n > 0))
      | if . == [] then $d | map({p: ., from: "default"}) | cnt else . end') \
    && mapfile -t g < <(testguess "$(jq -c 'map(.p)' <<<"$o")") || return 1
  [ ${#g[@]} != 0 ] || jq -e 'any(.[]; .from != "default")' <<<"$o" >/dev/null || return 0
  git -C "$MAIN" -c core.quotePath=false ls-files | jq -cRn --argjson o "$o" "$cnt"'$o + ($ARGS.positional | map({p: ., from: "names"}) | cnt)' --args "${g[@]}"
}
# How a test command takes test files, and the runner it runs, as one line `<mode> <runner>` (testrunner(), in main;
# setup() offers the command as test.fileCommand for args): nothing for a runner it does not know, or for a command
# that already names the test files its runner runs, which paths added at its end would not narrow.
listguess() { # <test command>
  local g
  g=$(testrunner "$1" "$MAIN") || return 0
  [[ $g == named* ]] || printf '%s\n' "$g"
}
# What doctor says of the pack's tests.patterns: a `missing:` line when they match no tracked file, or miss a file the
# test command runs, by its words or its runner's config (cmdtests()); else an `ok:` line with the count. Fails with a `missing:` line.
testcheck() {
  local p c n m=()
  packget tests.patterns p test.command c || return 1
  n=$(testcount "$p") || return 1
  mapfile -t m < <(cmdtests "$c" | testpaths -v)
  if [ "$n" = 0 ]; then
    echo "missing: test files the pack's tests.patterns match (they match no tracked file: $(jq -r 'join(", ")' <<<"$p")); fix: set tests.patterns in .conveyor/project.json to globs of the project's test files (docs/configuration.md, How test files are found)"; return 1
  elif [ ${#m[@]} != 0 ]; then
    echo "missing: tests.patterns that match the ${#m[@]} file$([ ${#m[@]} = 1 ] || echo s) the test command runs, such as ${m[0]}; fix: add a glob of them to tests.patterns in .conveyor/project.json (docs/configuration.md, How test files are found)"; return 1
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
# A key file's key, in KEY_V, for the route of <variable> (<option> names the answer): fails, saying why, when the file is
# no good (keyfile()), or when the env of the settings file holds another key under <variable>, as a session reads
# that before the key file (routekey()) and would use it in the file's place.
keyfileask() { # <variable> <key file> <option>
  local v f
  keyfile "$2" || { echo "conveyor: $3: $KEY_FROM" >&2; return 1; }
  v=$KEY_V f=$KEY_FROM
  routekey "{\"keyEnv\": \"$1\"}" service
  [ -z "$KEY_V" ] || [ "$KEY_V" = "$v" ] || { echo "conveyor: $3: $1 in the env of $CLAUDE_SETTINGS holds another key than the key file's, and sessions read the settings first: remove it there, or answer settings" >&2; return 1; }
  KEY_V=$v KEY_FROM=$f
}
# setup()'s route questions, in its own variables (its locals, read and set here). Each role's CLI now, in rcli: the
# pack's seat, or with no pack yet the seat the built-in models (MODELS0) give. Each of those CLIs, Claude or Codex, with no route set
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
    else s=$(jq -c --arg r "$r" --argjson c null "$SEATNOW"'[try seatnow($r; $c)] | first // empty' <<<"$MODELS0" 2>/dev/null) || s=''; fi
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
      keyfileask "$k" "$a" "--$c-key" || return 1
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
      keyfileask "$k" "$a" "--$c-proxy-key" || return 1
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
# doctor's line on one Conveyor per machine: the machine's loop (`machine`), and no loop of a project beside it that it
# did not start (a per-project service left from before, or a `serve` started by hand). Each loop alive names its pid.
# Returns 1 when a second loop runs. Needs jq.
doctorloops() {
  local loops=() mains=() v=() mp='' e t r m s q a is='^([^ ]*/)?bash (.*/)?conveyor\.sh (serve|run( .*)?)$'; local -A up=() loop=()
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
  if [ ${#loops[@]} -gt 1 ]; then
    echo "missing: one Conveyor loop on this machine: ${loops[1]} runs beside ${loops[0]}; fix: stop every loop but the machine's (a per-project service: systemctl --user disable --now conveyor-<name>.service, or launchctl bootout gui/\$(id -u)/conveyor.<name>), then run install-service once"
    return 1
  elif [ ${#loops[@]} = 1 ]; then echo "ok: one Conveyor loop on this machine: ${loops[0]}"; fi
}
# conveyor.sh doctor: each thing Conveyor needs on this machine for the project it is called in, one line each, "ok: ..."
# or "missing: <what>; fix: <how>", and "warning: ..." for a running loop on old code or a Board not running. Exit 1 when anything is missing,
# but for the project's instruction files (agentfiles(), which sessions run without). bash older than 5.1 stops at require_bash, above,
# which says how to get a newer one. The project's checks need jq and git; without either they are named as not checked.
# Setup's suggestion of a test.fileCommand, while the pack sets none and the project's test files run alone as plain
# scripts (fileguess()): a card runs each of its test files alone through it, and stops at its test step without it (a bug card with a fix at Build, bugproof.sh bugproof(): any change but test files alone, or test files with comments in
# JavaScript or TypeScript files, commentsonly(); a comment change with no test file, or a shell comment, is a fix).
filehint() {
  local fc g
  packget test.fileCommand fc 2>/dev/null && [ -z "$fc" ] && g=$(fileguess "$MAIN") && [ -n "$g" ] || return 0
  echo "conveyor: the test files run alone as plain scripts (\`$g <file>\`); set test.fileCommand to \"$g\" in .conveyor/project.json, so a card runs each of its test files alone"
}
# The offer of .conveyor/test-machine.sh (docs/setup.md), the script that installs what the project's suite needs on a
# bare Linux box, run on the machine a release's suite runs on when that is not this one (lib/suitehost.sh). While the
# main checkout has none, setup says so on each run; --test-machine yes writes one from the pack's test commands
# (test.command, test.full, test.fileCommand): a `# needs: <tool>` line for the first word of each, and no install
# commands, which only the project knows, so it says the project must finish the script and commit it. no writes
# nothing and says nothing. A script already there is never changed.
machineoffer() { # <yes|no|empty>
  local f=$MAIN/.conveyor/test-machine.sh t=() n
  [ ! -e "$f" ] && [ "${1:-}" != no ] && [ -e "$PACK" ] || return 0
  if [ "${1:-}" != yes ]; then
    echo "conveyor: the project has no .conveyor/test-machine.sh, which installs what its suite needs on a bare Linux box, for a release suite that runs on an ssh box or a Namespace devbox; pass --test-machine yes to write one from the pack's test commands, which the project must then finish"
    return 0
  fi
  # Each command's first word; a shell, jq and git are on any box that runs a suite (suite-machine check asks for jq and git).
  mapfile -t t < <(jq -r '.test | [.command, .full, .fileCommand] | map(strings | split(" ")[0] | select(test("^[A-Za-z0-9._+-]+$") and (IN("bash", "sh", "jq", "git") | not))) | unique[]' "$PACK")
  mkdir -p "${f%/*}" && {
    printf '#!/usr/bin/env bash\n# What this project'"'"'s test suite needs on a bare Linux box: the machine a release'"'"'s suite runs on when it is not this one.\n'
    printf '# Conveyor runs this script there as the box'"'"'s user, which can use sudo, and again only after the script changes.\n'
    printf '# `conveyor.sh suite-machine check` reads each `# needs: <tool> [<version>]` line and names the tools the box lacks.\n'
    printf '# Setup wrote the lines below from the pack'"'"'s test commands: add each tool the suite needs and the commands that install it.\n'
    [ ${#t[@]} = 0 ] || printf '# needs: %s\n' "${t[@]}"
    printf 'set -euo pipefail\n'
  } > "$f.new" 2>/dev/null && mv "$f.new" "$f" || { rm -f "$f.new"; echo "conveyor: .conveyor/test-machine.sh could not be written" >&2; return 1; }
  n=${#t[@]}
  echo "conveyor: wrote .conveyor/test-machine.sh with $n # needs: line(s) from the pack's test commands; it installs nothing yet: the project must finish it with the commands that install what the suite needs, and commit it"
}
# Doctor's warning of a pack whose cards cannot run their test files (listcmd(), lib/testrun.sh): a card runs each
# alone through test.fileCommand, else, when the pack does not set it, through Conveyor's own runner (lib/filerun.sh),
# so with neither for one of the project's test files (testpaths()), a card whose change is linked to it stops at its
# test step (a bug card with a fix at Build, bugproof.sh bugproof(): a comment change with no test file in the change, or in a file
# that is not JavaScript or TypeScript, is a fix, commentsonly()). It names the first such file (NORUNNER). Of the test
# files of one kind (their ending) in one folder, which have one runner, only the first is asked.
narrowwarn() {
  local fc f k r why
  local -A seen=()
  packget test.fileCommand fc 2>/dev/null && [ -z "$fc" ] || return 0
  while IFS= read -r f; do
    k=.; [[ $f != */* ]] || k=${f%/*}
    case $f in *_test.go|*_spec.rb) k+=/_${f##*_} ;; *.*) k+=/.${f##*.} ;; *) k=$f ;; esac
    [ -z "${seen[$k]:-}" ] || continue; seen[$k]=1
    r=$(cd "$MAIN" && bash "$HERE/lib/filerun.sh" --which "$f" 2>&1) && continue
    why=${NORUNNER//'<file>'/"$f"}; why=${why//'<reason>'/"$r"}; echo "warning: ${NARROW//'<why>'/"$why"}"
    return 0
  done < <(git -C "$MAIN" -c core.quotePath=false ls-files 2>/dev/null | testpaths)
}
# Doctor's warnings where the pack's models.allowed and a CLI's report (hostclis()) differ, one model a line: a model
# the pack lists for Codex (codex, codex-builder) or OpenCode (opencode, without its opencode: mark) that the CLI does
# not report, and one the CLI reports that the pack leaves out. A Codex family name (sol) is a model Codex has when
# it resolves, as a seat's does (codexmodel()), with that seat's route. Nothing when the pack sets no models.allowed
# (the project then takes the models the CLIs report, modelsallowed()), for Codex when the pack's codex list has no
# model (an empty codex list takes none of Codex's), for OpenCode when the pack lists none, or for a CLI whose report
# has no list (null: Codex installed with no models cache that reads, say).
modelswarn() {
  local p h f r s='' fam='[]'
  packget models.allowed p 2>/dev/null && [ -n "$p" ] && h=$(hostclis due 2>/dev/null) || return 0
  # Codex's families are resolved only when its report has a list to warn against: with no list the answer is never
  # used. Each answer, a failed one too, is kept in CODEXMODEL_V, so doctor's routes() does not resolve the role's family
  # again (codexmodel() asks the proxy when Codex has one, and reads models_cache.json when there is none, when it does
  # not answer or when its list has none of the family).
  jq -e '.codex | arrays' <<<"$h" >/dev/null 2>&1 || s=none
  [ "$s" = none ] || for s in codex:reviewer codex-builder:builder; do
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      # shellcheck disable=SC2034 # CODEXMODEL_V is read by routes() in lib/control.sh
      if r=$(PROXY_ROLE=${s#*:} codexmodel "$f" 2>/dev/null); then CODEXMODEL_V[${s#*:}:$f]=0$'\037'$r
        [ -z "$r" ] || fam=$(jq -c --arg f "$f" '. + [$f]' <<<"$fam")
      else CODEXMODEL_V[${s#*:}:$f]=1$'\037'$r; fi
    done < <(jq -r --arg k "${s%%:*}" '.[$k] // [] | arrays | .[] | strings | select(test("^[a-z]{2,}$"))' <<<"$p" 2>/dev/null)
  done
  jq -r --argjson h "$h" --argjson fam "$fam" '. as $p | [{c: "codex", n: "Codex", k: "codex", a: "", on: ($p.codex // [] | any(strings)), l: (($p.codex // []) + ($p["codex-builder"] // [])), x: $fam},
      {c: "opencode", n: "OpenCode", k: "opencode", a: "opencode:", l: [($p.opencode // [])[] | strings | select(startswith("opencode:")) | ltrimstr("opencode:")]}][]
    | (.l | map(strings)) as $l | select(if has("on") then .on else $l | length > 0 end) | ($h[.c] | arrays) as $r
    | (($l - $r - (.x // []) | unique[]) as $m | "warning: the pack'"'"'s models.allowed lists \($m) for \(.n), which \(.n) does not report on this host, so a seat set to it may not start; fix: correct the name, or take it out of models.allowed"),
      (($r - $l | unique[]) as $m | "warning: \(.n) reports \($m), which the pack'"'"'s models.allowed leaves out; a seat can run it, after the pack'"'"'s models in the list; fix: add \(.a)\($m) to models.allowed.\(.k) to put it in another place in the list, or leave it out")' <<<"$p" 2>/dev/null
}

# doctor's check of the judge and the reviewer in force, each on Claude: one question with no tools, as askmodel()
# asks it for Pick for me and the split check, on the review's route and account (as cardpick() calls the judge).
# On some machines such a call ends at once with an empty answer and exit 0; one that sends back an empty answer or an
# error is missing, naming the seat. Returns 1 when one is.
askcheck() {
  local t s a m c d e r rc=0 x
  c=$(ctl 2>/dev/null) || c=null
  mapfile -t x < <(SEATCARD='' cardaccts "$c" 2>/dev/null)
  c=$(jq -c --arg a "${x[1]-${x[0]-}}" 'objects | .account = (if $a == "" then null else $a end)' <<<"$c" 2>/dev/null) || c=''
  for t in judge reviewer; do
    s=$(SEATCARD='' seat "$t" "$c" 2>/dev/null) && jqget "$s" agent a model m 2>/dev/null && [ "$a" = claude ] || continue
    d=$(mktemp -d) || { echo "not checked: the $t ($m): no folder for its call"; continue; }
    echo "conveyor: asking the $t ($m) one question with no tools (up to 120 s)..." >&2
    e=$(PROXY_ROLE=reviewer ASKSEAT=$t askmodel "$d" 120 low "$c" 'Reply with the one word OK.'); r=$?
    rm -rf "$d"
    if [ "$r" = 0 ] && [ -z "$e" ]; then echo "ok: the $t ($m, claude) answers a call with no tools"
    else echo "missing: an answer from the $t ($m, claude) to a call with no tools: ${e:-exit $r; 124 is the 120 s timeout}; fix: check claude -p on this machine's account and route, or move the $t to another CLI (conveyor.sh control $t codex <model>, or Rules on the Board)"; rc=1; fi
  done
  return $rc
}
doctor() {
  local bad=0 p e t c h f s
  ok() { echo "ok: $1"; }; no() { echo "missing: $1; fix: $2"; bad=1; }
  # Each requirement at its minimum version, as the engine runs it: the version found, and where (lib/requires.sh).
  req_report || bad=1
  req_guards || bad=1
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
    [ ! -f "$c" ] || ! jq -e --arg n "$t" 'any(.records | arrays | .[] | objects; .repo == $n)' "$HOST" >/dev/null \
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
    # The settings of the machine room, which is removed (issue 346): read with them ignored, and said once, in one line.
    t=$(jq -r '[keys[] | select(IN("pressure", "maxLoad", "minFreeMemMB"))] | join(", ")' "$HOST" 2>/dev/null)
    [ -z "$t" ] || echo "warning: the host file $HOST sets $t, which no longer do anything: no card or test waits for the machine's load, pressure or free memory; remove them"
    # The host file's steer, which is removed (issue 347): read as if not there, and said once, in one line.
    [ "$(jq 'has("steer")' "$HOST" 2>/dev/null)" != true ] \
      || echo "warning: the host file $HOST sets steer, which no longer does anything: card sessions, reviews and test runs run at normal priority; remove it"
  fi
  ! command -v jq >/dev/null || doctorloops || bad=1
  # The cores kept for the user (the host file's reserveCores, lib/slots.sh slot_reserved), and the test slots left.
  local sl='the test-slot pool cannot be read'
  ! slot_pool >/dev/null 2>&1 || sl="the test-slot pool has $SLOT_N slots"
  s=$(slot_reserve_why)
  if [ -n "$s" ]; then ok "cores kept for you (the host file's reserveCores): not available on this machine, as $s"
  elif s=$(slot_keep); then ok "cores kept for you (the host file's reserveCores): cores $(slot_reserved | paste -sd, -); card sessions and test runs run on cores $s, and $sl"
  else ok "no cores kept for you (the host file's reserveCores is 0): $sl"; fi
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
  # ast-grep, which the plugin's bin/ast-grep runs, is optional: sessions without it search code by text only.
  if [ -x "$BOARD_VENV/bin/ast-grep" ]; then ok "ast-grep, in the Board's virtualenv $BOARD_VENV"
  else echo "warning: ast-grep is not in the Board's virtualenv $BOARD_VENV, so sessions search code by text only; fix: run /conveyor-belt:setup, which installs it there"; fi
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
  # A main checkout set to bare: each git command that needs a work tree fails in it (rev-parse --git-dir does not), so no card lands (land(), lib/claim.sh).
  [ "$(git -C "$MAIN" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
    || no "a working main checkout: $MAIN is not one (core.bare is true), so no card can land" "run git -C $MAIN config core.bare false"
  if [ ! -e "$PACK" ]; then no "the pack $PACK" "run /conveyor-belt:setup"; return 1; fi
  # A field this engine does not know, in a pack for a newer commit (packnewer(), lib/prompts.sh): the pack is right,
  # and the fix is to run the commit it names, not to correct the pack.
  if ! e=$("$HERE/lib/pack.sh" check "$PACK" 2>&1); then
    t=$(packnewer "$e"); t=${t#"conveyor pack: $PACK: "}
    if [ -n "$t" ]; then no "a pack this Conveyor reads: ${t%%; run conveyor.sh install-service *}" "run ${t#*; run }"
    else no "a valid pack" "correct what the check names: ${e//$'\n'/; }"; fi
    return 1
  fi
  ok "the pack $PACK"
  areadoctor "$PACK" # a warning when it has no path-to-area map (lib/areas.sh)
  # The pack's test-file globs: they must find the project's tests (testcheck()).
  testcheck || bad=1
  # Each of the pack's lint commands, tried once (lintdoctor(), lib/lint.sh): nothing when the pack has no lint field.
  lintdoctor || bad=1
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
  modelswarn
  # The builder and the reviewer in force (the control record's, its defaults' or the seed's): one whose CLI is not
  # installed here does not start (seatready), and the loop starts no card, so doctor names that seat.
  for t in builder reviewer; do
    c=$(seat "$t" 2>/dev/null) || continue
    e=$(seatready "$t" "$c" 2>/dev/null) || no "a $t that can start (${e%%: the $t does not start;*})" \
      "install its CLI, or set the $t to a CLI and model this host has (conveyor.sh control, or Rules on the Board)"
  done
  routes || bad=1
  askcheck || bad=1
  # A pack that follows the plugin's main or its releases: the commit it is on here, how far behind main that is (or
  # the release it is and whether a newer one is published), and a newer commit that failed its check (take()); then
  # that commit's install is checked as a pin's is.
  p=''; f=''; enginepin p f
  if [ -n "$f" ]; then
    if [ -n "$p" ] && [ "$f" = releases ]; then ok "the project follows the plugin's releases: it runs Conveyor commit $p, $(released "$p")"
    elif [ -n "$p" ]; then ok "the project follows the plugin's $f: it runs Conveyor commit $p, $(behind "$p" "$f")"; fi
    e=$(jq -r '.refused | objects | "\(.commit): \(.reason)"' "$ENGINE" 2>/dev/null) || e=''
    [ -z "$e" ] || echo "warning: Conveyor commit ${e%%: *} of the plugin's $f was not taken: ${e#*: }"
    # A newer commit that was not taken, and why (stalenote(), lib/install.sh).
    e=$(stalenote live); [ -z "$e" ] || echo "warning: $e"
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
  # The machine's Conveyor on another commit, whose own check refuses this pack (a field its schema does not name):
  # it starts the project's loop on that commit, which ends at once, so nothing of the project runs.
  if IFS=$'\t' read -r e t c < <(machinerefuses) && [ -n "$e" ]; then
    no "the machine's Conveyor reading this project's pack: it runs Conveyor commit $e, whose check refuses the pack ($t), so it does not serve the project" \
      "run conveyor.sh install-service in $MAIN, which starts it again on the project's commit${c:+ $c}"
  fi
  # A running loop on older code than its checkout's HEAD or, from an install, than the pin: a warning, as it restarts
  # on the new code by itself once its push is done.
  # The checkout is read on its own: @tsv escapes a backslash in a path, and read -r keeps that escape.
  if IFS=$'\t' read -r e t c < <(jq -r '[.pid, .started, .commit // ""] | @tsv' "$SAYS" 2>/dev/null) && [ -n "$c" ] && p_alive "$e" "$t"; then
    h=$(jq -r '.checkout // ""' "$SAYS" 2>/dev/null)
    if [ -n "$h" ]; then e=$(git -C "$h" rev-parse -q --verify HEAD) && [ "$e" != "$c" ] && echo "warning: the running loop started on Conveyor commit $c, and its checkout is at $e: it runs old code until it restarts"
    elif [ -n "$p" ] && [ "$p" != "$c" ]; then echo "warning: the running loop started on Conveyor commit $c, and the pack pins $p: it runs old code until it restarts"; fi
  fi
  # The project's last card test runs recorded no test times (UNTIMED, lib/views.sh): its test command prints no
  # `TESTRUN sec` lines and Conveyor read no report of its runner. A warning: the cards still run. When setup found a
  # runner whose report Conveyor cannot read now (test.report with no format), it names the runner and its option that
  # would give them.
  e=$(stdb ask lines cards 2>/dev/null | jq -s "$UNTIMED"' untimed' 2>/dev/null) || e=0
  t=$(jq -r '.test.report | objects | select(.format == null and .option) | "; the test command runs \(.runner), whose report option \(.option) would give them"' "$PACK" 2>/dev/null) || t=''
  [[ ! $e =~ ^[1-9][0-9]*$ ]] || echo "warning: the last $e card test run$([ "$e" = 1 ] || echo s) recorded no test times: the test command prints no \`TESTRUN sec\` lines; conveyor/README.md, Test file times, says how to add them$t"
  # No test file has a CPU budget: the pack's budget settings left in it are ignored, all named on one line.
  t=$(jq -r '[(.test | objects | select(has("fileBudget")) | "test.fileBudget"),
      (.test.files | objects | to_entries[] | select(.value | objects | has("budget")) | "test.files.\(.key).budget"),
      (.test.rules.list | arrays | .[] | objects | select(.measure == "budget") | "the test rule \(.name // "")")] | join(", ")' "$PACK" 2>/dev/null) || t=''
  [ -z "$t" ] || echo "note: no test file has a CPU budget, so the pack's budget settings are ignored: $t; take them out of $PACK"
  narrowwarn
  if packget privacy.mode e && [ "$e" = public ]; then
    if t=$(termsfile); then ok "the terms file $t"
    elif termsnamed; then no "a readable terms file (the host file $HOST names one, or does not read, and the pack's privacy.mode is public)" "make the file it names readable, or take \"terms\" out of $HOST"
    else ok "no terms file (it is optional): the privacy check runs with no word list"; fi
  fi
  ! command -v jq >/dev/null || doctordeps || bad=1
  return $bad
}
