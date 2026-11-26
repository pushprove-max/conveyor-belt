# SPDX-License-Identifier: Apache-2.0
# What the owner does to a card with no GitHub issue before the loop picks it: `control hold <card id>...`, `control
# release <card id>...` and `shut <card id>`. The card is an entry of $TACARDS (testcard(), lib/testaction.sh), and the
# pick (testpick()) reads that record under the lock of it: a card held here is passed over by the pick that comes
# after, and a card shut here is not there for it to take. Sourced by commands/control.sh and commands/shut.sh, after
# lib/testaction.sh.
# One lock, one write, all or nothing: with any card id of the list not fit for the action, nothing changes. hold: an entry
# not picked yet (card null); release: an entry that is held; shut: an entry not picked yet, which is taken off the
# record, and its list entries given back to their list (healsfree(), lib/followups.sh). Exit 2 and a line
# that names the card id, or exit 3 and no line (shut: the card is of another kind, which shut() reads), when one is not
# fit; 2 too for a shut of a part of a split issue (slices.sh), which its parent still waits for; 1 when the record could
# not be locked or written. The line also says how a blocked main-red fix card is stopped, as control() did for any card id of issue 0.
tcrefuse() { # <hold | release | shut> <card id>
  echo "conveyor: $2 is not $([ "$1" = hold ] && echo "a card with no GitHub issue that is waiting to be picked" || echo "a held card with no GitHub issue") (a blocked main-red fix card is given back with \`conveyor.sh retry <card id>\` or closed with \`conveyor.sh shut <card id>\`); nothing changed" >&2
}
testcardact() { # <hold | release | shut> <card id>...
  local act=$1 lock rec ids bad x; shift
  ids=$(jq -cn '$ARGS.positional' --args "$@")
  if [ ! -s "$TACARDS" ]; then
    [ "$act" != shut ] || return 3
    tcrefuse "$act" "$1"; return 2
  fi
  { exec {lock}>>"$TACARDS.lock"; } 2>/dev/null && flock "$lock" || { echo "conveyor: the record of the Tests page's cards could not be locked; nothing changed" >&2; return 1; }
  rec=$(jq -ce '.cards | arrays' "$TACARDS" 2>/dev/null) || rec='[]'
  bad=$(jq -r --arg a "$act" --argjson ids "$ids" '. as $r | first($ids[] | select(. as $c | any($r[]; .id == $c and (if $a == "release" then .held == true else .card == null end)) | not)) // empty' <<<"$rec")
  if [ -n "$bad" ]; then
    exec {lock}>&-
    [ "$act" != shut ] || return 3
    tcrefuse "$act" "$bad"; return 2
  fi
  if [ "$act" = shut ]; then
    bad=$(stdb ask lines cards | jq -rs --argjson ids "$ids" 'map(select(.step == "split" and any((.split.cards // [])[]; IN($ids[])))) | last | .issue // empty') \
      || { exec {lock}>&-; echo "conveyor: the card records could not be read; nothing changed" >&2; return 1; }
    # A part that splitcards() (lib/slices.sh) saved before splitcheck() wrote the split line: its entry names the issue.
    [ -n "$bad" ] || bad=$(jq -r --argjson ids "$ids" 'first(.[] | select((.id | IN($ids[])) and ((.label // "") | startswith("Split part of #"))) | .parent // empty) // empty' <<<"$rec")
    [ -z "$bad" ] || { exec {lock}>&-; echo "conveyor: $1 is a part of the split of issue #$bad, which waits for it; hold it with \`control hold $1\`, or close #$bad by hand first; nothing changed" >&2; return 2; }
  fi
  jq -c --argjson ids "$ids" --arg a "$act" '{cards: (if $a == "shut" then map(select(((.id | IN($ids[])) and .card == null) | not))
      else map(if .id | IN($ids[]) then (if $a == "hold" then .held = true else del(.held) end) else . end) end)}' <<<"$rec" > "$TACARDS.new" && mv -f "$TACARDS.new" "$TACARDS" \
    || { rm -f "$TACARDS.new"; exec {lock}>&-; echo "conveyor: the record of the Tests page's cards could not be written; nothing changed" >&2; return 1; }
  exec {lock}>&-
  for x; do
    # A card shut before it lands gives the list entries it holds back to their list (healsfree(), lib/followups.sh), as shut() does.
    [ "$act" != shut ] || healsfree "$x" 0 || echo "conveyor: card $x was shut, but the list entries it holds could not be given back to their list" >&2
    case $act in
      hold) echo "conveyor: card $x is held: it is not picked until \`control release $x\`" ;;
      release) echo "conveyor: card $x is released: it is picked in its turn" ;;
      shut) echo "conveyor: card $x was shut before it was picked; it is taken off the record and never picked" ;;
    esac
  done
}
