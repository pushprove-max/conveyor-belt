# upnext() in conveyor.sh, after DEPS, SEE and LEVEL: the open issues with no card, in pick order. Its arguments are named there.
($cards | map(.issue)) as $taken
    | map(.number) as $open | graph($cards) as $g | (if $all == "" then [] else cycles($cards) | add // [] end) as $cyc
    | ($cards | map(select(.step == "landed") | .followups // [] | .[])) as $ready
    | (if $only == null then null else ups($cards; $only) end) as $only
    | ($retried | map(.issue) | unique) as $again
    | ((($ENV.CONVEYOR_NOW // "" | tonumber?) // now) | localtime | .[3] != $sh) as $loud
    | map((.labels | map(.name)) as $l
      | select($only == null or (.number | IN($only[])))
      | select($l | index($built) | not)
      | select(.number | IN($taken[]) | not)
      | select($mode != "retried" or (.number | IN($again[])))
      | select(($l | index($fu) | not) or (.number | IN($ready[])) or (.body // "" | test("^Follow-up to #[0-9]+ \\(Conveyor card ") | not))
      | . + {later: ($l | index($fu) | not), p: level($l; $prio), rank: rank($l; $prio), again: (.number | IN($again[])),
             waits: waits($cards; $open), before: ($ctl.rules.visible != false and before($area; $np)), stuck: ($all != "" and (reach($g; .number) | any(IN($cyc[]))))})
    # forced: `control force` lets it past its open dependencies, only while the dependency guard is off.
    # hold: the control record holds it, or someone outside the project opened it (INSIDE) and the owner has not
    # released it (startSeen): held here too, before adopted() saves the hold, or when it cannot know who opened it.
    | map(. + {forced: (.waits != [] and $ctl.depGuard == false and (.number | IN($ctl.forced[]))),
        hold: ((.number | IN($ctl.held[])) or ((inside | not) and (.number | IN($ctl.startSeen[]) | not))), rule: (([.labels[].name | select(IN($ctl.rules.never[]))] | sort | .[0])
        // (if .later | not then (if $ctl.rules.followups then null else "follow-ups" end) elif $ctl.rules[.p] == false then .p else null end)
        // (if $loud and (.title // "" | startswith("Test-speed survey, ")) then "the survey hour" else null end)
        // (if .number | IN($guarded[]) then "the weekly limit guard" else null end))})
    | map(select($all != "" or ((.hold | not) and .rule == null and (.waits == [] or .forced) and (.before | not))))
    | sort_by(.number as $n | ($ctl.order | index($n)) // ($ctl.order | length), .later, .rank, .createdAt)
