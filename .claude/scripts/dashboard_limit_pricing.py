# SPDX-License-Identifier: Apache-2.0
# A part of dashboard_limit.py, run in its namespace (run_part()), not a module of its own: the pack's prices put
# over the price table, a request's price, the cards' and a benchmark trial's costs, and the week's cost.


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
    and subagents' transcripts below it). Claude Code files a session under the folder it began in, and each line
    carries the folder it works in then (cwd): a session begun in the main checkout, or in any other folder, that
    works in the worktree later is filed under that folder, so every folder is read. A line counts only when its own
    cwd is the worktree or inside it; one that does not hold the worktree's path as JSON writes it is not parsed.
    "<synthetic>" is no model: Claude Code writes it on a message no model answered. A file that cannot be read
    counts nothing."""
    if not isinstance(projects, str) or not isinstance(worktree, str) or not worktree.startswith("/") or since is None:
        return {}
    wt = json.dumps(worktree.rstrip("/"), ensure_ascii=False)[1:-1].encode("utf-8", "replace")
    out = {}
    for root, _, files in os.walk(projects):
        for name in files:
            path = os.path.join(root, name)
            try:
                if not name.endswith(".jsonl") or os.stat(path).st_mtime < since:
                    continue
                with open(path, "rb") as f:
                    for line in f:
                        if b'"model"' not in line or wt not in line:
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


def known(m):
    """The price row a model ID is priced at (the ID, or it with no [1m] and no date at its end, through the pack's
    aliases), or None when the table has no row for it."""
    if not isinstance(m, str):
        return None
    for c in (m, re.sub(r"\[[^]]*\]$", "", m), re.sub(r"-\d{8}$", "", re.sub(r"\[[^]]*\]$", "", m))):
        if canon(c) in PRICES:
            return canon(c)
    return None


def unpriced(part):
    """Of the model IDs `models` names, those with no price row (known), after the part's `prices` (the pack's) are
    put over the table: what Needs you counts (noprice(), lib/control.sh). An OpenCode model keeps the cost OpenCode
    reports, so it is never one."""
    use_prices(part.get("prices") if isinstance(part.get("prices"), dict) else {})
    ms = list(part.get("models")) if isinstance(part.get("models"), list) else []
    return sorted({m for m in ms if isinstance(m, str) and m and not m.startswith("opencode:") and known(m) is None})


def card_costs(part, lines=None, kept=None, dest=None):
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
    they were before ({model: [input, output, cache read]}), `aliases`, the built-in aliases ({alias: model}), and `names`, the display name each model of the table or
    the pack has when the pack gives it none (display), for the Rules tab's Model prices. With `since` (a time as the steps' lines write it), it
    gets `seen` too: each model ID the steps of that time or later ran ({model, sessions: how many steps, routes: the
    routes their lines name (proxy, subscription), as: the model it is priced as, null when none prices it}), the most
    used first. The part's `research` ({worktree, projects}: the research lane's folder and Claude Code's projects
    folder), taken out of the part, adds the model IDs its sessions ran from that time on (lane_models), one session
    each: they are no card's step. An ID only they ran has lane: true, as the belt never runs it: the Board counts its
    sessions, and does not list it as a model with no price.
    """

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

    table, aliases = {m: list(p) for m, p in PRICES.items()}, dict(ALIASES)
    pack = part.pop("prices", None)
    use_prices(pack)
    part["table"], part["aliases"] = table, aliases
    part["names"] = {m: display(m) for m in [*table, *(pack if isinstance(pack, dict) else {})] if m}
    since, seen = part.pop("since", None), {}

    def priced(card):
        """The card priced, in place. Returns what seen counts of it: each step's [time, the models it ran, its route
        or None], of every time (count() keeps those of since or later)."""
        uses = []
        steps = [s for s in card.get("steps") or [] if isinstance(s, dict)]
        models = card.get("models") if isinstance(card.get("models"), dict) else {}
        for s in steps:
            if s.get("step") != "test" and isinstance(s.get("time"), str):
                xs = sorted({x for x in ((s.get("step") != "review" and ran(s)) or [s.get("model")]) if isinstance(x, str) and x})
                if xs:
                    uses.append([s["time"], xs, s["route"] if isinstance(s.get("route"), str) and s["route"] else None])
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
        return uses

    def count(uses):
        for t, xs, r in uses:
            if isinstance(since, str) and t >= since:
                for x in xs:
                    k, ways = seen.get(x, (0, set()))
                    seen[x] = (k + 1, ways | ({r} if r else set()))

    if lines is None:
        for card in part["cards"]:
            count(priced(card))
    else:
        # A card's line priced before, under the same prices and this same script (its own text and its parts',
        # PARTS), is taken from <kept> as it was priced: only the cards whose line is new or changed are read and
        # priced. The summary is a line `<key> <sha256 of the rest>`, then a line `<sha256 of the card's line>\t<the
        # card priced>\t<what seen counts of it>` for each card of the last call; any other summary is not used.
        code = b"".join(open(p, "rb").read() for p in (__file__, *PARTS))
        key = hashlib.sha256(json.dumps([pack, hashlib.sha256(code).hexdigest()], sort_keys=True).encode()).hexdigest()
        was = {}
        try:
            with open(kept, "rb") as f:
                head, body = f.readline().split(), f.read()
            if head == [key.encode(), hashlib.sha256(body).hexdigest().encode()]:
                for ln in body.decode("ascii").split("\n")[:-1]:
                    h, p, u = ln.split("\t")
                    was[h] = (p, json.loads(u))
        except (OSError, ValueError):
            was = {}
        now, out, had = {}, [], len(was)
        with open(lines, "rb") as f:
            for ln in f:
                ln = ln.rstrip(b"\n")
                if not ln:
                    continue
                h = hashlib.sha256(ln).hexdigest()
                if h not in was:
                    card = json.loads(ln)
                    uses = priced(card)
                    was[h] = (json.dumps(card, separators=(",", ":")), uses)
                now[h] = was[h]
                out.append(was[h][0])
                count(was[h][1])
        with open(dest, "w", encoding="utf-8") as f:
            f.write("".join(o + "\n" for o in out))
        # The summary is written again only when a card's line is new, changed or gone (or the summary was not used),
        # through a file of its own and one rename: a call beside this one never reads half of it.
        if not len(was) == had == len(now):
            body = "".join(f"{h}\t{p}\t{json.dumps(u, separators=(',', ':'))}\n" for h, (p, u) in now.items()).encode()
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
    research, steps = part.pop("research", None), set(seen)
    if isinstance(since, str) and isinstance(research, dict):
        for x, n in lane_models(research.get("projects"), research.get("worktree"), epoch(since)).items():
            k, ways = seen.get(x, (0, set()))
            seen[x] = (k + n, ways)
    if isinstance(since, str):
        part["seen"] = [{"model": x, "sessions": k, "routes": sorted(ways), "as": known(x), **({} if x in steps else {"lane": True})}
                        for x, (k, ways) in sorted(seen.items(), key=lambda t: (-t[1][0], t[0]))]
    return part


def work_cost(part):
    """A benchmark trial's work at list price (bench/swe.sh): part is {steps, live, prices}: the trial's sessions as
    its card's record lines hold them (a judge's session a step of its own), the record of the session running now
    (null when none) and the pack's prices. Each is priced as card_costs prices a card's step. A running session whose
    answers so far all report usage 0 (zero) has no usage to price yet: it is unpriced, never $0.

    Returns {usd, state, unpriced, basis}. state is "known" when every session is priced (no session at all is a
    known $0), "partial" when only some are (usd is the priced part, unpriced how many are not) and "unknown" when
    none is (usd null). basis is the rate each model priced was priced at ({input, output, cacheRead, cacheWrite}, $
    per million tokens; a cost OpenCode reported has none), so a later change of prices leaves what was kept as it was."""
    steps = [dict(s) for s in part.get("steps") or [] if isinstance(s, dict)]
    live = part.get("live")
    if isinstance(live, dict):
        steps.append({"step": live.get("step"), "model": live.get("model"), "usage": None if live.get("zero") is True else live.get("usage")})
    card_costs({"cards": [{"steps": steps}], "prices": part.get("prices")})
    got = [s["usd"] for s in steps if s.get("usd") is not None]
    n = len(steps) - len(got)
    basis = {m: dict(zip(PRICE_KEYS + ("cacheWrite",), list(PRICES[m][:3]) + [write_rate(PRICES[m])]))
             for s in steps for m in (s.get("pricedBy") or {}) if m in PRICES}
    return {"usd": round(sum(got), 4) if got or not n else None, "state": "known" if not n else "partial" if got else "unknown",
            "unpriced": n, "basis": basis}


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
