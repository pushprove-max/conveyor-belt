#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# dashboard_limit.py cardlines keeps the cards it priced (<kept>) under a key of the pack's prices and of the script's
# own code, so a change to the code prices them again. The script is dashboard_limit.py and its parts (PARTS), and the
# key is of all of them. Bug caught: the key read dashboard_limit.py alone, so a change to a part (card_costs itself is
# in dashboard_limit_pricing.py) kept the cards the old code priced.
set -uo pipefail
SOURCE=$(git rev-parse --show-toplevel)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
cp "$SOURCE"/.claude/scripts/dashboard_limit*.py "$T/" || fail "the script and its parts could not be copied"
echo '{"card": "c20261120T000000-sample-1", "steps": []}' > "$T/cards"
# key: the key of the kept summary after one cardlines call.
key() {
  echo '{"prices": {}}' | python3 "$T/dashboard_limit.py" cardlines "$T/cards" "$T/kept" "$T/priced" > /dev/null || fail "cardlines failed"
  head -n 1 "$T/kept" | cut -d' ' -f1
}
was=$(key)
[ -n "$was" ] && [ "$(key)" = "$was" ] || fail "the key of the same code and prices is not the same twice: '$was'"
for p in "$T"/dashboard_limit_*.py; do
  echo '# a change' >> "$p"
  now=$(key)
  [ "$now" != "$was" ] || fail "a change to ${p##*/} kept the key, so the cards the old code priced are kept"
  was=$now
done
echo "PASS: dashboard-limit-kept"
