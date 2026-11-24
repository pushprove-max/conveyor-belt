# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh retry <issue | card id>`: a blocked card's issue queued again, or a blocked main-red fix card or Tests
# page card by its card id (retry(), lib/issues.sh), sourced by conveyor.sh. `retry <issue> --fresh` drops the issue's kept work first (moved
# to a dated folder under the state folder): its next card builds from nothing.
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
# What block() and gonewt() need, to end a card stuck in flight first (unstick(), lib/run.sh).
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/review.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/claim.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
# The rule Lint check (lintrule()), which retry() reads of a card stopped for its lint policy change.
. "$HERE/lib/lint.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
[[ ${2:-} =~ ^([0-9]+|c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0)$ ]] && { [ $# = 2 ] || { [ $# = 3 ] && [ "$3" = --fresh ] && [[ $2 =~ ^[0-9]+$ ]]; }; } \
  || { echo "usage: conveyor.sh retry <issue> [--fresh] | retry <the card id of a main-red fix card or a Tests page card>" >&2; exit 2; }
# The retry by review-land (RETRYBY review-land, needsland(), lib/needsask.sh) is the other way round from
# review-retry's, and read under the lock too, as needsland() reads its cards before it: the owner's standing order
# holds now. Auto is on (scope full) with the standing kind review-retry on; the issue's last blocked card is blocked by
# its review after review-retry gave the issue back, and no retry by review-land came since (reviewlanded()); its
# reason names no P0 and no word or item of auto.reserved or the owner's profile (landable(), lib/views.sh); its issue
# is under the follow-up depth cap, as at the cap its finding could not be filed (fudepth(), lib/followups.sh: RLDEPTH,
# read from GitHub before the lock); and the owner gave its decision (needsask()'s blocked-<card>) in the ledger RLLED
# no answer: that answer is theirs, never overridden. Not a fresh retry, which drops the kept patch. Its next card lands
# the kept patch (resumeplan(), lib/card.sh). Prints why not and fails, or prints nothing.
landable() { # <issue> [fresh]
  local c r_ rows='[]'
  [[ $1 =~ ^[0-9]+$ ]] && [ -z "${2:-}" ] || { echo "a retry by review-land takes an issue number, and no --fresh"; return 1; }
  jq -e 'select(.scope == "full")' "$ST/auto/mode.json" >/dev/null 2>&1 && standingon review-retry \
    || { echo "auto is not on (scope full) with the standing kind review-retry on, so review-land does not land issue #$1"; return 1; }
  heldlist r_ || { echo "the pack's auto.reserved or the owner's profile could not be read"; return 1; }
  c=$({ stdb ask issue cards "$1" && stdb ask issue retried "$1"; } | jq -rs --argjson n "$1" --arg rb "$REVIEWBLOCK" --argjson r "$r_" "$REVIEWAGAIN"'retrylines([]) as $all
    | select(reviewretried($n; $all) != null and (reviewlanded($n; $all) | not))
    | [.[] | select(.issue == $n and .step == "blocked" and .retriedAt == null)] | last | select(. != null and (.reason | strings | test($rb)))
    | "\(.card)\t\(landable($r; $rb))"') || { echo "the card records of issue #$1 could not be read"; return 1; }
  [ -n "$c" ] || { echo "issue #$1 has no card blocked by its review after review-retry gave it back once, or review-land already gave it back once to land"; return 1; }
  [ "${c#*$'\t'}" = true ] || { echo "the block reason of card ${c%%$'\t'*} names a P0, or a word of auto.reserved or an item of the owner's profile"; return 1; }
  c=${c%%$'\t'*}
  [[ $RLDEPTH =~ ^[0-9]+$ ]] || { echo "the follow-up depth of issue #$1 could not be read"; return 1; }
  [ "$RLDEPTH" -lt "$MAX_DEPTH" ] || { echo "issue #$1 is a follow-up at the depth cap of $MAX_DEPTH, so the finding of card $c could not be filed"; return 1; }
  [ ! -e "$RLLED" ] || rows=$(CONVEYOR_MAIN=$MAIN bash "$HERE/../.claude/scripts/decision.sh" list) || { echo "the decision ledger $RLLED could not be read"; return 1; }
  ! jq -e --arg id "blocked-$c" 'any(.[]; .id == $id and (.answer // "") != "")' <<<"$rows" >/dev/null \
    || { echo "the owner answered decision blocked-$c, so the engine takes that answer"; return 1; }
}
# A held issue (setup holds every open one) would stay off the belt once its card is given back: the owner's retry
# releases it too, under the same lock, once the retry is done. A refused retry leaves the hold as it was.
again() { # <issue | card id> [fresh]
  local held=false c lk
  [[ ! $1 =~ ^[0-9]+$ ]] || held=$(ctl | jq -r --argjson n "$1" '.held | index($n) != null') \
    || { echo "conveyor: cannot read the control record; nothing changed" >&2; return 1; }
  # The standing review-retry's retry (RETRYBY review-retry) gives an issue back once (reviewretried(), lib/views.sh),
  # read here under the lock: the watcher picks its card from a snapshot that can be older than a review-retry the
  # engine ran (needsretry()), or the other way round, and would then give back a later card of the issue.
  if [ "$RETRYBY" = review-retry ] && [[ $1 =~ ^[0-9]+$ ]]; then
    c=$({ stdb ask issue cards "$1" && stdb ask issue retried "$1"; } | jq -rs --argjson n "$1" "$REVIEWAGAIN"'retrylines([]) as $all | reviewretried($n; $all) | .card // ""') \
      || { echo "conveyor: the card records of issue #$1 could not be read; nothing changed" >&2; return 1; }
    [ -z "$c" ] || { echo "conveyor: review-retry already gave issue #$1 back once (its card $c was blocked by its review), and neither the owner's retry nor a landed card came after; nothing changed: it waits for the owner" >&2; return 1; }
  fi
  # The ledger's read lock is held from landable()'s read of the owner's answer until retry() has moved the card's lines
  # (it ends with this lock's subshell): the owner's answer (decision.sh answer, the Board's) waits for it. Bug: an
  # answer written between the two let the card be given back over it.
  if [ "$RETRYBY" = review-land ]; then
    [ ! -e "$RLLED" ] || { exec {lk}<"$RLLED" && flock -s -w 120 "$lk"; } \
      || { echo "conveyor: the decision ledger $RLLED could not be locked; nothing changed: it waits for the owner" >&2; return 1; }
    c=$(landable "$@") || { echo "conveyor: $c; nothing changed: it waits for the owner" >&2; return 1; }
  fi
  retry "$@" || return 1
  [ "$held" = true ] || return 0
  control release "$1" >/dev/null || { echo "conveyor: issue #$1 is held; release it with \`conveyor.sh control release $1\`" >&2; return 1; }
  echo "conveyor: issue #$1 was held; it is released, so the loop picks it again"
}
# An issue's card stuck in flight (its process gone or stopped, or no process of its step for the pack's stuck) is ended first,
# blocked with its work kept, outside the lock (unstick(), lib/run.sh): retry then takes it as a blocked card.
[[ ! $2 =~ ^[0-9]+$ ]] || unstick "$2"
# Who runs this retry, kept as the blocked line's retriedBy (retry(), lib/issues.sh): review-retry for the standing
# review-retry's (CONVEYOR_REVIEWRETRY: the watcher's, over ssh too, and needsretry()'s); review-land for needsland()'s
# (CONVEYOR_REVIEWLAND); CONVEYOR_RETRYBY when set
# (needsask()'s answer to a decision, lib/needsask.sh; a Foreman's command, foreman/lib.sh ask()). Else the owner's
# (the command line, the Board's Retry and Fix): only the owner's own retry lets review-retry give the issue back once
# more (REVIEWAGAIN, lib/views.sh). Not CONVEYOR_FOREMAN: a Board started from a Foreman session inherits it.
if [ -n "${CONVEYOR_REVIEWRETRY:-}" ]; then RETRYBY=review-retry; elif [ -n "${CONVEYOR_REVIEWLAND:-}" ]; then RETRYBY=review-land; else RETRYBY=${CONVEYOR_RETRYBY:-owner}; fi
# A retry by review-land reads its issue's follow-up depth from GitHub here, before the lock: every card's record
# writes wait on that lock, and a GitHub call can take as long as the network does. Bug: it ran under the lock.
RLDEPTH='' RLLED=${CONVEYOR_LEDGER:-$MAIN/.claude/metrics/decisions.jsonl}
[ "$RETRYBY" != review-land ] || [[ ! $2 =~ ^[0-9]+$ ]] || RLDEPTH=$(fudepth "$(gh issue view "$2" --json number,title,body,labels,milestone)") || RLDEPTH=''
locked again "$2" ${3:+fresh}
