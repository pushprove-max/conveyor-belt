#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""The snapshot's per-card figures, made again only for the issues whose cards changed (lib/snapshot.sh snapshot).

Usage: cardruns.py <cards> <kept> <out> <program> <samples> <now> <every> <yes>
  <cards>    the priced cards, one a line, in the snapshot's order
  <kept>     the summary of the last call, kept beside the card records
  <out>      the cards as <program> gave them, one array, then a line with the waits of every card, one array
  <program>  the jq program: given an array of cards (every card of each issue it holds), it prints three lines a
             card, in their order: the card, then its waits of each of the two kinds (arrays)
  <samples>  the loop's samples ($smp), <now> health's time in epoch seconds, <every> the sample period, <yes> YES

What <program> makes of a card reads only the cards of its issue, and of the rest only: the samples (each card's count
of samples, and of full samples, from its issue's creation to its pick-up), now (only when a card of the issue is open
or blocked and not retried), <every> and <yes>. So the cards of an issue are run through <program> only when their lines,
or one of those, changed since the last call; the rest are taken from <kept>. <kept> is a line `<key> <sha256 of the
rest>`, then `<the issue's key>\t<card>\t<waits>\t<waits>` a card; any other summary is not used. When two issues
share a card name, every card is one issue (the program reads the cards by name across issues then).
"""
import bisect
import calendar
import hashlib
import json
import os
import re
import subprocess
import sys
import time

ISO = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\Z")


def epoch(s):
    """s as jq's fromdate reads it, or None when it may read otherwise."""
    if isinstance(s, str) and ISO.match(s):
        try:
            return calendar.timegm(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ"))
        except ValueError:
            return None
    return None


def isnum(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def issuekey(v):
    """The issue as jq compares it: 1 and 1.0 are one issue."""
    return ("n", float(v)) if isnum(v) else ("v", json.dumps(v, sort_keys=True))


def main(cards, kept, out, program, samples, now, every, yes):
    with open(program, "rb") as f:
        prog = f.read()
    with open(samples, "rb") as f:
        sraw = f.read()
    ver = subprocess.run(["jq", "--version"], capture_output=True, check=True).stdout.decode()
    with open(__file__, "rb") as f:
        me = f.read()
    key = hashlib.sha256(json.dumps([hashlib.sha256(prog).hexdigest(), hashlib.sha256(me).hexdigest(), ver, every, yes]).encode()).hexdigest()
    # The sample times, and those of the full samples, when each reads as the program reads it and they are in
    # order: then a card's counts are found here. Else every card's figures read the samples whole (sdig).
    st, sf, sdig = [], [], None
    try:
        for ln in sraw.split(b"\n"):
            if not ln.strip():
                continue
            s = json.loads(ln)
            t = epoch(s.get("time"))
            if t is None:
                raise ValueError
            st.append(t)
            if isnum(s.get("cap")):
                if not isnum(s.get("slots")):
                    raise ValueError
                if s["slots"] >= s["cap"]:
                    sf.append(t)
        if st != sorted(st):
            raise ValueError
    except (ValueError, AttributeError):
        sdig = hashlib.sha256(sraw).hexdigest()

    def pos(a, x):
        return bisect.bisect_left(a, x)

    rows, groups, names = [], {}, {}
    with open(cards, "rb") as f:
        for ln in f:
            ln = ln.rstrip(b"\n")
            if not ln:
                continue
            c = json.loads(ln)
            g = issuekey(c.get("issue"))
            x = c.get("x") if isinstance(c.get("x"), dict) else {}
            log = x.get("log") if isinstance(x.get("log"), list) else []
            p = log[0] if log and isinstance(log[0], dict) else {}
            cr, pk = (epoch(p.get("created")) if "created" in p and p.get("created") is not None else "none"), epoch(c.get("startedAt"))
            # What the program reads of the samples for this card: nothing when slotSec is null whatever they hold.
            if cr == "none":
                slot = None
            elif sdig is not None or cr is None or pk is None:
                slot = sdig or hashlib.sha256(sraw).hexdigest()
            elif cr > pk:
                slot = None
            else:
                slot = [pos(st, pk + 0.5) - pos(st, cr - 0.5), pos(sf, pk + 0.5) - pos(sf, cr - 0.5)]
            opened = not isinstance(c.get("x"), dict) or x.get("endAt") is None or (c.get("step") == "blocked" and x.get("retried") in (None, False))
            rows.append((g, ln, slot, opened))
            groups.setdefault(g, []).append(len(rows) - 1)
            names.setdefault(c.get("card") if isinstance(c.get("card"), str) else json.dumps(c.get("card")), set()).add(g)
    if any(len(v) > 1 for v in names.values()):
        rows = [(("all",), ln, slot, opened) for _, ln, slot, opened in rows]
        groups = {("all",): list(range(len(rows)))}
    gkey = {}
    for g, ix in groups.items():
        h = hashlib.sha256(key.encode())
        if any(rows[i][3] for i in ix):
            h.update(b"now " + now.encode())
        for i in ix:
            h.update(b"\n" + rows[i][1] + b"\n" + json.dumps(rows[i][2]).encode())
        gkey[g] = h.hexdigest()

    was = {}
    try:
        with open(kept, "rb") as f:
            head, body = f.readline().split(), f.read()
        if head == [key.encode(), hashlib.sha256(body).hexdigest().encode()]:
            for ln in body.decode("utf-8").split("\n")[:-1]:
                k, c, w1, w2 = ln.split("\t")
                was.setdefault(k, []).append((c, w1, w2))
    except (OSError, ValueError):
        was = {}
    todo = [i for g, ix in groups.items() if gkey[g] not in was or len(was[gkey[g]]) != len(ix) for i in ix]
    todo.sort()
    made = {}
    if todo:
        r = subprocess.run(["jq", "-cs", "--argjson", "now", now, "--argjson", "every", every, "--arg", "yes", yes,
                            "--slurpfile", "smp", samples, "-f", program],
                           input=b"".join(rows[i][1] + b"\n" for i in todo), capture_output=True, check=True)
        lines = r.stdout.decode("utf-8").split("\n")[:-1]
        if len(lines) != 3 * len(todo):
            raise SystemExit(f"cardruns: the program printed {len(lines)} lines for {len(todo)} cards")
        for n, i in enumerate(todo):
            made.setdefault(gkey[rows[i][0]], []).append(tuple(lines[3 * n:3 * n + 3]))
    now_ = {gkey[g]: made.get(gkey[g]) or was[gkey[g]] for g in groups}
    left = {k: iter(v) for k, v in now_.items()}
    got = [next(left[gkey[g]]) for g, _, _, _ in rows]
    with open(out, "w", encoding="utf-8") as f:
        f.write("[" + ",".join(c for c, _, _ in got) + "]\n")
        # The waits in the order the program's caller made them: every card's first kind, then every card's second.
        f.write("[" + ",".join(w[1:-1] for w in [w1 for _, w1, _ in got] + [w2 for _, _, w2 in got] if w != "[]") + "]\n")
    # The summary is written again only when an issue's cards changed, through a file of its own and one rename: a
    # call beside this one never reads half of it.
    if made or set(was) != set(now_):
        body = "".join(f"{k}\t{c}\t{w1}\t{w2}\n" for k, v in now_.items() for c, w1, w2 in v).encode()
        tmp = f"{kept}.{os.getpid()}"
        try:
            with open(tmp, "wb") as f:
                f.write(f"{key} {hashlib.sha256(body).hexdigest()}\n".encode() + body)
            os.replace(tmp, kept)
        except OSError:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 9:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
