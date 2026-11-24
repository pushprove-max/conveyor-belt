# upnext() in conveyor.sh, after DEPS, SEE and LEVEL: the open issues with no card, in pick order. Its arguments are named there.
($cards | map(.issue)) as $taken
    # The graph, the landed issues and the lines that name follow-ups, each worked out once (DEPS): worked out again
    # for each open issue, they were most of a snapshot's time.
    | map(.number) as $open | graph($cards) as $g | (if $all == "" then [] else cyclesof($g) | add // [] end) as $cyc
    | landed($cards) as $done | ($cards | map(select(.followups))) as $fc
    | ($cards | map(select(.step == "landed") | .followups // [] | .[])) as $ready
    # The issues whose card is filing the slices of their split now: its newest line is the start of file (splitcheck(),
    # lib/slices.sh), written before the first slice is created; the split line comes once each is held or placed.
    | (reduce ($cards[] | select(.issue | type == "number")) as $l ({}; .[$l.issue | tostring] = ($l.step == "start" and $l.of == "file"))) as $filing
    # --only takes the slices of a split for size too (a grown line's filed, growcheck()), with those of a card `retry`
    # gave back (approved(): a parent blocked for the owner's yes), whose grown line is in $retried; they are no
    # followups for waits(), as each such slice depends on its parent, and would wait on itself. They are taken only once
    # their parent has landed: until then they wait on it, and a parent that blocked (for the owner's yes) kept the run
    # polling for a slice it could not build.
    # It takes the parts of a parent it names too (its GitHub sub-issues): the parent itself is never built, so without
    # them the run had nothing to build. Follow-ups and parts are taken in turn until neither adds an issue, so the
    # follow-up a part filed (a closed part too: it is not picked, as it is not open), and the parts of a follow-up, are
    # taken as well.
    # The records it grows from are built only for --only: a pick or snapshot without it never reads them.
    | . as $is | (if $only == null then null else
        ($cards | map(.followups //= (if .issue | IN($done[]) then .grown.filed else null end))
          + [$retried[] | select(.grown.filed and (.issue | IN($done[]))) | {issue, followups: .grown.filed}]) as $upc
        # An open issue whose parent (umbrella, as GitHub has it now) is in it: a part of a closed one (lib/issues.sh onlyparts()).
        | def withparts: . as $o | . + [$is[] | select(.number | IN($o[])) | (.parts // [])[] | .number | numbers]
            + [$is[] | select(.umbrella | numbers | IN($o[])) | .number] | unique;
          def grow: . as $o | (ups($upc; $o) | withparts) as $n | if $n == ($o | unique) then $n else $n | grow end;
          $only | grow end) as $only
    | ($retried | map(.issue) | unique) as $again
    | ((($ENV.CONVEYOR_NOW // "" | tonumber?) // now) | localtime | .[3] != $sh) as $loud
    | map((.labels | map(.name)) as $l
      | select($only == null or (.number | IN($only[])))
      | select($l | index($built) | not)
      | select(.number | IN($taken[]) | not)
      # A parent (an issue with GitHub sub-issues, parts: openissues()) is never built: its parts are the work, and
      # umbrellas() closes it once each is closed or landed.
      | select((.parts // []) == [])
      | select($mode != "retried" or (.number | IN($again[])))
      | select(($l | index($fu) | not) or (.number | IN($ready[])) or (.body // "" | test("^Follow-up to #[0-9]+ \\(Conveyor card ") | not))
      # A slice of a split still being filed: not yet held or placed as its parent is (splitplace()), so not picked.
      | select(.body // "" | [capture("^Follow-up of #(?<p>[0-9]+): slice ") | .p] | any($filing[.] == true) | not)
      | . + {later: ($l | index($fu) | not), p: level($l; $prio), rank: rank($l; $prio), again: (.number | IN($again[])),
             waits: waitsof($fc; $open; $done), before: ($ctl.rules.visible != false and before($area; $np)), stuck: ($all != "" and (reach($g; .number) | any(IN($cyc[]))))})
    # forced: `control force` lets it past its open dependencies, only while the dependency guard is off.
    # hold: the control record holds it, or someone outside the project opened it (INSIDE) and the owner has not
    # released it (startSeen): held here too, before adopted() saves the hold, or when it cannot know who opened it.
    | map(. + {forced: (.waits != [] and $ctl.depGuard == false and (.number | IN($ctl.forced[]))),
        hold: ((.number | IN($ctl.held[])) or ((inside | not) and (.number | IN($ctl.startSeen[]) | not))), rule: (([.labels[].name | select(IN($ctl.rules.never[]))] | sort | .[0])
        // (if .later | not then (if $ctl.rules.followups then null else "follow-ups" end) elif $ctl.rules[.p] == false then .p else null end)
        // (if $loud and (.title // "" | startswith("Test-speed survey, ")) then "the survey hour" else null end)
        // (if .number | IN($guarded[]) then "the weekly limit guard" else null end)
        # A Depends on: line it cannot read (baddeps, DEPS) would otherwise count as only the #N it holds (none for
        # `# 2 3`, #2 alone for `#2 3`), and the issue would start before the other issues it names.
        // (baddeps | first // null | if . == null then null else "the line \"\(.[0:200])\", not a list of issues in the form #N" end))})
    # named: the issues another open issue waits on (a Depends on line), read before the filter below drops the waiting
    # issues. Of equal owner order, follow-up position and priority, one of them is picked first: it unblocks others.
    | (reduce (.[] | .number as $m | .waits[] | numbers | select(. != $m)) as $d ({}; .[$d | tostring] = true)) as $named
    | map(select($all != "" or ((.hold | not) and .rule == null and (.waits == [] or .forced) and (.before | not))))
    | sort_by(.number as $n | ($ctl.order | index($n)) // ($ctl.order | length), .later, .rank, ($named[.number | tostring] | not), .createdAt)
