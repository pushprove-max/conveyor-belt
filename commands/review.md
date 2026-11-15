---
description: One Codex adversarial pass, then Codex review rounds until one finds no P0 to P2 finding (at most 10), fixing and committing after each round, on committed code against one base, in the plugin's review wording; in the fast lane, each round is the card reviewer's preview. By Max Goldfarb.
argument-hint: "[base commit] [focus text]"
allowed-tools: Bash, Read, Edit, Write
disable-model-invocation: true
---

# review

Run one adversarial pass first, then standard review passes. Fix the findings after every pass.

## Arguments

`$ARGUMENTS`: if its first word resolves as a commit (`git rev-parse --verify --quiet <word>^{commit}`), that is BASE
and the rest is focus text (USER_FOCUS). Otherwise BASE is the project's default branch (the pack's `defaultBranch`,
else `main`) and all of it is focus text.

## The reviewer: the Codex CLI

The reviewer is the Codex CLI, as for the card reviewer seat. If `command -v codex` finds nothing, say that this
command needs the Codex CLI (`npm install -g @openai/codex`, then `codex login`; `conveyor.sh doctor` names it too)
and stop.

## Review focus: the plugin's review wording

    W="${CLAUDE_PLUGIN_ROOT}/shim.sh"
    FOCUS_ADV="$("$W" conveyor/conveyor.sh wording adversarial)"   # the three angles, plus the standing checks
    FOCUS_REV="$("$W" conveyor/conveyor.sh wording review)"        # the closing-pass focus, plus the standing checks

Run them from this checkout. The wording is the plugin's `conveyor/rules/review.md`, or the project's own file when
its pack names one (`review.wording`). Both carry the standing checks ("list every finding you can defend", the test
rules, placeholder UI and the rest), the severity scale and a Class search line per finding. If either command fails,
show its message and stop: never fall back to a hand-written focus.

Severity holds the loop: critical, high and medium (P0 to P2) findings must be fixed; low (P3) findings are fixed if
cheap but never hold convergence. A user-visible change (screen, wording, error, sign-in, billing, API response)
found during fixing needs the owner's explicit yes, with before and after: stop and ask.

## One review sees the whole change

A review sees the commits since one base, never the uncommitted changes as well: a bug in how a fix meets the earlier
code is in neither half of two half reviews. So every review here runs on committed code against one base.

- Before every review, commit all work in scope on the branch (`git status --porcelain` must show nothing in scope).
  Never push.
- One review, in the foreground with a 600000 ms timeout, with FOCUS the round's wording:

      { printf 'Review the commits on this branch since %s (git diff %s...HEAD), read-only.\n\n' "$BASE" "$BASE"
        printf '%s\n\n%s\n' "$FOCUS" "$USER_FOCUS"; } \
        | codex exec -s read-only -o "${TMPDIR:-/tmp}/conveyor-review.md" - > /dev/null 2>&1
      cat "${TMPDIR:-/tmp}/conveyor-review.md"

## Steps

1. **Adversarial pass (once).** Commit first, then run one review with `FOCUS="$FOCUS_ADV"`. Fix every finding (see
   "Fixing").
2. **Review loop (up to 10 rounds).** Commit the last round's fixes, then run one review with `FOCUS="$FOCUS_REV"`.
   In the fast lane (a checkout `conveyor.sh lane fast create` made), each round is instead the card reviewer's
   preview: run `"${CLAUDE_PLUGIN_ROOT}/shim.sh" conveyor/conveyor.sh lane fast review` and show its output as it is.
   A preview never lands anything and never stands in for the card's own review (`conveyor.sh lane fast land` runs
   that). Its exit: 0, its `VERDICT:` line decides convergence, and on a `CLASS REPEAT` line the next fix round has
   the one job that line names (one rule that covers every shape of the class, and one test that lists the shapes);
   3 (`CLASS STOP`), stop the loop and ask the owner, as the class is back after the round that fixed the whole
   class, so the design is wrong, not the patch; 2, it refused (no lane here, a tracked change, no change against
   main, or a change that does not merge): say what it said; 1, the review failed: show why.
   - Every run of this command runs at least round 1 itself, even when an earlier review already passed the same
     commit: the user asked for a fresh review.
   - If a round reports no critical, high or medium finding that survives the proof bar, it has converged. Stop.
   - Otherwise fix every finding, commit, and start the next round. A round with fixes is never the last: the
     converging round reviews the commit that holds every fix.
   - Stop after round 10 even if findings remain, and report them as open.
3. **Report.** Give one table of every finding from every round, then the round that converged (or "did not converge
   in 10"). After it, list anything skipped or unverified.

## Fixing

- Show each round's findings as a `Sev | File | Line | Issue` table before any prose.
- Proof bar, every round: a finding with no exact failing input or command is marked "dropped: no failing input" and
  is not fixed. It does not hold convergence. In a fast-lane round, the reviewer's own verdict still decides.
- Before editing, read the code and check the callers of each function you change. Fix the root cause in the shared
  function, not in one caller.
- Fix siblings: for each finding, search for every other form of the same mistake (its Class search, then your own)
  and fix them all in that round, not only the case named.
- Repeat-class stop: keep a one-line class for each P0 to P2 finding per round. A class an earlier round fixed that
  comes back gets a whole-class round (one rule that covers every shape, plus one test that lists the shapes, and no
  per-case patch); back again after that, stop and ask the owner.
- A case an existing enforcement backstop already stops is not a blocking finding.
- If a finding is wrong, do not change code for it. Mark it "rejected" in the table with a one-line reason. If the
  reviewer raises the same rejected finding again, rejecting it again does not stop convergence.
- After each round's fixes, run only the test files for the touched area, the way the project's test rules require.
  If they fail, fix them before the next review: never hand a red tree to the reviewer. Never run the full suite,
  during or after the loop; report that it was not run.
- If a fix would be a policy, destructive or design reversal, stop and ask the user.
- Commit each round's fixes on the current branch with a message saying why. Do not push, merge or bump versions.

## Output per round

`Round N (adversarial|review): K findings → fixed F, rejected R`, then the table. Keep prose short.
