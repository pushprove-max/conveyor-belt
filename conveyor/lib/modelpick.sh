# SPDX-License-Identifier: Apache-2.0
# The rule Pick settings (the control record's rules.pick: off, shadow or on; off by default). card() asks
# modelpick() once, after the worktree is made (cardtree(), lib/card.sh) and the split check, and before the build, for an issue of its own (not a main-red fix card,
# issue 0, nor a branch); the slices of a split issue are issues of their own, so each gets its own pick. Code
# decides the card's group, from its issue, and the builder the rule chooses for that group: the project's builder,
# or the challenger on a trial (below); when the owner set the issue's builder (`control card <issue> builder`), the
# choice is the owner's, by "owner". Then the judge picks the card's three seats, fitted to the pack (pickjudge(),
# below), and with the rule On a card that is no trial nor promoted builds on the judge's builder, which is then its
# choice, unless the rule keeps it on the project's builder (a promoted group's card in the share, a blocked trial's
# retry). In shadow the pick changes nothing about which models run the card: seat() gives the card its seats, as
# with the rule off.
# The group is "<size> <kind>". size is small when the issue is under each of the pack's split thresholds (SPLITSIZE
# and split.doneWhen, split.files, split.areas, split.chars, as splitcheck() measures it, lib/slices.sh), else medium
# when it is under twice each of them, else large.
# kind is pipeline when its title or body names one of the pack's pipelineFiles or a file under one (onpipeline(),
# lib/followups.sh, which reads a directory or a file with no extension too, as SPLITSIZE's files do not); else docs
# when it has the label documentation, or names files and each is a Markdown file or a file under docs/; else code.
# A trial (the rule On only): a card of an eligible group (PICKELIGIBLE: small docs or small code, and a medium group
# the owner added; none names a pipeline file), picked by auto, whose issue number is a multiple of 5 (1 eligible card
# in 5) builds on the group's challenger (PICKTRIAL, or the next one the owner put on trial) with trial: true, through PICKSEAT, card()'s, which seat() (lib/control.sh) takes as the issue's builder
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
# on the challenger, 1 in 5 on the project's builder (pickpromote()), with no trials. Two more decisions, each the
# owner's only (control()): add, on a medium group, makes it eligible (else its cards get the defaults); next, on a
# promoted group, keeps its promoted cards on that challenger and makes the card in the share a trial of the next one
# on PICKLADDER, which the next promote, keep or drop decides on (a drop goes back to the promoted one). With the rule On, a kept
# snapshot that finds a promoted group's cards cost more per landed card than its default cards sets the rule to
# shadow, with a Needs you line (pickback(), lib/control.sh).
# The trial claim (trial.card in the state folder, read and written under its flock) names the newest trial card; it
# is in flight while its lines in the card records have none that ends a card (landed, closed, blocked; not filed,
# which comes before the landing) and it has a worktree line or the process that claimed it runs. The claim is written before the card's first line with its pick, so two cards picked at once never both take the trial.
# The pick goes on each line card() writes from then on, up to its end (PICK and PICKCARD, which line() reads,
# lib/records.sh; a stopped or blocked line the loop writes outside card() takes it from the card's lines,
# heldpick(); the push's lines, written after the card has ended, have none):
# {group, choice: {model, effort} of the builder, by: owner or auto, trial, mode: the rule, shadow or on}, promoted:
# true on a card of a promoted group that builds on the challenger (pickpromote(); the snapshot's cost check counts it
# by this, not by its choice, which a project's builder can share), seats: {reviewer, judge} the seats the owner
# promoted from a replay result that the card runs on (pickseats(), below), asked: the judge's pick of the three seats
# (pickjudge(), below), trialEffort: the effort a trial card builds at when the judge's is not its choice's, and on a
# trial card whose staged change touches pipeline files, pipeline: those files (trialflag(), lib/push.sh; the Board flags it). A
# later card of the same issue (a retry, or a stop and a new pick) reuses the newest pick that a line of the issue
# holds, in the card records or the retried lines, so a restart keeps its group and trial; only the owner's setting
# is put over it, as that always wins (and a pick the owner had set, whose setting is gone since, takes the rule's
# choice again), and a trial pick is checked for its trial again, as above. A pick that is no trial nor promoted
# takes the builder the owner set for the issue, or else the project's, as its choice again, which the judge's new
# answer then moves only with the rule On and when the owner set none (pickjudge()). Its pipeline and trialEffort are
# dropped: each is this card's own, set again when it holds (a retry that is no longer a trial has no trialEffort). An issue that cannot be read gets no
# pick, and the card goes on.
PICKTRIAL='{"model":"claude-sonnet-5-5","effort":"medium"}'
# The challengers, in order: the first is PICKTRIAL; each next one is cheaper, or the same model at a lower effort.
# `control pick <group> next`, on a promoted group, starts trials of the one after the group's promoted challenger.
# shellcheck disable=SC2034 # read by control() in lib/control.sh
PICKLADDER='[{"model":"claude-sonnet-5-5","effort":"medium"},{"model":"claude-sonnet-5-5","effort":"low"},{"model":"claude-haiku-5-5","effort":"medium"},{"model":"claude-haiku-5-5","effort":"low"}]'
# The groups the rule tries challengers in: small docs and small code, and each medium group the owner added
# (`control pick medium <docs|code> add`, a key of the control record's picks). jq, on a group name, with $c the record.
PICKELIGIBLE='def eligible($c): IN("small docs", "small code") or (startswith("medium ") and ($c.picks[.] | objects) != null);'
# shellcheck disable=SC2034 # PICK, PICKCARD, PICKSEAT and PICKSEATS are card()'s, read by line() in lib/records.sh and seat() in lib/control.sh
modelpick() { # <card> <issue>: sets card()'s PICK, PICKCARD and PICKSEAT
  local c=${CARDCTL:-} rule old a b by=auto issue size t1 t2 t3 t4 pipe group back bk PICKHOLD=''
  [ -n "$c" ] || c=$(ctl 2>/dev/null) || return 0
  rule=$(jq -r '.rules.pick // "off"' <<<"$c" 2>/dev/null)
  [ "$rule" = shadow ] || [ "$rule" = on ] || return 0
  # The rule's own return to shadow (pickback(), lib/control.sh): the kept snapshot (the one the Board reads,
  # commands/snapshot.sh) finds that a group's promoted cards cost more per landed card than its default cards
  # (cost.trials.groups' over), on the owner's promote that stands now: a snapshot built before a later decision
  # does not count. This card is picked in shadow too. pickback() checks that decision again on the record as it is
  # now: a keep or drop since this card read its record leaves the rule and this card as they were.
  if [ "$rule" = on ] && back=$(jq -c --argjson c "$c" 'first(.cost.trials.groups[]? | select(.over == true and .decidedAt == $c.picks[.group].at)) // empty' \
      "${STATE%/*}/snapshot.json" 2>/dev/null) && [ -n "$back" ]; then
    locked pickback "$(jq -r .group <<<"$back")" "$(jq -r .decision <<<"$back")" "$(jq -r .decidedAt <<<"$back")" "$(jq -r .back <<<"$back")"; bk=$?
    if [ "$bk" = 0 ]; then echo "conveyor: card $1: $(jq -r .back <<<"$back")" >&2; rule=shadow
    elif [ "$bk" != 2 ]; then echo "conveyor: card $1: the rule Pick settings could not be set to shadow" >&2; rule=shadow; fi
  fi
  b=$(seat builder "$c" | jq -c '{model, effort}') && [ -n "$b" ] || { echo "conveyor: card $1: no builder to record in its pick" >&2; return 0; }
  # The owner's builder for the issue counts only when the pack allows its model the builder: one it no longer allows is
  # passed over (percard(), seat()), and the card builds on the project's, or on the pick's (a project builder of the
  # same model does not make it the owner's).
  modelsallowed a 2>/dev/null || a=null
  ! jq -e --arg n "$2" --argjson c "$c" "$OKMODELS"'$c.cards[$n].builder | objects | .model as $m | [$a | okmodels("builder")[][]] | index($m) != null' \
    --argjson a "$a" -n >/dev/null 2>&1 || by=owner
  old=$({ stdb ask issue retried "$2" -- issue cards "$2"; } 2>/dev/null | jq -cs --argjson n "$2" \
    '[.[] | objects | select(.issue == $n and (.pick | type) == "object")] as $l
    | ($l | sort_by(.time) | last | .pick // empty) + {hold: any($l[]; .step == "blocked" and .pick.trial == true)}' 2>/dev/null)
  if [ -n "$old" ]; then
    # Every later card of an issue whose trial card was blocked builds on the project's builder, not the judge's: also
    # a second retry, whose last pick is no trial, and a retry that picktrial() leaves before its check of the blocks.
    ! jq -e .hold <<<"$old" >/dev/null || PICKHOLD=1
    old=$(jq -c 'del(.hold)' <<<"$old") || return 0
    PICK=$(jq -c --arg m "$rule" --arg by "$by" --argjson b "$b" '.mode = $m | del(.pipeline, .trialEffort, .judged) | if $by == "owner" or .by == "owner" then .by = $by | .choice = $b | .trial = false | del(.promoted) else . end' <<<"$old") || return 0
    PICKCARD=$1
    if pickpromote "$1" "$2" "$c" "$b"; then :
    elif jq -e .trial <<<"$PICK" >/dev/null; then picktrial "$1" "$2" "$c" "$b"
    # Else the card builds on the builder the owner set for the issue, or the project's ($b), so does its pick, until
    # the judge's answer moves it (pickjudge(); never the owner's, and only while the rule is On: in Shadow the card
    # builds on $b): a promoted card started again once its group is no longer promoted, and a card whose earlier
    # choice was the judge's builder, so a judge that fails this time leaves no earlier choice the card does not build on.
    else
      PICK=$(jq -c --argjson b "$b" '.choice = $b | del(.promoted)' <<<"$PICK") || :
    fi
    pickseats "$2" "$c"; pickjudge "$1" "$2" "$c"; return 0
  fi
  issue=$(gh issue view "$2" --json number,title,body,labels 2>/dev/null) && jq -e 'objects | .number' <<<"$issue" >/dev/null 2>&1 || return 0
  size=$(jq -c --arg area "$AREA" "$SPLITSIZE" <<<"$issue") && packget split.doneWhen t1 split.files t2 split.areas t3 split.chars t4 pipelineFiles pipe || return 0
  group=$(jq -r --argjson t "[$t1,$t2,$t3,$t4]" 'def under($k): (.doneWhen | length) < $t[0] * $k and (.files | length) < $t[1] * $k and .areas < $t[2] * $k and .chars < $t[3] * $k;
    if under(1) then "small" elif under(2) then "medium" else "large" end' <<<"$size") || return 0
  if [ -n "$(onpipeline "$(jq -r '(.title // "") + "\n" + (.body // "")' <<<"$issue")" <<<"$pipe")" ]; then group+=' pipeline'
  elif jq -e --argjson s "$size" 'any(.labels[]?; .name == "documentation") or ($s.files | length > 0 and all(.[]; test("\\.md$") or startswith("docs/")))' <<<"$issue" >/dev/null; then group+=' docs'
  else group+=' code'; fi
  PICK=$(jq -cn --arg g "$group" --argjson b "$b" --arg by "$by" --arg m "$rule" '{group: $g, choice: $b, by: $by, trial: false, mode: $m}') || return 0
  PICKCARD=$1
  pickpromote "$1" "$2" "$c" "$b" || picktrial "$1" "$2" "$c" "$b"
  pickseats "$2" "$c"
  pickjudge "$1" "$2" "$c" "$issue"
}
# The judge's fit of its answer to what the pack allows each seat, in jq, with $r the pack's pick lists (pick: {<seat>:
# {<model>: {min, max}}}; {} when it sets none): effs($r; $e; $s; $g; $m), the efforts seat $s may take on model $m of
# program $g: those $g takes (EFFORTS, $e; none for an OpenCode builder) inside the model's range in the seat's list
# (either bound left out: none on that side; in the order of $e.opencode, which lists every effort); chosen($r; $e;
# $s), on models.allowed, the models the pick may give seat $s, each {model, g: its program, efforts}: those the pack
# allows the seat (okmodels: the builder's, or the review's for the reviewer and the judge) that its list names (all
# of them when the seat has no list), less one of a program with no effort in its range; fit(...; $m; $f), the effort
# for effort $f: $f itself, else the nearest end of the range (null: the program takes none).
# clamp($ans; $r; $e; $now; $pr), on models.allowed, is the answer fitted: each seat {model, effort, why, asked:
# {model, effort} as the judge gave them} and, when either was moved, clamp: why and what it was moved to. A model
# not chosen gives, for a seat with a list, the chosen one nearest in price to it (input and output per million
# tokens, in the price table $pr: {<model>: {input, output}}, pickcall()'s), else the project's model ($now, the
# seats in force) when it is chosen, else the first chosen; a seat with none chosen at all is {why, asked, clamp},
# and the project's seat stands.
PICKCLAMP="$OKMODELS"'def noeff($s; $g): $s == "builder" and $g == "opencode";
  def listed($r; $s): ($r[$s] | type) == "object";
  def effs($r; $e; $s; $g; $m): (if noeff($s; $g) then [] else $e[$g] // [] end) as $l | $e.opencode as $o
    | (($r[$s] | objects | .[$m] | objects) // {}) as $b | ($o | index($b.min // $o[0])) as $lo | ($o | index($b.max // $o[-1])) as $hi
    | $l | map(. as $f | ($o | index($f)) as $i | select($lo != null and $hi != null and $i >= $lo and $i <= $hi));
  def chosen($r; $e; $s): [okmodels(if $s == "builder" then "builder" else "reviewer" end) | to_entries[] | .key as $g | .value[] | . as $m
    | select((listed($r; $s) | not) or ($r[$s] | has($m))) | {model: $m, g: $g, efforts: effs($r; $e; $s; $g; $m)} | select(noeff($s; .g) or .efforts != [])];
  def fit($r; $e; $s; $g; $m; $f): effs($r; $e; $s; $g; $m) as $l | $e.opencode as $o
    | if $l == [] then null elif ($l | index($f)) != null then $f
      else (($o | index($f)) // -1) as $i | [$l[] | . as $x | select(($o | index($x)) <= $i)] | last // $l[0] end;
  def price($pr): ($pr[.] // $pr[sub("^opencode:"; "")]) | if type == "object" and (.input | type) == "number" and (.output | type) == "number" then .input + .output else null end;
  def clamp($ans; $r; $e; $now; $pr): . as $a | [("builder", "reviewer", "judge") as $s
    | ($ans[$s] | if type == "object" then . else {} end) as $q
    | ($a | chosen($r; $e; $s)) as $ok
    | (if listed($r; $s) and ($q.model | type) == "string" then ($q.model | price($pr)) as $p
        | if $p == null then null else [$ok[] | (.model | price($pr)) as $x | select($x != null) | {m: ., d: ($x - $p | if . < 0 then -. else . end)}] | min_by(.d) | .m? end
       else null end) as $near
    | (first($ok[] | select(.model == $q.model)) // $near // first($ok[] | select(.model == $now[$s].model)) // $ok[0]) as $m
    | {why: ($q.why | strings // null), asked: {model: ($q.model // null), effort: ($q.effort // null)}} as $w
    | {key: $s, value: (if $m == null then $w + {clamp: (if listed($r; $s) then "pick.\($s) names no model the pack allows the \($s) with an effort its program takes" else "the pack allows the \($s) no model" end) + ", so the project'"'"'s \($s) stands"}
        else fit($r; $e; $s; $m.g; $m.model; (if ($q.effort | type) == "string" then $q.effort else $now[$s].effort end)) as $f
          | {model: $m.model, effort: $f} + $w
          + (if $m.model == $q.model and $f == $q.effort then {}
             else {clamp: ([if $m.model == $q.model then empty elif ($q.model | type) != "string" then "the answer named no model for the \($s)"
                   elif listed($r; $s) then "\($q.model) is not one of the models pick.\($s) lets the pick give the \($s)"
                   else "\($q.model) is not a model the pack allows the \($s)" end,
                 if $f == $q.effort then empty
                 elif ($q.effort | type) != "string" then (if $m.model == $q.model then "the answer named no effort for the \($s)" else empty end)
                 elif noeff($s; $m.g) then "\($m.model) takes no effort"
                 else "\($q.effort) is not one of the efforts the \($s) may take on \($m.model) (\($m.efforts | join(", ")))" end]
                 | join("; ")) + ": \($m.model) at \($f // "no effort")"} end) end)}] | from_entries;'
# The effort one level above <effort> for a builder-seat session on <model> of <program> (a second fix round, session1()):
# the next effort its program takes, fitted to the range the pack's pick.builder list gives the model (fit()), so it is
# never above the range's top, even when <effort> is (a control record can set one the pack does not allow).
effortup() { # <program> <model> <effort>
  local r; packget pick r 2>/dev/null && [ -n "$r" ] || r='{}'
  jq -rn --argjson r "$r" --argjson e "$EFFORTS" --arg g "$1" --arg m "$2" --arg f "$3" "$PICKCLAMP"'($e[$g] // []) as $l | ($l | index($f)) as $i
    | (if $i == null then $f else $l[$i + 1] // $f end) as $t | fit($r; $e; "builder"; $g; $m; $t) // $f' 2>/dev/null || printf '%s\n' "$3"
}
# The judge's pick of the three seats (the rule Pick settings, Shadow or On, on a card modelpick() picked): the judge
# is asked once, as Pick for me asks it (pickcall(), lib/control.sh), and its answer fitted to the pack (PICKCLAMP)
# goes in the pick as asked: {builder, reviewer, judge, model: the judge's}, or {failed: why} when the issue cannot be
# read or the judge fails, times out or names no model for any seat; the card then builds on the project's seats, as
# it does in Shadow. The call is a card line of its own, step seats (ok or failed, with the call's model, effort, sec,
# tokens and usage, or unread), so its tokens and price count on the card. Each card asks the judge: a later card of
# the issue (a retry or a restart) asks again, and its answer replaces the asked of the pick it reuses.
# On, a card that is not a trial nor promoted, and whose builder the owner did not set, builds on the judge's builder
# (PICKSEAT, which then is its choice, and judged true in the pick: the snapshot's seatsof()), except a card the rule keeps on the project's builder (PICKHOLD, modelpick()'s,
# set by pickpromote() and by modelpick() itself): a promoted group's card in the share, which the snapshot's cost
# check compares the promoted cards with, and each later card of an issue whose trial card was blocked, which builds
# on the default; a trial card keeps its challenger, at the judge's effort fitted to its range in pick.builder (fit()), or
# its own effort fitted to the range when the judge fails (picktrial()): its choice stays the challenger, by which the
# snapshot counts the group's trials, and trialEffort is the effort it builds at when that is another. A card that
# is not a trial runs its review on the judge's reviewer and judge (PICKSEATS), each one the owner promoted from a
# replay result standing over it. A seat the owner set for the issue (`control card`) is used as set, whatever the judge answers (seat(), lib/control.sh). When
# the judge's seats run on a Claude account at the weekly limit guard, the card builds on the seats it had before, and
# asked.guard says so.
# shellcheck disable=SC2034 # PICKSEAT and PICKSEATS are card()'s, read by seat() in lib/control.sh
pickjudge() { # <card> <issue> <control record> [<issue json>]
  local asked issue=${4:-} a r k='' now x ok=ok s0=${PICKSEAT:-} ss0=${PICKSEATS:-} p0=$PICK PICKANS='' PICKMODEL='' PICKUSE='' PICKWHY='' PICKPRICES=''
  { [ -n "$issue" ] || issue=$(gh issue view "$2" --json number,title,body,labels 2>/dev/null); } && jq -e 'objects | .number' <<<"$issue" >/dev/null 2>&1 \
    || PICKWHY="the issue could not be read"
  # The judge is given only the models the pick may give each seat, each at the efforts of its range (chosen()).
  packget pick r 2>/dev/null && [ -n "$r" ] || r='{}'
  ! modelsallowed a || k=$(jq -c --argjson r "$r" --argjson e "$EFFORTS" "$PICKCLAMP"'{builder: chosen($r; $e; "builder"), reviewer: chosen($r; $e; "reviewer"), judge: chosen($r; $e; "judge")}' <<<"$a" 2>/dev/null) || k=''
  [ -n "$PICKWHY" ] || pickcall "$issue" "$3" "$k" || :
  if [ -z "$PICKWHY" ]; then
    if ! jq -e 'any(.[]; type == "object" and (.model | type == "string"))' <<<"$PICKANS" >/dev/null 2>&1; then PICKWHY="the judge's answer named no model for any seat: ${PICKANS:0:300}"
    else
      now=$(for x in builder reviewer judge; do SEATCARD='' seat "$x" "$3" || echo null; done | jq -cs '{builder: .[0], reviewer: .[1], judge: .[2]}')
      [ -n "$PICKPRICES" ] || PICKPRICES='{}'
      modelsallowed a && asked=$(jq -c --argjson q "$PICKANS" --argjson r "$r" --argjson e "$EFFORTS" --argjson now "$now" --arg m "$PICKMODEL" --argjson pr "$PICKPRICES" \
        "$PICKCLAMP"'clamp($q; $r; $e; $now; $pr) + {model: $m}' <<<"$a" 2>/dev/null) && [ -n "$asked" ] \
        || PICKWHY="the judge's answer could not be fitted to the models and efforts the pack allows"
    fi
  fi
  if [ -n "$PICKWHY" ]; then
    ok=failed; asked=$(jq -cn --arg w "$PICKWHY" '{failed: $w}')
    echo "conveyor: card $1: Pick settings: the card builds on the project's seats: $PICKWHY" >&2
  fi
  PICK=$(jq -c --argjson s "$asked" '.asked = $s' <<<"$PICK") || return 0
  [ -z "$PICKUSE" ] || record "$1" "$2" seats "$ok" "$(jq -c --arg w "$PICKWHY" '. + {reason: $w}' <<<"$PICKUSE")"
  # Shadow, or a failed ask: the seats stand as modelpick() left them.
  [ "$(jq -r .mode <<<"$PICK")" = on ] && ! jq -e '.asked.failed' <<<"$PICK" >/dev/null 2>&1 || return 0
  if jq -e '.trial == true' <<<"$PICK" >/dev/null && [ -n "${PICKSEAT:-}" ]; then
    modelsallowed a && x=$(jq -c --argjson p "$PICKSEAT" --argjson q "$(jq -c .asked.builder <<<"$PICK")" --argjson r "$r" --argjson e "$EFFORTS" "$PICKCLAMP"'
      first(chosen($r; $e; "builder")[] | select(.model == $p.model)) as $c
      | fit($r; $e; "builder"; $c.g; $c.model; ($q.asked.effort // $p.effort)) as $f | if $f == null then $p else $p + {effort: $f} end' <<<"$a" 2>/dev/null) && [ -n "$x" ] \
      && PICKSEAT=$x && PICK=$(jq -c --argjson s "$x" 'if .choice.effort == $s.effort then del(.trialEffort) else .trialEffort = $s.effort end' <<<"$PICK") || :
  elif [ -z "${PICKSEAT:-}" ] && [ -z "${PICKHOLD:-}" ] && [ "$(jq -r .by <<<"$PICK")" = auto ]; then
    x=$(jq -c '.asked.builder | select(.model != null) | {model, effort}' <<<"$PICK" 2>/dev/null)
    [ -z "$x" ] || { PICKSEAT=$x; PICK=$(jq -c --argjson s "$x" '.choice = $s | .judged = true' <<<"$PICK") || :; }
  fi
  jq -e '.trial == true' <<<"$PICK" >/dev/null && return 0
  r=${PICKSEATS:-}; [ -n "$r" ] || r='{}'
  x=$(jq -c --argjson p "$r" '[.asked | to_entries[] | select((.key | IN("reviewer", "judge")) and (.value.model != null)) | {key, value: (.value | {model, effort})}]
    | from_entries + $p' <<<"$PICK" 2>/dev/null) && [ "$x" != '{}' ] && PICKSEATS=$x || :
  # The weekly limit guard, on the judge's seats: pick read the project's, and a builder or reviewer moved to Claude
  # can run on an account the guard holds (cardaccts(), lib/paths.sh), so the accounts they run on are asked for here.
  [ "${PICKSEAT:-}${PICKSEATS:-}" != "$s0$ss0" ] && [ "$(state "$3" "$(SEATCARD=$2 guardread "$3" ask | jq -r '.pct // empty')")" = "paused by guard" ] || return 0
  x="the judge's seats run on a Claude account at the weekly limit guard, so the card builds on the project's seats"
  echo "conveyor: card $1: Pick settings: $x" >&2
  PICKSEAT=$s0; PICKSEATS=$ss0; PICK=$(jq -c --argjson s "$(jq -c .asked <<<"$PICK")" --arg w "$x" '.asked = $s + {guard: $w}' <<<"$p0") || :
}
# <issue> <control record>: the reviewer and judge seats the owner promoted from a replay result (`control pick
# <reviewer|judge> promote <model> [<effort>]`, picks.reviewer and picks.judge, whose choice the replay's line names),
# on a card of the rule On that is not a trial (a trial card's review and judge stay at the defaults): each one the
# owner did not set for the issue (`control card`, which always wins) goes in PICKSEATS, which seat() takes as the
# issue's, and in the pick's seats. With none promoted, the card has no seats and the defaults stand.
# shellcheck disable=SC2034 # PICKSEATS is card()'s, read by seat() in lib/control.sh
pickseats() {
  local s
  PICKSEATS=''
  s=$(jq -c --argjson c "$2" --arg n "$1" 'if .mode == "on" and .trial != true
      then [$c.picks // {} | to_entries[] | select((.key | IN("reviewer", "judge")) and $c.cards[$n][.key] == null) | {key, value: .value.choice}] | from_entries
      else {} end' <<<"$PICK") || return 0
  PICK=$(jq -c --argjson s "$s" 'del(.seats) | if $s == {} then . else .seats = $s end' <<<"$PICK") || return 0
  [ "$s" = '{}' ] || PICKSEATS=$s
}
# <card> <issue> <control record> <the project's builder>: with the rule On, a card picked by auto of an eligible group
# the owner promoted (`control pick <group> promote`) builds on the promoted challenger, through PICKSEAT as a trial card does,
# with trial false and promoted true; the card of an issue whose number is a multiple of 5 (1 card in 5 of the group) stays on the
# project's builder, or is a trial of the group's next challenger (picktrial()) while one is on trial, as any card
# stays when challenger() finds the challenger not allowed or at the guard. There are no other trials in a promoted
# group. Fails, changing nothing, when the group is not promoted: picktrial() decides then.
pickpromote() {
  local p
  [ "$(jq -r .mode <<<"$PICK")" = on ] && [ "$(jq -r .by <<<"$PICK")" = auto ] \
    && p=$(jq -c --argjson c "$3" --argjson t "$PICKTRIAL" "$PICKELIGIBLE"'.group as $g | $c.picks[$g] as $d
      | select($g | eligible($c)) | $d.promoted // (select($d.decision == "promote") | $d.challenger // $t)' <<<"$PICK") && [ -n "$p" ] || return 1
  PICKSEAT=''
  PICK=$(jq -c --argjson b "$4" '.trial = false | .choice = $b | del(.promoted)' <<<"$PICK") || return 0
  # In a group whose next challenger is on trial (promoted kept: `control pick <group> next`), the card in the share
  # is a trial of it, as picktrial() allows.
  if [ $(($2 % 5)) = 0 ]; then PICKHOLD=1; ! jq -e --argjson c "$3" '$c.picks[.group].promoted' <<<"$PICK" >/dev/null || picktrial "$1" "$2" "$3" "$4"; return 0; fi
  [ "$4" != "$p" ] && challenger "$1" "$2" "$3" "$p" || return 0
  PICK=$(jq -c --argjson s "$p" '.choice = $s | .promoted = true' <<<"$PICK") || PICKSEAT=''
}
# <card> <issue> <control record> <choice>: sets PICKSEAT to the choice when seat() gives it for the builder (the pack
# allows it for the builder) and its Claude account is not at the weekly limit guard; else fails, PICKSEAT empty.
challenger() {
  local s
  PICKSEAT=$4
  s=$(SEATCARD=$2 seat builder "$3" | jq -c '{model, effort}') && [ "$s" = "$4" ] || { PICKSEAT=''; return 1; }
  # The weekly limit guard, on the challenger's seats: pick read the default builder's, which may run on no Claude
  # account (subaccts(), lib/paths.sh), so the account the challenger runs on is asked for here.
  [ "$(state "$3" "$(SEATCARD=$2 guardread "$3" ask | jq -r '.pct // empty')")" != "paused by guard" ] \
    || { echo "conveyor: card $1: not on the challenger: its account is at the weekly limit guard" >&2; PICKSEAT=''; return 1; }
}
# The blocked trial cards, of every issue: this issue's, and the group's (a drop at two), counted from the owner's
# last decision on the group (`control pick`): after keep, the blocks before it no longer drop the challenger. A
# blocked line that the card's own later landed or pushed line follows (a landed card whose process died, blocked and
# then pushed) is no block, as the snapshot's trials.dropped does not count it either. Prints why the card gets no
# trial for them, else nothing; fails when the records cannot be read.
trialblocked() { # <issue> <group> <control record>
  local lines
  lines=$({ stdb ask lines cards; stdb ask lines retried; } 2>/dev/null) || return 1
  jq -rs --argjson n "$1" --arg g "$2" --argjson c "$3" '($c.picks[$g].at // "") as $at
    | [.[] | objects] as $a
    | (reduce range($a | length) as $i ({}; if $a[$i].step | IN("landed", "pushed") then .[$a[$i].card | tostring] = $i else . end)) as $ok
    | [range($a | length) as $i | $a[$i] | select(.step == "blocked" and .pick.trial == true and $i > ($ok[.card | tostring] // -1))]
    | if any(.[]; .issue == $n) then "a trial card of the issue was blocked: its retry builds on the default"
      elif ([.[] | select(.pick.group == $g and (.time // "") > $at) | .card] | unique | length) >= 2 then "two trial cards of the group were blocked: its challenger is dropped"
      else "" end' <<<"$lines"
}
# <card> <issue> <control record> <the project's builder>: makes PICK a trial on the challenger, with PICKSEAT set,
# when the rules above allow it; else a pick on the project's builder, with no PICKSEAT. Fails on none of them.
# shellcheck disable=SC2034 # PICKSEAT is card()'s, read by seat() in lib/control.sh
picktrial() {
  local why='' claim=${STATE%/*}/trial.card ch a r f g me st
  PICKSEAT=''
  PICK=$(jq -c --argjson b "$4" '.trial = false | .choice = $b | del(.promoted)' <<<"$PICK") || return 0
  # The group's challenger: the one its next decision put on trial, else PICKTRIAL.
  ch=$(jq -c --argjson c "$3" --argjson t "$PICKTRIAL" '$c.picks[.group].challenger // $t' <<<"$PICK") || return 0
  [ "$(jq -r .mode <<<"$PICK")" = on ] && [ "$(jq -r .by <<<"$PICK")" = auto ] && [ $(($2 % 5)) = 0 ] \
    && jq -e --argjson c "$3" "$PICKELIGIBLE"'.group | eligible($c)' <<<"$PICK" >/dev/null && [ "$4" != "$ch" ] || return 0
  g=$(jq -r .group <<<"$PICK") && why=$(trialblocked "$2" "$g" "$3") || return 0
  [ -n "$why" ] || ! jq -e --argjson c "$3" '$c.picks[.group].decision == "drop"' <<<"$PICK" >/dev/null || why="the owner dropped the group's challenger"
  [ -z "$why" ] || { echo "conveyor: card $1: no trial: $why" >&2; return 0; }
  # The challenger the pack allows for the builder, as seat() gives it (else seat() keeps the project's builder), on
  # an account not at the weekly limit guard.
  challenger "$1" "$2" "$3" "$ch" || return 0
  # A challenger that is not one of the builder's chosen models (chosen(): pick.builder, when the pack sets it), or
  # whose program takes no effort in its range there, has no trial, as it would build outside them: the card builds
  # as one that is no trial (pickjudge()). Else the trial builds at the challenger's effort fitted to its range
  # (fit()), also when the judge fails; pickjudge() then fits the judge's.
  packget pick r 2>/dev/null && [ -n "$r" ] || r='{}'
  if ! { modelsallowed a && f=$(jq -ce --argjson p "$ch" --argjson r "$r" --argjson e "$EFFORTS" "$PICKCLAMP"'
      first(chosen($r; $e; "builder")[] | select(.model == $p.model)) as $c
      | fit($r; $e; "builder"; $c.g; $c.model; $p.effort) as $f | select($f != null) | $p + {effort: $f}' <<<"$a" 2>/dev/null) && [ -n "$f" ]; }; then
    echo "conveyor: card $1: no trial: the challenger is not one of the models pick.builder lets the pick give the builder, at an effort its program takes" >&2; PICKSEAT=''; return 0
  fi
  # One trial card in flight: the claim is checked and taken under its lock. It names this card's process (pid, then
  # p_started's answer): a claimed card with no worktree line whose process is gone (the loop restarted before card()
  # wrote that line) holds it no more, as nothing ever ends that card. The blocks are counted again after the claim is
  # read: the card it names may have blocked since the count above, the group's second block.
  me=$BASHPID; st=$(p_started "$me")
  # shellcheck disable=SC2094 # the claim is read and then written while its lock is held
  if ( flock 9 || exit 1
       o=$(sed -n 1p "$claim" 2>/dev/null); op=$(sed -n 2p "$claim" 2>/dev/null); ot=$(sed -n 3p "$claim" 2>/dev/null)
       [ -z "$o" ] || [ "$o" = "$1" ] || ! stdb ask card "$o" 2>/dev/null | jq -es --arg c "$o" --argjson up "$(p_alive "$op" "$ot" && echo true || echo false)" \
         'map(select(.card == $c)) | length > 0 and (any(.step | IN("landed", "closed", "blocked")) | not) and ($up or any(.step == "worktree"))' >/dev/null 2>&1 \
         || { echo "conveyor: card $1: no trial: trial card $o is in flight" >&2; exit 1; }
       why=$(trialblocked "$2" "$g" "$3") && [ -z "$why" ] || { echo "conveyor: card $1: no trial: ${why:-the blocked trial cards could not be read}" >&2; exit 1; }
       printf '%s\n%s\n%s\n' "$1" "$me" "$st" > "$claim" ) 9>>"$claim"; then
    PICKSEAT=$f
    PICK=$(jq -c --argjson s "$ch" --argjson f "$f" '.trial = true | .choice = $s | if $f.effort == $s.effort then . else .trialEffort = $f.effort end' <<<"$PICK") || PICKSEAT=''
  else PICKSEAT=''; fi
}
