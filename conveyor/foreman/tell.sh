#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# tell.sh fast|research <message> -- a lane's message to its project's Foreman (issue 1641): a finding, a question, a
# card to file or watch. It puts the message, its lane named, as one wake in the pending folder of the project's
# Foreman (lib.sh pending_put; the folder of the project's main checkout, CONVEYOR_MAIN, else the one of the checkout it
# runs in, never a session's CONVEYOR_FOREMAN_DIR, which in the research lane is the lane's own). A live Foreman's
# waiter relays it in its next wake (waiter.sh): within a minute while the Foreman waits, at its next stop while it
# works; with none live, the waiter of the Foreman's next start relays it.
# The message is made one line (each run of white space one space, other control characters taken out), so it cannot
# pass for another wake's line, and is refused over MAX characters: a long finding goes in a report, and the message
# names its path.
# `conveyor.sh lane fast tell` runs it for the fast lane; the research lane's filer runs it (lanes/research-file --tell).
set -u
MAX=2000
[ $# = 2 ] && [[ $1 =~ ^(fast|research)$ ]] || { echo "usage: tell.sh fast|research <message>" >&2; exit 2; }
msg=$(printf '%s' "$2" | tr -s '[:space:]' ' ' | tr -d '[:cntrl:]') msg=${msg# } msg=${msg% }
[ -n "$msg" ] || { echo "tell: an empty message is not sent" >&2; exit 2; }
[ "${#msg}" -le "$MAX" ] || { echo "tell: the message is ${#msg} characters, over $MAX: write it in a report and send its path" >&2; exit 2; }
unset CONVEYOR_FOREMAN_DIR
CONVEYOR_MAIN=${CONVEYOR_MAIN:-$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}
[ -n "$CONVEYOR_MAIN" ] || { echo "tell: the project's main checkout cannot be found: run it in a lane's checkout" >&2; exit 1; }
export CONVEYOR_MAIN
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
printf 'Message from the %s lane: %s\n' "$1" "$msg" | pending_put \
  || { echo "tell: the message could not be written in $PENDING" >&2; exit 1; }
echo "tell: sent to the $NAME ($FD); it reaches the session at its next wake, or at its next start when none is live"
