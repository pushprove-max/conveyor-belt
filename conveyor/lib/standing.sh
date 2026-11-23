# SPDX-License-Identifier: Apache-2.0
# The standing kinds of routine yes: the pack's auto.standing, each kind a step the owner said yes to ahead of time, so
# the Foreman takes it without asking (and, for review-followup, the engine: followups(), lib/followups.sh). The
# Foreman's watcher takes review-retry in its place (foreman/watch-conveyor.sh reviewretry()), and so does the engine's
# loop while auto is on (lib/needsask.sh needsretry()). Each kind
# is off until the owner turns it on: setup writes the list empty, and the Board's Rules tab turns a kind on or off
# (`conveyor.sh auto standing <kind> on|off`). The Foreman is told the kinds that are on, with their limits, at its
# start (foreman.sh asks each of its records for `conveyor.sh auto standing`, on the host that has the record). Each act under a kind is one row of the
# ruling log, source "standing", with its kind (standinglog); the Foreman then tells the owner in one line (a
# review-retry act the watcher takes and logs, and no one tells the owner of). What no kind and no auto pass may take,
# as it waits for the owner, is heldlist's: the pack's auto.reserved and the owner's profile items.
# Sourced by commands/auto.sh and lib/followups.sh, after lib/prompts.sh (packget).
# Test seam: CONVEYOR_RULING_LOG (the ruling log).
STANDING_KINDS=(asked-fix review-followup release-check fixed-block review-retry)
# The ruling log's path (.claude/hooks/lib/rulings.sh rulings_log, of main's checkout); fails when it cannot be named.
rulingslog() { [ -z "${CONVEYOR_RULING_LOG:-}" ] || { echo "$CONVEYOR_RULING_LOG"; return; }; CONVEYOR_MAIN=$MAIN bash -c '. "$1" && rulings_log' _ "$HERE/../.claude/hooks/lib/rulings.sh"; }
# The owner's written profile of how they decide (owner-way.md, in the folder foreman/lib.sh FD names): its path when
# it is there and not empty; fails when there is none.
profilefile() {
  local f
  f=$(CONVEYOR_MAIN=$MAIN bash -c '. "$1" > /dev/null && printf %s "$FD"' _ "$HERE/foreman/lib.sh") && [ -n "$f" ] || return 1
  [ -s "$f/owner-way.md" ] && printf %s "$f/owner-way.md"
}
# The items of the profile's "Never decide; ask" and "Hard lines" sections, as a JSON list: each "- " or "* " line under
# either heading (any level), trimmed, in two forms, as the question's text has no Markdown marks: with no marks
# (**bold**, _italic_, ~~struck~~, a [link](url)'s text only) outside its `code` spans, whose text is kept as written;
# and as written with only the code spans' backticks taken out, so a path such as .claude/scripts/__tests__/ written
# with no backticks is still held. [] with no profile; fails when the profile cannot be read.
profileheld() {
  local f
  f=$(profilefile) || { echo '[]'; return 0; }
  [ -r "$f" ] || return 1
  awk '/^#+[[:space:]]/ { h = tolower($0); sub(/^#+[[:space:]]+/, "", h); sub(/[[:space:]]+$/, "", h); on = (h == "never decide; ask" || h == "hard lines"); next }
    on && /^[[:space:]]*[-*][[:space:]]+[^[:space:]]/ { sub(/^[[:space:]]*[-*][[:space:]]+/, ""); print }' "$f" \
    | jq -Rsc 'def trim: gsub("^\\s+|\\s+$"; "");
      def plain: gsub("\\[(?<t>[^\\]]*)\\]\\([^)]*\\)"; "\(.t)") | gsub("[*~]"; "") | gsub("(?<!\\w)_+|_+(?!\\w)"; "");
      split("\n") | map(select(trim != "") | (split("`") | to_entries | map(if .key % 2 == 0 then .value | plain else .value end) | join("") | trim),
        (gsub("`"; "") | trim)) | map(select(. != "")) | unique'
}
# heldlist <var>: what waits for the owner, as one JSON list in <var>: the words of the pack's auto.reserved and the
# profile's items (profileheld). auto decide holds a decision that holds one (case-insensitive); lib/needsask.sh names
# each one a question's cut would hide (askcut()) and gives back no card whose block reason holds one (needsretry()).
# Fails when either cannot be read.
heldlist() {
  local h_ p_
  packget auto.reserved h_ && p_=$(profileheld) && h_=$(jq -c --argjson p "$p_" '. + $p' <<<"$h_") || return 1
  printf -v "$1" %s "$h_"
}
standingon() { # <kind>: 0 when the pack turns that kind on
  local s_; packget auto.standing s_ && jq -e --arg k "$1" 'index($k) != null' <<<"$s_" >/dev/null
}
# <kind> <what was done>: the act's row in the ruling log, as ruling-log.sh writes a row (its id, utc, time; source
# "standing", kind, the act as its answer, pick "standing"), under the log's own lock. Prints the row's id.
standinglog() {
  local rl pre now stamp utc time id row
  rl=$(rulingslog) && [ -n "$rl" ] || { echo "conveyor: the ruling log cannot be named, so the $1 act was not logged" >&2; return 1; }
  pre=$(bash -c '. "$1" && rulings_prefix' _ "$HERE/../.claude/hooks/lib/rulings.sh") || { echo "conveyor: the host file's rulingPrefix is not letters and digits, so the $1 act was not logged" >&2; return 1; }
  now=$(date +%s); printf -v stamp '%(%Y%m%d-%H%M%S)T' "$now"; printf -v time '%(%Y-%m-%d %H:%M:%S %Z)T' "$now"
  utc=$(TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T' "$now")
  id=$pre-$stamp-s-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')
  row=$(jq -cn --arg id "$id" --arg utc "$utc" --arg time "$time" --arg k "$1" --arg w "$2" \
    '{id: $id, utc: $utc, time: $time, source: "standing", kind: $k, question: null, answer: $w, pick: "standing"}') || return 1
  mkdir -p "${rl%/*}" 2>/dev/null
  { { flock -w 10 9 && printf '%s\n' "$row" >&9; } 9>>"$rl"; } 2>/dev/null || { echo "conveyor: the ruling log $rl could not be written, so the $1 act was not logged" >&2; return 1; }
  printf '%s\n' "$id"
}
# What the Foreman is told about the kinds that are on, with their limits; nothing when none is on. <run> is how the
# Foreman runs this engine; <reserved> the pack's auto.reserved, as words.
standingrules() { # <run> <reserved>
  local s_ k
  packget auto.standing s_ || return 1
  [ "$(jq 'length' <<<"$s_")" != 0 ] || return 0
  cat <<EOF
# STANDING YES (the pack's auto.standing)

The owner said yes ahead of time to the kinds of step below. Take each one without asking (but review-retry, which the watcher takes itself), even where your other rules wait for the owner's yes. Run each command below after \`$1\`. After each act, log it with \`auto act <kind> "<what you did, with the issue or card>"\` and put the one line it prints in your next reply.
EOF
  for k in "${STANDING_KINDS[@]}"; do
    jq -e --arg k "$k" 'index($k) != null' <<<"$s_" >/dev/null || continue
    case $k in
      asked-fix) echo "- asked-fix: the owner reports a problem or asks for a fix. File the issue, then release it at once (\`control release <issue>\`)." ;;
      review-followup) echo "- review-followup: a follow-up from the review of a card the owner approved. Release it when it only finishes or corrects that card's own change. The engine itself does not hold, and logs, one whose finding names only that card's files and no word of auto.reserved: tell the owner of each too." ;;
      release-check) echo "- release-check: a check fails in a release the owner asked for (a false privacy hit, a red test file). File a fix card for each failure, with the line \`Release fix: <version>\` in its body, and release it. Once every fix card has landed, the engine starts \`release-run prep <version>\` for a red test file; for another check, go on with the release." ;;
      fixed-block) echo "- fixed-block: a card is blocked, and a fix that landed removed the cause. Add \`Depends on: #<fix>\` to the card's issue, then run \`retry <issue> --fresh\`." ;;
      review-retry) echo "- review-retry: a card blocked by its review (\"the fix for <finding> did not hold after <n> rounds\"). The watcher runs \`retry <issue>\` and logs it: you take no step for it, log nothing and tell the owner nothing of it. A wake for such a card is a failed retry, or a block whose reason holds a word of auto.reserved or an item of the owner's profile, which the watcher leaves blocked for the owner: act on its reason, and ask the owner for the second." ;;
    esac
  done
  echo "- Still ask the owner, whatever the kind: new engine behaviour (how the engine builds, reviews, fixes, tests, lands or pushes) or a release, each one the owner did not ask for; a design choice; anything about $2. When unsure, ask."
}
