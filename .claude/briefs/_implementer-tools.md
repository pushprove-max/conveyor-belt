# Implementer token rules

Every Codex implementer and fixer reads this before the first tool call.
Why: one Sol build on 2026-09-09 ran 859 turns at 134K context each, 115M
input tokens for 250K of output. Every tool call is a turn, and every turn
re-sends the whole context. Fewer turns and a smaller context are the only
levers that matter; effort level is not (reasoning was under 1% of tokens).

1. **One look per turn: independent reads share one exec script.** Lookups,
   greps, serena calls, `git` status and a typecheck that do not depend on
   each other go in ONE exec script: several `tools.*` calls awaited together,
   `await Promise.all([tools.exec_command({...}), tools.mcp__serena__find_symbol({...})])`,
   or one shell command separated by `echo ---`. Never one `rg` per turn.
   Never a turn that only narrates what the next turn will do. Keep
   sequential: a step that needs an earlier result, every edit, every wait.
   Measured 2026-09-17: 2,083 turns carried 2,037 tool calls, one per turn.
   Check a session with `.claude/scripts/seat-tokens.sh --rollout <rollout.jsonl>`;
   `toolsPerTurn` above 1 means the looks were batched.
   `bash .claude/scripts/peek.sh a.ts:10-40 'plan.md#Heading' b.md` prints
   several files, line ranges and sections in one call (`--unit <unit>` prints a
   reviewer's inputs). `bash .claude/scripts/bgrun.sh --max 25 -- <command>`
   runs a slow command and returns its exit code and output in one call, or
   prints the `bgrun.sh wait <log>` line to read it later.
2. **Suite output goes to a file; print the decision, not the log.** Run
   `npm run test:changed > /tmp/conveyor/<unit>-<n>.log 2>&1; tail -n 40
   /tmp/conveyor/<unit>-<n>.log` (the runner already writes its own log;
   name it in the evidence); named files the same way with
   `npm run test:files -- <files>`. Same for `typecheck` and `tsc`. Never `cat` a
   log, a lockfile or a whole source file. Read a symbol (serena) or a
   bounded range (`sed -n 'a,bp'`). That is advice; no hook caps a read.
   `.claude/hooks/bash-guardrails.sh` no longer refuses a search:
   a lone `rg` or `grep -r` is rewritten to the checkout root with a 200-line
   cap when it names no path, the checkout root or a parent of it; an absolute
   /tmp path passes, and an unresolved variable passes with a warning. Name a
   bounded path anyway: a directory under the checkout, a file, or a log path.
   A generated file (`linguist-generated` in `.gitattributes`) is queried with
   `jq` or `rg`, never read whole. `.claude/hooks/generated-read-guard.sh`
   blocks a whole read of one every time; its message says how to ask main
   when only a whole read will do.
3. **One suite run per tree state; final checks follow the area the diff
   touches.** While iterating, and for the red-first proof, run only the
   touched test files: `npm run test:files -- <files>` (killed after 120s,
   naming the file still running), and check each changed `.ts` file with
   serena `get_diagnostics_for_file` instead of a whole-project `tsc`. Once
   per part, when the tree is final, run the checks that can see what changed;
   after a fix, re-run only the files that failed with `npm run test:files --`,
   never the whole `test:changed` or typecheck again. Main's local-checks
   chain owns the full suite. Measured: six full `test:changed` runs
   (37.5 min) and six `typecheck:backend` runs (11 min) in one build.
   The heap cap is inside the npm scripts, never a bare `node --test`.
   - `src/`, `shared/`, `lambdas/` changed: `npm run test:post-fix` runs the
     backend typecheck, the test-project typecheck and `test:changed` at once
     and reports each exit code; run it as the turn's last tree change, evidence
     written first, so the Stop hook skips its recompile. Any one red fails the
     round.
   - `scripts/` or `web/` changed: `npm run test:changed`.
   - `web/`: `npm --prefix web run typecheck`. For the touched web tests,
     name them: `npm --prefix web run test:unit:raw -- src/x.test.tsx`. The
     whole web `test:unit` is refused by `.claude/hooks/suite-rerun-guard.sh`,
     even with files named.
   - Backend code (`src/`, `shared/`, `lambdas/`): the two typechecks run in
     `npm run test:post-fix` above; alone, `bash .claude/hooks/typecheck.sh --check tsconfig.backend.json` (and
     `tsconfig.test.json`), the same compile, which also spares the Stop hook's recompile while the tree stays as it is.
   - `infra/`: `npm --prefix infra run typecheck` plus the touched infra jest
     files. Root `npm run typecheck` IS this infra typecheck; it sees no
     backend or web change.
   - `.claude/` only: its own shell self-tests.
   - Any diff: every guard test and hook self-test that names a changed file
     by path, which `test:changed` does not select (a stale value-census
     inventory row reached the push chain this way):
     `git diff --name-only main | while read -r f; do rg -l -F "$f" src/config/__tests__ shared scripts/__tests__ .claude/hooks/__tests__ .claude/scripts/__tests__; done | sort -u`;
     run the `.ts` hits with `npm run test:files --` and the `.sh` hits with
     `bash .claude/scripts/run-shell-tests.sh`.
   `test:guards` and the full web and infra suites are the PROD-candidate chain's job;
   a builder runs only the ratchet guard of rule 6. A brief's Verification
   section may add a check; it need not repeat these. A rerun without a
   changed file is a wasted turn and is what the evidence's "one run per tree
   state" line means.
4. **Do not re-read.** A file you read and did not change is still what you
   read. Re-read only what you edited, and only the range you edited.
5. **Prefer structural editing when the session advertises it for the target
   language**. Use advertised symbol-aware operations
   for function/class bodies, renames, removals and sibling insertion. Do not
   assume an unadvertised operation or unsupported language is available or
   atomic. After a structural lookup reports unsupported coverage, use a
   minimal `apply_patch`; for scripts and `.claude` material, inspect a
   bounded range (rule 2) first. An offset without a limit
   is not bounded, and runtime read hooks may still require their documented
   evidence-and-retry flow. Never print a whole file back. If the pane reports over 70% context
   used, finish the current cut, write the evidence section so far, and
   keep going with only bounded reads. Compaction costs a full re-read.
6. **No new type escapes in test files.** `as any`, `as unknown as`,
   `as never` and `@ts-*` in a test are counted by
   `src/config/__tests__/untyped-test-double-ratchet.guard.test.ts` against
   `src/config/untyped-test-double-baseline.json`; a file that grows its
   count fails the push gate and the ship stops (D0 and G1 both stopped
   there on 2026-09-09). Build fixtures typed: a helper returning the real
   type, `Partial`/`Omit`/`satisfies` for a deliberately absent member.
   Run that guard once before writing the evidence.
7. **Batch verification at the end**, one call: the touched test files, the
   rule 3 checks for each area the diff touches, and `git diff --check`, each
   to its own log, one `tail` each.

8. **No hook can see a tool call you make from the script.** The guardrails
   hook screens shell commands; a `tools.*` call reaches nothing, so these
   two are on you (measured 2026-09-15 across one day of Sol panes).
   - **Never enumerate your own tool inventory.** An `ALL_TOOLS.filter(...)`
     ran 78 times that day and carried 33M input tokens, because every match
     drags its description along. The names are
     `tools.mcp__serena__{get_symbols_overview, find_symbol,
     find_referencing_symbols, get_diagnostics_for_file, replace_content,
     replace_symbol_body, insert_after_symbol, safe_delete_symbol}`. Call one. Do not go looking for it.
   - **Never read an image at `detail:"original"`.** One such call carried
     21M input tokens by itself, 8% of the day. Use the default detail.

9. **A locked test does not need a question** (five of the
   last eighteen worker questions were this). When a test path in
   `.claude/bugfix-lock` blocks a change this brief names, use the Edit tool to take the path out of
   the lock file, change only what this brief or the finding names, Edit the path
   back, and show the before and the after in the evidence file. The lock exists
   to stop a test being quietly reshaped to pass; the diff and the evidence keep
   that visible. Anything WIDER than what the brief names is still a question.

A brief's Verification section names these rules; the evidence file records
the suite runs (count them: more than two `test:changed` runs on one unit is
a finding for the reviewer). In a worktree, a third `test:changed` run with no
file change since the last is refused and names the failing files to rerun.

## Instruction priority and stopping
