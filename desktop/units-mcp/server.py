#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""/units for Claude Desktop's Chat tab: an MCP App server over stdio, Python 3 standard library only.

One tool, `units`: it runs hooks/units-fetch.sh as /units runs it (hooks/units.tsx, in the checkout, with no mode),
reads its answer with a port of the parse in hooks/sources.ts (parseFetch, and the parts of boardOf and headerModel
the head needs), and with the weekly limit in the Board's limit.json gives the head lines /units prints as its text, and
the fetch's answer as its structured content, each record's snapshot with its own field names. The tool names the view
ui://conveyor/units, view.html beside this file, which Desktop draws. It only reads.

Usage: server.py [<checkout>]: the project's main checkout, where the fetch runs (default: the one this file is in).
The fetch is the one /units runs: the install of the project's engine, else the plugin's own beside this file.
"""
import json
import math
import os
import re
import subprocess
import sys
import unicodedata
from datetime import UTC, datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
URI = "ui://conveyor/units"
MIME = "text/html;profile=mcp-app"
# /units draws its text at the session's columns, else 56 (hooks/units.tsx): the Chat tab has no columns.
WIDTH = 56
# As hooks/units.tsx waits for the fetch.
FETCH_TIMEOUT = 75
TOOL = {
    "name": "units",
    "title": "Conveyor /units",
    "description": "Conveyor's board: what needs you, the belt, the queue and today's dollars, for every project of "
                   "this machine's host file. It only reads.",
    "inputSchema": {"type": "object", "properties": {}},
    "annotations": {"readOnlyHint": True},
    "_meta": {"ui": {"resourceUri": URI}},
}
CANNOT = "units: the Conveyor snapshot cannot be read"
WHY = {"nofile": "this machine has no host file", "config": "the host file is not understood"}


def one(v):
    return re.sub(r"\s+", " ", v).strip() if isinstance(v, str) else ""


def num(v):
    ok = isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
    return v if ok else None


# ---- the fetch's answer: sources.ts parseFetch ----

def _fast(f):
    if f[1:2] == ["none"] or f[1:2] == ["norecord"]:
        return {"state": f[1]}
    if f[1:2] == ["ok"] and len(f) > 4 and f[3].isdigit() and f[4].isdigit():
        return {"state": "ok", "branch": f[2], "ahead": int(f[3]), "dirty": int(f[4]),
                "subject": one(f[5] if len(f) > 5 else "")}
    return None


def _field(out, f):
    """One line before the host line, into out; False for a line it does not know."""
    k, at = f[0], (lambda i: f[i] if len(f) > i else "")
    if k == "paths":
        out.update(research=at(1), home=at(2), own=at(3))
    elif k == "fast":
        out["fast"] = _fast(f) or out["fast"]
    elif k == "foreman":
        out["foreman"] = f[1:]
    elif k == "foremandir":
        out["foremanDir"] = at(1)
    elif k == "engine" and one(" ".join(f[1:])):
        out["engine"] = one(" ".join(f[1:]))
    elif k == "host":
        rc = int(at(3)) if re.fullmatch(r"-?\d+", at(3)) else None
        out["host"] = {"name": at(1), "how": at(2), "rc": rc, "looked": [x for x in f[4:] if x]}
    else:
        return False
    return True


def parse_fetch(stdout):
    """The fetch's lines as sources.ts parseFetch reads them; None with no paths line (its home)."""
    out = {"research": "", "home": "", "own": "", "fast": {"state": "unread"}, "foreman": None, "foremanDir": "",
           "engine": None, "host": None, "records": []}
    for line in stdout.split("\n"):
        f = line.split("\t")
        if out["host"]:
            if len(f) >= 2 and f[0]:
                out["records"].append({"repo": f[0], "json": "\t".join(f[1:])})
        else:
            _field(out, f)
    return out if out["home"] else None


def read_snapshot(text):
    """A record's snapshot, as sources.ts parseRecord takes one; None when it cannot be read."""
    try:
        j = json.loads(text)
    except ValueError:
        return None
    if not isinstance(j, dict):
        return None
    ny = j.get("needsYou") if isinstance(j.get("needsYou"), dict) else {}
    lists = [ny.get("waiting"), ny.get("blocked"), j.get("belt"), j.get("landed")]
    if not all(isinstance(xs, list) and all(isinstance(x, dict) for x in xs) for xs in lists):
        return None
    return j if isinstance(j.get("queue"), dict) and isinstance(j.get("cost"), dict) else None


def why_none(f):
    """Why there is no board, as sources.ts boardOf says it; '' when the host answered."""
    if not f:
        return "the fetch did not run"
    if not f["host"]:
        return "the fetch did not finish"
    name, how, rc, looked = f["host"]["name"], f["host"]["how"], f["host"]["rc"], f["host"]["looked"]
    if how == "nofile" and looked:
        return f"{WHY['nofile']} at {' or '.join(looked)}"
    if how not in ("local", "ssh"):
        return WHY.get(how, "the fetch did not finish")
    if how == "ssh" and rc == 255:
        return f"{name} is unreachable"
    if rc in (124, 137):
        return f"{name} did not answer in time"
    return ""


# ---- the head: sources.ts headerModel, as plain text ----

def cols(t):
    """Width in terminal cells, as elements.ts cols counts it, per code point."""
    def cell(ch):
        if unicodedata.category(ch) in ("Mn", "Me", "Cf"):
            return 0
        return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return sum(cell(ch) for ch in t)


def fit_width(t, w):
    if cols(t) <= w:
        return t
    out, room = "", max(0, w - 1)
    for ch in t:
        if cols(ch) > room:
            break
        room -= cols(ch)
        out += ch
    return out + "…"


def spread(left, right, w):
    rw = cols(right or "")
    if not right or rw + 3 > w:
        return fit_width(left, w)
    lt = fit_width(left, w - rw - 2)
    return lt + " " * (w - cols(lt) - rw) + right


def fitting(rights, w, left=""):
    return next((r for r in rights if cols(r) + 3 <= w and cols(left) + cols(r) + 2 <= w), rights[-1])


def usd(n):
    return f"${math.floor(n * 100 + 0.5) / 100:.2f}"


def price_text(v, gap, estimate, short=False):
    tail = "" if not gap else "+" if short else f" + {gap} step{'' if gap == 1 else 's'} not priced"
    return f"{'~' if estimate else ''}{usd(v)}{tail}"


def day_of(recs, unread):
    """The day's dollars of every record, as sources.ts boardFrom adds them: None when one is not known."""
    todays = [num(j["cost"].get("today")) for _, j in recs]
    usd_ = None if unread or any(t is None for t in todays) else math.floor(sum(todays) * 100 + 0.5) / 100
    left = sum(num(j["cost"].get("todayLeftOut")) or 0 for _, j in recs)
    est = sum(num(j["cost"].get("todayEstimate")) or 0 for _, j in recs)
    return usd_, left, est > 0


def loop_text(recs):
    out = []
    for repo, j in recs:
        h = j.get("health") if isinstance(j.get("health"), dict) else {}
        state, reason = one(h.get("state")), one(h.get("reason"))
        if h.get("loop") is False:
            out.append(f"{repo}: no loop process")
        elif state and state != "running":
            out.append(f"{repo} {state}{': ' + reason if reason else ''}")
    return " · ".join(out)


def queued_text(recs):
    nexts = [[x for x in j["queue"]["next"] if isinstance(x, dict)] for _, j in recs
             if isinstance(j["queue"].get("next"), list)]
    if not nexts:
        return "queue not read"
    return f"{sum(len(q) for q in nexts)}{'+' if any(len(q) >= 10 for q in nexts) else ''} queued"


def limit_text(limit, now):
    """sources.ts limitLine as text: the weekly limit and its reset (elements.ts resetIn), from a parsed limit."""
    if not limit:
        return "weekly limit not read"
    s = math.floor((limit["resetsAt"] - now).total_seconds() + 0.5)
    d = s // 86400
    r = "" if s <= 0 else f"{d}d {s % 86400 // 3600}h" if d else f"{s // 3600}h {s % 3600 // 60}m" if s >= 3600 \
        else f"{max(1, s // 60)}m"
    return f"weekly limit {math.floor(limit['pct'] + 0.5)}%" + (f" · resets {r}" if r else "")


def head_lines(host, recs, unread, limit_line="weekly limit not read", w=WIDTH):
    """The head /units prints (sources.ts headerModel), with limit_line (limit_text) as its limit."""
    day_usd, left_out, est = day_of(recs, unread)
    def today(short=False):
        return "today partial" if day_usd is None else f"today {price_text(day_usd, left_out, est, short)}"
    lt = loop_text(recs)
    left, at_host = "CONVEYOR" + (f" · {lt}" if lt else ""), f"  ● {host}"
    beside = fitting([today() + at_host, today(), today(True) + at_host, today(True)], w, left)
    fits = cols(beside) + 3 <= w and cols(left) + cols(beside) + 2 <= w
    day = beside if fits else fitting([today(), today(True)], w)
    lines = [spread(left, day if fits else None, w)] + ([] if fits else [spread("", day, w)])
    if day_usd is not None and left_out > 0 and not day.startswith(f"today {price_text(day_usd, left_out, est)}"):
        full = price_text(day_usd, left_out, est)
        t = full if cols(full) <= w else f"{'~' if est else ''}{usd(day_usd)} + {left_out} not priced"
        lines.append(fit_width(" " * max(0, w - cols(t)) + t, w))
    belt = sum(len(j["belt"]) for _, j in recs)
    lines.append(spread(limit_line, f"{belt} on belt · {queued_text(recs)}", w))
    return lines


# ---- the tool ----

def units(stdout, now, limit=None):
    """The tool's result for the fetch's answer (None when the fetch did not run), read at now (a UTC datetime), with
    the Board's weekly limit (read_limit; None when not read)."""
    f = parse_fetch(stdout) if stdout is not None else None
    read = [(r["repo"], read_snapshot(r["json"])) for r in (f["records"] if f else [])]
    recs = [(repo, j) for repo, j in read if j is not None]
    host = f["host"]["name"] if f and f["host"] else ""
    why = why_none(f) or ("" if recs else f"{host} gave no snapshot")
    notes = [f"units: the {repo} snapshot cannot be read" for repo, j in read if j is None]
    note = f"{CANNOT} ({why})" if why else ""
    limit_line = limit_text(limit, now)
    head = [note] if why else head_lines(host, recs, len(recs) < len(read), limit_line)
    content = {
        "readAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "note": note, "notes": notes, "head": head, "limitLine": limit_line,
        "host": f["host"] if f else None, "own": f["own"] if f else "", "foreman": f["foreman"] if f else None,
        "records": [] if why else [{"repo": repo, "snapshot": j} for repo, j in read],
    }
    return {"content": [{"type": "text", "text": "\n".join(head)}], "structuredContent": content}


def _json_file(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def fetch_path(checkout, env):
    """The fetch, found as units.tsx fetchPath finds it: the one in the install of the project's engine (the commit
    the pack pins, else for a pack that follows the plugin's main the commit this machine took), else the plugin's own."""
    own = HERE.parents[1] / "hooks" / "units-fetch.sh"
    pack = _json_file(Path(checkout) / ".conveyor" / "project.json")
    plugin = pack.get("plugin") if isinstance(pack, dict) and isinstance(pack.get("plugin"), dict) else {}
    took = _json_file(Path(checkout) / ".git" / "conveyor-engine.json") if plugin.get("follow") else None
    commit = plugin.get("commit") or (took.get("commit") if isinstance(took, dict) else "")
    # Only a full commit id names a version folder: anything else could name a path outside versions/.
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        return own
    data = env.get("XDG_DATA_HOME") or (env.get("HOME") and f"{env['HOME']}/.local/share")
    path = Path(data) / "conveyor" / "versions" / commit / "hooks" / "units-fetch.sh" if data else None
    return path if path and path.exists() else own


def fetch(checkout):
    """The fetch's answer, run as /units runs it; None when it did not run."""
    try:
        r = subprocess.run(["bash", str(fetch_path(checkout, os.environ))], cwd=checkout, capture_output=True, timeout=FETCH_TIMEOUT, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.decode("utf-8", "replace")


# The Board's limit file holds the usage limit alone, a few hundred bytes; a larger one is not the Board's (units.tsx).
MAX_LIMIT = 16 * 1024


def feed_dir(checkout):
    """The Board's folder, named by units.tsx's own FEED_DIR script (read from that file, so the two never drift);
    None when it cannot be named."""
    try:
        tsx = (HERE.parents[1] / "hooks" / "units.tsx").read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.search(r"^const FEED_DIR = String\.raw`\n(.*?)^`$", tsx, re.DOTALL | re.MULTILINE)
    if not m:
        return None
    try:
        r = subprocess.run(["bash", "-c", m.group(1), "units-feed"], cwd=checkout, capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    d = r.stdout.strip()
    return d if r.returncode == 0 and d.startswith("/") and "\n" not in d else None


def parse_time(v):
    """sources.ts time for an ISO time: an aware datetime (a time with no offset is local, as Date.parse reads it)."""
    try:
        t = datetime.fromisoformat(v) if isinstance(v, str) else None
    except ValueError:
        return None
    return t.astimezone() if t and t.tzinfo is None else t


def read_limit(checkout):
    """The weekly limit in the Board's limit.json, as units.tsx readLimit and sources.ts parseLimit read it:
    {"pct", "resetsAt"}, or None when there is none to read."""
    d = feed_dir(checkout)
    file = Path(d) / "limit.json" if d else None
    try:
        if not file or file.stat().st_size > MAX_LIMIT:
            return None
    except OSError:
        return None
    j = _json_file(file)
    lim = j.get("limit") if isinstance(j, dict) and isinstance(j.get("limit"), dict) else {}
    pct, at = num(lim.get("usedPct")), parse_time(lim.get("resetsAt"))
    return None if pct is None or at is None else {"pct": pct, "resetsAt": at}


# ---- MCP over stdio: one JSON-RPC message a line ----

def answer(msg, checkout):
    """The result of one request, or (code, message) for an error."""
    method, params = msg.get("method"), msg.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion") or "2025-06-18",
                "capabilities": {"tools": {"listChanged": False}, "resources": {"listChanged": False}},
                "serverInfo": {"name": "conveyor-units", "version": "1"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [TOOL]}
    if method == "tools/call":
        if params.get("name") != "units":
            return (-32602, f"no tool {params.get('name')!r}")
        out = fetch(checkout)
        # As units.tsx: the limit only with a fetch that ran.
        return units(out, datetime.now(UTC), read_limit(checkout) if out is not None else None)
    if method == "resources/list":
        return {"resources": [{"uri": URI, "name": "Conveyor /units", "mimeType": MIME}]}
    if method == "resources/read":
        if params.get("uri") != URI:
            return (-32602, f"no resource {params.get('uri')!r}")
        return {"contents": [{"uri": URI, "mimeType": MIME, "text": (HERE / "view.html").read_text(encoding="utf-8")}]}
    return (-32601, f"no method {method!r}")


def serve(checkout, inp=sys.stdin, out=sys.stdout):
    for line in inp:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if not isinstance(msg, dict) or "id" not in msg:
            continue  # a notification: nothing to answer
        r = answer(msg, checkout)
        body = {"error": {"code": r[0], "message": r[1]}} if isinstance(r, tuple) else {"result": r}
        out.write(json.dumps({"jsonrpc": "2.0", "id": msg["id"], **body}) + "\n")
        out.flush()


if __name__ == "__main__":
    serve(sys.argv[1] if len(sys.argv) > 1 else str(HERE.parents[1]))
