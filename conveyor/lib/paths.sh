# SPDX-License-Identifier: Apache-2.0
# The installs (plan section 7): `install <commit>` puts that commit in VERSIONS/<commit>, read-only. OWN is the
# commit this process runs: its version folder's name when it runs from an install, empty when it runs from a checkout.
# A loop that runs from an install restarts on the commit the pack pins; a `serve` run from a checkout restarts on the
# checkout's code once its HEAD moves to a commit that changes engine code (stale(), lib/install.sh); past one that
# changes none, RAN moves to it with no restart (samecode()). RAN is the commit this process runs: OWN, or the checkout's
# HEAD read here, before bash reads the rest of this file, so a commit that lands while the engine is read is newer
# than RAN and restarts the loop. RAN is empty when the engine's folder is in no git checkout. FOLLOW is set for a
# `serve` run from a checkout (run()).
VERSIONS=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/versions; OWN=''; RAN=''; FOLLOW=''
up=${HERE%/*}; [ "$(cd "$VERSIONS" 2>/dev/null && pwd -P)" != "${up%/*}" ] || [ -z "${up%/*}" ] || OWN=${up##*/}
RAN=$OWN; [ -n "$OWN" ] || RAN=$(git -C "$HERE" rev-parse -q --verify HEAD 2>/dev/null) || RAN=''
# The main checkout is CONVEYOR_MAIN when it is set. If not, it is the checkout of the folder the command is called in
# for these commands: `setup`, `doctor`, `foreman`, `lane`, `take`, `board`, `lint` and `size`, which are for the
# project they are called in (the plugin copy runs them before the project has an engine, `board` runs from an install,
# read-only, in the project's checkout, `lane` called in the fast lane acts for that lane's main checkout, and `lint`
# called in a card's worktree reads that worktree's main checkout, as `size` does),
# and `auto` and
# `wording`, which the plugin's commands run. It is that checkout for every command too when the engine runs from an
# install, or from a folder in no git checkout (RAN empty), such as the plugin copy that Claude Code installs from a
# marketplace. Any other command is for the checkout the engine is in. When the folder looked in is in no git
# checkout, the command stops and names that folder: no path is made from an empty name.
mainat=$HERE
[[ ${1:-} =~ ^(setup|doctor|foreman|lane|take|board|lint|size|auto|wording)$ ]] || [ -n "$OWN" ] || [ -z "$RAN" ] && mainat=$(pwd)
MAIN=${CONVEYOR_MAIN:-}
[ -n "$MAIN" ] || { MAIN=$(git -C "$mainat" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && [ -n "$MAIN" ] && MAIN=$(cd "$MAIN/.." && pwd -P) && [ -n "$MAIN" ]; } \
  || { echo "conveyor: the project's main checkout cannot be found: $mainat is in no git checkout; run conveyor.sh in the project's checkout, or name it in CONVEYOR_MAIN" >&2; exit 1; }
# A project whose pack follows the plugin's main or its releases (plugin.follow) has its current engine on this machine
# in ENGINE, in the main checkout's git folder, so no worktree, card or commit carries it: {commit: the newest commit
# taken, release: its tag (following releases), taken: the commits taken here, oldest first, refused: {commit,
# reason, since, release} while the newest commit of main (or newest release) failed its check, head: {commit, name}
# the newest commit the last take read, worked: the time of the last take that worked (take(), lib/install.sh)}. shim.sh reads the same file.
ENGINE=$MAIN/.git/conveyor-engine.json
# The log of the takes shim.sh starts beside a hook, one JSON line each (shim.sh names the fields): stalenote() reads it.
# shellcheck disable=SC2034 # read by lib/install.sh, which conveyor.sh sources beside this file
ENGINELOG=$MAIN/.git/conveyor-engine.log
# The files outside the installs that name one by its path (a research lane's settings, written by lanes/research.sh;
# the machine's service, by install-service), one a line: prune() keeps each install one of them still names.
USES=${VERSIONS%/*}/uses
# The main checkouts of the projects that follow the plugin on this machine, one a line, each listed by its own take
# (taken(), which setup runs too): prune() keeps every install one of them names in its ENGINE, also when the host
# file of the project pruning does not list it.
# shellcheck disable=SC2034 # read by lib/install.sh, which conveyor.sh sources beside this file
FOLLOWERS=${VERSIONS%/*}/followers
# The Foreman folders of this machine, one a line, each listed by its own waiter as it starts (foreman/waiter.sh):
# prune() keeps the commit each live waiter names in its waiter.pid, also for a project no list above names, or one
# whose Foreman folder is not where its state folder is guessed.
# shellcheck disable=SC2034 # read by lib/install.sh, which conveyor.sh sources beside this file
FOREMEN=${VERSIONS%/*}/foremen
# The Board's own virtualenv (the page server's Python, dashboard.sh's BOARD_PY): setup fills it from requirements.txt
# with every hash checked, never the system Python; doctor checks each package the Board imports.
BOARD_VENV=${XDG_DATA_HOME:-$HOME/.local/share}/conveyor/board-venv
BOARD_REQ=$HERE/../.claude/scripts/requirements.txt
BOARD_PKGS='pyotp segno cryptography'
# The state folder and the cards folder (plan section 12): the one place either is resolved. Every other reader asks
# `conveyor.sh state-dir`. A blocked card's kept work is under the state folder, in kept/<card>; its blocked line
# names that folder relative to the state folder. The state folder is the host file's stateDir for the checkout the
# host file's main names, else its first record's (for every checkout when it names neither); any other checkout on
# the host (another record) keeps its own conveyor/state, so no record reads or changes another's cards or control
# record. With a host file that names no stateDir, it is the checkout's conveyor/state. A host file that is there but cannot be read
# as JSON stops every command: it may name another folder, so the checkout's is never taken in its place.
# It is absent only when the nearest path above it that is there is a folder that can be searched: test's -e is false
# both when the file is not there and when a folder or link above it cannot be followed, and only the first means
# absent. Anything else in the way (a link that cannot be followed, a file) is read, and fails.
HOST=${XDG_CONFIG_HOME:-$HOME/.config}/conveyor/host.json; ST=
nohost() {
  local up=$HOST
  while ! [ -e "$up" ] && ! [ -L "$up" ]; do case $up in */*) up=${up%/*}; up=${up:-/} ;; *) up=. ;; esac; done
  [ "$up" != "$HOST" ] && [ -d "$up" ] && [ -x "$up" ]
}
if ! nohost; then
  # doctor goes on, and names the host file among what is wrong.
  own='(.main // (.records | arrays | .[0] | objects | .main) // null)'
  hm=$(jq -r "$own"' // "" | strings' "$HOST" 2>/dev/null) && [ -n "$hm" ] && hm=$(cd "$hm" 2>/dev/null && pwd -P) || hm=
  ST=$(jq -er --arg m "$MAIN" --arg r "$hm" --arg p "$(cd "$MAIN" 2>/dev/null && pwd -P)" "$own"' as $o | if $o == null or $o == $m or ($r != "" and $r == $p) then .stateDir // "" else "" end' "$HOST") || [ "${1:-}" = doctor ] || { echo "conveyor: the host file $HOST cannot be read: the state folder cannot be named" >&2; exit 1; }
  # Two checkouts with one state folder (the stateDir and another checkout's own conveyor/state, or two other
  # checkouts' conveyor/state) would share one control record: every command stops, for every checkout.
  # A state folder is compared as the folder it leads to, also before it is made: its links, and the links of the
  # folders above it, are followed as far as they lead, and a `..` after a folder not made yet is taken away
  # (a link to the stateDir is that folder).
  mapfile -t hp < <(jq -r '(.stateDir // "" | strings), (.records | arrays | .[] | objects | .main | strings)' "$HOST" 2>/dev/null)
  # The host main's state folder (the stateDir, or its own conveyor/state when the host file names none), when that
  # checkout is there; the other checkouts are compared with each other either way.
  declare -A whose=(); [ -z "$hm" ] || whose[$(realpath -m -- "${hp[0]:-$hm/conveyor/state}")]=$hm
  for m in "${hp[@]:1}" "$MAIN"; do
    p=$(cd "$m" 2>/dev/null && pwd -P) && [ "$p" != "$hm" ] || continue
    q=$(realpath -m -- "$p/conveyor/state")
    [ "${whose[$q]:-$p}" != "$p" ] || { whose[$q]=$p; continue; }
    [ "${1:-}" = doctor ] || { echo "conveyor: the host file $HOST gives the checkouts ${whose[$q]} and $p one state folder, $q: give each its own" >&2; exit 1; }
  done
fi
ST=${ST:-$MAIN/conveyor/state}
# The project's name (docs/setup.md, Run: one Conveyor per machine): the repo of the host file's record whose main is this
# checkout (links followed), else the checkout's folder name. Every card line, health and the snapshot carry it.
REPO=$(jq -r '.records | arrays | .[] | objects | select((.repo | type == "string") and (.main | type == "string")) | "\(.repo)\t\(.main)"' "$HOST" 2>/dev/null \
  | while IFS=$'\t' read -r r m; do [ "$m" = "$MAIN" ] || [ "$(cd "$m" 2>/dev/null && pwd -P)" = "$(cd "$MAIN" 2>/dev/null && pwd -P)" ] && { echo "$r"; break; }; done)
REPO=${REPO:-${MAIN##*/}}
RTAG=${REPO//[^A-Za-z0-9._-]/-} # the name as a file name
# The name in a card id (c<second>-<CTAG>-<issue>): letters, digits and hyphens only, as every reader of a card id
# takes it (jq/rows.jq, from: the blocked card a card resumes, and with it the time of its earlier tries).
CTAG=${REPO//[^A-Za-z0-9]/-}
# The cards folder (worktrees, claims, live files and the push workspace) is conveyor-cards beside the checkout; when
# another record's checkout is in the same folder, it is conveyor-cards-<repo>, so no two projects share one.
#
# The folder's name is chosen once, by the first command that makes the folder, and kept in the state folder: a
# project added or taken away beside a project whose loop runs would else give that project's next commands another
# folder than the one its loop writes to, and health and watch would not see its live cards.
CARDS=${CONVEYOR_CARDS:-$(dirname "$MAIN")/conveyor-cards}
CARDSNAME=$ST/cards-folder
# The name kept in the file $1, when it is a cards folder's name: anything else in the file is no name kept.
keptcards() { local k; IFS= read -r k < "$1" && [[ $k =~ ^conveyor-cards(-[A-Za-z0-9._-]+)?$ ]] && printf '%s\n' "$k"; } 2>/dev/null
# The name chosen when none is kept. Beside another record's checkout it is never a name that record keeps: a
# record renamed keeps the folder of its old name, and a project added under that old name takes the next one free
# (conveyor-cards-<repo>-2, -3 and on). Another record's state folder is found as this one's is, above.
choosecards() {
  local me up m p s k n=1 name=conveyor-cards-$RTAG taken=' ' beside=''
  me=$(cd "$MAIN" 2>/dev/null && pwd -P); up=$(cd "$MAIN/.." 2>/dev/null && pwd -P)
  while IFS= read -r m; do
    p=$(cd "$m" 2>/dev/null && pwd -P) && [ "$p" != "$me" ] && [ "$(cd "$m/.." 2>/dev/null && pwd -P)" = "$up" ] || continue
    beside=1; s=$p/conveyor/state; [ "$p" != "${hm:-}" ] || s=${hp[0]:-$s}
    ! k=$(keptcards "$s/cards-folder") || taken+="$k "
  done < <(jq -r '.records | arrays | .[] | objects | .main | strings' "$HOST" 2>/dev/null)
  [ -n "$beside" ] || { echo conveyor-cards; return; }
  while [[ $taken = *" $name "* ]]; do n=$((n + 1)); name=conveyor-cards-$RTAG-$n; done
  echo "$name"
}
[ -n "${CONVEYOR_CARDS:-}" ] || CARDS=$(dirname "$MAIN")/$(keptcards "$CARDSNAME" || choosecards)
STATE=$ST/cards.jsonl
RETRIED=${STATE%/*}/retried.jsonl # the lines of blocked cards that `retry` took out of the card records
# shellcheck disable=SC2034 # read by lib/mainred.sh and lib/heals.sh, which conveyor.sh sources beside this file
MAINRED=${STATE%/*}/mainred.json # the fix card of each red main commit (mainred(), lib/mainred.sh)
# shellcheck disable=SC2034 # read by lib/run.sh, which conveyor.sh sources beside this file
SPEEDRETRIED=${STATE%/*}/speedretried.jsonl # the cards an older speed check blocked that the loop retried (speedretry())
# shellcheck disable=SC2034 # read by lib/replay.sh and lib/snapshot.sh, which conveyor.sh sources beside this file
REPLAYS=${STATE%/*}/replays.jsonl # each judge replay study the owner ran: its result and its own usage (replay())
# The card records' lines the record check refused, set aside (quarantine(), views.sh): {line, field, time, record}.
# shellcheck disable=SC2034 # read by lib/views.sh, which conveyor.sh sources beside this file
QUARANTINE=${STATE%/*}/quarantined.jsonl
READ=$STATE; READ_OLD=$RETRIED          # what the readers read: these two files, or the snapshot's one copy of each
CONTROL=${STATE%/*}/control.json  # the control record; the snapshot reads its own copy of this too
# What the running loop makes of the control record: {pid, started (p_started: with pid, it names the loop's
# process; watch.py tells by it whether the loop runs), state, reason, commit (RAN: the commit it started on, null
# when none is known), checkout (the folder its script runs from when that is a checkout, else null)}, written when it changes. The loop
# may run older code than health's, which then reads the record another way; health takes the loop's word that it
# picks nothing.
SAYS=${STATE%/*}/loop.json
# The declined list: every review finding that is not built, one line each: {id, time, card, issue, finding, by (who
# declined it: code, judge or owner), why, kind (when the reason has one), repo}, ruled (when the latest ruling was
# made) and was (the rulings it replaced: [{time, by, why, kind}], oldest first) once it was declined under another
# kind, built (the issue filed for it) once the owner asked for it to be
# built after all, and dismissed ({time, by}) once it was dismissed from the Board's panel (declined(), declinedbuild(),
# declineddismiss()).
DECLINED=${STATE%/*}/declined.jsonl
# The self-heals list: every finding the judge sorted as self-heals, cleanup or already guarded that is not built on
# its own (healsadd(), lib/followups.sh), one line each: {id, time, card (the card it came from, or #<issue> for an
# issue with no card named), issue, repo, area (the area label, or null), finding, why (the judge's reason), effect
# (its kind: self-heals, cleanup or already guarded), from: review or sort}, and batched (the issue number or card id of
# the batch card filed for it: healsbatch(), lib/heals.sh), and seen (when the finding was last seen again, healsadd())
# and sightings (how many times it was seen again, healsagain(), lib/healslist.sh).
# shellcheck disable=SC2034 # read by lib/followups.sh, lib/heals.sh and lib/snapshot.sh, which conveyor.sh sources beside this file
SELFHEALS=${STATE%/*}/selfheals.jsonl
# The entries that left the self-heals list because nobody fixed or saw them again for the rules.healsdays days
# (healsexpire(), lib/heals.sh), or that the owner dropped or moved up to harm (healsdiscard(), healsharm()): each is its
# list line with dropped: {time, why: expired, dropped or harm, and filed (the card a harm one was filed as)}. Kept, not erased: the same
# finding found again takes its line back to the list (healsadd(), lib/followups.sh). Written under the list's lock.
# shellcheck disable=SC2034 # read by lib/followups.sh and lib/heals.sh, which conveyor.sh sources beside this file
HEALSDROPPED=${STATE%/*}/healsdropped.jsonl
# The docs list: every finding the judge sorted as docs drift, its lines as the self-heals list's (effect: docs drift).
# No entry expires (healsexpire() reads the self-heals list alone): a docs sweep card of its area (healsbatch() docs, lib/heals.sh) holds it, filed from the Board or
# by release-prep.
# shellcheck disable=SC2034 # read by lib/followups.sh, lib/heals.sh and lib/snapshot.sh, which conveyor.sh sources beside this file
DOCSDRIFT=${STATE%/*}/docsdrift.jsonl
# Each sort of the queued follow-up cards and open finding issues (healssort(), lib/heals.sh), one line a run: {time,
# ended, judge: {model, failed} as judgecall() printed it, items: [{card or issue, finding, effect, why, entry, done}]}.
# shellcheck disable=SC2034 # read by lib/heals.sh, lib/run.sh and lib/snapshot.sh, which conveyor.sh sources beside this file
HEALSSORT=${STATE%/*}/healssort.jsonl
# Where each open issue was last seen and since when: {"<issue>": {col: held, queue or belt, at, seen, other, by}}; seen
# is when that was known, other that the snapshot saw something besides your hold or a rule keep it in Held, by what a
# rule of the control record reads of it (labels, fu: a follow-up, p: its priority), and left when `control release`
# took it out of Held (a release of an issue something else holds, a rule as the record now stands among it, does not). No step records a move
# between Held and Queue: a snapshot dates the moves it sees (movedsaw), and `control hold` and `release` their own
# (movedhold). Each writes it under the lock.
MOVED=${STATE%/*}/moved.json
# The whole of the lists the snapshot cuts to their newest SNAPKEEP (lib/snapshot.sh), as the last snapshot left them:
# {landed, metrics: {cards}, cost: {cards, unpriced}, declinedRest, pushedCards}. `conveyor.sh history` prints it.
# shellcheck disable=SC2034 # read by lib/snapshot.sh, which conveyor.sh sources beside this file
HISTORY=${STATE%/*}/history.json
LIMIT=${STATE%/*}/limit.jsonl     # the Claude weekly limit readings taken for the guard: {time, pct}
# The reading is the account's whose folder reading() sets CLAUDE_CONFIG_DIR to (ACCT's, else the default login's). It
# keeps and honours the account's 429 deadline in the machine's one folder the Board's reads use too: asked with none,
# every LIMIT_TTL whatever wait a 429 named, it kept the account refused for days, the Board's reads with it.
# shellcheck disable=SC2034 # read by lib/control.sh (reading()), which conveyor.sh sources beside this file
LIMIT_CMD=${CONVEYOR_LIMIT_CMD:-python3 $(printf %q "$HERE/../.claude/scripts/dashboard_limit.py") fetch '"$CLAUDE_CONFIG_DIR" "${XDG_CACHE_HOME:-$HOME/.cache}/conveyor/accounts"'}
# The Claude accounts of this host: the host file's accounts, each {name, configDir}, a Claude config folder already
# signed in on this host (CLAUDE_CONFIG_DIR=<folder> claude, then sign in). The control record's account (the
# builder's) and reviewAccount (a Claude reviewer's; none: the builder's) name one; none is the host's default login.
# ACCT and RACCT are the names in use: a card sets them once, as it starts, from the record the loop's guard read
# (pick waits a turn when the record's accounts changed since), so a change of the record reaches the cards started
# after it and never one in flight; the guard reads every account the next card will use (guardread). RACCT is set
# only when the reviewer is Claude as the card starts and its review account is another than ACCT: only then did the
# guard read it, so a card whose reviewer is changed to Claude while it runs reviews on its builder's account, which
# the guard read, never on a review account nobody read. Only the name is ever recorded, never the account's email.
ACCT=''; RACCT=''
acctdir() { # <name>: that account's folder (~/ or a relative path is under the user's home, as the Board reads it, so the
  # guard and a session in a card's worktree read the same folder); fails for a name the host file does not list
  jq -er --arg n "$1" --arg h "$HOME" 'first(.accounts // [] | .[] | objects | select(.name == $n) | .configDir | strings | select(. != ""))
    | if startswith("/") then . elif startswith("~/") then $h + .[1:] else $h + "/" + . end' "$HOST" 2>/dev/null
}
acctnames() { jq -c '[.accounts // [] | .[] | objects | .name | strings]' "$HOST" 2>/dev/null || echo '[]'; }
ctlacct() { jq -r '.account // ""' <<<"${1:-null}" 2>/dev/null; } # <the control record>: its account name, "" for the default
acctenv() { # <name or "">: the folder a session's CLAUDE_CONFIG_DIR is set to ("" for the default login), else why not
  [ -n "$1" ] || return 0
  acctdir "$1" || { echo "the account $1 this card started on is not in the host file's accounts ($HOST)"; return 1; }
}
# <folder from acctenv>: sets a session's CLAUDE_CONFIG_DIR to it; with none, the default login (~/.claude), so an
# inherited CLAUDE_CONFIG_DIR never runs the cards on an account the guard and the Board do not read for them.
# Every Claude session a card starts runs through it, so each runs with no auto memory: notes kept under
# ~/.claude/projects/ would carry from card to card (--setting-sources "" does not turn that off).
acctrun() { export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1; if [ -n "$1" ]; then export CLAUDE_CONFIG_DIR="$1"; else unset CLAUDE_CONFIG_DIR; fi; }
# What of the control record decides the accounts a card started on it uses: its account, reviewAccount and reviewer,
# and the seats it keeps for an issue (cards: a card of that issue runs on them).
acctkey() { jq -c '[.account, .reviewAccount, .reviewer, .cards]' <<<"${1:-null}" 2>/dev/null; }
# The accounts a card started on the control record uses, one name a line ("" for the default login): its builder's,
# and with a Claude reviewer its review's (reviewAccount, else the builder's).
cardaccts() { # <control record>
  local s; ctlacct "$1"
  s=$(seat reviewer "${1:-null}") && [ "$(jq -r .agent <<<"$s")" = claude ] && jq -r '.reviewAccount // .account // ""' <<<"${1:-null}" || :
}
# The guard's reading for the control record, {time, pct}: the highest of the readings of the accounts a card started
# on it uses (cardaccts), so an account at its limit holds back every card that would use it. Asked for (reading)
# with ask (with fresh: asked whatever the age of the last asking, reading fresh), else from the readings file alone
# (lastread). Nothing when none of them has a reading. The weekly limit is
# Claude's: an OpenCode or Codex builder runs on no Claude account, so its account is not read unless a fix or testFix
# seat runs on Claude (with a Codex reviewer and no Claude repair seat, none is, and Claude's limit holds no card back). Nor is the account of a role on an API route (subroles()): it is
# billed per token and has no usage limit, so with every role on one the loop asks for no reading before a pick.
# With SEATCARD set to an issue, the accounts of that issue's card, on the seats the record keeps for it (seat()):
# pick holds that card alone when one of them is at the guard (cardheld(), lib/pick.sh).
guardread() { # <control record> [ask | fresh]
  local a f=''; [ "${2:-}" != fresh ] || f=fresh
  subaccts "$1" | cut -d ' ' -f 2- | sort -u | while IFS= read -r a; do if [ -n "${2:-}" ]; then ACCT=$a reading $f; else ACCT=$a lastread; fi; done \
    | jq -cs 'max_by(.pct) // empty'
}
# The accounts of cardaccts() whose usage limit is read, each line as "<build|fix|review> <account>": the builder's (the
# first line) when the builder runs on Claude ("build"), or else when only a fix or testFix seat does ("fix": seat(); a
# repair runs on the builder's account and route, and builds nothing), and the reviewer's (the second line, only for a
# Claude reviewer), each while its role runs on the subscription login (subroles()).
subaccts() { # <control record>
  local a on b r; on=$'\n'$(subroles)$'\n'
  # The seats worked out once, in this shell: seat() keeps its answer here, so the subshells below (each seat's, and
  # cardaccts's) take it and start no jq of their own for it.
  seat builder "${1:-null}" > /dev/null 2>&1 || :
  b=$(for a in builder fix testFix; do seat "$a" "${1:-null}"; done 2>/dev/null | jq -r .agent 2>/dev/null)
  r=fix; [ "${b%%$'\n'*}" != claude ] || r=build; b=$'\n'$b$'\n'
  cardaccts "$1" | {
    IFS= read -r a; if [[ $b == *$'\n'claude$'\n'* && $on == *$'\n'builder$'\n'* ]]; then printf '%s %s\n' "$r" "$a"; fi
    if IFS= read -r a && [[ $on == *$'\n'reviewer$'\n'* ]]; then printf 'review %s\n' "$a"; fi
  }
}
# Each account guardread reads for the control record, for the Board's limit panel: [{account (null: the default
# login), uses (build, review: what a card started on the record runs on it), pct and readAt (its reading, as
# lastread gives it; null for none), email (the login of its folder on this machine, null when that names none)}].
# The email goes to the Board alone, in the snapshot: never into a record.
guardaccts() { # <control record>
  local a s f e r
  subaccts "$1" | while read -r s a; do
    # The default login's metadata is ~/.claude.json, not ~/.claude/.claude.json (dashboard_limit.py config_folders()).
    if [ -n "$a" ]; then f=$(acctdir "$a")/.claude.json || f=''; else f=$HOME/.claude.json; fi
    [ "$f" != "$HOME/.claude/.claude.json" ] || f=$HOME/.claude.json
    e=''; [ -z "$f" ] || e=$(jq -r '.oauthAccount.emailAddress | strings' "$f" 2>/dev/null) || e=''
    r=$(ACCT=$a lastread); [ -n "$r" ] || r=null
    jq -cn --arg a "$a" --arg s "$s" --arg e "$e" --argjson r "$r" \
      '{account: (if $a == "" then null else $a end), uses: [$s], pct: $r.pct, readAt: $r.time, email: (if $e == "" then null else $e end)}'
  done | jq -cs 'group_by(.account) | map(.[0] + {uses: map(.uses[])})'
}
# The seed's cap, for a control record that sets its cap null (`control cap off`, the Board's Default): six cards at
# once, the defaults' cap (CTL0, lib/control.sh).
# shellcheck disable=SC2034 # read by lib/control.sh, lib/run.sh and lib/views.sh, which conveyor.sh sources beside this file
CAP0=6
# The efforts each agent takes: claude --effort, codex's model_reasoning_effort (a Codex reviewer's and builder's),
# and opencode's --variant for the reviewer and the judge (each provider's own: a model that has no such variant runs
# without one). The OpenCode builder is given none (seatnow(), and `control model` and the Board's settings offer it none).
EFFORTS='{"claude":["low","medium","high","xhigh","max"],"codex":["minimal","low","medium","high","xhigh"],"opencode":["minimal","low","medium","high","xhigh","max"]}'
# The pack's own models for a seat, by the program that runs them, from its models.allowed: the seed's (the first
# of them) and the program of a seat the control record names by its model alone (no cli). They limit nothing the
# record names with its CLI (seatnow()): any CLI installed here runs any model named, listed by it or not. The builder's
# are Claude's, OpenCode's (opencode:<provider>/<model>) and the Codex models listed for the build (codex-builder); the
# reviewer's are Codex's, the Claude models listed for the review (a backup when Codex usage runs out) and the OpenCode
# ones (opencode:<provider>/<model>, OpenCode's provider/model). A reviewer's model is OpenCode's by that name alone:
# one listed under another program is not that program's, and one with no provider is no model.
OKMODELS='def okmodels($s): def oc: startswith("opencode:"); . as $a | if $s == "builder" then {claude: ($a.claude // [] | map(strings)), opencode: ($a.opencode // [] | map(strings | select(test("^opencode:[^/]+/.")))),
    codex: ($a["codex-builder"] // [] | map(strings))}
  else {codex: ($a.codex // [] | map(strings | select(oc | not))), claude: ($a["claude-reviewer"] // [] | map(strings | select(oc | not))),
    opencode: ($a.opencode // [] | map(strings | select(test("^opencode:[^/[:space:]]+/[^[:space:]]+$"))))} end;
  def seed($s): {model: ([okmodels($s)[][]] | first), effort: "medium"};'
# The models.allowed of a pack that sets none (modelsallowed()): Claude's are this list, as Claude Code reports no
# list of the models an account can use; Codex's are the ones Codex reports (climodels()), none when it is not
# installed, and these only when an installed Codex has reported none. A pack that sets a codex list with a model in it
# has the ones Codex reports added to it.
# shellcheck disable=SC2034 # read by lib/control.sh and lib/setup.sh, which conveyor.sh sources beside this file
MODELS0='{"claude":["claude-opus-5-5","claude-fable-5-2","claude-sonnet-5-5","claude-haiku-5-5"],"codex":["gpt-6.2-sol","gpt-6.2-astra","gpt-6.1-terra","gpt-6.1-sol","gpt-6-astra","gpt-6-sol","gpt-6-luna","gpt-5.6-sol","gpt-5.6-terra","gpt-5.6-luna","gpt-daybreak-blue-latest"],"claude-reviewer":["claude-opus-5-5","claude-sonnet-5-5","claude-fable-5-2"]}'
# The CLIs a seat can run, and how each lists the models it has registered on this host (climodels()); a CLI that
# offers no list (Claude Code's --model takes an alias or a full name, and nothing lists them) has null for its models.
CLINAMES='claude codex opencode'
# The host's report (hostclis()): {at: when it was read, clis: {<cli>: its models, or null}, seen: [<cli>...], px},
# one key of clis for each CLI that was installed then; seen, each CLI a report of this host has listed (seatwait());
# px, true when Codex's list was read with the Codex proxy on (pxon()), so it is read again once a role leaves the proxy. Read again once it is CLI_TTL seconds old by `watch`'s slower timer (github()), by a
# snapshot with no `watch` feed (snapshot()) and before a seat starts (seatready()), by `conveyor.sh clis`, and for one CLI by `control` when a seat is set to it.
CLIS=${STATE%/*}/clis.json
CLI_TTL=600
# Why a seat {model, agent} cannot start on this host, from the host's report $h ({<cli>: models or null}, the CLIs
# installed): its CLI is not installed. A model the CLI does not list is no reason: a name typed in (the Board's
# Other…) is given to the CLI, and one it cannot run fails in the card, as any model the CLI refuses does. null when
# it can start. bare is the model as its CLI names it (an OpenCode model without the opencode: mark seatnow() gives it).
MISSING='def bare: if .agent == "opencode" then .model | ltrimstr("opencode:") else .model end;
  def missing($h): . as $s | if $s.agent == null then null elif ($h | has($s.agent) | not) then "\($s.agent) is not installed on this host (not on PATH)" else null end;'
SAMPLES=${STATE%/*}/samples.jsonl # the loop's and the host's samples, one a minute (README.md)
PUSHED=${STATE%/*}/pushed         # the last push that worked: "<commit> <remote> <branch>"
# Any push's record (Push now's and Push landed's too), from its start to its end, with its stage and its log too:
# push() and pushing(), lib/push.sh.
PUSHING=${STATE%/*}/pushing       # the push in progress: {pid, since, sha}, while the loop's push job runs
# shellcheck disable=SC2034 # read by lib/push.sh and lib/views.sh, which conveyor.sh sources beside this file
LANDPR=${STATE%/*}/landingpr.json # the pull request of Land as pr and its last merge (prstate(), lib/push.sh)
MAINTEST=${STATE%/*}/maintest.json # the whole test on main (maintest()): its last run, its last pass and what fails now
# shellcheck disable=SC2034 # read by lib/mainred.sh and lib/views.sh, which conveyor.sh sources beside this file
MACHINEHOLD=${STATE%/*}/machinehold.json # the machine hold (machinehold(), lib/mainred.sh), while one stands
# `watch` runs each snapshot with this set to a folder where a slower timer keeps GitHub's answers (`github`):
# the open issues, when the awaiting-deploy labels were added, and whether gh is signed in. Read from there, a slow
# GitHub never holds up a card's snapshot; nor does a weekly limit reading, which such a snapshot never asks for.
GITHUB=${CONVEYOR_GITHUB:-}
# The loop asks GitHub for the open issues before each pick, never under the records' lock (every card's line waits
# on that lock), and keeps the answer here; the minute's sample takes it while it is younger than SAMPLE.
ISSUES=${STATE%/*}/issues.json
# shellcheck disable=SC2034 # read by lib/issues.sh, lib/run.sh, lib/records.sh and lib/snapshot.sh, sourced beside this file
FIELDS=number,title,body,labels,milestone,createdAt,authorAssociation # what a pick, the sample and the snapshot read of an open issue
# An issue opened from inside the project: by the repository's owner, a member of its organization or a collaborator
# (GitHub's authorAssociation, which openissues() adds). Any other is opened by someone outside the project: anyone
# with a GitHub account can open one, and its text would reach a card session with write tools, so it starts held
# (adopted(), lib/control.sh) whatever the rule "Queue new issues" says, until the owner releases it. One with no
# authorAssociation (closed between the two questions openissues asks) is not inside.
# shellcheck disable=SC2034 # read by lib/pick.sh, lib/control.sh and lib/snapshot.sh, sourced beside this file
INSIDE='def inside: .authorAssociation | IN("OWNER", "MEMBER", "COLLABORATOR");'
# The core of the rules every build, fix, rebase and test-fix session is given: its flags load no CLAUDE.md
# and no .claude/rules/, so this text is how a card knows them (cardrules() adds the pack's). A missing or empty file
# blocks the card.
RULES=${CONVEYOR_CARD_RULES:-$HERE/rules/card-core.md}
# Another repo sets these two: the core rules and the generic card hooks (cardsettings() adds the pack's). The only
# label that keeps an issue off the belt is the pack's built label (no skip list); backlog, dormant and ux-change are for information only: a hold of the control record keeps an issue off.
# `run --only 3838,3840` limits a run to the listed issue numbers: the set of issues it builds (at run below).
ONLY=''                                   # that list as JSON, '' for a run with no --only
CARD_SETTINGS=${CONVEYOR_CARD_SETTINGS:-$HERE/card-settings.json}
# The guard plugin every OpenCode session loads (ocready(), README.md OpenCode builder), with guard.sh beside it.
OC_GUARD=${CONVEYOR_OPENCODE_GUARD:-$HERE/opencode/guard.mjs}
# The guard hook every Codex build, fix and rebase session runs (cxready(), README.md Codex builder).
CX_GUARD=${CONVEYOR_CODEX_GUARD:-$HERE/codex/guard.mjs}
MAX_REVIEWS=3 # the review rule in README.md
# shellcheck disable=SC2034 # read by lib/card.sh, lib/followups.sh and lib/prompts.sh, which conveyor.sh sources beside this file
MAX_DEPTH=2   # the follow-up depth cap (fudepth(), lib/followups.sh), so the longest chain a pick reads: parent, its follow-up, that one's follow-up
