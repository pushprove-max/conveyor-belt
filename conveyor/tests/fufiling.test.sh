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
  # The record of cards with no issue holds another card, not this one, as when a land-branch card lands while a Foreman
  # order is queued. Bug: tcparent printed nothing for it, so the body read "Follow-up to # (Conveyor card".
  mkdir -p "$ST/testactions" && jq -cn '{cards: [{card: "c20261101T000000-main-1", title: "t", body: "b"}]}' > "$ST/testactions/cards.json" \
    || fail "the record of cards with no issue could not be written"
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

# Bug: a cut inside a code span left its opening backtick with no closing one, and the Board's fill() (app-text.js)
# drew that backtick as text in the Rules tab. The cut span is closed; a span with nothing of it left is dropped.
t_futitlecode() {
  local w f g
  w=$(printf '%*s' 170 '' | tr ' ' y)
  f="[P2] $w run \`conveyor.sh setup desktop now\` to fix it"
  g="[P2] $w and more words go \`\` conveyor.sh setup desktop \`\`"
  setup "[$(issue 7 2026-01-01)]"
  fx_in 'futitle "$f"; echo; futitle "$g"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "[P2] $w run \`conveyor.sh setup\`"$'\n'"[P2] $w and more words go" ] \
    || fail "futitle of '$f' and of '$g' did not close or drop the cut code span (exit $RC): $(cat "$T/$CASE/run.out")"
}

# #1736 D3: a card at depth 1 whose last review holds a P1, a P2 and a P3 harm finding files one follow-up, at depth 2,
# for the P1; the P2 and the P3 go on the self-heals list, under the parent's area, with FULOW as their reason. Bug: each
# got a follow-up of its own, so each follow-up card spawned more cards for findings that block nothing. The P2 comes
# first: withdrawing the follow-up (unfile()) still pairs #100101 with the P1, not with a finding that was not filed.
t_fulowp2() {
  local p='[P1] a.txt:1 the count is off by one' q='[P2] a.txt:2 the word is wrong' r='[P3] a.txt:3 the name is odd'
  setup "[$(issue 7 2026-01-01 area:engine | jq -c '.body = "Follow-up to #6\n\nFollow-up depth: 1"')]"
  printf '%s\n' "$q" "$p" "$r" 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review" && printf "\n%s" "$FULOW" && unfile 7 "$STUB/r.review" 100101'
  [ "$(cat "$STUB/r.withdrawn" 2>&1)" = "#100101 $p" ] || fail "unfile of #100101 after followups of card c1-7 (findings '$q', '$p', '$r', issue 7 at depth 1) did not pair it with the P1: $(cat "$STUB/r.withdrawn" 2>&1)"
  [ "$RC" = 0 ] && [ "$(head -n 1 "$T/$CASE/run.out")" = '[100101]' ] \
    && jq -e -s --arg p "$p" 'length == 1 and (.[0].body | contains("Finding: " + $p) and contains("Follow-up depth: 2"))' "$STUB/filed" > /dev/null \
    && jq -e -s --arg q "$q" --arg r "$r" --arg w "$(tail -n 1 "$T/$CASE/run.out")" 'map(.finding) == [$q, $r] and all(.why == $w and .issue == 7 and .area == "area:engine") and $w != ""' "$ST/selfheals.jsonl" > /dev/null \
    || fail "followups of card c1-7 (issue 7 at depth 1) with the findings '$q', '$p' and '$r' did not file one depth-2 follow-up for the P1 and put the P2 and the P3 on the self-heals list with FULOW (exit $RC): $(cat "$T/$CASE/run.out") filed: $(cat "$STUB/filed" 2>&1) list: $(cat "$ST/selfheals.jsonl" 2>&1)"
}

# A P2 of a follow-up that cannot be written to the self-heals list lands nothing: the P1 filed before it is withdrawn.
# Bug it catches: the finding was dropped with no follow-up and no list entry, and the card landed.
t_fulownolist() {
  local p='[P1] a.txt:1 the count is off by one' q='[P2] a.txt:2 the word is wrong'
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "Follow-up depth: 1"')]"; mkdir -p "$ST/selfheals.jsonl.lock" # the list's lock cannot be opened
  printf '%s\n' "$p" "$q" 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" != 0 ] && grep -q 'could not be written' "$T/$CASE/run.out" && [ "$(cat "$STUB/closed" 2>/dev/null)" = 100101 ] \
    || fail "followups of card c1-7 (issue 7 at depth 1) with the findings '$p' and '$q' and a self-heals list it cannot write did not fail and withdraw #100101 (exit $RC): $(cat "$T/$CASE/run.out") closed: $(cat "$STUB/closed" 2>&1)"
}

# A depth that cannot be read counts as the cap: no finding is filed, the P1 too goes on the self-heals list, with
# FUCAP. Bug it catches: an unread depth read as 0 or 1 files the P1 as a follow-up, one level past what can be shown.
t_fulownodepth() {
  local p='[P1] a.txt:1 the count is off by one'
  setup "[$(issue 7 2026-01-01)]"
  printf '%s\n' "$p" 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'fudepth() { return 1; }; followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review" && printf "\n%s" "$FUCAP"'
  [ "$RC" = 0 ] && [ "$(head -n 1 "$T/$CASE/run.out")" = '[]' ] && [ ! -s "$STUB/filed" ] \
    && jq -e -s --arg p "$p" --arg w "$(tail -n 1 "$T/$CASE/run.out")" 'length == 1 and .[0].finding == $p and .[0].why == $w' "$ST/selfheals.jsonl" > /dev/null \
    || fail "followups of card c1-7 (issue 7, fudepth failing) with the finding '$p' did not put it on the self-heals list with FUCAP and file nothing (exit $RC): $(cat "$T/$CASE/run.out") filed: $(cat "$STUB/filed" 2>&1) list: $(cat "$ST/selfheals.jsonl" 2>&1)"
}

# A P2 of a follow-up that names a pipeline file is filed held, not put on the self-heals list. Bug it catches: on the
# list it reached a Self-heals batch card, which is never held, so a change to the pipeline was built with no owner asked.
t_fulowpipe() {
  local q='[P2] a.txt:2 the word is wrong'
  setup "[$(issue 7 2026-01-01 | jq -c '.body = "Follow-up depth: 1"')]"; tune '.pipelineFiles = ["a.txt"]'
  printf '%s\n' "$q" 'VERDICT: NO-GO' > "$STUB/r.review"
  fx_in 'followups c1-7 "$(jq -c ".[0]" "$STUB/issues.json")" "$STUB/r.review"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = '[100101]' ] && [ "$(jq -c .held "$ST/control.json")" = '[100101]' ] && [ ! -s "$ST/selfheals.jsonl" ] \
    || fail "followups of card c1-7 (issue 7 at depth 1, pipelineFiles [a.txt]) with the finding '$q' did not file it held and off the self-heals list (exit $RC): $(cat "$T/$CASE/run.out") held: $(jq -c .held "$ST/control.json" 2>&1) list: $(cat "$ST/selfheals.jsonl" 2>&1)"
}
