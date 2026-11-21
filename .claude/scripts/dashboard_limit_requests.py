# SPDX-License-Identifier: Apache-2.0
# A part of dashboard_limit.py, run in its namespace (run_part()), not a module of its own: the requests of Claude
# Code's and Codex's transcripts, Codex's own reading and history, the billing, the API week and the cache writes.


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


def requests(projects, cache_path, since, now, roots=None, places=None):
    """Each distinct API request's row from Claude Code's transcripts (subagents included) since `since`.

    A week of transcripts runs to gigabytes, so each file is read once from the
    byte offset the last call stopped at; the cache keeps every request's row,
    and the working folder its session ran in. With `roots`, only the requests
    of sessions run in those folders are returned: one project's own. A list
    given as `places` is filled with each returned row's (working folder,
    session id), in the same order.
    """
    def picked(seen, where, sess):
        keys = [k for k, v in seen.items() if since <= v[0] <= now and under(where.get(k), roots)]
        if places is not None:
            places[:] = [(where.get(k), sess.get(k)) for k in keys]
        return [seen[k] for k in keys]
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
            return picked(seen, where, sess)
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
    return picked(seen, where, sess)


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


def cache_day(rows, now):
    """The last 24 h's requests (advisor calls too) whose input, cache write and cache read counts are all known."""
    return [r for r in model_calls(rows) if r[0] >= now - 86400 and None not in (r[2], r[3], r[4], r[5])]


def cache_write_pct(rows, now):
    """Share of the last 24 h's input tokens (new + cache write + cache read) written to cache, in percent.

    A request with any of those four counts unknown is left out of both sides,
    never read as 0; with no fully known request in the day the share is None.
    """
    if rows is None:
        return None
    day = cache_day(rows, now)
    writes = sum(r[3] + r[4] for r in day)
    total = writes + sum(r[2] + r[5] for r in day)
    return writes * 100 / total if total > 0 else None


# An issue's card ends in its issue number, a main-red fix card (which has no issue) in -0.
CARD_DIR = re.compile(r"c[0-9]{8}T[0-9]{6}-.+-(0|[1-9][0-9]{0,8})")


def card_of(folder):
    """The card id of a session's working folder: its last part named as a card's worktree is (<cards>/<card id>)."""
    return next((p for p in reversed(folder.split("/")) if CARD_DIR.fullmatch(p)), None) if isinstance(folder, str) else None


def cache_writes(rows, now, places=None):
    """The cache write tokens of the requests cache_write_pct counts, {write: 5-minute, write1h: 1-hour, cards}; None
    with no rows. cards: those of them made in a card's worktree (places, requests()'s, gives each row's folder and
    session), a row each card, session and model that wrote cache: {card, model, first, last (its requests' times),
    write, write1h}, the most written first. Each is counted by when its request was made, as the share is, so the
    cache-write alert names a card step by what it wrote in the 24 h, and shows the rest as written by no card step."""
    if rows is None:
        return None
    day, cards = [], {}
    for i, r in enumerate(rows):
        folder, session = places[i] if places else (None, None)
        card = card_of(folder)
        for x in cache_day([r], now):
            day.append(x)
            if card and x[3] + x[4] > 0:
                c = cards.setdefault((card, session, x[1]), {"card": card, "model": x[1], "first": x[0], "last": x[0], "write": 0, "write1h": 0})
                c.update(first=min(c["first"], x[0]), last=max(c["last"], x[0]), write=c["write"] + x[3], write1h=c["write1h"] + x[4])
    return {"write": sum(r[3] for r in day), "write1h": sum(r[4] for r in day),
            "cards": sorted(cards.values(), key=lambda c: (-(c["write"] + c["write1h"]), c["card"], c["first"]))}


def codex_sources(sessions):
    """The Codex session folders that build reads.

    Review panes run with CODEX_HOME=~/.codex-review; a test points CONVEYOR_CODEX_REVIEW_HOME at a temp folder so it
    never reads real spend. With no Codex folder at all, Codex spend stays not measured."""
    review = os.environ.get("CONVEYOR_CODEX_REVIEW_HOME") or os.path.expanduser("~/.codex-review")
    return [sessions, os.path.join(review, "sessions")] if sessions else []
