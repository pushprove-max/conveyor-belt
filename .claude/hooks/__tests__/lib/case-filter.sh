# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# Case filter for shell self-tests, sourced by bash-guardrails.test.sh, bash-guardrails-refusals.test.sh,
# bash-guardrails-writes.test.sh and fixtures/case-filter-fixture.sh, which the case_filter_runs_only_matching checks
# in bash-guardrails-refusals.test.sh run so each selector variant costs milliseconds, not a run of that file.
#
# CONVEYOR_SHELL_TEST_CASE=<text>[,<text>] runs only the top-level checks whose text holds one of the texts. It
# acts on top-level lines only: a line whose first word is `check`, or a function that calls `check` (`g`, `w`,
# `check_try`, found by `declare -f`), runs when its unexpanded text holds a text; once it runs, nothing inside it
# is filtered again. Set-up lines always run. A text that runs no check, or no text, exits 2. Unset = unchanged.

cf_refuse_empty() { # -- exit 2 when the selector is set but names no text
  if [ -n "${CONVEYOR_SHELL_TEST_CASE+x}" ] && [ -z "${CONVEYOR_SHELL_TEST_CASE//,/}" ]; then
    echo "FAIL CONVEYOR_SHELL_TEST_CASE='$CONVEYOR_SHELL_TEST_CASE' names no text to match" >&2; exit 2
  fi
}

cf_install() { # <hits file, or empty> -- from here on, skip the top-level checks the texts do not name
  IFS=, read -ra WANT_TEXTS <<<"$CONVEYOR_SHELL_TEST_CASE"; CF_HITS=$1
  shopt -s extdebug
  trap '[ -n "${FUNCNAME[0]:-}" ] || case_filter' DEBUG  # set -u: FUNCNAME is unset at top level
}

case_filter() { # -- 0 runs $BASH_COMMAND, 1 skips it: a check, or a function calling check, the texts do not name
  local W=${BASH_COMMAND%%[[:space:]]*} T
  [ "$W" = check ] || { [ "$(type -t "$W")" = function ] && declare -f "$W" | grep -qw check; } || return 0
  # Every text that selects a check while ON=1 is recorded, so cf_missed can name a text that ran nothing;
  # returning on the first would leave an overlapping second text unrecorded.
  local HIT=1
  for T in "${WANT_TEXTS[@]}"; do
    [ -n "$T" ] && [[ $BASH_COMMAND == *"$T"* ]] || continue
    [ "${ON:-0}" != 1 ] || [ -z "$CF_HITS" ] || echo "$T" >> "$CF_HITS"
    HIT=0
  done
  return $HIT
}

cf_missed() { # <hits file> -- a FAIL line per text that selected no check; 1 if any
  local T MISSED=0
  IFS=, read -ra WANT_TEXTS <<<"$CONVEYOR_SHELL_TEST_CASE"
  for T in "${WANT_TEXTS[@]}"; do
    [ -z "$T" ] || grep -qxF -- "$T" "$1" || { echo "FAIL no check matched the text '$T'"; MISSED=1; }
  done
  return $MISSED
}
