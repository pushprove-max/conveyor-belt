# SPDX-License-Identifier: Apache-2.0
# What stands in for the issue of a branch that names none: its first commit's subject as the title, and its commit
# messages as the body, so the reviewer has something to hold the change against and the owner's
# `Visible change approved:` line has a place to be.
branchissue() { # <branch> <tip>
  jq -cn --arg t "$(git log --reverse --format=%s "refs/heads/$BRANCH..$2" | head -n 1)" --arg b "$1" --rawfile m <(git log --reverse --format='%B' "refs/heads/$BRANCH..$2") \
    '{number: 0, title: ($t[0:200]), body: "No issue: this card lands the change of branch \($b) against main. The commit messages of the branch say what the change is for:\n\n\($m | sub("\n+$"; ""))", labels: [], milestone: null}'
}

# Under the lock: the picked line of a land-branch card, with main's commit the branch was weighed against (base: Needs
# you reads from it what the card was picked to land, branchon(), lib/snapshot.sh). Prints the card id. An issue with
# an open card is refused: that card (in flight in the loop, or stopped mid-card) is building the same issue.
pickbranch() { # <branch> <issue> <title> <main's commit>
  local card l
  check || return 1
  [ "$2" = 0 ] || ! stdb ask issue cards "$2" | jq -es --argjson n "$2" 'map(select(.issue == $n)) | group_by(.card) | any(all(.step | IN("landed", "closed", "blocked") | not))' >/dev/null \
    || { echo "conveyor: issue #$2 has a card that is still open; nothing recorded" >&2; return 1; }
  # A card id is its second, its project and its issue: a second landing in the same second (every branch that names no issue is
  # issue 0) waits for the next one, so no two cards share their lines.
  while card="c$(date -u +%Y%m%dT%H%M%S)-$CTAG-$2"; [ -n "$(stdb ask card "$card")" ]; do sleep 1; done
  l=$(line "$card" "$2" picked ok "$(jq -cn --arg t "${3:0:200}" --arg b "$1" --arg m "$4" '{title:$t,branch:$b,base:$m}')") && append "$l" && echo "$card"
}

# One branch landed as one card (the rule is in README.md). Everything that can be refused is refused before
# the picked line, so a refusal leaves no card. The tip is read once: the card lands that commit's change, whatever
# the branch gains meanwhile. The card's issue is the one of a branch named as the engine names a card of this
# project (c<time>-<project>-<issue>), else 0: a number elsewhere in a name (hand/snapexec-290) is no issue, as the
# engine would review the branch against that issue and could close it.
landbranch() { # <branch>
  local br=$1 tip n title c end m
  # A branch name only: revision syntax (fast-lane~0, @{-1}) names no branch.
  [ "$br" != "$BRANCH" ] && git check-ref-format "refs/heads/$br" && tip=$(git rev-parse -q --verify "refs/heads/$br^{commit}") \
    || { echo "conveyor: no branch $br to land" >&2; return 2; }
  # main is read once too: the checks below and the picked line's base are of the same commit.
  m=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") || { echo "conveyor: no branch $BRANCH to land on" >&2; return 2; }
  # The fast lane's change lands on the owner's command alone, under whatever name it is asked for: its branch, or
  # any branch that holds the change of any of its tips (lanetips, lanein), the lane's own branch renamed included.
  if [ "$br" = "$LANEBR" ] || { while read -r n; do lanein "$tip" "$n" && break; done < <(lanetips | sort -u); [ -n "$n" ]; }; then
    owneronly land || return 2
  fi
  # Its stdout alone: the first line is the tree id, so a warning on stderr must not come ahead of it.
  end=$(git merge-tree --write-tree "$m" "$tip") \
    || { echo "conveyor: branch $br does not merge into main as it stands; rebase it on main first. Nothing recorded: $(tail -n +2 <<<"$end" | head -c 600)" >&2; return 1; }
  [ "$(head -n 1 <<<"$end")" != "$(git rev-parse "$m^{tree}")" ] || { echo "conveyor: nothing to land: branch $br holds no change against main"; return 0; }
  n=0; ! [[ $br =~ ^c[0-9]{8}T[0-9]{6}-"$CTAG"-([1-9][0-9]{0,8})$ ]] || n=${BASH_REMATCH[1]}
  if [ "$n" = 0 ]; then title=$(git log --reverse --format=%s "refs/heads/$BRANCH..$tip" | head -n 1)
  else title=$(timeout 60 gh issue view "$n" --json title | jq -er .title) \
    || { echo "conveyor: branch $br lands as issue #$n, which cannot be read; nothing recorded" >&2; return 1; }
  fi
  c=$(codexready) || { echo "conveyor: $c; nothing recorded" >&2; return 1; }
  c=$(locked pickbranch "$br" "$n" "$title" "$m") || return 1
  # Each process the card starts carries its mark, as a card of the loop's does (cardrun(), lib/run.sh): a review left
  # running when this shell is gone is ended by retry or shut before its worktree is taken (leftin()).
  CONVEYOR_CARDRUN=$c card "$c" "$n" "$br" "$tip"
  end=$(jq -rs --arg c "$c" 'map(select(.card == $c and (.step | IN("landed", "closed", "blocked")))) | last | select(.) | "\(.step) \(.sha) \(.reason | gsub("\n"; "; "))"' < <(stdb ask card "$c"))
  echo "conveyor: card $c, branch $br: ${end:-no closing line}"
  [[ $end == landed\ * ]]
}

# The fast lane (plan section 11b): the owner's own linked worktree, on branch fast-lane, in the host file's lanesDir
# (a path starting ~/ is under the home folder; none: the folder the checkout is in), named <checkout>-fast-lane.
# `lane fast create` makes it; `lane fast review` is a preview of its change by the card reviewer, with the
# repeat-class stop; `lane fast land` lands it as one card (land-branch); `lane fast reset [--drop <sha>]` sets it to
# main's head once that card has landed. The lane is the owner's alone: land and reset refuse in a Foreman session
# and inside a card. It never pushes: the lane's own config (a worktree's own, read after every other config file)
# allows no transport (protocol.allow and each protocol.<name>.allow set to never), so no hook skipped by --no-verify,
# URL rewrite, remote or push URL, made before or after create, gets a push out. A command's GIT_ALLOW_PROTOCOL
# outranks those, so the same config also rewrites every URL, push URL included, to a transport no git has (LANEURL:
# url.<it>.insteadOf and pushInsteadOf the empty prefix), and a rewrite longer than the empty prefix still wins, so it
# also sets push.gpgSign to a value that is no setting (LANESIGN): git push and send-pack read it before their options,
# --no-signed included, and stop. A command's -c or GIT_CONFIG_* outranks any config
# file: the plugin's git guard (.claude/hooks/git-safety.sh, before every Bash call of a session) refuses any push in
# the lane.
# A fetch in the lane is refused too; main's checkout fetches for it (reset does).
LANEBR=fast-lane
LANEPROTO='file git ssh http https ext'
LANEURL=conveyor-fast-lane-refuses-push::
LANESIGN=conveyor-fast-lane-refuses-push
# A branch at <tip> holds the lane's change when its tree holds any part of it that main's does not: a hunk of the
# lane's change against main (no context; a binary or mode change whole) applies in reverse to <tip>'s tree and not to
# main's. So the lane's commits under any name or with more on top, a cherry-pick, the change squashed, or mixed with
# other changes in one commit or one file, all hold it. Anything that cannot be checked counts as holding it.
lanein() { # <tip> <a lane tip>
  local lt=$2 m=refs/heads/$BRANCH d p
  [ -n "$(git rev-list -1 "$lt" "^$m" 2>/dev/null)" ] || return 1
  d=$(mktemp -d) || return 0
  git diff -U0 --binary --no-renames "$m...$lt" > "$d/all" \
    && awk -v d="$d" 'function flush() { if (h != "" && !s) { n++; printf "%s", h > (d "/p." n); close(d "/p." n) } }
      /^diff --git /{flush(); h=$0 "\n"; hh=h; s=0; next}
      /^@@ /{if (f) close(f); n++; f=d "/p." n; printf "%s", hh > f; s=1}
      s {print > f; next}
      {h=h $0 "\n"}
      /^new file mode / {next}
      /^\+\+\+ b\// && hh ~ /\n--- \/dev\/null\n$/ {sub(/--- \/dev\/null\n$/, "--- a/" substr($0, 7) "\n", hh)}
      {hh=hh $0 "\n"}
      END {flush()}' "$d/all" \
    && GIT_INDEX_FILE=$d/tip git read-tree "$1" && GIT_INDEX_FILE=$d/main git read-tree "$m" || { rm -rf "$d"; return 0; }
  for p in "$d"/p.*; do
    [ -e "$p" ] || continue
    GIT_INDEX_FILE=$d/tip git apply --cached --check -R --unidiff-zero "$p" 2>/dev/null \
      && ! GIT_INDEX_FILE=$d/main git apply --cached --check -R --unidiff-zero "$p" 2>/dev/null && { rm -rf "$d"; return 0; }
  done
  rm -rf "$d"; return 1
}
# The lane's tips, one a line: its branch fast-lane, and the head of every linked worktree that is a lane whatever
# branch it is on (a renamed branch, a detached head) or wherever it was moved: the one at the lane's folder, and any
# with the lane's push refusal (protocol.allow never) in its own config.
lanetips() {
  local l p h
  git rev-parse -q --verify "refs/heads/$LANEBR^{commit}"
  l=$(lanepath 2>/dev/null && cd "$LANE" 2>/dev/null && pwd -P)
  while IFS= read -r p && IFS= read -r h; do
    [ "$(cd "${p#worktree }" 2>/dev/null && pwd -P)" != "$MAIN" ] || continue
    { [ -n "$l" ] && [ "$(cd "${p#worktree }" 2>/dev/null && pwd -P)" = "$l" ]; } \
      || [ "$(git -C "${p#worktree }" config --worktree --get protocol.allow 2>/dev/null)" = never ] && echo "${h#HEAD }"
  done < <(git worktree list --porcelain | grep -E '^(worktree|HEAD) ')
}
lanepath() {
  local d=''
  [ ! -e "$HOST" ] || d=$(jq -r '.lanesDir // "" | strings' "$HOST") || { echo "conveyor: the host file $HOST cannot be read: the lane cannot be found" >&2; return 2; }
  [[ $d != "~/"* ]] || d=$HOME/${d#"~/"}
  # MAIN's folder and name (its trailing slashes off) by the shell's own expansions, as dirname and basename give them.
  local m=${MAIN%"${MAIN##*[!/]}"}
  [ -n "$d" ] || case $m in */*) d=${m%/*}; d=${d:-/} ;; *) d=. ;; esac
  LANE=$d/${m##*/}-fast-lane
}
# The lane is there: a linked worktree of this repository at its folder, on its branch fast-lane (LBR).
lanefind() {
  lanepath || return 2
  [ "$(git -C "$LANE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
    && [ "$(git -C "$LANE" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$LANE" && pwd -P)" ] \
    || { echo "conveyor: no fast lane of $MAIN at $LANE: make it with conveyor.sh lane fast create" >&2; return 2; }
  LBR=$(git -C "$LANE" symbolic-ref -q --short HEAD) && [ "$LBR" = "$LANEBR" ] \
    || { echo "conveyor: the lane $LANE is on ${LBR:-no branch}, not $LANEBR: switch it back to $LANEBR" >&2; return 2; }
}
# The protocols the lane's push refusal names: every built-in transport, and any other a config file names.
laneprotos() {
  { printf '%s\n' $LANEPROTO; git -C "$LANE" config --name-only --get-regexp '^protocol\..+\.allow$' | sed 's/^protocol\.//; s/\.allow$//'; } | sort -u
}
# Its push refusal is in force: no transport is allowed in the lane.
lanesealed() {
  local p
  [ "$(git -C "$LANE" config --get protocol.allow)" = never ] || return 1
  for p in $(laneprotos); do [ "$(git -C "$LANE" config --get "protocol.$p.allow")" = never ] || return 1; done
  git -C "$LANE" config --get "url.$LANEURL.insteadOf" '^$' >/dev/null && git -C "$LANE" config --get "url.$LANEURL.pushInsteadOf" '^$' >/dev/null \
    && [ "$(git -C "$LANE" config --get push.gpgSign)" = "$LANESIGN" ]
}
# The lane as a command needs it: there, with its push refusal, and with no tracked change.
lanehere() { # <what to do once the change is committed>
  lanefind || return 2
  lanesealed || { echo "conveyor: the lane $LANE could push: run conveyor.sh lane fast create to set its push refusal" >&2; return 2; }
  [ -z "$(git -C "$LANE" status --porcelain --untracked-files=no)" ] || { echo "conveyor: the lane has a tracked change: commit it, then $1" >&2; return 2; }
}
# Land and reset run on the owner's command only: never in a Foreman session (the launcher's CONVEYOR_FOREMAN=1, or
# the session /conveyor-belt:foreman marked: Claude Code gives a session's commands its id, CLAUDE_CODE_SESSION_ID,
# and the Foreman's mark, foreman/lib.sh MARK, holds the marked one's), never inside a card (its sessions have
# CONVEYOR_CARD set, session(); or the command is called from the cards folder).
owneronly() { # <command>
  local w='' c s=''
  c=$(cd "$CARDS" 2>/dev/null && pwd -P)
  read -r s _ 2>/dev/null < "${XDG_STATE_HOME:-$HOME/.local/state}/conveyor/foreman/session"
  [ "${CONVEYOR_FOREMAN:-}" != 1 ] && { [ -z "$s" ] || [ "${CLAUDE_CODE_SESSION_ID:-}" != "$s" ]; } || w='a Foreman session'
  { [ -z "${CONVEYOR_CARD:-}" ] && { [ -z "$c" ] || [[ $(cd "$CALLED" && pwd -P)/ != "$c"/* ]]; }; } || w='a card'
  [ -z "$w" ] || { echo "conveyor: the fast lane is the owner's alone: lane fast $1 refuses inside $w" >&2; return 2; }
}
# The push refusal, set (again) on the lane in its own config; a lane that is already there gets it too.
laneseal() {
  local p
  git config extensions.worktreeConfig true && git -C "$LANE" config --worktree protocol.allow never || return 1
  for p in $(laneprotos); do git -C "$LANE" config --worktree "protocol.$p.allow" never || return 1; done
  git -C "$LANE" config --worktree --replace-all "url.$LANEURL.insteadOf" '' && git -C "$LANE" config --worktree --replace-all "url.$LANEURL.pushInsteadOf" '' \
    && git -C "$LANE" config --worktree push.gpgSign "$LANESIGN" || return 1
  lanesealed
}
# The lane's folder, written into the host file for the Board, which reads each record's lanes from there: the
# lanes.fast.worktree of this checkout's record, the record whose main is this checkout. Nothing else names a
# checkout's record: a record's repo is a name to show, and a checkout's folder may bear another project's. Paths
# are compared as the folders they name (test -ef), so a record that spells its checkout another way (a trailing /.,
# a link) is still this checkout's; each main is read whole, NUL-ended, so one with a tab or a newline in it is
# neither cut short into another path nor passed over. The file
# is read and replaced under one lock ($HOST.lock), so two lanes made at once both stay written. With no host
# file nothing is written; with one that has no such record, nothing is written and the line says what the Board
# needs. A file that cannot be written fails. Twin of lanenote in lanes/research.sh.
lanenote() {
  [ -d "$MAIN" ] || return 1
  [ -e "$HOST" ] || return 0
  ( flock 9 || exit 1
    mapfile -d '' a < <(jq -j '.records | arrays | to_entries[] | select(.value | objects | .main | strings | test("\u0000") | not) | "\(.key)\u0000\(.value.main)\u0000"' "$HOST")
    wait $! || exit 1
    i=
    for ((n = 0; n < ${#a[@]}; n += 2)); do
      m=${a[n+1]}
      [ "$m" = "$MAIN" ] || { [[ $m == /* ]] && [ "$m" -ef "$MAIN" ]; } || continue
      i=${a[n]}; break
    done
    [ -n "$i" ] || exit 3
    jq --argjson i "$i" --arg w "$LANE" '.records[$i].lanes.fast.worktree = $w' "$HOST" > "$HOST.lane.$$" && [ -s "$HOST.lane.$$" ] && mv "$HOST.lane.$$" "$HOST"
  ) 9>>"$HOST.lock"
  case $? in
    0) ;;
    3) echo "conveyor: the host file $HOST has no record of this checkout: the Board shows this lane once a record's lanes.fast.worktree names $LANE" >&2 ;;
    *) rm -f "$HOST.lane.$$"; echo "conveyor: the lane's folder $LANE could not be written into the host file $HOST: the Board does not show this lane" >&2; return 1 ;;
  esac
}
lanecreate() {
  lanepath || return 2
  if [ -e "$LANE" ] || [ -L "$LANE" ]; then
    lanefind || { echo "conveyor: $LANE is there and is not this checkout's fast lane; nothing changed" >&2; return 2; }
    laneseal || { echo "conveyor: the lane $LANE is there, but its push refusal could not be set" >&2; return 1; }
    lanenote || return 1
    echo "conveyor: the fast lane is already at $LANE; it never pushes"; return 0
  fi
  if git show-ref -q --verify "refs/heads/$LANEBR"; then git worktree add -q "$LANE" "$LANEBR"
  else git worktree add -q -b "$LANEBR" "$LANE" "refs/heads/$BRANCH"; fi || return 1
  laneseal || { git worktree remove --force "$LANE"; echo "conveyor: the lane's push refusal could not be set up; the lane is removed" >&2; return 1; }
  lanenote || return 1
  echo "conveyor: made the fast lane $LANE on branch $LANEBR; it never pushes: conveyor.sh lane fast land lands its change"
}
laneland() { owneronly land && lanehere land || return 2; landbranch "$LBR"; }
# The preview: the card reviewer (the control record's reviewer seat, the card review's instructions) reviews the
# lane's tip as a card's change, in a worktree of its own made from main, and its reply is printed. A preview never
# stands in for the card's review: land reads nothing it writes. Exit 0 answered, 1 the review failed, 2 refused,
# 3 CLASS STOP (classes()).
PREVIEW="This review is a preview of the owner's fast lane: nothing lands on it. After the proof of each [P0], [P1] or
[P2] finding, end its line with \` class: <the kind of mistake in a few words, not this one case>\`."
lanereview() {
  local sha base rnd d wt rec earlier out rc rv=$REVIEW
  lanehere review || return 2
  yesrule || rv=$REVIEWOFF
  sha=$(git -C "$LANE" rev-parse HEAD)
  base=$(git merge-base "refs/heads/$BRANCH" "$sha") || { echo "conveyor: the lane shares no history with $BRANCH" >&2; return 2; }
  rnd=$(git diff "$base" "$sha" | git patch-id --verbatim | cut -d' ' -f1); rnd=${rnd:-$sha}
  out=$(codexready) || { echo "conveyor: $out" >&2; return 1; }
  rec=$(git -C "$LANE" rev-parse --absolute-git-dir)/conveyor-classes
  earlier=$(classes earlier "$rec" "$rnd") || return 2
  d=$(mktemp -d) || return 1; wt=$d/preview
  if ! out=$(git worktree add -q --detach "$wt" "refs/heads/$BRANCH" 2>&1 && git -C "$wt" merge -q --squash "$sha" 2>&1); then
    rc=2; out="conveyor: the lane does not merge into $BRANCH as it stands; rebase it on $BRANCH first: ${out:0:400}"
  elif git -C "$wt" diff --cached --quiet; then rc=2; out="conveyor: nothing to review: the lane holds no change against $BRANCH"
  else
    out=$(reviewed "$wt" "$(branchissue "$LBR" "$sha" | jq -r '"# Issue: \(.title)\n\n\(.body)"')" "$rv"$'\n'"$PREVIEW${earlier:+
Classes earlier rounds of this change found; give a finding of the same kind of mistake this exact class text:
$earlier}"); rc=$?
    if [ $rc = 0 ]; then out=''; cat "$wt.review"; classes record "$rec" "$rnd" "$wt.review" <(grep -Ev "$NOTFINDING" "$wt.review"); rc=$?
    else out="conveyor: the review failed: $out"; fi
  fi
  git worktree remove --force "$wt" 2>/dev/null; rm -rf "$d"
  [ -z "$out" ] || echo "$out" >&2
  return $rc
}
# classes earlier <record> <round> | record <record> <round> <review> <findings> -- the repeat-class stop. The record,
# in the lane's git folder, holds "<round> <stage> <group> <class|file> <value>" rows (tab-separated) for the lane's
# change since its last reset (lanereset deletes it). A round is the change's patch-id against main, whitespace kept
# (--verbatim: a fix of indentation is a new round), so a rebase onto a newer main that changes nothing else is the
# same round; rounds of one change replace each other: a rerun is not a fix round. A stage is seen, whole (CLASS
# REPEAT ordered the whole-class fix) or stop. A P0-P2 finding, a line of
# <findings> (the review's lines that are findings, NOTFINDING: never an UNPROVEN or NEW CARD line), is a repeat when
# its class text or a file it cites matches an earlier round's: the class is the reviewer's judgment, and the file
# catches a reworded class. Only a class match stops the loop (CLASS STOP, exit 3). The record is replaced whole under
# a lock; a row it cannot read, or a blocking finding with neither a class nor a file, is refused (exit 2) before
# anything is saved. To start the lane's history over, delete the record file.
classes() {
  python3 -I - "$@" <<'PY'
import fcntl, os, re, sys
mode, rec, rnd = sys.argv[1:4]
def die(msg):
    print(f"conveyor: {msg}", file=sys.stderr)
    sys.exit(2)
norm = lambda c: " ".join(c.lower().split()).strip(" .;:-`*")
def load():
    rows = []
    if os.path.exists(rec):
        for n, l in enumerate(open(rec, encoding="utf-8"), 1):
            r = l.rstrip("\n").split("\t")
            if len(r) != 5 or not r[0] or r[1] not in ("seen", "whole", "stop") or not r[2] or r[3] not in ("class", "file") or not r[4]:
                die(f"{rec} line {n} is not a class row: {l.strip()!r}; delete the file to start the lane's history over")
            rows.append(r)
    return rows
if mode == "earlier":
    print("\n".join(f"- {v}" for v in dict.fromkeys(r[4] for r in load() if r[0] != rnd and r[3] == "class")))
    sys.exit(0)
lines = open(sys.argv[4], encoding="utf-8").read().strip().splitlines()
if not lines or lines[-1].strip() not in ("VERDICT: GO", "VERDICT: NO-GO"):
    die("the reviewer's last line is not VERDICT: GO or VERDICT: NO-GO, so its findings cannot be counted: review again")
found = []
for l in open(sys.argv[5], encoding="utf-8").read().splitlines():
    levels = re.findall(r"(?:^|[^A-Za-z0-9])P([0-3])(?=[^0-9]|$)", l)
    if not levels or min(levels) > "2":
        continue
    m = re.search(r"class:\s*(.*)$", l, re.I)
    keys = {("class", norm(m.group(1)))} if m and norm(m.group(1)) else set()
    keys |= {("file", f) for f in re.findall(r"([A-Za-z0-9_./-]+\.[A-Za-z0-9]+):[0-9]+", l)}
    if not keys:
        die(f"this blocking finding names neither a class nor a file:line, so a repeat of it cannot be seen: {l.strip()}")
    found.append((l.strip(), keys))
with open(rec + ".lock", "a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    rows = load()
    mine = [r for r in rows if r[0] != rnd]
    out, stop = [], False
    for i, (line, keys) in enumerate(found):
        hit = [r for r in mine if (r[3], r[4]) in keys]
        gids = {r[2] for r in hit}
        # A group is every key of the findings a match joins, so a class reworded in one round and named again in the
        # next is still one class.
        group = [r for r in mine if r[2] in gids]
        what = ", ".join(sorted({f"{r[3]} '{r[4]}'" for r in hit}))
        # Only the reviewer's own class text stops the loop: a shared file alone may be two unrelated findings, so it
        # orders the whole-class round again but never asks the owner.
        if any(r[1] != "seen" for r in group) and any(r[3] == "class" for r in hit):
            stage, stop = "stop", True
            print(f"CLASS STOP: {what} is back after the round that fixed the whole class ({line}). Stop the loop and ask the owner: the design is wrong, not the patch.")
        elif group:
            stage = "whole"
            print(f"CLASS REPEAT: {what} was found and patched in an earlier round and is back ({line}). Do not patch this case alone. The next fix round has one job: one rule that covers every shape of this class, and one test that lists the shapes.")
        else:
            stage = "seen"
        gid = min(gids) if gids else f"{rnd[:12]}.{i}"
        out += [(rnd, stage, gid, k, v) for k, v in sorted(keys | {(r[3], r[4]) for r in group})]
    if found:
        print("Fix siblings: for each finding, search for every other form of the same mistake and fix them all in this round, not only the case named.")
    tmp = f"{rec}.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        for r in mine + out:
            f.write("\t".join(r) + "\n")
    os.replace(tmp, rec)
sys.exit(3 if stop else 0)
PY
}
# Once the lane's card has landed: the lane's branch and working tree set to main's head, refs/heads/<default branch>
# of main's checkout (after a fetch of the pack's remote when it is set and reachable; it says which head it used).
# Refused (exit 2), changing nothing, when the lane has a commit main does not hold that is not patch-equivalent to
# one on main (git cherry), unless --drop names the lane's exact tip: a commit that landed after a rebase with
# conflicts is not patch-equivalent, and --drop is how the owner says "this tip has landed". The old tip is saved as
# refs/lane-reset/<UTC time> first, so the reset can be undone. Untracked files are left alone.
lanereset() { # [--drop <sha>]
  local drop=${2-} old new fetched="no remote $REMOTE is set" saved t n c x unl=() eq=()
  local -A same=()
  owneronly reset && lanehere 'land it' || return 2
  if git remote get-url "$REMOTE" >/dev/null 2>&1; then
    if GIT_TERMINAL_PROMPT=0 timeout 60 git fetch -q "$REMOTE" </dev/null >/dev/null 2>&1; then fetched="after a fetch of $REMOTE"
    else fetched="$REMOTE was not reachable, so no fetch"; fi
  fi
  new=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}") || { echo "conveyor: $MAIN has no refs/heads/$BRANCH" >&2; return 2; }
  echo "main's head: $new (refs/heads/$BRANCH of $MAIN, $fetched)"
  if t=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") && ! git merge-base --is-ancestor "$t" "$new"; then
    echo "note: $REMOTE's $BRANCH $t has commits main's checkout does not; the lane is set to main's checkout's head"
  fi
  old=$(git -C "$LANE" rev-parse HEAD)
  # --drop takes the tip as a commit id, never a name like HEAD or the branch that always resolves to it.
  if [ -n "$drop" ]; then
    [[ $drop =~ ^[0-9a-f]{7,64}$ ]] && [ "$(git -C "$LANE" rev-parse -q --verify "$drop^{commit}" 2>/dev/null)" = "$old" ] \
      || { echo "conveyor: --drop $drop does not name the lane's tip $old: --drop takes the lane's exact tip, as a commit id" >&2; return 2; }
  fi
  if [ "$old" = "$new" ]; then echo "the lane ($LBR) is already at main's head $new: nothing to do"; return 0; fi
  # The lane's commits main does not hold; git cherry marks the patch-equivalent ones '-'. A merge commit, which git
  # cherry does not list, counts as not on main.
  while read -r c x; do [ "$c" != - ] || same[$x]=1; done < <(git -C "$LANE" cherry "$new" "$old")
  while read -r c; do
    if [ -n "${same[$c]-}" ]; then eq+=("$c"); else unl+=("$c"); fi
  done < <(git -C "$LANE" rev-list --reverse "$new..$old")
  if [ ${#unl[@]} -gt 0 ] && [ -z "$drop" ]; then
    { echo "conveyor: the lane has commits main does not hold and that are not patch-equivalent to one on main:"
      for c in "${unl[@]}"; do git -C "$LANE" log -1 --format='  %H %s' "$c"; done
      echo "If the lane's tip has landed (after a rebase with conflicts, say), run: conveyor.sh lane fast reset --drop $old"; } >&2
    return 2
  fi
  t=$(date -u +%Y%m%dT%H%M%SZ); saved=refs/lane-reset/$t; n=1
  until git update-ref "$saved" "$old" "" 2>/dev/null; do
    n=$((n+1)); [ $n -le 20 ] || { echo "conveyor: cannot save the old tip as refs/lane-reset/$t; nothing changed" >&2; return 2; }
    saved=refs/lane-reset/$t-$n
  done
  # checkout -B, not reset --hard: it refuses rather than overwrite an untracked file that main tracks;
  # --no-overwrite-ignore makes it refuse for an ignored one too.
  if ! git -C "$LANE" checkout -q --no-overwrite-ignore -B "$LBR" "$new"; then
    git update-ref -d "$saved" "$old"
    echo "conveyor: the lane could not be moved to $new (an untracked or ignored file main tracks in the way?); nothing changed" >&2; return 2
  fi
  # The lane's next change starts its class history over (classes()).
  rm -f "$(git -C "$LANE" rev-parse --absolute-git-dir)/conveyor-classes"
  echo "reset the lane ($LBR): old tip $old, new tip $new"
  echo "old tip saved as $saved (to undo: git -C $LANE checkout -B $LBR $saved)"
  if [ ${#eq[@]} -eq 0 ] && [ ${#unl[@]} -eq 0 ]; then echo "commits dropped: none (the lane was behind main)"; return 0; fi
  echo "commits dropped:"
  for c in ${eq[@]+"${eq[@]}"}; do git -C "$LANE" log -1 --format='  %H %s (patch-equivalent to one on main)' "$c"; done
  for c in ${unl[@]+"${unl[@]}"}; do git -C "$LANE" log -1 --format='  %H %s (--drop: landed as a different patch)' "$c"; done
}
