#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# dashboard.sh's lanes part, by function: lanes, lane and latest_cwd are defined here from dashboard.sh itself.
# Issue 512: each lane() listed ~/.claude/projects with find and read every active record's cwd again, so a cycle ran
# find once a lane. Bug caught: a cycle with two records of two lanes each runs find more than once, or a lane loses
# its session when the list is shared.
set -euo pipefail
SOURCE=$(git rev-parse --show-toplevel)
. "$SOURCE/conveyor/lib/portable.sh"; p_tools
T=$(cd "$(mktemp -d /tmp/dashboard-lanes-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
eval "$(sed -n '/^latest_cwd() /p; /^lane() {/,/^}/p; /^lanes() {/,/^}/p' "$SOURCE/.claude/scripts/dashboard.sh")"
declare -F latest_cwd lane lanes >/dev/null || fail "dashboard.sh no longer defines latest_cwd, lane and lanes"

export HOME=$T/home GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
NOW=$(date +%s) ACTIVE=600 PP_MAIN=$T/main HOST_FILE=$T/host.json
export NOW ACTIVE # read by lane(), which the eval above defines from dashboard.sh
mkdir -p "$T/bin" "$HOME/.claude/projects/-main"
# A find that counts its runs, then runs the real one.
printf '#!/usr/bin/env bash\necho run >> %q\nexec %q "$@"\n' "$T/find-runs" "$(command -v find)" > "$T/bin/find"
chmod +x "$T/bin/find"

# Two records, each with a Fast and a Research lane; each lane has one session, begun in the main checkout (so filed
# there, not under the lane's own folder) and working in the lane now.
for l in a-fast a-research b-fast b-research; do
  git init -q -b main "$T/$l"
  git -C "$T/$l" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  { echo '{"type":"user","timestamp":"2026-11-18T10:00:00Z","cwd":"'"$PP_MAIN"'","message":{"role":"user","content":"Work on '"$l"'"}}'
    echo '{"type":"assistant","timestamp":"2026-11-18T10:00:05Z","cwd":"'"$T/$l/src"'","message":{"content":[{"type":"text","text":"On it."}]}}'
  } > "$HOME/.claude/projects/-main/$l.jsonl"
done
jq -n --arg t "$T" '{records: [{repo: "a", lanes: {fast: {worktree: "\($t)/a-fast"}, research: {worktree: "\($t)/a-research"}}},
  {repo: "b", lanes: {fast: {worktree: "\($t)/b-fast"}, research: {worktree: "\($t)/b-research"}}}]}' > "$HOST_FILE"

out=$(PATH=$T/bin:$PATH lanes)
runs=$(grep -c . "$T/find-runs")
[ "$runs" = 1 ] || fail "one_cycle_runs_find_once: find ran $runs times for four lanes"
jq -e '.records | map([.repo, .fast.run.topic, .research.run.topic])
  == [["a", "Work on a-fast", "Work on a-research"], ["b", "Work on b-fast", "Work on b-research"]]' <<<"$out" >/dev/null \
  || fail "each_lane_names_its_session: $out"
echo "dashboard-lanes: ok"
