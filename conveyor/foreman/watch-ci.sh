#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# watch-ci.sh [--once] -- the Foreman's CI watcher, run by waiter.sh. CI (.github/workflows/ci.yml) runs only at a
# release, called by the Release workflow (release.yml) before it tags. Every 5 minutes this reads, for each of the
# Foreman's own records (lib.sh mine) with a checkout on this machine (lib.sh ledger), the newest runs of the Release
# workflow (`gh run list --workflow release.yml`, run in that checkout). A failed Release run whose failed jobs include
# one of its CI jobs (named "CI / <job>", the caller job's name and the called job's) puts one wake in pending and
# exits, one line per such run: its commit, the failed CI steps (`gh run view --json jobs`) and the run's link. A run
# that failed past its CI (the release step's own checks) does not wake. Each run wakes once: its key,
# <repo>/release@<run id>, is kept in ci-seen.txt while the run is among those read. A run whose jobs cannot be read is
# tried again at the next poll; a record whose runs cannot be read keeps its keys.
# For tests: CONVEYOR_FOREMAN_GH (run by bash -c in place of gh, with gh's arguments as "$@", in the checkout),
# --once (one poll: exit 0 with a wake put, 1 with nothing new).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
SEEN=$FD/ci-seen.txt
mkdir -p "$FD" && touch "$SEEN" || exit 1
gh_() { # <checkout> <gh argument>...
  local d=$1; shift
  if [ -n "${CONVEYOR_FOREMAN_GH:-}" ]; then (cd "$d" && bash -c "$CONVEYOR_FOREMAN_GH" _ "$@" < /dev/null)
  else (cd "$d" && timeout -k 2 60 gh "$@" < /dev/null); fi
}
# A record's failed Release runs, oldest first, one line each: the run's id, link and short commit, tab-separated.
# The workflow's name is checked too, as --workflow is the only other filter. A cancelled or skipped run is not failed.
RED='[.[] | objects | select(.status == "completed" and .workflowName == "Release" and (.createdAt | strings)
    and (.conclusion | IN("failure", "timed_out", "startup_failure")))]
  | sort_by(.createdAt) | .[] | [(.databaseId | tostring), (.url // "" | tostring), (.headSha // "" | tostring | .[0:7])] | @tsv'
# A run's failed CI steps, "<job>: <step>" (the job alone when no step failed, as at a timeout), joined by "; ".
STEPS='[.jobs[]? | select(.conclusion == "failure" and (.name | strings | startswith("CI / "))) | .name as $j
  | ([.steps[]? | select(.conclusion == "failure") | "\($j): \(.name)"] | if length > 0 then .[] else $j end)] | join("; ")'
poll() { # 0 when a wake was put in pending
  local recs repo main dir runs red keep='' now='' lines='' id url sha key jobs steps
  recs=$(mine) || return 1
  while IFS=$'\t' read -r repo main; do
    if ! dir=$(ledger "$repo" "$main") \
      || ! runs=$(gh_ "$dir" run list --workflow release.yml --limit 20 --json databaseId,headSha,conclusion,status,workflowName,url,createdAt 2>/dev/null) \
      || ! red=$(jq -r "$RED" <<<"$runs" 2>/dev/null); then
      keep+=$(awk -v p="$repo/" 'index($0, p) == 1' "$SEEN")$'\n'
      continue
    fi
    while IFS=$'\t' read -r id url sha; do
      [ -n "$id" ] || continue
      key="$repo/release@$id"
      if grep -qxF -- "$key" "$SEEN"; then now+="$key"$'\n'; continue; fi
      jobs=$(gh_ "$dir" run view "$id" --json jobs 2>/dev/null) && steps=$(jq -r "$STEPS" <<<"$jobs" 2>/dev/null) || continue
      now+="$key"$'\n'
      [ -n "$steps" ] || continue
      lines+="$repo: CI failed in the Release run at commit $sha: failed steps: $steps; run: $url"$'\n'
    done <<<"$red"
  done <<<"$recs"
  # The wake is put before its keys are kept as seen: a kill between the two repeats it, never loses it.
  [ -z "$lines" ] || printf 'CI red in a release\n%s' "$lines" | pending_put || return 1
  printf '%s%s' "$keep" "$now" | sed '/^$/d' | sort -u > "$SEEN.tmp" && mv "$SEEN.tmp" "$SEEN" || return 1
  [ -n "$lines" ]
}
while :; do
  poll && exit 0
  [ "${1:-}" != --once ] || exit 1
  sleep 300
done
