# SPDX-License-Identifier: Apache-2.0
"""uncovered.py <format> <worktree> <since> <path>...: the lines a card's tested patch adds that no test reached, read
from the coverage report its test run wrote (the pack's test.coverage, conveyor/README.md, Changed lines no test
reached). The patch is `git diff -U0` on standard input; one JSON line is printed:
  {"uncovered": [{"file", "lines": "<n>-<m>, <k>"}], "count": <lines>, "checked": <lines>}: checked is how many added
      lines the report counts (a line it names, hit or not), count how many of them no report hit;
  {"unknown": "<why>"}: no report was written during the run, or the report does not match the tested patch.
A path is a report file or a folder of them (every file under it); every path given is read (a run's report and its
first run's, kept when it ran again). Only a file written at or after <since> (epoch
seconds: the run's start) is read, so a report an earlier run left is never taken for this one. Reports that overlap
count a line once: it is reached when any report hit it. A report matches the tested patch when it names a file of
<worktree> and each line it names of a changed file is within that file as the patch left it. A file the report does
not name (a test, a document) is not counted. Formats:
  lcov  LCOV tracefiles: SF (the source, absolute or from <worktree>) and DA (<line>,<hits>) records.
"""
import json
import os
import re
import sys


def files(p, since):
    if os.path.isdir(p):
        for d, _, ns in os.walk(p):
            for n in sorted(ns):
                yield from files(os.path.join(d, n), since)
    elif os.path.isfile(p) and os.path.getmtime(p) >= since:
        yield p


def added(diff):
    """{file: set of the line numbers the patch adds}, from `git diff -U0` output."""
    out, f = {}, None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            n = line[4:]
            f = n[2:] if n.startswith("b/") else None
        elif f and line.startswith("@@ "):
            m = re.match(r"@@ -\S+ \+(\d+)(?:,(\d+))? @@", line)
            if m:
                start, n = int(m.group(1)), int(m.group(2) or 1)
                out.setdefault(f, set()).update(range(start, start + n))
    return out


def lcov(p, root):
    """[(file from root, {line: hits})] of one LCOV tracefile; a source outside root is None."""
    out, f, da = [], None, {}
    with open(p, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("SF:"):
                s = line[3:]
                a = os.path.realpath(s if os.path.isabs(s) else os.path.join(root, s))
                f = os.path.relpath(a, root) if a.startswith(root + os.sep) else None
                da = {}
            elif line.startswith("DA:"):
                parts = line[3:].split(",")
                try:
                    n, h = int(parts[0]), int(float(parts[1]))
                except (ValueError, IndexError):
                    continue
                da[n] = max(da.get(n, 0), h)
            elif line == "end_of_record":
                out.append((f, da))
                f, da = None, {}
    return out


def ranges(ns):
    out, ns = [], sorted(ns)
    i = 0
    while i < len(ns):
        j = i
        while j + 1 < len(ns) and ns[j + 1] == ns[j] + 1:
            j += 1
        out.append(str(ns[i]) if i == j else f"{ns[i]}-{ns[j]}")
        i = j + 1
    return ", ".join(out)


def main():
    fmt, root, since, paths = sys.argv[1], os.path.realpath(sys.argv[2]), float(sys.argv[3]), sys.argv[4:]
    if fmt != "lcov":
        return {"unknown": f"the coverage format {fmt} is not one Conveyor reads (lcov)"}
    reports = [r for p in paths for r in files(p, since)]
    if not reports:
        return {"unknown": "the test run wrote no coverage report"}
    named, hits, seen = False, {}, {}
    for r in reports:
        for f, da in lcov(r, root):
            if f is None:
                continue
            named = True
            for n, h in da.items():
                seen.setdefault(f, set()).add(n)
                if h > 0:
                    hits.setdefault(f, set()).add(n)
    if not named:
        return {"unknown": "the coverage report names no file of the tested tree"}
    patch = added(sys.stdin.read())
    out, count, checked = [], 0, 0
    for f in sorted(patch):
        if f not in seen:
            continue
        try:
            with open(os.path.join(root, f), "rb") as fh:
                size = sum(1 for _ in fh)
        except OSError:
            return {"unknown": f"the coverage report names {f}, which the tested patch does not have"}
        if max(seen[f]) > size:
            return {"unknown": f"the coverage report names line {max(seen[f])} of {f}, which has {size} lines in the tested patch"}
        mine = patch[f] & seen[f]
        miss = mine - hits.get(f, set())
        checked += len(mine)
        count += len(miss)
        if miss:
            out.append({"file": f, "lines": ranges(miss)})
    return {"uncovered": out, "count": count, "checked": checked}


if __name__ == "__main__":
    print(json.dumps(main(), separators=(",", ":")))
