# Session context: big tool results

Every turn of a card session reads again all that the session holds, so a big tool result is paid for on every later
turn. Issue #540 runs test commands through a short-summary wrapper (`conveyor/tools/testbrief.sh`, which the command
guard `.claude/hooks/bash-guardrails.sh` adds to a test command run without it), and tells sessions in the core card
rules (`conveyor/rules/card-core.md`) to search before they read and to read a file of over 400 lines by line range.

## How it is measured

From the session transcripts Claude Code keeps for each card worktree (`~/.claude/projects/<the worktree path, with
/ as ->/<session>.jsonl`), for the cards of this repository started in the dates given. A build session is one whose
first prompt holds "Make the change this issue asks for". Subagent turns (`isSidechain`) are left out.

- Turns: the assistant messages with a `usage` record. Cached tokens: the sum of their `cache_read_input_tokens`.
- Tool result size: the characters of each `tool_result` (its text parts joined). Big: over 8,000 characters. Share:
  the characters of big results over the characters of all results.
- Kind of a big result: the tool call it answers. A Bash call is a test call when its command holds `.test.sh`,
  `--test`, `pytest`, `vitest`, `jest` or `test-changed`. A Read is ranged when it has an `offset` or a `limit`.

The script (Python 3, standard library; its two arguments are the first card stamp in and the first one out):

```python
import json, os, sys, glob, statistics
root = os.path.expanduser('~/.claude/projects')
rows = []
for d in glob.glob(root + '/*-conveyor-cards-c2026*-conveyor-belt-*'):
    stamp = d.split('conveyor-cards-')[1][:9]
    if not (sys.argv[1] <= stamp < sys.argv[2]): continue
    for f in glob.glob(d + '/*.jsonl'):
        first = None; turns = 0; cached = 0; sizes = []
        for line in open(f, errors='replace'):
            try: e = json.loads(line)
            except Exception: continue
            if e.get('isSidechain'): continue
            m = e.get('message') or {}
            if e.get('type') == 'user':
                c = m.get('content')
                if first is None and isinstance(c, str): first = c
                for b in c if isinstance(c, list) else []:
                    if isinstance(b, dict) and b.get('type') == 'tool_result':
                        x = b.get('content')
                        if isinstance(x, list): x = ''.join(i.get('text', '') for i in x if isinstance(i, dict))
                        sizes.append(len(x or ''))
            elif e.get('type') == 'assistant' and m.get('usage'):
                turns += 1; cached += m['usage'].get('cache_read_input_tokens', 0)
        if first and turns and 'Make the change this issue asks for' in first[:400]:
            rows.append((turns, cached, sizes))
allsz = [s for r in rows for s in r[2]]; big = [s for s in allsz if s > 8000]
print(f"sessions={len(rows)} turns={statistics.mean(r[0] for r in rows):.0f} "
      f"cached={statistics.mean(r[1] for r in rows) / 1e6:.2f}M results={len(allsz)} big={len(big)} "
      f"share={100 * sum(big) / sum(allsz):.0f}% largest={max(allsz)}")
```

## Before (main at 0215a22, cards started 2026-11-13 and 2026-11-14)

Measured 2026-11-14, `c20261113` to `c20261115`.

| Build sessions | Turns a session | Cached tokens a session | Tool results | Over 8,000 characters | Their share | Largest |
| --- | --- | --- | --- | --- | --- | --- |
| 626 | 61 | 6.47 M | 21,380 | 2,070 | 57% | 63,317 |

The big results (over 8,000 characters) of all sessions of those cards, by the call they answer:

| Call | Big results | Share of the big results' characters |
| --- | --- | --- |
| Bash, not a test | 1,307 | 51% |
| Bash, a test | 809 | 31% |
| Read, whole file | 102 | 10% |
| Read, by range | 129 | 7% |

## After

Not measured yet: it needs card sessions that ran with this change. Measure with the same script over the cards
started after the change landed, and add the row here.
