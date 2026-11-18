# SPDX-License-Identifier: Apache-2.0
"""testreport.py <format> <worktree> <since> <path>...: the clock seconds of each test file, read from a test runner's
own report (the pack's test.report, conveyor/README.md, Test file times), printed as the runner's log
line `TESTRUN sec<TAB><file><TAB><clock seconds>`, with no CPU seconds: a report gives clock time only.

A path is a report file or a folder of them (every file under it). Only a file written at or after <since> (epoch
seconds: the run's start) is read, so a report an earlier run left is never taken for this one. A file is named by its
path from <worktree>; a name that is no file there is left out. Formats:
  junit             JUnit XML: each testcase's time, by its file attribute or its suite's, else its classname or its
                    suite's name read as a path (pytest's tests.test_x reads as tests/test_x.py).
  jest-json         vitest's or jest's JSON report: each testResults entry, its perfStats or start and end times.
  go-json           go test -json: each top-level test's Elapsed, by the _test.go file of its package's folder (from
                    go.mod's module) that declares its function.
  go-text           go test -v's output: each top-level test's `--- PASS` (FAIL, SKIP) line, by its file as go-json's.
  cargo             cargo test's output: each test target's `test result` line (or, with libtest's JSON format, its
                    suite's exec_time), named by the source its `Running <source> (<binary>)` line gives.
  rspec-json        rspec's JSON formatter: each example's run_time.
  pytest-durations  pytest --durations=0 output: the setup, call and teardown seconds of each case.
  mocha-times       the lines tools/mochatimes.cjs writes in a mocha run: {"file": <path>, "sec": <seconds>}, a test a line.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET


def files(paths, since):
    for p in paths:
        if os.path.isdir(p):
            for d, _, ns in os.walk(p):
                for n in sorted(ns):
                    yield from files([os.path.join(d, n)], since)
        elif os.path.isfile(p) and os.path.getmtime(p) >= since:
            yield p


def text(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def num(x):
    try:
        v = float(x)
    except (TypeError, ValueError):
        return 0.0
    return v if v >= 0 and v == v and v != float("inf") else 0.0


class Names:
    """A runner's name of a test file, as its path from the worktree; None when it names no file there."""

    def __init__(self, root):
        self.root = os.path.realpath(root)

    def file(self, name):
        if not isinstance(name, str) or not name.strip():
            return None
        p = name.strip()
        if p.startswith("file://"):
            p = p[7:]
        p = os.path.realpath(p if os.path.isabs(p) else os.path.join(self.root, p))
        if not p.startswith(self.root + os.sep) or not os.path.isfile(p):
            return None
        return os.path.relpath(p, self.root)

    def dotted(self, name):
        """pytest's classname: tests.test_x.TestY reads as tests/test_x.py."""
        if not isinstance(name, str) or "/" in name:
            return None
        parts = name.split(".")
        for i in range(len(parts), 0, -1):
            f = self.file("/".join(parts[:i]) + ".py")
            if f:
                return f
        return None


def junit(paths, n):
    out = {}
    for p in paths:
        try:
            root = ET.fromstring(text(p))
        except ET.ParseError:
            continue

        def walk(el, suites):
            if el.tag == "testcase":
                a = el.attrib
                f = n.file(a.get("file"))
                for s in reversed(suites):
                    f = f or n.file(s.get("file"))
                f = f or n.file(a.get("classname")) or n.dotted(a.get("classname"))
                for s in reversed(suites):
                    f = f or n.file(s.get("name"))
                if f:
                    out[f] = out.get(f, 0.0) + num(a.get("time"))
                return
            inner = suites + [el.attrib] if el.tag == "testsuite" else suites
            for c in el:
                walk(c, inner)

        walk(root, [])
    return out


def jest(paths, n):
    out = {}
    for p in paths:
        try:
            d = json.loads(text(p))
        except ValueError:
            continue
        for r in (d.get("testResults") or []) if isinstance(d, dict) else []:
            if not isinstance(r, dict):
                continue
            f = n.file(r.get("name") or r.get("testFilePath"))
            if not f:
                continue
            ps = r.get("perfStats") if isinstance(r.get("perfStats"), dict) else {}
            if num(ps.get("runtime")):
                ms = num(ps.get("runtime"))
            elif num(ps.get("end")) and num(ps.get("start")):
                ms = num(ps["end"]) - num(ps["start"])
            elif num(r.get("endTime")) and num(r.get("startTime")):
                ms = num(r["endTime"]) - num(r["startTime"])
            else:
                ms = sum(num(a.get("duration")) for a in r.get("assertionResults") or [] if isinstance(a, dict))
            out[f] = out.get(f, 0.0) + max(ms, 0.0) / 1000
    return out


def jsonlines(p):
    for line in text(p).splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if isinstance(d, dict):
                yield d


def gotests(tests, n):
    """The seconds of each top-level test, (package, test, seconds), by the _test.go file of its package's folder (from
    go.mod's module) that declares its function."""
    out, mod = {}, None
    try:
        mod = re.search(r"^module\s+(\S+)", text(os.path.join(n.root, "go.mod")), re.M).group(1)
    except (OSError, AttributeError):
        pass
    decl = re.compile(r"^func\s+((?:Test|Benchmark|Fuzz|Example)\w*)\s*\(", re.M)
    found = {}

    def where(folder):
        """Each test function of the package's folder: the _test.go file that declares it."""
        if folder not in found:
            found[folder] = {}
            d = os.path.join(n.root, folder)
            for b in sorted(os.listdir(d)) if os.path.isdir(d) else []:
                f = n.file(os.path.join(folder, b))
                if b.endswith("_test.go") and f:
                    for m in decl.finditer(text(os.path.join(n.root, f))):
                        found[folder].setdefault(m.group(1), f)
        return found[folder]

    for pkg, t, sec in tests:
        # A package is its folder from the module's root; one outside the module is left out.
        if mod and pkg == mod:
            folder = ""
        elif mod and pkg.startswith(mod + "/"):
            folder = pkg[len(mod) + 1:]
        else:
            continue
        f = where(folder).get(t)
        if f:
            out[f] = out.get(f, 0.0) + num(sec)
    return out


def gojson(paths, n):
    def tests():
        for p in paths:
            for d in jsonlines(p):
                pkg, t = d.get("Package"), d.get("Test")
                # A top-level test's own end: a subtest's (a/b) is in its parent's seconds.
                if d.get("Action") in ("pass", "fail", "skip") and isinstance(pkg, str) \
                        and isinstance(t, str) and "/" not in t:
                    yield pkg, t, d.get("Elapsed")
    return gotests(tests(), n)


def gotext(paths, n):
    """go test -v: each top-level test's `--- PASS|FAIL|SKIP: <test> (<seconds>s)` line, at the line's start (a
    subtest's is indented), of the package the next `ok|FAIL <package> ...` line names."""
    end = re.compile(r"^--- (?:PASS|FAIL|SKIP): (\S+) \(([0-9.]+)s\)")
    pkg = re.compile(r"^(?:ok|FAIL|\?)\s+(\S+)\s")

    def tests():
        for p in paths:
            seen = []
            for line in text(p).splitlines():
                m = end.match(line)
                if m:
                    seen.append((m.group(1), m.group(2)))
                    continue
                m = pkg.match(line)
                if m:
                    for t, sec in seen:
                        yield m.group(1), t, sec
                    seen = []
    return gotests(tests(), n)


def cargo(paths, n):
    """Each test target's seconds, named by the source its `Running <source> (<binary>)` line gives: libtest's
    `test result: ... finished in <seconds>s` line, or with its JSON format, its suite's exec_time. A doctest run is
    of no one file: its seconds are left out."""
    out = {}
    run = re.compile(r"^\s*Running\s+(?:unittests\s+)?(\S+)\s+\(")
    done = re.compile(r"^test result: .*; finished in ([0-9.]+)s")
    for p in paths:
        cur = None
        for line in text(p).splitlines():
            m = run.match(line)
            if m:
                cur = n.file(m.group(1))
                continue
            line = line.strip()
            if line.startswith("Doc-tests "):
                cur = None
            m = done.match(line)
            if cur and m:
                out[cur] = out.get(cur, 0.0) + num(m.group(1))
            elif cur and line.startswith("{"):
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if isinstance(d, dict) and d.get("type") == "suite" and d.get("event") in ("ok", "failed"):
                    out[cur] = out.get(cur, 0.0) + num(d.get("exec_time"))
    return out


def mochatimes(paths, n):
    """tools/mochatimes.cjs's lines: each mocha test's file and seconds."""
    out = {}
    for p in paths:
        for d in jsonlines(p):
            f = n.file(d.get("file"))
            if f:
                out[f] = out.get(f, 0.0) + num(d.get("sec"))
    return out


def rspec(paths, n):
    out = {}
    for p in paths:
        try:
            d = json.loads(text(p))
        except ValueError:
            continue
        for e in (d.get("examples") or []) if isinstance(d, dict) else []:
            f = n.file(e.get("file_path")) if isinstance(e, dict) else None
            if f:
                out[f] = out.get(f, 0.0) + num(e.get("run_time"))
    return out


def durations(paths, n):
    out = {}
    line = re.compile(r"^\s*([0-9]+(?:\.[0-9]+)?)s\s+(?:setup|call|teardown)\s+([^\s:]+)::")
    for p in paths:
        for t in text(p).splitlines():
            m = line.match(t)
            f = m and n.file(m.group(2))
            if f:
                out[f] = out.get(f, 0.0) + num(m.group(1))
    return out


FORMATS = {"junit": junit, "jest-json": jest, "go-json": gojson, "go-text": gotext, "cargo": cargo,
           "rspec-json": rspec, "pytest-durations": durations, "mocha-times": mochatimes}


def main(argv):
    if len(argv) < 4 or argv[0] not in FORMATS:
        sys.stderr.write("usage: testreport.py <%s> <worktree> <since> <path>...\n" % "|".join(FORMATS))
        return 2
    n = Names(argv[1])
    got = FORMATS[argv[0]](list(files(argv[3:], num(argv[2]))), n)
    for f in sorted(got):
        if "\t" not in f and "\n" not in f:
            sys.stdout.write("TESTRUN sec\t%s\t%.3f\n" % (f, got[f]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
