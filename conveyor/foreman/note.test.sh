#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# `foreman.sh note` (note.sh, issue 1685): the Foreman's note on a blocked card it takes, sent by ask to the record's
# host as `conveyor.sh foreman note` (its own case, on the host, is t_foremannote, conveyor/tests/snapblock.test.sh),
# and the renewal the Conveyor watcher asks for at each poll (lib.sh renewnotes). The ask seam (CONVEYOR_FOREMAN_ASK)
# stands for the host: it logs each ask in $T/asks, refuses a note while $T/refuse is there (as the host refuses a card
# that is not blocked), says a repo has no such card (exit 4) while $T/none-<repo> is there, and while $T/claim is
# there, runs a claim by session sess-2 first, as the owner's claim in another session would come while the note is
# written.
# Bugs it catches: a note sent with no session, to the wrong record (or to none, for a repo with "." or "_" in its
# name, or to the first of two repos with the same tag only), or from a session that is not the Foreman's; a note the
# host refused reported as kept; a claim that moves the role between the note's check of the role and its write (a
# note kept for a session that lost the role); --ask not sent; the watcher renewing the notes once the Foreman's Claude
# process holds another session (a /resume there), so they never end.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CONVEYOR_FOREMAN_SESSION_PID
fail() { echo "FAIL [note]: $*" >&2; exit 1; }
M=$T/alpha FD=$T/state/foreman
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN_DIR=$FD CLAUDE_CONFIG_DIR=$T/claude \
  CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
mkdir -p "$HOME" "$FD" "$CLAUDE_CONFIG_DIR/sessions" "$M/.conveyor" "$XDG_CONFIG_HOME/conveyor" && git init -q "$M" && echo '{}' > "$M/.conveyor/project.json" \
  && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}, {repo: "alpha-x", main: ($m + "-x")}, {repo: "so-lo-1", main: ($m + "-t")}, {repo: "so_lo.1", main: ($m + "-s")}], foreman: {groups: [["alpha", "alpha-x", "so-lo-1", "so_lo.1"]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  || fail "the fixture was not made"
export CONVEYOR_FOREMAN_ASK="echo \"\$CONVEYOR_REPO|\$CONVEYOR_MAIN|\$CONVEYOR_CMD\" >> $T/asks
  [ ! -e $T/claim ] || { (cd $M && timeout 3 bash $SRC/foreman.sh claim sess-2) > $T/claimout 2>&1; echo \$? > $T/claimrc; }
  case \$CONVEYOR_CMD in 'foreman note '*' renew') ;; 'foreman note '*) [ ! -e $T/refuse ] || { echo 'conveyor: the card is not blocked now' >&2; exit 3; }
      [ ! -e \"$T/none-\$CONVEYOR_REPO\" ] || { echo 'conveyor: this record has no card' >&2; exit 4; } ;; *) exit 3 ;; esac"
# The Foreman's session is sess-1, and this test's shell stands for its Claude process: Claude Code's sessions/<pid>.json
# names the session (lib.sh cc_pid finds the nearest ancestor with one), and claude.pid records it (foreman.sh claim_).
echo 'sess-1 2026-11-25T11:00:00Z' > "$FD/session"; printf '%s' $$ > "$FD/claude.pid"
session() { jq -cn --argjson p $$ --arg s "$1" '{pid: $p, sessionId: $s}' > "$CLAUDE_CONFIG_DIR/sessions/$$.json"; } # <session id>
note() { CONVEYOR_MAIN=$M bash "$SRC/foreman.sh" note "$@"; }
asks() { cat "$T/asks" 2>/dev/null; rm -f "$T/asks"; }
C1=c20261125T110000-alpha-7 C2=c20261125T110500-alpha-8

session sess-1
out=$(note "$C1" 'traced run in progress,
  then hand land and retry' 2>&1) || fail "note $C1 'traced run in progress, then hand land and retry' in the Foreman's session failed: $out"
a=$(asks); [ "$a" = "alpha|$M|foreman note sess-1 $C1 --does traced run in progress, then hand land and retry" ] \
  || fail "note $C1 <two lines> did not ask alpha's host for one note of sess-1 on one line: $a"
out=$(note "$C2" --ask 'which fix to land' 2>&1) || fail "note $C2 --ask 'which fix to land' in the Foreman's session failed: $out"
a=$(asks); [ "$a" = "alpha|$M|foreman note sess-1 $C2 --ask which fix to land" ] || fail "note $C2 --ask 'which fix to land' did not send --ask: $a"
# A card of alpha-x names alpha too (c...-alpha-x-9): its record is the longest repo the ID names.
out=$(note c20261125T110000-alpha-x-9 'hand run' 2>&1) || fail "note c20261125T110000-alpha-x-9 'hand run' failed: $out"
a=$(asks); [ "${a%%|*}" = alpha-x ] || fail "note c20261125T110000-alpha-x-9 'hand run' asked the host of another record than alpha-x: $a"
[ "$(cat "$FD/noted")" = $'sess-1\nalpha\nalpha-x' ] || fail "after notes in alpha, alpha and alpha-x, noted does not list sess-1, then each repo once: $(cat "$FD/noted")"

# The host refuses a card that is not blocked now (retried, landed or shut): the note says so, and fails.
touch "$T/refuse"
out=$(note "$C1" 'hand run in progress' 2>&1) && fail "note $C1 'hand run in progress', which the host refused, said it was kept: $out"
[[ $out == *'not blocked now'* ]] || fail "note $C1 'hand run in progress', which the host refused, does not say why: $out"
rm -f "$T/refuse"; asks > /dev/null

# A card of none of the Foreman's projects, and a session that is not the Foreman's, ask nothing.
note c20261125T110000-beta-3 'x' > /dev/null 2>&1 && fail "note c20261125T110000-beta-3 x, a card of no record of the Foreman, was taken"
session sess-9
out=$(note "$C1" 'not mine' 2>&1) && fail "note $C1 'not mine' from session sess-9, not the Foreman's, was taken: $out"
[ -z "$(asks)" ] || fail "note $C1 from sess-9, or a card of beta, asked the host"
session sess-1

# A claim by sess-2 made while the note is written (the ask) waits for the note's claim.lock: the role does not move
# between the note's check and its write. Without the lock, the claim ends (exit 0) and the note is kept for sess-1, which
# no longer holds the role. The claim stops after 3 s of waiting (timeout): the lock is held for the whole write.
touch "$T/claim"
out=$(note "$C1" 'fix card filed' 2>&1) || fail "note $C1 'fix card filed' with a claim by sess-2 under way failed: $out"
rm -f "$T/claim"
[ "$(cat "$T/claimrc")" != 0 ] && [ "$(cut -d' ' -f1 "$FD/session")" = sess-1 ] \
  || fail "a claim by sess-2 made while note $C1 'fix card filed' was written ended (exit $(cat "$T/claimrc")) and moved the role to $(cut -d' ' -f1 "$FD/session"): $(cat "$T/claimout")"
asks > /dev/null

# The watcher renews the notes of alpha at a poll while the recorded Claude process holds the marked session; once a
# /resume there opened another session (sessions/<pid>.json names sess-7, the mark still sess-1), it renews nothing,
# so the notes end on the host. The real watcher, one poll (--once): renewnotes is run by its poll loop, which a direct
# call would leave out; its snapshot asks fail (exit 3), which this case does not look at.
poll() { CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --once > /dev/null 2>&1; }
poll; [ "$(grep renew "$T/asks")" = "alpha|$M|foreman note sess-1 renew"$'\n'"alpha-x|$M-x|foreman note sess-1 renew" ] \
  || fail "a poll with sess-1 in its process did not renew the notes of alpha and alpha-x once each: $(asks)"
asks > /dev/null
session sess-7
poll; [ -z "$(grep renew "$T/asks")" ] || fail "a poll after a /resume of sess-7 in the Foreman's process renewed the notes of sess-1: $(asks)"
session sess-1

# A new Foreman session starts noted anew.
echo 'sess-2 2026-11-25T12:00:00Z' > "$FD/session"; session sess-2
out=$(note "$C2" 'fix card filed' 2>&1) || fail "note $C2 'fix card filed' in the new Foreman's session sess-2 failed: $out"
[ "$(cat "$FD/noted")" = $'sess-2\nalpha' ] || fail "note $C2 in session sess-2 kept the list of sess-1: $(cat "$FD/noted")"
# A card of so_lo.1 is c...-so-lo-1-<issue>: the engine makes each character of the repo but a letter or digit "-"
# (CTAG, lib/paths.sh), and so-lo-1 has the same tag. The first that has the card keeps the note, and no other is asked.
asks > /dev/null
out=$(note c20261125T110000-so-lo-1-4 'hand run' 2>&1) || fail "note c20261125T110000-so-lo-1-4 'hand run', a card of so-lo-1, was refused: $out"
a=$(asks); [ "${a%%|*}" = so-lo-1 ] && [ "$(wc -l <<<"$a")" = 1 ] \
  || fail "note c20261125T110000-so-lo-1-4 'hand run', a card of so-lo-1, did not ask so-lo-1 alone: $a"
# Bugs it catches: the record looked for by the repo's own name, so a card of so_lo.1 was refused; and the note sent to
# the first repo with the tag only, which has no such card (exit 4), though so_lo.1 holds the card blocked.
touch "$T/none-so-lo-1"
out=$(note c20261125T110000-so-lo-1-5 'hand run' 2>&1) || fail "note c20261125T110000-so-lo-1-5 'hand run', a card of so_lo.1 and not of so-lo-1, was refused: $out"
a=$(asks); [ "$(cut -d'|' -f1 <<<"$a" | tr '\n' ' ')" = 'so-lo-1 so_lo.1 ' ] && tail -n 1 "$FD/noted" | grep -qxF so_lo.1 \
  || fail "note c20261125T110000-so-lo-1-5 'hand run' did not ask so-lo-1, then so_lo.1, and list so_lo.1 in noted: asks $a, noted $(cat "$FD/noted")"
touch "$T/none-so_lo.1"
out=$(note c20261125T110000-so-lo-1-6 'hand run' 2>&1) && fail "note c20261125T110000-so-lo-1-6 'hand run', a card of neither so-lo-1 nor so_lo.1, was taken: $out"
[[ $out == *'has no card'* ]] || fail "note c20261125T110000-so-lo-1-6 'hand run', a card of neither repo with its tag, does not say why: $out"
rm -f "$T"/none-*; asks > /dev/null

# A card ID that is not one, or no text, is a usage error.
note 'not-a-card' 'x' > /dev/null 2>&1; [ $? = 2 ] || fail "note 'not-a-card' x did not exit 2"
note "$C1" --ask '  ' > /dev/null 2>&1; [ $? = 2 ] || fail "note $C1 --ask '  ' (no text) did not exit 2"
echo "ok [note]"
