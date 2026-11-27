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
# yes; the Board sends the owner to Rules, which cannot release it.
# One fixture, one pick list: upnext is the list pick takes its first from (pick takes only an issue whose rule is null
# and that is not before).
benefitbody() { issue "$1" 2026-01-01 | jq -c --arg b "$2" '.body = $b'; }
t_benefithold() {
  local why='no live benefit: the issue says no live case is known or the gain was not measured, and names no risk it guards against; a line starting "Benefit approved:" in the issue releases it'
  local see=$'## What customers or staff will see\nA faster page.\n\nVisible change approved: owner, 2026-11-20'
  local deps='the line "Depends on: # 2 3", not a list of issues in the form #N'
  # Each issue: its number, held (the benefit rule), free, before (free, but waits for the visible-change approval) or
  # deps (skipped by the rule of an unreadable Depends on: line), and its body.
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
  )
  local i list=()
  for ((i = 0; i < ${#cases[@]}; i += 3)); do list+=("$(benefitbody "${cases[i]}" "${cases[i + 2]}")"); done
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
    [ "$got" = "$want" ] || fail "issue #$n with the body $(jq -cn --arg b "${cases[i + 2]}" '$b') is not ${cases[i + 1]} ([rule, before]): want $want, got $got; whole list: $out"
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
