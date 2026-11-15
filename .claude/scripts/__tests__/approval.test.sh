#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins approvals read from the decision log: a gate's approval is the owner's latest answer, a "Yes", to today's
# picker with exactly that header, asked in this project's main checkout. Without it an approval would have to be a
# hand-made file anyone can create; a "No", another header, an earlier day, a later "No", or another project's picker
# must never open the gate.
set -u
. "$(dirname "$0")/../../hooks/__tests__/lib/rulings-fixture.sh"
A=$PLUG/.claude/scripts/approval.sh
printf -v today '%(%Y%m%d)T' -1
row() { jq -cn --arg id "$1" --arg h "$2" --arg a "$3" --arg cwd "${4:-$MAIN}" '{id:$id, source:"ask", header:$h, question:"Go?", answer:$a, pick:"option", cwd:$cwd}'; }
appr() { (cd "${2:-$MAIN}" && bash "$A" "$1"; echo $?) 2>/dev/null | tail -n 1; }
# The parts below run side by side, so the file takes its slowest part's time, not their sum. Each has a decision log
# of its own (its own host file's state folder), so no part sees another's approvals: a part's log holds only the rows
# it wrote, in its order. Each part's output is printed and counted in the parts' order once all have ended.
PARTS=()
part() { # <name>: starts the part's own log, empty
  export XDG_CONFIG_HOME=$T/config-$1
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/state-$1/foreman"
  jq -n --arg s "$T/state-$1" '{stateDir: $s, rulingPrefix: "q"}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  LOG=$T/state-$1/foreman/rulings.jsonl; : > "$LOG"
}
started() { PARTS+=("$1:$!"); } # <name>, after the part's ( ... ) > "$T/out.<name>" 2>&1 &

( part read
row "q-$today-090000-1-aaaaaa" "Migrate" "No, wait" > "$LOG"
check "a No answer does not approve" 1 "$(appr Migrate)"
row "q-19990101-090000-1-bbbbbb" "Deploy" "Yes (Recommended)" >> "$LOG"
check "a Yes from an earlier day does not approve" 1 "$(appr Deploy)"
row "q-$today-090000-1-cccccc" "Deploy" "Yes (Recommended)" >> "$LOG"
check "today's Yes to the picker with that header approves" 0 "$(appr Deploy)"
check "it approves no other header" 1 "$(appr Migrate)"
jq -c '.void = true' <<<"$(row "q-$today-090000-1-dddddd" "Purge" "Yes")" >> "$LOG"
check "a void row approves nothing" 1 "$(appr Purge)"
row "q-$today-091000-1-eeeeee" "Deploy" "No" >> "$LOG"
check "a later No withdraws an earlier Yes" 1 "$(appr Deploy)"

# Another project's picker, and a picker asked in a worktree (never the owner's), approve nothing here.
OTHER=$T/other; git init -q "$OTHER"
row "q-$today-092000-1-ffffff" "Seed" "Yes" "$OTHER" >> "$LOG"
check "another project's Yes does not approve in this one" 1 "$(appr Seed)"
check "it approves in its own project" 0 "$(appr Seed "$OTHER")"
row "q-$today-092000-1-111111" "Index" "Yes" "$CARD" >> "$LOG"
check "a Yes asked in a worktree does not approve" 1 "$(appr Index)"
) > "$T/out.read" 2>&1 & started read

# The gate that asks for it: the dependency guard lets in a package the owner said Yes to today, by a picker headed
# "Dep <package>", and no other, whether added in package.json or by an install command.
printf '{"name":"f","dependencies":{"zod":"^3.22.0"}}\n' > "$MAIN/package.json"
G=$PLUG/.claude/hooks/dependency-addition-guard.sh
dep() { (cd "$MAIN" && jq -cn --arg f "$MAIN/package.json" --arg p "$1" '{tool_name:"Edit", tool_input:{file_path:$f,
  old_string:"\"zod\"", new_string:"\"\($p)\": \"^1.0.0\", \"zod\""}}' | bash "$G" >/dev/null 2>&1; echo $?); }
inst() { (cd "$MAIN" && jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$G" >/dev/null 2>&1; echo $?); }
lodash() { row "q-$today-100000-1-222222" "Dep lodash" "Yes" >> "$LOG"; } # the owner's Yes to lodash today

( part dep
check "an unapproved package is refused" 2 "$(dep lodash)"
check "an unapproved install command is refused" 2 "$(inst "npm install lodash")"
lodash
check "a package the owner approved by picker today is let in" 0 "$(dep lodash)"
check "an install command of that package is let in" 0 "$(inst "npm install lodash")"
check "that approval lets in no other package" 2 "$(dep ramda)"
check "nor an install command naming another package beside it" 2 "$(inst "npm install lodash ramda")"
# A version or a valued flag's folder is not the package: the approval is for the name.
check "a versioned install of that package is let in" 0 "$(inst "npm install lodash@4")"
check "an install with a valued npm flag before it is let in" 0 "$(inst "npm install --prefix web lodash")"
check "a valued flag does not hide another package" 2 "$(inst "npm install --prefix web ramda")"
# Another command's add on the line is not a package: git add package.json needs no "Dep package.json".
check "an approved install followed by git add is let in" 0 "$(inst "npm install lodash && git add package.json")"
check "a git add does not hide an unapproved install beside it" 2 "$(inst "git add package.json && npm install ramda")"
) > "$T/out.dep" 2>&1 & started dep

# A folder named after a manager is still git's argument: git -C pnpm add package.json installs nothing.
gitc() { # <manager>...
  local m
  for m; do
    check "an approved install followed by git -C $m add is let in" 0 "$(inst "npm install lodash && git -C $m add package.json")"
    check "an approved install followed by a wrapped git -C $m add is let in" 0 "$(inst "npm install lodash && env git -C $m add package.json")"
    check "an approved install followed by git -C./$m add is let in" 0 "$(inst "npm install lodash && git -C./$m add package.json")"
    check "an approved install followed by git --git-dir $m add is let in" 0 "$(inst "npm install lodash && git --git-dir $m/.git --work-tree=./$m add package.json")"
  done
}
( part gitnode; lodash; gitc npm yarn pnpm ) > "$T/out.gitnode" 2>&1 & started gitnode
( part gitpy; lodash; gitc pip uv
check "a git -C folder does not hide an unapproved install beside it" 2 "$(inst "git -C pnpm add package.json && pnpm add ramda")"
# A git alias can run an install: its packages still need their own Yes.
check "an unapproved install in a git alias is refused" 2 "$(inst "npm install lodash && git -c alias.deps='! npm install ramda' deps")"
check "an unapproved install in a git alias with no space is refused" 2 "$(inst "npm install lodash && git -c alias.deps='!npm install ramda' deps")"
) > "$T/out.gitpy" 2>&1 & started gitpy

( part wrap; lodash
# A wrapper does not hide the install it runs: its packages still need their own Yes.
check "an approved install behind env is let in" 0 "$(inst "env npm install lodash")"
check "a wrapped unapproved install beside an approved one is refused" 2 "$(inst "npm install lodash && env npm install ramda")"
check "a sudo-wrapped unapproved install is refused" 2 "$(inst "npm install lodash && sudo npm install ramda")"
row "q-$today-100000-1-333333" "Dep @types/node" "Yes" >> "$LOG"
check "approving a scoped package does not approve a look-alike name" 2 "$(dep types-node)"
check "the scoped package itself is let in" 0 "$(dep @types/node)"
check "a versioned install of the scoped package is let in" 0 "$(inst "npm install @types/node@20")"
row "q-$today-100000-1-444444" "Dep requests" "Yes" >> "$LOG"
check "a pip install with a version pin is let in" 0 "$(inst "pip install requests>=2")"
) > "$T/out.wrap" 2>&1 & started wrap

( part req
# A requirements file compares names PEP 503-normalised, but the owner's Yes names the package as it is written:
# a Yes to that exact spelling, or to the normalised name, lets it in, while another package stays refused.
req() { (cd "$MAIN" && jq -cn --arg f "$MAIN/requirements.txt" --arg c "$1" '{tool_name:"Write", tool_input:{file_path:$f,
  content:$c}}' | bash "$G" >/dev/null 2>&1; echo $?); }
: > "$MAIN/requirements.txt"
check "an unapproved requirement is refused" 2 "$(req "My_Pkg==1.0")"
row "q-$today-100000-1-555555" "Dep My_Pkg" "Yes" >> "$LOG"
check "a requirement spelt as the owner approved it is let in" 0 "$(req "My_Pkg==1.0")"
check "the approved spelling is let in after another spelling of the same package" 0 "$(req $'my.pkg>=1\nMy_Pkg==1.0')"
check "that approval lets in no other requirement beside it" 2 "$(req $'My_Pkg==1.0\nramda==1.0')"
row "q-$today-100000-1-666666" "Dep other-pkg" "Yes" >> "$LOG"
check "a Yes to the normalised name lets in another spelling" 0 "$(req "Other.Pkg==1.0")"
# An option line is approved only whole: a tab inside it must not split off a package name the owner said Yes to.
row "q-$today-100000-1-444444" "Dep requests" "Yes" >> "$LOG"
check "a package approval lets in no include line that names it after a tab" 2 "$(CONVEYOR_DEP_APPROVED=requests req $'-r\trequests\n')"
) > "$T/out.req" 2>&1 & started req

# Each part's checks, in the parts' order; a part that ended before its last line (an unset name under set -u) fails.
for p in "${PARTS[@]}"; do
  wait "${p#*:}"; rc=$?
  cat "$T/out.${p%%:*}"
  PASS=$((PASS + $(grep -c '^ok ' "$T/out.${p%%:*}"))) FAIL=$((FAIL + $(grep -c '^FAIL ' "$T/out.${p%%:*}")))
  [ "$rc" -eq 0 ] || check "the part ${p%%:*} ran to its end" 0 "$rc"
done
finish
