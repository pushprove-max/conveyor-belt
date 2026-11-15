#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Board's own usage reads (dashboard_limit.py accounts and build), by function. Issue 440: every usage read was
# refused (429) for hours while the Board read the account in use twice each cycle (fetch, then accounts) and retried
# the accounts read every 5 min whatever wait the 429 named, and the figures it kept carried no time.
set -euo pipefail
SOURCE=$(git rev-parse --show-toplevel)
T=$(cd "$(mktemp -d /tmp/dashboard-limit-accounts-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
H=$T/home X=$T/profiles/two/home
mkdir -p "$H/.claude" "$H/.config/conveyor" "$X" "$T/cache"
printf '{"claudeAiOauth":{"accessToken":"tok-d"}}' > "$H/.claude/.credentials.json"
printf '{"claudeAiOauth":{"accessToken":"tok-2"}}' > "$X/.credentials.json"
printf '{"oauthAccount":{"emailAddress":"noreply-d@example.com"}}' > "$H/.claude.json"
printf '{"oauthAccount":{"emailAddress":"noreply-2@example.com"}}' > "$X/.claude.json"
jq -cn --arg x "$X" '{accounts: [{name: "two", configDir: $x}]}' > "$H/.config/conveyor/host.json"
env -u CONVEYOR_CLAUDE_PROFILES -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$H" CONVEYOR_HOST_OS=Linux \
  python3 - "$SOURCE/.claude/scripts" "$T" "$X" <<'EOF'
import io, json, os, sys, urllib.error
from email.message import Message
sys.path.insert(0, sys.argv[1])
import dashboard_limit as d
T, X = sys.argv[2], sys.argv[3]
asked, answer = [], {}

class R(io.BytesIO):
    __enter__ = lambda s: s
    __exit__ = lambda s, *a: None

def urlopen(req, timeout=None):
    who = req.headers["Authorization"]
    asked.append(who)
    if answer.get(who) == 429:
        m = Message(); m["Retry-After"] = "3600"
        raise urllib.error.HTTPError("u", 429, "x", m, None)
    return R(json.dumps({"seven_day": {"utilization": answer.get(who, 53)}}).encode()).__enter__()

d.urllib.request.urlopen = urlopen
fail = []
check = lambda ok, why: ok or fail.append(why)
row = lambda rows, folder: next(r for r in rows if r["folder"] == folder)

# fetch()'s reading of the account in use, as dashboard.sh keeps it, read at 09:00 (here: 6 h before now), and its
# last read refused.
now = 1_800_000_000
usage = os.path.join(T, "cache", "claude-usage")
with open(usage, "w") as f:
    json.dump({"seven_day": {"utilization": 53, "resets_at": d.iso(now + 259200)}, "account": {"folder": os.path.join(os.environ["HOME"], ".claude")}}, f)
os.utime(usage, (now - 21600, now - 21600))
with open(usage + ".retry", "w") as f:
    f.write("%d rate limited (429); retry after 3600 s\n" % (now + 3600))

# The account in use is shown from that reading and never asked for again: a second read of it each cycle was the Board's
# own share of the 429s. Its figures carry their time, 6 h back, and why they were not read again.
rows = d.accounts(os.path.join(T, "cache"), now, usage)
check("Bearer tok-d" not in asked, "accounts read the account in use a second time: %s" % asked)
me = row(rows, os.path.join(os.environ["HOME"], ".claude"))
check((me["usedPct"], me["readAt"], me["error"]) == (53, d.iso(now - 21600), "rate limited (429); retry after 3600 s"),
      "the account in use is not shown from the usage file with its time and reason: %s" % me)
check(asked == ["Bearer tok-2"], "the other account is not read once: %s" % asked)

# A 429 on the other account keeps its last figures and their time, and is not asked for again before the hour it named,
# though the 5 min TTL has passed. Bug caught: it was retried every 5 min, with no figures shown meanwhile.
answer["Bearer tok-2"] = 429
two = row(d.accounts(os.path.join(T, "cache"), now + 301, usage), X)
check((two["usedPct"], two["readAt"], two["error"]) == (53, d.iso(now), "rate limited (429); retry after 3600 s"),
      "a refused read did not keep the last figures and their time: %s" % two)
asked.clear()
d.accounts(os.path.join(T, "cache"), now + 301 + 1800, usage)
check(asked == [], "the account was asked for again inside the 429's hour: %s" % asked)
answer["Bearer tok-2"] = 40
two = row(d.accounts(os.path.join(T, "cache"), now + 301 + 3601, usage), X)
check(asked == ["Bearer tok-2"] and (two["usedPct"], two["error"]) == (40, None), "the account was not read again after the hour: %s %s" % (asked, two))

# build() says when its figures were read: the usage file's own time, so Health can show their age.
out = io.StringIO()
real, sys.stdout = sys.stdout, out
try:
    d.build("stale", usage, now, os.path.join(T, "cache"), os.path.join(T, "projects"), os.path.join(T, "codex"))
finally:
    sys.stdout = real
check(json.loads(out.getvalue())["readAt"] == d.iso(now - 21600), "build gives no readAt of the reading's own time: %s" % out.getvalue()[:200])

# Issue 447: an account's 429 deadline outlives a switch, whichever read was refused. fetch() (dashboard.sh's read of
# the account in use) and accounts() keep one deadline an account; dashboard.sh drops its own on a switch, so each
# path asked at once the account the other had been refused for.
HC, cache, t1 = os.path.join(os.environ["HOME"], ".claude"), os.path.join(T, "cache"), now + 10000
clock = [t1]
d.time.time = lambda: clock[0]
# X is a profile folder now, so fetch can read it as the account in use (config_folders()).
os.environ["CONVEYOR_CLAUDE_PROFILES"] = os.path.dirname(os.path.dirname(X))
def run_fetch(folder):
    err, real = io.StringIO(), sys.stderr
    sys.stdout, sys.stderr = io.StringIO(), err
    try:
        return d.fetch(folder, cache), err.getvalue().strip()
    finally:
        sys.stdout, sys.stderr = sys.__stdout__, real
def in_use(folder):
    os.utime(os.path.join(os.environ["HOME"], ".claude.json"), (1, 2 if folder == HC else 1))
    os.utime(os.path.join(X, ".claude.json"), (1, 2 if folder == X else 1))
answer["Bearer tok-d"] = answer["Bearer tok-2"] = 429
in_use(HC)
check(run_fetch(HC)[0] == 1, "the account in use's refused fetch did not fail")
d.accounts(cache, t1, usage)
asked.clear()
# Switched to X: dashboard.sh deleted the usage file and its deadline, then fetched X.
in_use(X)
os.remove(usage); os.remove(usage + ".retry")
clock[0] = t1 + 600
got = run_fetch(X)
check(asked == [] and got == (1, "rate limited (429); retry after 3000 s"),
      "fetch asked the account switched to inside the hour accounts() was refused for: %s %s" % (asked, got))
d.accounts(cache, t1 + 600, usage)
check(asked == [], "accounts asked the account switched from inside the hour fetch was refused for: %s" % asked)
clock[0] = t1 + 3601
answer["Bearer tok-2"] = 40
check(run_fetch(X)[0] == 0 and asked == ["Bearer tok-2"], "fetch did not read the account once its hour had passed: %s" % asked)

for f in fail:
    print("FAIL: " + f, file=sys.stderr)
sys.exit(1 if fail else 0)
EOF
echo "PASS: dashboard-limit-accounts"
