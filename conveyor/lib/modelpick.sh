# SPDX-License-Identifier: Apache-2.0
# The rule Pick settings (the control record's rules.pick: off, shadow or on; off by default). card() asks
# modelpick() once, after the split check and before the worktree, for an issue of its own (not a main-red fix card,
# issue 0, nor a branch); the slices of a split issue are issues of their own, so each gets its own pick. Code
# decides, with no model call: the card's group, from its issue, and the builder the rule chooses for that group: the
# project's builder, or the challenger on a trial (below); when the owner set the issue's builder (`control card
# <issue> builder`), the choice is the owner's, by "owner". In shadow the pick changes nothing about which model builds
# the card: seat() gives the card its builder, as with the rule off.
# The group is "<size> <kind>". size is small when the issue is under each of the pack's split thresholds (SPLITSIZE
# and split.doneWhen, split.files, split.areas, split.chars, as splitcheck() measures it, lib/slices.sh), else large.
# kind is pipeline when its title or body names one of the pack's pipelineFiles or a file under one (onpipeline(),
# lib/followups.sh, which reads a directory or a file with no extension too, as SPLITSIZE's files do not); else docs
# when it has the label documentation, or names files and each is a Markdown file or a file under docs/; else code.
# A trial (the rule On only): a card of an eligible group (small docs or small code: small, and names no pipeline
# file), picked by auto, whose issue number is a multiple of 5 (1 eligible card in 5) builds on the challenger
# (PICKTRIAL) with trial: true, through PICKSEAT, card()'s, which seat() (lib/control.sh) takes as the issue's builder
# while the owner sets none for the issue.
# It does not when the project's builder is the challenger already, when the pack does not allow the challenger for
# the builder, when the challenger's account is at the weekly limit guard, when another trial card is in flight (one at a time: the trial claim, below), when a trial card of the
# issue was blocked (its retry, by `review-retry` or by hand, builds on the default; the rule adds no retry of its
# own), or when the group's challenger is dropped: two trial cards of the group were blocked. Those blocked lines,
# in the card records and the retried lines, are the record of the drop; the snapshot lists the dropped groups
# (cost.trials, lib/snapshot.sh) for the Board. The review and judge of a trial card stay at the defaults.
# The trial claim (trial.card in the state folder, read and written under its flock) names the newest trial card; it
# is in flight while its lines in the card records have none that ends a card (landed, closed, blocked; not filed,
# which comes before the landing). The claim is written before the card's first line with its pick, so two cards picked at once never both take the trial.
# The pick goes on each line card() writes from then on, up to its end (PICK and PICKCARD, which line() reads,
# lib/records.sh; a stopped or blocked line the loop writes outside card() takes it from the card's lines,
# heldpick(); the push's lines, written after the card has ended, have none):
# {group, choice: {model, effort} of the builder, by: owner or auto, trial, mode: the rule, shadow or on}, and on a
# trial card whose staged change touches pipeline files, pipeline: those files (trialflag(), lib/push.sh; the Board flags it). A
# later card of the same issue (a retry, or a stop and a new pick) reuses the newest pick that a line of the issue
# holds, in the card records or the retried lines, so a restart keeps its group and choice; only the owner's setting
# is put over it, as that always wins (and a pick the owner had set, whose setting is gone since, takes the rule's
# choice again), and a trial pick is checked for its trial again, as above. An issue that cannot be read gets no
# pick, and the card goes on.
PICKTRIAL='{"model":"claude-sonnet-5-5","effort":"medium"}'
# shellcheck disable=SC2034 # PICK, PICKCARD and PICKSEAT are card()'s, read by line() in lib/records.sh and seat() in lib/control.sh
modelpick() { # <card> <issue>: sets card()'s PICK, PICKCARD and PICKSEAT
  local c=${CARDCTL:-} rule old b by=auto issue size t1 t2 t3 t4 pipe group
  [ -n "$c" ] || c=$(ctl 2>/dev/null) || return 0
  rule=$(jq -r '.rules.pick // "off"' <<<"$c" 2>/dev/null)
  [ "$rule" = shadow ] || [ "$rule" = on ] || return 0
  b=$(seat builder "$c" | jq -c '{model, effort}') && [ -n "$b" ] || { echo "conveyor: card $1: no builder to record in its pick" >&2; return 0; }
  ! jq -e --arg n "$2" '.cards[$n].builder | objects' <<<"$c" >/dev/null 2>&1 || by=owner
  old=$({ stdb ask issue retried "$2" -- issue cards "$2"; } 2>/dev/null | jq -cs --argjson n "$2" \
    '[.[] | objects | select(.issue == $n and (.pick | type) == "object")] | sort_by(.time) | last | .pick // empty' 2>/dev/null)
  if [ -n "$old" ]; then
    PICK=$(jq -c --arg m "$rule" --arg by "$by" --argjson b "$b" '.mode = $m | del(.pipeline) | if $by == "owner" or .by == "owner" then .by = $by | .choice = $b | .trial = false else . end' <<<"$old") || return 0
    PICKCARD=$1
    ! jq -e .trial <<<"$PICK" >/dev/null || picktrial "$1" "$2" "$c" "$b"
    return 0
  fi
  issue=$(gh issue view "$2" --json number,title,body,labels 2>/dev/null) && jq -e 'objects | .number' <<<"$issue" >/dev/null 2>&1 || return 0
  size=$(jq -c --arg area "$AREA" "$SPLITSIZE" <<<"$issue") && packget split.doneWhen t1 split.files t2 split.areas t3 split.chars t4 pipelineFiles pipe || return 0
  group=$(jq -r --argjson t "[$t1,$t2,$t3,$t4]" 'if (.doneWhen | length) < $t[0] and (.files | length) < $t[1] and .areas < $t[2] and .chars < $t[3] then "small" else "large" end' <<<"$size") || return 0
  if [ -n "$(onpipeline "$(jq -r '(.title // "") + "\n" + (.body // "")' <<<"$issue")" <<<"$pipe")" ]; then group+=' pipeline'
  elif jq -e --argjson s "$size" 'any(.labels[]?; .name == "documentation") or ($s.files | length > 0 and all(.[]; test("\\.md$") or startswith("docs/")))' <<<"$issue" >/dev/null; then group+=' docs'
  else group+=' code'; fi
  PICK=$(jq -cn --arg g "$group" --argjson b "$b" --arg by "$by" --arg m "$rule" '{group: $g, choice: $b, by: $by, trial: false, mode: $m}') || return 0
  PICKCARD=$1
  picktrial "$1" "$2" "$c" "$b"
}
# <card> <issue> <control record> <the project's builder>: makes PICK a trial on the challenger, with PICKSEAT set,
# when the rules above allow it; else a pick on the project's builder, with no PICKSEAT. Fails on none of them.
# shellcheck disable=SC2034 # PICKSEAT is card()'s, read by seat() in lib/control.sh
picktrial() {
  local s lines why='' claim=${STATE%/*}/trial.card
  PICKSEAT=''
  PICK=$(jq -c --argjson b "$4" '.trial = false | .choice = $b' <<<"$PICK") || return 0
  [ "$(jq -r .mode <<<"$PICK")" = on ] && [ "$(jq -r .by <<<"$PICK")" = auto ] && [ $(($2 % 5)) = 0 ] \
    && jq -e '.group | IN("small docs", "small code")' <<<"$PICK" >/dev/null && [ "$4" != "$PICKTRIAL" ] || return 0
  # The blocked trial cards, of every issue: this issue's, and the group's (a drop at two).
  lines=$({ stdb ask lines cards; stdb ask lines retried; } 2>/dev/null) || return 0
  why=$(jq -rs --argjson n "$2" --arg g "$(jq -r .group <<<"$PICK")" '[.[] | objects | select(.step == "blocked" and .pick.trial == true)]
    | if any(.[]; .issue == $n) then "a trial card of the issue was blocked: its retry builds on the default"
      elif ([.[] | select(.pick.group == $g) | .card] | unique | length) >= 2 then "two trial cards of the group were blocked: its challenger is dropped"
      else "" end' <<<"$lines") || return 0
  [ -z "$why" ] || { echo "conveyor: card $1: no trial: $why" >&2; return 0; }
  # The challenger the pack allows for the builder, as seat() gives it (else seat() keeps the project's builder).
  PICKSEAT=$PICKTRIAL
  s=$(SEATCARD=$2 seat builder "$3" | jq -c '{model, effort}') && [ "$s" = "$PICKTRIAL" ] || { PICKSEAT=''; return 0; }
  # The weekly limit guard, on the trial's seats: pick read the default builder's, which may run on no Claude account
  # (subaccts(), lib/paths.sh), so the account the challenger runs on is asked for here; one at the guard, no trial.
  [ "$(state "$3" "$(SEATCARD=$2 guardread "$3" ask | jq -r '.pct // empty')")" != "paused by guard" ] \
    || { echo "conveyor: card $1: no trial: the challenger's account is at the weekly limit guard" >&2; PICKSEAT=''; return 0; }
  # One trial card in flight: the claim is checked and taken under its lock.
  # shellcheck disable=SC2094 # the claim is read and then written while its lock is held
  if ( flock 9 || exit 1
       o=$(head -n 1 "$claim" 2>/dev/null)
       [ -z "$o" ] || [ "$o" = "$1" ] || ! stdb ask card "$o" 2>/dev/null | jq -es --arg c "$o" \
         'map(select(.card == $c)) | length > 0 and (any(.step | IN("landed", "closed", "blocked")) | not)' >/dev/null 2>&1 \
         || { echo "conveyor: card $1: no trial: trial card $o is in flight" >&2; exit 1; }
       printf '%s\n' "$1" > "$claim" ) 9>>"$claim"; then
    PICK=$(jq -c --argjson s "$PICKTRIAL" '.trial = true | .choice = $s' <<<"$PICK") || PICKSEAT=''
  else PICKSEAT=''; fi
}
