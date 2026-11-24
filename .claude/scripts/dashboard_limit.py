#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""The dashboard's 7-day limit panel, called by dashboard.sh.

  dashboard_limit.py fetch [<config-folder> [<cache-dir>]]
      Claude's own usage reading (the statusline's source) as JSON on stdout;
      exit 1 with no output when there is no login token or the read fails, and
      the cause as one stderr line (dashboard.sh shows it and honours its
      `retry after <n> s`). The reading is the account in use's (with a folder: that folder's account; the
      engine's guard names the account a project's cards use; an empty folder is the account in use) and carries it
      as `account`. With a cache folder the account's 429 deadline is the one `accounts` keeps for it: both honour it
      and both keep their reads there. Every reader on a machine (the Board, the engine's guard, the Foreman's
      watcher) passes the machine's one folder, ${XDG_CACHE_HOME:-~/.cache}/conveyor/accounts: a reader that kept its
      own, or none, asked again inside the wait another reader's 429 named, and the account stayed refused for days.
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
      Conveyor's cards with each finished session, review and test run priced at list price.
  dashboard_limit.py cardlines <cards-file> <kept> <priced-file>  < {prices, since, research}
      The same, for the cards of <cards-file>, one a line (conveyor.sh snapshot): the priced cards go to
      <priced-file>, one a line, and the rest of the part to stdout. <kept> is a summary of the cards priced last
      time: a card whose line has not changed since is not priced again (card_costs). <kept>.lanes keeps the
      research lane's transcripts read last time: one not changed since is not read again (lane_models).
  dashboard_limit.py work  < {steps: [...], live, prices}
      A benchmark trial's sessions priced the same way, as one figure that says whether it is whole (work_cost).
  dashboard_limit.py unpriced  < {prices, models: [...]}
      The model IDs of models that no price row prices, the pack's prices put over the table (unpriced), as a JSON list.

Every figure comes from that reading or from Claude Code's own transcripts; a
figure with no source is null, never 0 or an estimate. Dollars are list-price
equivalents of the transcripts' token counts: what the same
usage would cost on the pay-as-you-go API. The reading carries no
history, so each new sample is appended to <cache-dir>/limit-history.jsonl and
the chart draws from that file.
"""
import email.utils
import fcntl
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
RATE_LIMITED = "rate limited (429)"  # how usage() begins the reason of a 429: the one failure fetch() and note() wait out

# This script is one module in four files: each of PARTS runs in this module's namespace where run_part() names it
# below, as if its text stood there, so a name is one name wherever it is read (a name replaced on this module, as a
# test replaces token or open, is replaced for every part). card_costs keys the cards it priced by the text of all four.
_HERE = os.path.dirname(os.path.abspath(__file__))
PARTS = (os.path.join(_HERE, "dashboard_limit_usage.py"), os.path.join(_HERE, "dashboard_limit_pricing.py"),
         os.path.join(_HERE, "dashboard_limit_requests.py"))


def run_part(path):
    with open(path, encoding="utf-8") as f:
        exec(compile(f.read(), path, "exec"), globals())


run_part(PARTS[0])


# List prices in $ per million tokens: (input, output, cache read). Cache writes
# are 1.25x input for the 5-minute TTL and 2x for 1 hour. Source:
# https://platform.claude.com/docs/en/about-claude/pricing, read 2026-11-16.
# The ":fast" Claude rows are that page's "Fast mode pricing" table, read
# 2026-11-16; the cache multipliers stack on the fast input price. The gpt-*
# rows are Codex's models, from the Standard and Fast tables of
# https://developers.openai.com/api/docs/pricing, read 2026-11-19 (a cache
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
    "gpt-6.2-sol": (2.0, 10.0, 0.10),
    "gpt-6.2-sol:fast": (4.0, 20.0, 0.20),
    "gpt-6.2-astra": (8.0, 40.0, 0.40),
    "gpt-6.2-astra:fast": (16.0, 80.0, 0.80),
    "gpt-6.1-terra": (1.0, 5.0, 0.05),
    "gpt-6.1-terra:fast": (2.0, 10.0, 0.10),
    "gpt-6-sol": (2.0, 10.0, 0.20),
    "gpt-6-sol:fast": (4.0, 20.0, 0.40),
    "gpt-6-luna": (0.10, 0.50, 0.01),
    "gpt-6-luna:fast": (0.20, 1.00, 0.02),
    "gpt-5.6-sol": (4.0, 20.0, 0.40),
    "gpt-5.6-sol:fast": (8.0, 40.0, 0.80),
    "gpt-5.6-terra": (2.0, 12.0, 0.20),
    "gpt-5.6-terra:fast": (4.0, 24.0, 0.40),
    "gpt-5.6-luna": (0.20, 1.20, 0.02),
    "gpt-5.6-luna:fast": (0.40, 2.40, 0.04),
}
LONG_PRICES = {"claude-haiku-5-5": (0.50, 2.50, 0.05),
               "gpt-6.1-sol": (4.0, 15.0, 0.20), "gpt-6.1-sol:fast": (8.0, 30.0, 0.40),
               "gpt-6-astra": (20.0, 75.0, 2.00), "gpt-6-astra:fast": (40.0, 150.0, 4.00),
               "gpt-6.2-sol": (4.0, 15.0, 0.20), "gpt-6.2-sol:fast": (8.0, 30.0, 0.40),
               "gpt-6.2-astra": (16.0, 60.0, 0.80), "gpt-6.2-astra:fast": (32.0, 120.0, 1.60),
               "gpt-6.1-terra": (2.0, 7.50, 0.10), "gpt-6.1-terra:fast": (4.0, 15.0, 0.20),
               "gpt-6-sol": (4.0, 15.0, 0.40), "gpt-6-sol:fast": (8.0, 30.0, 0.80),
               "gpt-6-luna": (0.20, 0.75, 0.02), "gpt-6-luna:fast": (0.40, 1.50, 0.04),
               "gpt-5.6-sol": (8.0, 30.0, 0.80), "gpt-5.6-sol:fast": (16.0, 60.0, 1.60),
               "gpt-5.6-terra": (4.0, 18.0, 0.40), "gpt-5.6-terra:fast": (8.0, 36.0, 0.80),
               "gpt-5.6-luna": (0.40, 1.80, 0.04), "gpt-5.6-luna:fast": (0.80, 3.60, 0.08)}
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
# Another model ID that means a model, and that model (use_prices, canon): the built-in ones, then the pack's
# aliases. gpt-daybreak-blue-latest has no price of its own: OpenAI's model page names it a deprecated alias whose
# snapshot is gpt-5.6-sol.
ALIASES = {"gpt-daybreak-blue-latest": "gpt-5.6-sol"}
PRICE_KEYS = ("input", "output", "cacheRead")


run_part(PARTS[1])
run_part(PARTS[2])


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
    places, api_places = [], []
    loaded = requests(projects, os.path.join(cache_dir, "limit-requests.json"), since, now, places=places) if live else None
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
        "cacheWrites24h": cache_writes(loaded, now, places),
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
        api_rows = requests(projects, os.path.join(cache_dir, "limit-requests.json"), min(monday, now - 86400), now, places=api_places)
        out["api"] = api_week(limit, api_rows, now, codex_rows, bool(missed))
        # With no subscription reading nothing above loaded the requests, and cache writes still cost dollars here.
        if out["cacheWritePct24h"] is None:
            out["cacheWritePct24h"], out["cacheWrites24h"] = cache_write_pct(api_rows, now), cache_writes(api_rows, now, api_places)
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
        return fetch(argv[2] if len(argv) >= 3 and argv[2] else None, argv[3] if len(argv) == 4 else None)
    if len(argv) in (3, 4) and argv[1] == "accounts":
        json.dump(accounts(argv[2], time.time(), argv[3] if len(argv) == 4 else None), sys.stdout)
        return 0
    if argv[1:] == ["account"]:
        json.dump(active_folder(), sys.stdout)
        return 0
    if len(argv) == 2 and argv[1] == "cards":
        json.dump(card_costs(json.load(sys.stdin)), sys.stdout)
        return 0
    if len(argv) == 2 and argv[1] == "work":
        json.dump(work_cost(json.load(sys.stdin)), sys.stdout)
        return 0
    if len(argv) == 2 and argv[1] == "unpriced":
        json.dump(unpriced(json.load(sys.stdin)), sys.stdout)
        return 0
    if len(argv) == 5 and argv[1] == "cardlines":
        json.dump(card_costs(json.load(sys.stdin), *argv[2:5]), sys.stdout)
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
