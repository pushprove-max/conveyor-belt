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
# own), or when the group's challenger is dropped: two trial cards of the group were blocked after the owner's last
# decision on it (`control pick`, below), or the owner dropped it. Those blocked lines,
# in the card records and the retried lines, are the record of the drop; the snapshot lists the dropped groups
# (cost.trials, lib/snapshot.sh) for the Board. The review and judge of a trial card stay at the defaults.
# The owner's decision (`control pick <group> promote|keep|drop`, the control record's picks): the snapshot asks for
# it in Needs you once ten trial cards of a group have ended since the last one (needsYou.pick); the rule never
# promotes by itself. keep: the trials go on. drop: no more trials in the group. promote: the group's auto cards build
# on the challenger, 1 in 5 on the project's builder (pickpromote()), with no trials. With the rule On, a kept
# snapshot that finds a promoted group's cards cost more per landed card than its default cards sets the rule to
# shadow, with a Needs you line (pickback(), lib/control.sh).
# The trial claim (trial.card in the state folder, read and written under its flock) names the newest trial card; it
# is in flight while its lines in the card records have none that ends a card (landed, closed, blocked; not filed,
# which comes before the landing). The claim is written before the card's first line with its pick, so two cards picked at once never both take the trial.
# The pick goes on each line card() writes from then on, up to its end (PICK and PICKCARD, which line() reads,
# lib/records.sh; a stopped or blocked line the loop writes outside card() takes it from the card's lines,
# heldpick(); the push's lines, written after the card has ended, have none):
# {group, choice: {model, effort} of the builder, by: owner or auto, trial, mode: the rule, shadow or on}, promoted:
# true on a card of a promoted group that builds on the challenger (pickpromote(); the snapshot's cost check counts it
# by this, not by its choice, which a project's builder can share), and on a
# trial card whose staged change touches pipeline files, pipeline: those files (trialflag(), lib/push.sh; the Board flags it). A
# later card of the same issue (a retry, or a stop and a new pick) reuses the newest pick that a line of the issue
# holds, in the card records or the retried lines, so a restart keeps its group and choice; only the owner's setting
# is put over it, as that always wins (and a pick the owner had set, whose setting is gone since, takes the rule's
# choice again), and a trial pick is checked for its trial again, as above. An issue that cannot be read gets no
# pick, and the card goes on.
PICKTRIAL='{"model":"claude-sonnet-5-5","effort":"medium"}'
# shellcheck disable=SC2034 # PICK, PICKCARD and PICKSEAT are card()'s, read by line() in lib/records.sh and seat() in lib/control.sh
modelpick() { # <card> <issue>: sets card()'s PICK, PICKCARD and PICKSEAT
  local c=${CARDCTL:-} rule old b by=auto issue size t1 t2 t3 t4 pipe group back
  [ -n "$c" ] || c=$(ctl 2>/dev/null) || return 0
  rule=$(jq -r '.rules.pick // "off"' <<<"$c" 2>/dev/null)
  [ "$rule" = shadow ] || [ "$rule" = on ] || return 0
  # The rule's own return to shadow (pickback(), lib/control.sh): the kept snapshot (the one the Board reads,
  # commands/snapshot.sh) finds that a group's promoted cards cost more per landed card than its default cards
  # (cost.trials.groups' over), on the owner's promote that stands now: a snapshot built before a later decision
  # does not count. This card is picked in shadow too.
  if [ "$rule" = on ] && back=$(jq -r --argjson c "$c" 'first(.cost.trials.groups[]? | select(.over == true and .decidedAt == $c.picks[.group].at) | .back) // empty' \
      "${STATE%/*}/snapshot.json" 2>/dev/null) && [ -n "$back" ]; then
    echo "conveyor: card $1: $back" >&2
    locked pickback "$back" || echo "conveyor: card $1: the rule Pick settings could not be set to shadow" >&2
    rule=shadow
  fi
  b=$(seat builder "$c" | jq -c '{model, effort}') && [ -n "$b" ] || { echo "conveyor: card $1: no builder to record in its pick" >&2; return 0; }
  ! jq -e --arg n "$2" '.cards[$n].builder | objects' <<<"$c" >/dev/null 2>&1 || by=owner
  old=$({ stdb ask issue retried "$2" -- issue cards "$2"; } 2>/dev/null | jq -cs --argjson n "$2" \
    '[.[] | objects | select(.issue == $n and (.pick | type) == "object")] | sort_by(.time) | last | .pick // empty' 2>/dev/null)
  if [ -n "$old" ]; then
    PICK=$(jq -c --arg m "$rule" --arg by "$by" --argjson b "$b" '.mode = $m | del(.pipeline) | if $by == "owner" or .by == "owner" then .by = $by | .choice = $b | .trial = false | del(.promoted) else . end' <<<"$old") || return 0
    PICKCARD=$1
    if pickpromote "$1" "$2" "$c" "$b"; then :
    elif jq -e .trial <<<"$PICK" >/dev/null; then picktrial "$1" "$2" "$c" "$b"
    # A promoted card started again once its group is no longer promoted builds on the project's builder: so does its pick.
    elif jq -e '.promoted == true' <<<"$PICK" >/dev/null; then
      PICK=$(jq -c --argjson b "$b" '.choice = $b | del(.promoted)' <<<"$PICK") || :
    fi
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
  pickpromote "$1" "$2" "$c" "$b" || picktrial "$1" "$2" "$c" "$b"
}
# <card> <issue> <control record> <the project's builder>: with the rule On, a card picked by auto of an eligible group
# the owner promoted (`control pick <group> promote`) builds on the challenger, through PICKSEAT as a trial card does,
# with trial false and promoted true; the card of an issue whose number is a multiple of 5 (1 card in 5 of the group) stays on the
# project's builder, as does any card when challenger() finds the challenger not allowed or at the guard. There are
# no trials in a promoted group. Fails, changing nothing, when the group is not promoted: picktrial() decides then.
pickpromote() {
  [ "$(jq -r .mode <<<"$PICK")" = on ] && [ "$(jq -r .by <<<"$PICK")" = auto ] \
    && jq -e --argjson c "$3" '.group as $g | ($g | IN("small docs", "small code")) and $c.picks[$g].decision == "promote"' <<<"$PICK" >/dev/null || return 1
  PICKSEAT=''
  PICK=$(jq -c --argjson b "$4" '.trial = false | .choice = $b | del(.promoted)' <<<"$PICK") || return 0
  [ $(($2 % 5)) != 0 ] && [ "$4" != "$PICKTRIAL" ] && challenger "$1" "$2" "$3" || return 0
  PICK=$(jq -c --argjson s "$PICKTRIAL" '.choice = $s | .promoted = true' <<<"$PICK") || PICKSEAT=''
}
# <card> <issue> <control record>: sets PICKSEAT to the challenger when seat() gives it for the builder (the pack
# allows it for the builder) and its Claude account is not at the weekly limit guard; else fails, PICKSEAT empty.
challenger() {
  local s
  PICKSEAT=$PICKTRIAL
  s=$(SEATCARD=$2 seat builder "$3" | jq -c '{model, effort}') && [ "$s" = "$PICKTRIAL" ] || { PICKSEAT=''; return 1; }
  # The weekly limit guard, on the challenger's seats: pick read the default builder's, which may run on no Claude
  # account (subaccts(), lib/paths.sh), so the account the challenger runs on is asked for here.
  [ "$(state "$3" "$(SEATCARD=$2 guardread "$3" ask | jq -r '.pct // empty')")" != "paused by guard" ] \
    || { echo "conveyor: card $1: not on the challenger: its account is at the weekly limit guard" >&2; PICKSEAT=''; return 1; }
}
# <card> <issue> <control record> <the project's builder>: makes PICK a trial on the challenger, with PICKSEAT set,
# when the rules above allow it; else a pick on the project's builder, with no PICKSEAT. Fails on none of them.
# shellcheck disable=SC2034 # PICKSEAT is card()'s, read by seat() in lib/control.sh
picktrial() {
  local lines why='' claim=${STATE%/*}/trial.card
  PICKSEAT=''
  PICK=$(jq -c --argjson b "$4" '.trial = false | .choice = $b | del(.promoted)' <<<"$PICK") || return 0
  [ "$(jq -r .mode <<<"$PICK")" = on ] && [ "$(jq -r .by <<<"$PICK")" = auto ] && [ $(($2 % 5)) = 0 ] \
    && jq -e '.group | IN("small docs", "small code")' <<<"$PICK" >/dev/null && [ "$4" != "$PICKTRIAL" ] || return 0
  # The blocked trial cards, of every issue: this issue's, and the group's (a drop at two), counted from the owner's
  # last decision on the group (`control pick`): after keep, the blocks before it no longer drop the challenger.
  lines=$({ stdb ask lines cards; stdb ask lines retried; } 2>/dev/null) || return 0
  why=$(jq -rs --argjson n "$2" --arg g "$(jq -r .group <<<"$PICK")" --argjson c "$3" '($c.picks[$g].at // "") as $at
    | [.[] | objects | select(.step == "blocked" and .pick.trial == true)]
    | if any(.[]; .issue == $n) then "a trial card of the issue was blocked: its retry builds on the default"
      elif ([.[] | select(.pick.group == $g and (.time // "") > $at) | .card] | unique | length) >= 2 then "two trial cards of the group were blocked: its challenger is dropped"
      else "" end' <<<"$lines") || return 0
  [ -n "$why" ] || ! jq -e --argjson c "$3" '$c.picks[.group].decision == "drop"' <<<"$PICK" >/dev/null || why="the owner dropped the group's challenger"
  [ -z "$why" ] || { echo "conveyor: card $1: no trial: $why" >&2; return 0; }
  # The challenger the pack allows for the builder, as seat() gives it (else seat() keeps the project's builder), on
  # an account not at the weekly limit guard.
  challenger "$1" "$2" "$3" || return 0
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
