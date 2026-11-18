#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""The engine's state database: the only reader and writer of <state folder>/state.db.

The history files of the state folder (cards.jsonl, retried.jsonl, declined.jsonl, samples.jsonl, limit.jsonl) are
tables of one SQLite database there: one row per line, in the file's order, with the fields the engine asks by as
columns (card, issue, step, time; indexed) and the whole line kept as it is in the file.

For the transition (a later card ends it, once no reader reads the files): every append goes to the file too, and the
files stay the truth. Each call first brings the tables it touches up to date with their files: the lines past what
the table holds are added (a first run imports every file whole), and a file shorter than that part, or whose first
or last bytes of that part changed (sync), was rewritten by hand and is imported anew, whole; the engine's own rewrites
(`retry`, the declined list, the samples' and readings' trims) go through `rewrite` and `keep`. So an edit by hand,
and a database lost or broken (it is made anew from the files), lose nothing. Only whole lines are read: a line
being written is read once it ends.

Usage: state.py <state folder> <command> ...
  append <table>            the lines on stdin, appended to the file and the table. The caller holds the file's lock,
                            as before. Exit 1 only when the file could not be written; a database that could not
                            take them takes them from the file at its next call.
  rewrite <table>           the file holds the lines on stdin alone, rewritten in place (a lock held on the file
                            itself finds the same file), and the table is made from it anew. The caller holds the
                            file's lock. Exit 1 when the file could not be written whole.
  keep <table> <over> <n>   when the table holds more than <over> lines, the file and the table keep the last <n>
  ask [-o <file>] <question> [<arg>...] [-- [-o <file>] <question> ...]
                            several questions in one call, answered from one reading of the database: each answer's
                            lines go to its -o file, else to stdout, in order.
Questions (cards is the card records, retried the lines `retry` took out of them):
  lines <table>             every whole line of the table, as in its file
  issue <table> <issue>     the table's lines of that issue
  tail <table> <n>          the table's last n lines
  card <card>               the card's lines in the card records
  last <card>               the card's last line in the card records
  lastreview <card>         the card's last review line in the card records
  ended <card>              true when the card records hold a landed, closed or blocked line of the card, else false
  tested <card>             true when the card records hold a test line of the card, else false; a line of a Test
                            step that the project's checks ended before any test ran ("checks":true) does not count
  pushes                    {step, time, sec[, head]} of each push and pushed line, of the card records then retried
  yes <reason start> <st>   card<TAB><st>/<kept> of each blocked line of the card records whose reason starts so and
                            that names a kept folder
  samples                   the samples of the last 20160 lines that have a time and a slots count
  limit <account>           the readings of the last 4000 lines with a percent and a time, of that account ("" the
                            default login's)
"""
import hashlib
import json
import os
import sqlite3
import sys
from datetime import datetime

TABLES = {"cards": "cards.jsonl", "retried": "retried.jsonl", "declined": "declined.jsonl",
          "samples": "samples.jsonl", "limit": "limit.jsonl"}
QUESTIONS = {"lines": 1, "issue": 2, "tail": 2, "card": 1, "last": 1, "lastreview": 1, "ended": 1, "tested": 1, "pushes": 0, "yes": 2,
             "samples": 0, "limit": 1}


def fail(msg):
    print("state.py: " + msg, file=sys.stderr)
    sys.exit(2)


def connect(folder):
    db = sqlite3.connect(os.path.join(folder, "state.db"), timeout=60, isolation_level=None)
    # No wait for the disk on each commit: a commit lost to a crash is taken from the files again at the next call.
    db.execute("PRAGMA synchronous=NORMAL")
    if db.execute("PRAGMA user_version").fetchone()[0] == 0:
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("BEGIN IMMEDIATE")
        db.execute("CREATE TABLE IF NOT EXISTS files (name TEXT PRIMARY KEY, size INTEGER NOT NULL, sum TEXT NOT NULL)")
        for t in TABLES:
            db.execute(f'CREATE TABLE IF NOT EXISTS "{t}" (n INTEGER PRIMARY KEY, card TEXT, issue INTEGER, step TEXT, '
                       'time TEXT, line TEXT NOT NULL)')
            for c in ("card", "issue", "step", "time"):
                db.execute(f'CREATE INDEX IF NOT EXISTS "{t}_{c}" ON "{t}" ({c})')
        db.execute("PRAGMA user_version=1")
        db.commit()
    return db


def row(line):
    """The columns of one line: each null when the line is not an object or the field is not of its type."""
    try:
        o = json.loads(line)
    except ValueError:
        o = None
    if not isinstance(o, dict):
        return (None, None, None, None, line)
    def s(k):
        v = o.get(k)
        return v if isinstance(v, str) else None
    i = o.get("issue")
    return (s("card"), i if isinstance(i, int) and not isinstance(i, bool) else None, s("step"), s("time"), line)


def insert(db, t, data):
    """The whole lines of data (bytes ending at a newline) as rows of t."""
    if data:
        db.executemany(f'INSERT INTO "{t}" (card, issue, step, time, line) VALUES (?, ?, ?, ?, ?)',
                       (row(l) for l in data.decode("utf-8", "replace").split("\n")[:-1]))


# The bytes of a file that mark the part a table was made from: its first and its last EDGE bytes. A call reads them
# and the bytes past that part, never the whole file again: each call costs what was added since, not the history.
EDGE = 4096


def mark(f, size):
    """The hash of the first and last EDGE bytes of the first size bytes of the open file f."""
    h = hashlib.sha1()
    f.seek(0)
    h.update(f.read(min(size, EDGE)))
    f.seek(max(0, size - EDGE))
    h.update(f.read(min(size, EDGE)))
    return h.hexdigest()


def sync(db, folder, t):
    """Brings table t up to date with its file, in the open transaction: the whole lines past the part the table holds
    are added; a file shorter than that part, or whose marked bytes (mark) changed, was rewritten and is read anew."""
    try:
        f = open(os.path.join(folder, TABLES[t]), "rb")
    except FileNotFoundError:
        f = None
    with f if f else open(os.devnull, "rb") as f:
        kept = db.execute("SELECT size, sum FROM files WHERE name = ?", (t,)).fetchone()
        start = kept[0] if kept and f.seek(0, 2) >= kept[0] and mark(f, kept[0]) == kept[1] else 0
        f.seek(start)
        data = f.read()
        data = data[:data.rfind(b"\n") + 1]
        if start == 0:
            db.execute(f'DELETE FROM "{t}"')
        insert(db, t, data)
        size = start + len(data)
        db.execute("INSERT OR REPLACE INTO files (name, size, sum) VALUES (?, ?, ?)", (t, size, mark(f, size)))


def opened(folder, tables):
    """The database, brought up to date for those tables, in an open write transaction. A database that cannot be
    read is made anew from the files."""
    for again in (False, True):
        try:
            db = connect(folder)
            db.execute("BEGIN IMMEDIATE")
            for t in tables:
                sync(db, folder, t)
            return db
        except sqlite3.DatabaseError as e:
            # A lock not given in time (OperationalError) is no broken database.
            if again or isinstance(e, sqlite3.OperationalError):
                raise
            for x in ("", "-wal", "-shm"):
                try:
                    os.remove(os.path.join(folder, "state.db" + x))
                except FileNotFoundError:
                    pass


def append(folder, t):
    data = sys.stdin.buffer.read()
    if not data:
        return 0
    if not data.endswith(b"\n"):
        data += b"\n"
    db = None
    try:
        db = opened(folder, [t])
    except (sqlite3.Error, OSError) as e:
        print(f"state.py: the database could not be read ({e}); the lines go to the file alone", file=sys.stderr)
    path = os.path.join(folder, TABLES[t])
    try:
        with open(path, "ab") as f:
            f.write(data)
    except OSError as e:
        print(f"state.py: cannot write {path}: {e}", file=sys.stderr)
        if db:
            db.rollback()
        return 1
    if db:
        try:
            sync(db, folder, t)
            db.commit()
        except sqlite3.Error as e:
            print(f"state.py: the database did not take the lines ({e}); it takes them from the file next", file=sys.stderr)
    return 0


def rewrite(folder, t, data):
    """The file of t holds data (whole lines) alone, written in place (a lock held on the file itself must find the
    same file), and the table is made from it anew. Exit 1 when the file could not be written whole."""
    if data and not data.endswith(b"\n"):
        data += b"\n"
    db = None
    try:
        db = opened(folder, [])
    except (sqlite3.Error, OSError) as e:
        print(f"state.py: the database could not be read ({e}); the file alone is rewritten", file=sys.stderr)
    path = os.path.join(folder, TABLES[t])
    try:
        with open(path, "r+b" if os.path.exists(path) else "wb") as f:
            f.write(data)
            f.truncate()
    except OSError as e:
        print(f"state.py: cannot write {path} whole: {e}", file=sys.stderr)
        if db:
            db.rollback()
        return 1
    if db:
        try:
            db.execute("DELETE FROM files WHERE name = ?", (t,))
            sync(db, folder, t)
            db.commit()
        except sqlite3.Error as e:
            print(f"state.py: the database did not take the file ({e}); it takes it from the file next", file=sys.stderr)
    return 0


def keep(folder, t, over, n):
    """When the table holds more than over lines, the file and the table keep its last n."""
    db = opened(folder, [t])
    lines = None
    if db.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0] > over:
        lines = [r[0] for r in db.execute(f'SELECT line FROM (SELECT n, line FROM "{t}" ORDER BY n DESC LIMIT ?) ORDER BY n', (n,))]
    db.commit()
    return 0 if lines is None else rewrite(folder, t, "".join(l + "\n" for l in lines).encode("utf-8"))


def objects(rows, raw=False):
    """The lines that are JSON objects, as objects (or, raw, as (line, object): the line keeps its numbers as written,
    31.70 say, as jq prints them)."""
    for (line,) in rows:
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if isinstance(o, dict):
            yield (line.strip(), o) if raw else o


def fromdate(v):
    try:
        datetime.strptime(v, "%Y-%m-%dT%H:%M:%SZ")
        return True
    except (TypeError, ValueError):
        return False


def dumps(o):
    return json.dumps(o, ensure_ascii=False, separators=(",", ":"))


def answer(db, q, a):
    one = lambda sql, *p: [r[0] for r in db.execute(sql, p)]
    if q == "lines":
        if a[0] not in TABLES:
            fail(f"no table {a[0]}")
        return one(f'SELECT line FROM "{a[0]}" ORDER BY n')
    if q == "issue":
        if a[0] not in TABLES or not a[1].isdigit():
            fail(f"not a table and an issue number: {' '.join(a)}")
        return one(f'SELECT line FROM "{a[0]}" WHERE issue = ? ORDER BY n', int(a[1]))
    if q == "tail":
        if a[0] not in TABLES or not a[1].isdigit():
            fail(f"not a table and a count: {' '.join(a)}")
        return one(f'SELECT line FROM (SELECT n, line FROM "{a[0]}" ORDER BY n DESC LIMIT ?) ORDER BY n', int(a[1]))
    if q == "card":
        return one("SELECT line FROM cards WHERE card = ? ORDER BY n", a[0])
    if q == "last":
        return one("SELECT line FROM cards WHERE card = ? ORDER BY n DESC LIMIT 1", a[0])
    if q == "lastreview":
        return one("SELECT line FROM cards WHERE card = ? AND step = 'review' ORDER BY n DESC LIMIT 1", a[0])
    if q == "ended":
        return [str(bool(one("SELECT 1 FROM cards WHERE card = ? AND step IN ('landed', 'closed', 'blocked') LIMIT 1",
                            a[0]))).lower()]
    if q == "tested":
        return [str(bool(one("SELECT 1 FROM cards WHERE card = ? AND step = 'test' AND instr(line, '\"checks\":true') = 0 LIMIT 1",
                             a[0]))).lower()]
    if q == "pushes":
        out = []
        for t in ("cards", "retried"):
            for o in objects(db.execute(f"SELECT line FROM {t} WHERE step IN ('push', 'pushed') ORDER BY n")):
                p = {"step": o.get("step"), "time": o.get("time"), "sec": o.get("sec")}
                if isinstance(o.get("head"), str) and o["head"] != "":
                    p["head"] = o["head"]
                out.append(dumps(p))
        return out
    if q == "yes":
        out = []
        for o in objects(db.execute("SELECT line FROM cards WHERE step = 'blocked' ORDER BY n")):
            r, k = o.get("reason"), o.get("kept") or ""
            if isinstance(r, str) and r.startswith(a[0]) and k != "":
                out.append(f"{o.get('card')}\t{a[1]}/{k}")
        return out
    if q == "samples":
        rows = db.execute("SELECT line FROM (SELECT n, line FROM samples ORDER BY n DESC LIMIT 20160) ORDER BY n")
        return [l for l, o in objects(rows, True)
                if isinstance(o.get("time"), str) and isinstance(o.get("slots"), (int, float))
                and not isinstance(o.get("slots"), bool) and fromdate(o["time"])]
    if q == "limit":
        rows = db.execute('SELECT line FROM (SELECT n, line FROM "limit" ORDER BY n DESC LIMIT 4000) ORDER BY n')
        return [l for l, o in objects(rows, True)
                if isinstance(o.get("pct"), (int, float)) and not isinstance(o.get("pct"), bool)
                and isinstance(o.get("time"), str) and (o.get("account") or "") == a[0]]


def ask(folder, argv):
    asks, cur = [], []
    for x in argv + ["--"]:
        if x != "--":
            cur.append(x)
            continue
        out = None
        if cur[:1] == ["-o"]:
            if len(cur) < 2:
                fail("-o names no file")
            out, cur = cur[1], cur[2:]
        if not cur or cur[0] not in QUESTIONS or len(cur) - 1 != QUESTIONS[cur[0]]:
            fail(f"not a question: {' '.join(cur)}")
        asks.append((out, cur[0], cur[1:]))
        cur = []
    # The tables the questions read, and no other: each is brought up to date with its file.
    need = set()
    for _, q, a in asks:
        need |= set(a[:1]) if q in ("lines", "issue", "tail") else {"pushes": {"cards", "retried"}, "samples": {"samples"},
                                                 "limit": {"limit"}}.get(q, {"cards"})
    # Every answer is read in the transaction that brought the tables up to date: one reading for all.
    db = opened(folder, sorted(t for t in need if t in TABLES))
    texts = [(out, "".join(l + "\n" for l in answer(db, q, a))) for out, q, a in asks]
    # The lock is let go before any answer is written: a reader of one call's pipe may wait on another call (two
    # process substitutions of one jq), and a call that held the lock while its pipe was full would hold that other
    # call back until its lock wait ran out.
    db.commit()
    for out, text in texts:
        if out is None:
            # A reader that stopped reading (`| head -1`) is no error: the rest is dropped, with no traceback, and
            # stdout is pointed at /dev/null so Python's flush at exit does not raise it again.
            try:
                sys.stdout.write(text)
                sys.stdout.flush()
            except BrokenPipeError:
                os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        else:
            with open(out, "w", encoding="utf-8") as f:
                f.write(text)
    return 0


def main(argv):
    if len(argv) < 3:
        fail("usage: state.py <state folder> append <table> | ask <question> [<arg>...] [-- ...]")
    folder, cmd = argv[1], argv[2]
    if cmd == "append" and len(argv) == 4 and argv[3] in TABLES:
        return append(folder, argv[3])
    if cmd == "rewrite" and len(argv) == 4 and argv[3] in TABLES:
        return rewrite(folder, argv[3], sys.stdin.buffer.read())
    if cmd == "keep" and len(argv) == 6 and argv[3] in TABLES and argv[4].isdigit() and argv[5].isdigit():
        return keep(folder, argv[3], int(argv[4]), int(argv[5]))
    if cmd == "ask":
        return ask(folder, argv[3:])
    fail(f"unknown command: {' '.join(argv[2:])}")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
