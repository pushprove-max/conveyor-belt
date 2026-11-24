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
# How the decision of a card blocked by its review, after review-retry gave its issue back once, says so
# (needsask(), lib/needsask.sh): auto decide leaves such a decision to the owner (commands/auto.sh). While auto is on
# (full), the engine lands such a card before it is asked (needsland(), lib/needsask.sh).
# shellcheck disable=SC2034 # RRAGAIN is read by needsask() in lib/needsask.sh and by commands/auto.sh
RRAGAIN='is blocked by its review again, after review-retry gave its issue back once'
# The answer a retry by review-land (landable(), commands/retry.sh) gives the card's open decision blocked-<card> before it
# gives the card back. needsask() (lib/needsask.sh) reopens a decision so closed whose card is still blocked: that retry
# ended before it moved the card's lines.
# shellcheck disable=SC2034 # RLCLOSED is read by commands/retry.sh and lib/needsask.sh
RLCLOSED='Closed: review-land gave the card back to land, the standing order of the owner while auto is on'
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
# with no backticks is still held. On a build host, whose Foreman's folder has no profile, the items the owner's machine
# sent with their rulings (`auto rulings`, their {source: "profile", held} row in <state folder>/auto/rulings.jsonl)
# are added. [] with neither; fails when either cannot be read.
profileheld() {
  local f l='[]' s=$ST/auto/rulings.jsonl
  if f=$(profilefile); then
    [ -r "$f" ] || return 1
    l=$(awk '/^#+[[:space:]]/ { h = tolower($0); sub(/^#+[[:space:]]+/, "", h); sub(/[[:space:]]+$/, "", h); on = (h == "never decide; ask" || h == "hard lines"); next }
      on && /^[[:space:]]*[-*][[:space:]]+[^[:space:]]/ { sub(/^[[:space:]]*[-*][[:space:]]+/, ""); print }' "$f" \
      | jq -Rsc 'def trim: gsub("^\\s+|\\s+$"; "");
        def plain: gsub("\\[(?<t>[^\\]]*)\\]\\([^)]*\\)"; "\(.t)") | gsub("[*~]"; "") | gsub("(?<!\\w)_+|_+(?!\\w)"; "");
        split("\n") | map(select(trim != "") | (split("`") | to_entries | map(if .key % 2 == 0 then .value | plain else .value end) | join("") | trim),
          (gsub("`"; "") | trim)) | map(select(. != "")) | unique') || return 1
  fi
  [ ! -e "$s" ] || l=$(jq -ncR --argjson l "$l" '$l + [inputs | fromjson? | objects | select(.source == "profile") | .held[]? | strings] | unique' "$s") || return 1
  printf '%s\n' "$l"
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
# auto's log (the mode's log, commands/auto.sh). autologged <log>: its decisions, the entries under "## Decisions", an
# entry whose answer could not be recorded left out. autowaiting <log>: the entries under "## Waiting for the owner": a
# "- <id>: " line, or a "### " entry with its "- **...**" lines. autosum <log>: the log, printed with its "## Summary"
# made again from those two, as auto decide and needsland() (rlput(), lib/needsask.sh) leave it after each entry.
autologged() { awk '/^## / { on = ($0 == "## Decisions") } on && /^### / { n++ } on && /^- \*\*Recorded:\*\* no/ { n-- } END { print n + 0 }' "$1" 2>/dev/null || echo 0; }
autowaiting() { awk '/^## / { on = ($0 == "## Waiting for the owner") } on && (/^### / || (/^- / && !/^- \*\*/)) { n++ } END { print n + 0 }' "$1" 2>/dev/null || echo 0; }
autosum() {
  local n h; n=$(autologged "$1") h=$(autowaiting "$1")
  S="Decided for the owner: $n. Waiting for the owner: $h. Last pass: $(date '+%F %H:%M')." awk '
    /^## Summary$/ { print; print ""; print ENVIRON["S"]; print ""; skip = 1; next } skip && /^## / { skip = 0 } !skip { print }' "$1"
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
# STANDING YES

The owner said yes ahead of time to these kinds of step. Take each one without asking (but review-retry, which the watcher takes itself), even where other rules wait for the owner. Run each command after \`$1\`. Log each act with \`auto act <kind> "<what you did, with the issue or card>"\` and put the line it prints in your next reply.
EOF
  for k in "${STANDING_KINDS[@]}"; do
    jq -e --arg k "$k" 'index($k) != null' <<<"$s_" >/dev/null || continue
    case $k in
      asked-fix) echo "- asked-fix: the owner reports a problem or asks for a fix. File the issue, then release it at once (\`control release <issue>\`)." ;;
      review-followup) echo "- review-followup: a review follow-up of a card the owner approved. Release it when it only finishes or corrects that card's change. The engine does not hold, and logs, one whose finding names only that card's files and no auto.reserved word: tell the owner of each too." ;;
      release-check) echo "- release-check: a check fails in a release the owner asked for (a false privacy hit, a red test file). File a fix card for each, with the line \`Release fix: <version>\` in its body, and release it. Then do what \`auto standing release-check how\` prints." ;;
      fixed-block) echo "- fixed-block: a landed fix removed a blocked card's cause. Add \`Depends on: #<fix>\` to its issue, then run \`retry <issue> --fresh\`." ;;
      review-retry) echo "- review-retry: a card blocked by its review (\"the fix for <finding> did not hold after <n> rounds\"). The watcher retries it once per issue and logs it: you take no step for it, log nothing and tell the owner nothing of it. On a wake for such a card, do what \`auto standing review-retry how\` prints." ;;
    esac
  done
  echo "- Still ask the owner, whatever the kind: new engine behaviour (how the engine builds, reviews, fixes, tests, lands or pushes) or a release, each one the owner did not ask for; a design choice; anything about $2. When unsure, ask."
}
# The rest of a kind's rule, which standingrules leaves out so the Foreman's start fits its size limit. The rule names
# it as an `auto standing <kind> how` command run like its others: by the engine on the record's host, the same engine
# that printed the rule, so a Foreman's machine with an older engine still reads it (a file of the Foreman's own engine
# could not). Nonzero for a kind with no such rest.
standinghow() { # <kind>
  case $1 in
    release-check) echo "Once every fix card has landed, the engine starts \`release-run prep <version>\` for a red test file; for another check, go on with the release." ;;
    review-retry) echo "A wake for such a card is a failed retry; a retry that worked but that the watcher could not log (\"was retried (review-retry), but the act was not logged\"); a block whose reason holds a word of auto.reserved or an item of the owner's profile, which the watcher leaves blocked for the owner; a block the watcher did not retry, as it could not read auto.reserved or the owner's profile on the card's host; or a second such block of an issue that review-retry already gave back once (the watcher, or the engine while the watcher was down), which waits for the owner in Needs you with both block reasons (while auto is on, the engine lands it instead, once for each issue, files its findings as follow-ups and logs that act). Act on the reason of a failed retry; one that says review-retry already gave the issue back once is such a second block. For a retry that was not logged, log it with \`auto act review-retry\` and do not say that the retry failed. Ask the owner for the last three, do not retry them, and do not say that a retry failed: no retry ran." ;;
    *) echo "conveyor: auto: the standing kind $1 has no more to its rule than auto standing prints" >&2; return 1 ;;
  esac
}
