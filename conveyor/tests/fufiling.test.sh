#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: how a review follow-up is filed (lib/followups.sh): which findings are held for the owner, which are
# privacy hits of the card's own change, the follow-up's title, and how it names its parent.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a pipeline file in Markdown emphasis made of underscores (__conveyor/lib/__) kept the "__" as part of its name,
# so a finding on it was not held for the owner. The pack's checked-in pipelineFiles, as a card of this repo reads them.
# shellcheck disable=SC1090 # sources one function cut from $SRC/lib/followups.sh by sed
t_fupipeunder() {
  local p f
  p=$(jq -c .pipelineFiles "$SRC/../.conveyor/project.json") || fail "the checked-in pack's pipelineFiles cannot be read"
  . <(sed -n '/^onpipeline() {/,/^}/p' "$SRC/lib/followups.sh")
  for f in '__conveyor/lib/__' '__conveyor/conveyor.sh__'; do
    [ "$(onpipeline "$f" <<<"$p")" = 1 ] || fail "onpipeline '$f' with the pipelineFiles $p did not print 1"
  done
}

# #1661: the follow-up card of a card with no GitHub issue and no parent issue names its parent by the branch a
# land-branch card landed (its picked line), else by its card id. Bug: its label read "Review follow-up of #" and its
# body "Follow-up to # (Conveyor card ...)", naming no parent. fuparent <branch or ""> <name it must have>.
fuparent() {
  local c=c20261101T000000-main-0
  setup "[$(issue 7 2026-01-01)]"; loop control rules followupissues=off > /dev/null || fail "control rules followupissues=off was refused"
  printf '%s\n' '[P2] a.txt:1 the word is wrong' 'VERDICT: NO-GO' > "$STUB/r.review"
  jq -cn --arg b "$1" '{title: "t"} + if $b == "" then {} else {branch: $b} end' > "$STUB/picked.json" \
    && jq -cn '{number: 0, title: "t", body: "b", labels: [], milestone: null}' > "$STUB/parent.json" || fail "the fixture's JSON could not be written"
  fx_in 'append "$(line '"$c"' 0 picked ok "$(cat "$STUB/picked.json")")" && followups '"$c"' "$(cat "$STUB/parent.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(jq -c '.cards[0] | [.label, (.body | split("\n")[0] | startswith("Follow-up to '"$2"' (Conveyor card '"$c"')."))]' "$ST/testactions/cards.json")" = "[\"Review follow-up of $2\",true]" ] \
    || fail "followups of card $c (issue 0, picked line branch '${1:-none}') did not name its parent '$2' in the label and body (exit $RC): $(cat "$T/$CASE/run.out") $(cat "$ST/testactions/cards.json" 2>&1)"
}
t_fuparentbranch() { fuparent hand/fix hand/fix; }
t_fuparentcard() { fuparent '' c20261101T000000-main-0; }
# A follow-up filed as a GitHub issue (followupissues on) keeps "Follow-up to #<n> (Conveyor card": the picker's wait for
# its parent to land (jq/upnext.jq) and Needs you (snapshot.sh) match only that form. Bug: it read "Follow-up to hand/fix",
# so the picker could take it before its parent landed.
t_fuparentissue() {
  local c=c20261101T000000-main-0
  setup "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P2] a.txt:1 the word is wrong' 'VERDICT: NO-GO' > "$STUB/r.review"
  jq -cn '{title: "t", branch: "hand/fix"}' > "$STUB/picked.json" \
    && jq -cn '{number: 0, title: "t", body: "b", labels: [], milestone: null}' > "$STUB/parent.json" || fail "the fixture's JSON could not be written"
  fx_in 'append "$(line '"$c"' 0 picked ok "$(cat "$STUB/picked.json")")" && followups '"$c"' "$(cat "$STUB/parent.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && jq -e -s 'length == 1 and (.[0].body | test("^Follow-up to #[0-9]+ \\(Conveyor card c20261101T000000-main-0\\)"))' "$STUB/filed" > /dev/null \
    || fail "followups of card $c (issue 0, picked line branch hand/fix, follow-up issues on) did not file one issue whose body starts 'Follow-up to #<n> (Conveyor card $c)' (exit $RC): $(cat "$T/$CASE/run.out") $(cat "$STUB/filed" 2>&1)"
}

# Bug: a finding on the card's own file that also names a new file in a tracked folder (conveyor/lib/newguard: no
# extension, not tracked yet) counted only the card's file, so it was let through with no one asked; in Markdown
# emphasis (__conveyor/lib/newguard__) its "_" kept it from naming the tracked folder, and in a new folder
# (conveyor/lib/guards/newguard) its folder had no tracked file.
# shellcheck disable=SC1090 # sources one function cut from $SRC/lib/followups.sh by sed
t_fuownnew() {
  local d=$T/$CASE/wt f out
  mkdir -p "$d/conveyor/lib" && echo one > "$d/conveyor/lib/followups.sh" && git -C "$d" init -q && git -C "$d" add -A \
    && git -C "$d" -c user.name=t -c user.email=t@example.com commit -qm one && echo two >> "$d/conveyor/lib/followups.sh" \
    && git -C "$d" add -A || fail "the worktree with conveyor/lib/followups.sh staged could not be made"
  . <(sed -n '/^ownonly() {/,/^}/p' "$SRC/lib/followups.sh")
  for f in '[P1] conveyor/lib/followups.sh:204 Add conveyor/lib/newguard' '[P1] conveyor/lib/followups.sh:204 Add __conveyor/lib/newguard__' \
    '[P1] conveyor/lib/followups.sh:204 Add conveyor/lib/guards/newguard'; do
    out=$(ownonly "$f" "$d")
    [ -z "$out" ] || fail "ownonly '$f' with only conveyor/lib/followups.sh staged printed '$out', not nothing"
  done
}

# Bug: privown() found a home path in the card's added lines when the line held it only as a folder under a variable
# ($C<home>/hf, which the privacy check does not flag), so a card was sent to a privacy fix round for nothing. The
# PATH line is flagged for <home>/hf2 only: a finding quoting <home>/hf matched the flagged word as a substring, and
# taking <home>/hf out of it took the hit <home>/hf2 out too.
t_fuprivvar() {
  local H=${HX%/*} # /home, put together as HX is
  setup "[$(issue 7 2026-01-01)]"; fx_wt "printf '%s\n' 'cd \$C$H/hf' 'PATH=\$C$H/hf:$H/hf2' >> a.txt" b.txt b
  printf '%s\n' "[P0] a.txt:3 flags $H/hf" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  fx_in 'privown "$FXWT"'
  [ "$RC" = 0 ] && [ ! -s "$T/$CASE/run.out" ] \
    || fail "privown with the added line 'cd \$C$H/hf' and 'PATH=\$C$H/hf:$H/hf2', and a finding quoting $H/hf, did not print nothing (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Bug: a finding that quotes the card's added home path in its escaped form (\/<home>\/x\/bench) was not matched to the
# added line, so the hit was filed as a follow-up and would land on main. The added word holds a second home path:
# with the quoted one taken out the check still flagged it, so the hit was missed. The change also adds over 128 KiB (big.txt):
# the added lines went to jq as one argument, which Linux refuses, so the check failed and printed nothing.
t_fuprivesc() {
  local e="$HX/bench" y="${HX%/*}/y/bin"; e=${e//\//\\/}
  setup "[$(issue 7 2026-01-01)]"; fx_wt "printf 'PATH=%s/bench:%s\n' '$HX' '$y' >> a.txt && awk 'BEGIN { for (i = 0; i < 10000; i++) print \"plain filler words\" }' > big.txt" b.txt b
  printf '%s\n' "[P0] a.txt:3 flags $e" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$FXWT.review"
  fx_in 'privown "$FXWT"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "[P0] a.txt:3 flags $e" ] \
    || fail "privown with the added line 'PATH=$HX/bench:$y' and 190000 bytes in big.txt, and a finding quoting $e, did not print the finding (exit $RC): $(cat "$T/$CASE/run.out")"
}

# Bug: the title is the masked finding cut at 200 characters; an example.com address across that cut became
# the address with its last letter cut, which the privacy check flags as an email, so the follow-up was not filed and
# nothing landed.
t_futitlecut() {
  local a='[P2] b.txt:3 mails ' m=someone@example.com w f
  w=$(printf '%*s' $((181 - ${#a})) '' | tr ' ' y); f="$a$w $m about it"
  [ "${f:182:18}" = "${m:0:18}" ] || fail "the fixture's address does not straddle character 200: ${f:182:18}"
  setup "[$(issue 7 2026-01-01)]"; tune '.privacy.mode = "public"'
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[100101]' ] || fail "the follow-up of '$f' was not filed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r .title "$STUB/filed")" = "$a$w" ] || fail "the title of '$f' is not cut before the address: $(jq -r .title "$STUB/filed")"
}
