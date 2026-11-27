#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the benefit hold before the build (BENEFIT and NOBENEFIT, lib/pick.sh; its rule in jq/upnext.jq).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: an issue that says no live case is known, or that its gain was not measured, and names no risk it guards
# against is built with no yes on its benefit; a `Visible change approved:` line lets it through, or a risk word in
# that line's condition does; an issue that says so but guards one of the risks (each on its own) is held; an issue
# with no benefit wording is held; a `Benefit approved:` line does not release the hold, alone or beside a visible-change
# approval; a `Benefit approved:` line under `Nothing visible changes.` puts the issue behind the visible-change gate;
# a risk word in a denial (`does not affect security`) frees the issue; a `Benefit approved:` line put first in the
# section of what customers or staff will see hides the change below it from the visible-change gate; the benefit rule
# names an issue whose Depends on: line cannot be read, so a run limited by --only to it waits for a yes that cannot
# queue it;
# the rule it is skipped by does not say why; a run limited by --only to a held issue ends instead of waiting for the
# yes; the Board sends the owner to Rules, which cannot release it; a `Benefit approved:` line releases it though
# the owner did not put it there (benefitYes false), or with no benefitYes.
# One fixture, one pick list: upnext is the list pick takes its first from (pick takes only an issue whose rule is null
# and that is not before).
# The issue opened by the owner (issue()), with benefitYes true (the owner put its approval line there), or, with a
# third argument, that value ("none": no field).
benefitbody() { issue "$1" 2026-01-01 | jq -c --arg b "$2" --arg o "${3:-true}" '.body = $b | if $o == "none" then . else .benefitYes = ($o == "true") end'; }
t_benefithold() {
  local why='no live benefit: the issue says no live case is known or the gain was not measured, and names no risk it guards against; a line starting "Benefit approved:" releases it only when the repository owner or the GitHub account of Conveyor added that line'
  local see=$'## What customers or staff will see\nA faster page.\n\nVisible change approved: owner, 2026-11-20'
  local deps='the line "Depends on: # 2 3", not a list of issues in the form #N'
  # Each issue: its number, held (the benefit rule), free, before (free, but waits for the visible-change approval) or
  # deps (skipped by the rule of an unreadable Depends on: line), and its body. Each issue's benefitYes is true but
  # those of who below.
  local -a cases=(
    1 held $'Speed up the cache.\n\nNo live case known.'
    2 held $'Speed up the cache.\n\nThe effect was not measured.\n\n'"$see"
    3 free $'Check the token.\n\nNo live case known; it guards a security risk.'
    4 free $'Keep the audit log.\n\nNot measured; it guards a compliance risk.'
    5 free $'Write the file first.\n\nNo live case known; it prevents data loss.'
    6 free $'Stop the default.\n\nNo live case known; it removes a silent fallback.'
    7 free $'Stop on a bad key.\n\nNo live case known; the step must fail loud.'
    8 free 'Fix the cache key.'
    9 free $'Speed up the cache.\n\nNot measured.\n\nBenefit approved: owner, 2026-11-27'
    10 free $'Speed up the cache.\n\nNot measured.\n\n'"$see"$'\nBenefit approved: owner, 2026-11-27'
    11 free $'Speed up the cache.\n\nNot measured.\n\n## What customers or staff will see\nNothing visible changes.\n\nBenefit approved: owner, 2026-11-27'
    12 held $'Speed up the cache.\n\nNot measured.\n\nVisible change approved: owner, 2026-11-27; condition: security staff only'
    13 held $'Speed up the cache.\n\nNo live case known. This change does not affect security.'
    14 before $'Add an export.\n\n## What customers or staff will see\nBenefit approved: owner, 2026-11-27\nStaff get a new export button.'
    15 deps $'Speed up the cache.\n\nDepends on: # 2 3\n\nNot measured.'
    16 held $'Speed up the cache.\n\nNot measured.\n\nBenefit approved: owner, 2026-11-27'
    17 held $'Speed up the cache.\n\nNot measured.\n\nBenefit approved: owner, 2026-11-27'
  )
  local -A who=([16]=false [17]=none)
  local i list=()
  for ((i = 0; i < ${#cases[@]}; i += 3)); do list+=("$(benefitbody "${cases[i]}" "${cases[i + 2]}" "${who[${cases[i]}]:-}")"); done
  setup "$(printf '%s\n' "${list[@]}" | jq -cs .)"
  # The visible-change gate on, so issue 11 shows whether a benefit approval line is read as part of its section.
  loop control rules visible=on >/dev/null || fail "control rules visible=on was refused"
  fx_in 'upnext "$(cat "$STUB/issues.json")" "" all | jq -c "map([.number, .rule, .before])"'
  local out; out=$(cat "$T/$CASE/run.out")
  local n want got
  for ((i = 0; i < ${#cases[@]}; i += 3)); do
    n=${cases[i]}
    case ${cases[i + 1]} in
      held) want=$(jq -cn --arg w "$why" '[$w, false]') ;;
      deps) want=$(jq -cn --arg w "$deps" '[$w, false]') ;;
      before) want='[null,true]' ;;
      *) want='[null,false]' ;;
    esac
    got=$(jq -c --argjson n "$n" 'map(select(.[0] == $n)) | .[0][1:]' <<<"$out")
    [ "$got" = "$want" ] || fail "issue #$n with benefitYes ${who[$n]:-true} and the body $(jq -cn --arg b "${cases[i + 2]}" '$b') is not ${cases[i + 1]} ([rule, before]): want $want, got $got; whole list: $out"
  done
  # A run limited by --only to a held issue hears wait, so it polls until the owner's yes comes, not ends.
  fx_in 'ONLY="[1]" locked pick "" "" "$(cat "$STUB/issues.json")"'
  # run.out also holds the loop log: the release limit's reason (rellimit(), lib/pick.sh), not part of the pick's answer.
  [ "$(grep -v '^conveyor: the release limit ' "$T/$CASE/run.out")" = wait ] || fail "pick with --only [1], #1 held by the benefit rule (body \"No live case known.\"), did not say wait: $(cat "$T/$CASE/run.out")"
  # ... and one limited to #15, whose Depends on: line no approval makes readable, does not wait for the benefit's yes.
  fx_in 'ONLY="[15]" locked pick "" "" "$(cat "$STUB/issues.json")"'
  [ -z "$(cat "$T/$CASE/run.out")" ] || fail "pick with --only [15] (body \"Depends on: # 2 3 ... Not measured.\") waits or picks, though no benefit approval can queue it: $(cat "$T/$CASE/run.out")"
  # The Board names the hold as a rule of Conveyor's own (standing), not one of Rules, which cannot release it.
  got=$(loop snapshot --fresh | jq -c '.open.held | map(select(.issue == 1)) | .[0].reasons | map([.kind, .rule])')
  [ "$got" = "$(jq -cn --arg w "$why" '[["standing", $w]]')" ] || fail "the snapshot's reasons for #1 (body \"No live case known.\") are not one standing rule with the benefit reason: $got"
}
# Bugs: the gate takes a `Benefit approved:` line as the owner's yes though a collaborator put it there: in their own
# issue (#3) or in the owner's (#4); when the owner later saves the text for another reason, such as a typo (#6); when
# the owner took the line out after the issue list was read (#7); when the history that names who put it there is
# not read whole (#9 to #12); or when a collaborator rewrote the issue under the owner's line (#13). And the owner's line does not release the issue: the line of the account gh is signed in
# as, which is not the repository's owner (#2: an organization owns the repository, and its owner runs Conveyor), the
# owner's line in a collaborator's issue as procedures.md says (#5), or the owner's line put back after a collaborator
# took out the same line (#8). The issues are read as a pick reads them (openissues() through the gh stub's GraphQL
# answers: viewer m, repository owner o, collaborator c), then upnext.
t_benefitowner() {
  # Each issue: held (the benefit rule) or not, its author, its edit history (oldest first, the first the text as
  # opened; none: never edited), and the text GraphQL gives (gqlBody) when it is not the listed body.
  setup "$(jq -cn --argjson base "$(issue 0 2026-01-01)" '"Speed up the cache.\n\nNot measured." as $a
    | "\($a)\n\nBenefit approved: 2026-11-27" as $b | ($b | sub("the cache"; "teh cache")) as $t
    | def v($by; $text): {by: $by, text: $text};
    [{number: 1, held: false, author: "o"},
     {number: 2, held: false, author: "m"},
     {number: 3, held: true, author: "c"},
     {number: 4, held: true, author: "o", edits: [v("o"; $a), v("c"; $b)]},
     {number: 5, held: false, author: "c", edits: [v("c"; $a), v("m"; $b)]},
     {number: 6, held: true, author: "c", edits: [v("c"; $t), v("o"; $b)]},
     {number: 7, held: true, author: "c", edits: [v("c"; $a), v("o"; $b), v("o"; $a)], gqlBody: $a},
     {number: 8, held: false, author: "c", edits: [v("c"; $b), v("c"; $a), v("m"; $b)]},
     {number: 9, held: true, author: "c", edits: [v("c"; $t) + {deleted: true}, v("o"; $b)]},
     {number: 10, held: true, author: "c", edits: [v("c"; $a), v("o"; $b)], editTotal: 3},
     {number: 11, held: true, author: "c", edits: [v("o"; $b)]},
     {number: 12, held: true, author: "c", edits: [v("c"; $a), v("o"; $b)], gqlBody: "\($b)\nEdited after."},
     {number: 13, held: true, author: "c", edits: [v("c"; $a), v("m"; $b), v("c"; "\($b)\nAlso drop the index.")], body: "\($b)\nAlso drop the index."}]
    | map($base + {title: "title \(.number)", body: $b, authorAssociation: ({o: "OWNER", m: "MEMBER", c: "COLLABORATOR"}[.author])} + .
      | if .edits then .edits = [.edits | to_entries[] | .value + {at: "2026-11-0\(.key + 1)T00:00:00Z"}] else . end)')"
  fx_in 'openissues "$FIELDS" > "$T/$CASE/asked.json" && upnext "$(cat "$T/$CASE/asked.json")" "" all | jq -c "map([.number, (.rule != null)])"'
  local bad
  bad=$(jq -r --slurpfile o "$T/$CASE/run.out" '.[] | (.number as $n | [$o[0][] | select(.[0] == $n) | .[1]] | if . == [] then "missing" else .[0] end) as $got | select($got != .held)
    | "issue #\(.number) opened by \(.author), edits \(.edits // "none" | tojson), body \(.body | tojson), GraphQL text \(.gqlBody // .body | tojson): held want \(.held), got \($got)"' \
    "$STUB/issues.json" 2>&1) || bad="the pick list could not be read: $(cat "$T/$CASE/run.out")"
  [ -z "$bad" ] || fail "$bad"
}
