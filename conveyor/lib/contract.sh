# SPDX-License-Identifier: Apache-2.0
# The persisted-contract check before a card lands: at the landing gate (contractgate()), after the lint gate, and for a
# card that waits to land in a batch (contractwait()), after its lint, and on each commit that lands (contractrange(),
# from landone() in lib/claim.sh). A project's pre-push hook can run this check
# (adversarial-review-gate.sh --contract-range <base> <tip>), so a card that fails it could land and then main could
# not push. Here it runs on the card's own change before that change lands.

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
