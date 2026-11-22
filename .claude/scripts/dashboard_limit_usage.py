# SPDX-License-Identifier: Apache-2.0
# A part of dashboard_limit.py, run in its namespace (run_part()), not a module of its own: the times, the Claude
# accounts and their usage readings, the usage history and the transcripts' request rows.
import math  # dashboard_limit.py imports both; named here so a linter reading this file alone finds them
import sys


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
    # account switched to or from was asked again at once. Each read here is kept there too. A 429 is honoured until
    # its kept `next`, one with no (or a malformed) Retry-After too (note() keeps ACCOUNT_TTL for it). Any other failed
    # read (a network error, no login token) is not: it says nothing of the endpoint's wait, and honoured it kept the
    # guard's fresh read after a card lands, and the Foreman's watcher's polls, from asking once the cause was gone.
    if cache_dir:
        now = time.time()
        cache, kept = account_cache(cache_dir, account["folder"])
        err = kept.get("error") if isinstance(kept.get("error"), str) else ""
        if err.startswith(RATE_LIMITED) and isinstance(kept.get("next"), (int, float)) and now < kept["next"]:
            err = re.sub(r"; retry after [0-9]+ s$", "", err)
            # Rounded down, never to 0 (dashboard.sh reads 0 as no wait named): cached() adds it to NOW, the whole
            # second the collect began in, so the kept retry-at is never past the deadline's own second.
            print(f"{err}; retry after {max(1, math.floor(kept['next'] - now))} s", file=sys.stderr)
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
            why = RATE_LIMITED
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
    """Writes one read of the account (usage()'s answer) over `kept` into `cache`, as account_reading() keeps it.
    The file is read again under its lock first: readers of one account (the Board, the guard, the watcher) can ask
    at once, and a 429 another one saved while this read was out keeps its later deadline and reason, whatever this
    read got. Written over, that 429's wait was lost and the account asked again inside it."""
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    with open(cache + ".lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(cache) as f:
                held = json.load(f)
            kept = held if isinstance(held, dict) else kept
        except (OSError, ValueError):
            pass
        if body is not None:
            new = {"at": now, "next": now + ACCOUNT_TTL, "body": body, "bodyAt": now, "error": None}
        else:
            wait = re.search(r"retry after ([0-9]+) s", why)
            new = {"at": now, "next": now + max(ACCOUNT_TTL, int(wait.group(1)) if wait else 0),
                   "body": kept.get("body") if isinstance(kept.get("body"), dict) else None,
                   "bodyAt": kept.get("bodyAt") if isinstance(kept.get("bodyAt"), (int, float)) else None, "error": why}
        err, nxt = kept.get("error"), kept.get("next")
        if isinstance(err, str) and err.startswith(RATE_LIMITED) and isinstance(nxt, (int, float)) and nxt > new["next"]:
            new.update(next=nxt, error=err)
        tmp = "%s.%d" % (cache, os.getpid())
        with open(tmp, "w") as f:
            json.dump(new, f)
        os.replace(tmp, cache)
    return new


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
