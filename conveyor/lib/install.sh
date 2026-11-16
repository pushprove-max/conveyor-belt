# SPDX-License-Identifier: Apache-2.0
# Whether VERSIONS/<commit> holds that commit as cloned: a repository of its own (never one Git finds above the folder),
# HEAD that commit, nothing changed or added, and nothing hidden from status by an index flag (assume-unchanged,
# skip-worktree), a file system monitor or a replacement ref (git replace: another commit's tree under this id).
# The folder is no link (the read-only check does not follow one), and every file of the commit's tree is hashed as it
# is on disk, past any clean filter, which can show status a changed file as unchanged, with its executable bit as
# the tree has it (core.filemode false hides a changed bit from status).
# With `ro`, also nothing in it (links aside) that can be written. <folder> is VERSIONS/<commit> unless given.
installed() { # <commit> [ro] [folder]
  local d=${3:-$VERSIONS/$1} g l st w fs=() hs=() got=()
  [[ $1 =~ ^[0-9a-f]{40}$ ]] && [ ! -L "$d" ] && [ -d "$d/.git" ] && [ ! -L "$d/.git" ] || return 1
  g=(git --no-replace-objects --git-dir="$d/.git" --work-tree="$d" --no-optional-locks -c core.fsmonitor=false)
  [ "$("${g[@]}" rev-parse HEAD 2>/dev/null)" = "$1" ] && l=$("${g[@]}" ls-files -v 2>/dev/null) && [ -n "$l" ] && ! grep -qv '^H ' <<<"$l" \
    && st=$("${g[@]}" status --porcelain --ignored --untracked-files=all 2>/dev/null) && [ -z "$st" ] || return 1
  while IFS= read -r -d '' l; do
    st=${l#* * }; st=${st%%$'\t'*}; w=$d/${l#*$'\t'}
    case ${l%% *} in
      100644|100755) [ -f "$w" ] && [ ! -L "$w" ] && { [ "${l%% *}" = 100755 ] && [ -x "$w" ] || { [ "${l%% *}" = 100644 ] && [ ! -x "$w" ]; }; } \
        && fs+=("$w") && hs+=("$st") ;;
      120000) [ -L "$w" ] && [ "$(printf %s "$(readlink "$w")" | "${g[@]}" hash-object --no-filters --stdin)" = "$st" ] ;;
      *) false ;;
    esac || return 1
  done < <("${g[@]}" ls-tree -r -z --full-tree HEAD 2>/dev/null)
  wait $! || return 1
  # The regular files are hashed in one git run (a few, for a tree too long for one command line), not one each: a
  # git run per file was the most programs any engine function started in the engine's tests (#532). Each hash is
  # its file's, in order.
  [ ${#fs[@]} = 0 ] || { mapfile -t got < <(printf '%s\0' "${fs[@]}" | xargs -0 "${g[@]}" hash-object --no-filters --) && wait $! \
    && [ ${#got[@]} = ${#hs[@]} ] && [ "${got[*]}" = "${hs[*]}" ]; } || return 1
  [ "${2:-}" != ro ] || { w=$(find "$d" ! -type l -perm /222 -print -quit) && [ -z "$w" ]; }
}
# Clones this repository (the origin of the checkout this script is in, or the repository given) at <commit> into
# VERSIONS/<commit> and marks it read-only. Only a full commit id names a version folder, and the clone is kept only
# when it is that commit as installed() verifies it: a hook (a Git template's post-checkout) may change the files the
# checkout wrote.
install() { # <commit> [<repository>]
  local c=$1 d=$VERSIONS/$1 src=${2:-}
  [[ $c =~ ^[0-9a-f]{40}$ ]] || { echo "conveyor: $c is not a full commit id: an install cannot be verified against it" >&2; return 1; }
  if [ -e "$d" ]; then
    # A folder already there is taken only when it is that commit with nothing changed or added; it is then made read-only.
    installed "$c" || { echo "conveyor: $d is there and is not commit $c as it was cloned" >&2; return 1; }
    chmod -R a-w "$d" && echo "conveyor: $c is installed in $d, read-only"; return
  fi
  [ -n "$src" ] || src=$(git -C "$HERE" remote get-url origin) || { echo "conveyor: the checkout at $HERE has no origin to clone" >&2; return 1; }
  mkdir -p "$VERSIONS" || return 1
  # Cloned beside its place and moved in once read-only, so a version folder is never there half made.
  [ ! -e "$d.part" ] || { chmod -R u+w "$d.part" && rm -rf "$d.part"; } || return 1
  if ! { git clone -q --no-checkout "$src" "$d.part" && git --no-replace-objects -C "$d.part" -c advice.detachedHead=false checkout -q --detach "$c" \
      && installed "$c" '' "$d.part"; } 2>/dev/null; then
    rm -rf "$d.part"; echo "conveyor: commit $c could not be checked out from $src and verified" >&2; return 1
  fi
  chmod -R a-w "$d.part" && mv "$d.part" "$d" && echo "conveyor: $c is installed in $d, read-only"
}
# The commit the project runs on this machine: the pack's pin, or, for a pack that follows the plugin's main, the
# newest commit taken here (ENGINE; empty while none is). The second variable, when named, is set to the branch the
# pack follows (empty for a pin). Fails when the pack does not read.
enginepin() { # <commit variable> [<follow variable>]
  local ep_c ep_f # names packget's own locals (f_, v_...) do not shadow
  packget plugin.commit ep_c plugin.follow ep_f || return 1
  [ -z "$ep_f" ] || ep_c=$(jq -r '.commit | strings | select(test("^[0-9a-f]{40}$"))' "$ENGINE" 2>/dev/null) || ep_c=''
  printf -v "$1" %s "$ep_c"; [ -z "${2:-}" ] || printf -v "$2" %s "$ep_f"
}
# The plugin's repository as its manifest names it, for a plugin folder that is no clone of its own (a marketplace
# install runs from Claude Code's plugin cache, a copy with no .git; one inside a repository kept above it, such as a
# config folder in git, is no clone either): plugin.json's repository, else the marketplace entry's source for that
# plugin (its url source's git URL), as https://github.com/<owner>/<repo>. When neither names one on GitHub, says
# which sources it read.
manifestrepo() {
  local p=${HERE%/*} m r
  m=$p/.claude-plugin
  r=$(jq -r '.repository | if type == "object" then .url else . end | strings' "$m/plugin.json" 2>/dev/null)
  [ -n "$r" ] || r=$(jq -r --arg n "$(jq -r '.name | strings' "$m/plugin.json" 2>/dev/null)" \
    '[.plugins[]? | select(.name == $n) | .source | objects | select(.source == "url") | .url | strings][0] // empty' "$m/marketplace.json" 2>/dev/null)
  r=${r%/}; r=${r%.git}
  if [[ $r =~ ^(https://github\.com/|ssh://git@github\.com/|git@github\.com:)?([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$ ]]; then
    echo "https://github.com/${BASH_REMATCH[2]}"
  else
    echo "conveyor: the plugin's repository could not be found: $p is no clone with an origin, and neither $m/plugin.json (repository) nor $m/marketplace.json (the plugin's source.url) names one on GitHub" >&2
    return 1
  fi
}
# Whether the plugin folder this engine is in is a clone of its own (not a copy inside a repository kept above it).
ownclone() { [ "$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" = "${HERE%/*}" ]; }
# The plugin's <branch> as pushed: "<repository> TAB <commit>". The repository is the remote that branch follows in the
# plugin checkout this engine was installed from (an install's origin; run from a checkout, that checkout), or that
# checkout itself when the branch follows none there; for a plugin folder that is no clone, or an install with no
# origin, the one its manifest names (manifestrepo).
mainof() { # <branch>
  local src r h
  if ownclone && [ -z "$OWN" ]; then src=${HERE%/*}
  else { ownclone && src=$(git -C "$HERE" remote get-url origin 2>/dev/null); } || src=$(manifestrepo) || return 1; fi
  r=$(git -C "$src" config "branch.$1.remote" 2>/dev/null) && [ "$r" != . ] && r=$(git -C "$src" remote get-url "$r" 2>/dev/null) && src=$r
  h=$(timeout 60 git ls-remote "$src" "refs/heads/$1" 2>/dev/null) && h=${h%%[[:space:]]*} && [[ $h =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s\t%s\n' "$src" "$h"
}
# The plugin's newest release: "<repository> TAB <commit> TAB <tag>". The repository is the origin of the plugin
# checkout this engine was installed from (an install's origin; run from a checkout, that checkout's origin), or, for
# a plugin folder that is no clone or has no origin, the one its manifest names (manifestrepo); the
# release is the newest vX.Y.Z tag whose GitHub release is published (neither a draft nor a prerelease), never main;
# the commit is the one that tag names on the repository.
releaseof() {
  local src t h
  { ownclone && src=$(git -C "$HERE" remote get-url origin 2>/dev/null); } || src=$(manifestrepo) || return 1
  t=$(timeout 60 gh release list -R "$src" --limit 100 --json tagName,isDraft,isPrerelease 2>/dev/null \
    | jq -r '[.[] | select((.isDraft or .isPrerelease) | not) | .tagName | strings | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))]
        | max_by(ltrimstr("v") | split(".") | map(tonumber)) // empty' 2>/dev/null) && [ -n "$t" ] || return 1
  # An annotated tag names its commit on the peeled line (^{}).
  h=$(timeout 60 git ls-remote "$src" "refs/tags/$t" "refs/tags/$t^{}" 2>/dev/null | awk -v t="refs/tags/$t" '$2 == t && !h {h = $1} $2 == t "^{}" {p = $1} END {print (p != "" ? p : h)}') \
    && [[ $h =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s\t%s\t%s\n' "$src" "$h" "$t"
}
# What a pack following <follow> (main or releases) would take now: "<repository> TAB <commit> TAB <name>", the name
# what messages call it ("main", "release v1.2.3"); the release's tag is in the name.
headof() { # <follow>
  local u h t
  if [ "$1" = releases ]; then IFS=$'\t' read -r u h t < <(releaseof) && [ -n "$h" ] && printf '%s\t%s\trelease %s\n' "$u" "$h" "$t"
  else IFS=$'\t' read -r u h < <(mainof "$1") && [ -n "$h" ] && printf '%s\t%s\t%s\n' "$u" "$h" "$1"; fi
}
# The hooks the project's .claude/settings.json runs through shim.sh (the path after it in a command) that <folder>
# does not hold, one a line.
hooksmissing() { # <folder>
  local p
  jq -r '[.. | objects | .command? | strings | capture("shim\\.sh\\W*\\s+[^\\w./\\s-]?(?<p>[\\w./-]+)").p] | unique[]' "$MAIN/.claude/settings.json" 2>/dev/null \
    | while IFS= read -r p; do [ -f "$1/$p" ] || echo "$p"; done
}
# For a pack that follows the plugin's main or its releases (docs/setup.md, Following releases or main, or pinning a commit), what keeps the project up
# to date on this machine, with nobody asked: run by the loop once every IDLE seconds, beside its cards and never one
# of them, and by shim.sh (`conveyor.sh take`): first, on a machine that has taken no commit yet, then beside a hook
# once a minute at most. Once the plugin's pushed main (mainof), or its newest release (releaseof), is a commit this
# project has not taken, that commit is installed (install()), its own pack check is run on the project's
# pack, and every hook the project's .claude/settings.json runs through shim.sh must be in it. Then it is the
# project's current engine (ENGINE): the loop restarts on it at its next pick (stale(), lib/run.sh) and shim.sh runs
# hooks from it; cards in flight end on the engine they started on. A commit that fails its check or lacks a hook is
# not taken and not tried again: the project stays on its engine, and ENGINE's refused (Needs you, in the snapshot)
# names the commit and why until a later commit is taken. One that could not be read or installed is tried again at
# the next look. Then old installs are pruned (prune). Nothing for a pinned pack. Under ENGINE's lock, so a loop and a
# hook never take at once.
take() { ( flock -w 600 9 || { echo "conveyor: another take of the plugin's main did not end" >&2; exit 1; }; taken ) 9>>"$ENGINE.lock"; }
taken() {
  local f h u n why t
  packget plugin.follow f || return 1; [ -n "$f" ] || return 0
  IFS=$'\t' read -r u h n < <(headof "$f") && [ -n "$h" ] || { echo "conveyor: the plugin's $f could not be read from its remote" >&2; return 1; }
  if [ "$h" != "$(jq -r '.commit // ""' "$ENGINE" 2>/dev/null)" ] && [ "$h" != "$(jq -r '.refused.commit // ""' "$ENGINE" 2>/dev/null)" ]; then
    why=$(install "$h" "$u" 2>&1 >/dev/null) || { echo "conveyor: Conveyor commit $h of the plugin's $n could not be installed: $why" >&2; return 1; }
    if ! why=$("$VERSIONS/$h/conveyor/lib/pack.sh" check "$PACK" 2>&1); then why="its check of the pack failed: ${why//$'\n'/; }"
    elif why=$(hooksmissing "$VERSIONS/$h") && [ -n "$why" ]; then why="it lacks hooks .claude/settings.json runs through shim.sh: ${why//$'\n'/, }"
    else why=''; fi
    t=$(mktemp "$ENGINE.XXXXXX") || return 1
    # A record that is not there, empty or not JSON is begun again. Following releases, the release's tag is kept
    # beside its commit (release), for doctor.
    { cat "$ENGINE" 2>/dev/null || :; } | jq -n --arg c "$h" --arg r "$why" --arg v "${n#release }" --arg f "$f" '(input? | objects) // {}
      | if $r == "" then {commit: $c, taken: ((.taken // []) - [$c] + [$c])} + (if $f == "releases" then {release: $v} else {} end)
      else . + {refused: ({commit: $c, reason: $r[0:1500], since: (now | todate)} + (if $f == "releases" then {release: $v} else {} end))} end' > "$t" \
      && mv "$t" "$ENGINE" || { rm -f "$t"; return 1; }
    if [ -z "$why" ]; then echo "conveyor: took Conveyor commit $h of the plugin's $n: the loop restarts on it at its next pick"
    else echo "conveyor: did not take Conveyor commit $h of the plugin's $n, as $why; the project stays on $(jq -r '.commit // "no commit"' "$ENGINE")" >&2; fi
  fi
  prune ${why:+"$h"}
}
# Old installs: of the commits this project took (ENGINE's taken), the newest two stay, and so does each one a card
# of it in flight runs on (its worktree line's engine) or this loop runs, and each one a file of USES (a research
# lane's settings, the machine's service) or a Conveyor service of this machine (services: a per-project one of before
# too, whose restart or reboot runs the file it names) still names by its path, or another project of the host file
# runs (its pack's pin, a card of it in flight or its loop: a pinned project repinned while a card runs on its old pin) or the
# machine's Conveyor runs from, or the Foreman's waiter of this project or another runs from while it runs (foremanon):
# those stay in the list, to be looked at again at the next prune. Every other leaves
# the list, and its folder is removed unless another following project's own taken list names it (that project's
# prune removes it; were it kept in both lists, neither would). A <refused> commit (installed to be checked, never
# taken) not in the list goes the same way: no card runs on it, and it is never tried again.
prune() { # [<refused>]
  local old keep held others c f t m s gone=()
  old=$(jq -r '(.taken // []) as $t | $t[:-2] + ($ARGS.positional - $t) | .[]' "$ENGINE" --args "$@" 2>/dev/null) && [ -n "$old" ] || return 0
  keep=$(inflight <(stdb ask lines cards 2>/dev/null)
    while IFS= read -r f; do grep -oE 'versions/[0-9a-f]{40}/' "$f" 2>/dev/null | cut -c10-49; done 2>/dev/null < <(cat "$USES" 2>/dev/null; services | cut -f1)
    foremanon "$ST")$'\n'$OWN$'\n'$RAN
  # The other projects: what they run (held), each line "h <commit>", and what their own taken lists name, "t <commit>".
  others=$(jq -r '.commit // empty | "h \(.)"' "$MACH/loop.json" 2>/dev/null
    projects 2>/dev/null | while IFS=$'\t' read -r _ m _; do
      [ ! "$m" -ef "$MAIN" ] || continue
      # Its state folder as paths.sh names it: the host file's stateDir for the host's own checkout, else its conveyor/state.
      s=$m/conveyor/state; [ "$(cd "$m" 2>/dev/null && pwd -P)" != "${hm:-}" ] || s=${hp[0]:-$s}
      { jq -r '.plugin.commit // empty | "h \(.)"' "$m/.conveyor/project.json"; jq -r '.taken // [] | .[] | "t \(.)"' "$m/.git/conveyor-engine.json"
        { inflight "$s/cards.jsonl"; foremanon "$s"; } | sed 's/^/h /'; jq -r '.commit // empty | "h \(.)"' "$s/loop.json"; } 2>/dev/null
    done)
  held=$(sed -n 's/^h //p' <<<"$others"); others=$(sed -n 's/^t //p' <<<"$others")
  for c in $old; do
    grep -qxF "$c" <<<"$keep" && continue
    [[ $c =~ ^[0-9a-f]{40}$ ]] && [ -d "$VERSIONS/$c" ] || { gone+=("$c"); continue; }
    grep -qxF "$c" <<<"$held" && continue
    gone+=("$c")
    grep -qxF "$c" <<<"$others" && continue
    chmod -R u+w "$VERSIONS/$c" && rm -rf "$VERSIONS/$c" && echo "conveyor: removed the old install $VERSIONS/$c"
  done
  [ ${#gone[@]} != 0 ] || return 0
  t=$(mktemp "$ENGINE.XXXXXX") && jq '.taken -= $ARGS.positional' "$ENGINE" --args "${gone[@]}" > "$t" && mv "$t" "$ENGINE" || { rm -f "$t"; return 1; }
}
# The commit the Foreman's waiter of the state folder <dir> runs from (foreman/waiter.pid: "<pid> <commit> <session>",
# foreman/waiter.sh) while that pid runs; its watchers end before it does (waiter.sh, stop_all). The pid is asked,
# not waiter.lock: a probe of the lock could make a waiter starting that instant find it taken and not start.
foremanon() { # <dir>
  local p c
  read -r p c _ 2>/dev/null < "$1/foreman/waiter.pid" && [[ $p =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null && printf '%s\n' "$c"
}
# The engine commits the cards in flight of the card records <file> run on (each worktree line's engine), one a line.
inflight() { jq -rs 'group_by(.card)[] | select(all(.step | IN("landed", "closed", "blocked") | not)) | .[].engine // empty' "$1" 2>/dev/null; }
# The Conveyor services of this machine, the machine's and any per-project one of before: each systemd user unit or
# launchd agent whose start runs a conveyor.sh, one a line, "<its file>\t<the conveyor.sh it runs>", with systemd's
# quotes and $$, %% and \ escapes, or the plist's &lt; &gt; &amp;, undone. For prune() and doctor.
services() {
  local o s
  for o in "${XDG_CONFIG_HOME:-$HOME/.config}"/systemd/user/conveyor*.service; do
    [ -f "$o" ] || continue
    s=$(sed -nE 's/^ExecStart=(.*[ =])?("[^"]*conveyor\.sh"|[^" ]*conveyor\.sh)( .*)?$/\2/p' "$o" | head -1 | sed 's/^"//; s/"$//; s/\\\(.\)/\1/g; s/%%/%/g; s/\$\$/$/g')
    [ -z "$s" ] || printf '%s\t%s\n' "$o" "$s"
  done
  for o in "$HOME"/Library/LaunchAgents/conveyor[.-]*.plist; do
    [ -f "$o" ] || continue
    s=$(sed -n 's/.*<string>\([^<]*conveyor\.sh\)<\/string>.*/\1/p' "$o" | head -1 | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g')
    [ -z "$s" ] || printf '%s\t%s\n' "$o" "$s"
  done
}
# The release <commit> is (ENGINE's release) and whether a newer one is published, for doctor.
released() { # <commit>
  local u h t r
  r=$(jq -r '.release // empty' "$ENGINE" 2>/dev/null); r=${r:-a release not recorded}
  IFS=$'\t' read -r u h t < <(releaseof) && [ -n "$h" ] || { echo "release $r; whether a newer release is published could not be read"; return; }
  # The newest release's commit is named by its tag, so one taken while following main has its release named too.
  if [ "$h" = "$1" ]; then echo "release $t, the newest release"
  else echo "release $r; a newer release is published: $t (commit $h)"; fi
}
# How far <commit> is behind the plugin's pushed <branch>, for doctor.
behind() { # <commit> <branch>
  local u h d n=''
  IFS=$'\t' read -r u h < <(mainof "$2") && [ -n "$h" ] || { echo "how far behind the plugin's $2 it is could not be read"; return; }
  [ "$h" != "$1" ] || { echo "the plugin's $2 as pushed"; return; }
  d=$(mktemp -d) && git init -q --bare "$d" && timeout 120 git -C "$d" fetch -q --filter=blob:none "$u" "refs/heads/$2" 2>/dev/null \
    && n=$(git -C "$d" rev-list --count "$1..FETCH_HEAD" 2>/dev/null)
  rm -rf "$d"
  echo "${n:-some} commit$([ "$n" = 1 ] || echo s) behind the plugin's $2 ($h)"
}
# The machine's one user service (docs/setup.md, Run): it runs `machine` (machineloop) from the install of the commit pinned
# by the pack of the current repo (the main checkout of the folder this was called from), or of its current engine
# when the pack follows the plugin's main (the service keeps that install: prune()), or, when the pack pins and follows
# nothing and a service of before runs the repo's own checkout's conveyor.sh, from that conveyor.sh (the repo is then
# recorded as run from its checkout), and that repo becomes a record of the host file (hostadd) if it is not one: a systemd user unit on Linux, a launchd agent on macOS, both
# named conveyor-machine. Either names this bash and this PATH, as a service starts with a bare PATH (gh, jq, git,
# claude, codex, and on macOS the GNU tools), and the data and config folders this was called with, where the loops
# find their installs and the host file. Each project's loop restarts itself on its own pack's pin.
# It replaces the per-project services of before: each other user unit or agent that runs Conveyor's `serve` has its
# project made a record of the host file (oldkept); then each is stopped and disabled, the machine's service is
# started, and only then are their files removed. Their state folders stay where they are and are read in place.
# A refusal leaves every loop as it was: while one of them cannot be made a record, none is stopped; when one cannot
# be stopped, or the machine's service does not start, each stopped so far is started again. The machine's service is
# never written or started beside one left running: its loops beside that one's would pass the machine cap. It says
# which, and install-service is run again once that one is seen to.
# A machine service already running is left running.
# <unit or agent file> <its CONVEYOR_MAIN> <the conveyor.sh it runs>: 0 once its project is a record of the host
# file. One with no CONVEYOR_MAIN serves the checkout its conveyor.sh is in (lib/paths.sh), unless that is an install.
# A project served from its own checkout's code (the plugin's own belt) is recorded as run from it (hostadd checkout),
# so the machine's Conveyor runs it on that checkout's code, as its service did.
oldkept() {
  local m=$2 s=''
  if s=$(ownckout "$3"); then m=${m:-$s}; [ "$s" -ef "$m" ] || s=''; else s=''; fi
  [ -n "$m" ] && MAIN=$m hostadd ${s:+checkout} && return 0
  echo "conveyor: left ${1##*/} running: its project (${m:-not named in it}) could not be made a record of $HOST; add it, then run install-service again" >&2
  return 1
}
# <conveyor.sh>: the main checkout it is in, printed, when that is not an install; 1 when it is one, or in no checkout.
ownckout() {
  local g s
  [ -n "$1" ] && g=$(git -C "${1%/*}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && s=$(cd "$g/.." && pwd -P) \
    && [ "${s%/*}" != "$(cd "$VERSIONS" 2>/dev/null && pwd -P)" ] && echo "$s"
}
installservice() {
  local repo pin code name=conveyor-machine f o m s uid why left=() olds=() stopped=() data=${VERSIONS%/conveyor/versions} conf=${XDG_CONFIG_HOME:-$HOME/.config}
  repo=$(cd "$CALLED" && cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P) \
    || { echo "conveyor: install-service runs in the checkout of a project to serve" >&2; return 1; }
  pin=$("$HERE/lib/pack.sh" get plugin.commit "$repo/.conveyor/project.json") && f=$("$HERE/lib/pack.sh" get plugin.follow "$repo/.conveyor/project.json") || return 1
  # A pack that follows the plugin's main runs its current engine on this machine, taken first when it has none.
  [ -z "$f" ] || { [ -s "$repo/.git/conveyor-engine.json" ] || CONVEYOR_MAIN=$repo "$BASH" "$HERE/conveyor.sh" take; pin=$(jq -r '.commit // empty' "$repo/.git/conveyor-engine.json" 2>/dev/null); }
  # A pack that pins and follows nothing, its project served by a service of before from its own checkout's code (the
  # plugin's own belt): that code runs the machine's Conveyor, and the project is recorded as run from its checkout.
  [ -n "$pin$f" ] || code=$(services | while IFS=$'\t' read -r _ s; do [ "$(ownckout "$s")" = "$repo" ] && { echo "$s"; break; }; done)
  if [ -n "$pin$f" ] || [ -z "$code" ]; then
    code=$VERSIONS/$pin/conveyor/conveyor.sh
    installed "$pin" ro && [ -f "$code" ] \
      || { echo "conveyor: the pack of $repo pins Conveyor commit ${pin:-(none)}, which is not installed and verified: run conveyor install <commit>" >&2; return 1; }
    machined "$code" \
      || { echo "conveyor: the pack of $repo pins Conveyor commit $pin, which has no machine's Conveyor to run: pin a newer commit; no service was changed" >&2; return 1; }
    MAIN=$repo hostadd || return 1
  else
    machined "$code" \
      || { echo "conveyor: $repo runs Conveyor from its own checkout's $code, which has no machine's Conveyor to run: update that checkout, or pin a commit in its pack; no service was changed" >&2; return 1; }
    MAIN=$repo hostadd checkout || return 1
  fi
  # Per system: the services of before (olds), and how one is stopped (oldstop: 1 when it could not be; one not
  # running is passed by: oldon) and started again (oldstart), and how the machine's is written and started (machinestart).
  if [ "$(uname -s)" = Darwin ]; then
    uid=$(id -u); f=$HOME/Library/LaunchAgents/$name.plist
    for o in "$HOME"/Library/LaunchAgents/conveyor.*.plist; do
      [ -f "$o" ] && [ "$o" != "$f" ] && grep -qF '<string>serve</string>' "$o" || continue
      m=$(sed -n 's/.*<key>CONVEYOR_MAIN<\/key><string>\(.*\)<\/string>.*/\1/p' "$o" | head -1 | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g')
      s=$(sed -n 's/.*<string>\([^<]*conveyor\.sh\)<\/string><string>serve<\/string>.*/\1/p' "$o" | head -1 | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g')
      if oldkept "$o" "$m" "$s"; then olds+=("$o"); else left+=("${o##*/}"); fi
    done
    oldon() { local l=${1##*/}; launchctl print "gui/$uid/${l%.plist}" >/dev/null 2>&1; } # one not loaded is only removed
    oldstop() { local l=${1##*/}; l=${l%.plist}; launchctl bootout "gui/$uid/$l" && return
      echo "conveyor: left the per-project agent $l: it could not be stopped; stop it with launchctl bootout gui/$uid/$l, then run install-service again" >&2; return 1; }
    oldstart() { launchctl bootstrap "gui/$uid" "$1"; }
    machinestart() {
      mkdir -p "$(dirname "$f")" "$HOME/Library/Logs" || return 1
      xml() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<<"$1"; }
      cat > "$f" <<PLIST || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$name</string>
  <key>ProgramArguments</key>
  <array><string>$(xml "$BASH")</string><string>$(xml "$code")</string><string>machine</string></array>
  <key>WorkingDirectory</key><string>$(xml "$repo")</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(xml "$PATH")</string>
    <key>XDG_DATA_HOME</key><string>$(xml "$data")</string>
    <key>XDG_CONFIG_HOME</key><string>$(xml "$conf")</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$(xml "$HOME/Library/Logs/$name.log")</string>
  <key>StandardErrorPath</key><string>$(xml "$HOME/Library/Logs/$name.log")</string>
</dict>
</plist>
PLIST
      launchctl print "gui/$uid/$name" >/dev/null 2>&1 || launchctl bootstrap "gui/$uid" "$f"
    }
  else
    f=$conf/systemd/user/$name.service
    for o in "$conf"/systemd/user/conveyor*.service; do
      [ -f "$o" ] && [ "$o" != "$f" ] && grep -qE '^ExecStart=.*conveyor\.sh"? serve$' "$o" || continue
      m=$(sed -n 's/^Environment="CONVEYOR_MAIN=\(.*\)"$/\1/p' "$o" | head -1 | sed 's/\\\(.\)/\1/g; s/%%/%/g')
      # The conveyor.sh it runs: the word before serve, quoted or not; systemd's $$, %% and \ escapes undone.
      s=$(sed -nE 's/^ExecStart=(.*[ =])?("[^"]*conveyor\.sh"|[^" ]*conveyor\.sh) serve$/\2/p' "$o" | head -1 | sed 's/^"//; s/"$//; s/\\\(.\)/\1/g; s/%%/%/g; s/\$\$/$/g')
      if oldkept "$o" "$m" "$s"; then olds+=("$o"); else left+=("${o##*/}"); fi
    done
    oldon() { :; } # each is disabled, running or not
    oldstop() { systemctl --user disable --now "${1##*/}" && return
      echo "conveyor: left the per-project unit ${1##*/}: it could not be stopped; stop it with systemctl --user disable --now ${1##*/}, then run install-service again" >&2; return 1; }
    oldstart() { systemctl --user enable --now "${1##*/}"; }
    machinestart() {
      mkdir -p "$(dirname "$f")" || return 1
      # systemd expands % in every line and $ in ExecStart: each is doubled to stand for itself. Inside double quotes it
      # reads \ and \" as escapes: qt escapes both.
      pc() { printf '%s' "${1//%/%%}"; }; qt() { local s; s=$(pc "$1"); s=${s//\\/\\\\}; printf '%s' "${s//\"/\\\"}"; }
      dl() { local s; s=$(qt "$1"); printf '%s' "${s//\$/\$\$}"; }
      cat > "$f" <<UNIT || return 1
[Unit]
Description=Conveyor Belt: the machine's Conveyor, every project of the host file
After=network-online.target

[Service]
WorkingDirectory=$(pc "$repo")
Environment="PATH=$(qt "$PATH")"
Environment="XDG_DATA_HOME=$(qt "$data")"
Environment="XDG_CONFIG_HOME=$(qt "$conf")"
ExecStart="$(dl "$BASH")" "$(dl "$code")" machine
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
UNIT
      systemctl --user daemon-reload && systemctl --user enable --now "$name.service"
    }
  fi
  [ ${#left[@]} = 0 ] || { echo "conveyor: the machine's Conveyor is not started while a per-project loop is left running beside it (${left[*]}): the two would pass the machine cap; no per-project service was stopped" >&2; return 1; }
  # Each removed only once it is stopped and the machine's service runs: a file gone under a running service leaves a
  # second loop, and one gone before the machine's runs leaves its project with none.
  for o in "${olds[@]}"; do
    oldon "$o" || continue
    if oldstop "$o"; then stopped+=("$o"); else left+=("${o##*/}"); break; fi
  done
  if [ ${#left[@]} != 0 ]; then why="the machine's Conveyor is not started while a per-project loop is left running beside it (${left[*]}): the two would pass the machine cap"
  elif ! machinestart; then why="the machine's Conveyor $f could not be started"; else why=''; fi
  if [ -n "$why" ]; then
    echo "conveyor: $why" >&2
    for o in "${stopped[@]}"; do
      if oldstart "$o"; then echo "conveyor: started the per-project service ${o##*/} again" >&2
      else echo "conveyor: the per-project service ${o##*/} could not be started again: start it by hand" >&2; fi
    done
    return 1
  fi
  for o in "${olds[@]}"; do
    if rm -f "$o"; then echo "conveyor: removed the per-project service ${o##*/}"
    else echo "conveyor: the per-project service ${o##*/} is stopped and disabled, but its file could not be removed: remove it by hand" >&2; fi
  done
  # The service names the install by its path: listed in USES, so prune() keeps it.
  grep -qxF "$f" "$USES" 2>/dev/null || echo "$f" >> "$USES" || return 1
  echo "conveyor: $f runs $code machine for every project of $HOST"
}
# `conveyor.sh board`, in a project's checkout: the Board installed as this user's service (dashboard.sh --install),
# reading this project, from the install of the commit the project runs (its pin, or the commit it took of the
# releases or main it follows), not from a clone of its own. With no Board admin who has a password yet, it first adds
# one, admin, asking for the password. The service names the install by its path: listed in USES, so prune() keeps it.
board() {
  local repo pin f s
  repo=$(cd "$CALLED" && cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P) \
    || { echo "conveyor: board runs in the checkout of a project" >&2; return 1; }
  pin=$("$HERE/lib/pack.sh" get plugin.commit "$repo/.conveyor/project.json") && f=$("$HERE/lib/pack.sh" get plugin.follow "$repo/.conveyor/project.json") || return 1
  [ -z "$f" ] || { [ -s "$repo/.git/conveyor-engine.json" ] || CONVEYOR_MAIN=$repo "$BASH" "$HERE/conveyor.sh" take; pin=$(jq -r '.commit // empty' "$repo/.git/conveyor-engine.json" 2>/dev/null); }
  s=$VERSIONS/$pin/.claude/scripts
  installed "$pin" ro && [ -f "$s/dashboard.sh" ] \
    || { echo "conveyor: the pack of $repo names Conveyor commit ${pin:-(none)}, which is not installed and verified with a Board: run /conveyor-belt:setup" >&2; return 1; }
  [ -x "$BOARD_VENV/bin/python3" ] || { echo "conveyor: the Board's virtualenv $BOARD_VENV is not there: run /conveyor-belt:setup" >&2; return 1; }
  CONVEYOR_MAIN=$repo "$BOARD_VENV/bin/python3" "$s/dashboard_server.py" has-password >/dev/null 2>&1 \
    || CONVEYOR_MAIN=$repo "$BOARD_VENV/bin/python3" "$s/dashboard_server.py" add-user admin --admin || return 1
  CONVEYOR_MAIN=$repo "$BASH" "$s/dashboard.sh" --install || return 1
  if [ "$(uname -s)" = Darwin ]; then f=$HOME/Library/LaunchAgents/com.conveyor.dashboard.plist; else f=$HOME/.config/systemd/user/dashboard.service; fi
  grep -qxF "$f" "$USES" 2>/dev/null || echo "$f" >> "$USES" || return 1
  echo "conveyor: the Board runs from $s for $repo"
}
