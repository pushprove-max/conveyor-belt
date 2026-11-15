#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# watch-alerts.sh [--once] -- the Foreman's alerts watcher, run by waiter.sh. Once a minute it reads the Board's data
# file (data.js, `window.DASH = {...};`), which the host file names as foreman.board, runs the Board's alert rules over
# its usage limit and the open decisions of the Foreman's own projects, and on any active alert not
# seen yet puts one wake in pending, one line per alert, and exits. An alert's id is <key>-<since epoch>: the key,
# without that stamp, is in alerts-seen.txt from its wake until it is no longer active, so one condition wakes once
# while it lasts, and again when it clears and comes back.
# With no data file named, or none readable yet, it still alerts on those decisions.
# For tests: --once (one poll: exit 0 with a wake put, 1 with nothing new).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
SEEN=$FD/alerts-seen.txt
mkdir -p "$FD" && touch "$SEEN" || exit 1
rules() { # <limit> <decisions>: the Board's alert rules (dashboard_alerts.jq) over them; each active alert {key, line}
  local out
  out=$(jq -cn --argjson parts "[{\"limit\": $1, \"needsMax\": {\"decisions\": $2}}]" --argjson srcs '[]' \
      --argjson preva '[{}]' --argjson now "$(date +%s)" -f "$FHERE/../../.claude/scripts/dashboard_alerts.jq" 2>/dev/null) \
    || return 1
  jq -c '.alerts // [] | .[] | objects | select(.id | strings)
    | {key: (.id | sub("-[0-9]{9,}$"; "")), line: (.text // .id | tostring | gsub("\\s+"; " ") | .[0:600])}' <<<"$out" 2>/dev/null
}
poll() { # 0 when a wake was put in pending
  local data lim board decs all new repo main
  # data.js is {updatedAt, panels}, with no alerts of its own: the Board's rules run here over the 7-day limit of its
  # Health panel (the account's, the same for every Foreman). The object alone is read: what is before its first {
  # (window.DASH =) and after its last } (;) is not JSON.
  lim=
  if data=$(jq -er '.foreman.board | strings' "$HOSTF" 2>/dev/null); then
    [[ $data != "~/"* ]] || data=$HOME/${data#"~/"}
    if data=$(cat "$data" 2>/dev/null); then
      data=${data#"${data%%\{*}"}; data=${data%"${data##*\}}"}
      lim=$(jq -c '.panels.health.data.limit | objects' <<<"$data" 2>/dev/null) || lim=
    fi
  fi
  # With no Board named, none that reads, or a limit its rules cannot read, the limit is unknown: its alerts seen stay
  # seen (every key but a question's), so a Board that reads again does not wake one still active.
  [ -n "$lim" ] && board=$(rules "$lim" '[]') || board=$(grep -v '^question-' "$SEEN" | jq -Rc '{key: .}')
  # The owner's open decisions are each project's, so they are read from the ledger of each of the Foreman's own
  # records (lib.sh mine; .claude/metrics/decisions.jsonl in its checkout, lib.sh ledger), each named for its project, never from
  # the Board's Needs panel, which shows the one ledger of the Board's checkout whichever Foreman reads it. A ledger
  # that does not read is passed over here (the live summary names it). They run apart from the limit, so no Board
  # holds them up.
  decs=$(mine | while IFS=$'\t' read -r repo main; do
    main=$(ledger "$repo" "$main") || continue
    jq -cs --arg r "$repo" 'group_by(.id) | map(last) | .[] | select(.answeredAt == null)
      | {id: "\($r)-\(.id)", askedAt, question: "\($r): \(.question)"}' "$main/.claude/metrics/decisions.jsonl" 2>/dev/null
  done | jq -cs .) || return 1
  all=$(rules null "$decs") || return 1
  all=$(printf '%s\n' "$board" "$all" | sed '/^$/d')
  new=$(jq -c --rawfile seen "$SEEN" '($seen | split("\n")) as $s | select(.key | IN($s[]) | not)' <<<"$all") \
    || return 1
  [ -z "$new" ] || jq -r '"Alert: \(.line)"' <<<"$new" | pending_put || return 1
  # Only the alerts active now stay seen: one that clears and comes back wakes again.
  jq -r .key <<<"$all" | sort -u > "$SEEN.tmp" && mv "$SEEN.tmp" "$SEEN" || return 1
  [ -n "$new" ]
}
while :; do
  poll && exit 0
  [ "${1:-}" != --once ] || exit 1
  sleep 60
done
