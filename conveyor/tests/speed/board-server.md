# The Board server, stream and decision tests

Measured 2026-11-14 as `README.md` says, on the loop's machine (16 cores), main first (172d067, from a Git checkout of
main) and then this card's change. Each file ran alone, by its own interpreter (`bash`, `node --max-old-space-size=4096
--test`, `python3`), one file after another. The load average was far from usual: 8 to 33 during the runs. Every run
passed. The three files nearest the 50% line (`dashboard-server`, `dashboard-stream`, `dashboard`) ran three times
each, main and the change one after the other, and their time is the middle of the three; the others ran once each.

These shell files have no cases by name: their checks run in one script, so their slowest case is the file. A node
file's slowest case is its slowest `test()`, from node's own report.

| File | Before: file (slowest case) | After: file (slowest case) | Faster by | How |
| --- | --- | --- | --- | --- |
| `approval.test.sh` | 18.83 s | 4.04 s | 78% | Its checks are in six parts (`read`, `dep`, `gitnode`, `gitpy`, `wrap`, `req`) that run side by side, each with a decision log of its own (its own host file's state folder), so no part sees another's approvals; a part that relied on an approval an earlier one wrote writes it itself first (`lodash`, the `requests` row before the include-line check). Output is printed and counted in the parts' order; a part that ends early fails. |
| `dashboard-collector-incremental.test.mjs` | 15.77 s (`claude: corrupt_state_is_cold_start` 2.12 s) | 1.16 s (`cycle_snapshot_misses_unless_whole` 0.91 s) | 92% | The 16 cases run side by side (one `describe`, concurrency on), each on folders of its own; each Python run is awaited (`execFile`) instead of blocking (`spawnSync`), and runs with `-S` (the reader needs only the standard library). |
| `dashboard-collector-incremental.test.sh` | 4.98 s | removed | - | A wrapper that ran `dashboard-collector-incremental.test.mjs` again through npm; that file runs directly in this project's test run (`.conveyor/test-changed.sh` runs every `.test.mjs`), so the wrapper proved nothing the `.mjs` does not. |
| `dashboard-limit-cost.refute.test.mjs` | 4.37 s (`a folder listed again by a narrower refresh stays unknown until its older files are read` 1.55 s) | 0.50 s (the same case, 0.34 s) | 88% | Its cases run side by side (one `describe`, concurrency on), each on folders of its own; each Python run is awaited and runs with `-S`; a case's two independent runs (the advisor price with and without, the two readers' folders) run together. |
| `dashboard-limit.test.sh` | 20.19 s | 4.33 s | 78% | Its checks are in eight parts (`prices`, `transcripts`, `codex`, `fetch`, `limit`, `account`, `accounts` and the no-Orca part) that run side by side, each on files of its own; the two that collect have their own last-collect second (`RUN_END`). It also holds the check of `dashboard-missing-prompt.refute.test.py`, below. |
| `dashboard-missing-prompt.refute.test.py` | 0.07 s | removed | - | Its one check (a Haiku request whose prompt size is missing, null or a string is unpriced) is now a line of `dashboard-limit.test.sh`'s `prices` part, beside the other price checks of the same function, with the same three values. |
| `dashboard-server-local.test.sh` | 1.22 s (three runs: 1.24, 1.22, 1.21) | 0.25 s (0.25, 0.23, 0.27) | 79% | The users' passwords are hashed at the cheapest scrypt the server takes (how passwords are hashed is `dashboard-server.test.sh`'s), and the in-process server polls every 0.02 s, so `shutdown()` at the end no longer waits out the default 0.5 s poll. |
| `dashboard-server.test.sh` | 37.03 s (three runs: 30.96, 59.09, 37.03) | 10.44 s (6.88, 22.59, 10.44) | 71% | Its checks are in eleven parts (`basics`, `answers`, `sessions`, `lockout`, `restart`, `actions`, `control`, `users`, `admins`, `mfa`, `standalone`) that run side by side, each with a server, port and folder of its own (`fresh`); the control route's actions are split over two of them (`actions`, `control`), each logged in on its own control host (`control_part`), with main's two OpenCode actions in `actions`. |
| `dashboard-stream.test.sh` | 12.82 s (12.76, 12.92, 12.82) | 6.24 s (6.20, 6.30, 6.24) | 51% | Its three feeds (`lost`, `down`, `hostchange`) run side by side, each in a folder of its own with its own host file, ssh stub and held connections. The `down` part waits out the feed's retry back-off (from `CONVEYOR_STREAM_BACKOFF=0.25`, doubling), which is what it checks. |
| `dashboard-view.test.sh` | 26.38 s | removed | - | A wrapper that ran every `dashboard-view.*.test.mjs` again through npm; each of those runs directly in this project's test run (`.conveyor/test-changed.sh`), so the wrapper proved nothing they do not. |
| `dashboard.test.sh` | 46.05 s (46.05, 49.07, 44.46) | 14.96 s (21.71, 14.96, 14.08) | 67% | Its checks are in parts (`contract`, `cards`, `machine`, `figures`, `decisions`, `lanes`, `update`, `install` and more) that run side by side, each with a folder, checkout, host file, stubs and dashboard folder of its own (`fresh`); a part that reads the cards' snapshots makes them itself (`cards_fixture`). |
| `decision-answer-correct.test.sh` | 7.52 s | 0.77 s (three runs: 0.78, 0.77, 0.77) | 89% | The real-sized digest case keeps its 1.8 MB ledger and log (past the Mac's 1 MiB and Linux's 128 KiB argument) in 300 long rows, not 3000 short ones, and the bytes are in each row's default and answer, not its question: the digest matches every question word by word, which cost about 2 s at that size and is not what the case checks. Its check also asserts both files are over 1.8 MB. |
| `decision-ledger.test.sh` | 3.95 s | 0.64 s | 83% | Its checks run in parts side by side (`fold`, `repeat` and more), each with a folder and main checkout of its own, so its own ledger. It also holds the checks of `decision-number-spelling.refute.test.sh`, below. |
| `decision-number-spelling.refute.test.sh` | 0.05 s | removed | - | Its two checks ("thirteenth", "13th" and "13" are one number, so the same round asked twice is a repeat) are now in `decision-ledger.test.sh` with the same question pairs, beside that file's other same-question checks. |
| `decision-unit.test.sh` | 1.29 s | 0.35 s | 72% | Its checks are in six parts (`read`, `writer`, `badunit`, `order`, `records`, `live`) that run side by side, each with a main checkout and ledger of its own; the six asks of `live`, each read from its own id, are added side by side. |

No case was skipped and no limit or timeout raised. `.conveyor/engine-areas.json` names no Board test file, so the four
removed files leave it unchanged, and no engine case was renamed, so `conveyor/conveyor.slowest` and
`conveyor/tools/closure.slowest` are as they were.

## Shared helper ideas

- `conveyor/tests/lib.sh` and `.claude/scripts/__tests__/dashboard-view.helpers.mjs`: none from this group.
