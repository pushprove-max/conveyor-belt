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
# A held issue (setup holds every open one) would stay off the belt once its card is given back: the owner's retry
# releases it too, under the same lock, once the retry is done. A refused retry leaves the hold as it was.
again() { # <issue | card id> [fresh]
  local held=false c
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
  retry "$@" || return 1
  [ "$held" = true ] || return 0
  control release "$1" >/dev/null || { echo "conveyor: issue #$1 is held; release it with \`conveyor.sh control release $1\`" >&2; return 1; }
  echo "conveyor: issue #$1 was held; it is released, so the loop picks it again"
}
# An issue's card stuck in flight (its process gone or stopped, or no process of its step for the pack's stuck) is ended first,
# blocked with its work kept, outside the lock (unstick(), lib/run.sh): retry then takes it as a blocked card.
[[ ! $2 =~ ^[0-9]+$ ]] || unstick "$2"
# Who runs this retry, kept as the blocked line's retriedBy (retry(), lib/issues.sh): review-retry for the standing
# review-retry's (CONVEYOR_REVIEWRETRY: the watcher's, over ssh too, and needsretry()'s); CONVEYOR_RETRYBY when set
# (needsask()'s answer to a decision, lib/needsask.sh; a Foreman's command, foreman/lib.sh ask()). Else the owner's
# (the command line, the Board's Retry and Fix): only the owner's own retry lets review-retry give the issue back once
# more (REVIEWAGAIN, lib/views.sh). Not CONVEYOR_FOREMAN: a Board started from a Foreman session inherits it.
if [ -n "${CONVEYOR_REVIEWRETRY:-}" ]; then RETRYBY=review-retry; else RETRYBY=${CONVEYOR_RETRYBY:-owner}; fi
locked again "$2" ${3:+fresh}
