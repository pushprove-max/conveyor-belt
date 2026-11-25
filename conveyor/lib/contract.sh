# SPDX-License-Identifier: Apache-2.0
# The persisted-contract check before a card lands: at the landing gate (contractgate()), after the lint gate, and for a
# card that waits to land in a batch (contractwait()), after its lint, and on each commit that lands (contractrange(),
# from landone() in lib/claim.sh). A project's pre-push hook can run this check
# (adversarial-review-gate.sh --contract-range <base> <tip>), so a card that fails it could land and then main could
# not push. Here it runs on the card's own change before that change lands. Then the push checks
# main's pre-push hook selects for the card's change: at the landing gate (pushgate()), and for a card that waits to
# land in a batch (pushgatewait()).

CONTRACTFIX=$'# Persisted-contract check: fix it and nothing else\nThe persisted-contract check (the one the project\'s pre-push hook runs) refused this card\'s change. A change to a persisted-contract writer needs one changed test that names both that writer and a changed reader. Add or change such a test. Do not change the check. Its message:'

# The check main's pre-push hook runs, printed: none (1) when that hook (`git rev-parse --git-path hooks/pre-push` in
# main: core.hooksPath when set) does not name --contract-range. It is the copy in the install the hook loads, the
# project's engine (enginepin(), lib/install.sh: the pack's pin, or the newest commit taken here), never this engine's
# own copy while that is another commit: a card can run on an older install than the one the push runs. With no such
# commit (a loop run from a checkout), this engine's copy.
contracthook() {
  local p c=''
  p=$(cd "$MAIN" && git rev-parse --git-path hooks/pre-push 2>/dev/null) || return 1
  [[ $p == /* ]] || p=$MAIN/$p
  [ -f "$p" ] && grep -qF -e '--contract-range' "$p" 2>/dev/null || return 1
  enginepin c 2>/dev/null || c=''
  if [ -n "$c" ]; then echo "$VERSIONS/$c/.claude/hooks/adversarial-review-gate.sh"
  else echo "$HERE/../.claude/hooks/adversarial-review-gate.sh"; fi
}

# The check on the commits <base>..<tip>, in <dir>; its output in CONTRACT_OUT. 0: the range passes, or main's pre-push
# hook runs no such check (contracthook). 2: a refusal (exit 2 with a BLOCKED line). 1: the check could not run
# (CONTRACT_OUT says why).
contractrange() { # <dir> <base> <tip>
  local h rc
  CONTRACT_OUT=''
  h=$(contracthook) || return 0
  [ -f "$h" ] || { CONTRACT_OUT="main's pre-push hook runs the persisted-contract check, and $h is missing"; return 1; }
  CONTRACT_OUT=$(cd "$1" && bash "$h" --contract-range "$2" "$3" 2>&1 < /dev/null 8>&-); rc=$?
  [ $rc != 0 ] || return 0
  [ $rc = 2 ] && [[ $CONTRACT_OUT == *BLOCKED:* ]] && return 2
  CONTRACT_OUT="exit $rc: $CONTRACT_OUT"; return 1
}

# The check on <worktree>'s staged change (HEAD to a commit of its index), in the worktree, as contractrange().
contractrun() { # <worktree>
  local base head
  CONTRACT_OUT=''
  contracthook > /dev/null || return 0
  base=$(git -C "$1" rev-parse -q --verify HEAD) && head=$(cd "$1" && git commit-tree "$(git write-tree)" -p "$base" -m "conveyor contract check" 2>&1) \
    || { CONTRACT_OUT="the engine could not make the card's change a commit: ${head:-}"; return 1; }
  contractrange "$1" "$base" "$head"
}

# The landing gate's check (cardtest(), lib/cardland.sh). 0: on to land. A refusal goes to one fix session
# (CONTRACTFIX, with the check's message), then checked() (lib/donewhen.sh): 2, the fixed change goes back to review
# (cfix, card()'s local, keeps each BLOCKED line a fix session was given). The check stops at the first writer with no
# covering test, so a change with two such writers names the second only once the first is fixed: that refusal gets its
# own fix session. A refusal whose BLOCKED line a fix session already had, or a check that could not run: the card
# blocks with the check's message, 1.
contractgate() { # <card> <issue> <worktree> <issue json> <the sessions' prompt> <branch>
  local c=$1 n=$2 wt=$3 out rc t b
  contractrun "$wt"; rc=$?; out=$CONTRACT_OUT
  [ $rc != 0 ] || return 0
  [ $rc = 2 ] || { block "$c" "$n" "$wt" "contract: the persisted-contract check could not run, so nothing landed: ${out:0:2000}"; return 1; }
  b=$(grep -m 1 'BLOCKED:' <<<"$out")
  ! grep -qxF -e "$b" <<<"${cfix:-}" || { block "$c" "$n" "$wt" "contract: the persisted-contract check still refuses the change after its fix session; nothing landed: $b"$'\n'"${out:0:2000}"; return 1; }
  readyrm "$wt"; locked giveway "$c" "$wt" fixing
  began "$c" "$n" fix
  redbrief "$c" "$n" "$6"; t=$(session "$wt" "$5"$'\n\n'"$CONTRACTFIX"$'\n'"${out:0:2000}" fix) || { block "$c" "$n" "$wt" "fix: $t"; return 1; }
  cfix+=$b$'\n'
  checked "$c" "$n" "$wt" "$4" "$5" fix "$(jq -c --arg r "contract: ${out:0:300}" '. + {reason: $r}' <<<"$t")" || return 1
  git -C "$wt" add -A 2>/dev/null; trialflag "$wt"
  return 2
}

# The push checks before a card lands: main's pre-push hook (`git rev-parse --git-path hooks/pre-push` in main, never
# the card's own copy), when it names CONVEYOR_PUSH_GATE, runs in the card's worktree as git runs it for a push of the
# card's change alone: its stdin line gives the card's change (a commit of its index) as the local commit and the
# worktree's HEAD as the remote's, so the checks the hook selects by changed files are those of the card's change. It
# gets CONVEYOR_PUSH_GATE (the card), the pack's push.env and the load factor, under pushTimeout times that factor, on a
# test slot, as the push's hook does (pushone(), lib/push.sh): it waits for a slot while every one is held. A hook that
# does not name CONVEYOR_PUSH_GATE is not run here: it can run a whole suite, which the card's own test step covers.
# While it waits and runs, <worktree>.live says so, so the loop does not take the card for one with no process of its
# step (stuckcard(), lib/run.sh) and stop it before its time limit. 0: it passed, or there is no such hook. 1: PUSH_WHY
# is the reason: the hook failed (the reason names the check, the word after its last "FAILED", and the hook's output
# follows it), it ran past its time limit (PUSHLATE), or it could not run.
PUSHLATE='its checks not finished'
pushgaterun() { # <card> <worktree>
  local c=$1 wt=$2 p base head pe e=() u pf lim out rc k
  PUSH_WHY=''
  p=$(cd "$MAIN" && git rev-parse --git-path hooks/pre-push 2>/dev/null) || return 0
  [[ $p == /* ]] || p=$MAIN/$p
  [ -x "$p" ] && grep -qF CONVEYOR_PUSH_GATE "$p" 2>/dev/null || return 0
  base=$(git -C "$wt" rev-parse -q --verify HEAD) && head=$(cd "$wt" && git commit-tree "$(git write-tree)" -p "$base" -m "conveyor push checks" 2>&1) \
    || { PUSH_WHY="push check: the engine could not make the card's change a commit, so its push checks did not run and nothing landed: ${head:-}"; return 1; }
  packget push.env pe && { [ -z "$pe" ] || mapfile -d '' -t e < <(jq -j 'to_entries[] | "\(.key)=\(.value)\u0000"' <<<"$pe"); } \
    || { PUSH_WHY="push check: the pack's push.env could not be read, so the push checks did not run and nothing landed"; return 1; }
  u=$(git -C "$MAIN" remote get-url "$REMOTE" 2>/dev/null) || u=$REMOTE
  slot_pool 2>/dev/null || { PUSH_WHY="push check: the test slots folder could not be made, so the push checks did not run and nothing landed"; return 1; }
  if [ -z "$SLOT_HOME" ]; then until slot_try || slot_wait; do pushgatelive "$wt" "$(slot_waiting)"; done; fi
  pushgatelive "$wt" "running main's pre-push hook on the card's change"
  pf=$(loadfactor); lim=$(awk -v n="$PUSH_TIMEOUT" -v f="$pf" "$LOADSCALE") || lim=$PUSH_TIMEOUT
  out=$(exec 2>&1 8>&-; cd "$wt" && { [ -n "$SLOT_HOME" ] || slot_mine; } \
    && exec env "${e[@]}" CONVEYOR_PUSH_GATE="$c" CONVEYOR_LOAD_FACTOR="$pf" timeout --kill-after=30 "$lim" "$p" "$REMOTE" "$u" <<<"HEAD $head refs/heads/$BRANCH $base"); rc=$?
  [ -n "$SLOT_HOME" ] || slot_free
  rm -f "$wt.live"
  [ $rc != 0 ] || return 0
  out=$(tail -c 4000 <<<"$out" | tr -d '\000')
  if [ $rc = 124 ] || [ $rc = 137 ]; then
    PUSH_WHY="push check: $PUSHLATE: main's pre-push hook ran past its time limit of ${lim}s on the card's change; nothing landed."$'\n'"$out"; return 1
  fi
  k=$(jq -Rrs '[scan("(?:^|[^A-Za-z0-9_])FAILED:?[ \t]+(\\S+)")] | last[0] // "the pre-push hook" | .[0:100]' <<<"$out")
  PUSH_WHY="push check: $k failed on the card's change (exit $rc); nothing landed."$'\n'"$out"; return 1
}
# The live record of the push checks (pushgaterun()): the Test step, doing <action>.
pushgatelive() { # <worktree> <action>
  jq -cn --arg a "$2" '{step: "test", at: (now | todate), last: (now | todate), turns: 0, files: {run: 0, of: null}, tests: null, action: $a}' > "$1.live.tmp" 2>/dev/null \
    && mv -f "$1.live.tmp" "$1.live"
}
# At the landing gate (cardtest(), lib/cardland.sh, after contractgate()). 0: on to land. 1: the card is blocked with
# the reason (pushgaterun()), nothing landed.
pushgate() { # <card> <issue> <worktree>
  pushgaterun "$1" "$3" || { block "$1" "$2" "$3" "$PUSH_WHY"; return 1; }
}
# For a card that waits to land (settle(), lib/claim.sh), with batches on, after contractwait(): a batch lands a card
# with no turn at its landing gate. 0: its checks and tests run. 1: the push checks failed or could not run: its
# <worktree>.ready is removed, so no batch takes it (gather()), and at its turn its landing gate (pushgate()) runs them
# again and blocks it on a failure.
pushgatewait() { # <card> <worktree>
  pushgaterun "$1" "$2" && return 0
  readyrm "$2"
  echo "conveyor: card $1: its push checks failed while it waits, or could not run: it runs no check or test, and its landing gate deals with it at its turn"
  printf '%s\n' "${PUSH_WHY:0:2000}"
  return 1
}

# The check for a card that waits to land (settle(), lib/claim.sh), with batches on, after its lint (lintwait()). 0:
# its checks and tests run. 1: a refusal, or a check that could not run: its <worktree>.ready is removed, so no batch
# takes it (gather()) and this check does not run again while it waits; at its turn its landing gate (contractgate)
# gives it its fix session, or blocks it. This check reads the card's change on its own HEAD: a batch puts it on the
# commit of the card before it, so landone() (lib/claim.sh) checks each card again on the commit it lands.
contractwait() { # <card> <worktree>
  contractrun "$2" && return 0
  readyrm "$2"
  echo "conveyor: card $1: the persisted-contract check refused its change while it waits, or could not run: it runs no check or test, and its landing gate deals with it at its turn"
  printf '%s\n' "${CONTRACT_OUT:0:2000}"
  return 1
}
