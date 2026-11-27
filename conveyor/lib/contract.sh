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
# The push of <tip> starts its check at the checker's own answer (--base-only <tip>, the base main's pre-push hook asks
# for): with pushes not made on landing, a landed card with no review record that covers it (a leftover finding and no
# filed follow-up) keeps that answer before it. A push sends a commit main has been at (Push landed: the one its run
# tested), and the next push starts at the checker's answer from that commit (--base-only <tip> <from>). So the range
# from the answer, and from the answer from each commit of main's reflog between it and <base>, must pass. Bugs: the
# check read <base>..<tip> alone, so two cards that each passed landed and the push of both was refused; read from the
# answer alone, a card passed on a test an earlier unpushed card changed, and the push that starts after that card was
# refused; and read from every commit up to <base>, a card was refused from a commit inside a batch, where main never
# was. An answer that is not under <base> (an older checker that has no --base-only, no remote branch) is <base>: no
# range leaves out the card's own change. <covered>: the commits under <base> that the landing of <tip> lands with it
# (the cards of its batch before it) whose landed lines the checker will read as reviewed (contractcovered()): it has no
# record of them yet, so its answer stops at them, though the push, which reads their records, does not (contractbase()).
contractrange() { # <dir> <base> <tip> [<covered>, one a line]
  local h rc b ps p ms bs
  CONTRACT_OUT=''
  h=$(contracthook) || return 0
  [ -f "$h" ] || { CONTRACT_OUT="main's pre-push hook runs the persisted-contract check, and $h is missing"; return 1; }
  b=$(contractbase "$1" "$h" "$2" "$3" "${4-}")
  ps=$(git -C "$1" rev-list --ancestry-path "$b..$2" 2>&1) || { CONTRACT_OUT="the commits from $b to $2 cannot be listed: $ps"; return 1; }
  # The commits main has been at (its reflog, and main now when it keeps none) on the path from the answer to <base>.
  ms=$( { git -C "$1" reflog show --format=%H "refs/heads/$BRANCH" -- 2>/dev/null; git -C "$1" rev-parse -q --verify "refs/heads/$BRANCH^{commit}"; } \
    | grep -Fx -f <(printf '%s\n' "$ps") | sort -u)
  bs=$b
  for p in $ms; do bs+=$'\n'$(contractbase "$1" "$h" "$2" "$3" "${4-}" "$p"); done
  for p in $(awk '!seen[$0]++' <<<"$bs"); do
    CONTRACT_OUT=$(cd "$1" && bash "$h" --contract-range "$p" "$3" 2>&1 < /dev/null 8>&-); rc=$?
    [ $rc = 0 ] || break
  done
  [ $rc != 0 ] || return 0
  [ $rc = 2 ] && [[ $CONTRACT_OUT == *BLOCKED:* ]] && return 2
  CONTRACT_OUT="exit $rc: $CONTRACT_OUT"; return 1
}
# The checker's answer for <tip> (--base-only; with <from>, as if the remote branch were at that commit), in <dir>. With
# no <from>: <base> when it gives none, or one that is not under <base>. With <from>: <from> when it gives none, or one
# that is not under <base> and at or after <from>: an older checker that has no <from> gives its answer from the remote
# branch, which can leave out a commit after <from> that the push from <from> checks (bug: a card landed on such a
# commit's test, and that push refused it). When the commit just after the answer, toward <base>, is in <covered>, the
# answer is the checker's from that commit, as the push reads it once those records are written (bug: a batch card was
# refused from a commit of its batch whose record was not yet written, where no push starts).
contractbase() { # <dir> <checker> <base> <tip> <covered, one a line> [<from>]
  local a n
  while :; do
    a=$(cd "$1" && bash "$2" --base-only "$4" ${6:+"$6"} 2>/dev/null < /dev/null 8>&-) && a=$(git -C "$1" rev-parse -q --verify "${a:-none}^{commit}" 2>/dev/null) \
      && git -C "$1" merge-base --is-ancestor "$a" "$3" 2>/dev/null && { [ -z "${6-}" ] || git -C "$1" merge-base --is-ancestor "$6" "$a" 2>/dev/null; } || a=${6:-$3}
    n=$(git -C "$1" rev-list --reverse --ancestry-path "$a..$3" 2>/dev/null | head -n 1)
    [ -n "$n" ] && grep -qxF -e "$n" <<<"$5" || break
    set -- "$1" "$2" "$3" "$4" "$5" "$n"
  done
  echo "$a"
}
# The landed line <json> (landone(), lib/claim.sh) is one the checker reads as reviewed (conveyor_reviewed() in
# .claude/hooks/adversarial-review-gate.sh, the same rule): no leftover finding, or each one filed as a follow-up.
contractcovered() { # <json>
  jq -e '.leftover == null or ((.leftover == true) and (.followups | type) == "array" and (.followups | length) > 0)' <<<"$1" > /dev/null 2>&1
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
