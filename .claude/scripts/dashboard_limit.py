#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""The dashboard's 7-day limit panel, called by dashboard.sh.

  dashboard_limit.py fetch [<config-folder> [<cache-dir>]]
      Claude's own usage reading (the statusline's source) as JSON on stdout;
      exit 1 with no output when there is no login token or the read fails, and
      the cause as one stderr line (dashboard.sh shows it and honours its
      `retry after <n> s`). The reading is the account in use's (with a folder: that folder's account; the
      engine's guard names the account a project's cards use) and carries it as `account`. With a cache folder
      the account's 429 deadline is the one `accounts` keeps for it: both honour it and both keep their reads there.
  dashboard_limit.py account
      {folder, email} of the Claude account in use: the config folder whose metadata file was written last.
  dashboard_limit.py accounts <cache-dir> [<usage-file>]
      Every Claude account this machine can read, each with its own usage (accounts()). The email is for the
      Board alone: it is never written anywhere else. With dashboard.sh's usage file (its copy of fetch's
      reading), the account fetch reads is shown from that file and not read a second time.
  dashboard_limit.py build <status> <usage-file> <now-epoch> <cache-dir> <projects-dir> [<codex-sessions-dir> [<project-folder>...]]
      The panel's JSON. <status> is dashboard.sh's record for the usage file.
      With the Codex sessions folder it adds `codex`: Codex's own 7-day
      reading, never summed with Claude's. With project folders, `today`
      counts only the sessions run in them; every other figure is the account's. The env PP_PRICES holds
      the pack's model prices, added models and aliases (its `prices`, as JSON), put over the built-in table (use_prices).
  dashboard_limit.py cards  < {cards: [...], prices, since, research}
      Conveyor's cards with each finished session, review and test run priced at list price (conveyor.sh snapshot).

Every figure comes from that reading or from Claude Code's own transcripts; a
figure with no source is null, never 0 or an estimate. Dollars are list-price
equivalents of the transcripts' token counts: what the same
usage would cost on the pay-as-you-go API. The reading carries no
history, so each new sample is appended to <cache-dir>/limit-history.jsonl and
the chart draws from that file.
"""
import email.utils
import glob
import hashlib
import json
import math
import os
import platform
import re
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone


def closing_root():
    """The folder the closing review copies run in: PP_SCRATCH (dashboard.sh sets it), else CONVEYOR_SCRATCH; raises
    when neither is set. The Board sources no paths.sh."""
    s = os.environ.get("PP_SCRATCH") or os.environ.get("CONVEYOR_SCRATCH")
    if not s:
        raise RuntimeError("dashboard_limit: no scratch folder (PP_SCRATCH and CONVEYOR_SCRATCH unset)")
    return os.path.join(s, "closing-copy")


DAY = 86400
WEEK = 7 * DAY
FIVE_HOURS = 5 * 3600
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
HISTORY_KEEP = 14 * 86400
ACCOUNT_TTL = 300  # accounts(): each account's usage is read again once its last answer is this old (dashboard.sh's TTL),
# and after a failed read not before the `retry after <n> s` it named when that is longer


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return None


def active_folder(found=None):
    """{folder, email} of the Claude account in use: the config folder whose metadata file was written last.

    The candidates are `found` ([(folder, metadata file)]), else config_folders(): CLAUDE_CONFIG_DIR when set, the
    default folder ~/.claude, then any extra profile folders found. Claude Code rewrites the metadata file through every session. With no metadata file
    anywhere it is the first candidate, email None. A profile manager's own account store is a credential store
    and is not read.
    """
    found = found or config_folders()
    seen = []
    for folder, meta in found:
        try:
            seen.append((os.stat(meta).st_mtime, -len(seen), folder, meta))
        except OSError:
            pass
    folder, meta = max(seen)[2:] if seen else found[0]
    return {"folder": folder, "email": account_email(meta)}


def config_folders():
    """[(config folder, its metadata file)], each folder once: CLAUDE_CONFIG_DIR when set (metadata
    <dir>/.claude.json), the default folder ~/.claude (metadata $HOME/.claude.json; ~/.claude/.claude.json does not
    exist), then the optional extra profile folders: <root>/*/home of each root in extra_profile_roots() that exists.
    A machine with none of those roots reads the first two alone, with no warning."""
    home = os.path.expanduser("~")
    default = os.path.join(home, ".claude")
    found = []
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    if env:
        env = os.path.abspath(os.path.expanduser(env))
        found.append((env, os.path.join(home, ".claude.json") if env == default else os.path.join(env, ".claude.json")))
    found.append((default, os.path.join(home, ".claude.json")))
    found += [(h, os.path.join(h, ".claude.json"))
              for root in extra_profile_roots() for h in sorted(glob.glob(os.path.join(glob.escape(root), "*", "home")))]
    out, seen = [], set()
    for folder, meta in found:
        if folder not in seen:
            seen.add(folder)
            out.append((folder, meta))
    return out


def extra_profile_roots():
    """Folders that may hold extra Claude profiles as <root>/<name>/home: CONVEYOR_CLAUDE_PROFILES when set, else
    none: no terminal app's folder is read by default. Optional: a root that does not exist adds nothing."""
    root = os.environ.get("CONVEYOR_CLAUDE_PROFILES")
    return [root] if root else []


def account_email(meta):
    try:
        with open(meta) as f:
            email = json.load(f)["oauthAccount"]["emailAddress"]
    except (OSError, ValueError, KeyError, TypeError):
        return None
    return email if isinstance(email, str) else None


def token(folder):
    # The same stores the statusline reads: the Mac keychain, else the credentials file, of the config folder given.
    # A profile's keychain item is suffixed with the first 8 hex of sha256 of its folder path; ~/.claude's is not.
    default = folder == os.path.join(os.path.expanduser("~"), ".claude")
    if (os.environ.get("CONVEYOR_HOST_OS") or platform.system()) == "Darwin":
        item = "Claude Code-credentials" + ("" if default else "-" + hashlib.sha256(folder.encode()).hexdigest()[:8])
        r = subprocess.run(["security", "find-generic-password", "-s", item, "-w"], capture_output=True, text=True)
        raw = r.stdout if r.returncode == 0 else ""
    else:
        try:
            with open(os.path.join(folder, ".credentials.json")) as f:
                raw = f.read()
        except OSError:
            raw = ""
    try:
        return json.loads(raw)["claudeAiOauth"]["accessToken"]
    except (ValueError, KeyError, TypeError):
        return None


def fetch(folder=None, cache_dir=None):
    # One read of the account for the token and the label: a switch while the request is out must not relabel it.
    # With a folder (the engine's: the account a project's cards use), that account's, never the one written last.
    account = active_folder() if folder is None else {"folder": folder, "email": account_email(metadata(folder))}
    # With a cache folder (dashboard.sh's), the account's 429 deadline is the one accounts() keeps for it
    # (account_reading()), whichever of the two was refused: dashboard.sh drops its own deadline on a switch, so an
    # account switched to or from was asked again at once. Each read here is kept there too.
    if cache_dir:
        now = time.time()
        cache, kept = account_cache(cache_dir, account["folder"])
        err = kept.get("error") if isinstance(kept.get("error"), str) else ""
        wait = re.search(r"; retry after [0-9]+ s$", err)
        if wait and isinstance(kept.get("next"), (int, float)) and now < kept["next"]:
            print("%s; retry after %d s" % (err[:wait.start()], math.ceil(kept["next"] - now)), file=sys.stderr)
            return 1
    body, why = usage(account["folder"])
    if cache_dir:
        note(cache, kept, now, body, why)
    if body is None:
        print(why, file=sys.stderr)
        return 1
    # The reading says whose it is, so dashboard.sh can drop it when the account in use changes.
    json.dump({**body, "account": account}, sys.stdout)
    return 0


def metadata(folder):
    """The metadata file of a config folder (config_folders()' rule)."""
    home = os.path.expanduser("~")
    return os.path.join(home, ".claude.json") if folder == os.path.join(home, ".claude") else os.path.join(folder, ".claude.json")


def usage(folder):
    """(the usage reading of the account signed in at `folder`, None) or (None, why it was not read: one line)."""
    t = token(folder)
    if not t:
        return None, "no login token"
    req = urllib.request.Request(USAGE_URL, headers={"Authorization": f"Bearer {t}", "anthropic-beta": "oauth-2025-04-20"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            body = json.load(r)
    except urllib.error.HTTPError as e:
        why = f"HTTP {e.code}"
        if e.code == 429:
            why = "rate limited (429)"
            wait = (e.headers.get("Retry-After") or "") if e.headers else ""
            if not wait.isdigit():
                # The header may also be an HTTP-date (RFC 9110): seconds from now, rounded up.
                try:
                    wait = str(max(0, math.ceil((email.utils.parsedate_to_datetime(wait) - datetime.now(timezone.utc)).total_seconds())))
                except (TypeError, ValueError):
                    wait = ""
            if wait:
                why += f"; retry after {wait} s"
        return None, why
    except OSError as e:
        # A connect timeout arrives wrapped in URLError.reason.
        return None, "timeout" if isinstance(getattr(e, "reason", e), TimeoutError) else "network error"
    except ValueError:
        return None, "malformed response"
    if not isinstance(body, dict) or not isinstance(body.get("seven_day"), dict):
        return None, "malformed response"
    return body, None


def accounts(cache_dir, now, usage_file=None):
    """Every Claude account this machine can read, each with its own usage: config_folders() (the folder in use,
    ~/.claude, the extra profile folders) and the accounts of this machine's Conveyor host file, each folder once.
    [{name, listedAs, folder, email, inUse, default, foreman, usedPct, resetsAt, fiveHourPct, readAt, error}]: name is the host file's, else
    "default" for ~/.claude, else the folder's own name; listedAs is every host file name the engine runs on this
    folder (its acctdir: the first account of a name), so a display name another row shares claims nothing; inUse marks the folder written last (active_folder()),
    default the default login (~/.claude: what a project that names no account runs on), foreman a folder holding
    the transcript of one of this machine's marked Foreman sessions (metadata recency proves nothing of it);
    readAt is when the figures were read (null with none); error says why the last read failed (any figures are then
    the last ones read). Each folder is read by account_reading(). With `usage_file` (dashboard.sh's copy of fetch()'s
    reading), the account fetch() reads is shown from that file (shared_reading()) and never read here: the usage
    endpoint refuses (429) for an hour and more an account asked for too often, and this second read of the same
    account each cycle, retried every ACCOUNT_TTL whatever wait the 429 named, kept it refused."""
    home = os.path.expanduser("~")
    named, host = [], {}
    try:
        with open(os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config"), "conveyor", "host.json")) as f:
            host = json.load(f)
        listed = host.get("accounts") or []
        for a in listed if isinstance(listed, list) else []:
            if isinstance(a, dict) and isinstance(a.get("name"), str) and isinstance(a.get("configDir"), str) and a["configDir"]:
                # ~/ and a relative folder are under the home folder, as the engine reads them (acctdir).
                d = a["configDir"]
                named.append((a["name"], os.path.join(home, d[2:] if d.startswith("~/") else d)))
    except (OSError, ValueError, AttributeError):
        pass
    default = os.path.join(home, ".claude")
    names = {d: n for n, d in named}
    first = {}
    for n, d in named:
        first.setdefault(n, d)
    found = config_folders()
    for _, d in named:
        if d not in [f for f, _ in found]:
            found.append((d, metadata(d)))
    # The folder in use is the one written last among all of them, the host file's too.
    in_use = active_folder(found)["folder"]
    # This machine's Foreman sessions (conveyor/foreman/lib.sh's mark, one a project or group): each is `foreman/session`
    # in its project's state folder, which is the host file's stateDir for the host file's own checkout and the
    # checkout's conveyor/state for any other (conveyor.sh's ST). The projects are the host file's records and the
    # main checkout of the one this script is in (a linked worktree's Foreman is its main checkout's). A group's mark
    # is in its first-named project's folder only (lib.sh's FD): one a grouped project kept from before is no
    # Foreman's. The folder holding a marked session's transcript ran it.
    host = host if isinstance(host, dict) else {}
    recs = host.get("records")
    recs = [r for r in recs if isinstance(r, dict) and isinstance(r.get("main"), str) and r["main"]] if isinstance(recs, list) else []
    hmain = host.get("main") or (recs[0]["main"] if recs else None)
    groups = host["foreman"].get("groups") if isinstance(host.get("foreman"), dict) else None
    groups = groups if isinstance(groups, list) and all(isinstance(g, list) and all(isinstance(n, str) for n in g) for g in groups) else []
    # A name in two groups, or twice in one, is not understood: no claim is made then, and each project's own folder is read.
    groups = groups if len({n for g in groups for n in g}) == sum(len(g) for g in groups) else []
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        common = subprocess.run(["git", "-C", here, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True).stdout.strip()
    except OSError:
        common = ""
    holders = set()
    for m in [os.path.dirname(common) if common else os.path.dirname(os.path.dirname(here)), hmain] + [r["main"] for r in recs]:
        if not isinstance(m, str) or not m:
            continue
        rec = next((r for r in recs if os.path.realpath(r["main"]) == os.path.realpath(m)), None)
        if rec is not None:
            group = next((g for g in groups if rec.get("repo") in g), [rec.get("repo")])
            m = next((r["main"] for n in group for r in recs if r.get("repo") == n), m)
        holders.add(m)
    sids = set()
    for m in holders:
        st = host.get("stateDir") if not isinstance(hmain, str) or os.path.realpath(hmain) == os.path.realpath(m) else None
        try:
            with open(os.path.join(st if isinstance(st, str) and st else os.path.join(m, "conveyor", "state"), "foreman", "session")) as f:
                sid = (f.read().split() or [""])[0]
        except OSError:
            continue
        if re.fullmatch(r"[A-Za-z0-9-]+", sid):
            sids.add(sid)
    # The folder fetch() reads (active_folder() over config_folders(), as `dashboard_limit.py account` names it).
    shared = active_folder()["folder"] if usage_file else None
    out = []
    for folder, _ in found:
        kept = shared_reading(usage_file, folder) if folder == shared else account_reading(cache_dir, folder, now)
        body = kept.get("body") if isinstance(kept.get("body"), dict) else {}
        seven, five = body.get("seven_day") or {}, body.get("five_hour") or {}
        num = lambda v: v if isinstance(v, (int, float)) else None
        # A profile folder is <root>/<name>/home: its name is the profile's.
        own = os.path.basename(folder.rstrip("/"))
        own = os.path.basename(os.path.dirname(folder.rstrip("/"))) if own == "home" else own
        out.append({"name": names.get(folder) or ("default" if folder == default else own or folder),
                    "listedAs": [n for n, d in first.items() if d == folder],
                    "folder": folder, "email": account_email(metadata(folder)), "inUse": folder == in_use, "default": folder == default,
                    "foreman": any(glob.glob(os.path.join(glob.escape(folder), "projects", "*", sid + ".jsonl")) for sid in sids),
                    "usedPct": num(seven.get("utilization")), "resetsAt": seven.get("resets_at") if isinstance(seven.get("resets_at"), str) else None,
                    "fiveHourPct": num(five.get("utilization")),
                    "readAt": iso(kept["bodyAt"]) if body and isinstance(kept.get("bodyAt"), (int, float)) else None,
                    "error": kept.get("error")})
    return out


def shared_reading(usage_file, folder):
    """{body, bodyAt, error} from dashboard.sh's usage file when it is `folder`'s reading: its time is the file's, and
    the reason its last read failed is the one in <usage_file>.retry ("<retry-at epoch> <reason>", cached())."""
    kept = {"body": None, "bodyAt": None, "error": None}
    try:
        with open(usage_file) as f:
            body = json.load(f)
        if isinstance(body, dict) and isinstance(body.get("account"), dict) and body["account"].get("folder") == folder:
            kept.update(body=body, bodyAt=os.stat(usage_file).st_mtime)
    except (OSError, ValueError):
        pass
    try:
        with open(usage_file + ".retry") as f:
            kept["error"] = (f.read().strip().split(" ", 1) + [""])[1] or "read failed"
    except OSError:
        if kept["body"] is None:
            kept["error"] = "not read yet"
    return kept


def account_reading(cache_dir, folder, now):
    """{at, next, body, bodyAt, error} of `folder`'s account, kept in <cache_dir>/account-<sha8 of the folder>.json and
    read again only once `next` has passed: ACCOUNT_TTL after a read, and after a failed one the longer of that and
    the `retry after <n> s` it named. A failed read keeps the last figures and their time (bodyAt). fetch() keeps
    its reads of the account in use here too, so a 429 deadline outlives a switch whichever path was refused."""
    cache, kept = account_cache(cache_dir, folder)
    if isinstance(kept.get("next"), (int, float)) and now < kept["next"]:
        return kept
    return note(cache, kept, now, *usage(folder))


def account_cache(cache_dir, folder):
    """(<cache_dir>/account-<sha8 of the folder>.json, what it holds: {} when nothing readable)."""
    cache = os.path.join(cache_dir, "account-%s.json" % hashlib.sha256(folder.encode()).hexdigest()[:8])
    try:
        with open(cache) as f:
            kept = json.load(f)
        kept = kept if isinstance(kept, dict) else {}
    except (OSError, ValueError):
        kept = {}
    return cache, kept


def note(cache, kept, now, body, why):
    """Writes one read of the account (usage()'s answer) over `kept` into `cache`, as account_reading() keeps it."""
    if body is not None:
        kept = {"at": now, "next": now + ACCOUNT_TTL, "body": body, "bodyAt": now, "error": None}
    else:
        wait = re.search(r"retry after ([0-9]+) s", why)
        kept = {"at": now, "next": now + max(ACCOUNT_TTL, int(wait.group(1)) if wait else 0),
                "body": kept.get("body") if isinstance(kept.get("body"), dict) else None,
                "bodyAt": kept.get("bodyAt") if isinstance(kept.get("bodyAt"), (int, float)) else None, "error": why}
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    tmp = "%s.%d" % (cache, os.getpid())
    with open(tmp, "w") as f:
        json.dump(kept, f)
    os.replace(tmp, cache)
    return kept


def pace(used, reset, now):
    """Goal, pace and time left for one reading; every key None without one.

    The goal is the linear share of the elapsed week. underPts > 0 is under pace;
    paceSec is the week time those points equal, from the unrounded gap.
    """
    if used is None or reset is None or reset <= now:
        return {"usedPct": None, "goalPct": None, "underPts": None, "paceSec": None, "timeLeftSec": None}
    start = reset - WEEK
    goal = max(0.0, min(100.0, (now - start) / WEEK * 100))
    under = goal - used
    return {"usedPct": used, "goalPct": goal, "underPts": under, "paceSec": round(under / 100 * WEEK),
            "timeLeftSec": round(reset - now)}


def record(history_path, at, pct, now, folder=None):
    """Append one sample unless the newest row of this account already holds it; drop rows past HISTORY_KEEP.

    A row carries the config folder of the account it was read for; Codex's rows carry none. Other accounts'
    rows are kept as they are. Returns this account's rows.
    """
    rows = _history_rows(history_path)
    mine = [r for r in rows if r[2] == folder]
    if mine and mine[-1][0] >= at:
        return [r[:2] for r in mine]
    rows = sorted([r for r in rows if r[0] >= now - HISTORY_KEEP] + [(at, pct, folder)], key=lambda r: (r[0], r[1], r[2] or ""))
    tmp = f"{history_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        f.writelines(json.dumps({"at": iso(a), "pct": p, **({"folder": fo} if fo is not None else {})}) + "\n" for a, p, fo in rows)
    os.replace(tmp, history_path)
    return [r[:2] for r in rows if r[2] == folder]


def _history_rows(path):
    rows = []
    try:
        with open(path) as f:
            for line in f:
                try:
                    r = json.loads(line)
                    a, p = epoch(r["at"]), r["pct"]
                except (ValueError, KeyError, TypeError):
                    continue
                if a is not None and isinstance(p, (int, float)):
                    rows.append((a, p, r.get("folder") if isinstance(r.get("folder"), str) else None))
    except OSError:
        pass
    return sorted(rows, key=lambda r: (r[0], r[1], r[2] or ""))


def read_history(path, folder=None):
    """(time, pct) rows of one account: those written for `folder`, or for none (Codex's file, and Claude rows written
    before the folder was recorded, which no account owns)."""
    return [r[:2] for r in _history_rows(path) if r[2] == folder]


def request_key(r):
    """A request's dedupe key: its requestId, or its message id behind an API proxy, which logs none, else the line's own id.

    Every streamed line of one request shares its message id, so the key never counts a request twice. A line with
    neither is counted under its own uuid, so a proxy run never reads as zero.
    """
    msg = r.get("message")
    key = r.get("requestId") or (msg.get("id") if isinstance(msg, dict) else None) or r.get("uuid")
    return key if isinstance(key, str) else None


def request_row(r):
    """[time, model, input, 5-min cache write, 1-hour cache write, cache read, output] or None.

    A fast-mode request keeps the model name with a ":fast" suffix, so the price
    table never prices it at the standard rate. A count the usage lacks stays
    None, so a price that depends on the prompt size can tell unknown from zero.

    An advisor call is logged only as an "advisor_message" entry in
    usage.iterations: the top-level counts leave it out. Each one follows
    the seven fields as its own row of the same shape, under its own model.
    """
    rid, at, msg = request_key(r), epoch(r.get("timestamp")), r.get("message")
    if r.get("type") != "assistant" or rid is None or at is None or not isinstance(msg, dict):
        return None
    u = msg.get("usage") if isinstance(msg.get("usage"), dict) else {}
    n = lambda d, k: d.get(k) if isinstance(d.get(k), int) else None

    def counts(u, model):
        cc = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else None
        w5, w1 = (n(cc, "ephemeral_5m_input_tokens"), n(cc, "ephemeral_1h_input_tokens")) if cc else (n(u, "cache_creation_input_tokens"), 0)
        return [at, model, n(u, "input_tokens"), w5, w1, n(u, "cache_read_input_tokens"), n(u, "output_tokens")]

    its = u.get("iterations") if isinstance(u.get("iterations"), list) else []
    return counts(u, str(msg.get("model")) + (":fast" if u.get("speed") == "fast" else "")) + [
        counts(i, str(i.get("model"))) for i in its if isinstance(i, dict) and i.get("type") == "advisor_message"]


# List prices in $ per million tokens: (input, output, cache read). Cache writes
# are 1.25x input for the 5-minute TTL and 2x for 1 hour. Source:
# https://platform.claude.com/docs/en/about-claude/pricing, read 2026-11-16.
# The ":fast" Claude rows are that page's "Fast mode pricing" table, read
# 2026-11-16; the cache multipliers stack on the fast input price. The gpt-*
# rows are Codex's models, from the Standard and Fast tables of
# https://developers.openai.com/api/docs/pricing, read 2026-11-16 (a cache
# write is 1.25x input there too; "priority" in a Codex log is its fast mode).
# A mode with no published price is priced by estimate() and its dollars are
# reported as estimated. A model with no row and nothing to estimate from is
# unpriced, never $0. Haiku 5.5 steps up for prompts over 100K tokens (input +
# cache read + cache write) and the gpt-* models over 272K: PRICES holds the
# short-prompt rate, LONG_PRICES the rest, LONG_AT a threshold that is not 100K.
PRICES = {
    "claude-fable-5-2": (8.0, 40.0, 0.20),
    "claude-mythos-5-2": (8.0, 40.0, 0.20),
    "claude-fable-5-1": (10.0, 50.0, 0.25),
    "claude-mythos-5-1": (10.0, 50.0, 0.25),
    "claude-fable-5": (10.0, 50.0, 1.00),
    "claude-mythos-5": (10.0, 50.0, 1.00),
    "claude-opus-5-5": (4.0, 20.0, 0.20),
    "claude-opus-5": (5.0, 25.0, 0.50),
    "claude-opus-4-8": (5.0, 25.0, 0.50),
    "claude-opus-4-7": (5.0, 25.0, 0.50),
    "claude-opus-4-6": (5.0, 25.0, 0.50),
    "claude-opus-4-5": (5.0, 25.0, 0.50),
    "claude-sonnet-5-5": (2.0, 10.0, 0.10),
    "claude-sonnet-5": (2.0, 10.0, 0.20),
    "claude-sonnet-4-6": (3.0, 15.0, 0.30),
    "claude-sonnet-4-5": (3.0, 15.0, 0.30),
    "claude-haiku-5-5": (0.10, 0.50, 0.01),
    "claude-haiku-4-5": (1.0, 5.0, 0.10),
    "claude-fable-5-2:fast": (16.0, 80.0, 0.40),
    "claude-mythos-5-2:fast": (16.0, 80.0, 0.40),
    "claude-opus-5-5:fast": (8.0, 40.0, 0.40),
    "claude-opus-5:fast": (10.0, 50.0, 1.00),
    "claude-opus-4-8:fast": (10.0, 50.0, 1.00),
    "gpt-6.1-sol": (2.0, 10.0, 0.10),
    "gpt-6.1-sol:fast": (4.0, 20.0, 0.20),
    "gpt-6-astra": (10.0, 50.0, 1.00),
    "gpt-6-astra:fast": (20.0, 100.0, 2.00),
}
LONG_PRICES = {"claude-haiku-5-5": (0.50, 2.50, 0.05),
               "gpt-6.1-sol": (4.0, 15.0, 0.20), "gpt-6.1-sol:fast": (8.0, 30.0, 0.40),
               "gpt-6-astra": (20.0, 75.0, 2.00), "gpt-6-astra:fast": (40.0, 150.0, 4.00)}
LONG_PROMPT = 100_000
LONG_AT = {m: 272_000 for m in LONG_PRICES if m.startswith("gpt-")}


UNKNOWN_TIER = ":tier-unknown"  # a Codex response whose speed tier nothing recorded (codex_row)


def estimate(model):
    """The price of a mode the vendor does not publish: a fast mode is twice its model's standard rate, the multiple
    both vendors publish for the fast modes they do list; a response of unknown tier is its model's standard rate.
    None when there is nothing near to estimate from."""
    if model.endswith(UNKNOWN_TIER):
        return PRICES.get(model[:-len(UNKNOWN_TIER)])
    base = PRICES.get(model[:-5]) if model.endswith(":fast") else None
    return tuple(2 * x for x in base) if base else None


# An estimated fast mode steps up for long prompts where its model does: the same doubling, on the long rate.
LONG_PRICES.update({f"{m}:fast": tuple(2 * x for x in p) for m, p in list(LONG_PRICES.items())
                    if not m.endswith(":fast") and f"{m}:fast" not in PRICES})
# An unknown tier steps up where its model's standard rate does, at the same threshold.
LONG_PRICES.update({m + UNKNOWN_TIER: p for m, p in list(LONG_PRICES.items()) if ":" not in m})
LONG_AT.update({m + UNKNOWN_TIER: n for m, n in list(LONG_AT.items()) if ":" not in m})


OVERRIDDEN = set()  # the models use_prices() priced from the pack's overrides
ALIASES = {}  # another model ID that means a model (the pack's aliases), and that model (use_prices, canon)
PRICE_KEYS = ("input", "output", "cacheRead")


def canon(m):
    """The model an ID is priced as: an alias's model, keeping the alias's :fast or unknown-tier mark; else the ID."""
    if not isinstance(m, str):
        return m
    if m in ALIASES:
        return ALIASES[m]
    for tail in (":fast", UNKNOWN_TIER):
        if m.endswith(tail) and m[:-len(tail)] in ALIASES:
            return ALIASES[m[:-len(tail)]] + tail
    return m


def display(m):
    """The display name a model ID has when the pack gives it none: one made from a built-in ID (claude-opus-5-5 is
    "Opus 5.5", gpt-6.1-sol is "GPT-6.1 Sol"), else the ID itself."""
    c = re.fullmatch(r"claude-([a-z]+)-(\d+(?:-\d+)?)", m)
    if c:
        return f"{c.group(1).capitalize()} {c.group(2).replace('-', '.')}"
    g = re.fullmatch(r"gpt-([\d.]+)-([a-z]+)", m)
    return f"GPT-{g.group(1)} {g.group(2).capitalize()}" if g else m


def write_rate(p):
    """The 5-minute cache write price of a row: its own fourth price, else 1.25 times its input price."""
    return p[3] if len(p) > 3 else p[0] * 1.25


def use_prices(prices):
    """The pack's model prices (its `prices`: {model: {input, output, cacheRead, cacheWrite, name, aliases}}, $ per
    million tokens) put over the table above, for card_costs and build. A model with the three prices (cacheWrite is
    optional: with none, a 5-minute cache write is 1.25 times input; a 1-hour one is always twice input) is priced at
    them: one the table has not got (an added model) as a built-in one. An override wins over the model's built-in
    row, over its fast mode (estimated at twice the override, unless the override names the :fast model itself) and
    over its long-prompt rate: it is one rate for every prompt size. An entry whose rates are not numbers of 0 or more
    prices nothing: its model keeps its built-in row, or stays unpriced. An OpenCode model (opencode:<provider>/<model>)
    with prices is priced at them, in place of the cost OpenCode reports (card_costs).
    name is the model's display name, which the Board shows over its own (display). aliases are other model IDs that mean the model (a proxy's or another
    provider's ID for it): a request or step with one is priced as the model (canon). An alias that is a model itself,
    priced by the table or named in the pack, is left out: an alias never re-prices a model."""
    num = lambda x: not isinstance(x, bool) and isinstance(x, (int, float)) and x >= 0
    entries = prices if isinstance(prices, dict) else {}
    for m, p in sorted(entries.items()):
        if not m or not isinstance(p, dict):
            continue
        rate, w = [p.get(k) for k in PRICE_KEYS], p.get("cacheWrite")
        if all(num(x) for x in rate) and (w is None or num(w)):
            PRICES[m] = tuple(rate) + (() if w is None else (w,))
            OVERRIDDEN.add(m)
        for a in p.get("aliases") if isinstance(p.get("aliases"), list) else []:
            if isinstance(a, str) and a and a != m:
                ALIASES.setdefault(a, m)
    for a in [a for a in ALIASES if a in PRICES or a in entries]:
        del ALIASES[a]
    for m in OVERRIDDEN:
        modes = [m] if ":" in m else [m, m + ":fast", m + UNKNOWN_TIER]
        for x in modes:
            if x not in OVERRIDDEN:
                PRICES.pop(x, None)
            if x == m or x not in OVERRIDDEN:
                LONG_PRICES.pop(x, None)
                LONG_AT.pop(x, None)


def estimated(row):
    """Whether this request, or an advisor call inside it, is priced by estimate()."""
    return any(canon(x[1]) not in PRICES and estimate(canon(x[1])) is not None for x in [row] + row[7:])


def price(row):
    m = canon(row[1])
    p = PRICES.get(m) or estimate(m)
    if p is None:
        # Every count present and 0 costs $0 at any price; a missing count is unknown, so it stays unpriced.
        return 0.0 if row[2:7] == [0, 0, 0, 0, 0] and not row[7:] else None
    # A count the usage lacks is unknown, not 0: the request is unpriced, for every model.
    if any(not isinstance(n, (int, float)) for n in row[2:7]):
        return None
    if m in LONG_PRICES and sum(row[2:6]) > LONG_AT.get(m, LONG_PROMPT):
        p = LONG_PRICES[m]
    inp, out, read = p[:3]
    i, w5, w1, r, o = row[2:7]
    # An advisor row with no price leaves the whole request unpriced: a partial total would read as complete.
    advisors = [price(a) for a in row[7:]]
    if None in advisors:
        return None
    return (i * inp + w5 * write_rate(p) + w1 * inp * 2 + r * read + o * out) / 1e6 + sum(advisors)


def lane_models(projects, worktree, since):
    """{model ID: the sessions that ran it} of the Claude Code sessions run in `worktree` (a research lane, whose
    sessions are no card's step) from `since` (epoch) on, read from their transcripts under `projects` (Claude Code's
    projects folder: one folder a working folder, its path with each other character than a letter or a digit as -,
    and subagents' transcripts below it). A session begun in a folder inside the worktree is filed under that folder's
    name, which starts with the worktree's name and a -, so each such folder is read too. A line counts only when its
    own cwd is the worktree or inside it, as two folders can share a name (and a name can start with another's).
    "<synthetic>" is no model: Claude Code writes it on a message no model answered. A file that cannot be read
    counts nothing."""
    if not isinstance(projects, str) or not isinstance(worktree, str) or not worktree.startswith("/") or since is None:
        return {}
    enc = re.sub(r"[^a-zA-Z0-9]", "-", worktree.rstrip("/"))
    try:
        dirs = [d for d in os.listdir(projects) if d == enc or d.startswith(enc + "-")]
    except OSError:
        return {}
    out = {}
    for root, _, files in (w for d in dirs for w in os.walk(os.path.join(projects, d))):
        for name in files:
            path = os.path.join(root, name)
            try:
                if not name.endswith(".jsonl") or os.stat(path).st_mtime < since:
                    continue
                with open(path, "rb") as f:
                    for line in f:
                        if b'"model"' not in line:
                            continue
                        try:
                            r = json.loads(line)
                        except ValueError:
                            continue
                        if not isinstance(r, dict):
                            continue
                        msg = r.get("message")
                        m = msg.get("model") if isinstance(msg, dict) else None
                        if r.get("type") != "assistant" or not isinstance(m, str) or m in ("", "<synthetic>") \
                                or (epoch(r.get("timestamp")) or 0) < since or not under(r.get("cwd"), [worktree]):
                            continue
                        out.setdefault(m, set()).add(r.get("sessionId") if isinstance(r.get("sessionId"), str) else path)
            except OSError:
                continue
    return {m: len(s) for m, s in out.items()}


def card_costs(part):
    """Conveyor's cards priced: each finished session (build, fix, rebase) and review (Codex too) at the list
    price of the model that ran it, from the token split its record line holds. A finished step is priced only at the
    model its own line names: a step whose line names none is unpriced, never priced at the model routing.json
    names now (after the builder moved from Fable to Opus, every earlier Fable session read at Opus rates). A running
    step's `live` names its model too; one that does not is running now, so it is priced at the card's `models` (the
    models in force), which is the model running it.

    A step's split is its whole session, not one request, so it is priced at the PRICES rate with no long-prompt
    step. A test run spends no tokens: it is $0 at any model. A step that cannot be priced has usd null and says why
    in `unpriced` (no model recorded, no price for its model, no token split recorded, its usage could not be read, a
    count that is not a number); its card's usd is then null too, never the sum of the priced part. The snapshot's
    totals sum the priced steps and count the ones left out.

    A card with a step running may hold `live`, that step's tokens so far: it is priced the same way into
    live.usd, and is no part of the card's usd, which stays the finished steps'.

    Each priced step names the model it was priced at (pricedAs), so the snapshot can sum the dollars by model.

    A session's result names the models that actually ran (stats.models) and each one's tokens (stats.byModel):
    those are what is priced, not the model the session was launched on (asked for Sonnet, ran Opus: Opus rates). One
    model that ran prices the step's split at that model; several price each one's own tokens at its own rate, and
    pricedAs is the one that cost most. The 1-hour cache writes are each model's own (byModel write1h, read from the
    answers each model gave); those no model's count accounts for go to the one model that wrote cache with no count
    of its own, and with more than one such model the step is unpriced: whose they were is not known.
    A model that ran with no price leaves the step unpriced, never priced at another model's rate.

    Each priced step also has pricedBy, {model: {usd, tokens}}: what each model that ran it cost and used, so the
    totals by model split a session that ran on two models between them.

    A step whose line says unread is unpriced even when it keeps a usage: that usage is only part of what
    the session used.

    A session OpenCode ran (model opencode:<provider>/<model>) is priced at the dollars OpenCode reported for it
    (usage.cost, the sum of its calls' costs): no list price here names its model, and none is guessed. One whose usage
    holds no cost (a call reported none) is unpriced. One whose model the pack prices, or names as an alias of a
    model, is priced at that price instead, from its token split.

    The part's `prices` (the pack's prices, added models and aliases) are put over the table first (use_prices), and
    taken out of the part; a step whose model is an alias is priced, and named (pricedAs, pricedBy), as the model it
    means. A step priced at a model an override prices has override: true. The part gets `table`, the built-in rows as
    they were before ({model: [input, output, cache read]}), and `names`, the display name each model of the table or
    the pack has when the pack gives it none (display), for the Rules tab's Model prices. With `since` (a time as the steps' lines write it), it
    gets `seen` too: each model ID the steps of that time or later ran ({model, sessions: how many steps, routes: the
    routes their lines name (proxy, subscription), as: the model it is priced as, null when none prices it}), the most
    used first. The part's `research` ({worktree, projects}: the research lane's folder and Claude Code's projects
    folder), taken out of the part, adds the model IDs its sessions ran from that time on (lane_models), one session
    each: they are no card's step, and an ID only they ran would never reach Seen but not priced.
    """
    def known(m):
        if not isinstance(m, str):
            return None
        for c in (m, re.sub(r"\[[^]]*\]$", "", m), re.sub(r"-\d{8}$", "", re.sub(r"\[[^]]*\]$", "", m))):
            if canon(c) in PRICES:
                return canon(c)
        return None

    def ran(step):
        st = step.get("stats") if isinstance(step.get("stats"), dict) else {}
        by = st.get("byModel")
        if isinstance(by, dict) and by:
            return by
        ms = st.get("models")
        if isinstance(ms, list) and len(ms) == 1 and isinstance(ms[0], str):
            return {ms[0]: None}
        return None

    def model(step, models):
        m = step.get("model")
        if not isinstance(m, str) and models is not None:
            m = models.get("codex" if step.get("step") == "review" else "claude")
        return m if isinstance(m, str) and m else None

    def nums(u, keys):
        n = [u.get(k, 0) for k in keys] if isinstance(u, dict) else None
        return None if n is None or any(isinstance(x, bool) or not isinstance(x, (int, float)) for x in n) else n

    def split(n, p):
        return (n[0] * p[0] + n[1] * write_rate(p) + n[2] * p[0] * 2 + n[3] * p[2] + n[4] * p[1]) / 1e6

    def usd(step, models):
        """(dollars, the model priced at, why it is unpriced, {model: {usd, tokens}}); dollars None when the step
        cannot be priced. models: the models in force, for a running step only (None for a finished one)."""
        u, r = step.get("usage"), ran(step) if step.get("step") != "review" else None
        if step.get("step") == "test":
            return 0, None, None, None
        if isinstance(step.get("unread"), str) and step["unread"]:
            return None, None, f"its token usage could not be read: {step['unread'][:200]}", None
        if u is None:
            return None, None, "no token split recorded (a step recorded before the split was)", None
        n = nums(u, ("input", "write", "write1h", "read", "output"))
        if n is None:
            return None, None, "a token count is not a number", None
        m = step.get("model")
        if isinstance(m, str) and m.startswith("opencode:") and known(m) is not None:
            k = known(m)
            d = round(split(n, PRICES[k]), 4)
            return d, k, None, {k: {"usd": d, "tokens": n[0] + n[1] + n[2] + n[4]}}
        if isinstance(m, str) and m.startswith("opencode:"):
            c = u.get("cost")
            if isinstance(c, bool) or not isinstance(c, (int, float)) or c < 0:
                return None, None, "OpenCode reported no cost for it", None
            d = round(c, 4)
            return d, m, None, {m: {"usd": d, "tokens": n[0] + n[1] + n[2] + n[4]}}
        if r is not None:
            bad = [m for m in r if known(m) is None]
            if bad:
                return None, None, f"no price for the model that ran it: {', '.join(str(m) for m in bad)}", None
            if len(r) == 1:
                m = known(next(iter(r)))
                d = round(split(n, PRICES[m]), 4)
                return d, m, None, {m: {"usd": d, "tokens": n[0] + n[1] + n[2] + n[4]}}
            parts, hours = {}, {}
            for m, mu in r.items():
                k = nums(mu, ("input", "write", "read", "output"))
                if k is None:
                    return None, None, f"a token count of {m} is not a number", None
                h = mu.get("write1h") if isinstance(mu, dict) else None
                if h is not None and (isinstance(h, bool) or not isinstance(h, (int, float)) or h < 0 or h > k[1]):
                    return None, None, f"the 1-hour cache writes of {m} are not a count within its cache writes", None
                if h is not None:
                    hours[known(m)] = hours.get(known(m), 0) + h
                parts[known(m)] = [a + b for a, b in zip(parts.get(known(m), [0, 0, 0, 0, 0]), [k[0], k[1], 0, k[2], k[3]])]
            rest = n[2] - sum(hours.values())
            if rest > 0:
                who = [m for m in parts if m not in hours and parts[m][1] > 0]
                if len(who) != 1:
                    return None, None, "its 1-hour cache writes cannot be put to the model that wrote them", None
                hours[who[0]] = rest
            for m, h in hours.items():
                h = min(h, parts[m][1])
                parts[m][1] -= h
                parts[m][2] += h
            cost = {m: split(k, PRICES[m]) for m, k in parts.items()}
            by = {m: {"usd": round(cost[m], 4), "tokens": k[0] + k[1] + k[2] + k[4]} for m, k in parts.items()}
            return round(sum(cost.values()), 4), max(cost, key=cost.get), None, by
        m = model(step, models)
        if m is None:
            return None, None, "no model recorded", None
        if known(m) is None:
            return None, None, f"no price for its model: {m}", None
        d = round(split(n, PRICES[known(m)]), 4)
        return d, known(m), None, {known(m): {"usd": d, "tokens": n[0] + n[1] + n[2] + n[4]}}

    table = {m: list(p) for m, p in PRICES.items()}
    pack = part.pop("prices", None)
    use_prices(pack)
    part["table"] = table
    part["names"] = {m: display(m) for m in [*table, *(pack if isinstance(pack, dict) else {})] if m}
    since, seen = part.pop("since", None), {}
    for card in part["cards"]:
        steps = [s for s in card.get("steps") or [] if isinstance(s, dict)]
        models = card.get("models") if isinstance(card.get("models"), dict) else {}
        for s in steps:
            if isinstance(since, str) and s.get("step") != "test" and isinstance(s.get("time"), str) and s["time"] >= since:
                for x in {x for x in ((s.get("step") != "review" and ran(s)) or [s.get("model")]) if isinstance(x, str) and x}:
                    k, ways = seen.get(x, (0, set()))
                    seen[x] = (k + 1, ways | ({s["route"]} if isinstance(s.get("route"), str) and s["route"] else set()))
            s["usd"], m, why, by = usd(s, None)
            s.pop("pricedAs", None)
            s.pop("pricedBy", None)
            s.pop("unpriced", None)
            if s["usd"] is not None and m is not None:
                s["pricedAs"] = m
            if s["usd"] is not None and by:
                s["pricedBy"] = by
            s.pop("override", None)
            if s["usd"] is not None and by and any(x in OVERRIDDEN for x in by):
                s["override"] = True
            if why:
                s["unpriced"] = why
        card["usd"] = None if any(s["usd"] is None for s in steps) else round(sum(s["usd"] for s in steps), 4)
        if isinstance(card.get("live"), dict):
            card["live"]["usd"] = usd(card["live"], models)[0]
    research = part.pop("research", None)
    if isinstance(since, str) and isinstance(research, dict):
        for x, n in lane_models(research.get("projects"), research.get("worktree"), epoch(since)).items():
            k, ways = seen.get(x, (0, set()))
            seen[x] = (k + n, ways)
    if isinstance(since, str):
        part["seen"] = [{"model": x, "sessions": k, "routes": sorted(ways), "as": known(x)}
                        for x, (k, ways) in sorted(seen.items(), key=lambda t: (-t[1][0], t[0]))]
    return part


def cost(rows, used, start, now):
    """List-price equivalent of this host's requests in the week, and what it projects to.

    perHour is the 100% projection spread over the 168-hour week, as the design
    pairs it with that tile. Requests that exist but none of which can be priced
    leave every dollar figure null: $0 would claim a price source there is not.
    """
    # Today runs from host-local midnight. Rows before the week start were never
    # loaded, so a day that began earlier has no total; nor do rows none of which price.
    midnight = datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    day = [r for r in rows if r[0] >= midnight]
    day_priced = [c for c in map(price, day) if c is not None]
    today = None if midnight < start or (day and not day_priced) else sum(day_priced)
    priced = [c for c in map(price, rows) if c is not None]
    if rows and not priced:
        return {"week": None, "today": today, "perHour": None, "projected": None, "perPoint": None, "unpricedRequests": len(rows)}
    week = sum(priced)
    projected = week / used * 100 if used > 0 else None
    return {"week": week, "today": today, "perHour": projected / (WEEK / 3600) if projected is not None else None,
            "projected": projected, "perPoint": week / used if used > 0 else None,
            "unpricedRequests": len(rows) - len(priced)}


def under(folder, roots):
    """Whether a session's working folder is one of `roots` or inside one; no roots is every session."""
    return not roots or (isinstance(folder, str) and any(folder == r or folder.startswith(r.rstrip("/") + "/") for r in roots))


def covered(held, since, now):
    """When a request cache's rows start being whole after a call from `since` at `now`.

    A call reads every file written since `since`, so it holds every request from then on. It extends the
    cache's earlier coverage `held` ([from, to], the last call's) only when it starts no later than that call
    ended: one starting later skips, unread, any file last written in between. Rows older than two weeks are
    dropped. stages() trusts a build's cost only from here on.
    """
    a, b = held if isinstance(held, list) and len(held) == 2 else (None, None)
    whole = all(isinstance(x, (int, float)) for x in (a, b)) and since <= b
    return [max(min(a, since) if whole else since, now - 2 * WEEK), now]


def gone(p):
    """True only when `p` is not there; lexists() also says False when a parent cannot be searched, which hid an unread path."""
    try:
        os.lstat(p)
    except FileNotFoundError:
        return True
    except OSError:
        return False
    return False


def reuses(cache, since, now):
    """Whether a request cache written by an earlier call of this same cycle (`now` is the cycle's stamp) already
    holds every request from `since` on: whole, and covering back that far. The limit card and the day's cost call
    with one `now`, so only the first of a cycle reads the files."""
    held = cache.get("covered")
    return cache.get("cycle") == now and cache.get("complete") is True and isinstance(held, list) and len(held) == 2 \
        and isinstance(held[0], (int, float)) and held[0] <= since


def requests(projects, cache_path, since, now, roots=None):
    """Each distinct API request's row from Claude Code's transcripts (subagents included) since `since`.

    A week of transcripts runs to gigabytes, so each file is read once from the
    byte offset the last call stopped at; the cache keeps every request's row,
    and the working folder its session ran in. With `roots`, only the requests
    of sessions run in those folders are returned: one project's own.
    """
    if not os.path.isdir(projects):
        return None
    try:
        with open(cache_path) as f:
            cache = json.load(f)
        offsets, seen, where, sess, side = cache["offsets"], cache["requests"], cache["cwd"], cache["session"], cache["side"]
        # Version 5 also keeps requests logged without a requestId, version 6 each request's session,
        # version 7 whether it was a sidechain's, version 8 a line with neither requestId nor message id (counted
        # under its own uuid, which version 7 skipped at an offset it never reads again); an older cache is read again.
        if cache.get("version") != 8 or not all(isinstance(v, list) for v in seen.values()) or not isinstance(where, dict) \
                or not isinstance(sess, dict) or not isinstance(side, dict):
            raise ValueError("cache from before requests kept their working folder, session and sidechain flag")
        missing, held = set(cache.get("unread", [])), cache.get("covered")
        if reuses(cache, since, now):
            return [v for k, v in seen.items() if since <= v[0] <= now and under(where.get(k), roots)]
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        offsets, seen, where, sess, side, missing, held = {}, {}, {}, {}, {}, set(), None
    # A file or folder deleted since it was listed is gone, and its cached rows stay. One that is there
    # and cannot be read leaves the totals unknown: a smaller number would read as measured.
    # `missing` carries such paths across calls until one reads them: a later call from a later `since`
    # skips an older file unread, and must not call the cache complete while its rows are still lost.
    live, unread = {}, []

    def lost(e):
        if not isinstance(e, FileNotFoundError):
            unread.append(e)
            missing.add(e.filename)
    recovered = set()  # folders unread before and listed now: their files older than `since` are still unread
    for root, _, files in os.walk(projects, onerror=lost):
        if root in missing or os.path.dirname(root) in recovered:
            recovered.add(root)
        missing.discard(root)
        for name in files:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(root, name)
            off = offsets.get(path, 0)
            try:
                st = os.stat(path)
                if st.st_mtime < since:
                    if root in recovered:
                        missing.add(path)
                    if path in offsets:
                        live[path] = off  # skipped, not forgotten: a later call from an earlier `since` must not read it from zero
                    continue
                if st.st_size < off:
                    off = 0  # rewritten in place: request ids are keys, so a re-read never double counts
                # Line by line: the Linux service caps the collector at 256 MB.
                with open(path, "rb") as f:
                    f.seek(off)
                    for line in f:
                        if not line.endswith(b"\n"):
                            break  # a half-written last line waits for the next call
                        off += len(line)
                        if b'"usage"' not in line:
                            continue
                        try:
                            r = json.loads(line)
                        except ValueError:
                            continue
                        row = request_row(r) if isinstance(r, dict) else None
                        if row:
                            seen[request_key(r)] = row  # a streamed request's last line carries its final usage
                            where[request_key(r)], sess[request_key(r)] = r.get("cwd"), r.get("sessionId")
                            side[request_key(r)] = r.get("isSidechain") is True
                missing.discard(path)
            except FileNotFoundError:
                missing.discard(path)
                continue
            except OSError as e:
                lost(e)
            live[path] = off
    seen = {k: v for k, v in seen.items() if v[0] >= now - 2 * WEEK}
    missing = {p for p in missing if not gone(p)}  # gone since: it spent nothing unseen
    tmp = f"{cache_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        # json.dumps, not json.dump: same text through the C encoder. This file reaches 50 MB.
        f.write(json.dumps({"version": 8, "offsets": live, "requests": seen, "cwd": {k: where.get(k) for k in seen},
                            "session": {k: sess.get(k) for k in seen}, "side": {k: side.get(k, False) for k in seen},
                            "unread": sorted(missing), "complete": not missing, "covered": covered(held, since, now), "cycle": now}))
    os.replace(tmp, cache_path)
    if unread:
        print(f"dashboard_limit: {len(unread)} transcript path(s) could not be read, so requests and cost are unknown: {unread[0]}", file=sys.stderr)
        return None
    return [v for k, v in seen.items() if since <= v[0] <= now and under(where.get(k), roots)]


CODEX_TAIL = 262144  # a session file is read 256 KB at a time from its end: token_count events are frequent


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _codex_last(f, now):
    """The last 7-day reading in f not past its reset, or None.

    Read backward CODEX_TAIL bytes at a time, each byte once: one read when the
    tail holds a reading, the windows before it only on a miss.
    """
    stop = f.seek(0, os.SEEK_END)
    carry = b""  # the cut start of the window after this one: the end of this window's last line
    while stop > 0:
        start = max(0, stop - CODEX_TAIL)
        f.seek(start)
        lines = (f.read(stop - start) + carry).split(b"\n")
        carry = lines.pop(0) if start > 0 else b""
        for line in reversed(lines):
            if b'"rate_limits"' not in line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            p = r.get("payload") if isinstance(r, dict) else None
            p = p.get("rate_limits") if isinstance(p, dict) else None
            p = p.get("primary") if isinstance(p, dict) else None
            # A reading past its reset is no reading (pace() nulls it): the search goes on.
            if isinstance(p, dict) and p.get("window_minutes") == 10080 and _num(p.get("used_percent")) \
                    and _num(p.get("resets_at")) and p["resets_at"] > now:
                return (p["used_percent"], p["resets_at"], epoch(r.get("timestamp")))
        stop = start
    return None


def codex(sessions_dir, now):
    """Codex's own 7-day reading: the last `rate_limits.primary` with a 10080-minute window.

    Newest session files first, each read backward from its end until a reading
    is found. Every key is None with no reading or past its
    reset (as pace() does), never 0. The reading is only as fresh as Codex's last
    call, so readAt is the event's own time.
    """
    out = dict(pace(None, None, now), windowStart=None, resetsAt=None, readAt=None)
    if not sessions_dir or not os.path.isdir(sessions_dir):
        return out
    # As in requests(): a deleted path is gone, one that cannot be read may hold the newest reading.
    files, unread = [], []
    for root, _, names in os.walk(sessions_dir, onerror=lambda e: isinstance(e, FileNotFoundError) or unread.append(e)):
        for n in names:
            if n.endswith(".jsonl"):
                p = os.path.join(root, n)
                try:
                    files.append((os.stat(p).st_mtime, p))
                except FileNotFoundError:
                    pass
                except OSError as e:
                    unread.append(e)
    best = None
    for i, (mtime, path) in enumerate(sorted(files, reverse=True)):
        # Past the ten newest, only a file modified inside the window can hold a reading not yet reset.
        if i >= 10 and mtime < now - WEEK:
            break
        # The newest reading by its own time wins: a resumed old session has the newest file and
        # an old reading. A file not written since the best reading cannot hold a newer one.
        if best and (best[2] is None or mtime < best[2]):
            break
        try:
            with open(path, "rb") as f:
                got = _codex_last(f, now)
        except FileNotFoundError:
            continue
        except OSError as e:
            unread.append(e)
            continue
        if got and (best is None or (got[2] is not None and got[2] > best[2])):
            best = got
    if unread:
        print(f"dashboard_limit: {len(unread)} Codex session path(s) could not be read, so the Codex reading is unknown: {unread[0]}", file=sys.stderr)
    elif best:
        used, reset, at = best
        out = pace(used, reset, now)
        live = out["usedPct"] is not None
        out.update(windowStart=iso(reset - WEEK) if live else None, resetsAt=iso(reset) if live else None,
                   readAt=iso(at) if live and at is not None else None)
    return out


def codex_subscription(sessions_dir):
    """False only on positive proof of no subscription window here: no sessions, no login file, or an API-key login. True for any other readable login, None when unreadable.

    Only False hides the 7-day tiles: a login that cannot be classified still shows "not measured".
    A keyring login leaves no auth.json, so config.toml naming keyring or auto storage makes it unknown, not absent.
    """
    if not sessions_dir:
        return False
    try:
        if not stat.S_ISDIR(os.stat(sessions_dir).st_mode):
            return False
    except (FileNotFoundError, NotADirectoryError):
        return False
    except OSError:
        return None
    home = os.path.dirname(os.path.abspath(sessions_dir))
    try:
        with open(os.path.join(home, "auth.json")) as f:
            a = json.load(f)
    except FileNotFoundError:
        try:
            import tomllib  # 3.11+; on the Mac's system python3 (3.9) the login type stays unknown
            with open(os.path.join(home, "config.toml"), "rb") as f:
                cfg = tomllib.load(f)
        except FileNotFoundError:
            return False
        except (ImportError, OSError, ValueError):
            return None
        return None if cfg.get("cli_auth_credentials_store") in ("keyring", "auto") else False
    except (OSError, ValueError):
        return None
    if not isinstance(a, dict):
        return None
    # Only a file that positively says API key hides the tiles; an omitted or unknown auth_mode is a subscription.
    return not (a.get("auth_mode") == "apikey" or (a.get("OPENAI_API_KEY") and not a.get("tokens")))


def codex_history(cache_dir, cx, now):
    """Codex's readings over the week, stored like Claude's (one row per reading, by the reading's own time).

    None with no live reading: a past week's samples are not this week's line.
    """
    path = os.path.join(cache_dir, "codex-limit-history.jsonl")
    start, at = epoch(cx.get("windowStart")), epoch(cx.get("readAt"))
    if cx.get("usedPct") is None or start is None:
        return None
    rows = record(path, int(at), cx["usedPct"], now) if at is not None else read_history(path)
    return [{"at": iso(a), "pct": p} for a, p in rows if start <= a <= now]


def billing(cache_dir):
    """("subscription" | "api", weekly limit in dollars or None), from billing.json beside the cache folder.

    The file is {"billing": "api", "weeklyLimitUsd": 1000}. Anything else, or no file, is the subscription panel.
    """
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(cache_dir)), "billing.json")) as f:
            b = json.load(f)
    except (OSError, ValueError):
        return "subscription", None
    if not isinstance(b, dict) or b.get("billing") != "api":
        return "subscription", None
    lim = b.get("weeklyLimitUsd")
    return "api", lim if _num(lim) and lim > 0 else None


def codex_row(r, model, tier):
    """One Codex `token_usage_record` as a request_row-shaped row, or None when it cannot be used.

    The one reading of a Codex response for a price: codex_requests() below and the build review
    (collect.py) both use it, so the two cannot price the same response differently.
    """
    p = r.get("payload") if isinstance(r.get("payload"), dict) else {}
    if not isinstance(p.get("usage"), dict) or not isinstance(p.get("response_id"), str) or epoch(r.get("timestamp")) is None:
        return None
    n = lambda d, k: d.get(k) if isinstance(d.get(k), int) else None
    u = p["usage"]
    inp, read, write = n(u, "input_tokens"), n(u, "cached_input_tokens"), n(u, "cache_write_input_tokens")
    # The one tier mapping: nothing recorded is unknown (priced at standard, and estimated); the Codex log says
    # "default" and "priority", and "standard" and "fast" mean the same two; any other name stays in the model name, priced
    # only if listed.
    mode = UNKNOWN_TIER if tier is None else "" if tier in ("default", "standard") else ":fast" if tier in ("priority", "fast") else f":{tier}"
    return [epoch(r["timestamp"]), f"{model or 'unknown Codex model'}{mode}",
            None if inp is None else max(0, inp - (read or 0) - (write or 0)), write, 0, read, n(u, "output_tokens")]


def codex_requests(sessions_dirs, cache_path, since, now, missed=None, roots=None):
    """Each Codex response's row, in request_row's shape, from the session files since `since`.

    A `token_usage_record` holds one response's counts. Its input count includes the cached and
    cache-written tokens, so the row's input is what is left. The model is the file's last `turn_context`
    or `thread_settings_applied`; the speed tier is logged only by the latter ("priority" is the vendor's
    fast mode), and a file that never logs one has no tier. Both are kept per file beside the byte offset, so a later call that starts past them still
    knows them, as is the working folder the file's `session_meta` names, which `roots` filters on as in
    requests(). The walk and the cache are requests()'s, with that state added. Every folder in
    `sessions_dirs` is walked: a review session may run with its own CODEX_HOME.

    A file or folder that cannot be opened is appended to `missed`: what it spent is unknown, so the caller
    must not call the week complete. One that has gone since it was listed spent nothing unseen.
    """
    missed = [] if missed is None else missed
    def absent(d):  # only a folder that is not there is skipped: one that cannot be searched is walked, so onerror reports it
        try:
            os.stat(d)
        except FileNotFoundError:
            return True
        except OSError:
            return False
        return False
    sessions_dirs = [d for d in sessions_dirs if d and not absent(d)]
    if not sessions_dirs:
        return None
    try:
        with open(cache_path) as f:
            cache = json.load(f)
        files, seen, where, sess = cache["files"], cache["requests"], cache["cwd"], cache["session"]
        # Version 6 prices an untiered response as unknown; a version-5 cache priced it as
        # standard and would never re-read it, so it is read again.
        if cache.get("version") != 6 or not all(isinstance(x, dict) for x in (files, seen, where, sess)):
            raise ValueError("not this reader's cache")
        missing, held = set(cache.get("unread", [])), cache.get("covered")
        if reuses(cache, since, now):
            return [v for k, v in seen.items() if since <= v[0] <= now and under(where.get(k), roots)]
    except (OSError, ValueError, KeyError, TypeError):
        files, seen, where, sess, missing, held = {}, {}, {}, {}, set(), None
    live = {}

    def lost(e):  # requests()'s `missing`: kept across calls until a read clears it
        if not isinstance(e, FileNotFoundError):
            missed.append(e.filename)
            missing.add(e.filename)
    recovered = set()  # as in requests()
    for root, _, names in (w for d in sessions_dirs for w in os.walk(d, onerror=lost)):
        if root in missing or os.path.dirname(root) in recovered:
            recovered.add(root)
        missing.discard(root)
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(root, name)
            try:
                st = os.stat(path)
                if st.st_mtime < since:
                    if root in recovered:
                        missing.add(path)
                    if path in files:
                        live[path] = files[path]  # as in requests(): skipped, not forgotten
                    continue
                f = open(path, "rb")
            except OSError as e:
                lost(e)
                if isinstance(e, FileNotFoundError):
                    missing.discard(path)
                continue
            off, model, tier, cwd = files.get(path) or (0, None, None, None)
            if st.st_size < off:
                off, model, tier, cwd = 0, None, None, None  # rewritten in place: response ids are keys, so a re-read never double counts
            with f:
                f.seek(off)
                for line in f:
                    if not line.endswith(b"\n"):
                        break  # a half-written last line waits for the next call
                    off += len(line)
                    if not any(t in line for t in (b'"token_usage_record"', b'"turn_context"', b'"thread_settings_applied"', b'"session_meta"')):
                        continue
                    try:
                        r = json.loads(line)
                    except ValueError:
                        r = None
                    if not isinstance(r, dict):
                        r = {"type": "token_usage_record"} if b'"token_usage_record"' in line else {}
                    p = r.get("payload") if isinstance(r.get("payload"), dict) else {}
                    s = p.get("thread_settings") if p.get("type") == "thread_settings_applied" else None
                    if r.get("type") == "session_meta":
                        cwd = p.get("cwd") if isinstance(p.get("cwd"), str) else cwd
                    elif isinstance(s, dict):
                        # A change in the log wins from this line on; a line that names no tier leaves it as it was.
                        model = s.get("model") if isinstance(s.get("model"), str) else model
                        tier = s["service_tier"] if isinstance(s.get("service_tier"), str) else tier
                    elif r.get("type") == "turn_context" and isinstance(p.get("model"), str):
                        model = p["model"]
                    elif r.get("type") == "token_usage_record" and codex_row(r, model, tier):
                        seen[p["response_id"]] = codex_row(r, model, tier)
                        where[p["response_id"]], sess[p["response_id"]] = cwd, name[:-6]
                    elif r.get("type") == "token_usage_record":
                        # Never dropped: a usage line this reader cannot use is spend of unknown size, kept as a
                        # request with no counts so the week reads it as unpriced. Keyed by where it sits in the file.
                        at = epoch(r.get("timestamp"))
                        seen[f"unreadable:{path}:{off}"] = [min(int(st.st_mtime), now) if at is None else at,
                                                            "unreadable Codex record", None, None, 0, None, None]
                        where[f"unreadable:{path}:{off}"], sess[f"unreadable:{path}:{off}"] = cwd, name[:-6]
            missing.discard(path)
            live[path] = [off, model, tier, cwd]
    seen = {k: v for k, v in seen.items() if v[0] >= now - 2 * WEEK}
    missing = {p for p in missing if not gone(p)}  # gone since: it spent nothing unseen
    tmp = f"{cache_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        f.write(json.dumps({"version": 6, "files": live, "requests": seen, "cwd": {k: where.get(k) for k in seen},
                            "session": {k: sess.get(k) for k in seen},
                            "unread": sorted(missing), "complete": not missing, "covered": covered(held, since, now), "cycle": now}))
    os.replace(tmp, cache_path)
    return [v for k, v in seen.items() if since <= v[0] <= now and under(where.get(k), roots)]


def api_week(limit, rows, now, codex_rows=None, codex_partial=False, since=None):
    """Dollars against the weekly limit for a machine that pays by API.

    The week starts Monday 00:00 host-local. Spend is the PRICES table over this host's Claude and Codex
    requests together; with no Codex session folder (codex_rows None) its share is not measured and the
    total is Claude's alone. With no limit there is no goal or pace. `since` starts the window later than
    Monday: build() passes midnight for the day's spend, so the day and the week are priced by one sum.
    """
    d = datetime.fromtimestamp(now)
    mon = (d - timedelta(days=d.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    start, end = mon.timestamp() if since is None else since, (mon + timedelta(days=7)).timestamp()
    out = {"limitUsd": limit, "spentUsd": None, "goalUsd": None, "underUsd": None, "paceSec": None,
           "timeLeftSec": round(end - now), "windowStart": iso(start), "resetsAt": iso(end),
           "requests": None, "unpricedRequests": None, "history": None,
           "claudeUsd": None, "codexUsd": None, "estimatedUsd": None, "unpricedModels": None, "complete": False}
    if rows is None and codex_rows is None:
        return out
    week = sorted(((r, cx) for rs, cx in ((rows or [], False), (codex_rows or [], True)) for r in rs if start <= r[0] <= now),
                  key=lambda t: t[0][0])
    costs = [(r, cx, price(r)) for r, cx in week]
    priced = [(r[0], c) for r, _, c in costs if c is not None]
    # Complete means the total can be trusted as the whole spend: both providers read, every Codex session
    # opened (codex_partial is codex_requests' missed list, non-empty), and nothing unpriced.
    out.update(requests=len(week), unpricedRequests=len(week) - len(priced),
               complete=rows is not None and codex_rows is not None and not codex_partial and len(week) == len(priced),
               unpricedModels=sorted({x[1] for r, _, c in costs if c is None for x in [r] + r[7:]
                                      if canon(x[1]) not in PRICES and estimate(canon(x[1])) is None}))
    if week and not priced:
        return out
    spent, hist = 0.0, []
    for at, c in priced:
        spent += c
        # One point per hour: the running total at that hour's last request.
        if hist and int(hist[-1][0] // 3600) == int(at // 3600):
            hist.pop()
        hist.append((at, spent))

    def share(read, cx):
        # A provider not read, or with requests none of which price, has no dollar figure: $0 would claim one.
        mine = [c for _, x, c in costs if x == cx]
        return None if read is None or (mine and all(c is None for c in mine)) else sum(c for c in mine if c is not None)

    out.update(spentUsd=spent, history=[{"at": iso(a), "usd": u} for a, u in hist + [(now, spent)]],
               claudeUsd=share(rows, False), codexUsd=share(codex_rows, True),
               estimatedUsd=sum(c for r, _, c in costs if c is not None and estimated(r)))
    if limit is not None:
        goal = limit * (now - start) / (end - start)
        out.update(goalUsd=round(goal, 2), underUsd=round(goal - spent, 2), paceSec=round((goal - spent) / limit * (end - start)))
    return out


def cache_write_pct(rows, now):
    """Share of the last 24 h's input tokens (new + cache write + cache read) written to cache, in percent.

    A request with any of those four counts unknown is left out of both sides,
    never read as 0; with no fully known request in the day the share is None.
    """
    if rows is None:
        return None
    day = [r for r in model_calls(rows) if r[0] >= now - 86400 and None not in (r[2], r[3], r[4], r[5])]
    writes = sum(r[3] + r[4] for r in day)
    total = writes + sum(r[2] + r[5] for r in day)
    return writes * 100 / total if total > 0 else None


def codex_sources(sessions):
    """The Codex session folders that build reads.

    Review panes run with CODEX_HOME=~/.codex-review; a test points CONVEYOR_CODEX_REVIEW_HOME at a temp folder so it
    never reads real spend. With no Codex folder at all, Codex spend stays not measured."""
    review = os.environ.get("CONVEYOR_CODEX_REVIEW_HOME") or os.path.expanduser("~/.codex-review")
    return [sessions, os.path.join(review, "sessions")] if sessions else []


def build(status, usage_path, now, cache_dir, projects, sessions=None, roots=None):
    usage = None
    if status in ("fresh", "stale"):
        try:
            with open(usage_path) as f:
                usage = json.load(f)
        except (OSError, ValueError):
            usage = None
    seven = (usage or {}).get("seven_day") or {}
    five = (usage or {}).get("five_hour") or {}
    # The account the reading was made for (fetch() writes it); history is kept and drawn per account.
    account = (usage or {}).get("account")
    account = {"folder": account.get("folder"), "email": account.get("email")} if isinstance(account, dict) and isinstance(account.get("folder"), str) else None
    folder = account["folder"] if account else None
    used = seven.get("utilization") if isinstance(seven.get("utilization"), (int, float)) else None
    reset = epoch(seven.get("resets_at"))
    out = pace(used, reset, now)
    live = out["usedPct"] is not None
    start = reset - WEEK if live else None
    hist_path = os.path.join(cache_dir, "limit-history.jsonl")
    if live:
        # The sample time is the reading's own (its cache file's), so a reused copy never re-records.
        # Whole seconds: the row stores whole-second ISO, and the duplicate check compares against it.
        rows = record(hist_path, min(int(os.stat(usage_path).st_mtime), now), used, now, folder)
    else:
        rows = read_history(hist_path, folder)
    # The cache write share is a rolling 24 h, so the first day after a reset reads back before the window start.
    since = min(start, now - 86400) if live else None
    loaded = requests(projects, os.path.join(cache_dir, "limit-requests.json"), since, now) if live else None
    reqs = [r for r in loaded if r[0] >= start] if loaded is not None else None
    five_reset = epoch(five.get("resets_at"))
    five_used = five.get("utilization") if isinstance(five.get("utilization"), (int, float)) else None
    out.update({
        "account": account,
        # When the figures were read: the usage file's own time (dashboard.sh's cached() replaces it only on a read that worked).
        "readAt": iso(int(os.stat(usage_path).st_mtime)) if live else None,
        "windowStart": iso(start) if live else None,
        "resetsAt": iso(reset) if live else None,
        "fiveHour": {"start": iso(five_reset - FIVE_HOURS), "end": iso(five_reset), "usedPct": five_used}
        if live and five_reset is not None and five_reset > now else None,
        "history": [{"at": iso(a), "pct": p} for a, p in rows if live and start <= a <= now],
        "requests": len(reqs) if reqs is not None else None,
        "cost": cost(reqs, used, start, now) if reqs is not None else None,
        "cacheWritePct24h": cache_write_pct(loaded, now),
        "codex": codex(sessions, now),
    })
    out["codex"]["subscription"] = codex_subscription(sessions)
    out["codex"]["history"] = codex_history(cache_dir, out["codex"], now)
    # The subscription keys above are the same in both modes; API mode adds its own block beside them.
    mode, limit = billing(cache_dir)
    out["billing"] = mode
    out["api"] = None
    missed = []
    codex_dirs = codex_sources(sessions)
    if mode == "api":
        monday = epoch(api_week(None, None, now)["windowStart"])
        codex_rows = codex_requests(codex_dirs, os.path.join(cache_dir, "codex-requests.json"), monday, now, missed)
        api_rows = requests(projects, os.path.join(cache_dir, "limit-requests.json"), min(monday, now - 86400), now)
        out["api"] = api_week(limit, api_rows, now, codex_rows, bool(missed))
        # With no subscription reading nothing above loaded the requests, and cache writes still cost dollars here.
        if out["cacheWritePct24h"] is None:
            out["cacheWritePct24h"] = cache_write_pct(api_rows, now)
    # The day's cost for the top strip: both providers since host-local midnight, in either billing mode. Unlike
    # every figure above, which is the account's, it counts only the sessions run in `roots`: one project's own.
    # Read from midnight itself, which is over 24 h back on the day the clocks go back.
    # The project's closing review copies are its own sessions too.
    roots = [*roots, closing_root()] if roots else roots
    midnight = datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    lost = []
    today = api_week(None, requests(projects, os.path.join(cache_dir, "limit-requests.json"), midnight, now, roots), now,
                     codex_requests(codex_dirs, os.path.join(cache_dir, "codex-requests.json"), midnight, now, lost, roots),
                     bool(lost), midnight)
    out["today"] = {k: today[k] for k in ("windowStart", "spentUsd", "claudeUsd", "codexUsd", "estimatedUsd", "requests",
                                        "unpricedRequests", "unpricedModels", "complete")}
    json.dump(out, sys.stdout)
    return 0


def model_calls(rows):
    """Each request row and the advisor calls inside it (request_row), as rows of their own."""
    return [x for r in rows for x in [r] + r[7:]]


def main(argv):
    if argv[1:2] == ["fetch"] and len(argv) <= 4:
        return fetch(argv[2] if len(argv) >= 3 else None, argv[3] if len(argv) == 4 else None)
    if len(argv) in (3, 4) and argv[1] == "accounts":
        json.dump(accounts(argv[2], time.time(), argv[3] if len(argv) == 4 else None), sys.stdout)
        return 0
    if argv[1:] == ["account"]:
        json.dump(active_folder(), sys.stdout)
        return 0
    if len(argv) == 2 and argv[1] == "cards":
        json.dump(card_costs(json.load(sys.stdin)), sys.stdout)
        return 0
    if len(argv) >= 7 and argv[1] == "build":
        try:
            use_prices(json.loads(os.environ.get("PP_PRICES") or "{}"))
        except ValueError:
            pass  # overrides that do not read are none: the built-in table prices every request
        return build(argv[2], argv[3], float(argv[4]), argv[5], argv[6], argv[7] if len(argv) > 7 else None, argv[8:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
