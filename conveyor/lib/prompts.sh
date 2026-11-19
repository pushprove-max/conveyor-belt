# SPDX-License-Identifier: Apache-2.0
# One field of the project pack in main's checkout (lib/pack.sh: checked against the schema first). Read when it is
# used, so a pack a card changed counts from the next use; a pack that fails the check fails that use.
# The file and the schema are read at every use; only a check that passed is kept, keyed on the exact text of both
# (PACK_OK), so the same text is not checked again and any other text, an older copy put back among them, is. A use
# in a subshell keeps nothing, so packget sets a variable of the shell that calls it rather than printing the value.
# A bash variable cannot hold a NUL byte, so a file with one is refused (JSON never holds one) rather than read short.
PACK=$MAIN/.conveyor/project.json
. "$HERE/lib/pack.sh" || exit 1
PACK_OK=()
packok() { # sets PACK_T and SCHEMA_T to the pack's and the schema's text, and checks it when it is not the kept one
  local a b
  [ -f "$PACK" ] || { echo "conveyor pack: $PACK: no such file" >&2; return 1; }
  PACK_T='' SCHEMA_T=''
  { IFS= read -r -d '' PACK_T; a=$?; } <"$PACK" && { IFS= read -r -d '' SCHEMA_T; b=$?; } <"$SCHEMA" || return 1
  [ "$a$b" = 11 ] || { echo "conveyor pack: $PACK, or the schema $SCHEMA: not readable JSON: it holds a NUL byte" >&2; return 1; }
  [ "${#PACK_OK[@]}" = 2 ] && [ "$PACK_T" = "${PACK_OK[0]}" ] && [ "$SCHEMA_T" = "${PACK_OK[1]}" ] && return 0
  NAMED=''
  a=$(packcheck "$PACK" "$PACK_T" "$SCHEMA_T" 2>&1) || { printf '%s\n' "$a" >&2; packnewer "$a" >&2; return 1; }
  packall || return 1
  PACK_OK=("$PACK_T" "$SCHEMA_T")
}
# The line an engine adds to its check's lines <lines> when they name a pack field its schema does not name: the pack
# may be for newer Conveyor than this one (a service left on an older engine). It names the fields, this engine's
# commit and the commit the project runs (the pack's plugin.commit, or the commit taken: ENGINE), read as plain JSON
# (the pack does not pass this engine's check), which the machine's service should run. Nothing for other lines, nor
# when the project runs this very commit, or names none: the field is then a mistake in the pack.
packnewer() { # <lines>
  local f p
  f=$(sed -n 's/^conveyor pack: .*: \(\.[^:]*\): not a field of the schema$/\1/p' <<<"$1" | paste -sd, - | sed 's/,/, /g')
  [ -n "$f" ] || return 0
  p=$(jq -r '.plugin.commit | strings' "$PACK" 2>/dev/null); [ -n "$p" ] || p=$(jq -r '.commit | strings' "$ENGINE" 2>/dev/null)
  [ -n "$p" ] && [ "$p" != "$OWN" ] || return 0
  echo "conveyor pack: $PACK: this Conveyor ($([ -n "$OWN" ] && echo "commit $OWN" || echo "the code of $HERE")) does not know $f: the pack is for newer Conveyor, commit $p; run conveyor.sh install-service in $MAIN to start the machine's Conveyor on the project's commit"
}
# Every field the schema names, read from the checked text in one jq run (PACK_V: field to value, as packget gives it),
# so a use of the same text, in this shell or a subshell started after, starts no program for it. A field the schema
# does not name (under additionalProperties), whose read fails (a field under one of another type: checks as an array)
# or whose value holds a NUL (\u0000 in the pack) is read by its own run, as before, failing as it did.
declare -gA PACK_V=()
packall() {
  local x_ i_
  PACK_V=()
  mapfile -d '' -t x_ < <(jq -js '.[0] as $v | .[1] as $s | def fields: (.properties // {}) | to_entries[]
      | .key as $k | select($k | contains(".") | not) | $k, (.value | fields | "\($k).\(.)");
    ($s | fields as $f | try ([('"$GET"')] | first // "") catch empty | select(explode | all(. != 0)) | $f + "\u0000" + . + "\u0000"),
    "end\u0000"' <<<"$PACK_T"$'\n'"$SCHEMA_T") \
    && [ $((${#x_[@]} % 2)) = 1 ] && [ "${x_[-1]}" = end ] || return 1
  for ((i_ = 0; i_ < ${#x_[@]} - 1; i_ += 2)); do PACK_V[${x_[i_]}]=${x_[i_ + 1]}; done
}
# Several fields are read in one jq run (each value ended by a NUL), so a step that needs many starts one program; one
# whose fields are all in PACK_V starts none.
packget() { # <field> <variable> [<field> <variable>]...: sets each variable to its field's value (both texts on jq's input, not as arguments)
  local f_=() v_=() x_=() i_
  while [ $# -ge 2 ]; do f_+=("$1"); v_+=("$2"); shift 2; done
  packok || return 1
  for i_ in "${f_[@]}"; do [[ -v PACK_V[$i_] ]] || break; x_+=("${PACK_V[$i_]}"); done
  [ "${#x_[@]}" = "${#f_[@]}" ] || { x_=(); mapfile -d '' -t x_ < <(jq -js '.[0] as $v | .[1] as $s | $ARGS.positional[] as $f | ([('"$GET"')] | first // "") + "\u0000"' \
      --args "${f_[@]}" <<<"$PACK_T"$'\n'"$SCHEMA_T") && [ "${#x_[@]}" = "${#f_[@]}" ]; } || return 1
  for i_ in "${!v_[@]}"; do printf -v "${v_[i_]}" '%s' "${x_[i_]}"; done
}
# The pack's names: the remote and branch a card lands on and the loop pushes to (REMOTE, BRANCH), the labels
# (BUILT, FOLLOWUP, TYPE, PRIOS, AREA, NONPRODUCT), the owner whose yes a visible change needs (OWNER), and what is
# made of them, of the product paths, of the test files' globs (tests.patterns) and of review.proof: PRODUCT, TESTRX,
# TESTGLOBS, YES, REVIEW and REVIEWOFF. Read at the start of every
# command that uses them and again at every turn of the loop, so a pack a card changed counts from the next turn; a
# pack that fails the check fails that command, or holds that turn's push and pick.
# BUILT is built and merged, open until the owner deploys it: such an issue looks like work not started, so it
# is never picked, follow-up or not. The owner sets and clears it; the loop never does.
# A string as a regular expression that matches it and nothing else, as jq and grep -E take one.
RX='def rx: gsub("(?<c>[][\\\\.^$|?*+(){}])"; "\\\(.c)");'
# A glob of the pack's tests.patterns as a regular expression of a path from the repository root (jq and grep -E take
# it): * and ? match within one folder name, ** across folders, a glob ending in / matches every file under such a
# folder, and a glob matches at any depth (after a /) unless it starts with /, which ties it to the root.
GLOBRX=$RX'def globrx: (if startswith("/") then "^" else "(^|/)" end) as $a | endswith("/") as $d
  | ltrimstr("/") | [scan("\\*\\*/|\\*\\*|\\*|\\?|[^*?]+")
    | if . == "**/" then "([^/]*/)*" elif . == "**" then ".*" elif . == "*" then "[^/]*" elif . == "?" then "[^/]" else rx end]
  | $a + join("") + (if $d then "" else "$" end);
  def globsrx: "(" + (map(globrx) | join("|")) + ")";'
# What names sets is kept while the pack's and the schema's text are those it read (NAMED, cleared by packok when either
# changes), so a turn on an unchanged pack starts no program for it. Main's package.json, whose scripts can name the
# test runner (runnerfiles()), is read too: when its text is not the one kept (NAMED_PJ), names makes all again.
NAMED='' NAMED_PJ=''
names() {
  local p x r y t pj=''
  packok || return 1
  [ ! -f "$MAIN/package.json" ] || IFS= read -r -d '' pj < "$MAIN/package.json" || :
  [ "$pj" = "$NAMED_PJ" ] || NAMED=''
  [ -z "$NAMED" ] || return 0
  packget remote REMOTE defaultBranch BRANCH owner.name OWNER labels.built BUILT labels.followup FOLLOWUP labels.type TYPE \
      labels.areaPrefix AREA labels.priorities PRIOS labels.nonProductAreas NONPRODUCT productPaths p review.proof r tests.patterns t \
    && mapfile -d '' -t x < <(jq -j --argjson t "$t" "$GLOBRX"'(map(rx) | "^(" + join("|") + ")"), join(", "), ($t | globsrx), ($t | join(", ")) | . + "\u0000"' <<<"$p") \
    && [ "${#x[@]}" = 4 ] || return 1
  # The test files' expression (TESTRX) and globs (TESTGLOBS), which testpaths() (lib/issues.sh) and bugproof() read.
  # shellcheck disable=SC2034 # TESTRX and TESTGLOBS are read in lib/issues.sh and lib/testrun.sh
  PRODUCT=${x[0]} p=${x[1]} TESTRX=${x[2]} TESTGLOBS=${x[3]}
  # The runner files (SUITERUNNERS, runnerfiles(), which no per-file run runs: filecmd(), lib/testrun.sh), and of
  # them those tests.patterns match (through testpaths() while TESTRUNNERS is empty), which testpaths() leaves out of
  # the test files from then on.
  # shellcheck disable=SC2034 # TESTRUNNERS is read in lib/issues.sh, lib/testrun.sh and lib/testmap.sh
  TESTRUNNERS=''
  SUITERUNNERS=$(runnerfiles)
  # shellcheck disable=SC2034
  TESTRUNNERS=$(testpaths <<<"$SUITERUNNERS"); NAMED_PJ=$pj
  YES="visible to customers or staff: needs $OWNER's yes: "
  [ "$r" = real ] && r=$REALPROOF || r=''
  REVIEW=${REVIEWT//'<owner>'/"$OWNER"}; REVIEW=${REVIEW//'<product paths>'/"$p"}; REVIEW=${REVIEW//'<real proof>'/"$r"}
  REVIEWOFF=${REVIEW//'<yes>'/"$NOYESREVIEW"}; y=${YESREVIEW//'<owner>'/"$OWNER"}; REVIEW=${REVIEW//'<yes>'/"${y//'<product paths>'/"$p"}"}
  tunables && NAMED=1
}
# The files the pack's test commands run as the project's test runner (#350), one a line: each tracked file of main's
# checkout that a word of test.command, test.full, test.main or test.fileCommand names (quotes and a leading ./ taken off; of an
# --option=<value>, the value), and so of each package script those commands run (npm test or t, npm run <name>,
# yarn, pnpm or bun <name> or run <name>: its package.json scripts entry, with its pre and post entries), and of each
# shell script among those files (a .sh file, or one whose first line names sh or bash) the file each of its commands
# starts by a path written in it (its first word after env settings, exec, env, timeout and the shell, node or python
# that runs it; a word with a $ in it, as the test file of `bash "$t"`, and a script's other words, such as the test
# files a selector names, are no runner), up to three files or scripts deep; and each
# of test.wholeCommands, the pack's runners of the whole suite. Such a file is the runner, not a test: given no list,
# it runs every test.
# shellcheck disable=SC2034 # used in lib/testrun.sh and lib/testmap.sh
RUNNERFIX='the test runner, not a test'
runnerfiles() {
  local c a b e mc ws w s r q=() n=() seen=' ' d=0 i cs=() pj=$MAIN/package.json m
  packget test.command c test.full a test.main mc test.fileCommand b test.wholeCommands e 2>/dev/null || return 0
  # Each to read: W, a command whose every word counts; F, a shell script's text, whose commands' first words count.
  q=("W$c" "W$a" "W$mc" "W$b")
  # The schema's default, [], names none: no jq for it.
  [ "${e:-[]}" = '[]' ] || while IFS= read -r w; do [ -z "$w" ] || cs+=("${w#./}"); done < <(jq -r '.[]? | strings' <<<"$e" 2>/dev/null)
  while [ ${#q[@]} != 0 ] && [ $d -lt 4 ]; do
    n=("${q[@]}"); q=(); d=$((d + 1))
    for c in "${n[@]}"; do
      m=${c:0:1}; c=${c:1}
      # Each command of it (split at && || ; | and parentheses, and lines), word by word.
      c=${c//'&&'/$'\n'}; c=${c//'||'/$'\n'}; c=${c//[;|()]/$'\n'}
      while IFS= read -r s; do
        read -ra ws <<<"$s"; [ ${#ws[@]} != 0 ] || continue
        if [ "$m" = F ]; then
          # A script's command: its first word after the env settings, wrappers and the program that runs the file.
          [[ ${ws[0]} != \#* ]] || continue
          i=0
          while [ $i -lt ${#ws[@]} ]; do
            case ${ws[i]} in
              [A-Za-z_]*=*|exec|env|command|nohup|time|timeout|then|do|else|'!'|bash|sh|zsh|dash|node|python|python3|-*) ;;
              # timeout's duration.
              *) [[ ${ws[i]} =~ ^[0-9.]+[smhd]?$ ]] || break ;;
            esac
            i=$((i + 1))
          done
          ws=("${ws[@]:i:1}")
        fi
        for w in "${ws[@]}"; do
          w=${w//[\"\']/}; [[ $w != -*=* ]] || w=${w#*=}; w=${w#./}
          [ -n "$w" ] && [[ $w != -* && $w != *[\$*?]* && $w != /* ]] || continue
          cs+=("$w")
          # A shell script it names, read once, whose commands start files too.
          [[ $seen != *" F:$w "* ]] && [ -f "$MAIN/$w" ] || continue
          [[ $w == *.sh ]] || head -n 1 "$MAIN/$w" 2>/dev/null | grep -qE '^#!.*[/ ](ba)?sh([[:space:]]|$)' || continue
          seen+="F:$w "; q+=("F$(sed -E 's/(^|[[:space:]])#.*//' "$MAIN/$w")")
        done
        # The package script it runs: its first word after the env settings is the package manager, and of the words
        # after that which are no options, the first names the script (test or t: test; run or run-script: the next).
        i=0; while [ $i -lt ${#ws[@]} ] && [[ ${ws[i]} == [A-Za-z_]*=* ]]; do i=$((i + 1)); done
        case ${ws[i]:-} in npm|pnpm|yarn|bun) ;; *) continue ;; esac
        r=(); for w in "${ws[@]:i+1}"; do [[ $w == -* ]] || r+=("$w"); done
        w=${r[0]:-}; case $w in run|run-script) w=${r[1]:-} ;; t) w='test' ;; esac
        [ -n "$w" ] && [ -f "$pj" ] || continue
        for s in "pre$w" "$w" "post$w"; do
          [[ $seen != *" $s "* ]] || continue; seen+="$s "
          s=$(jq -r --arg s "$s" '.scripts[$s] // empty | strings' "$pj" 2>/dev/null) && [ -n "$s" ] && q+=("W$s")
        done
      done <<<"$c"
    done
  done
  [ ${#cs[@]} != 0 ] || return 0
  # Each tracked file a word names, once, in git's order (by bytes, as LC_ALL=C sort's); a word that names a folder
  # lists the files under it, which are no file a word names. By the shell, not sort and grep: names() runs this in
  # every snapshot.
  local -A want=() got=()
  for w in "${cs[@]}"; do want[$w]=1; done
  while IFS= read -r w; do [ -z "${want[$w]:-}" ] || [ -n "${got[$w]:-}" ] || { got[$w]=1; printf '%s\n' "$w"; }; done \
    < <(git -C "$MAIN" -c core.quotePath=false ls-files -- "${cs[@]/#/:(literal)}" 2>/dev/null)
  return 0
}
# The pack's tunables (plan section 5), each the pack's value, else the schema's default; in seconds. TUNED is the
# pack's own tunables object, so health can say which home each value came from.
# POLL: a loop with a free builder slot looks for an issue at least this often. IDLE: `serve` with no card in flight
# and no issue to pick looks again after this. STUCK: `health` lists an open card with no new line and no output for
# this long (a card waiting at its claim brings its output up to date each poll), and one waiting longer than this on a
# card that is not alive; a build, fix, rebase or review with no progress for this long is ended and runs once more
# (watch()). SESSION_STUCK: a card whose session (build, fix, rebase) has had no output for this long is
# listed too, when that is sooner. CASE_STUCK: so is a card whose test step has one case running for this long (the
# ceiling of one case). WAIT_LIMIT, in minutes (waitLimitMin): so is a card that has waited on other cards for longer
# than this in total. SAMPLE: a sample is taken at most this often. LIVE: a running step's live record is brought up to date
# this often; `watch` streams it. CLOSE_WAIT: after a push, GitHub is given this long to show a landed card's
# issue closed. PUSH_RETRY: a failed push is tried again at least this often. PUSH_TIMEOUT: the pre-push hook caps its
# fast checks at 600 s. TEST_TIMEOUT: its clock starts once the run has its test slot (tests()), not while it waits for one, and stops while a runner of it waits for a whole-suite turn (testclock). LIMIT_TTL: the weekly
# limit reading is asked for again once the last asking is this old. LIMIT_OLD: a reading older than this is no reading.
# REVIEW_PAUSE: a review that ended with no verdict, and a session or review ended for no progress, runs once more after this pause (reviewed(), session1()).
# API_PAUSE: a session the model API refused runs again after 1, 2, 4 and 8 times this, and the loop picks no card
# for 5 times this after such an error (session(), apifresh()). A card blocked by a session that never began its work
# gets a check session at most this often (startagain()).
# TESTACTION_TIMEOUT (testActionTimeout): a test action's session (testaction()) is ended once it has run this long.
TUNABLES='poll idle stuck sessionStuck caseStuck waitLimitMin sample live closeWait pushRetry pushTimeout buildTimeout reviewTimeout testTimeout limitTtl limitOld reviewPause apiPause testActionTimeout'
tunables() {
  local t
  packget tunables TUNED && t=$(jq -r --slurpfile s "$HERE/schema/pack.schema.json" --arg k "$TUNABLES" \
      '(($s[0].properties.tunables.properties | map_values(.default)) + .) as $t | $k | split(" ") | map($t[.] | tostring) | join(" ")' <<<"$TUNED") \
    && read -r POLL IDLE STUCK SESSION_STUCK CASE_STUCK WAIT_LIMIT SAMPLE LIVE CLOSE_WAIT PUSH_RETRY PUSH_TIMEOUT BUILD_TIMEOUT REVIEW_TIMEOUT TEST_TIMEOUT LIMIT_TTL LIMIT_OLD REVIEW_PAUSE API_PAUSE TESTACTION_TIMEOUT <<<"$t"
}
# Does a visible change need the owner's yes? The control record's rule (rules.visible), off by default
# (lib/control-defaults.json), and on when the record cannot be read. Off, no card or issue waits for a `Visible change approved:` line, and no brief or review
# asks for one.
yesrule() { # [the control record, when the caller has read it]
  [ "$(jq -r '.rules.visible' <<<"${1:-$(ctl 2>/dev/null)}" 2>/dev/null)" != false ]
}
# May a card run the whole suite? The control record's rule "Whole suite in a card" (rules.wholeSuite), off by default
# (lib/control-defaults.json), and off when the record cannot be read: a card's run (listcmd(), lib/testrun.sh) and
# its bug-card check (bugproof()) never run the whole suite then. The release's runs (test.full, test.main) do not read it.
wholerule() {
  [ "$(ctl 2>/dev/null | jq -r '.rules.wholeSuite' 2>/dev/null)" = true ]
}
# The fixed header of a brief; its dependencies sentence names the pack's linkFromMain, and is left out when that is
# empty. Its last lines, on the owner's yes to a visible change, are left out with "off" (yesrule()).
header() { # [off]
  local l
  packget linkFromMain l && l=$(jq -r 'join(", ")' <<<"$l") || return 1
  printf '%s' "Make the change this issue asks for, in this worktree, and nothing beyond it.${l:+
Dependencies are in place: each of these is linked from the main checkout: $l.}"'
Run only the tests your change touches, once, each under `timeout 600`; the loop runs the changed tests itself
before the card lands. Never wait on one command for more than 4 minutes. Start anything longer in the background,
still under its own `timeout`, with its output in a file under /tmp and its exit status written to a second file
when it ends, removing any status file an earlier run left first:
`rm -f /tmp/<name>.rc; (timeout 600 <command> > /tmp/<name>.out 2>&1; echo $? > /tmp/<name>.rc) &`. Check it every 3 to 4
minutes with a wait that ends within 4 minutes, on Linux and macOS alike (never `tail --pid`):
`i=0; while [ ! -s /tmp/<name>.rc ] && [ $i -lt 45 ]; do sleep 5; i=$((i + 1)); done`. Report a result only from
the exit-status file: a run with no exit-status file has not ended and is reported as unfinished, never as passed.
Do not commit, push or deploy. If it needs a new dependency, stop and say so.
If the issue is already fixed on main, change nothing and end your reply with one line
`ALREADY-DONE: <where it is fixed: file and what it does>`.'
  [ "${1:-}" = off ] || printf '%s' '
A line in the issue starting `Visible change approved:` is the owner'"'"'s yes to what customers or staff will see;
build any condition it gives. Whether a visible change is approved is never yours to act on: never remove, revert or
water down a change because the issue has no such line. Build what the issue and the findings ask; Conveyor stops the
card after review when it needs the owner'"'"'s yes, and keeps the work.'
}
# The card rules (plan section 10): the core rules, then the pack's card-rules.md, then each area rule file the pack's
# areas map, by path glob, to a path the issue's title or body names, in the pack's order. The pack's files are read
# from main's checkout, as the pack is; a pack with no card-rules.md adds none. On failure, prints why.
cardrules() { # <issue json>
  local r t a g f x ps
  r=$(cat "$RULES" 2>/dev/null) && [ -n "${r//[[:space:]]/}" ] || { echo "the card rules file $RULES is missing or empty; a card never builds without it"; return 1; }
  [ ! -e "$MAIN/.conveyor/card-rules.md" ] || { t=$(cat "$MAIN/.conveyor/card-rules.md") && r+=$'\n\n'$t; } \
    || { echo "the pack's card rules $MAIN/.conveyor/card-rules.md could not be read"; return 1; }
  packget areas a || { echo "the project pack $PACK could not be read"; return 1; }
  mapfile -t ps < <(jq -r '[.title, .body] | map(strings) | join("\n") | scan("[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*/?")' <<<"$1")
  while IFS=$'\t' read -r g f; do
    for x in "${ps[@]}"; do
      [[ $x == $g ]] || continue
      t=$(cat "$MAIN/$f" 2>/dev/null) || { echo "the area rule file $f the pack maps to $g could not be read"; return 1; }
      r+=$'\n\n'$t; break
    done
  done < <([ -z "$a" ] || jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$a")
  printf '%s' "$r"
}
# The card's settings file (plan section 10), written to <file>: the generic card settings, with the hooks of the
# pack's .conveyor/hooks.json (Claude Code's hooks.json shape, {"hooks": {<event>: [<matcher group>...]}}) after the
# generic ones of each event. A pack adds hooks, never removes or changes one: nothing else of its file is read, and a
# file of another shape fails. A pack with no hooks.json adds none. The generic hooks run from their pinned path, the
# engine's own checkout: a generic command starting "$CLAUDE_PROJECT_DIR" starts with that checkout instead, so a
# project without those hook files still runs them. The pack's hooks are the project's own and stay as written.
cardsettings() { # <file>
  local h=$MAIN/.conveyor/hooks.json p='{"hooks":{}}'
  [ ! -e "$h" ] || p=$(cat "$h") || return 1
  jq -e --argjson p "$p" --arg root "${HERE%/*}" 'if $p | type == "object" and keys == ["hooks"] and (.hooks | type == "object" and all(.[]; type == "array"))
    then .hooks |= ((. // {}) | map_values(map(.hooks |= map(if .type == "command"
          then .command |= (if startswith("\"$CLAUDE_PROJECT_DIR\"") then "\u0027\($root | gsub("\u0027"; "\u0027\\\u0027\u0027"))\u0027" + ltrimstr("\"$CLAUDE_PROJECT_DIR\"") else . end)
          else . end))))
      | .hooks = reduce ($p.hooks | to_entries[]) as $e (.hooks; .[$e.key] = (.[$e.key] // []) + $e.value)
    else error("\($h) is not {\"hooks\": {<event>: [...]}}") end' --arg h "$h" "$CARD_SETTINGS" > "$1"
}
# The writing method: the pinned copy of the STE80 Humanizer in this engine (rules/ste80.md, its licence beside it).
# STE is the one block the reviewer (REVIEWT) and the judge (JUDGE, review.sh) are both given, so the findings, the
# judge's reasons and the issue bodies made of them read plainly on the Board. A session with no shell reads its copy
# of the file in the folder beside the worktree (noshell(), review.sh). The block holds no single quote.
STE80=$HERE/rules/ste80.md
STE='Write all the text that you write by the method in the file '"$STE80"' (STE80 Humanizer). Apply both
of its passes: Pass 1 removes the signs of AI writing, and Pass 2 rebuilds each sentence 80% of the way to
ASD-STE100. Keep the form that these instructions give each line: `[P1] file:line what. Proof: ...` for a finding,
`F<n> ACCEPT: ...` or `F<n> DECLINE: ...` for a decision. Do not change the names of files, commands, settings
and functions.'
# The review prompt, with the pack's owner, product paths and realistic-proof bar put in their places by names().
# Its first sentence (REVIEWHEAD) asks for a review of the whole staged change; the review of a fix alone (FIXREVIEW,
# card()) is given FIXREVIEW in its place.
REVIEWHEAD='Review the staged change in this worktree (`git diff --cached`) against the issue below.'
# shellcheck disable=SC2034 # used in lib/card.sh and lib/review.sh
FIXREVIEW='Review the fix of the last review'"'"'s findings, not the whole staged change: the rest of the change passed
its earlier review. The fix'"'"'s diff and the findings it was told to fix are under `# This review follows a fix`
below. The staged change (`git diff --cached`) and the issue below are context for the fix only.'
REVIEWT=$REVIEWHEAD' Do not run tests or
builds. Do not write that tests or builds were not run. The card rules, under `# Rules` below when a card has them,
are the builder'"'"'s standard: hold the change to them. Their lines about how to write a reply are for the builder only.
Report only what is wrong with this change for this issue, one line each: `[P0|P1|P2|P3] file:line what.
Proof: <proof>`. The levels:
- P0: the change breaks main, loses data or opens a security hole.
- P1: the change does not do what the issue asks, or breaks behaviour the project uses today.
- P2: a real defect with a limited effect.
- P3: a real but minor defect with no wrong result that users or the next card meet (for example a misleading
  name or message, a small inconsistency, or dead code the change left).
The proof ends the line: the input or command that fails, or the exact line (code, test, comment
or doc) that is untrue after the change. A problem you cannot prove that way is one line `UNPROVEN: what`: it never
holds the verdict.<real proof> After each finding, look for the same mistake elsewhere in the staged change. One
mistake is one finding: name the other places in the same finding.
'"$STE"'
Read the change from three angles, in this one review:
- bypass and trust: can a check, guard or gate in this change be skipped, forged or made to pass when it should
  refuse? Look at every input the change trusts.
- behaviour: wrong results, edge cases, failure paths and callers the change breaks. Trace each changed branch with
  a concrete input.
- tests and words: a changed behaviour with no test, a test that cannot fail, and comments, rule text or docs the
  change leaves untrue.
Four checks hold on every review:
- every test the change adds names the bug it would catch, in its name or a one-line comment; one that names none,
  or whose assertion cannot catch the bug it names, is a finding.
- a test that only finds text in a source file (a regex match on a file it reads, a `grep -q` on a script), where
  the behaviour could be run, is a finding: it passes when nothing uses that text. One whose one-line comment says
  no behaviour can be run (a stylesheet rule in a test with no layout) is not.
- unrequested placeholder UI (a control that is always disabled, a stub screen, or copy such as "coming soon" that
  the issue does not ask for) is a P1 finding.
- a smaller change that fully solves the issue is a finding that names it and why it fully solves the issue; it is
  never a reason to cut scope the issue needs.
A problem outside the issue is one line `NEW CARD: what` and never holds the verdict. A step an operator must take,
in order, for the change to work once deployed (a migration before the deploy, a new environment value, a flag) is
no defect: write it as one line `ROLLOUT: <the action> | <what fails without it> | <file:line>`. It never holds the
verdict, and a defect is always a finding, never a ROLLOUT line. Write no other line: any other
line is read as a finding, except the two that end the review. Second to last line, exactly: `USER-VISIBLE: no`, or
`USER-VISIBLE: yes: <one sentence: what a customer or staff member would see or do differently>`. Answer it from
the change itself, whatever the issue says.<yes>
Last line, exactly: `VERDICT: GO` or `VERDICT: NO-GO`.'
# What REVIEW says in its <yes> place while the control record's rule "visible changes need the owner's yes" is on
# (yesrule(); REVIEW), and while it is off (REVIEWOFF: no approval line is asked for or held to).
YESREVIEW=' A line in the issue starting `Visible change approved:` is the
owner'"'"'s yes to such a change: the answer is still yes, and a condition in that line that the change does not meet
is a finding. A missing approval line is not a finding: report a visible change on the USER-VISIBLE line only.
Answer the same whatever the change touches: only a change to product code (<product paths>, tests aside)
waits for that yes, but every review gives the line.
Approve before build. A product issue may hold a section headed `## What customers or staff
will see`: the screen, message or document, what it shows today and what it will show; or the one line `Nothing
visible changes.` An issue whose section names a change and has no `Visible change approved:` line is not picked: it
waits in "Needs you" to be approved before the build. Once approved, the build is held to that section, no more and
no less: for a card that touches product code, the reviewer answers on the USER-VISIBLE line whether what the change
shows matches it. A match lands with no second ask; any difference (more, less or other, wording included) stops the
card with its patch kept, and the ask names the difference only. An issue with no section, or whose section says
nothing visible changes, stops after review for <owner>'"'"'s yes when its change is visible, as before.'
NOYESREVIEW=' Every review gives the line, whatever the change touches.'
# What the review prompt says in its <real proof> place when the pack's review.proof is real (names()); with any,
# the default, it says nothing there.
REALPROOF=' A finding'"'"'s proof must happen with what the project really runs (its real config, commands and
inputs). A proof that needs a command paused by hand, a stub built to fail, or an input nobody in the project
produces goes on an `UNPROVEN:` line instead. A security finding (a way past a check, or to read or change data
without the right to) is exempt: it stays a finding with any proof that can be reproduced.'
# The review of a card whose session changed nothing and said ALREADY-DONE: is the issue already fixed on main?
CONFIRM='The build session for the issue below changed nothing in this worktree, which is main as it stands. It says
main already does what the issue asks; its ALREADY-DONE line is at the end of this message. Read the code and check
that claim against the issue. Do not run tests or builds and change nothing. Report each thing the issue asks for
that main does not already do, one line each: `[P0|P1|P2] file:line what`. Write no other line: any other line is
read as a finding. Last line, exactly: `VERDICT: GO` only if main already does what the issue asks, otherwise
`VERDICT: NO-GO`.'
# What the session that rebuilds a card after a landing conflict is told, after the brief; the conflict message and
# the path of the card's patch follow it (the path, never the patch: a prompt must not grow with the diff).
REBASE='# Landing conflict: apply the same change on top of main as it is now
The change this card made for the issue above passed review, but it no longer applies to main: another change
landed first. This worktree has been reset to main as it stands and does not hold the card'"'"'s change. Apply the same
change, the card'"'"'s own patch, on top of main as it is now. The patch is the file named below: read it there, in
parts if it is large (`git apply --3way <file>` applies what still fits). Resolve the conflict and change nothing
else: keep what main has gained, and add nothing the patch does not hold.'
# What the session that brings a card's change onto main as it is now is told before a review or landing,
# after the brief; the path of the card's patch follows it.
CAUGHT='# Main moved: apply the same change on top of main as it is now
Main has moved on since this card'"'"'s change was made (another card in flight may have landed a change to the same
files), and the card'"'"'s change no longer applies to it. This worktree has been reset to main as it stands and does
not hold the card'"'"'s change. Apply the same change, the card'"'"'s own patch, on top of main as it is now. The patch
is the file named below: read it there, in parts if it is large (`git apply --3way <file>` applies what still fits).
Resolve the conflict and change nothing else: keep what main has gained, and add nothing the patch does not hold.'
# The same session for a card stacked on another (stackto(), lib/claim.sh); @CARD@ is that card.
# shellcheck disable=SC2034 # used in lib/claim.sh
STACKED='# Stacked: apply the same change on top of main and the change of card @CARD@
Card @CARD@ changes the same files as this card and lands first. This card lands with it, after it. This worktree has
been reset to main with the change of card @CARD@ and does not hold the change of this card. Apply the same change, the
card'"'"'s own patch, on top of it. The patch is the file named below: read it there, in parts if it is large (`git
apply --3way <file>` applies what still fits). Resolve the conflict and change nothing else: keep the change of card
@CARD@, and add nothing the patch does not hold.'
# What the one review of a port is told, after REVIEW: the kept patch finished its review loop on the blocked
# card and only a landing conflict stopped it, so only what the port changed is reviewed again. The path of the file
# that holds that difference follows it (the path, never the difference: a prompt must not grow with the diff).
PORTREVIEW='# This review is of a port alone
The change below finished its review loop on this card or an earlier card of this issue, and only a landing conflict stopped it:
main had moved on. A session has since brought that change onto main as it is now. Review the port alone: a
conflict resolved wrongly, a part of the change lost, something added that the change did not hold, or a change main
made undone. Do not review the rest of the change again: it was reviewed. The difference between the kept patch and
the staged change, line for line (- is the kept patch, + the staged change), is the file named below. Its hunk
headers are kept: a changed header is main moving the lines, or the port changing another place than the patch did.
An empty file means the staged change is the kept patch exactly.'
# Does the owner's yes hold more than a plain yes? A `Visible change approved:` line that says anything beyond who,
# when and which ruling (the pack's owner, a date, a ruling id, "yes", the Board user who said it as the Board writes
# it, "(Board user <name>)", or "(Board user this device)" for the Board opened with no login on its own machine) may
# give a condition, and is taken as giving one.
conditional() { # <issue json>
  jq -e --arg o "$OWNER" "$RX"'($o | rx) as $o | .body // "" | split("\n") | any(select(startswith("Visible change approved:")) | ltrimstr("Visible change approved:")
    | gsub("\\(Board user ([A-Za-z0-9._-]{1,40}|this device)\\)|r-[0-9A-Za-z-]+|[0-9]{4}-[0-9]{2}-[0-9]{2}|\\b(" + $o + "|yes|ruling)\\b|[[:space:][:punct:]]"; ""; "i") != "")' <<<"$1" >/dev/null 2>&1
}
# A follow-up inherits its parent's yes. A follow-up Conveyor filed (its body opens "Follow-up
# to #N (Conveyor card ", or, a slice of a split, "Follow-up of #N: slice ") with no approval line of its own reads up its chain, up to MAX_DEPTH + 1 issues, for the
# first issue whose body has one, and prints {from, line, section, sentence}: that issue, its approval line, its section
# headed `## What customers or staff will see` ("" when none: a split parent's card ends before any review, so it has no review sentence), and the
# USER-VISIBLE sentence of its last review that gave one (the card records; "" when none is there). Nothing when the
# issue has its own line, is no follow-up, no issue up its chain has a line, or GitHub does not answer.
inherit() { # <issue json>
  local body p i=0 j l s sec
  body=$(jq -r '.body // ""' <<<"$1")
  ! grep -q '^Visible change approved:' <<<"$body" || return 0
  while [ $i -le "$MAX_DEPTH" ]; do
    p=$(head -n 1 <<<"$body" | sed -nE 's/^Follow-up to #([0-9]{1,9}) \(Conveyor card .*/\1/p; s/^Follow-up of #([0-9]{1,9}): slice [0-9]+ of [0-9]+\. Conveyor card .*/\1/p')
    [ -n "$p" ] || return 0
    i=$((i + 1))
    j=$(timeout 60 gh issue view "$p" --json number,body 2>/dev/null) && body=$(jq -er '.body // ""' <<<"$j" 2>/dev/null) || return 0
    l=$(grep -m 1 '^Visible change approved:' <<<"$body" | tr -d '\r')
    [ -z "$l" ] || break
  done
  [ -n "$l" ] || return 0
  sec=$(jq -r "$SEE"' section // ""' <<<"$j" 2>/dev/null)
  # The newest such review by its time, wherever it is kept (a retried card's lines are older than the current ones,
  # but not every time). The approval line is passed whole: a condition at its end must reach the reviewer.
  s=$(stdb ask issue retried "$p" -- issue cards "$p" 2>/dev/null | jq -rs --argjson n "$p" '[.[] | select(.issue == $n and .step == "review" and (.visible // "" | startswith("yes: ")))] | sort_by(.time // "") | last | .visible // "" | ltrimstr("yes: ")' 2>/dev/null)
  jq -cn --argjson f "$p" --arg l "$l" --arg c "$sec" --arg s "${s:0:1000}" '{from: $f, line: $l, section: $c, sentence: $s}'
}
# What the brief of a follow-up that may inherit a yes holds (both the session and the reviewer read it).
inherited_brief() { # <inherit json>
  local f l c s
  f=$(jq -r .from <<<"$1"); l=$(jq -r .line <<<"$1"); c=$(jq -r '.section // ""' <<<"$1"); s=$(jq -r .sentence <<<"$1")
  printf '# The yes of #%s\nThis issue is a follow-up of #%s, and the owner approved the change of #%s that customers or staff see. Its approval line:\n%s\n' \
    "$f" "$f" "$f" "$l"
  [ -z "$c" ] || printf 'What that change shows customers or staff, as its issue says:\n%s\n' "$c"
  [ -n "$c" ] && [ -z "$s" ] || printf 'What that change shows customers or staff, as its review said: %s\n' "${s:-not recorded}"
  ! conditional "$(jq -cn --arg b "$l" '{body: $b}')" \
    || printf 'That yes gives a condition. It holds for this follow-up too: hold the change to it.\n'
}
# What the reviewer of such a follow-up is asked, after REVIEW.
INHERIT='This issue is a follow-up of an issue whose visible change the owner approved; the brief below gives that
approval line (# The yes of #N) and what that change shows. A condition in that line is a condition this change must
hold to: one it does not meet is a finding. When your USER-VISIBLE answer is yes, write one more line just before it:
`INHERITED: part` when what customers or staff would see differently is part of that approved change (it fixes or
completes it), or `INHERITED: beyond: <one sentence: what goes beyond it>` when it does more than that change.'
# The reviewer's answer to it: "part", "beyond: <what>", or nothing when the review does not hold exactly one such line.
inheritance() { # <review file>
  [ "$(grep -c '^INHERITED:' "$1")" = 1 ] || return 0
  grep -E '^INHERITED: (part|beyond: .*[^[:space:]].*)[[:space:]]*$' "$1" | sed -E 's/^INHERITED: //; s/[[:space:]]+$//'
}
# Approve before build (the rule at the top). SEE reads an issue (jq): section is the text of its section headed
# `## What customers or staff will see` (to the next heading of level one or two, or an approval line; null when it
# has none, or an empty one); seen is "none", "nothing" (the section says `Nothing visible changes.`) or "change";
# approvals counts its lines starting `Visible change approved:`; before($area; $np) is an issue not to be picked yet: its section names a change and it has
# no approval line, and it is a product issue: its labels starting with the pack's areaPrefix ($area) are not
# only ones of its nonProductAreas ($np) (an issue with no area label counts as product); a tooling issue is picked as
# before. The section holds the build until a card stops for differing from it:
# an approval line written after that stop is the owner's yes to what that card shows (not any second line).
SEE='def section: [.body // "" | splits("\r?\n")] as $l
    | ([range($l | length) as $k | select($l[$k] | test("^##[[:space:]]+What customers or staff will see[[:space:]]*:?[[:space:]]*$"; "i")) | $k] | first) as $i
    | if $i == null then null else $l[$i + 1:] | ([range(length) as $k | select(.[$k] | test("^#{1,2}[[:space:]]|^Visible change approved:")) | $k] | first) as $e
      | (if $e == null then . else .[:$e] end) | join("\n") | sub("\\A[[:space:]]+"; "") | sub("[[:space:]]+\\z"; "") | if . == "" then null else . end end;
  def seen: section as $s | if $s == null then "none" elif $s | test("\\ANothing visible changes\\.?\\z"; "i") then "nothing" else "change" end;
  def approvals: [.body // "" | splits("\r?\n") | select(startswith("Visible change approved:"))] | length;
  def productissue($area; $np): [.labels // [] | .[].name | select(startswith($area))] | length == 0 or any(IN($np[]) | not);
  def before($area; $np): seen == "change" and approvals == 0 and productissue($area; $np);'
# The rank of an issue's priority, from its labels $l: the place of the first of the pack's priorities ($prio, most
# urgent first) it has; the number of priorities when it has none. The pick order uses the rank (every
# priority the pack declares keeps its place). Its level is "P<rank>", at most P3, and P3 when it has none, however
# few the pack declares: the control record's rules use it.
LEVEL='def rank($l; $prio): [range($prio | length) as $i | select($prio[$i] | IN($l[])) | $i] | first // ($prio | length);
  def level($l; $prio): rank($l; $prio) as $r | if $r == ($prio | length) then "P3" else [$r, 3] | min | "P\(.)" end;'
# What the reviewer of a card held to an approved section is asked, after REVIEW.
HELD='The owner approved, before the build, what this change is to show customers or staff: the part of the brief
headed `# The approved visible change` gives that section and the approval line. On this review the second to last
line answers whether the change matches it, in place of no or yes, exactly: `USER-VISIBLE: matches` when what the
change shows customers or staff is what that section says, no more and no less, or `USER-VISIBLE: differs: <one
sentence: only how it differs: more, less or other, wording included>` when it differs in any way. Answer it from
the change itself, whatever it touches.'
# The only lines of a review that are not findings. Every other line is one, whatever its shape, and holds a GO.
# An UNPROVEN line is a problem the reviewer could not prove: it never holds the verdict, is never filed or
# carried, and is not counted. A `DONE-WHEN: D<n> holds` line is the reviewer's word that a Done-when line's evidence
# holds (DONEWHENREVIEW); one that does not hold is a finding, so no other DONE-WHEN line is let through.
# An `EARLIER: E<n> holds` line is the reviewer's word that the fix of an earlier finding holds (REREVIEW).
# A `COVERED-BY: <test file>: <case>` line names the test that covers a case of a file an Optimize deletes (optproof()).
# A `ROLLOUT: <the action> | <what fails without it> | <file:line>` line is a step an operator must take, in order, to
# deploy the change (a migration before the deploy, a new environment value, a flag): no defect, so it holds no
# verdict, causes no fix round, is never filed or counted, and goes to the judge as no finding. It is kept on its own
# (rollouts()). Only a line of exactly that shape is one (ROLLOUT, after the prefix): any other line that starts so is a finding.
ROLLOUT='[^|]*[^|[:space:]][^|]* \| [^|]*[^|[:space:]][^|]* \| [^|[:space:]]+:[0-9]+[[:space:]]*$'
NOTFINDING='^(NEW CARD|UNPROVEN|DECLINED|MINOR|COVERED-BY|VERDICT|USER-VISIBLE|INHERITED):|^DONE-WHEN: D[0-9]+ holds[[:space:]]*$|^EARLIER: E[0-9]+ holds[[:space:]]*$|^ROLLOUT: '"$ROLLOUT"'|^[[:space:]]*$'
# The rollout actions a file names, as a JSON array of {action, fails, place} ([] when none): a review's ROLLOUT lines
# (prefix ROLLOUT) or a card's `Rollout:` commit trailers (prefix Rollout, trailerbrief()), each of the shape above.
# They are steps in order: each is kept once, where it is first named, and never sorted (ROLLOUTONCE).
ROLLOUTONCE='reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end)'
rollouts() { # <file> <prefix>
  { grep -E "^$2: $ROLLOUT" "$1" 2>/dev/null || :; } | jq -cRn --arg k "$2: " '[inputs | ltrimstr($k) | split(" | ") | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
    | {action: .[0], fails: .[1], place: .[2]}] | '"$ROLLOUTONCE"
}
# A `DECLINED:` line is a finding the judge declined (judged()), with the judge's reason: it holds no verdict, causes
# no fix round and is never filed. A `MINOR:` line is an accepted P3 finding while the control record's rule P3 is
# off (minor()): it is listed only, holds no verdict, causes no fix round and is never filed, but it is counted
# (counts()). Only the engine writes either: a line the reviewer starts so is a finding (review()).
# The lines a review's record line (reason) and a blocked card's comment leave out: the NEW CARD, UNPROVEN,
# DECLINED, MINOR and COVERED-BY lines stay there, so the dashboard's review text shows them, and the Tests page the
# test files that cover the cases of a file an Optimize deleted (testspart()).
# shellcheck disable=SC2034 # used in lib/card.sh, lib/followups.sh and lib/push.sh
UNRECORDED=${NOTFINDING/NEW CARD|UNPROVEN|DECLINED|MINOR|COVERED-BY|/}
# What the fix session after a NO-GO is told, after the brief; the review follows it, each finding led by its id
# (fixlines()).
FIX='# Reviewer findings: fix these findings, and every other place in this change that makes the same mistake; nothing else
An `UNPROVEN:` line is not a finding: change nothing for it. Each finding starts with its id (E1, E2 and so on):
the review after this fix names the finding by that id.'
# The Done-when check (donewhen(), checked()): what the one fix session after a failed check is told, after the brief;
# the failed items follow it. And what the review is told beside the card's D<n> lines.
DWFIX='# The Done-when check failed: fix these items, and end your reply with the whole `## Done when` section again
Each line of the issue'"'"'s `## Done when` needs a line `D<n> met: <evidence>` or `D<n> not met: <why>`, in order. Evidence
names something checkable: a test (file and case name), a file and line, or a command and its result. Every TODO
or [VERIFY] marker the change adds is named in the reply, on a line with its file.'
# The project's checks (treecheck(), checked() and the Test step): what the one fix session after they fail is told,
# after the brief; their output follows it.
# shellcheck disable=SC2034 # used in lib/testrun.sh and lib/card.sh
CHECKFIX='# The project'"'"'s checks failed: fix what they name and nothing else
These checks run after each session and before any review or test. Their output names each file and line. Fix each
one in the code: do not turn a check off. The checks run again on your change.'
DONEWHENREVIEW='# The card'"'"'s Done-when lines
The build session ended its reply with these lines, one for each line of the issue'"'"'s `## Done when`. For each, check
whether its evidence holds: write `DONE-WHEN: D<n> holds` when it does; a claim that is false (the evidence is not
there, or does not show the line holds) is a finding, written as any finding is. A `Note:` line names a file a D<n>
line gives that is not in the worktree: judge whether that line'"'"'s evidence still holds.'
# The bug-card check (bugproof(), card()): the reasons a bug card goes back to its build session or is blocked (UNFIXED
# only when its test files ran without the fix; NOTEST when the change has none, <patterns> the pack's tests.patterns;
# SHARED when its only new tests are inline tests that share lines with the fix in <file>;
# NOTALONE when the test command ran none of them; NOTBACK when main's code could not be put back for the run), what
# that session is told after the brief (<why>: the reason; the check's result follows it), and what the review is told
# before that result.
# shellcheck disable=SC2034 # used in lib/testrun.sh
UNFIXED='the new tests pass without the fix, so they do not prove it'
# shellcheck disable=SC2034 # used in lib/testrun.sh
NOTEST='no test file found in the change (patterns: <patterns>); set tests.patterns in .conveyor/project.json'
# shellcheck disable=SC2034 # used in lib/testrun.sh
SHARED='the new test and the fix are in the same lines of <file>; bugproof cannot take out the fix alone'
# shellcheck disable=SC2034 # used in lib/testrun.sh
NOTALONE='test files were found in the change, but the test command, given them, selected none of them, so they did not run without the fix; set test.fileCommand in .conveyor/project.json to a command that runs one test file'
# What the check's result and doctor say of a test command that, given <n> test files, ran <ran> (widewhy(), lib/issues.sh).
# shellcheck disable=SC2034 # used in lib/issues.sh
WIDE='the test command, given <n> test file(s), ran <ran> test files: it runs test files it is not given, so the bug-card check runs all of them; set test.fileCommand in .conveyor/project.json to a command that runs one test file'
# Why a card's test run, or its bug-card check, did not run or was stopped while the rule "Whole suite in a card"
# (rules.wholeSuite) is off (narrowstop(), lib/testrun.sh): <why> says what happened, and the rest names the settings
# that fix it.
# shellcheck disable=SC2034 # used in lib/testrun.sh
NARROW='the rule Whole suite in a card is off, and <why>; set test.list in .conveyor/project.json to the form the test command takes a list of test files in (args, placeholder with {files}, env or runner), or set test.fileCommand to a command that runs one test file'
# Why the bug-card check was stopped when, with that rule off, the test command was run with no list of test files to
# find whether the change selects a test of its own (bugproof(), lib/testrun.sh), and reported <ran> test files, more
# than the <n> that the test map and its links give the change and one for each file it touches (TEST_ADDS, tests()). test.list and test.fileCommand do not change this run.
# shellcheck disable=SC2034 # used in lib/testrun.sh
NARROWALONE='The rule Whole suite in a card is off. The test command ran with no list of test files, to find if the change selects a test of its own. It reported <ran> test files. That is more than the <n> test file(s) that the test map and .conveyor/test-links.json link to the change, with one more for each file that the change touches, so the run was stopped. To continue, turn on the rule Whole suite in a card on the Rules tab. Or link the changed files in .conveyor/test-links.json to the test files that the test command selects for them.'
# What a card's test step says when, with that rule off, no test file is linked to its change (listcmd()).
# shellcheck disable=SC2034 # used in lib/testrun.sh
NONELINKED='no test file is linked to the files the change touches, so no test ran; the release'"'"'s whole-suite run covers this change'
# What a card's test step says when, with that rule off, its change adds or changes no test file, so it runs <n> of
# the <all> test files linked to its change, at most CARDLINKED (the owner, 2026-11-18: listcmd(),
# testcap()).
# shellcheck disable=SC2034 # used in lib/testrun.sh
CARDLINKED=5
# shellcheck disable=SC2034 # used in lib/testrun.sh
LINKED='the change adds or changes no test file, so the card ran <n> of the <all> test files linked to it, those that failed most recently first. The run before the push runs all of them.'
# What a card's test step says when, with that rule off, it ran only the <n> cases its change adds or changes of <m>
# of its own test files (listcmd(), owncases(): #414), with OWNWHOLE when <w> of them ran whole; <s> is "s" for a
# count over 1.
# shellcheck disable=SC2034 # used in lib/testrun.sh
OWNCASES='the card ran <n> changed case<s> of <m> test file<s>'
# shellcheck disable=SC2034 # used in lib/testrun.sh
OWNWHOLE=', and <w> test file<s> whole'
# What the bug-card check says when, with that rule off, more test files are linked to its change than the pack's
# test.cardFiles (testcap()).
# shellcheck disable=SC2034 # used in lib/testrun.sh
CAPPED='<left> of the <all> test files linked to the change did not run, as a card runs at most <max> (test.cardFiles), those that failed most recently first. The release'"'"'s whole-suite run covers them.'
# shellcheck disable=SC2034 # used in lib/testrun.sh
NOTBACK='main'"'"'s code could not be put back, so the test files did not run without the fix'
# shellcheck disable=SC2034 # used in lib/card.sh
BUGBUILD='# Back to the build: <why>
This issue is a bug, so at least one test case your change adds or changes must fail on main'"'"'s code without your
fix (your test files alone, and the inline tests of your product files without the rest of their change, are run
in a worktree of main), and none does. Add or change a test case that fails on
main'"'"'s code without the fix and passes with it, and keep the fix. The check'"'"'s result:'
# shellcheck disable=SC2034 # used in lib/card.sh
BUGREVIEW='# The bug-card check
This issue is a bug: after the build, the test cases the change adds or changes were run on main'"'"'s code without the
fix (its test files alone, and the inline tests of its product files without the rest of their change, in a
worktree of main). At least one must fail there. A change to test files alone is not
run, as it has no fix to take out, nor is one whose product files change only comments. A change that selects no test of its own (comments only) is proved by the test
files its issue'"'"'s Done-when names instead, and is not checked when it names none. Its result:'
# What the review of a speed-up card (speedproof(), card()) is told before the check's result.
# shellcheck disable=SC2034 # used in lib/card.sh
SPEEDREVIEW='# The speed-up check
This issue speeds up one test file and keeps what it tests, so no test must fail on main'"'"'s code without the change.
After the build, the file was run alone with the change, on a test slot. It must pass, and its CPU seconds must be lower
than its median on record. Judge whether the file still tests all that it tested before. Its result:'
# What the review of an Optimize card (optproof(), card()) is told before the check's result.
# shellcheck disable=SC2034 # used in lib/card.sh
OPTREVIEW='# The Optimize check
This issue optimizes one test file: the change speeds it up, splits it, merges it into another test file or deletes
it, and keeps what it tests, so no test must fail on main'"'"'s code without the change. A file the change keeps, and the
test files a split adds, were run alone with the change, on a test slot: they must pass. A file kept must be faster
than its median on record; the files of a split, their CPU seconds summed, must take at most the file'"'"'s median plus a start-up allowance for each file the split adds. Judge whether the tests still test all
that the file tested before. Its result:'
# What the review of a Fix failures card (steadyproof(), card()) is told before the check's result.
# shellcheck disable=SC2034 # used in lib/card.sh
STEADYREVIEW='# The Fix failures check
This issue makes one test file pass reliably and keeps what it tests, so no test must fail on main'"'"'s code without
the change. After the build, the file was run alone with the change, on a test slot, 10 runs in a row: each must pass.
Judge whether the change removes the cause of its failures, and whether the file still tests all that it tested
before: a case deleted, skipped or weakened so that it passes is a finding. Its result:'
# What the review of the Board's other fix cards (#189; card(): Fix the waiting, Fix hollow cases, Delete it and Make
# it run) is told before the check's result.
# shellcheck disable=SC2034 # used in lib/card.sh
WAITREVIEW='# The Fix the waiting check
This issue removes or shortens the waits of one test file and keeps what it tests, so no test must fail on main'"'"'s
code without the change. After the build, the file was run alone with the change, on a test slot, 3 runs in a row: each
must pass and take at most 2 times its CPU seconds on the clock. Judge whether its cases still test all that they
tested before: a wait cut so that a case no longer checks what it waited for is a finding. Its result:'
# shellcheck disable=SC2034 # used in lib/card.sh
HOLLOWREVIEW='# The Fix hollow cases check
This issue makes each hollow case of one test file assert the behaviour it names, or deletes it when another test
already proves that behaviour. After the build, the judge'"'"'s hollow check, on a model of another family than the
builder'"'"'s where one is set up, read the file with the change: it must find no hollow case. Each deleted case needs a
COVERED-BY line in the build'"'"'s reply. Judge whether each case now asserts what it names, and whether the test each
COVERED-BY line names proves what its deleted case named. Its result:'
# shellcheck disable=SC2034 # used in lib/card.sh
DELREVIEW='# The Delete it check
This issue deletes one test file that has never run, so no test must fail on main'"'"'s code without the change. Each
case of it that matters must be proved by another test. Its result:'
# shellcheck disable=SC2034 # used in lib/card.sh
RUNREVIEW='# The Make it run check
This issue makes one test file run: the test command or the pack'"'"'s tests.patterns now take it, or what stopped it
loading is fixed. After this review, the card'"'"'s test step must run the file, and it must pass, or the card is
blocked. Judge whether the file now runs in each test run that should run it, and whether its cases test what they
name. Its result:'
# shellcheck disable=SC2034 # used in lib/card.sh
ALONEREVIEW='# The Make it run alone check
This issue makes one test file that only whole-suite runs ran (wholeOnly in the pack) run by itself, or moves what it
runs into test files the runner can list, and keeps what it tests. After the build, the pack must no longer mark the
file wholeOnly, and the file (or the test files the change adds in place of a file it removes) was run alone through
the pack'"'"'s test.list, with the change, on a test slot: it must pass. Judge whether the change keeps every check the
file ran: a check dropped so that the file can run alone is a finding. Its result:'
# What the review that follows a fix of review findings is told, in its brief (rereview()): REREVIEW, then
# REREVIEWALL when it reviews the whole change or REREVIEWFIX when it reviews the fix alone (fixonly()); the findings
# that fix was told to fix, its diff's path and the findings declined on this card follow it.
REREVIEW='# This review follows a fix of the last review'"'"'s findings
A fix session was told to fix the findings of the last review of this change, given below, each after its id (E1,
E2 and so on). Read what that fix changed first: its diff is the file named below. Then say for each of those
findings whether the fix holds: write `EARLIER: E<n> holds` when it does; one whose fix does not hold is a finding
again, written as any finding is with its id in brackets after its level mark and any kind mark (`[P1] [E2]
<file:line> ...`), at its
location now, its proof saying why the fix does not hold. A finding declined on this card (listed below, each with its
reason) is raised again only with a new, concrete reason its decline does not answer, given in its proof.'
# shellcheck disable=SC2034 # used in lib/testrun.sh
REREVIEWALL='A new defect anywhere in the change, in what the fix changed or elsewhere, may still be raised, at any level.'
# shellcheck disable=SC2034 # used in lib/testrun.sh
REREVIEWFIX='A new defect that the fix'"'"'s lines cause, in its diff or in the code that calls what it changed, may
still be raised, at any level. Do not review the rest of the change again: it passed its earlier review.'
# Dependencies. An issue body may hold lines `Depends on: #N` (several numbers on a line, comma
# separated); `owner/repo#N` there names issue N of another repository (farneeds, as "owner/repo#N"), never this
# one's #N. openissues() asks GitHub for the state of each and keeps it on the issue as far: {"owner/repo#N": {open,
# error}}; one with no state kept, or one that could not be read (error: what gh said), counts as open.
# An issue waits while any issue it depends on is open, and while any follow-up Conveyor filed from one
# of them is open, and theirs through the chain (a card is not built on work whose known
# faults are not fixed yet, and the follow-ups take priority). It is picked at the next poll after the last of them
# closes; closed for any reason (not planned, a withdrawn follow-up, too) clears it. One whose newest card (the card of
# its last first line: a later line of an older card, such as the pushed line of a push-now, does not make that card
# newest again) has a landed or pushed line clears it too, open or not: the change is on the main a card is built from,
# so with push off the issues that wait on it are not held until the push (landed($cards)). These read one list of open
# issues (number and body): needs is an issue's dependencies in this repository; ups($cards; $o) is the issues $o with the follow-ups
# filed from them and theirs, up to MAX_DEPTH (the card lines name them; a run limited by --only reads its
# set the same way); waits($cards; $open) an issue's open dependencies and their open follow-ups not landed, then the open ones of
# another repository (as "owner/repo#N"; nothing reaches past them, so no cycle goes through one); graph each open issue's
# open ones (through the follow-ups too), reach every open issue it waits on, through the chain, and cycles($cards)
# every set of open issues that wait on each other, through the follow-ups as well (an issue that depends on itself is one).
# waitsof($fc; $open; $done) is waits with what it reads of the lines worked out once for every issue: $fc the lines
# that name follow-ups, $done landed($cards); graph reads it so, and cyclesof($g) is cycles of a graph made already.
# Worked out again for each open issue, they were most of a snapshot's time on a long history.
# shellcheck disable=SC2034 # used in lib/issues.sh, lib/pick.sh, lib/run.sh, lib/snapshot.sh, lib/views.sh and lib/control.sh
DEPS='def deprefs: [.body // "" | splits("\r?\n") | select(test("^\\s*Depends on:")) | scan("(?:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#([0-9]+)")];
  def needs: [deprefs[] | select((.[0] // "") == "") | .[1] | tonumber] | unique;
  def farneeds: [deprefs[] | select((.[0] // "") != "") | "\(.[0])#\(.[1] | tonumber)"] | unique;
  def ups($cards; $o): reduce range('"$MAX_DEPTH"') as $_ ($o; . as $s | $s + [$cards[] | select(.followups and (.issue | IN($s[]))) | .followups[]] | unique);
  def landed($cards): reduce ($cards[] | select(.issue | type == "number")) as $l ({};
      ($l.issue | tostring) as $k | ($l.step | IN("landed", "pushed")) as $d
      | if .[$k].card == $l.card then .[$k].done = (.[$k].done or $d)
        elif .[$k].seen // [] | any(. == $l.card) then .
        else .[$k] = {card: $l.card, done: $d, seen: ((.[$k].seen // []) + [$l.card])} end)
    | [to_entries[] | select(.value.done) | .key | tonumber];
  def waitsof($fc; $open; $done): [ups($fc; needs)[] | select(IN($open[]) and (IN($done[]) | not))] + [farneeds[] as $r | select(.far[$r].open != false) | $r];
  def waits($cards; $open): waitsof($cards; $open; landed($cards));
  def graph($cards): map(.number) as $open | landed($cards) as $done | ($cards | map(select(.followups))) as $fc
    | map({key: (.number | tostring), value: waitsof($fc; $open; $done)}) | from_entries;
  def reach($g; $n): {seen: [], todo: ($g[$n | tostring] // [])}
    | until(.todo == []; .todo[0] as $x | .todo |= .[1:] | if .seen | any(. == $x) then . else .seen += [$x] | .todo += ($g[$x | tostring] // []) end) | .seen;
  def cyclesof($g): ($g | keys | map({key: ., value: reach($g; tonumber)}) | from_entries) as $r
    | [$r | to_entries[] | (.key | tonumber) as $n | select(.value | any(. == $n))
       | [.value[] | select(. as $m | $r[$m | tostring] // [] | any(. == $n))] | sort] | unique;
  def cycles($cards): cyclesof(graph($cards));'
# YES (names(), above) is how the reason of a card blocked for the owner's yes to a visible change begins; the
# reviewer's sentence follows it.
